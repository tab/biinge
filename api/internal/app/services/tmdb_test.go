package services

import (
	"context"
	"testing"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/models"
	"biinge-api/internal/app/serializers"
	"biinge-api/internal/config/cache"
	"biinge-api/pkg/tmdb"
)

// --- sample TMDB client responses ---

func sampleMovieDetails() *tmdb.MovieDetails {
	return &tmdb.MovieDetails{
		Id:          100,
		Title:       "The Matrix",
		Overview:    "A hacker learns the truth.",
		PosterPath:  "/tmdb-poster.jpg",
		Status:      "Released",
		ImdbId:      "tt0133093",
		ReleaseDate: "1999-03-31",
		Runtime:     136,
		VoteAverage: 8.7,
		Credits: tmdb.Credits{
			Cast: []tmdb.PersonCast{
				{Person: tmdb.Person{Id: 1, Name: "Keanu Reeves", ProfilePath: "/keanu.jpg"}, Character: "Neo"},
			},
			Crew: []tmdb.PersonCrew{
				{Person: tmdb.Person{Id: 2, Name: "Lana Wachowski", ProfilePath: "/lana.jpg"}, Job: tmdb.TMDBJobDirector},
			},
		},
		Recommendations: tmdb.Recommendations{
			Results: []tmdb.Recommendation{
				{Id: 200, Title: "John Wick", PosterPath: "/jw.jpg"},
			},
		},
		Videos: tmdb.Videos{
			Results: []tmdb.Video{
				{Id: "v1", Key: "abc123", Site: tmdb.TMDBYoutubeType, Type: tmdb.TMDBTrailerType, Official: true},
			},
		},
	}
}

func sampleTvDetails() *tmdb.TvDetails {
	return &tmdb.TvDetails{
		Id:            300,
		Title:         "Breaking Bad",
		Overview:      "A chemistry teacher turns to crime.",
		PosterPath:    "/bb-tmdb.jpg",
		Status:        "Ended",
		ImdbId:        "tt0903747",
		ReleaseDate:   "2008-01-20",
		VoteAverage:   9.5,
		SeasonsCount:  5,
		EpisodesCount: 62,
		Credits: tmdb.Credits{
			Cast: []tmdb.PersonCast{
				{Person: tmdb.Person{Id: 5, Name: "Bryan Cranston", ProfilePath: "/bc.jpg"}, Character: "Walter White"},
			},
			Crew: []tmdb.PersonCrew{
				{Person: tmdb.Person{Id: 6, Name: "Vince Gilligan", ProfilePath: "/vg.jpg"}, Job: tmdb.TMDBJobDirector},
			},
		},
		Recommendations: tmdb.Recommendations{
			Results: []tmdb.Recommendation{
				{Id: 400, Name: "Better Call Saul", PosterPath: "/bcs.jpg"},
			},
		},
		Videos: tmdb.Videos{
			Results: []tmdb.Video{
				{Id: "tv1", Key: "tvkey", Site: tmdb.TMDBYoutubeType, Type: tmdb.TMDBTrailerType, Official: true},
			},
		},
		Seasons: []tmdb.TvSeason{
			{Id: 50, Name: "Season 1", SeasonNumber: 1, EpisodeCount: 7, PosterPath: "/s1.jpg", AirDate: "2008-01-20"},
		},
	}
}

func samplePersonDetails() *tmdb.PersonDetails {
	return &tmdb.PersonDetails{
		Id:          500,
		ImdbId:      "nm0000206",
		Name:        "Keanu Reeves",
		Birthday:    "1964-09-02",
		ProfilePath: "/keanu.jpg",
		Gender:      2,
		Credits: tmdb.PersonMovieCredits{
			Cast: []tmdb.MovieCredit{
				{Id: 600, Title: "The Matrix", PosterPath: "/m.jpg", ReleaseDate: "1999-03-31", Character: "Neo"},
			},
		},
		TvCredits: tmdb.PersonTvCredits{
			Cast: []tmdb.TvCredit{
				{Id: 700, Name: "Some Show", PosterPath: "/tv.jpg", FirstAirDate: "2010-01-01", GenreIds: []int{18}, EpisodeCount: 10, Character: "Self"},
			},
		},
	}
}

func sampleSeasonDetails() *tmdb.SeasonDetails {
	return &tmdb.SeasonDetails{
		ID:           50,
		AirDate:      "2008-01-20",
		Name:         "Season 1",
		Overview:     "The first season.",
		PosterPath:   "/s1.jpg",
		SeasonNumber: 1,
		Episodes: []tmdb.Episode{
			{ID: 80, AirDate: "2008-01-20", EpisodeNumber: 1, Name: "Pilot", Overview: "The pilot.", Runtime: 58, StillPath: "/e1.jpg", VoteAverage: 8.0},
		},
	}
}

func sampleEpisodeDetails() *tmdb.EpisodeDetails {
	return &tmdb.EpisodeDetails{
		ID:            80,
		AirDate:       "2008-01-20",
		EpisodeNumber: 1,
		Name:          "Pilot",
		Overview:      "The pilot.",
		Runtime:       58,
		StillPath:     "/e1.jpg",
		VoteAverage:   8.0,
		Credits: tmdb.Credits{
			Cast: []tmdb.PersonCast{
				{Person: tmdb.Person{Id: 5, Name: "Bryan Cranston", ProfilePath: "/bc.jpg"}, Character: "Walter White"},
			},
			Crew: []tmdb.PersonCrew{
				{Person: tmdb.Person{Id: 6, Name: "Vince Gilligan", ProfilePath: "/vg.jpg"}, Job: tmdb.TMDBJobDirector},
			},
		},
		Videos: tmdb.Videos{
			Results: []tmdb.Video{
				{Id: "ev1", Key: "evkey", Site: tmdb.TMDBYoutubeType, Type: tmdb.TMDBTrailerType, Official: true},
			},
		},
	}
}

func sampleMovieListResult() *tmdb.MovieListResult {
	return &tmdb.MovieListResult{
		Page:         1,
		TotalResults: 4,
		Results: []tmdb.MovieListItem{
			{Id: 100, Title: "The Matrix", PosterPath: "/m.jpg", ReleaseDate: "1999-03-31", VoteAverage: 8.7},
			{Id: 103, Title: "Untracked", PosterPath: "/u.jpg", ReleaseDate: "2020-01-01", VoteAverage: 6.0},
			{Id: 101, Title: "No Poster", PosterPath: ""},
			{Id: 102, Title: "Adult", PosterPath: "/a.jpg", Adult: true},
		},
	}
}

func sampleTvListResult() *tmdb.TvListResult {
	return &tmdb.TvListResult{
		Page:         1,
		TotalResults: 4,
		Results: []tmdb.TvListItem{
			{Id: 300, Name: "Breaking Bad", PosterPath: "/bb.jpg", FirstAirDate: "2008-01-20", VoteAverage: 9.5},
			{Id: 303, Name: "Untracked Show", PosterPath: "/us.jpg", FirstAirDate: "2021-01-01", VoteAverage: 7.0},
			{Id: 301, Name: "No Poster", PosterPath: ""},
			{Id: 302, Name: "Adult", PosterPath: "/a.jpg", Adult: true},
		},
	}
}

// --- expected serializer fragments ---

func expectedMovieCredits() []serializers.PersonSerializer {
	return []serializers.PersonSerializer{
		{Id: 2, Name: "Lana Wachowski", Description: "Director", ProfilePath: "/lana.jpg"},
		{Id: 1, Name: "Keanu Reeves", Description: "Neo", ProfilePath: "/keanu.jpg"},
	}
}

func expectedTvCredits() []serializers.PersonSerializer {
	return []serializers.PersonSerializer{
		{Id: 6, Name: "Vince Gilligan", Description: "Director", ProfilePath: "/vg.jpg"},
		{Id: 5, Name: "Bryan Cranston", Description: "Walter White", ProfilePath: "/bc.jpg"},
	}
}

