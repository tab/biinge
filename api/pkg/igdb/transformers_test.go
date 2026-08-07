package igdb

import (
	"testing"

	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// Unix timestamps for the release dates the fixtures use
const (
	ps4Release   int64 = 1425168000 // 2015-03-01
	ps5Release   int64 = 1677628800 // 2023-03-01
	pcRelease    int64 = 1104537600 // 2005-01-01
	switchDevice       = uint64(130)
)

// futureRelease is 2099-01-01, a date that stays unreleased for the life of this test
const futureRelease int64 = 4070908800

func Test_TransformGameDetails(t *testing.T) {
	t.Run("Maps every rendered field", func(t *testing.T) {
		result := TransformGameDetails(&GameDetails{
			Game: Game{
				Id:               1942,
				Name:             "The Witcher 3",
				Summary:          "A monster hunter searches for his adopted daughter.",
				FirstReleaseDate: pcRelease,
				TotalRating:      94.6,
				TotalRatingCount: 3200,
				Cover:            Cover{Id: 7, ImageId: "co1wyy"},
				GameStatus:       GameStatus{Id: 1, Status: "Released"},
				Genres:           []Genre{{Name: "Role-playing (RPG)"}, {Name: "Adventure"}},
				Platforms:        []Platform{{Name: "PlayStation 5"}, {Name: "PC"}},
				ReleaseDates: []ReleaseDate{
					{Date: ps5Release, Platform: PlatformPlayStation5},
				},
			},
			TimeToBeat: TimeToBeat{Normally: 180000, Completely: 381600, Count: 1200},
		})

		require.NotNil(t, result)
		assert.Equal(t, uint64(1942), result.Id)
		assert.Equal(t, "The Witcher 3", result.Title)
		assert.Equal(t, "co1wyy", result.PosterPath)
		assert.Equal(t, "A monster hunter searches for his adopted daughter.", result.Overview)
		assert.Equal(t, "Released", result.Status)
		assert.Equal(t, "2023-03-01", result.ReleaseDate)
		assert.InDelta(t, 9.46, result.Rating, 0.001)
		assert.Equal(t, uint64(3000), result.Runtime)
		assert.Equal(t, uint64(6360), result.RuntimeCompleted)
		assert.Equal(t, []string{"RPG", "Adventure"}, result.Genres)
		assert.Equal(t, []string{"PS5", "PC"}, result.Platforms)
	})

	t.Run("Renames the genres that carry an acronym or read oddly", func(t *testing.T) {
		result := TransformGameDetails(&GameDetails{
			Game: Game{
				Id: 1942,
				Genres: []Genre{
					{Name: "Role-playing (RPG)"},
					{Name: "Turn-based strategy (TBS)"},
					{Name: "Hack and slash/Beat 'em up"},
					{Name: "Simulator"},
					{Name: "Sport"},
					{Name: "Platform"},
					{Name: "Adventure"},
				},
			},
		})

		require.NotNil(t, result)
		assert.Equal(
			t,
			[]string{"RPG", "TBS", "Hack and Slash", "Simulation", "Sports", "Platformer", "Adventure"},
			result.Genres,
		)
	})

	t.Run("Shortens platform names and drops the duplicates that collapsing creates", func(t *testing.T) {
		result := TransformGameDetails(&GameDetails{
			Game: Game{
				Id: 1942,
				Platforms: []Platform{
					{Name: "PC (Microsoft Windows)"},
					{Name: "PlayStation 5"},
					{Name: "PlayStation 4"},
					{Name: "Xbox Series X|S"},
					{Name: "Xbox One"},
					{Name: "Xbox 360"},
					{Name: "Nintendo Switch"},
					{Name: "Nintendo Switch 2"},
					{Name: "Wii U"},
					{Name: "Mac"},
					{Name: "ZX Spectrum"},
				},
			},
		})

		require.NotNil(t, result)
		// PlayStation keeps its generation, the rest collapse, and an unmapped name is left alone
		assert.Equal(
			t,
			[]string{"PC", "PS5", "PS4", "Xbox", "Nintendo", "Mac", "ZX Spectrum"},
			result.Platforms,
		)
	})

	t.Run("Keeps the PlayStation-playable similar games, best known first", func(t *testing.T) {
		result := TransformGameDetails(&GameDetails{
			Game: Game{
				Id: 1942,
				SimilarGames: []SimilarGame{
					{
						Id: 1, Name: "Obscure Match", Cover: Cover{ImageId: "co1"},
						TotalRatingCount: 28, Platforms: []uint64{PlatformPlayStation4},
					},
					{
						Id: 2, Name: "PC Only", Cover: Cover{ImageId: "co2"},
						TotalRatingCount: 900, Platforms: []uint64{switchDevice},
					},
					{
						Id: 3, Name: "Well Known", Cover: Cover{ImageId: "co3"},
						TotalRatingCount: 1755, Platforms: []uint64{PlatformPlayStation5},
					},
					{
						Id: 4, Name: "Bundle", Cover: Cover{ImageId: "co4"}, GameType: 3,
						TotalRatingCount: 400, Platforms: []uint64{PlatformPlayStation5},
					},
					{
						Id: 5, Name: "No Cover", TotalRatingCount: 500,
						Platforms: []uint64{PlatformPlayStation5},
					},
					{
						Id: 6, Name: "Alternate Edition", Cover: Cover{ImageId: "co6"}, VersionParent: 3,
						TotalRatingCount: 700, Platforms: []uint64{PlatformPlayStation5},
					},
					{
						Id: 7, Name: "Remaster", Cover: Cover{ImageId: "co7"}, GameType: gameTypeRemaster,
						TotalRatingCount: 613, Platforms: []uint64{PlatformPlayStation4},
					},
				},
			},
		})

		require.NotNil(t, result)
		require.Len(t, result.Recommendations, 3)
		assert.Equal(t, "Well Known", result.Recommendations[0].Title)
		assert.Equal(t, "Remaster", result.Recommendations[1].Title)
		assert.Equal(t, "Obscure Match", result.Recommendations[2].Title)
		assert.Equal(t, uint64(3), result.Recommendations[0].Id)
		assert.Equal(t, "co3", result.Recommendations[0].PosterPath)
	})

	t.Run("Absent cover and completion times leave empty values", func(t *testing.T) {
		result := TransformGameDetails(&GameDetails{
			Game: Game{Id: 5, Name: "Unknown", FirstReleaseDate: pcRelease},
		})

		require.NotNil(t, result)
		assert.Empty(t, result.PosterPath)
		// IGDB records no status on an ordinary game, so the past release date supplies it
		assert.Equal(t, "Released", result.Status)
		assert.Zero(t, result.Runtime)
		assert.Zero(t, result.RuntimeCompleted)
		assert.Zero(t, result.Rating)
		assert.Empty(t, result.Genres)
		assert.Empty(t, result.Platforms)
		assert.Empty(t, result.Recommendations)
	})
}

func Test_GameStatus(t *testing.T) {
	tests := []struct {
		name     string
		status   string
		release  int64
		expected string
	}{
		{name: "Keeps the status IGDB records", status: "Early Access", release: ps4Release, expected: "Early Access"},
		{name: "Keeps it even against a future date", status: "Cancelled", release: futureRelease, expected: "Cancelled"},
		{name: "A past release date reads as released", release: ps4Release, expected: "Released"},
		{name: "A future release date reads as upcoming", release: futureRelease, expected: "Upcoming"},
		{name: "No date leaves the pill off", release: 0, expected: ""},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.expected, gameStatus(tt.status, tt.release))
		})
	}
}

