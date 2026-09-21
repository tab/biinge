# Backlog

## Medium

- [ ] **BL-001: `UserRepository` keeps `FindById` and replaces `FindByLogin` and `FindByEmail` with `FindByFilter`**
  - Why: the movies, series and games repositories look rows up through a `FindByFilter(filter)` method. Users should match, so
    one finder shape holds across the repositories. `FindById` stays because a primary-key lookup is its own case
  - Added: 20260920
- [ ] **BL-002: The `webhooks` table gets a retention rule**
  - Why: every accepted Jellyfin event stores its full payload, and marking a long show played sends one event per episode.
    Nothing removes old rows, so the table only grows
  - Added: 20260921
  - Source: 20260920-jellyfin-watched-sync/feature.md
- [ ] **BL-003: The iOS Jellyfin screen learns whether a token exists**
  - Why: the screen has no way to ask, so Revoke always shows, also when there is nothing to revoke. Needs a `GET` on
    `/accounts/integrations/jellyfin` that reports whether a link exists
  - Added: 20260921
  - Source: 20260920-jellyfin-watched-sync/feature.md
