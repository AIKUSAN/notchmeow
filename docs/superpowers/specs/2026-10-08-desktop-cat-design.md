# Sub-project H: the desktop cat

**Status:** design approved in chat on 2026-10-08, section by section. This is the written spec for review.
**Parent spec:** `docs/superpowers/specs/2026-10-03-notchmeow-design.md` (sub-project H). **Builds on:**
- sub-project A (`docs/superpowers/specs/2026-10-04-cats-in-app-design.md`): the cats' look, motion, personality, collars, sleep and theme;
- sub-project B (`docs/superpowers/specs/2026-10-08-display-modes-kittens-design.md`): the display modes, the cast, the kittens and the small eyes.

Both are merged on both apps, and this document doesn't repeat them.

**Inspired by** upstream Coucou 0.1.6's desktop pet (`2b02b91`, Mac only), whose rules are rewritten here for NotchMeow's cats and both apps. Nothing of its character or names comes across.

## Goal
Let the user drag the big cat out of the notch and keep it on the desktop as a companion. There it watches the cursor, dances to music and sleeps. It flies back into the notch when an approval or a question needs the user, then returns to its spot. It costs almost nothing while it sits there.

## Decisions

| Topic | Decision |
|---|---|
| Which cat | **The big cat, keeping its role.** One desktop cat at a time, showing exactly what the big cat shows in the notch: One cat mode, the Main cat; A cat for each agent, the focused agent's cat (its coat follows the focus); Two cats, cat 1 (Momo stays in the notch). |
| The notch meanwhile | **The cat moves out:** the big cat's spot in the notch is empty while the cat is on the desktop. The pills, the grid and Two cats' cat 2 stay as they are. There are never two copies of one cat. |
| Layer | **Floats above windows** on every Space, like a sticker. Clicks pass through everywhere except the cat's body. It steps aside over fullscreen apps. |
| Clicks | **A click opens the island** at the notch, with a happy reaction. **A double-click sends it home.** Drag moves it. The right-click menu has Open the notch, Send home and Size ▸. |
| What travels with it | Its coat, motion, personality, eyes, cursor-watching, music dance and sleep, **plus the state badge, its agent's kittens and its collar**. |
| Size | **Small Ø48, Medium Ø64 (default) or Large Ø96**, from its right-click menu, remembered. |
| Frame rate | **Adaptive**: 60 fps only during motion, 20 fps while an agent works or the cursor is near, 5 fps idle, a slow breath asleep, nothing when it can't be seen. Target: under 1 % of a core while idle. |
| Controls | Drag out of the notch, plus a **menu-bar item**, a **Settings → Cat switch** and, on the Mac, **⌃⌥D** (on by default). |
| Approach | **Contract first, then both apps in parallel**, as in A and B. H-0 adds the rules and fixtures to `cat-core.js` and the prototype, then a Mac plan and a Windows/Linux plan replay them. The Mac gets at least what Windows/Linux gets. |
| Never restyle | The island, the pills and every existing view look exactly as they ship. The only change in the notch is the empty big-cat spot while the cat is out. |

## 1. The trip

**States** (one machine, pure, in `cat-core.js`):

| State | Meaning |
|---|---|
| `home` | In the notch, as today. Nothing on the desktop. |
| `flyingOut` | Travelling from the notch spot to its desktop spot. |
| `onDesktop` | Living on the desktop. |
| `retracting` | Flying back to the notch because an approval or question arrived. |
| `atNotchForAlert` | Sitting in its notch spot while the user answers. |
| `returning` | Flying back out to its desktop spot after the alert cleared. |
| `flyingHome` | Flying back to the notch because the user sent the cat home (a double-click, the menu, the menu-bar item, ⌃⌥D or the switch). |

`desktopStep(state, event)` moves between them on these events:
- `dragOut{spot}`: the big cat dropped on the desktop;
- `move{spot}`: the desktop cat dragged to a new spot;
- `toggle`: the menu item, ⌃⌥D or the switch;
- `sendHome`: a double-click, the menu, the switch off, or the cat dropped on the notch;
- `alertOn`, `alertOff`, `flightDone`;
- `launch`: after the greeting, if it was out;
- `screensChanged`.

An alert that clears mid-flight turns the cat around. A `sendHome` during an alert ends the trip at home. Events that make no sense in the current state change nothing.

**Getting it out.**
- Drag the big cat out of the notch and drop it on empty desktop.
  - On the Mac, dropping it on another app's window still attaches that window to a chat, as today. Only a drop on no window places the cat.
  - The App Store build has no attach, and neither does Windows/Linux, so there any drop places the cat.
- The menu-bar item, ⌃⌥D and the Settings switch fly it to its remembered spot. The first time, that's a default spot below the notch, a third of the way down the main screen, right of centre.