func expectedMovieRecommendations(state models.StateType) []serializers.RecommendationSerializer {
	return []serializers.RecommendationSerializer{
		{Id: 200, Title: "John Wick", PosterPath: "/jw.jpg", State: state},
	}
}

func expectedTvRecommendations(state models.StateType) []serializers.RecommendationSerializer {
	return []serializers.RecommendationSerializer{
		{Id: 400, Title: "Better Call Saul", PosterPath: "/bcs.jpg", State: state},
	}
}

func expectedTvSeasons() []serializers.SeasonSummarySerializer {
	return []serializers.SeasonSummarySerializer{
		{Id: 50, Title: "Season 1", Number: 1, PosterPath: "/s1.jpg", EpisodesCount: 7, AirDate: "2008-01-20"},
	}
}

func expectedMovieVideos() []serializers.VideoSerializer {
	return []serializers.VideoSerializer{{Id: "v1", Key: "abc123"}}
}

func expectedTvVideos() []serializers.VideoSerializer {
	return []serializers.VideoSerializer{{Id: "tv1", Key: "tvkey"}}
}

func Test_Tmdb_FetchMovieDetails(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	client := tmdb.NewMockClient(ctrl)
	moviesSvc := NewMockMovies(ctrl)
	seriesSvc := NewMockSeries(ctrl)
	progressSvc := NewMockProgress(ctrl)
	provider := NewTmdbProvider(client, moviesSvc, seriesSvc, progressSvc, cache.NewNoopCache(), newTestLogger())

	userId := uuid.New()
	movieID := uuid.New()

	tests := []struct {
		name     string
		before   func()
		expected *serializers.MovieDetailsSerializer
		error    error
	}{
		{
			name: "Found - read-repair updates stale poster",
			before: func() {
				client.EXPECT().FetchMovieDetails(ctx, uint64(100)).Return(sampleMovieDetails(), nil)

				moviesSvc.EXPECT().FindMoviesByTmdbIds(ctx, []uint64{200}, userId).Return([]models.Movie{
					{TmdbId: 200, State: "want"},
				}, nil)
				moviesSvc.EXPECT().FindByTmdbId(ctx, uint64(100), userId).Return(&models.Movie{
					ID: movieID, TmdbId: 100, Title: "Old Title", PosterPath: "/old-poster.jpg", Runtime: 100, State: "watched", Pinned: true,
				}, nil)
				moviesSvc.EXPECT().Update(ctx, &models.Movie{
					ID: movieID, Title: "The Matrix", PosterPath: "/tmdb-poster.jpg", Runtime: 136,
				}).Return(&models.Movie{}, nil)
			},
			expected: &serializers.MovieDetailsSerializer{
				Id:              100,
				Pinned:          true,
				State:           "watched",
				Status:          "Released",
				Title:           "The Matrix",
				PosterPath:      "/tmdb-poster.jpg",
				Overview:        "A hacker learns the truth.",
				ReleaseDate:     "1999-03-31",
				Runtime:         136,
				Rating:          8.7,
				Credits:         expectedMovieCredits(),
				Recommendations: expectedMovieRecommendations("want"),
				Videos:          expectedMovieVideos(),
			},
		},
		{
			name: "Found - poster matches, no update",
			before: func() {
				client.EXPECT().FetchMovieDetails(ctx, uint64(100)).Return(sampleMovieDetails(), nil)

				moviesSvc.EXPECT().FindMoviesByTmdbIds(ctx, []uint64{200}, userId).Return([]models.Movie{}, nil)
				moviesSvc.EXPECT().FindByTmdbId(ctx, uint64(100), userId).Return(&models.Movie{
					ID: movieID, TmdbId: 100, Title: "The Matrix", PosterPath: "/tmdb-poster.jpg", Runtime: 136, State: "want",
				}, nil)
			},
			expected: &serializers.MovieDetailsSerializer{
				Id:              100,
				Pinned:          false,
				State:           "want",
				Status:          "Released",
				Title:           "The Matrix",
				PosterPath:      "/tmdb-poster.jpg",
				Overview:        "A hacker learns the truth.",
				ReleaseDate:     "1999-03-31",
				Runtime:         136,
				Rating:          8.7,
				Credits:         expectedMovieCredits(),
				Recommendations: expectedMovieRecommendations("none"),
				Videos:          expectedMovieVideos(),
			},
		},
		{
			name: "Found - read-repair falls back to stored title and runtime",
			before: func() {
				response := sampleMovieDetails()
				response.Title = ""
				response.Runtime = 0
				response.PosterPath = "/new-poster.jpg"

				client.EXPECT().FetchMovieDetails(ctx, uint64(100)).Return(response, nil)

				moviesSvc.EXPECT().FindMoviesByTmdbIds(ctx, []uint64{200}, userId).Return([]models.Movie{}, nil)
				moviesSvc.EXPECT().FindByTmdbId(ctx, uint64(100), userId).Return(&models.Movie{
					ID: movieID, TmdbId: 100, Title: "Stored Title", PosterPath: "/old.jpg", Runtime: 90, State: "want",
				}, nil)
				moviesSvc.EXPECT().Update(ctx, &models.Movie{
					ID: movieID, Title: "Stored Title", PosterPath: "/new-poster.jpg", Runtime: 90,
				}).Return(&models.Movie{}, nil)
			},
			expected: &serializers.MovieDetailsSerializer{
				Id:              100,
				Pinned:          false,
				State:           "want",
				Status:          "Released",
				Title:           "",
				PosterPath:      "/new-poster.jpg",
				Overview:        "A hacker learns the truth.",
				ReleaseDate:     "1999-03-31",
				Runtime:         0,
				Rating:          8.7,
				Credits:         expectedMovieCredits(),
				Recommendations: expectedMovieRecommendations("none"),
				Videos:          expectedMovieVideos(),
			},
		},
		{
			name: "Found - read-repair update error is tolerated",
			before: func() {
				client.EXPECT().FetchMovieDetails(ctx, uint64(100)).Return(sampleMovieDetails(), nil)

				moviesSvc.EXPECT().FindMoviesByTmdbIds(ctx, []uint64{200}, userId).Return([]models.Movie{}, nil)
				moviesSvc.EXPECT().FindByTmdbId(ctx, uint64(100), userId).Return(&models.Movie{
					ID: movieID, TmdbId: 100, Title: "Old", PosterPath: "/old.jpg", Runtime: 100, State: "watched", Pinned: true,
				}, nil)
				moviesSvc.EXPECT().Update(ctx, gomock.Any()).Return(nil, assert.AnError)
			},
			expected: &serializers.MovieDetailsSerializer{
				Id:              100,
				Pinned:          true,
				State:           "watched",
				Status:          "Released",
				Title:           "The Matrix",
				PosterPath:      "/tmdb-poster.jpg",
				Overview:        "A hacker learns the truth.",
				ReleaseDate:     "1999-03-31",
				Runtime:         136,
				Rating:          8.7,
				Credits:         expectedMovieCredits(),
				Recommendations: expectedMovieRecommendations("none"),
				Videos:          expectedMovieVideos(),
			},
		},
		{
			name: "Not found returns none state",
			before: func() {
				client.EXPECT().FetchMovieDetails(ctx, uint64(100)).Return(sampleMovieDetails(), nil)

				moviesSvc.EXPECT().FindMoviesByTmdbIds(ctx, []uint64{200}, userId).Return([]models.Movie{
					{TmdbId: 200, State: "want"},
				}, nil)
				moviesSvc.EXPECT().FindByTmdbId(ctx, uint64(100), userId).Return(nil, errors.ErrMovieNotFound)
			},
			expected: &serializers.MovieDetailsSerializer{
				Id:              100,
				Pinned:          false,
				State:           "none",
				Status:          "Released",
				Title:           "The Matrix",
				PosterPath:      "/tmdb-poster.jpg",
				Overview:        "A hacker learns the truth.",
				ReleaseDate:     "1999-03-31",
				Runtime:         136,
				Rating:          8.7,
				Credits:         expectedMovieCredits(),
				Recommendations: expectedMovieRecommendations("want"),
				Videos:          expectedMovieVideos(),
			},
		},
		{
			name: "Client error - serves stored library data",
			before: func() {
				client.EXPECT().FetchMovieDetails(ctx, uint64(100)).Return(nil, assert.AnError)

				moviesSvc.EXPECT().FindByTmdbId(ctx, uint64(100), userId).Return(&models.Movie{
					ID: movieID, TmdbId: 100, Title: "Stored Title", PosterPath: "/stored.jpg", Runtime: 120, State: "watched", Pinned: true,
				}, nil)
			},
			expected: &serializers.MovieDetailsSerializer{
				Id:              100,
				Pinned:          true,
				State:           "watched",
				Title:           "Stored Title",
				PosterPath:      "/stored.jpg",
				Runtime:         120,
				Credits:         []serializers.PersonSerializer{},
				Recommendations: []serializers.RecommendationSerializer{},
				Videos:          []serializers.VideoSerializer{},
			},
		},
		{
			name: "Client error - not in library returns error",
			before: func() {
				client.EXPECT().FetchMovieDetails(ctx, uint64(100)).Return(nil, assert.AnError)

				moviesSvc.EXPECT().FindByTmdbId(ctx, uint64(100), userId).Return(nil, errors.ErrMovieNotFound)
			},
			expected: nil,
			error:    tmdb.ErrFailedToFetchMovieDetails,
		},
		{
			name: "Recommendation state lookup error",
			before: func() {
				client.EXPECT().FetchMovieDetails(ctx, uint64(100)).Return(sampleMovieDetails(), nil)

				moviesSvc.EXPECT().FindMoviesByTmdbIds(ctx, []uint64{200}, userId).Return(nil, assert.AnError)
			},
			expected: nil,
			error:    errors.ErrFailedToFetchResults,
		},
		{
			name: "Movie state lookup error",
			before: func() {
				client.EXPECT().FetchMovieDetails(ctx, uint64(100)).Return(sampleMovieDetails(), nil)

				moviesSvc.EXPECT().FindMoviesByTmdbIds(ctx, []uint64{200}, userId).Return([]models.Movie{}, nil)
				moviesSvc.EXPECT().FindByTmdbId(ctx, uint64(100), userId).Return(nil, assert.AnError)
			},
			expected: nil,
			error:    errors.ErrFailedToFetchMovie,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, err := provider.FetchMovieDetails(ctx, 100, userId)

			if tt.error != nil {
				require.ErrorIs(t, err, tt.error)
				assert.Nil(t, result)
			} else {
				require.NoError(t, err)
				assert.Equal(t, tt.expected, result)
			}
		})
	}
}

