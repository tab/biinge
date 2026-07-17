package repositories

import (
	"context"
	"errors"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"

	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories/db"
	"biinge-api/internal/app/repositories/postgres"
)

// SeriesProgressRepository keeps a show's series/season/episode rows and their derived watched state consistent
type SeriesProgressRepository interface {
	MarkShowWatched(ctx context.Context, userId uuid.UUID, show models.ShowInput) (*models.SeriesProgress, error)
	UnmarkShowWatched(ctx context.Context, userId uuid.UUID, seriesTmdbId uint64) (*models.SeriesProgress, error)
	MarkSeasonWatched(ctx context.Context, userId uuid.UUID, series models.SeriesInput, season models.SeasonInput) (*models.SeriesProgress, error)
	UnmarkSeasonWatched(ctx context.Context, userId uuid.UUID, seriesTmdbId, seasonTmdbId uint64) (*models.SeriesProgress, error)
	MarkEpisodeWatched(ctx context.Context, userId uuid.UUID, series models.SeriesInput, season models.SeasonInput, episode models.EpisodeInput) (*models.SeriesProgress, error)
	UnmarkEpisodeWatched(ctx context.Context, userId uuid.UUID, seriesTmdbId, seasonTmdbId, episodeTmdbId uint64) (*models.SeriesProgress, error)
	Progress(ctx context.Context, userId uuid.UUID, seriesTmdbId uint64) (*models.SeriesProgress, error)
}

type seriesProgress struct {
	client postgres.Postgres
}

func NewSeriesProgressRepository(client postgres.Postgres) SeriesProgressRepository {
	return &seriesProgress{client: client}
}

// withTx runs fn inside a database transaction, rolling back on error
func (r *seriesProgress) withTx(ctx context.Context, fn func(q *db.Queries) error) error {
	tx, err := r.client.Db().Begin(ctx)
	if err != nil {
		return err
	}

	defer func() { _ = tx.Rollback(ctx) }()

	if err = fn(r.client.Queries().WithTx(tx)); err != nil {
		return err
	}

	return tx.Commit(ctx)
}

func (r *seriesProgress) MarkShowWatched(ctx context.Context, userId uuid.UUID, show models.ShowInput) (*models.SeriesProgress, error) {
	var progress *models.SeriesProgress

	err := r.withTx(ctx, func(q *db.Queries) error {
		series, err := upsertSeries(ctx, q, userId, show.Series)
		if err != nil {
			return err
		}

		for _, season := range show.Seasons {
			if err = markSeason(ctx, q, series.ID, season); err != nil {
				return err
			}
		}

		if err = recomputeSeries(ctx, q, series); err != nil {
			return err
		}

		progress, err = buildProgress(ctx, q, userId, show.Series.TmdbId)

		return err
	})

	return progress, err
}

func (r *seriesProgress) MarkSeasonWatched(ctx context.Context, userId uuid.UUID, series models.SeriesInput, season models.SeasonInput) (*models.SeriesProgress, error) {
	var progress *models.SeriesProgress

	err := r.withTx(ctx, func(q *db.Queries) error {
		row, err := upsertSeries(ctx, q, userId, series)
		if err != nil {
			return err
		}

		if err = markSeason(ctx, q, row.ID, season); err != nil {
			return err
		}

		if err = recomputeSeries(ctx, q, row); err != nil {
			return err
		}

		progress, err = buildProgress(ctx, q, userId, series.TmdbId)

		return err
	})

	return progress, err
}

func (r *seriesProgress) MarkEpisodeWatched(ctx context.Context, userId uuid.UUID, series models.SeriesInput, season models.SeasonInput, episode models.EpisodeInput) (*models.SeriesProgress, error) {
	var progress *models.SeriesProgress

	err := r.withTx(ctx, func(q *db.Queries) error {
		seriesRow, err := upsertSeries(ctx, q, userId, series)
		if err != nil {
			return err
		}

		seasonRow, err := upsertSeason(ctx, q, seriesRow.ID, season)
		if err != nil {
			return err
		}

		if _, err = upsertEpisode(ctx, q, seasonRow.ID, episode, models.StateTypeWatched); err != nil {
			return err
		}

		if err = recomputeSeason(ctx, q, seasonRow.ID, season.EpisodesCount); err != nil {
			return err
		}

		if err = recomputeSeries(ctx, q, seriesRow); err != nil {
			return err
		}

		progress, err = buildProgress(ctx, q, userId, series.TmdbId)

		return err
	})

	return progress, err
}

