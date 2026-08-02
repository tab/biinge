# Biinge iOS

SwiftUI client for [biinge](../README.md) (iOS 26, Swift 6, one dependency —
sentry-cocoa, for crash reporting): login, library, movie/TV detail, search, Up
Next, and a profile with statistics.

## Requirements

- Xcode 26 with the iOS 26 SDK
- A running [Biinge API](../api/README.md) (the app defaults to `http://localhost:8080/api/v1`)
- Optional: [SwiftLint](https://github.com/realm/SwiftLint) for `make lint`

## Configuration

Copy `.env.example` to `.env` (gitignored) and set the values for the build you want:

```sh
cp .env.example .env
```

| Variable                          | Purpose                                                                   |
| --------------------------------- | ------------------------------------------------------------------------- |
| `API_BASE_URL`                    | API base URL — `http://localhost:8080/api/v1` locally; your Mac's LAN IP on a device |
| `SENTRY_DSN` / `SENTRY_ENABLED`   | crash/error reporting (off by default)                                    |

`Scripts/inject-env.sh` runs as the last build phase and writes these into
`Info.plist`; `Config.swift` reads them at runtime. A scheme environment
variable of the same name overrides `.env`, and everything falls back to
localhost when nothing is set.

## Run

Open `Biinge.xcodeproj` in Xcode and run on an iOS 26 simulator, or build from
the CLI:

```sh
make build                                                    # default simulator (iPhone 17 Pro)
make build DESTINATION='platform=iOS Simulator,name=iPhone 17'
```

Library lists are DB-backed, but detail, search, and trending proxy TMDB, so
the API needs a real TMDB token — see [api/README.md](../api/README.md#configuration).

## Development

```sh
make lint     # SwiftLint (skipped if not installed)
make test     # runs the BiingeTests unit tests on the simulator
make clean
```

## Structure

`Biinge/` holds the app sources, grouped by concern: `Auth/`, `Networking/`,
`Models/`, `Stores/`, `Screens/`, `Components/`, `Navigation/`, `Theme/`. The
entry point is `BiingeApp.swift`; runtime configuration lives in `Config.swift`.
