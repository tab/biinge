package errors

import "errors"

var (
	ErrEmptyLogin      = errors.New("empty login")
	ErrEmptyEmail      = errors.New("empty email")
	ErrEmptyPassword   = errors.New("empty password")
	ErrEmptyFirstName  = errors.New("empty first name")
	ErrEmptyLastName   = errors.New("empty last name")
	ErrEmptyAppearance = errors.New("empty appearance")

	ErrEmptyTitle    = errors.New("empty title")
	ErrEmptyState    = errors.New("empty state")
	ErrInvalidState  = errors.New("invalid state")
	ErrInvalidTmdbId = errors.New("invalid tmdb id")
	ErrEmptyQuery    = errors.New("empty query")

	ErrLoginAlreadyExists = errors.New("login already exists")
	ErrEmailAlreadyExists = errors.New("email already exists")

	ErrInvalidCredentials = errors.New("invalid credentials")
	ErrInvalidPassword    = errors.New("invalid password")

	ErrInvalidToken = errors.New("invalid token")

	ErrUserNotFound = errors.New("user not found")

	ErrFailedToProcessUser = errors.New("failed to process user")

	ErrUnauthorized = errors.New("unauthorized")

	ErrFailedToFetchResults = errors.New("failed to fetch results")
	ErrFailedToFetchMovies  = errors.New("failed to fetch movies")
	ErrFailedToFetchMovie   = errors.New("failed to fetch movie")
	ErrFailedToCreateMovie  = errors.New("failed to create movie")
	ErrFailedToUpdateMovie  = errors.New("failed to update movie")
	ErrFailedToDeleteMovie  = errors.New("failed to delete movie")

	ErrFailedToFetchGames = errors.New("failed to fetch games")
	ErrFailedToFetchGame  = errors.New("failed to fetch game")
	ErrFailedToCreateGame = errors.New("failed to create game")
	ErrFailedToUpdateGame = errors.New("failed to update game")
	ErrFailedToDeleteGame = errors.New("failed to delete game")

	ErrFailedToFetchSeriesList = errors.New("failed to fetch series list")
	ErrFailedToFetchSeries     = errors.New("failed to fetch series")
	ErrFailedToCreateSeries    = errors.New("failed to create series")
	ErrFailedToUpdateSeries    = errors.New("failed to update series")
	ErrFailedToDeleteSeries    = errors.New("failed to delete series")

	ErrFailedToUpdateProgress = errors.New("failed to update progress")
	ErrFailedToFetchProgress  = errors.New("failed to fetch progress")

	ErrFailedToFetchStats = errors.New("failed to fetch stats")
)

var (
	Is     = errors.Is
	As     = errors.As
	Unwrap = errors.Unwrap
)
