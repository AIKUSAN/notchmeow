# Sub-project I: the wardrobe

**Status:** Design decided by the owner in chat on 2026-10-14; written spec approved 2026-10-14.
**Parent spec:** `docs/superpowers/specs/2026-10-03-notchmeow-design.md` (sub-project I). **Builds on:**
- sub-project A (`docs/superpowers/specs/2026-10-04-cats-in-app-design.md`): the cats' look, the collar, the Ø28 detail switch and the ear fit;
- sub-project B (`docs/superpowers/specs/2026-10-08-display-modes-kittens-design.md`): the display modes, the cast and the kittens;
- sub-project H (`docs/superpowers/specs/2026-10-08-desktop-cat-design.md`): the desktop cat, its menu and the `desktop` shortcut.

All three are merged on both apps, and this document doesn't repeat them.

**Inspired by** upstream Coucou 0.1.5's wardrobe. Only three ideas come across: the Auto mode that follows the calendar, the fall-back to Auto for an unknown stored value, and the preview before you choose. Every outfit is drawn new, for NotchMeow's cats. No upstream drawing code, art, sound, name or key is read, ported or reused (they are reserved assets; see "Rules that apply").

## Goal
Let the user dress the cats. They pick one outfit, or let Auto pick for the season. Every big cat wears it, at every size, and it fits each of the 16 coats: the ears, the head outline and the collar. The small cats and the kittens stay bare.

## Decisions

