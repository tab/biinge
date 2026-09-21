-- +goose Up
-- integrations links a user to an external media server by a bearer token. Only the
-- SHA-256 of the token is stored, so a leaked dump cannot replay it. Revoke is a hard delete.
CREATE TABLE IF NOT EXISTS integrations (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
  provider provider_type NOT NULL,
  token_hash CHAR(64) NOT NULL,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE UNIQUE INDEX IF NOT EXISTS integrations_user_id_provider_unique ON integrations(user_id, provider);
CREATE UNIQUE INDEX IF NOT EXISTS integrations_token_hash_unique ON integrations(token_hash);

-- +goose Down
DROP INDEX integrations_token_hash_unique;
DROP INDEX integrations_user_id_provider_unique;
DROP TABLE integrations;
