-- +goose Up
CREATE TABLE movies (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  tmdb_id INTEGER NOT NULL,
  title VARCHAR(255) NOT NULL,
  poster_path VARCHAR(255),
  runtime INTEGER NOT NULL DEFAULT 0,
  state state_types NOT NULL,
  pinned BOOLEAN NOT NULL DEFAULT false,
  created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX movies_tmdb_id_idx ON movies(tmdb_id);
CREATE INDEX movies_user_id_state_idx ON movies(user_id, state);
CREATE INDEX movies_user_id_state_pinned_created_idx ON movies(user_id, state, pinned DESC, created_at DESC);
CREATE UNIQUE INDEX movies_user_id_tmdb_id_unique ON movies(user_id, tmdb_id);

-- +goose Down
DROP INDEX movies_user_id_tmdb_id_unique;
DROP INDEX movies_user_id_state_pinned_created_idx;
DROP INDEX movies_user_id_state_idx;
DROP INDEX movies_tmdb_id_idx;

DROP TABLE movies;
