package worker

import "go.uber.org/fx"

var Module = fx.Options(
	fx.Provide(NewTmdbWorker),
	fx.Provide(NewJellyfinWorker),
	fx.Invoke(func(*TmdbWorker, *JellyfinWorker) {}),
)
