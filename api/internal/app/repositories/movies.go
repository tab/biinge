package repositories

import (
	"context"

	"github.com/google/uuid"

	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories/db"
	"biinge-api/internal/app/repositories/postgres"
)

type MovieRepository interface {
	List(ctx context.Context, userId uuid.UUID, state string, limit, offset uint64) ([]models.Movie, uint64, error)
	Create(ctx context.Context, params *models.Movie) (*models.Movie, error)
	Update(ctx context.Context, params *models.Movie) (*models.Movie, error)
	UpdateByTmdbId(ctx context.Context, params *models.Movie) (*models.Movie, error)
	Delete(ctx context.Context, id uuid.UUID) error
	DeleteByTmdbId(ctx context.Context, tmdbId uint64, userId uuid.UUID) error
	FindById(ctx context.Context, id uuid.UUID) (*models.Movie, error)
	FindByTmdbId(ctx context.Context, tmdbId uint64, userId uuid.UUID) (*models.Movie, error)
	FindMoviesByTmdbIds(ctx context.Context, tmdbIds []uint64, userId uuid.UUID) ([]models.Movie, error)
}

type movie struct {
	client postgres.Postgres
}

func NewMovieRepository(client postgres.Postgres) MovieRepository {
	return &movie{client: client}
}

func (m *movie) List(ctx context.Context, userId uuid.UUID, state string, limit, offset uint64) ([]models.Movie, uint64, error) {
	rows, err := m.client.Queries().FindMoviesByState(ctx, db.FindMoviesByStateParams{
		UserID: userId,
		State:  db.StateTypes(state),
		Limit:  limit,
		Offset: offset,
	})
	if err != nil {
		return nil, 0, err
	}

	movies := make([]models.Movie, 0, len(rows))
	var total uint64

	if len(rows) > 0 {
		total = rows[0].Total
	}

	for _, row := range rows {
		movies = append(movies, models.Movie{
			ID:         row.ID,
			UserId:     row.UserID,
			TmdbId:     row.TmdbID,
			Title:      row.Title,
			PosterPath: row.PosterPath,
			Pinned:     row.Pinned,
			State:      string(row.State),
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
		State:      string(result.State),
		Pinned:     result.Pinned,
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
		State:      string(result.State),
		Pinned:     result.Pinned,
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
		State:      string(result.State),
		Pinned:     result.Pinned,
		CreatedAt:  result.CreatedAt.Time,
		UpdatedAt:  result.UpdatedAt.Time,
	}, nil
}

func (m *movie) Delete(ctx context.Context, id uuid.UUID) error {
	return m.client.Queries().DeleteMovie(ctx, id)
}

func (m *movie) DeleteByTmdbId(ctx context.Context, tmdbId uint64, userId uuid.UUID) error {
	return m.client.Queries().DeleteMovieByTmdbId(ctx, db.DeleteMovieByTmdbIdParams{
		TmdbID: tmdbId,
		UserID: userId,
	})
}

func (m *movie) FindById(ctx context.Context, id uuid.UUID) (*models.Movie, error) {
	result, err := m.client.Queries().FindMovieById(ctx, id)
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
		State:      string(result.State),
		Pinned:     result.Pinned,
		CreatedAt:  result.CreatedAt.Time,
		UpdatedAt:  result.UpdatedAt.Time,
	}, nil
}

func (m *movie) FindByTmdbId(ctx context.Context, tmdbId uint64, userId uuid.UUID) (*models.Movie, error) {
	result, err := m.client.Queries().FindMovieByTmdbId(ctx, db.FindMovieByTmdbIdParams{
		TmdbID: tmdbId,
		UserID: userId,
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
		State:      string(result.State),
		Pinned:     result.Pinned,
		CreatedAt:  result.CreatedAt.Time,
		UpdatedAt:  result.UpdatedAt.Time,
	}, nil
}

func (m *movie) FindMoviesByTmdbIds(ctx context.Context, tmdbIds []uint64, userId uuid.UUID) ([]models.Movie, error) {
	rows, err := m.client.Queries().FindMoviesByTmdbIds(ctx, db.FindMoviesByTmdbIdsParams{
		TmdbIds: tmdbIds,
		UserID:  userId,
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
			State:      string(row.State),
			Pinned:     row.Pinned,
			CreatedAt:  row.CreatedAt.Time,
			UpdatedAt:  row.UpdatedAt.Time,
		})
	}

	return movies, nil
}
