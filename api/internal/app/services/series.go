package services

import (
	"context"

	"github.com/google/uuid"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories"
	"biinge-api/internal/config/logger"
)

type Series interface {
	List(ctx context.Context, userId uuid.UUID, state models.StateType, pagination *Pagination) ([]models.Series, uint64, error)
	Create(ctx context.Context, params *models.Series) (*models.Series, error)
	Update(ctx context.Context, params *models.Series) (*models.Series, error)
	UpdateByTmdbId(ctx context.Context, params *models.Series) (*models.Series, error)
	Delete(ctx context.Context, tmdbId uint64, userId uuid.UUID) error
	FindByFilter(ctx context.Context, filter models.SeriesFilter) ([]models.Series, error)
}

type series struct {
	repository repositories.SeriesRepository
	stats      StatsCache
	log        *logger.Logger
}

func NewSeries(repository repositories.SeriesRepository, stats StatsCache, log *logger.Logger) Series {
	return &series{
		repository: repository,
		stats:      stats,
		log:        log.WithComponent("SeriesService"),
	}
}

func (s *series) List(ctx context.Context, userId uuid.UUID, state models.StateType, pagination *Pagination) ([]models.Series, uint64, error) {
	collection, total, err := s.repository.List(ctx, userId, state, pagination.Limit(), pagination.Offset())
	if err != nil {
		s.log.Error().Err(err).Msg("Failed to fetch series")
		return nil, 0, errors.ErrFailedToFetchSeriesList
	}

	return collection, total, nil
}

func (s *series) Create(ctx context.Context, params *models.Series) (*models.Series, error) {
	item, err := s.repository.Create(ctx, &models.Series{
		UserId:        params.UserId,
		TmdbId:        params.TmdbId,
		Title:         params.Title,
		PosterPath:    params.PosterPath,
		SeasonsCount:  params.SeasonsCount,
		EpisodesCount: params.EpisodesCount,
		Status:        params.Status,
		State:         params.State,
	})
	if err != nil {
		s.log.Error().Err(err).Msg("Failed to create series")
		return nil, errors.ErrFailedToCreateSeries
	}

	s.stats.Invalidate(ctx, params.UserId)

	return item, nil
}

func (s *series) Update(ctx context.Context, params *models.Series) (*models.Series, error) {
	item, err := s.repository.Update(ctx, &models.Series{
		ID:            params.ID,
		Title:         params.Title,
		PosterPath:    params.PosterPath,
		SeasonsCount:  params.SeasonsCount,
		EpisodesCount: params.EpisodesCount,
		Status:        params.Status,
	})
	if err != nil {
		s.log.Error().Err(err).Msg("Failed to update series")
		return nil, errors.ErrFailedToUpdateSeries
	}

	return item, nil
}

func (s *series) UpdateByTmdbId(ctx context.Context, params *models.Series) (*models.Series, error) {
	item, err := s.repository.UpdateByTmdbId(ctx, &models.Series{
		TmdbId: params.TmdbId,
		UserId: params.UserId,
		State:  params.State,
		Pinned: params.Pinned,
	})
	if err != nil {
		s.log.Error().Err(err).Msg("Failed to update series by TMDB Id")
		return nil, errors.ErrFailedToUpdateSeries
	}

	s.stats.Invalidate(ctx, params.UserId)

	return item, nil
}

func (s *series) Delete(ctx context.Context, tmdbId uint64, userId uuid.UUID) error {
	err := s.repository.Delete(ctx, tmdbId, userId)
	if err != nil {
		s.log.Error().Err(err).Msg("Failed to delete series by TMDB Id")
		return errors.ErrFailedToDeleteSeries
	}

	s.stats.Invalidate(ctx, userId)

	return nil
}

func (s *series) FindByFilter(ctx context.Context, filter models.SeriesFilter) ([]models.Series, error) {
	collection, err := s.repository.FindByFilter(ctx, filter)
	if err != nil {
		s.log.Error().Err(err).Msg("Failed to fetch series by TMDB Ids")
		return nil, errors.ErrFailedToFetchResults
	}

	return collection, nil
}
