package tmdb

import (
	"context"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"biinge-api/internal/config"
	"biinge-api/internal/config/logger"
)

// newTestClient builds a *client whose BaseURL points at the given address, so it can be
// pointed at an httptest.Server (or a closed one, to simulate a transport error)
func newTestClient(t *testing.T, baseURL string) *client {
	t.Helper()

	cfg := &config.Config{
		AppEnv: "test",
		TMDBConfig: config.TMDBConfig{
			BaseURL:            baseURL,
			APIReadAccessToken: "test-token",
			Locale:             "en-US",
		},
	}
	log := logger.NewLogger(cfg)

	c, ok := NewClient(cfg, log).(*client)
	require.True(t, ok)

	return c
}

// closedServerURL returns the URL of an httptest.Server that has already been closed, so
// requests against it fail at the transport level (connection refused)
func closedServerURL(t *testing.T) string {
	t.Helper()

	server := httptest.NewServer(http.HandlerFunc(func(http.ResponseWriter, *http.Request) {}))
	server.Close()

	return server.URL
}

func Test_NewClient(t *testing.T) {
	cfg := &config.Config{
		AppEnv: "test",
		TMDBConfig: config.TMDBConfig{
			BaseURL:            "https://api.themoviedb.org/3",
			APIReadAccessToken: "test-token",
			Locale:             "en-US",
		},
	}
	log := logger.NewLogger(cfg)

	result := NewClient(cfg, log)
	c, ok := result.(*client)

	require.True(t, ok)
	assert.Equal(t, "application/json", c.apiClient.Header.Get("Accept"))
	assert.Equal(t, "application/json", c.apiClient.Header.Get("Content-Type"))
	assert.Equal(t, "Bearer test-token", c.apiClient.Header.Get("Authorization"))
}

func Test_Client_FetchMovieDetails(t *testing.T) {
	tests := []struct {
		name           string
		statusCode     int
		body           string
		transportError bool
		expectedErr    error
		jsonErr        bool
		expected       *MovieDetails
	}{
		{
			name:       "Success",
			statusCode: http.StatusOK,
			body:       `{"id":550,"title":"Fight Club","overview":"desc","poster_path":"/poster.jpg","status":"Released","imdb_id":"tt0137523","release_date":"1999-10-15","runtime":139,"vote_average":8.4}`,
			expected: &MovieDetails{
				Id:          550,
				Title:       "Fight Club",
				Overview:    "desc",
				PosterPath:  "/poster.jpg",
				Status:      "Released",
				ImdbId:      "tt0137523",
				ReleaseDate: "1999-10-15",
				Runtime:     139,
				VoteAverage: 8.4,
			},
		},
		{
			name:        "Unauthorized",
			statusCode:  http.StatusUnauthorized,
			expectedErr: ErrAccessForbidden,
		},
		{
			name:        "Forbidden",
			statusCode:  http.StatusForbidden,
			expectedErr: ErrAccessForbidden,
		},
		{
			name:        "NotFound",
			statusCode:  http.StatusNotFound,
			expectedErr: ErrNotFound,
		},
		{
			name:        "UnexpectedStatus",
			statusCode:  http.StatusInternalServerError,
			expectedErr: ErrUnexpectedResponse,
		},
		{
			name:       "MalformedJSON",
			statusCode: http.StatusOK,
			body:       `{"id":`,
			jsonErr:    true,
		},
		{
			name:           "TransportError",
			transportError: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var baseURL string

			if tt.transportError {
				baseURL = closedServerURL(t)
			} else {
				server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
					w.WriteHeader(tt.statusCode)
					_, _ = w.Write([]byte(tt.body))
				}))
				defer server.Close()

				baseURL = server.URL
			}

			c := newTestClient(t, baseURL)

			result, err := c.FetchMovieDetails(context.Background(), 550)

			switch {
			case tt.expectedErr != nil:
				require.ErrorIs(t, err, tt.expectedErr)
				assert.Nil(t, result)
			case tt.jsonErr || tt.transportError:
				require.Error(t, err)
				assert.Nil(t, result)
			default:
				require.NoError(t, err)
				assert.Equal(t, tt.expected, result)
			}
		})
	}
}

