package repositories

import (
	"go.uber.org/fx"

	"biinge-api/internal/app/repositories/postgres"
)

var Module = fx.Options(
	fx.Provide(postgres.NewPostgresClient),
	fx.Provide(NewHealthRepository),
	fx.Provide(NewUserRepository),
)
