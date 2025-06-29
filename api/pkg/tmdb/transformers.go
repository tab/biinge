package tmdb

import (
	"sort"
	"time"
)

const (
	TMDBJobDirector              = "Director"
	TMDBJobDirectorOfPhotography = "Director of Photography"
	TMDBJobScreenplay            = "Screenplay"
	TMDBJobWriter                = "Writer"
	TMDBYoutubeType              = "YouTube"
	TMDBTrailerType              = "Trailer"
)

func UniqById[T any](items []T, idFunc func(T) int) []T {
	if len(items) == 0 {
		return items
	}

	seen := make(map[int]struct{})
	result := make([]T, 0, len(items))

	for _, item := range items {
		id := idFunc(item)
		if _, exists := seen[id]; !exists {
			seen[id] = struct{}{}
			result = append(result, item)
		}
	}

	return result
}

func TransformMovieDetails(movie *MovieDetails) *MovieResponse {
	if movie == nil {
		return nil
	}

	directorCredits := make([]CreditItem, 0)
	for _, crew := range movie.Credits.Crew {
		if crew.Job == TMDBJobDirector && crew.ProfilePath != "" {
			directorCredits = append(directorCredits, CreditItem{
				Id:          crew.Id,
				ProfilePath: crew.ProfilePath,
				Name:        crew.Name,
				Description: crew.Job,
			})
		}
	}

	castCredits := make([]CreditItem, 0)
	for _, cast := range movie.Credits.Cast {
		if cast.ProfilePath != "" {
			castCredits = append(castCredits, CreditItem{
				Id:          cast.Id,
				ProfilePath: cast.ProfilePath,
				Name:        cast.Name,
				Description: cast.Character,
			})
		}
	}

	crewCredits := make([]CreditItem, 0)
	for _, crew := range movie.Credits.Crew {
		if crew.ProfilePath != "" && (crew.Job == TMDBJobDirectorOfPhotography ||
			crew.Job == TMDBJobScreenplay ||
			crew.Job == TMDBJobWriter) {
			crewCredits = append(crewCredits, CreditItem{
				Id:          crew.Id,
				ProfilePath: crew.ProfilePath,
				Name:        crew.Name,
				Description: crew.Job,
			})
		}
	}

	recommendations := make([]RecommendationItem, 0)
	for _, rec := range movie.Recommendations.Results {
		if rec.PosterPath != "" {
			title := rec.Title
			if title == "" {
				title = rec.Name
			}

			recommendations = append(recommendations, RecommendationItem{
				Id:         rec.Id,
				Title:      title,
				PosterPath: rec.PosterPath,
			})
		}
	}

	videos := make([]VideoItem, 0)
	for _, video := range movie.Videos.Results {
		if video.Official && video.Site == TMDBYoutubeType && video.Type == TMDBTrailerType {
			videos = append(videos, VideoItem{
				Id:  video.Id,
				Key: video.Key,
			})
		}
	}

	allCredits := append(append(directorCredits, castCredits...), crewCredits...)
	uniqueCredits := UniqById(allCredits, func(c CreditItem) int {
		return c.Id
	})

	return &MovieResponse{
		Id:              movie.Id,
		Title:           movie.Title,
		Overview:        movie.Overview,
		PosterPath:      movie.PosterPath,
		Status:          movie.Status,
		ImdbId:          movie.ImdbId,
		ReleaseDate:     movie.ReleaseDate,
		Runtime:         movie.Runtime,
		Rating:          movie.VoteAverage,
		Credits:         uniqueCredits,
		Recommendations: recommendations,
		Videos:          videos,
	}
}

func ParseDate(dateStr string) (time.Time, error) {
	if dateStr == "" {
		return time.Time{}, nil
	}
	return time.Parse("2006-01-02", dateStr)
}

func FilterMovieCredits(credits []MovieCredit) []MovieCreditItem {
	filtered := make([]MovieCredit, 0)
	for _, credit := range credits {
		if !credit.Adult && credit.PosterPath != "" && credit.ReleaseDate != "" {
			filtered = append(filtered, credit)
		}
	}

	sort.Slice(filtered, func(i, j int) bool {
		dateA, errA := ParseDate(filtered[i].ReleaseDate)
		dateB, errB := ParseDate(filtered[j].ReleaseDate)

		if errA != nil || errB != nil {
			return false
		}

		return dateB.Before(dateA)
	})

	result := make([]MovieCreditItem, len(filtered))
	for i, credit := range filtered {
		creditType := credit.Character
		if credit.Job != "" {
			creditType = credit.Job
		}

		result[i] = MovieCreditItem{
			Id:         credit.Id,
			Title:      credit.Title,
			PosterPath: credit.PosterPath,
			Type:       creditType,
		}
	}

	return result
}

