package serializers

// UpNextSerializer is the user's ready-to-watch queue: aired episodes, released movies and released games from pinned library items
type UpNextSerializer struct {
	Episodes []UpNextEpisodeSerializer `json:"episodes"`
	Movies   []UpNextMovieSerializer   `json:"movies"`
	Games    []UpNextGameSerializer    `json:"games"`
}

// UpNextEpisodeSerializer is a single episode carrying the show context needed to open it
type UpNextEpisodeSerializer struct {
	SeriesId         uint64  `json:"seriesId"`
	SeriesTitle      string  `json:"seriesTitle"`
	SeriesPosterPath string  `json:"seriesPosterPath"`
	Id               uint64  `json:"id"`
	Title            string  `json:"title"`
	SeasonNumber     uint64  `json:"seasonNumber"`
	Number           uint64  `json:"number"`
	PosterPath       string  `json:"posterPath"`
	Overview         string  `json:"overview"`
	Runtime          uint64  `json:"runtime"`
	Rating           float64 `json:"rating,omitempty"`
	AirDate          string  `json:"airDate"`
}

// UpNextMovieSerializer is a released, still-unwatched movie from the user's want list
type UpNextMovieSerializer struct {
	Id          uint64  `json:"id"`
	Title       string  `json:"title"`
	PosterPath  string  `json:"posterPath"`
	Overview    string  `json:"overview"`
	Runtime     uint64  `json:"runtime"`
	Rating      float64 `json:"rating,omitempty"`
	ReleaseDate string  `json:"releaseDate"`
}

// UpNextGameSerializer is a released, still-unplayed game from the user's want list (PosterPath is an IGDB cover id, Runtime the time to beat)
type UpNextGameSerializer struct {
	Id          uint64  `json:"id"`
	Title       string  `json:"title"`
	PosterPath  string  `json:"posterPath"`
	Overview    string  `json:"overview"`
	Runtime     uint64  `json:"runtime"`
	Rating      float64 `json:"rating,omitempty"`
	ReleaseDate string  `json:"releaseDate"`
}
