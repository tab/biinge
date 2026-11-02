package services

import (
	"context"
	"fmt"
	"sync/atomic"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.uber.org/fx/fxtest"
	"go.uber.org/mock/gomock"

	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories"
	"biinge-api/internal/config"
	"biinge-api/internal/config/cache"
	"biinge-api/pkg/jellyfin"
	"biinge-api/pkg/tmdb"
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
	service := NewLibrary(fxtest.NewLifecycle(t), newTestJellyfinConfig(), repository, client, tmdb.NewMockClient(ctrl), cache.NewNoopCache(), newMemoryCache(), newTestLogger())

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
	service := NewLibrary(fxtest.NewLifecycle(t), newTestJellyfinConfig(), repository, client, tmdb.NewMockClient(ctrl), cache.NewNoopCache(), newMemoryCache(), newTestLogger())

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

func Test_Library_MovieIds(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockIntegrationRepository(ctrl)
	client := jellyfin.NewMockClient(ctrl)
	service := NewLibrary(fxtest.NewLifecycle(t), newTestJellyfinConfig(), repository, client, tmdb.NewMockClient(ctrl), cache.NewNoopCache(), newMemoryCache(), newTestLogger())

	userId := uuid.New()
	connection := jellyfin.Connection{DeviceId: "biinge-api-" + userId.String(), AccessToken: libraryToken, UserId: "jf-user"}

	tests := []struct {
		name     string
		before   func()
		expected map[uint64]string
	}{
		{
			name: "Only unique movie matches",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil)
				client.EXPECT().Items(ctx, connection).Return([]jellyfin.Item{
					{Id: "movie", Type: jellyfin.ItemTypeMovie, TmdbId: "603"},
					{Id: "first", Type: jellyfin.ItemTypeMovie, TmdbId: "604"},
					{Id: "second", Type: jellyfin.ItemTypeMovie, TmdbId: "604"},
					{Id: "series", Type: jellyfin.ItemTypeSeries, TmdbId: "605"},
					{Id: "unlisted", Type: jellyfin.ItemTypeMovie, TmdbId: "700"},
				}, nil)
			},
			expected: map[uint64]string{603: "movie"},
		},
		{
			name: "Not connected",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(nil, pgx.ErrNoRows)
			},
			expected: map[uint64]string{},
		},
		{
			name: "Jellyfin unavailable",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil)
				client.EXPECT().Items(ctx, connection).Return(nil, jellyfin.ErrUnavailable)
			},
			expected: map[uint64]string{},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			assert.Equal(t, tt.expected, service.MovieIds(ctx, userId, []uint64{603, 604, 605, 606}))
		})
	}
}

func Test_Library_SeriesIds(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockIntegrationRepository(ctrl)
	client := jellyfin.NewMockClient(ctrl)
	service := NewLibrary(fxtest.NewLifecycle(t), newTestJellyfinConfig(), repository, client, tmdb.NewMockClient(ctrl), cache.NewNoopCache(), newMemoryCache(), newTestLogger())

	userId := uuid.New()
	connection := jellyfin.Connection{DeviceId: "biinge-api-" + userId.String(), AccessToken: libraryToken, UserId: "jf-user"}

	tests := []struct {
		name     string
		before   func()
		expected map[uint64]string
	}{
		{
			name: "Only unique series matches",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil)
				client.EXPECT().Items(ctx, connection).Return([]jellyfin.Item{
					{Id: "series", Type: jellyfin.ItemTypeSeries, TmdbId: "1399"},
					{Id: "first", Type: jellyfin.ItemTypeSeries, TmdbId: "1400"},
					{Id: "second", Type: jellyfin.ItemTypeSeries, TmdbId: "1400"},
					{Id: "movie", Type: jellyfin.ItemTypeMovie, TmdbId: "1401"},
					{Id: "unlisted", Type: jellyfin.ItemTypeSeries, TmdbId: "1500"},
				}, nil)
			},
			expected: map[uint64]string{1399: "series"},
		},
		{
			name: "Not connected",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(nil, pgx.ErrNoRows)
			},
			expected: map[uint64]string{},
		},
		{
			name: "Jellyfin unavailable",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil)
				client.EXPECT().Items(ctx, connection).Return(nil, jellyfin.ErrUnavailable)
			},
			expected: map[uint64]string{},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			assert.Equal(t, tt.expected, service.SeriesIds(ctx, userId, []uint64{1399, 1400, 1401, 1402}))
		})
	}
}

