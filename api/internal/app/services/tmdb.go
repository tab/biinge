package services

import (
	"context"
	"fmt"
	"sort"
	"sync"
	"time"

	"github.com/google/uuid"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/models"
	"biinge-api/internal/app/serializers"
	"biinge-api/internal/config/cache"
	"biinge-api/internal/config/logger"
	"biinge-api/pkg/tmdb"
)

type TmdbProvider interface {
	FetchMovieDetails(ctx context.Context, id uint64, userId uuid.UUID) (*serializers.MovieDetailsSerializer, error)
	FetchTvDetails(ctx context.Context, id uint64, userId uuid.UUID) (*serializers.SeriesDetailsSerializer, error)
	FetchTvSeasonDetails(ctx context.Context, showId, seasonNumber uint64, userId uuid.UUID) (*serializers.SeasonDetailsSerializer, error)
	FetchTvEpisodeDetails(ctx context.Context, showId, seasonNumber, episodeNumber uint64, userId uuid.UUID) (*serializers.EpisodeDetailsSerializer, error)
	FetchPersonDetails(ctx context.Context, id uint64, userId uuid.UUID) (*serializers.PersonDetailsSerializer, error)

	SearchMovies(ctx context.Context, query string, page uint64, userId uuid.UUID) (*serializers.PaginationResponse[serializers.SearchMovieSerializer], error)
	SearchSeries(ctx context.Context, query string, page uint64, userId uuid.UUID) (*serializers.PaginationResponse[serializers.SearchSeriesSerializer], error)
	SearchPeople(ctx context.Context, query string, page uint64) (*serializers.PaginationResponse[serializers.SearchPersonSerializer], error)
	FetchTrendingMovies(ctx context.Context, userId uuid.UUID) (*serializers.PaginationResponse[serializers.SearchMovieSerializer], error)
	FetchTrendingSeries(ctx context.Context, userId uuid.UUID) (*serializers.PaginationResponse[serializers.SearchSeriesSerializer], error)
	FetchTrendingPeople(ctx context.Context) (*serializers.PaginationResponse[serializers.SearchPersonSerializer], error)

	FetchUpNext(ctx context.Context, userId uuid.UUID) (*serializers.UpNextSerializer, error)
}

type tmdbProvider struct {
	client   tmdb.Client
	movies   Movies
	series   Series
	progress Progress
	cache    cache.Cache
	log      *logger.Logger
}

func NewTmdbProvider(
	client tmdb.Client,
	movies Movies,
	series Series,
	progress Progress,
	store cache.Cache,
	log *logger.Logger,
) TmdbProvider {
	return &tmdbProvider{
		client:   client,
		movies:   movies,
		series:   series,
		progress: progress,
		cache:    store,
		log:      log.WithComponent("TmdbProvider"),
	}
}

// toIdSet builds a lookup set from a slice of TMDB ids
func toIdSet(ids []uint64) map[uint64]struct{} {
	set := make(map[uint64]struct{}, len(ids))
	for _, id := range ids {
		set[id] = struct{}{}
	}

	return set
}

