package repositories

import (
	"context"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"biinge-api/internal/app/models"
)

func Test_IntegrationRepository_UpsertConnection(t *testing.T) {
	ctx := context.Background()
	client := newRepoTestClient(t)
	repository := NewIntegrationRepository(client)
	userID := newProgressTestUser(t, client, "integr.connection")

	first, err := repository.UpsertConnection(ctx, &models.Integration{
		UserId:         userID,
		Provider:       models.JellyfinProvider,
		ExternalUserId: "jf-first",
		Username:       "first",
		Token:          []byte("sealed-first"),
	})
	require.NoError(t, err)

	t.Run("Creates the row", func(t *testing.T) {
		assert.NotEqual(t, uuid.Nil, first.ID)
		assert.Equal(t, userID, first.UserId)
		assert.Equal(t, models.JellyfinProvider, first.Provider)
		assert.Equal(t, "jf-first", first.ExternalUserId)
		assert.Equal(t, "first", first.Username)
		assert.Equal(t, []byte("sealed-first"), first.Token)
	})

	t.Run("Reconnect replaces the connection on the same row", func(t *testing.T) {
		second, err := repository.UpsertConnection(ctx, &models.Integration{
			UserId:         userID,
			Provider:       models.JellyfinProvider,
			ExternalUserId: "jf-second",
			Username:       "second",
			Token:          []byte("sealed-second"),
		})
		require.NoError(t, err)

		assert.Equal(t, first.ID, second.ID)
		assert.Equal(t, "jf-second", second.ExternalUserId)
		assert.Equal(t, "second", second.Username)
		assert.Equal(t, []byte("sealed-second"), second.Token)
		assert.Equal(t, first.CreatedAt, second.CreatedAt)
		assert.True(t, second.UpdatedAt.After(first.UpdatedAt))
	})
}

func Test_IntegrationRepository_FindByUser(t *testing.T) {
	ctx := context.Background()
	client := newRepoTestClient(t)
	repository := NewIntegrationRepository(client)
	userID := newProgressTestUser(t, client, "integr.find.user")
	otherID := newProgressTestUser(t, client, "integr.find.none")

	created, err := repository.UpsertConnection(ctx, &models.Integration{
		UserId:         userID,
		Provider:       models.JellyfinProvider,
		ExternalUserId: "jf-find",
		Username:       "find",
		Token:          []byte("sealed-find"),
	})
	require.NoError(t, err)

	tests := []struct {
		name     string
		userID   uuid.UUID
		expected *models.Integration
		error    error
	}{
		{
			name:     "Finds the user's row",
			userID:   userID,
			expected: created,
		},
		{
			name:   "User without a row is no rows",
			userID: otherID,
			error:  pgx.ErrNoRows,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, err := repository.FindByUser(ctx, tt.userID, models.JellyfinProvider)

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

func Test_IntegrationRepository_ClearConnection(t *testing.T) {
	ctx := context.Background()
	client := newRepoTestClient(t)
	repository := NewIntegrationRepository(client)
	userID := newProgressTestUser(t, client, "integr.disc")

	_, err := repository.UpsertConnection(ctx, &models.Integration{
		UserId:         userID,
		Provider:       models.JellyfinProvider,
		ExternalUserId: "jf-disc",
		Username:       "disc",
		Token:          []byte("sealed-disc"),
	})
	require.NoError(t, err)

	require.NoError(t, repository.ClearConnection(ctx, userID, models.JellyfinProvider))

	result, err := repository.FindByUser(ctx, userID, models.JellyfinProvider)
	require.ErrorIs(t, err, pgx.ErrNoRows)
	assert.Nil(t, result)
}
