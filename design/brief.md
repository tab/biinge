# Biinge for iPhone, macOS and Apple TV

## Product and UX design brief

**Document:** Design specification  
**Version:** 1.3  
**Date:** 1 November 2026  
**Project:** Turn Biinge into a Jellyfin media client on iPhone, macOS and Apple TV. All three apps come from one Apple codebase under `ios/`.

**Design deliverable:** A complete set of UI mockups, interaction specifications, navigation structures and end-to-end user flows for all three platforms.

---

## 1. Product overview

Biinge started as a personal movie, TV show and game tracker. It now also plays media from a personal Jellyfin library.

All three apps are Jellyfin media clients. On each one the user can:

- Pick up from Continue Watching and Next Up.
- Navigate seasons and episodes.
- Play media natively and resume from the last position.

macOS and Apple TV also browse the whole Jellyfin library. They have Movies, TV Shows, Collections and Recently Added.
They also show the user's Biinge lists in their own My Lists section.

The iPhone is the existing tracker with Jellyfin playback added. Its tabs stay the same. It keeps its tracking features:

- Want, Watching and Watched lists.
- Episode progress.
- TMDB discovery and search.
- Statistics.
- Games.

The Movies and TV tabs gain a Library view next to the lists. It holds Continue Watching, Recently Added and the whole library.
The iPhone does not get Collections.

Every app keeps lists and the library apart. Lists come from Biinge and can hold titles the server doesn't have.
The library comes from Jellyfin and can hold titles the user never tracked.

Search covers the Biinge catalog in every app: movies, shows and people, whether or not the server has them.

The platforms differ in input and layout:

| Platform | Input                     | Layout                                         |
| -------- | ------------------------- | ---------------------------------------------- |
| iPhone   | Touch                     | Existing tab bar, one column                   |
| macOS    | Keyboard, mouse, trackpad | Sidebar, resizable windows, dense metadata     |
| Apple TV | Siri Remote               | Large artwork, focus-based, minimal text entry |

### Audience and distribution

The apps are for internal use by the owner only. They are installed directly from a Mac to the owner's own devices.
They are not distributed through the App Store.

There is one personal Jellyfin server and one viewing user. Multi-user profiles, public onboarding and account switching are not priorities.

### Out of scope for v1

The owner approved these cuts. They apply to every platform. Do not design them.

- Server discovery and server address entry. The Biinge server supplies the Jellyfin server address.
- Jellyfin Quick Connect. Apple TV uses the on-screen keyboard or the iPhone keyboard.
- The "Who's watching" Jellyfin user picker. The app signs in as the one user.
- The library picker step in setup. The Movies and TV Shows libraries are used by default.
- Skip Intro.
- Shuffle.
- The grid/list toggle.
- Settings for the autoplay countdown and quality.
- An Appearance setting on macOS and Apple TV. The iPhone keeps its Appearance setting.

Autoplay of the next episode stays. It uses a fixed countdown and has no setting.
Default audio and subtitle languages come from the Jellyfin user's preferences.

### Core product priorities

The media experience on macOS and Apple TV should prioritize:

1. Immediate access to the Jellyfin library.
2. Fast discovery and browsing of owned content.
3. Continue watching from the last playback position.
4. Finding the next TV episode.
5. Choosing a movie for an evening.
6. A seamless playback experience.

On the iPhone, Continue Watching, Next Up and playback sit inside the existing tracker.

Tracking features should not dominate the macOS or Apple TV interface.

---

## 2. Existing project context

