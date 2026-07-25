package serializers

import (
	"encoding/json"
	"io"
	"strings"
	"time"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/models"
)

// tmdbDateLayout is the date format TMDB uses for air dates
const tmdbDateLayout = "2006-01-02"

// ProgressSeriesSerializer carries the show-level metadata persisted while recording progress
type ProgressSeriesSerializer struct {
	Title         string `json:"title"`
	PosterPath    string `json:"posterPath"`
	SeasonsCount  uint64 `json:"seasonsCount"`
	EpisodesCount uint64 `json:"episodesCount"`
	Status        string `json:"status"`
}

func (s ProgressSeriesSerializer) toInput(tmdbId uint64) models.SeriesInput {
	return models.SeriesInput{
		TmdbId:        tmdbId,
		Title:         strings.TrimSpace(s.Title),
		PosterPath:    s.PosterPath,
		SeasonsCount:  s.SeasonsCount,
		EpisodesCount: s.EpisodesCount,
		Status:        s.Status,
	}
}

// ProgressEpisodeSerializer is an episode with its own TMDB id, used inside season and show payloads
type ProgressEpisodeSerializer struct {
	Id         uint64 `json:"id"`
	Title      string `json:"title"`
	PosterPath string `json:"posterPath"`
	Runtime    uint64 `json:"runtime"`
	AirDate    string `json:"airDate"`
}

func (e ProgressEpisodeSerializer) toInput() models.EpisodeInput {
	return models.EpisodeInput{
		TmdbId:     e.Id,
		Title:      strings.TrimSpace(e.Title),
		PosterPath: e.PosterPath,
		Runtime:    e.Runtime,
		AirAt:      parseAirDate(e.AirDate),
	}
}

// ProgressSeasonSerializer is a season with its own TMDB id and episodes, used inside a show payload
type ProgressSeasonSerializer struct {
	Id            uint64                      `json:"id"`
	Title         string                      `json:"title"`
	Number        uint64                      `json:"number"`
	EpisodesCount uint64                      `json:"episodesCount"`
	Episodes      []ProgressEpisodeSerializer `json:"episodes"`
}

func (s ProgressSeasonSerializer) toInput() models.SeasonInput {
	return models.SeasonInput{
		TmdbId:        s.Id,
		Title:         strings.TrimSpace(s.Title),
		Number:        s.Number,
		EpisodesCount: s.EpisodesCount,
		Episodes:      episodeInputs(s.Episodes),
	}
}

// ProgressSeasonMetaSerializer is a season without its id (taken from the URL)
type ProgressSeasonMetaSerializer struct {
	Title         string `json:"title"`
	Number        uint64 `json:"number"`
	EpisodesCount uint64 `json:"episodesCount"`
}

func (s ProgressSeasonMetaSerializer) toInput(tmdbId uint64, episodes []ProgressEpisodeSerializer) models.SeasonInput {
	return models.SeasonInput{
		TmdbId:        tmdbId,
		Title:         strings.TrimSpace(s.Title),
		Number:        s.Number,
		EpisodesCount: s.EpisodesCount,
		Episodes:      episodeInputs(episodes),
	}
}

// ProgressEpisodeMetaSerializer is an episode without its id (taken from the URL)
type ProgressEpisodeMetaSerializer struct {
	Title      string `json:"title"`
	PosterPath string `json:"posterPath"`
	Runtime    uint64 `json:"runtime"`
	AirDate    string `json:"airDate"`
}

func (e ProgressEpisodeMetaSerializer) toInput(tmdbId uint64) models.EpisodeInput {
	return models.EpisodeInput{
		TmdbId:     tmdbId,
		Title:      strings.TrimSpace(e.Title),
		PosterPath: e.PosterPath,
		Runtime:    e.Runtime,
		AirAt:      parseAirDate(e.AirDate),
	}
}

// MarkShowRequestSerializer is the payload for marking a whole show watched
type MarkShowRequestSerializer struct {
	Series  ProgressSeriesSerializer   `json:"series"`
	Seasons []ProgressSeasonSerializer `json:"seasons"`
}

