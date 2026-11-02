package jellyfin

import (
	"context"
	"io"
	"net/http"
	"net/http/httptest"
	"net/url"
	"strings"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"biinge-api/internal/config"
	"biinge-api/internal/config/logger"
)

// capturedRequest is what the fake Jellyfin server saw of the client's request
type capturedRequest struct {
	method        string
	path          string
	query         url.Values
	authorization string
	userAgent     string
	body          string
}

// newTestServer starts a fake Jellyfin that records the request into captured and answers with the given status and body
func newTestServer(t *testing.T, captured *capturedRequest, statusCode int, body string) *httptest.Server {
	t.Helper()

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requestBody, _ := io.ReadAll(r.Body)
		*captured = capturedRequest{
			method:        r.Method,
			path:          r.URL.Path,
			query:         r.URL.Query(),
			authorization: r.Header.Get("Authorization"),
			userAgent:     r.Header.Get("User-Agent"),
			body:          string(requestBody),
		}

		// The real server answers 400 to an empty Version in the Authorization header
		if strings.Contains(captured.authorization, `Version=""`) {
			w.WriteHeader(http.StatusBadRequest)

			return
		}

		w.WriteHeader(statusCode)
		_, _ = w.Write([]byte(body))
	}))
	t.Cleanup(server.Close)

	return server
}

// newTestClient builds a client against baseURL (a closed server's URL simulates a transport error)
func newTestClient(t *testing.T, baseURL string, appVersion string) Client {
	t.Helper()

	cfg := &config.Config{
		AppEnv:     "test",
		AppVersion: appVersion,
		Jellyfin:   config.JellyfinConfig{BaseURL: baseURL},
	}

	return NewClient(cfg, logger.NewLogger(cfg))
}

// closedServerURL returns the URL of a server that is already closed, so a request to it is refused
func closedServerURL(t *testing.T) string {
	t.Helper()

	server := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {}))
	server.Close()

	return server.URL
}

