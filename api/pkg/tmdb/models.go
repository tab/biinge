package tmdb

type Person struct {
	Id          int     `json:"id"`
	Name        string  `json:"name"`
	Biography   string  `json:"biography,omitempty"`
	Adult       bool    `json:"adult"`
	ProfilePath string  `json:"profile_path"`
	Popularity  float64 `json:"popularity,omitempty"`
}

type PersonCast struct {
	Person
	Character string `json:"character"`
	Order     int    `json:"order,omitempty"`
}

type PersonCrew struct {
	Person
	Department string `json:"department"`
	Job        string `json:"job"`
}

type Credits struct {
	Cast []PersonCast `json:"cast"`
	Crew []PersonCrew `json:"crew"`
}

type Recommendation struct {
	Id               uint64  `json:"id"`
	Title            string  `json:"title,omitempty"`
	Name             string  `json:"name,omitempty"`
	Overview         string  `json:"overview"`
	Adult            bool    `json:"adult"`
	BackdropPath     string  `json:"backdrop_path"`
	PosterPath       string  `json:"poster_path"`
	ReleaseDate      string  `json:"release_date,omitempty"`
	FirstAirDate     string  `json:"first_air_date,omitempty"`
	OriginalLanguage string  `json:"original_language"`
	OriginalTitle    string  `json:"original_title,omitempty"`
	OriginalName     string  `json:"original_name,omitempty"`
	Popularity       float64 `json:"popularity"`
	VoteAverage      float64 `json:"vote_average"`
	VoteCount        int     `json:"vote_count"`
}

type Recommendations struct {
	Page         int              `json:"page"`
	Results      []Recommendation `json:"results"`
	TotalPages   int              `json:"total_pages"`
	TotalResults int              `json:"total_results"`
}

type Video struct {
	Id          string `json:"id"`
	Name        string `json:"name"`
	Key         string `json:"key"`
	Site        string `json:"site"`
	Size        int    `json:"size"`
	Type        string `json:"type"`
	Official    bool   `json:"official"`
	PublishedAt string `json:"published_at"`
	ISO31661    string `json:"iso_3166_1"`
	ISO6391     string `json:"iso_639_1"`
}

type Videos struct {
	Results []Video `json:"results"`
}

type MovieDetails struct {
	Id              int             `json:"id"`
	Title           string          `json:"title"`
	Overview        string          `json:"overview"`
	PosterPath      string          `json:"poster_path"`
	BackdropPath    string          `json:"backdrop_path"`
	Status          string          `json:"status"`
	ImdbId          string          `json:"imdb_id"`
	ReleaseDate     string          `json:"release_date"`
	Runtime         int             `json:"runtime"`
	VoteAverage     float64         `json:"vote_average"`
	Credits         Credits         `json:"credits"`
	Recommendations Recommendations `json:"recommendations"`
	Videos          Videos          `json:"videos"`
}

type MovieCredit struct {
	Id           uint64 `json:"id"`
	Title        string `json:"title"`
	Overview     string `json:"overview"`
	Adult        bool   `json:"adult"`
	BackdropPath string `json:"backdrop_path"`
	PosterPath   string `json:"poster_path"`
	ReleaseDate  string `json:"release_date"`
	Character    string `json:"character,omitempty"`
	Job          string `json:"job,omitempty"`
	Department   string `json:"department,omitempty"`
}

type TvCredit struct {
	Id           int    `json:"id"`
	Name         string `json:"name"`
	Overview     string `json:"overview"`
	Adult        bool   `json:"adult"`
	BackdropPath string `json:"backdrop_path"`
	PosterPath   string `json:"poster_path"`
	FirstAirDate string `json:"first_air_date"`
	Character    string `json:"character,omitempty"`
	Job          string `json:"job,omitempty"`
	Department   string `json:"department,omitempty"`
	EpisodeCount int    `json:"episode_count,omitempty"`
	GenreIds     []int  `json:"genre_ids"`
}

type PersonMovieCredits struct {
	Cast []MovieCredit `json:"cast"`
	Crew []MovieCredit `json:"crew"`
}

type PersonTvCredits struct {
	Cast []TvCredit `json:"cast"`
	Crew []TvCredit `json:"crew"`
}

type PersonDetails struct {
	Id          int                `json:"id"`
	ImdbId      string             `json:"imdb_id,omitempty"`
	Name        string             `json:"name"`
	Birthday    string             `json:"birthday,omitempty"`
	ProfilePath string             `json:"profile_path"`
	Gender      int                `json:"gender"`
	Credits     PersonMovieCredits `json:"credits"`
	TvCredits   PersonTvCredits    `json:"tv_credits"`
}

