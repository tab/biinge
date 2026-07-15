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
	"biinge-api/internal/config/middlewares"
)

func Test_SeriesController_HandleProgress(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	_, progress, _, controller := newSeriesController(ctrl)

	id, err := uuid.NewRandom()
	require.NoError(t, err)

	type result struct {
		response serializers.ProgressResponseSerializer
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
				progress.EXPECT().Get(gomock.Any(), id, uint64(1399)).Return(&models.SeriesProgress{
					SeriesTmdbId:    1399,
					State:           "watching",
					WatchedSeasons:  []uint64{1},
					WatchedEpisodes: []uint64{101, 102},
				}, nil)
			},
			withUser: true,
			param:    "1399",
			expected: result{
				response: serializers.ProgressResponseSerializer{
					Id:              1399,
					State:           "watching",
					WatchedSeasons:  []uint64{1},
					WatchedEpisodes: []uint64{101, 102},
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
			name: "Service Error",
			before: func() {
				progress.EXPECT().Get(gomock.Any(), id, uint64(1399)).Return(nil, assert.AnError)
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

			req := httptest.NewRequest(http.MethodGet, "/series/"+tt.param+"/progress", nil)
			if tt.withUser {
				ctx := context.WithValue(req.Context(), middlewares.CurrentUser{}, &models.User{ID: id})
				req = req.WithContext(ctx)
			}

			w := httptest.NewRecorder()

			r := chi.NewRouter()
			r.Get("/series/{id}/progress", controller.HandleProgress)
			r.ServeHTTP(w, req)

			resp := w.Result()
			defer resp.Body.Close()

			if tt.error {
				var response serializers.ErrorSerializer

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.error, response)
			} else {
				var response serializers.ProgressResponseSerializer

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.response, response)
			}

			assert.Equal(t, tt.expected.code, resp.StatusCode)
			assert.Equal(t, tt.expected.status, resp.Status)
		})
	}
}

func Test_SeriesController_HandleMarkShowWatched(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	_, progress, _, controller := newSeriesController(ctrl)

	id, err := uuid.NewRandom()
	require.NoError(t, err)

	type result struct {
		response serializers.ProgressResponseSerializer
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
				progress.EXPECT().MarkShow(gomock.Any(), id, gomock.Any()).Return(&models.SeriesProgress{
					SeriesTmdbId:    1399,
					State:           "watched",
					WatchedSeasons:  []uint64{1},
					WatchedEpisodes: []uint64{101},
				}, nil)
			},
			withUser: true,
			param:    "1399",
			body:     strings.NewReader(`{ "series": { "title": "Game of Thrones", "posterPath": "/g.jpg", "seasonsCount": 8, "episodesCount": 73, "status": "Ended" }, "seasons": [] }`),
			expected: result{
				response: serializers.ProgressResponseSerializer{
					Id:              1399,
					State:           "watched",
					WatchedSeasons:  []uint64{1},
					WatchedEpisodes: []uint64{101},
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
			body:     strings.NewReader(`{ "series": { "title": "Game of Thrones" } }`),
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
			body:     strings.NewReader(`{ "series": { "title": "Game of Thrones" } }`),
			expected: result{
				error:  serializers.ErrorSerializer{Error: "invalid tmdb id"},
				status: "400 Bad Request",
				code:   http.StatusBadRequest,
			},
			error: true,
		},
		{
			name:     "Validation Error - Empty Title",
			before:   func() {},
			withUser: true,
			param:    "1399",
			body:     strings.NewReader(`{ "series": { "title": "" } }`),
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
				progress.EXPECT().MarkShow(gomock.Any(), id, gomock.Any()).Return(nil, assert.AnError)
			},
			withUser: true,
			param:    "1399",
			body:     strings.NewReader(`{ "series": { "title": "Game of Thrones" } }`),
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

			req := httptest.NewRequest(http.MethodPost, "/series/"+tt.param+"/watched", tt.body)
			if tt.withUser {
				ctx := context.WithValue(req.Context(), middlewares.CurrentUser{}, &models.User{ID: id})
				req = req.WithContext(ctx)
			}

			w := httptest.NewRecorder()

			r := chi.NewRouter()
			r.Post("/series/{id}/watched", controller.HandleMarkShowWatched)
			r.ServeHTTP(w, req)

			resp := w.Result()
			defer resp.Body.Close()

			if tt.error {
				var response serializers.ErrorSerializer

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.error, response)
			} else {
				var response serializers.ProgressResponseSerializer

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.response, response)
			}

			assert.Equal(t, tt.expected.code, resp.StatusCode)
			assert.Equal(t, tt.expected.status, resp.Status)
		})
	}
}

