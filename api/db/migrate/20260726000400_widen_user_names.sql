-- +goose Up
-- Twenty characters rejects real surnames. Widening the column alone changes nothing,
-- so the validator and the OpenAPI schema move with it; login stays capped at 20 because
-- that limit is a deliberate handle length rather than a name.
ALTER TABLE users
  ALTER COLUMN first_name TYPE character varying(50),
  ALTER COLUMN last_name TYPE character varying(50);

-- +goose Down
ALTER TABLE users
  ALTER COLUMN first_name TYPE character varying(20),
  ALTER COLUMN last_name TYPE character varying(20);
