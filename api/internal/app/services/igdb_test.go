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
	"biinge-api/internal/config/cache"
	"biinge-api/pkg/igdb"
)

// ps5Release is 2023-03-01, the release date the fixtures below expect back
const ps5Release int64 = 1677628800

func sampleGameDetails() *igdb.GameDetails {
	return &igdb.GameDetails{
		Game: igdb.Game{
			Id:               1942,
			Name:             "The Witcher 3",
			Summary:          "A monster hunter searches for his adopted daughter.",
			Cover:            igdb.Cover{ImageId: "co1wyy"},
			GameStatus:       igdb.GameStatus{Status: "Released"},
			TotalRating:      94.6,
			TotalRatingCount: 3200,
			Genres:           []igdb.Genre{{Name: "RPG"}},
			Platforms:        []igdb.Platform{{Name: "PlayStation 5"}},
			ReleaseDates:     []igdb.ReleaseDate{{Date: ps5Release, Platform: igdb.PlatformPlayStation5}},
			SimilarGames: []igdb.SimilarGame{
				{
					Id: 26192, Name: "The Last of Us Part II", Cover: igdb.Cover{ImageId: "co2"},
					TotalRatingCount: 1755, Platforms: []uint64{igdb.PlatformPlayStation4},
				},
				{
					Id: 19561, Name: "Days Gone", Cover: igdb.Cover{ImageId: "co3"},
					TotalRatingCount: 613, Platforms: []uint64{igdb.PlatformPlayStation4},
				},
			},
		},
		TimeToBeat: igdb.TimeToBeat{Normally: 180000, Completely: 381600, Count: 1200},
	}
}

// unreleasedGameDetails carries no IGDB status and a release far ahead, the shape the transformer reads as Upcoming
func unreleasedGameDetails() *igdb.GameDetails {
	details := sampleGameDetails()
	details.Game.Id = 7777
	details.Game.Name = "Half-Life 3"
	details.Game.GameStatus = igdb.GameStatus{}
	details.Game.ReleaseDates = []igdb.ReleaseDate{
		{Date: time.Now().AddDate(2, 0, 0).Unix(), Platform: igdb.PlatformPlayStation5},
	}

	return details
}

func newIgdbProvider(t *testing.T, ctrl *gomock.Controller) (IgdbProvider, *igdb.MockClient, *MockGames) {
	t.Helper()

	client := igdb.NewMockClient(ctrl)
	gamesSvc := NewMockGames(ctrl)

	return NewIgdbProvider(client, gamesSvc, cache.NewNoopCache(), newTestLogger()), client, gamesSvc
}

