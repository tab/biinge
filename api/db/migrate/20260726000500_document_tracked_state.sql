-- +goose Up
-- series carries two state columns and the schema dump gives no hint how they relate,
-- so the distinction only lived in the migration that added the second one.
COMMENT ON COLUMN series.state IS 'the show''s effective state, derived from watched seasons when the user has not chosen one';
COMMENT ON COLUMN series.tracked_state IS 'the state the user explicitly chose; NULL when the row was created by marking an episode';

-- +goose Down
COMMENT ON COLUMN series.tracked_state IS NULL;
COMMENT ON COLUMN series.state IS NULL;
