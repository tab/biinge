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
	"go.uber.org/mock/gomock"

	"biinge-api/internal/app/models"
	"biinge-api/internal/app/serializers"
	"biinge-api/internal/app/services"
	"biinge-api/internal/config"
	"biinge-api/internal/config/logger"
	"biinge-api/internal/config/middlewares"
)

func Test_UsersController_Me(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	cfg := &config.Config{
		AppEnv:   "test",
		AppAddr:  "localhost:8080",
		LogLevel: "info",
	}

	users := services.NewMockUsers(ctrl)
	log := logger.NewLogger(cfg)
	controller := NewAccountsController(users, log)

	id, err := uuid.NewRandom()
	assert.NoError(t, err)

	type result struct {
		response serializers.UserSerializer
		error    serializers.ErrorSerializer
		status   string
		code     int
	}

	tests := []struct {
		name        string
		currentUser *models.User
		expected    result
	}{
		{
			name: "Success",
			currentUser: &models.User{
				ID:         id,
				Login:      "john.doe",
				Email:      "john.doe@local",
				FirstName:  "John",
				LastName:   "Doe",
				Appearance: "dark",
			},
			expected: result{
				response: serializers.UserSerializer{
					ID:         id,
					Login:      "john.doe",
					Email:      "john.doe@local",
					FirstName:  "John",
					LastName:   "Doe",
					Appearance: "dark",
				},
				status: "200 OK",
				code:   http.StatusOK,
			},
		},
		{
			name:        "Unauthorized",
			currentUser: nil,
			expected: result{
				error:  serializers.ErrorSerializer{Error: "unauthorized"},
				status: "401 Unauthorized",
				code:   http.StatusUnauthorized,
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			req := httptest.NewRequest(http.MethodGet, "/api/me", nil)
			if tt.currentUser != nil {
				ctx := context.WithValue(req.Context(), middlewares.CurrentUser{}, tt.currentUser)
				req = req.WithContext(ctx)
			}
			w := httptest.NewRecorder()

			r := chi.NewRouter()
			r.Get("/api/me", controller.Me)
			r.ServeHTTP(w, req)

			resp := w.Result()
			defer resp.Body.Close()

			if tt.currentUser != nil {
				var response serializers.UserSerializer
				err = json.NewDecoder(resp.Body).Decode(&response)
				assert.NoError(t, err)
				assert.Equal(t, tt.expected.response, response)
			} else {
				var response serializers.ErrorSerializer
				err = json.NewDecoder(resp.Body).Decode(&response)
				assert.NoError(t, err)
				assert.Equal(t, tt.expected.error, response)
			}

			assert.Equal(t, tt.expected.code, resp.StatusCode)
			assert.Equal(t, tt.expected.status, resp.Status)
		})
	}
}

