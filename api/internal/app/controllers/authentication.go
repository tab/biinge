package controllers

import (
	"encoding/json"
	"net/http"

	"biinge-api/internal/app/serializers"
	"biinge-api/internal/app/services"
	"biinge-api/internal/config/logger"
)

type AuthenticationController interface {
	HandleRegistration(w http.ResponseWriter, r *http.Request)
	HandleLogin(w http.ResponseWriter, r *http.Request)
}

type authenticationController struct {
	service services.Authentication
	log     *logger.Logger
}

func NewAuthenticationController(service services.Authentication, log *logger.Logger) AuthenticationController {
	return &authenticationController{
		service: service,
		log:     log.WithComponent("AuthenticationController"),
	}
}

//nolint:dupl
func (c *authenticationController) HandleRegistration(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	var params serializers.RegistrationRequestSerializer
	if err := params.Validate(r.Body); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: err.Error()})
		return
	}

	response, err := c.service.Registration(r.Context(), &params)
	if err != nil {
		c.log.Error().Err(err).Msg("Registration failed")
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: err.Error()})
		return
	}

	w.WriteHeader(http.StatusCreated)
	_ = json.NewEncoder(w).Encode(response)
}

//nolint:dupl
func (c *authenticationController) HandleLogin(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	var params serializers.LoginRequestSerializer
	if err := params.Validate(r.Body); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: err.Error()})
		return
	}

	response, err := c.service.Login(r.Context(), &params)
	if err != nil {
		c.log.Error().Err(err).Msg("Login failed")
		w.WriteHeader(http.StatusUnauthorized)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: err.Error()})
		return
	}

	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(response)
}
