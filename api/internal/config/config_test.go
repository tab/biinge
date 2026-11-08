package config

import (
	"flag"
	"log"
	"os"
	"testing"
	"time"

	"github.com/stretchr/testify/assert"

	"biinge-api/pkg/spec"
)

func TestMain(m *testing.M) {
	if err := spec.LoadEnv(); err != nil {
		log.Fatalf("Error loading environment variables: %v", err)
	}

	if os.Getenv("GO_ENV") == "ci" {
		os.Exit(0)
	}

	code := m.Run()
	os.Exit(code)
}

func Test_LoadConfig(t *testing.T) {
	tests := []struct {
		name     string
		args     []string
		env      map[string]string
		expected *Config
	}{
		{
			name: "Success",
			args: []string{},
			env:  map[string]string{},
			expected: &Config{
				AppEnv:       TestEnv,
				AppAddr:      "localhost:8080",
				ClientURL:    "http://localhost:3000",
				DatabaseDSN:  "postgres://postgres:postgres@localhost:5432/biinge-test?sslmode=disable",
				JWTSecretKey: "SECRET",
				TMDBConfig: TMDBConfig{
					BaseURL:            "https://api.themoviedb.org/3",
					APIReadAccessToken: "SECRET",
					Locale:             "en-US",
				},
				Jellyfin: JellyfinConfig{
					SyncInterval:      2 * time.Minute,
					ReconcileInterval: time.Hour,
				},
			},
		},
		{
			name: "Jellyfin sync enabled from the environment",
			args: []string{},
			env: map[string]string{
				"JELLYFIN_SYNC_ENABLED": "true",
			},
			expected: &Config{
				AppEnv:       TestEnv,
				AppAddr:      "localhost:8080",
				ClientURL:    "http://localhost:3000",
				DatabaseDSN:  "postgres://postgres:postgres@localhost:5432/biinge-test?sslmode=disable",
				JWTSecretKey: "SECRET",
				TMDBConfig: TMDBConfig{
					BaseURL:            "https://api.themoviedb.org/3",
					APIReadAccessToken: "SECRET",
					Locale:             "en-US",
				},
				Jellyfin: JellyfinConfig{
					SyncEnabled:       true,
					SyncInterval:      2 * time.Minute,
					ReconcileInterval: time.Hour,
				},
			},
		},
		{
			name: "Jellyfin intervals from the environment",
			args: []string{},
			env: map[string]string{
				"JELLYFIN_SYNC_INTERVAL":      "30s",
				"JELLYFIN_RECONCILE_INTERVAL": "6h",
			},
			expected: &Config{
				AppEnv:       TestEnv,
				AppAddr:      "localhost:8080",
				ClientURL:    "http://localhost:3000",
				DatabaseDSN:  "postgres://postgres:postgres@localhost:5432/biinge-test?sslmode=disable",
				JWTSecretKey: "SECRET",
				TMDBConfig: TMDBConfig{
					BaseURL:            "https://api.themoviedb.org/3",
					APIReadAccessToken: "SECRET",
					Locale:             "en-US",
				},
				Jellyfin: JellyfinConfig{
					SyncInterval:      30 * time.Second,
					ReconcileInterval: 6 * time.Hour,
				},
			},
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			for key, value := range tt.env {
				t.Setenv(key, value)
			}

			flag.CommandLine = flag.NewFlagSet(tt.name, flag.ContinueOnError)
			result := LoadConfig()

			assert.Equal(t, tt.expected.AppEnv, result.AppEnv)
			assert.Equal(t, tt.expected.AppAddr, result.AppAddr)
			assert.Equal(t, tt.expected.ClientURL, result.ClientURL)
			assert.Equal(t, tt.expected.DatabaseDSN, result.DatabaseDSN)
			assert.Equal(t, tt.expected.JWTSecretKey, result.JWTSecretKey)
			assert.Equal(t, tt.expected.BaseURL, result.BaseURL)
			assert.Equal(t, tt.expected.APIReadAccessToken, result.APIReadAccessToken)
			assert.Equal(t, tt.expected.Locale, result.Locale)
			assert.Equal(t, tt.expected.Jellyfin.SyncEnabled, result.Jellyfin.SyncEnabled)
			assert.Equal(t, tt.expected.Jellyfin.SyncInterval, result.Jellyfin.SyncInterval)
			assert.Equal(t, tt.expected.Jellyfin.ReconcileInterval, result.Jellyfin.ReconcileInterval)

			t.Cleanup(func() {
				for key := range tt.env {
					os.Unsetenv(key)
				}
			})
		})
	}
}

