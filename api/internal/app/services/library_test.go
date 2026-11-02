package services

import (
	"context"
	"fmt"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"

	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories"
	"biinge-api/internal/config"
	"biinge-api/internal/config/cache"
	"biinge-api/pkg/jellyfin"
)

// libraryToken is the plaintext Jellyfin token the library tests seal into the integration row
const libraryToken = "jellyfin-token"

// libraryConnection is the integration row of a user connected as the given Jellyfin user
func libraryConnection(userId uuid.UUID, jellyfinUserId string) *models.Integration {
	return &models.Integration{
		UserId:         userId,
		Provider:       models.JellyfinProvider,
		JellyfinUserId: jellyfinUserId,
		JellyfinToken:  encryptToken([]byte(testJellyfinKey), libraryToken),
	}
}

func Test_Library_Movie(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockIntegrationRepository(ctrl)
	client := jellyfin.NewMockClient(ctrl)
	service := NewLibrary(newTestJellyfinConfig(), repository, client, cache.NewNoopCache(), newTestLogger())

	userId := uuid.New()
	connection := jellyfin.Connection{DeviceId: "biinge-api-" + userId.String(), AccessToken: libraryToken, UserId: "jf-user"}

	tests := []struct {
		name     string
		before   func()
		expected string
	}{
		{
			name: "Unique match",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil)
				client.EXPECT().Items(ctx, connection).Return([]jellyfin.Item{
					{Id: "movie", Type: jellyfin.ItemTypeMovie, TmdbId: "603"},
					{Id: "other", Type: jellyfin.ItemTypeMovie, TmdbId: "604"},
				}, nil)
			},
			expected: "movie",
		},
		{
			name: "No match",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil)
				client.EXPECT().Items(ctx, connection).Return([]jellyfin.Item{
					{Id: "other", Type: jellyfin.ItemTypeMovie, TmdbId: "604"},
				}, nil)
			},
		},
		{
			name: "Series with the same TMDB id is not a movie",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil)
				client.EXPECT().Items(ctx, connection).Return([]jellyfin.Item{
					{Id: "series", Type: jellyfin.ItemTypeSeries, TmdbId: "603"},
				}, nil)
			},
		},
		{
			name: "Duplicate TMDB id",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil)
				client.EXPECT().Items(ctx, connection).Return([]jellyfin.Item{
					{Id: "first", Type: jellyfin.ItemTypeMovie, TmdbId: "603"},
					{Id: "second", Type: jellyfin.ItemTypeMovie, TmdbId: "603"},
					{Id: "third", Type: jellyfin.ItemTypeMovie, TmdbId: "603"},
				}, nil)
			},
		},
		{
			name: "Item without a TMDB id is ignored",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil)
				client.EXPECT().Items(ctx, connection).Return([]jellyfin.Item{
					{Id: "untagged", Type: jellyfin.ItemTypeMovie},
					{Id: "movie", Type: jellyfin.ItemTypeMovie, TmdbId: "603"},
				}, nil)
			},
			expected: "movie",
		},
		{
			name: "No integration row",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(nil, pgx.ErrNoRows)
			},
		},
		{
			name: "Repository failure",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(nil, assert.AnError)
			},
		},
		{
			name: "Row without a connection token",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(&models.Integration{UserId: userId, TokenHash: "hash"}, nil)
			},
		},
		{
			name: "Token that does not decrypt",
			before: func() {
				row := libraryConnection(userId, "jf-user")
				row.JellyfinToken[len(row.JellyfinToken)-1] ^= 0xff

				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(row, nil)
			},
		},
		{
			name: "Jellyfin rejects the token",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil)
				client.EXPECT().Items(ctx, connection).Return(nil, jellyfin.ErrInvalidCredentials)
			},
		},
		{
			name: "Jellyfin unavailable",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil)
				client.EXPECT().Items(ctx, connection).Return(nil, jellyfin.ErrUnavailable)
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			assert.Equal(t, tt.expected, service.Movie(ctx, userId, 603))
		})
	}
}

