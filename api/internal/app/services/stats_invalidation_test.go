package services

import (
	"context"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"

	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories"
)

// Every write that can move a watched count has to drop the cached statistics,
// otherwise the profile screen keeps serving the numbers from before the change.

func Test_Movies_InvalidatesStats(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	userId := uuid.New()

	tests := []struct {
		name       string
		before     func(repository *repositories.MockMovieRepository)
		call       func(service Movies) error
		invalidate bool
	}{
		{
			name: "Adding to a list",
			before: func(repository *repositories.MockMovieRepository) {
				repository.EXPECT().Create(ctx, gomock.Any()).Return(&models.Movie{}, nil)
			},
			call: func(service Movies) error {
				_, err := service.Create(ctx, &models.Movie{UserId: userId, State: models.StateTypeWant})

				return err
			},
			invalidate: true,
		},
		{
			name: "Moving between lists",
			before: func(repository *repositories.MockMovieRepository) {
				repository.EXPECT().UpdateByTmdbId(ctx, gomock.Any()).Return(&models.Movie{}, nil)
			},
			call: func(service Movies) error {
				_, err := service.UpdateByTmdbId(ctx, &models.Movie{UserId: userId, State: models.StateTypeWatched})

				return err
			},
			invalidate: true,
		},
		{
			name: "Removing from a list",
			before: func(repository *repositories.MockMovieRepository) {
				repository.EXPECT().Delete(ctx, uint64(100), userId).Return(nil)
			},
			call: func(service Movies) error {
				return service.Delete(ctx, 100, userId)
			},
			invalidate: true,
		},
		{
			name: "A failed write leaves the cache alone",
			before: func(repository *repositories.MockMovieRepository) {
				repository.EXPECT().UpdateByTmdbId(ctx, gomock.Any()).Return(nil, assert.AnError)
			},
			call: func(service Movies) error {
				_, err := service.UpdateByTmdbId(ctx, &models.Movie{UserId: userId, State: models.StateTypeWatched})

				return err
			},
			invalidate: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			repository := repositories.NewMockMovieRepository(ctrl)
			statsCache := NewMockStatsCache(ctrl)

			tt.before(repository)

			if tt.invalidate {
				statsCache.EXPECT().Invalidate(ctx, userId).Times(1)
			}

			err := tt.call(NewMovies(repository, statsCache, newTestLogger()))

			if tt.invalidate {
				require.NoError(t, err)
			} else {
				require.Error(t, err)
			}
		})
	}
}

func Test_Series_InvalidatesStats(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	userId := uuid.New()

	tests := []struct {
		name       string
		before     func(repository *repositories.MockSeriesRepository)
		call       func(service Series) error
		invalidate bool
	}{
		{
			name: "Adding to a list",
			before: func(repository *repositories.MockSeriesRepository) {
				repository.EXPECT().Create(ctx, gomock.Any()).Return(&models.Series{}, nil)
			},
			call: func(service Series) error {
				_, err := service.Create(ctx, &models.Series{UserId: userId, State: models.StateTypeWant})

				return err
			},
			invalidate: true,
		},
		{
			name: "Moving between lists",
			before: func(repository *repositories.MockSeriesRepository) {
				repository.EXPECT().UpdateByTmdbId(ctx, gomock.Any()).Return(&models.Series{}, nil)
			},
			call: func(service Series) error {
				_, err := service.UpdateByTmdbId(ctx, &models.Series{UserId: userId, State: models.StateTypeWatching})

				return err
			},
			invalidate: true,
		},
		{
			name: "Removing from a list",
			before: func(repository *repositories.MockSeriesRepository) {
				repository.EXPECT().Delete(ctx, uint64(200), userId).Return(nil)
			},
			call: func(service Series) error {
				return service.Delete(ctx, 200, userId)
			},
			invalidate: true,
		},
		{
			name: "A failed write leaves the cache alone",
			before: func(repository *repositories.MockSeriesRepository) {
				repository.EXPECT().Create(ctx, gomock.Any()).Return(nil, assert.AnError)
			},
			call: func(service Series) error {
				_, err := service.Create(ctx, &models.Series{UserId: userId, State: models.StateTypeWant})

				return err
			},
			invalidate: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			repository := repositories.NewMockSeriesRepository(ctrl)
			statsCache := NewMockStatsCache(ctrl)

			tt.before(repository)

			if tt.invalidate {
				statsCache.EXPECT().Invalidate(ctx, userId).Times(1)
			}

			err := tt.call(NewSeries(repository, statsCache, newTestLogger()))

			if tt.invalidate {
				require.NoError(t, err)
			} else {
				require.Error(t, err)
			}
		})
	}
}

