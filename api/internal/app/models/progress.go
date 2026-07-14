package models

import "time"

// TvInProductionStatus is the TMDB status of a show still airing; such a show is never derived "watched"
const TvInProductionStatus = "Returning Series"

// SeriesInput carries the show-level fields needed to upsert a series row
type SeriesInput struct {
	TmdbId        uint64
	Title         string
	PosterPath    string
	SeasonsCount  uint64
	EpisodesCount uint64
	Status        string
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

// ShowInput is the payload for marking an entire show watched
type ShowInput struct {
	Series  SeriesInput
	Seasons []SeasonInput
}

// SeriesProgress is a show's derived watched state; TrackedState is the user's explicit choice that unmark-all reverts to
type SeriesProgress struct {
	SeriesTmdbId    uint64
	State           string
	TrackedState    string
	WatchedSeasons  []uint64
	WatchedEpisodes []uint64
}
