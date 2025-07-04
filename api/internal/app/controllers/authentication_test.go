package controllers

import (
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/go-chi/chi/v5"
	"github.com/stretchr/testify/assert"
	"go.uber.org/mock/gomock"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/serializers"
	"biinge-api/internal/app/services"
	"biinge-api/internal/config"
	"biinge-api/internal/config/logger"
	"biinge-api/pkg/jwt"
)

func Test_AuthenticationController_Registration(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	cfg := &config.Config{
		AppEnv:   "test",
		AppAddr:  "localhost:8080",
		LogLevel: "info",
	}

	authentication := services.NewMockAuthentication(ctrl)
	log := logger.NewLogger(cfg)
	controller := NewAuthenticationController(authentication, log)

	type result struct {
		response serializers.TokenSerializer
		error    serializers.ErrorSerializer
		status   string
		code     int
	}

	tests := []struct {
		name     string
		before   func()
		body     io.Reader
		expected result
		error    bool
	}{
		{
			name: "Success",
			before: func() {
				authentication.EXPECT().Registration(gomock.Any(), &serializers.RegistrationRequestSerializer{
					Login:      "john.doe",
					Email:      "john.doe@local",
					FirstName:  "John",
					LastName:   "Doe",
					Password:   "password",
					Appearance: "dark",
				}).Return(&serializers.TokenSerializer{
					AccessToken:  "jwt-access-token",
					RefreshToken: "jwt-refresh-token",
				}, nil)
			},
			body: strings.NewReader(`{ "login": "john.doe", "email": "john.doe@local", "first_name": "John", "last_name": "Doe", "password": "password", "appearance": "dark" }`),
			expected: result{
				response: serializers.TokenSerializer{
					AccessToken:  "jwt-access-token",
					RefreshToken: "jwt-refresh-token",
				},
				status: "201 Created",
				code:   http.StatusCreated,
			},
		},
		{
			name:   "Validation Error – Empty Login",
			before: func() {},
			body:   strings.NewReader(`{ "login": "", "email": "john.doe@local", "first_name": "John", "last_name": "Doe", "password": "password", "appearance": "dark" }`),
			expected: result{
				error:  serializers.ErrorSerializer{Error: "empty login"},
				status: "400 Bad Request",
				code:   http.StatusBadRequest,
			},
			error: true,
		},
		{
			name:   "Validation Error – Empty Email",
			before: func() {},
			body:   strings.NewReader(`{ "login": "john.doe", "email": "", "first_name": "John", "last_name": "Doe", "password": "password", "appearance": "dark" }`),
			expected: result{
				error:  serializers.ErrorSerializer{Error: "empty email"},
				status: "400 Bad Request",
				code:   http.StatusBadRequest,
			},
			error: true,
		},
		{
			name:   "Validation Error – Empty Password",
			before: func() {},
			body:   strings.NewReader(`{ "login": "john.doe", "email": "john.doe@local", "first_name": "John", "last_name": "Doe", "password": "", "appearance": "dark" }`),
			expected: result{
				error:  serializers.ErrorSerializer{Error: "empty password"},
				status: "400 Bad Request",
				code:   http.StatusBadRequest,
			},
			error: true,
		},
		{
			name: "Error – Login Already Exists",
			before: func() {
				authentication.EXPECT().Registration(gomock.Any(), gomock.Any()).Return(nil, errors.ErrLoginAlreadyExists)
			},
			body: strings.NewReader(`{ "login": "existing.user", "email": "john.doe@local", "first_name": "John", "last_name": "Doe", "password": "password", "appearance": "dark" }`),
			expected: result{
				error:  serializers.ErrorSerializer{Error: "login already exists"},
				status: "400 Bad Request",
				code:   http.StatusBadRequest,
			},
			error: true,
		},
		{
			name: "Error – Email Already Exists",
			before: func() {
				authentication.EXPECT().Registration(gomock.Any(), gomock.Any()).Return(nil, errors.ErrEmailAlreadyExists)
			},
			body: strings.NewReader(`{ "login": "john.doe", "email": "existing@local", "first_name": "John", "last_name": "Doe", "password": "password", "appearance": "dark" }`),
			expected: result{
				error:  serializers.ErrorSerializer{Error: "email already exists"},
				status: "400 Bad Request",
				code:   http.StatusBadRequest,
			},
			error: true,
		},
		{
			name: "Error",
			before: func() {
				authentication.EXPECT().Registration(gomock.Any(), gomock.Any()).Return(nil, assert.AnError)
			},
			body: strings.NewReader(`{ "login": "john.doe", "email": "john.doe@local", "first_name": "John", "last_name": "Doe", "password": "password", "appearance": "dark" }`),
			expected: result{
				error:  serializers.ErrorSerializer{Error: "assert.AnError general error for testing"},
				status: "400 Bad Request",
				code:   http.StatusBadRequest,
			},
			error: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			req := httptest.NewRequest(http.MethodPost, "/api/users/registrations", tt.body)
			w := httptest.NewRecorder()

			r := chi.NewRouter()
			r.Post("/api/users/registrations", controller.HandleRegistration)
			r.ServeHTTP(w, req)

			resp := w.Result()
			defer resp.Body.Close()

			if tt.error {
				var response serializers.ErrorSerializer
				err := json.NewDecoder(resp.Body).Decode(&response)
				assert.NoError(t, err)
				assert.Equal(t, tt.expected.error, response)
			} else {
				var response serializers.TokenSerializer
				err := json.NewDecoder(resp.Body).Decode(&response)
				assert.NoError(t, err)
				assert.Equal(t, tt.expected.response, response)
			}

			assert.Equal(t, tt.expected.code, resp.StatusCode)
			assert.Equal(t, tt.expected.status, resp.Status)
		})
	}
}

