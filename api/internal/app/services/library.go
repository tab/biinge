package services

import (
	"context"
	"fmt"
	"maps"
	"slices"
	"strconv"
	"sync"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"go.uber.org/fx"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories"
	"biinge-api/internal/config"
	"biinge-api/internal/config/cache"
	"biinge-api/internal/config/logger"
	"biinge-api/pkg/jellyfin"
	"biinge-api/pkg/tmdb"
)

// libraryTTL is how long a user's library and episode indexes are cached (a title added to Jellyfin matches once it expires)
const libraryTTL = 10 * time.Minute

// playedTimeout bounds one background played write, TMDB lookups and Jellyfin calls included
// shortcut: a long series on a slow server stops partway when this runs out, revisit with the BL-025 sync
const playedTimeout = 30 * time.Second

// playedQueue is how many played writes wait behind the one in flight before SetPlayed drops the next
const playedQueue = 256

// PlayedKind is the kind of title a played write targets
type PlayedKind string

const (
	PlayedMovie   PlayedKind = "movie"
	PlayedSeries  PlayedKind = "series"
	PlayedSeason  PlayedKind = "season"
	PlayedEpisode PlayedKind = "episode"
)

// PlayedTarget is the title a played write marks (TmdbId is the movie or series, SeasonId and EpisodeId the TMDB ids below it)
type PlayedTarget struct {
	Kind      PlayedKind
	TmdbId    uint64
	SeasonId  uint64
	EpisodeId uint64
	Played    bool
}

// Library finds the user's Jellyfin item for a title ("" when the library holds none or several, or Jellyfin is off, unconnected or failing) and sets its played state
type Library interface {
	Movie(ctx context.Context, userId uuid.UUID, tmdbId uint64) string
	Series(ctx context.Context, userId uuid.UUID, tmdbId uint64) string
	MovieIds(ctx context.Context, userId uuid.UUID, tmdbIds []uint64) map[uint64]string
	SeriesIds(ctx context.Context, userId uuid.UUID, tmdbIds []uint64) map[uint64]string
	Episodes(ctx context.Context, userId uuid.UUID, tmdbId uint64, season uint64) map[uint64]string
	SetPlayed(ctx context.Context, userId uuid.UUID, target PlayedTarget)
}

// playedJob is one played write waiting for the library's worker
type playedJob struct {
	userId uuid.UUID
	target PlayedTarget
}

// libraryIndex maps TMDB ids to the user's movie and series item ids (an empty id marks a TMDB id held by several items)
type libraryIndex struct {
	Movies map[string]string
	Series map[string]string
}

type library struct {
	cfg        *config.Config
	repository repositories.IntegrationRepository
	client     jellyfin.Client
	tmdb       tmdb.Client
	cache      cache.Cache
	log        *logger.Logger

	// jobs feeds the worker, which runs the played writes one at a time in the order SetPlayed queued them
	jobs chan playedJob
	done chan struct{}

	// mu guards stopped, so SetPlayed never sends on the queue OnStop closed
	mu      sync.RWMutex
	stopped bool
}

func NewLibrary(
	lifecycle fx.Lifecycle,
	cfg *config.Config,
	repository repositories.IntegrationRepository,
	client jellyfin.Client,
	tmdbClient tmdb.Client,
	store cache.Cache,
	log *logger.Logger,
) Library {
	l := &library{
		cfg:        cfg,
		repository: repository,
		client:     client,
		tmdb:       tmdbClient,
		cache:      store,
		log:        log.WithComponent("LibraryService"),
		jobs:       make(chan playedJob, playedQueue),
		done:       make(chan struct{}),
	}

	lifecycle.Append(fx.Hook{
		OnStart: func(context.Context) error {
			//nolint:gosec // G118 wants OnStart's context, which ends with startup, so each write takes its own deadline instead
			go func() {
				defer close(l.done)

				for job := range l.jobs {
					// the write outlives the request, so it keeps its own deadline
					ctx, cancel := context.WithTimeout(context.Background(), playedTimeout)
					l.setPlayed(ctx, job.userId, job.target)
					cancel()
				}
			}()

			return nil
		},
		OnStop: func(ctx context.Context) error {
			l.mu.Lock()
			l.stopped = true
			close(l.jobs)
			l.mu.Unlock()

			// wait for the write in flight and the queued ones, bounded by the shutdown deadline
			select {
			case <-l.done:
			case <-ctx.Done():
			}

			return nil
		},
	})

	return l
}

func (l *library) Movie(ctx context.Context, userId uuid.UUID, tmdbId uint64) string {
	index, _ := l.index(ctx, userId)

	return index.Movies[strconv.FormatUint(tmdbId, 10)]
}

func (l *library) Series(ctx context.Context, userId uuid.UUID, tmdbId uint64) string {
	index, _ := l.index(ctx, userId)

	return index.Series[strconv.FormatUint(tmdbId, 10)]
}

