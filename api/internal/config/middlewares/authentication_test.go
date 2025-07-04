package middlewares

import (
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"go.uber.org/mock/gomock"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/models"
	"biinge-api/internal/app/serializers"
	"biinge-api/internal/app/services"
	"biinge-api/internal/config"
	"biinge-api/internal/config/logger"
	"biinge-api/pkg/jwt"
)

func Test_AuthMiddleware_Authenticate(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	cfg := &config.Config{
		AppEnv:   "test",
		AppAddr:  "localhost:8080",
		LogLevel: "info",
	}

	jwtService := jwt.NewMockJwt(ctrl)
	users := services.NewMockUsers(ctrl)
	log := logger.NewLogger(cfg)
	middleware := NewAuthenticationMiddleware(jwtService, users, log)

	id, err := uuid.NewRandom()
	assert.NoError(t, err)

	type result struct {
		status string
		code   int
	}

	tests := []struct {
		name     string
		before   func()
		header   string
		expected result
		error    error
	}{
		{
			name: "Success",
			before: func() {
				jwtService.EXPECT().Decode("valid-token").Return(&jwt.Payload{ID: id.String()}, nil)
				users.EXPECT().FindById(gomock.Any(), id).Return(&models.User{
					ID: id,
				}, nil)
			},
			header: "Bearer valid-token",
			expected: result{
				status: "200 OK",
				code:   http.StatusOK,
			},
			error: nil,
		},
		{
			name:   "Invalid header",
			before: func() {},
			header: "Bearer",
			expected: result{
				status: "401 Unauthorized",
				code:   http.StatusUnauthorized,
			},
			error: nil,
		},
		{
			name: "User not found",
			before: func() {
				jwtService.EXPECT().Decode("valid-token").Return(&jwt.Payload{ID: id.String()}, nil)
				users.EXPECT().FindById(gomock.Any(), id).Return(nil, errors.ErrUserNotFound)
			},
			header: "Bearer valid-token",
			expected: result{
				status: "401 Unauthorized",
				code:   http.StatusUnauthorized,
			},
		},
		{
			name: "Unauthorized",
			before: func() {
				jwtService.EXPECT().Decode("invalid-token").Return(nil, errors.ErrInvalidToken)
			},
			header: "Bearer invalid-token",
			expected: result{
				status: "401 Unauthorized",
				code:   http.StatusUnauthorized,
			},
			error: errors.ErrInvalidToken,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			handler := http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
				user, ok := CurrentUserFromContext(r.Context())
				if !ok {
					w.WriteHeader(http.StatusUnauthorized)
					return
				}
				_ = json.NewEncoder(w).Encode(serializers.UserSerializer{ID: user.ID})
			})

			req, _ := http.NewRequest("GET", "/", nil)
			req.Header.Set("Authorization", tt.header)
			rw := httptest.NewRecorder()

			middleware.Authenticate(handler).ServeHTTP(rw, req)

			res := rw.Result()
			defer res.Body.Close()

			if tt.error != nil {
				assert.Error(t, tt.error)
			} else {
				assert.Equal(t, tt.expected.code, res.StatusCode)
				assert.Equal(t, tt.expected.status, res.Status)
			}
		})
	}
}
