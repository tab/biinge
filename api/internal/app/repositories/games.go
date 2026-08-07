package repositories

import (
	"context"

	"github.com/google/uuid"

	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories/db"
	"biinge-api/internal/app/repositories/postgres"
)

type GameRepository interface {
	List(ctx context.Context, userId uuid.UUID, state models.StateType, limit, offset uint64) ([]models.Game, uint64, error)
	Create(ctx context.Context, params *models.Game) (*models.Game, error)
	Update(ctx context.Context, params *models.Game) (*models.Game, error)
	UpdateByIgdbId(ctx context.Context, params *models.Game) (*models.Game, error)
	DeleteByIgdbId(ctx context.Context, igdbId uint64, userId uuid.UUID) error
	FindByIgdbId(ctx context.Context, igdbId uint64, userId uuid.UUID) (*models.Game, error)
	FindGamesByIgdbIds(ctx context.Context, igdbIds []uint64, userId uuid.UUID) ([]models.Game, error)
}

type game struct {
	client postgres.Postgres
}

func NewGameRepository(client postgres.Postgres) GameRepository {
	return &game{client: client}
}

func (g *game) List(ctx context.Context, userId uuid.UUID, state models.StateType, limit, offset uint64) ([]models.Game, uint64, error) {
	rows, err := g.client.Queries().FindGamesByState(ctx, db.FindGamesByStateParams{
		UserID: userId,
		State:  db.StateTypes(state),
		Limit:  int32(limit),
		Offset: int32(offset),
	})
	if err != nil {
		return nil, 0, err
	}

	games := make([]models.Game, 0, len(rows))

	var total uint64

	if len(rows) > 0 {
		total = uint64(rows[0].Total)
	}

	for _, row := range rows {
		games = append(games, models.Game{
			ID:         row.ID,
			UserId:     row.UserID,
			IgdbId:     row.IgdbID,
			Title:      row.Title,
			PosterPath: row.PosterPath,
			Runtime:    row.Runtime,
			Pinned:     row.Pinned,
			State:      models.StateType(row.State),
			PlayedAt:   row.PlayedAt.Time,
			CreatedAt:  row.CreatedAt.Time,
			UpdatedAt:  row.UpdatedAt.Time,
		})
	}

	return games, total, nil
}

func (g *game) Create(ctx context.Context, params *models.Game) (*models.Game, error) {
	result, err := g.client.Queries().CreateGame(ctx, db.CreateGameParams{
		UserID:     params.UserId,
		IgdbID:     params.IgdbId,
		Title:      params.Title,
		PosterPath: params.PosterPath,
		Runtime:    params.Runtime,
		State:      db.StateTypes(params.State),
	})
	if err != nil {
		return nil, err
	}

	return &models.Game{
		ID:         result.ID,
		UserId:     result.UserID,
		IgdbId:     result.IgdbID,
		Title:      result.Title,
		PosterPath: result.PosterPath,
		Runtime:    result.Runtime,
		State:      models.StateType(result.State),
		Pinned:     result.Pinned,
		PlayedAt:   result.PlayedAt.Time,
		CreatedAt:  result.CreatedAt.Time,
		UpdatedAt:  result.UpdatedAt.Time,
	}, nil
}

func (g *game) Update(ctx context.Context, params *models.Game) (*models.Game, error) {
	result, err := g.client.Queries().UpdateGame(ctx, db.UpdateGameParams{
		ID:         params.ID,
		Title:      params.Title,
		PosterPath: params.PosterPath,
		Runtime:    params.Runtime,
	})
	if err != nil {
		return nil, err
	}

	return &models.Game{
		ID:         result.ID,
		UserId:     result.UserID,
		IgdbId:     result.IgdbID,
		Title:      result.Title,
		PosterPath: result.PosterPath,
		Runtime:    result.Runtime,
		State:      models.StateType(result.State),
		Pinned:     result.Pinned,
		PlayedAt:   result.PlayedAt.Time,
		CreatedAt:  result.CreatedAt.Time,
		UpdatedAt:  result.UpdatedAt.Time,
	}, nil
}

func (g *game) UpdateByIgdbId(ctx context.Context, params *models.Game) (*models.Game, error) {
	result, err := g.client.Queries().UpdateGameByIgdbId(ctx, db.UpdateGameByIgdbIdParams{
		IgdbID: params.IgdbId,
		UserID: params.UserId,
		State:  db.StateTypes(params.State),
		Pinned: params.Pinned,
	})
	if err != nil {
		return nil, err
	}

	return &models.Game{
		ID:         result.ID,
		UserId:     result.UserID,
		IgdbId:     result.IgdbID,
		Title:      result.Title,
		PosterPath: result.PosterPath,
		Runtime:    result.Runtime,
		State:      models.StateType(result.State),
		Pinned:     result.Pinned,
		PlayedAt:   result.PlayedAt.Time,
		CreatedAt:  result.CreatedAt.Time,
		UpdatedAt:  result.UpdatedAt.Time,
	}, nil
}

func (g *game) DeleteByIgdbId(ctx context.Context, igdbId uint64, userId uuid.UUID) error {
	return g.client.Queries().DeleteGameByIgdbId(ctx, db.DeleteGameByIgdbIdParams{
		IgdbID: igdbId,
		UserID: userId,
	})
}

func (g *game) FindByIgdbId(ctx context.Context, igdbId uint64, userId uuid.UUID) (*models.Game, error) {
	result, err := g.client.Queries().FindGameByIgdbId(ctx, db.FindGameByIgdbIdParams{
		IgdbID: igdbId,
		UserID: userId,
	})
	if err != nil {
		return nil, err
	}

	return &models.Game{
		ID:         result.ID,
		UserId:     result.UserID,
		IgdbId:     result.IgdbID,
		Title:      result.Title,
		PosterPath: result.PosterPath,
		Runtime:    result.Runtime,
		State:      models.StateType(result.State),
		Pinned:     result.Pinned,
		PlayedAt:   result.PlayedAt.Time,
		CreatedAt:  result.CreatedAt.Time,
		UpdatedAt:  result.UpdatedAt.Time,
	}, nil
}

func (g *game) FindGamesByIgdbIds(ctx context.Context, igdbIds []uint64, userId uuid.UUID) ([]models.Game, error) {
	rows, err := g.client.Queries().FindGamesByIgdbIds(ctx, db.FindGamesByIgdbIdsParams{
		IgdbIds: toInt32Slice(igdbIds),
		UserID:  userId,
	})
	if err != nil {
		return nil, err
	}

	games := make([]models.Game, 0, len(rows))
	for _, row := range rows {
		games = append(games, models.Game{
			ID:         row.ID,
			UserId:     row.UserID,
			IgdbId:     row.IgdbID,
			Title:      row.Title,
			PosterPath: row.PosterPath,
			Runtime:    row.Runtime,
			State:      models.StateType(row.State),
			Pinned:     row.Pinned,
			PlayedAt:   row.PlayedAt.Time,
			CreatedAt:  row.CreatedAt.Time,
			UpdatedAt:  row.UpdatedAt.Time,
		})
	}

	return games, nil
}
