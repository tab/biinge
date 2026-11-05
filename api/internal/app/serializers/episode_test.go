package serializers

import (
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func Test_EpisodeDetailsSerializer_Marshal(t *testing.T) {
	tests := []struct {
		name              string
		jellyfinId        string
		directors         []string
		expected          string
		expectedDirectors string
	}{
		{
			name:              "With a Jellyfin id and directors",
			jellyfinId:        "jf-1",
			directors:         []string{"Vince Gilligan"},
			expected:          `"jellyfinId":"jf-1"`,
			expectedDirectors: `"directors":["Vince Gilligan"]`,
		},
		{
			name:       "Without a Jellyfin id or directors",
			jellyfinId: "",
		},
		{
			name:      "Empty directors are omitted",
			directors: []string{},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			data, err := json.Marshal(EpisodeDetailsSerializer{Id: 1, JellyfinId: tt.jellyfinId, Directors: tt.directors})

			require.NoError(t, err)

			if tt.expectedDirectors == "" {
				assert.NotContains(t, string(data), "directors")
			} else {
				assert.Contains(t, string(data), tt.expectedDirectors)
			}

			if tt.expected == "" {
				assert.NotContains(t, string(data), "jellyfinId")
				return
			}

			assert.Contains(t, string(data), tt.expected)
		})
	}
}
