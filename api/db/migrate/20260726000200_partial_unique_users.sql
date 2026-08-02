-- +goose Up
-- A global unique keeps a soft-deleted user's email and login reserved forever, which
-- contradicts the lookups: they filter deleted_at IS NULL and report the address free
-- while registration fails on the constraint. Scope both to live rows.
--
-- The index names are preserved because CreateUser matches on the constraint name in
-- the 23505 error to choose between its login and email sentinels.
ALTER TABLE users DROP CONSTRAINT users_email_key;
ALTER TABLE users DROP CONSTRAINT users_login_key;

CREATE UNIQUE INDEX users_email_key ON users (email) WHERE deleted_at IS NULL;
CREATE UNIQUE INDEX users_login_key ON users (login) WHERE deleted_at IS NULL;

-- +goose Down
DROP INDEX users_email_key;
DROP INDEX users_login_key;

ALTER TABLE users ADD CONSTRAINT users_email_key UNIQUE (email);
ALTER TABLE users ADD CONSTRAINT users_login_key UNIQUE (login);