func Test_Library_Episodes(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockIntegrationRepository(ctrl)
	client := jellyfin.NewMockClient(ctrl)
	service := NewLibrary(fxtest.NewLifecycle(t), newTestJellyfinConfig(), repository, client, tmdb.NewMockClient(ctrl), cache.NewNoopCache(), newMemoryCache(), newTestLogger())

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
	service := NewLibrary(fxtest.NewLifecycle(t), cfg, repositories.NewMockIntegrationRepository(ctrl), jellyfin.NewMockClient(ctrl), tmdb.NewMockClient(ctrl), cache.NewNoopCache(), newMemoryCache(), newTestLogger())

	userId := uuid.New()

	assert.Empty(t, service.Movie(ctx, userId, 603))
	assert.Empty(t, service.Series(ctx, userId, 1399))
	assert.Nil(t, service.Episodes(ctx, userId, 1399, 1))

	// the strict mocks fail on any repository, Jellyfin or TMDB call
	service.(*library).setPlayed(ctx, userId, PlayedTarget{Kind: PlayedEpisode, TmdbId: 1399, SeasonId: 3624, EpisodeId: 63056, Played: true})
}

func Test_Library_Cache(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockIntegrationRepository(ctrl)
	client := jellyfin.NewMockClient(ctrl)
	store := newMemoryCache()
	service := NewLibrary(fxtest.NewLifecycle(t), newTestJellyfinConfig(), repository, client, tmdb.NewMockClient(ctrl), store, newMemoryCache(), newTestLogger())

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
	service := NewLibrary(fxtest.NewLifecycle(t), newTestJellyfinConfig(), repository, client, tmdb.NewMockClient(ctrl), store, newMemoryCache(), newTestLogger())

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

func Test_Library_SetPlayed(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockIntegrationRepository(ctrl)
	client := jellyfin.NewMockClient(ctrl)
	tmdbClient := tmdb.NewMockClient(ctrl)

	userId := uuid.New()
	connection := jellyfin.Connection{DeviceId: "biinge-api-" + userId.String(), AccessToken: libraryToken, UserId: "jf-user"}
	zero, one, two, three := 0, 1, 2, 3
	movies := []jellyfin.Item{{Id: "movie", Type: jellyfin.ItemTypeMovie, TmdbId: "603"}}
	series := []jellyfin.Item{{Id: "series", Type: jellyfin.ItemTypeSeries, TmdbId: "1399"}}
	details := &tmdb.TvDetails{Id: 1399, Seasons: []tmdb.TvSeason{{Id: 3627, SeasonNumber: 0}, {Id: 3624, SeasonNumber: 1}}}
	seasonOne := &tmdb.SeasonDetails{ID: 3624, SeasonNumber: 1, Episodes: []tmdb.Episode{{ID: 63057, EpisodeNumber: 2}, {ID: 63056, EpisodeNumber: 1}}}
	specials := &tmdb.SeasonDetails{ID: 3627, SeasonNumber: 0, Episodes: []tmdb.Episode{{ID: 1000, EpisodeNumber: 1}}}
	episodes := []jellyfin.Episode{
		{Id: "s0e1", Season: &zero, Number: &one},
		{Id: "s1e1", Season: &one, Number: &one},
		{Id: "s1e2", Season: &one, Number: &two},
		{Id: "first", Season: &one, Number: &three},
		{Id: "second", Season: &one, Number: &three},
		{Id: "s2e1", Season: &two, Number: &one},
	}

	tests := []struct {
		name   string
		before func()
		target PlayedTarget
	}{
		{
			name: "Movie played",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil)
				client.EXPECT().Items(ctx, connection).Return(movies, nil)
				client.EXPECT().SetPlayed(ctx, connection, jellyfin.PlayedState{ItemId: "movie", Played: true}).Return(nil)
			},
			target: PlayedTarget{Kind: PlayedMovie, TmdbId: 603, Played: true},
		},
		{
			name: "Movie unplayed",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil)
				client.EXPECT().Items(ctx, connection).Return(movies, nil)
				client.EXPECT().SetPlayed(ctx, connection, jellyfin.PlayedState{ItemId: "movie", Played: false}).Return(nil)
			},
			target: PlayedTarget{Kind: PlayedMovie, TmdbId: 603},
		},
		{
			name: "Movie without a match writes nothing",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil)
				client.EXPECT().Items(ctx, connection).Return([]jellyfin.Item{
					{Id: "first", Type: jellyfin.ItemTypeMovie, TmdbId: "603"},
					{Id: "second", Type: jellyfin.ItemTypeMovie, TmdbId: "603"},
				}, nil)
			},
			target: PlayedTarget{Kind: PlayedMovie, TmdbId: 603, Played: true},
		},
		{
			name: "Series played writes the series and every matched episode",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil).Times(2)
				client.EXPECT().Items(ctx, connection).Return(series, nil)
				client.EXPECT().Episodes(ctx, connection, "series").Return(episodes, nil)
				// the duplicate third episode of season one is not written
				client.EXPECT().SetPlayed(ctx, connection, jellyfin.PlayedState{ItemId: "series", Played: true}).Return(nil)
				client.EXPECT().SetPlayed(ctx, connection, jellyfin.PlayedState{ItemId: "s0e1", Played: true}).Return(nil)
				client.EXPECT().SetPlayed(ctx, connection, jellyfin.PlayedState{ItemId: "s1e1", Played: true}).Return(nil)
				client.EXPECT().SetPlayed(ctx, connection, jellyfin.PlayedState{ItemId: "s1e2", Played: true}).Return(nil)
				client.EXPECT().SetPlayed(ctx, connection, jellyfin.PlayedState{ItemId: "s2e1", Played: true}).Return(nil)
			},
			target: PlayedTarget{Kind: PlayedSeries, TmdbId: 1399, Played: true},
		},
		{
			name: "Series unplayed writes the series and every matched episode",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil).Times(2)
				client.EXPECT().Items(ctx, connection).Return(series, nil)
				client.EXPECT().Episodes(ctx, connection, "series").Return(episodes, nil)
				client.EXPECT().SetPlayed(ctx, connection, jellyfin.PlayedState{ItemId: "series", Played: false}).Return(nil)
				client.EXPECT().SetPlayed(ctx, connection, jellyfin.PlayedState{ItemId: "s0e1", Played: false}).Return(nil)
				client.EXPECT().SetPlayed(ctx, connection, jellyfin.PlayedState{ItemId: "s1e1", Played: false}).Return(nil)
				client.EXPECT().SetPlayed(ctx, connection, jellyfin.PlayedState{ItemId: "s1e2", Played: false}).Return(nil)
				client.EXPECT().SetPlayed(ctx, connection, jellyfin.PlayedState{ItemId: "s2e1", Played: false}).Return(nil)
			},
			target: PlayedTarget{Kind: PlayedSeries, TmdbId: 1399},
		},
		{
			name: "Series without a match writes nothing",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil).Times(2)
				client.EXPECT().Items(ctx, connection).Return([]jellyfin.Item{
					{Id: "first", Type: jellyfin.ItemTypeSeries, TmdbId: "1399"},
					{Id: "second", Type: jellyfin.ItemTypeSeries, TmdbId: "1399"},
				}, nil)
			},
			target: PlayedTarget{Kind: PlayedSeries, TmdbId: 1399, Played: true},
		},
		{
			name: "Series failed episode write leaves the others to run",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil).Times(2)
				client.EXPECT().Items(ctx, connection).Return(series, nil)
				client.EXPECT().Episodes(ctx, connection, "series").Return(episodes, nil)
				client.EXPECT().SetPlayed(ctx, connection, jellyfin.PlayedState{ItemId: "series", Played: true}).Return(nil)
				client.EXPECT().SetPlayed(ctx, connection, jellyfin.PlayedState{ItemId: "s0e1", Played: true}).Return(nil)
				client.EXPECT().SetPlayed(ctx, connection, jellyfin.PlayedState{ItemId: "s1e1", Played: true}).Return(jellyfin.ErrUnavailable)
				client.EXPECT().SetPlayed(ctx, connection, jellyfin.PlayedState{ItemId: "s1e2", Played: true}).Return(nil)
				client.EXPECT().SetPlayed(ctx, connection, jellyfin.PlayedState{ItemId: "s2e1", Played: true}).Return(nil)
			},
			target: PlayedTarget{Kind: PlayedSeries, TmdbId: 1399, Played: true},
		},
		{
			name: "Season writes every matched episode",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil).Times(2)
				client.EXPECT().Items(ctx, connection).Return(series, nil)
				tmdbClient.EXPECT().FetchTvDetails(ctx, uint64(1399)).Return(details, nil)
				client.EXPECT().Episodes(ctx, connection, "series").Return(episodes, nil)
				// the duplicate third episode and the other seasons are not written
				client.EXPECT().SetPlayed(ctx, connection, jellyfin.PlayedState{ItemId: "s1e1", Played: true}).Return(nil)
				client.EXPECT().SetPlayed(ctx, connection, jellyfin.PlayedState{ItemId: "s1e2", Played: true}).Return(nil)
			},
			target: PlayedTarget{Kind: PlayedSeason, TmdbId: 1399, SeasonId: 3624, Played: true},
		},
		{
			name: "Specials season writes its episodes",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil).Times(2)
				client.EXPECT().Items(ctx, connection).Return(series, nil)
				tmdbClient.EXPECT().FetchTvDetails(ctx, uint64(1399)).Return(details, nil)
				client.EXPECT().Episodes(ctx, connection, "series").Return(episodes, nil)
				client.EXPECT().SetPlayed(ctx, connection, jellyfin.PlayedState{ItemId: "s0e1", Played: false}).Return(nil)
			},
			target: PlayedTarget{Kind: PlayedSeason, TmdbId: 1399, SeasonId: 3627},
		},
		{
			name: "Episode unplayed",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil).Times(2)
				client.EXPECT().Items(ctx, connection).Return(series, nil)
				tmdbClient.EXPECT().FetchTvDetails(ctx, uint64(1399)).Return(details, nil)
				tmdbClient.EXPECT().FetchTvSeasonDetails(ctx, uint64(1399), uint64(1)).Return(seasonOne, nil)
				client.EXPECT().Episodes(ctx, connection, "series").Return(episodes, nil)
				client.EXPECT().SetPlayed(ctx, connection, jellyfin.PlayedState{ItemId: "s1e2", Played: false}).Return(nil)
			},
			target: PlayedTarget{Kind: PlayedEpisode, TmdbId: 1399, SeasonId: 3624, EpisodeId: 63057},
		},
		{
			name: "Specials episode played",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil).Times(2)
				client.EXPECT().Items(ctx, connection).Return(series, nil)
				tmdbClient.EXPECT().FetchTvDetails(ctx, uint64(1399)).Return(details, nil)
				tmdbClient.EXPECT().FetchTvSeasonDetails(ctx, uint64(1399), uint64(0)).Return(specials, nil)
				client.EXPECT().Episodes(ctx, connection, "series").Return(episodes, nil)
				client.EXPECT().SetPlayed(ctx, connection, jellyfin.PlayedState{ItemId: "s0e1", Played: true}).Return(nil)
			},
			target: PlayedTarget{Kind: PlayedEpisode, TmdbId: 1399, SeasonId: 3627, EpisodeId: 1000, Played: true},
		},
		{
			name: "Episode the library lacks writes nothing",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil).Times(2)
				client.EXPECT().Items(ctx, connection).Return(series, nil)
				tmdbClient.EXPECT().FetchTvDetails(ctx, uint64(1399)).Return(details, nil)
				tmdbClient.EXPECT().FetchTvSeasonDetails(ctx, uint64(1399), uint64(1)).Return(seasonOne, nil)
				client.EXPECT().Episodes(ctx, connection, "series").Return([]jellyfin.Episode{{Id: "s1e1", Season: &one, Number: &one}}, nil)
			},
			target: PlayedTarget{Kind: PlayedEpisode, TmdbId: 1399, SeasonId: 3624, EpisodeId: 63057, Played: true},
		},
		{
			name: "Season missing from the TMDB details writes nothing",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil)
				client.EXPECT().Items(ctx, connection).Return(series, nil)
				tmdbClient.EXPECT().FetchTvDetails(ctx, uint64(1399)).Return(details, nil)
			},
			target: PlayedTarget{Kind: PlayedSeason, TmdbId: 1399, SeasonId: 9999, Played: true},
		},
		{
			name: "Episode missing from the TMDB season writes nothing",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil)
				client.EXPECT().Items(ctx, connection).Return(series, nil)
				tmdbClient.EXPECT().FetchTvDetails(ctx, uint64(1399)).Return(details, nil)
				tmdbClient.EXPECT().FetchTvSeasonDetails(ctx, uint64(1399), uint64(1)).Return(seasonOne, nil)
			},
			target: PlayedTarget{Kind: PlayedEpisode, TmdbId: 1399, SeasonId: 3624, EpisodeId: 9999, Played: true},
		},
		{
			name: "TMDB details failure writes nothing",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil)
				client.EXPECT().Items(ctx, connection).Return(series, nil)
				tmdbClient.EXPECT().FetchTvDetails(ctx, uint64(1399)).Return(nil, tmdb.ErrUnexpectedResponse)
			},
			target: PlayedTarget{Kind: PlayedSeason, TmdbId: 1399, SeasonId: 3624, Played: true},
		},
		{
			name: "TMDB season failure writes nothing",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil)
				client.EXPECT().Items(ctx, connection).Return(series, nil)
				tmdbClient.EXPECT().FetchTvDetails(ctx, uint64(1399)).Return(details, nil)
				tmdbClient.EXPECT().FetchTvSeasonDetails(ctx, uint64(1399), uint64(1)).Return(nil, tmdb.ErrUnexpectedResponse)
			},
			target: PlayedTarget{Kind: PlayedEpisode, TmdbId: 1399, SeasonId: 3624, EpisodeId: 63056, Played: true},
		},
		{
			name: "Unmatched series reads no TMDB details",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil)
				client.EXPECT().Items(ctx, connection).Return(movies, nil)
			},
			target: PlayedTarget{Kind: PlayedEpisode, TmdbId: 1399, SeasonId: 3624, EpisodeId: 63056, Played: true},
		},
		{
			name: "No connection reads neither TMDB nor Jellyfin",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(nil, pgx.ErrNoRows)
			},
			target: PlayedTarget{Kind: PlayedEpisode, TmdbId: 1399, SeasonId: 3624, EpisodeId: 63056, Played: true},
		},
		{
			name: "Failed writes are logged and not retried",
			before: func() {
				repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil).Times(2)
				client.EXPECT().Items(ctx, connection).Return(series, nil)
				tmdbClient.EXPECT().FetchTvDetails(ctx, uint64(1399)).Return(details, nil)
				client.EXPECT().Episodes(ctx, connection, "series").Return(episodes, nil)
				// a failed write leaves the next one to run
				client.EXPECT().SetPlayed(ctx, connection, jellyfin.PlayedState{ItemId: "s1e1", Played: true}).Return(jellyfin.ErrUnavailable)
				client.EXPECT().SetPlayed(ctx, connection, jellyfin.PlayedState{ItemId: "s1e2", Played: true}).Return(jellyfin.ErrInvalidCredentials)
			},
			target: PlayedTarget{Kind: PlayedSeason, TmdbId: 1399, SeasonId: 3624, Played: true},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			// a fresh cache keeps each case's Jellyfin and TMDB reads its own
			service := NewLibrary(fxtest.NewLifecycle(t), newTestJellyfinConfig(), repository, client, tmdbClient, newMemoryCache(), newMemoryCache(), newTestLogger())

			tt.before()

			service.(*library).setPlayed(ctx, userId, tt.target)
		})
	}
}

