-- +goose Up
-- Backfill existing NULL poster_path values, then make the column NOT NULL with
-- an empty-string default. sqlc maps poster_path to a non-nullable Go string,
-- so a NULL row would fail every scan; enforcing NOT NULL keeps schema and
-- generated code consistent.
UPDATE movies SET poster_path = '' WHERE poster_path IS NULL;
ALTER TABLE movies ALTER COLUMN poster_path SET DEFAULT '';
ALTER TABLE movies ALTER COLUMN poster_path SET NOT NULL;

UPDATE series SET poster_path = '' WHERE poster_path IS NULL;
ALTER TABLE series ALTER COLUMN poster_path SET DEFAULT '';
ALTER TABLE series ALTER COLUMN poster_path SET NOT NULL;

UPDATE episodes SET poster_path = '' WHERE poster_path IS NULL;
ALTER TABLE episodes ALTER COLUMN poster_path SET DEFAULT '';
ALTER TABLE episodes ALTER COLUMN poster_path SET NOT NULL;

-- +goose Down
ALTER TABLE movies ALTER COLUMN poster_path DROP NOT NULL;
ALTER TABLE movies ALTER COLUMN poster_path DROP DEFAULT;

ALTER TABLE series ALTER COLUMN poster_path DROP NOT NULL;
ALTER TABLE series ALTER COLUMN poster_path DROP DEFAULT;

ALTER TABLE episodes ALTER COLUMN poster_path DROP NOT NULL;
ALTER TABLE episodes ALTER COLUMN poster_path DROP DEFAULT;
