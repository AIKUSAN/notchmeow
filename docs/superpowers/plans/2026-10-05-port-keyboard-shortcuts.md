# Keyboard Shortcuts (macOS) Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the macOS app keyboard shortcuts, ported by hand from Coucou's "Keyboard shortcuts" (upstream `9fe8294`, #205, released as Coucou 0.1.7): global shortcuts that work from any app (open the chat, go to the alert that is waiting, jump to the terminal, attach the front window, next and previous pill, mute, and open or close the island), shortcuts inside the island, and a Settings → Shortcuts section to turn each global one on or off, change its keys, or turn them all on at once. Five are on at first and three are off with their combinations kept (the owner's decision, below). The desktop and wardrobe actions are left out: they arrive with sub-projects H and I.

**Architecture:** `ShortcutLogic.swift` is Foundation-only (the actions, their defaults, the stored values with their validation, the island's own key map) and is tested by a `swiftc` program, the repo's pattern. `HotKeyCenter.swift` registers the global shortcuts with Carbon `RegisterEventHotKey` (no permission), and a second `swiftc` program tests it, simulating a key press with a Carbon event. `IslandWindowController` runs the actions and, while the island is the key window, the island's keys from a local `NSEvent` monitor; `EscapeRouting` decides who gets ⎋, and `KeyLayoutNames` names a key as the keyboard layout in use prints it. Settings gets a "Shortcuts" pane next to the existing sections. Upstream's change is read as a guide, not copied: the "Port notes" table lists what this plan does differently, and why.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI, AppKit and Carbon (`Carbon.HIToolbox`, a system framework: no dependency is added), XcodeGen, `swiftc` test programs, Bash.

**Spec:** `docs/superpowers/specs/2026-10-03-notchmeow-design.md`, the "Upstream ports" bullet: "Keyboard shortcuts (upstream 0.1.7, #205), after E1 merges. The desktop and wardrobe actions arrive with H and I." E1 has merged. The behaviour is written down by this plan in `docs/SPEC.md` §13 (in French, like the rest of that file). Read `CLAUDE.md` and `ARCHITECT.md` first.

**Base:** a new branch `shortcuts/mac` in a git worktree, from `notchmeow/rebrand` at `49a9d1a` or later, with this plan file already committed to `notchmeow/rebrand`. This plan touches nothing under `windows/`: upstream's change is macOS only, and the Windows and Linux app has no global shortcuts to match (see "Windows and Linux").

## Global Constraints

Every task's requirements include this section. Values are copied from `CLAUDE.md` and the spec.

- **Swift 6, SwiftUI and AppKit, no third-party dependencies.** Carbon is a system framework that ships with macOS; nothing is added to `project.yml`.
- **Never restyle what already ships.** The General → Hotkey box, the sidebar, the cards and the chat keep their look. The only visible additions are the new "Shortcuts" sidebar row and pane, and the highlight of a selected row in a GitHub list, which exists only while someone selects a row with the keyboard. New text is English, sentence case, no full stop on labels, like the rest of Settings.
- **Frozen names.** Never rename a pill ID, a cat ID, `nm-hook`, `nm.sock`, `notchmeow-hook`, `nm_kind`, `nm_agent`, a bundle identifier (`io.github.aikusan.notchmeow`, `io.github.aikusan.notchmeow.store`) or an existing notification name. The old Hotkey setting's UserDefaults keys `hotkeyEnabled`, `hotkeyFlags` and `hotkeyCode` keep their names and meaning (flags are `NSEvent.ModifierFlags` raw bits stored as an `Int`): a Mac that already uses the hotkey keeps it. New internal notification names follow the existing `notchBuddy.*` form.
- **Never reintroduce Coucou's names or assets.** No `Coucou` or `Mochi` in code, strings, defaults keys or comments this plan adds. Carbon's hot-key signature is `NMEW`, not upstream's `COUC`. Upstream's code is read, never merged or cherry-picked.
- **macOS is the primary platform:** it gets at least what Windows and Linux get. They have no keyboard shortcuts today.
- **Never block Claude Code, never approve without an explicit click.** No shortcut answers a permission request or a question. While one waits, the pill shortcuts do nothing, and ⎋ does not close the island.
- **0 % CPU when the island is hidden.** No timer, no polling. The Carbon handler is driven by the system; the local key monitor returns at once unless the island is the key window.
- **No telemetry, no network, no Keychain access.** Nothing here touches them.
- **Which shortcuts are on at first** (the owner's decision of 2026-10-05). On: ⌃⌥A (go to the waiting alert), ⌃⌥W (attach the front window), ⌃⌥] and ⌃⌥[ (next and previous pill), ⌃⌥M (mute). Off, each keeping its default combination so that turning it on is one click: ⌃⌥Space (open the chat, because macOS uses it for "Select next source in Input menu"), ⌃⌥T (jump to the terminal, because Rectangle uses it for "Last Two Thirds") and ⌘⇧N (open or close the island, off as the old Hotkey setting always was, under the old `hotkey*` keys). Settings → Shortcuts says why under the row of each of the first two, in its existing wording style, and has a "Turn all on" button that turns on every shortcut whose combination is free and reports, and leaves off, any that is taken or refused.
- **A shortcut never takes plain typing.** A global shortcut needs ⌘ or ⌃ with at least one more modifier (`ShortcutSpec.isUsableGlobal`); the island keys need ⌘ alone and never ⌘⇧ or ⌘⌥.
- **The App Store build** (`APPSTORE`) has no terminal and no front-window shortcut, like the buttons that do the same things.
- **Tests never write to `~/Library/Logs/NotchMeow` or `~/Library/Preferences`.** Nothing here uses `AppLog`, and the tests use an in-memory settings store (a `UserDefaults` suite leaves a plist behind even after `removePersistentDomain`). `scripts/test-hotkeys.sh`, `scripts/test-escape.sh` and `scripts/test-keynames.sh` need a logged-in macOS session and are not CI steps; `scripts/test-shortcuts.sh` is one.
- **Commits:** local only, never pushed, and only the files each task lists. Each message ends with the `Co-Authored-By` line of the model that wrote it: `Claude Sonnet 5.5` for `nm-implementer` and `nm-implementer-deep`, `Claude Haiku 4.5` for `nm-implementer-light`.
- **Never edit `NotchBuddy.xcodeproj` by hand.** Tasks that add Swift files run `cd NotchBuddy && xcodegen` and commit the regenerated `project.pbxproj`.

## Review Focus

The spec says what the shortcuts must do. It is silent on these conditions, and each would bite a person first. Each line names the test that pins it.

1. **⎋ while the island has the keyboard.** The island is the key window after a shortcut opens it, and in the chat. Expected: ⎋ closes it (unless it is pinned or an approval holds it open), except when a focused view wants ⎋ for itself (the "Other…" field, a list that goes back, a diff) or when the chat field is composing text (an input method or a dead key: ⎋ cancels the composition and the island stays). Upstream asked `NSApp.sendAction(cancelOperation:)` whether a view had taken it, but the panel itself answers that action, so the answer is always "yes" and, with the island as key window, ⎋ never closed it. Test: Task 3, `scripts/test-escape.sh` (real SwiftUI views in an invisible panel: the panel says "handled" with nothing focused, and `EscapeRouting.consumer` still finds no view; a focused `.onExitCommand` view and field are found and run once; marked text in the chat field makes `EscapeRouting.isComposing` true). The close itself is a manual check.
2. **⌘ with an arrow key while typing in the chat.** In a text field, ⌘← and ⌘→ go to the start and end of the line and ⌘↑ ⌘↓ to the start and end of the text. Expected: they still do, and the pill and list shortcuts work everywhere else. Test: Task 1, "island keys in the chat".
3. **A pill shortcut while a permission request or a question is waiting.** The card must stay on screen with the agent it belongs to; a pill shortcut would swap the pill under it. Expected: nothing happens. Test: Task 1, "pills" (`decisionWaiting`).
4. **A keyboard that is not US.** A shortcut is a key *position* (Carbon uses virtual key codes): ⌃⌥A is the key the US layout labels A, which an AZERTY keyboard labels Q, and a QWERTZ keyboard swaps Y and Z. Expected: Settings shows the character printed on the key to press, and ⌘, is the comma wherever the layout puts it. Tests: Task 1, "display strings" and "island keys" (a fake layout and `characters`), and Task 4, `scripts/test-keynames.sh` (the real US, French and German layouts that macOS ships). The labels on screen are manual check 9.
5. **A combination or a stored value that is wrong.**
   - *A combination that would take plain typing from every app:* a bare key, ⇧ or ⌥ alone (capital letters, accents), ⌘ or ⌃ alone (every Edit-menu and Emacs key). Carbon consumes a registered key press, so one such shortcut breaks typing everywhere. Expected: the recorder refuses it with a beep, and a stored one (the old Hotkey setting accepted any modifier) is ignored for the default.
   - *A stored value that cannot be trusted* (hand-edited, or from an old build): a negative or huge key code (`UInt16(-1)` traps, in upstream and in `AppState`'s own loading today), flags of the wrong type, one half missing. Expected: the default, never a crash. And a Mac that already set the old Hotkey keeps it, under the same keys.
   - *A combination another app already holds* when someone presses "Turn all on": that shortcut must stay off and be reported, not registered half-way. Expected: the rest come on, the taken one is named ("Left off: …"), tagged "In use elsewhere" and beeps once; a second press retries it.
   - Tests: Task 1, "which combinations may be global", "recorder keys", "stored values that cannot be trusted", "legacy hotkey keys" and "turn all on" (and Task 2's, which runs it against the real Carbon wrapper).

---

## Port notes: what upstream does and what this plan does instead

Upstream's change (`git show 9fe8294`, with `b5f7c0b` after it, which is only the version bump, the changelog and a README row) is macOS only: fourteen files, and nothing under `windows/`.

| Upstream | This plan | Why |
|---|---|---|
| Every global shortcut but ⌘⇧N on at first, ⌃⌥Space and ⌃⌥T among them | Five on (⌃⌥A, ⌃⌥W, ⌃⌥], ⌃⌥[, ⌃⌥M); ⌃⌥Space, ⌃⌥T and ⌘⇧N off with their combinations kept, a note under the first two in Settings, and a "Turn all on" button that skips and reports any combination that is taken | The owner's decision of 2026-10-05: macOS uses ⌃⌥Space ("Select next source in Input menu") and Rectangle uses ⌃⌥T ("Last Two Thirds"). A probe showed that Carbon still registers both on a Mac, so only a combination another app registered through Carbon is refused: the note is what warns about the others |
| Ten global actions, including `desktopToggle` (⌃⌥D) and `wardrobeToggle` (⌃⌥G), with `DesktopMochiController.flyOutOrHome()` | Eight: those two, and the `DesktopMochi.swift` change, are left out. New actions are appended at the end of the enum | The spec: they arrive with H and I. Carbon identifies a hot key by its index in `allCases` |
| `NSApp.sendAction(cancelOperation:)` decides whether a view handled ⎋, and the island closes if not | `EscapeRouting.consumer(in:)` walks the responder chain below the panel, and a field that is composing text keeps its ⎋ (`isComposing`) | Verified while planning: the panel answers `cancelOperation:`, so `sendAction` is always true; an input method needs ⎋ to cancel its composition |
| ⌘←→↑↓ always switch pills and move the list, even in the chat | In the chat they are left to the text field | They are caret movement there |
| The test `testLoadSaveRoundTrip` writes raw UserDefaults and never calls `hotKey(for:)` | `ShortcutLogic` takes the store it works on (`ShortcutStore`: `UserDefaults` in the app, a dictionary in the tests), and every storage rule is tested through it | The upstream test could not fail, and a `UserDefaults` suite leaves a plist in `~/Library/Preferences` for every test, even after `removePersistentDomain` (found while planning: 416 files) |
| `UInt16(kc)` and `UInt(fl)` on stored values; `AppState` does the same for the old keys | Validated: the default for anything that is not a key code from 0 to 127, a pair of Ints and a usable combination. `AppState.hotkey*` now read and write `ShortcutLogic` | A stray value trapped at launch |
| Any single modifier is accepted | `isUsableGlobal`: ⌘ or ⌃, and at least two modifiers | Carbon consumes the key press |
| Two shortcuts on one combination are both registered | The second is refused and reported; the first in the list keeps it | Verified while planning: Carbon accepts both from one app and runs one |
| The island is opened without telling the island state machine | `fsm.openedExternally()`, as a hook alert does | Its timers could fold the island under the user |
| ⌃⌥T is registered in the App Store build too, with an empty handler | `isNonAppStore` covers ⌃⌥T and ⌃⌥W: not registered, not listed | A dead shortcut would still eat the key press |
| ⌃⌥W attaches the front window and keeps the conversation | It starts a new one (`clearConversation(state:)`), like the drag onto the cat | E1: the window context only goes with a conversation's first message |
| `ClaudeService.shared.clearConversation()` and `state.chatHistory = []` | `clearConversation(state:)` does both | E1 changed the signature |
| General → Hotkey and the Shortcuts pane edit two copies of the same setting | One store, `ShortcutLogic`; General's two `@State` copies are gone | They went out of step |
| Pill shortcuts replace a waiting approval or question on screen | They do nothing while one waits | See Review Focus 3 |
| The selected list row is drawn above the text, never scrolled into view, and kept when the list shrinks or closes | Drawn behind the row; the list scrolls to it; the selection resets on close, on a pill change and when the list shrinks (`clampSelection`); ⌘O and ⌘↓ act only on the overview | Only three rows show; a stale index opened an invisible item |
| The recorder lets two rows listen at once, leaks its monitor when the pane closes, cannot be cancelled and shows `[`, `]` and arrows as "·" | One recorder at a time, ⎋ cancels, the monitor is removed when the row goes, every key has a name | The pane has eight recorders |
| Keys are labelled with the US names, and ⌘, is key code 43 | Labels come from the layout in use (`KeyLayoutNames`, `UCKeyTranslate`); ⌘, is matched by its character | A shortcut is a key position: on AZERTY the pane would read ⌃⌥A for the key labelled Q, and ⌘, would be the `;` key |
| Settings text "Mochi on / off desktop", `COUC`, `coucouHotKeyEventHandler`, `com.coucou…` | NotchMeow's own names | The rename rules |
| The SPEC text says ⌘E edits the prompt and ⌘P copies the last message | The code's behaviour is documented: ⌘E opens or closes the latest diff, ⌘P pins the island | The text and the code disagreed |

Left as upstream has them, on purpose: the global shortcuts that open the island make it the key window until it closes (so the island's keys and ⎋ work), and ⌃⌥Space opens the chat without toggling. These are in "Open questions".

---

## File Structure

| Path | Responsibility |
|---|---|
| `NotchBuddy/Sources/App/ShortcutLogic.swift` | New. Foundation only. `ShortcutAction`, `ShortcutSpec`, `IslandCommand`, `IslandKeyContext`, `ShortcutLogic` (defaults and which are on at first, "Turn all on", storage with validation, availability by build, Carbon modifiers, duplicates, key names, list selection, pill choice, the island's key map, the Settings table, the terminal list). |
| `NotchBuddy/Sources/App/HotKeyCenter.swift` | New. The Carbon wrapper: install the handler once, register what is on, report conflicts, release on quit. |
| `NotchBuddy/Sources/App/EscapeRouting.swift` | New. Which responder, if any, takes ⎋ before the island closes, and whether the chat field is composing text. |
| `NotchBuddy/Sources/App/KeyLayoutNames.swift` | New. The character printed on a key in a keyboard layout (`UCKeyTranslate`), for labels. |
| `NotchBuddy/Sources/App/ShortcutsSettingsView.swift` | New. Settings → Shortcuts. |
| `NotchBuddy/Sources/App/IslandWindowController.swift` | Runs the global actions, the local key monitor and ⎋; the four notification names; the old NSEvent hotkey monitor goes. |
| `NotchBuddy/Sources/App/AppDelegate.swift` | Releases the hot keys on quit. |
| `NotchBuddy/Sources/App/AppState.swift` | `hotkey*` become views of `ShortcutLogic`; `cardSelection` and `cardItemCount`. |
| `NotchBuddy/Sources/App/IslandViewContent.swift` | ⌘E in the overview; ⌘↩ and ⌘K in the chat; the GitHub list's selection, scrolling and ⌘O. |
| `NotchBuddy/Sources/App/SettingsView.swift` | The sidebar row and routing, the General hotkey box on the shared store, the recorder (and its label). |
| `tests/ShortcutTests.swift`, `tests/HotKeyCenterTests.swift`, `tests/EscapeRoutingTests.swift`, `tests/KeyLayoutNamesTests.swift`, `scripts/test-shortcuts.sh`, `scripts/test-hotkeys.sh`, `scripts/test-escape.sh`, `scripts/test-keynames.sh` | The four `swiftc` test programs and their scripts. |
| `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` | Regenerated by XcodeGen, never by hand. |
| `docs/SPEC.md`, `README.md`, `CHANGELOG.md`, `CLAUDE.md`, `.github/workflows/build.yml` | §13 (French), a README line, a changelog entry, a pointer, one CI step. |

Nothing under `windows/` and nothing in `ARCHITECT.md`.

### Overlap with the two cat plans (they run at the same time)

Both cat plans (`2026-10-04-a-mac-cats-stages-1-4.md`, `2026-10-04-a-tauri-cats-stages-1-4.md`) were read for their **Files:** blocks. The Tauri plan touches only `windows/`, `CLAUDE.md`, `ARCHITECT.md` and its own CI file. The Mac plan says it touches no `IslandWindowController.swift`, `AppState` or `HookServer`.

| File | Here | Cat plans | What to do |
|---|---|---|---|
| `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` | regenerated in Tasks 1 to 4 | regenerated by the Mac plan, in six of its tasks | **A conflict is certain on the second merge.** Take either side, run `cd NotchBuddy && xcodegen`, `git add` the result. Never merge it by hand. |
| `NotchBuddy/Sources/App/AppDelegate.swift` | one method, at the top of the class (anchored on the `islandController` property and `applicationDidFinishLaunching`) | the Mac plan adds a Debug menu item in `setupMenuBarItem` and a window method above `placeBelowIsland` | Disjoint hunks: git merges them. |
| `CLAUDE.md` | one bullet after the `PillCatalog.swift` bullet | the Mac plan replaces the `cat-core.js` bullet; the Tauri plan edits the `windows/` bullet | Disjoint. If git still reports a conflict, keep every line. |
| `.github/workflows/build.yml` | one step after "Diff engine tests" | the Mac plan edits the "Cat contract" step | Disjoint. |
| `IslandWindowController.swift`, `IslandViewContent.swift`, `AppState.swift` | edited | not touched | None. |
| `SettingsView.swift` | the sidebar (a row after "Integrations"), the General hotkey box, `ShortcutRecorderButton` | not touched by stages 1 to 4; the later stages 5 to 7 add the cat settings rows here | Merge this plan first, and let the cat stages 5 to 7 plan anchor on the merged file. |
| Everything else here | new files | none | None. |

Neither order is wrong. The simplest: merge this branch first (it is small and touches no drawing code), then the cat branch merges `notchmeow/rebrand`, regenerates the project and carries on. One thing to know if it goes that way: the Mac plan's Task 15 checks that its branch left `AppState.swift` and `IslandWindowController.swift` alone with `git diff --stat notchmeow/rebrand -- …`, which compares the working tree with the ref, so on a cat branch that has not yet merged this one the check would list this plan's changes. Merge `notchmeow/rebrand` into the cat branch before that check (or read the listed files as this plan's). This plan uses `BotEmote` (`.happy`, `.annoyed`), `SoundEngine` names `tick`, `error` and `approve`, and `.triggerEmote`: the cat plans keep all of them. If the sound plans rename a cue, this plan's four call sites follow.

---

## Execution

One worktree chat session runs the whole plan: branch `shortcuts/mac`, model **Sonnet 5.5 at medium effort** (`ARCHITECT.md`: a plan whose tasks are given in full). The platform APIs (Carbon hot keys, the keyboard-layout service, the responder chain) are small, and their code and their tests are given and were replayed while planning, so the session does not need high effort; if a task ends up in fix round 4 or 5, hand it to `nm-implementer-deep`. Nothing is pushed.

**Before the session starts,** this plan file is committed to `notchmeow/rebrand` (a docs-only commit): the controller does this, with the owner's OK, so the branch the session starts from already holds the plan it runs. **The base is `49a9d1a` or later:** `git merge-base --is-ancestor 49a9d1a HEAD` must succeed.

**The session is started in three steps** (`ARCHITECT.md`), because a chip's first turn runs on the app's default model and a model change applies only from a session's next turn:

1. **Setup and stop.** The chip's prompt only sets up:

   > Run `git switch -c shortcuts/mac notchmeow/rebrand`, then `git merge-base --is-ancestor 49a9d1a HEAD` and `git ls-files docs/superpowers/plans/2026-10-05-port-keyboard-shortcuts.md`: the first must succeed and the second must print the plan's path. If either fails, say so and stop. Read `CLAUDE.md`, `ARCHITECT.md`, `docs/superpowers/plans/2026-10-05-port-keyboard-shortcuts.md` and the "Upstream ports" bullet of `docs/superpowers/specs/2026-10-03-notchmeow-design.md`. Reply "ready" and stop. Do not start any task.

2. **Model.** Once the owner starts the chip, the main session sets that session to Sonnet 5.5 at medium effort (`set_session_model`, `set_session_effort`).
3. **Brief.** The main session then sends the controller brief as the next message:

   > Run `docs/superpowers/plans/2026-10-05-port-keyboard-shortcuts.md` with `superpowers:subagent-driven-development`, task by task, on this branch. Dispatch each task to the agent the plan names for it, then to `nm-reviewer`; fix what the review finds before the next task. After Task 5, dispatch `nm-reviewer-deep` over the whole branch (`git diff notchmeow/rebrand...shortcuts/mac`). Commit only as the plan's commit steps say, and never push. Never launch, quit or replace the installed NotchMeow app, and never run a build of it: the manual checks are the owner's. When you are done, report: the commits, the output of `scripts/test-shortcuts.sh`, `scripts/test-hotkeys.sh`, `scripts/test-escape.sh` and `scripts/test-keynames.sh`, the Debug build, the App Store Debug build and the Release build with `check-app-binary.sh`, `~/Library/Logs/NotchMeow/nm.log`'s size before and after, and anything you could not settle.

Before any follow-up turn, the main session checks the session is still on its configured model and effort.

**Agents** (`CLAUDE.md`: the lightest model that fits). Tasks 1 and 5 are transcription of given code and docs with tests: `nm-implementer-light`. Tasks 2 to 4 edit existing AppKit and SwiftUI files at given anchors and are proven by a build and a read of the diff: `nm-implementer`. Task reviews: `nm-reviewer`; the final whole-branch review: `nm-reviewer-deep`. Coding agents load `ponytail:ponytail`, `superpowers:test-driven-development` and `superpowers:verification-before-completion` (the deep agent also `superpowers:systematic-debugging`); reviewers load `ponytail:ponytail-review`. Ponytail never cuts a test, a Review Focus line or a rule above.

**How the edits are written.** Existing files change by *replace this exact text with that text*. Each old text matches exactly one place in the base; if it does not, stop and say so (the file moved on): never guess. New files are given whole.

**Manual checks owed to the owner** (after the branch builds; an agent cannot do them, and none may be done by launching the installed app from a session):

1. From another app, ⌃⌥Space opens the chat with the cursor in the field; ⎋ then closes the island. In the chat, ⌘← ⌘→ move the cursor, ⌘K starts over, ⌘↩ sends. While an input method (Japanese, Chinese) or a dead key (^ on a French keyboard) is composing in the chat field, ⎋ cancels the composition and the island stays.
2. ⌃⌥A with nothing waiting: the annoyed emote and the `error` sound. With a permission request waiting: its card opens, and ⌃⌥] ⌃⌥[ ⌘1 do nothing to it. ⎋ does not close it.
3. ⌃⌥T brings the terminal forward and closes the island. ⌃⌥W with a window in front: the chat shows its context chip and starts a new conversation. ⌃⌥M mutes and unmutes.
4. ⌃⌥] and ⌃⌥[ cycle the pills and open the island if it is closed. In the island, ⌘→ ⌘← ⌘1 to ⌘9 switch pills, ⌘E opens and closes the latest diff, ⌘, opens Settings, ⌘P pins.
5. On the GitHub pill's list with more than three rows: ⌘↓ selects the first row, then each next one, and the list scrolls to it; ⌘O opens it on github.com; close the island and reopen it: nothing is selected.
6. A Mac with no stored shortcut settings: only ⌃⌥A, ⌃⌥W, ⌃⌥], ⌃⌥[ and ⌃⌥M are on. ⌃⌥Space and ⌃⌥T are off, with their combinations shown and a grey note under the row ("Off at first: macOS uses ⌃⌥Space for “Select next source in Input menu”." and "Off at first: Rectangle uses ⌃⌥T for “Last Two Thirds”."); the note goes away once the shortcut is on. "Turn all on" turns on the three that are off. With another app holding one combination (Rectangle running, say), "Turn all on" leaves that shortcut off, tags it "In use elsewhere", names it in an orange "Left off: …" line and beeps; "Reset to defaults" brings back the five-on, three-off state.
   Also in Settings → Shortcuts: record a new combination for a shortcut and use it; try ⇧A, ⌥A, ⌘A alone (a beep each); ⎋ cancels a recording; click one recorder and then another (only the second listens); give two shortcuts one combination ("Duplicate" shows on both); take one that another app has ("In use elsewhere" shows); turn one off; "Reset to defaults".
7. A Mac that already had the old Hotkey turned on keeps ⌘⇧N, and General → Hotkey and Settings → Shortcuts show the same combination whichever you change.
8. Click another app's window while the island has the keyboard: the island lets go of it.
9. On a non-US keyboard layout (System Settings → Keyboard, for example French): Settings → Shortcuts labels each shortcut with the character printed on the key to press (the default ⌃⌥A reads ⌃⌥Q on AZERTY, and that key triggers it), and ⌘, opens Settings.

---

### Task 1: The shortcut logic

Agent: `nm-implementer-light`.

**Files:**
- Create: `NotchBuddy/Sources/App/ShortcutLogic.swift`, `tests/ShortcutTests.swift`, `scripts/test-shortcuts.sh`
- Modify (regenerated): `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj`

**Interfaces:**
- Consumes: nothing.
- Produces, for every later task:
  - `enum ShortcutAction: String, CaseIterable, Sendable` with the cases `toggleIsland`, `openChat`, `goToAlert`, `jumpToTerminal`, `attachFrontWindow`, `nextPill`, `prevPill`, `muteToggle` (in that order), and `udKeyCode`, `udFlags`, `udEnabled: String`, `displayName: String`, `isNonAppStore: Bool`, `enabledByDefault: Bool` (on: `goToAlert`, `attachFrontWindow`, `nextPill`, `prevPill`, `muteToggle`; off: `toggleIsland`, `openChat`, `jumpToTerminal`) and `offAtFirstNote: String?` (the sentence Settings shows under `openChat` and `jumpToTerminal` while they are off, nil for the others).
  - `struct ShortcutSpec: Equatable, Hashable, Sendable { var keyCode: UInt16; var nsFlags: UInt }` with `cmdBit`, `shiftBit`, `optBit`, `ctrlBit`, `modMask`, `cmdShift`, `ctrlOpt`, `maxKeyCode`, `modifierCount: Int`, `isUsableGlobal: Bool`.
  - `enum IslandCommand: Equatable, Sendable` (`nextPill`, `prevPill`, `pill(Int)`, `listDown`, `listUp`, `openSelection`, `toggleDiff`, `sendMessage`, `newConversation`, `openSettings`, `togglePin`, `escape`), `struct IslandKeyContext: Equatable, Sendable { var inOverview: Bool; var inChat: Bool }` and `enum RecorderKey: Equatable, Sendable` (`cancel`, `passThrough`, `refuse`, `record(ShortcutSpec)`).
  - `struct ShortcutLogic.TurnOnResult: Equatable, Sendable { var action: ShortcutAction; var reason: Reason }` with `enum Reason: Equatable, Sendable { case taken; case duplicate(of: ShortcutAction) }`: a shortcut "Turn all on" left off.
  - `enum ShortcutLogic`: `defaults`, `isAppStoreBuild`, `available(appStore:)`, `hotKey(for:in:)`, `save(_:for:in:)`, `isEnabled(_:in:)`, `setEnabled(_:for:in:)`, `resetToDefault(_:in:)`, `activeSpecs(appStore:in:)`, `turnAllOn(appStore:in:tryOn:) -> [ShortcutLogic.TurnOnResult]`, `turnOnSummary(_:) -> String?`, `carbonModifiers(fromNS:)`, `duplicates(in:)`, `displayString(for:keyName:)`, `keyCodeToString(_:)`, `navigate(selection:delta:itemCount:)`, `clampSelection(_:itemCount:)`, `pillID(from:current:delta:decisionWaiting:)`, `pillID(number:in:decisionWaiting:)`, `recorderKey(keyCode:nsFlags:)`, `islandCommand(keyCode:nsFlags:characters:in:)`, `islandShortcuts`, `terminalBundleIds`. Every `in:` is a `ShortcutStore` defaulting to `UserDefaults.standard`; `protocol ShortcutStore { func object(forKey key: String) -> Any?; func set(_ value: Any?, forKey key: String) }`, which `UserDefaults` conforms to and the tests replace with a dictionary.

- [ ] **Step 1: Write the failing test and its script**

**Create `tests/ShortcutTests.swift`**

```swift
import Foundation

@main
enum ShortcutTests {
    nonisolated(unsafe) static var cases = 0

    /// One case: counts it, and stops the run with `message` when it fails.
    static func check(_ ok: Bool, _ message: @autoclosure () -> String,
                      file: StaticString = #file, line: UInt = #line) {
        cases += 1
        precondition(ok, message(), file: file, line: line)
    }

    static func main() {
        testDefaults()
        testUsableCombinations()
        testCarbonModifiers()
        testDisplayStrings()
        testDuplicates()
        testStorage()
        testLegacyHotkeyKeys()
        testStoredValuesThatCannotBeTrusted()
        testEnabledAndReset()
        testBuildsAndActiveSpecs()
        testTurnAllOn()
        testTurnOnSummary()
        testListSelection()
        testPills()
        testIslandKeys()
        testIslandKeysInTheChat()
        testIslandKeysWithOtherModifiers()
        testRecorderKeys()
        testTables()
        print("Shortcuts: \(cases) cases passed")
    }

    /// A settings store in memory, so a test run never writes a preferences file.
    final class MemoryStore: ShortcutStore {
        var values: [String: Any] = [:]
        func object(forKey key: String) -> Any? { values[key] }
        func set(_ value: Any?, forKey key: String) { values[key] = value }
    }

    /// A fresh, empty store for `body`.
    static func withDefaults(_ body: (MemoryStore) -> Void) { body(MemoryStore()) }

    static let ctrlOpt = ShortcutSpec.ctrlOpt
    static let cmd = ShortcutSpec.cmdBit
    static let shift = ShortcutSpec.shiftBit
    static let opt = ShortcutSpec.optBit
    static let ctrl = ShortcutSpec.ctrlBit

    // MARK: Defaults

    static func testDefaults() {
        for action in ShortcutAction.allCases {
            check(ShortcutLogic.defaults[action] != nil, "no default for \(action.rawValue)")
        }
        check(ShortcutLogic.defaults.count == ShortcutAction.allCases.count, "the table must cover every action, and only those")
        for (action, spec) in ShortcutLogic.defaults {
            check(spec.isUsableGlobal, "default of \(action.rawValue) would take plain typing from every app")
        }
        check(ShortcutLogic.duplicates(in: ShortcutLogic.defaults).isEmpty, "two defaults share a combination")
        testDefaultsOnAndOff()
        // Carbon identifies a hot key by its index in allCases: new actions are appended, never inserted.
        check(ShortcutAction.allCases.first == .toggleIsland && ShortcutAction.allCases.last == .muteToggle,
              "action order changed")
    }

    // MARK: Which shortcuts are on at first

    /// The owner's decision: five on, three off. The off ones keep their combinations so that turning one on is a click.
    static func testDefaultsOnAndOff() {
        let on: Set<ShortcutAction> = [.goToAlert, .attachFrontWindow, .nextPill, .prevPill, .muteToggle]
        let off: Set<ShortcutAction> = [.toggleIsland, .openChat, .jumpToTerminal]
        check(on.union(off) == Set(ShortcutAction.allCases) && on.isDisjoint(with: off), "every action is on or off at first")
        for action in on { check(action.enabledByDefault, "\(action.rawValue) is on at first") }
        for action in off { check(!action.enabledByDefault, "\(action.rawValue) is off at first") }
        withDefaults { ud in
            check(Set(ShortcutLogic.activeSpecs(appStore: false, in: ud).keys) == on, "a fresh store registers exactly the five")
            check(Set(ShortcutLogic.activeSpecs(appStore: true, in: ud).keys) == [.goToAlert, .nextPill, .prevPill, .muteToggle],
                  "and four in the App Store build, which has no front-window shortcut")
            // Off at first, and the combination is still there: a click turns it on.
            check(ShortcutLogic.hotKey(for: .openChat, in: ud) == ShortcutSpec(keyCode: 49, nsFlags: ctrlOpt), "⌃⌥Space is kept for the chat")
            check(ShortcutLogic.hotKey(for: .jumpToTerminal, in: ud) == ShortcutSpec(keyCode: 17, nsFlags: ctrlOpt), "⌃⌥T is kept for the terminal")
            check(ShortcutLogic.hotKey(for: .toggleIsland, in: ud) == ShortcutSpec(keyCode: 45, nsFlags: ShortcutSpec.cmdShift), "⌘⇧N is kept for the island")
            ShortcutLogic.setEnabled(true, for: .openChat, in: ud)
            check(ShortcutLogic.activeSpecs(appStore: false, in: ud)[.openChat] == ShortcutSpec(keyCode: 49, nsFlags: ctrlOpt),
                  "turned on, the chat is registered under ⌃⌥Space")
        }
        // The note Settings shows: for the two that are off because another app uses the combination, and for no other.
        check(ShortcutAction.openChat.offAtFirstNote?.contains("⌃⌥Space") == true
              && ShortcutAction.openChat.offAtFirstNote?.contains("Select next source in Input menu") == true, "the chat's note names macOS's shortcut")
        check(ShortcutAction.jumpToTerminal.offAtFirstNote?.contains("⌃⌥T") == true
              && ShortcutAction.jumpToTerminal.offAtFirstNote?.contains("Rectangle") == true
              && ShortcutAction.jumpToTerminal.offAtFirstNote?.contains("Last Two Thirds") == true, "the terminal's note names Rectangle's")
        for action in ShortcutAction.allCases where action != .openChat && action != .jumpToTerminal {
            check(action.offAtFirstNote == nil, "\(action.rawValue) has no note")
        }
    }

    // MARK: Which combinations may be global

    static func testUsableCombinations() {
        func usable(_ flags: UInt) -> Bool { ShortcutSpec(keyCode: 0, nsFlags: flags).isUsableGlobal }
        check(!usable(0), "a bare key")
        check(!usable(shift), "⇧ alone types capital letters")
        check(!usable(opt), "⌥ alone types accents")
        check(!usable(shift | opt), "⇧⌥ types symbols")
        check(!usable(cmd), "⌘ alone is every Edit-menu key")
        check(!usable(ctrl), "⌃ alone is every Emacs key in a text field")
        check(usable(cmd | shift), "⌘⇧")
        check(usable(cmd | opt), "⌘⌥")
        check(usable(cmd | ctrl), "⌘⌃")
        check(usable(ctrl | opt), "⌃⌥")
        check(usable(ctrl | shift), "⌃⇧")
        check(usable(cmd | shift | opt | ctrl), "all four")
        check(ShortcutSpec(keyCode: 0, nsFlags: cmd | shift).modifierCount == 2, "two modifiers")
        check(ShortcutSpec(keyCode: 0, nsFlags: 0).modifierCount == 0, "no modifiers")
    }

    // MARK: Carbon

    static func testCarbonModifiers() {
        let cmdShift = ShortcutLogic.carbonModifiers(fromNS: ShortcutSpec.cmdShift)
        check(cmdShift == 256 | 512, "⌘⇧ is cmdKey | shiftKey (\(cmdShift))")
        let ctrlOpt = ShortcutLogic.carbonModifiers(fromNS: ShortcutSpec.ctrlOpt)
        check(ctrlOpt == 4096 | 2048, "⌃⌥ is controlKey | optionKey (\(ctrlOpt))")
        check(ShortcutLogic.carbonModifiers(fromNS: 0) == 0, "no modifiers, no Carbon bits")
        let all = ShortcutLogic.carbonModifiers(fromNS: cmd | shift | opt | ctrl)
        check(all == 256 | 512 | 2048 | 4096, "all four")
        check(ShortcutLogic.carbonModifiers(fromNS: 1 << 16) == 0, "caps lock is not a Carbon modifier here")
    }

    // MARK: Display

    static func testDisplayStrings() {
        check(ShortcutLogic.displayString(for: ShortcutLogic.defaults[.toggleIsland]!) == "⇧⌘N", "⌘⇧N shows as ⇧⌘N")
        check(ShortcutLogic.displayString(for: ShortcutLogic.defaults[.goToAlert]!) == "⌃⌥A", "⌃⌥A")
        check(ShortcutLogic.displayString(for: ShortcutLogic.defaults[.openChat]!) == "⌃⌥Space", "⌃⌥Space")
        check(ShortcutLogic.displayString(for: ShortcutLogic.defaults[.nextPill]!) == "⌃⌥]", "⌃⌥]")
        check(ShortcutLogic.displayString(for: ShortcutLogic.defaults[.prevPill]!) == "⌃⌥[", "⌃⌥[")
        check(ShortcutLogic.displayString(for: ShortcutSpec(keyCode: 49, nsFlags: cmd | shift | opt | ctrl)) == "⌃⌥⇧⌘Space",
              "modifier order is ⌃⌥⇧⌘")
        check(ShortcutLogic.keyCodeToString(123) == "←" && ShortcutLogic.keyCodeToString(126) == "↑", "arrows")
        check(ShortcutLogic.keyCodeToString(29) == "0" && ShortcutLogic.keyCodeToString(18) == "1", "digits")
        check(ShortcutLogic.keyCodeToString(50) == "`" && ShortcutLogic.keyCodeToString(27) == "-",
              "keys the General recorder already named")
        check(ShortcutLogic.keyCodeToString(122) == "F1", "F1")
        check(ShortcutLogic.keyCodeToString(127) == "·", "a key without a name shows a dot")
        // The layout in use names the key: on AZERTY the key at position 0 is labelled Q, the one at 12 is A.
        let azerty: (UInt16) -> String? = { code in [0: "Q", 12: "A", 13: "Z", 41: "M"][code] }
        check(ShortcutLogic.displayString(for: ShortcutSpec(keyCode: 0, nsFlags: ctrlOpt), keyName: azerty) == "⌃⌥Q",
              "the default ⌃⌥A is the key labelled Q on AZERTY")
        check(ShortcutLogic.displayString(for: ShortcutSpec(keyCode: 12, nsFlags: ctrlOpt), keyName: azerty) == "⌃⌥A", "and ⌃⌥Q is labelled A")
        check(ShortcutLogic.displayString(for: ShortcutSpec(keyCode: 49, nsFlags: ctrlOpt), keyName: azerty) == "⌃⌥Space",
              "a key the layout has no name for keeps its own")
        check(ShortcutLogic.displayString(for: ShortcutSpec(keyCode: 0, nsFlags: ctrlOpt)) == "⌃⌥A", "no layout, the US names")
        // Every key a default uses has a real name.
        for (action, spec) in ShortcutLogic.defaults {
            check(ShortcutLogic.keyCodeToString(spec.keyCode) != "·", "\(action.rawValue) shows a dot")
        }
    }

    // MARK: Duplicates inside NotchMeow

    static func testDuplicates() {
        check(ShortcutLogic.duplicates(in: [:]).isEmpty, "nothing, no duplicates")
        let a = ShortcutSpec(keyCode: 0, nsFlags: ctrlOpt)
        let b = ShortcutSpec(keyCode: 17, nsFlags: ctrlOpt)
        check(ShortcutLogic.duplicates(in: [.goToAlert: a]).isEmpty, "one entry")
        check(ShortcutLogic.duplicates(in: [.goToAlert: a, .jumpToTerminal: b]).isEmpty, "two different keys")
        check(ShortcutLogic.duplicates(in: [.goToAlert: a, .jumpToTerminal: a]) == [.goToAlert, .jumpToTerminal],
              "the same combination flags both actions")
        let c = ShortcutSpec(keyCode: 0, nsFlags: ShortcutSpec.cmdShift)
        check(ShortcutLogic.duplicates(in: [.goToAlert: a, .jumpToTerminal: c]).isEmpty, "same key, other modifiers")
        check(ShortcutLogic.duplicates(in: [.goToAlert: a, .jumpToTerminal: a, .muteToggle: a]).count == 3, "three share one")
    }

    // MARK: Storage

    static func testStorage() {
        withDefaults { ud in
            for action in ShortcutAction.allCases {
                check(ShortcutLogic.hotKey(for: action, in: ud) == ShortcutLogic.defaults[action]!, "nothing stored: the default")
            }
            let custom = ShortcutSpec(keyCode: 5, nsFlags: ShortcutSpec.cmdShift)
            ShortcutLogic.save(custom, for: .openChat, in: ud)
            check(ShortcutLogic.hotKey(for: .openChat, in: ud) == custom, "a saved shortcut comes back")
            check(ShortcutLogic.hotKey(for: .goToAlert, in: ud) == ShortcutLogic.defaults[.goToAlert]!, "others are untouched")
            check(ud.object(forKey: "shortcut.openChat.keyCode") as? Int == 5, "stored under its own key")
            check(ud.object(forKey: "shortcut.openChat.flags") as? Int == Int(ShortcutSpec.cmdShift), "flags stored as an Int")
        }
    }

    /// What the old Hotkey setting wrote (`AppState.hotkey*`) must still be read as the island shortcut.
    static func testLegacyHotkeyKeys() {
        check(ShortcutAction.toggleIsland.udKeyCode == "hotkeyCode", "legacy code key")
        check(ShortcutAction.toggleIsland.udFlags == "hotkeyFlags", "legacy flags key")
        check(ShortcutAction.toggleIsland.udEnabled == "hotkeyEnabled", "legacy enabled key")
        for action in ShortcutAction.allCases where action != .toggleIsland {
            check(action.udKeyCode == "shortcut.\(action.rawValue).keyCode", "\(action.rawValue) has its own code key")
            check(action.udFlags == "shortcut.\(action.rawValue).flags", "\(action.rawValue) has its own flags key")
            check(action.udEnabled == "shortcut.\(action.rawValue).enabled", "\(action.rawValue) has its own enabled key")
        }
        withDefaults { ud in
            // A person who set ⌃⌘J and turned the hotkey on, with the old build.
            ud.set(true, forKey: "hotkeyEnabled")
            ud.set(Int(ctrl | cmd), forKey: "hotkeyFlags")
            ud.set(38, forKey: "hotkeyCode")
            check(ShortcutLogic.isEnabled(.toggleIsland, in: ud), "the old toggle is read")
            check(ShortcutLogic.hotKey(for: .toggleIsland, in: ud) == ShortcutSpec(keyCode: 38, nsFlags: ctrl | cmd),
                  "the old combination is read")
            check(ShortcutLogic.activeSpecs(appStore: false, in: ud)[.toggleIsland] == ShortcutSpec(keyCode: 38, nsFlags: ctrl | cmd),
                  "and registered")
        }
    }

    /// A hand-edited file, an old build, a stray write: never a trap, never a shortcut that eats typing.
    static func testStoredValuesThatCannotBeTrusted() {
        let def = ShortcutLogic.defaults[.openChat]!
        func load(code: Any?, flags: Any?) -> ShortcutSpec {
            var result = def
            withDefaults { ud in
                if let code { ud.set(code, forKey: ShortcutAction.openChat.udKeyCode) }
                if let flags { ud.set(flags, forKey: ShortcutAction.openChat.udFlags) }
                result = ShortcutLogic.hotKey(for: .openChat, in: ud)
            }
            return result
        }
        let good = Int(ctrl | opt)
        check(load(code: -1, flags: good) == def, "a negative key code (UInt16(-1) used to trap)")
        check(load(code: 70000, flags: good) == def, "a key code beyond UInt16 (used to trap)")
        check(load(code: 128, flags: good) == def, "a key code no keyboard has")
        check(load(code: 5, flags: -1) == def, "negative flags (UInt(-1) used to trap)")
        check(load(code: "A", flags: good) == def, "a key code of the wrong type")
        check(load(code: 5, flags: "x") == def, "flags of the wrong type")
        check(load(code: 5, flags: nil) == def, "only the code stored")
        check(load(code: nil, flags: good) == def, "only the flags stored")
        check(load(code: 5, flags: 0) == def, "no modifier would take the bare key from every app")
        check(load(code: 5, flags: Int(shift)) == def, "⇧ alone")
        check(load(code: 5, flags: Int(opt)) == def, "⌥ alone")
        check(load(code: 5, flags: Int(cmd)) == def, "⌘ alone")
        check(load(code: 5, flags: Int(ctrl)) == def, "⌃ alone")
        check(load(code: 5, flags: Int(ctrl | opt)) == ShortcutSpec(keyCode: 5, nsFlags: ctrl | opt), "a good value is kept")
        check(load(code: 127, flags: good) == ShortcutSpec(keyCode: 127, nsFlags: ctrl | opt), "the last key code")
        check(load(code: 0, flags: good) == ShortcutSpec(keyCode: 0, nsFlags: ctrl | opt), "the first key code")
        check(load(code: 5, flags: good | Int(1 << 16) | Int(1 << 23)) == ShortcutSpec(keyCode: 5, nsFlags: ctrl | opt),
              "caps lock and the numeric-pad bit are dropped")
        let nsNumber: NSNumber = NSNumber(value: Int(ctrl | opt))
        check(load(code: NSNumber(value: 5), flags: nsNumber) == ShortcutSpec(keyCode: 5, nsFlags: ctrl | opt), "NSNumber values")
    }

    // MARK: On or off

    static func testEnabledAndReset() {
        withDefaults { ud in
            check(!ShortcutLogic.isEnabled(.toggleIsland, in: ud), "the island shortcut is off at first")
            check(ShortcutLogic.isEnabled(.goToAlert, in: ud), "the alert shortcut is on at first")
            ShortcutLogic.setEnabled(true, for: .toggleIsland, in: ud)
            ShortcutLogic.setEnabled(false, for: .goToAlert, in: ud)
            check(ShortcutLogic.isEnabled(.toggleIsland, in: ud) && !ShortcutLogic.isEnabled(.goToAlert, in: ud), "both switches stick")
            ShortcutLogic.save(ShortcutSpec(keyCode: 5, nsFlags: ShortcutSpec.cmdShift), for: .openChat, in: ud)
            for action in ShortcutAction.allCases { ShortcutLogic.resetToDefault(action, in: ud) }
            for action in ShortcutAction.allCases {
                check(ShortcutLogic.isEnabled(action, in: ud) == action.enabledByDefault, "\(action.rawValue) is back on or off as shipped")
                check(ShortcutLogic.hotKey(for: action, in: ud) == ShortcutLogic.defaults[action]!, "\(action.rawValue) is back to its default")
            }
        }
    }

    // MARK: Builds

    static func testBuildsAndActiveSpecs() {
        let all = ShortcutLogic.available(appStore: false)
        check(all == ShortcutAction.allCases, "the GitHub build offers every action, in order")
        let store = ShortcutLogic.available(appStore: true)
        check(!store.contains(.jumpToTerminal) && !store.contains(.attachFrontWindow), "no terminal or window shortcuts in the App Store build")
        check(store.count == all.count - 2, "and nothing else is dropped")
        check(store.contains(.openChat) && store.contains(.muteToggle) && store.contains(.nextPill), "the rest stays")
        withDefaults { ud in
            let normal = ShortcutLogic.activeSpecs(appStore: false, in: ud)
            check(normal.count == 5 && normal[.toggleIsland] == nil && normal[.openChat] == nil && normal[.jumpToTerminal] == nil,
                  "five are on at first: not the island shortcut, the chat or the terminal")
            check(ShortcutLogic.activeSpecs(appStore: true, in: ud).count == 4, "four in the App Store build")
            ShortcutLogic.setEnabled(false, for: .muteToggle, in: ud)
            check(ShortcutLogic.activeSpecs(appStore: false, in: ud)[.muteToggle] == nil, "an off shortcut is not registered")
            ShortcutLogic.setEnabled(true, for: .toggleIsland, in: ud)
            check(ShortcutLogic.activeSpecs(appStore: false, in: ud)[.toggleIsland] == ShortcutLogic.defaults[.toggleIsland]!,
                  "turned on, it is")
            // Two ON actions with one combination are reported; an OFF one is not counted.
            ShortcutLogic.setEnabled(true, for: .openChat, in: ud)
            ShortcutLogic.save(ShortcutLogic.defaults[.goToAlert]!, for: .openChat, in: ud)
            check(ShortcutLogic.duplicates(in: ShortcutLogic.activeSpecs(appStore: false, in: ud)) == [.openChat, .goToAlert],
                  "a duplicate between two on shortcuts")
            ShortcutLogic.setEnabled(false, for: .openChat, in: ud)
            check(ShortcutLogic.duplicates(in: ShortcutLogic.activeSpecs(appStore: false, in: ud)).isEmpty,
                  "turn one off and there is none")
        }
        check(ShortcutLogic.isAppStoreBuild == false, "the test build is not the App Store build")
    }

    // MARK: Turn all on

    static func testTurnAllOn() {
        // Nothing is taken: everything comes on, and only the three that were off are tried.
        withDefaults { ud in
            var tried: [ShortcutAction] = []
            let left = ShortcutLogic.turnAllOn(appStore: false, in: ud) { tried.append($0); return true }
            check(left.isEmpty, "nothing was left off")
            check(tried == [.toggleIsland, .openChat, .jumpToTerminal], "only the shortcuts that were off are tried, in list order: \(tried)")
            check(Set(ShortcutLogic.activeSpecs(appStore: false, in: ud).keys) == Set(ShortcutAction.allCases), "all eight are on")
            check(ShortcutLogic.duplicates(in: ShortcutLogic.activeSpecs(appStore: false, in: ud)).isEmpty, "with no two on one combination")
        }
        // One combination is taken (another app has ⌃⌥Space): that shortcut is reported and stays off, the rest come on.
        withDefaults { ud in
            let taken = ShortcutLogic.defaults[.openChat]!
            var asked: [ShortcutAction] = []
            let left = ShortcutLogic.turnAllOn(appStore: false, in: ud) { action in
                asked.append(action)
                return ShortcutLogic.hotKey(for: action, in: ud) != taken
            }
            check(left == [ShortcutLogic.TurnOnResult(action: .openChat, reason: .taken)], "the taken one is reported: \(left)")
            check(!ShortcutLogic.isEnabled(.openChat, in: ud), "and left off in the settings")
            check(ShortcutLogic.isEnabled(.toggleIsland, in: ud) && ShortcutLogic.isEnabled(.jumpToTerminal, in: ud), "the others that were off are on")
            check(ShortcutLogic.activeSpecs(appStore: false, in: ud)[.openChat] == nil, "it is not among the shortcuts to register")
            check(ShortcutLogic.hotKey(for: .openChat, in: ud) == taken, "it keeps its combination")
            // Turning all on again asks only about the one still off, and a free combination now comes on.
            asked.removeAll()
            let again = ShortcutLogic.turnAllOn(appStore: false, in: ud) { asked.append($0); return true }
            check(again.isEmpty && asked == [.openChat], "a second go retries only the one that was left off: \(asked)")
            check(ShortcutLogic.isEnabled(.openChat, in: ud), "and it comes on once the combination is free")
        }
        // Two NotchMeow shortcuts on one combination: the second is refused without asking the system.
        withDefaults { ud in
            ShortcutLogic.save(ShortcutLogic.defaults[.goToAlert]!, for: .jumpToTerminal, in: ud)   // goToAlert is on
            var asked: [ShortcutAction] = []
            let left = ShortcutLogic.turnAllOn(appStore: false, in: ud) { asked.append($0); return true }
            check(left == [ShortcutLogic.TurnOnResult(action: .jumpToTerminal, reason: .duplicate(of: .goToAlert))], "a duplicate is reported: \(left)")
            check(!asked.contains(.jumpToTerminal), "and never registered")
            check(!ShortcutLogic.isEnabled(.jumpToTerminal, in: ud), "and left off")
        }
        // Two that are off at first share a combination: the first in the list wins.
        withDefaults { ud in
            ShortcutLogic.save(ShortcutLogic.defaults[.openChat]!, for: .jumpToTerminal, in: ud)
            let left = ShortcutLogic.turnAllOn(appStore: false, in: ud) { _ in true }
            check(left == [ShortcutLogic.TurnOnResult(action: .jumpToTerminal, reason: .duplicate(of: .openChat))],
                  "the later of two off shortcuts on one combination is the one refused: \(left)")
            check(ShortcutLogic.isEnabled(.openChat, in: ud), "the earlier one comes on")
        }
        // The App Store build has no terminal or front-window shortcut: they are not touched, not even tried.
        withDefaults { ud in
            var asked: [ShortcutAction] = []
            let left = ShortcutLogic.turnAllOn(appStore: true, in: ud) { asked.append($0); return true }
            check(left.isEmpty && asked == [.toggleIsland, .openChat], "the App Store build tries only what it offers: \(asked)")
            check(ud.object(forKey: ShortcutAction.jumpToTerminal.udEnabled) == nil
                  && ud.object(forKey: ShortcutAction.attachFrontWindow.udEnabled) == nil, "and writes nothing for the two it lacks")
        }
        // A shortcut that was turned off on purpose is turned on too: that is what the button says.
        withDefaults { ud in
            ShortcutLogic.setEnabled(false, for: .muteToggle, in: ud)
            let left = ShortcutLogic.turnAllOn(appStore: false, in: ud) { _ in true }
            check(left.isEmpty && ShortcutLogic.isEnabled(.muteToggle, in: ud), "one switched off by hand comes back on")
        }
    }

    static func testTurnOnSummary() {
        typealias R = ShortcutLogic.TurnOnResult
        check(ShortcutLogic.turnOnSummary([]) == nil, "nothing left off, nothing to say")
        check(ShortcutLogic.turnOnSummary([R(action: .openChat, reason: .taken)]) == "Left off: Open chat (in use elsewhere)", "one taken")
        check(ShortcutLogic.turnOnSummary([R(action: .openChat, reason: .taken), R(action: .jumpToTerminal, reason: .duplicate(of: .goToAlert))])
              == "Left off: Open chat (in use elsewhere), Jump to terminal (same keys as Go to alert)", "a taken one and a duplicate")
    }

    // MARK: Lists

    static func testListSelection() {
        check(ShortcutLogic.navigate(selection: nil, delta: +1, itemCount: 3) == 0, "nothing selected, down: the first row")
        check(ShortcutLogic.navigate(selection: nil, delta: -1, itemCount: 3) == 2, "nothing selected, up: the last row")
        check(ShortcutLogic.navigate(selection: 0, delta: -1, itemCount: 3) == 0, "clamped at the top")
        check(ShortcutLogic.navigate(selection: 2, delta: +1, itemCount: 3) == 2, "clamped at the bottom")
        check(ShortcutLogic.navigate(selection: 1, delta: +1, itemCount: 3) == 2, "a step down")
        check(ShortcutLogic.navigate(selection: 1, delta: -1, itemCount: 3) == 0, "a step up")
        check(ShortcutLogic.navigate(selection: 1, delta: 0, itemCount: 3) == 1, "no move")
        check(ShortcutLogic.navigate(selection: nil, delta: +1, itemCount: 0) == nil, "an empty list")
        check(ShortcutLogic.navigate(selection: 4, delta: +1, itemCount: 0) == nil, "an empty list with a stale selection")
        check(ShortcutLogic.navigate(selection: 9, delta: -1, itemCount: 3) == 2, "a stale selection beyond the list is pulled in")
        check(ShortcutLogic.clampSelection(nil, itemCount: 3) == nil, "nothing stays nothing")
        check(ShortcutLogic.clampSelection(2, itemCount: 3) == 2, "inside the list")
        check(ShortcutLogic.clampSelection(5, itemCount: 3) == 2, "the list shrank")
        check(ShortcutLogic.clampSelection(1, itemCount: 0) == nil, "the list emptied")
        check(ShortcutLogic.clampSelection(-3, itemCount: 3) == 0, "negative")
    }

    // MARK: Pills

    static func testPills() {
        let ids = ["a", "b", "c"]
        func step(_ current: String?, _ delta: Int, waiting: Bool = false) -> String? {
            ShortcutLogic.pillID(from: ids, current: current, delta: delta, decisionWaiting: waiting)
        }
        func number(_ n: Int, waiting: Bool = false) -> String? {
            ShortcutLogic.pillID(number: n, in: ids, decisionWaiting: waiting)
        }
        check(step("a", +1) == "b", "next")
        check(step("c", +1) == "a", "next wraps to the first")
        check(step("a", -1) == "c", "previous wraps to the last")
        check(step("b", -1) == "a", "previous")
        check(step(nil, +1) == "b", "no focus counts as the first pill")
        check(step("gone", -1) == "c", "a focus that left counts as the first pill")
        check(ShortcutLogic.pillID(from: [], current: "a", delta: +1, decisionWaiting: false) == nil, "no pills")
        check(ShortcutLogic.pillID(from: ["a"], current: "a", delta: +1, decisionWaiting: false) == "a", "one pill stays")
        check(step("a", -7) == "c", "a big step still wraps")
        check(number(1) == "a" && number(3) == "c", "by number")
        check(number(4) == nil, "a number past the last pill")
        check(number(0) == nil, "zero")
        check(ShortcutLogic.pillID(number: 1, in: [], decisionWaiting: false) == nil, "no pills by number")
        // A permission request or a question is waiting: its card stays, with its agent.
        check(step("a", +1, waiting: true) == nil && step("a", -1, waiting: true) == nil, "next and previous do nothing while a decision waits")
        check(number(1, waiting: true) == nil && number(2, waiting: true) == nil, "⌘1 to ⌘9 do nothing while a decision waits")
        check(step("a", +1, waiting: false) == "b" && number(2, waiting: false) == "b", "and work again once it is answered")
    }

    // MARK: Island keys

    static let overview = IslandKeyContext(inOverview: true, inChat: false)
    static let chat = IslandKeyContext(inOverview: false, inChat: true)
    static let other = IslandKeyContext(inOverview: false, inChat: false)

    static func cmdKey(_ code: UInt16, _ ctx: IslandKeyContext) -> IslandCommand? {
        ShortcutLogic.islandCommand(keyCode: code, nsFlags: cmd, in: ctx)
    }

    static func testIslandKeys() {
        check(cmdKey(124, overview) == .nextPill, "⌘→")
        check(cmdKey(123, overview) == .prevPill, "⌘←")
        check(cmdKey(125, overview) == .listDown, "⌘↓")
        check(cmdKey(126, overview) == .listUp, "⌘↑")
        check(cmdKey(31, overview) == .openSelection, "⌘O")
        check(cmdKey(14, overview) == .toggleDiff, "⌘E on the overview")
        check(cmdKey(14, other) == nil, "⌘E elsewhere is left alone")
        check(cmdKey(43, other) == .openSettings, "⌘, without characters")
        check(ShortcutLogic.islandCommand(keyCode: 46, nsFlags: cmd, characters: ",", in: other) == .openSettings,
              "⌘, on a layout that puts the comma elsewhere (AZERTY: key code 46)")
        check(ShortcutLogic.islandCommand(keyCode: 43, nsFlags: cmd, characters: ";", in: other) == nil,
              "the US comma position is a semicolon on AZERTY: not Settings")
        check(ShortcutLogic.islandCommand(keyCode: 43, nsFlags: cmd, characters: ",", in: other) == .openSettings, "⌘, on the US layout")
        check(ShortcutLogic.islandCommand(keyCode: 43, nsFlags: cmd | shift, characters: ",", in: other) == nil, "⌘⇧, is not ⌘,")
        check(cmdKey(35, other) == .togglePin, "⌘P")
        check(cmdKey(36, overview) == nil, "⌘↩ outside the chat is left alone")
        check(cmdKey(40, overview) == nil, "⌘K outside the chat is left alone")
        let digits: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]
        for (code, n) in digits { check(cmdKey(code, other) == .pill(n), "⌘\(n)") }
        check(cmdKey(29, other) == nil, "⌘0 is left alone")
        check(ShortcutLogic.islandCommand(keyCode: 53, nsFlags: 0, in: other) == .escape, "⎋ with nothing held")
        check(ShortcutLogic.islandCommand(keyCode: 53, nsFlags: 1 << 16, in: other) == .escape, "⎋ with only caps lock on")
        check(ShortcutLogic.islandCommand(keyCode: 0, nsFlags: 0, in: other) == nil, "a plain letter is left alone")
        check(ShortcutLogic.islandCommand(keyCode: 49, nsFlags: 0, in: chat) == nil, "typing a space in the chat is left alone")
        check(cmdKey(8, overview) == nil && cmdKey(9, overview) == nil && cmdKey(0, overview) == nil, "⌘C ⌘V ⌘A are left alone")
    }

    /// In the chat, ⌘ with an arrow moves the cursor in the text field: line start, line end, top, bottom.
    static func testIslandKeysInTheChat() {
        for code: UInt16 in [123, 124, 125, 126] {
            check(cmdKey(code, chat) == nil, "⌘ and arrow \(code) must stay with the text field in the chat")
        }
        check(cmdKey(36, chat) == .sendMessage, "⌘↩ sends in the chat")
        check(cmdKey(40, chat) == .newConversation, "⌘K starts over in the chat")
        check(cmdKey(14, chat) == nil, "⌘E is not for the chat")
        check(cmdKey(43, chat) == .openSettings && cmdKey(35, chat) == .togglePin, "⌘, and ⌘P work in the chat")
        check(cmdKey(18, chat) == .pill(1), "⌘1 works in the chat")
        check(ShortcutLogic.islandCommand(keyCode: 53, nsFlags: 0, in: chat) == .escape, "⎋ in the chat")
    }

    /// ⌘⇧N, ⌘⌥1, ⌃⌘E … belong to other shortcuts or other apps: the island never takes them.
    static func testIslandKeysWithOtherModifiers() {
        let others: [UInt] = [cmd | shift, cmd | opt, cmd | ctrl, ctrl, opt, shift, ctrl | opt]
        for flags in others {
            for code: UInt16 in [124, 123, 125, 126, 31, 14, 36, 40, 43, 35, 18, 25] {
                check(ShortcutLogic.islandCommand(keyCode: code, nsFlags: flags, in: overview) == nil,
                      "key \(code) with flags \(flags) must be left alone")
                check(ShortcutLogic.islandCommand(keyCode: code, nsFlags: flags, in: chat) == nil,
                      "key \(code) with flags \(flags) must be left alone in the chat")
            }
            check(ShortcutLogic.islandCommand(keyCode: 53, nsFlags: flags, in: overview) == nil, "⎋ with a modifier is left alone")
        }
        check(ShortcutLogic.islandCommand(keyCode: 124, nsFlags: cmd | (1 << 16) | (1 << 23), in: overview) == .nextPill,
              "caps lock and the arrow-key bit do not hide ⌘→")
    }

    // MARK: Recorder

    static func testRecorderKeys() {
        func key(_ code: UInt16, _ flags: UInt) -> RecorderKey { ShortcutLogic.recorderKey(keyCode: code, nsFlags: flags) }
        check(key(53, 0) == .cancel, "⎋ alone cancels")
        check(key(53, 1 << 16) == .cancel, "⎋ with only caps lock on still cancels")
        check(key(53, cmd) == .refuse, "⌘⎋ is not a usable shortcut and does not cancel")
        check(key(0, 0) == .passThrough && key(36, 0) == .passThrough && key(48, 0) == .passThrough, "keys without a modifier go on")
        check(key(0, shift) == .refuse, "⇧A is refused: it would take capital A from every app")
        check(key(0, opt) == .refuse && key(0, shift | opt) == .refuse, "⌥A and ⇧⌥A are refused")
        check(key(0, cmd) == .refuse && key(0, ctrl) == .refuse, "⌘A and ⌃A are refused")
        check(key(0, ctrl | opt) == .record(ShortcutSpec(keyCode: 0, nsFlags: ctrl | opt)), "⌃⌥A is taken")
        check(key(45, cmd | shift) == .record(ShortcutSpec(keyCode: 45, nsFlags: cmd | shift)), "⌘⇧N is taken")
        check(key(49, ctrl | opt | (1 << 16) | (1 << 23)) == .record(ShortcutSpec(keyCode: 49, nsFlags: ctrl | opt)),
              "caps lock and the arrow-key bit are left out of what is stored")
        check(key(127, ctrl | opt) == .record(ShortcutSpec(keyCode: 127, nsFlags: ctrl | opt)), "the last key code")
        check(key(200, ctrl | opt) == .refuse, "a key code no keyboard has is refused, so a stored value is always one hotKey(for:) accepts")
        // Whatever the recorder takes, hotKey(for:) reads back unchanged.
        withDefaults { ud in
            for code: UInt16 in [0, 5, 45, 49, 123, 127] {
                for flags in [cmd | shift, ctrl | opt, cmd | ctrl, cmd | opt | shift] {
                    guard case .record(let spec) = key(code, flags) else { check(false, "key \(code) flags \(flags) should record"); return }
                    ShortcutLogic.save(spec, for: .openChat, in: ud)
                    check(ShortcutLogic.hotKey(for: .openChat, in: ud) == spec, "a recorded combination is read back as it was")
                }
            }
        }
    }

    // MARK: Tables

    static func testTables() {
        check(!ShortcutLogic.islandShortcuts.isEmpty, "the Settings table has rows")
        for row in ShortcutLogic.islandShortcuts {
            check(!row.key.isEmpty && !row.description.isEmpty, "a row with an empty cell")
        }
        check(ShortcutLogic.terminalBundleIds.first == "com.apple.Terminal", "Terminal first")
        check(ShortcutLogic.terminalBundleIds.count == 4, "four terminals, as the cards' button")
        check(Set(ShortcutLogic.terminalBundleIds).count == 4, "no repeats")
    }
}
```

**Create `scripts/test-shortcuts.sh`**

```bash
#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-shortcuts.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 6 NotchBuddy/Sources/App/ShortcutLogic.swift \
    tests/ShortcutTests.swift -o "$TEST_DIR/shortcut-tests"
"$TEST_DIR/shortcut-tests"
```

- [ ] **Step 2: Run the test and see it fail**

Run: `chmod +x scripts/test-shortcuts.sh && bash scripts/test-shortcuts.sh`
Expected: FAIL, `error opening input file 'NotchBuddy/Sources/App/ShortcutLogic.swift' (No such file or directory)`: the logic does not exist yet.

- [ ] **Step 3: Write the logic**

**Create `NotchBuddy/Sources/App/ShortcutLogic.swift`**

```swift
import Foundation

// MARK: - Where the settings live

/// What `ShortcutLogic` needs from a settings store: `UserDefaults` in the app, a dictionary in the tests, so a test
/// run never writes a preferences file.
protocol ShortcutStore {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: ShortcutStore {}

// MARK: - Global shortcut actions

/// The global shortcuts NotchMeow registers with Carbon (`HotKeyCenter`), in the order Settings shows them.
/// Island-local shortcuts (⌘→, ⌘K, ⎋ …) are not actions here: `ShortcutLogic.islandCommand` maps them,
/// and a local key monitor in `IslandWindowController` runs them while the island has the keyboard.
///
/// New actions go at the END: Carbon identifies a registered hot key by its index in `allCases`.
enum ShortcutAction: String, CaseIterable, Sendable {
    case toggleIsland       // ⌘⇧N: open or close the island. Off by default, like the old Hotkey setting.
    case openChat           // ⌃⌥Space: open the chat and focus its field. Off by default: macOS uses the combination
    case goToAlert          // ⌃⌥A: jump to the permission request or question that is waiting
    case jumpToTerminal     // ⌃⌥T: bring the agent's terminal forward (not in the App Store build). Off by default: Rectangle
    case attachFrontWindow  // ⌃⌥W: attach the front window to the chat (not in the App Store build)
    case nextPill           // ⌃⌥]: next pill, opening the island if it is closed
    case prevPill           // ⌃⌥[: previous pill
    case muteToggle         // ⌃⌥M: mute or unmute sounds

    /// `toggleIsland` keeps the storage keys the old Hotkey setting used (`AppState.hotkey*`), so a shortcut
    /// someone already set keeps working. Every other action has keys of its own.
    var udKeyCode: String { self == .toggleIsland ? "hotkeyCode" : "shortcut.\(rawValue).keyCode" }
    var udFlags: String   { self == .toggleIsland ? "hotkeyFlags" : "shortcut.\(rawValue).flags" }
    var udEnabled: String { self == .toggleIsland ? "hotkeyEnabled" : "shortcut.\(rawValue).enabled" }

    var displayName: String {
        switch self {
        case .toggleIsland:      return "Open or close the island"
        case .openChat:          return "Open chat"
        case .goToAlert:         return "Go to alert"
        case .jumpToTerminal:    return "Jump to terminal"
        case .attachFrontWindow: return "Attach front window"
        case .nextPill:          return "Next pill"
        case .prevPill:          return "Previous pill"
        case .muteToggle:        return "Mute or unmute sounds"
        }
    }

    /// Left out of the App Store build, like the buttons that do the same things.
    var isNonAppStore: Bool { self == .jumpToTerminal || self == .attachFrontWindow }

    /// On at first: the alert, the front window, the two pill keys and mute. Off at first, each with its combination
    /// kept so that turning it on is one click: the island shortcut (off as it always was), the chat (macOS uses
    /// ⌃⌥Space for "Select next source in Input menu") and the terminal (Rectangle uses ⌃⌥T for "Last Two Thirds").
    var enabledByDefault: Bool {
        switch self {
        case .toggleIsland, .openChat, .jumpToTerminal: return false
        case .goToAlert, .attachFrontWindow, .nextPill, .prevPill, .muteToggle: return true
        }
    }

    /// Why a shortcut is off at first, for Settings; nil for one that is on, and for the island shortcut, which
    /// is off because it always was.
    var offAtFirstNote: String? {
        switch self {
        case .openChat:
            return "Off at first: macOS uses ⌃⌥Space for “Select next source in Input menu”."
        case .jumpToTerminal:
            return "Off at first: Rectangle uses ⌃⌥T for “Last Two Thirds”."
        case .toggleIsland, .goToAlert, .attachFrontWindow, .nextPill, .prevPill, .muteToggle:
            return nil
        }
    }
}

// MARK: - Shortcut spec

/// A key and its modifiers, as plain numbers (no AppKit), so this file builds and tests on its own.
struct ShortcutSpec: Equatable, Hashable, Sendable {
    /// Virtual key code: `NSEvent.keyCode`, the `kVK_*` constants.
    var keyCode: UInt16
    /// `NSEvent.ModifierFlags.rawValue`, only the ⌘ ⇧ ⌥ ⌃ bits.
    var nsFlags: UInt

    // Stable since macOS 10.x (AppKit/NSEvent.h).
    static let cmdBit:   UInt = 1 << 20  // NSEvent.ModifierFlags.command = 1048576
    static let shiftBit: UInt = 1 << 17  // .shift   = 131072
    static let optBit:   UInt = 1 << 19  // .option  = 524288
    static let ctrlBit:  UInt = 1 << 18  // .control = 262144
    static let modMask:  UInt = cmdBit | shiftBit | optBit | ctrlBit
    static let cmdShift: UInt = cmdBit | shiftBit   // 1179648
    static let ctrlOpt:  UInt = ctrlBit | optBit    // 786432

    /// The largest virtual key code a keyboard produces.
    static let maxKeyCode = 127

    var modifierCount: Int {
        [Self.cmdBit, Self.shiftBit, Self.optBit, Self.ctrlBit].filter { nsFlags & $0 != 0 }.count
    }

    /// A global shortcut that no ordinary typing produces: ⌘ or ⌃ is held, with at least one more modifier.
    /// A bare key, ⇧ or ⌥ alone (capital letters, accents) or ⌘ or ⌃ alone (every Edit-menu and Emacs key)
    /// would be taken from every other app while the shortcut is registered.
    var isUsableGlobal: Bool {
        nsFlags & (Self.cmdBit | Self.ctrlBit) != 0 && modifierCount >= 2
    }
}

// MARK: - The recorder

/// What the shortcut recorder does with a key press while it listens.
enum RecorderKey: Equatable, Sendable {
    case cancel                     // ⎋ alone: stop recording
    case passThrough                // no modifier: not a shortcut, the key goes on
    case refuse                     // a combination that is not `isUsableGlobal`: a beep
    case record(ShortcutSpec)       // take it
}

// MARK: - Island-local commands

/// What a key press does while the island has the keyboard (`ShortcutLogic.islandCommand`).
enum IslandCommand: Equatable, Sendable {
    case nextPill, prevPill
    case pill(Int)          // ⌘1 to ⌘9
    case listDown, listUp   // ⌘↓ ⌘↑: move through the list on the card
    case openSelection      // ⌘O
    case toggleDiff         // ⌘E
    case sendMessage        // ⌘↩
    case newConversation    // ⌘K
    case openSettings       // ⌘,
    case togglePin          // ⌘P
    case escape             // ⎋
}

/// Where the island is, as far as key handling cares.
struct IslandKeyContext: Equatable, Sendable {
    var inOverview: Bool
    var inChat: Bool
}

// MARK: - Pure logic

/// Everything about shortcuts that needs no AppKit: tables, storage, validation, key mapping.
enum ShortcutLogic {

    // MARK: Defaults

    static let defaults: [ShortcutAction: ShortcutSpec] = [
        .toggleIsland:      ShortcutSpec(keyCode: 45, nsFlags: ShortcutSpec.cmdShift),  // ⌘⇧N
        .openChat:          ShortcutSpec(keyCode: 49, nsFlags: ShortcutSpec.ctrlOpt),   // ⌃⌥Space
        .goToAlert:         ShortcutSpec(keyCode: 0,  nsFlags: ShortcutSpec.ctrlOpt),   // ⌃⌥A
        .jumpToTerminal:    ShortcutSpec(keyCode: 17, nsFlags: ShortcutSpec.ctrlOpt),   // ⌃⌥T
        .attachFrontWindow: ShortcutSpec(keyCode: 13, nsFlags: ShortcutSpec.ctrlOpt),   // ⌃⌥W
        .nextPill:          ShortcutSpec(keyCode: 30, nsFlags: ShortcutSpec.ctrlOpt),   // ⌃⌥]
        .prevPill:          ShortcutSpec(keyCode: 33, nsFlags: ShortcutSpec.ctrlOpt),   // ⌃⌥[
        .muteToggle:        ShortcutSpec(keyCode: 46, nsFlags: ShortcutSpec.ctrlOpt),   // ⌃⌥M
    ]

    // MARK: Build

    #if APPSTORE
    static let isAppStoreBuild = true
    #else
    static let isAppStoreBuild = false
    #endif

    /// The actions this build offers, in Settings order.
    static func available(appStore: Bool = isAppStoreBuild) -> [ShortcutAction] {
        ShortcutAction.allCases.filter { !(appStore && $0.isNonAppStore) }
    }

    // MARK: Storage

    /// The stored shortcut, or the default when nothing is stored or what is stored cannot be trusted:
    /// a key code outside 0...127 (a hand-edited value used to trap in `UInt16(_:)`), a missing half,
    /// or a combination that is not `isUsableGlobal`.
    static func hotKey(for action: ShortcutAction, in store: any ShortcutStore = UserDefaults.standard) -> ShortcutSpec {
        let def = defaults[action]!
        guard let kc = store.object(forKey: action.udKeyCode) as? Int,
              let fl = store.object(forKey: action.udFlags) as? Int,
              (0...ShortcutSpec.maxKeyCode).contains(kc), fl >= 0 else { return def }
        let spec = ShortcutSpec(keyCode: UInt16(kc), nsFlags: UInt(fl) & ShortcutSpec.modMask)
        return spec.isUsableGlobal ? spec : def
    }

    static func save(_ spec: ShortcutSpec, for action: ShortcutAction, in store: any ShortcutStore = UserDefaults.standard) {
        store.set(Int(spec.keyCode), forKey: action.udKeyCode)
        store.set(Int(spec.nsFlags), forKey: action.udFlags)
    }

    static func isEnabled(_ action: ShortcutAction, in store: any ShortcutStore = UserDefaults.standard) -> Bool {
        store.object(forKey: action.udEnabled) as? Bool ?? action.enabledByDefault
    }

    static func setEnabled(_ enabled: Bool, for action: ShortcutAction, in store: any ShortcutStore = UserDefaults.standard) {
        store.set(enabled, forKey: action.udEnabled)
    }

    static func resetToDefault(_ action: ShortcutAction, in store: any ShortcutStore = UserDefaults.standard) {
        save(defaults[action]!, for: action, in: store)
        setEnabled(action.enabledByDefault, for: action, in: store)
    }

    /// A shortcut that "Turn all on" left off, and why.
    struct TurnOnResult: Equatable, Sendable {
        enum Reason: Equatable, Sendable {
            case taken                          // macOS refused the combination: another app has it
            case duplicate(of: ShortcutAction)  // another NotchMeow shortcut already has it
        }
        var action: ShortcutAction
        var reason: Reason
    }

    /// Turns on every shortcut of this build that is off, except those whose combination is not free, and returns
    /// those (in list order). A shortcut already on is left alone. `tryOn` is called once per shortcut that is
    /// switched on; it must register it with the system and say whether that worked (the app passes
    /// `HotKeyCenter`), and a `false` puts the switch back off. A combination another shortcut already has is
    /// refused without asking.
    static func turnAllOn(appStore: Bool = isAppStoreBuild, in store: any ShortcutStore = UserDefaults.standard,
                          tryOn: (ShortcutAction) -> Bool) -> [TurnOnResult] {
        var active = activeSpecs(appStore: appStore, in: store)
        var left: [TurnOnResult] = []
        for action in available(appStore: appStore) where active[action] == nil {
            let spec = hotKey(for: action, in: store)
            if let owner = ShortcutAction.allCases.first(where: { active[$0] == spec }) {
                left.append(TurnOnResult(action: action, reason: .duplicate(of: owner)))
                continue
            }
            setEnabled(true, for: action, in: store)
            if tryOn(action) {
                active[action] = spec
            } else {
                setEnabled(false, for: action, in: store)
                left.append(TurnOnResult(action: action, reason: .taken))
            }
        }
        return left
    }

    /// What Settings says after "Turn all on", nil when everything is on.
    static func turnOnSummary(_ left: [TurnOnResult]) -> String? {
        guard !left.isEmpty else { return nil }
        let parts = left.map { result -> String in
            switch result.reason {
            case .taken:                 return "\(result.action.displayName) (in use elsewhere)"
            case .duplicate(let owner):  return "\(result.action.displayName) (same keys as \(owner.displayName))"
            }
        }
        return "Left off: " + parts.joined(separator: ", ")
    }

    /// The shortcuts that are on, for this build: what `HotKeyCenter` registers.
    static func activeSpecs(appStore: Bool = isAppStoreBuild,
                            in store: any ShortcutStore = UserDefaults.standard) -> [ShortcutAction: ShortcutSpec] {
        var out: [ShortcutAction: ShortcutSpec] = [:]
        for action in available(appStore: appStore) where isEnabled(action, in: store) {
            out[action] = hotKey(for: action, in: store)
        }
        return out
    }

    // MARK: Carbon

    // Carbon modifier bits (Events.h), as plain numbers so no import is needed.
    private static let cCmdKey:   UInt32 = 1 << 8   // cmdKey     = 256
    private static let cShiftKey: UInt32 = 1 << 9   // shiftKey   = 512
    private static let cOptKey:   UInt32 = 1 << 11  // optionKey  = 2048
    private static let cCtrlKey:  UInt32 = 1 << 12  // controlKey = 4096

    static func carbonModifiers(fromNS nsFlags: UInt) -> UInt32 {
        var c: UInt32 = 0
        if nsFlags & ShortcutSpec.cmdBit   != 0 { c |= cCmdKey }
        if nsFlags & ShortcutSpec.shiftBit != 0 { c |= cShiftKey }
        if nsFlags & ShortcutSpec.optBit   != 0 { c |= cOptKey }
        if nsFlags & ShortcutSpec.ctrlBit  != 0 { c |= cCtrlKey }
        return c
    }

    // MARK: Conflicts inside NotchMeow

    /// The actions whose combination is shared with another action in `specs`.
    static func duplicates(in specs: [ShortcutAction: ShortcutSpec]) -> Set<ShortcutAction> {
        var seen: [ShortcutSpec: ShortcutAction] = [:]
        var dups: Set<ShortcutAction> = []
        for action in ShortcutAction.allCases {
            guard let spec = specs[action] else { continue }
            if let other = seen[spec] {
                dups.insert(action)
                dups.insert(other)
            } else {
                seen[spec] = action
            }
        }
        return dups
    }

    // MARK: Display

    /// "⌃⌥A", "⌘⇧N": modifiers in the order macOS shows them, then the key. A shortcut is a key position, so
    /// `keyName` can give the character printed on that key in the layout in use (`KeyLayoutNames`): the key
    /// labelled A on an AZERTY keyboard is the one the US layout calls Q. A key it has no name for (Space, the
    /// arrows, F1) keeps the name of `keyCodeToString`.
    static func displayString(for spec: ShortcutSpec, keyName: (UInt16) -> String? = { _ in nil }) -> String {
        var s = ""
        if spec.nsFlags & ShortcutSpec.ctrlBit  != 0 { s += "⌃" }
        if spec.nsFlags & ShortcutSpec.optBit   != 0 { s += "⌥" }
        if spec.nsFlags & ShortcutSpec.shiftBit != 0 { s += "⇧" }
        if spec.nsFlags & ShortcutSpec.cmdBit   != 0 { s += "⌘" }
        return s + (keyName(spec.keyCode) ?? keyCodeToString(spec.keyCode))
    }

    /// The name of a virtual key code, "·" for a key without one here.
    static func keyCodeToString(_ code: UInt16) -> String {
        keyNames[code] ?? "·"
    }

    private static let keyNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-",
        28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J",
        39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
        36: "↩", 48: "⇥", 49: "Space", 50: "`", 51: "⌫", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    // MARK: Lists and pills

    /// The next list selection: nil on an empty list, clamped to the list, and from nothing selected ↓ takes
    /// the first row and ↑ the last.
    static func navigate(selection: Int?, delta: Int, itemCount: Int) -> Int? {
        guard itemCount > 0 else { return nil }
        if let cur = selection { return max(0, min(itemCount - 1, cur + delta)) }
        return delta > 0 ? 0 : itemCount - 1
    }

    /// A selection kept inside a list that shrank: nil when nothing is selected or the list is empty.
    static func clampSelection(_ selection: Int?, itemCount: Int) -> Int? {
        guard let s = selection, itemCount > 0 else { return nil }
        return min(max(s, 0), itemCount - 1)
    }

    /// The pill `delta` steps from `current`, wrapping around. An unknown or missing `current` counts as the first.
    /// Nil when there are no pills, and nil while a permission request or a question is waiting
    /// (`decisionWaiting`): its card must stay on screen, with the agent it belongs to.
    static func pillID(from ids: [String], current: String?, delta: Int, decisionWaiting: Bool) -> String? {
        guard !decisionWaiting, !ids.isEmpty else { return nil }
        let cur = current.flatMap { ids.firstIndex(of: $0) } ?? 0
        let n = ids.count
        return ids[((cur + delta) % n + n) % n]
    }

    /// The pill for ⌘1 to ⌘9: nil when there is none, and nil while a decision is waiting.
    static func pillID(number: Int, in ids: [String], decisionWaiting: Bool) -> String? {
        guard !decisionWaiting, ids.indices.contains(number - 1) else { return nil }
        return ids[number - 1]
    }

    // MARK: Recorder

    /// What the recorder does with this key press.
    static func recorderKey(keyCode: UInt16, nsFlags: UInt) -> RecorderKey {
        let mods = nsFlags & ShortcutSpec.modMask
        if keyCode == 53 && mods == 0 { return .cancel }
        if mods == 0 { return .passThrough }
        let spec = ShortcutSpec(keyCode: keyCode, nsFlags: mods)
        return spec.isUsableGlobal && Int(keyCode) <= ShortcutSpec.maxKeyCode ? .record(spec) : .refuse
    }

    // MARK: Island-local keys

    private static let digitKeyCodes: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]

    /// What a key press means while the island has the keyboard, nil when the island leaves it alone.
    /// Only ⌘ with nothing else counts (⌘⇧N and friends are not island keys). In the chat, ⌘ with an arrow keeps
    /// moving the cursor in the text field instead of moving between pills. ⌘, is the comma wherever the layout puts
    /// it: `characters` is the key's character without modifiers (`NSEvent.charactersIgnoringModifiers`); without
    /// it, the US position (key code 43) stands in. The other keys are positions, which are the same on the layouts
    /// that matter here (the letters O, E, K and P and the number row).
    static func islandCommand(keyCode: UInt16, nsFlags: UInt, characters: String? = nil,
                              in ctx: IslandKeyContext) -> IslandCommand? {
        let mods = nsFlags & ShortcutSpec.modMask
        if keyCode == 53 && mods == 0 { return .escape }
        guard mods == ShortcutSpec.cmdBit else { return nil }
        if let characters { if characters == "," { return .openSettings } } else if keyCode == 43 { return .openSettings }
        switch keyCode {
        case 124: return ctx.inChat ? nil : .nextPill
        case 123: return ctx.inChat ? nil : .prevPill
        case 125: return ctx.inChat ? nil : .listDown
        case 126: return ctx.inChat ? nil : .listUp
        case 31:  return .openSelection
        case 14:  return ctx.inOverview ? .toggleDiff : nil
        case 36:  return ctx.inChat ? .sendMessage : nil
        case 40:  return ctx.inChat ? .newConversation : nil
        case 35:  return .togglePin
        default:  return digitKeyCodes[keyCode].map { .pill($0) }
        }
    }

    /// The island-local shortcuts, as Settings lists them (read-only).
    static let islandShortcuts: [(key: String, description: String)] = [
        ("⌘→ / ⌘←", "Next or previous pill"),
        ("⌘1 to ⌘9", "Go to a pill by its number"),
        ("⌘↓ / ⌘↑", "Move through a list"),
        ("⌘O", "Open the selected item"),
        ("⌘E", "Open or close the latest diff"),
        ("⌘↩", "Send the chat message"),
        ("⌘K", "Start a new conversation"),
        ("⌘,", "Open Settings"),
        ("⌘P", "Pin or unpin the island"),
        ("⎋", "Close the island, or go back"),
    ]

    // MARK: Terminals

    /// The terminals ⌃⌥T and the cards' "Open terminal" button bring forward, in order of preference.
    static let terminalBundleIds = ["com.apple.Terminal", "com.googlecode.iterm2",
                                    "net.kovidgoyal.kitty", "com.mitchellh.ghostty"]
}
```

- [ ] **Step 4: Run the test and see it pass**

Run: `bash scripts/test-shortcuts.sh`
Expected: PASS, the last line `Shortcuts: 496 cases passed`.

- [ ] **Step 5: Prove the tests can fail**

Four small breakages, each undone at once: one for the combination rule, one for the chat's arrow keys, one for the shortcuts that are on at first and one for "Turn all on" against a taken combination. Run:

```bash
F=NotchBuddy/Sources/App/ShortcutLogic.swift; B="${TMPDIR:-/tmp}/ShortcutLogic.swift.bak"; cp "$F" "$B"
sed -i '' 's/modifierCount >= 2/modifierCount >= 1/' "$F"
bash scripts/test-shortcuts.sh; echo "exit=$?"; cp "$B" "$F"
sed -i '' 's/case 124: return ctx.inChat ? nil : .nextPill/case 124: return .nextPill/' "$F"
bash scripts/test-shortcuts.sh; echo "exit=$?"; cp "$B" "$F"
sed -i '' -e 's/case .toggleIsland, .openChat, .jumpToTerminal: return false/case .toggleIsland, .jumpToTerminal: return false/' -e 's/case .goToAlert, .attachFrontWindow, .nextPill, .prevPill, .muteToggle: return true/case .openChat, .goToAlert, .attachFrontWindow, .nextPill, .prevPill, .muteToggle: return true/' "$F"
bash scripts/test-shortcuts.sh; echo "exit=$?"; cp "$B" "$F"
sed -i '' 's/if tryOn(action) {/if tryOn(action) || true {/' "$F"
bash scripts/test-shortcuts.sh; echo "exit=$?"; cp "$B" "$F"
diff "$B" "$F" && echo "restored"; bash scripts/test-shortcuts.sh
```

Expected: the runs stop, each with an `exit=` that is not 0, with `Precondition failed: ⌘ alone is every Edit-menu key`, then `⌘ and arrow 124 must stay with the text field in the chat`, then `openChat is off at first` (the default on/off set is pinned), then `the taken one is reported: []` ("Turn all on" must leave a taken combination off and report it); then `restored` is printed (the file is back as it was) and the last run passes again.

- [ ] **Step 6: Generate the project and build**

Run: `cd NotchBuddy && xcodegen && xcodebuild -scheme NotchBuddy -configuration Debug -derivedDataPath build build CODE_SIGNING_ALLOWED=NO`
Expected: PASS, `** BUILD SUCCEEDED **` (the app target compiles the new file under strict concurrency; nothing uses it yet).

- [ ] **Step 7: Commit**

```bash
git add NotchBuddy/Sources/App/ShortcutLogic.swift tests/ShortcutTests.swift scripts/test-shortcuts.sh NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -m "feat(shortcuts): the shortcut logic: actions, defaults, validated storage, the island's key map

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

---

### Task 2: The global shortcuts

Agent: `nm-implementer`.

**Files:**
- Create: `NotchBuddy/Sources/App/HotKeyCenter.swift`, `tests/HotKeyCenterTests.swift`, `scripts/test-hotkeys.sh`
- Modify: `NotchBuddy/Sources/App/AppDelegate.swift`, `NotchBuddy/Sources/App/AppState.swift`, `NotchBuddy/Sources/App/SettingsView.swift` (the General hotkey box only), `NotchBuddy/Sources/App/IslandWindowController.swift`, `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` (regenerated)

**Interfaces:**
- Consumes: Task 1's `ShortcutAction`, `ShortcutLogic.activeSpecs(appStore:in:)`, `carbonModifiers(fromNS:)`, `pillID(from:current:delta:decisionWaiting:)`, `terminalBundleIds`, `hotKey(for:in:)`, `save`, `isEnabled`, `setEnabled`.
- Produces:
  - `@MainActor final class HotKeyCenter`: `static let shared`, `var store: any ShortcutStore`, `var registered: Set<ShortcutAction>`, `private(set) var conflicts: Set<ShortcutAction>`, `start(onAction: @escaping @MainActor (ShortcutAction) -> Void)`, `unregisterAll()`, `registerAll()`, `reregister(_ action: ShortcutAction)`.
  - `AppState.hotkeyEnabled: Bool`, `hotkeyFlags: UInt` and `hotkeyCode: UInt16`, now computed over `ShortcutLogic` (same names, same types).
  - On `IslandWindowController` (Task 3 uses them): `func handleHotKey(_:)`, `func cyclePill(by:)`, `private func showPill(_ id: String)`, `private var decisionWaiting: Bool`, `private func openWithKeyboard(_:)`.

- [ ] **Step 1: Write the failing test and its script**

The test registers real hot keys with the system under ⌃⌥⇧⌘ and F13 to F20 (combinations nobody uses), against an in-memory store, and presses a shortcut by sending Carbon the event the system would send. It checks that only the five that are on at first are registered, then runs "Turn all on" with the real wrapper behind it. It needs a logged-in macOS session.

**Create `tests/HotKeyCenterTests.swift`**

```swift
import AppKit
import Carbon.HIToolbox

/// A settings store in memory: the test never writes a preferences file.
final class MemoryStore: ShortcutStore {
    var values: [String: Any] = [:]
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
}

/// The Carbon plumbing of `HotKeyCenter`, without launching the app and without a real key press: the shortcuts
/// are registered with the system under combinations nobody uses (⌃⌥⇧⌘ with F13 to F20), and a press is
/// simulated by sending Carbon the same event the system would send.
@main
enum HotKeyCenterTests {
    nonisolated(unsafe) static var cases = 0

    static func check(_ ok: Bool, _ message: @autoclosure () -> String,
                      file: StaticString = #file, line: UInt = #line) {
        cases += 1
        precondition(ok, message(), file: file, line: line)
    }

    static let allFour = ShortcutSpec.cmdBit | ShortcutSpec.shiftBit | ShortcutSpec.optBit | ShortcutSpec.ctrlBit
    /// F13 to F19: keys with no function on any keyboard that sold in years.
    static let fKeys: [UInt16] = [105, 107, 113, 106, 64, 79, 80]

    /// Sends Carbon a "hot key pressed" event for `action`, as the system does when its combination is typed.
    @MainActor static func press(_ action: ShortcutAction) {
        var event: EventRef?
        let created = CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0,
                                  EventAttributes(kEventAttributeNone), &event)
        precondition(created == noErr && event != nil, "CreateEvent failed (\(created))")
        var id = EventHotKeyID(signature: OSType(0x4E4D4557),
                               id: UInt32(ShortcutAction.allCases.firstIndex(of: action)!))
        let set = SetEventParameter(event, EventParamName(kEventParamDirectObject),
                                    EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &id)
        precondition(set == noErr, "SetEventParameter failed (\(set))")
        SendEventToEventTarget(event, GetApplicationEventTarget())
        ReleaseEvent(event)
    }

    @MainActor static func main() {
        let ud = MemoryStore()
        let center = HotKeyCenter.shared
        center.store = ud
        let actions = ShortcutLogic.available(appStore: false).filter { $0 != .toggleIsland }
        check(actions.count == 7, "seven actions besides the island shortcut")
        for (action, key) in zip(actions, fKeys) {
            ShortcutLogic.save(ShortcutSpec(keyCode: key, nsFlags: allFour), for: action, in: ud)
        }
        ShortcutLogic.save(ShortcutSpec(keyCode: 90, nsFlags: allFour), for: .toggleIsland, in: ud)  // F20

        // Start: what is on at first is registered (five of the eight), and a press runs the right action, once.
        let onAtFirst = actions.filter { $0.enabledByDefault }
        check(onAtFirst.count == 5, "five are on at first")
        var pressed: [ShortcutAction] = []
        center.start { pressed.append($0) }
        check(center.registered == Set(onAtFirst), "only the five that are on at first are registered")
        check(center.conflicts.isEmpty, "no conflicts: \(center.conflicts)")
        for action in onAtFirst { press(action) }
        check(pressed == onAtFirst, "each press runs its own action, in order: \(pressed)")
        press(.openChat)
        check(pressed.count == onAtFirst.count, "a shortcut that is off is not delivered")

        // "Turn all on" with the real thing behind it: the other three are registered, and delivered.
        let left = ShortcutLogic.turnAllOn(appStore: false, in: ud) { action in
            center.reregister(action)
            return !center.conflicts.contains(action)
        }
        check(left.isEmpty, "nothing is left off when every combination is free: \(left)")
        check(center.registered == Set(ShortcutAction.allCases), "all eight are registered")
        pressed.removeAll()
        for action in ShortcutAction.allCases { press(action) }
        check(pressed == ShortcutAction.allCases, "and each is delivered: \(pressed)")

        // Turning one off and back.
        ShortcutLogic.setEnabled(false, for: .muteToggle, in: ud)
        center.reregister(.muteToggle)
        check(!center.registered.contains(.muteToggle), "turned off, it is not registered")
        check(center.registered.count == 7, "the others stay")

        // A new key for one action: the old combination is released, the new one taken.
        ShortcutLogic.save(ShortcutSpec(keyCode: 96, nsFlags: allFour), for: .openChat, in: ud)  // F5 with ⌃⌥⇧⌘
        center.reregister(.openChat)
        check(center.registered.contains(.openChat) && center.conflicts.isEmpty, "re-registered under its new key")

        // Two shortcuts of ours on one combination: the second one is refused and reported.
        ShortcutLogic.setEnabled(true, for: .muteToggle, in: ud)
        let first = ShortcutAction.goToAlert   // before .muteToggle in the list: it keeps the combination
        ShortcutLogic.save(ShortcutLogic.hotKey(for: first, in: ud), for: .muteToggle, in: ud)
        center.registerAll()
        check(center.conflicts == [.muteToggle], "the later one is reported: \(center.conflicts)")
        check(center.registered.count == 7 && !center.registered.contains(.muteToggle),
              "eight are on, the refused one is not registered: \(center.registered.count)")
        pressed.removeAll()
        press(first)
        check(pressed == [first], "the first one still works")
        // A conflict clears when the shortcut is turned off.
        ShortcutLogic.setEnabled(false, for: .muteToggle, in: ud)
        center.reregister(.muteToggle)
        check(center.conflicts.isEmpty, "turned off, its conflict is gone")

        // Quit: everything is released, and a second start does not install a second handler.
        center.unregisterAll()
        check(center.registered.isEmpty, "nothing registered after unregisterAll")
        pressed.removeAll()
        press(actions[1])
        check(pressed.isEmpty, "a press after unregisterAll is ignored")
        center.start { pressed.append($0) }
        press(actions[1])
        check(pressed == [actions[1]], "one start, one delivery (\(pressed))")
        center.unregisterAll()

        print("HotKeyCenter: \(cases) cases passed")
    }
}
```

**Create `scripts/test-hotkeys.sh`**

```bash
#!/usr/bin/env bash
# The Carbon plumbing of HotKeyCenter (register, conflict, release, a simulated press). Needs a logged-in
# macOS session, like the app; it is not a CI step.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-hotkeys.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 6 NotchBuddy/Sources/App/ShortcutLogic.swift NotchBuddy/Sources/App/HotKeyCenter.swift \
    tests/HotKeyCenterTests.swift -o "$TEST_DIR/hotkey-tests"
"$TEST_DIR/hotkey-tests"
```

- [ ] **Step 2: Run the test and see it fail**

Run: `chmod +x scripts/test-hotkeys.sh && bash scripts/test-hotkeys.sh`
Expected: FAIL, `error opening input file 'NotchBuddy/Sources/App/HotKeyCenter.swift' (No such file or directory)`.

- [ ] **Step 3: Write the Carbon wrapper**

**Create `NotchBuddy/Sources/App/HotKeyCenter.swift`**

```swift
import AppKit
import Carbon.HIToolbox

// MARK: - C-level event handler
//
// Carbon's InstallEventHandler wants a top-level C-compatible function, so the state it reads lives in
// globals. They are only touched on the main thread: Carbon delivers hot-key events there, and
// `HotKeyCenter` is main-actor isolated.

private nonisolated(unsafe) var gHotKeyHandler: EventHandlerRef? = nil
private nonisolated(unsafe) var gHotKeyTable: [UInt32: ShortcutAction] = [:]
private nonisolated(unsafe) var gOnAction: (@MainActor (ShortcutAction) -> Void)? = nil

private func notchMeowHotKeyEventHandler(
    _: EventHandlerCallRef?,
    _ event: EventRef?,
    _: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hkid = EventHotKeyID()
    let err = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hkid
    )
    guard err == noErr, let action = gHotKeyTable[hkid.id] else {
        return OSStatus(eventNotHandledErr)
    }
    MainActor.assumeIsolated { gOnAction?(action) }
    return noErr
}

// MARK: - HotKeyCenter

/// Registers NotchMeow's global shortcuts with Carbon `RegisterEventHotKey`.
///
/// - No Accessibility or Input Monitoring permission, and it works in the App Store sandbox.
/// - A registered key press is consumed: it never reaches the app in front. That is why
///   `ShortcutSpec.isUsableGlobal` keeps plain typing keys out.
/// - Which shortcuts are on, and their keys, come from `ShortcutLogic` (UserDefaults).
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()
    private init() {}

    /// "NMEW": the signature of NotchMeow's hot-key IDs.
    private let kSignature = OSType(0x4E4D4557)

    private var refs: [ShortcutAction: EventHotKeyRef] = [:]
    private var combinations: [ShortcutAction: ShortcutSpec] = [:]

    /// Where the shortcuts are read from: the app's settings. Tests point it at a dictionary.
    var store: any ShortcutStore = UserDefaults.standard

    /// The shortcuts that are registered right now.
    var registered: Set<ShortcutAction> { Set(refs.keys) }

    /// Shortcuts that were not registered: macOS refused them (another app or the system owns the combination), or
    /// another NotchMeow shortcut already has it (Carbon would take both and run only one).
    private(set) var conflicts: Set<ShortcutAction> = []

    // MARK: Lifecycle

    /// Installs the handler (once) and registers every shortcut that is on. `onAction` runs on the main
    /// actor each time one is pressed.
    func start(onAction: @escaping @MainActor (ShortcutAction) -> Void) {
        gOnAction = onAction
        if gHotKeyHandler == nil {
            var spec = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                notchMeowHotKeyEventHandler,
                1, &spec,
                nil, &gHotKeyHandler
            )
            guard status == noErr else { gHotKeyHandler = nil; return }
        }
        registerAll()
    }

    /// Unregisters every hot key (app quit).
    func unregisterAll() {
        for (action, ref) in refs {
            UnregisterEventHotKey(ref)
            gHotKeyTable.removeValue(forKey: Self.carbonID(action))
        }
        refs.removeAll()
        combinations.removeAll()
    }

    /// Registers again from the stored settings: what is on, with its keys.
    func registerAll() {
        unregisterAll()
        conflicts.removeAll()
        let active = ShortcutLogic.activeSpecs(in: store)
        for action in ShortcutAction.allCases {   // in order: of two on one combination, the first wins
            if let spec = active[action] { register(action, spec) }
        }
    }

    /// Registers one action again after its key or its switch changed.
    func reregister(_ action: ShortcutAction) {
        if let ref = refs.removeValue(forKey: action) {
            UnregisterEventHotKey(ref)
            gHotKeyTable.removeValue(forKey: Self.carbonID(action))
        }
        combinations.removeValue(forKey: action)
        conflicts.remove(action)
        if let spec = ShortcutLogic.activeSpecs(in: store)[action] { register(action, spec) }
    }

    // MARK: Private

    private static func carbonID(_ action: ShortcutAction) -> UInt32 {
        UInt32(ShortcutAction.allCases.firstIndex(of: action)!)
    }

    private func register(_ action: ShortcutAction, _ spec: ShortcutSpec) {
        guard !combinations.contains(where: { $0.value == spec }) else {
            conflicts.insert(action)
            return
        }
        let id = Self.carbonID(action)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(spec.keyCode),
            ShortcutLogic.carbonModifiers(fromNS: spec.nsFlags),
            EventHotKeyID(signature: kSignature, id: id),
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr, let ref {
            refs[action] = ref
            combinations[action] = spec
            gHotKeyTable[id] = action
        } else {
            conflicts.insert(action)
        }
    }
}
```

- [ ] **Step 4: Run the test and see it pass**

Run: `bash scripts/test-hotkeys.sh`
Expected: PASS, `HotKeyCenter: 19 cases passed`. If it crashes at once, there is no window-server session (a remote shell): run it from the Terminal app.

- [ ] **Step 5: Release the hot keys on quit**

**Edit `NotchBuddy/Sources/App/AppDelegate.swift`** — replace:

```swift
    private(set) var islandController: IslandWindowController?

    func applicationDidFinishLaunching(_ notification: Notification) {
```

with:

```swift
    private(set) var islandController: IslandWindowController?

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyCenter.shared.unregisterAll()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
```

- [ ] **Step 6: Put the old Hotkey setting on the shared store**

`AppState.hotkey*` keep their names and types, so nothing that reads them changes. The three lines that loaded them in `init()` go (the old `UInt16(v)` there trapped on a bad value).

**Edit `NotchBuddy/Sources/App/AppState.swift`** — replace:

```swift
    // Hotkey to show island (e.g. ⌘⇧N)
    @Published var hotkeyEnabled: Bool = false {
        didSet { UserDefaults.standard.set(hotkeyEnabled, forKey: "hotkeyEnabled") }
    }
    var hotkeyFlags: UInt = NSEvent.ModifierFlags([.command, .shift]).rawValue {
        didSet { UserDefaults.standard.set(Int(hotkeyFlags), forKey: "hotkeyFlags") }
    }
    var hotkeyCode: UInt16 = 45 {  // 'n'
        didSet { UserDefaults.standard.set(Int(hotkeyCode), forKey: "hotkeyCode") }
    }
```

with:

```swift
    // Hotkey to open or close the island (⌘⇧N by default). It is stored with the other shortcuts, in
    // ShortcutLogic (same UserDefaults keys as before), so General and Settings → Shortcuts show one value.
    var hotkeyEnabled: Bool {
        get { ShortcutLogic.isEnabled(.toggleIsland) }
        set { objectWillChange.send(); ShortcutLogic.setEnabled(newValue, for: .toggleIsland) }
    }
    var hotkeyFlags: UInt {
        get { ShortcutLogic.hotKey(for: .toggleIsland).nsFlags }
        set {
            var spec = ShortcutLogic.hotKey(for: .toggleIsland)
            spec.nsFlags = newValue
            ShortcutLogic.save(spec, for: .toggleIsland)
        }
    }
    var hotkeyCode: UInt16 {
        get { ShortcutLogic.hotKey(for: .toggleIsland).keyCode }
        set {
            var spec = ShortcutLogic.hotKey(for: .toggleIsland)
            spec.keyCode = newValue
            ShortcutLogic.save(spec, for: .toggleIsland)
        }
    }
```

**Edit `NotchBuddy/Sources/App/AppState.swift`**, and replace:

```swift
        if let v = ud.object(forKey: "hotkeyEnabled") as? Bool  { hotkeyEnabled = v }
        if let v = ud.object(forKey: "hotkeyFlags")   as? Int   { hotkeyFlags = UInt(v) }
        if let v = ud.object(forKey: "hotkeyCode")    as? Int   { hotkeyCode = UInt16(v) }
        if let d = ud.data(forKey: "vercelProjectFilter"),
```

with:

```swift
        if let d = ud.data(forKey: "vercelProjectFilter"),
```

- [ ] **Step 7: Make General → Hotkey register what it changes**

The box looks exactly as before. Its two `@State` copies of the combination go; it reads and writes the shared store and registers the result.

**Edit `NotchBuddy/Sources/App/SettingsView.swift`** — replace:

```swift
    // Hotkey
    @State private var hotkeyFlags: UInt    = AppState.shared.hotkeyFlags
    @State private var hotkeyCode: UInt16   = AppState.shared.hotkeyCode

    // Vercel project filter
```

with:

```swift
    // Vercel project filter
```

**Edit `NotchBuddy/Sources/App/SettingsView.swift`**, and replace:

```swift
                Toggle("Show island with shortcut", isOn: $state.hotkeyEnabled)
                if state.hotkeyEnabled {
                    HStack(spacing: 8) {
                        Text("Shortcut")
                            .frame(width: 70, alignment: .leading)
                        ShortcutRecorderButton(flags: $hotkeyFlags, code: $hotkeyCode)
                            .onChange(of: hotkeyFlags) { _, v in state.hotkeyFlags = v }
                            .onChange(of: hotkeyCode)  { _, v in state.hotkeyCode  = v }
                        Text("presses this → island opens")
```

with:

```swift
                Toggle("Show island with shortcut", isOn: Binding(
                    get: { state.hotkeyEnabled },
                    set: { state.hotkeyEnabled = $0; HotKeyCenter.shared.reregister(.toggleIsland) }
                ))
                if state.hotkeyEnabled {
                    HStack(spacing: 8) {
                        Text("Shortcut")
                            .frame(width: 70, alignment: .leading)
                        ShortcutRecorderButton(
                            flags: Binding(
                                get: { state.hotkeyFlags },
                                set: { state.hotkeyFlags = $0; HotKeyCenter.shared.reregister(.toggleIsland) }
                            ),
                            code: Binding(
                                get: { state.hotkeyCode },
                                set: { state.hotkeyCode = $0; HotKeyCenter.shared.reregister(.toggleIsland) }
                            ))
                        Text("presses this → island opens")
```

- [ ] **Step 8: Run the actions from the island controller, and drop the old monitor**

The old `NSEvent` global monitor for the hotkey (it needed a permission and only ever opened the island) is replaced by `HotKeyCenter`. Every action that opens the island tells the state machine and gives the island the keyboard.

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`** — replace:

```swift
        startPolling()
        startKeyMonitor()
        wireFSM()
```

with:

```swift
        startPolling()
        startKeyMonitor()
        startHotKeys()
        wireFSM()
```

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`**, and replace:

```swift
    // MARK: - Keyboard (Escape closes)

    private func startKeyMonitor() {
```

with:

```swift
    // MARK: - Global hot keys (Carbon)

    private func startHotKeys() {
        HotKeyCenter.shared.start { [weak self] action in
            self?.handleHotKey(action)
        }
    }

    func handleHotKey(_ action: ShortcutAction) {
        switch action {
        case .toggleIsland:
            if state.mode == .expanded {
                collapse()
            } else {
                openWithKeyboard(defaultView())
            }

        case .openChat:
            openWithKeyboard(.prompt)

        case .goToAlert:
            if state.pendingApproval != nil {
                openWithKeyboard(.approval)
            } else if state.pendingQuestion != nil {
                openWithKeyboard(.question)
            } else {
                NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.annoyed)
                SoundEngine.shared.play("error")
            }

        case .jumpToTerminal:
            #if !APPSTORE
            performJumpToTerminal()
            #endif

        case .attachFrontWindow:
            #if !APPSTORE
            performAttachFrontWindow()
            #endif

        case .nextPill:
            cyclePill(by: +1)

        case .prevPill:
            cyclePill(by: -1)

        case .muteToggle:
            state.soundEnabled.toggle()
            if state.soundEnabled { SoundEngine.shared.play("tick") }
            NotificationCenter.default.post(
                name: .triggerEmote,
                object: state.soundEnabled ? BotEmote.happy : BotEmote.annoyed)
        }
    }

    /// Opens the island on `view` and gives it the keyboard, so the island shortcuts and ⎋ work until it closes.
    /// The state machine is told, like a hook alert does, so its timers don't fold the island under the user.
    private func openWithKeyboard(_ view: IslandView) {
        fsm.openedExternally()
        islandPanel.makeKey()
        expand(to: view)
    }

    // MARK: - Pill helpers

    /// ⌃⌥] and ⌃⌥[ (and ⌘→ and ⌘← in the island): the next or previous pill, opening the island if it is closed.
    /// Nothing happens while a permission request or a question is waiting: its card stays on screen, with its agent.
    func cyclePill(by delta: Int) {
        guard let id = ShortcutLogic.pillID(from: state.tasks.map(\.id), current: state.focusId, delta: delta,
                                            decisionWaiting: decisionWaiting) else { return }
        showPill(id)
    }

    private var decisionWaiting: Bool { state.pendingApproval != nil || state.pendingQuestion != nil }

    private func showPill(_ id: String) {
        state.setFocus(id)
        fsm.openedExternally()
        expand(to: .overview)
    }

    // MARK: - Terminal jump and window attach

    #if !APPSTORE
    /// ⌃⌥T: brings the agent's terminal forward, as the cards' "Open terminal" button does.
    private func performJumpToTerminal() {
        guard state.focusTask != nil else {
            SoundEngine.shared.play("error")
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.annoyed)
            return
        }
        let running = NSWorkspace.shared.runningApplications
        if let terminal = ShortcutLogic.terminalBundleIds.compactMap({ id in
            running.first { $0.bundleIdentifier == id }
        }).first {
            terminal.activate(options: .activateIgnoringOtherApps)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
        }
        collapse()
    }

    /// ⌃⌥W: the window that was in front becomes the chat's context, as when the cat is dragged onto it.
    private func performAttachFrontWindow() {
        guard let app = state.lastExternalApp,
              let ctx = WindowContextCapture.captureActive(from: app) else {
            SoundEngine.shared.play("error")
            return
        }
        state.promptContext = ctx
        // The context only goes with a conversation's first message, so a new window starts a new one.
        ClaudeService.shared.clearConversation(state: state)
        SoundEngine.shared.play("approve")
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
        openWithKeyboard(.prompt)
    }
    #endif

    // MARK: - Keyboard (Escape closes)

    private func startKeyMonitor() {
```

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`**, and replace:

```swift
        // Global hotkey to show island
        NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                guard let self, self.state.hotkeyEnabled else { return }
                let pressed = event.modifierFlags.intersection([.command, .control, .option, .shift]).rawValue
                guard pressed == self.state.hotkeyFlags, event.keyCode == self.state.hotkeyCode else { return }
                if self.state.mode == .hidden || self.state.mode == .compact {
                    self.expand(to: .overview)
                }
            }
        }

        // Track last external app for window context capture
```

with:

```swift
        // Track last external app for window context capture
```

- [ ] **Step 9: Build and run the tests**

Run: `cd NotchBuddy && xcodegen && xcodebuild -scheme NotchBuddy -configuration Debug -derivedDataPath build build CODE_SIGNING_ALLOWED=NO && cd .. && bash scripts/test-shortcuts.sh && bash scripts/test-hotkeys.sh`
Expected: PASS: `** BUILD SUCCEEDED **`, then both test programs pass. `IslandWindowController.swift` gains one warning, the same `activateIgnoringOtherApps` deprecation the cards' own terminal buttons already have.

- [ ] **Step 10: Read the diff for what the build cannot say**

Check by reading:
- `HotKeyCenter` is the only user of `RegisterEventHotKey`; `registerAll` loops `ShortcutAction.allCases` in order and a second shortcut on one combination is refused (`combinations`); `unregisterAll` is called from `applicationWillTerminate`.
- `handleHotKey` has one case per `ShortcutAction` and no `default`; `.jumpToTerminal` and `.attachFrontWindow` are inside `#if !APPSTORE`; `grep -n "addGlobalMonitorForEvents" NotchBuddy/Sources/App/IslandWindowController.swift` still prints the Escape monitor and the `leftMouseUp` one, and no longer the hotkey one.
- `performAttachFrontWindow` calls `clearConversation(state:)` before opening the chat, like the drag path further down the file.
- `openWithKeyboard` calls `fsm.openedExternally()` before `makeKey()` and `expand(to:)`.
- `cyclePill` passes `decisionWaiting`; `showPill` is never reached while a request waits.
- `grep -rn "Coucou\|Mochi\|COUC" NotchBuddy/Sources/App/HotKeyCenter.swift NotchBuddy/Sources/App/ShortcutLogic.swift` prints nothing.
- General → Hotkey: no `@State` copy of the combination is left (`grep -n "hotkeyFlags\|hotkeyCode" NotchBuddy/Sources/App/SettingsView.swift` shows only `state.hotkeyFlags` and `state.hotkeyCode`), and the labels and layout are unchanged.

- [ ] **Step 11: Commit**

```bash
git add NotchBuddy/Sources/App/HotKeyCenter.swift tests/HotKeyCenterTests.swift scripts/test-hotkeys.sh NotchBuddy/Sources/App/AppDelegate.swift NotchBuddy/Sources/App/AppState.swift NotchBuddy/Sources/App/SettingsView.swift NotchBuddy/Sources/App/IslandWindowController.swift NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -m "feat(shortcuts): global shortcuts through Carbon: chat, alert, terminal, front window, pills, mute and the island hotkey

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: The island's own shortcuts

Agent: `nm-implementer`.

**Files:**
- Create: `NotchBuddy/Sources/App/EscapeRouting.swift`, `tests/EscapeRoutingTests.swift`, `scripts/test-escape.sh`
- Modify: `NotchBuddy/Sources/App/AppState.swift`, `NotchBuddy/Sources/App/IslandWindowController.swift`, `NotchBuddy/Sources/App/IslandViewContent.swift`, `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` (regenerated)

**Interfaces:**
- Consumes: Task 1's `IslandKeyContext`, `ShortcutLogic.islandCommand(keyCode:nsFlags:characters:in:)`, `navigate`, `clampSelection`, `pillID(number:in:decisionWaiting:)`; Task 2's `cyclePill(by:)`, `showPill(_:)`, `decisionWaiting`.
- Produces: `enum EscapeRouting { @MainActor static func consumer(in window: NSWindow) -> NSResponder?; @MainActor static func isComposing(in window: NSWindow) -> Bool }`; `AppState.cardSelection: Int?` and `cardItemCount: Int` (both `@Published`); `Notification.Name.islandSendMessage`, `.islandNewConversation`, `.islandToggleDiff`, `.islandActivateCardSelection`; `IslandWindowController.handleIslandKey(_:)` (private) behind a local key monitor.

- [ ] **Step 1: Write the failing test and its script**

Real SwiftUI views in an invisible panel (alpha 0, no mouse), the way the island is built. It needs a logged-in macOS session.

**Create `tests/EscapeRoutingTests.swift`**

```swift
import AppKit
import SwiftUI

/// ⎋ in the island: which responder, if any, takes it before the island closes. Real SwiftUI views in an invisible
/// panel (alpha 0, no mouse), like the island's own, so it needs a logged-in macOS session.
@main
enum EscapeRoutingTests {
    nonisolated(unsafe) static var cases = 0
    nonisolated(unsafe) static var exitHits = 0

    static func check(_ ok: Bool, _ message: @autoclosure () -> String,
                      file: StaticString = #file, line: UInt = #line) {
        cases += 1
        precondition(ok, message(), file: file, line: line)
    }

    final class KeyPanel: NSPanel { override var canBecomeKey: Bool { true } }

    enum Kind { case nothingFocused, button, textField, focusedViewWithExit, textFieldWithExit }

    struct Content: View {
        let kind: Kind
        @FocusState private var focused: Bool
        @State private var text = ""
        var body: some View {
            switch kind {
            case .nothingFocused:
                Text("card").frame(width: 120, height: 40)
            case .button:
                Button("go") {}.frame(width: 120, height: 40)
            case .textField:
                TextField("Ask me anything…", text: $text).focused($focused)
                    .onAppear { focused = true }.frame(width: 120, height: 40)
            case .focusedViewWithExit:
                Text("list").frame(width: 120, height: 40).focusable().focused($focused)
                    .onAppear { focused = true }.onExitCommand { EscapeRoutingTests.exitHits += 1 }
            case .textFieldWithExit:
                TextField("Other…", text: $text).focused($focused)
                    .onAppear { focused = true }.onExitCommand { EscapeRoutingTests.exitHits += 1 }
                    .frame(width: 120, height: 40)
            }
        }
    }

    /// Shows `kind` in a key panel, lets SwiftUI settle, and runs `body` with the panel.
    @MainActor static func inPanel(_ kind: Kind, _ body: (NSPanel) -> Void) {
        let panel = KeyPanel(contentRect: NSRect(x: 0, y: 0, width: 120, height: 40),
                             styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.alphaValue = 0
        panel.ignoresMouseEvents = true
        panel.contentView = NSHostingView(rootView: Content(kind: kind))
        panel.orderFrontRegardless()
        panel.makeKey()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        body(panel)
        panel.orderOut(nil)
    }

    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        let cancel = #selector(NSStandardKeyBindingResponding.cancelOperation(_:))

        // The reason this type exists: the panel always answers cancelOperation:, so sendAction says "handled".
        inPanel(.nothingFocused) { panel in
            check(panel.isKeyWindow, "the panel is the key window")
            check(NSApp.sendAction(cancel, to: nil, from: nil), "sendAction says handled even though no view did")
            check(EscapeRouting.consumer(in: panel) == nil, "but no view in the chain handles it")
        }
        inPanel(.button) { panel in
            check(EscapeRouting.consumer(in: panel) == nil, "a button does not take ⎋")
        }
        inPanel(.textField) { panel in
            check(panel.firstResponder != nil && panel.firstResponder !== panel, "the chat field has the focus")
            check(EscapeRouting.consumer(in: panel) == nil, "a text field without .onExitCommand does not take ⎋: the island closes")
            // An input method or a dead key composing in the field: ⎋ cancels the composition, the island stays.
            check(!EscapeRouting.isComposing(in: panel), "nothing is composing yet")
            guard let input = panel.firstResponder as? NSTextInputClient else {
                preconditionFailure("the field's editor must be a text input client")
            }
            input.setMarkedText("é", selectedRange: NSRange(location: 1, length: 0),
                                replacementRange: NSRange(location: NSNotFound, length: 0))
            check(EscapeRouting.isComposing(in: panel), "marked text means the field is composing")
            input.unmarkText()
            check(!EscapeRouting.isComposing(in: panel), "and not any more once it is committed")
        }
        inPanel(.nothingFocused) { panel in
            check(!EscapeRouting.isComposing(in: panel), "no text field, no composition")
        }
        inPanel(.focusedViewWithExit) { panel in
            exitHits = 0
            guard let responder = EscapeRouting.consumer(in: panel) else {
                preconditionFailure("a focused view with .onExitCommand must take ⎋")
            }
            check(NSApp.sendAction(cancel, to: responder, from: nil), "the action is delivered")
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            check(exitHits == 1, "and its .onExitCommand ran once (\(exitHits))")
        }
        inPanel(.textFieldWithExit) { panel in
            exitHits = 0
            guard let responder = EscapeRouting.consumer(in: panel) else {
                preconditionFailure("the Other… field's .onExitCommand must take ⎋")
            }
            _ = NSApp.sendAction(cancel, to: responder, from: nil)
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            check(exitHits == 1, "the field's .onExitCommand ran once (\(exitHits))")
        }
        print("Escape routing: \(cases) cases passed")
    }
}
```

**Create `scripts/test-escape.sh`**

```bash
#!/usr/bin/env bash
# Which view takes ⎋ before the island closes, with real SwiftUI views in an invisible panel. Needs a
# logged-in macOS session, like the app; it is not a CI step.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-escape.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 6 NotchBuddy/Sources/App/EscapeRouting.swift tests/EscapeRoutingTests.swift \
    -o "$TEST_DIR/escape-tests"
"$TEST_DIR/escape-tests"
```

- [ ] **Step 2: Run the test and see it fail**

Run: `chmod +x scripts/test-escape.sh && bash scripts/test-escape.sh`
Expected: FAIL, `error opening input file 'NotchBuddy/Sources/App/EscapeRouting.swift' (No such file or directory)`.

- [ ] **Step 3: Write the routing**

**Create `NotchBuddy/Sources/App/EscapeRouting.swift`**

```swift
import AppKit

/// Who gets ⎋ before the island closes.
enum EscapeRouting {
    /// The responder in `window`'s chain that handles ⎋ (`cancelOperation:`): a focused view with `.onExitCommand`
    /// (the "Other…" field, a list that goes back, a diff). Nil when none does, and then ⎋ closes the island.
    ///
    /// `NSApp.sendAction(_:to:from:)` cannot answer this: the panel itself responds to `cancelOperation:`, so it
    /// reports "handled" even when no view did, and the island would never close.
    @MainActor static func consumer(in window: NSWindow) -> NSResponder? {
        let cancel = #selector(NSStandardKeyBindingResponding.cancelOperation(_:))
        var responder = window.firstResponder
        while let current = responder, current !== window {
            if current.responds(to: cancel) { return current }
            responder = current.nextResponder
        }
        return nil
    }

    /// True while the focused text field is composing: an input method or a dead key has marked text on screen. ⎋
    /// then belongs to that composition (it cancels it), not to the island.
    @MainActor static func isComposing(in window: NSWindow) -> Bool {
        (window.firstResponder as? NSTextInputClient)?.hasMarkedText() ?? false
    }
}
```

- [ ] **Step 4: Run the test and see it pass**

Run: `bash scripts/test-escape.sh`
Expected: PASS, `Escape routing: 13 cases passed`.

- [ ] **Step 5: State for the keyboard-driven list selection**

**Edit `NotchBuddy/Sources/App/AppState.swift`** — replace:

```swift
    // Pinned (alerts that stay open, never auto-close)
    var isPinned: Bool = false
```

with:

```swift
    // Pinned (alerts that stay open, never auto-close)
    var isPinned: Bool = false

    // Keyboard navigation: the selected row of the list on the card on screen (nil = none), and how
    // many rows that list has (0 = the card has no list).
    @Published var cardSelection: Int? = nil
    @Published var cardItemCount: Int = 0
```

- [ ] **Step 6: The local key monitor, ⎋, and the notification names**

The monitor does nothing unless the island panel is the key window. It passes the key's character without modifiers (`charactersIgnoringModifiers`), so ⌘, is the comma on any layout. `showPill` also clears the list selection now that `cardSelection` exists.

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`** — replace:

```swift
    private var keyMonitor: Any?
    private var viewSubscription: AnyCancellable?
```

with:

```swift
    private var keyMonitor: Any?
    private var localKeyMonitor: Any?
    private var viewSubscription: AnyCancellable?
```

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`**, and replace:

```swift
        startKeyMonitor()
        startHotKeys()
        wireFSM()
```

with:

```swift
        startKeyMonitor()
        startLocalKeyMonitor()
        startHotKeys()
        wireFSM()
```

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`**, and replace:

```swift
    private func showPill(_ id: String) {
        state.setFocus(id)
        fsm.openedExternally()
        expand(to: .overview)
    }
```

with:

```swift
    private func showPill(_ id: String) {
        state.setFocus(id)
        state.cardSelection = nil
        fsm.openedExternally()
        expand(to: .overview)
    }

    // MARK: - Island-local shortcuts (while the island has the keyboard)

    private func startLocalKeyMonitor() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let handled = MainActor.assumeIsolated { self.handleIslandKey(event) }
            return handled ? nil : event
        }
    }

    /// Runs the island shortcut `event` stands for. Returns false, and the key goes on, when it stands for none
    /// or the island is not the key window (Settings, another app).
    private func handleIslandKey(_ event: NSEvent) -> Bool {
        guard islandPanel.isKeyWindow else { return false }
        let context = IslandKeyContext(inOverview: state.view == .overview, inChat: state.view == .prompt)
        guard let command = ShortcutLogic.islandCommand(
            keyCode: event.keyCode, nsFlags: event.modifierFlags.rawValue,
            characters: event.charactersIgnoringModifiers, in: context) else { return false }
        switch command {
        case .nextPill:        cyclePill(by: +1)
        case .prevPill:        cyclePill(by: -1)
        case .pill(let n):
            if let id = ShortcutLogic.pillID(number: n, in: state.tasks.map(\.id), decisionWaiting: decisionWaiting) { showPill(id) }
        case .listDown:        navigateCard(by: +1)
        case .listUp:          navigateCard(by: -1)
        case .openSelection:   openCardSelection()
        case .toggleDiff:      NotificationCenter.default.post(name: .islandToggleDiff, object: nil)
        case .sendMessage:     NotificationCenter.default.post(name: .islandSendMessage, object: nil)
        case .newConversation: NotificationCenter.default.post(name: .islandNewConversation, object: nil)
        case .openSettings:    NotificationCenter.default.post(name: .openFullSettings, object: nil)
        case .togglePin:       state.isPinned.toggle()
        case .escape:
            if EscapeRouting.isComposing(in: islandPanel) { return false }   // ⎋ cancels the composition
            handleEscape()
        }
        return true
    }

    /// ⎋ with the island as key window. A focused view that handles it (the "Other…" field, a list, a diff) goes
    /// first; otherwise the island closes, unless it is pinned.
    private func handleEscape() {
        if let responder = EscapeRouting.consumer(in: islandPanel) {
            NSApp.sendAction(#selector(NSStandardKeyBindingResponding.cancelOperation(_:)), to: responder, from: nil)
        } else if state.mode == .expanded && !state.isPinned {
            collapse()
        }
    }

    private func navigateCard(by delta: Int) {
        guard state.view == .overview, state.cardItemCount > 0 else { return }
        state.cardSelection = ShortcutLogic.navigate(
            selection: state.cardSelection, delta: delta, itemCount: state.cardItemCount)
    }

    private func openCardSelection() {
        guard state.view == .overview, state.cardSelection != nil else { return }
        NotificationCenter.default.post(name: .islandActivateCardSelection, object: nil)
    }
```

**Edit `NotchBuddy/Sources/App/IslandWindowController.swift`**, and replace:

```swift
    static let islandCollapse   = Notification.Name("notchBuddy.islandCollapse")
    static let openFullSettings = Notification.Name("notchBuddy.openFullSettings")
```

with:

```swift
    static let islandCollapse   = Notification.Name("notchBuddy.islandCollapse")
    // Island shortcuts → the views that act on them
    static let islandSendMessage           = Notification.Name("notchBuddy.islandSendMessage")
    static let islandNewConversation       = Notification.Name("notchBuddy.islandNewConversation")
    static let islandToggleDiff            = Notification.Name("notchBuddy.islandToggleDiff")
    static let islandActivateCardSelection = Notification.Name("notchBuddy.islandActivateCardSelection")
    static let openFullSettings = Notification.Name("notchBuddy.openFullSettings")
```

- [ ] **Step 7: The views that act on the keys**

Every island view is alive at once (`IslandContentView` keeps them all in a `ZStack`), so each receiver checks `state.view` first. The selected GitHub row is drawn *behind* its text and only while selected, so no row looks different otherwise.

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`** — replace:

```swift
        .onChange(of: state.mode) { _, m in
            #if !APPSTORE
            if m != .expanded { state.showingPlanDetail = false; activeDiffId = nil }
            #endif
            if m == .expanded && state.focusId == "integration_github" {
                GithubPoller.shared.refreshIfStale()
            }
        }
    }
