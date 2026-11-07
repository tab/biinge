# Layout and naming

The target file tree for `ios/Biinge/`, and the rules for naming files and types in it.
[feature.md](feature.md) holds the goal and scope.

## Rules

- `App/` holds the composition root. `Core/` holds logic with no SwiftUI, UIKit or AppKit import.
  `UI/` holds SwiftUI shared by all three apps, and `Platforms/<platform>/` holds one app's views
- Tests in `BiingeTests/` cover `Core/` and the shared value types in `UI/`, so no test needs a platform filter
- Pure logic that only one platform uses still lives in `Core/`, so its tests build everywhere
- A platform prefix (`Mobile`, `Desktop`, `TV`) is used only when another platform has a file in the same role.
  The prefix also stays when the bare name clashes with a shared type
- A screen file declares the type it is named for, prefix included. A helper type with a platform prefix uses its platform's prefix
- `App/App.swift` declares `BiingeApp`. A type named `App` would hide SwiftUI's `App` protocol.
  Each platform's `*Scenes.swift` supplies `var body: some Scene` in an extension
- `App.swift` keeps one `#if os(iOS)`, around `@UIApplicationDelegateAdaptor(AppDelegate.self)`.
  The adaptor must be a stored property of the `App` type, so no extension can carry it.
  `AppDelegate` itself lives in `Platforms/iOS/App/`
- Color tokens keep the `biinge` prefix, because bare names such as `.primary` and `.fill` clash with SwiftUI
- `TV` means Apple TV. A TV series is a `Series`, as in the API
- Outside `Platforms/`, `#if os` and `#if canImport` choose a value: a size, an edge, a font, a duration,
  an image source or the AppKit and UIKit color bridge. They never declare a view, a modifier or a type.
  The delegate adaptor in `App.swift` is the one declaration they wrap.
  `BrandBackground` picks its image as one value and keeps one view tree

## Tree

`←` names the file it comes from. *New* marks a new file and *split* a part carved out of an existing file.
A file without a mark moves unchanged.

