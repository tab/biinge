-- name: UpsertIntegration :one
INSERT INTO integrations (
  user_id,
  provider,
  token_hash
) VALUES (
  $1, $2, $3
)
ON CONFLICT (user_id, provider) DO UPDATE SET
  token_hash = EXCLUDED.token_hash,
  updated_at = NOW()
RETURNING
  id,
  user_id,
  provider,
  token_hash,
  created_at,
  updated_at;

-- name: FindIntegrationByTokenHash :one
SELECT
  i.id,
  i.user_id,
  i.provider,
  i.token_hash,
  i.created_at,
  i.updated_at
FROM integrations i
  JOIN users u ON u.id = i.user_id
WHERE i.token_hash = $1 AND i.provider = $2 AND u.deleted_at IS NULL LIMIT 1;

-- name: DeleteIntegration :exec
DELETE FROM integrations WHERE user_id = $1 AND provider = $2;
