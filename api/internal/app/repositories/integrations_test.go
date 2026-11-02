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

func Test_IntegrationRepository_Upsert(t *testing.T) {
	ctx := context.Background()
	client := newRepoTestClient(t)
	repository := NewIntegrationRepository(client)
	userID := newProgressTestUser(t, client, "integration.upsert")

	first, err := repository.Upsert(ctx, &models.Integration{
		UserId:    userID,
		Provider:  models.JellyfinProvider,
		TokenHash: "a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1",
	})
	require.NoError(t, err)

	t.Run("Creates the link", func(t *testing.T) {
		assert.NotEqual(t, uuid.Nil, first.ID)
		assert.Equal(t, userID, first.UserId)
		assert.Equal(t, models.JellyfinProvider, first.Provider)
		assert.Equal(t, "a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1a1", first.TokenHash)
	})

	t.Run("Second upsert replaces the hash on the same row", func(t *testing.T) {
		second, err := repository.Upsert(ctx, &models.Integration{
			UserId:    userID,
			Provider:  models.JellyfinProvider,
			TokenHash: "b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2",
		})
		require.NoError(t, err)

		assert.Equal(t, first.ID, second.ID)
		assert.Equal(t, "b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2b2", second.TokenHash)
		assert.Equal(t, first.CreatedAt, second.CreatedAt)
		assert.True(t, second.UpdatedAt.After(first.UpdatedAt))

		result, err := repository.FindByTokenHash(ctx, first.TokenHash, models.JellyfinProvider)
		require.ErrorIs(t, err, pgx.ErrNoRows)
		assert.Nil(t, result)
	})

	t.Run("Keeps an existing connection", func(t *testing.T) {
		connectedID := newProgressTestUser(t, client, "integr.upsert.conn")

		connection, err := repository.UpsertConnection(ctx, &models.Integration{
			UserId:           connectedID,
			Provider:         models.JellyfinProvider,
			JellyfinUserId:   "jf-upsert",
			JellyfinUsername: "upsert",
			JellyfinToken:    []byte("sealed-upsert"),
		})
		require.NoError(t, err)

		result, err := repository.Upsert(ctx, &models.Integration{
			UserId:    connectedID,
			Provider:  models.JellyfinProvider,
			TokenHash: "a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7",
		})
		require.NoError(t, err)

		assert.Equal(t, connection.ID, result.ID)
		assert.Equal(t, "a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7a7", result.TokenHash)
		assert.Equal(t, "jf-upsert", result.JellyfinUserId)
		assert.Equal(t, "upsert", result.JellyfinUsername)
		assert.Equal(t, []byte("sealed-upsert"), result.JellyfinToken)
	})

	t.Run("Unknown provider is rejected by the enum", func(t *testing.T) {
		result, err := repository.Upsert(ctx, &models.Integration{
			UserId:    userID,
			Provider:  "plex",
			TokenHash: "c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3",
		})
		require.Error(t, err)
		assert.Nil(t, result)
	})

	t.Run("Unknown user fails foreign key", func(t *testing.T) {
		result, err := repository.Upsert(ctx, &models.Integration{
			UserId:    uuid.New(),
			Provider:  models.JellyfinProvider,
			TokenHash: "c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3c3",
		})
		require.Error(t, err)
		assert.Nil(t, result)
	})
}

