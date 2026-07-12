package repositories

import (
	"context"

	"github.com/google/uuid"

	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories/db"
	"biinge-api/internal/app/repositories/postgres"
)

type SeasonRepository interface {
	List(ctx context.Context, seriesId, userId uuid.UUID) ([]models.Season, error)
	Create(ctx context.Context, params *models.Season) (*models.Season, error)
	Update(ctx context.Context, userId uuid.UUID, params *models.Season) (*models.Season, error)
	UpdateByTmdbId(ctx context.Context, userId uuid.UUID, tmdbId uint64, state string) (*models.Season, error)
	Delete(ctx context.Context, id uuid.UUID) error
	FindById(ctx context.Context, id uuid.UUID) (*models.Season, error)
	CountWatched(ctx context.Context, seriesId, userId uuid.UUID, state string) (uint64, error)
}

type season struct {
	client postgres.Postgres
}

func NewSeasonRepository(client postgres.Postgres) SeasonRepository {
	return &season{client: client}
}

func (s *season) List(ctx context.Context, seriesId, userId uuid.UUID) ([]models.Season, error) {
	rows, err := s.client.Queries().FindSeasonsBySeriesId(ctx, db.FindSeasonsBySeriesIdParams{
		SeriesID: seriesId,
		UserID:   userId,
	})
	if err != nil {
		return nil, err
	}

	collection := make([]models.Season, 0, len(rows))
	for _, row := range rows {
		collection = append(collection, *seasonFromRow(row))
	}

	return collection, nil
}

func (s *season) Create(ctx context.Context, params *models.Season) (*models.Season, error) {
	result, err := s.client.Queries().CreateSeason(ctx, db.CreateSeasonParams{
		SeriesID:      params.SeriesId,
		TmdbID:        params.TmdbId,
		Title:         params.Title,
		Number:        params.Number,
		EpisodesCount: params.EpisodesCount,
		State:         db.StateTypes(params.State),
	})
	if err != nil {
		return nil, err
	}

	return seasonFromRow(result), nil
}

func (s *season) Update(ctx context.Context, userId uuid.UUID, params *models.Season) (*models.Season, error) {
	result, err := s.client.Queries().UpdateSeason(ctx, db.UpdateSeasonParams{
		ID:            params.ID,
		UserID:        userId,
		Title:         params.Title,
		Number:        params.Number,
		EpisodesCount: params.EpisodesCount,
	})
	if err != nil {
		return nil, err
	}

	return seasonFromRow(result), nil
}

func (s *season) UpdateByTmdbId(ctx context.Context, userId uuid.UUID, tmdbId uint64, state string) (*models.Season, error) {
	result, err := s.client.Queries().UpdateSeasonByTmdbId(ctx, db.UpdateSeasonByTmdbIdParams{
		TmdbID: tmdbId,
		UserID: userId,
		State:  db.StateTypes(state),
	})
	if err != nil {
		return nil, err
	}

	return seasonFromRow(result), nil
}

func (s *season) Delete(ctx context.Context, id uuid.UUID) error {
	return s.client.Queries().DeleteSeason(ctx, id)
}

func (s *season) FindById(ctx context.Context, id uuid.UUID) (*models.Season, error) {
	result, err := s.client.Queries().FindSeasonById(ctx, id)
	if err != nil {
		return nil, err
	}

	return seasonFromRow(result), nil
}

func (s *season) CountWatched(ctx context.Context, seriesId, userId uuid.UUID, state string) (uint64, error) {
	count, err := s.client.Queries().CountWatchedSeasonsBySeriesId(ctx, db.CountWatchedSeasonsBySeriesIdParams{
		SeriesID: seriesId,
		UserID:   userId,
		State:    db.StateTypes(state),
	})
	if err != nil {
		return 0, err
	}

	return uint64(count), nil
}

func seasonFromRow(row db.Season) *models.Season {
	return &models.Season{
		ID:            row.ID,
		SeriesId:      row.SeriesID,
		TmdbId:        row.TmdbID,
		Title:         row.Title,
		Number:        row.Number,
		EpisodesCount: row.EpisodesCount,
		State:         string(row.State),
		CreatedAt:     row.CreatedAt.Time,
		UpdatedAt:     row.UpdatedAt.Time,
	}
}