// MovieIds maps each of the TMDB ids with exactly one matched movie to its item id (one index read for a whole list)
func (l *library) MovieIds(ctx context.Context, userId uuid.UUID, tmdbIds []uint64) map[uint64]string {
	index, _ := l.index(ctx, userId)

	ids := map[uint64]string{}

	for _, tmdbId := range tmdbIds {
		if id := index.Movies[strconv.FormatUint(tmdbId, 10)]; id != "" {
			ids[tmdbId] = id
		}
	}

	return ids
}

// SeriesIds maps each of the TMDB ids with exactly one matched series to its item id (one index read for a whole list)
func (l *library) SeriesIds(ctx context.Context, userId uuid.UUID, tmdbIds []uint64) map[uint64]string {
	index, _ := l.index(ctx, userId)

	ids := map[uint64]string{}

	for _, tmdbId := range tmdbIds {
		if id := index.Series[strconv.FormatUint(tmdbId, 10)]; id != "" {
			ids[tmdbId] = id
		}
	}

	return ids
}

// Episodes maps each episode number of the season to its item id, nil when the series has no unique match
func (l *library) Episodes(ctx context.Context, userId uuid.UUID, tmdbId uint64, season uint64) map[uint64]string {
	return l.episodes(ctx, userId, tmdbId)[season]
}

// episodes maps each season number to its episode numbers and item ids from the cached series index (nil when the series has no unique match)
func (l *library) episodes(ctx context.Context, userId uuid.UUID, tmdbId uint64) map[uint64]map[uint64]string {
	// a matched series means the index read succeeded, so the connection is set
	index, connection := l.index(ctx, userId)

	seriesId := index.Series[strconv.FormatUint(tmdbId, 10)]
	if seriesId == "" {
		return nil
	}

	key := fmt.Sprintf("jellyfin:v1:episodes:%s:%s:%s", userId, connection.UserId, seriesId)

	episodes, err := cache.Fetch(ctx, l.cache, l.log, key, libraryTTL, func() (map[uint64]map[uint64]string, error) {
		items, err := l.client.Episodes(ctx, *connection, seriesId)
		if err != nil {
			return nil, err
		}

		result := map[uint64]map[uint64]string{}

		for _, item := range items {
			if item.Season == nil || item.Number == nil {
				continue
			}

			numbers := result[uint64(*item.Season)]
			if numbers == nil {
				numbers = map[uint64]string{}
				result[uint64(*item.Season)] = numbers
			}

			// several episodes with one season and number leave an empty id, removed below
			if _, seen := numbers[uint64(*item.Number)]; seen {
				numbers[uint64(*item.Number)] = ""
				continue
			}

			numbers[uint64(*item.Number)] = item.Id
		}

		for _, numbers := range result {
			maps.DeleteFunc(numbers, func(_ uint64, id string) bool { return id == "" })
		}

		return result, nil
	})
	if err != nil {
		// the client already logged the failure, without the token
		l.log.Warn().Err(err).Msg("Failed to read the Jellyfin episodes")
		return nil
	}

	return episodes
}

// SetPlayed queues the target's played write for the worker, which marks its matched Jellyfin items in order (nothing without a connection, exactly one match or the TMDB numbers)
func (l *library) SetPlayed(_ context.Context, userId uuid.UUID, target PlayedTarget) {
	l.mu.RLock()
	defer l.mu.RUnlock()

	// a request still running past the server's shutdown finds the worker stopped
	if l.stopped {
		l.log.Warn().Uint64("TmdbId", target.TmdbId).Str("Kind", string(target.Kind)).Msg("Dropping the Jellyfin played write; the library has stopped")
		return
	}

	select {
	case l.jobs <- playedJob{userId: userId, target: target}:
	default:
		// a full queue drops the write rather than hold the request, and the library drifts until the BL-025 sync
		l.log.Warn().Uint64("TmdbId", target.TmdbId).Str("Kind", string(target.Kind)).Msg("Dropping the Jellyfin played write; the queue is full")
	}
}

