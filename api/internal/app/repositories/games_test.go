package repositories

import (
	"context"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"biinge-api/internal/app/models"
)

func Test_GameRepository_Create(t *testing.T) {
	ctx := context.Background()
	client := newRepoTestClient(t)
	repository := NewGameRepository(client)
	userID := newProgressTestUser(t, client, "game.create")

	t.Run("Success", func(t *testing.T) {
		result, err := repository.Create(ctx, &models.Game{
			UserId:     userID,
			IgdbId:     800001,
			Title:      "The Witcher 3",
			PosterPath: "co1wyy",
			Runtime:    3000,
			State:      models.StateTypePlayed,
		})
		require.NoError(t, err)

		assert.NotEqual(t, uuid.Nil, result.ID)
		assert.Equal(t, userID, result.UserId)
		assert.Equal(t, uint64(800001), result.IgdbId)
		assert.Equal(t, "The Witcher 3", result.Title)
		assert.Equal(t, "co1wyy", result.PosterPath)
		assert.Equal(t, uint64(3000), result.Runtime)
		assert.Equal(t, models.StateTypePlayed, result.State)
		assert.False(t, result.Pinned)
		// entering the played state stamps the timestamp the statistics will read
		assert.False(t, result.PlayedAt.IsZero())
	})

	t.Run("Want state leaves the played timestamp unset", func(t *testing.T) {
		result, err := repository.Create(ctx, &models.Game{
			UserId:     userID,
			IgdbId:     800002,
			Title:      "Elden Ring",
			PosterPath: "co4jni",
			Runtime:    3300,
			State:      models.StateTypeWant,
		})
		require.NoError(t, err)

		assert.True(t, result.PlayedAt.IsZero())
	})

	t.Run("Unknown user fails foreign key", func(t *testing.T) {
		result, err := repository.Create(ctx, &models.Game{
			UserId:     uuid.New(),
			IgdbId:     800003,
			Title:      "Orphan",
			PosterPath: "co0",
			State:      models.StateTypeWant,
		})
		require.Error(t, err)
		assert.Nil(t, result)
	})

	t.Run("Same game twice for one user violates the unique index", func(t *testing.T) {
		_, err := repository.Create(ctx, &models.Game{
			UserId:     userID,
			IgdbId:     800001,
			Title:      "The Witcher 3",
			PosterPath: "co1wyy",
			State:      models.StateTypeWant,
		})
		require.Error(t, err)
	})
}

func Test_GameRepository_List(t *testing.T) {
	ctx := context.Background()
	client := newRepoTestClient(t)
	repository := NewGameRepository(client)
	userID := newProgressTestUser(t, client, "game.list")

	_, err := repository.Create(ctx, &models.Game{
		UserId: userID, IgdbId: 810001, Title: "Want One", PosterPath: "co1", State: models.StateTypeWant,
	})
	require.NoError(t, err)

	_, err = repository.Create(ctx, &models.Game{
		UserId: userID, IgdbId: 810002, Title: "Want Two", PosterPath: "co2", State: models.StateTypeWant,
	})
	require.NoError(t, err)

	_, err = repository.Create(ctx, &models.Game{
		UserId: userID, IgdbId: 810003, Title: "Played", PosterPath: "co3", State: models.StateTypePlayed,
	})
	require.NoError(t, err)

	t.Run("Scoped to the requested state", func(t *testing.T) {
		rows, total, err := repository.List(ctx, userID, models.StateTypeWant, 24, 0)
		require.NoError(t, err)

		assert.Len(t, rows, 2)
		assert.Equal(t, uint64(2), total)
	})

	t.Run("Pinned rows sort first", func(t *testing.T) {
		_, err := repository.UpdateByIgdbId(ctx, &models.Game{
			IgdbId: 810001, UserId: userID, State: models.StateTypeWant, Pinned: true,
		})
		require.NoError(t, err)

		rows, _, err := repository.List(ctx, userID, models.StateTypeWant, 24, 0)
		require.NoError(t, err)

		require.NotEmpty(t, rows)
		assert.Equal(t, uint64(810001), rows[0].IgdbId)
		assert.True(t, rows[0].Pinned)
	})

	t.Run("Total counts the whole state, not the page", func(t *testing.T) {
		rows, total, err := repository.List(ctx, userID, models.StateTypeWant, 1, 0)
		require.NoError(t, err)

		assert.Len(t, rows, 1)
		assert.Equal(t, uint64(2), total)
	})

	t.Run("Empty state", func(t *testing.T) {
		rows, total, err := repository.List(ctx, userID, models.StateTypeWatching, 24, 0)
		require.NoError(t, err)

		assert.Empty(t, rows)
		assert.Zero(t, total)
	})
}