func Test_Client_FetchMovieDetails_RequestShape(t *testing.T) {
	var capturedPath string

	var capturedQuery = map[string]string{}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		capturedPath = r.URL.Path
		capturedQuery["language"] = r.URL.Query().Get("language")
		capturedQuery["append_to_response"] = r.URL.Query().Get("append_to_response")

		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"id":550}`))
	}))
	defer server.Close()

	c := newTestClient(t, server.URL)

	_, err := c.FetchMovieDetails(context.Background(), 550)

	require.NoError(t, err)
	assert.Equal(t, "/movie/550", capturedPath)
	assert.Equal(t, "en-US", capturedQuery["language"])
	assert.Equal(t, "credits,recommendations,videos", capturedQuery["append_to_response"])
}

func Test_Client_FetchTvDetails(t *testing.T) {
	tests := []struct {
		name           string
		statusCode     int
		body           string
		transportError bool
		expectedErr    error
		jsonErr        bool
		expected       *TvDetails
	}{
		{
			name:       "Success",
			statusCode: http.StatusOK,
			body:       `{"id":1399,"name":"Game of Thrones","overview":"desc","poster_path":"/poster.jpg","status":"Ended","imdb_id":"tt0944947","first_air_date":"2011-04-17","vote_average":9.2}`,
			expected: &TvDetails{
				Id:          1399,
				Title:       "Game of Thrones",
				Overview:    "desc",
				PosterPath:  "/poster.jpg",
				Status:      "Ended",
				ImdbId:      "tt0944947",
				ReleaseDate: "2011-04-17",
				VoteAverage: 9.2,
			},
		},
		{
			name:        "Forbidden",
			statusCode:  http.StatusForbidden,
			expectedErr: ErrAccessForbidden,
		},
		{
			name:        "NotFound",
			statusCode:  http.StatusNotFound,
			expectedErr: ErrNotFound,
		},
		{
			name:        "UnexpectedStatus",
			statusCode:  http.StatusInternalServerError,
			expectedErr: ErrUnexpectedResponse,
		},
		{
			name:       "MalformedJSON",
			statusCode: http.StatusOK,
			body:       `{"id":`,
			jsonErr:    true,
		},
		{
			name:           "TransportError",
			transportError: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var baseURL string

			if tt.transportError {
				baseURL = closedServerURL(t)
			} else {
				server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
					w.WriteHeader(tt.statusCode)
					_, _ = w.Write([]byte(tt.body))
				}))
				defer server.Close()

				baseURL = server.URL
			}

			c := newTestClient(t, baseURL)

			result, err := c.FetchTvDetails(context.Background(), 1399)

			switch {
			case tt.expectedErr != nil:
				require.ErrorIs(t, err, tt.expectedErr)
				assert.Nil(t, result)
			case tt.jsonErr || tt.transportError:
				require.Error(t, err)
				assert.Nil(t, result)
			default:
				require.NoError(t, err)
				assert.Equal(t, tt.expected, result)
			}
		})
	}
}

func Test_Client_FetchTvSeasonDetails(t *testing.T) {
	tests := []struct {
		name           string
		statusCode     int
		body           string
		transportError bool
		expectedErr    error
		jsonErr        bool
		expected       *SeasonDetails
	}{
		{
			name:       "Success",
			statusCode: http.StatusOK,
			body:       `{"id":10,"air_date":"2011-04-17","name":"Season 1","overview":"desc","poster_path":"/s1.jpg","season_number":1,"episodes":[{"id":100,"air_date":"2011-04-17","episode_number":1,"name":"Winter Is Coming","overview":"ep1","runtime":62,"season_number":1,"still_path":"/e1.jpg","vote_average":8.1,"vote_count":100}]}`,
			expected: &SeasonDetails{
				ID:           10,
				AirDate:      "2011-04-17",
				Name:         "Season 1",
				Overview:     "desc",
				PosterPath:   "/s1.jpg",
				SeasonNumber: 1,
				Episodes: []Episode{
					{
						ID:            100,
						AirDate:       "2011-04-17",
						EpisodeNumber: 1,
						Name:          "Winter Is Coming",
						Overview:      "ep1",
						Runtime:       62,
						SeasonNumber:  1,
						StillPath:     "/e1.jpg",
						VoteAverage:   8.1,
						VoteCount:     100,
					},
				},
			},
		},
		{
			name:        "Forbidden",
			statusCode:  http.StatusForbidden,
			expectedErr: ErrAccessForbidden,
		},
		{
			name:        "NotFound",
			statusCode:  http.StatusNotFound,
			expectedErr: ErrNotFound,
		},
		{
			name:        "UnexpectedStatus",
			statusCode:  http.StatusInternalServerError,
			expectedErr: ErrUnexpectedResponse,
		},
		{
			name:       "MalformedJSON",
			statusCode: http.StatusOK,
			body:       `{"id":`,
			jsonErr:    true,
		},
		{
			name:           "TransportError",
			transportError: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var baseURL string

			if tt.transportError {
				baseURL = closedServerURL(t)
			} else {
				server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
					w.WriteHeader(tt.statusCode)
					_, _ = w.Write([]byte(tt.body))
				}))
				defer server.Close()

				baseURL = server.URL
			}

			c := newTestClient(t, baseURL)

			result, err := c.FetchTvSeasonDetails(context.Background(), 1399, 1)

			switch {
			case tt.expectedErr != nil:
				require.ErrorIs(t, err, tt.expectedErr)
				assert.Nil(t, result)
			case tt.jsonErr || tt.transportError:
				require.Error(t, err)
				assert.Nil(t, result)
			default:
				require.NoError(t, err)
				assert.Equal(t, tt.expected, result)
			}
		})
	}
}

func Test_Client_FetchTvSeasonDetails_RequestShape(t *testing.T) {
	var capturedPath string

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		capturedPath = r.URL.Path

		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"id":10}`))
	}))
	defer server.Close()

	c := newTestClient(t, server.URL)

	_, err := c.FetchTvSeasonDetails(context.Background(), 1399, 3)

	require.NoError(t, err)
	assert.Equal(t, "/tv/1399/season/3", capturedPath)
}

