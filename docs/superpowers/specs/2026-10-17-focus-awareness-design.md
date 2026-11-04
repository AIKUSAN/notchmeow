# Focus awareness: NotchMeow steps back when you are already in the app

Status: draft for the owner's review (2026-10-17; the design was approved in chat the same day). Part of the quality-of-life set for the next major update; the version stays 1.0.0 until that update ships. It sits beside `2026-10-17-projects-view-design.md` (the Projects spec) and changes it only where "The Projects fit" says.

## Why

When an agent asks for permission or asks a question while the owner is already looking at that agent's own window, the notch springs open, plays a sound and shows a card for something the owner can answer in front of them. It is noise, and it covers the screen they are working in. The card earns its place when the owner is somewhere else; when they are in the agent's app, the agent's own prompt is the better place to answer.

## Goals

1. **Step back when the session's app is frontmost.** When a `PermissionRequest` or a question arrives from a session and the app that session runs in is the frontmost app, NotchMeow answers the hook "ask" at once, so the agent prompts in its own window. The island does not open and makes no sound.
2. **Say that something waits, quietly.** The agent's pill gets a small amber waiting dot, and a read-only note waits inside the notch: "Waiting in <app>: <the island's step words>", with no buttons.
3. **When the app is not frontmost, nothing changes.** Card, buttons, sound, the island opens: exactly as today.
4. **All the hosts NotchMeow can name:** Claude Code in the Claude app, in any terminal, in VS Code and in Cursor, Codex, and every tagged agent whose app is known (Gemini CLI, Antigravity and the like, through their terminal). "Which hosts can be matched" below lists them per platform.
5. **A setting to turn it off:** Settings → General → Island, "Step back when I'm already in the app", on by default.
6. The Mac first, then the Windows/Linux twin with the same rules (Mac is primary).

## Non-goals

- Window or tab level matching. App level only (accepted by the owner): with Terminal in front but the session in another tab, the session still counts as "there".
- Answering, approving or denying anything. Stepping back hands the decision to the agent's own prompt.
- A new setting beyond the one switch, a new sound, a new alert, or any change to what a card looks like.
- Following the owner's focus after the request: nothing is re-evaluated when they switch apps later.
- Changing the hook relays, the hook protocol or the installed hooks.

## Anti-goals (a failure even if it works)

- NotchMeow approving, denying or "allowing" anything: the only answer this feature ever sends is the existing "ask".
- A poll, a timer or an observer that runs while the island is hidden (the 0 % rule): the frontmost app is read once per request, at the moment it arrives, and nowhere else.
- A new permission prompt for the user: no Accessibility, no Screen Recording on the Mac.
- Reading window titles, document names or any window content on any platform. The only thing read is which application is in front (its bundle ID on the Mac, its process image name on Windows, its window class on Linux), and it is compared and dropped, never logged or stored.
- Stepping back when the match is only a guess. A host that cannot be named exactly is "not matched", and the card shows as today. Every doubt resolves to today's behaviour.
- Dropping a request: a stepped-back request is answered "ask" exactly once, before any card is built, and never displaces a card that is already waiting.
- Changing how any pill, card or Settings page looks beyond the added dot, the added note and the added row.

## Constraints

