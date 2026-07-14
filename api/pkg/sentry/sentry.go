package sentry

import (
	"time"

	gosentry "github.com/getsentry/sentry-go"

	"biinge-api/internal/config"
	"biinge-api/internal/config/logger"
)

// Sentry reports panics and errors to Sentry for the lifetime of the process
type Sentry interface {
	Flush()
}

type sentryHandler struct{}

// NewSentry initialises the Sentry SDK, or a no-op handler when no DSN is set
func NewSentry(cfg *config.Config, log *logger.Logger) Sentry {
	if cfg.SentryDSN == "" {
		return &sentryHandler{}
	}

	err := gosentry.Init(gosentry.ClientOptions{
		Dsn:              cfg.SentryDSN,
		Environment:      cfg.AppEnv,
		Release:          cfg.AppVersion,
		AttachStacktrace: true,
		TracesSampleRate: 1.0,
		EnableLogs:       true,
	})
	if err != nil {
		log.Error().Err(err).Msg("Failed to initialize Sentry")
	}

	return &sentryHandler{}
}

// Flush waits briefly for buffered events to be delivered before shutdown
func (s *sentryHandler) Flush() {
	gosentry.Flush(2 * time.Second)
}
