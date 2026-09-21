package repositories

import (
	"context"
	"os"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories/postgres"
	"biinge-api/internal/config"
)

// newRepoTestClient builds a Postgres client against the shared local test database
func newRepoTestClient(t *testing.T) postgres.Postgres {
	t.Helper()

	cfg := &config.Config{DatabaseDSN: os.Getenv("DATABASE_DSN")}
	client, err := postgres.NewPostgresClient(cfg)
	require.NoError(t, err)

	return client
}

func Test_MovieRepository_Create(t *testing.T) {
	ctx := context.Background()
	client := newRepoTestClient(t)
	repository := NewMovieRepository(client)
	userID := newProgressTestUser(t, client, "movie.create")

	t.Run("Success", func(t *testing.T) {
		result, err := repository.Create(ctx, &models.Movie{
			UserId:     userID,
			TmdbId:     700001,
			Title:      "Inception",
			PosterPath: "/inception.jpg",
			Runtime:    148,
			State:      models.StateTypeWatched,
		})
		require.NoError(t, err)

		assert.NotEqual(t, uuid.Nil, result.ID)
		assert.Equal(t, userID, result.UserId)
		assert.Equal(t, uint64(700001), result.TmdbId)
		assert.Equal(t, "Inception", result.Title)
		assert.Equal(t, "/inception.jpg", result.PosterPath)
		assert.Equal(t, uint64(148), result.Runtime)
		assert.Equal(t, models.StateTypeWatched, result.State)
		assert.False(t, result.Pinned)
	})

	t.Run("Unknown user fails foreign key", func(t *testing.T) {
		result, err := repository.Create(ctx, &models.Movie{
			UserId:     uuid.New(),
			TmdbId:     700002,
			Title:      "Orphan",
			PosterPath: "/orphan.jpg",
			Runtime:    100,
			State:      models.StateTypeWant,
		})
		require.Error(t, err)
		assert.Nil(t, result)
	})
}

func Test_MovieRepository_List(t *testing.T) {
	ctx := context.Background()
	client := newRepoTestClient(t)
	repository := NewMovieRepository(client)
	userID := newProgressTestUser(t, client, "movie.list")

	for i, tmdb := range []uint64{710001, 710002, 710003} {
		_, err := repository.Create(ctx, &models.Movie{
			UserId:     userID,
			TmdbId:     tmdb,
			Title:      "Want Movie",
			PosterPath: "/want.jpg",
			Runtime:    uint64(90 + i),
			State:      models.StateTypeWant,
		})
		require.NoError(t, err)
	}

	_, err := repository.Create(ctx, &models.Movie{
		UserId:     userID,
		TmdbId:     710010,
		Title:      "Watched Movie",
		PosterPath: "/watched.jpg",
		Runtime:    120,
		State:      models.StateTypeWatched,
	})
	require.NoError(t, err)

	t.Run("Returns matching state with total across pages", func(t *testing.T) {
		first, total, err := repository.List(ctx, userID, models.StateTypeWant, 2, 0)
		require.NoError(t, err)
		assert.Len(t, first, 2)
		assert.Equal(t, uint64(3), total)

		second, total, err := repository.List(ctx, userID, models.StateTypeWant, 2, 2)
		require.NoError(t, err)
		assert.Len(t, second, 1)
		assert.Equal(t, uint64(3), total)

		for _, m := range first {
			assert.Equal(t, models.StateTypeWant, m.State)
			assert.Equal(t, userID, m.UserId)
		}
	})

	t.Run("Single watched movie", func(t *testing.T) {
		result, total, err := repository.List(ctx, userID, models.StateTypeWatched, 10, 0)
		require.NoError(t, err)
		assert.Len(t, result, 1)
		assert.Equal(t, uint64(1), total)
		assert.Equal(t, uint64(710010), result[0].TmdbId)
	})

	t.Run("Empty state yields no rows and zero total", func(t *testing.T) {
		result, total, err := repository.List(ctx, userID, models.StateTypeNone, 10, 0)
		require.NoError(t, err)
		assert.Empty(t, result)
		assert.Equal(t, uint64(0), total)
	})
}

func Test_MovieRepository_Update(t *testing.T) {
	ctx := context.Background()
	client := newRepoTestClient(t)
	repository := NewMovieRepository(client)
	userID := newProgressTestUser(t, client, "movie.update")

	created, err := repository.Create(ctx, &models.Movie{
		UserId:     userID,
		TmdbId:     720001,
		Title:      "Old Title",
		PosterPath: "/old.jpg",
		Runtime:    100,
		State:      models.StateTypeWant,
	})
	require.NoError(t, err)

	t.Run("Success", func(t *testing.T) {
		result, err := repository.Update(ctx, &models.Movie{
			ID:         created.ID,
			Title:      "New Title",
			PosterPath: "/new.jpg",
			Runtime:    130,
		})
		require.NoError(t, err)

		assert.Equal(t, created.ID, result.ID)
		assert.Equal(t, "New Title", result.Title)
		assert.Equal(t, "/new.jpg", result.PosterPath)
		assert.Equal(t, uint64(130), result.Runtime)
		assert.Equal(t, models.StateTypeWant, result.State)
	})

	t.Run("Unknown id returns error", func(t *testing.T) {
		result, err := repository.Update(ctx, &models.Movie{
			ID:         uuid.New(),
			Title:      "Ghost",
			PosterPath: "/ghost.jpg",
			Runtime:    10,
		})
		require.Error(t, err)
		assert.Nil(t, result)
	})
}

