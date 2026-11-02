package jellyfin

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

	signInPath   = "/Users/AuthenticateByName"
	signOutPath  = "/Sessions/Logout"
	itemsPath    = "/Users/{userId}/Items"
	episodesPath = "/Shows/{seriesId}/Episodes"

	// ItemTypeSeries sits beside ItemTypeMovie (event.go) as the other type Items returns
	ItemTypeSeries = "Series"

	// authorization names the API as a Jellyfin client on a device (device id, then app version)
	authorization = `MediaBrowser Client="biinge", Device="biinge API", DeviceId="%s", Version="%s"`
)

// Credentials are the Jellyfin username and password a user signs in with
type Credentials struct {
	Username string
	Password string
}

// Session is a signed-in Jellyfin user and the access token for that sign-in
type Session struct {
	AccessToken string
	UserId      string
	UserName    string
}

// Connection is a signed-in user's device id, access token and Jellyfin user id, for reads as that user
type Connection struct {
	DeviceId    string
	AccessToken string
	UserId      string
}

// Item is a movie or series in the user's library (TmdbId is empty when Jellyfin holds none)
type Item struct {
	Id     string
	Type   string
	TmdbId string
}

// Episode is one episode of a series (Season and Number are nil when Jellyfin holds none)
type Episode struct {
	Id     string
	Season *int
	Number *int
}

// Client signs a user in to and out of the instance's Jellyfin server, each sign-in as its own device, and reads their library
type Client interface {
	SignIn(ctx context.Context, deviceId string, credentials Credentials) (*Session, error)
	SignOut(ctx context.Context, deviceId string, token string) error
	Items(ctx context.Context, connection Connection) ([]Item, error)
	Episodes(ctx context.Context, connection Connection, seriesId string) ([]Episode, error)
}

type client struct {
	version   string
	apiClient *resty.Client
	log       *logger.Logger
}

// NewClient builds the Jellyfin client against cfg.Jellyfin.BaseURL
func NewClient(cfg *config.Config, log *logger.Logger) Client {
	apiClient := resty.New()

	// The proxy in front of Jellyfin answers 403 to default script user agents
	apiClient.
		SetBaseURL(cfg.Jellyfin.BaseURL).
		SetHeader("Accept", "application/json").
		SetHeader("User-Agent", "biinge-api").
		SetTimeout(DefaultTimeout)

	// Jellyfin answers 400 to an empty Version, and APP_VERSION is unset outside a Docker build
	version := cfg.AppVersion
	if version == "" {
		version = "dev"
	}

	return &client{
		version:   version,
		apiClient: apiClient,
		log:       log.WithComponent("JellyfinClient"),
	}
}

func (c *client) SignIn(ctx context.Context, deviceId string, credentials Credentials) (*Session, error) {
	// The body and headers carry the password, so only the path and status are logged
	response, err := c.apiClient.R().
		SetContext(ctx).
		SetHeader("Authorization", fmt.Sprintf(authorization, deviceId, c.version)).
		SetBody(map[string]string{"Username": credentials.Username, "Pw": credentials.Password}).
		Post(signInPath)
	if err != nil {
		c.log.Error().
			Err(err).
			Str("endpoint", signInPath).
			Msg("Failed to reach Jellyfin")

		return nil, ErrUnavailable
	}

	switch response.StatusCode() {
	case http.StatusOK:
		var result struct {
			AccessToken string
			User        struct {
				Id   string
				Name string
			}
		}
		if err = json.Unmarshal(response.Body(), &result); err != nil || result.AccessToken == "" || result.User.Id == "" {
			c.log.Error().
				Str("endpoint", signInPath).
				Int("statusCode", response.StatusCode()).
				Msg("Jellyfin sign-in response lacks a token or user id")

			return nil, ErrUnavailable
		}

		return &Session{AccessToken: result.AccessToken, UserId: result.User.Id, UserName: result.User.Name}, nil
	case http.StatusUnauthorized:
		c.log.Warn().
			Str("endpoint", signInPath).
			Int("statusCode", response.StatusCode()).
			Msg("Jellyfin rejected the credentials")

		return nil, ErrInvalidCredentials
	default:
		c.log.Error().
			Str("endpoint", signInPath).
			Int("statusCode", response.StatusCode()).
			Msg("Unexpected response from Jellyfin")

		return nil, ErrUnavailable
	}
}

