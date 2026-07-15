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

func Test_PeopleController_HandleDetails(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	provider := services.NewMockTmdbProvider(ctrl)
	log := logger.NewLogger(testConfig())
	controller := NewPeopleController(provider, log)

	id, err := uuid.NewRandom()
	require.NoError(t, err)

	type result struct {
		response serializers.PersonDetailsSerializer
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
				provider.EXPECT().FetchPersonDetails(gomock.Any(), uint64(287), id).Return(&serializers.PersonDetailsSerializer{
					Id:          287,
					Name:        "Brad Pitt",
					ProfilePath: "/p.jpg",
					Gender:      2,
				}, nil)
			},
			withUser: true,
			param:    "287",
			expected: result{
				response: serializers.PersonDetailsSerializer{
					Id:          287,
					Name:        "Brad Pitt",
					ProfilePath: "/p.jpg",
					Gender:      2,
				},
				status: "200 OK",
				code:   http.StatusOK,
			},
		},
		{
			name:     "Unauthorized",
			before:   func() {},
			withUser: false,
			param:    "287",
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
				provider.EXPECT().FetchPersonDetails(gomock.Any(), uint64(287), id).Return(nil, assert.AnError)
			},
			withUser: true,
			param:    "287",
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

			req := httptest.NewRequest(http.MethodGet, "/people/"+tt.param, nil)
			if tt.withUser {
				ctx := context.WithValue(req.Context(), middlewares.CurrentUser{}, &models.User{ID: id})
				req = req.WithContext(ctx)
			}

			w := httptest.NewRecorder()

			r := chi.NewRouter()
			r.Get("/people/{id}", controller.HandleDetails)
			r.ServeHTTP(w, req)

			resp := w.Result()
			defer resp.Body.Close()

			if tt.error {
				var response serializers.ErrorSerializer

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.error, response)
			} else {
				var response serializers.PersonDetailsSerializer

				err := json.NewDecoder(resp.Body).Decode(&response)
				require.NoError(t, err)
				assert.Equal(t, tt.expected.response, response)
			}

			assert.Equal(t, tt.expected.code, resp.StatusCode)
			assert.Equal(t, tt.expected.status, resp.Status)
		})
	}
}
