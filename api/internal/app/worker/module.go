package worker

import "go.uber.org/fx"

var Module = fx.Options(
	fx.Provide(NewWorker),
	fx.Invoke(func(*Worker) {}),
)
