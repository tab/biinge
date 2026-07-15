-- +goose Up
-- watched_at records when a row entered the watched state; NULL while not watched.
-- Powers watch-history/diary and time-series stats that updated_at can't express.
ALTER TABLE movies ADD COLUMN watched_at timestamp without time zone;
ALTER TABLE seasons ADD COLUMN watched_at timestamp without time zone;
ALTER TABLE episodes ADD COLUMN watched_at timestamp without time zone;

-- backfill from updated_at where the row is already watched; the best signal we have
UPDATE movies SET watched_at = updated_at WHERE state = 'watched';
UPDATE seasons SET watched_at = updated_at WHERE state = 'watched';
UPDATE episodes SET watched_at = updated_at WHERE state = 'watched';

-- +goose Down
ALTER TABLE movies DROP COLUMN watched_at;
ALTER TABLE seasons DROP COLUMN watched_at;
ALTER TABLE episodes DROP COLUMN watched_at;
