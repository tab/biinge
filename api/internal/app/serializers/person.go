package serializers

type MovieCreditSerializer struct {
	Id         uint64 `json:"id"`
	Title      string `json:"title"`
	PosterPath string `json:"posterPath"`
	State      string `json:"state,omitempty"`
	Type       string `json:"type,omitempty"`
}

type PersonDetailsSerializer struct {
	Id           uint64                  `json:"id"`
	Name         string                  `json:"name"`
	Birthday     string                  `json:"birthday,omitempty"`
	ProfilePath  string                  `json:"profilePath"`
	Gender       int                     `json:"gender"`
	MovieCredits []MovieCreditSerializer `json:"movieCredits"`
}
