package repositories

import (
	"context"

	"github.com/jackc/pgx/v5/pgtype"

	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories/db"
	"biinge-api/internal/app/repositories/postgres"
)

type WebhookRepository interface {
	Create(ctx context.Context, params *models.Webhook) error
}

type webhook struct {
	client postgres.Postgres
}

func NewWebhookRepository(client postgres.Postgres) WebhookRepository {
	return &webhook{client: client}
}

func (w *webhook) Create(ctx context.Context, params *models.Webhook) error {
	return w.client.Queries().CreateWebhook(ctx, db.CreateWebhookParams{
		IntegrationID: params.IntegrationId,
		Payload:       params.Payload,
		Status:        db.StatusType(params.Status),
		Error:         pgtype.Text{String: params.Error, Valid: params.Error != ""},
	})
}
