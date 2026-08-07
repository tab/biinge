package services

import (
	"context"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories"
)

func Test_Games_List(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockGameRepository(ctrl)
	service := NewGames(repository, newTestStatsCache(), newTestLogger())

	userId := uuid.New()
	pagination := &Pagination{Page: 1, PerPage: 24}

	tests := []struct {
		name     string
		before   func()
		expected []models.Game
		total    uint64
		error    error
	}{
		{
			name: "Success",
			before: func() {
				repository.EXPECT().List(ctx, userId, models.StateTypeWant, pagination.Limit(), pagination.Offset()).Return([]models.Game{
					{IgdbId: 1942, Title: "The Witcher 3", State: "want"},
				}, uint64(1), nil)
			},
			expected: []models.Game{
				{IgdbId: 1942, Title: "The Witcher 3", State: "want"},
			},
			total: 1,
		},
		{
			name: "Error",
			before: func() {
				repository.EXPECT().List(ctx, userId, models.StateTypeWant, pagination.Limit(), pagination.Offset()).Return(nil, uint64(0), assert.AnError)
			},
			total: 0,
			error: errors.ErrFailedToFetchGames,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, total, err := service.List(ctx, userId, models.StateTypeWant, pagination)

			if tt.error != nil {
				require.ErrorIs(t, err, tt.error)
				assert.Nil(t, result)
				assert.Zero(t, total)

				return
			}

			require.NoError(t, err)
			assert.Equal(t, tt.expected, result)
			assert.Equal(t, tt.total, total)
		})
	}
}

func Test_Games_Create(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockGameRepository(ctrl)
	service := NewGames(repository, newTestStatsCache(), newTestLogger())

	userId := uuid.New()
	params := &models.Game{
		UserId:     userId,
		IgdbId:     1942,
		Title:      "The Witcher 3",
		PosterPath: "co1wyy",
		Runtime:    3000,
		State:      models.StateTypeWant,
	}

	t.Run("Success", func(t *testing.T) {
		repository.EXPECT().Create(ctx, params).Return(&models.Game{IgdbId: 1942, State: models.StateTypeWant}, nil)

		result, err := service.Create(ctx, params)
		require.NoError(t, err)

		assert.Equal(t, uint64(1942), result.IgdbId)
	})

	t.Run("Error", func(t *testing.T) {
		repository.EXPECT().Create(ctx, params).Return(nil, assert.AnError)

		result, err := service.Create(ctx, params)
		require.ErrorIs(t, err, errors.ErrFailedToCreateGame)
		assert.Nil(t, result)
	})
}

func Test_Games_UpdateByIgdbId(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockGameRepository(ctrl)
	service := NewGames(repository, newTestStatsCache(), newTestLogger())

	userId := uuid.New()
	params := &models.Game{IgdbId: 1942, UserId: userId, State: models.StateTypePlayed, Pinned: true}

	t.Run("Success", func(t *testing.T) {
		repository.EXPECT().UpdateByIgdbId(ctx, params).Return(&models.Game{IgdbId: 1942, State: models.StateTypePlayed, Pinned: true}, nil)

		result, err := service.UpdateByIgdbId(ctx, params)
		require.NoError(t, err)

		assert.Equal(t, models.StateTypePlayed, result.State)
		assert.True(t, result.Pinned)
	})

	t.Run("Error", func(t *testing.T) {
		repository.EXPECT().UpdateByIgdbId(ctx, params).Return(nil, assert.AnError)

		result, err := service.UpdateByIgdbId(ctx, params)
		require.ErrorIs(t, err, errors.ErrFailedToUpdateGame)
		assert.Nil(t, result)
	})
}

func Test_Games_DeleteByIgdbId(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockGameRepository(ctrl)
	service := NewGames(repository, newTestStatsCache(), newTestLogger())

	userId := uuid.New()

	t.Run("Success", func(t *testing.T) {
		repository.EXPECT().DeleteByIgdbId(ctx, uint64(1942), userId).Return(nil)

		require.NoError(t, service.DeleteByIgdbId(ctx, 1942, userId))
	})

	t.Run("Error", func(t *testing.T) {
		repository.EXPECT().DeleteByIgdbId(ctx, uint64(1942), userId).Return(assert.AnError)

		require.ErrorIs(t, service.DeleteByIgdbId(ctx, 1942, userId), errors.ErrFailedToDeleteGame)
	})
}

func Test_Games_FindByIgdbId(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockGameRepository(ctrl)
	service := NewGames(repository, newTestStatsCache(), newTestLogger())

	userId := uuid.New()

	t.Run("Success", func(t *testing.T) {
		repository.EXPECT().FindByIgdbId(ctx, uint64(1942), userId).Return(&models.Game{IgdbId: 1942}, nil)

		result, err := service.FindByIgdbId(ctx, 1942, userId)
		require.NoError(t, err)

		assert.Equal(t, uint64(1942), result.IgdbId)
	})

	// a game the user never added is the ordinary case for the details screen
	t.Run("Missing row is a not found", func(t *testing.T) {
		repository.EXPECT().FindByIgdbId(ctx, uint64(1942), userId).Return(nil, pgx.ErrNoRows)

		result, err := service.FindByIgdbId(ctx, 1942, userId)
		require.ErrorIs(t, err, errors.ErrGameNotFound)
		assert.Nil(t, result)
	})
}

func Test_Games_FindGamesByIgdbIds(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockGameRepository(ctrl)
	service := NewGames(repository, newTestStatsCache(), newTestLogger())

	userId := uuid.New()
	ids := []uint64{1942, 2000}

	t.Run("Success", func(t *testing.T) {
		repository.EXPECT().FindGamesByIgdbIds(ctx, ids, userId).Return([]models.Game{{IgdbId: 1942}}, nil)

		result, err := service.FindGamesByIgdbIds(ctx, ids, userId)
		require.NoError(t, err)

		assert.Len(t, result, 1)
	})

	t.Run("Error", func(t *testing.T) {
		repository.EXPECT().FindGamesByIgdbIds(ctx, ids, userId).Return(nil, assert.AnError)

		result, err := service.FindGamesByIgdbIds(ctx, ids, userId)
		require.ErrorIs(t, err, errors.ErrFailedToFetchResults)
		assert.Nil(t, result)
	})
}
