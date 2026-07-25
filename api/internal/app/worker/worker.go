package worker

import (
	"context"
	"time"

	"go.uber.org/fx"

	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories"
	"biinge-api/internal/app/services"
	"biinge-api/internal/config"
	"biinge-api/internal/config/logger"
	"biinge-api/pkg/tmdb"
)

// activeSeriesStatuses are TMDB statuses for shows still in motion; these stay eligible for
// sync regardless of how long ago they last aired, so an announced revival is always caught
var activeSeriesStatuses = []string{"Returning Series", "In Production", "Planned", "Pilot"}

// Worker periodically refreshes stored movies and series from TMDB so derived state
// (a revived show, a released film) tracks reality without a user opening the title
type Worker struct {
	cfg   *config.Config
	repo  repositories.SyncRepository
	tmdb  tmdb.Client
	stats services.StatsCache
	log   *logger.Logger

	cancel context.CancelFunc
	done   chan struct{}
}

func NewWorker(lifecycle fx.Lifecycle, cfg *config.Config, repo repositories.SyncRepository, client tmdb.Client, stats services.StatsCache, log *logger.Logger) *Worker {
	w := &Worker{
		cfg:   cfg,
		repo:  repo,
		tmdb:  client,
		stats: stats,
		log:   log.WithComponent("SyncWorker"),
		done:  make(chan struct{}),
	}

	lifecycle.Append(fx.Hook{
		OnStart: func(context.Context) error {
			if !cfg.SyncEnabled {
				w.log.Info().Msg("Sync worker disabled")
				close(w.done)

				return nil
			}

			// detached context so the loop outlives the short OnStart deadline
			ctx, cancel := context.WithCancel(context.Background())
			w.cancel = cancel

			w.log.Info().
				Dur("interval", cfg.SyncInterval).
				Int("batchSize", cfg.SyncBatchSize).
				Msg("Starting sync worker")

			go w.run(ctx)

			return nil
		},
		OnStop: func(ctx context.Context) error {
			if w.cancel != nil {
				w.cancel()
			}

			// wait for an in-flight batch to unwind, bounded by the shutdown deadline
			select {
			case <-w.done:
			case <-ctx.Done():
			}

			return nil
		},
	})

	return w
}

// run drives one batch per tick until the context is cancelled
func (w *Worker) run(ctx context.Context) {
	defer close(w.done)

	ticker := time.NewTicker(w.cfg.SyncInterval)
	defer ticker.Stop()

	for {
		select {
		case <-ctx.Done():
			return
		case <-ticker.C:
			w.syncBatch(ctx)
		}
	}
}

// syncBatch refreshes one batch of due movies and series, isolating any panic to this tick
func (w *Worker) syncBatch(ctx context.Context) {
	defer func() {
		if r := recover(); r != nil {
			w.log.Error().Interface("panic", r).Msg("Sync batch recovered from panic")
		}
	}()

	now := time.Now()
	w.syncMovies(ctx, now)
	w.syncSeries(ctx, now)
}

func (w *Worker) syncMovies(ctx context.Context, now time.Time) {
	staleBefore := now.Add(-w.cfg.SyncStaleness)
	releaseCutoff := now.AddDate(0, 0, -w.cfg.SyncMovieMaxAgeDays)

	movies, err := w.repo.FindMoviesToSync(ctx, staleBefore, releaseCutoff, w.cfg.SyncBatchSize)
	if err != nil {
		w.log.Error().Err(err).Msg("Failed to list movies to sync")

		return
	}

	for _, movie := range movies {
		if ctx.Err() != nil {
			return
		}

		w.syncMovie(ctx, movie)
	}
}

