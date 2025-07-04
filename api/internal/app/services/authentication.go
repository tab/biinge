package services

import (
	"context"
	"time"

	"golang.org/x/crypto/bcrypt"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/models"
	"biinge-api/internal/app/serializers"
	"biinge-api/internal/config/logger"
	"biinge-api/pkg/jwt"
)

const (
	BcryptHashCost = 14

	AccessTokenDuration  = 24 * time.Hour
	RefreshTokenDuration = 7 * 24 * time.Hour
)

type Authentication interface {
	Registration(ctx context.Context, request *serializers.RegistrationRequestSerializer) (*serializers.TokenSerializer, error)
	Login(ctx context.Context, request *serializers.LoginRequestSerializer) (*serializers.TokenSerializer, error)
}

type authentication struct {
	jwt   jwt.Jwt
	users Users
	log   *logger.Logger
}

func NewAuthentication(jwt jwt.Jwt, users Users, log *logger.Logger) Authentication {
	return &authentication{
		jwt:   jwt,
		users: users,
		log:   log.WithComponent("AuthenticationService"),
	}
}

func (a *authentication) Registration(ctx context.Context, params *serializers.RegistrationRequestSerializer) (*serializers.TokenSerializer, error) {
	existingUserByLogin, err := a.users.FindByLogin(ctx, params.Login)
	if err == nil && existingUserByLogin != nil {
		a.log.Warn().
			Str("login", params.Login).
			Msg("Registration attempted with existing login")
		return nil, errors.ErrLoginAlreadyExists
	}

	existingUserByEmail, err := a.users.FindByEmail(ctx, params.Email)
	if err == nil && existingUserByEmail != nil {
		a.log.Warn().
			Str("email", params.Email).
			Msg("Registration attempted with existing email")
		return nil, errors.ErrEmailAlreadyExists
	}

	appearance := params.Appearance
	if appearance == "" {
		appearance = models.DefaultAppearance
	}

	encryptedPassword, err := bcrypt.GenerateFromPassword([]byte(params.Password), BcryptHashCost)
	if err != nil {
		a.log.Error().
			Err(err).
			Msg("Failed to hash password")
		return nil, err
	}

	user, err := a.users.Create(ctx, &models.User{
		Login:             params.Login,
		Email:             params.Email,
		EncryptedPassword: string(encryptedPassword),
		FirstName:         params.FirstName,
		LastName:          params.LastName,
		Appearance:        appearance,
	})
	if err != nil {
		a.log.Error().
			Err(err).
			Str("login", params.Login).
			Str("email", params.Email).
			Msg("Failed to create user")
		return nil, err
	}

	accessToken, err := a.jwt.Generate(jwt.Payload{
		ID:    user.ID.String(),
		Email: user.Email,
	}, AccessTokenDuration)
	if err != nil {
		a.log.Error().Err(err).Msg("Failed to generate access token")
		return nil, jwt.ErrFailedGenerateAccessToken
	}

	refreshToken, err := a.jwt.Generate(jwt.Payload{
		ID:    user.ID.String(),
		Email: user.Email,
	}, RefreshTokenDuration)
	if err != nil {
		a.log.Error().Err(err).Msg("Failed to generate refresh token")
		return nil, jwt.ErrFailedGenerateRefreshToken
	}

	return &serializers.TokenSerializer{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
	}, nil
}

func (a *authentication) Login(ctx context.Context, params *serializers.LoginRequestSerializer) (*serializers.TokenSerializer, error) {
	user, err := a.users.FindByEmail(ctx, params.Email)
	if err != nil {
		a.log.Error().
			Err(err).
			Str("email", params.Email).
			Msg("Failed to find user by email")
		return nil, errors.ErrInvalidCredentials
	}

	err = bcrypt.CompareHashAndPassword([]byte(user.EncryptedPassword), []byte(params.Password))
	if err != nil {
		a.log.Error().
			Err(err).
			Str("email", params.Email).
			Msg("Password mismatch")
		return nil, errors.ErrInvalidPassword
	}

	accessToken, err := a.jwt.Generate(jwt.Payload{
		ID:    user.ID.String(),
		Email: user.Email,
	}, AccessTokenDuration)
	if err != nil {
		a.log.Error().Err(err).Msg("Failed to generate access token")
		return nil, jwt.ErrFailedGenerateAccessToken
	}

	refreshToken, err := a.jwt.Generate(jwt.Payload{
		ID:    user.ID.String(),
		Email: user.Email,
	}, RefreshTokenDuration)
	if err != nil {
		a.log.Error().Err(err).Msg("Failed to generate refresh token")
		return nil, jwt.ErrFailedGenerateRefreshToken
	}

	return &serializers.TokenSerializer{
		AccessToken:  accessToken,
		RefreshToken: refreshToken,
	}, nil
}
