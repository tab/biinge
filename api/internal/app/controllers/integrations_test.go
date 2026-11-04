package controllers

import (
	"context"
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

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/models"
	"biinge-api/internal/app/services"
	"biinge-api/internal/config/middlewares"
	"biinge-api/pkg/jellyfin"
)

func Test_IntegrationsController_HandleConnect(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	integrations := services.NewMockIntegrations(ctrl)
	controller := NewIntegrationsController(integrations)

	user := &models.User{ID: uuid.New()}

	const body = `{"username":"  alice  ","password":" secret "}`

	credentials := jellyfin.Credentials{Username: "alice", Password: " secret "}

	tests := []struct {
		name     string
		before   func()
		withUser bool
		body     string
		code     int
		response string
	}{
		{
			name: "Success",
			before: func() {
				integrations.EXPECT().
					Connect(gomock.Any(), user.ID, credentials).
					Return(&models.JellyfinConnection{BaseURL: "https://jellyfin.example.com", Connected: true, Username: "alice"}, nil)
			},
			withUser: true,
			body:     body,
			code:     http.StatusOK,
			response: `{"base_url":"https://jellyfin.example.com","connected":true,"username":"alice"}`,
		},
		{
			name:     "Unauthorized",
			before:   func() {},
			withUser: false,
			body:     body,
			code:     http.StatusUnauthorized,
			response: `{"error":"unauthorized"}`,
		},
		{
			name:     "Malformed body",
			before:   func() {},
			withUser: true,
			body:     `{"username":`,
			code:     http.StatusBadRequest,
			response: `{"error":"unexpected EOF"}`,
		},
		{
			name:     "Empty username",
			before:   func() {},
			withUser: true,
			body:     `{"username":"   ","password":"secret"}`,
			code:     http.StatusBadRequest,
			response: `{"error":"empty login"}`,
		},
		{
			name:     "Empty password",
			before:   func() {},
			withUser: true,
			body:     `{"username":"alice","password":""}`,
			code:     http.StatusBadRequest,
			response: `{"error":"empty password"}`,
		},
		{
			name: "Jellyfin not configured",
			before: func() {
				integrations.EXPECT().Connect(gomock.Any(), user.ID, credentials).Return(nil, errors.ErrJellyfinNotConfigured)
			},
			withUser: true,
			body:     body,
			code:     http.StatusNotFound,
			response: `{"error":"jellyfin is not configured"}`,
		},
		{
			name: "Invalid Jellyfin credentials",
			before: func() {
				integrations.EXPECT().Connect(gomock.Any(), user.ID, credentials).Return(nil, errors.ErrInvalidJellyfinCredentials)
			},
			withUser: true,
			body:     body,
			code:     http.StatusUnprocessableEntity,
			response: `{"error":"invalid jellyfin credentials"}`,
		},
		{
			name: "Jellyfin unavailable",
			before: func() {
				integrations.EXPECT().Connect(gomock.Any(), user.ID, credentials).Return(nil, errors.ErrJellyfinUnavailable)
			},
			withUser: true,
			body:     body,
			code:     http.StatusBadGateway,
			response: `{"error":"jellyfin unavailable"}`,
		},
		{
			name: "Failed to save",
			before: func() {
				integrations.EXPECT().Connect(gomock.Any(), user.ID, credentials).Return(nil, errors.ErrFailedToSaveJellyfinConnection)
			},
			withUser: true,
			body:     body,
			code:     http.StatusServiceUnavailable,
			response: `{"error":"failed to save jellyfin connection"}`,
		},
		{
			name: "Unexpected error",
			before: func() {
				integrations.EXPECT().Connect(gomock.Any(), user.ID, credentials).Return(nil, assert.AnError)
			},
			withUser: true,
			body:     body,
			code:     http.StatusInternalServerError,
			response: `{"error":"` + assert.AnError.Error() + `"}`,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			req := httptest.NewRequest(http.MethodPut, "/api/v1/accounts/integrations/jellyfin/connection", strings.NewReader(tt.body))
			if tt.withUser {
				req = req.WithContext(context.WithValue(req.Context(), middlewares.CurrentUser{}, user))
			}

			w := httptest.NewRecorder()

			r := chi.NewRouter()
			r.Put("/api/v1/accounts/integrations/jellyfin/connection", controller.HandleConnect)
			r.ServeHTTP(w, req)

			resp := w.Result()
			defer resp.Body.Close()

			body, err := io.ReadAll(resp.Body)
			require.NoError(t, err)

			assert.Equal(t, tt.code, resp.StatusCode)
			assert.Equal(t, "application/json", resp.Header.Get("Content-Type"))
			assert.JSONEq(t, tt.response, string(body))
			assert.NotContains(t, string(body), "token")
		})
	}
}

