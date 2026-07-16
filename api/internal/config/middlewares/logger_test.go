package middlewares

import (
	"crypto/tls"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"

	"biinge-api/internal/config"
	"biinge-api/internal/config/logger"
)

func Test_NewLoggerMiddleware(t *testing.T) {
	cfg := &config.Config{
		AppEnv:   "test",
		AppAddr:  "localhost:8080",
		LogLevel: "info",
	}
	log := logger.NewLogger(cfg)

	middleware := NewLoggerMiddleware(log)
	assert.NotNil(t, middleware)
}

func Test_LoggerMiddleware_Logger(t *testing.T) {
	cfg := &config.Config{
		AppEnv:   "test",
		AppAddr:  "localhost:8080",
		LogLevel: "info",
	}
	log := logger.NewLogger(cfg)
	middleware := NewLoggerMiddleware(log)

	type result struct {
		code   int
		status string
	}

	tests := []struct {
		name     string
		traceId  string
		userId   string
		useTLS   bool
		status   int
		expected result
	}{
		{
			name:    "Success",
			traceId: "test-trace-id",
			status:  http.StatusOK,
			expected: result{
				code:   http.StatusOK,
				status: "200 OK",
			},
		},
		{
			name:    "Success with authenticated user",
			traceId: "test-trace-id",
			userId:  "user-123",
			status:  http.StatusOK,
			expected: result{
				code:   http.StatusOK,
				status: "200 OK",
			},
		},
		{
			name:    "Success over TLS",
			traceId: "test-trace-id",
			useTLS:  true,
			status:  http.StatusOK,
			expected: result{
				code:   http.StatusOK,
				status: "200 OK",
			},
		},
		{
			name:    "Client error logs at warn",
			traceId: "test-trace-id",
			status:  http.StatusUnprocessableEntity,
			expected: result{
				code:   http.StatusUnprocessableEntity,
				status: "422 Unprocessable Entity",
			},
		},
		{
			name:    "Server error logs at error",
			traceId: "test-trace-id",
			status:  http.StatusInternalServerError,
			expected: result{
				code:   http.StatusInternalServerError,
				status: "500 Internal Server Error",
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				if tt.userId != "" {
					SetCurrentUserId(r.Context(), tt.userId)
				}

				w.WriteHeader(tt.status)
				_, _ = w.Write([]byte("body"))
			})

			req, err := http.NewRequest(http.MethodGet, "/test", nil)
			require.NoError(t, err)

			if tt.useTLS {
				req.TLS = &tls.ConnectionState{}
			}

			ctx := NewContextModifier(req.Context()).
				WithTraceId(tt.traceId).
				Context()
			req = req.WithContext(ctx)

			rr := httptest.NewRecorder()

			middleware.Log(handler).ServeHTTP(rr, req)

			assert.Equal(t, tt.expected.code, rr.Code)
			assert.Equal(t, tt.expected.status, rr.Result().Status)
		})
	}
}
