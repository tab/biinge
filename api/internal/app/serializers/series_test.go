package serializers

import (
	"io"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"biinge-api/internal/app/errors"
)

func Test_CreateSeriesRequest_Validate(t *testing.T) {
	tests := []struct {
		name     string
		body     io.Reader
		expected error
		wantErr  bool
	}{
		{
			name:     "Success",
			body:     strings.NewReader(`{ "id": 1, "title": "Show", "posterPath": "/poster.jpg", "seasonsCount": 2, "episodesCount": 20, "state": "watching" }`),
			expected: nil,
		},
		{
			name:     "Empty title",
			body:     strings.NewReader(`{ "id": 1, "title": "", "state": "watching" }`),
			expected: errors.ErrEmptyTitle,
		},
		{
			name:     "Whitespace title",
			body:     strings.NewReader(`{ "id": 1, "title": "   ", "state": "watching" }`),
			expected: errors.ErrEmptyTitle,
		},
		{
			name:     "Empty state",
			body:     strings.NewReader(`{ "id": 1, "title": "Show", "state": "" }`),
			expected: errors.ErrEmptyState,
		},
		{
			name:     "Invalid state",
			body:     strings.NewReader(`{ "id": 1, "title": "Show", "state": "invalid" }`),
			expected: errors.ErrInvalidState,
		},
		{
			name:    "Missing id",
			body:    strings.NewReader(`{ "title": "Show", "state": "watching" }`),
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
			var params CreateSeriesRequestSerializer

			err := params.Validate(tt.body)

			if tt.wantErr {
				require.Error(t, err)
				return
			}

			assert.Equal(t, tt.expected, err)
		})
	}
}

func Test_UpdateSeriesRequest_Validate(t *testing.T) {
	tests := []struct {
		name     string
		body     io.Reader
		expected error
		wantErr  bool
	}{
		{
			name:     "Success",
			body:     strings.NewReader(`{ "state": "watched", "pinned": true }`),
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
			var params UpdateSeriesRequestSerializer

			err := params.Validate(tt.body)

			if tt.wantErr {
				require.Error(t, err)
				return
			}

			assert.Equal(t, tt.expected, err)
		})
	}
}
