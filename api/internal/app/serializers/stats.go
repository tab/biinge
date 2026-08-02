package serializers

import (
	"time"

	"biinge-api/internal/app/models"
)

// MovieStatsSerializer counts a user's movies and their watched runtime (a bounded
// period counts what was added to the want list inside it)
type MovieStatsSerializer struct {
	Want    uint64 `json:"want"`
	Watched uint64 `json:"watched"`
	Minutes uint64 `json:"minutes"`
}

// SeriesStatsSerializer counts a user's shows (a bounded period omits watching, which
// describes a show now rather than during a past window)
type SeriesStatsSerializer struct {
	Want     uint64  `json:"want"`
	Watching *uint64 `json:"watching,omitempty"`
	Watched  uint64  `json:"watched"`
}

type EpisodeStatsSerializer struct {
	Watched uint64 `json:"watched"`
	Minutes uint64 `json:"minutes"`
}

type ActivityBucketSerializer struct {
	Date         string `json:"date"`
	MovieMinutes uint64 `json:"movieMinutes"`
	TvMinutes    uint64 `json:"tvMinutes"`
}

type StatsSerializer struct {
	Period   string                     `json:"period"`
	Movies   MovieStatsSerializer       `json:"movies"`
	Series   SeriesStatsSerializer      `json:"series"`
	Episodes EpisodeStatsSerializer     `json:"episodes"`
	Activity []ActivityBucketSerializer `json:"activity"`
}

func NewStatsSerializer(stats *models.Stats) StatsSerializer {
	activity := make([]ActivityBucketSerializer, 0, len(stats.Activity))
	for _, bucket := range stats.Activity {
		activity = append(activity, ActivityBucketSerializer{
			Date:         bucket.Date.Format(time.DateOnly),
			MovieMinutes: bucket.MovieMinutes,
			TvMinutes:    bucket.TvMinutes,
		})
	}

	return StatsSerializer{
		Period: stats.Period.String(),
		Movies: MovieStatsSerializer{
			Want:    stats.MoviesWant,
			Watched: stats.MoviesWatched,
			Minutes: stats.MoviesMinutes,
		},
		Series: SeriesStatsSerializer{
			Want:     stats.SeriesWant,
			Watching: stats.SeriesWatching,
			Watched:  stats.SeriesWatched,
		},
		Episodes: EpisodeStatsSerializer{
			Watched: stats.EpisodesWatched,
			Minutes: stats.EpisodesMinutes,
		},
		Activity: activity,
	}
}