func Test_Client_FetchTvEpisodeDetails(t *testing.T) {
	tests := []struct {
		name           string
		statusCode     int
		body           string
		transportError bool
		expectedErr    error
		jsonErr        bool
		expected       *EpisodeDetails
	}{
		{
			name:       "Success",
			statusCode: http.StatusOK,
			body: `{"id":100,"air_date":"2011-04-17","episode_number":1,"name":"Winter Is Coming","overview":"ep1",` +
				`"runtime":62,"season_number":1,"still_path":"/e1.jpg","vote_average":8.1,"vote_count":100,` +
				`"credits":{"cast":[{"id":1,"name":"Actor A","adult":false,"profile_path":"/a.jpg","character":"Jon Snow"}],` +
				`"crew":[{"id":3,"name":"Director A","adult":false,"profile_path":"/d.jpg","department":"Directing","job":"Director"}]},` +
				`"videos":{"results":[{"id":"v1","name":"Trailer","key":"key1","site":"YouTube","size":1080,"type":"Trailer",` +
				`"official":true,"published_at":"2011-01-01","iso_3166_1":"US","iso_639_1":"en"}]}}`,
			expected: &EpisodeDetails{
				ID:            100,
				AirDate:       "2011-04-17",
				EpisodeNumber: 1,
				Name:          "Winter Is Coming",
				Overview:      "ep1",
				Runtime:       62,
				SeasonNumber:  1,
				StillPath:     "/e1.jpg",
				VoteAverage:   8.1,
				VoteCount:     100,
				Credits: Credits{
					Cast: []PersonCast{
						{Person: Person{Id: 1, Name: "Actor A", ProfilePath: "/a.jpg"}, Character: "Jon Snow"},
					},
					Crew: []PersonCrew{
						{Person: Person{Id: 3, Name: "Director A", ProfilePath: "/d.jpg"}, Department: "Directing", Job: "Director"},
					},
				},
				Videos: Videos{
					Results: []Video{
						{
							Id:          "v1",
							Name:        "Trailer",
							Key:         "key1",
							Site:        "YouTube",
							Size:        1080,
							Type:        "Trailer",
							Official:    true,
							PublishedAt: "2011-01-01",
							ISO31661:    "US",
							ISO6391:     "en",
						},
					},
				},
			},
		},
		{
			name:        "Forbidden",
			statusCode:  http.StatusForbidden,
			expectedErr: ErrAccessForbidden,
		},
		{
			name:        "NotFound",
			statusCode:  http.StatusNotFound,
			expectedErr: ErrNotFound,
		},
		{
			name:        "UnexpectedStatus",
			statusCode:  http.StatusInternalServerError,
			expectedErr: ErrUnexpectedResponse,
		},
		{
			name:       "MalformedJSON",
			statusCode: http.StatusOK,
			body:       `{"id":`,
			jsonErr:    true,
		},
		{
			name:           "TransportError",
			transportError: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var baseURL string

			if tt.transportError {
				baseURL = closedServerURL(t)
			} else {
				server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
					w.WriteHeader(tt.statusCode)
					_, _ = w.Write([]byte(tt.body))
				}))
				defer server.Close()

				baseURL = server.URL
			}

			c := newTestClient(t, baseURL)

			result, err := c.FetchTvEpisodeDetails(context.Background(), 1399, 1, 1)

			switch {
			case tt.expectedErr != nil:
				require.ErrorIs(t, err, tt.expectedErr)
				assert.Nil(t, result)
			case tt.jsonErr || tt.transportError:
				require.Error(t, err)
				assert.Nil(t, result)
			default:
				require.NoError(t, err)
				assert.Equal(t, tt.expected, result)
			}
		})
	}
}

