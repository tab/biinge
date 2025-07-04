package serializers

import (
	"encoding/json"
	"io"
	"strings"

	"biinge-api/internal/app/errors"
)

type RegistrationRequestSerializer struct {
	Login      string `json:"login" validate:"required,min=3,max=20"`
	Email      string `json:"email" validate:"required,email"`
	Password   string `json:"password" validate:"required,min=8"`
	FirstName  string `json:"first_name" validate:"required,min=2,max=20"`
	LastName   string `json:"last_name" validate:"required,min=2,max=20"`
	Appearance string `json:"appearance" validate:"omitempty,oneof=light dark system"`
}

type LoginRequestSerializer struct {
	Email    string `json:"email" validate:"required,email"`
	Password string `json:"password" validate:"required,min=8"`
}

func (params *RegistrationRequestSerializer) Validate(body io.Reader) error {
	if err := json.NewDecoder(body).Decode(params); err != nil {
		return err
	}

	params.Login = strings.TrimSpace(params.Login)
	params.Email = strings.TrimSpace(params.Email)
	params.Password = strings.TrimSpace(params.Password)
	params.FirstName = strings.TrimSpace(params.FirstName)
	params.LastName = strings.TrimSpace(params.LastName)
	params.Appearance = strings.TrimSpace(params.Appearance)

	if params.Login == "" {
		return errors.ErrEmptyLogin
	}

	if params.Email == "" {
		return errors.ErrEmptyEmail
	}

	if params.Password == "" {
		return errors.ErrEmptyPassword
	}

	return nil
}

func (params *LoginRequestSerializer) Validate(body io.Reader) error {
	if err := json.NewDecoder(body).Decode(params); err != nil {
		return err
	}

	params.Email = strings.TrimSpace(params.Email)
	params.Password = strings.TrimSpace(params.Password)

	if params.Email == "" {
		return errors.ErrEmptyEmail
	}

	if params.Password == "" {
		return errors.ErrEmptyPassword
	}

	return nil
}