```

with:

```swift
        .onChange(of: state.mode) { _, m in
            #if !APPSTORE
            if m != .expanded { state.showingPlanDetail = false; activeDiffId = nil }
            #endif
            if m == .expanded && state.focusId == "integration_github" {
                GithubPoller.shared.refreshIfStale()
            }
        }
        // ⌘E: open the latest diff of the pill on screen, or close the one that is open
        .onReceive(NotificationCenter.default.publisher(for: .islandToggleDiff)) { _ in
            guard state.view == .overview else { return }
            if activeDiffId != nil {
                withAnimation(.easeIn(duration: 0.16)) { activeDiffId = nil }
            } else if let task = agent, let last = state.sessionDiffs[task.id]?.last {
                withAnimation(.easeIn(duration: 0.16)) { activeDiffId = last.id }
            }
        }
    }
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`**, and replace:

```swift
        .onChange(of: state.chatStreaming) { _, streaming in
            if !streaming { focused = true }
        }
    }

    private func sendMessage() {
```

with:

```swift
        .onChange(of: state.chatStreaming) { _, streaming in
            if !streaming { focused = true }
        }
        // ⌘↩ sends, ⌘K starts a new conversation (every island view is alive at once: only the chat answers)
        .onReceive(NotificationCenter.default.publisher(for: .islandSendMessage)) { _ in
            guard state.view == .prompt else { return }
            sendMessage()
        }
        .onReceive(NotificationCenter.default.publisher(for: .islandNewConversation)) { _ in
            guard state.view == .prompt else { return }
            text = ""
            ClaudeService.shared.clearConversation(state: state)
            focused = true
        }
    }

    private func sendMessage() {
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`**, and replace:

```swift
    let stats: GitHubStats?
    let onBack: () -> Void

    private var title: String {
```

with:

```swift
    let stats: GitHubStats?
    let onBack: () -> Void
    @ObservedObject private var appState = AppState.shared

    private var title: String {
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`**, and replace:

```swift
    private var repoItems: [GitHubRepoCI] {
        section == .mainCI ? pulse.mainCI : []
    }

    var body: some View {
        if section == .activity {
```

with:

```swift
    private var repoItems: [GitHubRepoCI] {
        section == .mainCI ? pulse.mainCI : []
    }

    private var totalItems: Int { items.count + repoItems.count }

    /// ⌘O: opens the selected row on github.com, like a click on it.
    private func openSelectedRow() {
        guard appState.view == .overview, appState.mode == .expanded,
              let sel = appState.cardSelection else { return }
        let target: String
        if sel < items.count {
            target = items[sel].url
        } else if sel - items.count < repoItems.count {
            let base = repoItems[sel - items.count].url
            target = base.hasSuffix("/") ? base + "actions" : base + "/actions"
        } else {
            return
        }
        if let url = safeWebURL(target), url.host == "github.com" { NSWorkspace.shared.open(url) }
    }

    var body: some View {
        if section == .activity {
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`**, and replace:

```swift
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(items, id: \.id) { pr in
                                GitHubPRRowView(pr: pr, showCI: section == .myPRs)
                            }
                            ForEach(repoItems, id: \.repo) { repo in
                                GitHubRepoCIRowView(repo: repo)
                            }
                        }
                    }
                    .frame(maxHeight: 60)  // 3 rows × 20 pt; rest scrolls
                    .mask(
                        Group {
                            if (items.count + repoItems.count) > 3 {
```

with:

```swift
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(items.enumerated()), id: \.element.id) { idx, pr in
                                    GitHubPRRowView(pr: pr, showCI: section == .myPRs,
                                                    selected: appState.cardSelection == idx)
                                        .id(idx)
                                }
                                ForEach(Array(repoItems.enumerated()), id: \.element.repo) { idx, repo in
                                    GitHubRepoCIRowView(repo: repo,
                                                        selected: appState.cardSelection == items.count + idx)
                                        .id(items.count + idx)
                                }
                            }
                        }
                        // ⌘↓ and ⌘↑ can select a row below the three that show: keep it in view
                        .onChange(of: appState.cardSelection) { _, sel in
                            if let sel { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(sel) } }
                        }
                    }
                    .frame(maxHeight: 60)  // 3 rows × 20 pt; rest scrolls
                    .mask(
                        Group {
                            if totalItems > 3 {
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`**, and replace:

```swift
            .onAppear { GithubPoller.shared.refreshIfStale() }
            .onExitCommand { onBack() }
```

with:

```swift
            .onAppear {
                GithubPoller.shared.refreshIfStale()
                appState.cardSelection = nil
                appState.cardItemCount = totalItems
            }
            .onDisappear {
                appState.cardSelection = nil
                appState.cardItemCount = 0
            }
            // a poll can shorten the list under a selection
            .onChange(of: totalItems) { _, count in
                appState.cardItemCount = count
                appState.cardSelection = ShortcutLogic.clampSelection(appState.cardSelection, itemCount: count)
            }
            .onChange(of: appState.mode) { _, mode in
                if mode != .expanded { appState.cardSelection = nil }
            }
            .onReceive(NotificationCenter.default.publisher(for: .islandActivateCardSelection)) { _ in
                openSelectedRow()
            }
            .onExitCommand { onBack() }
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`**, and replace:

```swift
private struct GitHubPRRowView: View {
    let pr: GitHubPR
    let showCI: Bool
```

with:

```swift
private struct GitHubPRRowView: View {
    let pr: GitHubPR
    let showCI: Bool
    var selected: Bool = false
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`**, and replace:

```swift
                if pr.isDraft {
                    Text("Draft")
                        .font(.system(size: 9.5))
                        .foregroundColor(Color(hex: "#6B7079"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 20)
        }
```

with:

```swift
                if pr.isDraft {
                    Text("Draft")
                        .font(.system(size: 9.5))
                        .foregroundColor(Color(hex: "#6B7079"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 20)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.12))
                    .opacity(selected ? 1 : 0)
            )
        }
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`**, and replace:

```swift
private struct GitHubRepoCIRowView: View {
    let repo: GitHubRepoCI
```

with:

```swift
private struct GitHubRepoCIRowView: View {
    let repo: GitHubRepoCI
    var selected: Bool = false
```

**Edit `NotchBuddy/Sources/App/IslandViewContent.swift`**, and replace:

```swift
                if let word = ciStateWord {
                    Text(word)
                        .font(.system(size: 10))
                        .foregroundColor(ghCIDot(repo.ci))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 20)
        }
```

with:

```swift
                if let word = ciStateWord {
                    Text(word)
                        .font(.system(size: 10))
                        .foregroundColor(ghCIDot(repo.ci))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 20)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.12))
                    .opacity(selected ? 1 : 0)
            )
        }
```

- [ ] **Step 8: Build and run the tests**

Run: `cd NotchBuddy && xcodegen && xcodebuild -scheme NotchBuddy -configuration Debug -derivedDataPath build build CODE_SIGNING_ALLOWED=NO && cd .. && bash scripts/test-shortcuts.sh && bash scripts/test-escape.sh`
Expected: PASS: `** BUILD SUCCEEDED **`, and both programs pass. `IslandViewContent.swift` has no new warning.

- [ ] **Step 9: Read the diff for what the build cannot say**

Check by reading:
- `handleIslandKey` starts with `guard islandPanel.isKeyWindow`, every `ShortcutLogic.islandCommand` case has a branch, the call passes `characters: event.charactersIgnoringModifiers`, and the `.escape` branch returns `false` (the key goes on to the text field) while `EscapeRouting.isComposing` says an input method has marked text.
- `handleEscape` never calls `NSApp.sendAction` with `to: nil`: `grep -n "sendAction" NotchBuddy/Sources/App/IslandWindowController.swift` prints one line, with `to: responder`.
- Each receiver starts with a `state.view` guard: the diff toggle (`.overview`), send and new conversation (`.prompt`), and `openSelectedRow` (`.overview` and `.expanded`); `navigateCard` and `openCardSelection` check `.overview` too.
- ⌘K calls `ClaudeService.shared.clearConversation(state: state)` (which also empties `chatHistory`) and does not touch `state.promptContext`.
- The GitHub rows: `selected` defaults to `false`, the highlight is a `.background` at opacity 0 unless selected, `.id(idx)` and `.id(items.count + idx)` are the ids `proxy.scrollTo` uses, and `cardSelection` is reset on appear, on disappear, when the island is not expanded, and (by `clampSelection`) when the list shrinks.
- Nothing in the `GitHubActivityDetailContent` branch changed.

- [ ] **Step 10: Commit**

```bash
git add NotchBuddy/Sources/App/EscapeRouting.swift tests/EscapeRoutingTests.swift scripts/test-escape.sh NotchBuddy/Sources/App/AppState.swift NotchBuddy/Sources/App/IslandWindowController.swift NotchBuddy/Sources/App/IslandViewContent.swift NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -m "feat(shortcuts): the island's own keys: pills, lists, diff, chat, settings, pin and escape

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Settings → Shortcuts

Agent: `nm-implementer`.

**Files:**
- Create: `NotchBuddy/Sources/App/KeyLayoutNames.swift`, `tests/KeyLayoutNamesTests.swift`, `scripts/test-keynames.sh`, `NotchBuddy/Sources/App/ShortcutsSettingsView.swift`
- Modify: `NotchBuddy/Sources/App/SettingsView.swift`, `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` (regenerated)

**Interfaces:**
- Consumes: Task 1's `ShortcutLogic` (`available()`, `hotKey(for:)`, `isEnabled`, `setEnabled`, `save`, `resetToDefault`, `activeSpecs()`, `duplicates(in:)`, `displayString(for:keyName:)`, `recorderKey(keyCode:nsFlags:)`, `islandShortcuts`, `defaults`) and Task 2's `HotKeyCenter.shared` (`reregister`, `registerAll`, `conflicts`).
- Produces: `enum KeyLayoutNames { @MainActor static func name(for keyCode: UInt16) -> String?; @MainActor static func name(for keyCode: UInt16, in source: TISInputSource) -> String?; @MainActor static func layout(id: String) -> TISInputSource? }`; `struct ShortcutsSettingsView: View`; `ShortcutRecorderButton(flags:code:onRecorded:)` (the first two as before, `onRecorded` optional); `Notification.Name.shortcutRecordingStarted`; the sidebar tag `"shortcuts"`.

The key names are tested against real layouts. The pane and the recorder are UI over code the earlier tasks tested, so their proof is the build, the read of the diff and the owner's manual checks 6, 7 and 9.

- [ ] **Step 1: Write the failing test and its script**

macOS ships the French and German layouts whether or not they are enabled, so the test asks them directly. It needs a logged-in macOS session.

**Create `tests/KeyLayoutNamesTests.swift`**

```swift
import AppKit
import Carbon.HIToolbox

/// `KeyLayoutNames` against real keyboard layouts, which macOS ships whether or not they are enabled. Needs a
/// logged-in macOS session (the Text Input Sources service).
@main
enum KeyLayoutNamesTests {
    nonisolated(unsafe) static var cases = 0
    nonisolated(unsafe) static var skipped: [String] = []

    static func check(_ ok: Bool, _ message: @autoclosure () -> String,
                      file: StaticString = #file, line: UInt = #line) {
        cases += 1
        precondition(ok, message(), file: file, line: line)
    }

    /// Keys of `layout` and the character each should print.
    @MainActor static func expect(_ id: String, _ keys: [UInt16: String?]) {
        guard let source = KeyLayoutNames.layout(id: id) else { skipped.append(id); return }
        for (code, expected) in keys.sorted(by: { $0.key < $1.key }) {
            let got = KeyLayoutNames.name(for: code, in: source)
            check(got == expected, "\(id): key code \(code) should print \(expected ?? "nothing"), got \(got ?? "nothing")")
        }
    }

    @MainActor static func main() {
        NSApplication.shared.setActivationPolicy(.accessory)
        // US: the names ShortcutLogic.keyCodeToString uses.
        expect("com.apple.keylayout.US", [0: "A", 12: "Q", 13: "W", 6: "Z", 16: "Y", 30: "]", 33: "[", 45: "N", 46: "M",
                                          18: "1", 29: "0", 43: ",", 49: nil, 36: nil, 123: nil, 53: nil, 122: nil])
        // French AZERTY: the key at the US A position is labelled Q, and the other way round.
        expect("com.apple.keylayout.French", [0: "Q", 12: "A", 13: "Z", 6: "W", 41: "M", 46: ",", 49: nil, 123: nil])
        // German QWERTZ: Y and Z swap.
        expect("com.apple.keylayout.German", [6: "Y", 16: "Z", 0: "A", 49: nil])
        // The layout in use answers too (whatever it is, the key at a letter position prints a letter).
        check(KeyLayoutNames.name(for: 0) != nil, "the layout in use names the key at position 0")
        check(KeyLayoutNames.name(for: 49) == nil, "and prints nothing for Space")
        check(KeyLayoutNames.layout(id: "com.apple.keylayout.NoSuchLayout") == nil, "an unknown layout is nil, not a crash")
        check(skipped.count < 3, "at least one of the three layouts must be installed to test anything")
        print("Key layout names: \(cases) cases passed" + (skipped.isEmpty ? "" : " (layouts not installed, skipped: \(skipped.joined(separator: ", ")))"))
    }
}
```

**Create `scripts/test-keynames.sh`**

```bash
#!/usr/bin/env bash
# The names of keys in real keyboard layouts (US, French AZERTY, German QWERTZ). Needs a logged-in macOS
# session, like the app; it is not a CI step.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-keynames.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
swiftc -swift-version 6 NotchBuddy/Sources/App/KeyLayoutNames.swift tests/KeyLayoutNamesTests.swift \
    -o "$TEST_DIR/keyname-tests"
"$TEST_DIR/keyname-tests"
```

- [ ] **Step 2: Run the test and see it fail**

Run: `chmod +x scripts/test-keynames.sh && bash scripts/test-keynames.sh`
Expected: FAIL, `error opening input file 'NotchBuddy/Sources/App/KeyLayoutNames.swift' (No such file or directory)`.

- [ ] **Step 3: Write the key names**

**Create `NotchBuddy/Sources/App/KeyLayoutNames.swift`**

```swift
import AppKit
import Carbon.HIToolbox

/// The character printed on a key in a keyboard layout. Carbon hot keys are physical key positions: the key labelled
/// A on a French AZERTY keyboard is virtual key code 12, which the US layout calls Q. Settings shows what is printed
/// on the key the person has to press, so it asks the layout in use.
enum KeyLayoutNames {
    /// The key's character in the layout in use (upper case), nil for a key that prints nothing (arrows, Space, F1).
    @MainActor static func name(for keyCode: UInt16) -> String? {
        guard let source = TISCopyCurrentASCIICapableKeyboardLayoutInputSource()?.takeRetainedValue() else { return nil }
        return name(for: keyCode, in: source)
    }

    /// The same for one layout, such as `layout(id: "com.apple.keylayout.French")`.
    @MainActor static func name(for keyCode: UInt16, in source: TISInputSource) -> String? {
        guard let property = TISGetInputSourceProperty(source, kTISPropertyUnicodeKeyLayoutData) else { return nil }
        let data = Unmanaged<CFData>.fromOpaque(property).takeUnretainedValue() as Data
        return data.withUnsafeBytes { raw -> String? in
            guard let layout = raw.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else { return nil }
            var deadKeys: UInt32 = 0
            var length = 0
            var chars = [UniChar](repeating: 0, count: 4)
            let status = UCKeyTranslate(layout, keyCode, UInt16(kUCKeyActionDisplay), 0, UInt32(LMGetKbdType()),
                                        OptionBits(kUCKeyTranslateNoDeadKeysBit), &deadKeys, chars.count, &length, &chars)
            guard status == noErr, length > 0 else { return nil }
            let name = String(utf16CodeUnits: chars, count: length).uppercased()
            let printable = name.unicodeScalars.allSatisfy {
                !CharacterSet.controlCharacters.contains($0) && !CharacterSet.whitespaces.contains($0)
            }
            return printable ? name : nil
        }
    }

    /// An installed keyboard layout by its input-source ID, whether or not it is enabled.
    @MainActor static func layout(id: String) -> TISInputSource? {
        let filter = [kTISPropertyInputSourceID as String: id] as CFDictionary
        guard let list = TISCreateInputSourceList(filter, true)?.takeRetainedValue() as? [TISInputSource] else { return nil }
        return list.first
    }
}
```

- [ ] **Step 4: Run the test and see it pass**

Run: `bash scripts/test-keynames.sh`
Expected: PASS, `Key layout names: 33 cases passed`. If it names layouts as "not installed, skipped", they are missing from this Mac: at least one of the three must be there.

- [ ] **Step 5: Write the pane**

It follows Settings' own pattern: `GroupBox` with a title, a small grey caption, rows at 10 pt spacing, `Toggle` checkboxes, small bordered buttons, and the orange caption the Active pills section already uses for a warning. Nothing is saved from `onChange`: a value is written when the person records or switches it, so opening the pane never writes defaults. Under the row of a shortcut that is off at first (the chat and the terminal) a small grey note says why, while it is off. "Turn all on" calls `ShortcutLogic.turnAllOn` with `HotKeyCenter` behind it, lets go of any shortcut it put back off, shows the tag of a shortcut it left off, names them in an orange "Left off: …" line and beeps once, as the recorder does for a refused combination.

**Create `NotchBuddy/Sources/App/ShortcutsSettingsView.swift`**

```swift
import SwiftUI
import AppKit

/// Settings → Shortcuts: the global shortcuts (a switch and a key each) and a read-only list of the island's own.
struct ShortcutsSettingsView: View {
    @State private var enabled: [ShortcutAction: Bool] = [:]
    @State private var specs: [ShortcutAction: ShortcutSpec] = [:]
    /// Shortcuts macOS refused to register: another app already has that combination.
    @State private var takenElsewhere: Set<ShortcutAction> = []
    /// Two of NotchMeow's own shortcuts on one combination.
    @State private var duplicates: Set<ShortcutAction> = []
    /// What "Turn all on" left off, and why.
    @State private var leftOff: [ShortcutLogic.TurnOnResult] = []

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            globalGroup
            islandGroup
        }
        .onAppear { reload() }
    }

    // MARK: Global shortcuts

    private var globalGroup: some View {
        GroupBox("Global shortcuts") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Work from any app. Use ⌘ or ⌃ with another modifier.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                ForEach(ShortcutLogic.available(), id: \.self) { action in
                    row(action)
                }
                HStack {
                    Spacer()
                    Button("Turn all on") { turnAllOn() }
                        .controlSize(.small)
                    Button("Reset to defaults") { resetAll() }
                        .controlSize(.small)
                }
                if let summary = ShortcutLogic.turnOnSummary(leftOff) {
                    Text(summary)
                        .font(.system(size: 11))
                        .foregroundColor(.orange)
                }
            }
            .padding(6)
        }
    }

    private func row(_ action: ShortcutAction) -> some View {
        let isOn = enabled[action] ?? action.enabledByDefault
        let fallback = ShortcutLogic.defaults[action]!
        return VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 8) {
                Toggle(action.displayName, isOn: Binding(
                    get: { isOn },
                    set: { setEnabled($0, for: action) }
                ))
                Spacer(minLength: 8)
                ShortcutRecorderButton(
                    flags: Binding(
                        get: { (specs[action] ?? fallback).nsFlags },
                        set: { specs[action, default: fallback].nsFlags = $0 }
                    ),
                    code: Binding(
                        get: { (specs[action] ?? fallback).keyCode },
                        set: { specs[action, default: fallback].keyCode = $0 }
                    ),
                    onRecorded: { commit(action) }
                )
                .disabled(!isOn)
                .opacity(isOn ? 1 : 0.5)
                conflictTag(for: action)
            }
            // Why a shortcut starts off, while it is off
            if !isOn, let note = action.offAtFirstNote {
                Text(note)
                    .font(.system(size: 10))
                    .foregroundColor(.secondary)
            }
        }
    }

    /// "Duplicate" wins over "In use elsewhere" on a row that has both. A shortcut that "Turn all on" left off keeps
    /// its tag until it is changed.
    @ViewBuilder
    private func conflictTag(for action: ShortcutAction) -> some View {
        let refusal = leftOff.first { $0.action == action }?.reason
        if duplicates.contains(action) {
            tag("Duplicate", color: .red)
        } else if case .duplicate = refusal {
            tag("Duplicate", color: .red)
        } else if takenElsewhere.contains(action) {
            tag("In use elsewhere", color: .orange)
        } else if case .taken = refusal {
            tag("In use elsewhere", color: .orange)
        }
    }

    private func tag(_ text: String, color: Color) -> some View {
        Text(text)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(color)
            .padding(.horizontal, 6)
            .padding(.vertical, 2)
            .background(color.opacity(0.12))
            .clipShape(Capsule())
    }

    // MARK: The island's own shortcuts

    private var islandGroup: some View {
        GroupBox("In the island") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Work while the island has the keyboard. Opening it with a shortcut gives it the keyboard until you close it. In the chat, ⌘ with an arrow key still moves the cursor.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                ForEach(Array(ShortcutLogic.islandShortcuts.enumerated()), id: \.offset) { _, shortcut in
                    HStack(spacing: 10) {
                        Text(shortcut.key)
                            .font(.system(size: 11, design: .monospaced))
                            .frame(width: 90, alignment: .leading)
                        Text(shortcut.description)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                        Spacer()
                    }
                }
            }
            .padding(6)
        }
    }

    // MARK: Changes

    private func reload() {
        for action in ShortcutLogic.available() {
            enabled[action] = ShortcutLogic.isEnabled(action)
            specs[action] = ShortcutLogic.hotKey(for: action)
        }
        leftOff = []
        refreshConflicts()
    }

    private func setEnabled(_ on: Bool, for action: ShortcutAction) {
        enabled[action] = on
        leftOff.removeAll { $0.action == action }
        ShortcutLogic.setEnabled(on, for: action)
        HotKeyCenter.shared.reregister(action)
        refreshConflicts()
    }

    /// A combination was recorded for `action`: keep it and register it.
    private func commit(_ action: ShortcutAction) {
        guard let spec = specs[action] else { return }
        leftOff.removeAll { $0.action == action }
        ShortcutLogic.save(spec, for: action)
        HotKeyCenter.shared.reregister(action)
        refreshConflicts()
    }

    private func resetAll() {
        for action in ShortcutLogic.available() { ShortcutLogic.resetToDefault(action) }
        HotKeyCenter.shared.registerAll()
        reload()
    }

    /// Turns on every shortcut whose combination is free. One that macOS refuses (another app has it) or that
    /// another NotchMeow shortcut already has stays off, and is reported, with a beep like a refused recording.
    private func turnAllOn() {
        let refused = ShortcutLogic.turnAllOn { action in
            HotKeyCenter.shared.reregister(action)
            return !HotKeyCenter.shared.conflicts.contains(action)
        }
        for result in refused { HotKeyCenter.shared.reregister(result.action) }   // off again: let go of it
        reload()
        leftOff = refused
        if !refused.isEmpty { NSSound.beep() }
    }

    private func refreshConflicts() {
        takenElsewhere = HotKeyCenter.shared.conflicts
        duplicates = ShortcutLogic.duplicates(in: ShortcutLogic.activeSpecs())
    }
}
```

- [ ] **Step 6: Add the sidebar row, the routing, and fix the recorder**

The recorder keeps its look. It now refuses a combination that is not `isUsableGlobal` (with a beep; `ShortcutLogic.recorderKey` decides), ⎋ cancels, one recorder listens at a time, the monitor is removed when the row goes, `onRecorded` runs once after both bindings are set, and its label names the key as the layout in use prints it (`[`, `]`, arrows and digits showed "·" before).

**Edit `NotchBuddy/Sources/App/SettingsView.swift`** — replace:

```swift
                        SettingsSidebarRow(title: "Integrations", icon: "puzzlepiece.extension.fill",        color: "#7C5CFF").tag("integrations")
```

with:

```swift
                        SettingsSidebarRow(title: "Integrations", icon: "puzzlepiece.extension.fill",        color: "#7C5CFF").tag("integrations")
                        SettingsSidebarRow(title: "Shortcuts",    icon: "keyboard.fill",                     color: "#2FB5A6").tag("shortcuts")
```

**Edit `NotchBuddy/Sources/App/SettingsView.swift`**, and replace:

```swift
        case "integrations": return "Integrations"
        default:             return "General"
```

with:

```swift
        case "integrations": return "Integrations"
        case "shortcuts":    return "Shortcuts"
        default:             return "General"
```

**Edit `NotchBuddy/Sources/App/SettingsView.swift`**, and replace:

```swift
        case "integrations": integrationsSection
        default:             generalSection
```

with:

```swift
        case "integrations": integrationsSection
        case "shortcuts":    ShortcutsSettingsView()
        default:             generalSection
```

**Edit `NotchBuddy/Sources/App/SettingsView.swift`**, and replace:

```swift
struct ShortcutRecorderButton: View {
    @Binding var flags: UInt
    @Binding var code: UInt16
    @State private var isRecording = false

    var body: some View {
        Button {
            guard !isRecording else { return }
            isRecording = true
            var token: Any?
            token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let mods = event.modifierFlags.intersection([.command, .control, .option, .shift])
                guard !mods.isEmpty else { return event }
                DispatchQueue.main.async {
                    self.flags = mods.rawValue
                    self.code = event.keyCode
                    self.isRecording = false
                    if let t = token { NSEvent.removeMonitor(t) }
                }
                return nil
            }
        } label: {
```

with:

```swift
extension Notification.Name {
    /// A recorder started listening: the other recorders stop, so one key press is recorded once.
    static let shortcutRecordingStarted = Notification.Name("notchBuddy.shortcutRecordingStarted")
}

struct ShortcutRecorderButton: View {
    @Binding var flags: UInt
    @Binding var code: UInt16
    /// Runs once after a combination was recorded, when both bindings already hold it.
    var onRecorded: (() -> Void)? = nil
    @State private var isRecording = false
    @State private var token: Any?
    @State private var recorderID = UUID()

    var body: some View {
        Button {
            guard !isRecording else { return }
            NotificationCenter.default.post(name: .shortcutRecordingStarted, object: recorderID)
            isRecording = true
            token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
                let keyCode = event.keyCode
                let mods = event.modifierFlags.intersection([.command, .control, .option, .shift]).rawValue
                let consumed = MainActor.assumeIsolated { self.record(keyCode: keyCode, mods: mods) }
                return consumed ? nil : event
            }
        } label: {
```

**Edit `NotchBuddy/Sources/App/SettingsView.swift`**, and replace:

```swift
        .buttonStyle(.plain)
    }

    private var shortcutLabel: String {
        let f = NSEvent.ModifierFlags(rawValue: flags)
        var s = ""
        if f.contains(.control) { s += "⌃" }
        if f.contains(.option)  { s += "⌥" }
        if f.contains(.shift)   { s += "⇧" }
        if f.contains(.command) { s += "⌘" }
        s += keyChar(code)
        return s.isEmpty ? "None" : s
    }

    private func keyChar(_ c: UInt16) -> String {
        let map: [UInt16: String] = [
            0:"A", 1:"S", 2:"D", 3:"F", 4:"H", 5:"G", 6:"Z", 7:"X", 8:"C", 9:"V",
            11:"B", 12:"Q", 13:"W", 14:"E", 15:"R", 16:"Y", 17:"T", 31:"O", 32:"U",
            34:"I", 37:"L", 38:"J", 40:"K", 45:"N", 46:"M", 49:"Space", 50:"`", 27:"-"
        ]
        return map[c] ?? "·"
    }
}
```

with:

```swift
        .buttonStyle(.plain)
        .onReceive(NotificationCenter.default.publisher(for: .shortcutRecordingStarted)) { note in
            if (note.object as? UUID) != recorderID { stopRecording() }
        }
        .onDisappear { stopRecording() }
    }

    /// A key press while recording. Returns true when the recorder took it. `ShortcutLogic.recorderKey` decides: ⎋
    /// cancels, a key without a modifier goes on to whoever wanted it, a combination that is not `isUsableGlobal`
    /// is refused with a beep.
    private func record(keyCode: UInt16, mods: UInt) -> Bool {
        switch ShortcutLogic.recorderKey(keyCode: keyCode, nsFlags: mods) {
        case .cancel:
            stopRecording()
            return true
        case .passThrough:
            return false
        case .refuse:
            NSSound.beep()
            return true
        case .record(let spec):
            flags = spec.nsFlags
            code = spec.keyCode
            stopRecording()
            onRecorded?()
            return true
        }
    }

    private func stopRecording() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
        isRecording = false
    }

    private var shortcutLabel: String {
        ShortcutLogic.displayString(for: ShortcutSpec(keyCode: code, nsFlags: flags),
                                    keyName: { KeyLayoutNames.name(for: $0) })
    }
}
```

- [ ] **Step 7: Build, for the app and for the App Store scheme**

Run: `cd NotchBuddy && xcodegen && xcodebuild -scheme NotchBuddy -configuration Debug -derivedDataPath build build CODE_SIGNING_ALLOWED=NO && xcodebuild -scheme NotchMeowAppStore -configuration Debug -derivedDataPath build/store-dd build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO`
Expected: PASS: `** BUILD SUCCEEDED **` twice. (`NotchBuddy/build/` is ignored by git.)

- [ ] **Step 8: Read the diff for what the build cannot say**

Check by reading:
- The pane lists `ShortcutLogic.available()`: in the App Store scheme that is six rows, without the terminal and the front window.
- "Turn all on" (`turnAllOn()` in the pane): the `tryOn` closure registers with `HotKeyCenter.shared.reregister(action)` and answers `!conflicts.contains(action)`; every refused shortcut is `reregister`ed again afterwards, so it is not left registered while its switch is off; `reload()` runs before `leftOff` is set (it clears it); the beep is only for a non-empty result. `leftOff` is cleared for a row when its switch or its keys change, and by `reload()`. The grey note shows only while the row is off.
- `reload()` is the only thing `onAppear` calls, and it writes nothing to UserDefaults.
- A "Duplicate" tag wins over "In use elsewhere" on a row that has both.
- The recorder's `record(keyCode:mods:)` only switches on `ShortcutLogic.recorderKey` (tested in Task 1): `.passThrough` returns `false` so the key goes on, `.cancel` stops, `.refuse` beeps, and `onRecorded` runs only after `flags` and `code` are set; `General → Hotkey` does not pass `onRecorded` (its bindings already register).
- The sidebar row is the last one, after "Integrations"; no existing row, title or section moved.

- [ ] **Step 9: Commit**

```bash
git add NotchBuddy/Sources/App/KeyLayoutNames.swift tests/KeyLayoutNamesTests.swift scripts/test-keynames.sh NotchBuddy/Sources/App/ShortcutsSettingsView.swift NotchBuddy/Sources/App/SettingsView.swift NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -m "feat(shortcuts): Settings → Shortcuts: switch, key and conflicts for each global shortcut, and the island's keys

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Docs, CI and the final checks

