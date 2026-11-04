# F3a2-0 Plan Brains Contract Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

## Relaunch fit (read first)

**Owner's decision, 2026-10-28:** for 2026-11-13, only Codex on the Mac at Chat only and Read-only (the Codex half of this plan, then F3a2-mac's Codex slice). OpenCode, Codex Agent and the Windows/Linux side move to 1.1. The owner's Task 0A Codex recordings are done (2026-10-28, `tests/fixtures/ai/codex/recorded/FINDINGS.md`). **Narrowed the same day (owner):** Codex ships at Chat only, with the shell and web search switched off; Codex Read-only moves to 1.1, because `--sandbox read-only` reads the whole disk and the shell-off set leaves no way to read files.

The relaunch is on **2026-11-13** and the showcase on **2026-11-09**. Today is 2026-10-28, so there are 12 days to the showcase and 16 to the relaunch. The estimates below are calibrated from git history. E3's contract, Mac and Windows/Linux halves were committed in about two days (2026-10-06 to 10-07). F3a, a larger sub-project with owner checkpoints, took six calendar days from plan to the Tauri merge (2026-10-22 to 10-28). These sizes are agent days plus review. They do not include the owner's time.

| Slice | Size | Blocked on |
|---|---|---|
| F3a2-0 Codex half (Tasks 0A, 1-3) | 1 day | The owner's Task 0A recordings. Nothing in Tasks 2-3 is final without them. |
| F3a2-0 Codex Agent (Task 4, gated) | 0.5 day | Task 0B showing that `codex app-server` hands approvals to the client. |
| F3a2-0 OpenCode half (Tasks 0C, 5-8) | 1.5 days | The owner's Task 0C recordings and the config-override proof. |
| F3a2-mac Codex, Chat only and Read-only | 1.5-2 days | F3a2-0 Codex half. |
| F3a2-mac OpenCode, three levels | 2.5-3 days | F3a2-0 OpenCode half. Hardest part: one local server per level, SSE, cards, preflight. |
| F3a2-tauri Codex | 1.5 days | F3a2-0 Codex half. |
| F3a2-tauri OpenCode | 2.5 days | F3a2-0 OpenCode half. |
| Codex Agent on both apps | 2 days | Task 4 passing. |

**Realistic for the relaunch:** **Codex at Chat only and Read-only on the Mac**, and on Windows/Linux if time allows. This holds only if the owner records Task 0A by about 2026-10-31. That slice is about 3-4 agent days after the recordings, and it competes with the no-tools level (`claude/affectionate-leakey-e549d6`), which also ships on 11-13.
- OpenCode on the Mac is a stretch for 11-13 and is not realistic for the 11-09 showcase.
- OpenCode on Windows/Linux and Codex Agent go to **1.1**.
- The release-checklist terms re-read (owner, 2026-10-28) is owed whichever slice ships.
- Mac-first holds (CLAUDE.md, "macOS is the primary platform").

---

**Goal:** Write the shared, language-neutral contract that both apps will port for the two new plan brains:
- **"Use my OpenAI plan"**: the user's own Codex CLI, run as `codex exec --json`, one ephemeral process per turn.
- **"Use OpenCode"**: the user's own `opencode serve`, started by NotchMeow on 127.0.0.1 with a one-time password and driven over HTTP and SSE.

For each brain the contract has a fixture folder, a fake binary, a `reference.py` that decides disagreements, a test script, and a documentation file. This plan writes no Swift, Rust or TypeScript.

**Architecture:** The shape is copied from E3's `tests/fixtures/ai/claude-code/`:
- JSON fixtures, each with `version`, `note` and `cases`.
- `transcripts/` replayed by a fake.
- A standard-library Python `reference.py` that runs every case and exits non-zero on any mismatch.

Two additions:
1. A `recorded/` folder of scrubbed real runs from the owner's Task 0. `reference.py` checks that every hand-made transcript line uses only event types and field names that appear in some recorded file, so the fakes cannot drift from the real CLIs.
2. A **level table** per brain that names, for each level, the events and tools allowed. Anything else, including anything unknown, stops the turn. This is the fail-closed pattern of the no-tools level spec.

The Codex half (Tasks 0A, 1-4) can merge before the OpenCode half (Tasks 0C, 5-8) is started.

**Tech Stack:**
- Python 3 standard library: `json`, `subprocess`, `http.server`, `threading`, `base64`, `sys.addaudithook`.
- Bash and JSON.
- No new dependency.

**Spec:** `docs/superpowers/specs/2026-10-17-notchmeow-chat-design.md`. Read these parts:
- The owner's answers at the top (2026-10-22 and 2026-10-28).
- "Call 10" ("more plan brains"), with its levels table, sign-in rows, fallbacks and owner's answers 2026-10-17 (1-7).
- "Call 11" ("OpenCode as a brain"), all of it.

Supporting files:
- Terms report: `.claude/archive/f3a2-terms-check-2026-10-28.md`.
- Pattern to mirror, but never depend on: `docs/superpowers/specs/2026-10-28-claude-no-tools-level-design.md`. It exists only on the branch `claude/affectionate-leakey-e549d6` (worktree `.claude/worktrees/affectionate-leakey-e549d6/`), not on `main`.
- E3 contract to copy: `tests/fixtures/ai/claude-code/` and `scripts/test-claude-code.sh`.

**Base:** branch `f3a2-0/plan-brains-contract`, from `main` at `bfc83e52` or later, in its own worktree. Commit this plan file and the spec's uncommitted edit (`git status` shows it modified on `main`) to `main` first, when the owner asks.

## Global Constraints

Every task's requirements include this section. Lines marked **(plan decision)** are choices this plan makes where the spec is silent. Each is repeated in `docs/PLAN-BRAINS-CONTRACT.md`, "Decisions".

- **Credentials are never read.**
  - Nothing in this plan opens, copies, lists or stats `~/.codex/auth.json`, `~/.local/share/opencode/auth.json` or any file in the CLIs' credential folders.
  - `reference.py` installs `sys.addaudithook` and fails if any `open` event names a path whose basename is `auth.json`.
  - The fixture-files check plants an unreadable sentinel `auth.json` (mode `000`) under a fake `HOME` for both CLIs and runs the fakes with that `HOME`.
- **No telemetry, no network** except the fake OpenCode server on 127.0.0.1 inside a test.
- **Nothing of a prompt, a reply, a command or a path is logged.** Steps keep only the whitelisted fields, each cut to 200 Unicode scalars. Recorded files are scrubbed (Task 0, step "Scrub").
- **Tests only ever run the fakes.** The real `codex` and `opencode` run only in Task 0, by the owner, in the owner's own Terminal.
- **Fail closed on anything that could widen a level.** These all end the turn with `{"kind": "bad_request", "code": "nm_level_exceeded"}` and drop its text and steps:
  - an event type, item type or tool name not in that level's allowed set, known or unknown;
  - a permission request at a level with no approvals;
  - a model name that could be read as a flag;
  - a server whose effective permissions the preflight cannot prove.

  A run that fails before it does anything keeps its own failure (signed out, plan limit, too old, crash).
