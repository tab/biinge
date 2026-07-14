package controllers

import (
	"encoding/json"
	"net/http"
	"strconv"
	"strings"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/serializers"
	"biinge-api/internal/app/services"
	"biinge-api/internal/config/logger"
	"biinge-api/internal/config/middlewares"
)

type CatalogController interface {
	HandleSearchMovies(w http.ResponseWriter, r *http.Request)
	HandleSearchSeries(w http.ResponseWriter, r *http.Request)
	HandleSearchPeople(w http.ResponseWriter, r *http.Request)
	HandleTrendingMovies(w http.ResponseWriter, r *http.Request)
	HandleTrendingSeries(w http.ResponseWriter, r *http.Request)
	HandleTrendingPeople(w http.ResponseWriter, r *http.Request)
}

type catalogController struct {
	provider services.TmdbProvider
	log      *logger.Logger
}

func NewCatalogController(provider services.TmdbProvider, log *logger.Logger) CatalogController {
	return &catalogController{
		provider: provider,
		log:      log.WithComponent("CatalogController"),
	}
}

func (c *catalogController) HandleSearchMovies(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	user, ok := middlewares.CurrentUserFromContext(r.Context())
	if !ok {
		w.WriteHeader(http.StatusUnauthorized)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: errors.ErrUnauthorized.Error()})

		return
	}

	query, ok := searchQuery(w, r)
	if !ok {
		return
	}

	response, err := c.provider.SearchMovies(r.Context(), query, pageParam(r), user.ID)
	if err != nil {
		w.WriteHeader(http.StatusUnprocessableEntity)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: err.Error()})

		return
	}

	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(response)
}

func (c *catalogController) HandleSearchSeries(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	user, ok := middlewares.CurrentUserFromContext(r.Context())
	if !ok {
		w.WriteHeader(http.StatusUnauthorized)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: errors.ErrUnauthorized.Error()})

		return
	}

	query, ok := searchQuery(w, r)
	if !ok {
		return
	}

	response, err := c.provider.SearchSeries(r.Context(), query, pageParam(r), user.ID)
	if err != nil {
		w.WriteHeader(http.StatusUnprocessableEntity)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: err.Error()})

		return
	}

	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(response)
}

func (c *catalogController) HandleSearchPeople(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	query, ok := searchQuery(w, r)
	if !ok {
		return
	}

	response, err := c.provider.SearchPeople(r.Context(), query, pageParam(r))
	if err != nil {
		w.WriteHeader(http.StatusUnprocessableEntity)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: err.Error()})

		return
	}

	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(response)
}

func (c *catalogController) HandleTrendingMovies(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	user, ok := middlewares.CurrentUserFromContext(r.Context())
	if !ok {
		w.WriteHeader(http.StatusUnauthorized)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: errors.ErrUnauthorized.Error()})

		return
	}

	response, err := c.provider.FetchTrendingMovies(r.Context(), user.ID)
	if err != nil {
		w.WriteHeader(http.StatusUnprocessableEntity)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: err.Error()})

		return
	}

	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(response)
}

func (c *catalogController) HandleTrendingSeries(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	user, ok := middlewares.CurrentUserFromContext(r.Context())
	if !ok {
		w.WriteHeader(http.StatusUnauthorized)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: errors.ErrUnauthorized.Error()})

		return
	}

	response, err := c.provider.FetchTrendingSeries(r.Context(), user.ID)
	if err != nil {
		w.WriteHeader(http.StatusUnprocessableEntity)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: err.Error()})

		return
	}

	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(response)
}

func (c *catalogController) HandleTrendingPeople(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	response, err := c.provider.FetchTrendingPeople(r.Context())
	if err != nil {
		w.WriteHeader(http.StatusUnprocessableEntity)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: err.Error()})

		return
	}

	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(response)
}

// searchQuery extracts the required query parameter, writing a 400 when missing
func searchQuery(w http.ResponseWriter, r *http.Request) (string, bool) {
	query := strings.TrimSpace(r.URL.Query().Get("query"))
	if query == "" {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: errors.ErrEmptyQuery.Error()})

		return "", false
	}

	return query, true
}

// pageParam parses the optional `page` parameter, defaulting to the first page
func pageParam(r *http.Request) uint64 {
	page, err := strconv.ParseUint(r.URL.Query().Get("page"), 10, 64)
	if err != nil || page == 0 {
		return 1
	}

	return page
}
