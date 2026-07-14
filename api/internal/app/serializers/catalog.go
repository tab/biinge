package serializers

// Search and trending items carry the user's tracking state so the client can badge library items

type SearchMovieSerializer struct {
	Id          uint64  `json:"id"`
	Title       string  `json:"title"`
	PosterPath  string  `json:"posterPath"`
	ReleaseDate string  `json:"releaseDate,omitempty"`
	Rating      float64 `json:"rating,omitempty"`
	State       string  `json:"state,omitempty"`
}

type SearchSeriesSerializer struct {
	Id          uint64  `json:"id"`
	Title       string  `json:"title"`
	PosterPath  string  `json:"posterPath"`
	ReleaseDate string  `json:"releaseDate,omitempty"`
	Rating      float64 `json:"rating,omitempty"`
	State       string  `json:"state,omitempty"`
}

type SearchPersonSerializer struct {
	Id          uint64 `json:"id"`
	Name        string `json:"name"`
	ProfilePath string `json:"profilePath"`
}
