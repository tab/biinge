-- name: FindSeasonsBySeriesId :many
SELECT
  s.id,
  s.series_id,
  s.tmdb_id,
  s.title,
  s.number,
  s.episodes_count,
  s.state,
  s.created_at,
  s.updated_at
FROM seasons s
  JOIN series t ON s.series_id = t.id
WHERE s.series_id = $1 AND t.user_id = $2
ORDER BY s.number ASC;

-- name: FindSeasonById :one
SELECT
  s.id,
  s.series_id,
  s.tmdb_id,
  s.title,
  s.number,
  s.episodes_count,
  s.state,
  s.created_at,
  s.updated_at
FROM seasons s
  JOIN series t ON s.series_id = t.id
WHERE s.id = $1;

-- name: CreateSeason :one
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

-- name: UpdateSeason :one
UPDATE seasons
SET
  title = $3,
  number = $4,
  episodes_count = $5,
  updated_at = NOW()
WHERE seasons.id = $1 AND EXISTS (
  SELECT 1 FROM series t
  WHERE seasons.series_id = t.id AND t.user_id = $2
)
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

-- name: UpdateSeasonByTmdbId :one
UPDATE seasons
SET
  state = $3,
  updated_at = NOW()
WHERE seasons.tmdb_id = $1 AND EXISTS (
  SELECT 1 FROM series t
  WHERE seasons.series_id = t.id AND t.user_id = $2
)
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

-- name: CountWatchedSeasonsBySeriesId :one
SELECT COUNT(*)
FROM seasons s
  JOIN series t ON s.series_id = t.id
WHERE s.series_id = $1 AND t.user_id = $2 AND s.state = $3;
