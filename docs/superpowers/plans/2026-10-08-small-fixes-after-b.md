# Small Fixes after B Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Eight small fixes the owner approved after sub-project B was merged: the Windows personality sliders on one line; the three layout defects of the Mac's Claude plan card; an agent's config file that is a symbolic link (Mac) staying a link and keeping its permissions; the docs' stale words about the cats and the changelog lines for A and B; and four of B's deferred minors (an empty kitten layer that keeps drawing, the agents' list that does not follow the events, an unused parameter with a pass-through field and a duplicate source pin, a doc block in the wrong place).

**Architecture:** No new architecture: each fix is the smallest change in the file that holds the cause, which every task confirms in the code first. The two fixes that change a shipping view are measured and then drawn before and after without launching an app (the Vite dev server with the headless `playwright-cli` for Windows, `scripts/render-plan-card.sh` for the Mac card), and the owner looks at the pictures at a checkpoint. The Mac card's numbers stay in `CatIslandLayout`, and their tests measure the text with AppKit instead of guessing. The config write is one Foundation-only file (`ConfigFileWrite`) with a test that works only in a temp folder. The two minors with a rule (when a kitten layer may stop, when an event reorders the agents' list) are pure functions with tests, and the views call them.

**Tech Stack:** Swift 6, SwiftUI and AppKit (AppKit only to measure text in a test), `swiftc` test programs, XcodeGen, TypeScript and CSS (Vite 6, Node 22 `node --test`), `playwright-cli` (headless Chromium, for the Settings window), Python 3 (the edit scripts), Bash. Rust runs once, through `windows/scripts/cargo-linux.sh`, to confirm that the Windows twin is already right.

**Spec:** none: the owner's list of 2026-10-08, which the main session wrote into the task. The deferred minors come from the B-mac ledger (`/path/to/notchmeow/.claude/archive/sdd/b-mac-display-kittens/progress.md`: the final review's F3 and F4, "Fix A" and "Fix B", "Fix D"), which is read-only background and is not in a worktree. Format and conventions are the B plans' (`docs/superpowers/plans/2026-10-08-b-mac-display-kittens.md` and `2026-10-08-b-tauri-display-kittens.md`).

**Base:** a new branch `fixes/after-b` in a git worktree, from `notchmeow/rebrand` at `b13eed1` (sub-project B merged on both apps) or later: `git merge-base --is-ancestor b13eed1 HEAD` must succeed. This plan edits no contract file: not `design/prototype/cat-core.js`, not `tests/fixtures/`, not `scripts/gen-cat-fixtures.mjs`, not `docs/CAT-CONTRACT.md`.

## Global Constraints

Every task's requirements include this section.

