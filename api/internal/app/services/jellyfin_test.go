package services

import (
	"context"
	"encoding/json"
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

// jellyfinEvent builds a played, finished event of the given item type with the provider ids set
func jellyfinEvent(itemType string, providers map[string]string) *jellyfin.Event {
	return &jellyfin.Event{
		ItemType:     itemType,
		SaveReason:   jellyfin.SaveReasonPlaybackFinished,
		Played:       true,
		ProviderTmdb: providers["tmdb"],
		ProviderImdb: providers["imdb"],
		ProviderTvdb: providers["tvdb"],
		Name:         "Some Title",
		Raw:          json.RawMessage(`{"ItemType":"` + itemType + `","Extra":"kept"}`),
	}
}

func Test_Jellyfin_Handle(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	client := tmdb.NewMockClient(ctrl)
	movies := NewMockMovies(ctrl)
	progress := NewMockProgress(ctrl)
	webhooks := repositories.NewMockWebhookRepository(ctrl)
	service := NewJellyfin(client, movies, progress, webhooks, cache.NewNoopCache(), newTestLogger())

	userId := uuid.New()
	link := &models.Integration{ID: uuid.New(), UserId: userId, Provider: models.JellyfinProvider}

	const (
		movieId   uint64 = 603
		showId    uint64 = 1399
		seasonId  uint64 = 3624
		episodeId uint64 = 63056
	)

	movieFilter := models.MovieFilter{UserId: userId, TmdbIds: []uint64{movieId}}
	markWatched := &models.Movie{TmdbId: movieId, UserId: userId, State: models.StateTypeWatched}
	markWatchedPinned := &models.Movie{TmdbId: movieId, UserId: userId, State: models.StateTypeWatched, Pinned: true}
	foundEpisode := &tmdb.FindResult{TvEpisodeResults: []tmdb.FindEpisode{{
		Episode: tmdb.Episode{ID: int(episodeId), Name: "Winter Is Coming", AirDate: "2011-04-17", EpisodeNumber: 1, SeasonNumber: 1, StillPath: "/w.jpg", Runtime: 62},
		ShowId:  showId,
	}}}
	showDetails := &tmdb.TvDetails{
		Id:            int(showId),
		Title:         "Game of Thrones",
		PosterPath:    "/got.jpg",
		Status:        "Ended",
		SeasonsCount:  8,
		EpisodesCount: 73,
		Seasons: []tmdb.TvSeason{
			{Id: 3627, Name: "Specials", SeasonNumber: 0, EpisodeCount: 100},
			{Id: seasonId, Name: "Season 1", SeasonNumber: 1, EpisodeCount: 10},
		},
	}
	seriesInput := models.SeriesInput{TmdbId: showId, Title: "Game of Thrones", PosterPath: "/got.jpg", SeasonsCount: 8, EpisodesCount: 73, Status: "Ended"}
	seasonInput := models.SeasonInput{TmdbId: seasonId, Title: "Season 1", Number: 1, EpisodesCount: 10}
	episodeInput := models.EpisodeInput{TmdbId: episodeId, Title: "Winter Is Coming", PosterPath: "/w.jpg", Runtime: 62, AirAt: time.Date(2011, 4, 17, 0, 0, 0, 0, time.UTC)}

	tests := []struct {
		name   string
		event  *jellyfin.Event
		before func()
		noRow  bool
		status models.WebhookStatus
		reason string
		error  error
	}{
		{
			name: "Unplayed event is dropped before any work",
			event: func() *jellyfin.Event {
				event := jellyfinEvent(jellyfin.ItemTypeMovie, map[string]string{"tmdb": "603"})
				event.Played = false

				return event
			}(),
			before: func() {},
			noRow:  true,
		},
		{
			name: "Progress save is dropped before any work",
			event: func() *jellyfin.Event {
				event := jellyfinEvent(jellyfin.ItemTypeMovie, map[string]string{"tmdb": "603"})
				event.SaveReason = "PlaybackProgress"

				return event
			}(),
			before: func() {},
			noRow:  true,
		},
		{
			name: "Toggle played counts as a finish",
			event: func() *jellyfin.Event {
				event := jellyfinEvent(jellyfin.ItemTypeMovie, map[string]string{"tmdb": "603"})
				event.SaveReason = jellyfin.SaveReasonTogglePlayed

				return event
			}(),
			before: func() {
				movies.EXPECT().FindByFilter(ctx, movieFilter).Return([]models.Movie{{TmdbId: movieId, State: models.StateTypeWant}}, nil)
				movies.EXPECT().UpdateByTmdbId(ctx, markWatched).Return(&models.Movie{}, nil)
			},
			status: models.WebhookStatusMarked,
		},
		{
			name:   "Other item types are ignored",
			event:  jellyfinEvent("Season", map[string]string{"tmdb": "1399"}),
			before: func() {},
			status: models.WebhookStatusIgnored,
		},
		{
			name:  "Movie not in the library is ignored",
			event: jellyfinEvent(jellyfin.ItemTypeMovie, map[string]string{"tmdb": "603"}),
			before: func() {
				movies.EXPECT().FindByFilter(ctx, movieFilter).Return([]models.Movie{}, nil)
			},
			status: models.WebhookStatusIgnored,
		},
		{
			name:  "Movie in want is marked",
			event: jellyfinEvent(jellyfin.ItemTypeMovie, map[string]string{"tmdb": "603"}),
			before: func() {
				movies.EXPECT().FindByFilter(ctx, movieFilter).Return([]models.Movie{{TmdbId: movieId, State: models.StateTypeWant}}, nil)
				movies.EXPECT().UpdateByTmdbId(ctx, markWatched).Return(&models.Movie{}, nil)
			},
			status: models.WebhookStatusMarked,
		},
		{
			name:  "Movie already watched is ignored",
			event: jellyfinEvent(jellyfin.ItemTypeMovie, map[string]string{"tmdb": "603"}),
			before: func() {
				movies.EXPECT().FindByFilter(ctx, movieFilter).Return([]models.Movie{{TmdbId: movieId, State: models.StateTypeWatched, Pinned: true}}, nil)
			},
			status: models.WebhookStatusIgnored,
		},
		{
			name:  "Movie in watching is marked and keeps pinned",
			event: jellyfinEvent(jellyfin.ItemTypeMovie, map[string]string{"tmdb": "603"}),
			before: func() {
				movies.EXPECT().FindByFilter(ctx, movieFilter).Return([]models.Movie{{TmdbId: movieId, State: models.StateTypeWatching, Pinned: true}}, nil)
				movies.EXPECT().UpdateByTmdbId(ctx, markWatchedPinned).Return(&models.Movie{}, nil)
			},
			status: models.WebhookStatusMarked,
		},
		{
			name:   "Movie without a TMDB id is unresolved",
			event:  jellyfinEvent(jellyfin.ItemTypeMovie, map[string]string{"imdb": "tt0133093"}),
			before: func() {},
			status: models.WebhookStatusUnresolved,
			reason: errors.ErrMissingProviderId.Error(),
			error:  errors.ErrMissingProviderId,
		},
		{
			name:   "Movie with a non-numeric TMDB id is unresolved",
			event:  jellyfinEvent(jellyfin.ItemTypeMovie, map[string]string{"tmdb": "abc"}),
			before: func() {},
			status: models.WebhookStatusUnresolved,
			reason: errors.ErrMissingProviderId.Error(),
			error:  errors.ErrMissingProviderId,
		},
		{
			name:  "Movie library read failing is failed",
			event: jellyfinEvent(jellyfin.ItemTypeMovie, map[string]string{"tmdb": "603"}),
			before: func() {
				movies.EXPECT().FindByFilter(ctx, movieFilter).Return(nil, errors.ErrFailedToFetchResults)
			},
			status: models.WebhookStatusFailed,
			reason: errors.ErrFailedToProcessWebhook.Error(),
			error:  errors.ErrFailedToProcessWebhook,
		},
		{
			name:  "Movie mark failing is failed",
			event: jellyfinEvent(jellyfin.ItemTypeMovie, map[string]string{"tmdb": "603"}),
			before: func() {
				movies.EXPECT().FindByFilter(ctx, movieFilter).Return([]models.Movie{{TmdbId: movieId, State: models.StateTypeWant}}, nil)
				movies.EXPECT().UpdateByTmdbId(ctx, markWatched).Return(nil, errors.ErrFailedToUpdateMovie)
			},
			status: models.WebhookStatusFailed,
			reason: errors.ErrFailedToProcessWebhook.Error(),
			error:  errors.ErrFailedToProcessWebhook,
		},
		{
			name:   "Episode without provider ids is unresolved",
			event:  jellyfinEvent(jellyfin.ItemTypeEpisode, map[string]string{"tmdb": "1399"}),
			before: func() {},
			status: models.WebhookStatusUnresolved,
			reason: errors.ErrMissingProviderId.Error(),
			error:  errors.ErrMissingProviderId,
		},
		{
			name:  "Episode of a show not in the library is ignored",
			event: jellyfinEvent(jellyfin.ItemTypeEpisode, map[string]string{"tvdb": "3254641"}),
			before: func() {
				client.EXPECT().Find(ctx, "3254641", tmdb.FindSourceTvdb).Return(foundEpisode, nil)
				progress.EXPECT().Get(ctx, userId, showId).Return(&models.SeriesProgress{SeriesTmdbId: showId, State: models.StateTypeNone}, nil)
			},
			status: models.WebhookStatusIgnored,
		},
		{
			name:  "Episode already watched is ignored, not cascaded",
			event: jellyfinEvent(jellyfin.ItemTypeEpisode, map[string]string{"tvdb": "3254641"}),
			before: func() {
				client.EXPECT().Find(ctx, "3254641", tmdb.FindSourceTvdb).Return(foundEpisode, nil)
				progress.EXPECT().Get(ctx, userId, showId).Return(&models.SeriesProgress{SeriesTmdbId: showId, State: models.StateTypeWatching, WatchedEpisodes: []uint64{episodeId}}, nil)
			},
			status: models.WebhookStatusIgnored,
		},
		{
			name:  "Episode missing from a watched show is ignored",
			event: jellyfinEvent(jellyfin.ItemTypeEpisode, map[string]string{"tvdb": "3254641"}),
			before: func() {
				client.EXPECT().Find(ctx, "3254641", tmdb.FindSourceTvdb).Return(foundEpisode, nil)
				progress.EXPECT().Get(ctx, userId, showId).Return(&models.SeriesProgress{SeriesTmdbId: showId, State: models.StateTypeWatched, WatchedEpisodes: []uint64{1, 2}}, nil)
			},
			status: models.WebhookStatusIgnored,
		},
		{
			name:  "Episode of a watching show is marked through the cascade",
			event: jellyfinEvent(jellyfin.ItemTypeEpisode, map[string]string{"tvdb": "3254641"}),
			before: func() {
				client.EXPECT().Find(ctx, "3254641", tmdb.FindSourceTvdb).Return(foundEpisode, nil)
				progress.EXPECT().Get(ctx, userId, showId).Return(&models.SeriesProgress{SeriesTmdbId: showId, State: models.StateTypeWatching, WatchedEpisodes: []uint64{1}}, nil)
				client.EXPECT().FetchTvDetails(ctx, showId).Return(showDetails, nil)
				progress.EXPECT().MarkEpisode(ctx, userId, seriesInput, seasonInput, episodeInput).Return(&models.SeriesProgress{}, nil)
			},
			status: models.WebhookStatusMarked,
		},
		{
			name:  "Episode of a want show resolves through the IMDb id and is marked",
			event: jellyfinEvent(jellyfin.ItemTypeEpisode, map[string]string{"imdb": "tt1480055"}),
			before: func() {
				client.EXPECT().Find(ctx, "tt1480055", tmdb.FindSourceImdb).Return(foundEpisode, nil)
				progress.EXPECT().Get(ctx, userId, showId).Return(&models.SeriesProgress{SeriesTmdbId: showId, State: models.StateTypeWant}, nil)
				client.EXPECT().FetchTvDetails(ctx, showId).Return(showDetails, nil)
				progress.EXPECT().MarkEpisode(ctx, userId, seriesInput, seasonInput, episodeInput).Return(&models.SeriesProgress{}, nil)
			},
			status: models.WebhookStatusMarked,
		},
		{
			name:  "TVDB id wins over the IMDb id",
			event: jellyfinEvent(jellyfin.ItemTypeEpisode, map[string]string{"tvdb": "3254641", "imdb": "tt1480055"}),
			before: func() {
				client.EXPECT().Find(ctx, "3254641", tmdb.FindSourceTvdb).Return(foundEpisode, nil)
				progress.EXPECT().Get(ctx, userId, showId).Return(&models.SeriesProgress{SeriesTmdbId: showId, State: models.StateTypeNone}, nil)
			},
			status: models.WebhookStatusIgnored,
		},
		{
			name:  "Episode id unknown to TMDB is unresolved",
			event: jellyfinEvent(jellyfin.ItemTypeEpisode, map[string]string{"tvdb": "1"}),
			before: func() {
				client.EXPECT().Find(ctx, "1", tmdb.FindSourceTvdb).Return(nil, tmdb.ErrNotFound)
			},
			status: models.WebhookStatusUnresolved,
			reason: errors.ErrTitleNotFound.Error(),
			error:  errors.ErrTitleNotFound,
		},
		{
			name:  "Episode id with no episode result is unresolved",
			event: jellyfinEvent(jellyfin.ItemTypeEpisode, map[string]string{"tvdb": "1"}),
			before: func() {
				client.EXPECT().Find(ctx, "1", tmdb.FindSourceTvdb).Return(&tmdb.FindResult{}, nil)
			},
			status: models.WebhookStatusUnresolved,
			reason: errors.ErrTitleNotFound.Error(),
			error:  errors.ErrTitleNotFound,
		},
		{
			name:  "Episode result without a show id is unresolved",
			event: jellyfinEvent(jellyfin.ItemTypeEpisode, map[string]string{"tvdb": "1"}),
			before: func() {
				client.EXPECT().Find(ctx, "1", tmdb.FindSourceTvdb).Return(&tmdb.FindResult{TvEpisodeResults: []tmdb.FindEpisode{{Episode: tmdb.Episode{ID: 5}}}}, nil)
			},
			status: models.WebhookStatusUnresolved,
			reason: errors.ErrTitleNotFound.Error(),
			error:  errors.ErrTitleNotFound,
		},
		{
			name:  "Episode lookup failing on TMDB is failed",
			event: jellyfinEvent(jellyfin.ItemTypeEpisode, map[string]string{"tvdb": "3254641"}),
			before: func() {
				client.EXPECT().Find(ctx, "3254641", tmdb.FindSourceTvdb).Return(nil, tmdb.ErrAccessForbidden)
			},
			status: models.WebhookStatusFailed,
			reason: errors.ErrTmdbUnavailable.Error(),
			error:  errors.ErrTmdbUnavailable,
		},
		{
			name:  "Progress read failing is failed",
			event: jellyfinEvent(jellyfin.ItemTypeEpisode, map[string]string{"tvdb": "3254641"}),
			before: func() {
				client.EXPECT().Find(ctx, "3254641", tmdb.FindSourceTvdb).Return(foundEpisode, nil)
				progress.EXPECT().Get(ctx, userId, showId).Return(nil, errors.ErrFailedToFetchProgress)
			},
			status: models.WebhookStatusFailed,
			reason: errors.ErrFailedToProcessWebhook.Error(),
			error:  errors.ErrFailedToProcessWebhook,
		},
		{
			name:  "Show details failing on TMDB is failed",
			event: jellyfinEvent(jellyfin.ItemTypeEpisode, map[string]string{"tvdb": "3254641"}),
			before: func() {
				client.EXPECT().Find(ctx, "3254641", tmdb.FindSourceTvdb).Return(foundEpisode, nil)
				progress.EXPECT().Get(ctx, userId, showId).Return(&models.SeriesProgress{SeriesTmdbId: showId, State: models.StateTypeWatching}, nil)
				client.EXPECT().FetchTvDetails(ctx, showId).Return(nil, tmdb.ErrUnexpectedResponse)
			},
			status: models.WebhookStatusFailed,
			reason: errors.ErrTmdbUnavailable.Error(),
			error:  errors.ErrTmdbUnavailable,
		},
		{
			name:  "Show unknown to TMDB is unresolved",
			event: jellyfinEvent(jellyfin.ItemTypeEpisode, map[string]string{"tvdb": "3254641"}),
			before: func() {
				client.EXPECT().Find(ctx, "3254641", tmdb.FindSourceTvdb).Return(foundEpisode, nil)
				progress.EXPECT().Get(ctx, userId, showId).Return(&models.SeriesProgress{SeriesTmdbId: showId, State: models.StateTypeWatching}, nil)
				client.EXPECT().FetchTvDetails(ctx, showId).Return(nil, tmdb.ErrNotFound)
			},
			status: models.WebhookStatusUnresolved,
			reason: errors.ErrTitleNotFound.Error(),
			error:  errors.ErrTitleNotFound,
		},
		{
			name:  "Show details without the season is unresolved",
			event: jellyfinEvent(jellyfin.ItemTypeEpisode, map[string]string{"tvdb": "3254641"}),
			before: func() {
				client.EXPECT().Find(ctx, "3254641", tmdb.FindSourceTvdb).Return(foundEpisode, nil)
				progress.EXPECT().Get(ctx, userId, showId).Return(&models.SeriesProgress{SeriesTmdbId: showId, State: models.StateTypeWatching}, nil)
				client.EXPECT().FetchTvDetails(ctx, showId).Return(&tmdb.TvDetails{Seasons: []tmdb.TvSeason{{Id: 1, SeasonNumber: 2}}}, nil)
			},
			status: models.WebhookStatusUnresolved,
			reason: errors.ErrTitleNotFound.Error(),
			error:  errors.ErrTitleNotFound,
		},
		{
			name:  "Episode mark failing is failed",
			event: jellyfinEvent(jellyfin.ItemTypeEpisode, map[string]string{"tvdb": "3254641"}),
			before: func() {
				client.EXPECT().Find(ctx, "3254641", tmdb.FindSourceTvdb).Return(foundEpisode, nil)
				progress.EXPECT().Get(ctx, userId, showId).Return(&models.SeriesProgress{SeriesTmdbId: showId, State: models.StateTypeWatching}, nil)
				client.EXPECT().FetchTvDetails(ctx, showId).Return(showDetails, nil)
				progress.EXPECT().MarkEpisode(ctx, userId, seriesInput, seasonInput, episodeInput).Return(nil, errors.ErrFailedToUpdateProgress)
			},
			status: models.WebhookStatusFailed,
			reason: errors.ErrFailedToProcessWebhook.Error(),
			error:  errors.ErrFailedToProcessWebhook,
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			tt.before()

			var stored *models.Webhook

			if !tt.noRow {
				webhooks.EXPECT().
					Create(ctx, gomock.Any()).
					DoAndReturn(func(_ context.Context, params *models.Webhook) error {
						stored = params
						return nil
					})
			}

			err := service.Handle(ctx, link, tt.event)

			if tt.error != nil {
				require.ErrorIs(t, err, tt.error)
			} else {
				require.NoError(t, err)
			}

			if tt.noRow {
				assert.Nil(t, stored)
				return
			}

			require.NotNil(t, stored)
			assert.Equal(t, link.ID, stored.IntegrationId)
			assert.Equal(t, tt.status, stored.Status)
			assert.Equal(t, tt.reason, stored.Error)
			assert.JSONEq(t, string(tt.event.Raw), string(stored.Payload))
		})
	}
}

