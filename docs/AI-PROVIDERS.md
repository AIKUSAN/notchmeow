# AI providers

NotchMeow's macOS and Windows/Linux apps talk to the same AI providers the same way.
The values live in one machine-readable file, `tests/fixtures/ai/providers.json`. Both
apps have a catalog test that fails if their built-in table drifts from it. To change a
port, default model or filter, change `providers.json` first, then both apps.

## Providers

| ID | Name | Placement | API | How it's found |
|---|---|---|---|---|
| `anthropic` | Anthropic | cloud | Messages API, streaming, web search | key in the keychain |
| `openai` | OpenAI | cloud | Responses API, streaming, web search, `store:false` | key in the keychain |
| `google` | Google | cloud | OpenAI-compatible chat completions | key in the keychain |
| `ollama` | Ollama | local | OpenAI-compatible | `GET 127.0.0.1:11434/api/version` |
| `lmstudio` | LM Studio | local | OpenAI-compatible | `GET 127.0.0.1:1234/v1/models` |
| `llamacpp` | llama.cpp | local | OpenAI-compatible | `GET 127.0.0.1:8080/health` |
| `jan` | Jan | local | OpenAI-compatible | `GET 127.0.0.1:1337/v1/models` |
| `apple` | Apple on-device | local | Foundation Models (macOS 26+) | `SystemLanguageModel.default.availability` |
| `custom` | Local server | local or network | OpenAI-compatible | added by the user |
| `claudeCode` | Claude plan | cloud | the user's own installed Claude Code, run as a process (stream-json) | found on disk, then `claude auth status` |

A `custom` server is `local` when its host is 127.0.0.1, ::1 or localhost, and `network` otherwise.

`custom.keychainKey` in `providers.json` (`custom-server-key`) is a prefix, not a whole key name. Each user-added
server stores its key as `custom-server-key.<serverId>`, where `serverId` matches `^[a-z0-9-]{1,32}$`. One keychain
item per server, and more than one custom server is allowed.

## Auto

Auto tries the Preferred cloud (Claude plan, Claude API key or OpenAI), then the others of those three, then Google,
using the first one that is ready: one with a key, or `claudeCode` once the user connected it and the last check found
Claude Code signed in (the apps put it in `keys` for the router). Without a key, it uses the last-used local model, then the
first ready local model, then Apple on-device. A temporary cloud failure retries once on a
local model. See `tests/fixtures/ai/router-cases.json` for every rule as a test case.

## Claude Code (`claudeCode`)

The UI calls it **Use my Claude plan**, with the plain-text note "runs your installed Claude Code"; never "Claude Code" as
a label. NotchMeow runs the user's own, unmodified `claude` program, one process per chat turn, and never sees, stores or
forwards a login. Mac and Windows/Linux; the Mac App Store build compiles it out. The Mac App Store build has no Connect Claude box and no Claude Code engine; its existing Anthropic API field is the API-key path. Everything below is pinned by
`tests/fixtures/ai/claude-code/`; `claude-code/reference.py` is the tie-breaker.

- **Command line.** `claude -p --input-format stream-json --output-format stream-json --verbose --include-partial-messages`,
  then `--session-id <uuid>` on a chat's first turn or `--resume <id>` after, `--model sonnet|opus|haiku`, and the level's
  flags (`expected-args.json`). Every quoted value is one argument. Never `--bare`.
- **Levels**, per chat, every new chat starting at **Chat only**: Chat only (an empty folder NotchMeow owns, web search and
  fetch), Read-only (a folder the user picks, read tools), Agent (the same folder, every edit and command behind NotchMeow's
  approval card). In Agent level the user's own Claude Code setup loads as in a terminal (CLAUDE.md, MCP servers, plugins, hooks and its permission rules), so a tool the user's own rules already allow (an `allow` rule, or a permissive mode in their settings) runs without a card, and the folder chosen for Agent may carry its own `.claude` settings; the card appears for every step that Claude Code would ask about. On native Windows Agent passes no sandbox settings: every command asks.
