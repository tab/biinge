package serializers

import (
	"encoding/json"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"biinge-api/internal/app/models"
)

func Test_NewStatsSerializer(t *testing.T) {
	seriesWatching := uint64(5)

	stats := &models.Stats{
		Period:          models.StatsPeriodAll,
		MoviesWant:      1,
		MoviesWatched:   2,
		MoviesMinutes:   300,
		SeriesWant:      4,
		SeriesWatching:  &seriesWatching,
		SeriesWatched:   6,
		EpisodesWatched: 7,
		EpisodesMinutes: 800,
		Activity: []models.WatchBucket{
			{Date: time.Date(2026, time.February, 1, 0, 0, 0, 0, time.UTC), MovieMinutes: 120, TvMinutes: 240},
			{Date: time.Date(2026, time.March, 1, 0, 0, 0, 0, time.UTC), MovieMinutes: 0, TvMinutes: 90},
		},
	}

	expected := StatsSerializer{
		Period: "all",
		Movies: MovieStatsSerializer{
			Want:    1,
			Watched: 2,
			Minutes: 300,
		},
		Series: SeriesStatsSerializer{
			Want:     4,
			Watching: &seriesWatching,
			Watched:  6,
		},
		Episodes: EpisodeStatsSerializer{
			Watched: 7,
			Minutes: 800,
		},
		Activity: []ActivityBucketSerializer{
			{Date: "2026-02-01", MovieMinutes: 120, TvMinutes: 240},
			{Date: "2026-03-01", MovieMinutes: 0, TvMinutes: 90},
		},
	}

	assert.Equal(t, expected, NewStatsSerializer(stats))
}

func Test_NewStatsSerializer_OmitsWatchingOnABoundedPeriod(t *testing.T) {
	stats := &models.Stats{
		Period:          models.StatsPeriodWeek,
		MoviesWant:      1,
		MoviesWatched:   2,
		MoviesMinutes:   300,
		SeriesWant:      0,
		SeriesWatched:   3,
		EpisodesWatched: 7,
		EpisodesMinutes: 800,
	}

	payload, err := json.Marshal(NewStatsSerializer(stats))
	require.NoError(t, err)

	// A client reading a bounded period must not find a number that silently means all-time
	assert.NotContains(t, string(payload), `"watching"`)

	// Want is scoped to the period rather than dropped, so a zero still has to reach the client
	assert.Contains(t, string(payload), `"want":1`)
	assert.Contains(t, string(payload), `"want":0`)
}
