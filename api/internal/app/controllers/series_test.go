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

func newSeriesController(ctrl *gomock.Controller) (*services.MockSeries, *services.MockProgress, *services.MockTmdbProvider, SeriesController) {
	series := services.NewMockSeries(ctrl)
	progress := services.NewMockProgress(ctrl)
	provider := services.NewMockTmdbProvider(ctrl)
	log := logger.NewLogger(testConfig())

	return series, progress, provider, NewSeriesController(series, progress, provider, log)
}

func Test_SeriesController_HandleList(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	series, _, _, controller := newSeriesController(ctrl)

	id, err := uuid.NewRandom()
	require.NoError(t, err)

	type result struct {
		response serializers.PaginationResponse[serializers.SeriesSerializer]
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
				series.EXPECT().List(gomock.Any(), id, models.StateTypeWant, gomock.Any()).Return([]models.Series{
					{TmdbId: 1399, Title: "Game of Thrones", PosterPath: "/g.jpg", Pinned: true, State: "want", EpisodesCount: 73, WatchedEpisodesCount: 10},
				}, uint64(1), nil)
			},
			withUser: true,
			target:   "/series",
			expected: result{
				response: serializers.PaginationResponse[serializers.SeriesSerializer]{
					Data: []serializers.SeriesSerializer{{Id: 1399, Title: "Game of Thrones", PosterPath: "/g.jpg", Pinned: true, State: "want", EpisodesCount: 73, WatchedEpisodesCount: 10}},
					Meta: serializers.PaginationMeta{Page: 1, Per: 24, Total: 1},
				},
				status: "200 OK",
				code:   http.StatusOK,
			},
		},
		{
			name: "Success - Watching List",
			before: func() {
				series.EXPECT().List(gomock.Any(), id, models.StateTypeWatching, gomock.Any()).Return([]models.Series{}, uint64(0), nil)
			},
			withUser: true,
			target:   "/series?type=watching",
			expected: result{
				response: serializers.PaginationResponse[serializers.SeriesSerializer]{
					Data: []serializers.SeriesSerializer{},
					Meta: serializers.PaginationMeta{Page: 1, Per: 24, Total: 0},
				},
				status: "200 OK",
				code:   http.StatusOK,
			},
		},
		{
			name: "Success - Watched List",
			before: func() {
				series.EXPECT().List(gomock.Any(), id, models.StateTypeWatched, gomock.Any()).Return([]models.Series{}, uint64(0), nil)
			},
			withUser: true,
			target:   "/series?type=watched",
			expected: result{
				response: serializers.PaginationResponse[serializers.SeriesSerializer]{
					Data: []serializers.SeriesSerializer{},
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
			target:   "/series",
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
				series.EXPECT().List(gomock.Any(), id, models.StateTypeWant, gomock.Any()).Return(nil, uint64(0), assert.AnError)
			},
			withUser: true,
			target:   "/series",
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
			r.Get("/series", controller.HandleList)
			r.ServeHTTP(w, req)

			resp := w.Result()
			defer resp.Body.Close()

			if tt.error {
				var response serializers.ErrorSerializer

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.error, response)
			} else {
				var response serializers.PaginationResponse[serializers.SeriesSerializer]

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.response, response)
			}

			assert.Equal(t, tt.expected.code, resp.StatusCode)
			assert.Equal(t, tt.expected.status, resp.Status)
		})
	}
}