func (params *MarkShowRequestSerializer) Validate(body io.Reader) error {
	if err := json.NewDecoder(body).Decode(params); err != nil {
		return err
	}

	if strings.TrimSpace(params.Series.Title) == "" {
		return errors.ErrEmptyTitle
	}

	return nil
}

func (params *MarkShowRequestSerializer) ToInput(seriesTmdbId uint64) models.ShowInput {
	seasons := make([]models.SeasonInput, 0, len(params.Seasons))
	for _, season := range params.Seasons {
		seasons = append(seasons, season.toInput())
	}

	return models.ShowInput{
		Series:  params.Series.toInput(seriesTmdbId),
		Seasons: seasons,
	}
}

// MarkSeasonRequestSerializer is the payload for marking a whole season watched
type MarkSeasonRequestSerializer struct {
	Series   ProgressSeriesSerializer     `json:"series"`
	Season   ProgressSeasonMetaSerializer `json:"season"`
	Episodes []ProgressEpisodeSerializer  `json:"episodes"`
}

func (params *MarkSeasonRequestSerializer) Validate(body io.Reader) error {
	if err := json.NewDecoder(body).Decode(params); err != nil {
		return err
	}

	if strings.TrimSpace(params.Series.Title) == "" {
		return errors.ErrEmptyTitle
	}

	return nil
}

func (params *MarkSeasonRequestSerializer) ToInputs(seriesTmdbId, seasonTmdbId uint64) (models.SeriesInput, models.SeasonInput) {
	return params.Series.toInput(seriesTmdbId), params.Season.toInput(seasonTmdbId, params.Episodes)
}

// MarkEpisodeRequestSerializer is the payload for marking a single episode watched
type MarkEpisodeRequestSerializer struct {
	Series  ProgressSeriesSerializer      `json:"series"`
	Season  ProgressSeasonMetaSerializer  `json:"season"`
	Episode ProgressEpisodeMetaSerializer `json:"episode"`
}

func (params *MarkEpisodeRequestSerializer) Validate(body io.Reader) error {
	if err := json.NewDecoder(body).Decode(params); err != nil {
		return err
	}

	if strings.TrimSpace(params.Series.Title) == "" {
		return errors.ErrEmptyTitle
	}

	return nil
}

func (params *MarkEpisodeRequestSerializer) ToInputs(seriesTmdbId, seasonTmdbId, episodeTmdbId uint64) (models.SeriesInput, models.SeasonInput, models.EpisodeInput) {
	return params.Series.toInput(seriesTmdbId),
		params.Season.toInput(seasonTmdbId, nil),
		params.Episode.toInput(episodeTmdbId)
}

// ProgressResponseSerializer is the watched-progress snapshot returned by the progress endpoints
type ProgressResponseSerializer struct {
	Id              uint64           `json:"id"`
	State           models.StateType `json:"state"`
	TrackedState    models.StateType `json:"trackedState,omitempty"`
	WatchedSeasons  []uint64         `json:"watchedSeasons"`
	WatchedEpisodes []uint64         `json:"watchedEpisodes"`
}

func NewProgressResponse(progress *models.SeriesProgress) ProgressResponseSerializer {
	seasons := progress.WatchedSeasons
	if seasons == nil {
		seasons = []uint64{}
	}

	episodes := progress.WatchedEpisodes
	if episodes == nil {
		episodes = []uint64{}
	}

	return ProgressResponseSerializer{
		Id:              progress.SeriesTmdbId,
		State:           progress.State,
		TrackedState:    progress.TrackedState,
		WatchedSeasons:  seasons,
		WatchedEpisodes: episodes,
	}
}

func episodeInputs(episodes []ProgressEpisodeSerializer) []models.EpisodeInput {
	result := make([]models.EpisodeInput, 0, len(episodes))
	for _, episode := range episodes {
		result = append(result, episode.toInput())
	}

	return result
}

// parseAirDate parses a TMDB air date, zero time (SQL NULL) for empty or malformed values
func parseAirDate(value string) time.Time {
	value = strings.TrimSpace(value)
	if value == "" {
		return time.Time{}
	}

	parsed, err := time.Parse(tmdbDateLayout, value)
	if err != nil {
		return time.Time{}
	}

	return parsed
}