func Test_MovieRepository_UpdateByTmdbId(t *testing.T) {
	ctx := context.Background()
	client := newRepoTestClient(t)
	repository := NewMovieRepository(client)
	userID := newProgressTestUser(t, client, "movie.update.tmdb")

	created, err := repository.Create(ctx, &models.Movie{
		UserId:     userID,
		TmdbId:     730001,
		Title:      "Toggle Movie",
		PosterPath: "/toggle.jpg",
		Runtime:    100,
		State:      models.StateTypeWant,
	})
	require.NoError(t, err)

	t.Run("Success", func(t *testing.T) {
		result, err := repository.UpdateByTmdbId(ctx, &models.Movie{
			TmdbId: created.TmdbId,
			UserId: userID,
			State:  models.StateTypeWatched,
			Pinned: true,
		})
		require.NoError(t, err)

		assert.Equal(t, created.ID, result.ID)
		assert.Equal(t, models.StateTypeWatched, result.State)
		assert.True(t, result.Pinned)
	})

	t.Run("Other user's row on the same title is untouched", func(t *testing.T) {
		otherID := newProgressTestUser(t, client, "movie.update.other")

		other, err := repository.Create(ctx, &models.Movie{
			UserId:     otherID,
			TmdbId:     created.TmdbId,
			Title:      "Toggle Movie",
			PosterPath: "/toggle.jpg",
			Runtime:    100,
			State:      models.StateTypeWant,
		})
		require.NoError(t, err)

		_, err = repository.UpdateByTmdbId(ctx, &models.Movie{
			TmdbId: created.TmdbId,
			UserId: userID,
			State:  models.StateTypeWatched,
			Pinned: false,
		})
		require.NoError(t, err)

		rows, err := repository.FindByFilter(ctx, models.MovieFilter{UserId: otherID, TmdbIds: []uint64{created.TmdbId}})
		require.NoError(t, err)
		require.Len(t, rows, 1)

		assert.Equal(t, other.ID, rows[0].ID)
		assert.Equal(t, models.StateTypeWant, rows[0].State)
		assert.True(t, rows[0].WatchedAt.IsZero())
	})

	t.Run("Unknown tmdb id returns error", func(t *testing.T) {
		result, err := repository.UpdateByTmdbId(ctx, &models.Movie{
			TmdbId: 999999,
			UserId: userID,
			State:  models.StateTypeWatched,
			Pinned: false,
		})
		require.Error(t, err)
		assert.Nil(t, result)
	})
}

func Test_MovieRepository_Delete(t *testing.T) {
	ctx := context.Background()
	client := newRepoTestClient(t)
	repository := NewMovieRepository(client)
	userID := newProgressTestUser(t, client, "movie.delete.tmdb")

	created, err := repository.Create(ctx, &models.Movie{
		UserId:     userID,
		TmdbId:     750001,
		Title:      "Doomed By Tmdb",
		PosterPath: "/doomed.jpg",
		Runtime:    100,
		State:      models.StateTypeWant,
	})
	require.NoError(t, err)

	t.Run("Success removes the row", func(t *testing.T) {
		err := repository.Delete(ctx, created.TmdbId, userID)
		require.NoError(t, err)

		rows, err := repository.FindByFilter(ctx, models.MovieFilter{UserId: userID, TmdbIds: []uint64{created.TmdbId}})
		require.NoError(t, err)
		assert.Empty(t, rows)
	})

	t.Run("Deleting a missing tmdb id is a no-op", func(t *testing.T) {
		err := repository.Delete(ctx, 999998, userID)
		require.NoError(t, err)
	})
}

func Test_MovieRepository_FindByFilter(t *testing.T) {
	ctx := context.Background()
	client := newRepoTestClient(t)
	repository := NewMovieRepository(client)
	userID := newProgressTestUser(t, client, "movie.find.tmdbs")

	tmdbIDs := []uint64{780001, 780002, 780003}
	for _, tmdb := range tmdbIDs {
		_, err := repository.Create(ctx, &models.Movie{
			UserId:     userID,
			TmdbId:     tmdb,
			Title:      "Batch",
			PosterPath: "/batch.jpg",
			Runtime:    100,
			State:      models.StateTypeWant,
		})
		require.NoError(t, err)
	}

	t.Run("Returns the matching subset", func(t *testing.T) {
		result, err := repository.FindByFilter(ctx, models.MovieFilter{UserId: userID, TmdbIds: []uint64{780001, 780003, 999000}})
		require.NoError(t, err)
		assert.Len(t, result, 2)

		found := map[uint64]bool{}
		for _, m := range result {
			found[m.TmdbId] = true
			assert.Equal(t, userID, m.UserId)
		}

		assert.True(t, found[780001])
		assert.True(t, found[780003])
	})

	t.Run("Empty slice returns no rows", func(t *testing.T) {
		result, err := repository.FindByFilter(ctx, models.MovieFilter{UserId: userID, TmdbIds: []uint64{}})
		require.NoError(t, err)
		assert.Empty(t, result)
	})
}

func Test_MovieRepository_QueryErrors(t *testing.T) {
	client := newRepoTestClient(t)
	repository := NewMovieRepository(client)
	userID := newProgressTestUser(t, client, "movie.queryerr")

	canceled, cancel := context.WithCancel(context.Background())
	cancel()

	t.Run("List surfaces query errors", func(t *testing.T) {
		result, total, err := repository.List(canceled, userID, models.StateTypeWant, 10, 0)
		require.Error(t, err)
		assert.Nil(t, result)
		assert.Equal(t, uint64(0), total)
	})

	t.Run("FindByFilter surfaces query errors", func(t *testing.T) {
		result, err := repository.FindByFilter(canceled, models.MovieFilter{UserId: userID, TmdbIds: []uint64{1}})
		require.Error(t, err)
		assert.Nil(t, result)
	})
}
