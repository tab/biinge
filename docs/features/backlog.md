# Backlog

## Medium

- [ ] **BL-001: `UserRepository` keeps `FindById` and replaces `FindByLogin` and `FindByEmail` with `FindByFilter`**
  - Why: the movies, series and games repositories look rows up through a `FindByFilter(filter)` method. Users should match, so
    one finder shape holds across the repositories. `FindById` stays because a primary-key lookup is its own case
  - Added: 20260920
- [ ] **BL-005: Quitting the Mac or Apple TV app during playback sends the stop report**
  - Why: only Close and Disconnect stop a play session. A quit leaves Jellyfin showing the session and transcoding until it times out
  - Added: 20261031
  - Source: [Jellyfin playback](20261102-jellyfin-playback/feature.md)
- [ ] **BL-006: Check the API's Jellyfin played write live on every app**
  - Why: the apps write biinge and the API writes Jellyfin in the background, and only unit tests and a local server cover it. Check a movie, an episode, a season and a show with and without a connection, and a failed Jellyfin write
  - Added: 20261031
  - Source: [Jellyfin API](20261102-jellyfin-api/feature.md)
- [ ] **BL-007: Show a failed Jellyfin played write**
  - Why: a failed write keeps the biinge mark and only reaches the API's log, so no screen says the two sides differ
  - Added: 20261031
  - Source: [Jellyfin API](20261102-jellyfin-api/feature.md)
- [ ] **BL-008: Check the Mac build's Keychain and sandbox in a signed Release build**
  - Why: the checks ran unsigned. On macOS, "this device only" may need `kSecUseDataProtectionKeychain`, and the Release sandbox settings were never run
  - Added: 20261031
  - Source: [Jellyfin playback](20261102-jellyfin-playback/feature.md)
- [ ] **BL-009: Confirm the iOS workflow runs the macOS and tvOS tests in CI**
  - Why: the test matrix and the "iPhone 17" and `simctl`-resolved Apple TV simulator names on `macos-latest` are not proven until a pull request runs them. Also check the macOS log shows `handleFailureDisconnectsForA401()` passed, not skipped: it skips where the Keychain rejects writes
  - Added: 20261031
  - Source: `.github/workflows/ios.yaml`
- [ ] **BL-010: Keep the Jellyfin connection when biinge restore fails on a network error**
  - Why: a launch with the API unreachable shows the login screen and drops the Jellyfin connection, so it has to be connected again
  - Added: 20261031
  - Source: `ios/Biinge/Core/Auth/AuthManager.swift`
- [ ] **BL-011: Check specials, multi-episode files and HDR media against a live server**
  - Why: the test server has no season 0, no multi-episode files and no HDR, so unit tests are the only evidence for them, and the device profile has no HDR or Dolby Vision conditions
  - Added: 20261031
  - Source: `api/internal/app/services/library.go`, `ios/Biinge/Core/Playback/DeviceProfile+AVPlayer.swift`
- [ ] **BL-020: Pick the Apple TV Home hero by the date a series gained episodes**
  - Why: the hero sorts the recent movies and shows by `dateCreated`, so an old series that gains episodes never leads it, though its Recently Added row sorts shows by `dateLastContentAdded`
  - Added: 20261031
  - Source: [Library and details](20261103-library-and-details/feature.md)
- [ ] **BL-021: Surface a series with new episodes in the Mac Recently Added list and hero**
  - Why: the combined Recently Added list sorts movies and series by `dateCreated`, so an old series that gains episodes never rises, unlike the Apple TV row that sorts shows by `dateLastContentAdded`
  - Added: 20261101
  - Source: [Library and details](20261103-library-and-details/feature.md)
- [ ] **BL-022: Bring the swagger movie shapes to the API**
  - Why: the API returns `state: "none"` for an untracked movie, but `MovieDetailsSerializer` lists only `want` and `watched`. `CreateMovieRequest` names `tmdbId` where the serializer decodes `id`
  - Added: 20261101
  - Source: [Jellyfin API](20261102-jellyfin-api/feature.md)
