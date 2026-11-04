# NotchMeow — third-party agent integration

Any tool that can write to a Unix domain socket (macOS, Linux) or a named pipe (Windows) can send events to NotchMeow and have its own pill next to Claude Code.

## The `nm_agent` field

Add the optional field `nm_agent` to any hook JSON payload. NotchMeow will create a pill labelled with the agent name and route all events to it.

**Validation:** the name must match `^[a-z0-9-]{1,24}$` (lowercase letters, digits and hyphens, 1–24 characters). An absent or invalid name routes the event to the Claude Code pill instead.

## Hook command (macOS)

Configure your tool to call the NotchMeow relay with `--agent <your-name>` after the hook executable:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      { "type": "command", "command": "/path/to/nm-hook --agent my-tool" }
    ]
  }
}
```

The shell wrapper passes `"$@"` to the Python relay, which extracts the agent name and injects it into the payload before forwarding to NotchMeow.

## Hook command (Windows)

Same pattern with the Windows relay:

```json
{
  "hooks": {
    "UserPromptSubmit": [
      { "type": "command", "command": "C:\\path\\to\\notchmeow-hook.exe --agent my-tool" }
    ]
  }
}
```

## Hook command (Linux)

Same pattern with the Linux relay. NotchMeow copies the relay to `~/.local/share/notchmeow/bin/notchmeow-hook` at startup.

```json
{
  "hooks": {
    "UserPromptSubmit": [
      { "type": "command", "command": "/path/to/notchmeow-hook --agent my-tool" }
    ]
  }
}
```

## Payload format

The relay adds `nm_agent` to the JSON it forwards. You can also add it yourself if you talk to the socket directly:

```json
{
  "hook_event_name": "UserPromptSubmit",
  "session_id": "my-session-1",
  "nm_agent": "my-tool",
  "prompt": "Running task…"
}
```

Send newline-terminated JSON to the socket:
- **macOS (GitHub build):** `~/Library/Application Support/NotchMeow/nm.sock`
- **macOS (App Store build):** `~/Library/Containers/io.github.aikusan.notchmeow.store/Data/nm.sock`
- **Windows:** `\\.\pipe\notchmeow-<user-SID>`
- **Linux:** `$XDG_RUNTIME_DIR/notchmeow.sock` (usually `/run/user/<uid>/notchmeow.sock`). Only your own user account can connect.

## Supported events

All standard Claude Code hook events are supported, **except `PermissionRequest`**:
approval cards are not yet implemented for third-party agents (only Claude Code gets
one). A `PermissionRequest` from an external agent is answered immediately with no
decision, so the relay writes nothing and the agent re-asks in its terminal.
Approval support for other agents will be added with Codex support.

The pill lifecycle:

| Event | Effect |
|---|---|
| `SessionStart` | Creates the pill (if absent), sets state to idle |
| `UserPromptSubmit` | State → thinking; prompt shown in ticker |
| `PreToolUse` | State → working; tool label shown in ticker |
| `PostToolUse` / `PostToolUseFailure` | State → working |
| `Notification` | Rate-limit or question state if applicable |
| `Stop` | State → finished for 5 s; active declared pills (catalog + checked in Settings) reset to idle — all others are removed |
| `StopFailure` | State → error |
| `SessionEnd` | Active declared pills (catalog + checked in Settings) reset to idle — all others are removed |
| `SubagentStart` / `SubagentStop` | Step added to ticker |

## Declared pills

A **declared pill** is a catalog entry (`PillCatalog.swift`) that has been enabled in **Settings** (the pill switches on the Agents, AI and chat and Services pages). When a session ends for a declared pill, the pill stays visible and resets to idle instead of disappearing.

A catalog pill that is not checked in Settings behaves like any other agent: it gets an automatic pill when a session starts, and that pill is removed when the session ends.

The GitHub build exposes Gemini CLI (`agent_gemini`) and Antigravity (`agent_antigravity`) in Settings (the pill switches on the Agents, AI and chat and Services pages). Cursor (`agent_cursor`) and Codex (`agent_codex`, GitHub build only) are there too — their pills can be declared and set as the main pill; session support is coming in a future version.

**Claude Code from the Claude app (every build).** Claude Code sessions started from the Code tab of the Claude app set `CLAUDE_CODE_ENTRYPOINT=claude-desktop` and have no terminal: the relay tags them `nm_agent: claude-desktop` by itself (an explicit `--agent` wins), so there is nothing to install. They show under the Claude Code pill (`integration_claude`), their host is the Claude app, and their permission requests stay in the Claude app (NotchMeow answers `ask`, so the app shows its own prompt). The ↗ button and the "Open Claude" button of the finished card open the Claude app. The old `agent_claude-desktop` pill ID stays frozen but no event reaches it. On Windows the ↗, the finished card's "Open Claude" button, a Sidekick nudge's button and a file dropped on the pill's cat start the Claude app (a classic install, its Start-menu shortcut, or the packaged app that the Start menu lists as "Claude"; **owed, not run here**: nothing ran on Windows, the install type is unverified, and the resolver's order is a guess, tested only with fake folders); on Linux, where Anthropic ships no desktop app, there is nothing to open.

## Real-world examples

### Gemini CLI (macOS, Windows and Linux)

NotchMeow supports Gemini CLI out of the box via **Settings → Gemini CLI → Install hooks**.
The installer writes to `~/.gemini/settings.json` (`%USERPROFILE%\.gemini\settings.json` on Windows) and uses `--agent gemini` so
Gemini sessions get their own pill. The relay translates Gemini event names to canonical
NotchMeow events automatically. All three platforms install the same six events (the four
below, plus `SessionStart` and `SessionEnd`) with the same timeouts, in milliseconds.

| Gemini CLI event | Canonical event |
|---|---|
| `BeforeTool` | `PreToolUse` |
| `AfterTool` | `PostToolUse` |
| `BeforeAgent` | `UserPromptSubmit` |
| `AfterAgent` | `Stop` |

`AfterModel` is not installed — it fires on every response chunk and would flood the island.

### Antigravity — `agy` (macOS, Windows and Linux)

NotchMeow supports Antigravity out of the box via **Settings → Antigravity → Install hooks**.
The installer writes to `~/.gemini/config/hooks.json` (`%USERPROFILE%\.gemini\config\hooks.json`
on Windows; timeouts in seconds), under its own top-level key `notchmeow`, and uses
`--agent antigravity`. The relay translates `toolCall.name` / `conversationId` to the
island's `tool_name` / `session_id`, and `workspacePaths[0]` to `cwd`.

| Antigravity event | Canonical event |
|---|---|
| `PreInvocation` | `UserPromptSubmit` |
| `PreToolUse` | `PreToolUse` |
| `PostToolUse` | `PostToolUse` |
| `PostInvocation` | `PostToolUse` |
| `Stop` | `Stop` |

For both agents the relay answers `{}` on stdout, their "no decision" (Antigravity's PreToolUse gets
`{"decision":"ask"}` instead, because it reads `{}` there as a denial), and exits at once when
NotchMeow is closed, so neither agent is ever blocked.

### Any other tool

Follow the generic pattern: call `nm-hook --agent <your-name> <EventName>` (macOS),
`notchmeow-hook.exe --agent <your-name> <EventName>` (Windows)
or `~/.local/share/notchmeow/bin/notchmeow-hook --agent <your-name> <EventName>` (Linux)
and let the relay forward the event.

## Quick test (Linux)

With NotchMeow running:

```sh
echo '{"hook_event_name":"UserPromptSubmit","session_id":"t1","prompt":"hello","nm_agent":"demo"}' \
  | ~/.local/share/notchmeow/bin/notchmeow-hook --agent demo
```

A "demo" pill should appear in the island.

## Quick test (macOS)

With NotchMeow running:

```sh
echo '{"hook_event_name":"UserPromptSubmit","session_id":"t1","prompt":"hello","nm_agent":"demo"}' \
  | /bin/sh ~/Library/Application\ Support/NotchBuddy/nm-hook --agent demo
```

A "demo" pill should appear in the island.