Agent: `nm-implementer-light`.

**Files:**
- Modify: `docs/SPEC.md`, `README.md`, `CHANGELOG.md`, `CLAUDE.md`, `.github/workflows/build.yml`

**Interfaces:**
- Consumes: every earlier task; `scripts/test-shortcuts.sh` for CI.
- Produces: §13 of `docs/SPEC.md` (in French), one README line, one changelog entry, one pointer in `CLAUDE.md` (it says the Windows and Linux app has none), one CI step. `scripts/test-hotkeys.sh`, `scripts/test-escape.sh` and `scripts/test-keynames.sh` stay out of CI: they need a window-server session that a CI runner may not have.

- [ ] **Step 1: The spec, §13 (French, like the rest of the file)**

**Edit `docs/SPEC.md`** — replace:

```markdown
- **Hotkey** : raccourci global pour ouvrir le notch.
```

with:

```markdown
- **Hotkey** : raccourci global pour ouvrir ou fermer le notch (le même réglage que `toggleIsland` dans Shortcuts, voir §13).
- **Shortcuts** *(macOS)* : raccourcis globaux (un interrupteur et une touche chacun, avec les conflits signalés) et liste des raccourcis de l'île (voir §13).
```

**Edit `docs/SPEC.md`**, and replace:

```markdown
- La démo (⌃⌥⌘D) se filme d'une traite sans intervention.
```

