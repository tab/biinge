package models

import "time"

// StatsPeriod is the calendar period watched statistics are aggregated over
type StatsPeriod string

const (
	StatsPeriodWeek  StatsPeriod = "week"
	StatsPeriodMonth StatsPeriod = "month"
	StatsPeriodYear  StatsPeriod = "year"
	StatsPeriodAll   StatsPeriod = "all"
)

// String returns the period's wire value
func (p StatsPeriod) String() string {
	return string(p)
}

// Stats is a user's aggregate watch statistics. Minutes are summed runtimes
type Stats struct {
	Period          StatsPeriod
	MoviesWant      uint64
	MoviesWatched   uint64
	MoviesMinutes   uint64
	SeriesWant      uint64
	SeriesWatching  uint64
	SeriesWatched   uint64
	EpisodesWatched uint64
	EpisodesMinutes uint64
	Activity        []WatchBucket
}

// WatchBucket is watched runtime for one activity bucket, split by media kind
type WatchBucket struct {
	Date         time.Time
	MovieMinutes uint64
	TvMinutes    uint64
}

// NewStatsPeriod maps a raw request value to a supported period, defaulting to all
func NewStatsPeriod(value string) StatsPeriod {
	switch period := StatsPeriod(value); period {
	case StatsPeriodWeek, StatsPeriodMonth, StatsPeriodYear:
		return period
	default:
		return StatsPeriodAll
	}
}
