package tmdb

import (
	"testing"
	"time"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

func Test_UniqById(t *testing.T) {
	tests := []struct {
		name     string
		items    []CreditItem
		expected []CreditItem
	}{
		{
			name:     "Nil slice returns nil",
			items:    nil,
			expected: nil,
		},
		{
			name:     "Empty slice returns empty",
			items:    []CreditItem{},
			expected: []CreditItem{},
		},
		{
			name: "Deduplicates by id keeping first occurrence",
			items: []CreditItem{
				{Id: 1, Name: "First"},
				{Id: 2, Name: "Second"},
				{Id: 1, Name: "Duplicate"},
			},
			expected: []CreditItem{
				{Id: 1, Name: "First"},
				{Id: 2, Name: "Second"},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := UniqById(tt.items, func(c CreditItem) int {
				return c.Id
			})

			assert.Equal(t, tt.expected, result)
		})
	}
}

func Test_ParseDate(t *testing.T) {
	tests := []struct {
		name     string
		dateStr  string
		expected time.Time
		error    bool
	}{
		{
			name:     "Empty string returns zero time",
			dateStr:  "",
			expected: time.Time{},
		},
		{
			name:     "Valid date",
			dateStr:  "2020-01-15",
			expected: time.Date(2020, time.January, 15, 0, 0, 0, 0, time.UTC),
		},
		{
			name:    "Invalid format returns error",
			dateStr: "2020/01/15",
			error:   true,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result, err := ParseDate(tt.dateStr)

			if tt.error {
				require.Error(t, err)
			} else {
				require.NoError(t, err)
				assert.Equal(t, tt.expected, result)
			}
		})
	}
}

func Test_TransformMovieDetails(t *testing.T) {
	tests := []struct {
		name     string
		movie    *MovieDetails
		expected *MovieResponse
	}{
		{
			name:     "Nil input returns nil",
			movie:    nil,
			expected: nil,
		},
		{
			name: "Full transform",
			movie: &MovieDetails{
				Id:          550,
				Title:       "Fight Club",
				Overview:    "An insomniac office worker...",
				PosterPath:  "/poster.jpg",
				Status:      "Released",
				ImdbId:      "tt0137523",
				ReleaseDate: "1999-10-15",
				Runtime:     139,
				VoteAverage: 8.4,
				Credits: Credits{
					Cast: []PersonCast{
						{Person: Person{Id: 1, Name: "Actor A", ProfilePath: "/a.jpg"}, Character: "Narrator"},
						{Person: Person{Id: 2, Name: "Actor B", ProfilePath: ""}, Character: "Tyler"},
					},
					Crew: []PersonCrew{
						{Person: Person{Id: 3, Name: "Director A", ProfilePath: "/d.jpg"}, Job: TMDBJobDirector},
						{Person: Person{Id: 4, Name: "Director B", ProfilePath: ""}, Job: TMDBJobDirector},
						{Person: Person{Id: 5, Name: "DP A", ProfilePath: "/dp.jpg"}, Job: TMDBJobDirectorOfPhotography},
						{Person: Person{Id: 6, Name: "Writer A", ProfilePath: "/w.jpg"}, Job: TMDBJobWriter},
						{Person: Person{Id: 7, Name: "Editor A", ProfilePath: "/e.jpg"}, Job: "Editor"},
						{Person: Person{Id: 1, Name: "Actor A", ProfilePath: "/a.jpg"}, Job: TMDBJobScreenplay},
					},
				},
				Recommendations: Recommendations{
					Results: []Recommendation{
						{Id: 100, Title: "Rec Movie", PosterPath: "/r1.jpg"},
						{Id: 101, Name: "Rec Fallback Name", PosterPath: "/r2.jpg"},
						{Id: 102, Title: "No Poster", PosterPath: ""},
					},
				},
				Videos: Videos{
					Results: []Video{
						{Id: "v1", Key: "key1", Official: true, Site: TMDBYoutubeType, Type: TMDBTrailerType},
						{Id: "v2", Key: "key2", Official: false, Site: TMDBYoutubeType, Type: TMDBTrailerType},
						{Id: "v3", Key: "key3", Official: true, Site: "Vimeo", Type: TMDBTrailerType},
						{Id: "v4", Key: "key4", Official: true, Site: TMDBYoutubeType, Type: "Teaser"},
					},
				},
			},
			expected: &MovieResponse{
				Id:          550,
				Title:       "Fight Club",
				Overview:    "An insomniac office worker...",
				PosterPath:  "/poster.jpg",
				Status:      "Released",
				ImdbId:      "tt0137523",
				ReleaseDate: "1999-10-15",
				Runtime:     139,
				Rating:      8.4,
				Credits: []CreditItem{
					{Id: 3, ProfilePath: "/d.jpg", Name: "Director A", Description: "Director"},
					{Id: 1, ProfilePath: "/a.jpg", Name: "Actor A", Description: "Narrator"},
					{Id: 5, ProfilePath: "/dp.jpg", Name: "DP A", Description: "Director of Photography"},
					{Id: 6, ProfilePath: "/w.jpg", Name: "Writer A", Description: "Writer"},
				},
				Recommendations: []RecommendationItem{
					{Id: 100, Title: "Rec Movie", PosterPath: "/r1.jpg"},
					{Id: 101, Title: "Rec Fallback Name", PosterPath: "/r2.jpg"},
				},
				Videos: []VideoItem{
					{Id: "v1", Key: "key1"},
				},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := TransformMovieDetails(tt.movie)

			assert.Equal(t, tt.expected, result)
		})
	}
}

