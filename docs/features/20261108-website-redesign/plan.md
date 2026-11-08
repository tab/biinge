# Website redesign plan

Feature: [feature.md](feature.md)

Status: implemented

Phase: code review

Current step: the PR

## Done when

- `npm run build` in `docs/` passes
- Headless Chrome renders every page at 1440 px and at 390 px, in dark and in light, and each render was looked at.
  The 390 px render loads the page in a 390 px iframe, because headless Chrome will not size a window under 500 px
- A scroll-width probe inside that 390 px iframe shows no horizontal overflow on any page
- A grep of `docs/dist/` and `docs/public/` finds none of the `ios/.env` account names, Jellyfin username or hosts
- Every recording starts after the player's loading state, so the server name it shows never enters a clip
- OCR of every still and of every frame of every final recording finds no text AC11 forbids, and each still was looked at
- Every prototype claim kept on the site traces to `api/` or `ios/` source, or was rewritten or dropped (AC12)
- Seeking recordings to sampled times in headless Chrome shows them looping on screen and paused off screen (AC9)
- A reduced-motion render shows still frames in place of recordings and the hero rotation (AC10)

## Steps

- [x] 1. Prepare the capture account
  - Sign in on production with the `ios/.env` account, add the featured movies, shows and games, and set their states and pins
  - Connect the `ios/.env` Jellyfin user, and pick titles the library holds for the playback shots
- [x] 2. Audit the prototype copy against `api/` and `ios/`, and write the corrected copy for every page
- [x] 3. Capture iPhone stills and recordings in light and dark
- [x] 4. Capture Mac stills and recordings in light and dark
- [x] 5. Capture Apple TV stills and recordings
- [x] 6. Build the site shell: dark default with the theme toggle, header, footer and the recording component
- [x] 7. Build Home from variant 1a, Cinematic
- [x] 8. Build the iPhone, Mac and Apple TV pages
- [x] 9. Build About, move Self-hosting and the API reference onto the new shell, and delete what the old pages leave unused

- [x] 10. Rewrite the site copy in a plain voice: a self-hosted, open-source project, not a streaming service
- [x] 11. Reshoot Apple TV `home` and `continue` uncropped, with the poster clear of the edge
- [x] 12. Drop the panels around captures, and fix the tablet and mobile layouts

## Gates

- [x] Plan review – PASS (round 2, codex gpt-6.1-sol then gpt-6-luna follow-up, high)
- [x] Code review – PASS (round 4, codex gpt-6.1-sol then gpt-6-luna follow-up, high)