func (p *tmdbProvider) FetchMovieDetails(ctx context.Context, id uint64, userId uuid.UUID) (*serializers.MovieDetailsSerializer, error) {
	p.log.Debug().Uint64("Id", id).Msg("Fetching movie details")

	response, err := cache.Fetch(ctx, p.cache, p.log, fmt.Sprintf("tmdb:v1:movie:%d", id), cache.DetailsTTL, func() (*tmdb.MovieDetails, error) {
		return p.client.FetchMovieDetails(ctx, id)
	})
	if err != nil {
		p.log.Error().
			Err(err).
			Uint64("Id", id).
			Msg("Failed to fetch movie details")

		return p.fallbackMovieDetails(ctx, id, userId)
	}

	details := tmdb.TransformMovieDetails(response)

	p.log.Debug().
		Uint64("Id", id).
		Msg("Successfully fetched and transformed movie details")

	recommendationIds := make([]uint64, 0, len(details.Recommendations))
	for _, item := range details.Recommendations {
		recommendationIds = append(recommendationIds, item.Id)
	}

	moviesList, err := p.movies.FindMoviesByTmdbIds(ctx, recommendationIds, userId)
	if err != nil {
		p.log.Error().
			Err(err).
			Msg("Failed to fetch recommendation states")

		return nil, errors.ErrFailedToFetchResults
	}

	recommendationStatesMap := make(map[uint64]string)
	for _, movie := range moviesList {
		recommendationStatesMap[movie.TmdbId] = movie.State
	}

	recommendations := make([]serializers.RecommendationSerializer, 0, len(details.Recommendations))
	for _, item := range details.Recommendations {
		state := models.StateTypeNone
		if movieState, exists := recommendationStatesMap[item.Id]; exists {
			state = movieState
		}

		recommendations = append(recommendations, serializers.RecommendationSerializer{
			Id:         item.Id,
			Title:      item.Title,
			PosterPath: item.PosterPath,
			State:      state,
		})
	}

	credits := make([]serializers.PersonSerializer, 0, len(details.Credits))
	for _, item := range details.Credits {
		credits = append(credits, serializers.PersonSerializer{
			Id:          item.Id,
			Name:        item.Name,
			Description: item.Description,
			ProfilePath: item.ProfilePath,
		})
	}

	videos := make([]serializers.VideoSerializer, 0, len(details.Videos))
	for _, item := range details.Videos {
		videos = append(videos, serializers.VideoSerializer{
			Id:  item.Id,
			Key: item.Key,
		})
	}

	movie, err := p.movies.FindByTmdbId(ctx, id, userId)
	if err != nil {
		if errors.Is(err, errors.ErrMovieNotFound) {
			p.log.Debug().
				Err(err).
				Uint64("Id", id).
				Msg("Movie not found in database")

			return &serializers.MovieDetailsSerializer{
				Id:              id,
				Pinned:          false,
				State:           models.StateTypeNone,
				Status:          details.Status,
				Title:           details.Title,
				PosterPath:      details.PosterPath,
				Overview:        details.Overview,
				ReleaseDate:     details.ReleaseDate,
				Runtime:         details.Runtime,
				Rating:          details.Rating,
				Credits:         credits,
				Recommendations: recommendations,
				Videos:          videos,
			}, nil
		}

		p.log.Error().
			Err(err).
			Uint64("Id", id).
			Msg("Failed to fetch movie state")

		return nil, errors.ErrFailedToFetchMovie
	}

	// Read-repair: refresh a stale add-time poster/title from TMDB, leaving state and pinned untouched
	if details.PosterPath != "" && details.PosterPath != movie.PosterPath {
		runtime := uint64(details.Runtime)
		if runtime == 0 {
			runtime = movie.Runtime
		}

		title := details.Title
		if title == "" {
			title = movie.Title
		}

		if _, updateErr := p.movies.Update(ctx, &models.Movie{
			ID:         movie.ID,
			Title:      title,
			PosterPath: details.PosterPath,
			Runtime:    runtime,
		}); updateErr != nil {
			p.log.Warn().Err(updateErr).Uint64("Id", id).Msg("Failed to refresh stored movie poster")
		}
	}

	return &serializers.MovieDetailsSerializer{
		Id:              id,
		Pinned:          movie.Pinned,
		State:           movie.State,
		Status:          details.Status,
		Title:           details.Title,
		PosterPath:      details.PosterPath,
		Overview:        details.Overview,
		ReleaseDate:     details.ReleaseDate,
		Runtime:         details.Runtime,
		Rating:          details.Rating,
		Credits:         credits,
		Recommendations: recommendations,
		Videos:          videos,
	}, nil
}

// fallbackMovieDetails serves stored library data when TMDB is unavailable, else a fetch error
func (p *tmdbProvider) fallbackMovieDetails(ctx context.Context, id uint64, userId uuid.UUID) (*serializers.MovieDetailsSerializer, error) {
	movie, err := p.movies.FindByTmdbId(ctx, id, userId)
	if err != nil {
		return nil, tmdb.ErrFailedToFetchMovieDetails
	}

	p.log.Warn().Uint64("Id", id).Msg("Serving stored movie details while TMDB is unavailable")

	return &serializers.MovieDetailsSerializer{
		Id:              id,
		Pinned:          movie.Pinned,
		State:           movie.State,
		Title:           movie.Title,
		PosterPath:      movie.PosterPath,
		Runtime:         int(movie.Runtime),
		Credits:         make([]serializers.PersonSerializer, 0),
		Recommendations: make([]serializers.RecommendationSerializer, 0),
		Videos:          make([]serializers.VideoSerializer, 0),
	}, nil
}

