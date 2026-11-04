# Port the Windows and Linux Gemini CLI and Antigravity Hooks Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give the Windows/Linux app the Gemini CLI and Antigravity hooks the Mac has had since commit `b202eca`: two sections in Settings that install them (diff, dated backup, confirm), and a relay that translates their events, so each `gemini` or `agy` session gets its own `agent_gemini` or `agent_antigravity` pill. Ported by hand from upstream's branch `n22-gemini` (local ref `upstream/n22-gemini`: commits `0fdbda2`, `5c5b75e`, `5776b97`), with every identifier renamed to NotchMeow's and the Mac's behaviour matched.

**Architecture:** Three small layers. (1) The relay (`windows/hook/`): a new pure module `agents.rs` translates the two agents' event names and field shapes, and `main.rs` gets a testable `shape_event` and answers `{}` to those two agents, as the Mac's `nm-hook` does. (2) The installers (`windows/src-tauri/`): a new `agent_hooks.rs` holds one install, uninstall, preview and status path for both agents (not upstream's three copies of it), built on the hardened helpers of `hooks.rs`, plus three Tauri commands that take the agent's tag. (3) The Settings window: one `agentHooksSection`, used twice, in Claude Code's own look.

**Tech Stack:** Rust (`serde_json` only: no new crate), TypeScript without a framework, `cargo test` through `windows/scripts/cargo-linux.sh` (Docker), `npx --no-install tsc --noEmit`, and a stubbed-backend browser check with `playwright-cli`. No new dependency, no network.

**Spec:** `docs/superpowers/specs/2026-10-03-notchmeow-design.md`: the "Upstream ports" bullet (ported by hand, never a merge; identifiers renamed to NotchMeow's) and the identity table in "Sub-project A, steps" 1 (`nm_agent`, `notchmeow-hook`, the Antigravity root key `notchmeow`). The behaviour to match is the Mac's: upstream's two Mac commits are already in this history (`git show b202eca`, `git show f6f7c93`), renamed today in `NotchBuddy/Sources/App/HookServer.swift` (the `Gemini CLI and Antigravity hook installers` section and the `nm-hook` Python relay) and in `docs/AGENTS.md`.

**What upstream's branch does.** `git log --oneline upstream/main..upstream/n22-gemini` lists three commits, cut from `341b86a` (2026-10-01). `upstream/main` has the Mac half of the feature (`b202eca`, `f6f7c93`) and never received the Windows half (`git grep -il gemini upstream/main -- windows/` prints nothing), so the branch is the only source. It adds:
- **The relay** (`windows/hook/src/main.rs`): `normalize_event` (Gemini's `BeforeTool`, `AfterTool`, `BeforeAgent`, `AfterAgent` and Antigravity's `PreInvocation`, `PostInvocation` become `PreToolUse`, `PostToolUse`, `UserPromptSubmit`, `Stop`, `PostToolUse`), `normalize_tool_fields` (`toolCall: {name, args}` to `tool_name` and `tool_input`, the PascalCase argument keys `CommandLine`, `FilePath`, `Path`, `Url`, `Query`, `Pattern` flattened, `conversationId` to `session_id`) and a `GEMINI_SESSION_ID` fallback. The third commit corrects the first: `BeforeAgent` and `AfterAgent` were `SubagentStart` and `SubagentStop`, and `AfterModel` (one event per streamed chunk) was installed.
- **The installers** (`windows/src-tauri/src/hooks.rs`, `lib.rs`): Gemini CLI into `~/.gemini/settings.json` (six events, `matcher: "*"`, timeouts in milliseconds), Antigravity into `~/.gemini/config/hooks.json` (five events under one top-level key, timeouts in seconds), each with its own preview, write and status, and six Tauri commands.
- **The Settings window** (`windows/src/settings/main.ts`, `windows/src/core/bridge.ts`): an `agentHookSection` per agent.
- **Docs:** `windows/README.md`, `docs/AGENTS.md`, README, CHANGELOG.

**How the Mac does it today** (the behaviour this plan matches, from `HookServer.swift`):
- **Gemini CLI:** `~/.gemini/settings.json`; `SessionStart` and `SessionEnd` (10000 ms), `BeforeTool` as `PreToolUse`, `AfterTool` as `PostToolUse`, `BeforeAgent` as `UserPromptSubmit`, `AfterAgent` as `Stop` (5000 ms each); every entry is `{matcher: "*", hooks: [{type: "command", command: "<relay> --agent gemini <Event>", timeout}]}`. `AfterModel` is not installed.
- **Antigravity:** `~/.gemini/config/hooks.json`; the top-level key `notchmeow` holds `PreToolUse` and `PostToolUse` as matcher groups and `PreInvocation`, `PostInvocation` and `Stop` as direct handlers (no matcher), timeout 10 (seconds), command `<relay> --agent antigravity <Event>`. Uninstalling removes only that key.
- **Safety:** a file that is not valid JSON, or a `hooks` of an unexpected type, is refused with "NotchMeow has not touched it"; uninstalling when there is no file says "No Gemini CLI hooks to remove."; the write is backed up (`settings.json.bak-<time>`, `hooks.json.bak-<time>`), refused when the file changed since the preview, and only ours are ever removed (a flat older-format entry too).
- **Relay:** `--agent <name>` becomes `nm_agent`; the event is `hook_event_name` or the first positional argument, then translated; the folder is `cwd`, else `workspacePaths[0]`, else the working directory; and **the relay prints `{}` for `gemini` and `antigravity`** (both read stdout as JSON), nothing for Claude Code. If the app does not answer it exits at once.

**What this plan changes against upstream's branch, and why** (the first four are where the branch and the Mac differ, and the Mac wins):
1. The branch's relay prints nothing for these two agents; the Mac prints `{}`. Added.
2. The branch installs all five Antigravity events as matcher groups; the Mac installs the three lifecycle events as direct handlers. Matched.
3. The branch has no `workspacePaths` fallback for the folder and no "No … hooks to remove." refusal; the Mac has both. Added.
4. The branch coerces a `hooks` (or an event) of an unexpected type to an empty one and writes over it; the Mac refuses. The port refuses, with a test.
5. The branch was cut on 2026-10-01, before upstream's own hardening of `hooks.rs` (`bef6558`, 2026-10-02: Linux, owner-only permissions, symlink-following writes), and was never rebased onto it; it copies the older write path three times. NotchMeow's `hooks.rs` has the hardened code (a single-quoted command through `sh_quote`, `write_like`, the symlink handling). The port reuses it: `replace_file` is extracted from `hooks::write`, with `hooks.rs`'s tests as the guard, and the new installers call it.
6. Six commands become three, taking the agent's tag; one Settings section function serves both agents; one install path serves both files.
7. Renames: `coucou_agent` to `nm_agent`, `coucou-hook` to `notchmeow-hook`, the Antigravity key `coucou` to `notchmeow`, the marker `coucou-hook` to `notchmeow-hook`, every "Coucou" in text to "NotchMeow" (or dropped), and the relay's file name no longer assumed to end in `.exe` in the Settings text.

**Base:** branch `port/windows-gemini-antigravity`, created from `notchmeow/rebrand` at `49a9d1a` or later (the dry run below used `94552ae`; the commits in between touch only `design/sounds/` and the two cat plans), with this plan file already committed to `notchmeow/rebrand`. `e1/tauri` (the AI code under `windows/`) is merged, which is what the spec's "Upstream ports" bullet waited for. This plan touches nothing under `NotchBuddy/`.

## Global Constraints

Every task's requirements include this section. Values are copied from `CLAUDE.md`, `ARCHITECT.md` and the spec.

- **Port by hand.** Never `git merge`, `git cherry-pick` or `git checkout` anything from `upstream/*`: it would bring Coucou's identity back. The upstream refs are local and stay read-only. No fetch from any remote, no network, no download, no new dependency.
- **Contract strings are frozen and renamed together or not at all:** `nm-hook`, `nm.sock`, `notchmeow-hook`, `nm_kind`, `nm_agent`. This plan uses `notchmeow-hook` (the relay and the hook-entry marker), `nm_agent` (set by `--agent`), and the Antigravity root key `notchmeow`. It adds no new contract string.
- **Pill IDs are frozen:** the two agents' pills are `agent_gemini` and `agent_antigravity`, which the island derives from `nm_agent` (`gemini`, `antigravity`). The `--agent` tags are exactly `gemini` and `antigravity`; never rename them.
- **Never block the agent:** if NotchMeow does not answer, the relay exits at once, and every step stays under the relay's existing deadlines. A Gemini CLI or Antigravity hook never waits for an answer.
- **Never overwrite the user's agent settings:** read the file, refuse what is unreadable or of an unexpected shape, show the diff, take a dated backup, merge, and write only after the user's explicit click and only if the file is still the one previewed. Uninstall removes NotchMeow's entries and nothing else.
- **No Coucou:** no `coucou`, `Coucou`, `Mochi`, `nb-hook`, `nb.sock`, `coucou_agent` or `coucou-hook` in anything this plan adds (a `grep` of the diff in Task 4).
- **macOS is primary:** the Mac already has both agents. Nothing here changes the Mac; where the port is stricter than the Mac (see "Follow-ups"), the Mac is named, not edited.
- **Never restyle a shipping view:** the two new Settings sections reuse existing classes (`section`, `.row`, `.hint`, `.path`, `.notice`, `.diff`, `button.primary`, `button.danger`) and `claudeSection` is not touched.
- **Never run, quit or replace the installed NotchMeow app.** `~/Library/Logs/NotchMeow/nm.log` must not grow: nothing here starts the app (the relay is run only inside the Docker container, with its own `XDG_RUNTIME_DIR`).
- **Node tools come from the worktree's own `windows/node_modules`, which a new worktree does not have:** copy the main checkout's (`cp -cR "<main checkout>/windows/node_modules" windows/node_modules`, an APFS clone). Never run `npm install` or `npm ci`, and run `npx` only as `npx --no-install`: a plain `npx` for a package that is missing downloads it.
- **Rust runs only through `windows/scripts/cargo-linux.sh`** (Docker Desktop running), with this plan's own target directory, because other worktrees share that script's Docker volume (see "Running the Rust tests"). Never install a toolchain on the host and never build or pull an image.
- **Commits:** local only, never pushed. End every commit message with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`, or with the model that wrote it when an implementer runs on another one.

## Review Focus

The spec says the Mac behaviour is the target. It is silent on these inputs, and each would bite a person first. Each line names its test.

1. **A config file NotchMeow cannot safely edit:** invalid JSON, a JSON array, a `hooks` that is a list or a string, an event that is an object or a string, a symlinked file (a dotfiles repo). Expected: refused with the file's name and the reason (invalid JSON, not an object, "has an unexpected type — NotchMeow has not touched it"), no backup, no new folder, nothing written; a symlink stays a symlink and its target is updated. Tests: Task 2 `unexpected_shapes_are_refused_and_never_replaced`, `a_file_we_cannot_use_is_refused_before_any_backup_or_write`, `a_symlinked_config_file_stays_a_symlink_and_its_target_is_updated`.
2. **The user's own hooks next to ours, and a file that changes under the preview:** a foreign hook in the same group as ours, a foreign flat entry, other settings, a file edited between the preview and the click. Expected: only ours are touched; install twice is install once; uninstall puts the file back exactly; a changed file is refused. Tests: Task 2 `a_foreign_hook_in_the_same_group_as_ours_survives_both_ways`, `an_older_flat_entry_is_removed_and_a_foreign_flat_entry_is_kept`, `gemini_install_twice_is_install_once_and_uninstall_restores_the_file`, `installing_backs_up_keeps_a_bom_files_other_settings_and_refuses_a_changed_file`.
3. **A payload in a shape nobody planned for:** an Antigravity event with no `toolCall`, a `toolCall` that is a string, `args` that is a list, an empty or numeric `conversationId`, empty `workspacePaths`, a payload that already carries `tool_name` (Claude Code), garbage on stdin. Expected: no panic, nothing invented, a Claude Code event forwarded exactly as before, and garbage forwards nothing. Tests: Task 1 `odd_shapes_are_ignored_never_a_panic`, `a_payload_that_already_has_tool_name_is_left_exactly_as_it_is`, `a_claude_code_event_is_forwarded_as_before`, `a_payload_the_relay_cannot_use_forwards_nothing`.
4. **NotchMeow closed, and the wrong agent getting JSON:** the relay must answer `{}` to Gemini CLI and Antigravity and exit 0 at once, and stay silent for Claude Code and for every other `--agent`. Tests: Task 1 `only_gemini_and_antigravity_get_the_empty_json_answer`, `only_gemini_and_antigravity_are_answered_with_json_when_there_is_no_decision`, and the smoke test of the built relay (app closed: exit 0 in under 1.5 s with the right stdout).
5. **A relay path with a space or a quote** (a Windows user called "Zoé Smith", a Linux home with an apostrophe). Expected: the command still starts the relay: a quoted path in forward slashes on Windows, one single-quoted word on Linux. Tests: Task 2 `a_windows_command_is_a_quoted_path_in_forward_slashes`, `a_unix_command_is_one_single_quoted_word_whatever_the_path_holds`.

---

## File Structure

All paths are under the repository root.

| Path | Change | Responsibility |
|---|---|---|
| `windows/hook/src/agents.rs` | new | Pure translation of Gemini CLI and Antigravity events and fields into the island's names: `normalize_event`, `normalize_tool_fields`, `workspace_cwd`, `silent_answer`. |
| `windows/hook/src/main.rs` | modify | `mod agents`; `Event`; the pure `shape_event` split out of `read_event`; `stdout_for` (`{}` for the two agents). |
| `windows/src-tauri/src/agent_hooks.rs` | new | `Agent` (`Gemini`, `Antigravity`), the merge and removal of each file's entries, status, preview and write with backup, fingerprint and refusal. |
| `windows/src-tauri/src/hooks.rs` | modify | `replace_file` extracted from `write`; six helpers become `pub(crate)`. Claude Code's behaviour is unchanged. |
| `windows/src-tauri/src/lib.rs` | modify | `mod agent_hooks`; three commands (`agent_hooks_status`, `agent_hooks_preview`, `agent_hooks_apply`), registered. |
| `windows/src/core/bridge.ts` | modify | `HookAgent` and three `Bridge` methods. |
| `windows/src/settings/main.ts` | modify | `agentHooksSection`, two sections after Claude Code. |
| `windows/README.md`, `README.md`, `docs/AGENTS.md`, `CHANGELOG.md` | modify | What now works on Windows and Linux. |

**Not touched:** `windows/src/island/hooks.ts` (the island already routes `nm_agent` to an `agent_<name>` pill, and an external agent's `PermissionRequest` is declined there), `windows/src/core/state.ts`, `windows/src/island/island.ts`, `windows/src-tauri/src/pipe.rs`, `windows/hook/src/win.rs` and `unix.rs`, `CLAUDE.md`, `ARCHITECT.md`, `.github/workflows/*` (CI already runs `cargo test --workspace` on Windows for pull requests that touch `windows/`, so the new tests run there too), `NotchBuddy/`, `design/`, `tests/fixtures/`.

**Overlap with the Windows/Linux cat plan** (`2026-10-04-a-tauri-cats-stages-1-4.md`, which may run at the same time). Its **Files:** blocks list `windows/src/mochi/` (renamed to `src/cat/`), `src/island/island.ts`, `src/views/views.ts`, `src/core/state.ts`, `src/main.ts`, `tsconfig.json`, `package.json`, `src/upload/*`, `dev/upload-preview.ts`, `scripts/cat-tests/*`, and in Task 13 `windows/README.md`, `.github/workflows/windows-tests.yml`, `ARCHITECT.md` and `CLAUDE.md`. It says it leaves the Rust side, the relay and `island/hooks.ts` untouched.
- **No file is shared except `windows/README.md`.** This plan adds a whole section before the line `## AI: cloud keys and local models` (anchored on the last sentence of the Claude Code section); the cat plan changes the table row that starts `| Drag a file onto the island`, the layout line `mochi/ …` and inserts `### Testing the cats` before `## What's different from the Mac version`. The anchors are different lines and none is adjacent to another, so the two merge in either order. Both plans anchor on text, not on line numbers.
- **`island/hooks.ts`, `state.ts` and `island.ts`: not touched here.** Gemini and Antigravity events reach `hooks.ts` through the existing `nm_agent` routing. The cat plan's later stages will edit `hooks.ts` to map search tools to the "searching" state (its notes mention `SEARCH_TOOLS`); that work reads `payload.tool_name` and, for Gemini CLI, `payload.nm_agent === "gemini"`, which this plan's relay now sets. See "Follow-ups for the main session".
- **The `src/mochi/` to `src/cat/` rename** touches no file this plan edits; `settings/main.ts` and `core/bridge.ts` do not import from it.
- **`CHANGELOG.md`:** features add their bullet at the end of the Unreleased list, so this plan inserts its bullet before the line `- Local models everywhere (macOS): Ollama, …` instead, which no other plan touches. If git still reports a conflict there, keep both bullets.
- **Order:** either. Whichever lands second merges `notchmeow/rebrand` first; no conflict is expected.

**Overlap with the two other port plans written today** (`2026-10-05-port-keyboard-shortcuts.md`, macOS only, and `2026-10-05-port-release-plist-check.md`). Neither touches `windows/`. The release-check plan shares no file with this one (`scripts/`, `.gitignore`, `build.yml`). The shortcuts plan edits `README.md` (it adds a Features line after `- **Drop a file on the notch**`; this plan edits the two Gemini and Antigravity rows of the Setup table), `CHANGELOG.md` (it adds bullets after the `Dropped files reach every model` bullet; this plan inserts before `Local models everywhere`), `CLAUDE.md` and `docs/SPEC.md` (not touched here): different lines everywhere, so they merge in either order.

**Agents** (CLAUDE.md: the lightest model that fits). Tasks 3 and 4 give their full code and edits and are transcription plus a run: `nm-implementer-light`. Tasks 1 and 2 are Rust that the Mac cannot compile (Linux in Docker, and a Windows branch that only the Windows check and CI compile): `nm-implementer`; if a step's expected output differs and the cause is not a typo, hand the task to `nm-implementer-deep`. Task reviews: `nm-reviewer`; the final whole-branch review: `nm-reviewer-deep`. Coding agents load `ponytail:ponytail`, `superpowers:test-driven-development` and `superpowers:verification-before-completion`; reviewers load `ponytail:ponytail-review`.

**Order of tasks:** the relay first (the contract the installers write commands for), then the installers, then the Settings sections, then the docs and the final checks.

1. The relay translates Gemini CLI and Antigravity
2. The installers for both agents
3. The Settings sections
4. Docs and the final checks

## Execution

One worktree chat session runs the whole plan: branch `port/windows-gemini-antigravity`, model **Sonnet 5.5 at medium effort** (ARCHITECT.md: a plan whose tasks are mostly given in full). Medium and not high because every task carries its code, and the plan was replayed task by task in a throwaway clone before it was written down. What the clone could not prove is the Windows-only code (a few lines) and the real agents: Task 4's Windows check and the manual checks cover them, and a fix round that goes beyond a typo moves to `nm-implementer-deep`. Nothing is pushed.

**Before the session starts,** the plan file is committed to `notchmeow/rebrand` (a docs-only commit, the plan file alone): the controller does this, with the owner's OK, so the branch the session starts from already holds the plan it runs. **The base is `49a9d1a` or later:** the session's branch is made from `notchmeow/rebrand` as it is then, and `git merge-base --is-ancestor 49a9d1a HEAD` must succeed.

**The session is started in three steps** (ARCHITECT.md), because a chip's first turn runs on the app's default model and a model change applies only from a session's next turn:

1. **Setup and stop.** The chip's prompt only sets up:

   > Run `git switch -c port/windows-gemini-antigravity notchmeow/rebrand`, then `git merge-base --is-ancestor 49a9d1a HEAD` and `git ls-files docs/superpowers/plans/2026-10-05-port-windows-gemini-antigravity.md`: the first must succeed and the second must print the plan's path. If either fails, say so and stop. Read `CLAUDE.md`, `ARCHITECT.md`, `docs/superpowers/plans/2026-10-05-port-windows-gemini-antigravity.md` and `docs/superpowers/specs/2026-10-03-notchmeow-design.md` (the "Upstream ports" bullet). Run `docker image inspect notchmeow-linux-dev` and say whether it succeeds; never build or pull an image. Reply "ready" and stop. Do not start any task, and never launch NotchMeow.

2. **Model.** Once the owner starts the chip, the main session sets that session to Sonnet 5.5 at medium effort (`set_session_model`, `set_session_effort`).
3. **Brief.** The main session then sends the controller brief as the next message:

   > Run `docs/superpowers/plans/2026-10-05-port-windows-gemini-antigravity.md` with `superpowers:subagent-driven-development`, task by task, on this branch. Dispatch each task to the agent the plan names for it, then to `nm-reviewer`; fix what the review finds before the next task. After Task 4, dispatch `nm-reviewer-deep` over the whole branch. Commit only as the plan's commit steps say, and never push. When you are done, report: the commits, the test counts of `cargo-linux.sh test --workspace` (before and after), the output of the relay smoke test and of the browser check, the result of the Windows `cargo check`, and anything you could not settle, with the manual checks the owner still has to do on Windows and Linux.

Before any follow-up turn, the main session checks the session is still on its configured model and effort.

## Running the Rust tests

Every command in this plan runs from the repository root (the worktree's top folder). Rust runs in Docker through `windows/scripts/cargo-linux.sh`. Docker Desktop must be running and the image must already exist; the script would otherwise build it, which pulls a base image, so check first and stop if it is missing:

```bash
docker image inspect notchmeow-linux-dev >/dev/null && echo "image ok"
CL=windows/scripts/cargo-linux.sh
TD=/repo/windows/target/port-gemini-agy      # this plan's own target dir: the Docker volume is shared by every worktree
```

Every command below is `$CL <cargo arguments> --target-dir $TD`, for example `$CL test -p notchmeow-hook --target-dir $TD`. A test filter goes after `--`: `$CL test -p notchmeow --target-dir $TD -- agent_hooks`. The relay is built for the container's Linux, so the Windows-only lines (`#[cfg(windows)]`) are compiled by Task 4's Windows check, not by these runs.

---

### Task 1: The relay translates Gemini CLI and Antigravity

**Files:**
- Create: `windows/hook/src/agents.rs`
- Modify: `windows/hook/src/main.rs`
- Test: both files (`#[cfg(test)]` modules, run by `cargo test -p notchmeow-hook`)

**Interfaces:**
- Consumes: the relay as it is: `decision_json`, `talk`, `truncate_strings`, `DROPPED_FIELDS`, and the transport (`win.rs`, `unix.rs`).
- Produces `agents.rs`: `pub const GEMINI: &str = "gemini"`, `pub const ANTIGRAVITY: &str = "antigravity"`, `normalize_event(name: &str) -> &str`, `normalize_tool_fields(map: &mut Map<String, Value>, env_session_id: &str)`, `workspace_cwd(map: &Map<String, Value>) -> Option<String>`, `silent_answer(agent: &str) -> Option<&'static str>`.
- Produces `main.rs`: `struct Event { line: String, name: String, agent: String }`, `shape_event(raw: Vec<u8>, args: &[String], env: impl Fn(&str) -> String, current_dir: impl FnOnce() -> Option<String>) -> Option<Event>`, `stdout_for(decision: Option<&str>, agent: &str) -> Option<String>`.
- The wire contract Task 2 writes commands for: `<relay> --agent gemini|antigravity <Event>` with the agent's JSON on stdin; the forwarded line carries `nm_agent`, a translated `hook_event_name`, and `tool_name`, `tool_input`, `session_id` and `cwd` where the agent has them.

- [ ] **Step 1: Write the failing tests**

Create the module with its tests only, declare it, and add the relay's tests.

```rust title="windows/hook/src/agents.rs"
#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn obj(v: Value) -> Map<String, Value> {
        v.as_object().cloned().expect("a JSON object")
    }

    #[test]
    fn gemini_and_antigravity_event_names_become_the_islands() {
        for (from, to) in [
            ("BeforeTool", "PreToolUse"),
            ("BeforeToolSelection", "PreToolUse"),
            ("AfterTool", "PostToolUse"),
            ("AfterModel", "PostToolUse"),
            ("BeforeAgent", "UserPromptSubmit"),
            ("AfterAgent", "Stop"),
            ("startup", "SessionStart"),
            ("exit", "SessionEnd"),
            ("PreInvocation", "UserPromptSubmit"),
            ("PostInvocation", "PostToolUse"),
        ] {
            assert_eq!(normalize_event(from), to, "{from}");
        }
    }

    #[test]
    fn claude_code_event_names_pass_through_unchanged() {
        for name in [
            "SessionStart", "SessionEnd", "UserPromptSubmit", "PreToolUse", "PostToolUse",
            "PostToolUseFailure", "PermissionRequest", "Notification", "Stop", "StopFailure",
            "SubagentStart", "SubagentStop", "", "SomethingNew",
        ] {
            assert_eq!(normalize_event(name), name);
        }
    }

    #[test]
    fn an_antigravity_tool_call_becomes_tool_name_tool_input_and_session_id() {
        let mut map = obj(json!({
            "toolCall": { "name": "example_tool", "args": { "CommandLine": "ls -la", "Cwd": "/work" } },
            "conversationId": "conv-1"
        }));
        normalize_tool_fields(&mut map, "");
        assert_eq!(map["tool_name"], "example_tool");
        // The raw keys stay next to the flat ones the island reads.
        assert_eq!(map["tool_input"], json!({ "CommandLine": "ls -la", "command": "ls -la", "Cwd": "/work" }));
        assert_eq!(map["session_id"], "conv-1");
    }

    #[test]
    fn every_pascal_case_argument_gets_its_flat_twin() {
        let mut map = obj(json!({ "toolCall": { "name": "t", "args": {
            "CommandLine": "a", "FilePath": "b", "Path": "c", "Url": "d", "Query": "e", "Pattern": "f"
        } } }));
        normalize_tool_fields(&mut map, "");
        let input = &map["tool_input"];
        for (flat, want) in [("command", "a"), ("file_path", "b"), ("path", "c"), ("url", "d"), ("query", "e"), ("pattern", "f")] {
            assert_eq!(input[flat], want, "{flat}");
        }
    }

    #[test]
    fn a_payload_that_already_has_tool_name_is_left_exactly_as_it_is() {
        // Claude Code and Gemini CLI's tool events: nothing is added, not even a
        // session id from the environment (the macOS relay behaves the same).
        let before = obj(json!({
            "tool_name": "Bash", "tool_input": { "command": "ls" },
            "toolCall": { "name": "other", "args": { "CommandLine": "x" } },
            "conversationId": "conv-1"
        }));
        let mut after = before.clone();
        normalize_tool_fields(&mut after, "from-env");
        assert_eq!(after, before);
    }

    #[test]
    fn a_plain_tool_string_is_used_when_there_is_no_tool_call() {
        let mut map = obj(json!({ "tool": "read_file" }));
        normalize_tool_fields(&mut map, "");
        assert_eq!(map["tool_name"], "read_file");
        assert!(!map.contains_key("tool_input"));
    }

    #[test]
    fn existing_tool_input_and_session_id_win() {
        let mut map = obj(json!({
            "toolCall": { "name": "t", "args": { "CommandLine": "from-args" } },
            "tool_input": { "command": "kept" },
            "session_id": "kept-id",
            "conversationId": "conv-1"
        }));
        normalize_tool_fields(&mut map, "from-env");
        assert_eq!(map["tool_input"], json!({ "command": "kept" }));
        assert_eq!(map["session_id"], "kept-id");
        assert_eq!(map["tool_name"], "t");
    }

    #[test]
    fn odd_shapes_are_ignored_never_a_panic() {
        for payload in [
            json!({ "toolCall": "not an object" }),
            json!({ "toolCall": { "name": 7, "args": "nope" } }),
            json!({ "toolCall": { "name": "", "args": [1, 2] }, "tool": "" }),
            json!({ "toolCall": null, "conversationId": 5 }),
            json!({}),
        ] {
            let mut map = obj(payload.clone());
            normalize_tool_fields(&mut map, "");
            assert!(!map.contains_key("tool_name"), "{payload}");
            assert!(!map.contains_key("tool_input"), "{payload}");
            assert!(!map.contains_key("session_id"), "{payload}");
        }
    }

    #[test]
    fn the_session_id_comes_from_the_first_key_that_has_one_then_the_environment() {
        let mut map = obj(json!({ "conversationId": "", "conversation_id": "c-2", "sessionId": "s-3" }));
        normalize_tool_fields(&mut map, "env-4");
        assert_eq!(map["session_id"], "c-2");

        let mut map = obj(json!({}));
        normalize_tool_fields(&mut map, "env-4");
        assert_eq!(map["session_id"], "env-4");

        let mut map = obj(json!({}));
        normalize_tool_fields(&mut map, "");
        assert!(!map.contains_key("session_id"));
    }

    #[test]
    fn the_workspace_folder_is_the_first_path_of_the_first_list_that_has_one() {
        assert_eq!(workspace_cwd(&obj(json!({ "workspacePaths": ["/a", "/b"] }))).as_deref(), Some("/a"));
        assert_eq!(
            workspace_cwd(&obj(json!({ "workspacePaths": [], "workspace_roots": ["/r"] }))).as_deref(),
            Some("/r")
        );
        for none in [
            json!({}),
            json!({ "workspacePaths": [] }),
            json!({ "workspacePaths": [7] }),
            json!({ "workspacePaths": [""] }),
            json!({ "workspacePaths": "/a" }),
        ] {
            assert_eq!(workspace_cwd(&obj(none.clone())), None, "{none}");
        }
    }

    #[test]
    fn only_gemini_and_antigravity_get_the_empty_json_answer() {
        assert_eq!(silent_answer("gemini"), Some("{}"));
        assert_eq!(silent_answer("antigravity"), Some("{}"));
        for other in ["", "claude", "codex", "cursor", "my-tool", "Gemini", "gemini-cli"] {
            assert_eq!(silent_answer(other), None, "{other}");
        }
    }
}
```

```rust title="windows/hook/src/main.rs" old
#[cfg(windows)]
mod win;
```

```rust title="windows/hook/src/main.rs" new
mod agents;

#[cfg(windows)]
mod win;
```

```rust title="windows/hook/src/main.rs" old
        assert!(s.ends_with('…'));
    }
}
```

```rust title="windows/hook/src/main.rs" new
        assert!(s.ends_with('…'));
    }

    // ── What the relay forwards for each agent ───────────────────────────────

    /// Runs the pure half of the relay the way an installed hook command would:
    /// the stdin text, the arguments after the program name, a few variables.
    fn shape(stdin: &str, args: &[&str], env: &[(&str, &str)]) -> Option<Event> {
        let args: Vec<String> = args.iter().map(|a| a.to_string()).collect();
        let lookup = |name: &str| {
            env.iter().find(|(k, _)| *k == name).map(|(_, v)| v.to_string()).unwrap_or_default()
        };
        shape_event(stdin.as_bytes().to_vec(), &args, lookup, || Some("/the/working/dir".to_string()))
    }

    fn forwarded(event: &Event) -> serde_json::Value {
        assert!(event.line.ends_with('\n') && event.line.matches('\n').count() == 1, "one line");
        serde_json::from_str(event.line.trim_end()).expect("the line is JSON")
    }

    #[test]
    fn a_gemini_cli_tool_event_is_forwarded_as_the_agents_pre_tool_use() {
        let stdin = r#"{"hook_event_name":"BeforeTool","session_id":"g-1","cwd":"/proj","tool_name":"run_shell_command","tool_input":{"command":"ls"}}"#;
        let event = shape(stdin, &["--agent", "gemini", "PreToolUse"], &[]).unwrap();
        assert_eq!((event.name.as_str(), event.agent.as_str()), ("PreToolUse", "gemini"));
        let sent = forwarded(&event);
        assert_eq!(sent["hook_event_name"], "PreToolUse");
        assert_eq!(sent["nm_agent"], "gemini");
        assert_eq!(sent["session_id"], "g-1");
        assert_eq!(sent["cwd"], "/proj");
        assert_eq!(sent["tool_name"], "run_shell_command");
        assert_eq!(sent["tool_input"]["command"], "ls");
    }

    #[test]
    fn the_event_named_on_the_command_line_is_used_when_the_payload_has_none() {
        let event = shape(r#"{"session_id":"g-1"}"#, &["--agent", "gemini", "Stop"], &[]).unwrap();
        assert_eq!(event.name, "Stop");
        assert_eq!(forwarded(&event)["hook_event_name"], "Stop");
    }

    #[test]
    fn an_antigravity_invocation_event_gets_its_session_and_folder_from_the_payload() {
        let stdin = r#"{"hook_event_name":"PreInvocation","conversationId":"conv-9","workspacePaths":["/proj","/other"]}"#;
        let event = shape(stdin, &["--agent", "antigravity", "PreInvocation"], &[]).unwrap();
        assert_eq!(event.name, "UserPromptSubmit");
        let sent = forwarded(&event);
        assert_eq!(sent["nm_agent"], "antigravity");
        assert_eq!(sent["session_id"], "conv-9");
        assert_eq!(sent["cwd"], "/proj", "workspacePaths beats the working directory");
    }

    #[test]
    fn an_antigravity_tool_call_is_forwarded_the_way_the_island_reads_it() {
        let stdin = r#"{"toolCall":{"name":"example_tool","args":{"FilePath":"/proj/a.rs"}},"conversationId":"conv-9"}"#;
        let event = shape(stdin, &["--agent", "antigravity", "PostToolUse"], &[]).unwrap();
        let sent = forwarded(&event);
        assert_eq!(sent["hook_event_name"], "PostToolUse");
        assert_eq!(sent["tool_name"], "example_tool");
        assert_eq!(sent["tool_input"]["file_path"], "/proj/a.rs");
        assert_eq!(sent["cwd"], "/the/working/dir", "no workspace and no cwd: the working directory");
    }

    #[test]
    fn the_gemini_session_variable_is_the_last_resort() {
        let stdin = r#"{"hook_event_name":"SessionStart"}"#;
        let event = shape(stdin, &["--agent", "gemini", "SessionStart"], &[("GEMINI_SESSION_ID", "env-5")]).unwrap();
        assert_eq!(forwarded(&event)["session_id"], "env-5");
        let event = shape(stdin, &["--agent", "gemini", "SessionStart"], &[]).unwrap();
        assert!(forwarded(&event).get("session_id").is_none());
    }

    #[test]
    fn a_claude_code_event_is_forwarded_as_before() {
        let stdin = r#"{"hook_event_name":"PreToolUse","session_id":"c-1","cwd":"/proj","tool_name":"Bash","tool_input":{"command":"ls"},"tool_response":"big","transcript_path":"/t"}"#;
        let event = shape(stdin, &["PreToolUse"], &[("TERM_PROGRAM", "vscode")]).unwrap();
        assert_eq!((event.name.as_str(), event.agent.as_str()), ("PreToolUse", ""));
        let sent = forwarded(&event);
        assert_eq!(
            sent,
            serde_json::json!({
                "hook_event_name": "PreToolUse", "session_id": "c-1", "cwd": "/proj",
                "tool_name": "Bash", "tool_input": { "command": "ls" },
                "term_program": "vscode", "wt_session": "", "term_session_id": "",
                "vscode_pid": "", "session_pid": ""
            }),
            "no nm_agent, nothing translated, the two big fields dropped"
        );
        // A Claude Code permission request still waits for the island's answer.
        let ask = shape(r#"{"hook_event_name":"PermissionRequest","tool_name":"Bash"}"#, &[], &[]).unwrap();
        assert_eq!(ask.name, "PermissionRequest");
    }

    #[test]
    fn a_payload_the_relay_cannot_use_forwards_nothing() {
        for stdin in ["", "not json", "[1,2]", "\"text\"", "{"] {
            assert!(shape(stdin, &["--agent", "gemini", "Stop"], &[]).is_none(), "{stdin:?}");
        }
        // A BOM in front of good JSON is stripped, not fatal.
        let with_bom = format!("\u{feff}{}", r#"{"hook_event_name":"Stop"}"#);
        assert!(shape(&with_bom, &[], &[]).is_some());
    }

    #[test]
    fn a_dangling_agent_flag_names_no_agent() {
        let event = shape(r#"{"hook_event_name":"Stop"}"#, &["--agent"], &[]).unwrap();
        assert_eq!(event.agent, "");
        assert!(forwarded(&event).get("nm_agent").is_none());
    }

    #[test]
    fn only_gemini_and_antigravity_are_answered_with_json_when_there_is_no_decision() {
        assert_eq!(stdout_for(None, "gemini").as_deref(), Some("{}"));
        assert_eq!(stdout_for(None, "antigravity").as_deref(), Some("{}"));
        assert_eq!(stdout_for(None, ""), None, "Claude Code: silence");
        assert_eq!(stdout_for(None, "codex"), None);
        // A decision from the island is never replaced by the empty answer.
        assert!(stdout_for(Some("allow"), "gemini").unwrap().contains(r#""behavior":"allow""#));
        // An answer nobody recognises is silence for Claude Code, and `{}` for Gemini.
        assert_eq!(stdout_for(Some("maybe"), ""), None);
        assert_eq!(stdout_for(Some("maybe"), "gemini").as_deref(), Some("{}"));
    }
}
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `$CL test -p notchmeow-hook --target-dir $TD`
Expected: FAIL to compile, with errors such as ``error[E0425]: cannot find function `normalize_event` in this scope`` (in `agents.rs`) and ``error[E0425]: cannot find type `Event` in this scope`` (in `main.rs`).

- [ ] **Step 3: Write the implementation**

First the module's code, above its tests.

```rust title="windows/hook/src/agents.rs" old
#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
```

```rust title="windows/hook/src/agents.rs" new
//! Gemini CLI and Antigravity (`agy`) speak their own dialect of hook JSON. This
//! file turns it into the Claude-like shapes the island already handles, the way
//! the macOS relay does (`nm-hook`, embedded in HookServer.swift): the same event
//! table, the same field mapping, the same `{}` answer.
//!
//! Pure functions, no I/O, so the tests run on every OS. Claude Code events pass
//! through untouched: no Claude Code event name is in the table, and the field
//! mapping does nothing for a payload that already carries `tool_name`.

use serde_json::{Map, Value};

/// The `--agent` values of the two agents. They become `nm_agent`, which the island
/// routes on, so the pills are `agent_gemini` and `agent_antigravity`, as on the Mac.
pub const GEMINI: &str = "gemini";
pub const ANTIGRAVITY: &str = "antigravity";

/// Gemini CLI and Antigravity event names to the names the island handles.
/// Anything else, Claude Code's names included, comes back unchanged.
pub fn normalize_event(name: &str) -> &str {
    match name {
        "BeforeTool" | "BeforeToolSelection" => "PreToolUse",
        "AfterTool" | "AfterModel" => "PostToolUse",
        "BeforeAgent" => "UserPromptSubmit",
        "AfterAgent" => "Stop",
        "startup" => "SessionStart",
        "exit" => "SessionEnd",
        "PreInvocation" => "UserPromptSubmit",
        "PostInvocation" => "PostToolUse",
        other => other,
    }
}

/// Antigravity's PascalCase tool arguments and the keys the island reads.
const ARG_ALIASES: [(&str, &str); 6] = [
    ("CommandLine", "command"),
    ("FilePath", "file_path"),
    ("Path", "path"),
    ("Url", "url"),
    ("Query", "query"),
    ("Pattern", "pattern"),
];

/// Where Antigravity and Gemini CLI may keep the session id.
const SESSION_KEYS: [&str; 4] = ["conversationId", "conversation_id", "sessionId", "GEMINI_SESSION_ID"];

/// Antigravity wraps a tool call as `toolCall: {name, args}` and names the session
/// `conversationId`. Maps both onto `tool_name`, `tool_input` and `session_id`.
/// Fields already there win, and a payload that already has `tool_name` (Claude
/// Code, Gemini CLI's tool events) is left exactly as it is. `env_session_id` is
/// the value of `GEMINI_SESSION_ID`, the last place to look.
pub fn normalize_tool_fields(map: &mut Map<String, Value>, env_session_id: &str) {
    if map.contains_key("tool_name") {
        return;
    }
    let tool = map.get("toolCall").cloned().unwrap_or(Value::Null);
    let name = tool
        .get("name")
        .and_then(Value::as_str)
        .filter(|s| !s.is_empty())
        .or_else(|| map.get("tool").and_then(Value::as_str).filter(|s| !s.is_empty()))
        .map(str::to_string);
    if let Some(name) = name {
        map.insert("tool_name".into(), Value::String(name));
    }
    if !map.contains_key("tool_input") {
        if let Some(args) = tool.get("args").and_then(Value::as_object) {
            let mut flat = args.clone();
            for (from, to) in ARG_ALIASES {
                if let Some(value) = args.get(from) {
                    flat.insert(to.into(), value.clone());
                }
            }
            map.insert("tool_input".into(), Value::Object(flat));
        }
    }
    if !map.contains_key("session_id") {
        let id = SESSION_KEYS
            .iter()
            .find_map(|key| map.get(*key).and_then(Value::as_str).filter(|s| !s.is_empty()))
            .or_else(|| Some(env_session_id).filter(|s| !s.is_empty()))
            .map(str::to_string);
        if let Some(id) = id {
            map.insert("session_id".into(), Value::String(id));
        }
    }
}

/// Antigravity reports the folder it works in as `workspacePaths[0]`, and some
/// agents as `workspace_roots[0]`. Used when the payload has no `cwd`.
pub fn workspace_cwd(map: &Map<String, Value>) -> Option<String> {
    ["workspacePaths", "workspace_roots"]
        .iter()
        .filter_map(|key| map.get(*key).and_then(Value::as_array))
        .find(|paths| !paths.is_empty())
        .and_then(|paths| paths[0].as_str())
        .filter(|s| !s.is_empty())
        .map(str::to_string)
}

/// Gemini CLI and Antigravity read a hook's stdout as JSON, and `{}` is their
/// "no decision". Claude Code and every other agent want silence.
pub fn silent_answer(agent: &str) -> Option<&'static str> {
    matches!(agent, GEMINI | ANTIGRAVITY).then_some("{}")
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
```

Then the relay. Each pair below is one edit of `windows/hook/src/main.rs`; the original text is quoted exactly.

```rust title="windows/hook/src/main.rs" old
//! Usage: `notchmeow-hook <EventName>` (the name is also read from the JSON).
```

```rust title="windows/hook/src/main.rs" new
//! Usage: `notchmeow-hook [--agent <name>] <EventName>` (the name is also read from the JSON).
//!
//! Gemini CLI and Antigravity (`--agent gemini` / `--agent antigravity`) send
//! their own event names and field shapes; `agents.rs` translates them, and these
//! two agents read stdout as JSON, so they are answered `{}` ("no decision").
```

```rust title="windows/hook/src/main.rs" old
fn main() {
    let Some((payload, event)) = read_event() else { std::process::exit(0) };
```

```rust title="windows/hook/src/main.rs" new
/// What the relay forwards, and what it needs to know about it afterwards.
struct Event {
    /// The payload as one newline-terminated JSON line.
    line: String,
    /// The event name, Gemini CLI and Antigravity names already translated.
    name: String,
    /// The `--agent` value; empty for Claude Code.
    agent: String,
}

fn main() {
    let Some(Event { line: payload, name: event, agent }) = read_event() else { std::process::exit(0) };
```

```rust title="windows/hook/src/main.rs" old
    if let Ok(Some(decision)) = rx.recv_timeout(budget) {
        if let Some(json) = decision_json(&decision) {
            let mut out = std::io::stdout();
            let _ = writeln!(out, "{json}");
            let _ = out.flush();
        }
    }
    // Nothing printed: Claude Code asks in the terminal, as if we were not here.
    std::process::exit(0);
}
```

```rust title="windows/hook/src/main.rs" new
    let decision = rx.recv_timeout(budget).ok().flatten();
    if let Some(json) = stdout_for(decision.as_deref(), &agent) {
        let mut out = std::io::stdout();
        let _ = writeln!(out, "{json}");
        let _ = out.flush();
    }
    // Nothing printed: Claude Code asks in the terminal, as if we were not here.
    std::process::exit(0);
}

/// What goes to stdout: the island's decision when there is one. Without it,
/// nothing, so Claude Code asks in the terminal; Gemini CLI and Antigravity
/// insist on JSON, so they get `{}`.
fn stdout_for(decision: Option<&str>, agent: &str) -> Option<String> {
    decision
        .and_then(decision_json)
        .or_else(|| agents::silent_answer(agent).map(str::to_string))
}
```

```rust title="windows/hook/src/main.rs" old
/// Reads stdin and returns the payload to forward plus the event name.
fn read_event() -> Option<(String, String)> {
    let mut raw = Vec::new();
    if std::io::stdin().read_to_end(&mut raw).is_err() || raw.is_empty() {
        return None;
    }
    // Some shells hand us a UTF-8 BOM; serde_json would choke on it.
```

```rust title="windows/hook/src/main.rs" new
/// Reads stdin and returns the event to forward.
fn read_event() -> Option<Event> {
    let mut raw = Vec::new();
    if std::io::stdin().read_to_end(&mut raw).is_err() || raw.is_empty() {
        return None;
    }
    let args: Vec<String> = std::env::args().skip(1).collect();
    shape_event(
        raw,
        &args,
        |var| std::env::var(var).unwrap_or_default(),
        || std::env::current_dir().ok().map(|dir| dir.to_string_lossy().to_string()),
    )
}

/// The pure half of `read_event`: the bytes from stdin, the arguments after the
/// program name, the environment and the working directory in, the event out.
fn shape_event(
    mut raw: Vec<u8>,
    args: &[String],
    env: impl Fn(&str) -> String,
    current_dir: impl FnOnce() -> Option<String>,
) -> Option<Event> {
    // Some shells hand us a UTF-8 BOM; serde_json would choke on it.
```

```rust title="windows/hook/src/main.rs" old
        let mut it = std::env::args().skip(1);
        while let Some(arg) = it.next() {
            if arg == "--agent" {
                agent = it.next().unwrap_or_default();
            } else if arg_event.is_empty() {
                arg_event = arg;
            }
        }
```

```rust title="windows/hook/src/main.rs" new
        let mut it = args.iter();
        while let Some(arg) = it.next() {
            if arg == "--agent" {
                agent = it.next().cloned().unwrap_or_default();
            } else if arg_event.is_empty() {
                arg_event = arg.clone();
            }
        }
```

```rust title="windows/hook/src/main.rs" old
    if !agent.is_empty() {
        map.insert("nm_agent".into(), serde_json::Value::String(agent));
    }
    let event = map
        .get("hook_event_name")
        .and_then(|v| v.as_str())
        .map(str::to_string)
        .filter(|s| !s.is_empty())
        .unwrap_or(arg_event);
    map.insert("hook_event_name".into(), serde_json::Value::String(event.clone()));
```

```rust title="windows/hook/src/main.rs" new
    if !agent.is_empty() {
        map.insert("nm_agent".into(), serde_json::Value::String(agent.clone()));
    }
    let raw_event = map
        .get("hook_event_name")
        .and_then(|v| v.as_str())
        .map(str::to_string)
        .filter(|s| !s.is_empty())
        .unwrap_or(arg_event);
    // Gemini CLI and Antigravity name their events differently; Claude Code's
    // names pass through unchanged.
    let event = agents::normalize_event(&raw_event).to_string();
    map.insert("hook_event_name".into(), serde_json::Value::String(event.clone()));
    // ...and shape their tool calls and sessions differently. No-op for Claude Code.
    agents::normalize_tool_fields(map, &env("GEMINI_SESSION_ID"));
```

```rust title="windows/hook/src/main.rs" old
    if cwd_missing {
        if let Ok(cwd) = std::env::current_dir() {
            map.insert(
                "cwd".into(),
                serde_json::Value::String(cwd.to_string_lossy().to_string()),
            );
        }
    }
```

```rust title="windows/hook/src/main.rs" new
    if cwd_missing {
        if let Some(cwd) = agents::workspace_cwd(map).or_else(current_dir) {
            map.insert("cwd".into(), serde_json::Value::String(cwd));
        }
    }
```

```rust title="windows/hook/src/main.rs" old
        if !map.contains_key(key) {
            let value = std::env::var(var).unwrap_or_default();
            map.insert(key.into(), serde_json::Value::String(value));
        }
```

```rust title="windows/hook/src/main.rs" new
        if !map.contains_key(key) {
            map.insert(key.into(), serde_json::Value::String(env(var)));
        }
```

```rust title="windows/hook/src/main.rs" old
    let mut line = payload.to_string();
    line.push('\n');
    Some((line, event))
}
```

```rust title="windows/hook/src/main.rs" new
    let mut line = payload.to_string();
    line.push('\n');
    Some(Event { line, name: event, agent })
}
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `$CL test -p notchmeow-hook --target-dir $TD`
Expected: PASS, `test result: ok. 23 passed` (the 3 existing tests, 11 in `agents::tests` and 9 new ones in `tests`), and no `warning:` line from the compiler.

- [ ] **Step 5: Smoke-test the built relay**

The unit tests cover the shaping; this runs the real binary against a fake island, with the app closed and open. Build it, then run the script inside the container (the relay talks to `$XDG_RUNTIME_DIR/notchmeow.sock`, so the script makes a private directory of its own; nothing touches the real app or its log):

```bash
$CL build --release -p notchmeow-hook --target-dir $TD
mkdir -p "${TMPDIR:-/tmp}/port-gemini-agy"
cat > "${TMPDIR:-/tmp}/port-gemini-agy/relay-smoke.py" <<'PY'
import json, os, socket, subprocess, tempfile, threading, time

RELAY = "/repo/windows/target/port-gemini-agy/release/notchmeow-hook"
run_dir = tempfile.mkdtemp()
os.chmod(run_dir, 0o700)          # the relay only talks to a private runtime directory
sock_path = os.path.join(run_dir, "notchmeow.sock")
env = dict(os.environ, XDG_RUNTIME_DIR=run_dir, HOME=run_dir)
env.pop("GEMINI_SESSION_ID", None)

def run(args, stdin):
    t0 = time.time()
    p = subprocess.run([RELAY, *args], input=stdin.encode(), capture_output=True, env=env, timeout=10)
    return p.returncode, p.stdout.decode(), time.time() - t0

# 1. The app is closed: nothing listens. Gemini CLI gets `{}` at once, Claude Code gets silence. Both exit 0.
code, out, took = run(["--agent", "gemini", "PreToolUse"], '{"hook_event_name":"BeforeTool","tool_name":"x","tool_input":{}}')
assert (code, out) == (0, "{}\n") and took < 1.5, (code, out, took)
code, out, took = run(["--agent", "antigravity", "Stop"], '{"conversationId":"c"}')
assert (code, out) == (0, "{}\n") and took < 1.5, (code, out, took)
code, out, took = run(["PreToolUse"], '{"hook_event_name":"PreToolUse","tool_name":"Bash"}')
assert (code, out) == (0, "") and took < 1.5, (code, out, took)
code, out, took = run(["--agent", "gemini", "Stop"], "not json")
assert (code, out) == (0, ""), (code, out)
print("app closed: ok")

# 2. The app is open: a fake island receives one line per event.
server = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
server.bind(sock_path)
server.listen(8)
lines = []
def accept():
    while True:
        try:
            conn, _ = server.accept()
        except OSError:
            return
        data = b""
        while not data.endswith(b"\n"):
            chunk = conn.recv(4096)
            if not chunk:
                break
            data += chunk
        lines.append(json.loads(data))
        conn.close()
threading.Thread(target=accept, daemon=True).start()

code, out, _ = run(["--agent", "gemini", "PreToolUse"],
    '{"hook_event_name":"BeforeTool","session_id":"g-1","cwd":"/proj","tool_name":"run_shell_command","tool_input":{"command":"ls"}}')
assert (code, out) == (0, "{}\n")
code, out, _ = run(["--agent", "antigravity", "PostToolUse"],
    '{"toolCall":{"name":"example_tool","args":{"CommandLine":"ls"}},"conversationId":"conv-9","workspacePaths":["/proj"]}')
assert (code, out) == (0, "{}\n")
code, out, _ = run(["PreToolUse"], '{"hook_event_name":"PreToolUse","session_id":"c-1","cwd":"/proj","tool_name":"Bash","tool_input":{"command":"ls"}}')
assert (code, out) == (0, "")
time.sleep(0.3)
assert len(lines) == 3, lines
gem, agy, claude = lines
assert (gem["hook_event_name"], gem["nm_agent"], gem["tool_name"], gem["session_id"]) == ("PreToolUse", "gemini", "run_shell_command", "g-1"), gem
assert (agy["hook_event_name"], agy["nm_agent"], agy["tool_name"], agy["session_id"], agy["cwd"]) == ("PostToolUse", "antigravity", "example_tool", "conv-9", "/proj"), agy
assert agy["tool_input"]["command"] == "ls", agy
assert "nm_agent" not in claude and claude["hook_event_name"] == "PreToolUse" and claude["tool_name"] == "Bash", claude
print("app open: ok")
PY
docker run --rm -i --pull=never \
  -v "$PWD":/repo -v notchmeow-linux-target:/repo/windows/target \
  -w /repo/windows notchmeow-linux-dev python3 - < "${TMPDIR:-/tmp}/port-gemini-agy/relay-smoke.py"
```

Expected: two lines, `app closed: ok` and `app open: ok`, and exit status 0. If an assertion fails, Python prints the offending value: fix the relay, not the script.

- [ ] **Step 6: Commit**

```bash
git add windows/hook/src/agents.rs windows/hook/src/main.rs
git commit -m "feat(windows): the relay translates Gemini CLI and Antigravity events

Ported by hand from upstream's n22-gemini branch, matched to the Mac's nm-hook:
event names, toolCall and conversationId fields, workspacePaths for the folder,
and an empty JSON answer for the two agents. Claude Code events are unchanged.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: The installers for both agents

**Files:**
- Create: `windows/src-tauri/src/agent_hooks.rs`
- Modify: `windows/src-tauri/src/hooks.rs`, `windows/src-tauri/src/lib.rs`
- Test: `agent_hooks.rs` (`#[cfg(test)]`), and the existing tests of `hooks.rs`, which guard the extraction

**Interfaces:**
- Consumes: Task 1's wire contract (`<relay> --agent <tag> <Event>`); from `hooks.rs`: `HookStatus`, `HookPreview`, `stamp()`, and, made `pub(crate)` here, `MARKER`, `parse_settings`, `sh_quote` (Unix only), `pretty`, `fingerprint`, `unified_diff`; and `replace_file`, extracted here from `hooks::write`.
- Produces `agent_hooks.rs`: `enum Agent { Gemini, Antigravity }` with `Agent::from_tag(tag: &str) -> Result<Agent, String>` (`"gemini"`, `"antigravity"`, anything else is an error) and `path(self) -> PathBuf`; `status(Agent) -> HookStatus`; `preview(Agent, install: bool) -> Result<HookPreview, String>`; `write(Agent, install: bool, fingerprint: &str) -> Result<String, String>`, which returns the backup's path, or an empty string when there was no file to back up. `HookPreview.backup` is likewise empty when the file does not exist yet.
- Produces in `lib.rs`: Tauri commands `agent_hooks_status(agent: String) -> Result<HookStatus, String>`, `agent_hooks_preview(agent: String, install: bool) -> Result<HookPreview, String>`, `agent_hooks_apply(agent: String, install: bool, fingerprint: String) -> Result<String, String>`.

- [ ] **Step 1: Write the failing tests**

The tests point every file operation at a temporary directory (`preview_at`, `write_at`, `status_at` take the path), and the two merge functions take the command builder as an argument (`CommandFor`, a fixed string in the tests). So no test depends on the home directory, which `hooks.rs`'s own filesystem test changes for the whole process while the tests run side by side. Create the module with its tests only, and declare it.

```rust title="windows/src-tauri/src/agent_hooks.rs"
#[cfg(test)]
mod tests {
    use super::*;

    // The merge functions take the command builder, so these tests do not depend on
    // where this machine keeps the relay (hooks.rs's own test changes the home
    // directory, process-wide, while the tests run side by side).
    fn fake(agent: &str, event: &str) -> String {
        format!("{} --agent {agent} {event}", hooks::MARKER)
    }

    fn gemini_command(event: &str) -> String {
        fake("gemini", event)
    }

    /// A temp directory of its own per test; nothing here touches the real home.
    fn temp_dir(name: &str) -> PathBuf {
        let dir = std::env::temp_dir().join(format!("notchmeow-agent-hooks-{name}-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        dir
    }

    fn foreign_gemini() -> Value {
        json!({
            "model": "gemini-3-pro",
            "theme": "dark",
            "mcpServers": { "x": { "command": "x" } },
            "hooks": {
                "BeforeTool": [
                    { "matcher": "write_file", "hooks": [{ "type": "command", "command": "someone-elses-tool", "timeout": 1000 }] }
                ],
                "Notification": [
                    { "hooks": [{ "type": "command", "command": "keep-me" }] }
                ]
            }
        })
    }

    // ── Gemini CLI ───────────────────────────────────────────────────────────

    #[test]
    fn installing_gemini_hooks_adds_the_six_events_with_the_macs_timeouts() {
        let after = merged_gemini(&json!({}), &fake).unwrap();
        let hooks = after["hooks"].as_object().unwrap();
        assert_eq!(hooks.len(), 6);
        for (event, normalized, timeout) in [
            ("SessionStart", "SessionStart", 10_000),
            ("SessionEnd", "SessionEnd", 10_000),
            ("BeforeTool", "PreToolUse", 5_000),
            ("AfterTool", "PostToolUse", 5_000),
            ("BeforeAgent", "UserPromptSubmit", 5_000),
            ("AfterAgent", "Stop", 5_000),
        ] {
            assert_eq!(
                hooks[event],
                json!([{ "matcher": "*", "hooks": [{
                    "type": "command", "command": gemini_command(normalized), "timeout": timeout
                }] }]),
                "{event}"
            );
        }
        assert!(!hooks.contains_key("AfterModel"), "it fires on every chunk and would flood the island");
        assert!(gemini_command("Stop").contains("--agent gemini Stop"));
    }

    #[test]
    fn gemini_install_keeps_every_other_setting_and_every_foreign_hook() {
        let existing = foreign_gemini();
        let after = merged_gemini(&existing, &fake).unwrap();
        assert_eq!(after["model"], "gemini-3-pro");
        assert_eq!(after["theme"], "dark");
        assert_eq!(after["mcpServers"], existing["mcpServers"]);
        let before_tool = after["hooks"]["BeforeTool"].as_array().unwrap();
        assert_eq!(before_tool.len(), 2, "the other tool's group and ours");
        assert_eq!(before_tool[0], existing["hooks"]["BeforeTool"][0]);
        assert_eq!(after["hooks"]["Notification"], existing["hooks"]["Notification"]);
    }

    #[test]
    fn gemini_install_twice_is_install_once_and_uninstall_restores_the_file() {
        for existing in [json!({}), json!({ "model": "m" }), foreign_gemini()] {
            let once = merged_gemini(&existing, &fake).unwrap();
            assert_eq!(merged_gemini(&once, &fake).unwrap(), once, "no duplicates");
            assert_eq!(without_gemini(&once).unwrap(), existing, "uninstall puts it back exactly");
        }
    }

    #[test]
    fn a_foreign_hook_in_the_same_group_as_ours_survives_both_ways() {
        let existing = json!({ "hooks": { "BeforeTool": [{ "matcher": "*", "hooks": [
            { "type": "command", "command": "foreign" },
            { "type": "command", "command": gemini_command("PreToolUse"), "timeout": 5000 }
        ] }] } });
        let expected = json!([{ "matcher": "*", "hooks": [{ "type": "command", "command": "foreign" }] }]);
        assert_eq!(without_gemini(&existing).unwrap()["hooks"]["BeforeTool"], expected);
        let reinstalled = merged_gemini(&existing, &fake).unwrap();
        assert_eq!(reinstalled["hooks"]["BeforeTool"][0], expected[0]);
        assert_eq!(reinstalled["hooks"]["BeforeTool"].as_array().unwrap().len(), 2);
    }

    #[test]
    fn an_older_flat_entry_is_removed_and_a_foreign_flat_entry_is_kept() {
        let existing = json!({ "hooks": { "AfterTool": [
            { "type": "command", "command": gemini_command("PostToolUse") },
            { "type": "command", "command": "foreign-flat" }
        ] } });
        let cleaned = without_gemini(&existing).unwrap();
        assert_eq!(cleaned["hooks"]["AfterTool"], json!([{ "type": "command", "command": "foreign-flat" }]));
        assert_eq!(merged_gemini(&existing, &fake).unwrap()["hooks"]["AfterTool"][0], cleaned["hooks"]["AfterTool"][0]);
    }

    #[test]
    fn an_empty_event_or_group_that_is_not_ours_is_left_alone() {
        let existing = json!({ "hooks": { "SessionStart": [], "Stop": [{ "hooks": [] }] } });
        assert_eq!(without_gemini(&existing).unwrap(), existing);
    }

    #[test]
    fn unexpected_shapes_are_refused_and_never_replaced() {
        for existing in [
            json!({ "hooks": [] }),
            json!({ "hooks": "x" }),
            json!({ "hooks": null }),
            json!({ "hooks": { "BeforeTool": {} } }),
            json!({ "hooks": { "SessionStart": "x" } }),
            json!({ "hooks": { "AfterAgent": null } }),
            json!({ "hooks": { "SessionEnd": [1, 2] } }),
        ] {
            let err = merged_gemini(&existing, &fake).unwrap_err();
            assert!(err.contains("unexpected type") && err.contains("has not touched it"), "{existing}: {err}");
        }
        // Uninstall refuses the same top-level shapes, and leaves odd events alone.
        assert!(without_gemini(&json!({ "hooks": [] })).is_err());
        let odd = json!({ "hooks": { "Custom": { "a": 1 }, "Other": "x" } });
        assert_eq!(without_gemini(&odd).unwrap(), odd);
    }

    #[test]
    fn gemini_detection_needs_our_relay_and_the_gemini_tag() {
        assert!(!installed_in(Agent::Gemini, &json!({})));
        assert!(!installed_in(Agent::Gemini, &foreign_gemini()));
        assert!(installed_in(Agent::Gemini, &merged_gemini(&json!({}), &fake).unwrap()));
        // Our relay for another agent is not Gemini CLI's hook.
        let other = json!({ "hooks": { "Stop": [{ "hooks": [{ "command": fake("codex", "Stop") }] }] } });
        assert!(!installed_in(Agent::Gemini, &other));
        // An older flat entry counts too.
        let flat = json!({ "hooks": { "Stop": [{ "command": gemini_command("Stop") }] } });
        assert!(installed_in(Agent::Gemini, &flat));
    }

    // ── Antigravity ──────────────────────────────────────────────────────────

    #[test]
    fn installing_antigravity_hooks_adds_five_events_under_the_notchmeow_key() {
        let after = merged_agy(&json!({}), &fake);
        let ours = after[AGY_KEY].as_object().unwrap();
        assert_eq!(ours.len(), 5);
        let hook = |event: &str| json!({
            "type": "command", "command": fake("antigravity", event), "timeout": 10
        });
        // The tool events take a matcher group; the lifecycle events a direct handler.
        for event in ["PreToolUse", "PostToolUse"] {
            assert_eq!(ours[event], json!([{ "matcher": "*", "hooks": [hook(event)] }]), "{event}");
        }
        for event in ["PreInvocation", "PostInvocation", "Stop"] {
            assert_eq!(ours[event], json!([hook(event)]), "{event}");
        }
        assert!(fake("antigravity", "Stop").contains("--agent antigravity Stop"));
    }

    #[test]
    fn antigravity_install_and_uninstall_touch_only_the_notchmeow_key() {
        let existing = json!({ "mine": { "PreToolUse": [{ "command": "x" }] }, "other": 1 });
        let once = merged_agy(&existing, &fake);
        assert_eq!(once["mine"], existing["mine"]);
        assert_eq!(once["other"], 1);
        assert_eq!(merged_agy(&once, &fake), once, "install twice is install once");
        assert_eq!(without_agy(&once), existing, "uninstall puts it back exactly");
        assert_eq!(without_agy(&existing), existing, "nothing to remove is no change");
    }

    #[test]
    fn antigravity_detection_looks_only_under_the_notchmeow_key() {
        assert!(!installed_in(Agent::Antigravity, &json!({})));
        assert!(!installed_in(Agent::Antigravity, &json!({ "mine": { "x": hooks::MARKER } })));
        assert!(installed_in(Agent::Antigravity, &merged_agy(&json!({}), &fake)));
        assert!(!installed_in(Agent::Antigravity, &json!({ AGY_KEY: { "Stop": [{ "command": "foreign" }] } })));
    }

    // ── The command ──────────────────────────────────────────────────────────

    #[test]
    fn a_windows_command_is_a_quoted_path_in_forward_slashes() {
        assert_eq!(
            windows_command(r"C:\Users\Zoé Smith\AppData\Local\NotchMeow\bin\notchmeow-hook.exe", "gemini", "PreToolUse"),
            r#""C:/Users/Zoé Smith/AppData/Local/NotchMeow/bin/notchmeow-hook.exe" --agent gemini PreToolUse"#
        );
    }

    #[cfg(unix)]
    #[test]
    fn a_unix_command_is_one_single_quoted_word_whatever_the_path_holds() {
        assert_eq!(
            unix_command("/home/a b/.local/share/notchmeow/bin/notchmeow-hook", "antigravity", "Stop"),
            "'/home/a b/.local/share/notchmeow/bin/notchmeow-hook' --agent antigravity Stop"
        );
        assert_eq!(unix_command("/h/it's/$(id)/hook", "gemini", "Stop"), r"'/h/it'\''s/$(id)/hook' --agent gemini Stop");
    }

    #[test]
    fn the_relay_command_runs_the_relay_this_app_installs() {
        let command = relay_command("gemini", "PreToolUse");
        assert!(command.contains(hooks::MARKER), "{command}");
        assert!(command.ends_with(" --agent gemini PreToolUse"), "{command}");
    }

    // ── The files ────────────────────────────────────────────────────────────

    #[test]
    fn the_agents_files_are_where_the_mac_puts_them() {
        assert_eq!(Agent::from_tag("gemini"), Ok(Agent::Gemini));
        assert_eq!(Agent::from_tag("antigravity"), Ok(Agent::Antigravity));
        for bad in ["", "claude", "codex", "Gemini", "../x"] {
            assert!(Agent::from_tag(bad).is_err(), "{bad}");
        }
        let gemini = Agent::Gemini.path();
        let agy = Agent::Antigravity.path();
        assert!(gemini.ends_with(Path::new(".gemini").join("settings.json")));
        assert!(agy.ends_with(Path::new(".gemini").join("config").join("hooks.json")));
    }

    #[test]
    fn installing_backs_up_keeps_a_bom_files_other_settings_and_refuses_a_changed_file() {
        let dir = temp_dir("gemini");
        let path = dir.join(".gemini").join("settings.json");
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        // The way PowerShell 5 writes it: UTF-8 with a BOM.
        let mut original = vec![0xEF, 0xBB, 0xBF];
        original.extend_from_slice(serde_json::to_string(&foreign_gemini()).unwrap().as_bytes());
        std::fs::write(&path, &original).unwrap();

        let shown = preview_at(Agent::Gemini, &path, true).expect("a BOM must not stop the preview");
        assert!(shown.diff.contains(hooks::MARKER), "the diff must show what changes");
        assert!(shown.diff.contains("+ "), "and as added lines");
        assert!(shown.backup.contains("settings.json.bak-"), "{}", shown.backup);
        let backup = write_at(Agent::Gemini, &path, true, &shown.fingerprint).expect("install should succeed");
        assert_eq!(std::fs::read(&backup).unwrap(), original, "the backup holds the original bytes");

        let after: Value = serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
        assert_eq!(after["model"], "gemini-3-pro");
        assert_eq!(after["hooks"]["Notification"], foreign_gemini()["hooks"]["Notification"]);
        assert!(installed_in(Agent::Gemini, &after));
        assert!(status_at(Agent::Gemini, &path).installed);

        // A file that moved since the preview is refused, and left alone.
        let stale = preview_at(Agent::Gemini, &path, false).unwrap();
        std::fs::write(&path, br#"{"model":"someone-else-edited-this"}"#).unwrap();
        let err = write_at(Agent::Gemini, &path, false, &stale.fingerprint).unwrap_err();
        assert!(err.contains("changed since the preview"), "got: {err}");
        assert_eq!(std::fs::read(&path).unwrap(), br#"{"model":"someone-else-edited-this"}"#);

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_file_we_cannot_use_is_refused_before_any_backup_or_write() {
        let dir = temp_dir("refuse");
        let path = dir.join(".gemini").join("settings.json");
        std::fs::create_dir_all(path.parent().unwrap()).unwrap();
        for (bad, why) in [
            (&b"{ broken"[..], "isn't valid JSON"),
            (&b"[1,2]"[..], "isn't a JSON object"),
            (&br#"{"hooks":[]}"#[..], "unexpected type"),
        ] {
            std::fs::write(&path, bad).unwrap();
            for install in [true, false] {
                let err = preview_at(Agent::Gemini, &path, install).err().expect("a refusal");
                assert!(err.contains(why), "preview: {err}");
                // Even holding the right fingerprint, nothing is written.
                let err = write_at(Agent::Gemini, &path, install, &fingerprint_of(&path)).unwrap_err();
                assert!(err.contains(why), "write: {err}");
                assert_eq!(std::fs::read(&path).unwrap(), bad, "untouched");
                assert_eq!(std::fs::read_dir(path.parent().unwrap()).unwrap().count(), 1, "no backup was taken");
            }
        }
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn a_first_install_creates_the_folders_and_a_refusal_creates_nothing() {
        let dir = temp_dir("first");
        let path = dir.join(".gemini").join("config").join("hooks.json");

        // Nothing to remove: say so, and create nothing.
        let err = preview_at(Agent::Antigravity, &path, false).err().expect("a refusal");
        assert_eq!(err, "No Antigravity hooks to remove.");
        assert!(!dir.join(".gemini").exists());

        let shown = preview_at(Agent::Antigravity, &path, true).unwrap();
        assert_eq!(shown.fingerprint, hooks::fingerprint(b""), "a file that is not there is an empty one");
        assert_eq!(shown.backup, "", "there is nothing to back up yet");
        let backup = write_at(Agent::Antigravity, &path, true, &shown.fingerprint).unwrap();
        assert_eq!(backup, "");
        let written: Value = serde_json::from_slice(&std::fs::read(&path).unwrap()).unwrap();
        assert!(installed_in(Agent::Antigravity, &written));
        assert!(written[AGY_KEY].is_object(), "everything is under the notchmeow key");
        assert!(status_at(Agent::Antigravity, &path).installed);

        // And back out again: only our key goes.
        let shown = preview_at(Agent::Antigravity, &path, false).unwrap();
        write_at(Agent::Antigravity, &path, false, &shown.fingerprint).unwrap();
        assert_eq!(serde_json::from_slice::<Value>(&std::fs::read(&path).unwrap()).unwrap(), json!({}));
        assert!(!status_at(Agent::Antigravity, &path).installed);

        let _ = std::fs::remove_dir_all(&dir);
    }

    #[test]
    fn uninstall_with_no_gemini_file_says_so_and_creates_nothing() {
        let dir = temp_dir("nofile");
        let path = dir.join(".gemini").join("settings.json");
        assert_eq!(preview_at(Agent::Gemini, &path, false).err().expect("a refusal"), "No Gemini CLI hooks to remove.");
        assert!(!dir.join(".gemini").exists());
        let _ = std::fs::remove_dir_all(&dir);
    }

    #[cfg(unix)]
    #[test]
    fn a_symlinked_config_file_stays_a_symlink_and_its_target_is_updated() {
        let dir = temp_dir("symlink");
        let target = dir.join("dotfiles-settings.json");
        let link = dir.join(".gemini").join("settings.json");
        std::fs::create_dir_all(link.parent().unwrap()).unwrap();
        std::fs::write(&target, br#"{"model":"m"}"#).unwrap();
        std::os::unix::fs::symlink(&target, &link).unwrap();

        let shown = preview_at(Agent::Gemini, &link, true).unwrap();
        write_at(Agent::Gemini, &link, true, &shown.fingerprint).unwrap();

        assert!(std::fs::symlink_metadata(&link).unwrap().file_type().is_symlink(), "the link survives");
        let written: Value = serde_json::from_slice(&std::fs::read(&target).unwrap()).unwrap();
        assert!(installed_in(Agent::Gemini, &written), "the file it points at got the hooks");
        let _ = std::fs::remove_dir_all(&dir);
    }
}
```

```rust title="windows/src-tauri/src/lib.rs" old
mod ai;
mod files;
```

```rust title="windows/src-tauri/src/lib.rs" new
mod agent_hooks;
mod ai;
mod files;
```

- [ ] **Step 2: Run the tests to verify they fail**

Run: `$CL test -p notchmeow --target-dir $TD -- agent_hooks`
Expected: FAIL to compile, with errors such as ``error[E0433]: cannot find type `Agent` in this scope`` and ``error[E0425]: cannot find function `merged_gemini` in this scope``.

- [ ] **Step 3: Write the implementation**

First `hooks.rs`: six helpers become visible to the new module, and the tail of `write` moves into `replace_file` (same code, same order; the symlink and permission handling is not rewritten).

```rust title="windows/src-tauri/src/hooks.rs" old
/// Marker that identifies a NotchMeow entry inside settings.json.
const MARKER: &str = "notchmeow-hook";
```

```rust title="windows/src-tauri/src/hooks.rs" new
/// Marker that identifies a NotchMeow entry inside settings.json.
pub(crate) const MARKER: &str = "notchmeow-hook";
```

```rust title="windows/src-tauri/src/hooks.rs" old
fn parse_settings(bytes: &[u8], path: &str) -> Result<Value, String> {
```

```rust title="windows/src-tauri/src/hooks.rs" new
pub(crate) fn parse_settings(bytes: &[u8], path: &str) -> Result<Value, String> {
```

```rust title="windows/src-tauri/src/hooks.rs" old
#[cfg(unix)]
fn sh_quote(s: &str) -> String {
```

```rust title="windows/src-tauri/src/hooks.rs" new
#[cfg(unix)]
pub(crate) fn sh_quote(s: &str) -> String {
```

```rust title="windows/src-tauri/src/hooks.rs" old
fn pretty(v: &Value) -> String {
```

```rust title="windows/src-tauri/src/hooks.rs" new
pub(crate) fn pretty(v: &Value) -> String {
```

```rust title="windows/src-tauri/src/hooks.rs" old
fn fingerprint(bytes: &[u8]) -> String {
```

```rust title="windows/src-tauri/src/hooks.rs" new
pub(crate) fn fingerprint(bytes: &[u8]) -> String {
```

```rust title="windows/src-tauri/src/hooks.rs" old
fn unified_diff(before: &str, after: &str) -> String {
```

```rust title="windows/src-tauri/src/hooks.rs" new
pub(crate) fn unified_diff(before: &str, after: &str) -> String {
```

```rust title="windows/src-tauri/src/hooks.rs" old
    let mut text = pretty(&next);
    text.push('\n');

    // A dotfiles setup often makes settings.json a symlink: write to the file it
    // points at, so the link survives the rename below.
    #[cfg(unix)]
    let path = std::fs::canonicalize(&path).unwrap_or(path);

    // Write beside the target and rename over it: a crash or a full disk leaves
    // the original settings.json intact rather than half a file.
    let temp = path.with_extension(format!("json.notchmeow-{}", std::process::id()));
    if let Err(err) = write_like(&temp, &path, text.as_bytes()) {
        let _ = std::fs::remove_file(&temp);
        return Err(format!("write failed: {err}"));
    }
    if let Err(err) = std::fs::rename(&temp, &path) {
        let _ = std::fs::remove_file(&temp);
        return Err(format!("write failed: {err}"));
    }
    Ok(backup.to_string_lossy().to_string())
}
```

```rust title="windows/src-tauri/src/hooks.rs" new
    let mut text = pretty(&next);
    text.push('\n');
    replace_file(&path, &text)?;
    Ok(backup.to_string_lossy().to_string())
}

/// Replaces `path` with `text`, never leaving half a file. Shared by every agent's
/// installer (Claude Code here, Gemini CLI and Antigravity in agent_hooks.rs).
pub(crate) fn replace_file(path: &Path, text: &str) -> Result<(), String> {
    // A dotfiles setup often makes the file a symlink: write to the file it
    // points at, so the link survives the rename below.
    #[cfg(unix)]
    let path = std::fs::canonicalize(path).unwrap_or_else(|_| path.to_path_buf());
    #[cfg(not(unix))]
    let path = path.to_path_buf();

    // Write beside the target and rename over it: a crash or a full disk leaves
    // the original intact rather than half a file.
    let temp = path.with_extension(format!("json.notchmeow-{}", std::process::id()));
    if let Err(err) = write_like(&temp, &path, text.as_bytes()) {
        let _ = std::fs::remove_file(&temp);
        return Err(format!("write failed: {err}"));
    }
    if let Err(err) = std::fs::rename(&temp, &path) {
        let _ = std::fs::remove_file(&temp);
        return Err(format!("write failed: {err}"));
    }
    Ok(())
}
```

Then the module's code, above its tests.

```rust title="windows/src-tauri/src/agent_hooks.rs" old
#[cfg(test)]
mod tests {
    use super::*;
```

```rust title="windows/src-tauri/src/agent_hooks.rs" new
// Gemini CLI and Antigravity (`agy`) hook installation.
//
// The rules are the ones hooks.rs follows for Claude Code, and CLAUDE.md's: read
// the file and refuse anything unreadable or of an unexpected shape, show the
// diff, take a dated backup, merge without touching anybody else's entries, and
// write only after an explicit click, and only if the file is still the one the
// user looked at. Uninstall removes NotchMeow's entries and nothing else.
//
// What goes into the files is the macOS app's, entry for entry (HookServer.swift):
//
//   Gemini CLI   ~/.gemini/settings.json      six events, matcher "*", timeouts in ms
//   Antigravity  ~/.gemini/config/hooks.json  under the key "notchmeow", five
//                events, timeouts in seconds; the two tool events take a matcher
//                group, the three lifecycle events a direct handler
//
// Every command is the relay's path, `--agent <name>` and the event name the
// island understands (the relay translates the agents' own names as well).

use std::path::{Path, PathBuf};

use serde_json::{json, Map, Value};

use crate::hooks::{self, HookPreview, HookStatus};
use crate::{platform, settings};

/// The two agents. The tag is what `--agent` carries, what the island routes on
/// (`nm_agent`, so the pills `agent_gemini` and `agent_antigravity`) and what the
/// settings window sends to the commands in lib.rs.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Agent {
    Gemini,
    Antigravity,
}

impl Agent {
    pub fn from_tag(tag: &str) -> Result<Agent, String> {
        match tag {
            "gemini" => Ok(Agent::Gemini),
            "antigravity" => Ok(Agent::Antigravity),
            other => Err(format!("unknown agent \"{other}\"")),
        }
    }

    fn tag(self) -> &'static str {
        match self {
            Agent::Gemini => "gemini",
            Agent::Antigravity => "antigravity",
        }
    }

    fn label(self) -> &'static str {
        match self {
            Agent::Gemini => "Gemini CLI",
            Agent::Antigravity => "Antigravity",
        }
    }

    /// `%USERPROFILE%\.gemini\settings.json`, `%USERPROFILE%\.gemini\config\hooks.json`
    /// (and the same under `$HOME` on Linux).
    pub fn path(self) -> PathBuf {
        let dir = platform::home_dir().join(".gemini");
        match self {
            Agent::Gemini => dir.join("settings.json"),
            Agent::Antigravity => dir.join("config").join("hooks.json"),
        }
    }
}

/// Gemini CLI: its event, the name the relay is told, the timeout in milliseconds.
/// `AfterModel` is not installed: it fires on every streamed chunk and would
/// flood the island.
const GEMINI_EVENTS: &[(&str, &str, u64)] = &[
    ("SessionStart", "SessionStart", 10_000),
    ("SessionEnd", "SessionEnd", 10_000),
    ("BeforeTool", "PreToolUse", 5_000),
    ("AfterTool", "PostToolUse", 5_000),
    ("BeforeAgent", "UserPromptSubmit", 5_000),
    ("AfterAgent", "Stop", 5_000),
];

/// Antigravity: its event, and whether it takes a matcher group (the tool events)
/// or a direct handler (the lifecycle events).
const AGY_EVENTS: &[(&str, bool)] = &[
    ("PreToolUse", true),
    ("PostToolUse", true),
    ("PreInvocation", false),
    ("PostInvocation", false),
    ("Stop", false),
];

/// Antigravity's timeouts are in seconds.
const AGY_TIMEOUT_S: u64 = 10;

/// The top-level key of `hooks.json` that holds NotchMeow's entries.
const AGY_KEY: &str = "notchmeow";

// ── The command a hook runs ───────────────────────────────────────────────────

/// The quoted exe path in forward slashes, as hooks.rs writes it for Claude Code
/// on Windows. Not cfg-gated, so every OS can test it.
#[cfg(any(windows, test))]
fn windows_command(exe: &str, agent: &str, event: &str) -> String {
    format!("\"{}\" --agent {agent} {event}", exe.replace('\\', "/"))
}

/// A single-quoted path, as hooks.rs writes it for Claude Code on Linux.
#[cfg(unix)]
fn unix_command(exe: &str, agent: &str, event: &str) -> String {
    format!("{} --agent {agent} {event}", hooks::sh_quote(exe))
}

#[cfg(windows)]
fn relay_command(agent: &str, event: &str) -> String {
    windows_command(&settings::hook_exe_path().to_string_lossy(), agent, event)
}

#[cfg(unix)]
fn relay_command(agent: &str, event: &str) -> String {
    unix_command(&settings::hook_exe_path().to_string_lossy(), agent, event)
}

// ── Merging ───────────────────────────────────────────────────────────────────

/// True when `entry` (a hook group, or a hook inside one, or an older flat entry)
/// runs NotchMeow's relay.
fn runs_relay(entry: &Value) -> bool {
    entry
        .get("command")
        .and_then(Value::as_str)
        .is_some_and(|command| command.contains(hooks::MARKER))
}

/// True when `entry` runs the relay for `agent` (`--agent gemini`).
fn runs_relay_for(entry: &Value, agent: Agent) -> bool {
    entry
        .get("command")
        .and_then(Value::as_str)
        .is_some_and(|c| c.contains(hooks::MARKER) && c.contains(&format!("--agent {}", agent.tag())))
}

/// `groups` without NotchMeow's hooks. A group that also holds somebody else's
/// hooks stays, minus ours; a group that held only ours goes, and so does an
/// older flat entry (`command` on the group itself).
fn strip_ours(groups: &[Value]) -> Vec<Value> {
    groups
        .iter()
        .filter_map(|group| {
            if runs_relay(group) {
                return None;
            }
            let Some(inner) = group.get("hooks").and_then(Value::as_array) else {
                return Some(group.clone());
            };
            let kept: Vec<Value> = inner.iter().filter(|hook| !runs_relay(hook)).cloned().collect();
            if kept.is_empty() && !inner.is_empty() {
                return None;
            }
            let mut updated = group.clone();
            updated["hooks"] = Value::Array(kept);
            Some(updated)
        })
        .collect()
}

/// The event's groups, or an error when it is not a list of objects.
fn groups_of(hooks: &Map<String, Value>, event: &str) -> Result<Vec<Value>, String> {
    match hooks.get(event) {
        None => Ok(Vec::new()),
        Some(Value::Array(list)) if list.iter().all(Value::is_object) => Ok(list.clone()),
        Some(_) => Err(format!("\"hooks\"[\"{event}\"] has an unexpected type — NotchMeow has not touched it.")),
    }
}

/// The `hooks` object, an empty one when there is none, an error for anything else.
fn hooks_object(root: &Map<String, Value>) -> Result<Map<String, Value>, String> {
    match root.get("hooks") {
        None => Ok(Map::new()),
        Some(Value::Object(map)) => Ok(map.clone()),
        Some(_) => Err("\"hooks\" has an unexpected type — NotchMeow has not touched it.".to_string()),
    }
}

/// Builds the command a hook runs from the agent's tag and the event name:
/// `relay_command` in production, a fixed string in the tests.
type CommandFor<'a> = &'a dyn Fn(&str, &str) -> String;

/// Gemini CLI settings with NotchMeow's six hooks added; everything else is left alone.
fn merged_gemini(existing: &Value, command: CommandFor) -> Result<Value, String> {
    let mut root = existing.as_object().cloned().unwrap_or_default();
    let mut hooks = hooks_object(&root)?;
    for (event, normalized, timeout_ms) in GEMINI_EVENTS {
        let mut groups = strip_ours(&groups_of(&hooks, event)?);
        groups.push(json!({
            "matcher": "*",
            "hooks": [{
                "type": "command",
                "command": command(Agent::Gemini.tag(), normalized),
                "timeout": timeout_ms,
            }]
        }));
        hooks.insert((*event).to_string(), Value::Array(groups));
    }
    root.insert("hooks".into(), Value::Object(hooks));
    Ok(Value::Object(root))
}

/// Gemini CLI settings with every NotchMeow hook removed, and nothing else changed.
fn without_gemini(existing: &Value) -> Result<Value, String> {
    let mut root = existing.as_object().cloned().unwrap_or_default();
    let hooks = hooks_object(&root)?;
    let mut kept = Map::new();
    for (event, value) in &hooks {
        let groups = match value {
            Value::Array(list) if list.iter().all(Value::is_object) => list,
            other => {
                kept.insert(event.clone(), other.clone());
                continue;
            }
        };
        let cleaned = strip_ours(groups);
        // An event that held only ours goes; one that was empty before stays.
        if cleaned.is_empty() && !groups.is_empty() {
            continue;
        }
        kept.insert(event.clone(), Value::Array(cleaned));
    }
    if kept.is_empty() && !hooks.is_empty() {
        root.remove("hooks");
    } else if root.contains_key("hooks") {
        root.insert("hooks".into(), Value::Object(kept));
    }
    Ok(Value::Object(root))
}

/// Antigravity hooks with NotchMeow's five added under its own key.
fn merged_agy(existing: &Value, command: CommandFor) -> Value {
    let mut root = existing.as_object().cloned().unwrap_or_default();
    let mut ours = Map::new();
    for (event, takes_matcher) in AGY_EVENTS {
        let hook = json!({
            "type": "command",
            "command": command(Agent::Antigravity.tag(), event),
            "timeout": AGY_TIMEOUT_S,
        });
        let entry = if *takes_matcher { json!([{ "matcher": "*", "hooks": [hook] }]) } else { json!([hook]) };
        ours.insert((*event).to_string(), entry);
    }
    root.insert(AGY_KEY.into(), Value::Object(ours));
    Value::Object(root)
}

/// Antigravity hooks without NotchMeow's key.
fn without_agy(existing: &Value) -> Value {
    let mut root = existing.as_object().cloned().unwrap_or_default();
    root.remove(AGY_KEY);
    Value::Object(root)
}

fn plan(agent: Agent, current: &Value, install: bool) -> Result<Value, String> {
    match (agent, install) {
        (Agent::Gemini, true) => merged_gemini(current, &relay_command),
        (Agent::Gemini, false) => without_gemini(current),
        (Agent::Antigravity, true) => Ok(merged_agy(current, &relay_command)),
        (Agent::Antigravity, false) => Ok(without_agy(current)),
    }
}

/// Whether NotchMeow's hooks are in `value`: for Gemini CLI any hook that runs the
/// relay with `--agent gemini`, for Antigravity anything under its own key that runs it.
fn installed_in(agent: Agent, value: &Value) -> bool {
    match agent {
        Agent::Gemini => value
            .get("hooks")
            .and_then(Value::as_object)
            .is_some_and(|hooks| {
                hooks.values().filter_map(Value::as_array).flatten().any(|group| {
                    runs_relay_for(group, agent)
                        || group
                            .get("hooks")
                            .and_then(Value::as_array)
                            .is_some_and(|inner| inner.iter().any(|hook| runs_relay_for(hook, agent)))
                })
            }),
        Agent::Antigravity => value
            .get(AGY_KEY)
            .and_then(|ours| serde_json::to_string(ours).ok())
            .is_some_and(|text| text.contains(hooks::MARKER)),
    }
}

// ── The file ──────────────────────────────────────────────────────────────────

/// The file as JSON. Absent or empty: an empty object. Anything we cannot read or
/// parse is an error: it must never be mistaken for empty and written over.
fn read(path: &Path) -> Result<Value, String> {
    match std::fs::read(path) {
        Ok(bytes) => hooks::parse_settings(&bytes, &path.display().to_string()),
        Err(err) if err.kind() == std::io::ErrorKind::NotFound => Ok(Value::Object(Map::new())),
        Err(err) => Err(format!("Can't read {}: {err}", path.display())),
    }
}

fn fingerprint_of(path: &Path) -> String {
    hooks::fingerprint(&std::fs::read(path).unwrap_or_default())
}

/// `settings.json.bak-20261005-101500`, beside the file; empty when there is no
/// file yet, so nothing is backed up (the settings window says "created" then).
fn backup_path(path: &Path) -> String {
    if !path.exists() {
        return String::new();
    }
    let name = path.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
    path.with_file_name(format!("{name}.bak-{}", hooks::stamp())).to_string_lossy().to_string()
}

fn status_at(agent: Agent, path: &Path) -> HookStatus {
    let hook_path = settings::hook_exe_path();
    HookStatus {
        installed: read(path).map(|current| installed_in(agent, &current)).unwrap_or(false),
        settings_path: path.to_string_lossy().to_string(),
        hook_ready: hook_path.exists(),
        hook_path: hook_path.to_string_lossy().to_string(),
    }
}

fn preview_at(agent: Agent, path: &Path, install: bool) -> Result<HookPreview, String> {
    if !install && !path.exists() {
        return Err(format!("No {} hooks to remove.", agent.label()));
    }
    let current = read(path)?;
    let next = plan(agent, &current, install).map_err(|e| format!("{}: {e}", path.display()))?;
    Ok(HookPreview {
        diff: hooks::unified_diff(&hooks::pretty(&current), &hooks::pretty(&next)),
        backup: backup_path(path),
        settings_path: path.to_string_lossy().to_string(),
        fingerprint: fingerprint_of(path),
    })
}

/// Writes the merged (or cleaned) file after a dated backup, and returns the
/// backup's path (empty when there was no file to back up). Everything that can
/// refuse does so first, before the backup, so a refusal leaves nothing behind:
/// no backup, no new folder, no half a file.
fn write_at(agent: Agent, path: &Path, install: bool, fingerprint: &str) -> Result<String, String> {
    let current = read(path)?;
    if fingerprint_of(path) != fingerprint {
        return Err(format!(
            "{} changed since the preview. Nothing was written — review the new diff.",
            path.display()
        ));
    }
    let next = plan(agent, &current, install).map_err(|e| format!("{}: {e}", path.display()))?;

    let backup = backup_path(path);
    if !backup.is_empty() {
        std::fs::copy(path, &backup).map_err(|e| format!("backup failed: {e}"))?;
    }
    if let Some(dir) = path.parent() {
        std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    }
    let mut text = hooks::pretty(&next);
    text.push('\n');
    hooks::replace_file(path, &text)?;
    Ok(backup)
}

// ── Public API (the commands in lib.rs) ───────────────────────────────────────

pub fn status(agent: Agent) -> HookStatus {
    status_at(agent, &agent.path())
}

/// The diff the user has to look at before anything is written.
pub fn preview(agent: Agent, install: bool) -> Result<HookPreview, String> {
    preview_at(agent, &agent.path(), install)
}

/// Only ever called from an explicit click in the settings window, with the
/// fingerprint of the preview the user looked at.
pub fn write(agent: Agent, install: bool, fingerprint: &str) -> Result<String, String> {
    write_at(agent, &agent.path(), install, fingerprint)
}

#[cfg(test)]
mod tests {
    use super::*;
```

Last, the three commands and their registration in `lib.rs`.

```rust title="windows/src-tauri/src/lib.rs" old
use files::DroppedFile;
```

```rust title="windows/src-tauri/src/lib.rs" new
use agent_hooks::Agent;
use files::DroppedFile;
```

```rust title="windows/src-tauri/src/lib.rs" old
#[tauri::command]
fn approval_decision(app: AppHandle, request_id: String, decision: String) {
```

```rust title="windows/src-tauri/src/lib.rs" new
// ── Gemini CLI and Antigravity hooks ──────────────────────────────────────────
// The same three steps as Claude Code's, for the agent the settings window names
// (`gemini` or `antigravity`; anything else is refused).

#[tauri::command]
fn agent_hooks_status(agent: String) -> Result<HookStatus, String> {
    Ok(agent_hooks::status(Agent::from_tag(&agent)?))
}

#[tauri::command]
fn agent_hooks_preview(agent: String, install: bool) -> Result<HookPreview, String> {
    agent_hooks::preview(Agent::from_tag(&agent)?, install)
}

/// Only ever called from an explicit click in the settings window.
#[tauri::command]
fn agent_hooks_apply(agent: String, install: bool, fingerprint: String) -> Result<String, String> {
    agent_hooks::write(Agent::from_tag(&agent)?, install, &fingerprint)
}

#[tauri::command]
fn approval_decision(app: AppHandle, request_id: String, decision: String) {
```

```rust title="windows/src-tauri/src/lib.rs" old
            hooks_apply,
            approval_decision,
```

```rust title="windows/src-tauri/src/lib.rs" new
            hooks_apply,
            agent_hooks_status,
            agent_hooks_preview,
            agent_hooks_apply,
            approval_decision,
```

- [ ] **Step 4: Run the tests to verify they pass**

Run: `$CL test -p notchmeow --target-dir $TD -- agent_hooks hooks::`
Expected: PASS, `test result: ok. 28 passed`: the 8 existing `hooks::tests` (including `writing_backs_up_preserves_and_refuses_a_changed_file` and `rewriting_settings_never_widens_its_permissions`, which now go through `replace_file`) and the 20 new `agent_hooks::tests`. No `warning:` line.

Then the whole workspace: `$CL test --workspace --target-dir $TD`
Expected: PASS, `177 passed` for `notchmeow_lib` (157 before this task) and `23 passed` for `notchmeow_hook`.

- [ ] **Step 5: Commit**

```bash
git add windows/src-tauri/src/agent_hooks.rs windows/src-tauri/src/hooks.rs windows/src-tauri/src/lib.rs
git commit -m "feat(windows): install Gemini CLI and Antigravity hooks

Ported by hand from upstream's n22-gemini branch and matched to the Mac's
installers: ~/.gemini/settings.json (six events) and ~/.gemini/config/hooks.json
(five events under the notchmeow key). One install path for both agents, built on
the hardened helpers of hooks.rs (replace_file is extracted from hooks::write):
a file of an unexpected shape is refused, never coerced, and nothing is written
before the diff, the backup and the fingerprint check.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: The Settings sections

**Files:**
- Modify: `windows/src/core/bridge.ts`, `windows/src/settings/main.ts`
- Test: a browser check of the Settings page against a stubbed backend (`ui-check.js` in `${TMPDIR:-/tmp}/port-gemini-agy/`, never committed)

**Interfaces:**
- Consumes: Task 2's three commands, by name and argument: `agent_hooks_status { agent }`, `agent_hooks_preview { agent, install }`, `agent_hooks_apply { agent, install, fingerprint }`; `HookPreview.backup` is empty when the file does not exist yet.
- Produces `bridge.ts`: `type HookAgent = "gemini" | "antigravity"`, `Bridge.agentHooksStatus(agent) -> Promise<HookStatus | null>`, `Bridge.agentHooksPreview(agent, install) -> Promise<HookPreview>` (it throws with the reason when the file is refused), `Bridge.agentHooksApply(agent, install, fingerprint) -> Promise<string>`.
- Produces `settings/main.ts`: `agentHooksSection(copy: AgentHooksCopy, initial: HookStatus): HTMLElement`, used for `gemini` and `antigravity` right after `claudeSection`.

The Settings page has no test runner, so the test is a browser check against a stubbed Tauri backend: the page is served by Vite alone, and a script stands in for `window.__TAURI_INTERNALS__`, the object `invoke` calls. It plays the real flow (install, preview, confirm, status flips, a refusal, uninstall) and asserts the texts.

- [ ] **Step 1: Write the browser check**

Create the check, and start Vite on its own port. Not `npm run dev`: its `predev` step builds the relay for the host, which a Mac cannot do.

```bash
UI="${TMPDIR:-/tmp}/port-gemini-agy"; mkdir -p "$UI"
cat > "$UI/ui-check.js" <<'JS'
async page => {
  page.setDefaultTimeout(3000);
  // A stand-in for the Tauri backend: the object `invoke` talks to. It answers the
  // three agent commands from a small in-memory model of the two config files.
  await page.addInitScript(() => {
    const files = { gemini: false, antigravity: false };   // is NotchMeow installed in the file?
    const paths = {
      gemini: "C:\\Users\\Zoé Smith\\.gemini\\settings.json",
      antigravity: "C:\\Users\\Zoé Smith\\.gemini\\config\\hooks.json",
    };
    const relay = "C:\\Users\\Zoé Smith\\AppData\\Local\\NotchMeow\\bin\\notchmeow-hook.exe";
    const BACKUP = "C:\\Users\\Zoé Smith\\.gemini\\settings.json.bak-20261005-101500";
    window.__calls = [];
    window.__refuse = false;
    window.__TAURI_INTERNALS__ = {
      transformCallback: () => 1,
      invoke: async (cmd, args) => {
        window.__calls.push([cmd, args]);
        switch (cmd) {
          case "plugin:event|listen": return 1;
          case "hooks_status": return { installed: false, settingsPath: "C:\\x\\settings.json", hookPath: relay, hookReady: true };
          case "agent_hooks_status":
            return { installed: files[args.agent], settingsPath: paths[args.agent], hookPath: relay, hookReady: true };
          case "agent_hooks_preview":
            if (window.__refuse && args.agent === "gemini") {
              throw paths.gemini + ': "hooks" has an unexpected type — NotchMeow has not touched it.';
            }
            return {
              diff: args.install ? '  {\n+   "hooks": {\n+     "BeforeTool": [ … ]\n+   }\n  }' : '- removed',
              backup: args.agent === "gemini" ? BACKUP : "",   // antigravity: no file yet
              settingsPath: paths[args.agent],
              fingerprint: "abc123",
            };
          case "agent_hooks_apply":
            files[args.agent] = args.install;
            return args.agent === "gemini" ? BACKUP : "";
          default: return null;                              // everything else the page asks for
        }
      },
    };
  });

  const must = (cond, message) => { if (!cond) throw new Error("ui check failed: " + message); };
  await page.goto("http://127.0.0.1:1431/settings.html");
  const section = (title) => page.locator("section", { has: page.locator("h2", { hasText: title }) });
  const text = async (s) => (await s.innerText()).replace(/\s+/g, " ");
  const gem = section("Gemini CLI");
  const agy = section("Antigravity");

  // The new sections sit right after Claude Code's, in its own look.
  const titles = await page.locator("section h2").allInnerTexts();
  must(titles.slice(0, 3).join("|") === "Claude Code|Gemini CLI|Antigravity (agy)", "order of sections: " + titles);

  // Gemini CLI: not installed yet, then preview, then write.
  let t = await text(gem);
  must(t.includes("Install the hooks to see your Gemini CLI sessions"), "initial hint: " + t);
  must(t.includes("settings.json") && t.includes("notchmeow-hook.exe"), "paths shown: " + t);
  await gem.getByRole("button", { name: "Install hooks…" }).click();
  t = await text(gem);
  must(t.includes("This is exactly what will change") && t.includes('+ "hooks": {'), "diff shown: " + t);
  must(t.includes("Backup → C:\\Users\\Zoé Smith\\.gemini\\settings.json.bak-20261005-101500"), "backup shown: " + t);
  await gem.getByRole("button", { name: "Back up and write" }).click();
  t = await text(gem);
  must(t.includes("Done. Previous file saved as") && t.includes("Open a new Gemini CLI session"), "done note: " + t);
  await page.waitForTimeout(2900);
  t = await text(gem);
  must(t.includes("NotchMeow is hooked into your Gemini CLI sessions") && t.includes("Reinstall hooks…") && t.includes("Uninstall hooks…"), "installed state: " + t);

  // Antigravity: the file does not exist yet, so there is no backup to promise.
  await agy.getByRole("button", { name: "Install hooks…" }).click();
  t = await text(agy);
  must(t.includes("The file doesn't exist yet, so it will be created.") && !t.includes("Backup →"), "no backup promised: " + t);
  await agy.getByRole("button", { name: "Back up and write" }).click();
  t = await text(agy);
  must(t.includes("Done. The file was created.") && t.includes("Open a new agy session"), "created note: " + t);

  // Uninstall previews a removal, and Cancel goes back without writing.
  await gem.getByRole("button", { name: "Uninstall hooks…" }).click();
  t = await text(gem);
  must(t.includes("This removes NotchMeow's entries only") && t.includes("Back up and remove"), "uninstall preview: " + t);
  await gem.getByRole("button", { name: "Cancel" }).click();

  // A file NotchMeow cannot safely edit: the reason is shown, and nothing can be written.
  await page.evaluate(() => { window.__refuse = true; });
  await gem.getByRole("button", { name: "Reinstall hooks…" }).click();
  t = await text(gem);
  must(t.includes("has an unexpected type — NotchMeow has not touched it.") && !t.includes("Back up and write"), "refusal shown: " + t);
  await gem.getByRole("button", { name: "Back" }).click();

  // Exactly the commands and arguments the backend defines, in this order, and no write after the refusal.
  const calls = await page.evaluate(() =>
    window.__calls.filter((c) => c[0].startsWith("agent_hooks")).map((c) => c[0] + ":" + c[1].agent + ":" + (c[1].install ?? "")));
  must(calls.filter((c) => c.startsWith("agent_hooks_apply")).length === 2, "two writes only: " + calls);
  must(calls.includes("agent_hooks_preview:gemini:true") && calls.includes("agent_hooks_preview:antigravity:true"), "previews: " + calls);

  await page.screenshot({ path: "__SHOT__" });
  return "ui check passed";
}
JS
(cd windows && npx --no-install vite --port 1431 --strictPort > "$UI/vite.log" 2>&1 &)
sleep 4 && tail -3 "$UI/vite.log"
```

Expected: Vite prints `Local:   http://127.0.0.1:1431/`.

- [ ] **Step 2: Run the check to verify it fails**

`playwright-cli` keeps its browser session, and a `.playwright-cli/` snapshot folder, in the directory it is run from: run it from `$UI`, never from the worktree.

```bash
UI="${TMPDIR:-/tmp}/port-gemini-agy"
cd "$UI"
for try in 1 2 3; do   # the browser sometimes needs a second start
  playwright-cli close-all >/dev/null 2>&1; sleep 2
  playwright-cli open >/dev/null 2>&1; playwright-cli list 2>&1 | grep -q "status: open" && break
done
playwright-cli run-code "$(sed "s#__SHOT__#$UI/settings.png#" ui-check.js)" --raw
cd - >/dev/null
```

Expected: FAIL, printing `Error: ui check failed: order of sections: Claude Code,AI,Integrations,General`: the page has no Gemini CLI or Antigravity section yet.

- [ ] **Step 3: Write the implementation**

The bridge, then the sections.

```ts title="windows/src/core/bridge.ts" old
  hooksApply: (install: boolean, fingerprint: string) =>
    callOrThrow<string>("hooks_apply", { install, fingerprint }),
```

```ts title="windows/src/core/bridge.ts" new
  hooksApply: (install: boolean, fingerprint: string) =>
    callOrThrow<string>("hooks_apply", { install, fingerprint }),

  // ── Gemini CLI and Antigravity hooks ──────────────────────────────────────
  // The same three steps for the agent's own config file (~/.gemini/…).
  agentHooksStatus: (agent: HookAgent) => call<HookStatus>("agent_hooks_status", { agent }),
  agentHooksPreview: (agent: HookAgent, install: boolean) =>
    callOrThrow<HookPreview>("agent_hooks_preview", { agent, install }),
  agentHooksApply: (agent: HookAgent, install: boolean, fingerprint: string) =>
    callOrThrow<string>("agent_hooks_apply", { agent, install, fingerprint }),
```

```ts title="windows/src/core/bridge.ts" old
export interface HookPreview {
```

```ts title="windows/src/core/bridge.ts" new
/** The agents whose hooks live in a config file of their own; also their `--agent` / `nm_agent`. */
export type HookAgent = "gemini" | "antigravity";

export interface HookPreview {
```

```ts title="windows/src/settings/main.ts" old
import { Bridge, CLOUD_PROVIDERS, onEvent, type AiServer, type Feature, type HookStatus, type ModelInfo } from "../core/bridge";
```

```ts title="windows/src/settings/main.ts" new
import { Bridge, CLOUD_PROVIDERS, onEvent, type AiServer, type Feature, type HookAgent, type HookStatus, type ModelInfo } from "../core/bridge";
```

```ts title="windows/src/settings/main.ts" old
// ── AI section ────────────────────────────────────────────────────────────────
//
// Three boxes (spec §4)
```

```ts title="windows/src/settings/main.ts" new
// ── Gemini CLI and Antigravity sections ───────────────────────────────────────
// Claude Code's flow for the agents that keep their hooks in a config file of their
// own: look at the exact diff, back up, write only on a click. Their sessions then
// get a pill of their own in the island (`agent_gemini`, `agent_antigravity`).

interface AgentHooksCopy {
  agent: HookAgent;
  title: string;
  /** What the user opens after installing: "a new Gemini CLI session". */
  session: string;
}

function agentHooksSection(copy: AgentHooksCopy, initial: HookStatus): HTMLElement {
  let status = initial;
  const head = h("h2", {});
  const body = h("div", { style: "display:flex;flex-direction:column;gap:12px" });
  const section = h("section", {}, head, body);

  const paint = () => {
    clear(head);
    head.append(statusDot(status.installed), h("span", { text: copy.title }));
    clear(body);
    draw();
  };
  const refresh = async () => {
    const fresh = await Bridge.agentHooksStatus(copy.agent);
    if (fresh) status = fresh;
    paint();
  };

  function draw() {
    const relay = status.hookPath.split(/[\\/]/).pop() || "notchmeow-hook";
    body.append(
      h("div", {
        class: "hint",
        text: status.installed
          ? `NotchMeow is hooked into your ${copy.title} sessions. They get a pill in the island.`
          : `Install the hooks to see your ${copy.title} sessions in the island.`,
      }),
      h("div", { class: "row" },
        h("label", { text: "Config file" }),
        h("span", { class: "path", text: status.settingsPath }),
      ),
      h("div", { class: "row" },
        h("label", { text: "Relay" }),
        h("span", { class: "path", text: status.hookPath }),
        statusDot(status.hookReady),
      ),
    );

    if (!status.hookReady) {
      body.append(h("div", {
        class: "notice warn",
        text: `${relay} is not in place yet. Restart NotchMeow; if it still fails, build it with \`cargo build -p notchmeow-hook\`.`,
      }));
    }

    const actions = h("div", { class: "row" });
    const install = h("button", {
      class: "primary",
      text: status.installed ? "Reinstall hooks…" : "Install hooks…",
      onclick: () => showPreview(true),
    });
    // Hook commands that point at a relay which isn't there would break every session.
    if (!status.hookReady) {
      install.disabled = true;
      install.title = "The relay isn't installed yet.";
    }
    actions.append(install);
    if (status.installed) {
      actions.append(h("button", {
        class: "danger",
        text: "Uninstall hooks…",
        onclick: () => showPreview(false),
      }));
    }
    body.append(actions);
  }

  async function showPreview(install: boolean) {
    let preview;
    try {
      preview = await Bridge.agentHooksPreview(copy.agent, install);
    } catch (err) {
      // A file we cannot safely edit stops here, with the reason, and nothing is written.
      clear(body);
      body.append(
        h("div", { class: "notice err", text: String(err).replace(/^Error:\s*/, "") }),
        h("div", { class: "row" }, h("button", {
          text: "Back",
          onclick: () => { clear(body); draw(); },
        })),
      );
      return;
    }
    clear(body);
    body.append(
      h("div", {
        class: "hint",
        text: install
          ? "This is exactly what will change in the config file. Your own hooks are left untouched."
          : "This removes NotchMeow's entries only. Your own hooks are left untouched.",
      }),
      renderDiff(preview.diff),
      h("div", { class: "row" },
        h("span", {
          class: "path",
          // No file yet means nothing to back up: the backend sends an empty path.
          text: preview.backup ? `Backup → ${preview.backup}` : "The file doesn't exist yet, so it will be created.",
        }),
      ),
    );
    const confirm = h("button", {
      class: install ? "primary" : "danger",
      text: install ? "Back up and write" : "Back up and remove",
    });
    confirm.addEventListener("click", async () => {
      confirm.disabled = true;
      try {
        const backup = await Bridge.agentHooksApply(copy.agent, install, preview.fingerprint);
        clear(body);
        body.append(h("div", {
          class: "notice ok",
          text: `Done. ${backup ? `Previous file saved as ${backup}.` : "The file was created."} Open ${copy.session} to pick the change up.`,
        }));
        window.setTimeout(() => void refresh(), 2600);
      } catch (err) {
        confirm.disabled = false;
        body.append(h("div", { class: "notice err", text: `Could not write: ${String(err)}` }));
      }
    });
    body.append(h("div", { class: "row" }, confirm, h("button", {
      text: "Cancel",
      onclick: () => { clear(body); draw(); },
    })));
  }

  paint();
  return section;
}

// ── AI section ────────────────────────────────────────────────────────────────
//
// Three boxes (spec §4)
```

```ts title="windows/src/settings/main.ts" old
  const status = (await Bridge.hooksStatus()) ?? {
    installed: false, settingsPath: "", hookPath: "", hookReady: false,
  };
```

```ts title="windows/src/settings/main.ts" new
  const status = (await Bridge.hooksStatus()) ?? {
    installed: false, settingsPath: "", hookPath: "", hookReady: false,
  };
  const noStatus = { installed: false, settingsPath: "", hookPath: "", hookReady: false };
  const geminiStatus = (await Bridge.agentHooksStatus("gemini")) ?? { ...noStatus };
  const agyStatus = (await Bridge.agentHooksStatus("antigravity")) ?? { ...noStatus };
```

```ts title="windows/src/settings/main.ts" old
    claudeSection(status),
    aiSection(present),
```

```ts title="windows/src/settings/main.ts" new
    claudeSection(status),
    agentHooksSection({ agent: "gemini", title: "Gemini CLI", session: "a new Gemini CLI session" }, geminiStatus),
    agentHooksSection({ agent: "antigravity", title: "Antigravity (agy)", session: "a new agy session" }, agyStatus),
    aiSection(present),
```

- [ ] **Step 4: Run the check and the type check to verify they pass**

```bash
UI="${TMPDIR:-/tmp}/port-gemini-agy"
(cd "$UI" && playwright-cli run-code "$(sed "s#__SHOT__#$UI/settings.png#" ui-check.js)" --raw)
(cd windows && npx --no-install tsc --noEmit; echo "tsc exit $?")
```

Expected: the check prints `"ui check passed"` (it loads the page itself); `tsc exit 0` with no output before it. The check also saved `$UI/settings.png`: open it once. The Gemini CLI and Antigravity sections should look like the Claude Code section above them (same card, dot, rows, button).

- [ ] **Step 5: Stop Vite and commit**

`git status --short` must list exactly `M windows/src/core/bridge.ts` and `M windows/src/settings/main.ts`, with nothing untracked (a `.playwright-cli/` folder in the worktree means `playwright-cli` was run from the wrong directory: move it to the Trash).

```bash
UI="${TMPDIR:-/tmp}/port-gemini-agy"
(cd "$UI" && playwright-cli close-all >/dev/null 2>&1)
pkill -f "vite --port 1431" ; true
git status --short
git add windows/src/core/bridge.ts windows/src/settings/main.ts
git commit -m "feat(windows): Settings sections for Gemini CLI and Antigravity hooks

Ported by hand from upstream's n22-gemini branch: one agentHooksSection for both
agents, in Claude Code's own look: the diff first, a dated backup, a write only on
a click, and the refusal's reason shown when a file cannot be edited safely.

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Docs and the final checks

**Files:**
- Modify: `windows/README.md`, `README.md`, `docs/AGENTS.md`, `CHANGELOG.md`
- Test: the whole workspace, `npx --no-install tsc --noEmit`, `npm run check:ai`, a production build of the front end, the Windows `cargo check`, and a search of the diff for Coucou's names

**Interfaces:**
- Consumes: the three tasks above.
- Produces: the docs say what now works on Windows and Linux; the branch passes every check below.

- [ ] **Step 1: Update the docs**

```text title="windows/README.md" old
It works from any terminal — Windows Terminal, PowerShell, VS Code, Git Bash.

## AI: cloud keys and local models
```

```text title="windows/README.md" new
It works from any terminal — Windows Terminal, PowerShell, VS Code, Git Bash.

## Gemini CLI and Antigravity

NotchMeow also hooks into **Gemini CLI** (`gemini`) and **Antigravity** (`agy`), the way the Mac app does. A session of either gets a pill of its own in the island, with its tool calls in the ticker, like a Claude Code session. They get no approval card: that stays Claude Code's.

- **Settings… → Gemini CLI → Install hooks…** writes `%USERPROFILE%\.gemini\settings.json` (`~/.gemini/settings.json` on Linux): six events, timeouts in milliseconds.
- **Settings… → Antigravity → Install hooks…** writes `%USERPROFILE%\.gemini\config\hooks.json` (`~/.gemini/config/hooks.json` on Linux): five events, timeouts in seconds, all under a `"notchmeow"` key. Uninstalling removes only that key.

Both follow Claude Code's rules: you see the exact diff first, a dated backup is taken (`settings.json.bak-<time>`, `hooks.json.bak-<time>`), your own hooks are never touched, nothing is written until you click, and a file NotchMeow can't safely edit (invalid JSON, a `hooks` entry of an unexpected type) is refused with the reason. The events go through the same `notchmeow-hook` relay: it translates Gemini's `BeforeTool`, `AfterTool`, `BeforeAgent` and `AfterAgent` to `PreToolUse`, `PostToolUse`, `UserPromptSubmit` and `Stop`, maps Antigravity's `toolCall` and `conversationId` to the shapes the island reads, and answers `{}`, the "no decision" both agents expect. If NotchMeow is closed it exits at once, so neither agent is ever blocked.

## AI: cloud keys and local models
```

```text title="README.md" old
| **Gemini CLI hooks** *(macOS)* | Gemini CLI sessions in the island | **Install hooks** in Settings → Gemini CLI — backs up `~/.gemini/settings.json` |
| **Antigravity (agy) hooks** *(macOS)* | agy sessions in the island | **Install hooks** in Settings → Antigravity — backs up `~/.gemini/config/hooks.json` |
```

```text title="README.md" new
| **Gemini CLI hooks** *(macOS, Windows, Linux)* | Gemini CLI sessions in the island | **Install hooks** in Settings → Gemini CLI — backs up `~/.gemini/settings.json` |
| **Antigravity (agy) hooks** *(macOS, Windows, Linux)* | agy sessions in the island | **Install hooks** in Settings → Antigravity — backs up `~/.gemini/config/hooks.json` |
```

```text title="docs/AGENTS.md" old
### Gemini CLI (macOS)

NotchMeow supports Gemini CLI out of the box via **Settings → Gemini CLI → Install hooks**.
The installer writes to `~/.gemini/settings.json` and uses `--agent gemini` so
Gemini sessions get their own pill. The relay translates Gemini event names to canonical
NotchMeow events automatically.
```

```text title="docs/AGENTS.md" new
### Gemini CLI (macOS, Windows and Linux)

NotchMeow supports Gemini CLI out of the box via **Settings → Gemini CLI → Install hooks**.
The installer writes to `~/.gemini/settings.json` (`%USERPROFILE%\.gemini\settings.json` on Windows) and uses `--agent gemini` so
Gemini sessions get their own pill. The relay translates Gemini event names to canonical
NotchMeow events automatically. All three platforms install the same six events (the four
below, plus `SessionStart` and `SessionEnd`) with the same timeouts, in milliseconds.
```

```text title="docs/AGENTS.md" old
### Antigravity — `agy` (macOS)

NotchMeow supports Antigravity out of the box via **Settings → Antigravity → Install hooks**.
The installer writes to `~/.gemini/config/hooks.json` (timeouts in seconds) and uses
`--agent antigravity`. The relay translates `toolCall.name` / `conversationId` to the
island's `tool_name` / `session_id`.
```

```text title="docs/AGENTS.md" new
### Antigravity — `agy` (macOS, Windows and Linux)

NotchMeow supports Antigravity out of the box via **Settings → Antigravity → Install hooks**.
The installer writes to `~/.gemini/config/hooks.json` (`%USERPROFILE%\.gemini\config\hooks.json`
on Windows; timeouts in seconds), under its own top-level key `notchmeow`, and uses
`--agent antigravity`. The relay translates `toolCall.name` / `conversationId` to the
island's `tool_name` / `session_id`, and `workspacePaths[0]` to `cwd`.
```

```text title="docs/AGENTS.md" old
| `Stop` | `Stop` |

### Any other tool
```

```text title="docs/AGENTS.md" new
| `Stop` | `Stop` |

For both agents the relay answers `{}` on stdout, their "no decision", and exits at once when
NotchMeow is closed, so neither agent is ever blocked.

### Any other tool
```

```text title="CHANGELOG.md" old
- Local models everywhere (macOS): Ollama,
```

```text title="CHANGELOG.md" new
- Gemini CLI and Antigravity (agy) hook support on Windows and Linux, as on the Mac: install them from Settings → Gemini CLI and Settings → Antigravity, and their sessions show up in the island. Ported by hand from upstream's `n22-gemini` branch, by @corefusiion
- Local models everywhere (macOS): Ollama,
```

- [ ] **Step 2: Check the diff for Coucou's names and for stray files**

From the repository root:

```bash
BASE=$(git merge-base HEAD notchmeow/rebrand)
git diff "$BASE" --stat
git diff "$BASE" | grep '^+' | grep -v '^+++' | grep -n -i -E "coucou|mochi|nb-hook|nb\.sock|coucou_agent" ; echo "grep exit $? (1 means none)"
git status --short
```

Expected: `--stat` lists exactly these files: `CHANGELOG.md`, `README.md`, `docs/AGENTS.md`, `windows/README.md`, `windows/hook/src/agents.rs`, `windows/hook/src/main.rs`, `windows/src-tauri/src/agent_hooks.rs`, `windows/src-tauri/src/hooks.rs`, `windows/src-tauri/src/lib.rs`, `windows/src/core/bridge.ts`, `windows/src/settings/main.ts`; `grep exit 1`; `git status --short` lists only the four docs of step 1 as modified, with nothing untracked (no file under `NotchBuddy/`, `design/` or `tests/`).

- [ ] **Step 3: Run every check**

```bash
CL=windows/scripts/cargo-linux.sh; TD=/repo/windows/target/port-gemini-agy
$CL test --workspace --target-dir $TD
(cd windows && npx --no-install tsc --noEmit; echo "tsc exit $?")
(cd windows && npm run check:ai)
(cd windows && npx --no-install vite build)
```

Expected: the workspace passes with `177 passed` (`notchmeow_lib`) and `23 passed` (`notchmeow_hook`) and no `warning:` from the compiler; `tsc exit 0`; `All AI UI checks passed`; and Vite ends with `built in`. If other plans have merged and added `npm run check:*` scripts (for example `check:cat`), run each of them too: `grep '"check:' package.json`. Do not use `npm run build` or `npm run dev`: their `pre` steps build the relay for the host, which a Mac cannot do. Never run `npm install`.

- [ ] **Step 4: Check the Windows-only code compiles (needs the network inside a throwaway container)**

The three `#[cfg(windows)]` lines (`relay_command`, and `windows_command` outside tests) and Windows' side of `replace_file` are not compiled by the Linux runs. Compile them for the Windows target, in the same image, in a throwaway container with its own volume (the toolchain and `mingw-w64` are installed inside the container, never on the host; this one step needs network access from the container):

```bash
docker run --rm --pull=never \
  -v "$PWD":/repo -v notchmeow-portgemagy-win:/repo/windows/target \
  -v notchmeow-linux-cargo:/usr/local/cargo/registry \
  -w /repo/windows notchmeow-linux-dev bash -c '
    set -e
    rustup target add x86_64-pc-windows-gnu
    apt-get update -qq && apt-get install -y -qq --no-install-recommends mingw-w64
    cargo build --release -q -p notchmeow-hook
    touch target/release/notchmeow-hook.exe      # tauri-build only needs the bundled relay to exist for a check
    cargo check --target x86_64-pc-windows-gnu --workspace --all-targets'
```

Expected: `Finished` with no `error` and no `warning:` from `notchmeow`. If the container has no network, say so in the report: this step is then owed to CI (`windows-tests.yml` runs `cargo test --workspace` on Windows for pull requests), and the owner decides.

- [ ] **Step 5: Commit**

```bash
git add windows/README.md README.md docs/AGENTS.md CHANGELOG.md
git commit -m "docs: Gemini CLI and Antigravity hooks on Windows and Linux

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Self-review notes

Run against the spec and the Mac after writing:

- **Spec coverage.** "Windows Gemini CLI and Antigravity hooks (upstream branch `n22-gemini`), after `e1/tauri` merges, with the identifiers renamed to NotchMeow's": ported by hand (Tasks 1 to 3, no merge or cherry-pick), after `e1/tauri` (it is in the base), with `nm_agent`, `notchmeow-hook`, the key `notchmeow` and no Coucou name (Global Constraints, Task 4 step 2). The Mac's behaviour: the six Gemini events and their timeouts (Task 2 `installing_gemini_hooks_adds_the_six_events_with_the_macs_timeouts`), the five Antigravity events with matcher groups for the tool events and direct handlers for the others (`installing_antigravity_hooks_adds_five_events_under_the_notchmeow_key`), the refusals and the "No … hooks to remove." message, the backup name, the fingerprint check, the relay's translation table, `workspacePaths`, and the `{}` answer (Task 1).
- **Placeholder scan:** none left. Every code step carries its full code or its exact old and new text, and no step points at another task for code.
- **Type consistency:** `Event`, `shape_event`, `stdout_for` and the four `agents::` functions (Task 1) keep their names in the tests, the implementation and the smoke test; `Agent`, `from_tag`, `path`, `status`, `preview`, `write` (Task 2) are the names `lib.rs` calls; the command names and argument names `agent`, `install`, `fingerprint` are the ones `bridge.ts` invokes (Task 3), and the UI check's stub answers exactly them.
- **Review Focus:** each of the five lines has its test in the task named there.
- **Dry run.** Every task was replayed in a throwaway clone of `notchmeow/rebrand` (at `94552ae`), applying the blocks above with a small script and running each step: Task 1 and Task 2 red (the compile errors quoted) then green, `23` and `177` tests, the relay smoke test (`app closed: ok`, `app open: ok`), Task 3's browser check red then green with `tsc` clean, Task 4's checks. The tree after the replay is byte for byte the prototype's. Run through the Docker image with `--offline` and a private target volume (`windows/scripts/cargo-linux.sh` is the same command with the shared volume). **Not replayed:** Task 4's Windows `cargo check` (it installs a toolchain and `mingw-w64` from the network inside a container: no downloads were allowed), so the `#[cfg(windows)]` lines are checked by reading only until that step or CI runs.

## Follow-ups for the main session (not in this plan)

1. **Search tool names for the cat (`cat-core.js`, `tests/fixtures/cat/search-tools.json`).** `docs/CAT-CONTRACT.md` says Antigravity's tool names are unknown. Upstream's branch does not reveal them: it names only the argument keys Antigravity's tools use (`CommandLine`, `FilePath`, `Path`, `Url`, `Query`, `Pattern`, in `normalize_tool_fields`), never a tool name, and upstream's Mac code and docs are the same. The names will come from a real `agy` session: with the hooks installed, the relay forwards `tool_name` unchanged and the island labels a tool it does not know with its raw name (`example_tool · …` in the ticker), so a short real session reads them off the island. Gemini CLI's names (`grep_search`, `google_web_search`, `web_fetch`, `glob`, `search_file_content`) are already in `SEARCH_TOOLS.gemini` and arrive as `tool_name` untouched. The cat plan's later "searching" stage should pick the list from `payload.nm_agent` (`gemini`, `antigravity`, absent for Claude Code).
2. **The Mac's installer is less careful than this port in three small ways.** `HookServer.writeJSONFile` writes with `Data.write(options: .atomic)`, which renames a new file over the target: read from the code, not run, that replaces a symlinked `~/.gemini/settings.json` (a dotfiles repo) with a regular file and does nothing to keep the old file's mode; this port follows the link and keeps the mode (settings files can hold API keys in `env`). Uninstalling on the Mac also drops an event array that was already empty before NotchMeow. ARCHITECT.md's rule is that the Mac gets at least what Windows gets: a small Mac plan can match these.
3. **`hooks.rs` `merged()` (Claude Code, Windows/Linux) still coerces** a `hooks` of an unexpected type, or an event that is not a list, to an empty one and writes over it. The new installers refuse instead, as the Mac's Gemini and Antigravity installers do. Changing Claude's path was out of scope here: the owner decides.
4. **No pill catalogue on Windows/Linux.** The Mac declares `agent_gemini` ("Gemini CLI", `#8AB4F8`) and `agent_antigravity` ("Antigravity", `#E879F9`) in `PillCatalog.swift`; a live session pill is created from `nm_agent` alone, named `gemini` or `antigravity` with a hashed colour, on both apps unless the user declared the pill on the Mac. The Windows island keeps that behaviour. The cat's collar colours (cat plan stage 6) are "the real ones from the pill catalogue": a Windows catalogue, or a small table for these two, is a decision for that stage.

## Open questions for the owner

1. **Which shell runs a Gemini CLI or Antigravity hook on Windows?** The hook command is the relay's quoted path in forward slashes (`"C:/Users/.../notchmeow-hook.exe" --agent gemini PreToolUse`), as upstream wrote it and as Claude Code's own Windows entry is written. That works in Git Bash. A PowerShell host would need `& "…"` in front of a quoted path, and `cmd.exe /s /c` strips the first and last quote of a command line that starts with one, which can break a quoted path that contains a space (a user called "Zoé Smith") unless the whole command is wrapped in a second pair. I could not check either agent's Windows launcher offline. **Manual check, on a real Windows machine:** install both from Settings, start `gemini` and `agy` from `cmd`, PowerShell and Git Bash, with a profile folder that contains a space, and see the pill appear. If one fails, the command is built in one place (`windows_command` in `agent_hooks.rs`) and its test pins the format.
2. **Manual checks that need real machines:** Windows with Gemini CLI, Windows with Antigravity, Linux (X11 or Wayland) with Gemini CLI: the pill appears and ticks, finishes on `AfterAgent`, disappears on `SessionEnd`, and the agent is not slowed when NotchMeow is quit.
3. **Is a `{}` on empty or invalid stdin wanted?** The relay prints `{}` only when it could read a JSON payload (as the Mac's does): empty or invalid stdin prints nothing, so the agent sees an empty answer. Both agents are expected to treat that as "no decision"; the Mac behaves the same. Say so if you want `{}` there too.
