-- +goose Up
DO $$ BEGIN IF NOT EXISTS (SELECT 1 FROM pg_type WHERE typname = 'share_type') THEN CREATE TYPE share_type AS ENUM ('movie', 'tv', 'game'); END IF; END $$;

-- object_id is the TMDB id of a movie or series, or the IGDB id of a game.
-- visited_at moves on every visit and on a re-share, and a share expires after 30 days without one.
CREATE TABLE IF NOT EXISTS shares (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  type share_type NOT NULL,
  object_id INTEGER NOT NULL,
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  visited_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX IF NOT EXISTS shares_user_id_type_object_id_unique ON shares(user_id, type, object_id);

-- the cleanup job deletes by visited_at
CREATE INDEX IF NOT EXISTS shares_visited_at_idx ON shares(visited_at);

-- +goose Down
DROP INDEX shares_visited_at_idx;
DROP INDEX shares_user_id_type_object_id_unique;

DROP TABLE shares;

DO $$ BEGIN IF EXISTS (SELECT 1 FROM pg_type WHERE typname = 'share_type') THEN DROP TYPE share_type; END IF; END $$;
