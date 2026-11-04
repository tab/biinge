package serializers

import "biinge-api/internal/app/models"

type MovieCreditSerializer struct {
	Id         uint64           `json:"id"`
	Title      string           `json:"title"`
	PosterPath string           `json:"posterPath"`
	State      models.StateType `json:"state,omitempty"`
	Type       string           `json:"type,omitempty"`
}

type SeriesCreditSerializer struct {
	Id            uint64           `json:"id"`
	Title         string           `json:"title"`
	PosterPath    string           `json:"posterPath"`
	State         models.StateType `json:"state,omitempty"`
	EpisodesCount int              `json:"episodesCount,omitempty"`
}

type PersonDetailsSerializer struct {
	Id            uint64                   `json:"id"`
	Name          string                   `json:"name"`
	Birthday      string                   `json:"birthday,omitempty"`
	Biography     string                   `json:"biography,omitempty"`
	ProfilePath   string                   `json:"profilePath"`
	Gender        int                      `json:"gender"`
	MovieCredits  []MovieCreditSerializer  `json:"movieCredits"`
	SeriesCredits []SeriesCreditSerializer `json:"seriesCredits"`
}
