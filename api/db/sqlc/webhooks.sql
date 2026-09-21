-- name: CreateWebhook :exec
INSERT INTO webhooks (
  integration_id,
  payload,
  status,
  error
) VALUES (
  $1, $2, $3, $4
);
