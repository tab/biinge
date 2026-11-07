# ios

SwiftUI client for iPhone, Mac and Apple TV, in Swift 6. See `README.md` for
setup and commands.

## Structure

One target builds all three apps. `Biinge/` is split by layer, then by platform:

- `App/` is the composition root: `BiingeApp` in `App.swift`, `Config`,
  `Monitoring`, `DeviceInfo` and the asset catalog
- `Core/` is logic with no UI import: `Networking/`, `Auth/`, `Models/`,
  `Stores/`, `Jellyfin/`, `Playback/`, `Features/`
- `UI/` is SwiftUI shared between the apps: `Theme/`, `Components/`,
  `SplashView`
- `Resources/` holds the Archivo font, bundled in all three apps
- `Platforms/iOS/`, `Platforms/macOS/` and `Platforms/tvOS/` hold one app's
  views in `App/`, `Navigation/`, `Screens/` and `Components/`. Each platform's
  `*Scenes.swift` supplies `BiingeApp`'s `body`

A build compiles only its own `Platforms/` folder. Per-SDK
`EXCLUDED_SOURCE_FILE_NAMES` settings drop the other two folders, and no file
has a platform filter. The patterns reach three fixed depths. `make lint` runs
`Scripts/check-platform-depth.sh`, which fails on a file directly in
`Platforms/` or more than two folders below a platform folder. A deeper folder
needs one more pattern per excluded platform, in Debug and Release, and a
matching `-mindepth` in the script.

`Biinge/` is a synchronized folder, so a new app file needs no `project.pbxproj`
entry. `BiingeTests/` is not, so a new test file has to be registered there.

### Rules

- No SwiftUI, UIKit or AppKit import under `Core/`
- No `#if os` under `Platforms/`
- Elsewhere `#if os` and `#if canImport` choose a value, such as a size, an
  edge, a font, a duration, a name, an image source or the AppKit and UIKit
  color bridge. They never declare a view, a modifier or a type
- The one exception is the `#if os(iOS)` around the delegate adaptor in
  `App.swift`. The adaptor must be a stored property of the `App` type
- A screen that differs gets its own file under `Platforms/`
- Shared behavior goes in a `Core/Features/` model, and shared SwiftUI in
  `UI/Components/`, rather than into a screen. New logic goes in `Core/` even
  when only one platform uses it, so its tests build everywhere. A small display
  helper private to a screen can stay there

### Naming

- `Mobile*`, `Desktop*` and `TV*` name the iPhone, Mac and Apple TV version of a
  file. The prefix appears only when another platform has a file in the same
  role, or when the bare name clashes with a shared file. `TVBackdropArt` and
  `TVSetupButtonStyle` are the exceptions
- A screen file declares the type it is named for, prefix included. A helper
  type with a platform prefix uses its platform's prefix
- `TV` and `tv` in a name mean Apple TV, never a series. A TV series is a
  `Series`, as in the API. The stored `tvSort` key stays, because renaming it
  resets the saved sort
- Color tokens carry the `biinge` prefix, as in `biingePrimary`. The chart-only
  `dataMovies` and `dataSeries` are the exceptions

### Seams

- `Core/Stores/` (`MovieStore`, `SeriesStore`, `GameStore`) are `@MainActor
  @Observable` classes holding the user's library: want, watching, watched for
  screen media, want, playing, played for games. Anything that changes library
  state goes through a store so every screen sees it. The one exception is
  `Core/Features/Details/DetailsTitle.swift`, which marks an episode through
  `APIClient` and hands the result to `SeriesStore.apply`. `UpNextStore` holds
  the Up Next queue and Jellyfin's rows
- Screens and `Core/Features/` models call `APIClient` directly for read-through
  data the library doesn't own: TMDB and IGDB details, search, trending,
  statistics
- `Core/Networking/APIClient.swift` is the single seam to the API
- Two third-party dependencies, each confined: sentry-cocoa to
  `App/Monitoring.swift`, and jellyfin-sdk-swift (pinned to 3.3.0) to
  `Core/Jellyfin/`. Other code may use the SDK's model types, such as
  `BaseItemDto`, but its calls stay in `Core/Jellyfin/`. Everything else is
  first-party

## The backend contract

`../api/api/swagger.yaml` is the documentation for the API: every path, query
parameter, request body, response shape and status code. Read it before adding
or changing a call in `APIClient`, and match `Core/Models/` to the serializer
shapes it defines. Don't infer a shape from a neighbouring model or from a
response observed at runtime. It's kept current with the API by the same commit
that changes it.

