# NotchMeow architecture

A map of how NotchMeow fits together, and how AI agents should work in this repo.
For rules, read `CLAUDE.md`. For decisions and plans, read `docs/superpowers/specs/` and
`docs/superpowers/plans/`.

## Two apps, one contract

| | macOS | Windows / Linux |
|---|---|---|
| Code | `NotchBuddy/Sources/App/` (Swift 6, SwiftUI + AppKit, zero deps) | `windows/` (Tauri 2: Rust in `src-tauri/`, TypeScript in `src/`) |
| Hook relay | `nm-hook` (shell + Python, embedded in `HookServer.swift`) → Unix socket `nm.sock` | `notchmeow-hook` (`windows/hook/`) → named pipe / `$XDG_RUNTIME_DIR` socket |
| Secrets | Keychain | Credential Manager / Secret Service (`secrets.rs` allowlist) |

Contract strings (`nm-hook`, `nm.sock`, `notchmeow-hook`, `nm_kind`, `nm_agent`) and pill IDs are
frozen. Both apps must change them together or not at all.

## Main flows

1. **Agent sessions.** An agent hook fires and the relay forwards the hook JSON. Then:
   - **macOS:** `HookServer.processEvent` updates the `AppState` tasks, steps, diffs and pending approval or question.
   - **Windows:** `island/hooks.ts` updates `core/state.ts`.
   - **Focus awareness:** before building a card, `HookServer` asks `FocusAwareApp.stepBack`: when the session's app is the frontmost app (read once, at the request), the request is answered "ask" and only marked (an amber dot and a read-only note; Projects counts it as "Waiting in <host>"), so the agent prompts in its own window. Windows/Linux: `windows/src/core/focusaware.ts` through `island/hooks.ts` `takeHook`, the foreground read in Rust (`foreground_app`, once per request, 300 ms at most).

   The island state machine (`hidden → petit → home`) and the cat's state follow. Approvals
   wait for an explicit click. If the app doesn't answer, the hook exits, so Claude Code is never blocked.
2. **Chat.**
   - **One AI layer (sub-project E1):** both apps have providers (Anthropic, OpenAI Responses, OpenAI-compatible and local servers, Apple on-device on the Mac), a per-feature router, discovery and attachments, tested against the shared contract in `tests/fixtures/ai/`.
   - **macOS:** the chat UI calls `ClaudeService.chat`, which asks `AIService` (`AI/AIService.swift`) to resolve the feature through `ModelRouter`, then streams the reply with a `ChatRunner` (`AI/Core/`) and its provider, falling back to a local model when the cloud fails.
   - **Windows:** `views/chat.ts` → `Bridge.aiChat` → the `ai_chat` command (`src-tauri/src/ai/mod.rs`), which runs the turn in `ai/session.rs` with the router and providers beside it. The companion prompt (`companion/turn.ts`, the rules in `companion/core.generated.ts`) is built on the page and sent as the turn's text, and each conversation is a file that Rust writes (`companion_store.rs`); the chat also opens in its own pop-out window (`chatwin/`), which talks to the island through `chat_relay`.
   - **Claude plan (sub-project E3):** with "Use my Claude plan", each chat turn runs the user's own `claude -p` (stream-json, one process per turn) through `ClaudeCodeProvider` (macOS) or `claude_run.rs` (Windows/Linux), at the chat's level: Chat only, Read-only or Agent. Agent's approvals arrive as ordinary `PermissionRequest` hooks: `HookServer` and `island/hooks.ts` send one whose `session_id` belongs to a chat to that chat's card instead of a pill. Stop, and quitting the app, end the whole process tree. Not in the App Store build.