func FilterTvCredits(credits []TvCredit, excludedGenreIds []int) []TvCreditItem {
	filtered := make([]TvCredit, 0)
	for _, credit := range credits {
		if !credit.Adult && credit.PosterPath != "" && credit.FirstAirDate != "" && len(credit.GenreIds) > 0 {
			hasExcludedGenre := false
			for _, excludedId := range excludedGenreIds {
				for _, genreId := range credit.GenreIds {
					if genreId == excludedId {
						hasExcludedGenre = true
						break
					}
				}
				if hasExcludedGenre {
					break
				}
			}

			if !hasExcludedGenre {
				filtered = append(filtered, credit)
			}
		}
	}

	sort.Slice(filtered, func(i, j int) bool {
		dateA, errA := ParseDate(filtered[i].FirstAirDate)
		dateB, errB := ParseDate(filtered[j].FirstAirDate)

		if errA != nil || errB != nil {
			return false
		}

		return dateB.Before(dateA)
	})

	result := make([]TvCreditItem, len(filtered))
	for i, credit := range filtered {
		result[i] = TvCreditItem{
			Id:            credit.Id,
			Title:         credit.Name,
			PosterPath:    credit.PosterPath,
			EpisodesCount: credit.EpisodeCount,
		}
	}

	return result
}

func TransformPersonDetails(person *PersonDetails) *PersonResponse {
	if person == nil {
		return nil
	}

	castCredits := make([]MovieCredit, 0)
	castCredits = append(castCredits, person.Credits.Cast...)

	directorCredits := make([]MovieCredit, 0)
	for _, crew := range person.Credits.Crew {
		if crew.Job == TMDBJobDirector {
			directorCredits = append(directorCredits, crew)
		}
	}

	castCredits = append(castCredits, directorCredits...)
	movieCredits := FilterMovieCredits(castCredits)

	tvCastCredits := make([]TvCredit, 0)
	tvCastCredits = append(tvCastCredits, person.TvCredits.Cast...)

	tvDirectorCredits := make([]TvCredit, 0)
	for _, crew := range person.TvCredits.Crew {
		if crew.Job == TMDBJobDirector {
			tvDirectorCredits = append(tvDirectorCredits, crew)
		}
	}

	excludedGenreIds := []int{10767, 10763, 10764, 99} // Talk, News, Reality, Documentary

	tvCastCredits = append(tvCastCredits, tvDirectorCredits...)
	tvCredits := FilterTvCredits(tvCastCredits, excludedGenreIds)

	uniqueTvCredits := UniqById(tvCredits, func(c TvCreditItem) int {
		return c.Id
	})

	return &PersonResponse{
		Id:           person.Id,
		ImdbId:       person.ImdbId,
		Name:         person.Name,
		Birthday:     person.Birthday,
		ProfilePath:  person.ProfilePath,
		Gender:       person.Gender,
		MovieCredits: movieCredits,
		TvCredits:    uniqueTvCredits,
	}
}

func TransformTvDetails(tvShow *TvDetails) *TvResponse {
	if tvShow == nil {
		return nil
	}

	directorCredits := make([]CreditItem, 0)
	for _, crew := range tvShow.Credits.Crew {
		if crew.Job == TMDBJobDirector && crew.ProfilePath != "" {
			directorCredits = append(directorCredits, CreditItem{
				Id:          crew.Id,
				ProfilePath: crew.ProfilePath,
				Name:        crew.Name,
				Description: crew.Job,
			})
		}
	}

	castCredits := make([]CreditItem, 0)
	for _, cast := range tvShow.Credits.Cast {
		if cast.ProfilePath != "" {
			castCredits = append(castCredits, CreditItem{
				Id:          cast.Id,
				ProfilePath: cast.ProfilePath,
				Name:        cast.Name,
				Description: cast.Character,
			})
		}
	}

	crewCredits := make([]CreditItem, 0)
	for _, crew := range tvShow.Credits.Crew {
		if crew.ProfilePath != "" && (crew.Job == TMDBJobDirectorOfPhotography ||
			crew.Job == TMDBJobScreenplay ||
			crew.Job == TMDBJobWriter) {
			crewCredits = append(crewCredits, CreditItem{
				Id:          crew.Id,
				ProfilePath: crew.ProfilePath,
				Name:        crew.Name,
				Description: crew.Job,
			})
		}
	}

	recommendations := make([]RecommendationItem, 0)
	for _, rec := range tvShow.Recommendations.Results {
		if rec.PosterPath != "" {
			title := rec.Title
			if title == "" {
				title = rec.Name
			}

			recommendations = append(recommendations, RecommendationItem{
				Id:         rec.Id,
				Title:      title,
				PosterPath: rec.PosterPath,
			})
		}
	}

	videos := make([]VideoItem, 0)
	for _, video := range tvShow.Videos.Results {
		if video.Official && video.Site == TMDBYoutubeType && video.Type == TMDBTrailerType {
			videos = append(videos, VideoItem{
				Id:  video.Id,
				Key: video.Key,
			})
		}
	}

	allCredits := append(append(directorCredits, castCredits...), crewCredits...)
	uniqueCredits := UniqById(allCredits, func(c CreditItem) int {
		return c.Id
	})

	return &TvResponse{
		Id:              tvShow.Id,
		Title:           tvShow.Title,
		Overview:        tvShow.Overview,
		PosterPath:      tvShow.PosterPath,
		Status:          tvShow.Status,
		ImdbId:          tvShow.ImdbId,
		ReleaseDate:     tvShow.ReleaseDate,
		Rating:          tvShow.VoteAverage,
		Credits:         uniqueCredits,
		Recommendations: recommendations,
		Videos:          videos,
	}
}
