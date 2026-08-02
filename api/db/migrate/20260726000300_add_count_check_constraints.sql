-- +goose Up
-- Runtimes and counts come from TMDB, which has served junk before. The Go layer types
-- them as uint64 so the application cannot write a negative, but nothing stops a manual
-- edit or a future import from doing it, and a negative runtime corrupts watched minutes.
ALTER TABLE episodes ADD CONSTRAINT episodes_runtime_non_negative CHECK (runtime >= 0);

ALTER TABLE movies ADD CONSTRAINT movies_runtime_non_negative CHECK (runtime >= 0);

ALTER TABLE seasons
  ADD CONSTRAINT seasons_number_non_negative CHECK (number >= 0),
  ADD CONSTRAINT seasons_episodes_count_non_negative CHECK (episodes_count >= 0);

ALTER TABLE series
  ADD CONSTRAINT series_seasons_count_non_negative CHECK (seasons_count >= 0),
  ADD CONSTRAINT series_episodes_count_non_negative CHECK (episodes_count >= 0);

-- +goose Down
ALTER TABLE series
  DROP CONSTRAINT series_episodes_count_non_negative,
  DROP CONSTRAINT series_seasons_count_non_negative;

ALTER TABLE seasons
  DROP CONSTRAINT seasons_episodes_count_non_negative,
  DROP CONSTRAINT seasons_number_non_negative;

ALTER TABLE movies DROP CONSTRAINT movies_runtime_non_negative;

ALTER TABLE episodes DROP CONSTRAINT episodes_runtime_non_negative;
