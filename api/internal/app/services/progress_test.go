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

func Test_Progress_MarkShow(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockSeriesProgressRepository(ctrl)
	service := NewProgress(repository, newTestLogger())

	userId := uuid.New()
	show := models.ShowInput{
		Series: models.SeriesInput{TmdbId: 300, Title: "Breaking Bad", SeasonsCount: 5, EpisodesCount: 62},
		Seasons: []models.SeasonInput{
			{TmdbId: 50, Number: 1, EpisodesCount: 7},
		},
	}

	tests := []struct {
		name     string
		before   func()
		expected *models.SeriesProgress
		error    error
	}{
		{
			name: "Success",
			before: func() {
				repository.EXPECT().MarkShowWatched(ctx, userId, show).Return(&models.SeriesProgress{
					SeriesTmdbId: 300,
					State:        "watched",
				}, nil)
			},
			expected: &models.SeriesProgress{
				SeriesTmdbId: 300,
				State:        "watched",
			},
		},
		{
			name: "Error",
			before: func() {
				repository.EXPECT().MarkShowWatched(ctx, userId, show).Return(nil, assert.AnError)
			},
			expected: nil,
			error:    errors.ErrFailedToUpdateProgress,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, err := service.MarkShow(ctx, userId, show)

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

func Test_Progress_UnmarkShow(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockSeriesProgressRepository(ctrl)
	service := NewProgress(repository, newTestLogger())

	userId := uuid.New()

	tests := []struct {
		name     string
		before   func()
		expected *models.SeriesProgress
		error    error
	}{
		{
			name: "Success",
			before: func() {
				repository.EXPECT().UnmarkShowWatched(ctx, userId, uint64(300)).Return(&models.SeriesProgress{
					SeriesTmdbId: 300,
					State:        "want",
					TrackedState: "want",
				}, nil)
			},
			expected: &models.SeriesProgress{
				SeriesTmdbId: 300,
				State:        "want",
				TrackedState: "want",
			},
		},
		{
			name: "Error",
			before: func() {
				repository.EXPECT().UnmarkShowWatched(ctx, userId, uint64(300)).Return(nil, assert.AnError)
			},
			expected: nil,
			error:    errors.ErrFailedToUpdateProgress,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, err := service.UnmarkShow(ctx, userId, 300)

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

func Test_Progress_MarkSeason(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockSeriesProgressRepository(ctrl)
	service := NewProgress(repository, newTestLogger())

	userId := uuid.New()
	seriesInput := models.SeriesInput{TmdbId: 300, Title: "Breaking Bad", SeasonsCount: 5, EpisodesCount: 62}
	seasonInput := models.SeasonInput{TmdbId: 50, Number: 1, EpisodesCount: 7}

	tests := []struct {
		name     string
		before   func()
		expected *models.SeriesProgress
		error    error
	}{
		{
			name: "Success",
			before: func() {
				repository.EXPECT().MarkSeasonWatched(ctx, userId, seriesInput, seasonInput).Return(&models.SeriesProgress{
					SeriesTmdbId:   300,
					State:          "watching",
					WatchedSeasons: []uint64{50},
				}, nil)
			},
			expected: &models.SeriesProgress{
				SeriesTmdbId:   300,
				State:          "watching",
				WatchedSeasons: []uint64{50},
			},
		},
		{
			name: "Error",
			before: func() {
				repository.EXPECT().MarkSeasonWatched(ctx, userId, seriesInput, seasonInput).Return(nil, assert.AnError)
			},
			expected: nil,
			error:    errors.ErrFailedToUpdateProgress,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, err := service.MarkSeason(ctx, userId, seriesInput, seasonInput)

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

func Test_Progress_UnmarkSeason(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockSeriesProgressRepository(ctrl)
	service := NewProgress(repository, newTestLogger())

	userId := uuid.New()

	tests := []struct {
		name     string
		before   func()
		expected *models.SeriesProgress
		error    error
	}{
		{
			name: "Success",
			before: func() {
				repository.EXPECT().UnmarkSeasonWatched(ctx, userId, uint64(300), uint64(50)).Return(&models.SeriesProgress{
					SeriesTmdbId: 300,
					State:        "watching",
				}, nil)
			},
			expected: &models.SeriesProgress{
				SeriesTmdbId: 300,
				State:        "watching",
			},
		},
		{
			name: "Error",
			before: func() {
				repository.EXPECT().UnmarkSeasonWatched(ctx, userId, uint64(300), uint64(50)).Return(nil, assert.AnError)
			},
			expected: nil,
			error:    errors.ErrFailedToUpdateProgress,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, err := service.UnmarkSeason(ctx, userId, 300, 50)

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

func Test_Progress_MarkEpisode(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockSeriesProgressRepository(ctrl)
	service := NewProgress(repository, newTestLogger())

	userId := uuid.New()
	seriesInput := models.SeriesInput{TmdbId: 300, Title: "Breaking Bad", SeasonsCount: 5, EpisodesCount: 62}
	seasonInput := models.SeasonInput{TmdbId: 50, Number: 1, EpisodesCount: 7}
	episodeInput := models.EpisodeInput{TmdbId: 80, Title: "Pilot", Runtime: 58}

	tests := []struct {
		name     string
		before   func()
		expected *models.SeriesProgress
		error    error
	}{
		{
			name: "Success",
			before: func() {
				repository.EXPECT().MarkEpisodeWatched(ctx, userId, seriesInput, seasonInput, episodeInput).Return(&models.SeriesProgress{
					SeriesTmdbId:    300,
					State:           "watching",
					WatchedEpisodes: []uint64{80},
				}, nil)
			},
			expected: &models.SeriesProgress{
				SeriesTmdbId:    300,
				State:           "watching",
				WatchedEpisodes: []uint64{80},
			},
		},
		{
			name: "Error",
			before: func() {
				repository.EXPECT().MarkEpisodeWatched(ctx, userId, seriesInput, seasonInput, episodeInput).Return(nil, assert.AnError)
			},
			expected: nil,
			error:    errors.ErrFailedToUpdateProgress,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, err := service.MarkEpisode(ctx, userId, seriesInput, seasonInput, episodeInput)

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

func Test_Progress_UnmarkEpisode(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockSeriesProgressRepository(ctrl)
	service := NewProgress(repository, newTestLogger())

	userId := uuid.New()

	tests := []struct {
		name     string
		before   func()
		expected *models.SeriesProgress
		error    error
	}{
		{
			name: "Success",
			before: func() {
				repository.EXPECT().UnmarkEpisodeWatched(ctx, userId, uint64(300), uint64(50), uint64(80)).Return(&models.SeriesProgress{
					SeriesTmdbId: 300,
					State:        "watching",
				}, nil)
			},
			expected: &models.SeriesProgress{
				SeriesTmdbId: 300,
				State:        "watching",
			},
		},
		{
			name: "Error",
			before: func() {
				repository.EXPECT().UnmarkEpisodeWatched(ctx, userId, uint64(300), uint64(50), uint64(80)).Return(nil, assert.AnError)
			},
			expected: nil,
			error:    errors.ErrFailedToUpdateProgress,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, err := service.UnmarkEpisode(ctx, userId, 300, 50, 80)

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

func Test_Progress_Get(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockSeriesProgressRepository(ctrl)
	service := NewProgress(repository, newTestLogger())

	userId := uuid.New()

	tests := []struct {
		name     string
		before   func()
		expected *models.SeriesProgress
		error    error
	}{
		{
			name: "Success",
			before: func() {
				repository.EXPECT().Progress(ctx, userId, uint64(300)).Return(&models.SeriesProgress{
					SeriesTmdbId:    300,
					State:           "watching",
					TrackedState:    "watching",
					WatchedSeasons:  []uint64{50},
					WatchedEpisodes: []uint64{80, 81},
				}, nil)
			},
			expected: &models.SeriesProgress{
				SeriesTmdbId:    300,
				State:           "watching",
				TrackedState:    "watching",
				WatchedSeasons:  []uint64{50},
				WatchedEpisodes: []uint64{80, 81},
			},
		},
		{
			name: "Error",
			before: func() {
				repository.EXPECT().Progress(ctx, userId, uint64(300)).Return(nil, assert.AnError)
			},
			expected: nil,
			error:    errors.ErrFailedToFetchProgress,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, err := service.Get(ctx, userId, 300)

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
