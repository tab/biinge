package middlewares

import (
	"context"

	"biinge-api/internal/app/models"
)

const (
	Authorization = "Authorization"
	bearerScheme  = "Bearer "
)

func CurrentUserFromContext(ctx context.Context) (*models.User, bool) {
	u := ctx.Value(CurrentUser{})
	if u == nil {
		return nil, false
	}

	user, ok := u.(*models.User)
	return user, ok
}

func CurrentTraceIdFromContext(ctx context.Context) (string, bool) {
	t, ok := ctx.Value(TraceId{}).(string)
	return t, ok
}
