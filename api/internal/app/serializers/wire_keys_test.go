package serializers

import (
	"encoding/json"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"biinge-api/internal/app/models"
)

func Test_SeriesWireKeys(t *testing.T) {
	tests := []struct {
		name    string
		payload any
		key     string
		oldKey  string
	}{
		{
			name: "Stats activity bucket",
			payload: NewStatsSerializer(&models.Stats{
				Activity: []models.WatchBucket{{Date: time.Date(2026, time.January, 1, 0, 0, 0, 0, time.UTC), SeriesMinutes: 5}},
			}),
			key:    `"seriesMinutes":5`,
			oldKey: `"tvMinutes"`,
		},
		{
			name:    "Person details",
			payload: PersonDetailsSerializer{SeriesCredits: []SeriesCreditSerializer{{Id: 1}}},
			key:     `"seriesCredits":[`,
			oldKey:  `"tvCredits"`,
		},
		{
			name:    "Season details",
			payload: SeasonDetailsSerializer{TmdbSeriesId: 7},
			key:     `"tmdbSeriesId":7`,
			oldKey:  `"tmdbShowId"`,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			body, err := json.Marshal(tt.payload)
			require.NoError(t, err)

			assert.Contains(t, string(body), tt.key)
			assert.NotContains(t, string(body), tt.oldKey)
		})
	}
}
