package jellyfin

import "errors"

var (
	ErrInvalidCredentials = errors.New("jellyfin rejected the credentials")
	ErrUnavailable        = errors.New("jellyfin is unavailable")
)