```
ios/
├── Info.plist                    shared custom keys only (API_BASE_URL, SENTRY_*), and the Mac app's plist
├── Info-iOS.plist                new: the shared keys plus the iPhone's fonts, launch screen and orientation
├── Info-tvOS.plist               new: the shared keys plus the launch screen
└── Biinge/
    ├── App/
    │   ├── App.swift             ← BiingeApp.swift
    │   ├── Config.swift
    │   ├── Monitoring.swift
    │   ├── DeviceInfo.swift      new: the platform name for the User-Agent and the Jellyfin device
    │   └── Assets.xcassets       gains the tvOS app icon and Top Shelf image
    ├── Core/
    │   ├── Networking/   APIClient, APIError
    │   ├── Auth/         AuthManager, Keychain
    │   ├── Models/       Details, Library, Requests, Search, Stats, UpNext, User
    │   ├── Stores/       MovieStore, SeriesStore ← TvStore, GameStore, UpNextStore
    │   ├── Jellyfin/     JellyfinConnection, JellyfinConnection+Artwork, JellyfinService, BaseItemDto+Format
    │   ├── Playback/     PlaybackSession, PlaybackReporter, PlayResolution, PlayerChrome, SubtitleCue,
    │   │                 DeviceProfile+AVPlayer, SubtitleStyle (split from SubtitleOverlay), TrackLabel (new)
    │   └── Features/
    │       ├── Common/   LoadState, StackOrigins, SkeletonRows (split from Skeleton), Toast (split: model and copy)
    │       ├── Details/  DetailActions, DetailsTitle, SeasonEpisodes, NextEpisode, NextEpisodePick,
    │       │             ListChange (new), SeriesDetailsState (new), PlayNote (new)
    │       ├── Library/  ListEntry, PagedLibrary (new)
    │       ├── Home/     HomeHero, HeroRotation, HomeFeed (new)
    │       ├── Search/   RecentSearches
    │       └── Connect/  ConnectFlow (new), LoginFlow (new)
    ├── UI/
    │   ├── Theme/        Theme, Motion, Typography
    │   ├── Components/   Badges, BrandBackground, CachedImage, PieChartView, PlayFailure, PosterImage,
    │   │                 PressableStyle, SetupBackground, Skeleton, SubtitleOverlay,
    │   │                 ToastView (split from Toast), DetailBackdrop (split from DetailComponents)
    │   └── SplashView.swift
    ├── Resources/Fonts/      Archivo.ttf, OFL.txt
    └── Platforms/
        ├── iOS/
        │   ├── App/          MobileScenes (new), AppDelegate (split from BiingeApp: the rotation lock the player uses)
        │   ├── Navigation/   MobileRootView ← RootView, DetailNavigation
        │   ├── Screens/      MobileLibraryView ← LibraryView, MobileGamesView ← GamesView,
        │   │                 MobileSearchView ← SearchView, MobileStatisticsView ← StatisticsView,
        │   │                 MobileLoginView ← LoginView, MobileConnectView ← ConnectJellyfinView,
        │   │                 MobileMovieDetailsView ← MovieDetailView, MobileSeriesDetailsView ← TvDetailView,
        │   │                 MobileEpisodeDetailsView ← EpisodeDetailView, MobileGameDetailsView ← GameDetailView,
        │   │                 MobilePersonDetailsView ← PersonDetailView, MobilePlayerView ← PlayerView,
        │   │                 MoviesView, SeriesView ← TvView, UpNextView, ProfileView, PlayerTracksPanel
        │   └── Components/   CloseButton, DetailComponents, DetailMenuSheet, PillFilter, UpNextToolbar,
        │                     ErrorBanner, PosterGrid, CollapsingHeader
        ├── macOS/
        │   ├── App/          DesktopScenes (new: the Settings scene, commands, appearance and quit-on-close)
        │   ├── Navigation/   DesktopRootView, DesktopRoute
        │   ├── Screens/      DesktopHomeView, DesktopLibraryView, DesktopCollectionsView (split from MacCollectionView),
        │   │                 DesktopCollectionView, DesktopListsView ← MacListView, DesktopGamesView,
        │   │                 DesktopSearchView, DesktopStatisticsView, DesktopSettingsView, DesktopLoginView,
        │   │                 DesktopConnectView, DesktopMovieDetailsView, DesktopSeriesDetailsView,
        │   │                 DesktopEpisodeDetailsView, DesktopGameDetailsView,
        │   │                 DesktopPersonDetailsView ← MacPersonView, DesktopPlayerView, DesktopSubtitleStylePage
        │   └── Components/   DesktopDetailActions, DesktopNextEpisodeCard, PlaybackFullScreen,
        │                     MoreMenu, DetailsSkeleton, DetailsRows (all three split from MacMovieDetailsView),
        │                     PosterHover (split from Motion)
        └── tvOS/
            ├── App/          TVScenes (new)
            ├── Navigation/   TVRootView, TVRoute
            ├── Screens/      TVHomeView, TVLibraryView, TVCollectionsView, TVCollectionView, TVListsView,
            │                 TVGamesView, TVSearchView, TVStatisticsView, TVSettingsView, TVLoginView,
            │                 TVConnectView, TVMovieDetailsView, TVSeriesDetailsView, TVEpisodeDetailsView,
            │                 TVGameDetailsView, TVPersonDetailsView ← TVPersonView, TVPlayerView,
            │                 TVSubtitleStylePage, PlayChoice ← TVPlayChoice
            └── Components/   TVBackdropArt, TVNextEpisodeCard, DetailMenu ← TVDetailMenu, PillButtonStyle ← TVPillButtonStyle,
                              TVSetupButtonStyle
```

Every `Desktop*` file in the tree replaces the matching `Mac*` file.
`DesktopDetailActions` and `TVSetupButtonStyle` keep their prefix because `DetailActions` and `SetupButtonStyle` already exist.

The shared components replace `DesktopArtwork`, `TVArtwork`, `ProgressBar`, `TVPinBadge` and the inline Mac details backdrops.
`TVBackdropArt` replaces the art layer repeated in five Apple TV screens, and each screen keeps its own gradients.
The old copies are deleted.
