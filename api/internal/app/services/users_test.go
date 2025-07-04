package services

import (
	"context"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"go.uber.org/mock/gomock"

	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories"
	"biinge-api/internal/app/repositories/db"
	"biinge-api/internal/config"
	"biinge-api/internal/config/logger"
)

func Test_Users_Create(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	cfg := &config.Config{
		AppEnv:   "test",
		AppAddr:  "localhost:8080",
		LogLevel: "info",
	}
	repository := repositories.NewMockUserRepository(ctrl)
	log := logger.NewLogger(cfg)
	service := NewUsers(repository, log)

	id, err := uuid.NewRandom()
	assert.NoError(t, err)

	tests := []struct {
		name     string
		before   func()
		expected *models.User
		error    error
	}{
		{
			name: "Success",
			before: func() {
				repository.EXPECT().Create(ctx, db.CreateUserParams{
					Login:             "john.doe",
					Email:             "john.doe@local",
					EncryptedPassword: "SECRET",
					FirstName:         "John",
					LastName:          "Doe",
					Appearance:        "dark",
				}).Return(&models.User{
					ID:         id,
					Login:      "john.doe",
					Email:      "john.doe@local",
					FirstName:  "John",
					LastName:   "Doe",
					Appearance: "dark",
				}, nil)
			},
			expected: &models.User{
				ID:         id,
				Login:      "john.doe",
				Email:      "john.doe@local",
				FirstName:  "John",
				LastName:   "Doe",
				Appearance: "dark",
			},
		},
		{
			name: "Error",
			before: func() {
				repository.EXPECT().Create(ctx, db.CreateUserParams{
					Login:             "john.doe",
					Email:             "john.doe@local",
					EncryptedPassword: "SECRET",
					FirstName:         "John",
					LastName:          "Doe",
					Appearance:        "dark",
				}).Return(nil, assert.AnError)
			},
			expected: nil,
			error:    assert.AnError,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, err := service.Create(ctx, &models.User{
				Login:             "john.doe",
				Email:             "john.doe@local",
				EncryptedPassword: "SECRET",
				FirstName:         "John",
				LastName:          "Doe",
				Appearance:        "dark",
			})

			if tt.error != nil {
				assert.Error(t, err)
				assert.Nil(t, result)
			} else {
				assert.NoError(t, err)
				assert.Equal(t, tt.expected, result)
			}
		})
	}
}

func Test_Users_Update(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	cfg := &config.Config{
		AppEnv:   "test",
		AppAddr:  "localhost:8080",
		LogLevel: "info",
	}
	repository := repositories.NewMockUserRepository(ctrl)
	log := logger.NewLogger(cfg)
	service := NewUsers(repository, log)

	id, err := uuid.NewRandom()
	assert.NoError(t, err)

	tests := []struct {
		name     string
		before   func()
		params   *models.User
		expected *models.User
		error    error
	}{
		{
			name: "Success",
			before: func() {
				repository.EXPECT().Update(ctx, db.UpdateUserParams{
					ID:         id,
					FirstName:  "Jane",
					LastName:   "Doe",
					Appearance: "light",
				}).Return(&models.User{
					ID:         id,
					Login:      "john.doe",
					Email:      "john.doe@local",
					FirstName:  "Jane",
					LastName:   "Doe",
					Appearance: "light",
				}, nil)
			},
			params: &models.User{
				ID:         id,
				FirstName:  "Jane",
				LastName:   "Doe",
				Appearance: "light",
			},
			expected: &models.User{
				ID:         id,
				Login:      "john.doe",
				Email:      "john.doe@local",
				FirstName:  "Jane",
				LastName:   "Doe",
				Appearance: "light",
			},
		},
		{
			name: "Error",
			before: func() {
				repository.EXPECT().Update(ctx, db.UpdateUserParams{
					ID:         id,
					FirstName:  "Jane",
					LastName:   "Doe",
					Appearance: "light",
				}).Return(nil, assert.AnError)
			},
			params: &models.User{
				ID:         id,
				FirstName:  "Jane",
				LastName:   "Doe",
				Appearance: "light",
			},
			expected: nil,
			error:    assert.AnError,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, err := service.Update(ctx, tt.params)

			if tt.error != nil {
				assert.Error(t, err)
				assert.Nil(t, result)
			} else {
				assert.NoError(t, err)
				assert.Equal(t, tt.expected, result)
			}
		})
	}
}