func Test_TransformTvDetails(t *testing.T) {
	tests := []struct {
		name     string
		tvShow   *TvDetails
		expected *TvResponse
	}{
		{
			name:     "Nil input returns nil",
			tvShow:   nil,
			expected: nil,
		},
		{
			name: "Full transform",
			tvShow: &TvDetails{
				Id:          1399,
				Title:       "Game of Thrones",
				Overview:    "Seven noble families...",
				PosterPath:  "/poster.jpg",
				Status:      "Ended",
				ImdbId:      "tt0944947",
				ReleaseDate: "2011-04-17",
				VoteAverage: 9.2,
				Credits: Credits{
					Cast: []PersonCast{
						{Person: Person{Id: 1, Name: "Actor A", ProfilePath: "/a.jpg"}, Character: "Jon Snow"},
						{Person: Person{Id: 2, Name: "Actor B", ProfilePath: ""}, Character: "Cersei"},
					},
					Crew: []PersonCrew{
						{Person: Person{Id: 3, Name: "Director A", ProfilePath: "/d.jpg"}, Job: TMDBJobDirector},
						{Person: Person{Id: 4, Name: "Director B", ProfilePath: ""}, Job: TMDBJobDirector},
						{Person: Person{Id: 5, Name: "DP A", ProfilePath: "/dp.jpg"}, Job: TMDBJobDirectorOfPhotography},
						{Person: Person{Id: 6, Name: "Writer A", ProfilePath: "/w.jpg"}, Job: TMDBJobWriter},
						{Person: Person{Id: 7, Name: "Editor A", ProfilePath: "/e.jpg"}, Job: "Editor"},
						{Person: Person{Id: 1, Name: "Actor A", ProfilePath: "/a.jpg"}, Job: TMDBJobScreenplay},
					},
				},
				Recommendations: Recommendations{
					Results: []Recommendation{
						{Id: 100, Title: "Rec Show", PosterPath: "/r1.jpg"},
						{Id: 101, Name: "Rec Fallback Name", PosterPath: "/r2.jpg"},
						{Id: 102, Title: "No Poster", PosterPath: ""},
					},
				},
				Videos: Videos{
					Results: []Video{
						{Id: "v1", Key: "key1", Official: true, Site: TMDBYoutubeType, Type: TMDBTrailerType},
						{Id: "v2", Key: "key2", Official: false, Site: TMDBYoutubeType, Type: TMDBTrailerType},
					},
				},
				Seasons: []TvSeason{
					{Id: 10, Name: "Season 1", SeasonNumber: 1, EpisodeCount: 10, PosterPath: "/s1.jpg", AirDate: "2011-04-17"},
					{Id: 11, Name: "Season 2", SeasonNumber: 2, EpisodeCount: 10, PosterPath: "/s2.jpg", AirDate: "2012-04-01"},
				},
			},
			expected: &TvResponse{
				Id:          1399,
				Title:       "Game of Thrones",
				Overview:    "Seven noble families...",
				PosterPath:  "/poster.jpg",
				Status:      "Ended",
				ImdbId:      "tt0944947",
				ReleaseDate: "2011-04-17",
				Rating:      9.2,
				Credits: []CreditItem{
					{Id: 3, ProfilePath: "/d.jpg", Name: "Director A", Description: "Director"},
					{Id: 1, ProfilePath: "/a.jpg", Name: "Actor A", Description: "Jon Snow"},
					{Id: 5, ProfilePath: "/dp.jpg", Name: "DP A", Description: "Director of Photography"},
					{Id: 6, ProfilePath: "/w.jpg", Name: "Writer A", Description: "Writer"},
				},
				Recommendations: []RecommendationItem{
					{Id: 100, Title: "Rec Show", PosterPath: "/r1.jpg"},
					{Id: 101, Title: "Rec Fallback Name", PosterPath: "/r2.jpg"},
				},
				Videos: []VideoItem{
					{Id: "v1", Key: "key1"},
				},
				Seasons: []SeasonSummaryItem{
					{Id: 10, Title: "Season 1", Number: 1, PosterPath: "/s1.jpg", EpisodesCount: 10, AirDate: "2011-04-17"},
					{Id: 11, Title: "Season 2", Number: 2, PosterPath: "/s2.jpg", EpisodesCount: 10, AirDate: "2012-04-01"},
				},
			},
		},
		{
			name: "Empty seasons produces empty slice",
			tvShow: &TvDetails{
				Id:    1,
				Title: "Empty Show",
			},
			expected: &TvResponse{
				Id:              1,
				Title:           "Empty Show",
				Credits:         []CreditItem{},
				Recommendations: []RecommendationItem{},
				Videos:          []VideoItem{},
				Seasons:         []SeasonSummaryItem{},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := TransformTvDetails(tt.tvShow)

			assert.Equal(t, tt.expected, result)
		})
	}
}

