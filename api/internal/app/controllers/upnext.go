package controllers

import (
	"encoding/json"
	"net/http"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/serializers"
	"biinge-api/internal/app/services"
	"biinge-api/internal/config/middlewares"
)

type UpNextController interface {
	HandleUpNext(w http.ResponseWriter, r *http.Request)
}

type upNextController struct {
	provider services.TmdbProvider
	games    services.IgdbProvider
}

func NewUpNextController(provider services.TmdbProvider, games services.IgdbProvider) UpNextController {
	return &upNextController{
		provider: provider,
		games:    games,
	}
}

func (c *upNextController) HandleUpNext(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	user, ok := middlewares.CurrentUserFromContext(r.Context())
	if !ok {
		w.WriteHeader(http.StatusUnauthorized)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: errors.ErrUnauthorized.Error()})

		return
	}

	response, err := c.provider.FetchUpNext(r.Context(), user.ID)
	if err != nil {
		w.WriteHeader(http.StatusUnprocessableEntity)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: err.Error()})

		return
	}

	// the queue spans two providers, so the controller merges them the way the catalog handlers split them
	games, err := c.games.FetchUpNextGames(r.Context(), user.ID)
	if err != nil {
		w.WriteHeader(http.StatusUnprocessableEntity)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: err.Error()})

		return
	}

	response.Games = games

	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(response)
}