with:

```markdown
- La démo (⌃⌥⌘D) se filme d'une traite sans intervention.

## 13. Raccourcis clavier (macOS)

Code : `ShortcutLogic.swift` (tables, stockage, validation et touches de l'île ; Foundation seul, testé par `scripts/test-shortcuts.sh`), `HotKeyCenter.swift` (Carbon, testé par `scripts/test-hotkeys.sh`), `EscapeRouting.swift` (testé par `scripts/test-escape.sh`), `KeyLayoutNames.swift` (testé par `scripts/test-keynames.sh`) et `ShortcutsSettingsView.swift`. Les trois derniers tests ont besoin d'une session macOS ouverte et ne sont pas dans la CI. Windows et Linux n'ont pas de raccourcis clavier.

### 13.1 Raccourcis globaux

Enregistrés avec Carbon `RegisterEventHotKey` : ils marchent depuis n'importe quelle app, sans permission (ni Accessibilité ni Surveillance de l'entrée), y compris dans le build App Store. La frappe est consommée : l'app au premier plan ne la reçoit pas. Pour cette raison, une combinaison doit contenir ⌘ ou ⌃ avec au moins un autre modificateur (`ShortcutSpec.isUsableGlobal`). Une touche seule, ⇧ ou ⌥ seuls (majuscules, accents) ou ⌘ ou ⌃ seuls (menu Édition, touches Emacs) seraient volés à toutes les apps.

| Action | Défaut | Clés UserDefaults | Par défaut |
|--------|--------|-------------------|------------|
| Ouvrir ou fermer l'île (`toggleIsland`) | ⇧⌘N | `hotkeyCode`, `hotkeyFlags`, `hotkeyEnabled` (clés historiques du réglage Hotkey) | Désactivé |
| Ouvrir le chat (`openChat`) | ⌃⌥Espace | `shortcut.openChat.keyCode`, `.flags`, `.enabled` | Désactivé : macOS utilise ⌃⌥Espace pour « Select next source in Input menu » |
| Aller à l'alerte (`goToAlert`) | ⌃⌥A | `shortcut.goToAlert.…` | Activé |
| Sauter au terminal (`jumpToTerminal`) | ⌃⌥T | `shortcut.jumpToTerminal.…` | Désactivé : Rectangle utilise ⌃⌥T pour « Last Two Thirds » (hors App Store) |
| Attacher la fenêtre active (`attachFrontWindow`) | ⌃⌥W | `shortcut.attachFrontWindow.…` | Activé (hors App Store) |
| Pastille suivante (`nextPill`) | ⌃⌥] | `shortcut.nextPill.…` | Activé |
| Pastille précédente (`prevPill`) | ⌃⌥[ | `shortcut.prevPill.…` | Activé |
| Couper ou rétablir le son (`muteToggle`) | ⌃⌥M | `shortcut.muteToggle.…` | Activé |

- Cinq raccourcis sont activés au départ (`goToAlert`, `attachFrontWindow`, `nextPill`, `prevPill`, `muteToggle`) ; `toggleIsland` (comme avant), `openChat` et `jumpToTerminal` sont désactivés mais gardent leur combinaison, pour qu'un clic les active (décision du propriétaire, 2026-10-05). Réglages → Shortcuts dit pourquoi sous la ligne tant qu'elle est désactivée (`ShortcutAction.offAtFirstNote`). « Reset to defaults » revient à cet état.
- Une combinaison est une position de touche (code virtuel), pas un caractère : ⌃⌥A est la touche étiquetée A sur un clavier QWERTY américain. Réglages affiche le caractère imprimé sur la touche dans la disposition utilisée (`KeyLayoutNames`, par `UCKeyTranslate`) : sur AZERTY, le défaut ⌃⌥A s'affiche ⌃⌥Q, la touche qu'il faut presser.
- Une valeur stockée qui n'est pas fiable (code de touche hors 0 à 127, moitié manquante, mauvais type, combinaison qui n'est pas `isUsableGlobal`) est remplacée par le défaut : jamais de plantage, jamais de touche volée.
- Si macOS refuse l'enregistrement (une autre app a la combinaison), l'action n'est pas enregistrée et Réglages → Shortcuts affiche « In use elsewhere ». Deux raccourcis de NotchMeow sur la même combinaison : le premier de la liste garde la combinaison, l'autre n'est pas enregistré et les deux affichent « Duplicate ».
- `toggleIsland` ouvre l'île, ou la ferme si elle est ouverte (une approbation en attente la garde ouverte). Les autres actions qui ouvrent l'île la prennent comme fenêtre clé (clavier) jusqu'à sa fermeture : le survol et les alertes ne le font jamais. L'état de l'île (`IslandStateMachine.openedExternally`) est mis à jour comme pour une alerte.
- `goToAlert` ouvre l'approbation ou la question en attente ; sans alerte, émote agacée et son `error`.
- `jumpToTerminal` active le premier terminal ouvert (Terminal, iTerm, kitty, Ghostty), ou lance Terminal, puis ferme l'île ; sans pastille, émote agacée et son `error`.
- `attachFrontWindow` attache la fenêtre qui était au premier plan comme contexte du chat et démarre une nouvelle conversation (le contexte ne part qu'avec le premier message), comme le glisser de la tête.
- `nextPill` et `prevPill` changent de pastille en bouclant et ouvrent l'île si elle est fermée ; ils ne font rien tant qu'une approbation ou une question attend (sa carte reste affichée, avec son agent).
- `muteToggle` coupe ou rétablit les sons (son `tick` et émote).
- Les actions du bureau et de la garde-robe viendront avec leurs sous-projets, ajoutées à la fin de la liste : Carbon identifie une touche par son rang dans `ShortcutAction.allCases`.

### 13.2 Raccourcis de l'île

Un moniteur local `NSEvent` (`IslandWindowController.handleIslandKey`) les traite quand le panneau de l'île est la fenêtre clé : après un raccourci global qui l'ouvre, ou dans le chat. Seul ⌘ sans autre modificateur compte (`ShortcutLogic.islandCommand`). ⌘, est la virgule où que la disposition la mette (`charactersIgnoringModifiers`) ; les autres touches sont des positions, les mêmes sur les dispositions courantes pour O, E, K, P et la rangée de chiffres.

| Raccourci | Action |
|-----------|--------|
| ⌘→ ⌘← | Pastille suivante ou précédente (pas dans le chat : le curseur du champ garde ⌘ et les flèches) |
| ⌘1 … ⌘9 | Pastille n° 1 à 9 |
| ⌘↓ ⌘↑ | Descend ou monte dans la liste de la carte (pas dans le chat) ; la ligne choisie défile dans la vue |
| ⌘O | Ouvre la ligne choisie (liste GitHub) |
| ⌘E | Ouvre ou ferme le dernier diff (vue d'ensemble) |
| ⌘↩ | Envoie le message (chat) |
| ⌘K | Nouvelle conversation (chat) |
| ⌘, | Ouvre les Réglages |
| ⌘P | Épingle ou désépingle l'île |
| ⎋ | Pendant une composition de texte (méthode de saisie, touche morte), ⎋ l'annule et l'île reste. Sinon, une vue qui a le focus et gère ⎋ (`.onExitCommand` : champ « Other… », liste, diff) passe d'abord (`EscapeRouting` la trouve) ; sinon l'île se ferme, sauf si elle est épinglée ou retenue par une approbation |

Les pastilles ne bougent pas tant qu'une approbation ou une question attend. La sélection d'une liste est remise à zéro quand la liste se ferme, change de pastille ou raccourcit.

### 13.3 Réglages

Réglages → Shortcuts (`ShortcutsSettingsView`) : un interrupteur, un `ShortcutRecorderButton` et les étiquettes de conflit par action globale, les boutons « Turn all on » et « Reset to defaults », puis la liste en lecture seule des raccourcis de l'île. « Turn all on » (`ShortcutLogic.turnAllOn`) active chaque raccourci dont la combinaison est libre, dans l'ordre de la liste, en laissant ceux déjà activés. Un raccourci que macOS refuse (une autre app a la combinaison) ou qu'un autre raccourci de NotchMeow a déjà reste désactivé : il garde son étiquette (« In use elsewhere » ou « Duplicate »), une ligne orange « Left off: … » les nomme, et un bip se fait entendre, comme pour un enregistrement refusé. Carbon accepte ⌃⌥Espace et ⌃⌥T même si macOS ou Rectangle les utilisent (vérifié : l'enregistrement réussit) : « Turn all on » ne détecte donc que les combinaisons déjà enregistrées par une autre app, et la note sous la ligne reste la seule alerte pour les autres. L'enregistreur refuse (bip) une combinaison qui n'est pas `isUsableGlobal`, ⎋ l'annule, et un seul enregistreur écoute à la fois. Le bloc Hotkey de General et la ligne « Open or close the island » modifient le même réglage (`AppState.hotkey*` lit et écrit `ShortcutLogic`). Un raccourci déjà enregistré par NotchMeow lui-même ne peut pas être ré-enregistré tel quel : Carbon consomme la frappe avant l'enregistreur.
```