func Test_TransformSeasonDetails(t *testing.T) {
	tests := []struct {
		name     string
		season   *SeasonDetails
		expected *SeasonResponse
	}{
		{
			name:     "Nil input returns nil",
			season:   nil,
			expected: nil,
		},
		{
			name: "Full transform with runtime clamping",
			season: &SeasonDetails{
				ID:           1,
				AirDate:      "2011-04-17",
				Name:         "Season 1",
				Overview:     "Winter is coming",
				PosterPath:   "/s1.jpg",
				SeasonNumber: 1,
				Episodes: []Episode{
					{ID: 100, AirDate: "2011-04-17", EpisodeNumber: 1, Name: "Winter Is Coming", Overview: "Ep1", Runtime: 62, VoteAverage: 8.1},
					{ID: 101, AirDate: "2011-04-24", EpisodeNumber: 2, Name: "The Kingsroad", Overview: "Ep2", Runtime: -5, VoteAverage: 7.8},
				},
			},
			expected: &SeasonResponse{
				Id:         1,
				Title:      "Season 1",
				Number:     1,
				PosterPath: "/s1.jpg",
				AirDate:    "2011-04-17",
				Overview:   "Winter is coming",
				Episodes: []EpisodeResponseItem{
					{Id: 100, Title: "Winter Is Coming", Number: 1, PosterPath: "", Runtime: 62, Overview: "Ep1", Rating: 8.1, AirDate: "2011-04-17"},
					{Id: 101, Title: "The Kingsroad", Number: 2, PosterPath: "", Runtime: 0, Overview: "Ep2", Rating: 7.8, AirDate: "2011-04-24"},
				},
			},
		},
		{
			name: "Empty episodes produces empty slice",
			season: &SeasonDetails{
				ID:   2,
				Name: "Season 2",
			},
			expected: &SeasonResponse{
				Id:       2,
				Title:    "Season 2",
				Episodes: []EpisodeResponseItem{},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := TransformSeasonDetails(tt.season)

			assert.Equal(t, tt.expected, result)
		})
	}
}

