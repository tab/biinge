package serializers

import (
	"io"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"

	"biinge-api/internal/app/errors"
)

func Test_UpdateMovieRequest_Validate(t *testing.T) {
	tests := []struct {
		name     string
		body     io.Reader
		expected error
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
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var params UpdateMovieRequestSerializer
			err := params.Validate(tt.body)

			assert.Equal(t, tt.expected, err)
		})
	}
}
