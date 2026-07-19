package config

import (
	"fmt"
	"os"
	"strconv"
	"strings"
	"time"

	"github.com/joho/godotenv"
)

const DebugLevel = "debug"

// Application environment names
const (
	DevelopmentEnv = "development"
	TestEnv        = "test"
)

// minJWTSecretLength is the minimum length for an HS256 signing key (256 bits)
const minJWTSecretLength = 32

// Sync worker defaults, tuned for a small library and calm TMDB usage
const (
	defaultSyncInterval         = 2 * time.Hour
	defaultSyncBatchSize        = 50
	defaultSyncStaleness        = 7 * 24 * time.Hour
	defaultSyncMovieMaxAgeDays  = 180
	defaultSyncSeriesMaxAgeDays = 1095
)

type TMDBConfig struct {
	BaseURL      string
	BaseImageURL string

	APIReadAccessToken string

	Locale  string
	Timeout time.Duration
}

// WorkerConfig tunes the background TMDB sync worker
type WorkerConfig struct {
	SyncEnabled          bool
	SyncInterval         time.Duration
	SyncBatchSize        int
	SyncStaleness        time.Duration
	SyncMovieMaxAgeDays  int
	SyncSeriesMaxAgeDays int
}

type Config struct {
	AppEnv        string
	AppName       string
	AppVersion    string
	AppAddr       string
	ClientURL     string
	DatabaseDSN   string
	SecretKeyBase string
	JWTSecretKey  string
	LogLevel      string
	SentryDSN     string

	RedisURL string

	TMDBConfig
	WorkerConfig
}

func LoadConfig() *Config {
	env := os.Getenv("GO_ENV")
	if env == "" {
		env = DevelopmentEnv
	}

	envFiles := []string{
		".env",
		".env." + env,
		fmt.Sprintf(".env.%s.local", env),
	}
	for _, file := range envFiles {
		_ = godotenv.Overload(file)
	}

	return &Config{
		AppEnv:        env,
		AppName:       getEnvString("APP_NAME"),
		AppVersion:    getEnvString("APP_VERSION"),
		AppAddr:       getEnvString("APP_ADDRESS"),
		ClientURL:     getEnvString("CLIENT_URL"),
		DatabaseDSN:   getEnvString("DATABASE_DSN"),
		SecretKeyBase: getEnvString("SECRET_KEY_BASE"),
		JWTSecretKey:  getEnvString("JWT_SECRET_KEY"),
		LogLevel:      getEnvString("LOG_LEVEL"),
		SentryDSN:     getEnvString("SENTRY_DSN"),

		RedisURL: getEnvString("REDIS_URL"),

		TMDBConfig: TMDBConfig{
			BaseURL:            getEnvString("TMDB_BASE_URL"),
			BaseImageURL:       getEnvString("TMDB_BASE_IMAGE_URL"),
			APIReadAccessToken: getEnvString("TMDB_API_READ_ACCESS_TOKEN"),
			Locale:             getEnvString("TMDB_LOCALE"),
		},

		WorkerConfig: WorkerConfig{
			SyncEnabled:          getEnvBool("WORKER_SYNC_ENABLED", true),
			SyncInterval:         getEnvDuration("WORKER_SYNC_INTERVAL", defaultSyncInterval),
			SyncBatchSize:        getEnvInt("WORKER_SYNC_BATCH_SIZE", defaultSyncBatchSize),
			SyncStaleness:        getEnvDuration("WORKER_SYNC_STALENESS", defaultSyncStaleness),
			SyncMovieMaxAgeDays:  getEnvInt("WORKER_SYNC_MOVIE_MAX_AGE_DAYS", defaultSyncMovieMaxAgeDays),
			SyncSeriesMaxAgeDays: getEnvInt("WORKER_SYNC_SERIES_MAX_AGE_DAYS", defaultSyncSeriesMaxAgeDays),
		},
	}
}

// Validate checks required config is set and the JWT secret is strong enough
func (c *Config) Validate() error {
	var missing []string

	if c.DatabaseDSN == "" {
		missing = append(missing, "DATABASE_DSN")
	}

	if c.APIReadAccessToken == "" {
		missing = append(missing, "TMDB_API_READ_ACCESS_TOKEN")
	}

	if c.JWTSecretKey == "" {
		missing = append(missing, "JWT_SECRET_KEY")
	}

	if len(missing) > 0 {
		return fmt.Errorf("missing required configuration: %s", strings.Join(missing, ", "))
	}

	// Require a strong signing key outside local dev
	if !c.isLocalEnv() && len(c.JWTSecretKey) < minJWTSecretLength {
		return fmt.Errorf("JWT_SECRET_KEY must be at least %d bytes, got %d", minJWTSecretLength, len(c.JWTSecretKey))
	}

	return nil
}

// isLocalEnv reports whether the app runs in a local development or test environment
func (c *Config) isLocalEnv() bool {
	return c.AppEnv == DevelopmentEnv || c.AppEnv == TestEnv
}

func getEnvString(envVar string) string {
	if envValue, ok := os.LookupEnv(envVar); ok && envValue != "" {
		return envValue
	}

	return ""
}

// getEnvBool reads a boolean env var, falling back to def when unset or unparseable
func getEnvBool(envVar string, def bool) bool {
	value := getEnvString(envVar)
	if value == "" {
		return def
	}

	parsed, err := strconv.ParseBool(value)
	if err != nil {
		return def
	}

	return parsed
}

// getEnvInt reads an integer env var, falling back to def when unset or unparseable
func getEnvInt(envVar string, def int) int {
	value := getEnvString(envVar)
	if value == "" {
		return def
	}

	parsed, err := strconv.Atoi(value)
	if err != nil {
		return def
	}

	return parsed
}

// getEnvDuration reads a Go-duration env var, falling back to def when unset or unparseable
func getEnvDuration(envVar string, def time.Duration) time.Duration {
	value := getEnvString(envVar)
	if value == "" {
		return def
	}

	parsed, err := time.ParseDuration(value)
	if err != nil {
		return def
	}

	return parsed
}
