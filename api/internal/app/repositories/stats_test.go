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
func seedStatsMovie(t *testing.T, client postgres.Postgres, userID uuid.UUID, tmdbID, runtime uint64, state models.StateType) {
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

// seedStatsGame inserts a game in the given state
func seedStatsGame(t *testing.T, client postgres.Postgres, userID uuid.UUID, igdbID uint64, runtime uint64, state models.StateType) {
	t.Helper()

	_, err := client.Queries().CreateGame(context.Background(), db.CreateGameParams{
		UserID:     userID,
		IgdbID:     igdbID,
		Title:      "Stats Game",
		PosterPath: "co1wyy",
		Runtime:    runtime,
		State:      db.StateTypes(state),
	})
	require.NoError(t, err)
}

// seedStatsSeries inserts a series in the given state and returns its id
func seedStatsSeries(t *testing.T, client postgres.Postgres, userID uuid.UUID, tmdbID uint64, state models.StateType) uuid.UUID {
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

// backdateStatsMovie re-dates a watched movie the given interval before the start of this year
func backdateStatsMovie(t *testing.T, client postgres.Postgres, userID uuid.UUID, tmdbID uint64, back string) {
	t.Helper()

	_, err := client.Db().Exec(
		context.Background(),
		`UPDATE movies
		 SET watched_at = date_trunc('year', NOW()) - $1::interval
		 WHERE user_id = $2 AND tmdb_id = $3`,
		back, userID, tmdbID,
	)
	require.NoError(t, err)
}

// backdateStatsEpisode re-dates a watched episode the given interval before the start of this year
func backdateStatsEpisode(t *testing.T, client postgres.Postgres, tmdbID uint64, back string) {
	t.Helper()

	_, err := client.Db().Exec(
		context.Background(),
		`UPDATE episodes
		 SET watched_at = date_trunc('year', NOW()) - $1::interval
		 WHERE tmdb_id = $2`,
		back, tmdbID,
	)
	require.NoError(t, err)
}

// anchorStatsMovie re-dates a watched movie to the exact start of the given calendar unit
func anchorStatsMovie(t *testing.T, client postgres.Postgres, userID uuid.UUID, tmdbID uint64, unit string) {
	t.Helper()

	_, err := client.Db().Exec(
		context.Background(),
		`UPDATE movies
		 SET watched_at = date_trunc($1::text, NOW())
		 WHERE user_id = $2 AND tmdb_id = $3`,
		unit, userID, tmdbID,
	)
	require.NoError(t, err)
}

// statsAnchor returns a date_trunc boundary as postgres computes it, so expectations
// use the same calendar the queries do rather than the test process' clock
func statsAnchor(t *testing.T, client postgres.Postgres, unit string) time.Time {
	t.Helper()

	var anchor time.Time

	err := client.Db().QueryRow(context.Background(), `SELECT date_trunc($1::text, NOW())::date`, unit).Scan(&anchor)
	require.NoError(t, err)

	return anchor
}

// bucketDates renders activity bucket starts for comparison against calendar anchors
func bucketDates(activity []models.WatchBucket) []string {
	dates := make([]string, 0, len(activity))
	for _, bucket := range activity {
		dates = append(dates, bucket.Date.Format(time.DateOnly))
	}

	return dates
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

	seedStatsGame(t, client, userID, 900301, 1200, models.StateTypeWant)
	seedStatsGame(t, client, userID, 900302, 3000, models.StateTypePlaying)
	seedStatsGame(t, client, userID, 900303, 1800, models.StateTypePlayed)
	seedStatsGame(t, client, userID, 900304, 600, models.StateTypePlayed)

	t.Run("Aggregates counts and minutes across domains", func(t *testing.T) {
		result, err := repository.Get(ctx, userID, models.StatsPeriodAll)
		require.NoError(t, err)

		assert.Equal(t, models.StatsPeriodAll, result.Period)

		assert.Equal(t, uint64(2), result.MoviesWant)
		assert.Equal(t, uint64(3), result.MoviesWatched)
		assert.Equal(t, uint64(310), result.MoviesMinutes)

		require.NotNil(t, result.SeriesWatching)
		assert.Equal(t, uint64(1), result.SeriesWant)
		assert.Equal(t, uint64(1), *result.SeriesWatching)
		assert.Equal(t, uint64(1), result.SeriesWatched)

		assert.Equal(t, uint64(3), result.EpisodesWatched)
		assert.Equal(t, uint64(114), result.EpisodesMinutes)

		require.NotNil(t, result.GamesPlaying)
		assert.Equal(t, uint64(1), result.GamesWant)
		assert.Equal(t, uint64(1), *result.GamesPlaying)
		assert.Equal(t, uint64(2), result.GamesPlayed)
		// only the played games count toward minutes, so the 3000 in progress stays out
		assert.Equal(t, uint64(2400), result.GamesMinutes)
	})

	t.Run("A bounded period omits the playing count", func(t *testing.T) {
		result, err := repository.Get(ctx, userID, models.StatsPeriodYear)
		require.NoError(t, err)

		assert.Nil(t, result.GamesPlaying)
		// CreateGame stamps played_at now, so both played games land in the current year
		assert.Equal(t, uint64(2), result.GamesPlayed)
		assert.Equal(t, uint64(2400), result.GamesMinutes)
	})
}

func Test_StatsRepository_Get_Periods(t *testing.T) {
	ctx := context.Background()
	client := newRepoTestClient(t)
	repository := NewStatsRepository(client)
	userID := newProgressTestUser(t, client, "stats.periods")

	seedStatsMovie(t, client, userID, 910001, 40, models.StateTypeWant)
	seedStatsMovie(t, client, userID, 910002, 100, models.StateTypeWatched)
	seedStatsMovie(t, client, userID, 910003, 50, models.StateTypeWatched)
	seedStatsMovie(t, client, userID, 910004, 70, models.StateTypeWatched)

	series := seedStatsSeries(t, client, userID, 910101, models.StateTypeWatching)
	seedStatsEpisodes(t, client, series, 910201, 42, 42, 30)

	// Everything is seeded as watched now; push some of it into earlier years, far
	// enough back that it stays out of the current week, month and year whatever today is
	backdateStatsMovie(t, client, userID, 910003, "18 months")
	backdateStatsMovie(t, client, userID, 910004, "30 months")
	backdateStatsEpisode(t, client, 91020102, "18 months")

	weekStart := statsAnchor(t, client, "week")
	monthStart := statsAnchor(t, client, "month")
	yearStart := statsAnchor(t, client, "year")
	monthEnd := monthStart.AddDate(0, 1, -1)

	tests := []struct {
		period          models.StatsPeriod
		moviesWatched   uint64
		moviesMinutes   uint64
		seriesWatched   uint64
		episodesWatched uint64
		episodesMinutes uint64
		buckets         int
		firstBucket     time.Time
		lastBucket      time.Time
	}{
		{models.StatsPeriodWeek, 1, 100, 1, 2, 84, 7, weekStart, weekStart.AddDate(0, 0, 6)},
		{models.StatsPeriodMonth, 1, 100, 1, 2, 84, monthEnd.Day(), monthStart, monthEnd},
		{models.StatsPeriodYear, 1, 100, 1, 2, 84, 12, yearStart, yearStart.AddDate(0, 11, 0)},
		// the only series is still watching, so all-time counts no finished show
		{models.StatsPeriodAll, 3, 220, 0, 3, 114, 4, yearStart.AddDate(-3, 0, 0), yearStart},
	}

	for _, tt := range tests {
		t.Run(tt.period.String(), func(t *testing.T) {
			result, err := repository.Get(ctx, userID, tt.period)
			require.NoError(t, err)

			assert.Equal(t, tt.period, result.Period)
			assert.Equal(t, tt.moviesWatched, result.MoviesWatched)
			assert.Equal(t, tt.moviesMinutes, result.MoviesMinutes)
			assert.Equal(t, tt.seriesWatched, result.SeriesWatched)
			assert.Equal(t, tt.episodesWatched, result.EpisodesWatched)
			assert.Equal(t, tt.episodesMinutes, result.EpisodesMinutes)

			// The one want movie was seeded just now, so it lands in every window
			assert.Equal(t, uint64(1), result.MoviesWant)
			assert.Equal(t, uint64(0), result.SeriesWant)

			// A show is being watched now, so only all-time carries that count
			if tt.period == models.StatsPeriodAll {
				require.NotNil(t, result.SeriesWatching)
				assert.Equal(t, uint64(1), *result.SeriesWatching)
			} else {
				assert.Nil(t, result.SeriesWatching)
			}

			// The chart covers the whole calendar period, including days still to come
			dates := bucketDates(result.Activity)
			require.Len(t, dates, tt.buckets)
			assert.Equal(t, tt.firstBucket.Format(time.DateOnly), dates[0])
			assert.Equal(t, tt.lastBucket.Format(time.DateOnly), dates[len(dates)-1])

			var movieMinutes, tvMinutes uint64
			for _, bucket := range result.Activity {
				movieMinutes += bucket.MovieMinutes
				tvMinutes += bucket.TvMinutes
			}

			assert.Equal(t, tt.moviesMinutes, movieMinutes)
			assert.Equal(t, tt.episodesMinutes, tvMinutes)
		})
	}

	t.Run("Weeks run monday to sunday", func(t *testing.T) {
		result, err := repository.Get(ctx, userID, models.StatsPeriodWeek)
		require.NoError(t, err)

		require.Len(t, result.Activity, 7)
		assert.Equal(t, time.Monday, result.Activity[0].Date.Weekday())
		assert.Equal(t, time.Sunday, result.Activity[6].Date.Weekday())
	})

	t.Run("Years run january to december", func(t *testing.T) {
		result, err := repository.Get(ctx, userID, models.StatsPeriodYear)
		require.NoError(t, err)

		require.Len(t, result.Activity, 12)

		for i, bucket := range result.Activity {
			assert.Equal(t, time.Month(i+1), bucket.Date.Month())
			assert.Equal(t, 1, bucket.Date.Day())
		}
	})

	t.Run("All time buckets by year", func(t *testing.T) {
		result, err := repository.Get(ctx, userID, models.StatsPeriodAll)
		require.NoError(t, err)

		require.Len(t, result.Activity, 4)

		for i, bucket := range result.Activity {
			assert.Equal(t, time.January, bucket.Date.Month())
			assert.Equal(t, 1, bucket.Date.Day())
			assert.Equal(t, yearStart.Year()-3+i, bucket.Date.Year())
		}
	})
}

func Test_StatsRepository_Get_MonthStartsOnTheFirst(t *testing.T) {
	ctx := context.Background()
	client := newRepoTestClient(t)
	repository := NewStatsRepository(client)
	userID := newProgressTestUser(t, client, "stats.monthstart")

	seedStatsMovie(t, client, userID, 920001, 60, models.StateTypeWatched)
	anchorStatsMovie(t, client, userID, 920001, "month")

	// The first of the month can precede the current week, so only the wider windows are certain
	for _, period := range []models.StatsPeriod{models.StatsPeriodMonth, models.StatsPeriodYear, models.StatsPeriodAll} {
		t.Run(period.String(), func(t *testing.T) {
			result, err := repository.Get(ctx, userID, period)
			require.NoError(t, err)

			assert.Equal(t, uint64(1), result.MoviesWatched)
			assert.Equal(t, uint64(60), result.MoviesMinutes)
		})
	}

	t.Run("Lands in the first bucket of the month", func(t *testing.T) {
		result, err := repository.Get(ctx, userID, models.StatsPeriodMonth)
		require.NoError(t, err)

		require.NotEmpty(t, result.Activity)
		assert.Equal(t, statsAnchor(t, client, "month").Format(time.DateOnly), result.Activity[0].Date.Format(time.DateOnly))
		assert.Equal(t, uint64(60), result.Activity[0].MovieMinutes)
	})
}

func Test_StatsRepository_Get_CountsAShowOncePerPeriod(t *testing.T) {
	ctx := context.Background()
	client := newRepoTestClient(t)
	repository := NewStatsRepository(client)
	userID := newProgressTestUser(t, client, "stats.shows")

	binged := seedStatsSeries(t, client, userID, 930101, models.StateTypeWatching)
	dipped := seedStatsSeries(t, client, userID, 930102, models.StateTypeWatching)
	dormant := seedStatsSeries(t, client, userID, 930103, models.StateTypeWatching)

	seedStatsEpisodes(t, client, binged, 930201, 42, 42, 42)
	seedStatsEpisodes(t, client, dipped, 930202, 55)
	seedStatsEpisodes(t, client, dormant, 930203, 60)

	backdateStatsEpisode(t, client, 93020300, "18 months")

	result, err := repository.Get(ctx, userID, models.StatsPeriodWeek)
	require.NoError(t, err)

	// Three episodes of one show plus one of another is two shows watched, not four
	assert.Equal(t, uint64(2), result.SeriesWatched)
	assert.Equal(t, uint64(4), result.EpisodesWatched)
	assert.Equal(t, uint64(181), result.EpisodesMinutes)
}

func Test_StatsRepository_Get_CountsWantAddedInThePeriod(t *testing.T) {
	ctx := context.Background()
	client := newRepoTestClient(t)
	repository := NewStatsRepository(client)
	userID := newProgressTestUser(t, client, "stats.wantadded")

	seedStatsMovie(t, client, userID, 940001, 90, models.StateTypeWant)
	seedStatsMovie(t, client, userID, 940002, 95, models.StateTypeWant)
	seedStatsMovie(t, client, userID, 940003, 100, models.StateTypeWant)

	// Two of them were added long enough ago to fall outside the current week
	_, err := client.Db().Exec(
		ctx,
		`UPDATE movies SET created_at = NOW() - INTERVAL '18 months' WHERE user_id = $1 AND tmdb_id = ANY($2::integer[])`,
		userID, []int32{940002, 940003},
	)
	require.NoError(t, err)

	week, err := repository.Get(ctx, userID, models.StatsPeriodWeek)
	require.NoError(t, err)
	assert.Equal(t, uint64(1), week.MoviesWant)

	all, err := repository.Get(ctx, userID, models.StatsPeriodAll)
	require.NoError(t, err)
	assert.Equal(t, uint64(3), all.MoviesWant)
}

func Test_StatsRepository_Get_Empty(t *testing.T) {
	ctx := context.Background()
	client := newRepoTestClient(t)
	repository := NewStatsRepository(client)
	userID := newProgressTestUser(t, client, "stats.empty")

	result, err := repository.Get(ctx, userID, models.StatsPeriodAll)
	require.NoError(t, err)

	// With nothing watched the history collapses to the current year
	require.Len(t, result.Activity, 1)
	assert.Equal(t, statsAnchor(t, client, "year").Format(time.DateOnly), result.Activity[0].Date.Format(time.DateOnly))

	require.NotNil(t, result.SeriesWatching)
	assert.Equal(t, uint64(0), result.MoviesWant)
	assert.Equal(t, uint64(0), result.MoviesWatched)
	assert.Equal(t, uint64(0), result.MoviesMinutes)
	assert.Equal(t, uint64(0), result.SeriesWant)
	assert.Equal(t, uint64(0), *result.SeriesWatching)
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

	result, err := repository.Get(canceled, userID, models.StatsPeriodAll)
	require.Error(t, err)
	assert.Nil(t, result)
}
