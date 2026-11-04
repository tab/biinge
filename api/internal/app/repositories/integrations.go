package repositories

import (
	"context"

	"github.com/google/uuid"

	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories/db"
	"biinge-api/internal/app/repositories/postgres"
)

type IntegrationRepository interface {
	UpsertConnection(ctx context.Context, params *models.Integration) (*models.Integration, error)
	FindByUser(ctx context.Context, userId uuid.UUID, provider string) (*models.Integration, error)
	ClearConnection(ctx context.Context, userId uuid.UUID, provider string) error
}

type integration struct {
	client postgres.Postgres
}

func NewIntegrationRepository(client postgres.Postgres) IntegrationRepository {
	return &integration{client: client}
}

// UpsertConnection stores the provider connection, replacing any earlier one
func (i *integration) UpsertConnection(ctx context.Context, params *models.Integration) (*models.Integration, error) {
	result, err := i.client.Queries().UpsertIntegration(ctx, db.UpsertIntegrationParams{
		UserID:         params.UserId,
		Provider:       db.ProviderType(params.Provider),
		ExternalUserID: params.ExternalUserId,
		Username:       params.Username,
		Token:          params.Token,
	})
	if err != nil {
		return nil, err
	}

	return integrationFromRow(result), nil
}

// FindByUser returns the user's link for a provider, pgx.ErrNoRows when none
func (i *integration) FindByUser(ctx context.Context, userId uuid.UUID, provider string) (*models.Integration, error) {
	result, err := i.client.Queries().FindIntegrationByUser(ctx, db.FindIntegrationByUserParams{
		UserID:   userId,
		Provider: db.ProviderType(provider),
	})
	if err != nil {
		return nil, err
	}

	return integrationFromRow(result), nil
}

// ClearConnection deletes the user's link for a provider (no error when there is none)
func (i *integration) ClearConnection(ctx context.Context, userId uuid.UUID, provider string) error {
	return i.client.Queries().DeleteIntegration(ctx, db.DeleteIntegrationParams{
		UserID:   userId,
		Provider: db.ProviderType(provider),
	})
}

// integrationFromRow maps a stored row to the model
func integrationFromRow(row db.Integration) *models.Integration {
	return &models.Integration{
		ID:             row.ID,
		UserId:         row.UserID,
		Provider:       string(row.Provider),
		ExternalUserId: row.ExternalUserID,
		Username:       row.Username,
		Token:          row.Token,
		CreatedAt:      row.CreatedAt.Time,
		UpdatedAt:      row.UpdatedAt.Time,
	}
}
