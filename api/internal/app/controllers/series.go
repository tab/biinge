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

type SeriesController interface {
	HandleList(w http.ResponseWriter, r *http.Request)
	HandleDetails(w http.ResponseWriter, r *http.Request)
	HandleSeasonDetails(w http.ResponseWriter, r *http.Request)
	HandleEpisodeDetails(w http.ResponseWriter, r *http.Request)
	HandleCreate(w http.ResponseWriter, r *http.Request)
	HandleUpdate(w http.ResponseWriter, r *http.Request)
	HandleDelete(w http.ResponseWriter, r *http.Request)

	HandleProgress(w http.ResponseWriter, r *http.Request)
	HandleMarkShowWatched(w http.ResponseWriter, r *http.Request)
	HandleUnmarkShowWatched(w http.ResponseWriter, r *http.Request)
	HandleMarkSeasonWatched(w http.ResponseWriter, r *http.Request)
	HandleUnmarkSeasonWatched(w http.ResponseWriter, r *http.Request)
	HandleMarkEpisodeWatched(w http.ResponseWriter, r *http.Request)
	HandleUnmarkEpisodeWatched(w http.ResponseWriter, r *http.Request)
}

type seriesController struct {
	series   services.Series
	progress services.Progress
	provider services.TmdbProvider
}

func NewSeriesController(series services.Series, progress services.Progress, provider services.TmdbProvider) SeriesController {
	return &seriesController{
		series:   series,
		progress: progress,
		provider: provider,
	}
}

func (c *seriesController) HandleList(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	user, ok := middlewares.CurrentUserFromContext(r.Context())
	if !ok {
		w.WriteHeader(http.StatusUnauthorized)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: errors.ErrUnauthorized.Error()})

		return
	}

	listType := models.NewSeriesListState(r.URL.Query().Get("type"))

	pagination := services.NewPagination(r)

	rows, total, err := c.series.List(r.Context(), user.ID, listType, pagination)
	if err != nil {
		w.WriteHeader(http.StatusUnprocessableEntity)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: err.Error()})

		return
	}

	collection := make([]serializers.SeriesSerializer, 0, len(rows))
	for _, row := range rows {
		collection = append(collection, serializers.SeriesSerializer{
			Id:                   row.TmdbId,
			Title:                row.Title,
			PosterPath:           row.PosterPath,
			Pinned:               row.Pinned,
			State:                row.State,
			EpisodesCount:        row.EpisodesCount,
			WatchedEpisodesCount: row.WatchedEpisodesCount,
		})
	}

	response := serializers.PaginationResponse[serializers.SeriesSerializer]{
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

func (c *seriesController) HandleDetails(w http.ResponseWriter, r *http.Request) {
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
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: "invalid tmdb id"})

		return
	}

	response, err := c.provider.FetchTvDetails(r.Context(), id, user.ID)
	if err != nil {
		w.WriteHeader(http.StatusUnprocessableEntity)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: err.Error()})

		return
	}

	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(response)
}

func (c *seriesController) HandleCreate(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	user, ok := middlewares.CurrentUserFromContext(r.Context())
	if !ok {
		w.WriteHeader(http.StatusUnauthorized)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: errors.ErrUnauthorized.Error()})

		return
	}

	var params serializers.CreateSeriesRequestSerializer
	if err := params.Validate(r.Body); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: err.Error()})

		return
	}

	row, err := c.series.Create(r.Context(), &models.Series{
		UserId:        user.ID,
		TmdbId:        params.Id,
		Title:         params.Title,
		PosterPath:    params.PosterPath,
		SeasonsCount:  params.SeasonsCount,
		EpisodesCount: params.EpisodesCount,
		Status:        params.Status,
		State:         models.StateType(params.State),
	})
	if err != nil {
		w.WriteHeader(http.StatusUnprocessableEntity)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: err.Error()})

		return
	}

	// the write acknowledges state only, but the spec marks these arrays required, and a nil slice
	// encodes as null, which no client can decode into an array
	response := serializers.SeriesDetailsSerializer{
		Id:              row.TmdbId,
		Pinned:          row.Pinned,
		State:           row.State,
		Credits:         make([]serializers.PersonSerializer, 0),
		Recommendations: make([]serializers.RecommendationSerializer, 0),
		Videos:          make([]serializers.VideoSerializer, 0),
		Seasons:         make([]serializers.SeasonSummarySerializer, 0),
	}

	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(response)
}

func (c *seriesController) HandleUpdate(w http.ResponseWriter, r *http.Request) {
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
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: "invalid tmdb id"})

		return
	}

	var params serializers.UpdateSeriesRequestSerializer
	if err = params.Validate(r.Body); err != nil {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: err.Error()})

		return
	}

	row, err := c.series.UpdateByTmdbId(r.Context(), &models.Series{
		TmdbId: id,
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
	response := serializers.SeriesDetailsSerializer{
		Id:              row.TmdbId,
		Pinned:          row.Pinned,
		State:           row.State,
		Credits:         make([]serializers.PersonSerializer, 0),
		Recommendations: make([]serializers.RecommendationSerializer, 0),
		Videos:          make([]serializers.VideoSerializer, 0),
		Seasons:         make([]serializers.SeasonSummarySerializer, 0),
	}

	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(response)
}

func (c *seriesController) HandleDelete(w http.ResponseWriter, r *http.Request) {
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
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: "invalid tmdb id"})

		return
	}

	err = c.series.Delete(r.Context(), id, user.ID)
	if err != nil {
		w.WriteHeader(http.StatusUnprocessableEntity)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: err.Error()})

		return
	}

	w.WriteHeader(http.StatusNoContent)
}

func (c *seriesController) HandleSeasonDetails(w http.ResponseWriter, r *http.Request) {
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
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: "invalid tmdb id"})

		return
	}

	seasonNumber, err := strconv.ParseUint(chi.URLParam(r, "seasonNumber"), 10, 64)
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: "invalid season number"})

		return
	}

	response, err := c.provider.FetchTvSeasonDetails(r.Context(), id, seasonNumber, user.ID)
	if err != nil {
		w.WriteHeader(http.StatusUnprocessableEntity)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: err.Error()})

		return
	}

	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(response)
}

func (c *seriesController) HandleEpisodeDetails(w http.ResponseWriter, r *http.Request) {
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
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: "invalid tmdb id"})

		return
	}

	seasonNumber, err := strconv.ParseUint(chi.URLParam(r, "seasonNumber"), 10, 64)
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: "invalid season number"})

		return
	}

	episodeNumber, err := strconv.ParseUint(chi.URLParam(r, "episodeNumber"), 10, 64)
	if err != nil {
		w.WriteHeader(http.StatusBadRequest)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: "invalid episode number"})

		return
	}

	response, err := c.provider.FetchTvEpisodeDetails(r.Context(), id, seasonNumber, episodeNumber, user.ID)
	if err != nil {
		w.WriteHeader(http.StatusUnprocessableEntity)
		_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: err.Error()})

		return
	}

	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(response)
}
