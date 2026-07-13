package controllers

import (
	"encoding/json"
	"net/http"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/models"
	"biinge-api/internal/app/serializers"
	"biinge-api/internal/app/services"
	"biinge-api/internal/config/logger"
	"biinge-api/internal/config/middlewares"
)

type AccountsController interface {
	Me(w http.ResponseWriter, r *http.Request)
	HandleUpdate(w http.ResponseWriter, r *http.Request)
	HandleStats(w http.ResponseWriter, r *http.Request)
}

type accountsController struct {
	users services.Users
	stats services.Stats
	log   *logger.Logger
}

func NewAccountsController(users services.Users, stats services.Stats, log *logger.Logger) AccountsController {
	return &accountsController{
		users: users,
		stats: stats,
		log:   log.WithComponent("AccountsController"),
	}
}

func (c *accountsController) Me(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	user, ok := middlewares.CurrentUserFromContext(r.Context())
	if !ok {
		w.WriteHeader(http.StatusUnauthorized)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: errors.ErrUnauthorized.Error()})

		return
	}

	response := serializers.UserSerializer{
		ID:         user.ID,
		Login:      user.Login,
		Email:      user.Email,
		FirstName:  user.FirstName,
		LastName:   user.LastName,
		Appearance: user.Appearance,
	}

	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(response)
}

func (c *accountsController) HandleUpdate(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	user, ok := middlewares.CurrentUserFromContext(r.Context())
	if !ok {
		w.WriteHeader(http.StatusUnauthorized)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: errors.ErrUnauthorized.Error()})

		return
	}

	var params serializers.UpdateAccountRequestSerializer
	if err := params.Validate(r.Body); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: err.Error()})

		return
	}

	result, err := c.users.Update(r.Context(), &models.User{
		ID:         user.ID,
		FirstName:  params.FirstName,
		LastName:   params.LastName,
		Appearance: params.Appearance,
	})
	if err != nil {
		c.log.Error().Err(err).Msg("Update failed")
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: err.Error()})

		return
	}

	response := serializers.UserSerializer{
		ID:         result.ID,
		Login:      result.Login,
		Email:      result.Email,
		FirstName:  result.FirstName,
		LastName:   result.LastName,
		Appearance: result.Appearance,
	}

	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(response)
}

func (c *accountsController) HandleStats(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	user, ok := middlewares.CurrentUserFromContext(r.Context())
	if !ok {
		w.WriteHeader(http.StatusUnauthorized)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: errors.ErrUnauthorized.Error()})

		return
	}

	result, err := c.stats.Get(r.Context(), user.ID)
	if err != nil {
		w.WriteHeader(http.StatusUnprocessableEntity)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: err.Error()})

		return
	}

	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(serializers.NewStatsSerializer(result))
}
