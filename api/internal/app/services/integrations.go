package services

import (
	"context"
	"crypto/aes"
	"crypto/cipher"
	"crypto/rand"
	"crypto/sha256"
	"encoding/hex"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories"
	"biinge-api/internal/config"
	"biinge-api/internal/config/logger"
	"biinge-api/pkg/jellyfin"
)

// Integrations issues, revokes and checks the webhook bearer tokens, and holds each user's Jellyfin connection
type Integrations interface {
	CreateToken(ctx context.Context, userId uuid.UUID) (string, error)
	Revoke(ctx context.Context, userId uuid.UUID) error
	Authenticate(ctx context.Context, token string) (*models.Integration, error)
	Connect(ctx context.Context, userId uuid.UUID, credentials jellyfin.Credentials) (*models.JellyfinConnection, error)
	Status(ctx context.Context, userId uuid.UUID) (*models.JellyfinConnection, error)
	Disconnect(ctx context.Context, userId uuid.UUID) error
}

type integrations struct {
	cfg        *config.Config
	repository repositories.IntegrationRepository
	client     jellyfin.Client
	log        *logger.Logger
}

func NewIntegrations(
	cfg *config.Config,
	repository repositories.IntegrationRepository,
	client jellyfin.Client,
	log *logger.Logger,
) Integrations {
	return &integrations{
		cfg:        cfg,
		repository: repository,
		client:     client,
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
	if err := i.repository.ClearToken(ctx, userId, models.JellyfinProvider); err != nil {
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

// Connect signs the user in to Jellyfin, stores the encrypted token and signs out any earlier one (a failed sign-in keeps the earlier connection)
func (i *integrations) Connect(
	ctx context.Context,
	userId uuid.UUID,
	credentials jellyfin.Credentials,
) (*models.JellyfinConnection, error) {
	if i.cfg.Jellyfin.BaseURL == "" {
		return nil, errors.ErrJellyfinNotConfigured
	}

	// a missing row means no earlier connection
	existing, err := i.repository.FindByUser(ctx, userId, models.JellyfinProvider)
	if err != nil && !errors.Is(err, pgx.ErrNoRows) {
		i.log.Error().Err(err).Msg("Failed to fetch Jellyfin connection")
		return nil, errors.ErrFailedToSaveJellyfinConnection
	}

	deviceId := "biinge-api-" + userId.String()

	// the client already logged the failure, without the password
	session, err := i.client.SignIn(ctx, deviceId, credentials)
	if err != nil {
		if errors.Is(err, jellyfin.ErrInvalidCredentials) {
			return nil, errors.ErrInvalidJellyfinCredentials
		}

		return nil, errors.ErrJellyfinUnavailable
	}

	key := []byte(i.cfg.Jellyfin.TokenKey)

	if _, err = i.repository.UpsertConnection(ctx, &models.Integration{
		UserId:           userId,
		Provider:         models.JellyfinProvider,
		JellyfinUserId:   session.UserId,
		JellyfinUsername: session.UserName,
		JellyfinToken:    encryptToken(key, session.AccessToken),
	}); err != nil {
		i.log.Error().Err(err).Msg("Failed to save Jellyfin connection")

		// best-effort, so no device stays on the server for a connection that was never stored
		if signOutErr := i.client.SignOut(ctx, deviceId, session.AccessToken); signOutErr != nil {
			i.log.Warn().Err(signOutErr).Msg("Failed to sign out unsaved Jellyfin token")
		}

		return nil, errors.ErrFailedToSaveJellyfinConnection
	}

	connection := &models.JellyfinConnection{
		BaseURL:   i.cfg.Jellyfin.BaseURL,
		Connected: true,
		Username:  session.UserName,
	}

	if existing == nil || len(existing.JellyfinToken) == 0 {
		return connection, nil
	}

	// best-effort, the new connection is stored either way
	token, err := decryptToken(key, existing.JellyfinToken)
	if err == nil {
		err = i.client.SignOut(ctx, deviceId, token)
	}

	if err != nil {
		i.log.Warn().Err(err).Msg("Failed to sign out earlier Jellyfin token")
	}

	return connection, nil
}

// Status reports the server address and whether the user is connected (it never returns the token)
func (i *integrations) Status(ctx context.Context, userId uuid.UUID) (*models.JellyfinConnection, error) {
	if i.cfg.Jellyfin.BaseURL == "" {
		return nil, errors.ErrJellyfinNotConfigured
	}

	result, err := i.repository.FindByUser(ctx, userId, models.JellyfinProvider)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return &models.JellyfinConnection{BaseURL: i.cfg.Jellyfin.BaseURL}, nil
		}

		i.log.Error().Err(err).Msg("Failed to fetch Jellyfin connection")

		return nil, errors.ErrFailedToFetchJellyfinConnection
	}

	// a row with only the webhook token is not a connection
	if len(result.JellyfinToken) == 0 {
		return &models.JellyfinConnection{BaseURL: i.cfg.Jellyfin.BaseURL}, nil
	}

	return &models.JellyfinConnection{
		BaseURL:   i.cfg.Jellyfin.BaseURL,
		Connected: true,
		Username:  result.JellyfinUsername,
	}, nil
}

// Disconnect signs the token out of Jellyfin best-effort and clears the connection, keeping the webhook token
func (i *integrations) Disconnect(ctx context.Context, userId uuid.UUID) error {
	if i.cfg.Jellyfin.BaseURL == "" {
		return errors.ErrJellyfinNotConfigured
	}

	result, err := i.repository.FindByUser(ctx, userId, models.JellyfinProvider)
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return nil
		}

		i.log.Error().Err(err).Msg("Failed to fetch Jellyfin connection")

		return errors.ErrFailedToDeleteJellyfinConnection
	}

	if len(result.JellyfinToken) == 0 {
		return nil
	}

	// a failed sign-out still clears the connection, leaving only a stale device on the server
	token, signOutErr := decryptToken([]byte(i.cfg.Jellyfin.TokenKey), result.JellyfinToken)
	if signOutErr == nil {
		signOutErr = i.client.SignOut(ctx, "biinge-api-"+userId.String(), token)
	}

	if signOutErr != nil {
		i.log.Warn().Err(signOutErr).Msg("Failed to sign out Jellyfin token")
	}

	if err = i.repository.ClearConnection(ctx, userId, models.JellyfinProvider); err != nil {
		i.log.Error().Err(err).Msg("Failed to clear Jellyfin connection")
		return errors.ErrFailedToDeleteJellyfinConnection
	}

	return nil
}

// encryptToken seals a Jellyfin token with AES-256-GCM under key (the random 12-byte nonce leads the result)
func encryptToken(key []byte, token string) []byte {
	// the key length is checked at startup, so neither constructor can fail
	block, _ := aes.NewCipher(key)
	aead, _ := cipher.NewGCMWithRandomNonce(block)

	//nolint:gosec // G407 misreads the nil nonce: NewGCMWithRandomNonce draws a random one and prepends it
	return aead.Seal(nil, nil, []byte(token), nil)
}

// decryptToken opens a token sealed by encryptToken, an error when the bytes were altered or the key differs
func decryptToken(key []byte, sealed []byte) (string, error) {
	// the key length is checked at startup, so neither constructor can fail
	block, _ := aes.NewCipher(key)
	aead, _ := cipher.NewGCMWithRandomNonce(block)

	token, err := aead.Open(nil, nil, sealed, nil)
	if err != nil {
		return "", err
	}

	return string(token), nil
}

// hashToken is the SHA-256 hex digest stored in place of the plaintext token
func hashToken(token string) string {
	sum := sha256.Sum256([]byte(token))
	return hex.EncodeToString(sum[:])
}
