# iOS code layout by layer and platform plan

Feature: [feature.md](feature.md)

Status: implemented

Phase: code review

Current step: PR preparation, after the human check below

## Steps

1. Move every file into the layout, replacing per-file filters with per-platform folder exclusion
  - The depth check joins `make lint`
2. Rename files and types to the naming rules, and make the splits the layout lists
  - Per-platform scene files leave `App.swift` with only the iOS delegate adaptor's `#if`
3. Cut the logic-to-UI edges, and give the User-Agent the platform name
4. Shared detail models for list moves, series details state and play notes, used by all three apps
5. Shared models for paging, the Home load, the connect and login flows, and track labels
6. Shared components on Mac and Apple TV, and one `biinge*` color token set
7. Series naming in the API, the spec, the docs page and the iOS models that read them
  - The API part shipped in #38
8. The Jellyfin device ID in the Keychain, per-platform `Info.plist` keys and the tvOS icon
9. Coverage pass on the new shared models
10. Docs pass on `ios/CLAUDE.md` and `ios/README.md`

## Open human checks

- Run all three apps, and confirm nothing looks or behaves differently beyond what AC16 allows.
  - Tap Retry on the iPhone series details after a failed load.
