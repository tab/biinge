package errors

import "errors"

var (
	ErrEmptyLogin      = errors.New("empty login")
	ErrEmptyEmail      = errors.New("empty email")
	ErrEmptyPassword   = errors.New("empty password")
	ErrEmptyFirstName  = errors.New("empty first name")
	ErrEmptyLastName   = errors.New("empty last name")
	ErrEmptyAppearance = errors.New("empty appearance")

	ErrLoginAlreadyExists = errors.New("login already exists")
	ErrEmailAlreadyExists = errors.New("email already exists")

	ErrInvalidCredentials = errors.New("invalid credentials")
	ErrInvalidPassword    = errors.New("invalid password")

	ErrInvalidToken = errors.New("invalid token")

	ErrUserNotFound = errors.New("user not found")

	ErrUnauthorized = errors.New("unauthorized")
)
