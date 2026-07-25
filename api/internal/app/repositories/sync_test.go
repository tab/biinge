package repositories

import (
	"context"
	"os"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories/db"
	"biinge-api/internal/app/repositories/postgres"
)

func skipWithoutDatabase(t *testing.T) {
	t.Helper()

	if os.Getenv("GO_ENV") == "ci" {
		t.Skip("integration test requires a database")
	}
}

// setSyncTimestamps overrides a row's synced_at (and release/air column) for eligibility tests
func setSyncTimestamps(t *testing.T, client postgres.Postgres, table, dateColumn string, id uuid.UUID, synced, date *time.Time) {
	t.Helper()

	_, err := client.Db().Exec(
		context.Background(),
		"UPDATE "+table+" SET synced_at = $1, "+dateColumn+" = $2 WHERE id = $3",
		synced, date, id,
	)
	require.NoError(t, err)
}

func ptrTime(t time.Time) *time.Time { return &t }

func Test_SyncRepository_SyncSeries_Revival(t *testing.T) {
	skipWithoutDatabase(t)

	ctx := context.Background()
	client := newRepoTestClient(t)
	userID := newProgressTestUser(t, client, "sync.revival")

	progressRepo := NewSeriesProgressRepository(client)
	syncRepo := NewSyncRepository(client)

	const tmdbID uint64 = 900001

	// a two-season show, every season watched, marked finished -> derives watched
	_, err := progressRepo.MarkShowWatched(ctx, userID, models.ShowInput{
		Series: models.SeriesInput{
			TmdbId:        tmdbID,
			Title:         "Revival",
			PosterPath:    "/old.jpg",
			SeasonsCount:  2,
			EpisodesCount: 2,
			Status:        "Ended",
		},
		Seasons: []models.SeasonInput{
			{TmdbId: 1, Title: "S1", Number: 1, EpisodesCount: 1, Episodes: []models.EpisodeInput{{TmdbId: 11, Title: "E1"}}},
			{TmdbId: 2, Title: "S2", Number: 2, EpisodesCount: 1, Episodes: []models.EpisodeInput{{TmdbId: 21, Title: "E1"}}},
		},
	})
	require.NoError(t, err)

	before, err := client.Queries().FindSeriesByTmdbId(ctx, db.FindSeriesByTmdbIdParams{TmdbID: tmdbID, UserID: userID})
	require.NoError(t, err)
	require.Equal(t, db.StateTypesWatched, before.State)

	// a third season is announced: status flips to airing and the season total grows
	lastAir := time.Date(2026, 6, 1, 0, 0, 0, 0, time.UTC)
	err = syncRepo.SyncSeries(ctx, userID, tmdbID, models.SeriesSyncInput{
		Title:         "Revival",
		PosterPath:    "/new.jpg",
		Status:        models.TvInProductionStatus,
		SeasonsCount:  3,
		EpisodesCount: 30,
		LastAirAt:     lastAir,
	})
	require.NoError(t, err)

	after, err := client.Queries().FindSeriesByTmdbId(ctx, db.FindSeriesByTmdbIdParams{TmdbID: tmdbID, UserID: userID})
	require.NoError(t, err)

	assert.Equal(t, db.StateTypesWatching, after.State, "a revived show should leave watched")
	assert.Equal(t, models.TvInProductionStatus, after.Status)
	assert.Equal(t, uint64(3), after.SeasonsCount)
	assert.Equal(t, "/new.jpg", after.PosterPath)
	assert.True(t, after.SyncedAt.Valid, "synced_at should be stamped")
	assert.True(t, after.LastAirAt.Valid, "last_air_at should be stored")
}

func Test_SyncRepository_SyncSeries_UnchangedKeepsState(t *testing.T) {
	skipWithoutDatabase(t)

	ctx := context.Background()
	client := newRepoTestClient(t)
	userID := newProgressTestUser(t, client, "sync.nochange")

	progressRepo := NewSeriesProgressRepository(client)
	syncRepo := NewSyncRepository(client)

	const tmdbID uint64 = 900002

	_, err := progressRepo.MarkShowWatched(ctx, userID, models.ShowInput{
		Series: models.SeriesInput{TmdbId: tmdbID, Title: "Done", PosterPath: "/p.jpg", SeasonsCount: 1, EpisodesCount: 1, Status: "Ended"},
		Seasons: []models.SeasonInput{
			{TmdbId: 1, Title: "S1", Number: 1, EpisodesCount: 1, Episodes: []models.EpisodeInput{{TmdbId: 11, Title: "E1"}}},
		},
	})
	require.NoError(t, err)

	// same status and season total: state must stay watched, only synced_at advances
	err = syncRepo.SyncSeries(ctx, userID, tmdbID, models.SeriesSyncInput{
		Title:        "Done",
		PosterPath:   "/p.jpg",
		Status:       "Ended",
		SeasonsCount: 1,
	})
	require.NoError(t, err)

	after, err := client.Queries().FindSeriesByTmdbId(ctx, db.FindSeriesByTmdbIdParams{TmdbID: tmdbID, UserID: userID})
	require.NoError(t, err)

	assert.Equal(t, db.StateTypesWatched, after.State)
	assert.True(t, after.SyncedAt.Valid)
}

