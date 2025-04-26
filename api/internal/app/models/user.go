package models

import (
	"github.com/google/uuid"
)

const (
	DefaultAppearance = "system"
	LightAppearance   = "light"
	DarkAppearance    = "dark"
)

type User struct {
	ID                uuid.UUID
	Login             string
	Email             string
	EncryptedPassword string
	FirstName         string
	LastName          string
	Appearance        string
}