- Swift 6, SwiftUI + AppKit, no new dependency; the Windows/Linux twin in TypeScript with Rust only for the foreground read. On Windows the `windows` crate is already a dependency (new feature flags only if the build needs them); on Linux the Xlib the app already uses for the pointer feed (`platform::pointer_feed`). No new crate.
- The ask answers already exist and are reused unchanged: the Mac's `{"permissionDecision":"ask"}` on the two paths in `HookServer.swift` (the PermissionRequest handler and the question handler), the Windows page's `Bridge.approvalDecline(requestId)` that `island/hooks.ts` already uses for tagged agents and Claude app sessions, and the relay's own wording for Antigravity's PreToolUse (`{"decision":"ask"}`, `windows/hook/src/agents.rs`, `silent_answer`).
- The decision is a pure function, tested without the app; the foreground read is a thin app-side call.
- It is in every build (Debug, Release, App Store). In the App Store build only the hosts that build already handles are matched (Codex and the tagged agents' routes are GitHub-build only, as today).

## What the owner decided

- Step back when the session's app is frontmost; answer "ask" at once, no island, no sound; an amber waiting dot on the pill; a read-only note "Waiting in <app>: <step words>" cleared by the session's next event or after 10 minutes at most (2026-10-17).
- Not frontmost: everything as today (2026-10-17).
- Applies to Claude Code in the Claude app, any terminal, VS Code and Cursor, and every agent pill whose app NotchMeow can name (2026-10-17).
- App level, not window or tab: accepted (2026-10-17).
- Mac: `NSWorkspace.frontmostApplication` at the moment the request arrives, no polling, no new permission. Windows: the foreground window's process, read once per request in Rust. Linux: `_NET_ACTIVE_WINDOW` once per request where available, else not frontmost (Wayland) (2026-10-17).
- A switch in Settings → General → Island, "Step back when I'm already in the app", on by default, key `island.focusAware`, in today's row style (2026-10-17).
- The Projects feature treats a step-back like a Claude App wait; the "Tuck the island away" setting needs nothing beyond the island not opening (2026-10-17).

## The rules

Pure, over what the event and the system already give. Inputs: the setting, the request kind (permission or question), the route and tag, the session's host (below) and the frontmost application.

1. **When it applies.** The setting is on, the request is a `PermissionRequest` or a question (the `--ask` PreToolUse hook), and the session's host is known and equals the frontmost application. Otherwise: not applicable, and the request goes on to today's code unchanged. With the setting off the frontmost application is not even read.
2. **Where it sits in the flow.** After the route is known and before anything that builds a card, takes a pin, plays a sound, opens the island or displaces a waiting question. It is the same place as the existing ask-at-once paths (`HookOrigin.answersAskAtOnce`), and it answers with the same line. The session's ordinary bookkeeping still happens (the pill is touched as the latest, the Sidekick ledger is fed), as it does for a Claude App request today.
3. **The answer.** "Ask", nothing else. For Antigravity's PreToolUse the relay turns it into `{"decision":"ask"}` as it already does. A stepped-back request is final: it is never turned into a card later.
4. **The waiting mark.** Each step-back records one entry in memory: the session ID, the pill, the host's name (`HookOrigin.hostName` words: "VS Code", "iTerm", "Cursor", "Codex", "Claude App", "the terminal"), the kind, the step words and the time. It ends, whichever comes first, at the same events as the Projects spec's rule 4 for the Claude App wait (the session's next PreToolUse, PostToolUse, PostToolUseFailure, UserPromptSubmit, Stop, StopFailure, Interrupt or SessionEnd), or 10 minutes after it began. The 10 minutes are judged when the island reads the entry, from the time stored: no timer. One entry per pill and session; a newer request of the same session replaces it.
5. **What it shows.** The pill: a small amber dot, in the pill cell's existing badge place, shown while an entry lives (no pulse in the compact notch; any pulse runs only while the island is open, as the Projects spec's). The note: "Waiting in <host>: <step words>", where the step words are the island's existing `SessionStepText` words for that tool or question, cut to the line's width and never a command, a path or a prompt. It has no button and takes no click of its own; the pill's existing tap still brings the app forward.
6. **What it never does.** It does not open the island, hold or pin it, call the desktop cat, play a sound, raise the pill's badge that means "a card waits" or change the pill's state to approval (no card waits).
7. **A card already up.** If another request's card is waiting, a stepped-back request from a different session is simply answered "ask" and marked; the card is untouched. (A stepped-back request never needs the "one card" rule, as it has no card.)
8. **The setting.** `island.focusAware`, a Bool, default true, read as "on" when the key is absent or not a Bool. Turning it off ends nothing already marked; marks end as in rule 4.

## Which hosts can be matched

A session's host is what the relay already sends with each event; no relay change. A host is matched only when it is named exactly (rule "Anti-goals"). Anything else is "not matched" and behaves as today.

### Mac

The frontmost application's bundle ID is compared with the session's host. The session's host comes from the helpers `HookOrigin` and `AgentTarget` already hold (`bundle_id` is the relay's `__CFBundleIdentifier`, `term_program` is `TERM_PROGRAM`):

