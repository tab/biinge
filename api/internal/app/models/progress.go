package models

import "time"

// SeriesInProductionStatus is the TMDB status of a series still airing; such a series is never derived "watched"
const SeriesInProductionStatus = "Returning Series"

// SeriesInput carries the show-level fields needed to upsert a series row
type SeriesInput struct {
	TmdbId        uint64
	Title         string
	PosterPath    string
	SeasonsCount  uint64
	EpisodesCount uint64
	Status        string
}

// SeriesSyncInput carries the TMDB-refreshed show fields the sync worker writes back
type SeriesSyncInput struct {
	Title         string
	PosterPath    string
	Status        string
	SeasonsCount  uint64
	EpisodesCount uint64
	LastAirAt     time.Time
}

// SeasonInput carries the season-level fields and, for whole-season marks, its episodes
type SeasonInput struct {
	TmdbId        uint64
	Title         string
	Number        uint64
	EpisodesCount uint64
	Episodes      []EpisodeInput
}

// EpisodeInput carries the episode-level fields needed to upsert an episode row
type EpisodeInput struct {
	TmdbId     uint64
	Title      string
	PosterPath string
	Runtime    uint64
	AirAt      time.Time
}

// MarkSeriesInput is the payload for marking an entire series watched
type MarkSeriesInput struct {
	Series  SeriesInput
	Seasons []SeasonInput
}

// SeriesProgress is a show's derived watched state; TrackedState is the user's explicit choice that unmark-all reverts to
type SeriesProgress struct {
	SeriesTmdbId    uint64
	State           StateType
	TrackedState    StateType
	WatchedSeasons  []uint64
	WatchedEpisodes []uint64
}