func Test_Tmdb_FetchTvDetails(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	client := tmdb.NewMockClient(ctrl)
	moviesSvc := NewMockMovies(ctrl)
	seriesSvc := NewMockSeries(ctrl)
	progressSvc := NewMockProgress(ctrl)
	provider := NewTmdbProvider(client, moviesSvc, seriesSvc, progressSvc, cache.NewNoopCache(), newTestLogger())

	userId := uuid.New()
	seriesID := uuid.New()

	tests := []struct {
		name     string
		before   func()
		expected *serializers.SeriesDetailsSerializer
		error    error
	}{
		{
			name: "Found - read-repair updates stale poster",
			before: func() {
				client.EXPECT().FetchTvDetails(ctx, uint64(300)).Return(sampleTvDetails(), nil)

				seriesSvc.EXPECT().FindSeriesByTmdbIds(ctx, []uint64{400}, userId).Return([]models.Series{
					{TmdbId: 400, State: "want"},
				}, nil)
				seriesSvc.EXPECT().FindByTmdbId(ctx, uint64(300), userId).Return(&models.Series{
					ID: seriesID, TmdbId: 300, Title: "Old", PosterPath: "/old.jpg", SeasonsCount: 5, EpisodesCount: 62, Status: "Old Status", State: "watching", Pinned: true,
				}, nil)
				seriesSvc.EXPECT().Update(ctx, &models.Series{
					ID: seriesID, Title: "Breaking Bad", PosterPath: "/bb-tmdb.jpg", SeasonsCount: 5, EpisodesCount: 62, Status: "Ended",
				}).Return(&models.Series{}, nil)
			},
			expected: &serializers.SeriesDetailsSerializer{
				Id:              300,
				Pinned:          true,
				State:           "watching",
				Status:          "Ended",
				Title:           "Breaking Bad",
				PosterPath:      "/bb-tmdb.jpg",
				Overview:        "A chemistry teacher turns to crime.",
				ReleaseDate:     "2008-01-20",
				SeasonsCount:    5,
				EpisodesCount:   62,
				Rating:          9.5,
				Credits:         expectedTvCredits(),
				Recommendations: expectedTvRecommendations("want"),
				Videos:          expectedTvVideos(),
				Seasons:         expectedTvSeasons(),
			},
		},
		{
			name: "Found - poster matches, no update",
			before: func() {
				client.EXPECT().FetchTvDetails(ctx, uint64(300)).Return(sampleTvDetails(), nil)

				seriesSvc.EXPECT().FindSeriesByTmdbIds(ctx, []uint64{400}, userId).Return([]models.Series{}, nil)
				seriesSvc.EXPECT().FindByTmdbId(ctx, uint64(300), userId).Return(&models.Series{
					ID: seriesID, TmdbId: 300, Title: "Breaking Bad", PosterPath: "/bb-tmdb.jpg", SeasonsCount: 5, EpisodesCount: 62, Status: "Ended", State: "watched",
				}, nil)
			},
			expected: &serializers.SeriesDetailsSerializer{
				Id:              300,
				Pinned:          false,
				State:           "watched",
				Status:          "Ended",
				Title:           "Breaking Bad",
				PosterPath:      "/bb-tmdb.jpg",
				Overview:        "A chemistry teacher turns to crime.",
				ReleaseDate:     "2008-01-20",
				SeasonsCount:    5,
				EpisodesCount:   62,
				Rating:          9.5,
				Credits:         expectedTvCredits(),
				Recommendations: expectedTvRecommendations("none"),
				Videos:          expectedTvVideos(),
				Seasons:         expectedTvSeasons(),
			},
		},
		{
			name: "Found - read-repair falls back to stored title and status",
			before: func() {
				response := sampleTvDetails()
				response.Title = ""
				response.Status = ""
				response.PosterPath = "/new.jpg"

				client.EXPECT().FetchTvDetails(ctx, uint64(300)).Return(response, nil)

				seriesSvc.EXPECT().FindSeriesByTmdbIds(ctx, []uint64{400}, userId).Return([]models.Series{}, nil)
				seriesSvc.EXPECT().FindByTmdbId(ctx, uint64(300), userId).Return(&models.Series{
					ID: seriesID, TmdbId: 300, Title: "Stored Title", PosterPath: "/old.jpg", SeasonsCount: 5, EpisodesCount: 62, Status: "Stored Status", State: "watching",
				}, nil)
				seriesSvc.EXPECT().Update(ctx, &models.Series{
					ID: seriesID, Title: "Stored Title", PosterPath: "/new.jpg", SeasonsCount: 5, EpisodesCount: 62, Status: "Stored Status",
				}).Return(&models.Series{}, nil)
			},
			expected: &serializers.SeriesDetailsSerializer{
				Id:              300,
				Pinned:          false,
				State:           "watching",
				Status:          "",
				Title:           "",
				PosterPath:      "/new.jpg",
				Overview:        "A chemistry teacher turns to crime.",
				ReleaseDate:     "2008-01-20",
				SeasonsCount:    5,
				EpisodesCount:   62,
				Rating:          9.5,
				Credits:         expectedTvCredits(),
				Recommendations: expectedTvRecommendations("none"),
				Videos:          expectedTvVideos(),
				Seasons:         expectedTvSeasons(),
			},
		},
		{
			name: "Found - read-repair update error is tolerated",
			before: func() {
				client.EXPECT().FetchTvDetails(ctx, uint64(300)).Return(sampleTvDetails(), nil)

				seriesSvc.EXPECT().FindSeriesByTmdbIds(ctx, []uint64{400}, userId).Return([]models.Series{}, nil)
				seriesSvc.EXPECT().FindByTmdbId(ctx, uint64(300), userId).Return(&models.Series{
					ID: seriesID, TmdbId: 300, Title: "Old", PosterPath: "/old.jpg", SeasonsCount: 5, EpisodesCount: 62, Status: "Ended", State: "watched", Pinned: true,
				}, nil)
				seriesSvc.EXPECT().Update(ctx, gomock.Any()).Return(nil, assert.AnError)
			},
			expected: &serializers.SeriesDetailsSerializer{
				Id:              300,
				Pinned:          true,
				State:           "watched",
				Status:          "Ended",
				Title:           "Breaking Bad",
				PosterPath:      "/bb-tmdb.jpg",
				Overview:        "A chemistry teacher turns to crime.",
				ReleaseDate:     "2008-01-20",
				SeasonsCount:    5,
				EpisodesCount:   62,
				Rating:          9.5,
				Credits:         expectedTvCredits(),
				Recommendations: expectedTvRecommendations("none"),
				Videos:          expectedTvVideos(),
				Seasons:         expectedTvSeasons(),
			},
		},
		{
			name: "Not found returns none state",
			before: func() {
				client.EXPECT().FetchTvDetails(ctx, uint64(300)).Return(sampleTvDetails(), nil)

				seriesSvc.EXPECT().FindSeriesByTmdbIds(ctx, []uint64{400}, userId).Return([]models.Series{
					{TmdbId: 400, State: "want"},
				}, nil)
				seriesSvc.EXPECT().FindByTmdbId(ctx, uint64(300), userId).Return(nil, errors.ErrSeriesNotFound)
			},
			expected: &serializers.SeriesDetailsSerializer{
				Id:              300,
				Pinned:          false,
				State:           "none",
				Status:          "Ended",
				Title:           "Breaking Bad",
				PosterPath:      "/bb-tmdb.jpg",
				Overview:        "A chemistry teacher turns to crime.",
				ReleaseDate:     "2008-01-20",
				SeasonsCount:    5,
				EpisodesCount:   62,
				Rating:          9.5,
				Credits:         expectedTvCredits(),
				Recommendations: expectedTvRecommendations("want"),
				Videos:          expectedTvVideos(),
				Seasons:         expectedTvSeasons(),
			},
		},
		{
			name: "Client error - serves stored library data",
			before: func() {
				client.EXPECT().FetchTvDetails(ctx, uint64(300)).Return(nil, assert.AnError)

				seriesSvc.EXPECT().FindByTmdbId(ctx, uint64(300), userId).Return(&models.Series{
					ID: seriesID, TmdbId: 300, Title: "Stored Title", PosterPath: "/stored.jpg", SeasonsCount: 5, EpisodesCount: 62, Status: "Ended", State: "watched", Pinned: true,
				}, nil)
			},
			expected: &serializers.SeriesDetailsSerializer{
				Id:              300,
				Pinned:          true,
				State:           "watched",
				Status:          "Ended",
				Title:           "Stored Title",
				PosterPath:      "/stored.jpg",
				SeasonsCount:    5,
				EpisodesCount:   62,
				Credits:         []serializers.PersonSerializer{},
				Recommendations: []serializers.RecommendationSerializer{},
				Videos:          []serializers.VideoSerializer{},
				Seasons:         []serializers.SeasonSummarySerializer{},
			},
		},
		{
			name: "Client error - not in library returns error",
			before: func() {
				client.EXPECT().FetchTvDetails(ctx, uint64(300)).Return(nil, assert.AnError)

				seriesSvc.EXPECT().FindByTmdbId(ctx, uint64(300), userId).Return(nil, errors.ErrSeriesNotFound)
			},
			expected: nil,
			error:    tmdb.ErrFailedToFetchTvDetails,
		},
		{
			name: "Recommendation state lookup error",
			before: func() {
				client.EXPECT().FetchTvDetails(ctx, uint64(300)).Return(sampleTvDetails(), nil)

				seriesSvc.EXPECT().FindSeriesByTmdbIds(ctx, []uint64{400}, userId).Return(nil, assert.AnError)
			},
			expected: nil,
			error:    errors.ErrFailedToFetchResults,
		},
		{
			name: "Series state lookup error",
			before: func() {
				client.EXPECT().FetchTvDetails(ctx, uint64(300)).Return(sampleTvDetails(), nil)

				seriesSvc.EXPECT().FindSeriesByTmdbIds(ctx, []uint64{400}, userId).Return([]models.Series{}, nil)
				seriesSvc.EXPECT().FindByTmdbId(ctx, uint64(300), userId).Return(nil, assert.AnError)
			},
			expected: nil,
			error:    errors.ErrFailedToFetchSeries,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, err := provider.FetchTvDetails(ctx, 300, userId)

			if tt.error != nil {
				require.ErrorIs(t, err, tt.error)
				assert.Nil(t, result)
			} else {
				require.NoError(t, err)
				assert.Equal(t, tt.expected, result)
			}
		})
	}
}