func Test_AccountsController_Update(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	cfg := &config.Config{
		AppEnv:   "test",
		AppAddr:  "localhost:8080",
		LogLevel: "info",
	}

	users := services.NewMockUsers(ctrl)
	log := logger.NewLogger(cfg)
	controller := NewAccountsController(users, log)

	id, err := uuid.NewRandom()
	assert.NoError(t, err)

	type result struct {
		response serializers.UserSerializer
		error    serializers.ErrorSerializer
		status   string
		code     int
	}

	tests := []struct {
		name        string
		before      func()
		currentUser *models.User
		body        io.Reader
		expected    result
		error       bool
	}{
		{
			name: "Success",
			before: func() {
				users.EXPECT().Update(gomock.Any(), gomock.Any()).Return(&models.User{
					ID:         id,
					Login:      "john.doe",
					Email:      "john.doe@local",
					FirstName:  "Jane",
					LastName:   "Doe",
					Appearance: "light",
				}, nil)
			},
			currentUser: &models.User{
				ID:         id,
				Login:      "john.doe",
				Email:      "john.doe@local",
				FirstName:  "John",
				LastName:   "Doe",
				Appearance: "dark",
			},
			body: strings.NewReader(`{ "first_name": "Jane", "last_name": "Doe", "appearance": "light" }`),
			expected: result{
				response: serializers.UserSerializer{
					ID:         id,
					Login:      "john.doe",
					Email:      "john.doe@local",
					FirstName:  "Jane",
					LastName:   "Doe",
					Appearance: "light",
				},
				status: "200 OK",
				code:   http.StatusOK,
			},
		},
		{
			name:        "Unauthorized - No User Context",
			before:      func() {},
			currentUser: nil,
			body:        strings.NewReader(`{ "first_name": "Jane", "last_name": "Doe", "appearance": "light" }`),
			expected: result{
				error:  serializers.ErrorSerializer{Error: "unauthorized"},
				status: "401 Unauthorized",
				code:   http.StatusUnauthorized,
			},
			error: true,
		},
		{
			name:   "Validation Error - Empty First Name",
			before: func() {},
			currentUser: &models.User{
				ID:         id,
				Login:      "john.doe",
				Email:      "john.doe@local",
				FirstName:  "John",
				LastName:   "Doe",
				Appearance: "dark",
			},
			body: strings.NewReader(`{ "first_name": "", "last_name": "Doe", "appearance": "light" }`),
			expected: result{
				error:  serializers.ErrorSerializer{Error: "empty first name"},
				status: "400 Bad Request",
				code:   http.StatusBadRequest,
			},
			error: true,
		},
		{
			name:   "Validation Error - Empty Last Name",
			before: func() {},
			currentUser: &models.User{
				ID:         id,
				Login:      "john.doe",
				Email:      "john.doe@local",
				FirstName:  "John",
				LastName:   "Doe",
				Appearance: "dark",
			},
			body: strings.NewReader(`{ "first_name": "Jane", "last_name": "", "appearance": "light" }`),
			expected: result{
				error:  serializers.ErrorSerializer{Error: "empty last name"},
				status: "400 Bad Request",
				code:   http.StatusBadRequest,
			},
			error: true,
		},
		{
			name:   "Validation Error - Invalid Appearance",
			before: func() {},
			currentUser: &models.User{
				ID:         id,
				Login:      "john.doe",
				Email:      "john.doe@local",
				FirstName:  "John",
				LastName:   "Doe",
				Appearance: "dark",
			},
			body: strings.NewReader(`{ "first_name": "Jane", "last_name": "Doe", "appearance": "" }`),
			expected: result{
				error:  serializers.ErrorSerializer{Error: "empty appearance"},
				status: "400 Bad Request",
				code:   http.StatusBadRequest,
			},
			error: true,
		},
		{
			name: "Error",
			before: func() {
				users.EXPECT().Update(gomock.Any(), gomock.Any()).Return(nil, assert.AnError)
			},
			currentUser: &models.User{
				ID:         id,
				Login:      "john.doe",
				Email:      "john.doe@local",
				FirstName:  "John",
				LastName:   "Doe",
				Appearance: "dark",
			},
			body: strings.NewReader(`{ "first_name": "Jane", "last_name": "Doe", "appearance": "light" }`),
			expected: result{
				error:  serializers.ErrorSerializer{Error: "assert.AnError general error for testing"},
				status: "400 Bad Request",
				code:   http.StatusBadRequest,
			},
			error: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			req := httptest.NewRequest(http.MethodPatch, "/api/accounts", tt.body)
			if tt.currentUser != nil {
				ctx := context.WithValue(req.Context(), middlewares.CurrentUser{}, tt.currentUser)
				req = req.WithContext(ctx)
			}
			w := httptest.NewRecorder()

			r := chi.NewRouter()
			r.Patch("/api/accounts", controller.HandleUpdate)
			r.ServeHTTP(w, req)

			resp := w.Result()
			defer resp.Body.Close()

			if tt.error {
				var response serializers.ErrorSerializer
				err := json.NewDecoder(resp.Body).Decode(&response)
				assert.NoError(t, err)
				assert.Equal(t, tt.expected.error, response)
			} else {
				var response serializers.UserSerializer
				err := json.NewDecoder(resp.Body).Decode(&response)
				assert.NoError(t, err)
				assert.Equal(t, tt.expected.response, response)
			}

			assert.Equal(t, tt.expected.code, resp.StatusCode)
			assert.Equal(t, tt.expected.status, resp.Status)
		})
	}
}
