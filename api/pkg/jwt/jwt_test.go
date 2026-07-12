package jwt

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"

	"biinge-api/internal/config"
)

func newTestJwt() Jwt {
	return NewJWT(&config.Config{
		AppName:      "biinge-test",
		JWTSecretKey: "test-secret",
	})
}

func Test_Jwt_GenerateDecode_CarriesType(t *testing.T) {
	service := newTestJwt()

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
			token, err := service.Generate(Payload{
				ID:    "user-id",
				Email: "john.doe@example.com",
				Type:  tt.tokenType,
			}, time.Hour)
			assert.NoError(t, err)
			assert.NotEmpty(t, token)

			payload, err := service.Decode(token)
			assert.NoError(t, err)
			assert.Equal(t, "user-id", payload.ID)
			assert.Equal(t, "john.doe@example.com", payload.Email)
			assert.Equal(t, tt.tokenType, payload.Type)
		})
	}
}

func Test_Jwt_Decode_InvalidToken(t *testing.T) {
	service := newTestJwt()

	_, err := service.Decode("not-a-jwt")
	assert.Error(t, err)
}