func (c *client) SignOut(ctx context.Context, deviceId string, token string) error {
	// The Authorization header carries the token, so only the path and status are logged
	response, err := c.apiClient.R().
		SetContext(ctx).
		SetHeader("Authorization", fmt.Sprintf(authorization+`, Token="%s"`, deviceId, c.version, token)).
		Post(signOutPath)
	if err != nil {
		c.log.Error().
			Err(err).
			Str("endpoint", signOutPath).
			Msg("Failed to reach Jellyfin")

		return ErrUnavailable
	}

	switch response.StatusCode() {
	case http.StatusNoContent:
		return nil
	case http.StatusUnauthorized:
		c.log.Warn().
			Str("endpoint", signOutPath).
			Int("statusCode", response.StatusCode()).
			Msg("Jellyfin rejected the token")

		return ErrInvalidCredentials
	default:
		c.log.Error().
			Str("endpoint", signOutPath).
			Int("statusCode", response.StatusCode()).
			Msg("Unexpected response from Jellyfin")

		return ErrUnavailable
	}
}

func (c *client) Items(ctx context.Context, connection Connection) ([]Item, error) {
	// The Authorization header carries the token, so only the path template and status are logged
	response, err := c.apiClient.R().
		SetContext(ctx).
		SetHeader("Authorization", fmt.Sprintf(authorization+`, Token="%s"`, connection.DeviceId, c.version, connection.AccessToken)).
		SetPathParam("userId", connection.UserId).
		SetQueryParams(map[string]string{
			"IncludeItemTypes": ItemTypeMovie + "," + ItemTypeSeries,
			"Recursive":        "true",
			"Fields":           "ProviderIds",
			"EnableImages":     "false",
			"EnableUserData":   "false",
		}).
		Get(itemsPath)
	if err != nil {
		c.log.Error().
			Err(err).
			Str("endpoint", itemsPath).
			Msg("Failed to reach Jellyfin")

		return nil, ErrUnavailable
	}

	switch response.StatusCode() {
	case http.StatusOK:
		var result struct {
			Items []struct {
				Id          string
				Type        string
				ProviderIds map[string]string
			}
		}
		if err = json.Unmarshal(response.Body(), &result); err != nil {
			c.log.Error().
				Err(err).
				Str("endpoint", itemsPath).
				Int("statusCode", response.StatusCode()).
				Msg("Failed to decode the Jellyfin items")

			return nil, ErrUnavailable
		}

		items := make([]Item, 0, len(result.Items))
		for _, item := range result.Items {
			items = append(items, Item{Id: item.Id, Type: item.Type, TmdbId: item.ProviderIds["Tmdb"]})
		}

		return items, nil
	case http.StatusUnauthorized:
		c.log.Warn().
			Str("endpoint", itemsPath).
			Int("statusCode", response.StatusCode()).
			Msg("Jellyfin rejected the token")

		return nil, ErrInvalidCredentials
	default:
		c.log.Error().
			Str("endpoint", itemsPath).
			Int("statusCode", response.StatusCode()).
			Msg("Unexpected response from Jellyfin")

		return nil, ErrUnavailable
	}
}

func (c *client) Episodes(ctx context.Context, connection Connection, seriesId string) ([]Episode, error) {
	// The Authorization header carries the token, so only the path template and status are logged
	response, err := c.apiClient.R().
		SetContext(ctx).
		SetHeader("Authorization", fmt.Sprintf(authorization+`, Token="%s"`, connection.DeviceId, c.version, connection.AccessToken)).
		SetPathParam("seriesId", seriesId).
		SetQueryParams(map[string]string{
			"userId":         connection.UserId,
			"IsMissing":      "false",
			"EnableImages":   "false",
			"EnableUserData": "false",
		}).
		Get(episodesPath)
	if err != nil {
		c.log.Error().
			Err(err).
			Str("endpoint", episodesPath).
			Msg("Failed to reach Jellyfin")

		return nil, ErrUnavailable
	}

	switch response.StatusCode() {
	case http.StatusOK:
		var result struct {
			Items []struct {
				Id                string
				ParentIndexNumber *int
				IndexNumber       *int
			}
		}
		if err = json.Unmarshal(response.Body(), &result); err != nil {
			c.log.Error().
				Err(err).
				Str("endpoint", episodesPath).
				Int("statusCode", response.StatusCode()).
				Msg("Failed to decode the Jellyfin episodes")

			return nil, ErrUnavailable
		}

		episodes := make([]Episode, 0, len(result.Items))
		for _, episode := range result.Items {
			episodes = append(episodes, Episode{Id: episode.Id, Season: episode.ParentIndexNumber, Number: episode.IndexNumber})
		}

		return episodes, nil
	case http.StatusUnauthorized:
		c.log.Warn().
			Str("endpoint", episodesPath).
			Int("statusCode", response.StatusCode()).
			Msg("Jellyfin rejected the token")

		return nil, ErrInvalidCredentials
	default:
		c.log.Error().
			Str("endpoint", episodesPath).
			Int("statusCode", response.StatusCode()).
			Msg("Unexpected response from Jellyfin")

		return nil, ErrUnavailable
	}
}
