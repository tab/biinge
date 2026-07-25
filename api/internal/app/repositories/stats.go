package repositories

import (
	"context"

	"github.com/google/uuid"

	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories/db"
	"biinge-api/internal/app/repositories/postgres"
)

// truncUnit is a date_trunc unit, used both to bound a period and to bucket activity
type truncUnit string

const (
	truncUnitDay   truncUnit = "day"
	truncUnitWeek  truncUnit = "week"
	truncUnitMonth truncUnit = "month"
	truncUnitYear  truncUnit = "year"
)

// String returns the unit as postgres spells it
func (u truncUnit) String() string {
	return string(u)
}

type StatsRepository interface {
	Get(ctx context.Context, userId uuid.UUID, period models.StatsPeriod) (*models.Stats, error)
}

type stats struct {
	client postgres.Postgres
}

func NewStatsRepository(client postgres.Postgres) StatsRepository {
	return &stats{client: client}
}

func (s *stats) Get(ctx context.Context, userId uuid.UUID, period models.StatsPeriod) (*models.Stats, error) {
	movies, err := s.movieStats(ctx, userId, period)
	if err != nil {
		return nil, err
	}

	series, err := s.client.Queries().SeriesStats(ctx, userId)
	if err != nil {
		return nil, err
	}

	episodes, err := s.episodeStats(ctx, userId, period)
	if err != nil {
		return nil, err
	}

	activity, err := s.activity(ctx, userId, period)
	if err != nil {
		return nil, err
	}

	buckets := make([]models.WatchBucket, 0, len(activity))
	for _, row := range activity {
		buckets = append(buckets, models.WatchBucket{
			Date:         row.Bucket.Time,
			MovieMinutes: uint64(row.MovieMinutes),
			TvMinutes:    uint64(row.TvMinutes),
		})
	}

	return &models.Stats{
		Period:          period,
		MoviesWant:      uint64(movies.WantCount),
		MoviesWatched:   uint64(movies.WatchedCount),
		MoviesMinutes:   uint64(movies.WatchedMinutes),
		SeriesWant:      uint64(series.WantCount),
		SeriesWatching:  uint64(series.WatchingCount),
		SeriesWatched:   uint64(series.WatchedCount),
		EpisodesWatched: uint64(episodes.WatchedCount),
		EpisodesMinutes: uint64(episodes.WatchedMinutes),
		Activity:        buckets,
	}, nil
}

// movieStats counts movies by list and sums the runtime watched in the period
func (s *stats) movieStats(ctx context.Context, userId uuid.UUID, period models.StatsPeriod) (db.MovieStatsRow, error) {
	if period == models.StatsPeriodAll {
		row, err := s.client.Queries().MovieStatsAll(ctx, userId)

		return db.MovieStatsRow(row), err
	}

	periodUnit, _ := statsWindow(period)

	return s.client.Queries().MovieStats(ctx, db.MovieStatsParams{
		UserID:     userId,
		PeriodUnit: periodUnit.String(),
	})
}

// episodeStats counts the episodes watched in the period and sums their runtime
func (s *stats) episodeStats(ctx context.Context, userId uuid.UUID, period models.StatsPeriod) (db.EpisodeStatsRow, error) {
	if period == models.StatsPeriodAll {
		row, err := s.client.Queries().EpisodeStatsAll(ctx, userId)

		return db.EpisodeStatsRow(row), err
	}

	periodUnit, _ := statsWindow(period)

	return s.client.Queries().EpisodeStats(ctx, db.EpisodeStatsParams{
		UserID:     userId,
		PeriodUnit: periodUnit.String(),
	})
}

// activity returns the dense watch buckets covering the period
func (s *stats) activity(ctx context.Context, userId uuid.UUID, period models.StatsPeriod) ([]db.WatchActivityRow, error) {
	if period == models.StatsPeriodAll {
		all, err := s.client.Queries().WatchActivityAll(ctx, userId)
		if err != nil {
			return nil, err
		}

		rows := make([]db.WatchActivityRow, 0, len(all))
		for _, row := range all {
			rows = append(rows, db.WatchActivityRow(row))
		}

		return rows, nil
	}

	periodUnit, bucketUnit := statsWindow(period)

	return s.client.Queries().WatchActivity(ctx, db.WatchActivityParams{
		UserID:     userId,
		PeriodUnit: periodUnit.String(),
		BucketUnit: bucketUnit.String(),
	})
}

// statsWindow returns the calendar unit a bounded period covers and the unit it buckets activity by
func statsWindow(period models.StatsPeriod) (truncUnit, truncUnit) {
	switch period {
	case models.StatsPeriodWeek:
		return truncUnitWeek, truncUnitDay
	case models.StatsPeriodMonth:
		return truncUnitMonth, truncUnitDay
	default:
		// only the bounded periods reach here, and year is the widest of them
		return truncUnitYear, truncUnitMonth
	}
}
