-- +goose Up
CREATE INDEX IF NOT EXISTS users_created_at_not_deleted_idx
  ON users(created_at DESC)
  WHERE deleted_at IS NULL;

-- +goose Down
DROP INDEX users_created_at_not_deleted_idx;
