package worker

import (
	"context"
	"errors"
	"testing"

	"github.com/google/uuid"
	"go.uber.org/mock/gomock"

	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories"
	"biinge-api/internal/app/services"
	"biinge-api/internal/config"
	"biinge-api/internal/config/logger"
	"biinge-api/pkg/tmdb"
)

func newTestWorker(t *testing.T) (*Worker, *repositories.MockSyncRepository, *tmdb.MockClient) {
	t.Helper()

	w, repo, client, _ := newTestWorkerWithStats(t)

	return w, repo, client
}

// newTestWorkerWithStats also hands back the stats cache, for the sync paths that
// have to drop a user's cached statistics
func newTestWorkerWithStats(t *testing.T) (*Worker, *repositories.MockSyncRepository, *tmdb.MockClient, *services.MockStatsCache) {
	t.Helper()

	ctrl := gomock.NewController(t)
	t.Cleanup(ctrl.Finish)

	cfg := &config.Config{AppEnv: config.TestEnv, LogLevel: "info"}
	repo := repositories.NewMockSyncRepository(ctrl)
	client := tmdb.NewMockClient(ctrl)
	stats := services.NewMockStatsCache(ctrl)

	w := &Worker{
		cfg:   cfg,
		repo:  repo,
		tmdb:  client,
		stats: stats,
		log:   logger.NewLogger(cfg).WithComponent("SyncWorker"),
		done:  make(chan struct{}),
	}

	return w, repo, client, stats
}

func Test_Worker_SyncMovie_RefreshesSnapshot(t *testing.T) {
	w, repo, client, stats := newTestWorkerWithStats(t)
	ctx := context.Background()

	movie := models.Movie{ID: uuid.New(), UserId: uuid.New(), TmdbId: 693134, Title: "Dune 2 (working)", PosterPath: "", Runtime: 0}

	// the corrected runtime moves the watched minutes
	stats.EXPECT().Invalidate(ctx, movie.UserId).Times(1)

	client.EXPECT().FetchMovieDetails(ctx, uint64(693134)).Return(&tmdb.MovieDetails{
		Title:       "Dune: Part Two",
		PosterPath:  "/dune2.jpg",
		Runtime:     167,
		ReleaseDate: "2024-02-27",
	}, nil)

	releasedAt, _ := tmdb.ParseDate("2024-02-27")
	repo.EXPECT().SyncMovie(ctx, movie.ID, models.MovieSyncInput{
		Title:      "Dune: Part Two",
		PosterPath: "/dune2.jpg",
		Runtime:    167,
		ReleasedAt: releasedAt,
	}).Return(nil)

	w.syncMovie(ctx, movie)
}

func Test_Worker_SyncMovie_KeepsStoredWhenTmdbEmpty(t *testing.T) {
	w, repo, client, stats := newTestWorkerWithStats(t)
	ctx := context.Background()

	movie := models.Movie{ID: uuid.New(), UserId: uuid.New(), TmdbId: 700, Title: "Stored Title", PosterPath: "/stored.jpg", Runtime: 120}

	client.EXPECT().FetchMovieDetails(ctx, uint64(700)).Return(&tmdb.MovieDetails{}, nil)

	repo.EXPECT().SyncMovie(ctx, movie.ID, models.MovieSyncInput{
		Title:      "Stored Title",
		PosterPath: "/stored.jpg",
		Runtime:    120,
	}).Return(nil)

	// an unchanged runtime leaves the statistics alone, so a batch does not evict
	// every synced user for nothing
	stats.EXPECT().Invalidate(gomock.Any(), gomock.Any()).Times(0)

	w.syncMovie(ctx, movie)
}

func Test_Worker_SyncMovie_KeepsStatsWhenTheWriteFails(t *testing.T) {
	w, repo, client, stats := newTestWorkerWithStats(t)
	ctx := context.Background()

	movie := models.Movie{ID: uuid.New(), UserId: uuid.New(), TmdbId: 701, Runtime: 90}

	client.EXPECT().FetchMovieDetails(ctx, uint64(701)).Return(&tmdb.MovieDetails{Title: "Fresh", Runtime: 111}, nil)
	repo.EXPECT().SyncMovie(ctx, movie.ID, gomock.Any()).Return(errors.New("write failed"))
	stats.EXPECT().Invalidate(gomock.Any(), gomock.Any()).Times(0)

	w.syncMovie(ctx, movie)
}

func Test_Worker_SyncMovie_DefersOnFetchError(t *testing.T) {
	w, repo, client := newTestWorker(t)
	ctx := context.Background()

	movie := models.Movie{ID: uuid.New(), TmdbId: 42}

	client.EXPECT().FetchMovieDetails(ctx, uint64(42)).Return(nil, tmdb.ErrUnexpectedResponse)
	repo.EXPECT().TouchMovieSynced(ctx, movie.ID).Return(nil)
	// SyncMovie must not run when the fetch fails

	w.syncMovie(ctx, movie)
}

func Test_Worker_SyncShow_PassesRawSnapshot(t *testing.T) {
	w, repo, client := newTestWorker(t)
	ctx := context.Background()

	show := models.Series{ID: uuid.New(), UserId: uuid.New(), TmdbId: 1399, Status: "Ended", SeasonsCount: 2}

	client.EXPECT().FetchTvDetails(ctx, uint64(1399)).Return(&tmdb.TvDetails{
		Title:         "Reboot Show",
		PosterPath:    "/reboot.jpg",
		Status:        "Returning Series",
		SeasonsCount:  3,
		EpisodesCount: 30,
		LastAirDate:   "2024-05-01",
	}, nil)

	lastAirAt, _ := tmdb.ParseDate("2024-05-01")
	repo.EXPECT().SyncSeries(ctx, show.UserId, uint64(1399), models.SeriesSyncInput{
		Title:         "Reboot Show",
		PosterPath:    "/reboot.jpg",
		Status:        "Returning Series",
		SeasonsCount:  3,
		EpisodesCount: 30,
		LastAirAt:     lastAirAt,
	}).Return(nil)

	w.syncShow(ctx, show)
}

func Test_Worker_SyncShow_DefersOnFetchError(t *testing.T) {
	w, repo, client := newTestWorker(t)
	ctx := context.Background()

	show := models.Series{ID: uuid.New(), UserId: uuid.New(), TmdbId: 99}

	client.EXPECT().FetchTvDetails(ctx, uint64(99)).Return(nil, errors.New("connection refused"))
	repo.EXPECT().TouchSeriesSynced(ctx, show.ID).Return(nil)
	// SyncSeries must not run when the fetch fails

	w.syncShow(ctx, show)
}
