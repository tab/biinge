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

// StatsPeriods lists every period a user's statistics can be cached under
var StatsPeriods = []StatsPeriod{StatsPeriodWeek, StatsPeriodMonth, StatsPeriodYear, StatsPeriodAll}

// String returns the period's wire value
func (p StatsPeriod) String() string {
	return string(p)
}

// Stats is a user's aggregate watch statistics, every count scoped to the period
type Stats struct {
	// Minutes are summed runtimes. Want is the whole list all-time and what was added to it
	// inside a bounded period; SeriesWatched is shows finished all-time and shows with a
	// watched episode inside a bounded one. SeriesWatching and GamesPlaying are nil on a
	// bounded period, since a show or game is in progress now rather than during some past
	// window. GamesMinutes is IGDB's time to beat, not time actually played
	Period          StatsPeriod
	MoviesWant      uint64
	MoviesWatched   uint64
	MoviesMinutes   uint64
	SeriesWant      uint64
	SeriesWatching  *uint64
	SeriesWatched   uint64
	EpisodesWatched uint64
	EpisodesMinutes uint64
	GamesWant       uint64
	GamesPlaying    *uint64
	GamesPlayed     uint64
	GamesMinutes    uint64
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
