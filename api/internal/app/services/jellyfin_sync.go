package services

import (
	"context"
	"fmt"
	"slices"
	"time"

	"github.com/google/uuid"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories"
	"biinge-api/internal/config/cache"
	"biinge-api/internal/config/logger"
	"biinge-api/pkg/jellyfin"
	"biinge-api/pkg/tmdb"
)

// JellyfinChange is one Jellyfin played flip mapped to biinge (TmdbId is the movie or the episode's series, Season and Episode the episode's numbers, LastPlayed nil when Jellyfin holds no date)
type JellyfinChange struct {
	Kind       PlayedKind
	TmdbId     uint64
	Season     uint64
	Episode    uint64
	Played     bool
	LastPlayed *time.Time
}

// JellyfinSync applies a Jellyfin played change to the user's biinge library (nil when it applied or can never apply, an error when a retry may succeed) and reconciles Jellyfin with it
type JellyfinSync interface {
	Apply(ctx context.Context, userId uuid.UUID, change JellyfinChange) error
	Reconcile(ctx context.Context, read *JellyfinRead) error
}

type jellyfinSync struct {
	tmdb       tmdb.Client
	jellyfin   jellyfin.Client
	movies     Movies
	progress   Progress
	repository repositories.SeriesProgressRepository
	memory     PlayedMemory
	cache      cache.Cache
	log        *logger.Logger
}

func NewJellyfinSync(
	tmdbClient tmdb.Client,
	jellyfinClient jellyfin.Client,
	movies Movies,
	progress Progress,
	repository repositories.SeriesProgressRepository,
	memory PlayedMemory,
	store cache.Cache,
	log *logger.Logger,
) JellyfinSync {
	return &jellyfinSync{
		tmdb:       tmdbClient,
		jellyfin:   jellyfinClient,
		movies:     movies,
		progress:   progress,
		repository: repository,
		memory:     memory,
		cache:      store,
		log:        log.WithComponent("JellyfinSyncService"),
	}
}

func (j *jellyfinSync) Apply(ctx context.Context, userId uuid.UUID, change JellyfinChange) error {
	switch change.Kind {
	case PlayedMovie:
		return j.movie(ctx, userId, change)
	case PlayedEpisode:
		return j.episode(ctx, userId, change)
	default:
		return nil
	}
}