func Test_SeriesController_HandleDetails(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	_, _, provider, controller := newSeriesController(ctrl)

	id, err := uuid.NewRandom()
	require.NoError(t, err)

	type result struct {
		response serializers.SeriesDetailsSerializer
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
				provider.EXPECT().FetchTvDetails(gomock.Any(), uint64(1399), id).Return(&serializers.SeriesDetailsSerializer{
					Id:     1399,
					Title:  "Game of Thrones",
					State:  "watching",
					Pinned: true,
				}, nil)
			},
			withUser: true,
			param:    "1399",
			expected: result{
				response: serializers.SeriesDetailsSerializer{
					Id:     1399,
					Title:  "Game of Thrones",
					State:  "watching",
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
			param:    "1399",
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
				provider.EXPECT().FetchTvDetails(gomock.Any(), uint64(1399), id).Return(nil, assert.AnError)
			},
			withUser: true,
			param:    "1399",
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

			req := httptest.NewRequest(http.MethodGet, "/series/"+tt.param, nil)
			if tt.withUser {
				ctx := context.WithValue(req.Context(), middlewares.CurrentUser{}, &models.User{ID: id})
				req = req.WithContext(ctx)
			}

			w := httptest.NewRecorder()

			r := chi.NewRouter()
			r.Get("/series/{id}", controller.HandleDetails)
			r.ServeHTTP(w, req)

			resp := w.Result()
			defer resp.Body.Close()

			if tt.error {
				var response serializers.ErrorSerializer

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.error, response)
			} else {
				var response serializers.SeriesDetailsSerializer

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.response, response)
			}

			assert.Equal(t, tt.expected.code, resp.StatusCode)
			assert.Equal(t, tt.expected.status, resp.Status)
		})
	}
}

func Test_SeriesController_HandleSeasonDetails(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	_, _, provider, controller := newSeriesController(ctrl)

	id, err := uuid.NewRandom()
	require.NoError(t, err)

	type result struct {
		response serializers.SeasonDetailsSerializer
		error    serializers.ErrorSerializer
		status   string
		code     int
	}

	tests := []struct {
		name     string
		before   func()
		withUser bool
		path     string
		expected result
		error    bool
	}{
		{
			name: "Success",
			before: func() {
				provider.EXPECT().FetchTvSeasonDetails(gomock.Any(), uint64(1399), uint64(1), gomock.Any()).Return(&serializers.SeasonDetailsSerializer{
					Id:     3624,
					Title:  "Season 1",
					Number: 1,
				}, nil)
			},
			withUser: true,
			path:     "/series/1399/season/1",
			expected: result{
				response: serializers.SeasonDetailsSerializer{
					Id:     3624,
					Title:  "Season 1",
					Number: 1,
				},
				status: "200 OK",
				code:   http.StatusOK,
			},
		},
		{
			name:     "Unauthorized",
			before:   func() {},
			withUser: false,
			path:     "/series/1399/season/1",
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
			path:     "/series/abc/season/1",
			expected: result{
				error:  serializers.ErrorSerializer{Error: "invalid tmdb id"},
				status: "400 Bad Request",
				code:   http.StatusBadRequest,
			},
			error: true,
		},
		{
			name:     "Invalid Season Number",
			before:   func() {},
			withUser: true,
			path:     "/series/1399/season/abc",
			expected: result{
				error:  serializers.ErrorSerializer{Error: "invalid season number"},
				status: "400 Bad Request",
				code:   http.StatusBadRequest,
			},
			error: true,
		},
		{
			name: "Provider Error",
			before: func() {
				provider.EXPECT().FetchTvSeasonDetails(gomock.Any(), uint64(1399), uint64(1), gomock.Any()).Return(nil, assert.AnError)
			},
			withUser: true,
			path:     "/series/1399/season/1",
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

			req := httptest.NewRequest(http.MethodGet, tt.path, nil)
			if tt.withUser {
				ctx := context.WithValue(req.Context(), middlewares.CurrentUser{}, &models.User{ID: id})
				req = req.WithContext(ctx)
			}

			w := httptest.NewRecorder()

			r := chi.NewRouter()
			r.Get("/series/{id}/season/{seasonNumber}", controller.HandleSeasonDetails)
			r.ServeHTTP(w, req)

			resp := w.Result()
			defer resp.Body.Close()

			if tt.error {
				var response serializers.ErrorSerializer

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.error, response)
			} else {
				var response serializers.SeasonDetailsSerializer

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.response, response)
			}

			assert.Equal(t, tt.expected.code, resp.StatusCode)
			assert.Equal(t, tt.expected.status, resp.Status)
		})
	}
}

