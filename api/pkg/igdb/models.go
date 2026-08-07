package igdb

// Cover is a game's box art; ImageId builds the CDN URL
type Cover struct {
	Id      uint64 `json:"id"`
	ImageId string `json:"image_id"`
}

type Genre struct {
	Id   uint64 `json:"id"`
	Name string `json:"name"`
}

type Platform struct {
	Id   uint64 `json:"id"`
	Name string `json:"name"`
}

// GameStatus is the release status entity, absent on most released games
type GameStatus struct {
	Id     uint64 `json:"id"`
	Status string `json:"status"`
}

// ReleaseDate is one platform's release of a game (Date is a Unix timestamp)
type ReleaseDate struct {
	Id       uint64 `json:"id"`
	Date     int64  `json:"date"`
	Platform uint64 `json:"platform"`
}

// SimilarGame is one nested similar_games row; its Platforms are raw ids because a nested expansion
// carries no platform names
type SimilarGame struct {
	Id               uint64   `json:"id"`
	Name             string   `json:"name"`
	GameType         int      `json:"game_type"`
	VersionParent    uint64   `json:"version_parent"`
	TotalRatingCount int      `json:"total_rating_count"`
	Cover            Cover    `json:"cover"`
	Platforms        []uint64 `json:"platforms"`
}

type Game struct {
	Id               uint64        `json:"id"`
	Name             string        `json:"name"`
	Summary          string        `json:"summary"`
	FirstReleaseDate int64         `json:"first_release_date"`
	TotalRating      float64       `json:"total_rating"`
	TotalRatingCount int           `json:"total_rating_count"`
	Cover            Cover         `json:"cover"`
	GameStatus       GameStatus    `json:"game_status"`
	Genres           []Genre       `json:"genres"`
	Platforms        []Platform    `json:"platforms"`
	ReleaseDates     []ReleaseDate `json:"release_dates"`
	SimilarGames     []SimilarGame `json:"similar_games"`
}

// TimeToBeat holds crowd-sourced completion times in seconds, with the submission count behind them
type TimeToBeat struct {
	GameId     uint64 `json:"game_id"`
	Normally   int64  `json:"normally"`
	Completely int64  `json:"completely"`
	Count      int    `json:"count"`
}

// PopularityPrimitive ranks one game under one popularity type
type PopularityPrimitive struct {
	GameId uint64  `json:"game_id"`
	Value  float64 `json:"value"`
}

// GameDetails pairs a game with its completion times, both fetched in one multiquery round trip
type GameDetails struct {
	Game       Game
	TimeToBeat TimeToBeat
}

type GameListResult struct {
	Results []Game
}

// GameRecommendation is a similar game reduced to what the detail rail renders
type GameRecommendation struct {
	Id         uint64
	Title      string
	PosterPath string
}

// GameResponse is the transformed detail shape the services layer consumes
type GameResponse struct {
	Id               uint64
	Title            string
	PosterPath       string
	Overview         string
	Status           string
	ReleaseDate      string
	Rating           float64
	Runtime          uint64
	RuntimeCompleted uint64
	Genres           []string
	Platforms        []string
	Recommendations  []GameRecommendation
}

// GameItem is the transformed list shape shared by search and trending
type GameItem struct {
	Id          uint64
	Title       string
	PosterPath  string
	ReleaseDate string
	Rating      float64
}
