package services

import (
	"context"

	"github.com/google/uuid"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories"
	"biinge-api/internal/config/logger"
)

type Games interface {
	List(ctx context.Context, userId uuid.UUID, state models.StateType, pagination *Pagination) ([]models.Game, uint64, error)
	Create(ctx context.Context, params *models.Game) (*models.Game, error)
	Update(ctx context.Context, params *models.Game) (*models.Game, error)
	UpdateByIgdbId(ctx context.Context, params *models.Game) (*models.Game, error)
	Delete(ctx context.Context, igdbId uint64, userId uuid.UUID) error
	FindByFilter(ctx context.Context, filter models.GameFilter) ([]models.Game, error)
}

type games struct {
	repository repositories.GameRepository
	stats      StatsCache
	log        *logger.Logger
}

func NewGames(repository repositories.GameRepository, stats StatsCache, log *logger.Logger) Games {
	return &games{
		repository: repository,
		stats:      stats,
		log:        log.WithComponent("GamesService"),
	}
}

func (g *games) List(ctx context.Context, userId uuid.UUID, state models.StateType, pagination *Pagination) ([]models.Game, uint64, error) {
	collection, total, err := g.repository.List(ctx, userId, state, pagination.Limit(), pagination.Offset())
	if err != nil {
		g.log.Error().Err(err).Msg("Failed to fetch games")
		return nil, 0, errors.ErrFailedToFetchGames
	}

	return collection, total, nil
}

func (g *games) Create(ctx context.Context, params *models.Game) (*models.Game, error) {
	item, err := g.repository.Create(ctx, &models.Game{
		UserId:     params.UserId,
		IgdbId:     params.IgdbId,
		Title:      params.Title,
		PosterPath: params.PosterPath,
		Runtime:    params.Runtime,
		State:      params.State,
	})
	if err != nil {
		g.log.Error().Err(err).Msg("Failed to create game")
		return nil, errors.ErrFailedToCreateGame
	}

	g.stats.Invalidate(ctx, params.UserId)

	return item, nil
}

func (g *games) Update(ctx context.Context, params *models.Game) (*models.Game, error) {
	item, err := g.repository.Update(ctx, &models.Game{
		ID:         params.ID,
		Title:      params.Title,
		PosterPath: params.PosterPath,
		Runtime:    params.Runtime,
	})
	if err != nil {
		g.log.Error().Err(err).Msg("Failed to update game")
		return nil, errors.ErrFailedToUpdateGame
	}

	return item, nil
}

func (g *games) UpdateByIgdbId(ctx context.Context, params *models.Game) (*models.Game, error) {
	item, err := g.repository.UpdateByIgdbId(ctx, &models.Game{
		IgdbId: params.IgdbId,
		UserId: params.UserId,
		State:  params.State,
		Pinned: params.Pinned,
	})
	if err != nil {
		g.log.Error().Err(err).Msg("Failed to update game by IGDB Id")
		return nil, errors.ErrFailedToUpdateGame
	}

	g.stats.Invalidate(ctx, params.UserId)

	return item, nil
}

func (g *games) Delete(ctx context.Context, igdbId uint64, userId uuid.UUID) error {
	err := g.repository.Delete(ctx, igdbId, userId)
	if err != nil {
		g.log.Error().Err(err).Msg("Failed to delete game by IGDB Id")
		return errors.ErrFailedToDeleteGame
	}

	g.stats.Invalidate(ctx, userId)

	return nil
}

func (g *games) FindByFilter(ctx context.Context, filter models.GameFilter) ([]models.Game, error) {
	collection, err := g.repository.FindByFilter(ctx, filter)
	if err != nil {
		g.log.Error().Err(err).Msg("Failed to fetch games by IGDB Ids")
		return nil, errors.ErrFailedToFetchResults
	}

	return collection, nil
}
