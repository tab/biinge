package igdb

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"biinge-api/internal/config"
	"biinge-api/internal/config/logger"
)

// stubServer records every Apicalypse body it receives and answers each path from responses
type stubServer struct {
	server     *httptest.Server
	tokenCalls atomic.Int32
	bodies     map[string]string
}

// newStubServer serves the Twitch token endpoint at /token and the IGDB endpoints under /v4
func newStubServer(t *testing.T, responses map[string]string) *stubServer {
	t.Helper()

	stub := &stubServer{bodies: make(map[string]string)}

	stub.server = httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		if r.URL.Path == "/token" {
			stub.tokenCalls.Add(1)
			w.Header().Set("Content-Type", "application/json")
			_, _ = w.Write([]byte(`{"access_token":"stub-token","expires_in":5000000,"token_type":"bearer"}`))

			return
		}

		body, err := io.ReadAll(r.Body)
		assert.NoError(t, err)

		stub.bodies[r.URL.Path] = string(body)

		payload, ok := responses[r.URL.Path]
		if !ok {
			w.WriteHeader(http.StatusNotFound)
			return
		}

		w.Header().Set("Content-Type", "application/json")
		_, _ = w.Write([]byte(payload))
	}))

	t.Cleanup(stub.server.Close)

	return stub
}

func newTestClient(t *testing.T, stub *stubServer) Client {
	t.Helper()

	base := ""
	token := ""

	if stub != nil {
		base = stub.server.URL + "/v4"
		token = stub.server.URL + "/token"
	}

	cfg := &config.Config{
		AppEnv: "test",
		IGDB: config.IGDBConfig{
			BaseURL:      base,
			TokenURL:     token,
			ClientID:     "client-id",
			ClientSecret: "client-secret",
		},
	}

	return NewClient(cfg, logger.NewLogger(cfg))
}

func Test_Client_FetchGameDetails(t *testing.T) {
	t.Run("Merges the game and its completion times", func(t *testing.T) {
		stub := newStubServer(t, map[string]string{
			"/v4/multiquery": `[
				{"name":"game","result":[{"id":1942,"name":"The Witcher 3","summary":"Monster hunting.","cover":{"id":9,"image_id":"co1wyy"},"total_rating":94.6,"total_rating_count":3200}]},
				{"name":"time","result":[{"game_id":1942,"hastily":93600,"normally":180000,"completely":381600,"count":1200}]}
			]`,
		})

		result, err := newTestClient(t, stub).FetchGameDetails(context.Background(), 1942)
		require.NoError(t, err)

		assert.Equal(t, uint64(1942), result.Game.Id)
		assert.Equal(t, "The Witcher 3", result.Game.Name)
		assert.Equal(t, "co1wyy", result.Game.Cover.ImageId)
		assert.Equal(t, int64(180000), result.TimeToBeat.Normally)
		assert.Equal(t, 1200, result.TimeToBeat.Count)

		// both endpoints ride in one request, and the id reaches each sub-query
		body := stub.bodies["/v4/multiquery"]
		assert.Contains(t, body, `query games "game"`)
		assert.Contains(t, body, `query game_time_to_beats "time"`)
		assert.Contains(t, body, "where id = 1942;")
		assert.Contains(t, body, "where game_id = 1942;")
		// the recommendations rail is filtered in Go, so the nested rows carry what it tests
		assert.Contains(t, body, "similar_games.cover.image_id")
		assert.Contains(t, body, "similar_games.platforms")
	})

	t.Run("Missing completion times leave the game intact", func(t *testing.T) {
		stub := newStubServer(t, map[string]string{
			"/v4/multiquery": `[
				{"name":"game","result":[{"id":7,"name":"Obscure Game"}]},
				{"name":"time","result":[]}
			]`,
		})

		result, err := newTestClient(t, stub).FetchGameDetails(context.Background(), 7)
		require.NoError(t, err)

		assert.Equal(t, "Obscure Game", result.Game.Name)
		assert.Zero(t, result.TimeToBeat.Normally)
	})

	t.Run("Empty result is a not found, not a success", func(t *testing.T) {
		stub := newStubServer(t, map[string]string{
			"/v4/multiquery": `[{"name":"game","result":[]},{"name":"time","result":[]}]`,
		})

		result, err := newTestClient(t, stub).FetchGameDetails(context.Background(), 404)
		require.ErrorIs(t, err, ErrNotFound)
		assert.Nil(t, result)
	})

	t.Run("Transport failure", func(t *testing.T) {
		result, err := newTestClient(t, nil).FetchGameDetails(context.Background(), 1)
		require.Error(t, err)
		assert.Nil(t, result)
	})
}

func Test_Client_SearchGames(t *testing.T) {
	t.Run("Scopes the query to playable PlayStation games", func(t *testing.T) {
		stub := newStubServer(t, map[string]string{
			"/v4/games": `[{"id":1,"name":"Bloodborne","cover":{"image_id":"co1abc"}}]`,
		})

		result, err := newTestClient(t, stub).SearchGames(context.Background(), "bloodborne", 24, 0)
		require.NoError(t, err)
		require.Len(t, result.Results, 1)
		assert.Equal(t, "Bloodborne", result.Results[0].Name)

		body := stub.bodies["/v4/games"]
		assert.Contains(t, body, `search "bloodborne";`)
		assert.Contains(t, body, "platforms = (167,48)")
		// remakes, remasters and ports are the only PlayStation release for many games
		assert.Contains(t, body, "game_type = (0,4,8,9,10,11)")
		assert.Contains(t, body, "version_parent = null")
		assert.Contains(t, body, "limit 24;")
		assert.Contains(t, body, "offset 0;")

		// Apicalypse allows only one where clause per query
		assert.Equal(t, 1, strings.Count(body, "where "))
	})

	t.Run("Escapes a term that would otherwise break out of the string literal", func(t *testing.T) {
		stub := newStubServer(t, map[string]string{"/v4/games": `[]`})

		_, err := newTestClient(t, stub).SearchGames(context.Background(), `ratchet"; drop *; --`, 24, 0)
		require.NoError(t, err)

		body := stub.bodies["/v4/games"]
		assert.Contains(t, body, `search "ratchet\"  drop *  --";`)
		assert.Equal(t, 1, strings.Count(body, "where "))
	})
}