- [ ] **BL-024: Serialize a user's overlapping Jellyfin connects**
  - Why: two connects for one user that overlap can store a token Jellyfin already revoked, and status then reports connected
    with a dead credential until the next connect. It matters once two devices connect at the same moment
  - Added: 20261101
  - Source: [Jellyfin API](20261102-jellyfin-api/feature.md)
- [ ] **BL-026: Show the account's API Jellyfin connection in Mac and Apple TV Settings**
  - Why: a disconnect on one device clears the API connection for the whole account, so the other devices keep streaming
    while their Watched marks stop reaching Jellyfin, and nothing on screen says so
  - Added: 20261102
  - Source: [Jellyfin playback](20261102-jellyfin-playback/feature.md)

- [ ] **BL-029: The list endpoints don't wait on an unreachable Jellyfin**
  - Why: `GET /movies` and `GET /series` now read the library index. On a cold cache with Jellyfin down, each waits up to
    the 10 s Jellyfin timeout, because a failed index read isn't cached
  - Added: 20261102
  - Source: [Jellyfin API](20261102-jellyfin-api/feature.md)

- [ ] **BL-031: `stopDuringATrackSwitchStopsTheSessionThatStarted` passes only most of the time on tvOS**
  - Why: it races a 100 ms sleep against a 300 ms stream delay on a real AVPlayer, and under load the rate is still 1.0.
    It failed once in about ten tvOS runs on 2026-11-02, on code paths unrelated to the change under test
  - Added: 20261102
  - Source: [Jellyfin playback](20261102-jellyfin-playback/feature.md)

- [ ] **BL-032: One shimmer clock for each skeleton**
  - Why: every `SkeletonBlock` runs its own per-frame `TimelineView`, about 45 on the Apple TV lists skeleton, and they tick
    during the 300 ms hidden window and for cards past the screen edge. One `TimelineView` at the skeleton root would do
  - Added: 20261102
  - Source: [Design and motion](20261103-design-and-motion/feature.md)

- [ ] **BL-033: Every queued store write checks the session that queued it**
  - Why: a deferred removal now skips its DELETE once the session ends, but other queued writes (PATCH, POST) still read the
    current token when they run. A write queued just before a logout could reach the next account
  - Added: 20261102
  - Source: [Design and motion](20261103-design-and-motion/feature.md)

- [ ] **BL-034: A token refresh in flight can't overwrite the next account's tokens**
  - Why: `AuthManager.refreshTokens` stores the refreshed pair without checking the session. If a logout and a new login finish
    while it runs, the old account's tokens replace the new one's
  - Added: 20261102
  - Source: [Design and motion](20261103-design-and-motion/feature.md)

- [ ] **BL-038: A failed game add or move says so in a toast**
  - Why: `GameStore` has no `addFailure`, so only a failed removal reports, while movies and series name the failed add
  - Added: 20261104
  - Source: [iOS layout](20261104-ios-platform-layout/feature.md)

- [ ] **BL-039: A failed first episode or season mark rolls back with no earlier progress**
  - Why: when the mark and the progress read both fail and no snapshot exists, the optimistic mark stays in `progressBySeries`
  - Added: 20261104
  - Source: [iOS layout](20261104-ios-platform-layout/feature.md)

- [ ] **BL-040: A landed mark keeps its Jellyfin mirror when a newer mark overtakes it after a failed add**
  - Why: the overtaken mark applies no answer, so `SeriesDetailsState.setWatched` reads the cleared progress as unwatched
  - Added: 20261104
  - Source: [iOS layout](20261104-ios-platform-layout/feature.md)

- [ ] **BL-042: Make `aSkeletonThatLeavesDuringItsHoldEndsTheHold` and `aRepeatStopWaitsForTheFirstStopsReport` stable**
  - Why: the first failed twice and the second once in about 75 sequential full macOS runs, on code unrelated to the run
  - Added: 20261104
  - Source: [iOS layout](20261104-ios-platform-layout/feature.md)

