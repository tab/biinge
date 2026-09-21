-- +goose Up
-- What the API did with a stored webhook event
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'status_type') THEN CREATE TYPE status_type AS ENUM ('marked', 'ignored', 'unresolved', 'failed'); END IF; END $$;

-- +goose Down
DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'status_type') THEN DROP TYPE status_type; END IF; END $$;