func Test_Progress_InvalidatesStats(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	userId := uuid.New()
	show := models.SeriesInput{TmdbId: 300}
	season := models.SeasonInput{TmdbId: 400}
	episode := models.EpisodeInput{TmdbId: 500}

	tests := []struct {
		name   string
		before func(repository *repositories.MockSeriesProgressRepository)
		call   func(service Progress) error
	}{
		{
			name: "Marking a show watched",
			before: func(repository *repositories.MockSeriesProgressRepository) {
				repository.EXPECT().MarkShowWatched(ctx, userId, gomock.Any()).Return(&models.SeriesProgress{}, nil)
			},
			call: func(service Progress) error {
				_, err := service.MarkShow(ctx, userId, models.ShowInput{Series: show})

				return err
			},
		},
		{
			name: "Unmarking a show",
			before: func(repository *repositories.MockSeriesProgressRepository) {
				repository.EXPECT().UnmarkShowWatched(ctx, userId, uint64(300)).Return(&models.SeriesProgress{}, nil)
			},
			call: func(service Progress) error {
				_, err := service.UnmarkShow(ctx, userId, 300)

				return err
			},
		},
		{
			name: "Marking a season watched",
			before: func(repository *repositories.MockSeriesProgressRepository) {
				repository.EXPECT().MarkSeasonWatched(ctx, userId, show, season).Return(&models.SeriesProgress{}, nil)
			},
			call: func(service Progress) error {
				_, err := service.MarkSeason(ctx, userId, show, season)

				return err
			},
		},
		{
			name: "Unmarking a season",
			before: func(repository *repositories.MockSeriesProgressRepository) {
				repository.EXPECT().UnmarkSeasonWatched(ctx, userId, uint64(300), uint64(400)).Return(&models.SeriesProgress{}, nil)
			},
			call: func(service Progress) error {
				_, err := service.UnmarkSeason(ctx, userId, 300, 400)

				return err
			},
		},
		{
			name: "Marking an episode watched",
			before: func(repository *repositories.MockSeriesProgressRepository) {
				repository.EXPECT().MarkEpisodeWatched(ctx, userId, show, season, episode).Return(&models.SeriesProgress{}, nil)
			},
			call: func(service Progress) error {
				_, err := service.MarkEpisode(ctx, userId, show, season, episode)

				return err
			},
		},
		{
			name: "Unmarking an episode",
			before: func(repository *repositories.MockSeriesProgressRepository) {
				repository.EXPECT().UnmarkEpisodeWatched(ctx, userId, uint64(300), uint64(400), uint64(500)).Return(&models.SeriesProgress{}, nil)
			},
			call: func(service Progress) error {
				_, err := service.UnmarkEpisode(ctx, userId, 300, 400, 500)

				return err
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			repository := repositories.NewMockSeriesProgressRepository(ctrl)
			statsCache := NewMockStatsCache(ctrl)

			tt.before(repository)
			statsCache.EXPECT().Invalidate(ctx, userId).Times(1)

			require.NoError(t, tt.call(NewProgress(repository, statsCache, newTestLogger())))
		})
	}
}

func Test_Progress_LeavesTheCacheAloneOnFailure(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	userId := uuid.New()

	repository := repositories.NewMockSeriesProgressRepository(ctrl)
	statsCache := NewMockStatsCache(ctrl)

	repository.EXPECT().MarkEpisodeWatched(ctx, userId, gomock.Any(), gomock.Any(), gomock.Any()).Return(nil, assert.AnError)
	service := NewProgress(repository, statsCache, newTestLogger())

	_, err := service.MarkEpisode(ctx, userId, models.SeriesInput{}, models.SeasonInput{}, models.EpisodeInput{})

	require.Error(t, err)
}

func Test_Progress_ReadsDoNotInvalidate(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	userId := uuid.New()

	repository := repositories.NewMockSeriesProgressRepository(ctrl)
	statsCache := NewMockStatsCache(ctrl)

	repository.EXPECT().Progress(ctx, userId, uint64(300)).Return(&models.SeriesProgress{}, nil)

	service := NewProgress(repository, statsCache, newTestLogger())

	_, err := service.Get(ctx, userId, 300)

	require.NoError(t, err)
}
