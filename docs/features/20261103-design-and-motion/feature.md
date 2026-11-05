# Design and motion

## Goal

iPhone, Mac and Apple TV share the prototype's look in light and dark.
Motion explains where things come from and go, and waits read the same on every app.

## Why

The apps build the screens of `design/prototype`, so they take its theme.
A state change that cuts from one frame to the next hides what happened.
A spinner that flashes or a silent revert leaves the user guessing.

## Scope

- The prototype theme in light and dark, Archivo titles and the iPhone restyle
- Shared motion curves and durations
- Press, hover, focus, Want and Watched feedback and toasts
- Morphs from poster to details, details to player, and into the next-episode card
- List removal with Undo
- Skeletons with the loading timing rule
- Log In states
- Buffering on iPhone and Mac
- A Reduce Motion version of each moment

## How it works

1. Motion reads its curves and durations from `MotionCurve` and `MotionDuration`.
2. A load past 300 ms shows a skeleton of its own layout, held at least 500 ms.
3. A pressed Log In keeps its title. It dims and locks with the fields until the login ends.
4. A removal hides the title at once and writes biinge when its Undo window closes.

## Acceptance criteria

- **AC1** – Every screen uses the prototype tokens in light and dark. Artwork and the player stay dark.
- **AC2** – iPhone large titles and section headers use Archivo. Mac and Apple TV use the system font.
- **AC3** – iPhone details use blurred-poster backdrops, badges and bottom sheets for Lists and More.
- **AC4** – Login and connect screens follow the system light and dark appearance.
- **AC5** – Every custom animation uses a shared curve and duration, or a timing the board names for that moment.
- **AC6** – A new input interrupts a running animation. No animation blocks a click, a tap or the remote.
- **AC7** – Buttons press to 97 %, Mac posters lift on hover, and Apple TV cards lift on focus.
- **AC8** – A list change pops its icon, and a move to Watched badges the poster.
- **AC9** – A poster opens details on Mac and iPhone by growing into them, and details return into the same poster.
- **AC10** – Play grows the artwork into the player over Morph on every app, and the controls arrive after it.
- **AC11** – The next-episode card shrinks the video to 42 % and slides in beside it on Mac and Apple TV.
- **AC12** – A removed list poster leaves, and the grid reflows.
- **AC13** – On iPhone and Mac, the toast offers Undo for 4 seconds, and Undo brings the title back unchanged.
- **AC14** – On Apple TV a removal writes at once, and its toast has no Undo.
- **AC15** – A logout during the Undo window sends nothing, and the title stays listed.
- **AC16** – A failed removal puts the title back and shows a toast.
- **AC17** – A failed add or move of a movie or series reverts it, and a toast says why.
- **AC18** – A move into Watched adds "Also marked played on <server>" to the toast when the server holds the title.
- **AC19** – A page skeleton never shows for a load under 300 ms, and stays at least 500 ms once shown.
- **AC20** – Movie, series and episode details load as a skeleton of their layout on every app.
- **AC21** – Episode lists, search results and Continue Watching show as many skeleton rows as their last load, up to one screen.
- **AC22** – Section titles stay text while their rows load.
- **AC23** – A poster from the network fades in, 40 ms apart over the first 12. A poster in memory shows at once.
- **AC24** – The Apple TV hero crossfades every 9 seconds and pauses while focus is below it.
- **AC25** – A pressed Log In keeps its title and dims and locks with the fields. It shows no spinner.
- **AC26** – A successful Log In keeps the form locked until the next screen shows. It shows no check.
- **AC27** – A failed Log In unlocks the form, rings the field at fault in red and shows the message under it.
- **AC28** – Typing in a field clears its ring and message.
- **AC29** – On Mac the fields shake once on a failed Log In, and on iPhone the error haptic plays.
- **AC30** – On iPhone and Mac a stall over 500 ms dims the picture and shows a spinner, and the controls keep working.
- **AC31** – With Reduce Motion on, each item uses the board's alternative.
- **AC32** – With Reduce Motion on, nothing shakes, scales, slides or shimmers, and spinners keep turning.
- **AC33** – The iPhone Profile shows an account card with the initial, name and email, and the Jellyfin row inside it.
- **AC34** – The Jellyfin row shows a green dot while this iPhone is connected, and a Connect pill while it isn't.
- **AC35** – Profile groups Statistics, Appearance, About, Privacy and Terms in one card, and Log Out sits apart below it.
- **AC36** – A return to a Library or list grid shows its items at once, and a background load keeps them on screen.
- **AC37** – A switch between collections cuts, so old posters never cross new ones. With Reduce Motion on, it crossfades.

## Contracts

| Curve    | Control points       | Use                             |
| -------- | -------------------- | ------------------------------- |
| Standard | 0.2, 0.7, 0.2, 1     | Entrances, hovers, toggles      |
| Exit     | 0.4, 0, 1, 1         | Things leaving                  |
| Focus    | 0.34, 1.36, 0.64, 1  | Apple TV focus and icon pops    |
| Linear   | 0, 0, 1, 1           | Progress that tracks time       |

Durations: Press 120, Quick 200, Standard 280, Emphasis 450, Morph 550 and Ambient 800 ms.

The board's own timings are the 150 ms menu exit, the 1.4 s shimmer and the 10 s countdown.
System menus, sheets and AVKit controls keep their own motion.

## Decisions

- A removal writes to biinge only when its Undo window closes, so a series keeps its episodes and pin on Undo.
- A removal that never commits, for example when the app quits first, leaves the title listed.
- Only the Apple TV hero moves on its own.
- Mac sidebar sections switch instantly.
- Apple TV has no buffering spinner of ours, because AVKit's player owns it.
- Jellyfin Connect keeps its connecting screen on every app.
- Archivo ships in the iPhone bundle under its open font license.
- The remembered row count lives in memory for the app's run. A first visit fills one screen.
- Each list's last first page lives in memory until a disconnect. A first visit loads as before.
- A collection switch differs from the board's 20 px shift. Only the pill moves.

## Details

- `design/prototype/Biinge Motion.dc.html` holds every timing, curve and Reduce Motion alternative.
- `design/prototype/biinge-theme.js` holds the light and dark tokens.
