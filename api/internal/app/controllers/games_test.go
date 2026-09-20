package controllers

import (
	"context"
	"encoding/json"
	"io"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	"github.com/go-chi/chi/v5"
	"github.com/google/uuid"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
	"go.uber.org/mock/gomock"

	"biinge-api/internal/app/models"
	"biinge-api/internal/app/serializers"
	"biinge-api/internal/app/services"
	"biinge-api/internal/config/middlewares"
)

// newGamesController wires the controller with fresh mocks for one test
func newGamesController(t *testing.T, ctrl *gomock.Controller) (GamesController, *services.MockGames, *services.MockIgdbProvider) {
	t.Helper()

	games := services.NewMockGames(ctrl)
	provider := services.NewMockIgdbProvider(ctrl)

	return NewGamesController(games, provider), games, provider
}

// authenticated attaches a user to the request the way the authentication middleware does
func authenticated(req *http.Request, id uuid.UUID) *http.Request {
	return req.WithContext(context.WithValue(req.Context(), middlewares.CurrentUser{}, &models.User{ID: id}))
}

func Test_GamesController_HandleList(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	controller, games, _ := newGamesController(t, ctrl)
	userId := uuid.New()

	t.Run("Want list", func(t *testing.T) {
		games.EXPECT().List(gomock.Any(), userId, models.StateTypeWant, gomock.Any()).Return([]models.Game{
			{IgdbId: 1942, Title: "The Witcher 3", PosterPath: "co1wyy", Pinned: true, State: "want"},
		}, uint64(1), nil)

		req := authenticated(httptest.NewRequest(http.MethodGet, "/games", nil), userId)
		w := httptest.NewRecorder()

		r := chi.NewRouter()
		r.Get("/games", controller.HandleList)
		r.ServeHTTP(w, req)

		resp := w.Result()
		defer resp.Body.Close()

		var response serializers.PaginationResponse[serializers.GameSerializer]
		require.NoError(t, json.NewDecoder(resp.Body).Decode(&response))

		assert.Equal(t, http.StatusOK, resp.StatusCode)
		assert.Equal(t, serializers.PaginationResponse[serializers.GameSerializer]{
			Data: []serializers.GameSerializer{{Id: 1942, Title: "The Witcher 3", PosterPath: "co1wyy", Pinned: true, State: "want"}},
			Meta: serializers.PaginationMeta{Page: 1, Per: 24, Total: 1},
		}, response)
	})

	t.Run("Playing list", func(t *testing.T) {
		games.EXPECT().List(gomock.Any(), userId, models.StateTypePlaying, gomock.Any()).Return([]models.Game{}, uint64(0), nil)

		req := authenticated(httptest.NewRequest(http.MethodGet, "/games?type=playing", nil), userId)
		w := httptest.NewRecorder()

		r := chi.NewRouter()
		r.Get("/games", controller.HandleList)
		r.ServeHTTP(w, req)

		resp := w.Result()
		defer resp.Body.Close()

		assert.Equal(t, http.StatusOK, resp.StatusCode)
	})

	t.Run("Played list", func(t *testing.T) {
		games.EXPECT().List(gomock.Any(), userId, models.StateTypePlayed, gomock.Any()).Return([]models.Game{}, uint64(0), nil)

		req := authenticated(httptest.NewRequest(http.MethodGet, "/games?type=played", nil), userId)
		w := httptest.NewRecorder()

		r := chi.NewRouter()
		r.Get("/games", controller.HandleList)
		r.ServeHTTP(w, req)

		resp := w.Result()
		defer resp.Body.Close()

		assert.Equal(t, http.StatusOK, resp.StatusCode)
	})

	t.Run("Unauthorized", func(t *testing.T) {
		req := httptest.NewRequest(http.MethodGet, "/games", nil)
		w := httptest.NewRecorder()

		r := chi.NewRouter()
		r.Get("/games", controller.HandleList)
		r.ServeHTTP(w, req)

		resp := w.Result()
		defer resp.Body.Close()

		assert.Equal(t, http.StatusUnauthorized, resp.StatusCode)
	})

	t.Run("Service error", func(t *testing.T) {
		games.EXPECT().List(gomock.Any(), userId, models.StateTypeWant, gomock.Any()).Return(nil, uint64(0), assert.AnError)

		req := authenticated(httptest.NewRequest(http.MethodGet, "/games", nil), userId)
		w := httptest.NewRecorder()

		r := chi.NewRouter()
		r.Get("/games", controller.HandleList)
		r.ServeHTTP(w, req)

		resp := w.Result()
		defer resp.Body.Close()

		assert.Equal(t, http.StatusUnprocessableEntity, resp.StatusCode)
	})
}