func (p *tmdbProvider) FetchTvDetails(ctx context.Context, id uint64, userId uuid.UUID) (*serializers.SeriesDetailsSerializer, error) {
	p.log.Debug().Uint64("Id", id).Msg("Fetching tv details")

	response, err := cache.Fetch(ctx, p.cache, p.log, fmt.Sprintf("tmdb:v1:tv:%d", id), cache.DetailsTTL, func() (*tmdb.TvDetails, error) {
		return p.client.FetchTvDetails(ctx, id)
	})
	if err != nil {
		p.log.Error().
			Err(err).
			Uint64("Id", id).
			Msg("Failed to fetch tv details")

		return p.fallbackTvDetails(ctx, id, userId)
	}

	details := tmdb.TransformTvDetails(response)

	p.log.Debug().
		Uint64("Id", id).
		Msg("Successfully fetched and transformed tv details")

	recommendationIds := make([]uint64, 0, len(details.Recommendations))
	for _, item := range details.Recommendations {
		recommendationIds = append(recommendationIds, item.Id)
	}

	tvShowsList, err := p.series.FindSeriesByTmdbIds(ctx, recommendationIds, userId)
	if err != nil {
		p.log.Error().
			Err(err).
			Msg("Failed to fetch recommendation states")

		return nil, errors.ErrFailedToFetchResults
	}

	recommendationStatesMap := make(map[uint64]string)
	for _, tvShow := range tvShowsList {
		recommendationStatesMap[tvShow.TmdbId] = tvShow.State
	}

	recommendations := make([]serializers.RecommendationSerializer, 0, len(details.Recommendations))
	for _, item := range details.Recommendations {
		state := models.StateTypeNone
		if tvShowState, exists := recommendationStatesMap[item.Id]; exists {
			state = tvShowState
		}

		recommendations = append(recommendations, serializers.RecommendationSerializer{
			Id:         item.Id,
			Title:      item.Title,
			PosterPath: item.PosterPath,
			State:      state,
		})
	}

	credits := make([]serializers.PersonSerializer, 0, len(details.Credits))
	for _, item := range details.Credits {
		credits = append(credits, serializers.PersonSerializer{
			Id:          item.Id,
			Name:        item.Name,
			Description: item.Description,
			ProfilePath: item.ProfilePath,
		})
	}

	videos := make([]serializers.VideoSerializer, 0, len(details.Videos))
	for _, item := range details.Videos {
		videos = append(videos, serializers.VideoSerializer{
			Id:  item.Id,
			Key: item.Key,
		})
	}

	seasons := make([]serializers.SeasonSummarySerializer, 0, len(details.Seasons))
	for _, item := range details.Seasons {
		seasons = append(seasons, serializers.SeasonSummarySerializer{
			Id:            item.Id,
			Title:         item.Title,
			Number:        item.Number,
			PosterPath:    item.PosterPath,
			EpisodesCount: item.EpisodesCount,
			AirDate:       item.AirDate,
		})
	}

	tvShow, err := p.series.FindByTmdbId(ctx, id, userId)
	if err != nil {
		if errors.Is(err, errors.ErrSeriesNotFound) {
			p.log.Debug().
				Err(err).
				Uint64("Id", id).
				Msg("Series not found in database")

			return &serializers.SeriesDetailsSerializer{
				Id:              id,
				Pinned:          false,
				State:           models.StateTypeNone,
				Status:          details.Status,
				Title:           details.Title,
				PosterPath:      details.PosterPath,
				Overview:        details.Overview,
				ReleaseDate:     details.ReleaseDate,
				SeasonsCount:    uint64(max(details.SeasonsCount, 0)),
				EpisodesCount:   uint64(max(details.EpisodesCount, 0)),
				Rating:          details.Rating,
				Credits:         credits,
				Recommendations: recommendations,
				Videos:          videos,
				Seasons:         seasons,
			}, nil
		}

		p.log.Error().
			Err(err).
			Uint64("Id", id).
			Msg("Failed to fetch series state")

		return nil, errors.ErrFailedToFetchSeries
	}

	// Read-repair the stored poster/title/status (see FetchMovieDetails), leaving counts, state and pinned untouched
	if details.PosterPath != "" && details.PosterPath != tvShow.PosterPath {
		title := details.Title
		if title == "" {
			title = tvShow.Title
		}

		status := details.Status
		if status == "" {
			status = tvShow.Status
		}

		if _, updateErr := p.series.Update(ctx, &models.Series{
			ID:            tvShow.ID,
			Title:         title,
			PosterPath:    details.PosterPath,
			SeasonsCount:  tvShow.SeasonsCount,
			EpisodesCount: tvShow.EpisodesCount,
			Status:        status,
		}); updateErr != nil {
			p.log.Warn().Err(updateErr).Uint64("Id", id).Msg("Failed to refresh stored series poster")
		}
	}

	return &serializers.SeriesDetailsSerializer{
		Id:              id,
		Pinned:          tvShow.Pinned,
		State:           tvShow.State,
		Status:          details.Status,
		Title:           details.Title,
		PosterPath:      details.PosterPath,
		Overview:        details.Overview,
		ReleaseDate:     details.ReleaseDate,
		SeasonsCount:    uint64(max(details.SeasonsCount, 0)),
		EpisodesCount:   uint64(max(details.EpisodesCount, 0)),
		Rating:          details.Rating,
		Credits:         credits,
		Recommendations: recommendations,
		Videos:          videos,
		Seasons:         seasons,
	}, nil
}

// fallbackTvDetails serves stored library data when TMDB is unavailable, else a fetch error
func (p *tmdbProvider) fallbackTvDetails(ctx context.Context, id uint64, userId uuid.UUID) (*serializers.SeriesDetailsSerializer, error) {
	tvShow, err := p.series.FindByTmdbId(ctx, id, userId)
	if err != nil {
		return nil, tmdb.ErrFailedToFetchTvDetails
	}

	p.log.Warn().Uint64("Id", id).Msg("Serving stored series details while TMDB is unavailable")

	return &serializers.SeriesDetailsSerializer{
		Id:              id,
		Pinned:          tvShow.Pinned,
		State:           tvShow.State,
		Status:          tvShow.Status,
		Title:           tvShow.Title,
		PosterPath:      tvShow.PosterPath,
		SeasonsCount:    tvShow.SeasonsCount,
		EpisodesCount:   tvShow.EpisodesCount,
		Credits:         make([]serializers.PersonSerializer, 0),
		Recommendations: make([]serializers.RecommendationSerializer, 0),
		Videos:          make([]serializers.VideoSerializer, 0),
		Seasons:         make([]serializers.SeasonSummarySerializer, 0),
	}, nil
}

