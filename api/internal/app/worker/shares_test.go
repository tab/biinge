package worker

import (
	"context"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.uber.org/fx/fxtest"
	"go.uber.org/mock/gomock"

	"biinge-api/internal/app/repositories"
	"biinge-api/internal/config"
	"biinge-api/internal/config/logger"
)

func Test_ShareWorker_Cleanup(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	cfg := &config.Config{AppEnv: config.TestEnv, LogLevel: "info"}
	repo := repositories.NewMockShareRepository(ctrl)
	w := &ShareWorker{
		repo: repo,
		log:  logger.NewLogger(cfg).WithComponent("ShareWorker"),
	}

	tests := []struct {
		name   string
		before func()
	}{
		{
			name: "Deleted",
			before: func() {
				repo.EXPECT().DeleteExpired(ctx).Return(int64(3), nil)
			},
		},
		{
			name: "Nothing expired",
			before: func() {
				repo.EXPECT().DeleteExpired(ctx).Return(int64(0), nil)
			},
		},
		{
			name: "Error",
			before: func() {
				repo.EXPECT().DeleteExpired(ctx).Return(int64(0), assert.AnError)
			},
		},
		{
			name: "Panic",
			before: func() {
				repo.EXPECT().DeleteExpired(ctx).DoAndReturn(func(context.Context) (int64, error) {
					panic("boom")
				})
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			assert.NotPanics(t, func() { w.cleanup(ctx) })
		})
	}
}

func Test_ShareWorker_Run(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	cfg := &config.Config{AppEnv: config.TestEnv, LogLevel: "info"}
	repo := repositories.NewMockShareRepository(ctrl)
	w := &ShareWorker{
		repo:     repo,
		log:      logger.NewLogger(cfg).WithComponent("ShareWorker"),
		interval: time.Millisecond,
		done:     make(chan struct{}),
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	gomock.InOrder(
		repo.EXPECT().DeleteExpired(gomock.Any()).Return(int64(0), assert.AnError),
		repo.EXPECT().DeleteExpired(gomock.Any()).Return(int64(0), assert.AnError),
		repo.EXPECT().DeleteExpired(gomock.Any()).DoAndReturn(func(context.Context) (int64, error) {
			cancel()

			return 1, nil
		}),
		// a tick that lands with the cancel can still win the select once
		repo.EXPECT().DeleteExpired(gomock.Any()).Return(int64(0), nil).AnyTimes(),
	)

	go w.run(ctx)

	select {
	case <-w.done:
	case <-time.After(5 * time.Second):
		t.Fatal("share worker did not stop")
	}
}

func Test_ShareWorker_Run_CleansUpAtStart(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	cfg := &config.Config{AppEnv: config.TestEnv, LogLevel: "info"}
	repo := repositories.NewMockShareRepository(ctrl)
	w := &ShareWorker{
		repo:     repo,
		log:      logger.NewLogger(cfg).WithComponent("ShareWorker"),
		interval: time.Hour,
		done:     make(chan struct{}),
	}

	ctx, cancel := context.WithCancel(context.Background())
	defer cancel()

	repo.EXPECT().DeleteExpired(gomock.Any()).DoAndReturn(func(context.Context) (int64, error) {
		cancel()

		return 0, nil
	})

	go w.run(ctx)

	select {
	case <-w.done:
	case <-time.After(time.Second):
		t.Fatal("share worker did not clean up at start")
	}
}

func Test_ShareWorker_Lifecycle(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	cfg := &config.Config{AppEnv: config.TestEnv, LogLevel: "info"}
	repo := repositories.NewMockShareRepository(ctrl)

	tests := []struct {
		name     string
		deadline bool
	}{
		{
			name: "Stop waits for the cleanup to finish",
		},
		{
			name:     "Stop gives up on a cleanup at the shutdown deadline",
			deadline: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			started := make(chan struct{})
			release := make(chan struct{})

			// the cleanup at start blocks until released, so the stop below races nothing
			repo.EXPECT().DeleteExpired(gomock.Any()).DoAndReturn(func(context.Context) (int64, error) {
				close(started)
				<-release

				return 0, nil
			})

			lifecycle := fxtest.NewLifecycle(t)
			w := NewShareWorker(lifecycle, repo, logger.NewLogger(cfg))

			assert.Equal(t, shareCleanupInterval, w.interval)

			lifecycle.RequireStart()
			<-started

			if !tt.deadline {
				close(release)
				lifecycle.RequireStop()

				select {
				case <-w.done:
				default:
					assert.Fail(t, "the worker did not stop")
				}

				return
			}

			ctx, cancel := context.WithTimeout(context.Background(), 50*time.Millisecond)
			defer cancel()

			require.NoError(t, lifecycle.Stop(ctx))

			select {
			case <-w.done:
				assert.Fail(t, "the worker stopped before its cleanup returned")
			default:
			}

			close(release)

			select {
			case <-w.done:
			case <-time.After(5 * time.Second):
				t.Fatal("the worker did not stop after its cleanup returned")
			}
		})
	}
}
