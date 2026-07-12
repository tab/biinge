package models

import "time"

// TvInProductionStatus is the TMDB status of a show that is still airing new
// episodes. A show whose every episode is watched but that is still in
// production is treated as "watching" rather than "watched".
const TvInProductionStatus = "Returning Series"

// SeriesInput carries the show-level fields needed to upsert a series row while
// recording watched progress.
type SeriesInput struct {
	TmdbId        uint64
	Title         string
	PosterPath    string
	SeasonsCount  uint64
	EpisodesCount uint64
	Status        string
}

// SeasonInput carries the season-level fields plus, when marking a whole season
// or show watched, the episodes that belong to it.
type SeasonInput struct {
	TmdbId        uint64
	Title         string
	Number        uint64
	EpisodesCount uint64
	Episodes      []EpisodeInput
}

// EpisodeInput carries the episode-level fields needed to upsert an episode row.
type EpisodeInput struct {
	TmdbId     uint64
	Title      string
	PosterPath string
	Runtime    uint64
	AirAt      time.Time
}

// ShowInput is the payload for marking an entire show watched: the series plus
// every season and its episodes.
type ShowInput struct {
	Series  SeriesInput
	Seasons []SeasonInput
}

// SeriesProgress is the derived watched state of a show: the series' own state
// and the TMDB ids of the seasons and episodes currently marked watched.
type SeriesProgress struct {
	SeriesTmdbId    uint64
	State           string
	WatchedSeasons  []uint64
	WatchedEpisodes []uint64
}
