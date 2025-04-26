package serializers

import (
	"encoding/json"
	"io"
	"strings"

	"github.com/google/uuid"

	"biinge-api/internal/app/errors"
)

type UserSerializer struct {
	ID         uuid.UUID `json:"id"`
	Login      string    `json:"login"`
	Email      string    `json:"email"`
	FirstName  string    `json:"first_name,omitempty"`
	LastName   string    `json:"last_name,omitempty"`
	Appearance string    `json:"appearance"`
}

type UpdateAccountRequestSerializer struct {
	FirstName  string `json:"first_name" validate:"omitempty,min=2,max=20"`
	LastName   string `json:"last_name" validate:"omitempty,min=2,max=20"`
	Appearance string `json:"appearance" validate:"omitempty,oneof=light dark system"`
}

func (params *UpdateAccountRequestSerializer) Validate(body io.Reader) error {
	if err := json.NewDecoder(body).Decode(params); err != nil {
		return err
	}

	params.FirstName = strings.TrimSpace(params.FirstName)
	params.LastName = strings.TrimSpace(params.LastName)
	params.Appearance = strings.TrimSpace(params.Appearance)

	if params.FirstName == "" {
		return errors.ErrEmptyFirstName
	}

	if params.LastName == "" {
		return errors.ErrEmptyLastName
	}

	if params.Appearance == "" {
		return errors.ErrEmptyAppearance
	}

	return nil
}
