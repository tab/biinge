package serializers

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"

	"biinge-api/internal/app/models"
)

func Test_NewStatsSerializer(t *testing.T) {
	stats := &models.Stats{
		MoviesWant:      1,
		MoviesWatched:   2,
		MoviesMinutes:   300,
		SeriesWant:      4,
		SeriesWatching:  5,
		SeriesWatched:   6,
		EpisodesWatched: 7,
		EpisodesMinutes: 800,
		Activity: []models.MonthlyWatch{
			{Month: time.Date(2026, time.February, 1, 0, 0, 0, 0, time.UTC), MovieMinutes: 120, TvMinutes: 240},
			{Month: time.Date(2026, time.March, 1, 0, 0, 0, 0, time.UTC), MovieMinutes: 0, TvMinutes: 90},
		},
	}

	expected := StatsSerializer{
		Movies: MovieStatsSerializer{
			Want:    1,
			Watched: 2,
			Minutes: 300,
		},
		Series: SeriesStatsSerializer{
			Want:     4,
			Watching: 5,
			Watched:  6,
		},
		Episodes: EpisodeStatsSerializer{
			Watched: 7,
			Minutes: 800,
		},
		Activity: []MonthlyActivitySerializer{
			{Month: "2026-02", MovieMinutes: 120, TvMinutes: 240},
			{Month: "2026-03", MovieMinutes: 0, TvMinutes: 90},
		},
	}

	assert.Equal(t, expected, NewStatsSerializer(stats))
}