- **The owner approved this batch, and the views it names may change; no other shipping view may.** The changes to a shipping view are exactly these: the Windows Settings → Cat personality rows (Energy to Mischief: Task 1), and the Mac Claude plan card in both its layouts, the shipping one and Two cats mode's stacked one (Task 2). Nothing else is restyled, in any task. **Every fix that changes a shipping view has an owner checkpoint with before and after pictures** drawn without launching an app: Checkpoint 1 (Task 3) comes after the two visual fixes, and Checkpoint 2 (Task 11) at the end.
- **Never overwrite `~/.claude/settings.json` without a dated backup, a merge, a diff shown to the user and the user's confirmation** (CLAUDE.md). Task 4 changes how the bytes are written and where the backup is copied from, not that flow: the preview still builds the data first, the write still happens only after the confirm, the dated backup still comes first, and a test pins each of those in the source.
- **Frozen values stay frozen:** cat IDs, display mode IDs (`one`, `perAgent`, `two`), collar styles, pill IDs, the UserDefaults keys (`cat.*`), and the contract strings (`nm-hook`, `nm.sock`, `notchmeow-hook`, `nm_kind`, `nm_agent`). No test or script of this plan writes to `UserDefaults.standard` or to a suite.
- **Swift 6, SwiftUI and AppKit, no third-party dependency.** `ConfigFileWrite` is Foundation only and has no build condition. The App Store build keeps compiling and behaves as before: its two direct writes of `settings.json` (its sandbox grant is a folder the user picked, and a link's target may be outside it) are left as they are, and a test pins that count.
- **0 % CPU when the island is hidden, and no new timer or polling anywhere.** Task 6 makes an empty kitten layer stop asking for frames (it asks for none when hidden already); it adds no timer, and the existing pin that no kitten file contains `Timer`, `asyncAfter`, `DispatchWorkItem` or `Task {` stays true.
- **Fixtures and the contract decide, and are not edited here.** `scripts/test-cat-contract.sh` reads `# tests 231` before and after, and `node scripts/check-fixtures-additive.mjs b13eed1` says the fixtures did not change.
- **Never edit `NotchBuddy.xcodeproj` by hand.** Task 4 adds one Swift file: it runs `cd NotchBuddy && xcodegen` and commits the regenerated `project.pbxproj`.
- **Names:** the names Coucou and Mochi are reserved and are not NotchMeow's identity. Credit to the original project in `LICENSE`, `LICENSE-ASSETS.md`, the README's credits and the upstream history in `CHANGELOG.md` stays; `mocha` is a coat. `bash scripts/check-no-leftovers.sh` stays green.
- **Commits** are local only, never pushed, and only the files each task's commit step lists. Each message ends with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`, or `Claude Haiku 4.5` for a task `nm-implementer-light` ran.
- **SUBAGENT RULES (put this block in every subagent brief):**
  1. Never launch, quit or replace any NotchMeow app, and never start the Tauri app (`npm run tauri dev`, a built `notchmeow.exe`). A Debug, Release or App Store **build** is only built. The scripts that draw a PNG (`scripts/render-*.sh`) are not the app and may run. Serving the Windows front end with `npx --no-install vite` and looking at it in the headless `playwright-cli` browser is allowed, and only that.
  2. Install nothing and download nothing: `npx --no-install` only, never `npm install`, `npm ci`, `npm run build`, `npm run dev` or `npm run tauri`, and never build or pull a Docker image.
  3. Rust only through `windows/scripts/cargo-linux.sh`, with this plan's own `--target-dir /repo/windows/target/fixes-after-b`. Check the image first (`docker image inspect notchmeow-linux-dev`): if it is missing or the daemon is down, stop and say so, because the script would build it.
  4. Use `trash`, never `rm -rf`, for anything you delete by hand, and unique scratch names under `${TMPDIR:-/tmp}`: this plan uses `fixes-after-b-shots` (Windows), `fixes-after-b-1` (the plan card), `fixes-after-b-base` and `fixes-after-b-final` (the sheets). (The test scripts clean their own `mktemp` folders with `rm -rf` in a `trap`, as every `scripts/test-*.sh` does: that is the repo's convention, not a command an agent runs.) Stop every server you start by the process ID saved when it started (`kill "$(cat "$SHOTS/vite.pid")"`), never by port or by name, and close only the browser sessions you opened, by their names (`playwright-cli -s=<name> close`), never `close-all`.
  5. Never run the real `claude` binary, never read Claude Code's tokens or credentials, and never sign in anywhere.
  6. Never write to the real `~/.claude`, `~/.gemini`, `~/.codex`, `~/Library/Logs/NotchMeow/` or the app's preferences. Every test of this plan runs through its `scripts/test-*.sh`, which set `NM_LOG_DIR` (and `NM_CONFIG_TEST_DIR` for Task 4) to a temp folder; a test never uses `UserDefaults.standard` or a suite.
  7. Never edit `design/prototype/cat-core.js`, anything in `tests/fixtures/`, `scripts/gen-cat-fixtures.mjs` or `docs/CAT-CONTRACT.md`.
  8. Never restyle a view beyond what a task says, and never rename a frozen ID or a contract string.
  9. Write no Coucou or Mochi name as NotchMeow's identity anywhere (credit in licence and attribution text, and the upstream history in the changelog, stay).
  10. Never push. Commit only in a task's commit step. Subagents run on Sonnet 5.5 at most (Haiku 4.5 for the light tasks), never Opus or Fable.
  11. The SDD skill's plugin scripts (`sdd-workspace`, `task-brief`, `review-package`) are refused by the auto-mode permission check here: keep the ledger at `.superpowers/sdd/2026-10-08-small-fixes-after-b/progress.md`, write each task brief with the Write tool just before dispatch, and write review diffs with `git diff`.
  12. If a command is denied by a permission prompt, stop and report it. Do not look for a workaround.

## Review Focus

The owner's list says what each fix must do. It is silent on these inputs and conditions, and each would bite a person first, most likely first. Each line names the test that pins it.

1. **A config file that is a link in a shape other than the plain one.** A relative link, a chain of two, `~/.claude` itself a link to another folder with a relative link inside it, a link to a file that is not there yet, a loop of links, a 0600 file. Expected: the link stays a link, the file at the end changes and keeps its permissions, the dated backup is a copy of its text and still holds the old text after the write, a link to nothing makes the file where it points, and a loop ends. Tests: Task 4 (`ConfigFileWriteTests`: eight scenarios, and the source pins that the five writers use it).
2. **The plan card's longest texts.** "100%" in the weekly row, the reset label "Resetting…" (the longest), "59 min ago" (the longest ordinary subtitle) in Two cats mode's 168 pt, and "Waiting for a Claude Code reply" (the longest of all) in both layouts. Expected: "100%" on one line, nothing past the card's edge, the title never squeezed out, the subtitle cut instead. Tests: Task 2 (measured widths in `CatAgentListTests`, the pins in `CatWiringTests`, the five pictures and their regional pixel counts).
3. **The slider rows at every width the window can have, scrollbar included.** 560 and 460 px, and 543 and 443 when a 17 px scrollbar takes its room; the longest labels (`well-behaved`, `troublemaker`, `independent`); the other Settings rows. Expected: six rows on one line, the six sliders lined up, nothing clipped or overflowing, and no other row a pixel different. Tests: Task 1 (the measured rows at four widths, the other rows' sizes before and after, the source pins).
4. **A kitten layer that went quiet and has to wake.** The last kitten leaves while nothing else happens; a kitten starts afterwards; the focus moves to a pill that has kittens; the island is hidden and shown again; a time that is not a number. Expected: the layer stops asking for frames once nothing is left to draw and starts again at once when the kittens or its pills change, and never freezes a kitten on screen. Tests: Task 6 (`CatKittens.mayStop`: seven rows, and the pins on the layer).
5. **Several agents sending events while Settings is open.** An event from the agent that is already the most recent, from the second one, from a third that never sent one. Expected: Settings' list reorders exactly when the order changes, and an agent that was already first does not make every view redraw. Tests: Task 7 (`touchReorders` against `CatAgentList.rows` for each of three agents).

---

## What the investigation found

Each fix was checked in the code first, and the verdict is in the first step of its task.

| # | The owner's item | Verdict | Where |
|---|---|---|---|
| 1 | Windows Settings → Cat, the sliders' high labels wrap | **Confirmed.** `.row` has `flex-wrap: wrap`, and a slider row needs 132 + 84 + 140 + 84 + 3 × 12 = 476 px while a 560 px window leaves 474 (560 − 2 × 24 − 2 × 1 − 2 × 18), less a scrollbar's 17 and, at the 460 px minimum, 374. Measured: 0 of 6 rows on one line at 560, 543, 460 and 443. The six rows become a grid of their own (`.row.cat-trait`). | Task 1 |
| 2 | The Mac plan card: "100%" wraps, the waiting title is squeezed out, the stacked subtitle can truncate | **All three confirmed, with measured widths.** "100%" is 32.9 pt in a 30 pt column; the waiting subtitle is 166 pt next to a 70 pt title in a 178 pt header, and its fixed size squeezes the title out; the stacked header needs 147 pt of the 144 it has, because its right margin is 36 pt, which kept room for the card's ↗ button, and that button is hidden while the card is open. The fix: a 34 pt percent column for both rows, and the header's title kept with the subtitle cutting, with the rows' own 12 pt margin. | Task 2 |
| 3 | Mac `writeJSONFile` replaces a symlink with a plain file and drops its mode | **Confirmed, and wider than named.** Foundation's atomic write replaces a link with a plain file that takes the link's own mode (0755) and leaves the file it pointed at unchanged, and the dated backup of a link is a second link to the same file, which the write then changes. And `writeJSONFile` is only Gemini's `settings.json` and Codex's and Antigravity's `hooks.json`: **Claude Code's own `~/.claude/settings.json`, the file most likely to be a link, is written by three other places** (`writeClaudeHooks`, `writeStatusLine`, `uninstallClaudeHooks`) with the same atomic write and the same link-copying backup. All four go through one new `ConfigFileWrite` (Open question 1). **The Windows twin is already right and is not changed:** `hooks::replace_file` writes to the canonicalised path, `write_like` gives the new file the original's permissions, its backup is `std::fs::copy` (which follows a link), and two tests say so; Task 4 runs them once through `cargo-linux.sh`. | Task 4 |
| 4 | The docs pass | **Changed, with two drops.** `docs/SPEC.md` still describes Mochi (the line that says where the values come from, the no-notch line, all of §7, the menu bar icon, the plan card's cat, milestone M2) and has no Cat section in Settings: rewritten in French for Shrimpy, Momo, the 16 coats, the display modes, the kittens and the small eyes, pointing to `docs/CAT-CONTRACT.md`. **`docs/INTEGRATIONS.md` has no Mochi or Coucou and is not stale** (its "Sous-agents : les chatons" section is B's), so it is left alone. `README.md` had two stale statements (the cats and icons "being built" with "the upstream placeholder character", and "Two motion styles are planned"), `windows/README.md` none; `CHANGELOG.md` had no line for A or B and said the cats and icons were "in progress". Found and **not** changed (the owner's or the main session's call): the README roadmap row A still says "in progress", CLAUDE.md still says the prototype is "being built", and `windows/README.md` says "The 28 sounds are the macOS app's own files" (the sounds folder is empty). | Task 5 |
| 5 | B's deferred minors | **All four confirmed and done.** (a) An empty 30 fps kitten layer: a leaving kitten stays in its list until the next event, and the list is what keeps the layer on the island, so the layer drew nothing until the cat fell asleep. (b) The agents' list order refreshes only with the next publish: made live for almost nothing, by announcing a change only when an event reorders the list. (c) `overviewCardShift`'s `botD` is unused, `PairExpanded.cat1D` only passes the one cat's diameter through (so `pairExpanded`'s `botD` goes too), and a pin asserts the secondCatPlace guard twice (and a "34 exactly" line says what two others say). (d) The `BADGE_RIGHT` doc block sits between `IN_ROW`'s comment and `IN_ROW`. **Left alone, as B's plans prescribed:** the global `.second` selector, `drawBot2`, the `State.cast` memo, and the contract's parallel-tool approval flip. | Tasks 6 to 9 |

## File Structure

| Path | Responsibility |
|---|---|
| `windows/src/settings/cat.ts`, `windows/src/settings/settings.css` | The six slider rows get the class `cat-trait`, and a grid of four columns that give way together. |
| `windows/scripts/cat-tests/settings-ui.test.mjs` | A source pin for the rows and the CSS, and that the window's other rows keep their rule. |
| `NotchBuddy/Sources/App/ClaudePlanCardView.swift`, `NotchBuddy/Sources/App/CatIslandLayout.swift` | The card's header (title kept, subtitle truncates, the rows' right margin) and percent column (34 pt, one number for both rows); the plan numbers' comment. |
| `scripts/render-plan-card.sh`, `scripts/render-plan-card.swift` | The sheet gains `--ago MINUTES` (the subtitle's age), to draw "59 min ago". |
| `tests/CatAgentListTests.swift`, `tests/CatWiringTests.swift` | The card's measured widths and its pins; the new minors' tests and pins; the signatures' tests. |
| `NotchBuddy/Sources/App/ConfigFileWrite.swift`, `tests/ConfigFileWriteTests.swift`, `scripts/test-config-file-write.sh` | New. How an agent's config file is written and backed up, its test (in a temp folder, with a symbolic link in every shape) and the source pins that the writers use it. |
| `NotchBuddy/Sources/App/HookServer.swift` | `writeJSONFile`, `writeClaudeHooks`, `writeStatusLine` and `uninstallClaudeHooks` write and back up through `ConfigFileWrite`. |
| `docs/SPEC.md`, `README.md`, `CHANGELOG.md` | The cats, in French in the spec; the stale lines; the lines for A and B. |
| `NotchBuddy/Sources/App/KittenViews.swift`, `CatKittens.swift`, `CatKittenDraw.swift`, `tests/CatKittensTests.swift` | The empty layer stops asking for frames (`CatKittens.mayStop`, `CatKittenHerd.lastFrameEmpty`, `@State quiet`). |
| `NotchBuddy/Sources/App/CatAgentList.swift`, `AppState.swift`, `tests/CatAgentListTests.swift` | `CatAgentList.touchReorders`, and `touchPill` announcing a change only when it reorders the list. |
| `NotchBuddy/Sources/App/CatIslandLayout.swift`, `PairCatViews.swift`, `IslandViewContent.swift`, `IslandRootView.swift`, `scripts/render-cats.swift` | `pairExpanded(botX:cy:)` and `overviewCardShift(second:botX:)`: no `botD`, no `cat1D`. |
| `windows/src/cat/kittendraw.ts`, `windows/scripts/cat-tests/kittendraw.test.mjs` | The doc blocks of `BADGE_RIGHT` and `IN_ROW` in their places, and a pin. |
| `.github/workflows/build.yml`, `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` | One CI step for the new test; the project regenerated by `xcodegen`. |

## Tasks and agents

CLAUDE.md: the lightest model that fits. Tasks whose code is given in full and that are scripts to run and check (5, 7, 8, 9, 10) are `nm-implementer-light` (Haiku 4.5). Tasks that need a picture looked at, SwiftUI state or a judgement on the output (1, 2, 4, 6) are `nm-implementer` (Sonnet 5.5, medium). Each task is then reviewed by `nm-reviewer`, except Task 9 (a comment moved, covered by the whole-branch review), and the whole branch by `nm-reviewer-deep` after Task 10. If a step's expected output differs and the cause is not obvious, hand that task to `nm-implementer-deep`. Coding agents load `ponytail:ponytail`, `superpowers:test-driven-development` and `superpowers:verification-before-completion` (the deep agent also `superpowers:systematic-debugging`); the agents of Tasks 1 and 2 also load `playwright-cli`; reviewers load `ponytail:ponytail-review` (the deep reviewer also `superpowers:requesting-code-review`).

| # | Task | Agent | Review |
|---|---|---|---|
| 0 | Worktree, baseline and the base sheets | the session | none |
| 1 | Windows: the six personality sliders on one line (pictures at 560 × 680 and 460 × 680) | `nm-implementer` | `nm-reviewer` |
| 2 | Mac: the Claude plan card, three layout fixes (pictures of the shipping and stacked cards, with data and waiting) | `nm-implementer` | `nm-reviewer` |
| 3 | **Owner checkpoint 1:** the two visual fixes, before and after | the main session and the owner | none |
| 4 | Mac: an agent's config file that is a link stays a link and keeps its permissions (and the Windows twin, confirmed) | `nm-implementer` | `nm-reviewer` |
| 5 | Docs: the cats in `SPEC.md`, stale lines, the changelog for A and B | `nm-implementer-light` | `nm-reviewer` |
| 6 | Mac: an empty kitten layer stops asking for frames | `nm-implementer` | `nm-reviewer` |
| 7 | Mac: the agents' list order follows the events | `nm-implementer-light` | `nm-reviewer` |
| 8 | Mac: no unused `botD`, no pass-through `cat1D`, one duplicate pin fewer | `nm-implementer-light` | `nm-reviewer` |
| 9 | Windows: the `BADGE_RIGHT` doc block | `nm-implementer-light` | none |
| 10 | The final checks: every test, the builds, the binaries, the sheets unchanged | `nm-implementer-light` | `nm-reviewer` |
| After 10 | The whole branch: the scope, the shipping views, the config rule, the Review Focus | `nm-reviewer-deep` | none |
| 11 | **Owner checkpoint 2:** the final report and the checks only a real build can do | the main session and the owner | none |

## Execution

One worktree chat session runs the whole plan: branch `fixes/after-b`, model **Sonnet 5.5 at medium effort** (`ARCHITECT.md`: a plan whose tasks are mostly given in full). Nothing is pushed.

**The session is started in three steps** (ARCHITECT.md), because a chip's first turn runs on the app's default model and a model change applies only from a session's next turn:

1. **Setup and stop.** The chip's prompt only sets up:

   > Run `git switch -c fixes/after-b notchmeow/rebrand`, then Task 0 of `docs/superpowers/plans/2026-10-08-small-fixes-after-b.md`: only its Steps 1 and 2 (the base checks, and the copy of `windows/node_modules`). Read `CLAUDE.md`, `ARCHITECT.md` and that plan. If a base check fails, say so and stop. Reply "ready" and stop. Do not start Task 1.

2. **Model.** Once the owner starts the chip, the main session sets that session to Sonnet 5.5 at medium effort (`set_session_model`, `set_session_effort`).
3. **Brief.** The main session then sends the controller brief as the next message.

**Controller brief** (what the main session sends once the model is set):

> Run `docs/superpowers/plans/2026-10-08-small-fixes-after-b.md` with `superpowers:subagent-driven-development`, task by task, on branch `fixes/after-b`. The SDD plugin scripts (`sdd-workspace`, `task-brief`, `review-package`) are refused here: keep the ledger at `.superpowers/sdd/2026-10-08-small-fixes-after-b/progress.md`, write each task brief with the Write tool just before you dispatch it, and write the review diffs with `git diff`. Dispatch each task to the agent the plan's "Tasks and agents" table names, then to `nm-reviewer`; fix what the review finds before the next task. Put the plan's SUBAGENT RULES block (Global Constraints) in every brief. Never launch, quit or replace a NotchMeow app or the Tauri app: the builds are builds, the Mac pictures come from `scripts/render-*.sh`, the Windows pictures from `npx --no-install vite` and the headless `playwright-cli`. Install and download nothing; Rust only through `windows/scripts/cargo-linux.sh` with `--target-dir /repo/windows/target/fixes-after-b`. Do Task 0's Steps 3 and 4 first (the baseline, and the base sheets: they must be drawn before anything changes), then run Tasks 1 and 2, then stop and report to the main session for owner checkpoint 1 (Task 3: the pictures it names, and what to look for). After the owner's reply run Tasks 4 to 10, dispatch `nm-reviewer-deep` over the whole branch, and stop for checkpoint 2 (Task 11). Commit only as the plan's commit steps say, and never push. Report: the commits; for `windows/`: `npx --no-install tsc --noEmit`, `npm run check:cat`, `npm run check:ai` and `npm run check:claude`; every `bash scripts/test-cat-*.sh` line, `test-plan-gauge.sh`, `test-config-file-write.sh`, `check-no-leftovers.sh` and `check-test-logs.sh`; the Debug, Release and App Store build lines and the three `check-app-binary.sh` lines; the paths of the pictures of each checkpoint; what the Windows twin run printed; and anything you could not settle.

Before any follow-up turn (a fix round, a question, a resumed run), the main session checks the session is still on its configured model and effort.

## How to run this plan

**Blocks.** A code step is a `bash` block: either a file written with `cat > path <<'EOF'` (the file's exact content), or a Python script whose `edit` helper replaces text that must occur exactly once in the file it names, or a plain command. Run each block from the repository root, as it is, in `bash` (the blocks avoid what zsh does differently, but run them with `bash` if in doubt). Never type a block from memory and never "improve" one. If a find text occurs zero or two times, stop and report: the tree is not what the plan expects. Every `Run:` line is run from the repository root; `Expected:` says what it prints (every backticked literal must appear). A test program's failing run prints `✗` lines and ends `N test(s) failed.`; a passing one ends `All tests passed.`

**Mac commands.** The test programs are `swiftc` programs run through `scripts/test-*.sh`; none needs Xcode. A build is `cd NotchBuddy && xcodegen && cd ..` and then `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO`; the Release build is `-configuration Release -derivedDataPath NotchBuddy/build/release` and the App Store target `-scheme NotchMeowAppStore -configuration Debug -derivedDataPath NotchBuddy/build/store`, each with `CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO` (git ignores `NotchBuddy/build/`). **Never start a built app.**

**Looking at an image.** Several steps end with "look at it". The agent that ran the step opens the PNG with its file reader and says in one sentence what it sees against the thing named; a blank or broken image is a failed step. The owner's look is the checkpoint.

**Red first.** Each task writes its tests, runs them to see them fail, writes the code, and runs them to see them pass. A step that proves a check can bite changes a line, runs the check, and puts the line back: it is never committed.

---

## Tasks

### Task 0: Worktree, baseline and the base sheets

No code and no commit. Its first two steps are what the chip's prompt runs before the model is set (see "Execution").

- [ ] **Step 1: Put the session's worktree on the plan's branch**

```bash
git status                                    # must be clean
git switch -c fixes/after-b notchmeow/rebrand
git merge-base --is-ancestor b13eed1 HEAD && echo "the base (b13eed1) is in the history"
git log --oneline -3
```

Expected: `the base (b13eed1) is in the history`. If that line is missing, the worktree was cut from an older base: stop and tell the owner. Every later command runs from the root of this worktree. Never push.

- [ ] **Step 2: Copy the front end's packages**

This plan adds no package, so nothing is downloaded: no `npm install` or `npm ci`. `cp -c` makes an APFS clone, which is instant and takes no extra disk space. It must be a real folder, not a symlink, because `.gitignore` ignores `/windows/node_modules` only as a folder.

```bash
cp -cR "/path/to/notchmeow/windows/node_modules" windows/node_modules
git status --short                            # still empty: the copy is ignored
(cd windows && node --version)                # 22.6 or newer
```

Expected: no output from the status command (the copied packages are ignored), then a version that starts `v22.`.

- [ ] **Step 3: Check that the starting point is green**

Run: `cd windows && npx --no-install tsc --noEmit; echo "tsc exit $?"; npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; npm run check:ai 2>&1 | tail -1; npm run check:claude 2>&1 | tail -1; cd ..`
Expected: `tsc exit 0` with no type error before it, `ℹ tests 272`, `ℹ pass 272`, `ℹ fail 0`, `All AI UI checks passed` and `All Claude Code UI checks passed`.

Run: `bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)|✓ [0-9]+ fixture files|✓ two generator"; node scripts/check-fixtures-additive.mjs b13eed1 2>&1 | tail -1`
Expected: `# tests 231`, `# pass 231`, `# fail 0`, `✓ 14 fixture files match cat-core.js`, `✓ two generator runs write identical bytes` and `✓ fixtures changed only by addition since b13eed1`.

Run: `for f in scripts/test-cat-*.sh scripts/test-plan-gauge.sh; do bash "$f" 2>&1 | tail -1; done | sort | uniq -c`
Expected: `25 All tests passed.` and `1 ✓ two generator runs write identical bytes` (the contract's script ends with its own line; the other twenty-four cat scripts and the plan gauge's end with the first).

Run: `bash scripts/check-no-leftovers.sh 2>&1 | tail -1; bash scripts/check-test-logs.sh; docker image inspect notchmeow-linux-dev >/dev/null && echo "image ok"`
Expected: `✓ no notification that nothing posts or observes`, `✓ every log-writing test script sets NM_LOG_DIR` and `image ok`.

- [ ] **Step 4: Draw the base sheets, for the final check that nothing moved**

Tasks 6 to 8 touch code the island and kitten sheets run through (`CatIslandLayout`, `CatKittens`, `CatKittenDraw`). They change no pixel, and Task 10 proves it by drawing the same four sheets again and comparing the files. Draw them now, before anything changes.

```bash
O="${TMPDIR:-/tmp}/fixes-after-b-base"; mkdir -p "$O"
bash scripts/render-cats.sh --island --scale 2 --out "$O/island.png"
bash scripts/render-cats.sh --kittens --scenario life --out "$O/life-one.png"
bash scripts/render-cats.sh --kittens --scenario crowd --out "$O/crowd-one.png"
bash scripts/render-cats.sh --kittens --scenario life --mode two --out "$O/life-two.png"
ls "$O"
```

Expected: four `wrote … .png` lines, then `crowd-one.png`, `island.png`, `life-one.png` and `life-two.png`.

---
### Task 1: Windows, the six personality sliders on one line

**Agent:** `nm-implementer`. Loads `playwright-cli`.

**Files:**
- Modify: `windows/src/settings/cat.ts`, `windows/src/settings/settings.css`, `windows/scripts/cat-tests/settings-ui.test.mjs`

**Interfaces:**
- Consumes: the Cat section's `row(label, ...controls)` (a `div.row` with a label and the controls), `TRAITS` (Energy, Curiosity, Chattiness, Affection, Sass, Mischief, each with its two ends), the window's `.row` rule and the `.cat-low` and `.cat-high` rules.
- Produces: the class `cat-trait` on the six slider rows and no other row, and `.row.cat-trait`, a grid of four columns (`minmax(72px, 132px) minmax(76px, 84px) minmax(56px, 140px) minmax(76px, 84px)`).

**The cause, confirmed.** The Settings window is 560 × 680 with a 460 × 480 minimum (`windows/src-tauri/src/lib.rs`: `.inner_size(560.0, 680.0)`, `.min_inner_size(460.0, 480.0)`). A slider row is a `.row` (`display: flex; gap: 12px; flex-wrap: wrap`) of four things: the label (`min-width: 132px`), the low end (`.cat-low`, `min-width: 84px`), the slider (`width: 140px`) and the high end (`.cat-high`, `min-width: 84px`): 132 + 84 + 140 + 84 + 3 × 12 = 476 px. The row has `560 − 2 × 24` (the window's padding) `− 2 × 1` (the section's border) `− 2 × 18` (its padding) = 474 px, and a scrollbar takes about 17 more, so the last item wraps at every width, and at 460 even the slider does. The slider rows must not wrap, and **no other row may change**, so the six rows get a class of their own and the window's `.row` rule is left as it is.

- [ ] **Step 1: Draw the before pictures, and measure the rows**

`playwright-cli` opens `settings.html` from the Vite dev server (outside Tauri every Bridge call is a no-op, so the page shows the defaults). The script measures the six rows at four widths (560 and 460, and 543 and 443, which are what a 17 px scrollbar leaves of them), writes the size of every other row to a file so the after picture can prove none moved, and takes the pictures at 560 and 460 with the first slider row in the middle of the window.

```bash
SHOTS="${TMPDIR:-/tmp}/fixes-after-b-shots"; mkdir -p "$SHOTS"
cat > "$SHOTS/measure.js" <<'EOF'
(() => {
  const rows = [...document.querySelectorAll('.row')].filter((r) => r.querySelector('.cat-low'));
  const mid = (e) => e.getBoundingClientRect().top + e.getBoundingClientRect().height / 2;
  const one = rows.filter((r) => [...r.children].every((k) => Math.abs(mid(k) - mid(r)) < 1)).length;
  const lefts = [...new Set(rows.map((r) => Math.round(r.querySelector('input').getBoundingClientRect().left)))];
  const widths = [...new Set(rows.map((r) => Math.round(r.querySelector('input').getBoundingClientRect().width)))];
  const over = rows.filter((r) => [...r.children].some((k) => k.getBoundingClientRect().right > r.getBoundingClientRect().right + 0.5)).length;
  const clipped = rows.filter((r) => [...r.children].some((k) => k.scrollWidth > k.clientWidth + 0.5)).length;
  return `width ${window.innerWidth}: ${rows.length} slider rows, ${one} on one line, ${over} overflowing, ${clipped} clipped, slider left edge ${lefts.join('/')}, slider width ${widths.join('/')}`;
})()
EOF
cat > "$SHOTS/rows.js" <<'EOF'
JSON.stringify([...document.querySelectorAll('.row')].filter((r) => !r.querySelector('.cat-low')).map((r) => [r.textContent.trim().slice(0, 24), Math.round(r.getBoundingClientRect().width), Math.round(r.getBoundingClientRect().height)]))
EOF
cat > "$SHOTS/wide.js" <<'EOF'
(() => {
  document.body.style.fontFamily = 'Verdana, sans-serif';
  const rows = [...document.querySelectorAll('.row')].filter((r) => r.querySelector('.cat-low'));
  const mid = (e) => e.getBoundingClientRect().top + e.getBoundingClientRect().height / 2;
  const one = rows.filter((r) => [...r.children].every((k) => Math.abs(mid(k) - mid(r)) < 1)).length;
  const clipped = rows.filter((r) => [...r.children].some((k) => k.scrollWidth > k.clientWidth + 0.5)).length;
  const over = rows.filter((r) => [...r.children].some((k) => k.getBoundingClientRect().right > r.getBoundingClientRect().right + 0.5)).length;
  return `Verdana at ${window.innerWidth}: ${one} of ${rows.length} on one line, ${clipped} clipped, ${over} overflowing`;
})()
EOF
cat > "$SHOTS/sliders.sh" <<'EOF'
#!/usr/bin/env bash
# Usage: bash sliders.sh before|after   (Vite is already serving windows/ on port 14582)
set -euo pipefail
cd "$(dirname "$0")"
PHASE=$1
for W in 560 543 460 443; do
  cat > "pw-$W.json" <<JSON
{ "browser": { "contextOptions": { "viewport": { "width": $W, "height": 680 }, "deviceScaleFactor": 2 } } }
JSON
  playwright-cli -s="sl$W" open "http://127.0.0.1:14582/settings.html" --config="pw-$W.json" > /dev/null
  sleep 1.5
  playwright-cli -s="sl$W" --raw eval "$(cat measure.js)"
  playwright-cli -s="sl$W" --raw eval "$(cat rows.js)" > "rows-$PHASE-$W.json"
  if [ "$W" = 560 ] || [ "$W" = 460 ]; then
    playwright-cli -s="sl$W" run-code "async page => { await page.evaluate(() => document.querySelector('input[type=range]').closest('.row').scrollIntoView({ block: 'center' })); await page.waitForTimeout(400); await page.screenshot({ path: 'sliders-$PHASE-$W.png' }); }" > /dev/null
  fi
  # after the fix, the same rows in a font much wider than Windows' Segoe UI (the page is not used again after this)
  if [ "$PHASE" = after ] && { [ "$W" = 460 ] || [ "$W" = 443 ]; }; then
    playwright-cli -s="sl$W" --raw eval "$(cat wide.js)"
  fi
  playwright-cli -s="sl$W" close > /dev/null
done
EOF
(cd windows && exec node node_modules/vite/bin/vite.js --port 14582 --strictPort > "$SHOTS/vite.log" 2>&1) &
echo $! > "$SHOTS/vite.pid"
sleep 4
bash "$SHOTS/sliders.sh" before
kill "$(cat "$SHOTS/vite.pid")"; sleep 1; lsof -ti tcp:14582 | wc -l
ls "$SHOTS" | grep -E "^sliders-before"
```

Expected: four lines, `"width 560: 6 slider rows, 0 on one line, 0 overflowing, 0 clipped, slider left edge 283, slider width 140"`, `"width 543: 6 slider rows, 0 on one line, …"`, `"width 460: 6 slider rows, 0 on one line, 0 overflowing, 0 clipped, slider left edge 43, slider width 140"` and `"width 443: 6 slider rows, 0 on one line, …"` (none of the six rows is on one line at any width: the cause), then `0` (nothing listens on the port any more), `sliders-before-460.png` and `sliders-before-560.png`. **Open both pictures:** at 560 the high labels (bouncy, nosy, talkative, cuddly, grumpy, troublemaker) sit under the sliders, and at 460 the slider and the label both wrap, three lines to a row.

- [ ] **Step 2: Write the failing test**

The Cat section's glue is checked by source pins (it needs a browser, and Step 1 and Step 5 are that browser): the six rows get the class, the CSS gives it a grid and one column template, and the window's own `.row` rule stays as it is.

```bash
cat >> windows/scripts/cat-tests/settings-ui.test.mjs <<'EOF'

test("the six personality sliders stay on one line, in line with each other, from the window's 560 px down to its 460 px minimum: a grid on those rows only", () => {
  assert.match(cat, /el\.classList\.add\("cat-trait"\)/, "the six slider rows, and no other row, get the class");
  assert.equal(cat.split('"cat-trait"').length - 1, 1);
  const body = (selector) => {
    const at = css.indexOf(`${selector} {`);
    assert.ok(at > 0, selector);
    return css.slice(at, css.indexOf("}", at));
  };
  assert.match(body(".row.cat-trait"), /display: grid;/);
  assert.match(body(".row.cat-trait"), /grid-template-columns: minmax\(72px, 132px\) minmax\(76px, 84px\) minmax\(56px, 140px\) minmax\(76px, 84px\);/);
  assert.match(body(".cat-trait input[type=\"range\"]"), /width: 100%;/);
  assert.match(body(".row.cat-trait > label,\n.cat-trait .cat-low,\n.cat-trait .cat-high"), /min-width: 0;[\s\S]*white-space: nowrap;/);
  // Every other row keeps the rule it had: the wrapping row is still the window's own.
  assert.match(body(".row"), /display: flex;[\s\S]*flex-wrap: wrap;/);
  assert.match(body(".row > label"), /min-width: 132px;/);
});
EOF
```

Run: `cd windows && npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; cd ..`
Expected: FAIL: `ℹ tests 273`, `ℹ pass 272`, `ℹ fail 1`.

- [ ] **Step 3: Write the fix**

```bash
python3 - <<'PY'
# Task 1: the personality sliders stay on one line. Run from the repository root.
def edit(path, pairs):
    s = open(path, encoding='utf-8').read()
    for was, now in pairs:
        assert s.count(was) == 1, (path, was[:70])
        s = s.replace(was, now)
    open(path, 'w', encoding='utf-8').write(s)

edit('windows/src/settings/cat.ts', [
('''    return { key, input, el: row(label, h("span", { class: "hint cat-low", text: low }), input, h("span", { class: "hint cat-high", text: high })) };
''', '''    const el = row(label, h("span", { class: "hint cat-low", text: low }), input, h("span", { class: "hint cat-high", text: high }));
    el.classList.add("cat-trait");   // one line at every width the window can have (settings.css)
    return { key, input, el };
'''),
])

edit('windows/src/settings/settings.css', [
('''.cat-high {
  min-width: 84px;
}
''', '''.cat-high {
  min-width: 84px;
}

/* The six personality sliders stay on one line from the window's 560 px down to its 460 px minimum (about 440 px of room once a scrollbar is there), instead of wrapping the
   high end under the slider. The row is a grid, so its four columns give way together and the six sliders still line up: the label's and the slider's give first. */
.row.cat-trait {
  display: grid;
  grid-template-columns: minmax(72px, 132px) minmax(76px, 84px) minmax(56px, 140px) minmax(76px, 84px);
}

.row.cat-trait > label,
.cat-trait .cat-low,
.cat-trait .cat-high {
  min-width: 0;
  white-space: nowrap;
}

.cat-trait input[type="range"] {
  width: 100%;
}
'''),
])
PY
```

- [ ] **Step 4: Run the tests**

Run: `cd windows && npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; npx --no-install tsc --noEmit; echo "tsc exit $?"; cd ..`
Expected: PASS: `ℹ tests 273`, `ℹ pass 273`, `ℹ fail 0` and `tsc exit 0` with no type error before it.

- [ ] **Step 5: Draw the after pictures, and prove no other row moved**

```bash
SHOTS="${TMPDIR:-/tmp}/fixes-after-b-shots"
(cd windows && exec node node_modules/vite/bin/vite.js --port 14582 --strictPort > "$SHOTS/vite.log" 2>&1) &
echo $! > "$SHOTS/vite.pid"
sleep 4
bash "$SHOTS/sliders.sh" after
kill "$(cat "$SHOTS/vite.pid")"; sleep 1; lsof -ti tcp:14582 | wc -l
cd "$SHOTS"
for W in 560 543 460 443; do cmp "rows-before-$W.json" "rows-after-$W.json" && echo "the window's other rows are the same size at $W"; done
ls | grep -E "^sliders-after"
```

Expected: six lines, in this order: `"width 560: 6 slider rows, 6 on one line, 0 overflowing, 0 clipped, slider left edge 283, slider width 138"`, `"width 543: 6 slider rows, 6 on one line, 0 overflowing, 0 clipped, slider left edge 283, slider width 121"`, `"width 460: 6 slider rows, 6 on one line, 0 overflowing, 0 clipped, slider left edge 244, slider width 77"`, `"Verdana at 460: 6 of 6 on one line, 0 clipped, 0 overflowing"`, `"width 443: 6 slider rows, 6 on one line, 0 overflowing, 0 clipped, slider left edge 236, slider width 69"` and `"Verdana at 443: 6 of 6 on one line, 0 clipped, 0 overflowing"` (all six rows on one line at every width, one left edge for the six sliders, so they line up; and the two Verdana lines are the same rows in a font much wider than Segoe UI, which Windows uses: the columns have room to spare), then `0`, `the window's other rows are the same size at 560`, `… at 543`, `… at 460`, `… at 443`, then `sliders-after-460.png` and `sliders-after-560.png`. **Open both pictures and say what you see to the controller.** At 560 each row is the label, the low end, a slider about 138 px wide and the high end, all on one line, the six sliders in a column; at 460 the slider has shrunk to 77 px and the longest label, troublemaker, still ends inside the card; nothing else in the Cat section is different from the before pictures (Motion style, This cat's motion and Personality with their hints, Collar, Apply to every cat, Fur lines).

- [ ] **Step 6: Commit**

```bash
git add windows/scripts/cat-tests/settings-ui.test.mjs windows/src/settings/cat.ts windows/src/settings/settings.css
git commit -m "fix(settings): the six personality sliders stay on one line at 560 px and at the 460 px minimum

The Cat section's trait rows (Energy to Mischief) wrapped their high end (bouncy, nosy, talkative, cuddly, grumpy, troublemaker) under the
slider: the row needs 476 px, a 560 px window gives it 474 (less with a scrollbar), and .row has flex-wrap: wrap. Those six rows are now a grid
with one column template (.row.cat-trait), so the columns give way together and the sliders still line up. No other row changes.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

Run: `git status --short`
Expected: nothing (the copied packages are ignored).

---

### Task 2: Mac, the Claude plan card: "100%", the waiting title, the stacked subtitle

**Agent:** `nm-implementer`.

**Files:**
- Modify: `NotchBuddy/Sources/App/ClaudePlanCardView.swift`, `NotchBuddy/Sources/App/CatIslandLayout.swift`, `scripts/render-plan-card.sh`, `scripts/render-plan-card.swift`, `tests/CatAgentListTests.swift`, `tests/CatWiringTests.swift`

**Interfaces:**
- Consumes: `ClaudePlanCardView(usage:stacked:)` and its private `GaugeRowView` (its `shippingRow` and `stackedRow`); `CatIslandLayout`'s `cardWidth`, `planRowsTrailing`, `planLabelWidth`, `planBarWidth`, `planPercentWidth`, `planRowSpacing`, `planRowsWidth(shift:)`, `planStackedLineWidth`, `planResetIndent`, `oneTextLeading` and `overviewCardShift(second:botX:botD:)` (Task 8 removes its `botD`); the sheet's `--stacked`, `--shift` and `--waiting`.
- Produces: `CatIslandLayout.planPercentWidth` is 34 and is read by **both** rows (the shipping row's percent was a literal 30); `CatIslandLayout.planStackedLineWidth` is 134; the header's right margin is `CatIslandLayout.planRowsTrailing` (12); the sheet's `--ago MINUTES` (default 5).

**The causes, confirmed** (measured with the system font; the card is 322 pt wide, its rows start 108 pt in):

1. **"100%" wraps.** 11 pt semibold monospaced digits make "100%" 32.9 pt wide; the shipping row's percent column is a literal 30 pt. (Two cats mode's stacked row already has a 36 pt column, for this reason.) The column becomes 34 pt for both rows. The shipping row is then 200.5 pt with the longest date ("Thu 14:30"), inside the 202 pt it has, and 205.9 pt with "Resetting…" (53.9 pt, the longest label), which ends 8 pt inside the card's edge (it ended 12 pt inside); its reset labels move 4 pt to the right in both rows, and nothing else moves.
2. **The waiting title is squeezed out.** The header is the dot, the title ("Claude plan", 69.5 pt, 12 pt semibold) and the subtitle, in the 178 pt between 108 pt and a 36 pt right margin. The waiting subtitle ("Waiting for a Claude Code reply", 166 pt) has `fixedSize` on both axes, so it keeps all its width and the title gets none (and, with a title that may wrap, the squeezed "Claude plan" wraps letter by letter, which makes the header tall and pushes the rows down about 30 pt). The stacked card had the cure already: the title keeps its line and its priority, and the subtitle truncates. It becomes the rule of both layouts, which removes the `stacked ? :` choices from the header.
3. **A long stacked subtitle truncates.** "59 min ago" is 58.6 pt: the stacked header needs 7 + 6 + 69.5 + 6 + 58.6 = 147.1 pt of the 144 it has (322 − 142 − 36). The 36 pt right margin was room for the card's ↗ jump button, which is hidden while the plan card is open (`hideJumpButton` includes `showingPlanDetail`), so the header takes the rows' own 12 pt: 168 pt in Two cats mode and 202 in the shipping card.

- [ ] **Step 1: Add `--ago` to the sheet, and draw the before pictures**

The sheet draws the card with fixed data (63 % and 100 %, the longest labels) and a subtitle five minutes old; `--ago` sets the age, to draw the longest ordinary subtitle. It changes only the sheet.

```bash
python3 - <<'PY'
# Task 2: the plan card sheet's --ago. Run from the repository root.
def edit(path, pairs):
    s = open(path, encoding='utf-8').read()
    for was, now in pairs:
        assert s.count(was) == 1, (path, was[:70])
        s = s.replace(was, now)
    open(path, 'w', encoding='utf-8').write(s)

edit('scripts/render-plan-card.swift', [
('''//   bash scripts/render-plan-card.sh --out plan-card.png [--stacked] [--shift 34] [--waiting]
//   --stacked/--shift are what Two cats mode gives the card (`stacked: true`, 34 pt in); no flags is the card as it ships; --waiting is the card with no data yet (the longest subtitle).''',
 '''//   bash scripts/render-plan-card.sh --out plan-card.png [--stacked] [--shift 34] [--waiting] [--ago 5]
//   --stacked/--shift are what Two cats mode gives the card (`stacked: true`, 34 pt in); no flags is the card as it ships; --waiting is the card with no data yet (the longest subtitle);
//   --ago is how many minutes old the data is (the subtitle: 59 is the longest ordinary one).'''),
('''var out = "plan-card.png", stacked = false, shift = 0.0, waiting = false
''', '''var out = "plan-card.png", stacked = false, shift = 0.0, waiting = false, ago = 5.0
'''),
('''            case "--waiting": waiting = true
''', '''            case "--waiting": waiting = true
            case "--ago": ago = Double(it.next() ?? "") ?? ago
'''),
('''updatedAt: now.addingTimeInterval(-5 * 60))''', '''updatedAt: now.addingTimeInterval(-ago * 60))'''),
])
edit('scripts/render-plan-card.sh', [
('''#   bash scripts/render-plan-card.sh --out plan-card.png [--stacked] [--shift 34] [--waiting]''', '''#   bash scripts/render-plan-card.sh --out plan-card.png [--stacked] [--shift 34] [--waiting] [--ago 5]'''),
])
PY
O="${TMPDIR:-/tmp}/fixes-after-b-1"; mkdir -p "$O"
bash scripts/render-plan-card.sh --out "$O/plan-before-ship.png"
bash scripts/render-plan-card.sh --out "$O/plan-before-ship-waiting.png" --waiting
bash scripts/render-plan-card.sh --out "$O/plan-before-stacked.png" --stacked --shift 34
bash scripts/render-plan-card.sh --out "$O/plan-before-stacked-59.png" --stacked --shift 34 --ago 59
bash scripts/render-plan-card.sh --out "$O/plan-before-stacked-waiting.png" --stacked --shift 34 --waiting
```

Expected: five `wrote … .png` lines. **Open the five pictures** (they are 2×: 784 px for the 392 pt canvas; a red line marks the card's right edge at 322 pt). `plan-before-ship.png`: in the weekly row "100" sits over "%" (the wrap). `plan-before-ship-waiting.png`: a grey dot and "Waiting for a Claude Code reply", no "Claude plan" (the squeeze), and the two rows far lower than in the card with data. `plan-before-stacked.png`: both rows on two lines, nothing wrong. `plan-before-stacked-59.png`: "59 min a…" (the truncation). `plan-before-stacked-waiting.png`: "Claude plan" and "Waiting…".

- [ ] **Step 2: Write the failing tests**

The widths are measured with AppKit's system font in the test (an estimate of "about 48 pt" is how the percent column went wrong the first time). The measured test of "100%" and of the headers passes with the numbers as they stand and with the fix; what fails first is the shipping row's width with a 36 pt column, the column's own number, and the two pins that tie the view to `CatIslandLayout`.

```bash
python3 - <<'PY'
# Task 2, tests first: the plan card's measured widths and the two pins. Run from the repository root.
def edit(path, pairs):
    s = open(path, encoding='utf-8').read()
    for was, now in pairs:
        assert s.count(was) == 1, (path, was[:70])
        s = s.replace(was, now)
    open(path, 'w', encoding='utf-8').write(s)

edit('tests/CatAgentListTests.swift', [
('''import Foundation

@main
enum CatAgentListTests {
''', '''import AppKit
import Foundation

@main
enum CatAgentListTests {
'''),
('''        CT.section("the Claude plan card in Two cats mode: every row fits inside the card at the shifted width")
        let shipRows = CatIslandLayout.planRowsWidth(shift: 0), shiftedRows = CatIslandLayout.planRowsWidth(shift: CatIslandLayout.overviewCardShift(second: true, botX: 68, botD: 58))
        CT.check("the rows have 202 pt in the card as it ships (322 - 108 - 12) and 168 pt with cat 2's 34 pt shift", [shipRows, shiftedRows], [202, 168])
        CT.check("a stacked row's widest line is the label, the bar and the percent (36 wide here: 100% is about 33 pt): 40 + 50 + 36 + 2 x 5 = 136", CatIslandLayout.planStackedLineWidth, 136)
        CT.checkTrue("it fits the shifted width with 30 pt to spare", CatIslandLayout.planStackedLineWidth <= shiftedRows - 30)
        CT.check("the reset line is indented under the bar: the label column and one gap, 45 pt", CatIslandLayout.planResetIndent, 45)
        let resetLine: Double = CatIslandLayout.planResetIndent + 9 + CatIslandLayout.planRowSpacing + 48
        let shippingRow: Double = 130 + 9 + CatIslandLayout.planRowSpacing + 48
        CT.checkTrue("the reset line (indent + arrow 9 + gap 5 + the longest label, 'Thu 14:30', about 48 pt) fits the shifted width", resetLine <= shiftedRows)
        CT.checkTrue("the shipping row (shipping's own 130 + arrow 9 + gap 5 + 48) fits the 202 pt it has, and would not fit 168: that is why only the shifted card stacks", shippingRow <= shipRows && shippingRow > shiftedRows)
''', '''        CT.section("the Claude plan card: the percent, the rows and the header fit, as it ships and in Two cats mode (text widths are measured with the system font, not guessed)")
        func textWidth(_ s: String, _ size: CGFloat, _ weight: NSFont.Weight = .regular, digits: Bool = false) -> Double {
            let font = digits ? NSFont.monospacedDigitSystemFont(ofSize: size, weight: weight) : NSFont.systemFont(ofSize: size, weight: weight)
            return Double((s as NSString).size(withAttributes: [.font: font]).width)
        }
        let shipRows = CatIslandLayout.planRowsWidth(shift: 0), shiftedRows = CatIslandLayout.planRowsWidth(shift: CatIslandLayout.overviewCardShift(second: true, botX: 68, botD: 58))
        CT.check("the rows have 202 pt in the card as it ships (322 - 108 - 12) and 168 pt with cat 2's 34 pt shift", [shipRows, shiftedRows], [202, 168])
        CT.check("the percent column is 34 pt in both rows, and a stacked row's widest line is the label, the bar and the percent: 40 + 50 + 34 + 2 x 5 = 134", [CatIslandLayout.planPercentWidth, CatIslandLayout.planStackedLineWidth], [34, 134])
        CT.checkTrue("'100%' (about 33 pt, measured) fits that column on one line: in the 30 pt the shipping row used to have, it wrapped to '100' over '%'", textWidth("100%", 11, .semibold, digits: true) + 1 <= CatIslandLayout.planPercentWidth)
        CT.checkTrue("the stacked row fits the shifted width with 30 pt to spare", CatIslandLayout.planStackedLineWidth <= shiftedRows - 30)
        CT.check("the reset line is indented under the bar: the label column and one gap, 45 pt", CatIslandLayout.planResetIndent, 45)
        let arrow = 8.0   // the clockwise arrow, a symbol set at 8 pt
        CT.checkTrue("the stacked reset line (indent + arrow + gap + 'Resetting…', the longest label, measured) fits the shifted width", CatIslandLayout.planResetIndent + arrow + CatIslandLayout.planRowSpacing + textWidth("Resetting…", 10) <= shiftedRows)
        func shippingRow(_ reset: String) -> Double { CatIslandLayout.planLabelWidth + CatIslandLayout.planBarWidth + CatIslandLayout.planPercentWidth + arrow + 4 * CatIslandLayout.planRowSpacing + textWidth(reset, 10) }
        CT.checkTrue("the shipping row with its longest date label ('Thu 14:30') fits the 202 pt it has, and would not fit 168: that is why only the shifted card stacks", shippingRow("Thu 14:30") <= shipRows && shippingRow("Thu 14:30") > shiftedRows)
        CT.checkTrue("even with 'Resetting…' the shipping row stays inside the card, 6 pt from its edge", CatIslandLayout.oneTextLeading + shippingRow("Resetting…") <= CatIslandLayout.cardWidth - 6)
        let titleAndDot = 7 + 6 + textWidth("Claude plan", 12, .semibold)
        CT.checkTrue("the header fits its longest ordinary subtitle, '59 min ago' (the dot, the title and the subtitle: about 147 pt measured), in the shifted card's 168 pt: with the 36 pt right margin it used to have, it had 144 and cut it to '59 min a…'", titleAndDot + 6 + textWidth("59 min ago", 11) <= shiftedRows)
        CT.checkTrue("and the title stays whole next to the longest subtitle there is, 'Waiting for a Claude Code reply', which gives way instead", titleAndDot + 6 + textWidth("Waiting for a Claude Code reply", 11) > shipRows && titleAndDot <= shiftedRows)
'''),
])

edit('tests/CatWiringTests.swift', [
('''        CT.checkTrue("the shipping row is untouched outside the stacked path: the 40 pt label, the 50 pt bar, the 30 pt percent, the fixed-size reset label, and the header's and rows' paddings", plan.contains(".frame(width: 40, alignment: .leading)") && plan.contains("Capsule()\\n                        .fill(Color.white.opacity(0.08))\\n                        .frame(width: 50, height: 4)") && plan.contains(".frame(width: 30, alignment: .trailing)") && plan.contains("Image(systemName: \\"arrow.clockwise\\")\\n                    .font(.system(size: 8))\\n                    .foregroundColor(Color(hex: \\"#6B7079\\"))\\n                Text(resetLabel(w))\\n                    .font(.system(size: 10))\\n                    .foregroundColor(Color(hex: \\"#6B7079\\"))\\n                    .fixedSize()") && plan.contains(".padding(.leading, 108)\\n            .padding(.trailing, 36)") && plan.contains(".padding(.leading, 108)\\n            .padding(.trailing, 12)") && count(".padding(.leading, 108)", in: plan) == 2)
        CT.checkTrue("the shipping header keeps its fixed-size subtitle (fixedSize on both axes unless stacked); only the stacked card truncates it, and the row picks its layout in one place", plan.contains(".lineLimit(1)\\n                    .fixedSize(horizontal: !stacked, vertical: !stacked)") && plan.contains("if stacked { stackedRow } else { shippingRow }"))
''', '''        CT.checkTrue("the shipping row keeps its 40 pt label, 50 pt bar, fixed-size reset label and the rows' paddings; its percent is on one line in CatIslandLayout's column (it was a literal 30 and wrapped '100%')", plan.contains(".frame(width: 40, alignment: .leading)") && plan.contains("Capsule()\\n                        .fill(Color.white.opacity(0.08))\\n                        .frame(width: 50, height: 4)") && plan.contains(".monospacedDigit()\\n                    .lineLimit(1)\\n                    .frame(width: CatIslandLayout.planPercentWidth, alignment: .trailing)\\n                Image(systemName: \\"arrow.clockwise\\")") && !plan.contains(".frame(width: 30, alignment: .trailing)") && plan.contains("Image(systemName: \\"arrow.clockwise\\")\\n                    .font(.system(size: 8))\\n                    .foregroundColor(Color(hex: \\"#6B7079\\"))\\n                Text(resetLabel(w))\\n                    .font(.system(size: 10))\\n                    .foregroundColor(Color(hex: \\"#6B7079\\"))\\n                    .fixedSize()") && plan.contains(".padding(.leading, 108)\\n            .padding(.trailing, 12)") && count(".padding(.leading, 108)", in: plan) == 2)
        CT.checkTrue("the header keeps its title on its line and its priority, lets the subtitle truncate in both layouts (no fixedSize), and has the rows' own right margin; the row picks its layout in one place", plan.contains(".lineLimit(1)\\n                    .layoutPriority(1)\\n                Text(subtitleText)") && plan.contains("Text(subtitleText)\\n                    .font(.system(size: 11))\\n                    .foregroundColor(Color(hex: \\"#8E939C\\"))\\n                    .lineLimit(1)\\n            }") && !plan.contains("fixedSize(horizontal: !stacked") && plan.contains(".padding(.leading, 108)\\n            .padding(.trailing, CatIslandLayout.planRowsTrailing)") && plan.contains("if stacked { stackedRow } else { shippingRow }"))
'''),
])
PY
```

Run: `bash scripts/test-cat-agent-list.sh 2>&1 | grep -E '✗|failed' | cut -c1-200; bash scripts/test-cat-wiring.sh 2>&1 | grep -E '✗|failed' | cut -c1-200`
Expected: FAIL: from the agent list's program `✗ the percent column is 34 pt in both rows, …`, `✗ the shipping row with its longest date label ('Thu 14:30') fits the 202 pt it has, …` and `2 test(s) failed.`; from the wiring program `✗ the shipping row keeps its 40 pt label, …`, `✗ the header keeps its title on its line and its priority, …` and `2 test(s) failed.`

- [ ] **Step 3: Write the fix**

```bash
python3 - <<'PY'
# Task 2: the plan card's layout. Run from the repository root.
def edit(path, pairs):
    s = open(path, encoding='utf-8').read()
    for was, now in pairs:
        assert s.count(was) == 1, (path, was[:70])
        s = s.replace(was, now)
    open(path, 'w', encoding='utf-8').write(s)

edit('NotchBuddy/Sources/App/CatIslandLayout.swift', [
('''    /// The Claude plan card's rows. The card is 322 pt wide; its gauge rows start 108 pt in and keep 12 pt on the right, so they have 202 pt as the card ships and 34 pt less when it is shifted
    /// for cat 2. Shipping, a row is one line (label, bar, percent, arrow, reset time), about 190 to 197 pt, which does not fit 168: in the shifted card (`stacked`) the reset time goes on a second line
    /// under the bar, so the widest line is label + bar + percent and their two gaps (the percent column is 36, not the shipping 30: \\"100%\\" is about 33 pt wide and would be cut off in 30). The stacked row in `ClaudePlanCardView.swift` reads these numbers.
    static let cardWidth = 322.0, planRowsTrailing = 12.0
    static let planLabelWidth = 40.0, planBarWidth = 50.0, planPercentWidth = 36.0, planRowSpacing = 5.0
''', '''    /// The Claude plan card's rows. The card is 322 pt wide; its gauge rows start 108 pt in and keep 12 pt on the right (the header keeps the same 12), so they have 202 pt as the card ships and 34 pt
    /// less when it is shifted for cat 2. Shipping, a row is one line (label, bar, percent, arrow, reset time), about 200 pt, which does not fit 168: in the shifted card (`stacked`) the reset time goes
    /// on a second line under the bar, so the widest line is label + bar + percent and their two gaps. The percent column is 34 pt in both rows: "100%" is about 33 pt wide, and in the 30 pt the
    /// shipping row used to have it wrapped to "100" over "%". Both rows in `ClaudePlanCardView.swift` read these numbers.
    static let cardWidth = 322.0, planRowsTrailing = 12.0
    static let planLabelWidth = 40.0, planBarWidth = 50.0, planPercentWidth = 34.0, planRowSpacing = 5.0
'''),
])

edit('NotchBuddy/Sources/App/ClaudePlanCardView.swift', [
('''    /// Two cats mode's shifted card: the rows have 34 pt less width, so each reset time goes on a second line under its bar and the subtitle truncates. False is the card as it ships.
''', '''    /// Two cats mode's shifted card: the rows have 34 pt less width, so each reset time goes on a second line under its bar. False is the card as it ships.
'''),
('''                Text("Claude plan")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                    .lineLimit(stacked ? 1 : nil)          // stacked: the title keeps its line and the subtitle gives way
                    .layoutPriority(stacked ? 1 : 0)
                Text(subtitleText)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#8E939C"))
                    .lineLimit(1)
                    .fixedSize(horizontal: !stacked, vertical: !stacked)   // stacked: the subtitle truncates instead of passing the card's edge
            }
            .padding(.top, 6)
            .padding(.leading, 108)
            .padding(.trailing, 36)
''', '''                // The title keeps its line and the subtitle gives way, with data or without: the waiting subtitle is the longest text here and used to squeeze the title out.
                Text("Claude plan")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                    .lineLimit(1)
                    .layoutPriority(1)
                Text(subtitleText)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#8E939C"))
                    .lineLimit(1)
            }
            .padding(.top, 6)
            .padding(.leading, 108)
            .padding(.trailing, CatIslandLayout.planRowsTrailing)
'''),
('''                    .monospacedDigit()
                    .frame(width: 30, alignment: .trailing)
''', '''                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(width: CatIslandLayout.planPercentWidth, alignment: .trailing)
'''),
])
PY
```

- [ ] **Step 4: Run the tests, and prove they bite**

Run: `bash scripts/test-cat-agent-list.sh 2>&1 | tail -2; bash scripts/test-cat-wiring.sh 2>&1 | tail -2`
Expected: PASS: `All tests passed.` twice.

Put the old column back for a moment: the card must not be allowed to go back to 30 pt.

Run: `cp NotchBuddy/Sources/App/CatIslandLayout.swift "${TMPDIR:-/tmp}/fixes-after-b-layout.swift"; sed -i '' 's/planPercentWidth = 34.0/planPercentWidth = 30.0/' NotchBuddy/Sources/App/CatIslandLayout.swift; bash scripts/test-cat-agent-list.sh 2>&1 | grep -E '✗|failed' | cut -c1-120; cp "${TMPDIR:-/tmp}/fixes-after-b-layout.swift" NotchBuddy/Sources/App/CatIslandLayout.swift; bash scripts/test-cat-agent-list.sh 2>&1 | tail -1`
Expected: with the column at 30 `✗ the percent column is 34 pt in both rows, …`, `✗ '100%' (about 33 pt, measured) fits that column on one line` and `2 test(s) failed.`; with it back `All tests passed.`

- [ ] **Step 5: Draw the after pictures, and say what moved**

```bash
O="${TMPDIR:-/tmp}/fixes-after-b-1"
bash scripts/render-plan-card.sh --out "$O/plan-after-ship.png"
bash scripts/render-plan-card.sh --out "$O/plan-after-ship-waiting.png" --waiting
bash scripts/render-plan-card.sh --out "$O/plan-after-stacked.png" --stacked --shift 34
bash scripts/render-plan-card.sh --out "$O/plan-after-stacked-59.png" --stacked --shift 34 --ago 59
bash scripts/render-plan-card.sh --out "$O/plan-after-stacked-waiting.png" --stacked --shift 34 --waiting
```

Expected: five `wrote … .png` lines. **Open the five pictures and say what you see to the controller.** `plan-after-ship.png`: "63%" and "100%" each on one line, the reset labels ("in 4 h 59", "Thu 14:30") a little to the right of where they were, the header ("Claude plan", "5 min ago") as before. `plan-after-ship-waiting.png`: "Claude plan" is there, with the subtitle cut after it ("Waiting for a Claud…"), and the two rows sit where they do in the card with data (about 30 pt higher than before). `plan-after-stacked.png`: as before, the percents 2 pt to the left. `plan-after-stacked-59.png`: "59 min ago" whole. `plan-after-stacked-waiting.png`: the title and "Waiting for a…". Nothing passes the red line.

Then count the pixels that differ, by region, with a small tool (kept in the scratch folder, not in the repository). The shipping card's header and its first row's label and bar must be identical to the picture before; only the percent column and what follows it move.

```bash
SHOTS="${TMPDIR:-/tmp}/fixes-after-b-shots"; mkdir -p "$SHOTS"
cat > "$SHOTS/pngdiff.swift" <<'EOF'
import AppKit

// Compares two PNGs of the same size and says how many pixels differ (by more than 2 in a colour channel), optionally only inside a rectangle x0 y0 x1 y1 (pixels).
func load(_ path: String) -> (w: Int, h: Int, px: [UInt8]) {
    let img = NSImage(contentsOfFile: path)!
    var r = CGRect(origin: .zero, size: img.size)
    let cg = img.cgImage(forProposedRect: &r, context: nil, hints: nil)!
    var px = [UInt8](repeating: 0, count: cg.width * cg.height * 4)
    let ctx = CGContext(data: &px, width: cg.width, height: cg.height, bitsPerComponent: 8, bytesPerRow: cg.width * 4, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
    ctx.draw(cg, in: CGRect(x: 0, y: 0, width: cg.width, height: cg.height))
    return (cg.width, cg.height, px)
}
let args = CommandLine.arguments, a = load(args[1]), b = load(args[2])
guard a.w == b.w && a.h == b.h else { print("sizes differ"); exit(1) }
let r = args.count >= 7 ? args[3...6].map { Int($0)! } : [0, 0, a.w, a.h]
var n = 0
for y in r[1]..<min(r[3], a.h) { for x in r[0]..<min(r[2], a.w) {
    let i = (y * a.w + x) * 4
    if (0..<3).contains(where: { abs(Int(a.px[i + $0]) - Int(b.px[i + $0])) > 2 }) { n += 1 }
} }
print("\(n) pixels differ in x \(r[0])..<\(r[2]), y \(r[1])..<\(r[3])")
EOF
swiftc -swift-version 5 "$SHOTS/pngdiff.swift" -o "$SHOTS/pngdiff"
O="${TMPDIR:-/tmp}/fixes-after-b-1"
"$SHOTS/pngdiff" "$O/plan-before-ship.png" "$O/plan-after-ship.png" 0 0 784 60
"$SHOTS/pngdiff" "$O/plan-before-ship.png" "$O/plan-after-ship.png" 216 60 420 100
"$SHOTS/pngdiff" "$O/plan-before-ship.png" "$O/plan-after-ship.png" 420 60 784 100
"$SHOTS/pngdiff" "$O/plan-before-stacked.png" "$O/plan-after-stacked.png" 0 0 784 60
"$SHOTS/pngdiff" "$O/plan-before-stacked.png" "$O/plan-after-stacked.png" 216 60 480 196
```

Expected: `0 pixels differ in x 0..<784, y 0..<60` (the shipping card's header, with data, is the same), `0 pixels differ in x 216..<420, y 60..<100` (the first row's label and bar), a number above 1000 for `x 420..<784, y 60..<100` (the percent, the arrow and the reset label moved), `0 pixels differ in x 0..<784, y 0..<60` (the stacked header, with data and five minutes) and `0 pixels differ in x 216..<480, y 60..<196` (the stacked rows' labels, bars and reset lines; only the percent's right edge moved).

- [ ] **Step 6: Build**

The card is in the GitHub build only (`#if !APPSTORE` at its one call), and `CatIslandLayout` is in both builds: Task 10 builds the App Store target too.

Run: `cd NotchBuddy && xcodegen && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: `Created project at …` and the last lines end with `** BUILD SUCCEEDED **` (a few minutes on a cold build). The build only builds: do not open the app.

Run: `git status --short`
Expected: six modified files (`NotchBuddy/Sources/App/CatIslandLayout.swift`, `NotchBuddy/Sources/App/ClaudePlanCardView.swift`, `scripts/render-plan-card.sh`, `scripts/render-plan-card.swift`, `tests/CatAgentListTests.swift` and `tests/CatWiringTests.swift`) and no regenerated project file (nothing was added).

- [ ] **Step 7: Commit**

```bash
git add NotchBuddy/Sources/App/CatIslandLayout.swift NotchBuddy/Sources/App/ClaudePlanCardView.swift scripts/render-plan-card.sh scripts/render-plan-card.swift tests/CatAgentListTests.swift tests/CatWiringTests.swift
git commit -m "fix(plan-card): 100% on one line, the title kept in the waiting state, a long subtitle whole in Two cats

The shipping row's percent column was a literal 30 pt and '100%' is about 33: it wrapped to '100' over '%'. Both rows now read CatIslandLayout.planPercentWidth,
34 pt. The header keeps its title (a line and the layout priority) and lets the subtitle truncate in both layouts, so the waiting subtitle no longer squeezes
the title out, and it has the rows' own 12 pt right margin (36 pt was room for a jump button that is hidden while the card is open), so '59 min ago' is whole
in Two cats mode. The tests measure the text with AppKit instead of estimating it, and the sheet gains --ago.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

Run: `git status --short`
Expected: nothing.

---

### Task 3: Owner checkpoint 1: the two visual fixes, before and after

No code and no commit. The session reports; the main session sends the owner the pictures and asks the questions below, then relays the owner's reply to the session.

- [ ] **Step 1: Collect the pictures**

```bash
S="${TMPDIR:-/tmp}/fixes-after-b-shots"; C="${TMPDIR:-/tmp}/fixes-after-b-1"; D=.claude/checkpoints/fixes-after-b-1
mkdir -p "$D"
cp "$S/sliders-before-560.png" "$S/sliders-after-560.png" "$S/sliders-before-460.png" "$S/sliders-after-460.png" "$D/"
for n in ship ship-waiting stacked stacked-59 stacked-waiting; do cp "$C/plan-before-$n.png" "$C/plan-after-$n.png" "$D/"; done
ls "$D" | wc -l
ls "$D"
```

Expected: `14`, then the fourteen files (`plan-after-ship-waiting.png`, `plan-after-ship.png`, `plan-after-stacked-59.png`, `plan-after-stacked-waiting.png`, `plan-after-stacked.png`, the five `plan-before-…` files, and the four `sliders-…` files). The folder is the worktree's own and is never committed.

- [ ] **Step 2: What the owner looks at**

1. **Windows, Settings → Cat → Personality** (`sliders-before-560.png` and `sliders-after-560.png`, then the same at 460, the window's minimum; the window is 560 × 680 and these are drawn at that size): is each of the six rows (Energy, Curiosity, Chattiness, Affection, Sass, Mischief) on one line now, with its high end (bouncy, nosy, talkative, cuddly, grumpy, troublemaker) after the slider? At 460 the slider is short (77 px) so that the labels fit: is that right, or would the owner rather have the labels give way (a smaller minimum width for the window, which is `lib.rs`'s call)? Nothing else in the section changed: the pictures show Motion style, This cat's motion, Personality, Collar and the rest as before. The pictures are drawn without a scrollbar; the numbers at 543 and 443 px (what a 17 px scrollbar leaves) are in the report, and they are all single-line too. **Headless Chromium on a Mac is not WebView2 on Windows:** the font is the system font here and Segoe UI there, and the owner's real-build check (Task 11) is the last word.
2. **Mac, the plan card**, shipping with data (`plan-before-ship.png` and `plan-after-ship.png`): "100%" is on one line; the reset labels moved 4 pt to the right in both rows (the percent column is 34 pt, was 30); the header and the labels and bars are pixel-identical (the report says how many pixels differ in each region: 0 in the header and in the first row's label and bar). Is that the card the owner wants?
3. **The waiting card** (`plan-before-ship-waiting.png` and `plan-after-ship-waiting.png`): the title "Claude plan" is back, the subtitle is cut ("Waiting for a Claud…"), and the two rows are about 30 pt higher, where they are in the card with data (the squeezed title had made the header tall). The alternative is to shorten the words (for example "Waiting for Claude Code"), which is a copy change the owner did not ask for: Open question 2.
4. **Two cats mode's card** (`plan-*-stacked*.png`): "59 min ago" is whole now (it was "59 min a…"), the waiting header shows more of its subtitle, and the rows are as before with the percents 2 pt to the left.

Record the owner's answers in the PR description.

---
### Task 4: Mac, an agent's config file that is a link stays a link and keeps its permissions

**Agent:** `nm-implementer`.

**Files:**
- Create: `NotchBuddy/Sources/App/ConfigFileWrite.swift`, `tests/ConfigFileWriteTests.swift`, `scripts/test-config-file-write.sh`
- Modify: `NotchBuddy/Sources/App/HookServer.swift`, `.github/workflows/build.yml`, `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` (regenerated by `xcodegen`, never by hand)

**Interfaces:**
- Consumes: `HookServer.writeJSONFile(_:to:suffix:)` (Gemini's `settings.json`, Codex's and Antigravity's `hooks.json`, inside `#if !APPSTORE`), `writeClaudeHooks()`, `writeStatusLine()` and `uninstallClaudeHooks()` (Claude Code's `~/.claude/settings.json`, in both builds), and `CT` (`tests/CatTestSupport.swift`).
- Produces: `enum ConfigFileWrite` (Foundation only): `resolved(_ url: URL) -> URL` (the file at the end of the chain of links), `backUp(_ url: URL, to backup: URL) throws` (a copy of that file's text) and `write(_ data: Data, to url: URL) throws` (an atomic write to it, its folder made if need be); the script `scripts/test-config-file-write.sh`.

**The cause, confirmed** (by a scratch program, in a temp folder). Foundation's `Data.write(to:options: .atomic)` on the path of a symbolic link does not write through it: it writes a temp file and renames it over the link, so (1) the link becomes a plain file, (2) the file it pointed at is left as it was (the user's dotfiles repo keeps the old hooks), and (3) the new file takes the link's own permissions, 0755 on macOS, so a 0600 `settings.json` that may hold keys becomes world-readable and executable. A plain file is fine: an atomic write keeps the mode of the file it replaces (0600, 0640 and 0755 came back unchanged). And `FileManager.copyItem` on a link copies the link, so the **dated backup of a symlinked config is a second link to the same file**, which the write then changes: no backup at all. The fix is to resolve the link first and do both to the file at the end of the chain. `resolvingSymlinksInPath()` is not enough (a link to a file that is not there yet comes back unresolved), so `resolved` walks the chain itself, reads each relative link from the folder it really sits in (`~/.claude` may itself be a link), and stops after 32 links.

**The scope, decided** (Open question 1): `writeJSONFile` is the three files the owner named, and the same defect is in the four writes of Claude Code's own `settings.json` (`writeClaudeHooks`, `writeStatusLine` and `uninstallClaudeHooks`, and the backup of the first two), which is the file most likely to be a link. All go through `ConfigFileWrite`. The App Store build's two direct writes are left (its sandbox grant is a folder the user picked, and a link's target may be outside it: not testable here).

**The Windows twin has no such bug, and this task changes nothing under `windows/`.** `hooks::replace_file` (shared by Claude Code, Gemini CLI and Antigravity) writes to `std::fs::canonicalize(path)`, `write_like` gives the new file the original's permissions, its backup is `std::fs::copy` (which follows a link and copies the text), and `a_symlinked_config_file_stays_a_symlink_and_its_target_is_updated` and `rewriting_settings_never_widens_its_permissions` say so. Step 7 runs those two tests once.

- [ ] **Step 1: Watch the bug**

A scratch program, kept in the temp folder and not in the repository, shows the three effects in a folder of its own. It does not touch any real config file.

```bash
P="${TMPDIR:-/tmp}/fixes-after-b-cfg-probe"; mkdir -p "$P"
cat > "$P/probe.swift" <<'EOF'
import Foundation

// A scratch probe, not part of the repository: what Foundation does to a symbolic link. Everything happens in a folder of its own under the temp folder.
let fm = FileManager.default
let dir = fm.temporaryDirectory.appendingPathComponent("notchmeow-config-probe-\(UUID().uuidString)")
func mode(_ u: URL) -> String { String(((try? fm.attributesOfItem(atPath: u.path))?[.posixPermissions] as? NSNumber)?.intValue ?? -1, radix: 8) }
func isLink(_ u: URL) -> Bool { (try? fm.attributesOfItem(atPath: u.path))?[.type] as? FileAttributeType == .typeSymbolicLink }
let target = dir.appendingPathComponent("dotfiles/settings.json"), link = dir.appendingPathComponent("home/settings.json")
let backup = dir.appendingPathComponent("home/settings.json.bak"), plain = dir.appendingPathComponent("plain.json")
try fm.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
try fm.createDirectory(at: link.deletingLastPathComponent(), withIntermediateDirectories: true)
try Data("{\"old\":1}".utf8).write(to: target)
try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
try fm.createSymbolicLink(atPath: link.path, withDestinationPath: target.path)
try fm.copyItem(at: link, to: backup)
print("the backup of a link is itself a link: \(isLink(backup))")
try Data("{\"new\":1}".utf8).write(to: link, options: .atomic)
print("after an atomic write to the link: it is still a link: \(isLink(link)); the file it pointed at says \(String(data: try Data(contentsOf: target), encoding: .utf8)!); the new file's mode is \(mode(link))")
try Data("{}".utf8).write(to: plain)
try fm.setAttributes([.posixPermissions: 0o600], ofItemAtPath: plain.path)
try Data("{\"a\":1}".utf8).write(to: plain, options: .atomic)
print("an atomic write to a plain file of mode 600 keeps its mode: \(mode(plain))")
try? fm.removeItem(at: dir)
EOF
swiftc -swift-version 5 "$P/probe.swift" -o "$P/probe" && "$P/probe"
```

Expected: three lines: `the backup of a link is itself a link: true`, `after an atomic write to the link: it is still a link: false; the file it pointed at says {"old":1}; the new file's mode is 755` and `an atomic write to a plain file of mode 600 keeps its mode: 600`.

- [ ] **Step 2: Write the failing test and its script**

The test makes every file in a folder of its own (`NM_CONFIG_TEST_DIR`, set by the script to a `mktemp` folder), refuses to run without it, and never reads a real `~/.claude`, `~/.gemini` or `~/.codex`. Its last section pins in the source that the four writers use `ConfigFileWrite` in the order backup then write, and that the flow the repo's rule asks for is still there: the preview builds the data first, the write takes only that pending data, and the backup is dated.

```bash
cat > tests/ConfigFileWriteTests.swift <<'EOF'
import Foundation

// ConfigFileWrite: how NotchMeow writes another tool's config file (Claude Code's settings.json, Gemini's settings.json, Codex's and Antigravity's hooks.json). Every file here is in a folder
// of this script's own (NM_CONFIG_TEST_DIR, made by scripts/test-config-file-write.sh): the user's real ~/.claude, ~/.gemini and ~/.codex are never read or written.

@main
@MainActor
enum ConfigFileWriteTests {
    static let fm = FileManager.default
    static var base = URL(fileURLWithPath: "/")

    static func folder(_ name: String) throws -> URL {
        let dir = base.appendingPathComponent(name)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static func put(_ text: String, at url: URL, mode: Int = 0o644) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    }
    static func text(_ url: URL) -> String { (try? String(contentsOf: url, encoding: .utf8)) ?? "(unreadable)" }
    static func mode(_ url: URL) -> Int { ((try? fm.attributesOfItem(atPath: url.path))?[.posixPermissions] as? NSNumber)?.intValue ?? -1 }
    static func isLink(_ url: URL) -> Bool { (try? fm.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType == .typeSymbolicLink }
    static func link(_ at: URL, to destination: String) throws {
        try fm.createDirectory(at: at.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: at.path, withDestinationPath: destination)
    }
    /// Both sides of a path comparison go through the same normalising call (the temp folder sits behind /var, a link to /private/var).
    static func same(_ a: URL, _ b: URL) -> Bool { a.resolvingSymlinksInPath().path == b.resolvingSymlinksInPath().path }

    static func main() {
        CT.section("the folder of this test")
        guard let path = ProcessInfo.processInfo.environment["NM_CONFIG_TEST_DIR"], path.contains("notchmeow-config-write"), !path.contains("/.claude"), !path.contains("/.gemini"), !path.contains("/.codex") else {
            print("NM_CONFIG_TEST_DIR is not a temp folder of this script: run this through scripts/test-config-file-write.sh")
            exit(2)
        }
        base = URL(fileURLWithPath: path)
        CT.checkTrue("it is a folder made for this run", (try? fm.createDirectory(at: base, withIntermediateDirectories: true)) != nil)

        func scenario(_ name: String, _ body: (URL) throws -> Void) {
            CT.section(name)
            do { try body(try folder(String(name.prefix(24)).filter { $0.isLetter || $0.isNumber })) } catch { CT.checkTrue("the scenario ran: \(error)", false) }
        }

        scenario("a plain file: replaced, and its permissions kept") { dir in
            for want in [0o600, 0o640, 0o644, 0o755] {
                let file = dir.appendingPathComponent("plain-\(want).json")
                try put("{\"old\":1}", at: file, mode: want)
                try ConfigFileWrite.write(Data("{\"new\":1}".utf8), to: file)
                CT.check("text \(String(want, radix: 8)): the new text", text(file), "{\"new\":1}")
                CT.check("mode \(String(want, radix: 8)): the same", mode(file), want)
            }
            CT.check("resolving a plain file is that file", same(ConfigFileWrite.resolved(dir.appendingPathComponent("plain-600.json")), dir.appendingPathComponent("plain-600.json")), true)
        }

        scenario("a file that is not there yet: made, with its folder") { dir in
            let file = dir.appendingPathComponent("new/deeper/settings.json")
            try ConfigFileWrite.write(Data("{}".utf8), to: file)
            CT.check("written", text(file), "{}")
            CT.checkTrue("a new file is readable by its owner", mode(file) & 0o600 == 0o600)
        }

        scenario("a symbolic link: it stays a link, the file it points at changes, with its permissions") { dir in
            let target = dir.appendingPathComponent("dotfiles/settings.json"), settings = dir.appendingPathComponent("home/.cfg/settings.json")
            try put("{\"old\":1}", at: target, mode: 0o600)
            try link(settings, to: target.path)
            try ConfigFileWrite.write(Data("{\"new\":1}".utf8), to: settings)
            CT.check("the link is still a link", isLink(settings), true)
            CT.check("the file it points at has the new text", text(target), "{\"new\":1}")
            CT.check("the file it points at keeps 0600 (a link's own mode is 0755)", mode(target), 0o600)
            CT.check("reading through the link gives the new text", text(settings), "{\"new\":1}")
        }

        scenario("the dated backup of a link holds the file's text, not a second link") { dir in
            let target = dir.appendingPathComponent("dotfiles/hooks.json"), settings = dir.appendingPathComponent("home/hooks.json"), backup = dir.appendingPathComponent("home/hooks.json.bak-20261008-1200")
            try put("{\"before\":1}", at: target, mode: 0o600)
            try link(settings, to: target.path)
            try ConfigFileWrite.backUp(settings, to: backup)
            try ConfigFileWrite.write(Data("{\"after\":1}".utf8), to: settings)
            CT.check("the backup is a file, not a link", isLink(backup), false)
            CT.check("it still holds the text from before the write", text(backup), "{\"before\":1}")
            CT.check("and the write changed the file the link points at", text(target), "{\"after\":1}")
            CT.check("the backup of a plain file is a copy too", try { let f = dir.appendingPathComponent("plain.json"), b = dir.appendingPathComponent("plain.json.bak"); try put("{\"p\":1}", at: f); try ConfigFileWrite.backUp(f, to: b); return text(b) }(), "{\"p\":1}")
        }

        scenario("a relative link, a chain of links and a link through a linked folder") { dir in
            let shared = dir.appendingPathComponent("shared/settings.json")
            try put("{\"old\":1}", at: shared, mode: 0o640)
            let relative = dir.appendingPathComponent("home/.cfg/settings.json")
            try link(relative, to: "../../shared/settings.json")
            CT.check("a relative link resolves to its file", same(ConfigFileWrite.resolved(relative), shared), true)
            let chain = dir.appendingPathComponent("home/chain.json"), middle = dir.appendingPathComponent("home/middle.json")
            try link(middle, to: relative.path)
            try link(chain, to: "middle.json")
            CT.check("a chain of two links resolves to the last file", same(ConfigFileWrite.resolved(chain), shared), true)
            try ConfigFileWrite.write(Data("{\"new\":1}".utf8), to: chain)
            CT.check("both links stay links and the shared file changes, with 0640", [isLink(chain), isLink(middle), isLink(relative), text(shared) == "{\"new\":1}", mode(shared) == 0o640], [true, true, true, true, true])
            // ~/.claude is itself a link to another folder, and settings.json in it is a relative link: the link is read from the real folder, not from the path it was reached through.
            let store = dir.appendingPathComponent("store/claude/settings.json"), other = dir.appendingPathComponent("store/shared/settings.json"), home = dir.appendingPathComponent("home2/.claude")
            try put("{\"viaDir\":1}", at: other, mode: 0o600)
            try link(store, to: "../shared/settings.json")
            try link(home, to: dir.appendingPathComponent("store/claude").path)
            CT.check("through a linked folder", same(ConfigFileWrite.resolved(home.appendingPathComponent("settings.json")), other), true)
            try ConfigFileWrite.write(Data("{\"viaDir\":2}".utf8), to: home.appendingPathComponent("settings.json"))
            CT.check("the file at the end changes", text(other), "{\"viaDir\":2}")
        }

        scenario("a link to a file that is not there: the file is made where the link points") { dir in
            let target = dir.appendingPathComponent("elsewhere/not-yet/settings.json"), settings = dir.appendingPathComponent("home/settings.json")
            try link(settings, to: target.path)
            try ConfigFileWrite.write(Data("{\"first\":1}".utf8), to: settings)
            CT.check("the link is still a link, and the file is where it points", [isLink(settings), text(target) == "{\"first\":1}"], [true, true])
        }

        scenario("a loop of links ends") { dir in
            let a = dir.appendingPathComponent("home/a.json"), b = dir.appendingPathComponent("home/b.json")
            try link(a, to: "b.json")
            try link(b, to: "a.json")
            _ = ConfigFileWrite.resolved(a)
            CT.checkTrue("resolving a loop returns", true)
        }

        scenario("the app's writers use it: the source says so, and the rule of a backup, a merge, a diff and a confirm still holds") { _ in
            let hook = (try? String(contentsOfFile: "NotchBuddy/Sources/App/HookServer.swift", encoding: .utf8)) ?? ""
            func count(_ needle: String) -> Int { hook.components(separatedBy: needle).count - 1 }
            func body(of signature: String) -> String {
                guard let start = hook.range(of: signature) else { return "" }
                let rest = hook[start.upperBound...]
                return String(rest.prefix(upTo: rest.range(of: "\n    }\n")?.lowerBound ?? rest.endIndex))
            }
            CT.checkTrue("the source was read", hook.contains("func writeJSONFile"))
            let json = body(of: "private func writeJSONFile(_ data: Data, to url: URL, suffix: String) throws {")
            CT.checkTrue("writeJSONFile (Gemini's settings, Codex's and Antigravity's hooks) backs up and writes through ConfigFileWrite, in that order, and no longer writes atomically to the link", !json.isEmpty && json.contains("try ConfigFileWrite.backUp(url, to: backupURL)") && json.contains("try ConfigFileWrite.write(data, to: url)") && !json.contains(".atomic") && !json.contains("copyItem") && json.range(of: "backUp")!.lowerBound < json.range(of: "ConfigFileWrite.write")!.lowerBound)
            let hooksWrite = body(of: "func writeClaudeHooks() throws {"), statusWrite = body(of: "func writeStatusLine() throws {"), uninstall = body(of: "func uninstallClaudeHooks() throws {")
            CT.checkTrue("Claude Code's installer writes only what the user confirmed (the preview's pending data), after a dated backup, through ConfigFileWrite", hooksWrite.contains("guard let data = _pendingHooksData else { return }") && hooksWrite.contains("settings.json.bak-") && hooksWrite.contains("try? ConfigFileWrite.backUp(settingsURL, to: backupURL)") && hooksWrite.contains("try ConfigFileWrite.write(data, to: settingsURL)") && hooksWrite.range(of: "backUp")!.lowerBound < hooksWrite.range(of: "ConfigFileWrite.write")!.lowerBound && !hooksWrite.contains(".atomic"))
            CT.checkTrue("so does the plan gauge's status line writer", statusWrite.contains("guard let data = _pendingStatusLineData else { return }") && statusWrite.contains("settings.json.bak-") && statusWrite.contains("try? ConfigFileWrite.backUp(settingsURL, to: backupURL)") && statusWrite.contains("try ConfigFileWrite.write(data, to: settingsURL)") && statusWrite.range(of: "backUp")!.lowerBound < statusWrite.range(of: "ConfigFileWrite.write")!.lowerBound)
            CT.checkTrue("and the uninstall", uninstall.contains("try ConfigFileWrite.write(newData, to: settingsURL)") && !uninstall.contains(".atomic"))
            CT.check("the preview still builds the data before anything is written (the install's and the status line's)", [hook.contains("func previewClaudeHooks() throws -> String {") && hook.contains("_pendingHooksData = data"), hook.contains("func previewStatusLine(install: Bool) throws -> String {") && hook.contains("_pendingStatusLineData = data")], [true, true])
            CT.check("the App Store build's own two writes (its sandbox folder grant) are as they were", count("newData.write(to: settingsURL, options: .atomic)") + count("try data.write(to: settingsURL, options: .atomic)"), 2)
        }

        CT.finish()
    }
}
EOF
cat > scripts/test-config-file-write.sh <<'EOF'
#!/usr/bin/env bash
# ConfigFileWrite: writing an agent's config file through a symbolic link (the link stays, the file it points at changes, its permissions are kept, the dated backup is a copy), all in a
# temp folder of this script's own, and the source pins that the app's writers use it. Nothing reads or writes the real ~/.claude, ~/.gemini or ~/.codex.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-config-write.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"                 # tests never write to ~/Library/Logs
export NM_CONFIG_TEST_DIR="$TEST_DIR/files"        # every config file of the test lives here

swiftc -swift-version 6 \
    NotchBuddy/Sources/App/ConfigFileWrite.swift \
    tests/CatTestSupport.swift tests/ConfigFileWriteTests.swift \
    -o "$TEST_DIR/config-file-write-tests"
"$TEST_DIR/config-file-write-tests"
EOF
chmod +x scripts/test-config-file-write.sh
```

Run: `bash scripts/test-config-file-write.sh 2>&1 | tail -3`
Expected: FAIL: `error opening input file 'NotchBuddy/Sources/App/ConfigFileWrite.swift'` (the file does not exist yet).

- [ ] **Step 3: Write `ConfigFileWrite`**

```bash
cat > NotchBuddy/Sources/App/ConfigFileWrite.swift <<'EOF'
import Foundation

// How NotchMeow writes another tool's config file: Claude Code's settings.json, Gemini's settings.json, Codex's and Antigravity's hooks.json. A dotfiles setup often makes such a file a symbolic
// link, and Foundation's atomic write replaces a link with a plain file (with the link's own permissions, 0755) and leaves the file it pointed at as it was. So a write goes to the file the link
// points at, which keeps the link and that file's permissions, and a dated backup holds that file's text, not a second link to it that the write would then change. Foundation only.

enum ConfigFileWrite {
    /// The file a write to `url` changes: `url` itself, or the file at the end of its chain of symbolic links (a link to a file that is not there yet ends at the place it points to). A relative link is
    /// read from the folder it really sits in, and the chain is cut after 32 links, which also ends a loop.
    static func resolved(_ url: URL) -> URL {
        var url = url
        for _ in 0..<32 {
            let dir = url.deletingLastPathComponent().resolvingSymlinksInPath()
            url = dir.appendingPathComponent(url.lastPathComponent)
            guard let to = try? FileManager.default.destinationOfSymbolicLink(atPath: url.path) else { return url }
            url = URL(fileURLWithPath: to, relativeTo: dir).absoluteURL.standardizedFileURL
        }
        return url
    }

    /// Copies the file `url` stands for to `backup`: its text, never a link to it. Throws like `FileManager.copyItem`.
    static func backUp(_ url: URL, to backup: URL) throws {
        try FileManager.default.copyItem(at: resolved(url), to: backup)
    }

    /// Replaces the file `url` stands for with `data`, atomically, making its folder if need be. An atomic write to a plain file keeps that file's permissions, which is why it is made to the file at the
    /// end of the links and not to the link.
    static func write(_ data: Data, to url: URL) throws {
        let target = resolved(url)
        try FileManager.default.createDirectory(at: target.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: target, options: .atomic)
    }
}
EOF
```

Run: `bash scripts/test-config-file-write.sh 2>&1 | grep -E '✗|failed|passed' | cut -c1-150`
Expected: FAIL, in the source pins only (the scenarios with links all pass; the hook server is not changed yet): `✗ writeJSONFile (Gemini's settings, Codex's and Antigravity's hooks) backs up and writes through ConfigFileWrite, …`, `✗ Claude Code's installer writes only what the user confirmed …`, `✗ so does the plan gauge's status line writer`, `✗ and the uninstall` and `✗ the App Store build's own two writes (its sandbox folder grant) are as they were`, then `5 test(s) failed.`

- [ ] **Step 4: Make the four writers use it**

Each edit replaces the copy and the atomic write and nothing else. `ConfigFileWrite.write` makes the folder, so the two `createDirectory` calls that came with the writes go. The backup of the two Claude Code writers stays a best-effort `try?`, as it was; `writeJSONFile`'s still throws on failure ("Could not back up …").

```bash
python3 - <<'PY'
# Task 4: the four writers of an agent's config file. Run from the repository root.
def edit(path, pairs):
    s = open(path, encoding='utf-8').read()
    for was, now in pairs:
        assert s.count(was) == 1, (path, was[:70])
        s = s.replace(was, now)
    open(path, 'w', encoding='utf-8').write(s)

edit('NotchBuddy/Sources/App/HookServer.swift', [
('''        try? FileManager.default.copyItem(at: settingsURL, to: backupURL)
        try? FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(),
                                                  withIntermediateDirectories: true)
        try data.write(to: settingsURL, options: .atomic)
        _pendingHooksData = nil
''', '''        try? ConfigFileWrite.backUp(settingsURL, to: backupURL)
        try ConfigFileWrite.write(data, to: settingsURL)
        _pendingHooksData = nil
'''),
('''        let newData = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try newData.write(to: settingsURL, options: .atomic)
    }

    // MARK: - Claude plan status line installer
''', '''        let newData = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try ConfigFileWrite.write(newData, to: settingsURL)
    }

    // MARK: - Claude plan status line installer
'''),
('''        try? FileManager.default.copyItem(at: settingsURL, to: backupURL)
        try? FileManager.default.createDirectory(at: settingsURL.deletingLastPathComponent(),
                                                  withIntermediateDirectories: true)
        try data.write(to: settingsURL, options: .atomic)
        // Commit side effects only after successful write
''', '''        try? ConfigFileWrite.backUp(settingsURL, to: backupURL)
        try ConfigFileWrite.write(data, to: settingsURL)
        // Commit side effects only after successful write
'''),
('''    /// Backs up the existing file (throws on failure), creates parent dirs, then atomically writes.
    private func writeJSONFile(_ data: Data, to url: URL, suffix: String) throws {''', '''    /// Backs up the existing file (throws on failure), creates parent dirs, then atomically writes. A symbolic link stays a link: the backup holds the text of the file it points at, and the write goes to
    /// that file and keeps its permissions (`ConfigFileWrite`).
    private func writeJSONFile(_ data: Data, to url: URL, suffix: String) throws {'''),
('''            do { try fm.copyItem(at: url, to: backupURL) }
            catch {
                throw NSError(domain: "NotchMeow", code: 3, userInfo: [
                    NSLocalizedDescriptionKey: "Could not back up \\(url.lastPathComponent): \\(error.localizedDescription)"
                ])
            }
        }
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try data.write(to: url, options: .atomic)
    }
''', '''            do { try ConfigFileWrite.backUp(url, to: backupURL) }
            catch {
                throw NSError(domain: "NotchMeow", code: 3, userInfo: [
                    NSLocalizedDescriptionKey: "Could not back up \\(url.lastPathComponent): \\(error.localizedDescription)"
                ])
            }
        }
        try ConfigFileWrite.write(data, to: url)
    }
'''),
])
PY
```

Run: `bash scripts/test-config-file-write.sh 2>&1 | tail -2`
Expected: PASS: `All tests passed.`

- [ ] **Step 5: Prove the tests bite**

Make `write` go to the link again, then make `backUp` copy the link again, one at a time.

Run: `cp NotchBuddy/Sources/App/ConfigFileWrite.swift "${TMPDIR:-/tmp}/fixes-after-b-cfw.swift"; sed -i '' 's/let target = resolved(url)/let target = url/' NotchBuddy/Sources/App/ConfigFileWrite.swift; bash scripts/test-config-file-write.sh 2>&1 | grep -E '✗|failed' | cut -c1-110; cp "${TMPDIR:-/tmp}/fixes-after-b-cfw.swift" NotchBuddy/Sources/App/ConfigFileWrite.swift`
Expected: with `write` going to the link, six `✗` lines (`the link is still a link`, `the file it points at has the new text`, `and the write changed the file the link points at`, `both links stay links and the shared file changes, with 0640`, `the file at the end changes`, `the link is still a link, and the file is where it points`) and `6 test(s) failed.`

Run: `sed -i '' 's/copyItem(at: resolved(url), to: backup)/copyItem(at: url, to: backup)/' NotchBuddy/Sources/App/ConfigFileWrite.swift; bash scripts/test-config-file-write.sh 2>&1 | grep -E '✗|failed' | cut -c1-110; cp "${TMPDIR:-/tmp}/fixes-after-b-cfw.swift" NotchBuddy/Sources/App/ConfigFileWrite.swift; bash scripts/test-config-file-write.sh 2>&1 | tail -1`
Expected: with the backup copying the link `✗ the backup is a file, not a link`, `✗ it still holds the text from before the write` and `2 test(s) failed.`; with the file put back `All tests passed.`

- [ ] **Step 6: One CI step, the project, and the builds**

```bash
python3 - <<'PY'
# Task 4: one CI step for the new test. Run from the repository root.
def edit(path, pairs):
    s = open(path, encoding='utf-8').read()
    for was, now in pairs:
        assert s.count(was) == 1, (path, was[:70])
        s = s.replace(was, now)
    open(path, 'w', encoding='utf-8').write(s)
edit('.github/workflows/build.yml', [
('''      - name: Keyboard shortcut logic
        run: bash scripts/test-shortcuts.sh
''', '''      - name: Keyboard shortcut logic
        run: bash scripts/test-shortcuts.sh

      - name: Config file write (symbolic links, permissions, backups)
        run: bash scripts/test-config-file-write.sh
'''),
])
PY
cd NotchBuddy && xcodegen 2>&1 | tail -1 && cd ..
git diff --stat -- NotchBuddy/NotchBuddy.xcodeproj | tail -1
```

Expected: `Created project at …/NotchBuddy/NotchBuddy.xcodeproj` and ` 1 file changed, 6 insertions(+)` (the new file in the project).

Run: `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: the last lines end with `** BUILD SUCCEEDED **`.

Run: `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchMeowAppStore -configuration Debug -derivedDataPath NotchBuddy/build/store build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | tail -3`
Expected: the last lines end with `** BUILD SUCCEEDED **` (the hook server's file is in both builds).

- [ ] **Step 7: Confirm the Windows twin, once**

Two tests that already exist run in the Linux container, with this plan's own target directory. `--offline` makes cargo refuse to download a crate. The first run compiles the workspace into that directory (some minutes); the script also builds the relay into its shared volume, as it always does.

Run: `docker image inspect notchmeow-linux-dev >/dev/null && bash windows/scripts/cargo-linux.sh test --offline -p notchmeow --target-dir /repo/windows/target/fixes-after-b -- a_symlinked_config_file rewriting_settings_never_widens 2>&1 | grep -E "^test |^test result: ok. [1-9]"`
Expected: `test hooks::tests::rewriting_settings_never_widens_its_permissions ... ok`, `test agent_hooks::tests::a_symlinked_config_file_stays_a_symlink_and_its_target_is_updated ... ok` and `test result: ok. 2 passed; 0 failed; 0 ignored; 0 measured; 244 filtered out`. If the image is missing or the daemon is down, say so and skip this step: the script would build the image.

- [ ] **Step 8: Commit**

```bash
git add NotchBuddy/Sources/App/ConfigFileWrite.swift NotchBuddy/Sources/App/HookServer.swift tests/ConfigFileWriteTests.swift scripts/test-config-file-write.sh .github/workflows/build.yml NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -m "fix(config): a symbolic-linked agent config stays a link, and its target keeps its permissions

Foundation's atomic write replaced a link with a plain file that took the link's 0755 mode and left the file it pointed at as it was, and the dated backup of a
link was a second link to the same file. ConfigFileWrite resolves the chain of links (a relative link is read from the folder it really sits in, a link to nothing
ends where it points, a loop ends after 32) and backs up and writes the file at the end of it, which keeps the link and the file's permissions. Gemini's settings.json,
Codex's and Antigravity's hooks.json and Claude Code's settings.json (install, status line, uninstall) use it; the preview, the confirm and the dated backup are
as they were, and a test pins each in the source. The test works only in a temp folder. The App Store build's two direct writes are left. The Windows twin is already
right (replace_file canonicalises and keeps the mode).

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

Run: `git status --short`
Expected: nothing.

---

### Task 5: Docs, the cats in `SPEC.md`, the stale lines and the changelog for A and B

**Agent:** `nm-implementer-light`. Everything is given in full; the scripts assert that each anchor occurs exactly once.

**Files:**
- Modify: `docs/SPEC.md` (French), `README.md`, `CHANGELOG.md`, `CLAUDE.md` (one word, with the owner's OK)

**What is changed, and what is not.** The names Coucou and Mochi are reserved and must not remain as NotchMeow's identity; credit to the original project stays. `docs/SPEC.md` is the inherited French specification of the island, and these are its stale cat passages: the line that says the values come from `reference/notch-buddy.html` (constants `PISTES` and the `Bot` class, a file that is not in the repository: the island's values still come from it, the cats' from `design/prototype/notchmeow.html` and `cat-core.js`); the no-notch line ("Mochi visible au centre"); **all of §7** ("Le personnage : Mochi", the old Mochi's constants: its body, colours, cheeks and eyes, a gaze with `tanh(dx/260)` where the cats' is over 240 px, and canvas sizes); the menu bar icon ("silhouette du Mochi"; it is Momo's head, as `scripts/gen-icons.swift` draws it); the plan card ("Grand Mochi prend la couleur de l'usage"); and milestone M2 ("port de `Bot` (Mochi)"). §7 keeps its tables of states and emotes (the states' colours and tints are `cat-core.js`'s, which the dry run compared) and gains the display modes, the kittens and the small eyes, pointing to `docs/CAT-CONTRACT.md`; §10 gains the Cat section of Settings, which it did not list. The French word "bonhomme", used as "the character", is left everywhere else. `docs/INTEGRATIONS.md` has no Mochi or Coucou and is not changed. `windows/README.md` has nothing stale about the cats.

- [ ] **Step 1: `docs/SPEC.md`**

```bash
python3 - <<'PY'
# Task 5, step 1: SPEC.md, the cats. Run from the repository root. Every anchor must occur exactly once.
def edit(path, pairs):
    s = open(path, encoding='utf-8').read()
    for was, now in pairs:
        assert s.count(was) == 1, (path, was[:70])
        s = s.replace(was, now)
    open(path, 'w', encoding='utf-8').write(s)

def replace_between(path, start, end, now):
    s = open(path, encoding='utf-8').read()
    assert s.count(start) == 1 and s.count(end) == 1, (path, start[:50], end[:50])
    i, j = s.index(start), s.index(end)
    assert i < j
    open(path, 'w', encoding='utf-8').write(s[:i] + now + s[j:])

SECTION_7 = '''## 7. Les personnages : Shrimpy, Momo et les autres chats

Le personnage de NotchMeow est un **chat**, dessiné entièrement en code (`Canvas` dans `TimelineView(.animation(paused:))`), jamais en image. Tout ce qui s'écrit en nombres (pelages, pose, déformation du visage, mouvement, personnalité, règles du sommeil et du salut, réglages stockés, chats des agents, chatons, petits yeux) est dans `design/prototype/cat-core.js`, qui tranche en cas de désaccord. `docs/CAT-CONTRACT.md` le décrit et `tests/fixtures/cat/` en est tiré ; l'app Mac (`Cat*.swift`, `Personality.swift`, `MotionProfiles.swift`) et l'app Windows et Linux (`windows/src/cat/`) le réimplémentent chacune et se testent contre ces fixtures. L'aspect se juge à l'œil contre `design/prototype/notchmeow.html`, qui dessine avec le même noyau.

- **Les chats.** Shrimpy (tigré brun à poil long) et Momo (smoking gris et blanc) sont les chats par défaut. Quatorze autres pelages du même patron se choisissent dans Réglages → Cat : Ginger, Midnight, Latte, Patches, Blue, Snow, Oreo, Mocha, Silver, Cloud, Leo, Button, Puff et Noodle, soit 16 en tout. Leurs identifiants (`shrimpy`, `momo`, `ginger`, …) sont figés, parce qu'ils sont stockés ; un identifiant inconnu donne Shrimpy.
- **Le visage.** Les yeux sont projetés sur une sphère (yaw, pitch, roll) avec raccourci de perspective et découpés par la silhouette de la tête : c'est ce qui donne les roulades (les yeux sortent par le haut et reviennent par le bas). Le regard suit la souris avec retard, le clignement est aléatoire, avec des doubles clignements. Les oreilles et les moustaches suivent la tête, et la bouche change avec l'état et l'émote.
- **Le mouvement.** Deux styles, au choix dans Réglages → Cat : **Playful** (le langage du corps du chat : oreilles qui bougent, clignements lents, affût, grand bâillement) et **Classic** (les timings d'origine). Six curseurs de personnalité (Energy, Curiosity, Chattiness, Affection, Sass, Mischief) et six préréglages modulent le mouvement. Après dix minutes sans agent en route, le chat s'endort ; un événement, un survol ou un clic le réveille, sauf pendant une approbation ou une question, où il ne dort jamais.
- **Le collier et les poils.** Le chat peut porter un **collier** à la couleur de l'agent qu'il suit (bande et plaque, bande, foulard, ou aucun : aucun par défaut), et des **poils** tracés en traits fins sur le gros chat (éteints par défaut).
- **Les petits chats.** Les chats des pastilles, de la grille 2×2 et des chatons utilisent le même moteur, avec des badges réduits ; le collier y porte la couleur de l'agent. Sous un diamètre de 28, les yeux au repos sont de **petits yeux colorés** (un iris aux couleurs du pelage, une pupille en fente, un reflet, un fin liseré) à la place des pilules d'encre ; les formes d'expression (contents, spirales, plats…) restent à l'encre. Midnight, Oreo et Mocha, et leurs chatons, ont à la place un iris plat de la plus claire de leurs deux couleurs, sans liseré.

### Modes d'affichage, chats des agents et chatons

Réglages → Cat → **Display** choisit comment les chats se partagent l'île, avec une petite image animée du notch compact dans le mode choisi (le contrat : `docs/CAT-CONTRACT.md`, « Display modes, agent coats, kittens and small eyes »). Le chat choisi dans Réglages → Cat s'appelle le **Main cat**.

- **One cat** (par défaut) : le Main cat partout, comme toujours.
- **A cat for each agent** : le gros chat est celui de l'agent en focus (le Main cat quand le focus est une intégration ou rien), et chaque pastille d'agent porte le chat de son agent. Claude Code est Shrimpy et Codex est Momo ; tout autre agent reçoit, la première fois qu'on le voit, un pelage tiré au hasard que ni un autre agent ni le Main cat ne porte déjà, et le garde. « Cats for your agents » les liste, avec un menu de pelage, un dé pour un nouveau pelage au hasard et **Reset to defaults**.
- **Two cats** : une paire (Shrimpy et Momo par défaut, au choix). Le chat 1 est le gros chat et montre l'agent en focus ; le chat 2 montre l'autre agent le plus occupé (d'abord un agent qui attend ta réponse, puis une erreur, puis un travail en cours). Cet agent quitte la rangée de pastilles et la grille, et toucher le chat 2 met son agent en focus dans la vue d'ensemble. Compact : deux chats Ø 20, à 30 et 54 pt du bord gauche de l'île ; vue d'ensemble : Ø 58 et Ø 46, côte à côte.

Un **sous-agent** de Claude Code (ou de Codex, sur Mac) est un **chaton** du chat de son agent : il apparaît à côté de ce chat au `SubagentStart`, montre son propre état (au travail, en recherche, en attente d'une approbation) et part avec un clin d'œil content au `SubagentStop`. Au plus 8 par agent ; aucun n'est enregistré. Les règles (événements, ordre, places, minuterie de sommeil) sont dans `INTEGRATIONS.md`, « Sous-agents : les chatons », et dans le contrat.

Les états ci-dessous, avec leurs couleurs et leurs teintes, sont ceux du contrat (`STATES`, `COL` et `TINT` de `cat-core.js`).

'''

replace_between('docs/SPEC.md', '## 7. Le personnage : Mochi', '### États (`STATES`)', SECTION_7)

edit('docs/SPEC.md', [
('''Toutes les mesures sont en points macOS. Les valeurs viennent de `reference/notch-buddy.html` (constantes `NW`, `NH`, `EW`, `VIEWS`, `STATES`, `EMOTES`, `PISTES`, `AGENTS`, classe `Bot`). En cas de doute, relire le code du prototype.''',
 '''Toutes les mesures sont en points macOS. Les valeurs de l'île viennent du prototype hérité `reference/notch-buddy.html` (constantes `NW`, `NH`, `EW`, `VIEWS`, `STATES`, `EMOTES`, `AGENTS`), qui n'est plus dans le dépôt ; celles des chats viennent de `design/prototype/notchmeow.html` et de `design/prototype/cat-core.js` (voir §7 et `docs/CAT-CONTRACT.md`). En cas de doute, relire le code du prototype.'''),
('''avec Mochi visible au centre et son animation en pause''', '''avec le gros chat visible au centre et son animation en pause'''),
('''(icône : silhouette du Mochi, monochrome)''', '''(icône : la tête de Momo en silhouette, monochrome, dessinée par le moteur des chats)'''),
('''Grand Mochi prend la couleur de l'usage quand `showingPlanDetail == true`.''', '''Le gros chat prend la couleur de l'usage (celle de son collier, si le collier est activé) quand `showingPlanDetail == true`.'''),
('''- **M2 Personnage** : port de `Bot` (Mochi), tous les états et émotes, mini-bonhommes, halo, badges, particules, mains. Pause quand masqué.''',
 '''- **M2 Personnage** : les chats (Shrimpy, Momo et les autres pelages, voir §7), tous les états et émotes, petits chats, halo, badges, particules, mains. Pause quand masqué.'''),
('''- **Shortcuts** *(macOS)* : raccourcis globaux (un interrupteur et une touche chacun, avec les conflits signalés) et liste des raccourcis de l'île (voir §13).
''', '''- **Shortcuts** *(macOS)* : raccourcis globaux (un interrupteur et une touche chacun, avec les conflits signalés) et liste des raccourcis de l'île (voir §13).
- **Cat** : **Display** (One cat, A cat for each agent ou Two cats, avec son aperçu), **Main cat** (le pelage, parmi 16, avec un aperçu), style de mouvement (Playful ou Classic) et mouvement propre à chaque chat, personnalité (préréglages et six curseurs), **Collar**, **Apply to every cat** et **Fur lines** (voir §7).
'''),
])
PY
```

Run: `git diff --stat -- docs/SPEC.md | tail -1; grep -c -i mochi docs/SPEC.md; grep -c "## 7. Les personnages : Shrimpy, Momo et les autres chats" docs/SPEC.md; grep -c "^### Modes d'affichage, chats des agents et chatons" docs/SPEC.md`
Expected: ` 1 file changed, 25 insertions(+), 14 deletions(-)`, `0`, `1` and `1`.

- [ ] **Step 2: `README.md` and `CHANGELOG.md`**

`README.md`: the work-in-progress note said the cats, the name, the icons and the sounds "are being built now" and that development builds "still draw the upstream placeholder character": the cats and the icons are built (stages 1 to 7 of sub-project A, and the icons), and so are the sounds (the sound pack, merged into `notchmeow/rebrand` at `7435680`, after this plan's base: the lines describe the branch this one merges into); and "Two motion styles are planned" is stale, they are Settings → Cat → Motion style. `CHANGELOG.md`: one line each for A and B in the file's style (the `Unreleased (NotchMeow)` list), and the line that said the cats and icons were "in progress" says only the sounds are.

```bash
python3 - <<'PY'
# Task 5, step 2: README.md and CHANGELOG.md. Run from the repository root. Every anchor must occur exactly once.
def edit(path, pairs):
    s = open(path, encoding='utf-8').read()
    for was, now in pairs:
        assert s.count(was) == 1, (path, was[:70])
        s = s.replace(was, now)
    open(path, 'w', encoding='utf-8').write(s)

edit('README.md', [
('''> The engine, the island and the integrations come from Coucou (MIT). The cats, the name, the icons and the
> sounds are NotchMeow's own and are being built now. Until they land, development builds still draw the
> upstream placeholder character and play no sounds. There are no releases yet.
''', '''> The engine, the island and the integrations come from Coucou (MIT). The cats, the name, the icons and the
> sounds are NotchMeow's own. There are no releases yet.
'''),
('''waiting for your approval, finished, error, rate-limited). Two motion styles are planned: **Playful** (cat body
language: ear flicks, slow blinks, a hunting crouch, a big yawn) and **Classic** (the original timings).
''', '''waiting for your approval, finished, error, rate-limited). Two motion styles, picked in Settings → Cat: **Playful** (cat body
language: ear flicks, slow blinks, a hunting crouch, a big yawn) and **Classic** (the original timings).
'''),
])

edit('CHANGELOG.md', [
('''- Removed Coucou's reserved assets (sounds, media, captures and prototypes); NotchMeow's own cats, icons and sounds are in progress
''', '''- Removed Coucou's reserved assets (sounds, media, captures and prototypes)
- Shrimpy and Momo, two cats drawn entirely in code, replace Coucou's character on macOS, Windows and Linux, with NotchMeow's own app, menu bar and tray icons. Their eyes follow your cursor and each agent state has its own reaction. Settings → Cat picks the cat among 16 coats, a Playful or Classic motion style, a personality (six sliders and six presets), an optional collar in the agent's colour and fur lines. An idle cat falls asleep after ten minutes, bobs to Apple Music (macOS) and coughs up a file it can't read as a hairball
- Settings → Cat → Display: One cat, A cat for each agent (each agent keeps its own coat, with a dice and Reset to defaults) or Two cats side by side (the focused agent and the busiest other one). A Claude Code subagent shows up as a small kitten beside its parent's cat and leaves with a happy blink when it stops (Codex's too, on macOS). Every cat below Ø28 has small coloured eyes
- NotchMeow's own sounds: one short WAV for each moment, built from CC0 clips and credited in `docs/SOUND-CREDITS.md`, on macOS, Windows and Linux
'''),
])
PY
```

Run: `git diff --stat -- README.md CHANGELOG.md | tail -3`
Expected: ` CHANGELOG.md | 5 ++++-`, ` README.md    | 5 ++---` and ` 2 files changed, 6 insertions(+), 4 deletions(-)`.

- [ ] **Step 2b: The roadmap row for A and CLAUDE.md's prototype line (the owner's answers of 2026-10-08)**

The owner asked for two more stale lines: the README roadmap row for A, which still says "in progress" though stages 1 to 7 are built on both apps (set like B's row), and CLAUDE.md's "(being built)" after the cat prototype, which is done. The owner approved this CLAUDE.md edit; nothing else in CLAUDE.md changes.

```bash
python3 - <<'PY'
# Task 5, step 2b: the roadmap row for A and CLAUDE.md's prototype line. Run from the repository root. Every anchor must occur exactly once.
def edit(path, pairs):
    s = open(path, encoding='utf-8').read()
    for was, now in pairs:
        assert s.count(was) == 1, (path, was[:70])
        s = s.replace(was, now)
    open(path, 'w', encoding='utf-8').write(s)

edit('README.md', [
('| A | Fork and rebrand, then the Shrimpy and Momo characters on macOS, Windows and Linux | in progress |\n',
 '| A | Fork and rebrand, then the Shrimpy and Momo characters on macOS, Windows and Linux | built on macOS, Windows and Linux; real-build checks pending |\n'),
('| C | NotchMeow\'s own sounds | planned |\n',
 '| C | NotchMeow\'s own sounds | the pack is built and plays on macOS, Windows and Linux; per-cat voices and play rules planned |\n'),
('- **Sounds**: short WAVs played through preloaded `AVAudioPlayer`s (NotchMeow\'s own set is in progress).\n',
 '- **Sounds**: NotchMeow\'s own short WAVs, one for each moment (credits in [`docs/SOUND-CREDITS.md`](docs/SOUND-CREDITS.md)), played through preloaded `AVAudioPlayer`s.\n'),
])
edit('CLAUDE.md', [
('the visual source of truth for the characters (being built).', 'the visual source of truth for the characters.'),
])
PY
```

Run: `git diff --stat -- README.md CLAUDE.md | tail -3`
Expected: ` CLAUDE.md |  2 +-`, ` README.md | 11 +++++------` and ` 2 files changed, 6 insertions(+), 7 deletions(-)`.

- [ ] **Step 3: Check that nothing else moved**

Run: `git grep -c -i mochi -- docs/SPEC.md docs/INTEGRATIONS.md README.md windows/README.md CHANGELOG.md CLAUDE.md ARCHITECT.md`
Expected: `CHANGELOG.md:2` and `CLAUDE.md:2`: the two lines of the upstream history that the changelog keeps "for reference" (Apple Music, and the agent tag), and CLAUDE.md's rule that forbids the name. No other file has the word.

Run: `git grep -n -i "coucou" -- docs/SPEC.md docs/INTEGRATIONS.md windows/README.md | wc -l; bash scripts/check-no-leftovers.sh 2>&1 | tail -1`
Expected: `0` and `✓ no notification that nothing posts or observes`.

Run: `git diff --stat | tail -1; git status --short`
Expected: ` 4 files changed, 35 insertions(+), 22 deletions(-)` and the four modified files (`CHANGELOG.md`, `CLAUDE.md`, `README.md` and `docs/SPEC.md`).

- [ ] **Step 4: Commit**

```bash
git add docs/SPEC.md README.md CHANGELOG.md CLAUDE.md
git commit -m "docs: the cats in SPEC.md, stale README lines, and the changelog for A and B

SPEC.md (French) no longer describes the inherited character: the values' source, the no-notch bar, all of section 7 (now Shrimpy, Momo, the 16 coats, the display
modes, the kittens and the small eyes, pointing to docs/CAT-CONTRACT.md), the menu bar icon, the plan card's cat and milestone M2, and Settings gets its Cat section.
README.md: the cats, the icons and the sounds are built, the motion styles are not planned, and roadmap rows A and C say where they are. CLAUDE.md: the prototype is no longer '(being built)'. CHANGELOG.md: a line each for sub-projects A and B and the sound pack, and its
fork line no longer says anything is in progress. docs/INTEGRATIONS.md and windows/README.md had nothing stale.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

Run: `git status --short`
Expected: nothing.

---
### Task 6: Mac, an empty kitten layer stops asking for frames

**Agent:** `nm-implementer`.

**Files:**
- Modify: `NotchBuddy/Sources/App/CatKittens.swift`, `NotchBuddy/Sources/App/CatKittenDraw.swift`, `NotchBuddy/Sources/App/KittenViews.swift`, `tests/CatKittensTests.swift`, `tests/CatWiringTests.swift`

**Interfaces:**
- Consumes: `CatKittens.view(_:now:)` (the kittens to draw at a time: a leaving kitten is hidden from its `until`), `KittenLayerView(state:pills:parentCat:place:unit:colour:)` and its `@StateObject herd: CatKittenHerd`, `AppState.kittens` (`[String: [CatKittens.Kitten]]`, `Equatable`), and the existing pin that no kitten file contains `Timer`, `asyncAfter`, `DispatchWorkItem` or `Task {`.
- Produces: `CatKittens.mayStop(lastFrameEmpty: Bool, lists: [[Kitten]], now: Double) -> Bool`; `CatKittenHerd.lastFrameEmpty` (set by the layer as it draws); the layer's `@State quiet`, which pauses its `TimelineView` and is cleared when `AppState.kittens` or the layer's `pills` change.

**The cause, confirmed.** `KittenPlacement` shows its layers only while `state.kittens` is not empty. A pill's list loses a leaving kitten only at the **next event for that pill** (`CatKittens.step` drops the due kittens), or when the cat falls asleep (the sweep), so after the last subagent stops, and while the parent is quiet, the list still holds a kitten whose farewell is over: `view` hides it, nothing is drawn, and the layer keeps asking for a frame 30 times a second (`TimelineView(.animation(minimumInterval: 1.0 / 30, paused: state.mode == .hidden))`) for as long as the island is open and the cat awake, up to ten minutes. The 0 %-CPU rule holds when the island is hidden (it pauses) and not when it is open. **No timer may fix it** (the farewell ends because the view stops listing it), so the layer decides for itself: after a frame that drew nothing, with nothing left to show, it pauses; a change of the kittens or of its pills wakes it. Two details keep it right. The decision needs **both** facts (the last frame on screen is empty, and nothing is left to show now), so a kitten that expires between a draw and the check cannot be frozen on screen. And the pair's compact "×N" label is drawn while kittens exist, with no kitten shown, so "empty" means no kittens at all, not no slots.

- [ ] **Step 1: Write the failing tests**

```bash
python3 - <<'PY'
# Task 6, tests first: the rule, and the pin on the layer. Run from the repository root.
def edit(path, pairs):
    s = open(path, encoding='utf-8').read()
    for was, now in pairs:
        assert s.count(was) == 1, (path, was[:70])
        s = s.replace(was, now)
    open(path, 'w', encoding='utf-8').write(s)

edit('tests/CatKittensTests.swift', [
('''        CT.finish()
    }
}''', '''        CT.section("a kitten layer may stop asking for frames only when nothing is left to show and the frame on screen is empty")
        let farewell = [K.Kitten(id: "gone", state: .leaving, born: 1, last: 2, until: 5)], working = [K.Kitten(id: "w", state: .working, born: 1, last: 1)]
        CT.check("a kitten that is working: no", K.mayStop(lastFrameEmpty: true, lists: [working], now: 100), false)
        CT.check("a farewell that is not over: no", K.mayStop(lastFrameEmpty: true, lists: [farewell], now: 4), false)
        CT.check("a farewell that is over, though the list keeps it until the next event: yes", K.mayStop(lastFrameEmpty: true, lists: [farewell], now: 5), true)
        CT.check("no list, or lists with nothing in them: yes", [K.mayStop(lastFrameEmpty: true, lists: [], now: 0), K.mayStop(lastFrameEmpty: true, lists: [[], []], now: 0)], [true, true])
        CT.check("the frame on screen still shows a kitten: not yet, whatever the lists hold now", K.mayStop(lastFrameEmpty: false, lists: [farewell], now: 9), false)
        CT.check("two pills, one of them with a working kitten: no", K.mayStop(lastFrameEmpty: true, lists: [farewell, working], now: 9), false)
        CT.check("a time that is not finite hides nothing, so a farewell is still shown: no", K.mayStop(lastFrameEmpty: true, lists: [farewell], now: .nan), false)

        CT.finish()
    }
}'''),
])

edit('tests/CatWiringTests.swift', [
('''        CT.checkTrue("the parent's coat reaches the layer from the cast (the big cat's, cat 2's and the pill's)", layers.contains("cat: spot.cat") && pillSource.contains("parentCat: cat"))
''', '''        CT.checkTrue("the parent's coat reaches the layer from the cast (the big cat's, cat 2's and the pill's)", layers.contains("cat: spot.cat") && pillSource.contains("parentCat: cat"))
        CT.checkTrue("a layer with nothing to draw stops asking for frames (CatKittens.mayStop, on the frame it just drew and the lists it draws) and starts again when the kittens or its pills change", layers.contains("@State private var quiet = false") && layers.contains("paused: state.mode == .hidden || quiet") && layers.contains("herd.lastFrameEmpty = list.isEmpty") && layers.contains("CatKittens.mayStop(lastFrameEmpty: herd.lastFrameEmpty, lists: pills.map { state.kittens[$0] ?? [] }, now: CACurrentMediaTime() * 1000)") && layers.contains(".onChange(of: state.kittens) { _, _ in quiet = false }") && layers.contains(".onChange(of: pills) { _, _ in quiet = false }") && draw.contains("var lastFrameEmpty = false"))
'''),
])
PY
```

Run: `bash scripts/test-cat-kittens.sh 2>&1 | grep -E "error:|failed" | cut -c1-160; bash scripts/test-cat-wiring.sh 2>&1 | grep -E '✗|failed' | cut -c1-170`
Expected: FAIL: the kittens program does not compile (`type 'CatKittensTests.K' (aka 'CatKittens') has no member 'mayStop'`), and the wiring program prints `✗ a layer with nothing to draw stops asking for frames …` and `1 test(s) failed.`

- [ ] **Step 2: Write the rule, the flag and the layer**

```bash
python3 - <<'PY'
# Task 6: the rule, the flag and the layer. Run from the repository root.
def edit(path, pairs):
    s = open(path, encoding='utf-8').read()
    for was, now in pairs:
        assert s.count(was) == 1, (path, was[:70])
        s = s.replace(was, now)
    open(path, 'w', encoding='utf-8').write(s)

edit('NotchBuddy/Sources/App/CatKittens.swift', [
('''    static func view(_ list: [Kitten], now: Double) -> [Kitten] {
        order(clean(list).filter { $0.state != .leaving || !now.isFinite || ($0.until ?? 0) > now })
    }
''', '''    static func view(_ list: [Kitten], now: Double) -> [Kitten] {
        order(clean(list).filter { $0.state != .leaving || !now.isFinite || ($0.until ?? 0) > now })
    }

    /// Whether a layer that draws these lists may stop asking for frames: the frame on screen is empty (`lastFrameEmpty`) and nothing is left to show at `now` (ms). A leaving kitten is dropped from its
    /// list only by the next event, so a list can still hold one whose farewell is over, and a layer that waited for its lists to be empty would draw nothing at 30 fps until the cat fell asleep.
    static func mayStop(lastFrameEmpty: Bool, lists: [[Kitten]], now: Double) -> Bool {
        lastFrameEmpty && lists.allSatisfy { view($0, now: now).isEmpty }
    }
'''),
])

edit('NotchBuddy/Sources/App/CatKittenDraw.swift', [
('''    /// Where the engines' dice come from: `Double.random` in the app, a seeded source on a contact sheet.
    var rand: () -> Double = { Double.random(in: 0..<1) }
''', '''    /// Where the engines' dice come from: `Double.random` in the app, a seeded source on a contact sheet.
    var rand: () -> Double = { Double.random(in: 0..<1) }
    /// Whether the layer's last frame had nothing to draw. The layer sets it as it draws and reads it to stop asking for frames (`CatKittens.mayStop`).
    var lastFrameEmpty = false
'''),
])

edit('NotchBuddy/Sources/App/KittenViews.swift', [
('''    @StateObject private var herd = CatKittenHerd()

    var body: some View {
        let box = CatIslandLayout.kittenBox(place), u = Double(unit)
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: state.mode == .hidden)) { timeline in
            Canvas { context, size in
                _ = timeline.date   // the Canvas redraws on every tick of the timeline
                let now = CACurrentMediaTime() * 1000
                let list = pills.flatMap { state.kittenView($0, at: now) }
                let slots = CatKittens.slots(place, list)
''', '''    @StateObject private var herd = CatKittenHerd()
    /// Set when the layer has nothing left to draw: it then stops asking for frames until the kittens, or the pills it draws, change. A leaving kitten stays in its list until the next event, and the list
    /// is what keeps the layer on the island, so without this an empty layer drew nothing at 30 fps for as long as the island was open and the cat awake.
    @State private var quiet = false

    var body: some View {
        let box = CatIslandLayout.kittenBox(place), u = Double(unit)
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: state.mode == .hidden || quiet)) { timeline in
            Canvas { context, size in
                _ = timeline.date   // the Canvas redraws on every tick of the timeline
                let now = CACurrentMediaTime() * 1000
                let list = pills.flatMap { state.kittenView($0, at: now) }
                herd.lastFrameEmpty = list.isEmpty
                let slots = CatKittens.slots(place, list)
'''),
('''                                       now: { CACurrentMediaTime() * 1000 }) { e in e.update(dt: CatEngine.frameDelta(now: CACurrentMediaTime(), last: e.lastTime)) }
                }
            }
        }
        .frame(width: (box.x1 - box.x0) * u, height: (box.y1 - box.y0) * u)
        .allowsHitTesting(false)
    }
}
''', '''                                       now: { CACurrentMediaTime() * 1000 }) { e in e.update(dt: CatEngine.frameDelta(now: CACurrentMediaTime(), last: e.lastTime)) }
                }
            }
            .onChange(of: timeline.date) { _, _ in
                if CatKittens.mayStop(lastFrameEmpty: herd.lastFrameEmpty, lists: pills.map { state.kittens[$0] ?? [] }, now: CACurrentMediaTime() * 1000) { quiet = true }
            }
        }
        .frame(width: (box.x1 - box.x0) * u, height: (box.y1 - box.y0) * u)
        .allowsHitTesting(false)
        .onChange(of: state.kittens) { _, _ in quiet = false }
        .onChange(of: pills) { _, _ in quiet = false }
    }
}
'''),
])
PY
```

- [ ] **Step 3: Run the tests, and prove they bite**

Run: `bash scripts/test-cat-kittens.sh 2>&1 | tail -3; bash scripts/test-cat-wiring.sh 2>&1 | tail -2`
Expected: PASS: `✓ a time that is not finite hides nothing, so a farewell is still shown: no` and `All tests passed.` from the first, `All tests passed.` from the second.

Make the rule stop on one fact only.

Run: `cp NotchBuddy/Sources/App/CatKittens.swift "${TMPDIR:-/tmp}/fixes-after-b-kittens.swift"; sed -i '' 's/lastFrameEmpty \&\& lists.allSatisfy/lastFrameEmpty || lists.allSatisfy/' NotchBuddy/Sources/App/CatKittens.swift; bash scripts/test-cat-kittens.sh 2>&1 | grep -E '✗|failed' | cut -c1-130; cp "${TMPDIR:-/tmp}/fixes-after-b-kittens.swift" NotchBuddy/Sources/App/CatKittens.swift; bash scripts/test-cat-kittens.sh 2>&1 | tail -1`
Expected: with the rule stopping on either fact, `✗ a kitten that is working: no`, `✗ a farewell that is not over: no`, `✗ the frame on screen still shows a kitten: not yet, whatever the lists hold now`, `✗ two pills, one of them with a working kitten: no`, `✗ a time that is not finite hides nothing, so a farewell is still shown: no` and `5 test(s) failed.`; with the line put back `All tests passed.`

- [ ] **Step 4: Build**

Run: `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: the last lines end with `** BUILD SUCCEEDED **`. (The App Store target builds in Task 10.) The layer's behaviour in a real window is the owner's check (Task 11): nothing here starts the app.

- [ ] **Step 5: Commit**

```bash
git add NotchBuddy/Sources/App/CatKittens.swift NotchBuddy/Sources/App/CatKittenDraw.swift NotchBuddy/Sources/App/KittenViews.swift tests/CatKittensTests.swift tests/CatWiringTests.swift
git commit -m "fix(cat): an empty kitten layer stops asking for frames

A leaving kitten stays in its pill's list until the next event for that pill, and the list is what keeps the layer on the island, so after the last subagent
stopped the layer drew nothing at 30 fps for as long as the island was open and the cat awake. The layer now pauses its timeline after a frame that drew nothing
when nothing is left to show (CatKittens.mayStop: both facts), and wakes when the kittens or its pills change. No timer: the rule is a pure function with seven tests.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

Run: `git status --short`
Expected: nothing.

---

### Task 7: Mac, the agents' list follows the events

**Agent:** `nm-implementer-light`. The code is given in full.

**Files:**
- Modify: `NotchBuddy/Sources/App/CatAgentList.swift`, `NotchBuddy/Sources/App/AppState.swift`, `tests/CatAgentListTests.swift`, `tests/CatWiringTests.swift`

**Interfaces:**
- Consumes: `AppState.pillLastEvent` (each pill's last event time, not `@Published`) and `touchPill(_:at:)` (called by the hook server for every event, permission request and question), `CatAgentList.rows(agents:display:main:lookup:)` (most recent event first), `CatSettingsSection` (observes `AppState`).
- Produces: `CatAgentList.touchReorders(_ last: [String: Double], id: String) -> Bool`; `touchPill` calls `objectWillChange.send()` before it records the time, when and only when that returns true.

**The cause, confirmed.** "Cats for your agents" is ordered by each pill's last event, and `pillLastEvent` is a plain dictionary on purpose (every event would otherwise invalidate every view): "the events that set it change the tasks too, and the views redraw for those". So the list's order is as fresh as the next change of `tasks`, which an event does not always make. Making the dictionary `@Published` would publish on every hook event, many a second during a tool run. **It is cheap to make live** because an event changes the order only when the pill it is for is not already the most recent one: that is the rule (`touchReorders`), and `touchPill` announces a change only then, a handful of times in a session (when work moves from one agent to another).

- [ ] **Step 1: Write the failing tests**

The second test replays the rule against the list itself: for each of three agents (the first most recent, the second, and a third that has had no event), it records an event and checks that the order `rows` produces changes exactly when `touchReorders` said it would.

```bash
python3 - <<'PY'
# Task 7, tests first: the rule against the list's own order, and the call in AppState. Run from the repository root.
def edit(path, pairs):
    s = open(path, encoding='utf-8').read()
    for was, now in pairs:
        assert s.count(was) == 1, (path, was[:70])
        s = s.replace(was, now)
    open(path, 'w', encoding='utf-8').write(s)

edit('tests/CatAgentListTests.swift', [
('''        CT.section("the Display preview's sample island: what each mode shows")
''', '''        CT.section("the list's order follows the events live: an event reorders it unless that pill already had the latest one")
        CT.check("nothing recorded yet: the first event does", L.touchReorders([:], id: "agent_a"), true)
        CT.check("the pill with the latest event has another: the order stays", L.touchReorders(["agent_a": 30, "agent_b": 20], id: "agent_a"), false)
        CT.check("another pill's event moves it to the front: the order changes", L.touchReorders(["agent_a": 30, "agent_b": 20], id: "agent_b"), true)
        CT.check("a pill with no event yet gets its first: the order changes", L.touchReorders(["agent_a": 30], id: "agent_c"), true)
        func order(_ last: [String: Double]) -> [String] {
            L.rows(agents: ["agent_a", "agent_b", "agent_c"].map { L.Agent(id: $0, name: $0, color: "#000000", last: last[$0] ?? 0) }, display: D(), main: "ginger").map(\\.id)
        }
        for id in ["agent_a", "agent_b", "agent_c"] {
            var last: [String: Double] = ["agent_a": 30, "agent_b": 20]   // agent_c has had no event
            let before = order(last), predicted = L.touchReorders(last, id: id)
            last[id] = 99
            CT.check("an event for \\(id): the list reorders exactly when touchReorders says so", order(last) != before, predicted)
        }

        CT.section("the Display preview's sample island: what each mode shows")
'''),
])
edit('tests/CatWiringTests.swift', [
('''        CT.checkTrue("AppState keeps the times in a dictionary that is not published", app.contains("var pillLastEvent: [String: Double] = [:]") && !app.contains("@Published var pillLastEvent"))
''', '''        CT.checkTrue("AppState keeps the times in a dictionary that is not published by itself: it announces a change only when an event reorders the agents' list in Settings, before it records the time", app.contains("var pillLastEvent: [String: Double] = [:]") && !app.contains("@Published var pillLastEvent") && app.contains("if CatAgentList.touchReorders(pillLastEvent, id: id) { objectWillChange.send() }") && app.contains("objectWillChange.send() }\\n        pillLastEvent[id] = ms"))
'''),
])
PY
```

Run: `bash scripts/test-cat-agent-list.sh 2>&1 | grep -E "error:" | cut -c1-170 | head -2; bash scripts/test-cat-wiring.sh 2>&1 | grep -E '✗|failed' | cut -c1-120`
Expected: FAIL: the agent list program does not compile (`type 'CatAgentListTests.L' (aka 'CatAgentList') has no member 'touchReorders'`), and the wiring program prints `✗ AppState keeps the times in a dictionary that is not published by itself: …` and `1 test(s) failed.`

- [ ] **Step 2: Write the rule and the call**

```bash
python3 - <<'PY'
# Task 7: the rule and the call. Run from the repository root.
def edit(path, pairs):
    s = open(path, encoding='utf-8').read()
    for was, now in pairs:
        assert s.count(was) == 1, (path, was[:70])
        s = s.replace(was, now)
    open(path, 'w', encoding='utf-8').write(s)

edit('NotchBuddy/Sources/App/CatAgentList.swift', [
('''    /// The agents on the island first, the most recent event first''', '''    /// Whether an event for `id` changes the order of this list (most recent event first): it does, unless that pill already had the latest event. The app announces a change then and only then, so
    /// Settings follows the order as it changes without every hook event invalidating every view. `last` is each pill's last event time (ms), as `AppState.pillLastEvent` holds it.
    static func touchReorders(_ last: [String: Double], id: String) -> Bool {
        guard let newest = last.max(by: { $0.value < $1.value })?.key else { return true }
        return newest != id
    }

    /// The agents on the island first, the most recent event first'''),
])

edit('NotchBuddy/Sources/App/AppState.swift', [
('''    /// When each pill last had a hook event, in ms on the `CACurrentMediaTime()` clock (`touchPill`). Two cats mode picks the busiest other agent with it. Not
    /// published: the events that set it change the tasks too, and the views redraw for those.
    var pillLastEvent: [String: Double] = [:]
    func touchPill(_ id: String, at ms: Double = CACurrentMediaTime() * 1000) { pillLastEvent[id] = ms }
''', '''    /// When each pill last had a hook event, in ms on the `CACurrentMediaTime()` clock (`touchPill`). Two cats mode picks the busiest other agent with it, and Settings → Cat lists the agents by it.
    /// Not published by itself: the events that set it change the tasks too, and the views redraw for those; `touchPill` announces a change on its own only when an event reorders the agents' list.
    var pillLastEvent: [String: Double] = [:]
    func touchPill(_ id: String, at ms: Double = CACurrentMediaTime() * 1000) {
        if CatAgentList.touchReorders(pillLastEvent, id: id) { objectWillChange.send() }
        pillLastEvent[id] = ms
    }
'''),
])
PY
```

- [ ] **Step 3: Run the tests, and prove they bite**

Run: `bash scripts/test-cat-agent-list.sh 2>&1 | tail -2; bash scripts/test-cat-wiring.sh 2>&1 | tail -2`
Expected: PASS: `All tests passed.` twice.

Make the rule always say no.

Run: `cp NotchBuddy/Sources/App/CatAgentList.swift "${TMPDIR:-/tmp}/fixes-after-b-list.swift"; sed -i '' 's/return newest != id/return false/' NotchBuddy/Sources/App/CatAgentList.swift; bash scripts/test-cat-agent-list.sh 2>&1 | grep -E '✗|failed' | cut -c1-120; cp "${TMPDIR:-/tmp}/fixes-after-b-list.swift" NotchBuddy/Sources/App/CatAgentList.swift; bash scripts/test-cat-agent-list.sh 2>&1 | tail -1`
Expected: with the rule always saying no, `✗ another pill's event moves it to the front: the order changes`, `✗ a pill with no event yet gets its first: the order changes`, `✗ an event for agent_b: the list reorders exactly when touchReorders says so`, `✗ an event for agent_c: the list reorders exactly when touchReorders says so` and `4 test(s) failed.`; with the line put back `All tests passed.`

- [ ] **Step 4: Build**

Run: `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: the last lines end with `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add NotchBuddy/Sources/App/CatAgentList.swift NotchBuddy/Sources/App/AppState.swift tests/CatAgentListTests.swift tests/CatWiringTests.swift
git commit -m "feat(cat): the agents' list in Settings follows the events

Cats for your agents is ordered by each pill's last event, which AppState keeps in a dictionary that is not published, so the order was as fresh as the next change
of the tasks. touchPill now announces a change when, and only when, the event reorders the list (CatAgentList.touchReorders: the pill was not already the most recent),
which happens when work moves from one agent to another, not at every hook event. The rule is tested against the list's own order.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

Run: `git status --short`
Expected: nothing.

---

### Task 8: Mac, no unused `botD`, no pass-through `cat1D`, one duplicate pin fewer

**Agent:** `nm-implementer-light`. The code is given in full.

**Files:**
- Modify: `NotchBuddy/Sources/App/CatIslandLayout.swift`, `NotchBuddy/Sources/App/PairCatViews.swift`, `NotchBuddy/Sources/App/IslandViewContent.swift`, `NotchBuddy/Sources/App/IslandRootView.swift`, `scripts/render-cats.swift`, `tests/CatAgentListTests.swift`, `tests/CatWiringTests.swift`

**Interfaces:**
- Consumes: `CatIslandLayout.pairExpanded(botX:botD:cy:) -> PairExpanded` (with `cat1D`), `CatIslandLayout.overviewCardShift(second:botX:botD:)`, and their callers.
- Produces: `CatIslandLayout.pairExpanded(botX: Double, cy: Double) -> PairExpanded` (no `cat1D`: the struct is `cat1X`, `cat2X`, `cat2Y`, `cat2D`, `textLeading`) and `CatIslandLayout.overviewCardShift(second: Bool, botX: Double) -> Double`.

**The causes, confirmed.** `overviewCardShift(second:botX:botD:)` only passes `botD` on to `pairExpanded`, and `textLeading` (the one number it returns) does not depend on it. `PairExpanded.cat1D` is `botD` handed back (cat 1 keeps the one cat's diameter, which every caller already has), and no code reads it but two lines of a test; with it gone `pairExpanded` has no use for `botD` either. In `CatWiringTests`, the pin "tapping cat 2 focuses its agent, in the overview only" asserts the `overview: state.view == .overview) else { return nil }` text that the pin "cat 1's badge and cat 2's place use the same rule" asserts in full (`guard CatIslandLayout.secondBesideBig(…) else { return nil }`). And "and by 34 exactly" in `CatAgentListTests` says what the 142 and the 108 pinned a few lines above already say. Nothing about the layout's numbers changes: the island and kitten sheets are drawn again in Task 10 and must be byte for byte the ones of Task 0.

- [ ] **Step 1: Write the failing tests**

The tests take the new signatures, which do not exist yet, and lose the two duplicates.

```bash
python3 - <<'PY'
# Task 8, tests first: the signatures without botD and cat1D, and the two duplicates gone. Run from the repository root.
def edit(path, pairs):
    s = open(path, encoding='utf-8').read()
    for was, now in pairs:
        assert s.count(was) == 1, (path, was[:70])
        s = s.replace(was, now)
    open(path, 'w', encoding='utf-8').write(s)

edit('tests/CatAgentListTests.swift', [
('''p = CatIslandLayout.pairExpanded(botX: 68, botD: 58, cy: 101)
        CT.check("cat 1 moves 18 pt left and keeps its size", [p.cat1X, p.cat1D], [50, 58])
''', '''p = CatIslandLayout.pairExpanded(botX: 68, cy: 101)
        CT.check("cat 1 moves 18 pt left (its size is the one cat's, Ø58, and is not the layout's to say)", p.cat1X, 50)
'''),
('''(p.cat2X - p.cat2D / 2) - (p.cat1X + p.cat1D / 2) == 6)''', '''(p.cat2X - p.cat2D / 2) - (p.cat1X + 58.0 / 2) == 6)'''),
('''CatIslandLayout.overviewCardShift(second: true, botX: 68, botD: 58), p.textLeading - shippingLeading)
        CT.check("and by 34 exactly", CatIslandLayout.overviewCardShift(second: true, botX: 68, botD: 58), 34)
        CT.check("One cat and A cat for each agent have no cat 2: the cards do not move", CatIslandLayout.overviewCardShift(second: false, botX: 68, botD: 58), 0)
''', '''CatIslandLayout.overviewCardShift(second: true, botX: 68), p.textLeading - shippingLeading)
        CT.check("One cat and A cat for each agent have no cat 2: the cards do not move", CatIslandLayout.overviewCardShift(second: false, botX: 68), 0)
'''),
('''CatIslandLayout.planRowsWidth(shift: CatIslandLayout.overviewCardShift(second: true, botX: 68, botD: 58))''', '''CatIslandLayout.planRowsWidth(shift: CatIslandLayout.overviewCardShift(second: true, botX: 68))'''),
])
edit('tests/CatWiringTests.swift', [
('''content.contains("CatIslandLayout.overviewCardShift(second: second != nil, botX: Double(l.botX), botD: Double(l.botDiameter))")''', '''content.contains("CatIslandLayout.overviewCardShift(second: second != nil, botX: Double(l.botX))")'''),
('''pair.contains(".allowsHitTesting(!place.compact && task != nil)") && pair.contains("overview: state.view == .overview) else { return nil }"))''', '''pair.contains(".allowsHitTesting(!place.compact && task != nil)"))'''),
])
PY
```

Run: `bash scripts/test-cat-agent-list.sh 2>&1 | grep -E "error:" | cut -c1-150 | head -2; bash scripts/test-cat-wiring.sh 2>&1 | grep -E '✗|failed' | cut -c1-130`
Expected: FAIL: the agent list program does not compile (`missing argument for parameter 'botD' in call`), and the wiring program prints `✗ the overview moves its hosted cards (the integration card, the plan card, the diff card) …` and `1 test(s) failed.`

- [ ] **Step 2: Write the change**

```bash
python3 - <<'PY'
# Task 8: the layout's signatures and their call sites. Run from the repository root.
def edit(path, pairs):
    s = open(path, encoding='utf-8').read()
    for was, now in pairs:
        assert s.count(was) == 1, (path, was[:70])
        s = s.replace(was, now)
    open(path, 'w', encoding='utf-8').write(s)

edit('NotchBuddy/Sources/App/CatIslandLayout.swift', [
('''        var cat1X: Double, cat1D: Double
''', '''        var cat1X: Double
'''),
('''    /// `botX`, `botD` and `cy` are where `botPosition` puts the one big cat in the overview.
    static func pairExpanded(botX: Double, botD: Double, cy: Double) -> PairExpanded {
        let cat2X = botX + 40
        return PairExpanded(cat1X: botX - 18, cat1D: botD, cat2X: cat2X, cat2Y: cy + 8, cat2D: pairCat2D, textLeading: cat2X + pairCat2D / 2 + textGap - cardX)
''', '''    /// `botX` and `cy` are where `botPosition` puts the one big cat in the overview. Cat 1 keeps the diameter the one cat has there, so it is not the layout's to say.
    static func pairExpanded(botX: Double, cy: Double) -> PairExpanded {
        let cat2X = botX + 40
        return PairExpanded(cat1X: botX - 18, cat2X: cat2X, cat2Y: cy + 8, cat2D: pairCat2D, textLeading: cat2X + pairCat2D / 2 + textGap - cardX)
'''),
('''    static func overviewCardShift(second: Bool, botX: Double, botD: Double) -> Double {
        second ? pairExpanded(botX: botX, botD: botD, cy: 0).textLeading - oneTextLeading : 0
''', '''    static func overviewCardShift(second: Bool, botX: Double) -> Double {
        second ? pairExpanded(botX: botX, cy: 0).textLeading - oneTextLeading : 0
'''),
])
edit('NotchBuddy/Sources/App/PairCatViews.swift', [
('''CatIslandLayout.pairExpanded(botX: Double(one.0), botD: Double(one.2), cy: Double(one.1))''', '''CatIslandLayout.pairExpanded(botX: Double(one.0), cy: Double(one.1))'''),
])
edit('NotchBuddy/Sources/App/IslandViewContent.swift', [
('''CatIslandLayout.pairExpanded(botX: Double(l.botX), botD: Double(l.botDiameter), cy: 0).textLeading''', '''CatIslandLayout.pairExpanded(botX: Double(l.botX), cy: 0).textLeading'''),
('''CatIslandLayout.overviewCardShift(second: second != nil, botX: Double(l.botX), botD: Double(l.botDiameter))''', '''CatIslandLayout.overviewCardShift(second: second != nil, botX: Double(l.botX))'''),
])
edit('NotchBuddy/Sources/App/IslandRootView.swift', [
('''CatIslandLayout.pairExpanded(botX: Double(cx), botD: Double(diameter), cy: Double(cy)).cat1X''', '''CatIslandLayout.pairExpanded(botX: Double(cx), cy: Double(cy)).cat1X'''),
])
edit('scripts/render-cats.swift', [
('''let cy = 101.0, one = CatIslandLayout.pairExpanded(botX: 68, botD: 58, cy: cy)''', '''let cy = 101.0, one = CatIslandLayout.pairExpanded(botX: 68, cy: cy)'''),
('''let pairAt = CatIslandLayout.pairExpanded(botX: 68, botD: 58, cy: cy)''', '''let pairAt = CatIslandLayout.pairExpanded(botX: 68, cy: cy)'''),
])
PY
```

- [ ] **Step 3: Run the tests, and look for what is left**

Run: `bash scripts/test-cat-agent-list.sh 2>&1 | tail -2; bash scripts/test-cat-wiring.sh 2>&1 | tail -2; grep -rn 'botD\b\|cat1D' NotchBuddy/Sources scripts tests --include='*.swift' | grep -v botDizzy | wc -l`
Expected: PASS: `All tests passed.` twice, then `0` (no unused parameter and no pass-through field left).

Run: `for f in scripts/test-cat-greeting.sh scripts/test-cat-renderer.sh scripts/test-cat-settings-store.sh scripts/test-cat-cast.sh; do bash "$f" 2>&1 | tail -1; done`
Expected: `All tests passed.` four times (the other programs that compile the layout file).

- [ ] **Step 4: Build**

Run: `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: the last lines end with `** BUILD SUCCEEDED **`.

- [ ] **Step 5: Commit**

```bash
git add NotchBuddy/Sources/App/CatIslandLayout.swift NotchBuddy/Sources/App/PairCatViews.swift NotchBuddy/Sources/App/IslandViewContent.swift NotchBuddy/Sources/App/IslandRootView.swift scripts/render-cats.swift tests/CatAgentListTests.swift tests/CatWiringTests.swift
git commit -m "refactor(cat): drop the unused botD, the pass-through cat1D and a duplicate pin

overviewCardShift only handed botD to pairExpanded, whose textLeading does not depend on it; PairExpanded.cat1D was the one cat's diameter handed back, read by
two lines of a test. Both signatures are shorter, and the two tests that said what others say (a pin that asserted the secondCatPlace guard twice, and a
'34 exactly' line) are gone. The layout's numbers do not change: the island and kitten sheets are drawn the same.

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

Run: `git status --short`
Expected: nothing.

---

### Task 9: Windows, the `BADGE_RIGHT` doc block

**Agent:** `nm-implementer-light`. The code is given in full.

**Files:**
- Modify: `windows/src/cat/kittendraw.ts`, `windows/scripts/cat-tests/kittendraw.test.mjs`

**The cause, confirmed.** In `kittendraw.ts` the doc block of `IN_ROW` ("The places whose "+N" sits in the row…") is followed by the doc block of `BADGE_RIGHT`, then `export const BADGE_RIGHT`, then `const IN_ROW`: `BADGE_RIGHT`'s block splits `IN_ROW`'s comment from `IN_ROW`. Each block goes above its own constant, and `IN_ROW`'s says `BADGE_RIGHT` instead of repeating "about 0.85 heads". Comments only: no code changes.

- [ ] **Step 1: Write the failing test**

```bash
cat >> windows/scripts/cat-tests/kittendraw.test.mjs <<'EOF'

test("each doc block sits directly above the constant it documents: BADGE_RIGHT's, then IN_ROW's, with no block between a constant and its own", () => {
  assert.match(source("cat/kittendraw.ts"), /\/\*\* Where a kitten's state badge ends[^\n]*\*\/\nexport const BADGE_RIGHT = 0\.85;\n\/\*\* The places whose "\+N" sits in the row[^\n]*\*\/\nconst IN_ROW = new Set\(/);
});
EOF
```

Run: `cd windows && npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; cd ..`
Expected: FAIL: `ℹ tests 274`, `ℹ pass 273`, `ℹ fail 1`.

- [ ] **Step 2: Move the blocks**

```bash
python3 - <<'PY'
# Task 9: BADGE_RIGHT's block moves above BADGE_RIGHT, and IN_ROW's stays above IN_ROW. Run from the repository root.
def edit(path, pairs):
    s = open(path, encoding='utf-8').read()
    for was, now in pairs:
        assert s.count(was) == 1, (path, was[:70])
        s = s.replace(was, now)
    open(path, 'w', encoding='utf-8').write(s)
edit('windows/src/cat/kittendraw.ts', [
('''/** The places whose "+N" sits in the row, right of the last kitten: its left edge clears that kitten's state badge (the badge's right edge is about 0.85 heads from the kitten's centre), and under the pair it is on the row's line, so it stays inside the card. */
/** Where a kitten's state badge ends on its right, in heads from the kitten's centre: the "+N" of a row starts there. */
export const BADGE_RIGHT = 0.85;
const IN_ROW''', '''/** Where a kitten's state badge ends on its right, in heads from the kitten's centre: the "+N" of a row starts there. */
export const BADGE_RIGHT = 0.85;
/** The places whose "+N" sits in the row, right of the last kitten: its left edge clears that kitten's state badge (`BADGE_RIGHT`), and under the pair it is on the row's line, so it stays inside the card. */
const IN_ROW'''),
])
PY
```

- [ ] **Step 3: Run the checks**

Run: `cd windows && npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; npx --no-install tsc --noEmit; echo "tsc exit $?"; cd ..`
Expected: PASS: `ℹ tests 274`, `ℹ pass 274`, `ℹ fail 0` and `tsc exit 0`.

- [ ] **Step 4: Commit**

```bash
git add windows/src/cat/kittendraw.ts windows/scripts/cat-tests/kittendraw.test.mjs
git commit -m "docs(cat): BADGE_RIGHT's and IN_ROW's doc blocks above their own constants

Co-Authored-By: Claude Haiku 4.5 <noreply@anthropic.com>"
```

Run: `git status --short`
Expected: nothing.

---

### Task 10: The final checks

**Agent:** `nm-implementer-light`. Everything here is a command with an expected output; if one differs and the cause is not obvious, hand the task to `nm-implementer-deep`.

**Files:** none.

- [ ] **Step 1: Every Mac test, and the guards**

Run: `for f in scripts/test-*.sh; do printf '%-42s' "$f"; bash "$f" 2>&1 | tail -1; done | grep -v "All tests passed."`
Expected: eleven lines, the scripts whose last line is not the usual one: `test-ai-contract.sh` (`OK`), `test-cat-contract.sh` (`✓ two generator runs write identical bytes`), `test-escape.sh` (`Escape routing: 21 cases passed`), `test-hotkeys.sh` (`HotKeyCenter: 19 cases passed`), `test-island-poller.sh` (`IslandPoller: visible 59 Hz, hidden 10 Hz, shown again 60 Hz`), `test-keynames.sh` (`Key layout names: 33 cases passed`), `test-safe-links.sh` (`Safe web links: 15 cases passed`), `test-screen-geometry.sh` (`Island screen geometry and resting layout: 13 cases passed`), `test-shortcuts.sh` (`Shortcuts: 496 cases passed`), `test-sound-build.sh` (`candidates folder not found: the clip files were not checked`) and `test-theme.sh` (`✓ 3 theme files match shared/theme.json`). Every other script (43 of them, the new config-file test among them) ended with "All tests passed." and printed nothing here.

Run: `bash scripts/check-no-leftovers.sh 2>&1 | tail -1; bash scripts/check-test-logs.sh; bash scripts/test-cat-contract.sh 2>&1 | grep -E "^# (tests|pass|fail)"; node scripts/check-fixtures-additive.mjs b13eed1 2>&1 | tail -1`
Expected: `✓ no notification that nothing posts or observes`, `✓ every log-writing test script sets NM_LOG_DIR`, `# tests 231`, `# pass 231`, `# fail 0` and `✓ fixtures changed only by addition since b13eed1`.

- [ ] **Step 2: The Windows checks**

Run: `cd windows && npx --no-install tsc --noEmit; echo "tsc exit $?"; npm run check:cat 2>&1 | grep -E "^ℹ (tests|pass|fail)"; npm run check:ai 2>&1 | tail -1; npm run check:claude 2>&1 | tail -1; cd ..`
Expected: `tsc exit 0` with no type error before it, `ℹ tests 274`, `ℹ pass 274`, `ℹ fail 0`, `All AI UI checks passed` and `All Claude Code UI checks passed`.

- [ ] **Step 3: The three builds and the three binaries**

Run: `cd NotchBuddy && xcodegen && cd .. && xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Release -derivedDataPath NotchBuddy/build/release build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | tail -3`
Expected: `Created project at …` and the last lines end with `** BUILD SUCCEEDED **`.

Run: `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath NotchBuddy/build build CODE_SIGNING_ALLOWED=NO 2>&1 | tail -3`
Expected: the last lines end with `** BUILD SUCCEEDED **`.

Run: `xcodebuild -project NotchBuddy/NotchBuddy.xcodeproj -scheme NotchMeowAppStore -configuration Debug -derivedDataPath NotchBuddy/build/store build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | tail -3`
Expected: the last lines end with `** BUILD SUCCEEDED **`.

Run: `bash scripts/check-app-binary.sh NotchBuddy/build/release/Build/Products/Release/NotchMeow.app release 2>&1 | tail -2; bash scripts/check-app-binary.sh NotchBuddy/build/Build/Products/Debug/NotchMeow.app debug 2>&1 | tail -2; bash scripts/check-app-binary.sh NotchBuddy/build/store/Build/Products/Debug/NotchMeow.app appstore 2>&1 | tail -2`
Expected: six lines, two for each build, all starting with `✓`.

- [ ] **Step 4: The sheets did not move**

The island and kitten sheets run through the code Tasks 6 to 8 touched. Draw them again and compare them with Task 0's, byte for byte.

```bash
O="${TMPDIR:-/tmp}/fixes-after-b-base"; N="${TMPDIR:-/tmp}/fixes-after-b-final"; mkdir -p "$N"
bash scripts/render-cats.sh --island --scale 2 --out "$N/island.png"
bash scripts/render-cats.sh --kittens --scenario life --out "$N/life-one.png"
bash scripts/render-cats.sh --kittens --scenario crowd --out "$N/crowd-one.png"
bash scripts/render-cats.sh --kittens --scenario life --mode two --out "$N/life-two.png"
for f in island life-one crowd-one life-two; do cmp "$O/$f.png" "$N/$f.png" && echo "$f.png is identical"; done
```

Expected: four `wrote … .png` lines, then `island.png is identical`, `life-one.png is identical`, `crowd-one.png is identical` and `life-two.png is identical`.

- [ ] **Step 5: Nothing outside the plan changed**

Run: `git diff --stat notchmeow/rebrand...HEAD -- design tests/fixtures scripts/gen-cat-fixtures.mjs docs/CAT-CONTRACT.md shared windows/src-tauri windows/hook | wc -l`
Expected: `0` (no contract file, no fixture, no generated theme file and no Rust file changed).

Run: `git diff --name-only notchmeow/rebrand...HEAD | sort`
Expected: these 31 paths, and no other: `.github/workflows/build.yml`, `CHANGELOG.md`, `CLAUDE.md`, `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj`, `NotchBuddy/Sources/App/AppState.swift`, `NotchBuddy/Sources/App/CatAgentList.swift`, `NotchBuddy/Sources/App/CatIslandLayout.swift`, `NotchBuddy/Sources/App/CatKittenDraw.swift`, `NotchBuddy/Sources/App/CatKittens.swift`, `NotchBuddy/Sources/App/ClaudePlanCardView.swift`, `NotchBuddy/Sources/App/ConfigFileWrite.swift`, `NotchBuddy/Sources/App/HookServer.swift`, `NotchBuddy/Sources/App/IslandRootView.swift`, `NotchBuddy/Sources/App/IslandViewContent.swift`, `NotchBuddy/Sources/App/KittenViews.swift`, `NotchBuddy/Sources/App/PairCatViews.swift`, `README.md`, `docs/SPEC.md`, `scripts/render-cats.swift`, `scripts/render-plan-card.sh`, `scripts/render-plan-card.swift`, `scripts/test-config-file-write.sh`, `tests/CatAgentListTests.swift`, `tests/CatKittensTests.swift`, `tests/CatWiringTests.swift`, `tests/ConfigFileWriteTests.swift`, `windows/scripts/cat-tests/kittendraw.test.mjs`, `windows/scripts/cat-tests/settings-ui.test.mjs`, `windows/src/cat/kittendraw.ts`, `windows/src/settings/cat.ts` and `windows/src/settings/settings.css`.

Run: `git log --oneline notchmeow/rebrand..HEAD | wc -l; git status --short`
Expected: `8` (one commit for each of Tasks 1, 2, 4, 5, 6, 7, 8 and 9), and then nothing from the status command (the worktree is clean).

**After Task 10**, the session dispatches `nm-reviewer-deep` over the whole branch (`git diff notchmeow/rebrand...HEAD`), with the Review Focus, the Global Constraints and these cross-task contracts to check: **the shipping views** (only the two named: the Windows slider rows, and the Mac plan card's header and percent column; no other view, row or Settings section differs, and the One cat layout is untouched); **the config rule** (the preview, the confirm, the dated backup and the diff are as they were, and nothing writes outside a temp folder in a test); **the scope** (nothing under `design/`, `tests/fixtures/`, `shared/`, `windows/src-tauri/` or `windows/hook/`; `docs/CAT-CONTRACT.md` untouched; no Coucou or Mochi name written as an identity); **0 % CPU** (no timer or polling added; the kitten layer pauses, and wakes when it must); every name in the interface tables is the one the tasks use (`planPercentWidth`, `planRowsTrailing`, `ConfigFileWrite.resolved`/`backUp`/`write`, `CatKittens.mayStop`, `CatKittenHerd.lastFrameEmpty`, `CatAgentList.touchReorders`, `pairExpanded(botX:cy:)`, `overviewCardShift(second:botX:)`). Fix what it finds, re-run the checks above, and report.

---

### Task 11: Owner checkpoint 2: the final report and the checks only a real build can do

No code and no commit. The session reports; the main session sends the owner the final report and, for the plan card and the sliders, the pictures of `.claude/checkpoints/fixes-after-b-1/` again if Task 1 or 2 changed after Checkpoint 1 (and the sheets' "identical" lines), and asks the owner to run the Debug build (`NotchBuddy/build/Build/Products/Debug/NotchMeow.app`; quit the installed app first) and, on Windows, a real build, and check:

1. **Windows, Settings → Cat → Personality** in a real build (WebView2, Segoe UI, a real scrollbar), at the window's size and dragged to its minimum: the six rows stay on one line and the sliders line up. This is the check the headless pictures cannot make (a Mac's Chromium is not WebView2).
2. **Mac, the plan card** (Settings → Agents → Plan usage on, then the pill in the island's header): with data, "100%" is on one line when the weekly window is full; with no data yet ("Waiting for a Claude Code reply") the title "Claude plan" is there; in Two cats mode a subtitle of "59 min ago" is whole. The App Store build has no plan card.
3. **A symlinked config, in a throwaway home.** Make a folder with a `.gemini/settings.json` that is a link to a file beside it, with mode 0600, and run the Debug build against it (or use a machine's own dotfiles setup the owner is happy to touch): Settings → Gemini CLI → Install hooks. The link is still a link, the file it points at has the hooks, it is still 0600, and `settings.json.bak-…` next to the link is a plain file with the old text. The same for `~/.claude/settings.json` (Settings → Claude Code → Install hooks, and Plan usage → Install relay): the diff is shown, nothing is written before the click, and the dated backup comes first. **This check writes the real file of whoever runs it: it is the owner's to do, on a copy.**
4. **Settings → Cat → Display → A cat for each agent, with Settings left open:** run a hook event from a second agent (an `nm_agent` event through the socket, or a real Codex or Gemini run): "Cats for your agents" reorders itself, most recent first, without the window being closed and opened.
5. **CPU with the island open and a subagent that has finished** (`python3 scripts/fake-subagent-events.py --scenario life` against the Debug build, answer the approval card when it comes): after the last kitten has left, with the island open and the cat awake, Activity Monitor shows the same idle level as before any kitten; `Two cats` mode with a kitten still shows its "×N" count as before.
6. **The docs**: `docs/SPEC.md` §7 and the Cat section of §10 read right in French, and the two lines Task 5 Step 2b fixed (README's roadmap row A, CLAUDE.md's "being built") read right.

Record the owner's answers in the PR description. What was **not** done: no commit was pushed; the Windows `cargo check` and a release build (owed to CI); the real-build checks above; (the roadmap row A and CLAUDE.md's "(being built)" were fixed in Task 5 Step 2b).

---

## Open questions for the owner

Each has the answer this plan assumes, so nothing blocks. A different answer changes one small thing, named in each.

1. **Claude Code's own `settings.json` goes through `ConfigFileWrite` too** (`writeClaudeHooks`, `writeStatusLine`, `uninstallClaudeHooks`, and the backups of the first two), not only `writeJSONFile`. It is the same defect in the file most likely to be a link, and the same helper; the flow (preview, confirm, dated backup) is pinned unchanged. **Assumed: yes.** To keep to `writeJSONFile` alone, drop the three edits of Task 4's Step 4 that name `settingsURL` and the three pins that read them.
2. **The waiting card cuts its subtitle** ("Waiting for a Claud…") instead of making room or changing the words, and the header takes the rows' 12 pt right margin in both layouts (36 pt was room for a jump button that is hidden while the card is open). **Assumed: yes.** The alternative is a shorter text ("Waiting for Claude Code"), a copy change.
3. **The percent column is 34 pt in both rows** (the stacked row's was 36), so the shipping row's reset labels move 4 pt to the right and the stacked row's percent 2 pt left. The shipping row with "Resetting…" ends 8 pt inside the card (it was 12). **Assumed: yes.**
4. **Task 4 adds one file and one CI step** (`ConfigFileWrite.swift`, `scripts/test-config-file-write.sh`). **Assumed: yes.** It is Foundation-only, in both builds, and used only by the GitHub build's Gemini, Codex and Antigravity installers and by Claude Code's two (the App Store build never reaches them).
5. **The App Store build's two direct writes of `settings.json` stay.** Its sandbox grant is the folder the user picked, and a link's target may be outside it, which no test here can try. **Assumed: yes.**
6. **The agents' list publishes when an event makes a pill the most recent**, which is a handful of times in a session; it does not publish at every event. **Assumed: yes.**
7. **A kitten layer that shows only the pair's "×N" label keeps asking for frames while kittens exist** (as it does today): "empty" means no kittens at all. **Assumed: yes.**
8. **Left for the owner or the main session:** the README roadmap row A ("in progress"), CLAUDE.md's "(being built)" for the prototype, and `windows/README.md`'s "The 28 sounds are the macOS app's own files" (the folder is empty). None is about this batch's cats. **Assumed: left.**
9. **The Windows twin gets no change**, and Task 4's Step 7 runs two existing tests through `cargo-linux.sh` once to say so. It compiles the workspace into `--target-dir /repo/windows/target/fixes-after-b` (some minutes, offline, no image built). **Assumed: yes.**

## Self-review

- **Spec coverage.** The owner's items: 1 (Task 1), 2 (Task 2: the three defects, the layout numbers in `CatIslandLayout`, their tests, before and after pictures of the shipping and stacked cards with data and waiting), 3 (Task 4: `writeJSONFile` and its siblings, the test in a temp folder, the CLAUDE.md rule pinned, the Windows twin checked and run once through `cargo-linux.sh` with its own target directory), 4 (Task 5), 5 (Tasks 6 to 9, each its own commit, and what B's plans left on purpose left alone). The checkpoints: after the visual fixes (Task 3) and at the end (Task 11). The rules are in the SUBAGENT RULES.
- **Placeholders.** None: every code step is a full file or a script whose replacements assert that their anchor occurs exactly once, and every `Run:` line has its expected output.
- **Type consistency.** `planPercentWidth` (Task 2) is read by both rows and by Task 2's tests; `overviewCardShift(second:botX:botD:)` is what Task 2's test calls and Task 8 shortens to `(second:botX:)` (every call site of both is edited in Task 8, and a grep says none is left); `ConfigFileWrite.resolved`, `backUp` and `write` (Task 4) are what `HookServer` and the test use; `CatKittens.mayStop` and `CatKittenHerd.lastFrameEmpty` (Task 6) are what the layer and its pin use; `CatAgentList.touchReorders` (Task 7) is what `AppState.touchPill` and its tests use.
- **Review Focus.** Lines 1 to 5 each name their tests.
- **What this plan deliberately does not do:** touch `cat-core.js`, a fixture, the contract or anything under `windows/src-tauri/` or `windows/hook/`; launch any app; restyle any view beyond the two named; change the App Store build's behaviour; make a timer; change the Windows twin.

---

## Dry run (2026-10-08)

The plan was run before it was handed over: every task was built and checked in a throwaway clone while the plan was written, and **then the finished file was replayed from the top in a fresh clone**, so that every block applies and every `Run:` line prints what its `Expected:` says. Nothing was committed or pushed in the main checkout, no NotchMeow app and no Tauri app was started, nothing was installed or downloaded, and no network was used. The only file this work added to the main checkout is this plan, untracked.

**Set-up.** `git clone --local --shared` of this repository, with its branch put at `b13eed1` (the branch tip had moved to `582d8b9`, a docs-only commit that adds sub-project H's design spec, after this plan was asked for; it touches nothing this plan touches, and the plan says "`b13eed1` or later"), in the session scratchpad. The plan's own Task 0 did the rest: the branch, the `cp -cR` of the main checkout's `windows/node_modules` as a real folder, the baseline, the base sheets. The scratch pictures' folders under `$TMPDIR` were emptied before the replay, so nothing a former run left behind could make a step pass. The Docker image `notchmeow-linux-dev` was there; no image was built. **The commit steps were run in the clone** (it is a throwaway), which proves the `git add` lists: after each one `git status --short` printed nothing, and a script compared each add list with the files of the commit it made.

**Method.** A small runner reads the plan's text, runs its `bash` blocks and its `Run:` lines in order in the clone, prints each command's output next to the plan's `Expected:` line, and checks that every backticked literal of every `Expected:` line is in the output. The whole plan replayed with **37 blocks and 56 `Run:` lines (93 items), 0 commands that exited non-zero, 256 expected literals compared and 0 missing, and 8 commits whose `git add` lists are exactly the files each changed** (30 paths in all, the list of Task 10). The commands took about 20 minutes in all, seven of them the Mac test loop of Task 10 and two the baseline's cat tests; a cold Release build was the next longest. After the last wording fix (the order of the lines Task 1 prints) Tasks 0 and 1 were replayed once more from a fresh clone.

| Task | Agent | What the run printed (the plan's Expected) |
|---|---|---|
| 0 | the session | the base check; `tsc exit 0`, `check:cat` 272, `check:ai` and `check:claude`; the contract's `# tests 231`, 14 fixture files, fixtures additive; 25 `All tests passed.` and the contract's line; the guards and `image ok`; four base sheets |
| 1 | `nm-implementer` | before: 0 of 6 rows on one line at 560, 543, 460 and 443; red: `check:cat` 273 tests, 272 pass; green: 273, `tsc exit 0`; after: 6 of 6 at every width (slider 138, 121, 77 and 69 px), and in Verdana too; the other rows the same size at all four widths |
| 2 | `nm-implementer` | five before pictures; red: 2 and 2 failures; green; with the column back at 30, 2 fail; five after pictures; 0 pixels differ in the header band and in the first row's label and bar, 1799 in the rest of that row; the Debug build |
| 3 | the session | fourteen pictures collected |
| 4 | `nm-implementer` | the probe's three lines; red: `error opening input file`, then 5 pins; green; with `write` on the link 6 fail, with `backUp` on the link 2 fail; the project +6 lines; Debug and App Store builds; the two Windows tests, `2 passed … 244 filtered out` |
| 5 | `nm-implementer-light` | `docs/SPEC.md` 25 insertions and 14 deletions, no `mochi`; README and CHANGELOG 6 and 5; the word `mochi` only in the changelog's history and CLAUDE.md's rule |
| 6 | `nm-implementer` | red: 8 compile errors and 1 pin; green; with the rule on either fact, 5 fail; Debug build |
| 7 | `nm-implementer-light` | red: 1 compile error and 1 pin; green; with the rule always no, 4 fail; Debug build |
| 8 | `nm-implementer-light` | red: 1 compile error and 1 pin; green; no `botD` or `cat1D` left; four other programs green; Debug build |
| 9 | `nm-implementer-light` | red: `check:cat` 274, 273 pass; green: 274, `tsc exit 0` |
| 10 | `nm-implementer-light` | the eleven odd last lines of 54 scripts and 43 `All tests passed.`; the guards; `check:cat` 274; Release, Debug and App Store builds; the six `check-app-binary.sh` lines; the four sheets identical to Task 0's; 0 contract files changed; the 30 paths; 8 commits and a clean tree |

**The pictures were looked at, every one.** The Windows Settings section at 560 × 680 and 460 × 680, before and after (the high labels under the sliders and three lines to a row, then one line to a row with the six sliders in a column); the plan card's five before and five after pictures (the wrapped "100", the missing title with the rows far too low, "Waiting…" and "59 min a…", then "100%" on one line, the title back with the subtitle cut, "59 min ago" whole); and the island sheet and the kitten sheet (life, Two cats), which came out identical to the base. Nothing was blank or broken.

**What the dry run changed in the plan** (each was a defect in an earlier draft, found because a step failed, printed something else or drew something wrong, and is fixed in the text):

- **The percent column.** The first draft gave the shipping row the stacked row's 36 pt. With the measured arrow and labels the row is then 202.5 pt in the 202 it has; 34 pt (still 1.9 pt more than "100%" needs) is 200.5, and the tests now measure the text with AppKit instead of the "about 48 pt" estimate the earlier card's tests used.
- **The waiting card's rows.** The squeezed title wrapped one letter at a time, so the header was tall and pushed the rows about 30 pt down: this was not in the owner's list, and the fix removes it (the pictures show it; the checkpoint says so).
- **`resolvingSymlinksInPath` is not enough.** It returns a link to a file that is not there yet unchanged, so a write replaced the link; `resolved` walks the chain itself (a relative link is read from the folder it really sits in, which a test with `~/.claude` as a link proves), and a loop ends after 32.
- **The same defect was in Claude Code's own writes.** `writeJSONFile` is Gemini's, Codex's and Antigravity's files; `~/.claude/settings.json` has three writers of its own, with the same atomic write and the same backup of a link (the probe shows the backup is a link). Open question 1.
- **Foundation keeps a plain file's mode.** An atomic write to a plain 0600 file comes back 0600, so no permission code is needed once the write goes to the file at the end of the links; the only mode that is wrong is a link's own 0755.
- **The first measure counted seven slider rows**: the Sound volume slider is one too. It selects the rows by their `.cat-low` end.
- **Swift 6.** `@MainActor` on the config test's enum, a mixed-type array in a `CT.check`, and a type-check that gave up on one test line until the compile errors were gone.
- **zsh is not bash.** An unquoted `$a` is not split and a `rm -f rows-*.json` with no match is an error in zsh: the blocks use neither, and run with `bash`.
- **Expected texts were corrected to the real output** many times: counts, a diff stat (`README.md | 7 +++----`), the order of the Verdana lines, literals that were prose.

**Not run, and owed.**

- **The apps themselves.** No NotchMeow window and no Tauri window was opened: the real island with a real event, the plan card on a real screen, the kitten layer's CPU in Activity Monitor, "Cats for your agents" reordering with Settings open, and the symlinked config in a real home are Checkpoint 2's list for the owner. The Windows rows were drawn by headless Chromium on a Mac, in the system font; WebView2 and Segoe UI (and a real scrollbar) are the owner's check, softened by the 543 and 443 px widths and a font much wider than Segoe UI.
- **The Windows `cargo check` and a release build,** owed to CI as before; Task 4 ran two existing tests through `cargo-linux.sh` (offline, with this plan's own target directory) and nothing else of Rust.
- **Signing.** The three builds are unsigned (`CODE_SIGNING_ALLOWED=NO`).
- **The Mac's frame time.** No cat drawing changed, so the bench was not read.

The throwaway clones, the pictures' folders and the scratch programs were moved to the Trash afterwards (`trash`, never `rm -rf`).

## The owner's answers (2026-10-08)

- **Open questions 1 to 9: approved as assumed.** Claude Code's own `settings.json` writes go through `ConfigFileWrite` too (the backup, diff and confirm flow unchanged); the percent column is 34 pt in both layouts; the waiting card cuts its subtitle; `ConfigFileWrite.swift` and its CI step are added; the App Store build's two direct writes stay; the agents' list publishes only when the order changes; the pair's "×N" keeps the layer drawing; the Windows twin needs no change.
- **Open question 8, partly changed:** the README roadmap row for A and CLAUDE.md's "(being built)" are fixed in Task 5 (Step 2b, added by the main session and replayed on `582d8b9`: 4 files, +33 −21). The "28 sounds" line of `windows/README.md` is left to the sound pack's merge, which makes it true.
- The base may be `582d8b9` or later (it adds only the sub-project H spec, which this plan doesn't touch).

## After the sound pack merged (2026-10-08, the owner's answer)

The sound pack merged into `notchmeow/rebrand` at `7435680` after this plan was written, and auto mode refused the first dispatch of Task 1 ("Modify Shared Resources"). The owner approved these corrections, replayed in a throwaway clone (Task 5 at `1627851`: `4 files changed, 35 insertions(+), 22 deletions(-)`, the commit lands, and the branch merges cleanly into `7435680`):
- **Task 5:** the README's note, roadmap row C and its "How it works" sounds line, and the changelog, say NotchMeow's sounds are built (they said "still to come"); the commit message's `"(being built)"` closed the `-m` string, so it is `'(being built)'`; the expected numbers follow.
- **Task 10:** the two `git diff` checks compare with the merge base (`notchmeow/rebrand...HEAD`), so commits that land on `notchmeow/rebrand` meanwhile do not count.
- **Task 1 and the rules:** the Vite server is started with `exec node node_modules/vite/bin/vite.js --strictPort`, its process ID saved, and stopped by that ID, never by port; browser sessions are closed by name, never `close-all`.
- **The branch:** `fixes/after-b` had no commit of its own yet, so it fast-forwards to `notchmeow/rebrand` before Task 1; the base is that commit.
