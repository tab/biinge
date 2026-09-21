package services

import (
	"context"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories"
	"biinge-api/internal/config/logger"
)

// Integrations issues, revokes and checks the bearer tokens external media servers use
type Integrations interface {
	CreateToken(ctx context.Context, userId uuid.UUID) (string, error)
	Revoke(ctx context.Context, userId uuid.UUID) error
	Authenticate(ctx context.Context, token string) (*models.Integration, error)
}

type integrations struct {
	repository repositories.IntegrationRepository
	log        *logger.Logger
}

func NewIntegrations(repository repositories.IntegrationRepository, log *logger.Logger) Integrations {
	return &integrations{
		repository: repository,
		log:        log.WithComponent("IntegrationsService"),
	}
}

// CreateToken links Jellyfin to the user with a fresh token, replacing any earlier one, and returns the plaintext once
func (i *integrations) CreateToken(ctx context.Context, userId uuid.UUID) (string, error) {
	// crypto/rand.Read never returns an error (it stops the process instead)
	raw := make([]byte, 32)
	_, _ = rand.Read(raw)

	token := hex.EncodeToString(raw)

	if _, err := i.repository.Upsert(ctx, &models.Integration{
		UserId:    userId,
		Provider:  models.JellyfinProvider,
		TokenHash: hashToken(token),
	}); err != nil {
		i.log.Error().Err(err).Msg("Failed to create integration token")
		return "", errors.ErrFailedToCreateIntegration
	}

	return token, nil
}

func (i *integrations) Revoke(ctx context.Context, userId uuid.UUID) error {
	if err := i.repository.Delete(ctx, userId, models.JellyfinProvider); err != nil {
		i.log.Error().Err(err).Msg("Failed to revoke integration")
		return errors.ErrFailedToDeleteIntegration
	}

	return nil
}

// Authenticate finds the live link holding the token, ErrUnauthorized when none (the token itself is never logged)
func (i *integrations) Authenticate(ctx context.Context, token string) (*models.Integration, error) {
	result, err := i.repository.FindByTokenHash(ctx, hashToken(token), models.JellyfinProvider)
	if err != nil {
		// an unknown or revoked token is the ordinary failure, not a datastore one
		if errors.Is(err, pgx.ErrNoRows) {
			return nil, errors.ErrUnauthorized
		}

		i.log.Error().Err(err).Msg("Failed to authenticate integration")

		return nil, errors.ErrFailedToAuthenticateIntegration
	}

	return result, nil
}

// hashToken is the SHA-256 hex digest stored in place of the plaintext token
func hashToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}
