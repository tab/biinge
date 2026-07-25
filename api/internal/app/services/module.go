package services

import "go.uber.org/fx"

var Module = fx.Options(
	fx.Provide(NewAuthentication),
	fx.Provide(NewHealthChecker),
	fx.Provide(NewTmdbProvider),
	fx.Provide(NewMovies),
	fx.Provide(NewSeries),
	fx.Provide(NewProgress),
	fx.Provide(NewStatsCache),
	fx.Provide(NewStats),
	fx.Provide(NewUsers),
)
