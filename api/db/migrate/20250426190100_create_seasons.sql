-- +goose Up
CREATE TABLE IF NOT EXISTS seasons (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  series_id UUID NOT NULL REFERENCES series(id) ON DELETE CASCADE,
  tmdb_id INTEGER NOT NULL,
  title VARCHAR(255) NOT NULL,
  number INTEGER NOT NULL DEFAULT 0,
  episodes_count INTEGER NOT NULL DEFAULT 0,
  state state_types NOT NULL,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS seasons_series_id_idx ON seasons(series_id);
CREATE INDEX IF NOT EXISTS seasons_tmdb_id_idx ON seasons(tmdb_id);
CREATE UNIQUE INDEX IF NOT EXISTS seasons_series_id_tmdb_id_unique ON seasons(series_id, tmdb_id);

-- +goose Down
DROP INDEX seasons_series_id_tmdb_id_unique;
DROP INDEX seasons_tmdb_id_idx;
DROP INDEX seasons_series_id_idx;

DROP TABLE seasons;
