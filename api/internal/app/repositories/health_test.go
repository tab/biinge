package repositories

import (
	"context"
	"os"
	"testing"

	"github.com/stretchr/testify/assert"

	"biinge-api/internal/app/repositories/postgres"
	"biinge-api/internal/config"
)

func Test_HealthRepository_Ping(t *testing.T) {
	ctx := context.Background()
	dsn := os.Getenv("DATABASE_DSN")
	if dsn == "" {
		dsn = "postgres://postgres:postgres@localhost:5432/biinge-test?sslmode=disable"
	}
	cfg := &config.Config{
		DatabaseDSN: dsn,
	}

	client, err := postgres.NewPostgresClient(cfg)
	assert.NoError(t, err)

	healthRepository := NewHealthRepository(client)

	tests := []struct {
		name     string
		expected error
	}{
		{
			name:     "Success",
			expected: nil,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := healthRepository.Ping(ctx)
			assert.Equal(t, tt.expected, result)
		})
	}
}
