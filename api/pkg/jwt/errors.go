package jwt

import "errors"

var (
	ErrInvalidSigningMethod = errors.New("invalid JWT signing method")
	ErrInvalidToken         = errors.New("invalid JWT token")
	ErrInvalidTokenType     = errors.New("invalid JWT token type")

	ErrFailedGenerateAccessToken  = errors.New("failed to generate access token")
	ErrFailedGenerateRefreshToken = errors.New("failed to generate refresh token")
)