func (p *tmdbProvider) FetchPersonDetails(ctx context.Context, id uint64, userId uuid.UUID) (*serializers.PersonDetailsSerializer, error) {
	p.log.Debug().Uint64("Id", id).Msg("Fetching person details")

	response, err := cache.Fetch(ctx, p.cache, p.log, fmt.Sprintf("tmdb:v1:person:%d", id), cache.DetailsTTL, func() (*tmdb.PersonDetails, error) {
		return p.client.FetchPersonDetails(ctx, id)
	})
	if err != nil {
		p.log.Error().
			Err(err).
			Uint64("Id", id).
			Msg("Failed to fetch person details")

		return nil, tmdb.ErrFailedToFetchPersonDetails
	}

	details := tmdb.TransformPersonDetails(response)

	p.log.Debug().
		Uint64("Id", id).
		Msg("Successfully fetched and transformed person details")

	movieCreditIds := make([]uint64, 0, len(details.MovieCredits))
	for _, item := range details.MovieCredits {
		movieCreditIds = append(movieCreditIds, item.Id)
	}

	moviesList, err := p.movies.FindMoviesByTmdbIds(ctx, movieCreditIds, userId)
	if err != nil {
		p.log.Error().
			Err(err).
			Msg("Failed to fetch credit states")

		return nil, errors.ErrFailedToFetchResults
	}

	movieCreditStatesMap := make(map[uint64]string)
	for _, movie := range moviesList {
		movieCreditStatesMap[movie.TmdbId] = movie.State
	}

	movieCredits := make([]serializers.MovieCreditSerializer, 0, len(details.MovieCredits))
	for _, item := range details.MovieCredits {
		state := models.StateTypeNone
		if movieState, exists := movieCreditStatesMap[item.Id]; exists {
			state = movieState
		}

		movieCredits = append(movieCredits, serializers.MovieCreditSerializer{
			Id:         item.Id,
			Title:      item.Title,
			PosterPath: item.PosterPath,
			State:      state,
			Type:       item.Type,
		})
	}

	tvCreditIds := make([]uint64, 0, len(details.TvCredits))
	for _, item := range details.TvCredits {
		tvCreditIds = append(tvCreditIds, uint64(item.Id))
	}

	seriesList, err := p.series.FindSeriesByTmdbIds(ctx, tvCreditIds, userId)
	if err != nil {
		p.log.Error().
			Err(err).
			Msg("Failed to fetch tv credit states")

		return nil, errors.ErrFailedToFetchResults
	}

	tvCreditStatesMap := make(map[uint64]string)
	for _, tvShow := range seriesList {
		tvCreditStatesMap[tvShow.TmdbId] = tvShow.State
	}

	tvCredits := make([]serializers.TvCreditSerializer, 0, len(details.TvCredits))
	for _, item := range details.TvCredits {
		state := models.StateTypeNone
		if tvShowState, exists := tvCreditStatesMap[uint64(item.Id)]; exists {
			state = tvShowState
		}

		tvCredits = append(tvCredits, serializers.TvCreditSerializer{
			Id:            uint64(item.Id),
			Title:         item.Title,
			PosterPath:    item.PosterPath,
			State:         state,
			EpisodesCount: item.EpisodesCount,
		})
	}

	return &serializers.PersonDetailsSerializer{
		Id:           id,
		Name:         details.Name,
		Birthday:     details.Birthday,
		ProfilePath:  details.ProfilePath,
		Gender:       details.Gender,
		MovieCredits: movieCredits,
		TvCredits:    tvCredits,
	}, nil
}

func (p *tmdbProvider) FetchTvSeasonDetails(ctx context.Context, showId, seasonNumber uint64, userId uuid.UUID) (*serializers.SeasonDetailsSerializer, error) {
	p.log.Debug().Uint64("ShowId", showId).Uint64("SeasonNumber", seasonNumber).Msg("Fetching tv season details")

	response, err := cache.Fetch(ctx, p.cache, p.log, fmt.Sprintf("tmdb:v1:tv:%d:season:%d", showId, seasonNumber), cache.DetailsTTL, func() (*tmdb.SeasonDetails, error) {
		return p.client.FetchTvSeasonDetails(ctx, showId, seasonNumber)
	})
	if err != nil {
		p.log.Error().Err(err).Uint64("ShowId", showId).Uint64("SeasonNumber", seasonNumber).Msg("Failed to fetch tv season details")
		return nil, tmdb.ErrFailedToFetchSeasonDetails
	}

	progress, err := p.progress.Get(ctx, userId, showId)
	if err != nil {
		p.log.Error().Err(err).Uint64("ShowId", showId).Msg("Failed to fetch watched state for season details")
		return nil, tmdb.ErrFailedToFetchSeasonDetails
	}

	watchedSeasons := toIdSet(progress.WatchedSeasons)
	watchedEpisodes := toIdSet(progress.WatchedEpisodes)

	details := tmdb.TransformSeasonDetails(response)

	episodes := make([]serializers.SeasonEpisodeSerializer, 0, len(details.Episodes))
	for _, item := range details.Episodes {
		_, watched := watchedEpisodes[item.Id]
		episodes = append(episodes, serializers.SeasonEpisodeSerializer{
			Id:         item.Id,
			Title:      item.Title,
			Number:     item.Number,
			PosterPath: item.PosterPath,
			Runtime:    item.Runtime,
			Overview:   item.Overview,
			Rating:     item.Rating,
			AirDate:    item.AirDate,
			Watched:    watched,
		})
	}

	_, seasonWatched := watchedSeasons[details.Id]

	return &serializers.SeasonDetailsSerializer{
		Id:         details.Id,
		TmdbShowId: showId,
		Title:      details.Title,
		Number:     details.Number,
		PosterPath: details.PosterPath,
		AirDate:    details.AirDate,
		Overview:   details.Overview,
		Watched:    seasonWatched,
		Episodes:   episodes,
	}, nil
}