func Test_Config_Validate(t *testing.T) {
	valid := func() *Config {
		return &Config{
			AppEnv:       "production",
			DatabaseDSN:  "postgres://localhost:5432/biinge",
			JWTSecretKey: "a-strong-production-jwt-secret-key-32b+",
			TMDBConfig: TMDBConfig{
				APIReadAccessToken: "tmdb-token",
			},
			IGDB: IGDBConfig{
				BaseURL:      "https://api.igdb.com/v4",
				TokenURL:     "https://id.twitch.tv/oauth2/token",
				ClientID:     "igdb-client-id",
				ClientSecret: "igdb-client-secret",
			},
		}
	}

	// jellyfin is a valid Jellyfin configuration
	jellyfin := func() JellyfinConfig {
		return JellyfinConfig{
			BaseURL:           "http://jellyfin:8096",
			TokenKey:          "0123456789abcdef0123456789abcdef",
			SyncInterval:      time.Minute,
			ReconcileInterval: time.Hour,
		}
	}

	tests := []struct {
		name    string
		mutate  func(c *Config)
		wantErr string
	}{
		{
			name:   "Valid",
			mutate: func(c *Config) {},
		},
		{
			name:    "Missing database DSN",
			mutate:  func(c *Config) { c.DatabaseDSN = "" },
			wantErr: "DATABASE_DSN",
		},
		{
			name:    "Missing TMDB token",
			mutate:  func(c *Config) { c.APIReadAccessToken = "" },
			wantErr: "TMDB_API_READ_ACCESS_TOKEN",
		},
		{
			name:    "Missing JWT secret",
			mutate:  func(c *Config) { c.JWTSecretKey = "" },
			wantErr: "JWT_SECRET_KEY",
		},
		{
			name:    "Missing IGDB credentials in production",
			mutate:  func(c *Config) { c.IGDB.ClientID = ""; c.IGDB.ClientSecret = "" },
			wantErr: "IGDB_CLIENT_ID, IGDB_CLIENT_SECRET",
		},
		{
			name:    "Missing IGDB endpoints in production",
			mutate:  func(c *Config) { c.IGDB.BaseURL = ""; c.IGDB.TokenURL = "" },
			wantErr: "IGDB_BASE_URL, IGDB_TOKEN_URL",
		},
		{
			name:   "Missing IGDB configuration allowed in development",
			mutate: func(c *Config) { c.AppEnv = DevelopmentEnv; c.IGDB = IGDBConfig{} },
		},
		{
			name:    "JWT secret too short in production",
			mutate:  func(c *Config) { c.JWTSecretKey = "short" },
			wantErr: "at least 32 bytes",
		},
		{
			name:   "Short JWT secret allowed in development",
			mutate: func(c *Config) { c.AppEnv = DevelopmentEnv; c.JWTSecretKey = "SECRET" },
		},
		{
			name:   "Jellyfin with a 32-byte token key",
			mutate: func(c *Config) { c.Jellyfin = jellyfin() },
		},
		{
			name:    "Jellyfin with a zero sync interval",
			mutate:  func(c *Config) { c.Jellyfin = jellyfin(); c.Jellyfin.SyncInterval = 0 },
			wantErr: "JELLYFIN_SYNC_INTERVAL must be positive",
		},
		{
			name:    "Jellyfin with a negative sync interval",
			mutate:  func(c *Config) { c.Jellyfin = jellyfin(); c.Jellyfin.SyncInterval = -time.Minute },
			wantErr: "JELLYFIN_SYNC_INTERVAL must be positive when JELLYFIN_BASE_URL is set, got -1m0s",
		},
		{
			name:    "Jellyfin with a zero reconcile interval",
			mutate:  func(c *Config) { c.Jellyfin = jellyfin(); c.Jellyfin.ReconcileInterval = 0 },
			wantErr: "JELLYFIN_RECONCILE_INTERVAL must be positive",
		},
		{
			name:    "Jellyfin with a negative reconcile interval",
			mutate:  func(c *Config) { c.Jellyfin = jellyfin(); c.Jellyfin.ReconcileInterval = -time.Hour },
			wantErr: "JELLYFIN_RECONCILE_INTERVAL must be positive when JELLYFIN_BASE_URL is set, got -1h0m0s",
		},
		{
			name: "Nonpositive intervals without Jellyfin are ignored",
			mutate: func(c *Config) {
				c.Jellyfin.SyncInterval = 0
				c.Jellyfin.ReconcileInterval = -time.Hour
			},
		},
		{
			name:    "Jellyfin without a token key",
			mutate:  func(c *Config) { c.Jellyfin.BaseURL = "http://jellyfin:8096" },
			wantErr: "JELLYFIN_TOKEN_KEY must be 32 bytes",
		},
		{
			name: "Jellyfin with a 33-byte token key",
			mutate: func(c *Config) {
				c.Jellyfin = JellyfinConfig{BaseURL: "http://jellyfin:8096", TokenKey: "0123456789abcdef0123456789abcdef0"}
			},
			wantErr: "got 33",
		},
		{
			name: "Jellyfin with a short token key in development",
			mutate: func(c *Config) {
				c.AppEnv = DevelopmentEnv
				c.Jellyfin = JellyfinConfig{BaseURL: "http://jellyfin:8096", TokenKey: "SECRET"}
			},
			wantErr: "got 6",
		},
		{
			name:   "Token key without Jellyfin is ignored",
			mutate: func(c *Config) { c.Jellyfin.TokenKey = "SECRET" },
		},
	}

	for _, tt := range tests {
		t.Run(tt.name, func(t *testing.T) {
			cfg := valid()
			tt.mutate(cfg)

			err := cfg.Validate()

			if tt.wantErr == "" {
				assert.NoError(t, err)
			} else {
				assert.ErrorContains(t, err, tt.wantErr)
			}
		})
	}
}