func Test_Tmdb_FetchPersonDetails(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	client := tmdb.NewMockClient(ctrl)
	moviesSvc := NewMockMovies(ctrl)
	seriesSvc := NewMockSeries(ctrl)
	progressSvc := NewMockProgress(ctrl)
	provider := NewTmdbProvider(client, moviesSvc, seriesSvc, progressSvc, cache.NewNoopCache(), newTestLogger())

	userId := uuid.New()

	tests := []struct {
		name     string
		before   func()
		expected *serializers.PersonDetailsSerializer
		error    error
	}{
		{
			name: "Success with tracking state",
			before: func() {
				client.EXPECT().FetchPersonDetails(ctx, uint64(500)).Return(samplePersonDetails(), nil)

				moviesSvc.EXPECT().FindMoviesByTmdbIds(ctx, []uint64{600}, userId).Return([]models.Movie{
					{TmdbId: 600, State: "watched"},
				}, nil)
				seriesSvc.EXPECT().FindSeriesByTmdbIds(ctx, []uint64{700}, userId).Return([]models.Series{
					{TmdbId: 700, State: "want"},
				}, nil)
			},
			expected: &serializers.PersonDetailsSerializer{
				Id:          500,
				Name:        "Keanu Reeves",
				Birthday:    "1964-09-02",
				ProfilePath: "/keanu.jpg",
				Gender:      2,
				MovieCredits: []serializers.MovieCreditSerializer{
					{Id: 600, Title: "The Matrix", PosterPath: "/m.jpg", State: "watched", Type: "Neo"},
				},
				TvCredits: []serializers.TvCreditSerializer{
					{Id: 700, Title: "Some Show", PosterPath: "/tv.jpg", State: "want", EpisodesCount: 10},
				},
			},
		},
		{
			name: "Success without tracking state",
			before: func() {
				client.EXPECT().FetchPersonDetails(ctx, uint64(500)).Return(samplePersonDetails(), nil)

				moviesSvc.EXPECT().FindMoviesByTmdbIds(ctx, []uint64{600}, userId).Return([]models.Movie{}, nil)
				seriesSvc.EXPECT().FindSeriesByTmdbIds(ctx, []uint64{700}, userId).Return([]models.Series{}, nil)
			},
			expected: &serializers.PersonDetailsSerializer{
				Id:          500,
				Name:        "Keanu Reeves",
				Birthday:    "1964-09-02",
				ProfilePath: "/keanu.jpg",
				Gender:      2,
				MovieCredits: []serializers.MovieCreditSerializer{
					{Id: 600, Title: "The Matrix", PosterPath: "/m.jpg", State: "none", Type: "Neo"},
				},
				TvCredits: []serializers.TvCreditSerializer{
					{Id: 700, Title: "Some Show", PosterPath: "/tv.jpg", State: "none", EpisodesCount: 10},
				},
			},
		},
		{
			name: "Client error",
			before: func() {
				client.EXPECT().FetchPersonDetails(ctx, uint64(500)).Return(nil, assert.AnError)
			},
			expected: nil,
			error:    tmdb.ErrFailedToFetchPersonDetails,
		},
		{
			name: "Movie credit state lookup error",
			before: func() {
				client.EXPECT().FetchPersonDetails(ctx, uint64(500)).Return(samplePersonDetails(), nil)

				moviesSvc.EXPECT().FindMoviesByTmdbIds(ctx, []uint64{600}, userId).Return(nil, assert.AnError)
			},
			expected: nil,
			error:    errors.ErrFailedToFetchResults,
		},
		{
			name: "Tv credit state lookup error",
			before: func() {
				client.EXPECT().FetchPersonDetails(ctx, uint64(500)).Return(samplePersonDetails(), nil)

				moviesSvc.EXPECT().FindMoviesByTmdbIds(ctx, []uint64{600}, userId).Return([]models.Movie{}, nil)
				seriesSvc.EXPECT().FindSeriesByTmdbIds(ctx, []uint64{700}, userId).Return(nil, assert.AnError)
			},
			expected: nil,
			error:    errors.ErrFailedToFetchResults,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, err := provider.FetchPersonDetails(ctx, 500, userId)

			if tt.error != nil {
				require.ErrorIs(t, err, tt.error)
				assert.Nil(t, result)
			} else {
				require.NoError(t, err)
				assert.Equal(t, tt.expected, result)
			}
		})
	}
}

