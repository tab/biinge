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
	List(ctx context.Context, userId uuid.UUID, status string, pagination *Pagination) ([]models.Movie, uint64, error)
	Create(ctx context.Context, params *models.Movie) (*models.Movie, error)
	Update(ctx context.Context, params *models.Movie) (*models.Movie, error)
	UpdateByTmdbId(ctx context.Context, params *models.Movie) (*models.Movie, error)
	Delete(ctx context.Context, id uuid.UUID) error
	DeleteByTmdbId(ctx context.Context, tmdbId uint64, userId uuid.UUID) error
	FindById(ctx context.Context, id uuid.UUID) (*models.Movie, error)
	FindByTmdbId(ctx context.Context, tmdbId uint64, userId uuid.UUID) (*models.Movie, error)
	FindMoviesByTmdbIds(ctx context.Context, tmdbIds []uint64, userId uuid.UUID) ([]models.Movie, error)
}

type movies struct {
	repository repositories.MovieRepository
	log        *logger.Logger
}

func NewMovies(repository repositories.MovieRepository, log *logger.Logger) Movies {
	return &movies{
		repository: repository,
		log:        log.WithComponent("MoviesService"),
	}
}

func (m *movies) List(ctx context.Context, userId uuid.UUID, status string, pagination *Pagination) ([]models.Movie, uint64, error) {
	collection, total, err := m.repository.List(ctx, userId, status, pagination.Limit(), pagination.Offset())

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

	return item, nil
}

func (m *movies) Delete(ctx context.Context, id uuid.UUID) error {
	err := m.repository.Delete(ctx, id)
	if err != nil {
		m.log.Error().Err(err).Msg("Failed to delete movie")
		return errors.ErrFailedToDeleteMovie
	}

	return nil
}

func (m *movies) DeleteByTmdbId(ctx context.Context, tmdbId uint64, userId uuid.UUID) error {
	err := m.repository.DeleteByTmdbId(ctx, tmdbId, userId)
	if err != nil {
		m.log.Error().Err(err).Msg("Failed to delete movie by TMDB Id")
		return errors.ErrFailedToDeleteMovie
	}

	return nil
}

func (m *movies) FindById(ctx context.Context, id uuid.UUID) (*models.Movie, error) {
	item, err := m.repository.FindById(ctx, id)
	if err != nil {
		m.log.Error().Err(err).Msg("Failed to fetch movie by Id")
		return nil, errors.ErrMovieNotFound
	}

	return item, nil
}

func (m *movies) FindByTmdbId(ctx context.Context, tmdbId uint64, userId uuid.UUID) (*models.Movie, error) {
	item, err := m.repository.FindByTmdbId(ctx, tmdbId, userId)
	if err != nil {
		m.log.Error().Err(err).Msg("Failed to fetch movie by TMDB Id")
		return nil, errors.ErrMovieNotFound
	}

	return item, nil
}

func (m *movies) FindMoviesByTmdbIds(ctx context.Context, tmdbIds []uint64, userId uuid.UUID) ([]models.Movie, error) {
	collection, err := m.repository.FindMoviesByTmdbIds(ctx, tmdbIds, userId)
	if err != nil {
		m.log.Error().Err(err).Msg("Failed to fetch movies by TMDB Ids")
		return nil, errors.ErrFailedToFetchResults
	}

	return collection, nil
}
