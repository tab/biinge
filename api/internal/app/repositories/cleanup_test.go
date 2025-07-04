package repositories

import (
	"context"
	"log"
	"os"
	"testing"

	"biinge-api/internal/config"
	"biinge-api/pkg/spec"
)

func TestMain(m *testing.M) {
	if err := spec.LoadEnv(); err != nil {
		log.Fatalf("Error loading environment variables: %v", err)
	}

	if os.Getenv("GO_ENV") == "ci" {
		os.Exit(0)
	}

	ctx := context.Background()
	cfg := &config.Config{
		DatabaseDSN: os.Getenv("DATABASE_DSN"),
	}

	tables := []string{
		"users",
	}

	err := spec.TruncateTables(ctx, cfg.DatabaseDSN, tables)
	if err != nil {
		log.Fatalf("Error truncating tables: %v", err)
	}

	code := m.Run()

	err = spec.TruncateTables(ctx, cfg.DatabaseDSN, tables)
	if err != nil {
		log.Fatalf("Error truncating tables: %v", err)
	}

	os.Exit(code)
}
