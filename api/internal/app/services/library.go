package services

import (
	"context"
	"fmt"
	"maps"
	"strconv"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories"
	"biinge-api/internal/config"
	"biinge-api/internal/config/cache"
	"biinge-api/internal/config/logger"
	"biinge-api/pkg/jellyfin"
)

// libraryTTL is how long a user's library and episode indexes are cached (a title added to Jellyfin matches once it expires)
const libraryTTL = 10 * time.Minute

// Library finds the user's Jellyfin item for a title ("" when the library holds none or several, or Jellyfin is off, unconnected or failing)
type Library interface {
	Movie(ctx context.Context, userId uuid.UUID, tmdbId uint64) string
	Series(ctx context.Context, userId uuid.UUID, tmdbId uint64) string
	Episodes(ctx context.Context, userId uuid.UUID, tmdbId uint64, season uint64) map[uint64]string
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
	cache      cache.Cache
	log        *logger.Logger
}

func NewLibrary(
	cfg *config.Config,
	repository repositories.IntegrationRepository,
	client jellyfin.Client,
	store cache.Cache,
	log *logger.Logger,
) Library {
	return &library{
		cfg:        cfg,
		repository: repository,
		client:     client,
		cache:      store,
		log:        log.WithComponent("LibraryService"),
	}
}

func (l *library) Movie(ctx context.Context, userId uuid.UUID, tmdbId uint64) string {
	index, _ := l.index(ctx, userId)

	return index.Movies[strconv.FormatUint(tmdbId, 10)]
}

func (l *library) Series(ctx context.Context, userId uuid.UUID, tmdbId uint64) string {
	index, _ := l.index(ctx, userId)

	return index.Series[strconv.FormatUint(tmdbId, 10)]
}

// Episodes maps each episode number of the season to its item id, nil when the series has no unique match
func (l *library) Episodes(ctx context.Context, userId uuid.UUID, tmdbId uint64, season uint64) map[uint64]string {
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

	return episodes[season]
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

	// a row with only the webhook token is not a connection
	if len(integration.JellyfinToken) == 0 {
		return libraryIndex{}, nil
	}

	token, err := decryptToken([]byte(l.cfg.Jellyfin.TokenKey), integration.JellyfinToken)
	if err != nil {
		l.log.Warn().Err(err).Msg("Failed to decrypt Jellyfin token")
		return libraryIndex{}, nil
	}

	connection := &jellyfin.Connection{
		DeviceId:    "biinge-api-" + userId.String(),
		AccessToken: token,
		UserId:      integration.JellyfinUserId,
	}

	// the Jellyfin user id keeps a reconnect as another Jellyfin user off the earlier index
	key := fmt.Sprintf("jellyfin:v1:library:%s:%s", userId, integration.JellyfinUserId)

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