func Test_Library_SetPlayed_Echo(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockIntegrationRepository(ctrl)
	client := jellyfin.NewMockClient(ctrl)
	store := newMemoryCache()
	service := NewLibrary(fxtest.NewLifecycle(t), newTestJellyfinConfig(), repository, client, tmdb.NewMockClient(ctrl), cache.NewNoopCache(), store, newTestLogger())

	userId := uuid.New()
	connection := jellyfin.Connection{DeviceId: "biinge-api-" + userId.String(), AccessToken: libraryToken, UserId: "jf-user"}
	key := fmt.Sprintf("jellyfin:v1:echo:%s:a1b2c3d4:true", userId)

	// a failed write is recorded too, since it may have landed
	repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil)
	client.EXPECT().Items(ctx, connection).Return([]jellyfin.Item{{Id: "A1B2-C3D4", Type: jellyfin.ItemTypeMovie, TmdbId: "603"}}, nil)
	client.EXPECT().SetPlayed(ctx, connection, jellyfin.PlayedState{ItemId: "A1B2-C3D4", Played: true}).Return(jellyfin.ErrUnavailable)

	service.(*library).setPlayed(ctx, userId, PlayedTarget{Kind: PlayedMovie, TmdbId: 603, Played: true})

	assert.Contains(t, store.store, key)
	assert.Equal(t, 60*time.Second, store.ttls[key])
}

