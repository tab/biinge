package router

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/assert"
	"go.uber.org/mock/gomock"

	"biinge-api/internal/app/controllers"
	"biinge-api/internal/config"
	"biinge-api/internal/config/middlewares"
)

func Test_HealthCheck(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	cfg := &config.Config{
		AppEnv:  "test",
		AppAddr: "localhost:8080",
	}

	mockTraceMiddleware := middlewares.NewMockTraceMiddleware(ctrl)
	mockLoggerMiddleware := middlewares.NewMockLoggerMiddleware(ctrl)
	mockAuthenticationMiddleware := middlewares.NewMockAuthenticationMiddleware(ctrl)
	mockHealthController := controllers.NewMockHealthController(ctrl)
	mockSessionsController := controllers.NewMockAuthenticationController(ctrl)
	mockAccountsController := controllers.NewMockAccountsController(ctrl)
	mockMoviesController := controllers.NewMockMoviesController(ctrl)
	mockSeriesController := controllers.NewMockSeriesController(ctrl)
	mockGamesController := controllers.NewMockGamesController(ctrl)
	mockPeopleController := controllers.NewMockPeopleController(ctrl)
	mockCatalogController := controllers.NewMockCatalogController(ctrl)
	mockUpNextController := controllers.NewMockUpNextController(ctrl)
	mockIntegrationsController := controllers.NewMockIntegrationsController(ctrl)
	mockSharesController := controllers.NewMockSharesController(ctrl)

	mockAuthenticationMiddleware.EXPECT().
		Authenticate(gomock.Any()).
		AnyTimes().
		DoAndReturn(func(next http.Handler) http.Handler {
			return next
		})
	mockTraceMiddleware.EXPECT().
		Trace(gomock.Any()).
		AnyTimes().
		DoAndReturn(func(next http.Handler) http.Handler {
			return next
		})
	mockLoggerMiddleware.EXPECT().
		Log(gomock.Any()).
		AnyTimes().
		DoAndReturn(func(next http.Handler) http.Handler {
			return next
		})

	router := NewRouter(
		cfg,
		mockAuthenticationMiddleware,
		mockTraceMiddleware,
		mockLoggerMiddleware,
		mockHealthController,
		mockSessionsController,
		mockAccountsController,
		mockMoviesController,
		mockSeriesController,
		mockGamesController,
		mockPeopleController,
		mockCatalogController,
		mockUpNextController,
		mockIntegrationsController,
		mockSharesController,
	)

	req := httptest.NewRequest(http.MethodHead, "/health", nil)
	w := httptest.NewRecorder()

	router.ServeHTTP(w, req)

	resp := w.Result()
	defer resp.Body.Close()

	assert.Equal(t, http.StatusOK, resp.StatusCode)
}

func Test_AuthRateLimitByIP(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	cfg := &config.Config{
		AppEnv:  "test",
		AppAddr: "localhost:8080",
	}

	mockTraceMiddleware := middlewares.NewMockTraceMiddleware(ctrl)
	mockLoggerMiddleware := middlewares.NewMockLoggerMiddleware(ctrl)
	mockAuthenticationMiddleware := middlewares.NewMockAuthenticationMiddleware(ctrl)
	mockHealthController := controllers.NewMockHealthController(ctrl)
	mockSessionsController := controllers.NewMockAuthenticationController(ctrl)
	mockAccountsController := controllers.NewMockAccountsController(ctrl)
	mockMoviesController := controllers.NewMockMoviesController(ctrl)
	mockSeriesController := controllers.NewMockSeriesController(ctrl)
	mockGamesController := controllers.NewMockGamesController(ctrl)
	mockPeopleController := controllers.NewMockPeopleController(ctrl)
	mockCatalogController := controllers.NewMockCatalogController(ctrl)
	mockUpNextController := controllers.NewMockUpNextController(ctrl)
	mockIntegrationsController := controllers.NewMockIntegrationsController(ctrl)
	mockSharesController := controllers.NewMockSharesController(ctrl)

	passthrough := func(next http.Handler) http.Handler { return next }
	mockAuthenticationMiddleware.EXPECT().Authenticate(gomock.Any()).AnyTimes().DoAndReturn(passthrough)
	mockTraceMiddleware.EXPECT().Trace(gomock.Any()).AnyTimes().DoAndReturn(passthrough)
	mockLoggerMiddleware.EXPECT().Log(gomock.Any()).AnyTimes().DoAndReturn(passthrough)

	// The first 5 logins reach the handler; the 6th is throttled before it
	mockSessionsController.EXPECT().
		HandleLogin(gomock.Any(), gomock.Any()).
		Times(5).
		DoAndReturn(func(w http.ResponseWriter, _ *http.Request) {
			w.WriteHeader(http.StatusOK)
		})

	router := NewRouter(
		cfg,
		mockAuthenticationMiddleware,
		mockTraceMiddleware,
		mockLoggerMiddleware,
		mockHealthController,
		mockSessionsController,
		mockAccountsController,
		mockMoviesController,
		mockSeriesController,
		mockGamesController,
		mockPeopleController,
		mockCatalogController,
		mockUpNextController,
		mockIntegrationsController,
		mockSharesController,
	)

	for i := 1; i <= 5; i++ {
		req := httptest.NewRequest(http.MethodPost, "/api/v1/users/sessions", nil)
		w := httptest.NewRecorder()

		router.ServeHTTP(w, req)

		assert.Equal(t, http.StatusOK, w.Code, "request %d should pass", i)
	}

	req := httptest.NewRequest(http.MethodPost, "/api/v1/users/sessions", nil)
	w := httptest.NewRecorder()

	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusTooManyRequests, w.Code)
}

