package repositories

import (
	"context"
	"errors"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories/db"
	"biinge-api/internal/app/repositories/postgres"
)

// SyncRepository finds stored titles due for a TMDB refresh and writes the refreshed snapshot back
type SyncRepository interface {
	FindMoviesToSync(ctx context.Context, staleBefore, releaseCutoff time.Time, limit int) ([]models.Movie, error)
	FindSeriesToSync(ctx context.Context, staleBefore, airCutoff time.Time, activeStatuses []string, limit int) ([]models.Series, error)
	SyncMovie(ctx context.Context, id uuid.UUID, in models.MovieSyncInput) error
	SyncSeries(ctx context.Context, userId uuid.UUID, tmdbId uint64, in models.SeriesSyncInput) error
	TouchMovieSynced(ctx context.Context, id uuid.UUID) error
	TouchSeriesSynced(ctx context.Context, id uuid.UUID) error
}

type syncRepository struct {
	client postgres.Postgres
}

func NewSyncRepository(client postgres.Postgres) SyncRepository {
	return &syncRepository{client: client}
}

func (r *syncRepository) FindMoviesToSync(ctx context.Context, staleBefore, releaseCutoff time.Time, limit int) ([]models.Movie, error) {
	rows, err := r.client.Queries().FindMoviesToSync(ctx, db.FindMoviesToSyncParams{
		StaleBefore:   timestampFromTime(staleBefore),
		ReleaseCutoff: timestampFromTime(releaseCutoff),
		BatchSize:     int32(limit),
	})
	if err != nil {
		return nil, err
	}

	movies := make([]models.Movie, 0, len(rows))
	for _, row := range rows {
		movies = append(movies, models.Movie{
			ID:         row.ID,
			UserId:     row.UserID,
			TmdbId:     row.TmdbID,
			Title:      row.Title,
			PosterPath: row.PosterPath,
			Runtime:    row.Runtime,
		})
	}

	return movies, nil
}

func (r *syncRepository) FindSeriesToSync(ctx context.Context, staleBefore, airCutoff time.Time, activeStatuses []string, limit int) ([]models.Series, error) {
	rows, err := r.client.Queries().FindSeriesToSync(ctx, db.FindSeriesToSyncParams{
		StaleBefore:    timestampFromTime(staleBefore),
		AirCutoff:      timestampFromTime(airCutoff),
		ActiveStatuses: activeStatuses,
		BatchSize:      int32(limit),
	})
	if err != nil {
		return nil, err
	}

	collection := make([]models.Series, 0, len(rows))
	for _, row := range rows {
		collection = append(collection, models.Series{
			ID:            row.ID,
			UserId:        row.UserID,
			TmdbId:        row.TmdbID,
			Title:         row.Title,
			PosterPath:    row.PosterPath,
			SeasonsCount:  row.SeasonsCount,
			EpisodesCount: row.EpisodesCount,
			Status:        row.Status,
		})
	}

	return collection, nil
}

func (r *syncRepository) SyncMovie(ctx context.Context, id uuid.UUID, in models.MovieSyncInput) error {
	return r.client.Queries().SyncMovie(ctx, db.SyncMovieParams{
		ID:         id,
		Title:      in.Title,
		PosterPath: in.PosterPath,
		Runtime:    in.Runtime,
		ReleasedAt: timestampFromTime(in.ReleasedAt),
	})
}

// SyncSeries refreshes a show's snapshot under a row lock, recomputing derived state only
// when the status or season total actually shifted (a revival, a wrapped-up season)
func (r *syncRepository) SyncSeries(ctx context.Context, userId uuid.UUID, tmdbId uint64, in models.SeriesSyncInput) error {
	return r.withTx(ctx, func(q *db.Queries) error {
		current, err := q.FindSeriesByTmdbIdForUpdate(ctx, db.FindSeriesByTmdbIdForUpdateParams{TmdbID: tmdbId, UserID: userId})
		if err != nil {
			// the row was removed between listing and sync; nothing to refresh
			if errors.Is(err, pgx.ErrNoRows) {
				return nil
			}

			return err
		}

		// keep the stored value whenever TMDB returns nothing, mirroring the read-repair
		status := firstNonEmpty(in.Status, current.Status)
		seasonsCount := firstPositive(in.SeasonsCount, current.SeasonsCount)

		updated, err := q.SyncSeries(ctx, db.SyncSeriesParams{
			ID:            current.ID,
			Title:         firstNonEmpty(in.Title, current.Title),
			PosterPath:    firstNonEmpty(in.PosterPath, current.PosterPath),
			SeasonsCount:  seasonsCount,
			EpisodesCount: firstPositive(in.EpisodesCount, current.EpisodesCount),
			Status:        status,
			LastAirAt:     timestampFromTime(in.LastAirAt),
		})
		if err != nil {
			return err
		}

		if status != current.Status || seasonsCount != current.SeasonsCount {
			return recomputeSeries(ctx, q, updated)
		}

		return nil
	})
}

func (r *syncRepository) TouchMovieSynced(ctx context.Context, id uuid.UUID) error {
	return r.client.Queries().TouchMovieSynced(ctx, id)
}

func (r *syncRepository) TouchSeriesSynced(ctx context.Context, id uuid.UUID) error {
	return r.client.Queries().TouchSeriesSynced(ctx, id)
}

// withTx runs fn inside a database transaction, rolling back on error
func (r *syncRepository) withTx(ctx context.Context, fn func(q *db.Queries) error) error {
	tx, err := r.client.Db().Begin(ctx)
	if err != nil {
		return err
	}

	defer func() { _ = tx.Rollback(ctx) }()

	if err = fn(r.client.Queries().WithTx(tx)); err != nil {
		return err
	}

	return tx.Commit(ctx)
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