3. **File drop.** A dropped file is copied to the app's `inbox` and becomes the chat context. On a drop, the conversation resets, so the file reaches the model.
4. **Integrations.** Lightweight pollers (GitHub, Stripe, Vercel and others) pause while the island is hidden. CPU stays at 0% when hidden.
5. **Character.**
   - **macOS:** `CatEngine` (with the Playful and Classic motion profiles in `MotionProfiles.swift`) animates a `CatPreset`; `CatRenderer` draws it into a `CGContext` inside the existing canvases (`BotCanvasView`, `MiniBotCanvasView`, `GreetingCanvasView`, `UploadCanvasView`). It replaces `BotEngine.swift`. A file the app refuses is decided at the drop (`CatFileRule`) and coughed up as a hairball. The Debug-only cat panel (`CatDevPanel.swift`) is not in Release or App Store builds.
   - **Windows:** the cat is drawn from the contract (`windows/src/cat/`): `BotEngine` animates a `CatPreset` with the Playful and Classic profiles (`motion/`), and `renderer.ts` draws it in Canvas 2D inside the existing canvases. Checked by `npm run check:cat` against `tests/fixtures/cat/`. Settings → Cat (`settings/cat.ts`) saves a `cat` block that `settings.rs` holds as a JSON value and cleans (`cat_settings.rs`), as `cleanCatSettings` does in `cat/settings.ts`; the engines read the result through the shared `catCfg`. The collar (`collar.ts`), searching (`toolState` in `island/hooks.ts`), the ten-minute sleep (`island/sleep.ts`) and the music bob (`dance.ts`) follow the contract. **Sub-project B (Windows/Linux):** the `cat` block also holds the Display settings (`displayMode`, `pair`, `agentCats`), cleaned by `cat/display.ts` and, in Rust, `clean_cat_block` (`cat_settings.rs`, called by `settings::sanitized`, so a save keeps them). `State.cast` (`cat/cast.ts`) says which coat each place wears, and every `BotEngine` is given it with `setCoat`. `island/hooks.ts` turns a subagent's hook events into kitten events (`island/subagents.ts`), which change the pill's list in `State.kittens` (`cat/kittens.ts`, never stored); `cat/kittendraw.ts` and the island's overlay canvas draw them, and the ten-minute sleep timer sweeps the ones whose stop never came when the cat falls asleep.
   - **Sub-project A:** both apps now draw Shrimpy and Momo, with stages 1 to 7 done on both. `design/prototype/notchmeow.html` is the visual source of truth, and `design/prototype/cat-core.js` holds its pure maths. Both apps are tested against the fixtures generated from it in `tests/fixtures/cat/` (see `docs/CAT-CONTRACT.md`). The Mac app's Settings → Cat (stages 5 to 7) is loaded by `CatSettingsStore` through `CatSettings.clean` and handed to the engines through `CatConfig.shared`; it draws the optional fur lines and the collar (the agent's `task.color`, in the style the user picks), puts an idle cat to sleep after ten minutes with one one-shot timer, and bobs the head and ears to Apple Music. The Cat settings both apps store are cleaned by `cleanCatSettings` (`settings-cases.json`), and `shared/theme.json` feeds the generated theme files (`docs/THEME.md`). **Sub-project B** (display modes, subagent kittens, coloured small eyes) has its contract in the same file and fixtures (`display-cases.json`, `agent-cat-cases.json`, `cast-cases.json`, `kitten-cases.json`, `small-eye-cases.json`), and the prototype draws it; see `docs/CAT-CONTRACT.md`, "Display modes, agent coats, kittens and small eyes". **On the Mac** it is built: Settings → Cat → Display (`CatSettingsView`, `CatDisplayPreview`) picks One cat, A cat for each agent or Two cats and is stored by `CatDisplaySettings` (`cat.displayMode`, `cat.pair`, `cat.agentCat.<pillId>`); a new agent pill gets its coat when `HookServer` or `AppState` creates it (`CatAgentCats`, through `CatSettingsStore`); `AppState.cast` (`CatCast`) hands every cat view its coat; Two cats adds `PairCatViews.swift` and the numbers of `CatIslandLayout`; and `HookServer.processEvent` and `processPermissionRequest` turn `SubagentStart` and the tool and permission events that carry an `agent_id` into kittens (`CatKittenHooks`, `CatKittens`, drawn by `CatKittenDraw`), swept by the cat's sleep timer, in both builds.
   - **Sub-project H (the desktop cat):** its contract is in `design/prototype/cat-core.js` and `tests/fixtures/cat/desktop-cases.json` (new names only; the prototype's Desktop panel draws it): the trip `desktopStep` (seven phases) with `desktopFlightAt`, `desktopFps`, `screenKey`, `clampSpot` and `spotFor`, `cleanDesktopSettings` and `desktopKittenSlots`; see `docs/CAT-CONTRACT.md`, "The desktop cat (H-0)". The two H app plans build on it. **On the Mac** the cat is `DesktopCatController` (the trip, one timer at `DesktopCatTrip.fps`'s rate, the mouse) in a non-activating floating `DesktopCatPanel`; `AppState.desktopPhase` empties the notch's big-cat spot while it is out; a drag of the big cat ends in `DesktopCatDrop` (a window attaches, empty desktop places the cat); ⌃⌥D, the menu-bar item and Settings → Cat → Desktop all end in the store's `cat.desktop.on`, which the controller follows.
   - **Sub-project G1-0 (the shelf contract):** `tests/fixtures/shelf/` (`zone-cases.json`, `shelf-cases.json`) with a Python `reference.py` that decides, like the AI contract's; `build_cases.py` writes the JSON, `scripts/test-shelf-contract.sh` checks it and CI runs that. Documented in `docs/SHELF-CONTRACT.md`. The G1 Mac and Windows/Linux plans port the rules and replay the fixtures.
   - **Sub-project G1 on the Mac (the shelf and Send):** `ShelfRules.swift` ports the G1-0 contract and `scripts/test-shelf-rules.sh` replays its fixtures (the file is read by a strict JSON reader of its own, because `JSONSerialization` repairs a lone surrogate and may strip a byte order mark); `ShelfStore` keeps the list and the bookmarks, `ShelfModel` is what the view shows. A drag over the notch splits the open island at its centre line: the upload canvas stays the Ask half and `ShelfDropLayer` draws the Shelf half over it (`state.dropHalf`, set by the drop view's callbacks in `IslandWindowController`); a drop on Shelf goes through `ShelfDropReader` and `ShelfFlow.afterShelfDrop` and opens `IslandView.shelf`, and never through `FileDropHandler.handle`. Dragging out holds the island open through `AppState.shelfHoldsIsland` (the state machine's `isHeldOpen` and the poll's `inIsland`); the share picker holds it by a clock reading with a limit (`ShelfHold`), so no timer exists. The compact badge is drawn by `IslandContainer` beside the grid and fades with the wing; a click on it is caught in the panel's mouse-up monitor.
   - **Sub-project G2 on the Mac (between your machines):** the link's rules are Swift ports of the G2-0 contract, one script each (`test-link-noise.sh` and its siblings), under `NotchBuddy/Sources/App/Link*.swift`. A conversation (`LinkPairRun`, `LinkTransferReceive`, `LinkTransferSend`) is one run that consumes one `AsyncStream` of events (the peer's frames, the user's click, a one-shot timer) and lets the pure machines (`LinkPairing`, `LinkFlow`) decide; it speaks to a `LinkTransport` (in memory in the tests, `LinkNWTransport` on Network.framework in the app). `LinkService` is the only file that joins them to the app: the listener and its Bonjour advert exist only while `link.visible` is on, the browser only while Settings → Devices or the shelf is on screen, an incoming pairing runs only while Devices is open or within 2 minutes after a Pair click here (otherwise refused silently, no card), an unknown device id is closed, and an offer becomes the `.link` island card that only a click answers and that holds the island open and calls the desktop cat (`transferOffer`). `LinkCardRules` decides what the one card on the island shows and when it may be replaced, so a card the user is about to click is never swapped for another flow's card. `LinkKeychain` reads each secret as `LinkSecretLookup` (absent, found or failed): a failed read is an error, never a fresh key. The privacy pin is `scripts/check-link-render-private.sh`: no picture and no link source reads this Mac's name or user.
   - **Sub-project G2-0 (the link contract):** `tests/fixtures/link/` (`noise-vectors.json`, `pairing-cases.json` with the commit-then-reveal pairing machines, `frames.json`, `flow-cases.json`, `filename-cases.json`) with a Python `reference.py` that decides; `build_cases.py` writes the JSON, `scripts/test-link-contract.sh` checks it and CI runs that. Documented in `docs/LINK-CONTRACT.md`. The incoming transfer offer is an alert to the desktop cat through one more flag of `desktopAlert` (`transferOffer`, fixture `offerCases`). The G2 Mac and Windows/Linux plans port the rules and replay the fixtures.
   - **Sub-project G2 on Windows/Linux (between your machines):** `src-tauri/src/link/` is Tauri-free and replays `tests/fixtures/link/`; `link::service::Service` is an actor (one task owns all state, tasks of its own run each pairing, transfer and connection and report back by command) that emits a whole `Snapshot` as the `link` event, and `link_cmd.rs` is the only Tauri file (15 `link_*` commands; `link_send` takes shelf ids and `crate::shelf_store().resolve` finds the paths). Flow: `link_set_visible(true)` starts `net::Listener` (IPv4, a system port) and `mdns::Mdns` advertises; Settings → Devices or the shelf on screen (`link_devices_open`, `link_shelf_open`, states and not counters) starts the browser; a pairing (Noise XX, commit-then-reveal, six digits) or a transfer (Noise KK, offer, chunks) is a run over a `Transport`; an offer becomes the `link` island card (`island/link.ts` opens and holds the island, `transferOffer` calls the desktop cat). Keys live in the OS credential store (`keystore.rs`, `keyring`); a read that fails turns the link off with a sentence. `conformance.rs` and `windows/scripts/test-link-peers.sh` are the cross-checks with the Mac; the Mac's twin is `LinkService.swift`.
   - **Sub-project H on Windows/Linux:** the `cat` block's `desktop` object (`on`, `size`, `spots`) is cleaned with the rest of the block by `cat/display.ts` and `clean_cat_block`. The island's page is the brain: `island/desktop.ts` runs the trip (`cat/desktoptrip.ts`, from `desktopStep`), takes the cat out of the notch (a press on it that moves 4 px, `cat/pressdrag.ts`), asks `State.attentionNeeded` for alerts and keeps the notch's big-cat spot empty (`State.desktopNotchEmpty`) while the cat is out. A second window, `desktop.html`, is the body: `desktop/body.ts` draws the cat, flies it (`cat/desktopflight.ts`), takes the clicks and the drag (`cat/gestures.ts`), and keeps to the frame rate the contract gives (`cat/desktopgov.ts`). Rust (`src-tauri/src/desktop.rs`) only moves and shows the window, decides what takes the mouse and relays the messages between the two pages.
   - **Sub-project F1 on Windows/Linux (the sidekick):** the rules are `shared/sidekick-core.js`, copied into `windows/src/sidekick/core.generated.ts` by `scripts/gen-sidekick-ts.mjs`. `island/hooks.ts` feeds the memory-only ledger (`sidekick/ledger.ts`) before the one-card gate; `Sidekick` (`sidekick/controller.ts`, installed through `sidekick/hub.ts`) asks the rules for a recap on return (`presence.ts` from the platform's lock, sleep and display news and a lazy idle reading), for nudges (`stuckclock.ts`: one one-shot timer) and for the permission line (`explain.ts`), and offers every note to the gate (`notes.ts`) which opens the island through its existing peek on a new `sidekick` view. The chat answers "What's Claude doing?" itself (`statuschat.ts`); a drop on an agent's cat copies the path (Rust `copy_text`); a local model may reword a note (`voice.ts`, Rust `ai_oneshot`).
   - **Sub-project G1 on Windows/Linux (the shelf):** `src/shelf/rules.ts` replays `tests/fixtures/shelf/`, and `src-tauri/src/shelf.rs` replays only `shelf-cases.json` (the zone rows are checked by the TypeScript test); Rust owns `shelf.json` and the files (the page holds ids, never paths: every command that touches a file takes an id), the page holds the list (`shelf/store.ts`, `State.shelf`). A drop's half is `zoneAt` on the pointer (`shelf/dropflow.ts`); the halves are a layer over the unchanged drop canvas (`shelf/zones.ts`), a Shelf drop skips the desktop cat's wait (`Island.shelfDrop`), and an item dragged out and back is ignored (`shelf/dragguard.ts`). Drag out, Send and Show in folder are native (`dragout.rs`, `platform/*/drag.rs`, `platform/windows/share.rs`, `platform::reveal_file`), and `BootInfo.shelf` says what a system can do. The badge (`shelf/badge.ts`) is a function of the island's mode.
   - **Sub-project I (the wardrobe):** its contract is in `design/prototype/cat-core.js` and `tests/fixtures/cat/wardrobe-cases.json` (new names only; the prototype's Wardrobe panel draws it, and `shared/theme.json` has the `outfits` colours): `OUTFIT_IDS` and `cleanWardrobeSettings`, Auto's calendar (`easterOf`, `autoOutfitFor`, `resolveOutfit`), who wears it (`outfitWorn(role)`: the big-cat role at every size, the compact notch included), where it sits (`outfitAnchors`, `outfitRoom`, the slots `OUTFIT_SLOTS` and `OUTFIT_ORDER`) and its shapes (`outfitGeometry`, checked by `outfitDigest`); see `docs/CAT-CONTRACT.md`, "The wardrobe (I-0)". The two app plans (I-mac, I-tauri) build on it. **On the Mac** it is built: `Wardrobe`, `WardrobeSettings` (`cat.outfit`) and `WardrobeAuto` hold the IDs, the clean-up and Auto; `WardrobeClock` resolves the stored choice for the date into `CatConfig.outfit` and keeps one wall-clock one-shot for the next midnight (only while the choice is `auto`); `CatOutfit` ports the anchors and shapes, `CatOutfitDraw` paints them at the renderer's three slots, and only the five big-cat views ask for an outfit (the role decides, never the diameter); Settings → Cat → Wardrobe, the island cat's right-click menu (new, Wardrobe only), the desktop cat's Wardrobe submenu and ⌃⌥G (`wardrobe`, off by default) all end in `CatSettingsStore.setOutfit`.
   - **Focus awareness's bounded exception to "no timer"** (owner-approved 2026-10-22; spec `docs/superpowers/specs/2026-10-17-focus-awareness-design.md`, "Calls made after the builder check", item 8): each stepped-back mark's 10-minute end is a one-shot wake through the Sidekick's existing clock, armed even with the Sidekick off. It never repeats or polls: one wake per mark lifetime, cancelled or re-armed when the mark ends early or is replaced. Windows/Linux: the stuck clock of `sidekick/controller.ts`, the same rule.
6. **Sidekick (sub-project F1).** The cats say something useful at task boundaries: a recap on return, a plain line and a risk label under a permission request, a nudge when an agent looks stuck, and "What's Claude doing?" in the chat. The brain is pure rules in `shared/sidekick-core.js` (no AI, always on; a local model may only polish a sentence), fed by a ledger of the hook events each app already receives and tested against `tests/fixtures/sidekick/` (`docs/SIDEKICK-CONTRACT.md`). It labels and remembers, never decides: only the user's click answers a request. **On the Mac** it is built: `Sidekick*.swift` are the Swift ports of the rules, replayed against the fixtures; `SidekickEngine` holds the flow and `HookServer` feeds the ledger before the pending-approval gate. There is one clock (`SidekickClock`, a one-shot timer), and `PresenceMonitor` is shared with the desktop cat. The card line, the notes, the chat answer and the drop: `docs/SPEC.md`, "Le compagnon".
   - **Sub-project I on Windows/Linux:** the `cat` block's `outfit` key is cleaned with the rest of the block by `cat/display.ts` and `clean_cat_block` (`clean_wardrobe_settings`). `cat/wardrobe.ts` and `cat/outfit.ts` port the contract's rules and shapes; `cat/outfitdraw.ts` paints them and `cat/renderer.ts` calls it at the three slots (behind, neck, top) when `DrawOptions.outfit` is set, which `BotEngine.outfit` does for the island's main cat, cat 2 and the desktop cat only. `island/wardrobe.ts` resolves the stored choice for today (`State.outfit`) and is Auto's one-shot midnight timer; the desktop cat's page is told the outfit in `BodyLook`. `settings/wardrobe.ts` is the Settings card, `core/wardrobemenu.ts` the shared Wardrobe submenu of the two right-click menus. There is no global shortcut.

7. **Projects (sub-project P).** P-0 is the rules only. `shared/projects-core.js` is pure and decides which project and role a Claude Code session has, the memory-only registry that the hook events of both apps feed, and the time-based states; it is tested against `tests/fixtures/projects/` and documented in `docs/PROJECTS-CONTRACT.md`. **On the Mac** it is built (P-mac): `ProjectsRules`, `ProjectsRegistry`, `ProjectsSnapshot` and `ProjectsLayout` are the Swift ports, replayed by `scripts/test-projects-*.sh`. `ProjectsModel` keeps the registry in memory only and is fed by every Claude Code hook through `HookServer`; it arms one tick, only while the island is expanded. The island shows the project pills when Claude Code is the only agent (the Claude-only layout), or the expandable Claude panel when others are active, with the big card, the peek on hover, the compact amber waiting count and the Projects screen (the folder icon, the menu item or ⌃⌥P). A waiting project only adds to the count: it never opens or holds the island and never calls the desktop cat. P-tauri built it on Windows/Linux too: the generated copy of the contract (`windows/src/projects/core.generated.ts`), the model fed by `island/hooks.ts`, the views, and the tray's Projects item in place of the menu-bar item, with no shortcut. A session's full `cwd` never leaves memory; only folder names, worktree names, roles and step words are shown; a project's cat is stored by its folder name (`cat.projectCat.<folder>`).

8. **The companion (sub-project F3, the chat rebuild).** One chat for every brain, a companion with the cat's personality, a "Right now" view of the sessions from the Projects registry, and quick actions on selected text and screenshots (F3a, in the relaunch); a memory the user can see and edit and a daily recap (1.1); then actions (F3b), brainstorm to plan (F3c) and computer use (F3d). The rules are `shared/companion-core.js` (F3a-0: pure, tested against `tests/fixtures/companion/`, `docs/COMPANION-CONTRACT.md`); the Mac port and views are F3a-mac, the Windows/Linux generated copy F3a-tauri. The memory and the conversations are plain files the user owns; nothing leaves the machine except through the brain the user picked. **On the Mac** the relaunch core is built: the rules are Swift ports replayed by `scripts/test-companion-prompt.sh` and `scripts/test-companion-rules.sh`; `CompanionStore` owns the conversation files (owner-only); `Companion` builds each turn's prompt parts on the main actor and `ClaudeService` finishes them per target inside `ChatRunner` (the Claude plan gets them as the turn's preamble); "Right now" reads `ProjectsModel.shared.view()`; Services give Fix, Rewrite and Explain from any app; Settings → AI and chat → Companion holds Humor, See my sessions, Conversations and What the AI saw last.

**Settings (Mac).** Three layers. The pure rules and the control map are plain Swift (`SettingsRoute`, `SettingsLayout`, `SettingsDrafts` and `SettingsDraftBook`, `SettingsStatus`, `SettingsSidekick`, `SettingsAI`, `SettingsMap` with `tests/fixtures/settings/controls.json`). The kit and the page views take plain values, so `scripts/render-settings.sh` draws every page without the app. The app side is `SettingsController` and `SettingsSections`, which build those values from `AppState`, the Keychain and `HookServer`. Make main writes only `aiChoices.chat`. The Windows/Linux Settings gets the same pages in its own plan.

**Settings (Windows and Linux).** The same three layers, in TypeScript under `windows/src/settings/`: the pure rules (`route.ts`, `layout.ts`, `status.ts`, `drafts.ts`, `sidekicktab.ts`, `airows.ts`, `aicache.ts`), the kit and the pages (`kit.ts`, `shell.ts`, one file per page; the Cat page is `cat.ts` with `display.ts` and `wardrobe.ts` beside it), and `backend.ts`, which the pages go through to reach Rust. The island's rule for an agent switch is in `core/state.ts`. A page exists only while it is shown: `shell.ts` disposes the last one before it builds the next. Make main writes only `ai.chat`. The page never reads a stored secret; it knows only whether a key is saved, and typed text that is not saved is dropped when the window hides (`settings-hidden`). The window follows the system's light or dark appearance. The island opens a page through `open_settings_window(place)`, which emits `settings-place`.

## Code map (graphify)

`graphify-out/` holds a knowledge graph of the repo: about 2,000 nodes and 99 communities.
It is excluded from git locally via `.git/info/exclude`, never `.gitignore`.

- **Overview:** `graphify-out/GRAPH_REPORT.md`, with the communities, hubs and surprising links.
- **Ask a question** (from the repo root):
  - `graphify query "How does chat flow from the UI to the AI provider?"`
  - `graphify path "PromptView" "ClaudeService"`
- **Refresh** after big changes with an incremental graphify update of the changed files.
  A full rebuild costs millions of tokens.

## How AI agents work in this repo

- **Haiku 5.5 first; Sonnet 5.5 only when the task needs it** (owner's rule, 2026-10-12). Never Opus
  or Fable, except that **implementation plans are written on Opus 5.5** (`claude-opus-5-5`; owner's
  rule, 2026-10-17). Every subagent starts from Haiku 5.5 (`claude-haiku-5-5`) and moves to Sonnet 5.5
  (`claude-sonnet-5-5`) only for one of `CLAUDE.md`'s five triggers (platform APIs or concurrency to
  design, an unknown failure or Haiku's third try, design work, a whole-branch or security review, an
  app-plan controller), named in the brief or the ledger. Otherwise Haiku 5.5 runs at low effort for
  lookups and mechanical edits, medium for given code, fixtures, docs and CI, and high for multi-file
  coding, task reviews and visual checks. The main session coordinates and reviews.

  | Work | Model, effort | Agent (`~/.claude/agents/`) | Skills it loads |
  |---|---|---|---|
  | Transcribing a plan task with full code, fixtures, docs, CI | Haiku 5.5, medium | `nm-implementer-light` | `ponytail:ponytail`, `superpowers:test-driven-development`, `superpowers:verification-before-completion` |
  | Normal multi-file coding | Haiku 5.5, high | `nm-implementer` | same |
  | Hard integration, platform APIs, debugging, Haiku's third try | Sonnet 5.5, high | `nm-implementer-deep` | same, plus `superpowers:systematic-debugging` |
  | Task reviews, fix re-reviews | Haiku 5.5, high | `nm-reviewer` | `ponytail:ponytail-review` |
  | Whole-branch final review | Sonnet 5.5, high | `nm-reviewer-deep` | `ponytail:ponytail-review`, `superpowers:requesting-code-review` |
  | Specs, multi-source research | Sonnet 5.5, medium | any | research skills |
  | Implementation plans: drafts with their dry runs, and rewrites | Opus 5.5, high | any (`model: opus`) | `superpowers:writing-plans` |

  Ponytail keeps code minimal but never cuts what a plan or spec explicitly asks for, nor tests,
  security or privacy rules.
- **Extra skills by kind of work** (owner's rule, 2026-10-17). The brief names the ones that apply;
  the project's rules win over any skill. Skills marked *(file)* come from a catalog that is not
  installed as a plugin: the agent reads `~/.claude/plugins/marketplaces/ecc/skills/<name>/SKILL.md`
  instead of calling the Skill tool, and only the parts that fit the task.

  | Work | Skills |
  |---|---|
  | Swift code on the Mac | `swift-concurrency-6-2` *(file)* for actors, `Task` and isolation (the link, the shelf, timers); `swiftui-patterns` *(file)* for views. The app's Swift 6 settings and existing patterns win where the skill differs. |
  | Rust code (Windows and Linux) | `rust-patterns` *(file)*, `rust-testing` *(file)*. No new crate without the owner's approval. |
  | Whole-branch final review | `nm-reviewer-deep`, and beside it the `pr-review-toolkit:silent-failure-hunter` and `pr-review-toolkit:pr-test-analyzer` agents on the same diff (pass `model: sonnet`: trigger 4). |
  | Security or privacy review (Keychain, the link, file access, hooks) | `security-review` |
  | Chat rebuild (F3): spec checks, plans, reviews | `agent-security-hardening`, `agent-harness-construction` *(file)*: tool permissions, untrusted content, action design, computer use |
  | Settings polish | `accessibility` *(file)* and `design-system` *(file)*, as an audit before any restyle. `design-system` never writes a tokens file: `shared/theme.json` stays the one source of colours. |
  | Relaunch | `shipping-and-launch` (the checklist), `browser-qa` (the site), `slopmonster` (README and site wording, only when asked) |
  | Driving a desktop app by hand, over and over | `cli-anything:cli-anything`: build a command-line harness instead of clicking. Installing it (`pip install -e .`) needs the owner's OK; never publish it to PyPI. |

  **Never load these on NotchMeow**, because each one breaks a rule above: skills that push, open
  PRs, deploy or post (`commit-push-pr`, `finishing-a-development-branch`'s push and PR steps,
  `github-ops`, `vercel:deploy`, `netlify-deploy`, `social-publisher` and the like); telemetry
  (`sentry-*`, `product-tracking-*`, `observability-and-instrumentation`, any memory cloud sync);
  restyle-by-default design skills (`frontend-design`, `redesign-existing-projects`, `impeccable`,
  the `design-taste-*` family); reverse engineering (`reverse-engineer-anything`, the `rea` tools:
  Coucou's code and art are never read); and skills that write hooks or Claude settings on their own
  (`update-config`, `hookify`, `git-guardrails-claude-code`, the hook-gating skills).
- **Delegate independent work in parallel.** Give each subagent a self-contained prompt:
  - file paths;
  - the skills to load: research skills for web work, `superpowers:writing-plans` for plans, `graphify` for code questions;
  - a verify step;
  - a short report format.
- **Two memories, two jobs.** The graphify graph (`graphify-out/`, in the repo) answers code questions.
  The Obsidian vault (`~/Documents/Obsidian Vault`) holds what the code can't: decisions, session
  handoffs and project context, shared across Claude clients. The main session reads the vault at
  the start (`Home.md`, the newest `03-Sessions/` note, `01-Projects/NotchMeow.md`) and writes back:
  a `03-Sessions/` handoff when work pauses, and a `02-Decisions/` note for each meaningful decision.
  Worktree sessions and subagents only read the vault, so parallel sessions never race on one note.
  The graph is never exported into the vault, and when they disagree the repo wins.
- **Plans run in git worktrees** (`superpowers:subagent-driven-development`), one branch per plan.
  Independent plans run in parallel, each in its own worktree chat session.
- **Worktree chat sessions follow the same rule:** Haiku 5.5 first, Sonnet 5.5 only for an app plan
  with hard integration (trigger 5), never Opus or Fable (Opus 5.5 only for a session that writes an
  implementation plan).

  | Worktree session runs | Model, effort |
  |---|---|
  | A docs-only or mechanical chore, a plan whose tasks are given in full (contracts, fixtures, sound recipes, small fixes), or one small fix | Haiku 5.5, medium |
  | A plan that needs some judgement but no platform design (the site, release scripts) | Haiku 5.5, high |
  | A plan with hard integration, platform APIs, concurrency or many cross-task interfaces (the app plans) | Sonnet 5.5, high |

  A session chip's first turn runs on the app's default model, and a model change applies only from a
  session's next turn. So the main session starts each worktree session in three steps:
  1. The chip's prompt only sets up: switch to the plan's base, read `CLAUDE.md`, this file, the plan
     and the spec, report "ready" and stop.
  2. Once the owner starts the chip, the main session sets that session's model and effort from the table
     (`set_session_model`, `set_session_effort`).
  3. The main session then sends the controller brief as the next message, so the whole plan runs on
     the configured model.

  The chip's prompt also carries the owner's advance approval of that brief, because a session never
  takes a message from another session as the owner's approval. Every brief ends with the ping rule:
  at each owner checkpoint, at the end, and whenever it stops (a refusal, a failed check, a question),
  the worktree session sends its report to the main session with `SendMessage` (the main session's
  `local_…` id, given in the brief) as well as writing it in its own chat. The main session then
  double-checks the work (its own clone, merge and full checks) before anything reaches the owner.

  Before any follow-up turn (a fix round, a question, a resumed run), the main session checks the
  session is still on its configured model and effort. This covers finished sessions too, since any
  of them can be resumed. The main session itself runs on whatever model the owner picks in the app.
- **Archive a worktree session once it's no longer needed,** to keep the sidebar group tidy. A session
  is no longer needed when its branch is merged (or dropped with the owner's OK), its final report has
  reached the owner, and no fix round or question is pending. Archiving also deletes the session's
  worktree folder, so first:
  1. confirm the worktree has no uncommitted work (`git status`);
  2. copy its work ledger (`.superpowers/sdd/`) to the main checkout's `.claude/archive/sdd/<branch>/`;
  3. note any manual checks still owed to the owner from its final report in the project notes;
  4. move the worktree folder to the Trash (never delete it) and run `git worktree prune`.

  Then archive the session (`archive_session`). It can be reopened from the Archived list.
- **Process:** brainstorm, then spec (`docs/superpowers/specs/`), then plan
  (`docs/superpowers/plans/`), then implementation. Each sub-project (A–G) gets its own approve-then-build cycle.
- **Verify before claiming:** build, run the `scripts/test-*.sh` tests and `cargo test`, then report the evidence.
- **Git:** commits are local and use the repo identity. Never push, and never commit or push without the owner asking.