func Test_Library_SetPlayed_EchoRecordFailure(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockIntegrationRepository(ctrl)
	client := jellyfin.NewMockClient(ctrl)
	store := newMemoryCache()
	store.setErr = assert.AnError
	receipts := NewEchoReceipts(store)
	service := NewLibrary(fxtest.NewLifecycle(t), newTestJellyfinConfig(), repository, client, tmdb.NewMockClient(ctrl), cache.NewNoopCache(), receipts, newTestLogger())

	userId := uuid.New()
	connection := jellyfin.Connection{DeviceId: "biinge-api-" + userId.String(), AccessToken: libraryToken, UserId: "jf-user"}

	// a failing Redis still leaves the receipt in process, and the write goes out
	repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil)
	client.EXPECT().Items(ctx, connection).Return([]jellyfin.Item{{Id: "a1b2c3d4", Type: jellyfin.ItemTypeMovie, TmdbId: "603"}}, nil)
	client.EXPECT().SetPlayed(ctx, connection, jellyfin.PlayedState{ItemId: "a1b2c3d4", Played: true}).Return(nil)

	service.(*library).setPlayed(ctx, userId, PlayedTarget{Kind: PlayedMovie, TmdbId: 603, Played: true})

	assert.Empty(t, store.store)

	_, found, err := receipts.Get(ctx, fmt.Sprintf("jellyfin:v1:echo:%s:a1b2c3d4:true", userId))
	require.NoError(t, err)
	assert.True(t, found)
}

