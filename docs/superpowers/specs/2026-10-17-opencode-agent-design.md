# OpenCode as an agent pill: sessions, steps and approvals in the notch

Status: draft for the owner's review (2026-10-17; the owner decided in chat the same day to add OpenCode). Revised 2026-10-28 after the builder check and the owner's three answers (see "Decisions"). Part A of two: this spec is the agent pill. Part B, OpenCode as a chat brain, is "Call 11" in `2026-10-17-notchmeow-chat-design.md`. It sits beside `2026-10-17-projects-view-design.md` (OpenCode sessions appear in Projects) and `2026-10-17-focus-awareness-design.md`.

Marks: "builder's call (main session), 2026-10-28" tags a choice the main session made from the builder check, not the owner. The owner can overrule any of them.

## Why

OpenCode (the open-source terminal coding agent, MIT, macOS, Windows and Linux) is used next to, or instead of, Claude Code, Codex and Gemini CLI. Today a person running it gets nothing in the notch. The owner wants OpenCode treated like the agents NotchMeow already knows: a pill, live steps, a finish, and permission requests that can be answered from the notch with a click.

## Goals

1. An **OpenCode pill** that shows its sessions, the step it is on, and when a turn ends, like Codex and Antigravity.
2. **Permission requests answered from the notch on the Mac** (a card with Allow once / Deny, and "Always" only if it can be sent safely, see "Approvals"), with the same rules as every other card: nothing is approved without an explicit click, and a card that cannot be delivered falls back to OpenCode's own prompt.
3. OpenCode sessions in the **Projects view**, grouped by folder like the other agents.
4. **Install and uninstall from Settings → Agents**, with the dated backup, the merge and the confirmed diff the other agents use.
5. The Mac first with full cards. Windows and Linux are **watch-only first** (owner, 2026-10-28): steps and finish, no approval card.

## Non-goals

- Running OpenCode for the user or starting `opencode serve` for the pill (that is the chat brain, part B). The pill only listens to sessions the user started.
- Reading OpenCode's credentials, its session database or its config beyond the one file NotchMeow writes. `~/.local/share/opencode/auth.json` is never opened.
- Sending any prompt, assistant text, tool output, command or full path to the notch. The relay carries what Codex's carries: session ID, folder name, tool name, a short input for the step words.
- Approval cards on Windows and Linux in the first plans (a later sub-project, see "Left for later").
- Subagent kittens in the first plan.
- OpenCode's desktop app and IDE extensions as separate hosts: they use the same plugin directory, so they work if they load plugins, but "Open OpenCode" targets the terminal only. Unverified.
- Supporting more than one plugin API generation (owner, 2026-10-28).

## Anti-goals (a failure even if it works)

