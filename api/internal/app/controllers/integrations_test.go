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

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/models"
	"biinge-api/internal/app/serializers"
	"biinge-api/internal/app/services"
	"biinge-api/internal/config/middlewares"
	"biinge-api/pkg/jellyfin"
)

func Test_IntegrationsController_HandleCreateToken(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	integrations := services.NewMockIntegrations(ctrl)
	handler := services.NewMockJellyfin(ctrl)
	controller := NewIntegrationsController(integrations, handler)

	user := &models.User{ID: uuid.New()}

	const token = "0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f"

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
				integrations.EXPECT().CreateToken(gomock.Any(), user.ID).Return(token, nil)
			},
			withUser: true,
			code:     http.StatusCreated,
			response: `{"token":"` + token + `"}`,
		},
		{
			name:     "Unauthorized",
			before:   func() {},
			withUser: false,
			code:     http.StatusUnauthorized,
			response: `{"error":"unauthorized"}`,
		},
		{
			name: "Error",
			before: func() {
				integrations.EXPECT().CreateToken(gomock.Any(), user.ID).Return("", errors.ErrFailedToCreateIntegration)
			},
			withUser: true,
			code:     http.StatusUnprocessableEntity,
			response: `{"error":"failed to create integration"}`,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			req := httptest.NewRequest(http.MethodPost, "/api/v1/accounts/integrations/jellyfin", nil)
			if tt.withUser {
				req = req.WithContext(context.WithValue(req.Context(), middlewares.CurrentUser{}, user))
			}

			w := httptest.NewRecorder()

			r := chi.NewRouter()
			r.Post("/api/v1/accounts/integrations/jellyfin", controller.HandleCreateToken)
			r.ServeHTTP(w, req)

			resp := w.Result()
			defer resp.Body.Close()

			body, err := io.ReadAll(resp.Body)
			require.NoError(t, err)

			assert.Equal(t, tt.code, resp.StatusCode)
			assert.Equal(t, "application/json", resp.Header.Get("Content-Type"))
			assert.JSONEq(t, tt.response, string(body))
		})
	}
}