func Test_Tmdb_FetchTvSeasonDetails(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	client := tmdb.NewMockClient(ctrl)
	moviesSvc := NewMockMovies(ctrl)
	seriesSvc := NewMockSeries(ctrl)
	progressSvc := NewMockProgress(ctrl)
	provider := NewTmdbProvider(client, moviesSvc, seriesSvc, progressSvc, cache.NewNoopCache(), newTestLogger())
	userId := uuid.New()

	tests := []struct {
		name     string
		before   func()
		expected *serializers.SeasonDetailsSerializer
		error    error
	}{
		{
			name: "Success merges watched state",
			before: func() {
				client.EXPECT().FetchTvSeasonDetails(ctx, uint64(300), uint64(1)).Return(sampleSeasonDetails(), nil)
				progressSvc.EXPECT().Get(ctx, userId, uint64(300)).Return(&models.SeriesProgress{
					WatchedSeasons:  []uint64{50},
					WatchedEpisodes: []uint64{80},
				}, nil)
			},
			expected: &serializers.SeasonDetailsSerializer{
				Id:         50,
				TmdbShowId: 300,
				Title:      "Season 1",
				Number:     1,
				PosterPath: "/s1.jpg",
				AirDate:    "2008-01-20",
				Overview:   "The first season.",
				Watched:    true,
				Episodes: []serializers.SeasonEpisodeSerializer{
					{Id: 80, Title: "Pilot", Number: 1, PosterPath: "/e1.jpg", Runtime: 58, Overview: "The pilot.", Rating: 8.0, AirDate: "2008-01-20", Watched: true},
				},
			},
		},
		{
			name: "Success with nothing watched",
			before: func() {
				client.EXPECT().FetchTvSeasonDetails(ctx, uint64(300), uint64(1)).Return(sampleSeasonDetails(), nil)
				progressSvc.EXPECT().Get(ctx, userId, uint64(300)).Return(&models.SeriesProgress{State: models.StateTypeNone}, nil)
			},
			expected: &serializers.SeasonDetailsSerializer{
				Id:         50,
				TmdbShowId: 300,
				Title:      "Season 1",
				Number:     1,
				PosterPath: "/s1.jpg",
				AirDate:    "2008-01-20",
				Overview:   "The first season.",
				Watched:    false,
				Episodes: []serializers.SeasonEpisodeSerializer{
					{Id: 80, Title: "Pilot", Number: 1, PosterPath: "/e1.jpg", Runtime: 58, Overview: "The pilot.", Rating: 8.0, AirDate: "2008-01-20", Watched: false},
				},
			},
		},
		{
			name: "Client error",
			before: func() {
				client.EXPECT().FetchTvSeasonDetails(ctx, uint64(300), uint64(1)).Return(nil, assert.AnError)
			},
			expected: nil,
			error:    tmdb.ErrFailedToFetchSeasonDetails,
		},
		{
			name: "Progress error",
			before: func() {
				client.EXPECT().FetchTvSeasonDetails(ctx, uint64(300), uint64(1)).Return(sampleSeasonDetails(), nil)
				progressSvc.EXPECT().Get(ctx, userId, uint64(300)).Return(nil, assert.AnError)
			},
			expected: nil,
			error:    tmdb.ErrFailedToFetchSeasonDetails,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, err := provider.FetchTvSeasonDetails(ctx, 300, 1, userId)

			if tt.error != nil {
				require.ErrorIs(t, err, tt.error)
				assert.Nil(t, result)
			} else {
				require.NoError(t, err)
				assert.Equal(t, tt.expected, result)
			}
		})
	}
}

func Test_Tmdb_FetchTvEpisodeDetails(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	client := tmdb.NewMockClient(ctrl)
	moviesSvc := NewMockMovies(ctrl)
	seriesSvc := NewMockSeries(ctrl)
	progressSvc := NewMockProgress(ctrl)
	provider := NewTmdbProvider(client, moviesSvc, seriesSvc, progressSvc, cache.NewNoopCache(), newTestLogger())
	userId := uuid.New()

	tests := []struct {
		name     string
		before   func()
		expected *serializers.EpisodeDetailsSerializer
		error    error
	}{
		{
			name: "Success merges watched state",
			before: func() {
				client.EXPECT().FetchTvEpisodeDetails(ctx, uint64(300), uint64(1), uint64(1)).Return(sampleEpisodeDetails(), nil)
				progressSvc.EXPECT().Get(ctx, userId, uint64(300)).Return(&models.SeriesProgress{
					WatchedEpisodes: []uint64{80},
				}, nil)
			},
			expected: &serializers.EpisodeDetailsSerializer{
				Id:         80,
				Title:      "Pilot",
				Number:     1,
				PosterPath: "/e1.jpg",
				Runtime:    58,
				Overview:   "The pilot.",
				Rating:     8.0,
				AirDate:    "2008-01-20",
				Watched:    true,
				Credits: []serializers.PersonSerializer{
					{Id: 6, Name: "Vince Gilligan", Description: "Director", ProfilePath: "/vg.jpg"},
					{Id: 5, Name: "Bryan Cranston", Description: "Walter White", ProfilePath: "/bc.jpg"},
				},
				Videos: []serializers.VideoSerializer{
					{Id: "ev1", Key: "evkey"},
				},
			},
		},
		{
			name: "Success not watched",
			before: func() {
				client.EXPECT().FetchTvEpisodeDetails(ctx, uint64(300), uint64(1), uint64(1)).Return(sampleEpisodeDetails(), nil)
				progressSvc.EXPECT().Get(ctx, userId, uint64(300)).Return(&models.SeriesProgress{State: models.StateTypeNone}, nil)
			},
			expected: &serializers.EpisodeDetailsSerializer{
				Id:         80,
				Title:      "Pilot",
				Number:     1,
				PosterPath: "/e1.jpg",
				Runtime:    58,
				Overview:   "The pilot.",
				Rating:     8.0,
				AirDate:    "2008-01-20",
				Watched:    false,
				Credits: []serializers.PersonSerializer{
					{Id: 6, Name: "Vince Gilligan", Description: "Director", ProfilePath: "/vg.jpg"},
					{Id: 5, Name: "Bryan Cranston", Description: "Walter White", ProfilePath: "/bc.jpg"},
				},
				Videos: []serializers.VideoSerializer{
					{Id: "ev1", Key: "evkey"},
				},
			},
		},
		{
			name: "Client error",
			before: func() {
				client.EXPECT().FetchTvEpisodeDetails(ctx, uint64(300), uint64(1), uint64(1)).Return(nil, assert.AnError)
			},
			expected: nil,
			error:    tmdb.ErrFailedToFetchEpisodeDetails,
		},
		{
			name: "Progress error",
			before: func() {
				client.EXPECT().FetchTvEpisodeDetails(ctx, uint64(300), uint64(1), uint64(1)).Return(sampleEpisodeDetails(), nil)
				progressSvc.EXPECT().Get(ctx, userId, uint64(300)).Return(nil, assert.AnError)
			},
			expected: nil,
			error:    tmdb.ErrFailedToFetchEpisodeDetails,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, err := provider.FetchTvEpisodeDetails(ctx, 300, 1, 1, userId)

			if tt.error != nil {
				require.ErrorIs(t, err, tt.error)
				assert.Nil(t, result)
			} else {
				require.NoError(t, err)
				assert.Equal(t, tt.expected, result)
			}
		})
	}
}

