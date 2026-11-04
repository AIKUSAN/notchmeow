# Projects: every Claude Code project and its sessions, from the notch

Status: draft for the owner's review (2026-10-17, second version: the island's project pills, the expandable Claude panel, the Projects screen and four polish items). Part of the quality-of-life set for the next major update; the version stays 1.0.0 until that update ships (owner, 2026-10-17).

## Why

The owner runs Claude Code from the Claude desktop app, signed in with a Claude subscription, on several projects at once. On a project like NotchMeow there is a main chat (the orchestrator), side sessions in git worktrees (one per plan), and subagents inside each session. Today the notch shows one Claude Code pill holding only the latest session: the other sessions, which project they belong to and what each is doing are invisible unless the owner switches windows. The owner wants a glance at the notch to answer "what is running, where, and does anything need me?".

## Goals

1. **Project pills in the island.** Each Claude Code project with a live session becomes a pill.
   - **Claude only** (no other agent set up, see "Claude only" below): the open island's right panel lists the project pills instead of agent pills. The big card on the left shows the selected project (its cat, its session count, its last step, its app, how long ago), with the project's running subagents as the small kitten heads.
   - **With other agents** (Codex, Antigravity, Gemini CLI or any other agent set up): today's two panels stay exactly as they ship. The Claude Code card gains an expand control: a click opens a section under the two panels with Claude's project pills and the selected project's running subagents; a second click folds it. Expanding and folding animate both ways with the island's existing spring.
