package services

import (
	"context"

	"github.com/google/uuid"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories"
	"biinge-api/internal/config/logger"
)

type Stats interface {
	Get(ctx context.Context, userId uuid.UUID, period models.StatsPeriod) (*models.Stats, error)
}

type stats struct {
	repository repositories.StatsRepository
	cache      StatsCache
	log        *logger.Logger
}

func NewStats(repository repositories.StatsRepository, cache StatsCache, log *logger.Logger) Stats {
	return &stats{
		repository: repository,
		cache:      cache,
		log:        log.WithComponent("StatsService"),
	}
}

func (s *stats) Get(ctx context.Context, userId uuid.UUID, period models.StatsPeriod) (*models.Stats, error) {
	result, err := s.cache.Fetch(ctx, userId, period, func() (*models.Stats, error) {
		return s.repository.Get(ctx, userId, period)
	})
	if err != nil {
		s.log.Error().Err(err).Msg("Failed to fetch stats")
		return nil, errors.ErrFailedToFetchStats
	}

	return result, nil
}
