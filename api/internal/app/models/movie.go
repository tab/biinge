package models

import (
	"time"

	"github.com/google/uuid"
)

const (
	StateTypeWant     = "want"
	StateTypeWatched  = "watched"
	StateTypeWatching = "watching"
	StateTypeNone     = "none"
)

type Movie struct {
	ID         uuid.UUID
	UserId     uuid.UUID
	TmdbId     uint64
	Title      string
	PosterPath string
	Runtime    uint64
	State      string
	Pinned     bool
	CreatedAt  time.Time
	UpdatedAt  time.Time
}