func Test_GameRepository_UpdateByIgdbId(t *testing.T) {
	ctx := context.Background()
	client := newRepoTestClient(t)
	repository := NewGameRepository(client)
	userID := newProgressTestUser(t, client, "game.update")

	_, err := repository.Create(ctx, &models.Game{
		UserId: userID, IgdbId: 820001, Title: "Returnal", PosterPath: "co5", State: models.StateTypeWant,
	})
	require.NoError(t, err)

	t.Run("Moving to played stamps the timestamp", func(t *testing.T) {
		result, err := repository.UpdateByIgdbId(ctx, &models.Game{
			IgdbId: 820001, UserId: userID, State: models.StateTypePlayed,
		})
		require.NoError(t, err)

		assert.Equal(t, models.StateTypePlayed, result.State)
		assert.False(t, result.PlayedAt.IsZero())
	})

	// replaying a finished game drops it out of the statistics until it is finished again
	t.Run("Moving from played to playing clears the timestamp", func(t *testing.T) {
		result, err := repository.UpdateByIgdbId(ctx, &models.Game{
			IgdbId: 820001, UserId: userID, State: models.StateTypePlaying,
		})
		require.NoError(t, err)

		assert.Equal(t, models.StateTypePlaying, result.State)
		assert.True(t, result.PlayedAt.IsZero())
	})

	t.Run("Moving back to want clears the timestamp", func(t *testing.T) {
		result, err := repository.UpdateByIgdbId(ctx, &models.Game{
			IgdbId: 820001, UserId: userID, State: models.StateTypeWant,
		})
		require.NoError(t, err)

		assert.Equal(t, models.StateTypeWant, result.State)
		assert.True(t, result.PlayedAt.IsZero())
	})

	t.Run("Another user's game is untouched", func(t *testing.T) {
		result, err := repository.UpdateByIgdbId(ctx, &models.Game{
			IgdbId: 820001, UserId: uuid.New(), State: models.StateTypePlayed,
		})
		require.Error(t, err)
		assert.Nil(t, result)
	})
}

func Test_GameRepository_Update(t *testing.T) {
	ctx := context.Background()
	client := newRepoTestClient(t)
	repository := NewGameRepository(client)
	userID := newProgressTestUser(t, client, "game.metadata")

	created, err := repository.Create(ctx, &models.Game{
		UserId: userID, IgdbId: 830001, Title: "Old Title", PosterPath: "co-expired", Runtime: 100, State: models.StateTypeWant,
	})
	require.NoError(t, err)

	t.Run("Refreshes metadata without touching state", func(t *testing.T) {
		result, err := repository.Update(ctx, &models.Game{
			ID: created.ID, Title: "New Title", PosterPath: "co-fresh", Runtime: 200,
		})
		require.NoError(t, err)

		assert.Equal(t, "New Title", result.Title)
		assert.Equal(t, "co-fresh", result.PosterPath)
		assert.Equal(t, uint64(200), result.Runtime)
		assert.Equal(t, models.StateTypeWant, result.State)
	})
}

func Test_GameRepository_FindByIgdbId(t *testing.T) {
	ctx := context.Background()
	client := newRepoTestClient(t)
	repository := NewGameRepository(client)
	userID := newProgressTestUser(t, client, "game.find")

	_, err := repository.Create(ctx, &models.Game{
		UserId: userID, IgdbId: 840001, Title: "Ghost of Tsushima", PosterPath: "co6", State: models.StateTypePlayed,
	})
	require.NoError(t, err)

	t.Run("Success", func(t *testing.T) {
		result, err := repository.FindByIgdbId(ctx, 840001, userID)
		require.NoError(t, err)

		assert.Equal(t, "Ghost of Tsushima", result.Title)
	})

	t.Run("Missing row", func(t *testing.T) {
		result, err := repository.FindByIgdbId(ctx, 849999, userID)
		require.Error(t, err)
		assert.Nil(t, result)
	})

	t.Run("Scoped to the owner", func(t *testing.T) {
		result, err := repository.FindByIgdbId(ctx, 840001, uuid.New())
		require.Error(t, err)
		assert.Nil(t, result)
	})
}

func Test_GameRepository_FindGamesByIgdbIds(t *testing.T) {
	ctx := context.Background()
	client := newRepoTestClient(t)
	repository := NewGameRepository(client)
	userID := newProgressTestUser(t, client, "game.batch")

	_, err := repository.Create(ctx, &models.Game{
		UserId: userID, IgdbId: 850001, Title: "One", PosterPath: "co7", State: models.StateTypeWant,
	})
	require.NoError(t, err)

	_, err = repository.Create(ctx, &models.Game{
		UserId: userID, IgdbId: 850002, Title: "Two", PosterPath: "co8", State: models.StateTypePlayed,
	})
	require.NoError(t, err)

	t.Run("Returns only the ids the user tracks", func(t *testing.T) {
		rows, err := repository.FindGamesByIgdbIds(ctx, []uint64{850001, 850002, 859999}, userID)
		require.NoError(t, err)

		assert.Len(t, rows, 2)
	})

	t.Run("Empty ids", func(t *testing.T) {
		rows, err := repository.FindGamesByIgdbIds(ctx, []uint64{}, userID)
		require.NoError(t, err)

		assert.Empty(t, rows)
	})
}

func Test_GameRepository_DeleteByIgdbId(t *testing.T) {
	ctx := context.Background()
	client := newRepoTestClient(t)
	repository := NewGameRepository(client)
	userID := newProgressTestUser(t, client, "game.delete")

	_, err := repository.Create(ctx, &models.Game{
		UserId: userID, IgdbId: 860001, Title: "Astro Bot", PosterPath: "co9", State: models.StateTypeWant,
	})
	require.NoError(t, err)

	t.Run("Success", func(t *testing.T) {
		require.NoError(t, repository.DeleteByIgdbId(ctx, 860001, userID))

		result, err := repository.FindByIgdbId(ctx, 860001, userID)
		require.Error(t, err)
		assert.Nil(t, result)
	})

	// deleting something that isn't there is not an error, it is already gone
	t.Run("Missing row", func(t *testing.T) {
		require.NoError(t, repository.DeleteByIgdbId(ctx, 869999, userID))
	})
}