// Reconcile writes biinge's watched state to each read item of a tracked title whose played state differs (an error only when a biinge read fails, a failed Jellyfin write is logged and retried by the next reconcile)
func (j *jellyfinSync) Reconcile(ctx context.Context, read *JellyfinRead) error {
	userId := read.Key.UserId

	var movieIds []uint64

	// the episode items by series, then by season number
	series := map[uint64]map[uint64][]JellyfinItem{}

	for _, item := range read.Items {
		switch item.Kind {
		case PlayedMovie:
			movieIds = append(movieIds, item.TmdbId)
		case PlayedEpisode:
			if series[item.TmdbId] == nil {
				series[item.TmdbId] = map[uint64][]JellyfinItem{}
			}

			series[item.TmdbId][item.Season] = append(series[item.TmdbId][item.Season], item)
		default:
		}
	}

	var writes []jellyfin.PlayedState

	tracked := map[uint64]models.Movie{}

	// a read without movies needs no movie query
	if len(movieIds) > 0 {
		rows, err := j.movies.FindByFilter(ctx, models.MovieFilter{UserId: userId, TmdbIds: movieIds})
		if err != nil {
			return err
		}

		for _, row := range rows {
			tracked[row.TmdbId] = row
		}
	}

	for _, item := range read.Items {
		// an untracked movie is left alone
		movie, found := tracked[item.TmdbId]
		if item.Kind != PlayedMovie || !found {
			continue
		}

		played := movie.State == models.StateTypeWatched
		if item.Played == played {
			continue
		}

		state := jellyfin.PlayedState{ItemId: item.Id, Played: played}
		if played && !movie.WatchedAt.IsZero() {
			state.DatePlayed = &movie.WatchedAt
		}

		writes = append(writes, state)
	}

nextSeries:
	for tmdbId, seasons := range series {
		progress, err := j.progress.Get(ctx, userId, tmdbId)
		if err != nil {
			return err
		}

		// an untracked show is left alone
		if progress.State == models.StateTypeNone {
			continue
		}

		watched, err := j.repository.WatchedEpisodes(ctx, userId, tmdbId)
		if err != nil {
			j.log.Error().Err(err).Uint64("SeriesId", tmdbId).Msg("Failed to fetch the watched episodes")
			return errors.ErrFailedToFetchProgress
		}

		details, err := cache.Fetch(ctx, j.cache, j.log, fmt.Sprintf("tmdb:v3:tv:%d", tmdbId), cache.DetailsTTL, func() (*tmdb.TvDetails, error) {
			return j.tmdb.FetchTvDetails(ctx, tmdbId)
		})
		if err != nil {
			// the next reconcile retries a series TMDB failed to return
			j.log.Warn().Err(err).Uint64("SeriesId", tmdbId).Msg("Skipping the Jellyfin reconcile of the series; TMDB details unavailable")
			continue
		}

		for number, items := range seasons {
			// an explicit find, because season 0 holds the specials
			if !slices.ContainsFunc(details.Seasons, func(season tmdb.TvSeason) bool { return uint64(season.SeasonNumber) == number }) {
				j.log.Warn().Uint64("SeriesId", tmdbId).Uint64("Season", number).Msg("Skipping the Jellyfin reconcile of the season; TMDB lists no such season")
				continue
			}

			season, err := cache.Fetch(ctx, j.cache, j.log, fmt.Sprintf("tmdb:v1:tv:%d:season:%d", tmdbId, number), cache.DetailsTTL, func() (*tmdb.SeasonDetails, error) {
				return j.tmdb.FetchTvSeasonDetails(ctx, tmdbId, number)
			})

			switch {
			case errors.Is(err, tmdb.ErrNotFound):
				j.log.Warn().Uint64("SeriesId", tmdbId).Uint64("Season", number).Msg("Skipping the Jellyfin reconcile of the season; TMDB doesn't know it")
				continue
			case err != nil:
				j.log.Warn().Err(err).Uint64("SeriesId", tmdbId).Uint64("Season", number).Msg("Skipping the Jellyfin reconcile of the series; TMDB season details unavailable")
				continue nextSeries
			}

			for _, item := range items {
				found := slices.IndexFunc(season.Episodes, func(episode tmdb.Episode) bool { return uint64(episode.EpisodeNumber) == item.Episode })
				if found < 0 {
					j.log.Warn().Uint64("SeriesId", tmdbId).Uint64("Season", number).Uint64("Episode", item.Episode).Msg("Skipping the Jellyfin reconcile of the episode; TMDB lists no such episode")
					continue
				}

				watchedAt, played := watched[uint64(season.Episodes[found].ID)]
				if item.Played == played {
					continue
				}

				state := jellyfin.PlayedState{ItemId: item.Id, Played: played}
				if played && !watchedAt.IsZero() {
					state.DatePlayed = &watchedAt
				}

				writes = append(writes, state)
			}
		}
	}

	// written directly, not through the played-write queue, so none is dropped
	for _, state := range writes {
		if err := j.jellyfin.SetPlayed(ctx, read.Connection, state); err != nil {
			// the client already logged the failure, without the token, and the next reconcile retries it
			j.log.Warn().Err(err).Str("ItemId", state.ItemId).Msg("Failed to write the reconciled Jellyfin played state")
			continue
		}

		// the poll then reads the API's own write as no Jellyfin change
		j.memory.Record(read.Key, state.ItemId, state.Played)
	}

	return nil
}

// movie adds a played untracked movie, marks a want or watching one watched and returns an unplayed watched one to want
func (j *jellyfinSync) movie(ctx context.Context, userId uuid.UUID, change JellyfinChange) error {
	var watchedAt time.Time
	if change.LastPlayed != nil {
		watchedAt = *change.LastPlayed
	}

	rows, err := j.movies.FindByFilter(ctx, models.MovieFilter{UserId: userId, TmdbIds: []uint64{change.TmdbId}})
	if err != nil {
		return err
	}

	// an untracked movie is added only when played
	if len(rows) == 0 && !change.Played {
		return nil
	}

	if len(rows) == 0 {
		details, err := j.tmdb.FetchMovieDetails(ctx, change.TmdbId)

		switch {
		case errors.Is(err, tmdb.ErrNotFound):
			// a title TMDB doesn't know never resolves, so retrying it helps nothing
			j.log.Warn().Uint64("TmdbId", change.TmdbId).Msg("Skipping the Jellyfin played movie; TMDB doesn't know it")
			return nil
		case err != nil:
			j.log.Warn().Err(err).Uint64("TmdbId", change.TmdbId).Msg("Failed to fetch the TMDB details of the Jellyfin played movie")
			return errors.ErrFailedToFetchMovie
		}

		_, err = j.movies.Create(ctx, &models.Movie{
			UserId:     userId,
			TmdbId:     change.TmdbId,
			Title:      details.Title,
			PosterPath: details.PosterPath,
			Runtime:    uint64(max(details.Runtime, 0)),
			State:      models.StateTypeWatched,
			WatchedAt:  watchedAt,
		})

		return err
	}

	if (rows[0].State == models.StateTypeWatched) == change.Played {
		return nil
	}

	state := models.StateTypeWatched
	if !change.Played {
		state, watchedAt = models.StateTypeWant, time.Time{}
	}

	// pinned is passed back as read so the write leaves it alone
	_, err = j.movies.UpdateByTmdbId(ctx, &models.Movie{
		TmdbId:    change.TmdbId,
		UserId:    userId,
		State:     state,
		Pinned:    rows[0].Pinned,
		WatchedAt: watchedAt,
	})

	return err
}

