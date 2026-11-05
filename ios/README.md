# Biinge iOS

SwiftUI client for [biinge](../README.md) on iPhone, Mac and Apple TV (Swift 6):
login, library, movie, series and game details, search, a profile with
statistics, and Jellyfin playback. It has two dependencies: sentry-cocoa for
crash reporting and jellyfin-sdk-swift for Jellyfin.

## Requirements

- Xcode 26 with the SDKs and simulator runtimes for the platforms you run: iOS 26 and tvOS 26
  (the Mac app targets macOS 15.6 and needs no runtime). `make test` and `make build` run all three
- A running [Biinge API](../api/README.md) (the app defaults to `http://localhost:8080/api/v1`)
- Optional: [SwiftLint](https://github.com/realm/SwiftLint), which `make lint` skips when it is not installed

## Configuration

Copy `.env.example` to `.env` (gitignored) and set the values for the build you want:

```sh
cp .env.example .env
```

| Variable                        | Purpose                                                                             |
| ------------------------------- | ----------------------------------------------------------------------------------- |
| `API_BASE_URL`                  | API base URL: `http://localhost:8080/api/v1` locally, your Mac's LAN IP on a device |
| `SENTRY_DSN` / `SENTRY_ENABLED` | crash and error reporting (off by default)                                          |

`Scripts/inject-env.sh` runs as the last build phase and writes these into the
built app's `Info.plist`. `Config.swift` reads them at runtime. A scheme
environment variable of the same name overrides `.env`, and the API URL falls
back to localhost when nothing is set.

Each platform has its own plist source, set per SDK by `INFOPLIST_FILE`:

| File              | Build    | Holds                                                 |
| ----------------- | -------- | ----------------------------------------------------- |
| `Info.plist`      | Mac      | the shared keys and fonts                             |
| `Info-iOS.plist`  | iPhone   | the shared keys, fonts, launch screen and orientation |
| `Info-tvOS.plist` | Apple TV | the shared keys, fonts and the launch screen          |

The shared keys are `API_BASE_URL`, `SENTRY_DSN`, `SENTRY_ENABLED` and
`NSAppTransportSecurity`. Keep them in all three files.

## Run

Open `Biinge.xcodeproj` in Xcode and run on an iOS 26 simulator, or build from
the CLI:

```sh
make build         # iOS, macOS and tvOS, one after another
make build:ios     # one platform (also build:macos, build:tvos)
make build:ios DESTINATION_ios='platform=iOS Simulator,name=iPhone 17'
```

Library lists are DB-backed, but detail, search, and trending proxy TMDB, so
the API needs a real TMDB token. See [api/README.md](../api/README.md#configuration).

## Development

```sh
make lint         # doc comments, the platform depth check, then SwiftLint
make test         # BiingeTests on iOS, macOS and tvOS, one after another
make test:macos   # one platform (also test:ios, test:tvos)
make clean
```

### What runs when

| When                 | What runs                            | Why                                        |
| -------------------- | ------------------------------------ | ------------------------------------------ |
| While working        | `make test:macos`                    | macOS is fastest and has no skips          |
| End of every change  | `make lint && make test`             | the verification loop covers all platforms |
| Before a push (hook) | `make lint && make test:macos`       | macOS is fastest and has no skips          |
| Pull request (CI)    | lint and each platform, one job each | CI can't be skipped                        |

macOS is the platform with no skipped tests. The tests that write to the
Keychain run only there, because unsigned simulators reject Keychain writes.

A new test file has to be registered in `project.pbxproj`, because `BiingeTests/`
is not a synchronized folder. `Biinge/` is, so a new app file needs no entry.

### Debug launch hooks

Debug builds read these environment variables, to drive simulator screenshots.
Release builds ignore them.

- `AUTOLOGIN_EMAIL`, `AUTOLOGIN_PASSWORD`: sign in at launch when no session exists
- `INITIAL_TAB`: tab index to start on (iPhone)
- `DEBUG_STATISTICS=1`: open the Statistics sheet from Profile (iPhone)
- `DEBUG_STATS_PERIOD`: initial Statistics period, a `StatsPeriod` raw value (iPhone)
- `DEBUG_UP_NEXT=1`: open the Up Next sheet (iPhone)
- `DEBUG_MOVIE_ID`, `DEBUG_SERIES_ID`, `DEBUG_GAME_ID`, `DEBUG_PERSON_ID`: open that TMDB or game ID's details from the matching tab or Search (iPhone)
- `DEBUG_EPISODE`: open an episode's details as `seriesID:season:episode` (iPhone)
- `DEBUG_SCROLL_SEASONS=1`: scroll a series' details to its seasons (iPhone)
- `JELLYFIN_USER`, `JELLYFIN_PASSWORD`: prefill the Jellyfin connect form
- `JELLYFIN_AUTOCONNECT`: sign in once the connect form shows
- `JELLYFIN_AUTOPLAY`: search Jellyfin for the term and play the first movie or episode (macOS)

## Structure

One target builds the app for iPhone, Mac and Apple TV. `Biinge/` is split by
layer, then by platform:

| Folder             | Holds                                                                     |
| ------------------ | ------------------------------------------------------------------------- |
| `App/`             | the composition root: `App.swift`, `Config.swift`, monitoring, the assets |
| `Core/`            | logic and models, with no SwiftUI, UIKit or AppKit import                 |
| `UI/`              | SwiftUI shared between the apps                                           |
| `Resources/`       | the bundled Archivo font, for all three apps                              |
| `Platforms/iOS/`   | the iPhone app's views (`Mobile*`)                                        |
| `Platforms/macOS/` | the Mac app's views (`Desktop*`)                                          |
| `Platforms/tvOS/`  | the Apple TV app's views (`TV*`)                                          |

Behavior shared between the apps lives in `Core/Features/` models and shared
SwiftUI in `UI/Components/`, not in a screen. A screen that differs per platform
gets its own file under `Platforms/`.

A build compiles only its own `Platforms/` folder, through per-SDK
`EXCLUDED_SOURCE_FILE_NAMES` settings. Files can sit at most two folders below a
platform folder. `make lint` runs `Scripts/check-platform-depth.sh` to enforce
that. A deeper folder needs one more pattern per excluded platform in those
settings, for Debug and Release, and a matching `-mindepth` in the script.
[CLAUDE.md](CLAUDE.md) holds the full layer and naming rules.

## Jellyfin

All three apps connect to a Jellyfin server and play from it.
After biinge login they read the server address from the API and ask only for
a Jellyfin username and password. The iPhone also connects from Profile.
The Jellyfin device ID lives in the Keychain, so it outlives a disconnect and a
reinstall.

Debug launches can prefill the connect form from the `JELLYFIN_USER` and
`JELLYFIN_PASSWORD` launch environment variables. `JELLYFIN_AUTOCONNECT` also
signs in.
