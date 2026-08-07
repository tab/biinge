-- +goose Up
-- poster_path holds an IGDB cover image_id rather than a path, and runtime holds the
-- minutes to beat the game normally, from IGDB game_time_to_beats. State reuses
-- state_types: games take 'want', 'playing' and 'played', the values added alongside
-- this table.
-- synced_at records the last refresh from IGDB and is NULL until first synced;
-- released_at caches the PlayStation release date so the sync worker can skip
-- long-settled games without re-fetching them. Both are written by the games sync
-- worker, which does not exist yet.
CREATE TABLE IF NOT EXISTS games (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  igdb_id INTEGER NOT NULL,
  title VARCHAR(255) NOT NULL,
  poster_path VARCHAR(255) NOT NULL DEFAULT '',
  runtime INTEGER NOT NULL DEFAULT 0,
  state state_types NOT NULL,
  pinned BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  played_at TIMESTAMPTZ,
  synced_at TIMESTAMPTZ,
  released_at TIMESTAMPTZ,
  CONSTRAINT games_runtime_non_negative CHECK (runtime >= 0)
);

CREATE INDEX IF NOT EXISTS games_user_id_state_pinned_created_idx ON games(user_id, state, pinned DESC, created_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS games_user_id_igdb_id_unique ON games(user_id, igdb_id);

-- the statistics screen windows played history by calendar period; partial because
-- only played rows carry a played_at, which keeps the index small
CREATE INDEX IF NOT EXISTS games_user_id_played_at_idx ON games (user_id, played_at) WHERE played_at IS NOT NULL;

-- the sync worker scans oldest-synced-first
CREATE INDEX IF NOT EXISTS games_synced_at_idx ON games (synced_at ASC NULLS FIRST);

-- +goose Down
DROP INDEX games_synced_at_idx;
DROP INDEX games_user_id_played_at_idx;
DROP INDEX games_user_id_igdb_id_unique;
DROP INDEX games_user_id_state_pinned_created_idx;

DROP TABLE games;
