package tmdb

import (
	"context"
	"encoding/json"
	"fmt"
	"net/http"
	"time"

	"github.com/go-resty/resty/v2"

	"biinge-api/internal/config"
	"biinge-api/internal/config/logger"
)

const (
	DefaultTimeout = 10 * time.Second

	MaxIdleConnections        = 10000
	MaxIdleConnectionsPerHost = 10000
	IdleConnTimeout           = 90 * time.Second
	TLSHandshakeTimeout       = 10 * time.Second
)

type Client interface {
	FetchMovieDetails(ctx context.Context, id uint64) (*MovieDetails, error)
	FetchTvDetails(ctx context.Context, id uint64) (*TvDetails, error)
	FetchTvSeasonDetails(ctx context.Context, id uint64, seasonNumber uint64) (*SeasonDetails, error)
	FetchTvEpisodeDetails(ctx context.Context, id uint64, seasonNumber uint64, episodeNumber uint64) (*EpisodeDetails, error)
	FetchPersonDetails(ctx context.Context, id uint64) (*PersonDetails, error)

	WithApiReadAccessToken(apiReadAccessToken string) Client
	WithLocale(lang string) Client
	WithTimeout(timeout time.Duration) Client
}

type client struct {
	cfg       *config.Config
	apiClient *resty.Client
	log       *logger.Logger
}

func NewClient(cfg *config.Config, log *logger.Logger) Client {
	apiClient := resty.New()

	apiClient.
		SetHeader("Accept", "application/json").
		SetHeader("Content-Type", "application/json").
		SetHeader("Authorization", fmt.Sprintf("Bearer %s", cfg.TMDBConfig.APIReadAccessToken)).
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
		log:       log.WithComponent("TmdbClient"),
	}
}

//nolint:dupl
func (c *client) FetchMovieDetails(ctx context.Context, id uint64) (*MovieDetails, error) {
	endpoint := fmt.Sprintf("%s/movie/%d", c.cfg.TMDBConfig.BaseURL, id)

	c.log.Debug().
		Str("endpoint", endpoint).
		Uint64("Id", id).
		Msg("Fetching movie details")

	response, err := c.apiClient.R().
		SetContext(ctx).
		SetQueryParam("language", c.cfg.TMDBConfig.Locale).
		SetQueryParam("append_to_response", "credits,recommendations,videos").
		Get(endpoint)
	if err != nil {
		c.log.Error().
			Err(err).
			Uint64("Id", id).
			Msg("Failed to fetch movie details")
		return nil, err
	}

	switch response.StatusCode() {
	case http.StatusOK:
		var result MovieDetails
		if err = json.Unmarshal(response.Body(), &result); err != nil {
			c.log.Error().
				Err(err).
				Uint64("Id", id).
				Msg("Failed to parse movie details response")
			return nil, err
		}

		return &result, nil
	case http.StatusUnauthorized, http.StatusForbidden:
		c.log.Error().
			Int("statusCode", response.StatusCode()).
			Uint64("Id", id).
			Msg("Access forbidden to TMDB API")
		return nil, ErrAccessForbidden
	case http.StatusNotFound:
		c.log.Error().
			Int("statusCode", response.StatusCode()).
			Uint64("Id", id).
			Msg("Movie not found in TMDB API")
		return nil, ErrNotFound
	default:
		c.log.Error().
			Int("statusCode", response.StatusCode()).
			Uint64("Id", id).
			Msg("Unexpected response from TMDB API")
		return nil, ErrUnexpectedResponse
	}
}

