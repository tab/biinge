-- +goose Up
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'appearance_type') THEN CREATE TYPE appearance_type AS ENUM ('system', 'light', 'dark'); END IF; END $$;

-- +goose Down
DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'appearance_type') THEN DROP TYPE appearance_type; END IF; END $$;
