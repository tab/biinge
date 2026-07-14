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
	MarkShow(ctx context.Context, userId uuid.UUID, show models.ShowInput) (*models.SeriesProgress, error)
	UnmarkShow(ctx context.Context, userId uuid.UUID, seriesTmdbId uint64) (*models.SeriesProgress, error)
	MarkSeason(ctx context.Context, userId uuid.UUID, series models.SeriesInput, season models.SeasonInput) (*models.SeriesProgress, error)
	UnmarkSeason(ctx context.Context, userId uuid.UUID, seriesTmdbId, seasonTmdbId uint64) (*models.SeriesProgress, error)
	MarkEpisode(ctx context.Context, userId uuid.UUID, series models.SeriesInput, season models.SeasonInput, episode models.EpisodeInput) (*models.SeriesProgress, error)
	UnmarkEpisode(ctx context.Context, userId uuid.UUID, seriesTmdbId, seasonTmdbId, episodeTmdbId uint64) (*models.SeriesProgress, error)
	Get(ctx context.Context, userId uuid.UUID, seriesTmdbId uint64) (*models.SeriesProgress, error)
}

type progress struct {
	repository repositories.SeriesProgressRepository
	log        *logger.Logger
}

func NewProgress(repository repositories.SeriesProgressRepository, log *logger.Logger) Progress {
	return &progress{
		repository: repository,
		log:        log.WithComponent("ProgressService"),
	}
}

func (p *progress) MarkShow(ctx context.Context, userId uuid.UUID, show models.ShowInput) (*models.SeriesProgress, error) {
	result, err := p.repository.MarkShowWatched(ctx, userId, show)
	if err != nil {
		p.log.Error().Err(err).Msg("Failed to mark show watched")
		return nil, errors.ErrFailedToUpdateProgress
	}

	return result, nil
}

func (p *progress) UnmarkShow(ctx context.Context, userId uuid.UUID, seriesTmdbId uint64) (*models.SeriesProgress, error) {
	result, err := p.repository.UnmarkShowWatched(ctx, userId, seriesTmdbId)
	if err != nil {
		p.log.Error().Err(err).Msg("Failed to unmark show watched")
		return nil, errors.ErrFailedToUpdateProgress
	}

	return result, nil
}

func (p *progress) MarkSeason(ctx context.Context, userId uuid.UUID, series models.SeriesInput, season models.SeasonInput) (*models.SeriesProgress, error) {
	result, err := p.repository.MarkSeasonWatched(ctx, userId, series, season)
	if err != nil {
		p.log.Error().Err(err).Msg("Failed to mark season watched")
		return nil, errors.ErrFailedToUpdateProgress
	}

	return result, nil
}

func (p *progress) UnmarkSeason(ctx context.Context, userId uuid.UUID, seriesTmdbId, seasonTmdbId uint64) (*models.SeriesProgress, error) {
	result, err := p.repository.UnmarkSeasonWatched(ctx, userId, seriesTmdbId, seasonTmdbId)
	if err != nil {
		p.log.Error().Err(err).Msg("Failed to unmark season watched")
		return nil, errors.ErrFailedToUpdateProgress
	}

	return result, nil
}

func (p *progress) MarkEpisode(ctx context.Context, userId uuid.UUID, series models.SeriesInput, season models.SeasonInput, episode models.EpisodeInput) (*models.SeriesProgress, error) {
	result, err := p.repository.MarkEpisodeWatched(ctx, userId, series, season, episode)
	if err != nil {
		p.log.Error().Err(err).Msg("Failed to mark episode watched")
		return nil, errors.ErrFailedToUpdateProgress
	}

	return result, nil
}

func (p *progress) UnmarkEpisode(ctx context.Context, userId uuid.UUID, seriesTmdbId, seasonTmdbId, episodeTmdbId uint64) (*models.SeriesProgress, error) {
	result, err := p.repository.UnmarkEpisodeWatched(ctx, userId, seriesTmdbId, seasonTmdbId, episodeTmdbId)
	if err != nil {
		p.log.Error().Err(err).Msg("Failed to unmark episode watched")
		return nil, errors.ErrFailedToUpdateProgress
	}

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