func Test_Library_SetPlayed_Order(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockIntegrationRepository(ctrl)
	client := jellyfin.NewMockClient(ctrl)
	lifecycle := fxtest.NewLifecycle(t)
	service := NewLibrary(lifecycle, newTestJellyfinConfig(), repository, client, tmdb.NewMockClient(ctrl), cache.NewNoopCache(), newMemoryCache(), newTestLogger())

	lifecycle.RequireStart()
	defer lifecycle.RequireStop()

	userId := uuid.New()
	connection := jellyfin.Connection{DeviceId: "biinge-api-" + userId.String(), AccessToken: libraryToken, UserId: "jf-user"}
	started := make(chan struct{})
	release := make(chan struct{})
	done := make(chan struct{})
	played := false

	repository.EXPECT().FindByUser(gomock.Any(), userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil).Times(2)
	client.EXPECT().Items(gomock.Any(), connection).Return([]jellyfin.Item{{Id: "movie", Type: jellyfin.ItemTypeMovie, TmdbId: "603"}}, nil).Times(2)
	gomock.InOrder(
		client.EXPECT().SetPlayed(gomock.Any(), connection, jellyfin.PlayedState{ItemId: "movie", Played: true}).
			DoAndReturn(func(context.Context, jellyfin.Connection, jellyfin.PlayedState) error {
				close(started)

				// the mark holds the worker until the unmark is queued behind it
				select {
				case <-release:
				case <-time.After(time.Second):
					t.Error("The mark was never released")
				}

				played = true

				return nil
			}),
		client.EXPECT().SetPlayed(gomock.Any(), connection, jellyfin.PlayedState{ItemId: "movie", Played: false}).
			DoAndReturn(func(context.Context, jellyfin.Connection, jellyfin.PlayedState) error {
				defer close(done)

				played = false

				return nil
			}),
	)

	service.SetPlayed(ctx, userId, PlayedTarget{Kind: PlayedMovie, TmdbId: 603, Played: true})

	select {
	case <-started:
	case <-time.After(time.Second):
		t.Fatal("The mark never ran")
	}

	service.SetPlayed(ctx, userId, PlayedTarget{Kind: PlayedMovie, TmdbId: 603})

	// the unmark waits in the queue while the mark is in flight
	assert.Len(t, service.(*library).jobs, 1)

	close(release)

	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("The unmark never ran")
	}

	assert.False(t, played)
}

