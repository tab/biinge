package services

import (
	"context"
	"fmt"
	"strings"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/jackc/pgx/v5"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories"
	"biinge-api/internal/app/serializers"
	"biinge-api/internal/config"
	"biinge-api/internal/config/cache"
	"biinge-api/pkg/igdb"
	"biinge-api/pkg/tmdb"
)

func Test_Shares_Create(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockShareRepository(ctrl)
	tmdbClient := tmdb.NewMockClient(ctrl)
	igdbClient := igdb.NewMockClient(ctrl)
	cfg := &config.Config{ShareURL: "https://share.example.com/"}
	service := NewShares(cfg, repository, tmdbClient, igdbClient, cache.NewNoopCache(), newTestLogger())

	userId := uuid.New()
	shareId := uuid.MustParse("6f1c3c1e-8a2b-4d4e-9f3a-1b2c3d4e5f60")

	tests := []struct {
		name     string
		before   func()
		params   *models.Share
		expected *serializers.ShareSerializer
		error    error
	}{
		{
			name: "Movie",
			before: func() {
				tmdbClient.EXPECT().FetchMovieDetails(ctx, uint64(603)).Return(&tmdb.MovieDetails{}, nil)
				repository.EXPECT().
					Upsert(ctx, &models.Share{UserId: userId, Type: models.ShareTypeMovie, ObjectId: 603}).
					Return(&models.Share{ID: shareId, UserId: userId, Type: models.ShareTypeMovie, ObjectId: 603}, nil)
			},
			params: &models.Share{UserId: userId, Type: models.ShareTypeMovie, ObjectId: 603},
			expected: &serializers.ShareSerializer{
				Id:  shareId,
				URL: "https://share.example.com/6f1c3c1e-8a2b-4d4e-9f3a-1b2c3d4e5f60",
			},
		},
		{
			name: "Series",
			before: func() {
				tmdbClient.EXPECT().FetchTvDetails(ctx, uint64(1399)).Return(&tmdb.TvDetails{}, nil)
				repository.EXPECT().
					Upsert(ctx, &models.Share{UserId: userId, Type: models.ShareTypeTv, ObjectId: 1399}).
					Return(&models.Share{ID: shareId, UserId: userId, Type: models.ShareTypeTv, ObjectId: 1399}, nil)
			},
			params: &models.Share{UserId: userId, Type: models.ShareTypeTv, ObjectId: 1399},
			expected: &serializers.ShareSerializer{
				Id:  shareId,
				URL: "https://share.example.com/6f1c3c1e-8a2b-4d4e-9f3a-1b2c3d4e5f60",
			},
		},
		{
			name: "Game",
			before: func() {
				igdbClient.EXPECT().FetchGameDetails(ctx, uint64(1942)).Return(&igdb.GameDetails{}, nil)
				repository.EXPECT().
					Upsert(ctx, &models.Share{UserId: userId, Type: models.ShareTypeGame, ObjectId: 1942}).
					Return(&models.Share{ID: shareId, UserId: userId, Type: models.ShareTypeGame, ObjectId: 1942}, nil)
			},
			params: &models.Share{UserId: userId, Type: models.ShareTypeGame, ObjectId: 1942},
			expected: &serializers.ShareSerializer{
				Id:  shareId,
				URL: "https://share.example.com/6f1c3c1e-8a2b-4d4e-9f3a-1b2c3d4e5f60",
			},
		},
		{
			name: "Re-share returns the stored id",
			before: func() {
				tmdbClient.EXPECT().FetchMovieDetails(ctx, uint64(603)).Return(&tmdb.MovieDetails{}, nil)
				repository.EXPECT().
					Upsert(ctx, &models.Share{UserId: userId, Type: models.ShareTypeMovie, ObjectId: 603}).
					Return(&models.Share{ID: shareId, UserId: userId, Type: models.ShareTypeMovie, ObjectId: 603}, nil)
			},
			params: &models.Share{UserId: userId, Type: models.ShareTypeMovie, ObjectId: 603},
			expected: &serializers.ShareSerializer{
				Id:  shareId,
				URL: "https://share.example.com/6f1c3c1e-8a2b-4d4e-9f3a-1b2c3d4e5f60",
			},
		},
		{
			name: "Unknown movie stores nothing",
			before: func() {
				tmdbClient.EXPECT().FetchMovieDetails(ctx, uint64(999999)).Return(nil, tmdb.ErrNotFound)
			},
			params: &models.Share{UserId: userId, Type: models.ShareTypeMovie, ObjectId: 999999},
			error:  errors.ErrShareObjectNotFound,
		},
		{
			name: "Unknown series stores nothing",
			before: func() {
				tmdbClient.EXPECT().FetchTvDetails(ctx, uint64(999999)).Return(nil, tmdb.ErrNotFound)
			},
			params: &models.Share{UserId: userId, Type: models.ShareTypeTv, ObjectId: 999999},
			error:  errors.ErrShareObjectNotFound,
		},
		{
			name: "Unknown game stores nothing",
			before: func() {
				igdbClient.EXPECT().FetchGameDetails(ctx, uint64(999999)).Return(nil, igdb.ErrNotFound)
			},
			params: &models.Share{UserId: userId, Type: models.ShareTypeGame, ObjectId: 999999},
			error:  errors.ErrShareObjectNotFound,
		},
		{
			name: "TMDB failure",
			before: func() {
				tmdbClient.EXPECT().FetchMovieDetails(ctx, uint64(603)).Return(nil, assert.AnError)
			},
			params: &models.Share{UserId: userId, Type: models.ShareTypeMovie, ObjectId: 603},
			error:  errors.ErrFailedToFetchResults,
		},
		{
			name: "IGDB failure",
			before: func() {
				igdbClient.EXPECT().FetchGameDetails(ctx, uint64(1942)).Return(nil, assert.AnError)
			},
			params: &models.Share{UserId: userId, Type: models.ShareTypeGame, ObjectId: 1942},
			error:  errors.ErrFailedToFetchResults,
		},
		{
			name: "Repository failure",
			before: func() {
				tmdbClient.EXPECT().FetchMovieDetails(ctx, uint64(603)).Return(&tmdb.MovieDetails{}, nil)
				repository.EXPECT().
					Upsert(ctx, &models.Share{UserId: userId, Type: models.ShareTypeMovie, ObjectId: 603}).
					Return(nil, assert.AnError)
			},
			params: &models.Share{UserId: userId, Type: models.ShareTypeMovie, ObjectId: 603},
			error:  errors.ErrFailedToCreateShare,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, err := service.Create(ctx, tt.params)

			if tt.error != nil {
				require.ErrorIs(t, err, tt.error)
				assert.Nil(t, result)

				return
			}

			require.NoError(t, err)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func Test_Shares_Create_WarmsTheProviderCache(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockShareRepository(ctrl)
	tmdbClient := tmdb.NewMockClient(ctrl)
	igdbClient := igdb.NewMockClient(ctrl)
	store := newMemoryCache()
	cfg := &config.Config{ShareURL: "https://share.example.com"}
	service := NewShares(cfg, repository, tmdbClient, igdbClient, store, newTestLogger())

	userId := uuid.New()
	shareId := uuid.New()

	tests := []struct {
		name   string
		before func()
		key    string
		params *models.Share
	}{
		{
			name: "Movie",
			before: func() {
				tmdbClient.EXPECT().FetchMovieDetails(ctx, uint64(603)).Return(&tmdb.MovieDetails{}, nil)
			},
			key:    "tmdb:v2:movie:603",
			params: &models.Share{UserId: userId, Type: models.ShareTypeMovie, ObjectId: 603},
		},
		{
			name: "Series",
			before: func() {
				tmdbClient.EXPECT().FetchTvDetails(ctx, uint64(1399)).Return(&tmdb.TvDetails{}, nil)
			},
			key:    "tmdb:v3:tv:1399",
			params: &models.Share{UserId: userId, Type: models.ShareTypeTv, ObjectId: 1399},
		},
		{
			name: "Game",
			before: func() {
				igdbClient.EXPECT().FetchGameDetails(ctx, uint64(1942)).Return(&igdb.GameDetails{}, nil)
			},
			key:    "igdb:v2:game:1942",
			params: &models.Share{UserId: userId, Type: models.ShareTypeGame, ObjectId: 1942},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()
			repository.EXPECT().Upsert(ctx, tt.params).Return(&models.Share{ID: shareId}, nil).Times(2)

			result, err := service.Create(ctx, tt.params)

			require.NoError(t, err)
			assert.Equal(t, "https://share.example.com/"+shareId.String(), result.URL)
			assert.Contains(t, store.store, tt.key)
			assert.Equal(t, cache.DetailsTTL, store.ttls[tt.key])

			// a second share of the same title reads the entry and skips the provider
			_, err = service.Create(ctx, tt.params)

			require.NoError(t, err)
		})
	}
}

func Test_Shares_Page(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockShareRepository(ctrl)
	tmdbClient := tmdb.NewMockClient(ctrl)
	igdbClient := igdb.NewMockClient(ctrl)
	service := NewShares(&config.Config{}, repository, tmdbClient, igdbClient, cache.NewNoopCache(), newTestLogger())

	shareId := uuid.MustParse("6f1c3c1e-8a2b-4d4e-9f3a-1b2c3d4e5f60")
	movieShare := &models.Share{ID: shareId, UserId: uuid.New(), Type: models.ShareTypeMovie, ObjectId: 603}
	seriesShare := &models.Share{ID: shareId, UserId: uuid.New(), Type: models.ShareTypeTv, ObjectId: 1399}
	gameShare := &models.Share{ID: shareId, UserId: uuid.New(), Type: models.ShareTypeGame, ObjectId: 1942}

	// twenty-two billed cast members, the second without a photo, which the transformed credits leave out
	cast := make([]tmdb.PersonCast, 0, 22)

	for i := 1; i <= 22; i++ {
		photo := fmt.Sprintf("/cast%d.jpg", i)
		if i == 2 {
			photo = ""
		}

		cast = append(cast, tmdb.PersonCast{
			Person:    tmdb.Person{Id: i, Name: fmt.Sprintf("Actor %d", i), ProfilePath: photo},
			Character: fmt.Sprintf("Role %d", i),
		})
	}

	// the director leads, then the cast with a photo, cut at twenty
	credits := []serializers.ShareCreditSerializer{
		{Name: "Lana Wachowski", Role: "Director", PhotoURL: "https://image.tmdb.org/t/p/w185/lana.jpg"},
	}

	for i := 1; len(credits) < 20; i++ {
		if i == 2 {
			continue
		}

		credits = append(credits, serializers.ShareCreditSerializer{
			Name:     fmt.Sprintf("Actor %d", i),
			Role:     fmt.Sprintf("Role %d", i),
			PhotoURL: fmt.Sprintf("https://image.tmdb.org/t/p/w185/cast%d.jpg", i),
		})
	}

	movie := &tmdb.MovieDetails{
		Id:          603,
		Title:       "The Matrix",
		Overview:    "A hacker learns the truth.",
		PosterPath:  "/matrix.jpg",
		Status:      "Released",
		ReleaseDate: "1999-03-31",
		Runtime:     136,
		VoteAverage: 8.217,
		Genres:      []tmdb.Genre{{Id: 28, Name: "Action"}, {Id: 878, Name: "Science Fiction"}, {Id: 53, Name: "Thriller"}, {Id: 12, Name: "Adventure"}},
		Credits: tmdb.Credits{
			Cast: cast,
			Crew: []tmdb.PersonCrew{
				{Person: tmdb.Person{Id: 100, Name: "Lana Wachowski", ProfilePath: "/lana.jpg"}, Job: "Director"},
				{Person: tmdb.Person{Id: 101, Name: "Lilly Wachowski"}, Job: "Director"},
			},
		},
	}

	tests := []struct {
		name     string
		before   func()
		expected *serializers.SharePageSerializer
		error    error
	}{
		{
			name: "Movie",
			before: func() {
				repository.EXPECT().FindLive(ctx, shareId).Return(movieShare, nil)
				tmdbClient.EXPECT().FetchMovieDetails(ctx, uint64(603)).Return(movie, nil)
				repository.EXPECT().TouchVisit(ctx, shareId).Return(nil)
			},
			expected: &serializers.SharePageSerializer{
				Kind:        "Movie",
				Title:       "The Matrix",
				Year:        "1999",
				Meta:        "1999 · 2h 16m · Action, Science Fiction, Thriller",
				Rating:      "8.2",
				Overview:    "A hacker learns the truth.",
				Description: "A hacker learns the truth.",
				ImageURL:    "https://image.tmdb.org/t/p/w500/matrix.jpg",
				Facts: []serializers.ShareFactSerializer{
					{Label: "Director", Value: "Lana Wachowski, Lilly Wachowski"},
					{Label: "Released", Value: "31 Mar 1999"},
				},
				Credits: credits,
			},
		},
		{
			name: "Upcoming movie",
			before: func() {
				repository.EXPECT().FindLive(ctx, shareId).Return(movieShare, nil)
				tmdbClient.EXPECT().
					FetchMovieDetails(ctx, uint64(603)).
					Return(&tmdb.MovieDetails{Title: "Sequel", ReleaseDate: "2999-12-01", Status: "Post Production", Runtime: 45}, nil)
				repository.EXPECT().TouchVisit(ctx, shareId).Return(nil)
			},
			expected: &serializers.SharePageSerializer{
				Kind:  "Movie",
				Title: "Sequel",
				Year:  "2999",
				Meta:  "1 Dec 2999 · 45 min",
				Facts: []serializers.ShareFactSerializer{
					{Label: "Releases", Value: "1 Dec 2999"},
					{Label: "Status", Value: "Post-production"},
				},
				Credits: []serializers.ShareCreditSerializer{},
			},
		},
		{
			name: "Series",
			before: func() {
				repository.EXPECT().FindLive(ctx, shareId).Return(seriesShare, nil)
				tmdbClient.EXPECT().FetchTvDetails(ctx, uint64(1399)).Return(&tmdb.TvDetails{
					Id:           1399,
					Title:        "Game of Thrones",
					Overview:     "Seven noble families fight.",
					PosterPath:   "/got.jpg",
					Status:       "Returning Series",
					ReleaseDate:  "2011-04-17",
					VoteAverage:  8.4,
					SeasonsCount: 2,
					Genres:       []tmdb.Genre{{Id: 18, Name: "Drama"}},
					CreatedBy:    []tmdb.Person{{Id: 9813, Name: "David Benioff"}, {Id: 228068, Name: "D. B. Weiss"}},
					Seasons: []tmdb.TvSeason{
						{Id: 3627, Name: "Specials", SeasonNumber: 0, EpisodeCount: 1},
						{Id: 3624, Name: "Season 1", SeasonNumber: 1, EpisodeCount: 10, AirDate: "2011-04-17"},
						{Id: 3625, Name: "Season 2", SeasonNumber: 2, EpisodeCount: 10, AirDate: "2012-04-01"},
					},
					Credits: tmdb.Credits{Cast: cast[:1]},
				}, nil)
				repository.EXPECT().TouchVisit(ctx, shareId).Return(nil)
			},
			expected: &serializers.SharePageSerializer{
				Kind:        "TV Show",
				Title:       "Game of Thrones",
				Year:        "2011",
				Meta:        "2011 · 2 Seasons · Drama",
				Rating:      "8.4",
				Overview:    "Seven noble families fight.",
				Description: "Seven noble families fight.",
				ImageURL:    "https://image.tmdb.org/t/p/w500/got.jpg",
				Facts: []serializers.ShareFactSerializer{
					{Label: "Created by", Value: "David Benioff, D. B. Weiss"},
					{Label: "First aired", Value: "2011"},
					{Label: "Status", Value: "Returning"},
				},
				Seasons: []serializers.ShareSeasonSerializer{
					{Name: "Specials", Episodes: "1 episode"},
					{Name: "Season 1", Year: "2011", Episodes: "10 episodes"},
					{Name: "Season 2", Year: "2012", Episodes: "10 episodes"},
				},
				Credits: credits[1:2],
			},
		},
		{
			name: "Series with one season",
			before: func() {
				repository.EXPECT().FindLive(ctx, shareId).Return(seriesShare, nil)
				tmdbClient.EXPECT().
					FetchTvDetails(ctx, uint64(1399)).
					Return(&tmdb.TvDetails{Title: "Pilot", ReleaseDate: "2011-04-17", SeasonsCount: 1, Status: "Canceled"}, nil)
				repository.EXPECT().TouchVisit(ctx, shareId).Return(nil)
			},
			expected: &serializers.SharePageSerializer{
				Kind:  "TV Show",
				Title: "Pilot",
				Year:  "2011",
				Meta:  "2011 · 1 Season",
				Facts: []serializers.ShareFactSerializer{
					{Label: "First aired", Value: "2011"},
					{Label: "Status", Value: "Cancelled"},
				},
				Seasons: []serializers.ShareSeasonSerializer{},
				Credits: []serializers.ShareCreditSerializer{},
			},
		},
		{
			name: "Series without seasons",
			before: func() {
				repository.EXPECT().FindLive(ctx, shareId).Return(seriesShare, nil)
				tmdbClient.EXPECT().
					FetchTvDetails(ctx, uint64(1399)).
					Return(&tmdb.TvDetails{Title: "Pilot", ReleaseDate: "2011-04-17", Genres: []tmdb.Genre{{Id: 18, Name: "Drama"}}}, nil)
				repository.EXPECT().TouchVisit(ctx, shareId).Return(nil)
			},
			expected: &serializers.SharePageSerializer{
				Kind:  "TV Show",
				Title: "Pilot",
				Year:  "2011",
				Meta:  "2011 · Drama",
				Facts: []serializers.ShareFactSerializer{
					{Label: "First aired", Value: "2011"},
				},
				Seasons: []serializers.ShareSeasonSerializer{},
				Credits: []serializers.ShareCreditSerializer{},
			},
		},
		{
			name: "Game",
			before: func() {
				repository.EXPECT().FindLive(ctx, shareId).Return(gameShare, nil)
				igdbClient.EXPECT().FetchGameDetails(ctx, uint64(1942)).Return(&igdb.GameDetails{
					Game: igdb.Game{
						Id:                1942,
						Name:              "The Witcher 3",
						Summary:           "Geralt hunts monsters.",
						FirstReleaseDate:  1709251200,
						TotalRating:       92.4,
						TotalRatingCount:  500,
						Cover:             igdb.Cover{ImageId: "co1wyy"},
						GameStatus:        igdb.GameStatus{Status: "Early Access"},
						Genres:            []igdb.Genre{{Id: 12, Name: "Role-playing (RPG)"}},
						Platforms:         []igdb.Platform{{Id: 48, Name: "PlayStation 4"}},
						InvolvedCompanies: []igdb.InvolvedCompany{{Company: igdb.Company{Name: "CD Projekt RED"}, Developer: true}},
					},
					TimeToBeat: igdb.TimeToBeat{Normally: 3 * 60 * 60 * 50, Count: 10},
				}, nil)
				repository.EXPECT().TouchVisit(ctx, shareId).Return(nil)
			},
			expected: &serializers.SharePageSerializer{
				Kind:        "Game",
				Title:       "The Witcher 3",
				Year:        "2024",
				Meta:        "2024 · 150h",
				Rating:      "9.2",
				Overview:    "Geralt hunts monsters.",
				Description: "Geralt hunts monsters.",
				ImageURL:    "https://images.igdb.com/igdb/image/upload/t_cover_big_2x/co1wyy.jpg",
				Facts: []serializers.ShareFactSerializer{
					{Label: "Developer", Value: "CD Projekt RED"},
					{Label: "Released", Value: "1 Mar 2024"},
					{Label: "Status", Value: "Early Access"},
				},
				Genres:    []string{"RPG"},
				Platforms: []string{"PS4"},
			},
		},
		{
			name: "A fact with no value is hidden",
			before: func() {
				repository.EXPECT().FindLive(ctx, shareId).Return(movieShare, nil)
				tmdbClient.EXPECT().FetchMovieDetails(ctx, uint64(603)).Return(&tmdb.MovieDetails{Title: "Untitled"}, nil)
				repository.EXPECT().TouchVisit(ctx, shareId).Return(nil)
			},
			expected: &serializers.SharePageSerializer{
				Kind:    "Movie",
				Title:   "Untitled",
				Facts:   []serializers.ShareFactSerializer{},
				Credits: []serializers.ShareCreditSerializer{},
			},
		},
		{
			name: "Touch failure still returns the page",
			before: func() {
				repository.EXPECT().FindLive(ctx, shareId).Return(movieShare, nil)
				tmdbClient.EXPECT().FetchMovieDetails(ctx, uint64(603)).Return(&tmdb.MovieDetails{Title: "Untitled"}, nil)
				repository.EXPECT().TouchVisit(ctx, shareId).Return(assert.AnError)
			},
			expected: &serializers.SharePageSerializer{
				Kind:    "Movie",
				Title:   "Untitled",
				Facts:   []serializers.ShareFactSerializer{},
				Credits: []serializers.ShareCreditSerializer{},
			},
		},
		{
			name: "Unknown or expired share",
			before: func() {
				repository.EXPECT().FindLive(ctx, shareId).Return(nil, pgx.ErrNoRows)
			},
			error: errors.ErrShareNotFound,
		},
		{
			name: "Repository failure",
			before: func() {
				repository.EXPECT().FindLive(ctx, shareId).Return(nil, assert.AnError)
			},
			error: errors.ErrFailedToFetchShare,
		},
		{
			name: "Movie removed at TMDB",
			before: func() {
				repository.EXPECT().FindLive(ctx, shareId).Return(movieShare, nil)
				tmdbClient.EXPECT().FetchMovieDetails(ctx, uint64(603)).Return(nil, tmdb.ErrNotFound)
			},
			error: errors.ErrShareNotFound,
		},
		{
			name: "Game removed at IGDB",
			before: func() {
				repository.EXPECT().FindLive(ctx, shareId).Return(gameShare, nil)
				igdbClient.EXPECT().FetchGameDetails(ctx, uint64(1942)).Return(nil, igdb.ErrNotFound)
			},
			error: errors.ErrShareNotFound,
		},
		{
			name: "TMDB failure",
			before: func() {
				repository.EXPECT().FindLive(ctx, shareId).Return(seriesShare, nil)
				tmdbClient.EXPECT().FetchTvDetails(ctx, uint64(1399)).Return(nil, assert.AnError)
			},
			error: errors.ErrFailedToFetchResults,
		},
		{
			name: "IGDB failure",
			before: func() {
				repository.EXPECT().FindLive(ctx, shareId).Return(gameShare, nil)
				igdbClient.EXPECT().FetchGameDetails(ctx, uint64(1942)).Return(nil, assert.AnError)
			},
			error: errors.ErrFailedToFetchResults,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			result, err := service.Page(ctx, shareId)

			if tt.error != nil {
				require.ErrorIs(t, err, tt.error)
				assert.Nil(t, result)

				return
			}

			require.NoError(t, err)
			assert.Equal(t, tt.expected, result)
		})
	}
}

func Test_Shares_Page_ReadsTheProviderCache(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	repository := repositories.NewMockShareRepository(ctrl)
	tmdbClient := tmdb.NewMockClient(ctrl)
	igdbClient := igdb.NewMockClient(ctrl)
	store := newMemoryCache()
	service := NewShares(&config.Config{}, repository, tmdbClient, igdbClient, store, newTestLogger())

	shareId := uuid.New()

	tests := []struct {
		name   string
		before func()
		key    string
		share  *models.Share
	}{
		{
			name: "Movie",
			before: func() {
				tmdbClient.EXPECT().FetchMovieDetails(ctx, uint64(603)).Return(&tmdb.MovieDetails{Title: "The Matrix"}, nil)
			},
			key:   "tmdb:v2:movie:603",
			share: &models.Share{ID: shareId, Type: models.ShareTypeMovie, ObjectId: 603},
		},
		{
			name: "Series",
			before: func() {
				tmdbClient.EXPECT().FetchTvDetails(ctx, uint64(1399)).Return(&tmdb.TvDetails{Title: "Game of Thrones"}, nil)
			},
			key:   "tmdb:v3:tv:1399",
			share: &models.Share{ID: shareId, Type: models.ShareTypeTv, ObjectId: 1399},
		},
		{
			name: "Game",
			before: func() {
				igdbClient.EXPECT().FetchGameDetails(ctx, uint64(1942)).Return(&igdb.GameDetails{Game: igdb.Game{Name: "The Witcher 3"}}, nil)
			},
			key:   "igdb:v2:game:1942",
			share: &models.Share{ID: shareId, Type: models.ShareTypeGame, ObjectId: 1942},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()
			repository.EXPECT().FindLive(ctx, shareId).Return(tt.share, nil).Times(2)
			repository.EXPECT().TouchVisit(ctx, shareId).Return(nil).Times(2)

			_, err := service.Page(ctx, shareId)

			require.NoError(t, err)
			assert.Contains(t, store.store, tt.key)
			assert.Equal(t, cache.DetailsTTL, store.ttls[tt.key])

			// a second visit reads the entry and skips the provider
			_, err = service.Page(ctx, shareId)

			require.NoError(t, err)
		})
	}
}

