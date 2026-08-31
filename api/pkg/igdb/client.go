package igdb

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"sort"
	"strconv"
	"strings"
	"sync"
	"time"

	"github.com/go-resty/resty/v2"

	"biinge-api/internal/config"
	"biinge-api/internal/config/logger"
)

const (
	DefaultTimeout = 10 * time.Second

	MaxIdleConnections        = 100
	MaxIdleConnectionsPerHost = 100
	IdleConnTimeout           = 90 * time.Second
	TLSHandshakeTimeout       = 10 * time.Second
)

// PlayStation platform ids, both verified against `POST /v4/platforms`
const (
	PlatformPlayStation5 uint64 = 167
	PlatformPlayStation4 uint64 = 48
)

// The IGDB game_type values that are a game someone owns and plays
const (
	// On PlayStation the remaster or port is often the only version that runs, so restricting
	// this to main games loses Demon's Souls, The Last of Us Remastered and Red Dead Redemption
	// entirely. DLC, expansions and bundles stay out: they are not separately trackable
	gameTypeMain                = 0
	gameTypeStandaloneExpansion = 4
	gameTypeRemake              = 8
	gameTypeRemaster            = 9
	gameTypeExpanded            = 10
	gameTypePort                = 11
)

// playableGameTypes lists those types as an Apicalypse value set
var playableGameTypes = fmt.Sprintf(
	"(%d,%d,%d,%d,%d,%d)",
	gameTypeMain, gameTypeStandaloneExpansion, gameTypeRemake, gameTypeRemaster, gameTypeExpanded, gameTypePort,
)

// popularityTypeVisits ranks games by IGDB.com page visits, the closest thing IGDB has to TMDB's trending
const popularityTypeVisits = 1

// trendingCandidates is how many popularity rows to pull before filtering down to PlayStation titles
const trendingCandidates = 200

// tokenRefreshMargin re-authenticates this far before the Twitch token actually expires
const tokenRefreshMargin = 5 * time.Minute

// detailFields is the full field set for a game detail screen (the similar_games expansion carries
// the fields playstationFilter would test, since Apicalypse can't filter through a nested expansion)
const detailFields = "fields name,summary,first_release_date,total_rating,total_rating_count," +
	"cover.image_id,game_status.status,genres.name,platforms.name,release_dates.date,release_dates.platform," +
	"similar_games.name,similar_games.game_type,similar_games.version_parent," +
	"similar_games.total_rating_count,similar_games.cover.image_id,similar_games.platforms;"

// listFields drops the long-form text a search or trending row never renders
const listFields = "fields name,first_release_date,total_rating,total_rating_count," +
	"cover.image_id,release_dates.date,release_dates.platform;"

// playstationFilter keeps playable games released on a PlayStation we track, dropping editions, DLC
// and cover-less entries (an expression rather than a full clause, since Apicalypse allows only one
// `where` per query)
var playstationFilter = fmt.Sprintf(
	"platforms = (%d,%d) & game_type = %s & version_parent = null & cover != null",
	PlatformPlayStation5, PlatformPlayStation4, playableGameTypes,
)

type Client interface {
	FetchGameDetails(ctx context.Context, id uint64) (*GameDetails, error)
	SearchGames(ctx context.Context, query string, limit, offset uint64) (*GameListResult, error)
	FetchTrendingGames(ctx context.Context, limit uint64) (*GameListResult, error)
}

type client struct {
	cfg       *config.Config
	apiClient *resty.Client
	log       *logger.Logger

	mu          sync.Mutex
	token       string
	tokenExpiry time.Time
}

func NewClient(cfg *config.Config, log *logger.Logger) Client {
	apiClient := resty.New()

	apiClient.
		SetHeader("Accept", "application/json").
		SetHeader("Client-ID", cfg.IGDB.ClientID).
		SetTimeout(DefaultTimeout)

	apiClient.SetTransport(&http.Transport{
		MaxIdleConns:        MaxIdleConnections,
		MaxIdleConnsPerHost: MaxIdleConnectionsPerHost,
		IdleConnTimeout:     IdleConnTimeout,
		TLSHandshakeTimeout: TLSHandshakeTimeout,
	})

	return &client{
		cfg:       cfg,
		apiClient: apiClient,
		log:       log.WithComponent("IgdbClient"),
	}
}

// tokenResponse is Twitch's client-credentials grant payload
type tokenResponse struct {
	AccessToken string `json:"access_token"`
	ExpiresIn   int64  `json:"expires_in"`
	TokenType   string `json:"token_type"`
}

