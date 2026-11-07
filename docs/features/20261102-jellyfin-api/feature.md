# Jellyfin API

## Goal

The biinge API holds a Jellyfin connection for each user.
It matches catalog titles to that user's library and writes watched marks to Jellyfin.

## Why

The apps need one source for what the library holds.
A watched mark needs one write path, so no app repeats it.
Every play goes through the biinge apps, so the API has no Jellyfin webhook.

## Scope

- `JELLYFIN_BASE_URL` and `JELLYFIN_TOKEN_KEY` in the API config
- Connect, status and disconnect at `/api/v1/accounts/integrations/jellyfin/connection`
- `jellyfinId` on movie, series, season and episode reads, and on the movie and series lists
- `genres` on movie and series details
- Played writes to Jellyfin for marks and deletes
- Retirement of the Jellyfin webhook, its token routes and its table
- The routes and fields in `swagger.yaml` and the docs site API reference

## How it works

1. The user sends their Jellyfin username and password to the connect route.
2. The API signs in to Jellyfin as that user, on a device of its own.
3. The API stores the Jellyfin user id, the username and the encrypted token, never the password.
4. The API reads the user's movies and series, and indexes them by TMDB id.
5. Each read adds `jellyfinId` for a title with exactly one match.
6. A mark writes biinge first, then queues the Jellyfin write.
7. One worker runs the queued writes in order, in the background.

## Acceptance criteria

- **AC1** – Connect with a valid username and password stores the connection and returns its status.
- **AC2** – Connect again replaces the connection and signs the earlier token out of Jellyfin.
- **AC3** – A wrong username or password returns 422 and keeps any earlier connection.
- **AC4** – An unreachable Jellyfin server returns 502 and keeps any earlier connection.
- **AC5** – A connection that can't be stored returns 503, and its new token is signed out.
- **AC6** – Status returns the server address, the connected flag and the username, and never a token.
- **AC7** – Disconnect deletes the connection, even when the Jellyfin sign-out fails.
- **AC8** – Disconnect without a connection returns 204.
- **AC9** – With `JELLYFIN_BASE_URL` empty, the connection routes return 404.
- **AC10** – With `JELLYFIN_BASE_URL` set, the API refuses to start unless `JELLYFIN_TOKEN_KEY` is 32 bytes.
- **AC11** – The database holds the access token only encrypted.
- **AC12** – No log line holds the token or the password.
- **AC13** – A movie or series with exactly one library item of its TMDB id carries `jellyfinId` in its details.
- **AC14** – `GET /movies` and `GET /series` items carry `jellyfinId` by the same rule.
- **AC15** – An episode carries `jellyfinId` when its series matches and one item holds its season and episode number.
- **AC16** – A title with no match, or with more than one, has no `jellyfinId`.
- **AC17** – A user without a connection, or an instance without Jellyfin, gets no `jellyfinId` and no error.
- **AC18** – When Jellyfin fails or rejects the token, the response arrives without `jellyfinId`.
- **AC19** – The index holds only items the user's Jellyfin account can access.
- **AC20** – With Redis working, reads within 10 minutes read Jellyfin once for the library and once per series.
- **AC21** – Without Redis, each request reads Jellyfin.
- **AC22** – A title added to the library shows its `jellyfinId` once the cache expires.
- **AC23** – Movie and series details return `genres`, whether the library holds the title or not.
- **AC24** – Marking a movie watched marks its item played. Changing it from watched marks it unplayed.
- **AC25** – Marking an episode watched or unwatched sets the matching episode's played state.
- **AC26** – Marking a season sets the played state of each matched episode of that season.
- **AC27** – Marking a show sets the played state of the series item and each matched episode.
- **AC28** – Deleting a movie or series from biinge marks its item unplayed, whatever its biinge state was.
- **AC29** – A series delete also unplays each of its matched episodes.
- **AC30** – A mark that doesn't change the watched state sends nothing to Jellyfin.
- **AC31** – A title without exactly one match writes biinge only.
- **AC32** – A slow, failed or rejected Jellyfin write never delays or changes the biinge response.
- **AC33** – A failed Jellyfin write is logged.
- **AC34** – Queued writes reach Jellyfin in the order they were queued, so a mark and a quick unmark end unplayed.
- **AC35** – The API has no Jellyfin webhook route, webhook token route or webhook table.

## Contracts

- A Jellyfin auth failure never returns 401, so the apps never read it as a biinge logout.
- The API never sends the Jellyfin token to a client.
- `jellyfinId` is omitted unless the library holds exactly one match.
- The library and episode indexes live in the Redis cache for 10 minutes, per user and Jellyfin user.
- Played state is written with `POST` and `DELETE /UserPlayedItems/{itemId}?userId=…`.

## Decisions

- Tokens are sealed with AES-GCM under `JELLYFIN_TOKEN_KEY`.
- Disconnect deletes the user's `integrations` row.
- The sign-in device id derives from the biinge user id, so each user's API login is its own Jellyfin device.
- Jellyfin ignores a TMDB id filter on its items query, so the API reads the library list and matches it itself.
- Episodes match by series, season and episode number, because Jellyfin's TMDB id on episodes is unreliable.
- A show writes the series item and each matched episode, because Jellyfin leaves the episodes unplayed otherwise.
- Jellyfin follows biinge: a delete marks the item unplayed, even when Jellyfin held it played from before.
- Season and episode numbers come from cached TMDB details, because unmark requests carry only TMDB ids.
- A TMDB lookup that fails skips that Jellyfin write.
- One write takes at most 30 seconds. The queue holds 256 writes, and a full queue drops the next one with a warning.
