# Spotify and Apple Music (Mac): Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** The music pill (`integration_music`, GitHub build only) follows Apple Music and Spotify: it shows whichever plays, says which ("Apple Music" or "Spotify"), and its controls act on that app.

**Architecture:** One pure Foundation file, `MusicFollow.swift`, holds every decision: the two apps' table (bundle ID, notification, label, grant flag), the player-state words, the track clean-up (moved from `MusicController`), the shown-app rule, the AppleScript texts (each guarded by `is running`) and the words shown. `MusicController.swift` keeps its shape and public API; it listens to both notifications, keeps one `MusicFollow`, and sends every script through one guarded path. The views change words only.

**Tech Stack:** Swift 6, SwiftUI + AppKit, `swiftc` test programs under `tests/` run by `scripts/test-*.sh`.

**Spec:** `docs/superpowers/specs/2026-10-22-spotify-design.md`. This plan takes the spec's recommended answer to each of its five questions; if the owner answers otherwise, the lines to change are named under "If the owner answers otherwise".

**Base:** a new branch `music/spotify-mac` in a git worktree from `main` at `2701c1ef` or later (`git merge-base --is-ancestor 2701c1ef HEAD` must succeed). If a find text below does not occur exactly once, stop and report; do not guess.

## Global Constraints

Every task's requirements include this section.