func Test_IgdbProvider_FetchGameDetails(t *testing.T) {
	ctx := context.Background()
	userId := uuid.New()

	t.Run("Untracked game carries no state", func(t *testing.T) {
		ctrl := gomock.NewController(t)
		defer ctrl.Finish()

		provider, client, gamesSvc := newIgdbProvider(t, ctrl)

		client.EXPECT().FetchGameDetails(ctx, uint64(1942)).Return(sampleGameDetails(), nil)
		gamesSvc.EXPECT().FindGamesByIgdbIds(ctx, []uint64{26192, 19561}, userId).Return(nil, nil)
		gamesSvc.EXPECT().FindByIgdbId(ctx, uint64(1942), userId).Return(nil, errors.ErrGameNotFound)

		result, err := provider.FetchGameDetails(ctx, 1942, userId)
		require.NoError(t, err)

		assert.Equal(t, uint64(1942), result.Id)
		assert.Equal(t, "The Witcher 3", result.Title)
		assert.Equal(t, "co1wyy", result.PosterPath)
		assert.Equal(t, "Released", result.Status)
		assert.Equal(t, "2023-03-01", result.ReleaseDate)
		assert.InDelta(t, 9.46, result.Rating, 0.001)
		assert.Equal(t, uint64(3000), result.Runtime)
		assert.Equal(t, uint64(6360), result.RuntimeCompleted)
		assert.Equal(t, models.StateTypeNone, result.State)
		assert.False(t, result.Pinned)
	})

	t.Run("Tracked game carries its stored state", func(t *testing.T) {
		ctrl := gomock.NewController(t)
		defer ctrl.Finish()

		provider, client, gamesSvc := newIgdbProvider(t, ctrl)

		client.EXPECT().FetchGameDetails(ctx, uint64(1942)).Return(sampleGameDetails(), nil)
		gamesSvc.EXPECT().FindGamesByIgdbIds(ctx, []uint64{26192, 19561}, userId).Return(nil, nil)
		gamesSvc.EXPECT().FindByIgdbId(ctx, uint64(1942), userId).Return(&models.Game{
			ID:         uuid.New(),
			IgdbId:     1942,
			Title:      "The Witcher 3",
			PosterPath: "co1wyy",
			State:      models.StateTypePlayed,
			Pinned:     true,
		}, nil)

		result, err := provider.FetchGameDetails(ctx, 1942, userId)
		require.NoError(t, err)

		assert.Equal(t, models.StateTypePlayed, result.State)
		assert.True(t, result.Pinned)
	})

	t.Run("Read-repairs a stale stored cover", func(t *testing.T) {
		ctrl := gomock.NewController(t)
		defer ctrl.Finish()

		provider, client, gamesSvc := newIgdbProvider(t, ctrl)
		stored := uuid.New()

		client.EXPECT().FetchGameDetails(ctx, uint64(1942)).Return(sampleGameDetails(), nil)
		gamesSvc.EXPECT().FindGamesByIgdbIds(ctx, []uint64{26192, 19561}, userId).Return(nil, nil)
		gamesSvc.EXPECT().FindByIgdbId(ctx, uint64(1942), userId).Return(&models.Game{
			ID:         stored,
			IgdbId:     1942,
			Title:      "The Witcher 3",
			PosterPath: "co-expired",
			Runtime:    3000,
			State:      models.StateTypeWant,
		}, nil)

		gamesSvc.EXPECT().Update(ctx, &models.Game{
			ID:         stored,
			Title:      "The Witcher 3",
			PosterPath: "co1wyy",
			Runtime:    3000,
		}).Return(&models.Game{ID: stored}, nil)

		result, err := provider.FetchGameDetails(ctx, 1942, userId)
		require.NoError(t, err)

		assert.Equal(t, "co1wyy", result.PosterPath)
		// the repair must not disturb what the user set
		assert.Equal(t, models.StateTypeWant, result.State)
	})

	t.Run("Matching cover skips the repair write", func(t *testing.T) {
		ctrl := gomock.NewController(t)
		defer ctrl.Finish()

		provider, client, gamesSvc := newIgdbProvider(t, ctrl)

		client.EXPECT().FetchGameDetails(ctx, uint64(1942)).Return(sampleGameDetails(), nil)
		gamesSvc.EXPECT().FindGamesByIgdbIds(ctx, []uint64{26192, 19561}, userId).Return(nil, nil)
		gamesSvc.EXPECT().FindByIgdbId(ctx, uint64(1942), userId).Return(&models.Game{
			IgdbId:     1942,
			PosterPath: "co1wyy",
			State:      models.StateTypeWant,
		}, nil)

		_, err := provider.FetchGameDetails(ctx, 1942, userId)
		require.NoError(t, err)
	})

	t.Run("Recommendations carry their own tracking state", func(t *testing.T) {
		ctrl := gomock.NewController(t)
		defer ctrl.Finish()

		provider, client, gamesSvc := newIgdbProvider(t, ctrl)

		client.EXPECT().FetchGameDetails(ctx, uint64(1942)).Return(sampleGameDetails(), nil)
		gamesSvc.EXPECT().FindGamesByIgdbIds(ctx, []uint64{26192, 19561}, userId).Return([]models.Game{
			{IgdbId: 26192, State: models.StateTypePlaying},
		}, nil)
		gamesSvc.EXPECT().FindByIgdbId(ctx, uint64(1942), userId).Return(nil, errors.ErrGameNotFound)

		result, err := provider.FetchGameDetails(ctx, 1942, userId)
		require.NoError(t, err)

		require.Len(t, result.Recommendations, 2)
		assert.Equal(t, "The Last of Us Part II", result.Recommendations[0].Title)
		assert.Equal(t, "co2", result.Recommendations[0].PosterPath)
		assert.Equal(t, models.StateTypePlaying, result.Recommendations[0].State)
		assert.Equal(t, models.StateTypeNone, result.Recommendations[1].State)
	})

	t.Run("Recommendation state lookup failure", func(t *testing.T) {
		ctrl := gomock.NewController(t)
		defer ctrl.Finish()

		provider, client, gamesSvc := newIgdbProvider(t, ctrl)

		client.EXPECT().FetchGameDetails(ctx, uint64(1942)).Return(sampleGameDetails(), nil)
		gamesSvc.EXPECT().FindGamesByIgdbIds(ctx, []uint64{26192, 19561}, userId).Return(nil, errors.ErrFailedToFetchResults)

		result, err := provider.FetchGameDetails(ctx, 1942, userId)
		require.ErrorIs(t, err, errors.ErrFailedToFetchResults)
		assert.Nil(t, result)
	})

	t.Run("Falls back to stored data when IGDB is unavailable", func(t *testing.T) {
		ctrl := gomock.NewController(t)
		defer ctrl.Finish()

		provider, client, gamesSvc := newIgdbProvider(t, ctrl)

		client.EXPECT().FetchGameDetails(ctx, uint64(1942)).Return(nil, igdb.ErrUnexpectedResponse)
		gamesSvc.EXPECT().FindByIgdbId(ctx, uint64(1942), userId).Return(&models.Game{
			IgdbId:     1942,
			Title:      "The Witcher 3",
			PosterPath: "co-stored",
			Runtime:    3000,
			State:      models.StateTypePlayed,
			Pinned:     true,
		}, nil)

		result, err := provider.FetchGameDetails(ctx, 1942, userId)
		require.NoError(t, err)

		assert.Equal(t, "co-stored", result.PosterPath)
		assert.Equal(t, uint64(3000), result.Runtime)
		assert.Equal(t, models.StateTypePlayed, result.State)
		assert.Empty(t, result.Genres)
		assert.Empty(t, result.Platforms)
	})

	t.Run("Unavailable IGDB and an untracked game is an error", func(t *testing.T) {
		ctrl := gomock.NewController(t)
		defer ctrl.Finish()

		provider, client, gamesSvc := newIgdbProvider(t, ctrl)

		client.EXPECT().FetchGameDetails(ctx, uint64(1942)).Return(nil, igdb.ErrUnexpectedResponse)
		gamesSvc.EXPECT().FindByIgdbId(ctx, uint64(1942), userId).Return(nil, errors.ErrGameNotFound)

		result, err := provider.FetchGameDetails(ctx, 1942, userId)
		require.ErrorIs(t, err, igdb.ErrFailedToFetchGameDetails)
		assert.Nil(t, result)
	})
}

