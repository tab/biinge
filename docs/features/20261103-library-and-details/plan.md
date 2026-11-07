# Library and details plan

Feature: [feature.md](feature.md)

Status: in progress

Phase: code review

Current step: the human checks below

## Steps

1. Lists on every app: My Lists, the Mac sidebar counts, availability, resume bars and load errors with Retry
2. Games on every app: the Mac sidebar group, the Apple TV tab, the iPhone pills and game details
3. Search and person pages from the biinge API, with recent searches on Mac and Apple TV
4. One details screen per kind, with the white pill, the list menu, More and genres
5. Episode details on every app, and progress on every episode row
6. The iPhone Library pill with its four states, and pill filters and sort on iPhone lists
7. Library filters and later-page errors on Mac and Apple TV
8. Home on Mac and Apple TV, with See All, the featured row and the Watched refresh, and Up Next on iPhone
9. The Mac sidebar library card

## Open human checks

- Run `make test:macos` from a terminal that can answer the Keychain prompt.
- Run all three apps against a real Jellyfin server, and walk AC1 to AC49 on each, in light and dark.
  - Compare the Mac sidebar counts and the Apple TV rows with the iPhone lists.
  - On Apple TV, use the remote presses and check the rendered layouts.
- After each live run, follow the cleanup in [`ios/CLAUDE.md`](../../../ios/CLAUDE.md#live-runs).