## Configuration

`.env` (gitignored) → `Scripts/inject-env.sh` → the built `Info.plist` →
`Config.swift`. Read hosts and keys from `Config`, never hardcode them in a view
or client. The injection script fails the build when a value set in `.env`
doesn't land, so a misinjected build can't quietly fall back to localhost. With
no `.env`, or a key left unset, the build still succeeds and `Config` uses
localhost for the API URL.

Each platform has its own plist source. `Info.plist` is the Mac app's and adds
the fonts. `Info-iOS.plist` adds the fonts, launch screen and orientation, and
`Info-tvOS.plist` adds the fonts and launch screen. Keep the shared keys
(`API_BASE_URL`, `SENTRY_*`, `NSAppTransportSecurity`) in all three.

`.env` is edited by hand to switch between local and production. No build
configuration switches it, and Debug/Release doesn't either.

## Verification loop

`make lint`, then `make test`, at the end of every change. `make test` runs the
`BiingeTests` target on iOS, macOS and tvOS, one after another, so it needs
Xcode 26 and the iOS 26 and tvOS 26 runtimes. When a simulator isn't available,
say the change is unverified rather than calling it done. The README has the
table of [what runs when](README.md#what-runs-when).

Tests cover `Core/` and the shared value types in `UI/`. macOS is the platform
with no skips. The tests behind `keychainIsFree()` run only there, because
unsigned simulators reject Keychain writes. A Jellyfin connection stored in the
Mac's Keychain skips them too. Apple TV also skips the three Undo tests, because
its toast takes no focus.

The scheme's test action sets `TZ=America/Los_Angeles`, so `make test` and each
`make test:<platform>` run in that zone. `DetailFactsTests` needs a zone behind
UTC to catch a date that slips back a day.

## Jellyfin and AVPlayer

- jellyfin-sdk-swift stays on 3.3.0, because later releases need a newer Swift
  than Xcode 26.0.1 ships. Its `signOut()` revokes the key through an admin-only
  call, so disconnect sends `reportSessionEnded` itself
- Playback info honours the chosen tracks only when `mediaSourceID` is set
- Jellyfin's HLS stream always starts at zero, so the player seeks to the resume
  position itself
- Streams are fMP4 HLS, because Apple's HLS takes HEVC only there. Jellyfin maps
  WebVTT in the manifest to TS time (10 s), which runs 10 s late against fMP4
  video. `enableSubtitlesInManifest` stays off, and the app draws text subtitles
  from their files
- AVPlayer lists only the selected audio track, so the audio picker is ours
- `AVPlayerItem.status`'s KVO async sequence never delivers the change, so
  `PlaybackSession` polls it
- SwiftUI `VideoPlayer` crashes on macOS unless the target links AVKit
  explicitly, so `OTHER_LDFLAGS` names it
- A request with a default script User-Agent can answer 403, wrong password or
  not. Send an explicit one

## Failure classes

Reviews keep finding these three. Check for them in any store or load change.

- **Queued write order and rollback.** Each store runs its writes in submission
  order on `writeChain`, and every new write path joins that queue. A failed
  write gives way to later writes on the same title. The last one restores the
  state the server confirmed (`confirmed`), and the queue resyncs once it
  drains. Series marks carry a per-series generation (`episodeMarks`), so an
  older answer or rollback never overwrites a newer mark
- **Stale responses.** A load that starts more than one way (a task, a refresh,
  Retry, paging) carries a generation, and a superseded load drops its result
  and its error. Paging also checks the offset it asked at. `PagedLibrary`,
  `HomeFeed` and `JellyfinConnection.generation` show the pattern
- **Session-scoped deferred writes.** A write that outlives its screen is bound
  to its session. A pending removal records `sessionsEnded` and carries it into
  `APIClient`, which sends nothing once that session ended. Other queued writes
  have no such check yet (BL-033)

## Live runs

Pass credentials only as launch environment variables. Never print them, and
never write them, a token or a stream URL to a file or a log. On tvOS, prefix
each variable with `SIMCTL_CHILD_` for `xcrun simctl launch`.
`xcrun simctl keychain <device> reset` shuts the simulator down.

After a run against a real Jellyfin server:

- Reset each test item's resume position to 0, and leave it unplayed
- Clear the Jellyfin keys from the Mac and simulator Keychains
- On the Mac, delete `com.biinge.accessToken` and `com.biinge.refreshToken` from
  the login Keychain. Each unsigned rebuild is a new binary to the Keychain, so
  `make test:macos` asks for the password while they exist
