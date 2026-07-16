# biinge

Movie & TV tracker. Monorepo, one deployable unit per top-level directory.

| Path   | What                                                                                  |
| ------ | ------------------------------------------------------------------------------------- |
| `api/` | Go backend — Chi, pgx/sqlc, goose, JWT, TMDB. PostgreSQL-backed REST API on `:8080`.  |
| `ios/` | SwiftUI client (iOS 26, Swift 6, zero deps): login, library, detail, search, profile.  |

The two apps are decoupled by the HTTP contract in `api/api/swagger.yaml`; there is no shared code directory.

## Local development

Start Postgres and Redis (and optionally build the API image):

```sh
docker compose up -d database redis  # Postgres on :5432, Redis on :6379
make -C api db:migrate               # apply migrations (GO_ENV=development)
```

TMDB proxy responses (detail/search/trending) are cached in Redis when `REDIS_URL` is set
(e.g. `redis://localhost:6379`); the cache is optional — with it unset, or Redis unreachable,
the API just serves uncached.

Run the API from source, or boot everything with readiness checks via [fuku](https://github.com/tab/fuku):

```sh
cd api && GO_ENV=development go run ./cmd/biinge   # http://localhost:8080
# — or —
fuku up                                            # runs the api, waits on /ready
```

Health: `GET /health` · Readiness: `GET /ready` · API base: `/api/v1`.

Real TMDB and JWT secrets go in `api/.env.development.local` (gitignored); the committed
`api/.env.development` holds `SECRET` placeholders.

## iOS app

Open `ios/Biinge.xcodeproj` in Xcode 26 and run on an iOS 26 simulator, or build from the CLI:

```sh
make -C ios build
```

The app targets `http://localhost:8080/api/v1` by default; override with the `API_BASE_URL`
scheme environment variable. Library lists are DB-backed, but detail/search/trending proxy
TMDB, so they need a real read token in `api/.env.development.local`.

## Conventions

Each package owns a `Makefile` exposing the same targets (`lint`, `vet`, `test`, `all`) so CI
stays uniform. The Go module is rooted inside `api/` (no `go.work`). CI lives in
`.github/workflows/` and is scoped per package via `working-directory`.
