package serializers

import "biinge-api/internal/app/models"

type MovieStatsSerializer struct {
	Want    uint64 `json:"want"`
	Watched uint64 `json:"watched"`
	Minutes uint64 `json:"minutes"`
}

type SeriesStatsSerializer struct {
	Want     uint64 `json:"want"`
	Watching uint64 `json:"watching"`
	Watched  uint64 `json:"watched"`
}

type EpisodeStatsSerializer struct {
	Watched uint64 `json:"watched"`
	Minutes uint64 `json:"minutes"`
}

type MonthlyActivitySerializer struct {
	Month        string `json:"month"`
	MovieMinutes uint64 `json:"movieMinutes"`
	TvMinutes    uint64 `json:"tvMinutes"`
}

type StatsSerializer struct {
	Movies   MovieStatsSerializer        `json:"movies"`
	Series   SeriesStatsSerializer       `json:"series"`
	Episodes EpisodeStatsSerializer      `json:"episodes"`
	Activity []MonthlyActivitySerializer `json:"activity"`
}

func NewStatsSerializer(stats *models.Stats) StatsSerializer {
	activity := make([]MonthlyActivitySerializer, 0, len(stats.Activity))
	for _, month := range stats.Activity {
		activity = append(activity, MonthlyActivitySerializer{
			Month:        month.Month.Format("2006-01"),
			MovieMinutes: month.MovieMinutes,
			TvMinutes:    month.TvMinutes,
		})
	}

	return StatsSerializer{
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
