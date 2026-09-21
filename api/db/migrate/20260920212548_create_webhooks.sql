-- +goose Up
-- webhooks keeps every accepted event with what biinge did about it, so a wrong or
-- missing mark can be traced back to the payload that caused it
CREATE TABLE IF NOT EXISTS webhooks (
  id UUID PRIMARY KEY DEFAULT uuid_generate_v4(),
  integration_id UUID NOT NULL REFERENCES integrations(id) ON DELETE CASCADE,
  payload JSONB NOT NULL,
  status status_type NOT NULL,
  error TEXT,
  created_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMPTZ NOT NULL DEFAULT CURRENT_TIMESTAMP
);

CREATE INDEX IF NOT EXISTS webhooks_integration_id_created_at_idx ON webhooks(integration_id, created_at);

-- +goose Down
DROP INDEX webhooks_integration_id_created_at_idx;
DROP TABLE webhooks;
