package services

import (
	"context"
	"testing"
	"time"

	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/models"
	"biinge-api/internal/app/repositories"
	"biinge-api/internal/config/cache"
	"biinge-api/pkg/jellyfin"
	"biinge-api/pkg/tmdb"
)

func Test_JellyfinSync_Apply(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	client := tmdb.NewMockClient(ctrl)
	movies := NewMockMovies(ctrl)
	progress := NewMockProgress(ctrl)
	// the service takes no Library, and the strict Jellyfin mock fails on any write, so a poll never writes Jellyfin
	service := NewJellyfinSync(client, jellyfin.NewMockClient(ctrl), movies, progress, repositories.NewMockSeriesProgressRepository(ctrl), NewMockPlayedMemory(ctrl), cache.NewNoopCache(), newTestLogger())

	userId := uuid.New()
	playedAt := time.Date(2026, 11, 1, 20, 30, 0, 0, time.UTC)
	filter := models.MovieFilter{UserId: userId, TmdbIds: []uint64{603}}

	movieDetails := &tmdb.MovieDetails{Id: 603, Title: "The Matrix", PosterPath: "/matrix.jpg", Runtime: 136}

	tvDetails := &tmdb.TvDetails{
		Id:            95396,
		Title:         "Severance",
		PosterPath:    "/severance.jpg",
		Status:        "Returning Series",
		SeasonsCount:  1,
		EpisodesCount: 9,
		Seasons: []tmdb.TvSeason{
			{Id: 10, Name: "Specials", SeasonNumber: 0, EpisodeCount: 1},
			{Id: 11, Name: "Season 1", SeasonNumber: 1, EpisodeCount: 9},
		},
	}

	seasonDetails := &tmdb.SeasonDetails{
		ID:           11,
		SeasonNumber: 1,
		Episodes: []tmdb.Episode{
			{ID: 101, EpisodeNumber: 1, Name: "Good News About Hell", StillPath: "/e1.jpg", Runtime: 57, AirDate: "2022-02-18"},
			{ID: 102, EpisodeNumber: 2, Name: "Half Loop", StillPath: "/e2.jpg", Runtime: 53, AirDate: "2022-02-18"},
		},
	}

	specialsDetails := &tmdb.SeasonDetails{
		ID:           10,
		SeasonNumber: 0,
		Episodes: []tmdb.Episode{
			{ID: 201, EpisodeNumber: 1, Name: "Inside Lumon", StillPath: "/s1.jpg", Runtime: 12},
		},
	}

	seriesInput := models.SeriesInput{
		TmdbId:        95396,
		Title:         "Severance",
		PosterPath:    "/severance.jpg",
		SeasonsCount:  1,
		EpisodesCount: 9,
		Status:        "Returning Series",
	}

	seasonInput := models.SeasonInput{TmdbId: 11, Title: "Season 1", Number: 1, EpisodesCount: 9}

	episodeInput := models.EpisodeInput{
		TmdbId:     101,
		Title:      "Good News About Hell",
		PosterPath: "/e1.jpg",
		Runtime:    57,
		AirAt:      time.Date(2022, 2, 18, 0, 0, 0, 0, time.UTC),
	}

	playedMovie := JellyfinChange{Kind: PlayedMovie, TmdbId: 603, Played: true, LastPlayed: &playedAt}
	unplayedMovie := JellyfinChange{Kind: PlayedMovie, TmdbId: 603, Played: false}
	playedEpisode := JellyfinChange{Kind: PlayedEpisode, TmdbId: 95396, Season: 1, Episode: 1, Played: true, LastPlayed: &playedAt}
	unplayedEpisode := JellyfinChange{Kind: PlayedEpisode, TmdbId: 95396, Season: 1, Episode: 1, Played: false}

	tests := []struct {
		name   string
		change JellyfinChange
		before func()
		error  error
	}{
		{
			name:   "Played movie not in biinge is created watched with the played date",
			change: playedMovie,
			before: func() {
				movies.EXPECT().FindByFilter(ctx, filter).Return([]models.Movie{}, nil)
				client.EXPECT().FetchMovieDetails(ctx, uint64(603)).Return(movieDetails, nil)
				movies.EXPECT().Create(ctx, &models.Movie{
					UserId:     userId,
					TmdbId:     603,
					Title:      "The Matrix",
					PosterPath: "/matrix.jpg",
					Runtime:    136,
					State:      models.StateTypeWatched,
					WatchedAt:  playedAt,
				}).Return(&models.Movie{}, nil)
			},
		},
		{
			name: "Played movie without a played date is created with the date unset",
			change: JellyfinChange{
				Kind:   PlayedMovie,
				TmdbId: 603,
				Played: true,
			},
			before: func() {
				movies.EXPECT().FindByFilter(ctx, filter).Return([]models.Movie{}, nil)
				client.EXPECT().FetchMovieDetails(ctx, uint64(603)).Return(movieDetails, nil)
				movies.EXPECT().Create(ctx, &models.Movie{
					UserId:     userId,
					TmdbId:     603,
					Title:      "The Matrix",
					PosterPath: "/matrix.jpg",
					Runtime:    136,
					State:      models.StateTypeWatched,
				}).Return(&models.Movie{}, nil)
			},
		},
		{
			name:   "Played movie TMDB doesn't know is skipped",
			change: playedMovie,
			before: func() {
				movies.EXPECT().FindByFilter(ctx, filter).Return([]models.Movie{}, nil)
				client.EXPECT().FetchMovieDetails(ctx, uint64(603)).Return(nil, tmdb.ErrNotFound)
			},
		},
		{
			name:   "Played movie with TMDB unavailable fails",
			change: playedMovie,
			before: func() {
				movies.EXPECT().FindByFilter(ctx, filter).Return([]models.Movie{}, nil)
				client.EXPECT().FetchMovieDetails(ctx, uint64(603)).Return(nil, tmdb.ErrFailedToFetchMovieDetails)
			},
			error: errors.ErrFailedToFetchMovie,
		},
		{
			name:   "Played movie create failure fails",
			change: playedMovie,
			before: func() {
				movies.EXPECT().FindByFilter(ctx, filter).Return([]models.Movie{}, nil)
				client.EXPECT().FetchMovieDetails(ctx, uint64(603)).Return(movieDetails, nil)
				movies.EXPECT().Create(ctx, gomock.Any()).Return(nil, errors.ErrFailedToCreateMovie)
			},
			error: errors.ErrFailedToCreateMovie,
		},
		{
			name:   "Played want movie becomes watched with the played date and keeps pinned",
			change: playedMovie,
			before: func() {
				movies.EXPECT().FindByFilter(ctx, filter).Return([]models.Movie{{TmdbId: 603, State: models.StateTypeWant, Pinned: true}}, nil)
				movies.EXPECT().UpdateByTmdbId(ctx, &models.Movie{
					TmdbId:    603,
					UserId:    userId,
					State:     models.StateTypeWatched,
					Pinned:    true,
					WatchedAt: playedAt,
				}).Return(&models.Movie{}, nil)
			},
		},
		{
			name:   "Played watching movie becomes watched with the played date",
			change: playedMovie,
			before: func() {
				movies.EXPECT().FindByFilter(ctx, filter).Return([]models.Movie{{TmdbId: 603, State: models.StateTypeWatching}}, nil)
				movies.EXPECT().UpdateByTmdbId(ctx, &models.Movie{
					TmdbId:    603,
					UserId:    userId,
					State:     models.StateTypeWatched,
					WatchedAt: playedAt,
				}).Return(&models.Movie{}, nil)
			},
		},
		{
			name:   "Played watched movie writes nothing",
			change: playedMovie,
			before: func() {
				movies.EXPECT().FindByFilter(ctx, filter).Return([]models.Movie{{TmdbId: 603, State: models.StateTypeWatched}}, nil)
			},
		},
		{
			name: "Unplayed watched movie becomes want and keeps pinned",
			change: JellyfinChange{
				Kind:       PlayedMovie,
				TmdbId:     603,
				Played:     false,
				LastPlayed: &playedAt,
			},
			before: func() {
				movies.EXPECT().FindByFilter(ctx, filter).Return([]models.Movie{{TmdbId: 603, State: models.StateTypeWatched, Pinned: true}}, nil)
				movies.EXPECT().UpdateByTmdbId(ctx, &models.Movie{
					TmdbId: 603,
					UserId: userId,
					State:  models.StateTypeWant,
					Pinned: true,
				}).Return(&models.Movie{}, nil)
			},
		},
		{
			name:   "Unplayed want movie writes nothing",
			change: unplayedMovie,
			before: func() {
				movies.EXPECT().FindByFilter(ctx, filter).Return([]models.Movie{{TmdbId: 603, State: models.StateTypeWant}}, nil)
			},
		},
		{
			name:   "Unplayed watching movie writes nothing",
			change: unplayedMovie,
			before: func() {
				movies.EXPECT().FindByFilter(ctx, filter).Return([]models.Movie{{TmdbId: 603, State: models.StateTypeWatching}}, nil)
			},
		},
		{
			name:   "Unplayed movie not in biinge writes nothing",
			change: unplayedMovie,
			before: func() {
				movies.EXPECT().FindByFilter(ctx, filter).Return([]models.Movie{}, nil)
			},
		},
		{
			name:   "Movie lookup failure fails",
			change: playedMovie,
			before: func() {
				movies.EXPECT().FindByFilter(ctx, filter).Return(nil, errors.ErrFailedToFetchResults)
			},
			error: errors.ErrFailedToFetchResults,
		},
		{
			name:   "Movie update failure fails",
			change: playedMovie,
			before: func() {
				movies.EXPECT().FindByFilter(ctx, filter).Return([]models.Movie{{TmdbId: 603, State: models.StateTypeWant}}, nil)
				movies.EXPECT().UpdateByTmdbId(ctx, gomock.Any()).Return(nil, errors.ErrFailedToUpdateMovie)
			},
			error: errors.ErrFailedToUpdateMovie,
		},
		{
			name:   "Played episode of a watching show is marked",
			change: playedEpisode,
			before: func() {
				progress.EXPECT().Get(ctx, userId, uint64(95396)).Return(&models.SeriesProgress{State: models.StateTypeWatching, WatchedEpisodes: []uint64{102}}, nil)
				client.EXPECT().FetchTvDetails(ctx, uint64(95396)).Return(tvDetails, nil)
				client.EXPECT().FetchTvSeasonDetails(ctx, uint64(95396), uint64(1)).Return(seasonDetails, nil)
				progress.EXPECT().MarkEpisode(ctx, userId, seriesInput, seasonInput, episodeInput).Return(&models.SeriesProgress{}, nil)
			},
		},
		{
			name:   "Played episode of a watched show is marked",
			change: playedEpisode,
			before: func() {
				progress.EXPECT().Get(ctx, userId, uint64(95396)).Return(&models.SeriesProgress{State: models.StateTypeWatched, WatchedEpisodes: []uint64{102}}, nil)
				client.EXPECT().FetchTvDetails(ctx, uint64(95396)).Return(tvDetails, nil)
				client.EXPECT().FetchTvSeasonDetails(ctx, uint64(95396), uint64(1)).Return(seasonDetails, nil)
				progress.EXPECT().MarkEpisode(ctx, userId, seriesInput, seasonInput, episodeInput).Return(&models.SeriesProgress{}, nil)
			},
		},
		{
			name:   "Played episode of a show not in biinge is marked",
			change: playedEpisode,
			before: func() {
				progress.EXPECT().Get(ctx, userId, uint64(95396)).Return(&models.SeriesProgress{State: models.StateTypeNone}, nil)
				client.EXPECT().FetchTvDetails(ctx, uint64(95396)).Return(tvDetails, nil)
				client.EXPECT().FetchTvSeasonDetails(ctx, uint64(95396), uint64(1)).Return(seasonDetails, nil)
				progress.EXPECT().MarkEpisode(ctx, userId, seriesInput, seasonInput, episodeInput).Return(&models.SeriesProgress{}, nil)
			},
		},
		{
			name: "Played special resolves season 0",
			change: JellyfinChange{
				Kind:    PlayedEpisode,
				TmdbId:  95396,
				Season:  0,
				Episode: 1,
				Played:  true,
			},
			before: func() {
				progress.EXPECT().Get(ctx, userId, uint64(95396)).Return(&models.SeriesProgress{State: models.StateTypeWatching}, nil)
				client.EXPECT().FetchTvDetails(ctx, uint64(95396)).Return(tvDetails, nil)
				client.EXPECT().FetchTvSeasonDetails(ctx, uint64(95396), uint64(0)).Return(specialsDetails, nil)
				progress.EXPECT().MarkEpisode(ctx, userId, seriesInput,
					models.SeasonInput{TmdbId: 10, Title: "Specials", Number: 0, EpisodesCount: 1},
					models.EpisodeInput{TmdbId: 201, Title: "Inside Lumon", PosterPath: "/s1.jpg", Runtime: 12},
				).Return(&models.SeriesProgress{}, nil)
			},
		},
		{
			name:   "Played watched episode writes nothing",
			change: playedEpisode,
			before: func() {
				progress.EXPECT().Get(ctx, userId, uint64(95396)).Return(&models.SeriesProgress{State: models.StateTypeWatching, WatchedEpisodes: []uint64{101}}, nil)
				client.EXPECT().FetchTvDetails(ctx, uint64(95396)).Return(tvDetails, nil)
				client.EXPECT().FetchTvSeasonDetails(ctx, uint64(95396), uint64(1)).Return(seasonDetails, nil)
			},
		},
		{
			name:   "Unplayed watched episode is unmarked",
			change: unplayedEpisode,
			before: func() {
				progress.EXPECT().Get(ctx, userId, uint64(95396)).Return(&models.SeriesProgress{State: models.StateTypeWatching, WatchedEpisodes: []uint64{101}}, nil)
				client.EXPECT().FetchTvDetails(ctx, uint64(95396)).Return(tvDetails, nil)
				client.EXPECT().FetchTvSeasonDetails(ctx, uint64(95396), uint64(1)).Return(seasonDetails, nil)
				progress.EXPECT().UnmarkEpisode(ctx, userId, uint64(95396), uint64(11), uint64(101)).Return(&models.SeriesProgress{}, nil)
			},
		},
		{
			name:   "Unplayed episode not watched writes nothing",
			change: unplayedEpisode,
			before: func() {
				progress.EXPECT().Get(ctx, userId, uint64(95396)).Return(&models.SeriesProgress{State: models.StateTypeWatching, WatchedEpisodes: []uint64{102}}, nil)
				client.EXPECT().FetchTvDetails(ctx, uint64(95396)).Return(tvDetails, nil)
				client.EXPECT().FetchTvSeasonDetails(ctx, uint64(95396), uint64(1)).Return(seasonDetails, nil)
			},
		},
		{
			name:   "Unplayed episode of a show not in biinge writes nothing",
			change: unplayedEpisode,
			before: func() {
				progress.EXPECT().Get(ctx, userId, uint64(95396)).Return(&models.SeriesProgress{State: models.StateTypeNone}, nil)
			},
		},
		{
			name:   "Progress lookup failure fails",
			change: playedEpisode,
			before: func() {
				progress.EXPECT().Get(ctx, userId, uint64(95396)).Return(nil, errors.ErrFailedToFetchProgress)
			},
			error: errors.ErrFailedToFetchProgress,
		},
		{
			name:   "Series TMDB doesn't know is skipped",
			change: playedEpisode,
			before: func() {
				progress.EXPECT().Get(ctx, userId, uint64(95396)).Return(&models.SeriesProgress{State: models.StateTypeNone}, nil)
				client.EXPECT().FetchTvDetails(ctx, uint64(95396)).Return(nil, tmdb.ErrNotFound)
			},
		},
		{
			name:   "Series details with TMDB unavailable fails",
			change: playedEpisode,
			before: func() {
				progress.EXPECT().Get(ctx, userId, uint64(95396)).Return(&models.SeriesProgress{State: models.StateTypeNone}, nil)
				client.EXPECT().FetchTvDetails(ctx, uint64(95396)).Return(nil, tmdb.ErrFailedToFetchTvDetails)
			},
			error: errors.ErrFailedToFetchSeries,
		},
		{
			name: "Season number TMDB doesn't list is skipped",
			change: JellyfinChange{
				Kind:    PlayedEpisode,
				TmdbId:  95396,
				Season:  7,
				Episode: 1,
				Played:  true,
			},
			before: func() {
				progress.EXPECT().Get(ctx, userId, uint64(95396)).Return(&models.SeriesProgress{State: models.StateTypeNone}, nil)
				client.EXPECT().FetchTvDetails(ctx, uint64(95396)).Return(tvDetails, nil)
			},
		},
		{
			name:   "Season TMDB doesn't know is skipped",
			change: playedEpisode,
			before: func() {
				progress.EXPECT().Get(ctx, userId, uint64(95396)).Return(&models.SeriesProgress{State: models.StateTypeNone}, nil)
				client.EXPECT().FetchTvDetails(ctx, uint64(95396)).Return(tvDetails, nil)
				client.EXPECT().FetchTvSeasonDetails(ctx, uint64(95396), uint64(1)).Return(nil, tmdb.ErrNotFound)
			},
		},
		{
			name:   "Season details with TMDB unavailable fails",
			change: playedEpisode,
			before: func() {
				progress.EXPECT().Get(ctx, userId, uint64(95396)).Return(&models.SeriesProgress{State: models.StateTypeNone}, nil)
				client.EXPECT().FetchTvDetails(ctx, uint64(95396)).Return(tvDetails, nil)
				client.EXPECT().FetchTvSeasonDetails(ctx, uint64(95396), uint64(1)).Return(nil, assert.AnError)
			},
			error: errors.ErrFailedToFetchSeries,
		},
		{
			name: "Episode number TMDB doesn't list is skipped",
			change: JellyfinChange{
				Kind:    PlayedEpisode,
				TmdbId:  95396,
				Season:  1,
				Episode: 40,
				Played:  true,
			},
			before: func() {
				progress.EXPECT().Get(ctx, userId, uint64(95396)).Return(&models.SeriesProgress{State: models.StateTypeNone}, nil)
				client.EXPECT().FetchTvDetails(ctx, uint64(95396)).Return(tvDetails, nil)
				client.EXPECT().FetchTvSeasonDetails(ctx, uint64(95396), uint64(1)).Return(seasonDetails, nil)
			},
		},
		{
			name:   "Episode mark failure fails",
			change: playedEpisode,
			before: func() {
				progress.EXPECT().Get(ctx, userId, uint64(95396)).Return(&models.SeriesProgress{State: models.StateTypeWatching}, nil)
				client.EXPECT().FetchTvDetails(ctx, uint64(95396)).Return(tvDetails, nil)
				client.EXPECT().FetchTvSeasonDetails(ctx, uint64(95396), uint64(1)).Return(seasonDetails, nil)
				progress.EXPECT().MarkEpisode(ctx, userId, seriesInput, seasonInput, episodeInput).Return(nil, errors.ErrFailedToUpdateProgress)
			},
			error: errors.ErrFailedToUpdateProgress,
		},
		{
			name:   "Episode unmark failure fails",
			change: unplayedEpisode,
			before: func() {
				progress.EXPECT().Get(ctx, userId, uint64(95396)).Return(&models.SeriesProgress{State: models.StateTypeWatching, WatchedEpisodes: []uint64{101}}, nil)
				client.EXPECT().FetchTvDetails(ctx, uint64(95396)).Return(tvDetails, nil)
				client.EXPECT().FetchTvSeasonDetails(ctx, uint64(95396), uint64(1)).Return(seasonDetails, nil)
				progress.EXPECT().UnmarkEpisode(ctx, userId, uint64(95396), uint64(11), uint64(101)).Return(nil, errors.ErrFailedToUpdateProgress)
			},
			error: errors.ErrFailedToUpdateProgress,
		},
		{
			name: "Series kind writes nothing",
			change: JellyfinChange{
				Kind:   PlayedSeries,
				TmdbId: 95396,
				Played: true,
			},
			before: func() {},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			err := service.Apply(ctx, userId, tt.change)

			if tt.error != nil {
				require.ErrorIs(t, err, tt.error)
				return
			}

			require.NoError(t, err)
		})
	}
}

