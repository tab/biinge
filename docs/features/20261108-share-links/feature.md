# Share links

## Goal

A user shares a movie, series or game from the app as a link. Anyone who opens the link sees a simple public page with the title's details.

## Why

The app has no way to send a title to someone else.
A public page per TMDB or IGDB id would let anyone fetch provider data through our API.
A stored share limits the public pages to titles a user chose to share.

## Scope

In:

- A `shares` table that records each share
- An authenticated endpoint that creates a share and returns its link
- A public HTML page per share, for desktop and mobile widths
- Open Graph tags so a pasted link shows a preview
- A page design that follows the apps' Details screens
- Expiry after 30 days without a visit, and a cleanup of expired shares
- A share button on movie, series and game details on iPhone and Mac

Out:

- A share button on Apple TV (tvOS has no share sheet)
- Revoking a share or listing a user's shares
- Visit counts or other analytics
- Opening the link in the app (universal links)
- Recommendations, the user's list or state, and Jellyfin data on the page
- Trailers and episodes on the page
- A Share button or any JavaScript on the page
- Provider credit on the page

## How it works

1. The user taps Share on a details screen.
2. The app sends the type and the provider id to the API.
3. The API checks the title exists at TMDB or IGDB and upserts the share.
4. The API returns the share id and its link, and the app opens the share sheet.
5. A viewer opens the link. The API looks up the share, renders the page and records the visit.
6. A periodic job deletes shares with no visit for 30 days.

## Acceptance criteria

- **AC1** – `POST /api/v1/shares` with a `type` of `movie`, `tv` or `game` and an `object_id` returns the share `id` and `url`.
- **AC2** – Sharing the same type and object again as the same user returns the same id.
- **AC3** – A re-share sets `visited_at` and `updated_at` to now.
- **AC4** – An object id that TMDB or IGDB does not know is rejected, and no share is stored.
- **AC5** – A request without a valid session is rejected.
- **AC6** – `GET /s/{id}` for a live share returns an HTML page with the title's details.
- **AC7** – A movie page shows the poster, a Movie label, the title, a meta line with release, runtime, genres and rating, and the overview.
  Below come facts for director, release date and status, then Cast & Crew.
- **AC8** – A series page shows the poster, a TV Show label, the title, a meta line with first air, season count, genres and rating, and the overview.
  Below come facts for creators, first air date and status, a Seasons list with each season's name, year and episode count, then Cast & Crew.
- **AC9** – A game page shows the cover, a Game label, the title, a meta line with release, play time and rating, and the summary.
  Below come facts for developers, release date and status, then Genres and Platforms as tags.
- **AC10** – A fact with no value is hidden.
- **AC11** – The page carries `og:title`, `og:description` and `og:image`.
- **AC12** – On a phone the page follows the iPhone Details screen: the poster centred above the text, and facts in two columns.
  On a desktop it follows the Mac Details screen: the poster beside the title block, with facts and Cast & Crew below.
- **AC13** – The page never shows who shared it.
- **AC14** – The page shows no TMDB or IGDB credit.
- **AC15** – A visit sets `visited_at` to now when the stored value is more than a day old.
- **AC16** – A share whose `visited_at` is more than 30 days old returns the not-found page.
- **AC17** – A malformed or unknown id returns the not-found page with status 404.
- **AC18** – The page response carries `Cache-Control: public, max-age=86400`.
- **AC19** – The public page is rate limited per IP.
- **AC20** – The cleanup job deletes shares whose `visited_at` is more than 30 days old.
- **AC21** – Deleting a user deletes their shares.
- **AC22** – Movie, series and game details on iPhone and Mac show a Share button.
  The button creates the share, then opens the share sheet with the link.
- **AC23** – A failed share request shows an error and opens no share sheet.
- **AC24** – A header shows the biinge app icon next to the biinge wordmark.
- **AC25** – The page has a blurred backdrop made from the poster, shows Cast & Crew photos in black and white, and runs no JavaScript.

## Contracts

- `shares`: `id UUID` (`uuid_generate_v4()`), `type share_type`, `object_id INTEGER`, `user_id UUID` (cascade on user delete), `visited_at`, `created_at`, `updated_at`
- `share_type` enum: `movie`, `tv`, `game`. Unique on `(user_id, type, object_id)`, indexed on `visited_at`
- `SHARE_URL` holds the public base of the link, and a link is `SHARE_URL/s/{id}`. It lives in the deployment compose file, like `CLIENT_URL`
- `SITE_URL` is optional. When set, the page logo links to the landing site

## Decisions

- The page lives in the API process, because the provider keys and the cache are there. A subdomain points at it through the reverse proxy
- The link is `<share host>/s/{uuid}`. A random id stops anyone from walking provider ids through our API
- The page reads provider data through the existing Redis entries, so it shares the 12-hour cache with the app
- Go `html/template` with an embedded template and inline CSS, and no JavaScript.
  The app icon ships embedded in the API binary
- The page mirrors the apps' Details screens, so a shared title looks the same in and out of the app
- Accepted risk: the page carries no TMDB or IGDB credit, although TMDB's terms ask for one where its data shows.
  The apps keep the credit in Profile
- A visit extends the share, so a link in active use never expires
- The visit write skips values less than a day old, so a busy link costs one write a day
- The 30-day window is a code constant, not configuration
