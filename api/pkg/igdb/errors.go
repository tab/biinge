package igdb

import "errors"

var (
	ErrAccessForbidden = errors.New("access forbidden")
	ErrNotFound        = errors.New("not found")

	ErrUnexpectedResponse = errors.New("unexpected response from IGDB API")

	ErrFailedToFetchToken       = errors.New("failed to fetch IGDB access token")
	ErrFailedToFetchGameDetails = errors.New("failed to fetch game details")
)
