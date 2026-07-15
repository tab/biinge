package controllers

import (
	"context"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"

	"biinge-api/internal/app/models"
	"biinge-api/internal/app/serializers"
	"biinge-api/internal/app/services"
	"biinge-api/internal/config"
	"biinge-api/internal/config/logger"
	"biinge-api/internal/config/middlewares"
)

func testConfig() *config.Config {
	return &config.Config{
		AppEnv:   "test",
		AppAddr:  "localhost:8080",
		LogLevel: "info",
	}
}

func Test_CatalogController_HandleSearchMovies(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	provider := services.NewMockTmdbProvider(ctrl)
	log := logger.NewLogger(testConfig())
	controller := NewCatalogController(provider, log)

	id, err := uuid.NewRandom()
	require.NoError(t, err)

	type result struct {
		response serializers.PaginationResponse[serializers.SearchMovieSerializer]
		error    serializers.ErrorSerializer
		status   string
		code     int
	}

	tests := []struct {
		name     string
		before   func()
		withUser bool
		target   string
		expected result
		error    bool
	}{
		{
			name: "Success",
			before: func() {
				provider.EXPECT().SearchMovies(gomock.Any(), "batman", uint64(1), id).Return(&serializers.PaginationResponse[serializers.SearchMovieSerializer]{
					Data: []serializers.SearchMovieSerializer{{Id: 1, Title: "Batman", PosterPath: "/b.jpg"}},
					Meta: serializers.PaginationMeta{Page: 1, Per: 20, Total: 1},
				}, nil)
			},
			withUser: true,
			target:   "/search/movies?query=batman",
			expected: result{
				response: serializers.PaginationResponse[serializers.SearchMovieSerializer]{
					Data: []serializers.SearchMovieSerializer{{Id: 1, Title: "Batman", PosterPath: "/b.jpg"}},
					Meta: serializers.PaginationMeta{Page: 1, Per: 20, Total: 1},
				},
				status: "200 OK",
				code:   http.StatusOK,
			},
		},
		{
			name: "Success With Page Parameter",
			before: func() {
				provider.EXPECT().SearchMovies(gomock.Any(), "batman", uint64(3), id).Return(&serializers.PaginationResponse[serializers.SearchMovieSerializer]{
					Data: []serializers.SearchMovieSerializer{},
					Meta: serializers.PaginationMeta{Page: 3, Per: 20, Total: 0},
				}, nil)
			},
			withUser: true,
			target:   "/search/movies?query=batman&page=3",
			expected: result{
				response: serializers.PaginationResponse[serializers.SearchMovieSerializer]{
					Data: []serializers.SearchMovieSerializer{},
					Meta: serializers.PaginationMeta{Page: 3, Per: 20, Total: 0},
				},
				status: "200 OK",
				code:   http.StatusOK,
			},
		},
		{
			name:     "Unauthorized",
			before:   func() {},
			withUser: false,
			target:   "/search/movies?query=batman",
			expected: result{
				error:  serializers.ErrorSerializer{Error: "unauthorized"},
				status: "401 Unauthorized",
				code:   http.StatusUnauthorized,
			},
			error: true,
		},
		{
			name:     "Empty Query",
			before:   func() {},
			withUser: true,
			target:   "/search/movies?query=%20",
			expected: result{
				error:  serializers.ErrorSerializer{Error: "empty query"},
				status: "400 Bad Request",
				code:   http.StatusBadRequest,
			},
			error: true,
		},
		{
			name: "Provider Error",
			before: func() {
				provider.EXPECT().SearchMovies(gomock.Any(), "batman", uint64(1), id).Return(nil, assert.AnError)
			},
			withUser: true,
			target:   "/search/movies?query=batman",
			expected: result{
				error:  serializers.ErrorSerializer{Error: "assert.AnError general error for testing"},
				status: "422 Unprocessable Entity",
				code:   http.StatusUnprocessableEntity,
			},
			error: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			req := httptest.NewRequest(http.MethodGet, tt.target, nil)
			if tt.withUser {
				ctx := context.WithValue(req.Context(), middlewares.CurrentUser{}, &models.User{ID: id})
				req = req.WithContext(ctx)
			}

			w := httptest.NewRecorder()

			r := chi.NewRouter()
			r.Get("/search/movies", controller.HandleSearchMovies)
			r.ServeHTTP(w, req)

			resp := w.Result()
			defer resp.Body.Close()

			if tt.error {
				var response serializers.ErrorSerializer

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.error, response)
			} else {
				var response serializers.PaginationResponse[serializers.SearchMovieSerializer]

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.response, response)
			}

			assert.Equal(t, tt.expected.code, resp.StatusCode)
			assert.Equal(t, tt.expected.status, resp.Status)
		})
	}
}

