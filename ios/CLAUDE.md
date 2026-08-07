# ios

SwiftUI client, iOS 26 and Swift 6. See `README.md` for setup and commands.

## Structure

`Biinge/` is grouped by concern: `Auth/`, `Networking/`, `Models/`, `Stores/`,
`Screens/`, `Components/`, `Navigation/`, `Theme/`. The entry point is
`BiingeApp.swift`.

- `Stores/` (`MovieStore`, `TvStore`, `GameStore`) are `@MainActor @Observable`
  classes holding the user's library — want, watching, watched for screen media,
  want, playing, played for games. Anything that changes library state goes
  through a store so every screen sees it
- Screens call `APIClient` directly for read-through data the library doesn't
  own: TMDB detail, search, trending, Up Next
- `Networking/APIClient.swift` is the single seam to the API
- One third-party dependency, sentry-cocoa, confined to `Monitoring.swift`.
  Keep it confined; everything else is first-party

## The backend contract

`../api/api/swagger.yaml` is the documentation for the API: every path, query
parameter, request body, response shape and status code. Read it before adding
or changing a call in `APIClient`, and match `Models/` to the serializer shapes
it defines — don't infer a shape from a neighbouring model or from a response
observed at runtime. It's kept current with the API by the same commit that
changes it.

## Configuration

`.env` (gitignored) → `Scripts/inject-env.sh` → `Info.plist` → `Config.swift`.
Read hosts and keys from `Config`, never hardcode them in a view or client. The
injection script fails the build when a value doesn't land, so a misconfigured
build can't quietly fall back to localhost.

`.env` is edited by hand to switch between local and production — there is no
build configuration that switches it, and Debug/Release doesn't either.

## Verification loop

`make lint`, then `make test`, at the end of every change. Tests are the
`BiingeTests` target and run on a simulator, so they need Xcode 26 and an iOS 26
runtime. When the simulator isn't available, say the change is unverified rather
than calling it done.
