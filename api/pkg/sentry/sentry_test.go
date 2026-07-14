package sentry

import (
	"testing"

	gosentry "github.com/getsentry/sentry-go"
	"github.com/stretchr/testify/assert"

	"biinge-api/internal/config"
	"biinge-api/internal/config/logger"
)

func Test_NewSentry_EmptyDSN(t *testing.T) {
	cfg := &config.Config{}
	s := NewSentry(cfg, logger.NewLogger(cfg))

	assert.NotNil(t, s)
	s.Flush()
}

func Test_NewSentry_InvalidDSN(t *testing.T) {
	cfg := &config.Config{
		SentryDSN: "invalid-dsn",
		AppEnv:    "test",
	}
	s := NewSentry(cfg, logger.NewLogger(cfg))

	assert.NotNil(t, s)
	s.Flush()
}

func Test_NewSentry_ValidDSN(t *testing.T) {
	cfg := &config.Config{
		SentryDSN:  "https://key@sentry.io/1",
		AppEnv:     "test",
		AppVersion: "0.1.0",
	}
	s := NewSentry(cfg, logger.NewLogger(cfg))

	assert.NotNil(t, s)

	client := gosentry.CurrentHub().Client()
	assert.NotNil(t, client)

	options := client.Options()
	assert.Equal(t, "https://key@sentry.io/1", options.Dsn)
	assert.Equal(t, "test", options.Environment)
	assert.Equal(t, "0.1.0", options.Release)
	assert.InEpsilon(t, 1.0, options.TracesSampleRate, 0.0001)
	assert.True(t, options.EnableLogs)

	s.Flush()
}
