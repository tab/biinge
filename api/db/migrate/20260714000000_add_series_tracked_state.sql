-- +goose Up
-- tracked_state remembers the state the user explicitly chose; NULL for rows auto-created by episode marks
ALTER TABLE series ADD COLUMN tracked_state state_types;

-- existing rows predate the distinction; keep them as explicitly tracked
UPDATE series SET tracked_state = state;

-- +goose Down
ALTER TABLE series DROP COLUMN tracked_state;
