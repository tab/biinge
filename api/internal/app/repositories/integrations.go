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
	UpsertConnection(ctx context.Context, params *models.Integration) (*models.Integration, error)
	FindByTokenHash(ctx context.Context, hash string, provider string) (*models.Integration, error)
	FindByUser(ctx context.Context, userId uuid.UUID, provider string) (*models.Integration, error)
	ClearToken(ctx context.Context, userId uuid.UUID, provider string) error
	ClearConnection(ctx context.Context, userId uuid.UUID, provider string) error
}

type integration struct {
	client postgres.Postgres
}

func NewIntegrationRepository(client postgres.Postgres) IntegrationRepository {
	return &integration{client: client}
}

// Upsert stores the webhook token hash and keeps any connection on the row
func (i *integration) Upsert(ctx context.Context, params *models.Integration) (*models.Integration, error) {
	result, err := i.client.Queries().UpsertIntegration(ctx, db.UpsertIntegrationParams{
		UserID:    params.UserId,
		Provider:  db.ProviderType(params.Provider),
		TokenHash: &params.TokenHash,
	})
	if err != nil {
		return nil, err
	}

	return integrationFromRow(result), nil
}

// UpsertConnection stores the Jellyfin connection and keeps any webhook token on the row
func (i *integration) UpsertConnection(ctx context.Context, params *models.Integration) (*models.Integration, error) {
	result, err := i.client.Queries().UpsertJellyfinConnection(ctx, db.UpsertJellyfinConnectionParams{
		UserID:           params.UserId,
		Provider:         db.ProviderType(params.Provider),
		JellyfinUserID:   &params.JellyfinUserId,
		JellyfinUsername: &params.JellyfinUsername,
		JellyfinToken:    params.JellyfinToken,
	})
	if err != nil {
		return nil, err
	}

	return integrationFromRow(result), nil
}

// FindByTokenHash returns the live owner's link for a token hash and provider, pgx.ErrNoRows when none or the owner is soft-deleted
func (i *integration) FindByTokenHash(ctx context.Context, hash string, provider string) (*models.Integration, error) {
	result, err := i.client.Queries().FindIntegrationByTokenHash(ctx, db.FindIntegrationByTokenHashParams{
		TokenHash: &hash,
		Provider:  db.ProviderType(provider),
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

// ClearToken removes the webhook token, and the whole row when it holds no connection
func (i *integration) ClearToken(ctx context.Context, userId uuid.UUID, provider string) error {
	if err := i.client.Queries().ClearIntegrationToken(ctx, db.ClearIntegrationTokenParams{
		UserID:   userId,
		Provider: db.ProviderType(provider),
	}); err != nil {
		return err
	}

	return i.client.Queries().DeleteEmptyIntegration(ctx, db.DeleteEmptyIntegrationParams{
		UserID:   userId,
		Provider: db.ProviderType(provider),
	})
}

// ClearConnection removes the Jellyfin connection, and the whole row when it holds no webhook token
func (i *integration) ClearConnection(ctx context.Context, userId uuid.UUID, provider string) error {
	if err := i.client.Queries().ClearJellyfinConnection(ctx, db.ClearJellyfinConnectionParams{
		UserID:   userId,
		Provider: db.ProviderType(provider),
	}); err != nil {
		return err
	}

	return i.client.Queries().DeleteEmptyIntegration(ctx, db.DeleteEmptyIntegrationParams{
		UserID:   userId,
		Provider: db.ProviderType(provider),
	})
}

// integrationFromRow maps a stored row to the model, NULL columns to empty values
func integrationFromRow(row db.Integration) *models.Integration {
	return &models.Integration{
		ID:               row.ID,
		UserId:           row.UserID,
		Provider:         string(row.Provider),
		TokenHash:        stringValue(row.TokenHash),
		JellyfinUserId:   stringValue(row.JellyfinUserID),
		JellyfinUsername: stringValue(row.JellyfinUsername),
		JellyfinToken:    row.JellyfinToken,
		CreatedAt:        row.CreatedAt.Time,
		UpdatedAt:        row.UpdatedAt.Time,
	}
}