func Test_SeriesController_HandleUnmarkShowWatched(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	_, progress, _, controller := newSeriesController(ctrl)

	id, err := uuid.NewRandom()
	require.NoError(t, err)

	type result struct {
		response serializers.ProgressResponseSerializer
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
				progress.EXPECT().UnmarkShow(gomock.Any(), id, uint64(1399)).Return(&models.SeriesProgress{
					SeriesTmdbId:    1399,
					State:           "want",
					WatchedSeasons:  []uint64{},
					WatchedEpisodes: []uint64{},
				}, nil)
			},
			withUser: true,
			param:    "1399",
			expected: result{
				response: serializers.ProgressResponseSerializer{
					Id:              1399,
					State:           "want",
					WatchedSeasons:  []uint64{},
					WatchedEpisodes: []uint64{},
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
			name: "Service Error",
			before: func() {
				progress.EXPECT().UnmarkShow(gomock.Any(), id, uint64(1399)).Return(nil, assert.AnError)
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

			req := httptest.NewRequest(http.MethodDelete, "/series/"+tt.param+"/watched", nil)
			if tt.withUser {
				ctx := context.WithValue(req.Context(), middlewares.CurrentUser{}, &models.User{ID: id})
				req = req.WithContext(ctx)
			}

			w := httptest.NewRecorder()

			r := chi.NewRouter()
			r.Delete("/series/{id}/watched", controller.HandleUnmarkShowWatched)
			r.ServeHTTP(w, req)

			resp := w.Result()
			defer resp.Body.Close()

			if tt.error {
				var response serializers.ErrorSerializer

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.error, response)
			} else {
				var response serializers.ProgressResponseSerializer

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.response, response)
			}

			assert.Equal(t, tt.expected.code, resp.StatusCode)
			assert.Equal(t, tt.expected.status, resp.Status)
		})
	}
}

