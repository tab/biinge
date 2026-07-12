package serializers

import "github.com/go-playground/validator/v10"

// validate is the process-wide, singleton validator used to enforce the
// `validate` struct tags declared on request serializers. It is safe for
// concurrent use and caches struct reflection metadata, so it is created once
// and shared by every Validate method.
var validate = validator.New(validator.WithRequiredStructEnabled())
