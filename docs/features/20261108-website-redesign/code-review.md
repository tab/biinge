# Code review

Mode: standard
Gate: code
Status: passed
Round: 4
Target: 38464bd..ed1dccf
Reviewer: codex
Model: gpt-6-luna
Effort: high

## Findings

## Resolved

- CODE-1 – resolved: the reduced-motion change listener reloads recordings to their posters and blocks observer playback while reduction is enabled; disabling it resumes visible clips. The hero stops and returns to title 0. Supplied CDP probes passed for live and initial preference changes; removing either listener or the observer gate failed the probes.
- CODE-2 – resolved: the updated Home and iPhone copy qualify time-to-beat estimates with “when it has an estimate” / “when IGDB has one”; the `docs/src` search found no unqualified promise that every game has an estimate.

## Checked

- Rechecked only CODE-2 and its fix in `git diff ed1dccf..c3275ee -- docs/src`; the diff changes the Home games body and point in `index.astro`, and the Games card in `iphone.astro`.
- Searched `docs/src` for “time to beat.” All three matches are qualified to say estimates are shown when IGDB has one.
- Build passes at `c3275ee`, as reported for this review.
- Did not rerun the build or inspect other site areas. The recheck was limited to CODE-2’s copy and the requested search.

## Verdict

PASS
