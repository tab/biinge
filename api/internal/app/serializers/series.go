package serializers

import (
	"encoding/json"
	"io"
	"strings"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/models"
)

type SeriesSerializer struct {
	Id                   uint64 `json:"id"`
	Title                string `json:"title"`
	PosterPath           string `json:"posterPath"`
	Pinned               bool   `json:"pinned"`
	State                string `json:"state"`
	EpisodesCount        uint64 `json:"episodesCount"`
	WatchedEpisodesCount uint64 `json:"watchedEpisodesCount"`
}

type SeriesDetailsSerializer struct {
	Id              uint64                     `json:"id"`
	ImdbId          string                     `json:"imdbId,omitempty"`
	Title           string                     `json:"title"`
	PosterPath      string                     `json:"posterPath"`
	Pinned          bool                       `json:"pinned"`
	State           string                     `json:"state"`
	Overview        string                     `json:"overview"`
	Status          string                     `json:"status,omitempty"`
	ReleaseDate     string                     `json:"releaseDate,omitempty"`
	SeasonsCount    uint64                     `json:"seasonsCount,omitempty"`
	EpisodesCount   uint64                     `json:"episodesCount,omitempty"`
	Rating          float64                    `json:"rating,omitempty"`
	Credits         []PersonSerializer         `json:"credits"`
	Recommendations []RecommendationSerializer `json:"recommendations"`
	Videos          []VideoSerializer          `json:"videos"`
	Seasons         []SeasonSummarySerializer  `json:"seasons"`
}

type CreateSeriesRequestSerializer struct {
	Id            uint64 `json:"id" validate:"required"`
	Title         string `json:"title" validate:"required"`
	PosterPath    string `json:"posterPath"`
	SeasonsCount  uint64 `json:"seasonsCount" validate:"omitempty,min=0"`
	EpisodesCount uint64 `json:"episodesCount" validate:"omitempty,min=0"`
	Status        string `json:"status"`
	State         string `json:"state" validate:"omitempty,oneof=want watching watched"`
}

func (params *CreateSeriesRequestSerializer) Validate(body io.Reader) error {
	if err := json.NewDecoder(body).Decode(params); err != nil {
		return err
	}

	params.Title = strings.TrimSpace(params.Title)
	if params.Title == "" {
		return errors.ErrEmptyTitle
	}

	params.PosterPath = strings.TrimSpace(params.PosterPath)

	params.State = strings.TrimSpace(params.State)
	switch params.State {
	case models.StateTypeWant, models.StateTypeWatching, models.StateTypeWatched:
	case "":
		return errors.ErrEmptyState
	default:
		return errors.ErrInvalidState
	}

	return nil
}

type UpdateSeriesRequestSerializer struct {
	State  string `json:"state" validate:"omitempty,oneof=want watching watched"`
	Pinned bool   `json:"pinned"`
}

func (params *UpdateSeriesRequestSerializer) Validate(body io.Reader) error {
	if err := json.NewDecoder(body).Decode(params); err != nil {
		return err
	}

	params.State = strings.TrimSpace(params.State)
	switch params.State {
	case models.StateTypeWant, models.StateTypeWatching, models.StateTypeWatched:
	case "":
		return errors.ErrEmptyState
	default:
		return errors.ErrInvalidState
	}

	return nil
}
