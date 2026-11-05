package serializers

import (
	"encoding/json"
	"io"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"biinge-api/internal/app/errors"
)

func Test_CreateMovieRequest_Validate(t *testing.T) {
	tests := []struct {
		name     string
		body     io.Reader
		expected error
		wantErr  bool
	}{
		{
			name:     "Success",
			body:     strings.NewReader(`{ "id": 1, "title": "Movie", "posterPath": "/poster.jpg", "runtime": 120, "state": "want" }`),
			expected: nil,
		},
		{
			name:     "Empty title",
			body:     strings.NewReader(`{ "id": 1, "title": "", "state": "want" }`),
			expected: errors.ErrEmptyTitle,
		},
		{
			name:     "Whitespace title",
			body:     strings.NewReader(`{ "id": 1, "title": "   ", "state": "want" }`),
			expected: errors.ErrEmptyTitle,
		},
		{
			name:     "Empty state",
			body:     strings.NewReader(`{ "id": 1, "title": "Movie", "state": "" }`),
			expected: errors.ErrEmptyState,
		},
		{
			name:     "Invalid state",
			body:     strings.NewReader(`{ "id": 1, "title": "Movie", "state": "invalid" }`),
			expected: errors.ErrInvalidState,
		},
		{
			name:    "Missing id",
			body:    strings.NewReader(`{ "title": "Movie", "state": "want" }`),
			wantErr: true,
		},
		{
			name:    "Malformed JSON",
			body:    strings.NewReader(`{ invalid`),
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var params CreateMovieRequestSerializer

			err := params.Validate(tt.body)

			if tt.wantErr {
				require.Error(t, err)
				return
			}

			assert.Equal(t, tt.expected, err)
		})
	}
}

func Test_UpdateMovieRequest_Validate(t *testing.T) {
	tests := []struct {
		name     string
		body     io.Reader
		expected error
		wantErr  bool
	}{
		{
			name:     "Success",
			body:     strings.NewReader(`{ "state": "want", "pinned": true }`),
			expected: nil,
		},
		{
			name:     "Empty state",
			body:     strings.NewReader(`{ "state": "", "pinned": true }`),
			expected: errors.ErrEmptyState,
		},
		{
			name:     "Invalid state",
			body:     strings.NewReader(`{ "state": "invalid", "pinned": true }`),
			expected: errors.ErrInvalidState,
		},
		{
			name:    "Malformed JSON",
			body:    strings.NewReader(`{ invalid`),
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var params UpdateMovieRequestSerializer

			err := params.Validate(tt.body)

			if tt.wantErr {
				require.Error(t, err)
				return
			}

			assert.Equal(t, tt.expected, err)
		})
	}
}

func Test_MovieDetailsSerializer_Marshal(t *testing.T) {
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
			directors:         []string{"Lana Wachowski"},
			expected:          `"jellyfinId":"jf-1"`,
			expectedDirectors: `"directors":["Lana Wachowski"]`,
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
			data, err := json.Marshal(MovieDetailsSerializer{Id: 1, JellyfinId: tt.jellyfinId, Directors: tt.directors})

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
