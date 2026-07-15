package controllers

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"

	"biinge-api/internal/app/models"
	"biinge-api/internal/app/serializers"
	"biinge-api/internal/app/services"
	"biinge-api/internal/config/logger"
	"biinge-api/internal/config/middlewares"
)

func Test_MoviesController_HandleList(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	movies := services.NewMockMovies(ctrl)
	provider := services.NewMockTmdbProvider(ctrl)
	log := logger.NewLogger(testConfig())
	controller := NewMoviesController(movies, provider, log)

	id, err := uuid.NewRandom()
	require.NoError(t, err)

	type result struct {
		response serializers.PaginationResponse[serializers.MovieSerializer]
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
			name: "Success - Want List",
			before: func() {
				movies.EXPECT().List(gomock.Any(), id, models.StateTypeWant, gomock.Any()).Return([]models.Movie{
					{TmdbId: 550, Title: "Fight Club", PosterPath: "/f.jpg", Pinned: true, State: "want"},
				}, uint64(1), nil)
			},
			withUser: true,
			target:   "/movies",
			expected: result{
				response: serializers.PaginationResponse[serializers.MovieSerializer]{
					Data: []serializers.MovieSerializer{{Id: 550, Title: "Fight Club", PosterPath: "/f.jpg", Pinned: true, State: "want"}},
					Meta: serializers.PaginationMeta{Page: 1, Per: 24, Total: 1},
				},
				status: "200 OK",
				code:   http.StatusOK,
			},
		},
		{
			name: "Success - Watched List",
			before: func() {
				movies.EXPECT().List(gomock.Any(), id, models.StateTypeWatched, gomock.Any()).Return([]models.Movie{}, uint64(0), nil)
			},
			withUser: true,
			target:   "/movies?type=watched",
			expected: result{
				response: serializers.PaginationResponse[serializers.MovieSerializer]{
					Data: []serializers.MovieSerializer{},
					Meta: serializers.PaginationMeta{Page: 1, Per: 24, Total: 0},
				},
				status: "200 OK",
				code:   http.StatusOK,
			},
		},
		{
			name:     "Unauthorized",
			before:   func() {},
			withUser: false,
			target:   "/movies",
			expected: result{
				error:  serializers.ErrorSerializer{Error: "unauthorized"},
				status: "401 Unauthorized",
				code:   http.StatusUnauthorized,
			},
			error: true,
		},
		{
			name: "Service Error",
			before: func() {
				movies.EXPECT().List(gomock.Any(), id, models.StateTypeWant, gomock.Any()).Return(nil, uint64(0), assert.AnError)
			},
			withUser: true,
			target:   "/movies",
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
			r.Get("/movies", controller.HandleList)
			r.ServeHTTP(w, req)

			resp := w.Result()
			defer resp.Body.Close()

			if tt.error {
				var response serializers.ErrorSerializer

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.error, response)
			} else {
				var response serializers.PaginationResponse[serializers.MovieSerializer]

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.response, response)
			}

			assert.Equal(t, tt.expected.code, resp.StatusCode)
			assert.Equal(t, tt.expected.status, resp.Status)
		})
	}
}

func Test_MoviesController_HandleDetails(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	movies := services.NewMockMovies(ctrl)
	provider := services.NewMockTmdbProvider(ctrl)
	log := logger.NewLogger(testConfig())
	controller := NewMoviesController(movies, provider, log)

	id, err := uuid.NewRandom()
	require.NoError(t, err)

	type result struct {
		response serializers.MovieDetailsSerializer
		error    serializers.ErrorSerializer
		status   string
		code     int
	}

	tests := []struct {
		name     string
		before   func()
		withUser bool
		param    string
		expected result
		error    bool
	}{
		{
			name: "Success",
			before: func() {
				provider.EXPECT().FetchMovieDetails(gomock.Any(), uint64(550), id).Return(&serializers.MovieDetailsSerializer{
					Id:     550,
					Title:  "Fight Club",
					State:  "want",
					Pinned: true,
				}, nil)
			},
			withUser: true,
			param:    "550",
			expected: result{
				response: serializers.MovieDetailsSerializer{
					Id:     550,
					Title:  "Fight Club",
					State:  "want",
					Pinned: true,
				},
				status: "200 OK",
				code:   http.StatusOK,
			},
		},
		{
			name:     "Unauthorized",
			before:   func() {},
			withUser: false,
			param:    "550",
			expected: result{
				error:  serializers.ErrorSerializer{Error: "unauthorized"},
				status: "401 Unauthorized",
				code:   http.StatusUnauthorized,
			},
			error: true,
		},
		{
			name:     "Invalid Tmdb Id",
			before:   func() {},
			withUser: true,
			param:    "abc",
			expected: result{
				error:  serializers.ErrorSerializer{Error: "invalid tmdb id"},
				status: "400 Bad Request",
				code:   http.StatusBadRequest,
			},
			error: true,
		},
		{
			name: "Provider Error",
			before: func() {
				provider.EXPECT().FetchMovieDetails(gomock.Any(), uint64(550), id).Return(nil, assert.AnError)
			},
			withUser: true,
			param:    "550",
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

			req := httptest.NewRequest(http.MethodGet, "/movies/"+tt.param, nil)
			if tt.withUser {
				ctx := context.WithValue(req.Context(), middlewares.CurrentUser{}, &models.User{ID: id})
				req = req.WithContext(ctx)
			}

			w := httptest.NewRecorder()

			r := chi.NewRouter()
			r.Get("/movies/{id}", controller.HandleDetails)
			r.ServeHTTP(w, req)

			resp := w.Result()
			defer resp.Body.Close()

			if tt.error {
				var response serializers.ErrorSerializer

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.error, response)
			} else {
				var response serializers.MovieDetailsSerializer

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.response, response)
			}

			assert.Equal(t, tt.expected.code, resp.StatusCode)
			assert.Equal(t, tt.expected.status, resp.Status)
		})
	}
}

