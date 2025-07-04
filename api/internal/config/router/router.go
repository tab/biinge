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
	logger middlewares.LoggerMiddleware,
	health controllers.HealthController,
	sessions controllers.AuthenticationController,
	accounts controllers.AccountsController,
	movies controllers.MoviesController,
	people controllers.PeopleController,
) http.Handler {
	r := chi.NewRouter()

	r.Use(middleware.RequestID)
	r.Use(logger.Log)
	r.Use(middleware.Compress(5))
	r.Use(middleware.Heartbeat("/health"))
	r.Use(
		cors.Handler(cors.Options{
			AllowedOrigins: []string{"http://*", cfg.ClientURL},
			AllowedMethods: []string{"GET", "POST", "PUT", "PATCH", "DELETE", "OPTIONS"},
			AllowedHeaders: []string{"Accept", "Authorization", "Content-Type", "X-Request-ID", "X-Trace-ID"},
			MaxAge:         300,
		}),
	)

	r.Get("/live", health.HandleLiveness)
	r.Get("/ready", health.HandleReadiness)

	r.Route("/api/v1", func(r chi.Router) {
		r.Route("/users", func(r chi.Router) {
			r.Post("/registrations", sessions.HandleRegistration)
			r.Post("/sessions", sessions.HandleLogin)
		})

		r.Group(func(r chi.Router) {
			r.Use(authentication.Authenticate)

			r.Route("/accounts", func(r chi.Router) {
				r.Get("/me", accounts.Me)
				r.Patch("/", accounts.HandleUpdate)
			})

			r.Route("/movies", func(r chi.Router) {
				r.Get("/", movies.HandleList)
				r.Get("/{id}", movies.HandleDetails)
				r.Post("/", movies.HandleCreate)
				r.Patch("/{id}", movies.HandleUpdate)
				r.Delete("/{id}", movies.HandleDelete)
			})

			r.Route("/people", func(r chi.Router) {
				r.Get("/{id}", people.HandleDetails)
			})
		})
	})

	return r
}
