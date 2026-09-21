package repositories

import (
	"context"

	"github.com/google/uuid"

	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories/db"
	"biinge-api/internal/app/repositories/postgres"
)

type IntegrationRepository interface {
	Upsert(ctx context.Context, params *models.Integration) (*models.Integration, error)
	FindByTokenHash(ctx context.Context, hash string, provider string) (*models.Integration, error)
	Delete(ctx context.Context, userId uuid.UUID, provider string) error
}

type integration struct {
	client postgres.Postgres
}

func NewIntegrationRepository(client postgres.Postgres) IntegrationRepository {
	return &integration{client: client}
}

func (i *integration) Upsert(ctx context.Context, params *models.Integration) (*models.Integration, error) {
	result, err := i.client.Queries().UpsertIntegration(ctx, db.UpsertIntegrationParams{
		UserID:    params.UserId,
		Provider:  db.ProviderType(params.Provider),
		TokenHash: params.TokenHash,
	})
	if err != nil {
		return nil, err
	}

	return &models.Integration{
		ID:        result.ID,
		UserId:    result.UserID,
		Provider:  string(result.Provider),
		TokenHash: result.TokenHash,
		CreatedAt: result.CreatedAt.Time,
		UpdatedAt: result.UpdatedAt.Time,
	}, nil
}

// FindByTokenHash returns the live owner's link for a token hash and provider, pgx.ErrNoRows when none or the owner is soft-deleted
func (i *integration) FindByTokenHash(ctx context.Context, hash string, provider string) (*models.Integration, error) {
	result, err := i.client.Queries().FindIntegrationByTokenHash(ctx, db.FindIntegrationByTokenHashParams{
		TokenHash: hash,
		Provider:  db.ProviderType(provider),
	})
	if err != nil {
		return nil, err
	}

	return &models.Integration{
		ID:        result.ID,
		UserId:    result.UserID,
		Provider:  string(result.Provider),
		TokenHash: result.TokenHash,
		CreatedAt: result.CreatedAt.Time,
		UpdatedAt: result.UpdatedAt.Time,
	}, nil
}

func (i *integration) Delete(ctx context.Context, userId uuid.UUID, provider string) error {
	return i.client.Queries().DeleteIntegration(ctx, db.DeleteIntegrationParams{
		UserID:   userId,
		Provider: db.ProviderType(provider),
	})
}
