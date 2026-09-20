# Biinge docs

Landing site for [biinge](../README.md), built with Astro and published to
GitHub Pages: the marketing pages, an about page, a self-hosting guide, and an
API reference with a live playground.

## Requirements

- Node 22 (the version CI installs)

## Configuration

Copy `.env.example` to `.env` (gitignored) and set the values for the site you
deploy:

```sh
cp .env.example .env
```

| Variable              | Purpose                                                              |
| --------------------- | -------------------------------------------------------------------- |
| `SITE_URL`            | the site's own origin, no trailing slash                             |
| `PUBLIC_API_BASE_URL` | default target of the API playground on `/docs/api`, origin only      |

Both are optional. `astro.config.mjs` reads `SITE_URL` through Vite's
`loadEnv`, and leaves `site` unset when it is empty, so a local build works
without it and just leaves the canonical and Open Graph URLs relative. The
playground falls back to `http://localhost:8080` when `PUBLIC_API_BASE_URL` is
unset.

Neither name holds a value in the repository. CI reads both from GitHub Actions
repository variables, which is what keeps the production domain out of the
tree. An unset variable arrives as an empty string rather than absent, so the
config treats empty as unset.

## Development

```sh
npm install
npm run dev       # http://localhost:4321
npm run build     # writes dist/
npm run preview   # serve the built dist/
```

`npm run build` is the verification loop for this directory. Run it at the end
of every change.

## Structure

```
src/
  pages/        one file per route: index, about, self-hosting, docs/api
  components/   the page sections (Hero, Chapter, DeviceFlow, StateRing, ...)
  layouts/      Layout.astro, which owns head, canonical and Open Graph tags
  styles/       global.css
public/         fonts, icons, Open Graph images, and the screenshots under screens/
```

`src/pages/docs/api.astro` keeps its own hand-written endpoint list. It does not
read `../api/api/swagger.yaml`, so a contract change touches both files. See
[api/CLAUDE.md](../api/CLAUDE.md).

## Deployment

The `Docs` job in `.github/workflows/release.yaml` builds and deploys the site to GitHub Pages.

