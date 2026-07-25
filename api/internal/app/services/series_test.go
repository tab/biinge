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

func Test_Series_List(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockSeriesRepository(ctrl)
	service := NewSeries(repository, newTestStatsCache(), newTestLogger())

	userId := uuid.New()
	pagination := &Pagination{Page: 1, PerPage: 24}

	tests := []struct {
		name     string
		before   func()
		expected []models.Series
		total    uint64
		error    error
	}{
		{
			name: "Success",
			before: func() {
				repository.EXPECT().List(ctx, userId, models.StateTypeWatching, pagination.Limit(), pagination.Offset()).Return([]models.Series{
					{TmdbId: 300, Title: "Breaking Bad", State: "watching"},
				}, uint64(1), nil)
			},
			expected: []models.Series{
				{TmdbId: 300, Title: "Breaking Bad", State: "watching"},
			},
			total: 1,
		},
		{
			name: "Error",
			before: func() {
				repository.EXPECT().List(ctx, userId, models.StateTypeWatching, pagination.Limit(), pagination.Offset()).Return(nil, uint64(0), assert.AnError)
			},
			expected: nil,
			total:    0,
			error:    errors.ErrFailedToFetchSeriesList,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, total, err := service.List(ctx, userId, models.StateTypeWatching, pagination)

			if tt.error != nil {
				require.ErrorIs(t, err, tt.error)
				assert.Nil(t, result)
				assert.Equal(t, uint64(0), total)
			} else {
				require.NoError(t, err)
				assert.Equal(t, tt.expected, result)
				assert.Equal(t, tt.total, total)
			}
		})
	}
}

