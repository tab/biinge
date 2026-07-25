package cache

import (
	"context"
	"errors"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"biinge-api/internal/config"
	"biinge-api/internal/config/logger"
)

type payload struct {
	Name string `json:"name"`
}

// fakeCache is an in-memory Cache with injectable errors for testing Fetch
type fakeCache struct {
	store       map[string][]byte
	getErr      error
	setErr      error
	deleteErr   error
	setCalls    int
	deletedKeys []string
}

func newFakeCache() *fakeCache {
	return &fakeCache{store: map[string][]byte{}}
}

func (c *fakeCache) Get(_ context.Context, key string) ([]byte, bool, error) {
	if c.getErr != nil {
		return nil, false, c.getErr
	}

	data, ok := c.store[key]

	return data, ok, nil
}

func (c *fakeCache) Set(_ context.Context, key string, value []byte, _ time.Duration) error {
	c.setCalls++
	if c.setErr != nil {
		return c.setErr
	}

	c.store[key] = value

	return nil
}

func (c *fakeCache) Delete(_ context.Context, keys ...string) error {
	c.deletedKeys = append(c.deletedKeys, keys...)
	if c.deleteErr != nil {
		return c.deleteErr
	}

	for _, key := range keys {
		delete(c.store, key)
	}

	return nil
}

func testLogger() *logger.Logger {
	return logger.NewLogger(&config.Config{AppEnv: "test", LogLevel: "info"})
}

func Test_NoopCache(t *testing.T) {
	c := NewNoopCache()

	data, ok, err := c.Get(context.Background(), "key")
	require.NoError(t, err)
	assert.False(t, ok)
	assert.Nil(t, data)

	assert.NoError(t, c.Set(context.Background(), "key", []byte("value"), time.Minute))
	assert.NoError(t, c.Delete(context.Background(), "key"))
}

func Test_Fetch(t *testing.T) {
	ctx := context.Background()
	log := testLogger()

	t.Run("Miss calls source and caches the result", func(t *testing.T) {
		c := newFakeCache()
		calls := 0

		result, err := Fetch(ctx, c, log, "p", time.Minute, func() (*payload, error) {
			calls++
			return &payload{Name: "fresh"}, nil
		})

		require.NoError(t, err)
		assert.Equal(t, &payload{Name: "fresh"}, result)
		assert.Equal(t, 1, calls)
		assert.Equal(t, 1, c.setCalls)
		assert.Contains(t, c.store, "p")
	})

	t.Run("Hit returns the cached value without calling source", func(t *testing.T) {
		c := newFakeCache()
		c.store["p"] = []byte(`{"name":"cached"}`)
		calls := 0

		result, err := Fetch(ctx, c, log, "p", time.Minute, func() (*payload, error) {
			calls++
			return &payload{Name: "fresh"}, nil
		})

		require.NoError(t, err)
		assert.Equal(t, &payload{Name: "cached"}, result)
		assert.Equal(t, 0, calls)
		assert.Equal(t, 0, c.setCalls)
	})

	t.Run("Read error falls through to source", func(t *testing.T) {
		c := newFakeCache()
		c.getErr = errors.New("boom")
		calls := 0

		result, err := Fetch(ctx, c, log, "p", time.Minute, func() (*payload, error) {
			calls++
			return &payload{Name: "fresh"}, nil
		})

		require.NoError(t, err)
		assert.Equal(t, &payload{Name: "fresh"}, result)
		assert.Equal(t, 1, calls)
	})

	t.Run("Corrupt entry falls through to source", func(t *testing.T) {
		c := newFakeCache()
		c.store["p"] = []byte("not json")
		calls := 0

		result, err := Fetch(ctx, c, log, "p", time.Minute, func() (*payload, error) {
			calls++
			return &payload{Name: "fresh"}, nil
		})

		require.NoError(t, err)
		assert.Equal(t, &payload{Name: "fresh"}, result)
		assert.Equal(t, 1, calls)
	})

	t.Run("Source error is returned and nothing is cached", func(t *testing.T) {
		c := newFakeCache()
		sentinel := errors.New("source failed")

		result, err := Fetch(ctx, c, log, "p", time.Minute, func() (*payload, error) {
			return nil, sentinel
		})

		require.ErrorIs(t, err, sentinel)
		assert.Nil(t, result)
		assert.Equal(t, 0, c.setCalls)
	})

	t.Run("Write error is swallowed and the fresh value is returned", func(t *testing.T) {
		c := newFakeCache()
		c.setErr = errors.New("write boom")

		result, err := Fetch(ctx, c, log, "p", time.Minute, func() (*payload, error) {
			return &payload{Name: "fresh"}, nil
		})

		require.NoError(t, err)
		assert.Equal(t, &payload{Name: "fresh"}, result)
		assert.Equal(t, 1, c.setCalls)
	})
}