// episode resolves the episode's TMDB ids by its numbers, then marks or unmarks it through the progress cascade
func (j *jellyfinSync) episode(ctx context.Context, userId uuid.UUID, change JellyfinChange) error {
	progress, err := j.progress.Get(ctx, userId, change.TmdbId)
	if err != nil {
		return err
	}

	// an unplayed episode of a show with nothing watched changes nothing, an untracked show included
	if !change.Played && len(progress.WatchedEpisodes) == 0 {
		return nil
	}

	details, err := cache.Fetch(ctx, j.cache, j.log, fmt.Sprintf("tmdb:v3:tv:%d", change.TmdbId), cache.DetailsTTL, func() (*tmdb.TvDetails, error) {
		return j.tmdb.FetchTvDetails(ctx, change.TmdbId)
	})
	if err != nil {
		if errors.Is(err, tmdb.ErrNotFound) {
			j.log.Warn().Uint64("SeriesId", change.TmdbId).Msg("Skipping the Jellyfin played episode; TMDB doesn't know the series")
			return nil
		}

		j.log.Warn().Err(err).Uint64("SeriesId", change.TmdbId).Msg("Failed to fetch the TMDB details of the Jellyfin played episode's series")

		return errors.ErrFailedToFetchSeries
	}

	// an explicit find, because season 0 holds the specials
	index := slices.IndexFunc(details.Seasons, func(season tmdb.TvSeason) bool { return uint64(season.SeasonNumber) == change.Season })
	if index < 0 {
		j.log.Warn().Uint64("SeriesId", change.TmdbId).Uint64("Season", change.Season).Msg("Skipping the Jellyfin played episode; TMDB lists no such season")
		return nil
	}

	season := details.Seasons[index]

	seasonDetails, err := cache.Fetch(ctx, j.cache, j.log, fmt.Sprintf("tmdb:v1:tv:%d:season:%d", change.TmdbId, change.Season), cache.DetailsTTL, func() (*tmdb.SeasonDetails, error) {
		return j.tmdb.FetchTvSeasonDetails(ctx, change.TmdbId, change.Season)
	})
	if err != nil {
		if errors.Is(err, tmdb.ErrNotFound) {
			j.log.Warn().Uint64("SeriesId", change.TmdbId).Uint64("Season", change.Season).Msg("Skipping the Jellyfin played episode; TMDB doesn't know the season")
			return nil
		}

		j.log.Warn().Err(err).Uint64("SeriesId", change.TmdbId).Uint64("Season", change.Season).Msg("Failed to fetch the TMDB season of the Jellyfin played episode")

		return errors.ErrFailedToFetchSeries
	}

	found := slices.IndexFunc(seasonDetails.Episodes, func(episode tmdb.Episode) bool { return uint64(episode.EpisodeNumber) == change.Episode })
	if found < 0 {
		j.log.Warn().Uint64("SeriesId", change.TmdbId).Uint64("Season", change.Season).Uint64("Episode", change.Episode).Msg("Skipping the Jellyfin played episode; TMDB lists no such episode")
		return nil
	}

	episode := seasonDetails.Episodes[found]
	episodeId := uint64(episode.ID)

	if slices.Contains(progress.WatchedEpisodes, episodeId) == change.Played {
		return nil
	}

	if !change.Played {
		_, err = j.progress.UnmarkEpisode(ctx, userId, change.TmdbId, season.Id, episodeId)
		return err
	}

	airAt, _ := tmdb.ParseDate(episode.AirDate)

	// the cascade adds an untracked show as watching and derives the season and show state
	_, err = j.progress.MarkEpisode(ctx, userId,
		models.SeriesInput{
			TmdbId:        change.TmdbId,
			Title:         details.Title,
			PosterPath:    details.PosterPath,
			SeasonsCount:  uint64(details.SeasonsCount),
			EpisodesCount: uint64(details.EpisodesCount),
			Status:        details.Status,
		},
		models.SeasonInput{
			TmdbId:        season.Id,
			Title:         season.Name,
			Number:        uint64(season.SeasonNumber),
			EpisodesCount: uint64(season.EpisodeCount),
		},
		models.EpisodeInput{
			TmdbId:     episodeId,
			Title:      episode.Name,
			PosterPath: episode.StillPath,
			Runtime:    uint64(max(episode.Runtime, 0)),
			AirAt:      airAt,
		},
	)

	return err
}
