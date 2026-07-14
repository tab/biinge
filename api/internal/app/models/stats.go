package models

// Stats is a user's aggregate watch statistics. Minutes are summed runtimes
type Stats struct {
	MoviesWant      uint64
	MoviesWatched   uint64
	MoviesMinutes   uint64
	SeriesWant      uint64
	SeriesWatching  uint64
	SeriesWatched   uint64
	EpisodesWatched uint64
	EpisodesMinutes uint64
}
