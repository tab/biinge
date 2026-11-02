-- +goose Up
-- The connection is the API's own Jellyfin sign-in for the user. Its token is AES-GCM encrypted under
-- JELLYFIN_TOKEN_KEY, because the API sends it to Jellyfin. The webhook token and the connection are
-- independent, so either may be NULL; a row with neither is deleted.
ALTER TABLE integrations
  ALTER COLUMN token_hash DROP NOT NULL,
  ADD COLUMN jellyfin_user_id TEXT,
  ADD COLUMN jellyfin_username TEXT,
  ADD COLUMN jellyfin_token BYTEA;

-- +goose Down
DELETE FROM integrations WHERE token_hash IS NULL;

ALTER TABLE integrations
  DROP COLUMN jellyfin_token,
  DROP COLUMN jellyfin_username,
  DROP COLUMN jellyfin_user_id,
  ALTER COLUMN token_hash SET NOT NULL;
