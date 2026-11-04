-- name: UpsertIntegration :one
INSERT INTO integrations (
  user_id,
  provider,
  external_user_id,
  username,
  token
) VALUES (
  $1, $2, $3, $4, $5
)
ON CONFLICT (user_id, provider) DO UPDATE SET
  external_user_id = EXCLUDED.external_user_id,
  username = EXCLUDED.username,
  token = EXCLUDED.token,
  updated_at = NOW()
RETURNING
  id,
  user_id,
  provider,
  external_user_id,
  username,
  token,
  created_at,
  updated_at;

-- name: FindIntegrationByUser :one
SELECT
  id,
  user_id,
  provider,
  external_user_id,
  username,
  token,
  created_at,
  updated_at
FROM integrations
WHERE user_id = $1 AND provider = $2;

-- name: DeleteIntegration :exec
DELETE FROM integrations WHERE user_id = $1 AND provider = $2;