func Test_CatalogController_HandleSearchSeries(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	provider := services.NewMockTmdbProvider(ctrl)
	log := logger.NewLogger(testConfig())
	controller := NewCatalogController(provider, log)

	id, err := uuid.NewRandom()
	require.NoError(t, err)

	type result struct {
		response serializers.PaginationResponse[serializers.SearchSeriesSerializer]
		error    serializers.ErrorSerializer
		status   string
		code     int
	}

	tests := []struct {
		name     string
		before   func()
		withUser bool
		target   string
		expected result
		error    bool
	}{
		{
			name: "Success",
			before: func() {
				provider.EXPECT().SearchSeries(gomock.Any(), "thrones", uint64(1), id).Return(&serializers.PaginationResponse[serializers.SearchSeriesSerializer]{
					Data: []serializers.SearchSeriesSerializer{{Id: 1399, Title: "Game of Thrones", PosterPath: "/g.jpg"}},
					Meta: serializers.PaginationMeta{Page: 1, Per: 20, Total: 1},
				}, nil)
			},
			withUser: true,
			target:   "/search/series?query=thrones",
			expected: result{
				response: serializers.PaginationResponse[serializers.SearchSeriesSerializer]{
					Data: []serializers.SearchSeriesSerializer{{Id: 1399, Title: "Game of Thrones", PosterPath: "/g.jpg"}},
					Meta: serializers.PaginationMeta{Page: 1, Per: 20, Total: 1},
				},
				status: "200 OK",
				code:   http.StatusOK,
			},
		},
		{
			name:     "Unauthorized",
			before:   func() {},
			withUser: false,
			target:   "/search/series?query=thrones",
			expected: result{
				error:  serializers.ErrorSerializer{Error: "unauthorized"},
				status: "401 Unauthorized",
				code:   http.StatusUnauthorized,
			},
			error: true,
		},
		{
			name:     "Empty Query",
			before:   func() {},
			withUser: true,
			target:   "/search/series",
			expected: result{
				error:  serializers.ErrorSerializer{Error: "empty query"},
				status: "400 Bad Request",
				code:   http.StatusBadRequest,
			},
			error: true,
		},
		{
			name: "Provider Error",
			before: func() {
				provider.EXPECT().SearchSeries(gomock.Any(), "thrones", uint64(1), id).Return(nil, assert.AnError)
			},
			withUser: true,
			target:   "/search/series?query=thrones",
			expected: result{
				error:  serializers.ErrorSerializer{Error: "assert.AnError general error for testing"},
				status: "422 Unprocessable Entity",
				code:   http.StatusUnprocessableEntity,
			},
			error: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			req := httptest.NewRequest(http.MethodGet, tt.target, nil)
			if tt.withUser {
				ctx := context.WithValue(req.Context(), middlewares.CurrentUser{}, &models.User{ID: id})
				req = req.WithContext(ctx)
			}

			w := httptest.NewRecorder()

			r := chi.NewRouter()
			r.Get("/search/series", controller.HandleSearchSeries)
			r.ServeHTTP(w, req)

			resp := w.Result()
			defer resp.Body.Close()

			if tt.error {
				var response serializers.ErrorSerializer

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.error, response)
			} else {
				var response serializers.PaginationResponse[serializers.SearchSeriesSerializer]

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.response, response)
			}

			assert.Equal(t, tt.expected.code, resp.StatusCode)
			assert.Equal(t, tt.expected.status, resp.Status)
		})
	}
}

func Test_CatalogController_HandleSearchPeople(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	provider := services.NewMockTmdbProvider(ctrl)
	log := logger.NewLogger(testConfig())
	controller := NewCatalogController(provider, log)

	type result struct {
		response serializers.PaginationResponse[serializers.SearchPersonSerializer]
		error    serializers.ErrorSerializer
		status   string
		code     int
	}

	tests := []struct {
		name     string
		before   func()
		target   string
		expected result
		error    bool
	}{
		{
			name: "Success",
			before: func() {
				provider.EXPECT().SearchPeople(gomock.Any(), "pitt", uint64(1)).Return(&serializers.PaginationResponse[serializers.SearchPersonSerializer]{
					Data: []serializers.SearchPersonSerializer{{Id: 287, Name: "Brad Pitt", ProfilePath: "/p.jpg"}},
					Meta: serializers.PaginationMeta{Page: 1, Per: 20, Total: 1},
				}, nil)
			},
			target: "/search/people?query=pitt",
			expected: result{
				response: serializers.PaginationResponse[serializers.SearchPersonSerializer]{
					Data: []serializers.SearchPersonSerializer{{Id: 287, Name: "Brad Pitt", ProfilePath: "/p.jpg"}},
					Meta: serializers.PaginationMeta{Page: 1, Per: 20, Total: 1},
				},
				status: "200 OK",
				code:   http.StatusOK,
			},
		},
		{
			name:   "Empty Query",
			before: func() {},
			target: "/search/people",
			expected: result{
				error:  serializers.ErrorSerializer{Error: "empty query"},
				status: "400 Bad Request",
				code:   http.StatusBadRequest,
			},
			error: true,
		},
		{
			name: "Provider Error",
			before: func() {
				provider.EXPECT().SearchPeople(gomock.Any(), "pitt", uint64(1)).Return(nil, assert.AnError)
			},
			target: "/search/people?query=pitt",
			expected: result{
				error:  serializers.ErrorSerializer{Error: "assert.AnError general error for testing"},
				status: "422 Unprocessable Entity",
				code:   http.StatusUnprocessableEntity,
			},
			error: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			req := httptest.NewRequest(http.MethodGet, tt.target, nil)
			w := httptest.NewRecorder()

			r := chi.NewRouter()
			r.Get("/search/people", controller.HandleSearchPeople)
			r.ServeHTTP(w, req)

			resp := w.Result()
			defer resp.Body.Close()

			if tt.error {
				var response serializers.ErrorSerializer

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.error, response)
			} else {
				var response serializers.PaginationResponse[serializers.SearchPersonSerializer]

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.response, response)
			}

			assert.Equal(t, tt.expected.code, resp.StatusCode)
			assert.Equal(t, tt.expected.status, resp.Status)
		})
	}
}