func Test_Library_SetPlayed_RequestCancelled(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	repository := repositories.NewMockIntegrationRepository(ctrl)
	client := jellyfin.NewMockClient(ctrl)
	lifecycle := fxtest.NewLifecycle(t)
	service := NewLibrary(lifecycle, newTestJellyfinConfig(), repository, client, tmdb.NewMockClient(ctrl), cache.NewNoopCache(), newMemoryCache(), newTestLogger())

	userId := uuid.New()
	connection := jellyfin.Connection{DeviceId: "biinge-api-" + userId.String(), AccessToken: libraryToken, UserId: "jf-user"}
	ctx, cancel := context.WithCancel(context.Background())
	done := make(chan struct{})

	repository.EXPECT().FindByUser(gomock.Any(), userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil)
	client.EXPECT().Items(gomock.Any(), connection).Return([]jellyfin.Item{{Id: "movie", Type: jellyfin.ItemTypeMovie, TmdbId: "603"}}, nil)
	client.EXPECT().SetPlayed(gomock.Any(), connection, jellyfin.PlayedState{ItemId: "movie", Played: true}).
		DoAndReturn(func(ctx context.Context, _ jellyfin.Connection, _ jellyfin.PlayedState) error {
			defer close(done)

			_, bounded := ctx.Deadline()
			assert.True(t, bounded)
			assert.NoError(t, ctx.Err())

			return nil
		})

	service.SetPlayed(ctx, userId, PlayedTarget{Kind: PlayedMovie, TmdbId: 603, Played: true})

	// the request ends before the worker starts, so the write runs after it
	cancel()
	lifecycle.RequireStart()

	defer lifecycle.RequireStop()

	select {
	case <-done:
	case <-time.After(time.Second):
		t.Fatal("The write never ran")
	}
}

