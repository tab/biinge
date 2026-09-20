-- name: FindGamesByState :many
WITH counter AS (
  SELECT COUNT(*) AS total
  FROM games
  WHERE user_id = $1 AND state = $2
)
SELECT
  g.id,
  g.user_id,
  g.igdb_id,
  g.title,
  g.poster_path,
  g.runtime,
  g.pinned,
  g.state,
  g.played_at,
  g.created_at,
  g.updated_at,
  counter.total
FROM games g CROSS JOIN counter
WHERE g.user_id = $1 AND g.state = $2
ORDER BY g.pinned DESC, g.created_at DESC LIMIT $3 OFFSET $4;

-- name: FindGamesByIgdbIds :many
SELECT
  id,
  user_id,
  igdb_id,
  title,
  poster_path,
  runtime,
  pinned,
  state,
  played_at,
  created_at,
  updated_at
FROM games
WHERE igdb_id = ANY(@igdb_ids::integer[]) AND user_id = @user_id;

-- name: CreateGame :one
INSERT INTO games (
  user_id,
  igdb_id,
  title,
  poster_path,
  runtime,
  state,
  played_at
) VALUES (
  $1, $2, $3, $4, $5, $6, CASE WHEN $6 = 'played'::state_types THEN NOW() ELSE NULL END
)
RETURNING
  id,
  user_id,
  igdb_id,
  title,
  poster_path,
  runtime,
  state,
  pinned,
  created_at,
  updated_at,
  played_at;

-- name: UpdateGame :one
UPDATE games
SET
  title = $2,
  poster_path = $3,
  runtime = $4,
  updated_at = NOW()
WHERE id = $1
RETURNING
  id,
  user_id,
  igdb_id,
  title,
  poster_path,
  runtime,
  state,
  pinned,
  created_at,
  updated_at,
  played_at;

-- name: UpdateGameByIgdbId :one
UPDATE games
SET
  state = $3,
  pinned = $4,
  played_at = CASE WHEN $3 = 'played'::state_types THEN COALESCE(played_at, NOW()) ELSE NULL END,
  updated_at = NOW()
WHERE igdb_id = $1 AND user_id = $2
RETURNING
  id,
  user_id,
  igdb_id,
  title,
  poster_path,
  runtime,
  state,
  pinned,
  created_at,
  updated_at,
  played_at;

-- name: DeleteGameByIgdbId :exec
DELETE FROM games WHERE igdb_id = $1 AND user_id = $2;
