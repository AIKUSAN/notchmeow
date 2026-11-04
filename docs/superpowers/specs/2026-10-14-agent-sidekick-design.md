# Sub-project F1: the agent sidekick

**Status:** Design decided by the owner in chat on 2026-10-14; written spec approved 2026-10-14.
**Parent spec:** `docs/superpowers/specs/2026-10-03-notchmeow-design.md` (sub-project F, stage F1). **Builds on:**
- sub-project A and B (the cats, the display modes, the cast and the kittens);
- sub-project H (`docs/superpowers/specs/2026-10-08-desktop-cat-design.md`): the desktop cat, whose lock and sleep observers F1 shares;
- sub-project E1 and E3 (`docs/superpowers/specs/2026-10-03-local-models-design.md`, `2026-10-06-connect-claude-design.md`): the local models, the router and the chat.

Those are merged on both apps, and this document doesn't repeat them.

**Research behind it** (2026-10-03, and a code pass on 2026-10-14): the parent spec's lessons are the rules of this spec.
- Speak only at task boundaries.
- Remember every dismissal.
- Look at the work, not at the user.
- Never cover the user's work.

## Context
Make the cats useful, not only cute. They watch the agents' work and speak up in four small ways:
1. **A recap** when you come back after being away and an agent did something.
2. **A plain-English line** under each permission request, with a risk badge when it is risky.
3. **A nudge** when an agent looks stuck.
4. **An answer** to "What's Claude doing?" in the chat, and **a drop** of a file on an agent's own cat to hand it to that agent.

The brain is a set of plain rules. It needs no AI and is always on. A local model may only polish a sentence. Session data never leaves the machine.

## Decisions

