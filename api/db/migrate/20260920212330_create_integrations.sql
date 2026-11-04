-- +goose Up
-- integrations holds the API's own sign-in to a user's media server. The token is the provider's access
-- token, AES-GCM encrypted under JELLYFIN_TOKEN_KEY, because the API sends it to the provider.
-- Disconnect deletes the row.
CREATE TABLE IF NOT EXISTS integrations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider provider_type NOT NULL,
  external_user_id TEXT NOT NULL,
  username TEXT NOT NULL,
  token BYTEA NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX IF NOT EXISTS integrations_user_id_provider_unique ON integrations(user_id, provider);

-- +goose Down
DROP INDEX integrations_user_id_provider_unique;
DROP TABLE integrations;
