repo: tab/biinge
branch: master

## Last sync
date: 2026-11-03T10:26:11Z

### Updated in this project
- Profile, Appearance and Statistics redesigned for iPhone; Statistics added for macOS and Apple TV; data colours and Statistics components in the Design System
- Website: new Home (two hero options), iPhone, Mac, Apple TV and About pages, read from docs/src (Astro site)
- Actions: audit and redesign of detail-page action buttons for movies, TV shows and games, read from GameDetailView.swift
- iPhone: library, details, series, episode sheet, action menu, Up Next, search, profile and empty states restyled with macOS/TV components
- macOS: Home, Movies, TV Shows, Series/Episodes, Movie Details, Collections, Continue Watching, Search overlay, Player states
- Apple TV: Home and Movie Details with remote-style focus navigation
- Larger type scale; posters cropped from docs/public/screens/poster-wall.jpg and the iOS LoginBackground image
- Archivo display font copied from docs/public/fonts

## Screen map
| Screen | Repo files |
|---|---|
| Biinge Mac.dc.html (M05–M16, M24) | ios/Biinge/Theme/Theme.swift, ios/Biinge/Theme/Typography.swift, ios/Biinge/Components/PosterImage.swift, ios/Biinge/Components/Badges.swift, ios/Biinge/Components/DetailComponents.swift, ios/Biinge/Screens/MovieDetailView.swift, docs/src/styles/global.css |
| Biinge Mac Player.dc.html (M17–M20, M25) | ios/Biinge/Theme/Theme.swift, docs/src/styles/global.css |
| Biinge TV.dc.html (T04, T06, T15) | ios/Biinge/Theme/Theme.swift, ios/Biinge/Components/PosterImage.swift, docs/src/styles/global.css |
| Biinge iOS.dc.html (I01–I14) | ios/Biinge/Screens/RootView.swift, MoviesView.swift, TvView.swift, GamesView.swift, MovieDetailView.swift, UpNextView.swift, SearchView.swift, ProfileView.swift, ios/Biinge/Components/Badges.swift, PosterGrid.swift, UpNextToolbar.swift, DetailComponents.swift, ios/Biinge/Theme/Theme.swift |
| Biinge Profile Stats.dc.html (P01–P03, M30, T30) | ios/Biinge/Screens/ProfileView.swift, ios/Biinge/Theme/Theme.swift, uploads/ app screenshots of Profile, Statistics, Appearance |
| Biinge Actions.dc.html | ios/Biinge/Screens/GameDetailView.swift, MovieDetailView.swift, TvDetailView.swift |
| Site Home / iPhone / Mac / Apple TV / About.dc.html, Site Header, Site Footer | docs/src/pages/index.astro, docs/src/pages/about.astro, docs/src/components/Hero.astro, Header.astro, Chapter.astro, Cta.astro, Footer.astro, docs/src/styles/global.css |
| biinge-data.js | docs/public/screens/poster-wall.jpg, ios/Biinge/Assets.xcassets/LoginBackground.imageset/background@2x.png |