func Test_SeriesController_HandleMarkSeasonWatched(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	_, progress, _, controller := newSeriesController(ctrl)

	id, err := uuid.NewRandom()
	require.NoError(t, err)

	type result struct {
		response serializers.ProgressResponseSerializer
		error    serializers.ErrorSerializer
		status   string
		code     int
	}

	tests := []struct {
		name     string
		before   func()
		withUser bool
		path     string
		body     io.Reader
		expected result
		error    bool
	}{
		{
			name: "Success",
			before: func() {
				progress.EXPECT().MarkSeason(gomock.Any(), id, gomock.Any(), gomock.Any()).Return(&models.SeriesProgress{
					SeriesTmdbId:    1399,
					State:           "watching",
					WatchedSeasons:  []uint64{3624},
					WatchedEpisodes: []uint64{101},
				}, nil)
			},
			withUser: true,
			path:     "/series/1399/seasons/3624/watched",
			body:     strings.NewReader(`{ "series": { "title": "Game of Thrones" }, "season": { "title": "Season 1", "number": 1, "episodesCount": 10 }, "episodes": [] }`),
			expected: result{
				response: serializers.ProgressResponseSerializer{
					Id:              1399,
					State:           "watching",
					WatchedSeasons:  []uint64{3624},
					WatchedEpisodes: []uint64{101},
				},
				status: "200 OK",
				code:   http.StatusOK,
			},
		},
		{
			name:     "Unauthorized",
			before:   func() {},
			withUser: false,
			path:     "/series/1399/seasons/3624/watched",
			body:     strings.NewReader(`{ "series": { "title": "Game of Thrones" } }`),
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
			path:     "/series/abc/seasons/3624/watched",
			body:     strings.NewReader(`{ "series": { "title": "Game of Thrones" } }`),
			expected: result{
				error:  serializers.ErrorSerializer{Error: "invalid tmdb id"},
				status: "400 Bad Request",
				code:   http.StatusBadRequest,
			},
			error: true,
		},
		{
			name:     "Invalid Season Id",
			before:   func() {},
			withUser: true,
			path:     "/series/1399/seasons/abc/watched",
			body:     strings.NewReader(`{ "series": { "title": "Game of Thrones" } }`),
			expected: result{
				error:  serializers.ErrorSerializer{Error: "invalid tmdb id"},
				status: "400 Bad Request",
				code:   http.StatusBadRequest,
			},
			error: true,
		},
		{
			name:     "Validation Error - Empty Title",
			before:   func() {},
			withUser: true,
			path:     "/series/1399/seasons/3624/watched",
			body:     strings.NewReader(`{ "series": { "title": "" } }`),
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
				progress.EXPECT().MarkSeason(gomock.Any(), id, gomock.Any(), gomock.Any()).Return(nil, assert.AnError)
			},
			withUser: true,
			path:     "/series/1399/seasons/3624/watched",
			body:     strings.NewReader(`{ "series": { "title": "Game of Thrones" }, "season": { "title": "Season 1", "number": 1 } }`),
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

			req := httptest.NewRequest(http.MethodPost, tt.path, tt.body)
			if tt.withUser {
				ctx := context.WithValue(req.Context(), middlewares.CurrentUser{}, &models.User{ID: id})
				req = req.WithContext(ctx)
			}

			w := httptest.NewRecorder()

			r := chi.NewRouter()
			r.Post("/series/{id}/seasons/{seasonId}/watched", controller.HandleMarkSeasonWatched)
			r.ServeHTTP(w, req)

			resp := w.Result()
			defer resp.Body.Close()

			if tt.error {
				var response serializers.ErrorSerializer

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.error, response)
			} else {
				var response serializers.ProgressResponseSerializer

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.response, response)
			}

			assert.Equal(t, tt.expected.code, resp.StatusCode)
			assert.Equal(t, tt.expected.status, resp.Status)
		})
	}
}

func Test_SeriesController_HandleUnmarkSeasonWatched(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	_, progress, _, controller := newSeriesController(ctrl)

	id, err := uuid.NewRandom()
	require.NoError(t, err)

	type result struct {
		response serializers.ProgressResponseSerializer
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
				progress.EXPECT().UnmarkSeason(gomock.Any(), id, uint64(1399), uint64(3624)).Return(&models.SeriesProgress{
					SeriesTmdbId:    1399,
					State:           "watching",
					WatchedSeasons:  []uint64{},
					WatchedEpisodes: []uint64{},
				}, nil)
			},
			withUser: true,
			path:     "/series/1399/seasons/3624/watched",
			expected: result{
				response: serializers.ProgressResponseSerializer{
					Id:              1399,
					State:           "watching",
					WatchedSeasons:  []uint64{},
					WatchedEpisodes: []uint64{},
				},
				status: "200 OK",
				code:   http.StatusOK,
			},
		},
		{
			name:     "Unauthorized",
			before:   func() {},
			withUser: false,
			path:     "/series/1399/seasons/3624/watched",
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
			path:     "/series/abc/seasons/3624/watched",
			expected: result{
				error:  serializers.ErrorSerializer{Error: "invalid tmdb id"},
				status: "400 Bad Request",
				code:   http.StatusBadRequest,
			},
			error: true,
		},
		{
			name:     "Invalid Season Id",
			before:   func() {},
			withUser: true,
			path:     "/series/1399/seasons/abc/watched",
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
				progress.EXPECT().UnmarkSeason(gomock.Any(), id, uint64(1399), uint64(3624)).Return(nil, assert.AnError)
			},
			withUser: true,
			path:     "/series/1399/seasons/3624/watched",
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

			req := httptest.NewRequest(http.MethodDelete, tt.path, nil)
			if tt.withUser {
				ctx := context.WithValue(req.Context(), middlewares.CurrentUser{}, &models.User{ID: id})
				req = req.WithContext(ctx)
			}

			w := httptest.NewRecorder()

			r := chi.NewRouter()
			r.Delete("/series/{id}/seasons/{seasonId}/watched", controller.HandleUnmarkSeasonWatched)
			r.ServeHTTP(w, req)

			resp := w.Result()
			defer resp.Body.Close()

			if tt.error {
				var response serializers.ErrorSerializer

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.error, response)
			} else {
				var response serializers.ProgressResponseSerializer

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.response, response)
			}

			assert.Equal(t, tt.expected.code, resp.StatusCode)
			assert.Equal(t, tt.expected.status, resp.Status)
		})
	}
}

