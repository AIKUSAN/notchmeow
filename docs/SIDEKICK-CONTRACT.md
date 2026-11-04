# The sidekick contract (sub-project F1-0)

The agent sidekick gives the cats four small useful things: a recap when you come back, a plain line under each permission request, a nudge when an agent looks stuck, and an
answer to "What's Claude doing?". Its brain is a set of plain rules. This document is the contract those rules keep, so the Mac app, the Windows and Linux app and the tests
agree. The design is `docs/superpowers/specs/2026-10-14-agent-sidekick-design.md`.

**`shared/sidekick-core.js` decides.** It is pure (no clock, no files, no network, no randomness: every rule is given the time it needs) and is the one source of truth, as
`design/prototype/cat-core.js` is for the cats. `node scripts/gen-sidekick-fixtures.mjs` writes `tests/fixtures/sidekick/*.json` from it, and both apps replay those files in
their own language. If an app and a fixture disagree, the core is right and the app is wrong.

## Files

| File | What it is |
|---|---|
| `shared/sidekick-core.js` | The rules. Loads in Node (`require`) and in a page (`globalThis.SidekickCore`). |
| `scripts/gen-sidekick-fixtures.mjs` | Writes the fixtures. Every case lists its input and, typed by hand beside it, the answer it must get: the generator stops if the core disagrees. `--check` fails on drift; `--out DIR` writes elsewhere. |
| `tests/fixtures/sidekick/*.json` | The ten fixture files (below). Generated: never edit by hand. |
| `tests/sidekick/*.test.mjs` | The rules' own tests (`node --test`): the fixtures replayed, the pinned thresholds, the leak checks, the fuzzes. |
| `scripts/test-sidekick-contract.sh` | Runs the tests, the no-drift check and the determinism check (two generator runs write identical bytes). CI runs it. |
| `scripts/print-sidekick-tables.mjs` | Prints the rules as tables for a person to read (the owner's checkpoint). |

Ports: Swift `Sidekick*.swift` (tested by `scripts/test-sidekick-*.sh`) and TypeScript `windows/src/sidekick/` (tested by `npm run check:sidekick`) replay the same files; the
Rust twin is the settings cleaner only. The fixtures hold whole numbers, text, booleans and null only (no `NaN`, no `Infinity`, no fractions): each port adds its own tests
for a non-finite number.

## What the sidekick never keeps

The prompt, the assistant's text, `transcript_path`, a tool's output, a command, a full path, a file's content. Events and the ledger hold a **basename**, a **command key**
(a hash) and counts. A name keeps no control or invisible character (bidi overrides included). An event with no `session_id` or `conversation_id` is filed under the session `unknown`, so no session is keyed by a missing id. Every line the rules write holds a basename, a count, an agent's name or a number of minutes, and nothing else. Tests plant a marker in each of those
inputs and assert it never comes out.

## The rules

### `explain(agent, tool, toolInput, cwd, home) -> {risk, reasonId, line, target}`  (`explain-cases.json`)

Says how risky one permission request is. It **labels only**: it never allows, denies or blocks; only the user's click does. `agent` is reserved (every agent is read the same
way). A shell command is split at `&&`, `||`, `;`, `|`, `&` and newlines (respecting quotes), a leading `cd`, `sudo`, `doas`, `env VAR=1`, `VAR=1`, `time`, `command` and
`nohup` are looked through, `bash -c "..."` is read through to two levels, and the request takes the highest risk of its parts (on a tie the earlier reason of the table).
What it can't read safely (an open quote, `$(...)`, backticks, `<(...)`, a here-document, `eval`, a script file, `find -delete`) is `medium` / `unsure`. It never throws.
Paths are resolved against `cwd` with `~`, `$HOME`, `..` and Windows drive letters; "outside the project" means outside `cwd`.