func Test_TransformEpisodeDetails(t *testing.T) {
	tests := []struct {
		name     string
		episode  *EpisodeDetails
		expected *EpisodeResponse
	}{
		{
			name:     "Nil input returns nil",
			episode:  nil,
			expected: nil,
		},
		{
			name: "Full transform with credits and videos",
			episode: &EpisodeDetails{
				ID:            100,
				AirDate:       "2011-04-17",
				EpisodeNumber: 1,
				Name:          "Winter Is Coming",
				Overview:      "Ep1",
				Runtime:       -1,
				VoteAverage:   8.1,
				Credits: Credits{
					Cast: []PersonCast{
						{Person: Person{Id: 1, Name: "Actor A", ProfilePath: "/a.jpg"}, Character: "Jon Snow"},
						{Person: Person{Id: 2, Name: "Actor B", ProfilePath: ""}, Character: "Cersei"},
					},
					Crew: []PersonCrew{
						{Person: Person{Id: 3, Name: "Director A", ProfilePath: "/d.jpg"}, Job: TMDBJobDirector},
						{Person: Person{Id: 1, Name: "Actor A", ProfilePath: "/a.jpg"}, Job: TMDBJobWriter},
					},
				},
				Videos: Videos{
					Results: []Video{
						{Id: "v1", Key: "key1", Official: true, Site: TMDBYoutubeType, Type: TMDBTrailerType},
						{Id: "v2", Key: "key2", Official: false, Site: TMDBYoutubeType, Type: TMDBTrailerType},
					},
				},
			},
			expected: &EpisodeResponse{
				Id:       100,
				Title:    "Winter Is Coming",
				Number:   1,
				Runtime:  0,
				Overview: "Ep1",
				Rating:   8.1,
				AirDate:  "2011-04-17",
				Credits: []CreditItem{
					{Id: 3, ProfilePath: "/d.jpg", Name: "Director A", Description: "Director"},
					{Id: 1, ProfilePath: "/a.jpg", Name: "Actor A", Description: "Jon Snow"},
				},
				Videos: []VideoItem{
					{Id: "v1", Key: "key1"},
				},
			},
		},
		{
			name: "Empty credits and videos produce empty slices",
			episode: &EpisodeDetails{
				ID:      200,
				Name:    "The Kingsroad",
				Runtime: 55,
			},
			expected: &EpisodeResponse{
				Id:      200,
				Title:   "The Kingsroad",
				Runtime: 55,
				Credits: []CreditItem{},
				Videos:  []VideoItem{},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := TransformEpisodeDetails(tt.episode)

			assert.Equal(t, tt.expected, result)
		})
	}
}

func Test_FilterMovieCredits(t *testing.T) {
	tests := []struct {
		name     string
		credits  []MovieCredit
		expected []MovieCreditItem
	}{
		{
			name:     "Empty input returns empty slice",
			credits:  []MovieCredit{},
			expected: []MovieCreditItem{},
		},
		{
			name: "Filters adult, missing poster and missing release date",
			credits: []MovieCredit{
				{Id: 1, Title: "Adult Movie", PosterPath: "/a.jpg", ReleaseDate: "2020-01-01", Adult: true},
				{Id: 2, Title: "No Poster", PosterPath: "", ReleaseDate: "2020-01-01"},
				{Id: 3, Title: "No Release Date", PosterPath: "/c.jpg", ReleaseDate: ""},
				{Id: 4, Title: "Valid Movie", PosterPath: "/d.jpg", ReleaseDate: "2020-01-01", Character: "Hero"},
			},
			expected: []MovieCreditItem{
				{Id: 4, Title: "Valid Movie", PosterPath: "/d.jpg", Type: "Hero"},
			},
		},
		{
			name: "Job takes precedence over character for type",
			credits: []MovieCredit{
				{Id: 1, Title: "Directed Movie", PosterPath: "/a.jpg", ReleaseDate: "2020-01-01", Character: "Himself", Job: TMDBJobDirector},
			},
			expected: []MovieCreditItem{
				{Id: 1, Title: "Directed Movie", PosterPath: "/a.jpg", Type: TMDBJobDirector},
			},
		},
		{
			name: "Sorted by release date descending",
			credits: []MovieCredit{
				{Id: 1, Title: "Oldest", PosterPath: "/a.jpg", ReleaseDate: "2018-01-01"},
				{Id: 2, Title: "Newest", PosterPath: "/b.jpg", ReleaseDate: "2022-01-01"},
				{Id: 3, Title: "Middle", PosterPath: "/c.jpg", ReleaseDate: "2020-01-01"},
			},
			expected: []MovieCreditItem{
				{Id: 2, Title: "Newest", PosterPath: "/b.jpg"},
				{Id: 3, Title: "Middle", PosterPath: "/c.jpg"},
				{Id: 1, Title: "Oldest", PosterPath: "/a.jpg"},
			},
		},
		{
			name: "Invalid release date format does not panic and is retained",
			credits: []MovieCredit{
				{Id: 1, Title: "Bad Date", PosterPath: "/a.jpg", ReleaseDate: "not-a-date"},
				{Id: 2, Title: "Good Date", PosterPath: "/b.jpg", ReleaseDate: "2020-01-01"},
			},
			expected: []MovieCreditItem{
				{Id: 1, Title: "Bad Date", PosterPath: "/a.jpg"},
				{Id: 2, Title: "Good Date", PosterPath: "/b.jpg"},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := FilterMovieCredits(tt.credits)

			assert.Equal(t, tt.expected, result)
		})
	}
}

