package serializers

// SeasonSummarySerializer is a season overview embedded in a series' details
type SeasonSummarySerializer struct {
	Id            uint64 `json:"id"`
	Title         string `json:"title"`
	Number        uint64 `json:"number"`
	PosterPath    string `json:"posterPath"`
	EpisodesCount uint64 `json:"episodesCount"`
	AirDate       string `json:"airDate,omitempty"`
}

// SeasonDetailsSerializer is a TMDB-sourced season with its episodes and the user's watched state
type SeasonDetailsSerializer struct {
	Id         uint64                    `json:"id"`
	TmdbShowId uint64                    `json:"tmdbShowId,omitempty"`
	Title      string                    `json:"title"`
	Number     uint64                    `json:"number"`
	PosterPath string                    `json:"posterPath"`
	AirDate    string                    `json:"airDate,omitempty"`
	Overview   string                    `json:"overview"`
	Watched    bool                      `json:"watched"`
	Episodes   []SeasonEpisodeSerializer `json:"episodes"`
}

// SeasonEpisodeSerializer is a lightweight episode within a season's details
type SeasonEpisodeSerializer struct {
	Id         uint64  `json:"id"`
	Title      string  `json:"title"`
	Number     uint64  `json:"number"`
	PosterPath string  `json:"posterPath"`
	Runtime    uint64  `json:"runtime"`
	Overview   string  `json:"overview"`
	Rating     float64 `json:"rating,omitempty"`
	AirDate    string  `json:"airDate,omitempty"`
	Watched    bool    `json:"watched"`
}
