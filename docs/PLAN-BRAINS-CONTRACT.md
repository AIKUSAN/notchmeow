# Plan brains contract (F3a2-0)

The contract for the two plan brains, Codex (`codex exec`) and OpenCode (`opencode serve`), as the F3a2-0 plan
(`docs/superpowers/plans/2026-10-28-f3a2-0-plan-brains-contract.md`) sets it. The app plans (F3a2-mac, F3a2-tauri)
port the Python reference in `tests/fixtures/ai/` and replay the same fixtures; where an app and a fixture disagree,
the reference decides. Nothing here runs the real CLIs: tests run the fakes only.

This file has the Codex part. The OpenCode part is added by Task 8 of the plan.

## Codex

### Files

- `tests/fixtures/ai/codex/recorded/`: the owner's scrubbed real runs (Task 0A), the source of truth for shapes;
  `FINDINGS.md` in it records each step and its verdict.
- `tests/fixtures/ai/codex/expected-args.json`: the argv, the working folder and the image folder per level, the model
  rule and the shell-off set.
- `tests/fixtures/ai/codex/expected-env.json`: the environment a run keeps, and the names it drops.
- `tests/fixtures/ai/codex/locator-cases.json`: where `codex` is looked for, per platform. The login shell's answer is its last non-empty line, and it counts only as an absolute path to an installed file named exactly `codex`.
- `tests/fixtures/ai/codex/versions.json`: the `--version` parse and the minimum (0.165.0, the version recorded).
- `tests/fixtures/ai/codex/login-status.json`: `codex login status` exit and words, and the state each gives. Only the exit code decides the state; the mode is read from stdout and stderr together. The 2026-10-29 probe of codex-cli 0.165.0 found "Not logged in" on stderr with stdout empty (exit 1); the signed-in line on stderr is expected but not yet probed. The locator runs the login check with `2>&1`.
- `tests/fixtures/ai/codex/levels.json`: per level, whether it is offered, whether its argv carries the shell-off set,
  and the item types a turn may carry; the unrecorded item types.
- `tests/fixtures/ai/codex/expected-parse.json`: transcript plus level gives text, steps, finish, error and engine.
- `tests/fixtures/ai/codex/transcripts/*.jsonl`: what the fake replays. Byte copies of `recorded/` where a recording
  exists, otherwise hand-written from shapes a recording has.
- `tests/fixtures/ai/codex/copy.json`, `labels.json`: the words of each failure, and the model and level chips.
- `tests/fixtures/ai/codex/fake_codex.py`: the stand-in `codex`. It records what it was run with and replays a
  transcript; it never reads a login.
- `tests/fixtures/ai/codex/reference.py`: the Python model of the contract. Its checks are the ones the apps replay.
- `scripts/test-codex-contract.sh`: runs `reference.py`.

