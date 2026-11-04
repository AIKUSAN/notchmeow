# Theme tokens

`shared/theme.json` holds the colours of NotchMeow's own drawing that no other contract file holds: the cat's details (pupil, mouth, tongue, teeth, the heart, star and sweat drop, the file sheet of the file catch), the launch greeting (badge, tint, halo, header text, card) and the palette of the fork's own pages (the prototype, the Windows/Linux `?dev` sheet, the Debug cat panel). `scripts/gen-theme.mjs` turns it into one file per platform, so each colour has one home.

**Only the character, branding and greeting colours are here.** Existing views keep their own colours (Settings, chat, the pills and the upload view), even where they use the same hex value. The island's glow is the one exception: with the owner's OK it reads the `state.glow` tokens since stage 7, at the same values. Coat colours are in `tests/fixtures/cat/presets.json`; the state colours, the state glows and the greeting's streak palette are pinned by `tests/fixtures/cat/`, so the generator reads them from `design/prototype/cat-core.js` instead of copying them into `theme.json`. If `cat-core.js` changes one, regenerate the fixtures and then the theme files.

**Both apps read these files since stage 7 of sub-project A:** the Mac reads `Theme.generated.swift` and Windows/Linux reads `theme.generated.ts` (`theme.generated.css` feeds the site: `windows/src/site/main.ts` imports it, so `docs/assets/cats.css` carries the tokens and `docs/site.css` reads them). Every site in the table below now reads its token instead of a hard-coded copy. Stage 7 changed no pixel, proved on the Mac by byte-identical before and after contact sheets and on Windows/Linux by an equal before and after drawing record. The table records where each colour lived at `947e2d3`, so a site is found again by its value.

## Run it

```
node scripts/gen-theme.mjs           # write the three files after editing shared/theme.json (or a state colour in cat-core.js)
node scripts/gen-theme.mjs --check   # write nothing; exit 1 and name the file if one is stale
bash scripts/test-theme.sh           # the generator's self-checks, then --check (CI runs this)
```

Node 22 or newer, no npm packages. Commit `theme.json` and the three generated files together; CI fails when they disagree.

| Platform | Generated file | Names |
|---|---|---|
| macOS | `NotchBuddy/Sources/App/Theme.generated.swift` | `Theme.Cat.pupil` (a `"#RRGGBB"` String), `Theme.Cat.pupilRGB` (`[Double]`); lists and maps: `Theme.Greeting.streaks`, `Theme.State.color["working"]`, `Theme.State.glowRGB["working"]` |
| Windows and Linux | `windows/src/theme.generated.ts` | `THEME.cat.pupil`, `THEME_RGB.cat.pupil`, `THEME.greeting.streaks[0]`, `THEME.state.color.working` (both are `as const`) |
| Windows and Linux | `windows/src/theme.generated.css` | `--nm-cat-pupil` and `--nm-cat-pupil-rgb` (`14, 11, 9`, for `rgba(var(--nm-cat-pupil-rgb), .5)`), `--nm-greeting-streak-1`, `--nm-state-color-working`, `--nm-state-glow-working` |

## The tokens

| Group | Token | Value | What it is |
|---|---|---|---|
| `brand` | `accent` | `#5EEAD4` | The accent of the fork's own pages |
| `brand` | `page`, `panel`, `line`, `ink`, `dim`, `button` | `#0F1012`, `#17181B`, `#2A2C31`, `#ECECEE`, `#9A9CA3`, `#202227` | The dark page, panel, border, text, dim text and button of those pages |
| `cat` | `pupil` | `#0E0B09` | The pupil |
| `cat` | `mouthInside`, `tongue`, `teeth` | `#3A1218`, `#E8798C`, `#FBF7F0` | The open mouth, the tongue, the small fangs |
| `cat` | `heart`, `star`, `sweat` | `#FF4D6D`, `#F7B32B`, `#7CC7FF` | The love heart, the happy star, the sweat drop |
| `cat` | `paper`, `paperFold`, `paperLabel` | `#F4F5F7`, `#C9CDD4`, `#3B9EFF` | The file the cat catches: sheet, folded corner, label |
| `greeting` | `badge`, `tint` | `#3BA0F5`, `#7FB4EA` | The greeting's badge, and the blue its cats end in |
| `greeting` | `haloGold`, `haloBlue` | `#E8C39A`, `#3B9EFF` | The halo's two ends (golden, then blue) |
| `greeting` | `headerDim`, `card` | `#8D9098`, `#141518` | The header's right-hand text, the Windows greeting's card |
| `greeting` | `streaks` | `#3B9EFF`, `#F29B38`, `#FF5A4E`, `#2EC4A0`, `#A78BFA` | The five colours the sixteen streaks cycle through. From `cat-core.js` |
| `outfits` | the 38 colours of `shared/theme.json` | The outfits' colour roles (`partyA`, `santaRed`, `gold`, `bunnyInner` and so on) and the two edges `edgeLight` and `edgeDark`. `Theme.Outfits`, `THEME.outfits` and `--nm-outfits-*`. The prototype's Wardrobe panel keeps a copy that a test holds equal |
| `state` | `color` | the 11 `COL` colours | The cat's state colour. From `cat-core.js` |
| `state` | `glow` | the 7 `GLOW` colours | The glow behind a working cat. From `cat-core.js` |