func Test_Users_FindById(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	cfg := &config.Config{
		AppEnv:   "test",
		AppAddr:  "localhost:8080",
		LogLevel: "info",
	}
	repository := repositories.NewMockUserRepository(ctrl)
	log := logger.NewLogger(cfg)
	service := NewUsers(repository, log)

	id, err := uuid.NewRandom()
	assert.NoError(t, err)

	tests := []struct {
		name     string
		before   func()
		id       uuid.UUID
		expected *models.User
		error    error
	}{
		{
			name: "Success",
			before: func() {
				repository.EXPECT().FindById(ctx, id).Return(&models.User{
					ID:         id,
					Login:      "john.doe",
					Email:      "john.doe@local",
					FirstName:  "John",
					LastName:   "Doe",
					Appearance: "dark",
				}, nil)
			},
			id: id,
			expected: &models.User{
				ID:         id,
				Login:      "john.doe",
				Email:      "john.doe@local",
				FirstName:  "John",
				LastName:   "Doe",
				Appearance: "dark",
			},
		},
		{
			name: "Error",
			before: func() {
				repository.EXPECT().FindById(ctx, id).Return(nil, assert.AnError)
			},
			id:       id,
			expected: nil,
			error:    assert.AnError,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, err := service.FindById(ctx, tt.id)

			if tt.error != nil {
				assert.Error(t, err)
				assert.Nil(t, result)
			} else {
				assert.NoError(t, err)
				assert.Equal(t, tt.expected, result)
			}
		})
	}
}

func Test_Users_FindByLogin(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	cfg := &config.Config{
		AppEnv:   "test",
		AppAddr:  "localhost:8080",
		LogLevel: "info",
	}
	repository := repositories.NewMockUserRepository(ctrl)
	log := logger.NewLogger(cfg)
	service := NewUsers(repository, log)

	id, err := uuid.NewRandom()
	assert.NoError(t, err)

	tests := []struct {
		name     string
		before   func()
		login    string
		expected *models.User
		error    error
	}{
		{
			name: "Success",
			before: func() {
				repository.EXPECT().FindByLogin(ctx, "john.doe").Return(&models.User{
					ID:                id,
					Login:             "john.doe",
					Email:             "john.doe@local",
					EncryptedPassword: "hashed_password",
					FirstName:         "John",
					LastName:          "Doe",
					Appearance:        "dark",
				}, nil)
			},
			login: "john.doe",
			expected: &models.User{
				ID:                id,
				Login:             "john.doe",
				Email:             "john.doe@local",
				EncryptedPassword: "hashed_password",
				FirstName:         "John",
				LastName:          "Doe",
				Appearance:        "dark",
			},
		},
		{
			name: "Error",
			before: func() {
				repository.EXPECT().FindByLogin(ctx, "nonexistent").Return(nil, assert.AnError)
			},
			login:    "nonexistent",
			expected: nil,
			error:    assert.AnError,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, err := service.FindByLogin(ctx, tt.login)

			if tt.error != nil {
				assert.Error(t, err)
				assert.Nil(t, result)
			} else {
				assert.NoError(t, err)
				assert.Equal(t, tt.expected, result)
			}
		})
	}
}

func Test_Users_FindByEmail(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	cfg := &config.Config{
		AppEnv:   "test",
		AppAddr:  "localhost:8080",
		LogLevel: "info",
	}
	repository := repositories.NewMockUserRepository(ctrl)
	log := logger.NewLogger(cfg)
	service := NewUsers(repository, log)

	id, err := uuid.NewRandom()
	assert.NoError(t, err)

	tests := []struct {
		name     string
		before   func()
		email    string
		expected *models.User
		error    error
	}{
		{
			name: "Success",
			before: func() {
				repository.EXPECT().FindByEmail(ctx, "john.doe@local").Return(&models.User{
					ID:                id,
					Login:             "john.doe",
					Email:             "john.doe@local",
					EncryptedPassword: "hashed_password",
					FirstName:         "John",
					LastName:          "Doe",
					Appearance:        "dark",
				}, nil)
			},
			email: "john.doe@local",
			expected: &models.User{
				ID:                id,
				Login:             "john.doe",
				Email:             "john.doe@local",
				EncryptedPassword: "hashed_password",
				FirstName:         "John",
				LastName:          "Doe",
				Appearance:        "dark",
			},
		},
		{
			name: "Error",
			before: func() {
				repository.EXPECT().FindByEmail(ctx, "nonexistent@local").Return(nil, assert.AnError)
			},
			email:    "nonexistent@local",
			expected: nil,
			error:    assert.AnError,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, err := service.FindByEmail(ctx, tt.email)

			if tt.error != nil {
				assert.Error(t, err)
				assert.Nil(t, result)
			} else {
				assert.NoError(t, err)
				assert.Equal(t, tt.expected, result)
			}
		})
	}
}
