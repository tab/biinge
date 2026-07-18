# biinge

Movie & TV tracker — keep separate lists of what you want to watch, what
you're watching, and what you've finished, across movies and TV shows.

![screenshots](https://github.com/user-attachments/assets/08474315-74c5-4677-847e-effa783401c3)

## Features

- **Track movies and TV shows** — separate want / watching / watched lists
- **Episode-level progress** — mark individual episodes and seasons; the show's state follows automatically
- **Up Next** — a queue of aired-but-unwatched episodes and released movies from the titles you pin
- **Search & trending** — browse TMDB's catalog of movies, shows, and people
- **Statistics** — watch-time totals and a monthly activity chart
- **Pinning & themes** — pin favorites to the top; dark, light, or system appearance

## Repository layout

Monorepo, one deployable unit per top-level directory. The two apps are
decoupled by the HTTP contract in `api/api/swagger.yaml`; there is no shared
code directory.

## Running the full stack

Bring up the API and its dependencies, then run the app against it.

**1. Start Postgres + Redis and the API** (env setup lives in
[api/README.md](api/README.md#configuration)):

```sh
docker compose up -d database redis                 # Postgres :5432, Redis :6379
make -C api db:migrate                              # apply migrations
cd api && GO_ENV=development go run ./cmd/biinge     # http://localhost:8080
```

Or boot the API with a readiness wait via [fuku](https://github.com/tab/fuku): `fuku up`.

**2. Run the app** (details in [ios/README.md](ios/README.md)):

```sh
make -C ios build     # or open ios/Biinge.xcodeproj in Xcode 26
```

The app targets `http://localhost:8080/api/v1` by default. Library lists are
DB-backed; detail, search, and trending proxy TMDB, so the API needs a real
TMDB token — see [api/README.md](api/README.md#configuration).

## Conventions

Each package owns a `Makefile` with matching targets (`lint`, `test`, `build`/`check`) so CI stays uniform. 
The Go module is rooted inside `api/` (no `go.work`); CI in `.github/workflows/` is scoped per package via `working-directory`.

## License

MIT — see [api/LICENSE](api/LICENSE).
