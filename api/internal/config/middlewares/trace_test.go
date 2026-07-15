package middlewares

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
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
		name          string
		headerTraceId string
		expected      result
	}{
		{
			name:          "Generates a new trace Id when the header is absent",
			headerTraceId: "",
			expected: result{
				code:   http.StatusOK,
				status: "200 OK",
			},
		},
		{
			name:          "Propagates an existing trace Id from the header",
			headerTraceId: "test-trace-id",
			expected: result{
				code:   http.StatusOK,
				status: "200 OK",
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var (
				contextTraceId        string
				responseHeaderTraceId string
			)

			handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				contextTraceId, _ = CurrentTraceIdFromContext(r.Context())
				responseHeaderTraceId = r.Header.Get(TraceKey)

				w.WriteHeader(http.StatusOK)
				_, _ = w.Write([]byte("Success"))
			})

			req, err := http.NewRequest(http.MethodGet, "/test", nil)
			require.NoError(t, err)

			if tt.headerTraceId != "" {
				req.Header.Set(TraceKey, tt.headerTraceId)
			}

			rr := httptest.NewRecorder()

			middleware.Trace(handler).ServeHTTP(rr, req)

			assert.Equal(t, tt.expected.code, rr.Code)
			assert.Equal(t, tt.expected.status, rr.Result().Status)

			if tt.headerTraceId != "" {
				assert.Equal(t, tt.headerTraceId, contextTraceId)
				assert.Equal(t, tt.headerTraceId, responseHeaderTraceId)
			} else {
				assert.NotEmpty(t, contextTraceId)
				assert.Equal(t, contextTraceId, responseHeaderTraceId)
			}
		})
	}
}