func Test_IntegrationsController_HandleRevoke(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	integrations := services.NewMockIntegrations(ctrl)
	handler := services.NewMockJellyfin(ctrl)
	controller := NewIntegrationsController(integrations, handler)

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
				integrations.EXPECT().Revoke(gomock.Any(), user.ID).Return(nil)
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
			name: "Error",
			before: func() {
				integrations.EXPECT().Revoke(gomock.Any(), user.ID).Return(errors.ErrFailedToDeleteIntegration)
			},
			withUser: true,
			code:     http.StatusUnprocessableEntity,
			response: `{"error":"failed to delete integration"}`,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			req := httptest.NewRequest(http.MethodDelete, "/api/v1/accounts/integrations/jellyfin", nil)
			if tt.withUser {
				req = req.WithContext(context.WithValue(req.Context(), middlewares.CurrentUser{}, user))
			}

			w := httptest.NewRecorder()

			r := chi.NewRouter()
			r.Delete("/api/v1/accounts/integrations/jellyfin", controller.HandleRevoke)
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

func Test_IntegrationsController_HandleJellyfinWebhook(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	integrations := services.NewMockIntegrations(ctrl)
	handler := services.NewMockJellyfin(ctrl)
	controller := NewIntegrationsController(integrations, handler)

	const token = "0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f0f"

	link := &models.Integration{ID: uuid.New(), UserId: uuid.New(), Provider: models.JellyfinProvider}
	event := `{"ItemType":"Movie","SaveReason":"PlaybackFinished","Played":true,"Provider_tmdb":"603","Extra":"kept"}`

	authenticated := func() {
		integrations.EXPECT().Authenticate(gomock.Any(), token).Return(link, nil)
	}

	tests := []struct {
		name     string
		before   func()
		header   string
		body     string
		code     int
		response string
	}{
		{
			name: "Mark written",
			before: func() {
				authenticated()
				handler.EXPECT().
					Handle(gomock.Any(), link, gomock.Any()).
					DoAndReturn(func(_ context.Context, _ *models.Integration, params *jellyfin.Event) error {
						assert.Equal(t, "Movie", params.ItemType)
						assert.Equal(t, "603", params.ProviderTmdb)
						assert.JSONEq(t, event, string(params.Raw))

						return nil
					})
			},
			header: "Bearer " + token,
			body:   event,
			code:   http.StatusNoContent,
		},
		{
			name:     "Missing token",
			before:   func() {},
			header:   "",
			body:     event,
			code:     http.StatusUnauthorized,
			response: `{"error":"unauthorized"}`,
		},
		{
			name:     "Wrong scheme",
			before:   func() {},
			header:   "Basic " + token,
			body:     event,
			code:     http.StatusUnauthorized,
			response: `{"error":"unauthorized"}`,
		},
		{
			name: "Unknown or revoked token",
			before: func() {
				integrations.EXPECT().Authenticate(gomock.Any(), token).Return(nil, errors.ErrUnauthorized)
			},
			header:   "Bearer " + token,
			body:     event,
			code:     http.StatusUnauthorized,
			response: `{"error":"unauthorized"}`,
		},
		{
			name:     "Missing token with a malformed body is still unauthorized",
			before:   func() {},
			header:   "",
			body:     `{"ItemType":`,
			code:     http.StatusUnauthorized,
			response: `{"error":"unauthorized"}`,
		},
		{
			name: "Token lookup failing",
			before: func() {
				integrations.EXPECT().Authenticate(gomock.Any(), token).Return(nil, errors.ErrFailedToAuthenticateIntegration)
			},
			header:   "Bearer " + token,
			body:     event,
			code:     http.StatusServiceUnavailable,
			response: `{"error":"failed to authenticate integration"}`,
		},
		{
			name:     "Malformed body",
			before:   authenticated,
			header:   "Bearer " + token,
			body:     `{"ItemType":`,
			code:     http.StatusBadRequest,
			response: `{"error":"unexpected end of JSON input"}`,
		},
		{
			name:     "Oversized body",
			before:   authenticated,
			header:   "Bearer " + token,
			body:     `{"ItemType":"Movie","Padding":"` + strings.Repeat("x", maxJellyfinEventBytes) + `"}`,
			code:     http.StatusBadRequest,
			response: `{"error":"http: request body too large"}`,
		},
		{
			name:     "Null body",
			before:   authenticated,
			header:   "Bearer " + token,
			body:     `null`,
			code:     http.StatusBadRequest,
			response: `{"error":"payload must be a JSON object"}`,
		},
		{
			name:     "Array body",
			before:   authenticated,
			header:   "Bearer " + token,
			body:     `[]`,
			code:     http.StatusBadRequest,
			response: `{"error":"payload must be a JSON object"}`,
		},
		{
			name:     "Scalar body",
			before:   authenticated,
			header:   "Bearer " + token,
			body:     `42`,
			code:     http.StatusBadRequest,
			response: `{"error":"payload must be a JSON object"}`,
		},
		{
			name: "Unresolved event",
			before: func() {
				authenticated()
				handler.EXPECT().Handle(gomock.Any(), link, gomock.Any()).Return(errors.ErrTitleNotFound)
			},
			header:   "Bearer " + token,
			body:     event,
			code:     http.StatusUnprocessableEntity,
			response: `{"error":"title not found on tmdb"}`,
		},
		{
			name: "TMDB unavailable",
			before: func() {
				authenticated()
				handler.EXPECT().Handle(gomock.Any(), link, gomock.Any()).Return(errors.ErrTmdbUnavailable)
			},
			header:   "Bearer " + token,
			body:     event,
			code:     http.StatusBadGateway,
			response: `{"error":"tmdb unavailable"}`,
		},
		{
			name: "Processing failed",
			before: func() {
				authenticated()
				handler.EXPECT().Handle(gomock.Any(), link, gomock.Any()).Return(errors.ErrFailedToProcessWebhook)
			},
			header:   "Bearer " + token,
			body:     event,
			code:     http.StatusServiceUnavailable,
			response: `{"error":"failed to process webhook"}`,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			req := httptest.NewRequest(http.MethodPost, "/api/v1/webhooks/jellyfin", strings.NewReader(tt.body))
			if tt.header != "" {
				req.Header.Set("Authorization", tt.header)
			}

			w := httptest.NewRecorder()

			r := chi.NewRouter()
			r.Post("/api/v1/webhooks/jellyfin", controller.HandleJellyfinWebhook)
			r.ServeHTTP(w, req)

			resp := w.Result()
			defer resp.Body.Close()

			body, err := io.ReadAll(resp.Body)
			require.NoError(t, err)

			assert.Equal(t, tt.code, resp.StatusCode)
			assert.Equal(t, "application/json", resp.Header.Get("Content-Type"))

			if tt.response == "" {
				assert.Empty(t, body)
				return
			}

			var response serializers.ErrorSerializer
			require.NoError(t, json.Unmarshal(body, &response))
			assert.JSONEq(t, tt.response, string(body))
		})
	}
}