func Test_JellyfinSync_Reconcile(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	tmdbClient := tmdb.NewMockClient(ctrl)
	client := jellyfin.NewMockClient(ctrl)
	movies := NewMockMovies(ctrl)
	progress := NewMockProgress(ctrl)
	repository := repositories.NewMockSeriesProgressRepository(ctrl)
	memory := NewMockPlayedMemory(ctrl)
	// the service takes no Library, so every write goes to the client directly instead of the played-write queue
	service := NewJellyfinSync(tmdbClient, client, movies, progress, repository, memory, cache.NewNoopCache(), newTestLogger())

	userId := uuid.New()
	key := PlayedKey{UserId: userId, JellyfinUserId: "jf-user"}
	connection := jellyfin.Connection{DeviceId: "biinge-api-" + userId.String(), AccessToken: "token", UserId: "jf-user"}
	watchedAt := time.Date(2026, 10, 1, 21, 0, 0, 0, time.UTC)
	filter := models.MovieFilter{UserId: userId, TmdbIds: []uint64{603}}

	tvDetails := &tmdb.TvDetails{
		Id: 95396,
		Seasons: []tmdb.TvSeason{
			{Id: 10, SeasonNumber: 0},
			{Id: 11, SeasonNumber: 1},
		},
	}

	seasonDetails := &tmdb.SeasonDetails{ID: 11, SeasonNumber: 1, Episodes: []tmdb.Episode{{ID: 101, EpisodeNumber: 1}, {ID: 102, EpisodeNumber: 2}}}
	specialsDetails := &tmdb.SeasonDetails{ID: 10, SeasonNumber: 0, Episodes: []tmdb.Episode{{ID: 201, EpisodeNumber: 1}}}

	movie := func(played bool) JellyfinItem {
		return JellyfinItem{Id: "movie", JellyfinChange: JellyfinChange{Kind: PlayedMovie, TmdbId: 603, Played: played}}
	}

	episode := func(id string, season, number uint64, played bool) JellyfinItem {
		return JellyfinItem{Id: id, JellyfinChange: JellyfinChange{Kind: PlayedEpisode, TmdbId: 95396, Season: season, Episode: number, Played: played}}
	}

	tests := []struct {
		name   string
		items  []JellyfinItem
		before func()
		error  error
	}{
		{
			name:  "Watched movie unplayed in Jellyfin is marked played with its watched_at",
			items: []JellyfinItem{movie(false)},
			before: func() {
				movies.EXPECT().FindByFilter(ctx, filter).Return([]models.Movie{{TmdbId: 603, State: models.StateTypeWatched, WatchedAt: watchedAt}}, nil)
				gomock.InOrder(
					client.EXPECT().SetPlayed(ctx, connection, jellyfin.PlayedState{ItemId: "movie", Played: true, DatePlayed: &watchedAt}).Return(nil),
					memory.EXPECT().Record(key, "movie", true),
				)
			},
		},
		{
			name:  "Watched movie without a watched_at is marked played without a date",
			items: []JellyfinItem{movie(false)},
			before: func() {
				movies.EXPECT().FindByFilter(ctx, filter).Return([]models.Movie{{TmdbId: 603, State: models.StateTypeWatched}}, nil)
				client.EXPECT().SetPlayed(ctx, connection, jellyfin.PlayedState{ItemId: "movie", Played: true}).Return(nil)
				memory.EXPECT().Record(key, "movie", true)
			},
		},
		{
			name:  "Movie not watched in biinge is marked unplayed without a date",
			items: []JellyfinItem{movie(true)},
			before: func() {
				movies.EXPECT().FindByFilter(ctx, filter).Return([]models.Movie{{TmdbId: 603, State: models.StateTypeWant}}, nil)
				client.EXPECT().SetPlayed(ctx, connection, jellyfin.PlayedState{ItemId: "movie", Played: false}).Return(nil)
				memory.EXPECT().Record(key, "movie", false)
			},
		},
		{
			name:  "Watched movie played in Jellyfin writes nothing",
			items: []JellyfinItem{movie(true)},
			before: func() {
				movies.EXPECT().FindByFilter(ctx, filter).Return([]models.Movie{{TmdbId: 603, State: models.StateTypeWatched, WatchedAt: watchedAt}}, nil)
			},
		},
		{
			name:  "Watching movie unplayed in Jellyfin writes nothing",
			items: []JellyfinItem{movie(false)},
			before: func() {
				movies.EXPECT().FindByFilter(ctx, filter).Return([]models.Movie{{TmdbId: 603, State: models.StateTypeWatching}}, nil)
			},
		},
		{
			name:  "Untracked movie is left alone",
			items: []JellyfinItem{movie(true)},
			before: func() {
				movies.EXPECT().FindByFilter(ctx, filter).Return([]models.Movie{}, nil)
			},
		},
		{
			name:  "Movie read failure fails and writes nothing",
			items: []JellyfinItem{movie(false)},
			before: func() {
				movies.EXPECT().FindByFilter(ctx, filter).Return(nil, errors.ErrFailedToFetchResults)
			},
			error: errors.ErrFailedToFetchResults,
		},
		{
			name: "Failed write is skipped without a record and the rest continue",
			items: []JellyfinItem{
				{Id: "first", JellyfinChange: JellyfinChange{Kind: PlayedMovie, TmdbId: 603}},
				{Id: "second", JellyfinChange: JellyfinChange{Kind: PlayedMovie, TmdbId: 604}},
			},
			before: func() {
				movies.EXPECT().FindByFilter(ctx, models.MovieFilter{UserId: userId, TmdbIds: []uint64{603, 604}}).Return([]models.Movie{
					{TmdbId: 603, State: models.StateTypeWatched, WatchedAt: watchedAt},
					{TmdbId: 604, State: models.StateTypeWatched, WatchedAt: watchedAt},
				}, nil)
				client.EXPECT().SetPlayed(ctx, connection, jellyfin.PlayedState{ItemId: "first", Played: true, DatePlayed: &watchedAt}).Return(jellyfin.ErrUnavailable)
				client.EXPECT().SetPlayed(ctx, connection, jellyfin.PlayedState{ItemId: "second", Played: true, DatePlayed: &watchedAt}).Return(nil)
				memory.EXPECT().Record(key, "second", true)
			},
		},
		{
			name: "Episodes take biinge's watched state and its watched_at",
			items: []JellyfinItem{
				episode("s1e1", 1, 1, false),
				episode("s1e2", 1, 2, true),
				episode("s0e1", 0, 1, false),
			},
			before: func() {
				progress.EXPECT().Get(ctx, userId, uint64(95396)).Return(&models.SeriesProgress{State: models.StateTypeWatching}, nil)
				repository.EXPECT().WatchedEpisodes(ctx, userId, uint64(95396)).Return(map[uint64]time.Time{101: watchedAt}, nil)
				tmdbClient.EXPECT().FetchTvDetails(ctx, uint64(95396)).Return(tvDetails, nil)
				tmdbClient.EXPECT().FetchTvSeasonDetails(ctx, uint64(95396), uint64(1)).Return(seasonDetails, nil)
				tmdbClient.EXPECT().FetchTvSeasonDetails(ctx, uint64(95396), uint64(0)).Return(specialsDetails, nil)
				client.EXPECT().SetPlayed(ctx, connection, jellyfin.PlayedState{ItemId: "s1e1", Played: true, DatePlayed: &watchedAt}).Return(nil)
				client.EXPECT().SetPlayed(ctx, connection, jellyfin.PlayedState{ItemId: "s1e2", Played: false}).Return(nil)
				memory.EXPECT().Record(key, "s1e1", true)
				memory.EXPECT().Record(key, "s1e2", false)
			},
		},
		{
			name:  "Episodes of an untracked show are left alone",
			items: []JellyfinItem{episode("s1e1", 1, 1, true)},
			before: func() {
				progress.EXPECT().Get(ctx, userId, uint64(95396)).Return(&models.SeriesProgress{State: models.StateTypeNone}, nil)
			},
		},
		{
			name:  "Episodes of a show TMDB doesn't know are skipped",
			items: []JellyfinItem{episode("s1e1", 1, 1, true)},
			before: func() {
				progress.EXPECT().Get(ctx, userId, uint64(95396)).Return(&models.SeriesProgress{State: models.StateTypeWant}, nil)
				repository.EXPECT().WatchedEpisodes(ctx, userId, uint64(95396)).Return(map[uint64]time.Time{}, nil)
				tmdbClient.EXPECT().FetchTvDetails(ctx, uint64(95396)).Return(nil, tmdb.ErrNotFound)
			},
		},
		{
			name:  "Episodes of a show whose TMDB details fail are skipped",
			items: []JellyfinItem{episode("s1e1", 1, 1, true)},
			before: func() {
				progress.EXPECT().Get(ctx, userId, uint64(95396)).Return(&models.SeriesProgress{State: models.StateTypeWant}, nil)
				repository.EXPECT().WatchedEpisodes(ctx, userId, uint64(95396)).Return(map[uint64]time.Time{}, nil)
				tmdbClient.EXPECT().FetchTvDetails(ctx, uint64(95396)).Return(nil, assert.AnError)
			},
		},
		{
			name: "Episodes of a season TMDB doesn't list are skipped and the rest continue",
			items: []JellyfinItem{
				episode("s5e1", 5, 1, true),
				episode("s1e1", 1, 1, true),
			},
			before: func() {
				progress.EXPECT().Get(ctx, userId, uint64(95396)).Return(&models.SeriesProgress{State: models.StateTypeWant}, nil)
				repository.EXPECT().WatchedEpisodes(ctx, userId, uint64(95396)).Return(map[uint64]time.Time{}, nil)
				tmdbClient.EXPECT().FetchTvDetails(ctx, uint64(95396)).Return(tvDetails, nil)
				tmdbClient.EXPECT().FetchTvSeasonDetails(ctx, uint64(95396), uint64(1)).Return(seasonDetails, nil)
				client.EXPECT().SetPlayed(ctx, connection, jellyfin.PlayedState{ItemId: "s1e1", Played: false}).Return(nil)
				memory.EXPECT().Record(key, "s1e1", false)
			},
		},
		{
			name: "Episode TMDB doesn't list is skipped and the rest continue",
			items: []JellyfinItem{
				episode("s1e40", 1, 40, true),
				episode("s1e1", 1, 1, true),
			},
			before: func() {
				progress.EXPECT().Get(ctx, userId, uint64(95396)).Return(&models.SeriesProgress{State: models.StateTypeWant}, nil)
				repository.EXPECT().WatchedEpisodes(ctx, userId, uint64(95396)).Return(map[uint64]time.Time{}, nil)
				tmdbClient.EXPECT().FetchTvDetails(ctx, uint64(95396)).Return(tvDetails, nil)
				tmdbClient.EXPECT().FetchTvSeasonDetails(ctx, uint64(95396), uint64(1)).Return(seasonDetails, nil)
				client.EXPECT().SetPlayed(ctx, connection, jellyfin.PlayedState{ItemId: "s1e1", Played: false}).Return(nil)
				memory.EXPECT().Record(key, "s1e1", false)
			},
		},
		{
			name:  "Episodes of a season TMDB doesn't know are skipped",
			items: []JellyfinItem{episode("s1e1", 1, 1, true)},
			before: func() {
				progress.EXPECT().Get(ctx, userId, uint64(95396)).Return(&models.SeriesProgress{State: models.StateTypeWant}, nil)
				repository.EXPECT().WatchedEpisodes(ctx, userId, uint64(95396)).Return(map[uint64]time.Time{}, nil)
				tmdbClient.EXPECT().FetchTvDetails(ctx, uint64(95396)).Return(tvDetails, nil)
				tmdbClient.EXPECT().FetchTvSeasonDetails(ctx, uint64(95396), uint64(1)).Return(nil, tmdb.ErrNotFound)
			},
		},
		{
			name:  "Season details failure skips the series and the movies are still written",
			items: []JellyfinItem{movie(false), episode("s1e1", 1, 1, true)},
			before: func() {
				movies.EXPECT().FindByFilter(ctx, filter).Return([]models.Movie{{TmdbId: 603, State: models.StateTypeWatched, WatchedAt: watchedAt}}, nil)
				progress.EXPECT().Get(ctx, userId, uint64(95396)).Return(&models.SeriesProgress{State: models.StateTypeWant}, nil)
				repository.EXPECT().WatchedEpisodes(ctx, userId, uint64(95396)).Return(map[uint64]time.Time{}, nil)
				tmdbClient.EXPECT().FetchTvDetails(ctx, uint64(95396)).Return(tvDetails, nil)
				tmdbClient.EXPECT().FetchTvSeasonDetails(ctx, uint64(95396), uint64(1)).Return(nil, assert.AnError)
				client.EXPECT().SetPlayed(ctx, connection, jellyfin.PlayedState{ItemId: "movie", Played: true, DatePlayed: &watchedAt}).Return(nil)
				memory.EXPECT().Record(key, "movie", true)
			},
		},
		{
			name:  "Progress failure fails and writes nothing",
			items: []JellyfinItem{episode("s1e1", 1, 1, true)},
			before: func() {
				progress.EXPECT().Get(ctx, userId, uint64(95396)).Return(nil, errors.ErrFailedToFetchProgress)
			},
			error: errors.ErrFailedToFetchProgress,
		},
		{
			name:  "Watched episodes failure fails and writes nothing",
			items: []JellyfinItem{episode("s1e1", 1, 1, true)},
			before: func() {
				progress.EXPECT().Get(ctx, userId, uint64(95396)).Return(&models.SeriesProgress{State: models.StateTypeWatching}, nil)
				repository.EXPECT().WatchedEpisodes(ctx, userId, uint64(95396)).Return(nil, assert.AnError)
			},
			error: errors.ErrFailedToFetchProgress,
		},
		{
			name:   "Empty read writes nothing",
			before: func() {},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			err := service.Reconcile(ctx, &JellyfinRead{Key: key, Connection: connection, Items: tt.items})

			if tt.error != nil {
				require.ErrorIs(t, err, tt.error)
				return
			}

			require.NoError(t, err)
		})
	}
}
