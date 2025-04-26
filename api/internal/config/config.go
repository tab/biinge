package config

import (
	"fmt"
	"os"

	"github.com/joho/godotenv"
)

const DebugLevel = "debug"


type Config struct {
	AppEnv        string
	AppName       string
	AppAddr       string
	ClientURL     string
	DatabaseDSN   string
	SecretKeyBase string
	JWTSecretKey  string
	LogLevel      string
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

	return &Config{
		AppEnv:        env,
		AppName:       getEnvString("APP_NAME"),
		AppAddr:       getEnvString("APP_ADDRESS"),
		ClientURL:     getEnvString("CLIENT_URL"),
		DatabaseDSN:   getEnvString("DATABASE_DSN"),
		SecretKeyBase: getEnvString("SECRET_KEY_BASE"),
		JWTSecretKey:  getEnvString("JWT_SECRET_KEY"),
		LogLevel:      getEnvString("LOG_LEVEL"),
	}
}

func getEnvString(envVar string) string {
	if envValue, ok := os.LookupEnv(envVar); ok && envValue != "" {
		return envValue
	}

	return ""
}
