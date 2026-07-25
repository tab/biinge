package services

import (
	"context"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories"
)

func Test_Stats_Get(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockStatsRepository(ctrl)
	service := NewStats(repository, newTestStatsCache(), newTestLogger())

	userId := uuid.New()

	tests := []struct {
		name     string
		period   models.StatsPeriod
		before   func()
		expected *models.Stats
		error    error
	}{
		{
			name:   "Success",
			period: models.StatsPeriodAll,
			before: func() {
				repository.EXPECT().Get(ctx, userId, models.StatsPeriodAll).Return(&models.Stats{
					Period:          models.StatsPeriodAll,
					MoviesWant:      3,
					MoviesWatched:   10,
					MoviesMinutes:   1200,
					SeriesWant:      2,
					SeriesWatching:  1,
					SeriesWatched:   4,
					EpisodesWatched: 100,
					EpisodesMinutes: 4200,
				}, nil)
			},
			expected: &models.Stats{
				Period:          models.StatsPeriodAll,
				MoviesWant:      3,
				MoviesWatched:   10,
				MoviesMinutes:   1200,
				SeriesWant:      2,
				SeriesWatching:  1,
				SeriesWatched:   4,
				EpisodesWatched: 100,
				EpisodesMinutes: 4200,
			},
		},
		{
			name:   "Passes the period through",
			period: models.StatsPeriodWeek,
			before: func() {
				repository.EXPECT().Get(ctx, userId, models.StatsPeriodWeek).Return(&models.Stats{
					Period:        models.StatsPeriodWeek,
					MoviesWatched: 2,
					MoviesMinutes: 240,
				}, nil)
			},
			expected: &models.Stats{
				Period:        models.StatsPeriodWeek,
				MoviesWatched: 2,
				MoviesMinutes: 240,
			},
		},
		{
			name:   "Error",
			period: models.StatsPeriodAll,
			before: func() {
				repository.EXPECT().Get(ctx, userId, models.StatsPeriodAll).Return(nil, assert.AnError)
			},
			expected: nil,
			error:    errors.ErrFailedToFetchStats,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, err := service.Get(ctx, userId, tt.period)

			if tt.error != nil {
				require.ErrorIs(t, err, tt.error)
				assert.Nil(t, result)
			} else {
				require.NoError(t, err)
				assert.Equal(t, tt.expected, result)
			}
		})
	}
}

func Test_Stats_Get_ReadsThroughTheCache(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	userId := uuid.New()

	t.Run("A cached period never reaches the repository", func(t *testing.T) {
		repository := repositories.NewMockStatsRepository(ctrl)
		service := NewStats(repository, NewStatsCache(newMemoryCache(), newTestLogger()), newTestLogger())

		repository.EXPECT().Get(ctx, userId, models.StatsPeriodWeek).Return(&models.Stats{MoviesWatched: 4}, nil).Times(1)

		first, err := service.Get(ctx, userId, models.StatsPeriodWeek)
		require.NoError(t, err)

		second, err := service.Get(ctx, userId, models.StatsPeriodWeek)
		require.NoError(t, err)

		assert.Equal(t, first, second)
	})

	t.Run("Each period is computed on its own", func(t *testing.T) {
		repository := repositories.NewMockStatsRepository(ctrl)
		service := NewStats(repository, NewStatsCache(newMemoryCache(), newTestLogger()), newTestLogger())

		for _, period := range models.StatsPeriods {
			repository.EXPECT().Get(ctx, userId, period).Return(&models.Stats{Period: period}, nil).Times(1)
		}

		for _, period := range models.StatsPeriods {
			result, err := service.Get(ctx, userId, period)

			require.NoError(t, err)
			assert.Equal(t, period, result.Period)
		}
	})

	t.Run("A repository failure is not cached", func(t *testing.T) {
		repository := repositories.NewMockStatsRepository(ctrl)
		service := NewStats(repository, NewStatsCache(newMemoryCache(), newTestLogger()), newTestLogger())

		repository.EXPECT().Get(ctx, userId, models.StatsPeriodAll).Return(nil, assert.AnError)
		repository.EXPECT().Get(ctx, userId, models.StatsPeriodAll).Return(&models.Stats{MoviesWatched: 9}, nil)

		_, err := service.Get(ctx, userId, models.StatsPeriodAll)
		require.ErrorIs(t, err, errors.ErrFailedToFetchStats)

		result, err := service.Get(ctx, userId, models.StatsPeriodAll)

		require.NoError(t, err)
		assert.Equal(t, uint64(9), result.MoviesWatched)
	})
}