**Bringing it home:** a double-click, "Send home" in its menu, the menu-bar item, ⌃⌥D, the switch, or dropping it back on the notch.

**Alerts.**
- When `pendingApproval` or `pendingQuestion` becomes set, the cat gives the surprised emote, then flies into its notch spot. The user answers in the notch as today.
- When both are clear, it flies back to its spot. An approval that lands while the cat is home doesn't take it out.

**The flight:** an arc from the notch spot to the desktop spot, eased, about 0.6 s, with the cat at full size the whole way. The path and its timing are a pure function in the core: `desktopFlightAt(from, to, t)` gives the position and scale at `t` (`flightAt` is the file catch's flight).

**Remembered:**
- Whether it's out, its size and its spot.
- The spot is stored per screen arrangement, so a laptop alone and a laptop with a monitor each keep their own spot. The key is `screenKey(screens)`, built in the core from the connected screens' frames, sorted so their order doesn't matter.
- `clampSpot` keeps the cat's head 24 pt inside the visible frame, never under the menu bar or the Dock. A spot whose screen is gone moves to the main screen's default spot.
- At launch, after the greeting, a cat that was out flies back out.

## 2. On the desktop

**What it shows.** It's the big cat, drawn by the same renderer at full detail: whiskers, stripes, fur lines if they're on, and realistic eyes. Small eyes are a notch-only look below Ø28, so they never apply here. It keeps:
- **The state badge** of its role.
- **Its agent's kittens:** up to 3 beside it, then "+N".
  - The slots come from a new place, `DESKTOP_KITTEN_PLACE`, measured in the cat's diameter so they scale with its size, through `desktopKittenSlots(kittens)`.
  - That function uses the same slot maths as B's `kittenSlots`. It's a separate constant, not a new entry in B's `KITTEN_PLACES`, because both apps copy and pin that table.
  - B's rules for kittens are unchanged.
- **The collar** in the working agent's colour, if collars are on.
- **Cursor-watching:** on the Mac and Windows it looks wherever the cursor is. Wayland gives an app the cursor only over its own surface, so on Linux it looks ahead unless the cursor is over the cat.
- **The music dance** (Mac, Apple Music).
- **Sleep:** the existing ten-minute rule, with the sweep of stale kittens that B attached to it. A hover or a click wakes it, with zoomies in Playful.

**Sizes:** Ø48, Ø64 (default) or Ø96 (`DESKTOP_SIZES`), picked in its right-click menu and remembered. The window around the cat is sized for the cat, its badge and its kittens, and no larger.

**Clicks.**
- **Click:** the happy emote, and the island opens at the notch, like a click on the notch.
- **Double-click:** it flies home. A single click waits one double-click interval before acting, so a double-click never also opens the island.
- **Drag:** move it. On release the spot is clamped and saved.
- **Right-click menu:** Open the notch, Send home, Size ▸ Small, Medium, Large, and on the Mac a line showing ⌃⌥D.
- **Hit-testing:** only the cat's body takes the mouse; everything else passes through. The body is the head circle plus the badge and kitten slots.

**Not on the desktop cat:** dropping files on it (files still go to the notch), the slap, and the hairball.

## 3. Frame rate, CPU and the platforms

**The rule** (`desktopFps(input)`, pure, in the core):

| When | Frame rate |
|---|---|
| Dragging, flying, an emote, a kitten arriving or leaving, the dance | 60 fps |
| An agent working, thinking or searching, or the cursor within 150 pt of the cat | 20 fps |
| Idle and awake | 5 fps |
| Asleep | a still frame, redrawn for a slow breath every 2 s |
| Screen asleep or locked, display off, covered by a fullscreen app, `home` | 0 |

The app's loop reads the target and skips frames to meet it. Nothing new polls: the Mac watches the cursor with a mouse-moved event monitor that exists only while the cat is out, not upstream's 60 Hz timer. The notch's own rule (0 % CPU while the island is hidden) is unchanged. A bench (`render-cats.sh --bench-desktop` on the Mac, the `?dev` page on Windows) measures each rate. Target: under 1 % of a core idle and awake, and about 0 % asleep.

**Mac:**
- A borderless, non-activating floating `NSPanel` that is never key, so it never steals focus.
- It joins all Spaces, stays out of fullscreen Spaces (fullscreen auxiliary off), and is excluded from the window cycle.
- Click-through follows the body's shape.
- It's in Debug, Release and App Store builds; `check-app-binary.sh` keeps passing.

**Windows:** a second transparent, borderless, always-on-top Tauri window, skipped in the taskbar. It takes the mouse only over the body, with the same click-through mechanism as the island.

**Linux:**
- On compositors with layer-shell (KDE Plasma, COSMIC, Hyprland, Sway and other wlroots), the cat is an overlay-layer surface placed with margins.
- On GNOME, where the island is already a regular window, it's a small always-on-top window. GNOME may ignore the position, so there the spot is remembered only where the system honours it, and Settings says so under the switch.

**Storage:**
- Mac UserDefaults: `cat.desktop.on` (Bool), `cat.desktop.size` (`small`/`medium`/`large`) and `cat.desktop.spots` (JSON: screen-arrangement key to spot).
- Windows/Linux: the same three fields as the `desktop` object of the `cat` block of `settings.json`.
- Both go through `cleanDesktopSettings`, a clean-up of its own, so `settings-cases.json` and `display-cases.json` stay byte for byte. Windows' Rust `sanitized` keeps them, as it keeps B's keys.
- An unknown size is `medium`, a bad spot is dropped, and a bad `on` is `false`.

**Frozen IDs:** the size IDs `small`, `medium` and `large`, and the shortcut action ID `desktop`. They are contract values like the cat and mode IDs.

**Controls:**
- **Menu-bar item** (the tray menu on Windows and Linux): "Cat on the desktop", which becomes "Bring the cat home" while it's out.
- **Settings → Cat:** a "Cat on the desktop" switch under the Display picker, with the GNOME note where it applies.
- **⌃⌥D:** the `desktop` action in `ShortcutLogic`, on by default, listed in Settings → Shortcuts and tested by `scripts/test-shortcuts.sh`.

## 4. Build order, testing and checkpoints

1. **H-0, the contract** (one worktree session, Sonnet 5.5 at medium effort):
   - **The rules in `cat-core.js`:** `desktopStep`, `desktopFlightAt`, `desktopFps`, `clampSpot`, `screenKey`, `spotFor`, `DESKTOP_SIZES`, `cleanDesktopSettings`, `DESKTOP_KITTEN_PLACE` and `desktopKittenSlots`.
   - **Only new names.** H-0 changes no existing constant or function that the apps copy or pin (`KITTEN_PLACES`, `SMALL_EYE`, `kittenSlots`, the cleaners), so both apps stay green on `notchmeow/rebrand` until their H plans land.
   - **Fixtures:** one new file, `desktop-cases.json`, which also holds the desktop kitten slots. Every existing fixture stays byte-identical (`check-fixtures-additive.mjs`).
   - **Prototype:** a mock desktop with the cat. You can drag it out, see the flight, fire an alert, change size and watch the frame-rate readout.
   - **Owner checkpoint:** the prototype in a browser, plus a strip of the three sizes with badge and kittens.
2. **H-mac and H-tauri, in parallel** (worktree sessions, Sonnet 5.5 at high effort), each in this order:
   1. the settings and the clean-up port;
   2. the window or panel and its click-through;
   3. dragging out, the flight and sending home;
   4. alerts;
   5. what it shows: badge, kittens, collar, eyes, dance and sleep;
   6. the frame-rate rule and the bench;
   7. the menu-bar item, the Settings switch and, on the Mac, ⌃⌥D;
   8. docs.

   Three owner checkpoints each:
   1. pictures of the cat at S, M and L on a desktop mock, and the Settings switch;
   2. the alert flight as a strip of frames, and the frame-rate bench numbers;
   3. sign-off, then `nm-reviewer-deep` over the whole branch.

   Everything is checked without launching the app: sheet programs on the Mac, and the Vite dev server with a headless browser on Windows.
3. **The owner's real-build checks** at the end: drag out and home, an alert's flight and return, Spaces, a fullscreen app, two monitors (unplug one), sleep and wake, CPU in Activity Monitor or Task Manager, and GNOME if available.

## Out of scope
- Two cats on the desktop at once, or dragging Two cats' cat 2 out.
- A cat that walks around on its own.
- The wardrobe (sub-project I).
- Dropping files on the desktop cat.
- Global shortcuts on Windows and Linux.
- Sounds for the trip; sound Stage 3 can add them later.

## Risks
- **Multiple screens and Spaces on the Mac:** spots per screen arrangement and `clampSpot` are pinned by fixtures; the owner checks two monitors and Spaces at the end.
- **GNOME may ignore the position:** said in Settings; the cat still works where it lands.
- **The frame cost of a Ø96 full-detail cat:** benchmarked, and drawn at 60 fps only during motion.
- **The existing drag-to-attach on the Mac:** the drop rule (a window attaches, no window places) is tested so attaching keeps working exactly as it does today.

## Done means
- A user can drag the big cat to the desktop on the Mac, Windows and Linux and find it there after a restart, at its size and spot.
- It flies to the notch for every approval or question, and back when they're cleared.
- It shows its role's state, badge, kittens and collar, and watches the cursor where the platform allows.
- It sleeps and wakes like the notch cat.
- Its idle cost is under 1 % of a core, and nothing runs while it can't be seen.
- Every existing view looks exactly as it ships.
- Both apps pass the shared fixtures.