func Test_MoviesController_HandleCreate(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	movies := services.NewMockMovies(ctrl)
	provider := services.NewMockTmdbProvider(ctrl)
	log := logger.NewLogger(testConfig())
	controller := NewMoviesController(movies, provider, log)

	id, err := uuid.NewRandom()
	require.NoError(t, err)

	type result struct {
		response serializers.MovieDetailsSerializer
		error    serializers.ErrorSerializer
		status   string
		code     int
	}

	tests := []struct {
		name     string
		before   func()
		withUser bool
		body     io.Reader
		expected result
		error    bool
	}{
		{
			name: "Success",
			before: func() {
				movies.EXPECT().Create(gomock.Any(), gomock.Any()).Return(&models.Movie{
					TmdbId: 550,
					State:  "want",
				}, nil)
			},
			withUser: true,
			body:     strings.NewReader(`{ "id": 550, "title": "Fight Club", "posterPath": "/f.jpg", "runtime": 139, "state": "want" }`),
			expected: result{
				response: serializers.MovieDetailsSerializer{Id: 550, State: "want"},
				status:   "200 OK",
				code:     http.StatusOK,
			},
		},
		{
			name:     "Unauthorized",
			before:   func() {},
			withUser: false,
			body:     strings.NewReader(`{ "id": 550, "title": "Fight Club", "state": "want" }`),
			expected: result{
				error:  serializers.ErrorSerializer{Error: "unauthorized"},
				status: "401 Unauthorized",
				code:   http.StatusUnauthorized,
			},
			error: true,
		},
		{
			name:     "Validation Error - Empty Title",
			before:   func() {},
			withUser: true,
			body:     strings.NewReader(`{ "id": 550, "title": "", "state": "want" }`),
			expected: result{
				error:  serializers.ErrorSerializer{Error: "empty title"},
				status: "400 Bad Request",
				code:   http.StatusBadRequest,
			},
			error: true,
		},
		{
			name: "Service Error",
			before: func() {
				movies.EXPECT().Create(gomock.Any(), gomock.Any()).Return(nil, assert.AnError)
			},
			withUser: true,
			body:     strings.NewReader(`{ "id": 550, "title": "Fight Club", "state": "want" }`),
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

			req := httptest.NewRequest(http.MethodPost, "/movies", tt.body)
			if tt.withUser {
				ctx := context.WithValue(req.Context(), middlewares.CurrentUser{}, &models.User{ID: id})
				req = req.WithContext(ctx)
			}

			w := httptest.NewRecorder()

			r := chi.NewRouter()
			r.Post("/movies", controller.HandleCreate)
			r.ServeHTTP(w, req)

			resp := w.Result()
			defer resp.Body.Close()

			if tt.error {
				var response serializers.ErrorSerializer

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.error, response)
			} else {
				var response serializers.MovieDetailsSerializer

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.response, response)
			}

			assert.Equal(t, tt.expected.code, resp.StatusCode)
			assert.Equal(t, tt.expected.status, resp.Status)
		})
	}
}

