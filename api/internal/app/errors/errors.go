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
	ErrEmptyPoster   = errors.New("empty poster")
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

	ErrFailedToFetchSeriesList = errors.New("failed to fetch series list")
	ErrFailedToFetchSeries     = errors.New("failed to fetch series")
	ErrFailedToCreateSeries    = errors.New("failed to create series")
	ErrFailedToUpdateSeries    = errors.New("failed to update series")
	ErrFailedToDeleteSeries    = errors.New("failed to delete series")

	ErrFailedToFetchSeasons = errors.New("failed to fetch seasons")
	ErrFailedToCreateSeason = errors.New("failed to create season")
	ErrFailedToUpdateSeason = errors.New("failed to update season")
	ErrFailedToDeleteSeason = errors.New("failed to delete season")

	ErrFailedToFetchEpisodes = errors.New("failed to fetch episodes")
	ErrFailedToFetchEpisode  = errors.New("failed to fetch episode")
	ErrFailedToCreateEpisode = errors.New("failed to create episode")
	ErrFailedToUpdateEpisode = errors.New("failed to update episode")
	ErrFailedToDeleteEpisode = errors.New("failed to delete episode")

	ErrFailedToUpdateProgress = errors.New("failed to update progress")
	ErrFailedToFetchProgress  = errors.New("failed to fetch progress")

	ErrFailedToFetchStats = errors.New("failed to fetch stats")

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
