package repositories

import (
	"testing"

	"github.com/stretchr/testify/assert"

	"biinge-api/internal/app/models"
)

func Test_deriveSeriesState(t *testing.T) {
	cases := []struct {
		name            string
		watchedEpisodes uint64
		watchedSeasons  uint64
		totalSeasons    uint64
		status          string
		want            string
	}{
		{
			name: "no watched episodes is untracked",
			want: models.StateTypeNone,
		},
		{
			name:            "partway through a season is watching",
			watchedEpisodes: 4,
			watchedSeasons:  0,
			totalSeasons:    3,
			status:          "Ended",
			want:            models.StateTypeWatching,
		},
		{
			name:            "some but not all seasons watched is watching",
			watchedEpisodes: 20,
			watchedSeasons:  2,
			totalSeasons:    3,
			status:          "Ended",
			want:            models.StateTypeWatching,
		},
		{
			name:            "every season watched marks a finished show watched",
			watchedEpisodes: 30,
			watchedSeasons:  3,
			totalSeasons:    3,
			status:          "Ended",
			want:            models.StateTypeWatched,
		},
		{
			// the drift bug: TMDB's show-level episode total no longer matters,
			// completing every season is enough to mark the show watched
			name:            "watched even when episode count would fall short of the TMDB total",
			watchedEpisodes: 61,
			watchedSeasons:  3,
			totalSeasons:    3,
			status:          "Ended",
			want:            models.StateTypeWatched,
		},
		{
			name:            "a still-airing show never completes",
			watchedEpisodes: 30,
			watchedSeasons:  3,
			totalSeasons:    3,
			status:          models.TvInProductionStatus,
			want:            models.StateTypeWatching,
		},
		{
			name:            "unknown season total stays watching",
			watchedEpisodes: 10,
			watchedSeasons:  0,
			totalSeasons:    0,
			status:          "Ended",
			want:            models.StateTypeWatching,
		},
	}

	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			got := deriveSeriesState(tc.watchedEpisodes, tc.watchedSeasons, tc.totalSeasons, tc.status)
			assert.Equal(t, tc.want, got)
		})
	}
}
