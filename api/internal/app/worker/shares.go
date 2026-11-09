package worker

import (
	"context"
	"time"

	"go.uber.org/fx"

	"biinge-api/internal/app/repositories"
	"biinge-api/internal/config/logger"
)

// shareCleanupInterval is how often the share worker deletes expired shares
const shareCleanupInterval = time.Hour

// ShareWorker periodically deletes shares that have gone unvisited past their lifetime
type ShareWorker struct {
	repo     repositories.ShareRepository
	log      *logger.Logger
	interval time.Duration

	cancel context.CancelFunc
	done   chan struct{}
}

func NewShareWorker(lifecycle fx.Lifecycle, repo repositories.ShareRepository, log *logger.Logger) *ShareWorker {
	w := &ShareWorker{
		repo:     repo,
		log:      log.WithComponent("ShareWorker"),
		interval: shareCleanupInterval,
		done:     make(chan struct{}),
	}

	lifecycle.Append(fx.Hook{
		OnStart: func(context.Context) error {
			// detached context so the loop outlives the short OnStart deadline
			ctx, cancel := context.WithCancel(context.Background())
			w.cancel = cancel

			w.log.Info().Dur("interval", w.interval).Msg("Starting share worker")

			go w.run(ctx)

			return nil
		},
		OnStop: func(ctx context.Context) error {
			w.cancel()

			// wait for an in-flight cleanup to unwind, bounded by the shutdown deadline
			select {
			case <-w.done:
			case <-ctx.Done():
			}

			return nil
		},
	})

	return w
}

// run cleans up once at start and then on every tick until the context is cancelled
func (w *ShareWorker) run(ctx context.Context) {
	defer close(w.done)

	w.cleanup(ctx)

	ticker := time.NewTicker(w.interval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			w.cleanup(ctx)
		}
	}
}

// cleanup deletes the expired shares, isolating any panic to this tick
func (w *ShareWorker) cleanup(ctx context.Context) {
	defer func() {
		if r := recover(); r != nil {
			w.log.Error().Interface("panic", r).Msg("Share cleanup recovered from panic")
		}
	}()

	deleted, err := w.repo.DeleteExpired(ctx)
	if err != nil {
		w.log.Error().Err(err).Msg("Failed to delete expired shares")

		return
	}

	if deleted > 0 {
		w.log.Info().Int64("deleted", deleted).Msg("Deleted expired shares")
	}
}
