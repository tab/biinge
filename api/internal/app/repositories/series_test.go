package repositories

import (
	"context"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"biinge-api/internal/app/models"
)

func Test_SeriesRepository_Create(t *testing.T) {
	ctx := context.Background()
	client := newRepoTestClient(t)
	repository := NewSeriesRepository(client)
	userID := newProgressTestUser(t, client, "series.create")

	t.Run("Success", func(t *testing.T) {
		result, err := repository.Create(ctx, &models.Series{
			UserId:        userID,
			TmdbId:        800001,
			Title:         "Breaking Bad",
			PosterPath:    "/bb.jpg",
			SeasonsCount:  5,
			EpisodesCount: 62,
			Status:        "Ended",
			State:         models.StateTypeWatching,
		})
		require.NoError(t, err)

		assert.NotEqual(t, uuid.Nil, result.ID)
		assert.Equal(t, userID, result.UserId)
		assert.Equal(t, uint64(800001), result.TmdbId)
		assert.Equal(t, "Breaking Bad", result.Title)
		assert.Equal(t, "/bb.jpg", result.PosterPath)
		assert.Equal(t, uint64(5), result.SeasonsCount)
		assert.Equal(t, uint64(62), result.EpisodesCount)
		assert.Equal(t, "Ended", result.Status)
		assert.Equal(t, models.StateTypeWatching, result.State)
		assert.False(t, result.Pinned)
	})

	t.Run("Unknown user fails foreign key", func(t *testing.T) {
		result, err := repository.Create(ctx, &models.Series{
			UserId:        uuid.New(),
			TmdbId:        800002,
			Title:         "Orphan",
			PosterPath:    "/orphan.jpg",
			SeasonsCount:  1,
			EpisodesCount: 1,
			Status:        "Ended",
			State:         models.StateTypeWant,
		})
		require.Error(t, err)
		assert.Nil(t, result)
	})
}

func Test_SeriesRepository_List(t *testing.T) {
	ctx := context.Background()
	client := newRepoTestClient(t)
	repository := NewSeriesRepository(client)
	userID := newProgressTestUser(t, client, "series.list")

	for _, tmdb := range []uint64{810001, 810002, 810003} {
		_, err := repository.Create(ctx, &models.Series{
			UserId:        userID,
			TmdbId:        tmdb,
			Title:         "Watching Show",
			PosterPath:    "/watching.jpg",
			SeasonsCount:  1,
			EpisodesCount: 10,
			Status:        "Returning Series",
			State:         models.StateTypeWatching,
		})
		require.NoError(t, err)
	}

	_, err := repository.Create(ctx, &models.Series{
		UserId:        userID,
		TmdbId:        810010,
		Title:         "Wanted Show",
		PosterPath:    "/wanted.jpg",
		SeasonsCount:  2,
		EpisodesCount: 20,
		Status:        "Ended",
		State:         models.StateTypeWant,
	})
	require.NoError(t, err)

	t.Run("Returns matching state with total across pages", func(t *testing.T) {
		first, total, err := repository.List(ctx, userID, models.StateTypeWatching, 2, 0)
		require.NoError(t, err)
		assert.Len(t, first, 2)
		assert.Equal(t, uint64(3), total)

		second, total, err := repository.List(ctx, userID, models.StateTypeWatching, 2, 2)
		require.NoError(t, err)
		assert.Len(t, second, 1)
		assert.Equal(t, uint64(3), total)

		for _, s := range first {
			assert.Equal(t, models.StateTypeWatching, s.State)
			assert.Equal(t, userID, s.UserId)
			assert.Equal(t, uint64(10), s.EpisodesCount)
		}
	})

	t.Run("Single wanted show", func(t *testing.T) {
		result, total, err := repository.List(ctx, userID, models.StateTypeWant, 10, 0)
		require.NoError(t, err)
		assert.Len(t, result, 1)
		assert.Equal(t, uint64(1), total)
		assert.Equal(t, uint64(810010), result[0].TmdbId)
	})

	t.Run("Empty state yields no rows and zero total", func(t *testing.T) {
		result, total, err := repository.List(ctx, userID, models.StateTypeNone, 10, 0)
		require.NoError(t, err)
		assert.Empty(t, result)
		assert.Equal(t, uint64(0), total)
	})
}

func Test_SeriesRepository_Update(t *testing.T) {
	ctx := context.Background()
	client := newRepoTestClient(t)
	repository := NewSeriesRepository(client)
	userID := newProgressTestUser(t, client, "series.update")

	created, err := repository.Create(ctx, &models.Series{
		UserId:        userID,
		TmdbId:        820001,
		Title:         "Old Title",
		PosterPath:    "/old.jpg",
		SeasonsCount:  1,
		EpisodesCount: 8,
		Status:        "Returning Series",
		State:         models.StateTypeWatching,
	})
	require.NoError(t, err)

	t.Run("Success", func(t *testing.T) {
		result, err := repository.Update(ctx, &models.Series{
			ID:            created.ID,
			Title:         "New Title",
			PosterPath:    "/new.jpg",
			SeasonsCount:  2,
			EpisodesCount: 16,
			Status:        "Ended",
		})
		require.NoError(t, err)

		assert.Equal(t, created.ID, result.ID)
		assert.Equal(t, "New Title", result.Title)
		assert.Equal(t, "/new.jpg", result.PosterPath)
		assert.Equal(t, uint64(2), result.SeasonsCount)
		assert.Equal(t, uint64(16), result.EpisodesCount)
		assert.Equal(t, "Ended", result.Status)
		assert.Equal(t, models.StateTypeWatching, result.State)
	})

	t.Run("Unknown id returns error", func(t *testing.T) {
		result, err := repository.Update(ctx, &models.Series{
			ID:            uuid.New(),
			Title:         "Ghost",
			PosterPath:    "/ghost.jpg",
			SeasonsCount:  1,
			EpisodesCount: 1,
			Status:        "Ended",
		})
		require.Error(t, err)
		assert.Nil(t, result)
	})
}

