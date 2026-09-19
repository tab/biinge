---
name: add-test
description: Write a Go test for the biinge api, table-driven with the mocks built once at the top. Use when adding tests, refactoring tests, or fixing a failing test under api/.
---

# Add a Go test

Match the `*_test.go` you are adding to before anything here. An existing file
in the same package is the better guide.

## Defaults

- Table-driven whenever a function has more than one scenario
- Never more than one `t.Run()` outside a table. Two cases means a table
- Named `Test_<Type>_<Method>`, so `Test_Games_List`, `Test_IgdbProvider_SearchGames`
- `testify` for assertions, `go.uber.org/mock` for mocks. Never `testify/mock`
- Same package as the source, so `package services`, not `services_test`

## The pattern

The controller and its mocks are built once at the top of the test function.
Each case carries a `before func()` that sets its own expectations.

```go
func Test_Games_List(t *testing.T) {
    ctrl := gomock.NewController(t)
    defer ctrl.Finish()

    ctx := context.Background()
    repository := NewMockGames(ctrl)
    service := NewGames(repository, logger.NewLogger(cfg))

    tests := []struct {
        name     string
        before   func()
        expected []models.Game
        error    error
    }{
        {
            name: "Success",
            before: func() {
                repository.EXPECT().List(ctx, userId).Return([]models.Game{{IgdbId: 100}}, nil)
            },
            expected: []models.Game{{IgdbId: 100}},
        },
        {
            name: "Error",
            before: func() {
                repository.EXPECT().List(ctx, userId).Return(nil, assert.AnError)
            },
            error: errors.ErrFailedToFetchGames,
        },
    }

    for _, tt := range tests {
        t.Run(tt.name, func(t *testing.T) {
            tt.before()

            result, err := service.List(ctx, userId)

            if tt.error != nil {
                require.ErrorIs(t, err, tt.error)
                assert.Nil(t, result)

                return
            }

            require.NoError(t, err)
            assert.Equal(t, tt.expected, result)
        })
    }
}
```

## Rules

- `require` for the error, `assert` for the values. A wrong error makes the
  value assertions noise, so stop at the first failure
- The error assertion comes before the result assertion
- Assert a sentinel with `require.ErrorIs`, never by matching the string
- Table cases are multi-line, one field per line. Never inline a case
- Add to the `*_test.go` matching the source file. Don't start a second one
- No comment above a `t.Run()`. The case name already says it
- No doc comment on a test function
- Deterministic inputs. No random generators, no `time.Now()` in an expectation
- Cover the success path and each error path
- Never disable a test or bend production code to make one pass

## Running them

Service and controller tests mock everything. Repository and `pkg/spec` tests
hit real Postgres:

```bash
docker compose up -d database redis
GO_ENV=test make db:migrate
cd api && make test
```

`make test` passes `-p=1`. Every package shares `biinge-test` and `pkg/spec`
truncates it, so packages left to run in parallel wipe each other's rows.

Generate a missing mock with the `generate-mock` skill before writing against
it, then finish with the `verify` skill.
