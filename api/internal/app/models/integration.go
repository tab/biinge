package models

import (
	"time"

	"github.com/google/uuid"
)

// JellyfinProvider is the provider value of a Jellyfin link
const JellyfinProvider = "jellyfin"

// Integration is the API's sign-in to a user's external media server
type Integration struct {
	ID             uuid.UUID
	UserId         uuid.UUID
	Provider       string
	ExternalUserId string
	Username       string
	// Token is the provider's access token, AES-GCM encrypted under JELLYFIN_TOKEN_KEY
	Token []byte

	CreatedAt time.Time
	UpdatedAt time.Time
}

// JellyfinConnection is a user's Jellyfin connection status (it never carries the token)
type JellyfinConnection struct {
	BaseURL   string
	Connected bool
	Username  string
}