- **Environment.** `ANTHROPIC_API_KEY`, `ANTHROPIC_AUTH_TOKEN`, `CLAUDE_CODE_OAUTH_TOKEN`, `ANTHROPIC_PROFILE` and every
  `CLAUDE_CODE_USE_*` are dropped (case-insensitively on Windows), because they outrank the plan login (`expected-env.json`).
- **A session lives under its working folder.** A level change that keeps the folder resumes the session; one that moves it
  starts a new session, seeded with a recap of the chat, and retires the old id.
- **What a transcript means** (`expected-parse.json`, `transcripts/`): text deltas are the reply (assistant messages around
  a tool call are joined by a blank line); `tool_use` blocks are step rows that keep only `command`, `file_path`, `path`,
  `query`, `pattern` and `url`; `system/init` says who pays (`apiKeySource`: none or oauth is the plan; user, project, org or
  temporary is an API key; anything else says nothing).
- **Failures** map onto the twelve error kinds with a code in `AiError.code`: `nm_signed_out` (auth), `nm_plan_limit`
  (billing, with `resetsAt`), `nm_claude_missing` (unreachable), `nm_claude_old` and `nm_needs_git` and `nm_folder_missing`
  (bad_request), `nm_claude_offline` (unreachable), `nm_claude_crashed` (interrupted, or server when nothing was said). An
  unknown shape is a crash, never a guess. The exact JSON of Claude Code's failures is not documented: the owner's manual check
  confirms the shapes.
- **Approvals.** The hooks NotchMeow installs in `~/.claude/settings.json` still fire in `-p`. A `PermissionRequest` whose
  `session_id` is one of a chat's own ids goes to that chat's card (`hook-routing.json`); nothing in `nm_*` changes. With no
  decision Claude Code denies the step.
- **Finding it.** `~/.local/bin/claude`, the Homebrew prefixes, the npm global bin, the login shell's `PATH`; on Windows
  `%USERPROFILE%\.local\bin\claude.exe` first (`locator-cases.json`). `claude --version` must be at least the pinned minimum
  (`versions.json`); `claude auth status` gives `authMethod` (`auth-status.json`) and nothing else is kept.

## Reply length

Each app asks for at most `maxOutputTokens` tokens in a reply, by the placement of the model that answers
(`providers.json`): 16,000 for cloud models, 4,096 for local and network ones. OpenAI's reasoning models spend
hidden reasoning tokens from the same cap, so a smaller cloud cap could leave an empty reply. Local servers
keep 4,096, which is what the macOS app already sent to them.

## Long chats

A small model has a small context, so a long chat is trimmed before it is sent. The rule is the same in both
apps and is spelled out in `tests/fixtures/ai/history-cases.json`:

- A turn's size is its Unicode scalars: its text, plus the text of each attached file. An attached image or PDF counts 1,000.
- Tokens are estimated as scalars ÷ 3.5, rounded up. The input budget is the model's context (4,096 when unknown)
  minus a quarter kept for the reply.
- While the system prompt and the turns are over budget and more than one turn remains, the two oldest turns
  (a question and its answer) are dropped. The system prompt and the latest turn always stay.
- Cloud models are never trimmed. When turns were dropped, the chat says: "This chat got long, so I dropped the oldest messages."

## Rules

Exact values live in `providers.json` and the fixtures; `reference.py` decides any disagreement.

- **Text budget.** A file's text is cut to `floor(context × 7 / 4)` characters (Unicode scalars). The context is
  4,096 tokens when unknown. Cloud models are capped at 204,800 characters. The cut falls on a whole line.
  Three notices: "I read the first N lines.", "I read the first line.", and "I read the first part of this file."
  (not even one line fits, so the first `floor(...)` characters are kept).
