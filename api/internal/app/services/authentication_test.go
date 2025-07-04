package services

import (
	"context"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"go.uber.org/mock/gomock"
	"golang.org/x/crypto/bcrypt"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/models"
	"biinge-api/internal/app/serializers"
	"biinge-api/internal/config"
	"biinge-api/internal/config/logger"
	"biinge-api/pkg/jwt"
)

func Test_Authentication_Registration(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	cfg := &config.Config{
		AppEnv:   "test",
		AppAddr:  "localhost:8080",
		LogLevel: "info",
	}

	usersService := NewMockUsers(ctrl)
	jwtService := jwt.NewMockJwt(ctrl)
	log := logger.NewLogger(cfg)
	service := NewAuthentication(jwtService, usersService, log)

	id, err := uuid.NewRandom()
	assert.NoError(t, err)

	tests := []struct {
		name     string
		before   func()
		params   *serializers.RegistrationRequestSerializer
		expected *serializers.TokenSerializer
		error    error
	}{
		{
			name: "Success",
			before: func() {
				usersService.EXPECT().FindByLogin(ctx, "john.doe").Return(nil, errors.ErrUserNotFound)
				usersService.EXPECT().FindByEmail(ctx, "john.doe@local").Return(nil, errors.ErrUserNotFound)
				usersService.EXPECT().Create(ctx, gomock.Any()).Return(&models.User{
					ID:         id,
					Login:      "john.doe",
					Email:      "john.doe@local",
					FirstName:  "John",
					LastName:   "Doe",
					Appearance: "dark",
				}, nil)

				jwtService.EXPECT().Generate(jwt.Payload{
					ID:    id.String(),
					Email: "john.doe@local",
				}, AccessTokenDuration).Return("jwt-access-token", nil)
				jwtService.EXPECT().Generate(jwt.Payload{
					ID:    id.String(),
					Email: "john.doe@local",
				}, RefreshTokenDuration).Return("jwt-refresh-token", nil)
			},
			params: &serializers.RegistrationRequestSerializer{
				Login:      "john.doe",
				Email:      "john.doe@local",
				Password:   "password123",
				FirstName:  "John",
				LastName:   "Doe",
				Appearance: "dark",
			},
			expected: &serializers.TokenSerializer{
				AccessToken:  "jwt-access-token",
				RefreshToken: "jwt-refresh-token",
			},
		},
		{
			name: "Set Default Appearance",
			before: func() {
				usersService.EXPECT().FindByLogin(ctx, "john.doe").Return(nil, errors.ErrUserNotFound)
				usersService.EXPECT().FindByEmail(ctx, "john.doe@local").Return(nil, errors.ErrUserNotFound)
				usersService.EXPECT().Create(ctx, gomock.Any()).Return(&models.User{
					ID:        id,
					Login:     "john.doe",
					Email:     "john.doe@local",
					FirstName: "John",
					LastName:  "Doe",
				}, nil)

				jwtService.EXPECT().Generate(jwt.Payload{
					ID:    id.String(),
					Email: "john.doe@local",
				}, AccessTokenDuration).Return("jwt-access-token", nil)
				jwtService.EXPECT().Generate(jwt.Payload{
					ID:    id.String(),
					Email: "john.doe@local",
				}, RefreshTokenDuration).Return("jwt-refresh-token", nil)
			},
			params: &serializers.RegistrationRequestSerializer{
				Login:      "john.doe",
				Email:      "john.doe@local",
				Password:   "password123",
				FirstName:  "John",
				LastName:   "Doe",
				Appearance: models.DefaultAppearance,
			},
			expected: &serializers.TokenSerializer{
				AccessToken:  "jwt-access-token",
				RefreshToken: "jwt-refresh-token",
			},
		},
		{
			name: "Login Already Exists",
			before: func() {
				usersService.EXPECT().FindByLogin(ctx, "existing.user").Return(&models.User{
					ID:         id,
					Login:      "existing.user",
					Email:      "existing@local",
					FirstName:  "Existing",
					LastName:   "User",
					Appearance: "light",
				}, nil)
			},
			params: &serializers.RegistrationRequestSerializer{
				Login:      "existing.user",
				Email:      "new@local",
				Password:   "password123",
				FirstName:  "New",
				LastName:   "User",
				Appearance: "light",
			},
			expected: nil,
			error:    errors.ErrLoginAlreadyExists,
		},
		{
			name: "Email Already Exists",
			before: func() {
				usersService.EXPECT().FindByLogin(ctx, "new.user").Return(nil, errors.ErrUserNotFound)
				usersService.EXPECT().FindByEmail(ctx, "existing@local").Return(&models.User{
					ID:         id,
					Login:      "existing.user",
					Email:      "existing@local",
					FirstName:  "Existing",
					LastName:   "User",
					Appearance: "light",
				}, nil)
			},
			params: &serializers.RegistrationRequestSerializer{
				Login:      "new.user",
				Email:      "existing@local",
				Password:   "password123",
				FirstName:  "New",
				LastName:   "User",
				Appearance: "light",
			},
			expected: nil,
			error:    errors.ErrEmailAlreadyExists,
		},
		{
			name: "Error creating user",
			before: func() {
				usersService.EXPECT().FindByLogin(ctx, "john.doe").Return(nil, errors.ErrUserNotFound)
				usersService.EXPECT().FindByEmail(ctx, "john.doe@local").Return(nil, errors.ErrUserNotFound)
				usersService.EXPECT().Create(ctx, gomock.Any()).Return(nil, assert.AnError)
			},
			params: &serializers.RegistrationRequestSerializer{
				Login:      "john.doe",
				Email:      "john.doe@local",
				Password:   "password123",
				FirstName:  "John",
				LastName:   "Doe",
				Appearance: "dark",
			},
			expected: nil,
			error:    assert.AnError,
		},
		{
			name: "Error generating JWT access token",
			before: func() {
				usersService.EXPECT().FindByLogin(ctx, "john.doe").Return(nil, errors.ErrUserNotFound)
				usersService.EXPECT().FindByEmail(ctx, "john.doe@local").Return(nil, errors.ErrUserNotFound)
				usersService.EXPECT().Create(ctx, gomock.Any()).Return(&models.User{
					ID:         id,
					Login:      "john.doe",
					Email:      "john.doe@local",
					FirstName:  "John",
					LastName:   "Doe",
					Appearance: "dark",
				}, nil)

				jwtService.EXPECT().Generate(gomock.Any(), AccessTokenDuration).Return("", jwt.ErrFailedGenerateAccessToken)
			},
			params: &serializers.RegistrationRequestSerializer{
				Login:      "john.doe",
				Email:      "john.doe@local",
				Password:   "password123",
				FirstName:  "John",
				LastName:   "Doe",
				Appearance: "dark",
			},
			expected: nil,
			error:    jwt.ErrFailedGenerateAccessToken,
		},
		{
			name: "Error generating JWT refresh token",
			before: func() {
				usersService.EXPECT().FindByLogin(ctx, "john.doe").Return(nil, errors.ErrUserNotFound)
				usersService.EXPECT().FindByEmail(ctx, "john.doe@local").Return(nil, errors.ErrUserNotFound)
				usersService.EXPECT().Create(ctx, gomock.Any()).Return(&models.User{
					ID:         id,
					Login:      "john.doe",
					Email:      "john.doe@local",
					FirstName:  "John",
					LastName:   "Doe",
					Appearance: "dark",
				}, nil)

				jwtService.EXPECT().Generate(gomock.Any(), AccessTokenDuration).Return("jwt-access-token", nil)
				jwtService.EXPECT().Generate(gomock.Any(), RefreshTokenDuration).Return("", jwt.ErrFailedGenerateRefreshToken)
			},
			params: &serializers.RegistrationRequestSerializer{
				Login:      "john.doe",
				Email:      "john.doe@local",
				Password:   "password123",
				FirstName:  "John",
				LastName:   "Doe",
				Appearance: "dark",
			},
			expected: nil,
			error:    jwt.ErrFailedGenerateRefreshToken,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, err := service.Registration(ctx, tt.params)

			if tt.error != nil {
				assert.Error(t, err)
				assert.Equal(t, tt.error.Error(), err.Error())
				assert.Nil(t, result)
			} else {
				assert.NoError(t, err)
				assert.Equal(t, tt.expected, result)
			}
		})
	}
}