func Test_IntegrationsController_HandleStatus(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	integrations := services.NewMockIntegrations(ctrl)
	controller := NewIntegrationsController(integrations)

	user := &models.User{ID: uuid.New()}

	tests := []struct {
		name     string
		before   func()
		withUser bool
		code     int
		response string
	}{
		{
			name: "Connected",
			before: func() {
				integrations.EXPECT().
					Status(gomock.Any(), user.ID).
					Return(&models.JellyfinConnection{BaseURL: "https://jellyfin.example.com", Connected: true, Username: "alice"}, nil)
			},
			withUser: true,
			code:     http.StatusOK,
			response: `{"base_url":"https://jellyfin.example.com","connected":true,"username":"alice"}`,
		},
		{
			name: "Not connected",
			before: func() {
				integrations.EXPECT().
					Status(gomock.Any(), user.ID).
					Return(&models.JellyfinConnection{BaseURL: "https://jellyfin.example.com"}, nil)
			},
			withUser: true,
			code:     http.StatusOK,
			response: `{"base_url":"https://jellyfin.example.com","connected":false}`,
		},
		{
			name:     "Unauthorized",
			before:   func() {},
			withUser: false,
			code:     http.StatusUnauthorized,
			response: `{"error":"unauthorized"}`,
		},
		{
			name: "Jellyfin not configured",
			before: func() {
				integrations.EXPECT().Status(gomock.Any(), user.ID).Return(nil, errors.ErrJellyfinNotConfigured)
			},
			withUser: true,
			code:     http.StatusNotFound,
			response: `{"error":"jellyfin is not configured"}`,
		},
		{
			name: "Failed to fetch",
			before: func() {
				integrations.EXPECT().Status(gomock.Any(), user.ID).Return(nil, errors.ErrFailedToFetchJellyfinConnection)
			},
			withUser: true,
			code:     http.StatusServiceUnavailable,
			response: `{"error":"failed to fetch jellyfin connection"}`,
		},
		{
			name: "Unexpected error",
			before: func() {
				integrations.EXPECT().Status(gomock.Any(), user.ID).Return(nil, assert.AnError)
			},
			withUser: true,
			code:     http.StatusInternalServerError,
			response: `{"error":"` + assert.AnError.Error() + `"}`,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			req := httptest.NewRequest(http.MethodGet, "/api/v1/accounts/integrations/jellyfin/connection", nil)
			if tt.withUser {
				req = req.WithContext(context.WithValue(req.Context(), middlewares.CurrentUser{}, user))
			}

			w := httptest.NewRecorder()

			r := chi.NewRouter()
			r.Get("/api/v1/accounts/integrations/jellyfin/connection", controller.HandleStatus)
			r.ServeHTTP(w, req)

			resp := w.Result()
			defer resp.Body.Close()

			body, err := io.ReadAll(resp.Body)
			require.NoError(t, err)

			assert.Equal(t, tt.code, resp.StatusCode)
			assert.Equal(t, "application/json", resp.Header.Get("Content-Type"))
			assert.JSONEq(t, tt.response, string(body))
			assert.NotContains(t, string(body), "token")
		})
	}
}

func Test_IntegrationsController_HandleDisconnect(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	integrations := services.NewMockIntegrations(ctrl)
	controller := NewIntegrationsController(integrations)

	user := &models.User{ID: uuid.New()}

	tests := []struct {
		name     string
		before   func()
		withUser bool
		code     int
		response string
	}{
		{
			name: "Success",
			before: func() {
				integrations.EXPECT().Disconnect(gomock.Any(), user.ID).Return(nil)
			},
			withUser: true,
			code:     http.StatusNoContent,
		},
		{
			name:     "Unauthorized",
			before:   func() {},
			withUser: false,
			code:     http.StatusUnauthorized,
			response: `{"error":"unauthorized"}`,
		},
		{
			name: "Jellyfin not configured",
			before: func() {
				integrations.EXPECT().Disconnect(gomock.Any(), user.ID).Return(errors.ErrJellyfinNotConfigured)
			},
			withUser: true,
			code:     http.StatusNotFound,
			response: `{"error":"jellyfin is not configured"}`,
		},
		{
			name: "Failed to delete",
			before: func() {
				integrations.EXPECT().Disconnect(gomock.Any(), user.ID).Return(errors.ErrFailedToDeleteJellyfinConnection)
			},
			withUser: true,
			code:     http.StatusServiceUnavailable,
			response: `{"error":"failed to delete jellyfin connection"}`,
		},
		{
			name: "Unexpected error",
			before: func() {
				integrations.EXPECT().Disconnect(gomock.Any(), user.ID).Return(assert.AnError)
			},
			withUser: true,
			code:     http.StatusInternalServerError,
			response: `{"error":"` + assert.AnError.Error() + `"}`,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			req := httptest.NewRequest(http.MethodDelete, "/api/v1/accounts/integrations/jellyfin/connection", nil)
			if tt.withUser {
				req = req.WithContext(context.WithValue(req.Context(), middlewares.CurrentUser{}, user))
			}

			w := httptest.NewRecorder()

			r := chi.NewRouter()
			r.Delete("/api/v1/accounts/integrations/jellyfin/connection", controller.HandleDisconnect)
			r.ServeHTTP(w, req)

			resp := w.Result()
			defer resp.Body.Close()

			body, err := io.ReadAll(resp.Body)
			require.NoError(t, err)

			assert.Equal(t, tt.code, resp.StatusCode)

			if tt.response == "" {
				assert.Empty(t, body)
				return
			}

			assert.JSONEq(t, tt.response, string(body))
		})
	}
}
