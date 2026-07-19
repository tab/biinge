package middlewares

import (
	"encoding/json"
	"net/http"
	"strings"

	"github.com/google/uuid"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/serializers"
	"biinge-api/internal/app/services"
	"biinge-api/internal/config/logger"
	"biinge-api/pkg/jwt"
)

type AuthenticationMiddleware interface {
	Authenticate(next http.Handler) http.Handler
}

type authenticationMiddleware struct {
	jwt   jwt.Jwt
	users services.Users
	log   *logger.Logger
}

func NewAuthenticationMiddleware(jwt jwt.Jwt, users services.Users, log *logger.Logger) AuthenticationMiddleware {
	return &authenticationMiddleware{
		jwt:   jwt,
		users: users,
		log:   log.WithComponent("AuthenticationMiddleware"),
	}
}

func (m *authenticationMiddleware) Authenticate(next http.Handler) http.Handler {
	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		token, ok := extractBearerToken(r)
		if !ok {
			m.log.Error().Msg("Invalid authorization header")
			writeJSONError(w, http.StatusUnauthorized, "unauthorized")

			return
		}

		claims, err := m.jwt.Decode(token)
		if err != nil {
			m.log.Error().Err(err).Msg("Failed to decode token")
			writeJSONError(w, http.StatusUnauthorized, "unauthorized")

			return
		}

		// Reject refresh tokens as access credentials; legacy untyped tokens stay accepted
		if claims.Type == jwt.TokenTypeRefresh {
			m.log.Error().Msg("Refresh token used on a protected endpoint")
			writeJSONError(w, http.StatusUnauthorized, "unauthorized")

			return
		}

		id, err := uuid.Parse(claims.ID)
		if err != nil {
			m.log.Error().Err(err).Msg("Failed to parse user Id from claims")
			writeJSONError(w, http.StatusUnauthorized, "unauthorized")

			return
		}

		user, err := m.users.FindById(r.Context(), id)
		if err != nil {
			// A missing user is an auth failure; anything else is the datastore, not the caller
			if errors.Is(err, errors.ErrUserNotFound) {
				m.log.Error().Err(err).Msg("Token references an unknown user")
				writeJSONError(w, http.StatusUnauthorized, "unauthorized")

				return
			}

			m.log.Error().Err(err).Msg("Failed to find user by identity number")
			writeJSONError(w, http.StatusServiceUnavailable, "service unavailable")

			return
		}

		ctx := NewContextModifier(r.Context()).
			WithCurrentUser(user).
			Context()

		SetCurrentUserId(r.Context(), user.ID.String())

		next.ServeHTTP(w, r.WithContext(ctx))
	})
}

// writeJSONError sends a constant JSON error body with the content type set before the status
func writeJSONError(w http.ResponseWriter, status int, message string) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: message})
}

func extractBearerToken(r *http.Request) (string, bool) {
	authHeader := r.Header.Get(Authorization)
	if authHeader == "" {
		return "", false
	}

	if len(authHeader) < len(bearerScheme) || !strings.EqualFold(authHeader[:len(bearerScheme)], bearerScheme) {
		return "", false
	}

	token := authHeader[len(bearerScheme):]
	if token == "" {
		return "", false
	}

	return token, true
}