func (p *tmdbProvider) FetchTvEpisodeDetails(ctx context.Context, showId, seasonNumber, episodeNumber uint64, userId uuid.UUID) (*serializers.EpisodeDetailsSerializer, error) {
	p.log.Debug().
		Uint64("ShowId", showId).
		Uint64("SeasonNumber", seasonNumber).
		Uint64("EpisodeNumber", episodeNumber).
		Msg("Fetching tv episode details")

	response, err := cache.Fetch(ctx, p.cache, p.log, fmt.Sprintf("tmdb:v1:tv:%d:season:%d:episode:%d", showId, seasonNumber, episodeNumber), cache.DetailsTTL, func() (*tmdb.EpisodeDetails, error) {
		return p.client.FetchTvEpisodeDetails(ctx, showId, seasonNumber, episodeNumber)
	})
	if err != nil {
		p.log.Error().
			Err(err).
			Uint64("ShowId", showId).
			Uint64("SeasonNumber", seasonNumber).
			Uint64("EpisodeNumber", episodeNumber).
			Msg("Failed to fetch tv episode details")

		return nil, tmdb.ErrFailedToFetchEpisodeDetails
	}

	progress, err := p.progress.Get(ctx, userId, showId)
	if err != nil {
		p.log.Error().Err(err).Uint64("ShowId", showId).Msg("Failed to fetch watched state for episode details")
		return nil, tmdb.ErrFailedToFetchEpisodeDetails
	}

	details := tmdb.TransformEpisodeDetails(response)

	_, watched := toIdSet(progress.WatchedEpisodes)[details.Id]

	credits := make([]serializers.PersonSerializer, 0, len(details.Credits))
	for _, item := range details.Credits {
		credits = append(credits, serializers.PersonSerializer{
			Id:          item.Id,
			Name:        item.Name,
			Description: item.Description,
			ProfilePath: item.ProfilePath,
		})
	}

	videos := make([]serializers.VideoSerializer, 0, len(details.Videos))
	for _, item := range details.Videos {
		videos = append(videos, serializers.VideoSerializer{
			Id:  item.Id,
			Key: item.Key,
		})
	}

	return &serializers.EpisodeDetailsSerializer{
		Id:         details.Id,
		Title:      details.Title,
		Number:     details.Number,
		PosterPath: details.PosterPath,
		Runtime:    details.Runtime,
		Overview:   details.Overview,
		Rating:     details.Rating,
		AirDate:    details.AirDate,
		Watched:    watched,
		Credits:    credits,
		Videos:     videos,
	}, nil
}

func (p *tmdbProvider) SearchMovies(ctx context.Context, query string, page uint64, userId uuid.UUID) (*serializers.PaginationResponse[serializers.SearchMovieSerializer], error) {
	response, err := cache.Fetch(ctx, p.cache, p.log, fmt.Sprintf("tmdb:v1:search:movies:%d:%s", page, query), cache.SearchTTL, func() (*tmdb.MovieListResult, error) {
		return p.client.SearchMovies(ctx, query, page)
	})
	if err != nil {
		p.log.Error().Err(err).Str("query", query).Msg("Failed to search movies")
		return nil, errors.ErrFailedToFetchResults
	}

	return p.buildMovieList(ctx, response, userId)
}

func (p *tmdbProvider) FetchTrendingMovies(ctx context.Context, userId uuid.UUID) (*serializers.PaginationResponse[serializers.SearchMovieSerializer], error) {
	response, err := cache.Fetch(ctx, p.cache, p.log, "tmdb:v1:trending:movies", cache.TrendingTTL, func() (*tmdb.MovieListResult, error) {
		return p.client.FetchTrendingMovies(ctx)
	})
	if err != nil {
		p.log.Error().Err(err).Msg("Failed to fetch trending movies")
		return nil, errors.ErrFailedToFetchResults
	}

	return p.buildMovieList(ctx, response, userId)
}

func (p *tmdbProvider) SearchSeries(ctx context.Context, query string, page uint64, userId uuid.UUID) (*serializers.PaginationResponse[serializers.SearchSeriesSerializer], error) {
	response, err := cache.Fetch(ctx, p.cache, p.log, fmt.Sprintf("tmdb:v1:search:tv:%d:%s", page, query), cache.SearchTTL, func() (*tmdb.TvListResult, error) {
		return p.client.SearchTv(ctx, query, page)
	})
	if err != nil {
		p.log.Error().Err(err).Str("query", query).Msg("Failed to search series")
		return nil, errors.ErrFailedToFetchResults
	}

	return p.buildSeriesList(ctx, response, userId)
}

