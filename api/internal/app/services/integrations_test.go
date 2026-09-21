package services

import (
	"context"
	"crypto/sha256"
	"encoding/hex"
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

func Test_Integrations_CreateToken(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockIntegrationRepository(ctrl)
	service := NewIntegrations(repository, newTestLogger())

	userId := uuid.New()

	tests := []struct {
		name   string
		before func() *string
		error  error
	}{
		{
			name: "Success stores the hash and returns the plaintext",
			before: func() *string {
				stored := new(string)

				repository.EXPECT().
					Upsert(ctx, gomock.Any()).
					DoAndReturn(func(_ context.Context, params *models.Integration) (*models.Integration, error) {
						assert.Equal(t, userId, params.UserId)
						assert.Equal(t, models.JellyfinProvider, params.Provider)

						*stored = params.TokenHash

						return params, nil
					})

				return stored
			},
		},
		{
			name: "Error",
			before: func() *string {
				repository.EXPECT().Upsert(ctx, gomock.Any()).Return(nil, assert.AnError)

				return nil
			},
			error: errors.ErrFailedToCreateIntegration,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			stored := tt.before()

			token, err := service.CreateToken(ctx, userId)

			if tt.error != nil {
				require.ErrorIs(t, err, tt.error)
				assert.Empty(t, token)

				return
			}

			require.NoError(t, err)
			assert.Len(t, token, 64)
			assert.Regexp(t, "^[0-9a-f]{64}$", token)

			sum := sha256.Sum256([]byte(token))
			assert.Equal(t, hex.EncodeToString(sum[:]), *stored)
			assert.NotEqual(t, token, *stored)
		})
	}
}

func Test_Integrations_CreateToken_IsRandom(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockIntegrationRepository(ctrl)
	service := NewIntegrations(repository, newTestLogger())

	repository.EXPECT().Upsert(ctx, gomock.Any()).Times(2).DoAndReturn(func(_ context.Context, params *models.Integration) (*models.Integration, error) {
		return params, nil
	})

	first, err := service.CreateToken(ctx, uuid.New())
	require.NoError(t, err)

	second, err := service.CreateToken(ctx, uuid.New())
	require.NoError(t, err)

	assert.NotEqual(t, first, second)
}

func Test_Integrations_Revoke(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockIntegrationRepository(ctrl)
	service := NewIntegrations(repository, newTestLogger())

	userId := uuid.New()

	tests := []struct {
		name   string
		before func()
		error  error
	}{
		{
			name: "Success",
			before: func() {
				repository.EXPECT().Delete(ctx, userId, models.JellyfinProvider).Return(nil)
			},
		},
		{
			name: "Error",
			before: func() {
				repository.EXPECT().Delete(ctx, userId, models.JellyfinProvider).Return(assert.AnError)
			},
			error: errors.ErrFailedToDeleteIntegration,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			err := service.Revoke(ctx, userId)

			if tt.error != nil {
				require.ErrorIs(t, err, tt.error)
				return
			}

			require.NoError(t, err)
		})
	}
}

func Test_Integrations_Authenticate(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockIntegrationRepository(ctrl)
	service := NewIntegrations(repository, newTestLogger())

	const token = "0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f"

	sum := sha256.Sum256([]byte(token))
	hash := hex.EncodeToString(sum[:])
	link := &models.Integration{ID: uuid.New(), UserId: uuid.New(), Provider: models.JellyfinProvider, TokenHash: hash}

	tests := []struct {
		name     string
		before   func()
		expected *models.Integration
		error    error
	}{
		{
			name: "Success looks the row up by hash",
			before: func() {
				repository.EXPECT().FindByTokenHash(ctx, hash, models.JellyfinProvider).Return(link, nil)
			},
			expected: link,
		},
		{
			name: "Unknown, revoked or soft-deleted owner is unauthorized",
			before: func() {
				repository.EXPECT().FindByTokenHash(ctx, hash, models.JellyfinProvider).Return(nil, pgx.ErrNoRows)
			},
			error: errors.ErrUnauthorized,
		},
		{
			name: "Repository failure",
			before: func() {
				repository.EXPECT().FindByTokenHash(ctx, hash, models.JellyfinProvider).Return(nil, assert.AnError)
			},
			error: errors.ErrFailedToAuthenticateIntegration,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, err := service.Authenticate(ctx, token)

			if tt.error != nil {
				require.ErrorIs(t, err, tt.error)
				assert.Nil(t, result)

				return
			}

			require.NoError(t, err)
			assert.Equal(t, tt.expected, result)
		})
	}
}