func Test_Tmdb_SearchMovies(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	client := tmdb.NewMockClient(ctrl)
	moviesSvc := NewMockMovies(ctrl)
	seriesSvc := NewMockSeries(ctrl)
	progressSvc := NewMockProgress(ctrl)
	provider := NewTmdbProvider(client, moviesSvc, seriesSvc, progressSvc, cache.NewNoopCache(), newTestLogger())

	userId := uuid.New()

	tests := []struct {
		name     string
		before   func()
		expected *serializers.PaginationResponse[serializers.SearchMovieSerializer]
		error    error
	}{
		{
			name: "Success filters and merges state",
			before: func() {
				client.EXPECT().SearchMovies(ctx, "matrix", uint64(1)).Return(sampleMovieListResult(), nil)

				moviesSvc.EXPECT().FindMoviesByTmdbIds(ctx, []uint64{100, 103, 101, 102}, userId).Return([]models.Movie{
					{TmdbId: 100, State: "want"},
				}, nil)
			},
			expected: &serializers.PaginationResponse[serializers.SearchMovieSerializer]{
				Data: []serializers.SearchMovieSerializer{
					{Id: 100, Title: "The Matrix", PosterPath: "/m.jpg", ReleaseDate: "1999-03-31", Rating: 8.7, State: "want"},
					{Id: 103, Title: "Untracked", PosterPath: "/u.jpg", ReleaseDate: "2020-01-01", Rating: 6.0, State: "none"},
				},
				Meta: serializers.PaginationMeta{Page: 1, Per: 2, Total: 4},
			},
		},
		{
			name: "Client error",
			before: func() {
				client.EXPECT().SearchMovies(ctx, "matrix", uint64(1)).Return(nil, assert.AnError)
			},
			expected: nil,
			error:    errors.ErrFailedToFetchResults,
		},
		{
			name: "State lookup error",
			before: func() {
				client.EXPECT().SearchMovies(ctx, "matrix", uint64(1)).Return(sampleMovieListResult(), nil)

				moviesSvc.EXPECT().FindMoviesByTmdbIds(ctx, []uint64{100, 103, 101, 102}, userId).Return(nil, assert.AnError)
			},
			expected: nil,
			error:    errors.ErrFailedToFetchResults,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, err := provider.SearchMovies(ctx, "matrix", 1, userId)

			if tt.error != nil {
				require.ErrorIs(t, err, tt.error)
				assert.Nil(t, result)
			} else {
				require.NoError(t, err)
				assert.Equal(t, tt.expected, result)
			}
		})
	}
}

func Test_Tmdb_FetchTrendingMovies(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	client := tmdb.NewMockClient(ctrl)
	moviesSvc := NewMockMovies(ctrl)
	seriesSvc := NewMockSeries(ctrl)
	progressSvc := NewMockProgress(ctrl)
	provider := NewTmdbProvider(client, moviesSvc, seriesSvc, progressSvc, cache.NewNoopCache(), newTestLogger())

	userId := uuid.New()

	tests := []struct {
		name     string
		before   func()
		expected *serializers.PaginationResponse[serializers.SearchMovieSerializer]
		error    error
	}{
		{
			name: "Success",
			before: func() {
				client.EXPECT().FetchTrendingMovies(ctx).Return(sampleMovieListResult(), nil)

				moviesSvc.EXPECT().FindMoviesByTmdbIds(ctx, []uint64{100, 103, 101, 102}, userId).Return([]models.Movie{
					{TmdbId: 100, State: "want"},
				}, nil)
			},
			expected: &serializers.PaginationResponse[serializers.SearchMovieSerializer]{
				Data: []serializers.SearchMovieSerializer{
					{Id: 100, Title: "The Matrix", PosterPath: "/m.jpg", ReleaseDate: "1999-03-31", Rating: 8.7, State: "want"},
					{Id: 103, Title: "Untracked", PosterPath: "/u.jpg", ReleaseDate: "2020-01-01", Rating: 6.0, State: "none"},
				},
				Meta: serializers.PaginationMeta{Page: 1, Per: 2, Total: 4},
			},
		},
		{
			name: "Client error",
			before: func() {
				client.EXPECT().FetchTrendingMovies(ctx).Return(nil, assert.AnError)
			},
			expected: nil,
			error:    errors.ErrFailedToFetchResults,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, err := provider.FetchTrendingMovies(ctx, userId)

			if tt.error != nil {
				require.ErrorIs(t, err, tt.error)
				assert.Nil(t, result)
			} else {
				require.NoError(t, err)
				assert.Equal(t, tt.expected, result)
			}
		})
	}
}

func Test_Tmdb_SearchSeries(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	client := tmdb.NewMockClient(ctrl)
	moviesSvc := NewMockMovies(ctrl)
	seriesSvc := NewMockSeries(ctrl)
	progressSvc := NewMockProgress(ctrl)
	provider := NewTmdbProvider(client, moviesSvc, seriesSvc, progressSvc, cache.NewNoopCache(), newTestLogger())

	userId := uuid.New()

	tests := []struct {
		name     string
		before   func()
		expected *serializers.PaginationResponse[serializers.SearchSeriesSerializer]
		error    error
	}{
		{
			name: "Success filters and merges state",
			before: func() {
				client.EXPECT().SearchTv(ctx, "bad", uint64(1)).Return(sampleTvListResult(), nil)

				seriesSvc.EXPECT().FindSeriesByTmdbIds(ctx, []uint64{300, 303, 301, 302}, userId).Return([]models.Series{
					{TmdbId: 300, State: "watching"},
				}, nil)
			},
			expected: &serializers.PaginationResponse[serializers.SearchSeriesSerializer]{
				Data: []serializers.SearchSeriesSerializer{
					{Id: 300, Title: "Breaking Bad", PosterPath: "/bb.jpg", ReleaseDate: "2008-01-20", Rating: 9.5, State: "watching"},
					{Id: 303, Title: "Untracked Show", PosterPath: "/us.jpg", ReleaseDate: "2021-01-01", Rating: 7.0, State: "none"},
				},
				Meta: serializers.PaginationMeta{Page: 1, Per: 2, Total: 4},
			},
		},
		{
			name: "Client error",
			before: func() {
				client.EXPECT().SearchTv(ctx, "bad", uint64(1)).Return(nil, assert.AnError)
			},
			expected: nil,
			error:    errors.ErrFailedToFetchResults,
		},
		{
			name: "State lookup error",
			before: func() {
				client.EXPECT().SearchTv(ctx, "bad", uint64(1)).Return(sampleTvListResult(), nil)

				seriesSvc.EXPECT().FindSeriesByTmdbIds(ctx, []uint64{300, 303, 301, 302}, userId).Return(nil, assert.AnError)
			},
			expected: nil,
			error:    errors.ErrFailedToFetchResults,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, err := provider.SearchSeries(ctx, "bad", 1, userId)

			if tt.error != nil {
				require.ErrorIs(t, err, tt.error)
				assert.Nil(t, result)
			} else {
				require.NoError(t, err)
				assert.Equal(t, tt.expected, result)
			}
		})
	}
}