func Test_AuthenticationController_Login(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	cfg := &config.Config{
		AppEnv:   "test",
		AppAddr:  "localhost:8080",
		LogLevel: "info",
	}

	authentication := services.NewMockAuthentication(ctrl)
	log := logger.NewLogger(cfg)
	controller := NewAuthenticationController(authentication, log)

	type result struct {
		response serializers.TokenSerializer
		error    serializers.ErrorSerializer
		status   string
		code     int
	}

	tests := []struct {
		name     string
		before   func()
		body     io.Reader
		expected result
		error    bool
	}{
		{
			name: "Success",
			before: func() {
				authentication.EXPECT().Login(gomock.Any(), &serializers.LoginRequestSerializer{
					Email:    "john.doe@local",
					Password: "password",
				}).Return(&serializers.TokenSerializer{
					AccessToken:  "jwt-access-token",
					RefreshToken: "jwt-refresh-token",
				}, nil)
			},
			body: strings.NewReader(`{ "email": "john.doe@local", "password": "password" }`),
			expected: result{
				response: serializers.TokenSerializer{
					AccessToken:  "jwt-access-token",
					RefreshToken: "jwt-refresh-token",
				},
				status: "200 OK",
				code:   http.StatusOK,
			},
		},
		{
			name:   "Validation Error – Empty Email",
			before: func() {},
			body:   strings.NewReader(`{ "email": "", "password": "password" }`),
			expected: result{
				error:  serializers.ErrorSerializer{Error: "empty email"},
				status: "400 Bad Request",
				code:   http.StatusBadRequest,
			},
			error: true,
		},
		{
			name:   "Validation Error – Empty Password",
			before: func() {},
			body:   strings.NewReader(`{ "email": "john.doe@local", "password": "" }`),
			expected: result{
				error:  serializers.ErrorSerializer{Error: "empty password"},
				status: "400 Bad Request",
				code:   http.StatusBadRequest,
			},
			error: true,
		},
		{
			name: "User Not Found",
			before: func() {
				authentication.EXPECT().Login(gomock.Any(), gomock.Any()).Return(nil, errors.ErrInvalidCredentials)
			},
			body: strings.NewReader(`{ "email": "nonexistent@local", "password": "password" }`),
			expected: result{
				error:  serializers.ErrorSerializer{Error: "invalid credentials"},
				status: "401 Unauthorized",
				code:   http.StatusUnauthorized,
			},
			error: true,
		},
		{
			name: "Invalid Password",
			before: func() {
				authentication.EXPECT().Login(gomock.Any(), gomock.Any()).Return(nil, errors.ErrInvalidPassword)
			},
			body: strings.NewReader(`{ "email": "john.doe@local", "password": "wrongpassword" }`),
			expected: result{
				error:  serializers.ErrorSerializer{Error: "invalid password"},
				status: "401 Unauthorized",
				code:   http.StatusUnauthorized,
			},
			error: true,
		},
		{
			name: "Error – Failed to Generate Access Token",
			before: func() {
				authentication.EXPECT().Login(gomock.Any(), gomock.Any()).Return(nil, jwt.ErrFailedGenerateAccessToken)
			},
			body: strings.NewReader(`{ "email": "john.doe@local", "password": "password" }`),
			expected: result{
				error:  serializers.ErrorSerializer{Error: "failed to generate access token"},
				status: "401 Unauthorized",
				code:   http.StatusUnauthorized,
			},
			error: true,
		},
		{
			name: "Error",
			before: func() {
				authentication.EXPECT().Login(gomock.Any(), gomock.Any()).Return(nil, assert.AnError)
			},
			body: strings.NewReader(`{ "email": "john.doe@local", "password": "password" }`),
			expected: result{
				error:  serializers.ErrorSerializer{Error: "assert.AnError general error for testing"},
				status: "401 Unauthorized",
				code:   http.StatusUnauthorized,
			},
			error: true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			req := httptest.NewRequest(http.MethodPost, "/api/users/login", tt.body)
			w := httptest.NewRecorder()

			r := chi.NewRouter()
			r.Post("/api/users/login", controller.HandleLogin)
			r.ServeHTTP(w, req)

			resp := w.Result()
			defer resp.Body.Close()

			if tt.error {
				var response serializers.ErrorSerializer
				err := json.NewDecoder(resp.Body).Decode(&response)
				assert.NoError(t, err)
				assert.Equal(t, tt.expected.error, response)
			} else {
				var response serializers.TokenSerializer
				err := json.NewDecoder(resp.Body).Decode(&response)
				assert.NoError(t, err)
				assert.Equal(t, tt.expected.response, response)
			}

			assert.Equal(t, tt.expected.code, resp.StatusCode)
			assert.Equal(t, tt.expected.status, resp.Status)
		})
	}
}