func Test_CatalogController_HandleTrendingMovies(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	provider := services.NewMockTmdbProvider(ctrl)
	log := logger.NewLogger(testConfig())
	controller := NewCatalogController(provider, log)

	id, err := uuid.NewRandom()
	require.NoError(t, err)

	type result struct {
		response serializers.PaginationResponse[serializers.SearchMovieSerializer]
		error    serializers.ErrorSerializer
		status   string
		code     int
	}

	tests := []struct {
		name     string
		before   func()
		withUser bool
		expected result
		error    bool
	}{
		{
			name: "Success",
			before: func() {
				provider.EXPECT().FetchTrendingMovies(gomock.Any(), id).Return(&serializers.PaginationResponse[serializers.SearchMovieSerializer]{
					Data: []serializers.SearchMovieSerializer{{Id: 1, Title: "Batman", PosterPath: "/b.jpg"}},
					Meta: serializers.PaginationMeta{Page: 1, Per: 20, Total: 1},
				}, nil)
			},
			withUser: true,
			expected: result{
				response: serializers.PaginationResponse[serializers.SearchMovieSerializer]{
					Data: []serializers.SearchMovieSerializer{{Id: 1, Title: "Batman", PosterPath: "/b.jpg"}},
					Meta: serializers.PaginationMeta{Page: 1, Per: 20, Total: 1},
				},
				status: "200 OK",
				code:   http.StatusOK,
			},
		},
		{
			name:     "Unauthorized",
			before:   func() {},
			withUser: false,
			expected: result{
				error:  serializers.ErrorSerializer{Error: "unauthorized"},
				status: "401 Unauthorized",
				code:   http.StatusUnauthorized,
			},
			error: true,
		},
		{
			name: "Provider Error",
			before: func() {
				provider.EXPECT().FetchTrendingMovies(gomock.Any(), id).Return(nil, assert.AnError)
			},
			withUser: true,
			expected: result{
				error:  serializers.ErrorSerializer{Error: "assert.AnError general error for testing"},
				status: "422 Unprocessable Entity",
				code:   http.StatusUnprocessableEntity,
			},
			error: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			req := httptest.NewRequest(http.MethodGet, "/trending/movies", nil)
			if tt.withUser {
				ctx := context.WithValue(req.Context(), middlewares.CurrentUser{}, &models.User{ID: id})
				req = req.WithContext(ctx)
			}

			w := httptest.NewRecorder()

			r := chi.NewRouter()
			r.Get("/trending/movies", controller.HandleTrendingMovies)
			r.ServeHTTP(w, req)

			resp := w.Result()
			defer resp.Body.Close()

			if tt.error {
				var response serializers.ErrorSerializer

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.error, response)
			} else {
				var response serializers.PaginationResponse[serializers.SearchMovieSerializer]

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.response, response)
			}

			assert.Equal(t, tt.expected.code, resp.StatusCode)
			assert.Equal(t, tt.expected.status, resp.Status)
		})
	}
}