// multiqueryResult is one named sub-query's slice inside a multiquery response
type multiqueryResult struct {
	Name   string          `json:"name"`
	Result json.RawMessage `json:"result"`
}

// accessToken returns a cached Twitch token, exchanging the client credentials when it is missing or near expiry
func (c *client) accessToken(ctx context.Context) (string, error) {
	c.mu.Lock()
	defer c.mu.Unlock()

	if c.token != "" && time.Now().Before(c.tokenExpiry) {
		return c.token, nil
	}

	c.log.Debug().Msg("Exchanging IGDB client credentials for an access token")

	response, err := c.apiClient.R().
		SetContext(ctx).
		SetQueryParam("client_id", c.cfg.IGDB.ClientID).
		SetQueryParam("client_secret", c.cfg.IGDB.ClientSecret).
		SetQueryParam("grant_type", "client_credentials").
		Post(c.cfg.IGDB.TokenURL)
	if err != nil {
		c.log.Error().Err(err).Msg("Failed to reach the IGDB token endpoint")
		return "", ErrFailedToFetchToken
	}

	if response.StatusCode() != http.StatusOK {
		c.log.Error().Int("statusCode", response.StatusCode()).Msg("IGDB token endpoint rejected the client credentials")
		return "", ErrAccessForbidden
	}

	var result tokenResponse
	if err = json.Unmarshal(response.Body(), &result); err != nil {
		c.log.Error().Err(err).Msg("Failed to parse the IGDB token response")
		return "", ErrFailedToFetchToken
	}

	c.token = result.AccessToken
	c.tokenExpiry = time.Now().Add(time.Duration(result.ExpiresIn)*time.Second - tokenRefreshMargin)

	return c.token, nil
}

// invalidateToken drops the cached token so the next request re-authenticates
func (c *client) invalidateToken() {
	c.mu.Lock()
	defer c.mu.Unlock()

	c.token = ""
	c.tokenExpiry = time.Time{}
}

// post sends an Apicalypse body to an IGDB endpoint and returns the raw response body
func (c *client) post(ctx context.Context, endpoint, body string) ([]byte, error) {
	token, err := c.accessToken(ctx)
	if err != nil {
		return nil, err
	}

	url := c.cfg.IGDB.BaseURL + endpoint

	c.log.Debug().Str("endpoint", url).Str("query", body).Msg("Querying the IGDB API")

	response, err := c.apiClient.R().
		SetContext(ctx).
		SetHeader("Authorization", "Bearer "+token).
		SetHeader("Content-Type", "text/plain").
		SetBody(body).
		Post(url)
	if err != nil {
		c.log.Error().Err(err).Str("endpoint", url).Msg("Failed to reach the IGDB API")
		return nil, err
	}

	switch response.StatusCode() {
	case http.StatusOK:
		return response.Body(), nil
	case http.StatusUnauthorized, http.StatusForbidden:
		// the token was revoked or rotated early; drop it so the next call re-authenticates
		c.invalidateToken()
		c.log.Error().Int("statusCode", response.StatusCode()).Str("endpoint", url).Msg("Access forbidden to IGDB API")

		return nil, ErrAccessForbidden
	case http.StatusNotFound:
		c.log.Error().Int("statusCode", response.StatusCode()).Str("endpoint", url).Msg("Resource not found in IGDB API")
		return nil, ErrNotFound
	default:
		c.log.Error().Int("statusCode", response.StatusCode()).Str("endpoint", url).Msg("Unexpected response from IGDB API")
		return nil, ErrUnexpectedResponse
	}
}

