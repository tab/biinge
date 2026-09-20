package models

import (
	"time"

	"github.com/google/uuid"
)

type Movie struct {
	ID         uuid.UUID
	UserId     uuid.UUID
	TmdbId     uint64
	Title      string
	PosterPath string
	Runtime    uint64
	State      StateType
	Pinned     bool
	WatchedAt  time.Time
	CreatedAt  time.Time
	UpdatedAt  time.Time
}

// MovieSyncInput carries the TMDB-refreshed movie fields the sync worker writes back
type MovieSyncInput struct {
	Title      string
	PosterPath string
	Runtime    uint64
	ReleasedAt time.Time
}

// MovieFilter narrows a user's movies to the given TMDB ids
type MovieFilter struct {
	UserId  uuid.UUID
	TmdbIds []uint64
}
