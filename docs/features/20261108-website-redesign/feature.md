# Website redesign

## Goal

The docs site follows the `Biinge Website` prototype: the Cinematic home, a page for each of iPhone, Mac and Apple TV, and a new About page.
Every image and loop on it comes from the real apps, and every claim matches what the code does today.

## Why

The site still describes the iPhone tracker.
Today Biinge also streams a Jellyfin library on iPhone, Mac and Apple TV, and watched marks sync both ways with Jellyfin.
The prototype in `design/prototype/` lays out pages for that product, but its copy describes the plan, not the shipped code.

## Scope

In:

- Home built from prototype variant 1a, Cinematic, in `Site Home.dc.html`
- iPhone, Mac and Apple TV pages from `Site iPhone`, `Site Mac` and `Site Apple TV`
- About rebuilt from `Site About`
- Header and footer from `Site Header` and `Site Footer`, on every page, Self-hosting and the API reference included
- Dark as the default theme, with the header toggle switching to light
- Screenshots and short screen recordings captured from the apps, in light and dark where the app has both
- Titles added to the capture account so the shots show good movies, shows and games

Out:

- Home variant 1b, Devices
- Content changes to the Self-hosting guide and the API reference
- App or API code changes. A capture that needs one stops the work for a decision
- A new Open Graph image
- An App Store link. The apps are built from the repository

## Assumptions

- The capture account is the `BIINGE_USER` account in `ios/.env` on the production API.
  It is a marketing account, so adding titles, marks and a Jellyfin connection to it is fine
- The Jellyfin user in `ios/.env` is connected to that account, and its library holds the titles the playback shots need

## How it works

1. Each page section takes its layout, order and copy shape from its prototype page.
2. A screenshot slot in the prototype gets a real capture from the matching app.
3. A motion moment shows a short muted recording that loops while it is on screen.
4. Each claim in the prototype copy is checked against `api/` and `ios/`. Wrong claims are rewritten to the current behavior or removed.

## Acceptance criteria

- **AC1** – Home shows the Cinematic hero: a blurred backdrop and a poster rotating through featured titles from the capture account.
- **AC2** – Home has the prototype's sections in order: platforms, Continue Watching, lists and library, TV progress, playback, games, Also in Biinge, open source.
- **AC3** – `/iphone/`, `/mac/` and `/apple-tv/` exist with the sections of their prototype pages, and the platform switcher links all three.
- **AC4** – `/about/` has the sections of `Site About`.
- **AC5** – The header links iPhone, Mac, Apple TV and About on every page and marks the current one.
- **AC6** – The footer links the platform pages, About, Self-host, API, GitHub and the license, and names no location.
- **AC7** – The site opens in dark.
  The toggle switches to light, the choice persists, and every capture shown matches the active theme where the app has both.
- **AC8** – Every prototype screenshot slot shows a real capture. No slot keeps a placeholder.
- **AC9** – Recordings are muted, loop while on screen and pause off screen.
- **AC10** – Under reduced motion, recordings and the hero rotation are replaced by a still frame.
- **AC11** – No capture or page shows an email address, account login, server address, hostname, Jellyfin server name, Jellyfin username or media file name.
- **AC12** – Every feature claim on the site matches current code.
  That covers two-way Jellyfin sync, the per-kind states, Up Next rules and Statistics.
- **AC13** – Every page fits a 390 px viewport with no horizontal scroll.
- **AC14** – `npm run build` in `docs/` passes.

## Decisions

- Dark is the default because the prototype is dark-first, and artwork and the player read best on dark
- Screen recordings over CSS reconstructions, so the motion shown is the apps' own
- Captures come from production because the local Jellyfin library is too thin for the playback shots
- No location in the footer, because the site stays free of personal details