func Test_GamesController_HandleDetails(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	controller, _, provider := newGamesController(t, ctrl)
	userId := uuid.New()

	serve := func(target string, withUser bool) *http.Response {
		req := httptest.NewRequest(http.MethodGet, target, nil)
		if withUser {
			req = authenticated(req, userId)
		}

		w := httptest.NewRecorder()

		r := chi.NewRouter()
		r.Get("/games/{id}", controller.HandleDetails)
		r.ServeHTTP(w, req)

		return w.Result()
	}

	t.Run("Success", func(t *testing.T) {
		provider.EXPECT().FetchGameDetails(gomock.Any(), uint64(1942), userId).Return(&serializers.GameDetailsSerializer{
			Id:               1942,
			Title:            "The Witcher 3",
			PosterPath:       "co1wyy",
			Runtime:          3000,
			RuntimeCompleted: 6360,
			State:            models.StateTypeWant,
			Genres:           []string{"RPG"},
			Platforms:        []string{"PlayStation 5"},
		}, nil)

		resp := serve("/games/1942", true)
		defer resp.Body.Close()

		var response serializers.GameDetailsSerializer
		require.NoError(t, json.NewDecoder(resp.Body).Decode(&response))

		assert.Equal(t, http.StatusOK, resp.StatusCode)
		assert.Equal(t, uint64(1942), response.Id)
		assert.Equal(t, uint64(3000), response.Runtime)
		assert.Equal(t, uint64(6360), response.RuntimeCompleted)
	})

	t.Run("Non-numeric id", func(t *testing.T) {
		resp := serve("/games/witcher", true)
		defer resp.Body.Close()

		var response serializers.ErrorSerializer
		require.NoError(t, json.NewDecoder(resp.Body).Decode(&response))

		assert.Equal(t, http.StatusBadRequest, resp.StatusCode)
		assert.Equal(t, "invalid igdb id", response.Error)
	})

	t.Run("Unauthorized", func(t *testing.T) {
		resp := serve("/games/1942", false)
		defer resp.Body.Close()

		assert.Equal(t, http.StatusUnauthorized, resp.StatusCode)
	})

	t.Run("Provider error", func(t *testing.T) {
		provider.EXPECT().FetchGameDetails(gomock.Any(), uint64(1942), userId).Return(nil, assert.AnError)

		resp := serve("/games/1942", true)
		defer resp.Body.Close()

		assert.Equal(t, http.StatusUnprocessableEntity, resp.StatusCode)
	})
}

func Test_GamesController_HandleCreate(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	controller, games, _ := newGamesController(t, ctrl)
	userId := uuid.New()

	serve := func(body string, withUser bool) *http.Response {
		req := httptest.NewRequest(http.MethodPost, "/games", strings.NewReader(body))
		if withUser {
			req = authenticated(req, userId)
		}

		w := httptest.NewRecorder()

		r := chi.NewRouter()
		r.Post("/games", controller.HandleCreate)
		r.ServeHTTP(w, req)

		return w.Result()
	}

	t.Run("Success", func(t *testing.T) {
		games.EXPECT().Create(gomock.Any(), &models.Game{
			UserId:     userId,
			IgdbId:     1942,
			Title:      "The Witcher 3",
			PosterPath: "co1wyy",
			Runtime:    3000,
			State:      models.StateTypeWant,
		}).Return(&models.Game{IgdbId: 1942, State: models.StateTypeWant}, nil)

		resp := serve(`{"id":1942,"title":"The Witcher 3","posterPath":"co1wyy","runtime":3000,"state":"want"}`, true)
		defer resp.Body.Close()

		body, err := io.ReadAll(resp.Body)
		require.NoError(t, err)

		var response serializers.GameDetailsSerializer
		require.NoError(t, json.Unmarshal(body, &response))

		assert.Equal(t, http.StatusOK, resp.StatusCode)
		assert.Equal(t, uint64(1942), response.Id)
		assert.Equal(t, models.StateTypeWant, response.State)
		// the spec marks these required, and a nil slice would encode as null, which the client can't decode
		assert.Contains(t, string(body), `"genres":[]`)
		assert.Contains(t, string(body), `"platforms":[]`)
		assert.Contains(t, string(body), `"recommendations":[]`)
	})

	t.Run("Invalid state", func(t *testing.T) {
		resp := serve(`{"id":1942,"title":"The Witcher 3","state":"watched"}`, true)
		defer resp.Body.Close()

		var response serializers.ErrorSerializer
		require.NoError(t, json.NewDecoder(resp.Body).Decode(&response))

		assert.Equal(t, http.StatusBadRequest, resp.StatusCode)
		assert.Equal(t, "invalid state", response.Error)
	})

	t.Run("Unauthorized", func(t *testing.T) {
		resp := serve(`{"id":1942,"title":"The Witcher 3","state":"want"}`, false)
		defer resp.Body.Close()

		assert.Equal(t, http.StatusUnauthorized, resp.StatusCode)
	})

	t.Run("Service error", func(t *testing.T) {
		games.EXPECT().Create(gomock.Any(), gomock.Any()).Return(nil, assert.AnError)

		resp := serve(`{"id":1942,"title":"The Witcher 3","state":"want"}`, true)
		defer resp.Body.Close()

		assert.Equal(t, http.StatusUnprocessableEntity, resp.StatusCode)
	})
}