func Test_FilterTvCredits(t *testing.T) {
	excludedGenreIds := []int{10767, 10763, 10764, 99}

	tests := []struct {
		name     string
		credits  []TvCredit
		expected []TvCreditItem
	}{
		{
			name:     "Empty input returns empty slice",
			credits:  []TvCredit{},
			expected: []TvCreditItem{},
		},
		{
			name: "Filters adult, missing poster, missing air date and missing genres",
			credits: []TvCredit{
				{Id: 1, Name: "Adult Show", PosterPath: "/a.jpg", FirstAirDate: "2020-01-01", GenreIds: []int{18}, Adult: true},
				{Id: 2, Name: "No Poster", PosterPath: "", FirstAirDate: "2020-01-01", GenreIds: []int{18}},
				{Id: 3, Name: "No Air Date", PosterPath: "/c.jpg", FirstAirDate: "", GenreIds: []int{18}},
				{Id: 4, Name: "No Genres", PosterPath: "/d.jpg", FirstAirDate: "2020-01-01", GenreIds: []int{}},
				{Id: 5, Name: "Valid Show", PosterPath: "/e.jpg", FirstAirDate: "2020-01-01", GenreIds: []int{18}, EpisodeCount: 10},
			},
			expected: []TvCreditItem{
				{Id: 5, Title: "Valid Show", PosterPath: "/e.jpg", EpisodesCount: 10},
			},
		},
		{
			name: "Excludes shows with an excluded genre id",
			credits: []TvCredit{
				{Id: 1, Name: "Reality Show", PosterPath: "/a.jpg", FirstAirDate: "2020-01-01", GenreIds: []int{10764}},
				{Id: 2, Name: "Drama Show", PosterPath: "/b.jpg", FirstAirDate: "2020-01-01", GenreIds: []int{18, 99}},
				{Id: 3, Name: "Kept Show", PosterPath: "/c.jpg", FirstAirDate: "2020-01-01", GenreIds: []int{18}},
			},
			expected: []TvCreditItem{
				{Id: 3, Title: "Kept Show", PosterPath: "/c.jpg"},
			},
		},
		{
			name: "Sorted by first air date descending",
			credits: []TvCredit{
				{Id: 1, Name: "Oldest", PosterPath: "/a.jpg", FirstAirDate: "2018-01-01", GenreIds: []int{18}},
				{Id: 2, Name: "Newest", PosterPath: "/b.jpg", FirstAirDate: "2022-01-01", GenreIds: []int{18}},
				{Id: 3, Name: "Middle", PosterPath: "/c.jpg", FirstAirDate: "2020-01-01", GenreIds: []int{18}},
			},
			expected: []TvCreditItem{
				{Id: 2, Title: "Newest", PosterPath: "/b.jpg"},
				{Id: 3, Title: "Middle", PosterPath: "/c.jpg"},
				{Id: 1, Title: "Oldest", PosterPath: "/a.jpg"},
			},
		},
		{
			name: "Invalid air date format does not panic and is retained",
			credits: []TvCredit{
				{Id: 1, Name: "Bad Date", PosterPath: "/a.jpg", FirstAirDate: "not-a-date", GenreIds: []int{18}},
				{Id: 2, Name: "Good Date", PosterPath: "/b.jpg", FirstAirDate: "2020-01-01", GenreIds: []int{18}},
			},
			expected: []TvCreditItem{
				{Id: 1, Title: "Bad Date", PosterPath: "/a.jpg"},
				{Id: 2, Title: "Good Date", PosterPath: "/b.jpg"},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := FilterTvCredits(tt.credits, excludedGenreIds)

			assert.Equal(t, tt.expected, result)
		})
	}
}

