# biinge

Movie & TV tracker. Monorepo, one deployable unit per top-level directory.

| Path   | What                                                                                  |
| ------ | ------------------------------------------------------------------------------------- |
| `api/` | Go backend — Chi, pgx/sqlc, goose, JWT, TMDB. PostgreSQL-backed REST API on `:8080`.  |
| `ios/` | SwiftUI client (iOS 26). _In progress — rebuild of the retired React Native app._     |

The two apps are decoupled by the HTTP contract in `api/api/swagger.yaml`; there is no shared code directory.

## Local development

Start Postgres (and optionally build the API image):

```sh
docker compose up -d database        # Postgres on :5432
make -C api db:migrate               # apply migrations (GO_ENV=development)
```

Run the API from source, or boot everything with readiness checks via [fuku](https://github.com/tab/fuku):

```sh
cd api && GO_ENV=development go run ./cmd/biinge   # http://localhost:8080
# — or —
fuku up                                            # runs the api, waits on /ready
```

Health: `GET /health` · Readiness: `GET /ready` · API base: `/api/v1`.

Real TMDB and JWT secrets go in `api/.env.development.local` (gitignored); the committed
`api/.env.development` holds `SECRET` placeholders.

## Conventions

Each package owns a `Makefile` exposing the same targets (`lint`, `vet`, `test`, `all`) so CI
stays uniform. The Go module is rooted inside `api/` (no `go.work`). CI lives in
`.github/workflows/` and is scoped per package via `working-directory`.
