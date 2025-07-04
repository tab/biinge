package controllers

import "go.uber.org/fx"

var Module = fx.Options(
	fx.Provide(NewAuthenticationController),
	fx.Provide(NewHealthController),
	fx.Provide(NewAccountsController),
	fx.Provide(NewMoviesController),
	fx.Provide(NewPeopleController),
)
