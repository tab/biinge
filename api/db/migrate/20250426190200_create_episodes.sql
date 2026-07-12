-- +goose Up
CREATE TABLE IF NOT EXISTS episodes (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  season_id UUID NOT NULL REFERENCES seasons(id) ON DELETE CASCADE,
  tmdb_id INTEGER NOT NULL,
  title VARCHAR(255) NOT NULL,
  poster_path VARCHAR(255),
  runtime INTEGER NOT NULL DEFAULT 0,
  state state_types NOT NULL,
  air_at TIMESTAMP,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS episodes_season_id_idx ON episodes(season_id);
CREATE INDEX IF NOT EXISTS episodes_tmdb_id_idx ON episodes(tmdb_id);
CREATE INDEX IF NOT EXISTS episodes_season_id_air_at_idx ON episodes(season_id, air_at DESC);
CREATE UNIQUE INDEX IF NOT EXISTS episodes_season_id_tmdb_id_unique ON episodes(season_id, tmdb_id);

-- +goose Down
DROP INDEX episodes_season_id_tmdb_id_unique;
DROP INDEX episodes_season_id_air_at_idx;
DROP INDEX episodes_tmdb_id_idx;
DROP INDEX episodes_season_id_idx;

DROP TABLE episodes;
