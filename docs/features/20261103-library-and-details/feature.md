# Library and details

## Goal

iPhone, Mac and Apple TV show the user's lists, search, people, details and Games from the biinge API.
They mark what the Jellyfin library holds, and they browse that library.

## Why

Lists and the catalog live in the biinge API, and the library lives in Jellyfin.
A title the user tracks but the server doesn't hold still needs a home on every app.
A failed load must never look like an empty list.

## Scope

- Lists and Games on every app, with availability and resume bars
- The Library pill on iPhone, and library grids with filters on Mac and Apple TV
- Search and people from the biinge API
- One details screen per kind, with the white pill, the list menu and More
- Home on Mac and Apple TV, and Up Next on iPhone
- The Mac sidebar library card
- Statistics on every app and Collections on Mac and Apple TV

## How it works

1. Lists come from `MovieStore`, `SeriesStore` and `GameStore`. Search, people and details come from the biinge API.
2. A list entry, a search result and a library poster open the same details screen by TMDB ID.
3. A library poster finds its TMDB ID in Jellyfin's provider IDs.
4. A list read carries `jellyfinId`, and one Jellyfin resume read covers every resume bar.
5. A failed request keeps what's on screen and adds an error line with Retry.

## Acceptance criteria

- **AC1** – The Mac sidebar lists Want to Watch, Watching and Watched with counts from biinge.
- **AC2** – The Mac sidebar has a Games group with Want to Play, Playing and Played, with counts.
- **AC3** – Apple TV has a My Lists tab and a Games tab with those lists as poster rows.
- **AC4** – My Lists shows a banner with Connect Jellyfin while Jellyfin isn't connected.
- **AC5** – iPhone Movies has Want, Watched and Library pills, and TV adds Watching. Games has Want, Playing and Played.
- **AC6** – iPhone and Mac lists sort by date added and by title.
- **AC7** – On a connected device, a list poster without `jellyfinId` shows "Not on <server>" on iPhone and Mac.
- **AC8** – On Apple TV that poster shows a circle-slash mark.
- **AC9** – A list poster with a resume position shows a bar.
- **AC10** – On a disconnected device, list posters show plainly.
- **AC11** – An empty list shows its own empty text.
- **AC12** – A failed list, season, Home, library or search load shows an error with Retry, never the empty text.
- **AC13** – A failed refresh keeps the posters already loaded.
- **AC14** – A failed positions load keeps the bars and shows "Couldn’t load playback positions" with Retry.
- **AC15** – The Mac list context menu offers Pin or Unpin, Watched or Unwatched, and Remove. Watched offers no pin.
- **AC16** – The iPhone Library pill shows Continue Watching, Recently Added and the full grid.
- **AC17** – The Library grid sorts by title, date added and year.
- **AC18** – Library has a state for loading, empty, not connected with Connect in Profile, and unreachable with Try Again.
- **AC19** – Mac and Apple TV library grids filter by played state and genre, and sort.
- **AC20** – A failed genre load shows "Genres unavailable" with Retry, and the grid stays.
- **AC21** – A failed later page shows "Couldn’t load more" with Retry.
- **AC22** – Without Jellyfin, the Mac and Apple TV library sections ask to connect.
- **AC23** – Search returns movies, shows and people from the biinge catalog, whether the server holds them or not.
- **AC24** – iPhone search also returns games.
- **AC25** – Mac and Apple TV search show up to 8 recent searches before typing.
- **AC26** – A person page shows the bio and filmography, and each title opens its details.
- **AC27** – Details hold a white pill, a list button and More when it has an entry.
- **AC28** – With no play to offer, the white pill reads Add to Want to Watch while the title sits in no list.
- **AC29** – The list menu picks a list, pins to Up Next on a pinnable list, and removes the title from its list.
- **AC30** – On Mac, ⇧⌘U marks Watched and ⌘P pins, with the menu closed.
- **AC31** – More offers Start Over for a stored position, and Mark Season N Watched on series. iPhone adds Watch Trailer.
- **AC32** – Movie and series details show genres for titles the server doesn't hold.
- **AC33** – An episode opens details with the full synopsis, progress, Play or Resume, and Watched.
- **AC34** – Every episode with a resume position shows a progress bar in the season list.
- **AC35** – A list change on details updates the lists and counts without a reload.
- **AC36** – Game details move a game one list forward with the white pill, on every app.
  On an unreleased or cancelled game the pill stops at Want to Play, and the list menu still offers Playing.
- **AC37** – Game covers in the Mac and Apple TV lists open their details.
- **AC38** – Mac Home section headers link to their full list through See All.
- **AC39** – A click on a Mac Home card opens details and never plays.
- **AC40** – The Mac and Apple TV featured row holds up to five titles with page dots.
- **AC41** – A movie, episode or season marked Watched leaves Continue Watching and the next-episode button at once.
  A series moved to Watched leaves them on a load after Jellyfin reports its episodes played.
- **AC42** – A late Jellyfin answer doesn't bring that title back.
- **AC43** – iPhone Up Next shows Jellyfin's Continue Watching and Next Up above the tracked queue.
- **AC44** – With the library unreachable, the Mac sidebar shows "Can’t reach your library" with Retry.
- **AC45** – After Not Now, the Mac sidebar shows "Library not connected" with Connect….
- **AC46** – While connected and reachable, the Mac sidebar shows no card.
- **AC47** – Retry keeps its size and shows a spinner while it checks. An answer clears the card.
- **AC48** – Settings opens from the Global section of the Mac sidebar.
- **AC49** – Library titles with no TMDB ID show in the grids and open no details.
- **AC50** – Statistics opens from Profile on iPhone, Settings on Apple TV and the sidebar on Mac.
- **AC51** – Statistics has Week, Month, Year and All periods, each with its own total, activity chart and highlights.
- **AC52** – A period shows a spinner until its own numbers load, never another period's.
- **AC53** – Mac and Apple TV Collections lists the Jellyfin collections in a grid, and a collection opens its movies and shows.
- **AC54** – A movie, series or game release from the last six months or the future shows its full date, and an older one shows its year.

## Contracts

- Unreachable means a transport error or an HTTP 502, 503 or 504 from a Jellyfin call.
- Transport errors are no host, no connection, a timeout and a lost connection.
- A 401 means the token was revoked, and the device disconnects.
- A poster shows the check while its title or game is on any biinge list, read from the live stores.
  Jellyfin's played state and a response's state never set it. A title on no list shows none.
  Lists, Games and Up Next show no check, as every title there is on a list. Continue Watching and Next Up cards show none.
  Details show the biinge mark.

## Decisions

- Lists and the library stay apart on every app.
- List availability can lag the library by up to 10 minutes, as it shares the API's index.
- `JellyfinConnection` holds the reachability state, and the live `JellyfinService` reports each call's outcome to it.
- Retry sends Jellyfin's public system info request, which needs no sign-in.

## Details

- The [design brief](../../../design/brief.md) and the screen prototypes in [`design/prototype`](../../../design/prototype/).