func Test_Client_SignIn(t *testing.T) {
	ctx := context.Background()
	credentials := Credentials{Username: "alice", Password: "secret"}

	tests := []struct {
		name           string
		statusCode     int
		body           string
		transportError bool
		expected       *Session
		error          error
	}{
		{
			name:       "Success",
			statusCode: http.StatusOK,
			body:       `{"AccessToken":"token-1","User":{"Id":"user-1","Name":"Alice"}}`,
			expected: &Session{
				AccessToken: "token-1",
				UserId:      "user-1",
				UserName:    "Alice",
			},
		},
		{
			name:       "WrongCredentials",
			statusCode: http.StatusUnauthorized,
			error:      ErrInvalidCredentials,
		},
		{
			name:       "ServerError",
			statusCode: http.StatusInternalServerError,
			error:      ErrUnavailable,
		},
		{
			name:       "NoToken",
			statusCode: http.StatusOK,
			body:       `{"User":{"Id":"user-1","Name":"Alice"}}`,
			error:      ErrUnavailable,
		},
		{
			name:       "NoUserId",
			statusCode: http.StatusOK,
			body:       `{"AccessToken":"token-1","User":{"Name":"Alice"}}`,
			error:      ErrUnavailable,
		},
		{
			name:       "UndecodableBody",
			statusCode: http.StatusOK,
			body:       `{"AccessToken":"token-1","User":{"Id":"user-1","Name":5}}`,
			error:      ErrUnavailable,
		},
		{
			name:           "Unreachable",
			transportError: true,
			error:          ErrUnavailable,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var captured capturedRequest

			baseURL := closedServerURL(t)
			if !tt.transportError {
				baseURL = newTestServer(t, &captured, tt.statusCode, tt.body).URL
			}

			result, err := newTestClient(t, baseURL, "1.2.3").SignIn(ctx, "device-1", credentials)

			if !tt.transportError {
				assert.Equal(t, http.MethodPost, captured.method)
				assert.Equal(t, "/Users/AuthenticateByName", captured.path)
				assert.Equal(t, `MediaBrowser Client="biinge", Device="biinge API", DeviceId="device-1", Version="1.2.3"`, captured.authorization)
				assert.Equal(t, "biinge-api", captured.userAgent)
				assert.JSONEq(t, `{"Username":"alice","Pw":"secret"}`, captured.body)
			}

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

func Test_Client_SignOut(t *testing.T) {
	ctx := context.Background()

	tests := []struct {
		name           string
		statusCode     int
		transportError bool
		error          error
	}{
		{
			name:       "Success",
			statusCode: http.StatusNoContent,
		},
		{
			name:       "RevokedToken",
			statusCode: http.StatusUnauthorized,
			error:      ErrInvalidCredentials,
		},
		{
			name:       "ServerError",
			statusCode: http.StatusInternalServerError,
			error:      ErrUnavailable,
		},
		{
			name:           "Unreachable",
			transportError: true,
			error:          ErrUnavailable,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var captured capturedRequest

			baseURL := closedServerURL(t)
			if !tt.transportError {
				baseURL = newTestServer(t, &captured, tt.statusCode, "").URL
			}

			err := newTestClient(t, baseURL, "1.2.3").SignOut(ctx, "device-1", "token-1")

			if !tt.transportError {
				assert.Equal(t, http.MethodPost, captured.method)
				assert.Equal(t, "/Sessions/Logout", captured.path)
				assert.Equal(t, `MediaBrowser Client="biinge", Device="biinge API", DeviceId="device-1", Version="1.2.3", Token="token-1"`, captured.authorization)
				assert.Equal(t, "biinge-api", captured.userAgent)
			}

			if tt.error != nil {
				require.ErrorIs(t, err, tt.error)

				return
			}

			require.NoError(t, err)
		})
	}
}

func Test_Client_Items(t *testing.T) {
	ctx := context.Background()
	connection := Connection{DeviceId: "device-1", AccessToken: "token-1", UserId: "user-1"}

	tests := []struct {
		name           string
		statusCode     int
		body           string
		transportError bool
		expected       []Item
		error          error
	}{
		{
			name:       "Success",
			statusCode: http.StatusOK,
			body: `{"Items":[
				{"Id":"item-1","Type":"Movie","ProviderIds":{"Tmdb":"603","Imdb":"tt0133093"}},
				{"Id":"item-2","Type":"Series","ProviderIds":{"Tmdb":"1399"}},
				{"Id":"item-3","Type":"Movie","ProviderIds":{"Imdb":"tt0000001"}},
				{"Id":"item-4","Type":"Series"}
			],"TotalRecordCount":4}`,
			expected: []Item{
				{Id: "item-1", Type: ItemTypeMovie, TmdbId: "603"},
				{Id: "item-2", Type: ItemTypeSeries, TmdbId: "1399"},
				{Id: "item-3", Type: ItemTypeMovie},
				{Id: "item-4", Type: ItemTypeSeries},
			},
		},
		{
			name:       "EmptyLibrary",
			statusCode: http.StatusOK,
			body:       `{"Items":[],"TotalRecordCount":0}`,
			expected:   []Item{},
		},
		{
			name:       "RevokedToken",
			statusCode: http.StatusUnauthorized,
			error:      ErrInvalidCredentials,
		},
		{
			name:       "ServerError",
			statusCode: http.StatusInternalServerError,
			error:      ErrUnavailable,
		},
		{
			name:       "UndecodableBody",
			statusCode: http.StatusOK,
			body:       `<html>Bad Gateway</html>`,
			error:      ErrUnavailable,
		},
		{
			name:           "Unreachable",
			transportError: true,
			error:          ErrUnavailable,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var captured capturedRequest

			baseURL := closedServerURL(t)
			if !tt.transportError {
				baseURL = newTestServer(t, &captured, tt.statusCode, tt.body).URL
			}

			result, err := newTestClient(t, baseURL, "1.2.3").Items(ctx, connection)

			if !tt.transportError {
				assert.Equal(t, http.MethodGet, captured.method)
				assert.Equal(t, "/Users/user-1/Items", captured.path)
				assert.Equal(t, url.Values{
					"IncludeItemTypes": {"Movie,Series"},
					"Recursive":        {"true"},
					"Fields":           {"ProviderIds"},
					"EnableImages":     {"false"},
					"EnableUserData":   {"false"},
				}, captured.query)
				assert.Equal(t, `MediaBrowser Client="biinge", Device="biinge API", DeviceId="device-1", Version="1.2.3", Token="token-1"`, captured.authorization)
				assert.Equal(t, "biinge-api", captured.userAgent)
			}

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

func Test_Client_Episodes(t *testing.T) {
	ctx := context.Background()
	connection := Connection{DeviceId: "device-1", AccessToken: "token-1", UserId: "user-1"}
	zero, one, two := 0, 1, 2

	tests := []struct {
		name           string
		statusCode     int
		body           string
		transportError bool
		expected       []Episode
		error          error
	}{
		{
			name:       "Success",
			statusCode: http.StatusOK,
			body: `{"Items":[
				{"Id":"episode-1","Type":"Episode","ParentIndexNumber":1,"IndexNumber":2},
				{"Id":"episode-2","Type":"Episode","ParentIndexNumber":0,"IndexNumber":1},
				{"Id":"episode-3","Type":"Episode","IndexNumber":1},
				{"Id":"episode-4","Type":"Episode","ParentIndexNumber":2}
			],"TotalRecordCount":4}`,
			expected: []Episode{
				{Id: "episode-1", Season: &one, Number: &two},
				{Id: "episode-2", Season: &zero, Number: &one},
				{Id: "episode-3", Number: &one},
				{Id: "episode-4", Season: &two},
			},
		},
		{
			name:       "NoEpisodes",
			statusCode: http.StatusOK,
			body:       `{"Items":[],"TotalRecordCount":0}`,
			expected:   []Episode{},
		},
		{
			name:       "RevokedToken",
			statusCode: http.StatusUnauthorized,
			error:      ErrInvalidCredentials,
		},
		{
			name:       "ServerError",
			statusCode: http.StatusInternalServerError,
			error:      ErrUnavailable,
		},
		{
			name:       "UndecodableBody",
			statusCode: http.StatusOK,
			body:       `{"Items":[{"Id":"episode-1","IndexNumber":"one"}]}`,
			error:      ErrUnavailable,
		},
		{
			name:           "Unreachable",
			transportError: true,
			error:          ErrUnavailable,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var captured capturedRequest

			baseURL := closedServerURL(t)
			if !tt.transportError {
				baseURL = newTestServer(t, &captured, tt.statusCode, tt.body).URL
			}

			result, err := newTestClient(t, baseURL, "1.2.3").Episodes(ctx, connection, "series-1")

			if !tt.transportError {
				assert.Equal(t, http.MethodGet, captured.method)
				assert.Equal(t, "/Shows/series-1/Episodes", captured.path)
				assert.Equal(t, url.Values{
					"userId":         {"user-1"},
					"IsMissing":      {"false"},
					"EnableImages":   {"false"},
					"EnableUserData": {"false"},
				}, captured.query)
				assert.Equal(t, `MediaBrowser Client="biinge", Device="biinge API", DeviceId="device-1", Version="1.2.3", Token="token-1"`, captured.authorization)
				assert.Equal(t, "biinge-api", captured.userAgent)
			}

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

func Test_Client_Version(t *testing.T) {
	ctx := context.Background()
	credentials := Credentials{Username: "alice", Password: "secret"}

	tests := []struct {
		name       string
		appVersion string
		expected   string
	}{
		{
			name:       "Set",
			appVersion: "1.2.3",
			expected:   `Version="1.2.3"`,
		},
		{
			name:       "Unset",
			appVersion: "",
			expected:   `Version="dev"`,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var signIn, signOut capturedRequest

			signInURL := newTestServer(t, &signIn, http.StatusOK, `{"AccessToken":"token-1","User":{"Id":"user-1","Name":"Alice"}}`).URL
			_, err := newTestClient(t, signInURL, tt.appVersion).SignIn(ctx, "device-1", credentials)
			require.NoError(t, err)
			assert.Contains(t, signIn.authorization, tt.expected)

			signOutURL := newTestServer(t, &signOut, http.StatusNoContent, "").URL
			err = newTestClient(t, signOutURL, tt.appVersion).SignOut(ctx, "device-1", "token-1")
			require.NoError(t, err)
			assert.Contains(t, signOut.authorization, tt.expected)
		})
	}
}
