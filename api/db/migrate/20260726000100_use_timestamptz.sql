-- +goose Up
-- Naive timestamps keep the server's wall clock and discard the offset, so the calendar
-- windows the statistics screen depends on move if the server's zone ever changes and
-- an imported history has no instant to anchor to. Existing rows were written by NOW()
-- under the container default of UTC, which is what the conversion reads them as.
ALTER TABLE episodes
  ALTER COLUMN air_at TYPE timestamptz USING air_at AT TIME ZONE 'UTC',
  ALTER COLUMN created_at TYPE timestamptz USING created_at AT TIME ZONE 'UTC',
  ALTER COLUMN updated_at TYPE timestamptz USING updated_at AT TIME ZONE 'UTC',
  ALTER COLUMN watched_at TYPE timestamptz USING watched_at AT TIME ZONE 'UTC';

ALTER TABLE movies
  ALTER COLUMN created_at TYPE timestamptz USING created_at AT TIME ZONE 'UTC',
  ALTER COLUMN updated_at TYPE timestamptz USING updated_at AT TIME ZONE 'UTC',
  ALTER COLUMN watched_at TYPE timestamptz USING watched_at AT TIME ZONE 'UTC',
  ALTER COLUMN synced_at TYPE timestamptz USING synced_at AT TIME ZONE 'UTC',
  ALTER COLUMN released_at TYPE timestamptz USING released_at AT TIME ZONE 'UTC';

ALTER TABLE seasons
  ALTER COLUMN created_at TYPE timestamptz USING created_at AT TIME ZONE 'UTC',
  ALTER COLUMN updated_at TYPE timestamptz USING updated_at AT TIME ZONE 'UTC',
  ALTER COLUMN watched_at TYPE timestamptz USING watched_at AT TIME ZONE 'UTC';

ALTER TABLE series
  ALTER COLUMN created_at TYPE timestamptz USING created_at AT TIME ZONE 'UTC',
  ALTER COLUMN updated_at TYPE timestamptz USING updated_at AT TIME ZONE 'UTC',
  ALTER COLUMN synced_at TYPE timestamptz USING synced_at AT TIME ZONE 'UTC',
  ALTER COLUMN last_air_at TYPE timestamptz USING last_air_at AT TIME ZONE 'UTC';

ALTER TABLE users
  ALTER COLUMN deleted_at TYPE timestamptz USING deleted_at AT TIME ZONE 'UTC',
  ALTER COLUMN created_at TYPE timestamptz USING created_at AT TIME ZONE 'UTC',
  ALTER COLUMN updated_at TYPE timestamptz USING updated_at AT TIME ZONE 'UTC';

-- +goose Down
ALTER TABLE episodes
  ALTER COLUMN air_at TYPE timestamp USING air_at AT TIME ZONE 'UTC',
  ALTER COLUMN created_at TYPE timestamp USING created_at AT TIME ZONE 'UTC',
  ALTER COLUMN updated_at TYPE timestamp USING updated_at AT TIME ZONE 'UTC',
  ALTER COLUMN watched_at TYPE timestamp USING watched_at AT TIME ZONE 'UTC';

ALTER TABLE movies
  ALTER COLUMN created_at TYPE timestamp USING created_at AT TIME ZONE 'UTC',
  ALTER COLUMN updated_at TYPE timestamp USING updated_at AT TIME ZONE 'UTC',
  ALTER COLUMN watched_at TYPE timestamp USING watched_at AT TIME ZONE 'UTC',
  ALTER COLUMN synced_at TYPE timestamp USING synced_at AT TIME ZONE 'UTC',
  ALTER COLUMN released_at TYPE timestamp USING released_at AT TIME ZONE 'UTC';

ALTER TABLE seasons
  ALTER COLUMN created_at TYPE timestamp USING created_at AT TIME ZONE 'UTC',
  ALTER COLUMN updated_at TYPE timestamp USING updated_at AT TIME ZONE 'UTC',
  ALTER COLUMN watched_at TYPE timestamp USING watched_at AT TIME ZONE 'UTC';

ALTER TABLE series
  ALTER COLUMN created_at TYPE timestamp USING created_at AT TIME ZONE 'UTC',
  ALTER COLUMN updated_at TYPE timestamp USING updated_at AT TIME ZONE 'UTC',
  ALTER COLUMN synced_at TYPE timestamp USING synced_at AT TIME ZONE 'UTC',
  ALTER COLUMN last_air_at TYPE timestamp USING last_air_at AT TIME ZONE 'UTC';

ALTER TABLE users
  ALTER COLUMN deleted_at TYPE timestamp USING deleted_at AT TIME ZONE 'UTC',
  ALTER COLUMN created_at TYPE timestamp USING created_at AT TIME ZONE 'UTC',
  ALTER COLUMN updated_at TYPE timestamp USING updated_at AT TIME ZONE 'UTC';