func Test_ShareDescription(t *testing.T) {
	// 200 characters end two letters into the 34th word
	long := strings.Repeat("words ", 60)

	tests := []struct {
		name     string
		overview string
		expected string
	}{
		{
			name:     "Short overview stays whole",
			overview: "  A hacker learns the truth.  ",
			expected: "A hacker learns the truth.",
		},
		{
			name:     "Long overview is cut at a word break",
			overview: long,
			expected: strings.TrimSpace(strings.Repeat("words ", 33)) + "…",
		},
		{
			name:     "Empty overview",
			overview: "",
			expected: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.expected, shareDescription(tt.overview))
		})
	}
}

func Test_ShareRuntime(t *testing.T) {
	tests := []struct {
		name     string
		minutes  int
		expected string
	}{
		{
			name:     "No runtime",
			minutes:  0,
			expected: "",
		},
		{
			name:     "Under an hour",
			minutes:  45,
			expected: "45 min",
		},
		{
			name:     "Whole hours",
			minutes:  120,
			expected: "2h 0m",
		},
		{
			name:     "Hours and minutes",
			minutes:  136,
			expected: "2h 16m",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.expected, shareRuntime(tt.minutes))
		})
	}
}

func Test_ShareStatus(t *testing.T) {
	tests := []struct {
		name     string
		status   string
		expected string
	}{
		{
			name:     "Released",
			status:   "Released",
			expected: "",
		},
		{
			name:     "Canceled",
			status:   "Canceled",
			expected: "Cancelled",
		},
		{
			name:     "Returning Series",
			status:   "Returning Series",
			expected: "Returning",
		},
		{
			name:     "Post Production",
			status:   "Post Production",
			expected: "Post-production",
		},
		{
			name:     "In Production",
			status:   "In Production",
			expected: "In production",
		},
		{
			name:     "Other status passes through",
			status:   "Ended",
			expected: "Ended",
		},
		{
			name:     "No status",
			status:   "",
			expected: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.expected, shareStatus(tt.status))
		})
	}
}

func Test_ShareRelease(t *testing.T) {
	now := time.Date(2024, time.August, 31, 23, 0, 0, 0, time.UTC)

	tests := []struct {
		name     string
		date     string
		expected string
	}{
		{
			name:     "Within six months reads the day",
			date:     "2024-05-01",
			expected: "1 May 2024",
		},
		{
			name:     "Six months back in a shorter month reads the day",
			date:     "2024-02-29",
			expected: "29 Feb 2024",
		},
		{
			name:     "Past six months reads the year",
			date:     "2024-02-28",
			expected: "2024",
		},
		{
			name:     "Future reads the day",
			date:     "2025-03-01",
			expected: "1 Mar 2025",
		},
		{
			name:     "Year only",
			date:     "2010",
			expected: "2010",
		},
		{
			name:     "No date",
			date:     "",
			expected: "",
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			assert.Equal(t, tt.expected, shareRelease(tt.date, now))
		})
	}
}

func Test_ShareMeta(t *testing.T) {
	assert.Equal(t, "2010 · 2h 28m · Action", shareMeta("2010", "", "2h 28m", "Action"))
	assert.Empty(t, shareMeta("", ""))
}
