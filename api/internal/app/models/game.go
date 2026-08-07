package models

import (
	"time"

	"github.com/google/uuid"
)

type Game struct {
	ID         uuid.UUID
	UserId     uuid.UUID
	IgdbId     uint64
	Title      string
	PosterPath string
	Runtime    uint64
	State      StateType
	Pinned     bool
	PlayedAt   time.Time
	CreatedAt  time.Time
	UpdatedAt  time.Time
}
