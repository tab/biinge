-- +goose Up
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'state_types') THEN CREATE TYPE state_types AS ENUM ('want', 'watching', 'watched', 'none'); END IF; END $$;

-- +goose Down
DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'state_types') THEN DROP TYPE state_types; END IF; END $$;