//nolint:dupl
func (c *client) FetchTvDetails(ctx context.Context, id uint64) (*TvDetails, error) {
	endpoint := fmt.Sprintf("%s/tv/%d", c.cfg.TMDBConfig.BaseURL, id)

	c.log.Debug().
		Str("endpoint", endpoint).
		Uint64("Id", id).
		Msg("Fetching tv show details")

	response, err := c.apiClient.R().
		SetContext(ctx).
		SetQueryParam("language", c.cfg.TMDBConfig.Locale).
		SetQueryParam("append_to_response", "credits,recommendations,videos").
		Get(endpoint)
	if err != nil {
		c.log.Error().
			Err(err).
			Uint64("Id", id).
			Msg("Failed to fetch tv details")
		return nil, err
	}

	switch response.StatusCode() {
	case http.StatusOK:
		var result TvDetails
		if err = json.Unmarshal(response.Body(), &result); err != nil {
			c.log.Error().
				Err(err).
				Uint64("Id", id).
				Msg("Failed to parse tv details response")
			return nil, err
		}

		return &result, nil
	case http.StatusUnauthorized, http.StatusForbidden:
		c.log.Error().
			Int("statusCode", response.StatusCode()).
			Uint64("Id", id).
			Msg("Access forbidden to TMDB API")
		return nil, ErrAccessForbidden
	case http.StatusNotFound:
		c.log.Error().
			Int("statusCode", response.StatusCode()).
			Uint64("Id", id).
			Msg("Tv show not found in TMDB API")
		return nil, ErrNotFound
	default:
		c.log.Error().
			Int("statusCode", response.StatusCode()).
			Uint64("Id", id).
			Msg("Unexpected response from TMDB API")
		return nil, ErrUnexpectedResponse
	}
}

//nolint:dupl
func (c *client) FetchTvSeasonDetails(ctx context.Context, tvId uint64, seasonNumber uint64) (*SeasonDetails, error) {
	endpoint := fmt.Sprintf("%s/tv/%d/season/%d", c.cfg.TMDBConfig.BaseURL, tvId, seasonNumber)

	c.log.Debug().
		Str("endpoint", endpoint).
		Uint64("TvId", tvId).
		Uint64("SeasonNumber", seasonNumber).
		Msg("Fetching TV season details")

	response, err := c.apiClient.R().
		SetContext(ctx).
		SetQueryParam("language", c.cfg.TMDBConfig.Locale).
		Get(endpoint)

	if err != nil {
		c.log.Error().
			Err(err).
			Uint64("TvId", tvId).
			Uint64("SeasonNumber", seasonNumber).
			Msg("Failed to fetch TV season details")
		return nil, err
	}

	switch response.StatusCode() {
	case http.StatusOK:
		var result SeasonDetails
		if err = json.Unmarshal(response.Body(), &result); err != nil {
			c.log.Error().
				Err(err).
				Uint64("TvId", tvId).
				Uint64("SeasonNumber", seasonNumber).
				Msg("Failed to parse TV season details response")
			return nil, err
		}

		return &result, nil
	case http.StatusUnauthorized, http.StatusForbidden:
		c.log.Error().
			Int("statusCode", response.StatusCode()).
			Uint64("TvId", tvId).
			Uint64("SeasonNumber", seasonNumber).
			Msg("Access forbidden to TMDB API")
		return nil, ErrAccessForbidden
	case http.StatusNotFound:
		c.log.Error().
			Int("statusCode", response.StatusCode()).
			Uint64("TvId", tvId).
			Uint64("SeasonNumber", seasonNumber).
			Msg("TV season not found in TMDB API")
		return nil, ErrNotFound
	default:
		c.log.Error().
			Int("statusCode", response.StatusCode()).
			Uint64("TvId", tvId).
			Uint64("SeasonNumber", seasonNumber).
			Msg("Unexpected response from TMDB API")
		return nil, ErrUnexpectedResponse
	}
}