Repository: [tab/biinge](https://github.com/tab/biinge)

The existing architecture already provides a foundation for the new clients.

| Area                  | Current implementation                                    |
| --------------------- | --------------------------------------------------------- |
| Apple client          | SwiftUI, Swift 6, iOS 26, one codebase under `ios/`       |
| Backend               | Go REST API                                               |
| Backend database      | PostgreSQL                                                |
| Cache                 | Redis                                                     |
| Movie and TV metadata | TMDB                                                      |
| Game metadata         | IGDB                                                      |
| Authentication        | Biinge account with JWT                                   |
| Library tracking      | Want / Watching / Watched                                 |
| TV progress           | Episode-level tracking                                    |
| Jellyfin              | Existing webhook integration; target server 12.3 or later |
| Distribution          | Installed directly from a Mac, no App Store               |

The repository is a monorepo with `api/`, `ios/` and `docs/`.
The iOS app already separates networking, models, stores, navigation, screens and components.

Existing functionality worth understanding and reusing:

- Movie, TV show and game data models.
- TV show and episode progress.
- Poster and image components.
- Theme and typography foundations.
- User authentication.
- Jellyfin integration and account settings.
- Shared API networking concepts.

**Important architectural distinction:** the existing Jellyfin integration is a tracking webhook, not a Jellyfin media client.
It synchronizes watched and unwatched events for titles already tracked in Biinge. It does not provide library browsing or playback.

The design must therefore treat the Jellyfin media library as a new content source.
It should not assume the current integration already supplies these capabilities.

---

## 3. Platform roles and priorities

The three platforms share one product direction. Each one needs its own interaction model.

### iPhone: tracker with Jellyfin playback

The existing iPhone app gains Jellyfin playback inside its tracker.

- **Primary input:** Touch.
- **Experience:** The existing tabs and tracking screens, restyled to match macOS in both light and dark themes.
  Movies and TV add a Library view. Titles on the server get a Play or Resume action.
- **Main goal:** Keep tracking, and watch what the server has without leaving the app.

### macOS: personal media center

A full desktop app for browsing, searching, organizing and watching content.

- **Primary input:** Keyboard, mouse, trackpad.
- **Experience:** Information-rich, efficient navigation, flexible layouts, detailed metadata and integrated video playback.
- **Main goal:** Make the personal media collection easy to explore and use.

### Apple TV: living-room cinema

A visually immersive media browsing and playback app.

- **Primary input:** Siri Remote.
- **Experience:** Large artwork, clear hierarchy, large focus targets, spatial navigation and minimal text input.
- **Main goal:** Let the user find and start watching something with minimal effort.

### Feature priority

| Capability                | iPhone       | macOS        | Apple TV     |
| ------------------------- | -----------: | -----------: | -----------: |
| Biinge login              | Critical     | Critical     | Critical     |
| Jellyfin library browsing | High         | Critical     | Critical     |
| Continue Watching         | Critical     | Critical     | Critical     |
| Next Up                   | Critical     | Critical     | Critical     |
| Movies browsing           | High         | Critical     | Critical     |
| TV shows browsing         | High         | Critical     | Critical     |
| Episode navigation        | Critical     | Critical     | Critical     |
| Video playback            | Critical     | Critical     | Critical     |
| Playback resume           | Critical     | Critical     | Critical     |
| Playback controls         | Critical     | Critical     | Critical     |
| Movie/show details        | Critical     | High         | Medium       |
| Collections               | Not required | High         | High         |
| Recently Added            | High         | High         | High         |
| Biinge lists              | Critical     | Medium       | Medium       |
| Statistics                | High         | Not required | Not required |
| Catalog search and people | High         | High         | High         |
| Games tracking            | High         | Not required | Not required |
| Connection settings       | Medium       | Medium       | Medium       |

On iPhone, "Movies browsing" and "TV shows browsing" mean the Library view in the Movies and TV tabs. The tracked lists stay as they are.

Games stay iPhone-only. Do not introduce games into the macOS or Apple TV navigation unless a future product decision requires it.

---

## 4. Sign-in and connection

Every platform starts with a Biinge login. Jellyfin setup comes after it.

- The login uses an existing Biinge account. There is no sign-up.
- After a successful login, the user signs in to Jellyfin with a username and password. There is no user picker.
- The Biinge server supplies the Jellyfin server address and name. The user never types an address.
- One Jellyfin sign-in links the server to the Biinge account and to this device.
- The app uses the Movies and TV Shows libraries by default. There is no library picker.
- Not Now skips the Jellyfin step. Lists, search, people and details still work. Play and the library need Jellyfin.

The full flows are in section 8.

---

## 5. iPhone application

The iPhone prototype is `design/prototype/Biinge iOS.dc.html`.

### 5.1 Navigation

The existing tabs stay. The prototype keeps Movies, TV, Games and Profile in the tab bar, with Search as the search tab. Up Next opens as a sheet.

One pill control sits at the top of Movies and TV:

- Movies: Want · Watched · Library.
- TV: Want · Watching · Watched · Library.

The first pills are the Biinge lists. Games keeps its own Want · Playing · Played control and has no Library.
There is no Library tab and no Collections.

### 5.2 Library

The Library view shows the Jellyfin library for that tab, top to bottom:

1. Continue Watching.
2. Recently Added.
3. All Movies or All TV Shows, as a poster grid with a sort control.

The rows and the grid come from Jellyfin, so a poster can start Play.
List posters also show resume bars. They come from one Jellyfin resume call, matched by the item's Jellyfin id from Biinge.

Library states:

- Loading.
- Empty: nothing in that library yet. Want and Watched still show the lists.
- Jellyfin not connected: a prompt to connect in Profile.
- Server unreachable: Try Again. Want, Watched and Search still work.

### 5.3 Visual restyle

The app keeps its light and dark themes and its Appearance setting. The prototype shows the dark theme. The light theme needs the same restyle.

The restyle matches macOS:

- A deep neutral background and blurred-poster backdrops.
- Archivo for large titles and section headers, the system font for the rest.
- Pill filters instead of the system segmented control, the same as the macOS library filters and season tabs.
- Poster badges that match macOS: check, progress pie, pin, NEW and a playback bar.
- A glass action sheet.
- The red accent is removed.

### 5.4 Movie and series details

Details show one action row:

- A white Play or Resume pill when Jellyfin has the title.
- Want when Jellyfin does not have it.
- Round glass buttons for Watched and More.

A title that is not on the server shows a note: "Not on <server>. Add it to Jellyfin to play here." `<server>` is the Jellyfin server's name.

A title the server holds more than once is treated as not on the server. It has no Play and shows the same note.

Series details list seasons and episodes. An episode on the server can be played from its details sheet.

### 5.5 Up Next

Up Next leads with Jellyfin Continue Watching cards and Next Up rows, as on macOS Home. The tracked Up Next content follows.
An empty state covers the case with nothing on deck.

### 5.6 Profile

Profile shows:

- The Biinge account.
- The Jellyfin connection, with its status, Reconnect and Disconnect.
- Log Out.

The other existing Profile entries stay as they are, including Appearance.

### 5.7 Search

Search stays the existing catalog search across movies, shows, games and people. A result on the server shows Play in its details.

---

## 6. macOS application

### 6.1 Information architecture

Use a persistent sidebar with a content-focused main area.

The interface should feel like a native macOS app, not a web-based streaming service.

Recommended navigation:

**Library**

- Home
- Movies
- TV Shows
- Collections
- Continue Watching

**My Lists**

- Want to Watch
- Watching
- Watched

**Global**

- Search

**Settings**

- Settings

The sidebar should be collapsible. Each My Lists entry shows its count.

My Lists come from Biinge:

- Want to Watch and Watched have Movies and TV Shows pills and a sort.
- Watching holds TV shows only, because movies have no Watching state.
- A poster the library holds shows its resume bar. A click opens its details, and playback starts from the details, the hover Play or the context menu.
- A title the server doesn't hold opens its details, with no Play.

Home is the default landing page. The user should not need to visit several sections to resume a movie or TV episode.

### 6.2 Home screen

**Highest design priority.**

Home is the most important screen in the macOS app.

It should answer three questions at once:

- What was I watching?
- What is available in my library?
- What should I watch next?

Recommended content hierarchy:

#### 1. Featured hero

A prominent movie or TV show with large backdrop artwork.

Content:

- Title.
- Release year.
- Overview.
- Runtime or number of seasons.
- Genre.
- Play button.
- More information button.

The hero can highlight a recently added title or a pinned title. It should not show content that is unavailable in Jellyfin.

#### 2. Continue Watching

A horizontal row of movies and TV episodes with incomplete playback.

Each card shows:

- Poster or episode artwork.
- Title.
- Season and episode (for TV).
- Playback progress.
- Remaining runtime.
- Resume action.

This row sits near the top and takes priority over general browsing.

#### 3. Next Up

TV episodes available to watch from shows with existing playback history.

Show:

- Series title.
- Season and episode number.
- Episode name.
- Episode thumbnail.
- Duration.

#### 4. Recently Added

Newly added movies and TV shows, sorted by library addition date.

#### 5. Browse Collections

Collections on the Jellyfin server, presented as visually distinct groups.

### 6.3 Movies

The Movies section gives a visual overview of the whole Jellyfin movie library.

Required elements:

- Movie poster grid.
- Title.
- Release year.
- Optional rating.
- Recently added indicator.
- Search and filters.
- Sorting options.

There is no grid/list toggle.

Suggested filters:

- All movies.
- Unwatched.
- Watched.
- Genres.
- Years.
- Collections.

Suggested sorting:

- Recently added.
- Title.
- Release year.
- Runtime.
- Community rating (only where available).

**Interaction:** A click on a movie opens its detail page. Playback starts from the details, the hover Play or the context menu.

Do not overload the grid with metadata. Artwork and title stay the primary visual elements.

### 6.4 TV Shows

The TV Shows section has two navigation levels.

#### Series library

A poster grid of all available series.

#### Series details

A dedicated detail page with:

- Hero artwork and series poster.
- Title, year, genres.
- Description.
- Total seasons.
- Number of episodes.
- Overall watch progress.
- Continue Watching action.
- Season selector.

#### Season and episode browser

Show the episodes of a season.

Each episode shows:

- Episode number.
- Thumbnail.
- Episode title.
- Description.
- Runtime.
- Watched state.
- Playback progress, where applicable.

The user must be able to select any episode and start playback.

The next unwatched episode should be especially easy to find.

### 6.5 Movie and episode details

Movie and TV details should look consistent.

#### Movie detail layout

1. Large cinematic backdrop.
2. Title and year.
3. Play / Resume button.
4. Overview.
5. Runtime and release date.
6. Genres.
7. Rating.
8. Cast and crew.
9. Related content, when available.
10. Watched status.

#### TV detail layout

1. Series backdrop and poster.
2. Series metadata.
3. Continue Watching / Next Episode button.
4. Description.
5. Season navigation.
6. Episode list.
7. Watched progress.
8. Cast and crew.

Playback is the primary action. Other metadata is secondary.

### 6.6 Search

Search covers the Biinge catalog: every movie, show and person, whether or not the server has them.
Results carry no availability badge. The details screen decides Play.

Requirements:

- Global search.
- Instant or debounced results.
- Search across movies, TV shows and people.
- Separate result categories.
- A person page with a bio and filmography.
- Search by title.
- Empty state.
- No-results state.
- Clear search.

Keyboard shortcuts are part of the design:

- `⌘ + F` or `⌘ + K` opens search.
- `Escape` dismisses the search overlay or returns to the previous context.

Explore both a dedicated search page and a lightweight global search overlay.

### 6.7 Collections

Collections make a large personal library more enjoyable to browse.

Examples:

- A genre.
- A director.
- A studio.
- Award winners.
- A holiday theme.
- Personal favorites.

A collection page shows:

- Collection artwork.
- Name.
- Description (if available).
- Number of titles.
- Collection items.

Collections reflect real Jellyfin library data, not invented Biinge categories.

### 6.8 Video player

Playback is a first-class feature. See section 10 for how playback works on all platforms.

Required controls:

- Play / Pause.
- Seek backward and forward.
- Timeline with playback progress.
- Volume.
- Fullscreen.
- Audio track selection.
- Subtitle selection.
- Subtitle style.
- Playback speed.
- Next episode.
- Previous episode.

#### Audio and subtitles

The subtitles button opens one panel with two columns:

- **Audio** lists every track with its language, title and format, such as "Dolby Digital 5.1". The original track is tagged.
- **Subtitles** starts with Off, then groups the tracks by language. Each track says what it holds:
  every line, every line with sound cues, or foreign lines only.
- A subtitle track that fails to load stays in the list with "Couldn't load from the server".

The panel footer holds two controls:

- A "Use for every episode of <series>" switch, shown for episodes. It keeps the chosen tracks for the rest of the series.
- Subtitle Style, with the current values, such as "Medium · Shadow".

#### Subtitle style

Subtitle Style opens inside the same panel, with Back and Reset:

- Size: Small, Medium or Large.
- Weight: Regular or Bold.
- Background: None, Shadow or Box.
- Position: a slider from lower to higher.
- Timing: minus and plus steps, for subtitles that run early or late. "In sync" means no offset.

The style applies to every title.

#### Speed

The speed button shows the current speed and opens a menu: 0.5×, 0.75×, 1× (Normal), 1.25×, 1.5× and 2×.

Additional TV behavior:

- Next episode prompt.
- Automatic next episode playback with a fixed countdown (no setting).
- End-of-episode behavior.

Create mockups for:

1. Windowed playback.
2. Fullscreen playback.
3. Controls visible.
4. Controls hidden.
5. Audio/subtitle selection.
6. Subtitle style.
7. Speed menu.
8. Audio track switch reloading the stream.
9. End-of-episode state.
10. Playback error.

The player interface stays minimal and hides when inactive.

### 6.9 Settings

Settings contain only:

- Connection status.
- Reconnect.
- Disconnect.
- Log out.

There are no playback, language, quality, autoplay or appearance settings. macOS follows the system appearance.
Subtitle style lives in the player (see 6.8), not in Settings.

The first connection has its own flow (see section 8).

---

## 7. Apple TV application

Apple TV is a different interaction environment. It should not be a scaled-down macOS app.

Design it for television viewing distances and Siri Remote navigation.

The main design constraint is focus-based interaction.

Every interactive element needs a clear focused state. The user should always know where the remote selection is.

### 7.1 Navigation structure

Recommended main sections:

- Search.
- Home.
- Movies.
- TV Shows.
- Collections.
- My Lists.
- Settings.

My Lists is one tab with three poster rows from Biinge: Want to Watch, Watching and Watched.
Select opens details, where Play depends on the library. Without Jellyfin, My Lists still works and shows a banner.

Navigation should be simple and predictable.

Avoid deep nested menus and needless confirmation dialogs.

The user should be able to return to Home from any major section without losing their place.

### 7.2 Home screen

**Highest design priority.**

Home prioritizes large artwork and immediate playback.

Recommended hierarchy:

#### 1. Featured content

A cinematic hero banner with backdrop artwork and:

- Title.
- Short description.
- Release year.
- Play / Resume.
- Details.

#### 2. Continue Watching

The most important carousel.

Cards show:

- Large artwork.
- Title.
- Episode information when relevant.
- Progress bar.

Selecting a card opens an immediate Play / Resume action.

#### 3. Next Up

Unwatched episodes from shows the user is watching.

#### 4. Recently Added Movies

A horizontal poster carousel.

#### 5. Recently Added TV Shows

A separate carousel.

#### 6. Collections

Large artwork-based tiles.

#### 7. Browse Movies / Browse TV Shows

An entry point to the complete library.

Home should never feel like an admin dashboard. No statistics, progress tables or tracking controls.

### 7.3 Movies browsing

The Movies section provides:

- A full-screen browsing experience.
- A large poster grid or horizontal rows.
- Genre navigation.
- Recently added.
- Unwatched movies.
- Collections.

A focused movie card visually expands or gets a clear highlight.

The user should be able to browse a large library without opening each movie to see basic information.

### 7.4 TV Shows browsing

The navigation hierarchy:

`TV Shows → Series → Season → Episode`

Series details contain:

- Backdrop and poster.
- Title.
- Overview.
- Seasons.
- Continue Watching.
- Next Episode.

Season screen:

- Season selector.
- Episode cards.
- Watched indicators.
- Episode runtime.

Episode details show:

- Episode title.
- Description.
- Number.
- Runtime.
- Play / Resume action.

The next episode should be very easy to find.

### 7.5 Movie details

Required content:

- Cinematic backdrop.
- Movie title.
- Release year.
- Runtime.
- Genres.
- Rating.
- Overview.
- Primary Play button.
- Additional information.

Avoid excessive metadata. The user should not need to read much before starting playback.

### 7.6 TV episode playback

Playback controls:

- Play / Pause.
- Seek backward / forward.
- Progress timeline.
- Audio selection.
- Subtitle selection.
- Subtitle style, as on macOS (see 6.8).
- Next episode.
- Return to episode details.

The controls adapt to Siri Remote interaction.

The end-of-episode experience shows:

- Next episode artwork.
- Episode title.
- A fixed countdown to automatic playback.
- Play next episode.
- Cancel autoplay.

The countdown has no setting.

### 7.7 Apple TV search

Search should avoid needless typing.

Requirements:

- Search from the main navigation.
- On-screen keyboard.
- Search history or recent searches.
- The Biinge catalog, as on macOS.
- Results grouped by Movies, TV Shows and People.
- Clear search.
- Empty and no-results states.

Voice search through the Siri Remote can be explored as an enhancement. The first design should not depend on it.

### 7.8 Settings

Settings are simple and remote-friendly. They contain only:

- Connection status.
- Reconnect.
- Disconnect.
- Log out.

Apple TV follows the system appearance. There is no Appearance setting.

---

## 8. Complete user flows

Design complete journeys, not isolated screens.

The following flows define the required mockup scope. Flows marked "all platforms" apply to iPhone, macOS and Apple TV.

### 8.1 Initial setup: iPhone and macOS

**Critical flow**

1. Launch Biinge.
2. Show the Biinge login screen.
3. Enter the email and password of an existing Biinge account.
4. If login fails, show an error and allow retry.
5. After login, show Connect Jellyfin with the server name from Biinge, a username and a password.
6. Connect, or choose Not Now to open the app with lists and search only.
7. If the server is unreachable, show an error with Try Again and Not Now.
8. If sign-in fails, return to Connect Jellyfin with an inline error.
9. Load the Movies and TV Shows libraries.
10. Open Home on macOS, or the existing tabs on iPhone.

On iPhone, an existing user is already logged in. They connect from Profile, in a Connect Jellyfin sheet.

The login screen has no sign-up option. Setup has no server discovery, address entry, user picker or library picker.

Mockup requirements:

1. Biinge login.
2. Biinge login error.
3. Connect Jellyfin.
4. Connecting state.
5. Server unreachable.
6. Jellyfin sign-in error.
7. Loading library.
8. Not Now: the app without Jellyfin.
9. First successful Home screen (macOS).

### 8.2 Initial setup: Apple TV

**Critical flow**

1. Launch Biinge.
2. Show the Biinge login screen.
3. Log in with an existing Biinge account.
4. If login fails, show an error and allow retry.
5. Show Connect Jellyfin with the server name from Biinge, a username and a password.
6. Connect, or choose Not Now to open the app with My Lists and search only.
7. If the server is unreachable, show an error with Try Again and Not Now.
8. Load the Movies and TV Shows libraries.
9. Open Home.

Text entry uses the on-screen keyboard or the iPhone keyboard. There is no Quick Connect, QR code or device-based authorization.

### 8.3 Resume a movie: all platforms

**Critical flow**

1. Open Home (Up Next on iPhone).
2. Go to Continue Watching.
3. Select a movie.
4. Show movie details or a Resume action.
5. Start playback.
6. Play from the last position.
7. Show playback controls when requested.
8. Allow pause, resume and seek.
9. Exit playback.
10. Return to the previous screen.
11. Show the updated Continue Watching state.

Expected behavior:

- Resume at the last playback position.
- Start from the beginning when the content is not partially watched.
- Update progress during playback.
- Reflect completed playback correctly.
- Preserve the playback position when the user exits unexpectedly, subject to Jellyfin's playback reporting.

### 8.4 Start a new movie: macOS and Apple TV

1. Open Home.
2. Open Movies.
3. Browse, filter or sort.
4. Select a movie.
5. Open movie details.
6. Select Play.
7. Start playback.
8. Finish or exit.

Other entry points:

- Recently Added.
- Collections.
- Search results.
- Featured content.

### 8.5 Play a title: iPhone

1. Open a movie or show from a tracked list, Up Next or Search.
2. Open its details.
3. If Jellyfin has the title, select the Play or Resume pill and start playback.
4. If Jellyfin does not have it, show Want and the "Not on <server>" note.

### 8.6 Continue a TV show

**Critical flow**

1. Open Home (Up Next on iPhone).
2. Open Continue Watching or Next Up.
3. Select an episode.
4. Show episode information.
5. Select Resume or Play.
6. Start playback.
7. If the episode is not finished, save playback progress and allow exit.
8. If the episode finishes, show the next episode with a fixed countdown.
9. When the countdown ends, play the next episode.
10. If the user cancels autoplay, show play or return actions.

### 8.7 Browse a TV series

1. Open TV Shows (the TV tab on iPhone).
2. Browse the series.
3. Select a series.
4. Open series details.
5. Choose a season.
6. Open the episode list.
7. Select an episode.
8. Show episode details.
9. Play the episode.

### 8.8 Search for content

1. Open Search.
2. Enter a query.
3. Show search results.
4. If there are no results, show a no-results state and allow query editing.
5. If there are results, select a movie, show or person.
6. Open details.
7. Select Play or Resume.

Search covers the Biinge catalog on every platform. The iPhone also searches games.
Play appears only on the details of a title the server holds once.

### 8.9 Change audio or subtitles

1. Open playback controls.
2. Open the audio and subtitles panel.
3. Select an audio track.
4. Select a subtitle track. The change applies at once.
5. Optionally keep the tracks for every episode of the series.
6. Optionally open Subtitle Style and change the size, weight, background, position or timing.
7. Return to playback.

The default tracks follow the Jellyfin user's language preferences.

Switching the audio track may briefly reload the stream (see section 10). Design a short loading state that keeps the playback position visible.

### 8.10 Reconnect, disconnect or log out

1. Open Settings (Profile on iPhone).
2. See the connection status.
3. Select Reconnect, Disconnect or Log out.
4. Reconnect retries the current server.
5. Disconnect asks for confirmation, then returns to Jellyfin setup. The user stays logged in to Biinge.
6. Log out returns to the Biinge login screen.

### 8.11 Error and recovery scenarios

These must be covered in the design, not left to implementation.

| Scenario                       | Expected experience                             |
| ------------------------------ | ----------------------------------------------- |
| Biinge login failure           | Explain the credentials problem and allow retry |
| Server unavailable             | Clear connection error and retry                |
| Server offline during browsing | Connection state with retry                     |
| Jellyfin sign-in failure       | Explain the credentials or access problem       |
| Session expired                | Re-authentication                               |
| Library empty                  | Empty state with setup guidance                 |
| No matching content            | Search no-results state                         |
| Title not on server            | No Play; Want, Watched and the "Not on" note    |
| Title on server twice          | Same as not on server                           |
| Jellyfin not connected         | Lists work; Play and the library ask to connect |
| Media unavailable              | Playback error with return action               |
| Playback interrupted           | Recoverable interruption and retry              |
| Unsupported format             | Explain the playback compatibility issue        |
| Audio unavailable              | Show available audio options                    |
| Subtitle unavailable           | Allow playback without subtitles                |
| Network interruption           | Retry or reconnect                              |
| Missing artwork                | Consistent placeholder artwork                  |

---

## 9. Design system and visual direction

### 9.1 General direction

Biinge keeps one brand identity across all three platforms. Layout and interaction decisions differ per platform.

The media screens should feel cinematic on every platform.

Recommended direction:

- Cinematic visual language in both light and dark themes.
- High-quality artwork as the primary visual asset.
- Strong typography and clear hierarchy.
- Restrained use of accent colors.
- Few unnecessary borders and containers.
- Subtle transitions and animation.
- Consistent spacing and corner radii.
- High contrast for active and focused states.

Avoid:

- Generic Netflix clones.
- Excessive gradients.
- Too many colorful badges.
- Dense metadata cards.
- Excessive glass effects.
- Phone card layouts stretched across desktop screens.

### 9.2 Colors

Start from the existing Biinge theme rather than inventing a new visual identity.

Explore:

- Deep neutral background.
- Slightly lighter secondary surfaces.
- Neutral borders.
- Light primary typography.
- Muted secondary typography.
- A restrained Biinge accent color.

The palette above describes the dark theme. The light theme needs its own values from the same tokens. The iPhone's red accent is removed.

Themes per platform:

- The iPhone keeps both light and dark themes and its Appearance setting in Profile. Both themes get the restyle.
- macOS and Apple TV follow the system appearance, with no Appearance setting.
- Light and dark themes are both in v1 scope on every platform.
- The current prototypes show only the dark theme.
  Design a light variant of every screen, including blurred poster backdrops, glass and focus effects.
- All screens use the shared color tokens, not hard-coded dark values.

### 9.3 Typography

Use native Apple typography conventions.

**iPhone:**

- Archivo for large titles and section headers.
- The system font for the rest.
- Dynamic Type support.

**macOS:**

- Clear heading hierarchy.
- Compact metadata.
- Comfortable reading sizes.
- Native system typography.

**Apple TV:**

- Larger titles.
- Larger body text.
- Strong contrast.
- Low text density.
- Readable at typical television viewing distances.

### 9.4 Artwork and imagery

Artwork is central to the experience.

Create components and layouts that support:

- Movie posters.
- TV series posters.
- Episode thumbnails.
- Wide cinematic backdrops.
- Collection artwork.
- Featured hero imagery.
- Missing artwork placeholders.

The apps must handle varying artwork proportions and missing images without breaking visual consistency.

---

## 10. Playback

Playback is native AVPlayer and AVKit on all three platforms.

The library is mostly MKV files:

- H.264 video.
- Several DTS 5.1 audio tracks.
- SRT subtitles.

AVPlayer cannot play these files directly. Jellyfin remuxes them to HLS and converts the audio.

What this means for the design:

- Switching the audio track may briefly reload the stream. Show a short loading state, not an error.
- The playback position should survive the reload.
- Startup can take a moment while Jellyfin prepares the stream. Design a loading state for it.
- The "Unsupported format" error stays, for media Jellyfin cannot serve in a playable form.
- Default audio and subtitle languages come from the Jellyfin user's preferences.
- There is no quality setting. Every player has the same audio and subtitles panel and subtitle style (see 6.8), adapted to its input.
- macOS and iPhone have the speed menu (see 6.8).
- The audio picker is Biinge's own. AVPlayer's menu lists only the selected audio track of a Jellyfin stream.

---

## 11. Platform interaction guidelines

| Interaction     | iPhone                  | macOS                   | Apple TV              |
| --------------- | ----------------------- | ----------------------- | --------------------- |
| Main navigation | Existing tab bar        | Sidebar                 | Top navigation / tabs |
| Selection       | Tap                     | Click                   | Focus and Select      |
| Search          | On-screen keyboard      | Keyboard                | On-screen keyboard    |
| Details         | Pushed full-screen page | Page / split view       | Full-screen detail    |
| Browsing        | Lists and Library pills | Poster grid             | Large poster rows     |
| Playback        | Touch                   | Keyboard and pointer    | Siri Remote           |
| Context actions | Glass action sheet      | Context menu            | Focus-based actions   |
| Back navigation | Back button / swipe     | Back button / shortcuts | Remote Back           |
| Focus indicator | None (touch)            | Hover / selection       | Prominent focus state |

### iPhone-specific interactions

Design for:

- Touch targets of at least 44 points.
- Portrait browsing.
- Landscape and fullscreen playback.
- Standard back swipe.

### macOS-specific interactions

Design for:

- Keyboard shortcuts.
- Window resizing.
- Sidebar collapse.
- Context menus.
- Fullscreen.
- Native window controls.
- Multiple windows or scenes, where appropriate.

### Apple TV-specific interactions

Design for:

- Clear focus indicators.
- Predictable directional navigation.
- Focus transitions between rows.
- Large selection targets.
- Minimal keyboard input.
- Remote Back behavior.
- Focus preservation when returning to a previous screen.

The Apple TV design must never depend on hover.

---

## 12. Shared product behavior

The three apps should feel like one product.

### 12.1 Jellyfin is the source of truth for playback

Jellyfin owns:

- Available media.
- Media availability.
- Playback sessions.
- Playback position.
- Jellyfin's played state.
- Media streams.
- Audio and subtitle tracks.
- Default audio and subtitle languages.
- Library organization.
- Collections.

Biinge presents this information consistently.

### 12.2 TMDB remains a metadata source

TMDB can enrich movie and TV information:

- Cast.
- Crew.
- Release dates.
- Genres.
- Descriptions.
- Ratings.
- Posters and backdrops.

A title being in TMDB does not mean it is available to watch.

The library screens on every platform show only playable Jellyfin items.

Lists, search and people show catalog titles whether or not the server has them.
Their details mark the difference with the Play or Want action and the "Not on <server>" note.

### 12.3 Biinge tracking remains separate

Biinge has its own tracking model:

| Content  | States                    |
| -------- | ------------------------- |
| Movies   | Want / Watched            |
| TV Shows | Want / Watching / Watched |
| Games    | Want / Playing / Played   |

These are Biinge tracking states. They are not interchangeable with Jellyfin playback state.

Want is a Biinge-only action. It never writes to Jellyfin.

For example:

- A movie may be on the Biinge Want list but not yet in Jellyfin.
- A movie may exist in Jellyfin without being tracked in Biinge.
- A movie may be partially watched in Jellyfin but not yet marked Watched in Biinge.

This matters most on the iPhone, where tracking and playback live on the same details screen. A title may show both states.
Keep them visually distinct.

### 12.4 Watched and Unwatched

Watched and Unwatched mean the same thing in every app: iPhone, macOS and Apple TV.

- The action always writes the Biinge mark.
- While a Jellyfin server is connected, it also writes Jellyfin's played state.
- Without a connection, it writes the Biinge mark only.
- The Biinge API writes Jellyfin in the background. A failed Jellyfin write keeps the Biinge mark and shows nothing in the app.

Design one Watched control that behaves the same on every platform.

Watched state shows in two places, and each reads its own source:

- Lists, details and the Watched action use the Biinge mark.
- Library grids show the Biinge status in the check badge. The Watched and Unwatched filters stay Jellyfin's played state.
  Jellyfin returns it with each library page, and it covers library titles the user never tracked.

The Watched action writes both, so they agree for every mark made in the apps. A title marked before Jellyfin was connected can differ.

### 12.5 Playback progress synchronization

Playback progress should match across devices.

Example:

1. Start a TV episode on Apple TV.
2. Pause halfway through.
3. Open Biinge on the iPhone or Mac.
4. Find the same episode in Continue Watching.
5. Resume from about the same position.

Jellyfin is responsible for playback state and synchronization, subject to its session reporting and server behavior.

---

## 13. Required screen inventory

This section is the concrete design scope.

Produce mockups for every required screen and its essential states.

### iPhone screens

I01 to I14 match the screens in the iPhone prototype. I15 onwards are not in the prototype yet.

| ID  | Screen                                     | Priority |
| --- | ------------------------------------------ | -------- |
| I01 | Movies, Want list                          | High     |
| I02 | TV, Watching list                          | High     |
| I03 | Games, Playing list                        | Medium   |
| I04 | Movie details, on server                   | Critical |
| I05 | Movie details, not on server               | Critical |
| I06 | Series details, seasons and episodes       | Critical |
| I07 | Episode details sheet                      | High     |
| I08 | Action sheet                               | High     |
| I09 | Up Next with Continue Watching and Next Up | Critical |
| I10 | Search, trending                           | High     |
| I11 | Search, no results                         | High     |
| I12 | Profile with account, connection, Log Out  | Critical |
| I13 | Empty tracked list                         | Medium   |
| I14 | Up Next, empty                             | Medium   |
| I15 | Biinge login                               | Critical |
| I16 | Jellyfin connection and sign-in            | Critical |
| I17 | Connection error                           | High     |
| I18 | Video player                               | Critical |
| I19 | Audio/subtitle selection                   | Critical |
| I20 | Next episode prompt                        | High     |
| I21 | Playback error                             | High     |

### macOS screens

| ID  | Screen                     | Priority |
| --- | -------------------------- | -------- |
| M01 | Biinge login               | Critical |
| M02 | Jellyfin connection start  | Critical |
| M03 | Server connection          | Critical |
| M04 | Jellyfin sign-in           | Critical |
| M05 | Home                       | Critical |
| M06 | Movies library             | Critical |
| M07 | Movie details              | Critical |
| M08 | TV shows library           | Critical |
| M09 | TV series details          | Critical |
| M10 | Season details             | Critical |
| M11 | Episode details            | High     |
| M12 | Search                     | High     |
| M13 | Search results             | High     |
| M14 | Collections                | High     |
| M15 | Collection details         | Medium   |
| M16 | Continue Watching          | Critical |
| M17 | Video player, windowed     | Critical |
| M18 | Video player, fullscreen   | Critical |
| M19 | Audio/subtitle selection   | Critical |
| M20 | Next episode prompt        | High     |
| M21 | Settings                   | High     |
| M22 | Connection error           | High     |
| M23 | Empty library / no results | High     |
| M24 | Playback error             | High     |

### Apple TV screens

| ID  | Screen                     | Priority |
| --- | -------------------------- | -------- |
| T01 | Biinge login               | Critical |
| T02 | Jellyfin connection start  | Critical |
| T03 | Server connection          | Critical |
| T04 | Jellyfin sign-in           | Critical |
| T05 | Home                       | Critical |
| T06 | Movies library             | Critical |
| T07 | Movie details              | Critical |
| T08 | TV shows library           | Critical |
| T09 | TV series details          | Critical |
| T10 | Season selection           | Critical |
| T11 | Episode details            | High     |
| T12 | Search                     | High     |
| T13 | Search results             | High     |
| T14 | Collections                | High     |
| T15 | Collection details         | Medium   |
| T16 | Continue Watching          | Critical |
| T17 | Video player               | Critical |
| T18 | Playback controls          | Critical |
| T19 | Audio/subtitle selection   | Critical |
| T20 | Next episode prompt        | High     |
| T21 | Settings                   | High     |
| T22 | Server connection error    | High     |
| T23 | Empty library / no results | High     |
| T24 | Playback error             | High     |

This is the screen inventory, not a demand for 69 independent visual designs.
Use reusable components, templates and shared states wherever appropriate.

---

## 14. Core components to design

Create this component library alongside the screens.

| Component               | Description                                 |
| ----------------------- | ------------------------------------------- |
| Movie poster card       | Poster, title, year, optional progress      |
| TV show card            | Poster, title, year, progress               |
| Episode card            | Thumbnail, episode information, progress    |
| Collection card         | Artwork and collection title                |
| Hero banner             | Backdrop, title, description, actions       |
| Continue Watching card  | Artwork and resume progress                 |
| Progress bar            | Playback progress                           |
| Poster badges           | Check, progress pie, pin, NEW, playback bar |
| Metadata row            | Year, genre, runtime, rating                |
| Primary action          | Play / Resume (white pill on iPhone)        |
| Secondary action        | Details / More information                  |
| Availability note       | "Not on <server>" note on iPhone details    |
| Search field            | Text input and query                        |
| Pill filter             | Genre, year, watched status, season tabs    |
| Season selector         | Season navigation                           |
| Focused card            | Apple TV remote-selected state              |
| Playback control bar    | Video controls and timeline                 |
| Audio/subtitle selector | Available streams                           |
| Stream reload indicator | Brief loading after an audio track switch   |
| Connection status       | Server health, Reconnect, Disconnect        |
| Glass action sheet      | iPhone title actions                        |
| Loading placeholder     | Artwork and content loading                 |
| Empty state             | No data or unavailable content              |
| Error state             | Connection and playback failure             |

The visual language is shared across platforms. Individual components may need native implementations.

---

## 15. What the designer delivers

The output is not just a set of static screens.

It is a complete design package that can be handed to engineering.

### Deliverable A: information architecture

A navigation map for iPhone, macOS and Apple TV.

Include:

- Main navigation.
- Nested navigation.
- Screen hierarchy.
- Back navigation.
- Entry points into playback.

### Deliverable B: low-fidelity wireframes

Wireframes for all critical screens.

Focus on:

- Content hierarchy.
- Layout.
- Navigation.
- Interaction.
- Screen states.

Do not invest in visual polish before the structure is validated.

### Deliverable C: high-fidelity UI mockups

Polished designs for:

- Biinge login (each platform).
- iPhone Up Next.
- iPhone Movie Details, on and not on the server.
- iPhone Series Details.
- iPhone Profile.
- iPhone Video Player.
- macOS Home.
- macOS Movies.
- macOS Movie Details.
- macOS TV Shows.
- macOS TV Details.
- macOS Video Player.
- Apple TV Home.
- Apple TV Movies.
- Apple TV Movie Details.
- Apple TV TV Shows.
- Apple TV TV Details.
- Apple TV Playback.

These set the visual language for the remaining screens.

### Deliverable D: interactive prototypes

The prototypes demonstrate all critical flows.

**iPhone**

1. Log in to Biinge.
2. Connect Jellyfin.
3. Resume from Continue Watching in Up Next.
4. Open a title on the server and play it.
5. Open a title not on the server and add it to Want.
6. Browse a series and play an episode.
7. Start the next episode.
8. Change audio/subtitles.
9. Disconnect or log out from Profile.

**macOS**

1. Log in to Biinge.
2. Connect Jellyfin.
3. Browse movies.
4. Start a movie.
5. Resume a movie.
6. Browse TV shows.
7. Select an episode.
8. Continue watching.
9. Change audio/subtitles.
10. Complete an episode and continue to the next one.
11. Search the library.

**Apple TV**

1. Initial setup, starting with the Biinge login.
2. Browse the Home screen.
3. Navigate the movie library with Siri Remote focus.
4. Open movie details.
5. Start playback.
6. Resume playback.
7. Browse TV episodes.
8. Start the next episode.
9. Select subtitles.
10. Search.
11. Recover from a connection error.

### Deliverable E: interaction specifications

For every interactive element, specify:

- Default state.
- Focused / selected state.
- Hover state (macOS where applicable).
- Pressed state.
- Disabled state.
- Loading state.
- Error state.
- Navigation destination.
- Result of the interaction.

### Deliverable F: design handoff

Include:

- Design tokens.
- Typography.
- Colors.
- Spacing.
- Artwork dimensions and aspect ratios.
- Component variants.
- Focus and navigation behavior.
- Responsive behavior for iPhone sizes and macOS window sizes.
- Annotated interaction flows.

---

## 16. Recommended design workflow

Split the design into four phases.

### Phase 1: product architecture and wireframes

Define the navigation structures and screen layouts for all three platforms.

Check that each layout suits its input model and that all essential journeys are covered.

**Output:** Information architecture, screen maps, low-fidelity wireframes.

### Phase 2: visual direction

Establish the visual identity across iPhone, macOS and Apple TV.

Start with Home, Movies, Details, TV Shows and Playback.

**Output:** Design system and high-fidelity key screens.

### Phase 3: complete flows

Extend the visual system to every required screen and state.

Complete login, Jellyfin connection, browsing, playback, search and error flows.

**Output:** Complete interactive prototypes.

### Phase 4: engineering handoff

Document component behavior and interactions. Include Apple TV focus navigation and macOS keyboard shortcuts.

**Output:** Final design package ready for implementation.

---

## 17. Open technical and product questions

Design and engineering must align on these before the final implementation.

They do not block initial wireframes. They do affect the final interaction design.

| Question                                   | Design implication       |
| ------------------------------------------ | ------------------------ |
| How are playback sessions reported?        | Progress synchronization |
| Are collections exposed by Jellyfin?       | Collections screen       |

Settled since version 1.0:

- One Jellyfin server and one viewing user, with no user picker.
- Target Jellyfin server 12.3 or later.
- Native AVPlayer/AVKit playback, with Jellyfin remuxing MKV files to HLS and converting the audio.
- The Movies and TV Shows libraries are used by default, with no library picker.
- No device-based authentication, Quick Connect or QR code. Apple TV uses the on-screen or iPhone keyboard.
- No Skip Intro, so intro markers do not matter for v1.
- The iPhone keeps its existing tabs. Movies and TV add a Library view, and details add playback.
- Lists and the library stay apart on every platform. macOS shows lists in the sidebar, and Apple TV in a My Lists tab.
- Search covers the Biinge catalog on every platform.
- The Biinge server supplies the Jellyfin server address. One Jellyfin sign-in links it to the account and the device.
- Biinge matches a title to the library by TMDB id, and an episode by season and episode number. No match or two matches means no Play.

**Architectural recommendation:** keep the existing Biinge API as the app-facing backend.
The new apps should not each implement all Biinge functionality and account integration on their own.
A dedicated Jellyfin client or integration layer can expose the library and playback data while the tracking API stays as it is.

There is also an important security distinction. The existing Jellyfin webhook token is only for incoming watched-state events.
It is not a Jellyfin login credential and must not be reused for client authentication.

---

## 18. Final product direction

**Biinge: your personal media library.**

One product. Three platforms. One media client, shaped by each platform's input and screen.

- **iPhone:** Track, discover and play.
- **macOS:** Browse and watch.
- **Apple TV:** Relax and watch.

### Recommendation for the first design iteration

Do not mock up every screen at once.

Start with seven screens:

1. macOS Home.
2. macOS Movie Details.
3. macOS TV Series / Episode Browser.
4. macOS Video Player.
5. Apple TV Home.
6. Apple TV Movie Details.
7. iPhone Up Next.

These screens settle most of the important design decisions: artwork, content hierarchy, navigation, playback actions and how each platform's input shapes the layout.

Once they are approved, develop the remaining screens and flows against the established visual system.

**The most important outcome:** Biinge should feel native on each device.
It should be a personal media center on the Mac, a cinematic experience on Apple TV and a tracker that can play on the iPhone.
It should never be one platform's layout stretched to fit another screen.