- Blocking or slowing OpenCode without the user knowing. The plugin never waits for NotchMeow except for a permission request; that wait is bounded (about 118 s) and visible (the notch card is up), and when NotchMeow is not running the plugin does nothing at all. (Reworded: builder's call (main session), 2026-10-28.)
- Approving anything for the user. A timeout, an error or a closed socket resolves to "ask" (OpenCode shows its own prompt), never to allow.
- Overwriting or deleting a file the user wrote. The installer creates one file of its own and touches no existing plugin or `opencode.json`.
- A listening port, a poll or a timer in NotchMeow for this feature (the 0 % rule). Events arrive on the existing `nm.sock`.
- A new network call. The plugin talks to the local socket only.

## What was found (sources; "unverified" must be proven by the builder on the installed version)

- **Plugins are files.** A `.js` or `.ts` file in `~/.config/opencode/plugins/` (global) or `.opencode/plugins/` (a project) loads at startup, with no config change; npm plugins go under the `"plugin"` key of `opencode.json`. Load order: global config, project config, global plugin directory, project plugin directory. https://opencode.ai/docs/plugins/
- **Two plugin API generations are documented** (checked 2026-10-28; versions v1.18.x and v2.0.x both appear). V1 handles events and hooks such as `permission.ask`. V2 replaces `event` with `ctx.event.subscribe()`, `tool.execute.before/after` with `ctx.tool.hook("execute.before" / "execute.after")`, and `permission.ask` with `ctx.permission.hook("evaluate", cb)`. **Unverified: which one the current stable release loads, and whether V1 plugins still load. The OC-0 spike decides and records the OpenCode version.**
- **A plugin receives** the project, an SDK client, Bun's shell, the working directory and the git worktree (V1), or a `ctx` (V2). https://opencode.ai/docs/plugins/
- **Events a plugin can handle** (documented): `session.created`, `session.compacted`, `session.deleted`, `session.diff`, `session.error`, `session.idle`, `session.status`, `session.updated`; `tool.execute.before`, `tool.execute.after`; `permission.asked`, `permission.replied`; `message.updated`, `message.part.updated`, `command.executed`, `file.edited` and others.
- **A plugin can block a tool** by throwing in `tool.execute.before`.
- **Answering a permission.** The V2 `ctx.permission.hook("evaluate", cb)` runs after the configured rules and before a prompt is published; the callback may be async and may set `event.effect` to allow, ask or deny (with a message). It does not run for an explicit configured deny. This is the route the spec relies on: it removes the double-prompt race, needs no `client` reply, and makes "ask" a plain fall-through. The old route (the server API `POST /session/:id/permissions/:permissionID`, SDK `postSessionByIdPermissionsByPermissionId`, answering the `permission.asked` event) is not used. https://opencode.ai/docs/server/
- **The permission event** is `permission.asked` with `data: {id, sessionID, action, resources, save?, metadata?, source?: {type:"tool", messageID, id}, message?}` (the schema package, `permission.ts`). It carries `action` and `resources`, not a tool name or tool input, so the payload's `tool_name` and `tool_input` are built from `action` and `resources`. Actions such as `external_directory` or `doom_loop` have no `SessionStepText` words: the builder adds words for them, or the card shows the action name. `metadata` can hold diffs or file text and is never forwarded.
- **Permission outcomes** are `once`, `always` and `reject`. `always` saves durable, project-scoped `allow` rules (not just for the session), which is why the card has no Always. `reject` also rejects every other pending request in the same session. Rules are `allow`, `ask`, `deny` in `opencode.json`. Several permissions default to `allow`, so the notch will only see the ones set to `ask`. https://opencode.ai/docs/permissions/
- **Sessions carry** an ID and a directory; child (subagent) sessions carry `parentID` in `session.created.info`. Other field names inside each event are not in the prose docs. **Unverified: read them from the generated OpenAPI spec at `/doc` of a running `opencode serve`.**
- **Platforms and license.** MIT; macOS, Windows, Linux; install by script, npm, Homebrew, Scoop, Chocolatey, and a desktop app (beta). The repository now lives at https://github.com/anomalyco/opencode (it was `sst/opencode`).
- **Sign-in state** lives in `auth.json`. https://opencode.ai/docs/providers/ The pill does not need it.

## How NotchMeow receives the events: a plugin that calls the existing relay (recommended)

Two ways exist.

| | Plugin file forwarding to `nm-hook` | NotchMeow connects to `opencode serve` (`GET /event`) |
|---|---|---|
| Who starts it | OpenCode, itself, every time | The user must run `serve`, or NotchMeow must |
| Covers sessions the user starts in a terminal | Yes, all of them | Only sessions on that server |
| New NotchMeow pieces | One generated file, one relay tag | A client, port discovery, auth, reconnect and a long-lived connection (a poll in effect) |
| Approvals | The permission hook, answered in-process | An API call to the server, which has to be reachable and, if protected, authenticated |
| Credentials | None | A server password if the user set one |
| 0 % rule | Nothing runs unless OpenCode runs | A connection stays open while OpenCode is closed |

**Recommendation: the plugin.** It reuses the relay the other agents use (`nm-hook` on the Mac, `notchmeow-hook` on Windows and Linux), so socket discovery, timeouts and the "app is not running, exit at once" rule are already solved and already tested. The server route stays for part B, where NotchMeow itself starts the server it talks to.

### The plugin file

NotchMeow writes one file, `notchmeow.js`, in OpenCode's global plugins folder. **One template, for the current stable plugin API only** (owner, 2026-10-28; if the spike confirms V2 is current, it is built on `ctx.permission.hook("evaluate")`, `ctx.event.subscribe()` and `ctx.tool.hook`). Two templates are shipped only if the spike shows both generations in use, and then the owner is asked first (builder's call (main session), 2026-10-28).