- [ ] **Step 2: The README line, the changelog entry and the pointer in CLAUDE.md**

**Edit `README.md`** — replace:

```markdown
- **Drop a file on the notch** to ask a question about it.
```

with:

```markdown
- **Drop a file on the notch** to ask a question about it.
- **Keyboard shortcuts** *(macOS)*: open the chat, jump to a waiting alert or your terminal, attach the front window, switch pills and mute from any app, and drive the island from the keyboard. Change or turn off each one in Settings → Shortcuts.
```

**Edit `CHANGELOG.md`** — replace:

```markdown
- Dropped files reach every model: text, PDFs, scans and images (read on the Mac for models that can't see images), Word, RTF and HTML, cut to fit small models; the drop card says who will read the file, and follow-up questions stay with the model chosen for File questions
```

with:

```markdown
- Dropped files reach every model: text, PDFs, scans and images (read on the Mac for models that can't see images), Word, RTF and HTML, cut to fit small models; the drop card says who will read the file, and follow-up questions stay with the model chosen for File questions
- Keyboard shortcuts (macOS), ported from Coucou 0.1.7: ⌃⌥A jumps to a waiting permission or question, ⌃⌥W attaches the front window to the chat (GitHub build), ⌃⌥] and ⌃⌥[ switch pills and ⌃⌥M mutes. ⌃⌥Space (open the chat) and ⌃⌥T (bring your terminal forward) are there too but off at first, because macOS and Rectangle already use those combinations. Settings → Shortcuts turns each on or off, changes its keys, flags a combination another app already uses, and has a "Turn all on" button
- In the open island: ⌘→ ⌘← and ⌘1 to ⌘9 switch pills, ⌘↓ ⌘↑ and ⌘O move through a GitHub list, ⌘E opens the diff, ⌘↩ sends and ⌘K starts a new conversation in the chat, ⌘, opens Settings, ⌘P pins the island, and ⎋ closes it
- The island shortcut (⌘⇧N, off by default) now opens and closes the island and needs no permission. A shortcut needs ⌘ or ⌃ plus another modifier, so it can't take plain typing from other apps
```