- **Lines.** A line ends at `\n` only. A lone `\r`, U+2028 or U+0085 is not a line end. SSE lines may end in `\r\n`.
- **Timeouts (ms).** Probe 300. Connect: local 5,000, cloud 10,000. First token: local 60,000, cloud 30,000.
- **File limit.** 25 MB (26,214,400 bytes). A bigger file is rejected.
- **HTTP errors.** Billing markers win over the status code. Billing is: status 402; an error `type` or `code` of
  `billing_error`, `insufficient_quota`, `credit_balance_exhausted`, `organization_usage_limit_exceeded` or ending
  in `_spend_limit_exceeded`; or "credit balance" in the message. Then by status: 401 and 403 are `auth`;
  400, 404, 413 and 422 are `bad_request`; 429 is `rate_limited`; 503 and 529 are `overloaded`; other 5xx are
  `server`; anything else is `bad_request`. The `error` field may be a string, an object, or a list of objects
  (the first one is used); anything else counts as no marker. A classifier never throws.
- **Retry-After.** Counts only if it is ASCII digits (`^[0-9]+$`) and not 0. Anything else is null, and the app uses its default.
- **Mid-stream errors.** One mapping for OpenAI `error.code` and Anthropic `error.type`:

  | Code / type | Kind |
  |---|---|
  | `rate_limit_exceeded`, `rate_limit_error` | `rate_limited` |
  | `server_is_overloaded`, `slow_down`, `overloaded_error` | `overloaded` |
  | `server_error`, `api_error`, `timeout_error`, `vector_store_timeout` | `server` |
  | the billing codes above, `billing_error` | `billing` |
  | `invalid_prompt`, `image_content_policy_violation`, `content_policy_violation`, `content_filter` | `refusal` |
  | `authentication_error`, `invalid_api_key`, `permission_error` | `auth` |
  | anything else (`invalid_request_error`, `context_length_exceeded`, unknown codes) | `bad_request` |

  Only `offline`, `unreachable`, `timeout`, `server`, `rate_limited` and `overloaded` are temporary, so Auto
  falls back to a local model only for those. An unknown code never falls back.
- **Model filters.** Strip a leading `models/` (Google), then drop any id whose lowercase form contains one of the
  `exclude` strings for its provider (case-insensitive substring). OpenAI also keeps only ids that start with one
  of its `includePrefixes`.
- **Custom key.** `custom-server-key.<serverId>`, as above.

## Fixture formats

| File | Shape |
|---|---|
| `router-cases.json` | `defaults` plus `cases[]` of `{name, input, expect}`; merge `defaults` under each `input` |
| `http-errors.json` | `cases[]` of `{status, headers, body, kind, retryAfter}` |
| `budget-cases.json` | `cases[]` of `{name, placement, contextTokens, lineLength, lineCount, expect{keptChars, keptLines, notice}}` |
| `history-cases.json` | `rule{reservedOutputDivisor, binaryAttachmentChars, notice}` plus `cases[]` of `{name, placement, contextTokens, system, turns[{role, text, files[]}], expect{dropped, notice}}`; a `text` is `{fill, count}`, `fill` repeated `count` times |
| `attachment-cases.json` | `cases[]` of `{file, kind, reason?, mime?, contains?, notContains?}`; run `make_attachments.py <dir>` first |
| `claude-code/fake_claude.py` | a stand-in for `claude` that records its argv, environment and stdin and replays a transcript (see its docstring); never contacts anything |
| `claude-code/transcripts/*.jsonl` | what the fake prints: success, tool use, signed out, plan limit, offline, crash and a few more, built from the documented shapes |
| `claude-code/expected-args.json` | `cases[]` of `{name, platform, level, model, resume, sessionId, folder?, cwd, argv}` |
| `claude-code/expected-env.json` | the stripped names and prefixes, and `cases[]` of `{name, platform, base, expect}` |
| `claude-code/expected-parse.json` | `cases[]` of `{name, transcript, exit, stderr, platform, expect{engine, text, steps, finish, error}}` |
| `claude-code/auth-status.json`, `versions.json`, `locator-cases.json`, `hook-routing.json`, `labels.json`, `copy.json` | the other rules above, one file each |
| `sse/<format>/<name>.txt` | a raw SSE stream exactly as sent on the wire |
| `sse/<format>/<name>.expected.json` | `{text, toolCalls[{id,name,arguments}], citations[{url,title}], refusal, finish, error}` |

`tests/fixtures/ai/reference.py` is the tie-breaker: if an app and a fixture disagree,
the reference decides.
