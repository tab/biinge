package models

import (
	"time"

	"github.com/google/uuid"
)

type Season struct {
	ID            uuid.UUID
	SeriesId      uuid.UUID
	TmdbId        uint64
	Title         string
	Number        uint64
	EpisodesCount uint64
	State         string
	CreatedAt     time.Time
	UpdatedAt     time.Time
}