func Test_IgdbProvider_FetchUpNextGames(t *testing.T) {
	ctx := context.Background()
	userId := uuid.New()

	t.Run("Keeps only the pinned want games that are out", func(t *testing.T) {
		ctrl := gomock.NewController(t)
		defer ctrl.Finish()

		provider, client, gamesSvc := newIgdbProvider(t, ctrl)

		gamesSvc.EXPECT().List(gomock.Any(), userId, models.StateTypeWant, gomock.Any()).Return([]models.Game{
			{IgdbId: 1942, Pinned: true},
			{IgdbId: 7777, Pinned: true},
			{IgdbId: 3333, Pinned: false},
		}, uint64(3), nil)

		client.EXPECT().FetchGameDetails(gomock.Any(), uint64(1942)).Return(sampleGameDetails(), nil)
		client.EXPECT().FetchGameDetails(gomock.Any(), uint64(7777)).Return(unreleasedGameDetails(), nil)

		result, err := provider.FetchUpNextGames(ctx, userId)
		require.NoError(t, err)
		require.Len(t, result, 1)

		assert.Equal(t, uint64(1942), result[0].Id)
		assert.Equal(t, "The Witcher 3", result[0].Title)
		assert.Equal(t, "co1wyy", result[0].PosterPath)
		assert.Equal(t, "2023-03-01", result[0].ReleaseDate)
		assert.Equal(t, uint64(3000), result[0].Runtime)
		assert.InDelta(t, 9.46, result[0].Rating, 0.001)
	})

	t.Run("Skips a game IGDB cannot resolve", func(t *testing.T) {
		ctrl := gomock.NewController(t)
		defer ctrl.Finish()

		provider, client, gamesSvc := newIgdbProvider(t, ctrl)

		gamesSvc.EXPECT().List(gomock.Any(), userId, models.StateTypeWant, gomock.Any()).Return([]models.Game{
			{IgdbId: 1942, Pinned: true},
		}, uint64(1), nil)

		client.EXPECT().FetchGameDetails(gomock.Any(), uint64(1942)).Return(nil, igdb.ErrUnexpectedResponse)

		result, err := provider.FetchUpNextGames(ctx, userId)
		require.NoError(t, err)
		assert.Empty(t, result)
	})

	t.Run("An empty queue serializes as a list, not null", func(t *testing.T) {
		ctrl := gomock.NewController(t)
		defer ctrl.Finish()

		provider, _, gamesSvc := newIgdbProvider(t, ctrl)

		gamesSvc.EXPECT().List(gomock.Any(), userId, models.StateTypeWant, gomock.Any()).Return(nil, uint64(0), nil)

		result, err := provider.FetchUpNextGames(ctx, userId)
		require.NoError(t, err)
		assert.NotNil(t, result)
		assert.Empty(t, result)
	})

	t.Run("Propagates a library failure", func(t *testing.T) {
		ctrl := gomock.NewController(t)
		defer ctrl.Finish()

		provider, _, gamesSvc := newIgdbProvider(t, ctrl)

		gamesSvc.EXPECT().List(gomock.Any(), userId, models.StateTypeWant, gomock.Any()).
			Return(nil, uint64(0), errors.ErrFailedToFetchResults)

		result, err := provider.FetchUpNextGames(ctx, userId)
		require.ErrorIs(t, err, errors.ErrFailedToFetchResults)
		assert.Nil(t, result)
	})
}

