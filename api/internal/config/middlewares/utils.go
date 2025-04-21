package middlewares

import (
	"context"
)

func CurrentTraceIdFromContext(ctx context.Context) (string, bool) {
	t, ok := ctx.Value(TraceId{}).(string)
	return t, ok
}
