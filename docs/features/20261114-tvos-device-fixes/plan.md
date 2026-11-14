# Apple TV fixes from device testing plan

Feature: [feature.md](feature.md)

Status: implemented

Phase: pr review

Current step: pull request

Branch: `fix/tvos-device-fixes`

## Done when

- `make lint && make test` pass in `ios/`, and the iOS, macOS and tvOS schemes build
- A tvOS simulator screenshot shows each changed screen: sign-in, connect, Home rows, hero, series episodes, Person, list sheet, tab bar and player
- A focused screenshot of the Collections tab grid matches the current spacing and focus look (AC8)
- When a fix touches `UI/` or `Core/`, an iOS and a macOS screenshot of the screens using it show no change
- The Top Shelf images open at 1920×720, 3840×1440, 2320×720 and 4640×1440 and show a poster wall
- The user confirms AC3, AC4, AC5 and AC12 on the Apple TV

## Steps

- [x] 1. Make the player full screen with one working track picker
  - Find why the player cover leaves app content around the video, and fix it
  - Give our Audio & Subtitles button an icon distinct from AVKit's subtitle button
  - Make the tracks panel take remote focus and select rows
- [x] 2. Restyle the focused field on the Biinge sign-in and Jellyfin connect forms
- [x] 3. Fix the Home screen: no check on the hero poster, and a gap between focused cards in the Collections and Browse Your Library rows
  - Keep the spacing change local to Home, so the Collections grid is unchanged
- [x] 4. Give the focused episode row a glass background with readable text
- [x] 5. Let the Person screen scroll back up to its photo and biography
- [x] 6. Show the portrait poster in the list sheet of a movie or series
- [x] 7. Remove the gold tint from the selected tab
- [x] 8. Generate the Top Shelf poster wall from the production library and replace both Top Shelf image sets
- [x] 9. Run the verification loop, take the simulator screenshots and add the per-user Top Shelf to the backlog
- [x] 10. Remove the watched check from the Mac Home hero poster

## Gates

- [x] Plan review – PASS (standard, round 2, codex)
- [x] Code review – PASS (standard, round 2, codex; CODE-1 accepted by the human as a risk, make test:macos and the Apple TV and Mac checks confirmed by the human)