func Test_Jellyfin_Handle_TraceFailure(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	ctx := context.Background()
	client := tmdb.NewMockClient(ctrl)
	movies := NewMockMovies(ctrl)
	progress := NewMockProgress(ctrl)
	webhooks := repositories.NewMockWebhookRepository(ctrl)
	service := NewJellyfin(client, movies, progress, webhooks, cache.NewNoopCache(), newTestLogger())

	userId := uuid.New()
	link := &models.Integration{ID: uuid.New(), UserId: userId}

	// the mark lands, but without its trace row the event is not accepted
	movies.EXPECT().FindByFilter(ctx, models.MovieFilter{UserId: userId, TmdbIds: []uint64{603}}).Return([]models.Movie{{TmdbId: 603, State: models.StateTypeWant}}, nil)
	movies.EXPECT().UpdateByTmdbId(ctx, &models.Movie{TmdbId: 603, UserId: userId, State: models.StateTypeWatched}).Return(&models.Movie{}, nil)
	webhooks.EXPECT().Create(ctx, gomock.Any()).Return(assert.AnError)

	err := service.Handle(ctx, link, jellyfinEvent(jellyfin.ItemTypeMovie, map[string]string{"tmdb": "603"}))

	require.ErrorIs(t, err, errors.ErrFailedToProcessWebhook)
}
