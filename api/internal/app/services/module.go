package services

import "go.uber.org/fx"

var Module = fx.Options(
	fx.Provide(NewAuthentication),
	fx.Provide(NewHealthChecker),
	fx.Provide(NewTmdbProvider),
	fx.Provide(NewMovies),
	fx.Provide(NewUsers),
)
