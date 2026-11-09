package serializers

import (
	"io"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"biinge-api/internal/app/models"
)

func Test_CreateShareRequest_Validate(t *testing.T) {
	tests := []struct {
		name     string
		body     io.Reader
		expected CreateShareRequestSerializer
		wantErr  bool
	}{
		{
			name:     "Movie",
			body:     strings.NewReader(`{ "type": "movie", "object_id": 603 }`),
			expected: CreateShareRequestSerializer{Type: models.ShareTypeMovie, ObjectId: 603},
		},
		{
			name:     "Series",
			body:     strings.NewReader(`{ "type": "tv", "object_id": 1399 }`),
			expected: CreateShareRequestSerializer{Type: models.ShareTypeTv, ObjectId: 1399},
		},
		{
			name:     "Game",
			body:     strings.NewReader(`{ "type": "game", "object_id": 1942 }`),
			expected: CreateShareRequestSerializer{Type: models.ShareTypeGame, ObjectId: 1942},
		},
		{
			name:     "Largest id the column holds",
			body:     strings.NewReader(`{ "type": "movie", "object_id": 2147483647 }`),
			expected: CreateShareRequestSerializer{Type: models.ShareTypeMovie, ObjectId: 2147483647},
		},
		{
			name:    "Unknown type",
			body:    strings.NewReader(`{ "type": "book", "object_id": 603 }`),
			wantErr: true,
		},
		{
			name:    "Missing type",
			body:    strings.NewReader(`{ "object_id": 603 }`),
			wantErr: true,
		},
		{
			name:    "Zero object id",
			body:    strings.NewReader(`{ "type": "movie", "object_id": 0 }`),
			wantErr: true,
		},
		{
			name:    "Negative object id",
			body:    strings.NewReader(`{ "type": "movie", "object_id": -1 }`),
			wantErr: true,
		},
		{
			name:    "Object id past the column",
			body:    strings.NewReader(`{ "type": "movie", "object_id": 2147483648 }`),
			wantErr: true,
		},
		{
			name:    "Malformed body",
			body:    strings.NewReader(`{ "type":`),
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var params CreateShareRequestSerializer

			err := params.Validate(tt.body)

			if tt.wantErr {
				require.Error(t, err)
				return
			}

			require.NoError(t, err)
			assert.Equal(t, tt.expected, params)
		})
	}
}