func Test_Client_FetchTrendingGames(t *testing.T) {
	t.Run("Restores the popularity order and caps at the limit", func(t *testing.T) {
		stub := newStubServer(t, map[string]string{
			"/v4/popularity_primitives": `[
				{"game_id":30,"value":900},
				{"game_id":10,"value":800},
				{"game_id":20,"value":700}
			]`,
			// IGDB answers an id filter in its own order, and drops the non-PlayStation id
			"/v4/games": `[
				{"id":10,"name":"Second","cover":{"image_id":"co10"}},
				{"id":30,"name":"First","cover":{"image_id":"co30"}}
			]`,
		})

		result, err := newTestClient(t, stub).FetchTrendingGames(context.Background(), 2)
		require.NoError(t, err)
		require.Len(t, result.Results, 2)

		assert.Equal(t, "First", result.Results[0].Name)
		assert.Equal(t, "Second", result.Results[1].Name)

		assert.Contains(t, stub.bodies["/v4/popularity_primitives"], "where popularity_type = 1;")
		assert.Contains(t, stub.bodies["/v4/popularity_primitives"], "sort value desc;")
		assert.Contains(t, stub.bodies["/v4/games"], "id = (30,10,20)")
	})

	t.Run("Truncates to the requested limit", func(t *testing.T) {
		stub := newStubServer(t, map[string]string{
			"/v4/popularity_primitives": `[{"game_id":1,"value":10},{"game_id":2,"value":9}]`,
			"/v4/games": `[
				{"id":1,"name":"One","cover":{"image_id":"co1"}},
				{"id":2,"name":"Two","cover":{"image_id":"co2"}}
			]`,
		})

		result, err := newTestClient(t, stub).FetchTrendingGames(context.Background(), 1)
		require.NoError(t, err)
		require.Len(t, result.Results, 1)
		assert.Equal(t, "One", result.Results[0].Name)
	})

	t.Run("No popularity rows short-circuits the games query", func(t *testing.T) {
		stub := newStubServer(t, map[string]string{"/v4/popularity_primitives": `[]`})

		result, err := newTestClient(t, stub).FetchTrendingGames(context.Background(), 24)
		require.NoError(t, err)
		assert.Empty(t, result.Results)
		assert.NotContains(t, stub.bodies, "/v4/games")
	})
}

func Test_Client_Token(t *testing.T) {
	t.Run("Exchanges the credentials once and reuses the token", func(t *testing.T) {
		stub := newStubServer(t, map[string]string{"/v4/games": `[]`})
		client := newTestClient(t, stub)

		_, err := client.SearchGames(context.Background(), "one", 24, 0)
		require.NoError(t, err)

		_, err = client.SearchGames(context.Background(), "two", 24, 0)
		require.NoError(t, err)

		assert.Equal(t, int32(1), stub.tokenCalls.Load())
	})

	t.Run("A rejected token is dropped so the next call re-authenticates", func(t *testing.T) {
		var unauthorized atomic.Bool
		unauthorized.Store(true)

		var tokenCalls atomic.Int32

		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
			if r.URL.Path == "/token" {
				tokenCalls.Add(1)

				_, _ = w.Write([]byte(`{"access_token":"stub-token","expires_in":5000000}`))

				return
			}

			if unauthorized.Swap(false) {
				w.WriteHeader(http.StatusUnauthorized)
				return
			}

			_, _ = w.Write([]byte(`[]`))
		}))
		defer server.Close()

		cfg := &config.Config{
			AppEnv: "test",
			IGDB: config.IGDBConfig{
				BaseURL:      server.URL + "/v4",
				TokenURL:     server.URL + "/token",
				ClientID:     "client-id",
				ClientSecret: "client-secret",
			},
		}
		client := NewClient(cfg, logger.NewLogger(cfg))

		_, err := client.SearchGames(context.Background(), "first", 24, 0)
		require.ErrorIs(t, err, ErrAccessForbidden)

		_, err = client.SearchGames(context.Background(), "second", 24, 0)
		require.NoError(t, err)

		assert.Equal(t, int32(2), tokenCalls.Load())
	})

	t.Run("Rejected credentials surface as forbidden", func(t *testing.T) {
		server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
			w.WriteHeader(http.StatusForbidden)
		}))
		defer server.Close()

		cfg := &config.Config{
			AppEnv: "test",
			IGDB: config.IGDBConfig{
				BaseURL:      server.URL + "/v4",
				TokenURL:     server.URL + "/token",
				ClientID:     "client-id",
				ClientSecret: "wrong",
			},
		}

		_, err := NewClient(cfg, logger.NewLogger(cfg)).SearchGames(context.Background(), "any", 24, 0)
		require.ErrorIs(t, err, ErrAccessForbidden)
	})
}