The fake-codex checks (the sentinel's mode and atime, and the refused write) need a non-root user. As root, a folder at
mode 0500 still takes a write, so the "refused write" check fails. As root, a read of the mode-000 sentinel also
succeeds, so only the static `auth.json` guard stands between a fake and that read. The user CI runs the contract as
is not checked here.
- Not created: `hook-routing.json` (0A step 9 was not run, so no pill was recorded) and `app-server/` (Task 4, not run).

### The levels

Codex runs with `--sandbox read-only` on every level (the base argv). The shell-off set (FINDINGS step 13) is added
on each offered level. Stopping a turn is detection, not a barrier: under a read-only sandbox a command may already
have run when its `item.started` arrives.

| Level | Offered | Shell-off argv | Working folder (cwd) | Items a turn may carry |
|---|---|---|---|---|
| `chat` | yes (owner, 2026-10-28) | yes | `/support/NotchMeow/codex-chat`, mode 0500 | `agent_message`, `reasoning`*, `todo_list`* |
| `none` (quick actions) | yes (plan decision: the override was verified) | yes | the same chat folder | the same as `chat` |
| `read` | no (owner ruling R1) | no | not used | kept in `levels.json` as not offered, so its cases fail closed; it carries `command_execution` |
| `agent` | not offered (see Decisions) | no | not used | absent |

\* `reasoning` and `todo_list` are not in any recording. They are unverified (see Probe results).

- The shell-off set is `--disable shell_tool --disable unified_exec --disable apps --disable browser_use
  --disable computer_use --disable in_app_browser -c web_search="disabled"`.
- The working folder is the process's working directory and never appears in argv. Images go to
  `/support/NotchMeow/codex-images/`, mode 0700, a folder apart from the chat folder, emptied after the turn.
- The model name must match `^[A-Za-z0-9][A-Za-z0-9._:-]{0,63}$`. Anything else, or a name that a flag could read,
  is `nm_bad_model`. An unknown level, `read` and `agent` are `nm_level_unavailable`.
- Item types: a `command_execution` step keeps its `command`, cut to 200 Unicode scalars. A `web_search` item is
  outside every offered level. Any other item type, known or unknown, is `nm_level_exceeded`. An `error` item is a
  note, not a failure (FINDINGS, "Also seen").

### What it never keeps

- Nothing of a prompt, a reply, a command or a path is logged. The prompt goes to Codex on stdin only.
- A step keeps its kind, one whitelisted field (`command` or `query`) cut to 200 Unicode scalars, and its state.
- The sign-in check keeps the state and the mode (`chatgpt`, `api_key` or `unknown`), read by fixed substrings. The
  rest of the status output is dropped.
- `~/.codex/auth.json` is never opened or read by any code in this contract. The fixture check plants a mode-000
  `auth.json` under a fake `HOME` and only stats it, to check that its mode is still 000 and, where the file system
  records it, that its atime is unchanged. `reference.py`'s audit hook fails any open of an `auth.json` in its own
  process. A fake child is a separate process the hook cannot see, so `fake_codex.py` is held by a static check that
  its text never names `auth.json`. The static check is a literal match: a fake that built the name at run time would
  pass it, so the fake's review is the net for that.
- The thread id is read for the engine record. Turns are stateless, so it is never sent back to Codex.
- The `OPENAI_*` names are dropped from the environment (below).

### Decisions

Each is a "(plan decision)" in the plan's Global Constraints that concerns Codex, with what happened to it.

- **Web search is off on Codex, at every offered level.** The plan said "no `--search` flag". FINDINGS step 10 showed
  web search is on by default, so `--search` is not the switch. The switch is `-c web_search="disabled"` in the
  shell-off set (step 13). A `web_search` item stays `nm_level_exceeded`.
- **Stopping is detection, not a barrier.** `chat` and `none` rely on stopping the turn quickly on a disallowed item.
  The shell-off set is what keeps the tool from running at all.
- **`none` exists**, because step 13 verified the shell-off override: `none` is the base argv plus the shell-off set.
- **Codex Agent: not offered (1.1 or pending owner Task 0B).** Task 4 did not run. The `agent` case stays
  `nm_level_unavailable`.
- **Turns are stateless.** `--ephemeral` is kept (step 8: 201 sessions before and after, no session saved). There is no
  `exec resume`. The conversation is carried in the prompt on stdin. The folder is the cwd, never argv.
- **Environment.** Codex drops `OPENAI_API_KEY`, `CODEX_API_KEY`, `OPENAI_BASE_URL`, `OPENAI_ORG_ID`,
  `OPENAI_PROJECT_ID` and every name starting `OPENAI_`. The names are unverified: every recorded run ran with them
  unset, so which of them Codex reads was not tested. `CODEX_HOME` is kept, because the user's login lives there.
  Names compare without regard to case on Windows.
- **Credentials are never read**, and the fixture-files check plants the sentinel (see What it never keeps).
- **Fail closed.** These end the turn with `nm_level_exceeded` and drop its text and steps: an item type or tool not
  in the level's set, a web search, an MCP call, a file change at a level without it, and any item that started but
  never completed. A run that fails before it does anything keeps its own failure (signed out, plan limit, too old,
  crash).
- **Frozen.** The level keys, the error codes in `copy.json` and the provider IDs are contract values: added to, never
  renamed.

Owner rulings made while the recordings were read (2026-10-28): R1, read is not offered (Codex Read-only moves to 1.1,
because `--sandbox read-only` reads the whole disk and the shell-off set leaves no way to read files, FINDINGS step 7
and 13). R2, `none` is offered with the shell-off set. R3, the chat argv is the base plus the shell-off set exactly as
recorded in step 13, with no `--enable skip_host_skill_discovery`. R4, Task 4 is not run. R5, the argv keeps the plan's
order, with the prompt as `-` last. R6, an `item.completed` of type `error` is a note; a top-level `error` or a
`turn.failed` is a failure; a line that is not JSON is skipped.

Checkpoint 1 rulings (2026-10-28, after the signed-out exec run, step 14). CP1-A: a top-level `error` whose message
starts with `Reconnecting...` (`retryNotes` in `levels.json`) is a note, not a failure. The turn's failure is its
`turn.failed`, or a later top-level `error` that is not a retry note. CP1-B: a `turn.failed` (or a top-level `error`)
whose message contains `401 Unauthorized` is `nm_codex_signed_out`, with the words of `copy.json`. The same state as
`codex login status` "Not logged in", exit 1. Plan-limit wording stays unverified.

### Probe results

Task 0A, run by the owner in the owner's Terminal, Codex CLI 0.165.0 (Homebrew cask), signed in with ChatGPT.
Every run used `codex exec --json --ephemeral --skip-git-repo-check --sandbox read-only --ignore-user-config
--ignore-rules -` with the prompt on stdin, and the OpenAI variables unset.

| Step | Recording | Result | Verdict |
|---|---|---|---|
| 1 | `v.txt` | `codex-cli 0.165.0` | Passed. The minimum is 0.165.0. |
| 2 | `login-in.txt`, `login-out.txt` | Signed in: "Logged in using ChatGPT", exit 0. Empty `CODEX_HOME`: "Not logged in", exit 1. | Passed for the status command. The exec run's signed-out error is step 14. |
| 3 | `exec-help.txt`, `help.txt` | Every flag the plan uses exists. `-` (or no prompt) reads stdin. | Passed. |
| 4 | `chat.jsonl` | Exit 0; `thread.started`, `turn.started`, `agent_message`, `turn.completed`. | Passed. Also an `error` item that is a skills-budget warning: a note. |
| 5 | `chat-wants-command.jsonl` | Two `command_execution` items in a chmod-500 folder. | Failed as a Chat-only design: `--sandbox read-only` does not stop commands. The shell-off set is required. |
| 6 | `read.jsonl`, `read-write-attempt.jsonl` | The summary worked; the write was refused ("filesystem is read-only"); no `made.txt`. | Passed for the write. Read-only is not shipped (owner). |
| 7 | `read-outside.jsonl` | `secret-line` read from a file outside the folder. | Failed: the read-only sandbox reads the whole disk. Read-only moves to 1.1. |
| 8 | `sessions-before.txt`, `sessions-after.txt` | 201 and 201. | Passed: `--ephemeral` saves no session. |
| 9 | none | Not run: no Debug NotchMeow was running. | Not verified. No `hook-routing.json`. |
| 10 | `chat-wants-web.jsonl` | Three `web_search` items without `--search`. | Failed as a design: web search is on by default. Off through the shell-off set. |
| 11 | `bad-model.jsonl`, `bad-model.err`, `image.jsonl` | Bad model: exit 1, `error` and `turn.failed` ("model is not supported when using Codex with a ChatGPT account"). Image: exit 0, correct answer. | Passed. The bad model maps to `nm_codex_bad_model`. The `--image` form is settled (below, 2026-10-29). |
| 12 | every file in `recorded/` | Scrubbed. Scans: no home path (`/Users/`, `/home/`), no email, no key-shaped string. | Passed, with notes below. |
| 13 | `shell-off-*.jsonl`, `shell-off-flags.txt` | With the shell-off set: no `command_execution`, no `web_search`, `secret-line` not read; the model says it has no tool. | Passed. The set is the one that ships. |
| 14 | `signed-out-exec.jsonl` | Real signed-out `codex exec`: empty `CODEX_HOME`, the shipping Chat-only flags (base and shell-off set), exit 1. `Reconnecting... k/5` top-level `error` lines come first (the websocket, then HTTPS), then a top-level `error` and `turn.failed`, both "401 Unauthorized". | Passed. The `turn.failed` maps to `nm_codex_signed_out` (CP1-B). The retry lines are notes (CP1-A). |
| 0B | none | Not run by the owner (`codex app-server`, Task 0B). | Codex Agent: not offered (1.1 or pending owner Task 0B). |

Notes on step 12:

- The plan's literal grep matched substrings only: the user name (from `$USER`) inside other words, `sk-` inside
  `disk-full-read-access` in the help files, and `@keyframes` in a web page's CSS. None is a secret.
- `__KEY__` placeholders stand in for long key-shaped strings in two recordings: 22 in `chat-wants-web.jsonl` (web
  result URL segments) and 7 in `signed-out-exec.jsonl` (request ids). The scrubber cannot tell what they were. The
  owner should look at the raw runs and say whether anything of the account was in them. The 27 that were in
  `shell-off-wants-command.jsonl` sat in the 403 page that Checkpoint 1 re-scrubbed.
- The scrubber's UUID-prefix rule also matched the key `thread_id`, so `thread.started` reads
  `{"type":"thread.started","__ID_1__":"__ID_2__"}`. The fake writes the key back as `thread_id`.

Step 13 re-record: the set was re-run the same day without `--enable skip_host_skill_discovery`, the exact set that
ships. Same result, and only the skills-budget note remains (FINDINGS step 13). The recorded flags are in
`recorded/shell-off-flags.txt`.

A non-JSON line is in two recordings: `image.jsonl` begins "Reading prompt from stdin...", and
`shell-off-wants-command.jsonl` has an rmcp `ERROR` line with an HTTP 403 page. Both are byte copies, kept as recorded,
and the parser skips such lines. `signed-out-exec.jsonl` has seven tracing lines of the same kind (its `ERROR` lines
from the websocket). Those are byte copies, kept as recorded, and the parser skips them.

Re-scrub (owner-directed, 2026-10-28, Checkpoint 1): the 403 HTML page in `shell-off-wants-command.jsonl` was replaced by
the one-line marker `<stderr: rmcp worker quit, HTTP 403 HTML page elided>`, and the byte copy in `transcripts/` was
made again. The page carried challenge tokens, and the parser skips the line either way. FINDINGS, "Also seen", now
names the right file.

Controller rulings from Task 2 that concern this document:

- **Signed-out words, in part verified.** `nm_codex_signed_out` is matched on a `turn.failed` or a top-level `error`
  containing "401 Unauthorized" (verified: step 14). It is also matched on stderr "Not logged in", which is still
  unverified as an exec line: that text came from the sign-in status command (`login-out.txt`). Any other stderr text is
  `nm_codex_crashed`, which may give the wrong label.
- **Plan-limit wording is unverified.** The recorded run's message is "You've hit your usage limit for this plan."; the
  copy says "Your OpenAI plan's limit was reached." It is marked unverified in `copy.json`. A reset time, when one is
  present, is shown in the viewer's locale.
- **`reasoning` and `todo_list` were never recorded.** They are in the `chat` and `none` sets in `levels.json` without a
  recording, so a turn carrying one is accepted, and its shape is unknown. Record one before release.
- **`unrecordedTypes` has no source URL.** `file_change`, `mcp_tool_call` and `future_tool` are in `levels.json`
  `unrecordedTypes` with `"url": "not found"`. Their sources are named by file or by the plan, not by a link. The
  `future_tool` line is hand-written on purpose, for the fail-closed rule.
- **Bare NaN and Infinity, Swift-only (F3a2-mac controller ruling, 2026-10-29):** a stdout line that Python's `json.loads` accepts but Apple's `JSONSerialization` rejects (bare `NaN` or `Infinity`) is skipped by the Swift parser like any non-JSON line; serde cannot emit such a line and the shell-off flags are the primary barrier, so this Swift-only divergence is accepted.
- **Closed by F3a2-mac Task 1 (2026-10-29):** the signed-out exec case is renamed (its retry notes also say 401), and two negative cases pin the retry-note prefix and the exact `401 Unauthorized` substring.
- **Thread id and usage, stated order-free (2026-10-29):** the thread id is `thread_id` when it is a string; else the value of the one key besides `type`, when there is exactly one and it is a string; else null. Usage keeps only its integer values (a bool is not one), and is null when it is absent or not an object. Two edge cases pin this: `thread-two-ids.jsonl` (two keys besides `type`, so no id; named in `levels.json` `unrecordedEvents`) and `usage-kinds.jsonl` (a float and a bool dropped).

Open checks (owner, before Checkpoint 1):

- **`--image` form (settled, 2026-10-29).** A probe of codex-cli 0.165.0 (an empty signed-out CODEX_HOME, no
  credentials, no model reached) found that `codex exec --image a.png -` makes the CLI read the final `-` as a second
  image path, and a junk note, "Codex could not read the local image at `-`", enters the turn. Two images with the same
  ending do the same. `--image=<path>` for each picture, with `-` still last, builds a clean turn: the image part, then
  the prompt from stdin, nothing else. The argv is therefore one `--image=<path>` per picture, `-` last (the argv cases
  in `expected-args.json` and `reference.py`; the fake refuses the bare form).
- The signed-out exec run is recorded (step 14). Its 401 words are verified; the stderr "Not logged in" line is not.
- The plan-limit wording and the `reasoning` and `todo_list` recordings (T2 ruling above).
- Which `OPENAI_*` names Codex reads (Environment, above).

### Release re-check

Before each release, re-read OpenAI's Terms of Use and https://learn.chatgpt.com/docs/non-interactive-mode, and
Anthropic's legal page for OpenCode. Pull the row if they forbid it (owner, 2026-10-28). There is no release checklist
file in the repo yet; this section is that item until one exists.

### Changing it

Add cases, never rename a code. A recording is never edited: a new run is added beside it, and its transcript is a
byte copy of it. One exception, owner-directed: the 403 HTML line of `shell-off-wants-command.jsonl` was re-scrubbed to a
marker (Probe results, 2026-10-28). Any other scrub of a raw run needs the owner's yes first. A hand-written transcript uses only shapes a recording has, or a named exception in `reference.py`.

### Mac port (F3a2-mac)

The Mac runs the rules above in `NotchBuddy/Sources/App/AI/Core/Codex*.swift` (the file map is in `CLAUDE.md`). Only an explicit OpenAI plan choice reaches it.

- The provider ID is `codexPlan` (frozen). Chat turns run at `chat`. Quick actions run at `none`, and a quick Explain's follow-ups run at `chat`. Both levels build the same argv (`CodexCommand.arguments`).
- The folders sit under `<Application Support>/NotchMeow/` (the `/support/` above). `codex-chat` is the working folder, set to 0500 after each check and read back: a folder that is not exactly 0500 ends the turn as `nm_codex_crashed`. `codex-images/<turn>/` (0700, files 0600) holds the pictures, passed as `--image=<path>` each, and is removed when the turn ends. Once per process, before the first turn writes a picture, every folder left under `codex-images/` is removed (a Quit or a crash mid-turn leaves one); a turn that comes while that sweep runs waits for it.
- A known too-old or signed-out Codex (the last status check) fails at once, as `nm_codex_old` or `nm_codex_signed_out`, before anything is written or launched. A program not found, or an unknown state, is still tried.
- The prompt goes to stdin as `CodexPrompt` builds it: the instructions under "Instructions from NotchMeow, the app this chat runs in (not words of the user):", then "Earlier in this chat (already answered):" when there is more than one message, then "The user's new message:". The `--image` form is settled above (2026-10-29).
- `nm_codex_signed_out` shows its detail, "Open your terminal and run `codex login`. NotchMeow opens nothing.", and no button.
- No model is sent. The picker has one row, "OpenAI's default model".