// setPlayed resolves the target to the user's Jellyfin items and writes their played state, logging each failure
func (l *library) setPlayed(ctx context.Context, userId uuid.UUID, target PlayedTarget) {
	index, connection := l.index(ctx, userId)
	if connection == nil {
		return
	}

	var items []string

	switch target.Kind {
	case PlayedMovie:
		items = append(items, index.Movies[strconv.FormatUint(target.TmdbId, 10)])
	case PlayedSeries:
		items = append(items, index.Series[strconv.FormatUint(target.TmdbId, 10)])

		// Jellyfin leaves the episodes unplayed when it marks the series, so each matched episode is written too
		for _, numbers := range l.episodes(ctx, userId, target.TmdbId) {
			items = slices.AppendSeq(items, maps.Values(numbers))
		}
	case PlayedSeason, PlayedEpisode:
		// an unmatched series needs no TMDB numbers
		if index.Series[strconv.FormatUint(target.TmdbId, 10)] == "" {
			return
		}

		details, err := cache.Fetch(ctx, l.cache, l.log, fmt.Sprintf("tmdb:v2:tv:%d", target.TmdbId), cache.DetailsTTL, func() (*tmdb.TvDetails, error) {
			return l.tmdb.FetchTvDetails(ctx, target.TmdbId)
		})
		if err != nil {
			l.log.Warn().Err(err).Uint64("SeriesId", target.TmdbId).Msg("Skipping the Jellyfin played write; TMDB details unavailable")
			return
		}

		// an explicit find, because season 0 holds the specials
		found := slices.IndexFunc(details.Seasons, func(season tmdb.TvSeason) bool { return season.Id == target.SeasonId })
		if found < 0 {
			return
		}

		seasonNumber := details.Seasons[found].SeasonNumber

		if target.Kind == PlayedSeason {
			items = slices.AppendSeq(items, maps.Values(l.Episodes(ctx, userId, target.TmdbId, uint64(seasonNumber))))
			break
		}

		season, err := cache.Fetch(ctx, l.cache, l.log, fmt.Sprintf("tmdb:v1:tv:%d:season:%d", target.TmdbId, seasonNumber), cache.DetailsTTL, func() (*tmdb.SeasonDetails, error) {
			return l.tmdb.FetchTvSeasonDetails(ctx, target.TmdbId, uint64(seasonNumber))
		})
		if err != nil {
			l.log.Warn().Err(err).Uint64("SeriesId", target.TmdbId).Int("Season", seasonNumber).Msg("Skipping the Jellyfin played write; TMDB season details unavailable")
			return
		}

		episode := slices.IndexFunc(season.Episodes, func(episode tmdb.Episode) bool { return uint64(episode.ID) == target.EpisodeId })
		if episode < 0 {
			return
		}

		items = append(items, l.Episodes(ctx, userId, target.TmdbId, uint64(seasonNumber))[uint64(season.Episodes[episode].EpisodeNumber)])
	}

	for _, item := range items {
		// an empty id is a title without exactly one match
		if item == "" {
			continue
		}

		if err := l.client.SetPlayed(ctx, *connection, jellyfin.PlayedState{ItemId: item, Played: target.Played}); err != nil {
			// the client already logged the failure, without the token
			l.log.Warn().Err(err).Str("ItemId", item).Msg("Failed to write the Jellyfin played state")
		}
	}
}

// index returns the user's cached library index and Jellyfin connection (an empty index and nil connection when there is none to read)
func (l *library) index(ctx context.Context, userId uuid.UUID) (libraryIndex, *jellyfin.Connection) {
	if l.cfg.Jellyfin.BaseURL == "" {
		return libraryIndex{}, nil
	}

	integration, err := l.repository.FindByUser(ctx, userId, models.JellyfinProvider)
	if err != nil {
		// a missing row is a user who never connected
		if !errors.Is(err, pgx.ErrNoRows) {
			l.log.Error().Err(err).Msg("Failed to fetch Jellyfin connection")
		}

		return libraryIndex{}, nil
	}

	token, err := decryptToken([]byte(l.cfg.Jellyfin.TokenKey), integration.Token)
	if err != nil {
		l.log.Warn().Err(err).Msg("Failed to decrypt Jellyfin token")
		return libraryIndex{}, nil
	}

	connection := &jellyfin.Connection{
		DeviceId:    "biinge-api-" + userId.String(),
		AccessToken: token,
		UserId:      integration.ExternalUserId,
	}

	// the Jellyfin user id keeps a reconnect as another Jellyfin user off the earlier index
	key := fmt.Sprintf("jellyfin:v1:library:%s:%s", userId, integration.ExternalUserId)

	index, err := cache.Fetch(ctx, l.cache, l.log, key, libraryTTL, func() (libraryIndex, error) {
		items, err := l.client.Items(ctx, *connection)
		if err != nil {
			return libraryIndex{}, err
		}

		result := libraryIndex{Movies: map[string]string{}, Series: map[string]string{}}

		for _, item := range items {
			if item.TmdbId == "" {
				continue
			}

			// Items returns only movies and series
			ids := result.Series
			if item.Type == jellyfin.ItemTypeMovie {
				ids = result.Movies
			}

			// a TMDB id held by several items keeps an empty id, so it never matches
			if _, seen := ids[item.TmdbId]; seen {
				ids[item.TmdbId] = ""
				continue
			}

			ids[item.TmdbId] = item.Id
		}

		return result, nil
	})
	if err != nil {
		// the client already logged the failure, without the token
		l.log.Warn().Err(err).Msg("Failed to read the Jellyfin library")
		return libraryIndex{}, nil
	}

	return index, connection
}
