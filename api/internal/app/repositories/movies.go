package repositories

import (
	"context"

	"github.com/google/uuid"

	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories/db"
	"biinge-api/internal/app/repositories/postgres"
)

type MovieRepository interface {
	List(ctx context.Context, userId uuid.UUID, state models.StateType, limit, offset uint64) ([]models.Movie, uint64, error)
	Create(ctx context.Context, params *models.Movie) (*models.Movie, error)
	Update(ctx context.Context, params *models.Movie) (*models.Movie, error)
	UpdateByTmdbId(ctx context.Context, params *models.Movie) (*models.Movie, error)
	Delete(ctx context.Context, tmdbId uint64, userId uuid.UUID) error
	FindByFilter(ctx context.Context, filter models.MovieFilter) ([]models.Movie, error)
}

type movie struct {
	client postgres.Postgres
}

func NewMovieRepository(client postgres.Postgres) MovieRepository {
	return &movie{client: client}
}

func (m *movie) List(ctx context.Context, userId uuid.UUID, state models.StateType, limit, offset uint64) ([]models.Movie, uint64, error) {
	rows, err := m.client.Queries().FindMoviesByState(ctx, db.FindMoviesByStateParams{
		UserID: userId,
		State:  db.StateTypes(state),
		Limit:  int32(limit),
		Offset: int32(offset),
	})
	if err != nil {
		return nil, 0, err
	}

	movies := make([]models.Movie, 0, len(rows))

	var total uint64

	if len(rows) > 0 {
		total = uint64(rows[0].Total)
	}

	for _, row := range rows {
		movies = append(movies, models.Movie{
			ID:         row.ID,
			UserId:     row.UserID,
			TmdbId:     row.TmdbID,
			Title:      row.Title,
			PosterPath: row.PosterPath,
			Pinned:     row.Pinned,
			State:      models.StateType(row.State),
			WatchedAt:  row.WatchedAt.Time,
			CreatedAt:  row.CreatedAt.Time,
			UpdatedAt:  row.UpdatedAt.Time,
		})
	}

	return movies, total, err
}

func (m *movie) Create(ctx context.Context, params *models.Movie) (*models.Movie, error) {
	result, err := m.client.Queries().CreateMovie(ctx, db.CreateMovieParams{
		UserID:     params.UserId,
		TmdbID:     params.TmdbId,
		Title:      params.Title,
		PosterPath: params.PosterPath,
		Runtime:    params.Runtime,
		State:      db.StateTypes(params.State),
	})
	if err != nil {
		return nil, err
	}

	return &models.Movie{
		ID:         result.ID,
		UserId:     result.UserID,
		TmdbId:     result.TmdbID,
		Title:      result.Title,
		PosterPath: result.PosterPath,
		Runtime:    result.Runtime,
		State:      models.StateType(result.State),
		Pinned:     result.Pinned,
		WatchedAt:  result.WatchedAt.Time,
		CreatedAt:  result.CreatedAt.Time,
		UpdatedAt:  result.UpdatedAt.Time,
	}, nil
}

func (m *movie) Update(ctx context.Context, params *models.Movie) (*models.Movie, error) {
	result, err := m.client.Queries().UpdateMovie(ctx, db.UpdateMovieParams{
		ID:         params.ID,
		Title:      params.Title,
		PosterPath: params.PosterPath,
		Runtime:    params.Runtime,
	})
	if err != nil {
		return nil, err
	}

	return &models.Movie{
		ID:         result.ID,
		UserId:     result.UserID,
		TmdbId:     result.TmdbID,
		Title:      result.Title,
		PosterPath: result.PosterPath,
		Runtime:    result.Runtime,
		State:      models.StateType(result.State),
		Pinned:     result.Pinned,
		WatchedAt:  result.WatchedAt.Time,
		CreatedAt:  result.CreatedAt.Time,
		UpdatedAt:  result.UpdatedAt.Time,
	}, nil
}

func (m *movie) UpdateByTmdbId(ctx context.Context, params *models.Movie) (*models.Movie, error) {
	result, err := m.client.Queries().UpdateMovieByTmdbId(ctx, db.UpdateMovieByTmdbIdParams{
		TmdbID: params.TmdbId,
		UserID: params.UserId,
		State:  db.StateTypes(params.State),
		Pinned: params.Pinned,
	})
	if err != nil {
		return nil, err
	}

	return &models.Movie{
		ID:         result.ID,
		UserId:     result.UserID,
		TmdbId:     result.TmdbID,
		Title:      result.Title,
		PosterPath: result.PosterPath,
		Runtime:    result.Runtime,
		State:      models.StateType(result.State),
		Pinned:     result.Pinned,
		WatchedAt:  result.WatchedAt.Time,
		CreatedAt:  result.CreatedAt.Time,
		UpdatedAt:  result.UpdatedAt.Time,
	}, nil
}

func (m *movie) Delete(ctx context.Context, tmdbId uint64, userId uuid.UUID) error {
	return m.client.Queries().DeleteMovieByTmdbId(ctx, db.DeleteMovieByTmdbIdParams{
		TmdbID: tmdbId,
		UserID: userId,
	})
}

func (m *movie) FindByFilter(ctx context.Context, filter models.MovieFilter) ([]models.Movie, error) {
	rows, err := m.client.Queries().FindMoviesByTmdbIds(ctx, db.FindMoviesByTmdbIdsParams{
		TmdbIds: toInt32Slice(filter.TmdbIds),
		UserID:  filter.UserId,
	})
	if err != nil {
		return nil, err
	}

	movies := make([]models.Movie, 0, len(rows))
	for _, row := range rows {
		movies = append(movies, models.Movie{
			ID:         row.ID,
			UserId:     row.UserID,
			TmdbId:     row.TmdbID,
			Title:      row.Title,
			PosterPath: row.PosterPath,
			Runtime:    row.Runtime,
			State:      models.StateType(row.State),
			Pinned:     row.Pinned,
			WatchedAt:  row.WatchedAt.Time,
			CreatedAt:  row.CreatedAt.Time,
			UpdatedAt:  row.UpdatedAt.Time,
		})
	}

	return movies, nil
}
