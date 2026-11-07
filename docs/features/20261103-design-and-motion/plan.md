# Design and motion plan

Feature: [feature.md](feature.md)

Status: in progress

Phase: code review

Current step: the human checks below

## Steps

1. The prototype theme and tokens, Archivo, pill filters, badges and the glass action sheet
2. The shared motion tokens, press feedback, Mac poster hover and Apple TV focus lift
3. Want and Watched feedback and the toast on every app, with the failure toasts
4. Poster to details on Mac and iPhone, and details to player on every app
5. The next-episode morph, the tracks panel page slide and menus on Mac and Apple TV
6. List removal with Undo, the pill slide and the iPhone and Apple TV sheets
7. The loading timing rule, details and list skeletons, and the poster fade-in
8. The Apple TV hero rotation
9. Buffering on iPhone and Mac
10. Log In loading and error states on every app

## Open human checks

- Run `make test:macos` from a terminal that can answer the Keychain prompt.
- Hand check all three apps in light and dark, with Reduce Motion on and off (AC1 to AC32).
- Walk the motion live on all three apps, and confirm it feels right (AC5 to AC24, AC31, AC32).
  - The Mac navigation lifecycle: normal Back, Back during the entrance, and the same title in two sidebar stacks.
  - Uncached poster arrivals.
- Capture screenshots or recordings of each moment, in light and dark, with Reduce Motion on and off.
