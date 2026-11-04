# E3. Connect Claude: your Claude plan or an API key, design

- **Status:** design approved in conversation on 2026-10-06; implemented on the Mac and on Windows/Linux (branch e3/connect-claude), pending the owner's checks with a real Claude Code.
- **Parent spec:** [`2026-10-03-notchmeow-design.md`](2026-10-03-notchmeow-design.md), sub-project E. Builds on [`2026-10-03-local-models-design.md`](2026-10-03-local-models-design.md) (E1, merged).

## Context

The owner wants Claude to be NotchMeow's main AI, and asked how apps like Hermes Agent (Nous Research) connect many models.

**Where things stand today:**
- Claude already is the main cloud provider on both apps. It is first in Auto's cloud order and the default preferred cloud, with `claude-sonnet-5-5` as its default model (`AICatalog.swift`, `ModelRouter.swift`, `windows/src-tauri/src/ai/router.rs`). It works through Anthropic's official Messages API with an API key stored in the Keychain.
- What's missing is the counterpart to OpenAI's "Sign in with ChatGPT": using the Claude plan (Pro or Max) the user already pays for, without an API key.

**What Anthropic allows** (Claude Code [legal and compliance](https://code.claude.com/docs/en/legal-and-compliance) and the [Agent SDK overview](https://code.claude.com/docs/en/agent-sdk/overview), read 2026-10-06):
- Not allowed:
  - offering Claude.ai login inside a third-party app;
  - routing requests through a user's Free, Pro or Max plan credentials;
  - collecting, storing or passing on Claude.ai credentials or session tokens.

  Anthropic enforced this in 2026 against tools that reused Claude Code's login (OpenCode removed its Claude Pro/Max support).
- Allowed: an end user signing in to the **unmodified Claude Code binary** with their own Claude plan, including when a product runs Claude Code. The conditions:
  - the binary is not modified and none of its sign-in methods are removed;
  - the product doesn't pay for, resell or intermediate the usage, so each user brings their own plan, API key or cloud credential;
  - the product's owner agrees to Anthropic's Commercial Terms;
  - the product may say in plain text that it runs Claude Code, but may not use "Claude Code" or Anthropic's names or logos as a product or feature name, or suggest endorsement.

**How Hermes Agent does it** ([providers](https://github.com/NousResearch/hermes-agent/blob/main/website/docs/integrations/providers.md), [provider runtime](https://hermes-agent.nousresearch.com/docs/developer-guide/provider-runtime)):
- Every provider is a plugin that declares an API mode: OpenAI-style chat, native Anthropic Messages or Codex Responses. A fallback chain sits on top. NotchMeow's E1 layer already has this shape.
- For Claude it offers an API key, and also reuses Claude Code's login and token files. NotchMeow will not copy the latter.
- Its newest route is an experimental plugin that runs the user's own `claude` program as a subprocess, which is the route this spec takes.

## Decisions

| Topic | Decision |
|---|---|
| Scope | **A + B now, C later.** (A) Use my Claude plan, through the user's installed Claude Code. (B) A smoother "Connect Claude" setup for an API key. (C) OpenRouter, Amazon Bedrock and Google Vertex as providers, in a later small spec. |
| How the plan is used | NotchMeow runs the user's own installed, unmodified `claude` program for each chat turn. Claude Code signs in through Anthropic's own flow; NotchMeow never sees, stores or forwards a login. |
| What Claude may do | Three levels, picked **per chat** with a chip next to the model chip; every new chat starts at **Chat only**. Read-only and Agent ask for a folder. |
| Approvals | Agent mode asks before every edit and every command, with NotchMeow's existing approval card shown in the chat. Nothing runs without a click. |
| Platforms | **Mac and Windows/Linux**, Mac built first. The Mac App Store build compiles the Claude Code engine out and offers only the API-key path. |
| Naming | The engine is called **"Use my Claude plan"** in the UI, with the plain-text note "runs your installed Claude Code". Never "Claude Code" as a label. |

**Out of scope:**
- **C** (OpenRouter, Bedrock, Vertex);
- any Claude.ai sign-in inside NotchMeow, and any reuse of Claude Code's tokens or Keychain items;
- the Claude Agent SDK, which would need a bundled Node or Python runtime and is meant for API keys;
- installing Claude Code for the user (NotchMeow links to Anthropic's installer);
- App Attest (developer-paid usage on Apple platforms, in beta).

## 1. What the user sees

**Connect Claude** appears on the first run, and in Settings → AI as a new "Connect Claude" row above the existing provider list. It is a small card in the app's existing style, with two paths:

1. **Use my Claude plan.** NotchMeow looks for Claude Code:
   - **Not installed:** a short guide with Anthropic's install link.
   - **Installed, signed out:** a "Sign in" button. It opens Terminal (Windows Terminal or PowerShell on Windows) running `claude auth login`, and Claude Code's own sign-in completes in the browser.
   - **Signed in:** a check mark, the version, the sign-in method Claude Code reports, and "Claude is now your main AI".
2. **Paste an API key** from the Claude Console. It is checked and saved in the Keychain, as Settings → AI does today.

Choosing either path sets the preferred cloud to that engine. The App Store build shows no Connect Claude box: its Settings → AI stays as it ships, and its existing API-key field is the API-key path.

**In the chat:**
- **Model chip:** reads "Claude · your plan" when the engine runs on the user's plan, "Claude · API key" when Claude Code reports that it runs on an API key, or "Auto · claude-sonnet-5-5" as today. Its picker offers Sonnet, Opus and Haiku through Claude Code's model aliases.
- **Level chip** (new):
  - **Chat only** (the default for every new chat): answers, dropped files, web search and fetch.
  - **Read-only · folder:** also reads and searches files in that folder.
  - **Agent · folder:** also edits files and runs commands there, each step behind an approval card.
  - Choosing Read-only or Agent opens a folder picker. The chip then shows the folder's name.
- **Agent steps** appear in the chat as the same step rows the session view already uses ("Reading…", "Editing…"). Approvals use the existing card.
- **The cat** reacts as it does for any chat: thinking while Claude works, and the rate-limit look when the plan's limit is reached.

The level chip is the only addition to the existing chat view; everything else keeps its current look (CLAUDE.md: never restyle shipping views).

## 2. Architecture

**A new provider** sits beside Anthropic, OpenAI, the OpenAI-compatible servers and Apple on-device:
- **Mac:** `NotchBuddy/Sources/App/AI/Core/ClaudeCodeProvider.swift` (using `Process`), plus `ClaudeCodeLocator.swift` (finding the program and reading its sign-in status).
- **Windows/Linux:** `windows/src-tauri/src/ai/claude_code.rs` (using `std::process::Command`).
- Its ID is `claudeCode`, with placement `cloud` (the model runs on Anthropic's servers). It is listed in `tests/fixtures/ai/providers.json`, and Auto's preferred-cloud choice gains it.

**One turn is one run of the user's Claude Code:**

```
claude -p --input-format stream-json --output-format stream-json --verbose --include-partial-messages
       --session-id <uuid>          (first turn; NotchMeow picks the id)
       --resume <session_id>        (later turns)
       --model sonnet|opus|haiku
       <the level's flags, below>
```

- NotchMeow writes the new user message to stdin as one line in the documented `SDKUserMessage` shape (`{"type":"user","message":{"role":"user","content":[…]}}`), then closes stdin. A dropped image or PDF goes in as a content block, and other files as their extracted text, as in E1.
- It reads stdout line by line:
  - `system/init` gives the session id, the model and how the run was paid for;
  - `stream_event` text deltas make up the streamed reply;
  - `tool_use` blocks become step rows;
  - `result` ends the turn.
- Claude Code keeps the conversation's history in its own session. NotchMeow sends only the new message.
- Stop cancels the run by terminating the process.

**Keeping it on the user's plan:**
- The run's environment drops `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`, `ANTHROPIC_PROFILE` and every `CLAUDE_CODE_USE_*` variable, which would otherwise outrank the user's plan login.
- An `apiKeyHelper` in the user's own Claude Code settings still wins over the plan. The model chip shows what `system/init` reports, so the label is always true.

**The three levels** map to Claude Code's documented limits:

| Level | Working folder | Flags |
|---|---|---|
| Chat only | an empty folder NotchMeow owns (`Application Support/NotchMeow/claude-chat/`, Windows `%APPDATA%\NotchMeow\claude-chat\`) | `--safe-mode --tools "WebSearch,WebFetch" --allowedTools "WebSearch,WebFetch" --disallowedTools "mcp__*" --permission-mode dontAsk` |
| Read-only | the chosen folder | `--safe-mode --tools "Read,Grep,Glob,WebSearch,WebFetch" --allowedTools "Read,Grep,Glob,WebSearch,WebFetch" --permission-mode dontAsk --settings '{"permissions":{"blockReadsOutsideWorkingDirectories":true}}'` |
| Agent | the chosen folder | `--permission-mode default --settings '{"sandbox":{"enabled":true,"allowUnsandboxedCommands":false,"autoAllowBashIfSandboxed":false}}'`. The user's own Claude Code setup (CLAUDE.md, MCP servers, plugins, hooks) loads, as in a terminal. |

- `--safe-mode` turns off CLAUDE.md, skills, plugins, hooks, MCP and auto memory while keeping the sign-in. It also keeps NotchMeow's own hooks from firing for the two lower levels, so a chat never shows up as an extra Claude Code pill in the notch.
- `dontAsk` makes Claude Code refuse anything outside the allowed tools, so those levels never need an approval.
- In Agent mode, Claude Code's sandbox confines commands on macOS and Linux. Native Windows has no command sandbox, so there every command asks.

**Finding Claude Code:**
- It looks in `~/.local/bin/claude`, the Homebrew prefixes, the npm global bin, the login shell's `PATH`, and `%USERPROFILE%\.local\bin\claude.exe` on Windows (preferring it over a Desktop `Claude.exe` that may shadow it on `PATH`).
- `claude --version` gives the version. `claude auth status` exits 0 when signed in, and its JSON gives `authMethod`.
- These checks run when Settings opens and before a chat's first turn, never on a timer (0 % CPU when hidden).

**The App Store build** compiles the provider, the locator and the plan card out behind a build flag, as it does the cat panel. `scripts/check-app-binary.sh appstore` fails if they are present.

## 3. Approvals and safety

- **Chat only and Read-only never ask:** anything outside their tools is refused by Claude Code (`dontAsk`).
- **Agent mode reuses NotchMeow's approval path:**
  - The hooks NotchMeow already installs in `~/.claude/settings.json` still fire in `-p` mode.
  - When `HookServer` gets a `PermissionRequest` whose `session_id` matches a chat's own session (NotchMeow chose the id with `--session-id`), the card opens inside that chat instead of a new pill. The chat's other hook events are swallowed (they never create a session or a pill); the step rows come from Claude Code's own stream.
  - Nothing runs without the user's click. If the hooks aren't installed or the app doesn't answer, Claude Code denies the step: in `-p` mode a request with no decision is denied.
  - The same matching happens in the Windows app's `island/hooks.ts`.
- **No new contract strings:** matching is by the session id Claude Code already sends, and no `nm_*` field changes.
- **Credentials:** NotchMeow never reads Claude Code's Keychain items, credential files or OAuth tokens, and never passes a login on. Sign-in always completes in Anthropic's own flow.
- **Re-check:** Anthropic's billing for programs that run Claude Code changed several times in 2026. The release checklist re-reads the legal page before shipping.

## 4. Errors and fallbacks

| What happens | How it's detected | What the chat shows |
|---|---|---|
| Claude Code not found | locator | "Claude Code isn't installed." + install guide |
| Signed out | `claude auth status` exit 1, or "Not logged in" in the result | "Claude Code is signed out." + a Sign in button |
| Plan limit reached | `rate_limit_event` with `status: "rejected"` and `resetsAt`, or a `rate_limit` error | the rate-limit cat and "Your Claude plan's limit resets at 3:45 pm" |
| Offline, Anthropic down | `api_retry` events then an error result | "Couldn't reach Claude." Auto falls back to the API key or a local model, as E1 does |
| Too old | `--version` below the minimum the plan pins | "Update Claude Code" |
| Crash or bad output | non-zero exit with no `result`, or a line that isn't JSON | "Claude stopped unexpectedly." with a retry |

## 5. Testing

- **A fake `claude`:** a small script in `tests/fixtures/ai/claude-code/` that records its arguments and environment, then prints a recorded stream-json transcript chosen by the test (success, tool use, signed out, plan limit, offline, crash). Both apps' tests run against it.
- **Mac tests:** a `scripts/test-claude-code.sh` program; **Windows tests:** Rust unit tests. Both cover:
  - the exact command line per level and per turn (first turn versus resumed);
  - the stripped variables;
  - stream parsing into text, steps and the `result`;
  - each error mapping;
  - `auth status` parsing and the locator's search order;
  - the App Store build having no Claude Code engine (`check-app-binary.sh`).
- **Approval routing:** a test feeds `HookServer` a `PermissionRequest` with a chat's session id and checks it reaches the chat, not a new pill. The same for `hooks.ts`.
- **No real account** is used by any test or agent. Trying it with the owner's own Claude Code is a manual check.

## Owner actions before a public release

1. Accept Anthropic's Commercial Terms. They are required to run Claude Code inside a product.
2. Re-check the legal page and Anthropic's billing for programs that run Claude Code.
3. Manual checks with a real Claude Code:
   - sign in and out;
   - each level;
   - an Agent approval;
   - a plan limit;
   - Windows with and without Git for Windows.

## Risks and open questions

- **Billing drift:** Anthropic paused a separate monthly credit for programs that run Claude Code in June 2026. If it returns, plan users may see a separate allowance.
- **Startup time:** each turn starts a new `claude` process. If that feels slow, a later version can keep one process per chat with `--input-format stream-json` on stdin.
- **Windows, no sandbox:** Agent mode asks for every command there.
- **Docs gaps:** the exact JSON of some failures and every `auth status` field beyond `authMethod` are not documented. The plan's fake transcripts are synthetic, built from the documented event shapes; the owner's checks with a real Claude Code confirm the undocumented failure shapes.
