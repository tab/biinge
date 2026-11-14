# Apple TV fixes from device testing

## Goal

Fix ten bugs and rough edges found on a real Apple TV, so the tvOS app looks and behaves as the other two apps already do.

## Why

The tvOS app was built and checked mostly in the simulator.
On a TV, the player does not fill the screen and our subtitle panel cannot be used.
The Person screen cannot scroll back to its top.
Several focus states look broken: the login fields, the episode rows and the home cards that overlap on focus.

## Scope

In:

- The ten items below, on tvOS only
- Changes to shared code under `UI/` or `Core/` when a fix needs them, with iOS and macOS behavior unchanged

Out:

- A Top Shelf extension with the user's own library. The Top Shelf stays a static image
- Any change to iOS screens, and any macOS change beyond the Home hero check
- The Collections tab grid, which already looks right
- New player features beyond the tracks panel we already have
- A share action on Apple TV. The share links feature left it out because tvOS has no share sheet

## Assumptions

- The Top Shelf poster wall is a new image built from movie, series and game posters in the production library.
  The posters come from TMDB and IGDB through the production Biinge API, as the login background's posters do
- AVKit adds its own subtitle and audio buttons. They offer only the stream's CC track and the playing audio track

## How it works

1. The user picks the Biinge icon on the Apple TV home screen and the Top Shelf shows a wall of posters
2. The user signs in and the focused field on the Biinge sign-in and Jellyfin connect forms stays readable and lines up with the other fields
3. On Home, the hero poster has no watched check, and the Collections and Browse Your Library cards keep a gap when focused
4. On a series, the focused episode row uses a glass background with readable text
5. On a Person screen, the user scrolls down to the credits and back up to the photo and biography
6. The list sheet of a movie, series or game shows its portrait poster at full height
7. The player fills the whole TV. Our Audio & Subtitles button, distinct from AVKit's own, opens our panel, and the remote moves through its rows and picks a track

## Acceptance criteria

- **AC1** – The focused text field on the Biinge sign-in form and the Jellyfin connect form keeps its text readable and has the same width and inset as the unfocused fields.
  These two are the only tvOS forms with text fields
- **AC2** – The Top Shelf Image and Top Shelf Image Wide show a poster wall instead of the enlarged app icon
- **AC3** – The player covers the whole screen, and no app content shows around the video
- **AC4** – Our Audio & Subtitles button in the transport bar has an icon distinct from AVKit's subtitle button and opens our panel
- **AC5** – In the Audio & Subtitles panel, the remote moves focus between the audio, subtitle and option rows, and a click selects the focused row
- **AC6** – A focused episode row on the series and season screens uses a glass background, and its title and overview stay readable
- **AC7** – Focused cards in the Home Collections row and the Home Browse Your Library row do not touch or overlap their neighbors
- **AC8** – The Collections tab grid keeps its current spacing and focus look
- **AC9** – On a Person screen, scrolling up from the credits brings the photo and biography back into view, and the header shows when it has focus
- **AC10** – The Home hero poster shows no watched check on Apple TV and on the Mac
- **AC11** – The list sheet shows the portrait poster at full height for a movie, a series and a game
- **AC12** – The selected tab in the top tab bar has no gold tint, on any tab
- **AC13** – The iOS and macOS apps build, and `make lint && make test` pass

## Decisions

- The Top Shelf stays a static image, generated once at full Top Shelf size. The one-off script that builds it stays out of the repo.
  A per-user Top Shelf needs an app extension, so it goes to the backlog
- AVKit's own subtitle and audio buttons stay, because no public tvOS API hides them and keeps our action.
  Our panel stays the place to pick Jellyfin audio tracks and subtitles, so its button gets its own icon
- The watched check goes only from the hero poster, on Apple TV and on the Mac. Posters in rows keep it
- The gold tint is removed from the tvOS tab bar only. The app accent color stays as it is on iOS and macOS

## Details

Device screenshots of each item are in the session that opened this feature. Steps live in [plan.md](plan.md).