func Test_Tmdb_FetchTrendingSeries(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	client := tmdb.NewMockClient(ctrl)
	moviesSvc := NewMockMovies(ctrl)
	seriesSvc := NewMockSeries(ctrl)
	progressSvc := NewMockProgress(ctrl)
	provider := NewTmdbProvider(client, moviesSvc, seriesSvc, progressSvc, cache.NewNoopCache(), newTestLogger())

	userId := uuid.New()

	tests := []struct {
		name     string
		before   func()
		expected *serializers.PaginationResponse[serializers.SearchSeriesSerializer]
		error    error
	}{
		{
			name: "Success",
			before: func() {
				client.EXPECT().FetchTrendingTv(ctx).Return(sampleTvListResult(), nil)

				seriesSvc.EXPECT().FindSeriesByTmdbIds(ctx, []uint64{300, 303, 301, 302}, userId).Return([]models.Series{
					{TmdbId: 300, State: "watching"},
				}, nil)
			},
			expected: &serializers.PaginationResponse[serializers.SearchSeriesSerializer]{
				Data: []serializers.SearchSeriesSerializer{
					{Id: 300, Title: "Breaking Bad", PosterPath: "/bb.jpg", ReleaseDate: "2008-01-20", Rating: 9.5, State: "watching"},
					{Id: 303, Title: "Untracked Show", PosterPath: "/us.jpg", ReleaseDate: "2021-01-01", Rating: 7.0, State: "none"},
				},
				Meta: serializers.PaginationMeta{Page: 1, Per: 2, Total: 4},
			},
		},
		{
			name: "Client error",
			before: func() {
				client.EXPECT().FetchTrendingTv(ctx).Return(nil, assert.AnError)
			},
			expected: nil,
			error:    errors.ErrFailedToFetchResults,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, err := provider.FetchTrendingSeries(ctx, userId)

			if tt.error != nil {
				require.ErrorIs(t, err, tt.error)
				assert.Nil(t, result)
			} else {
				require.NoError(t, err)
				assert.Equal(t, tt.expected, result)
			}
		})
	}
}

func Test_Tmdb_SearchPeople(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	client := tmdb.NewMockClient(ctrl)
	moviesSvc := NewMockMovies(ctrl)
	seriesSvc := NewMockSeries(ctrl)
	progressSvc := NewMockProgress(ctrl)
	provider := NewTmdbProvider(client, moviesSvc, seriesSvc, progressSvc, cache.NewNoopCache(), newTestLogger())

	tests := []struct {
		name     string
		before   func()
		expected *serializers.PaginationResponse[serializers.SearchPersonSerializer]
		error    error
	}{
		{
			name: "Success drops profile-less and adult results",
			before: func() {
				client.EXPECT().SearchPeople(ctx, "keanu", uint64(2)).Return(&tmdb.PersonListResult{
					Page:         2,
					TotalResults: 3,
					Results: []tmdb.PersonListItem{
						{Id: 600, Name: "Keanu Reeves", ProfilePath: "/p1.jpg"},
						{Id: 601, Name: "No Profile", ProfilePath: ""},
						{Id: 602, Name: "Adult Star", ProfilePath: "/a.jpg", Adult: true},
					},
				}, nil)
			},
			expected: &serializers.PaginationResponse[serializers.SearchPersonSerializer]{
				Data: []serializers.SearchPersonSerializer{
					{Id: 600, Name: "Keanu Reeves", ProfilePath: "/p1.jpg"},
				},
				Meta: serializers.PaginationMeta{Page: 2, Per: 1, Total: 3},
			},
		},
		{
			name: "Client error",
			before: func() {
				client.EXPECT().SearchPeople(ctx, "keanu", uint64(2)).Return(nil, assert.AnError)
			},
			expected: nil,
			error:    errors.ErrFailedToFetchResults,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, err := provider.SearchPeople(ctx, "keanu", 2)

			if tt.error != nil {
				require.ErrorIs(t, err, tt.error)
				assert.Nil(t, result)
			} else {
				require.NoError(t, err)
				assert.Equal(t, tt.expected, result)
			}
		})
	}
}

func Test_Tmdb_FetchTrendingPeople(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	client := tmdb.NewMockClient(ctrl)
	moviesSvc := NewMockMovies(ctrl)
	seriesSvc := NewMockSeries(ctrl)
	progressSvc := NewMockProgress(ctrl)
	provider := NewTmdbProvider(client, moviesSvc, seriesSvc, progressSvc, cache.NewNoopCache(), newTestLogger())

	tests := []struct {
		name     string
		before   func()
		expected *serializers.PaginationResponse[serializers.SearchPersonSerializer]
		error    error
	}{
		{
			name: "Success requires a notable credit",
			before: func() {
				client.EXPECT().FetchTrendingPeople(ctx).Return(&tmdb.PersonListResult{
					Page:         1,
					TotalResults: 4,
					Results: []tmdb.PersonListItem{
						{Id: 500, Name: "Famous", ProfilePath: "/f.jpg", KnownFor: []tmdb.PersonKnownFor{{VoteCount: 200}}},
						{Id: 501, Name: "Unknown", ProfilePath: "/u.jpg", KnownFor: []tmdb.PersonKnownFor{{VoteCount: 10}}},
						{Id: 502, Name: "No Profile", ProfilePath: "", KnownFor: []tmdb.PersonKnownFor{{VoteCount: 500}}},
						{Id: 503, Name: "Adult Star", ProfilePath: "/a.jpg", Adult: true, KnownFor: []tmdb.PersonKnownFor{{VoteCount: 500}}},
					},
				}, nil)
			},
			expected: &serializers.PaginationResponse[serializers.SearchPersonSerializer]{
				Data: []serializers.SearchPersonSerializer{
					{Id: 500, Name: "Famous", ProfilePath: "/f.jpg"},
				},
				Meta: serializers.PaginationMeta{Page: 1, Per: 1, Total: 4},
			},
		},
		{
			name: "Client error",
			before: func() {
				client.EXPECT().FetchTrendingPeople(ctx).Return(nil, assert.AnError)
			},
			expected: nil,
			error:    errors.ErrFailedToFetchResults,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, err := provider.FetchTrendingPeople(ctx)

			if tt.error != nil {
				require.ErrorIs(t, err, tt.error)
				assert.Nil(t, result)
			} else {
				require.NoError(t, err)
				assert.Equal(t, tt.expected, result)
			}
		})
	}
}