func Test_JellyfinConnectionRoutes(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	cfg := &config.Config{
		AppEnv:  "test",
		AppAddr: "localhost:8080",
	}

	mockTraceMiddleware := middlewares.NewMockTraceMiddleware(ctrl)
	mockLoggerMiddleware := middlewares.NewMockLoggerMiddleware(ctrl)
	mockAuthenticationMiddleware := middlewares.NewMockAuthenticationMiddleware(ctrl)
	mockHealthController := controllers.NewMockHealthController(ctrl)
	mockSessionsController := controllers.NewMockAuthenticationController(ctrl)
	mockAccountsController := controllers.NewMockAccountsController(ctrl)
	mockMoviesController := controllers.NewMockMoviesController(ctrl)
	mockSeriesController := controllers.NewMockSeriesController(ctrl)
	mockGamesController := controllers.NewMockGamesController(ctrl)
	mockPeopleController := controllers.NewMockPeopleController(ctrl)
	mockCatalogController := controllers.NewMockCatalogController(ctrl)
	mockUpNextController := controllers.NewMockUpNextController(ctrl)
	mockIntegrationsController := controllers.NewMockIntegrationsController(ctrl)
	mockSharesController := controllers.NewMockSharesController(ctrl)

	passthrough := func(next http.Handler) http.Handler { return next }
	mockTraceMiddleware.EXPECT().Trace(gomock.Any()).AnyTimes().DoAndReturn(passthrough)
	mockLoggerMiddleware.EXPECT().Log(gomock.Any()).AnyTimes().DoAndReturn(passthrough)

	// Stands in for biinge auth: a request without an Authorization header never reaches the handler
	mockAuthenticationMiddleware.EXPECT().
		Authenticate(gomock.Any()).
		AnyTimes().
		DoAndReturn(func(next http.Handler) http.Handler {
			return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.Header.Get("Authorization") == "" {
					w.WriteHeader(http.StatusUnauthorized)
					return
				}

				next.ServeHTTP(w, r)
			})
		})

	router := NewRouter(
		cfg,
		mockAuthenticationMiddleware,
		mockTraceMiddleware,
		mockLoggerMiddleware,
		mockHealthController,
		mockSessionsController,
		mockAccountsController,
		mockMoviesController,
		mockSeriesController,
		mockGamesController,
		mockPeopleController,
		mockCatalogController,
		mockUpNextController,
		mockIntegrationsController,
		mockSharesController,
	)

	reached := func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusTeapot)
	}

	tests := []struct {
		name   string
		before func()
		method string
		header string
		code   int
	}{
		{
			name: "Connect",
			before: func() {
				mockIntegrationsController.EXPECT().HandleConnect(gomock.Any(), gomock.Any()).DoAndReturn(reached)
			},
			method: http.MethodPut,
			header: "Bearer access",
			code:   http.StatusTeapot,
		},
		{
			name: "Status",
			before: func() {
				mockIntegrationsController.EXPECT().HandleStatus(gomock.Any(), gomock.Any()).DoAndReturn(reached)
			},
			method: http.MethodGet,
			header: "Bearer access",
			code:   http.StatusTeapot,
		},
		{
			name: "Disconnect",
			before: func() {
				mockIntegrationsController.EXPECT().HandleDisconnect(gomock.Any(), gomock.Any()).DoAndReturn(reached)
			},
			method: http.MethodDelete,
			header: "Bearer access",
			code:   http.StatusTeapot,
		},
		{
			name:   "Connect without biinge auth",
			before: func() {},
			method: http.MethodPut,
			code:   http.StatusUnauthorized,
		},
		{
			name:   "Status without biinge auth",
			before: func() {},
			method: http.MethodGet,
			code:   http.StatusUnauthorized,
		},
		{
			name:   "Disconnect without biinge auth",
			before: func() {},
			method: http.MethodDelete,
			code:   http.StatusUnauthorized,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			req := httptest.NewRequest(tt.method, "/api/v1/accounts/integrations/jellyfin/connection", nil)
			if tt.header != "" {
				req.Header.Set("Authorization", tt.header)
			}

			w := httptest.NewRecorder()

			router.ServeHTTP(w, req)

			assert.Equal(t, tt.code, w.Code)
		})
	}
}