func Test_Client_FetchTvEpisodeDetails_RequestShape(t *testing.T) {
	var capturedPath string

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		capturedPath = r.URL.Path

		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"id":100}`))
	}))
	defer server.Close()

	c := newTestClient(t, server.URL)

	_, err := c.FetchTvEpisodeDetails(context.Background(), 1399, 3, 7)

	require.NoError(t, err)
	assert.Equal(t, "/tv/1399/season/3/episode/7", capturedPath)
}

func Test_Client_FetchPersonDetails(t *testing.T) {
	tests := []struct {
		name           string
		statusCode     int
		body           string
		transportError bool
		expectedErr    error
		jsonErr        bool
		expected       *PersonDetails
	}{
		{
			name:       "Success",
			statusCode: http.StatusOK,
			body: `{"id":6193,"imdb_id":"nm0000138","name":"Leonardo DiCaprio","birthday":"1974-11-11","profile_path":"/p.jpg","gender":2,` +
				`"credits":{"cast":[{"id":1,"title":"Movie A","poster_path":"/a.jpg","release_date":"2020-01-01","character":"Hero"}],"crew":[]},` +
				`"tv_credits":{"cast":[],"crew":[]}}`,
			expected: &PersonDetails{
				Id:          6193,
				ImdbId:      "nm0000138",
				Name:        "Leonardo DiCaprio",
				Birthday:    "1974-11-11",
				ProfilePath: "/p.jpg",
				Gender:      2,
				Credits: PersonMovieCredits{
					Cast: []MovieCredit{
						{Id: 1, Title: "Movie A", PosterPath: "/a.jpg", ReleaseDate: "2020-01-01", Character: "Hero"},
					},
					Crew: []MovieCredit{},
				},
				TvCredits: PersonTvCredits{
					Cast: []TvCredit{},
					Crew: []TvCredit{},
				},
			},
		},
		{
			name:        "Forbidden",
			statusCode:  http.StatusForbidden,
			expectedErr: ErrAccessForbidden,
		},
		{
			name:        "NotFound",
			statusCode:  http.StatusNotFound,
			expectedErr: ErrNotFound,
		},
		{
			name:        "UnexpectedStatus",
			statusCode:  http.StatusInternalServerError,
			expectedErr: ErrUnexpectedResponse,
		},
		{
			name:       "MalformedJSON",
			statusCode: http.StatusOK,
			body:       `{"id":`,
			jsonErr:    true,
		},
		{
			name:           "TransportError",
			transportError: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var baseURL string

			if tt.transportError {
				baseURL = closedServerURL(t)
			} else {
				server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
					w.WriteHeader(tt.statusCode)
					_, _ = w.Write([]byte(tt.body))
				}))
				defer server.Close()

				baseURL = server.URL
			}

			c := newTestClient(t, baseURL)

			result, err := c.FetchPersonDetails(context.Background(), 6193)

			switch {
			case tt.expectedErr != nil:
				require.ErrorIs(t, err, tt.expectedErr)
				assert.Nil(t, result)
			case tt.jsonErr || tt.transportError:
				require.Error(t, err)
				assert.Nil(t, result)
			default:
				require.NoError(t, err)
				assert.Equal(t, tt.expected, result)
			}
		})
	}
}

func Test_Client_SearchMovies(t *testing.T) {
	tests := []struct {
		name           string
		statusCode     int
		body           string
		transportError bool
		expectedErr    error
		jsonErr        bool
		expected       *MovieListResult
	}{
		{
			name:       "Success",
			statusCode: http.StatusOK,
			body:       `{"page":1,"results":[{"id":1,"title":"Movie A","poster_path":"/a.jpg","release_date":"2020-01-01","vote_average":7.5,"overview":"desc","adult":false}],"total_pages":1,"total_results":1}`,
			expected: &MovieListResult{
				Page: 1,
				Results: []MovieListItem{
					{Id: 1, Title: "Movie A", PosterPath: "/a.jpg", ReleaseDate: "2020-01-01", VoteAverage: 7.5, Overview: "desc"},
				},
				TotalPages:   1,
				TotalResults: 1,
			},
		},
		{
			name:        "Forbidden",
			statusCode:  http.StatusForbidden,
			expectedErr: ErrAccessForbidden,
		},
		{
			name:        "NotFound",
			statusCode:  http.StatusNotFound,
			expectedErr: ErrNotFound,
		},
		{
			name:        "UnexpectedStatus",
			statusCode:  http.StatusInternalServerError,
			expectedErr: ErrUnexpectedResponse,
		},
		{
			name:       "MalformedJSON",
			statusCode: http.StatusOK,
			body:       `{"page":`,
			jsonErr:    true,
		},
		{
			name:           "TransportError",
			transportError: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var baseURL string

			if tt.transportError {
				baseURL = closedServerURL(t)
			} else {
				server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
					w.WriteHeader(tt.statusCode)
					_, _ = w.Write([]byte(tt.body))
				}))
				defer server.Close()

				baseURL = server.URL
			}

			c := newTestClient(t, baseURL)

			result, err := c.SearchMovies(context.Background(), "movie a", 1)

			switch {
			case tt.expectedErr != nil:
				require.ErrorIs(t, err, tt.expectedErr)
				assert.Nil(t, result)
			case tt.jsonErr || tt.transportError:
				require.Error(t, err)
				assert.Nil(t, result)
			default:
				require.NoError(t, err)
				assert.Equal(t, tt.expected, result)
			}
		})
	}
}

func Test_Client_SearchMovies_RequestShape(t *testing.T) {
	var capturedPath string

	var capturedQuery = map[string]string{}

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		capturedPath = r.URL.Path
		capturedQuery["query"] = r.URL.Query().Get("query")
		capturedQuery["page"] = r.URL.Query().Get("page")
		capturedQuery["include_adult"] = r.URL.Query().Get("include_adult")
		capturedQuery["language"] = r.URL.Query().Get("language")

		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"page":1}`))
	}))
	defer server.Close()

	c := newTestClient(t, server.URL)

	_, err := c.SearchMovies(context.Background(), "fight club", 2)

	require.NoError(t, err)
	assert.Equal(t, "/search/movie", capturedPath)
	assert.Equal(t, "fight club", capturedQuery["query"])
	assert.Equal(t, "2", capturedQuery["page"])
	assert.Equal(t, "false", capturedQuery["include_adult"])
	assert.Equal(t, "en-US", capturedQuery["language"])
}

