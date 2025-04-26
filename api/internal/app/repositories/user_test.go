package repositories

import (
	"context"
	"os"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"

	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories/db"
	"biinge-api/internal/app/repositories/postgres"
	"biinge-api/internal/config"
)

func Test_UserRepository_Create(t *testing.T) {
	ctx := context.Background()
	cfg := &config.Config{
		DatabaseDSN: os.Getenv("DATABASE_DSN"),
	}

	client, err := postgres.NewPostgresClient(cfg)
	assert.NoError(t, err)

	repository := NewUserRepository(client)

	tests := []struct {
		name     string
		before   func()
		params   db.CreateUserParams
		expected *models.User
		error    bool
	}{
		{
			name:   "Success",
			before: func() {},
			params: db.CreateUserParams{
				Login:             "john.doe",
				Email:             "john.doe@local",
				EncryptedPassword: "SECRET",
				FirstName:         "John",
				LastName:          "Doe",
				Appearance:        "dark",
			},
			expected: &models.User{
				Login:             "john.doe",
				Email:             "john.doe@local",
				EncryptedPassword: "SECRET",
				FirstName:         "John",
				LastName:          "Doe",
				Appearance:        "dark",
			},
			error: false,
		},
		{
			name:   "Invalid login",
			before: func() {},
			params: db.CreateUserParams{
				Login:             "",
				Email:             "john.doe@local",
				EncryptedPassword: "SECRET",
				FirstName:         "John",
				LastName:          "Doe",
				Appearance:        "dark",
			},
			expected: nil,
			error:    true,
		},
		{
			name:   "Invalid email",
			before: func() {},
			params: db.CreateUserParams{
				Login:             "john.doe",
				Email:             "",
				EncryptedPassword: "SECRET",
				FirstName:         "John",
				LastName:          "Doe",
				Appearance:        "dark",
			},
			expected: nil,
			error:    true,
		},
		{
			name:   "Invalid password",
			before: func() {},
			params: db.CreateUserParams{
				Login:             "john.doe",
				Email:             "john.doe@local",
				EncryptedPassword: "",
				FirstName:         "John",
				LastName:          "Doe",
				Appearance:        "dark",
			},
			expected: nil,
			error:    true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, err := repository.Create(ctx, tt.params)

			if tt.error {
				assert.Error(t, err)
			} else {
				assert.NoError(t, err)

				assert.NotEqual(t, uuid.Nil, result.ID)
				assert.Equal(t, tt.expected.Login, result.Login)
				assert.Equal(t, tt.expected.Email, result.Email)
				assert.Equal(t, tt.expected.FirstName, result.FirstName)
				assert.Equal(t, tt.expected.LastName, result.LastName)
				assert.Equal(t, tt.expected.Appearance, result.Appearance)
			}
		})
	}
}

func Test_UserRepository_Update(t *testing.T) {
	ctx := context.Background()
	cfg := &config.Config{
		DatabaseDSN: os.Getenv("DATABASE_DSN"),
	}

	client, err := postgres.NewPostgresClient(cfg)
	assert.NoError(t, err)

	repository := NewUserRepository(client)

	account, err := repository.Create(ctx, db.CreateUserParams{
		Login:             "jane.doe",
		Email:             "jane.doe@local",
		EncryptedPassword: "SECRET",
		FirstName:         "Jane",
		LastName:          "Doe",
		Appearance:        "dark",
	})
	assert.NoError(t, err)

	tests := []struct {
		name     string
		before   func()
		params   db.UpdateUserParams
		expected *models.User
		error    bool
	}{
		{
			name:   "Success",
			before: func() {},
			params: db.UpdateUserParams{
				ID:         account.ID,
				FirstName:  "Jane",
				LastName:   "Doe",
				Appearance: "light",
			},
			expected: &models.User{
				ID:         account.ID,
				Login:      "jane.doe",
				Email:      "jane.doe@local",
				FirstName:  "Jane",
				LastName:   "Doe",
				Appearance: "light",
			},
			error: false,
		},
		{
			name:   "User not found",
			before: func() {},
			params: db.UpdateUserParams{
				ID:         uuid.MustParse("00000000-0000-0000-0000-000000000002"),
				FirstName:  "Jane",
				LastName:   "Doe",
				Appearance: "light",
			},
			expected: nil,
			error:    true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, err := repository.Update(ctx, tt.params)

			if tt.error {
				assert.Error(t, err)
			} else {
				assert.NoError(t, err)

				assert.Equal(t, tt.expected.ID, result.ID)
				assert.Equal(t, tt.expected.Login, result.Login)
				assert.Equal(t, tt.expected.Email, result.Email)
				assert.Equal(t, tt.expected.FirstName, result.FirstName)
				assert.Equal(t, tt.expected.LastName, result.LastName)
				assert.Equal(t, tt.expected.Appearance, result.Appearance)
			}
		})
	}
}