func Test_SeriesController_HandleMarkEpisodeWatched(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	_, progress, _, controller := newSeriesController(ctrl)

	id, err := uuid.NewRandom()
	require.NoError(t, err)

	type result struct {
		response serializers.ProgressResponseSerializer
		error    serializers.ErrorSerializer
		status   string
		code     int
	}

	tests := []struct {
		name     string
		before   func()
		withUser bool
		path     string
		body     io.Reader
		expected result
		error    bool
	}{
		{
			name: "Success",
			before: func() {
				progress.EXPECT().MarkEpisode(gomock.Any(), id, gomock.Any(), gomock.Any(), gomock.Any()).Return(&models.SeriesProgress{
					SeriesTmdbId:    1399,
					State:           "watching",
					WatchedSeasons:  []uint64{},
					WatchedEpisodes: []uint64{63056},
				}, nil)
			},
			withUser: true,
			path:     "/series/1399/seasons/3624/episodes/63056/watched",
			body:     strings.NewReader(`{ "series": { "title": "Game of Thrones" }, "season": { "title": "Season 1", "number": 1 }, "episode": { "title": "Winter Is Coming", "runtime": 62, "airDate": "2011-04-17" } }`),
			expected: result{
				response: serializers.ProgressResponseSerializer{
					Id:              1399,
					State:           "watching",
					WatchedSeasons:  []uint64{},
					WatchedEpisodes: []uint64{63056},
				},
				status: "200 OK",
				code:   http.StatusOK,
			},
		},
		{
			name:     "Unauthorized",
			before:   func() {},
			withUser: false,
			path:     "/series/1399/seasons/3624/episodes/63056/watched",
			body:     strings.NewReader(`{ "series": { "title": "Game of Thrones" } }`),
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
			path:     "/series/abc/seasons/3624/episodes/63056/watched",
			body:     strings.NewReader(`{ "series": { "title": "Game of Thrones" } }`),
			expected: result{
				error:  serializers.ErrorSerializer{Error: "invalid tmdb id"},
				status: "400 Bad Request",
				code:   http.StatusBadRequest,
			},
			error: true,
		},
		{
			name:     "Invalid Season Id",
			before:   func() {},
			withUser: true,
			path:     "/series/1399/seasons/abc/episodes/63056/watched",
			body:     strings.NewReader(`{ "series": { "title": "Game of Thrones" } }`),
			expected: result{
				error:  serializers.ErrorSerializer{Error: "invalid tmdb id"},
				status: "400 Bad Request",
				code:   http.StatusBadRequest,
			},
			error: true,
		},
		{
			name:     "Invalid Episode Id",
			before:   func() {},
			withUser: true,
			path:     "/series/1399/seasons/3624/episodes/abc/watched",
			body:     strings.NewReader(`{ "series": { "title": "Game of Thrones" } }`),
			expected: result{
				error:  serializers.ErrorSerializer{Error: "invalid tmdb id"},
				status: "400 Bad Request",
				code:   http.StatusBadRequest,
			},
			error: true,
		},
		{
			name:     "Validation Error - Empty Title",
			before:   func() {},
			withUser: true,
			path:     "/series/1399/seasons/3624/episodes/63056/watched",
			body:     strings.NewReader(`{ "series": { "title": "" } }`),
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
				progress.EXPECT().MarkEpisode(gomock.Any(), id, gomock.Any(), gomock.Any(), gomock.Any()).Return(nil, assert.AnError)
			},
			withUser: true,
			path:     "/series/1399/seasons/3624/episodes/63056/watched",
			body:     strings.NewReader(`{ "series": { "title": "Game of Thrones" }, "season": { "title": "Season 1", "number": 1 }, "episode": { "title": "Winter Is Coming", "runtime": 62 } }`),
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

			req := httptest.NewRequest(http.MethodPost, tt.path, tt.body)
			if tt.withUser {
				ctx := context.WithValue(req.Context(), middlewares.CurrentUser{}, &models.User{ID: id})
				req = req.WithContext(ctx)
			}

			w := httptest.NewRecorder()

			r := chi.NewRouter()
			r.Post("/series/{id}/seasons/{seasonId}/episodes/{episodeId}/watched", controller.HandleMarkEpisodeWatched)
			r.ServeHTTP(w, req)

			resp := w.Result()
			defer resp.Body.Close()

			if tt.error {
				var response serializers.ErrorSerializer

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.error, response)
			} else {
				var response serializers.ProgressResponseSerializer

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.response, response)
			}

			assert.Equal(t, tt.expected.code, resp.StatusCode)
			assert.Equal(t, tt.expected.status, resp.Status)
		})
	}
}