func Test_SyncRepository_FindSeriesToSync_Eligibility(t *testing.T) {
	skipWithoutDatabase(t)

	ctx := context.Background()
	client := newRepoTestClient(t)
	userID := newProgressTestUser(t, client, "sync.find.tv")
	repo := NewSyncRepository(client)

	now := time.Now()
	old := now.AddDate(-6, 0, 0)    // last aired 6 years ago
	recent := now.AddDate(0, 0, -1) // synced yesterday

	seed := func(tmdbID uint64, status string, synced, lastAir *time.Time) uuid.UUID {
		row, err := client.Queries().CreateSeries(ctx, db.CreateSeriesParams{
			UserID: userID, TmdbID: tmdbID, Title: "S", PosterPath: "/p.jpg",
			SeasonsCount: 1, EpisodesCount: 1, Status: status, State: db.StateTypesWatched,
		})
		require.NoError(t, err)
		setSyncTimestamps(t, client, "series", "last_air_at", row.ID, synced, lastAir)

		return row.ID
	}

	dueNeverSynced := seed(910001, "Ended", nil, nil)                         // never synced -> due
	frozenOldEnded := seed(910002, "Ended", nil, ptrTime(old))                // ended long ago -> skip
	airingOld := seed(910003, models.TvInProductionStatus, nil, ptrTime(old)) // still airing -> due despite age
	freshlySynced := seed(910004, "Ended", ptrTime(recent), nil)              // synced yesterday -> not due

	staleBefore := now.Add(-72 * time.Hour)
	airCutoff := now.AddDate(-4, 0, 0)

	results, err := repo.FindSeriesToSync(ctx, staleBefore, airCutoff, []string{models.TvInProductionStatus, "In Production", "Planned", "Pilot"}, 100)
	require.NoError(t, err)

	got := make(map[uuid.UUID]bool, len(results))
	for _, s := range results {
		got[s.ID] = true
	}

	assert.True(t, got[dueNeverSynced], "a never-synced show is due")
	assert.True(t, got[airingOld], "an airing show is due regardless of age")
	assert.False(t, got[frozenOldEnded], "a show ended long ago is frozen")
	assert.False(t, got[freshlySynced], "a freshly synced show is not due")
}

func Test_SyncRepository_FindMoviesToSync_Eligibility(t *testing.T) {
	skipWithoutDatabase(t)

	ctx := context.Background()
	client := newRepoTestClient(t)
	userID := newProgressTestUser(t, client, "sync.find.mv")
	movies := NewMovieRepository(client)
	repo := NewSyncRepository(client)

	now := time.Now()
	longAgo := now.AddDate(-2, 0, 0)
	yesterday := now.AddDate(0, 0, -1)

	seed := func(tmdbID uint64, synced, released *time.Time) uuid.UUID {
		created, err := movies.Create(ctx, &models.Movie{UserId: userID, TmdbId: tmdbID, Title: "M", PosterPath: "/p.jpg", Runtime: 100, State: models.StateTypeWant})
		require.NoError(t, err)
		setSyncTimestamps(t, client, "movies", "released_at", created.ID, synced, released)

		return created.ID
	}

	releasedLongAgo := seed(920001, nil, ptrTime(longAgo))          // settled -> skip
	releasedRecently := seed(920002, nil, ptrTime(yesterday))       // recent -> due
	unreleased := seed(920003, nil, nil)                            // no date yet -> due
	freshlySynced := seed(920004, ptrTime(now), ptrTime(yesterday)) // synced now -> not due

	staleBefore := now.Add(-time.Hour)
	releaseCutoff := now.AddDate(0, 0, -180)

	results, err := repo.FindMoviesToSync(ctx, staleBefore, releaseCutoff, 100)
	require.NoError(t, err)

	got := make(map[uuid.UUID]bool, len(results))
	for _, m := range results {
		got[m.ID] = true
	}

	assert.True(t, got[releasedRecently], "a recently released movie is due")
	assert.True(t, got[unreleased], "an unreleased movie is due")
	assert.False(t, got[releasedLongAgo], "a long-settled movie is frozen")
	assert.False(t, got[freshlySynced], "a freshly synced movie is not due")
}

func Test_SyncRepository_SyncMovie_WritesSnapshot(t *testing.T) {
	skipWithoutDatabase(t)

	ctx := context.Background()
	client := newRepoTestClient(t)
	userID := newProgressTestUser(t, client, "sync.movie")
	movies := NewMovieRepository(client)
	repo := NewSyncRepository(client)

	created, err := movies.Create(ctx, &models.Movie{UserId: userID, TmdbId: 930001, Title: "Old", PosterPath: "/old.jpg", Runtime: 0, State: models.StateTypeWant})
	require.NoError(t, err)

	released := time.Date(2025, 3, 1, 0, 0, 0, 0, time.UTC)
	err = repo.SyncMovie(ctx, created.ID, models.MovieSyncInput{Title: "New", PosterPath: "/new.jpg", Runtime: 120, ReleasedAt: released})
	require.NoError(t, err)

	row, err := client.Queries().FindMovieById(ctx, created.ID)
	require.NoError(t, err)

	assert.Equal(t, "New", row.Title)
	assert.Equal(t, "/new.jpg", row.PosterPath)
	assert.Equal(t, uint64(120), row.Runtime)
	assert.Equal(t, models.StateTypeWant, models.StateType(row.State), "sync must not touch user-driven state")
}
