package serializers

import (
	"io"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"

	"biinge-api/internal/app/errors"
)

func Test_UpdateAccountRequest_Validate(t *testing.T) {
	tests := []struct {
		name     string
		body     io.Reader
		expected error
	}{
		{
			name:     "Success",
			body:     strings.NewReader(`{ "first_name": "John", "last_name": "Doe", "appearance": "dark" }`),
			expected: nil,
		},
		{
			name:     "Empty first name",
			body:     strings.NewReader(`{ "first_name": "", "last_name": "Doe", "appearance": "dark" }`),
			expected: errors.ErrEmptyFirstName,
		},
		{
			name:     "Empty last name",
			body:     strings.NewReader(`{ "first_name": "John", "last_name": "", "appearance": "dark" }`),
			expected: errors.ErrEmptyLastName,
		},
		{
			name:     "Empty appearance",
			body:     strings.NewReader(`{ "first_name": "John", "last_name": "Doe", "appearance": "" }`),
			expected: errors.ErrEmptyAppearance,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var params UpdateAccountRequestSerializer
			err := params.Validate(tt.body)

			assert.Equal(t, tt.expected, err)
		})
	}
}
