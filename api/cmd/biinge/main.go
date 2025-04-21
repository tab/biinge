package main

import (
	"os"

	"go.uber.org/fx"
	"go.uber.org/fx/fxevent"

	"biinge-api/internal/app"
	"biinge-api/internal/config"
	"biinge-api/internal/config/logger"
)

func main() {
	cfg := config.LoadConfig()

	fx.New(
		fx.WithLogger(
			func(log *logger.Logger) fxevent.Logger {
				if cfg.LogLevel == config.DebugLevel {
					return &fxevent.ConsoleLogger{W: os.Stdout}
				}
				return fxevent.NopLogger
			},
		),
		fx.Supply(cfg),
		app.Module,
	).Run()
}
