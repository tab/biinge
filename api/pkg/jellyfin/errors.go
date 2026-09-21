package jellyfin

import "errors"

var ErrNotAnObject = errors.New("payload must be a JSON object")
