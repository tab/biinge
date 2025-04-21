package config

import (
	"flag"
	"fmt"
	"os"

	"github.com/joho/godotenv"
)

const (
	AppAddr    = "0.0.0.0:8080"
	ClientURL  = "http://localhost:3000"
	DebugLevel = "debug"
)

type Config struct {
	AppEnv      string
	AppName     string
	AppAddr     string
	ClientURL   string
	DatabaseDSN string
	LogLevel    string
}

func LoadConfig() *Config {
	env := os.Getenv("GO_ENV")
	if env == "" {
		env = "development"
	}

	envFiles := []string{
		".env",
		fmt.Sprintf(".env.%s", env),
		fmt.Sprintf(".env.%s.local", env),
	}
	for _, file := range envFiles {
		_ = godotenv.Overload(file)
	}

	flagAppAddr := flag.String("b", AppAddr, "server address")
	flagClientURL := flag.String("c", ClientURL, "client address")
	flagDatabaseDSN := flag.String("d", "", "database DSN")
	flag.Parse()

	return &Config{
		AppEnv:      env,
		AppName:     getEnvString("APP_NAME"),
		AppAddr:     getFlagOrEnvString(*flagAppAddr, "APP_ADDRESS", AppAddr),
		ClientURL:   getFlagOrEnvString(*flagClientURL, "CLIENT_URL", ClientURL),
		DatabaseDSN: getFlagOrEnvString(*flagDatabaseDSN, "DATABASE_DSN", ""),
		LogLevel:    getEnvString("LOG_LEVEL"),
	}
}

func getFlagOrEnvString(flagValue, envVar, defaultValue string) string {
	if flagValue != "" {
		return flagValue
	}

	if envValue, ok := os.LookupEnv(envVar); ok && envValue != "" {
		return envValue
	}

	return defaultValue
}

func getEnvString(envVar string) string {
	if envValue, ok := os.LookupEnv(envVar); ok && envValue != "" {
		return envValue
	}

	return ""
}
