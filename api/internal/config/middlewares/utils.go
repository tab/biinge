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

// UserHolder carries the authenticated user id up to the logger, which runs above auth
type UserHolder struct {
	UserId string
}

type userHolderKey struct{}

// WithUserHolder seeds an empty holder that the auth middleware fills once it resolves the user
func WithUserHolder(ctx context.Context) (context.Context, *UserHolder) {
	holder := &UserHolder{}
	return context.WithValue(ctx, userHolderKey{}, holder), holder
}

// SetCurrentUserId records the user id in the holder seeded upstream, if present
func SetCurrentUserId(ctx context.Context, userId string) {
	if holder, ok := ctx.Value(userHolderKey{}).(*UserHolder); ok {
		holder.UserId = userId
	}
}
