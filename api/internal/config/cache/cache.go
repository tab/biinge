package cache

import (
	"context"
	"encoding/json"
	"time"

	"biinge-api/internal/config/logger"
)

// TTLs for cached TMDB responses, a pure freshness-against-API-calls trade since no user action changes what TMDB answers
const (
	// tightest of the three: a just-aired episode reaches a season list, and so up-next, only once this expires
	DetailsTTL  = 12 * time.Hour
	SearchTTL   = 6 * time.Hour
	TrendingTTL = 6 * time.Hour
)

// StatsTTL covers only the drift invalidation cannot see (a calendar period rolling over mid-entry), since every write that moves a count drops the entry
const StatsTTL = 30 * time.Minute

// Cache is a byte-oriented key/value store with per-entry expiry
type Cache interface {
	Get(ctx context.Context, key string) ([]byte, bool, error)
	Set(ctx context.Context, key string, value []byte, ttl time.Duration) error
	Delete(ctx context.Context, keys ...string) error
}

// Fetch returns the cached value for key, otherwise calls source and caches its result
func Fetch[T any](ctx context.Context, cache Cache, log *logger.Logger, key string, ttl time.Duration, source func() (T, error)) (T, error) {
	switch data, ok, err := cache.Get(ctx, key); {
	case err != nil:
		log.Debug().Err(err).Str("key", key).Msg("Cache read failed")
	case ok:
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

func (noopCache) Delete(context.Context, ...string) error {
	return nil
}