// nolint:dupl
func (c *client) FetchTvEpisodeDetails(ctx context.Context, tvId uint64, seasonNumber uint64, episodeNumber uint64) (*EpisodeDetails, error) {
	endpoint := fmt.Sprintf("%s/tv/%d/season/%d/episode/%d", c.cfg.TMDBConfig.BaseURL, tvId, seasonNumber, episodeNumber)

	c.log.Debug().
		Str("endpoint", endpoint).
		Uint64("TvId", tvId).
		Uint64("SeasonNumber", seasonNumber).
		Uint64("EpisodeNumber", episodeNumber).
		Msg("Fetching TV episode details")

	response, err := c.apiClient.R().
		SetContext(ctx).
		SetQueryParam("language", c.cfg.TMDBConfig.Locale).
		Get(endpoint)

	if err != nil {
		c.log.Error().
			Err(err).
			Uint64("TvId", tvId).
			Uint64("SeasonNumber", seasonNumber).
			Uint64("EpisodeNumber", episodeNumber).
			Msg("Failed to fetch TV episode details")
		return nil, err
	}

	switch response.StatusCode() {
	case http.StatusOK:
		var result EpisodeDetails
		if err = json.Unmarshal(response.Body(), &result); err != nil {
			c.log.Error().
				Err(err).
				Uint64("TvId", tvId).
				Uint64("SeasonNumber", seasonNumber).
				Uint64("EpisodeNumber", episodeNumber).
				Msg("Failed to parse TV episode details response")
			return nil, err
		}

		return &result, nil
	case http.StatusUnauthorized, http.StatusForbidden:
		c.log.Error().
			Int("statusCode", response.StatusCode()).
			Uint64("TvId", tvId).
			Uint64("SeasonNumber", seasonNumber).
			Uint64("EpisodeNumber", episodeNumber).
			Msg("Access forbidden to TMDB API")
		return nil, ErrAccessForbidden
	case http.StatusNotFound:
		c.log.Error().
			Int("statusCode", response.StatusCode()).
			Uint64("TvId", tvId).
			Uint64("SeasonNumber", seasonNumber).
			Uint64("EpisodeNumber", episodeNumber).
			Msg("TV episode not found in TMDB API")
		return nil, ErrNotFound
	default:
		c.log.Error().
			Int("statusCode", response.StatusCode()).
			Uint64("TvId", tvId).
			Uint64("SeasonNumber", seasonNumber).
			Uint64("EpisodeNumber", episodeNumber).
			Msg("Unexpected response from TMDB API")
		return nil, ErrUnexpectedResponse
	}
}

//nolint:dupl
func (c *client) FetchPersonDetails(ctx context.Context, id uint64) (*PersonDetails, error) {
	endpoint := fmt.Sprintf("%s/person/%d", c.cfg.TMDBConfig.BaseURL, id)

	c.log.Debug().
		Str("endpoint", endpoint).
		Uint64("Id", id).
		Msg("Fetching person details")

	response, err := c.apiClient.R().
		SetContext(ctx).
		SetQueryParam("language", c.cfg.TMDBConfig.Locale).
		SetQueryParam("append_to_response", "credits,tv_credits").
		Get(endpoint)
	if err != nil {
		c.log.Error().
			Err(err).
			Uint64("Id", id).
			Msg("Failed to fetch person details")
		return nil, err
	}

	switch response.StatusCode() {
	case http.StatusOK:
		var result PersonDetails
		if err = json.Unmarshal(response.Body(), &result); err != nil {
			c.log.Error().
				Err(err).
				Uint64("Id", id).
				Msg("Failed to parse person details response")
			return nil, err
		}

		return &result, nil
	case http.StatusUnauthorized, http.StatusForbidden:
		c.log.Error().
			Int("statusCode", response.StatusCode()).
			Uint64("Id", id).
			Msg("Access forbidden to TMDB API")
		return nil, ErrAccessForbidden
	case http.StatusNotFound:
		c.log.Error().
			Int("statusCode", response.StatusCode()).
			Uint64("Id", id).
			Msg("Person not found in TMDB API")
		return nil, ErrNotFound
	default:
		c.log.Error().
			Int("statusCode", response.StatusCode()).
			Uint64("Id", id).
			Msg("Unexpected response from TMDB API")
		return nil, ErrUnexpectedResponse
	}
}

func (c *client) WithApiReadAccessToken(apiReadAccessToken string) Client {
	c.cfg.TMDBConfig.APIReadAccessToken = apiReadAccessToken
	c.apiClient.SetHeader("Authorization", fmt.Sprintf("Bearer %s", apiReadAccessToken))
	return c
}

func (c *client) WithLocale(lang string) Client {
	c.cfg.TMDBConfig.Locale = lang
	c.apiClient.SetQueryParam("language", lang)
	return c
}

func (c *client) WithTimeout(timeout time.Duration) Client {
	c.cfg.TMDBConfig.Timeout = timeout
	c.apiClient.SetTimeout(timeout)
	return c
}