func Test_SeriesRepository_UpdateByTmdbId(t *testing.T) {
	ctx := context.Background()
	client := newRepoTestClient(t)
	repository := NewSeriesRepository(client)
	userID := newProgressTestUser(t, client, "series.update.tmdb")

	created, err := repository.Create(ctx, &models.Series{
		UserId:        userID,
		TmdbId:        830001,
		Title:         "Toggle Show",
		PosterPath:    "/toggle.jpg",
		SeasonsCount:  1,
		EpisodesCount: 8,
		Status:        "Ended",
		State:         models.StateTypeWant,
	})
	require.NoError(t, err)

	t.Run("Success", func(t *testing.T) {
		result, err := repository.UpdateByTmdbId(ctx, &models.Series{
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

	t.Run("Unknown tmdb id returns error", func(t *testing.T) {
		result, err := repository.UpdateByTmdbId(ctx, &models.Series{
			TmdbId: 999996,
			UserId: userID,
			State:  models.StateTypeWatched,
			Pinned: false,
		})
		require.Error(t, err)
		assert.Nil(t, result)
	})
}

func Test_SeriesRepository_Delete(t *testing.T) {
	ctx := context.Background()
	client := newRepoTestClient(t)
	repository := NewSeriesRepository(client)
	userID := newProgressTestUser(t, client, "series.delete.tmdb")

	created, err := repository.Create(ctx, &models.Series{
		UserId:        userID,
		TmdbId:        850001,
		Title:         "Doomed By Tmdb",
		PosterPath:    "/doomed.jpg",
		SeasonsCount:  1,
		EpisodesCount: 1,
		Status:        "Ended",
		State:         models.StateTypeWant,
	})
	require.NoError(t, err)

	t.Run("Success removes the row", func(t *testing.T) {
		err := repository.Delete(ctx, created.TmdbId, userID)
		require.NoError(t, err)

		rows, err := repository.FindByFilter(ctx, models.SeriesFilter{UserId: userID, TmdbIds: []uint64{created.TmdbId}})
		require.NoError(t, err)
		assert.Empty(t, rows)
	})

	t.Run("Deleting a missing tmdb id is a no-op", func(t *testing.T) {
		err := repository.Delete(ctx, 999995, userID)
		require.NoError(t, err)
	})
}

func Test_SeriesRepository_FindByFilter(t *testing.T) {
	ctx := context.Background()
	client := newRepoTestClient(t)
	repository := NewSeriesRepository(client)
	userID := newProgressTestUser(t, client, "series.find.tmdbs")

	tmdbIDs := []uint64{880001, 880002, 880003}
	for _, tmdb := range tmdbIDs {
		_, err := repository.Create(ctx, &models.Series{
			UserId:        userID,
			TmdbId:        tmdb,
			Title:         "Batch",
			PosterPath:    "/batch.jpg",
			SeasonsCount:  1,
			EpisodesCount: 5,
			Status:        "Ended",
			State:         models.StateTypeWant,
		})
		require.NoError(t, err)
	}

	t.Run("Returns the matching subset", func(t *testing.T) {
		result, err := repository.FindByFilter(ctx, models.SeriesFilter{UserId: userID, TmdbIds: []uint64{880001, 880003, 999000}})
		require.NoError(t, err)
		assert.Len(t, result, 2)

		found := map[uint64]bool{}
		for _, s := range result {
			found[s.TmdbId] = true
			assert.Equal(t, userID, s.UserId)
		}

		assert.True(t, found[880001])
		assert.True(t, found[880003])
	})

	t.Run("Empty slice returns no rows", func(t *testing.T) {
		result, err := repository.FindByFilter(ctx, models.SeriesFilter{UserId: userID, TmdbIds: []uint64{}})
		require.NoError(t, err)
		assert.Empty(t, result)
	})
}

func Test_SeriesRepository_QueryErrors(t *testing.T) {
	client := newRepoTestClient(t)
	repository := NewSeriesRepository(client)
	userID := newProgressTestUser(t, client, "series.queryerr")

	canceled, cancel := context.WithCancel(context.Background())
	cancel()

	t.Run("List surfaces query errors", func(t *testing.T) {
		result, total, err := repository.List(canceled, userID, models.StateTypeWant, 10, 0)
		require.Error(t, err)
		assert.Nil(t, result)
		assert.Equal(t, uint64(0), total)
	})

	t.Run("FindByFilter surfaces query errors", func(t *testing.T) {
		result, err := repository.FindByFilter(canceled, models.SeriesFilter{UserId: userID, TmdbIds: []uint64{1}})
		require.Error(t, err)
		assert.Nil(t, result)
	})
}
