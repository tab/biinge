-- +goose Up
-- synced_at records the last time the row was refreshed from TMDB; NULL until first synced.
-- released_at (movies) and last_air_at (series) cache the TMDB release / last-air date so the
-- sync worker can skip long-settled titles without re-fetching them.
ALTER TABLE movies ADD COLUMN synced_at timestamp without time zone;
ALTER TABLE movies ADD COLUMN released_at timestamp without time zone;
ALTER TABLE series ADD COLUMN synced_at timestamp without time zone;
ALTER TABLE series ADD COLUMN last_air_at timestamp without time zone;

-- the worker scans oldest-synced-first per table
CREATE INDEX movies_synced_at_idx ON movies (synced_at ASC NULLS FIRST);
CREATE INDEX series_synced_at_idx ON series (synced_at ASC NULLS FIRST);

-- +goose Down
DROP INDEX series_synced_at_idx;
DROP INDEX movies_synced_at_idx;
ALTER TABLE series DROP COLUMN last_air_at;
ALTER TABLE series DROP COLUMN synced_at;
ALTER TABLE movies DROP COLUMN released_at;
ALTER TABLE movies DROP COLUMN synced_at;
