package serializers

import (
	"encoding/json"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func Test_SeasonEpisodeSerializer_Marshal(t *testing.T) {
	tests := []struct {
		name       string
		jellyfinId string
		expected   string
	}{
		{
			name:       "With a Jellyfin id",
			jellyfinId: "jf-1",
			expected:   `"jellyfinId":"jf-1"`,
		},
		{
			name:       "Without a Jellyfin id",
			jellyfinId: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			data, err := json.Marshal(SeasonEpisodeSerializer{Id: 1, JellyfinId: tt.jellyfinId})

			require.NoError(t, err)

			if tt.expected == "" {
				assert.NotContains(t, string(data), "jellyfinId")
				return
			}

			assert.Contains(t, string(data), tt.expected)
		})
	}
}
