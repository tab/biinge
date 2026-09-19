package services

import (
	"cmp"
	"context"
	"fmt"

	"github.com/google/uuid"

	"biinge-api/internal/app/errors"
	"biinge-api/internal/app/models"
	"biinge-api/internal/app/serializers"
	"biinge-api/internal/config/cache"
	"biinge-api/internal/config/logger"
	"biinge-api/pkg/igdb"
)

type IgdbProvider interface {
	FetchGameDetails(ctx context.Context, id uint64, userId uuid.UUID) (*serializers.GameDetailsSerializer, error)
	FetchUpNextGames(ctx context.Context, userId uuid.UUID) ([]serializers.UpNextGameSerializer, error)
	SearchGames(ctx context.Context, query string, page uint64, userId uuid.UUID) (*serializers.PaginationResponse[serializers.SearchGameSerializer], error)
	FetchTrendingGames(ctx context.Context, userId uuid.UUID) (*serializers.PaginationResponse[serializers.SearchGameSerializer], error)
}

// igdbReleasedStatus is the status TransformGameDetails reports for a game that is out
const igdbReleasedStatus = "Released"

type igdbProvider struct {
	client igdb.Client
	games  Games
	cache  cache.Cache
	log    *logger.Logger
}

func NewIgdbProvider(client igdb.Client, games Games, store cache.Cache, log *logger.Logger) IgdbProvider {
	return &igdbProvider{
		client: client,
		games:  games,
		cache:  store,
		log:    log.WithComponent("IgdbProvider"),
	}
}

func (p *igdbProvider) FetchGameDetails(ctx context.Context, id uint64, userId uuid.UUID) (*serializers.GameDetailsSerializer, error) {
	p.log.Debug().Uint64("Id", id).Msg("Fetching game details")

	response, err := cache.Fetch(ctx, p.cache, p.log, fmt.Sprintf("igdb:v1:game:%d", id), cache.DetailsTTL, func() (*igdb.GameDetails, error) {
		return p.client.FetchGameDetails(ctx, id)
	})
	if err != nil {
		p.log.Error().Err(err).Uint64("Id", id).Msg("Failed to fetch game details")
		return p.fallbackGameDetails(ctx, id, userId)
	}

	details := igdb.TransformGameDetails(response)

	recommendationIds := make([]uint64, 0, len(details.Recommendations))
	for _, item := range details.Recommendations {
		recommendationIds = append(recommendationIds, item.Id)
	}

	recommendedGames, err := p.games.FindGamesByIgdbIds(ctx, recommendationIds, userId)
	if err != nil {
		p.log.Error().Err(err).Msg("Failed to fetch recommendation states")
		return nil, errors.ErrFailedToFetchResults
	}

	recommendationStates := make(map[uint64]models.StateType, len(recommendedGames))
	for _, recommended := range recommendedGames {
		recommendationStates[recommended.IgdbId] = recommended.State
	}

	recommendations := make([]serializers.RecommendationSerializer, 0, len(details.Recommendations))

	for _, item := range details.Recommendations {
		state := models.StateTypeNone
		if gameState, exists := recommendationStates[item.Id]; exists {
			state = gameState
		}

		recommendations = append(recommendations, serializers.RecommendationSerializer{
			Id:         item.Id,
			Title:      item.Title,
			PosterPath: item.PosterPath,
			State:      state,
		})
	}

	game, err := p.games.FindByIgdbId(ctx, id, userId)
	if err != nil {
		if errors.Is(err, errors.ErrGameNotFound) {
			p.log.Debug().Uint64("Id", id).Msg("Game not found in database")

			return &serializers.GameDetailsSerializer{
				Id:               id,
				Pinned:           false,
				State:            models.StateTypeNone,
				Title:            details.Title,
				PosterPath:       details.PosterPath,
				Overview:         details.Overview,
				Status:           details.Status,
				ReleaseDate:      details.ReleaseDate,
				Runtime:          details.Runtime,
				RuntimeCompleted: details.RuntimeCompleted,
				Rating:           details.Rating,
				Genres:           details.Genres,
				Platforms:        details.Platforms,
				Recommendations:  recommendations,
			}, nil
		}

		p.log.Error().Err(err).Uint64("Id", id).Msg("Failed to fetch game state")

		return nil, errors.ErrFailedToFetchGame
	}

	// Read-repair: refresh a stale add-time cover/title from IGDB, leaving state and pinned untouched.
	// IGDB drops replaced images after 30 days, so a stored image_id can go dead on its own
	if details.PosterPath != "" && details.PosterPath != game.PosterPath {
		runtime := cmp.Or(details.Runtime, game.Runtime)
		title := cmp.Or(details.Title, game.Title)

		if _, updateErr := p.games.Update(ctx, &models.Game{
			ID:         game.ID,
			Title:      title,
			PosterPath: details.PosterPath,
			Runtime:    runtime,
		}); updateErr != nil {
			p.log.Warn().Err(updateErr).Uint64("Id", id).Msg("Failed to refresh stored game cover")
		}
	}

	return &serializers.GameDetailsSerializer{
		Id:               id,
		Pinned:           game.Pinned,
		State:            game.State,
		Title:            details.Title,
		PosterPath:       details.PosterPath,
		Overview:         details.Overview,
		Status:           details.Status,
		ReleaseDate:      details.ReleaseDate,
		Runtime:          details.Runtime,
		RuntimeCompleted: details.RuntimeCompleted,
		Rating:           details.Rating,
		Genres:           details.Genres,
		Platforms:        details.Platforms,
		Recommendations:  recommendations,
	}, nil
}

