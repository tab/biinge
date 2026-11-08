package services

import (
	"context"
	"testing"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories"
	"biinge-api/internal/config"
	"biinge-api/pkg/jellyfin"
)

// testJellyfinKey is a 32-byte AES-256 key for the Jellyfin token tests
const testJellyfinKey = "0123456789abcdef0123456789abcdef"

// newTestJellyfinConfig is a config with Jellyfin on and testJellyfinKey as the token key
func newTestJellyfinConfig() *config.Config {
	return &config.Config{
		Jellyfin: config.JellyfinConfig{BaseURL: "http://jellyfin.test", TokenKey: testJellyfinKey},
	}
}

func Test_Integrations_JellyfinNotConfigured(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockIntegrationRepository(ctrl)
	client := jellyfin.NewMockClient(ctrl)
	service := NewIntegrations(&config.Config{}, repository, client, NewMockPlayedMemory(ctrl), newTestLogger())

	userId := uuid.New()

	connection, err := service.Connect(ctx, userId, jellyfin.Credentials{Username: "alice", Password: "secret"})
	require.ErrorIs(t, err, errors.ErrJellyfinNotConfigured)
	assert.Nil(t, connection)

	connection, err = service.Status(ctx, userId)
	require.ErrorIs(t, err, errors.ErrJellyfinNotConfigured)
	assert.Nil(t, connection)

	err = service.Disconnect(ctx, userId)
	require.ErrorIs(t, err, errors.ErrJellyfinNotConfigured)
}

func Test_Integrations_Connect(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockIntegrationRepository(ctrl)
	client := jellyfin.NewMockClient(ctrl)
	memory := NewMockPlayedMemory(ctrl)
	service := NewIntegrations(newTestJellyfinConfig(), repository, client, memory, newTestLogger())

	userId := uuid.MustParse("11111111-2222-3333-4444-555555555555")
	deviceId := "biinge-api-11111111-2222-3333-4444-555555555555"
	credentials := jellyfin.Credentials{Username: "alice", Password: "secret"}
	session := &jellyfin.Session{AccessToken: "new-token", UserId: "jellyfin-user", UserName: "Alice"}
	earlier := &models.Integration{
		UserId:   userId,
		Provider: models.JellyfinProvider,
		Token:    encryptToken([]byte(testJellyfinKey), "old-token"),
	}
	connected := &models.JellyfinConnection{BaseURL: "http://jellyfin.test", Connected: true, Username: "Alice"}

	// expectUpsert checks the stored connection holds the new token only encrypted
	expectUpsert := func() *gomock.Call {
		return repository.EXPECT().
			UpsertConnection(ctx, gomock.Any()).
			DoAndReturn(func(_ context.Context, params *models.Integration) (*models.Integration, error) {
				assert.Equal(t, userId, params.UserId)
				assert.Equal(t, models.JellyfinProvider, params.Provider)
				assert.Equal(t, "jellyfin-user", params.ExternalUserId)
				assert.Equal(t, "Alice", params.Username)
				assert.NotContains(t, string(params.Token), "new-token")

				token, err := decryptToken([]byte(testJellyfinKey), params.Token)
				require.NoError(t, err)
				assert.Equal(t, "new-token", token)

				return params, nil
			})
	}

	tests := []struct {
		name     string
		before   func()
		expected *models.JellyfinConnection
		error    error
	}{
		{
			name: "First connect signs in with the user's device id and stores the encrypted token",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(nil, pgx.ErrNoRows)
				client.EXPECT().SignIn(ctx, deviceId, credentials).Return(session, nil)
				expectUpsert()
				memory.EXPECT().Forget(userId)
			},
			expected: connected,
		},
		{
			name: "Reconnect signs out the earlier token after storing the new one",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(earlier, nil)
				gomock.InOrder(
					client.EXPECT().SignIn(ctx, deviceId, credentials).Return(session, nil),
					expectUpsert(),
					memory.EXPECT().Forget(userId),
					client.EXPECT().SignOut(ctx, deviceId, "old-token").Return(nil),
				)
			},
			expected: connected,
		},
		{
			name: "Reconnect succeeds when the earlier sign-out fails",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(earlier, nil)
				client.EXPECT().SignIn(ctx, deviceId, credentials).Return(session, nil)
				expectUpsert()
				memory.EXPECT().Forget(userId)
				client.EXPECT().SignOut(ctx, deviceId, "old-token").Return(jellyfin.ErrUnavailable)
			},
			expected: connected,
		},
		{
			name: "Reconnect succeeds when the earlier token does not decrypt",
			before: func() {
				repository.EXPECT().
					FindByUser(ctx, userId, models.JellyfinProvider).
					Return(&models.Integration{UserId: userId, Token: []byte("not a sealed token")}, nil)
				client.EXPECT().SignIn(ctx, deviceId, credentials).Return(session, nil)
				expectUpsert()
				memory.EXPECT().Forget(userId)
			},
			expected: connected,
		},
		{
			name: "Wrong credentials keep the earlier connection",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(earlier, nil)
				client.EXPECT().SignIn(ctx, deviceId, credentials).Return(nil, jellyfin.ErrInvalidCredentials)
			},
			error: errors.ErrInvalidJellyfinCredentials,
		},
		{
			name: "Unavailable server keeps the earlier connection",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(earlier, nil)
				client.EXPECT().SignIn(ctx, deviceId, credentials).Return(nil, jellyfin.ErrUnavailable)
			},
			error: errors.ErrJellyfinUnavailable,
		},
		{
			name: "Save failure signs the new token out",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(earlier, nil)
				client.EXPECT().SignIn(ctx, deviceId, credentials).Return(session, nil)
				repository.EXPECT().UpsertConnection(ctx, gomock.Any()).Return(nil, assert.AnError)
				client.EXPECT().SignOut(ctx, deviceId, "new-token").Return(nil)
			},
			error: errors.ErrFailedToSaveJellyfinConnection,
		},
		{
			name: "Lookup failure",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(nil, assert.AnError)
			},
			error: errors.ErrFailedToSaveJellyfinConnection,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, err := service.Connect(ctx, userId, credentials)

			if tt.error != nil {
				require.ErrorIs(t, err, tt.error)
				assert.Nil(t, result)

				return
			}

			require.NoError(t, err)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func Test_Integrations_Status(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockIntegrationRepository(ctrl)
	service := NewIntegrations(newTestJellyfinConfig(), repository, jellyfin.NewMockClient(ctrl), NewMockPlayedMemory(ctrl), newTestLogger())

	userId := uuid.New()

	tests := []struct {
		name     string
		before   func()
		expected *models.JellyfinConnection
		error    error
	}{
		{
			name: "No row is disconnected",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(nil, pgx.ErrNoRows)
			},
			expected: &models.JellyfinConnection{BaseURL: "http://jellyfin.test"},
		},
		{
			name: "Connected row returns the username",
			before: func() {
				repository.EXPECT().
					FindByUser(ctx, userId, models.JellyfinProvider).
					Return(&models.Integration{
						UserId:         userId,
						ExternalUserId: "jellyfin-user",
						Username:       "Alice",
						Token:          []byte("sealed"),
					}, nil)
			},
			expected: &models.JellyfinConnection{BaseURL: "http://jellyfin.test", Connected: true, Username: "Alice"},
		},
		{
			name: "Repository failure",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(nil, assert.AnError)
			},
			error: errors.ErrFailedToFetchJellyfinConnection,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, err := service.Status(ctx, userId)

			if tt.error != nil {
				require.ErrorIs(t, err, tt.error)
				assert.Nil(t, result)

				return
			}

			require.NoError(t, err)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func Test_Integrations_Disconnect(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockIntegrationRepository(ctrl)
	client := jellyfin.NewMockClient(ctrl)
	memory := NewMockPlayedMemory(ctrl)
	service := NewIntegrations(newTestJellyfinConfig(), repository, client, memory, newTestLogger())

	userId := uuid.MustParse("11111111-2222-3333-4444-555555555555")
	deviceId := "biinge-api-11111111-2222-3333-4444-555555555555"
	connected := &models.Integration{
		UserId:   userId,
		Provider: models.JellyfinProvider,
		Token:    encryptToken([]byte(testJellyfinKey), "token"),
	}

	tests := []struct {
		name   string
		before func()
		error  error
	}{
		{
			name: "No row is a no-op",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(nil, pgx.ErrNoRows)
			},
		},
		{
			name: "Signs the token out then clears the connection",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(connected, nil)
				gomock.InOrder(
					client.EXPECT().SignOut(ctx, deviceId, "token").Return(nil),
					repository.EXPECT().ClearConnection(ctx, userId, models.JellyfinProvider).Return(nil),
				)
			},
		},
		{
			name: "Sign-out failure still clears the connection",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(connected, nil)
				client.EXPECT().SignOut(ctx, deviceId, "token").Return(jellyfin.ErrUnavailable)
				repository.EXPECT().ClearConnection(ctx, userId, models.JellyfinProvider).Return(nil)
			},
		},
		{
			name: "Clear failure",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(connected, nil)
				client.EXPECT().SignOut(ctx, deviceId, "token").Return(nil)
				repository.EXPECT().ClearConnection(ctx, userId, models.JellyfinProvider).Return(assert.AnError)
			},
			error: errors.ErrFailedToDeleteJellyfinConnection,
		},
		{
			name: "Lookup failure",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(nil, assert.AnError)
			},
			error: errors.ErrFailedToDeleteJellyfinConnection,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			err := service.Disconnect(ctx, userId)

			if tt.error != nil {
				require.ErrorIs(t, err, tt.error)
				return
			}

			require.NoError(t, err)
		})
	}
}

