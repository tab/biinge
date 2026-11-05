# Jellyfin playback plan

Feature: [feature.md](feature.md)

Status: in progress

Phase: code review

Current step: the human checks below

## Steps

1. The connection endpoints in `APIClient`, and one connect, Not Now, reconnect and disconnect flow on every app
2. The Play rule through `DetailsPlay` and `PlayResolution`, with the notes under the actions
3. The next-episode pick on series details, with a Retry for a failed season behind it
4. The Mac player: the next-episode card, episode buttons, speed, subtitle style and error states
5. The Apple TV player: the next-episode card, one tracks panel with subtitle style, and error states
6. The iPhone player: controls, tracks, subtitle style, speed, the next-episode card and error states
7. The finished-play mark on every app
8. Settings and Profile: the account, the server state and the confirmations

## Open human checks

- Run `make test:macos` from a terminal that can answer the Keychain prompt.
- Upgrade the iPhone app over an existing install, without uninstalling it.
  - The login, the lists, episode progress, Games and Appearance survive the upgrade and a relaunch.
- Run all three apps against a real Jellyfin server, and walk AC1 to AC46 on each.
  - On iPhone, check light and dark.
  - On Apple TV, use the remote presses and check the rendered layouts.
- After each live run, follow the cleanup in [`ios/CLAUDE.md`](../../../ios/CLAUDE.md#live-runs).
