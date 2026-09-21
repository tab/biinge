# Jellyfin watched sync

## Goal

When a person marks a movie or an episode watched in Jellyfin, biinge marks it watched.
Only titles already in the library are affected. A title that is already watched is left alone.

## Context

biinge tracks want, watching and watched for movies, and progress per episode for shows. Every mark is made by hand in the app.
Jellyfin knows the moment a person finishes something. Its Webhook plugin can post that moment to the biinge API.

Jellyfin stores a TMDB id on movies. On episodes it stores the TVDB and IMDb ids that TMDB lists for them, not a TMDB id.
TMDB's `/find` endpoint turns a TVDB or IMDb episode id into the show id, season number, episode number and episode fields.
The target version is Jellyfin 12.

## Scope

### In

- A Jellyfin token per user. The user creates it, sees it once and can revoke it
- A `webhooks` table. Every event that passes the filter is stored with what biinge did about it
- A webhook endpoint for the Jellyfin Webhook plugin. It accepts `UserDataSaved` events for movies and episodes
- Two writes. A movie marked watched in Jellyfin becomes watched in biinge. An episode marked watched in Jellyfin becomes
  watched in biinge. Both only for titles already in the library
- A Profile screen in the iOS app for the token and the setup steps
- A setup guide on the docs site. The API reference and `swagger.yaml` get the new routes

### Out

- Pushing biinge marks to Jellyfin. Sync is one way
- Polling the Jellyfin API, or storing any Jellyfin credential in biinge
- Removing a watched mark because of a Jellyfin event (unmark, unplayed, deleted item)
- Rewatch tracking. A title that is already watched keeps its `watched_at`
- Adding a title that is not in the library
- Backfilling plays from before the token was created
- Games, music, playback position or a "currently watching" state
- Season and series events from Jellyfin. biinge derives those from episodes
- A retry queue. The plugin sends once and logs a failed delivery
- The second episode of a multi-episode file (`EpisodeNumberEnd`)
- Resolving a movie by its IMDb id. Jellyfin's TMDB provider always sets `Provider_tmdb`

## Expected behavior

### Main flow

1. In the app, the user opens Profile → Jellyfin and taps Generate token. The app shows the token once, with a copy button,
   and lists the setup steps with the webhook URL for this API
2. A Jellyfin admin adds a Generic Destination in the Webhook plugin. Webhook Url: `<API base>/api/v1/webhooks/jellyfin`.
   Request header: `Authorization: Bearer <token>`. Notification Type: "User Data Saved". Item Type: "Movies" and "Episodes".
   User Filter: that person's Jellyfin user. "Send All Properties": ticked
3. The person finishes a movie or an episode in Jellyfin, or marks it played there. The plugin POSTs the event
4. The API finds the user by the token. It keeps only events with `Played` true and `SaveReason` `PlaybackFinished` or
   `TogglePlayed`. It resolves the title on TMDB, applies the rules below and replies `204`
5. The app shows the change on its next refresh

### Rules

Jellyfin only adds marks to titles the person already tracks. It never adds a title and never changes a `watched` state.
Every write goes through the `Movies` and `Progress` services, which invalidate the user's stats cache. An ignored event
invalidates nothing.

Movie events:

- Not in the library, or already `watched`: no write
- In `want` or `watching`: move to `watched`. Set `watched_at` to now. Keep `pinned`

Episode events, checked against the show's current progress:

- Show not in the library: no write
- Episode already watched: no write
- Show `watched` and the episode row missing: no write. The cascade would flip the show back to `watching`
- Show `want` or `watching`: mark the episode through the existing progress cascade. The show becomes `watching`, or
  `watched` when every season is watched and the TMDB status is not `Returning Series`. `tracked_state` does not change

### Acceptance criteria

Webhook:

- **AC1**: a POST with a missing, unknown or revoked token gets `401` and writes nothing. AC3 comes first when the IP is over the limit
- **AC2**: a POST with a body that is not valid JSON, is JSON but not an object, or is over 1 MiB, gets `400` and writes nothing
- **AC3**: the 121st POST from one IP within a minute gets `429`. The token is not checked
- **AC4**: an event with `Played` false, or a `SaveReason` other than `PlaybackFinished` or `TogglePlayed`, gets `204` and writes nothing
- **AC5**: a movie event for a title not in the library, or already `watched`, gets `204` and writes nothing
- **AC6**: a movie event for a title in `want` or `watching` moves it to `watched`, sets `watched_at` and keeps `pinned`
- **AC7**: an episode event with `Provider_tvdb` resolves through TMDB `/find` to the show, season and episode and marks the
  episode. The season and show state derive through the existing progress cascade
- **AC8**: an episode event without `Provider_tvdb` but with `Provider_imdb` resolves the same way through the IMDb id
- **AC9**: an episode event gets `204` and writes nothing when the show is not in the library, the episode is already watched,
  or the show is `watched` and there is no row for that episode
- **AC10**: an unresolvable event gets `422`, a warning log and no write. Unresolvable means a movie event without
  `Provider_tmdb`, an episode event with neither `Provider_tvdb` nor `Provider_imdb`, or an id TMDB answers with not found
- **AC11**: a TMDB request that fails for any reason other than not found gets `502` and no write
- **AC12**: an event that writes a mark invalidates the user's stats cache. An event that writes nothing leaves the cache alone
- **AC13**: every event that passes the token check and the AC4 filter gets a `webhooks` row with the raw payload and its
  status, the `422` and `502` ones included. Events dropped by AC1 to AC4 get no row

Token endpoints:

