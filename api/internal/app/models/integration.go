package models

import (
	"time"

	"github.com/google/uuid"
)

// JellyfinProvider is the provider value of a Jellyfin link
const JellyfinProvider = "jellyfin"

// Integration links a user to an external media server (an empty TokenHash means no webhook token, a nil JellyfinToken no connection)
type Integration struct {
	ID        uuid.UUID
	UserId    uuid.UUID
	Provider  string
	TokenHash string

	JellyfinUserId   string
	JellyfinUsername string
	// JellyfinToken is the connection's access token, AES-GCM encrypted under JELLYFIN_TOKEN_KEY
	JellyfinToken []byte

	CreatedAt time.Time
	UpdatedAt time.Time
}

// JellyfinConnection is a user's Jellyfin connection status (it never carries the token)
type JellyfinConnection struct {
	BaseURL   string
	Connected bool
	Username  string
}
