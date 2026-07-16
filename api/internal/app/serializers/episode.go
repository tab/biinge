package serializers

// EpisodeDetailsSerializer is a TMDB-sourced episode with credits, trailers and the user's watched state
type EpisodeDetailsSerializer struct {
	Id         uint64             `json:"id"`
	Title      string             `json:"title"`
	Number     uint64             `json:"number"`
	PosterPath string             `json:"posterPath"`
	Runtime    uint64             `json:"runtime"`
	Overview   string             `json:"overview"`
	Rating     float64            `json:"rating,omitempty"`
	AirDate    string             `json:"airDate,omitempty"`
	Watched    bool               `json:"watched"`
	Credits    []PersonSerializer `json:"credits"`
	Videos     []VideoSerializer  `json:"videos"`
}