Folder lookup: a GUI app does not share the shell's environment, so the installer reads its own `XDG_CONFIG_HOME` and `OPENCODE_CONFIG_DIR`, else `~/.config/opencode/plugins/`; on Windows `%USERPROFILE%\.config\opencode\plugins\`, unverified (builder's call (main session), 2026-10-28).

The file is generated from a template by the app with the relay's absolute path in it (the path contains a space on the Mac and is passed as an argument array, never through a shell string). It carries a marker line, `// notchmeow-managed: v1`, so detection, update and uninstall find exactly NotchMeow's own file. A backup named `notchmeow.js.bak-…` does not end in `.js`, so OpenCode never loads it.

What it does, in plain terms:

1. On each handled event it builds a small JSON payload in the Claude-like shape the app already understands and starts the relay with `--agent opencode`, writing the payload to its input. It does not wait for the relay except for a permission request, and it never throws: every failure is swallowed so a broken NotchMeow can never break OpenCode. If the spike finds the current release only offers the event route (no holdable hook), the relay for a permission request runs detached and is never awaited inside the event handler, so other events keep flowing (builder's call (main session), 2026-10-28).
2. The mapping:

| OpenCode | Payload `hook_event_name` | Notes |
|---|---|---|
| `session.created` (top-level session) | `SessionStart` | `session_id`, `cwd` = `directory` |
| a user message arriving (`message.updated`, role user) | `UserPromptSubmit` | **No prompt text is sent.** One per message ID: `message.updated` fires many times per message, so repeats are dropped, and assistant messages send nothing (builder's call (main session), 2026-10-28) |
| tool before hook | `PreToolUse` | `tool_name`, `tool_input` cut by the allowlist below |
| tool after hook | `PostToolUse` | |
| `session.idle` (top-level session) | `Stop` | the turn ended |
| `session.error` | `StopFailure` | an abort error maps to `Interrupt` instead (builder's call (main session), 2026-10-28) |
| `session.deleted` (top-level session) | `SessionEnd` | |
| the permission hook | `PermissionRequest` | held; see "Approvals" |
| `permission.replied` | `PostToolUseFailure` | same `tool_name` and `tool_input` as the request, so a card whose request the user answered in OpenCode's terminal clears at once; the plugin also kills the held relay child. Without it a rejected request has no PostToolUse and the card sits until about 120 s (builder's call (main session), 2026-10-28) |

   OpenCode's tool names (`bash`, `edit`, `write`, `read`, `webfetch`, `task`…) are mapped to the names `SessionStepText` already words (Bash, Edit, Write, Read, WebFetch, Task); an unknown tool keeps its own name.
3. **`tool_input` is cut by an allowlist**: bash `command`, edit / write / read `filePath`, webfetch `url`, task `description`, each cut at 2000 bytes by the plugin itself (the Windows relay already cuts every field at 2000 bytes, `windows/hook/src/main.rs:42`; the Mac relay has no cut, so the plugin's own cut is what holds on both). The card needs the command or file name (memory only, like Codex). Everything else, including `metadata`, output and diffs, is dropped. The fixtures pin this (builder's call (main session), 2026-10-28).
4. **Child (subagent) sessions** (those with a `parentID`): their tool and permission events are forwarded under the parent's `session_id` (their permission requests are real); their SessionStart, Stop and SessionEnd are suppressed, so the pill does not read "finished" while the parent works; no `agent_id` is sent, so no kittens appear (builder's call (main session), 2026-10-28).
5. It sends nothing when the relay file is missing, and it sends at most one event per tool call.

The mapping table and the exact field names are fixed in the contract (`tests/fixtures/opencode/`, below) after the builder proves them against a real OpenCode.

## Approvals

OpenCode asks for a permission only for rules set to `ask`. In the permission hook the plugin sends a `PermissionRequest` through the relay and **waits for the relay's answer**. Ceiling: the relay socket times out at 118 s, the app's card at 115 s and the hook budget is 120 s, so the plugin kills its relay child at about 118 s (builder's call (main session), 2026-10-28). The relay prints the Claude-style `{"hookSpecificOutput":{"decision":{"behavior":"allow"|"deny"}}}`, or nothing; the plugin parses exactly that and **empty output means ask**. The fixtures pin this shape (builder's call (main session), 2026-10-28). When the answer comes:

- **Allow once** → the hook sets the effect to allow for this request only.
- **Deny** → OpenCode's reject. **This also rejects the session's other pending requests**; the card's help text says so plainly (owner, 2026-10-28). The spike records which call the plugin makes and confirms the cascade.
- **"ask"**, empty output, a timeout, no app, a broken socket, anything else → the hook changes nothing; OpenCode's own prompt shows and the user answers there.
- **Always** is not offered on the card in the first plan. OpenCode's `always` saves durable, project-scoped allow rules, which is broader than one click on a summary line should grant. A later version may offer it with the patterns written out.

While the notch card is up OpenCode shows nothing for up to about two minutes. This is the same as Claude Code's PermissionRequest hook today; the island's alert and Focus Awareness (below) are the mitigation (builder's call (main session), 2026-10-28).

If the spike finds that the installed OpenCode has no hook that can hold a permission request, the fallback is the documented one for tagged agents: the request is answered "ask" at once, the card is not built, and the pill shows "Still waiting in OpenCode". Everything else in this spec still works. The owner is told before the plan is final (builder's call (main session), 2026-10-28, from the spec's earlier question 3).

The card follows the existing look (Codex's: the pill's color, the summary of the step, the same two buttons). The risk label under it (`explain`) is the sidekick's, unchanged. Both the card's 600 ms click guard and the "ask at once" fallback already exist (`ApprovalClickGuard`, `answersAskAtOnce`).

**Windows and Linux (owner, 2026-10-28): no card.** `windows/src/island/hooks.ts` already answers every tagged agent's permission request "ask" at once, and the pill shows a note like "Still waiting in OpenCode". There is no card, answer plumbing, `explain` label or click guard for a non-Claude agent there, and no Codex precedent; building them is a later sub-project.

## The pill

- **ID `agent_opencode`**, following `agent_codex`, `agent_gemini`, `agent_antigravity`. No pill with this ID or any `opencode` string exists in the repo today (rechecked 2026-10-28; `validateAgent` accepts it). The ID is frozen once it ships.
- **Label "OpenCode"**, subtitle in the style of the catalog's others (for example "Terminal coding agent"), category agents. Color `#FB923C` (see "Decisions").
- **On/off and slot.** Copy Gemini and Antigravity: a "Where you code" switch, off by default; on Windows and Linux an off pill shows only while the agent works (CLAUDE.md's rule). The Mac's four-slot cap applies (`SettingsStatus.maxSlots = 4`) (builder's call (main session), 2026-10-28).
- Routing: the relay tags `nm_agent=opencode`. `HookOrigin` gets a `.opencode` route beside `.codex`, because a plain tagged agent is answered "ask" at once with no card (`answersAskAtOnce`); `.opencode` keeps the Codex behavior (a card) on the Mac and nothing else changes for other tagged agents. `AgentTarget` knows its tap target: the terminal the session runs in, by the same `bundle_id` / `TERM_PROGRAM` rules as Claude Code; `Open` offers nothing for a session with no known terminal.
- **Focus Awareness.** OpenCode's terminal hosts go into the `FocusAware` table. `FocusAwareApp.stepBack` takes a route, so `.opencode` needs its own case or the step-back silently never fires (builder's call (main session), 2026-10-28).
- **Names.** `PillCatalog`, `SidekickText` and `SidekickRecap` gain the name, and so do `shared/sidekick-core.js` (then `node scripts/gen-sidekick-fixtures.mjs` and `gen-sidekick-ts.mjs`) and the Windows names table `core/pills.ts`. `CatAgentList` and `CatDisplay` give it a coat the way a new agent gets one (`CatAgentCats`). Nothing existing is restyled.
- **Wiring checklist.** The 43 `.codex` / `agent_codex` references in 16 Swift files (SidekickLedger, SidekickEngine, IslandViewContent, CatDisplay, SettingsSections…) each need an explicit "does `.opencode` behave like Codex here" call, written down as a checklist task, and `test-hook-origin-wiring.sh` is extended to pin it (builder's call (main session), 2026-10-28).
- **Build scope.** Writing into `~/.config/opencode` is outside the App Store sandbox, so the pill, like Codex, Gemini and Antigravity (`githubOnly: true`, routes under `#if !APPSTORE`), is GitHub-build only; the App Store build treats an `opencode` tag as the ordinary external agent it already is.

## Projects feed

`projectEventFrom` (`shared/projects-core.js`, around lines 205-210) turns every non-Claude `nm_agent` into `kind: 'other'` with every field empty, and `otherAgentSeen` is the only thing it sets. **Codex has no Projects support either**, so this is new work from scratch: the rule must let `agent: 'agent_opencode'` events carry `sessionId`, `cwd`, `kind` and the step like Claude Code's do (it needs only `session_id` and `cwd`, which the plugin sends). It belongs in its own contract task with new cases in `tests/fixtures/projects/` and `tests/fixtures/mac/projects-scenarios.json`, in the shared core and both ports. `registryApply` must not treat the new agent as Claude Code: it gets its own `agent` field and pill color in the row, and the new field must not reach code paths that assume Claude. OpenCode events still set `otherAgentSeen`, so the Claude-only layout behaves as before (builder's call (main session), 2026-10-28). Child sessions are folded into the parent as above; kittens are out of this feed for now.

## Install and uninstall (Settings → Agents)

A row "OpenCode" in the same style as Codex's: state ("Hooks not installed" / installed), **Install hooks** and **Uninstall hooks**, and the **minimum OpenCode version** the plugin needs (owner, 2026-10-28; the version comes from the OC-0 spike). The wording stays "hooks" for consistency, with the sentence "Adds one plugin file to OpenCode's plugins folder." (builder's call (main session), 2026-10-28).

The never-overwrite rule, specialised:

1. Look for the plugins folder (lookup above); if OpenCode is not installed (no `opencode` on the path and no config folder) the row says "OpenCode not found" and offers nothing.
2. Build the file. If `notchmeow.js` exists and carries the marker, the diff is old against new. If a file of that name exists **without** the marker, the installer stops and says so (it never writes over a file it did not make).
3. Show the diff (a new file shows as all additions, with the path) and wait for the click.
4. On confirm: write through the shared `ConfigFileWrite.writeWithBackup` (a dated backup of an existing file, a symbolic link kept as a link, atomic write).
5. **Uninstall** removes only a file that carries the marker, after a confirm, and keeps a dated backup copy beside it. Nothing else in the folder or in `opencode.json` is touched.
6. The same flow on Windows and Linux through the Settings page and the relay's folder logic. A project-level plugin folder is never written to.

## Phasing

1. **Contract (OC-0).** `tests/fixtures/opencode/`: recorded OpenCode event payloads (from a real run, scrubbed), the mapping to Claude-like payloads, expected relay arguments, and a `reference.py` that decides when an app and a fixture disagree. Includes the spike: **the OpenCode version and plugin API generation to support (recorded as the minimum version)**, field names, whether the permission hook can hold a request and what Deny calls, subagent session fields, Windows path. Output decides this spec's "unverified" lines.
2. **Mac (OC-mac).** The generated plugin and its installer, `HookOrigin` route, pill, card, Settings row, Focus Awareness case, the wiring checklist, `scripts/test-opencode-*.sh`, `scripts/fake-opencode-events.py`.
3. **Projects (OC-projects).** The shared rule change with fixtures, in the Mac and Windows/Linux ports.
4. **Windows and Linux (OC-tauri), watch-only.** The relay mapping in `windows/hook/src/agents.rs` is not needed (the plugin already sends Claude-like payloads); the installer, the pill, the Settings row, the "Still waiting in OpenCode" note and the name changes in `core/pills.ts` and the shared sidekick core are. Linux and Windows folders differ; both are tested.

## Tests

- **Plugin template:** a Node test runs the generated `notchmeow.js` against a fake OpenCode host (a stub that calls its handlers with recorded events and a fake permission hook) and a fake relay (a script that records its input and answers on stdout). It proves the mapping, that no prompt text is sent, that `tool_input` is cut to the allowlist and carries no `metadata`, that child sessions send no Start, Stop or End, that repeated `message.updated` events send one prompt event, that every failure is swallowed, that a missing relay file sends nothing, that a permission waits and allows or denies only on an explicit allow / deny in the pinned answer shape, that `permission.replied` sends `PostToolUseFailure` and kills the relay child, and that empty output, a timeout and a crash mean ask.
- **Relay and routing:** `scripts/test-hook-relay.sh` gains the `opencode` tag; `test-hook-origin.sh` the `.opencode` route and the "other tagged agents still answer ask" case; a wiring test pins the call sites, including the Focus Awareness case.
- **Installer:** against a temp home: new file, marked file updated, unmarked file refused, uninstall removes only the marked file, backups exist, a symlinked plugins folder is followed.
- **`scripts/fake-opencode-events.py`**, in the style of `fake-terminal-events.py`: sends a scripted OpenCode session (start, prompt, a step, a permission request held open for the card, an idle) to a running Debug build's socket, with `--print`, `--sock` and `--approval`. For the owner's check; the tests send to a socket of their own.
- **Fake `opencode` for part B** is separate (see the chat spec).

## Left for later

Approval cards on Windows and Linux (a generic non-Claude approval path in `hooks.ts` plus the Rust bridge; owner, 2026-10-28), subagent kittens (OpenCode's `task` tool makes child sessions; field names unverified), a project-level install, an "Always" button, OpenCode's desktop app as a named host, step diffs (`file.edited`).

## Decisions

### Owner's answers, 2026-10-28

1. **Windows and Linux: watch-only first.** The pill shows steps and finish; a permission request there is answered "ask" at once and the pill shows a note like "Still waiting in OpenCode". Full approval cards on Windows and Linux are a later sub-project. The Mac gets full approval cards (Mac-primary rule).
2. **One plugin API.** Support only the current stable plugin API, one template, built on the permission hook that can hold the request (V2 `ctx.permission.hook("evaluate")` if the spike confirms it is current). The Settings row states the minimum OpenCode version; the OC-0 spike records it.
3. **Deny stays.** The Deny button maps to OpenCode's reject, which also rejects the session's other pending requests. The card's help text says so plainly.

### Settled by builder's call (main session), 2026-10-28

These were the spec's own questions; the builder check says none changes the build, so the spec's proposals stand. The owner can overrule.

1. **Color** `#FB923C` (warm orange), unused by Codex (`#2DD4BF`), Gemini (`#8AB4F8`) and Antigravity (`#E879F9`).
2. **Always** is left off the card in 1.0 (it persists project-wide).
3. **If no hook can hold a permission request:** watch-only on the Mac too ("Still waiting in OpenCode"); the owner is told before the plan is final.
4. **GitHub build only**, like the other agents (settled by precedent).
5. **Install wording:** "Install hooks", with the sentence under the row.
6. **Subagents** as kittens: a later round.

### Still open for the owner

None.
