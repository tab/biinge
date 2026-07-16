package middlewares

import (
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/go-chi/chi/v5/middleware"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func Test_RequestID(t *testing.T) {
	tests := []struct {
		name            string
		headerRequestId string
	}{
		{
			name:            "Generates a new UUID when the header is absent",
			headerRequestId: "",
		},
		{
			name:            "Propagates an existing request Id from the header",
			headerRequestId: "test-request-id",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			var contextRequestId string

			handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				contextRequestId = middleware.GetReqID(r.Context())

				w.WriteHeader(http.StatusOK)
				_, _ = w.Write([]byte("Success"))
			})

			req, err := http.NewRequest(http.MethodGet, "/test", nil)
			require.NoError(t, err)

			if tt.headerRequestId != "" {
				req.Header.Set(RequestKey, tt.headerRequestId)
			}

			rr := httptest.NewRecorder()

			RequestID(handler).ServeHTTP(rr, req)

			assert.Equal(t, http.StatusOK, rr.Code)

			if tt.headerRequestId != "" {
				assert.Equal(t, tt.headerRequestId, contextRequestId)
			} else {
				assert.NotEmpty(t, contextRequestId)
				_, parseErr := uuid.Parse(contextRequestId)
				assert.NoError(t, parseErr)
			}
		})
	}
}
