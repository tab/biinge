package jellyfin

import "errors"

var (
	ErrNotAnObject = errors.New("payload must be a JSON object")

	ErrInvalidCredentials = errors.New("jellyfin rejected the credentials")
	ErrUnavailable        = errors.New("jellyfin is unavailable")
)
