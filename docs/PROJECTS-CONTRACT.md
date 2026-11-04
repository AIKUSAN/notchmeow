# The Projects contract (sub-project P-0)

The Projects view (designed, not yet built) groups the Claude Code sessions on this computer by the project they work in: one pill per project, its main and side sessions and their subagents under it, and a plain word for what each one is doing (working, waiting for an approval or a question, finished, idle). Its brain is a set of plain rules. This document is the contract those rules keep, so the Mac app, the Windows and Linux app and the tests agree. The design is `docs/superpowers/specs/2026-10-17-projects-view-design.md`; the step that shows a session waiting in its host app (call A) is `docs/superpowers/specs/2026-10-17-focus-awareness-design.md`.

**`shared/projects-core.js` decides.** It is pure (no clock, no files, no network, no randomness: every rule is given the time it needs) and is the one source of truth, as `shared/sidekick-core.js` is for the sidekick. `node scripts/gen-projects-fixtures.mjs` writes `tests/fixtures/projects/*.json` from it, and both apps replay those files in their own language. If an app and a fixture disagree, the core is right and the app is wrong.

## Files

| File | What it is |
|---|---|
| `shared/projects-core.js` | The rules. Loads in Node (`require`) and in a page (`globalThis.ProjectsCore`). Copies four small pieces of `cat-core.js` rather than loading it (see the last decision below). |
| `scripts/gen-projects-fixtures.mjs` | Writes the fixtures. Every case lists its input and, typed by hand beside it, the answer it must get: the generator stops with "the core says X, the case says Y" if the core disagrees. `--check` fails on drift; `--out DIR` writes elsewhere. |
| `tests/fixtures/projects/*.json` | The eight fixture files (below). Generated: never edit by hand. |
| `tests/projects/*.test.mjs` | The rules' own tests (`node --test`): `paths`, `events`, `registry`, `view`, `cats`, `print` (the tables print) and `gen` (the generator: `--out` with no value is a usage error; `problemsOf` catches a stray `.json` file, a missing or different file, and fewer than 8 files). `cats` pins every copy of `cat-core.js` to its original. |
| `scripts/test-projects-contract.sh` | Runs the tests, the no-drift check and the determinism check (two generator runs write identical bytes). CI runs it. |
| `scripts/print-projects-tables.mjs` | Prints the rules as tables for a person to read (the owner's checkpoint). |

Fixtures: `project-cases.json` (`projectOf`, `projectNames`, `rolesOf`, `sessionOrder`, the project id), `event-cases.json` (`projectEventFrom`), `registry-cases.json` (`registryApply`, `registryPrune`, the view at a time, the presentation, and `caps`: the caps and the clock's edges, replayed on the registry itself), `state-cases.json` (`sessionStateAt`, `projectStateOf`, `agoOf`), `order-cases.json` (`projectOrder`, `bigCardOf`, `waitingCount`), `claude-only-cases.json` (`claudeOnly`, `islandLayout`), `cat-cases.json` (`projectCatOf`, `cleanProjectCats`), `step-cases.json` (`cleanStep`, and a view whose steps map has `__proto__` and `constructor` keys).

Ports: Swift `Projects*.swift` (P-mac) and the generated TypeScript copy `windows/src/projects/core.generated.ts` (P-tauri, `npm run check:projects`) replay the same files. The fixtures hold whole numbers, text, booleans, null, lists and objects only; each port adds its own tests for a non-finite number.

## What never leaves memory, and what is never kept

- The registry holds a session's full `cwd`, and the home folder the app gave it (`registry.home`), **in memory only**. The event's own `cwd` lives in the event until it is applied, and is never kept or shown either. Neither is shown, logged or stored. The home folder's own project shows only `Home`.
- Events and the registry hold no prompt, no `transcript_path`, no tool's input or output, no notification's message and no assistant text.
- Nothing the view returns for display carries a `/` or a `\`: names, labels, steps, types and notes. A step's word that holds a path keeps its last part (`cleanStep`).
- A project's `id` is `p-` plus the FNV-1a of its root, never the root. It is 32 bits and an opaque key: never displayed, and never persisted (DR2, DR7).
- The only thing stored is a project's cat, keyed by its `catKey` (the folder name through the alias table, without the collision suffix: spec call 9). It is kept as `cat.projectCat.<catKey>` on the Mac and as `projectCats` in the `cat` block on Windows and Linux.
- Pins, the last click and the expanded state live in app memory (spec call 5).

## The rules

Every object is returned with its keys in the order written. Each export below names the fixture that pins it.

### Constants

| Name | Value | Meaning |
|---|---|---|
| `VERSION` | `1` | The registry's version. |
| `QUIET_IDLE_MS` | `600000` (10 min) | A working session quiet this long shows `idle`. |
| `DIM_MS` | `1800000` (30 min) | A session quiet this long is dimmed. |
| `REMOVE_MS` | `7200000` (2 h) | A session quiet this long leaves the registry and the view. |
| `FINISHED_MS` | `5200` | `finished` shows this long after a stop. |
| `APP_WAIT_MS` | `600000` (10 min) | A Claude App wait, or a stepped-back wait, ends by itself after this. |
| `CARD_APPROVAL_MS` | `120000` (120 s) | A notch card's approval ends by itself (the PermissionRequest hook's `timeout: 120`). |
| `CARD_QUESTION_MS` | `130000` (130 s) | A notch card's question ends by itself (the `--ask` hook's `timeout: 130`). |
| `PEEK_DWELL_MS` | `400` | The peek opens after the pointer rests this long. |
| `AGO_TICK_MS` | `60000` | The "… ago" labels refresh once a minute while the island is open. |
| `SUBAGENTS_MAX` | `8` | Subagents kept per session. |
| `SESSIONS_MAX` | `64` | Sessions kept in the registry. |
| `NAME_MAX` | `60` | Code points in a name, a host or a cat key. |
| `STEP_MAX` | `80` | Code points in a step. |
| `PROJECT_CATS_MAX` | `256` | Stored project cats. |
| `CWD_MAX_BYTES` | `4096` | A `cwd` longer than this in UTF-8 bytes reads as none. |
| `PENDING_MAX` | `16` | Open asks kept per session (the newest). |
| `APP_WAIT_LABEL` | `'Waiting in Claude App'` | The label of a Claude App wait (and of a wait with no host). |
| `HOME_NAME` | `'Home'` | The name of the home folder's project. |
| `STATES` | `['approval','question','working','finished','idle']` | The state words, most urgent first. |
| `CAT_IDS` | the 16 cat IDs in cat-core's order | Frozen: stored in settings. |
| `PROJECT_ALIASES` | `notch-buddy`, `notchbuddy`, `notch_buddy` → `Notch Buddy` | Folder names shown as a product name (lower-case keys). |

A boundary is inclusive on the later side: at exactly 10 min the session is `idle`; at exactly 5200 ms it is no longer `finished`; at exactly 120 s a card's approval is no longer open (130 s for a question); at exactly 30 min it is dim; at exactly 2 h it is gone.

### `fnv1a(s)`  (`cats`, `project-cases.json`)

FNV-1a 32 over the UTF-8 bytes, as 8 lower-case hex digits. The same function as `sidekick-core.js`.

### `normPath(cwd)`  (`project-cases.json`)

A path as one text: `\` becomes `/`, repeated and a trailing `/` fold (the root `/` stays), a drive letter is upper-cased. `''` when the input is not a non-empty text. Letter case is otherwise kept.

### `projectOf(cwd, roots, home) -> {root, worktree} | null`  (`project-cases.json`)

Which project a session's folder belongs to. `worktree` is `''` for a repository's own folder. A worktree belongs to the repository before its path (the first `/.claude/worktrees/`); its name is the segment after the last one. A folder inside a worktree is still that worktree. Otherwise the session joins the longest of `roots` that holds its folder, matched by whole segments (`/Users/sam/Code/notchmeow-old` is not inside `/Users/sam/Code/notchmeow`); `/` and a bare drive match only themselves. With no root it becomes a root of its own. The home folder is its own project and is never a root another session joins.

### `projectNames(roots, home) -> [{root, name, catKey}]`  (`project-cases.json`)

The name of each project root, in input order. The `catKey` is the folder name through the alias table (`Notch Buddy` for `notchbuddy`); a root with no folder name is `Session`; the home folder is `Home`. Two roots with one folder name show their parent folder (`notchmeow — Code`, `notchmeow — Old`). Two labels that still match get a number (` · 2`, ` · 3`) in input order; a label already taken, a numbered one included, is skipped, so every name is distinct (`site — p`, `site — p · 2`, then `site — p · 2 · 2` for a root named `site — p · 2`). Names lose control and invisible characters and are cut at 60 code points, the cut falling on the folder part first so the parent part and the number survive. When the parent part alone is too long, it is cut and the number kept (the folder part is then gone: a known limit).

### `rolesOf(sessions) -> [{id, role, label}]`  (`project-cases.json`)

A session in no worktree (a worktree that is not text, or none, counts as none) is `main`, labelled `main`, `main · 2`, … by start order (`seq`). A session in a worktree is `side`, labelled by the worktree's name; two sessions in one worktree are `name` and `name · 2`.

### `sessionOrder(rows) -> ids`  (`project-cases.json`)

The mains first, by start; then the sides, most recent activity first; a tie is broken by id.

### `projectEventFrom(payload, now, waitIn) -> event | null`  (`event-cases.json`)

Turns one hook payload into the event the registry takes: `{at, agent, kind, sessionId, cwd, subagentId, subagentType, fromApp, termProgram, bundleId, waitIn, stepped}` (`waitIn` and `stepped` are the last keys). It returns `null` for a Claude Code event with no session id or an unknown event name. Another agent's event (any valid `nm_agent` other than `claude` and `claude-desktop`, or Cursor's bundle) is `kind: 'other'` with every other field empty. Ids are cut at 128 code points. A `cwd` longer than `CWD_MAX_BYTES` (4096) UTF-8 bytes reads as `''` (counted in bytes, not code points). A subagent type is cut at 64 code points (a hard cut, no `…`) with `/` and `\` turned into `-`; the view cleans it the same way again (DR3).

The event names:

| Hook event | `kind` |
|---|---|
| `SessionStart` | `start` |
| `UserPromptSubmit` | `prompt` |
| `PreToolUse` | `preTool`, or `question` when the tool is `AskUserQuestion` |
| `PostToolUse`, `PostToolUseFailure` | `tool` |
| `PermissionRequest` | `approval`, or `question` when the tool is `AskUserQuestion` |
| `Notification` | `note`, or `question` when its message ends with `?` |
| `Stop` | `stop` |
| `StopFailure`, `Interrupt` | `halt` |
| `SubagentStart` | `subStart` |
| `SubagentStop` | `subStop` |
| `SessionEnd` | `end` |

`claude-desktop` is Claude Code with `fromApp` set. `waitIn` (the optional third argument) is the host a session steps back to, as text: a name cut to 32 code points, `''` when absent, blank or not text. `stepped` is true when the raw `waitIn` is a non-blank text, even when its host cleans to nothing (SF6: an invisible-only or a slash-only host is still a stepped-back wait, labelled `Waiting in Claude App`). Both are `''` and false for a Claude App event and for `kind: 'other'`.

### `emptyRegistry(home) -> {version, home, sessions, otherAgentSeen, nextSeq}`  (`registry-cases.json`)

An empty registry for the user's home folder (normalized; `''` when none is given). The app makes its registry once, with its user's home folder.

### `registryApply(registry, event) -> registry`  (`registry-cases.json`)

A new registry; the input is never changed. It prunes first (2 h quiet sessions go). An event from another agent only sets `otherAgentSeen`. An event for a new session with no usable `cwd` is ignored, and so is an `end` for a session not yet seen; the one exception is a first-seen approval or question, filed under the home project when the home folder is known, so it is still shown and counted waiting (SF3). A non-finite event time reads as the registry's newest `lastAt` (0 when empty), so nothing is pruned or aged by it (SF4). A session that cannot be copied (a cycle, a BigInt) is dropped alone and the rest survive (SF1). A session takes its project from its first folder and keeps it. The rules by event:

- `prompt`: working; pending asks are cleared.
- `preTool`, `tool`: working; the pending ask of that asker (the main agent, or one subagent) ends. Parallel tools of one asker end the same entry (one ask at most per asker); another asker's ask stays open. This is the spec's per-asker rule (SF5), not 'every ask of the session'.
- `approval`, `question`: working; the asker's pending ask is replaced. An ask whose raw `waitIn` is a non-blank text (`stepped`) is a stepped-back wait: `inApp` is true, so it ends at `APP_WAIT_MS` and never at a card's wait. A Claude App event is `inApp` too. A session keeps its newest `PENDING_MAX` (16) open asks: a 17th pushed drops the oldest.
- `stop`: finished (`finishedAt` set); pending asks and subagents cleared.
- `halt`: idle (`StopFailure` and `Interrupt` end work as `idle`, not `finished`); pending asks and subagents cleared.
- `subStart`: a subagent is added (at most 8; the oldest start goes) or its type is kept up to date.
- `subStop`: that subagent and its ask go.
- `end`: the session leaves.

A session's pending entry is `{by, kind, at, inApp, waitIn}` (`by` is `''` for the main agent, else the subagent's id). An ask ends only its own asker's pending entries, except the `prompt`, `stop`, `halt` and `end` events, which end them all.

### `registryPrune(registry, now) -> registry`  (`registry-cases.json`)

A new registry without the sessions 2 h quiet at `now`.

### `sessionStateAt(session, now) -> {state, dim, gone, waitingInApp}`  (`state-cases.json`)

A session's state at `now`; the session is not changed. A `now` that is not a number reads as the session's own `lastAt` (SF4): nothing ages, and a waiting session stays waiting. An ask still open wins: `approval` if any open ask is an approval, else `question`. An open ask is one that `liveAsk` counts: an in-app wait lasts `APP_WAIT_MS`, a card's approval `CARD_APPROVAL_MS`, a card's question `CARD_QUESTION_MS`. Otherwise a working session is `working` until 10 min quiet, then `idle`; a finished session is `finished` for 5.2 s after its stop, then `idle`. `dim` is true from 30 min quiet and `gone` from 2 h. `waitingInApp` is true when an open ask is in-app.

### `projectStateOf(states) -> state`  (`state-cases.json`)

The most urgent of the states, in `STATES` order. Unknown words count for nothing; no state at all is `idle`.

### `cleanStep(text) -> text`  (`view.test.mjs`)

A step as the notch shows it: invisible characters become spaces; a word that holds a path keeps its last part (`…` when it has none); at most 80 code points. `''` when the input is not text. Fixture: `step-cases.json` (paths inside a word, `a/`, `/`, `C:\`, 80 and 81 code points, an astral character at the cut, invisible and bidi characters, non-text).

### `waitLabel(host) -> text`  (`view.test.mjs`)

`Waiting in <host>`, the host cleaned as a name (invisible characters, `/` and `\` out, spaces trimmed, at most 60 code points). `APP_WAIT_LABEL` (`Waiting in Claude App`) when the host is blank. It is the one wording for a Claude App wait and for a stepped-back wait (focus awareness, call A).

### `projectsView(registry, now, opts?) -> {projects, waiting, sessionCount, otherAgentSeen}`  (`registry-cases.json`)

The notch's view at `now` (designed, not yet built: the rule is built and tested now, the views come with P-mac and P-tauri). The registry is not changed. `opts.steps` maps a session id to its step text; `opts.projectCats` and `opts.mainCat` pick a project's cat (`projectCatOf`). Sessions that are gone are left out. A `now` that is not a number reads the newest `lastAt` of the registry (SF4). The fields:

- `projects` (in pill order, see `projectOrder`): each `{id, name, catKey, cat, state, dim, waiting, sessionCount, lastAt, agoMin, step, host, sessions}`. `state` is the most urgent of its sessions' states; `dim` is true only when every session is dim; `waiting` counts its sessions in an approval or a question; `step` and `host` are those of its newest session; `agoMin` is whole minutes since `lastAt`.
- Each project's `sessions` (the order of `sessionOrder`): `{id, role, label, state, dim, waitingInApp, note, step, host, lastAt, agoMin, subagents}`. `note` is `waitLabel` of the newest live in-app wait, so a Claude App session reads `Waiting in Claude App` and a stepped-back one reads `Waiting in <host>`.
- Each subagent `{id, type, state}`: `approval` when its live ask is open, else `working`; a subagent with no event for 10 min is not shown.
- `waiting` (top level) is the sum of the projects' `waiting`. `sessionCount` counts the live sessions. `otherAgentSeen` is the registry's flag.
- The big card is not the first project in the list. Its fields are not the card's: `bigCardOf` decides which project the card shows.

Host: `claude-app` for a Claude App session, `vscode` when the terminal program or bundle names VS Code (Cursor's bundle is never VS Code), else `terminal`.

### `projectOrder(projects) -> projects`  (`order-cases.json`)

A new array of the same objects, in pill order: a project that waits (approval or question) first, then the most recently active, then by id.

### `bigCardOf(projects, pinned, clicked) -> {project, pinned, clicked}`  (`order-cases.json`)

The project the big card shows: the pinned one, else the last clicked, each only while that project is still there; else the most recently active (a tie: the first). Waiting does not take the card. The app stores the `pinned` and `clicked` this returns, so a pin goes with its project (DR6). `project`, `pinned` and `clicked` are ids or `null`.

### `waitingCount(projects) -> number`  (`order-cases.json`)

The sessions waiting (an approval or a question) over the projects: a whole number, never below 0.

### `claudeOnly(activePills, otherAgentSeen) -> boolean`  (`claude-only-cases.json`)

False when another agent's pill is declared (any `agent_` pill but `agent_claude-desktop`) or another agent has sent an event; true otherwise. Nothing declared and nothing seen is Claude only.

### `islandLayout(current, claudeOnlyNow, open) -> 'projects' | 'agents'`  (`claude-only-cases.json`)

While the island is open it keeps the layout it has. Folded, it shows `projects` when Claude only and `agents` otherwise. The layout changes only while folded.

### `projectCatOf(catKey, projectCats, mainCat) -> {cat, stored}`  (`cat-cases.json`)

A project's cat: its stored coat, else `pickCat([main], rng(parseInt(fnv1a(catKey), 16)), null)` (the generator is seeded with the hash, DR4), which avoids the Main cat and is the same on every launch while the Main cat is unchanged. A key that is not a valid cat key wears the Main cat (an unknown Main cat falls back to `shrimpy`). The function never stores.

### `cleanProjectCats(raw) -> {catKey: catId}`  (`cat-cases.json`)

The stored project cats, cleaned: a key must be a valid cat key (1 to 60 code points, no `/` or `\`, no invisible character, not `__proto__`, `constructor` or `prototype`) and a value a valid cat ID. Keys come out in UTF-16 code-unit order, at most 256: names past the 256th in that order are dropped without a word (SF9, a known limit). Anything that is not a plain object is `{}`.

## Decisions where the spec was silent

Each is pinned by the case named in brackets.

- A session's root is fixed when it enters. A later session at a parent folder does not merge an earlier subfolder project, and a session never moves project: a session that moves `cwd` stays in its first project. [`registry-cases`, moves cwd]
- A worktree in a worktree: the repository is before the first `/.claude/worktrees/`, the name after the last. [`project-cases`, worktree]
- Prefix matching is by whole segments; `\` is `/`, repeated and trailing `/` fold, a drive letter is upper-cased; letter case is otherwise kept. [`project-cases`]
- Colliding names: the parent folder, then ` · 2`, ` · 3` in first-seen order. Names lose control and invisible characters and are cut at 60 code points; an empty name is `Session`. Ruling (2026-10-17): a collision label keeps its whole suffix (` — parent`, then ` · k`); the folder-name part is cut first so the label fits. [`project-cases`, collision names]
- The home folder (owner, 2026-10-17): its own project `Home`, never a root another session joins; a worktree of a repository at the home folder joins Home. Home is never numbered; another folder named `Home` shows its parent folder, and a root named `Home` with no parent folder shows `Home · 2` while the home project is there. With no home given (empty) the plain rule applies; the apps always give it. [`project-cases`, the home folder]
- Roles: mains are numbered among live sessions in start order (`main`, `main · 2`); two sessions in one worktree are `name`, `name · 2`. [`project-cases`, roles]
- Waiting is kept per asker (the main agent or one subagent). A tool event ends only its own asker's ask; `UserPromptSubmit`, `Stop`, `StopFailure`, `Interrupt` and `SessionEnd` end all of them. An ask also ends by itself (rule 4): after 10 min from the Claude App or from a stepped-back wait; otherwise after 120 s for an approval and 130 s for a question, the installed hooks' own waits. Every non-App question counts as a card's, a question notification included. A subagent whose ask ended so shows `working`. The session then shows what its run says (usually `working` until 10 min quiet). [`state-cases`, `registry-cases`]
- A subagent's question shows its kitten as `approval`. Ruling (2026-10-17): the brief's literal rule; the state of a subagent is `working` or `approval` only, and the owner decides whether a question should get its own word. [`registry-cases`]
- Call A (focus awareness, owner checkpoint 2026-10-17): an approval or a question whose raw `waitIn` is a non-blank text is a stepped-back wait (`stepped`, SF6). It is `inApp`, so it ends at `APP_WAIT_MS`, never at the card's 120 s or 130 s; its row's `note` reads `Waiting in <host>`; the host is cleaned by `waitLabel`. A blank raw text is no host and is not a stepped-back wait (it would otherwise turn a 120 s card wait into a 10 min one). Ruling (2026-10-17): a whitespace-only text is blank. Ruling (SF6): the test is on the raw text, so a non-blank text whose host cleans to nothing is still a stepped-back wait, and its label falls back to `Waiting in Claude App`. [`event-cases`, `view.test`]
- A Claude App wait is always `Waiting in Claude App`. Ruling (2026-10-17): `waitIn` is guarded to `''` for a Claude App event, because the app is the host and a Claude App session never names another. [`event-cases`]
- The Cursor-bundle host exclusion is kept (`hostOf` never reports `vscode` for Cursor's bundle). Ruling (2026-10-17): no hook input reaches it today; it is one defensive condition, and a port fed another way stays right. [`view.test`]
- `StopFailure` and `Interrupt` end work as `idle`, not `finished`. [`state-cases`]
- A Claude event with no session id is ignored, and so is a new session's event with no usable `cwd`, except a first-seen approval or question, which is filed under Home (SF3). Another agent's event (Codex, Cursor, any valid `nm_agent` but `claude` and `claude-desktop`) only sets `otherAgentSeen`. `claude-desktop` is Claude Code with `fromApp`; `agent_claude-desktop` among the active pills (`activeIntegrations`) counts as Claude. [`event-cases`, `claude-only-cases`]
- Caps: 64 sessions (the least recently active goes, a tie to the earlier start); 8 subagents per session (the oldest start goes); ids cut at 128 code points; subagent types at 64 with `/` and `\` turned into `-`. A subagent with no event for 10 min is not shown. [`registry-cases`, `event-cases`]
- A step's word that holds a `/` or `\` is shown as its last component; steps are cut at 80 code points (the view cuts further to the row). [`view.test`]
- A project's cat: the stored coat, else the picked one (see `projectCatOf`). Ruling (2026-10-17): a cat key with a `\` is not a valid cat key, so it is dropped and that project wears the Main cat with no stored choice kept. Backslash folder names are rare on macOS, and a key must never look like a path. [`cat-cases`]
- `projects-core.js` copies `CAT_IDS`, the seeded generator `rng` (cat-core's line 31), the pick of `pickCat` for the case `taken = [main]`, and the agent-pill test of `isAgentPill`; plus `fnv1a` and the invisible-character class from `sidekick-core.js`. It does not load `cat-core.js`, so that a page or the generated TypeScript copy can load it alone. `tests/projects/cats.test.mjs` pins every copy: the same `CAT_IDS`, the same pick as `CatCore.pickCat([main], CatCore.rng(seed), null)` for 300 names by 16 Main cats, the same `fnv1a`, and `SUBAGENTS_MAX` equal to `CatCore.KITTEN_MAX`. Neither `cat-core.js` nor its fixtures change. [`cats`]

## Known limits

- Claude Code started in a parent folder other than the home folder (for example `~/Code`) takes in every later session under it and shows that folder's name. This is rule 1 as written: another parent folder still takes in sessions under it.
- Paths are compared as text. There is no symlink or letter-case folding on Windows beyond the drive letter.
- A session whose window closed without `SessionEnd` stays up to 2 h (dimmed from 30 min).
- Project cats may repeat across projects: two projects can wear one cat (DR5).
- `cleanProjectCats` keeps the first 256 names in UTF-16 code-unit order and drops the rest silently (SF9).
- Ids are 32-bit FNV-1a values: opaque, never displayed, never persisted (DR2, DR7).
- A collision name whose parent part is over 58 code points shows only the cut parent part, the folder name lost (`fitName`, TG8).
- The time-based states move only when the island reads the registry. There is no timer for them (spec); the "… ago" labels refresh once a minute while the island is open.

## Changing it

Change the core and the typed answer beside its case, run `node scripts/gen-projects-fixtures.mjs`, and commit the fixtures with the core. A new state word, role, host or layout may be added; none is renamed. Once an app reads these files, change them only by addition.