| Session | Host compared | Source |
|---|---|---|
| Claude Code from the Claude app (tag `claude-desktop`) | `com.anthropic.claudefordesktop` | `HookOrigin.desktopBundleId` |
| Claude Code from a terminal | the app that started it: `bundle_id`, else the terminal `TERM_PROGRAM` names (Terminal, iTerm, Ghostty, Warp, kitty, Alacritty, WezTerm, Hyper) | `HookOrigin.terminalBundleId` |
| Claude Code from VS Code | any frontmost bundle ID containing `vscode` (VS Code, Insiders) | `HookOrigin.isVSCode` |
| Cursor | `com.todesktop.230313mzl4w4u92` | `HookOrigin.cursorBundleId` |
| Codex (GitHub build) | `com.openai.codex` | `AgentTarget` |
| Gemini CLI, Antigravity and other tagged agents | the terminal as above (`terminalBundleId` of their event). When the event names no terminal (`bundle_id` and `TERM_PROGRAM` empty or unknown), not matched. | `AgentTarget` opens "the first running terminal" for Gemini and Antigravity, which is not exact enough to match on, so it is not used here |

A terminal inside tmux or ssh counts as its terminal app (it inherits the launcher's bundle ID). NotchMeow itself is never a match (its panels are non-activating, so the app in front stays the owner's; Settings in front is "not a match").

Tagged agents and Claude App sessions already answer "ask" at once with no card today. For them this feature adds only the dot and the note, and only when the host is frontmost; when it is not, they behave as today (no dot, no note), which is nothing visible at all.

### Windows

The foreground window's owning process (`GetForegroundWindow`, `GetWindowThreadProcessId`, then the process image name, read once per request in Rust and handed to the page) is compared with a small table keyed by what the relay sends (`term_program`, `wt_session`, `vscode_pid`, the `nm_agent` tag; there is no bundle ID):

| Session | Host compared |
|---|---|
| Claude Code from the Claude app (tag `claude-desktop`) | `Claude.exe` |
| `term_program` = `vscode` (VS Code, and its forks: they set the same value) | `Code.exe`, `Code - Insiders.exe`, `VSCodium.exe`, `Cursor.exe` |
| `wt_session` present | `WindowsTerminal.exe` |
| Gemini CLI, Antigravity, other tagged agents | by the same two rows, from their own event |
| Plain console windows (`cmd`, PowerShell in conhost), other terminals | not matched: the relay carries no marker for them |

Windows has no Cursor or Codex route in `island/hooks.ts` today; those rows come with their routes, if they ever do.

### Linux

X11: `_NET_ACTIVE_WINDOW` read once per request through the Xlib the pointer feed already loads, then the window's `WM_CLASS`. Matched: the VS Code family when `term_program` = `vscode`, and a terminal whose `TERM_PROGRAM` names it (kitty, WezTerm, Alacritty, ghostty; the exact class names are the builder's table). Everything else is not matched. Wayland, or any failure to read: not frontmost, so the card shows as today. Anthropic ships no Claude desktop app for Linux, so there is no Claude app row.

## The Projects fit

The Projects spec marks a session `approval`/`question`, labelled "Waiting in Claude App", counted, and ended by its rule 4. A step-back is the same thing for another reason, so the two share one mechanism and one text:

- A step-back mark is the same kind of mark: the session is `approval` or `question`, labelled "Waiting in <host>", counted in the waiting count (rule 10), a waiting project moves first (rule 8) and pulses while the island is open, and the compact amber count includes it. It ends at rule 4's events or at 10 minutes, so the 120 s and 130 s endings of rule 4's card case do not apply (no card).
- The Claude App case needs nothing new: its mark and a step-back's are one entry, never counted twice.
- One function builds the label ("Waiting in <host>") for both, so the Projects rows, the pill's note and the Claude App wait read the same.
- Waiting stays a count, never an alert: consistent with the Projects spec's call 7 and with this feature's rule 6.