- **AC14**: `POST` returns `201` with a 64-character hex token. A second `POST` returns a new token and the first gets `401`
- **AC15**: the `integrations` row holds the SHA-256 of the token and never the token itself
- **AC16**: `DELETE` returns `204` and the token gets `401` from then on. A second `DELETE` also returns `204`

Client and docs:

- **AC17**: Profile → Jellyfin in the iOS app offers Generate token and Revoke and lists the setup steps with the webhook URL.
  After Generate it shows the new token once, with Copy
- **AC18**: `api/api/swagger.yaml`, `docs/src/pages/docs/api.astro` and a setup guide page on the docs site describe the new
  routes and the Jellyfin configuration

## Assumptions

- Jellyfin uses its built-in TMDB providers, so movies carry `Provider_tmdb` and episodes carry `Provider_tvdb` or
  `Provider_imdb`. A library scraped only from local NFO files may lack them. Its events get `422`
- Only a Jellyfin admin can add a Webhook plugin destination
- The Jellyfin server can reach the API over HTTPS. The API never calls Jellyfin
- Delivery is best effort. A lost event is one missing mark, which the person can still add in the app
- "Send All Properties" also posts a `PlaybackProgress` save about every ten seconds during playback. The `SaveReason` check
  drops those before any TMDB or database work. The rate limit allows about six requests a minute per stream
- Without the User Filter, every Jellyfin user's plays land on the account that owns the token. The setup guide says so
- Marking a season or a show played in Jellyfin sends one `TogglePlayed` event per episode

## Contracts

### Webhook

`POST /api/v1/webhooks/jellyfin` with `Authorization: Bearer <token>`. The body is the JSON that "Send All Properties" sends.
The route sits outside the JWT middleware. It has an `httprate` limit of 120 requests a minute per client IP, checked before
the token. The body is read up to 1 MiB.

The API reads these keys. Key matching is case-insensitive. Every other key is ignored but stored.

| Key | Use |
| --- | --- |
| `ItemType` | `Movie` or `Episode`. Anything else is ignored with `204` |
| `SaveReason` | must be `PlaybackFinished` or `TogglePlayed` |
| `Played` | must be `true` |
| `Provider_tmdb` | movie TMDB id |
| `Provider_tvdb` | episode TVDB id, tried first |
| `Provider_imdb` | episode IMDb id, used when the TVDB id is missing |
| `Name` | logging only |

Resolution:

- Movie: `Provider_tmdb` is the TMDB id. The row already holds the title, poster and runtime
- Episode: `/find/{id}?external_source=tvdb_id`, else `imdb_id`. The first of `tv_episode_results` gives `show_id`,
  `season_number` and the episode fields. When the episode gets a new mark, `/tv/{show_id}` gives the show title, poster,
  status, counts and the matching season's TMDB id and episode count. An ignored event skips that call

Responses:

| Status | When | Body |
| --- | --- | --- |
| `204` | mark written, or event ignored | none |
| `400` | body is not valid JSON, is JSON but not an object, or is over 1 MiB | `{ "error": "..." }` |
| `401` | missing, unknown or revoked token | `{ "error": "..." }` |
| `422` | no usable provider id, or TMDB answers not found | `{ "error": "..." }` |
| `502` | TMDB request failed for another reason | `{ "error": "..." }` |
| `503` | the token lookup, the library write or the trace insert failed in the database | `{ "error": "..." }` |
| `429` | over the IP limit | `httprate`'s plain-text default, as on the existing routes |

### Token endpoints

Behind the JWT middleware, under `/api/v1/accounts/integrations/jellyfin`:

- `POST` creates or replaces the link. It returns `201 { "token": "<64 hex chars>" }`. The plaintext is never returned again
- `DELETE` removes the link and returns `204`, also when there was none

### Data

Table `integrations`. One row per user and provider.

- `id`: uuid, primary key
- `user_id`: foreign key to `users`, cascade delete
- `provider`: `provider_type` enum, `jellyfin` for now. A later provider adds a value with `ALTER TYPE`
- `token_hash`: `char(64)`, unique. The SHA-256 of the token as hex. Lookup is by hash
- `created_at`, `updated_at`: as on every other table. `updated_at` moves when `POST` replaces the token

Unique on (`user_id`, `provider`). Revoke is a hard delete.

Table `webhooks`. One row per stored event, so a wrong or missing mark can be traced to its payload.

- `id`: uuid, primary key
- `integration_id`: foreign key to `integrations`, cascade delete
- `payload`: `jsonb`, the request body as received
- `status`: `status_type` enum, one of `marked`, `ignored`, `unresolved`, `failed`
- `error`: `text`, nullable, the reason for `unresolved` and `failed`
- `created_at`, `updated_at`: as on every other table

Index on (`integration_id`, `created_at`). No retention job. The `PlaybackProgress` saves never reach the table.

The token is 32 random bytes as hex. A soft-deleted owner's token stops working with the account.

## Decisions

- Webhook push instead of polling. Polling needs a Jellyfin credential in biinge, and Jellyfin only has server-wide admin
  keys or user logins. The token biinge hands out can only add watched marks. The cost is no backfill
- `UserDataSaved` instead of `PlaybackStop`, so "mark played" in Jellyfin counts too
- Jellyfin only adds marks. A library rescan or a user-data reset in Jellyfin must never erase biinge history
- Processing runs inside the request. At most two TMDB calls per event, and the show detail call uses the existing cache
- "Send All Properties" instead of a Handlebars template. One less copy-paste step in the setup
- Episodes resolve through `/find` only. A name search can match the wrong show
- The token travels in `Authorization: Bearer`, the header the JWT routes already use, so nothing new has to pass a proxy
- `429` keeps `httprate`'s plain-text body, as on the login routes
