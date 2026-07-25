package repositories

import (
	"context"

	"github.com/google/uuid"

	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories/db"
	"biinge-api/internal/app/repositories/postgres"
)

type SeriesRepository interface {
	List(ctx context.Context, userId uuid.UUID, state models.StateType, limit, offset uint64) ([]models.Series, uint64, error)
	Create(ctx context.Context, params *models.Series) (*models.Series, error)
	Update(ctx context.Context, params *models.Series) (*models.Series, error)
	UpdateByTmdbId(ctx context.Context, params *models.Series) (*models.Series, error)
	Delete(ctx context.Context, id uuid.UUID) error
	DeleteByTmdbId(ctx context.Context, tmdbId uint64, userId uuid.UUID) error
	FindById(ctx context.Context, id uuid.UUID) (*models.Series, error)
	FindByTmdbId(ctx context.Context, tmdbId uint64, userId uuid.UUID) (*models.Series, error)
	FindSeriesByTmdbIds(ctx context.Context, tmdbIds []uint64, userId uuid.UUID) ([]models.Series, error)
}

type series struct {
	client postgres.Postgres
}

func NewSeriesRepository(client postgres.Postgres) SeriesRepository {
	return &series{client: client}
}

func (s *series) List(ctx context.Context, userId uuid.UUID, state models.StateType, limit, offset uint64) ([]models.Series, uint64, error) {
	rows, err := s.client.Queries().FindSeriesByState(ctx, db.FindSeriesByStateParams{
		UserID: userId,
		State:  db.StateTypes(state),
		Limit:  int32(limit),
		Offset: int32(offset),
	})
	if err != nil {
		return nil, 0, err
	}

	collection := make([]models.Series, 0, len(rows))

	var total uint64

	if len(rows) > 0 {
		total = uint64(rows[0].Total)
	}

	for _, row := range rows {
		collection = append(collection, models.Series{
			ID:                   row.ID,
			UserId:               row.UserID,
			TmdbId:               row.TmdbID,
			Title:                row.Title,
			PosterPath:           row.PosterPath,
			EpisodesCount:        row.EpisodesCount,
			WatchedEpisodesCount: uint64(row.WatchedEpisodesCount),
			Pinned:               row.Pinned,
			State:                models.StateType(row.State),
			CreatedAt:            row.CreatedAt.Time,
			UpdatedAt:            row.UpdatedAt.Time,
		})
	}

	return collection, total, nil
}

func (s *series) Create(ctx context.Context, params *models.Series) (*models.Series, error) {
	result, err := s.client.Queries().CreateSeries(ctx, db.CreateSeriesParams{
		UserID:        params.UserId,
		TmdbID:        params.TmdbId,
		Title:         params.Title,
		PosterPath:    params.PosterPath,
		SeasonsCount:  params.SeasonsCount,
		EpisodesCount: params.EpisodesCount,
		Status:        params.Status,
		State:         db.StateTypes(params.State),
	})
	if err != nil {
		return nil, err
	}

	return seriesFromRow(result), nil
}

func (s *series) Update(ctx context.Context, params *models.Series) (*models.Series, error) {
	result, err := s.client.Queries().UpdateSeries(ctx, db.UpdateSeriesParams{
		ID:            params.ID,
		Title:         params.Title,
		PosterPath:    params.PosterPath,
		SeasonsCount:  params.SeasonsCount,
		EpisodesCount: params.EpisodesCount,
		Status:        params.Status,
	})
	if err != nil {
		return nil, err
	}

	return seriesFromRow(result), nil
}

func (s *series) UpdateByTmdbId(ctx context.Context, params *models.Series) (*models.Series, error) {
	result, err := s.client.Queries().UpdateSeriesByTmdbId(ctx, db.UpdateSeriesByTmdbIdParams{
		TmdbID: params.TmdbId,
		UserID: params.UserId,
		State:  db.StateTypes(params.State),
		Pinned: params.Pinned,
	})
	if err != nil {
		return nil, err
	}

	return seriesFromRow(result), nil
}

func (s *series) Delete(ctx context.Context, id uuid.UUID) error {
	return s.client.Queries().DeleteSeries(ctx, id)
}

func (s *series) DeleteByTmdbId(ctx context.Context, tmdbId uint64, userId uuid.UUID) error {
	return s.client.Queries().DeleteSeriesByTmdbId(ctx, db.DeleteSeriesByTmdbIdParams{
		TmdbID: tmdbId,
		UserID: userId,
	})
}

func (s *series) FindById(ctx context.Context, id uuid.UUID) (*models.Series, error) {
	result, err := s.client.Queries().FindSeriesById(ctx, id)
	if err != nil {
		return nil, err
	}

	return seriesFromRow(result), nil
}

func (s *series) FindByTmdbId(ctx context.Context, tmdbId uint64, userId uuid.UUID) (*models.Series, error) {
	result, err := s.client.Queries().FindSeriesByTmdbId(ctx, db.FindSeriesByTmdbIdParams{
		TmdbID: tmdbId,
		UserID: userId,
	})
	if err != nil {
		return nil, err
	}

	return seriesFromRow(result), nil
}

func (s *series) FindSeriesByTmdbIds(ctx context.Context, tmdbIds []uint64, userId uuid.UUID) ([]models.Series, error) {
	rows, err := s.client.Queries().FindSeriesByTmdbIds(ctx, db.FindSeriesByTmdbIdsParams{
		TmdbIds: toInt32Slice(tmdbIds),
		UserID:  userId,
	})
	if err != nil {
		return nil, err
	}

	collection := make([]models.Series, 0, len(rows))
	for _, row := range rows {
		collection = append(collection, *seriesFromRow(row))
	}

	return collection, nil
}

func seriesFromRow(row db.Series) *models.Series {
	return &models.Series{
		ID:            row.ID,
		UserId:        row.UserID,
		TmdbId:        row.TmdbID,
		Title:         row.Title,
		PosterPath:    row.PosterPath,
		SeasonsCount:  row.SeasonsCount,
		EpisodesCount: row.EpisodesCount,
		Status:        row.Status,
		State:         models.StateType(row.State),
		Pinned:        row.Pinned,
		CreatedAt:     row.CreatedAt.Time,
		UpdatedAt:     row.UpdatedAt.Time,
	}
}