What this implies in the Projects contract (a call for the owner, below): rule 4 gains a third case, "sessions that stepped back because their app was frontmost", and the pure core's session event gains one optional input, the host name to label the wait with. No other rule, ID or fixture of that contract changes.

## The island (Mac)

- No new view. The dot and the note are in the open island only; the compact notch shows nothing new from this feature (Projects' own compact count excepted, once that ships).
- The dot: the pill cell's existing badge place; amber is the Projects spec's waiting amber (one colour, from `shared/theme.json`'s existing groups if one fits, else a new entry in the `projects` or `glow` group, never a hard-coded value).
- The note: shown on the pill's card in the open island and in the Projects screen's session row, in the style of the existing "Handled in …" and "Still waiting in …" notes (`HookOrigin.note`), without buttons.
- Accepted exception to never-restyle, owner-approved 2026-10-22: while a focus mark lives, the note replaces cat 2's secondLine, unless that line is itself a waiting alert, in which case it stays. The rule is `FocusAware.showsNoteOverSecondLine` (the dot's rule: a card or question waiting on cat 2's pill wins), and the card's height does not change either way.
- It does not appear in the pill grid's compact cells or in the chat.

## Settings (Mac)

- Settings → General → Island gains a toggle row, "Step back when I'm already in the app", next to "Open on hover", in the same Toggle style (`SettingsView.swift`). Key `island.focusAware`, default on, held like `openOnHover` (in `AppState`).

## Windows/Linux

The same rules in TypeScript (a pure `windows/src/core/focusaware.ts` for the decision and the host table, fed by `island/hooks.ts`, which already declines tagged agents' and Claude app requests through `Bridge.approvalDecline`), the foreground read in Rust (`platform/windows.rs`, `platform/linux.rs`, one function each, called once per request through one Tauri command), the dot through the existing pill badge mechanism (`State.setPillBadge`), the note in the Windows island's style, and the switch in the Windows Settings' General page, stored with the other behaviour settings in `settings.json` (kept at every save, with a clean-up like the other settings' and a Rust twin if the file's schema needs one). No global shortcut.

## Left to the builder

- The shape of the pure rule and its tests: Mac `FocusAware.swift` with `scripts/test-focus-aware.sh` (decision table: each host row, not matched, setting off, a card waiting) plus a wiring pin (`scripts/test-focus-aware-wiring.sh`: the two `HookServer` call sites, no timer or observer added, `island.focusAware` key); Windows `focusaware.test.mjs` in `windows/scripts/cat-tests/`. No shared JS contract: the host tables differ per platform by nature; the shared parts (the label, the endings) live in the Projects core.
- The memory structure for the marks, as long as it is cleared as in rule 4 and read for age at read time.
- Where exactly the note sits on the pill's card, the dot's size, and the picture scripts (`render-pills.sh` showing the dot, a note picture) at each checkpoint.
- The Linux class-name table, and whether the X11 read needs a short connection each time or the pointer feed's one.
- Checking that the Sidekick's stuck nudges (`stuckStep`) do not speak up about a stepped-back, open request (the ledger sees the `PermissionRequest`). If they would, the smallest fix inside the sidekick's app side, without touching the contract, is the builder's to propose; any change to `shared/sidekick-core.js` goes to the owner first.
- Making sure `state.touchPill` on the Mac (and `ensurePill`/`upsert` on Windows) do not reveal the island on their own for a stepped-back request.

## Calls made by the main session (2026-10-17; the owner may override any)

1. **No re-check after the request.** The frontmost app is read once, when the request arrives. If the owner switches away afterwards, the agent's own prompt keeps waiting, the dot and note stay until rule 4's end, and no card appears. A poll or an app-activation observer would be needed to do better, and the 0 % rule forbids it. This is the price of "no polling".
2. **The note and dot also cover agents that already answer "ask" with no card** (tagged agents, Claude App sessions) when their host is frontmost, because the owner listed "every agent pill whose app NotchMeow can name". When not frontmost they stay as today.
3. **Gemini CLI and Antigravity are matched by the terminal their own event names**, never by "the first running terminal" that `AgentTarget` opens for them, since that is a guess. If their event names no terminal, they are not matched.
4. **The host is matched from the existing event fields; the relays do not change.** On Windows this limits matching to VS Code and forks, and Windows Terminal; plain console windows are not matched. A relay change (the process tree) would match more but is a bigger, riskier step, left out.
5. **The step words are `SessionStepText`'s, cut to the line, never the command, the path or the prompt.** If `SessionStepText` has no words for a tool, the note says "Waiting in <host>" alone.
6. **The 10-minute end is read-time, not a timer** (as the Projects spec's other ages), and a newer request of the same session replaces the entry.
7. **Failure direction.** Any unknown (no host, unreadable foreground app, Wayland, a blank bundle ID) means "not matched" and today's behaviour.
8. **No contract fixtures of its own.** The decision table is tested per platform; the Projects fixtures gain only the wait-label case below.
9. **Colours** come from `shared/theme.json`, with one existing amber reused if there is one (the Projects spec's waiting amber).
10. **A card already waiting is not touched** by a stepped-back request from another session (rule 7), rather than being asked-back as the "one card" rule does for a second card request.

### Calls for the owner (they touch an approved spec)

A. **Projects, rule 4:** add the third case ("a session that stepped back because its app was frontmost": same `approval`/`question` mark, label "Waiting in <host>", ends at the listed events or after 10 minutes), and give the pure core's event one optional `waitIn` field (the host name). One new fixture case: a stepped-back session counted once with its label, then ended by its next PreToolUse. If the Projects contract (branch `p0/projects-contract`) is not merged yet, the cheapest path is to fold this into P-0 now; if it is, this feature adds it afterwards as a small contract change. Recommended: fold it into P-0 now.
B. **Same words for the Claude App wait:** the Projects label stays "Waiting in Claude App" and becomes one case of "Waiting in <host>", produced by `HookOrigin.hostName`. No visible change.

## Calls made after the builder check (main session, 2026-10-17; the owner may override any)

1. **Base and the Projects contract.** Call A is taken: the optional `waitIn` field, the "Waiting in <host>" label and their fixture go into P-0 now, at its open owner checkpoint (before its Task 7), so this feature builds on the merged P-0 contract. Call B follows: "Waiting in Claude App" is the `claude-app` case of "Waiting in <host>". This feature's app plans branch from `main` after P-0 merges.
2. **The amber dot shows in the compact notch too,** on the session's pill, still (no pulse, no animation), so a glance up shows it. Rule 5's "no pulse in the compact notch" stands; "the compact notch shows nothing new" is replaced by this.
3. **The dot uses the pill cell's existing badge place, in amber, with no number.** The card badge (a card waits) keeps its own look; the two never show together on one pill, and a waiting card wins.
4. **A tagged agent's event without `bundle_id` or `term_program` is "not matched"** (today's behaviour), listed as a known limit. No relay change in this feature.
5. **Windows process names are unverified;** a name that does not match falls back to today's behaviour. Verifying them on a real PC is owed and listed for the owner, not a gate.
6. **A stepped-back request from a session that already has a card waiting leaves that card alone** (it is still answerable from the notch); the new request asks in the app and adds the note.
7. **While a session's "Waiting in <host>" note is open, it replaces that session's "Handled in …" note;** when the mark ends, the existing notes come back as today.
8. **Owner-approved exception to "no timer" (2026-10-22; it adds a wake to rule 4's "judged when read" and call 6 of the main session's list above).** Each stepped-back mark's 10-minute end is a one-shot wake through the Sidekick's existing clock (`SidekickClock`), armed even with the Sidekick off, so a blocked agent's dot and note clear on time. It never repeats and never polls: one wake per mark lifetime, cancelled or re-armed when the mark ends early or is replaced. Nothing else in this spec changes: the 0 % rule holds for everything but this one wake, and the frontmost app is still read only once per request.
