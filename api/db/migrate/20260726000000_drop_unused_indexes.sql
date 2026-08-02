-- +goose Up
-- Nine indexes no query can reach. Four are strict prefixes of a wider index on the
-- same leading columns, four cover tmdb_id alone when every lookup pairs it with the
-- owning user or parent row, and users is never listed or ordered by created_at.
DROP INDEX episodes_season_id_idx;
DROP INDEX seasons_series_id_idx;
DROP INDEX movies_user_id_state_idx;
DROP INDEX series_user_id_state_idx;

DROP INDEX episodes_tmdb_id_idx;
DROP INDEX seasons_tmdb_id_idx;
DROP INDEX movies_tmdb_id_idx;
DROP INDEX series_tmdb_id_idx;

DROP INDEX users_created_at_not_deleted_idx;

-- +goose Down
CREATE INDEX episodes_season_id_idx ON episodes (season_id);
CREATE INDEX seasons_series_id_idx ON seasons (series_id);
CREATE INDEX movies_user_id_state_idx ON movies (user_id, state);
CREATE INDEX series_user_id_state_idx ON series (user_id, state);

CREATE INDEX episodes_tmdb_id_idx ON episodes (tmdb_id);
CREATE INDEX seasons_tmdb_id_idx ON seasons (tmdb_id);
CREATE INDEX movies_tmdb_id_idx ON movies (tmdb_id);
CREATE INDEX series_tmdb_id_idx ON series (tmdb_id);

CREATE INDEX users_created_at_not_deleted_idx ON users (created_at DESC) WHERE deleted_at IS NULL;
