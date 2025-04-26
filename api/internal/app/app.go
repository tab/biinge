package app

import (
	"context"
	"net/http"
	"time"

	"go.uber.org/fx"

	"biinge-api/internal/app/controllers"
	"biinge-api/internal/app/repositories"
	"biinge-api/internal/app/services"
	"biinge-api/internal/config"
	"biinge-api/internal/config/logger"
	"biinge-api/internal/config/middlewares"
	"biinge-api/internal/config/router"
	"biinge-api/internal/config/server"
	"biinge-api/pkg/jwt"
)

var Module = fx.Options(
	logger.Module,

	controllers.Module,
	repositories.Module,
	services.Module,

	middlewares.Module,
	server.Module,
	router.Module,

	jwt.Module,
	fx.Invoke(registerHooks),
)

func registerHooks(
	lifecycle fx.Lifecycle,
	cfg *config.Config,
	server server.Server,
	log *logger.Logger,
) {
	lifecycle.Append(fx.Hook{
		OnStart: func(ctx context.Context) error {
			log.Info().Msgf("Starting server in %s environment at %s", cfg.AppEnv, cfg.AppAddr)

			go func() {
				if err := server.Run(); err != nil && err != http.ErrServerClosed {
					log.Error().Err(err).Msg("Server failed")
				}
			}()

			return nil
		},
		OnStop: func(ctx context.Context) error {
			log.Info().Msg("Shutting down server...")

			shutdownCtx, cancel := context.WithTimeout(ctx, 5*time.Second)
			defer cancel()

			return server.Shutdown(shutdownCtx)
		},
	})
}
