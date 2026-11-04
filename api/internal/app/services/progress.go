package services

import (
	"context"

	"github.com/google/uuid"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories"
	"biinge-api/internal/config/logger"
)

// Progress orchestrates the cascading watched-state changes for a show
type Progress interface {
	MarkSeries(ctx context.Context, userId uuid.UUID, input models.MarkSeriesInput) (*models.SeriesProgress, error)
	UnmarkSeries(ctx context.Context, userId uuid.UUID, seriesTmdbId uint64) (*models.SeriesProgress, error)
	MarkSeason(ctx context.Context, userId uuid.UUID, series models.SeriesInput, season models.SeasonInput) (*models.SeriesProgress, error)
	UnmarkSeason(ctx context.Context, userId uuid.UUID, seriesTmdbId, seasonTmdbId uint64) (*models.SeriesProgress, error)
	MarkEpisode(ctx context.Context, userId uuid.UUID, series models.SeriesInput, season models.SeasonInput, episode models.EpisodeInput) (*models.SeriesProgress, error)
	UnmarkEpisode(ctx context.Context, userId uuid.UUID, seriesTmdbId, seasonTmdbId, episodeTmdbId uint64) (*models.SeriesProgress, error)
	Get(ctx context.Context, userId uuid.UUID, seriesTmdbId uint64) (*models.SeriesProgress, error)
}

type progress struct {
	repository repositories.SeriesProgressRepository
	stats      StatsCache
	log        *logger.Logger
}

func NewProgress(repository repositories.SeriesProgressRepository, stats StatsCache, log *logger.Logger) Progress {
	return &progress{
		repository: repository,
		stats:      stats,
		log:        log.WithComponent("ProgressService"),
	}
}

func (p *progress) MarkSeries(ctx context.Context, userId uuid.UUID, input models.MarkSeriesInput) (*models.SeriesProgress, error) {
	result, err := p.repository.MarkSeriesWatched(ctx, userId, input)
	if err != nil {
		p.log.Error().Err(err).Msg("Failed to mark series watched")
		return nil, errors.ErrFailedToUpdateProgress
	}

	p.stats.Invalidate(ctx, userId)

	return result, nil
}

func (p *progress) UnmarkSeries(ctx context.Context, userId uuid.UUID, seriesTmdbId uint64) (*models.SeriesProgress, error) {
	result, err := p.repository.UnmarkSeriesWatched(ctx, userId, seriesTmdbId)
	if err != nil {
		p.log.Error().Err(err).Msg("Failed to unmark series watched")
		return nil, errors.ErrFailedToUpdateProgress
	}

	p.stats.Invalidate(ctx, userId)

	return result, nil
}

func (p *progress) MarkSeason(ctx context.Context, userId uuid.UUID, series models.SeriesInput, season models.SeasonInput) (*models.SeriesProgress, error) {
	result, err := p.repository.MarkSeasonWatched(ctx, userId, series, season)
	if err != nil {
		p.log.Error().Err(err).Msg("Failed to mark season watched")
		return nil, errors.ErrFailedToUpdateProgress
	}

	p.stats.Invalidate(ctx, userId)

	return result, nil
}

func (p *progress) UnmarkSeason(ctx context.Context, userId uuid.UUID, seriesTmdbId, seasonTmdbId uint64) (*models.SeriesProgress, error) {
	result, err := p.repository.UnmarkSeasonWatched(ctx, userId, seriesTmdbId, seasonTmdbId)
	if err != nil {
		p.log.Error().Err(err).Msg("Failed to unmark season watched")
		return nil, errors.ErrFailedToUpdateProgress
	}

	p.stats.Invalidate(ctx, userId)

	return result, nil
}

func (p *progress) MarkEpisode(ctx context.Context, userId uuid.UUID, series models.SeriesInput, season models.SeasonInput, episode models.EpisodeInput) (*models.SeriesProgress, error) {
	result, err := p.repository.MarkEpisodeWatched(ctx, userId, series, season, episode)
	if err != nil {
		p.log.Error().Err(err).Msg("Failed to mark episode watched")
		return nil, errors.ErrFailedToUpdateProgress
	}

	p.stats.Invalidate(ctx, userId)

	return result, nil
}

func (p *progress) UnmarkEpisode(ctx context.Context, userId uuid.UUID, seriesTmdbId, seasonTmdbId, episodeTmdbId uint64) (*models.SeriesProgress, error) {
	result, err := p.repository.UnmarkEpisodeWatched(ctx, userId, seriesTmdbId, seasonTmdbId, episodeTmdbId)
	if err != nil {
		p.log.Error().Err(err).Msg("Failed to unmark episode watched")
		return nil, errors.ErrFailedToUpdateProgress
	}

	p.stats.Invalidate(ctx, userId)

	return result, nil
}

func (p *progress) Get(ctx context.Context, userId uuid.UUID, seriesTmdbId uint64) (*models.SeriesProgress, error) {
	result, err := p.repository.Progress(ctx, userId, seriesTmdbId)
	if err != nil {
		p.log.Error().Err(err).Msg("Failed to fetch progress")
		return nil, errors.ErrFailedToFetchProgress
	}

	return result, nil
}
