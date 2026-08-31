package igdb

import (
	"sort"
	"time"
)

// minRatingVotes is the vote floor below which IGDB's aggregate rating reflects a handful of people, not a consensus
const minRatingVotes = 5

// minTimeToBeatSubmissions is the submission floor below which a completion time is one player's playthrough
const minTimeToBeatSubmissions = 3

// igdbRatingScale converts IGDB's 0-100 rating to the 0-10 scale the clients already render
const igdbRatingScale = 10

func TransformGameDetails(details *GameDetails) *GameResponse {
	game := details.Game

	genres := make([]string, 0, len(game.Genres))
	for _, genre := range game.Genres {
		genres = append(genres, genreName(genre.Name))
	}

	platforms := make([]string, 0, len(game.Platforms))
	seen := make(map[string]bool, len(game.Platforms))

	// several IGDB names collapse onto one label, so the same one can arrive twice
	for _, platform := range game.Platforms {
		name := platformName(platform.Name)
		if seen[name] {
			continue
		}

		seen[name] = true
		platforms = append(platforms, name)
	}

	release := playstationRelease(&game)

	return &GameResponse{
		Id:               game.Id,
		Title:            game.Name,
		PosterPath:       game.Cover.ImageId,
		Overview:         game.Summary,
		Status:           gameStatus(game.GameStatus.Status, release),
		ReleaseDate:      FormatDate(release),
		Rating:           rating(game.TotalRating, game.TotalRatingCount),
		Runtime:          minutes(details.TimeToBeat.Normally, details.TimeToBeat.Count),
		RuntimeCompleted: minutes(details.TimeToBeat.Completely, details.TimeToBeat.Count),
		Genres:           genres,
		Platforms:        platforms,
		Recommendations:  recommendations(game.SimilarGames),
	}
}

// recommendations keeps the similar games playable on a PlayStation, best known first
func recommendations(similar []SimilarGame) []GameRecommendation {
	playable := make([]SimilarGame, 0, len(similar))

	for index := range similar {
		if isPlayableGame(&similar[index]) {
			playable = append(playable, similar[index])
		}
	}

	// IGDB returns similar_games unranked and the tail is mostly obscure keyword matches, so the
	// titles the most people have rated lead
	sort.SliceStable(playable, func(i, j int) bool {
		return playable[i].TotalRatingCount > playable[j].TotalRatingCount
	})

	items := make([]GameRecommendation, 0, len(playable))

	for _, game := range playable {
		items = append(items, GameRecommendation{
			Id:         game.Id,
			Title:      game.Name,
			PosterPath: game.Cover.ImageId,
		})
	}

	return items
}

// isPlayableGame mirrors playstationFilter for a nested similar_games row, which the query can't reach
func isPlayableGame(game *SimilarGame) bool {
	if game.Cover.ImageId == "" || game.VersionParent != 0 {
		return false
	}

	switch game.GameType {
	case gameTypeMain, gameTypeStandaloneExpansion, gameTypeRemake, gameTypeRemaster, gameTypeExpanded, gameTypePort:
	default:
		return false
	}

	for _, platform := range game.Platforms {
		if platform == PlatformPlayStation5 || platform == PlatformPlayStation4 {
			return true
		}
	}

	return false
}

func TransformGameList(result *GameListResult) []GameItem {
	if result == nil {
		return make([]GameItem, 0)
	}

	items := make([]GameItem, 0, len(result.Results))

	for _, game := range result.Results {
		if game.Cover.ImageId == "" {
			continue
		}

		items = append(items, GameItem{
			Id:          game.Id,
			Title:       game.Name,
			PosterPath:  game.Cover.ImageId,
			ReleaseDate: FormatDate(playstationRelease(&game)),
			Rating:      rating(game.TotalRating, game.TotalRatingCount),
		})
	}

	return items
}

// genreLabels renames the IGDB genres that don't read as a genre: the ones carrying their own acronym
// in brackets, and a handful whose wording is off (Platform sits right above the Platforms section, and
// Sport and Simulator are singular)
var genreLabels = map[string]string{
	// the other 14 of IGDB's 23 genres pass through untouched
	"Role-playing (RPG)":         "RPG",
	"Real Time Strategy (RTS)":   "RTS",
	"Turn-based strategy (TBS)":  "TBS",
	"Hack and slash/Beat 'em up": "Hack and Slash",
	"Card & Board Game":          "Card & Board",
	"Quiz/Trivia":                "Trivia",
	"Simulator":                  "Simulation",
	"Sport":                      "Sports",
	"Platform":                   "Platformer",
}