func Test_UserRepository_FindById(t *testing.T) {
	ctx := context.Background()
	cfg := &config.Config{
		DatabaseDSN: os.Getenv("DATABASE_DSN"),
	}

	client, err := postgres.NewPostgresClient(cfg)
	assert.NoError(t, err)

	repository := NewUserRepository(client)

	account, err := repository.Create(ctx, db.CreateUserParams{
		Login:     "ann.doe",
		Email:     "ann.doe@local",
		FirstName: "Ann",
		LastName:  "Doe",
	})
	assert.NoError(t, err)

	tests := []struct {
		name     string
		id       uuid.UUID
		expected *models.User
		error    bool
	}{
		{
			name: "Success",
			id:   account.ID,
			expected: &models.User{
				ID:        account.ID,
				Login:     "ann.doe",
				Email:     "ann.doe@local",
				FirstName: "Ann",
				LastName:  "Doe",
			},
			error: false,
		},
		{
			name:     "User not found",
			id:       uuid.MustParse("00000000-0000-0000-0000-000000000002"),
			expected: nil,
			error:    true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, err := repository.FindById(ctx, tt.id)

			if tt.error {
				assert.Error(t, err)
			} else {
				assert.NoError(t, err)

				assert.Equal(t, tt.expected.ID, result.ID)
				assert.Equal(t, tt.expected.Login, result.Login)
				assert.Equal(t, tt.expected.Email, result.Email)
				assert.Equal(t, tt.expected.FirstName, result.FirstName)
				assert.Equal(t, tt.expected.LastName, result.LastName)
				assert.Equal(t, tt.expected.Appearance, result.Appearance)
			}
		})
	}
}

func Test_UserRepository_FindByLogin(t *testing.T) {
	ctx := context.Background()
	cfg := &config.Config{
		DatabaseDSN: os.Getenv("DATABASE_DSN"),
	}

	client, err := postgres.NewPostgresClient(cfg)
	assert.NoError(t, err)

	repository := NewUserRepository(client)

	account, err := repository.Create(ctx, db.CreateUserParams{
		Login:     "alice.doe",
		Email:     "alice.doe@local",
		FirstName: "Alice",
		LastName:  "Doe",
	})
	assert.NoError(t, err)

	tests := []struct {
		name     string
		login    string
		expected *models.User
		error    bool
	}{
		{
			name:  "Success",
			login: account.Login,
			expected: &models.User{
				ID:        account.ID,
				Login:     "alice.doe",
				Email:     "alice.doe@local",
				FirstName: "Alice",
				LastName:  "Doe",
			},
			error: false,
		},
		{
			name:     "User not found",
			login:    "not-a-login",
			expected: nil,
			error:    true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, err := repository.FindByLogin(ctx, tt.login)

			if tt.error {
				assert.Error(t, err)
			} else {
				assert.NoError(t, err)

				assert.Equal(t, tt.expected.ID, result.ID)
				assert.Equal(t, tt.expected.Login, result.Login)
				assert.Equal(t, tt.expected.Email, result.Email)
				assert.Equal(t, tt.expected.FirstName, result.FirstName)
				assert.Equal(t, tt.expected.LastName, result.LastName)
				assert.Equal(t, tt.expected.Appearance, result.Appearance)
			}
		})
	}
}

func Test_UserRepository_FindByEmail(t *testing.T) {
	ctx := context.Background()
	cfg := &config.Config{
		DatabaseDSN: os.Getenv("DATABASE_DSN"),
	}

	client, err := postgres.NewPostgresClient(cfg)
	assert.NoError(t, err)

	repository := NewUserRepository(client)

	account, err := repository.Create(ctx, db.CreateUserParams{
		Login:     "bob.doe",
		Email:     "bob.doe@local",
		FirstName: "Bob",
		LastName:  "Doe",
	})
	assert.NoError(t, err)

	tests := []struct {
		name     string
		email    string
		expected *models.User
		error    bool
	}{
		{
			name:  "Success",
			email: account.Email,
			expected: &models.User{
				ID:        account.ID,
				Login:     "bob.doe",
				Email:     "bob.doe@local",
				FirstName: "Bob",
				LastName:  "Doe",
			},
			error: false,
		},
		{
			name:     "User not found",
			email:    "not-a-email",
			expected: nil,
			error:    true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, err := repository.FindByEmail(ctx, tt.email)

			if tt.error {
				assert.Error(t, err)
			} else {
				assert.NoError(t, err)

				assert.Equal(t, tt.expected.ID, result.ID)
				assert.Equal(t, tt.expected.Login, result.Login)
				assert.Equal(t, tt.expected.Email, result.Email)
				assert.Equal(t, tt.expected.FirstName, result.FirstName)
				assert.Equal(t, tt.expected.LastName, result.LastName)
				assert.Equal(t, tt.expected.Appearance, result.Appearance)
			}
		})
	}
}
