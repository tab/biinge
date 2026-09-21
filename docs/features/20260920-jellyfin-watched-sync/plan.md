# Jellyfin watched sync plan

Feature: feature.md

Status: implemented

Phase: code review

Current step: PR preparation

## Approach

One unauthenticated route, two authenticated routes, two tables, one TMDB client method. Every library write goes through
the existing `Movies` and `Progress` services, so nothing in the progress cascade changes.

Layers, following `api/CLAUDE.md`:

- `db/migrate`: four migrations in the `appearance_type` shape: the `provider_type` enum, `integrations`, the `status_type`
  enum, `webhooks`. `make db:schema:dump` refreshes `db/schema.sql`
- `db/sqlc/integrations.sql`: upsert, find by token hash and provider (joined to a live user), delete. `db/sqlc/webhooks.sql`: insert
- `pkg/jellyfin`: the Webhook plugin protocol. `Event` with the keys from the contract and the raw body, `ParseEvent` (a JSON
  object, else an error), `Finished` (the `Played` and `SaveReason` filter), the item type and save reason constants. It has
  no biinge dependency, so it can move to another project
- `pkg/tmdb`: `Find(ctx, externalId, source)` for `/find/{id}?external_source=...`, returning `tv_episode_results`
- `repositories/integrations.go`: `IntegrationRepository` with `Upsert`, `FindByTokenHash` and `Delete`. `repositories/webhooks.go`:
  `WebhookRepository` with `Create`, an insert that returns nothing. Raw errors pass through, `pgx.ErrNoRows` included
- `services/integrations.go`: `Integrations` with `CreateToken`, `Revoke`, `Authenticate`. The token is 32 random bytes as hex,
  the row stores its SHA-256. `Authenticate` hashes the bearer value; no row is `ErrUnauthorized` without an error log, any
  other repository error is `ErrFailedToAuthenticateIntegration`
- `services/jellyfin.go`: `Jellyfin.Handle(ctx, integration, event)`. It drops events that are not `Finished`, then:
  1. `ItemType` other than `Movie` or `Episode`: `ignored`
  2. Movie: `Provider_tmdb` is the id, else `unresolved`. `Movies.FindByFilter`; no row or already `watched`: `ignored`.
     Else `Movies.UpdateByTmdbId` with `watched` and the row's `pinned`: `marked`
  3. Episode: `/find` on `Provider_tvdb`, else `Provider_imdb`, else `unresolved`. `Progress.Get`; show `none`, show `watched`
     or the episode id already in `WatchedEpisodes`: `ignored`. Else `/tv/{show_id}` through the shared `tmdb:v1:tv:{id}`
     cache entry, then `Progress.MarkEpisode` with the show, season and episode inputs: `marked`
  4. TMDB `ErrNotFound` is `unresolved` with `ErrTitleNotFound`, any other TMDB error is `failed` with `ErrTmdbUnavailable`,
     a service error is `failed` with `ErrFailedToProcessWebhook`. `unresolved` logs a warning with the item type, name and ids
  5. `WebhookRepository.Create` with the raw body, status and error text. A failed insert returns `ErrFailedToProcessWebhook`
- `controllers/integrations.go`: `HandleCreateToken` (`201`), `HandleRevoke` (`204`), `HandleJellyfinWebhook`. The webhook
  handler reads the bearer value with `middlewares.BearerToken` and calls `Authenticate` (`401`), parses the body through a
  1 MiB `http.MaxBytesReader` (`400`), then `Handle`. `ErrTmdbUnavailable` is `502`, `ErrFailedToProcessWebhook` and
  `ErrFailedToAuthenticateIntegration` are `503`, any other error `422`, success `204`
- `config/router`: `/webhooks` route outside the JWT middleware with `httprate.LimitBy(120, time.Minute, keyByIP)`.
  `/accounts/integrations/jellyfin` inside the JWT group
- fx wiring in `repositories/module.go`, `services/module.go` and `controllers/module.go`. Every interface has a mock

iOS: `JellyfinView` is a `ProfileSheet` case and a Profile row. It shows the setup steps with the webhook URL from `Config.baseURL`,
Generate token, Revoke with a confirmation, and the new token once with Copy. `APIClient` gains `createJellyfinToken` and
`revokeJellyfin`. A `DEBUG_JELLYFIN=1` launch hook opens the sheet for the screenshot pipeline.

