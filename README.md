# biinge

An open-source, self-hosted tracker and player for movies, TV shows and games.
You run the Biinge API next to your Jellyfin server on your own hardware. The
iPhone, Mac and Apple TV apps track your lists and play what the server holds.

<picture>
  <source media="(prefers-color-scheme: dark)" srcset="docs/public/media/readme/devices-dark.webp">
  <img src="docs/public/media/readme/devices-light.webp" alt="Biinge on iPhone, Mac and Apple TV">
</picture>

## Features

- **Track movies, TV shows and games**: want / watching / watched lists, and want / playing / played for games
- **Episode-level progress**: mark individual episodes and seasons, and the show's state follows
- **Up Next**: aired episodes you haven't watched, plus released movies and games, from the titles you pin.
  On iPhone, Jellyfin's Continue Watching and Next Up come first
- **Search & trending**: movies, shows and people from TMDB, games from IGDB
- **Jellyfin playback**: connect a Jellyfin server, then play what it holds on iPhone, Mac and Apple TV, with resume and the next episode
- **Jellyfin sync**: a watched mark or a finished play in the app shows the same state in Jellyfin
- **Statistics**: watch-time totals and a monthly activity chart
- **Pinning & themes**: pin favorites to the top, with dark, light or system appearance

## Repository layout

Monorepo, one deployable unit per top-level directory: `api/` (Go REST API),
`ios/` (SwiftUI app) and `docs/` (Astro site). The API and the app are
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

Or run the API in Docker too: after the migrations, `docker compose up -d api` starts it on :8080.

**2. Run the app** (details in [ios/README.md](ios/README.md)):

```sh
make -C ios build:ios     # or open ios/Biinge.xcodeproj in Xcode 26
```

The app targets `http://localhost:8080/api/v1` by default. Library lists are
DB-backed; detail, search, and trending proxy TMDB, so the API needs a real
TMDB token. See [api/README.md](api/README.md#configuration).

## Conventions

Each package owns a `Makefile` with matching targets (`lint`, `test`, `build`/`check`) so CI stays uniform. 
The Go module is rooted inside `api/` (no `go.work`); CI in `.github/workflows/` is scoped per package via `working-directory`.

## License

MIT. See [LICENSE](LICENSE).