- **GitHub build only.** `MusicFollow.swift` and `MusicController.swift` start with `#if !APPSTORE` and end with `#endif`; the pill stays `githubOnly: true`. The App Store build gains nothing: no `NM_MUSIC_FOLLOWS_SPOTIFY`, no `com.spotify.client` in its binary (`scripts/check-app-binary.sh appstore`).
- **Never launch an app to ask it.** Every AppleScript goes through `MusicController.send(_:_:)`, which returns at once unless `NSRunningApplication` lists that app; every script text starts with `if application id "<id>" is running`/`is not running` (built in `MusicFollow`). `NSWorkspace.shared.open(` stays at 2 uses (Open Music's `/System/Applications/Music.app`, and the Automation settings URL); no `openApplication`, no `launchApplication`.
- **No poll, no timer:** notifications and `NSWorkspace` launch/terminate observers only, as today. No `Timer`, `asyncAfter`, `DispatchSource` in either file.
- **Privacy:** title, artist and album live in memory only. No `appendAppLog`, `print(`, `NSLog`, `Logger(`, `os_log` in either file. Stored values: the two grant flags only, `notchmeow.musicAutomationGranted` (unchanged, so an Apple Music user is never asked again) and `notchmeow.spotifyAutomationGranted` (new).
- **Never restyle:** colours, sizes, paddings, fonts and the layout of `MusicPill`, `MusicCardView` and the Settings card stay as they are. Only the words named in Task 2 change. The pill and dot stay `#FA2D48` for both apps.
- **Frozen values untouched:** the pill ID `integration_music`, its colour, `githubOnly`, the key `notchmeow.musicAutomationGranted`, `AppState.musicPlaying` and `AppState.musicAutomationDenied` (their meaning becomes "the shown app"), the `musicReveal` notification.
- **Swift 6, no new dependency.** `MusicFollow.swift` imports Foundation only.
- **Models and commits** (CLAUDE.md, "Working with AI agents"): Haiku 5.5 first; Sonnet 5.5 only on a named trigger; never Opus or Fable. Each commit is local, never pushed, lists only its task's files, uses `git commit -F <file>`, and ends with the `Co-Authored-By` line of the model that did the task. A task that ran `xcodegen` after adding a Swift file also commits `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj`.
- **SUBAGENT RULES (put this block in every subagent brief):**
  1. Never launch, quit or script Music, Spotify or any other app; never run `osascript`; never post the fake notifications (`scripts/fake-music-events.swift` is run with `--dry-run` only, by its test). Never launch, quit or replace any NotchMeow app.
  2. Install nothing. No network calls.
  3. Use `trash`, never `rm -rf`, for anything you delete by hand; scratch files go under `${TMPDIR:-/tmp}` in a uniquely named folder.
  4. Never edit `design/prototype/cat-core.js`, `shared/*`, a generated theme file, a fixture under `tests/fixtures/`, or anything under `windows/`.
  5. Never push. Commit only in a task's commit step, after `git rev-parse --show-toplevel` shows this worktree and `git branch --show-current` shows `music/spotify-mac`.
  6. Never rename a frozen ID; write no `Coucou` or `Mochi` name anywhere.
  7. Never read, print or write anything in the real `~/.claude`, `~/.gemini`, `~/.codex`.
  8. If a command is denied by a permission prompt, stop and report it.

## Review Focus

The spec is silent on these; most likely first. Each names the test that pins it.

1. **Both apps play, the shown one pauses.** Expected: the other app, still playing, shows at once; the cat keeps dancing; no reveal fires. Test: Task 1 ("the shown one pauses while the other plays").
2. **The shown app quits or stops while the other is paused.** Expected: the paused one shows with its last track; with both gone the pill goes back to "Music" and the dance stops. Tests: Task 1 ("Spotify stops…", "Apple Music quits…"); Task 2 pin (the terminate observer calls `follow.remove(`).
3. **Spotify not installed, or quit between the check and the click.** Expected: no script is compiled for it (macOS would ask "Where is Spotify?"), nothing is launched. Tests: Task 1 (every script text starts with the `is running` guard); Task 2 pins (`runAppleScript(` appears twice: its definition and the one call inside `send`, which begins `guard isRunning(app) else`).
4. **A refusal for one app while the other plays.** Expected: a playing Apple Music is not hidden by Spotify's refusal; the card names the app that refused; Apple Music's grant flag is untouched. Tests: Task 1 (`deniedToShow`, `grantedKey`).
5. **A notification with an unknown or missing `Player State`, or no `Name`.** Expected: an unknown state is ignored; a missing name shows no title, as today. Test: Task 1 (`fromNotification`, the blank track).

Also covered: the track clean-up unchanged (Task 1), the App Store binary (Task 2, `check-app-binary.sh`), no log call (Task 2 pins), the new key allowlisted (Task 1, `test-settings-map.sh`).

---

## File Structure

| Path | Responsibility |
|---|---|
| `NotchBuddy/Sources/App/MusicFollow.swift` (new) | The pure rules (Task 1). |
| `tests/MusicFollowTests.swift`, `scripts/test-music-follow.sh` (new) | Their tests (Task 1). |
| `tests/SettingsMapTests.swift` (modify) | The Spotify grant flag allowlisted (Task 1). |
| `NotchBuddy/Sources/App/MusicController.swift` (rewrite) | Both notifications, one `MusicFollow`, the guarded script path, per-app refusals (Task 2). |
| `NotchBuddy/Sources/App/IslandViewContent.swift`, `PillCatalog.swift`, `SettingsSections.swift` (modify) | Words: status line, card lines, Open button, the pill's idle name, the Settings help (Task 2). |
| `NotchBuddy/project.yml`, `NotchBuddy/Resources/Info.plist`, `scripts/test-release-tools.sh`, `scripts/render-settings.swift` (modify) | The Automation purpose line and the Settings sample (Task 2). |
| `scripts/check-app-binary.sh` (modify) | The marker and Spotify's name: in Release and Debug, not in App Store (Task 2). |
| `tests/MusicWiringTests.swift`, `scripts/test-music-wiring.sh` (new) | Source pins (Task 2). |
| `scripts/render-music.swift`, `scripts/render-music.sh` (new) | The checkpoint picture (Task 3). |
| `scripts/fake-music-events.swift`, `scripts/test-fake-music-events.sh` (new) | The owner's fake notification sender and its dry-run test (Task 3). |
| `.github/workflows/build.yml` (modify) | The three new test scripts (Tasks 1 to 3). |
| `CLAUDE.md`, `README.md`, `docs/SPEC.md`, `docs/INTEGRATIONS.md` (modify) | Docs (Task 4). |

## Tasks and agents

Coding agents load `ponytail:ponytail`, `superpowers:test-driven-development`, `superpowers:verification-before-completion`, and read `swift-concurrency-6-2` *(file: `~/.claude/plugins/marketplaces/ecc/skills/swift-concurrency-6-2/SKILL.md`)* for Task 2. Reviewers load `ponytail:ponytail-review`. The final reviewer also loads `security-review` and runs `pr-review-toolkit:silent-failure-hunter` beside it (`model: sonnet`, trigger 4).

| # | Task | Agent, model, effort | Trigger | Review |
|---|---|---|---|---|
| 0 | Worktree and baseline | the session | | none |
| 1 | The pure rules, their tests, the allowlist | `nm-implementer`, Haiku 5.5, high | | `nm-reviewer` |
| 2 | The controller, the words, the purpose line, the binary check, the pins | `nm-implementer`, Haiku 5.5, high | | `nm-reviewer` |
| 3 | The picture and the fake sender | `nm-implementer`, Haiku 5.5, high | | `nm-reviewer` |
| 3b | **Owner checkpoint 1:** the picture and the five questions | the main session and the owner | | none |
| 4 | Docs | `nm-implementer-light`, Haiku 5.5, medium | | `nm-reviewer` |
| After 4 | The whole branch: never launch, App Store fence, privacy | `nm-reviewer-deep`, Sonnet 5.5, high | 4 | none |
| 5 | **Owner checkpoint 2:** the real machine | the main session and the owner | | none |

Why no Sonnet implementer: the AppleScript runner, the observers and the main-actor hop already exist and are kept; Spotify's scripts are the same template with its bundle ID and one verb; every new decision is in the pure file. Trigger 1 does not apply. If a Haiku task fails twice, hand it to `nm-implementer-deep` (trigger 2) and write it in the ledger.

## Execution

One worktree chat session, branch `music/spotify-mac`, **Haiku 5.5 at high effort** (no trigger 5: three coding tasks, one interface between them). It edits `IslandViewContent.swift`, `PillCatalog.swift`, `SettingsSections.swift`, `tests/SettingsMapTests.swift`, `scripts/check-app-binary.sh`, `scripts/test-release-tools.sh`, `project.yml`, `Info.plist`, `build.yml` and `project.pbxproj`: do not run it beside another plan that edits them (`project.pbxproj` and `build.yml` merge mechanically; re-run `xcodegen` for the former). Start it in the three steps of `ARCHITECT.md`. The session pings the main session with `SendMessage` at Task 3b, at the end and whenever it stops. Ledger: `.superpowers/sdd/2026-10-22-spotify-mac/progress.md` (one line per task: agent, model, commit, test lines, review verdict). Reviews read `git diff main...HEAD` narrowed to the task's files.

---

### Task 0: Worktree and baseline

- [ ] **Step 1:** `git switch -c music/spotify-mac main` in the new worktree; `git merge-base --is-ancestor 2701c1ef HEAD && echo ok` prints `ok`.
- [ ] **Step 2:** Anchor counts, each must print `1`:
  ```bash
  V=NotchBuddy/Sources/App/IslandViewContent.swift
  grep -cF 'if appState.musicAutomationDenied { return "Automation not allowed" }' $V
  grep -cF 'Button("Open Music") { MusicController.shared.openMusic() }' $V
  grep -cF 'Text("Apple Music")' $V
  grep -cF 'Text("Allow NotchMeow to control Music")' $V
  grep -cF 'if let artist = controller.artist {' $V
  grep -cF '            MusicCardView()' $V
  grep -cF '.init(id: "integration_music",   name: "Apple Music", color: "#FA2D48",' NotchBuddy/Sources/App/PillCatalog.swift
  grep -cF 'help: "Shows what the Music app is playing. Nothing to enter."),' NotchBuddy/Sources/App/SettingsSections.swift
  grep -cF 'help: "Shows what the Music app is playing. Nothing to enter."))' scripts/render-settings.swift
  grep -cF 'send mail and control Music."' NotchBuddy/project.yml
  grep -cF 'send mail and control Music.</string>' NotchBuddy/Resources/Info.plist
  grep -cF "APPLE='NotchMeow uses this to jump to your terminal, send mail and control Music.'" scripts/test-release-tools.sh
  B=scripts/check-app-binary.sh
  grep -cF 'linkpeer=0; has NM_LINK_DEV_PEER && linkpeer=1' $B
  grep -cF 'echo "✓ No cat panel and no Claude Code override in this build; the Claude Code engine is in it" ;;' $B
  grep -cF 'echo "✓ No cat panel and no Claude Code engine in this build" ;;' $B
  grep -cF 'echo "✓ The cat panel, the Claude Code engine and its override are in this Debug build" ;;' $B
  grep -cF '("notchmeow.musicAutomationGranted", "the Music automation grant flag' tests/SettingsMapTests.swift
  grep -cF '      - name: Island right wing wiring (source pins of the panel, AppState and the view)' .github/workflows/build.yml
  ```
- [ ] **Step 3:** Baseline: `bash scripts/test-settings-map.sh && bash scripts/test-release-tools.sh && bash scripts/test-cat-sleep.sh` pass. Write the ledger's first line.

---

### Task 1: The pure rules, their tests, the allowlist

**Files:**
- Create: `NotchBuddy/Sources/App/MusicFollow.swift`, `tests/MusicFollowTests.swift`, `scripts/test-music-follow.sh`
- Modify: `tests/SettingsMapTests.swift`, `.github/workflows/build.yml`, `NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` (by `xcodegen`)

**Interfaces:**
- Consumes: `CT` (`tests/CatTestSupport.swift`).
- Produces (Tasks 2 and 3 rely on these exact names):
  ```swift
  #if !APPSTORE
  enum MusicApp: String, CaseIterable, Sendable {
      case appleMusic, spotify                       // this order is the first-read order
      var bundleId: String                           // "com.apple.Music", "com.spotify.client"
      var notificationName: String                   // "com.apple.Music.playerInfo", "com.spotify.client.PlaybackStateChanged"
      var label: String                              // "Apple Music", "Spotify"
      var grantedKey: String                         // MusicFollow.appleMusicGrantedKey, MusicFollow.spotifyGrantedKey
      static func of(bundleId: String?) -> MusicApp? // exact match only
  }
  enum MusicPlayback: Equatable, Sendable {
      case playing, paused, stopped
      static func fromNotification(_ state: String?) -> MusicPlayback?   // "Playing" / "Paused" / "Stopped" exactly; anything else nil
      static func fromScript(_ state: String) -> MusicPlayback?          // "playing", "fast forwarding", "rewinding" → playing; "paused"; "stopped"; else nil
  }
  struct MusicTrack: Equatable, Sendable {
      var title: String?; var artist: String?; var album: String?
      init(name: String?, artist: String?, album: String?)   // shortTitle / shortArtist as today; blank (whitespace only) → nil
      static func shortTitle(_ raw: String) -> String        // moved unchanged from MusicController
      static func shortArtist(_ raw: String) -> String       // moved unchanged from MusicController
  }
  enum MusicCommand: Sendable { case playPause, next, previous }
  struct MusicFollow: Equatable, Sendable {
      static let appleMusicGrantedKey = "notchmeow.musicAutomationGranted"
      static let spotifyGrantedKey = "notchmeow.spotifyAutomationGranted"
      static let deniedCode = -1743
      struct Entry: Equatable, Sendable { var playback: MusicPlayback; var track: MusicTrack; var order: Int }
      private(set) var entries: [MusicApp: Entry]
      init()
      mutating func apply(_ app: MusicApp, _ playback: MusicPlayback, _ track: MusicTrack)  // .stopped removes the app
      mutating func remove(_ app: MusicApp)
      mutating func clear()
      var shown: MusicApp? { get }          // playing beats paused; between equals, the higher order
      var shownTrack: MusicTrack? { get }
      var isPlaying: Bool { get }           // the shown app's playback is .playing
      static func script(_ command: MusicCommand, for app: MusicApp) -> String
      static func readScript(for app: MusicApp) -> String
      static func statusLine(shown: MusicApp?, playing: Bool, title: String?, denied: MusicApp?) -> String
      static func secondLine(artist: String?, app: MusicApp?) -> String?
      static func deniedToShow(denied: Set<MusicApp>, shown: MusicApp?, lastDenied: MusicApp?) -> MusicApp?
  }
  #endif
  ```

The rules (spec, "The rules"):
- `apply` stamps `order` from a private counter that grows by one per call (no clock). A `.stopped` from an app never seen changes nothing.
- `script`: three lines, `if application id "<id>" is running then` / `    tell application id "<id>" to <verb>` / `end if`. Verbs: `playpause`, `next track`; previous is `back track` for Apple Music (today's) and `previous track` for Spotify.
- `readScript`: first line `if application id "<id>" is not running then return {"stopped", "", "", ""}`, then `tell application id "<id>"`, then today's body from `MusicController.fetchAndApply` (from `set ps to player state as string` to `return {ps, n, ar, al}`, indented 4), then `end tell`.
- `statusLine`: `denied` set → `"<label>: automation not allowed"`; else shown and playing → `"<label> · Playing · <title or Unknown>"`; shown, not playing → `"<label> · Paused"`; nothing → `"Not playing"`.
- `secondLine`: `"<artist> · <label>"`, or either alone, or nil.
- `deniedToShow`: with a shown app, that app if it is in `denied`, else nil; with none, `lastDenied` if it is in `denied`, else nil.

- [ ] **Step 1: Write the failing test** `tests/MusicFollowTests.swift` (`@main enum MusicFollowTests { static func main() { … } }`):
  ```swift
  CT.section("the two apps")
  CT.check("order", MusicApp.allCases, [.appleMusic, .spotify])
  CT.check("bundle IDs", MusicApp.allCases.map(\.bundleId), ["com.apple.Music", "com.spotify.client"])
  CT.check("notifications", MusicApp.allCases.map(\.notificationName), ["com.apple.Music.playerInfo", "com.spotify.client.PlaybackStateChanged"])
  CT.check("labels", MusicApp.allCases.map(\.label), ["Apple Music", "Spotify"])
  CT.check("grant flags: Apple Music keeps today's", MusicApp.allCases.map(\.grantedKey), ["notchmeow.musicAutomationGranted", "notchmeow.spotifyAutomationGranted"])
  CT.check("of(bundleId:) is exact", [MusicApp.of(bundleId: "com.spotify.client"), MusicApp.of(bundleId: "com.apple.Music"), MusicApp.of(bundleId: "com.apple.music"), MusicApp.of(bundleId: nil)], [.spotify, .appleMusic, nil, nil])

  CT.section("player states")
  CT.check("notification words", ["Playing", "Paused", "Stopped", "playing", "Buffering", ""].map { MusicPlayback.fromNotification($0) }, [.playing, .paused, .stopped, nil, nil, nil])
  CT.check("no state", MusicPlayback.fromNotification(nil), nil)
  CT.check("script words", ["playing", "paused", "stopped", "fast forwarding", "rewinding", "kPSP", ""].map { MusicPlayback.fromScript($0) }, [.playing, .paused, .stopped, .playing, .playing, nil, nil])

  CT.section("the track, cleaned as today")
  let t = MusicTrack(name: "Song (Remastered 2011) [Live] - Radio Edit", artist: "Ana feat. Bo", album: "")
  CT.check("title", t.title, "Song"); CT.check("artist", t.artist, "Ana"); CT.check("blank album", t.album, nil)
  CT.check("a title that is only brackets stays", MusicTrack(name: "(Intro)", artist: nil, album: nil).title, "(Intro)")
  CT.check("ft.", MusicTrack(name: "x", artist: "Ana ft. Bo", album: nil).artist, "Ana")
  CT.check("blank and missing", [MusicTrack(name: nil, artist: "  ", album: nil).title, MusicTrack(name: nil, artist: "  ", album: nil).artist], [nil, nil])

  CT.section("which app is shown")
  let a = MusicTrack(name: "A", artist: "Ann", album: nil), s = MusicTrack(name: "S", artist: "Sam", album: nil)
  var f = MusicFollow()
  CT.check("nothing yet", f.shown, nil); CT.checkTrue("not playing", !f.isPlaying)
  f.apply(.appleMusic, .playing, a); CT.check("Apple Music plays", f.shown, .appleMusic)
  f.apply(.spotify, .paused, s); CT.check("a paused Spotify does not take over a playing Apple Music", f.shown, .appleMusic)
  f.apply(.spotify, .playing, s); CT.check("both play: the latest play wins", f.shown, .spotify); CT.check("its track", f.shownTrack, s)
  f.apply(.appleMusic, .playing, MusicTrack(name: "A2", artist: nil, album: nil)); CT.check("a track change is a newer play", f.shown, .appleMusic)
  f.apply(.appleMusic, .paused, a); CT.check("the shown one pauses while the other plays: the other shows", f.shown, .spotify); CT.checkTrue("still playing", f.isPlaying)
  f.apply(.spotify, .paused, s); CT.check("both paused: the latest pause wins", f.shown, .spotify); CT.checkTrue("nothing plays", !f.isPlaying)
  f.apply(.spotify, .stopped, s); CT.check("Spotify stops: the paused Apple Music shows, with its last track", [f.shown?.rawValue, f.shownTrack?.title], ["appleMusic", "A"])
  f.remove(.appleMusic); CT.check("Apple Music quits: nothing", f.shown, nil); CT.check("no track", f.shownTrack, nil)
  f.apply(.spotify, .playing, s); f.clear(); CT.check("clear forgets both", f.entries.count, 0)
  var g = MusicFollow(); g.apply(.spotify, .stopped, s); CT.check("a stop from an app never seen changes nothing", g.entries.count, 0)

  CT.section("the scripts: only to a running app")
  CT.check("Apple Music play/pause", MusicFollow.script(.playPause, for: .appleMusic), "if application id \"com.apple.Music\" is running then\n    tell application id \"com.apple.Music\" to playpause\nend if")
  CT.check("Spotify previous", MusicFollow.script(.previous, for: .spotify), "if application id \"com.spotify.client\" is running then\n    tell application id \"com.spotify.client\" to previous track\nend if")
  CT.checkTrue("Apple Music previous is today's back track", MusicFollow.script(.previous, for: .appleMusic).contains(" to back track\n"))
  CT.check("next", MusicApp.allCases.map { MusicFollow.script(.next, for: $0).contains(" to next track\n") }, [true, true])
  for app in MusicApp.allCases {
      let r = MusicFollow.readScript(for: app)
      CT.checkTrue("\(app.label): the read checks first", r.hasPrefix("if application id \"\(app.bundleId)\" is not running then return {\"stopped\", \"\", \"\", \"\"}\ntell application id \"\(app.bundleId)\"\n"))
      CT.checkTrue("\(app.label): state, name, artist, album", r.contains("set ps to player state as string") && r.contains("return {ps, n, ar, al}") && r.hasSuffix("end tell"))
  }

  CT.section("the words")
  CT.check("playing", MusicFollow.statusLine(shown: .spotify, playing: true, title: "S", denied: nil), "Spotify · Playing · S")
  CT.check("playing, no title", MusicFollow.statusLine(shown: .appleMusic, playing: true, title: nil, denied: nil), "Apple Music · Playing · Unknown")
  CT.check("paused", MusicFollow.statusLine(shown: .spotify, playing: false, title: "S", denied: nil), "Spotify · Paused")
  CT.check("nothing", MusicFollow.statusLine(shown: nil, playing: false, title: nil, denied: nil), "Not playing")
  CT.check("a refusal wins", MusicFollow.statusLine(shown: .spotify, playing: true, title: "S", denied: .spotify), "Spotify: automation not allowed")
  CT.check("second line", [MusicFollow.secondLine(artist: "Sam", app: .spotify), MusicFollow.secondLine(artist: nil, app: .appleMusic), MusicFollow.secondLine(artist: "Sam", app: nil), MusicFollow.secondLine(artist: nil, app: nil)], ["Sam · Spotify", "Apple Music", "Sam", nil])

  CT.section("a refusal shows only for the app it concerns")
  CT.check("the shown app refused", MusicFollow.deniedToShow(denied: [.spotify], shown: .spotify, lastDenied: .spotify), .spotify)
  CT.check("the other app refused: nothing", MusicFollow.deniedToShow(denied: [.spotify], shown: .appleMusic, lastDenied: .spotify), nil)
  CT.check("nothing shown: the last refusal", MusicFollow.deniedToShow(denied: [.appleMusic, .spotify], shown: nil, lastDenied: .appleMusic), .appleMusic)
  CT.check("a cleared refusal is not shown", MusicFollow.deniedToShow(denied: [], shown: nil, lastDenied: .spotify), nil)
  CT.finish()
  ```
- [ ] **Step 2: Write `scripts/test-music-follow.sh`** as a copy of `scripts/test-island-wing.sh` (header comment: "The music pill's rules (MusicFollow): which of Apple Music and Spotify is shown, the scripts, the words."), compiling `NotchBuddy/Sources/App/MusicFollow.swift tests/CatTestSupport.swift tests/MusicFollowTests.swift` to `"$TEST_DIR/music-follow-tests"`.
- [ ] **Step 3: Run it to see it fail.** `bash scripts/test-music-follow.sh` → compile error (`MusicApp` not found).
- [ ] **Step 4: Implement `MusicFollow.swift`** per the interface and rules above (Foundation only; a header comment naming the spec). Move `shortTitle` and `shortArtist` from `MusicController.swift` unchanged into `MusicTrack` (Task 2 deletes the old copies).
- [ ] **Step 5: Run.** `bash scripts/test-music-follow.sh` → every line `✓`, exit 0.
- [ ] **Step 6: The new flag.** `bash scripts/test-settings-map.sh` now fails (`notchmeow.spotifyAutomationGranted` is a key literal outside the lists). In `tests/SettingsMapTests.swift`, replace the line beginning `        ("notchmeow.musicAutomationGranted", "the Music automation grant flag` with:
  ```swift
          ("notchmeow.musicAutomationGranted", "the Apple Music automation grant flag (MusicFollow), written by MusicController when macOS grants or revokes it; no Settings control"),
          ("notchmeow.spotifyAutomationGranted", "the Spotify automation grant flag (MusicFollow), written by MusicController when macOS grants or revokes it; no Settings control"),
  ```
  Run `bash scripts/test-settings-map.sh` → passes.
- [ ] **Step 7: Project and CI.** `cd NotchBuddy && xcodegen` (adds the file). In `.github/workflows/build.yml`, right before `      - name: Island right wing wiring (source pins of the panel, AppState and the view)`, add:
  ```yaml
      - name: Music pill rules (MusicFollow)
        run: bash scripts/test-music-follow.sh

  ```
- [ ] **Step 8: Commit** `NotchBuddy/Sources/App/MusicFollow.swift tests/MusicFollowTests.swift scripts/test-music-follow.sh tests/SettingsMapTests.swift .github/workflows/build.yml NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj` with `feat(music): the rules for following Apple Music and Spotify (Mac)`.

---

### Task 2: The controller, the words, the purpose line, the binary check, the pins

**Files:**
- Rewrite: `NotchBuddy/Sources/App/MusicController.swift`
- Modify: `NotchBuddy/Sources/App/IslandViewContent.swift`, `PillCatalog.swift`, `SettingsSections.swift`, `NotchBuddy/project.yml`, `NotchBuddy/Resources/Info.plist`, `scripts/test-release-tools.sh`, `scripts/render-settings.swift`, `scripts/check-app-binary.sh`, `.github/workflows/build.yml`
- Create: `tests/MusicWiringTests.swift`, `scripts/test-music-wiring.sh`

**Interfaces:**
- Consumes: everything Task 1 produces.
- Produces (Task 3 relies on these):
  ```swift
  #if !APPSTORE
  @MainActor final class MusicController: ObservableObject {
      static let shared: MusicController
      static let marker = "NM_MUSIC_FOLLOWS_SPOTIFY"          // scripts/check-app-binary.sh looks for it
      @Published var trackTitle: String?                      // the shown app's (unchanged names)
      @Published var artist: String?
      @Published var album: String?
      @Published private(set) var shownApp: MusicApp?
      @Published private(set) var deniedApp: MusicApp?        // MusicFollow.deniedToShow(...)
      var openLabel: String { get }                           // "Spotify" when Spotify is shown, else "Music"
      var deniedLabel: String { get }                         // deniedApp?.label ?? "Music"
      func receive(_ app: MusicApp, playerState: String?, name: String?, artist: String?, album: String?)   // what each notification calls
      func noteDenied(_ app: MusicApp)                        // what a -1743 calls
      func playPause(); func nextTrack(); func previousTrack(); func openMusic(); func openAutomationSettings()
  }
  #endif
  ```

How the controller works (today's file, reshaped; keep the `queue`, `ScriptResult` and the descriptor-reading code as they are):
- `private var follow = MusicFollow()`, `private var denied: Set<MusicApp> = []`, `private var lastDenied: MusicApp?`.
- `init`: for each `app` in `MusicApp.allCases`, one `DistributedNotificationCenter` observer on `NSNotification.Name(app.notificationName)` that extracts `Player State`, `Name`, `Artist`, `Album` as `String?` (as today) and hops to `receive(app, …)`. The launch observer maps the bundle ID with `MusicApp.of(bundleId:)` and calls `fetch(app)` when the pill is on and `UserDefaults.standard.bool(forKey: app.grantedKey)`. The terminate observer calls `follow.remove(app)` then `publish()`. The `activeIntegrations` sink: on, `fetch(app)` for each app that is running and granted, in `allCases` order; off, `clearState()`.
- `receive`: `guard isPillActive, let playback = MusicPlayback.fromNotification(playerState) else { return }`, then `follow.apply(app, playback, MusicTrack(name: name, artist: artist, album: album))` and `publish()`.
- `private func publish()`: copies `follow.shownTrack` into `trackTitle`/`artist`/`album` and `follow.shown` into `shownApp`; sets `deniedApp = MusicFollow.deniedToShow(denied: denied, shown: follow.shown, lastDenied: lastDenied)` and `AppState.shared.musicAutomationDenied = deniedApp != nil`; sets `AppState.shared.musicPlaying = follow.isPlaying` and posts `.musicReveal` only when it goes from false to true; then `syncTaskName()` (the catalog name when `trackTitle` is nil, as today).
- `private func fetch(_ app: MusicApp)`: `send(app, MusicFollow.readScript(for: app))`; on `.success` with 4 values and `MusicPlayback.fromScript(values[0])`, `follow.apply(...)` with `MusicTrack(name: values[1], artist: values[2], album: values[3])` and `publish()`.
- Controls: `guard let app = follow.shown else { return }`, then `Task { await send(app, MusicFollow.script(.playPause / .next / .previous, for: app)) }`.
- `private func send(_ app: MusicApp, _ source: String) async -> ScriptResult` begins `guard isRunning(app) else { return .error }` and is the only caller of `runAppleScript`. `private func isRunning(_ app: MusicApp) -> Bool` checks `NSWorkspace.shared.runningApplications` for `app.bundleId`.
- `runAppleScript(_ source: String, app: MusicApp)`: on `MusicFollow.deniedCode`, hop to the main actor and call `noteDenied(app)`; on success, hop and do `denied.remove(app)`, `UserDefaults.standard.set(true, forKey: app.grantedKey)`, `publish()`. `noteDenied(app)`: `denied.insert(app)`, `lastDenied = app`, `UserDefaults.standard.set(false, forKey: app.grantedKey)`, `publish()`.
- `openMusic()`: activates the shown app's `NSRunningApplication` when there is one; otherwise opens `/System/Applications/Music.app` as today.
- `clearState()`: `follow.clear()`, `publish()`.

- [ ] **Step 1: Write the failing pins** `tests/MusicWiringTests.swift`, in the shape of `tests/IslandWingWiringTests.swift` (`source(_:)`, `count(_:in:)`), with `scripts/test-music-wiring.sh` a copy of `scripts/test-island-wing-wiring.sh` compiling `tests/CatTestSupport.swift tests/MusicWiringTests.swift`. Let `c` be `MusicController.swift`, `r` `MusicFollow.swift`, `v` `IslandViewContent.swift`, and also read `PillCatalog.swift` and `SettingsSections.swift` (through `source(_:)`), and `NotchBuddy/project.yml`, `NotchBuddy/Resources/Info.plist` and `scripts/check-app-binary.sh` by their paths from the repository root. Checks:
  - both files: `hasPrefix("#if !APPSTORE")` and `hasSuffix("#endif\n")`; neither contains `appendAppLog`, `print(`, `NSLog`, `Logger(`, `os_log`, `Timer`, `asyncAfter`, `DispatchSource`.
  - `r`: contains `import Foundation`, not `import AppKit`, not `import SwiftUI`.
  - `c`: contains `MusicApp.allCases`, `app.notificationName`, `static let marker = "NM_MUSIC_FOLLOWS_SPOTIFY"`, `guard isRunning(app) else { return .error }`, `follow.remove(app)`, `MusicPlayback.fromNotification(`; `count("runAppleScript(", in: c) == 2`; `count("NSWorkspace.shared.open(", in: c) == 2`; no `tell application`, `com.apple.Music.playerInfo`, `com.spotify.client`, `openApplication`, `launchApplication`, `func shortTitle`.
  - `v`: contains `MusicCardView()\n                .accessibilityIdentifier(MusicController.marker)`, `MusicFollow.statusLine(`, `MusicFollow.secondLine(artist: controller.artist, app: controller.shownApp)`, `Text(controller.deniedLabel)`, `Text("Allow NotchMeow to control \(controller.deniedLabel)")`, `Button("Open \(MusicController.shared.openLabel)")`; no `Text("Apple Music")`, no `"Automation not allowed"`.
  - `PillCatalog.swift`: contains `.init(id: "integration_music",   name: "Music", color: "#FA2D48",` and the next line ends `githubOnly: true),`.
  - `SettingsSections.swift`: contains `help: "Shows what Apple Music or Spotify is playing. Nothing to enter."`.
  - `project.yml` and `Info.plist`: contain `send mail and control Music or Spotify.`
  - `check-app-binary.sh`: contains `has NM_MUSIC_FOLLOWS_SPOTIFY && music=1` and `has com.spotify.client && spotify=1`.
  Run `bash scripts/test-music-wiring.sh` → fails.
- [ ] **Step 2: Rewrite `MusicController.swift`** as described above; delete its `shortTitle`/`shortArtist` (now `MusicTrack`'s).
- [ ] **Step 3: The words in `IslandViewContent.swift`** (no other change in the file):
  - Replace the three lines from `            if appState.musicAutomationDenied { return "Automation not allowed" }` to `            return "Not playing"` with `            return MusicFollow.statusLine(shown: MusicController.shared.shownApp, playing: appState.musicPlaying, title: MusicController.shared.trackTitle, denied: MusicController.shared.deniedApp)`.
  - `Button("Open Music") { MusicController.shared.openMusic() }` → `Button("Open \(MusicController.shared.openLabel)") { MusicController.shared.openMusic() }`.
  - `Text("Apple Music")` → `Text(controller.deniedLabel)`; `Text("Allow NotchMeow to control Music")` → `Text("Allow NotchMeow to control \(controller.deniedLabel)")`.
  - `if let artist = controller.artist {` → `if let line = MusicFollow.secondLine(artist: controller.artist, app: controller.shownApp) {`, and the `Text(artist)` right under it → `Text(line)`.
  - After the line `            MusicCardView()` insert `                .accessibilityIdentifier(MusicController.marker)` (before its `.transition(.opacity)`).
- [ ] **Step 4: The other words.**
  - `PillCatalog.swift`: `name: "Apple Music"` on the `integration_music` line → `name: "Music"` (Question 2).
  - `SettingsSections.swift` and `scripts/render-settings.swift`: `"Shows what the Music app is playing. Nothing to enter."` → `"Shows what Apple Music or Spotify is playing. Nothing to enter."` (Question 5).
  - `NotchBuddy/project.yml`, `NotchBuddy/Resources/Info.plist`, and the `APPLE=` line of `scripts/test-release-tools.sh`: `send mail and control Music.` → `send mail and control Music or Spotify.` (Question 3).
- [ ] **Step 5: The binary check** in `scripts/check-app-binary.sh`:
  - After `linkpeer=0; has NM_LINK_DEV_PEER && linkpeer=1` add:
    ```bash
    # The music pill (GitHub build only) follows Apple Music and Spotify: its controller carries this marker; nothing of it, not even Spotify's name, is in the App Store build.
    music=0; has NM_MUSIC_FOLLOWS_SPOTIFY && music=1
    spotify=0; has com.spotify.client && spotify=1
    ```
  - In `release)` and `debug)`, before their final `echo "✓ …" ;;` line, add `        [ "$music" = 1 ] && [ "$spotify" = 1 ] || { echo "✗ the music controller (NM_MUSIC_FOLLOWS_SPOTIFY) is missing from this build" >&2; exit 1; }`.
  - In `appstore)`, before its final `echo` line, add `        [ "$music" = 0 ] && [ "$spotify" = 0 ] || { echo "✗ the music controller or Spotify's name is in the App Store build" >&2; exit 1; }`.
- [ ] **Step 6: Run.** `bash scripts/test-music-wiring.sh` → all `✓`. `bash scripts/test-music-follow.sh`, `bash scripts/test-settings-map.sh`, `bash scripts/test-release-tools.sh`, `bash scripts/test-cat-sleep.sh`, `bash scripts/test-u1-wiring.sh` pass. Then, from `NotchBuddy/`: `xcodegen && xcodebuild -scheme NotchBuddy -configuration Debug -derivedDataPath build build CODE_SIGNING_ALLOWED=NO -quiet` → `BUILD SUCCEEDED`, `bash ../scripts/check-app-binary.sh build/Build/Products/Debug/NotchMeow.app debug` → passes; `xcodebuild -scheme NotchMeowAppStore -configuration Debug -derivedDataPath build-store build CODE_SIGNING_ALLOWED=NO -quiet` → `BUILD SUCCEEDED`, `bash ../scripts/check-app-binary.sh build-store/Build/Products/Debug/NotchMeow.app appstore` → passes. Build only; never open the built app.
- [ ] **Step 7: CI.** In `.github/workflows/build.yml`, right after the `Music pill rules (MusicFollow)` step, add:
  ```yaml
      - name: Music pill wiring (source pins of the controller, the views and the binary check)
        run: bash scripts/test-music-wiring.sh

  ```
- [ ] **Step 8: Commit** the files listed above with `feat(music): the music pill follows Apple Music and Spotify (Mac)`.

---

### Task 3: The picture and the fake sender

**Files:**
- Create: `scripts/render-music.swift`, `scripts/render-music.sh`, `scripts/fake-music-events.swift`, `scripts/test-fake-music-events.sh`
- Modify: `.github/workflows/build.yml`

**Interfaces:**
- Consumes: `MusicController.shared.receive(_:playerState:name:artist:album:)`, `noteDenied(_:)`, `MusicCardView`, `MusicPill`, `AppState.shared.activeIntegrations`, `PillCatalog.definition(for:)`, `MusicApp.notificationName`.

- [ ] **Step 1: The picture.** `scripts/render-music.sh` is a copy of `scripts/render-pills.sh` (its own build folder, the defaults domain `render-music` deleted on exit, the whole-app compile, `scripts/render-home-guard.sh`) building `scripts/render-music.swift`, a copy of `scripts/render-pills.swift`'s window-and-bitmap code. It inserts `integration_music` into `AppState.shared.activeIntegrations` and puts the music task in `state.tasks`, then draws one PNG (`--out`, `--scale`) of five rows on black, each drawn right after its state is set: (1) `MusicCardView` with Apple Music playing "Blue in Green" by "Miles Davis"; (2) the same card with Spotify paused "Sunday Morning" by "Maroon 5" (Apple Music stopped first); (3) `MusicPill` (width 134) for row 2's state, hovered off; (4) `MusicPill` with nothing shown (Spotify stopped: the pill reads "Music"); (5) `MusicCardView` after `noteDenied(.spotify)` with Spotify playing. Run `bash scripts/render-music.sh --out "$TMPDIR/music.png"` (about seven minutes) and look at it: row 2's second line reads "Maroon 5 · Spotify", row 5 reads "Spotify" and "Allow NotchMeow to control Spotify", colours as on `main`.
- [ ] **Step 2: The fake sender** `scripts/fake-music-events.swift` (run as `swift scripts/fake-music-events.swift <apple|spotify|both|stop> [--dry-run]`; header comment: for the owner's check only; it posts the two apps' distributed notifications with made-up tracks and never talks to Music or Spotify). Each post is `DistributedNotificationCenter.default().postNotificationName(_, object: nil, userInfo: ["Player State": state, "Name": name, "Artist": "NotchMeow Test", "Album": "Fake"], deliverImmediately: true)`, printed first as `post <notification name> <state> <name>`; each pause is printed as `wait 3` and is `Thread.sleep(forTimeInterval: 3)` unless `--dry-run`, which posts and sleeps nothing. Names: `Test Song (Apple Music)`, `Test Song (Spotify)`. Scenarios: `apple` = Apple Music Playing; `spotify` = Spotify Playing; `stop` = Apple Music Stopped, Spotify Stopped (no waits); `both` = Apple Music Playing, wait, Spotify Playing, wait, Spotify Paused, wait, Apple Music Paused, wait, Spotify Stopped, wait, Apple Music Stopped. An unknown scenario prints the usage and exits 2.
- [ ] **Step 3: Its test** `scripts/test-fake-music-events.sh` (shape of `scripts/test-island-wing.sh`): `swiftc -swift-version 6 scripts/fake-music-events.swift -o "$TEST_DIR/fake-music"`, then checks that `"$TEST_DIR/fake-music" both --dry-run` prints exactly these 11 lines, and that `"$TEST_DIR/fake-music" nope --dry-run` exits 2:
  ```
  post com.apple.Music.playerInfo Playing Test Song (Apple Music)
  wait 3
  post com.spotify.client.PlaybackStateChanged Playing Test Song (Spotify)
  wait 3
  post com.spotify.client.PlaybackStateChanged Paused Test Song (Spotify)
  wait 3
  post com.apple.Music.playerInfo Paused Test Song (Apple Music)
  wait 3
  post com.spotify.client.PlaybackStateChanged Stopped Test Song (Spotify)
  wait 3
  post com.apple.Music.playerInfo Stopped Test Song (Apple Music)
  ```
  Run it → passes. (It never runs without `--dry-run`.)
- [ ] **Step 4: CI.** In `.github/workflows/build.yml`, right after the `Music pill wiring …` step, add a step `Fake music events (the owner's script, dry run)` running `bash scripts/test-fake-music-events.sh`.
- [ ] **Step 5: Commit** the five files with `test(music): the checkpoint picture and the owner's fake music events (Mac)`.

---

### Task 3b: Owner checkpoint 1

- [ ] The main session sends the owner the picture from Task 3 Step 1 and the spec's five "Questions for the owner" with their recommendations. Changes go back to Task 1 or 2 (see "If the owner answers otherwise"); nothing proceeds until the owner approves.

---

### Task 4: Docs

**Files:** Modify `CLAUDE.md`, `README.md`, `docs/SPEC.md`, `docs/INTEGRATIONS.md`.

- [ ] **Step 1: CLAUDE.md.** Add one bullet to "Where things are", right after the bullet that begins ``- `NotchBuddy/Sources/App/HookOrigin.swift` — which pill``:
  > - `NotchBuddy/Sources/App/MusicFollow.swift` — the music pill (Mac, GitHub build only, `#if !APPSTORE`): it follows Apple Music and Spotify through their distributed notifications and shows whichever plays (a playing app beats a paused one; between two of the same, the latest event), labelled "Apple Music" or "Spotify"; its controls act on that app. Pure Foundation (the apps' table, the player states, the track clean-up, the shown-app rule, the AppleScript texts, each guarded by `is running`, and the words), tested by `scripts/test-music-follow.sh`; `MusicController.swift` listens and sends every script through one guarded path (an app is never launched to be asked), `scripts/test-music-wiring.sh` pins it, `check-app-binary.sh` proves the App Store build has none of it (`NM_MUSIC_FOLLOWS_SPOTIFY`), `render-music.sh` draws the card and the pill, and `swift scripts/fake-music-events.swift both` is the owner's fake player. Each app has its own Automation prompt (at the first control click while it is shown) and grant flag (`notchmeow.musicAutomationGranted`, `notchmeow.spotifyAutomationGranted`). Track names stay in memory only. Windows and Linux have no music source (`State.musicPlaying` is the seam).
- [ ] **Step 2: README.md.** `Apple Music *(macOS)*` → `Apple Music and Spotify *(macOS)*`.
- [ ] **Step 3: docs/SPEC.md.** `Stripe, Apple Music *(GitHub only)* | Integration` → `Stripe, Music (Apple Music ou Spotify, celle qui joue) *(GitHub only)* | Integration`.
- [ ] **Step 4: docs/INTEGRATIONS.md.** Replace the row `| Automatisation → Musique *(GitHub only)* | contrôler la lecture Apple Music | première commande depuis le notch |` with two rows:
  ```
  | Automatisation → Musique *(GitHub only)* | contrôler la lecture Apple Music | premier clic sur un contrôle quand Apple Music est affichée |
  | Automatisation → Spotify *(GitHub only)* | contrôler la lecture Spotify | premier clic sur un contrôle quand Spotify est affiché |
  ```
- [ ] **Step 5:** `bash scripts/test-music-follow.sh && bash scripts/test-music-wiring.sh` still pass. **Commit** the four files with `docs(music): Apple Music and Spotify in CLAUDE.md, README, SPEC and INTEGRATIONS`.

---

### After Task 4: whole-branch review

`nm-reviewer-deep` (Sonnet 5.5, high, trigger 4) on `git diff main...HEAD`, with `security-review` loaded and `pr-review-toolkit:silent-failure-hunter` beside it (`model: sonnet`). It checks: no script can reach an app that is not running (the Swift guard and the script's own guard); nothing of the feature is in the App Store build; no track text reaches a log, a file, UserDefaults or the network; Apple Music's flag and prompt behave exactly as on `main`; the views changed words only (diff the view hunks); the Review Focus items have their tests.

---

### Task 5: Owner checkpoint 2: the real machine

The owner runs a Debug build with the Music pill on (the main session never launches or replaces the app). Real Music and Spotify paused or quit for checks 1 and 2.

1. `swift scripts/fake-music-events.swift both` → Apple Music's fake song shows; then Spotify's (the latest play); after Spotify's pause, Apple Music's again (still playing); after Apple Music's pause, Apple Music (the latest pause); after Spotify stops, Apple Music; after Apple Music stops, the pill reads "Music". The cat dances during the first three steps only.
2. `swift scripts/fake-music-events.swift stop` with nothing else running → nothing launches.
3. Real Spotify plays → the pill shows its title, the card "<artist> · Spotify". First click on play/pause → macOS asks about Spotify (the purpose line ends "control Music or Spotify.") → Allow → it pauses; next and previous work.
4. Real Apple Music plays while Spotify plays → Apple Music shows; pause Apple Music → Spotify shows. Apple Music's controls work without a new prompt (the old grant is kept).
5. System Settings → Privacy & Security → Automation → NotchMeow → Spotify off; Spotify shown; click play/pause → the card reads "Allow NotchMeow to control Spotify" with Open Settings…; play Apple Music → it shows and its controls work.
6. Quit Spotify while it is shown → it disappears; click the pill's controls → Spotify does not relaunch.
7. Spotify allowed and playing, turn the Music pill off and on (Settings → Services → Music) → the pill shows Spotify's track at once (the first read: Spotify's `player state as string` is checked here for real).

---

## If the owner answers otherwise

1. Strict "latest event wins": `MusicFollow.shown` takes the highest `order` whatever the playback; in Task 1's test, "a paused Spotify does not take over…" expects `.spotify`, and "the shown one pauses while the other plays" expects `.appleMusic`; Task 5 check 1's expected order changes the same way.
2. Keep "Apple Music": drop the `PillCatalog.swift` change and its pin; the idle pill reads "Apple Music".
3. Keep "…control Music.": drop the three purpose-line edits and their pins.
4. Spotify green: add `var color: String` to `MusicApp` (`"#FA2D48"`, `"#1DB954"`), a Task 1 test, and use it for the card's dot and `MusicPill`'s hover colour only.
5. Keep the help line: drop the two help edits and their pin.

## Self-review

- Spec coverage: goals 1 to 3 → Tasks 1 and 2; rules 1 to 5 → Task 1 (shown, words, scripts) and Task 2 (first read, controls, dance via `AppState.musicPlaying`, reveal); "Not installed, not running, not allowed" → Task 1 (script guards, `deniedToShow`, flags) and Task 2 (`send`, per-app refusals); the prompt → Task 2 (purpose line) and Task 5 checks 3 to 5; builds → Task 2 Steps 5 and 6; privacy → Global Constraints and Task 2 pins; Windows/Linux → no task (unchanged, Task 4's CLAUDE.md line); testing → Tasks 1 to 3.
- Type consistency: `MusicApp`, `MusicPlayback`, `MusicTrack`, `MusicFollow` names are the same in Tasks 1 to 3; `shownApp`/`deniedApp`/`openLabel`/`deniedLabel` are defined in Task 2's interface and used by its view edits and Task 3.
- Proportion: one pure file with its full test, one rewritten controller described by behaviour, word-only view edits given as find/replace.

## Dry run

Walked each task as its implementer, against `main` at `2701c1ef`:

- Every Task 0 anchor occurs exactly once. `IslandViewContent.swift` has two `if task.id == "integration_music" {` (statusDot and statusLabel), so the status edit is found by its three body lines, which occur once; `Text(artist)` occurs once, right under `if let artist = controller.artist {` (16 and 20 spaces); `            MusicCardView()` is followed by `                .transition(.opacity)`.
- `MusicController`'s public names used outside it today: `shared`, `trackTitle`, `artist`, `playPause()`, `nextTrack()`, `previousTrack()`, `openMusic()`, `openAutomationSettings()` (IslandViewContent, AppDelegate); all are kept. `AppState.musicPlaying` is read by `BotCanvasView`, `DesktopCatController`, `CatSleep+App` and the views, `musicAutomationDenied` by the views: both kept with the "shown app" meaning, so the dance and the sleep rule need no change.
- `tests/SettingsMapTests.swift` scans `\w*Key\s*=\s*"…"` in the app's sources, so `appleMusicGrantedKey = "notchmeow.musicAutomationGranted"` (already allowlisted; the allowlist check needs the quoted literal somewhere in the sources, which `MusicFollow.swift` keeps) and `spotifyGrantedKey = …` (new, Task 1 Step 6) are both seen; `forKey: app.grantedKey` is not a literal and is not scanned.
- `PillCatalog.available` filters `githubOnly` under `#if APPSTORE`, unchanged. The Services card's title is already the literal "Music" (`SettingsSections.swift`), so only its help changes; `SettingsMap.swift`'s `was:` strings are history and stay.
- `scripts/test-release-tools.sh` reads the purpose line from `project.yml` and `Info.plist` through its `APPLE=` variable (once), and checks the App Store plist has none: one edit keeps it green. `release.sh` checks only the apple-events entitlement, which stays.
- `check-app-binary.sh` collects `strings` of every binary in `Contents/MacOS` (Debug's `.debug.dylib` included); `MusicController.marker` is used by `accessibilityIdentifier`, as `ProjectsModel.marker` is, so the string stays in the binary; under `#if !APPSTORE` neither it nor `com.spotify.client` reach the App Store target. CI already builds Release and the App Store target and runs the check in both modes.
- `render-pills.sh` compiles every app file but `NotchBuddyApp.swift` without `-D APPSTORE`, so `MusicController` and the views compile into `render-music`.
- `MusicFollow.swift` is new in `Sources/App`, so Task 1 runs `xcodegen` and commits `project.pbxproj`; Tasks 2 and 3 add no app file.
- The build step `Island right wing wiring (source pins of the panel, AppState and the view)` exists once in `build.yml`; the three new steps go before it in order.
