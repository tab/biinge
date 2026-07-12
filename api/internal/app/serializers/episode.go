package serializers

import (
	"encoding/json"
	"io"
	"strings"

	"biinge-api/internal/app/errors"
)

type EpisodeSerializer struct {
	Id         uint64 `json:"id"`
	Title      string `json:"title"`
	PosterPath string `json:"posterPath"`
	Runtime    uint64 `json:"runtime"`
	State      string `json:"state"`
	AirDate    string `json:"airDate,omitempty"`
}

type CreateEpisodeRequestSerializer struct {
	Id         uint64 `json:"id" validate:"required"`
	Title      string `json:"title" validate:"required"`
	PosterPath string `json:"posterPath"`
	Runtime    uint64 `json:"runtime" validate:"omitempty,min=0"`
	AirDate    string `json:"airDate"`
	State      string `json:"state" validate:"omitempty,oneof=want watching watched none"`
}

func (params *CreateEpisodeRequestSerializer) Validate(body io.Reader) error {
	if err := json.NewDecoder(body).Decode(params); err != nil {
		return err
	}

	params.Title = strings.TrimSpace(params.Title)
	if params.Title == "" {
		return errors.ErrEmptyTitle
	}

	return validateItemState(&params.State)
}

type UpdateEpisodeRequestSerializer struct {
	State string `json:"state" validate:"omitempty,oneof=want watching watched none"`
}

func (params *UpdateEpisodeRequestSerializer) Validate(body io.Reader) error {
	if err := json.NewDecoder(body).Decode(params); err != nil {
		return err
	}

	return validateItemState(&params.State)
}

// EpisodeDetailsSerializer is a TMDB-sourced single episode with credits and
// trailers, returned by GET /series/{id}/season/{seasonNumber}/episode/{episodeNumber}.
type EpisodeDetailsSerializer struct {
	Id         uint64             `json:"id"`
	Title      string             `json:"title"`
	Number     uint64             `json:"number"`
	PosterPath string             `json:"posterPath"`
	Runtime    uint64             `json:"runtime"`
	Overview   string             `json:"overview"`
	Rating     float64            `json:"rating,omitempty"`
	AirDate    string             `json:"airDate,omitempty"`
	Credits    []PersonSerializer `json:"credits"`
	Videos     []VideoSerializer  `json:"videos"`
}
