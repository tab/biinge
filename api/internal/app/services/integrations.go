package services

import (
	"context"
	"crypto/aes"
	"crypto/cipher"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories"
	"biinge-api/internal/config"
	"biinge-api/internal/config/logger"
	"biinge-api/pkg/jellyfin"
)

// Integrations holds each user's Jellyfin connection
type Integrations interface {
	Connect(ctx context.Context, userId uuid.UUID, credentials jellyfin.Credentials) (*models.JellyfinConnection, error)
	Status(ctx context.Context, userId uuid.UUID) (*models.JellyfinConnection, error)
	Disconnect(ctx context.Context, userId uuid.UUID) error
}

type integrations struct {
	cfg        *config.Config
	repository repositories.IntegrationRepository
	client     jellyfin.Client
	memory     PlayedMemory
	log        *logger.Logger
}

func NewIntegrations(
	cfg *config.Config,
	repository repositories.IntegrationRepository,
	client jellyfin.Client,
	memory PlayedMemory,
	log *logger.Logger,
) Integrations {
	return &integrations{
		cfg:        cfg,
		repository: repository,
		client:     client,
		memory:     memory,
		log:        log.WithComponent("IntegrationsService"),
	}
}

// Connect signs the user in to Jellyfin, stores the encrypted token, drops the previous played read and signs out any earlier token (a failed sign-in keeps the earlier connection)
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
		UserId:         userId,
		Provider:       models.JellyfinProvider,
		ExternalUserId: session.UserId,
		Username:       session.UserName,
		Token:          encryptToken(key, session.AccessToken),
	}); err != nil {
		i.log.Error().Err(err).Msg("Failed to save Jellyfin connection")

		// best-effort, so no device stays on the server for a connection that was never stored
		if signOutErr := i.client.SignOut(ctx, deviceId, session.AccessToken); signOutErr != nil {
			i.log.Warn().Err(signOutErr).Msg("Failed to sign out unsaved Jellyfin token")
		}

		return nil, errors.ErrFailedToSaveJellyfinConnection
	}

	// the next sync pass is a first pass, which records the new connection's read and reconciles it
	i.memory.Forget(userId)

	connection := &models.JellyfinConnection{
		BaseURL:   i.cfg.Jellyfin.BaseURL,
		Connected: true,
		Username:  session.UserName,
	}

	if existing == nil {
		return connection, nil
	}

	// best-effort, the new connection is stored either way
	token, err := decryptToken(key, existing.Token)
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

	return &models.JellyfinConnection{
		BaseURL:   i.cfg.Jellyfin.BaseURL,
		Connected: true,
		Username:  result.Username,
	}, nil
}

// Disconnect signs the token out of Jellyfin best-effort and clears the connection
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

	// a failed sign-out still clears the connection, leaving only a stale device on the server
	token, signOutErr := decryptToken([]byte(i.cfg.Jellyfin.TokenKey), result.Token)
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
