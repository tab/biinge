package serializers

// Search and trending results are TMDB-sourced browse lists. Movie and series
// items carry the current user's tracking state (want/watched/none) so the
// client can badge items already in the library; people items do not.

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
