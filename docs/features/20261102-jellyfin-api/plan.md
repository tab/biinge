# Jellyfin API plan

Feature: [feature.md](feature.md)

Status: implemented

Phase: code review

Current step: complete, shipped in #37 and #38

## Steps

1. Optional Jellyfin config, with the token key checked at startup
2. A Jellyfin client that signs in, signs out, reads the library and writes played state
3. Connection storage, and the connect, status and disconnect routes with the token encrypted at rest
4. A cached per-user library index that finds a movie, a series or an episode
5. `jellyfinId` on details, on season and episode reads, and on the movie and series lists
6. `genres` on movie and series details
7. Played writes for movie, series, season and episode marks and for deletes, on one ordered worker
8. The webhook, its token routes and its table removed
9. The routes and fields documented in the API spec and on the docs site