func Test_IntegrationRepository_UpsertConnection(t *testing.T) {
	ctx := context.Background()
	client := newRepoTestClient(t)
	repository := NewIntegrationRepository(client)
	userID := newProgressTestUser(t, client, "integr.connection")

	first, err := repository.UpsertConnection(ctx, &models.Integration{
		UserId:           userID,
		Provider:         models.JellyfinProvider,
		JellyfinUserId:   "jf-first",
		JellyfinUsername: "first",
		JellyfinToken:    []byte("sealed-first"),
	})
	require.NoError(t, err)

	t.Run("Creates the row without a webhook token", func(t *testing.T) {
		assert.NotEqual(t, uuid.Nil, first.ID)
		assert.Equal(t, userID, first.UserId)
		assert.Equal(t, models.JellyfinProvider, first.Provider)
		assert.Empty(t, first.TokenHash)
		assert.Equal(t, "jf-first", first.JellyfinUserId)
		assert.Equal(t, "first", first.JellyfinUsername)
		assert.Equal(t, []byte("sealed-first"), first.JellyfinToken)
	})

	t.Run("Reconnect replaces the connection on the same row", func(t *testing.T) {
		second, err := repository.UpsertConnection(ctx, &models.Integration{
			UserId:           userID,
			Provider:         models.JellyfinProvider,
			JellyfinUserId:   "jf-second",
			JellyfinUsername: "second",
			JellyfinToken:    []byte("sealed-second"),
		})
		require.NoError(t, err)

		assert.Equal(t, first.ID, second.ID)
		assert.Equal(t, "jf-second", second.JellyfinUserId)
		assert.Equal(t, "second", second.JellyfinUsername)
		assert.Equal(t, []byte("sealed-second"), second.JellyfinToken)
		assert.Equal(t, first.CreatedAt, second.CreatedAt)
		assert.True(t, second.UpdatedAt.After(first.UpdatedAt))
	})

	t.Run("Keeps an existing webhook token", func(t *testing.T) {
		tokenID := newProgressTestUser(t, client, "integr.conn.token")

		link, err := repository.Upsert(ctx, &models.Integration{
			UserId:    tokenID,
			Provider:  models.JellyfinProvider,
			TokenHash: "a8a8a8a8a8a8a8a8a8a8a8a8a8a8a8a8a8a8a8a8a8a8a8a8a8a8a8a8a8a8a8a8",
		})
		require.NoError(t, err)

		result, err := repository.UpsertConnection(ctx, &models.Integration{
			UserId:           tokenID,
			Provider:         models.JellyfinProvider,
			JellyfinUserId:   "jf-token",
			JellyfinUsername: "token",
			JellyfinToken:    []byte("sealed-token"),
		})
		require.NoError(t, err)

		assert.Equal(t, link.ID, result.ID)
		assert.Equal(t, link.TokenHash, result.TokenHash)
		assert.Equal(t, "jf-token", result.JellyfinUserId)
	})
}

