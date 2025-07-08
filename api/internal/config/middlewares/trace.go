package middlewares

import (
	"net/http"

	"github.com/google/uuid"
)

const (
	TraceKey = "X-Trace-ID"
)

type TraceMiddleware interface {
	Trace(next http.Handler) http.Handler
}

type traceMiddleware struct{}

func NewTraceMiddleware() TraceMiddleware {
	return &traceMiddleware{}
}

func (m *traceMiddleware) Trace(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		traceId := r.Header.Get(TraceKey)

		if traceId == "" {
			traceId = uuid.NewString()
			r.Header.Set(TraceKey, traceId)
		}

		ctx := NewContextModifier(r.Context()).
			WithTraceId(traceId).
			Context()

		next.ServeHTTP(w, r.WithContext(ctx))
	})
}
