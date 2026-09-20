-- name: FindSeriesByState :many
WITH counter AS (
  SELECT COUNT(*) AS total
  FROM series
  WHERE user_id = $1 AND state = $2
)
SELECT
  s.id,
  s.user_id,
  s.tmdb_id,
  s.title,
  s.poster_path,
  s.episodes_count,
  s.pinned,
  s.state,
  s.created_at,
  s.updated_at,
  counter.total,
  (
    SELECT COUNT(*)
    FROM episodes e
      JOIN seasons se ON e.season_id = se.id
    WHERE se.series_id = s.id
  )::bigint AS watched_episodes_count
FROM series s CROSS JOIN counter
WHERE s.user_id = $1 AND s.state = $2
ORDER BY s.pinned DESC, s.created_at DESC LIMIT $3 OFFSET $4;

-- name: FindSeriesByTmdbIds :many
SELECT
  id,
  user_id,
  tmdb_id,
  title,
  poster_path,
  seasons_count,
  episodes_count,
  status,
  state,
  pinned,
  created_at,
  updated_at,
  tracked_state,
  synced_at,
  last_air_at
FROM series
WHERE tmdb_id = ANY(@tmdb_ids::integer[]) AND user_id = @user_id;

-- name: FindSeriesByTmdbId :one
SELECT
  id,
  user_id,
  tmdb_id,
  title,
  poster_path,
  seasons_count,
  episodes_count,
  status,
  state,
  pinned,
  created_at,
  updated_at,
  tracked_state,
  synced_at,
  last_air_at
FROM series
WHERE tmdb_id = $1 AND user_id = $2 LIMIT 1;

-- name: FindSeriesByTmdbIdForUpdate :one
SELECT
  id,
  user_id,
  tmdb_id,
  title,
  poster_path,
  seasons_count,
  episodes_count,
  status,
  state,
  pinned,
  created_at,
  updated_at,
  tracked_state,
  synced_at,
  last_air_at
FROM series
WHERE tmdb_id = $1 AND user_id = $2 LIMIT 1
FOR UPDATE;

-- name: FindSeriesToSync :many
SELECT
  id,
  user_id,
  tmdb_id,
  title,
  poster_path,
  seasons_count,
  episodes_count,
  status
FROM series
WHERE (synced_at IS NULL OR synced_at < @stale_before)
  AND (
    last_air_at IS NULL
    OR last_air_at >= @air_cutoff
    OR status = ANY(@active_statuses::varchar[])
  )
ORDER BY synced_at ASC NULLS FIRST
LIMIT @batch_size;

-- name: CreateSeries :one
INSERT INTO series (
  user_id,
  tmdb_id,
  title,
  poster_path,
  seasons_count,
  episodes_count,
  status,
  state,
  tracked_state
) VALUES (
  $1, $2, $3, $4, $5, $6, $7, $8, $8
)
RETURNING
  id,
  user_id,
  tmdb_id,
  title,
  poster_path,
  seasons_count,
  episodes_count,
  status,
  state,
  pinned,
  created_at,
  updated_at,
  tracked_state,
  synced_at,
  last_air_at;

-- name: UpdateSeries :one
UPDATE series
SET
  title = $2,
  poster_path = $3,
  seasons_count = $4,
  episodes_count = $5,
  status = $6,
  updated_at = NOW()
WHERE id = $1
RETURNING
  id,
  user_id,
  tmdb_id,
  title,
  poster_path,
  seasons_count,
  episodes_count,
  status,
  state,
  pinned,
  created_at,
  updated_at,
  tracked_state,
  synced_at,
  last_air_at;

-- name: SyncSeries :one
UPDATE series
SET
  title = @title,
  poster_path = @poster_path,
  seasons_count = @seasons_count,
  episodes_count = @episodes_count,
  status = @status,
  last_air_at = @last_air_at,
  synced_at = NOW()
WHERE id = @id
RETURNING
  id,
  user_id,
  tmdb_id,
  title,
  poster_path,
  seasons_count,
  episodes_count,
  status,
  state,
  pinned,
  created_at,
  updated_at,
  tracked_state,
  synced_at,
  last_air_at;

-- name: TouchSeriesSynced :exec
UPDATE series SET synced_at = NOW() WHERE id = $1;

-- name: UpdateSeriesByTmdbId :one
UPDATE series
SET
  state = $3,
  tracked_state = $3,
  pinned = $4,
  updated_at = NOW()
WHERE tmdb_id = $1 AND user_id = $2
RETURNING
  id,
  user_id,
  tmdb_id,
  title,
  poster_path,
  seasons_count,
  episodes_count,
  status,
  state,
  pinned,
  created_at,
  updated_at,
  tracked_state,
  synced_at,
  last_air_at;

-- name: DeleteSeries :exec
DELETE FROM series WHERE id = $1;

-- name: DeleteSeriesByTmdbId :exec
DELETE FROM series WHERE tmdb_id = $1 AND user_id = $2;

-- name: UpsertSeries :one
INSERT INTO series (
  user_id,
  tmdb_id,
  title,
  poster_path,
  seasons_count,
  episodes_count,
  status,
  state
) VALUES (
  $1, $2, $3, $4, $5, $6, $7, $8
)
ON CONFLICT (user_id, tmdb_id) DO UPDATE SET
  title = EXCLUDED.title,
  poster_path = EXCLUDED.poster_path,
  seasons_count = CASE WHEN EXCLUDED.seasons_count > 0 THEN EXCLUDED.seasons_count ELSE series.seasons_count END,
  episodes_count = CASE WHEN EXCLUDED.episodes_count > 0 THEN EXCLUDED.episodes_count ELSE series.episodes_count END,
  status = EXCLUDED.status,
  updated_at = NOW()
RETURNING
  id,
  user_id,
  tmdb_id,
  title,
  poster_path,
  seasons_count,
  episodes_count,
  status,
  state,
  pinned,
  created_at,
  updated_at,
  tracked_state,
  synced_at,
  last_air_at;

-- name: SetSeriesState :exec
UPDATE series SET state = $2, updated_at = NOW() WHERE id = $1;

-- name: CountEpisodesBySeriesId :one
SELECT COUNT(*)
FROM episodes e
  JOIN seasons s ON e.season_id = s.id
WHERE s.series_id = $1;

-- name: FindWatchedSeasonTmdbIdsBySeriesId :many
SELECT tmdb_id FROM seasons WHERE series_id = $1 AND state = 'watched';

-- name: CountWatchedSeasonsBySeriesId :one
SELECT COUNT(*)
FROM seasons
WHERE series_id = $1 AND state = 'watched' AND number > 0;

-- name: FindEpisodeTmdbIdsBySeriesId :many
SELECT e.tmdb_id
FROM episodes e
  JOIN seasons s ON e.season_id = s.id
WHERE s.series_id = $1;
