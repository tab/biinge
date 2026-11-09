package models

import (
	"time"

	"github.com/google/uuid"
)

// ShareType is the kind of title a share points at
type ShareType string

const (
	ShareTypeMovie ShareType = "movie"
	ShareTypeTv    ShareType = "tv"
	ShareTypeGame  ShareType = "game"
)

// Share is a public link to a title a user chose to share
type Share struct {
	ID     uuid.UUID
	Type   ShareType
	UserId uuid.UUID
	// ObjectId is the TMDB id of a movie or series, or the IGDB id of a game
	ObjectId uint64

	VisitedAt time.Time
	CreatedAt time.Time
	UpdatedAt time.Time
}
