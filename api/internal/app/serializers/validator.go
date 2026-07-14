package serializers

import "github.com/go-playground/validator/v10"

// validate is the process-wide validator enforcing the request serializers' validate tags
var validate = validator.New(validator.WithRequiredStructEnabled())
