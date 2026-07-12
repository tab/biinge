-- name: DeleteSeason :exec
DELETE FROM seasons WHERE id = $1;

-- name: UpsertSeason :one
INSERT INTO seasons (
  series_id,
  tmdb_id,
  title,
  number,
  episodes_count,
  state
) VALUES (
  $1, $2, $3, $4, $5, $6
)
ON CONFLICT (series_id, tmdb_id) DO UPDATE SET
  title = EXCLUDED.title,
  number = EXCLUDED.number,
  episodes_count = EXCLUDED.episodes_count,
  updated_at = NOW()
RETURNING
  id,
  series_id,
  tmdb_id,
  title,
  number,
  episodes_count,
  state,
  created_at,
  updated_at;

-- name: SetSeasonState :exec
UPDATE seasons SET state = $2, updated_at = NOW() WHERE id = $1;

-- name: FindSeasonBySeriesAndTmdbId :one
SELECT
  id,
  series_id,
  tmdb_id,
  title,
  number,
  episodes_count,
  state,
  created_at,
  updated_at
FROM seasons
WHERE series_id = $1 AND tmdb_id = $2 LIMIT 1;

-- name: CountEpisodesBySeason :one
SELECT COUNT(*) FROM episodes WHERE season_id = $1;