Docs: `docs/src/pages/docs/jellyfin.astro` is the setup guide, with the webhook URL from `PUBLIC_API_BASE_URL`. It shares
`src/styles/guide.css` with the self-hosting page instead of carrying a copy of that page's styles. `api.astro`
gains an `Integrations` group, the webhook exception in its auth sentence and the `502` row. `swagger.yaml` gains the three
routes, a second security scheme for the Jellyfin token and the `JellyfinEvent` schema.

## Steps

API:

- [x] Migrations, schema dump, sqlc queries and generated code (AC14, AC15)
- [x] `tmdb.Client.Find` with models, client tests and a regenerated mock (AC7, AC8, AC10, AC11)
- [x] `pkg/jellyfin` with `Event`, `ParseEvent`, `Finished` and tests (AC2, AC4)
- [x] `IntegrationRepository` and `WebhookRepository` with tests against Postgres (AC13, AC14, AC15, AC16)
- [x] `Integrations` service, mock and tests, including a soft-deleted owner and a repository failure (AC1, AC14, AC16)
- [x] `Jellyfin` service, mock and table-driven tests for every rule and status (AC4 to AC13)
- [x] `IntegrationsController`, fx wiring and tests for each status code and the order of checks (AC1 to AC5, AC10, AC11, AC14, AC16)
- [x] Router test for the `/webhooks` rate limit (AC3), `BearerToken` test
- [x] `swagger.yaml` entries (AC18)
- [x] `make check` clean

Code review fixes:

- [x] CODE-1: datastore failures on the webhook answer `503`; contract, `swagger.yaml`, `api.astro` and the guide updated
- [x] `FindIntegrationByTokenHash` binds the provider; `FindByTokenHash(ctx, hash, provider)`, mock regenerated
- [x] `ParseEvent` answers `ErrNotAnObject` for every body that does not start with `{`
- [x] `swagger.yaml`: `JellyfinEvent` has no `required` list, `400` names a wrong-typed key
- [x] `Test_IntegrationRepository_FindByFilter` renamed to `Test_IntegrationRepository_FindByTokenHash`
- [x] Footer links the Jellyfin guide, checked in headless Chrome at desktop and phone widths
- [x] BL-002 and BL-003 in `docs/features/backlog.md`
- [x] All three loops clean

iOS:

- [x] `APIClient` methods and the `JellyfinToken` model (AC17)
- [x] `JellyfinView` and the Profile row (AC17)
- [x] `make lint && make test` clean

Docs:

- [x] `docs/src/pages/docs/jellyfin.astro` setup guide (AC18)
- [x] `api.astro` `Integrations` group and the auth sentence in its overview (AC18)
- [x] `npm run build` clean

## Verification

- `make check` in `api/`: fmt, lint, test and test:race against the live `biinge-test` database
- `make lint && make test` in `ios/`
- `npm run build` in `docs/`
- Service tests cover each rule with mocks: movie not in library, want, watching, already watched; episode with show absent,
  show watched, episode already watched, show want or watching. Each asserts the calls made and the stored status
- Controller tests cover `204`, `400`, `401`, `422`, `502` and `503` from the webhook and `201` and `204` from the token routes.
  Order cases: no token and a malformed body gets `401`; a valid token with a `null`, array, scalar, malformed or oversized
  body gets `400`; the router test proves `429` comes before the token check
- `pkg/jellyfin` tests prove an extra key stays in `Raw`, keys match case-insensitively and only finished plays pass the filter
- Repository tests prove the upsert replaces the hash, `FindByTokenHash` misses a revoked row and a soft-deleted owner, the
  enums reject unknown values and the `webhooks` insert stores the payload
- Manual check against a Jellyfin server: generate a token in the app, add the destination, finish an episode of a show in
  `watching` and one already watched, finish a movie in `want`. Read the `webhooks` rows and the library rows afterwards

## Gates

- [x] Plan review: PASS (stress: general + authorization boundaries, codex, 2026-09-20, 11 findings resolved in round 1).
      The MVP cut only removed steps, so the human approved the simplified contract and plan without a new review
- [x] Code review: PASS (standard, claude, 2026-09-21, CODE-1 fixed, not rechecked; stress: general + authorization
      boundaries, codex, 2026-09-20, 2 mediums fixed and rechecked by round 3)
- [ ] PR review – not run
