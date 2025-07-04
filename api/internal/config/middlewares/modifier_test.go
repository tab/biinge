package middlewares

import (
	"context"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"

	"biinge-api/internal/app/models"
)

func Test_NewContextModifier(t *testing.T) {
	ctx := context.Background()
	ctxModifier := NewContextModifier(ctx)

	assert.NotNil(t, ctxModifier)
	assert.Equal(t, ctx, ctxModifier.Context())
}

func Test_Modifier_WithTraceId(t *testing.T) {
	ctx := context.Background()

	tests := []struct {
		name    string
		traceId string
	}{
		{
			name:    "Valid trace ID",
			traceId: "valid-trace-id",
		},
		{
			name:    "Empty trace ID",
			traceId: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctxModifier := NewContextModifier(ctx).WithTraceId(tt.traceId)

			traceId, ok := ctxModifier.Context().Value(TraceId{}).(string)
			assert.True(t, ok)
			assert.Equal(t, tt.traceId, traceId)
		})
	}
}

func Test_Modifier_WithCurrentUser(t *testing.T) {
	ctx := context.Background()

	tests := []struct {
		name string
		user *models.User
	}{
		{
			name: "Success",
			user: &models.User{
				ID:        uuid.New(),
				Login:     "john.doe",
				Email:     "john.doe@local",
				FirstName: "John",
				LastName:  "Doe",
			},
		},
		{
			name: "Empty user",
			user: &models.User{},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			ctxModifier := NewContextModifier(ctx).WithCurrentUser(tt.user)

			user, ok := ctxModifier.Context().Value(CurrentUser{}).(*models.User)
			assert.True(t, ok)
			assert.Equal(t, tt.user.ID, user.ID)
			assert.Equal(t, tt.user.Login, user.Login)
			assert.Equal(t, tt.user.Email, user.Email)
			assert.Equal(t, tt.user.FirstName, user.FirstName)
			assert.Equal(t, tt.user.LastName, user.LastName)
		})
	}
}
