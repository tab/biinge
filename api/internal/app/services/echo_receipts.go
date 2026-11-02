package services

import (
	"context"
	"sync"
	"time"

	"biinge-api/internal/config/cache"
)

// EchoReceipts records the API's own Jellyfin played writes under echoKey, so the webhook can skip their echo
type EchoReceipts interface {
	Get(ctx context.Context, key string) ([]byte, bool, error)
	Set(ctx context.Context, key string, value []byte, ttl time.Duration) error
}

// NewEchoReceipts keeps every receipt in process and in the response cache too (the no-op cache without Redis stores nothing and always misses)
func NewEchoReceipts(store cache.Cache) EchoReceipts {
	return &echoReceipts{shared: store, now: time.Now, entries: map[string]memoryReceipt{}}
}

// memoryReceipt is one stored receipt and the time it expires
type memoryReceipt struct {
	value   []byte
	expires time.Time
}

// echoReceipts is an in-process TTL map behind the shared cache (expired entries are pruned on each write)
// shortcut: with Redis down or unset, a receipt reaches only the instance that wrote it, so a deploy running several instances loses cross-instance echo protection until Redis answers
type echoReceipts struct {
	shared  cache.Cache
	mu      sync.Mutex
	now     func() time.Time
	entries map[string]memoryReceipt
}

// Get answers from the shared cache and falls back to process memory on a miss or an error (a shared-cache error comes back alongside the memory answer)
func (r *echoReceipts) Get(ctx context.Context, key string) ([]byte, bool, error) {
	value, found, err := r.shared.Get(ctx, key)
	if err == nil && found {
		return value, true, nil
	}

	r.mu.Lock()
	defer r.mu.Unlock()

	entry, ok := r.entries[key]
	if !ok || !r.now().Before(entry.expires) {
		return nil, false, err
	}

	return entry.value, true, err
}

// Set stores the receipt in process memory, then in the shared cache (a shared-cache error still leaves the receipt in memory)
func (r *echoReceipts) Set(ctx context.Context, key string, value []byte, ttl time.Duration) error {
	r.mu.Lock()

	now := r.now()
	for k, entry := range r.entries {
		if !now.Before(entry.expires) {
			delete(r.entries, k)
		}
	}

	r.entries[key] = memoryReceipt{value: value, expires: now.Add(ttl)}

	r.mu.Unlock()

	return r.shared.Set(ctx, key, value, ttl)
}