func Test_MoviesController_HandleUpdate(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	movies := services.NewMockMovies(ctrl)
	provider := services.NewMockTmdbProvider(ctrl)
	log := logger.NewLogger(testConfig())
	controller := NewMoviesController(movies, provider, log)

	id, err := uuid.NewRandom()
	require.NoError(t, err)

	type result struct {
		response serializers.MovieDetailsSerializer
		error    serializers.ErrorSerializer
		status   string
		code     int
	}

	tests := []struct {
		name     string
		before   func()
		withUser bool
		param    string
		body     io.Reader
		expected result
		error    bool
	}{
		{
			name: "Success",
			before: func() {
				movies.EXPECT().UpdateByTmdbId(gomock.Any(), gomock.Any()).Return(&models.Movie{
					TmdbId: 550,
					State:  "watched",
					Pinned: true,
				}, nil)
			},
			withUser: true,
			param:    "550",
			body:     strings.NewReader(`{ "state": "watched", "pinned": true }`),
			expected: result{
				response: serializers.MovieDetailsSerializer{Id: 550, State: "watched", Pinned: true},
				status:   "200 OK",
				code:     http.StatusOK,
			},
		},
		{
			name:     "Unauthorized",
			before:   func() {},
			withUser: false,
			param:    "550",
			body:     strings.NewReader(`{ "state": "watched" }`),
			expected: result{
				error:  serializers.ErrorSerializer{Error: "unauthorized"},
				status: "401 Unauthorized",
				code:   http.StatusUnauthorized,
			},
			error: true,
		},
		{
			name:     "Invalid Tmdb Id",
			before:   func() {},
			withUser: true,
			param:    "abc",
			body:     strings.NewReader(`{ "state": "watched" }`),
			expected: result{
				error:  serializers.ErrorSerializer{Error: "invalid tmdb id"},
				status: "400 Bad Request",
				code:   http.StatusBadRequest,
			},
			error: true,
		},
		{
			name:     "Validation Error - Empty State",
			before:   func() {},
			withUser: true,
			param:    "550",
			body:     strings.NewReader(`{ "state": "" }`),
			expected: result{
				error:  serializers.ErrorSerializer{Error: "empty state"},
				status: "400 Bad Request",
				code:   http.StatusBadRequest,
			},
			error: true,
		},
		{
			name: "Service Error",
			before: func() {
				movies.EXPECT().UpdateByTmdbId(gomock.Any(), gomock.Any()).Return(nil, assert.AnError)
			},
			withUser: true,
			param:    "550",
			body:     strings.NewReader(`{ "state": "watched" }`),
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

			req := httptest.NewRequest(http.MethodPatch, "/movies/"+tt.param, tt.body)
			if tt.withUser {
				ctx := context.WithValue(req.Context(), middlewares.CurrentUser{}, &models.User{ID: id})
				req = req.WithContext(ctx)
			}

			w := httptest.NewRecorder()

			r := chi.NewRouter()
			r.Patch("/movies/{id}", controller.HandleUpdate)
			r.ServeHTTP(w, req)

			resp := w.Result()
			defer resp.Body.Close()

			if tt.error {
				var response serializers.ErrorSerializer

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.error, response)
			} else {
				var response serializers.MovieDetailsSerializer

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.response, response)
			}

			assert.Equal(t, tt.expected.code, resp.StatusCode)
			assert.Equal(t, tt.expected.status, resp.Status)
		})
	}
}

func Test_MoviesController_HandleDelete(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	movies := services.NewMockMovies(ctrl)
	provider := services.NewMockTmdbProvider(ctrl)
	log := logger.NewLogger(testConfig())
	controller := NewMoviesController(movies, provider, log)

	id, err := uuid.NewRandom()
	require.NoError(t, err)

	type result struct {
		error  serializers.ErrorSerializer
		status string
		code   int
	}

	tests := []struct {
		name     string
		before   func()
		withUser bool
		param    string
		expected result
		error    bool
	}{
		{
			name: "Success",
			before: func() {
				movies.EXPECT().DeleteByTmdbId(gomock.Any(), uint64(550), id).Return(nil)
			},
			withUser: true,
			param:    "550",
			expected: result{
				status: "204 No Content",
				code:   http.StatusNoContent,
			},
		},
		{
			name:     "Unauthorized",
			before:   func() {},
			withUser: false,
			param:    "550",
			expected: result{
				error:  serializers.ErrorSerializer{Error: "unauthorized"},
				status: "401 Unauthorized",
				code:   http.StatusUnauthorized,
			},
			error: true,
		},
		{
			name:     "Invalid Tmdb Id",
			before:   func() {},
			withUser: true,
			param:    "abc",
			expected: result{
				error:  serializers.ErrorSerializer{Error: "invalid tmdb id"},
				status: "400 Bad Request",
				code:   http.StatusBadRequest,
			},
			error: true,
		},
		{
			name: "Service Error",
			before: func() {
				movies.EXPECT().DeleteByTmdbId(gomock.Any(), uint64(550), id).Return(assert.AnError)
			},
			withUser: true,
			param:    "550",
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

			req := httptest.NewRequest(http.MethodDelete, "/movies/"+tt.param, nil)
			if tt.withUser {
				ctx := context.WithValue(req.Context(), middlewares.CurrentUser{}, &models.User{ID: id})
				req = req.WithContext(ctx)
			}

			w := httptest.NewRecorder()

			r := chi.NewRouter()
			r.Delete("/movies/{id}", controller.HandleDelete)
			r.ServeHTTP(w, req)

			resp := w.Result()
			defer resp.Body.Close()

			if tt.error {
				var response serializers.ErrorSerializer

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.error, response)
			} else {
				body, err := io.ReadAll(resp.Body)
				require.NoError(t, err)
				assert.Empty(t, body)
			}

			assert.Equal(t, tt.expected.code, resp.StatusCode)
			assert.Equal(t, tt.expected.status, resp.Status)
		})
	}
}