func (r *seriesProgress) UnmarkShowWatched(ctx context.Context, userId uuid.UUID, seriesTmdbId uint64) (*models.SeriesProgress, error) {
	var progress *models.SeriesProgress

	err := r.withTx(ctx, func(q *db.Queries) error {
		series, err := q.FindSeriesByTmdbId(ctx, db.FindSeriesByTmdbIdParams{TmdbID: seriesTmdbId, UserID: userId})
		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				progress = &models.SeriesProgress{SeriesTmdbId: seriesTmdbId, State: models.StateTypeNone}
				return nil
			}

			return err
		}

		if err = q.DeleteSeasonsBySeriesId(ctx, series.ID); err != nil {
			return err
		}

		if err = recomputeSeries(ctx, q, series); err != nil {
			return err
		}

		progress, err = buildProgress(ctx, q, userId, seriesTmdbId)

		return err
	})

	return progress, err
}

func (r *seriesProgress) UnmarkSeasonWatched(ctx context.Context, userId uuid.UUID, seriesTmdbId, seasonTmdbId uint64) (*models.SeriesProgress, error) {
	var progress *models.SeriesProgress

	err := r.withTx(ctx, func(q *db.Queries) error {
		series, err := q.FindSeriesByTmdbId(ctx, db.FindSeriesByTmdbIdParams{TmdbID: seriesTmdbId, UserID: userId})
		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				progress = &models.SeriesProgress{SeriesTmdbId: seriesTmdbId, State: models.StateTypeNone}
				return nil
			}

			return err
		}

		season, err := q.FindSeasonBySeriesAndTmdbId(ctx, db.FindSeasonBySeriesAndTmdbIdParams{SeriesID: series.ID, TmdbID: seasonTmdbId})
		if err != nil && !errors.Is(err, pgx.ErrNoRows) {
			return err
		}

		if err == nil {
			if err = q.DeleteSeason(ctx, season.ID); err != nil {
				return err
			}
		}

		if err = recomputeSeries(ctx, q, series); err != nil {
			return err
		}

		progress, err = buildProgress(ctx, q, userId, seriesTmdbId)

		return err
	})

	return progress, err
}

func (r *seriesProgress) UnmarkEpisodeWatched(ctx context.Context, userId uuid.UUID, seriesTmdbId, seasonTmdbId, episodeTmdbId uint64) (*models.SeriesProgress, error) {
	var progress *models.SeriesProgress

	err := r.withTx(ctx, func(q *db.Queries) error {
		series, err := q.FindSeriesByTmdbId(ctx, db.FindSeriesByTmdbIdParams{TmdbID: seriesTmdbId, UserID: userId})
		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				progress = &models.SeriesProgress{SeriesTmdbId: seriesTmdbId, State: models.StateTypeNone}
				return nil
			}

			return err
		}

		season, err := q.FindSeasonBySeriesAndTmdbId(ctx, db.FindSeasonBySeriesAndTmdbIdParams{SeriesID: series.ID, TmdbID: seasonTmdbId})
		if err != nil {
			if errors.Is(err, pgx.ErrNoRows) {
				progress, err = buildProgress(ctx, q, userId, seriesTmdbId)
				return err
			}

			return err
		}

		if err = q.DeleteEpisodeBySeasonAndTmdbId(ctx, db.DeleteEpisodeBySeasonAndTmdbIdParams{SeasonID: season.ID, TmdbID: episodeTmdbId}); err != nil {
			return err
		}

		if err = recomputeSeason(ctx, q, season.ID, season.EpisodesCount); err != nil {
			return err
		}

		if err = recomputeSeries(ctx, q, series); err != nil {
			return err
		}

		progress, err = buildProgress(ctx, q, userId, seriesTmdbId)

		return err
	})

	return progress, err
}

func (r *seriesProgress) Progress(ctx context.Context, userId uuid.UUID, seriesTmdbId uint64) (*models.SeriesProgress, error) {
	return buildProgress(ctx, r.client.Queries(), userId, seriesTmdbId)
}

// upsertSeries inserts or updates the series row and returns it
func upsertSeries(ctx context.Context, q *db.Queries, userId uuid.UUID, input models.SeriesInput) (db.Series, error) {
	return q.UpsertSeries(ctx, db.UpsertSeriesParams{
		UserID:        userId,
		TmdbID:        input.TmdbId,
		Title:         input.Title,
		PosterPath:    input.PosterPath,
		SeasonsCount:  input.SeasonsCount,
		EpisodesCount: input.EpisodesCount,
		Status:        input.Status,
		State:         db.StateTypes(models.StateTypeWatching),
	})
}

// upsertSeason inserts or updates the season row and returns it
func upsertSeason(ctx context.Context, q *db.Queries, seriesID uuid.UUID, input models.SeasonInput) (db.Season, error) {
	return q.UpsertSeason(ctx, db.UpsertSeasonParams{
		SeriesID:      seriesID,
		TmdbID:        input.TmdbId,
		Title:         input.Title,
		Number:        input.Number,
		EpisodesCount: input.EpisodesCount,
		State:         db.StateTypes(models.StateTypeNone),
	})
}

