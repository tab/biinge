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
	if period == models.StatsPeriodAll {
		return s.allTime(ctx, userId)
	}

	return s.forPeriod(ctx, userId, period)
}

// allTime reports the whole library: every list alongside everything ever watched
func (s *stats) allTime(ctx context.Context, userId uuid.UUID) (*models.Stats, error) {
	movies, err := s.client.Queries().MovieStatsAll(ctx, userId)
	if err != nil {
		return nil, err
	}

	series, err := s.client.Queries().SeriesStatsAll(ctx, userId)
	if err != nil {
		return nil, err
	}

	episodes, err := s.client.Queries().EpisodeStatsAll(ctx, userId)
	if err != nil {
		return nil, err
	}

	games, err := s.client.Queries().GameStatsAll(ctx, userId)
	if err != nil {
		return nil, err
	}

	activity, err := s.client.Queries().WatchActivityAll(ctx, userId)
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

	seriesWatching := uint64(series.WatchingCount)
	gamesPlaying := uint64(games.PlayingCount)

	return &models.Stats{
		Period:          models.StatsPeriodAll,
		MoviesWant:      uint64(movies.WantCount),
		MoviesWatched:   uint64(movies.WatchedCount),
		MoviesMinutes:   uint64(movies.WatchedMinutes),
		SeriesWant:      uint64(series.WantCount),
		SeriesWatching:  &seriesWatching,
		SeriesWatched:   uint64(series.WatchedCount),
		EpisodesWatched: uint64(episodes.WatchedCount),
		EpisodesMinutes: uint64(episodes.WatchedMinutes),
		GamesWant:       uint64(games.WantCount),
		GamesPlaying:    &gamesPlaying,
		GamesPlayed:     uint64(games.PlayedCount),
		GamesMinutes:    uint64(games.PlayedMinutes),
		Activity:        buckets,
	}, nil
}

// forPeriod reports what happened inside the current calendar period: titles added to a
// want list and titles watched, with no watching count for shows
func (s *stats) forPeriod(ctx context.Context, userId uuid.UUID, period models.StatsPeriod) (*models.Stats, error) {
	periodUnit, bucketUnit := statsWindow(period)

	movies, err := s.client.Queries().MovieStats(ctx, db.MovieStatsParams{
		UserID:     userId,
		PeriodUnit: periodUnit.String(),
	})
	if err != nil {
		return nil, err
	}

	series, err := s.client.Queries().SeriesStats(ctx, db.SeriesStatsParams{
		UserID:     userId,
		PeriodUnit: periodUnit.String(),
	})
	if err != nil {
		return nil, err
	}

	episodes, err := s.client.Queries().EpisodeStats(ctx, db.EpisodeStatsParams{
		UserID:     userId,
		PeriodUnit: periodUnit.String(),
	})
	if err != nil {
		return nil, err
	}

	games, err := s.client.Queries().GameStats(ctx, db.GameStatsParams{
		UserID:     userId,
		PeriodUnit: periodUnit.String(),
	})
	if err != nil {
		return nil, err
	}

	activity, err := s.client.Queries().WatchActivity(ctx, db.WatchActivityParams{
		UserID:     userId,
		PeriodUnit: periodUnit.String(),
		BucketUnit: bucketUnit.String(),
	})
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
		SeriesWatched:   uint64(series.WatchedCount),
		EpisodesWatched: uint64(episodes.WatchedCount),
		EpisodesMinutes: uint64(episodes.WatchedMinutes),
		GamesWant:       uint64(games.WantCount),
		GamesPlayed:     uint64(games.PlayedCount),
		GamesMinutes:    uint64(games.PlayedMinutes),
		Activity:        buckets,
	}, nil
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
