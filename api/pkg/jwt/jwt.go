package jwt

import (
	"time"

	"github.com/golang-jwt/jwt/v5"

	"biinge-api/internal/config"
)

type Jwt interface {
	Generate(payload Payload, duration time.Duration) (string, error)
	Verify(token string) (bool, error)
	Decode(token string) (*Payload, error)
}

type jwtService struct {
	cfg *config.Config
}

type Payload struct {
	ID    string `json:"id"`
	Email string `json:"email"`
}

type Claims struct {
	jwt.RegisteredClaims
	Payload Payload `json:"payload"`
}

func NewJWT(cfg *config.Config) Jwt {
	return &jwtService{cfg: cfg}
}

func (j *jwtService) Generate(payload Payload, duration time.Duration) (string, error) {
	claims := Claims{
		RegisteredClaims: jwt.RegisteredClaims{
			ID:        payload.ID,
			Issuer:    j.cfg.AppName,
			Subject:   payload.Email,
			Audience:  jwt.ClaimStrings{j.cfg.AppName},
			ExpiresAt: jwt.NewNumericDate(time.Now().Add(duration)),
			IssuedAt:  jwt.NewNumericDate(time.Now()),
			NotBefore: jwt.NewNumericDate(time.Now()),
		},
		Payload: payload,
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)

	signedToken, err := token.SignedString([]byte(j.cfg.JWTSecretKey))
	if err != nil {
		return "", err
	}

	return signedToken, nil
}

func (j *jwtService) Verify(token string) (bool, error) {
	claims := &Claims{}

	result, err := jwt.ParseWithClaims(token, claims,
		func(t *jwt.Token) (interface{}, error) {
			if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
				return false, ErrInvalidSigningMethod
			}
			return []byte(j.cfg.JWTSecretKey), nil
		})

	if err != nil {
		return false, err
	}

	if !result.Valid {
		return false, ErrInvalidToken
	}

	return true, nil
}

func (j *jwtService) Decode(token string) (*Payload, error) {
	claims := &Claims{}

	result, err := jwt.ParseWithClaims(token, claims,
		func(t *jwt.Token) (interface{}, error) {
			if _, ok := t.Method.(*jwt.SigningMethodHMAC); !ok {
				return false, ErrInvalidSigningMethod
			}
			return []byte(j.cfg.JWTSecretKey), nil
		})

	if err != nil {
		return nil, err
	}

	if !result.Valid {
		return nil, ErrInvalidToken
	}

	return &Payload{
		ID:    claims.ID,
		Email: claims.Subject,
	}, nil
}
