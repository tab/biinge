# Details facts plan

Feature: [feature.md](feature.md)

Status: implemented

Phase: code review

Current step: PR preparation, after the human checks below

## Steps

1. API: episode `directors` and game `developers`, with the spec and the docs page
2. Core: the models, the facts and the badge rules
3. Mac: the block and the badges
4. iPhone: the block and the badges
5. Apple TV: the block on two rows, and the shared badge rules
6. Coverage pass on the new shared code
7. Docs pass

## Open human checks

- Add a movie to Jellyfin, and confirm it returns its streams through `service.item(id:)` (AC9).
- Run all three apps, and confirm the block and the badges on each screen (AC6, AC15).
  - Check the rendered layouts, and use the remote presses on Apple TV.
- On the Apple TV first screen, confirm two fact rows with progress and a note on screen (AC19).
