# Jellyfin two-way watched sync plan

Feature: [feature.md](feature.md)

Status: implemented

Phase: pr review

Current step: open the pull request

## Done when

- Every acceptance criterion in `feature.md` holds
- `make check` and `make drift BASE=master` in `api/` are clean
- The TMDB refresh worker's tests pass with unchanged behavior after the split
- Tests cover a first pass, a flip in each direction, a failed change retried by the next poll, a reconnect as another
  Jellyfin user, a reconcile with a failed write and its retry, duplicate Jellyfin matches, a user reversing a reconcile write before the next poll, a queued
  write that succeeds and a later one that fails, and a queued write that lands during a poll's read
- On the local server, a movie and an episode marked played and unplayed in the Jellyfin web client show in biinge within
  one poll, and a movie played only in Jellyfin is added
- On the local server, the first reconcile leaves Jellyfin's played items matching biinge's watched titles
- The full played-state read is timed on the production server and fits the interval

## Steps

- [x] 1. Check on the live Jellyfin server how a played change can be read, that a partial replay keeps `Played` true and that `datePlayed` sets `LastPlayedDate`
  - `MinDateLastSavedForUser` filters on the item's saved date, so the poll reads the full state. The other checks passed
- [x] 2. Organise `api/internal/app/worker` by purpose, with no behavior change
  - The TMDB refresh becomes its own worker type and file, with its tests beside it
- [x] 3. Add `JELLYFIN_SYNC_INTERVAL` and `JELLYFIN_RECONCILE_INTERVAL` to the config
- [x] 4. Add the Jellyfin client calls the sync needs
  - One read of every movie and episode with its played flag, last played date, provider ids, series id and numbers
  - `datePlayed` on the played write
- [x] 5. Apply changes to biinge through the `Movies` and `Progress` services, per the feature rules
  - Port the rules of the retired webhook service (`api/internal/app/services/jellyfin.go` before `6bc1fce`)
  - Add an untracked movie from its TMDB details, and let the progress cascade add an untracked show
- [x] 6. Keep the previous read in one store that the played-write queue and the reconcile update on each successful write
- [x] 7. Add the reconcile, which compares biinge's library with the read and writes the differences to Jellyfin directly
- [x] 8. Add the Jellyfin worker: one pass per connected user per tick, the in-memory previous read, the diff, the first pass and the reconcile schedule
- [x] 9. Update the API README, the `.env` templates and BL-025 in the backlog

- [x] 10. Add `JELLYFIN_SYNC_ENABLED`, default off, which gates the Jellyfin worker, with the README and `.env` templates
## Gates

- [x] Plan review – PASS, round 2, 2026-11-08 (codex; PLAN-1 and PLAN-2 fixed)
- [x] Code review – PASS, round 4, 2026-11-08 (codex; reopened by step 10, no new findings)
