package serializers

import (
	"encoding/json"
	"io"
	"strings"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/models"
)

type RecommendationSerializer struct {
	Id         uint64 `json:"id"`
	Title      string `json:"title"`
	PosterPath string `json:"posterPath"`
	State      string `json:"state,omitempty"`
}

type PersonSerializer struct {
	Id          int    `json:"id"`
	ProfilePath string `json:"profilePath"`
	Name        string `json:"name"`
	Description string `json:"description"`
}

type VideoSerializer struct {
	Id  string `json:"id"`
	Key string `json:"key"`
}

type MovieSerializer struct {
	Id         uint64 `json:"id"`
	Title      string `json:"title"`
	PosterPath string `json:"posterPath"`
	Pinned     bool   `json:"pinned"`
	State      string `json:"state"`
}

type MovieDetailsSerializer struct {
	Id              uint64                     `json:"id"`
	ImdbId          string                     `json:"imdbId,omitempty"`
	Title           string                     `json:"title"`
	PosterPath      string                     `json:"posterPath"`
	Pinned          bool                       `json:"pinned"`
	State           string                     `json:"state"`
	Overview        string                     `json:"overview"`
	Status          string                     `json:"status,omitempty"`
	ReleaseDate     string                     `json:"releaseDate,omitempty"`
	Runtime         int                        `json:"runtime,omitempty"`
	Rating          float64                    `json:"rating,omitempty"`
	Credits         []PersonSerializer         `json:"credits"`
	Recommendations []RecommendationSerializer `json:"recommendations"`
	Videos          []VideoSerializer          `json:"videos"`
}

type CreateMovieRequestSerializer struct {
	Id         uint64 `json:"id" validate:"required"`
	Title      string `json:"title" validate:"required"`
	PosterPath string `json:"posterPath" validate:"required"`
	Runtime    uint64 `json:"runtime" validate:"omitempty,min=0"`
	State      string `json:"state" validate:"omitempty,oneof=want watched"`
}

func (params *CreateMovieRequestSerializer) Validate(body io.Reader) error {
	if err := json.NewDecoder(body).Decode(params); err != nil {
		return err
	}

	params.Title = strings.TrimSpace(params.Title)
	if params.Title == "" {
		return errors.ErrEmptyTitle
	}

	params.PosterPath = strings.TrimSpace(params.PosterPath)
	if params.PosterPath == "" {
		return errors.ErrEmptyPoster
	}

	params.State = strings.TrimSpace(params.State)
	switch params.State {
	case models.StateTypeWant, models.StateTypeWatched:
	case "":
		return errors.ErrEmptyState
	default:
		return errors.ErrInvalidState
	}

	return nil
}

type UpdateMovieRequestSerializer struct {
	State  string `json:"state" validate:"omitempty,oneof=want watched"`
	Pinned bool   `json:"pinned"`
}

func (params *UpdateMovieRequestSerializer) Validate(body io.Reader) error {
	if err := json.NewDecoder(body).Decode(params); err != nil {
		return err
	}

	params.State = strings.TrimSpace(params.State)
	switch params.State {
	case models.StateTypeWant, models.StateTypeWatched:
	case "":
		return errors.ErrEmptyState
	default:
		return errors.ErrInvalidState
	}

	return nil
}
