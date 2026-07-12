package services

import (
	"context"

	"github.com/google/uuid"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories"
	"biinge-api/internal/config/logger"
)

type Episodes interface {
	List(ctx context.Context, seasonId, userId uuid.UUID) ([]models.Episode, error)
	Create(ctx context.Context, params *models.Episode) (*models.Episode, error)
	Update(ctx context.Context, userId uuid.UUID, params *models.Episode) (*models.Episode, error)
	UpdateByTmdbId(ctx context.Context, userId uuid.UUID, tmdbId uint64, state string) (*models.Episode, error)
	Delete(ctx context.Context, id uuid.UUID) error
	FindById(ctx context.Context, id, userId uuid.UUID) (*models.Episode, error)
	Count(ctx context.Context, seasonId, userId uuid.UUID) (uint64, error)
	CountWatched(ctx context.Context, seasonId, userId uuid.UUID, state string) (uint64, error)
}

type episodes struct {
	repository repositories.EpisodeRepository
	log        *logger.Logger
}

func NewEpisodes(repository repositories.EpisodeRepository, log *logger.Logger) Episodes {
	return &episodes{
		repository: repository,
		log:        log.WithComponent("EpisodesService"),
	}
}

func (e *episodes) List(ctx context.Context, seasonId, userId uuid.UUID) ([]models.Episode, error) {
	collection, err := e.repository.List(ctx, seasonId, userId)
	if err != nil {
		e.log.Error().Err(err).Msg("Failed to fetch episodes")
		return nil, errors.ErrFailedToFetchEpisodes
	}

	return collection, nil
}

func (e *episodes) Create(ctx context.Context, params *models.Episode) (*models.Episode, error) {
	item, err := e.repository.Create(ctx, &models.Episode{
		SeasonId:   params.SeasonId,
		TmdbId:     params.TmdbId,
		Title:      params.Title,
		PosterPath: params.PosterPath,
		Runtime:    params.Runtime,
		State:      params.State,
		AirAt:      params.AirAt,
	})
	if err != nil {
		e.log.Error().Err(err).Msg("Failed to create episode")
		return nil, errors.ErrFailedToCreateEpisode
	}

	return item, nil
}

func (e *episodes) Update(ctx context.Context, userId uuid.UUID, params *models.Episode) (*models.Episode, error) {
	item, err := e.repository.Update(ctx, userId, &models.Episode{
		ID:         params.ID,
		Title:      params.Title,
		PosterPath: params.PosterPath,
		Runtime:    params.Runtime,
		AirAt:      params.AirAt,
		State:      params.State,
	})
	if err != nil {
		e.log.Error().Err(err).Msg("Failed to update episode")
		return nil, errors.ErrFailedToUpdateEpisode
	}

	return item, nil
}

func (e *episodes) UpdateByTmdbId(ctx context.Context, userId uuid.UUID, tmdbId uint64, state string) (*models.Episode, error) {
	item, err := e.repository.UpdateByTmdbId(ctx, userId, tmdbId, state)
	if err != nil {
		e.log.Error().Err(err).Msg("Failed to update episode by TMDB Id")
		return nil, errors.ErrFailedToUpdateEpisode
	}

	return item, nil
}

func (e *episodes) Delete(ctx context.Context, id uuid.UUID) error {
	err := e.repository.Delete(ctx, id)
	if err != nil {
		e.log.Error().Err(err).Msg("Failed to delete episode")
		return errors.ErrFailedToDeleteEpisode
	}

	return nil
}

func (e *episodes) FindById(ctx context.Context, id, userId uuid.UUID) (*models.Episode, error) {
	item, err := e.repository.FindById(ctx, id, userId)
	if err != nil {
		e.log.Error().Err(err).Msg("Failed to fetch episode by Id")
		return nil, errors.ErrEpisodeNotFound
	}

	return item, nil
}

func (e *episodes) Count(ctx context.Context, seasonId, userId uuid.UUID) (uint64, error) {
	count, err := e.repository.Count(ctx, seasonId, userId)
	if err != nil {
		e.log.Error().Err(err).Msg("Failed to count episodes")
		return 0, errors.ErrFailedToFetchEpisodes
	}

	return count, nil
}

func (e *episodes) CountWatched(ctx context.Context, seasonId, userId uuid.UUID, state string) (uint64, error) {
	count, err := e.repository.CountWatched(ctx, seasonId, userId, state)
	if err != nil {
		e.log.Error().Err(err).Msg("Failed to count watched episodes")
		return 0, errors.ErrFailedToFetchEpisodes
	}

	return count, nil
}