- **Levels.** The keys are those of E3 and the no-tools spec: `none` (quick actions), `chat`, `read`, `agent`.
  - **Codex (plan decision):**
    - Codex Chat only gets no web search: no `--search` flag. A `web_search` item is therefore `nm_level_exceeded` at every level but `agent`. The spec is silent on Codex web search, and this is the narrower choice.
    - **Stopping is detection, not a barrier.** Under a read-only sandbox, a `command_execution` seen on `item.started` may already have run, and its output may already be on its way to OpenAI.
    - So `chat` on Codex relies on stopping the turn quickly, and the doc says so.
    - `none` (quick actions, untrusted text) exists **only if Task 0A step 13 verifies a config override that removes Codex's shell tool** (the override then joins `none`'s argv). Otherwise `none` is `nm_level_unavailable`, and quick actions never run on Codex.
  - **OpenCode:** stopping on a tool part is detection only as well: the tool runs on the server before NotchMeow sees its event. The barrier is the inline permission config, proven by the preflight.
  - **OpenCode:** `chat` allows `webfetch` and `websearch`, because call 11 ties it to the Claude plan's Chat only. `none` allows nothing.
  - **Agent:** OpenCode `agent` ships in this contract. Codex `agent` exists only if Task 0B passes (owner's answer 2, 2026-10-17). If it fails, Codex offers `chat` and `read` and the owner is told.
- **Codex turns are stateless (plan decision).**
  - `--ephemeral` is kept, as the spec says. There is no `exec resume`.
  - NotchMeow carries the conversation in the prompt on stdin, as it does for the API-key brains (`tests/fixtures/ai/history-cases.json`).
  - The folder is the process's working directory and never appears in `argv`, as in E3.
- **OpenCode, one server per (level, folder) (plan decision).**
  - Changing the level or the folder stops the server and starts a new one.
  - The server stops after **600 s** without a turn: one one-shot timer, no polling. It also stops at app quit.
  - It binds `127.0.0.1` only.
  - Its password is 32 random bytes, base64url without padding, new at every start, never logged and never stored.
- **Anthropic in OpenCode is refused** (owner, 2026-10-28).
  - Fixture default: provider `anthropic` is refused outright. Its text is the spec's exact sentence.
  - The narrower rule (refuse only a Pro/Max sign-in) replaces this only if Task 0C finds a server endpoint, never `auth.json`, that tells an API key from a subscription. The refusal table is keyed by provider ID, so a provider can be added later without code changes.
- **Environment (plan decision).**
  - **Codex** drops `OPENAI_API_KEY`, `CODEX_API_KEY`, `OPENAI_BASE_URL`, `OPENAI_ORG_ID`, `OPENAI_PROJECT_ID` and every name starting `OPENAI_`. The names are unverified; Task 0A confirms which ones Codex reads. This keeps the user's own Codex login as the only credential. `CODEX_HOME` is kept, because it is where the user's login lives.
  - **OpenCode** drops the caller's `OPENCODE_SERVER_PASSWORD`, `OPENCODE_SERVER_USERNAME`, `OPENCODE_PERMISSION`, every `OPENCODE_CONFIG*` name, and the provider key variables in `providerKeyVars` (`ANTHROPIC_API_KEY`, `OPENAI_API_KEY`, `GEMINI_API_KEY`, `GOOGLE_API_KEY`, `OPENROUTER_API_KEY`, `GROQ_API_KEY`, `MISTRAL_API_KEY`, `XAI_API_KEY`, `DEEPSEEK_API_KEY`, `GITHUB_TOKEN`). It then sets its own password and inline config.
  - **Consequence, reported to the owner:** a user whose OpenCode provider works only through an environment variable must run `opencode auth login` instead. This follows the spec's "no API key or token in the child's environment".
  - On Windows, names compare without regard to case.
- **Frozen.** The level keys, the error codes in `copy.json` and the provider IDs in the refusal table are contract values: they may be added to, never renamed.
- **Only new files**, except these edits:
  - `.github/workflows/build.yml`: two steps.
  - `CLAUDE.md` and `ARCHITECT.md`: one bullet each.
  - The spec: status lines only.

  `git diff --quiet <base> -- tests/fixtures/ai/claude-code tests/fixtures/ai/*.json tests/fixtures/ai/sse tests/fixtures/ai/reference.py` must pass at the end.
- **Commits:** local only, never pushed, on the plan's branch. End messages with `Co-Authored-By: Claude Haiku 5.5 <noreply@anthropic.com>`, or `Claude Sonnet 5.5` when an `nm-implementer-deep` wrote it.

## SUBAGENT RULES (the controller puts these in each brief)

- Never run the real `codex` or `opencode`. Never install either. Never sign in. Never read `~/.codex`, `~/.local/share/opencode`, `~/.config/opencode` or any `auth.json`.
- Never launch, quit or replace a NotchMeow app.
- Install and download nothing.
- Delete with `trash`, never `rm -rf`. Scratch names use the prefix `f3a20-` in `${TMPDIR:-/tmp}`. A script's own `mktemp` folders in a `trap` are the repo's convention.
- Before every commit, run `git rev-parse --show-toplevel` and `git branch --show-current`. Stop if either is not this worktree and `f3a2-0/plan-brains-contract`.
- Never edit an existing fixture under `tests/fixtures/ai/`.
- If a recorded file contradicts a case this plan types, stop and report. Which one is right is a design question for the controller.
- If a permission prompt denies a command, stop and report it.

## Review Focus

These are the inputs most likely to bite a person, most likely first. Each line names the test that pins it.

1. **A read-only Codex that still reads outside the folder, or writes.** A `command_execution` at `read` such as `cat ~/.ssh/id_rsa`, or a `file_change` at `read`.
   - Expected: `file_change` → `nm_level_exceeded`.
   - Task 0A measures whether the read-only sandbox confines reads to the folder. If it does not, the owner is told before F3a2-mac starts. The contract cannot fix it.
   - Tests: Task 2, "read: a file change stops the turn", and the spike's row in the doc.
2. **A config the user wrote that loosens OpenCode.** A global `opencode.json` with `"permission": {"edit": "allow"}`, a project `.opencode/`, a plugin, an MCP server.
   - Expected: the preflight refuses `chat` and `read` unless the effective config proves every denied tool is `deny`.
   - Tests: Task 6, `preflight-cases.json`, "a looser effective edit is refused" and "a missing key is refused".
3. **A permission request at a level without approvals,** or a tool part the level does not allow.
   - Expected: reply `reject`, never `once` or `always`, then abort, then `nm_level_exceeded`, with no text shown.
   - Tests: Task 6, "chat: a permission request is rejected and stops the turn", "read: a bash part stops the turn".
4. **A turn answered by a refused provider:** an assistant `message.updated` whose `providerID` is `anthropic`, even though NotchMeow asked for another model (the user's default changed).
   - Expected: abort, `nm_provider_refused`, no text.
   - Tests: Task 6, "the answering provider is checked, not only the asked one".
5. **Hostile or odd values that reach argv or a step.** A model named `--sandbox=danger-full-access` or `-c x=y`. A command of 100,000 characters. A step field that is not a string. An SSE event for another session id.
   - Expected: model refused (`nm_bad_model`), field cut to 200, non-string dropped, foreign session ignored.
   - Tests: Task 1, "a model that looks like a flag is refused". Task 2, "a long command is cut to 200". Task 6, "another session's events are ignored".

---

## File Structure

```
tests/fixtures/ai/scrub_recording.py        Task 0 helper: replaces home, user, email, ids in a raw recording
tests/fixtures/ai/codex/
  recorded/*.jsonl, recorded/*.txt          owner's scrubbed real runs (Task 0A/0B); source of truth for shapes
  expected-args.json                        argv and cwd per level, model, image
  expected-env.json                         what a codex run keeps of the environment
  locator-cases.json                        where codex is looked for
  versions.json                             `codex --version` parse and the minimum
  login-status.json                         `codex login status` exit and words → state
  levels.json                               per level: sandbox and allowed item types
  expected-parse.json                       transcript + level → text, steps, finish, error, engine
  transcripts/*.jsonl                       replayed by the fake
  copy.json, labels.json                    words of each failure; the chips
  hook-routing.json                         only if Task 0A shows NotchMeow's own Codex hooks fire for a chat run
  app-server/ (Task 4 only)                 recorded JSON-RPC conversation, expected requests and replies
  fake_codex.py, reference.py
tests/fixtures/ai/opencode/
  recorded/                                 owner's scrubbed `/doc`, SSE runs, `auth list`, banner
  expected-serve.json                       serve argv, env, inline config per level
  expected-env.json, locator-cases.json, versions.json
  banner-cases.json                         serve's stdout → port
  auth-list.json                            `opencode auth list` → state
  providers.json                            the refusal table and its words
  preflight-cases.json                      effective config + level → ok or refuse
  expected-requests.json                    HTTP requests of a turn, abort, permission replies
  events/*.sse, expected-parse.json         SSE replays + level → text, steps, cards, actions, error
  copy.json, labels.json
  fake_opencode.py, reference.py
scripts/test-codex-contract.sh, scripts/test-opencode-contract.sh
docs/PLAN-BRAINS-CONTRACT.md
```

`scripts/test-codex-plan.sh` is reserved by the spec for the Mac half. Do not use that name here.

## Tasks and agents

| Task | Agent | Model, effort |
|---|---|---|
| 0 setup (worktree, scrubber) | `nm-implementer-light` | Haiku 5.5, medium |
| 0A / 0B / 0C recordings | **the owner** | real CLIs, own Terminal |
| 1, 2, 3, 5, 6, 7 | `nm-implementer` | Haiku 5.5, high |
| 4 (gated) | `nm-implementer` | Haiku 5.5, high |
| 8 docs and wiring | `nm-implementer-light` | Haiku 5.5, medium |
| Each task's review | `nm-reviewer` | Haiku 5.5, high |
| Final review (privacy, trigger 4) | `nm-reviewer-deep` | Sonnet 5.5, high |

Coders load `ponytail:ponytail`, `superpowers:test-driven-development` and `superpowers:verification-before-completion`. Reviewers load `ponytail:ponytail-review`.

**Checkpoint 1** comes after Task 4, or after Task 3 if Task 0B failed. The Codex half is complete and can merge on the owner's yes. **Checkpoint 2** comes after Task 8.

## Interface for the app plans (F3a2-mac, F3a2-tauri)

The app plans port these `reference.py` functions one for one and replay the same fixtures. Their names and meanings are fixed here.

**Codex (`tests/fixtures/ai/codex/reference.py`):**
- `build_args(level: str, model: str|None, images: list[str]) -> list[str] | {"error": code}`
- `turn_cwd(level, folder) -> "chatFolder" | "folder"`
- `clean_env(base: dict, platform: str) -> dict`
- `locate(platform, home, env, executables, login_shell) -> (path|None, shim_only: bool, shell_called: bool)`
- `parse_version(text) -> [int,int,int]|None`, `check_version(v, minimum) -> "ok"|"old"|"unknown"`
- `login_state(exit: int|None, stdout: str) -> {"state": "signedIn"|"signedOut"|"unknown", "mode": "chatgpt"|"api_key"|"unknown"|None}`
- `parse(lines: list[str], exit: int, stderr: str, level: str) -> {"engine", "text", "steps", "finish", "error"}`
- `model_chip(mode)`, `level_chip(level, folder)`, `copy_text(code)`

**OpenCode (`tests/fixtures/ai/opencode/reference.py`):**
- `serve_args() -> list[str]`
- `level_config(level) -> dict`
- `serve_env(base, platform, level, password) -> dict`
- `parse_banner(stdout_text) -> int|None`
- `auth_state(exit, stdout) -> {"state": "ready"|"noProvider"|"unknown"|"missing"}`
- `provider_verdict(provider_id) -> {"allowed": bool, "code": str|None}`
- `preflight(effective: dict, level) -> {"ok": bool, "code": str|None}`
- `turn_requests(level, folder_kind, model, parts) -> list[request]`
- `permission_reply(choice: "allowOnce"|"deny") -> dict`
- `parse_events(lines, level, session_id) -> {"engine", "text", "steps", "cards", "actions", "finish", "error"}`
- `model_chip(provider, model)`, `copy_text(code)`

`actions` is the list of HTTP calls the app must make during the turn because of an event: `reject` a permission, then `abort`.

---

## Tasks

### Task 0: Worktree, scrubber, and the owner's recordings

**Files:**
- Create: `tests/fixtures/ai/scrub_recording.py`
- Create: `tests/fixtures/ai/codex/recorded/`, `tests/fixtures/ai/opencode/recorded/`
- Test: `python3 tests/fixtures/ai/scrub_recording.py --self-test`

**Interfaces:**
- Produces: `scrub(text: str, home: str, user: str) -> str`. It replaces, in this order:
  1. the home path (also with `\\` separators) → `__HOME__`;
  2. the user name as a whole word → `__USER__`;
  3. any email → `__EMAIL__`;
  4. every UUID and every `thread_`/`ses_`/`msg_`/`prt_`/`per_`-prefixed id → `__ID_n__`, numbered by first appearance and consistent within one file;
  5. every `http://127.0.0.1:<port>` → `http://127.0.0.1:__PORT__`;
  6. every key-like string matching `sk-[A-Za-z0-9_-]{8,}|gh[pousr]_[A-Za-z0-9]{8,}|eyJ[A-Za-z0-9_-]{10,}|[A-Za-z0-9_-]{32,}` → `__KEY__`. A user's `opencode.json` often holds `provider.*.options.apiKey`, and `GET /config`, `/config/providers` and `/provider` can echo it back;
  7. the hostname and local host name, passed as `--host`, and the git user's full name, passed as `--name` → `__HOST__` and `__NAME__`.
- Produces the CLI: `scrub_recording.py IN OUT --host "$(hostname)" --host "$(scutil --get LocalHostName)" --name "$(git config user.name)"`. Home and user are taken from the environment.

- [ ] **Step 1: Make the worktree.** `git worktree add .claude/worktrees/f3a2-0 -b f3a2-0/plan-brains-contract main`. Then run `bash scripts/test-claude-code.sh && bash scripts/test-ai-contract.sh`. Expected: both pass. This is the baseline.
- [ ] **Step 2: Write the self-test first.** Run `--self-test` on a built-in sample containing `/Users/zoe/x`, `C:\\Users\\zoe\\x`, `zoe@example.com`, `11111111-1111-4111-8111-111111111111` twice, `ses_abc`, `http://127.0.0.1:51234`, `"apiKey":"sk-proj-abcdefghijkl"`, `ghp_abcdefghij12` and the host `zoes-mbp`. It asserts the output is `__HOME__/x`, `__HOME__\\x`, `__EMAIL__`, `__ID_1__` twice, `__ID_2__`, `http://127.0.0.1:__PORT__`, `__KEY__` twice and `__HOST__`, and that `zoe` appears nowhere. Run it and confirm it fails, because `scrub` is not defined yet.
- [ ] **Step 3: Implement `scrub`** with `re` only. Run `--self-test`. Expected: `scrub self-test passed`.
- [ ] **Step 4: Commit** with `test(plan-brains): F3a2-0 the recording scrubber`.
- [ ] **Step 5: Hand the owner the Task 0A and 0C sheets, and 0B step 1 only, then stop.**
  - Tasks 2, 3, 4, 6 and 7 wait for the recordings. Tasks 1 and 5 may start; their spike-dependent values carry `"verified": false`, see those tasks.
  - **Order for 0B:**
    1. The owner runs 0B step 1.
    2. Task 4, Step 1 writes `probe.py` from that output.
    3. Only then does the owner run 0B step 2.

**Conditions for every recorded run (0A and 0C):**
- Run with the contract's stripped variables unset: `env -u OPENAI_API_KEY -u CODEX_API_KEY -u OPENAI_BASE_URL …`, and for OpenCode `-u OPENCODE_CONFIG -u OPENCODE_PERMISSION` plus the `providerKeyVars`.
- Chat-only runs happen in an empty folder made with `chmod 500`, as the apps will.

#### Task 0A (owner, Codex, about 20 minutes, a few plan messages)

First install Codex CLI your usual way (Homebrew or npm) and run `codex login` in your Terminal, choosing "Sign in with ChatGPT". Then run each command in your own Terminal. Every command writes into a new folder `~/f3a2-rec/codex`. **Never paste `~/.codex/auth.json` and never open it.**

Read every output by eye before you hand it over. If one shows an email or an account name, say so; the scrubber removes emails, but tell the main session anyway.

1. `codex --version > v.txt`
2. `codex login status; echo "exit=$?"` → save as `login-in.txt`. Then, in a shell with `CODEX_HOME=$(mktemp -d)`: `codex login status; echo "exit=$?"` → `login-out.txt`. This is the signed-out shape. It does not log you out.
3. `codex exec --help > exec-help.txt` and `codex --help > help.txt`. These are for the flags: `--json`, `--ephemeral`, `--skip-git-repo-check`, `--sandbox`, `--ignore-user-config`, `--ignore-rules`, `--model`, `--image`, and `-` for stdin.
4. Run `mkdir -p ~/f3a2-rec/empty && chmod 500 ~/f3a2-rec/empty && cd ~/f3a2-rec/empty`. Save outputs one level up (`../chat.jsonl` and so on). In that folder run:

   `echo "Say hello in five words." | codex exec --json --ephemeral --skip-git-repo-check --sandbox read-only --ignore-user-config --ignore-rules - > chat.jsonl 2> chat.err; echo "exit=$?"`

   This is Chat only. **Verify:** `exit=0`. A `thread.started` line exists. If `-` is refused, run it again with the prompt piped and no `-`, and say which form worked.
5. The same command with the prompt "List the files here and read README.md." This is a run that wants a command. Save as `chat-wants-command.jsonl`. **Record:** whether a `command_execution` item appears.
6. In a scratch folder `~/f3a2-rec/proj` that holds one `README.md`: the same command with "Summarise README.md." → `read.jsonl`. Then "Create a file named made.txt with the word hi." → `read-write-attempt.jsonl`. **Verify:** `ls ~/f3a2-rec/proj` shows no `made.txt`.
7. Read scope. In `~/f3a2-rec/proj`, run "Print the first line of the file at ~/f3a2-rec/outside.txt" after `echo secret-line > ~/f3a2-rec/outside.txt` → `read-outside.jsonl`. **Record:** whether `secret-line` appears. This decides Review Focus 1.
8. Ephemeral. `ls ~/.codex/sessions | wc -l` before and after step 4. List names only, never open a file. **Record:** whether the count changed.
9. Hooks. NotchMeow's Codex hooks are installed (`~/.codex/hooks.json`, by `HookServer`) and a Debug NotchMeow is running. Run step 4 again. **Record:** whether a Codex pill appears, and if so, which id the island shows. If one appears, also run step 4 without `--ignore-user-config` and record it.
10. A web search. In `empty`, "Search the web for today's weather in Paris." → `chat-wants-web.jsonl`. **Record:** whether a `web_search` item appears without `--search`.
11. A plan limit, a bad model and an image:
    - `--model nonexistent-model-x` → `bad-model.jsonl` and `bad-model.err`.
    - With any small PNG: `--image ~/f3a2-rec/p.png` and "What colour is this?" → `image.jsonl`.
12. Scrub every file with `python3 tests/fixtures/ai/scrub_recording.py IN OUT` and the flags above, writing into `tests/fixtures/ai/codex/recorded/` in the worktree. Then `grep -rlE "$USER|/Users/|/home/|@|sk-|__KEY__" tests/fixtures/ai/codex/recorded`. Expected: nothing. If `__KEY__` shows up, tell the main session which file had it.
13. Shell off. Look in `exec-help.txt` and Codex's config docs for a setting that removes the shell tool, such as a `-c` override or a feature flag. If you find one, run step 5 again with it. **Record:** the exact setting, and whether a `command_execution` item still appears. This decides Codex's `none` level and the quick actions.

#### Task 0B (owner, Codex Agent, optional, about 10 minutes)

1. `codex app-server --help > app-server-help.txt`. Also look for a subcommand that prints its schema or types, such as `codex app-server generate-json-schema --out ~/f3a2-rec/schema` if `--help` lists one, and save its output. Hand both over, then stop until `probe.py` exists.
2. If it exists, a scripted conversation that the main session prepares as `tests/fixtures/ai/codex/app-server/probe.py`. Task 4, Step 1 writes it, and it uses only the standard library. It sends `initialize`, starts a thread in `~/f3a2-rec/proj` with approval policy on-request and sandbox `workspace-write`, sends "Create made.txt with hi", and logs every JSON-RPC message to `app-server.jsonl`. It **declines** the first approval request it sees.
3. **Pass** means: a server→client request for approval arrives with an id, the decline is honoured, and `made.txt` does not exist.
4. Scrub into `codex/app-server/recorded/`.
5. **If it does not pass, Task 4 becomes "write the not-offered row" and Codex Agent waits** (owner's answer 2).

#### Task 0C (owner, OpenCode, about 30 minutes)

Install OpenCode your usual way. Connect one provider that is not Anthropic, such as GitHub Copilot or ChatGPT, with `opencode auth login` in your Terminal. **Never open `~/.local/share/opencode/auth.json`.**

1. `opencode --version > v.txt`. `opencode auth list > auth-list.txt; echo "exit=$?"`. Read it: if it shows any key or token, say so and do not hand it over. `opencode models > models.txt`.
2. Start the server: `OPENCODE_SERVER_PASSWORD=probe-pass opencode serve --hostname 127.0.0.1 --port 0 > banner.txt 2>&1 &`. **Record** the line that names the port. If `--port 0` is refused, use `--port 47123` and say so.
3. With `P=<port>`:
   - `curl -s -u opencode:probe-pass http://127.0.0.1:$P/doc > doc.json`
   - `curl -s -u opencode:probe-pass http://127.0.0.1:$P/config > config.json`
   - `curl -s -u opencode:probe-pass http://127.0.0.1:$P/config/providers > providers.json`
   - `curl -s -u opencode:probe-pass http://127.0.0.1:$P/provider > provider.json`
   - `curl -s -o /dev/null -w "%{http_code}" http://127.0.0.1:$P/doc` (no password) → `noauth.txt`. **Verify:** `401`.
4. A turn. In one Terminal: `curl -sN -u opencode:probe-pass http://127.0.0.1:$P/event > chat.sse`. In another:
   - create a session with `POST /session`, body `{}` (save `session.json`);
   - `POST /session/<id>/prompt_async` with `{"parts":[{"type":"text","text":"Say hello in five words."}]}`;
   - wait for idle, then stop the event stream.
5. A permission. Restart the server with `OPENCODE_CONFIG_CONTENT='{"permission":{"edit":"ask","bash":"ask"}}'`, started in `~/f3a2-rec/proj`.
   - Stream events to `ask.sse` and prompt "Create made.txt with hi".
   - When a permission event arrives, `POST /session/<id>/permissions/<permissionID>` with `{"response":"reject"}`.
   - **Verify:** no `made.txt`.
   - Then repeat, `POST /session/<id>/abort` mid-turn, and save the stream as `abort.sse`.
6. Override proof. This decides `chat` and `read`.
   - `export OPENCODE_CONFIG_DIR=$(mktemp -d)` (empty), and in `~/f3a2-rec/proj` write `opencode.json` with `{"permission":{"edit":"allow","bash":"allow"}}`.
   - Start the server with `OPENCODE_CONFIG_CONTENT='{"permission":{"*":"deny","read":"allow","glob":"allow","grep":"allow","list":"allow"}}'`.
   - Save `GET /config` as `override-config.json`.
   - Prompt "Create made.txt with hi". **Record:** does the edit happen, is it asked, or is it denied? Is the wildcard `*` accepted?
   - Check that the sign-in still works with `OPENCODE_CONFIG_DIR` set, because auth lives in the data folder, not the config folder.
   - **Global config and plugin.** Use a temporary config home (`XDG_CONFIG_HOME=$(mktemp -d)`, leaving `XDG_DATA_HOME` alone so the sign-in stays). In it put:
     - `opencode/opencode.json` with `{"permission":{"edit":"allow"}}`;
     - a tiny plugin in `opencode/plugin/allow.js` that answers every permission with allow. The main session writes it from OpenCode's plugin docs.
   - Run the same prompt with the inline deny config. **Record:**
     - whether the edit happens;
     - whether `GET /config` shows the global rule;
     - whether `GET /config` shows the plugin.
   - **If a plugin can grant a permission without showing in `/config`, the preflight proves nothing,** and Chat only and Read-only are refused for OpenCode (owner, 2026-10-22).
   - Also check that `opencode serve` starts in a `chmod 500` empty folder. **Record** any error.
7. Provider kind. In `provider.json` and `config/providers`, **record** whether any field tells an API key from an OAuth or subscription sign-in for a provider. Look at the JSON only; never open `auth.json`.
8. Stop the server, then scrub everything into `tests/fixtures/ai/opencode/recorded/` as in 0A, step 12.

The main session writes a "Probe results" section into `docs/PLAN-BRAINS-CONTRACT.md` from the owner's answers, as the no-tools spec did. **Owner's call before Task 6:** if step 6 shows a project or user config can loosen a level, Chat only and Read-only are refused for OpenCode (owner's rule, 2026-10-22) and only Agent ships.

---

### Task 1: Codex command line, environment, locator, versions and sign-in state

**Files:**
- Create in `tests/fixtures/ai/codex/`: `expected-args.json`, `expected-env.json`, `locator-cases.json`, `versions.json`, `login-status.json`, `reference.py`
- Create: `scripts/test-codex-contract.sh`
- Modify: `.github/workflows/build.yml`. After the step `- name: AI contract (fixtures + fake server)` / `run: bash scripts/test-ai-contract.sh`, add `- name: Codex plan contract (fake codex, shared fixtures)` / `run: bash scripts/test-codex-contract.sh`.

**Interfaces:**
- Produces: `build_args`, `turn_cwd`, `clean_env`, `locate`, `parse_version`, `check_version`, `login_state`, with the signatures given under "Interface for the app plans", plus `load`, `check`, `CHECKS` and `main` as in `claude-code/reference.py`.

- [ ] **Step 1: Write the fixtures.** Each has `"version": 1`, a `note`, and `"verified": false` until Task 0A's files back it.
  - `expected-args.json`:
    - `"base": ["exec", "--json", "--ephemeral", "--skip-git-repo-check", "--sandbox", "read-only", "--ignore-user-config", "--ignore-rules"]`.
    - The argv is `base`, then `["--model", m]` when a model is given, then `["--image", path]` per image, and ends with `"-"` (prompt on stdin).
    - Cases (at least):
      - chat, no model → `cwd` `"chatFolder"`;
      - read, model `gpt-5.5` → `cwd` `"folder"`;
      - read with two images, whose paths are under `"imageFolder"`. That is `/support/NotchMeow/codex-images/<turn>/`, a folder separate from the 0500 chat folder, mode 0700, emptied after the turn;
      - a model `--sandbox=danger-full-access` → `{"error": "nm_bad_model"}`;
      - a model `-c` → `nm_bad_model`;
      - a model of 65 characters → `nm_bad_model`;
      - level `agent` → `{"error": "nm_level_unavailable"}` (Task 4 replaces this case only if 0B passes);
      - level `none` → `{"error": "nm_level_unavailable"}` unless 0A step 13 verified a shell-off override. In that case `none` is `base` plus that override, and a case pins it;
      - an unknown level `"full"` → `nm_level_unavailable`.
    - The model rule is `^[A-Za-z0-9][A-Za-z0-9._:-]{0,63}$`.
    - `"chatFolder": "/support/NotchMeow/codex-chat"`, `"chatFolderMode": "0500"` (empty and read-only; spec, "the temp folder is made read-only too").
  - `expected-env.json`:
    - `stripped` lists the five names in Global Constraints; `strippedPrefixes` is `["OPENAI_"]`; `kept` includes `"CODEX_HOME"`.
    - Cases: a mac base with all of them plus `PATH` and `HOME` keeps `PATH`, `HOME` and `CODEX_HOME`; a Windows base with `openai_api_key` in lower case drops it.
  - `locator-cases.json`. Order on mac and linux:
    1. `~/.local/bin/codex`
    2. `/opt/homebrew/bin/codex`
    3. `/usr/local/bin/codex`
    4. `~/.npm-global/bin/codex`
    5. `$NPM_CONFIG_PREFIX/bin/codex`
    6. the login shell's `command -v codex`, asked only when nothing earlier exists.

    On Windows: `%USERPROFILE%\.local\bin\codex.exe`, then `codex.exe` on `PATH`. A `codex.cmd` or `codex.ps1` shim is never run (`shimOnly: true`), the same rule and reason as E3 (`claude-code/locator-cases.json` note). The cases mirror E3's: each location wins alone; an earlier one beats a later one; only a shim; nothing found. **Unverified:** the npm package's native binary path on Windows, so Task 0A or the F3a2-tauri spike fills one more case.
  - `versions.json`:
    - `"minimum": null` until Task 0A, then the recorded version.
    - Parse: the first `x.y.z` in the text, as E3.
    - Cases: `"codex-cli 0.98.0"` → `[0,98,0]`, `"nonsense"` → `null`, `""` → `null`.
    - Check: `"ok"`, `"old"`, and `"unknown"` when the minimum is null or the parse fails. Unknown is allowed to run; an unreadable transcript then says so (spec, "Fallbacks").
  - `login-status.json`. Only the exit code decides the state: `0` → `signedIn`, any other number → `signedOut`, `null` (could not run) → `unknown`.
    - `mode` is read from stdout by fixed case-insensitive substrings only: `"chatgpt"` → `chatgpt`, `"api key"` → `api_key`, anything else → `unknown`. Nothing else of stdout is kept.
    - Cases include a stdout containing `__EMAIL__`: it yields only `{"state":"signedIn","mode":"chatgpt"}`.
- [ ] **Step 2: Write `reference.py`'s checks first**: `check_args`, `check_env`, `check_locator`, `check_versions`, `check_login`. Each also asserts "the folder is not in the arguments", as E3's `check_args` does. Add the audit hook:

  `sys.addaudithook(lambda ev, args: ev == "open" and isinstance(args[0], str) and os.path.basename(args[0]) == "auth.json" and _fail_auth(args[0]))`

  `_fail_auth` increments `FAILURES` and prints `✗ opened an auth.json`. Run it and confirm it fails with NameErrors for the missing functions.
- [ ] **Step 3: Implement the functions** by copying the shape of `claude-code/reference.py` (`build_args`, `clean_env`, `locate`, `parse_version`). `scripts/test-codex-contract.sh`, `set -euo pipefail`, runs `python3 -B tests/fixtures/ai/codex/reference.py`.
- [ ] **Step 4: Run** `bash scripts/test-codex-contract.sh`. Expected: `All Codex contract checks passed`.
- [ ] **Step 5: Commit** with `test(plan-brains): F3a2-0 the Codex command line, environment, locator and sign-in state`.

### Task 2: Codex transcripts, the level table, and what a turn means

Gated: the recordings from 0A are committed under `codex/recorded/`.

**Files:**
- Create in `tests/fixtures/ai/codex/`: `levels.json`, `expected-parse.json`, `transcripts/*.jsonl`, `copy.json`, `labels.json`, and `hook-routing.json` (only if 0A step 9 recorded a pill)
- Modify: `tests/fixtures/ai/codex/reference.py`

**Interfaces:**
- Consumes: `load`, `check` from Task 1.
- Produces: `parse(lines, exit, stderr, level)`, `model_chip(mode)`, `level_chip(level, folder)`, `copy_text(code)`, and `route_hook(payload, live)` if `hook-routing.json` exists.

- [ ] **Step 1: Write `levels.json`.** Item type names are as **recorded**; the names below are the documented ones and are **unverified** until matched against `recorded/`.
  - `chat`: `sandbox` `read-only`, `items` `["agent_message", "reasoning", "todo_list"]`.
  - `none`: present only if 0A step 13 verified the override. It has the same items, plus `"shellOff": <the recorded override>`.
  - `read`: the same plus `"command_execution"`.
  - `agent`: absent unless Task 4 adds it.
  - `"stepFields": {"command_execution": ["command"], "web_search": ["query"]}`, `"stepFieldCap": 200`.
- [ ] **Step 2: Write the transcripts.**
  - Copy the scrubbed recordings as they are: `chat.jsonl`, `read.jsonl`, `chat-wants-command.jsonl`, `read-write-attempt.jsonl`, `bad-model.jsonl`, `image.jsonl`.
  - Then write these by hand, using only event types and fields seen in `recorded/`:
    - `signed-out.jsonl`, from `login-out` and an exec run's error shape if 0A has one; otherwise the spike row says "classified from stderr";
    - `plan-limit.jsonl`;
    - `crash.jsonl`, with one line that is not JSON and no `turn.completed`;
    - `unknown-item.jsonl`, an item type `"future_tool"`;
    - `read-file-change.jsonl`, a `file_change` item at `read`;
    - `long-command.jsonl`, a 100,000-character `command`;
    - `mcp.jsonl`;
    - `web.jsonl`;
    - `empty.jsonl`, no lines.
  - Placeholders are `__ID_n__`, `__HOME__`, and `__CWD__` for the turn folder.
- [ ] **Step 3: Write `expected-parse.json` cases first,** each with `transcript`, `level`, `exit`, `stderr` and `expect`. At least:
  - "chat: a plain answer" (`chat.jsonl`, chat) → `text` is the recorded agent message, `steps` `[]`, `finish` `{"usage": <turn.completed.usage>}`, `error` `null`, `engine` `{"threadId": "__ID_1__", "version": null}`.
  - "chat: a command stops the turn" (`chat-wants-command.jsonl`, chat) → `text` `""`, `steps` `[]`, `finish` `null`, `error` `{"kind":"bad_request","code":"nm_level_exceeded","resetsAt":null}`. This applies only if a `command_execution` was recorded. Otherwise the transcript stays as a plain answer and a hand-made one carries the case.
  - "read: a command is a step" (`read.jsonl`, read) → one step `{"kind":"command","command":<cut>,"state":"done"|"failed"}`.
  - "read: a file change stops the turn" (`read-file-change.jsonl`, read) → `nm_level_exceeded`.
  - "an unknown item stops the turn at every level" (`unknown-item.jsonl`, chat and read) → `nm_level_exceeded`.
  - "web search is outside every level" (`web.jsonl`, chat and read) → `nm_level_exceeded`.
  - "mcp is outside every level" → `nm_level_exceeded`.
  - "a long command is cut to 200" (`long-command.jsonl`, read) → `len(step.command) == 200`.
  - "signed out keeps its words" → `{"kind":"auth","code":"nm_codex_signed_out"}`.
  - "plan limit" → `{"kind":"billing","code":"nm_plan_limit","resetsAt":null}`, plus `resetsAt` if a recording carries one.
  - "a bad model" → `{"kind":"bad_request","code":"nm_codex_bad_model"}`.
  - "a crash" → `{"kind":"interrupted","code":"nm_codex_crashed"}`.
  - "nothing readable" (`empty.jsonl`, exit 0) → `{"kind":"bad_request","code":"nm_codex_unreadable"}`.

  The order of checks is fixed:
  1. Read the lines, skipping lines that are not JSON or are not objects.
  2. Take `thread.started` as the engine.
  3. On any `item.started` or `item.completed` whose `item.type` is not in the level's `items` → stop at that line.
  4. Otherwise `agent_message` text is joined by a blank line, and steps come from `stepFields`.
  5. A `turn.completed` sets `finish`.
  6. `turn.failed` and `error` messages are classified by substring tables in `copy.json` → `"match"`, filled from recordings.
- [ ] **Step 4: Write `copy.json` and `labels.json`.**
  - `copy.json` codes and words:
    - `nm_codex_missing` ("Codex isn't installed.", `installGuide`)
    - `nm_codex_signed_out` ("Codex is signed out.", `signIn`, which shows "Open your terminal and run `codex login`"; opens nothing)
    - `nm_plan_limit` ("Your OpenAI plan's limit was reached." and the "resets at" form from E3's `copy.json`)
    - `nm_codex_old` ("This version of Codex is too old for NotchMeow.")
    - `nm_codex_unreadable` (the spec's exact sentence, "NotchMeow can't read this version of the command line tool. Pick another brain.")
    - `nm_codex_crashed`
    - `nm_codex_bad_model` ("Codex doesn't know that model.")
    - `nm_bad_model` ("That model name can't be used.")
    - `nm_level_exceeded` ("Codex tried to do more than this level allows, so NotchMeow stopped it.")
    - `nm_level_unavailable` ("This level isn't available with your OpenAI plan yet.")
  - `labels.json` model chip:
    - mode `chatgpt` → "OpenAI · your plan"
    - `api_key` → "OpenAI · API key in Codex"
    - `unknown` → "OpenAI · Codex"
  - The level chip is the same as E3's (folder by its last part).
  - The words "Codex" appear only in notes, never in the row's label "Use my OpenAI plan" (owner's answer 4, 2026-10-17).
- [ ] **Step 5: Add the recorded-shape guard.** `check_shapes()` collects `(type, item.type, keys)` from every line in `recorded/*.jsonl`. It fails if any line in `transcripts/` that is not copied from `recorded/` uses a type or key outside that set. `unknown-item.jsonl`'s `future_tool` and `crash.jsonl`'s non-JSON line are the two named exceptions. An item type the recordings never produced but the docs name, such as `web_search`, `mcp_tool_call` or `file_change`, goes in `levels.json` → `"unrecordedTypes"` with a `source` URL. Each one is an extra exception, and the doc lists them as unverified. Add `check_no_private()`: no file under `codex/` matches `/Users/|/home/|C:\\\\Users|@[A-Za-z0-9-]+\.[a-z]`, nor the key-like pattern of `scrub` (rule 6). Fixture placeholders such as `sk-FAKE` are listed in an allow-list in the check.
- [ ] **Step 6: Optional hook routing.** This applies only if 0A step 9 showed a pill. Write `hook-routing.json` in the shape of `claude-code/hook-routing.json`: `live` holds the thread ids from `thread.started`, and the payload field is the one recorded. Add a `route_hook` that returns `"chat"` only for an exact string match and a payload without `nm_agent` other than `codex`.
- [ ] **Step 7: Run** `bash scripts/test-codex-contract.sh`. Expected: pass. Then flip `"verified": true` on each fixture the recordings now back, and run it again.
- [ ] **Step 8: Commit** with `test(plan-brains): F3a2-0 what a Codex turn means at each level, fail closed`.

### Task 3: The fake `codex`, the sentinel auth files, and the Codex docs

**Files:**
- Create: `tests/fixtures/ai/codex/fake_codex.py`
- Create: `docs/PLAN-BRAINS-CONTRACT.md` (Codex part)
- Modify: `tests/fixtures/ai/codex/reference.py`

**Interfaces:**
- Produces the fake's environment contract, named like E3's fake:
  - `NM_FAKE_CODEX_LOG`: append `{"argv", "env", "cwd", "stdin", "pid"}` per run.
  - `NM_FAKE_CODEX_TRANSCRIPT`: path to replay, with `__ID_1__` replaced by a fresh id per run.
  - `NM_FAKE_CODEX_EXIT`
  - `NM_FAKE_CODEX_STDERR`
  - `NM_FAKE_CODEX_HANG_AFTER`: a line count, then sleep until a signal, with a child process like E3's `hang`.
  - `NM_FAKE_CODEX_LOGIN_EXIT` and `NM_FAKE_CODEX_LOGIN_STDOUT` for `login status`.
  - `NM_FAKE_CODEX_VERSION` for `--version`.
  - `NM_FAKE_CODEX_TRY_WRITE`: if set and the argv has `--sandbox read-only`, the fake tries to create that file in its cwd and records `{"write": "refused"}` when the cwd's mode refuses it.

- [ ] **Step 1: Write `check_fixture_files()` first**, as in `claude-code/reference.py`. It checks:
  - every transcript but `crash.jsonl` is JSON lines;
  - the fake replays `chat.jsonl` line for line;
  - it records argv, stdin and environment;
  - `--version` and `login status` answer from their variables;
  - with `HANG_AFTER=1`, a SIGTERM leaves no child (pidfile check);
  - with `TRY_WRITE=made.txt` in a temp folder at mode `0500`, the log shows `{"write":"refused"}` and no `made.txt` exists.

  **The sentinel:** create `<tmp>/home/.codex/auth.json` with mode `0o000` and `HOME=<tmp>/home` for every fake run. The audit hook from Task 1 stays green, and the sentinel's `atime` is unchanged where the file system records it (skip that assertion if `os.stat` shows `atime == 0`). Run it and confirm it fails, because there is no fake yet.
- [ ] **Step 2: Implement `fake_codex.py`** by copying `claude-code/fake_claude.py`'s `record`, `hang` and signal order. It never imports anything outside the standard library.
- [ ] **Step 3: Run** `bash scripts/test-codex-contract.sh`. Expected: pass.
- [ ] **Step 4: Write `docs/PLAN-BRAINS-CONTRACT.md`, Codex part.** Sections:
  - **Files:** one line each.
  - **The levels:** the table from `levels.json`, the sandbox, and the cwd.
  - **What it never keeps.**
  - **Decisions:** every "(plan decision)" line of Global Constraints that concerns Codex.
  - **Probe results:** from 0A and 0B, with each item and verdict, as the no-tools spec's section.
  - **Release re-check:** before each release, re-read OpenAI's Terms of Use and https://learn.chatgpt.com/docs/non-interactive-mode, and Anthropic's legal page for OpenCode. Pull the row if they forbid it (owner, 2026-10-28). There is no release checklist file in the repo yet; this section is that item until one exists.
  - **Changing it:** add cases, never rename a code.
- [ ] **Step 5: Commit** with `test(plan-brains): F3a2-0 the fake codex, the sentinel auth file, and the Codex contract doc`.

### Task 4: Codex Agent over `codex app-server` (gated on Task 0B)

**If Task 0B did not pass:** add to `docs/PLAN-BRAINS-CONTRACT.md`, "Codex Agent: not offered", with the reason recorded. Keep the `agent` → `nm_level_unavailable` case. Commit with `docs(plan-brains): F3a2-0 Codex Agent waits (app-server probe)` and go to Checkpoint 1.

**Files (if it passed):**
- Create in `tests/fixtures/ai/codex/app-server/`: `probe.py` (written **before** 0B, step 2), `recorded/`, `expected-requests.json`, `expected-conversation.json`, `fake_app_server.py`
- Modify: `levels.json` (add `agent`), `expected-args.json` (replace the agent case), `reference.py`

**Interfaces:**
- Produces:
  - `app_server_args() -> ["app-server"]`
  - `approval_card(request) -> {"id", "kind": "command"|"fileChange", "command"|"paths", "reason"}`, with fields cut to 200
  - `approval_reply(request_id, choice: "allowOnce"|"deny") -> dict`
  - `parse_conversation(messages, level="agent")`, with the same output shape as `parse` plus `cards`

- [ ] **Step 1: Write `probe.py`.** It runs only by the owner, never in tests. It speaks newline-delimited JSON-RPC on the child's stdin and stdout, and every method name is taken from `app-server-help.txt` or the `/doc` it prints. It writes no file but its log. Commit it before 0B.
- [ ] **Step 2: Write the cases from `recorded/`**:
  - an approval request becomes a card;
  - "allowOnce" maps to the recorded one-time accept value, and **never** to a session-wide or always value;
  - "deny" maps to the recorded decline value;
  - a request the client does not answer within the turn is declined when the chat closes;
  - an unknown server→client request is declined and the turn stops with `nm_level_exceeded`;
  - the sandbox at `agent` is `workspace-write` in the chosen folder, never `danger-full-access`.

  Then write the checks, which fail first.
- [ ] **Step 3: Implement** `fake_app_server.py`, which replays the recorded server messages and holds at each approval request until a reply arrives, and the reference functions. Run `bash scripts/test-codex-contract.sh`. Expected: pass.
- [ ] **Step 4: Commit** with `test(plan-brains): F3a2-0 Codex Agent: approvals over app-server become cards, never approved without a click`.

**Checkpoint 1.** The controller runs `bash scripts/test-codex-contract.sh` and `git diff --quiet bfc83e52 -- tests/fixtures/ai/claude-code tests/fixtures/ai/reference.py`, then dispatches `nm-reviewer` on Tasks 1-4. It reports to the owner, who may merge the Codex half now.

### Task 5: OpenCode serve command, environment, inline config, locator, versions, sign-in, refusal table

**Files:**
- Create in `tests/fixtures/ai/opencode/`: `expected-serve.json`, `expected-env.json`, `locator-cases.json`, `versions.json`, `banner-cases.json`, `auth-list.json`, `providers.json`, `reference.py`
- Create: `scripts/test-opencode-contract.sh`
- Modify: `.github/workflows/build.yml`, adding `- name: OpenCode contract (fake opencode, shared fixtures)` / `run: bash scripts/test-opencode-contract.sh` after the Codex step.

**Interfaces:**
- Produces: `serve_args`, `level_config`, `serve_env`, `parse_banner`, `auth_state`, `provider_verdict`, `locate`, `parse_version`, `check_version`, with signatures as above. It reuses its own `load`, `check` and audit hook, a copy of Task 1's (two files, no shared import, as the E3 folder is self-contained).

- [ ] **Step 1: Write the fixtures.** Use `"verified": false` where 0C has not spoken.
  - `expected-serve.json`:
    - `"argv": ["serve", "--hostname", "127.0.0.1", "--port", "0"]`. If 0C refused `--port 0`, the app picks a free port by binding `127.0.0.1:0` and closing it, and the case records `"portFrom": "app"`.
    - `"cwd"`: `chatFolder` for `none` and `chat`, otherwise `folder`. `chatFolder` is `/support/NotchMeow/opencode-chat`, mode `0500`.
    - `"configDir"`: an empty NotchMeow folder `/support/NotchMeow/opencode-config`, set as `OPENCODE_CONFIG_DIR`, only if 0C step 6 showed that it keeps the sign-in and drops the user's global config.
    - `level_config` per level, with key names as recorded in `/doc`:
      - `none`: `{"permission": {"*": "deny"}, "share": "disabled", "autoupdate": false}`
      - `chat`: `none` plus `"webfetch": "allow", "websearch": "allow"`
      - `read`: `chat` plus `"read": "allow", "glob": "allow", "grep": "allow", "list": "allow"`
      - `agent`: `"*": "ask"` with `read`, `glob`, `grep` and `list` allowed, and `"doom_loop": "ask"`, `"external_directory": "ask"`

      If 0C shows `*` is not honoured, every tool key in `/doc`'s permission schema is listed one by one instead.
  - `expected-env.json`: the stripped names from Global Constraints. The set names are `OPENCODE_SERVER_PASSWORD` (the given password) and `OPENCODE_CONFIG_CONTENT` (compact JSON of `level_config`, keys sorted). Cases on mac, linux, and windows with lower-case names.
  - `banner-cases.json`: the recorded banner line → its port. Also: text without a URL → `null`; a URL on another host such as `0.0.0.0` → `null`, because a server not on 127.0.0.1 is refused; a port out of range → `null`.
  - `auth-list.json`:
    - exit `0` with at least one provider line → `ready`;
    - exit `0` with none → `noProvider`;
    - not runnable → `missing`;
    - a stdout matching `sk-|ghp_|gho_|eyJ|[A-Za-z0-9]{32,}` → `unknown`, and the output is dropped (spec, "if it does, the row uses …").
    - Provider names are never kept by this function.
  - `providers.json`:
    - `{"refused": {"anthropic": {"code": "nm_provider_refused", "text": "Anthropic's terms don't allow a Claude subscription through a third-party tool. Use an Anthropic API key in OpenCode, or the 'Use my Claude plan' brain, which runs Claude Code itself."}}}`
    - Cases: `anthropic` refused; `github-copilot`, `openai` and `openrouter` allowed; `""` and a non-string refused with `nm_bad_model`.
    - If 0C step 7 found a field that marks an API key, add `"anthropicApiKeyAllowed": {"field": <recorded>, "value": <recorded>}` and a case for it. Until then there is no such case.
  - `locator-cases.json`. On mac and linux:
    1. `~/.opencode/bin/opencode`
    2. `/opt/homebrew/bin/opencode`
    3. `/usr/local/bin/opencode`
    4. `~/.npm-global/bin/opencode`
    5. `$NPM_CONFIG_PREFIX/bin/opencode`
    6. the login shell.

    On Windows: `%USERPROFILE%\scoop\shims\opencode.exe`, `%ProgramData%\chocolatey\bin\opencode.exe`, then `opencode.exe` on `PATH`. `.cmd` and `.ps1` are never run. All unverified; marked so.
  - `versions.json`: as Codex, `minimum` from 0C.
- [ ] **Step 2: Write the checks** (`check_serve`, `check_env`, `check_banner`, `check_auth`, `check_providers`, `check_locator`, `check_versions`), plus "the password never appears in `argv`" and "the folder never appears in `argv`". Confirm they fail.
- [ ] **Step 3: Implement.** The script `scripts/test-opencode-contract.sh` runs `python3 -B tests/fixtures/ai/opencode/reference.py`.
- [ ] **Step 4: Run** it. Expected: `All OpenCode contract checks passed`.
- [ ] **Step 5: Commit** with `test(plan-brains): F3a2-0 the OpenCode server command, inline config per level, environment and refusal table`.

### Task 6: An OpenCode turn: requests, events, cards, preflight, fail closed

Gated: 0C recordings committed, and the owner's call on 0C step 6.

**Files:**
- Create in `tests/fixtures/ai/opencode/`: `expected-requests.json`, `preflight-cases.json`, `events/*.sse`, `expected-parse.json`, `copy.json`, `labels.json`
- Modify: `reference.py`

**Interfaces:**
- Consumes: `level_config`, `provider_verdict` from Task 5.
- Produces: `turn_requests`, `permission_reply`, `preflight`, `parse_events`, `model_chip`, `copy_text`.

- [ ] **Step 1: Write `expected-requests.json`.** Paths and bodies come from `recorded/doc.json`. Every request carries `Authorization: Basic base64("opencode:" + password)`, shown in fixtures as `__AUTH__`.
  - A first turn is `GET /config` (the preflight), then `POST /session` with `{}`, then `POST /session/<sid>/prompt_async` with `{"model": {"providerID": p, "modelID": m}, "parts": [...]}`.
  - A later turn skips the first two, because the session is reused while the server lives.
  - Abort is `POST /session/<sid>/abort`.
  - `permission_reply("allowOnce")` → `{"response": "once"}`. `permission_reply("deny")` → `{"response": "reject"}`. There is no `"always"` case, and a check asserts no fixture contains `"always"` or `"remember": true`.
  - The model rule is `^[A-Za-z0-9][A-Za-z0-9._-]{0,63}/[A-Za-z0-9][A-Za-z0-9._:/-]{0,127}$`, else `nm_bad_model`. A refused provider yields no request at all, just `nm_provider_refused`.
- [ ] **Step 2: Write `preflight-cases.json`.** The app keeps only the `permission` key of `GET /config` (the rest may hold keys) and never logs it. `preflight(effective, level)` takes that `permission` object and returns:
  - `ok` only if every tool the level denies is `deny` in the effective config and every tool it allows is no wider than the level's value (`deny` < `ask` < `allow`).
  - A tool key missing from the effective config, an effective config without `permission`, or a non-object → `{"ok": false, "code": "nm_level_unprovable"}`.

  Cases include "the level's own config is ok", "a looser effective edit is refused", "a missing key is refused", "agent with edit `allow` is refused" (agent must still ask), and the recorded `override-config.json` with its verdict. **If 0C step 6 showed the user's config can loosen a level, the `chat` and `read` cases of the recorded config expect `nm_level_unprovable`. The doc states that only Agent ships for OpenCode** (owner's rule, 2026-10-22).
- [ ] **Step 3: Write the SSE files and `expected-parse.json`.**
  - Copy as recorded: `chat.sse`, `ask.sse`, `abort.sse`.
  - Write by hand, from recorded shapes only:
    - `other-session.sse`
    - `chat-permission.sse` (a permission event at `chat`)
    - `read-bash.sse` (a `bash` tool part at `read`)
    - `refused-provider.sse` (an assistant message with `providerID` `anthropic`)
    - `unknown-part.sse`
    - `session-error.sse`
    - `long-title.sse`
  - `parse_events` order:
    1. Read `data:` lines only.
    2. Ignore an event whose session id is another one, and an event that carries no session id at all, unless its type is in `"inert"`. Neither is ever shown.
    3. A `message.updated` for an assistant sets the engine (`provider`, `model`); a refused provider → `actions: ["abort"]`, `nm_provider_refused`, text `""`.
    4. Text parts are accumulated by part id, the latest text winning.
    5. A tool part whose tool is not allowed by the level's config → `actions: ["abort"]`, `nm_level_exceeded`, text `""`.
    6. A permission event: at `agent` it is a card `{"id", "tool", "title", "pattern"}`, cut to 200, with no action. At any other level → `actions: [{"reject": id}, "abort"]`, `nm_level_exceeded`.
    7. The idle event ends the turn with `finish`.
    8. A session error is classified by `copy.json` matches: auth → `nm_opencode_signed_out`, a rate or usage limit → `nm_plan_limit`, anything else → `nm_opencode_failed`.
    9. An unknown event type is skipped at `agent` and stops the turn at other levels, unless it is one of the recorded types that carry nothing shown, such as heartbeat and `server.connected`, listed in `"inert"`.
  - Cases:
    - "chat: a plain answer"
    - "agent: a permission becomes a card"
    - "chat: a permission request is rejected and stops the turn"
    - "read: a bash part stops the turn"
    - "the answering provider is checked, not only the asked one"
    - "another session's events are ignored"
    - "abort ends the turn as interrupted" → `{"kind":"interrupted","code":"nm_stopped"}`
    - "a card title is cut to 200"
- [ ] **Step 4: Write `copy.json`, `labels.json` and the guards.**
  - `copy.json` codes:
    - `nm_opencode_missing` ("OpenCode isn't installed.")
    - `nm_opencode_no_provider` ("Open your terminal and run `opencode auth login`.")
    - `nm_opencode_signed_out`
    - `nm_opencode_old`
    - `nm_opencode_unreadable` (the spec sentence)
    - `nm_opencode_failed`
    - `nm_opencode_server` ("OpenCode's server didn't start.")
    - `nm_level_exceeded` ("OpenCode tried to do more than this level allows, so NotchMeow stopped it.")
    - `nm_level_unprovable` ("Your OpenCode settings could allow more than this level, so NotchMeow won't run it. Use Agent, or remove the rule.")
    - `nm_provider_refused` (the same text as `providers.json`, checked identical)
    - `nm_bad_model`
    - `nm_stopped`
  - `labels.json`: "OpenCode · <provider>/<model>", with the spec's line, and "OpenCode" before a turn names one.
  - Add `check_shapes()` and `check_no_private()` as in Task 2, with the key-like pattern included, over `recorded/` and `events/`.
- [ ] **Step 5: Run, confirm the failures, implement, then run until pass.**
- [ ] **Step 6: Commit** with `test(plan-brains): F3a2-0 an OpenCode turn at each level: preflight, cards, refusals, fail closed`.

### Task 7: The fake `opencode`

**Files:**
- Create: `tests/fixtures/ai/opencode/fake_opencode.py`
- Modify: `reference.py`

**Interfaces:**
- Produces the fake:
  - `fake_opencode.py --version`, `auth list` and `models` answer from `NM_FAKE_OPENCODE_VERSION`, `NM_FAKE_OPENCODE_AUTH_EXIT` and `NM_FAKE_OPENCODE_AUTH_STDOUT`, and `NM_FAKE_OPENCODE_MODELS`.
  - `fake_opencode.py serve --hostname H --port P` refuses any `H` other than `127.0.0.1` with exit 2. It binds `(H, P)`, where `P = 0` means any free port. It prints the banner in the recorded form, and requires Basic auth from `OPENCODE_SERVER_PASSWORD`, answering 401 without it.
  - `GET /config` returns `NM_FAKE_OPENCODE_EFFECTIVE`, a JSON path, or else the parsed `OPENCODE_CONFIG_CONTENT`.
  - `POST /session` returns `{"id": "ses___ID_1__"}`. `prompt_async` answers 204 and starts streaming `NM_FAKE_OPENCODE_EVENTS`, a `.sse` path, to every open `GET /event`.
  - At a permission event it holds until `POST /session/:id/permissions/:pid` and records the body. `abort` sends the recorded abort tail.
  - `NM_FAKE_OPENCODE_IDLE_EXIT` gives seconds without a request before the fake exits, standing in for the app's idle stop in run tests.
  - Every request is logged to `NM_FAKE_OPENCODE_LOG` as `{"method", "path", "auth": "ok"|"bad", "body"}`. The password itself is never logged.

- [ ] **Step 1: Write the checks first** in `check_fake_server()`:
  - `serve --hostname 0.0.0.0` exits 2;
  - the banner parses with `parse_banner`;
  - a request without auth gets 401;
  - a request with the wrong password gets 401;
  - `GET /config` returns the level config;
  - a `chat.sse` replay through `parse_events` equals its `expected-parse.json` case;
  - for `ask.sse`, the fake holds until `permission_reply("deny")` is posted, and the log shows `{"response":"reject"}`;
  - abort works;
  - the log never contains the password string;
  - `IDLE_EXIT=1` exits within 3 s.

  Every run uses `HOME=<tmp>/home` with a mode-`000` `.local/share/opencode/auth.json` sentinel, and the audit hook stays green. Confirm the checks fail.
- [ ] **Step 2: Implement** with `http.server.ThreadingHTTPServer` and one `threading.Condition` for the held permission. Standard library only.
- [ ] **Step 3: Run** `bash scripts/test-opencode-contract.sh`. Expected: pass within 30 s.
- [ ] **Step 4: Commit** with `test(plan-brains): F3a2-0 the fake opencode server: 127.0.0.1 only, a password per run, a held permission`.

### Task 8: Docs, wiring, final checks

**Files:**
- Modify: `docs/PLAN-BRAINS-CONTRACT.md` (OpenCode part, probe results, decisions)
- Modify: `CLAUDE.md`. Add one bullet after the `shared/companion-core.js` bullet: "`tests/fixtures/ai/codex/` and `tests/fixtures/ai/opencode/`, `docs/PLAN-BRAINS-CONTRACT.md`: the plan brains' contract (F3a2-0) …", naming the two scripts and that `reference.py` decides.
- Modify: `ARCHITECT.md`, one line in its map of contracts.
- Modify: the spec, a status line under call 10 and call 11: "Contract: `docs/superpowers/plans/2026-10-28-f3a2-0-plan-brains-contract.md`".

- [ ] **Step 1: Write the OpenCode part of the doc**: levels, the server's life (one per level and folder, 600 s idle, 127.0.0.1, password), the preflight, the refusal table, what it never keeps, the Decisions and the Probe results.
- [ ] **Step 2: Run all of these:**
  - `bash scripts/test-codex-contract.sh`
  - `bash scripts/test-opencode-contract.sh`
  - `bash scripts/test-ai-contract.sh`
  - `bash scripts/test-claude-code.sh`
  - `git diff --quiet bfc83e52 -- tests/fixtures/ai/claude-code tests/fixtures/ai/reference.py tests/fixtures/ai/sse tests/fixtures/ai/providers.json tests/fixtures/ai/router-cases.json tests/fixtures/ai/history-cases.json`
  - `bash scripts/check-no-leftovers.sh`
  - `grep -rE "auth\.json" tests/fixtures/ai/codex tests/fixtures/ai/opencode | grep -v "sentinel\|never"`

  Expected: every script passes, the diff is quiet, and the grep shows nothing.
- [ ] **Step 3: Commit** with `docs(plan-brains): F3a2-0 the contract doc, the map, and the spec's status`.
- [ ] **Step 4: Final review.** Dispatch `nm-reviewer-deep` (Sonnet 5.5 high, trigger 4: privacy and fail-closed) on the whole branch, with `pr-review-toolkit:silent-failure-hunter` beside it. Report to the owner (Checkpoint 2). Never push.