func Test_ShareRoutes(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	cfg := &config.Config{
		AppEnv:  "test",
		AppAddr: "localhost:8080",
	}

	mockTraceMiddleware := middlewares.NewMockTraceMiddleware(ctrl)
	mockLoggerMiddleware := middlewares.NewMockLoggerMiddleware(ctrl)
	mockAuthenticationMiddleware := middlewares.NewMockAuthenticationMiddleware(ctrl)
	mockHealthController := controllers.NewMockHealthController(ctrl)
	mockSessionsController := controllers.NewMockAuthenticationController(ctrl)
	mockAccountsController := controllers.NewMockAccountsController(ctrl)
	mockMoviesController := controllers.NewMockMoviesController(ctrl)
	mockSeriesController := controllers.NewMockSeriesController(ctrl)
	mockGamesController := controllers.NewMockGamesController(ctrl)
	mockPeopleController := controllers.NewMockPeopleController(ctrl)
	mockCatalogController := controllers.NewMockCatalogController(ctrl)
	mockUpNextController := controllers.NewMockUpNextController(ctrl)
	mockIntegrationsController := controllers.NewMockIntegrationsController(ctrl)
	mockSharesController := controllers.NewMockSharesController(ctrl)

	passthrough := func(next http.Handler) http.Handler { return next }
	mockTraceMiddleware.EXPECT().Trace(gomock.Any()).AnyTimes().DoAndReturn(passthrough)
	mockLoggerMiddleware.EXPECT().Log(gomock.Any()).AnyTimes().DoAndReturn(passthrough)

	// Stands in for biinge auth: a request without an Authorization header never reaches the handler
	mockAuthenticationMiddleware.EXPECT().
		Authenticate(gomock.Any()).
		AnyTimes().
		DoAndReturn(func(next http.Handler) http.Handler {
			return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if r.Header.Get("Authorization") == "" {
					w.WriteHeader(http.StatusUnauthorized)
					return
				}

				next.ServeHTTP(w, r)
			})
		})

	router := NewRouter(
		cfg,
		mockAuthenticationMiddleware,
		mockTraceMiddleware,
		mockLoggerMiddleware,
		mockHealthController,
		mockSessionsController,
		mockAccountsController,
		mockMoviesController,
		mockSeriesController,
		mockGamesController,
		mockPeopleController,
		mockCatalogController,
		mockUpNextController,
		mockIntegrationsController,
		mockSharesController,
	)

	reached := func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusTeapot)
	}

	tests := []struct {
		name   string
		before func()
		method string
		path   string
		header string
		code   int
	}{
		{
			name: "Share page without biinge auth",
			before: func() {
				mockSharesController.EXPECT().HandleShow(gomock.Any(), gomock.Any()).DoAndReturn(reached)
			},
			method: http.MethodGet,
			path:   "/s/6f1c3c1e-8a2b-4d4e-9f3a-1b2c3d4e5f60",
			code:   http.StatusTeapot,
		},
		{
			name:   "Share id at the root",
			before: func() {},
			method: http.MethodGet,
			path:   "/6f1c3c1e-8a2b-4d4e-9f3a-1b2c3d4e5f60",
			code:   http.StatusNotFound,
		},
		{
			name: "Create",
			before: func() {
				mockSharesController.EXPECT().HandleCreate(gomock.Any(), gomock.Any()).DoAndReturn(reached)
			},
			method: http.MethodPost,
			path:   "/api/v1/shares",
			header: "Bearer access",
			code:   http.StatusTeapot,
		},
		{
			name:   "Create without biinge auth",
			before: func() {},
			method: http.MethodPost,
			path:   "/api/v1/shares",
			code:   http.StatusUnauthorized,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			req := httptest.NewRequest(tt.method, tt.path, nil)
			if tt.header != "" {
				req.Header.Set("Authorization", tt.header)
			}

			w := httptest.NewRecorder()

			router.ServeHTTP(w, req)

			assert.Equal(t, tt.code, w.Code)
		})
	}
}