## Where each colour is hard-coded today

Line numbers are as of commit `947e2d3`. They move; find a colour by its value (`grep -rniE '#0E0B09' NotchBuddy/Sources windows/src design/prototype`). Stage 7 replaces each of these, and only these, with the token.

| Token | macOS (`NotchBuddy/Sources/App/`) | Windows and Linux (`windows/src/`) | Prototype (`design/prototype/`) |
|---|---|---|---|
| `brand.accent` | none | `cat/dev.ts:72, 93` | `notchmeow.html:15` |
| `brand.page` | `CatDevPanel.swift:330` (as 0.059, 0.063, 0.071) | `cat/dev.ts:80` | `notchmeow.html:15` |
| `brand.panel` | none | `cat/dev.ts:55` | `notchmeow.html:15` |
| `brand.line` | none | `cat/dev.ts:19, 55, 72, 93, 135` | `notchmeow.html:15, 497` |
| `brand.ink` | none | `cat/dev.ts:19, 72, 81, 131` | `notchmeow.html:15, 496` |
| `brand.dim` | none | `cat/dev.ts:56, 64, 85, 141, 159, 175` | `notchmeow.html:15, 499` |
| `brand.button` | none | `cat/dev.ts:19` | `notchmeow.html:26` |
| `cat.pupil` | `CatFace.swift:64` | `cat/renderer.ts:275` | `notchmeow.html:203` |
| `cat.mouthInside` | `CatFace.swift:170` | `cat/renderer.ts:403` | `notchmeow.html:260` |
| `cat.tongue` | `CatFace.swift:154` | `cat/renderer.ts:404, 411, 424` | `notchmeow.html:261, 263, 268` |
| `cat.teeth` | `CatFace.swift:178` | `cat/renderer.ts:406` | `notchmeow.html:262` |
| `cat.heart` | `CatFace.swift:116`, `CatEffects.swift:127` | `cat/renderer.ts:300, 377` | `notchmeow.html:218, 241` |
| `cat.star` | `CatFace.swift:120`, `CatEffects.swift:130` | `cat/renderer.ts:301, 378` | `notchmeow.html:219, 242` |
| `cat.sweat` | `CatEffects.swift:139` | `cat/renderer.ts:380` | `notchmeow.html:244` |
| `cat.paper` | `CatEffects.swift:158` | `cat/renderer.ts:443` | `notchmeow.html:398` |
| `cat.paperFold` | `CatEffects.swift:159` | `cat/renderer.ts:444` | `notchmeow.html:399` |
| `cat.paperLabel` | `CatEffects.swift:160` | `cat/renderer.ts:445` | `notchmeow.html:400` |
| `greeting.badge` | `CatGreetingRenderer.swift:41` | `cat/greeting.ts:186` | `notchmeow.html:476` |
| `greeting.tint` (127, 180, 234) | `CatGreetingRenderer.swift:41, 66` | `cat/greeting.ts:177, 187` | `notchmeow.html:476` |
| `greeting.haloGold`, `greeting.haloBlue` (the two ends of a `lerp`) | `CatGreetingRenderer.swift:16` | `cat/greeting.ts:291` | `notchmeow.html:471` |
| `greeting.headerDim` (141, 144, 152) | `CatGreetingRenderer.swift:32` | `cat/greeting.ts:303` | `notchmeow.html:458, 461, 463, 474` |
| `greeting.card` | none: the Mac draws no card | `cat/greeting.ts:272` | none |
| `greeting.streaks` | `CatGreeting.swift:94` | `cat/greeting.ts:74` | `cat-core.js:418` |
| `state.color` | `MotionProfiles.swift:10-11` | `cat/base.ts:54-56` | `cat-core.js:37` |
| `state.glow` | `MotionProfiles.swift:18`; the island's glow, `IslandRootView.swift:342-348` | `cat/base.ts:63-64`; the island's glow, `core/layout.ts:163-175` (every other line) | `cat-core.js:39` |

The two island glow rows are the cat's glow drawn by existing island code, with the same values as `GLOW`. Replacing the literals there with `state.glow` changes no pixel, but it is edited code of an existing view: stage 7 does it only with the owner's OK.

## Not tokens

- **The same hex value in an existing view.** `#F5A524`, `#F4505E`, `#34D399`, `#F7B32B`, `#C9CDD4` and others also appear in `IslandViewContent.swift`, `SettingsView.swift`, `windows/src/style.css` and the like. Those are upstream's UI colours and stay as they are.
- **Alpha-only black and white** (`rgba(0,0,0,.42)`, `rgba(255,255,255,.85)`, the collar's edge and highlight) and colours computed from a coat or an agent.
- **Coat colours.** They are in `presets.json`, pinned by the contract.
- **The agent colours** of the collar. They come from the pill catalog (`PillCatalog.swift` on the Mac).
- **Icons.** Their palette is chosen separately.