- [ ] **BL-043: Retry on the iPhone Movie, Game, Episode and Person details errors**
  - Why: `DetailLoadError` offers no action there, so a failed load needs the screen closed and reopened
  - Added: 20261104
  - Source: [iOS layout](20261104-ios-platform-layout/feature.md)

## Low

- [ ] **BL-035: Statistics reads Week and Month as the last 7 and 30 days and shows the change against the previous period**
  - Why: the prototype labels the ranges "Last 7 days", "Last 30 days" and "Since <month year>", with "+17% vs 2025" under
    the total. The API buckets by calendar week and month (`date_trunc`) and returns no previous-period total
  - Added: 20261104
  - Source: [Biinge Profile Stats.dc.html](../../design/prototype/Biinge%20Profile%20Stats.dc.html)
- [ ] **BL-036: Statistics shows Most watched TV Shows and a poster strip on each category card**
  - Why: the prototype ranks the top 5 shows by watch time (poster, time, episodes, bar against #1) and puts recent posters
    under each category card. The stats payload carries neither
  - Added: 20261104
  - Source: [Biinge Profile Stats.dc.html](../../design/prototype/Biinge%20Profile%20Stats.dc.html)
- [ ] **BL-037: The iPhone Profile account card shows "Member since <month year>"**
  - Why: the prototype's account card carries it, but the user payload has no creation date
  - Added: 20261104
  - Source: [Biinge Profile Stats.dc.html](../../design/prototype/Biinge%20Profile%20Stats.dc.html)

- [ ] **BL-041: Mint a Jellyfin device ID only when the Keychain item is truly missing**
  - Why: `Keychain.read` returns nil on any error, so a locked read makes a one-off ID, and `save` deletes before it adds
  - Added: 20261104
  - Source: [iOS layout](20261104-ios-platform-layout/feature.md)

## Done

- [x] **BL-004: Replace the iOS "Login or Register" button label with "Log in"**
  - Why: the button calls the login endpoint, so its current label incorrectly promises account registration.
  - Added: 20261030
  - Source: [MobileLoginView.swift](../../ios/Biinge/Platforms/iOS/Screens/MobileLoginView.swift)
  - Boundary: change the label only; keep authentication behavior and API endpoints unchanged.
- [x] **BL-013: Add next-episode autoplay with the end-of-episode countdown on Apple TV**
  - Why: brief §7.6 asks for a next-episode card with a fixed countdown, Play next and Cancel. The first Apple TV slice ships without it
  - Added: 20261031
  - Source: [Jellyfin playback](20261102-jellyfin-playback/feature.md)
- [x] **BL-014: Add recent searches to Apple TV search**
  - Why: brief §7.7 lists search history. The first Apple TV slice ships search without it
  - Added: 20261031
  - Source: [Library and details](20261103-library-and-details/feature.md)
- [x] **BL-015: Add genre navigation and an unwatched filter to Apple TV Movies**
  - Why: brief §7.3 lists both. The first Apple TV slice ships a plain poster grid
  - Added: 20261031
  - Source: [Library and details](20261103-library-and-details/feature.md)
- [x] **BL-016: Decide whether Apple TV gets a Watched/Unwatched control**
  - Why: the brief rates tracking Low on Apple TV, and a finished play already writes the biinge mark, and the list menu on Apple TV details offers Watched. BL-006 and BL-007 stay open
  - Added: 20261031
  - Source: [Library and details](20261103-library-and-details/feature.md)
- [x] **BL-017: Replace the fixed 3-second sleep in `playingToTheEndStopsTheSession`**
  - Why: it failed once under full CPU load during the Apple TV player review. Waiting on the session's stop instead of a fixed sleep removes the timing dependency
  - Added: 20261031
  - Source: `ios/BiingeTests/PlaybackSessionTests.swift`
- [x] **BL-019: Show a Retry when a later Apple TV or Mac grid page fails to load**
  - Why: after the first page, a failed page is dropped silently. Movies, TV Shows and Collections stop at the loaded items with no connection state, and the tab does not reload. Both apps share `PagedLibrary`
  - Added: 20261031
  - Source: [Library and details](20261103-library-and-details/feature.md)
- [x] **BL-027: Show the resume bar and Play on Mac list posters the library holds**
  - Why: brief §6.1 asks for both on My Lists posters, but `GET /movies` and `GET /series` list items carry no `jellyfinId`,
    so the lists open details for Play instead
  - Added: 20261102
  - Source: [Library and details](20261103-library-and-details/feature.md)
- [x] **BL-028: A pinned movie marked Watched drops its pin**
  - Why: `MovieStore.toggle` keeps `pinned` on a move into Watched, and Watched offers no Unpin. The prototype clears the pin
  - Added: 20261102
  - Source: [Library and details](20261103-library-and-details/feature.md)
- [x] **BL-030: One episode mark method in `SeriesStore` for every series screen**
  - Why: Mac series details, Apple TV series details and the Apple TV episode screen each carry a ~50-line copy of the
    optimistic episode mark with its generation guards. Three copies will drift
  - Added: 20261102
  - Source: [Library and details](20261103-library-and-details/feature.md)
- [x] **BL-025: Reconcile biinge and Jellyfin watched state with a background sync**
  - Why: the API writes Jellyfin in the background and only logs a failure, so a Jellyfin outage leaves the two sides apart
    until the title is marked again. A periodic job in the existing worker could compare and repair them. Which side is the
    source of truth, or whether the sync runs both ways, is still open
  - Added: 20261101
  - Source: [Jellyfin API](20261102-jellyfin-api/feature.md)
  - Delivered: [Jellyfin two-way sync](20261107-jellyfin-two-way-sync/feature.md)

## Won't implement

- [ ] **BL-002: The `webhooks` table gets a retention rule**
  - Why: every accepted Jellyfin event stores its full payload, and marking a long show played sends one event per episode.
    Nothing removes old rows, so the table only grows
  - Added: 20260921
  - Source: 20260920-jellyfin-watched-sync/feature.md
  - Status: Won't do. The webhook and its table are removed ([Jellyfin API](20261102-jellyfin-api/feature.md))
- [ ] **BL-003: The iOS Jellyfin screen learns whether a token exists**
  - Why: the screen has no way to ask, so Revoke always shows, also when there is nothing to revoke
  - Added: 20260921
  - Source: 20260920-jellyfin-watched-sync/feature.md
  - Status: Won't do. The webhook token and the Integrations screen are removed ([Jellyfin API](20261102-jellyfin-api/feature.md))

- [ ] **BL-012: Cache the Jellyfin movie and series lists for matching**
  - Why: each match fetched the whole movie or series list on the device
  - Added: 20261031
  - Status: Won't do. The app no longer matches titles: the API matches with its own index ([Jellyfin API](20261102-jellyfin-api/feature.md))
- [ ] **BL-023: Make `stopDuringATrackSwitchStopsTheSessionThatStarted` stable on tvOS**
  - Why: it failed once in a full tvOS run (the player rate was still 1.0 after the stop) and passed on the rerun, like BL-018
  - Added: 20261101
  - Source: [Jellyfin playback](20261102-jellyfin-playback/feature.md)
  - Status: Won't do. It is the same test as BL-031, which tracks it
- [ ] **BL-018: Make `anAudioSwitchCarriesSubtitlesTurnedOffInThePlayer` stable in full-suite runs**
  - Why: it failed once in a full `make test:ios` run ("subtitleIndex → 3) == -1"), while passing alone. It can fail CI by chance
  - Added: 20261031
  - Source: `ios/BiingeTests/PlaybackSessionTests.swift`
  - Status: Won't do. The test no longer exists
