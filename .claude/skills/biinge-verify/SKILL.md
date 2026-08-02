---
name: biinge-verify
description: Run the verification loop for the area you changed (api, ios or docs). Use at the end of any implementation, when asked to verify changes, run lint or tests, or check that changes pass CI.
---

# biinge verification loop

Run the loop for every area the change touched. Fix issues at each step and
re-run before moving to the next. **An implementation isn't finished until its
loop is clean** — that includes changes that don't end in a commit.

## api

```bash
cd api
make check
```

`make check` runs fmt → vet → lint → staticcheck → test → test:race, the same
set CI runs. To iterate on one step:

```bash
make fmt          # gofmt
make lint         # golangci-lint (make lint:fix applies what it can)
make vet
make staticcheck
make test         # GO_ENV=test, needs a live biinge-test database
make test:race
```

Tests need Postgres running and the `biinge-test` database migrated:

```bash
docker compose up -d database redis
GO_ENV=test make db:migrate
```

If the database isn't reachable, say the suite didn't run. Never report success
from the steps that happened to pass.

## ios

```bash
cd ios
make lint     # SwiftLint, skipped with a notice if not installed
make test     # BiingeTests on a simulator, needs Xcode 26 and an iOS 26 runtime
```

`make build` when the change is UI-only and you just need it to compile.

## docs

```bash
cd docs
npm run build
```

The build is the only check — there's no separate lint or test. Confirm the
pages you touched are in `dist/` and that env-derived URLs resolved the way you
expect.

## Reporting

State which loops ran and what they returned. If one couldn't run, name it and
call the change unverified rather than implying full coverage.