func Test_Library_SetPlayed_QueueFull(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockIntegrationRepository(ctrl)
	client := jellyfin.NewMockClient(ctrl)
	lifecycle := fxtest.NewLifecycle(t)
	service := NewLibrary(lifecycle, newTestJellyfinConfig(), repository, client, tmdb.NewMockClient(ctrl), cache.NewNoopCache(), newMemoryCache(), newTestLogger())

	lifecycle.RequireStart()

	userId := uuid.New()
	other := uuid.New()
	connection := jellyfin.Connection{DeviceId: "biinge-api-" + userId.String(), AccessToken: libraryToken, UserId: "jf-user"}
	started := make(chan struct{})
	release := make(chan struct{})
	queued := make(chan struct{})

	repository.EXPECT().FindByUser(gomock.Any(), userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil)
	client.EXPECT().Items(gomock.Any(), connection).Return([]jellyfin.Item{{Id: "movie", Type: jellyfin.ItemTypeMovie, TmdbId: "603"}}, nil)
	client.EXPECT().SetPlayed(gomock.Any(), connection, jellyfin.PlayedState{ItemId: "movie", Played: true}).
		DoAndReturn(func(context.Context, jellyfin.Connection, jellyfin.PlayedState) error {
			close(started)

			select {
			case <-release:
			case <-time.After(time.Second):
				t.Error("The write in flight was never released")
			}

			return nil
		})
	// each queued write reads the connection of a user who never connected, and the one past the queue never runs
	repository.EXPECT().FindByUser(gomock.Any(), other, models.JellyfinProvider).Return(nil, pgx.ErrNoRows).Times(playedQueue)

	service.SetPlayed(ctx, userId, PlayedTarget{Kind: PlayedMovie, TmdbId: 603, Played: true})

	select {
	case <-started:
	case <-time.After(time.Second):
		t.Fatal("The first write never ran")
	}

	go func() {
		defer close(queued)

		for range playedQueue + 1 {
			service.SetPlayed(ctx, other, PlayedTarget{Kind: PlayedMovie, TmdbId: 604, Played: true})
		}
	}()

	select {
	case <-queued:
	case <-time.After(time.Second):
		t.Fatal("SetPlayed blocked on a full queue")
	}

	close(release)

	// stopping drains the queue, so every queued write has run when it returns
	stopCtx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()

	require.NoError(t, lifecycle.Stop(stopCtx))
}

