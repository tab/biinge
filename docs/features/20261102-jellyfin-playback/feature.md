# Jellyfin playback

## Goal

iPhone, Mac and Apple TV connect the user's Jellyfin account and play what the library holds.
A finished play shows as Watched in biinge and in Jellyfin.

## Why

Lists live in the biinge API and media lives in Jellyfin.
Every app needs the same connect flow, the same Play rule and a player built for its input.
Every failure the user can hit says what went wrong and offers a way to retry.

## Scope

- One connect, reconnect and disconnect flow on every app
- One Play rule for details, Home cards and poster menus
- A player on each app, with tracks, subtitle style and the next-episode card
- Error states with Try Again for Play and playback
- The finished-play mark

## How it works

1. After biinge login, the connect screen reads `base_url` from `GET /accounts/integrations/jellyfin/connection`.
2. It shows the server name from Jellyfin's public system info and asks for a username and password.
3. Connect signs in to Jellyfin for this device's token, then sends the same credentials to the API.
4. Details show Play only when the API returns a `jellyfinId`. Play loads that item and streams it.
5. A play that stops fetches the item again. Jellyfin's played flag on it decides a finished play.
6. A finished play writes the biinge Watched mark through the stores.

## Acceptance criteria

- **AC1** – After biinge login, Mac and Apple TV show the connect screen until a connection exists or Not Now skips it.
- **AC2** – iPhone shows Connect Jellyfin after a login. A restored session opens the tabs.
- **AC3** – iPhone connects from Profile in a sheet at any time, and from details through Connect….
- **AC4** – The connect screen shows the server name and has no address field.
- **AC5** – Biinge connects only over https.
- **AC6** – A failed API connect ends the new device session and keeps nothing.
- **AC7** – Cancel while connecting returns to the form, and the sign-in in flight opens nothing.
- **AC8** – An unreachable server shows the reason with Try Again and Not Now.
- **AC9** – An instance without Jellyfin shows "No Jellyfin server" with Not Now.
- **AC10** – Not Now opens the app until the next launch.
- **AC11** – Disconnect asks for confirmation, and the user stays logged in to biinge.
- **AC12** – Disconnect ends the device session and clears the API connection.
- **AC13** – A failed API disconnect shows a Try Again on the connect screen.
- **AC14** – Reconnect opens the connect screen with the username filled in, and the API connection stays.
- **AC15** – Mac and Apple TV Settings and iPhone Profile show the account email and the server state.
- **AC16** – Log Out asks for confirmation on Mac and Apple TV. It acts at once on iPhone.
- **AC17** – A 401 from Jellyfin disconnects the device.
- **AC18** – Details offer Play, Resume or Play Again only when the title has a `jellyfinId` and the device is connected.
- **AC19** – A connected device shows "Not on <server>" for a title without a `jellyfinId`.
- **AC20** – A device without a connection notes "Jellyfin isn’t connected on this <device>".
- **AC21** – iPhone adds Connect… to that note, and Mac adds Connect Jellyfin. Apple TV shows the text only.
- **AC22** – An unreachable server disables the play and shows "Can’t reach <server>".
- **AC23** – Details note a title Jellyfin has played and biinge doesn't hold as Watched.
- **AC24** – Mac and iPhone offer Add to Watched on that note.
- **AC25** – A movie or an episode plays outside details only when its own biinge details carry a `jellyfinId`.
- **AC26** – A series never plays directly. It opens details, which offer an episode.
- **AC27** – Series details offer the first aired episode biinge doesn't hold as watched.
- **AC28** – Caught up or fully watched, series details offer episode 1 of the first regular season.
- **AC29** – Series details name a season the server lacks, and the air date when the user is caught up.
- **AC30** – A failed season load behind that offer shows "Couldn’t load season N" with Retry.
- **AC31** – Playback resumes at the position Jellyfin stores, and Start Over plays from zero.
- **AC32** – The player switches audio and subtitle tracks in one panel on every app.
- **AC33** – Subtitle style sets size, weight, background (none, shadow, box), position and a timing offset, with Reset.
- **AC34** – Subtitle style is one setting for the device, edited only in the player.
- **AC35** – A subtitle track that fails to load says so in the track list.
- **AC36** – iPhone and Mac controls hide after 3 seconds without input while playback runs.
- **AC37** – The iPhone player pauses, seeks and skips 10 seconds, and offers speed and the next episode.
- **AC38** – The Mac player has previous and next episode buttons and a speed menu from 0.5× to 2×.
- **AC39** – Apple TV uses AVKit's transport bar with an Audio & Subtitles action, and Next Episode when the server holds one.
- **AC40** – In an episode's last 30 seconds, a card offers the next episode the server holds.
- **AC41** – The card counts down 10 seconds and plays it. Play Now skips the wait, and Cancel stops it.
- **AC42** – The last episode, or a next episode the server doesn't hold, gets no card.
- **AC43** – A failed Play shows the reason in an alert with Try Again.
- **AC44** – A playback error shows the reason with Try Again from the same position.
- **AC45** – A play Jellyfin reports as played marks the movie or episode Watched in biinge, and the lists update.
- **AC46** – An episode biinge already holds as watched writes nothing and refreshes the show's progress.

## Contracts

- Biinge owns identity, lists, tracking and the catalog.
- Jellyfin owns media, permissions, playback position, sessions and devices.
- The Jellyfin address comes only from the API.
- Disconnect on one device clears the API connection for the whole account.
- The device token decides what a device shows. The app doesn't compare it with the API connection.

## Decisions

- Jellyfin's played threshold decides a finished play, so biinge and Jellyfin agree on it.
- The next episode comes from season and episode numbers, never from watched progress.
- It is the next number in the season, or episode 1 of the next season. Specials never cross into regular seasons.
- Not Now lives in memory only.
- The player and artwork stay dark in light mode.

## Details

- The [design brief](../../../design/brief.md) and the player prototypes in [`design/prototype`](../../../design/prototype/).
- The connection endpoints in [`swagger.yaml`](../../../api/api/swagger.yaml).
