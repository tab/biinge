package repositories

import (
	"go.uber.org/fx"

	"biinge-api/internal/app/repositories/postgres"
)

var Module = fx.Options(
	fx.Provide(postgres.NewPostgresClient),
	fx.Provide(NewHealthRepository),
	fx.Provide(NewMovieRepository),
	fx.Provide(NewSeriesRepository),
	fx.Provide(NewSeriesProgressRepository),
	fx.Provide(NewStatsRepository),
	fx.Provide(NewUserRepository),
	fx.Provide(NewSyncRepository),
)
