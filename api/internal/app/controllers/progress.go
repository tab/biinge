package controllers

import (
	"encoding/json"
	"net/http"
	"slices"
	"strconv"

	"github.com/go-chi/chi/v5"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/models"
	"biinge-api/internal/app/serializers"
	"biinge-api/internal/app/services"
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

func (c *seriesController) HandleMarkSeriesWatched(w http.ResponseWriter, r *http.Request) {
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

	var params serializers.MarkSeriesRequestSerializer
	if err = params.Validate(r.Body); err != nil {
		writeError(w, http.StatusBadRequest, err)
		return
	}

	// the progress before the mark tells whether it changes what Jellyfin holds
	before, err := c.progress.Get(r.Context(), user.ID, seriesTmdbId)
	if err != nil {
		writeError(w, http.StatusUnprocessableEntity, err)
		return
	}

	progress, err := c.progress.MarkSeries(r.Context(), user.ID, params.ToInput(seriesTmdbId))
	if err != nil {
		writeError(w, http.StatusUnprocessableEntity, err)
		return
	}

	// only a mark that changes the watched episodes writes Jellyfin (a repeated mark sends nothing)
	if !slices.Equal(slices.Sorted(slices.Values(before.WatchedEpisodes)), slices.Sorted(slices.Values(progress.WatchedEpisodes))) {
		c.library.SetPlayed(r.Context(), user.ID, services.PlayedTarget{Kind: services.PlayedSeries, TmdbId: seriesTmdbId, Played: true})
	}

	writeProgress(w, progress)
}

func (c *seriesController) HandleUnmarkSeriesWatched(w http.ResponseWriter, r *http.Request) {
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

	// the progress before the mark tells whether it changes what Jellyfin holds
	before, err := c.progress.Get(r.Context(), user.ID, seriesTmdbId)
	if err != nil {
		writeError(w, http.StatusUnprocessableEntity, err)
		return
	}

	progress, err := c.progress.UnmarkSeries(r.Context(), user.ID, seriesTmdbId)
	if err != nil {
		writeError(w, http.StatusUnprocessableEntity, err)
		return
	}

	// only a mark that changes the watched episodes writes Jellyfin (a repeated mark sends nothing)
	if !slices.Equal(slices.Sorted(slices.Values(before.WatchedEpisodes)), slices.Sorted(slices.Values(progress.WatchedEpisodes))) {
		c.library.SetPlayed(r.Context(), user.ID, services.PlayedTarget{Kind: services.PlayedSeries, TmdbId: seriesTmdbId, Played: false})
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

	// the progress before the mark tells whether it changes what Jellyfin holds
	before, err := c.progress.Get(r.Context(), user.ID, seriesTmdbId)
	if err != nil {
		writeError(w, http.StatusUnprocessableEntity, err)
		return
	}

	progress, err := c.progress.MarkSeason(r.Context(), user.ID, series, season)
	if err != nil {
		writeError(w, http.StatusUnprocessableEntity, err)
		return
	}

	// only a mark that changes the watched episodes writes Jellyfin (a repeated mark sends nothing)
	if !slices.Equal(slices.Sorted(slices.Values(before.WatchedEpisodes)), slices.Sorted(slices.Values(progress.WatchedEpisodes))) {
		c.library.SetPlayed(r.Context(), user.ID, services.PlayedTarget{Kind: services.PlayedSeason, TmdbId: seriesTmdbId, SeasonId: seasonTmdbId, Played: true})
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

	// the progress before the mark tells whether it changes what Jellyfin holds
	before, err := c.progress.Get(r.Context(), user.ID, seriesTmdbId)
	if err != nil {
		writeError(w, http.StatusUnprocessableEntity, err)
		return
	}

	progress, err := c.progress.UnmarkSeason(r.Context(), user.ID, seriesTmdbId, seasonTmdbId)
	if err != nil {
		writeError(w, http.StatusUnprocessableEntity, err)
		return
	}

	// only a mark that changes the watched episodes writes Jellyfin (a repeated mark sends nothing)
	if !slices.Equal(slices.Sorted(slices.Values(before.WatchedEpisodes)), slices.Sorted(slices.Values(progress.WatchedEpisodes))) {
		c.library.SetPlayed(r.Context(), user.ID, services.PlayedTarget{Kind: services.PlayedSeason, TmdbId: seriesTmdbId, SeasonId: seasonTmdbId, Played: false})
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

	// the progress before the mark tells whether it changes what Jellyfin holds
	before, err := c.progress.Get(r.Context(), user.ID, seriesTmdbId)
	if err != nil {
		writeError(w, http.StatusUnprocessableEntity, err)
		return
	}

	progress, err := c.progress.MarkEpisode(r.Context(), user.ID, series, season, episode)
	if err != nil {
		writeError(w, http.StatusUnprocessableEntity, err)
		return
	}

	// only a mark that changes the watched episodes writes Jellyfin (a repeated mark sends nothing)
	if !slices.Equal(slices.Sorted(slices.Values(before.WatchedEpisodes)), slices.Sorted(slices.Values(progress.WatchedEpisodes))) {
		c.library.SetPlayed(r.Context(), user.ID, services.PlayedTarget{Kind: services.PlayedEpisode, TmdbId: seriesTmdbId, SeasonId: seasonTmdbId, EpisodeId: episodeTmdbId, Played: true})
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

	// the progress before the mark tells whether it changes what Jellyfin holds
	before, err := c.progress.Get(r.Context(), user.ID, seriesTmdbId)
	if err != nil {
		writeError(w, http.StatusUnprocessableEntity, err)
		return
	}

	progress, err := c.progress.UnmarkEpisode(r.Context(), user.ID, seriesTmdbId, seasonTmdbId, episodeTmdbId)
	if err != nil {
		writeError(w, http.StatusUnprocessableEntity, err)
		return
	}

	// only a mark that changes the watched episodes writes Jellyfin (a repeated mark sends nothing)
	if !slices.Equal(slices.Sorted(slices.Values(before.WatchedEpisodes)), slices.Sorted(slices.Values(progress.WatchedEpisodes))) {
		c.library.SetPlayed(r.Context(), user.ID, services.PlayedTarget{Kind: services.PlayedEpisode, TmdbId: seriesTmdbId, SeasonId: seasonTmdbId, EpisodeId: episodeTmdbId, Played: false})
	}

	writeProgress(w, progress)
}

// parseTmdbParam reads a uint64 TMDB id from a chi URL parameter
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
