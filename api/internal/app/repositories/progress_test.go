package repositories

import (
	"context"
	"os"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories/db"
	"biinge-api/internal/app/repositories/postgres"
	"biinge-api/internal/config"
)

func newProgressTestUser(t *testing.T, client postgres.Postgres, login string) uuid.UUID {
	t.Helper()

	user, err := client.Queries().CreateUser(context.Background(), db.CreateUserParams{
		Login:             login,
		Email:             login + "@local",
		EncryptedPassword: "SECRET",
		FirstName:         "TV",
		LastName:          "Tester",
		Appearance:        models.DefaultAppearance,
	})
	require.NoError(t, err)

	return user.ID
}

func seriesInput(tmdbID, episodesCount uint64, status string) models.SeriesInput {
	return models.SeriesInput{
		TmdbId:        tmdbID,
		Title:         "Test Show",
		PosterPath:    "/poster.jpg",
		SeasonsCount:  1,
		EpisodesCount: episodesCount,
		Status:        status,
	}
}

func seasonInput(tmdbID, episodesCount uint64, episodes ...models.EpisodeInput) models.SeasonInput {
	return models.SeasonInput{
		TmdbId:        tmdbID,
		Title:         "Season 1",
		Number:        1,
		EpisodesCount: episodesCount,
		Episodes:      episodes,
	}
}

func episodeInput(tmdbID uint64) models.EpisodeInput {
	return models.EpisodeInput{TmdbId: tmdbID, Title: "Episode", Runtime: 42}
}

func Test_SeriesProgressRepository_Cascade(t *testing.T) {
	if os.Getenv("GO_ENV") == "ci" {
		t.Skip("integration test requires a database")
	}

	ctx := context.Background()
	cfg := &config.Config{DatabaseDSN: os.Getenv("DATABASE_DSN")}

	client, err := postgres.NewPostgresClient(cfg)
	require.NoError(t, err)

	repository := NewSeriesProgressRepository(client)
	userID := newProgressTestUser(t, client, "tv.tester")

	t.Run("mark single episode marks show watching, season not yet watched", func(t *testing.T) {
		const seriesID uint64 = 100
		defer func() { _, _ = repository.UnmarkShowWatched(ctx, userID, seriesID) }()

		progress, err := repository.MarkEpisodeWatched(
			ctx, userID,
			seriesInput(seriesID, 3, "Ended"),
			seasonInput(3624, 3),
			episodeInput(63056),
		)
		require.NoError(t, err)

		assert.Equal(t, models.StateTypeWatching, progress.State)
		assert.Equal(t, []uint64{63056}, progress.WatchedEpisodes)
		assert.Empty(t, progress.WatchedSeasons)
	})

	t.Run("marking every episode of a finished show marks it watched", func(t *testing.T) {
		const seriesID uint64 = 101
		defer func() { _, _ = repository.UnmarkShowWatched(ctx, userID, seriesID) }()

		for _, ep := range []uint64{1, 2, 3} {
			_, err := repository.MarkEpisodeWatched(
				ctx, userID,
				seriesInput(seriesID, 3, "Ended"),
				seasonInput(200, 3),
				episodeInput(ep),
			)
			require.NoError(t, err)
		}

		progress, err := repository.Progress(ctx, userID, seriesID)
		require.NoError(t, err)

		assert.Equal(t, models.StateTypeWatched, progress.State)
		assert.ElementsMatch(t, []uint64{1, 2, 3}, progress.WatchedEpisodes)
		assert.Equal(t, []uint64{200}, progress.WatchedSeasons)
	})

	t.Run("in-production show with all episodes watched stays watching", func(t *testing.T) {
		const seriesID uint64 = 102
		defer func() { _, _ = repository.UnmarkShowWatched(ctx, userID, seriesID) }()

		progress, err := repository.MarkSeasonWatched(
			ctx, userID,
			seriesInput(seriesID, 2, models.TvInProductionStatus),
			seasonInput(300, 2, episodeInput(10), episodeInput(11)),
		)
		require.NoError(t, err)

		assert.Equal(t, models.StateTypeWatching, progress.State)
		assert.Equal(t, []uint64{300}, progress.WatchedSeasons)
		assert.ElementsMatch(t, []uint64{10, 11}, progress.WatchedEpisodes)
	})

	t.Run("mark whole show watched cascades to seasons and episodes", func(t *testing.T) {
		const seriesID uint64 = 103
		defer func() { _, _ = repository.UnmarkShowWatched(ctx, userID, seriesID) }()

		progress, err := repository.MarkShowWatched(ctx, userID, models.ShowInput{
			Series: seriesInput(seriesID, 3, "Ended"),
			Seasons: []models.SeasonInput{
				seasonInput(400, 2, episodeInput(20), episodeInput(21)),
				seasonInput(401, 1, episodeInput(30)),
			},
		})
		require.NoError(t, err)

		assert.Equal(t, models.StateTypeWatched, progress.State)
		assert.ElementsMatch(t, []uint64{400, 401}, progress.WatchedSeasons)
		assert.ElementsMatch(t, []uint64{20, 21, 30}, progress.WatchedEpisodes)
	})

	t.Run("unmarking the last episode untracks the show", func(t *testing.T) {
		const seriesID uint64 = 104

		_, err := repository.MarkEpisodeWatched(
			ctx, userID,
			seriesInput(seriesID, 2, "Ended"),
			seasonInput(500, 2),
			episodeInput(40),
		)
		require.NoError(t, err)

		progress, err := repository.UnmarkEpisodeWatched(ctx, userID, seriesID, 500, 40)
		require.NoError(t, err)

		assert.Equal(t, models.StateTypeNone, progress.State)
		assert.Empty(t, progress.WatchedEpisodes)
		assert.Empty(t, progress.WatchedSeasons)
	})

	t.Run("unmarking one episode downgrades a watched show to watching", func(t *testing.T) {
		const seriesID uint64 = 105
		defer func() { _, _ = repository.UnmarkShowWatched(ctx, userID, seriesID) }()

		_, err := repository.MarkShowWatched(ctx, userID, models.ShowInput{
			Series:  seriesInput(seriesID, 2, "Ended"),
			Seasons: []models.SeasonInput{seasonInput(600, 2, episodeInput(50), episodeInput(51))},
		})
		require.NoError(t, err)

		progress, err := repository.UnmarkEpisodeWatched(ctx, userID, seriesID, 600, 51)
		require.NoError(t, err)

		assert.Equal(t, models.StateTypeWatching, progress.State)
		assert.Equal(t, []uint64{50}, progress.WatchedEpisodes)
		assert.Empty(t, progress.WatchedSeasons, "season is no longer fully watched")
	})
}
