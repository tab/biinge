package serializers

import (
	"io"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"biinge-api/internal/app/errors"
)

func Test_RegistrationRequest_Validate(t *testing.T) {
	tests := []struct {
		name     string
		body     io.Reader
		expected error
		wantErr  bool
	}{
		{
			name:     "Success",
			body:     strings.NewReader(`{ "login": "john.doe", "email": "john.doe@example.com", "password": "password123", "first_name": "John", "last_name": "Doe", "appearance": "light" }`),
			expected: nil,
		},
		{
			name:     "Empty login",
			body:     strings.NewReader(`{ "login": "", "email": "john.doe@example.com", "password": "password123", "first_name": "John", "last_name": "Doe", "appearance": "light" }`),
			expected: errors.ErrEmptyLogin,
		},
		{
			name:     "Empty email",
			body:     strings.NewReader(`{ "login": "john.doe", "email": "", "password": "password123", "first_name": "John", "last_name": "Doe", "appearance": "light" }`),
			expected: errors.ErrEmptyEmail,
		},
		{
			name:     "Empty password",
			body:     strings.NewReader(`{ "login": "john.doe", "email": "john.doe@example.com", "password": "", "first_name": "John", "last_name": "Doe", "appearance": "light" }`),
			expected: errors.ErrEmptyPassword,
		},
		{
			// first_name is enforced (validate:"required"), so an empty value is rejected
			name:    "Empty first name",
			body:    strings.NewReader(`{ "login": "john.doe", "email": "john.doe@example.com", "password": "password123", "first_name": "", "last_name": "Doe", "appearance": "light" }`),
			wantErr: true,
		},
		{
			// last_name is enforced (validate:"required"), so an empty value is rejected
			name:    "Empty last name",
			body:    strings.NewReader(`{ "login": "john.doe", "email": "john.doe@example.com", "password": "password123", "first_name": "John", "last_name": "", "appearance": "light" }`),
			wantErr: true,
		},
		{
			name:     "Empty appearance",
			body:     strings.NewReader(`{ "login": "john.doe", "email": "john.doe@example.com", "password": "password123", "first_name": "John", "last_name": "Doe", "appearance": "" }`),
			expected: nil,
		},
		{
			name:    "Invalid email",
			body:    strings.NewReader(`{ "login": "john.doe", "email": "not-an-email", "password": "password123", "first_name": "John", "last_name": "Doe", "appearance": "light" }`),
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
			var params RegistrationRequestSerializer

			err := params.Validate(tt.body)

			if tt.wantErr {
				require.Error(t, err)
				return
			}

			assert.Equal(t, tt.expected, err)
		})
	}
}

func Test_LoginRequest_Validate(t *testing.T) {
	tests := []struct {
		name     string
		body     io.Reader
		expected error
		wantErr  bool
	}{
		{
			name:     "Success",
			body:     strings.NewReader(`{ "email": "john.doe@example.com", "password": "password123" }`),
			expected: nil,
		},
		{
			name:     "Empty email",
			body:     strings.NewReader(`{ "email": "", "password": "password123" }`),
			expected: errors.ErrEmptyEmail,
		},
		{
			name:     "Empty password",
			body:     strings.NewReader(`{ "email": "john.doe@example.com", "password": "" }`),
			expected: errors.ErrEmptyPassword,
		},
		{
			name:    "Malformed JSON",
			body:    strings.NewReader(`{ invalid`),
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var params LoginRequestSerializer

			err := params.Validate(tt.body)

			if tt.wantErr {
				require.Error(t, err)
				return
			}

			assert.Equal(t, tt.expected, err)
		})
	}
}

func Test_RefreshRequest_Validate(t *testing.T) {
	tests := []struct {
		name     string
		body     io.Reader
		expected error
		wantErr  bool
	}{
		{
			name:     "Success",
			body:     strings.NewReader(`{ "refresh_token": "some-refresh-token" }`),
			expected: nil,
		},
		{
			name:     "Empty refresh token",
			body:     strings.NewReader(`{ "refresh_token": "" }`),
			expected: errors.ErrInvalidToken,
		},
		{
			name:     "Whitespace refresh token",
			body:     strings.NewReader(`{ "refresh_token": "   " }`),
			expected: errors.ErrInvalidToken,
		},
		{
			name:    "Malformed JSON",
			body:    strings.NewReader(`{ invalid`),
			wantErr: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var params RefreshRequestSerializer

			err := params.Validate(tt.body)

			if tt.wantErr {
				require.Error(t, err)
				return
			}

			assert.Equal(t, tt.expected, err)
		})
	}
}
