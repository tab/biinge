# api

Go REST API on chi, wired with uber-fx. See `README.md` for setup and commands.

## Layering

`controllers → services → repositories → db`

- `internal/app/repositories/db/` is sqlc output. Never hand-edit it
- `repositories/` wraps the generated queries and passes raw errors through,
  `pgx.ErrNoRows` included
- `services/` hold the business rules. A service logs a repository failure and
  returns a sentinel from `app/errors` — that translation is the service's job
- `controllers/` map sentinels to status codes and encode a `serializers` type.
  They don't re-log what a service already logged
- `serializers/` are the wire shapes. Models never go out directly

## Rules the linters don't catch

- A missing row is ordinary, not a failure. On `pgx.ErrNoRows` return the
  not-found sentinel *without* an error-level log — the details screen looks up
  every title a user opens and most aren't in their library, so logging it as an
  error buries real failures
- Any write that moves a user's watch counts calls `stats.Invalidate`, or the
  cached statistics stay stale until the TTL. That includes the sync worker,
  when a corrected runtime changes watched minutes
- New services register in `services/module.go`; every package exposes its
  wiring the same way through a `Module`. Everything is constructed by fx — never
  instantiate a dependency by hand in application code
- Dependencies are interfaces so fx can inject and gomock can replace them. Name
  them for the capability (`Movies`, `StatsCache`), never with an `I` prefix, and
  give each one a mock
- Import `internal/app/errors` plainly, never aliased as `apperrors`. It
  re-exports `Is`, `As` and `Unwrap`, so a file needs no stdlib `errors` import
- No `else if`. Use a `switch` or a guard clause
- Imports in three groups separated by blank lines: stdlib, third-party, then
  `biinge-api/...`
- Four or more parameters, or three or more return values, is a signal to pass a
  struct. fx constructors are exempt — named dependencies read better there
- `//nolint` goes on the line above, never inline, and names the specific linter
  with an explanation — `nolintlint` enforces both

## The OpenAPI spec ships with the change

`api/swagger.yaml` is the contract for every route and is hand-maintained — no
generator writes it. Any change to a path, query parameter, request body,
response shape or status code updates it in the same commit. The iOS client
reads it as the backend's documentation, so a stale spec misleads the other half
of the repo.

`docs/src/pages/docs/api.astro` carries its own hand-written endpoint list for
the reference page and playground. It doesn't read the spec, so a contract
change touches both.

## Generated code is committed

Regenerate and commit alongside the change:

- `sqlc generate` after editing `db/sqlc/`
- `make db:schema:dump` after adding a migration — `db/schema.sql` is the
  canonical dump, and CI loads it to create the test database
- mockgen mocks live next to the interface they mock as `*_mock.go`

`vendor/` is gitignored. Don't commit it.

## Verification loop

`make check` at the end of every change — it runs fmt, lint, test and test:race,
the same set CI runs. golangci-lint covers go vet and staticcheck, so neither
runs separately. Fix and re-run until clean.

Tests run with `-p=1`. Every package shares the `biinge-test` database and
`pkg/spec` truncates it, so packages running in parallel wipe each other's rows
mid-test and fail on a foreign key.

Tests need a live `biinge-test` database and `GO_ENV=test`. If the database
isn't reachable, say the suite didn't run rather than reporting success from the
steps that did.