func Test_Tmdb_FetchUpNext(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	client := tmdb.NewMockClient(ctrl)
	moviesSvc := NewMockMovies(ctrl)
	seriesSvc := NewMockSeries(ctrl)
	progressSvc := NewMockProgress(ctrl)
	provider := NewTmdbProvider(client, moviesSvc, seriesSvc, progressSvc, cache.NewNoopCache(), newTestLogger())
	userId := uuid.New()

	tests := []struct {
		name     string
		before   func()
		expected *serializers.UpNextSerializer
		error    error
	}{
		{
			name: "Suggests the next unwatched aired episode and released movies",
			before: func() {
				seriesSvc.EXPECT().List(ctx, userId, models.StateTypeWatching, gomock.Any()).Return([]models.Series{
					{TmdbId: 300, Title: "Breaking Bad", PosterPath: "/bb.jpg", Pinned: true},
					{TmdbId: 400, Title: "Dropped Show", PosterPath: "/d.jpg", Pinned: false},
				}, uint64(2), nil)

				// season 1 (id 50) is fully watched, so it is skipped without a fetch; the resume point is S2E2
				client.EXPECT().FetchTvDetails(ctx, uint64(300)).Return(&tmdb.TvDetails{Id: 300, Seasons: []tmdb.TvSeason{{Id: 50, SeasonNumber: 1}, {Id: 60, SeasonNumber: 2}}}, nil)
				progressSvc.EXPECT().Get(ctx, userId, uint64(300)).Return(&models.SeriesProgress{WatchedSeasons: []uint64{50}, WatchedEpisodes: []uint64{201}}, nil)
				client.EXPECT().FetchTvSeasonDetails(ctx, uint64(300), uint64(2)).Return(&tmdb.SeasonDetails{Episodes: []tmdb.Episode{
					{ID: 201, EpisodeNumber: 1, SeasonNumber: 2, Name: "Seen", AirDate: "2000-01-01"},
					{ID: 202, EpisodeNumber: 2, SeasonNumber: 2, Name: "Next Ep", Overview: "The next one.", Runtime: 47, StillPath: "/a.jpg", AirDate: "2000-01-08", VoteAverage: 9.0},
					{ID: 203, EpisodeNumber: 3, SeasonNumber: 2, Name: "Future", AirDate: "2999-01-01"},
				}}, nil)

				moviesSvc.EXPECT().List(ctx, userId, models.StateTypeWant, gomock.Any()).Return([]models.Movie{
					{TmdbId: 500, Title: "Dune", Pinned: true},
					{TmdbId: 550, Title: "Old Film", Pinned: true},
					{TmdbId: 600, Title: "Unpinned", Pinned: false},
				}, uint64(3), nil)

				// 500 released by status, 550 released by a past date; 600 is unpinned and never looked up
				client.EXPECT().FetchMovieDetails(ctx, uint64(500)).Return(&tmdb.MovieDetails{Id: 500, Title: "Dune", PosterPath: "/dune.jpg", Overview: "Paul's journey.", Status: "Released", ReleaseDate: "2021-10-22", Runtime: 155, VoteAverage: 8.0}, nil)
				client.EXPECT().FetchMovieDetails(ctx, uint64(550)).Return(&tmdb.MovieDetails{Id: 550, Title: "Old Film", PosterPath: "/old.jpg", Overview: "Classic.", Status: "", ReleaseDate: "2000-06-15", Runtime: 120, VoteAverage: 7.0}, nil)
			},
			expected: &serializers.UpNextSerializer{
				Episodes: []serializers.UpNextEpisodeSerializer{
					{SeriesId: 300, SeriesTitle: "Breaking Bad", SeriesPosterPath: "/bb.jpg", Id: 202, Title: "Next Ep", SeasonNumber: 2, Number: 2, PosterPath: "/a.jpg", Overview: "The next one.", Runtime: 47, Rating: 9.0, AirDate: "2000-01-08"},
				},
				Movies: []serializers.UpNextMovieSerializer{
					{Id: 500, Title: "Dune", PosterPath: "/dune.jpg", Overview: "Paul's journey.", Runtime: 155, Rating: 8.0, ReleaseDate: "2021-10-22"},
					{Id: 550, Title: "Old Film", PosterPath: "/old.jpg", Overview: "Classic.", Runtime: 120, Rating: 7.0, ReleaseDate: "2000-06-15"},
				},
			},
		},
		{
			name: "Skips a show whose next episode has not aired and unreleased movies",
			before: func() {
				seriesSvc.EXPECT().List(ctx, userId, models.StateTypeWatching, gomock.Any()).Return([]models.Series{{TmdbId: 300, Title: "Breaking Bad", Pinned: true}}, uint64(1), nil)
				client.EXPECT().FetchTvDetails(ctx, uint64(300)).Return(&tmdb.TvDetails{Id: 300, Seasons: []tmdb.TvSeason{{Id: 50, SeasonNumber: 1}}}, nil)
				progressSvc.EXPECT().Get(ctx, userId, uint64(300)).Return(&models.SeriesProgress{WatchedEpisodes: []uint64{201}}, nil)
				client.EXPECT().FetchTvSeasonDetails(ctx, uint64(300), uint64(1)).Return(&tmdb.SeasonDetails{Episodes: []tmdb.Episode{
					{ID: 201, EpisodeNumber: 1, AirDate: "2000-01-01"},
					{ID: 202, EpisodeNumber: 2, AirDate: "2999-01-01"},
				}}, nil)

				moviesSvc.EXPECT().List(ctx, userId, models.StateTypeWant, gomock.Any()).Return([]models.Movie{{TmdbId: 500, Title: "Future Film", Pinned: true}}, uint64(1), nil)
				client.EXPECT().FetchMovieDetails(ctx, uint64(500)).Return(&tmdb.MovieDetails{Id: 500, Status: "Post Production", ReleaseDate: "2999-01-01"}, nil)
			},
			expected: &serializers.UpNextSerializer{
				Episodes: []serializers.UpNextEpisodeSerializer{},
				Movies:   []serializers.UpNextMovieSerializer{},
			},
		},
		{
			name: "Skips items when TMDB lookups fail",
			before: func() {
				seriesSvc.EXPECT().List(ctx, userId, models.StateTypeWatching, gomock.Any()).Return([]models.Series{{TmdbId: 300, Pinned: true}}, uint64(1), nil)
				client.EXPECT().FetchTvDetails(ctx, uint64(300)).Return(&tmdb.TvDetails{Id: 300, Seasons: []tmdb.TvSeason{{Id: 50, SeasonNumber: 1}}}, nil)
				progressSvc.EXPECT().Get(ctx, userId, uint64(300)).Return(&models.SeriesProgress{}, nil)
				client.EXPECT().FetchTvSeasonDetails(ctx, uint64(300), uint64(1)).Return(nil, assert.AnError)

				moviesSvc.EXPECT().List(ctx, userId, models.StateTypeWant, gomock.Any()).Return([]models.Movie{{TmdbId: 500, Pinned: true}}, uint64(1), nil)
				client.EXPECT().FetchMovieDetails(ctx, uint64(500)).Return(nil, assert.AnError)
			},
			expected: &serializers.UpNextSerializer{
				Episodes: []serializers.UpNextEpisodeSerializer{},
				Movies:   []serializers.UpNextMovieSerializer{},
			},
		},
		{
			name: "Returns empty when nothing is pinned",
			before: func() {
				seriesSvc.EXPECT().List(ctx, userId, models.StateTypeWatching, gomock.Any()).Return([]models.Series{{TmdbId: 300, Pinned: false}}, uint64(1), nil)
				moviesSvc.EXPECT().List(ctx, userId, models.StateTypeWant, gomock.Any()).Return([]models.Movie{{TmdbId: 500, Pinned: false}}, uint64(1), nil)
			},
			expected: &serializers.UpNextSerializer{
				Episodes: []serializers.UpNextEpisodeSerializer{},
				Movies:   []serializers.UpNextMovieSerializer{},
			},
		},
		{
			name: "Series list error is returned",
			before: func() {
				seriesSvc.EXPECT().List(ctx, userId, models.StateTypeWatching, gomock.Any()).Return(nil, uint64(0), assert.AnError)
			},
			expected: nil,
			error:    assert.AnError,
		},
		{
			name: "Movie list error is returned",
			before: func() {
				seriesSvc.EXPECT().List(ctx, userId, models.StateTypeWatching, gomock.Any()).Return([]models.Series{}, uint64(0), nil)
				moviesSvc.EXPECT().List(ctx, userId, models.StateTypeWant, gomock.Any()).Return(nil, uint64(0), assert.AnError)
			},
			expected: nil,
			error:    assert.AnError,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, err := provider.FetchUpNext(ctx, userId)

			if tt.error != nil {
				require.ErrorIs(t, err, tt.error)
				assert.Nil(t, result)
			} else {
				require.NoError(t, err)
				assert.Equal(t, tt.expected, result)
			}
		})
	}
}
