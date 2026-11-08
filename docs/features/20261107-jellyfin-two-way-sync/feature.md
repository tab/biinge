# Jellyfin two-way watched sync

## Goal

A watched mark made in Jellyfin reaches biinge, and a mark made in biinge keeps reaching Jellyfin.
A periodic reconcile repairs any drift, with biinge's state winning.

## Why

The API writes every biinge mark to Jellyfin, but nothing comes back.
The [Jellyfin API](../20261102-jellyfin-api/feature.md) feature assumed every play goes through the biinge apps.
Plays in the Jellyfin web client and in Wholphin on the TV mark Jellyfin only, and the existing Jellyfin library was never aligned with biinge.
A failed or dropped biinge → Jellyfin write is only logged, so the two sides stay apart until the title is marked again.

## Scope

In:

- A poll in a new Jellyfin worker that finds each connected user's changed Jellyfin played states and applies them to biinge
- Adding a title to biinge when it is played in Jellyfin and biinge does not track it yet
- A reconcile in the same worker that writes biinge's watched state to every matched Jellyfin item that differs
- The worker package organised by purpose: the TMDB refresh and the Jellyfin sync each run as their own worker
- The new config values in the API README and `.env` templates

Out:

- The Jellyfin Webhook plugin. The API keeps no webhook route
- Changing Jellyfin items whose title is not in the biinge library
- Playback position, resume points and play counts. Games and music
- Rewatch history. A title that is already watched keeps its `watched_at`
- A screen in the apps for the poll or the reconcile
- Telling apart the people who share one Jellyfin user. Every play on it counts as the biinge user's
- Keeping Jellyfin changes made while the API is down. See [Decisions](#decisions)

## How it works

1. The Jellyfin worker runs a sync pass for each connected user every `JELLYFIN_SYNC_INTERVAL`, 2 minutes by default.
2. The pass reads the played state of all the user's Jellyfin movies and episodes in one request.
3. The worker compares it with the previous pass's read, which it keeps in memory. Each item whose played flag flipped is a change.
4. Each change maps to a biinge title: a movie by its TMDB id, an episode by its series' TMDB id and its season and episode number. Only a unique match counts, as in the played writes: an id or number held by several items matches nothing.
5. The API applies each change with the [rules](#rules), then keeps this read as the previous one. Each successful API write to Jellyfin, queued or from the reconcile, sets that item's previous state to the written one.
6. On the first pass and then every `JELLYFIN_RECONCILE_INTERVAL`, 1 hour by default, the pass runs the reconcile after a clean poll. It writes biinge's state to each matched item of the same read that differs.
7. A biinge mark keeps writing Jellyfin as it does today. The poll writes biinge only, so it never echoes back.

### Rules

Writes go through the `Movies` and `Progress` services, so the cascade and the stats cache stay correct. An item that changes nothing writes nothing.

- Movie played, not in biinge: created from its TMDB details as `watched`, `watched_at` is Jellyfin's last played date
- Movie played, `want` or `watching`: becomes `watched` with Jellyfin's last played date. `watched` stays
- Movie unplayed: `watched` becomes `want`. Other states stay, and an untracked movie is not added
- Episode played: marked through the progress cascade. A show not in biinge is added by the cascade and becomes `watching`
- Episode unplayed: a watched episode is unmarked through the progress cascade. An untracked show is not added

## Acceptance criteria

- **AC1** – A movie played in Jellyfin and not in biinge is in biinge as `watched` after the next poll, with Jellyfin's last played date.
- **AC2** – A movie played in Jellyfin and `want` or `watching` in biinge is `watched` after the next poll, with Jellyfin's last played date.
- **AC3** – A movie marked unplayed in Jellyfin and `watched` in biinge is `want` after the next poll, with `pinned` kept.
- **AC4** – An episode played in Jellyfin is watched in biinge after the next poll, and the season and show state derive through the cascade.
- **AC5** – An episode played in Jellyfin of a show not in biinge adds the show and marks the episode.
- **AC6** – An episode marked unplayed in Jellyfin is unwatched in biinge after the next poll.
- **AC7** – An unplayed item whose title is not in biinge, or any item without a unique match, writes nothing.
- **AC8** – A change that already matches biinge's state writes nothing and leaves the stats cache alone.
- **AC9** – A poll writes nothing to Jellyfin.
- **AC10** – A poll applies only items whose played flag differs from the previous pass's read, so an unchanged item is never applied twice.
- **AC11** – The first pass after the API starts or the user connects only records the read, applies nothing and runs the reconcile.
- **AC12** – A reconnect as another Jellyfin user drops the previous read, so its next pass is a first pass.
- **AC13** – A Jellyfin failure or a rejected token for one user skips that user's pass and keeps its previous read. Other users are unaffected.
- **AC14** – A TMDB or database failure on a change keeps that item's previous state, so the next poll applies it again, and skips the reconcile on that pass.
- **AC15** – The reconcile marks played each matched item of a watched biinge movie or episode, with biinge's `watched_at` as the date.
- **AC16** – The reconcile marks unplayed each matched item of a biinge movie or episode that is not watched.
- **AC17** – The reconcile writes only items whose Jellyfin played state differs from biinge's.
- **AC18** – The reconcile writes Jellyfin directly, not through the played-write queue, so no write is dropped.
- **AC19** – A failed reconcile write is logged, and the next reconcile tries it again.
- **AC20** – With `JELLYFIN_BASE_URL` empty or `JELLYFIN_SYNC_ENABLED` not `true`, no sync pass runs.
- **AC21** – A successful queued or reconcile write to Jellyfin sets that item's previous state, so no poll reads it as a Jellyfin change, even one whose read began before the write.

## Assumptions

- Marking a series or a season played in Jellyfin saves the user data of each episode
- One read of the whole library fits well inside the 2-minute interval. To be measured on the production server

## Contracts

- New config `JELLYFIN_SYNC_ENABLED` (default `false`, so a deploy never starts the first reconcile by itself), and `JELLYFIN_SYNC_INTERVAL` and `JELLYFIN_RECONCILE_INTERVAL`, Go durations, defaults `2m` and `1h`. No new table: the previous read and the last reconcile time live in memory
- Played writes use `POST /UserPlayedItems/{itemId}?userId=…&datePlayed=…` and `DELETE` of the same path

## Decisions

- Poll instead of a webhook. It needs no Jellyfin plugin setup and reuses the stored connection
- A full read and an in-memory diff, because Jellyfin 12.4 has no "changed since" filter for user data: `MinDateLastSavedForUser` filters on the item's own saved date
- Last write wins between marks, with no timestamps. Each side's change reaches the other within one poll
- biinge wins in the reconcile. The poll's goroutine runs it after a clean poll, so the two never race and it only overrides what the poll could not apply and biinge writes that never reached Jellyfin
- The API's own Jellyfin writes update the previous state, so they never read back as Jellyfin changes, even when a later biinge write fails
- Accepted risk: the previous read is lost on restart, so a Jellyfin mark made while the API is down is reverted by the first reconcile
- Checked on Jellyfin 12.4.0: a partial replay of a played item keeps `Played` true, and `datePlayed` sets `LastPlayedDate`
- The reconcile replaces a one-time backfill command: the first pass pushes biinge's full state
- A played episode is marked even when the show is `watched`, so the reconcile never reverts that Jellyfin mark