func Test_PlaystationRelease(t *testing.T) {
	tests := []struct {
		name     string
		game     Game
		expected string
	}{
		{
			name: "Prefers the earliest PlayStation release over the first release anywhere",
			game: Game{
				FirstReleaseDate: pcRelease,
				ReleaseDates: []ReleaseDate{
					{Date: ps5Release, Platform: PlatformPlayStation5},
					{Date: ps4Release, Platform: PlatformPlayStation4},
					{Date: pcRelease, Platform: switchDevice},
				},
			},
			expected: "2015-03-01",
		},
		{
			name: "Falls back to the first release when no PlayStation release is listed",
			game: Game{
				FirstReleaseDate: pcRelease,
				ReleaseDates:     []ReleaseDate{{Date: ps5Release, Platform: switchDevice}},
			},
			expected: "2005-01-01",
		},
		{
			name:     "Empty when the game has no dates at all",
			game:     Game{},
			expected: "",
		},
		{
			name: "Skips PlayStation entries with no date",
			game: Game{
				FirstReleaseDate: pcRelease,
				ReleaseDates:     []ReleaseDate{{Date: 0, Platform: PlatformPlayStation5}},
			},
			expected: "2005-01-01",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.expected, FormatDate(playstationRelease(&tt.game)))
		})
	}
}

func Test_Rating(t *testing.T) {
	tests := []struct {
		name     string
		total    float64
		votes    int
		expected float64
	}{
		{name: "Rescales a well-voted rating to ten points", total: 87.5, votes: 400, expected: 8.75},
		{name: "Suppressed below the vote floor", total: 96.0, votes: minRatingVotes - 1, expected: 0},
		{name: "Suppressed when IGDB reports no rating", total: 0, votes: 900, expected: 0},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.InDelta(t, tt.expected, rating(tt.total, tt.votes), 0.001)
		})
	}
}

func Test_Minutes(t *testing.T) {
	tests := []struct {
		name        string
		seconds     int64
		submissions int
		expected    uint64
	}{
		{name: "Converts seconds to whole minutes", seconds: 7260, submissions: 50, expected: 121},
		{name: "Suppressed below the submission floor", seconds: 144000, submissions: minTimeToBeatSubmissions - 1, expected: 0},
		{name: "Suppressed when IGDB has no time", seconds: 0, submissions: 500, expected: 0},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.expected, minutes(tt.seconds, tt.submissions))
		})
	}
}

func Test_TransformGameList(t *testing.T) {
	t.Run("Nil result", func(t *testing.T) {
		assert.Empty(t, TransformGameList(nil))
	})

	t.Run("Drops cover-less rows and maps the rest", func(t *testing.T) {
		items := TransformGameList(&GameListResult{Results: []Game{
			{
				Id:               1,
				Name:             "Bloodborne",
				Cover:            Cover{ImageId: "co1abc"},
				TotalRating:      91.2,
				TotalRatingCount: 800,
				ReleaseDates:     []ReleaseDate{{Date: ps4Release, Platform: PlatformPlayStation4}},
			},
			{Id: 2, Name: "No Cover"},
		}})

		require.Len(t, items, 1)
		assert.Equal(t, uint64(1), items[0].Id)
		assert.Equal(t, "Bloodborne", items[0].Title)
		assert.Equal(t, "co1abc", items[0].PosterPath)
		assert.Equal(t, "2015-03-01", items[0].ReleaseDate)
		assert.InDelta(t, 9.12, items[0].Rating, 0.001)
	})
}

func Test_FormatDate(t *testing.T) {
	assert.Equal(t, "2023-03-01", FormatDate(ps5Release))
	assert.Empty(t, FormatDate(0))
}
