package spec

import (
	"context"
	"fmt"

	"github.com/jackc/pgx/v5/pgxpool"
)

func TruncateTables(ctx context.Context, dsn string, tables []string) error {
	for _, table := range tables {
		query := fmt.Sprintf("TRUNCATE TABLE %s RESTART IDENTITY CASCADE;", table)
		err := run(ctx, dsn, query)
		if err != nil {
			return err
		}
	}

	return nil
}

func run(ctx context.Context, dsn string, query string) error {
	db, err := pgxpool.New(ctx, dsn)
	if err != nil {
		return err
	}
	defer db.Close()

	_, err = db.Exec(ctx, query)
	if err != nil {
		return err
	}

	return nil
}
