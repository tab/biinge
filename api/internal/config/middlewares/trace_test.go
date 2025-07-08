package middlewares

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/assert"
)

func Test_NewTraceMiddleware(t *testing.T) {
	middleware := NewTraceMiddleware()
	assert.NotNil(t, middleware)
}

func Test_TraceMiddleware_Trace(t *testing.T) {
	middleware := NewTraceMiddleware()

	type result struct {
		code   int
		status string
	}

	tests := []struct {
		name     string
		traceId  string
		expected result
	}{
		{
			name:    "Success",
			traceId: "test-trace-id",
			expected: result{
				code:   http.StatusOK,
				status: "200 OK",
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				w.WriteHeader(http.StatusOK)
				_, _ = w.Write([]byte("Success"))
			})

			req, err := http.NewRequest("GET", "/test", nil)
			assert.NoError(t, err)

			ctx := NewContextModifier(req.Context()).
				WithTraceId(tt.traceId).
				Context()
			req = req.WithContext(ctx)

			rr := httptest.NewRecorder()

			middleware.Trace(handler).ServeHTTP(rr, req)

			assert.Equal(t, tt.expected.code, rr.Code)
			assert.Equal(t, tt.expected.status, rr.Result().Status)
		})
	}
}