2. **The Projects screen.** A new island view, opened from a folder icon in the island's top bar (beside home, chat and +), that lists every project and, under each, every session: role (main, or side with its worktree name), state dot, last step, app, how long ago; subagents as smaller indented rows under their session.
3. **One click on a session or a project brings its app forward** (the existing jump: the Claude app by bundle ID, the terminal or VS Code as today).
4. **A count that says at a glance that something waits for the owner** (an approval or a question) in any project.
5. **Polish (owner, 2026-10-17, all four):**
   - **A cat for each project.** Each project gets its own coat, chosen once and remembered by the project's name, the way each agent has its own coat (`agentCatFor`). The owner can change a project's cat in Settings → Cat → Display, in the existing agent list's style.
   - **Waiting comes first.** A project with an approval or a question moves to the first pill, its dot turns amber and pulses, and the compact notch shows a small amber count (like the shelf's badge: compact only, fades with the wing, never wakes a hidden island).
   - **Pin a project.** A right-click on a project pill offers Pin / Unpin. A pinned project stays in the big card even when another project was active more recently. One pin at a time.
   - **Hover to peek.** Resting the pointer on a project pill for 0.4 s shows a small popover with its sessions and subagents (the Projects screen's rows for that project only), without opening the screen. It closes when the pointer leaves.
6. No keys, no sign-in, no network: everything comes from the hook events NotchMeow already receives. The owner is signed in through the Claude app; NotchMeow never talks to Anthropic for this.
7. The Mac first, then the Windows/Linux twin with the same rules (Mac is primary).

## Non-goals

- Starting a session, sending a prompt or a message to a session, or stopping one.
- Reading Claude Code's own files: no transcript (`transcript_path` stays unread), nothing under `~/.claude`, no Claude Code credentials. So the chat's own title (as the Claude app shows it) is not available: a project is named by its folder.
- History: sessions are not kept across a restart of NotchMeow, and no log of past sessions is built.
- Answering approvals from the island for sessions whose prompts stay in their own app (the Claude App sessions keep their prompts in the Claude app, owner 2026-10-17). Sessions that already get notch cards keep them exactly as today.
- Changing how existing pills, cards or Settings look, beyond the added expand control, the added top-bar icon and the added Settings rows.

## Anti-goals (a failure even if it works)

- Any CPU while the island is hidden (the 0 % rule), or a new poll or timer that runs without the island open. The pulse of a waiting dot runs only while the island is open; the compact badge is still.
- Showing or storing a full path, a prompt, assistant text or a command: views show the project's folder name, a side session's worktree name, the role and the island's existing step words only.
- Breaking or renaming any pill ID, cat ID, display mode ID, action ID, the hook relay, or the existing kitten and approval behaviour.
- A list that lies: a session that ended must leave the list, and a project with no live session must not linger.
- The with-other-agents layout changing at all while the Claude panel is folded.

## Constraints

- Swift 6, SwiftUI + AppKit, no new dependency; the Windows/Linux twin in TypeScript with Rust only where the platform needs it.
- Builds on the routing fix merged on 2026-10-17 (5d8c9dd8): Claude Code sessions from the Claude desktop app reach the Claude Code pill (`integration_claude`), with their prompts left in the app.
- House pattern for shared rules: a small contract (pure rules, a Python `reference.py`, generated JSON fixtures, a test script), then the Mac and Windows/Linux ports replay the fixtures (as the cat, shelf, sidekick and link contracts do).
- New views follow the existing island style; nothing that ships is restyled.

## What the owner decided

- Projects come from Claude Code as used in the Claude desktop app (and, the same way, from a terminal or VS Code), with no API keys (2026-10-17).
- Per project: the main session (the orchestrator chat), the side sessions and the subagents (2026-10-17).
- Claude only → project pills in place of agent pills; with other agents → today's two panels plus an expandable Claude panel with the project pills and the subagents, opening and closing both ways (2026-10-17, "exactly I was thinking").
- Both the in-island pills (option 1) and the separate Projects screen (option 2), combined (2026-10-17).
- All four polish items: a cat for each project, waiting comes first, pin a project, hover to peek (2026-10-17).

## The rules (the contract)

Pure functions over the hook events the island already parses (`session_id`, `cwd`, `hook_event_name`, `agent_id`, `agent_type`, `nm_agent`, `term_program`, `bundle_id`, `tool_name`):

1. **Project of a session.** From the session's first `cwd`:
   - a path containing `/.claude/worktrees/<name>` belongs to the repository at the part before `/.claude/worktrees/`; the session is a **side session** named `<name>`;
   - otherwise the project is the `cwd` itself (a session started in a subfolder of a repository is matched to an already-known project whose root is a prefix of its `cwd`; the longest root wins);
   - no file is read to find a repository (no `.git` read): a worktree outside `/.claude/worktrees/` is its own project, with a main session.
   - **the home folder never groups other sessions** (owner, 2026-10-17): a session whose `cwd` is the user's home folder is its own project, displayed as "Home", and it is never a root that later sessions under the home folder join. The home folder is given to the rules by the app (never guessed from a path).
   - The project's display name is its root folder's name, through the existing `aliasProjectName`; two projects with the same folder name show the parent folder too ("notchmeow — GitHub Local Repos").
2. **Role.** A session whose `cwd` is the project root (or under it, not in a worktree) is a **main** session; two main sessions in one folder are "main" and "main · 2" in start order. A worktree session is a **side** session.
3. **State of a session**, from its last events: `working` (UserPromptSubmit or any tool event, until Stop, StopFailure, Interrupt or SessionEnd; quiet for 10 min shows `idle`), `approval` (a PermissionRequest is open), `question` (an ask-user-question or a question notification is open), `finished` (Stop; shown for 5.2 s like the pill, then `idle`), `idle`. An open approval or question outranks everything.
4. **Waiting for sessions whose prompts stay in their app** (Claude App): NotchMeow answers their PermissionRequest with `ask` at once, as today; the session is marked `approval`, labelled "Waiting in Claude App", and counted. The mark ends at the session's next PreToolUse, PostToolUse, PostToolUseFailure, UserPromptSubmit, Stop, StopFailure, Interrupt or SessionEnd, or after 10 min, so it can never stick. Same for a question notification.
   **Waiting for sessions with notch cards** (terminal, VS Code; owner, 2026-10-17): the mark ends when the card is answered, at the same events as above, or after 120 s, the hook's own wait for a PermissionRequest (`timeout: 120` in the installed hooks), after which Claude Code shows its own prompt. A question's card (the `--ask` hook, `timeout: 130`) ends after 130 s.
5. **State of a project**: the most urgent of its sessions' states (approval/question, then working, then finished, then idle).
6. **Subagents** of a session are its kittens (the existing `agent_id` tracking: type, state, at most 8 per session). They leave on Stop and SessionEnd.
7. **Lifetime.** A session enters on its first event and leaves on SessionEnd. A session with no event for 30 min is shown as idle and dimmed; with none for 2 h it leaves (no SessionEnd arrives when a window is just closed). A project leaves when its last session leaves; its pin goes with it.
8. **Order of the pills.** Projects with something waiting first, then by most recent activity. Inside a project: main sessions, then side sessions by most recent activity.
9. **The big card's project**: the pinned project if it is live; else the one the owner last clicked, while live; else the most recently active. A waiting project does not take the big card by itself (it moves to the first pill and pulses).
10. **The waiting count**: the number of sessions in `approval` or `question` across all projects.
11. **Claude only**: true when no agent other than Claude Code is set up, that is when Settings → Active pills declares no agent pill other than `integration_claude`, and no session of another agent has sent an event since NotchMeow started. The island switches layout only while it is folded, never while the owner is looking at it.
12. **A project's cat**: the stored choice for that project's display name if any (cleaned like the agents' coats: an unknown ID falls back), else a coat picked the same way `agentCatFor` picks a new agent's, from the project's display name, so it is the same on every launch.

Time-based states (`finished` for 5.2 s, the 10 min and 30 min ages, the 2 h removal) are computed when the island reads the registry, from event times: no timer. While the island is open, one one-shot timer per minute refreshes the "… ago" labels and stops when it folds.

The contract's fixtures cover: a worktree path and its repo, a subfolder session, two repos whose names collide, a path with spaces, a session that moves `cwd`, SessionEnd, the 10 min, 30 min and 2 h ages, an open approval outranking a running tool, the Claude App waiting mark and its end, kittens attached to the right session, the order with a waiting project, the big card's project with and without a pin, Claude only with and without another agent, and a project's cat with and without a stored choice.

## The island (Mac)

- **Claude only, open island**: left, the big card for the big card's project (rule 9), in the existing card's layout (cat, title = project name and "· N sessions", step line, app and age); right, the project pills in the existing pill grid's style (the project's cat with its state dot, name, session count). A click on a pill makes it the big card's project; a click on the big card brings its app forward; the right-click menu has Pin / Unpin.
- **With other agents, open island**: exactly today's two panels while folded, plus a chevron on the Claude Code card and, under its title, "N projects" and "M waiting" when any. A click on the chevron (or the card's empty area) expands: a section under the two panels with the project pills in a row of three columns and the selected project's running subagents (kitten head and type). A second click folds it. The expanded state is remembered while NotchMeow runs.
- **Compact notch**: unchanged, except the small amber waiting count (polish) on the right of the notch when the count is above 0, in both layouts.
- **The Projects screen**: the folder icon in the top bar opens it; one section per project (cat, name, waiting count), its sessions as rows, subagents indented; a session row's click brings its app forward; a row whose session owns the notch's open card (terminal or VS Code) shows that card instead. Empty state: "No Claude Code session is running." It is also opened by a menu-bar item "Projects (N)" and an optional global shortcut with a new frozen action ID `projects` (off by default, like `shelf`).
- **Hover to peek**: on a project pill (in either layout), after 0.4 s, a popover with that project's rows from the Projects screen.
- **Display modes**: in One cat, A cat for each agent and Two cats modes, the compact notch's cats keep their current rules; the project cats appear only in the open island, the Projects screen and the peek.
- It is in every build (Debug, Release, App Store); whatever the hooks deliver is shown.

## Settings (Mac)

- Settings → Cat → Display gains "Project cats": one row per live project with its cat and a coat picker, in the style of the existing agent list (`CatAgentList.swift`). The stored key is per project display name (`cat.projectCat.<name>`), never a path.

## Windows/Linux

The same contract, ported to TypeScript in `windows/src/` and replayed against the same fixtures; the island's two layouts, the expand control, the top-bar icon, the Projects screen, the peek and the compact count in the Windows island's style; the jump uses the existing `openRoute` (the Claude app on Windows, none on Linux). No global shortcut (as for the shelf). The project cats are stored in the `cat` block of `settings.json` (cleaned by `cleanCatBlock` and its Rust twin, kept at every save).

## Left to the builder

- The registry's data structure (keyed by `session_id`), as long as the existing pill and kitten behaviour stays exactly as it is.
- The exact constants (the values above are the defaults), the row and pill layout within the existing style, and the dev panel / render scripts (a `render-projects.sh` picture of each layout, the screen and the peek at each checkpoint, without launching the app, as the other views have).
- The split into a contract plan and the app plans.

## Calls made by the main session (2026-10-17; the owner may override any)

1. **Paths.** A live session's full `cwd` is held in memory only, to group sessions into projects. It is never shown, logged or persisted. On Windows/Linux the page already receives `cwd` in each hook event (`windows/src/island/hooks.ts`), so the rules run there, in memory, like the sidekick's. A leak pin, like `test-sidekick-leak.sh`, proves the views, the log and the stored settings never carry a `/`-path. Both apps already receive `cwd` on every Claude Code event (Mac `HookServer`, Windows `hooks.ts`), and a Claude App session's tool events arrive even though its permission requests are answered `ask`.
2. **A registry and contract of its own**, in the sidekick's pattern: `shared/projects-core.js` (pure, Node-tested), its fixtures generated from it, a Swift port on the Mac and a generated TypeScript copy on Windows/Linux. The sidekick contract is not modified.
3. **The jump** brings the app forward, and nothing finer: the Claude app is not asked for a particular chat.
4. **Last step** is the island's existing step line (`SessionStepText`), held in memory only and cut to the row's width.
5. **Pins and the expanded state live in memory**, not in settings: a restart forgets them. Project cats are stored (by display name), because a cat that changes on every launch would be confusing.
6. **"Claude only" is decided from what is set up and seen** (rule 11), not a new setting: Active pills plus events seen since launch. An agent whose hooks are installed but that has sent nothing does not count. The project pills and the big card reuse the existing pill cell and big card views with project data; the layout grid is the one that ships.
7. **Waiting is a count, never an alert.** A waiting project moves first, pulses while the island is open, and adds to the compact count. It does not open the island, hold it, or call the desktop cat. Sessions with notch cards keep their existing alerts unchanged.
8. **When the big card's project ends** (or the pinned one's last session ends), the card moves to the next project by rule 9 at once, so the list never shows an ended project; a pin goes with its project.
9. **A project cat's key** is the folder name as `aliasProjectName` gives it, without the parent suffix used to tell colliding names apart. Two projects with the same folder name share a cat.
10. **Settings → Project cats** lists the live projects and every project with a stored cat; a stored one has a Reset button that removes its key.
11. **The `projects` action ID is final** and the shortcut is off by default, like `shelf`.
