package middlewares

import "go.uber.org/fx"

var Module = fx.Options(
	fx.Provide(NewLoggerMiddleware),
	fx.Provide(NewAuthenticationMiddleware),
)