func Test_Library_Series(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockIntegrationRepository(ctrl)
	client := jellyfin.NewMockClient(ctrl)
	service := NewLibrary(newTestJellyfinConfig(), repository, client, cache.NewNoopCache(), newTestLogger())

	userId := uuid.New()
	connection := jellyfin.Connection{DeviceId: "biinge-api-" + userId.String(), AccessToken: libraryToken, UserId: "jf-user"}

	tests := []struct {
		name     string
		items    []jellyfin.Item
		expected string
	}{
		{
			name: "Unique match",
			items: []jellyfin.Item{
				{Id: "series", Type: jellyfin.ItemTypeSeries, TmdbId: "1399"},
				{Id: "other", Type: jellyfin.ItemTypeSeries, TmdbId: "1400"},
			},
			expected: "series",
		},
		{
			name: "No match",
			items: []jellyfin.Item{
				{Id: "other", Type: jellyfin.ItemTypeSeries, TmdbId: "1400"},
			},
		},
		{
			name: "Movie with the same TMDB id is not a series",
			items: []jellyfin.Item{
				{Id: "movie", Type: jellyfin.ItemTypeMovie, TmdbId: "1399"},
			},
		},
		{
			name: "Duplicate TMDB id",
			items: []jellyfin.Item{
				{Id: "first", Type: jellyfin.ItemTypeSeries, TmdbId: "1399"},
				{Id: "second", Type: jellyfin.ItemTypeSeries, TmdbId: "1399"},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil)
			client.EXPECT().Items(ctx, connection).Return(tt.items, nil)

			assert.Equal(t, tt.expected, service.Series(ctx, userId, 1399))
		})
	}
}

func Test_Library_Episodes(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockIntegrationRepository(ctrl)
	client := jellyfin.NewMockClient(ctrl)
	service := NewLibrary(newTestJellyfinConfig(), repository, client, cache.NewNoopCache(), newTestLogger())

	userId := uuid.New()
	connection := jellyfin.Connection{DeviceId: "biinge-api-" + userId.String(), AccessToken: libraryToken, UserId: "jf-user"}
	one, two := 1, 2
	series := []jellyfin.Item{{Id: "series", Type: jellyfin.ItemTypeSeries, TmdbId: "1399"}}

	tests := []struct {
		name     string
		before   func()
		expected map[uint64]string
	}{
		{
			name: "Unique episodes of the season",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil)
				client.EXPECT().Items(ctx, connection).Return(series, nil)
				client.EXPECT().Episodes(ctx, connection, "series").Return([]jellyfin.Episode{
					{Id: "s1e1", Season: &one, Number: &one},
					{Id: "s1e2", Season: &one, Number: &two},
					{Id: "s2e1", Season: &two, Number: &one},
				}, nil)
			},
			expected: map[uint64]string{1: "s1e1", 2: "s1e2"},
		},
		{
			name: "Season missing from the library",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil)
				client.EXPECT().Items(ctx, connection).Return(series, nil)
				client.EXPECT().Episodes(ctx, connection, "series").Return([]jellyfin.Episode{
					{Id: "s2e1", Season: &two, Number: &one},
				}, nil)
			},
		},
		{
			name: "Duplicate season and number",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil)
				client.EXPECT().Items(ctx, connection).Return(series, nil)
				client.EXPECT().Episodes(ctx, connection, "series").Return([]jellyfin.Episode{
					{Id: "first", Season: &one, Number: &one},
					{Id: "second", Season: &one, Number: &one},
					{Id: "third", Season: &one, Number: &one},
					{Id: "s1e2", Season: &one, Number: &two},
				}, nil)
			},
			expected: map[uint64]string{2: "s1e2"},
		},
		{
			name: "Episodes without a season or number are ignored",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil)
				client.EXPECT().Items(ctx, connection).Return(series, nil)
				client.EXPECT().Episodes(ctx, connection, "series").Return([]jellyfin.Episode{
					{Id: "no-season", Number: &one},
					{Id: "no-number", Season: &one},
					{Id: "s1e1", Season: &one, Number: &one},
				}, nil)
			},
			expected: map[uint64]string{1: "s1e1"},
		},
		{
			name: "Series not matched reads no episodes",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil)
				client.EXPECT().Items(ctx, connection).Return([]jellyfin.Item{
					{Id: "other", Type: jellyfin.ItemTypeSeries, TmdbId: "1400"},
				}, nil)
			},
		},
		{
			name: "No integration row",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(nil, pgx.ErrNoRows)
			},
		},
		{
			name: "Jellyfin unavailable for the library",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil)
				client.EXPECT().Items(ctx, connection).Return(nil, jellyfin.ErrUnavailable)
			},
		},
		{
			name: "Jellyfin rejects the token for the episodes",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil)
				client.EXPECT().Items(ctx, connection).Return(series, nil)
				client.EXPECT().Episodes(ctx, connection, "series").Return(nil, jellyfin.ErrInvalidCredentials)
			},
		},
		{
			name: "Jellyfin unavailable for the episodes",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil)
				client.EXPECT().Items(ctx, connection).Return(series, nil)
				client.EXPECT().Episodes(ctx, connection, "series").Return(nil, jellyfin.ErrUnavailable)
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			assert.Equal(t, tt.expected, service.Episodes(ctx, userId, 1399, 1))
		})
	}
}