**Edit `CLAUDE.md`** — replace:

```markdown
- `NotchBuddy/Sources/App/PillCatalog.swift` — single source of truth for all declared pills (workspace tools, agents, AI providers, services). Every pill ID, color, category and subtitle lives here.
```

with:

```markdown
- `NotchBuddy/Sources/App/PillCatalog.swift` — single source of truth for all declared pills (workspace tools, agents, AI providers, services). Every pill ID, color, category and subtitle lives here.
- `NotchBuddy/Sources/App/ShortcutLogic.swift` — every keyboard shortcut on the Mac: the global actions and their defaults, stored values and their validation, the island's own keys. Pure Foundation, tested by `scripts/test-shortcuts.sh`; `HotKeyCenter.swift` registers the global ones with Carbon (`docs/SPEC.md` §13). The Windows and Linux app has none.
```

- [ ] **Step 3: One CI step**

Read the real `.github/workflows/build.yml` first: other branches add steps to the same list. This edit anchors on the "Diff engine tests" step alone, which the cat plans do not touch.

**Edit `.github/workflows/build.yml`** — replace:

```yaml
      - name: Diff engine tests
        run: bash scripts/test-diff-engine.sh
```

with:

```yaml
      - name: Diff engine tests
        run: bash scripts/test-diff-engine.sh

      - name: Keyboard shortcut logic
        run: bash scripts/test-shortcuts.sh
```

