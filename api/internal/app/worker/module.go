package worker

import "go.uber.org/fx"

var Module = fx.Options(
	fx.Provide(NewTmdbWorker),
	fx.Invoke(func(*TmdbWorker) {}),
)
