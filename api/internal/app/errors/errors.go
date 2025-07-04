package errors

import "errors"

var (
	ErrEmptyLogin      = errors.New("empty login")
	ErrEmptyEmail      = errors.New("empty email")
	ErrEmptyPassword   = errors.New("empty password")
	ErrEmptyFirstName  = errors.New("empty first name")
	ErrEmptyLastName   = errors.New("empty last name")
	ErrEmptyAppearance = errors.New("empty appearance")

	ErrEmptyTitle   = errors.New("empty title")
	ErrEmptyPoster  = errors.New("empty poster")
	ErrEmptyState   = errors.New("empty state")
	ErrInvalidState = errors.New("invalid state")

	ErrLoginAlreadyExists = errors.New("login already exists")
	ErrEmailAlreadyExists = errors.New("email already exists")

	ErrInvalidCredentials = errors.New("invalid credentials")
	ErrInvalidPassword    = errors.New("invalid password")

	ErrInvalidToken = errors.New("invalid token")

	ErrUserNotFound = errors.New("user not found")

	ErrUnauthorized = errors.New("unauthorized")

	ErrFailedToFetchResults = errors.New("failed to fetch results")
	ErrFailedToFetchMovies  = errors.New("failed to fetch movies")
	ErrFailedToFetchMovie   = errors.New("failed to fetch movie")
	ErrFailedToCreateMovie  = errors.New("failed to create movie")
	ErrFailedToUpdateMovie  = errors.New("failed to update movie")
	ErrFailedToDeleteMovie  = errors.New("failed to delete movie")

	ErrMovieNotFound   = errors.New("movie not found")
	ErrSeriesNotFound  = errors.New("series not found")
	ErrSeasonNotFound  = errors.New("season not found")
	ErrEpisodeNotFound = errors.New("episode not found")
)

var (
	Is     = errors.Is
	As     = errors.As
	Unwrap = errors.Unwrap
)
