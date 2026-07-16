package cache

import (
	"context"
	"encoding/json"
	"time"

	"biinge-api/internal/config/logger"
)

// TTLs for the classes of cached TMDB responses
const (
	DetailsTTL  = 12 * time.Hour
	SearchTTL   = time.Hour
	TrendingTTL = 3 * time.Hour
)

// Cache is a byte-oriented key/value store with per-entry expiry
type Cache interface {
	Get(ctx context.Context, key string) ([]byte, bool, error)
	Set(ctx context.Context, key string, value []byte, ttl time.Duration) error
}

// Fetch returns the cached value for key, otherwise calls source and caches its result
func Fetch[T any](ctx context.Context, cache Cache, log *logger.Logger, key string, ttl time.Duration, source func() (T, error)) (T, error) {
	if data, ok, err := cache.Get(ctx, key); err != nil {
		log.Debug().Err(err).Str("key", key).Msg("Cache read failed")
	} else if ok {
		var cached T
		if err := json.Unmarshal(data, &cached); err == nil {
			return cached, nil
		}

		log.Debug().Str("key", key).Msg("Discarding unreadable cache entry")
	}

	result, err := source()
	if err != nil {
		return result, err
	}

	data, err := json.Marshal(result)
	if err != nil {
		log.Debug().Err(err).Str("key", key).Msg("Cache encode failed")
		return result, nil
	}

	if err := cache.Set(ctx, key, data, ttl); err != nil {
		log.Debug().Err(err).Str("key", key).Msg("Cache write failed")
	}

	return result, nil
}

// noopCache satisfies Cache without storing anything, used when caching is disabled
type noopCache struct{}

// NewNoopCache returns a Cache that always misses
func NewNoopCache() Cache {
	return noopCache{}
}

func (noopCache) Get(context.Context, string) ([]byte, bool, error) {
	return nil, false, nil
}

func (noopCache) Set(context.Context, string, []byte, time.Duration) error {
	return nil
}