func Test_SeriesController_HandleEpisodeDetails(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	_, _, provider, controller := newSeriesController(ctrl)

	id, err := uuid.NewRandom()
	require.NoError(t, err)

	type result struct {
		response serializers.EpisodeDetailsSerializer
		error    serializers.ErrorSerializer
		status   string
		code     int
	}

	tests := []struct {
		name     string
		before   func()
		withUser bool
		path     string
		expected result
		error    bool
	}{
		{
			name: "Success",
			before: func() {
				provider.EXPECT().FetchTvEpisodeDetails(gomock.Any(), uint64(1399), uint64(1), uint64(1), gomock.Any()).Return(&serializers.EpisodeDetailsSerializer{
					Id:      63056,
					Title:   "Winter Is Coming",
					Number:  1,
					Runtime: 62,
				}, nil)
			},
			withUser: true,
			path:     "/series/1399/season/1/episode/1",
			expected: result{
				response: serializers.EpisodeDetailsSerializer{
					Id:      63056,
					Title:   "Winter Is Coming",
					Number:  1,
					Runtime: 62,
				},
				status: "200 OK",
				code:   http.StatusOK,
			},
		},
		{
			name:     "Unauthorized",
			before:   func() {},
			withUser: false,
			path:     "/series/1399/season/1/episode/1",
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
			path:     "/series/abc/season/1/episode/1",
			expected: result{
				error:  serializers.ErrorSerializer{Error: "invalid tmdb id"},
				status: "400 Bad Request",
				code:   http.StatusBadRequest,
			},
			error: true,
		},
		{
			name:     "Invalid Season Number",
			before:   func() {},
			withUser: true,
			path:     "/series/1399/season/abc/episode/1",
			expected: result{
				error:  serializers.ErrorSerializer{Error: "invalid season number"},
				status: "400 Bad Request",
				code:   http.StatusBadRequest,
			},
			error: true,
		},
		{
			name:     "Invalid Episode Number",
			before:   func() {},
			withUser: true,
			path:     "/series/1399/season/1/episode/abc",
			expected: result{
				error:  serializers.ErrorSerializer{Error: "invalid episode number"},
				status: "400 Bad Request",
				code:   http.StatusBadRequest,
			},
			error: true,
		},
		{
			name: "Provider Error",
			before: func() {
				provider.EXPECT().FetchTvEpisodeDetails(gomock.Any(), uint64(1399), uint64(1), uint64(1), gomock.Any()).Return(nil, assert.AnError)
			},
			withUser: true,
			path:     "/series/1399/season/1/episode/1",
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

			req := httptest.NewRequest(http.MethodGet, tt.path, nil)
			if tt.withUser {
				ctx := context.WithValue(req.Context(), middlewares.CurrentUser{}, &models.User{ID: id})
				req = req.WithContext(ctx)
			}

			w := httptest.NewRecorder()

			r := chi.NewRouter()
			r.Get("/series/{id}/season/{seasonNumber}/episode/{episodeNumber}", controller.HandleEpisodeDetails)
			r.ServeHTTP(w, req)

			resp := w.Result()
			defer resp.Body.Close()

			if tt.error {
				var response serializers.ErrorSerializer

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.error, response)
			} else {
				var response serializers.EpisodeDetailsSerializer

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.response, response)
			}

			assert.Equal(t, tt.expected.code, resp.StatusCode)
			assert.Equal(t, tt.expected.status, resp.Status)
		})
	}
}

