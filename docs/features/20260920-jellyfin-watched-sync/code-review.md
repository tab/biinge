# Code review

Mode: standard
Gate: code
Status: passed
Round: 2
Target: working tree of `feat/jellyfin-watched-sync`, staged and uncommitted, against `master` at 39a5701
Reviewer: claude
Model: claude-fable-5-1
Effort: xhigh

## Findings

No open findings.

## Resolved

- CODE-1 – resolved: `HandleJellyfinWebhook` answers `503` for `ErrFailedToAuthenticateIntegration` and
  `ErrFailedToProcessWebhook`, `422` for `ErrMissingProviderId` and `ErrTitleNotFound`, `502` for `ErrTmdbUnavailable`.
  The contract's response table, `swagger.yaml`, the `api.astro` note and status table and the guide's troubleshooting
  list carry the `503` row. Controller tests "Token lookup failing" and "Processing failed" assert `503`
- CODE-R1 (codex stress review, authorization boundaries) – resolved: Copy uses local-only pasteboard storage with a
  two-minute expiration and explains the limitation to users
- CODE-R2 (codex stress review, authorization boundaries) – resolved: the Jellyfin webhook entry on the API reference
  renders a curl example only and never sends the Jellyfin token

## Checked

### Round 2 (recheck of CODE-1 and the round 1 suggestions)

- CODE-1 fix in the controller, contract, spec, reference page and guide; no other status mapping moved
- `FindIntegrationByTokenHash` filters on `provider`; `FindByTokenHash(ctx, hash, provider)` in the repository, its
  regenerated mock and `Authenticate` passing `models.JellyfinProvider`; repository and service tests updated
- `ParseEvent` answers `ErrNotAnObject` for any body not starting with `{`; the null special case is gone and the array,
  scalar and null controller cases share one message. Malformed JSON keeps the decoder error
- `JellyfinEvent` schema has no `required` list; the `400` description names a wrong-typed key
- `Test_IntegrationRepository_FindByTokenHash` renamed
- Footer links `docs/jellyfin/`; the link renders in the built home and self-hosting pages
- BL-002 and BL-003 in `docs/features/backlog.md`
- `make check` in `api/`: clean, with every new file staged so the doc-comment grader saw it
- `make drift BASE=master`: no schema or spec drift. `git diff --cached --check`: clean
- `npm run build` in `docs/`: clean
- iOS sources unchanged since round 1; `make lint` clean in round 1, `make test` recorded clean in the plan
- Headless Chrome check of the footer recorded in the plan, not rerun

### Round 1

- `feature.md` and `plan.md`: AC1 to AC18, contracts, decisions, recorded verification
- Tracked diff against `master` at 39a5701 and every untracked implementation file, mocks and sqlc output included
- Existing paths the feature writes through: `Movies.UpdateByTmdbId` (`watched_at` through `COALESCE`, stats
  invalidation), `Progress.Get` (`none` for an untracked show), `MarkEpisodeWatched` (the series upsert always updates the
  row, so its lock serialises a per-episode burst under read committed; `recomputeSeries` derives the state and
  `tracked_state` is untouched), the shared `tmdb:v1:tv:{id}` cache entry (`*tmdb.TvDetails` in `services/tmdb.go`)
- `make check` in `api/`, `make drift BASE=master`, `git diff --check`, `npm run build` in `docs/`, `make lint` in
  `ios/`: clean. `make test` in `ios/` and the manual Jellyfin end-to-end check not rerun; the plan records both

## Verdict

PASS