Reasons (`git_history` is first, added by F1-0; the next twelve are the spec's high ones; the order is the tie-break):

| Risk | Reason ID | Line (`{name}` is a basename, at most 60 characters) |
|---|---|---|
| high | `git_history` | Deletes this project's git history. |
| high | `rm_recursive` | Deletes {name} and everything inside it. |
| high | `sudo` | Runs a command with admin rights. |
| high | `pipe_to_shell` | Downloads a script and runs it at once. |
| high | `chmod_recursive` | Changes permissions on {name} and everything inside it. |
| high | `git_force_push` | Overwrites the remote branch history. |
| high | `git_reset_hard` | Throws away local changes. |
| high | `git_clean` | Deletes files git doesn't track. |
| high | `disk_write` | Writes straight to a disk. |
| high | `sql_drop` | Deletes a database table or database. |
| high | `sql_delete_all` | Changes every row in a table. |
| high | `sensitive_file` | Changes {name}, which can hold secrets or settings. |
| high | `write_outside` | Changes {name}, outside this project. |
| medium | `git_push` | Sends commits to a remote. |
| medium | `install` | Installs software. |
| medium | `network_fetch` | Talks to another computer. |
| medium | `container` | Controls containers. |
| medium | `lockfile_ci` | Changes {name}, which affects every build. |
| medium | `reads_secrets` | Reads {name}, which can hold secrets. |
| medium | `mcp_tool` | Uses a tool from an add-on. |
| medium | `unknown_tool` | Uses a tool NotchMeow doesn’t know. |
| medium | `unsure` | Runs a command NotchMeow can't fully read. |
| medium | `outside_project` | Touches {name}, outside this project. |
| medium | `rm_in_project` | Deletes {name} in this project. |
| low | `read_only` | Only reads files. |
| low | `test_build` | Runs the project's own test or build script. |
| low | `edit_in_project` | Edits {name} in this project. |
| low | `web` | Reads a web page. |
| low | `subagent` | Starts a helper agent. |
| low | `local_command` | Does a simple local step. |

**Decisions where the spec was silent** (each is pinned by rows in `explain-cases.json`):
- Four reasons were added to the spec's first table, as the spec allows: `outside_project` and `rm_in_project` (medium), `reads_secrets` (medium, the owner's answer of 2026-10-14) and `local_command` (low). A shell command NotchMeow does not recognise is `unsure`, not a reason of its own.
- `rm -rf .` (the project folder itself) is `rm_recursive`; `rm -r ./build` is `rm_in_project`.
- Deleting `.git` or anything inside it is `git_history` (high), recursive or not: `rm -fr .git`, `rm -rf .git/objects`, `rm .git/config`. `.gitignore` is not `.git`: `rm -rf .gitignore` is `rm_in_project`.
- A `>` or `>>` redirect is a write: into a sensitive file or outside the project it is high (`sensitive_file`, `write_outside`); into `/dev/...` it is `disk_write`; into `/dev/null` it is nothing.
- `.env*` includes `.env.example`; `.claude/settings*.json` and `.git/hooks/` are sensitive; `.ssh`, `.aws` and `.gnupg` are sensitive in any folder, at any depth (`~/.ssh`, `proj/.ssh/x`), not only under the home that the caller passes in.
- **Secret names** (the owner's list, applied literally): a basename that starts or ends with `.env`, or contains `credential`, `secret`, `token` or `passw` (any case), except a source, doc or style file: one whose extension is `ts`, `tsx`, `js`, `jsx`, `mjs`, `cjs`, `py`, `rs`, `go`, `swift`, `kt`, `java`, `rb`, `md`, `txt`, `css`, `scss`, `less` or `html` is plain, unless its name is exactly `credentials` or `secrets` (any extension). So `src/token.ts`, `auth/tokenizer.ts`, `password_reset.ts` and `tokens.css` are plain, while `credentials.json`, `secrets.yml`, `secrets.rs` and `token.json` are secret. `token.yml`, `password.yaml`, `token.toml` and `token.sh` are secret too: config and data formats carry secret values, so they are not exempt. The names `.npmrc`, `.netrc`, `.pypirc`, `.mcp.json`, `.pgpass`, `.yarnrc.yml`, `.gitmodules` and `kubeconfig` (in any folder); any name that starts with `terraform.tfstate` (so `terraform.tfstate.backup`); the extensions `.pem`, `.key`, `.p12`, `.pfx`, `.keystore`, `.jks`, `.p8` and `.tfvars`; the folders `.ssh`, `.aws`, `.gnupg`, `.kube`, `.docker`, `.config/gh` and `secrets` (any file in them, at any depth); and `.claude/hooks/`, `.claude/commands/` and `.githooks/` (any file in them). A read of one is `reads_secrets`, a write is `sensitive_file`.
- A content tool (`Read`, `NotebookRead`, `LS`) with no string path, or an empty one, is `unsure`: there is nothing to read, and it is never low.
- **Reading the contents** of a secrets file is `reads_secrets` (medium), the owner's answer of 2026-10-14: the Read tool on it, or `cat`, `grep`, `head` and the like on it; writes and edits stay `sensitive_file` (high), and listing it (`ls ~/.ssh`) is not a read.
- `git push --force-with-lease` is `git_force_push` (high), as `--force` is; `git push origin +main` is a force push too.
- `psql`, `mysql`, `sqlite3` and the like are read for `DROP` and for `DELETE` / `UPDATE` / `TRUNCATE` with no `WHERE`; any other statement through them is `unsure`.
- Codex: `tool_input.command` may be a list like `["bash","-lc","ls"]`, and `apply_patch` names its files in `*** Add/Update/Delete File:` lines. Gemini's `run_shell_command` and `write_file`, and PowerShell's `Remove-Item -Recurse`, `Get-*`, are read as their Claude Code counterparts. Other PowerShell cmdlets are `unsure`.

### `eventFrom(payload, now, opts) -> event | null`  (`hook-cases.json`, `cases`)

Turns a hook payload into the event the ledger takes. `now` is the time the app received it (ms). `opts.codex` is false in the App Store build. It accepts the names the
relays send and the agents' own (`BeforeTool`, `AfterTool`, `BeforeAgent`, `AfterAgent`, `PreInvocation`, `PostInvocation`, `startup`, `exit`). An event it doesn't know, a payload
that is not an object and a time that is not a number give `null`.

An event is `{at, agentId, sessionId, kind, name, tool, target, file, key, ok, project, subagentId}`. `kind` is one of `sessionStart`, `prompt`, `preTool`, `question`, `tool`, `failure`,
`approvalAsked`, `approvalAnswered`, `stop`, `stopFailure`, `subagentStart`, `subagentStop`, `sessionEnd`, `notification`. `agentId` is the pill: a valid `nm_agent`
(lower case, digits and hyphens, at most 24, and not `claude`) is `agent_<name>`, Codex is `agent_codex`, Cursor's bundle ID is `agent_cursor`, anything else is
`integration_claude`. A question (`AskUserQuestion`) is `question`, not an approval. `target` is the first file's basename, or the **command key** (the loop rule's step). `file` is the first file's basename or empty: the one name the recap may show. `project` is the basename of `cwd`. A tool name, a session id and a subagent id are kept to 128 code points.
The app makes the one event that is not a hook: `approvalAnsweredEvent(agentId, sessionId, now)`, for the user's click.

