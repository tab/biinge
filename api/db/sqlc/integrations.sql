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
  updated_at,
  jellyfin_user_id,
  jellyfin_username,
  jellyfin_token;

-- name: UpsertJellyfinConnection :one
INSERT INTO integrations (
  user_id,
  provider,
  jellyfin_user_id,
  jellyfin_username,
  jellyfin_token
) VALUES (
  $1, $2, $3, $4, $5
)
ON CONFLICT (user_id, provider) DO UPDATE SET
  jellyfin_user_id = EXCLUDED.jellyfin_user_id,
  jellyfin_username = EXCLUDED.jellyfin_username,
  jellyfin_token = EXCLUDED.jellyfin_token,
  updated_at = NOW()
RETURNING
  id,
  user_id,
  provider,
  token_hash,
  created_at,
  updated_at,
  jellyfin_user_id,
  jellyfin_username,
  jellyfin_token;

-- name: FindIntegrationByTokenHash :one
SELECT
  i.id,
  i.user_id,
  i.provider,
  i.token_hash,
  i.created_at,
  i.updated_at,
  i.jellyfin_user_id,
  i.jellyfin_username,
  i.jellyfin_token
FROM integrations i
  JOIN users u ON u.id = i.user_id
WHERE i.token_hash = $1 AND i.provider = $2 AND u.deleted_at IS NULL LIMIT 1;

-- name: FindIntegrationByUser :one
SELECT
  id,
  user_id,
  provider,
  token_hash,
  created_at,
  updated_at,
  jellyfin_user_id,
  jellyfin_username,
  jellyfin_token
FROM integrations
WHERE user_id = $1 AND provider = $2;

-- name: ClearIntegrationToken :exec
UPDATE integrations SET token_hash = NULL, updated_at = NOW() WHERE user_id = $1 AND provider = $2;

-- name: ClearJellyfinConnection :exec
UPDATE integrations SET
  jellyfin_user_id = NULL,
  jellyfin_username = NULL,
  jellyfin_token = NULL,
  updated_at = NOW()
WHERE user_id = $1 AND provider = $2;

-- name: DeleteEmptyIntegration :exec
DELETE FROM integrations
WHERE user_id = $1 AND provider = $2 AND token_hash IS NULL AND jellyfin_token IS NULL;
