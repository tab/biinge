package models

import (
	"time"

	"github.com/google/uuid"
)

type Series struct {
	ID                   uuid.UUID
	UserId               uuid.UUID
	TmdbId               uint64
	Title                string
	PosterPath           string
	SeasonsCount         uint64
	EpisodesCount        uint64
	WatchedEpisodesCount uint64
	Status               string
	State                StateType
	Pinned               bool
	CreatedAt            time.Time
	UpdatedAt            time.Time
}

// SeriesFilter narrows a user's series to the given TMDB ids
type SeriesFilter struct {
	UserId  uuid.UUID
	TmdbIds []uint64
}
