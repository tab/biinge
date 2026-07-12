package models

import (
	"time"

	"github.com/google/uuid"
)

type Episode struct {
	ID         uuid.UUID
	SeasonId   uuid.UUID
	TmdbId     uint64
	Title      string
	PosterPath string
	Runtime    uint64
	State      string
	AirAt      time.Time
	CreatedAt  time.Time
	UpdatedAt  time.Time
}