func (w *Worker) syncMovie(ctx context.Context, movie models.Movie) {
	details, err := w.tmdb.FetchMovieDetails(ctx, movie.TmdbId)
	if err != nil {
		w.deferMovie(ctx, movie, err)

		return
	}

	releasedAt, _ := tmdb.ParseDate(details.ReleaseDate)

	in := models.MovieSyncInput{
		Title:      firstNonEmpty(details.Title, movie.Title),
		PosterPath: firstNonEmpty(details.PosterPath, movie.PosterPath),
		Runtime:    firstPositive(uint64(details.Runtime), movie.Runtime),
		ReleasedAt: releasedAt,
	}

	if err := w.repo.SyncMovie(ctx, movie.ID, in); err != nil {
		w.log.Error().Err(err).Uint64("tmdbId", movie.TmdbId).Msg("Failed to sync movie")

		return
	}

	// A corrected runtime moves the watched minutes, and this is the one write to a
	// user's library that does not go through the services that drop their statistics
	if in.Runtime != movie.Runtime {
		w.stats.Invalidate(ctx, movie.UserId)
	}

	w.log.Info().
		Uint64("tmdbId", movie.TmdbId).
		Str("title", in.Title).
		Str("status", details.Status).
		Str("releaseDate", details.ReleaseDate).
		Msg("Synced movie")
}

func (w *Worker) syncSeries(ctx context.Context, now time.Time) {
	staleBefore := now.Add(-w.cfg.SyncStaleness)
	airCutoff := now.AddDate(0, 0, -w.cfg.SyncSeriesMaxAgeDays)

	shows, err := w.repo.FindSeriesToSync(ctx, staleBefore, airCutoff, activeSeriesStatuses, w.cfg.SyncBatchSize)
	if err != nil {
		w.log.Error().Err(err).Msg("Failed to list series to sync")

		return
	}

	for _, show := range shows {
		if ctx.Err() != nil {
			return
		}

		w.syncShow(ctx, show)
	}
}

func (w *Worker) syncShow(ctx context.Context, show models.Series) {
	details, err := w.tmdb.FetchTvDetails(ctx, show.TmdbId)
	if err != nil {
		w.deferShow(ctx, show, err)

		return
	}

	lastAirAt, _ := tmdb.ParseDate(details.LastAirDate)

	in := models.SeriesSyncInput{
		Title:         details.Title,
		PosterPath:    details.PosterPath,
		Status:        details.Status,
		SeasonsCount:  uint64(details.SeasonsCount),
		EpisodesCount: uint64(details.EpisodesCount),
		LastAirAt:     lastAirAt,
	}

	if err := w.repo.SyncSeries(ctx, show.UserId, show.TmdbId, in); err != nil {
		w.log.Error().Err(err).Uint64("tmdbId", show.TmdbId).Msg("Failed to sync series")

		return
	}

	w.log.Info().
		Uint64("tmdbId", show.TmdbId).
		Str("title", show.Title).
		Str("status", in.Status).
		Uint64("seasons", in.SeasonsCount).
		Uint64("episodes", in.EpisodesCount).
		Str("lastAirDate", details.LastAirDate).
		Msg("Synced series")
}

// deferMovie pushes a movie to the back of the queue so a failing title never starves the batch
func (w *Worker) deferMovie(ctx context.Context, movie models.Movie, cause error) {
	if ctx.Err() != nil {
		return
	}

	w.log.Warn().Err(cause).Uint64("tmdbId", movie.TmdbId).Msg("Movie sync fetch failed, deferring")

	if err := w.repo.TouchMovieSynced(ctx, movie.ID); err != nil {
		w.log.Error().Err(err).Uint64("tmdbId", movie.TmdbId).Msg("Failed to defer movie sync")
	}
}

// deferShow pushes a show to the back of the queue so a failing title never starves the batch
func (w *Worker) deferShow(ctx context.Context, show models.Series, cause error) {
	if ctx.Err() != nil {
		return
	}

	w.log.Warn().Err(cause).Uint64("tmdbId", show.TmdbId).Msg("Series sync fetch failed, deferring")

	if err := w.repo.TouchSeriesSynced(ctx, show.ID); err != nil {
		w.log.Error().Err(err).Uint64("tmdbId", show.TmdbId).Msg("Failed to defer series sync")
	}
}

// firstNonEmpty returns a when it is set, otherwise the fallback
func firstNonEmpty(a, fallback string) string {
	if a != "" {
		return a
	}

	return fallback
}

// firstPositive returns a when it is greater than zero, otherwise the fallback
func firstPositive(a, fallback uint64) uint64 {
	if a > 0 {
		return a
	}

	return fallback
}
