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
	"biinge-api/internal/config/logger"
	"biinge-api/internal/config/middlewares"
)

func Test_UpNextController_HandleUpNext(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	provider := services.NewMockTmdbProvider(ctrl)
	games := services.NewMockIgdbProvider(ctrl)
	log := logger.NewLogger(testConfig())
	controller := NewUpNextController(provider, games, log)

	id, err := uuid.NewRandom()
	require.NoError(t, err)

	type result struct {
		response serializers.UpNextSerializer
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
				provider.EXPECT().FetchUpNext(gomock.Any(), id).Return(&serializers.UpNextSerializer{
					Episodes: []serializers.UpNextEpisodeSerializer{
						{SeriesId: 300, SeriesTitle: "Breaking Bad", Id: 800, Title: "Aired Ep", SeasonNumber: 5, Number: 16, AirDate: "2000-01-01"},
					},
					Movies: []serializers.UpNextMovieSerializer{
						{Id: 500, Title: "Dune", ReleaseDate: "2021-10-22"},
					},
				}, nil)
				games.EXPECT().FetchUpNextGames(gomock.Any(), id).Return([]serializers.UpNextGameSerializer{
					{Id: 1942, Title: "The Witcher 3", ReleaseDate: "2015-05-19"},
				}, nil)
			},
			withUser: true,
			expected: result{
				response: serializers.UpNextSerializer{
					Episodes: []serializers.UpNextEpisodeSerializer{
						{SeriesId: 300, SeriesTitle: "Breaking Bad", Id: 800, Title: "Aired Ep", SeasonNumber: 5, Number: 16, AirDate: "2000-01-01"},
					},
					Movies: []serializers.UpNextMovieSerializer{
						{Id: 500, Title: "Dune", ReleaseDate: "2021-10-22"},
					},
					Games: []serializers.UpNextGameSerializer{
						{Id: 1942, Title: "The Witcher 3", ReleaseDate: "2015-05-19"},
					},
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
				provider.EXPECT().FetchUpNext(gomock.Any(), id).Return(nil, assert.AnError)
			},
			withUser: true,
			expected: result{
				error:  serializers.ErrorSerializer{Error: "assert.AnError general error for testing"},
				status: "422 Unprocessable Entity",
				code:   http.StatusUnprocessableEntity,
			},
			error: true,
		},
		{
			name: "Games Provider Error",
			before: func() {
				provider.EXPECT().FetchUpNext(gomock.Any(), id).Return(&serializers.UpNextSerializer{
					Episodes: []serializers.UpNextEpisodeSerializer{},
					Movies:   []serializers.UpNextMovieSerializer{},
				}, nil)
				games.EXPECT().FetchUpNextGames(gomock.Any(), id).Return(nil, assert.AnError)
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

			req := httptest.NewRequest(http.MethodGet, "/up-next", nil)
			if tt.withUser {
				ctx := context.WithValue(req.Context(), middlewares.CurrentUser{}, &models.User{ID: id})
				req = req.WithContext(ctx)
			}

			w := httptest.NewRecorder()

			r := chi.NewRouter()
			r.Get("/up-next", controller.HandleUpNext)
			r.ServeHTTP(w, req)

			resp := w.Result()
			defer resp.Body.Close()

			if tt.error {
				var response serializers.ErrorSerializer

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.error, response)
			} else {
				var response serializers.UpNextSerializer

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.response, response)
			}

			assert.Equal(t, tt.expected.code, resp.StatusCode)
			assert.Equal(t, tt.expected.status, resp.Status)
		})
	}
}
