package repositories

import (
	"context"

	"github.com/google/uuid"

	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories/db"
	"biinge-api/internal/app/repositories/postgres"
)

type EpisodeRepository interface {
	List(ctx context.Context, seasonId, userId uuid.UUID) ([]models.Episode, error)
	Create(ctx context.Context, params *models.Episode) (*models.Episode, error)
	Update(ctx context.Context, userId uuid.UUID, params *models.Episode) (*models.Episode, error)
	UpdateByTmdbId(ctx context.Context, userId uuid.UUID, tmdbId uint64, state string) (*models.Episode, error)
	Delete(ctx context.Context, id uuid.UUID) error
	FindById(ctx context.Context, id, userId uuid.UUID) (*models.Episode, error)
	Count(ctx context.Context, seasonId, userId uuid.UUID) (uint64, error)
	CountWatched(ctx context.Context, seasonId, userId uuid.UUID, state string) (uint64, error)
}

type episode struct {
	client postgres.Postgres
}

func NewEpisodeRepository(client postgres.Postgres) EpisodeRepository {
	return &episode{client: client}
}

func (e *episode) List(ctx context.Context, seasonId, userId uuid.UUID) ([]models.Episode, error) {
	rows, err := e.client.Queries().FindEpisodesBySeasonId(ctx, db.FindEpisodesBySeasonIdParams{
		SeasonID: seasonId,
		UserID:   userId,
	})
	if err != nil {
		return nil, err
	}

	collection := make([]models.Episode, 0, len(rows))
	for _, row := range rows {
		collection = append(collection, *episodeFromRow(row))
	}

	return collection, nil
}

func (e *episode) Create(ctx context.Context, params *models.Episode) (*models.Episode, error) {
	result, err := e.client.Queries().CreateEpisode(ctx, db.CreateEpisodeParams{
		SeasonID:   params.SeasonId,
		TmdbID:     params.TmdbId,
		Title:      params.Title,
		PosterPath: params.PosterPath,
		Runtime:    params.Runtime,
		State:      db.StateTypes(params.State),
		AirAt:      timestampFromTime(params.AirAt),
	})
	if err != nil {
		return nil, err
	}

	return episodeFromRow(result), nil
}

func (e *episode) Update(ctx context.Context, userId uuid.UUID, params *models.Episode) (*models.Episode, error) {
	result, err := e.client.Queries().UpdateEpisode(ctx, db.UpdateEpisodeParams{
		ID:         params.ID,
		UserID:     userId,
		Title:      params.Title,
		PosterPath: params.PosterPath,
		Runtime:    params.Runtime,
		AirAt:      timestampFromTime(params.AirAt),
		State:      db.StateTypes(params.State),
	})
	if err != nil {
		return nil, err
	}

	return episodeFromRow(result), nil
}

func (e *episode) UpdateByTmdbId(ctx context.Context, userId uuid.UUID, tmdbId uint64, state string) (*models.Episode, error) {
	result, err := e.client.Queries().UpdateEpisodeByTmdbId(ctx, db.UpdateEpisodeByTmdbIdParams{
		TmdbID: tmdbId,
		UserID: userId,
		State:  db.StateTypes(state),
	})
	if err != nil {
		return nil, err
	}

	return episodeFromRow(result), nil
}

func (e *episode) Delete(ctx context.Context, id uuid.UUID) error {
	return e.client.Queries().DeleteEpisode(ctx, id)
}

func (e *episode) FindById(ctx context.Context, id, userId uuid.UUID) (*models.Episode, error) {
	result, err := e.client.Queries().FindEpisodeById(ctx, db.FindEpisodeByIdParams{
		ID:     id,
		UserID: userId,
	})
	if err != nil {
		return nil, err
	}

	return episodeFromRow(result), nil
}

func (e *episode) Count(ctx context.Context, seasonId, userId uuid.UUID) (uint64, error) {
	count, err := e.client.Queries().CountEpisodesBySeasonId(ctx, db.CountEpisodesBySeasonIdParams{
		SeasonID: seasonId,
		UserID:   userId,
	})
	if err != nil {
		return 0, err
	}

	return uint64(count), nil
}

func (e *episode) CountWatched(ctx context.Context, seasonId, userId uuid.UUID, state string) (uint64, error) {
	count, err := e.client.Queries().CountWatchedEpisodesBySeasonId(ctx, db.CountWatchedEpisodesBySeasonIdParams{
		SeasonID: seasonId,
		UserID:   userId,
		State:    db.StateTypes(state),
	})
	if err != nil {
		return 0, err
	}

	return uint64(count), nil
}

func episodeFromRow(row db.Episode) *models.Episode {
	return &models.Episode{
		ID:         row.ID,
		SeasonId:   row.SeasonID,
		TmdbId:     row.TmdbID,
		Title:      row.Title,
		PosterPath: row.PosterPath,
		Runtime:    row.Runtime,
		State:      string(row.State),
		AirAt:      row.AirAt.Time,
		CreatedAt:  row.CreatedAt.Time,
		UpdatedAt:  row.UpdatedAt.Time,
	}
}
