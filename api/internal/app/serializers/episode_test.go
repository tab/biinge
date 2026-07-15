package serializers

import (
	"io"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"biinge-api/internal/app/errors"
)

func Test_CreateEpisodeRequest_Validate(t *testing.T) {
	tests := []struct {
		name     string
		body     io.Reader
		expected error
		wantErr  bool
	}{
		{
			name:     "Success",
			body:     strings.NewReader(`{ "id": 1, "title": "Pilot", "runtime": 45, "state": "watched" }`),
			expected: nil,
		},
		{
			name:     "Empty title",
			body:     strings.NewReader(`{ "id": 1, "title": "", "state": "watched" }`),
			expected: errors.ErrEmptyTitle,
		},
		{
			name:     "Whitespace title",
			body:     strings.NewReader(`{ "id": 1, "title": "   ", "state": "watched" }`),
			expected: errors.ErrEmptyTitle,
		},
		{
			name:     "Empty state",
			body:     strings.NewReader(`{ "id": 1, "title": "Pilot", "state": "" }`),
			expected: errors.ErrEmptyState,
		},
		{
			name:     "Invalid state",
			body:     strings.NewReader(`{ "id": 1, "title": "Pilot", "state": "invalid" }`),
			expected: errors.ErrInvalidState,
		},
		{
			name:    "Missing id",
			body:    strings.NewReader(`{ "title": "Pilot", "state": "watched" }`),
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
			var params CreateEpisodeRequestSerializer

			err := params.Validate(tt.body)

			if tt.wantErr {
				require.Error(t, err)
				return
			}

			assert.Equal(t, tt.expected, err)
		})
	}
}

func Test_UpdateEpisodeRequest_Validate(t *testing.T) {
	tests := []struct {
		name     string
		body     io.Reader
		expected error
		wantErr  bool
	}{
		{
			name:     "Success",
			body:     strings.NewReader(`{ "state": "watching" }`),
			expected: nil,
		},
		{
			name:     "Empty state",
			body:     strings.NewReader(`{ "state": "" }`),
			expected: errors.ErrEmptyState,
		},
		{
			name:     "Invalid state",
			body:     strings.NewReader(`{ "state": "invalid" }`),
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
			var params UpdateEpisodeRequestSerializer

			err := params.Validate(tt.body)

			if tt.wantErr {
				require.Error(t, err)
				return
			}

			assert.Equal(t, tt.expected, err)
		})
	}
}
