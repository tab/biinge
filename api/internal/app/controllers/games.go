package controllers

import (
	"encoding/json"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/models"
	"biinge-api/internal/app/serializers"
	"biinge-api/internal/app/services"
	"biinge-api/internal/config/middlewares"
)

type GamesController interface {
	HandleList(w http.ResponseWriter, r *http.Request)
	HandleDetails(w http.ResponseWriter, r *http.Request)
	HandleCreate(w http.ResponseWriter, r *http.Request)
	HandleUpdate(w http.ResponseWriter, r *http.Request)
	HandleDelete(w http.ResponseWriter, r *http.Request)
}

type gamesController struct {
	games    services.Games
	provider services.IgdbProvider
}

func NewGamesController(games services.Games, provider services.IgdbProvider) GamesController {
	return &gamesController{
		games:    games,
		provider: provider,
	}
}

func (c *gamesController) HandleList(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	user, ok := middlewares.CurrentUserFromContext(r.Context())
	if !ok {
		w.WriteHeader(http.StatusUnauthorized)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: errors.ErrUnauthorized.Error()})

		return
	}

	listType := models.NewGameListState(r.URL.Query().Get("type"))

	pagination := services.NewPagination(r)

	rows, total, err := c.games.List(r.Context(), user.ID, listType, pagination)
	if err != nil {
		w.WriteHeader(http.StatusUnprocessableEntity)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: err.Error()})

		return
	}

	collection := make([]serializers.GameSerializer, 0, len(rows))
	for _, row := range rows {
		collection = append(collection, serializers.GameSerializer{
			Id:         row.IgdbId,
			Title:      row.Title,
			PosterPath: row.PosterPath,
			Pinned:     row.Pinned,
			State:      row.State,
		})
	}

	response := serializers.PaginationResponse[serializers.GameSerializer]{
		Data: collection,
		Meta: serializers.PaginationMeta{
			Page:  pagination.Page,
			Per:   pagination.PerPage,
			Total: total,
		},
	}

	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(response)
}

func (c *gamesController) HandleDetails(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	user, ok := middlewares.CurrentUserFromContext(r.Context())
	if !ok {
		w.WriteHeader(http.StatusUnauthorized)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: errors.ErrUnauthorized.Error()})

		return
	}

	id, err := strconv.ParseUint(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: "invalid igdb id"})

		return
	}

	response, err := c.provider.FetchGameDetails(r.Context(), id, user.ID)
	if err != nil {
		w.WriteHeader(http.StatusUnprocessableEntity)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: err.Error()})

		return
	}

	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(response)
}

func (c *gamesController) HandleCreate(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	user, ok := middlewares.CurrentUserFromContext(r.Context())
	if !ok {
		w.WriteHeader(http.StatusUnauthorized)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: errors.ErrUnauthorized.Error()})

		return
	}

	var params serializers.CreateGameRequestSerializer
	if err := params.Validate(r.Body); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: err.Error()})

		return
	}

	row, err := c.games.Create(r.Context(), &models.Game{
		UserId:     user.ID,
		IgdbId:     params.Id,
		Title:      params.Title,
		PosterPath: params.PosterPath,
		Runtime:    params.Runtime,
		State:      models.StateType(params.State),
	})
	if err != nil {
		w.WriteHeader(http.StatusUnprocessableEntity)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: err.Error()})

		return
	}

	// the write acknowledges state only, but the spec marks these arrays required, and a nil slice
	// encodes as null, which no client can decode into an array
	response := serializers.GameDetailsSerializer{
		Id:              row.IgdbId,
		Pinned:          row.Pinned,
		State:           row.State,
		Genres:          make([]string, 0),
		Platforms:       make([]string, 0),
		Recommendations: make([]serializers.RecommendationSerializer, 0),
	}

	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(response)
}

func (c *gamesController) HandleUpdate(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	user, ok := middlewares.CurrentUserFromContext(r.Context())
	if !ok {
		w.WriteHeader(http.StatusUnauthorized)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: errors.ErrUnauthorized.Error()})

		return
	}

	id, err := strconv.ParseUint(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: "invalid igdb id"})

		return
	}

	var params serializers.UpdateGameRequestSerializer
	if err = params.Validate(r.Body); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: err.Error()})

		return
	}

	row, err := c.games.UpdateByIgdbId(r.Context(), &models.Game{
		IgdbId: id,
		UserId: user.ID,
		State:  models.StateType(params.State),
		Pinned: params.Pinned,
	})
	if err != nil {
		w.WriteHeader(http.StatusUnprocessableEntity)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: err.Error()})

		return
	}

	// the write acknowledges state only, but the spec marks these arrays required, and a nil slice
	// encodes as null, which no client can decode into an array
	response := serializers.GameDetailsSerializer{
		Id:              row.IgdbId,
		Pinned:          row.Pinned,
		State:           row.State,
		Genres:          make([]string, 0),
		Platforms:       make([]string, 0),
		Recommendations: make([]serializers.RecommendationSerializer, 0),
	}

	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(response)
}

func (c *gamesController) HandleDelete(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	user, ok := middlewares.CurrentUserFromContext(r.Context())
	if !ok {
		w.WriteHeader(http.StatusUnauthorized)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: errors.ErrUnauthorized.Error()})

		return
	}

	id, err := strconv.ParseUint(chi.URLParam(r, "id"), 10, 64)
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: "invalid igdb id"})

		return
	}

	err = c.games.DeleteByIgdbId(r.Context(), id, user.ID)
	if err != nil {
		w.WriteHeader(http.StatusUnprocessableEntity)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: err.Error()})

		return
	}

	w.WriteHeader(http.StatusNoContent)
}