- [ ] **Step 4: Run every test, the way CI does**

Run: `export NM_LOG_DIR="$(mktemp -d)"; bash scripts/check-test-logs.sh && for s in scripts/test-*.sh; do bash "$s" > "$NM_LOG_DIR/out.txt" 2>&1 && echo "ok   $s" || { echo "FAIL $s"; tail -5 "$NM_LOG_DIR/out.txt"; }; done`
Expected: PASS: `✓ every log-writing test script sets NM_LOG_DIR`, then `ok` for every script, `scripts/test-shortcuts.sh`, `scripts/test-hotkeys.sh`, `scripts/test-escape.sh` and `scripts/test-keynames.sh` among them, and no `FAIL`.

- [ ] **Step 5: Build as CI does, and as the App Store does**

Run: `cd NotchBuddy && xcodegen && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchMeowAppStore -configuration Debug -derivedDataPath NotchBuddy/build/store-dd build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Release -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO && bash scripts/check-app-binary.sh NotchBuddy/build/Build/Products/Release/NotchMeow.app release`
Expected: PASS: three times `** BUILD SUCCEEDED **`, then the check prints a `✓ FoundationModels is weak-linked` line and `✓ No AI base-URL override in this Release build`. (`NotchBuddy/build/` is ignored by git.)

