package services

import (
	"context"
	"fmt"
	"slices"
	"strconv"

	"github.com/google/uuid"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories"
	"biinge-api/internal/config/cache"
	"biinge-api/internal/config/logger"
	"biinge-api/pkg/jellyfin"
	"biinge-api/pkg/tmdb"
)

// Jellyfin turns a Webhook plugin event into a watched mark on a title the user already tracks
type Jellyfin interface {
	Handle(ctx context.Context, integration *models.Integration, event *jellyfin.Event) error
}

type jellyfinService struct {
	client   tmdb.Client
	movies   Movies
	progress Progress
	webhooks repositories.WebhookRepository
	cache    cache.Cache
	log      *logger.Logger
}

func NewJellyfin(
	client tmdb.Client,
	movies Movies,
	progress Progress,
	webhooks repositories.WebhookRepository,
	store cache.Cache,
	log *logger.Logger,
) Jellyfin {
	return &jellyfinService{
		client:   client,
		movies:   movies,
		progress: progress,
		webhooks: webhooks,
		cache:    store,
		log:      log.WithComponent("JellyfinService"),
	}
}

// Handle drops progress saves before any work, then resolves and merges the event and stores it with its status
func (j *jellyfinService) Handle(ctx context.Context, integration *models.Integration, event *jellyfin.Event) error {
	if !event.Finished() {
		return nil
	}

	var (
		status models.WebhookStatus
		err    error
	)

	switch event.ItemType {
	case jellyfin.ItemTypeMovie:
		status, err = j.movie(ctx, integration.UserId, event)
	case jellyfin.ItemTypeEpisode:
		status, err = j.episode(ctx, integration.UserId, event)
	default:
		status = models.WebhookStatusIgnored
	}

	if status == models.WebhookStatusUnresolved {
		j.log.Warn().
			Err(err).
			Str("itemType", event.ItemType).
			Str("name", event.Name).
			Str("tmdb", event.ProviderTmdb).
			Str("imdb", event.ProviderImdb).
			Str("tvdb", event.ProviderTvdb).
			Msg("Jellyfin event could not be resolved")
	}

	reason := ""
	if err != nil {
		reason = err.Error()
	}

	// the trace is part of accepting the event, so a mark without its row still fails the request
	if insertErr := j.webhooks.Create(ctx, &models.Webhook{
		IntegrationId: integration.ID,
		Payload:       event.Raw,
		Status:        status,
		Error:         reason,
	}); insertErr != nil {
		j.log.Error().Err(insertErr).Msg("Failed to store webhook event")
		return errors.ErrFailedToProcessWebhook
	}

	return err
}

// movie marks the movie watched when the user tracks it; Jellyfin's TMDB provider always sets Provider_tmdb
func (j *jellyfinService) movie(ctx context.Context, userId uuid.UUID, event *jellyfin.Event) (models.WebhookStatus, error) {
	tmdbId, err := strconv.ParseUint(event.ProviderTmdb, 10, 64)
	if err != nil || tmdbId == 0 {
		return models.WebhookStatusUnresolved, errors.ErrMissingProviderId
	}

	rows, err := j.movies.FindByFilter(ctx, models.MovieFilter{UserId: userId, TmdbIds: []uint64{tmdbId}})
	if err != nil {
		return models.WebhookStatusFailed, errors.ErrFailedToProcessWebhook
	}

	// a title that is not tracked, or is already watched, is left exactly as it is
	if len(rows) == 0 || rows[0].State == models.StateTypeWatched {
		return models.WebhookStatusIgnored, nil
	}

	// pinned is passed back as read so the mark leaves it alone
	_, err = j.movies.UpdateByTmdbId(ctx, &models.Movie{
		TmdbId: tmdbId,
		UserId: userId,
		State:  models.StateTypeWatched,
		Pinned: rows[0].Pinned,
	})
	if err != nil {
		return models.WebhookStatusFailed, errors.ErrFailedToProcessWebhook
	}

	return models.WebhookStatusMarked, nil
}

// episode resolves the episode through /find, then applies the merge rules against the show's progress
func (j *jellyfinService) episode(ctx context.Context, userId uuid.UUID, event *jellyfin.Event) (models.WebhookStatus, error) {
	var externalId, source string

	switch {
	case event.ProviderTvdb != "":
		externalId, source = event.ProviderTvdb, tmdb.FindSourceTvdb
	case event.ProviderImdb != "":
		externalId, source = event.ProviderImdb, tmdb.FindSourceImdb
	default:
		return models.WebhookStatusUnresolved, errors.ErrMissingProviderId
	}

	result, err := j.client.Find(ctx, externalId, source)
	if err != nil {
		if errors.Is(err, tmdb.ErrNotFound) {
			return models.WebhookStatusUnresolved, errors.ErrTitleNotFound
		}

		return models.WebhookStatusFailed, errors.ErrTmdbUnavailable
	}

	if len(result.TvEpisodeResults) == 0 || result.TvEpisodeResults[0].ShowId == 0 {
		return models.WebhookStatusUnresolved, errors.ErrTitleNotFound
	}

	found := result.TvEpisodeResults[0]
	episodeId := uint64(found.ID)

	progress, err := j.progress.Get(ctx, userId, found.ShowId)
	if err != nil {
		return models.WebhookStatusFailed, errors.ErrFailedToProcessWebhook
	}

	// an untracked show and an episode that is already watched are left as they are; a new row on
	// a finished show would run the cascade and flip it back to watching, so that is left too
	if progress.State == models.StateTypeNone || progress.State == models.StateTypeWatched || slices.Contains(progress.WatchedEpisodes, episodeId) {
		return models.WebhookStatusIgnored, nil
	}

	details, err := cache.Fetch(ctx, j.cache, j.log, fmt.Sprintf("tmdb:v1:tv:%d", found.ShowId), cache.DetailsTTL, func() (*tmdb.TvDetails, error) {
		return j.client.FetchTvDetails(ctx, found.ShowId)
	})
	if err != nil {
		if errors.Is(err, tmdb.ErrNotFound) {
			return models.WebhookStatusUnresolved, errors.ErrTitleNotFound
		}

		return models.WebhookStatusFailed, errors.ErrTmdbUnavailable
	}

	index := slices.IndexFunc(details.Seasons, func(season tmdb.TvSeason) bool { return season.SeasonNumber == found.SeasonNumber })
	if index < 0 {
		return models.WebhookStatusUnresolved, errors.ErrTitleNotFound
	}

	season := details.Seasons[index]
	airAt, _ := tmdb.ParseDate(found.AirDate)

	_, err = j.progress.MarkEpisode(ctx, userId,
		models.SeriesInput{
			TmdbId:        found.ShowId,
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
			Title:      found.Name,
			PosterPath: found.StillPath,
			Runtime:    uint64(max(found.Runtime, 0)),
			AirAt:      airAt,
		},
	)
	if err != nil {
		return models.WebhookStatusFailed, errors.ErrFailedToProcessWebhook
	}

	return models.WebhookStatusMarked, nil
}
