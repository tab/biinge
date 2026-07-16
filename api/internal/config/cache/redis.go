package cache

import (
	"context"
	"errors"
	"time"

	"github.com/redis/go-redis/v9"
	"go.uber.org/fx"

	"biinge-api/internal/config"
	"biinge-api/internal/config/logger"
)

type redisCache struct {
	client *redis.Client
	log    *logger.Logger
}

// NewCache returns a Redis-backed cache, or a no-op cache when no Redis URL is configured
func NewCache(cfg *config.Config, log *logger.Logger, lifecycle fx.Lifecycle) Cache {
	log = log.WithComponent("Cache")

	if cfg.RedisURL == "" {
		log.Info().Msg("No Redis URL configured, caching disabled")
		return NewNoopCache()
	}

	options, err := redis.ParseURL(cfg.RedisURL)
	if err != nil {
		// A malformed URL must never block boot; degrade to uncached rather than crash
		log.Warn().Err(err).Msg("Invalid Redis URL, caching disabled")
		return NewNoopCache()
	}

	client := redis.NewClient(options)

	lifecycle.Append(fx.Hook{
		OnStart: func(ctx context.Context) error {
			// A cold Redis must never block boot; the cache falls back to source per call
			if err := client.Ping(ctx).Err(); err != nil {
				log.Warn().Err(err).Str("addr", options.Addr).Msg("Redis unreachable at start, serving uncached")
			} else {
				log.Info().Str("addr", options.Addr).Msg("Connected to Redis cache")
			}

			return nil
		},
		OnStop: func(context.Context) error {
			return client.Close()
		},
	})

	return &redisCache{client: client, log: log}
}

func (c *redisCache) Get(ctx context.Context, key string) ([]byte, bool, error) {
	data, err := c.client.Get(ctx, key).Bytes()
	if errors.Is(err, redis.Nil) {
		return nil, false, nil
	}

	if err != nil {
		return nil, false, err
	}

	return data, true, nil
}

func (c *redisCache) Set(ctx context.Context, key string, value []byte, ttl time.Duration) error {
	return c.client.Set(ctx, key, value, ttl).Err()
}