| Topic | Decision |
|---|---|
| Outfits | **16 outfits**, all drawn in code by NotchMeow: five seasonal, five everyday, four cat extras and two that belong to the cats. Plus **None** and **Auto**: 18 selection IDs. |
| One at a time | One outfit at a time. They don't combine. |
| Auto | Follows the **local date** on the **northern calendar**, by fixed rules in a fixed priority order. No setting, no hemisphere switch. |
| Who wears it | **One choice dresses every big cat, at every size, the compact notch included.** "Big cat" is a role, not a diameter: the island's main cat (compact and open), both cats in Two cats mode, each agent's big cat in A cat for each agent mode, and the desktop cat. **Kittens and the small cats (the pills' small cats, the mini row and the grid) stay bare, whatever their diameter.** |
| Pickers | **Settings → Cat → Wardrobe**, a **Wardrobe submenu** in a new right-click menu on the island cat (Wardrobe is the only item for now) and in the desktop cat's menu, and on the Mac **⌃⌥G**. |
| Shortcut | Action ID **`wardrobe`**, **off by default**, cycles through `auto`, `none` and the 16 outfits, in the grid's order. Mac only. |
| Storage | Mac `UserDefaults` key `cat.outfit`. Windows/Linux the `outfit` key of the `cat` block. One clean-up rule for both. |
| Frozen | The 18 selection IDs and the action ID `wardrobe`, like the cat IDs. An unknown stored value is `auto`. Default `auto`. |
| Cost | Part of the existing frame draw. **No new timer** except Auto's one-shot at midnight. |
| Sound | None. Upstream's pop sound is reserved. |
| Approach | **Contract first, then both apps in parallel**, as in A, B and H. The Mac gets at least what Windows/Linux gets; the shortcut is Mac only because Windows/Linux has no global shortcuts. |
| Never restyle | The island, the pills and every existing view look exactly as they ship. Wardrobe is a new section and a new menu item, in the existing style. |

## Outfits

**The IDs** (lowercase letters only, no separators; this is the order of the grid, the menu and the shortcut's cycle):

| # | ID | Group | Name in the UI |
|---|---|---|---|
| 1 | `auto` | | Auto |
| 2 | `none` | | None |
| 3 | `partyhat` | Seasonal | Party hat |
| 4 | `santahat` | Seasonal | Santa hat |
| 5 | `witchhat` | Seasonal | Witch hat |
| 6 | `bunnyears` | Seasonal | Bunny ears |
| 7 | `sunglasses` | Seasonal | Sunglasses |
| 8 | `beanie` | Everyday | Beanie |
| 9 | `bow` | Everyday | Bow |
| 10 | `scarf` | Everyday | Scarf |
| 11 | `roundglasses` | Everyday | Round glasses |
| 12 | `crown` | Everyday | Crown |
| 13 | `bell` | Cat extras | Bell |
| 14 | `bandana` | Cat extras | Bandana |
| 15 | `fishclip` | Cat extras | Fish clip |
| 16 | `flower` | Cat extras | Flower |
| 17 | `shrimpclip` | The cats' own | Shrimp clip |
| 18 | `blossomclip` | The cats' own | Peach-blossom clip |

**The drawings.** One line each. The contact sheet decides the final shapes and colours; these are the intent.

- **Party hat.** A slim cone of two bright stripes, leaning about 12° towards the right ear, with a small star on the tip. It stands between the ear bases.
- **Santa hat.** A soft red hat with a white fur band across the crown, between the ear bases. The tip bends to the left and ends in a white pompom.
- **Witch hat.** A dark purple cone with a bent tip and a buckled band, on a brim that is narrower than the ear spread, so both ears stay in view.
- **Bunny ears.** Two tall soft ears with a pink inside, rising from behind the crown between the cat's own ears. One has a bent tip. The cat's ears stay.
- **Sunglasses.** Two rounded dark lenses with a pale glint, a thin bridge and a short arm at each side. They sit over the eyes and turn with the face.
- **Beanie.** A snug knitted cap with a ribbed cuff and a pompom. It hugs the crown between the ear bases, and the ears stay outside it.
- **Bow.** A ribbon bow, two loops and a knot, pinned at the base of the right ear and tilted with it.
- **Scarf.** A knitted scarf with two stripes, wrapped under the chin, with one short tail hanging on the left.
- **Round glasses.** Thin round rims with a faint tint and a glint, and a bridge. The cat's eyes stay visible through them.
- **Crown.** A small gold crown with three points and a coloured gem on each, lying on the crown between the ear bases.
- **Bell.** A small gold bell on a ring, hanging at the front of the neck, from the collar.
- **Bandana.** A red triangle with white dots, knotted at the side of the neck. It is bigger than the kerchief collar and covers it.
- **Fish clip.** A tiny silver-blue fish, a hair clip at the base of the left ear.
- **Flower.** A five-petal flower tucked in at the base of the right ear.
- **Shrimp clip.** A tiny coral shrimp curl, a hair clip at the base of the left ear. It is Shrimpy's own.
- **Peach-blossom clip.** A peach-blossom with five rounded petals, a small gold centre and two leaves, at the base of the right ear. It is Momo's own (momo = peach).

**Open to every coat.** The two cats' own clips are in every cat's list and menu, not only Shrimpy's and Momo's. They are "theirs" because they match those two coats' character, not because the others are locked out.

**Colours.** Each outfit has fixed colours, in a new `outfits` block of `shared/theme.json` (generated by `scripts/gen-theme.mjs`; `docs/THEME.md`). A coat is never recoloured. Where an outfit would vanish on a coat, its thin edge switches between light and dark by the luminance of the coat's head colour (`outfitEdge`, part of the contract). The contact sheet is how the owner finds those.

## Auto rules

Auto reads the **local calendar date** (year, month, day) on the northern calendar. The first rule that matches wins; there are no overlaps today, but the order is the contract.

| Priority | Dates (local) | Outfit |
|---|---|---|
| 1 | Dec 31 to Jan 2 (across the new year) | `partyhat` |
| 2 | Dec 1 to Dec 26 | `santahat` |
| 3 | Oct 1 to Nov 1 | `witchhat` |
| 4 | Easter Sunday minus 2 days to plus 1 day (Good Friday to Easter Monday) | `bunnyears` |
| 5 | Jun 21 to Aug 31 | `sunglasses` |
| | anything else | no outfit |

- **Easter** is the Gregorian Easter of the date's own year, by the Meeus/Jones/Butcher computation. The day difference is counted on calendar-date numbers, not on clock times, so a daylight-saving change can never shift it.
- **No hemisphere, no locale.** The dates are the same for everyone. In the southern hemisphere summer sunglasses arrive in winter. That is accepted for now (see "Out of scope").
- **Auto is a choice, not an outfit.** `autoOutfitFor(y, m, d)` returns an outfit ID or `none`. The stored value stays `auto`; the app resolves it for drawing.
- **When it re-checks.** At launch, and then at the next local midnight, with one one-shot timer (the same shape as `CatSleep`). The timer exists only while the stored value is `auto`; picking an explicit outfit or `none` cancels it. When it fires after a long Mac sleep, it is late, and it recomputes from the date then. Nothing polls.
- **Settings shows today's result:** the Auto tile is labelled "Auto: today, Santa hat" (or "Auto: today, none").

## Who wears it

- **Dressed, by role:** a cat drawn in a **big-cat role** wears the outfit, whatever its diameter. That is the island's main cat (compact and open), both cats in Two cats mode, each agent's big cat in A cat for each agent mode, and the desktop cat (Ø48, Ø64 or Ø96).
- **Bare, always:** kittens (a kitten is never given an outfit, as it is never given `useCharacter`) and the **small cats**: the pills' small cats, the mini row and the grid, whatever their diameter.
- **The role decides, not the diameter.** The Ø28 detail switch (`DETAIL_FULL_MIN`) only changes how the cat is drawn (flat fills below it); it doesn't decide who is dressed. `outfitWorn(role)` takes the role (`big`, `small` or `kitten`).
- **The compact notch is dressed.** The compact island's big cat is drawn at **Ø20** in the 32-point notch strip (Ø18 in the 24-point strip of a screen without a notch; `islandBase`/`collapsePose` in `cat-core.js`: `hb` ends at `20/1.34`, so `D = 20`). Every outfit must still read at that size: hats and bunny ears take the ear-fit room, the thin parts have floors, and the contact sheet has a row at Ø20 and one at Ø18 (see "Floors" and "Fit to the strip").
- **One cast, one outfit.** The outfit is global. It is not per cat, and `AppState.cast` doesn't change: each cat view reads the one resolved outfit next to its coat and its role.
- **The desktop cat** wears it in every size, and the kittens beside it stay bare.

## Pickers

**Settings → Cat → Wardrobe** (a new section after Display and Desktop, in the existing style):
- A grid of 18 tiles in the ID order: Auto and None first, then the groups with small headings.
- A **live preview** above it: the Main cat, drawn by the same renderer, wearing the tile under the pointer, else the chosen one. A coat picker next to the preview shows the same outfit on any of the 16 coats; it changes nothing that is stored (not the Main cat, not the outfit).
- A click chooses and stores. The Auto tile shows today's result.

**Right-click on the island cat:** a **Wardrobe** submenu with the 18 entries in groups, a check on the current one. **In the desktop cat's menu:** the same submenu, beside Open the notch, Send home and Size.
- The desktop cat already has a right-click menu (H). The island cat has none today, so its menu is new, with **only Wardrobe in it for now**, and needs a hit-test that does not change how a click or a drag works (the risk below).

**⌃⌥G (Mac only):** the `wardrobe` action in `ShortcutLogic`, **off by default** (⌃⌥D is on by default; this one is not, so it can't take a key from someone who never asked). Each press moves to the next ID in the order above, `auto` and `none` included, and wraps from `blossomclip` to `auto`. It is listed in Settings → Shortcuts with the others, and the existing conflict check applies. **Windows and Linux have no global shortcuts**, so they have the section and the menus but not this.

**Not added:** a menu-bar item, a toast, a sound or a new emote. The cat simply shows the new outfit.

## Storage

- **Mac:** `UserDefaults` key `cat.outfit` (a string). The shortcut's own keys follow the others (`shortcut.wardrobe.keyCode`, `.flags`, `.enabled`).
- **Windows/Linux:** the `outfit` key of the `cat` block of `settings.json`. The block is cleaned as a whole by `cat/display.ts` (`cleanCatBlock`) and its Rust twin `clean_cat_block` in `cat_settings.rs`; both gain a call to the wardrobe clean-up, and `settings.rs` must keep the key at every save, as it keeps B's and H's.
- **Clean-up:** `cleanWardrobeSettings(raw)` in `cat-core.js`, a clean-up of its own, so `settings-cases.json`, `display-cases.json` and `desktop-cases.json` stay byte for byte. It takes the stored value as a plain JSON value and returns `{outfit}`:
  - one of the 18 IDs, exactly as written (lowercase, no trimming), is kept;
  - anything else, or no value, or a value that is not a string, is `auto`.
- **Fresh install:** `auto`.
- **Frozen:** the 18 IDs and the action ID `wardrobe` never change or get reused, because they are stored. A future outfit gets a new ID at the end of its group's list in the contract (and a new row in the grid); the cycle order is a UI order, not a stored value.

## Contract

All new names in `design/prototype/cat-core.js`, pinned by one fixture, `tests/fixtures/cat/wardrobe-cases.json`. No existing constant, function or fixture changes (`scripts/check-fixtures-additive.mjs` proves it); `PASSES` stays as A-0 wrote it.

- **IDs.** `OUTFIT_IDS` (the 18, in order), `OUTFIT_NAMES` (the UI names), `OUTFIT_GROUPS` (the grid's five rows), `OUTFIT_DRAWN` (the 16), `outfitIdOf(v)` (the stored value to an ID, unknown to `auto`) and `cleanWardrobeSettings(raw)`.
- **Auto.** `easterOf(year)` and `autoOutfitFor(y, m, d)`. The input is date numbers, so the function is pure and the same in Node, Swift and TypeScript. `resolveOutfit(id, y, m, d)` gives the outfit to draw (`none` for none, the Auto result for `auto`).
- **Who.** `OUTFIT_ROLES` (`big`, `small`, `kitten`) and `outfitWorn(role)`, true for `big` only (any other value is false). The apps map their views to roles: the cast's big cats and the desktop cat are `big`, the pills, the mini row and the grid `small`, the kittens `kitten`.
- **Anchors.** `outfitAnchors(p, s, D, o)`, in head-local px (before tilt and squash), turning with the face warp, like `collarGeometry`. It returns:
  - `top` (the crown point between the ear bases, on the head outline), and `gap` (the span between the two ear bases at the head's top, from `earGeom`), so hats sit between the ears;
  - `earBase` for each side, and each ear's tip, so clips, the bow and the flower sit at an ear base and bunny ears rise between the ears;
  - `eyes`, the two eye frames, for both pairs of glasses;
  - `chin`, the lower outline from 40° to 140° and its centre front, shared with `collarGeometry`, for the scarf, bandana and bell;
  - `edge`, the light or dark outline colour for this coat (`outfitEdge`), and `neck`, the point the collar's tag hangs from (for the bell with the collar off).
- **Room.** `outfitRoom(anchors, headY, ceiling)`, the height above the crown that the ear fit's ceiling leaves a hat (null without a ceiling).
- **Geometry.** `outfitGeometry(id, p, s, D, o)` returns a short list of shapes in a tiny vocabulary: `poly`, `ellipse` and `curve`, each with points in head-local px, a **colour role** (`partyA`, `fur`, `lens`, and so on, the keys of the theme's `outfits` group, or `edge`), a **slot**, an alpha, a stroke width and a `fine` flag (a glint or a star, left out below Ø28). It is pure; the renderer paints it. `o` carries `dpr`, `detail`, `earScale`, `room` and the collar style (the bell reads the collar's geometry from it, and never changes it). `outfitDigest(shapes)` summarises a list (counts, a box, the mean point) so a port compares numbers within the tolerance, not a float checksum.
- **Slots and order.** `OUTFIT_SLOTS` names where each shape is drawn, without touching `PASSES`:
  - `behind`: after `ears` in the behind pass (bunny ears), so the head covers their roots;
  - `neck`: in the front pass **after the collar** and before `whiskers` (scarf, bandana, bell);
  - `top`: after `neck`, still before `whiskers` (hats, crown, glasses, clips, flower, bow).

  So the front pass reads: `foldEars`, collar, outfit `neck`, outfit `top`, `whiskers`, `badge`, `particles`, `balls`. The whiskers and the badge stay in front of every outfit. Folded ears are covered by a hat that lies over them.
- **Floors.** `OUTFIT_MIN`, in **device** pixels, as `COLLAR_MIN` is: below it a part gets no smaller (a hat's height, the bell's radius, a rim's or a stroke's width, a clip's size, a gem or a pompom). The smallest dressed cat is the compact notch's Ø18 to Ø20 big cat, so the floors are set for it: at Ø20 and two device pixels per point, the head is 40 device pixels wide. The plan measures every outfit on every coat at Ø20 and Ø18 against the floors, and draws them on the contact sheet. Details that cannot read at that size (glints, stars, ribbing) are marked `fine` and left out below Ø28, as the cat's own fine details are.
- **Fit to the strip.** Hats and bunny ears rise above the head. In the compact notch they get the same room the ears get (`earFit`'s ceiling and margin): `outfitRoom` gives the height available above the crown, and the rising parts are shortened to it; if even the floor does not fit, they are held at the floor's height, not hidden. The fixture pins it.
- **Collar interplay.** `outfitGeometry` reads the collar's geometry, and never changes it. See "Drawing and fitting".

## Drawing and fitting

**One rule for every coat.** The geometry is computed from the coat's own numbers (`rx`, `ry`, `n`, `earSpread`, the ear box, the eye frames), never from a coat list, so the 16 coats and any future one fit by construction. A coat with a ruff or a wide cheek (Shrimpy, the fluffy coats) is covered by the same maths, because the head outline `supPoints` already includes it.

**Ears.** Hats are narrower than the gap between the ear bases (the witch brim is the only wide part, and it stays narrower than the ear spread). Clips, the bow and the flower anchor at an ear base and follow its tilt and squash. The folded ears of the coats that have them are drawn before the outfit, so a hat covers them. Bunny ears rise between the cat's own ears; the cat keeps its own.

**Eyes.** Both pairs of glasses follow the eye frames (`Eye`: `x`, `y`, the face-turn `fx`, `fy`) and turn with the face. The sunglasses cover the eyes, so the iris and the cursor-watching are not visible through them, which is the point. The round glasses leave them showing. A glance, a wink and a blink still move the eyes beneath.

**The face turns away.** Parts on the face (glasses) go through the same warp as the eyes and flatten with them. Hats and the bow go through the warp of their anchor, so they slide with the head. The contact sheet shows a head turned a full yaw each way.

**The collar.** The collar is drawn first. The outfit's `neck` slot is above it.

| Outfit | With a collar | With the collar off |
|---|---|---|
| `bell` | Hangs from the collar: the tag's lower edge (tag style), the middle of the band (band style), the apex of the triangle (kerchief style). | **Still draws.** It hangs from its own thin ring at the chin's centre front, the same point the tag would use. |
| `bandana` | Drawn over the collar and bigger than the kerchief, so the collar is covered, not doubled. | **Still draws**, on the same anchor. |
| `scarf` | Drawn over the collar; the collar's edge is hidden under it. | **Still draws.** |
| `bow` | The bow is on the head, not the neck; the collar is unaffected. | Same. |
| any hat, glasses or clip | The collar is unaffected. | Same. |

The collar's colour is the agent's colour, so a bell on a kerchief collar still reads as the agent's. Where the collar is hidden by a scarf or bandana, the agent's colour is not seen on that cat; that is accepted, and the owner can pick another outfit. (The state badge and the glow still carry the agent's state.)

**Two cats and per-agent mode.** Every dressed cat gets its own geometry from its own coat. The same outfit on two different coats is two different shapes.

**Performance.**
- Outfits are part of the existing frame draw: no layer, no window, no timer. The geometry is pure and small, and is recomputed with the pose as the collar's is.
- `none`, every small cat and every kitten cost nothing: `outfitWorn` is checked first.
- The desktop cat's frame-rate rule (`desktopFps`) is unchanged; an outfit adds no motion of its own. The bench (`render-cats.sh --bench-desktop`) is run once with an outfit on, to prove it.
- The notch's own rule stays: **0 % CPU while the island is hidden.** Auto's midnight timer is one one-shot, and it needs nothing while the island is hidden.

**Files** (proposed names; a plan may adjust them).
- Contract: `design/prototype/cat-core.js`, `design/prototype/notchmeow.html` (the Wardrobe panel), `shared/theme.json`.
- Mac: `WardrobeSettings.swift` (the port of `cleanWardrobeSettings` and the stored key), `CatOutfit.swift` (the pure port of the anchors and geometry), `CatOutfitDraw.swift` (painting into a `CGContext`, called from `CatRenderer` at the three slots), `WardrobeAuto.swift` (the resolved outfit and the one-shot timer), `WardrobeSettingsView.swift` (the section) and a `wardrobe` action in `ShortcutLogic.swift`.
- Windows/Linux: `windows/src/cat/wardrobe.ts`, `outfit.ts`, `outfitdraw.ts`, `settings/wardrobe.ts`, and in Rust `clean_wardrobe_settings` in `cat_settings.rs`.

## Testing

Everything is checked without launching the app, as in A, B and H.

- **Fixtures.** `tests/fixtures/cat/wardrobe-cases.json`, generated by `node scripts/gen-cat-fixtures.mjs` from `cat-core.js`. It holds:
  - the 18 IDs and the groups, in order;
  - `clean`: a stored value to an ID (every ID, a wrong case, a padded string, `null`, a number, an object, the old `mochi` names, an empty string);
  - `auto`: the Auto result for chosen dates, each side of every boundary (Dec 31, Jan 2, Jan 3, Nov 30, Dec 1, Dec 26, Dec 27, Sep 30, Oct 1, Nov 1, Nov 2, Jun 20, Jun 21, Aug 31, Sep 1) and for **Easter −3 to +2 in several years**, including the earliest and the latest possible Easter, a leap year and a year where Easter falls in March;
  - `worn`: the three roles, and values that are not roles (a diameter, `null`, a number, `Big`) which are all bare;
  - `anchors` and `geometry`: the full anchors, and the full shapes for four pinned cases, for a pinned set of four coats (a round one, a fluffy one, a folded-ear one and a black one) at four sizes (Ø20 in the notch strip, Ø28, Ø48 and Ø64), at rest and with the head turned; and the **digest of the shapes for all 16 outfits on all 16 coats** at Ø18, Ø20, Ø48 and Ø64, so any drift in any pair fails;
  - `compact`: for every outfit on every coat at Ø20 in the 32-point strip and at Ø18 in the 24-point strip, that no part is below its floor and nothing rises above the strip;
  - `collar`: the bell, bandana and scarf with each of the four collar styles.
- **Mac.** `scripts/test-wardrobe-{settings,auto,geometry,wiring,shortcut}.sh` replay the fixture; `scripts/test-cat-wiring.sh` gains the three renderer slots, and `scripts/test-shortcuts.sh` the new action. `bash scripts/render-cats.sh --wardrobe` draws the **contact sheet: 16 outfits on 16 coats**, and strips for the compact notch's Ø20 and Ø18 big cat, the head turned, the collar styles, the three desktop sizes and a Two cats pair. `render-cat-settings.sh` draws the Wardrobe section.
- **Windows/Linux.** `npm run check:cat` replays the same fixture; the Rust tests replay it for `clean_wardrobe_settings`. `npx vite`, then `http://127.0.0.1:1420/?dev` has the same **16 by 16 sheet**, and the headless browser check draws it. The site's bundled cats (`docs/assets/cats.js`) are rebuilt only if the owner wants outfits on the site; this spec doesn't ask for it.
- **The prototype is the visual source of truth.** `notchmeow.html` gets a **Wardrobe panel**: the outfit chooser, the coat chooser, the date field for Auto and the same sheet. The apps' sheets are compared against it.
- **Gates.** `check-fixtures-additive.mjs` (nothing existing changed), `test-theme.sh` (the generated theme files are fresh), `check-no-leftovers.sh` (no `mochi`, no pumpkin, no top hat, no upstream key) and `check-app-binary.sh` for the three builds.

## Rules that apply

From `CLAUDE.md`:
- **Never restyle what ships.** The Wardrobe section follows the existing Settings style. The only change in the island is a cat wearing something.
- **Cat IDs, pill IDs and now outfit IDs and `wardrobe` are frozen.** `cat.outfit` is a new key; no existing key is renamed.
- **Licensing.** No upstream drawing, no art, no name. The upstream wardrobe's names (`Mochi*`, `mochiOutfit`, `mochi_outfit`), its outfit list as drawn, its pumpkin and the "pop" sound are not used. The only reused ideas are the Auto dates, the fall-back and the preview. NotchMeow's own outfits are covered by `LICENSE-ASSETS.md`.
- **Drawn in code.** `CGContext` and Canvas 2D, no images, no Rive or Lottie.
- **No telemetry, no network, no secrets.** Nothing here touches any.
- **Never block Claude Code.** Nothing here is on the hook path.
- **Performance.** 0 % CPU when the island is hidden. No new timer except the one-shot.
- **Mac primary.** Everything the Windows/Linux app gets, the Mac gets; the shortcut is the Mac's extra.
- **Model rule** (owner's, 2026-10-12): Haiku 5.5 first; Sonnet 5.5 only on a named trigger; never Opus or Fable.
- **Never push**, and commit only when the owner asks.

## Rounds

1. **I-0, the contract** (one worktree session; **Haiku 5.5, medium**: the plan gives the code in full, and the design work is in drafting the plan, `docs/superpowers/plans/2026-10-14-i0-wardrobe-contract.md`). Adds to `cat-core.js` the IDs, `cleanWardrobeSettings`, `easterOf`, `autoOutfitFor`, `resolveOutfit`, `outfitWorn`, `outfitAnchors`, `outfitRoom`, `outfitGeometry`, `outfitDigest`, `outfitEdge`, `OUTFIT_SLOTS`, `OUTFIT_ORDER`, `OUTFIT_ROLES` and `OUTFIT_MIN`; the `outfits` block in `shared/theme.json`; `wardrobe-cases.json`; the prototype's Wardrobe panel; and `docs/CAT-CONTRACT.md`, "The wardrobe (I-0)". Only new names.
   - **Owner checkpoint:** the **contact sheet of all 16 outfits on all 16 coats**, plus the compact Ø20 and Ø18 rows, the head turned and the collar strips, and the prototype in a browser. The owner approves or asks for changes to shapes and colours **before** any app plan starts. The pinned fixture is regenerated after any change.
2. **I-mac and I-tauri, in parallel** (worktree sessions). I-mac is **Sonnet 5.5, high**, trigger 1 (AppKit menus on a non-activating panel, Carbon hot key) and trigger 5. I-tauri is **Haiku 5.5, high**, moving to Sonnet 5.5 only if a named trigger appears (the island's context menu in a Tauri window is the likely one). Each, in this order:
   1. the settings and clean-up port, with the fixture replay;
   2. the pure geometry port, with the fixture replay;
   3. the drawing at the three slots, and the sheet;
   4. Auto and its one-shot;
   5. the Wardrobe section;
   6. the right-click submenus (island cat, desktop cat);
   7. on the Mac, ⌃⌥G and its Settings row;
   8. docs (`SPEC.md`, `CAT-CONTRACT.md`, `ARCHITECT.md`, `CLAUDE.md`'s pointer and the Settings text).

   Three owner checkpoints each:
   1. the app's contact sheet against the prototype's, and the Wardrobe section drawn;
   2. the bench with an outfit on, and Two cats and per-agent mode sheets;
   3. sign-off, then `nm-reviewer-deep` over the whole branch.
3. **The owner's real-build checks** at the end: each outfit on the island, on the desktop cat at three sizes and in Two cats mode; Auto on a faked date (a Debug-only date override, like the Debug cat panel, compiled out of Release and App Store); the midnight change; the right-click menus; ⌃⌥G; CPU in Activity Monitor or Task Manager with an outfit on.

## Out of scope
- Combining outfits (a hat and a scarf at once).
- Per-cat outfits, or a different outfit for each agent.
- A southern-hemisphere or locale-aware Auto, and holidays beyond the five rules.
- Outfits on kittens and on the small cats (the pills' cats, the mini row and the grid), whatever their size.
- Outfits on the site's live cats.
- A sound, an emote or a toast for changing outfit.
- Global shortcuts on Windows and Linux.
- Outfit packs, user-made outfits or importing.

## Risks
- **Fit across 16 coats.** The contact sheet is the control, and the 16-by-16 digests keep a later change from breaking one pair silently.
- **Reading at Ø20.** The compact notch's big cat is dressed too, in a 32-point strip with about 8 points of headroom above the crown. Hats are shortened to fit and the thin parts have floors; the contact sheet's Ø20 and Ø18 rows are the control, and the owner may ask for a simpler drawing of an outfit at that size.
- **The island cat has no right-click menu today.** Adding one (with only Wardrobe in it) must not change a click, a drag or the drag-out of the cat.
- **Colour clashes** with the agent's collar colour under a scarf or bandana. Accepted and visible on the sheet.

## Answered by the owner on 2026-10-14
These had a proposed answer each; the owner's answers are used throughout.
1. **Compact notch.** The big cat is **always dressed, at every size**, the compact notch included. The role decides, not the diameter: big cats (the island's main cat compact and open, both cats in Two cats mode, each agent's big cat, the desktop cat) are dressed; kittens and the small cats are bare, whatever their diameter. `outfitWorn` takes the role. The plan measures the compact cat (Ø20 in the notch strip, Ø18 without a notch) and checks that every outfit reads there.
2. **The island cat's right-click menu** is new, with only Wardrobe in it for now. Approved as proposed.
3. **The shortcut's cycle** includes `auto` and `none`, in the grid's order. Approved as proposed.
4. **The two cats' own clips are open to every coat.** Approved as proposed.
5. **Models.** I-0 runs on **Haiku 5.5, medium** (the plan gives the code in full; the design work is in drafting the plan). I-mac on **Sonnet 5.5, high** (trigger 1). I-tauri on **Haiku 5.5, high**.
6. **A coat picker in the Settings preview** that changes nothing stored. Approved as proposed.
7. **The IDs** are as listed in "Outfits". Approved as proposed.