func Test_Library_SetPlayed_Stop(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	repository := repositories.NewMockIntegrationRepository(ctrl)
	client := jellyfin.NewMockClient(ctrl)
	lifecycle := fxtest.NewLifecycle(t)
	service := NewLibrary(lifecycle, newTestJellyfinConfig(), repository, client, tmdb.NewMockClient(ctrl), cache.NewNoopCache(), newMemoryCache(), newTestLogger())

	lifecycle.RequireStart()

	userId := uuid.New()
	connection := jellyfin.Connection{DeviceId: "biinge-api-" + userId.String(), AccessToken: libraryToken, UserId: "jf-user"}
	jobs := service.(*library).jobs
	started := make(chan struct{})

	var finished atomic.Bool

	repository.EXPECT().FindByUser(gomock.Any(), userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil)
	client.EXPECT().Items(gomock.Any(), connection).Return([]jellyfin.Item{{Id: "movie", Type: jellyfin.ItemTypeMovie, TmdbId: "603"}}, nil)
	client.EXPECT().SetPlayed(gomock.Any(), connection, jellyfin.PlayedState{ItemId: "movie", Played: true}).
		DoAndReturn(func(context.Context, jellyfin.Connection, jellyfin.PlayedState) error {
			close(started)

			// the write ends only once OnStop has closed the empty queue, so a Stop that did not wait finds it unfinished
			select {
			case <-jobs:
			case <-time.After(time.Second):
				t.Error("OnStop never closed the queue")
			}

			finished.Store(true)

			return nil
		})

	service.SetPlayed(context.Background(), userId, PlayedTarget{Kind: PlayedMovie, TmdbId: 603, Played: true})

	select {
	case <-started:
	case <-time.After(time.Second):
		t.Fatal("The write never ran")
	}

	stopCtx, cancel := context.WithTimeout(context.Background(), time.Second)
	defer cancel()

	require.NoError(t, lifecycle.Stop(stopCtx))
	assert.True(t, finished.Load())
}

func Test_Library_SetPlayed_AfterStop(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	lifecycle := fxtest.NewLifecycle(t)
	service := NewLibrary(lifecycle, newTestJellyfinConfig(), repositories.NewMockIntegrationRepository(ctrl), jellyfin.NewMockClient(ctrl), tmdb.NewMockClient(ctrl), cache.NewNoopCache(), newMemoryCache(), newTestLogger())

	lifecycle.RequireStart()
	lifecycle.RequireStop()

	// a request outliving the server's shutdown drops its write, and the mocks expect no call
	assert.NotPanics(t, func() {
		service.SetPlayed(context.Background(), uuid.New(), PlayedTarget{Kind: PlayedMovie, TmdbId: 603, Played: true})
	})
}

func Test_Library_SetPlayed_TmdbCache(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockIntegrationRepository(ctrl)
	client := jellyfin.NewMockClient(ctrl)
	tmdbClient := tmdb.NewMockClient(ctrl)
	store := newMemoryCache()
	service := NewLibrary(fxtest.NewLifecycle(t), newTestJellyfinConfig(), repository, client, tmdbClient, store, newMemoryCache(), newTestLogger())

	userId := uuid.New()
	connection := jellyfin.Connection{DeviceId: "biinge-api-" + userId.String(), AccessToken: libraryToken, UserId: "jf-user"}
	one := 1
	target := PlayedTarget{Kind: PlayedEpisode, TmdbId: 1399, SeasonId: 3624, EpisodeId: 63056, Played: true}

	repository.EXPECT().FindByUser(ctx, userId, models.JellyfinProvider).Return(libraryConnection(userId, "jf-user"), nil).Times(4)
	client.EXPECT().Items(ctx, connection).Return([]jellyfin.Item{{Id: "series", Type: jellyfin.ItemTypeSeries, TmdbId: "1399"}}, nil)
	client.EXPECT().Episodes(ctx, connection, "series").Return([]jellyfin.Episode{{Id: "s1e1", Season: &one, Number: &one}}, nil)
	tmdbClient.EXPECT().FetchTvDetails(ctx, uint64(1399)).Return(&tmdb.TvDetails{Id: 1399, Seasons: []tmdb.TvSeason{{Id: 3624, SeasonNumber: 1}}}, nil)
	tmdbClient.EXPECT().FetchTvSeasonDetails(ctx, uint64(1399), uint64(1)).Return(&tmdb.SeasonDetails{ID: 3624, SeasonNumber: 1, Episodes: []tmdb.Episode{{ID: 63056, EpisodeNumber: 1}}}, nil)
	client.EXPECT().SetPlayed(ctx, connection, jellyfin.PlayedState{ItemId: "s1e1", Played: true}).Return(nil).Times(2)

	writer := service.(*library)
	writer.setPlayed(ctx, userId, target)
	writer.setPlayed(ctx, userId, target)

	// the keys and TTL TmdbProvider uses, so the two share entries
	assert.Equal(t, cache.DetailsTTL, store.ttls["tmdb:v2:tv:1399"])
	assert.Equal(t, cache.DetailsTTL, store.ttls["tmdb:v1:tv:1399:season:1"])
}
