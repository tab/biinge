package models

import "time"

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
	Activity        []MonthlyWatch
}

// MonthlyWatch is watched runtime for one calendar month, split by media kind
type MonthlyWatch struct {
	Month        time.Time
	MovieMinutes uint64
	TvMinutes    uint64
}