func Test_IgdbProvider_SearchGames(t *testing.T) {
	ctx := context.Background()
	userId := uuid.New()

	t.Run("Merges tracking state into the results", func(t *testing.T) {
		ctrl := gomock.NewController(t)
		defer ctrl.Finish()

		provider, client, gamesSvc := newIgdbProvider(t, ctrl)

		client.EXPECT().SearchGames(ctx, "witcher", DefaultPerPage, uint64(0)).Return(&igdb.GameListResult{Results: []igdb.Game{
			{Id: 1942, Name: "The Witcher 3", Cover: igdb.Cover{ImageId: "co1wyy"}},
			{Id: 2000, Name: "The Witcher 2", Cover: igdb.Cover{ImageId: "co2"}},
		}}, nil)

		gamesSvc.EXPECT().FindGamesByIgdbIds(ctx, []uint64{1942, 2000}, userId).Return([]models.Game{
			{IgdbId: 1942, State: models.StateTypePlayed},
		}, nil)

		result, err := provider.SearchGames(ctx, "witcher", 1, userId)
		require.NoError(t, err)

		require.Len(t, result.Data, 2)
		assert.Equal(t, models.StateTypePlayed, result.Data[0].State)
		assert.Equal(t, models.StateTypeNone, result.Data[1].State)
		assert.Equal(t, uint64(1), result.Meta.Page)
	})

	t.Run("Page two asks IGDB for the matching offset", func(t *testing.T) {
		ctrl := gomock.NewController(t)
		defer ctrl.Finish()

		provider, client, gamesSvc := newIgdbProvider(t, ctrl)

		client.EXPECT().SearchGames(ctx, "witcher", DefaultPerPage, DefaultPerPage).Return(&igdb.GameListResult{}, nil)
		gamesSvc.EXPECT().FindGamesByIgdbIds(ctx, []uint64{}, userId).Return(nil, nil)

		result, err := provider.SearchGames(ctx, "witcher", 2, userId)
		require.NoError(t, err)

		assert.Empty(t, result.Data)
		assert.Equal(t, uint64(2), result.Meta.Page)
	})

	t.Run("IGDB failure", func(t *testing.T) {
		ctrl := gomock.NewController(t)
		defer ctrl.Finish()

		provider, client, _ := newIgdbProvider(t, ctrl)

		client.EXPECT().SearchGames(ctx, "witcher", DefaultPerPage, uint64(0)).Return(nil, igdb.ErrUnexpectedResponse)

		result, err := provider.SearchGames(ctx, "witcher", 1, userId)
		require.ErrorIs(t, err, errors.ErrFailedToFetchResults)
		assert.Nil(t, result)
	})
}

func Test_IgdbProvider_FetchTrendingGames(t *testing.T) {
	ctx := context.Background()
	userId := uuid.New()

	t.Run("Success", func(t *testing.T) {
		ctrl := gomock.NewController(t)
		defer ctrl.Finish()

		provider, client, gamesSvc := newIgdbProvider(t, ctrl)

		client.EXPECT().FetchTrendingGames(ctx, DefaultPerPage).Return(&igdb.GameListResult{Results: []igdb.Game{
			{Id: 1942, Name: "The Witcher 3", Cover: igdb.Cover{ImageId: "co1wyy"}},
		}}, nil)

		gamesSvc.EXPECT().FindGamesByIgdbIds(ctx, []uint64{1942}, userId).Return(nil, nil)

		result, err := provider.FetchTrendingGames(ctx, userId)
		require.NoError(t, err)

		require.Len(t, result.Data, 1)
		assert.Equal(t, "The Witcher 3", result.Data[0].Title)
		assert.Equal(t, models.StateTypeNone, result.Data[0].State)
	})

	t.Run("IGDB failure", func(t *testing.T) {
		ctrl := gomock.NewController(t)
		defer ctrl.Finish()

		provider, client, _ := newIgdbProvider(t, ctrl)

		client.EXPECT().FetchTrendingGames(ctx, DefaultPerPage).Return(nil, igdb.ErrUnexpectedResponse)

		result, err := provider.FetchTrendingGames(ctx, userId)
		require.ErrorIs(t, err, errors.ErrFailedToFetchResults)
		assert.Nil(t, result)
	})
}
