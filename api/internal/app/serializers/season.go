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

	return nil
}

type UpdateSeasonRequestSerializer struct {
	State string `json:"state" validate:"omitempty,oneof=want watching watched none"`
}

func (params *UpdateSeasonRequestSerializer) Validate(body io.Reader) error {
	if err := json.NewDecoder(body).Decode(params); err != nil {
		return err
	}

	return validateItemState(&params.State)
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
