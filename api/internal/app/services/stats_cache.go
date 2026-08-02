package services

import (
	"context"
	"fmt"

	"github.com/google/uuid"

	"biinge-api/internal/app/models"
	"biinge-api/internal/config/cache"
	"biinge-api/internal/config/logger"
)

// StatsCache holds a user's rendered statistics per period. It sits between the stats
// service and the store so the write paths can drop an entry without depending on the
// service that reads it
type StatsCache interface {
	Fetch(ctx context.Context, userId uuid.UUID, period models.StatsPeriod, source func() (*models.Stats, error)) (*models.Stats, error)
	Invalidate(ctx context.Context, userId uuid.UUID)
}

type statsCache struct {
	store cache.Cache
	log   *logger.Logger
}

func NewStatsCache(store cache.Cache, log *logger.Logger) StatsCache {
	return &statsCache{
		store: store,
		log:   log.WithComponent("StatsCache"),
	}
}

// Fetch returns the cached statistics for the period, otherwise computes and stores them
func (c *statsCache) Fetch(ctx context.Context, userId uuid.UUID, period models.StatsPeriod, source func() (*models.Stats, error)) (*models.Stats, error) {
	return cache.Fetch(ctx, c.store, c.log, statsCacheKey(userId, period), cache.StatsTTL, source)
}

// Invalidate drops every period at once, since a single watch moves the counts in all
// of them. A failure only costs staleness until the entries expire, so it never fails
// the write that triggered it
func (c *statsCache) Invalidate(ctx context.Context, userId uuid.UUID) {
	keys := make([]string, 0, len(models.StatsPeriods))
	for _, period := range models.StatsPeriods {
		keys = append(keys, statsCacheKey(userId, period))
	}

	if err := c.store.Delete(ctx, keys...); err != nil {
		c.log.Warn().Err(err).Str("userId", userId.String()).Msg("Failed to invalidate stats cache")
	}
}

// statsCacheKey namespaces an entry by user and period
func statsCacheKey(userId uuid.UUID, period models.StatsPeriod) string {
	return fmt.Sprintf("stats:v2:%s:%s", userId, period)
}