// fallbackGameDetails serves stored library data when IGDB is unavailable, else a fetch error
func (p *igdbProvider) fallbackGameDetails(ctx context.Context, id uint64, userId uuid.UUID) (*serializers.GameDetailsSerializer, error) {
	game, err := p.games.FindByIgdbId(ctx, id, userId)
	if err != nil {
		return nil, igdb.ErrFailedToFetchGameDetails
	}

	p.log.Warn().Uint64("Id", id).Msg("Serving stored game details while IGDB is unavailable")

	return &serializers.GameDetailsSerializer{
		Id:              id,
		Pinned:          game.Pinned,
		State:           game.State,
		Title:           game.Title,
		PosterPath:      game.PosterPath,
		Runtime:         game.Runtime,
		Genres:          make([]string, 0),
		Platforms:       make([]string, 0),
		Recommendations: make([]serializers.RecommendationSerializer, 0),
	}, nil
}

// FetchUpNextGames returns the released games among the user's pinned want list, preserving library order
func (p *igdbProvider) FetchUpNextGames(ctx context.Context, userId uuid.UUID) ([]serializers.UpNextGameSerializer, error) {
	want, _, err := p.games.List(ctx, userId, models.StateTypeWant, &Pagination{Page: DefaultPage, PerPage: MaxPerPage})
	if err != nil {
		return nil, err
	}

	pinned := make([]models.Game, 0, len(want))
	for _, game := range want {
		if game.Pinned {
			pinned = append(pinned, game)
		}
	}

	entries := boundedMap(pinned, upNextConcurrency, func(game models.Game) *serializers.UpNextGameSerializer {
		return p.releasedGame(ctx, game)
	})

	games := make([]serializers.UpNextGameSerializer, 0, len(pinned))

	for _, entry := range entries {
		if entry != nil {
			games = append(games, *entry)
		}
	}

	return games, nil
}