func Test_Library_JellyfinNotConfigured(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	cfg := &config.Config{Jellyfin: config.JellyfinConfig{TokenKey: testJellyfinKey}}
	service := NewLibrary(cfg, repositories.NewMockIntegrationRepository(ctrl), jellyfin.NewMockClient(ctrl), cache.NewNoopCache(), newTestLogger())

	userId := uuid.New()

	assert.Empty(t, service.Movie(ctx, userId, 603))
	assert.Empty(t, service.Series(ctx, userId, 1399))
	assert.Nil(t, service.Episodes(ctx, userId, 1399, 1))
}

func Test_Library_Cache(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockIntegrationRepository(ctrl)
	client := jellyfin.NewMockClient(ctrl)
	store := newMemoryCache()
	service := NewLibrary(newTestJellyfinConfig(), repository, client, store, newTestLogger())

	one := 1
	series := []jellyfin.Item{{Id: "series", Type: jellyfin.ItemTypeSeries, TmdbId: "1399"}}
	episodes := []jellyfin.Episode{{Id: "s1e1", Season: &one, Number: &one}}

	tests := []struct {
		name     string
		before   func(userId uuid.UUID, connection jellyfin.Connection)
		expected []map[uint64]string
	}{
		{
			name: "Second lookup reads Jellyfin no more",
			before: func(userId uuid.UUID, connection jellyfin.Connection) {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil).Times(2)
				client.EXPECT().Items(ctx, connection).Return(series, nil)
				client.EXPECT().Episodes(ctx, connection, "series").Return(episodes, nil)
			},
			expected: []map[uint64]string{{1: "s1e1"}, {1: "s1e1"}},
		},
		{
			name: "Library failure is not cached",
			before: func(userId uuid.UUID, connection jellyfin.Connection) {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil).Times(2)
				gomock.InOrder(
					client.EXPECT().Items(ctx, connection).Return(nil, jellyfin.ErrUnavailable),
					client.EXPECT().Items(ctx, connection).Return(series, nil),
				)
				client.EXPECT().Episodes(ctx, connection, "series").Return(episodes, nil)
			},
			expected: []map[uint64]string{nil, {1: "s1e1"}},
		},
		{
			name: "Episodes failure is not cached",
			before: func(userId uuid.UUID, connection jellyfin.Connection) {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil).Times(2)
				client.EXPECT().Items(ctx, connection).Return(series, nil)
				gomock.InOrder(
					client.EXPECT().Episodes(ctx, connection, "series").Return(nil, jellyfin.ErrUnavailable),
					client.EXPECT().Episodes(ctx, connection, "series").Return(episodes, nil),
				)
			},
			expected: []map[uint64]string{nil, {1: "s1e1"}},
		},
		{
			name: "Another Jellyfin user reads its own library",
			before: func(userId uuid.UUID, connection jellyfin.Connection) {
				other := connection
				other.UserId = "jf-other"

				gomock.InOrder(
					repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil),
					repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-other"), nil),
				)
				client.EXPECT().Items(ctx, connection).Return(series, nil)
				// Jellyfin item ids are server-wide, so both users see the same series id
				client.EXPECT().Items(ctx, other).Return(series, nil)
				client.EXPECT().Episodes(ctx, connection, "series").Return(episodes, nil)
				client.EXPECT().Episodes(ctx, other, "series").Return([]jellyfin.Episode{{Id: "other-s1e1", Season: &one, Number: &one}}, nil)
			},
			expected: []map[uint64]string{{1: "s1e1"}, {1: "other-s1e1"}},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			userId := uuid.New()
			tt.before(userId, jellyfin.Connection{DeviceId: "biinge-api-" + userId.String(), AccessToken: libraryToken, UserId: "jf-user"})

			results := make([]map[uint64]string, 0, len(tt.expected))
			for range tt.expected {
				results = append(results, service.Episodes(ctx, userId, 1399, 1))
			}

			assert.Equal(t, tt.expected, results)
		})
	}

	for key := range store.store {
		require.NotContains(t, key, libraryToken)
	}
}

