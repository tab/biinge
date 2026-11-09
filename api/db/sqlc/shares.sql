-- name: UpsertShare :one
INSERT INTO shares (
  user_id,
  type,
  object_id
) VALUES (
  $1, $2, $3
)
ON CONFLICT (user_id, type, object_id) DO UPDATE SET
  visited_at = NOW(),
  updated_at = NOW()
RETURNING
  id,
  type,
  object_id,
  user_id,
  visited_at,
  created_at,
  updated_at;

-- name: FindLiveShare :one
SELECT
  id,
  type,
  object_id,
  user_id,
  visited_at,
  created_at,
  updated_at
FROM shares
WHERE id = sqlc.arg(id) AND visited_at > NOW() - make_interval(days => sqlc.arg(lifetime_days)::int);

-- name: TouchShareVisit :exec
UPDATE shares SET visited_at = NOW() WHERE id = $1 AND visited_at < NOW() - INTERVAL '1 day';

-- name: DeleteExpiredShares :execrows
DELETE FROM shares WHERE visited_at <= NOW() - make_interval(days => sqlc.arg(lifetime_days)::int);