func (p *tmdbProvider) FetchTrendingSeries(ctx context.Context, userId uuid.UUID) (*serializers.PaginationResponse[serializers.SearchSeriesSerializer], error) {
	response, err := cache.Fetch(ctx, p.cache, p.log, "tmdb:v1:trending:tv", cache.TrendingTTL, func() (*tmdb.TvListResult, error) {
		return p.client.FetchTrendingTv(ctx)
	})
	if err != nil {
		p.log.Error().Err(err).Msg("Failed to fetch trending series")
		return nil, errors.ErrFailedToFetchResults
	}

	return p.buildSeriesList(ctx, response, userId)
}

func (p *tmdbProvider) SearchPeople(ctx context.Context, query string, page uint64) (*serializers.PaginationResponse[serializers.SearchPersonSerializer], error) {
	response, err := cache.Fetch(ctx, p.cache, p.log, fmt.Sprintf("tmdb:v1:search:people:%d:%s", page, query), cache.SearchTTL, func() (*tmdb.PersonListResult, error) {
		return p.client.SearchPeople(ctx, query, page)
	})
	if err != nil {
		p.log.Error().Err(err).Str("query", query).Msg("Failed to search people")
		return nil, errors.ErrFailedToFetchResults
	}

	// User-initiated search: only drop poster-less and flagged-adult results
	return buildPeopleList(response, 0), nil
}

func (p *tmdbProvider) FetchTrendingPeople(ctx context.Context) (*serializers.PaginationResponse[serializers.SearchPersonSerializer], error) {
	response, err := cache.Fetch(ctx, p.cache, p.log, "tmdb:v1:trending:people", cache.TrendingTTL, func() (*tmdb.PersonListResult, error) {
		return p.client.FetchTrendingPeople(ctx)
	})
	if err != nil {
		p.log.Error().Err(err).Msg("Failed to fetch trending people")
		return nil, errors.ErrFailedToFetchResults
	}

	// Discovery list: also require a notable credit to weed out unknown performers
	return buildPeopleList(response, minNotableVoteCount), nil
}

// minNotableVoteCount is the vote-count floor a person's best-known title must clear for the discovery list
const minNotableVoteCount = 100

// buildMovieList filters adult and poster-less results, merges tracking state, and paginates
func (p *tmdbProvider) buildMovieList(ctx context.Context, response *tmdb.MovieListResult, userId uuid.UUID) (*serializers.PaginationResponse[serializers.SearchMovieSerializer], error) {
	ids := make([]uint64, 0, len(response.Results))
	for _, item := range response.Results {
		ids = append(ids, item.Id)
	}

	moviesList, err := p.movies.FindMoviesByTmdbIds(ctx, ids, userId)
	if err != nil {
		p.log.Error().Err(err).Msg("Failed to fetch movie states")
		return nil, errors.ErrFailedToFetchResults
	}

	stateMap := make(map[uint64]string)
	for _, movie := range moviesList {
		stateMap[movie.TmdbId] = movie.State
	}

	data := make([]serializers.SearchMovieSerializer, 0, len(response.Results))
	for _, item := range response.Results {
		if item.PosterPath == "" || item.Adult {
			continue
		}

		state := models.StateTypeNone
		if value, ok := stateMap[item.Id]; ok {
			state = value
		}

		data = append(data, serializers.SearchMovieSerializer{
			Id:          item.Id,
			Title:       item.Title,
			PosterPath:  item.PosterPath,
			ReleaseDate: item.ReleaseDate,
			Rating:      item.VoteAverage,
			State:       state,
		})
	}

	return &serializers.PaginationResponse[serializers.SearchMovieSerializer]{
		Data: data,
		Meta: serializers.PaginationMeta{
			Page:  uint64(response.Page),
			Per:   uint64(len(data)),
			Total: uint64(response.TotalResults),
		},
	}, nil
}

// buildSeriesList mirrors buildMovieList for TV results (TMDB uses "name")
func (p *tmdbProvider) buildSeriesList(ctx context.Context, response *tmdb.TvListResult, userId uuid.UUID) (*serializers.PaginationResponse[serializers.SearchSeriesSerializer], error) {
	ids := make([]uint64, 0, len(response.Results))
	for _, item := range response.Results {
		ids = append(ids, item.Id)
	}

	seriesList, err := p.series.FindSeriesByTmdbIds(ctx, ids, userId)
	if err != nil {
		p.log.Error().Err(err).Msg("Failed to fetch series states")
		return nil, errors.ErrFailedToFetchResults
	}

	stateMap := make(map[uint64]string)
	for _, series := range seriesList {
		stateMap[series.TmdbId] = series.State
	}

	data := make([]serializers.SearchSeriesSerializer, 0, len(response.Results))
	for _, item := range response.Results {
		if item.PosterPath == "" || item.Adult {
			continue
		}

		state := models.StateTypeNone
		if value, ok := stateMap[item.Id]; ok {
			state = value
		}

		data = append(data, serializers.SearchSeriesSerializer{
			Id:          item.Id,
			Title:       item.Name,
			PosterPath:  item.PosterPath,
			ReleaseDate: item.FirstAirDate,
			Rating:      item.VoteAverage,
			State:       state,
		})
	}

	return &serializers.PaginationResponse[serializers.SearchSeriesSerializer]{
		Data: data,
		Meta: serializers.PaginationMeta{
			Page:  uint64(response.Page),
			Per:   uint64(len(data)),
			Total: uint64(response.TotalResults),
		},
	}, nil
}

