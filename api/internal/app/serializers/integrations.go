package serializers

import (
	"encoding/json"
	"io"
	"strings"

	"biinge-api/internal/app/errors"
)

// JellyfinConnectionRequestSerializer carries the Jellyfin username and password for one sign-in (the password is never stored)
type JellyfinConnectionRequestSerializer struct {
	Username string `json:"username"`
	Password string `json:"password"`
}

// Validate trims the username and leaves the password as sent (a Jellyfin password may start or end with a space)
func (params *JellyfinConnectionRequestSerializer) Validate(body io.Reader) error {
	if err := json.NewDecoder(body).Decode(params); err != nil {
		return err
	}

	params.Username = strings.TrimSpace(params.Username)

	if params.Username == "" {
		return errors.ErrEmptyLogin
	}

	if params.Password == "" {
		return errors.ErrEmptyPassword
	}

	return nil
}

// JellyfinConnectionSerializer is a user's Jellyfin connection status (it never carries the token)
type JellyfinConnectionSerializer struct {
	BaseURL   string `json:"base_url"`
	Connected bool   `json:"connected"`
	Username  string `json:"username,omitempty"`
}
