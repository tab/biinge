package tmdb

import "errors"

var (
	ErrAccessForbidden = errors.New("access forbidden")
	ErrNotFound        = errors.New("not found")

	ErrUnexpectedResponse = errors.New("unexpected response from TMDB API")

	ErrFailedToFetchMovieDetails   = errors.New("failed to fetch movie details")
	ErrFailedToFetchTvDetails      = errors.New("failed to fetch tv details")
	ErrFailedToFetchSeasonDetails  = errors.New("failed to fetch season details")
	ErrFailedToFetchEpisodeDetails = errors.New("failed to fetch episode details")
	ErrFailedToFetchPersonDetails  = errors.New("failed to fetch person details")
)