func Test_Integrations_TokenEncryption(t *testing.T) {
	key := []byte(testJellyfinKey)
	sealed := encryptToken(key, "token")

	// a reused GCM nonce breaks both secrecy and integrity, so each seal must differ
	again := encryptToken(key, "token")
	require.NotEqual(t, sealed, again)

	tampered := append([]byte{}, sealed...)
	tampered[len(tampered)-1] ^= 0xff

	tests := []struct {
		name     string
		key      []byte
		sealed   []byte
		expected string
		error    bool
	}{
		{
			name:     "Round trip",
			key:      key,
			sealed:   sealed,
			expected: "token",
		},
		{
			name:     "Second seal of the same token round-trips",
			key:      key,
			sealed:   again,
			expected: "token",
		},
		{
			name:   "Tampered byte fails",
			key:    key,
			sealed: tampered,
			error:  true,
		},
		{
			name:   "Different key fails",
			key:    []byte("fedcba9876543210fedcba9876543210"),
			sealed: sealed,
			error:  true,
		},
		{
			name:   "Bytes shorter than the nonce fail",
			key:    key,
			sealed: []byte("short"),
			error:  true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, err := decryptToken(tt.key, tt.sealed)

			if tt.error {
				require.Error(t, err)
				assert.Empty(t, result)

				return
			}

			require.NoError(t, err)
			assert.Equal(t, tt.expected, result)
			assert.Len(t, tt.sealed, 12+len("token")+16)
			assert.NotContains(t, string(tt.sealed), "token")
		})
	}
}