func Test_SeriesController_HandleUnmarkEpisodeWatched(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	_, progress, _, controller := newSeriesController(ctrl)

	id, err := uuid.NewRandom()
	require.NoError(t, err)

	type result struct {
		response serializers.ProgressResponseSerializer
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
				progress.EXPECT().UnmarkEpisode(gomock.Any(), id, uint64(1399), uint64(3624), uint64(63056)).Return(&models.SeriesProgress{
					SeriesTmdbId:    1399,
					State:           "watching",
					WatchedSeasons:  []uint64{},
					WatchedEpisodes: []uint64{},
				}, nil)
			},
			withUser: true,
			path:     "/series/1399/seasons/3624/episodes/63056/watched",
			expected: result{
				response: serializers.ProgressResponseSerializer{
					Id:              1399,
					State:           "watching",
					WatchedSeasons:  []uint64{},
					WatchedEpisodes: []uint64{},
				},
				status: "200 OK",
				code:   http.StatusOK,
			},
		},
		{
			name:     "Unauthorized",
			before:   func() {},
			withUser: false,
			path:     "/series/1399/seasons/3624/episodes/63056/watched",
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
			path:     "/series/abc/seasons/3624/episodes/63056/watched",
			expected: result{
				error:  serializers.ErrorSerializer{Error: "invalid tmdb id"},
				status: "400 Bad Request",
				code:   http.StatusBadRequest,
			},
			error: true,
		},
		{
			name:     "Invalid Season Id",
			before:   func() {},
			withUser: true,
			path:     "/series/1399/seasons/abc/episodes/63056/watched",
			expected: result{
				error:  serializers.ErrorSerializer{Error: "invalid tmdb id"},
				status: "400 Bad Request",
				code:   http.StatusBadRequest,
			},
			error: true,
		},
		{
			name:     "Invalid Episode Id",
			before:   func() {},
			withUser: true,
			path:     "/series/1399/seasons/3624/episodes/abc/watched",
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
				progress.EXPECT().UnmarkEpisode(gomock.Any(), id, uint64(1399), uint64(3624), uint64(63056)).Return(nil, assert.AnError)
			},
			withUser: true,
			path:     "/series/1399/seasons/3624/episodes/63056/watched",
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

			req := httptest.NewRequest(http.MethodDelete, tt.path, nil)
			if tt.withUser {
				ctx := context.WithValue(req.Context(), middlewares.CurrentUser{}, &models.User{ID: id})
				req = req.WithContext(ctx)
			}

			w := httptest.NewRecorder()

			r := chi.NewRouter()
			r.Delete("/series/{id}/seasons/{seasonId}/episodes/{episodeId}/watched", controller.HandleUnmarkEpisodeWatched)
			r.ServeHTTP(w, req)

			resp := w.Result()
			defer resp.Body.Close()

			if tt.error {
				var response serializers.ErrorSerializer

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.error, response)
			} else {
				var response serializers.ProgressResponseSerializer

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.response, response)
			}

			assert.Equal(t, tt.expected.code, resp.StatusCode)
			assert.Equal(t, tt.expected.status, resp.Status)
		})
	}
}