func Test_Authentication_Login(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	cfg := &config.Config{
		AppEnv:   "test",
		AppAddr:  "localhost:8080",
		LogLevel: "info",
	}

	usersService := NewMockUsers(ctrl)
	jwtService := jwt.NewMockJwt(ctrl)
	log := logger.NewLogger(cfg)
	service := NewAuthentication(jwtService, usersService, log)

	id, err := uuid.NewRandom()
	assert.NoError(t, err)

	hashedPassword, err := bcrypt.GenerateFromPassword([]byte("password123"), BcryptHashCost)
	assert.NoError(t, err)

	tests := []struct {
		name     string
		before   func()
		params   *serializers.LoginRequestSerializer
		expected *serializers.TokenSerializer
		error    error
	}{
		{
			name: "Success",
			before: func() {
				usersService.EXPECT().FindByEmail(ctx, "john.doe@local").Return(&models.User{
					ID:                id,
					Login:             "john.doe",
					Email:             "john.doe@local",
					EncryptedPassword: string(hashedPassword),
					FirstName:         "John",
					LastName:          "Doe",
					Appearance:        "dark",
				}, nil)

				jwtService.EXPECT().Generate(jwt.Payload{
					ID:    id.String(),
					Email: "john.doe@local",
				}, AccessTokenDuration).Return("jwt-access-token", nil)
				jwtService.EXPECT().Generate(jwt.Payload{
					ID:    id.String(),
					Email: "john.doe@local",
				}, RefreshTokenDuration).Return("jwt-refresh-token", nil)
			},
			params: &serializers.LoginRequestSerializer{
				Email:    "john.doe@local",
				Password: "password123",
			},
			expected: &serializers.TokenSerializer{
				AccessToken:  "jwt-access-token",
				RefreshToken: "jwt-refresh-token",
			},
		},
		{
			name: "Error – User Not Found",
			before: func() {
				usersService.EXPECT().FindByEmail(ctx, "nonexistent@local").Return(nil, errors.ErrUserNotFound)
			},
			params: &serializers.LoginRequestSerializer{
				Email:    "nonexistent@local",
				Password: "password123",
			},
			expected: nil,
			error:    errors.ErrInvalidCredentials,
		},
		{
			name: "Error – Invalid Password",
			before: func() {
				usersService.EXPECT().FindByEmail(ctx, "john.doe@local").Return(&models.User{
					ID:                id,
					Login:             "john.doe",
					Email:             "john.doe@local",
					EncryptedPassword: string(hashedPassword),
					FirstName:         "John",
					LastName:          "Doe",
					Appearance:        "dark",
				}, nil)
			},
			params: &serializers.LoginRequestSerializer{
				Email:    "john.doe@local",
				Password: "invalid-password",
			},
			expected: nil,
			error:    errors.ErrInvalidPassword,
		},
		{
			name: "Error generating JWT access token",
			before: func() {
				usersService.EXPECT().FindByEmail(ctx, "john.doe@local").Return(&models.User{
					ID:                id,
					Login:             "john.doe",
					Email:             "john.doe@local",
					EncryptedPassword: string(hashedPassword),
					FirstName:         "John",
					LastName:          "Doe",
					Appearance:        "dark",
				}, nil)

				jwtService.EXPECT().Generate(jwt.Payload{
					ID:    id.String(),
					Email: "john.doe@local",
				}, AccessTokenDuration).Return("", jwt.ErrFailedGenerateAccessToken)
			},
			params: &serializers.LoginRequestSerializer{
				Email:    "john.doe@local",
				Password: "password123",
			},
			expected: nil,
			error:    jwt.ErrFailedGenerateAccessToken,
		},
		{
			name: "Error generating JWT refresh token",
			before: func() {
				usersService.EXPECT().FindByEmail(ctx, "john.doe@local").Return(&models.User{
					ID:                id,
					Login:             "john.doe",
					Email:             "john.doe@local",
					EncryptedPassword: string(hashedPassword),
					FirstName:         "John",
					LastName:          "Doe",
					Appearance:        "dark",
				}, nil)

				jwtService.EXPECT().Generate(jwt.Payload{
					ID:    id.String(),
					Email: "john.doe@local",
				}, AccessTokenDuration).Return("jwt-access-token", nil)
				jwtService.EXPECT().Generate(jwt.Payload{
					ID:    id.String(),
					Email: "john.doe@local",
				}, RefreshTokenDuration).Return("", jwt.ErrFailedGenerateRefreshToken)
			},
			params: &serializers.LoginRequestSerializer{
				Email:    "john.doe@local",
				Password: "password123",
			},
			expected: nil,
			error:    jwt.ErrFailedGenerateRefreshToken,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, err := service.Login(ctx, tt.params)

			if tt.error != nil {
				assert.Error(t, err)
				assert.Equal(t, tt.error.Error(), err.Error())
				assert.Nil(t, result)
			} else {
				assert.NoError(t, err)
				assert.Equal(t, tt.expected, result)
			}
		})
	}
}
