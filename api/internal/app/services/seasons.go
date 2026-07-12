package services

import (
	"context"

	"github.com/google/uuid"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories"
	"biinge-api/internal/config/logger"
)

type Seasons interface {
	List(ctx context.Context, seriesId, userId uuid.UUID) ([]models.Season, error)
	Create(ctx context.Context, params *models.Season) (*models.Season, error)
	Update(ctx context.Context, userId uuid.UUID, params *models.Season) (*models.Season, error)
	UpdateByTmdbId(ctx context.Context, userId uuid.UUID, tmdbId uint64, state string) (*models.Season, error)
	Delete(ctx context.Context, id uuid.UUID) error
	FindById(ctx context.Context, id uuid.UUID) (*models.Season, error)
	CountWatched(ctx context.Context, seriesId, userId uuid.UUID, state string) (uint64, error)
}

type seasons struct {
	repository repositories.SeasonRepository
	log        *logger.Logger
}

func NewSeasons(repository repositories.SeasonRepository, log *logger.Logger) Seasons {
	return &seasons{
		repository: repository,
		log:        log.WithComponent("SeasonsService"),
	}
}

func (s *seasons) List(ctx context.Context, seriesId, userId uuid.UUID) ([]models.Season, error) {
	collection, err := s.repository.List(ctx, seriesId, userId)
	if err != nil {
		s.log.Error().Err(err).Msg("Failed to fetch seasons")
		return nil, errors.ErrFailedToFetchSeasons
	}

	return collection, nil
}

func (s *seasons) Create(ctx context.Context, params *models.Season) (*models.Season, error) {
	item, err := s.repository.Create(ctx, &models.Season{
		SeriesId:      params.SeriesId,
		TmdbId:        params.TmdbId,
		Title:         params.Title,
		Number:        params.Number,
		EpisodesCount: params.EpisodesCount,
		State:         params.State,
	})
	if err != nil {
		s.log.Error().Err(err).Msg("Failed to create season")
		return nil, errors.ErrFailedToCreateSeason
	}

	return item, nil
}

func (s *seasons) Update(ctx context.Context, userId uuid.UUID, params *models.Season) (*models.Season, error) {
	item, err := s.repository.Update(ctx, userId, &models.Season{
		ID:            params.ID,
		Title:         params.Title,
		Number:        params.Number,
		EpisodesCount: params.EpisodesCount,
	})
	if err != nil {
		s.log.Error().Err(err).Msg("Failed to update season")
		return nil, errors.ErrFailedToUpdateSeason
	}

	return item, nil
}

func (s *seasons) UpdateByTmdbId(ctx context.Context, userId uuid.UUID, tmdbId uint64, state string) (*models.Season, error) {
	item, err := s.repository.UpdateByTmdbId(ctx, userId, tmdbId, state)
	if err != nil {
		s.log.Error().Err(err).Msg("Failed to update season by TMDB Id")
		return nil, errors.ErrFailedToUpdateSeason
	}

	return item, nil
}

func (s *seasons) Delete(ctx context.Context, id uuid.UUID) error {
	err := s.repository.Delete(ctx, id)
	if err != nil {
		s.log.Error().Err(err).Msg("Failed to delete season")
		return errors.ErrFailedToDeleteSeason
	}

	return nil
}

func (s *seasons) FindById(ctx context.Context, id uuid.UUID) (*models.Season, error) {
	item, err := s.repository.FindById(ctx, id)
	if err != nil {
		s.log.Error().Err(err).Msg("Failed to fetch season by Id")
		return nil, errors.ErrSeasonNotFound
	}

	return item, nil
}

func (s *seasons) CountWatched(ctx context.Context, seriesId, userId uuid.UUID, state string) (uint64, error) {
	count, err := s.repository.CountWatched(ctx, seriesId, userId, state)
	if err != nil {
		s.log.Error().Err(err).Msg("Failed to count watched seasons")
		return 0, errors.ErrFailedToFetchSeasons
	}

	return count, nil
}
