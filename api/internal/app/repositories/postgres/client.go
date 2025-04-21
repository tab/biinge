package postgres

import (
	"context"

	"github.com/jackc/pgx/v5/pgxpool"

	"biinge-api/internal/app/repositories/db"
	"biinge-api/internal/config"
)

type Postgres interface {
	Db() *pgxpool.Pool
	Queries() *db.Queries
}

type pgClient struct {
	db      *pgxpool.Pool
	queries *db.Queries
}

func NewPostgresClient(cfg *config.Config) (Postgres, error) {
	poolConfig, err := pgxpool.ParseConfig(cfg.DatabaseDSN)
	if err != nil {
		return nil, err
	}

	pool, err := pgxpool.NewWithConfig(context.Background(), poolConfig)
	if err != nil {
		return nil, err
	}

	queries := db.New(pool)

	return &pgClient{
		db:      pool,
		queries: queries,
	}, nil
}

func (p *pgClient) Db() *pgxpool.Pool {
	return p.db
}

func (p *pgClient) Queries() *db.Queries {
	return p.queries
}
