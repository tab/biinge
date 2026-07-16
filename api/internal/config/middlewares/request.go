package middlewares

import (
	"context"
	"net/http"

	"github.com/go-chi/chi/v5/middleware"
	"github.com/google/uuid"
)

const (
	RequestKey = "X-Request-ID"
)

// RequestID assigns each request a UUID (honoring an inbound X-Request-ID) under chi's request-id key
func RequestID(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		requestId := r.Header.Get(RequestKey)

		if requestId == "" {
			requestId = uuid.NewString()
			r.Header.Set(RequestKey, requestId)
		}

		ctx := context.WithValue(r.Context(), middleware.RequestIDKey, requestId)

		next.ServeHTTP(w, r.WithContext(ctx))
	})
}
