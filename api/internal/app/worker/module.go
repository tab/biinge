package worker

import "go.uber.org/fx"

var Module = fx.Options(
	fx.Provide(NewTmdbWorker),
	fx.Provide(NewJellyfinWorker),
	fx.Provide(NewShareWorker),
	fx.Invoke(func(*TmdbWorker, *JellyfinWorker, *ShareWorker) {}),
)
