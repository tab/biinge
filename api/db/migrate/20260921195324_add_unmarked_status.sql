-- +goose Up
-- unmarked is the status of a stored event whose unplayed toggle removed a watched mark.
-- Postgres cannot drop a value from an enum, hence the rebuild on the way down.
ALTER TYPE status_type ADD VALUE IF NOT EXISTS 'unmarked';

-- +goose Down
DELETE FROM webhooks WHERE status = 'unmarked';

ALTER TYPE status_type RENAME TO status_type_old;

CREATE TYPE status_type AS ENUM ('marked', 'ignored', 'unresolved', 'failed');

ALTER TABLE webhooks ALTER COLUMN status TYPE status_type USING status::text::status_type;

DROP TYPE status_type_old;