func Test_CatalogController_HandleTrendingSeries(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	provider := services.NewMockTmdbProvider(ctrl)
	log := logger.NewLogger(testConfig())
	controller := NewCatalogController(provider, log)

	id, err := uuid.NewRandom()
	require.NoError(t, err)

	type result struct {
		response serializers.PaginationResponse[serializers.SearchSeriesSerializer]
		error    serializers.ErrorSerializer
		status   string
		code     int
	}

	tests := []struct {
		name     string
		before   func()
		withUser bool
		expected result
		error    bool
	}{
		{
			name: "Success",
			before: func() {
				provider.EXPECT().FetchTrendingSeries(gomock.Any(), id).Return(&serializers.PaginationResponse[serializers.SearchSeriesSerializer]{
					Data: []serializers.SearchSeriesSerializer{{Id: 1399, Title: "Game of Thrones", PosterPath: "/g.jpg"}},
					Meta: serializers.PaginationMeta{Page: 1, Per: 20, Total: 1},
				}, nil)
			},
			withUser: true,
			expected: result{
				response: serializers.PaginationResponse[serializers.SearchSeriesSerializer]{
					Data: []serializers.SearchSeriesSerializer{{Id: 1399, Title: "Game of Thrones", PosterPath: "/g.jpg"}},
					Meta: serializers.PaginationMeta{Page: 1, Per: 20, Total: 1},
				},
				status: "200 OK",
				code:   http.StatusOK,
			},
		},
		{
			name:     "Unauthorized",
			before:   func() {},
			withUser: false,
			expected: result{
				error:  serializers.ErrorSerializer{Error: "unauthorized"},
				status: "401 Unauthorized",
				code:   http.StatusUnauthorized,
			},
			error: true,
		},
		{
			name: "Provider Error",
			before: func() {
				provider.EXPECT().FetchTrendingSeries(gomock.Any(), id).Return(nil, assert.AnError)
			},
			withUser: true,
			expected: result{
				error:  serializers.ErrorSerializer{Error: "assert.AnError general error for testing"},
				status: "422 Unprocessable Entity",
				code:   http.StatusUnprocessableEntity,
			},
			error: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			req := httptest.NewRequest(http.MethodGet, "/trending/series", nil)
			if tt.withUser {
				ctx := context.WithValue(req.Context(), middlewares.CurrentUser{}, &models.User{ID: id})
				req = req.WithContext(ctx)
			}

			w := httptest.NewRecorder()

			r := chi.NewRouter()
			r.Get("/trending/series", controller.HandleTrendingSeries)
			r.ServeHTTP(w, req)

			resp := w.Result()
			defer resp.Body.Close()

			if tt.error {
				var response serializers.ErrorSerializer

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.error, response)
			} else {
				var response serializers.PaginationResponse[serializers.SearchSeriesSerializer]

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.response, response)
			}

			assert.Equal(t, tt.expected.code, resp.StatusCode)
			assert.Equal(t, tt.expected.status, resp.Status)
		})
	}
}

func Test_CatalogController_HandleTrendingPeople(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	provider := services.NewMockTmdbProvider(ctrl)
	log := logger.NewLogger(testConfig())
	controller := NewCatalogController(provider, log)

	type result struct {
		response serializers.PaginationResponse[serializers.SearchPersonSerializer]
		error    serializers.ErrorSerializer
		status   string
		code     int
	}

	tests := []struct {
		name     string
		before   func()
		expected result
		error    bool
	}{
		{
			name: "Success",
			before: func() {
				provider.EXPECT().FetchTrendingPeople(gomock.Any()).Return(&serializers.PaginationResponse[serializers.SearchPersonSerializer]{
					Data: []serializers.SearchPersonSerializer{{Id: 287, Name: "Brad Pitt", ProfilePath: "/p.jpg"}},
					Meta: serializers.PaginationMeta{Page: 1, Per: 20, Total: 1},
				}, nil)
			},
			expected: result{
				response: serializers.PaginationResponse[serializers.SearchPersonSerializer]{
					Data: []serializers.SearchPersonSerializer{{Id: 287, Name: "Brad Pitt", ProfilePath: "/p.jpg"}},
					Meta: serializers.PaginationMeta{Page: 1, Per: 20, Total: 1},
				},
				status: "200 OK",
				code:   http.StatusOK,
			},
		},
		{
			name: "Provider Error",
			before: func() {
				provider.EXPECT().FetchTrendingPeople(gomock.Any()).Return(nil, assert.AnError)
			},
			expected: result{
				error:  serializers.ErrorSerializer{Error: "assert.AnError general error for testing"},
				status: "422 Unprocessable Entity",
				code:   http.StatusUnprocessableEntity,
			},
			error: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			req := httptest.NewRequest(http.MethodGet, "/trending/people", nil)
			w := httptest.NewRecorder()

			r := chi.NewRouter()
			r.Get("/trending/people", controller.HandleTrendingPeople)
			r.ServeHTTP(w, req)

			resp := w.Result()
			defer resp.Body.Close()

			if tt.error {
				var response serializers.ErrorSerializer

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.error, response)
			} else {
				var response serializers.PaginationResponse[serializers.SearchPersonSerializer]

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.response, response)
			}

			assert.Equal(t, tt.expected.code, resp.StatusCode)
			assert.Equal(t, tt.expected.status, resp.Status)
		})
	}
}
