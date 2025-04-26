-- +goose Up
CREATE INDEX users_created_at_not_deleted_idx
  ON users(created_at DESC)
  WHERE deleted_at IS NULL;

-- +goose Down
DROP INDEX users_created_at_not_deleted_idx;
