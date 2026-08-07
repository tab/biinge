-- +goose Up
-- Games are played, not watched. state_types is already a superset that each table
-- draws a subset from -- movies use want and watched, series add watching -- so games
-- take want, playing and played. Postgres cannot drop a value from an enum, hence the
-- rebuild on the way down.
ALTER TYPE state_types ADD VALUE IF NOT EXISTS 'playing';
ALTER TYPE state_types ADD VALUE IF NOT EXISTS 'played';

-- +goose Down
ALTER TYPE state_types RENAME TO state_types_old;

CREATE TYPE state_types AS ENUM ('want', 'watching', 'watched', 'none');

ALTER TABLE episodes ALTER COLUMN state TYPE state_types USING state::text::state_types;
ALTER TABLE movies ALTER COLUMN state TYPE state_types USING state::text::state_types;
ALTER TABLE seasons ALTER COLUMN state TYPE state_types USING state::text::state_types;
ALTER TABLE series
  ALTER COLUMN state TYPE state_types USING state::text::state_types,
  ALTER COLUMN tracked_state TYPE state_types USING tracked_state::text::state_types;

DROP TYPE state_types_old;