func Test_GamesController_HandleUpdate(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	controller, games, _ := newGamesController(t, ctrl)
	userId := uuid.New()

	serve := func(target, body string) *http.Response {
		req := authenticated(httptest.NewRequest(http.MethodPatch, target, strings.NewReader(body)), userId)
		w := httptest.NewRecorder()

		r := chi.NewRouter()
		r.Patch("/games/{id}", controller.HandleUpdate)
		r.ServeHTTP(w, req)

		return w.Result()
	}

	t.Run("Moves the game to played", func(t *testing.T) {
		games.EXPECT().UpdateByIgdbId(gomock.Any(), &models.Game{
			IgdbId: 1942,
			UserId: userId,
			State:  models.StateTypePlayed,
			Pinned: true,
		}).Return(&models.Game{IgdbId: 1942, State: models.StateTypePlayed, Pinned: true}, nil)

		resp := serve("/games/1942", `{"state":"played","pinned":true}`)
		defer resp.Body.Close()

		body, err := io.ReadAll(resp.Body)
		require.NoError(t, err)

		var response serializers.GameDetailsSerializer
		require.NoError(t, json.Unmarshal(body, &response))

		assert.Equal(t, http.StatusOK, resp.StatusCode)
		assert.Equal(t, models.StateTypePlayed, response.State)
		assert.True(t, response.Pinned)
		// the spec marks these required, and a nil slice would encode as null, which the client can't decode
		assert.Contains(t, string(body), `"genres":[]`)
		assert.Contains(t, string(body), `"platforms":[]`)
		assert.Contains(t, string(body), `"recommendations":[]`)
	})

	t.Run("Non-numeric id", func(t *testing.T) {
		resp := serve("/games/witcher", `{"state":"played"}`)
		defer resp.Body.Close()

		assert.Equal(t, http.StatusBadRequest, resp.StatusCode)
	})

	t.Run("Empty state", func(t *testing.T) {
		resp := serve("/games/1942", `{}`)
		defer resp.Body.Close()

		var response serializers.ErrorSerializer
		require.NoError(t, json.NewDecoder(resp.Body).Decode(&response))

		assert.Equal(t, http.StatusBadRequest, resp.StatusCode)
		assert.Equal(t, "empty state", response.Error)
	})
}

func Test_GamesController_HandleDelete(t *testing.T) {
	ctrl := gomock.NewController(t)
	defer ctrl.Finish()

	controller, games, _ := newGamesController(t, ctrl)
	userId := uuid.New()

	serve := func(target string, withUser bool) *http.Response {
		req := httptest.NewRequest(http.MethodDelete, target, nil)
		if withUser {
			req = authenticated(req, userId)
		}

		w := httptest.NewRecorder()

		r := chi.NewRouter()
		r.Delete("/games/{id}", controller.HandleDelete)
		r.ServeHTTP(w, req)

		return w.Result()
	}

	t.Run("Success", func(t *testing.T) {
		games.EXPECT().DeleteByIgdbId(gomock.Any(), uint64(1942), userId).Return(nil)

		resp := serve("/games/1942", true)
		defer resp.Body.Close()

		assert.Equal(t, http.StatusNoContent, resp.StatusCode)
	})

	t.Run("Unauthorized", func(t *testing.T) {
		resp := serve("/games/1942", false)
		defer resp.Body.Close()

		assert.Equal(t, http.StatusUnauthorized, resp.StatusCode)
	})

	t.Run("Service error", func(t *testing.T) {
		games.EXPECT().DeleteByIgdbId(gomock.Any(), uint64(1942), userId).Return(assert.AnError)

		resp := serve("/games/1942", true)
		defer resp.Body.Close()

		assert.Equal(t, http.StatusUnprocessableEntity, resp.StatusCode)
	})
}
