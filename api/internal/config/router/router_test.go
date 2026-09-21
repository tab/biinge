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

func Test_WebhookRateLimitByIP(t *testing.T) {
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

	passthrough := func(next http.Handler) http.Handler { return next }
	mockAuthenticationMiddleware.EXPECT().Authenticate(gomock.Any()).AnyTimes().DoAndReturn(passthrough)
	mockTraceMiddleware.EXPECT().Trace(gomock.Any()).AnyTimes().DoAndReturn(passthrough)
	mockLoggerMiddleware.EXPECT().Log(gomock.Any()).AnyTimes().DoAndReturn(passthrough)

	// The first 120 events reach the handler, which is where the token is checked; the 121st is
	// throttled before it, so an over-limit IP gets 429 whatever token it carries
	mockIntegrationsController.EXPECT().
		HandleJellyfinWebhook(gomock.Any(), gomock.Any()).
		Times(120).
		DoAndReturn(func(w http.ResponseWriter, _ *http.Request) {
			w.WriteHeader(http.StatusUnauthorized)
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
	)

	for i := 1; i <= 120; i++ {
		req := httptest.NewRequest(http.MethodPost, "/api/v1/webhooks/jellyfin", nil)
		w := httptest.NewRecorder()

		router.ServeHTTP(w, req)

		assert.Equal(t, http.StatusUnauthorized, w.Code, "request %d should reach the handler", i)
	}

	req := httptest.NewRequest(http.MethodPost, "/api/v1/webhooks/jellyfin", nil)
	w := httptest.NewRecorder()

	router.ServeHTTP(w, req)

	assert.Equal(t, http.StatusTooManyRequests, w.Code)
}
