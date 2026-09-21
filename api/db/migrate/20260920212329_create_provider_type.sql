-- +goose Up
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'provider_type') THEN CREATE TYPE provider_type AS ENUM ('jellyfin'); END IF; END $$;

-- +goose Down
DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'provider_type') THEN DROP TYPE provider_type; END IF; END $$;