| Topic | Decision |
|---|---|
| Scope | **All four in F1:** away recaps; permission explanations with a risk badge; stuck nudges; "What's Claude doing?" in the chat, plus dropping a file on an agent's own cat. |
| Brain | **Rules first, always on, no AI:** risk labels, stuck checks and a template recap. |
| Nicer wording | **Only from a local model:** servers on `127.0.0.1`, `::1` or `localhost`, and Apple on-device. Never from the chat's Auto router, which can pick a cloud model. If none is present, the template stands. |
| "What's Claude doing?" | **Answered on this machine** from the ledger. It is never added to a conversation, so it never reaches a cloud model. |
| Timing | **Task boundaries only.** A recap on return, at most one per away period. A stuck nudge at most once per session. Shown only in the island, never over the user's work. |
| Agents | **Every hooked agent:** Claude Code, Codex, Gemini CLI and Antigravity, with the coverage in the tables below. |
| Permission card | **Stays exactly as it ships.** One new grey line under the command and a small orange risk badge. On a high-risk request the cat gives the existing `surprised` emote. No new emote. Island card only; the E3 chat cards come later. |
| Drop on an agent's cat | **The big cat keeps today's drop exactly** (the chat or Ask drop, and G's future Ask and Shelf split). **Only a drop on an agent's own cat hands over a path:** an agent's cat in the grid in A cat for each agent mode, or cat 2 in Two cats mode. It copies the file's original path to the clipboard and brings that agent's terminal or editor forward. The line says "Copied the path — paste it into <agent>". NotchMeow never pastes or types into another app and never claims delivery. |
| Dismissal | **Clicking Not now, OK or × counts. Folding the island unseen does not.** After 2 dismissals a kind is muted. Settings has an Unmute. The risk badge is never muted. |
| Away | Lock, sleep, screen off, or 5 minutes of no input, where the OS allows it. |
| No new polling | Existing notifications and the existing poll ticks only. The stuck clock is one one-shot timer that idles when nothing runs. The hidden island still costs 0 % CPU. |
| Approach | **Contract first, then both apps in parallel**, as in A, B and H. F1-0 writes the shared pure rules and fixtures. Then F1-mac and F1-tauri replay them. The Mac gets at least what Windows/Linux gets. |
| Privacy | No telemetry. The ledger lives in memory only, is capped and is never logged. Lines contain basenames only. `transcript_path` is never read. A leak test proves it. |
| Never restyle | Every existing view looks exactly as it ships. New views follow the existing style. |

## Coverage

What each agent gives F1 comes from the hook events the apps receive today (verified in `HookServer.swift`, `windows/src/island/hooks.ts`, `agent_hooks.rs`). "Yes" means the data exists. "No" means the rule is silent for that agent, never faked.

**macOS**

| Feature | Claude Code | Codex | Gemini CLI | Antigravity |
|---|---|---|---|---|
| Ledger and recap | Yes | Yes | Yes | Yes |
| Permission line and badge | Yes | Yes | No (no permission card) | No (no permission card) |
| Stuck: loop | Yes | Yes | Yes | Yes |
| Stuck: errors | Yes (`PostToolUseFailure`) | No (no failure event) | No | No |
| Stuck: waiting for OK | Yes | Yes | No | No |
| Stuck: silent | Yes | Yes | Yes | Yes |
| "What's Claude doing?" | Yes | Yes | Yes | Yes |
| Drop on an agent's cat: path copied | Yes | Yes | Yes | Yes |
| Drop on an agent's cat: terminal or editor forward | Yes, by the existing routes (first running terminal, VS Code, Cursor) | Yes, by the Codex route | Terminal only | Terminal only |

**Windows and Linux** (there is no Codex)

| Feature | Claude Code | Gemini CLI | Antigravity |
|---|---|---|---|
| Ledger and recap | Yes | Yes | Yes |
| Permission line and badge | Yes | No | No |
| Stuck: loop | Yes | Yes | Yes |
| Stuck: errors | Yes, but it can't say why (the relay drops the error text) | No | No |
| Stuck: waiting for OK | Yes | No | No |
| Stuck: silent | Yes | Yes | Yes |
| "What's Claude doing?" | Yes | Yes | Yes |
| Drop on an agent's cat: path copied | Yes | Yes | Yes |
| Drop on an agent's cat: terminal or editor forward | Windows: the existing "open the project" action. Linux: none. | Same | Same |

Other notes on coverage:
- **Codex on the Mac is the GitHub build's.** The App Store build keeps what it has today. F1 adds nothing there that the build can't already see.
- **Claude Code on the Mac is seen only from VS Code and Cursor today** (`HookServer.processEvent` ignores other terminals). That is why the prerequisite round exists. Until it lands, F1-mac works, but only for those sessions.
- **Gemini and Antigravity pills vanish 5.2 s after Stop.** F1 keeps its own ledger, so the recap still has them.
- **The fields F1 reads** are the ones both apps already read: `session_id` or `conversation_id`, `cwd`, `hook_event_name`, `tool_name`, `tool_input` and the relay's `nm_agent`, `term_program`, `bundle_id`. The Windows relay cuts strings to 2000 bytes and drops `tool_response` and `transcript_path`. F1 needs none of the dropped parts.
- **Fields that are in the docs but not yet used** (`PostToolUseFailure`, `StopFailure`, `Notification`, `SubagentStop`) get a fixture of a real-shaped payload in F1-0 before any rule depends on them.

## The ledger

One small record per session, kept by each app from the hook events. It is the only memory the sidekick has.

**Key:** `(agentId, sessionId)`. `agentId` is the pill's ID (`integration_claude`, `agent_cursor`, `agent_codex`, `agent_gemini`, `agent_antigravity`).

**Fields:**
- `startedAt`, `lastEventAt`, `state` (the cat's state words: working, thinking, searching, finished and so on);
- `project`: the basename of `cwd`, and nothing else of it;
- `ring`: the last 40 entries, each `{at, kind, tool, target, file, key, ok}`. `kind` is one of `tool`, `failure`, `approvalAsked`, `approvalAnswered`, `stop`, `stopFailure`, `subagentStart`, `subagentStop`. `target` is a basename or a normalised command key (see below), never a path.
- `pendingApprovalAt`, when a request is waiting;
- `subagentsAlive`: how many kittens are alive (from B's rules).

**What it does not hold:** the prompt, the assistant's text, `transcript_path`, a full path, a command, or any file content. The proposed shape in the research also held a prompt head and a final line. F1 drops both. They are the likeliest to carry secrets, and no F1 line needs them.

**The command key.** The loop rule needs to know that two calls are "the same". The key is the tool name plus a hash of the normalised `tool_input` (the Mac already does this for approvals: `approvalInputKey`). Only the hash is stored.

**Life:**
- It is created by the first event of a session.
- It ends at `SessionEnd` plus 30 minutes. (Gemini and Antigravity pills disappear sooner, so the ledger outlives them.) A session with no `SessionEnd` ends 12 hours after its last event.
- At most 8 sessions are kept. The oldest finished one goes first.
- It is memory only. Quitting the app clears it. It is never written to disk and never logged.

**Where it is fed.** From the hook handler, before the pending-approval gate, so that a displaced or declined approval is still counted: `HookServer.processEvent` and `processPermissionRequest` on the Mac, `island/hooks.ts` on Windows and Linux. A thin adapter in each app turns a hook payload into a normalised event (`eventFrom`, in the shared core, so both apps agree). The pure `ledgerApply(ledger, event)` updates the record.

## Risk rules

`explain(agent, tool, toolInput, cwd, home)` is pure. It returns `{risk, reasonId, line, target}`.

- `risk` is `low`, `medium` or `high`. `unsure` is a valid reason and counts as `medium`.
- It labels. It never blocks, never allows and never denies. Only the user's click does.
- `target` is the basename the line names, or empty.
- `line` is a fixed template for the `reasonId`, with the target's basename filled in. No command text, no path and no argument ever appears in it.

**How a command is read.** For a shell tool, the command is split into parts at `&&`, `||`, `;`, `|`, `&` and newlines, respecting quotes. A leading `cd x &&`, `sudo`, `env VAR=1`, `time` and `command` are looked through. The request takes the highest risk of its parts. A command that can't be read safely is `medium` with the reason `unsure`.

**Paths.** A path is resolved against `cwd`, with `..` and `~` handled, using the `home` that the caller passes in. "Outside the project" means outside `cwd`.

| Risk | Reason ID | Triggers | Line (template) |
|---|---|---|---|
| High | `rm_recursive` | recursive delete of `/`, `~`, a home folder, or anything outside `cwd` | Deletes {name} and everything inside it. |
| High | `sudo` | any `sudo` or `doas` | Runs a command with admin rights. |
| High | `pipe_to_shell` | `curl` or `wget` piped to `sh`, `bash` or `zsh` | Downloads a script and runs it at once. |
| High | `chmod_recursive` | `chmod -R` or `chown -R` | Changes permissions on {name} and everything inside it. |
| High | `git_force_push` | `git push --force` or `-f` | Overwrites the remote branch history. |
| High | `git_reset_hard` | `git reset --hard` | Throws away local changes. |
| High | `git_clean` | `git clean -f` or `-fd` | Deletes files git doesn't track. |
| High | `disk_write` | `dd`, `mkfs`, writes to `/dev/*` | Writes straight to a disk. |
| High | `sql_drop` | SQL `DROP` | Deletes a database table or database. |
| High | `sql_delete_all` | SQL `DELETE` or `UPDATE` with no `WHERE` | Changes every row in a table. |
| High | `sensitive_file` | write or edit of `.env*`, keys (`*.pem`, `id_*`), `~/.ssh`, `~/.aws`, `~/.gnupg`, shell start-up files, `.git/hooks`, the agent's own settings (`.claude/settings*.json`) | Changes {name}, which can hold secrets or settings. |
| High | `write_outside` | write or edit outside `cwd`, to a file not listed above | Changes {name}, outside this project. |
| Medium | `git_push` | `git push` | Sends commits to a remote. |
| Medium | `install` | `npm`, `pnpm`, `yarn`, `pip`, `brew`, `cargo` and `gem` installs | Installs software. |
| Medium | `network_fetch` | `curl`, `wget`, `ssh`, `scp` | Talks to another computer. |
| Medium | `container` | `docker`, `kubectl` | Controls containers. |
| Medium | `lockfile_ci` | write of a lockfile or CI config | Changes {name}, which affects every build. |
| Medium | `mcp_tool` | a tool named `mcp__*` | Uses a tool from an add-on. |
| Medium | `unknown_tool` | a tool the rules don't know | Uses a tool NotchMeow doesn't know. |
| Medium | `unsure` | a command that can't be read | NotchMeow can't tell what this does. |
| Low | `read_only` | `Read`, `Glob`, `Grep`, `ls`, `cat`, `git status`, `git diff`, `git log` | Only reads files. |
| Low | `test_build` | test and build runners | Runs the project's tests or build. |
| Low | `edit_in_project` | edit or write inside `cwd` | Edits {name} in this project. |
| Low | `web` | `WebFetch`, `WebSearch` | Reads a web page. |
| Low | `subagent` | `Task` | Starts a helper agent. |

The table is the first version. F1-0 pins each row with at least two positive cases and one near-miss in `explain-cases.json` (for example `rm -r ./build` is not `rm_recursive`, `git push --force-with-lease` is `git_force_push` (high), as `--force` is, and `echo "sudo"` is not `sudo`). F1-0 added reasons the first table did not have, as this section allows: `outside_project` and `rm_in_project` (medium), `local_command` (low) and `reads_secrets` (medium, the owner's answer of 2026-10-14), and wrote the decisions where the table was silent in `docs/SIDEKICK-CONTRACT.md`.

Codex's shell tool (`Bash`, `shell`, `local_shell` or `exec_command`, with a string or an argv list as its command) and its `apply_patch` are read in F1-0 from the documented shapes. A payload captured from a real Codex session should replace them: every payload in `hook-cases.json` says whether its shape is `repo` (the app already sends it) or `docs` (only the agent's documentation shows it).

## Stuck rules

`stuckStep(ledger, now)` is pure. It returns at most one nudge `{kind, reasonId}` or nothing, plus the time of the next deadline for the timer.

| Kind | Rule | Evaluated | Text (template) |
|---|---|---|---|
| `stuck.loop` | The same tool and command key 4 times in the last 8 calls, within 10 minutes, with no successful `Edit` or `Write` between. | On each tool event. | {Agent} has run the same step 4 times. |
| `stuck.errors` | 3 failures in a row (`PostToolUseFailure`), all within 10 minutes, with no success between. | On each failure. Claude Code only. | {Agent} hit 3 errors in a row. |
| `stuck.waiting` | A request has waited for 60 s (`pendingApprovalAt`), and its card is not on screen. | By the timer. | {Agent} is still waiting for your OK. |
| `stuck.silent` | State is thinking, working or searching, and no event has come for 5 minutes after a `PostToolUse`, `UserPromptSubmit` or `SubagentStop`, or 15 minutes after a `PreToolUse` with no `PostToolUse`. | By the timer. | {Agent} has been quiet for {n} minutes. |

Rules that apply to all four:
- **Once per session.** After one nudge for a session, the rest stay silent for it.
- **Never while a kitten is alive for under 10 minutes** (for `stuck.silent`). A helper agent can legitimately take a while.
- **Never in the rate-limit state.** The cat already shows it.
- **Never while the user is away.** A nudge that falls due is dropped. The recap covers it.
- **`stuck.waiting` and the give-up.** The Mac gives up on the request at about 115 s, Windows and Linux at 110 s. If the nudge is still open then, its text changes in place to "{Agent} is waiting for your OK in the terminal." That change is not a second nudge.
- **The text has the agent's name** and nothing else of the work. {n} is a whole number of minutes.

**The clock.** It is one one-shot timer, like `CatSleep` (`CatSleep.swift`, `windows/src/island/sleep.ts`).
- It is set to the nearest deadline of `stuck.waiting` and `stuck.silent` across the live sessions.
- Every ledger change, and every presence change, re-sets it.
- When nothing is running it is not set, and nothing wakes.
- `stuck.loop` and `stuck.errors` need no timer. They are checked when the event arrives.
- After a sleep, the wake signal re-evaluates at once, because a one-shot timer doesn't fire while the machine sleeps.

## Away and recap

**Presence.** `presenceStep(state, signal, now)` is pure.
- `state` is `{reasons, awaySince, wasAway}`. `reasons` is the set of `lock`, `sleep`, `display` and `idle` that hold now.
- The signals are `lock`, `unlock`, `sleep`, `wake`, `displayOff`, `displayOn` and `idle{seconds}`.
- The user is **away** when `reasons` is not empty.
- `idle{seconds}` with 300 or more adds `idle`, and `awaySince` is `now` minus those seconds. A sample under 3 seconds removes it.
- The user is **back** when `reasons` becomes empty. The step then reports `{back: true, awaySince, awayMs}`.

**Where the signals come from, with no new polling.**

| | Lock, sleep, display | Idle |
|---|---|---|
| macOS | The observers `DesktopCatController` already holds (`screenIsLocked` and `Unlocked`, `screensDidSleep` and `Wake`, session resign and active) move into one shared `PresenceMonitor`, which the desktop cat and the sidekick both read. Add `willSleep` and `didWake`. | `CGEventSource.secondsSinceLastEventType` (needs no permission), sampled on the existing hidden poll tick at most once every 5 s, and only while a ledger session is alive. Also on each hook event and on unlock. |
| Windows | The message-only window in `platform/windows.rs` and `watch_away` already see lock and display. Today they tell only the desktop window. Add a sink for the island. | `GetLastInputInfo`, sampled on each hook event, when the island opens and on unlock. |
| Linux | logind `Lock`, `Unlock` and `PrepareForSleep` (`platform/linux.rs`). | Only if GNOME's idle monitor (Mutter) is there. Otherwise lock and suspend only. |

On Windows and Linux the idle part is lazy. The "back" is noticed at the next sample, which is the next hook event, the next island open, or an unlock. So a recap there can wait for the first of those.

**The recap.** `recapOf(snapshot)` is pure. `snapshot` is `{awaySince, now, sessions}`, with the ledger's sessions.
- It looks only at ring entries with `at` at or after `awaySince`.
- It returns nothing when no agent did anything in that time. A recap is never "nothing happened".
- It returns nothing when the away time was under 2 minutes (a lock and unlock in a hurry).
- Otherwise it returns `{lines, facts}`. There is one line per active agent, at most 3, then "+N more".

Each line is a fixed template filled with counts and basenames:
- **Finished:** "While you were away, {Agent} in {project} ran {n} steps, edited {a}, {b} and {c}, and finished."
- **Waiting for you:** "…and is waiting for your OK."
- **Hit an error:** "…and stopped on an error."
- **Still working:** "…and is still working."
- **Gone quiet:** "…and has been quiet for {n} minutes."

Rules for the lines:
- At most 3 file names, then "and {k} more".
- A step count past the ring's limit reads "40 or more".
- If one session did several of these, the last state wins, and approvals asked and failures are added as counts ("1 error").

**When it shows.**
- It shows once, at the moment of return, if the gate allows it.
- If a card is in front (an approval or a question), the recap is held. It is dropped if the card is still up 2 minutes after the return.
- It never shows twice for one away period, whatever the gate does.
- It has one button: OK. The × is the same as OK. Both count as a dismissal of the kind `recap`.

## The permission line

The card stays as it ships. Two things are added, only when the request has been explained.

**The line.**
- Mac: an 11 pt grey (`#8E939C`) single-line `Text` between the code block and the buttons, `lineLimit(1)`. The card is a fixed 160 pt, so `scripts/render-approval-card.sh` proves it still fits.
- Windows/Linux: a `.sub` div between the code and the button row in `buildApproval` (`windows/src/views/views.ts`). The button row is left alone.

**The badge.** A small orange capsule at the trailing edge of the "who" row, on high-risk requests only. It reads "High risk". Medium and low show only the line.

**The cat.** On a high-risk request the cat gives the existing `surprised` emote once. No new emote is added. If the desktop cat is flying to the notch for the same request, its alert emote already is this one, so there is no second.

**Data.** `ApprovalInfo` gains `target`, `risk` and `line` (Mac, `IslandTypes.swift`; Windows/Linux, `state.ts`). The Mac card today shows only `tool_input.command` or the tool name, and keeps no path or URL. For an edit or a write, F1 stores the basename as `target` and nothing else.

**What doesn't change.** Deny, Allow and Always, the 120 s limit, "never approve without a click" and the Codex rule that hides Always. A request the rules don't know still shows the card as today, with the `unknown_tool` line.

**Not in F1.** The E3 chat cards (`ClaudeChatViews.swift`, `chat.ts`) get the same line later.

## What's Claude doing?

An answer in the chat, built from the ledger, on this machine.

**How it is asked.**
- A chip in the chat's empty state: "What's Claude doing?".
- A typed question. `matchStatusQuestion(text)` is pure. It matches only a short message whose whole text, once lower-cased and stripped of punctuation, is one of a few phrases ("what's claude doing", "what is claude doing", "what are the agents doing", "what's codex doing", "status") with an optional agent name. Anything longer, or anything else, is a normal chat message. A real question that merely contains the words goes to the model as usual.

**How it is answered.**
- `statusOf(snapshot, agent?)` is pure. It reuses the recap's templates, for all live sessions or the one named.
- The answer is a card in the chat marked "From NotchMeow, on this Mac". It is not a model reply.
- **It is never added to a conversation.** It is not part of the history sent to any provider, and it does not reset a file drop's context. If the chat is on a cloud model, nothing about the question or the answer is sent.
- If nothing is running: "No agent is running right now."
- The optional local polish (below) can reword it. It follows the same rules.

**Where.** The chat send path (`ClaudeService.chat` on the Mac, `views/chat.ts` and `Bridge.aiChat` on Windows/Linux) checks the matcher first and returns before any provider is chosen.

## Drop on an agent's cat

Drag a file from Finder (or the file manager) onto an agent's own cat in the island. The agent that cat stands for gets a path, not the file.

**The big cat is not a target.** A drop on the big cat (the island's main cat, compact or open, in every display mode, including cat 1 in Two cats mode) works exactly as it does today: the chat or Ask drop, and after G1 the Ask and Shelf halves. Nothing that ships changes.

**Which cats are targets (agent cats).** A cat that stands for one agent and is not the big cat:
- in A cat for each agent mode, an agent's cat in the grid (its pill cat, which wears that agent's coat);
- in Two cats mode, cat 2 (the busiest other agent, `CatCast` `second`).

In One cat mode the small cats in the grid wear the Main cat and stand for no coat of their own, so they are not targets and a drop on them is unchanged. Widening the targets to those cats would be a later, separate decision of the owner's.

Each app tests the point against these cats' rectangles, **before** any other drop rule (`CatIslandLayout.swift` on the Mac: a new pure `agentCatAt(point, layout)`; the Windows/Linux twin in `core/layout.ts`). Today `FileDropView` gets one drop for the whole island.

**When it applies.** Only when the cat under the pointer is an agent cat and its agent has a live session in the ledger. In any other case the drop works exactly as it does today, so an agent cat with no running agent, the big cat, or a drop anywhere else on the island, is unchanged.

**What happens.**
1. The file's **original path** goes to the clipboard. One file is its plain path. Several files are one path per line. The file is not copied, moved or read.
2. That agent's terminal or editor is brought forward, by the routes the island already uses:
   - Mac: the first running terminal, VS Code or Cursor (`IslandViewContent` open-terminal routes, `⌃⌥T`'s activation). It brings an app to the front. It does not pick a tab.
   - Windows: the existing "Open terminal" action, which opens the project folder in VS Code.
   - Linux: nothing comes forward.
3. The island shows one line: **"Copied the path — paste it into {Agent}"**. On Linux, and when nothing could be brought forward, it is the same line.
4. The agent's cat gives the happy emote.

**What never happens.**
- No paste, no typing and no keystroke is sent to another app.
- No `claude --resume`, no second process, and no session is touched. The hooks are one-way, so NotchMeow has no channel into a running agent.
- The line never says "sent", "delivered" or "attached".

**The App Store build.** Copying to the clipboard and bringing an app forward work in the sandbox. The build keeps its existing limits.

**Clipboard.** The Mac uses `NSPasteboard`. Windows/Linux need a small clipboard command in Rust or the webview's clipboard, whichever works in the island window. No new dependency unless there is no other way.

## Dismissal memory

`dismiss`, `muted` and `unmute` are pure. The state is a count per kind.

- **Kinds:** `recap`, `stuck.loop`, `stuck.errors`, `stuck.waiting`, `stuck.silent`.
- **What counts:** a click on Not now, OK or ×.
- **What doesn't:** folding the island or letting a note time out unseen (a note waits up to 30 s for the gate, then is dropped silently). A tap on a note's action (for example "Show me") isn't a dismissal.
- **Muted** when the count reaches 2. A muted kind never shows.
- **Unmute** in Settings sets that kind back to 0.
- **The risk badge and the line are never muted.** They are a safety aid, not a nudge.
- **The count persists** across launches. It never decays by itself.

## The show gate

`shouldShow(input)` is pure. It returns `{show, reason}`. Every note (a recap or a nudge) goes through it. The drop's confirmation line is user-started and skips it.

It says no when any of these hold:
- the Sidekick switch is off;
- the kind is muted;
- the user is away (a recap waits for the return, and so does a nudge), or the agent is rate-limited (a stuck nudge only);
- a card is in front: an approval or a question (for `stuck.waiting`, the rule is the reverse: its own card must not be on screen);
- the user is typing in the island (`inputFocused`);
- another note is visible, or one was shown in the last 60 s (a recap goes first and may replace a nudge that is not yet seen);
- the session has had its nudge already;
- the recap for this away period was already given.

A note that is refused is kept up to 30 s (a recap up to 2 minutes) and shown if the gate opens, then dropped silently.

**Where it shows.** A note is a row in a new island view, `.sidekick`, with its own `ViewLayout` row. It is not the `.note` view (that is the AI error flow). It uses the island's existing peek for a finished task. If the island is already open on something else, the note waits for the gate. It never opens over the user's other windows, because the island is the notch.

## The local voice

The template is always shown first and is always right. A local model may offer a nicer sentence.

**Seam.** `SidekickVoice.nicerLine(facts) async -> String?` on the Mac, an `ai_oneshot` command on Windows/Linux. It returns nothing (and the template stands) when there is no local model, on any error, after 6 seconds, or when the sanity check fails.

**Which models.**
- Only a provider whose placement is `local`: servers on `127.0.0.1`, `::1` or `localhost` (`AICatalog` placement), and Apple on-device on the Mac.
- It uses the local choice (`ModelRouter.localChoice`; `router::local_choice` in Rust), and never the Auto choice. F1 does not add an `AIFeature.cats`, because Auto would pick a cloud model for it.
- It is a one-shot request, not a conversation. Nothing is stored, and the chat's history is untouched.

**What it is given.** Only the same facts that are in the template: the agent name, the project's basename, counts, up to 3 file basenames and the state words. Never a command, a path, a prompt or an assistant message. The prompt is short (under about 800 characters) because Apple's on-device model is limited to a few thousand tokens.

**Sanity check.** `acceptNicerLine(line, facts)` is pure. It accepts a line only if it:
- is one line of at most 200 characters, with no URL, no `/` or `\`, no backtick and no markdown;
- uses only numbers that are in the facts;
- names the agent.

**When it replaces the template.** If it arrives within 6 s, it crossfades in once, and only if the pointer isn't over the note. After that, nothing changes. A permission line is never reworded: it stays the fixed template.

## Settings

A new **Sidekick** section in Settings, in the existing row style. Nothing existing is restyled.

| Row | What it does |
|---|---|
| Recaps and nudges | A switch, on by default. Off means no recap and no stuck nudge. |
| Nicer wording from a local model | A switch, on by default. Under it, one grey line: "Found: {model}" or "No local model found". Off means only templates. |
| Muted notes | One row per muted kind, with an **Unmute** button: Away recaps, Repeated steps, Repeated errors, Waiting for your OK, Gone quiet. When none is muted it says "Nothing is muted". |
| (note) | "Permission explanations are always on." |

The same rows appear on Windows/Linux in `settings/sidekick.ts`.

## Storage

- **Mac, UserDefaults:** `sidekick.on` (Bool), `sidekick.local` (Bool) and `sidekick.dismissals` (JSON, kind to count).
- **Windows/Linux:** the same three as one `sidekick` object in `settings.json`. The Rust cleaner (`clean_sidekick` in a new `sidekick_settings.rs`) keeps it, and `settings.rs` must keep it at every save, as it does the `cat` block.
- **Both** go through `cleanSidekickSettings`, a clean-up of its own, so every existing fixture stays byte for byte. An unknown kind is dropped, a bad count becomes 0, a count above 2 is capped at 2, a bad switch is its default (on).
- **Not stored:** the ledger, the presence state, the nudged-session set, and any note.

## Contract

Like B and H, the rules are written once and both apps replay them.

- **`shared/sidekick-core.js`** (pure, beside `theme.json`, shared by Node and the apps' tests) holds:
  1. `explain` (the risk rules);
  2. `eventFrom` and `ledgerApply` (the hook adapter and the ledger);
  3. `stuckStep`;
  4. `recapOf`, `statusOf` and `matchStatusQuestion` (the templates and the matcher);
  5. `dismiss`, `muted`, `unmute` and `cleanSidekickSettings`;
  6. `presenceStep`;
  7. `shouldShow`;
  8. `acceptNicerLine`.
- **`scripts/gen-sidekick-fixtures.mjs`** writes `tests/fixtures/sidekick/*.json`, and `--check` fails on stale ones: `explain-cases.json`, `hook-cases.json` (the real-shaped payloads for the four agents, including a Windows-shaped variant), `stuck-cases.json`, `recap-cases.json`, `status-cases.json`, `dismiss-cases.json`, `presence-cases.json`, `show-cases.json`, `voice-cases.json` and `settings-cases.json`.
- **`docs/SIDEKICK-CONTRACT.md`** documents them, and **`scripts/print-sidekick-tables.mjs`** prints the rules as tables for a person to read.
- **Swift ports** (`Sidekick*.swift`) are tested by `scripts/test-sidekick-*.sh`. **TypeScript ports** (`windows/src/sidekick/`) are tested by `npm run check:sidekick`. The Rust twin is the settings cleaner only.
- **Frozen IDs:** the five dismissal kinds and the reason IDs are contract values, like the cat and pill IDs. A new reason may be added. None is renamed.
- **Only new files.** `tests/fixtures/cat/`, `ai/` and the shelf's fixtures stay byte for byte (`node scripts/check-fixtures-additive.mjs`).
- **If an app and a fixture disagree,** `sidekick-core.js` decides.

## Testing

- **F1-0:** every rule against its cases, the generator's `--check`, and the additive check.
- **Each app:** replay of every fixture in the app's language, then the wiring tests below.
- **Wiring** (`scripts/test-sidekick-wiring.sh` on the Mac, a script test on Windows/Linux): pins where the app calls the pure parts: the feed point before the approval gate, the chat's matcher before the provider choice, the drop's agent-cat test (before every other drop rule, never on the big cat), the show gate before every note.
- **Leak test.** Fake providers record every request. A marker string is put in a command, a prompt, a parent folder of `cwd`, an assistant message and a file's contents. After a full recap, a nudge, a status answer and a local polish, the test asserts:
  1. the marker is in no log line, and no log line has a command or a path;
  2. the cloud fake provider received no request at all;
  3. the local fake provider's request holds only the allowed facts, not the marker;
  4. the status answer is not in the conversation that the chat holds.
- **CPU.** The hidden island adds no timer. A test pins that the stuck clock is not set when no session is live, and that idle is sampled only while one is. The existing 0 % hidden check stays.
- **Pictures** (no app launch): `render-approval-card.sh` for the card with the line and the badge, and a new `render-sidekick.sh` for the note rows, as in `render-cats.sh`. The Windows/Linux pictures come from the Vite dev page.
- **The owner's real-build checks** at the end: lock and unlock after a run; a high-risk request; a deliberate loop; a long wait on an approval; the status question on a cloud chat; a file dropped on an agent's cat (a grid cat in A cat for each agent mode, cat 2 in Two cats) and on the big cat (unchanged); Unmute in Settings.

## Rules that apply (CLAUDE.md)

- **No telemetry.** No network call except a local model on this machine. Nothing is added to the cloud path.
- **Never block Claude Code.** The sidekick only reads events. If the app doesn't answer, the hook exits as today. The feed must be quick and must never wait on a timer or a model.
- **Never approve without a click.** Risk is a label. Nothing the sidekick does answers a request.
- **Never overwrite `~/.claude/settings.json`.** F1 installs no hook. It reads the events the existing hooks send. It never reads anything under `~/.claude`, and never `transcript_path`.
- **0 % CPU when the island is hidden.** No new timer or monitor on the hidden poll. One one-shot timer that idles.
- **Never restyle what ships.** The card keeps its look. The grey line and the badge are the only additions. Settings gets a new section.
- **Mac is primary.** Every feature is on the Mac. The Mac gets at least what Windows/Linux gets.
- **Pill IDs, cat IDs and the contract strings are frozen.** F1 renames nothing.
- **Secrets stay in the Keychain.** F1 stores none.
- **No third-party dependency.**
- **Never push. Commit only when the owner asks.**

## Rounds

**Prerequisite round (a separate small plan, not F1):** `docs/superpowers/plans/2026-10-14-mac-all-terminals.md`. Widen the Mac to Claude Code sessions in every terminal, not only VS Code and Cursor.
- Change `HookServer.processEvent` (the "Ignored" branch) and the `PermissionRequest` and `AskUserQuestion` paths that answer `ask` at once for those terminals.
- Update `docs/QA-MAC.md` and `docs/INTEGRATIONS.md`, whose "terminal" wording is then true.
- It comes first because Windows/Linux already handle every terminal, and the Mac is primary. F1-0 and F1-tauri don't depend on it. F1-mac is far more useful after it.

**F1-0, the contract** (one worktree session, Haiku 5.5 at medium effort: the plan gives the code).
Eight tasks, in `docs/superpowers/plans/2026-10-14-f1-0-sidekick-contract.md`: the core's `explain`; `eventFrom` and `ledgerApply`; `stuckStep`; `recapOf`, `statusOf` and `matchStatusQuestion`; `dismiss`, `muted`, `unmute` and the settings cleaner; `presenceStep` and `shouldShow`; `acceptNicerLine`; the generator, the fixtures, `docs/SIDEKICK-CONTRACT.md` and the additive check.
- Only new names and new files.
- **Owner checkpoint:** `node scripts/print-sidekick-tables.mjs` prints a table of the risk reasons with a sample request and its line, the stuck thresholds with a timeline for each, and the recap and status samples.

**F1-mac and F1-tauri, in parallel** (worktree sessions).

*F1-mac* (Sonnet 5.5 at high effort: trigger 1, the presence monitor, timers and AppKit work). About 14 tasks:
1. the Swift ports and their tests;
2. the settings store and the Settings section;
3. the ledger and its feed in `HookServer`;
4. the shared `PresenceMonitor`, taken out of `DesktopCatController`, with the desktop cat's tests still green;
5. the idle sample on the existing tick;
6. the one-shot stuck clock;
7. the show gate and the `.sidekick` island view;
8. the recap;
9. the permission line and the badge (`ApprovalInfo`, `ApprovalView`), and the `surprised` emote;
10. the status answer in the chat;
11. the agent-cat hit test (the big cat is excluded) and the drop handoff, including the clipboard and the terminal-forward routes;
12. the local voice (`SidekickVoice`);
13. the leak test and the wiring test;
14. the pictures and the docs.

*F1-tauri* (Haiku 5.5 at high effort). About 14 tasks: the TypeScript ports; the Rust settings cleaner and the `settings.rs` keep; the ledger feed in `hooks.ts`; the island sink for the lock and display signals, and the idle sample; the stuck clock; the gate and the sidekick row; the card line and badge; the status answer; the agent-cat drop test and the clipboard command; `ai_oneshot` for the local voice; the leak test; the dev page and the docs.

Three owner checkpoints each: (1) the card with the line and badge, and the note rows, as pictures; (2) the recap, a nudge and the status answer in a scripted run (`scripts/fake-subagent-events.py` style); (3) sign-off, then `nm-reviewer-deep` over the whole branch, with the privacy review in its brief.

## Out of scope
- **F2, the desktop helper:** a hotkey that explains selected text or a screenshot.
- **F3, the companion:** a memory you can see and edit, and a personality that grows.
- **The chat cards (E3):** the permission line and the badge on the chat's approval cards.
- Anything that talks into a running agent: pasting, typing, `claude --resume`, a new session.
- Reading a transcript, or showing what the agent said.
- A model that decides or blocks. The sidekick labels only.
- Notifications outside the island (system banners, sounds).
- A new emote or a new cat state.
- Sound for the notes. Stage C can add it later.

## Risks
- **The Mac sees few Claude Code sessions today.** Fixed by the prerequisite round. Until then, F1-mac's value is limited, and the spec says so.
- **The risk rules are heuristics.** A wrong label could give false comfort or alarm. Mitigations: it labels only, `unsure` exists, near-miss cases are pinned, and the line never repeats the command so it can't mislead about it.
- **Away detection differs by platform.** On Windows and Linux the "back" can be late. The coverage notes say so.
- **A nudge can annoy.** Mitigations: once per session, 2 dismissals mute a kind, the gate, and the switch.
- **The drop adds one target and changes none that ships.** The big cat keeps today's drop, so a file dropped on it is still chat context (and, after G1, Ask or Shelf). Only a drop on an agent's own cat (a grid cat in A cat for each agent mode, cat 2 in Two cats) with a live session hands over a path. Everywhere else the drop is unchanged.
- **G's drop halves.** G1 splits the open island into Ask and Shelf halves by the pointer's position. The per-cat hit test runs first; the halves apply only to the big cat area and the rest of the island, never to an agent cat that took the drop. A drop on an agent cat with a live session never reaches `zoneAt`, and the shelf's drag-over highlight must not light up over an agent cat. F1-mac must check which of F1 and G1 has landed and keep the order. If G1 has not landed, the test is still first.
- **Docs-only hook fields.** Failure and stop events are described in docs, not yet seen in fixtures. F1-0 pins real-shaped ones first (`scripts/fake-subagent-events.py` exists for the Mac).
- **The fixed 160 pt card.** The extra line must fit. `render-approval-card.sh` proves it, and the plan treats a failure as a stop.
- **The local model is slow or odd.** The template is shown first, the swap is optional, and the sanity check rejects bad lines.

## Answered by the owner on 2026-10-14

1. **Which risks get the orange badge?** High risk only. Medium and low show the grey line only.
2. **Which cat takes the drop?** The big cat keeps today's drop exactly (the chat or Ask drop, and G's future Ask and Shelf split). Dropping a file on an **agent's own cat** (the agent cats in the grid in A cat for each agent mode, or cat 2 in Two cats mode) hands that agent the path: copy the path, bring its terminal or editor forward, show the honest line. Nothing that ships changes.
3. **Several dropped paths:** one path per line, plain, with no quotes.
4. **The agent's own words:** none are kept. No prompt text and no assistant text reaches a line, the ledger or a local model.
5. **The errors rule:** 3 failures in a row within 10 minutes.
6. **Minimum away time for a recap** after a lock, sleep or screen-off: 2 minutes (idle already needs 5).
7. **How a note appears when the island is hidden:** through the island's existing peek for a finished task. F1 adds no new window. If that peek does not suit a note, the note waits until the island is next open.
8. **Master switch:** "Recaps and nudges", on by default. The permission line has none.
9. **How long a held note lives:** 30 s for a nudge and 2 minutes for a recap, then dropped silently.
