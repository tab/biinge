# iOS code layout by layer and platform

## Goal

The `ios/` app is organized by layer, then by platform.
Shared logic lives in `Core/` and shared SwiftUI in `UI/`.
Each app's screens live in `Platforms/iOS`, `Platforms/macOS` or `Platforms/tvOS`.
Shared behavior lives once in `Core/`, and series naming is the same in `api/` and `ios/`.

## Why

- One target builds iPhone, Mac and Apple TV, so the folders must say where a file runs.
- A behavior coded once per platform drifts.
  List moves with the Jellyfin mirror, series loading, play notes, paging and the connect flow live once in `Core/`.
- Logic stays free of UI, so `Core/` tests build on every platform.
- `TV` means Apple TV, and a TV series is a `Series`, as in the API.
- The User-Agent names the platform, and the Jellyfin device ID survives a reinstall.
- Each app has its own `Info.plist` keys, and the tvOS app has an icon.

## Scope

- The layout and naming rules in [layout.md](layout.md)
- One build setting per platform that excludes the other platforms' folders
- Shared `Core/Features` models for behavior every platform runs
- Shared `UI/Components` for poster artwork, progress bar, pin badge and the Mac details backdrops
- One Apple TV backdrop art view
- One `biinge*` color token set
- Series naming in `api/`, `ios/`, the spec and the API docs page
- The User-Agent, Jellyfin device ID, `Info.plist` and tvOS icon
- `ios/CLAUDE.md` and `ios/README.md` describing the structure

## Acceptance criteria

- **AC1** – Every file under `ios/Biinge/` sits where [layout.md](layout.md) puts it and carries the name it gives
- **AC2** – A platform build compiles only its own `Platforms/` folder. The project has no per-file platform filters
- **AC3** – `make lint` fails when a file under `Platforms/` sits deeper than the exclusion patterns reach
- **AC4** – No file under `Core/` imports SwiftUI, UIKit or AppKit
- **AC5** – No file under `Platforms/` contains `#if os`. Elsewhere `#if os` and `#if canImport` choose a value,
  as [layout.md](layout.md) defines, and never declare a view, a modifier or a type
- **AC6** – List moves, the Jellyfin played mirror and their toasts run through one shared model on all three apps
- **AC7** – Series details state, play notes, paging, the Home load and the connect and login flows each run through one shared model
- **AC8** – Each new shared model has unit tests
- **AC9** – Mac and Apple TV use the shared poster artwork, progress bar and pin badge.
  The copies [layout.md](layout.md) names are gone.
  The Mac details screens use the shared backdrop.
  Apple TV screens share one backdrop art view and keep their own gradients
- **AC10** – No biinge name in `ios/` or `api/` uses `Tv`, `tv` or `Show` for a series.
  The color tokens have one `biinge*` set.
  Names in the API's TMDB client that mirror TMDB's `/tv` API stay, such as `FetchTvDetails`, `TvDetails` and `SearchTv`.
  The stored `tvSort` key stays, because renaming it resets the saved sort
- **AC11** – The API returns `seriesCredits`, `seriesMinutes` and `tmdbSeriesId` in place of `tvCredits`, `tvMinutes` and `tmdbShowId`
- **AC12** – The User-Agent names the platform the app runs on
- **AC13** – The Jellyfin device ID lives in the Keychain, and an existing ID moves there once, unchanged
- **AC14** – The Mac and Apple TV app bundles carry no iPhone-only `Info.plist` keys
- **AC15** – The tvOS app has an app icon and a Top Shelf image
- **AC16** – Apart from AC6, AC7, AC12 to AC15 and the shared components' accepted changes below,
  every screen looks and behaves as before

## Contracts

- `GET /api/v1/people/{id}` returns `seriesCredits`, and the activity buckets of `GET /api/v1/accounts/stats` return `seriesMinutes`.
  `GET /api/v1/series/{id}/season/{seasonNumber}` returns `tmdbSeriesId`. The old keys are removed
- `POST /api/v1/series/{id}/watched` takes `MarkSeriesRequest`. Its wire shape does not change

## Decisions

- One target and no package: nothing else consumes the code, and a folder split is the usual choice at this size
- Folders are excluded per SDK with `EXCLUDED_SOURCE_FILE_NAMES`.
  A `*` does not cross a `/`, so each folder depth gets its own pattern (tested on 2026-11-04)
- Views never branch on platform. A screen that differs gets its own file under `Platforms/`
- When copies differ, the shared model keeps the more correct behavior:
  - the stale-page guard
  - errors with Retry
  - a reload when the Jellyfin connection changes
  - an episode with no air date counts as upcoming
  - the "Also marked played" toast line on every app
  - one wording for each note, with the device name filled in
- Apple TV keeps its toast without Undo
- The API renames its keys in one change with no transition. No released build reads the old keys
- The tvOS icon is a flat image built from the existing 1024 px icon until layered artwork exists
- The Apple TV bundle keeps two keys. Xcode writes `LSRequiresIPhoneOS` itself, and removing `UILaunchScreen` changes the launch
- Look-alikes that differ in pixels stay, because visual changes are out:
  - the Apple TV list pin
  - the Mac episode row and Continue Watching bars
  - the Mac Home hero backdrop
- The shared components bring accepted changes on Mac and Apple TV:
  - VoiceOver labels on pins and progress bars
  - Mac backdrops hidden from VoiceOver
  - a card fill under posters that shows during a poster crossfade and under a transparent image

## Details

- [layout.md](layout.md) holds the full file tree and the naming rules
