-- name: FindEpisodesBySeasonId :many
SELECT
  e.id,
  e.season_id,
  e.tmdb_id,
  e.title,
  e.poster_path,
  e.runtime,
  e.state,
  e.air_at,
  e.created_at,
  e.updated_at
FROM episodes e
  JOIN seasons s ON e.season_id = s.id
  JOIN series t ON s.series_id = t.id
WHERE e.season_id = $1 AND t.user_id = $2
ORDER BY e.air_at DESC;

-- name: FindEpisodeById :one
SELECT
  e.id,
  e.season_id,
  e.tmdb_id,
  e.title,
  e.poster_path,
  e.runtime,
  e.state,
  e.air_at,
  e.created_at,
  e.updated_at
FROM episodes e
  JOIN seasons s ON e.season_id = s.id
  JOIN series t ON s.series_id = t.id
WHERE e.id = $1 AND t.user_id = $2;

-- name: CreateEpisode :one
INSERT INTO episodes (
  season_id,
  tmdb_id,
  title,
  poster_path,
  runtime,
  state,
  air_at
) VALUES (
  $1, $2, $3, $4, $5, $6, $7
)
RETURNING
  id,
  season_id,
  tmdb_id,
  title,
  poster_path,
  runtime,
  state,
  air_at,
  created_at,
  updated_at;

-- name: UpdateEpisode :one
UPDATE episodes
SET
  title = $3,
  poster_path = $4,
  runtime = $5,
  air_at = $6,
  state = $7,
  updated_at = NOW()
WHERE episodes.id = $1
  AND EXISTS (
  SELECT 1 FROM seasons s
    JOIN series t ON s.series_id = t.id
  WHERE episodes.season_id = s.id AND t.user_id = $2
)
RETURNING
  id,
  season_id,
  tmdb_id,
  title,
  poster_path,
  runtime,
  state,
  air_at,
  created_at,
  updated_at;

-- name: UpdateEpisodeByTmdbId :one
UPDATE episodes
SET
  state = $3,
  updated_at = NOW()
WHERE episodes.tmdb_id = $1
  AND EXISTS (
  SELECT 1 FROM seasons s
    JOIN series t ON s.series_id = t.id
  WHERE episodes.season_id = s.id AND t.user_id = $2
)
  RETURNING
  id,
  season_id,
  tmdb_id,
  title,
  poster_path,
  runtime,
  state,
  air_at,
  created_at,
  updated_at;


-- name: DeleteEpisode :exec
DELETE FROM episodes WHERE id = $1;

-- name: UpsertEpisode :one
INSERT INTO episodes (
  season_id,
  tmdb_id,
  title,
  poster_path,
  runtime,
  state,
  air_at
) VALUES (
  $1, $2, $3, $4, $5, $6, $7
)
ON CONFLICT (season_id, tmdb_id) DO UPDATE SET
  title = EXCLUDED.title,
  poster_path = EXCLUDED.poster_path,
  runtime = EXCLUDED.runtime,
  state = EXCLUDED.state,
  air_at = EXCLUDED.air_at,
  updated_at = NOW()
RETURNING
  id,
  season_id,
  tmdb_id,
  title,
  poster_path,
  runtime,
  state,
  air_at,
  created_at,
  updated_at;

-- name: DeleteEpisodeBySeasonAndTmdbId :exec
DELETE FROM episodes WHERE season_id = $1 AND tmdb_id = $2;

-- name: CountEpisodesBySeasonId :one
SELECT COUNT(*)
FROM episodes e
  JOIN seasons s ON e.season_id = s.id
  JOIN series t ON s.series_id = t.id
WHERE e.season_id = $1 AND t.user_id = $2;

-- name: CountWatchedEpisodesBySeasonId :one
SELECT COUNT(*)
FROM episodes e
  JOIN seasons s ON e.season_id = s.id
  JOIN series t ON s.series_id = t.id
WHERE e.season_id = $1 AND t.user_id = $2 AND e.state = $3;
