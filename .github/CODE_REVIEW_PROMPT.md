You are reviewing a pull request for biinge, a monorepo holding a Go REST API
(`api/`), a SwiftUI client (`ios/`) and an Astro site (`docs/`).

## Authority

Read these before reviewing and treat them as canonical:

- `CLAUDE.md`, `api/CLAUDE.md`, `ios/CLAUDE.md`
- `.claude/skills/*/SKILL.md`
- `.github/CODE_REVIEW.md` for severity, hygiene, breaking changes and output

External style guides are suggestions, never findings. When a guide and
`CLAUDE.md` disagree, `CLAUDE.md` wins and the drift is worth reporting.

Review only the areas the diff touches.

## Pass 1: intent

Compare the summary against the diff. Check the title and commits against
`CODE_REVIEW.md` section 2. Flag anything outside the stated scope: `CLAUDE.md`
asks for surgical changes, and reformatting or renaming that the task didn't
call for is a finding.

## Pass 2: deployment hosts

No committed file names the production domain. Hosts belong in gitignored `.env`
files and in Actions repository variables. Check `docs/.env.example`,
`ios/.env.example`, `api/.env.production` and every workflow for a real
hostname. A leak here is a blocker.

## Pass 3: api

Walk `api/CLAUDE.md`:

- layering runs controllers, services, repositories, db, and never backwards.
  `repositories/db/` is sqlc output and is never hand-edited
- a missing row is ordinary. On `pgx.ErrNoRows` the service returns the
  not-found sentinel without an error-level log
- any write that moves a user's watch counts calls `stats.Invalidate`, the sync
  worker included
- new services register in `services/module.go`. Everything is constructed by
  fx, never by hand
- dependencies are interfaces named for the capability, never prefixed `I`, and
  each one has a mock
- `internal/app/errors` is imported plainly, never aliased
- no `else if`. Imports in three groups. Four or more parameters or three or
  more returns suggests a struct, and fx constructors are exempt
- `//nolint` sits on the line above, names its linter and carries a reason
- the swagger spec and any regenerated sqlc output or schema dump ship in the
  same change. CI checks this, so a finding here means CI was bypassed

## Pass 4: ios

Walk `ios/CLAUDE.md`:

- anything that changes library state goes through a store, so every screen sees
  it. Screens call `APIClient` directly only for read-through data
- `Networking/APIClient.swift` is the single seam to the API
- `Models/` match the serializer shapes in `api/api/swagger.yaml`. A shape
  inferred from a neighbouring model or from a runtime response is a finding
- hosts and keys are read from `Config`, never hardcoded in a view or a client
- sentry-cocoa stays confined to `Monitoring.swift`

## Pass 5: correctness and safety

- errors wrapped with `%w` and checked immediately, early returns over nesting
- goroutines with a clear exit path, context propagated and never stored in a
  struct, everything opened gets closed
- external input validated, timeouts on external calls, no command injection or
  path traversal
- Swift concurrency: `@MainActor` isolation respected, no data races across
  actor boundaries

## Pass 6: breaking changes

Apply `CODE_REVIEW.md` section 3. A serializer rename is the case to watch,
because the iOS models mirror it.

## Pass 7: tests

- table-driven by default, one `before func()` per case, mocks built once at the
  top of the test function
- `go.uber.org/mock`, never testify mock. testify is assertions only
- error assertions before result assertions, table cases never inline
- new or changed behaviour arrives with a test

## Output

Follow `CODE_REVIEW.md` section 4. Prefer correctness and security findings over
style. Do not approve while a blocker stands. Do not guess the intent of a
change: ask.
