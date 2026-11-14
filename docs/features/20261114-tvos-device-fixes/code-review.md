# Code review

Mode: standard  
Gate: code  
Status: incomplete  
Round: 2  
Target: focused recheck of `c996d58` and `a00fd30` on `fix/tvos-device-fixes`  
Reviewer: codex  
Model: gpt-6.1-sol  
Effort: high

## Findings

### CODE-1 – Game posters still lose their sides in the list sheet

Severity: medium  
Status: open  
Location: `ios/Biinge/Platforms/tvOS/Components/DetailMenu.swift:110`

Finding: The new portrait frame fixes the wide crop, but does not guarantee the whole poster required by AC11. `TVGameDetailsView.swift:43` supplies an IGDB cover. IGDB recommends 3:4 covers, and its `1080p` image preset uses fit resizing. See the [cover guidelines](https://github.com/twitchtv/igdb-contribution-guidelines/wiki/Cover) and [image documentation](https://api-docs.igdb.com/#images).

`PosterImage.swift:33` delegates rendering to `CachedImage`, whose `.scaledToFill()` at `CachedImage.swift:136` fills the 400×600 frame before `PosterImage.swift:37` clips it. From this source trace, a 600×800 cover becomes 450×600 and loses 25 points from each side. Game artwork and edge lettering remain cropped despite the comment claiming it shows uncropped.

Suggested fix: Fit the loaded poster inside the tvOS sheet's portrait slot while preserving its aspect ratio. Verify with a 3:4 game cover whose edges are visible; preserve existing rendering elsewhere.

Reply: Partly accepted. The comment at `DetailMenu.swift:109` overclaimed, and it now says a 3:4 game cover loses a sliver at the sides, as in its hero. The fill stays. AC11 replaced a 640×360 crop that showed only the middle band of the poster. The fill keeps the full height and about 89 % of the width of a 3:4 cover. The game hero (`TVGameDetailsView.swift:101`, 440×660 fill) and every game poster row crop the same way, so the sheet matches the rest of the app. Fitting would add letterbox bars beside each game cover. The simulator shot of the Grand Theft Auto VI sheet shows the whole cover reading correctly.

Recheck: Still open because AC11 requires the whole game poster, and the reviewed code and Reply confirm that 3:4 covers remain cropped at the sides. The comment correction does not resolve the crop.

Human decision: Accepted risk. The human chose to keep the fill, so the sheet matches the game hero and the game poster rows. AC11 now reads "the portrait poster at full height".

## Checked

- Read the CODE gate preparation, checking, findings, reporting and handoff rules, including the review template.
- Read `CLAUDE.md`, `ios/CLAUDE.md`, the feature contract and current plan.
- Reviewed the complete feature diff, changed Swift views, relevant callers, image rendering, focus styles, platform exclusions and nearby tests.
- Confirmed Swift changes are confined to `Platforms/tvOS/`. The shared AccentColor change adds only `tv` entries; universal iOS gold and both macOS entries remain unchanged.
- Confirmed Home spacing changes leave the Collections grid and shared card style unchanged. Reviewed form validation and secure-field semantics, player focus handoff, Person header focus, episode styling and hero badge removal.
- Opened both Top Shelf poster-wall variants and verified all four dimensions: 1920×720, 3840×1440, 2320×720 and 4640×1440.
- Independently ran `cd ios && make lint`: PASS, 0 violations across 207 files.
- Ran `git diff --check master...HEAD`: PASS.
- Accepted the lead's supplied results: `make test:ios` and `make test:tvos` each passed 523 tests; iOS, macOS and tvOS builds passed.
- Accepted the lead's assetutil results confirming platform-specific accent renditions and simulator screenshot results for AC1, AC3 and AC5–AC12. These were not independently reproduced.
- Focused recheck of `c996d58`: the comment now describes the 3:4 crop; the crop itself remains as stated in CODE-1.
- Focused review of `a00fd30`: removes `.trackedBadge(...)` from the Mac Home hero poster. The feature contract now includes the Mac hero check in AC10 and allows this specific macOS change; the implementation matches that scope.
- Required evidence remains missing: `make test:macos` has not completed, and the human has not confirmed AC3, AC4, AC5 and AC12 on Apple TV.
- No additional concrete findings, comment-convention violations or orphaned code found. Working-tree status remains limited to the lead's uncommitted plan gate lines.

## Verdict

INCOMPLETE

Keep the gate unchecked until the required macOS test result and Apple TV confirmations are available. CODE-1 remains open.

Not checked: `make test:macos` or physical Apple TV behavior; the builds and simulator results above are lead-supplied.  
Risk: 3:4 game covers remain cropped, and the required device verification is unfinished.

Human evidence: The human ran `make test:macos` and confirmed AC3, AC4, AC5, AC10 and AC12 on the Apple TV and the Mac. Both pass.