func Test_SharePageRateLimitByIP(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	cfg := &config.Config{
		AppEnv:  "test",
		AppAddr: "localhost:8080",
	}

	mockTraceMiddleware := middlewares.NewMockTraceMiddleware(ctrl)
	mockLoggerMiddleware := middlewares.NewMockLoggerMiddleware(ctrl)
	mockAuthenticationMiddleware := middlewares.NewMockAuthenticationMiddleware(ctrl)
	mockHealthController := controllers.NewMockHealthController(ctrl)
	mockSessionsController := controllers.NewMockAuthenticationController(ctrl)
	mockAccountsController := controllers.NewMockAccountsController(ctrl)
	mockMoviesController := controllers.NewMockMoviesController(ctrl)
	mockSeriesController := controllers.NewMockSeriesController(ctrl)
	mockGamesController := controllers.NewMockGamesController(ctrl)
	mockPeopleController := controllers.NewMockPeopleController(ctrl)
	mockCatalogController := controllers.NewMockCatalogController(ctrl)
	mockUpNextController := controllers.NewMockUpNextController(ctrl)
	mockIntegrationsController := controllers.NewMockIntegrationsController(ctrl)
	mockSharesController := controllers.NewMockSharesController(ctrl)

	passthrough := func(next http.Handler) http.Handler { return next }
	mockAuthenticationMiddleware.EXPECT().Authenticate(gomock.Any()).AnyTimes().DoAndReturn(passthrough)
	mockTraceMiddleware.EXPECT().Trace(gomock.Any()).AnyTimes().DoAndReturn(passthrough)
	mockLoggerMiddleware.EXPECT().Log(gomock.Any()).AnyTimes().DoAndReturn(passthrough)

	// The first 60 pages from one IP reach the handler, then the one from another IP
	mockSharesController.EXPECT().
		HandleShow(gomock.Any(), gomock.Any()).
		Times(61).
		DoAndReturn(func(w http.ResponseWriter, _ *http.Request) {
			w.WriteHeader(http.StatusOK)
		})

	router := NewRouter(
		cfg,
		mockAuthenticationMiddleware,
		mockTraceMiddleware,
		mockLoggerMiddleware,
		mockHealthController,
		mockSessionsController,
		mockAccountsController,
		mockMoviesController,
		mockSeriesController,
		mockGamesController,
		mockPeopleController,
		mockCatalogController,
		mockUpNextController,
		mockIntegrationsController,
		mockSharesController,
	)

	for i := 1; i <= 60; i++ {
		req := httptest.NewRequest(http.MethodGet, "/s/6f1c3c1e-8a2b-4d4e-9f3a-1b2c3d4e5f60", nil)
		w := httptest.NewRecorder()

		router.ServeHTTP(w, req)

		assert.Equal(t, http.StatusOK, w.Code, "request %d should pass", i)
	}

	req := httptest.NewRequest(http.MethodGet, "/s/6f1c3c1e-8a2b-4d4e-9f3a-1b2c3d4e5f60", nil)
	w := httptest.NewRecorder()

	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusTooManyRequests, w.Code)

	// the page budget is its own, so the same IP still reaches the create route and liveness
	reached := func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusTeapot)
	}
	mockSharesController.EXPECT().HandleCreate(gomock.Any(), gomock.Any()).DoAndReturn(reached)
	mockHealthController.EXPECT().HandleLiveness(gomock.Any(), gomock.Any()).DoAndReturn(reached)

	req = httptest.NewRequest(http.MethodPost, "/api/v1/shares", nil)
	w = httptest.NewRecorder()

	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusTeapot, w.Code)

	req = httptest.NewRequest(http.MethodGet, "/live", nil)
	w = httptest.NewRecorder()

	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusTeapot, w.Code)

	// another IP has its own budget
	req = httptest.NewRequest(http.MethodGet, "/s/6f1c3c1e-8a2b-4d4e-9f3a-1b2c3d4e5f60", nil)
	req.RemoteAddr = "198.51.100.7:1234"
	w = httptest.NewRecorder()

	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusOK, w.Code)
}