**The command key** is `tool#` plus the FNV-1a (32 bits, 8 lower-case hex digits) of the canonical JSON of the tool input: keys sorted, no spaces, a command's whitespace
folded and trimmed. Only the hash is stored. It needs valid Unicode; the fixtures' keys are ASCII.

**Where the payload shapes come from.** Each case says `source`: `repo` is an event the app already sends (its scenarios and QA brief), `docs` is the agent's documentation, written
down before a real session was captured (`PostToolUseFailure`, `StopFailure`, `Notification`, `SubagentStop`, and all of Codex, Gemini and Antigravity). Replace a `docs`
payload with a captured one when there is one. The Windows relay drops `tool_response` and `transcript_path` and cuts strings at 2000 bytes: a Windows-shaped case is included.

### `ledgerApply(ledger, event) -> ledger`  (`hook-cases.json`, `sequences`)

One small record per session, keyed `agentId|sessionId`, memory only: `{key, agentId, sessionId, startedAt, lastEventAt, endedAt, state, last, project, ring, pendingApprovalAt,
pendingKey, subagents, nudgedAt}`. `ring` keeps the last 40 entries `{at, kind, tool, target, file, key, ok}` (`key` is the command key of a call; kinds `tool`, `failure`, `approvalAsked`, `approvalAnswered`, `stop`,
`stopFailure`, `subagentStart`, `subagentStop`). `state` uses the cat's words (idle, thinking, working, searching, approval, question, finished, error); a search tool is
searching. `last` is the kind of the last event; `subagents` maps an alive helper's id to its start (the spec's `subagentsAlive` is its size: `aliveSubagents(session)`). A
session ends at `SessionEnd` plus 30 minutes, or 12 hours after its last event if it never ended (`ledgerPrune`); at most 8 are kept, a finished one going first, the oldest
first. A request waits in `pendingApprovalAt` until the same step finishes (the same command key), the turn ends or the user answers. The ledger given is never changed.

