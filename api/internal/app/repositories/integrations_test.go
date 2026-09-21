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

	t.Run("Revoked link is no rows", func(t *testing.T) {
		require.NoError(t, repository.Delete(ctx, userID, models.JellyfinProvider))

		result, err := repository.FindByTokenHash(ctx, hash, models.JellyfinProvider)
		require.ErrorIs(t, err, pgx.ErrNoRows)
		assert.Nil(t, result)

		// a second revoke has nothing to remove and still succeeds
		require.NoError(t, repository.Delete(ctx, userID, models.JellyfinProvider))
	})
}
