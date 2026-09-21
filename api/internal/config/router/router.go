package router

import (
	"net/http"
	"time"

	sentryhttp "github.com/getsentry/sentry-go/http"
	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"
	"github.com/go-chi/httprate"

	"biinge-api/internal/app/controllers"
	"biinge-api/internal/config"
	"biinge-api/internal/config/middlewares"
)

func NewRouter(
	cfg *config.Config,
	authentication middlewares.AuthenticationMiddleware,
	tracer middlewares.TraceMiddleware,
	logger middlewares.LoggerMiddleware,
	health controllers.HealthController,
	sessions controllers.AuthenticationController,
	accounts controllers.AccountsController,
	movies controllers.MoviesController,
	series controllers.SeriesController,
	games controllers.GamesController,
	people controllers.PeopleController,
	catalog controllers.CatalogController,
	upNext controllers.UpNextController,
	integrations controllers.IntegrationsController,
) http.Handler {
	r := chi.NewRouter()

	r.Use(middlewares.RequestID)

	// report panics to Sentry, then repanic so Recoverer still returns a 500
	sentryHandler := sentryhttp.New(sentryhttp.Options{Repanic: true})
	r.Use(sentryHandler.Handle)

	r.Use(middleware.Recoverer)

	// Resolve the client IP from RemoteAddr (not spoofable headers) for rate-limit keys
	r.Use(middleware.ClientIPFromRemoteAddr)

	r.Use(tracer.Trace)
	r.Use(logger.Log)

	// NOTE: CORS - must be before other middlewares that might write headers
	r.Use(
		cors.Handler(cors.Options{
			AllowedOrigins: []string{"http://*", cfg.ClientURL},
			AllowedMethods: []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
			AllowedHeaders: []string{"Accept", "Authorization", "Content-Type", "X-Request-ID", "X-Trace-ID", "sentry-trace", "baggage"},
			ExposedHeaders: []string{"X-Request-ID", "X-Trace-ID"},
			MaxAge:         300,
		}),
	)

	r.Use(middleware.Compress(5))
	r.Use(middleware.Heartbeat("/health"))

	r.Get("/live", health.HandleLiveness)
	r.Get("/ready", health.HandleReadiness)

	r.Route("/api/v1", func(r chi.Router) {
		r.Route("/users", func(r chi.Router) {
			r.Use(httprate.LimitBy(5, time.Minute, keyByIP))

			r.Post("/registrations", sessions.HandleRegistration)
			r.Post("/sessions", sessions.HandleLogin)
			r.Post("/tokens", sessions.HandleRefresh)
		})

		// Media servers authenticate with their own token, checked inside the handler after the IP limit
		r.Route("/webhooks", func(r chi.Router) {
			r.Use(httprate.LimitBy(120, time.Minute, keyByIP))

			r.Post("/jellyfin", integrations.HandleJellyfinWebhook)
		})

		r.Group(func(r chi.Router) {
			r.Use(authentication.Authenticate)
			r.Use(httprate.LimitBy(120, time.Minute, keyByUserID))

			r.Route("/accounts", func(r chi.Router) {
				r.Get("/me", accounts.Me)
				r.Get("/stats", accounts.HandleStats)
				r.Patch("/", accounts.HandleUpdate)

				r.Post("/integrations/jellyfin", integrations.HandleCreateToken)
				r.Delete("/integrations/jellyfin", integrations.HandleRevoke)
			})

			r.Route("/movies", func(r chi.Router) {
				r.Get("/", movies.HandleList)
				r.Get("/{id}", movies.HandleDetails)
				r.Post("/", movies.HandleCreate)
				r.Patch("/{id}", movies.HandleUpdate)
				r.Delete("/{id}", movies.HandleDelete)
			})

			r.Route("/series", func(r chi.Router) {
				r.Get("/", series.HandleList)
				r.Get("/{id}", series.HandleDetails)
				r.Post("/", series.HandleCreate)
				r.Patch("/{id}", series.HandleUpdate)
				r.Delete("/{id}", series.HandleDelete)

				r.Get("/{id}/season/{seasonNumber}", series.HandleSeasonDetails)
				r.Get("/{id}/season/{seasonNumber}/episode/{episodeNumber}", series.HandleEpisodeDetails)

				r.Get("/{id}/progress", series.HandleProgress)
				r.Post("/{id}/watched", series.HandleMarkShowWatched)
				r.Delete("/{id}/watched", series.HandleUnmarkShowWatched)
				r.Post("/{id}/seasons/{seasonId}/watched", series.HandleMarkSeasonWatched)
				r.Delete("/{id}/seasons/{seasonId}/watched", series.HandleUnmarkSeasonWatched)
				r.Post("/{id}/seasons/{seasonId}/episodes/{episodeId}/watched", series.HandleMarkEpisodeWatched)
				r.Delete("/{id}/seasons/{seasonId}/episodes/{episodeId}/watched", series.HandleUnmarkEpisodeWatched)
			})

			r.Route("/games", func(r chi.Router) {
				r.Get("/", games.HandleList)
				r.Get("/{id}", games.HandleDetails)
				r.Post("/", games.HandleCreate)
				r.Patch("/{id}", games.HandleUpdate)
				r.Delete("/{id}", games.HandleDelete)
			})

			r.Route("/people", func(r chi.Router) {
				r.Get("/{id}", people.HandleDetails)
			})

			r.Route("/search", func(r chi.Router) {
				r.Get("/movies", catalog.HandleSearchMovies)
				r.Get("/series", catalog.HandleSearchSeries)
				r.Get("/games", catalog.HandleSearchGames)
				r.Get("/people", catalog.HandleSearchPeople)
			})

			r.Route("/trending", func(r chi.Router) {
				r.Get("/movies", catalog.HandleTrendingMovies)
				r.Get("/series", catalog.HandleTrendingSeries)
				r.Get("/games", catalog.HandleTrendingGames)
				r.Get("/people", catalog.HandleTrendingPeople)
			})

			r.Get("/up-next", upNext.HandleUpNext)
		})
	})

	return r
}

// keyByIP keys the rate limiter on the resolved client IP
func keyByIP(r *http.Request) (string, error) {
	return httprate.CanonicalizeIP(middleware.GetClientIP(r.Context())), nil
}

// keyByUserID throttles authenticated traffic per user, falling back to IP
func keyByUserID(r *http.Request) (string, error) {
	if user, ok := middlewares.CurrentUserFromContext(r.Context()); ok {
		return user.ID.String(), nil
	}

	return keyByIP(r)
}