func (c *client) FetchGameDetails(ctx context.Context, id uint64) (*GameDetails, error) {
	c.log.Debug().Uint64("Id", id).Msg("Fetching game details")

	// completion times live on their own endpoint, so multiquery keeps the detail screen at one round trip
	body := fmt.Sprintf(
		"query games \"game\" { %s where id = %d; };\n"+
			"query game_time_to_beats \"time\" { fields normally,completely,count; where game_id = %d; };",
		detailFields, id, id,
	)

	payload, err := c.post(ctx, "/multiquery", body)
	if err != nil {
		return nil, err
	}

	var results []multiqueryResult
	if err = json.Unmarshal(payload, &results); err != nil {
		c.log.Error().Err(err).Uint64("Id", id).Msg("Failed to parse game details response")
		return nil, err
	}

	var details GameDetails

	for _, result := range results {
		switch result.Name {
		case "game":
			var games []Game
			if err = json.Unmarshal(result.Result, &games); err != nil {
				c.log.Error().Err(err).Uint64("Id", id).Msg("Failed to parse game payload")
				return nil, err
			}

			if len(games) > 0 {
				details.Game = games[0]
			}
		case "time":
			var times []TimeToBeat
			if err = json.Unmarshal(result.Result, &times); err != nil {
				c.log.Error().Err(err).Uint64("Id", id).Msg("Failed to parse time to beat payload")
				return nil, err
			}

			if len(times) > 0 {
				details.TimeToBeat = times[0]
			}
		}
	}

	// IGDB answers an unknown id with an empty result rather than a 404
	if details.Game.Id == 0 {
		c.log.Debug().Uint64("Id", id).Msg("Game not found in IGDB API")
		return nil, ErrNotFound
	}

	return &details, nil
}

func (c *client) SearchGames(ctx context.Context, query string, limit, offset uint64) (*GameListResult, error) {
	body := fmt.Sprintf(
		"search \"%s\";\n%s\nwhere %s;\nlimit %d;\noffset %d;",
		escapeQuery(query), listFields, playstationFilter, limit, offset,
	)

	games, err := c.fetchGames(ctx, body)
	if err != nil {
		c.log.Error().Err(err).Str("query", query).Msg("Failed to search games")
		return nil, err
	}

	return &GameListResult{Results: games}, nil
}

func (c *client) FetchTrendingGames(ctx context.Context, limit uint64) (*GameListResult, error) {
	body := fmt.Sprintf(
		"fields game_id,value;\nwhere popularity_type = %d;\nsort value desc;\nlimit %d;",
		popularityTypeVisits, trendingCandidates,
	)

	payload, err := c.post(ctx, "/popularity_primitives", body)
	if err != nil {
		c.log.Error().Err(err).Msg("Failed to fetch game popularity")
		return nil, err
	}

	var primitives []PopularityPrimitive
	if err = json.Unmarshal(payload, &primitives); err != nil {
		c.log.Error().Err(err).Msg("Failed to parse game popularity response")
		return nil, err
	}

	if len(primitives) == 0 {
		return &GameListResult{Results: make([]Game, 0)}, nil
	}

	ids := make([]string, 0, len(primitives))
	rank := make(map[uint64]int, len(primitives))

	for index, primitive := range primitives {
		ids = append(ids, strconv.FormatUint(primitive.GameId, 10))
		rank[primitive.GameId] = index
	}

	// the popularity ranking spans every platform, so most of these ids fall away here
	gamesBody := fmt.Sprintf(
		"%s\nwhere %s & id = (%s);\nlimit %d;",
		listFields, playstationFilter, strings.Join(ids, ","), trendingCandidates,
	)

	games, err := c.fetchGames(ctx, gamesBody)
	if err != nil {
		c.log.Error().Err(err).Msg("Failed to fetch trending games")
		return nil, err
	}

	// IGDB returns an id filter in its own order, so restore the popularity ranking
	sortByRank(games, rank)

	if uint64(len(games)) > limit {
		games = games[:limit]
	}

	return &GameListResult{Results: games}, nil
}

// escapeQuery makes a user's search term safe to embed in an Apicalypse string literal
func escapeQuery(query string) string {
	replacer := strings.NewReplacer(`\`, `\\`, `"`, `\"`, "\n", " ", "\r", " ", ";", " ")

	return replacer.Replace(query)
}

// sortByRank orders games by their popularity position, pushing anything unranked to the back
func sortByRank(games []Game, rank map[uint64]int) {
	sort.SliceStable(games, func(i, j int) bool {
		left, leftRanked := rank[games[i].Id]
		right, rightRanked := rank[games[j].Id]

		if !leftRanked {
			return false
		}

		if !rightRanked {
			return true
		}

		return left < right
	})
}

// fetchGames runs an Apicalypse body against the games endpoint
func (c *client) fetchGames(ctx context.Context, body string) ([]Game, error) {
	payload, err := c.post(ctx, "/games", body)
	if err != nil {
		return nil, err
	}

	var games []Game
	if err = json.Unmarshal(payload, &games); err != nil {
		c.log.Error().Err(err).Msg("Failed to parse games response")
		return nil, err
	}

	return games, nil
}
