package router

import (
	"net/http"

	"github.com/go-chi/chi/v5"
	"github.com/go-chi/chi/v5/middleware"
	"github.com/go-chi/cors"

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
	people controllers.PeopleController,
	catalog controllers.CatalogController,
) http.Handler {
	r := chi.NewRouter()

	r.Use(middleware.RequestID)
	r.Use(middleware.RealIP)
	r.Use(middleware.Recoverer)

	r.Use(tracer.Trace)
	r.Use(logger.Log)

	// NOTE: CORS - must be before other middlewares that might write headers
	r.Use(
		cors.Handler(cors.Options{
			AllowedOrigins: []string{"http://*", cfg.ClientURL},
			AllowedMethods: []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
			AllowedHeaders: []string{"Accept", "Authorization", "Content-Type", "X-Request-ID", "X-Trace-ID"},
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
			r.Post("/registrations", sessions.HandleRegistration)
			r.Post("/sessions", sessions.HandleLogin)
			r.Post("/tokens", sessions.HandleRefresh)
		})

		r.Group(func(r chi.Router) {
			r.Use(authentication.Authenticate)

			r.Route("/accounts", func(r chi.Router) {
				r.Get("/me", accounts.Me)
				r.Get("/stats", accounts.HandleStats)
				r.Patch("/", accounts.HandleUpdate)
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

			r.Route("/people", func(r chi.Router) {
				r.Get("/{id}", people.HandleDetails)
			})

			r.Route("/search", func(r chi.Router) {
				r.Get("/movies", catalog.HandleSearchMovies)
				r.Get("/series", catalog.HandleSearchSeries)
				r.Get("/people", catalog.HandleSearchPeople)
			})

			r.Route("/trending", func(r chi.Router) {
				r.Get("/movies", catalog.HandleTrendingMovies)
				r.Get("/series", catalog.HandleTrendingSeries)
				r.Get("/people", catalog.HandleTrendingPeople)
			})
		})
	})

	return r
}
