package app

import (
	"context"
	"net/http"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.uber.org/fx"
	"go.uber.org/mock/gomock"

	"biinge-api/internal/config"
	"biinge-api/internal/config/logger"
	"biinge-api/internal/config/server"
	"biinge-api/pkg/sentry"
)

// testLifecycle captures appended hooks so they can be driven directly
type testLifecycle struct {
	hooks []fx.Hook
}

func (l *testLifecycle) Append(h fx.Hook) { l.hooks = append(l.hooks, h) }

func Test_registerHooks(t *testing.T) {
	cfg := &config.Config{AppEnv: "test", AppAddr: "localhost:0", LogLevel: "info"}
	log := logger.NewLogger(cfg)

	tests := []struct {
		name   string
		runErr error
	}{
		{name: "Clean shutdown", runErr: http.ErrServerClosed},
		{name: "Server run error is logged", runErr: assert.AnError},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctrl := gomock.NewController(t)
			defer ctrl.Finish()

			srv := server.NewMockServer(ctrl)
			snt := sentry.NewMockSentry(ctrl)

			runCalled := make(chan struct{})

			srv.EXPECT().Run().DoAndReturn(func() error {
				close(runCalled)

				return tt.runErr
			}).Times(1)
			srv.EXPECT().Shutdown(gomock.Any()).Return(nil).Times(1)
			snt.EXPECT().Flush().Times(1)

			lc := &testLifecycle{}
			registerHooks(lc, cfg, srv, snt, log)
			require.Len(t, lc.hooks, 1)

			hook := lc.hooks[0]

			require.NoError(t, hook.OnStart(context.Background()))
			<-runCalled
			// let the goroutine return from Run and evaluate the error branch
			time.Sleep(20 * time.Millisecond)

			require.NoError(t, hook.OnStop(context.Background()))
		})
	}
}
