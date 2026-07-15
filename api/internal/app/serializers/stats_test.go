package serializers

import (
	"testing"

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
	}

	assert.Equal(t, expected, NewStatsSerializer(stats))
}
