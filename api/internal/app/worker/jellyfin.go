package worker

import (
	"context"
	"time"

	"github.com/google/uuid"
	"go.uber.org/fx"

	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories"
	"biinge-api/internal/app/services"
	"biinge-api/internal/config"
	"biinge-api/internal/config/logger"
)

// JellyfinWorker applies each connected user's Jellyfin played changes to biinge and reconciles Jellyfin with biinge on a schedule
type JellyfinWorker struct {
	cfg          *config.Config
	integrations repositories.IntegrationRepository
	library      services.Library
	sync         services.JellyfinSync
	memory       services.PlayedMemory
	log          *logger.Logger

	// reconciled holds each user's last successful reconcile, touched only by the run goroutine
	reconciled map[uuid.UUID]time.Time

	cancel context.CancelFunc
	done   chan struct{}
}

func NewJellyfinWorker(
	lifecycle fx.Lifecycle,
	cfg *config.Config,
	integrations repositories.IntegrationRepository,
	library services.Library,
	sync services.JellyfinSync,
	memory services.PlayedMemory,
	log *logger.Logger,
) *JellyfinWorker {
	w := &JellyfinWorker{
		cfg:          cfg,
		integrations: integrations,
		library:      library,
		sync:         sync,
		memory:       memory,
		log:          log.WithComponent("JellyfinWorker"),
		reconciled:   map[uuid.UUID]time.Time{},
		done:         make(chan struct{}),
	}

	lifecycle.Append(fx.Hook{
		OnStart: func(context.Context) error {
			if cfg.Jellyfin.BaseURL == "" || !cfg.Jellyfin.SyncEnabled {
				w.log.Info().Msg("Jellyfin worker disabled")
				close(w.done)

				return nil
			}

			// detached context so the loop outlives the short OnStart deadline
			ctx, cancel := context.WithCancel(context.Background())
			w.cancel = cancel

			w.log.Info().
				Dur("interval", cfg.Jellyfin.SyncInterval).
				Dur("reconcileInterval", cfg.Jellyfin.ReconcileInterval).
				Msg("Starting Jellyfin worker")

			go w.run(ctx)

			return nil
		},
		OnStop: func(ctx context.Context) error {
			if w.cancel != nil {
				w.cancel()
			}

			// wait for an in-flight pass to unwind, bounded by the shutdown deadline
			select {
			case <-w.done:
			case <-ctx.Done():
			}

			return nil
		},
	})

	return w
}

// run drives one round of passes per tick until the context is cancelled
func (w *JellyfinWorker) run(ctx context.Context) {
	defer close(w.done)

	ticker := time.NewTicker(w.cfg.Jellyfin.SyncInterval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			w.syncUsers(ctx)
		}
	}
}

// syncUsers runs one pass for each connected user in turn, isolating any panic to this tick
func (w *JellyfinWorker) syncUsers(ctx context.Context) {
	defer func() {
		if r := recover(); r != nil {
			w.log.Error().Interface("panic", r).Msg("Jellyfin sync recovered from panic")
		}
	}()

	users, err := w.integrations.ListUsers(ctx, models.JellyfinProvider)
	if err != nil {
		w.log.Error().Err(err).Msg("Failed to list the Jellyfin users")

		return
	}

	for _, userId := range users {
		if ctx.Err() != nil {
			return
		}

		w.syncUser(ctx, userId)
	}
}

// syncUser applies the user's Jellyfin played flips since the previous read, then reconciles after a first or a clean due pass
func (w *JellyfinWorker) syncUser(ctx context.Context, userId uuid.UUID) {
	read, err := w.library.Played(ctx, userId)
	if err != nil {
		// the previous read and the reconcile time stay, so the next pass picks up where this one could not
		w.log.Warn().Err(err).Str("userId", userId.String()).Msg("Skipping the Jellyfin sync pass")

		return
	}

	if read == nil {
		// Jellyfin is off or the user disconnected, so a later connection starts with a first pass
		w.memory.Forget(userId)
		delete(w.reconciled, userId)

		return
	}

	next := make(map[string]bool, len(read.Items))
	for _, item := range read.Items {
		next[item.Id] = item.Played
	}

	previous, found := w.memory.Previous(read.Key)

	// keeping the read first brings back each API write that landed while it ran, which the read may have missed
	w.memory.Replace(read.Key, next, read.Began)

	if !found {
		// a first pass only records the read, then pushes biinge's state
		if err := w.sync.Reconcile(ctx, read); err != nil {
			w.log.Warn().Err(err).Str("userId", userId.String()).Msg("Failed to reconcile Jellyfin")

			return
		}

		w.reconciled[userId] = time.Now()

		return
	}

	clean := true

	for _, item := range read.Items {
		if previous[item.Id] == item.Played {
			continue
		}

		// read right before the apply, a stored flag that differs from the read's was written by the API after the read began, not changed in Jellyfin
		if kept, _ := w.memory.Previous(read.Key); kept[item.Id] != item.Played {
			continue
		}

		if err := w.sync.Apply(ctx, userId, item.JellyfinChange); err != nil {
			w.log.Warn().Err(err).Str("userId", userId.String()).Str("itemId", item.Id).Msg("Failed to apply a Jellyfin played change")

			// the item goes back to its previous flag (or out, which reads as unplayed), so the next pass applies it again
			clean = false

			delete(next, item.Id)

			if flag, had := previous[item.Id]; had {
				next[item.Id] = flag
			}
		}
	}

	if !clean {
		// an unclean pass skips the reconcile, which would write over the changes it could not apply
		w.memory.Replace(read.Key, next, read.Began)

		return
	}

	if time.Since(w.reconciled[userId]) < w.cfg.Jellyfin.ReconcileInterval {
		return
	}

	if err := w.sync.Reconcile(ctx, read); err != nil {
		w.log.Warn().Err(err).Str("userId", userId.String()).Msg("Failed to reconcile Jellyfin")

		return
	}

	w.reconciled[userId] = time.Now()
}