func Test_Client_SearchTv(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"page":1,"results":[{"id":1,"name":"Show A","poster_path":"/a.jpg","first_air_date":"2020-01-01","vote_average":7.5,"overview":"desc","adult":false}],"total_pages":1,"total_results":1}`))
	}))
	defer server.Close()

	c := newTestClient(t, server.URL)

	result, err := c.SearchTv(context.Background(), "show a", 1)

	require.NoError(t, err)
	assert.Equal(t, &TvListResult{
		Page: 1,
		Results: []TvListItem{
			{Id: 1, Name: "Show A", PosterPath: "/a.jpg", FirstAirDate: "2020-01-01", VoteAverage: 7.5, Overview: "desc"},
		},
		TotalPages:   1,
		TotalResults: 1,
	}, result)
}

func Test_Client_SearchPeople(t *testing.T) {
	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"page":1,"results":[{"id":1,"name":"Person A","profile_path":"/a.jpg","adult":false,"known_for":[{"vote_count":100}]}],"total_pages":1,"total_results":1}`))
	}))
	defer server.Close()

	c := newTestClient(t, server.URL)

	result, err := c.SearchPeople(context.Background(), "person a", 1)

	require.NoError(t, err)
	assert.Equal(t, &PersonListResult{
		Page: 1,
		Results: []PersonListItem{
			{Id: 1, Name: "Person A", ProfilePath: "/a.jpg", KnownFor: []PersonKnownFor{{VoteCount: 100}}},
		},
		TotalPages:   1,
		TotalResults: 1,
	}, result)
}

