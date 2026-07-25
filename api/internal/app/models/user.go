package models

import (
	"github.com/google/uuid"
)

// Appearance is a user's preferred interface theme
type Appearance string

const (
	DefaultAppearance Appearance = "system"
	LightAppearance   Appearance = "light"
	DarkAppearance    Appearance = "dark"
)

// String returns the appearance's wire value
func (a Appearance) String() string {
	return string(a)
}

type User struct {
	ID                uuid.UUID
	Login             string
	Email             string
	EncryptedPassword string
	FirstName         string
	LastName          string
	Appearance        Appearance
}
