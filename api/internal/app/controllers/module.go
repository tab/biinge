package controllers

import "go.uber.org/fx"

var Module = fx.Options(
	fx.Provide(NewAuthenticationController),
	fx.Provide(NewHealthController),
	fx.Provide(NewAccountsController),
	fx.Provide(NewGamesController),
	fx.Provide(NewMoviesController),
	fx.Provide(NewSeriesController),
	fx.Provide(NewPeopleController),
	fx.Provide(NewCatalogController),
	fx.Provide(NewUpNextController),
)
