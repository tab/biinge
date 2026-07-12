package services

import "go.uber.org/fx"

var Module = fx.Options(
	fx.Provide(NewAuthentication),
	fx.Provide(NewHealthChecker),
	fx.Provide(NewTmdbProvider),
	fx.Provide(NewMovies),
	fx.Provide(NewSeries),
	fx.Provide(NewSeasons),
	fx.Provide(NewEpisodes),
	fx.Provide(NewProgress),
	fx.Provide(NewStats),
	fx.Provide(NewUsers),
)