type CreditItem struct {
	Id          int    `json:"id"`
	ProfilePath string `json:"profilePath"`
	Name        string `json:"name"`
	Description string `json:"description"`
}

type RecommendationItem struct {
	Id         uint64 `json:"id"`
	Title      string `json:"title"`
	PosterPath string `json:"posterPath"`
}

type VideoItem struct {
	Id  string `json:"id"`
	Key string `json:"key"`
}

type MovieResponse struct {
	Id              int                  `json:"id"`
	Title           string               `json:"title"`
	Overview        string               `json:"overview"`
	PosterPath      string               `json:"posterPath"`
	Status          string               `json:"status"`
	ImdbId          string               `json:"imdbId"`
	ReleaseDate     string               `json:"releaseDate"`
	Runtime         int                  `json:"runtime"`
	Rating          float64              `json:"rating"`
	Credits         []CreditItem         `json:"credits"`
	Recommendations []RecommendationItem `json:"recommendations"`
	Videos          []VideoItem          `json:"videos"`
}

type MovieCreditItem struct {
	Id         uint64 `json:"id"`
	Title      string `json:"title"`
	PosterPath string `json:"posterPath"`
	Type       string `json:"type"`
}

type TvCreditItem struct {
	Id            int    `json:"id"`
	Title         string `json:"title"`
	PosterPath    string `json:"posterPath"`
	EpisodesCount int    `json:"episodesCount,omitempty"`
}

type PersonResponse struct {
	Id           int               `json:"id"`
	ImdbId       string            `json:"imdbId,omitempty"`
	Name         string            `json:"name"`
	Birthday     string            `json:"birthday,omitempty"`
	ProfilePath  string            `json:"profilePath"`
	Gender       int               `json:"gender"`
	MovieCredits []MovieCreditItem `json:"movieCredits"`
	TvCredits    []TvCreditItem    `json:"tvCredits"`
}

type TvDetails struct {
	Id              int             `json:"id"`
	Title           string          `json:"name"`
	Overview        string          `json:"overview"`
	PosterPath      string          `json:"poster_path"`
	BackdropPath    string          `json:"backdrop_path"`
	Status          string          `json:"status"`
	ImdbId          string          `json:"imdb_id"`
	ReleaseDate     string          `json:"first_air_date"`
	Runtime         int             `json:"runtime"`
	VoteAverage     float64         `json:"vote_average"`
	Credits         Credits         `json:"credits"`
	Recommendations Recommendations `json:"recommendations"`
	Videos          Videos          `json:"videos"`
	Seasons         []TvSeason      `json:"seasons"`
}

type TvResponse struct {
	Id              int                  `json:"id"`
	Title           string               `json:"title"`
	Overview        string               `json:"overview"`
	PosterPath      string               `json:"posterPath"`
	Status          string               `json:"status"`
	ImdbId          string               `json:"imdb_id"`
	ReleaseDate     string               `json:"release_date"`
	Rating          float64              `json:"rating"`
	Credits         []CreditItem         `json:"credits"`
	Recommendations []RecommendationItem `json:"recommendations"`
	Videos          []VideoItem          `json:"videos"`
	Seasons         []SeasonSummaryItem  `json:"seasons"`
}

type SeasonDetails struct {
	ID           int       `json:"id"`
	AirDate      string    `json:"air_date"`
	Name         string    `json:"name"`
	Overview     string    `json:"overview"`
	PosterPath   string    `json:"poster_path"`
	SeasonNumber int       `json:"season_number"`
	Episodes     []Episode `json:"episodes"`
}

type Episode struct {
	ID             int     `json:"id"`
	AirDate        string  `json:"air_date"`
	EpisodeNumber  int     `json:"episode_number"`
	Name           string  `json:"name"`
	Overview       string  `json:"overview"`
	ProductionCode string  `json:"production_code"`
	Runtime        int     `json:"runtime"`
	SeasonNumber   int     `json:"season_number"`
	StillPath      string  `json:"still_path"`
	VoteAverage    float64 `json:"vote_average"`
	VoteCount      int     `json:"vote_count"`
}

