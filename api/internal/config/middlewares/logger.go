package middlewares

import (
	"net/http"
	"time"

	"github.com/go-chi/chi/v5/middleware"

	"biinge-api/internal/config/logger"
)

type LoggerMiddleware interface {
	Log(next http.Handler) http.Handler
}

type loggerMiddleware struct {
	log *logger.Logger
}

func NewLoggerMiddleware(log *logger.Logger) LoggerMiddleware {
	return &loggerMiddleware{
		log: log,
	}
}

func (m *loggerMiddleware) Log(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		startTime := time.Now()

		traceId, _ := CurrentTraceIdFromContext(r.Context())
		requestId := middleware.GetReqID(r.Context())

		// seed a holder the auth middleware fills in, so we can log the user id
		ctx, userHolder := WithUserHolder(r.Context())
		r = r.WithContext(ctx)

		reqLogger := m.log.
			WithComponent("http").
			WithRequestId(requestId).
			WithTraceId(traceId)

		ww := middleware.NewWrapResponseWriter(w, r.ProtoMajor)
		next.ServeHTTP(ww, r)

		scheme := "http"
		if r.TLS != nil {
			scheme = "https"
		}

		status := ww.Status()
		size := ww.BytesWritten()
		duration := time.Since(startTime)

		// Level by outcome so failures surface above the info noise: 5xx errors, 4xx warnings
		event := reqLogger.Info()

		switch {
		case status >= http.StatusInternalServerError:
			event = reqLogger.Error()
		case status >= http.StatusBadRequest:
			event = reqLogger.Warn()
		}

		event.
			Str("method", r.Method).
			Str("uri", r.RequestURI).
			Str("proto", r.Proto).
			Str("scheme", scheme).
			Str("remote_addr", r.RemoteAddr).
			Str("user_agent", r.UserAgent()).
			Int("status", status).
			Int("size", size).
			Dur("duration", duration)

		if userHolder.UserId != "" {
			event.Str("user_id", userHolder.UserId)
		}

		event.Msgf("%s %s - %d %dB in %s", r.Method, r.RequestURI, status, size, duration)
	})
}
