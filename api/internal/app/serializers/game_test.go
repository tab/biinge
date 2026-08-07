package serializers

import (
	"io"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"biinge-api/internal/app/errors"
)

func Test_CreateGameRequest_Validate(t *testing.T) {
	tests := []struct {
		name     string
		body     io.Reader
		expected error
		wantErr  bool
	}{
		{
			name:     "Success",
			body:     strings.NewReader(`{ "id": 1942, "title": "The Witcher 3", "posterPath": "co1wyy", "runtime": 3000, "state": "want" }`),
			expected: nil,
		},
		{
			name:     "Playing state",
			body:     strings.NewReader(`{ "id": 1942, "title": "The Witcher 3", "state": "playing" }`),
			expected: nil,
		},
		{
			name:     "Played state",
			body:     strings.NewReader(`{ "id": 1942, "title": "The Witcher 3", "state": "played" }`),
			expected: nil,
		},
		{
			name:     "Empty title",
			body:     strings.NewReader(`{ "id": 1942, "title": "", "state": "want" }`),
			expected: errors.ErrEmptyTitle,
		},
		{
			name:     "Whitespace title",
			body:     strings.NewReader(`{ "id": 1942, "title": "   ", "state": "want" }`),
			expected: errors.ErrEmptyTitle,
		},
		{
			name:     "Empty state",
			body:     strings.NewReader(`{ "id": 1942, "title": "The Witcher 3", "state": "" }`),
			expected: errors.ErrEmptyState,
		},
		{
			// games are played, so the movie and series values are rejected even though
			// they are legal members of the shared state_types enum
			name:     "Watched state is rejected",
			body:     strings.NewReader(`{ "id": 1942, "title": "The Witcher 3", "state": "watched" }`),
			expected: errors.ErrInvalidState,
		},
		{
			name:     "Watching state is rejected",
			body:     strings.NewReader(`{ "id": 1942, "title": "The Witcher 3", "state": "watching" }`),
			expected: errors.ErrInvalidState,
		},
		{
			name:    "Missing id",
			body:    strings.NewReader(`{ "title": "The Witcher 3", "state": "want" }`),
			wantErr: true,
		},
		{
			name:    "Malformed body",
			body:    strings.NewReader(`{`),
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var params CreateGameRequestSerializer

			err := params.Validate(tt.body)

			switch {
			case tt.expected != nil:
				require.ErrorIs(t, err, tt.expected)
			case tt.wantErr:
				require.Error(t, err)
			default:
				require.NoError(t, err)
			}
		})
	}
}

func Test_CreateGameRequest_TrimsInput(t *testing.T) {
	var params CreateGameRequestSerializer

	require.NoError(t, params.Validate(strings.NewReader(
		`{ "id": 1942, "title": "  The Witcher 3  ", "posterPath": "  co1wyy  ", "state": "  want  " }`,
	)))

	assert.Equal(t, "The Witcher 3", params.Title)
	assert.Equal(t, "co1wyy", params.PosterPath)
	assert.Equal(t, "want", params.State)
}

func Test_UpdateGameRequest_Validate(t *testing.T) {
	tests := []struct {
		name     string
		body     io.Reader
		expected error
		wantErr  bool
	}{
		{
			name:     "Success",
			body:     strings.NewReader(`{ "state": "played", "pinned": true }`),
			expected: nil,
		},
		{
			name:     "Playing state",
			body:     strings.NewReader(`{ "state": "playing", "pinned": false }`),
			expected: nil,
		},
		{
			name:     "Empty state",
			body:     strings.NewReader(`{ "pinned": true }`),
			expected: errors.ErrEmptyState,
		},
		{
			name:     "Invalid state",
			body:     strings.NewReader(`{ "state": "finished" }`),
			expected: errors.ErrInvalidState,
		},
		{
			name:     "Watched state is rejected",
			body:     strings.NewReader(`{ "state": "watched" }`),
			expected: errors.ErrInvalidState,
		},
		{
			name:     "Watching state is rejected",
			body:     strings.NewReader(`{ "state": "watching" }`),
			expected: errors.ErrInvalidState,
		},
		{
			name:    "Malformed body",
			body:    strings.NewReader(`{`),
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var params UpdateGameRequestSerializer

			err := params.Validate(tt.body)

			switch {
			case tt.expected != nil:
				require.ErrorIs(t, err, tt.expected)
			case tt.wantErr:
				require.Error(t, err)
			default:
				require.NoError(t, err)
			}
		})
	}
}