func Test_Library_Expiry(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockIntegrationRepository(ctrl)
	client := jellyfin.NewMockClient(ctrl)
	store := newMemoryCache()
	service := NewLibrary(newTestJellyfinConfig(), repository, client, store, newTestLogger())

	one, two := 1, 2
	series := []jellyfin.Item{{Id: "series", Type: jellyfin.ItemTypeSeries, TmdbId: "1399"}}

	tests := []struct {
		name      string
		before    func(userId uuid.UUID, connection jellyfin.Connection)
		key       string
		lookup    func(userId uuid.UUID) any
		cached    any
		refreshed any
	}{
		{
			name: "Added movie matches once the library index expires",
			before: func(userId uuid.UUID, connection jellyfin.Connection) {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil).Times(3)
				gomock.InOrder(
					client.EXPECT().Items(ctx, connection).Return([]jellyfin.Item{}, nil),
					client.EXPECT().Items(ctx, connection).Return([]jellyfin.Item{{Id: "movie", Type: jellyfin.ItemTypeMovie, TmdbId: "603"}}, nil),
				)
			},
			key:       "jellyfin:v1:library:%s:jf-user",
			lookup:    func(userId uuid.UUID) any { return service.Movie(ctx, userId, 603) },
			cached:    "",
			refreshed: "movie",
		},
		{
			name: "Added episode matches once the episodes index expires",
			before: func(userId uuid.UUID, connection jellyfin.Connection) {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil).Times(3)
				client.EXPECT().Items(ctx, connection).Return(series, nil)
				gomock.InOrder(
					client.EXPECT().Episodes(ctx, connection, "series").Return([]jellyfin.Episode{{Id: "s1e1", Season: &one, Number: &one}}, nil),
					client.EXPECT().Episodes(ctx, connection, "series").Return([]jellyfin.Episode{
						{Id: "s1e1", Season: &one, Number: &one},
						{Id: "s1e2", Season: &one, Number: &two},
					}, nil),
				)
			},
			key:       "jellyfin:v1:episodes:%s:jf-user:series",
			lookup:    func(userId uuid.UUID) any { return service.Episodes(ctx, userId, 1399, 1) },
			cached:    map[uint64]string{1: "s1e1"},
			refreshed: map[uint64]string{1: "s1e1", 2: "s1e2"},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			userId := uuid.New()
			key := fmt.Sprintf(tt.key, userId)
			tt.before(userId, jellyfin.Connection{DeviceId: "biinge-api-" + userId.String(), AccessToken: libraryToken, UserId: "jf-user"})

			// the second lookup is served from the cache, so the added item stays unmatched
			assert.Equal(t, tt.cached, tt.lookup(userId))
			assert.Equal(t, tt.cached, tt.lookup(userId))
			assert.Equal(t, 10*time.Minute, store.ttls[key])

			// dropping the entry stands in for its TTL running out
			require.Contains(t, store.store, key)
			delete(store.store, key)

			assert.Equal(t, tt.refreshed, tt.lookup(userId))
		})
	}
}
