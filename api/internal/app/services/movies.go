package services

import (
	"context"

	"github.com/google/uuid"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories"
	"biinge-api/internal/config/logger"
)

type Movies interface {
	List(ctx context.Context, userId uuid.UUID, state models.StateType, pagination *Pagination) ([]models.Movie, uint64, error)
	Create(ctx context.Context, params *models.Movie) (*models.Movie, error)
	Update(ctx context.Context, params *models.Movie) (*models.Movie, error)
	UpdateByTmdbId(ctx context.Context, params *models.Movie) (*models.Movie, error)
	Delete(ctx context.Context, tmdbId uint64, userId uuid.UUID) error
	FindByFilter(ctx context.Context, filter models.MovieFilter) ([]models.Movie, error)
}

type movies struct {
	repository repositories.MovieRepository
	stats      StatsCache
	log        *logger.Logger
}

func NewMovies(repository repositories.MovieRepository, stats StatsCache, log *logger.Logger) Movies {
	return &movies{
		repository: repository,
		stats:      stats,
		log:        log.WithComponent("MoviesService"),
	}
}

func (m *movies) List(ctx context.Context, userId uuid.UUID, state models.StateType, pagination *Pagination) ([]models.Movie, uint64, error) {
	collection, total, err := m.repository.List(ctx, userId, state, pagination.Limit(), pagination.Offset())
	if err != nil {
		m.log.Error().Err(err).Msg("Failed to fetch movies")
		return nil, 0, errors.ErrFailedToFetchMovies
	}

	return collection, total, nil
}

func (m *movies) Create(ctx context.Context, params *models.Movie) (*models.Movie, error) {
	item, err := m.repository.Create(ctx, &models.Movie{
		UserId:     params.UserId,
		TmdbId:     params.TmdbId,
		Title:      params.Title,
		PosterPath: params.PosterPath,
		Runtime:    params.Runtime,
		State:      params.State,
	})
	if err != nil {
		m.log.Error().Err(err).Msg("Failed to create movie")
		return nil, errors.ErrFailedToCreateMovie
	}

	m.stats.Invalidate(ctx, params.UserId)

	return item, nil
}

func (m *movies) Update(ctx context.Context, params *models.Movie) (*models.Movie, error) {
	item, err := m.repository.Update(ctx, &models.Movie{
		ID:         params.ID,
		Title:      params.Title,
		PosterPath: params.PosterPath,
		Runtime:    params.Runtime,
	})
	if err != nil {
		m.log.Error().Err(err).Msg("Failed to update movie")
		return nil, errors.ErrFailedToUpdateMovie
	}

	return item, nil
}

func (m *movies) UpdateByTmdbId(ctx context.Context, params *models.Movie) (*models.Movie, error) {
	item, err := m.repository.UpdateByTmdbId(ctx, &models.Movie{
		TmdbId: params.TmdbId,
		UserId: params.UserId,
		State:  params.State,
		Pinned: params.Pinned,
	})
	if err != nil {
		m.log.Error().Err(err).Msg("Failed to update movie by TMDB Id")
		return nil, errors.ErrFailedToUpdateMovie
	}

	m.stats.Invalidate(ctx, params.UserId)

	return item, nil
}

func (m *movies) Delete(ctx context.Context, tmdbId uint64, userId uuid.UUID) error {
	err := m.repository.Delete(ctx, tmdbId, userId)
	if err != nil {
		m.log.Error().Err(err).Msg("Failed to delete movie by TMDB Id")
		return errors.ErrFailedToDeleteMovie
	}

	m.stats.Invalidate(ctx, userId)

	return nil
}

func (m *movies) FindByFilter(ctx context.Context, filter models.MovieFilter) ([]models.Movie, error) {
	collection, err := m.repository.FindByFilter(ctx, filter)
	if err != nil {
		m.log.Error().Err(err).Msg("Failed to fetch movies by TMDB Ids")
		return nil, errors.ErrFailedToFetchResults
	}

	return collection, nil
}