- [ ] **Step 6: Check the log did not grow and nothing stray is staged**

Run: `stat -f "%z bytes" ~/Library/Logs/NotchMeow/nm.log; git status --short`
Expected: the log size is what it was before Task 1 (note it in Task 1's first step), and `git status --short` lists only this task's five files (and, until the commit, nothing else).

- [ ] **Step 7: Commit**

```bash
git add docs/SPEC.md README.md CHANGELOG.md CLAUDE.md .github/workflows/build.yml
git commit -m "docs(shortcuts): spec section 13, README, changelog and a CI step for the shortcut logic

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

- [ ] **Step 8: Final review**

Dispatch `nm-reviewer-deep` on `git diff notchmeow/rebrand...shortcuts/mac`. Give it this plan, the Review Focus and the Port notes. It should read for: any `Coucou`, `Mochi` or `COUC` in what this branch adds; a timer or poll added anywhere; a way for a shortcut to answer an approval or a question, or for a pill shortcut or ⎋ to move or close one that waits; a global shortcut that can be set to a combination without ⌘ or ⌃, or to fewer than two modifiers; a `UInt16(` or `UInt(` conversion of a stored value; a changed label, font, colour or spacing in an existing view; a `windows/` file; and that the General → Hotkey box and the Shortcuts pane read and write the same keys. Fix what it finds before the owner sees the branch.

---

## Windows and Linux

Upstream's shortcuts are macOS only, and `windows/` has no global shortcut code today (a search for `shortcut`, `hotkey` and `global-shortcut` in `windows/` finds nothing), so there is nothing for the Mac to catch up with and this plan adds nothing there.

A later plan for Windows and Linux is worth having, small and separate, not part of this one:
- Tauri 2 has an official global-shortcut plugin (`tauri-plugin-global-shortcut`), so the open-the-chat, next and previous pill and mute shortcuts are within reach on Windows. The "attach the front window" shortcut would follow the existing window-context code of the Windows app.
- Linux is the hard part: under Wayland an app cannot register a global shortcut without the desktop's shortcuts portal, so a Linux version may have to be X11-only or leave it out.
- The pure parts port as they are: the default table, the "usable global combination" rule (⌘ or ⌃ with a second modifier, which on Windows is Ctrl or Win with a second modifier), the validation of stored values, the island's key map and the pill choice. If both apps should stay in step, put those tables in a shared fixture under `tests/fixtures/` the way the cat contract is, and test both apps against it. That is a decision for the owner; this plan keeps the tables in Swift.

---

## Self-review

Run against the spec and the brief after writing.

**1. Spec coverage.**
- "Keyboard shortcuts (upstream 0.1.7, #205), after E1 merges": Tasks 1 to 4 port the global shortcuts, the island shortcuts and the Settings → Shortcuts pane. E1 is in the base.
- "The desktop and wardrobe actions arrive with H and I": left out (Port notes row 1); the enum order rule and `docs/SPEC.md` §13.1 say where they are added.
- The owner's defaults (2026-10-05): the on/off set and the kept combinations in `ShortcutAction.enabledByDefault` (Task 1, pinned by "defaults on and off"), the note under the chat and terminal rows (`offAtFirstNote`, Task 1, shown by Task 4's pane), the "Turn all on" button (`ShortcutLogic.turnAllOn` and `turnOnSummary`, Task 1, tested against a taken combination and a duplicate; Task 2 runs it on the real Carbon wrapper; Task 4's pane), and the question removed from "Open questions" with the decision recorded in the Port notes.
- Mac-only upstream, Mac gets it, a Windows and Linux plan worth having later but not added: "Windows and Linux".
- New UI follows the Settings style and existing views keep their look: Task 4 (`GroupBox`, caption, checkbox rows, an extra sidebar row) and the Global Constraints.
- Renames: `NMEW`, no `Coucou` or `Mochi` (Task 2 step 10 greps for it); bundle IDs and the legacy defaults keys kept (Task 1 "legacy hotkey keys").
- Tests with the repo's harness: four `scripts/test-*.sh` programs, one in CI; the Debug build, the App Store build and the Release build with `check-app-binary.sh` are in Task 5.
- Agents and skills lines, the three-step session start with its setup prompt and the brief, and the model recommendation: "Execution".
- Files touched and the overlap with the cat plans, with how to avoid conflicts: "File Structure" and its overlap table.

**2. Placeholder scan.** No `TBD`, no "similar to Task N", no step that describes code without showing it. Every file is given whole and every change to an existing file is a replace with exact text.

**3. Type consistency.** Names across tasks: `ShortcutAction` (eight cases, same order in the logic, the tests, the Carbon wrapper and the pane), `ShortcutSpec.isUsableGlobal`, `ShortcutStore` and `ShortcutLogic.activeSpecs(appStore:in:)` (used by `HotKeyCenter`, through its `store`, and by the pane), `ShortcutLogic.turnAllOn(appStore:in:tryOn:)`, `TurnOnResult` and `turnOnSummary(_:)` (Task 1, used by Task 2's test and by the pane, whose `leftOff` holds the results), `ShortcutAction.offAtFirstNote` (Task 1, used by the pane), `pillID(from:current:delta:decisionWaiting:)` and `pillID(number:in:decisionWaiting:)` (Task 1, used by `cyclePill` and the island key map in Tasks 2 and 3), `decisionWaiting` (Task 2, used by Task 3), `cardSelection` and `cardItemCount` (Task 3, in `AppState`, the controller and `GitHubDetailView`), `EscapeRouting.consumer(in:)` and `isComposing(in:)` (Task 3, used by `handleEscape` and `handleIslandKey`), `ShortcutLogic.islandCommand(keyCode:nsFlags:characters:in:)` (Task 1, called by `handleIslandKey` with `charactersIgnoringModifiers`), `ShortcutLogic.displayString(for:keyName:)` and `KeyLayoutNames.name(for:)` (Task 1 and Task 4, used together by the recorder's label), `ShortcutLogic.recorderKey(keyCode:nsFlags:)` (Task 1, used by the recorder), `ShortcutRecorderButton(flags:code:onRecorded:)` (Task 4, used by the pane and, without `onRecorded`, by General), the notification names (Task 3 defines four, Task 4 one, each used where it is defined).

**4. Review Focus.** Each of the five lines has its test in the task named there (1: Task 3; 2 and 3: Task 1 "island keys in the chat" and "pills"; 4: Task 1 "display strings" and "island keys", and Task 4's `test-keynames.sh`; 5: Task 1 "which combinations may be global", "recorder keys", "stored values that cannot be trusted" and "legacy hotkey keys"), and the parts a test cannot reach are manual checks 1, 2, 6, 7 and 9.

**Things a test here cannot show, decided on evidence while planning.** Probes in throwaway programs (never the app) showed that `NSPanel` and `NSWindow` respond to `cancelOperation:` and `NSApp.sendAction` returns true with nothing focused; that a focused `.onExitCommand` view puts a responder that answers it into the chain below the panel and a plain text field does not; that Carbon accepts a second registration of one combination from the same process; that `UCKeyTranslate` names the keys of the French and German layouts the way their keyboards print them; and that a `ScrollViewReader` over rows given `.id(idx)` scrolls the selected row into a 60 pt window (row 5 puts the window at y 60, row 7 at 100, row 0 back at 0). Tasks 2, 3 and 4 pin the first four in tests; the scroll is manual check 5.

**Dry run.** Replayed on 2026-10-05 in a throwaway clone of `notchmeow/rebrand`, task by task, by a script that reads this file the way an implementer would (each full file written, each replace matched exactly once): the tests passed (`496`, `19`, `13` and `33` cases), the Debug, App Store Debug and Release builds succeeded, `check-app-binary.sh` passed, every other `scripts/test-*.sh` still passed, `nm.log` did not grow, and the replayed tree equalled the author's tree byte for byte.

## Open questions for the owner

1. **Who has the keyboard.** Opening the island with ⌘⇧N, ⌃⌥Space, ⌃⌥A or ⌃⌥W makes it the key window until it closes, as upstream does, so ⎋ and the island keys work. The cost: someone who peeks with ⌘⇧N and goes on typing in their editor types into the island until they close it. ⌃⌥] and ⌃⌥[ do not take the keyboard. Keep it, or let ⌘⇧N peek without it?
2. **⎋ in the chat** now closes the island (it did nothing before, when the chat was the key window), and an unsent draft in the chat field goes with it. OK?
3. **General → Hotkey wording.** The caption "presses this → island opens" is left as it is (existing views stay as they are), but the shortcut now opens and closes the island, as upstream's does.
4. **⌘P** pins the island with no sign that it did. Upstream is the same. A small indicator is a change to an existing view, so it is not here.
5. **Re-recording a combination NotchMeow already holds** is not possible (Carbon eats the key press before the recorder sees it), so to swap two shortcuts, change one first. Suspending the hot keys while a row records would fix it, at the price of more state; not done.
6. **A stored Hotkey that is only ⇧ or ⌥ plus a key** (the old recorder allowed it) now falls back to ⌘⇧N. It would otherwise take that letter from every app.
7. **`test-hotkeys.sh`, `test-escape.sh` and `test-keynames.sh` are not CI steps.** They need a window-server session. Add them if the runner has one.
8. **Defaults are key positions.** On an AZERTY keyboard the default ⌃⌥A is the key labelled Q, ⌃⌥W is labelled Z, ⌃⌥M is the comma key and ⌃⌥] ⌃⌥[ are `$` and `^`, so the mnemonics (A for alert, T for terminal) break for people who do not type on a US layout, though the pane always shows the right key. Keep position-based defaults, or choose them by character at first launch (which makes a stored shortcut depend on the layout that was in use)?
9. **Windows and Linux:** a small later plan, as described above?
