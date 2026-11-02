package services

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"biinge-api/internal/config/cache"
)

func Test_EchoReceipts(t *testing.T) {
	ctx := context.Background()

	tests := []struct {
		name    string
		store   func() cache.Cache
		setErr  error
		getErr  error
		dropped bool
	}{
		{
			name:  "No Redis keeps the receipt in process",
			store: cache.NewNoopCache,
		},
		{
			name:  "A Redis-backed cache holds the receipt",
			store: func() cache.Cache { return newMemoryCache() },
		},
		{
			name: "A failed Redis write leaves the receipt in process",
			store: func() cache.Cache {
				redis := newMemoryCache()
				redis.setErr = assert.AnError

				return redis
			},
			setErr: assert.AnError,
		},
		{
			name: "A failed Redis read answers from process memory",
			store: func() cache.Cache {
				redis := newMemoryCache()
				redis.getErr = assert.AnError

				return redis
			},
			getErr: assert.AnError,
		},
		{
			name:    "A receipt Redis lost is still found in process",
			store:   func() cache.Cache { return newMemoryCache() },
			dropped: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			store := tt.store()
			receipts := NewEchoReceipts(store)

			require.ErrorIs(t, receipts.Set(ctx, "first", []byte("1"), echoTTL), tt.setErr)

			if tt.dropped {
				require.NoError(t, store.Delete(ctx, "first"))
			}

			value, found, err := receipts.Get(ctx, "first")
			require.ErrorIs(t, err, tt.getErr)
			assert.True(t, found)
			assert.Equal(t, []byte("1"), value)

			_, found, err = receipts.Get(ctx, "second")
			require.ErrorIs(t, err, tt.getErr)
			assert.False(t, found)
		})
	}
}

func Test_EchoReceipts_Get(t *testing.T) {
	ctx := context.Background()
	start := time.Date(2026, 11, 2, 12, 0, 0, 0, time.UTC)

	tests := []struct {
		name    string
		elapsed time.Duration
		found   bool
		entries int
	}{
		{
			name:    "A receipt within its TTL is found",
			elapsed: echoTTL - time.Second,
			found:   true,
			entries: 2,
		},
		{
			name:    "A receipt expires at its TTL and the next write prunes it",
			elapsed: echoTTL,
			entries: 1,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			now := start
			receipts := &echoReceipts{shared: cache.NewNoopCache(), now: func() time.Time { return now }, entries: map[string]memoryReceipt{}}

			require.NoError(t, receipts.Set(ctx, "first", []byte("1"), echoTTL))

			now = start.Add(tt.elapsed)

			value, found, err := receipts.Get(ctx, "first")
			require.NoError(t, err)
			assert.Equal(t, tt.found, found)

			if tt.found {
				assert.Equal(t, []byte("1"), value)
			}

			require.NoError(t, receipts.Set(ctx, "second", []byte("1"), echoTTL))
			assert.Len(t, receipts.entries, tt.entries)
		})
	}
}