// buildPeopleList filters adult and profile-less results (people carry no tracking state)
func buildPeopleList(response *tmdb.PersonListResult, minKnownForVotes int) *serializers.PaginationResponse[serializers.SearchPersonSerializer] {
	data := make([]serializers.SearchPersonSerializer, 0, len(response.Results))
	for _, item := range response.Results {
		if item.ProfilePath == "" || item.Adult {
			continue
		}

		if minKnownForVotes > 0 && !hasNotableCredit(item.KnownFor, minKnownForVotes) {
			continue
		}

		data = append(data, serializers.SearchPersonSerializer{
			Id:          item.Id,
			Name:        item.Name,
			ProfilePath: item.ProfilePath,
		})
	}

	return &serializers.PaginationResponse[serializers.SearchPersonSerializer]{
		Data: data,
		Meta: serializers.PaginationMeta{
			Page:  uint64(response.Page),
			Per:   uint64(len(data)),
			Total: uint64(response.TotalResults),
		},
	}
}

// hasNotableCredit reports whether any known-for title clears the vote-count floor
func hasNotableCredit(knownFor []tmdb.PersonKnownFor, minVotes int) bool {
	for _, credit := range knownFor {
		if credit.VoteCount >= minVotes {
			return true
		}
	}

	return false
}

// upNextConcurrency bounds the parallel TMDB detail lookups a single up-next request may run
const upNextConcurrency = 8

// tmdbReleasedStatus is the TMDB movie status meaning the film is out
const tmdbReleasedStatus = "Released"

// FetchUpNext builds the user's ready-to-watch queue from pinned library items: the latest aired-but-unwatched episode of each pinned show and any released, unwatched pinned movie
func (p *tmdbProvider) FetchUpNext(ctx context.Context, userId uuid.UUID) (*serializers.UpNextSerializer, error) {
	episodes, err := p.upNextEpisodes(ctx, userId)
	if err != nil {
		return nil, err
	}

	movies, err := p.upNextMovies(ctx, userId)
	if err != nil {
		return nil, err
	}

	return &serializers.UpNextSerializer{Episodes: episodes, Movies: movies}, nil
}

// upNextEpisodes returns the next unwatched-but-aired episode of each pinned watching show, most recent first
func (p *tmdbProvider) upNextEpisodes(ctx context.Context, userId uuid.UUID) ([]serializers.UpNextEpisodeSerializer, error) {
	watching, _, err := p.series.List(ctx, userId, models.StateTypeWatching, &Pagination{Page: DefaultPage, PerPage: MaxPerPage})
	if err != nil {
		return nil, err
	}

	pinned := make([]models.Series, 0, len(watching))
	for _, show := range watching {
		if show.Pinned {
			pinned = append(pinned, show)
		}
	}

	entries := boundedMap(pinned, upNextConcurrency, func(show models.Series) *serializers.UpNextEpisodeSerializer {
		return p.nextUnwatchedEpisode(ctx, userId, show)
	})

	episodes := make([]serializers.UpNextEpisodeSerializer, 0, len(pinned))

	for _, entry := range entries {
		if entry != nil {
			episodes = append(episodes, *entry)
		}
	}

	// most-recently-aired first (ISO dates sort lexically)
	sort.SliceStable(episodes, func(i, j int) bool { return episodes[i].AirDate > episodes[j].AirDate })

	return episodes, nil
}

// nextUnwatchedEpisode walks a show's seasons in order and returns the first unwatched episode that has aired (the resume point), skipping on any TMDB failure
func (p *tmdbProvider) nextUnwatchedEpisode(ctx context.Context, userId uuid.UUID, show models.Series) *serializers.UpNextEpisodeSerializer {
	detail, err := cache.Fetch(ctx, p.cache, p.log, fmt.Sprintf("tmdb:v1:tv:%d", show.TmdbId), cache.DetailsTTL, func() (*tmdb.TvDetails, error) {
		return p.client.FetchTvDetails(ctx, show.TmdbId)
	})
	if err != nil {
		p.log.Warn().Err(err).Uint64("ShowId", show.TmdbId).Msg("Skipping show in up-next; TMDB details unavailable")
		return nil
	}

	progress, err := p.progress.Get(ctx, userId, show.TmdbId)
	if err != nil {
		p.log.Warn().Err(err).Uint64("ShowId", show.TmdbId).Msg("Skipping show in up-next; progress unavailable")
		return nil
	}

	watchedEpisodes := toIdSet(progress.WatchedEpisodes)
	watchedSeasons := toIdSet(progress.WatchedSeasons)
	today := time.Now().UTC().Truncate(24 * time.Hour)

	// regular seasons only (drop specials), ascending so the walk follows air order
	seasons := make([]tmdb.TvSeason, 0, len(detail.Seasons))
	for _, season := range detail.Seasons {
		if season.SeasonNumber >= 1 {
			seasons = append(seasons, season)
		}
	}

	sort.SliceStable(seasons, func(i, j int) bool { return seasons[i].SeasonNumber < seasons[j].SeasonNumber })

	for _, season := range seasons {
		if _, done := watchedSeasons[season.Id]; done {
			continue // fully watched, skip without fetching
		}

		seasonDetail, err := cache.Fetch(ctx, p.cache, p.log, fmt.Sprintf("tmdb:v1:tv:%d:season:%d", show.TmdbId, season.SeasonNumber), cache.DetailsTTL, func() (*tmdb.SeasonDetails, error) {
			return p.client.FetchTvSeasonDetails(ctx, show.TmdbId, uint64(season.SeasonNumber))
		})
		if err != nil {
			p.log.Warn().Err(err).Uint64("ShowId", show.TmdbId).Int("Season", season.SeasonNumber).Msg("Skipping show in up-next; season details unavailable")
			return nil
		}

		for _, episode := range seasonDetail.Episodes {
			if _, watched := watchedEpisodes[uint64(episode.ID)]; watched {
				continue
			}

			// the first unwatched episode is the resume point: suggest it only if it has aired
			if airedOnOrBefore(episode.AirDate, today) {
				entry := upNextEpisodeEntry(show, episode)
				return &entry
			}

			return nil
		}
	}

	return nil
}

