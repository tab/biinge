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
	"biinge-api/internal/config"
	"biinge-api/internal/config/logger"
)

// newTestLogger builds a logger backed by a test config for service unit tests
func newTestLogger() *logger.Logger {
	return logger.NewLogger(&config.Config{
		AppEnv:   "test",
		AppAddr:  "localhost:8080",
		LogLevel: "info",
	})
}

func Test_Movies_List(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockMovieRepository(ctrl)
	service := NewMovies(repository, newTestLogger())

	userId := uuid.New()
	pagination := &Pagination{Page: 1, PerPage: 24}

	tests := []struct {
		name     string
		before   func()
		expected []models.Movie
		total    uint64
		error    error
	}{
		{
			name: "Success",
			before: func() {
				repository.EXPECT().List(ctx, userId, "want", pagination.Limit(), pagination.Offset()).Return([]models.Movie{
					{TmdbId: 100, Title: "The Matrix", State: "want"},
				}, uint64(1), nil)
			},
			expected: []models.Movie{
				{TmdbId: 100, Title: "The Matrix", State: "want"},
			},
			total: 1,
		},
		{
			name: "Error",
			before: func() {
				repository.EXPECT().List(ctx, userId, "want", pagination.Limit(), pagination.Offset()).Return(nil, uint64(0), assert.AnError)
			},
			expected: nil,
			total:    0,
			error:    errors.ErrFailedToFetchMovies,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, total, err := service.List(ctx, userId, "want", pagination)

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

func Test_Movies_Create(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockMovieRepository(ctrl)
	service := NewMovies(repository, newTestLogger())

	userId := uuid.New()
	id := uuid.New()

	params := &models.Movie{
		UserId:     userId,
		TmdbId:     100,
		Title:      "The Matrix",
		PosterPath: "/matrix.jpg",
		Runtime:    136,
		State:      "want",
	}

	tests := []struct {
		name     string
		before   func()
		expected *models.Movie
		error    error
	}{
		{
			name: "Success",
			before: func() {
				repository.EXPECT().Create(ctx, params).Return(&models.Movie{
					ID:         id,
					UserId:     userId,
					TmdbId:     100,
					Title:      "The Matrix",
					PosterPath: "/matrix.jpg",
					Runtime:    136,
					State:      "want",
				}, nil)
			},
			expected: &models.Movie{
				ID:         id,
				UserId:     userId,
				TmdbId:     100,
				Title:      "The Matrix",
				PosterPath: "/matrix.jpg",
				Runtime:    136,
				State:      "want",
			},
		},
		{
			name: "Error",
			before: func() {
				repository.EXPECT().Create(ctx, params).Return(nil, assert.AnError)
			},
			expected: nil,
			error:    errors.ErrFailedToCreateMovie,
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

func Test_Movies_Update(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockMovieRepository(ctrl)
	service := NewMovies(repository, newTestLogger())

	id := uuid.New()

	params := &models.Movie{
		ID:         id,
		Title:      "The Matrix",
		PosterPath: "/matrix.jpg",
		Runtime:    136,
	}

	tests := []struct {
		name     string
		before   func()
		expected *models.Movie
		error    error
	}{
		{
			name: "Success",
			before: func() {
				repository.EXPECT().Update(ctx, params).Return(&models.Movie{
					ID:         id,
					Title:      "The Matrix",
					PosterPath: "/matrix.jpg",
					Runtime:    136,
				}, nil)
			},
			expected: &models.Movie{
				ID:         id,
				Title:      "The Matrix",
				PosterPath: "/matrix.jpg",
				Runtime:    136,
			},
		},
		{
			name: "Error",
			before: func() {
				repository.EXPECT().Update(ctx, params).Return(nil, assert.AnError)
			},
			expected: nil,
			error:    errors.ErrFailedToUpdateMovie,
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

func Test_Movies_UpdateByTmdbId(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockMovieRepository(ctrl)
	service := NewMovies(repository, newTestLogger())

	userId := uuid.New()

	params := &models.Movie{
		TmdbId: 100,
		UserId: userId,
		State:  "watched",
		Pinned: true,
	}

	tests := []struct {
		name     string
		before   func()
		expected *models.Movie
		error    error
	}{
		{
			name: "Success",
			before: func() {
				repository.EXPECT().UpdateByTmdbId(ctx, params).Return(&models.Movie{
					TmdbId: 100,
					UserId: userId,
					State:  "watched",
					Pinned: true,
				}, nil)
			},
			expected: &models.Movie{
				TmdbId: 100,
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
			error:    errors.ErrFailedToUpdateMovie,
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

func Test_Movies_Delete(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockMovieRepository(ctrl)
	service := NewMovies(repository, newTestLogger())

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
			error: errors.ErrFailedToDeleteMovie,
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

func Test_Movies_DeleteByTmdbId(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockMovieRepository(ctrl)
	service := NewMovies(repository, newTestLogger())

	userId := uuid.New()

	tests := []struct {
		name   string
		before func()
		error  error
	}{
		{
			name: "Success",
			before: func() {
				repository.EXPECT().DeleteByTmdbId(ctx, uint64(100), userId).Return(nil)
			},
		},
		{
			name: "Error",
			before: func() {
				repository.EXPECT().DeleteByTmdbId(ctx, uint64(100), userId).Return(assert.AnError)
			},
			error: errors.ErrFailedToDeleteMovie,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			err := service.DeleteByTmdbId(ctx, 100, userId)

			if tt.error != nil {
				require.ErrorIs(t, err, tt.error)
			} else {
				require.NoError(t, err)
			}
		})
	}
}

func Test_Movies_FindById(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockMovieRepository(ctrl)
	service := NewMovies(repository, newTestLogger())

	id := uuid.New()

	tests := []struct {
		name     string
		before   func()
		expected *models.Movie
		error    error
	}{
		{
			name: "Success",
			before: func() {
				repository.EXPECT().FindById(ctx, id).Return(&models.Movie{
					ID:     id,
					TmdbId: 100,
					Title:  "The Matrix",
				}, nil)
			},
			expected: &models.Movie{
				ID:     id,
				TmdbId: 100,
				Title:  "The Matrix",
			},
		},
		{
			name: "Error",
			before: func() {
				repository.EXPECT().FindById(ctx, id).Return(nil, assert.AnError)
			},
			expected: nil,
			error:    errors.ErrMovieNotFound,
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

func Test_Movies_FindByTmdbId(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockMovieRepository(ctrl)
	service := NewMovies(repository, newTestLogger())

	userId := uuid.New()

	tests := []struct {
		name     string
		before   func()
		expected *models.Movie
		error    error
	}{
		{
			name: "Success",
			before: func() {
				repository.EXPECT().FindByTmdbId(ctx, uint64(100), userId).Return(&models.Movie{
					TmdbId: 100,
					UserId: userId,
					Title:  "The Matrix",
				}, nil)
			},
			expected: &models.Movie{
				TmdbId: 100,
				UserId: userId,
				Title:  "The Matrix",
			},
		},
		{
			name: "Error",
			before: func() {
				repository.EXPECT().FindByTmdbId(ctx, uint64(100), userId).Return(nil, assert.AnError)
			},
			expected: nil,
			error:    errors.ErrMovieNotFound,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, err := service.FindByTmdbId(ctx, 100, userId)

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

func Test_Movies_FindMoviesByTmdbIds(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockMovieRepository(ctrl)
	service := NewMovies(repository, newTestLogger())

	userId := uuid.New()
	tmdbIds := []uint64{100, 200}

	tests := []struct {
		name     string
		before   func()
		expected []models.Movie
		error    error
	}{
		{
			name: "Success",
			before: func() {
				repository.EXPECT().FindMoviesByTmdbIds(ctx, tmdbIds, userId).Return([]models.Movie{
					{TmdbId: 100, State: "want"},
					{TmdbId: 200, State: "watched"},
				}, nil)
			},
			expected: []models.Movie{
				{TmdbId: 100, State: "want"},
				{TmdbId: 200, State: "watched"},
			},
		},
		{
			name: "Error",
			before: func() {
				repository.EXPECT().FindMoviesByTmdbIds(ctx, tmdbIds, userId).Return(nil, assert.AnError)
			},
			expected: nil,
			error:    errors.ErrFailedToFetchResults,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, err := service.FindMoviesByTmdbIds(ctx, tmdbIds, userId)

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