func Test_IntegrationRepository_FindByUser(t *testing.T) {
	ctx := context.Background()
	client := newRepoTestClient(t)
	repository := NewIntegrationRepository(client)
	userID := newProgressTestUser(t, client, "integr.find.user")
	otherID := newProgressTestUser(t, client, "integr.find.none")

	created, err := repository.UpsertConnection(ctx, &models.Integration{
		UserId:           userID,
		Provider:         models.JellyfinProvider,
		JellyfinUserId:   "jf-find",
		JellyfinUsername: "find",
		JellyfinToken:    []byte("sealed-find"),
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

func Test_IntegrationRepository_FindByTokenHash(t *testing.T) {
	ctx := context.Background()
	client := newRepoTestClient(t)
	repository := NewIntegrationRepository(client)
	userID := newProgressTestUser(t, client, "integration.find")
	deletedID := newProgressTestUser(t, client, "integr.find.deleted")

	const hash = "d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4d4"

	const deletedHash = "e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5e5"

	created, err := repository.Upsert(ctx, &models.Integration{UserId: userID, Provider: models.JellyfinProvider, TokenHash: hash})
	require.NoError(t, err)

	_, err = repository.Upsert(ctx, &models.Integration{UserId: deletedID, Provider: models.JellyfinProvider, TokenHash: deletedHash})
	require.NoError(t, err)

	_, err = client.Db().Exec(ctx, `UPDATE users SET deleted_at = NOW() WHERE id = $1`, deletedID)
	require.NoError(t, err)

	t.Run("Finds the link by hash", func(t *testing.T) {
		result, err := repository.FindByTokenHash(ctx, hash, models.JellyfinProvider)
		require.NoError(t, err)

		assert.Equal(t, created.ID, result.ID)
		assert.Equal(t, userID, result.UserId)
	})

	t.Run("Unknown hash is no rows", func(t *testing.T) {
		result, err := repository.FindByTokenHash(ctx, "0000000000000000000000000000000000000000000000000000000000000000", models.JellyfinProvider)
		require.ErrorIs(t, err, pgx.ErrNoRows)
		assert.Nil(t, result)
	})

	t.Run("Soft-deleted owner is no rows", func(t *testing.T) {
		result, err := repository.FindByTokenHash(ctx, deletedHash, models.JellyfinProvider)
		require.ErrorIs(t, err, pgx.ErrNoRows)
		assert.Nil(t, result)
	})

	t.Run("Row without a webhook token is no rows", func(t *testing.T) {
		connectedID := newProgressTestUser(t, client, "integr.find.null")

		_, err := repository.UpsertConnection(ctx, &models.Integration{
			UserId:           connectedID,
			Provider:         models.JellyfinProvider,
			JellyfinUserId:   "jf-null",
			JellyfinUsername: "null",
			JellyfinToken:    []byte("sealed-null"),
		})
		require.NoError(t, err)

		result, err := repository.FindByTokenHash(ctx, "", models.JellyfinProvider)
		require.ErrorIs(t, err, pgx.ErrNoRows)
		assert.Nil(t, result)
	})

	t.Run("Revoked link is no rows", func(t *testing.T) {
		require.NoError(t, repository.ClearToken(ctx, userID, models.JellyfinProvider))

		result, err := repository.FindByTokenHash(ctx, hash, models.JellyfinProvider)
		require.ErrorIs(t, err, pgx.ErrNoRows)
		assert.Nil(t, result)

		// a second revoke has nothing to remove and still succeeds
		require.NoError(t, repository.ClearToken(ctx, userID, models.JellyfinProvider))
	})
}

func Test_IntegrationRepository_ClearToken(t *testing.T) {
	ctx := context.Background()
	client := newRepoTestClient(t)
	repository := NewIntegrationRepository(client)

	tests := []struct {
		name      string
		login     string
		hash      string
		connected bool
	}{
		{
			name:      "Keeps the connection",
			login:     "integr.clear.conn",
			hash:      "b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9b9",
			connected: true,
		},
		{
			name:  "Deletes the row with no connection",
			login: "integr.clear.empty",
			hash:  "c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9c9",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			userID := newProgressTestUser(t, client, tt.login)

			_, err := repository.Upsert(ctx, &models.Integration{UserId: userID, Provider: models.JellyfinProvider, TokenHash: tt.hash})
			require.NoError(t, err)

			if tt.connected {
				_, err = repository.UpsertConnection(ctx, &models.Integration{
					UserId:           userID,
					Provider:         models.JellyfinProvider,
					JellyfinUserId:   "jf-clear",
					JellyfinUsername: "clear",
					JellyfinToken:    []byte("sealed-clear"),
				})
				require.NoError(t, err)
			}

			require.NoError(t, repository.ClearToken(ctx, userID, models.JellyfinProvider))

			_, err = repository.FindByTokenHash(ctx, tt.hash, models.JellyfinProvider)
			require.ErrorIs(t, err, pgx.ErrNoRows)

			result, err := repository.FindByUser(ctx, userID, models.JellyfinProvider)

			if !tt.connected {
				require.ErrorIs(t, err, pgx.ErrNoRows)
				assert.Nil(t, result)

				return
			}

			require.NoError(t, err)
			assert.Empty(t, result.TokenHash)
			assert.Equal(t, "jf-clear", result.JellyfinUserId)
			assert.Equal(t, "clear", result.JellyfinUsername)
			assert.Equal(t, []byte("sealed-clear"), result.JellyfinToken)
		})
	}
}

func Test_IntegrationRepository_ClearConnection(t *testing.T) {
	ctx := context.Background()
	client := newRepoTestClient(t)
	repository := NewIntegrationRepository(client)

	tests := []struct {
		name  string
		login string
		hash  string
	}{
		{
			name:  "Keeps the webhook token",
			login: "integr.disc.token",
			hash:  "d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9d9",
		},
		{
			name:  "Deletes the row with no webhook token",
			login: "integr.disc.empty",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			userID := newProgressTestUser(t, client, tt.login)

			if tt.hash != "" {
				_, err := repository.Upsert(ctx, &models.Integration{UserId: userID, Provider: models.JellyfinProvider, TokenHash: tt.hash})
				require.NoError(t, err)
			}

			_, err := repository.UpsertConnection(ctx, &models.Integration{
				UserId:           userID,
				Provider:         models.JellyfinProvider,
				JellyfinUserId:   "jf-disc",
				JellyfinUsername: "disc",
				JellyfinToken:    []byte("sealed-disc"),
			})
			require.NoError(t, err)

			require.NoError(t, repository.ClearConnection(ctx, userID, models.JellyfinProvider))

			result, err := repository.FindByUser(ctx, userID, models.JellyfinProvider)

			if tt.hash == "" {
				require.ErrorIs(t, err, pgx.ErrNoRows)
				assert.Nil(t, result)

				return
			}

			require.NoError(t, err)
			assert.Equal(t, tt.hash, result.TokenHash)
			assert.Empty(t, result.JellyfinUserId)
			assert.Empty(t, result.JellyfinUsername)
			assert.Nil(t, result.JellyfinToken)

			found, err := repository.FindByTokenHash(ctx, tt.hash, models.JellyfinProvider)
			require.NoError(t, err)
			assert.Equal(t, result.ID, found.ID)
		})
	}
}