// upsertEpisode inserts or updates an episode row in the given state
func upsertEpisode(ctx context.Context, q *db.Queries, seasonID uuid.UUID, input models.EpisodeInput, state string) (db.Episode, error) {
	return q.UpsertEpisode(ctx, db.UpsertEpisodeParams{
		SeasonID:   seasonID,
		TmdbID:     input.TmdbId,
		Title:      input.Title,
		PosterPath: input.PosterPath,
		Runtime:    input.Runtime,
		State:      db.StateTypes(state),
		AirAt:      timestampFromTime(input.AirAt),
	})
}

// markSeason upserts a season with all provided episodes watched and sets the season state to watched
func markSeason(ctx context.Context, q *db.Queries, seriesID uuid.UUID, season models.SeasonInput) error {
	row, err := upsertSeason(ctx, q, seriesID, season)
	if err != nil {
		return err
	}

	for _, episode := range season.Episodes {
		if _, err = upsertEpisode(ctx, q, row.ID, episode, models.StateTypeWatched); err != nil {
			return err
		}
	}

	return q.SetSeasonState(ctx, db.SetSeasonStateParams{ID: row.ID, State: db.StateTypes(models.StateTypeWatched)})
}

// recomputeSeason derives a season's state from its watched-episode count, deleting the row once empty
func recomputeSeason(ctx context.Context, q *db.Queries, seasonID uuid.UUID, episodesCount uint64) error {
	count, err := q.CountEpisodesBySeason(ctx, seasonID)
	if err != nil {
		return err
	}

	if count == 0 {
		return q.DeleteSeason(ctx, seasonID)
	}

	state := models.StateTypeNone
	if episodesCount > 0 && uint64(count) >= episodesCount {
		state = models.StateTypeWatched
	}

	return q.SetSeasonState(ctx, db.SetSeasonStateParams{ID: seasonID, State: db.StateTypes(state)})
}

// recomputeSeries derives a series' state from its watched episodes and seasons
func recomputeSeries(ctx context.Context, q *db.Queries, series db.Series) error {
	episodes, err := q.CountEpisodesBySeriesId(ctx, series.ID)
	if err != nil {
		return err
	}

	seasons, err := q.CountWatchedSeasonsBySeriesId(ctx, series.ID)
	if err != nil {
		return err
	}

	state := deriveSeriesState(uint64(episodes), uint64(seasons), series.SeasonsCount, series.Status)
	if state == models.StateTypeNone {
		// an explicitly tracked show reverts to the user's choice; auto-tracked rows are deleted
		if series.TrackedState.Valid {
			return q.SetSeriesState(ctx, db.SetSeriesStateParams{ID: series.ID, State: series.TrackedState.StateTypes})
		}

		return q.DeleteSeries(ctx, series.ID)
	}

	return q.SetSeriesState(ctx, db.SetSeriesStateParams{ID: series.ID, State: db.StateTypes(state)})
}

// deriveSeriesState maps watched progress and show status to none/watching/watched
// a finished show becomes watched once every regular season is watched, rather than
// comparing raw episode counts, whose show-level TMDB total often drifts from the seasons
func deriveSeriesState(watchedEpisodes, watchedSeasons, totalSeasons uint64, status string) string {
	if watchedEpisodes == 0 {
		return models.StateTypeNone
	}

	if totalSeasons > 0 && watchedSeasons >= totalSeasons && status != models.TvInProductionStatus {
		return models.StateTypeWatched
	}

	return models.StateTypeWatching
}

// buildProgress reads the current watched state for a show (none-state when untracked)
func buildProgress(ctx context.Context, q *db.Queries, userId uuid.UUID, seriesTmdbId uint64) (*models.SeriesProgress, error) {
	series, err := q.FindSeriesByTmdbId(ctx, db.FindSeriesByTmdbIdParams{TmdbID: seriesTmdbId, UserID: userId})
	if err != nil {
		if errors.Is(err, pgx.ErrNoRows) {
			return &models.SeriesProgress{SeriesTmdbId: seriesTmdbId, State: models.StateTypeNone}, nil
		}

		return nil, err
	}

	seasons, err := q.FindWatchedSeasonTmdbIdsBySeriesId(ctx, series.ID)
	if err != nil {
		return nil, err
	}

	episodes, err := q.FindEpisodeTmdbIdsBySeriesId(ctx, series.ID)
	if err != nil {
		return nil, err
	}

	trackedState := ""
	if series.TrackedState.Valid {
		trackedState = string(series.TrackedState.StateTypes)
	}

	return &models.SeriesProgress{
		SeriesTmdbId:    seriesTmdbId,
		State:           string(series.State),
		TrackedState:    trackedState,
		WatchedSeasons:  seasons,
		WatchedEpisodes: episodes,
	}, nil
}