func Test_SeriesController_HandleCreate(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	series, _, _, controller := newSeriesController(ctrl)

	id, err := uuid.NewRandom()
	require.NoError(t, err)

	type result struct {
		response serializers.SeriesDetailsSerializer
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
				series.EXPECT().Create(gomock.Any(), gomock.Any()).Return(&models.Series{
					TmdbId: 1399,
					State:  "watching",
				}, nil)
			},
			withUser: true,
			body:     strings.NewReader(`{ "id": 1399, "title": "Game of Thrones", "posterPath": "/g.jpg", "seasonsCount": 8, "episodesCount": 73, "status": "Ended", "state": "watching" }`),
			expected: result{
				response: serializers.SeriesDetailsSerializer{Id: 1399, State: "watching"},
				status:   "200 OK",
				code:     http.StatusOK,
			},
		},
		{
			name:     "Unauthorized",
			before:   func() {},
			withUser: false,
			body:     strings.NewReader(`{ "id": 1399, "title": "Game of Thrones", "state": "watching" }`),
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
			body:     strings.NewReader(`{ "id": 1399, "title": "", "state": "watching" }`),
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
				series.EXPECT().Create(gomock.Any(), gomock.Any()).Return(nil, assert.AnError)
			},
			withUser: true,
			body:     strings.NewReader(`{ "id": 1399, "title": "Game of Thrones", "state": "watching" }`),
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

			req := httptest.NewRequest(http.MethodPost, "/series", tt.body)
			if tt.withUser {
				ctx := context.WithValue(req.Context(), middlewares.CurrentUser{}, &models.User{ID: id})
				req = req.WithContext(ctx)
			}

			w := httptest.NewRecorder()

			r := chi.NewRouter()
			r.Post("/series", controller.HandleCreate)
			r.ServeHTTP(w, req)

			resp := w.Result()
			defer resp.Body.Close()

			if tt.error {
				var response serializers.ErrorSerializer

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.error, response)
			} else {
				var response serializers.SeriesDetailsSerializer

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.response, response)
			}

			assert.Equal(t, tt.expected.code, resp.StatusCode)
			assert.Equal(t, tt.expected.status, resp.Status)
		})
	}
}

func Test_SeriesController_HandleUpdate(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	series, _, _, controller := newSeriesController(ctrl)

	id, err := uuid.NewRandom()
	require.NoError(t, err)

	type result struct {
		response serializers.SeriesDetailsSerializer
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
				series.EXPECT().UpdateByTmdbId(gomock.Any(), gomock.Any()).Return(&models.Series{
					TmdbId: 1399,
					State:  "watched",
					Pinned: true,
				}, nil)
			},
			withUser: true,
			param:    "1399",
			body:     strings.NewReader(`{ "state": "watched", "pinned": true }`),
			expected: result{
				response: serializers.SeriesDetailsSerializer{Id: 1399, State: "watched", Pinned: true},
				status:   "200 OK",
				code:     http.StatusOK,
			},
		},
		{
			name:     "Unauthorized",
			before:   func() {},
			withUser: false,
			param:    "1399",
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
			param:    "1399",
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
				series.EXPECT().UpdateByTmdbId(gomock.Any(), gomock.Any()).Return(nil, assert.AnError)
			},
			withUser: true,
			param:    "1399",
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

			req := httptest.NewRequest(http.MethodPatch, "/series/"+tt.param, tt.body)
			if tt.withUser {
				ctx := context.WithValue(req.Context(), middlewares.CurrentUser{}, &models.User{ID: id})
				req = req.WithContext(ctx)
			}

			w := httptest.NewRecorder()

			r := chi.NewRouter()
			r.Patch("/series/{id}", controller.HandleUpdate)
			r.ServeHTTP(w, req)

			resp := w.Result()
			defer resp.Body.Close()

			if tt.error {
				var response serializers.ErrorSerializer

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.error, response)
			} else {
				var response serializers.SeriesDetailsSerializer

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.response, response)
			}

			assert.Equal(t, tt.expected.code, resp.StatusCode)
			assert.Equal(t, tt.expected.status, resp.Status)
		})
	}
}

func Test_SeriesController_HandleDelete(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	series, _, _, controller := newSeriesController(ctrl)

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
				series.EXPECT().DeleteByTmdbId(gomock.Any(), uint64(1399), id).Return(nil)
			},
			withUser: true,
			param:    "1399",
			expected: result{
				status: "204 No Content",
				code:   http.StatusNoContent,
			},
		},
		{
			name:     "Unauthorized",
			before:   func() {},
			withUser: false,
			param:    "1399",
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
				series.EXPECT().DeleteByTmdbId(gomock.Any(), uint64(1399), id).Return(assert.AnError)
			},
			withUser: true,
			param:    "1399",
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

			req := httptest.NewRequest(http.MethodDelete, "/series/"+tt.param, nil)
			if tt.withUser {
				ctx := context.WithValue(req.Context(), middlewares.CurrentUser{}, &models.User{ID: id})
				req = req.WithContext(ctx)
			}

			w := httptest.NewRecorder()

			r := chi.NewRouter()
			r.Delete("/series/{id}", controller.HandleDelete)
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
