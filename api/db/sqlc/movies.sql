-- name: FindMoviesByState :many
WITH counter AS (
  SELECT COUNT(*) AS total
  FROM movies
  WHERE user_id = $1 AND state = $2
)
SELECT
  m.id,
  m.user_id,
  m.tmdb_id,
  m.title,
  m.poster_path,
  m.runtime,
  m.pinned,
  m.state,
  m.watched_at,
  m.created_at,
  m.updated_at,
  counter.total
FROM movies m CROSS JOIN counter
WHERE m.user_id = $1 AND m.state = $2
ORDER BY m.pinned DESC, m.created_at DESC LIMIT $3 OFFSET $4;

-- name: FindMoviesByTmdbIds :many
SELECT
  id,
  user_id,
  tmdb_id,
  title,
  poster_path,
  runtime,
  pinned,
  state,
  watched_at,
  created_at,
  updated_at
FROM movies
WHERE tmdb_id = ANY(@tmdb_ids::integer[]) AND user_id = @user_id;

-- name: CreateMovie :one
INSERT INTO movies (
  user_id,
  tmdb_id,
  title,
  poster_path,
  runtime,
  state,
  watched_at
) VALUES (
  $1, $2, $3, $4, $5, $6, CASE WHEN $6 = 'watched'::state_types THEN NOW() ELSE NULL END
)
RETURNING
  id,
  user_id,
  tmdb_id,
  title,
  poster_path,
  runtime,
  state,
  pinned,
  created_at,
  updated_at,
  watched_at;

-- name: UpdateMovie :one
UPDATE movies
SET
  title = $2,
  poster_path = $3,
  runtime = $4,
  updated_at = NOW()
WHERE id = $1
RETURNING
  id,
  user_id,
  tmdb_id,
  title,
  poster_path,
  runtime,
  state,
  pinned,
  created_at,
  updated_at,
  watched_at;

-- name: UpdateMovieByTmdbId :one
UPDATE movies
SET
  state = $3,
  pinned = $4,
  watched_at = CASE WHEN $3 = 'watched'::state_types THEN COALESCE(watched_at, NOW()) ELSE NULL END,
  updated_at = NOW()
WHERE tmdb_id = $1 AND user_id = $2
RETURNING
  id,
  user_id,
  tmdb_id,
  title,
  poster_path,
  runtime,
  state,
  pinned,
  created_at,
  updated_at,
  watched_at;

-- name: DeleteMovieByTmdbId :exec
DELETE FROM movies WHERE tmdb_id = $1 AND user_id = $2;

-- name: FindMoviesToSync :many
SELECT
  id,
  user_id,
  tmdb_id,
  title,
  poster_path,
  runtime
FROM movies
WHERE (synced_at IS NULL OR synced_at < @stale_before)
  AND (released_at IS NULL OR released_at >= @release_cutoff)
ORDER BY synced_at ASC NULLS FIRST
LIMIT @batch_size;

-- name: SyncMovie :exec
UPDATE movies
SET
  title = @title,
  poster_path = @poster_path,
  runtime = @runtime,
  released_at = @released_at,
  synced_at = NOW()
WHERE id = @id;

-- name: TouchMovieSynced :exec
UPDATE movies SET synced_at = NOW() WHERE id = $1;
