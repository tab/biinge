package middlewares

import (
	"context"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"

	"biinge-api/internal/app/models"
)

func Test_CurrentUserFromContext(t *testing.T) {
	tests := []struct {
		name   string
		ctx    context.Context
		user   *models.User
		exists bool
	}{
		{
			name: "Success",
			ctx: context.WithValue(context.Background(), CurrentUser{}, &models.User{
				ID:        uuid.MustParse("10000000-0000-0000-0000-000000000000"),
				Login:     "john.doe",
				Email:     "john.doe@local",
				FirstName: "John",
				LastName:  "Doe",
			}),
			user: &models.User{
				ID:        uuid.MustParse("10000000-0000-0000-0000-000000000000"),
				Login:     "john.doe",
				Email:     "john.doe@local",
				FirstName: "John",
				LastName:  "Doe",
			},
			exists: true,
		},
		{
			name:   "User does not exist",
			ctx:    context.Background(),
			user:   nil,
			exists: false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			user, exists := CurrentUserFromContext(tt.ctx)
			assert.Equal(t, tt.exists, exists)

			if tt.exists {
				assert.Equal(t, tt.user.ID, user.ID)
				assert.Equal(t, tt.user.Login, user.Login)
				assert.Equal(t, tt.user.Email, user.Email)
				assert.Equal(t, tt.user.FirstName, user.FirstName)
				assert.Equal(t, tt.user.LastName, user.LastName)
			} else {
				assert.Nil(t, user)
			}
		})
	}
}

func Test_CurrentTraceIdFromContext(t *testing.T) {
	tests := []struct {
		name    string
		ctx     context.Context
		traceId string
		exists  bool
	}{
		{
			name:    "Success",
			ctx:     context.WithValue(context.Background(), TraceId{}, "9809b3e0-484b-438c-80b2-73cb9af51cd4"),
			traceId: "9809b3e0-484b-438c-80b2-73cb9af51cd4",
			exists:  true,
		},
		{
			name:    "TraceId does not exist",
			ctx:     context.Background(),
			traceId: "",
			exists:  false,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			traceId, exists := CurrentTraceIdFromContext(tt.ctx)
			assert.Equal(t, tt.exists, exists)

			if tt.exists {
				assert.Equal(t, tt.traceId, traceId)
			} else {
				assert.Empty(t, traceId)
			}
		})
	}
}