// releasedGame resolves a want-list game when it is out, skipping on any IGDB failure
func (p *igdbProvider) releasedGame(ctx context.Context, game models.Game) *serializers.UpNextGameSerializer {
	response, err := cache.Fetch(ctx, p.cache, p.log, fmt.Sprintf("igdb:v1:game:%d", game.IgdbId), cache.DetailsTTL, func() (*igdb.GameDetails, error) {
		return p.client.FetchGameDetails(ctx, game.IgdbId)
	})
	if err != nil {
		p.log.Warn().Err(err).Uint64("GameId", game.IgdbId).Msg("Skipping game in up-next; IGDB details unavailable")
		return nil
	}

	details := igdb.TransformGameDetails(response)

	// IGDB leaves the status empty on a game that released normally, so the transformer resolves it
	// against the release date: "Released" already means dated and out. Early Access and Delisted
	// carry a status of their own and stay out of the queue
	if details.Status != igdbReleasedStatus {
		return nil
	}

	entry := serializers.UpNextGameSerializer{
		Id:          game.IgdbId,
		Title:       details.Title,
		PosterPath:  details.PosterPath,
		Overview:    details.Overview,
		Runtime:     details.Runtime,
		Rating:      details.Rating,
		ReleaseDate: details.ReleaseDate,
	}

	return &entry
}

func (p *igdbProvider) SearchGames(ctx context.Context, query string, page uint64, userId uuid.UUID) (*serializers.PaginationResponse[serializers.SearchGameSerializer], error) {
	offset := (page - 1) * DefaultPerPage

	response, err := cache.Fetch(ctx, p.cache, p.log, fmt.Sprintf("igdb:v1:search:games:%d:%s", page, query), cache.SearchTTL, func() (*igdb.GameListResult, error) {
		return p.client.SearchGames(ctx, query, DefaultPerPage, offset)
	})
	if err != nil {
		p.log.Error().Err(err).Str("query", query).Msg("Failed to search games")
		return nil, errors.ErrFailedToFetchResults
	}

	return p.buildGameList(ctx, response, page, userId)
}

func (p *igdbProvider) FetchTrendingGames(ctx context.Context, userId uuid.UUID) (*serializers.PaginationResponse[serializers.SearchGameSerializer], error) {
	response, err := cache.Fetch(ctx, p.cache, p.log, "igdb:v1:trending:games", cache.TrendingTTL, func() (*igdb.GameListResult, error) {
		return p.client.FetchTrendingGames(ctx, DefaultPerPage)
	})
	if err != nil {
		p.log.Error().Err(err).Msg("Failed to fetch trending games")
		return nil, errors.ErrFailedToFetchResults
	}

	return p.buildGameList(ctx, response, DefaultPage, userId)
}

// buildGameList merges the user's tracking state into a page of IGDB results
func (p *igdbProvider) buildGameList(ctx context.Context, response *igdb.GameListResult, page uint64, userId uuid.UUID) (*serializers.PaginationResponse[serializers.SearchGameSerializer], error) {
	items := igdb.TransformGameList(response)

	ids := make([]uint64, 0, len(items))
	for _, item := range items {
		ids = append(ids, item.Id)
	}

	gamesList, err := p.games.FindGamesByIgdbIds(ctx, ids, userId)
	if err != nil {
		p.log.Error().Err(err).Msg("Failed to fetch game states")
		return nil, errors.ErrFailedToFetchResults
	}

	stateMap := make(map[uint64]models.StateType)
	for _, game := range gamesList {
		stateMap[game.IgdbId] = game.State
	}

	data := make([]serializers.SearchGameSerializer, 0, len(items))

	for _, item := range items {
		state := models.StateTypeNone
		if value, ok := stateMap[item.Id]; ok {
			state = value
		}

		data = append(data, serializers.SearchGameSerializer{
			Id:          item.Id,
			Title:       item.Title,
			PosterPath:  item.PosterPath,
			ReleaseDate: item.ReleaseDate,
			Rating:      item.Rating,
			State:       state,
		})
	}

	// IGDB reports no result count for a search, so total covers this page only
	return &serializers.PaginationResponse[serializers.SearchGameSerializer]{
		Data: data,
		Meta: serializers.PaginationMeta{
			Page:  page,
			Per:   uint64(len(data)),
			Total: uint64(len(data)),
		},
	}, nil
}
