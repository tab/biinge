package serializers

import (
	"encoding/json"
	"io"
	"strings"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/models"
)

// PosterPath on a game is an IGDB cover image_id, not a path: the client builds
// {IGDB_BASE_IMAGE_URL}/t_{size}/{posterPath}.jpg

type GameSerializer struct {
	Id         uint64           `json:"id"`
	Title      string           `json:"title"`
	PosterPath string           `json:"posterPath"`
	Pinned     bool             `json:"pinned"`
	State      models.StateType `json:"state"`
}

type GameDetailsSerializer struct {
	Id               uint64                     `json:"id"`
	Title            string                     `json:"title"`
	PosterPath       string                     `json:"posterPath"`
	Pinned           bool                       `json:"pinned"`
	State            models.StateType           `json:"state"`
	Overview         string                     `json:"overview"`
	Status           string                     `json:"status,omitempty"`
	ReleaseDate      string                     `json:"releaseDate,omitempty"`
	Runtime          uint64                     `json:"runtime,omitempty"`
	RuntimeCompleted uint64                     `json:"runtimeCompleted,omitempty"`
	Rating           float64                    `json:"rating,omitempty"`
	Genres           []string                   `json:"genres"`
	Platforms        []string                   `json:"platforms"`
	Recommendations  []RecommendationSerializer `json:"recommendations"`
}

type CreateGameRequestSerializer struct {
	Id         uint64 `json:"id" validate:"required"`
	Title      string `json:"title" validate:"required"`
	PosterPath string `json:"posterPath"`
	Runtime    uint64 `json:"runtime" validate:"omitempty,min=0"`
	State      string `json:"state" validate:"omitempty,oneof=want playing played"`
}

func (params *CreateGameRequestSerializer) Validate(body io.Reader) error {
	if err := json.NewDecoder(body).Decode(params); err != nil {
		return err
	}

	params.Title = strings.TrimSpace(params.Title)
	if params.Title == "" {
		return errors.ErrEmptyTitle
	}

	params.PosterPath = strings.TrimSpace(params.PosterPath)

	params.State = strings.TrimSpace(params.State)
	switch models.StateType(params.State) {
	case models.StateTypeWant, models.StateTypePlaying, models.StateTypePlayed:
	case "":
		return errors.ErrEmptyState
	default:
		return errors.ErrInvalidState
	}

	return validate.Struct(params)
}

type UpdateGameRequestSerializer struct {
	State  string `json:"state" validate:"omitempty,oneof=want playing played"`
	Pinned bool   `json:"pinned"`
}

func (params *UpdateGameRequestSerializer) Validate(body io.Reader) error {
	if err := json.NewDecoder(body).Decode(params); err != nil {
		return err
	}

	params.State = strings.TrimSpace(params.State)
	switch models.StateType(params.State) {
	case models.StateTypeWant, models.StateTypePlaying, models.StateTypePlayed:
	case "":
		return errors.ErrEmptyState
	default:
		return errors.ErrInvalidState
	}

	return validate.Struct(params)
}