// genreName renames one IGDB genre
func genreName(name string) string {
	if label, ok := genreLabels[name]; ok {
		return label
	}

	return name
}

// platformLabels shortens the IGDB platform names a detail screen renders
var platformLabels = map[string]string{
	// PlayStation keeps its generation, since that is the one the user picks a game to play on;
	// every other family collapses to the family name, where the exact model changes nothing about
	// how the game is tracked. A name with no entry here passes through as IGDB wrote it
	"PlayStation":                         "PS1",
	"PlayStation 2":                       "PS2",
	"PlayStation 3":                       "PS3",
	"PlayStation 4":                       "PS4",
	"PlayStation 5":                       "PS5",
	"PlayStation Portable":                "PSP",
	"PlayStation Vita":                    "PS Vita",
	"PlayStation VR":                      "PS VR",
	"PlayStation VR2":                     "PS VR",
	"Xbox":                                "Xbox",
	"Xbox 360":                            "Xbox",
	"Xbox One":                            "Xbox",
	"Xbox Series X|S":                     "Xbox",
	"Nintendo Switch":                     "Nintendo",
	"Nintendo Switch 2":                   "Nintendo",
	"Nintendo 3DS":                        "Nintendo",
	"New Nintendo 3DS":                    "Nintendo",
	"Nintendo DS":                         "Nintendo",
	"Nintendo DSi":                        "Nintendo",
	"Nintendo 64":                         "Nintendo",
	"Nintendo GameCube":                   "Nintendo",
	"Nintendo Entertainment System":       "Nintendo",
	"Super Nintendo Entertainment System": "Nintendo",
	"Super Famicom":                       "Nintendo",
	"Famicom":                             "Nintendo",
	"Wii":                                 "Nintendo",
	"Wii U":                               "Nintendo",
	"Game Boy":                            "Nintendo",
	"Game Boy Color":                      "Nintendo",
	"Game Boy Advance":                    "Nintendo",
	"PC (Microsoft Windows)":              "PC",
	"DOS":                                 "PC",
}

// platformName shortens one IGDB platform name
func platformName(name string) string {
	if label, ok := platformLabels[name]; ok {
		return label
	}

	return name
}

// gameStatus is IGDB's status where it has one, otherwise what the release date says
func gameStatus(status string, release int64) string {
	// IGDB only records the exceptions — Early Access, Delisted, Cancelled — and leaves the status
	// empty on the 96% of games that released normally, so the date is the only thing left to read
	if status != "" {
		return status
	}

	switch {
	case release == 0:
		return ""
	case release > time.Now().Unix():
		return "Upcoming"
	default:
		return "Released"
	}
}

// playstationRelease returns the earliest PlayStation release, falling back to the game's first release anywhere
func playstationRelease(game *Game) int64 {
	var earliest int64

	for _, release := range game.ReleaseDates {
		if release.Platform != PlatformPlayStation5 && release.Platform != PlatformPlayStation4 {
			continue
		}

		if release.Date == 0 {
			continue
		}

		if earliest == 0 || release.Date < earliest {
			earliest = release.Date
		}
	}

	if earliest == 0 {
		return game.FirstReleaseDate
	}

	return earliest
}

// FormatDate renders a Unix timestamp as an ISO date, the string shape the clients already parse
func FormatDate(timestamp int64) string {
	if timestamp == 0 {
		return ""
	}

	return time.Unix(timestamp, 0).UTC().Format(time.DateOnly)
}

// rating rescales IGDB's 0-100 aggregate, suppressing it when too few votes stand behind it
func rating(total float64, votes int) float64 {
	if votes < minRatingVotes || total <= 0 {
		return 0
	}

	return total / igdbRatingScale
}

// minutes converts an IGDB completion time from seconds, suppressing it when too few submissions stand behind it
func minutes(seconds int64, submissions int) uint64 {
	if submissions < minTimeToBeatSubmissions || seconds <= 0 {
		return 0
	}

	return uint64(seconds / 60)
}
