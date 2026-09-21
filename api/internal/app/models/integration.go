package models

import (
	"time"

	"github.com/google/uuid"
)

// JellyfinProvider is the provider value of a Jellyfin link
const JellyfinProvider = "jellyfin"

// Integration links a user to an external media server through a hashed bearer token
type Integration struct {
	ID        uuid.UUID
	UserId    uuid.UUID
	Provider  string
	TokenHash string
	CreatedAt time.Time
	UpdatedAt time.Time
}
