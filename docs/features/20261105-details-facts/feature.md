# Details facts

## Goal

Movie, series, episode and game details show a block of facts on iPhone, Mac and Apple TV.
Titles in the Jellyfin library also show Audio, Subtitles and quality badges.

## Why

Details screens have no block with the director, creator or developer, the release date, the release status and the list.

## Scope

- `directors` on movie and episode details
- `creators` on series details
- `developers` on game details
- The facts block on iPhone, Mac and Apple TV
- Quality badges on movie and episode details

## How it works

1. The API returns the names with the details.
2. The client builds the facts for the screen and hides a fact with no value.
3. Each platform draws the block and the badges in its layout from `design/prototype`.

| Screen  | Facts, in order                                                 |
|---------|-----------------------------------------------------------------|
| Movie   | Director, Released or Releases, Status, Audio, Subtitles, List  |
| Series  | Created by, First aired or First airs, Status, List             |
| Episode | Director, Air date, Audio, Subtitles                            |
| Game    | Developer, Released or Releases, Status, List                   |

## Acceptance criteria

- **AC1** – Movie details return every director in TMDB order, each person once, with or without a photo.
- **AC2** – Episode details return directors by the same rule.
- **AC3** – Series details return the TMDB `created_by` names as `creators`.
- **AC4** – Game details return the IGDB companies flagged as developer.
- **AC5** – A cached series gets `creators` and a cached game gets `developers` on the next load.
- **AC6** – Each screen shows the facts in the table on iPhone, Mac and Apple TV.
- **AC7** – A fact with no value is hidden.
- **AC8** – An episode with no directors shows the series creators as Created by in place of Director.
- **AC9** – Audio, Subtitles and badges show only when the item is in the library and the server is connected and reachable.
- **AC10** – Audio reads as "English · 5.1", or "English · Dolby Atmos" for an Atmos track, from the default track or else the first.
- **AC11** – Subtitles read as "English" for one language and "English +2" for more, with each language once.
  The value stays on one line. A long name truncates at its end and the count stays visible.
- **AC12** – Released and Air date read as "1 Mar 2024" and keep their calendar day in every time zone.
  A movie or game date after today reads Releases in place of Released. The day is compared in UTC.
  A date of today reads Released.
- **AC13** – First aired follows the same rule as AC54.
  A series date after today reads First airs in place of First aired.
- **AC14** – List shows the list name or Not tracked.
- **AC15** – Badges follow the kind label, as in "Movie 4K HDR ATMOS".
- **AC16** – The resolution badge reads 4K from 2160 high or 3800 wide, and 1080p from 1080 high or 1900 wide.
- **AC17** – The HDR badge shows when the video range is neither SDR nor unknown.
- **AC18** – The ATMOS badge shows when any audio track has the Dolby Atmos spatial format or names Atmos in its profile or title.
- **AC19** – On Apple TV the block wraps onto a second row and keeps every fact whole.
- **AC20** – Status shows the release status of a movie, series or game, and is hidden when it is empty.
  Canceled reads "Cancelled", Returning Series reads "Returning", Post Production reads "Post-production"
  and In Production reads "In production". Any other status reads as sent.
  Released is hidden, as the date row says it.

## Contracts

- `GET` movie details: optional `directors: [string]`
- `GET` episode details: optional `directors: [string]`
- `GET` series details: optional `creators: [string]`
- `GET` game details: optional `developers: [string]`

Each field is omitted when empty, on fallback and on create and update responses.

## Decisions

- The Apple TV movie badge rules move to `Core`, and every platform uses them.
