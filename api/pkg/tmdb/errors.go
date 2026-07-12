package tmdb

import "fmt"

var (
	ErrAccessForbidden = fmt.Errorf("access forbidden")
	ErrNotFound        = fmt.Errorf("not found")

	ErrUnexpectedResponse = fmt.Errorf("unexpected response from TMDB API")

	ErrFailedToFetchMovieDetails   = fmt.Errorf("failed to fetch movie details")
	ErrFailedToFetchTvDetails      = fmt.Errorf("failed to fetch tv details")
	ErrFailedToFetchSeasonDetails  = fmt.Errorf("failed to fetch season details")
	ErrFailedToFetchEpisodeDetails = fmt.Errorf("failed to fetch episode details")
	ErrFailedToFetchPersonDetails  = fmt.Errorf("failed to fetch person details")
)
