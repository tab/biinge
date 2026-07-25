package services

import (
	"context"
	"io"
	"os"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/repositories"
	"biinge-api/internal/config"
	"biinge-api/internal/config/logger"
)

// captureLogs builds a logger writing to a pipe and returns everything it emitted.
// The logger has to be built inside the swap because it binds to os.Stdout on construction
func captureLogs(t *testing.T, fn func(log *logger.Logger)) string {
	t.Helper()

	reader, writer, err := os.Pipe()
	require.NoError(t, err)

	original := os.Stdout
	os.Stdout = writer

	fn(logger.NewLogger(&config.Config{AppEnv: "test", AppAddr: "localhost:8080", LogLevel: "debug"}))

	require.NoError(t, writer.Close())

	os.Stdout = original

	out, err := io.ReadAll(reader)
	require.NoError(t, err)

	return string(out)
}

// A details screen looks up every title the user opens, and most are not in their
// library. That miss must not read as a failure in the logs.

func Test_Movies_LookupMissIsNotLoggedAsAnError(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	userId := uuid.New()

	t.Run("A movie outside the library stays quiet", func(t *testing.T) {
		repository := repositories.NewMockMovieRepository(ctrl)
		repository.EXPECT().FindByTmdbId(ctx, uint64(100), userId).Return(nil, pgx.ErrNoRows)

		out := captureLogs(t, func(log *logger.Logger) {
			_, err := NewMovies(repository, newTestStatsCache(), log).FindByTmdbId(ctx, 100, userId)
			require.ErrorIs(t, err, errors.ErrMovieNotFound)
		})

		assert.NotContains(t, out, `"level":"error"`)
	})

	t.Run("A real failure is still logged", func(t *testing.T) {
		repository := repositories.NewMockMovieRepository(ctrl)
		repository.EXPECT().FindByTmdbId(ctx, uint64(100), userId).Return(nil, assert.AnError)

		out := captureLogs(t, func(log *logger.Logger) {
			_, err := NewMovies(repository, newTestStatsCache(), log).FindByTmdbId(ctx, 100, userId)
			require.ErrorIs(t, err, errors.ErrMovieNotFound)
		})

		assert.Contains(t, out, `"level":"error"`)
		assert.Contains(t, out, "Failed to fetch movie by TMDB Id")
	})

	t.Run("The same holds for a lookup by id", func(t *testing.T) {
		id := uuid.New()
		repository := repositories.NewMockMovieRepository(ctrl)
		repository.EXPECT().FindById(ctx, id).Return(nil, pgx.ErrNoRows)

		out := captureLogs(t, func(log *logger.Logger) {
			_, err := NewMovies(repository, newTestStatsCache(), log).FindById(ctx, id)
			require.ErrorIs(t, err, errors.ErrMovieNotFound)
		})

		assert.NotContains(t, out, `"level":"error"`)
	})
}

func Test_Series_LookupMissIsNotLoggedAsAnError(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	userId := uuid.New()

	t.Run("A show outside the library stays quiet", func(t *testing.T) {
		repository := repositories.NewMockSeriesRepository(ctrl)
		repository.EXPECT().FindByTmdbId(ctx, uint64(200), userId).Return(nil, pgx.ErrNoRows)

		out := captureLogs(t, func(log *logger.Logger) {
			_, err := NewSeries(repository, newTestStatsCache(), log).FindByTmdbId(ctx, 200, userId)
			require.ErrorIs(t, err, errors.ErrSeriesNotFound)
		})

		assert.NotContains(t, out, `"level":"error"`)
	})

	t.Run("A real failure is still logged", func(t *testing.T) {
		repository := repositories.NewMockSeriesRepository(ctrl)
		repository.EXPECT().FindByTmdbId(ctx, uint64(200), userId).Return(nil, assert.AnError)

		out := captureLogs(t, func(log *logger.Logger) {
			_, err := NewSeries(repository, newTestStatsCache(), log).FindByTmdbId(ctx, 200, userId)
			require.ErrorIs(t, err, errors.ErrSeriesNotFound)
		})

		assert.Contains(t, out, `"level":"error"`)
		assert.Contains(t, out, "Failed to fetch series by TMDB Id")
	})
}
