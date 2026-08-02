package services

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"biinge-api/internal/app/models"
)

// memoryCache is an in-memory cache.Cache with injectable errors
type memoryCache struct {
	store     map[string][]byte
	deleteErr error
	deleted   []string
}

func newMemoryCache() *memoryCache {
	return &memoryCache{store: map[string][]byte{}}
}

func (c *memoryCache) Get(_ context.Context, key string) ([]byte, bool, error) {
	data, ok := c.store[key]

	return data, ok, nil
}

func (c *memoryCache) Set(_ context.Context, key string, value []byte, _ time.Duration) error {
	c.store[key] = value

	return nil
}

func (c *memoryCache) Delete(_ context.Context, keys ...string) error {
	c.deleted = append(c.deleted, keys...)
	if c.deleteErr != nil {
		return c.deleteErr
	}

	for _, key := range keys {
		delete(c.store, key)
	}

	return nil
}

func Test_StatsCache_Fetch(t *testing.T) {
	ctx := context.Background()
	userId := uuid.New()

	t.Run("Miss computes and stores the period", func(t *testing.T) {
		store := newMemoryCache()
		statsCache := NewStatsCache(store, newTestLogger())
		calls := 0

		result, err := statsCache.Fetch(ctx, userId, models.StatsPeriodWeek, func() (*models.Stats, error) {
			calls++
			return &models.Stats{Period: models.StatsPeriodWeek, MoviesWatched: 3}, nil
		})

		require.NoError(t, err)
		assert.Equal(t, uint64(3), result.MoviesWatched)
		assert.Equal(t, 1, calls)
		assert.Contains(t, store.store, statsCacheKey(userId, models.StatsPeriodWeek))
	})

	t.Run("Hit skips the source", func(t *testing.T) {
		store := newMemoryCache()
		statsCache := NewStatsCache(store, newTestLogger())

		_, err := statsCache.Fetch(ctx, userId, models.StatsPeriodWeek, func() (*models.Stats, error) {
			return &models.Stats{Period: models.StatsPeriodWeek, MoviesWatched: 3}, nil
		})
		require.NoError(t, err)

		result, err := statsCache.Fetch(ctx, userId, models.StatsPeriodWeek, func() (*models.Stats, error) {
			t.Fatal("source called on a hit")
			return nil, nil
		})

		require.NoError(t, err)
		assert.Equal(t, uint64(3), result.MoviesWatched)
	})

	t.Run("Round trips the activity buckets", func(t *testing.T) {
		store := newMemoryCache()
		statsCache := NewStatsCache(store, newTestLogger())
		day := time.Date(2026, 7, 20, 0, 0, 0, 0, time.UTC)

		_, err := statsCache.Fetch(ctx, userId, models.StatsPeriodWeek, func() (*models.Stats, error) {
			return &models.Stats{
				Period:   models.StatsPeriodWeek,
				Activity: []models.WatchBucket{{Date: day, MovieMinutes: 120, TvMinutes: 42}},
			}, nil
		})
		require.NoError(t, err)

		result, err := statsCache.Fetch(ctx, userId, models.StatsPeriodWeek, func() (*models.Stats, error) {
			t.Fatal("source called on a hit")
			return nil, nil
		})

		require.NoError(t, err)
		require.Len(t, result.Activity, 1)
		assert.True(t, day.Equal(result.Activity[0].Date))
		assert.Equal(t, uint64(120), result.Activity[0].MovieMinutes)
		assert.Equal(t, uint64(42), result.Activity[0].TvMinutes)
	})

	t.Run("Periods are cached separately", func(t *testing.T) {
		store := newMemoryCache()
		statsCache := NewStatsCache(store, newTestLogger())

		for _, period := range models.StatsPeriods {
			_, err := statsCache.Fetch(ctx, userId, period, func() (*models.Stats, error) {
				return &models.Stats{Period: period}, nil
			})
			require.NoError(t, err)
		}

		assert.Len(t, store.store, len(models.StatsPeriods))
	})

	t.Run("Users are cached separately", func(t *testing.T) {
		store := newMemoryCache()
		statsCache := NewStatsCache(store, newTestLogger())
		other := uuid.New()

		_, err := statsCache.Fetch(ctx, userId, models.StatsPeriodAll, func() (*models.Stats, error) {
			return &models.Stats{MoviesWatched: 1}, nil
		})
		require.NoError(t, err)

		result, err := statsCache.Fetch(ctx, other, models.StatsPeriodAll, func() (*models.Stats, error) {
			return &models.Stats{MoviesWatched: 2}, nil
		})

		require.NoError(t, err)
		assert.Equal(t, uint64(2), result.MoviesWatched)
	})
}

func Test_StatsCache_Invalidate(t *testing.T) {
	ctx := context.Background()
	userId := uuid.New()

	t.Run("Drops every period for the user", func(t *testing.T) {
		store := newMemoryCache()
		statsCache := NewStatsCache(store, newTestLogger())

		for _, period := range models.StatsPeriods {
			_, err := statsCache.Fetch(ctx, userId, period, func() (*models.Stats, error) {
				return &models.Stats{Period: period}, nil
			})
			require.NoError(t, err)
		}

		statsCache.Invalidate(ctx, userId)

		assert.Empty(t, store.store)
		assert.Len(t, store.deleted, len(models.StatsPeriods))
	})

	t.Run("Leaves other users alone", func(t *testing.T) {
		store := newMemoryCache()
		statsCache := NewStatsCache(store, newTestLogger())
		other := uuid.New()

		_, err := statsCache.Fetch(ctx, other, models.StatsPeriodAll, func() (*models.Stats, error) {
			return &models.Stats{MoviesWatched: 7}, nil
		})
		require.NoError(t, err)

		statsCache.Invalidate(ctx, userId)

		assert.Contains(t, store.store, statsCacheKey(other, models.StatsPeriodAll))
	})

	t.Run("A store failure is swallowed", func(t *testing.T) {
		store := newMemoryCache()
		store.deleteErr = errors.New("redis down")
		statsCache := NewStatsCache(store, newTestLogger())

		assert.NotPanics(t, func() { statsCache.Invalidate(ctx, userId) })
	})
}

func Test_StatsCacheKey(t *testing.T) {
	userId := uuid.MustParse("11111111-2222-3333-4444-555555555555")

	assert.Equal(t, "stats:v2:11111111-2222-3333-4444-555555555555:week", statsCacheKey(userId, models.StatsPeriodWeek))
	assert.Equal(t, "stats:v2:11111111-2222-3333-4444-555555555555:all", statsCacheKey(userId, models.StatsPeriodAll))
}