### `stuckStep(ledger, now, ctx) -> {nudge, nextAt}`  (`stuck-cases.json`)

At most one nudge, and the earliest future deadline of the waiting and quiet rules for the one-shot timer (null when nothing is live: the clock then isn't set). `ctx` is
`{ratelimit, away, cardShown, muted}`; `platform` is not read here (`nudgeText` reads it). `muted` is an array of the nudge kinds the user muted (see below). Kinds, tried in this order: `stuck.loop` (the same tool and key 4 times in the last 8 calls, within 10 minutes, no successful
edit or write after the first of them), `stuck.errors` (3 failures in a row within 10 minutes, Claude Code only), `stuck.waiting` (a request unanswered for 60 s whose card
is not on screen; its words change in place once the platform's give-up time has passed (`mac` at 115 s, `windows` and `linux` at 110 s, any other value is the Mac; `nudgeText` takes the `platform`), `stuck.silent` (5 minutes after a finished step, a prompt or a
subagent's stop, 15 minutes after a step that began and never ended; never while a helper is under 10 minutes old). A session is nudged once (`markNudged`); nothing is said
while the user is away or in the rate-limit state. `nudgeText` gives the fixed words. The thresholds are in the fixture so a port can compare its own.

**Muted kinds.** `ctx.muted` lists the nudge kinds the user muted (`stuck.loop`, `stuck.errors`, `stuck.waiting`, `stuck.silent`). `stuckStep` skips them when it chooses the nudge, so the next-ranked kind that is due fires for the same session, and a muted waiting or quiet deadline is left out of `nextAt`, so the clock never wakes for a note that cannot show. Without this, a muted `stuck.loop` kept being picked first, the app dropped it, never marked the session nudged, and the same loop was picked again on the next call: a muted loop (or errors) starved the quiet (and waiting) nudge of that session for as long as the loop held. Anything in `muted` that is not one of the four kinds (unknown names, other types, `recap`), duplicates and a `muted` that is not an array are ignored, and a missing or empty `muted` is exactly the behaviour without it. The app still drops a muted note defensively when the gate refuses it; that is a second line, no longer the only one.

**The caller calls again.** `nextAt` is null while the user is away and while the agent is rate-limited (no nudge is given then), and the waiting deadline is left out while its card is on screen. The caller must call `stuckStep` again when the away or rate-limit state ends or the card hides; that call gives the nudge then.

### `recapOf(snapshot)`, `statusOf(snapshot, agent)`, `matchStatusQuestion(text)`  (`recap-cases.json`, `status-cases.json`)

`recapOf({awaySince, now, sessions})` is `{lines, facts}` or null: null when the user was away under 2 minutes or no ring entry is at or after `awaySince`. One line per agent
(sessions of one agent merge), the agent that spoke last first, at most 3, then `+N more`. A line is "While you were away, {Agent} in {project} ran {n} steps (1 error, 2
approvals asked), edited a, b and c, and finished." with at most 3 file names then "and k more", "40 or more steps" when the ring was full, and a tail of `finished`, `is waiting
for your OK`, `stopped on an error`, `is waiting for your answer`, `is still working` or `has been quiet for {n} minutes`. `facts` is the same in numbers and names
(`agent, agentId, project, steps, stepsAtLeast, files, more, errors, approvals, end, quietMinutes`): the only thing the local voice may be given.

`statusOf({now, sessions}, agentId?)` uses the same templates over everything the ledger holds ("has run" for "ran"), for the sessions that have not ended (a finished one for 10
minutes), or one agent; "No agent is running right now." / "{Agent} is not running right now." when there are none. It is answered on this machine and never added to a conversation.

`matchStatusQuestion(text)` is `{matched, agentId}`. The whole message must be short (80 characters) and, lower-cased and stripped of punctuation, one of: `status`, `agent status`,
`{agent} status`, `what is / what's {agent} doing`, `what are the / my agents doing`, with an optional "right now" or "now". Anything longer or different is a normal chat message.

### `dismiss`, `muted`, `unmute`, `mute`, `cleanSidekickSettings`  (`dismiss-cases.json`, `settings-cases.json`)

The five kinds are frozen: `recap`, `stuck.loop`, `stuck.errors`, `stuck.waiting`, `stuck.silent`. A click on Not now, OK or x is a dismissal (folding the island unseen isn't: that is
the app's call); two mute a kind; Unmute sets it to 0. The risk badge and the permission line are not a kind and are never muted. `cleanSidekickSettings(raw)` is
`{on, local, dismissals}`: a switch is on unless it is `false`, a count is a whole number from 1 to 2 (anything else is 0), unknown kinds and fields are dropped; cleaning twice is cleaning once.
It is a clean-up of its own: no existing settings fixture changes.

`mute(state, kind)` sets a kind to 2 at once: Settings → AI and chat → Sidekick turns a kind's switch off with it, and on again with `unmute`.

### `presenceStep(state, signal, now)`  (`presence-cases.json`)

`state` is `{reasons, awaySince, wasAway}`. Signals: `lock`, `unlock`, `sleep`, `wake`, `displayOff`, `displayOn`, and `{type: 'idle', seconds}`. The user is away while any reason holds;
idle of 300 s or more adds `idle` (the away began `seconds` ago), a sample under 3 s removes it, samples between change nothing. It returns `{state, back}` where `back` is false or
`{back: true, awaySince, awayMs}`, told once when the last reason lets go.

### `shouldShow(input)`  (`show-cases.json`)

`{show, reason, replace}`. The reasons are tried in this order: `off`, `kind`, `muted`, `away` (a recap waits for the return, and so does a nudge), `ratelimit` (a stuck nudge only), `card` (an approval or a question is in front; for the waiting nudge its own
card must not be on screen), `typing`, `busy` (another note is visible; a recap replaces a nudge nobody has seen), `recent` (a note showed in the last 60 s; not for the recap), `nudged`,
`recapGiven`. A refused note is kept `HOLD_MS` (30 s for a nudge, 2 minutes for a recap) and shown if the gate opens, then dropped silently. The drop's confirmation line is user-started and skips the gate.

### `acceptNicerLine(line, facts)`  (`voice-cases.json`)

Guards the swap of a template for a sentence from a local model: one line, at most 200 characters, no URL, `/`, `\`, backtick or markdown, only numbers from the facts, and the name of an agent of the facts.

## Known limits

The line is a hint. It never blocks, allows or denies anything, and an `unsure` label is shown as `medium`. These are known and are not parsed further; each is `unsure`, `medium` or a rule that over-labels, never silently safe unless it says low.

- A shell keyword hides its command: `if …; then sudo …; fi` and `{ sudo …; }` are `unsure`.
- Options of `time`, `command` and `exec` are not parsed: `time -p sudo ls`, `command -p`, `exec -a name` are `unsure`.
- Options of `env` are not parsed: `env -u HOME rm -rf ~` and `env -S "rm -rf ~"` are `unsure`.
- A variable as the command word is `unsure`: `$RM -rf ~`.
- A wrapper (`timeout`, `nice`, `ionice`, `stdbuf`, `xargs`) with an option outside its table looks only for `sudo`, `doas` and `rm`; `timeout --weird 9 git push --force` is `unsure`, not high.
- The `timeout` duration is read only in the forms `5`, `1.5`, `5s`, `2m`, `1h`, `1d`; anything else is read as the command word.
- The words of a remote or container shell are not read: `ssh h "sudo reboot"` is `network_fetch` and `docker exec c sh -c "rm -rf /"` is `container`, both `medium`.
- A relative path after a `cd` outside the project is read against the project folder: `cd / && rm -rf bin` is `unsure`, not high.
- The words after `-exec` are not read: `find . -exec rm -rf {} +` is `unsure`.
- A bare folder name stays low for the readers that take a file (`cat src`), because the core cannot tell a folder from a file.
- Inline code without a pipe runs whatever it is given: `python3 -c`, `node -e`, `osascript -e` and `awk 'BEGIN{system(…)}'` are `unsure`, not high.
- `su -c "…"` runs a command as another user and is `unsure`.
- `find . -delete` deletes without `rm` and is `unsure`.
- Shell syntax that hides a word is not parsed: `! sudo ls`, `$'sudo' ls` and a here-string `bash <<< "sudo ls"` are `unsure`, not high.
- Piping into `. /dev/stdin` or `source /dev/stdin` is not read as a pipe into a shell.
- A download and a run in two steps (`curl -o x.sh … && sh x.sh`) is `network_fetch` plus `unsure`, not high.
- `git checkout -- .` and other git commands that overwrite files are `unsure`, not high.
- Runners that fetch and run code (`npx`, `bunx`, `uvx`, `go run`) are `unsure`.
- `security find-generic-password -w` prints a secret from the keychain and is `unsure`, not `reads_secrets`.
- An environment variable is not a file: `echo $OPENAI_API_KEY` is low.
- `npm test` and the other build and test commands run a script of the project's `package.json` or Makefile, which the core never reads.
- `git diff` and `git show` with no path operand are low, by the owner's decision: they print committed files, so a secret already committed to the repo may be shown.
- Commands that publish, delete or stop things are `unsure`, not high: `npm publish`, `cargo publish`, `gh repo delete`, `unlink`, `truncate -s 0`, `kill`, `crontab -r`, `security delete-generic-password`, `terraform destroy`, `reboot`, `git branch -D` and `git stash drop`.
- Project scripts are never read: `./deploy.sh`, `bash clean.sh`, `python3 clean.py` and `npm run deploy` are `unsure`.
- Only `mongosh` is read for SQL-like text; `mongo --eval "db.x.drop()"` is `unsure`.
- A `DELETE` with a `WHERE` that is always true passes the check: `sqlite3 db "DELETE FROM t WHERE 1=1"` is `unsure`, not high.
- PowerShell download and run is not read as a pipe into a shell: `irm https://x | iex` and `Invoke-Expression (irm https://x)` are `unsure`, not high.
- A command word built by the shell is not read: `rm${IFS}-rf${IFS}~` is `unsure`, not high.
- PowerShell and cmd aliases of a recursive delete are not read: `rd -Recurse ~`, `ri -Recurse ~`, `rmdir C:\x /s` and `del /s` are `unsure`, not high.
- A write named by a URL is not read: `curl -O https://x/.zshrc` is `network_fetch` (medium), not `sensitive_file`.
- A piped awk is not read as code: `curl x | awk 'BEGIN{system("id")}'` is `network_fetch` (medium), not high.
- A symlink in the project that points to a secrets file is low, because the pure core reads no file system and does not resolve symlinks (`ln -s ~/.ssh/id_rsa key.txt`, then `cat key.txt`). The same holds for a symlink to a folder outside the project, written through.
- A brace list under a recursive delete (`rm -rf {dist,build}`) is high though its names are plain: an over-label by design, as are the globs above.
- `git push --mirror` and `git push origin :main` (which deletes the remote branch) are a plain `git_push` (medium), not `git_force_push`: the owner's decision.
- A shell command over 20,000 characters is `unsure` (medium), not read: the wrapper skips shift their word list one word at a time, which is quadratic on long lists (800 KB took 7 s). Upgrade: index-based skips.

## Changing it

Only new names and new files: `tests/fixtures/cat/`, `tests/fixtures/ai/`, the shelf's fixtures and `design/prototype/cat-core.js` stay byte for byte (`node scripts/check-fixtures-additive.mjs <base>` and `git diff --quiet <base> -- ...`).
The five dismissal kinds and the reason IDs are frozen like the cat and pill IDs: a reason may be added, none is renamed. After changing the core, run `node scripts/gen-sidekick-fixtures.mjs` and commit the fixtures with it.
