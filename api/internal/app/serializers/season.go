package serializers

import (
	"encoding/json"
	"io"
	"strings"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/models"
)

type SeasonSerializer struct {
	Id            uint64 `json:"id"`
	Number        uint64 `json:"number"`
	Title         string `json:"title"`
	EpisodesCount uint64 `json:"episodesCount"`
	State         string `json:"state"`
}

type CreateSeasonRequestSerializer struct {
	Id            uint64 `json:"id" validate:"required"`
	Title         string `json:"title" validate:"required"`
	Number        uint64 `json:"number" validate:"omitempty,min=0"`
	EpisodesCount uint64 `json:"episodesCount" validate:"omitempty,min=0"`
	State         string `json:"state" validate:"omitempty,oneof=want watching watched none"`
}

func (params *CreateSeasonRequestSerializer) Validate(body io.Reader) error {
	if err := json.NewDecoder(body).Decode(params); err != nil {
		return err
	}

	params.Title = strings.TrimSpace(params.Title)
	if params.Title == "" {
		return errors.ErrEmptyTitle
	}

	if err := validateItemState(&params.State); err != nil {
		return err
	}

	return validate.Struct(params)
}

type UpdateSeasonRequestSerializer struct {
	State string `json:"state" validate:"omitempty,oneof=want watching watched none"`
}

func (params *UpdateSeasonRequestSerializer) Validate(body io.Reader) error {
	if err := json.NewDecoder(body).Decode(params); err != nil {
		return err
	}

	if err := validateItemState(&params.State); err != nil {
		return err
	}

	return validate.Struct(params)
}

// validateItemState trims and validates the state of a season or episode
// against the full set of tracking states supported by the state_types enum.
func validateItemState(state *string) error {
	*state = strings.TrimSpace(*state)
	switch *state {
	case models.StateTypeWant, models.StateTypeWatching, models.StateTypeWatched, models.StateTypeNone:
		return nil
	case "":
		return errors.ErrEmptyState
	default:
		return errors.ErrInvalidState
	}
}

// SeasonSummarySerializer is a season overview embedded in a series' details.
type SeasonSummarySerializer struct {
	Id            uint64 `json:"id"`
	Title         string `json:"title"`
	Number        uint64 `json:"number"`
	PosterPath    string `json:"posterPath"`
	EpisodesCount uint64 `json:"episodesCount"`
	AirDate       string `json:"airDate,omitempty"`
}

// SeasonDetailsSerializer is a TMDB-sourced season with its episodes, returned
// by GET /series/{id}/season/{seasonNumber}.
type SeasonDetailsSerializer struct {
	Id         uint64                    `json:"id"`
	TmdbShowId uint64                    `json:"tmdbShowId,omitempty"`
	Title      string                    `json:"title"`
	Number     uint64                    `json:"number"`
	PosterPath string                    `json:"posterPath"`
	AirDate    string                    `json:"airDate,omitempty"`
	Overview   string                    `json:"overview"`
	Episodes   []SeasonEpisodeSerializer `json:"episodes"`
}

// SeasonEpisodeSerializer is a lightweight episode within a season's details.
type SeasonEpisodeSerializer struct {
	Id         uint64  `json:"id"`
	Title      string  `json:"title"`
	Number     uint64  `json:"number"`
	PosterPath string  `json:"posterPath"`
	Runtime    uint64  `json:"runtime"`
	Overview   string  `json:"overview"`
	Rating     float64 `json:"rating,omitempty"`
	AirDate    string  `json:"airDate,omitempty"`
}