type EpisodeDetails struct {
	ID             int     `json:"id"`
	AirDate        string  `json:"air_date"`
	EpisodeNumber  int     `json:"episode_number"`
	Name           string  `json:"name"`
	Overview       string  `json:"overview"`
	ProductionCode string  `json:"production_code"`
	Runtime        int     `json:"runtime"`
	SeasonNumber   int     `json:"season_number"`
	StillPath      string  `json:"still_path"`
	VoteAverage    float64 `json:"vote_average"`
	VoteCount      int     `json:"vote_count"`
	Credits        Credits `json:"credits"`
	Videos         Videos  `json:"videos"`
}

// TvSeason is a season summary as returned within a TMDB /tv/{id} response
type TvSeason struct {
	Id           uint64 `json:"id"`
	Name         string `json:"name"`
	SeasonNumber int    `json:"season_number"`
	EpisodeCount int    `json:"episode_count"`
	PosterPath   string `json:"poster_path"`
	AirDate      string `json:"air_date"`
	Overview     string `json:"overview"`
}

// SeasonSummaryItem is the transformed (camelCase) season summary embedded in TvResponse
type SeasonSummaryItem struct {
	Id            uint64 `json:"id"`
	Title         string `json:"title"`
	Number        uint64 `json:"number"`
	PosterPath    string `json:"posterPath"`
	EpisodesCount uint64 `json:"episodesCount"`
	AirDate       string `json:"airDate,omitempty"`
}

// SeasonResponse is the transformed season detail (with its episodes)
type SeasonResponse struct {
	Id         uint64                `json:"id"`
	Title      string                `json:"title"`
	Number     uint64                `json:"number"`
	PosterPath string                `json:"posterPath"`
	AirDate    string                `json:"airDate,omitempty"`
	Overview   string                `json:"overview"`
	Episodes   []EpisodeResponseItem `json:"episodes"`
}

// EpisodeResponseItem is a lightweight episode within a season detail
type EpisodeResponseItem struct {
	Id         uint64  `json:"id"`
	Title      string  `json:"title"`
	Number     uint64  `json:"number"`
	PosterPath string  `json:"posterPath"`
	Runtime    uint64  `json:"runtime"`
	Overview   string  `json:"overview"`
	Rating     float64 `json:"rating,omitempty"`
	AirDate    string  `json:"airDate,omitempty"`
}

// EpisodeResponse is the transformed single-episode detail (with credits + videos)
type EpisodeResponse struct {
	Id         uint64       `json:"id"`
	Title      string       `json:"title"`
	Number     uint64       `json:"number"`
	PosterPath string       `json:"posterPath"`
	Runtime    uint64       `json:"runtime"`
	Overview   string       `json:"overview"`
	Rating     float64      `json:"rating,omitempty"`
	AirDate    string       `json:"airDate,omitempty"`
	Credits    []CreditItem `json:"credits"`
	Videos     []VideoItem  `json:"videos"`
}

// --- Search / trending list results ---

type MovieListItem struct {
	Id          uint64  `json:"id"`
	Title       string  `json:"title"`
	PosterPath  string  `json:"poster_path"`
	ReleaseDate string  `json:"release_date"`
	VoteAverage float64 `json:"vote_average"`
	Overview    string  `json:"overview"`
	Adult       bool    `json:"adult"`
}

type TvListItem struct {
	Id           uint64  `json:"id"`
	Name         string  `json:"name"`
	PosterPath   string  `json:"poster_path"`
	FirstAirDate string  `json:"first_air_date"`
	VoteAverage  float64 `json:"vote_average"`
	Overview     string  `json:"overview"`
	Adult        bool    `json:"adult"`
}

type PersonKnownFor struct {
	VoteCount int `json:"vote_count"`
}

type PersonListItem struct {
	Id          uint64           `json:"id"`
	Name        string           `json:"name"`
	ProfilePath string           `json:"profile_path"`
	Adult       bool             `json:"adult"`
	KnownFor    []PersonKnownFor `json:"known_for"`
}

type MovieListResult struct {
	Page         int             `json:"page"`
	Results      []MovieListItem `json:"results"`
	TotalPages   int             `json:"total_pages"`
	TotalResults int             `json:"total_results"`
}

type TvListResult struct {
	Page         int          `json:"page"`
	Results      []TvListItem `json:"results"`
	TotalPages   int          `json:"total_pages"`
	TotalResults int          `json:"total_results"`
}

type PersonListResult struct {
	Page         int              `json:"page"`
	Results      []PersonListItem `json:"results"`
	TotalPages   int              `json:"total_pages"`
	TotalResults int              `json:"total_results"`
}
