package repositories

import (
	"context"

	"github.com/google/uuid"

	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories/postgres"
)

type StatsRepository interface {
	Get(ctx context.Context, userId uuid.UUID) (*models.Stats, error)
}

type stats struct {
	client postgres.Postgres
}

func NewStatsRepository(client postgres.Postgres) StatsRepository {
	return &stats{client: client}
}

func (s *stats) Get(ctx context.Context, userId uuid.UUID) (*models.Stats, error) {
	movies, err := s.client.Queries().MovieStats(ctx, userId)
	if err != nil {
		return nil, err
	}

	series, err := s.client.Queries().SeriesStats(ctx, userId)
	if err != nil {
		return nil, err
	}

	episodes, err := s.client.Queries().EpisodeStats(ctx, userId)
	if err != nil {
		return nil, err
	}

	activity, err := s.client.Queries().WatchActivityByMonth(ctx, userId)
	if err != nil {
		return nil, err
	}

	months := make([]models.MonthlyWatch, 0, len(activity))
	for _, row := range activity {
		months = append(months, models.MonthlyWatch{
			Month:        row.Month.Time,
			MovieMinutes: uint64(row.MovieMinutes),
			TvMinutes:    uint64(row.TvMinutes),
		})
	}

	return &models.Stats{
		MoviesWant:      uint64(movies.WantCount),
		MoviesWatched:   uint64(movies.WatchedCount),
		MoviesMinutes:   uint64(movies.WatchedMinutes),
		SeriesWant:      uint64(series.WantCount),
		SeriesWatching:  uint64(series.WatchingCount),
		SeriesWatched:   uint64(series.WatchedCount),
		EpisodesWatched: uint64(episodes.WatchedCount),
		EpisodesMinutes: uint64(episodes.WatchedMinutes),
		Activity:        months,
	}, nil
}