// airedOnOrBefore reports whether a TMDB air date parses and falls on or before the given day
func airedOnOrBefore(airDate string, day time.Time) bool {
	date, err := tmdb.ParseDate(airDate)
	if err != nil || date.IsZero() {
		return false
	}

	return !date.After(day)
}

// upNextEpisodeEntry builds an up-next row from a show and one of its episodes
func upNextEpisodeEntry(show models.Series, episode tmdb.Episode) serializers.UpNextEpisodeSerializer {
	return serializers.UpNextEpisodeSerializer{
		SeriesId:         show.TmdbId,
		SeriesTitle:      show.Title,
		SeriesPosterPath: show.PosterPath,
		Id:               uint64(episode.ID),
		Title:            episode.Name,
		SeasonNumber:     uint64(episode.SeasonNumber),
		Number:           uint64(episode.EpisodeNumber),
		PosterPath:       episode.StillPath,
		Overview:         episode.Overview,
		Runtime:          uint64(max(episode.Runtime, 0)),
		Rating:           episode.VoteAverage,
		AirDate:          episode.AirDate,
	}
}

// upNextMovies returns the released movies among the user's pinned want list, preserving library order
func (p *tmdbProvider) upNextMovies(ctx context.Context, userId uuid.UUID) ([]serializers.UpNextMovieSerializer, error) {
	want, _, err := p.movies.List(ctx, userId, models.StateTypeWant, &Pagination{Page: DefaultPage, PerPage: MaxPerPage})
	if err != nil {
		return nil, err
	}

	pinned := make([]models.Movie, 0, len(want))
	for _, movie := range want {
		if movie.Pinned {
			pinned = append(pinned, movie)
		}
	}

	today := time.Now().UTC().Truncate(24 * time.Hour)

	entries := boundedMap(pinned, upNextConcurrency, func(movie models.Movie) *serializers.UpNextMovieSerializer {
		return p.releasedMovie(ctx, movie, today)
	})

	movies := make([]serializers.UpNextMovieSerializer, 0, len(pinned))

	for _, entry := range entries {
		if entry != nil {
			movies = append(movies, *entry)
		}
	}

	return movies, nil
}

// releasedMovie resolves a want-list movie when it has been released, skipping on any TMDB failure
func (p *tmdbProvider) releasedMovie(ctx context.Context, movie models.Movie, today time.Time) *serializers.UpNextMovieSerializer {
	response, err := cache.Fetch(ctx, p.cache, p.log, fmt.Sprintf("tmdb:v1:movie:%d", movie.TmdbId), cache.DetailsTTL, func() (*tmdb.MovieDetails, error) {
		return p.client.FetchMovieDetails(ctx, movie.TmdbId)
	})
	if err != nil {
		p.log.Warn().Err(err).Uint64("MovieId", movie.TmdbId).Msg("Skipping movie in up-next; TMDB details unavailable")
		return nil
	}

	if !isReleased(response.Status, response.ReleaseDate, today) {
		return nil
	}

	entry := serializers.UpNextMovieSerializer{
		Id:          movie.TmdbId,
		Title:       response.Title,
		PosterPath:  response.PosterPath,
		Overview:    response.Overview,
		Runtime:     uint64(max(response.Runtime, 0)),
		Rating:      response.VoteAverage,
		ReleaseDate: response.ReleaseDate,
	}

	return &entry
}

// isReleased reports whether a movie is out: a "Released" status, or a release date on or before today
func isReleased(status, releaseDate string, today time.Time) bool {
	if status == tmdbReleasedStatus {
		return true
	}

	date, err := tmdb.ParseDate(releaseDate)
	if err != nil || date.IsZero() {
		return false
	}

	return !date.After(today)
}

// boundedMap applies fn to every item concurrently, capped at `concurrency` in-flight, preserving input order
func boundedMap[T any, R any](items []T, concurrency int, fn func(T) R) []R {
	results := make([]R, len(items))
	semaphore := make(chan struct{}, concurrency)

	var wg sync.WaitGroup
	for i := range items {
		wg.Add(1)

		semaphore <- struct{}{}

		go func(i int) {
			defer wg.Done()
			defer func() { <-semaphore }()

			results[i] = fn(items[i])
		}(i)
	}

	wg.Wait()

	return results
}
