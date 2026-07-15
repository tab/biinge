package repositories

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories/db"
	"biinge-api/internal/app/repositories/postgres"
)

// seedStatsMovie inserts a movie in the given state with the given runtime
func seedStatsMovie(t *testing.T, client postgres.Postgres, userID uuid.UUID, tmdbID, runtime uint64, state string) {
	t.Helper()

	_, err := client.Queries().CreateMovie(context.Background(), db.CreateMovieParams{
		UserID:     userID,
		TmdbID:     tmdbID,
		Title:      "Stats Movie",
		PosterPath: "/stats.jpg",
		Runtime:    runtime,
		State:      db.StateTypes(state),
	})
	require.NoError(t, err)
}

// seedStatsSeries inserts a series in the given state and returns its id
func seedStatsSeries(t *testing.T, client postgres.Postgres, userID uuid.UUID, tmdbID uint64, state string) uuid.UUID {
	t.Helper()

	result, err := client.Queries().CreateSeries(context.Background(), db.CreateSeriesParams{
		UserID:        userID,
		TmdbID:        tmdbID,
		Title:         "Stats Show",
		PosterPath:    "/stats.jpg",
		SeasonsCount:  1,
		EpisodesCount: 3,
		Status:        "Ended",
		State:         db.StateTypes(state),
	})
	require.NoError(t, err)

	return result.ID
}

// seedStatsEpisodes attaches a season with episodes of the given runtimes to a series
func seedStatsEpisodes(t *testing.T, client postgres.Postgres, seriesID uuid.UUID, seasonTmdbID uint64, runtimes ...uint64) {
	t.Helper()

	ctx := context.Background()

	season, err := client.Queries().UpsertSeason(ctx, db.UpsertSeasonParams{
		SeriesID:      seriesID,
		TmdbID:        seasonTmdbID,
		Title:         "Season 1",
		Number:        1,
		EpisodesCount: uint64(len(runtimes)),
		State:         db.StateTypesWatched,
	})
	require.NoError(t, err)

	for i, runtime := range runtimes {
		_, err := client.Queries().UpsertEpisode(ctx, db.UpsertEpisodeParams{
			SeasonID:   season.ID,
			TmdbID:     seasonTmdbID*100 + uint64(i),
			Title:      "Episode",
			PosterPath: "/episode.jpg",
			Runtime:    runtime,
			State:      db.StateTypesWatched,
			AirAt:      timestampFromTime(time.Time{}),
		})
		require.NoError(t, err)
	}
}

func Test_StatsRepository_Get(t *testing.T) {
	ctx := context.Background()
	client := newRepoTestClient(t)
	repository := NewStatsRepository(client)
	userID := newProgressTestUser(t, client, "stats.get")

	seedStatsMovie(t, client, userID, 900001, 80, models.StateTypeWant)
	seedStatsMovie(t, client, userID, 900002, 95, models.StateTypeWant)
	seedStatsMovie(t, client, userID, 900003, 100, models.StateTypeWatched)
	seedStatsMovie(t, client, userID, 900004, 120, models.StateTypeWatched)
	seedStatsMovie(t, client, userID, 900005, 90, models.StateTypeWatched)

	seedStatsSeries(t, client, userID, 900101, models.StateTypeWant)
	watchingSeries := seedStatsSeries(t, client, userID, 900102, models.StateTypeWatching)
	seedStatsSeries(t, client, userID, 900103, models.StateTypeWatched)

	seedStatsEpisodes(t, client, watchingSeries, 900201, 42, 42, 30)

	t.Run("Aggregates counts and minutes across domains", func(t *testing.T) {
		result, err := repository.Get(ctx, userID)
		require.NoError(t, err)

		assert.Equal(t, uint64(2), result.MoviesWant)
		assert.Equal(t, uint64(3), result.MoviesWatched)
		assert.Equal(t, uint64(310), result.MoviesMinutes)

		assert.Equal(t, uint64(1), result.SeriesWant)
		assert.Equal(t, uint64(1), result.SeriesWatching)
		assert.Equal(t, uint64(1), result.SeriesWatched)

		assert.Equal(t, uint64(3), result.EpisodesWatched)
		assert.Equal(t, uint64(114), result.EpisodesMinutes)
	})
}

func Test_StatsRepository_Get_Empty(t *testing.T) {
	ctx := context.Background()
	client := newRepoTestClient(t)
	repository := NewStatsRepository(client)
	userID := newProgressTestUser(t, client, "stats.empty")

	result, err := repository.Get(ctx, userID)
	require.NoError(t, err)

	assert.Equal(t, uint64(0), result.MoviesWant)
	assert.Equal(t, uint64(0), result.MoviesWatched)
	assert.Equal(t, uint64(0), result.MoviesMinutes)
	assert.Equal(t, uint64(0), result.SeriesWant)
	assert.Equal(t, uint64(0), result.SeriesWatching)
	assert.Equal(t, uint64(0), result.SeriesWatched)
	assert.Equal(t, uint64(0), result.EpisodesWatched)
	assert.Equal(t, uint64(0), result.EpisodesMinutes)
}

func Test_StatsRepository_Get_QueryError(t *testing.T) {
	client := newRepoTestClient(t)
	repository := NewStatsRepository(client)
	userID := newProgressTestUser(t, client, "stats.queryerr")

	canceled, cancel := context.WithCancel(context.Background())
	cancel()

	result, err := repository.Get(canceled, userID)
	require.Error(t, err)
	assert.Nil(t, result)
}
