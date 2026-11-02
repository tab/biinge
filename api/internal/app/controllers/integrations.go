package controllers

import (
	"encoding/json"
	"net/http"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/serializers"
	"biinge-api/internal/app/services"
	"biinge-api/internal/config/middlewares"
	"biinge-api/pkg/jellyfin"
)

// maxJellyfinEventBytes caps a webhook body so a token holder cannot exhaust memory with one request
const maxJellyfinEventBytes = 1 << 20

type IntegrationsController interface {
	HandleCreateToken(w http.ResponseWriter, r *http.Request)
	HandleRevoke(w http.ResponseWriter, r *http.Request)
	HandleJellyfinWebhook(w http.ResponseWriter, r *http.Request)
	HandleConnect(w http.ResponseWriter, r *http.Request)
	HandleStatus(w http.ResponseWriter, r *http.Request)
	HandleDisconnect(w http.ResponseWriter, r *http.Request)
}

type integrationsController struct {
	integrations services.Integrations
	jellyfin     services.Jellyfin
}

func NewIntegrationsController(integrations services.Integrations, jellyfin services.Jellyfin) IntegrationsController {
	return &integrationsController{
		integrations: integrations,
		jellyfin:     jellyfin,
	}
}

func (c *integrationsController) HandleCreateToken(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	user, ok := middlewares.CurrentUserFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, errors.ErrUnauthorized)
		return
	}

	token, err := c.integrations.CreateToken(r.Context(), user.ID)
	if err != nil {
		writeError(w, http.StatusUnprocessableEntity, err)
		return
	}

	w.WriteHeader(http.StatusCreated)
	_ = json.NewEncoder(w).Encode(serializers.IntegrationTokenSerializer{Token: token})
}

func (c *integrationsController) HandleRevoke(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	user, ok := middlewares.CurrentUserFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, errors.ErrUnauthorized)
		return
	}

	if err := c.integrations.Revoke(r.Context(), user.ID); err != nil {
		writeError(w, http.StatusUnprocessableEntity, err)
		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// HandleJellyfinWebhook checks the token before reading the body, so a bad token never costs a parse
func (c *integrationsController) HandleJellyfinWebhook(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	token, ok := middlewares.BearerToken(r)
	if !ok {
		writeError(w, http.StatusUnauthorized, errors.ErrUnauthorized)
		return
	}

	integration, err := c.integrations.Authenticate(r.Context(), token)
	if err != nil {
		if errors.Is(err, errors.ErrUnauthorized) {
			writeError(w, http.StatusUnauthorized, err)
			return
		}

		// the lookup failed, not the token
		writeError(w, http.StatusServiceUnavailable, err)

		return
	}

	event, err := jellyfin.ParseEvent(http.MaxBytesReader(w, r.Body, maxJellyfinEventBytes))
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}

	if err = c.jellyfin.Handle(r.Context(), integration, event); err != nil {
		switch {
		case errors.Is(err, errors.ErrTmdbUnavailable):
			writeError(w, http.StatusBadGateway, err)
		case errors.Is(err, errors.ErrFailedToProcessWebhook):
			writeError(w, http.StatusServiceUnavailable, err)
		default:
			// no usable provider id, or TMDB does not know it
			writeError(w, http.StatusUnprocessableEntity, err)
		}

		return
	}

	w.WriteHeader(http.StatusNoContent)
}

// HandleConnect signs the user in to Jellyfin (a Jellyfin failure is never 401, so the apps never read it as a biinge logout)
func (c *integrationsController) HandleConnect(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	user, ok := middlewares.CurrentUserFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, errors.ErrUnauthorized)
		return
	}

	var params serializers.JellyfinConnectionRequestSerializer
	if err := params.Validate(r.Body); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}

	connection, err := c.integrations.Connect(r.Context(), user.ID, jellyfin.Credentials{
		Username: params.Username,
		Password: params.Password,
	})
	if err != nil {
		switch {
		case errors.Is(err, errors.ErrJellyfinNotConfigured):
			writeError(w, http.StatusNotFound, err)
		case errors.Is(err, errors.ErrInvalidJellyfinCredentials):
			writeError(w, http.StatusUnprocessableEntity, err)
		case errors.Is(err, errors.ErrJellyfinUnavailable):
			writeError(w, http.StatusBadGateway, err)
		case errors.Is(err, errors.ErrFailedToSaveJellyfinConnection):
			writeError(w, http.StatusServiceUnavailable, err)
		default:
			writeError(w, http.StatusInternalServerError, err)
		}

		return
	}

	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(serializers.JellyfinConnectionSerializer{
		BaseURL:   connection.BaseURL,
		Connected: connection.Connected,
		Username:  connection.Username,
	})
}

func (c *integrationsController) HandleStatus(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	user, ok := middlewares.CurrentUserFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, errors.ErrUnauthorized)
		return
	}

	connection, err := c.integrations.Status(r.Context(), user.ID)
	if err != nil {
		switch {
		case errors.Is(err, errors.ErrJellyfinNotConfigured):
			writeError(w, http.StatusNotFound, err)
		case errors.Is(err, errors.ErrFailedToFetchJellyfinConnection):
			writeError(w, http.StatusServiceUnavailable, err)
		default:
			writeError(w, http.StatusInternalServerError, err)
		}

		return
	}

	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(serializers.JellyfinConnectionSerializer{
		BaseURL:   connection.BaseURL,
		Connected: connection.Connected,
		Username:  connection.Username,
	})
}

func (c *integrationsController) HandleDisconnect(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	user, ok := middlewares.CurrentUserFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, errors.ErrUnauthorized)
		return
	}

	if err := c.integrations.Disconnect(r.Context(), user.ID); err != nil {
		switch {
		case errors.Is(err, errors.ErrJellyfinNotConfigured):
			writeError(w, http.StatusNotFound, err)
		case errors.Is(err, errors.ErrFailedToDeleteJellyfinConnection):
			writeError(w, http.StatusServiceUnavailable, err)
		default:
			writeError(w, http.StatusInternalServerError, err)
		}

		return
	}

	w.WriteHeader(http.StatusNoContent)
}