func Test_Series_Create(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockSeriesRepository(ctrl)
	service := NewSeries(repository, newTestStatsCache(), newTestLogger())

	userId := uuid.New()
	id := uuid.New()

	params := &models.Series{
		UserId:        userId,
		TmdbId:        300,
		Title:         "Breaking Bad",
		PosterPath:    "/bb.jpg",
		SeasonsCount:  5,
		EpisodesCount: 62,
		Status:        "Ended",
		State:         "watching",
	}

	tests := []struct {
		name     string
		before   func()
		expected *models.Series
		error    error
	}{
		{
			name: "Success",
			before: func() {
				repository.EXPECT().Create(ctx, params).Return(&models.Series{
					ID:            id,
					UserId:        userId,
					TmdbId:        300,
					Title:         "Breaking Bad",
					PosterPath:    "/bb.jpg",
					SeasonsCount:  5,
					EpisodesCount: 62,
					Status:        "Ended",
					State:         "watching",
				}, nil)
			},
			expected: &models.Series{
				ID:            id,
				UserId:        userId,
				TmdbId:        300,
				Title:         "Breaking Bad",
				PosterPath:    "/bb.jpg",
				SeasonsCount:  5,
				EpisodesCount: 62,
				Status:        "Ended",
				State:         "watching",
			},
		},
		{
			name: "Error",
			before: func() {
				repository.EXPECT().Create(ctx, params).Return(nil, assert.AnError)
			},
			expected: nil,
			error:    errors.ErrFailedToCreateSeries,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, err := service.Create(ctx, params)

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

func Test_Series_Update(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockSeriesRepository(ctrl)
	service := NewSeries(repository, newTestStatsCache(), newTestLogger())

	id := uuid.New()

	params := &models.Series{
		ID:            id,
		Title:         "Breaking Bad",
		PosterPath:    "/bb.jpg",
		SeasonsCount:  5,
		EpisodesCount: 62,
		Status:        "Ended",
	}

	tests := []struct {
		name     string
		before   func()
		expected *models.Series
		error    error
	}{
		{
			name: "Success",
			before: func() {
				repository.EXPECT().Update(ctx, params).Return(&models.Series{
					ID:            id,
					Title:         "Breaking Bad",
					PosterPath:    "/bb.jpg",
					SeasonsCount:  5,
					EpisodesCount: 62,
					Status:        "Ended",
				}, nil)
			},
			expected: &models.Series{
				ID:            id,
				Title:         "Breaking Bad",
				PosterPath:    "/bb.jpg",
				SeasonsCount:  5,
				EpisodesCount: 62,
				Status:        "Ended",
			},
		},
		{
			name: "Error",
			before: func() {
				repository.EXPECT().Update(ctx, params).Return(nil, assert.AnError)
			},
			expected: nil,
			error:    errors.ErrFailedToUpdateSeries,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, err := service.Update(ctx, params)

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

func Test_Series_UpdateByTmdbId(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockSeriesRepository(ctrl)
	service := NewSeries(repository, newTestStatsCache(), newTestLogger())

	userId := uuid.New()

	params := &models.Series{
		TmdbId: 300,
		UserId: userId,
		State:  "watched",
		Pinned: true,
	}

	tests := []struct {
		name     string
		before   func()
		expected *models.Series
		error    error
	}{
		{
			name: "Success",
			before: func() {
				repository.EXPECT().UpdateByTmdbId(ctx, params).Return(&models.Series{
					TmdbId: 300,
					UserId: userId,
					State:  "watched",
					Pinned: true,
				}, nil)
			},
			expected: &models.Series{
				TmdbId: 300,
				UserId: userId,
				State:  "watched",
				Pinned: true,
			},
		},
		{
			name: "Error",
			before: func() {
				repository.EXPECT().UpdateByTmdbId(ctx, params).Return(nil, assert.AnError)
			},
			expected: nil,
			error:    errors.ErrFailedToUpdateSeries,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, err := service.UpdateByTmdbId(ctx, params)

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

func Test_Series_Delete(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockSeriesRepository(ctrl)
	service := NewSeries(repository, newTestStatsCache(), newTestLogger())

	id := uuid.New()

	tests := []struct {
		name   string
		before func()
		error  error
	}{
		{
			name: "Success",
			before: func() {
				repository.EXPECT().Delete(ctx, id).Return(nil)
			},
		},
		{
			name: "Error",
			before: func() {
				repository.EXPECT().Delete(ctx, id).Return(assert.AnError)
			},
			error: errors.ErrFailedToDeleteSeries,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			err := service.Delete(ctx, id)

			if tt.error != nil {
				require.ErrorIs(t, err, tt.error)
			} else {
				require.NoError(t, err)
			}
		})
	}
}

func Test_Series_DeleteByTmdbId(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockSeriesRepository(ctrl)
	service := NewSeries(repository, newTestStatsCache(), newTestLogger())

	userId := uuid.New()

	tests := []struct {
		name   string
		before func()
		error  error
	}{
		{
			name: "Success",
			before: func() {
				repository.EXPECT().DeleteByTmdbId(ctx, uint64(300), userId).Return(nil)
			},
		},
		{
			name: "Error",
			before: func() {
				repository.EXPECT().DeleteByTmdbId(ctx, uint64(300), userId).Return(assert.AnError)
			},
			error: errors.ErrFailedToDeleteSeries,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			err := service.DeleteByTmdbId(ctx, 300, userId)

			if tt.error != nil {
				require.ErrorIs(t, err, tt.error)
			} else {
				require.NoError(t, err)
			}
		})
	}
}

func Test_Series_FindById(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockSeriesRepository(ctrl)
	service := NewSeries(repository, newTestStatsCache(), newTestLogger())

	id := uuid.New()

	tests := []struct {
		name     string
		before   func()
		expected *models.Series
		error    error
	}{
		{
			name: "Success",
			before: func() {
				repository.EXPECT().FindById(ctx, id).Return(&models.Series{
					ID:     id,
					TmdbId: 300,
					Title:  "Breaking Bad",
				}, nil)
			},
			expected: &models.Series{
				ID:     id,
				TmdbId: 300,
				Title:  "Breaking Bad",
			},
		},
		{
			name: "Error",
			before: func() {
				repository.EXPECT().FindById(ctx, id).Return(nil, assert.AnError)
			},
			expected: nil,
			error:    errors.ErrSeriesNotFound,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, err := service.FindById(ctx, id)

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

func Test_Series_FindByTmdbId(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockSeriesRepository(ctrl)
	service := NewSeries(repository, newTestStatsCache(), newTestLogger())

	userId := uuid.New()

	tests := []struct {
		name     string
		before   func()
		expected *models.Series
		error    error
	}{
		{
			name: "Success",
			before: func() {
				repository.EXPECT().FindByTmdbId(ctx, uint64(300), userId).Return(&models.Series{
					TmdbId: 300,
					UserId: userId,
					Title:  "Breaking Bad",
				}, nil)
			},
			expected: &models.Series{
				TmdbId: 300,
				UserId: userId,
				Title:  "Breaking Bad",
			},
		},
		{
			name: "Error",
			before: func() {
				repository.EXPECT().FindByTmdbId(ctx, uint64(300), userId).Return(nil, assert.AnError)
			},
			expected: nil,
			error:    errors.ErrSeriesNotFound,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, err := service.FindByTmdbId(ctx, 300, userId)

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

func Test_Series_FindSeriesByTmdbIds(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockSeriesRepository(ctrl)
	service := NewSeries(repository, newTestStatsCache(), newTestLogger())

	userId := uuid.New()
	tmdbIds := []uint64{300, 400}

	tests := []struct {
		name     string
		before   func()
		expected []models.Series
		error    error
	}{
		{
			name: "Success",
			before: func() {
				repository.EXPECT().FindSeriesByTmdbIds(ctx, tmdbIds, userId).Return([]models.Series{
					{TmdbId: 300, State: "watching"},
					{TmdbId: 400, State: "want"},
				}, nil)
			},
			expected: []models.Series{
				{TmdbId: 300, State: "watching"},
				{TmdbId: 400, State: "want"},
			},
		},
		{
			name: "Error",
			before: func() {
				repository.EXPECT().FindSeriesByTmdbIds(ctx, tmdbIds, userId).Return(nil, assert.AnError)
			},
			expected: nil,
			error:    errors.ErrFailedToFetchResults,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, err := service.FindSeriesByTmdbIds(ctx, tmdbIds, userId)

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