func Test_Client_FetchTrendingMovies(t *testing.T) {
	var capturedPath string

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		capturedPath = r.URL.Path

		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"page":1,"results":[{"id":1,"title":"Movie A","poster_path":"/a.jpg","release_date":"2020-01-01","vote_average":7.5,"overview":"desc","adult":false}],"total_pages":1,"total_results":1}`))
	}))
	defer server.Close()

	c := newTestClient(t, server.URL)

	result, err := c.FetchTrendingMovies(context.Background())

	require.NoError(t, err)
	assert.Equal(t, "/trending/movie/week", capturedPath)
	assert.Equal(t, &MovieListResult{
		Page: 1,
		Results: []MovieListItem{
			{Id: 1, Title: "Movie A", PosterPath: "/a.jpg", ReleaseDate: "2020-01-01", VoteAverage: 7.5, Overview: "desc"},
		},
		TotalPages:   1,
		TotalResults: 1,
	}, result)
}

func Test_Client_FetchTrendingTv(t *testing.T) {
	var capturedPath string

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		capturedPath = r.URL.Path

		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"page":1,"results":[{"id":1,"name":"Show A","poster_path":"/a.jpg","first_air_date":"2020-01-01","vote_average":7.5,"overview":"desc","adult":false}],"total_pages":1,"total_results":1}`))
	}))
	defer server.Close()

	c := newTestClient(t, server.URL)

	result, err := c.FetchTrendingTv(context.Background())

	require.NoError(t, err)
	assert.Equal(t, "/trending/tv/week", capturedPath)
	assert.Equal(t, &TvListResult{
		Page: 1,
		Results: []TvListItem{
			{Id: 1, Name: "Show A", PosterPath: "/a.jpg", FirstAirDate: "2020-01-01", VoteAverage: 7.5, Overview: "desc"},
		},
		TotalPages:   1,
		TotalResults: 1,
	}, result)
}

func Test_Client_FetchTrendingPeople(t *testing.T) {
	var capturedPath string

	server := httptest.NewServer(http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		capturedPath = r.URL.Path

		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte(`{"page":1,"results":[{"id":1,"name":"Person A","profile_path":"/a.jpg","adult":false,"known_for":[{"vote_count":100}]}],"total_pages":1,"total_results":1}`))
	}))
	defer server.Close()

	c := newTestClient(t, server.URL)

	result, err := c.FetchTrendingPeople(context.Background())

	require.NoError(t, err)
	assert.Equal(t, "/person/popular", capturedPath)
	assert.Equal(t, &PersonListResult{
		Page: 1,
		Results: []PersonListItem{
			{Id: 1, Name: "Person A", ProfilePath: "/a.jpg", KnownFor: []PersonKnownFor{{VoteCount: 100}}},
		},
		TotalPages:   1,
		TotalResults: 1,
	}, result)
}
