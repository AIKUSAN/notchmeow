# Codex recordings (Task 0A), 2026-10-28

Codex CLI 0.165.0 (Homebrew cask), signed in with ChatGPT. Every run:
`codex exec --json --ephemeral --skip-git-repo-check --sandbox read-only
--ignore-user-config --ignore-rules -` with the prompt on stdin and
`OPENAI_API_KEY`, `CODEX_API_KEY`, `OPENAI_BASE_URL` unset. Files were scrubbed
with `tests/fixtures/ai/scrub_recording.py`.

| Step | File | Result |
|---|---|---|
| 1 | `v.txt` | `codex-cli 0.165.0` |
| 2 | `login-in.txt`, `login-out.txt` | signed in: "Logged in using ChatGPT", exit 0; empty `CODEX_HOME`: "Not logged in", exit 1 |
| 3 | `exec-help.txt`, `help.txt` | every flag the plan uses exists; `-` (or no prompt) reads stdin |
| 4 | `chat.jsonl` | exit 0; `thread.started`, `turn.started`, `agent_message`, `turn.completed` |
| 5 | `chat-wants-command.jsonl` | **2 `command_execution` items** in an empty chmod-500 folder: read-only does not stop commands from running |
| 6 | `read.jsonl`, `read-write-attempt.jsonl` | summary works; the write was refused ("filesystem is read-only"), no `made.txt` |
| 7 | `read-outside.jsonl` | **`secret-line` read** from a file outside the folder (`head -n 1` through `zsh -lc`): the read-only sandbox reads the whole disk |
| 8 | `sessions-before.txt`, `sessions-after.txt` | 201 / 201: `--ephemeral` saved no session |
| 9 | (skipped) | no Debug NotchMeow running |
| 10 | `chat-wants-web.jsonl` | **3 `web_search` items without `--search`**: web search is on by default |
| 11 | `bad-model.jsonl`, `bad-model.err`, `image.jsonl` | bad model: exit 1, `error` + `turn.failed` "not supported when using Codex with a ChatGPT account"; image: exit 0, correct answer |
| 13 | `shell-off-*.jsonl`, `shell-off-flags.txt` | with `--disable shell_tool --disable unified_exec --disable apps --disable browser_use --disable computer_use --disable in_app_browser -c 'web_search="disabled"'` (re-recorded the same day **without** `--enable skip_host_skill_discovery`, the exact set that ships: same result, and only the skills-budget note remains): **no `command_execution`, no `web_search`, `secret-line` not read**; the model says it has no tool |
| 14 | `signed-out-exec.jsonl` | Real signed-out `codex exec`: empty `CODEX_HOME`, the shipping Chat-only flags (base and shell-off set), exit 1. Shows `Reconnecting... k/5` top-level `error` lines (the websocket, then HTTPS), then a top-level `error` and `turn.failed`, both "401 Unauthorized". | The `turn.failed` is the signed-out state (verified). The retry lines are notes, not failures. |

## Also seen

- Every run starts with an `item.completed` of type `error` that is a warning, not a failure ("Exceeded skills context budget … 202 additional skills"). Codex loads the host's skills even with `--ignore-user-config`; `--enable skip_host_skill_discovery` did not stop it and adds its own "under-development feature" warning. A parser must treat `item.completed:error` as a note and only `error` / `turn.failed` as failure.
- One run (`shell-off-wants-command.jsonl`) has a non-JSON stderr line: an rmcp worker quit with HTTP 403 (an HTML error page). It is ChatGPT's connector (chatgpt.com, `/backend-api/product-account-links/mcp`), tried even with `--disable apps` in the shell-off set, so `apps` does not stop it. Parsers must skip non-JSON lines. The page is re-scrubbed to a one-line marker (below).
- Re-scrub (owner-directed, 2026-10-28, Checkpoint 1): the 6,657-character HTML line of `shell-off-wants-command.jsonl` (the 403 page, with Cloudflare challenge tokens in it) is replaced by the one-line marker `<stderr: rmcp worker quit, HTTP 403 HTML page elided>`. Nothing else in the file changed. The plan's "never edit a fixture" rule covers test fixtures; this is a scrub of a raw run, which the owner directed. `transcripts/shell-off-wants-command.jsonl` is a byte copy again.

## What this decides (for Tasks 1-3, to be confirmed by the plan's controller)

- Chat only and Read-only both need the shell-off flag set; `--sandbox read-only` alone is not enough (steps 5, 7, 10).
- Read-only with the shell off has no way to read files at all (13c), so Codex Read-only needs another reading path, or it is the same as Chat only.
- Quick actions (the no-tools level) can run on Codex with the shell-off flag set (Review Focus: re-check per Codex version; fail closed if `init`-like evidence of a tool appears).

## Owner's decision, 2026-10-28

"Use my OpenAI plan" ships at **Chat only** for the relaunch, with the step-13
shell-off and web-off flags. Codex Read-only moves to 1.1, until a way to limit
reading to the chosen folder is found. This narrows the plan's relaunch slice
("Chat only and Read-only") to Chat only.