func Test_TransformPersonDetails(t *testing.T) {
	tests := []struct {
		name     string
		person   *PersonDetails
		expected *PersonResponse
	}{
		{
			name:     "Nil input returns nil",
			person:   nil,
			expected: nil,
		},
		{
			name: "Full transform with director merge, genre exclusion and tv credit dedupe",
			person: &PersonDetails{
				Id:          6193,
				ImdbId:      "nm0000138",
				Name:        "Leonardo DiCaprio",
				Birthday:    "1974-11-11",
				ProfilePath: "/profile.jpg",
				Gender:      2,
				Credits: PersonMovieCredits{
					Cast: []MovieCredit{
						{Id: 1, Title: "Movie A", PosterPath: "/a.jpg", ReleaseDate: "2020-01-01", Character: "Hero"},
						{Id: 2, Title: "Adult Movie", PosterPath: "/b.jpg", ReleaseDate: "2019-01-01", Character: "X", Adult: true},
						{Id: 3, Title: "No Poster Movie", PosterPath: "", ReleaseDate: "2018-01-01", Character: "Y"},
					},
					Crew: []MovieCredit{
						{Id: 10, Title: "Directed Movie", PosterPath: "/d.jpg", ReleaseDate: "2021-01-01", Job: TMDBJobDirector},
						{Id: 11, Title: "Produced Movie", PosterPath: "/p.jpg", ReleaseDate: "2022-01-01", Job: "Producer"},
					},
				},
				TvCredits: PersonTvCredits{
					Cast: []TvCredit{
						{Id: 100, Name: "Show A", PosterPath: "/s1.jpg", FirstAirDate: "2015-01-01", GenreIds: []int{18}, EpisodeCount: 10},
						{Id: 101, Name: "Reality Show", PosterPath: "/s2.jpg", FirstAirDate: "2016-01-01", GenreIds: []int{10764}, EpisodeCount: 5},
						{Id: 102, Name: "No Genre Show", PosterPath: "/s3.jpg", FirstAirDate: "2016-01-01", GenreIds: []int{}, EpisodeCount: 5},
						{Id: 103, Name: "Show B - Also Directed", PosterPath: "/s4.jpg", FirstAirDate: "2017-01-01", GenreIds: []int{18}, EpisodeCount: 20},
					},
					Crew: []TvCredit{
						{Id: 103, Name: "Show B - Also Directed", PosterPath: "/s4.jpg", FirstAirDate: "2017-01-01", GenreIds: []int{18}, EpisodeCount: 20, Job: TMDBJobDirector},
						{Id: 104, Name: "Produced Show", PosterPath: "/s5.jpg", FirstAirDate: "2014-01-01", GenreIds: []int{18}, Job: "Producer"},
					},
				},
			},
			expected: &PersonResponse{
				Id:          6193,
				ImdbId:      "nm0000138",
				Name:        "Leonardo DiCaprio",
				Birthday:    "1974-11-11",
				ProfilePath: "/profile.jpg",
				Gender:      2,
				MovieCredits: []MovieCreditItem{
					{Id: 10, Title: "Directed Movie", PosterPath: "/d.jpg", Type: TMDBJobDirector},
					{Id: 1, Title: "Movie A", PosterPath: "/a.jpg", Type: "Hero"},
				},
				TvCredits: []TvCreditItem{
					{Id: 103, Title: "Show B - Also Directed", PosterPath: "/s4.jpg", EpisodesCount: 20},
					{Id: 100, Title: "Show A", PosterPath: "/s1.jpg", EpisodesCount: 10},
				},
			},
		},
		{
			name: "Empty credits produce empty slices",
			person: &PersonDetails{
				Id:   1,
				Name: "Empty Person",
			},
			expected: &PersonResponse{
				Id:           1,
				Name:         "Empty Person",
				MovieCredits: []MovieCreditItem{},
				TvCredits:    []TvCreditItem{},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			result := TransformPersonDetails(tt.person)

			assert.Equal(t, tt.expected, result)
		})
	}
}
