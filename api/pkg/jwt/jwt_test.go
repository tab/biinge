package jwt

import (
	"encoding/base64"
	"testing"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"biinge-api/internal/config"
)

func newTestConfig() *config.Config {
	return &config.Config{
		AppName:      "biinge-test",
		JWTSecretKey: "test-secret",
	}
}

func newTestJwt() Jwt {
	return NewJWT(newTestConfig())
}

// b64url encodes a raw string the same way the JWT spec encodes each segment
// (unpadded, URL-safe base64), so hand-crafted tokens below decode the same
// way a real token would.
func b64url(s string) string {
	return base64.RawURLEncoding.EncodeToString([]byte(s))
}

func Test_Jwt_Generate_Decode(t *testing.T) {
	cfg := newTestConfig()
	service := NewJWT(cfg)

	tests := []struct {
		name      string
		tokenType string
	}{
		{name: "access", tokenType: TokenTypeAccess},
		{name: "refresh", tokenType: TokenTypeRefresh},
		{name: "legacy (empty)", tokenType: ""},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			before := time.Now()

			token, err := service.Generate(Payload{
				ID:    "user-id",
				Email: "john.doe@example.com",
				Type:  tt.tokenType,
			}, time.Hour)
			require.NoError(t, err)
			assert.NotEmpty(t, token)

			payload, err := service.Decode(token)
			require.NoError(t, err)
			assert.Equal(t, "user-id", payload.ID)
			assert.Equal(t, "john.doe@example.com", payload.Email)
			assert.Equal(t, tt.tokenType, payload.Type)

			var claims Claims

			_, err = jwt.ParseWithClaims(token, &claims, func(*jwt.Token) (any, error) {
				return []byte(cfg.JWTSecretKey), nil
			})
			require.NoError(t, err)
			assert.Equal(t, cfg.AppName, claims.Issuer)
			assert.Equal(t, "john.doe@example.com", claims.Subject)
			assert.Equal(t, jwt.ClaimStrings{cfg.AppName}, claims.Audience)
			assert.WithinDuration(t, before.Add(time.Hour), claims.ExpiresAt.Time, 5*time.Second)
			assert.WithinDuration(t, before, claims.IssuedAt.Time, 5*time.Second)
			assert.WithinDuration(t, before, claims.NotBefore.Time, 5*time.Second)
		})
	}
}

func Test_Jwt_Decode_Errors(t *testing.T) {
	service := newTestJwt()

	tests := []struct {
		name        string
		token       func(t *testing.T) string
		decoder     func() Jwt
		expectedErr error
	}{
		{
			name: "malformed - not a JWT",
			token: func(*testing.T) string {
				return "not-a-jwt"
			},
			expectedErr: jwt.ErrTokenMalformed,
		},
		{
			name: "malformed - missing segment",
			token: func(*testing.T) string {
				return "only.two"
			},
			expectedErr: jwt.ErrTokenMalformed,
		},
		{
			name: "malformed - too many segments",
			token: func(*testing.T) string {
				return "a.b.c.d"
			},
			expectedErr: jwt.ErrTokenMalformed,
		},
		{
			name: "wrong claims type",
			token: func(*testing.T) string {
				header := b64url(`{"alg":"HS256","typ":"JWT"}`)
				claims := b64url(`{"payload":{"id":12345,"email":"john.doe@example.com"}}`)

				return header + "." + claims + "." + b64url("signature")
			},
			expectedErr: jwt.ErrTokenMalformed,
		},
		{
			name: "wrong signing method",
			token: func(t *testing.T) string {
				unsignedToken := jwt.NewWithClaims(jwt.SigningMethodNone, jwt.MapClaims{
					"payload": Payload{ID: "user-id", Email: "john.doe@example.com"},
				})

				tokenString, err := unsignedToken.SignedString(jwt.UnsafeAllowNoneSignatureType)
				require.NoError(t, err)

				return tokenString
			},
			expectedErr: ErrInvalidSigningMethod,
		},
		{
			name: "wrong secret",
			token: func(t *testing.T) string {
				tokenString, err := service.Generate(Payload{ID: "user-id", Email: "john.doe@example.com"}, time.Hour)
				require.NoError(t, err)

				return tokenString
			},
			decoder: func() Jwt {
				return NewJWT(&config.Config{AppName: "biinge-test", JWTSecretKey: "different-secret"})
			},
			expectedErr: jwt.ErrTokenSignatureInvalid,
		},
		{
			name: "expired token",
			token: func(t *testing.T) string {
				tokenString, err := service.Generate(Payload{ID: "user-id", Email: "john.doe@example.com"}, -time.Hour)
				require.NoError(t, err)

				return tokenString
			},
			expectedErr: jwt.ErrTokenExpired,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			decoder := service
			if tt.decoder != nil {
				decoder = tt.decoder()
			}

			payload, err := decoder.Decode(tt.token(t))

			require.ErrorIs(t, err, tt.expectedErr)
			assert.Nil(t, payload)
		})
	}
}
