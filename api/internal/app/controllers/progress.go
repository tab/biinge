package controllers

import (
	"encoding/json"
	"net/http"
	"strconv"

	"github.com/go-chi/chi/v5"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/models"
	"biinge-api/internal/app/serializers"
	"biinge-api/internal/config/middlewares"
)

func (c *seriesController) HandleProgress(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	user, ok := middlewares.CurrentUserFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, errors.ErrUnauthorized)
		return
	}

	seriesTmdbId, err := parseTmdbParam(r, "id")
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}

	progress, err := c.progress.Get(r.Context(), user.ID, seriesTmdbId)
	if err != nil {
		writeError(w, http.StatusUnprocessableEntity, err)
		return
	}

	writeProgress(w, progress)
}

func (c *seriesController) HandleMarkShowWatched(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	user, ok := middlewares.CurrentUserFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, errors.ErrUnauthorized)
		return
	}

	seriesTmdbId, err := parseTmdbParam(r, "id")
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}

	var params serializers.MarkShowRequestSerializer
	if err = params.Validate(r.Body); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}

	progress, err := c.progress.MarkShow(r.Context(), user.ID, params.ToInput(seriesTmdbId))
	if err != nil {
		writeError(w, http.StatusUnprocessableEntity, err)
		return
	}

	writeProgress(w, progress)
}

func (c *seriesController) HandleUnmarkShowWatched(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	user, ok := middlewares.CurrentUserFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, errors.ErrUnauthorized)
		return
	}

	seriesTmdbId, err := parseTmdbParam(r, "id")
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}

	progress, err := c.progress.UnmarkShow(r.Context(), user.ID, seriesTmdbId)
	if err != nil {
		writeError(w, http.StatusUnprocessableEntity, err)
		return
	}

	writeProgress(w, progress)
}

func (c *seriesController) HandleMarkSeasonWatched(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	user, ok := middlewares.CurrentUserFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, errors.ErrUnauthorized)
		return
	}

	seriesTmdbId, err := parseTmdbParam(r, "id")
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}

	seasonTmdbId, err := parseTmdbParam(r, "seasonId")
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}

	var params serializers.MarkSeasonRequestSerializer
	if err = params.Validate(r.Body); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}

	series, season := params.ToInputs(seriesTmdbId, seasonTmdbId)
	progress, err := c.progress.MarkSeason(r.Context(), user.ID, series, season)
	if err != nil {
		writeError(w, http.StatusUnprocessableEntity, err)
		return
	}

	writeProgress(w, progress)
}

func (c *seriesController) HandleUnmarkSeasonWatched(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	user, ok := middlewares.CurrentUserFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, errors.ErrUnauthorized)
		return
	}

	seriesTmdbId, err := parseTmdbParam(r, "id")
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}

	seasonTmdbId, err := parseTmdbParam(r, "seasonId")
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}

	progress, err := c.progress.UnmarkSeason(r.Context(), user.ID, seriesTmdbId, seasonTmdbId)
	if err != nil {
		writeError(w, http.StatusUnprocessableEntity, err)
		return
	}

	writeProgress(w, progress)
}

func (c *seriesController) HandleMarkEpisodeWatched(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	user, ok := middlewares.CurrentUserFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, errors.ErrUnauthorized)
		return
	}

	seriesTmdbId, err := parseTmdbParam(r, "id")
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}

	seasonTmdbId, err := parseTmdbParam(r, "seasonId")
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}

	episodeTmdbId, err := parseTmdbParam(r, "episodeId")
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}

	var params serializers.MarkEpisodeRequestSerializer
	if err = params.Validate(r.Body); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}

	series, season, episode := params.ToInputs(seriesTmdbId, seasonTmdbId, episodeTmdbId)
	progress, err := c.progress.MarkEpisode(r.Context(), user.ID, series, season, episode)
	if err != nil {
		writeError(w, http.StatusUnprocessableEntity, err)
		return
	}

	writeProgress(w, progress)
}

func (c *seriesController) HandleUnmarkEpisodeWatched(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")

	user, ok := middlewares.CurrentUserFromContext(r.Context())
	if !ok {
		writeError(w, http.StatusUnauthorized, errors.ErrUnauthorized)
		return
	}

	seriesTmdbId, err := parseTmdbParam(r, "id")
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}

	seasonTmdbId, err := parseTmdbParam(r, "seasonId")
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}

	episodeTmdbId, err := parseTmdbParam(r, "episodeId")
	if err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}

	progress, err := c.progress.UnmarkEpisode(r.Context(), user.ID, seriesTmdbId, seasonTmdbId, episodeTmdbId)
	if err != nil {
		writeError(w, http.StatusUnprocessableEntity, err)
		return
	}

	writeProgress(w, progress)
}

// parseTmdbParam reads a uint64 TMDB id from a chi URL parameter.
func parseTmdbParam(r *http.Request, name string) (uint64, error) {
	id, err := strconv.ParseUint(chi.URLParam(r, name), 10, 64)
	if err != nil {
		return 0, errors.ErrInvalidTmdbId
	}
	return id, nil
}

func writeError(w http.ResponseWriter, status int, err error) {
	w.WriteHeader(status)
	_ = json.NewEncoder(w).Encode(serializers.ErrorSerializer{Error: err.Error()})
}

func writeProgress(w http.ResponseWriter, progress *models.SeriesProgress) {
	w.WriteHeader(http.StatusOK)
	_ = json.NewEncoder(w).Encode(serializers.NewProgressResponse(progress))
}
