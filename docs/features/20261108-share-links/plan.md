# Share links plan

Feature: [feature.md](feature.md)

Status: implemented

Phase: pr review

Current step: PR (AC11 chat-app preview checked by a human after deploy)

## Done when

- `make check` and `make drift` pass in `api/` on the committed steps
- `make lint && make test` passes in `ios/`
- `npm run build` passes in `docs/`
- A share created through the API opens as a page at phone and desktop widths, checked by screenshot
- Movie, series and game pages at phone and desktop widths, in light and dark, match the apps' Details layout by screenshot
- A share with `visited_at` moved back 31 days returns the not-found page, and the cleanup deletes it
- A human pastes a link into a chat app and sees the preview with poster and title (AC11)
- A human shares a title from iPhone and Mac, and the link opens the page (AC22)

## Steps

- [x] 1. API: the `shares` migration, the schema dump, the sqlc queries and the repository with its mock
- [x] 2. API: `POST /api/v1/shares` with the provider check, the upsert and the `url` from `SHARE_URL`, plus the spec
- [x] 3. API: the public page per type, the not-found page, the visit write, the cache header and the IP rate limit
  - The template carries the Open Graph tags, the provider credit and the inline Share button script
- [x] 4. API: the periodic cleanup of expired shares
- [x] 5. Config and docs: `SHARE_URL` in the env templates and the CLAUDE.md hosts table, and the endpoint on the API docs page
- [x] 6. iOS core: the share request and the Share button state, with the error path
- [x] 7. iPhone and Mac: the Share button on movie, series and game details
- [x] 8. Coverage pass on the new API and core code
- [x] 9. Docs pass
- [x] 10. API: the share page redesign (AC7–AC9, AC12, AC14, AC24, AC25)
  - The view model carries the kind label, the app's meta line, the facts, Cast & Crew from the transformed credits,
    the seasons for a series, and genres and platforms for a game
  - The template drops the Share button, its script and the provider credit.
    It adds the header with the app icon, the blurred poster backdrop and grayscale photos
  - The icon is a small PNG embedded in the binary and inlined as a data URI, so the page needs no extra route
  - Tests cover the new fields per type, and the docs drop anything that names the Share button or the credit

## Gates

- [x] Plan review – PASS (round 3, codex)
- [ ] Code review – INCOMPLETE (round 4, codex; no findings; AC11 human check pending)
