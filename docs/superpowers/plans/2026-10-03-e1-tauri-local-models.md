# E1 Tauri Local Models Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Give NotchMeow for Windows and Linux every model the spec lists, all streaming and routed per feature. That means Anthropic and OpenAI as native providers, Google and any local or network OpenAI-compatible server through one adapter, Auto's single local retry, files read as the spec's table says, and the spec's chat and settings UI.

**Architecture:**
- A new Rust module, `windows/src-tauri/src/ai/`, holds:
  - the provider trait;
  - a pure router;
  - three SSE aggregators;
  - HTTP-error classification and the error wording;
  - the text budget;
  - localhost discovery;
  - three providers;
  - the attachment pipeline.

  Every part is tested against the shared E1-0 fixtures and fake server.
- A session layer runs one turn: route, stream, fall back at most once, and keep the history provider-neutral. It reports everything as events.
- Tauri commands expose the session. `ai_chat` streams over a `tauri::ipc::Channel`.
- The island's chat and the settings window gain the spec's UI on top.

**Tech Stack:**
- **Rust:**
  - Tauri 2.12;
  - `reqwest` 0.12 with rustls, already a dependency, streaming through `Response::chunk()` so no new feature is needed;
  - `tokio`, `serde_json`.
- **New crates:** `lopdf` 0.45 (MIT) and `zip` 8 (MIT).
- **Windows only:** the existing `windows` 0.61 crate's WinRT OCR and PDF APIs.
- **Front end:** TypeScript + Vite, no framework.
- **Tests and CI:** Python 3 standard library for the shared fixtures; GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-03-local-models-design.md` (revision 1, OpenAI first-class).

**Consumes:** `docs/superpowers/plans/2026-10-03-e1-0-shared-ai-contract.md`. That plan must be merged before Task 1. The sibling macOS plan is `2026-10-03-e1-mac-local-models.md`.

## Global Constraints

- **Contract names (verbatim from E1-0):**
  - **Provider IDs:** `anthropic`, `openai`, `google`, `ollama`, `lmstudio`, `llamacpp`, `jan`, `apple`, `custom`.
  - **Placements:** `local`, `network`, `cloud`.
  - **Error kinds:** `offline`, `unreachable`, `timeout`, `server`, `rate_limited`, `overloaded`, `auth`, `bad_request`, `billing`, `refusal`, `cancelled`, `interrupted`.
  - **Router outcomes:** `ok`, `fallback`, `error`, `retry_countdown`, `empty_state`, `interrupted`, `cancelled`.
- **UI-only notices (not contract names):** `cant_see`, `scanned_pdf`, `heic`, `rejected`, `unreadable`, `missing_model`, `outdated` and `empty_reply` are the island's own notices (`session::ProblemKind`). They are not among the 12 error kinds above, never reach the router, and travel as `AiEvent::Problem`, never as `AiEvent::Error`, whose `kind` is always one of the 12.
- **Semantics:** `tests/fixtures/ai/reference.py` defines them. Every Rust test loads its cases from `tests/fixtures/ai`, found through `env!("CARGO_MANIFEST_DIR")` + `../../tests/fixtures/ai`.
- **Timeouts (ms):**
  - probe 300;
  - connect: local 5000, cloud 10000;
  - first token: local 60000, cloud 30000.

  This plan adds one more: after the first bytes, 120 s of silence ends the stream as `interrupted`.
- **Limits:**
  - 25 MB = 26,214,400 bytes per file;
  - text budget = `floor(ctx × 7 / 4)` characters, which is half the context at 3.5 characters per token, computed in integers (`ctx * 7 / 4` on `u64`, never a float): ctx 4,097 gives 7,169, not 7,170;
  - a local model with unknown context counts as 4,096 tokens;
  - cloud is capped at 204,800 characters;
  - characters are `chars().count()`, never bytes;
  - **a line ends at `\n` only**, in the budget's line counting and in SSE line splitting. A lone `\r`, U+2028 and U+0085 are not line ends, and one trailing `\r` is dropped from an SSE line so `\r\n` still works. The budget uses `split_inclusive('\n')`; the SSE decoder scans bytes for `\n`. Neither uses `str::lines()`.
- **History trimming** (a long chat on a small model), exactly as `history-cases.json` and `reference.py`'s `trim_history` define it, counted in Unicode scalars:
  - cloud is never trimmed; `local` and `network` are, with `ctx` = the model's context, or 4,096 when unknown;
  - budget = `ctx − floor(ctx ÷ 4)` tokens;
  - `n` scalars cost `ceil(2n ÷ 7)` tokens (that is `n ÷ 3.5` in integers), taken over the system prompt plus all remaining turns in one sum;
  - a turn's size is its text plus each attached file's text, or 1,000 for an image or PDF sent as such;
  - while over budget and more than one turn remains, the oldest `min(2, remaining − 1)` turns go; the system prompt and the latest turn always stay, and an empty history drops nothing;
  - the notice (exact): `This chat got long, so I dropped the oldest messages.`
- **Truncation notices (exact):** `I read the first N lines.`, `I read the first line.`, `I read the first part of this file.`
- **Errors** (as `reference.py` defines them):
  - `classify_http`: a billing marker wins over the status. Billing is status 402, an error `type` or `code` of `billing_error`, `insufficient_quota`, `credit_balance_exhausted` or `organization_usage_limit_exceeded`, any code ending in `_spend_limit_exceeded`, or "credit balance" in the message. The `error` field may be an object, a list of objects (the first is used) or a string, and nothing in a body may make it panic;
  - `Retry-After` counts only as ASCII digits (`^[0-9]+$`) greater than 0; anything else is none;
  - **mid-stream errors** use one function, `errors::stream_error_kind`, for OpenAI `error.code` (Responses `response.failed` and `error` events) and Anthropic `error.type`. It shares `errors::is_billing` with `classify_http`. An unknown code, or an `error` that isn't an object, is `bad_request`: it never falls back, and only `offline`, `unreachable`, `timeout`, `server`, `rate_limited` and `overloaded` are temporary.
- **HTTP:**
  - All model HTTP goes through Rust `reqwest`, which is already in `windows/src-tauri/Cargo.toml` (0.12, `rustls-tls`, `json`). Streaming uses `Response::chunk()`, so no new feature or crate is needed.
  - Never use `tauri-plugin-http`. Never set an `Origin` header.
  - Local and network clients use `.no_proxy()`.
- **Keys:**
  - stored only through `secrets.rs`;
  - the server the user adds keeps its key as `custom-server-key.<serverId>`, where `serverId` matches `^[a-z0-9-]{1,32}$` (the contract allows several added servers, one key each). This app offers one, stored under the id `default`, so its key is `custom-server-key.default` (`catalog::keychain_name("custom")`). `secrets.rs` allows that prefix only with a valid id, and never the bare `custom-server-key`;
  - never returned to the webview, which only ever gets models, statuses or booleans;
  - never logged, and never printed: `Endpoint` and `Probe` have a hand-written `Debug` that redacts them;
  - which providers have one is read from the keychain once and cached until a key is saved or removed, so focusing a window never reads the keychain again.
- **Server URLs:** the server the user adds is stored in `settings.json` and sent to the webview without `user:pass@`, query or fragment (`discovery::clean_server_url`). Its key goes in the key field.
- **Logs:** event types, provider IDs, error kinds, HTTP status and request IDs only. Never prompts, file contents, file names or keys.
- **Debug redirect:** `NM_AI_BASE_URL_OVERRIDE` is read only under `#[cfg(debug_assertions)]`. Release builds don't contain it.
- **OpenAI:** every request sends `"store": false` and the whole conversation, and never `previous_response_id`.
- **OpenAI-compatible:** sends `max_tokens`; never `max_completion_tokens` or `tool_choice`.
- **Reply length:** every request asks for `providers.json`'s `maxOutputTokens` for the answering model's placement (`catalog::max_output_tokens`): 16,000 for cloud, 4,096 for local and network. A thinking model spends its `<think>` or hidden reasoning tokens from the cap: OpenAI's reasoning models could return nothing at 4,096, and 4,096 locally is what the Mac's `LocalChat` already sends.
- **File follow-ups stay on File questions:** a conversation that holds a file uses the File questions setting for every message in it, so file text never reaches a model the user didn't pick for files. The conversation's own messages decide (`featureFor(current, history)`), never `State.droppedFile`, which is never cleared. Dropping a file resets the conversation, and with it this rule. Continue and Retry reuse the setting of the reply they extend.
- **Empty replies:** a reply with no text is a failure: it never enters the history and never plays the finish sound.
- **Webview events:**
  - Streaming uses a Channel.
  - The only event this plan emits is the existing `settings-changed`, kebab-case like `screen-changed`.
  - Commands are snake_case like `chat_reset`.
- **Existing views keep their look (CLAUDE.md):**
  - New parts reuse the existing classes and tokens.
  - Copy changes only where the spec asks: the drop card line, the Settings section renamed **AI**, and the error table.
- **Where to run cargo:**
  - On Linux or Windows: in `windows/`, after building the relay once with `cargo build --release -p notchmeow-hook`.
  - On a Mac: `windows/scripts/cargo-linux.sh <args>` (Task 2) from anywhere in the repository, with Docker Desktop running.
  - Windows-only tests (Task 7) run on Windows or in CI.
- **TypeScript gate:** `cd windows && npx tsc --noEmit` prints nothing and exits 0.
- **Commits:** a local `git commit` per task, with the message ending `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. Never push.
- **Out of scope:**
  - E2 (the one-click runtime);
  - F (the cats' assistant);
  - anything in `NotchBuddy/`;
  - Apple on-device (macOS only);
  - `docs/INTEGRATIONS.md`, which the macOS plan updates once for both apps.

## Review Focus

1. **Sending again while a reply is still streaming** (Enter twice, or Retry hammered). The second send is refused and the first keeps streaming. Task 13's `one_turn_at_a_time` pins it.
2. **A local server that quit after discovery** (the user closed Ollama). The message says "Couldn't reach Ollama. Is its server on?", and the next message checks again instead of trusting the stale result. Task 12's `a_server_that_quit_after_discovery_is_reported_and_forgotten` pins it.
3. **A new file dropped while a reply is still streaming.** The drop resets the chat, and the old reply must never land in the new conversation. Task 12's `a_reply_to_a_reset_conversation_is_dropped` pins it.
4. **An explicit choice that went stale** (a cloud key removed, a local model deleted). The chat says what happened and never swaps in another model behind the user's back. Task 12's `stale_explicit_choices_say_what_happened` pins it.
5. **Windows paths reaching WinRT.** `std::fs::canonicalize` returns `\\?\C:\…`, and a user folder can be `C:\Users\Zoé`. OCR must still open the file. Task 13's `only_inbox_files_are_read_and_their_path_is_kept` and Task 7's `windows_ocr_survives_unicode_and_verbatim_paths` pin it.
6. **A follow-up question about a dropped file, with Chat on a cloud model and File questions on a local one.** The follow-up must stay on File questions: its history still holds the file's text, which would otherwise reach the cloud on message 2. Task 13's `check:ai` case "a file only on an earlier message still uses File questions" pins the rule, and Task 14's walk-through checks the cloud server's log.
7. **A provider that answers with an odd error shape** (`{"error":"model not found"}` from LM Studio, a list from Google, a mid-stream `error` that is a string, null or a list, an unknown error code, `Retry-After: ²`). Nothing panics, an unknown code is `bad_request` and never falls back to a local model, and a bad `Retry-After` is ignored. Task 3's `odd_error_bodies_never_panic` and `retry_after_is_ascii_digits_above_zero`, and Task 4's `odd_stream_errors_never_panic_and_never_fall_back`, pin it.

---

## File Structure

| Path | Responsibility |
|---|---|
| `windows/src-tauri/src/ai/mod.rs` | Module root; `AiState` (with the cached key presence); the Tauri commands `ai_discover`, `ai_list_models`, `ai_resolve` and `ai_prewarm` (both async), `ai_chat` (Channel) and `ai_cancel` |
| `windows/src-tauri/src/ai/provider.rs` | Contract types (`Placement`, `ErrorKind`, `ModelInfo`, `ChatRequest`, `ChatChunk`, `Aggregate`, `AiError`, `Endpoint` with a redacting `Debug`, `Timeouts`), the `ModelProvider` trait, `http_client` |
| `windows/src-tauri/src/ai/catalog.rs` | Built-in provider table mirroring `providers.json`; filters, defaults, the web-search tools, the reply length by placement (`max_output_tokens`), the keychain name of each provider (`keychain_name`: the added server's is `custom-server-key.default`), the debug redirect |
| `windows/src-tauri/src/ai/router.rs` | Pure `route()` = `reference.py`'s router |
| `windows/src-tauri/src/ai/errors.rs` | `classify_http`, `stream_error_kind` (the one mid-stream error mapping), transport errors, the spec's error wording and actions, the wording for empty replies, HEIC photos and scanned PDFs |
| `windows/src-tauri/src/ai/sse.rs` | Byte-level SSE decoder (lines end at `\n` only), the three aggregators, `<think>` hiding, `stream_request` |
| `windows/src-tauri/src/ai/budget.rs` | File text budget, and the contract's history trimming (`message_chars`, `messages_to_drop`) |
| `windows/src-tauri/src/ai/attachments.rs` | Classification, text extraction (PDF, docx, RTF, HTML), `prepare()` per model; Windows OCR |
| `windows/src-tauri/src/ai/discovery.rs` | Parallel 300 ms probes of localhost and the user's server; `clean_server_url` |
| `windows/src-tauri/src/ai/openai_compat.rs` | Google, Ollama, LM Studio, llama.cpp, Jan, custom |
| `windows/src-tauri/src/ai/anthropic.rs` | Claude (was `claude.rs`), now streaming |
| `windows/src-tauri/src/ai/openai.rs` | OpenAI Responses API, `store: false` |
| `windows/src-tauri/src/ai/session.rs` | Conversation (with each message's prepared files), one turn end to end, `AiEvent` (`Error` vs `Problem`), `resolve()` |
| `windows/src-tauri/src/ai/testkit.rs` | Test-only: fixtures, Python, the fake server, `canned_server` |
| `windows/src-tauri/src/{lib,settings,secrets,files,log,integrations}.rs` | Wiring, per-feature choices, keychain allowlist (with the `custom-server-key.<serverId>` prefix rule), drop-time reject, log capture for the leak test |
| `windows/src-tauri/src/claude.rs` | Deleted in Task 13 (moved into `ai/anthropic.rs`) |
| `windows/src/core/{bridge,state}.ts` | AI commands and types |
| `windows/src/core/feature.ts`, `windows/scripts/check-ai-ui.mjs`, `windows/package.json` | `featureFor` (File questions for a message that carries a file and for every later message of that conversation), its plain-Node check, the `check:ai` script |
| `windows/src/views/chat.ts` | Streaming chat, model chip and picker, caption, sources, notes, empty state |
| `windows/src/island/island.ts`, `windows/src/upload/canvas.ts`, `windows/src/views/{upload,views,icons}.ts` | Pending attachment, drop card line, yawn, Stop icon |
| `windows/src/settings/main.ts` + `settings.css` | The AI section's three boxes |
| `windows/src/style.css` | New chat classes |
| `windows/scripts/cargo-linux.sh` | Run cargo in Linux from a Mac |
| `.github/workflows/windows.yml`, `linux.yml` | `cargo test` on Windows; Linux also runs when fixtures change |
| `windows/README.md` | AI, files, platform differences, testing |

---

### Task 1: Contract check

E1-0 must land first. It includes the fake-server rule that tasks 8–12 rely on: hosted tools (`{"type": "web_search"}`, `{"type": "web_search_20260209", ...}`) never select the tool-call stream; only a client function tool does. It also includes the `webSearch` tool values and the `maxOutputTokens` reply lengths in `providers.json`, and `history-cases.json`.

**Files:** none modified.

**Interfaces:**
- **Consumes:** everything E1-0 creates under `tests/fixtures/ai/`, plus `tests/fake_local_llm.py` with `--persona`, `--fail`, `--delay`, `--log` and `has_client_tools()`.
- **Produces:** nothing new; a green baseline for Task 2.

- [ ] **Step 1: Check the contract is there**

Run: `bash scripts/test-ai-contract.sh`
Expected: `All AI contract checks passed`, then `Ran 13 tests … OK`. If the script is missing, stop: E1-0 has not landed.

Run: `grep -c "def has_client_tools" tests/fake_local_llm.py && python3 -c "import json;d=json.load(open('tests/fixtures/ai/providers.json'));print(d['webSearch']['anthropic']['type']);print(d['maxOutputTokens'])" && test -f tests/fixtures/ai/history-cases.json && echo history-cases`
Expected: `1`, then `web_search_20260209`, then `{'cloud': 16000, 'network': 4096, 'local': 4096}`, then `history-cases`.

Run: `python3 tests/fake_local_llm.py /tmp/nm-port & sleep 1; curl -s "http://127.0.0.1:$(cat /tmp/nm-port)/v1/models?limit=100"; kill %1`
Expected: `{"data": [{"id": "llama3.2", "object": "model"}, {"id": "nomic-embed-text", "object": "model"}]}`. The fake server ignores query strings, which Anthropic's model list (`?limit=100`) needs.

Nothing changes in this task, so there's nothing to commit.

### Task 2: AI module skeleton, provider catalog and CI

**Files:**
- Create: `windows/scripts/cargo-linux.sh`
- Create: `windows/src-tauri/src/ai/mod.rs`, `provider.rs`, `catalog.rs`, `testkit.rs`
- Modify: `windows/src-tauri/src/lib.rs:3` (add `mod ai;`)
- Modify: `windows/src-tauri/src/secrets.rs:9-19` (allowlist, plus the `custom-server-key.<serverId>` prefix rule) and add tests
- Modify: `.github/workflows/windows.yml` (Python + test step), `.github/workflows/linux.yml` (`pull_request.paths`)
- Create: `.github/workflows/windows-tests.yml` (read-only Windows tests on pull requests)

**Interfaces:**
- **Consumes:** `tests/fixtures/ai/providers.json`.
- **Produces:**
  - **From `provider.rs`:**
    - `Placement { Local, Network, Cloud }` with `as_str()`;
    - `ErrorKind`, the 12 kinds, with `is_temporary()` and `as_str()`;
    - `Finish { Stop, Length, ToolCalls, Refusal }`;
    - `Capabilities { tools, vision, json }`;
    - `ModelInfo { id, display_name, context_tokens: Option<u64>, capabilities }` with `ModelInfo::named(id)`;
    - `Role { User, Assistant }`;
    - `Part::{Text(String), FileText{name,text}, Image{name,mime,base64}, Pdf{name,base64}}`;
    - `Message { role, parts }` with `plain_text()`, plus `file_text(name, text)` and `file_label(name)`;
    - `ToolSpec`;
    - `ChatRequest { model, system, messages, tools, response_format, max_tokens }`;
    - `ChatChunk::{Text, ToolCall{index,id,name,arguments}, Citation{url,title}, Refusal, Finish, Error}`;
    - `ToolCall`, `Citation`;
    - `Aggregate { text, tool_calls, citations, refusal, finish, error }`;
    - `AiError { kind, status, retry_after, request_id, detail, code }` with `AiError::new(kind)`;
    - `Timeouts { connect, first_token, idle }` with `for_placement()`;
    - `Endpoint { provider, name, base_url, key, placement, timeouts }`, whose `Debug` is written by hand and prints the key as `<redacted>` and the URL as its host only;
    - `trait ModelProvider { id, display_name, placement, list_models, stream, prewarm }`;
    - `type BoxFuture`;
    - `http_client(&Endpoint, Option<Duration>) -> reqwest::Client`.
  - **From `catalog.rs`:**
    - `PROVIDERS: &[ProviderDef]`, `CLOUD_ORDER`, `LOCAL_SERVERS`;
    - filter lists;
    - timeout and limit constants;
    - `get`, `is_cloud`, `brand`, `billing_url`, `debug_override`, `base_url(id, override)`, `is_local_host`, `filter_models`, `default_model`, `cloud_capabilities`, `reads_pdf_natively`, `placement_of`;
    - the hosted web-search tools, as providers.json `webSearch` spells them: `web_search_tools(provider, model) -> Vec<Value>` and `anthropic_web_search_type(model)`, which gives older Claude models (`LEGACY_WEB_SEARCH_PREFIXES`) the `legacyType`. A test compares both with providers.json, so Tasks 9 and 10 send nothing hard-coded;
    - the reply length, as providers.json `maxOutputTokens` spells it: `max_output_tokens(Placement) -> u32` (cloud 16,000; local and network 4,096), over the constants `MAX_OUTPUT_TOKENS_CLOUD`, `_NETWORK` and `_LOCAL`. A test compares it with providers.json for every placement, and a second one pins the two values the product relies on;
    - the text budget as integers: `BUDGET_CHARS_NUMERATOR = 7` and `BUDGET_CHARS_DENOMINATOR = 4` (`floor(ctx × 7 / 4)` characters), which replace the two float constants; a test checks that providers.json's `budgetFractionOfContext × charsPerToken` is 7/4;
    - the keychain item of a provider: `keychain_name(id) -> Option<String>` and `CUSTOM_SERVER_ID = "default"`. providers.json's `custom.keychainKey` (`custom-server-key`) is a prefix, so the added server's item is `custom-server-key.default`; every other provider's item is its `keychain_key`.
  - **From `secrets.rs`:** the allowlist now also accepts `custom-server-key.<serverId>` when `serverId` matches `^[a-z0-9-]{1,32}$` (checked by hand, no regex crate), and never the bare `custom-server-key`. `set` and `clear` refuse anything else before touching the keychain.
  - **From `testkit.rs` (tests only):**
    - `fixtures_dir()`, `load_json(name)`, `python()`;
    - `TempDir`, `make_attachments()`;
    - `FakeServer::start(flags)` with `.base` and `.requests()`;
    - `canned_server(status, content_type, body) -> base_url`, one fixed response for what the fake server can't produce (a rejected key on `GET /v1/models`, a stream that ends inside `<think>`);
    - `sse_fixture(fmt, name)`.

- [ ] **Step 1: Add the Linux runner for Macs**

Create `windows/scripts/cargo-linux.sh`:

```bash
#!/usr/bin/env bash
# Runs cargo for the Windows/Linux app inside a Linux container, for anyone
# working on a Mac: the Tauri app only builds for Windows and Linux. Needs
# Docker Desktop running. Examples, from anywhere in the repository:
#
#   windows/scripts/cargo-linux.sh test -p notchmeow ai::router::
#   windows/scripts/cargo-linux.sh test --workspace
#
# The first run builds a small image with the app's Linux build dependencies and
# Python (the AI tests run the shared fixtures and the fake model server).
# Linux build output stays in Docker volumes, never in your windows/target.
set -euo pipefail

repo="$(cd "$(dirname "$0")/../.." && pwd)"
image="notchmeow-linux-dev"

if ! docker image inspect "$image" >/dev/null 2>&1; then
  docker build -t "$image" - <<'DOCKERFILE'
FROM rust:1-bookworm
RUN apt-get update \
 && apt-get install -y --no-install-recommends \
      libwebkit2gtk-4.1-dev libgtk-layer-shell-dev libayatana-appindicator3-dev \
      librsvg2-dev libssl-dev libdbus-1-dev python3 \
 && rm -rf /var/lib/apt/lists/*
DOCKERFILE
fi

# tauri-build refuses to run until the relay it bundles exists, so build it first.
exec docker run --rm \
  -v "$repo":/repo \
  -v notchmeow-linux-target:/repo/windows/target \
  -v notchmeow-linux-cargo:/usr/local/cargo/registry \
  -w /repo/windows \
  "$image" \
  bash -c 'cargo build --release -q -p notchmeow-hook && cargo "$@"' cargo-linux "$@"
```

Run: `chmod +x windows/scripts/cargo-linux.sh && bash -n windows/scripts/cargo-linux.sh && echo ok`
Expected: `ok`

- [ ] **Step 2: Create the module root, the contract types and the test kit**

Create `windows/src-tauri/src/ai/mod.rs`:

```rust
// NotchMeow's AI layer: providers, routing, streaming, files. Spec:
// docs/superpowers/specs/2026-10-03-local-models-design.md.
//
// Until Task 13 wires the commands, most of this is only reached by tests.
#![allow(dead_code)]

pub mod catalog;
pub mod provider;

#[cfg(test)]
pub mod testkit;
```

Create `windows/src-tauri/src/ai/provider.rs`:

```rust
// The types every model provider speaks. They mirror the shared contract in
// tests/fixtures/ai/ and docs/AI-PROVIDERS.md, so the names match the macOS app.

use std::fmt;
use std::future::Future;
use std::pin::Pin;
use std::time::Duration;

use serde::{Deserialize, Serialize};

use crate::ai::catalog;

pub type BoxFuture<'a, T> = Pin<Box<dyn Future<Output = T> + Send + 'a>>;

/// Where an answer comes from. Every reply in the chat is labelled with it.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Placement {
    Local,
    Network,
    Cloud,
}

impl Placement {
    pub fn as_str(self) -> &'static str {
        match self {
            Placement::Local => "local",
            Placement::Network => "network",
            Placement::Cloud => "cloud",
        }
    }
}

/// The contract's error kinds, spelled exactly as in tests/fixtures/ai/.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Hash, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ErrorKind {
    Offline,
    Unreachable,
    Timeout,
    Server,
    RateLimited,
    Overloaded,
    Auth,
    BadRequest,
    Billing,
    Refusal,
    Cancelled,
    Interrupted,
}

impl ErrorKind {
    /// A failure that a local model may answer instead (spec §5).
    pub fn is_temporary(self) -> bool {
        matches!(
            self,
            ErrorKind::Offline
                | ErrorKind::Unreachable
                | ErrorKind::Timeout
                | ErrorKind::Server
                | ErrorKind::RateLimited
                | ErrorKind::Overloaded
        )
    }

    pub fn as_str(self) -> &'static str {
        match self {
            ErrorKind::Offline => "offline",
            ErrorKind::Unreachable => "unreachable",
            ErrorKind::Timeout => "timeout",
            ErrorKind::Server => "server",
            ErrorKind::RateLimited => "rate_limited",
            ErrorKind::Overloaded => "overloaded",
            ErrorKind::Auth => "auth",
            ErrorKind::BadRequest => "bad_request",
            ErrorKind::Billing => "billing",
            ErrorKind::Refusal => "refusal",
            ErrorKind::Cancelled => "cancelled",
            ErrorKind::Interrupted => "interrupted",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Finish {
    Stop,
    Length,
    ToolCalls,
    Refusal,
}

#[derive(Debug, Clone, Default, PartialEq, Eq, Serialize, Deserialize)]
pub struct Capabilities {
    pub tools: bool,
    pub vision: bool,
    pub json: bool,
}

#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ModelInfo {
    pub id: String,
    /// What the picker and the reply caption show. The id when the server gives no name.
    pub display_name: String,
    pub context_tokens: Option<u64>,
    pub capabilities: Capabilities,
}

impl ModelInfo {
    pub fn named(id: &str) -> Self {
        ModelInfo {
            id: id.to_string(),
            display_name: id.to_string(),
            context_tokens: None,
            capabilities: Capabilities::default(),
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Role {
    User,
    Assistant,
}

/// One piece of a message. A dropped file becomes one of the last three.
#[derive(Debug, Clone, PartialEq)]
pub enum Part {
    Text(String),
    /// A file's extracted text, already cut to the model's budget.
    FileText { name: String, text: String },
    Image { name: String, mime: String, base64: String },
    /// A PDF passed through untouched, for providers that read PDFs natively.
    Pdf { name: String, base64: String },
}

#[derive(Debug, Clone, PartialEq)]
pub struct Message {
    pub role: Role,
    pub parts: Vec<Part>,
}

impl Message {
    /// Every text part joined, for providers that take plain-string content.
    pub fn plain_text(&self) -> String {
        let mut out = Vec::new();
        for part in &self.parts {
            match part {
                Part::Text(t) => out.push(t.clone()),
                Part::FileText { name, text } => out.push(file_text(name, text)),
                Part::Image { name, .. } | Part::Pdf { name, .. } => out.push(file_label(name)),
            }
        }
        out.join("\n\n")
    }
}

/// How a file's text is introduced to every model, so all providers read it the same way.
pub fn file_text(name: &str, text: &str) -> String {
    format!("File: {name}\n\n{text}")
}

pub fn file_label(name: &str) -> String {
    format!("File: {name}")
}

/// A client-side tool. Unused in E1; F's cats will send them.
#[derive(Debug, Clone, PartialEq)]
pub struct ToolSpec {
    pub name: String,
    pub description: String,
    pub parameters: serde_json::Value,
}

#[derive(Debug, Clone, PartialEq)]
pub struct ChatRequest {
    pub model: String,
    pub system: String,
    pub messages: Vec<Message>,
    /// Unused in E1 (F adds tools); kept so the interface does not change later.
    pub tools: Vec<ToolSpec>,
    /// A JSON schema for structured output. Unused in E1.
    pub response_format: Option<serde_json::Value>,
    pub max_tokens: u32,
}

#[derive(Debug, Clone, PartialEq)]
pub enum ChatChunk {
    Text(String),
    ToolCall { index: usize, id: String, name: String, arguments: String },
    Citation { url: String, title: String },
    Refusal(String),
    Finish(Finish),
    Error(ErrorKind),
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ToolCall {
    pub id: String,
    pub name: String,
    pub arguments: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Citation {
    pub url: String,
    pub title: String,
}

/// A whole stream folded into one result: the shape of the `.expected.json` fixtures.
#[derive(Debug, Clone, Default, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Aggregate {
    pub text: String,
    pub tool_calls: Vec<ToolCall>,
    pub citations: Vec<Citation>,
    pub refusal: Option<String>,
    pub finish: Option<Finish>,
    pub error: Option<ErrorKind>,
}

/// A failure before any of the reply arrived. Carries nothing the user typed.
#[derive(Debug, Clone, PartialEq)]
pub struct AiError {
    pub kind: ErrorKind,
    pub status: Option<u16>,
    pub retry_after: Option<u64>,
    /// `x-request-id` / `request-id`, logged for support.
    pub request_id: Option<String>,
    /// The provider's own short error message (never our prompt), for bad requests and billing.
    pub detail: Option<String>,
    /// The provider's error code, e.g. `insufficient_quota`.
    pub code: Option<String>,
}

impl AiError {
    pub fn new(kind: ErrorKind) -> Self {
        AiError { kind, status: None, retry_after: None, request_id: None, detail: None, code: None }
    }
}

/// Connection and first-token limits. Spec §5: local 5 s / 60 s, cloud 10 s / 30 s.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub struct Timeouts {
    pub connect: Duration,
    pub first_token: Duration,
    /// Silence after the first token that counts as a cut stream.
    pub idle: Duration,
}

impl Timeouts {
    pub fn for_placement(placement: Placement) -> Self {
        let (connect, first) = match placement {
            Placement::Cloud => (catalog::CONNECT_CLOUD_MS, catalog::FIRST_TOKEN_CLOUD_MS),
            Placement::Local | Placement::Network => {
                (catalog::CONNECT_LOCAL_MS, catalog::FIRST_TOKEN_LOCAL_MS)
            }
        };
        Timeouts {
            connect: Duration::from_millis(connect),
            first_token: Duration::from_millis(first),
            idle: Duration::from_secs(120),
        }
    }
}

/// Everything a provider needs to reach one model. Keys stay in here, on the Rust side.
///
/// `Debug` is written by hand: a derived one would print the key into any failed
/// assertion, panic message or `{:?}` log line.
#[derive(Clone, PartialEq)]
pub struct Endpoint {
    /// Catalog id: anthropic, openai, google, ollama, lmstudio, llamacpp, jan or custom.
    pub provider: String,
    /// "Ollama", "LM Studio", "Local server (OpenAI-compatible)", "Anthropic"…
    pub name: String,
    pub base_url: String,
    pub key: Option<String>,
    pub placement: Placement,
    pub timeouts: Timeouts,
}

impl fmt::Debug for Endpoint {
    fn fmt(&self, f: &mut fmt::Formatter<'_>) -> fmt::Result {
        f.debug_struct("Endpoint")
            .field("provider", &self.provider)
            .field("name", &self.name)
            // The host only: a URL typed in by hand could once have carried `user:pass@`.
            .field("host", &reqwest::Url::parse(&self.base_url).ok().and_then(|u| u.host_str().map(str::to_string)))
            .field("key", &self.key.as_ref().map(|_| "<redacted>"))
            .field("placement", &self.placement)
            .field("timeouts", &self.timeouts)
            .finish()
    }
}

pub trait ModelProvider: Send + Sync {
    fn id(&self) -> &str;
    /// Part of the shared interface (spec §1); F's assistant shows it.
    #[allow(dead_code)]
    fn display_name(&self) -> &str;
    fn placement(&self) -> Placement;
    fn list_models(&self) -> BoxFuture<'_, Result<Vec<ModelInfo>, AiError>>;
    /// Streams one reply into `sink`. `Err` means nothing arrived; a stream that
    /// breaks after the first token returns `Ok` with `Aggregate::error` set.
    fn stream<'a>(
        &'a self,
        request: &'a ChatRequest,
        sink: &'a mut (dyn FnMut(ChatChunk) + Send),
    ) -> BoxFuture<'a, Result<Aggregate, AiError>>;
    /// Loads a local model ahead of the first message. A no-op where it isn't needed.
    fn prewarm<'a>(&'a self, _model: &'a str) -> BoxFuture<'a, ()> {
        Box::pin(async {})
    }
}

/// The HTTP client for one endpoint. Local and network servers bypass any system
/// proxy. Nothing here sets an `Origin` header: Ollama refuses Windows' webview
/// origin, which is why every model call goes through Rust.
pub fn http_client(endpoint: &Endpoint, total: Option<Duration>) -> reqwest::Client {
    let mut b = reqwest::Client::builder().connect_timeout(endpoint.timeouts.connect);
    if endpoint.placement != Placement::Cloud {
        b = b.no_proxy();
    }
    if let Some(t) = total {
        b = b.timeout(t);
    }
    b.build().unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn an_endpoint_never_prints_its_key() {
        let endpoint = Endpoint {
            provider: "custom".into(),
            name: "studio-pc".into(),
            base_url: "http://me:hunter2@studio-pc:11434".into(),
            key: Some("sk-live-SECRET".into()),
            placement: Placement::Network,
            timeouts: Timeouts::for_placement(Placement::Network),
        };
        for printed in [format!("{endpoint:?}"), format!("{endpoint:#?}")] {
            assert!(!printed.contains("sk-live-SECRET"), "the key was printed: {printed}");
            assert!(!printed.contains("hunter2"), "a URL password was printed: {printed}");
            assert!(printed.contains("<redacted>") && printed.contains("studio-pc"), "{printed}");
        }
        let keyless = Endpoint { key: None, ..endpoint };
        assert!(format!("{keyless:?}").contains("key: None"));
    }
}
```

Create `windows/src-tauri/src/ai/testkit.rs`:

```rust
// Test helpers shared by the ai tests: the shared fixtures, Python, and the fake
// model server from tests/fake_local_llm.py. Compiled for `cargo test` only.

use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicU32, Ordering};
use std::time::{Duration, Instant};

use serde_json::Value;

/// tests/fixtures/ai at the repository root.
pub fn fixtures_dir() -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR")).join("../../tests/fixtures/ai")
}

pub fn load_json(name: &str) -> Value {
    let path = fixtures_dir().join(name);
    let text = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("read {}: {e}", path.display()));
    serde_json::from_str(&text).unwrap_or_else(|e| panic!("parse {}: {e}", path.display()))
}

/// `python3` on Linux and macOS, `python` (or the `py` launcher) on Windows runners.
pub fn python() -> Command {
    for (exe, args) in [("python3", &[][..]), ("python", &[][..]), ("py", &["-3"][..])] {
        let ok = Command::new(exe)
            .args(args)
            .arg("--version")
            .stdout(Stdio::null())
            .stderr(Stdio::null())
            .status()
            .map(|s| s.success())
            .unwrap_or(false);
        if ok {
            let mut cmd = Command::new(exe);
            cmd.args(args);
            return cmd;
        }
    }
    panic!("Python 3 is needed for the AI tests (python3, python or py -3)");
}

static COUNTER: AtomicU32 = AtomicU32::new(0);

/// A fresh, empty temporary directory, removed when dropped.
pub struct TempDir(pub PathBuf);

impl TempDir {
    pub fn new(tag: &str) -> Self {
        let n = COUNTER.fetch_add(1, Ordering::Relaxed);
        let dir = std::env::temp_dir().join(format!("nm-ai-{tag}-{}-{n}", std::process::id()));
        let _ = std::fs::remove_dir_all(&dir);
        std::fs::create_dir_all(&dir).unwrap();
        TempDir(dir)
    }

    pub fn path(&self) -> &Path {
        &self.0
    }
}

impl Drop for TempDir {
    fn drop(&mut self) {
        let _ = std::fs::remove_dir_all(&self.0);
    }
}

/// Runs tests/fixtures/ai/make_attachments.py into a temporary directory.
pub fn make_attachments() -> TempDir {
    let dir = TempDir::new("att");
    let status = python()
        .arg(fixtures_dir().join("make_attachments.py"))
        .arg(dir.path())
        .status()
        .expect("run make_attachments.py");
    assert!(status.success(), "make_attachments.py failed");
    dir
}

/// tests/fake_local_llm.py on a free port, killed when dropped.
pub struct FakeServer {
    pub base: String,
    log: PathBuf,
    child: Child,
    _dir: TempDir,
}

impl FakeServer {
    /// `flags` are the server's own: `--persona ollama`, `--fail 429`, `--delay 2`…
    pub fn start(flags: &[&str]) -> Self {
        let dir = TempDir::new("fake");
        let port_file = dir.path().join("port");
        let log = dir.path().join("requests.jsonl");
        let script = Path::new(env!("CARGO_MANIFEST_DIR")).join("../../tests/fake_local_llm.py");
        let child = python()
            .arg(script)
            .arg(&port_file)
            .arg("--log")
            .arg(&log)
            .args(flags)
            .stdout(Stdio::null())
            .stderr(Stdio::inherit())
            .spawn()
            .expect("start the fake server");
        let started = Instant::now();
        loop {
            if let Ok(port) = std::fs::read_to_string(&port_file) {
                if !port.trim().is_empty() {
                    // The port is written just before serve_forever; give it a moment to listen.
                    std::thread::sleep(Duration::from_millis(50));
                    return FakeServer { base: format!("http://127.0.0.1:{}", port.trim()), log, child, _dir: dir };
                }
            }
            assert!(started.elapsed() < Duration::from_secs(10), "fake server did not start");
            std::thread::sleep(Duration::from_millis(20));
        }
    }

    /// Every request the server received: `{method, path, origin, body}`.
    pub fn requests(&self) -> Vec<Value> {
        std::fs::read_to_string(&self.log)
            .unwrap_or_default()
            .lines()
            .filter_map(|l| serde_json::from_str(l).ok())
            .collect()
    }
}

impl Drop for FakeServer {
    fn drop(&mut self) {
        let _ = self.child.kill();
        let _ = self.child.wait();
    }
}

/// A server that answers every request with one fixed response, for what the fake model
/// server can't produce: a rejected key on `GET /v1/models`, a stream that ends inside
/// `<think>`. Returns its base URL; it runs until the test process exits.
pub fn canned_server(status: u16, content_type: &str, body: &str) -> String {
    use std::io::{Read, Write};
    let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
    let base = format!("http://{}", listener.local_addr().unwrap());
    let response = format!(
        "HTTP/1.1 {status} Canned\r\nContent-Type: {content_type}\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{body}",
        body.len()
    );
    std::thread::spawn(move || {
        for mut stream in listener.incoming().flatten() {
            // Read the whole request first (headers, then the body) so the client never sees a reset.
            let mut seen = Vec::new();
            let mut chunk = [0u8; 4096];
            let mut want: Option<usize> = None;
            loop {
                let n = match stream.read(&mut chunk) {
                    Ok(0) | Err(_) => break,
                    Ok(n) => n,
                };
                seen.extend_from_slice(&chunk[..n]);
                if want.is_none() {
                    if let Some(end) = seen.windows(4).position(|w| w == b"\r\n\r\n") {
                        let head = String::from_utf8_lossy(&seen[..end]).to_ascii_lowercase();
                        let length = head
                            .lines()
                            .find_map(|l| l.strip_prefix("content-length:"))
                            .and_then(|v| v.trim().parse::<usize>().ok())
                            .unwrap_or(0);
                        want = Some(end + 4 + length);
                    }
                }
                if want.is_some_and(|w| seen.len() >= w) {
                    break;
                }
            }
            let _ = stream.write_all(response.as_bytes());
            let _ = stream.flush();
        }
    });
    base
}

/// A fixture file under tests/fixtures/ai/sse/.
pub fn sse_fixture(format: &str, name: &str) -> String {
    std::fs::read_to_string(fixtures_dir().join("sse").join(format).join(name)).unwrap()
}
```

`Endpoint` holds an API key, so its `Debug` is written by hand: it prints `key: Some("<redacted>")` and the URL's host only. `provider.rs` ends with the test that pins it; Step 6 runs it. `testkit.rs` includes `canned_server`, which later tasks use for the replies the fake server can't give.

In `windows/src-tauri/src/lib.rs`, add `mod ai;` as the first line of the `mod` list, above `mod claude;`.

- [ ] **Step 3: Write the catalog tests first**

Create `windows/src-tauri/src/ai/catalog.rs` containing only this test module for now:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use crate::ai::testkit;
    use serde_json::Value;

    fn opt(v: Option<&str>) -> Value {
        v.map(|s| Value::String(s.into())).unwrap_or(Value::Null)
    }

    #[test]
    fn catalog_matches_providers_json() {
        let json = testkit::load_json("providers.json");
        let listed = json["providers"].as_array().unwrap();
        assert_eq!(listed.len(), PROVIDERS.len(), "provider count");
        for (want, have) in listed.iter().zip(PROVIDERS) {
            let id = have.id;
            assert_eq!(want["id"], id);
            assert_eq!(want["name"], have.name, "{id} name");
            assert_eq!(want["placement"], have.placement.as_str(), "{id} placement");
            assert_eq!(want["api"], have.api.as_str(), "{id} api");
            assert_eq!(want.get("baseURL").cloned().unwrap_or(Value::Null), opt(have.base_url), "{id} baseURL");
            assert_eq!(want.get("port").and_then(Value::as_u64), have.port.map(u64::from), "{id} port");
            assert_eq!(want.get("probePath").cloned().unwrap_or(Value::Null), opt(have.probe_path), "{id} probePath");
            assert_eq!(want.get("chatPath").cloned().unwrap_or(Value::Null), opt(have.chat_path), "{id} chatPath");
            assert_eq!(want.get("modelsPath").cloned().unwrap_or(Value::Null), opt(have.models_path), "{id} modelsPath");
            assert_eq!(want["keychainKey"], opt(have.keychain_key), "{id} keychainKey");
            assert_eq!(want["defaultModel"], opt(have.default_model), "{id} defaultModel");
        }
        let order: Vec<&str> = json["cloudOrder"].as_array().unwrap().iter().map(|v| v.as_str().unwrap()).collect();
        assert_eq!(order, CLOUD_ORDER);

        let strs = |v: &Value| -> Vec<String> { v.as_array().unwrap().iter().map(|s| s.as_str().unwrap().to_string()).collect() };
        let filters = &json["modelFilters"];
        assert_eq!(strs(&filters["local"]["exclude"]), LOCAL_EXCLUDE);
        assert_eq!(strs(&filters["google"]["exclude"]), GOOGLE_EXCLUDE);
        assert_eq!(strs(&filters["openai"]["includePrefixes"]), OPENAI_INCLUDE_PREFIXES);
        assert_eq!(strs(&filters["openai"]["exclude"]), OPENAI_EXCLUDE);

        let t = &json["timeoutsMs"];
        assert_eq!(t["probe"], PROBE_MS);
        assert_eq!(t["connectLocal"], CONNECT_LOCAL_MS);
        assert_eq!(t["connectCloud"], CONNECT_CLOUD_MS);
        assert_eq!(t["firstTokenLocal"], FIRST_TOKEN_LOCAL_MS);
        assert_eq!(t["firstTokenCloud"], FIRST_TOKEN_CLOUD_MS);

        let l = &json["limits"];
        assert_eq!(l["maxFileBytes"], MAX_FILE_BYTES);
        assert_eq!(l["cloudTextCapChars"].as_u64(), Some(CLOUD_TEXT_CAP_CHARS as u64));
        // 0.5 × 3.5 = 7/4: the budget is `ctx × 7 / 4` characters, in integers.
        let per_context = l["budgetFractionOfContext"].as_f64().unwrap() * l["charsPerToken"].as_f64().unwrap();
        assert_eq!(per_context * BUDGET_CHARS_DENOMINATOR as f64, BUDGET_CHARS_NUMERATOR as f64);
        assert_eq!(l["defaultLocalContextTokens"], DEFAULT_LOCAL_CONTEXT_TOKENS);
    }

    #[test]
    fn web_search_tools_match_the_contract() {
        let json = testkit::load_json("providers.json");
        let ws = &json["webSearch"];
        assert_eq!(ws.as_object().unwrap().len(), 2, "providers.json gained a web-search provider: give it a tool here");
        // OpenAI: exactly the contract's object.
        assert_eq!(web_search_tools("openai", "gpt-6.1-sol"), vec![ws["openai"].clone()]);
        // Anthropic: the contract's type, name and max_uses for a current model…
        let claude = &ws["anthropic"];
        let tool = |ty: &Value| json!({ "type": ty, "name": claude["name"], "max_uses": claude["max_uses"] });
        assert_eq!(web_search_tools("anthropic", "claude-sonnet-5-5"), vec![tool(&claude["type"])]);
        // …and `legacyType` for the model prefixes the contract lists.
        assert_eq!(claude["legacyType"], WEB_SEARCH_ANTHROPIC_LEGACY);
        let prefixes: Vec<&str> = claude["legacyModelPrefixes"].as_array().unwrap().iter().map(|p| p.as_str().unwrap()).collect();
        assert_eq!(prefixes, LEGACY_WEB_SEARCH_PREFIXES);
        for model in ["claude-haiku-4-5-20251001", "claude-3-7-sonnet"] {
            assert_eq!(web_search_tools("anthropic", model), vec![tool(&claude["legacyType"])], "{model}");
        }
        assert!(web_search_tools("google", "gemini").is_empty() && web_search_tools("ollama", "qwen3.5:2b").is_empty());
    }

    #[test]
    fn reply_length_follows_the_contract() {
        let json = testkit::load_json("providers.json");
        let lengths = json["maxOutputTokens"].as_object().unwrap();
        assert_eq!(lengths.len(), 3, "providers.json gained a placement: give it a reply length here");
        for placement in [Placement::Cloud, Placement::Network, Placement::Local] {
            assert_eq!(lengths[placement.as_str()], max_output_tokens(placement), "{}", placement.as_str());
        }
    }

    /// Pinned on purpose, so that an edit to providers.json (or to the constants) is noticed and decided on:
    /// OpenAI's reasoning models spend hidden reasoning tokens from the cap, and 4,096 is what the Mac's
    /// `LocalChat` already sends to local models.
    #[test]
    fn reply_length_is_16000_for_cloud_and_4096_for_local() {
        assert_eq!(max_output_tokens(Placement::Cloud), 16_000);
        assert_eq!(max_output_tokens(Placement::Local), 4_096);
        assert_eq!(max_output_tokens(Placement::Network), 4_096);
    }

    #[test]
    fn the_added_servers_keychain_item_is_the_prefix_plus_its_id() {
        // providers.json says `custom-server-key`; each added server is stored as `<that>.<serverId>`.
        assert_eq!(keychain_name("custom").as_deref(), Some("custom-server-key.default"));
        assert_eq!(keychain_name("anthropic").as_deref(), Some("anthropic-api-key"));
        assert_eq!(keychain_name("google").as_deref(), Some("google-api-key"));
        assert_eq!(keychain_name("ollama"), None);
        assert_eq!(keychain_name("nope"), None);
    }

    #[test]
    fn local_servers_are_the_catalog_ports_in_order() {
        let ports: Vec<u16> = LOCAL_SERVERS.iter().map(|id| get(id).unwrap().port.unwrap()).collect();
        assert_eq!(ports, [11434, 1234, 8080, 1337]);
    }

    #[test]
    fn filters_drop_embeddings_and_non_chat_models() {
        let ids = |v: Vec<ModelInfo>| v.into_iter().map(|m| m.id).collect::<Vec<_>>();
        let local = vec![ModelInfo::named("llama3.2"), ModelInfo::named("nomic-embed-text"), ModelInfo::named("bge-m3")];
        assert_eq!(ids(filter_models("ollama", local)), ["llama3.2"]);
        let openai = vec![
            ModelInfo::named("gpt-6.1-sol"), ModelInfo::named("text-embedding-3-large"),
            ModelInfo::named("gpt-6-audio-preview"), ModelInfo::named("o5-mini"), ModelInfo::named("dall-e-3"),
        ];
        assert_eq!(ids(filter_models("openai", openai)), ["gpt-6.1-sol", "o5-mini"]);
        let google = vec![ModelInfo::named("gemini-3-flash"), ModelInfo::named("imagen-4"), ModelInfo::named("gemini-3-pro")];
        assert_eq!(ids(filter_models("google", google)), ["gemini-3-flash", "gemini-3-pro"]);
    }

    #[test]
    fn default_models_follow_the_catalog() {
        assert_eq!(default_model("anthropic", &[]).as_deref(), Some("claude-sonnet-5-5"));
        assert_eq!(default_model("openai", &[]).as_deref(), Some("gpt-6.1-sol"));
        let google = [ModelInfo::named("gemini-3-pro"), ModelInfo::named("gemini-3-flash")];
        assert_eq!(default_model("google", &google).as_deref(), Some("gemini-3-flash"));
        assert_eq!(default_model("google", &google[..1]).as_deref(), Some("gemini-3-pro"));
        assert_eq!(default_model("google", &[]), None);
    }

    #[test]
    fn override_redirects_cloud_only() {
        assert_eq!(base_url("openai", None).as_deref(), Some("https://api.openai.com"));
        assert_eq!(base_url("openai", Some("http://127.0.0.1:9/")).as_deref(), Some("http://127.0.0.1:9"));
        assert_eq!(base_url("anthropic", Some("http://127.0.0.1:9")).as_deref(), Some("http://127.0.0.1:9"));
        assert_eq!(base_url("google", Some("http://127.0.0.1:9")).as_deref(), Some("http://127.0.0.1:9/v1"));
        assert_eq!(base_url("ollama", Some("http://127.0.0.1:9")).as_deref(), Some("http://127.0.0.1:11434"));
    }

    /// `cargo test --release` runs this one: a shipped app can't be redirected.
    #[cfg(not(debug_assertions))]
    #[test]
    fn release_builds_ignore_the_override() {
        std::env::set_var("NM_AI_BASE_URL_OVERRIDE", "http://127.0.0.1:9");
        assert_eq!(debug_override(), None);
    }

    #[cfg(debug_assertions)]
    #[test]
    fn debug_builds_read_the_override() {
        assert_eq!(BASE_URL_OVERRIDE_VAR, "NM_AI_BASE_URL_OVERRIDE");
    }

    #[test]
    fn custom_placement_depends_on_the_host() {
        assert_eq!(placement_of("custom", Some("127.0.0.1")), Placement::Local);
        assert_eq!(placement_of("custom", Some("[::1]")), Placement::Local);
        assert_eq!(placement_of("custom", Some("LOCALHOST")), Placement::Local);
        assert_eq!(placement_of("custom", Some("studio-pc")), Placement::Network);
        assert_eq!(placement_of("google", None), Placement::Cloud);
        assert_eq!(placement_of("jan", None), Placement::Local);
    }
}
```

- [ ] **Step 4: Run them to see them fail**

Run: `cargo test -p notchmeow catalog::`
Expected: FAIL to compile, with `cannot find value 'PROVIDERS' in this scope` and similar errors for the other catalog names.

- [ ] **Step 5: Write the catalog**

Put this above the test module in `catalog.rs`:

```rust
// The provider catalog: ids, URLs, ports, defaults, filters and limits.
// tests/fixtures/ai/providers.json is the source of truth shared with the macOS
// app; `catalog_matches_providers_json` fails if this table drifts from it.

use serde_json::{json, Value};

use crate::ai::provider::{Capabilities, ModelInfo, Placement};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Api {
    Anthropic,
    OpenAIResponses,
    OpenAIChat,
    Apple,
}

#[cfg(test)]
impl Api {
    pub fn as_str(self) -> &'static str {
        match self {
            Api::Anthropic => "anthropic",
            Api::OpenAIResponses => "openai-responses",
            Api::OpenAIChat => "openai-chat",
            Api::Apple => "apple",
        }
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum CatalogPlacement {
    Local,
    Cloud,
    /// `custom`: local on 127.0.0.1 / ::1 / localhost, network anywhere else.
    Computed,
}

#[cfg(test)]
impl CatalogPlacement {
    pub fn as_str(self) -> &'static str {
        match self {
            CatalogPlacement::Local => "local",
            CatalogPlacement::Cloud => "cloud",
            CatalogPlacement::Computed => "computed",
        }
    }
}

#[derive(Debug, Clone, Copy)]
pub struct ProviderDef {
    pub id: &'static str,
    pub name: &'static str,
    pub placement: CatalogPlacement,
    pub api: Api,
    pub base_url: Option<&'static str>,
    /// Already part of `base_url`; kept so the table reads like providers.json.
    #[cfg_attr(not(test), allow(dead_code))]
    pub port: Option<u16>,
    pub probe_path: Option<&'static str>,
    pub chat_path: Option<&'static str>,
    pub models_path: Option<&'static str>,
    /// providers.json `keychainKey`. For `custom` it is a prefix: use `keychain_name`.
    pub keychain_key: Option<&'static str>,
    pub default_model: Option<&'static str>,
}

pub const PROVIDERS: &[ProviderDef] = &[
    ProviderDef {
        id: "anthropic", name: "Anthropic", placement: CatalogPlacement::Cloud, api: Api::Anthropic,
        base_url: Some("https://api.anthropic.com"), port: None, probe_path: None,
        chat_path: Some("/v1/messages"), models_path: Some("/v1/models"),
        keychain_key: Some("anthropic-api-key"), default_model: Some("claude-sonnet-5-5"),
    },
    ProviderDef {
        id: "openai", name: "OpenAI", placement: CatalogPlacement::Cloud, api: Api::OpenAIResponses,
        base_url: Some("https://api.openai.com"), port: None, probe_path: None,
        chat_path: Some("/v1/responses"), models_path: Some("/v1/models"),
        keychain_key: Some("openai-api-key"), default_model: Some("gpt-6.1-sol"),
    },
    ProviderDef {
        id: "google", name: "Google", placement: CatalogPlacement::Cloud, api: Api::OpenAIChat,
        base_url: Some("https://generativelanguage.googleapis.com/v1beta/openai"), port: None, probe_path: None,
        chat_path: Some("/chat/completions"), models_path: Some("/models"),
        keychain_key: Some("google-api-key"), default_model: None,
    },
    ProviderDef {
        id: "ollama", name: "Ollama", placement: CatalogPlacement::Local, api: Api::OpenAIChat,
        base_url: Some("http://127.0.0.1:11434"), port: Some(11434), probe_path: Some("/api/version"),
        chat_path: Some("/v1/chat/completions"), models_path: Some("/v1/models"),
        keychain_key: None, default_model: None,
    },
    ProviderDef {
        id: "lmstudio", name: "LM Studio", placement: CatalogPlacement::Local, api: Api::OpenAIChat,
        base_url: Some("http://127.0.0.1:1234"), port: Some(1234), probe_path: Some("/v1/models"),
        chat_path: Some("/v1/chat/completions"), models_path: Some("/v1/models"),
        keychain_key: None, default_model: None,
    },
    ProviderDef {
        id: "llamacpp", name: "llama.cpp", placement: CatalogPlacement::Local, api: Api::OpenAIChat,
        base_url: Some("http://127.0.0.1:8080"), port: Some(8080), probe_path: Some("/health"),
        chat_path: Some("/v1/chat/completions"), models_path: Some("/v1/models"),
        keychain_key: None, default_model: None,
    },
    ProviderDef {
        id: "jan", name: "Jan", placement: CatalogPlacement::Local, api: Api::OpenAIChat,
        base_url: Some("http://127.0.0.1:1337"), port: Some(1337), probe_path: Some("/v1/models"),
        chat_path: Some("/v1/chat/completions"), models_path: Some("/v1/models"),
        keychain_key: None, default_model: None,
    },
    ProviderDef {
        id: "apple", name: "Apple on-device", placement: CatalogPlacement::Local, api: Api::Apple,
        base_url: None, port: None, probe_path: None, chat_path: None, models_path: None,
        keychain_key: None, default_model: Some("system"),
    },
    ProviderDef {
        id: "custom", name: "Local server", placement: CatalogPlacement::Computed, api: Api::OpenAIChat,
        base_url: None, port: None, probe_path: None,
        chat_path: Some("/v1/chat/completions"), models_path: Some("/v1/models"),
        keychain_key: Some("custom-server-key"), default_model: None,
    },
];

/// Auto's cloud order before the Preferred cloud is moved to the front.
pub const CLOUD_ORDER: [&str; 3] = ["anthropic", "openai", "google"];
/// Servers checked on 127.0.0.1, in this order.
pub const LOCAL_SERVERS: [&str; 4] = ["ollama", "lmstudio", "llamacpp", "jan"];

pub const LOCAL_EXCLUDE: &[&str] = &["embed", "bge-", "all-minilm", "clip", "rerank"];
pub const GOOGLE_EXCLUDE: &[&str] = &["embed", "imagen", "veo", "aqa", "tts", "audio", "live"];
pub const OPENAI_INCLUDE_PREFIXES: &[&str] = &["gpt-", "o1", "o3", "o4", "o5"];
pub const OPENAI_EXCLUDE: &[&str] = &[
    "embed", "tts", "whisper", "dall-e", "audio", "realtime", "moderat", "codex", "computer-use",
    "transcribe", "image", "sora", "babbage", "davinci", "instruct", "search", "live",
];

pub const PROBE_MS: u64 = 300;
pub const CONNECT_LOCAL_MS: u64 = 5_000;
pub const CONNECT_CLOUD_MS: u64 = 10_000;
pub const FIRST_TOKEN_LOCAL_MS: u64 = 60_000;
pub const FIRST_TOKEN_CLOUD_MS: u64 = 30_000;

pub const MAX_FILE_BYTES: u64 = 26_214_400;
pub const CLOUD_TEXT_CAP_CHARS: usize = 204_800;
/// A file's text budget is `ctx × 7 / 4` characters: half the context at 3.5 characters per token
/// (providers.json `budgetFractionOfContext` × `charsPerToken`), in integers so no platform rounds differently.
pub const BUDGET_CHARS_NUMERATOR: u64 = 7;
pub const BUDGET_CHARS_DENOMINATOR: u64 = 4;
pub const DEFAULT_LOCAL_CONTEXT_TOKENS: u64 = 4_096;

/// providers.json `maxOutputTokens`: the reply length asked for, by the placement of the model.
/// Cloud gets more because OpenAI's reasoning models spend hidden reasoning tokens from the cap;
/// 4,096 for local and network is what the Mac's `LocalChat` already sends.
pub const MAX_OUTPUT_TOKENS_CLOUD: u32 = 16_000;
pub const MAX_OUTPUT_TOKENS_NETWORK: u32 = 4_096;
pub const MAX_OUTPUT_TOKENS_LOCAL: u32 = 4_096;

/// Environment variable that points the cloud providers at a test server.
/// Debug builds only: release builds don't even contain the name.
#[cfg(debug_assertions)]
pub const BASE_URL_OVERRIDE_VAR: &str = "NM_AI_BASE_URL_OVERRIDE";

pub fn get(id: &str) -> Option<&'static ProviderDef> {
    PROVIDERS.iter().find(|p| p.id == id)
}

pub fn is_cloud(id: &str) -> bool {
    CLOUD_ORDER.contains(&id)
}

/// The name used in "… is busy" and "… will read this": the product for Claude,
/// the company otherwise.
pub fn brand(id: &str) -> &'static str {
    match id {
        "anthropic" => "Claude",
        other => get(other).map(|p| p.name).unwrap_or("The server"),
    }
}

/// Where "Open billing page" goes.
pub fn billing_url(id: &str) -> Option<&'static str> {
    match id {
        "anthropic" => Some("https://console.anthropic.com/settings/billing"),
        "openai" => Some("https://platform.openai.com/settings/organization/billing/overview"),
        "google" => Some("https://aistudio.google.com/"),
        _ => None,
    }
}

/// The debug-only redirect of the cloud providers. Always `None` in release builds.
pub fn debug_override() -> Option<String> {
    #[cfg(debug_assertions)]
    {
        std::env::var(BASE_URL_OVERRIDE_VAR).ok().filter(|v| !v.trim().is_empty())
    }
    #[cfg(not(debug_assertions))]
    {
        None
    }
}

/// A cloud provider's base URL, or the override's root when one is given. Google's
/// paths are relative to an OpenAI-style root, so its override gains `/v1`.
pub fn base_url(id: &str, override_root: Option<&str>) -> Option<String> {
    let def = get(id)?;
    if let (Some(root), CatalogPlacement::Cloud) = (override_root, def.placement) {
        let root = root.trim_end_matches('/');
        return Some(if id == "google" { format!("{root}/v1") } else { root.to_string() });
    }
    def.base_url.map(str::to_string)
}

/// 127.0.0.1, ::1 and localhost are this computer; anything else is the network.
pub fn is_local_host(host: &str) -> bool {
    let host = host.trim_start_matches('[').trim_end_matches(']').to_ascii_lowercase();
    host == "127.0.0.1" || host == "::1" || host == "localhost"
}

/// Keeps chat models only (spec §2: embedding models are filtered out).
pub fn filter_models(provider: &str, models: Vec<ModelInfo>) -> Vec<ModelInfo> {
    models
        .into_iter()
        .filter(|m| {
            let id = m.id.to_ascii_lowercase();
            match provider {
                "anthropic" => true,
                "openai" => {
                    OPENAI_INCLUDE_PREFIXES.iter().any(|p| id.starts_with(p))
                        && !OPENAI_EXCLUDE.iter().any(|x| id.contains(x))
                }
                "google" => !GOOGLE_EXCLUDE.iter().any(|x| id.contains(x)),
                _ => !LOCAL_EXCLUDE.iter().any(|x| id.contains(x)),
            }
        })
        .collect()
}

/// The model Auto uses when the user never picked one. Google's rule: the first id
/// containing "flash", else the first.
pub fn default_model(provider: &str, available: &[ModelInfo]) -> Option<String> {
    if let Some(m) = get(provider).and_then(|p| p.default_model) {
        return Some(m.to_string());
    }
    if provider == "google" {
        return available
            .iter()
            .find(|m| m.id.contains("flash"))
            .or_else(|| available.first())
            .map(|m| m.id.clone());
    }
    available.first().map(|m| m.id.clone())
}

/// providers.json `webSearch.anthropic`: `web_search_20260209` needs a recent Claude model, so a
/// model ID starting with one of these prefixes gets the legacy type instead.
pub const WEB_SEARCH_ANTHROPIC: &str = "web_search_20260209";
pub const WEB_SEARCH_ANTHROPIC_LEGACY: &str = "web_search_20250305";
pub const LEGACY_WEB_SEARCH_PREFIXES: &[&str] = &["claude-haiku-4", "claude-3"];

/// The contract's `anthropicWebSearchType(model)`.
pub fn anthropic_web_search_type(model: &str) -> &'static str {
    if LEGACY_WEB_SEARCH_PREFIXES.iter().any(|p| model.starts_with(p)) {
        WEB_SEARCH_ANTHROPIC_LEGACY
    } else {
        WEB_SEARCH_ANTHROPIC
    }
}

/// The hosted web-search tool a cloud provider's request carries, as providers.json
/// `webSearch` spells it (`web_search_tools_match_the_contract` compares them). Claude and
/// OpenAI search the web themselves; no other provider gets a tool.
pub fn web_search_tools(provider: &str, model: &str) -> Vec<Value> {
    match provider {
        "anthropic" => vec![json!({ "type": anthropic_web_search_type(model), "name": "web_search", "max_uses": 5 })],
        "openai" => vec![json!({ "type": "web_search" })],
        _ => Vec::new(),
    }
}

/// Cloud models all read images and PDFs; their lists carry no capability fields.
pub fn cloud_capabilities() -> Capabilities {
    Capabilities { tools: true, vision: true, json: true }
}

/// Anthropic and OpenAI take PDFs as-is; everyone else gets extracted text.
pub fn reads_pdf_natively(provider: &str) -> bool {
    provider == "anthropic" || provider == "openai"
}

pub fn placement_of(id: &str, host: Option<&str>) -> Placement {
    match get(id).map(|p| p.placement) {
        Some(CatalogPlacement::Cloud) => Placement::Cloud,
        Some(CatalogPlacement::Computed) => match host {
            Some(h) if !is_local_host(h) => Placement::Network,
            _ => Placement::Local,
        },
        _ => Placement::Local,
    }
}

/// `max_tokens` for a request to a model at this placement: providers.json `maxOutputTokens`.
pub fn max_output_tokens(placement: Placement) -> u32 {
    match placement {
        Placement::Cloud => MAX_OUTPUT_TOKENS_CLOUD,
        Placement::Network => MAX_OUTPUT_TOKENS_NETWORK,
        Placement::Local => MAX_OUTPUT_TOKENS_LOCAL,
    }
}

/// The id the one added server is stored under. The contract allows several (ids match
/// `^[a-z0-9-]{1,32}$`, one keychain item each); this app offers one.
pub const CUSTOM_SERVER_ID: &str = "default";

/// The keychain item a provider's key lives in. providers.json gives `custom` the prefix
/// `custom-server-key`, so the added server's item is `custom-server-key.<serverId>`.
pub fn keychain_name(id: &str) -> Option<String> {
    let key = get(id)?.keychain_key?;
    Some(if id == "custom" { format!("{key}.{CUSTOM_SERVER_ID}") } else { key.to_string() })
}
```

- [ ] **Step 6: Run the catalog and provider tests**

Run: `cargo test -p notchmeow -- ai::catalog:: ai::provider::`
Expected: `test result: ok. 12 passed; 0 failed`.
- `web_search_tools_match_the_contract` compares the web-search tools with providers.json `webSearch`: OpenAI `{"type": "web_search"}`, Anthropic `{"type": "web_search_20260209", "name": "web_search", "max_uses": 5}`, and the legacy type for older Claude models.
- `reply_length_follows_the_contract` compares `max_output_tokens` with providers.json `maxOutputTokens` for every placement, and `reply_length_is_16000_for_cloud_and_4096_for_local` pins the two values on purpose.
- `an_endpoint_never_prints_its_key` pins the hand-written `Debug`: a failed assertion or a `{:?}` can't leak a key.
- `the_added_servers_keychain_item_is_the_prefix_plus_its_id` pins `custom-server-key.default` for the added server and the plain `keychain_key` for the others.

- [ ] **Step 7: Allow the new keys, test first**

Append to `windows/src-tauri/src/secrets.rs`:

```rust

#[cfg(test)]
mod tests {
    use super::{clear, is_allowed, set, KNOWN_KEYS};

    /// Every keychain item the AI catalog names can be stored: the fixed keys as they are, the
    /// added server's under its id.
    #[test]
    fn every_ai_key_in_the_catalog_is_allowed() {
        for p in crate::ai::catalog::PROVIDERS {
            if let Some(name) = crate::ai::catalog::keychain_name(p.id) {
                assert!(is_allowed(&name), "{name} is missing from KNOWN_KEYS");
            }
        }
        assert!(KNOWN_KEYS.contains(&"openai-api-key"));
    }

    /// providers.json's `custom-server-key` is a prefix: `custom-server-key.<serverId>`, with
    /// `serverId` matching `^[a-z0-9-]{1,32}$`.
    #[test]
    fn an_added_servers_key_needs_a_valid_server_id() {
        for ok in ["custom-server-key.default", "custom-server-key.a", "custom-server-key.studio-2", "custom-server-key.0-9"] {
            assert!(is_allowed(ok), "{ok}");
        }
        assert!(is_allowed(&format!("custom-server-key.{}", "a".repeat(32))), "32 characters is the longest id");
        for bad in [
            "custom-server-key",
            "custom-server-key.",
            "custom-server-key.../x",
            "custom-server-key.Studio",
            "custom-server-key.st\u{fc}dio",
            "custom-server-key.\u{663}",
            "custom-server-key.a_b",
            "custom-server-key.a.b",
            "custom-server-key.default\n",
            "custom-server-key.default ",
            "custom-server-key-default",
            "Custom-server-key.default",
        ] {
            assert!(!is_allowed(bad), "{bad:?} must be refused");
        }
        assert!(!is_allowed(&format!("custom-server-key.{}", "a".repeat(33))), "33 characters is one too many");
    }

    /// A refused key never reaches the keychain.
    #[test]
    fn set_and_clear_refuse_a_key_that_is_not_allowed() {
        for bad in ["custom-server-key.", "custom-server-key.../x", "custom-server-key.UPPER", "custom-server-key", "not-a-key"] {
            assert!(set(bad, "secret").is_err(), "set {bad}");
            assert!(clear(bad).is_err(), "clear {bad}");
        }
    }
}
```

Run: `cargo test -p notchmeow secrets::`
Expected: FAIL to compile: ``cannot find function `is_allowed` in module `super` ``.

Then, in `KNOWN_KEYS`, add the three AI keys below `"anthropic-api-key",` (the added server's key is not listed: it is a prefix, handled next):

```rust
    "anthropic-api-key",
    "google-api-key",
    "openai-api-key",
```

Below `KNOWN_KEYS`, add:

```rust

/// The server added with Settings → AI → Add server… keeps its key (when it needs one) as
/// `custom-server-key.<serverId>`. The contract allows several added servers, one item each.
const CUSTOM_SERVER_KEY_PREFIX: &str = "custom-server-key.";

/// `^[a-z0-9-]{1,32}$`, checked by hand: no regex crate, and a trailing newline can't slip past a `$`.
fn is_server_id(id: &str) -> bool {
    (1..=32).contains(&id.len()) && id.bytes().all(|b| matches!(b, b'a'..=b'z' | b'0'..=b'9' | b'-'))
}

/// A fixed key, or the prefix with a valid server id. The bare prefix is not a key.
fn is_allowed(key: &str) -> bool {
    KNOWN_KEYS.contains(&key) || key.strip_prefix(CUSTOM_SERVER_KEY_PREFIX).is_some_and(is_server_id)
}
```

and make `entry` use it:

```rust
fn entry(key: &str) -> Option<Entry> {
    if !is_allowed(key) {
        return None;
    }
    Entry::new(SERVICE, key).ok()
}
```

Run: `cargo test -p notchmeow secrets::`
Expected: `test result: ok. 3 passed; 0 failed`

- [ ] **Step 8: Run the Rust tests on Windows CI, and on Linux when the fixtures change**

In `.github/workflows/windows.yml`, insert these steps after the `- name: Install dependencies` step, at the same indentation:

```yaml
      # The AI tests run the shared fixtures (tests/fixtures/ai) and the fake
      # model server, both in Python.
      - uses: actions/setup-python@v5
        with:
          python-version: '3.x'

      # tauri-build refuses to run until the relay it bundles exists, so the
      # relay is built first, exactly as on Linux. bash stops at the first failure.
      - name: Test
        shell: bash
        run: |
          cargo build --release -p notchmeow-hook
          cargo test --workspace
```

`windows.yml` only runs on `windows-v*` tags and by hand, and it has `contents: write` for publishing. So pull requests also get a separate, read-only Windows test workflow. Create `.github/workflows/windows-tests.yml`:

```yaml
name: Windows tests

# Runs the Rust tests (including the shared AI contract) on Windows for pull requests.
# Read-only on purpose: windows.yml builds and publishes; this one only tests.

on:
  pull_request:
    paths:
      - 'windows/**'
      - 'tests/fixtures/ai/**'
      - 'tests/fake_local_llm.py'
      - '.github/workflows/windows-tests.yml'
  workflow_dispatch:

permissions:
  contents: read

jobs:
  test:
    runs-on: windows-latest
    defaults:
      run:
        working-directory: windows
    steps:
      - uses: actions/checkout@v4
        with:
          persist-credentials: false
      - uses: actions/setup-node@v4
        with:
          node-version: '20'
      - uses: actions/setup-python@v5
        with:
          python-version: '3.x'
      - name: Install dependencies
        run: npm ci
      - name: Test
        shell: bash
        run: |
          cargo build --release -p notchmeow-hook
          cargo test --workspace
```

In `.github/workflows/linux.yml`, extend `on.pull_request.paths`:

```yaml
    paths:
      - 'windows/**'
      - '.github/workflows/linux.yml'
      - 'tests/fixtures/ai/**'
      - 'tests/fake_local_llm.py'
```

Run: `grep -n "setup-python\|cargo test --workspace" .github/workflows/windows.yml && grep -n "tests/fixtures/ai" .github/workflows/linux.yml`
Expected: three matching lines: `setup-python` and `cargo test --workspace` in `windows.yml`, and `tests/fixtures/ai/**` in `linux.yml`.

- [ ] **Step 9: Run the whole workspace**

Run: `cargo build --release -p notchmeow-hook && cargo test --workspace`
Expected: every `test result:` line says `ok`.

Run: `cargo build -p notchmeow 2>&1 | grep -A4 "^warning" | grep -c "src/ai/"`
Expected: `0`. No warning points into the new module.

- [ ] **Step 10: Commit**

```bash
git add windows/scripts/cargo-linux.sh windows/src-tauri/src/ai windows/src-tauri/src/lib.rs windows/src-tauri/src/secrets.rs .github/workflows/windows.yml .github/workflows/linux.yml .github/workflows/windows-tests.yml
git commit -m "feat(ai): AI module skeleton, provider catalog and CI tests on Windows

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Router and error wording

**Files:**
- Create: `windows/src-tauri/src/ai/router.rs`, `windows/src-tauri/src/ai/errors.rs`
- Modify: `windows/src-tauri/src/ai/mod.rs` (add `pub mod errors;` and `pub mod router;`)

**Interfaces:**
- **Consumes:** `catalog::{is_cloud, brand, billing_url}`; `provider::{ErrorKind, Placement, AiError}`; `router-cases.json`; `http-errors.json`.
- **Produces:**
  - **From `router.rs`:**
    - `ModelRef { provider, model }`;
    - `Choice::{Explicit(ModelRef), Auto(AutoWord)}`, which serializes as `"auto"` or `{provider, model}`, with `Default` = Auto and `is_auto()`;
    - `Ready { provider, model, placement }`;
    - `RouteInput { setting, preferred_cloud, keys, online, local_ready, last_used_local, apple_ready, failure }`;
    - `Outcome`;
    - `RouteResult { primary, outcome, answered_by, label, error_kind }`;
    - `route(&RouteInput) -> RouteResult`, `cloud_choice(&RouteInput) -> Option<String>`, `local_choice(&RouteInput) -> Option<Ready>`.
  - **From `errors.rs`:**
    - `BILLING_CODES`, `is_billing(&str) -> bool` (a billing code, or any code ending in `_spend_limit_exceeded`), `MISSING_KEY`, `DEFAULT_RETRY_SECONDS`;
    - `classify_http(status, Option<&Value>, &[(String,String)]) -> (ErrorKind, Option<u64>)`, which never panics on an odd body;
    - `stream_error_kind(&str) -> ErrorKind`: the one mapping for a mid-stream OpenAI `error.code` or Anthropic `error.type` (Task 4 calls it);
    - `classify_transport`, `from_transport`, `async from_response(reqwest::Response) -> AiError`;
    - `Action::{OpenSettings, OpenBilling{url}, OpenGuide, ChooseModel, Cancel}`, which serializes as `{"kind": …}`;
    - `Wording { text, action }`, `Who { provider, name }`;
    - `error_copy(kind, &Who, Option<&AiError>) -> Wording`;
    - `fallback_copy(primary, model)`, `model_family(model)`, `missing_model_copy`, `outdated_copy`, `waking_copy`;
    - the constants `TOO_LONG` and `CANT_SEE`;
    - the wording for an empty or cut-off reply and for files that can't be read: `RAN_OUT_OF_ROOM`, `EMPTY_REPLY`, `CUT_OFF`, `HEIC`, `SCANNED_PDF_LINUX`, `SCANNED_PDF_WINDOWS` and `scanned_pdf_copy()`.

- [ ] **Step 1: Write the router tests**

Create `windows/src-tauri/src/ai/router.rs` with only:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use crate::ai::testkit;
    use serde_json::Value;

    #[test]
    fn router_cases() {
        let data = testkit::load_json("router-cases.json");
        let cases = data["cases"].as_array().unwrap();
        assert_eq!(cases.len(), 30, "router-cases.json changed: update this count on purpose");
        for case in cases {
            let mut input = data["defaults"].clone();
            for (k, v) in case["input"].as_object().unwrap() {
                input[k] = v.clone();
            }
            let input: RouteInput = serde_json::from_value(input).unwrap();
            let got = serde_json::to_value(route(&input)).unwrap();
            assert_eq!(got, case["expect"], "case {}", case["name"]);
        }
    }

    #[test]
    fn choice_round_trips_as_the_contract_spells_it() {
        let auto: Choice = serde_json::from_value(Value::String("auto".into())).unwrap();
        assert!(auto.is_auto());
        assert_eq!(serde_json::to_value(&auto).unwrap(), "auto");
        let explicit: Choice = serde_json::from_str(r#"{"provider":"ollama","model":"qwen3.5:2b"}"#).unwrap();
        assert_eq!(explicit, Choice::Explicit(ModelRef { provider: "ollama".into(), model: "qwen3.5:2b".into() }));
        assert!(serde_json::from_value::<Choice>(Value::String("sometimes".into())).is_err());
    }

    #[test]
    fn local_choice_returns_the_model_too() {
        let input = RouteInput {
            setting: Choice::default(),
            preferred_cloud: "anthropic".into(),
            keys: vec![],
            online: true,
            local_ready: vec![
                Ready { provider: "ollama".into(), model: "qwen3.5:2b".into(), placement: Placement::Local },
                Ready { provider: "custom".into(), model: "llama3".into(), placement: Placement::Network },
            ],
            last_used_local: Some(ModelRef { provider: "custom".into(), model: "llama3".into() }),
            apple_ready: false,
            failure: None,
        };
        assert_eq!(local_choice(&input).unwrap().model, "llama3");
    }
}
```

Add `pub mod router;` to `ai/mod.rs`, below `pub mod provider;`.

- [ ] **Step 2: Run them to see them fail**

Run: `cargo test -p notchmeow ai::router::`
Expected: FAIL to compile, with `cannot find type 'RouteInput' in this scope` and similar errors.

- [ ] **Step 3: Write the router**

Put this above the tests in `router.rs`:

```rust
// Which model answers. A pure function of the inputs, identical to `route()` in
// tests/fixtures/ai/reference.py; `router_cases` runs every case in
// router-cases.json against it.

use serde::{Deserialize, Serialize};

use crate::ai::catalog;
use crate::ai::provider::{ErrorKind, Placement};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ModelRef {
    pub provider: String,
    pub model: String,
}

/// The JSON word `"auto"`.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum AutoWord {
    Auto,
}

/// A per-feature setting: `"auto"` or `{"provider": …, "model": …}`.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(untagged)]
pub enum Choice {
    Explicit(ModelRef),
    Auto(AutoWord),
}

impl Default for Choice {
    fn default() -> Self {
        Choice::Auto(AutoWord::Auto)
    }
}

impl Choice {
    pub fn is_auto(&self) -> bool {
        matches!(self, Choice::Auto(_))
    }
}

/// A local or network model that answered discovery, in discovery order.
#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct Ready {
    pub provider: String,
    pub model: String,
    pub placement: Placement,
}

#[derive(Debug, Clone, PartialEq, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RouteInput {
    pub setting: Choice,
    pub preferred_cloud: String,
    /// Cloud providers with a key.
    pub keys: Vec<String>,
    pub online: bool,
    pub local_ready: Vec<Ready>,
    pub last_used_local: Option<ModelRef>,
    pub apple_ready: bool,
    pub failure: Option<ErrorKind>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum Outcome {
    Ok,
    Fallback,
    Error,
    RetryCountdown,
    EmptyState,
    Interrupted,
    Cancelled,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct RouteResult {
    pub primary: Option<String>,
    pub outcome: Outcome,
    pub answered_by: Option<String>,
    pub label: Option<Placement>,
    pub error_kind: Option<ErrorKind>,
}

/// The Preferred cloud, then the other of Claude/OpenAI, then Google — the first with a key.
pub fn cloud_choice(input: &RouteInput) -> Option<String> {
    let preferred = input.preferred_cloud.as_str();
    let mut order = vec![preferred];
    order.extend(["anthropic", "openai"].into_iter().filter(|p| *p != preferred));
    order.push("google");
    order.into_iter().find(|p| input.keys.iter().any(|k| k == p)).map(str::to_string)
}

/// The last-used local model if it is still ready, else the first ready one, else Apple.
pub fn local_choice(input: &RouteInput) -> Option<Ready> {
    if let Some(last) = &input.last_used_local {
        if let Some(r) = input
            .local_ready
            .iter()
            .find(|r| r.provider == last.provider && r.model == last.model)
        {
            return Some(r.clone());
        }
    }
    if let Some(first) = input.local_ready.first() {
        return Some(first.clone());
    }
    if input.apple_ready {
        return Some(Ready { provider: "apple".into(), model: "system".into(), placement: Placement::Local });
    }
    None
}

fn placement(input: &RouteInput, provider: &str) -> Placement {
    if catalog::is_cloud(provider) {
        return Placement::Cloud;
    }
    if provider == "apple" {
        return Placement::Local;
    }
    input
        .local_ready
        .iter()
        .find(|r| r.provider == provider)
        .map(|r| r.placement)
        .unwrap_or(Placement::Local)
}

fn result(primary: &str, outcome: Outcome, answered_by: Option<&str>, label: Option<Placement>, kind: Option<ErrorKind>) -> RouteResult {
    RouteResult {
        primary: Some(primary.to_string()),
        outcome,
        answered_by: answered_by.map(str::to_string),
        label,
        error_kind: kind,
    }
}

pub fn route(input: &RouteInput) -> RouteResult {
    let auto = input.setting.is_auto();
    let (primary, local) = match &input.setting {
        Choice::Auto(_) => {
            let cloud = cloud_choice(input);
            let local = local_choice(input);
            match (cloud, &local) {
                (Some(c), _) if input.online || local.is_none() => (c, local),
                (_, Some(l)) => (l.provider.clone(), local.clone()),
                _ => {
                    return RouteResult {
                        primary: None,
                        outcome: Outcome::EmptyState,
                        answered_by: None,
                        label: None,
                        error_kind: None,
                    }
                }
            }
        }
        Choice::Explicit(m) => (m.provider.clone(), None),
    };

    let Some(failure) = input.failure else {
        return result(&primary, Outcome::Ok, Some(&primary), Some(placement(input, &primary)), None);
    };
    match failure {
        ErrorKind::Cancelled => result(&primary, Outcome::Cancelled, None, None, None),
        ErrorKind::Interrupted => result(
            &primary,
            Outcome::Interrupted,
            Some(&primary),
            Some(placement(input, &primary)),
            Some(ErrorKind::Interrupted),
        ),
        kind if kind.is_temporary() && auto && catalog::is_cloud(&primary) && local.is_some() => {
            let fallback = local.unwrap();
            result(&primary, Outcome::Fallback, Some(&fallback.provider), Some(fallback.placement), Some(kind))
        }
        kind @ (ErrorKind::RateLimited | ErrorKind::Overloaded) => {
            result(&primary, Outcome::RetryCountdown, None, None, Some(kind))
        }
        kind => result(&primary, Outcome::Error, None, None, Some(kind)),
    }
}
```

- [ ] **Step 4: Run the router tests**

Run: `cargo test -p notchmeow ai::router::`
Expected: `test result: ok. 3 passed; 0 failed`. `router_cases` runs all 30 cases in `router-cases.json`.

- [ ] **Step 5: Write the error tests**

Create `windows/src-tauri/src/ai/errors.rs` with only:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use crate::ai::testkit;

    #[test]
    fn http_error_cases() {
        let data = testkit::load_json("http-errors.json");
        let cases = data["cases"].as_array().unwrap();
        assert_eq!(cases.len(), 21, "http-errors.json changed: update this count on purpose");
        for case in cases {
            let status = case["status"].as_u64().unwrap() as u16;
            let headers: Vec<(String, String)> = case["headers"]
                .as_object()
                .unwrap()
                .iter()
                .map(|(k, v)| (k.clone(), v.as_str().unwrap().to_string()))
                .collect();
            let body = if case["body"].is_null() { None } else { Some(&case["body"]) };
            let (kind, retry) = classify_http(status, body, &headers);
            assert_eq!(serde_json::to_value(kind).unwrap(), case["kind"], "{status} {}", case["body"]);
            assert_eq!(retry, case["retryAfter"].as_u64(), "{status} retryAfter");
        }
    }

    #[test]
    fn odd_error_bodies_never_panic() {
        use serde_json::json;
        // A string, a list, a list of non-objects, a list in a list, null, a number, an empty list,
        // wrong-typed fields: each counts as "no marker", and the status decides.
        for (status, body, want) in [
            (500, json!({"error": "boom"}), ErrorKind::Server),
            (400, json!([{"error": {"code": 400, "message": "bad"}}]), ErrorKind::BadRequest),
            (429, json!({"error": ["x"]}), ErrorKind::RateLimited),
            (429, json!({"error": [[{"code": "insufficient_quota"}]]}), ErrorKind::RateLimited),
            (503, json!({"error": null}), ErrorKind::Overloaded),
            (401, json!({"error": 7}), ErrorKind::Auth),
            (404, json!({"error": []}), ErrorKind::BadRequest),
            (500, json!("just text"), ErrorKind::Server),
            (500, json!([]), ErrorKind::Server),
            (429, json!({"error": {"code": 5, "type": ["x"], "message": 9}}), ErrorKind::RateLimited),
        ] {
            assert_eq!(classify_http(status, Some(&body), &[]).0, want, "{status} {body}");
        }
        // A list still carries its marker, whether it wraps the whole body (Google) or only the `error` field,
        // and a string error has no message to show.
        let google = json!([{"error": {"code": "insufficient_quota"}}]);
        assert_eq!(classify_http(429, Some(&google), &[]).0, ErrorKind::Billing);
        let wrapped = json!({"error": [{"type": "billing_error"}]});
        assert_eq!(classify_http(400, Some(&wrapped), &[]).0, ErrorKind::Billing);
        assert_eq!(error_field(Some(&json!({"error": "boom"})), "message"), None);
    }

    #[test]
    fn retry_after_is_ascii_digits_above_zero() {
        let retry = |v: &str| classify_http(429, None, &[("Retry-After".to_string(), v.to_string())]).1;
        assert_eq!(retry("30"), Some(30));
        assert_eq!(retry(" 7 "), Some(7));
        assert_eq!(retry("007"), Some(7));
        // `parse` alone would take "+5"; "0" means "use the default"; "\u{b2}" and "\u{663}" are digits to Unicode, not to HTTP.
        for bad in ["0", "00", "", "+5", "-1", "1.5", "5 s", "\u{b2}", "\u{663}", "Wed, 21 Oct 2026 07:28:00 GMT"] {
            assert_eq!(retry(bad), None, "{bad:?}");
        }
        assert_eq!(classify_http(429, None, &[]).1, None);
    }

    #[test]
    fn stream_errors_map_like_the_reference_table() {
        use ErrorKind::*;
        for (code, want) in [
            ("rate_limit_exceeded", RateLimited), ("rate_limit_error", RateLimited),
            ("server_is_overloaded", Overloaded), ("slow_down", Overloaded), ("overloaded_error", Overloaded),
            ("server_error", Server), ("api_error", Server), ("timeout_error", Server), ("vector_store_timeout", Server),
            ("insufficient_quota", Billing), ("credit_balance_exhausted", Billing),
            ("organization_usage_limit_exceeded", Billing), ("billing_error", Billing),
            ("project_spend_limit_exceeded", Billing), ("user_spend_limit_exceeded", Billing),
            ("invalid_prompt", Refusal), ("image_content_policy_violation", Refusal),
            ("content_policy_violation", Refusal), ("content_filter", Refusal),
            ("authentication_error", Auth), ("invalid_api_key", Auth), ("permission_error", Auth),
            ("invalid_request_error", BadRequest), ("context_length_exceeded", BadRequest),
            ("something_new", BadRequest), ("", BadRequest),
        ] {
            assert_eq!(stream_error_kind(code), want, "{code:?}");
        }
        // Only a temporary kind may fall back to a local model, and an unknown code never is one.
        for code in ["something_new", "invalid_prompt", "invalid_api_key", "insufficient_quota", "context_length_exceeded"] {
            assert!(!stream_error_kind(code).is_temporary(), "{code}");
        }
    }

    fn who(provider: &str, name: &str) -> Who {
        Who { provider: provider.into(), name: name.into() }
    }

    fn err_with(code: Option<&str>, retry: Option<u64>) -> AiError {
        AiError { code: code.map(str::to_string), retry_after: retry, ..AiError::new(ErrorKind::Billing) }
    }

    #[test]
    fn copy_matches_the_spec_table() {
        let anthropic = who("anthropic", "Anthropic");
        let openai = who("openai", "OpenAI");
        let lmstudio = who("lmstudio", "LM Studio");
        assert_eq!(
            error_copy(ErrorKind::Auth, &anthropic, None),
            Wording { text: "Your Anthropic key was rejected.".into(), action: Some(Action::OpenSettings) }
        );
        assert_eq!(error_copy(ErrorKind::Billing, &openai, Some(&err_with(Some("insufficient_quota"), None))).text, "Your OpenAI credit ran out.");
        assert_eq!(
            error_copy(ErrorKind::Billing, &openai, Some(&err_with(Some("project_spend_limit_exceeded"), None))).text,
            "Your OpenAI spend limit was reached."
        );
        assert!(matches!(
            error_copy(ErrorKind::Billing, &openai, None).action,
            Some(Action::OpenBilling { .. })
        ));
        assert_eq!(
            error_copy(ErrorKind::RateLimited, &anthropic, Some(&err_with(None, Some(20)))),
            Wording { text: "Claude is busy. Trying again in 20 s.".into(), action: Some(Action::Cancel) }
        );
        assert_eq!(error_copy(ErrorKind::Overloaded, &anthropic, None).text, "Claude is busy. Trying again in 20 s.");
        assert_eq!(
            error_copy(ErrorKind::Unreachable, &lmstudio, None),
            Wording { text: "Couldn't reach LM Studio. Is its server on?".into(), action: Some(Action::OpenGuide) }
        );
        assert_eq!(fallback_copy("anthropic", "qwen3.5:2b"), "Claude's busy right now, so Qwen answered instead.");
        assert_eq!(outdated_copy("Ollama").text, "Update Ollama to use it here.");
        let missing = AiError { code: Some(MISSING_KEY.into()), ..AiError::new(ErrorKind::Auth) };
        assert_eq!(error_copy(ErrorKind::Auth, &anthropic, Some(&missing)).text, "Your Anthropic key is missing.");
        assert_eq!(missing_model_copy("qwen3.5:2b", "Ollama").text, "qwen3.5:2b isn't on Ollama any more.");
        let bad = AiError { detail: Some("image exceeds 5 MB maximum".into()), ..AiError::new(ErrorKind::BadRequest) };
        assert_eq!(error_copy(ErrorKind::BadRequest, &anthropic, Some(&bad)).text, "Claude: image exceeds 5 MB maximum");
        assert_eq!(waking_copy("qwen3.5:2b"), "Waking up qwen3.5…");
        assert_eq!(TOO_LONG, "This chat got long, so I dropped the oldest messages.");
        assert_eq!(CANT_SEE, "This model can't see images. Pick one that can.");
    }

    #[test]
    fn empty_reply_and_file_copy() {
        assert_eq!(
            RAN_OUT_OF_ROOM,
            "The model ran out of room before answering. Try again, or pick a model without thinking mode."
        );
        assert_eq!(CUT_OFF, "The answer was cut off.");
        assert_eq!(HEIC, "HEIC photos aren't supported yet. Export it as JPEG or PNG.");
        assert_eq!(SCANNED_PDF_LINUX, "I can't read scanned PDFs on Linux yet. Try Claude or OpenAI, or paste the text.");
        assert!(scanned_pdf_copy().starts_with("I can't read"));
    }

    #[test]
    fn model_family_names() {
        assert_eq!(model_family("qwen3.5:2b"), "Qwen");
        assert_eq!(model_family("gemma-4-e2b"), "Gemma");
        assert_eq!(model_family("llama3"), "Llama");
        assert_eq!(model_family("3b-chat"), "3b-chat");
    }

    #[test]
    fn actions_serialize_for_the_island() {
        assert_eq!(serde_json::to_value(Action::OpenSettings).unwrap(), serde_json::json!({"kind": "openSettings"}));
        assert_eq!(
            serde_json::to_value(Action::OpenBilling { url: "https://x".into() }).unwrap(),
            serde_json::json!({"kind": "openBilling", "url": "https://x"})
        );
    }
}
```

Add `pub mod errors;` to `ai/mod.rs`, below `pub mod catalog;`.

Run: `cargo test -p notchmeow ai::errors::`
Expected: FAIL to compile, with `cannot find function 'classify_http' in this scope` and similar errors.

- [ ] **Step 6: Write the classification and the wording**

Put this above the tests in `errors.rs`:

```rust
// HTTP and transport failures → the contract's error kinds, and the words the
// chat shows for each (spec §5). `classify_http` is `classify_http()` from
// tests/fixtures/ai/reference.py; `http_error_cases` runs http-errors.json.

use serde::Serialize;
use serde_json::{Map, Value};

use crate::ai::catalog;
use crate::ai::provider::{AiError, ErrorKind};

/// The codes (and error types) that mean money, for HTTP errors and mid-stream errors alike.
/// A code that ends in `_spend_limit_exceeded` is billing too: see `is_billing`.
pub const BILLING_CODES: [&str; 4] = [
    "insufficient_quota",
    "credit_balance_exhausted",
    "organization_usage_limit_exceeded",
    "billing_error",
];

/// `reference.py`'s `_is_billing`: the one list `classify_http` and `stream_error_kind` share.
pub fn is_billing(code: &str) -> bool {
    BILLING_CODES.contains(&code) || code.ends_with("_spend_limit_exceeded")
}

/// `AiError::code` when a chosen cloud provider has no key at all.
pub const MISSING_KEY: &str = "missing_key";

/// Seconds Auto waits before retrying a busy cloud when `Retry-After` says nothing.
pub const DEFAULT_RETRY_SECONDS: u64 = 20;

fn header<'a>(headers: &'a [(String, String)], name: &str) -> Option<&'a str> {
    headers.iter().find(|(k, _)| k.eq_ignore_ascii_case(name)).map(|(_, v)| v.as_str())
}

/// An object, or the first element of a list when that is one (Google's OpenAI-compatible endpoint
/// wraps its errors in a list): `reference.py`'s `_first_dict`. Anything else is none.
fn first_object(v: Option<&Value>) -> Option<&Map<String, Value>> {
    match v? {
        Value::Object(map) => Some(map),
        Value::Array(list) => list.first()?.as_object(),
        _ => None,
    }
}

/// The body's `error` object. `{"error":"model not found"}` (LM Studio, Ollama), null, a number
/// or an empty list have none, and nothing here can panic.
fn error_object(body: Option<&Value>) -> Option<&Map<String, Value>> {
    first_object(first_object(body)?.get("error"))
}

fn error_field<'a>(body: Option<&'a Value>, field: &str) -> Option<&'a str> {
    error_object(body)?.get(field)?.as_str()
}

/// Rules, in order: a billing marker wins (status 402; an error `code` or `type` that `is_billing`;
/// "credit balance" in the message); 401/403 auth; 400/404/413/422 bad request; 429 rate limited;
/// 503/529 overloaded; other 5xx server; else bad request. `Retry-After` counts only as ASCII
/// digits above 0.
pub fn classify_http(status: u16, body: Option<&Value>, headers: &[(String, String)]) -> (ErrorKind, Option<u64>) {
    // Not `parse` alone: it takes "+5". Not `char::is_numeric`: "\u{b2}" is a digit to Unicode, not to HTTP.
    let retry = header(headers, "retry-after")
        .map(str::trim)
        .filter(|v| !v.is_empty() && v.bytes().all(|b| b.is_ascii_digit()))
        .and_then(|v| v.parse::<u64>().ok())
        .filter(|seconds| *seconds > 0);
    let text = |field: &str| error_field(body, field);
    let billing = text("code").is_some_and(is_billing)
        || text("type").is_some_and(is_billing)
        || status == 402
        || text("message").is_some_and(|m| m.to_lowercase().contains("credit balance"));
    let kind = if billing {
        ErrorKind::Billing
    } else {
        match status {
            401 | 403 => ErrorKind::Auth,
            400 | 404 | 413 | 422 => ErrorKind::BadRequest,
            429 => ErrorKind::RateLimited,
            503 | 529 => ErrorKind::Overloaded,
            500..=599 => ErrorKind::Server,
            _ => ErrorKind::BadRequest,
        }
    };
    (kind, retry)
}

/// The kind of a mid-stream error: an OpenAI `error.code` (Responses `response.failed` and `error`
/// events) or an Anthropic `error.type`; `reference.py`'s `stream_error_kind`. An unknown code is
/// `BadRequest`, never `Server`: `Server` is temporary, so Auto would hand a policy refusal or a
/// rejected key to a local model.
pub fn stream_error_kind(code: &str) -> ErrorKind {
    if is_billing(code) {
        return ErrorKind::Billing;
    }
    match code {
        "rate_limit_exceeded" | "rate_limit_error" => ErrorKind::RateLimited,
        "server_is_overloaded" | "slow_down" | "overloaded_error" => ErrorKind::Overloaded,
        "server_error" | "api_error" | "timeout_error" | "vector_store_timeout" => ErrorKind::Server,
        "invalid_prompt" | "image_content_policy_violation" | "content_policy_violation" | "content_filter" => {
            ErrorKind::Refusal
        }
        "authentication_error" | "invalid_api_key" | "permission_error" => ErrorKind::Auth,
        _ => ErrorKind::BadRequest,
    }
}

/// Connection refused and DNS failures are `unreachable`; slow connects are `timeout`.
pub fn classify_transport(err: &reqwest::Error) -> ErrorKind {
    if err.is_timeout() {
        ErrorKind::Timeout
    } else {
        ErrorKind::Unreachable
    }
}

pub fn from_transport(err: &reqwest::Error) -> AiError {
    AiError::new(classify_transport(err))
}

/// Reads a failed response into an `AiError`. Keeps the provider's own short
/// message (shown for bad requests) but never the request body.
pub async fn from_response(response: reqwest::Response) -> AiError {
    let status = response.status().as_u16();
    let headers: Vec<(String, String)> = response
        .headers()
        .iter()
        .filter_map(|(k, v)| v.to_str().ok().map(|v| (k.as_str().to_string(), v.to_string())))
        .collect();
    let request_id = header(&headers, "x-request-id").or_else(|| header(&headers, "request-id")).map(str::to_string);
    let body: Option<Value> = response.text().await.ok().and_then(|t| serde_json::from_str(&t).ok());
    let (kind, retry_after) = classify_http(status, body.as_ref(), &headers);
    AiError {
        kind,
        status: Some(status),
        retry_after,
        request_id,
        detail: error_field(body.as_ref(), "message").map(|m| m.chars().take(200).collect()),
        code: error_field(body.as_ref(), "code").map(str::to_string),
    }
}

/// What a button under an error does.
#[derive(Debug, Clone, PartialEq, Eq, Serialize)]
#[serde(tag = "kind", rename_all = "camelCase", rename_all_fields = "camelCase")]
pub enum Action {
    OpenSettings,
    OpenBilling { url: String },
    OpenGuide,
    ChooseModel,
    Cancel,
}

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Wording {
    pub text: String,
    pub action: Option<Action>,
}

fn wording(text: String, action: Option<Action>) -> Wording {
    Wording { text, action }
}

/// Who a provider is, in the words the messages use.
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Who {
    /// Catalog id.
    pub provider: String,
    /// "Ollama", "LM Studio", "Local server (OpenAI-compatible)", "Anthropic"…
    pub name: String,
}

/// The chat's message for a failure that nothing could answer instead (spec §5's table,
/// plus the cases it leaves out, worded the same way).
pub fn error_copy(kind: ErrorKind, who: &Who, err: Option<&AiError>) -> Wording {
    let cloud = catalog::is_cloud(&who.provider);
    let brand = if cloud { catalog::brand(&who.provider).to_string() } else { who.name.clone() };
    match kind {
        ErrorKind::Auth => {
            let owner = if cloud { who.name.clone() } else { "server".to_string() };
            let missing = err.and_then(|e| e.code.as_deref()) == Some(MISSING_KEY);
            let text = if missing { format!("Your {owner} key is missing.") } else { format!("Your {owner} key was rejected.") };
            wording(text, Some(Action::OpenSettings))
        }
        ErrorKind::Billing => {
            let spend = err
                .and_then(|e| e.code.as_deref())
                .is_some_and(|c| c.ends_with("_spend_limit_exceeded") || c == "organization_usage_limit_exceeded");
            let text = if spend {
                format!("Your {} spend limit was reached.", who.name)
            } else {
                format!("Your {} credit ran out.", who.name)
            };
            let action = catalog::billing_url(&who.provider).map(|u| Action::OpenBilling { url: u.to_string() });
            wording(text, action)
        }
        ErrorKind::RateLimited | ErrorKind::Overloaded => {
            let secs = err.and_then(|e| e.retry_after).unwrap_or(DEFAULT_RETRY_SECONDS);
            wording(format!("{brand} is busy. Trying again in {secs} s."), Some(Action::Cancel))
        }
        ErrorKind::Offline | ErrorKind::Unreachable if !cloud => {
            wording(format!("Couldn't reach {brand}. Is its server on?"), Some(Action::OpenGuide))
        }
        ErrorKind::Offline | ErrorKind::Unreachable => {
            wording(format!("Couldn't reach {brand}. Check your connection."), None)
        }
        ErrorKind::Timeout => wording(format!("{brand} took too long to answer."), None),
        ErrorKind::Server => wording(format!("{brand} had a problem. Try again in a moment."), None),
        ErrorKind::BadRequest => {
            let detail = err.and_then(|e| e.detail.clone()).unwrap_or_else(|| "it couldn't handle this request.".into());
            wording(format!("{brand}: {detail}"), None)
        }
        ErrorKind::Refusal => wording(format!("{brand} declined this one."), None),
        ErrorKind::Cancelled | ErrorKind::Interrupted => wording(String::new(), None),
    }
}

/// "Claude's busy right now, so Qwen answered instead."
pub fn fallback_copy(primary: &str, fallback_model: &str) -> String {
    format!("{}'s busy right now, so {} answered instead.", catalog::brand(primary), model_family(fallback_model))
}

/// "qwen3.5:2b" → "Qwen", "gemma-4-e2b" → "Gemma"; the whole id when it starts with no letters.
pub fn model_family(model: &str) -> String {
    let letters: String = model.chars().take_while(|c| c.is_ascii_alphabetic()).collect();
    let mut chars = letters.chars();
    match chars.next() {
        Some(first) => first.to_ascii_uppercase().to_string() + chars.as_str(),
        None => model.to_string(),
    }
}

pub const TOO_LONG: &str = "This chat got long, so I dropped the oldest messages.";
pub const CANT_SEE: &str = "This model can't see images. Pick one that can.";

/// The reply came back empty because the model spent every token thinking.
pub const RAN_OUT_OF_ROOM: &str = "The model ran out of room before answering. Try again, or pick a model without thinking mode.";
/// The reply came back empty for any other reason.
pub const EMPTY_REPLY: &str = "The model sent an empty reply. Try again.";
/// The reply stopped at the token limit but has text worth keeping.
pub const CUT_OFF: &str = "The answer was cut off.";

/// Anthropic and OpenAI reject `image/heic`, and local servers can't decode it.
pub const HEIC: &str = "HEIC photos aren't supported yet. Export it as JPEG or PNG.";
pub const SCANNED_PDF_LINUX: &str = "I can't read scanned PDFs on Linux yet. Try Claude or OpenAI, or paste the text.";
pub const SCANNED_PDF_WINDOWS: &str = "I can't read this scanned PDF. Try Claude or OpenAI, or paste the text.";

/// A scanned PDF no model here can be shown: Linux has no PDF renderer and no OCR, and
/// Windows can lack an OCR language. It is not "this model can't see images".
pub fn scanned_pdf_copy() -> &'static str {
    if cfg!(windows) {
        SCANNED_PDF_WINDOWS
    } else {
        SCANNED_PDF_LINUX
    }
}

/// A model the user chose that its server no longer has.
pub fn missing_model_copy(model: &str, server: &str) -> Wording {
    wording(format!("{model} isn't on {server} any more."), Some(Action::ChooseModel))
}

pub fn outdated_copy(name: &str) -> Wording {
    wording(format!("Update {name} to use it here."), Some(Action::OpenGuide))
}

pub fn waking_copy(model: &str) -> String {
    let short = model.split(':').next().unwrap_or(model);
    format!("Waking up {short}…")
}
```

- [ ] **Step 7: Run the error tests**

Run: `cargo test -p notchmeow ai::errors::`
Expected: `test result: ok. 8 passed; 0 failed`.
- `http_error_cases` runs all 21 cases in `http-errors.json`, 402 and the `*_spend_limit_exceeded` suffix included.
- `odd_error_bodies_never_panic` covers what the shared cases can't hold in one table: an `error` that is a string, null, a number, an empty list or a list in a list.
- `retry_after_is_ascii_digits_above_zero` pins `^[0-9]+$` and "greater than 0": `+5`, `0`, `²` and a date are all none.
- `stream_errors_map_like_the_reference_table` runs every row of the stream-error table, and an unknown code is `bad_request`, never temporary.
- `empty_reply_and_file_copy` pins the wording for empty replies, HEIC photos and scanned PDFs.

- [ ] **Step 8: Commit**

```bash
git add windows/src-tauri/src/ai
git commit -m "feat(ai): router and HTTP error classification from the shared cases

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: SSE decoding and the three stream formats

**Files:**
- Create: `windows/src-tauri/src/ai/sse.rs`
- Modify: `windows/src-tauri/src/ai/mod.rs` (add `pub mod sse;`)

**Interfaces:**
- **Consumes:** `errors::{from_transport, from_response, stream_error_kind}`; `provider::{Aggregate, ChatChunk, Citation, ErrorKind, Finish, ToolCall, AiError}`; `tests/fixtures/ai/sse/**`.
- **Produces:**
  - `Format::{OpenAIChat, OpenAIResponses, Anthropic}`;
  - `SseDecoder::{new, feed(&[u8]) -> Vec<String>, finish}`;
  - `strip_think`, `ThinkFilter::push`;
  - `Aggregator::{new(Format), push(&str) -> Vec<ChatChunk>, is_terminal, finish() -> Aggregate}`;
  - `async stream_request(reqwest::RequestBuilder, Format, first_token: Duration, idle: Duration, sink: &mut (dyn FnMut(ChatChunk) + Send)) -> Result<Aggregate, AiError>`.

  `stream_request` returns `Err` when nothing arrived (an HTTP error, a failed connection, or no bytes before `first_token`), and `Ok` with `Aggregate::error` set when the stream broke later.

- [ ] **Step 1: Write the tests**

Create `windows/src-tauri/src/ai/sse.rs` with only:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use crate::ai::testkit;

    const FORMATS: [Format; 3] = [Format::OpenAIChat, Format::OpenAIResponses, Format::Anthropic];

    fn fixtures(format: Format) -> Vec<(String, String, Aggregate)> {
        let dir = testkit::fixtures_dir().join("sse").join(format.dir());
        let mut out = Vec::new();
        for entry in std::fs::read_dir(&dir).unwrap() {
            let path = entry.unwrap().path();
            if path.extension().and_then(|e| e.to_str()) != Some("txt") {
                continue;
            }
            let expected = path.with_extension("expected.json");
            let want: Aggregate = serde_json::from_str(&std::fs::read_to_string(&expected).unwrap()).unwrap();
            let name = path.file_name().unwrap().to_string_lossy().to_string();
            out.push((name, std::fs::read_to_string(&path).unwrap(), want));
        }
        out.sort_by(|a, b| a.0.cmp(&b.0));
        out
    }

    #[test]
    fn sse_fixtures() {
        let mut seen = Vec::new();
        for format in FORMATS {
            for (name, text, want) in fixtures(format) {
                assert_eq!(aggregate(format, &text), want, "{}/{name}", format.dir());
                seen.push(format!("{}/{name}", format.dir()));
            }
        }
        // Every recorded stream runs; these are the ones the spec requires.
        for required in [
            "openai-chat/text-think.txt", "openai-chat/tool-call.txt", "openai-chat/keepalive-cut.txt",
            "openai-chat/content-filter.txt", "openai-chat/crlf.txt", "openai-chat/unicode-separators.txt",
            "openai-responses/text-citations.txt", "openai-responses/tool-call.txt",
            "openai-responses/refusal.txt", "openai-responses/incomplete.txt",
            "openai-responses/failed.txt", "openai-responses/failed-policy.txt",
            "openai-responses/failed-billing.txt", "openai-responses/failed-unknown.txt",
            "openai-responses/error-event.txt", "openai-responses/cut.txt",
            "anthropic/text-websearch.txt", "anthropic/tool-use.txt", "anthropic/refusal.txt",
            "anthropic/error-overloaded.txt", "anthropic/cut.txt",
        ] {
            assert!(seen.iter().any(|s| s == required), "missing fixture {required}");
        }
        assert_eq!(seen.len(), 21, "the SSE fixtures changed: update this count on purpose");
    }

    #[test]
    fn sse_fixtures_byte_by_byte() {
        // The network can split anywhere, even inside a UTF-8 character.
        for format in FORMATS {
            for (name, text, want) in fixtures(format) {
                let mut dec = SseDecoder::new();
                let mut agg = Aggregator::new(format);
                for b in text.as_bytes() {
                    for p in dec.feed(std::slice::from_ref(b)) {
                        agg.push(&p);
                    }
                }
                for p in dec.finish() {
                    agg.push(&p);
                }
                assert_eq!(agg.finish(), want, "{}/{name} split per byte", format.dir());
            }
        }
    }

    #[test]
    fn visible_text_hides_think_blocks_while_streaming() {
        let text = testkit::sse_fixture("openai-chat", "text-think.txt");
        let mut dec = SseDecoder::new();
        let mut agg = Aggregator::new(Format::OpenAIChat);
        let mut shown = String::new();
        for b in text.as_bytes().chunks(7) {
            for p in dec.feed(b) {
                for c in agg.push(&p) {
                    if let ChatChunk::Text(t) = c {
                        shown.push_str(&t);
                    }
                }
            }
        }
        assert_eq!(shown, "Hello from NotchMeow.");
    }

    #[test]
    fn think_filter_holds_split_tags() {
        let mut f = ThinkFilter::default();
        let mut out = String::new();
        for piece in ["Hi <thi", "nk>secret</th", "ink> there <", "b>"] {
            out.push_str(&f.push(piece));
        }
        assert_eq!(out, "Hi  there <b>");
    }

    #[test]
    fn strip_think_matches_the_reference_regex() {
        assert_eq!(strip_think("a<think>x</think>b<think>y</think>c"), "abc");
        assert_eq!(strip_think("a<think>open"), "a<think>open");
        assert_eq!(strip_think("<think>\nplan it\n</think>Hello"), "Hello");
    }

    #[test]
    fn response_failed_maps_its_code_like_an_error_event() {
        // The shared fixtures cover server_error, invalid_prompt, insufficient_quota and an unknown code;
        // the rest of `errors::stream_error_kind`'s table is checked here, through both events.
        let fold = |event: String| {
            let mut agg = Aggregator::new(Format::OpenAIResponses);
            agg.push(&event);
            agg.finish().error
        };
        let failed = |code: &str| format!(r#"{{"type":"response.failed","response":{{"status":"failed","error":{{"code":"{code}"}}}}}}"#);
        let error = |code: &str| format!(r#"{{"type":"error","code":"{code}","message":"x"}}"#);
        for (code, want) in [
            ("rate_limit_exceeded", ErrorKind::RateLimited),
            ("server_is_overloaded", ErrorKind::Overloaded),
            ("slow_down", ErrorKind::Overloaded),
            ("insufficient_quota", ErrorKind::Billing),
            ("credit_balance_exhausted", ErrorKind::Billing),
            ("project_spend_limit_exceeded", ErrorKind::Billing),
            ("organization_usage_limit_exceeded", ErrorKind::Billing),
            ("server_error", ErrorKind::Server),
            ("vector_store_timeout", ErrorKind::Server),
            ("invalid_prompt", ErrorKind::Refusal),
            ("content_policy_violation", ErrorKind::Refusal),
            ("invalid_api_key", ErrorKind::Auth),
            ("context_length_exceeded", ErrorKind::BadRequest),
            ("something_new", ErrorKind::BadRequest),
        ] {
            assert_eq!(fold(failed(code)), Some(want), "response.failed {code}");
            assert_eq!(fold(error(code)), Some(want), "error {code}");
        }
        // No error object at all is still a failure, never `interrupted`, and never a temporary one.
        assert_eq!(
            fold(r#"{"type":"response.failed","response":{"status":"failed"}}"#.into()),
            Some(ErrorKind::BadRequest)
        );
    }

    #[test]
    fn odd_stream_errors_never_panic_and_never_fall_back() {
        let fold = |format: Format, event: &str| {
            let mut agg = Aggregator::new(format);
            agg.push(event);
            agg.finish().error
        };
        // `error` as a string, null, a list or missing; `code` as null, a number or a list: an unknown code.
        for event in [
            r#"{"type":"response.failed","response":{"status":"failed","error":"boom"}}"#,
            r#"{"type":"response.failed","response":{"status":"failed","error":null}}"#,
            r#"{"type":"response.failed","response":{"status":"failed","error":["boom"]}}"#,
            r#"{"type":"response.failed","response":{"status":"failed","error":{"code":null}}}"#,
            r#"{"type":"response.failed","response":{"status":"failed","error":{"code":["x"]}}}"#,
            r#"{"type":"response.failed","response":"gone"}"#,
            r#"{"type":"response.failed"}"#,
            r#"{"type":"error","code":null}"#,
            r#"{"type":"error","code":42}"#,
            r#"{"type":"error","error":"boom"}"#,
            r#"{"type":"error"}"#,
        ] {
            let got = fold(Format::OpenAIResponses, event);
            assert_eq!(got, Some(ErrorKind::BadRequest), "{event}");
            assert!(!got.unwrap().is_temporary(), "{event} must not fall back");
        }
        for event in [
            r#"{"type":"error","error":"boom"}"#,
            r#"{"type":"error","error":null}"#,
            r#"{"type":"error","error":["overloaded_error"]}"#,
            r#"{"type":"error","error":{"type":null}}"#,
            r#"{"type":"error","error":{"type":7}}"#,
            r#"{"type":"error"}"#,
        ] {
            assert_eq!(fold(Format::Anthropic, event), Some(ErrorKind::BadRequest), "{event}");
        }
    }

    #[test]
    fn lines_end_at_newline_only() {
        // U+2028, U+0085, a vertical tab and a lone CR inside a data line don't split it; CRLF still ends one.
        let mut dec = SseDecoder::new();
        let got = dec.feed("data: {\"a\":\"x\u{2028}y\u{85}z\u{b}w\rv\"}\r\ndata: [DONE]\n".as_bytes());
        assert_eq!(got, vec!["{\"a\":\"x\u{2028}y\u{85}z\u{b}w\rv\"}".to_string(), "[DONE]".to_string()]);
    }

    #[test]
    fn non_json_and_comment_lines_are_skipped() {
        let mut dec = SseDecoder::new();
        let got = dec.feed(b": keep-alive\r\n\r\nevent: ping\ndata: {\"a\":1}\r\ndata: [DONE]\n");
        assert_eq!(got, vec!["{\"a\":1}".to_string(), "[DONE]".to_string()]);
    }
}
```

Add `pub mod sse;` to `ai/mod.rs`, below `pub mod router;`.

- [ ] **Step 2: Run them to see them fail**

Run: `cargo test -p notchmeow ai::sse::`
Expected: FAIL to compile, with `cannot find type 'Format' in this scope` and similar errors.

- [ ] **Step 3: Write the decoder, the aggregators and the stream pump**

Put this above the tests in `sse.rs`:

```rust
// Server-sent events: a byte-level line decoder, and one aggregator per wire
// format (OpenAI chat completions, OpenAI Responses, Anthropic Messages). Each
// aggregator reproduces `agg_*` in tests/fixtures/ai/reference.py exactly;
// `sse_fixtures` folds every recorded stream and compares with its
// `.expected.json`.

use std::collections::BTreeMap;
use std::time::Duration;

use serde_json::Value;

use crate::ai::errors::{self, stream_error_kind};
use crate::ai::provider::{AiError, Aggregate, ChatChunk, Citation, ErrorKind, Finish, ToolCall};

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Format {
    OpenAIChat,
    OpenAIResponses,
    Anthropic,
}

#[cfg(test)]
impl Format {
    /// The fixture folder under tests/fixtures/ai/sse/.
    pub fn dir(self) -> &'static str {
        match self {
            Format::OpenAIChat => "openai-chat",
            Format::OpenAIResponses => "openai-responses",
            Format::Anthropic => "anthropic",
        }
    }
}

/// Splits a byte stream into lines and returns each `data:` payload, trimmed.
/// Bytes are buffered until a newline, so a UTF-8 character or a line split across
/// two network chunks is never cut. Comments, `event:` lines and blanks are dropped.
#[derive(Default)]
pub struct SseDecoder {
    buf: Vec<u8>,
}

impl SseDecoder {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn feed(&mut self, bytes: &[u8]) -> Vec<String> {
        self.buf.extend_from_slice(bytes);
        let mut out = Vec::new();
        while let Some(i) = self.buf.iter().position(|b| *b == b'\n') {
            let line: Vec<u8> = self.buf.drain(..=i).collect();
            if let Some(p) = payload(&line[..line.len() - 1]) {
                out.push(p);
            }
        }
        out
    }

    /// The last line, when the stream ended without a newline.
    pub fn finish(&mut self) -> Vec<String> {
        let line = std::mem::take(&mut self.buf);
        payload(&line).into_iter().collect()
    }
}

fn payload(line: &[u8]) -> Option<String> {
    let line = line.strip_suffix(b"\r").unwrap_or(line);
    let rest = line.strip_prefix(b"data:")?;
    Some(String::from_utf8_lossy(rest).trim().to_string())
}

/// Removes complete `<think>…</think>` blocks, like the reference's non-greedy regex.
/// An unclosed `<think>` is left alone.
pub fn strip_think(text: &str) -> String {
    let mut out = text.to_string();
    let mut from = 0;
    while let Some(start) = out[from..].find("<think>").map(|i| i + from) {
        match out[start + 7..].find("</think>") {
            Some(end) => {
                out.replace_range(start..start + 7 + end + 8, "");
                from = start;
            }
            None => break,
        }
    }
    out
}

/// Hides `<think>` blocks from text as it streams, holding back a tag split
/// across two deltas until it is complete.
#[derive(Default)]
pub struct ThinkFilter {
    inside: bool,
    pending: String,
}

impl ThinkFilter {
    pub fn push(&mut self, delta: &str) -> String {
        self.pending.push_str(delta);
        let mut out = String::new();
        loop {
            let tag = if self.inside { "</think>" } else { "<think>" };
            if let Some(i) = self.pending.find(tag) {
                if !self.inside {
                    out.push_str(&self.pending[..i]);
                }
                self.pending.drain(..i + tag.len());
                self.inside = !self.inside;
                continue;
            }
            let keep = partial_tag(&self.pending, tag);
            let cut = self.pending.len() - keep;
            if !self.inside {
                out.push_str(&self.pending[..cut]);
            }
            self.pending.drain(..cut);
            return out;
        }
    }
}

/// How many trailing bytes of `s` could be the start of `tag` (tags are ASCII).
fn partial_tag(s: &str, tag: &str) -> usize {
    (1..tag.len()).rev().find(|n| s.ends_with(&tag[..*n])).unwrap_or(0)
}

#[derive(Default)]
struct Block {
    kind: String,
    id: String,
    name: String,
    args: String,
}

/// Folds one stream. `push` returns what the chat can show right away; `finish`
/// returns the whole result in the fixtures' shape.
pub struct Aggregator {
    format: Format,
    text: String,
    calls: Vec<(String, ToolCall)>,
    citations: Vec<Citation>,
    refusal: Option<String>,
    finish: Option<Finish>,
    error: Option<ErrorKind>,
    terminal: bool,
    blocks: BTreeMap<u64, Block>,
    think: ThinkFilter,
}

impl Aggregator {
    pub fn new(format: Format) -> Self {
        Aggregator {
            format,
            text: String::new(),
            calls: Vec::new(),
            citations: Vec::new(),
            refusal: None,
            finish: None,
            error: None,
            terminal: false,
            blocks: BTreeMap::new(),
            think: ThinkFilter::default(),
        }
    }

    /// True once the stream's terminal event arrived: stop reading.
    pub fn is_terminal(&self) -> bool {
        self.terminal
    }

    pub fn push(&mut self, payload: &str) -> Vec<ChatChunk> {
        if payload == "[DONE]" {
            if self.format == Format::OpenAIChat {
                self.terminal = true;
            }
            return Vec::new();
        }
        let Ok(ev) = serde_json::from_str::<Value>(payload) else { return Vec::new() };
        let (finish, error) = (self.finish, self.error);
        let mut out = match self.format {
            Format::OpenAIChat => self.push_chat(&ev),
            Format::OpenAIResponses => self.push_responses(&ev),
            Format::Anthropic => self.push_anthropic(&ev),
        };
        if let Some(f) = self.finish.filter(|f| Some(*f) != finish) {
            out.push(ChatChunk::Finish(f));
        }
        if let Some(e) = self.error.filter(|e| Some(*e) != error) {
            out.push(ChatChunk::Error(e));
        }
        out
    }

    fn text_delta(&mut self, delta: &str, out: &mut Vec<ChatChunk>) {
        self.text.push_str(delta);
        let visible = if self.format == Format::OpenAIChat { self.think.push(delta) } else { delta.to_string() };
        if !visible.is_empty() {
            out.push(ChatChunk::Text(visible));
        }
    }

    fn cite(&mut self, url: &str, title: &str, out: &mut Vec<ChatChunk>) {
        if self.citations.iter().any(|c| c.url == url) {
            return;
        }
        let c = Citation { url: url.to_string(), title: title.to_string() };
        out.push(ChatChunk::Citation { url: c.url.clone(), title: c.title.clone() });
        self.citations.push(c);
    }

    fn push_chat(&mut self, ev: &Value) -> Vec<ChatChunk> {
        let mut out = Vec::new();
        for ch in ev.get("choices").and_then(Value::as_array).into_iter().flatten() {
            let d = ch.get("delta").cloned().unwrap_or(Value::Null);
            if let Some(content) = d.get("content").and_then(Value::as_str) {
                self.text_delta(content, &mut out);
            }
            for tc in d.get("tool_calls").and_then(Value::as_array).into_iter().flatten() {
                let index = tc.get("index").and_then(Value::as_u64).unwrap_or(0);
                let key = index.to_string();
                let pos = match self.calls.iter().position(|(k, _)| *k == key) {
                    Some(p) => p,
                    None => {
                        self.calls.push((key, ToolCall { id: String::new(), name: String::new(), arguments: String::new() }));
                        self.calls.len() - 1
                    }
                };
                let slot = &mut self.calls[pos].1;
                if let Some(id) = tc.get("id").and_then(Value::as_str).filter(|s| !s.is_empty()) {
                    slot.id = id.to_string();
                }
                let f = tc.get("function").cloned().unwrap_or(Value::Null);
                if let Some(name) = f.get("name").and_then(Value::as_str).filter(|s| !s.is_empty()) {
                    slot.name = name.to_string();
                }
                let args = f.get("arguments").and_then(Value::as_str).unwrap_or("");
                slot.arguments.push_str(args);
                out.push(ChatChunk::ToolCall { index: pos, id: slot.id.clone(), name: slot.name.clone(), arguments: args.to_string() });
            }
            if let Some(reason) = ch.get("finish_reason").and_then(Value::as_str).filter(|s| !s.is_empty()) {
                self.finish = Some(match reason {
                    "content_filter" => Finish::Refusal,
                    "length" => Finish::Length,
                    "tool_calls" => Finish::ToolCalls,
                    _ => Finish::Stop,
                });
            }
        }
        out
    }

    fn push_responses(&mut self, ev: &Value) -> Vec<ChatChunk> {
        let mut out = Vec::new();
        let s = |v: &Value, k: &str| v.get(k).and_then(Value::as_str).unwrap_or("").to_string();
        match ev.get("type").and_then(Value::as_str).unwrap_or("") {
            "response.output_text.delta" => self.text_delta(&s(ev, "delta"), &mut out),
            "response.output_item.added" => {
                let item = ev.get("item").cloned().unwrap_or(Value::Null);
                if item.get("type").and_then(Value::as_str) == Some("function_call") {
                    let call = ToolCall { id: s(&item, "call_id"), name: s(&item, "name"), arguments: s(&item, "arguments") };
                    self.calls.push((s(&item, "id"), call));
                }
            }
            "response.function_call_arguments.delta" => {
                let key = s(ev, "item_id");
                if let Some(pos) = self.calls.iter().position(|(k, _)| *k == key) {
                    let delta = s(ev, "delta");
                    let call = &mut self.calls[pos].1;
                    call.arguments.push_str(&delta);
                    out.push(ChatChunk::ToolCall { index: pos, id: call.id.clone(), name: call.name.clone(), arguments: delta });
                }
            }
            "response.function_call_arguments.done" => {
                let key = s(ev, "item_id");
                if let Some((_, call)) = self.calls.iter_mut().find(|(k, _)| *k == key) {
                    call.arguments = s(ev, "arguments");
                }
            }
            "response.output_text.annotation.added" => {
                let a = ev.get("annotation").cloned().unwrap_or(Value::Null);
                if a.get("type").and_then(Value::as_str) == Some("url_citation") {
                    self.cite(&s(&a, "url"), &s(&a, "title"), &mut out);
                }
            }
            "response.refusal.done" => {
                let r = s(ev, "refusal");
                out.push(ChatChunk::Refusal(r.clone()));
                self.refusal = Some(r);
            }
            "response.completed" => {
                self.terminal = true;
                self.finish = Some(if self.refusal.is_some() {
                    Finish::Refusal
                } else if !self.calls.is_empty() {
                    Finish::ToolCalls
                } else {
                    Finish::Stop
                });
            }
            "response.incomplete" => {
                self.terminal = true;
                let reason = ev.pointer("/response/incomplete_details/reason").and_then(Value::as_str);
                self.finish = Some(if reason == Some("content_filter") { Finish::Refusal } else { Finish::Length });
            }
            "response.failed" => {
                self.terminal = true;
                // `error` may be missing, a string or a list, and `code` may not be a string:
                // any of that is an unknown code, which is `bad_request`.
                let code = ev.pointer("/response/error/code").and_then(Value::as_str).unwrap_or("");
                self.error = Some(stream_error_kind(code));
            }
            "error" => self.error = Some(stream_error_kind(&s(ev, "code"))),
            _ => {}
        }
        out
    }

    fn push_anthropic(&mut self, ev: &Value) -> Vec<ChatChunk> {
        let mut out = Vec::new();
        let s = |v: &Value, k: &str| v.get(k).and_then(Value::as_str).unwrap_or("").to_string();
        let index = ev.get("index").and_then(Value::as_u64).unwrap_or(0);
        match ev.get("type").and_then(Value::as_str).unwrap_or("") {
            "content_block_start" => {
                let b = ev.get("content_block").cloned().unwrap_or(Value::Null);
                self.blocks.insert(index, Block { kind: s(&b, "type"), id: s(&b, "id"), name: s(&b, "name"), args: String::new() });
            }
            "content_block_delta" => {
                let d = ev.get("delta").cloned().unwrap_or(Value::Null);
                match d.get("type").and_then(Value::as_str).unwrap_or("") {
                    "text_delta" => self.text_delta(&s(&d, "text"), &mut out),
                    "input_json_delta" => {
                        if let Some(b) = self.blocks.get_mut(&index) {
                            b.args.push_str(&s(&d, "partial_json"));
                        }
                    }
                    "citations_delta" => {
                        let c = d.get("citation").cloned().unwrap_or(Value::Null);
                        self.cite(&s(&c, "url"), &s(&c, "title"), &mut out);
                    }
                    _ => {}
                }
            }
            "message_delta" => {
                let mapped = match ev.pointer("/delta/stop_reason").and_then(Value::as_str) {
                    Some("end_turn") | Some("stop_sequence") => Some(Finish::Stop),
                    Some("max_tokens") => Some(Finish::Length),
                    Some("tool_use") => Some(Finish::ToolCalls),
                    Some("refusal") => Some(Finish::Refusal),
                    _ => None,
                };
                if mapped.is_some() {
                    self.finish = mapped;
                }
            }
            "message_stop" => self.terminal = true,
            "error" => {
                // The same mapping as the Responses events; a missing or odd `error` is an unknown type.
                let kind = ev.pointer("/error/type").and_then(Value::as_str).unwrap_or("");
                self.error = Some(stream_error_kind(kind));
            }
            _ => {}
        }
        out
    }

    pub fn finish(self) -> Aggregate {
        let mut text = self.text;
        let mut refusal = self.refusal;
        let mut calls = self.calls;
        if self.format == Format::OpenAIChat {
            // Chat-completions calls are keyed by their `index`; the reference sorts by it.
            calls.sort_by_key(|(k, _)| k.parse::<u64>().unwrap_or(0));
        }
        let mut tool_calls: Vec<ToolCall> = calls.into_iter().map(|(_, c)| c).collect();
        match self.format {
            Format::OpenAIChat => {
                text = strip_think(&text);
                if self.finish == Some(Finish::Refusal) {
                    refusal = Some(String::new());
                }
            }
            Format::Anthropic => {
                tool_calls = self
                    .blocks
                    .into_values()
                    .filter(|b| b.kind == "tool_use")
                    .map(|b| ToolCall { id: b.id, name: b.name, arguments: b.args })
                    .collect();
                if self.finish == Some(Finish::Refusal) {
                    refusal = Some(std::mem::take(&mut text));
                }
            }
            Format::OpenAIResponses => {}
        }
        let error = self.error.or((!self.terminal).then_some(ErrorKind::Interrupted));
        Aggregate {
            text,
            tool_calls,
            citations: self.citations,
            refusal,
            finish: if error.is_some() { None } else { self.finish },
            error,
        }
    }
}

/// Folds a whole recorded stream at once.
#[cfg(test)]
pub fn aggregate(format: Format, sse: &str) -> Aggregate {
    let mut dec = SseDecoder::new();
    let mut agg = Aggregator::new(format);
    for p in dec.feed(sse.as_bytes()).into_iter().chain(dec.finish()) {
        agg.push(&p);
    }
    agg.finish()
}

/// Sends a streaming request and pumps its events into `sink`.
/// * Nothing back before `first_token` (headers included) → `Err(timeout)`.
/// * An HTTP error → `Err` classified by `errors::from_response`.
/// * Silence longer than `idle` after the first bytes, or a dropped connection,
///   ends the stream; the aggregator then reports `interrupted`.
pub async fn stream_request(
    request: reqwest::RequestBuilder,
    format: Format,
    first_token: Duration,
    idle: Duration,
    sink: &mut (dyn FnMut(ChatChunk) + Send),
) -> Result<Aggregate, AiError> {
    let deadline = tokio::time::Instant::now() + first_token;
    let mut response = match tokio::time::timeout_at(deadline, request.send()).await {
        Err(_) => return Err(AiError::new(ErrorKind::Timeout)),
        Ok(Err(e)) => return Err(errors::from_transport(&e)),
        Ok(Ok(r)) => r,
    };
    if !response.status().is_success() {
        return Err(errors::from_response(response).await);
    }
    let mut decoder = SseDecoder::new();
    let mut agg = Aggregator::new(format);
    let mut first = true;
    loop {
        let next = if first {
            tokio::time::timeout_at(deadline, response.chunk()).await
        } else {
            tokio::time::timeout(idle, response.chunk()).await
        };
        let bytes = match next {
            Err(_) if first => return Err(AiError::new(ErrorKind::Timeout)),
            Err(_) | Ok(Err(_)) => break,
            Ok(Ok(None)) => {
                for p in decoder.finish() {
                    for c in agg.push(&p) {
                        sink(c);
                    }
                }
                break;
            }
            Ok(Ok(Some(b))) => b,
        };
        first = false;
        for p in decoder.feed(&bytes) {
            for c in agg.push(&p) {
                sink(c);
            }
        }
        if agg.is_terminal() {
            break;
        }
    }
    Ok(agg.finish())
}
```

- [ ] **Step 4: Run the tests**

Run: `cargo test -p notchmeow ai::sse::`
Expected: `test result: ok. 9 passed; 0 failed`.
- `sse_fixtures` compares every `.txt` under `tests/fixtures/ai/sse/` with its `.expected.json`: 21 streams (openai-chat 6, openai-responses 10, anthropic 5), the number E1-0 ends with. It includes `failed-policy` (refusal), `failed-billing`, `failed-unknown` (`bad_request`), `cut` (interrupted), `content-filter` (finish `refusal`), `crlf` and `unicode-separators`.
- `sse_fixtures_byte_by_byte` feeds them one byte at a time.
- `response_failed_maps_its_code_like_an_error_event` covers the table rows the fixtures don't: `response.failed` reads `response.error.code` exactly like an `error` event, through `errors::stream_error_kind`. Rate limits, overload, billing, policy, auth and server codes get their own kinds, and anything unknown is `bad_request`, which never falls back to a local model.
- `odd_stream_errors_never_panic_and_never_fall_back`: an `error` that is a string, null or a list, a `code` that isn't a string, or no error at all, is an unknown code (`bad_request`), for both Responses events and Anthropic's `error` event.
- `lines_end_at_newline_only`: U+2028, U+0085, a vertical tab and a lone `\r` don't split a data line, and `\r\n` still ends one.

- [ ] **Step 5: Commit**

```bash
git add windows/src-tauri/src/ai
git commit -m "feat(ai): SSE decoder and aggregators for chat, Responses and Anthropic streams

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Text budget and history trimming

**Files:**
- Create: `windows/src-tauri/src/ai/budget.rs`
- Modify: `windows/src-tauri/src/ai/mod.rs` (add `pub mod budget;`)

**Interfaces:**
- **Consumes:** `catalog` limits; `provider::{Message, Part, Placement, Role}`; `errors::TOO_LONG`; `budget-cases.json` and `history-cases.json`.
- **Produces:**
  - `Budget { kept_chars, kept_lines, notice }`;
  - `char_budget(Placement, Option<u64>) -> usize`;
  - `budget(Placement, Option<u64>, &str) -> Budget`;
  - `cut(&str, &Budget) -> String`, which appends `\n\n[<notice>]` so the model knows too;
  - `message_chars(&Message) -> usize`: a message's size in Unicode scalars, as the history rule counts it: its text, plus each file's text, plus 1,000 for an image or PDF sent as such. File labels and base64 are not counted;
  - `messages_to_drop(Placement, Option<u64>, system_chars, &[usize]) -> usize`: `trim_history` from `reference.py`, the contract's rule (Global Constraints, "History trimming"). The slice holds each turn's `message_chars`, oldest first. It returns how many of the oldest turns to leave out, and the caller shows `errors::TOO_LONG` when that is more than 0. Cloud is never trimmed;
  - `RESERVED_OUTPUT_DIVISOR: u64 = 4` and `BINARY_ATTACHMENT_CHARS: usize = 1_000`, the two numbers `history-cases.json` carries in its `rule`.

  The reply length is not here: it depends on the placement and lives in the catalog, `catalog::max_output_tokens`.

- [ ] **Step 1: Write the tests**

Create `windows/src-tauri/src/ai/budget.rs` with only:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use crate::ai::provider::Role;
    use crate::ai::{errors, testkit};
    use serde_json::Value;

    fn placement(s: &str) -> Placement {
        serde_json::from_value(serde_json::Value::String(s.into())).unwrap()
    }

    #[test]
    fn budget_cases() {
        let data = testkit::load_json("budget-cases.json");
        let cases = data["cases"].as_array().unwrap();
        assert_eq!(cases.len(), 13, "budget-cases.json changed: update this count on purpose");
        for case in cases {
            let fill = case.get("fill").and_then(|v| v.as_str()).unwrap_or("a");
            let line_len = case["lineLength"].as_u64().unwrap() as usize;
            let count = case["lineCount"].as_u64().unwrap() as usize;
            let text = format!("{}\n", fill.repeat(line_len - 1)).repeat(count);
            let got = budget(placement(case["placement"].as_str().unwrap()), case["contextTokens"].as_u64(), &text);
            assert_eq!(serde_json::to_value(&got).unwrap(), case["expect"], "case {}", case["name"]);
        }
    }

    #[test]
    fn cut_keeps_scalars_and_tells_the_model() {
        let text = "🐱🐱\n🐱🐱\n";
        let b = Budget { kept_chars: 3, kept_lines: 1, notice: Some("I read the first line.".into()) };
        assert_eq!(cut(text, &b), "🐱🐱\n\n\n[I read the first line.]");
        let all = budget(Placement::Local, None, text);
        assert_eq!(cut(text, &all), text);
    }

    #[test]
    fn the_budget_is_floor_of_ctx_times_seven_quarters() {
        // Integers, so an odd context floors and never rounds: 4,097 × 7 / 4 = 7,169.75.
        assert_eq!(char_budget(Placement::Local, Some(4097)), 7169);
        assert_eq!(char_budget(Placement::Local, Some(4096)), 7168);
        assert_eq!(char_budget(Placement::Local, None), 7168);
        assert_eq!(char_budget(Placement::Network, Some(1)), 1);
        assert_eq!(char_budget(Placement::Cloud, None), 204_800);
        assert_eq!(char_budget(Placement::Cloud, Some(1_000_000)), 204_800);
        // A server can report any context: the product saturates instead of overflowing.
        let _ = char_budget(Placement::Local, Some(u64::MAX));
    }

    #[test]
    fn only_a_newline_ends_a_line() {
        // Each line is 12 scalars with a lone CR, U+2028 and U+0085 inside it. ctx 17 budgets 29: two lines fit, three don't.
        let text = "ab\rcd\u{2028}ef\u{85}gh\n".repeat(3);
        let got = budget(Placement::Local, Some(17), &text);
        assert_eq!(got, Budget { kept_chars: 24, kept_lines: 2, notice: Some("I read the first 2 lines.".into()) });
    }

    /// A `{fill, count}` from history-cases.json: `fill` repeated `count` times.
    fn filled(spec: &Value) -> String {
        spec["fill"].as_str().unwrap().repeat(spec["count"].as_u64().unwrap() as usize)
    }

    /// One turn of a history case as the message the session would send.
    fn message_of(turn: &Value) -> Message {
        let role: Role = serde_json::from_value(turn["role"].clone()).unwrap();
        let mut parts = Vec::new();
        for file in turn.get("files").and_then(Value::as_array).into_iter().flatten() {
            parts.push(match file["kind"].as_str().unwrap() {
                "text" => Part::FileText { name: "notes.txt".into(), text: filled(&file["text"]) },
                "image" => Part::Image { name: "photo.png".into(), mime: "image/png".into(), base64: String::new() },
                "pdf" => Part::Pdf { name: "paper.pdf".into(), base64: String::new() },
                other => panic!("history-cases.json has a new file kind: {other}"),
            });
        }
        parts.push(Part::Text(filled(&turn["text"])));
        Message { role, parts }
    }

    #[test]
    fn history_cases() {
        let data = testkit::load_json("history-cases.json");
        let cases = data["cases"].as_array().unwrap();
        assert_eq!(cases.len(), 12, "history-cases.json changed: update this count on purpose");
        for case in cases {
            let lengths: Vec<usize> =
                case["turns"].as_array().unwrap().iter().map(|t| message_chars(&message_of(t))).collect();
            let system_chars = filled(&case["system"]).chars().count();
            let ctx = case["contextTokens"].as_u64();
            let dropped = messages_to_drop(placement(case["placement"].as_str().unwrap()), ctx, system_chars, &lengths);
            let notice = (dropped > 0).then_some(errors::TOO_LONG);
            let got = serde_json::json!({ "dropped": dropped, "notice": notice });
            assert_eq!(got, case["expect"], "case {}", case["name"]);
        }
    }

    #[test]
    fn history_constants_match_the_fixture() {
        let rule = &testkit::load_json("history-cases.json")["rule"];
        assert_eq!(rule["reservedOutputDivisor"], RESERVED_OUTPUT_DIVISOR);
        assert_eq!(rule["binaryAttachmentChars"], BINARY_ATTACHMENT_CHARS);
        assert_eq!(rule["notice"], errors::TOO_LONG);
    }

    #[test]
    fn a_message_counts_its_text_its_file_text_and_1000_for_an_image_or_pdf() {
        let message = Message {
            role: Role::User,
            parts: vec![
                Part::FileText { name: "notes.txt".into(), text: "abc".into() },
                Part::Image { name: "a.png".into(), mime: "image/png".into(), base64: "x".repeat(50_000) },
                Part::Pdf { name: "b.pdf".into(), base64: "y".repeat(50_000) },
                Part::Text("🐱é".into()),
            ],
        };
        // The "File: notes.txt" labels and the base64 are not counted; 🐱 and é are one scalar each.
        assert_eq!(message_chars(&message), 3 + 1_000 + 1_000 + 2);
    }

    #[test]
    fn the_budget_line_is_the_contracts_down_to_the_scalar() {
        // ctx 5001: budget = 5001 − 1250 = 3751 tokens. That holds 13,128 scalars (ceil(2 × 13,128 ÷ 7) = 3,751)
        // and not 13,129. A float rule ("three quarters of the context, at 3.5 characters per token") would put the line at 13,127.
        assert_eq!(messages_to_drop(Placement::Local, Some(5001), 0, &[6564, 6564]), 0);
        assert_eq!(messages_to_drop(Placement::Local, Some(5001), 0, &[6564, 6565]), 1);
    }

    #[test]
    fn the_latest_turn_an_empty_history_and_cloud_are_never_trimmed() {
        assert_eq!(messages_to_drop(Placement::Local, None, 0, &[20_000]), 0);
        assert_eq!(messages_to_drop(Placement::Local, None, 50_000, &[]), 0);
        assert_eq!(messages_to_drop(Placement::Cloud, Some(1_000), 0, &[999_999, 1]), 0);
    }
}
```

Add `pub mod budget;` to `ai/mod.rs`, above `pub mod catalog;`.

- [ ] **Step 2: Run them to see them fail**

Run: `cargo test -p notchmeow ai::budget::`
Expected: FAIL to compile, with `cannot find function 'budget' in this scope` and similar errors.

- [ ] **Step 3: Write the budget**

Put this above the tests in `budget.rs`:

```rust
// How much of a file a model gets, and how much history fits. `budget` is `budget()` and
// `messages_to_drop` is `trim_history()` from tests/fixtures/ai/reference.py; `budget_cases` and
// `history_cases` run budget-cases.json and history-cases.json. "Characters" are Unicode scalar
// values (`chars()`), never bytes.

use serde::{Deserialize, Serialize};

use crate::ai::catalog;
use crate::ai::provider::{Message, Part, Placement};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Budget {
    pub kept_chars: usize,
    pub kept_lines: usize,
    /// "I read the first 716 lines." when the text was cut; `None` when it all fit.
    pub notice: Option<String>,
}

/// The character budget for one file: `floor(ctx × 7 / 4)`, which is half the context at 3.5
/// characters per token, in integers; unknown local context counts as 4,096 tokens; cloud is
/// capped at 204,800.
pub fn char_budget(placement: Placement, context_tokens: Option<u64>) -> usize {
    let ctx = match (context_tokens, placement) {
        (Some(c), _) => Some(c),
        (None, Placement::Cloud) => None,
        (None, _) => Some(catalog::DEFAULT_LOCAL_CONTEXT_TOKENS),
    };
    // Saturating: a server can report any context, and an overflow must not panic.
    let chars = ctx.map(|c| (c.saturating_mul(catalog::BUDGET_CHARS_NUMERATOR) / catalog::BUDGET_CHARS_DENOMINATOR) as usize);
    match placement {
        Placement::Cloud => chars.map_or(catalog::CLOUD_TEXT_CAP_CHARS, |c| c.min(catalog::CLOUD_TEXT_CAP_CHARS)),
        _ => chars.unwrap_or(0),
    }
}

pub fn budget(placement: Placement, context_tokens: Option<u64>, text: &str) -> Budget {
    let chars = char_budget(placement, context_tokens);
    let total = text.chars().count();
    if total <= chars {
        let lines = text.matches('\n').count() + usize::from(!text.is_empty() && !text.ends_with('\n'));
        return Budget { kept_chars: total, kept_lines: lines, notice: None };
    }
    let (mut kept, mut lines) = (0, 0);
    // `split_inclusive('\n')`, not `lines()`: a line ends at \n only (not at a lone \r, U+2028 or U+0085).
    for line in text.split_inclusive('\n') {
        let len = line.chars().count();
        if kept + len > chars {
            break;
        }
        kept += len;
        lines += 1;
    }
    let notice = match lines {
        0 => return Budget { kept_chars: chars, kept_lines: 0, notice: Some("I read the first part of this file.".into()) },
        1 => "I read the first line.".to_string(),
        n => format!("I read the first {n} lines."),
    };
    Budget { kept_chars: kept, kept_lines: lines, notice: Some(notice) }
}

/// The text a model actually receives, with the notice appended so it knows too.
pub fn cut(text: &str, b: &Budget) -> String {
    let kept: String = text.chars().take(b.kept_chars).collect();
    match &b.notice {
        Some(n) => format!("{kept}\n\n[{n}]"),
        None => kept,
    }
}

/// history-cases.json `rule.reservedOutputDivisor`: a quarter of the context is kept for the reply.
pub const RESERVED_OUTPUT_DIVISOR: u64 = 4;
/// history-cases.json `rule.binaryAttachmentChars`: what an image or PDF sent as such counts for.
pub const BINARY_ATTACHMENT_CHARS: usize = 1_000;

/// A message's size in Unicode scalars, the way the history rule counts it: its text, plus each
/// file's text, plus 1,000 for an image or PDF sent as such. The "File: name" labels and the
/// base64 are not counted.
pub fn message_chars(message: &Message) -> usize {
    message
        .parts
        .iter()
        .map(|part| match part {
            Part::Text(text) | Part::FileText { text, .. } => text.chars().count(),
            Part::Image { .. } | Part::Pdf { .. } => BINARY_ATTACHMENT_CHARS,
        })
        .sum()
}

/// `ceil(scalars ÷ 3.5)`, written as `ceil(2n ÷ 7)` in integers so that no platform rounds differently.
fn estimate_tokens(scalars: usize) -> u64 {
    (scalars as u64 * 2).div_ceil(7)
}

/// How many of the oldest turns to drop so the conversation fits a small model: `trim_history`
/// in tests/fixtures/ai/reference.py, whose cases `history_cases` runs. `lengths` are each turn's
/// `message_chars`, oldest first.
///
/// Cloud is never trimmed. For local and network models the budget is the context (4,096 when
/// unknown) minus a quarter kept for the reply. While the system prompt plus the remaining turns
/// cost more than that and more than one turn remains, the oldest two go (one, when two are left,
/// so the latest never does). The system prompt and the latest turn always stay.
pub fn messages_to_drop(placement: Placement, context_tokens: Option<u64>, system_chars: usize, lengths: &[usize]) -> usize {
    if placement == Placement::Cloud {
        return 0;
    }
    let ctx = context_tokens.unwrap_or(catalog::DEFAULT_LOCAL_CONTEXT_TOKENS);
    let budget = ctx - ctx / RESERVED_OUTPUT_DIVISOR;
    let mut total = system_chars + lengths.iter().sum::<usize>();
    let mut dropped = 0;
    while estimate_tokens(total) > budget && lengths.len() - dropped > 1 {
        let step = (lengths.len() - dropped - 1).min(2);
        total -= lengths[dropped..dropped + step].iter().sum::<usize>();
        dropped += step;
    }
    dropped
}
```

- [ ] **Step 4: Run the tests**

Run: `cargo test -p notchmeow ai::budget::`
Expected: `test result: ok. 9 passed; 0 failed`.
- `budget_cases` runs all 13 cases, `emoji-scalars` included, the ctx 4,097 case (7,169, not 7,170) and the lone-CR case ("a lone CR is not a line end").
- `history_cases` runs all 12 cases of `history-cases.json`, including the ctx = 5001 case where the contract's integer rule and a float formula part ways, and the two-turn case: two turns over budget drop 1, never both.
- `the_budget_line_is_the_contracts_down_to_the_scalar` keeps the 5001 boundary visible on both sides (13,128 scalars fit, 13,129 drop one).
- `the_budget_is_floor_of_ctx_times_seven_quarters` pins the integer arithmetic; `only_a_newline_ends_a_line` pins U+2028, U+0085 and a lone `\r`.

- [ ] **Step 5: Commit**

```bash
git add windows/src-tauri/src/ai
git commit -m "feat(ai): context-sized text budget and the contract's history trimming

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---
### Task 6: Files to the AI: classification, text extraction, drop-time reject

**Files:**
- Modify: `windows/src-tauri/Cargo.toml` (`[dependencies]`: `lopdf`, `zip`)
- Modify: `windows/Cargo.toml` (`[profile.release]`: `panic = "abort"` → `panic = "unwind"`, so `pdf_text`'s `catch_unwind` also works in release builds; costs a slightly larger binary, but a malformed PDF can no longer crash the app)
- Create: `windows/src-tauri/src/ai/attachments.rs`
- Modify: `windows/src-tauri/src/ai/mod.rs` (add `pub mod attachments;`)
- Modify: `windows/src-tauri/src/files.rs` (reject in `ingest`, plus a test)
- Modify: `windows/src-tauri/src/claude.rs:197-263` (use `attachments::base64`; drop its own copy and test)
- Modify: `windows/src-tauri/src/integrations.rs:148` (`crate::ai::attachments::base64`)

**Interfaces:**
- **Consumes:**
  - `budget::{budget, cut}`;
  - `catalog::{MAX_FILE_BYTES, reads_pdf_natively}`;
  - `provider::{Part, Placement}`;
  - `attachment-cases.json`, `make_attachments.py`.
- **Produces:**
  - `Kind::{Text, PdfText, PdfScanned, Image, Docx, Rtf, Html}`, which serializes as the contract's snake_case kinds;
  - `RejectReason::{Size, Type}`;
  - `Classified::{Accepted(Kind), Rejected(RejectReason)}`;
  - `screen(&Path)`: cheap, so it's safe on the UI thread;
  - `classify(&Path)`: also looks inside PDFs;
  - `reject_message(RejectReason) -> &str`;
  - `image_mime(ext)`, `pdf_text(&Path)`, `extract_text(&Path, Kind)`;
  - `word_xml_to_text`, `rtf_to_text`, `html_to_text`, `decode_entities`;
  - `base64(&[u8])`;
  - `Reader { provider, placement, vision, context_tokens }`;
  - `Prepared { parts, notice }`;
  - `PrepareError::{Rejected, CantSee, ScannedPdf, Heic, Unreadable}`: `ScannedPdf` is a scanned PDF this platform can neither render nor OCR (on Linux, whatever the model), and `Heic` is a HEIC photo, which is never sent to a model that sees images because Anthropic and OpenAI reject `image/heic` and local servers can't decode it;
  - `prepare(&Path, name, &Reader) -> Result<Prepared, PrepareError>`;
  - a private `mod ocr { image_text, pdf_text, pdf_pages_png }`, which returns `None` everywhere until Task 7.

- [ ] **Step 0: Let release builds unwind**

In `windows/Cargo.toml`, under `[profile.release]`, change:

```toml
panic = "abort"
```

to:

```toml
panic = "unwind"
```

`std::panic::catch_unwind` in `pdf_text` only works when panics unwind. Run `cd windows && cargo build --release -p notchmeow 2>&1 | tail -1`. Expected: `Finished`. If the package name differs, use the one in `windows/src-tauri/Cargo.toml`.

- [ ] **Step 1: Add the two crates**

In `windows/src-tauri/Cargo.toml`, under `[dependencies]`, below the `reqwest` line:

```toml
# Text out of PDFs (MIT). Default features off: no rayon, no chrono.
lopdf = { version = "0.45", default-features = false }
# A .docx is a zip. Reading only, with pure-Rust deflate (MIT).
zip = { version = "8", default-features = false, features = ["deflate-flate2-zlib-rs"] }
```

Run: `cargo tree -p notchmeow -e normal --depth 1 | grep -E "lopdf|zip"`
Expected: `├── lopdf v0.45.x` and `├── zip v8.x.y`. Both need Rust 1.88 or newer.

- [ ] **Step 2: Write the attachment tests**

Create `windows/src-tauri/src/ai/attachments.rs` with only:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use crate::ai::testkit;
    use serde_json::Value;

    fn local(vision: bool) -> Reader {
        Reader { provider: "ollama".into(), placement: Placement::Local, vision, context_tokens: None }
    }

    fn cloud(provider: &str) -> Reader {
        Reader { provider: provider.into(), placement: Placement::Cloud, vision: true, context_tokens: None }
    }

    #[test]
    fn rule_lists_match_attachment_cases_json() {
        let rules = testkit::load_json("attachment-cases.json");
        assert_eq!(rules["maxFileBytes"], catalog::MAX_FILE_BYTES);
        let rejects: Vec<&str> = rules["rejectExtensions"].as_array().unwrap().iter().map(|v| v.as_str().unwrap()).collect();
        assert_eq!(rejects, REJECT_EXTENSIONS);
        let images = rules["imageExtensions"].as_object().unwrap();
        assert_eq!(images.len(), IMAGE_EXTENSIONS.len());
        for (ext, mime) in IMAGE_EXTENSIONS {
            assert_eq!(images[*ext], *mime, "{ext}");
        }
    }

    #[test]
    fn attachment_cases() {
        let rules = testkit::load_json("attachment-cases.json");
        let dir = testkit::make_attachments();
        let cases = rules["cases"].as_array().unwrap();
        assert_eq!(cases.len(), 15, "attachment-cases.json changed: update this count on purpose");
        for case in cases {
            let file = case["file"].as_str().unwrap();
            let path = dir.path().join(file);
            let got = classify(&path).unwrap();
            match got {
                Classified::Rejected(r) => {
                    assert_eq!(case["kind"], "rejected", "{file}");
                    assert_eq!(serde_json::to_value(r).unwrap(), case["reason"], "{file} reason");
                }
                Classified::Accepted(kind) => {
                    assert_eq!(serde_json::to_value(kind).unwrap(), case["kind"], "{file}");
                    if let Some(mime) = case.get("mime").and_then(Value::as_str) {
                        let ext = path.extension().unwrap().to_str().unwrap().to_ascii_lowercase();
                        assert_eq!(image_mime(&ext), Some(mime), "{file} mime");
                    }
                    let text = extract_text(&path, kind).unwrap_or_default();
                    for want in case.get("contains").and_then(Value::as_array).into_iter().flatten() {
                        assert!(text.contains(want.as_str().unwrap()), "{file} should contain {want}: {text:?}");
                    }
                    for bad in case.get("notContains").and_then(Value::as_array).into_iter().flatten() {
                        assert!(!text.contains(bad.as_str().unwrap()), "{file} must not contain {bad}: {text:?}");
                    }
                }
            }
        }
    }

    #[test]
    fn broken_pdfs_never_panic() {
        let dir = testkit::make_attachments();
        let whole = std::fs::read(dir.path().join("text.pdf")).unwrap();
        let cut = dir.path().join("cut.pdf");
        std::fs::write(&cut, &whole[..whole.len() / 2]).unwrap();
        let junk = dir.path().join("junk.pdf");
        std::fs::write(&junk, b"%PDF-1.4\nnot really").unwrap();
        for p in [&cut, &junk] {
            assert_eq!(classify(p).unwrap(), Classified::Accepted(Kind::PdfScanned), "{}", p.display());
        }
    }

    #[test]
    fn prepare_follows_the_spec_table() {
        let dir = testkit::make_attachments();
        let p = |f: &str| dir.path().join(f);

        // A text PDF: native to Anthropic and OpenAI, extracted text for everyone else.
        let native = prepare(&p("text.pdf"), "text.pdf", &cloud("anthropic")).unwrap();
        assert!(matches!(&native.parts[0], Part::Pdf { name, .. } if name == "text.pdf"));
        assert!(matches!(&prepare(&p("text.pdf"), "text.pdf", &cloud("openai")).unwrap().parts[0], Part::Pdf { .. }));
        let local_pdf = prepare(&p("text.pdf"), "text.pdf", &local(false)).unwrap();
        assert!(matches!(&local_pdf.parts[0], Part::FileText { text, .. } if text.contains("Hello from NotchMeow")));
        let google_pdf = prepare(&p("text.pdf"), "text.pdf", &cloud("google")).unwrap();
        assert!(matches!(&google_pdf.parts[0], Part::FileText { .. }));

        // Images go to models that can see them.
        let img = prepare(&p("photo.png"), "photo.png", &local(true)).unwrap();
        assert!(matches!(&img.parts[0], Part::Image { mime, .. } if mime == "image/png"));

        // Rejects.
        assert_eq!(prepare(&p("big.txt"), "big.txt", &local(false)), Err(PrepareError::Rejected(RejectReason::Size)));
        assert_eq!(prepare(&p("archive.zip"), "archive.zip", &local(false)), Err(PrepareError::Rejected(RejectReason::Type)));

        // Office formats become text.
        let docx = prepare(&p("letter.docx"), "letter.docx", &cloud("anthropic")).unwrap();
        assert!(matches!(&docx.parts[0], Part::FileText { text, .. } if text.contains("live in the notch.")));
    }

    #[cfg(not(windows))]
    #[test]
    fn linux_cannot_read_images_or_scanned_pdfs_for_models_that_need_help() {
        let dir = testkit::make_attachments();
        let scan = dir.path().join("scan.pdf");
        assert_eq!(prepare(&dir.path().join("photo.png"), "photo.png", &local(false)), Err(PrepareError::CantSee));
        // A scanned PDF is not "this model can't see images": a model that sees fine still can't
        // be shown it here, because Linux has no PDF renderer and no OCR.
        assert_eq!(prepare(&scan, "scan.pdf", &local(false)), Err(PrepareError::ScannedPdf));
        assert_eq!(prepare(&scan, "scan.pdf", &local(true)), Err(PrepareError::ScannedPdf));
        assert_eq!(prepare(&scan, "scan.pdf", &cloud("google")), Err(PrepareError::ScannedPdf));
        // Claude and OpenAI take the PDF as it is.
        assert!(matches!(&prepare(&scan, "scan.pdf", &cloud("anthropic")).unwrap().parts[0], Part::Pdf { .. }));
        assert!(matches!(&prepare(&scan, "scan.pdf", &cloud("openai")).unwrap().parts[0], Part::Pdf { .. }));
    }

    #[test]
    fn heic_photos_are_never_sent() {
        let dir = testkit::TempDir::new("heic");
        let heic = dir.path().join("IMG_0001.HEIC");
        std::fs::write(&heic, b"\0\0\0\x18ftypheic\0\0\0\0mif1heic").unwrap();
        assert_eq!(classify(&heic).unwrap(), Classified::Accepted(Kind::Image));
        for reader in [cloud("anthropic"), cloud("openai"), cloud("google"), local(true)] {
            assert_eq!(prepare(&heic, "IMG_0001.HEIC", &reader), Err(PrepareError::Heic), "{}", reader.provider);
        }
        // A model that can't see goes to OCR, which can't read it either: say HEIC, not "can't see".
        assert_eq!(prepare(&heic, "IMG_0001.HEIC", &local(false)), Err(PrepareError::Heic));
        // JPEG and PNG still go out.
        let png = testkit::make_attachments();
        let sent = prepare(&png.path().join("photo.png"), "photo.png", &cloud("anthropic")).unwrap();
        assert!(matches!(&sent.parts[0], Part::Image { mime, .. } if mime == "image/png"));
    }

    #[test]
    fn long_text_is_cut_and_announced() {
        let dir = testkit::TempDir::new("long");
        let path = dir.path().join("long.txt");
        std::fs::write(&path, "aaaaaaaaa\n".repeat(1000)).unwrap();
        let got = prepare(&path, "long.txt", &local(false)).unwrap();
        assert_eq!(got.notice.as_deref(), Some("I read the first 716 lines."));
        assert!(matches!(&got.parts[0], Part::FileText { text, .. } if text.ends_with("[I read the first 716 lines.]")));
    }

    #[test]
    fn entities_and_odd_markup() {
        assert_eq!(decode_entities("a &amp; b &lt;c&gt; &#233;&#x41; &bogus; &"), "a & b <c> éA &bogus; &");
        assert_eq!(html_to_text("<P>One</P><DIV>Two<SCRIPT>x()</script></div>"), "One Two");
        assert_eq!(html_to_text("unclosed <b"), "unclosed");
        assert_eq!(rtf_to_text(r"{\rtf1 caf\'e9 \u233? ok\par}"), "café é ok");
    }

    #[test]
    fn base64_matches_rfc4648_vectors() {
        assert_eq!(base64(b""), "");
        assert_eq!(base64(b"f"), "Zg==");
        assert_eq!(base64(b"fo"), "Zm8=");
        assert_eq!(base64(b"foo"), "Zm9v");
        assert_eq!(base64(b"foob"), "Zm9vYg==");
        assert_eq!(base64(b"fooba"), "Zm9vYmE=");
        assert_eq!(base64(b"foobar"), "Zm9vYmFy");
    }
}
```

Add `pub mod attachments;` to `ai/mod.rs`, at the top of the `pub mod` list.

- [ ] **Step 3: Run them to see them fail**

Run: `cargo test -p notchmeow ai::attachments::`
Expected: FAIL to compile, with `cannot find function 'classify' in this scope` and similar errors.

- [ ] **Step 4: Write the pipeline**

Put this above the tests in `attachments.rs`:

```rust
// Files to the AI (spec §3): classify a dropped file, pull its text out, and
// shape it for the model that will read it. Classification follows the rules in
// tests/fixtures/ai/attachment-cases.json; `attachment_cases` runs every case.
//
// No file content is ever logged here or anywhere else.

use std::io::Read;
use std::path::Path;

use serde::Serialize;

use crate::ai::budget;
use crate::ai::catalog;
use crate::ai::provider::{Part, Placement};

pub const REJECT_EXTENSIONS: &[&str] = &[
    "zip", "gz", "tar", "7z", "rar", "dmg", "iso", "pkg", "msi", "exe", "app", "mov", "mp4", "mkv", "avi",
];

pub const IMAGE_EXTENSIONS: &[(&str, &str)] = &[
    ("png", "image/png"),
    ("jpg", "image/jpeg"),
    ("jpeg", "image/jpeg"),
    ("gif", "image/gif"),
    ("webp", "image/webp"),
    ("heic", "image/heic"),
];

/// How much of a file is sniffed to tell text from binary.
const SNIFF_BYTES: usize = 8192;
/// A docx's document.xml is read up to this size: guards against zip bombs.
const MAX_XML_BYTES: u64 = 64 * 1024 * 1024;

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum Kind {
    Text,
    PdfText,
    PdfScanned,
    Image,
    Docx,
    Rtf,
    Html,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "lowercase")]
pub enum RejectReason {
    Size,
    Type,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Classified {
    Accepted(Kind),
    Rejected(RejectReason),
}

/// The cheap part of classification: size, extension and a sniff of the first
/// 8 KB. PDFs come back as `PdfText` until `classify` looks inside them. Safe to
/// call on the UI thread.
pub fn screen(path: &Path) -> std::io::Result<Classified> {
    let meta = std::fs::metadata(path)?;
    if meta.len() > catalog::MAX_FILE_BYTES {
        return Ok(Classified::Rejected(RejectReason::Size));
    }
    let ext = path.extension().and_then(|e| e.to_str()).unwrap_or("").to_ascii_lowercase();
    let kind = match ext.as_str() {
        "pdf" => Kind::PdfText,
        e if image_mime(e).is_some() => Kind::Image,
        "docx" => Kind::Docx,
        "rtf" => Kind::Rtf,
        "html" | "htm" => Kind::Html,
        e if REJECT_EXTENSIONS.contains(&e) => return Ok(Classified::Rejected(RejectReason::Type)),
        _ => {
            let mut head = Vec::with_capacity(SNIFF_BYTES);
            std::fs::File::open(path)?.take(SNIFF_BYTES as u64).read_to_end(&mut head)?;
            if head.contains(&0) {
                return Ok(Classified::Rejected(RejectReason::Type));
            }
            if let Err(e) = std::str::from_utf8(&head) {
                // Only a multi-byte character cut by the 8 KB limit is allowed.
                if e.valid_up_to() + 3 < head.len() {
                    return Ok(Classified::Rejected(RejectReason::Type));
                }
            }
            Kind::Text
        }
    };
    Ok(Classified::Accepted(kind))
}

/// Full classification: `screen`, then a PDF is opened to see whether it has a text layer.
pub fn classify(path: &Path) -> std::io::Result<Classified> {
    match screen(path)? {
        Classified::Accepted(Kind::PdfText) if pdf_text(path).is_none() => Ok(Classified::Accepted(Kind::PdfScanned)),
        other => Ok(other),
    }
}

/// What the island says when the cat refuses a file at drop time.
pub fn reject_message(reason: RejectReason) -> &'static str {
    match reason {
        RejectReason::Size => "Files over 25 MB are too big for me.",
        RejectReason::Type => "I can't read this kind of file.",
    }
}

pub fn image_mime(ext: &str) -> Option<&'static str> {
    IMAGE_EXTENSIONS.iter().find(|(e, _)| *e == ext).map(|(_, m)| *m)
}

/// The PDF's text layer, or `None` for a scanned, encrypted or unreadable PDF.
///
/// A malformed PDF can make `lopdf` panic. The release profile unwinds (see the
/// `windows/Cargo.toml` step), so `catch_unwind` turns such a panic into "unreadable"
/// instead of killing the app.
pub fn pdf_text(path: &Path) -> Option<String> {
    let path = path.to_path_buf();
    std::panic::catch_unwind(move || {
        let doc = lopdf::Document::load(&path).ok()?;
        if doc.is_encrypted() {
            return None;
        }
        let pages: Vec<u32> = doc.get_pages().keys().copied().collect();
        let text = doc.extract_text(&pages).ok()?;
        (!text.trim().is_empty()).then_some(text)
    })
    .ok()
    .flatten()
}

/// A file's text, for every kind that has one.
pub fn extract_text(path: &Path, kind: Kind) -> Result<String, String> {
    let read = || std::fs::read(path).map(|b| String::from_utf8_lossy(&b).trim_start_matches('\u{feff}').to_string());
    match kind {
        Kind::Text => read().map_err(|e| e.to_string()),
        Kind::PdfText => pdf_text(path).ok_or_else(|| "no text layer".to_string()),
        Kind::Docx => docx_text(path),
        Kind::Rtf => read().map(|s| rtf_to_text(&s)).map_err(|e| e.to_string()),
        Kind::Html => read().map(|s| html_to_text(&s)).map_err(|e| e.to_string()),
        Kind::Image | Kind::PdfScanned => Err("no text layer".to_string()),
    }
}

fn docx_text(path: &Path) -> Result<String, String> {
    let file = std::fs::File::open(path).map_err(|e| e.to_string())?;
    let mut zip = zip::ZipArchive::new(file).map_err(|e| e.to_string())?;
    let entry = zip.by_name("word/document.xml").map_err(|e| e.to_string())?;
    let mut xml = String::new();
    entry.take(MAX_XML_BYTES).read_to_string(&mut xml).map_err(|e| e.to_string())?;
    Ok(word_xml_to_text(&xml))
}

/// The text of `<w:t>` runs; paragraphs end in a newline, tabs and breaks are kept.
pub fn word_xml_to_text(xml: &str) -> String {
    let mut out = String::new();
    let mut rest = xml;
    while let Some(lt) = rest.find('<') {
        let after = &rest[lt + 1..];
        let Some(gt) = after.find('>') else { break };
        let tag = &after[..gt];
        rest = &after[gt + 1..];
        let closing = tag.starts_with('/');
        let name = tag.trim_start_matches('/').split(|c: char| c.is_whitespace() || c == '/').next().unwrap_or("");
        match (closing, name) {
            (true, "w:p") => out.push('\n'),
            (false, "w:t") if !tag.ends_with('/') => {
                let end = rest.find("</w:t>").unwrap_or(rest.len());
                out.push_str(&decode_entities(&rest[..end]));
                rest = &rest[end..];
            }
            (false, "w:tab") => out.push('\t'),
            (false, "w:br") | (false, "w:cr") => out.push('\n'),
            _ => {}
        }
    }
    out.trim().to_string()
}

/// Plain text out of RTF: groups like the font table are skipped, `\par` is a
/// newline, `\'hh` and `\uN` escapes are decoded.
pub fn rtf_to_text(rtf: &str) -> String {
    const SKIP: &[&str] = &[
        "fonttbl", "colortbl", "stylesheet", "info", "pict", "header", "headerl", "headerr", "footer",
        "footerl", "footerr", "themedata", "colorschememapping", "latentstyles", "datastore", "xmlnstbl",
        "listtable", "listoverridetable", "rsidtbl", "generator", "object", "fldinst",
    ];
    let chars: Vec<char> = rtf.chars().collect();
    let mut out = String::new();
    let mut stack: Vec<bool> = Vec::new();
    let mut skip = false;
    let mut i = 0;
    while i < chars.len() {
        match chars[i] {
            '{' => {
                stack.push(skip);
                i += 1;
            }
            '}' => {
                skip = stack.pop().unwrap_or(false);
                i += 1;
            }
            '\\' if i + 1 < chars.len() => {
                let next = chars[i + 1];
                i += 2;
                if next.is_ascii_alphabetic() {
                    let mut word = String::from(next);
                    while i < chars.len() && chars[i].is_ascii_alphabetic() {
                        word.push(chars[i]);
                        i += 1;
                    }
                    let mut num = String::new();
                    if i < chars.len() && (chars[i] == '-' || chars[i].is_ascii_digit()) {
                        num.push(chars[i]);
                        i += 1;
                        while i < chars.len() && chars[i].is_ascii_digit() {
                            num.push(chars[i]);
                            i += 1;
                        }
                    }
                    if i < chars.len() && chars[i] == ' ' {
                        i += 1;
                    }
                    if SKIP.contains(&word.as_str()) {
                        skip = true;
                        continue;
                    }
                    if skip {
                        continue;
                    }
                    match word.as_str() {
                        "par" | "line" | "sect" | "page" | "row" => out.push('\n'),
                        "tab" | "cell" => out.push('\t'),
                        "u" => {
                            if let Ok(v) = num.parse::<i32>() {
                                let v = if v < 0 { v + 65536 } else { v };
                                if let Some(ch) = char::from_u32(v as u32) {
                                    out.push(ch);
                                }
                                // \uN is followed by one fallback character for old readers.
                                if i < chars.len() && !matches!(chars[i], '\\' | '{' | '}') {
                                    i += 1;
                                }
                            }
                        }
                        _ => {}
                    }
                } else if next == '*' {
                    skip = true;
                } else if next == '\'' {
                    let hex: String = chars[i..(i + 2).min(chars.len())].iter().collect();
                    if let Ok(b) = u8::from_str_radix(&hex, 16) {
                        if !skip {
                            out.push(cp1252(b));
                        }
                    }
                    i = (i + 2).min(chars.len());
                } else if !skip {
                    match next {
                        '\\' | '{' | '}' => out.push(next),
                        '~' => out.push('\u{a0}'),
                        '_' => out.push('-'),
                        _ => {}
                    }
                }
            }
            '\r' | '\n' => i += 1,
            c => {
                if !skip {
                    out.push(c);
                }
                i += 1;
            }
        }
    }
    out.trim().to_string()
}

/// Windows-1252, the code page RTF's `\'hh` escapes almost always use.
fn cp1252(b: u8) -> char {
    const HIGH: [char; 32] = [
        '€', '\u{81}', '‚', 'ƒ', '„', '…', '†', '‡', 'ˆ', '‰', 'Š', '‹', 'Œ', '\u{8d}', 'Ž', '\u{8f}',
        '\u{90}', '‘', '’', '“', '”', '•', '–', '—', '˜', '™', 'š', '›', 'œ', '\u{9d}', 'ž', 'Ÿ',
    ];
    match b {
        0x80..=0x9f => HIGH[(b - 0x80) as usize],
        _ => b as char,
    }
}

/// Visible text of an HTML page: `<script>`/`<style>` dropped, block tags become
/// spaces, entities decoded, whitespace runs collapsed to single spaces.
pub fn html_to_text(html: &str) -> String {
    const BLOCK: &[&str] = &[
        "p", "div", "br", "li", "ul", "ol", "tr", "td", "th", "table", "h1", "h2", "h3", "h4", "h5", "h6",
        "section", "article", "header", "footer", "blockquote", "pre", "hr", "title", "head", "body", "html",
    ];
    // ASCII lowercasing keeps every byte offset, so `lower` and `html` index alike.
    let lower = html.to_ascii_lowercase();
    let mut out = String::new();
    let mut i = 0;
    while i < html.len() {
        if html.as_bytes()[i] != b'<' {
            let next = html[i..].find('<').map_or(html.len(), |e| i + e);
            out.push_str(&decode_entities(&html[i..next]));
            i = next;
            continue;
        }
        if lower[i..].starts_with("<!--") {
            i = lower[i..].find("-->").map_or(html.len(), |e| i + e + 3);
            out.push(' ');
            continue;
        }
        let (tag, end) = match html[i..].find('>') {
            Some(e) => (&lower[i + 1..i + e], i + e + 1),
            None => (&lower[i + 1..], html.len()),
        };
        let name: String = tag.trim_start_matches('/').chars().take_while(|c| c.is_ascii_alphanumeric()).collect();
        if !tag.starts_with('/') && (name == "script" || name == "style") {
            let close = format!("</{name}");
            i = match lower[end..].find(&close) {
                Some(e) => lower[end + e..].find('>').map_or(html.len(), |g| end + e + g + 1),
                None => html.len(),
            };
            out.push(' ');
            continue;
        }
        if BLOCK.contains(&name.as_str()) {
            out.push(' ');
        }
        i = end;
    }
    out.split_whitespace().collect::<Vec<_>>().join(" ")
}

/// `&amp;`, `&lt;`, `&gt;`, `&quot;`, `&apos;`, `&#39;`, `&nbsp;`, `&#NNN;`, `&#xHH;`.
pub fn decode_entities(s: &str) -> String {
    let mut out = String::with_capacity(s.len());
    let mut rest = s;
    while let Some(amp) = rest.find('&') {
        out.push_str(&rest[..amp]);
        let after = &rest[amp + 1..];
        let semi = after.find(';').filter(|n| *n <= 10);
        let decoded = semi.and_then(|n| {
            let name = &after[..n];
            match name {
                "amp" => Some('&'),
                "lt" => Some('<'),
                "gt" => Some('>'),
                "quot" => Some('"'),
                "apos" => Some('\''),
                "nbsp" => Some('\u{a0}'),
                _ if name.starts_with("#x") || name.starts_with("#X") => {
                    u32::from_str_radix(&name[2..], 16).ok().and_then(char::from_u32)
                }
                _ if name.starts_with('#') => name[1..].parse().ok().and_then(char::from_u32),
                _ => None,
            }
        });
        match (decoded, semi) {
            (Some(c), Some(n)) => {
                out.push(c);
                rest = &after[n + 1..];
            }
            _ => {
                out.push('&');
                rest = after;
            }
        }
    }
    out.push_str(rest);
    out
}

/// Standard base64 (RFC 4648), for PDFs and images sent natively and for Stripe's basic auth.
pub fn base64(bytes: &[u8]) -> String {
    const TABLE: &[u8; 64] = b"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/";
    let mut out = String::with_capacity(bytes.len().div_ceil(3) * 4);
    for chunk in bytes.chunks(3) {
        let b = [chunk[0], *chunk.get(1).unwrap_or(&0), *chunk.get(2).unwrap_or(&0)];
        let n = ((b[0] as u32) << 16) | ((b[1] as u32) << 8) | b[2] as u32;
        out.push(TABLE[(n >> 18) as usize & 63] as char);
        out.push(TABLE[(n >> 12) as usize & 63] as char);
        out.push(if chunk.len() > 1 { TABLE[(n >> 6) as usize & 63] as char } else { '=' });
        out.push(if chunk.len() > 2 { TABLE[n as usize & 63] as char } else { '=' });
    }
    out
}

/// Who will read the file.
#[derive(Debug, Clone, PartialEq)]
pub struct Reader {
    pub provider: String,
    pub placement: Placement,
    pub vision: bool,
    pub context_tokens: Option<u64>,
}

#[derive(Debug, Clone, PartialEq)]
pub struct Prepared {
    pub parts: Vec<Part>,
    /// "I read the first 600 lines." when the text was cut.
    pub notice: Option<String>,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum PrepareError {
    Rejected(RejectReason),
    /// The model can't see images and nothing here can read them for it.
    CantSee,
    /// A scanned PDF this platform can neither render for a model that sees nor read with OCR.
    /// Not "can't see": a model that sees fine still can't be shown it.
    ScannedPdf,
    /// A HEIC photo. Anthropic and OpenAI reject `image/heic` and local servers can't decode
    /// it, so it is never sent; JPEG and PNG are.
    Heic,
    Unreadable,
}

fn is_heic(ext: &str) -> bool {
    ext == "heic"
}

fn text_part(name: &str, text: &str, reader: &Reader) -> Prepared {
    let b = budget::budget(reader.placement, reader.context_tokens, text);
    Prepared { parts: vec![Part::FileText { name: name.to_string(), text: budget::cut(text, &b) }], notice: b.notice }
}

/// Shapes one dropped file for one model (spec §3's table).
pub fn prepare(path: &Path, name: &str, reader: &Reader) -> Result<Prepared, PrepareError> {
    let kind = match classify(path).map_err(|_| PrepareError::Unreadable)? {
        Classified::Rejected(r) => return Err(PrepareError::Rejected(r)),
        Classified::Accepted(k) => k,
    };
    let bytes = || std::fs::read(path).map_err(|_| PrepareError::Unreadable);
    let name_s = name.to_string();
    match kind {
        Kind::PdfText | Kind::PdfScanned if catalog::reads_pdf_natively(&reader.provider) => {
            Ok(Prepared { parts: vec![Part::Pdf { name: name_s, base64: base64(&bytes()?) }], notice: None })
        }
        Kind::Image if reader.vision => {
            let ext = path.extension().and_then(|e| e.to_str()).unwrap_or("").to_ascii_lowercase();
            if is_heic(&ext) {
                return Err(PrepareError::Heic);
            }
            let mime = image_mime(&ext).unwrap_or("image/png").to_string();
            Ok(Prepared { parts: vec![Part::Image { name: name_s, mime, base64: base64(&bytes()?) }], notice: None })
        }
        Kind::Image => {
            let ext = path.extension().and_then(|e| e.to_str()).unwrap_or("").to_ascii_lowercase();
            ocr::image_text(path)
                .filter(|t| !t.trim().is_empty())
                .map(|t| text_part(name, &t, reader))
                .ok_or(if is_heic(&ext) { PrepareError::Heic } else { PrepareError::CantSee })
        }
        Kind::PdfScanned if reader.vision => {
            let pages = ocr::pdf_pages_png(path).filter(|p| !p.is_empty()).ok_or(PrepareError::ScannedPdf)?;
            let parts = pages
                .iter()
                .enumerate()
                .map(|(i, png)| Part::Image {
                    name: format!("{name}, page {}", i + 1),
                    mime: "image/png".into(),
                    base64: base64(png),
                })
                .collect();
            Ok(Prepared { parts, notice: None })
        }
        Kind::PdfScanned => ocr::pdf_text(path)
            .filter(|t| !t.trim().is_empty())
            .map(|t| text_part(name, &t, reader))
            .ok_or(PrepareError::ScannedPdf),
        _ => {
            let text = extract_text(path, kind).map_err(|_| PrepareError::Unreadable)?;
            Ok(text_part(name, &text, reader))
        }
    }
}

/// Without OCR or a PDF renderer, images reach only models that can see them.
mod ocr {
    use std::path::Path;

    pub fn image_text(_path: &Path) -> Option<String> {
        None
    }

    pub fn pdf_text(_path: &Path) -> Option<String> {
        None
    }

    pub fn pdf_pages_png(_path: &Path) -> Option<Vec<Vec<u8>>> {
        None
    }
}
```

- [ ] **Step 5: Run the attachment tests**

Run: `cargo test -p notchmeow ai::attachments::`
Expected: `test result: ok. 9 passed; 0 failed` (8 on Windows, where `linux_cannot_read_images_or_scanned_pdfs_for_models_that_need_help` doesn't compile in).
- `attachment_cases` runs all 15 cases, with `big.txt` generated sparse.
- `broken_pdfs_never_panic` covers a half PDF and a junk one.
- `linux_cannot_read_images_or_scanned_pdfs_for_models_that_need_help` pins the Linux wording: a picture for a model that can't see is `CantSee`, but a scanned PDF is `ScannedPdf` for every model that isn't Claude or OpenAI, a model that sees images included.
- `heic_photos_are_never_sent` covers `.HEIC` for Claude, OpenAI, Google and a local vision model.

- [ ] **Step 6: Refuse archives and huge files at drop time, test first**

In `windows/src-tauri/src/files.rs`, add this test inside `mod tests`, after `ingest_copies_and_never_overwrites`:

```rust
    #[test]
    fn ingest_refuses_what_the_cat_cannot_read() {
        let tmp = std::env::temp_dir().join(format!("notchmeow-reject-{}", std::process::id()));
        std::fs::create_dir_all(&tmp).unwrap();
        let (zip_name, big_name) = ("nm-test-bundle.zip", "nm-test-huge.txt");
        // A run before the fix copied these into the inbox; start clean.
        let _ = std::fs::remove_file(inbox_dir().join(zip_name));
        let _ = std::fs::remove_file(inbox_dir().join(big_name));

        let zip = tmp.join(zip_name);
        std::fs::write(&zip, b"PK\x03\x04").unwrap();
        assert_eq!(ingest(zip.to_str().unwrap()).err().as_deref(), Some("I can't read this kind of file."));
        let big = tmp.join(big_name);
        std::fs::File::create(&big).unwrap().set_len(26_214_401).unwrap();
        assert_eq!(ingest(big.to_str().unwrap()).err().as_deref(), Some("Files over 25 MB are too big for me."));
        assert!(!inbox_dir().join(zip_name).exists() && !inbox_dir().join(big_name).exists(), "nothing was copied");
        let _ = std::fs::remove_dir_all(&tmp);
    }
```

Run: `cargo test -p notchmeow files::`
Expected: FAIL: `ingest_refuses_what_the_cat_cannot_read`, `left: None`, `right: Some("I can't read this kind of file.")`.

Then change `files.rs`. Below `use serde::Serialize;`, add:

```rust
use crate::ai::attachments::{self, Classified};
```

and in `ingest`, right after the folder check:

```rust
    if meta.is_dir() {
        return Err("Folders can't be dropped yet.".into());
    }
    // The cat refuses archives, apps, videos and anything over 25 MB before
    // anything is copied (spec §3).
    if let Classified::Rejected(reason) = attachments::screen(src).map_err(|e| format!("cannot read {source}: {e}"))? {
        return Err(attachments::reject_message(reason).into());
    }
```

Run: `cargo test -p notchmeow files::`
Expected: `test result: ok. 2 passed; 0 failed`. The island's existing `ingestFile().catch` shows the message with the error sound, so nothing changes in TypeScript.

- [ ] **Step 7: One base64 for everyone**

In `windows/src-tauri/src/claude.rs`:
- delete `pub(crate) fn base64_for`, `fn base64` and the whole `#[cfg(test)] mod tests` block at the end;
- in `file_block`, change `base64(&bytes)` to `crate::ai::attachments::base64(&bytes)`.

The RFC 4648 test now lives in `attachments.rs` as `base64_matches_rfc4648_vectors`.

In `windows/src-tauri/src/integrations.rs`, line 148:

```rust
    let auth = format!("Basic {}", crate::ai::attachments::base64(format!("{key}:").as_bytes()));
```

Run: `cargo test --workspace`
Expected: every `test result:` line says `ok`.

- [ ] **Step 8: Commit**

```bash
git add windows/src-tauri/Cargo.toml windows/Cargo.lock windows/src-tauri/src
git commit -m "feat(ai): classify and read dropped files; refuse archives and huge files at drop

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Windows OCR and PDF page rendering

Windows reads text out of images and scanned PDFs with its own OCR, and renders PDF pages for local vision models, with no new dependency. Linux keeps the Task 6 behaviour: an image for a model that can't see gets "This model can't see images. Pick one that can.", and a scanned PDF gets "I can't read scanned PDFs on Linux yet. Try Claude or OpenAI, or paste the text."

**Files:**
- Modify: `windows/src-tauri/Cargo.toml` (`[target.'cfg(windows)'.dependencies]` `windows` features)
- Modify: `windows/src-tauri/src/ai/attachments.rs` (the `ocr` module and three Windows-only tests)

**Interfaces:**
- **Consumes:** Task 6's `prepare()`, which already calls `ocr::image_text`, `ocr::pdf_text` and `ocr::pdf_pages_png`.
- **Produces:** `ocr::{available, image_text, pdf_text, pdf_pages_png}` on Windows. It renders at most 3 pages and accepts `\\?\` and non-ASCII paths.

- [ ] **Step 1: Turn on the WinRT namespaces**

In `windows/src-tauri/Cargo.toml`, make the Windows `windows` dependency's feature list:

```toml
windows = { version = "0.61", features = [
  "Data_Pdf",
  "Foundation",
  "Graphics_Imaging",
  "Media_Ocr",
  "Storage",
  "Storage_Streams",
  "Win32_Foundation",
  "Win32_Security",
  "Win32_Security_Authorization",
  "Win32_System_Ole",
  "Win32_System_SystemInformation",
  "Win32_System_Threading",
  "Win32_UI_Input_KeyboardAndMouse",
  "Win32_UI_WindowsAndMessaging",
] }
```

- [ ] **Step 2: Write the Windows tests**

Add these three tests at the end of `mod tests` in `attachments.rs`:

```rust

    #[cfg(windows)]
    #[test]
    fn windows_renders_a_scanned_pdf_for_models_that_see() {
        let dir = testkit::make_attachments();
        let got = prepare(&dir.path().join("scan.pdf"), "scan.pdf", &local(true)).unwrap();
        assert!(
            matches!(&got.parts[0], Part::Image { name, mime, base64 }
                if name == "scan.pdf, page 1" && mime == "image/png" && base64.starts_with("iVBOR")),
            "expected the first page rendered as a PNG"
        );
    }

    #[cfg(windows)]
    #[test]
    fn windows_reads_text_out_of_a_rendered_pdf() {
        if !ocr::available() {
            eprintln!("skipped: no OCR language is installed for this user");
            return;
        }
        let dir = testkit::make_attachments();
        let text = ocr::pdf_text(&dir.path().join("text.pdf")).expect("OCR of a rendered page");
        assert!(text.contains("Hello"), "{text:?}");
    }

    #[cfg(windows)]
    #[test]
    fn windows_ocr_survives_unicode_and_verbatim_paths() {
        let src = testkit::make_attachments();
        let dir = testkit::TempDir::new("zoé");
        let pdf = dir.path().join("Zoé scan.pdf");
        std::fs::copy(src.path().join("text.pdf"), &pdf).unwrap();
        let verbatim = std::fs::canonicalize(&pdf).unwrap();
        assert!(verbatim.to_string_lossy().starts_with(r"\\?\"));
        assert_eq!(ocr::pdf_pages_png(&pdf).map(|p| p.len()), Some(1));
        assert_eq!(ocr::pdf_pages_png(&verbatim).map(|p| p.len()), Some(1));
    }
```

- [ ] **Step 3: Run them on Windows to see them fail**

Run on Windows: `cargo test -p notchmeow ai::attachments::`
Expected: FAIL to compile: `cannot find function 'available' in module 'ocr'`.

- [ ] **Step 4: Write the Windows OCR**

In `attachments.rs`, put `#[cfg(not(windows))]` on the Task 6 `ocr` module and reword its comment:

```rust
/// Linux has no built-in OCR or PDF renderer: images reach only models that can see.
#[cfg(not(windows))]
mod ocr {
```

Directly below that module, add:

```rust
/// Windows' own OCR (Windows.Media.Ocr) and PDF renderer (Windows.Data.Pdf): no
/// extra dependency. Called from a blocking thread, because the WinRT `.get()`
/// calls wait. windows-rs joins the multithreaded apartment on first use.
#[cfg(windows)]
mod ocr {
    use std::path::Path;

    use windows::core::{Param, HSTRING};
    use windows::Data::Pdf::PdfDocument;
    use windows::Graphics::Imaging::{BitmapDecoder, BitmapPixelFormat, SoftwareBitmap};
    use windows::Media::Ocr::OcrEngine;
    use windows::Storage::Streams::{Buffer, DataReader, IRandomAccessStream, InMemoryRandomAccessStream, InputStreamOptions};
    use windows::Storage::{FileAccessMode, StorageFile};

    /// The first pages are enough for a question, and keep a request small.
    const MAX_PDF_PAGES: u32 = 3;

    type R<T> = windows::core::Result<T>;

    /// `None` when no OCR language is installed for the user's languages.
    fn engine() -> Option<OcrEngine> {
        OcrEngine::TryCreateFromUserProfileLanguages().ok()
    }

    pub fn available() -> bool {
        engine().is_some()
    }

    fn open(path: &Path) -> R<StorageFile> {
        // WinRT refuses the `\\?\` paths that std::fs::canonicalize returns.
        let text = path.to_string_lossy();
        let plain = text.strip_prefix(r"\\?\").unwrap_or(&text);
        StorageFile::GetFileFromPathAsync(&HSTRING::from(plain))?.get()
    }

    fn bitmap<P: Param<IRandomAccessStream>>(stream: P) -> R<SoftwareBitmap> {
        let decoder = BitmapDecoder::CreateAsync(stream)?.get()?;
        let bitmap = decoder.GetSoftwareBitmapAsync()?.get()?;
        SoftwareBitmap::Convert(&bitmap, BitmapPixelFormat::Bgra8)
    }

    fn recognize<P: Param<IRandomAccessStream>>(engine: &OcrEngine, stream: P) -> R<String> {
        let result = engine.RecognizeAsync(&bitmap(stream)?)?.get()?;
        Ok(result.Text()?.to_string_lossy())
    }

    /// The first pages, each rendered to a PNG in memory.
    fn pages(path: &Path) -> R<Vec<InMemoryRandomAccessStream>> {
        let doc = PdfDocument::LoadFromFileAsync(&open(path)?)?.get()?;
        let mut out = Vec::new();
        for i in 0..doc.PageCount()?.min(MAX_PDF_PAGES) {
            let stream = InMemoryRandomAccessStream::new()?;
            doc.GetPage(i)?.RenderToStreamAsync(&stream)?.get()?;
            out.push(stream);
        }
        Ok(out)
    }

    fn png_bytes(stream: &InMemoryRandomAccessStream) -> R<Vec<u8>> {
        stream.Seek(0)?;
        let size = stream.Size()? as u32;
        let buffer = Buffer::Create(size)?;
        let read = stream.ReadAsync(&buffer, size, InputStreamOptions::None)?.get()?;
        let mut bytes = vec![0u8; read.Length()? as usize];
        DataReader::FromBuffer(&read)?.ReadBytes(&mut bytes)?;
        Ok(bytes)
    }

    pub fn image_text(path: &Path) -> Option<String> {
        let engine = engine()?;
        let stream = open(path).ok()?.OpenAsync(FileAccessMode::Read).ok()?.get().ok()?;
        recognize(&engine, &stream).ok()
    }

    pub fn pdf_text(path: &Path) -> Option<String> {
        let engine = engine()?;
        let mut text = Vec::new();
        for page in pages(path).ok()? {
            text.push(recognize(&engine, &page).ok()?);
        }
        Some(text.join("\n\n"))
    }

    pub fn pdf_pages_png(path: &Path) -> Option<Vec<Vec<u8>>> {
        let mut out = Vec::new();
        for page in pages(path).ok()? {
            out.push(png_bytes(&page).ok()?);
        }
        Some(out)
    }
}
```

- [ ] **Step 5: Run the tests**

Run on Windows: `cargo test -p notchmeow ai::attachments::`
Expected: `test result: ok. 11 passed; 0 failed`. On a machine without an OCR language, `windows_reads_text_out_of_a_rendered_pdf` prints `skipped:` and passes.

Run on Linux (or `windows/scripts/cargo-linux.sh test -p notchmeow ai::attachments::` on a Mac):
Expected: `test result: ok. 9 passed; 0 failed`, unchanged.

Without a Windows machine, this step runs in the Windows workflow (`Actions → Windows → Run workflow`) once the user pushes the branch. Note that in the task's report.

- [ ] **Step 6: Commit**

```bash
git add windows/src-tauri/Cargo.toml windows/Cargo.lock windows/src-tauri/src/ai/attachments.rs
git commit -m "feat(ai): Windows OCR and PDF page rendering for files to the AI

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 8: OpenAI-compatible provider and local discovery

**Files:**
- Modify: `windows/src-tauri/Cargo.toml` (`tokio` gains `macros`)
- Create: `windows/src-tauri/src/ai/openai_compat.rs`, `windows/src-tauri/src/ai/discovery.rs`
- Modify: `windows/src-tauri/src/ai/mod.rs` (add `pub mod discovery;` and `pub mod openai_compat;`)

**Interfaces:**
- **Consumes:**
  - `provider::{http_client, Endpoint, ModelProvider, …}`;
  - `sse::{stream_request, Format}`;
  - `errors::{from_transport, from_response}`;
  - `catalog::{get, filter_models, LOCAL_SERVERS, PROBE_MS, placement_of}`;
  - `crate::platform::{find_on_path, home_dir}`;
  - the fake server personas and failure modes.
- **Produces:**
  - **From `openai_compat.rs`:** `OpenAICompat::new(Endpoint)`, which implements `ModelProvider` (chat at `base_url + chatPath` from the catalog; `prewarm` loads an Ollama model), and `OpenAICompat::body(&ChatRequest) -> Value`.
  - **From `discovery.rs`:**
    - `UNKNOWN_SERVER`;
    - `ServerStatus::{Running, Off, NotInstalled, Outdated}`, which serializes as camelCase;
    - `Server { provider, name, base_url, host, placement, status, models, unencrypted }`;
    - `Probe { provider, base_url, key }`, whose `Debug` redacts the key;
    - `clean_server_url(url) -> Option<String>`: an http(s) URL with a host, without a trailing `/` or `/v1`, and without `user:pass@`, query or fragment. `settings::sanitized` and `custom_probe` both use it, so nothing secret is saved or shown;
    - `localhost_probes()`, `custom_probe(url, key) -> Option<Probe>`, `describe(provider, base_url) -> (host, Placement, unencrypted)`;
    - `async discover(Vec<Probe>, Duration) -> Vec<Server>`;
    - `async vision(&Server, model) -> bool`.

- [ ] **Step 1: Let tests and `select!` use tokio's macros**

In `windows/src-tauri/Cargo.toml`, change the `tokio` line to:

```toml
tokio = { version = "1", features = ["net", "io-util", "sync", "time", "rt", "macros"] }
```

- [ ] **Step 2: Write the provider tests**

Create `windows/src-tauri/src/ai/openai_compat.rs` with only:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use crate::ai::provider::{Message, Timeouts};
    use crate::ai::testkit::FakeServer;

    fn endpoint(provider: &str, base: &str) -> Endpoint {
        Endpoint {
            provider: provider.into(),
            name: "Test".into(),
            base_url: base.into(),
            key: None,
            placement: Placement::Local,
            timeouts: Timeouts::for_placement(Placement::Local),
        }
    }

    fn request(text: &str) -> ChatRequest {
        ChatRequest {
            model: "llama3.2".into(),
            system: "sys".into(),
            messages: vec![Message { role: Role::User, parts: vec![Part::Text(text.into())] }],
            tools: vec![],
            response_format: None,
            // Any value: the provider must put the request's own limit on the wire.
            max_tokens: 1234,
        }
    }

    async fn run(p: &OpenAICompat, req: &ChatRequest) -> (Result<Aggregate, AiError>, String) {
        let mut shown = String::new();
        let mut sink = |c: ChatChunk| {
            if let ChatChunk::Text(t) = c {
                shown.push_str(&t);
            }
        };
        let r = p.stream(req, &mut sink).await;
        (r, shown)
    }

    #[tokio::test]
    async fn streams_and_hides_think_blocks() {
        let fake = FakeServer::start(&[]);
        let p = OpenAICompat::new(endpoint("ollama", &fake.base));
        let (r, shown) = run(&p, &request("hi")).await;
        let agg = r.unwrap();
        assert_eq!(agg.error, None);
        assert!(!agg.text.contains("<think>") && agg.text.starts_with("## Answer"), "{:?}", agg.text);
        assert_eq!(shown, agg.text);
    }

    #[tokio::test]
    async fn request_sends_max_tokens_never_tool_choice_and_no_origin() {
        let fake = FakeServer::start(&[]);
        let p = OpenAICompat::new(endpoint("lmstudio", &fake.base));
        let _ = run(&p, &request("hi")).await;
        let log = fake.requests();
        let chat = log.iter().find(|r| r["path"] == "/v1/chat/completions").unwrap();
        assert_eq!(chat["body"]["max_tokens"], 1234, "the request's own limit, as given");
        assert!(chat["body"].get("max_completion_tokens").is_none());
        assert!(chat["body"].get("tool_choice").is_none());
        assert_eq!(chat["body"]["stream"], true);
        assert_eq!(chat["body"]["messages"][0]["role"], "system");
        assert!(chat["origin"].is_null(), "Ollama refuses http://tauri.localhost; we must send no Origin");
    }

    #[tokio::test]
    async fn cut_stream_keeps_partial_text_as_interrupted() {
        let fake = FakeServer::start(&["--fail", "cut"]);
        let p = OpenAICompat::new(endpoint("ollama", &fake.base));
        let agg = run(&p, &request("hi")).await.0.unwrap();
        assert_eq!(agg.error, Some(ErrorKind::Interrupted));
        assert_eq!(agg.finish, None);
    }

    #[tokio::test]
    async fn http_errors_are_classified() {
        let fake = FakeServer::start(&["--fail", "429"]);
        let p = OpenAICompat::new(endpoint("ollama", &fake.base));
        let err = run(&p, &request("hi")).await.0.unwrap_err();
        assert_eq!((err.kind, err.retry_after, err.status), (ErrorKind::RateLimited, Some(2), Some(429)));

        let fake = FakeServer::start(&["--fail", "500"]);
        let p = OpenAICompat::new(endpoint("ollama", &fake.base));
        assert_eq!(run(&p, &request("hi")).await.0.unwrap_err().kind, ErrorKind::Server);
    }

    #[tokio::test]
    async fn no_first_token_in_time_is_a_timeout() {
        let fake = FakeServer::start(&["--fail", "slow-first-token", "--delay", "2"]);
        let mut e = endpoint("ollama", &fake.base);
        e.timeouts.first_token = Duration::from_millis(400);
        let p = OpenAICompat::new(e);
        assert_eq!(run(&p, &request("hi")).await.0.unwrap_err().kind, ErrorKind::Timeout);
    }

    #[tokio::test]
    async fn refused_connection_is_unreachable() {
        let port = std::net::TcpListener::bind("127.0.0.1:0").unwrap().local_addr().unwrap().port();
        let p = OpenAICompat::new(endpoint("ollama", &format!("http://127.0.0.1:{port}")));
        assert_eq!(run(&p, &request("hi")).await.0.unwrap_err().kind, ErrorKind::Unreachable);
    }

    #[tokio::test]
    async fn lists_models_without_embeddings() {
        let fake = FakeServer::start(&[]);
        let p = OpenAICompat::new(endpoint("ollama", &fake.base));
        let ids: Vec<String> = p.list_models().await.unwrap().into_iter().map(|m| m.id).collect();
        assert_eq!(ids, ["llama3.2"]);
    }

    #[test]
    fn images_become_content_parts() {
        let req = ChatRequest {
            messages: vec![Message {
                role: Role::User,
                parts: vec![
                    Part::Image { name: "cat.png".into(), mime: "image/png".into(), base64: "AAAA".into() },
                    Part::Text("what is this?".into()),
                ],
            }],
            ..request("")
        };
        let body = OpenAICompat::body(&req);
        let content = &body["messages"][1]["content"];
        assert_eq!(content[1]["image_url"]["url"], "data:image/png;base64,AAAA");
        assert_eq!(content[2]["text"], "what is this?");
        let plain = OpenAICompat::body(&request("hello"));
        assert_eq!(plain["messages"][1]["content"], "hello");
    }
}
```

Add `pub mod openai_compat;` to `ai/mod.rs`, below `pub mod errors;`.

Run: `cargo test -p notchmeow ai::openai_compat::`
Expected: FAIL to compile: `cannot find type 'OpenAICompat' in this scope`.

- [ ] **Step 3: Write the provider**

Put this above the tests in `openai_compat.rs`:

```rust
// OpenAI-compatible chat completions: Google's OpenAI endpoint, Ollama, LM Studio,
// llama.cpp, Jan and any server the user adds. Sends `max_tokens` (not
// `max_completion_tokens`) and never `tool_choice`: Ollama ignores both.
// `<think>` blocks are hidden by the sse aggregator.

use std::time::Duration;

use serde_json::{json, Value};

use crate::ai::catalog;
use crate::ai::errors;
use crate::ai::provider::{
    file_label, file_text, http_client as client, AiError, Aggregate, BoxFuture, ChatChunk, ChatRequest, Endpoint,
    ErrorKind, ModelInfo, ModelProvider, Part, Placement, Role,
};
use crate::ai::sse::{self, Format};

pub struct OpenAICompat {
    pub endpoint: Endpoint,
}

impl OpenAICompat {
    pub fn new(endpoint: Endpoint) -> Self {
        OpenAICompat { endpoint }
    }

    fn url(&self, chat: bool) -> String {
        let def = catalog::get(&self.endpoint.provider).or_else(|| catalog::get("custom")).unwrap();
        let path = if chat { def.chat_path } else { def.models_path };
        format!("{}{}", self.endpoint.base_url.trim_end_matches('/'), path.unwrap_or(""))
    }

    fn authed(&self, req: reqwest::RequestBuilder) -> reqwest::RequestBuilder {
        match &self.endpoint.key {
            Some(k) => req.bearer_auth(k),
            None => req,
        }
    }

    pub fn body(request: &ChatRequest) -> Value {
        let mut messages = vec![json!({ "role": "system", "content": request.system })];
        for m in &request.messages {
            let role = if m.role == Role::User { "user" } else { "assistant" };
            if m.parts.iter().any(|p| matches!(p, Part::Image { .. })) {
                let mut content = Vec::new();
                for p in &m.parts {
                    match p {
                        Part::Text(t) => content.push(json!({ "type": "text", "text": t })),
                        Part::FileText { name, text } => content.push(json!({ "type": "text", "text": file_text(name, text) })),
                        Part::Pdf { name, .. } => content.push(json!({ "type": "text", "text": file_label(name) })),
                        Part::Image { name, mime, base64 } => {
                            content.push(json!({ "type": "text", "text": file_label(name) }));
                            content.push(json!({ "type": "image_url", "image_url": { "url": format!("data:{mime};base64,{base64}") } }));
                        }
                    }
                }
                messages.push(json!({ "role": role, "content": content }));
            } else {
                messages.push(json!({ "role": role, "content": m.plain_text() }));
            }
        }
        json!({
            "model": request.model,
            "messages": messages,
            "stream": true,
            "max_tokens": request.max_tokens,
        })
    }
}

impl ModelProvider for OpenAICompat {
    fn id(&self) -> &str {
        &self.endpoint.provider
    }

    fn display_name(&self) -> &str {
        &self.endpoint.name
    }

    fn placement(&self) -> Placement {
        self.endpoint.placement
    }

    fn list_models(&self) -> BoxFuture<'_, Result<Vec<ModelInfo>, AiError>> {
        Box::pin(async move {
            let client = client(&self.endpoint, Some(Duration::from_secs(10)));
            let response = self.authed(client.get(self.url(false))).send().await.map_err(|e| errors::from_transport(&e))?;
            if !response.status().is_success() {
                return Err(errors::from_response(response).await);
            }
            let body: Value = response.json().await.map_err(|_| AiError::new(ErrorKind::Server))?;
            let models = body["data"]
                .as_array()
                .into_iter()
                .flatten()
                .filter_map(|m| m["id"].as_str())
                .map(|id| ModelInfo::named(id.strip_prefix("models/").unwrap_or(id)))
                .collect();
            Ok(catalog::filter_models(&self.endpoint.provider, models))
        })
    }

    fn stream<'a>(
        &'a self,
        request: &'a ChatRequest,
        sink: &'a mut (dyn FnMut(ChatChunk) + Send),
    ) -> BoxFuture<'a, Result<Aggregate, AiError>> {
        Box::pin(async move {
            let client = client(&self.endpoint, None);
            let req = self.authed(client.post(self.url(true))).json(&Self::body(request));
            let t = self.endpoint.timeouts;
            sse::stream_request(req, Format::OpenAIChat, t.first_token, t.idle, sink).await
        })
    }

    /// Ollama loads a model when asked to generate nothing.
    fn prewarm<'a>(&'a self, model: &'a str) -> BoxFuture<'a, ()> {
        Box::pin(async move {
            if self.endpoint.provider != "ollama" {
                return;
            }
            let client = client(&self.endpoint, Some(Duration::from_secs(120)));
            let url = format!("{}/api/generate", self.endpoint.base_url.trim_end_matches('/'));
            let _ = client.post(url).json(&json!({ "model": model })).send().await;
        })
    }
}
```

Run: `cargo test -p notchmeow ai::openai_compat::`
Expected: `test result: ok. 8 passed; 0 failed`.
- `request_sends_max_tokens_never_tool_choice_and_no_origin` reads the fake server's request log.
- `no_first_token_in_time_is_a_timeout` takes about 0.4 s.

- [ ] **Step 4: Write the discovery tests**

Create `windows/src-tauri/src/ai/discovery.rs` with only:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use crate::ai::testkit::FakeServer;
    use std::time::Instant;

    fn closed_port() -> String {
        let port = std::net::TcpListener::bind("127.0.0.1:0").unwrap().local_addr().unwrap().port();
        format!("http://127.0.0.1:{port}")
    }

    fn probe(provider: &str, base: &str) -> Probe {
        Probe { provider: provider.into(), base_url: base.into(), key: None }
    }

    const T: Duration = Duration::from_millis(catalog::PROBE_MS);

    #[tokio::test]
    async fn personas_are_identified() {
        let ollama = FakeServer::start(&["--persona", "ollama"]);
        let lmstudio = FakeServer::start(&["--persona", "lmstudio"]);
        let llamacpp = FakeServer::start(&["--persona", "llamacpp"]);
        let jan = FakeServer::start(&["--persona", "jan"]);
        let servers = discover(
            vec![
                probe("ollama", &ollama.base),
                probe("lmstudio", &lmstudio.base),
                probe("llamacpp", &llamacpp.base),
                probe("jan", &jan.base),
            ],
            T,
        )
        .await;
        let names: Vec<&str> = servers.iter().map(|s| s.name.as_str()).collect();
        assert_eq!(names, ["Ollama", "LM Studio", "llama.cpp", "Jan"]);
        for s in &servers {
            assert_eq!(s.status, ServerStatus::Running, "{}", s.name);
            assert_eq!(s.models.iter().map(|m| m.id.as_str()).collect::<Vec<_>>(), ["llama3.2"], "{}", s.name);
            assert_eq!(s.placement, Placement::Local);
        }
        // Probes never carry an Origin header.
        assert!(ollama.requests().iter().all(|r| r["origin"].is_null()));
    }

    #[tokio::test]
    async fn the_wrong_server_on_a_known_port_is_a_local_server() {
        let generic = FakeServer::start(&[]);
        let servers = discover(vec![probe("ollama", &generic.base), probe("llamacpp", &generic.base)], T).await;
        for s in servers {
            assert_eq!((s.name.as_str(), s.status), (UNKNOWN_SERVER, ServerStatus::Running));
        }
    }

    #[tokio::test]
    async fn nothing_running_finishes_fast() {
        let probes = (0..4).map(|_| probe("jan", &closed_port())).collect();
        let started = Instant::now();
        let servers = discover(probes, T).await;
        assert!(started.elapsed() < Duration::from_millis(400), "took {:?}", started.elapsed());
        assert!(servers.iter().all(|s| s.status != ServerStatus::Running));
    }

    #[tokio::test]
    async fn a_silent_port_costs_one_probe_timeout() {
        // Accepts the connection, never answers.
        let listener = std::net::TcpListener::bind("127.0.0.1:0").unwrap();
        let base = format!("http://{}", listener.local_addr().unwrap());
        let started = Instant::now();
        let servers = discover(vec![probe("ollama", &base)], T).await;
        assert!(started.elapsed() < Duration::from_millis(600), "took {:?}", started.elapsed());
        assert_ne!(servers[0].status, ServerStatus::Running);
        drop(listener);
    }

    #[test]
    fn custom_urls_are_normalised() {
        let p = custom_probe(" http://studio-pc:11434/v1/ ", None).unwrap();
        assert_eq!(p.base_url, "http://studio-pc:11434");
        assert!(custom_probe("ftp://x", None).is_none());
        assert!(custom_probe("not a url", None).is_none());
    }

    #[test]
    fn a_typed_password_never_survives_into_the_url() {
        for typed in [
            "http://me:hunter2@studio-pc:11434",
            "http://me:hunter2@studio-pc:11434/v1/?api_key=abc#frag",
            "http://:hunter2@studio-pc:11434/",
            "https://me@studio-pc:11434/v1",
        ] {
            let clean = clean_server_url(typed).unwrap();
            assert!(!clean.contains("hunter2") && !clean.contains("me@") && !clean.contains("abc"), "{typed} → {clean}");
            assert!(clean.starts_with("http") && clean.contains("studio-pc:11434"), "{clean}");
            assert_eq!(custom_probe(typed, None).unwrap().base_url, clean);
        }
        assert_eq!(clean_server_url("http://me:pw@studio-pc:11434/v1/").as_deref(), Some("http://studio-pc:11434"));
        assert_eq!(clean_server_url("http://host/proxy/ollama/").as_deref(), Some("http://host/proxy/ollama"));
        assert_eq!(clean_server_url("not a url"), None);
    }

    #[test]
    fn a_probe_never_prints_its_key() {
        let p = custom_probe("http://studio-pc:11434", Some("sk-live-SECRET".into())).unwrap();
        let printed = format!("{p:?} {p:#?}");
        assert!(!printed.contains("sk-live-SECRET") && printed.contains("<redacted>"), "{printed}");
    }

    #[tokio::test]
    async fn a_custom_server_on_this_computer_is_local() {
        let fake = FakeServer::start(&[]);
        let local = discover(vec![custom_probe(&fake.base, None).unwrap()], T).await;
        assert_eq!((local[0].placement, local[0].unencrypted, local[0].status), (Placement::Local, false, ServerStatus::Running));
        assert_eq!(local[0].name, "127.0.0.1");
    }

    #[tokio::test]
    async fn a_server_url_with_a_password_reaches_the_webview_without_it() {
        let fake = FakeServer::start(&[]);
        let typed = format!("http://me:hunter2@{}", fake.base.trim_start_matches("http://"));
        let servers = discover(vec![custom_probe(&typed, None).unwrap()], T).await;
        assert_eq!(servers[0].status, ServerStatus::Running);
        // `Server` is what `ai_discover` sends to the webview.
        let sent = serde_json::to_string(&servers).unwrap();
        assert!(!sent.contains("hunter2") && !sent.contains("me:"), "{sent}");
    }

    #[test]
    fn a_network_server_is_labelled_and_plain_http_is_flagged() {
        assert_eq!(describe("custom", "http://studio-pc:11434"), ("studio-pc".into(), Placement::Network, true));
        assert_eq!(describe("custom", "https://studio-pc"), ("studio-pc".into(), Placement::Network, false));
        assert_eq!(describe("custom", "http://localhost:8080"), ("localhost".into(), Placement::Local, false));
        assert_eq!(describe("ollama", "http://127.0.0.1:11434"), ("127.0.0.1".into(), Placement::Local, false));
    }
}
```

Add `pub mod discovery;` to `ai/mod.rs`, below `pub mod catalog;`.

Run: `cargo test -p notchmeow ai::discovery::`
Expected: FAIL to compile: `cannot find function 'discover' in this scope`.

- [ ] **Step 5: Write discovery**

Put this above the tests in `discovery.rs`:

```rust
// Finding local model servers (spec §2). Only this computer (127.0.0.1) is
// checked on its own, every probe in parallel with a 300 ms limit; a network
// server is only ever one the user typed in. Runs at launch, when the picker or
// the AI settings open, and when Auto needs a local model — never on a timer.

use std::path::PathBuf;
use std::time::Duration;

use serde::Serialize;
use serde_json::{json, Value};

use crate::ai::catalog;
use crate::ai::provider::{ModelInfo, Placement};

/// Shown for anything that answers in the OpenAI format but isn't who its port says.
pub const UNKNOWN_SERVER: &str = "Local server (OpenAI-compatible)";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "camelCase")]
pub enum ServerStatus {
    Running,
    Off,
    NotInstalled,
    /// Ollama answers but has no OpenAI-compatible API yet.
    Outdated,
}

#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Server {
    /// ollama, lmstudio, llamacpp, jan or custom.
    pub provider: String,
    pub name: String,
    pub base_url: String,
    pub host: String,
    pub placement: Placement,
    pub status: ServerStatus,
    pub models: Vec<ModelInfo>,
    /// Plain http to another computer: "unencrypted on your network".
    pub unencrypted: bool,
}

#[derive(Clone, PartialEq)]
pub struct Probe {
    pub provider: String,
    pub base_url: String,
    pub key: Option<String>,
}

/// By hand, like `Endpoint`'s: a derived `Debug` would print the key.
impl std::fmt::Debug for Probe {
    fn fmt(&self, f: &mut std::fmt::Formatter<'_>) -> std::fmt::Result {
        f.debug_struct("Probe")
            .field("provider", &self.provider)
            .field("base_url", &self.base_url)
            .field("key", &self.key.as_ref().map(|_| "<redacted>"))
            .finish()
    }
}

/// The four servers checked on 127.0.0.1.
pub fn localhost_probes() -> Vec<Probe> {
    catalog::LOCAL_SERVERS
        .iter()
        .map(|id| Probe { provider: id.to_string(), base_url: catalog::get(id).unwrap().base_url.unwrap().to_string(), key: None })
        .collect()
}

/// What settings.json and the webview may hold for the server the user added: an http(s) URL
/// with a host, normalised (no trailing `/` or `/v1`) and without anything secret: a typed
/// `user:pass@`, a `?key=…` query or a `#fragment` are dropped, because a key belongs in the
/// key field (the OS keychain), never in a URL that is saved and shown. `None` for anything
/// that isn't such a URL.
pub fn clean_server_url(url: &str) -> Option<String> {
    let mut parsed = reqwest::Url::parse(url.trim()).ok()?;
    if !matches!(parsed.scheme(), "http" | "https") || parsed.host_str().is_none() {
        return None;
    }
    let _ = parsed.set_username("");
    let _ = parsed.set_password(None);
    parsed.set_query(None);
    parsed.set_fragment(None);
    let text = parsed.as_str().trim_end_matches('/');
    let text = text.strip_suffix("/v1").unwrap_or(text);
    Some(text.trim_end_matches('/').to_string())
}

/// The server the user added, as `clean_server_url` spells it. `None` for anything that
/// isn't an http(s) URL with a host.
pub fn custom_probe(url: &str, key: Option<String>) -> Option<Probe> {
    Some(Probe { provider: "custom".into(), base_url: clean_server_url(url)?, key })
}

/// Probes every server in parallel. Results keep the order of `probes`.
pub async fn discover(probes: Vec<Probe>, timeout: Duration) -> Vec<Server> {
    let handles: Vec<_> = probes.into_iter().map(|p| tokio::spawn(probe(p, timeout))).collect();
    let mut out = Vec::new();
    for h in handles {
        if let Ok(server) = h.await {
            out.push(server);
        }
    }
    out
}

/// `Some((status, json))` when the server answered at all; `None` when the
/// connection failed or timed out.
async fn get(client: &reqwest::Client, probe: &Probe, path: &str) -> Option<(u16, Value)> {
    let mut req = client.get(format!("{}{path}", probe.base_url));
    if let Some(k) = &probe.key {
        req = req.bearer_auth(k);
    }
    let resp = req.send().await.ok()?;
    let status = resp.status().as_u16();
    Some((status, resp.json().await.unwrap_or(Value::Null)))
}

fn model_list(body: &Value) -> Option<Vec<ModelInfo>> {
    let data = body.get("data")?.as_array()?;
    Some(data.iter().filter_map(|m| m["id"].as_str()).map(ModelInfo::named).collect())
}

/// Host, placement and the "unencrypted" flag of a server URL.
pub fn describe(provider: &str, base_url: &str) -> (String, Placement, bool) {
    let host = reqwest::Url::parse(base_url).ok().and_then(|u| u.host_str().map(str::to_string)).unwrap_or_default();
    let placement = catalog::placement_of(provider, Some(&host));
    let unencrypted = placement == Placement::Network && base_url.starts_with("http://");
    (host, placement, unencrypted)
}

async fn probe(p: Probe, timeout: Duration) -> Server {
    let (host, placement, unencrypted) = describe(&p.provider, &p.base_url);
    let catalog_name = catalog::get(&p.provider).map(|d| d.name).unwrap_or("Local server");
    let mut server = Server {
        provider: p.provider.clone(),
        name: if p.provider == "custom" { host.clone() } else { catalog_name.to_string() },
        base_url: p.base_url.clone(),
        host,
        placement,
        status: ServerStatus::Off,
        models: Vec::new(),
        unencrypted,
    };
    let client = reqwest::Client::builder().timeout(timeout).no_proxy().build().unwrap_or_default();

    // Who is this? The port's own check endpoint (catalog `probePath`); a
    // connection failure ends it here.
    let check = catalog::get(&p.provider).and_then(|d| d.probe_path).filter(|path| *path != "/v1/models");
    let identified = match (p.provider.as_str(), check) {
        ("ollama", Some(path)) => match get(&client, &p, path).await {
            None => return finish(server),
            Some((200, v)) => v.get("version").is_some(),
            Some(_) => false,
        },
        (_, Some(path)) => match get(&client, &p, path).await {
            None => return finish(server),
            Some((status, _)) => status == 200,
        },
        _ => true,
    };
    let body = match get(&client, &p, "/v1/models").await {
        None => return finish(server),
        Some((200, body)) => body,
        Some((404, _)) if identified && p.provider == "ollama" => {
            server.status = ServerStatus::Outdated;
            return server;
        }
        Some(_) => Value::Null,
    };
    let Some(models) = model_list(&body) else {
        // llama.cpp says it is healthy but has no model list yet: still loading.
        if identified && p.provider == "llamacpp" {
            server.status = ServerStatus::Running;
        }
        return finish(server);
    };
    // mistral.rs also takes port 1234; LM Studio's list says `organization_owner` or nothing.
    let lmstudio_like = p.provider != "lmstudio"
        || body["data"]
            .as_array()
            .into_iter()
            .flatten()
            .filter_map(|m| m.get("owned_by").and_then(Value::as_str))
            .all(|o| o == "organization_owner");
    if !(identified && lmstudio_like) && p.provider != "custom" {
        server.name = UNKNOWN_SERVER.to_string();
    }
    server.status = ServerStatus::Running;
    server.models = catalog::filter_models(&p.provider, models);
    server
}

/// A server that didn't answer is "Server off", or "Not installed" when nothing
/// of it is on this computer either.
fn finish(mut server: Server) -> Server {
    if server.status == ServerStatus::Off && !installed(&server.provider) {
        server.status = ServerStatus::NotInstalled;
    }
    server
}

/// Best effort: Jan and custom servers can't be told apart from "off", so they count as installed.
fn installed(provider: &str) -> bool {
    let home: PathBuf = crate::platform::home_dir();
    match provider {
        "ollama" => crate::platform::find_on_path("ollama").is_some(),
        "lmstudio" => crate::platform::find_on_path("lms").is_some() || home.join(".lmstudio").exists(),
        "llamacpp" => crate::platform::find_on_path("llama-server").is_some(),
        _ => true,
    }
}

/// Whether a local model reads images: Ollama's `/api/show` capabilities, LM Studio's
/// model type. Anything else, or no answer within a second, counts as text only.
pub async fn vision(server: &Server, model: &str) -> bool {
    let client = reqwest::Client::builder().timeout(Duration::from_secs(1)).no_proxy().build().unwrap_or_default();
    let base = server.base_url.trim_end_matches('/');
    match server.provider.as_str() {
        "ollama" => {
            let Ok(resp) = client.post(format!("{base}/api/show")).json(&json!({ "model": model })).send().await else {
                return false;
            };
            let body: Value = resp.json().await.unwrap_or(Value::Null);
            body["capabilities"].as_array().is_some_and(|c| c.iter().any(|v| v == "vision"))
        }
        "lmstudio" => {
            let Ok(resp) = client.get(format!("{base}/api/v0/models/{model}")).send().await else {
                return false;
            };
            let body: Value = resp.json().await.unwrap_or(Value::Null);
            body["type"] == "vlm"
        }
        _ => false,
    }
}
```

Run: `cargo test -p notchmeow ai::discovery::`
Expected: `test result: ok. 10 passed; 0 failed`.
- `nothing_running_finishes_fast` asserts under 400 ms.
- `a_silent_port_costs_one_probe_timeout` asserts under 600 ms.
- `a_typed_password_never_survives_into_the_url` and `a_server_url_with_a_password_reaches_the_webview_without_it` cover `user:pass@`, `?api_key=…` and `#fragment` in an added server's URL: none is kept, and the `Server` that `ai_discover` sends to the webview has none.
- `a_probe_never_prints_its_key` pins `Probe`'s hand-written `Debug`.

- [ ] **Step 6: Commit**

```bash
git add windows/src-tauri/Cargo.toml windows/Cargo.lock windows/src-tauri/src/ai
git commit -m "feat(ai): OpenAI-compatible provider and parallel localhost discovery

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 9: Anthropic provider, streaming

`claude.rs` keeps serving `chat_send` until Task 13 moves the chat over. This task adds the streaming provider next to it.

**Files:**
- Create: `windows/src-tauri/src/ai/anthropic.rs`
- Modify: `windows/src-tauri/src/ai/mod.rs` (add `pub mod anthropic;`)

**Interfaces:**
- **Consumes:** `provider::*`, `sse::stream_request(Format::Anthropic)`, `errors`, `catalog::{cloud_capabilities, web_search_tools}`, `testkit::load_json`.
- **Produces:**
  - `ANTHROPIC_VERSION = "2023-06-01"`;
  - `FALLBACK_BETA = "server-side-fallback-2026-07-01"`;
  - `Anthropic::new(Endpoint)`, which implements `ModelProvider`; its `list_models` calls `GET /v1/models?limit=100`;
  - `Anthropic::body(&ChatRequest) -> Value`. PDFs become `document` blocks and images become `image` blocks, each followed by `File: <name>`. The web-search tool is `catalog::web_search_tools("anthropic", model)`, never a literal here: the tests compare the request with providers.json `webSearch`.

- [ ] **Step 1: Write the tests**

Create `windows/src-tauri/src/ai/anthropic.rs` with only:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use crate::ai::provider::{Finish, Message, Timeouts};
    use crate::ai::testkit::{self, FakeServer};

    fn endpoint(base: &str) -> Endpoint {
        Endpoint {
            provider: "anthropic".into(),
            name: "Anthropic".into(),
            base_url: base.into(),
            key: Some("sk-ant-test".into()),
            placement: Placement::Cloud,
            timeouts: Timeouts::for_placement(Placement::Cloud),
        }
    }

    fn request() -> ChatRequest {
        ChatRequest {
            model: "claude-sonnet-5-5".into(),
            system: "sys".into(),
            messages: vec![Message {
                role: Role::User,
                parts: vec![Part::Pdf { name: "a.pdf".into(), base64: "JVBERi0=".into() }, Part::Text("sum it up".into())],
            }],
            tools: vec![],
            response_format: None,
            max_tokens: 1234,
        }
    }

    #[tokio::test]
    async fn streams_text_and_sources() {
        let fake = FakeServer::start(&[]);
        let p = Anthropic::new(endpoint(&fake.base));
        let mut cites = Vec::new();
        let mut sink = |c: ChatChunk| {
            if let ChatChunk::Citation { url, .. } = c {
                cites.push(url);
            }
        };
        let agg = p.stream(&request(), &mut sink).await.unwrap();
        assert_eq!(agg.text, "Cats sleep a lot.");
        assert_eq!(agg.finish, Some(Finish::Stop));
        assert_eq!(cites, ["https://example.com/cats"]);

        let req = &fake.requests()[0];
        assert_eq!(req["path"], "/v1/messages");
        assert_eq!(req["body"]["stream"], true);
        // The tool is exactly what providers.json says for this model.
        let ws = &testkit::load_json("providers.json")["webSearch"]["anthropic"];
        assert_eq!(req["body"]["tools"][0], json!({ "type": ws["type"], "name": ws["name"], "max_uses": ws["max_uses"] }));
        assert_eq!(req["body"]["messages"][0]["content"][0]["type"], "document");
        assert!(req["origin"].is_null());
    }

    #[tokio::test]
    async fn refusal_and_errors() {
        let fake = FakeServer::start(&["--fail", "refuse"]);
        let agg = Anthropic::new(endpoint(&fake.base)).stream(&request(), &mut |_| {}).await.unwrap();
        assert_eq!((agg.finish, agg.refusal.as_deref()), (Some(Finish::Refusal), Some("")));

        let fake = FakeServer::start(&["--fail", "401"]);
        let err = Anthropic::new(endpoint(&fake.base)).stream(&request(), &mut |_| {}).await.unwrap_err();
        assert_eq!(err.kind, ErrorKind::Auth);

        let fake = FakeServer::start(&["--fail", "overloaded"]);
        let err = Anthropic::new(endpoint(&fake.base)).stream(&request(), &mut |_| {}).await.unwrap_err();
        assert_eq!((err.kind, err.status), (ErrorKind::Overloaded, Some(529)));

        let fake = FakeServer::start(&["--fail", "cut"]);
        let agg = Anthropic::new(endpoint(&fake.base)).stream(&request(), &mut |_| {}).await.unwrap();
        assert_eq!(agg.error, Some(ErrorKind::Interrupted));
    }

    #[test]
    fn older_models_get_the_legacy_search_tool() {
        let ws = &testkit::load_json("providers.json")["webSearch"]["anthropic"];
        let mut req = request();
        req.model = "claude-haiku-4-5-20251001".into();
        assert_eq!(Anthropic::body(&req)["tools"][0]["type"], ws["legacyType"]);
        req.model = "claude-sonnet-5-5".into();
        assert_eq!(Anthropic::body(&req)["tools"][0]["type"], ws["type"]);
    }

    #[tokio::test]
    async fn lists_models_with_a_page_size() {
        // This is also the settings window's key check: a good key gets a list, so ✓.
        let fake = FakeServer::start(&[]);
        let models = Anthropic::new(endpoint(&fake.base)).list_models().await.unwrap();
        assert_eq!(models.iter().map(|m| m.id.as_str()).collect::<Vec<_>>(), ["llama3.2", "nomic-embed-text"]);
        assert!(models.iter().all(|m| m.capabilities == catalog::cloud_capabilities() && m.display_name == m.id));
        let log = fake.requests();
        assert_eq!(log.len(), 1);
        assert_eq!((log[0]["method"].as_str(), log[0]["path"].as_str()), (Some("GET"), Some("/v1/models?limit=100")));
        assert!(log[0]["origin"].is_null());
    }

    #[test]
    fn images_are_image_blocks() {
        let mut req = request();
        req.messages[0].parts = vec![Part::Image { name: "c.png".into(), mime: "image/png".into(), base64: "AA==".into() }];
        let body = Anthropic::body(&req);
        assert_eq!(body["messages"][0]["content"][0]["source"]["media_type"], "image/png");
        assert_eq!(body["messages"][0]["content"][1]["text"], "File: c.png");
        assert_eq!(body["fallbacks"], "default");
    }
}
```

Add `pub mod anthropic;` to `ai/mod.rs`, at the top of the `pub mod` list.

Run: `cargo test -p notchmeow ai::anthropic::`
Expected: FAIL to compile: `cannot find type 'Anthropic' in this scope`.

- [ ] **Step 2: Write the provider**

Put this above the tests in `anthropic.rs`:

```rust
// Claude through Anthropic's Messages API: the integration that lived in
// claude.rs, now streaming. Server-side web search with cited sources, PDFs as
// document blocks, images as image blocks. The key never leaves Rust.

use std::time::Duration;

use serde_json::{json, Value};

use crate::ai::catalog;
use crate::ai::errors;
use crate::ai::provider::{
    file_label, file_text, http_client as client, AiError, Aggregate, BoxFuture, ChatChunk, ChatRequest, Endpoint, ErrorKind, ModelInfo,
    ModelProvider, Part, Placement, Role,
};
use crate::ai::sse::{self, Format};

pub const ANTHROPIC_VERSION: &str = "2023-06-01";
/// Server-side fallback: on a policy decline the API retries the same request on
/// a fallback model inside the same call, so the island never shows a dead end.
pub const FALLBACK_BETA: &str = "server-side-fallback-2026-07-01";

pub struct Anthropic {
    pub endpoint: Endpoint,
}

impl Anthropic {
    pub fn new(endpoint: Endpoint) -> Self {
        Anthropic { endpoint }
    }

    fn headers(&self, req: reqwest::RequestBuilder) -> reqwest::RequestBuilder {
        req.header("x-api-key", self.endpoint.key.clone().unwrap_or_default())
            .header("anthropic-version", ANTHROPIC_VERSION)
    }

    pub fn body(request: &ChatRequest) -> Value {
        let messages: Vec<Value> = request
            .messages
            .iter()
            .map(|m| {
                let mut content = Vec::new();
                for p in &m.parts {
                    match p {
                        Part::Text(t) => content.push(json!({ "type": "text", "text": t })),
                        Part::FileText { name, text } => content.push(json!({ "type": "text", "text": file_text(name, text) })),
                        Part::Pdf { name, base64 } => {
                            content.push(json!({ "type": "document", "source": { "type": "base64", "media_type": "application/pdf", "data": base64 } }));
                            content.push(json!({ "type": "text", "text": file_label(name) }));
                        }
                        Part::Image { name, mime, base64 } => {
                            content.push(json!({ "type": "image", "source": { "type": "base64", "media_type": mime, "data": base64 } }));
                            content.push(json!({ "type": "text", "text": file_label(name) }));
                        }
                    }
                }
                json!({ "role": if m.role == Role::User { "user" } else { "assistant" }, "content": content })
            })
            .collect();
        json!({
            "model": request.model,
            "max_tokens": request.max_tokens,
            "system": request.system,
            "tools": catalog::web_search_tools("anthropic", &request.model),
            "fallbacks": "default",
            "stream": true,
            "messages": messages,
        })
    }
}

impl ModelProvider for Anthropic {
    fn id(&self) -> &str {
        "anthropic"
    }

    fn display_name(&self) -> &str {
        &self.endpoint.name
    }

    fn placement(&self) -> Placement {
        Placement::Cloud
    }

    fn list_models(&self) -> BoxFuture<'_, Result<Vec<ModelInfo>, AiError>> {
        Box::pin(async move {
            let client = client(&self.endpoint, Some(Duration::from_secs(10)));
            let url = format!("{}/v1/models?limit=100", self.endpoint.base_url.trim_end_matches('/'));
            let response = self.headers(client.get(url)).send().await.map_err(|e| errors::from_transport(&e))?;
            if !response.status().is_success() {
                return Err(errors::from_response(response).await);
            }
            let body: Value = response.json().await.map_err(|_| AiError::new(ErrorKind::Server))?;
            Ok(body["data"]
                .as_array()
                .into_iter()
                .flatten()
                .filter_map(|m| {
                    let id = m["id"].as_str()?;
                    Some(ModelInfo {
                        id: id.to_string(),
                        display_name: m["display_name"].as_str().unwrap_or(id).to_string(),
                        context_tokens: None,
                        capabilities: catalog::cloud_capabilities(),
                    })
                })
                .collect())
        })
    }

    fn stream<'a>(
        &'a self,
        request: &'a ChatRequest,
        sink: &'a mut (dyn FnMut(ChatChunk) + Send),
    ) -> BoxFuture<'a, Result<Aggregate, AiError>> {
        Box::pin(async move {
            let client = client(&self.endpoint, None);
            let url = format!("{}/v1/messages", self.endpoint.base_url.trim_end_matches('/'));
            let req = self
                .headers(client.post(url))
                .header("anthropic-beta", FALLBACK_BETA)
                .json(&Self::body(request));
            let t = self.endpoint.timeouts;
            sse::stream_request(req, Format::Anthropic, t.first_token, t.idle, sink).await
        })
    }
}
```

- [ ] **Step 3: Run the tests**

Run: `cargo test -p notchmeow ai::anthropic::`
Expected: `test result: ok. 5 passed; 0 failed`.
- `streams_text_and_sources` checks the request's `tools[0]` against providers.json `webSearch.anthropic`, and `older_models_get_the_legacy_search_tool` checks Haiku 4.x against its `legacyType`.
- `lists_models_with_a_page_size` runs `list_models` against the fake server's `GET /v1/models?limit=100` (it ignores query strings): the request log shows the query, and the list is what the settings window's key check turns into ✓.

- [ ] **Step 4: Commit**

```bash
git add windows/src-tauri/src/ai
git commit -m "feat(ai): streaming Anthropic provider with web search sources

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 10: OpenAI provider (Responses API)

**Files:**
- Create: `windows/src-tauri/src/ai/openai.rs`
- Modify: `windows/src-tauri/src/ai/mod.rs` (add `pub mod openai;`)

**Interfaces:**
- **Consumes:** `provider::*`, `sse::stream_request(Format::OpenAIResponses)`, `errors`, `catalog::{filter_models, cloud_capabilities}`.
- **Produces:** `OpenAI::new(Endpoint)`, which implements `ModelProvider`, and `OpenAI::body(&ChatRequest) -> Value`.
  - The body always carries `"store": false`, `"tools"` from `catalog::web_search_tools("openai", model)` (`[{"type": "web_search"}]`, compared with providers.json by the test), `instructions` and `max_output_tokens`.
  - The whole history is resent, with assistant turns as plain strings.
  - PDFs become `input_file` data URLs and images become `input_image` data URLs.

- [ ] **Step 1: Write the tests**

Create `windows/src-tauri/src/ai/openai.rs` with only:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use crate::ai::provider::{Finish, Message, Timeouts};
    use crate::ai::testkit::{self, FakeServer};

    fn endpoint(base: &str) -> Endpoint {
        Endpoint {
            provider: "openai".into(),
            name: "OpenAI".into(),
            base_url: base.into(),
            key: Some("sk-test".into()),
            placement: Placement::Cloud,
            timeouts: Timeouts::for_placement(Placement::Cloud),
        }
    }

    fn request() -> ChatRequest {
        ChatRequest {
            model: "gpt-6.1-sol".into(),
            system: "sys".into(),
            messages: vec![
                Message { role: Role::User, parts: vec![Part::Text("first".into())] },
                Message { role: Role::Assistant, parts: vec![Part::Text("answer".into())] },
                Message {
                    role: Role::User,
                    parts: vec![
                        Part::Pdf { name: "a.pdf".into(), base64: "JVBERi0=".into() },
                        Part::Image { name: "c.png".into(), mime: "image/png".into(), base64: "AA==".into() },
                        Part::Text("and these?".into()),
                    ],
                },
            ],
            tools: vec![],
            response_format: None,
            max_tokens: 1234,
        }
    }

    #[tokio::test]
    async fn every_request_sends_store_false_and_the_whole_history() {
        let fake = FakeServer::start(&[]);
        let p = OpenAI::new(endpoint(&fake.base));
        let mut cites = Vec::new();
        let agg = p
            .stream(&request(), &mut |c| {
                if let ChatChunk::Citation { url, title } = c {
                    cites.push((url, title));
                }
            })
            .await
            .unwrap();
        assert_eq!(agg.text, "Cats sleep a lot.");
        assert_eq!(agg.finish, Some(Finish::Stop));
        assert_eq!(cites, [("https://example.com/cats".to_string(), "Cat sleep facts".to_string())]);

        let log = fake.requests();
        let body = &log.iter().find(|r| r["path"] == "/v1/responses").unwrap()["body"];
        assert_eq!(body["store"], false);
        assert!(body.get("previous_response_id").is_none());
        // The tool is exactly what providers.json says.
        assert_eq!(body["tools"][0], testkit::load_json("providers.json")["webSearch"]["openai"]);
        assert_eq!(body["input"].as_array().unwrap().len(), 3);
        assert_eq!(body["input"][1], json!({ "role": "assistant", "content": "answer" }));
        let last = &body["input"][2]["content"];
        assert_eq!(last[0]["type"], "input_file");
        assert_eq!(last[0]["file_data"], "data:application/pdf;base64,JVBERi0=");
        assert_eq!(last[2]["image_url"], "data:image/png;base64,AA==");
    }

    #[tokio::test]
    async fn refusal_billing_and_overload() {
        let fake = FakeServer::start(&["--fail", "refuse"]);
        let agg = OpenAI::new(endpoint(&fake.base)).stream(&request(), &mut |_| {}).await.unwrap();
        assert_eq!(agg.refusal.as_deref(), Some("I can't help with that."));

        let fake = FakeServer::start(&["--fail", "billing"]);
        let err = OpenAI::new(endpoint(&fake.base)).stream(&request(), &mut |_| {}).await.unwrap_err();
        assert_eq!((err.kind, err.code.as_deref()), (ErrorKind::Billing, Some("insufficient_quota")));

        let fake = FakeServer::start(&["--fail", "overloaded"]);
        let err = OpenAI::new(endpoint(&fake.base)).stream(&request(), &mut |_| {}).await.unwrap_err();
        assert_eq!((err.kind, err.retry_after), (ErrorKind::Overloaded, Some(7)));
    }
}
```

Add `pub mod openai;` to `ai/mod.rs`, below `pub mod errors;`.

Run: `cargo test -p notchmeow ai::openai::`
Expected: FAIL to compile: `cannot find type 'OpenAI' in this scope`.

- [ ] **Step 2: Write the provider**

Put this above the tests in `openai.rs`:

```rust
// OpenAI through the Responses API (`POST /v1/responses`, streaming): hosted web
// search with clickable `url_citation` sources, PDFs as `input_file`, images as
// `input_image`. Every request sends `store: false` and the whole conversation,
// never `previous_response_id`, so OpenAI keeps no conversation state (spec §5).

use std::time::Duration;

use serde_json::{json, Value};

use crate::ai::catalog;
use crate::ai::errors;
use crate::ai::provider::{
    file_label, file_text, http_client as client, AiError, Aggregate, BoxFuture, ChatChunk, ChatRequest, Endpoint,
    ErrorKind, ModelInfo, ModelProvider, Part, Placement, Role,
};
use crate::ai::sse::{self, Format};

pub struct OpenAI {
    pub endpoint: Endpoint,
}

impl OpenAI {
    pub fn new(endpoint: Endpoint) -> Self {
        OpenAI { endpoint }
    }

    fn authed(&self, req: reqwest::RequestBuilder) -> reqwest::RequestBuilder {
        req.bearer_auth(self.endpoint.key.clone().unwrap_or_default())
    }

    pub fn body(request: &ChatRequest) -> Value {
        let input: Vec<Value> = request
            .messages
            .iter()
            .map(|m| {
                if m.role == Role::Assistant {
                    return json!({ "role": "assistant", "content": m.plain_text() });
                }
                let mut content = Vec::new();
                for p in &m.parts {
                    match p {
                        Part::Text(t) => content.push(json!({ "type": "input_text", "text": t })),
                        Part::FileText { name, text } => {
                            content.push(json!({ "type": "input_text", "text": file_text(name, text) }))
                        }
                        Part::Pdf { name, base64 } => content.push(json!({
                            "type": "input_file",
                            "filename": name,
                            "file_data": format!("data:application/pdf;base64,{base64}"),
                        })),
                        Part::Image { name, mime, base64 } => {
                            content.push(json!({ "type": "input_text", "text": file_label(name) }));
                            content.push(json!({ "type": "input_image", "image_url": format!("data:{mime};base64,{base64}") }));
                        }
                    }
                }
                json!({ "role": "user", "content": content })
            })
            .collect();
        json!({
            "model": request.model,
            "instructions": request.system,
            "input": input,
            "tools": catalog::web_search_tools("openai", &request.model),
            "stream": true,
            "store": false,
            "max_output_tokens": request.max_tokens,
        })
    }
}

impl ModelProvider for OpenAI {
    fn id(&self) -> &str {
        "openai"
    }

    fn display_name(&self) -> &str {
        &self.endpoint.name
    }

    fn placement(&self) -> Placement {
        Placement::Cloud
    }

    fn list_models(&self) -> BoxFuture<'_, Result<Vec<ModelInfo>, AiError>> {
        Box::pin(async move {
            let client = client(&self.endpoint, Some(Duration::from_secs(10)));
            let url = format!("{}/v1/models", self.endpoint.base_url.trim_end_matches('/'));
            let response = self.authed(client.get(url)).send().await.map_err(|e| errors::from_transport(&e))?;
            if !response.status().is_success() {
                return Err(errors::from_response(response).await);
            }
            let body: Value = response.json().await.map_err(|_| AiError::new(ErrorKind::Server))?;
            let models = body["data"]
                .as_array()
                .into_iter()
                .flatten()
                .filter_map(|m| m["id"].as_str())
                .map(|id| ModelInfo { capabilities: catalog::cloud_capabilities(), ..ModelInfo::named(id) })
                .collect();
            Ok(catalog::filter_models("openai", models))
        })
    }

    fn stream<'a>(
        &'a self,
        request: &'a ChatRequest,
        sink: &'a mut (dyn FnMut(ChatChunk) + Send),
    ) -> BoxFuture<'a, Result<Aggregate, AiError>> {
        Box::pin(async move {
            let client = client(&self.endpoint, None);
            let url = format!("{}/v1/responses", self.endpoint.base_url.trim_end_matches('/'));
            let req = self.authed(client.post(url)).json(&Self::body(request));
            let t = self.endpoint.timeouts;
            sse::stream_request(req, Format::OpenAIResponses, t.first_token, t.idle, sink).await
        })
    }
}
```

- [ ] **Step 3: Run the tests**

Run: `cargo test -p notchmeow ai::openai::`
Expected: `test result: ok. 2 passed; 0 failed`. The fake server's request log shows `"store": false` and no `previous_response_id`.

- [ ] **Step 4: Commit**

```bash
git add windows/src-tauri/src/ai
git commit -m "feat(ai): OpenAI Responses provider with store:false and cited web search

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---
### Task 11: Settings: per-feature choices, Preferred cloud, and the old model field

**Files:**
- Modify: `windows/src-tauri/src/settings.rs` (whole file shown below)
- Modify: `windows/src-tauri/src/lib.rs:244` (`chat_send` reads the Claude model from the AI settings) and `save_settings` (it cleans what the webview sends)
- Modify: `windows/src/core/state.ts:84-109` (`Settings.ai` replaces `Settings.model`)
- Modify: `windows/src/settings/main.ts:233-242` (the current Claude model menu reads and writes `settings.ai.cloudModels.anthropic`; Task 15 replaces the section)

**Interfaces:**
- **Consumes:** `router::{Choice, ModelRef}`.
- **Produces:**
  - **Rust:**
    - `settings::AiSettings`: `chat: Choice`, `files: Choice`, `preferred_cloud: String`, `cloud_models` and `local_models` (both `BTreeMap<String,String>`), `last_used_local: Option<ModelRef>`, `custom_server: Option<String>`. It derives `PartialEq` and serializes as camelCase JSON.
    - `Settings.ai`.
    - `Settings.model: Option<String>`: read from older files only, never written.
    - `settings::migrate(Settings) -> Settings`, which `load()` applies.
    - `settings::sanitized(Settings) -> Settings`, which `load()` and `save_settings` apply: the added server's URL loses any `user:pass@`, query or fragment (`discovery::clean_server_url`), and a URL that isn't one is dropped. settings.json is plain text and the webview sees it; the server's key lives in the keychain.
  - **TypeScript:** `ModelChoice`, `AiSettings`, `DEFAULT_AI` and `Settings.ai`.

- [ ] **Step 1: Write the migration and clean-up tests**

Append to `windows/src-tauri/src/settings.rs`:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_settings_file_from_0_1_1_keeps_its_claude_model() {
        let old = r#"{"soundEnabled":true,"soundVolume":0.12,"autoCloseInterval":15,"absenceInterval":180,
            "activeIntegrations":["integration_github"],"screen":"primary","autostart":false,
            "hooksInstalled":true,"model":"claude-opus-5"}"#;
        let s = migrate(serde_json::from_str(old).unwrap());
        assert_eq!(s.ai.cloud_models.get("anthropic").map(String::as_str), Some("claude-opus-5"));
        assert_eq!(s.ai.chat, Choice::default());
        assert!(s.hooks_installed);
        let written = serde_json::to_value(&s).unwrap();
        assert!(written.get("model").is_none(), "the old field is never written back");
        assert_eq!(written["ai"]["chat"], "auto");
        assert_eq!(written["ai"]["files"], "auto");
        assert_eq!(written["ai"]["preferredCloud"], "anthropic");
        assert_eq!(written["ai"]["lastUsedLocal"], serde_json::Value::Null);
    }

    #[test]
    fn a_server_url_loses_its_password_before_it_is_stored_or_shown() {
        let mut s = Settings::default();
        s.ai.custom_server = Some("http://me:hunter2@studio-pc:11434/v1/?key=abc".into());
        let clean = sanitized(s);
        assert_eq!(clean.ai.custom_server.as_deref(), Some("http://studio-pc:11434"));
        let json = serde_json::to_string(&clean).unwrap();
        assert!(!json.contains("hunter2") && !json.contains("abc"), "{json}");

        // Not a URL at all: nothing is kept.
        let mut junk = Settings::default();
        junk.ai.custom_server = Some("not a url".into());
        assert_eq!(sanitized(junk).ai.custom_server, None);
    }

    #[test]
    fn a_settings_file_written_by_hand_is_cleaned_the_way_load_does() {
        let raw = r#"{"soundEnabled":true,"soundVolume":0.12,"autoCloseInterval":15,"absenceInterval":180,
            "activeIntegrations":[],"screen":"primary","autostart":false,"hooksInstalled":false,
            "model":"claude-opus-5","ai":{"customServer":"http://u:p4ss@10.0.0.7:1234/v1"}}"#;
        let s = sanitized(migrate(serde_json::from_str(raw).unwrap()));
        assert_eq!(s.ai.custom_server.as_deref(), Some("http://10.0.0.7:1234"));
        assert_eq!(s.ai.cloud_models.get("anthropic").map(String::as_str), Some("claude-opus-5"));
    }

    #[test]
    fn a_chosen_model_round_trips() {
        let mut s = Settings::default();
        s.ai.files = Choice::Explicit(ModelRef { provider: "ollama".into(), model: "qwen3.5:2b".into() });
        let back: Settings = serde_json::from_value(serde_json::to_value(&s).unwrap()).unwrap();
        assert_eq!(back.ai, s.ai);
    }
}
```

Run: `cargo test -p notchmeow settings::`
Expected: FAIL to compile: `cannot find function 'migrate' in this scope` and `no field 'ai' on type 'Settings'`.

- [ ] **Step 2: Add the AI settings and the one-time migration**

Replace everything in `settings.rs` above the test module with:

```rust
// Preferences, stored as plain JSON in settings.json under platform::config_dir().
// No secret ever lands here — API keys live in the OS keychain (see secrets.rs).

use std::collections::BTreeMap;
use std::path::PathBuf;

use serde::{Deserialize, Serialize};

use crate::ai::router::{Choice, ModelRef};

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Settings {
    pub sound_enabled: bool,
    pub sound_volume: f64,
    pub auto_close_interval: f64,
    pub absence_interval: f64,
    pub active_integrations: Vec<String>,
    /// "primary" = the main display, "cursor" = whichever display the mouse is on.
    pub screen: String,
    pub autostart: bool,
    pub hooks_installed: bool,
    /// Up to 0.1.1 the chat had a single Claude model here. `load` moves it into
    /// `ai.cloud_models["anthropic"]`; it is never written back.
    #[serde(default, skip_serializing)]
    pub model: Option<String>,
    /// Which models answer. Defaulted so a settings.json from an older build still loads.
    #[serde(default)]
    pub ai: AiSettings,
}

/// The AI part of settings.json (spec §4). Keys are never here: they live in the
/// OS keychain (secrets.rs).
#[derive(Debug, Clone, PartialEq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase", default)]
pub struct AiSettings {
    /// Which model answers in the chat: "auto" or {provider, model}.
    pub chat: Choice,
    /// Which model answers questions about a dropped file.
    pub files: Choice,
    /// "anthropic" or "openai": the cloud Auto tries first.
    pub preferred_cloud: String,
    /// Remembered model per cloud provider, e.g. {"anthropic": "claude-opus-5"}.
    pub cloud_models: BTreeMap<String, String>,
    /// Last-used model per local server, e.g. {"ollama": "qwen3.5:2b"}.
    pub local_models: BTreeMap<String, String>,
    /// The local model Auto uses first when there is no cloud key.
    pub last_used_local: Option<ModelRef>,
    /// The server added with "Add server…", e.g. "http://studio-pc:11434".
    pub custom_server: Option<String>,
}

impl Default for AiSettings {
    fn default() -> Self {
        AiSettings {
            chat: Choice::default(),
            files: Choice::default(),
            preferred_cloud: "anthropic".into(),
            cloud_models: BTreeMap::new(),
            local_models: BTreeMap::new(),
            last_used_local: None,
            custom_server: None,
        }
    }
}

impl Default for Settings {
    fn default() -> Self {
        Self {
            sound_enabled: true,
            sound_volume: 0.12,
            auto_close_interval: 15.0,
            absence_interval: 180.0,
            active_integrations: vec![
                "integration_resend".into(),
                "integration_n8n".into(),
                "integration_vercel".into(),
                "integration_github".into(),
            ],
            screen: "primary".into(),
            autostart: false,
            hooks_installed: false,
            model: None,
            ai: AiSettings::default(),
        }
    }
}

pub use crate::platform::{config_dir, local_dir};

pub fn hook_exe_path() -> PathBuf {
    local_dir().join("bin").join(crate::platform::HOOK_EXE)
}

fn settings_path() -> PathBuf {
    config_dir().join("settings.json")
}

pub fn load() -> Settings {
    match std::fs::read(settings_path()) {
        Ok(bytes) => sanitized(migrate(serde_json::from_slice(&bytes).unwrap_or_default())),
        Err(_) => Settings::default(),
    }
}

/// What may be kept and shown: the server the user added loses a typed `user:pass@` (and any
/// query), because settings.json is plain text and the webview sees it. Applied on load and
/// to everything the webview saves; the server's key lives in the keychain, never in a URL.
pub fn sanitized(mut settings: Settings) -> Settings {
    settings.ai.custom_server = settings.ai.custom_server.as_deref().and_then(crate::ai::discovery::clean_server_url);
    settings
}

/// Moves the pre-AI `model` (a Claude model id) into the AI settings, once.
pub fn migrate(mut settings: Settings) -> Settings {
    if let Some(model) = settings.model.take() {
        settings.ai.cloud_models.entry("anthropic".into()).or_insert(model);
    }
    settings
}

pub fn save(settings: &Settings) -> std::io::Result<()> {
    let dir = config_dir();
    crate::platform::ensure_private_dir(&dir)?;
    let json = serde_json::to_vec_pretty(settings)
        .map_err(|e| std::io::Error::new(std::io::ErrorKind::InvalidData, e))?;
    std::fs::write(settings_path(), json)
}
```

`settings.rs` no longer refers to `crate::claude::DEFAULT_MODEL`. In `windows/src-tauri/src/lib.rs`, `chat_send` now reads the Claude model from its new home. Replace its first line:

```rust
    let model = shared.settings.lock().unwrap().ai.cloud_models.get("anthropic").cloned()
        .unwrap_or_else(|| claude::DEFAULT_MODEL.to_string());
```

`save_settings` stores, saves and shares whatever the webview sends, so it cleans it first. In `windows/src-tauri/src/lib.rs`, make this the first statement of `save_settings`:

```rust
    // What the webview sends is cleaned before it is stored, saved or shared: a server URL
    // loses any `user:pass@` (see `settings::sanitized`).
    let settings = settings::sanitized(settings);
```

- [ ] **Step 3: Run the tests**

Run: `cargo test -p notchmeow settings::`
Expected: `test result: ok. 4 passed; 0 failed`.
- `a_server_url_loses_its_password_before_it_is_stored_or_shown` and `a_settings_file_written_by_hand_is_cleaned_the_way_load_does` cover `sanitized`, which `load()` and `save_settings` both call.

Run: `cargo test --workspace`
Expected: every `test result:` line says `ok`.

- [ ] **Step 4: The same shape in TypeScript**

In `windows/src/core/state.ts`, replace the `Settings` interface, from `export interface Settings {` to its closing `}`, with:

```ts
/** "auto", or one model on one provider. */
export type ModelChoice = "auto" | { provider: string; model: string };

/** The AI part of settings.json — mirrors settings::AiSettings in Rust. */
export interface AiSettings {
  chat: ModelChoice;
  files: ModelChoice;
  /** Which cloud Auto tries first. */
  preferredCloud: "anthropic" | "openai";
  /** Remembered model per cloud provider. */
  cloudModels: Record<string, string>;
  /** Last-used model per local server. */
  localModels: Record<string, string>;
  lastUsedLocal: { provider: string; model: string } | null;
  /** The server added with "Add server…". */
  customServer: string | null;
}

export const DEFAULT_AI: AiSettings = {
  chat: "auto",
  files: "auto",
  preferredCloud: "anthropic",
  cloudModels: {},
  localModels: {},
  lastUsedLocal: null,
  customServer: null,
};

export interface Settings {
  soundEnabled: boolean;
  soundVolume: number;
  autoCloseInterval: number;
  absenceInterval: number;
  activeIntegrations: string[];
  screen: "primary" | "cursor";
  autostart: boolean;
  hooksInstalled: boolean;
  /** Which models answer (settings::AiSettings). */
  ai: AiSettings;
}
```

and in `DEFAULT_SETTINGS`, replace `model: "claude-opus-5",` with `ai: { ...DEFAULT_AI },`.

In `windows/src/settings/main.ts`, inside `apiSection`, replace the block from `const model = h("select", {}) as HTMLSelectElement;` through the end of its `change` listener with:

```ts
  // The Claude model now lives in the AI settings (settings.ai.cloudModels).
  const currentModel = settings.ai.cloudModels.anthropic ?? "claude-sonnet-5-5";
  const model = h("select", {}) as HTMLSelectElement;
  for (const [id, label] of MODELS) model.append(h("option", { value: id, text: label }));
  if (!MODELS.some(([id]) => id === currentModel)) {
    model.append(h("option", { value: currentModel, text: currentModel }));
  }
  model.value = currentModel;
  model.addEventListener("change", () => {
    settings.ai = { ...settings.ai, cloudModels: { ...settings.ai.cloudModels, anthropic: model.value } };
    void save();
  });
```

Run: `cd windows && npx tsc --noEmit`
Expected: no output, exit 0.

- [ ] **Step 5: Commit**

```bash
git add windows/src-tauri/src/settings.rs windows/src-tauri/src/lib.rs windows/src/core/state.ts windows/src/settings/main.ts
git commit -m "feat(ai): per-feature model choices in settings, keeping the old Claude model

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 12: One turn, end to end (route, stream, fall back once, history)

**Files:**
- Modify: `windows/src-tauri/src/log.rs` (record lines in tests for the leak test)
- Create: `windows/src-tauri/src/ai/session.rs`
- Modify: `windows/src-tauri/src/ai/mod.rs` (add `pub mod session;`)

**Interfaces:**
- **Consumes:** every earlier module, plus `settings::AiSettings` and `log::CAPTURED`.
- **Produces:**
  - `SYSTEM_PROMPT_SEARCH` (Claude and OpenAI, which search the web) and `SYSTEM_PROMPT_PLAIN` (every other model);
  - `Feature::{Chat, Files}`, serialized as `"chat"` / `"files"`, and `AiSettings::choice(Feature)`;
  - `FileRef { name, path }`; `Turn { role, text, files, prepared }` with `Turn::user(text, files)` and `Turn::assistant(text)`. `prepared` caches what `attachments::prepare` made of the message's files for each reader (`Arc`, so cloning a turn stays cheap), and `PreparedFiles`;
  - `Conversation { turns, generation }` with `reset()`;
  - `AiEvent::{Started{provider,model,placement,caption,fallback,waking}, Delta{text}, Citation{url,title}, Notice{text}, Done{text,interrupted,cancelled}, Error{kind,message,action,retry_after}, Problem{kind,message,action}, EmptyState}`, which serializes as `{"type": "started", …}` with camelCase fields;
  - the two kinds of failure, kept apart on purpose:
    - `AiEvent::Error.kind` is an `ErrorKind`, one of the contract's 12, serialized as in `ErrorKind::as_str`. It means a provider or the network failed, and the router has already had its say;
    - `AiEvent::Problem.kind` is a `ProblemKind`: `CantSee`, `ScannedPdf`, `Heic`, `Rejected`, `Unreadable`, `MissingModel`, `Outdated` or `EmptyReply`. These are the island's own notices, **not** contract error kinds: they never reach the router and the island shows them like errors (a note and the error sound). Nothing may treat one as if a provider sent it;
  - `TurnRequest { feature, text, files, regenerate }`;
  - `Env { settings, keys, servers, probes, cloud_override, models, timeouts }`;
  - `ready_list(&Env)`, `route_input(&Env, Feature)`;
  - `Target { endpoint, model, model_name, vision, context_tokens }` with `who()` and `caption()`;
  - `make_provider(Endpoint) -> Box<dyn ModelProvider>`;
  - `async run_turn(&mut Env, &Mutex<Conversation>, TurnRequest, &Notify, &mut (dyn FnMut(AiEvent) + Send))`;
  - `Resolution { empty, auto, provider, model, placement, model_name, reader, fallback }` and `resolve(&Env, Feature) -> Resolution`, which makes no network call.

  `run_turn` follows these rules:
  - The router decides; a turn falls back at most once.
  - When nothing was received, the user's message is removed again. A retry (`regenerate`) pushed no message, so a failed retry removes nothing: the question it answers again stays.
  - A partial reply is kept and marked as interrupted.
  - A reply with no text at all (a thinking model that used every token inside `<think>`, or a model that just said nothing) is an `EmptyReply` problem: it never enters the history, no `Done` follows (so no finish sound), and the user's message is taken back. When it stopped at the token limit the words are "The model ran out of room before answering. Try again, or pick a model without thinking mode.", with a Choose model button.
  - A reply with text that stopped at the token limit is kept, and a notice says "The answer was cut off."
  - A reply that arrives after a reset is dropped.
  - A local server found down is marked off, so the next turn checks again.
  - Each message's files are prepared (OCR, page rendering, base64) once per reader and reused by later messages. A file from an earlier message that can no longer be read (the inbox sweep removed it) becomes the line "File: <name> (no longer available)" instead of blocking the new question; the newest message's own file is reported as `Unreadable`.
  - Each attempt sizes the request for its own model: the history is trimmed by the contract's rule (`budget::messages_to_drop`, local and network only) and the reply length is `catalog::max_output_tokens(placement)`. A fallback to a local model is trimmed and capped for that model, not for the cloud one it replaced.

- [ ] **Step 1: Let tests read the log**

In `windows/src-tauri/src/log.rs`, add above `pub fn line`:

```rust
/// Every line, in tests: the leak test checks that no prompt or file reaches the log.
#[cfg(test)]
pub static CAPTURED: std::sync::Mutex<Vec<String>> = std::sync::Mutex::new(Vec::new());
```

and make the first statement of `line`:

```rust
    #[cfg(test)]
    CAPTURED.lock().unwrap().push(message.as_ref().to_string());
```

- [ ] **Step 2: Write the session tests**

Create `windows/src-tauri/src/ai/session.rs` with only:

```rust
#[cfg(test)]
mod tests {
    use super::*;
    use crate::ai::provider::Capabilities;
    use crate::ai::testkit::{self, FakeServer};

    fn running(provider: &str, base: &str, placement: Placement) -> Server {
        Server {
            provider: provider.into(),
            name: catalog::get(provider).map(|d| d.name).unwrap_or("x").into(),
            base_url: base.into(),
            host: "127.0.0.1".into(),
            placement,
            status: ServerStatus::Running,
            models: vec![ModelInfo::named("llama3.2")],
            unencrypted: false,
        }
    }

    fn env(keys: &[&str], cloud: Option<&FakeServer>, local: Option<&FakeServer>) -> Env {
        Env {
            settings: AiSettings::default(),
            keys: keys.iter().map(|k| (k.to_string(), "test-key".to_string())).collect(),
            servers: local.map(|f| vec![running("ollama", &f.base, Placement::Local)]).unwrap_or_default(),
            probes: Vec::new(),
            cloud_override: cloud.map(|f| f.base.clone()),
            models: HashMap::new(),
            timeouts: Some(Timeouts {
                connect: std::time::Duration::from_secs(2),
                first_token: std::time::Duration::from_secs(5),
                idle: std::time::Duration::from_secs(5),
            }),
        }
    }

    fn ask(text: &str) -> TurnRequest {
        TurnRequest { feature: Feature::Chat, text: text.into(), files: vec![], regenerate: false }
    }

    async fn turn(env: &mut Env, conv: &Mutex<Conversation>, req: TurnRequest) -> Vec<AiEvent> {
        let cancel = Notify::new();
        let mut events = Vec::new();
        run_turn(env, conv, req, &cancel, &mut |e| events.push(e)).await;
        events
    }

    fn done_text(events: &[AiEvent]) -> Option<String> {
        events.iter().find_map(|e| match e {
            AiEvent::Done { text, .. } => Some(text.clone()),
            _ => None,
        })
    }

    /// An Ollama-like server whose one reply streams these chat-completions text deltas and
    /// then `finish_reason`. For the replies the fake model server can't produce.
    fn canned_reply(deltas: &[&str], finish: &str) -> Env {
        let mut body = String::new();
        for d in deltas {
            let event = serde_json::json!({ "choices": [{ "index": 0, "delta": { "content": d } }] });
            body.push_str(&format!("data: {event}\n\n"));
        }
        let last = serde_json::json!({ "choices": [{ "index": 0, "delta": {}, "finish_reason": finish }] });
        body.push_str(&format!("data: {last}\n\ndata: [DONE]\n\n"));
        let base = testkit::canned_server(200, "text/event-stream", &body);
        let mut env = env(&[], None, None);
        env.servers = vec![running("ollama", &base, Placement::Local)];
        env
    }

    #[tokio::test]
    async fn auto_with_a_key_answers_from_the_cloud_and_streams() {
        let cloud = FakeServer::start(&[]);
        let mut env = env(&["anthropic"], Some(&cloud), None);
        let conv = Mutex::new(Conversation::default());
        let events = turn(&mut env, &conv, ask("hi")).await;
        assert!(matches!(&events[0], AiEvent::Started { caption, fallback: false, .. } if caption == "cloud · claude-sonnet-5-5"));
        assert!(events.iter().any(|e| matches!(e, AiEvent::Delta { .. })));
        assert!(events.iter().any(|e| matches!(e, AiEvent::Citation { url, .. } if url == "https://example.com/cats")));
        assert_eq!(done_text(&events).as_deref(), Some("Cats sleep a lot."));
        assert_eq!(conv.lock().unwrap().turns.len(), 2);
    }

    #[tokio::test]
    async fn busy_cloud_falls_back_to_local_once_with_the_spec_message() {
        let cloud = FakeServer::start(&["--fail", "429"]);
        let local = FakeServer::start(&[]);
        let mut env = env(&["anthropic"], Some(&cloud), Some(&local));
        let conv = Mutex::new(Conversation::default());
        let events = turn(&mut env, &conv, ask("hi")).await;
        assert!(events.contains(&AiEvent::Notice { text: "Claude's busy right now, so Llama answered instead.".into() }));
        assert!(events.iter().any(|e| matches!(e, AiEvent::Started { caption, fallback: true, .. } if caption == "local · llama3.2")));
        assert!(done_text(&events).unwrap().starts_with("## Answer"));
        assert_eq!(env.settings.last_used_local, Some(ModelRef { provider: "ollama".into(), model: "llama3.2".into() }));
    }

    #[tokio::test]
    async fn rejected_key_never_falls_back() {
        let cloud = FakeServer::start(&["--fail", "401"]);
        let local = FakeServer::start(&[]);
        let mut env = env(&["anthropic"], Some(&cloud), Some(&local));
        let conv = Mutex::new(Conversation::default());
        let events = turn(&mut env, &conv, ask("hi")).await;
        assert_eq!(
            events.last().unwrap(),
            &AiEvent::Error { kind: ErrorKind::Auth, message: "Your Anthropic key was rejected.".into(), action: Some(Action::OpenSettings), retry_after: None }
        );
        assert!(local.requests().is_empty(), "the local model must not be asked");
        assert!(conv.lock().unwrap().turns.is_empty(), "a failed message leaves no half turn");
    }

    #[tokio::test]
    async fn busy_without_local_counts_down() {
        let cloud = FakeServer::start(&["--fail", "429"]);
        let mut env = env(&["anthropic"], Some(&cloud), None);
        let conv = Mutex::new(Conversation::default());
        let events = turn(&mut env, &conv, ask("hi")).await;
        assert!(matches!(events.last().unwrap(), AiEvent::Error { kind: ErrorKind::RateLimited, retry_after: Some(2), message, .. }
            if message == "Claude is busy. Trying again in 2 s."));
    }

    #[tokio::test]
    async fn billing_never_falls_back() {
        let cloud = FakeServer::start(&["--fail", "billing"]);
        let local = FakeServer::start(&[]);
        let mut env = env(&["openai"], Some(&cloud), Some(&local));
        let conv = Mutex::new(Conversation::default());
        let events = turn(&mut env, &conv, ask("hi")).await;
        assert!(matches!(events.last().unwrap(), AiEvent::Error { kind: ErrorKind::Billing, message, action: Some(Action::OpenBilling { .. }), .. }
            if message == "Your OpenAI credit ran out."));
    }

    #[tokio::test]
    async fn no_key_and_nothing_local_is_the_empty_state() {
        let mut env = env(&[], None, None);
        let conv = Mutex::new(Conversation::default());
        assert_eq!(turn(&mut env, &conv, ask("hi")).await, vec![AiEvent::EmptyState]);
        assert!(conv.lock().unwrap().turns.is_empty());
    }

    #[tokio::test]
    async fn no_key_uses_the_local_model() {
        let local = FakeServer::start(&[]);
        let mut env = env(&[], None, Some(&local));
        let conv = Mutex::new(Conversation::default());
        let events = turn(&mut env, &conv, ask("hi")).await;
        assert!(matches!(&events[0], AiEvent::Started { placement: Placement::Local, .. }));
        assert!(done_text(&events).is_some());
    }

    #[tokio::test]
    async fn explicit_local_choice_beats_a_cloud_key() {
        let cloud = FakeServer::start(&[]);
        let local = FakeServer::start(&[]);
        let mut env = env(&["anthropic"], Some(&cloud), Some(&local));
        env.settings.chat = Choice::Explicit(ModelRef { provider: "ollama".into(), model: "llama3.2".into() });
        let conv = Mutex::new(Conversation::default());
        let events = turn(&mut env, &conv, ask("hi")).await;
        assert!(matches!(&events[0], AiEvent::Started { provider, .. } if provider == "ollama"));
        assert!(cloud.requests().is_empty());
    }

    #[tokio::test]
    async fn a_cut_stream_keeps_the_partial_reply() {
        let local = FakeServer::start(&["--fail", "cut"]);
        let mut env = env(&[], None, Some(&local));
        let conv = Mutex::new(Conversation::default());
        let events = turn(&mut env, &conv, ask("hi")).await;
        assert_eq!(
            events.last().unwrap(),
            &AiEvent::Done { text: "Hello from ".into(), interrupted: true, cancelled: false }
        );
        // The partial reply stays in the history, so "Continue" makes sense.
        assert_eq!(conv.lock().unwrap().turns[1].text, "Hello from ");
    }

    #[tokio::test]
    async fn a_stream_cut_before_any_text_is_a_plain_failure() {
        // The cut Anthropic stream stops before its first text delta.
        let cloud = FakeServer::start(&["--fail", "cut"]);
        let mut env = env(&["anthropic"], Some(&cloud), None);
        let conv = Mutex::new(Conversation::default());
        let events = turn(&mut env, &conv, ask("hi")).await;
        assert!(matches!(events.last().unwrap(), AiEvent::Error { kind: ErrorKind::Server, message, .. }
            if message == "Claude had a problem. Try again in a moment."));
    }

    #[tokio::test]
    async fn stop_cancels_the_stream() {
        let local = FakeServer::start(&["--fail", "slow-first-token", "--delay", "3"]);
        let mut env = env(&[], None, Some(&local));
        let conv = Mutex::new(Conversation::default());
        let cancel = std::sync::Arc::new(Notify::new());
        let stopper = cancel.clone();
        tokio::spawn(async move {
            tokio::time::sleep(std::time::Duration::from_millis(300)).await;
            stopper.notify_one();
        });
        let mut events = Vec::new();
        let started = std::time::Instant::now();
        run_turn(&mut env, &conv, ask("hi"), &cancel, &mut |e| events.push(e)).await;
        assert!(started.elapsed() < std::time::Duration::from_secs(2));
        assert!(matches!(events.last().unwrap(), AiEvent::Done { cancelled: true, .. }));
        assert!(conv.lock().unwrap().turns.is_empty());
    }

    #[tokio::test]
    async fn a_file_joins_the_message_it_was_dropped_on() {
        // Regression: files used to ride along with a conversation's first message only.
        let local = FakeServer::start(&[]);
        let files = testkit::make_attachments();
        let mut env = env(&[], None, Some(&local));
        let conv = Mutex::new(Conversation::default());
        turn(&mut env, &conv, ask("hello")).await;
        let second = TurnRequest {
            feature: Feature::Files,
            text: "what does it say?".into(),
            files: vec![FileRef { name: "note.txt".into(), path: files.path().join("note.txt") }],
            regenerate: false,
        };
        turn(&mut env, &conv, second).await;
        let chats: Vec<_> = local.requests().into_iter().filter(|r| r["path"] == "/v1/chat/completions").collect();
        let messages = chats[1]["body"]["messages"].as_array().unwrap();
        let last = messages.last().unwrap()["content"].as_str().unwrap();
        assert!(last.contains("Hello Shrimpy") && last.contains("what does it say?"), "{last}");
        assert!(!messages[1]["content"].as_str().unwrap().contains("Hello Shrimpy"));
    }

    #[tokio::test]
    async fn retry_answers_the_last_message_again() {
        let local = FakeServer::start(&[]);
        let mut env = env(&[], None, Some(&local));
        let conv = Mutex::new(Conversation::default());
        turn(&mut env, &conv, ask("hi")).await;
        let events = turn(&mut env, &conv, TurnRequest { regenerate: true, ..ask("") }).await;
        assert!(done_text(&events).is_some());
        let c = conv.lock().unwrap();
        assert_eq!(c.turns.len(), 2);
        assert_eq!(c.turns[0].text, "hi");
    }

    #[tokio::test]
    async fn a_blind_model_and_an_image_say_so() {
        let local = FakeServer::start(&[]);
        let files = testkit::make_attachments();
        let mut env = env(&[], None, Some(&local));
        let conv = Mutex::new(Conversation::default());
        let req = TurnRequest {
            feature: Feature::Files,
            text: "what is it?".into(),
            files: vec![FileRef { name: "photo.png".into(), path: files.path().join("photo.png") }],
            regenerate: false,
        };
        let events = turn(&mut env, &conv, req).await;
        if cfg!(windows) {
            // Windows reads the (blank) image with OCR, finds nothing, and says the same.
            assert!(matches!(events.last().unwrap(), AiEvent::Problem { kind: ProblemKind::CantSee, .. }));
        } else {
            assert_eq!(
                events.last().unwrap(),
                &AiEvent::Problem { kind: ProblemKind::CantSee, message: errors::CANT_SEE.into(), action: Some(Action::ChooseModel) }
            );
        }
    }

    #[tokio::test]
    async fn prompts_and_files_never_reach_the_log() {
        const MARKER: &str = "QUOKKAMARKER7731";
        let dir = testkit::TempDir::new("leak");
        let file = dir.path().join("secret.txt");
        std::fs::write(&file, format!("the password is {MARKER}\n")).unwrap();
        let ok = FakeServer::start(&[]);
        let failing = FakeServer::start(&["--fail", "500"]);
        for cloud in [&ok, &failing] {
            let mut env = env(&["anthropic"], Some(cloud), None);
            let conv = Mutex::new(Conversation::default());
            let req = TurnRequest {
                feature: Feature::Files,
                text: format!("tell me about {MARKER}"),
                files: vec![FileRef { name: format!("{MARKER}.txt"), path: file.clone() }],
                regenerate: false,
            };
            turn(&mut env, &conv, req).await;
        }
        let lines = log::CAPTURED.lock().unwrap().clone();
        assert!(lines.iter().any(|l| l.starts_with("ai ")), "the turns were logged");
        assert!(lines.iter().all(|l| !l.contains(MARKER)), "a prompt or file leaked into the log");
    }

    #[tokio::test]
    async fn a_server_that_quit_after_discovery_is_reported_and_forgotten() {
        let port = std::net::TcpListener::bind("127.0.0.1:0").unwrap().local_addr().unwrap().port();
        let gone = format!("http://127.0.0.1:{port}");
        let mut env = env(&[], None, None);
        env.servers = vec![running("ollama", &gone, Placement::Local)];
        let conv = Mutex::new(Conversation::default());
        let events = turn(&mut env, &conv, ask("hi")).await;
        assert_eq!(
            events.last().unwrap(),
            &AiEvent::Error {
                kind: ErrorKind::Unreachable,
                message: "Couldn't reach Ollama. Is its server on?".into(),
                action: Some(Action::OpenGuide),
                retry_after: None,
            }
        );
        assert_eq!(env.servers[0].status, ServerStatus::Off, "the next message looks again");
    }

    #[tokio::test]
    async fn a_reply_to_a_reset_conversation_is_dropped() {
        let local = FakeServer::start(&["--fail", "slow-first-token", "--delay", "1"]);
        let mut env = env(&[], None, Some(&local));
        let conv = Mutex::new(Conversation::default());
        let cancel = Notify::new();
        let mut events = Vec::new();
        let mut emit = |e| events.push(e);
        let run = run_turn(&mut env, &conv, ask("old question"), &cancel, &mut emit);
        let reset = async {
            tokio::time::sleep(std::time::Duration::from_millis(300)).await;
            conv.lock().unwrap().reset();
        };
        tokio::join!(run, reset);
        assert!(conv.lock().unwrap().turns.is_empty(), "the old reply must not land in the new conversation");
    }

    #[tokio::test]
    async fn stale_explicit_choices_say_what_happened() {
        let local = FakeServer::start(&[]);
        let mut env = env(&[], None, Some(&local));
        env.settings.chat = Choice::Explicit(ModelRef { provider: "anthropic".into(), model: "claude-opus-5".into() });
        let conv = Mutex::new(Conversation::default());
        let events = turn(&mut env, &conv, ask("hi")).await;
        assert!(matches!(events.last().unwrap(), AiEvent::Error { message, action: Some(Action::OpenSettings), .. }
            if message == "Your Anthropic key is missing."));

        env.settings.chat = Choice::Explicit(ModelRef { provider: "ollama".into(), model: "qwen3.5:2b".into() });
        let events = turn(&mut env, &conv, ask("hi")).await;
        assert!(matches!(events.last().unwrap(), AiEvent::Problem { kind: ProblemKind::MissingModel, message, action: Some(Action::ChooseModel) }
            if message == "qwen3.5:2b isn't on Ollama any more."));
        assert!(local.requests().iter().all(|r| r["path"] != "/v1/chat/completions"), "no other model answered instead");
    }

    #[tokio::test]
    async fn a_thinking_model_that_runs_out_of_tokens_says_so_and_adds_no_turn() {
        // Every token went into <think>: the visible reply is empty and the model stopped at the limit.
        let mut env = canned_reply(&["<think>\nlet me weigh this ", "for a very long time"], "length");
        let conv = Mutex::new(Conversation::default());
        let events = turn(&mut env, &conv, ask("hi")).await;
        assert!(!events.iter().any(|e| matches!(e, AiEvent::Done { .. })), "no Done, so no finish sound: {events:?}");
        assert!(!events.iter().any(|e| matches!(e, AiEvent::Delta { .. })), "the thinking is never shown");
        assert_eq!(
            events.last().unwrap(),
            &AiEvent::Problem {
                kind: ProblemKind::EmptyReply,
                message: "The model ran out of room before answering. Try again, or pick a model without thinking mode.".into(),
                action: Some(Action::ChooseModel),
            }
        );
        assert!(conv.lock().unwrap().turns.is_empty(), "no empty assistant turn, and the question is taken back");
    }

    #[tokio::test]
    async fn a_reply_cut_off_at_the_token_limit_is_kept_with_a_note() {
        let mut env = canned_reply(&["The first half of an ans"], "length");
        let conv = Mutex::new(Conversation::default());
        let events = turn(&mut env, &conv, ask("hi")).await;
        let note = events.iter().position(|e| *e == AiEvent::Notice { text: "The answer was cut off.".into() });
        let done = events.iter().position(|e| matches!(e, AiEvent::Done { .. }));
        assert!(note.is_some() && note < done, "the note comes before Done: {events:?}");
        assert_eq!(
            events.last().unwrap(),
            &AiEvent::Done { text: "The first half of an ans".into(), interrupted: false, cancelled: false }
        );
        assert_eq!(conv.lock().unwrap().turns[1].text, "The first half of an ans");
    }

    #[tokio::test]
    async fn an_unclosed_think_block_never_becomes_the_reply() {
        let mut env = canned_reply(&["Sure. <think>hm"], "length");
        let conv = Mutex::new(Conversation::default());
        let events = turn(&mut env, &conv, ask("hi")).await;
        assert_eq!(done_text(&events).as_deref(), Some("Sure. "));
        assert_eq!(conv.lock().unwrap().turns[1].text, "Sure. ");
    }

    #[tokio::test]
    async fn an_empty_reply_is_a_failure_whatever_the_finish() {
        for deltas in [&[][..], &["  \n"][..]] {
            let mut env = canned_reply(deltas, "stop");
            let conv = Mutex::new(Conversation::default());
            let events = turn(&mut env, &conv, ask("hi")).await;
            assert_eq!(
                events.last().unwrap(),
                &AiEvent::Problem {
                    kind: ProblemKind::EmptyReply,
                    message: "The model sent an empty reply. Try again.".into(),
                    action: None,
                },
                "{deltas:?}"
            );
            assert!(!events.iter().any(|e| matches!(e, AiEvent::Done { .. })));
            assert!(conv.lock().unwrap().turns.is_empty());
        }
    }

    /// `maxOutputTokens` for a placement, read from providers.json.
    fn reply_length(placement: &str) -> serde_json::Value {
        testkit::load_json("providers.json")["maxOutputTokens"][placement].clone()
    }

    #[tokio::test]
    async fn every_request_asks_for_its_placements_reply_length() {
        // A thinking model spends its <think> or reasoning tokens from this cap.
        let local = FakeServer::start(&[]);
        let mut at_home = env(&[], None, Some(&local));
        turn(&mut at_home, &Mutex::new(Conversation::default()), ask("hi")).await;
        let chat = local.requests().into_iter().find(|r| r["path"] == "/v1/chat/completions").unwrap();
        assert_eq!(chat["body"]["max_tokens"], reply_length("local"));

        let cloud = FakeServer::start(&[]);
        let mut away = env(&["anthropic", "openai"], Some(&cloud), None);
        turn(&mut away, &Mutex::new(Conversation::default()), ask("hi")).await;
        away.settings.preferred_cloud = "openai".into();
        turn(&mut away, &Mutex::new(Conversation::default()), ask("hi")).await;
        let log = cloud.requests();
        assert_eq!(log.iter().find(|r| r["path"] == "/v1/messages").unwrap()["body"]["max_tokens"], reply_length("cloud"));
        assert_eq!(log.iter().find(|r| r["path"] == "/v1/responses").unwrap()["body"]["max_output_tokens"], reply_length("cloud"));
        // A server on the network gets the local length.
        away.servers = vec![running("custom", &local.base, Placement::Network)];
        away.keys.clear();
        let events = turn(&mut away, &Mutex::new(Conversation::default()), ask("hi again")).await;
        assert!(events.iter().any(|e| matches!(e, AiEvent::Started { placement: Placement::Network, .. })), "{events:?}");
        let last = local.requests().into_iter().filter(|r| r["path"] == "/v1/chat/completions").last().unwrap();
        assert_eq!(last["body"]["max_tokens"], reply_length("network"));
    }

    #[tokio::test]
    async fn a_long_chat_on_a_small_model_drops_the_oldest_pair_and_says_so() {
        let local = FakeServer::start(&[]);
        let mut at_home = env(&[], None, Some(&local));
        let conv = Mutex::new(Conversation::default());
        conv.lock().unwrap().turns = vec![Turn::user("a".repeat(6000), vec![]), Turn::assistant("b".repeat(6000))];
        let events = turn(&mut at_home, &conv, ask("and now?")).await;
        // An unknown local context counts as 4,096 tokens: 10,752 scalars fit, and 12,000+ do not.
        assert!(events.contains(&AiEvent::Notice { text: errors::TOO_LONG.into() }), "{events:?}");
        let chat = local.requests().into_iter().find(|r| r["path"] == "/v1/chat/completions").unwrap();
        let sent = chat["body"]["messages"].as_array().unwrap();
        assert_eq!(sent.len(), 2, "the system prompt and the latest message only");
        assert_eq!(sent[1]["content"], "and now?");
        // The conversation itself keeps every turn: only what is sent was trimmed.
        assert_eq!(conv.lock().unwrap().turns.len(), 4);
    }

    #[tokio::test]
    async fn a_failed_retry_keeps_the_question_it_retries() {
        let local = FakeServer::start(&[]);
        let mut env = env(&[], None, Some(&local));
        let conv = Mutex::new(Conversation::default());
        turn(&mut env, &conv, ask("hi")).await;
        // The server goes away, so the retry fails. It pushed no message, so it must not take one back.
        let port = std::net::TcpListener::bind("127.0.0.1:0").unwrap().local_addr().unwrap().port();
        env.servers[0].base_url = format!("http://127.0.0.1:{port}");
        let events = turn(&mut env, &conv, TurnRequest { regenerate: true, ..ask("") }).await;
        assert!(matches!(events.last().unwrap(), AiEvent::Error { kind: ErrorKind::Unreachable, .. }), "{events:?}");
        let c = conv.lock().unwrap();
        assert_eq!(c.turns.len(), 1, "the old reply went when Retry was pressed; the question stays");
        assert_eq!(c.turns[0].text, "hi");
    }

    #[tokio::test]
    async fn later_messages_reuse_what_was_prepared_for_a_file() {
        let local = FakeServer::start(&[]);
        let dir = testkit::TempDir::new("reuse");
        let file = dir.path().join("memo.txt");
        std::fs::write(&file, "the memo says QUOKKA\n").unwrap();
        let mut env = env(&[], None, Some(&local));
        let conv = Mutex::new(Conversation::default());
        let first = TurnRequest {
            feature: Feature::Files,
            text: "what does it say?".into(),
            files: vec![FileRef { name: "memo.txt".into(), path: file.clone() }],
            regenerate: false,
        };
        turn(&mut env, &conv, first).await;
        assert_eq!(conv.lock().unwrap().turns[0].prepared.len(), 1, "prepared once, on the message it was dropped on");

        // The inbox sweep removes the file; the conversation goes on.
        std::fs::remove_file(&file).unwrap();
        let events = turn(&mut env, &conv, ask("and then?")).await;
        assert!(done_text(&events).is_some(), "{events:?}");
        let chats: Vec<_> = local.requests().into_iter().filter(|r| r["path"] == "/v1/chat/completions").collect();
        let earlier = chats[1]["body"]["messages"][1]["content"].as_str().unwrap();
        assert!(earlier.contains("the memo says QUOKKA"), "{earlier}");
        assert_eq!(conv.lock().unwrap().turns[0].prepared.len(), 1, "and not prepared again");
    }

    #[tokio::test]
    async fn an_earlier_file_that_is_gone_does_not_block_a_new_question() {
        let local = FakeServer::start(&[]);
        let mut env = env(&[], None, Some(&local));
        let conv = Mutex::new(Conversation::default());
        {
            let mut c = conv.lock().unwrap();
            let gone = FileRef { name: "gone.txt".into(), path: PathBuf::from("/definitely/not/here/gone.txt") };
            c.turns.push(Turn::user("what is it?".into(), vec![gone]));
            c.turns.push(Turn::assistant("A memo.".into()));
        }
        let events = turn(&mut env, &conv, ask("thanks, and?")).await;
        assert!(done_text(&events).is_some(), "{events:?}");
        let chats: Vec<_> = local.requests().into_iter().filter(|r| r["path"] == "/v1/chat/completions").collect();
        let earlier = chats[0]["body"]["messages"][1]["content"].as_str().unwrap();
        assert!(earlier.contains("File: gone.txt (no longer available)"), "{earlier}");
        assert!(conv.lock().unwrap().turns[0].prepared.is_empty(), "a miss is not cached: a later message tries again");

        // The newest message's own file is different: a file that can't be read is said so.
        let missing_now = TurnRequest {
            feature: Feature::Files,
            text: "read this".into(),
            files: vec![FileRef { name: "new.txt".into(), path: PathBuf::from("/definitely/not/here/new.txt") }],
            regenerate: false,
        };
        let events = turn(&mut env, &conv, missing_now).await;
        assert!(matches!(events.last().unwrap(), AiEvent::Problem { kind: ProblemKind::Unreadable, .. }), "{events:?}");
    }

    #[tokio::test]
    async fn files_nothing_here_can_read_say_why_not_that_the_model_cannot_see() {
        let local = FakeServer::start(&[]);
        let files = testkit::make_attachments();
        let heic = files.path().join("IMG_0001.HEIC");
        std::fs::write(&heic, b"\0\0\0\x18ftypheic").unwrap();
        let mut env = env(&[], None, Some(&local));
        let conv = Mutex::new(Conversation::default());
        let about = |name: &str, path: PathBuf| TurnRequest {
            feature: Feature::Files,
            text: "what is it?".into(),
            files: vec![FileRef { name: name.into(), path }],
            regenerate: false,
        };
        let events = turn(&mut env, &conv, about("scan.pdf", files.path().join("scan.pdf"))).await;
        assert_eq!(
            events.last().unwrap(),
            &AiEvent::Problem { kind: ProblemKind::ScannedPdf, message: errors::scanned_pdf_copy().into(), action: None }
        );
        let events = turn(&mut env, &conv, about("IMG_0001.HEIC", heic)).await;
        assert_eq!(
            events.last().unwrap(),
            &AiEvent::Problem { kind: ProblemKind::Heic, message: errors::HEIC.into(), action: None }
        );
        assert!(conv.lock().unwrap().turns.is_empty());
    }

    #[test]
    fn island_notices_are_not_contract_error_kinds() {
        let contract = [
            ErrorKind::Offline, ErrorKind::Unreachable, ErrorKind::Timeout, ErrorKind::Server,
            ErrorKind::RateLimited, ErrorKind::Overloaded, ErrorKind::Auth, ErrorKind::BadRequest,
            ErrorKind::Billing, ErrorKind::Refusal, ErrorKind::Cancelled, ErrorKind::Interrupted,
        ];
        let names: Vec<&str> = contract.iter().map(|k| k.as_str()).collect();
        for kind in [
            ProblemKind::CantSee, ProblemKind::ScannedPdf, ProblemKind::Heic, ProblemKind::Rejected,
            ProblemKind::Unreadable, ProblemKind::MissingModel, ProblemKind::Outdated, ProblemKind::EmptyReply,
        ] {
            let name = serde_json::to_value(kind).unwrap();
            assert!(!names.contains(&name.as_str().unwrap()), "{name} is a contract kind");
        }
        // And on the wire they differ by event type: `problem`, never `error`.
        let event = AiEvent::Problem { kind: ProblemKind::CantSee, message: "x".into(), action: None };
        assert_eq!(serde_json::to_value(event).unwrap(), serde_json::json!({ "type": "problem", "kind": "cant_see", "message": "x", "action": null }));
        let event = AiEvent::Error { kind: ErrorKind::RateLimited, message: "x".into(), action: None, retry_after: Some(2) };
        assert_eq!(
            serde_json::to_value(event).unwrap(),
            serde_json::json!({ "type": "error", "kind": "rate_limited", "message": "x", "action": null, "retryAfter": 2 })
        );
    }

    #[test]
    fn resolve_describes_auto_and_its_fallback() {
        let mut env = env(&["anthropic"], None, None);
        env.servers = vec![running("ollama", "http://127.0.0.1:11434", Placement::Local)];
        env.models.insert(
            "anthropic".into(),
            vec![ModelInfo {
                id: "claude-sonnet-5-5".into(),
                display_name: "Claude Sonnet 5.5".into(),
                context_tokens: None,
                capabilities: Capabilities::default(),
            }],
        );
        let r = resolve(&env, Feature::Chat);
        assert_eq!(r.reader.as_deref(), Some("Claude"));
        assert_eq!(r.model_name.as_deref(), Some("Claude Sonnet 5.5"));
        assert_eq!(r.fallback.as_deref(), Some("Local · llama3.2"));
        env.keys.clear();
        env.servers.clear();
        assert!(resolve(&env, Feature::Files).empty);
    }
}
```

Add `pub mod session;` to `ai/mod.rs`, below `pub mod router;`.

Run: `cargo test -p notchmeow ai::session::`
Expected: FAIL to compile: `cannot find type 'Env' in this scope` and similar errors.

- [ ] **Step 3: Write the session**

Put this above the tests in `session.rs`:

```rust
// One conversation, and one turn of it: route, stream, fall back once, keep the
// history provider-neutral so any model can pick it up. Everything the island
// sees arrives as `AiEvent`s. Logs record event types and errors only — never a
// prompt, a file, a file name or a key.

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::{Arc, Mutex};

use serde::{Deserialize, Serialize};
use tokio::sync::Notify;

use crate::ai::anthropic::Anthropic;
use crate::ai::attachments::{self, Prepared, PrepareError, Reader};
use crate::ai::budget;
use crate::ai::catalog::{self, Api};
use crate::ai::discovery::{self, Probe, Server, ServerStatus};
use crate::ai::errors::{self, Action, Who};
use crate::ai::openai::OpenAI;
use crate::ai::openai_compat::OpenAICompat;
use crate::ai::provider::{
    file_label, AiError, Aggregate, ChatChunk, ChatRequest, Endpoint, ErrorKind, Finish, Message, ModelInfo,
    ModelProvider, Part, Placement, Role, Timeouts,
};
use crate::ai::router::{self, Choice, ModelRef, Outcome, Ready, RouteInput};
use crate::log;
use crate::settings::AiSettings;

/// Claude and OpenAI search the web themselves.
pub const SYSTEM_PROMPT_SEARCH: &str = "You are Shrimpy, a personal AI assistant living at the top of the user's screen. \
You have web search access and can help with absolutely anything — research, coding, finding places, recommendations, tasks, questions. \
Respond in the user's language. Be thorough and complete — use as much detail as the task requires. \
No markdown formatting (no **, no ##, no bullet dashes). Use plain text with line breaks.";

/// Every other model: no claim of web access it doesn't have.
pub const SYSTEM_PROMPT_PLAIN: &str = "You are Shrimpy, a personal AI assistant living at the top of the user's screen. \
You can help with research, coding, recommendations, tasks and questions. \
Respond in the user's language. Be thorough and complete — use as much detail as the task requires. \
No markdown formatting (no **, no ##, no bullet dashes). Use plain text with line breaks.";

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "lowercase")]
pub enum Feature {
    Chat,
    Files,
}

impl AiSettings {
    pub fn choice(&self, feature: Feature) -> &Choice {
        match feature {
            Feature::Chat => &self.chat,
            Feature::Files => &self.files,
        }
    }
}

#[derive(Debug, Clone, PartialEq)]
pub struct FileRef {
    pub name: String,
    pub path: PathBuf,
}

/// What `attachments::prepare` made of one message's files for one reader.
#[derive(Debug, Clone, PartialEq)]
pub struct PreparedFiles {
    reader: Reader,
    files: Vec<Prepared>,
}

/// One message of the conversation. Files stay as references and are shaped for
/// whichever model reads them, so a fallback model gets them in its own format.
#[derive(Debug, Clone, PartialEq)]
pub struct Turn {
    pub role: Role,
    pub text: String,
    pub files: Vec<FileRef>,
    /// Filled the first time a model reads this message's files, one entry per reader. Later
    /// messages reuse it, so OCR, page rendering and base64 run once, and a file the inbox
    /// sweep has since removed no longer blocks the conversation. `Arc` keeps the per-turn
    /// clone cheap when a 25 MB PDF is in there.
    prepared: Vec<Arc<PreparedFiles>>,
}

impl Turn {
    pub fn user(text: String, files: Vec<FileRef>) -> Self {
        Turn { role: Role::User, text, files, prepared: Vec::new() }
    }

    pub fn assistant(text: String) -> Self {
        Turn { role: Role::Assistant, text, files: Vec::new(), prepared: Vec::new() }
    }
}

#[derive(Default)]
pub struct Conversation {
    pub turns: Vec<Turn>,
    /// Bumped on every reset: a reply still on its way to an old conversation is dropped.
    pub generation: u64,
}

impl Conversation {
    pub fn reset(&mut self) {
        self.turns.clear();
        self.generation += 1;
    }
}

/// Why a turn stopped for a reason that is not a failure of a provider or the network. These
/// are the island's own notices. They are NOT the contract's twelve `ErrorKind`s
/// (docs/AI-PROVIDERS.md): they never reach the router, and they travel as
/// `AiEvent::Problem`, never as `AiEvent::Error`. The island shows them like errors (a note
/// and the error sound), but nothing may treat them as if a provider had sent them.
#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize)]
#[serde(rename_all = "snake_case")]
pub enum ProblemKind {
    /// The model can't see images and nothing here can read the image for it.
    CantSee,
    /// A scanned PDF this platform can neither render nor read.
    ScannedPdf,
    /// A HEIC photo: Anthropic and OpenAI reject it and local servers can't decode it.
    Heic,
    /// An archive, an app, a video or a file over 25 MB.
    Rejected,
    /// A file that could not be opened.
    Unreadable,
    /// The model the user picked is no longer on its server.
    MissingModel,
    /// The server answers but has no OpenAI-compatible API yet.
    Outdated,
    /// The model finished without any text to show.
    EmptyReply,
}

/// What the island receives over the `ai_chat` channel.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(tag = "type", rename_all = "camelCase", rename_all_fields = "camelCase")]
pub enum AiEvent {
    /// A model started answering; `caption` is "cloud · Claude Sonnet 5.5". `waking`
    /// ("Waking up qwen3.5…") is shown if a local model is slow to say its first word.
    Started { provider: String, model: String, placement: Placement, caption: String, fallback: bool, waking: Option<String> },
    Delta { text: String },
    Citation { url: String, title: String },
    /// A line under the reply: a cut file, trimmed history, a fallback.
    Notice { text: String },
    /// The reply is over. `interrupted`: the stream broke; `cancelled`: Stop was pressed.
    Done { text: String, interrupted: bool, cancelled: bool },
    /// A failure of a provider or the network: `kind` is one of the contract's twelve
    /// `ErrorKind`s, spelled as in `ErrorKind::as_str`. `retry_after` is set when the island
    /// should count down and send again.
    Error { kind: ErrorKind, message: String, action: Option<Action>, retry_after: Option<u64> },
    /// One of the island's own notices (`ProblemKind`), not a contract error kind.
    Problem { kind: ProblemKind, message: String, action: Option<Action> },
    /// No key and no local model.
    EmptyState,
}

#[derive(Debug, Clone, PartialEq)]
pub struct TurnRequest {
    pub feature: Feature,
    pub text: String,
    pub files: Vec<FileRef>,
    /// Retry: drop the last reply and answer the last message again.
    pub regenerate: bool,
}

/// Everything a turn reads. Built from the app state for each turn; tests build it by hand.
pub struct Env {
    pub settings: AiSettings,
    /// Provider id (anthropic, openai, google, custom) → key. Rust-side only.
    pub keys: HashMap<String, String>,
    /// The last discovery.
    pub servers: Vec<Server>,
    /// What discovery checks when Auto needs a local model.
    pub probes: Vec<Probe>,
    /// The debug-only cloud redirect (`catalog::debug_override()`).
    pub cloud_override: Option<String>,
    /// Model lists already fetched, for display names and Google's default.
    pub models: HashMap<String, Vec<ModelInfo>>,
    /// Shorter limits for tests; `None` uses the spec's.
    pub timeouts: Option<Timeouts>,
}

impl Env {
    async fn rediscover(&mut self) {
        self.servers = discovery::discover(self.probes.clone(), std::time::Duration::from_millis(catalog::PROBE_MS)).await;
    }

    fn timeouts(&self, placement: Placement) -> Timeouts {
        self.timeouts.unwrap_or_else(|| Timeouts::for_placement(placement))
    }
}

/// Running servers with models, each with its last-used (or first) model, in discovery order.
pub fn ready_list(env: &Env) -> Vec<Ready> {
    env.servers
        .iter()
        .filter(|s| s.status == ServerStatus::Running && !s.models.is_empty())
        .map(|s| {
            let remembered = env.settings.local_models.get(&s.provider).filter(|m| s.models.iter().any(|x| &x.id == *m));
            Ready {
                provider: s.provider.clone(),
                model: remembered.cloned().unwrap_or_else(|| s.models[0].id.clone()),
                placement: s.placement,
            }
        })
        .collect()
}

pub fn route_input(env: &Env, feature: Feature) -> RouteInput {
    RouteInput {
        setting: env.settings.choice(feature).clone(),
        preferred_cloud: env.settings.preferred_cloud.clone(),
        keys: catalog::CLOUD_ORDER.iter().filter(|p| env.keys.contains_key(**p)).map(|p| p.to_string()).collect(),
        online: true,
        local_ready: ready_list(env),
        last_used_local: env.settings.last_used_local.clone(),
        apple_ready: false,
        failure: None,
    }
}

/// One model, ready to be called.
#[derive(Debug, Clone, PartialEq)]
pub struct Target {
    pub endpoint: Endpoint,
    pub model: String,
    /// What the caption shows: the model's display name, or its id.
    pub model_name: String,
    pub vision: bool,
    pub context_tokens: Option<u64>,
    host: String,
}

impl Target {
    pub fn who(&self) -> Who {
        Who { provider: self.endpoint.provider.clone(), name: self.endpoint.name.clone() }
    }

    /// "cloud · Claude Sonnet 5.5", "local · qwen3.5:2b", "network · llama3 @ studio-pc".
    pub fn caption(&self) -> String {
        match self.endpoint.placement {
            Placement::Cloud => format!("cloud · {}", self.model_name),
            Placement::Local => format!("local · {}", self.model),
            Placement::Network => format!("network · {} @ {}", self.model, self.host),
        }
    }

}

pub fn make_provider(endpoint: Endpoint) -> Box<dyn ModelProvider> {
    match catalog::get(&endpoint.provider).map(|p| p.api) {
        Some(Api::Anthropic) => Box::new(Anthropic::new(endpoint)),
        Some(Api::OpenAIResponses) => Box::new(OpenAI::new(endpoint)),
        _ => Box::new(OpenAICompat::new(endpoint)),
    }
}

enum TargetError {
    Failed(AiError, Who),
    Event(AiEvent),
}

fn problem(kind: ProblemKind, message: String, action: Option<Action>) -> AiEvent {
    AiEvent::Problem { kind, message, action }
}

/// The endpoint and model for a provider. Cloud needs its key; a local server is
/// looked for again when the last discovery didn't see it running.
async fn target_for(env: &mut Env, provider: &str, model: Option<String>) -> Result<Target, TargetError> {
    if catalog::is_cloud(provider) {
        let def = catalog::get(provider).unwrap();
        let who = Who { provider: provider.into(), name: def.name.into() };
        let Some(key) = env.keys.get(provider).cloned() else {
            let missing = AiError { code: Some(errors::MISSING_KEY.into()), ..AiError::new(ErrorKind::Auth) };
            return Err(TargetError::Failed(missing, who));
        };
        let endpoint = Endpoint {
            provider: provider.into(),
            name: def.name.into(),
            base_url: catalog::base_url(provider, env.cloud_override.as_deref()).unwrap_or_default(),
            key: Some(key),
            placement: Placement::Cloud,
            timeouts: env.timeouts(Placement::Cloud),
        };
        let known = env.models.get(provider).cloned().unwrap_or_default();
        let chosen = model
            .or_else(|| env.settings.cloud_models.get(provider).cloned())
            .or_else(|| catalog::default_model(provider, &known));
        let model = match chosen {
            Some(m) => m,
            None => {
                let list = make_provider(endpoint.clone()).list_models().await.map_err(|e| TargetError::Failed(e, who.clone()))?;
                env.models.insert(provider.into(), list.clone());
                catalog::default_model(provider, &list).ok_or_else(|| TargetError::Failed(AiError::new(ErrorKind::BadRequest), who.clone()))?
            }
        };
        let model_name = env
            .models
            .get(provider)
            .and_then(|l| l.iter().find(|m| m.id == model))
            .map(|m| m.display_name.clone())
            .unwrap_or_else(|| model.clone());
        return Ok(Target { endpoint, model, model_name, vision: true, context_tokens: None, host: String::new() });
    }

    let running = |env: &Env| env.servers.iter().find(|s| s.provider == provider && s.status == ServerStatus::Running).cloned();
    if running(env).is_none() {
        env.rediscover().await;
    }
    let server = match running(env) {
        Some(s) => s,
        None => {
            let seen = env.servers.iter().find(|s| s.provider == provider);
            if let Some(s) = seen.filter(|s| s.status == ServerStatus::Outdated) {
                let w = errors::outdated_copy(&s.name);
                return Err(TargetError::Event(problem(ProblemKind::Outdated, w.text, w.action)));
            }
            let name = seen.map(|s| s.name.clone()).or_else(|| catalog::get(provider).map(|d| d.name.to_string())).unwrap_or_default();
            return Err(TargetError::Failed(AiError::new(ErrorKind::Unreachable), Who { provider: provider.into(), name }));
        }
    };
    let who = Who { provider: provider.into(), name: server.name.clone() };
    let model = match model {
        Some(m) if server.models.iter().any(|x| x.id == m) => m,
        // An explicit choice is never swapped for another model behind the user's back.
        Some(m) => {
            let w = errors::missing_model_copy(&m, &server.name);
            return Err(TargetError::Event(problem(ProblemKind::MissingModel, w.text, w.action)));
        }
        None => server
            .models
            .first()
            .map(|m| m.id.clone())
            .ok_or_else(|| TargetError::Failed(AiError::new(ErrorKind::BadRequest), who.clone()))?,
    };
    let info = server.models.iter().find(|m| m.id == model);
    Ok(Target {
        endpoint: Endpoint {
            provider: provider.into(),
            name: server.name.clone(),
            base_url: server.base_url.clone(),
            key: if provider == "custom" { env.keys.get("custom").cloned() } else { None },
            placement: server.placement,
            timeouts: env.timeouts(server.placement),
        },
        model_name: info.map(|m| m.display_name.clone()).unwrap_or_else(|| model.clone()),
        context_tokens: info.and_then(|m| m.context_tokens),
        vision: info.is_some_and(|m| m.capabilities.vision),
        model,
        host: server.host.clone(),
    })
}

fn prepare_event(err: PrepareError) -> AiEvent {
    match err {
        PrepareError::CantSee => problem(ProblemKind::CantSee, errors::CANT_SEE.into(), Some(Action::ChooseModel)),
        PrepareError::ScannedPdf => problem(ProblemKind::ScannedPdf, errors::scanned_pdf_copy().into(), None),
        PrepareError::Heic => problem(ProblemKind::Heic, errors::HEIC.into(), None),
        PrepareError::Rejected(r) => problem(ProblemKind::Rejected, attachments::reject_message(r).into(), None),
        PrepareError::Unreadable => problem(ProblemKind::Unreadable, "I couldn't read that file.".into(), None),
    }
}

/// One file shaped for one reader, off the async threads: OCR, page rendering and base64 are slow.
async fn prepare_one(file: &FileRef, reader: &Reader) -> Result<Prepared, PrepareError> {
    let (path, name, reader) = (file.path.clone(), file.name.clone(), reader.clone());
    tokio::task::spawn_blocking(move || attachments::prepare(&path, &name, &reader))
        .await
        .unwrap_or(Err(PrepareError::Unreadable))
}

/// Keeps what was prepared on its message, so the next message doesn't prepare it again.
fn remember(conv: &Mutex<Conversation>, generation: u64, index: usize, files: &[FileRef], entry: Arc<PreparedFiles>) {
    let mut c = conv.lock().unwrap();
    if c.generation != generation {
        return;
    }
    if let Some(turn) = c.turns.get_mut(index).filter(|t| t.files == files) {
        turn.prepared.push(entry);
    }
}

/// The provider-neutral history, shaped for one model: each message's files prepared for it
/// (once per reader, then reused), the oldest turns dropped when the chat outgrew the model.
async fn build_request(
    target: &Target,
    turns: &[Turn],
    conv: &Mutex<Conversation>,
    generation: u64,
) -> Result<(ChatRequest, Vec<String>), AiEvent> {
    let reader = Reader {
        provider: target.endpoint.provider.clone(),
        placement: target.endpoint.placement,
        vision: target.vision,
        context_tokens: target.context_tokens,
    };
    let mut messages = Vec::new();
    let mut notices = Vec::new();
    for (i, turn) in turns.iter().enumerate() {
        let latest = i + 1 == turns.len();
        let mut parts = Vec::new();
        if !turn.files.is_empty() {
            let prepared = match turn.prepared.iter().find(|p| p.reader == reader) {
                Some(hit) => hit.clone(),
                None => {
                    let mut files = Vec::new();
                    let mut complete = true;
                    for file in &turn.files {
                        match prepare_one(file, &reader).await {
                            Ok(p) => files.push(p),
                            // A file from an earlier message that can't be read now (the inbox sweep
                            // removed it, say) must not block a new question: tell the model instead.
                            Err(_) if !latest => {
                                complete = false;
                                let note = format!("{} (no longer available)", file_label(&file.name));
                                files.push(Prepared { parts: vec![Part::Text(note)], notice: None });
                            }
                            Err(e) => return Err(prepare_event(e)),
                        }
                    }
                    let entry = Arc::new(PreparedFiles { reader: reader.clone(), files });
                    if complete {
                        remember(conv, generation, i, &turn.files, entry.clone());
                    }
                    entry
                }
            };
            for file in &prepared.files {
                if latest {
                    notices.extend(file.notice.clone());
                }
                parts.extend(file.parts.clone());
            }
        }
        if !turn.text.is_empty() {
            parts.push(Part::Text(turn.text.clone()));
        }
        messages.push(Message { role: turn.role, parts });
    }
    let system = if catalog::reads_pdf_natively(&reader.provider) { SYSTEM_PROMPT_SEARCH } else { SYSTEM_PROMPT_PLAIN };
    let lengths: Vec<usize> = messages.iter().map(budget::message_chars).collect();
    let drop = budget::messages_to_drop(reader.placement, reader.context_tokens, system.chars().count(), &lengths);
    if drop > 0 {
        messages.drain(..drop);
        notices.push(errors::TOO_LONG.to_string());
    }
    let request = ChatRequest {
        model: target.model.clone(),
        system: system.to_string(),
        messages,
        tools: Vec::new(),
        response_format: None,
        max_tokens: catalog::max_output_tokens(reader.placement),
    };
    Ok((request, notices))
}

enum Attempt {
    /// `cut_off`: the model stopped at the token limit, so the text may end mid-sentence.
    Answered { text: String, cut_off: bool },
    /// The model finished with nothing to show; `cut_off` says it ran out of tokens first.
    Empty { cut_off: bool },
    Interrupted(String),
    Cancelled(String),
    Refused(String),
    Failed(AiError),
    Stopped(AiEvent),
}

/// Streams one model's answer into the island.
async fn attempt(
    env: &Env,
    target: &mut Target,
    turns: &[Turn],
    conv: &Mutex<Conversation>,
    generation: u64,
    cancel: &Notify,
    fallback: bool,
    emit: &mut (dyn FnMut(AiEvent) + Send),
) -> Attempt {
    if target.endpoint.placement != Placement::Cloud && turns.iter().any(|t| !t.files.is_empty()) {
        if let Some(server) = env.servers.iter().find(|s| s.provider == target.endpoint.provider) {
            target.vision = target.vision || discovery::vision(server, &target.model).await;
        }
    }
    let (request, notices) = match build_request(target, turns, conv, generation).await {
        Ok(r) => r,
        Err(event) => return Attempt::Stopped(event),
    };
    let provider = make_provider(target.endpoint.clone());
    log::line(format!("ai start provider={} placement={} fallback={fallback}", provider.id(), provider.placement().as_str()));
    emit(AiEvent::Started {
        provider: target.endpoint.provider.clone(),
        model: target.model.clone(),
        placement: target.endpoint.placement,
        caption: target.caption(),
        fallback,
        waking: (target.endpoint.placement != Placement::Cloud).then(|| errors::waking_copy(&target.model)),
    });
    for text in notices {
        emit(AiEvent::Notice { text });
    }
    let mut shown = String::new();
    let result = {
        let mut sink = |chunk: ChatChunk| match chunk {
            ChatChunk::Text(text) => {
                shown.push_str(&text);
                emit(AiEvent::Delta { text });
            }
            ChatChunk::Citation { url, title } => emit(AiEvent::Citation { url, title }),
            _ => {}
        };
        tokio::select! {
            r = provider.stream(&request, &mut sink) => Some(r),
            _ = cancel.notified() => None,
        }
    };
    match result {
        None => Attempt::Cancelled(shown),
        Some(Err(e)) => Attempt::Failed(e),
        Some(Ok(agg)) => classify(agg, shown),
    }
}

/// The reply as the user saw it. By the contract's rule an unclosed `<think>` stays in the
/// aggregate (a model that ran out of tokens mid-thought), but it must never become the reply.
fn visible_text(aggregate_text: String, shown: String) -> String {
    if aggregate_text.contains("<think>") {
        shown
    } else {
        aggregate_text
    }
}

fn classify(agg: Aggregate, shown: String) -> Attempt {
    if agg.finish == Some(Finish::Refusal) {
        return Attempt::Refused(agg.refusal.unwrap_or_default());
    }
    let cut_off = agg.finish == Some(Finish::Length);
    let text = visible_text(agg.text, shown);
    match agg.error {
        // No text at all is a failure, never an empty reply in the history.
        None if text.trim().is_empty() => Attempt::Empty { cut_off },
        None => Attempt::Answered { text, cut_off },
        // Some text arrived: keep it and mark it, whatever broke the stream.
        Some(_) if !text.trim().is_empty() => Attempt::Interrupted(text),
        // Nothing arrived: a failure like any other.
        Some(ErrorKind::Interrupted) => Attempt::Failed(AiError::new(ErrorKind::Server)),
        Some(kind) => Attempt::Failed(AiError::new(kind)),
    }
}

fn error_event(err: &AiError, who: &Who) -> AiEvent {
    let w = errors::error_copy(err.kind, who, Some(err));
    let countdown = matches!(err.kind, ErrorKind::RateLimited | ErrorKind::Overloaded);
    AiEvent::Error {
        kind: err.kind,
        message: w.text,
        action: w.action,
        retry_after: countdown.then(|| err.retry_after.unwrap_or(errors::DEFAULT_RETRY_SECONDS)),
    }
}

fn log_failure(err: &AiError, who: &Who) {
    log::line(format!(
        "ai error provider={} kind={} status={} request-id={}",
        who.provider,
        err.kind.as_str(),
        err.status.map_or("-".to_string(), |s| s.to_string()),
        err.request_id.as_deref().unwrap_or("-")
    ));
}

/// A local server that stopped answering is forgotten, so the next message looks again.
fn forget_if_down(env: &mut Env, err: &AiError, who: &Who) {
    if err.kind == ErrorKind::Unreachable && !catalog::is_cloud(&who.provider) {
        if let Some(s) = env.servers.iter_mut().find(|s| s.provider == who.provider) {
            s.status = ServerStatus::Off;
        }
    }
}

/// A turn that failed leaves no half turn behind: the message it pushed is taken back. A
/// retry pushed no message (`pushed` is false): the question it answers again stays.
fn undo_user(conv: &Mutex<Conversation>, generation: u64, pushed: bool) {
    let mut c = conv.lock().unwrap();
    if pushed && c.generation == generation && c.turns.last().map(|t| t.role) == Some(Role::User) {
        c.turns.pop();
    }
}

fn push_reply(conv: &Mutex<Conversation>, generation: u64, text: &str) {
    let mut c = conv.lock().unwrap();
    if c.generation == generation {
        c.turns.push(Turn::assistant(text.to_string()));
    }
}

/// Settles a finished attempt. Returns the failure when the router may still act on it.
fn settle(
    env: &mut Env,
    conv: &Mutex<Conversation>,
    generation: u64,
    pushed: bool,
    target: &Target,
    outcome: Attempt,
    emit: &mut (dyn FnMut(AiEvent) + Send),
) -> Option<AiError> {
    match outcome {
        Attempt::Answered { text, cut_off } => {
            push_reply(conv, generation, &text);
            if target.endpoint.placement != Placement::Cloud {
                let (p, m) = (target.endpoint.provider.clone(), target.model.clone());
                env.settings.local_models.insert(p.clone(), m.clone());
                env.settings.last_used_local = Some(ModelRef { provider: p, model: m });
            }
            log::line(format!("ai done provider={} cut-off={cut_off}", target.endpoint.provider));
            if cut_off {
                // Worth keeping, but it stopped at the token limit and may end mid-sentence.
                emit(AiEvent::Notice { text: errors::CUT_OFF.into() });
            }
            emit(AiEvent::Done { text, interrupted: false, cancelled: false });
            None
        }
        Attempt::Empty { cut_off } => {
            // No text at all: nothing joins the history and no `Done` follows, so the island
            // plays the error sound, not the finish one.
            undo_user(conv, generation, pushed);
            log::line(format!("ai empty provider={} cut-off={cut_off}", target.endpoint.provider));
            let (message, action) = if cut_off {
                (errors::RAN_OUT_OF_ROOM, Some(Action::ChooseModel))
            } else {
                (errors::EMPTY_REPLY, None)
            };
            emit(problem(ProblemKind::EmptyReply, message.into(), action));
            None
        }
        Attempt::Interrupted(text) => {
            push_reply(conv, generation, &text);
            log::line(format!("ai interrupted provider={}", target.endpoint.provider));
            emit(AiEvent::Done { text, interrupted: true, cancelled: false });
            None
        }
        Attempt::Cancelled(text) => {
            if text.is_empty() {
                undo_user(conv, generation, pushed);
            } else {
                push_reply(conv, generation, &text);
            }
            log::line(format!("ai cancelled provider={}", target.endpoint.provider));
            emit(AiEvent::Done { text, interrupted: false, cancelled: true });
            None
        }
        Attempt::Refused(text) => {
            undo_user(conv, generation, pushed);
            log::line(format!("ai refusal provider={}", target.endpoint.provider));
            let message = if text.trim().is_empty() { errors::error_copy(ErrorKind::Refusal, &target.who(), None).text } else { text };
            emit(AiEvent::Error { kind: ErrorKind::Refusal, message, action: None, retry_after: None });
            None
        }
        Attempt::Stopped(event) => {
            undo_user(conv, generation, pushed);
            emit(event);
            None
        }
        Attempt::Failed(err) => {
            log_failure(&err, &target.who());
            Some(err)
        }
    }
}

/// One turn, start to finish. Never panics, never blocks an agent: every outcome
/// is an event.
pub async fn run_turn(
    env: &mut Env,
    conv: &Mutex<Conversation>,
    request: TurnRequest,
    cancel: &Notify,
    emit: &mut (dyn FnMut(AiEvent) + Send),
) {
    // A retry answers the message already there; only a new message is taken back on failure.
    let pushed = !request.regenerate;
    let (turns, generation) = {
        let mut c = conv.lock().unwrap();
        if request.regenerate {
            if c.turns.last().map(|t| t.role) == Some(Role::Assistant) {
                c.turns.pop();
            }
        } else {
            c.turns.push(Turn::user(request.text.clone(), request.files.clone()));
        }
        (c.turns.clone(), c.generation)
    };
    if turns.last().map(|t| t.role) != Some(Role::User) {
        emit(AiEvent::Done { text: String::new(), interrupted: false, cancelled: true });
        return;
    }

    let mut input = route_input(env, request.feature);
    if input.setting.is_auto() && router::cloud_choice(&input).is_none() && input.local_ready.is_empty() {
        env.rediscover().await;
        input = route_input(env, request.feature);
    }
    let first = router::route(&input);
    let Some(primary) = first.primary.clone().filter(|_| first.outcome != Outcome::EmptyState) else {
        undo_user(conv, generation, pushed);
        emit(AiEvent::EmptyState);
        return;
    };
    let primary_model = match &input.setting {
        Choice::Explicit(m) => Some(m.model.clone()),
        Choice::Auto(_) if catalog::is_cloud(&primary) => None,
        Choice::Auto(_) => router::local_choice(&input).map(|r| r.model),
    };

    let failure = match target_for(env, &primary, primary_model).await {
        Ok(mut target) => {
            let outcome = attempt(env, &mut target, &turns, conv, generation, cancel, false, emit).await;
            match settle(env, conv, generation, pushed, &target, outcome, emit) {
                None => return,
                Some(err) => (err, target.who()),
            }
        }
        Err(TargetError::Event(event)) => {
            undo_user(conv, generation, pushed);
            emit(event);
            return;
        }
        Err(TargetError::Failed(err, who)) => {
            log_failure(&err, &who);
            (err, who)
        }
    };

    // The router decides what a failure means: one local retry, a countdown, or an error.
    let (err, who) = failure;
    forget_if_down(env, &err, &who);
    let mut after = input.clone();
    after.failure = Some(err.kind);
    if after.setting.is_auto() && err.kind.is_temporary() && catalog::is_cloud(&primary) && after.local_ready.is_empty() {
        env.rediscover().await;
        after.local_ready = ready_list(env);
    }
    let decision = router::route(&after);
    if decision.outcome != Outcome::Fallback {
        undo_user(conv, generation, pushed);
        emit(error_event(&err, &who));
        return;
    }
    let Some(local) = router::local_choice(&after) else {
        undo_user(conv, generation, pushed);
        emit(error_event(&err, &who));
        return;
    };
    log::line(format!("ai fallback from={primary} to={}", local.provider));
    let fallback = match target_for(env, &local.provider, Some(local.model.clone())).await {
        Ok(t) => t,
        Err(TargetError::Event(event)) => {
            undo_user(conv, generation, pushed);
            emit(event);
            return;
        }
        Err(TargetError::Failed(e, w)) => {
            forget_if_down(env, &e, &w);
            undo_user(conv, generation, pushed);
            emit(error_event(&e, &w));
            return;
        }
    };
    emit(AiEvent::Notice { text: errors::fallback_copy(&primary, &fallback.model) });
    let mut fallback = fallback;
    let outcome = attempt(env, &mut fallback, &turns, conv, generation, cancel, true, emit).await;
    if let Some(e) = settle(env, conv, generation, pushed, &fallback, outcome, emit) {
        forget_if_down(env, &e, &fallback.who());
        undo_user(conv, generation, pushed);
        emit(error_event(&e, &fallback.who()));
    }
}

/// What a feature resolves to right now, for the model chip, the settings line
/// ("Claude Sonnet · falls back to Local · qwen3.5:2b") and the drop card.
/// Makes no network call.
#[derive(Debug, Clone, PartialEq, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct Resolution {
    pub empty: bool,
    pub auto: bool,
    pub provider: Option<String>,
    pub model: Option<String>,
    pub placement: Option<Placement>,
    /// "Claude Sonnet 5.5", "qwen3.5:2b".
    pub model_name: Option<String>,
    /// The drop card: "Claude", "Local · qwen3.5:2b".
    pub reader: Option<String>,
    /// Auto's local retry: "Local · qwen3.5:2b".
    pub fallback: Option<String>,
}

pub fn resolve(env: &Env, feature: Feature) -> Resolution {
    let input = route_input(env, feature);
    let decision = router::route(&input);
    let mut res = Resolution {
        empty: decision.outcome == Outcome::EmptyState,
        auto: input.setting.is_auto(),
        provider: None,
        model: None,
        placement: None,
        model_name: None,
        reader: None,
        fallback: None,
    };
    let Some(primary) = decision.primary else { return res };
    let local_reader = |r: &Ready| match r.placement {
        Placement::Network => {
            let host = env.servers.iter().find(|s| s.provider == r.provider).map(|s| s.host.clone()).unwrap_or_default();
            format!("Network · {} @ {host}", r.model)
        }
        _ => format!("Local · {}", r.model),
    };
    let model = match &input.setting {
        Choice::Explicit(m) => Some(m.model.clone()),
        Choice::Auto(_) if catalog::is_cloud(&primary) => env
            .settings
            .cloud_models
            .get(&primary)
            .cloned()
            .or_else(|| catalog::default_model(&primary, env.models.get(&primary).map(Vec::as_slice).unwrap_or(&[]))),
        Choice::Auto(_) => router::local_choice(&input).map(|r| r.model),
    };
    let placement = decision.label.unwrap_or(Placement::Local);
    res.model_name = model.as_ref().map(|m| {
        env.models
            .get(&primary)
            .and_then(|l| l.iter().find(|x| &x.id == m))
            .map(|x| x.display_name.clone())
            .unwrap_or_else(|| m.clone())
    });
    res.reader = Some(match placement {
        Placement::Cloud => catalog::brand(&primary).to_string(),
        _ => local_reader(&Ready { provider: primary.clone(), model: model.clone().unwrap_or_default(), placement }),
    });
    if res.auto && placement == Placement::Cloud {
        res.fallback = router::local_choice(&input).map(|r| local_reader(&r));
    }
    res.provider = Some(primary);
    res.model = model;
    res.placement = Some(placement);
    res
}
```

- [ ] **Step 4: Run the tests**

Run: `cargo test -p notchmeow ai::session::`
Expected: `test result: ok. 30 passed; 0 failed`. These include:
- the spec's required cases:
  - no key and a local model → local;
  - rejected key → no fallback;
  - 429 with a local model → local, with "Claude's busy right now, so Llama answered instead.";
  - 429 without one → countdown;
  - `insufficient_quota` → billing, no fallback;
- `a_file_joins_the_message_it_was_dropped_on`, the regression test;
- `prompts_and_files_never_reach_the_log`, the leak test with the marker `QUOKKAMARKER7731`;
- Review Focus items 2, 3 and 4;
- empty and cut-off replies, which use `canned_server` because the fake server has no think-only stream:
  - `a_thinking_model_that_runs_out_of_tokens_says_so_and_adds_no_turn`: every token in `<think>`, finish `length` → the "ran out of room" problem, no `Done` (so no finish sound), no empty assistant turn, and the question taken back;
  - `a_reply_cut_off_at_the_token_limit_is_kept_with_a_note`: text, finish `length` → "The answer was cut off." before `Done`, and the text in the history;
  - `an_unclosed_think_block_never_becomes_the_reply` and `an_empty_reply_is_a_failure_whatever_the_finish`;
  - `every_request_asks_for_its_placements_reply_length` reads the request logs and providers.json's `maxOutputTokens`: `max_tokens` for a local model, a network server and Claude, `max_output_tokens` for OpenAI;
  - `a_long_chat_on_a_small_model_drops_the_oldest_pair_and_says_so`: what goes over the wire is trimmed by the contract's rule, the notice is shown, and the stored conversation keeps every turn;
- retries and file reuse:
  - `a_failed_retry_keeps_the_question_it_retries`: Retry pushed no message, so a failed Retry takes none back;
  - `later_messages_reuse_what_was_prepared_for_a_file`: the file is prepared once, the inbox copy is deleted, and the next message still carries its text;
  - `an_earlier_file_that_is_gone_does_not_block_a_new_question`;
  - `files_nothing_here_can_read_say_why_not_that_the_model_cannot_see`: a scanned PDF and a `.HEIC` get their own words;
- `island_notices_are_not_contract_error_kinds`: no `ProblemKind` is one of the 12 `ErrorKind`s, and the two travel as different event types.

Run: `cargo test -p notchmeow ai::`
Expected: `test result: ok. 97 passed; 0 failed` (99 on Windows, which leaves out one Linux-only attachment test and adds three Windows ones). Task 13 adds five more.

- [ ] **Step 5: Commit**

```bash
git add windows/src-tauri/src/log.rs windows/src-tauri/src/ai
git commit -m "feat(ai): one chat turn end to end: route, stream, one local retry, history

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 13: Tauri commands, and the chat moved onto them

**Files:**
- Modify: `windows/src-tauri/src/ai/mod.rs` (whole file: state, commands, tests; the temporary `#![allow(dead_code)]` goes)
- Modify: `windows/src-tauri/src/lib.rs` (`mod claude`, `use claude::…`, `chat_send`, `chat_reset`, `.manage(Chat…)`, `invoke_handler`, setup, and `secret_set` / `secret_clear`, which drop the cached key presence)
- Delete: `windows/src-tauri/src/claude.rs`
- Create: `windows/src/core/feature.ts` (which setting answers a message), `windows/scripts/check-ai-ui.mjs` (a plain-Node check of it)
- Modify: `windows/package.json` (`check:ai` script)
- Modify: `windows/src/core/bridge.ts` (AI calls and types; `chatSend` and `ChatContext` go)
- Modify: `windows/src/core/state.ts` (`AiAction`, `pendingAttachment`, `ChatMessage.attachments`)
- Modify: `windows/src/views/chat.ts` (`submit` streams through `aiChat`; the render key includes the reply's length)
- Modify: `windows/src/island/island.ts` (`swallow` sets `pendingAttachment`)

**Interfaces:**
- **Consumes:** `session::*`, `discovery::*`, `catalog::debug_override`, `crate::{Shared, secrets, files::inbox_dir, settings::save, log}`.
- **Produces:**
  - **Commands** (snake_case like the existing ones; arguments arrive camelCase from TypeScript):
    - `ai_discover() -> Vec<Server>`;
    - `ai_list_models(provider) -> Vec<ModelInfo>`, which also checks a key (`cloud_models(provider, key, root) -> Result<Vec<ModelInfo>, String>` does the work, and its `Err` is the words shown after ✗);
    - `ai_resolve(feature) -> Resolution` and `ai_prewarm(feature)`, both **async**: a sync command runs on the main thread, and these run on every focus. They read key presence from a cache and never a key's value (see below);
    - `ai_chat(feature, text, attachments: Vec<String>, regenerate, onEvent: Channel<AiEvent>)`;
    - `ai_cancel()`;
    - `chat_reset`, which is kept and now resets the AI conversation and stops a running reply.
  - **Rust:** `ai::AiState` (managed state) and `ai::discover_at_launch(AppHandle)`. `AiState` keeps which providers have a key (`present_providers`, read from the keychain once, off the async threads) until `AiState::forget_key_presence()` runs; `secret_set` and `secret_clear` call it. A keychain read that began before a key change is not kept.
  - **TypeScript:**
    - `Bridge.aiChat(feature, text, attachments, regenerate, onEvent)`, `Bridge.aiCancel`, `aiDiscover`, `aiListModels`, `aiResolve`, `aiPrewarm`, plus the types `Feature`, `Placement`, `AiEvent`, `ModelInfo`, `AiServer`, `Resolution`, `AiAction` and `State.pendingAttachment`;
    - **`featureFor(current: readonly string[], history: readonly { attachments?: readonly string[] }[]) -> Feature`** (`core/feature.ts`): `"files"` when the message being sent carries a file or any earlier message of the conversation did, `"chat"` otherwise. `current` is the new message's attachments and `history` is `State.chatHistory`, whose user messages now carry `attachments` (`ChatMessage.attachments`). The conversation decides, never `State.droppedFile`, which is never cleared. A drop or a new chat empties `State.chatHistory`, and the rule starts over with it.

- [ ] **Step 1: Write the command-layer tests**

Append to `windows/src-tauri/src/ai/mod.rs`:

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn one_turn_at_a_time() {
        let ai = AiState::default();
        let first = ai.begin_turn().expect("idle state starts a turn");
        assert!(ai.begin_turn().is_none(), "a second send while a reply streams is refused");
        ai.cancel_running();
        drop(first);
        assert!(ai.begin_turn().is_some(), "the switch clears when the turn ends");
    }

    #[tokio::test]
    async fn focusing_reads_the_keychain_once_not_every_time() {
        use std::sync::atomic::AtomicUsize;
        let ai = AiState::default();
        let reads = Arc::new(AtomicUsize::new(0));
        let counting = |reads: &Arc<AtomicUsize>| {
            let reads = reads.clone();
            move || {
                reads.fetch_add(1, Ordering::SeqCst);
                HashSet::from(["openai".to_string()])
            }
        };
        for _ in 0..5 {
            assert_eq!(present_providers(&ai, counting(&reads)).await, HashSet::from(["openai".to_string()]));
        }
        assert_eq!(reads.load(Ordering::SeqCst), 1, "five focuses, one keychain read");
        // A key was saved or removed (`secret_set`, `secret_clear`): the next look reads again.
        ai.forget_key_presence();
        present_providers(&ai, counting(&reads)).await;
        assert_eq!(reads.load(Ordering::SeqCst), 2);
    }

    #[test]
    fn a_keychain_read_that_raced_a_key_change_is_not_kept() {
        let ai = AiState::default();
        let started = ai.key_epoch.load(Ordering::SeqCst); // the read begins…
        ai.forget_key_presence(); // …a key is saved meanwhile…
        ai.remember_presence(started, HashSet::new()); // …and the old answer arrives late.
        assert_eq!(ai.cached_presence(), None);
    }

    #[tokio::test]
    async fn the_key_check_lists_models_and_says_why_a_key_failed() {
        // The fake model server answers GET /v1/models, so any key "works" against it.
        let fake = testkit::FakeServer::start(&[]);
        let claude = cloud_models("anthropic", "sk-ant-test".into(), Some(&fake.base)).await.unwrap();
        assert_eq!(claude.len(), 2);
        assert_eq!(fake.requests()[0]["path"], "/v1/models?limit=100");
        // OpenAI keeps chat models only and Google drops embeddings; a list, even an empty one, is a pass.
        assert!(cloud_models("openai", "sk-test".into(), Some(&fake.base)).await.unwrap().is_empty());
        let google = cloud_models("google", "AIza-test".into(), Some(&fake.base)).await.unwrap();
        assert_eq!(google.iter().map(|m| m.id.as_str()).collect::<Vec<_>>(), ["llama3.2"]);

        // What the settings window prints after the ✗.
        let rejected = |body: &str, status: u16| testkit::canned_server(status, "application/json", body);
        let claude_401 = rejected(r#"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#, 401);
        assert_eq!(cloud_models("anthropic", "nope".into(), Some(&claude_401)).await.unwrap_err(), "Your Anthropic key was rejected.");
        let openai_401 = rejected(r#"{"error":{"message":"Incorrect API key","type":"invalid_request_error","code":"invalid_api_key"}}"#, 401);
        assert_eq!(cloud_models("openai", "nope".into(), Some(&openai_401)).await.unwrap_err(), "Your OpenAI key was rejected.");
        let openai_429 = rejected(r#"{"error":{"type":"insufficient_quota","code":"insufficient_quota","message":"quota"}}"#, 429);
        assert_eq!(cloud_models("openai", "sk-test".into(), Some(&openai_429)).await.unwrap_err(), "Your OpenAI credit ran out.");
        let port = std::net::TcpListener::bind("127.0.0.1:0").unwrap().local_addr().unwrap().port();
        let down = format!("http://127.0.0.1:{port}");
        assert_eq!(cloud_models("openai", "sk-test".into(), Some(&down)).await.unwrap_err(), "Couldn't reach OpenAI. Check your connection.");
        assert_eq!(cloud_models("ollama", "x".into(), None).await.unwrap_err(), "unknown provider");
    }

    #[test]
    fn only_inbox_files_are_read_and_their_path_is_kept() {
        let root = testkit::TempDir::new("inbox");
        let inbox = root.path().join("inbox");
        std::fs::create_dir_all(&inbox).unwrap();
        let inside = inbox.join("Zoé notes.txt");
        std::fs::write(&inside, "hi").unwrap();
        let outside = root.path().join("secret.txt");
        std::fs::write(&outside, "no").unwrap();

        let given = inside.to_string_lossy().to_string();
        let got = inbox_file(&given, &inbox).expect("a file in the inbox is accepted");
        assert_eq!(got.path, PathBuf::from(&given), "the path is not rewritten (no \\\\?\\ prefix)");
        assert_eq!(got.name, "Zoé notes.txt");
        assert!(inbox_file(&outside.to_string_lossy(), &inbox).is_none());
        let sneaky = inbox.join("..").join("secret.txt");
        assert!(inbox_file(&sneaky.to_string_lossy(), &inbox).is_none());
        assert!(inbox_file(&inbox.to_string_lossy(), &inbox).is_none(), "a folder is not a file");
    }
}
```

Run: `cargo test -p notchmeow ai::tests::`
Expected: FAIL to compile: `cannot find type 'AiState' in this scope` and `cannot find function 'inbox_file' in this scope`.

- [ ] **Step 2: Write the state and the commands**

Replace everything above the test module in `ai/mod.rs` with:

```rust
// NotchMeow's AI layer: providers, routing, streaming, files, and the commands
// the island and the settings window call. Spec:
// docs/superpowers/specs/2026-10-03-local-models-design.md.
//
// All model traffic goes through Rust (reqwest): no webview Origin reaches a
// local server, and API keys never cross into the webview.

pub mod anthropic;
pub mod attachments;
pub mod budget;
pub mod catalog;
pub mod discovery;
pub mod errors;
pub mod openai;
pub mod openai_compat;
pub mod provider;
pub mod router;
pub mod session;
pub mod sse;

#[cfg(test)]
pub mod testkit;

use std::collections::{HashMap, HashSet};
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use tauri::ipc::Channel;
use tauri::{AppHandle, Emitter, Manager, State};
use tokio::sync::Notify;

use crate::settings::AiSettings;
use crate::Shared;
use discovery::{Probe, Server, ServerStatus};
use errors::Who;
use provider::{Endpoint, ModelInfo, Placement, Timeouts};
use session::{AiEvent, Conversation, Env, Feature, FileRef, Resolution, TurnRequest};

/// The AI state the app manages: one conversation, the running turn's Stop
/// switch, the last discovery, the model lists fetched so far and which providers
/// have a key.
#[derive(Default)]
pub struct AiState {
    pub conversation: Mutex<Conversation>,
    cancel: Mutex<Option<Arc<Notify>>>,
    servers: Mutex<Vec<Server>>,
    models: Mutex<HashMap<String, Vec<ModelInfo>>>,
    /// Which providers have a key, read from the keychain once and kept until a key is saved
    /// or removed: the chat and the settings window ask on every focus, and a keychain read
    /// is a blocking OS call. Only presence is kept here, never a key.
    key_presence: Mutex<Option<HashSet<String>>>,
    /// Bumped whenever a key changes: a read that started before the change is not kept.
    key_epoch: AtomicU64,
}

impl AiState {
    /// `chat_reset`: a new conversation; a reply still on its way is stopped and dropped.
    pub fn reset(&self) {
        self.conversation.lock().unwrap().reset();
        self.cancel_running();
    }

    /// A key was saved or removed: the next `ai_resolve` reads the keychain again.
    pub fn forget_key_presence(&self) {
        self.key_epoch.fetch_add(1, Ordering::SeqCst);
        *self.key_presence.lock().unwrap() = None;
    }

    fn cached_presence(&self) -> Option<HashSet<String>> {
        self.key_presence.lock().unwrap().clone()
    }

    /// Keeps a read that began at `epoch`, unless a key changed since.
    fn remember_presence(&self, epoch: u64, present: HashSet<String>) {
        let mut slot = self.key_presence.lock().unwrap();
        if self.key_epoch.load(Ordering::SeqCst) == epoch {
            *slot = Some(present);
        }
    }

    fn cancel_running(&self) {
        if let Some(c) = self.cancel.lock().unwrap().as_ref() {
            c.notify_one();
        }
    }

    /// One turn at a time: `None` while a reply is still streaming.
    fn begin_turn(&self) -> Option<Running<'_>> {
        let mut slot = self.cancel.lock().unwrap();
        if slot.is_some() {
            return None;
        }
        let cancel = Arc::new(Notify::new());
        *slot = Some(cancel.clone());
        Some(Running { state: self, cancel })
    }
}

/// The running turn's Stop switch; cleared however the turn ends.
struct Running<'a> {
    state: &'a AiState,
    cancel: Arc<Notify>,
}

impl Drop for Running<'_> {
    fn drop(&mut self) {
        *self.state.cancel.lock().unwrap() = None;
    }
}

/// Keys from the OS keychain, by provider id. They stay on this side. A blocking
/// call: only a turn needs the values, and it reads them off the async threads.
/// `catalog::keychain_name` gives the item: the added server's is `custom-server-key.default`.
fn read_keys() -> HashMap<String, String> {
    catalog::PROVIDERS
        .iter()
        .filter_map(|p| Some((p.id.to_string(), crate::secrets::get(&catalog::keychain_name(p.id)?)?)))
        .collect()
}

/// Which providers have a key: the ids `read_keys` would return, without the values.
fn read_presence() -> HashSet<String> {
    catalog::PROVIDERS
        .iter()
        .filter_map(|p| crate::secrets::present(&catalog::keychain_name(p.id)?).then(|| p.id.to_string()))
        .collect()
}

/// Which providers have a key, from the cache or, once, from `read` (the keychain). `read`
/// is a blocking OS call, so it runs off the async threads.
async fn present_providers(ai: &AiState, read: impl FnOnce() -> HashSet<String> + Send + 'static) -> HashSet<String> {
    if let Some(known) = ai.cached_presence() {
        return known;
    }
    let epoch = ai.key_epoch.load(Ordering::SeqCst);
    let found = tokio::task::spawn_blocking(read).await.unwrap_or_default();
    ai.remember_presence(epoch, found.clone());
    found
}

fn probes(settings: &AiSettings, custom_key: Option<String>) -> Vec<Probe> {
    let mut probes = discovery::localhost_probes();
    if let Some(url) = &settings.custom_server {
        probes.extend(discovery::custom_probe(url, custom_key));
    }
    probes
}

/// The `Env` for a turn: the keys themselves, read once for this turn.
async fn turn_env(shared: &Shared, ai: &AiState) -> Env {
    let settings = shared.settings.lock().unwrap().ai.clone();
    let keys = tokio::task::spawn_blocking(read_keys).await.unwrap_or_default();
    Env {
        probes: probes(&settings, keys.get("custom").cloned()),
        settings,
        keys,
        servers: ai.servers.lock().unwrap().clone(),
        cloud_override: catalog::debug_override(),
        models: ai.models.lock().unwrap().clone(),
        timeouts: None,
    }
}

/// The `Env` for what the user sees (the model chip, the settings line, the drop card,
/// pre-warming): which providers have a key, never the keys. The empty values are never
/// sent anywhere: nothing built from this `Env` makes a cloud request.
async fn display_env(shared: &Shared, ai: &AiState) -> Env {
    let settings = shared.settings.lock().unwrap().ai.clone();
    let keys = present_providers(ai, read_presence).await.into_iter().map(|p| (p, String::new())).collect();
    Env {
        probes: Vec::new(),
        settings,
        keys,
        servers: ai.servers.lock().unwrap().clone(),
        cloud_override: catalog::debug_override(),
        models: ai.models.lock().unwrap().clone(),
        timeouts: None,
    }
}

/// Writes back what a turn learned — the last-used local model, nothing else, so
/// a choice made in the picker while the reply streamed is kept — and tells both
/// windows through the existing `settings-changed` event.
fn store_learned(app: &AppHandle, shared: &Shared, learned: &AiSettings) {
    let updated = {
        let mut current = shared.settings.lock().unwrap();
        if current.ai.last_used_local == learned.last_used_local && current.ai.local_models == learned.local_models {
            return;
        }
        current.ai.last_used_local = learned.last_used_local.clone();
        current.ai.local_models = learned.local_models.clone();
        current.clone()
    };
    if let Err(err) = crate::settings::save(&updated) {
        crate::log::line(format!("ai could not save settings: {err}"));
    }
    let _ = app.emit("settings-changed", updated);
}

/// Only files NotchMeow copied into its own inbox may be read for the chat.
/// The check uses canonical paths, but the path kept is the one given: on
/// Windows a canonical path starts with `\\?\`, which WinRT's OCR refuses.
fn inbox_file(path: &str, inbox: &Path) -> Option<FileRef> {
    let inbox = std::fs::canonicalize(inbox).ok()?;
    let real = std::fs::canonicalize(path).ok()?;
    if !real.starts_with(&inbox) || !real.is_file() {
        return None;
    }
    let name = Path::new(path).file_name()?.to_string_lossy().to_string();
    Some(FileRef { name, path: PathBuf::from(path) })
}

/// Checks localhost (and the server the user added) for model servers.
#[tauri::command]
pub async fn ai_discover(shared: State<'_, Shared>, ai: State<'_, AiState>) -> Result<Vec<Server>, String> {
    let settings = shared.settings.lock().unwrap().ai.clone();
    // Only the added server's key is needed, and only when there is such a server.
    let custom_key = match settings.custom_server {
        Some(_) => tokio::task::spawn_blocking(|| catalog::keychain_name("custom").and_then(|key| crate::secrets::get(&key)))
            .await
            .ok()
            .flatten(),
        None => None,
    };
    let servers = discovery::discover(probes(&settings, custom_key), Duration::from_millis(catalog::PROBE_MS)).await;
    *ai.servers.lock().unwrap() = servers.clone();
    Ok(servers)
}

/// A cloud provider's model list with this key. It doubles as the key check behind the
/// settings window's ✓ / ✗: `Err` carries the words shown after the ✗ ("Your OpenAI key was
/// rejected."). `root` is the debug-only redirect to the fake server.
async fn cloud_models(provider: &str, key: String, root: Option<&str>) -> Result<Vec<ModelInfo>, String> {
    let def = catalog::get(provider).filter(|d| catalog::is_cloud(d.id)).ok_or("unknown provider")?;
    let who = Who { provider: provider.to_string(), name: def.name.to_string() };
    let endpoint = Endpoint {
        provider: provider.to_string(),
        name: def.name.to_string(),
        base_url: catalog::base_url(provider, root).unwrap_or_default(),
        key: Some(key),
        placement: Placement::Cloud,
        timeouts: Timeouts::for_placement(Placement::Cloud),
    };
    session::make_provider(endpoint).list_models().await.map_err(|e| errors::error_copy(e.kind, &who, Some(&e)).text)
}

/// A provider's live model list. For a cloud provider it doubles as the key check behind the
/// settings window's ✓ / ✗.
#[tauri::command]
pub async fn ai_list_models(ai: State<'_, AiState>, provider: String) -> Result<Vec<ModelInfo>, String> {
    if !catalog::is_cloud(&provider) {
        let servers = ai.servers.lock().unwrap().clone();
        return Ok(servers
            .into_iter()
            .find(|s| s.provider == provider && s.status == ServerStatus::Running)
            .map(|s| s.models)
            .unwrap_or_default());
    }
    let id = provider.clone();
    let key = tokio::task::spawn_blocking(move || catalog::keychain_name(&id).and_then(|key| crate::secrets::get(&key)))
        .await
        .ok()
        .flatten()
        .ok_or_else(|| "No key yet.".to_string())?;
    let list = cloud_models(&provider, key, catalog::debug_override().as_deref()).await?;
    ai.models.lock().unwrap().insert(provider, list.clone());
    Ok(list)
}

/// What a feature resolves to now: the model chip, the settings line, the drop card.
/// Async, so the keychain is never read on the main thread, and the answer comes from the
/// cached key presence, so focusing the chat doesn't read it again.
#[tauri::command]
pub async fn ai_resolve(shared: State<'_, Shared>, ai: State<'_, AiState>, feature: Feature) -> Result<Resolution, String> {
    Ok(session::resolve(&display_env(&shared, &ai).await, feature))
}

/// Opening the chat loads the selected local model ahead of the first message.
#[tauri::command]
pub async fn ai_prewarm(shared: State<'_, Shared>, ai: State<'_, AiState>, feature: Feature) -> Result<(), String> {
    let env = display_env(&shared, &ai).await;
    let res = session::resolve(&env, feature);
    let (Some(provider), Some(model)) = (res.provider, res.model) else { return Ok(()) };
    let Some(server) = env.servers.iter().find(|s| s.provider == provider && s.status == ServerStatus::Running) else {
        return Ok(());
    };
    let endpoint = Endpoint {
        provider,
        name: server.name.clone(),
        base_url: server.base_url.clone(),
        key: None,
        placement: server.placement,
        timeouts: Timeouts::for_placement(server.placement),
    };
    tauri::async_runtime::spawn(async move {
        session::make_provider(endpoint).prewarm(&model).await;
    });
    Ok(())
}

/// One chat turn, streamed to the island over `on_event`.
#[tauri::command]
#[allow(clippy::too_many_arguments)]
pub async fn ai_chat(
    app: AppHandle,
    shared: State<'_, Shared>,
    ai: State<'_, AiState>,
    feature: Feature,
    text: String,
    attachments: Vec<String>,
    regenerate: bool,
    on_event: Channel<AiEvent>,
) -> Result<(), String> {
    let running = ai.begin_turn().ok_or_else(|| "A reply is still on its way.".to_string())?;
    let inbox = crate::files::inbox_dir();
    let mut files = Vec::new();
    for path in &attachments {
        files.push(inbox_file(path, &inbox).ok_or_else(|| "That file is no longer in NotchMeow's inbox.".to_string())?);
    }
    let mut env = turn_env(&shared, &ai).await;
    let mut emit = |event: AiEvent| {
        let _ = on_event.send(event);
    };
    let request = TurnRequest { feature, text, files, regenerate };
    session::run_turn(&mut env, &ai.conversation, request, &running.cancel, &mut emit).await;
    *ai.servers.lock().unwrap() = env.servers;
    ai.models.lock().unwrap().extend(env.models);
    store_learned(&app, &shared, &env.settings);
    Ok(())
}

/// Stop: cancels the stream on its way.
#[tauri::command]
pub fn ai_cancel(ai: State<'_, AiState>) {
    ai.cancel_running();
}

/// Discovery at launch (spec §2), in the background.
pub fn discover_at_launch(app: AppHandle) {
    tauri::async_runtime::spawn(async move {
        let shared = app.state::<Shared>();
        let ai = app.state::<AiState>();
        let _ = ai_discover(shared, ai).await;
    });
}
```

The `#![allow(dead_code)]` from Task 2 is gone: from now on, everything in `ai/` is reached from a command.

- [ ] **Step 3: Wire them into the app and retire `claude.rs`**

In `windows/src-tauri/src/lib.rs`:
- delete `mod claude;` and `use claude::{Chat, ChatContext, ChatReply};`;
- delete the whole `chat_send` command;
- replace `chat_reset` with:

```rust
/// A new conversation: a file was dropped or the chat was cleared. A reply still
/// on its way is stopped and dropped.
#[tauri::command]
fn chat_reset(ai: State<ai::AiState>) {
    ai.reset();
}
```

- replace `.manage(Chat::default())` with `.manage(ai::AiState::default())`;
- in `invoke_handler`, replace `chat_send,` with:

```rust
            ai::ai_discover,
            ai::ai_list_models,
            ai::ai_resolve,
            ai::ai_prewarm,
            ai::ai_chat,
            ai::ai_cancel,
```

- in `setup`, after `integrations::start(handle.clone());`, add:

```rust
            // Spec §2: local servers are looked for at launch, then only on demand.
            ai::discover_at_launch(handle.clone());
```

- replace `secret_set` and `secret_clear` with these. A key that changed makes the cached "which providers have a key" stale, so the model chip and Auto look at the keychain again:

```rust
#[tauri::command]
fn secret_set(ai: State<ai::AiState>, key: String, value: String) -> Result<(), String> {
    let saved = secrets::set(&key, &value);
    // A key changed: the model chip and Auto must look at the keychain again.
    ai.forget_key_presence();
    saved
}

#[tauri::command]
fn secret_clear(ai: State<ai::AiState>, key: String) -> Result<(), String> {
    let removed = secrets::clear(&key);
    ai.forget_key_presence();
    removed
}
```

Then delete the old client: `git rm windows/src-tauri/src/claude.rs`.

- [ ] **Step 4: Build and test**

Run: `cargo test -p notchmeow ai::tests:: -- --skip openai::`
Expected: `test result: ok. 5 passed; 0 failed`. (`ai::tests::` is also a substring of `ai::openai::tests::`, hence the `--skip`.) They are:
- `one_turn_at_a_time` and `only_inbox_files_are_read_and_their_path_is_kept` (Review Focus 1 and 5);
- `focusing_reads_the_keychain_once_not_every_time`: five focuses make one keychain read, and a saved or removed key makes the next look read again;
- `a_keychain_read_that_raced_a_key_change_is_not_kept`;
- `the_key_check_lists_models_and_says_why_a_key_failed`: against the fake server's `GET /v1/models` (the Anthropic request carries `?limit=100`), a good key gets a list for Claude, OpenAI and Google, and a rejected key, an exhausted credit and an unreachable provider each get their own words ("Your Anthropic key was rejected.", "Your OpenAI credit ran out.", "Couldn't reach OpenAI. Check your connection.").

Run: `cargo build -p notchmeow 2>&1 | grep -A4 "^warning" | grep -c "src/ai/"`
Expected: `0`. Nothing in `ai/` is unused now that the allow is gone.

Run: `cargo test --workspace`
Expected: every `test result:` line says `ok`.

- [ ] **Step 5: The bridge speaks the new commands**

In `windows/src/core/bridge.ts`, make the imports:

```ts
import { Channel, invoke } from "@tauri-apps/api/core";
import { listen } from "@tauri-apps/api/event";
import { getCurrentWebview } from "@tauri-apps/api/webview";
import type { AiAction, Settings } from "./state";
```

Replace the `// ── Chat, files, secrets ──` heading together with the `chatSend` and `chatReset` entries with:

```ts
  // ── AI: chat, models, files, secrets ──────────────────────────────────────
  /**
   * One chat turn, streamed back event by event. Keys and file bytes never
   * leave Rust; `attachments` are inbox paths from `ingestFile`.
   */
  aiChat: (
    feature: Feature,
    text: string,
    attachments: string[],
    regenerate: boolean,
    onEvent: (event: AiEvent) => void,
  ) => {
    const channel = new Channel<AiEvent>();
    channel.onmessage = onEvent;
    return callOrThrow<void>("ai_chat", { feature, text, attachments, regenerate, onEvent: channel });
  },
  /** Stop: cancels the reply on its way. */
  aiCancel: () => call<void>("ai_cancel"),
  /** Checks this computer (and the server the user added) for model servers. */
  aiDiscover: () => call<AiServer[]>("ai_discover"),
  /** A provider's live models. For a cloud provider it is also the key check. */
  aiListModels: (provider: string) => callOrThrow<ModelInfo[]>("ai_list_models", { provider }),
  /** What Auto or the chosen model resolves to right now. No network call. */
  aiResolve: (feature: Feature) => call<Resolution>("ai_resolve", { feature }),
  /** Loads the selected local model before the first message. */
  aiPrewarm: (feature: Feature) => call<void>("ai_prewarm", { feature }),
  /** Starts a new conversation (a file was dropped, or the chat was cleared). */
  chatReset: () => call<void>("chat_reset"),
```

Replace the `export type ChatContext = …;` declaration with:

```ts
export type Feature = "chat" | "files";
export type Placement = "local" | "network" | "cloud";

/** The contract's 12 error kinds (docs/AI-PROVIDERS.md): a provider or the network failed. */
export type ErrorKind =
  | "offline" | "unreachable" | "timeout" | "server" | "rate_limited" | "overloaded"
  | "auth" | "bad_request" | "billing" | "refusal" | "cancelled" | "interrupted";

/**
 * The island's own notices (session::ProblemKind in Rust). NOT contract error kinds: they
 * never come from a provider, and arrive as `problem` events, never as `error` events.
 */
export type ProblemKind =
  | "cant_see" | "scanned_pdf" | "heic" | "rejected" | "unreadable" | "missing_model" | "outdated" | "empty_reply";

/** What `ai_chat` streams — mirrors session::AiEvent in Rust. */
export type AiEvent =
  | { type: "started"; provider: string; model: string; placement: Placement; caption: string; fallback: boolean; waking: string | null }
  | { type: "delta"; text: string }
  | { type: "citation"; url: string; title: string }
  | { type: "notice"; text: string }
  | { type: "done"; text: string; interrupted: boolean; cancelled: boolean }
  | { type: "error"; kind: ErrorKind; message: string; action: AiAction | null; retryAfter: number | null }
  | { type: "problem"; kind: ProblemKind; message: string; action: AiAction | null }
  | { type: "emptyState" };

export interface ModelInfo {
  id: string;
  displayName: string;
  contextTokens: number | null;
  capabilities: { tools: boolean; vision: boolean; json: boolean };
}

export interface AiServer {
  provider: string;
  name: string;
  baseUrl: string;
  host: string;
  placement: Placement;
  status: "running" | "off" | "notInstalled" | "outdated";
  models: ModelInfo[];
  /** Plain http to another computer. */
  unencrypted: boolean;
}

export interface Resolution {
  empty: boolean;
  auto: boolean;
  provider: string | null;
  model: string | null;
  placement: Placement | null;
  modelName: string | null;
  /** The drop card: "Claude", "Local · qwen3.5:2b". */
  reader: string | null;
  /** Auto's local retry: "Local · qwen3.5:2b". */
  fallback: string | null;
}
```

In `windows/src/core/state.ts`, add above `export interface ChatMessage {`:

```ts
/** What a button under a chat note does — mirrors errors::Action in Rust. */
export type AiAction =
  | { kind: "openSettings" }
  | { kind: "openBilling"; url: string }
  | { kind: "openGuide" }
  | { kind: "chooseModel" }
  | { kind: "cancel" };
```

and in `class AppState`, below `droppedFile`:

```ts
  /** The inbox copy of the file just dropped: it goes with the next message, then clears. */
  pendingAttachment: string | null = null;
```

- [ ] **Step 6: Write the check for which setting answers a message**

The file's text stays in the conversation's history, so a follow-up that went to the Chat setting would hand it to whichever model Chat uses, a cloud one included. A conversation that holds a file therefore uses the File questions setting for every message in it.

Create `windows/scripts/check-ai-ui.mjs`:

```js
// Plain-Node checks for the parts of the chat UI that hold logic: no DOM, no framework.
// Needs Node 22.6 or newer, which can read the TypeScript source directly:
//
//   cd windows && npm run check:ai
import assert from "node:assert/strict";
import { featureFor } from "../src/core/feature.ts";

const FILE = "C:\\Users\\Zoé\\AppData\\Local\\NotchMeow\\inbox\\notes.txt";
// A conversation as the chat view keeps it: a user message carries the files it was sent with.
const user = (attachments = []) => ({ role: "user", content: "…", attachments });
const reply = () => ({ role: "assistant", content: "…" });

// No file anywhere in the conversation: Chat.
assert.equal(featureFor([], []), "chat");
assert.equal(featureFor([], [user(), reply(), user(), reply()]), "chat");
console.log("✓ a conversation with no file uses Chat");

// The message that carries a file: File questions.
assert.equal(featureFor([FILE], []), "files");
assert.equal(featureFor([FILE], [user(), reply()]), "files");
console.log("✓ a message that carries a file uses File questions");

// Every later message too: the file's text is still in the history.
const afterTheFile = [user([FILE]), reply()];
assert.equal(featureFor([], afterTheFile), "files");
assert.equal(featureFor([], [...afterTheFile, user(), reply()]), "files");
console.log("✓ a file only on an earlier message still uses File questions");

// A drop or a new chat empties State.chatHistory, and the rule starts over. The decision reads only the
// messages it is given, never State.droppedFile, which is never cleared.
let history = [user([FILE]), reply()];
assert.equal(featureFor([], history), "files");
history = [];
assert.equal(featureFor([], history), "chat");
console.log("✓ after the conversation is reset, a message uses Chat again");

console.log("\nAll AI UI checks passed");
```

In `windows/package.json`, add this to `scripts`, below `"icons"`:

```json
    "check:ai": "node --experimental-strip-types scripts/check-ai-ui.mjs",
```

Run: `cd windows && npm run check:ai`
Expected: FAIL with `Cannot find module` for `src/core/feature.ts`.

- [ ] **Step 7: Write `featureFor`, and let a message remember its files**

Create `windows/src/core/feature.ts`. It imports only a type, so a plain Node script can load it:

```ts
// Which model setting answers a message. No imports besides a type, so the plain-Node
// check in scripts/check-ai-ui.mjs can load this file as it is.

import type { Feature } from "./bridge";

/** What the rule needs from a message of the conversation; `ChatMessage` has it. */
export interface MaybeWithFiles {
  readonly attachments?: readonly string[];
}

/**
 * File questions when the message being sent carries a file or any earlier message of the
 * conversation did; Chat otherwise. A file's text stays in the history, so every follow-up must use
 * the setting the user picked for files: on the Chat route it would reach whichever model Chat uses,
 * a cloud one included.
 *
 * The conversation's own messages decide, never `State.droppedFile`: it is never cleared, so it
 * could not tell a conversation that holds a file from one that doesn't. A drop or a new chat
 * empties `State.chatHistory`, and the rule starts over with it.
 */
export function featureFor(current: readonly string[], history: readonly MaybeWithFiles[]): Feature {
  const carriesFile = (attachments: readonly string[] | undefined) => (attachments?.length ?? 0) > 0;
  return carriesFile(current) || history.some((m) => carriesFile(m.attachments)) ? "files" : "chat";
}
```

In `windows/src/core/state.ts`, add to `ChatMessage`, below `content: string;`:

```ts
  /** User messages: the inbox files this message was sent with. A conversation that holds one keeps using the File questions setting (`featureFor`). */
  attachments?: readonly string[];
```

Run: `cd windows && npm run check:ai`
Expected:

```text
✓ a conversation with no file uses Chat
✓ a message that carries a file uses File questions
✓ a file only on an earlier message still uses File questions
✓ after the conversation is reset, a message uses Chat again

All AI UI checks passed
```

This needs Node 22.6 or newer, which reads the TypeScript source as it is. CI's Node 20 doesn't run it; `tsc --noEmit` still type-checks `feature.ts` and its callers there.

- [ ] **Step 8: The chat streams; the file goes with the message it was dropped on**

In `windows/src/views/chat.ts`:
- change `import { Bridge, type ChatContext } from "../core/bridge";` to `import { Bridge } from "../core/bridge";`, and add `import { featureFor } from "../core/feature";` below it;
- replace everything from `  let sending = false;` down to (not including) `  send.addEventListener("click", () => void submit());` with:

```ts
  let sending = false;
  let renderedKey = "";

  async function submit() {
    const query = input.value.trim();
    if (!query || sending) return;
    input.value = "";
    sending = true;
    Sound.play("send");

    // The dropped file goes with the message it was dropped on, then clears.
    const attachments = State.pendingAttachment ? [State.pendingAttachment] : [];
    State.pendingAttachment = null;
    // This message and the conversation before it decide: once a file is in the conversation, every
    // message uses File questions (Step 7). `State.droppedFile` is never cleared, so it can't be asked.
    const feature = featureFor(attachments, State.chatHistory);
    State.chatHistory.push({ id: nextId++, role: "user", content: query, attachments });
    State.stateOverride = "thinking";
    State.notify();
    onHeightChange();
    const reply: ChatMessage = { id: nextId++, role: "assistant", content: "" };
    let failure = null as string | null;

    try {
      await Bridge.aiChat(feature, query, attachments, false, (e) => {
        if (e.type === "delta") {
          if (!State.chatHistory.includes(reply)) State.chatHistory.push(reply);
          reply.content += e.text;
          State.stateOverride = null;
        } else if (e.type === "done") {
          reply.content = e.text || reply.content;
        } else if (e.type === "error") {
          failure = e.message;
        } else if (e.type === "emptyState") {
          failure = "Add a cloud key in Settings, or start a local model.";
        }
        State.notify();
        onHeightChange();
      });
    } catch (err) {
      failure = String(err).replace(/^Error:\s*/, "");
    }
    State.stateOverride = null;
    if (failure) {
      State.chatHistory = State.chatHistory.filter((m) => m !== reply);
      State.noteMessage = failure;
      State.view = "note";
      Sound.play("error");
    } else {
      if (reply.content && !State.chatHistory.includes(reply)) State.chatHistory.push(reply);
      Sound.play("finish");
    }
    sending = false;
    State.notify();
    onHeightChange();
    input.focus();
  }
```

- in `sync()`, replace the `count` / `renderedCount` comparison with a key that grows with the streaming reply:

```ts
      const thinking = State.stateOverride === "thinking";
      // The last reply grows while it streams, so its length is part of the key.
      const key = `${State.chatHistory.length}:${thinking}:${State.chatHistory.at(-1)?.content.length ?? 0}`;
      if (key !== renderedKey) {
        renderedKey = key;
```

In `windows/src/island/island.ts`, `swallow()`:

```ts
    State.droppedFile = { name, path };
    State.promptContext = { kind: "file", name, path };
    State.pendingAttachment = null;
    State.chatHistory = [];
    void Bridge.chatReset();
```

and in its `ingestFile(path).then(…)`:

```ts
      .then((file) => {
        State.droppedFile = { name: file.name, path: file.path };
        State.promptContext = { kind: "file", name: file.name, path: file.path };
        // The inbox copy goes with the next message, whichever turn that is.
        State.pendingAttachment = file.path;
        State.notify();
      })
```

Run: `cd windows && npx tsc --noEmit && npm run check:ai`
Expected: `tsc` prints nothing, then four `✓` lines and `All AI UI checks passed`.

- [ ] **Step 9: See it stream (Windows or Linux)**

```bash
python3 tests/fake_local_llm.py /tmp/nm-port &
cd windows
NM_AI_BASE_URL_OVERRIDE="http://127.0.0.1:$(cat /tmp/nm-port)" npm run tauri dev
```

On Windows PowerShell, use `$env:NM_AI_BASE_URL_OVERRIDE = "http://127.0.0.1:$(Get-Content $env:TEMP\nm-port)"` with the port file written to `$env:TEMP\nm-port`.

In Settings → Claude, save any text as the key. In the island chat, ask "hi".
Expected: "Cats sleep a lot." appears word by word, not all at once.

Drop a `.txt` file, ask about it, and look at the server's requests (start it with `--log /tmp/nm-log.jsonl` to keep them).
Expected: the last user message contains the file's text.

- [ ] **Step 10: Commit**

```bash
git add -A windows/src-tauri/src windows/src/core windows/src/views/chat.ts windows/src/island/island.ts windows/scripts/check-ai-ui.mjs windows/package.json
git commit -m "feat(ai): Tauri AI commands with a streaming chat channel; claude.rs retired

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 14: Chat UI: model chip, caption, sources, notes, empty state, drop card

**Files:**
- Modify: `windows/src/core/state.ts` (`ChatSource`, the richer `ChatMessage`, `dropReader`)
- Modify: `windows/src/views/views.ts` (`ViewActions.emote`; `buildPrompt(actions, …)`)
- Modify: `windows/src/views/icons.ts` (`stop`)
- Modify: `windows/src/views/chat.ts` (whole file)
- Modify: `windows/src/island/island.ts` (`emote` action; `dropReader`)
- Modify: `windows/src/upload/canvas.ts:277`, `windows/src/views/upload.ts:117-122` (the drop card names the reader)
- Modify: `windows/src/style.css` (append the new chat classes)

**Interfaces:**
- **Consumes:** Task 13's `Bridge.ai*` calls, `AiEvent`, `Resolution` and `AiAction`, and its `featureFor(current, history)` and `ChatMessage.attachments`.
- **Produces:**
  - **Which setting answers:** `featureFor(attachments, State.chatHistory)` in two places. `submit()` asks it for the message being sent, and `nextFeature()` asks it for the model chip, the picker and pre-warming. File questions answer a message that carries a file and every later message of the conversation; Chat answers a conversation with no file. Never `State.droppedFile`, which is never cleared.
  - **The chat:**
    - streaming replies;
    - a caption under each reply;
    - source links;
    - lines for notices;
    - error notes with at most one action (Open Settings, Open billing page, Open guide, Choose model, Cancel);
    - a 1 s countdown that sends again by itself up to 3 times;
    - "interrupted" with Continue and Retry;
    - Stop;
    - "Waking up …" with a yawn after 1.5 s of silence from a local model;
    - the model chip and its picker (Auto, Cloud, Local);
    - the empty state, and a guide with Ollama and LM Studio links and Rescan;
    - `error` events (a provider or the network failed) and `problem` events (the island's own notices, such as a file it can't read or an empty reply) shown the same way: a note and the error sound. Only a reply with text plays the finish sound.
  - **The drop cards:** "Claude will read this." / "Local · qwen3.5:2b will read this."

- [ ] **Step 1: Richer chat messages**

At the top of `windows/src/core/state.ts`, above the `layout` import, add:

```ts
import type { Feature } from "./bridge";
```

In `windows/src/core/state.ts`, add above the `AiAction` type:

```ts
export interface ChatSource {
  url: string;
  title: string;
}
```

Replace `ChatMessage` with:

```ts
export interface ChatMessage {
  id: number;
  /** `note`: a line from NotchMeow itself (an error, a countdown), not from the model. */
  role: "user" | "assistant" | "note";
  content: string;
  /** User messages: the inbox files this message was sent with. A conversation that holds one keeps using the File questions setting (`featureFor`). */
  attachments?: readonly string[];
  /** Under a reply: "cloud · Claude Sonnet 5.5", "local · qwen3.5:2b". */
  caption?: string;
  /** Web-search sources, shown as links under the reply. */
  sources?: ChatSource[];
  /** Lines under the reply: a cut file, trimmed history, a fallback. */
  notices?: string[];
  /** `interrupted`: the stream broke; `stopped`: Stop was pressed. */
  status?: "streaming" | "interrupted" | "stopped";
  /** The one button a note may carry. */
  action?: AiAction | null;
  /** Under a reply: the setting that answered, so Continue and Retry use it again. */
  feature?: Feature;
}
```

and in `class AppState`, below `pendingAttachment`:

```ts
  /** The drop card's "… will read this": "Claude", "Local · qwen3.5:2b". */
  dropReader: string | null = null;
```

- [ ] **Step 2: Views can ask the cat for a face; Stop has an icon**

In `windows/src/views/views.ts`:
- change the layout import to `import { washRGBA, type BotEmoteName, type IslandViewName, type Wash } from "../core/layout";`;
- add to `ViewActions`, after `blip(): void;`:

```ts
  /** A one-off face from the cat, e.g. a yawn while a local model wakes up. */
  emote(name: BotEmoteName): void;
```

- change `map.set("prompt", buildPrompt(onChatHeightChange));` to `map.set("prompt", buildPrompt(actions, onChatHeightChange));`.

In `windows/src/views/icons.ts`, after `arrowUp`:

```ts
  // stop.fill (Stop while a reply streams)
  stop: "M7 7h10v10H7z",
```

In `windows/src/island/island.ts`, in the `actions` object, after `blip: () => Sound.play("blip"),`:

```ts
      emote: (name) => this.engine.triggerEmote(name),
```

- [ ] **Step 3: The chat view**

Replace `windows/src/views/chat.ts` with:

```ts
// Chat view — DOM port of PromptView / ChatBubble / TypingDotsView from
// IslandViewContent.swift, plus the AI layer's parts: the model chip, streamed
// replies with their caption and sources, notes with one action, and the empty
// state. Every model call goes through Rust (`Bridge.aiChat`).

import { h, svg, clear } from "./dom";
import { ICONS } from "./icons";
import { Bridge, type AiEvent, type AiServer, type Feature, type Resolution } from "../core/bridge";
import { featureFor } from "../core/feature";
import { Sound } from "../core/sound";
import { State, type AiAction, type ChatMessage, type ModelChoice } from "../core/state";
import type { ViewActions, ViewHost } from "./views";

let nextId = 1;

/** How many times a busy cloud is retried on its own before the note just waits. */
const MAX_AUTO_RETRIES = 3;
/** A local model that hasn't said a word by now is probably loading. */
const WAKING_AFTER_MS = 1500;

const CLOUD: { id: string; name: string; key: string }[] = [
  { id: "anthropic", name: "Claude", key: "anthropic-api-key" },
  { id: "openai", name: "OpenAI", key: "openai-api-key" },
  { id: "google", name: "Google", key: "google-api-key" },
];

const GUIDE_LINKS: [string, string][] = [
  ["Ollama", "https://ollama.com/download"],
  ["LM Studio", "https://lmstudio.ai"],
];

/** What the next message will carry: the file dropped on it, if one is waiting. */
function pendingAttachments(): string[] {
  return State.pendingAttachment ? [State.pendingAttachment] : [];
}

/**
 * The setting the next message will use, for the model chip, the picker and pre-warming: File
 * questions while a dropped file is waiting to go with it and for the rest of a conversation that
 * holds a file, Chat otherwise. The conversation's messages decide, never `State.droppedFile`,
 * which is never cleared.
 */
function nextFeature(): Feature {
  return featureFor(pendingAttachments(), State.chatHistory);
}

function typingDots(): HTMLElement {
  return h(
    "div",
    { class: "chat-row" },
    h("div", { class: "typing" }, h("i"), h("i"), h("i")),
  );
}

/** The coloured chip showing what the question is about (a dropped file). */
function contextChip(label: string): HTMLElement {
  const chip = h("div", { class: "chip" }, h("i", { class: "chip-dot" }), h("span", { text: label }));
  requestAnimationFrame(() => chip.classList.add("settled"));
  return chip;
}

function chipLabel(r: Resolution | null): string {
  if (!r || r.empty) return "No model yet";
  const name = r.modelName ?? r.provider ?? "";
  return r.auto ? `Auto · ${name}` : name;
}

function sameChoice(a: ModelChoice, b: ModelChoice): boolean {
  if (a === "auto" || b === "auto") return a === b;
  return a.provider === b.provider && a.model === b.model;
}

export function buildPrompt(actions: ViewActions, onHeightChange: () => void): ViewHost {
  const chipRow = h("div", { class: "chip-row" });
  const fileChipSlot = h("span", {});
  const modelChip = h("button", { class: "chip model-chip", title: "Which model answers" });
  chipRow.append(fileChipSlot, modelChip);
  const log = h("div", { class: "chat-log" });
  const picker = h("div", { class: "model-picker" });
  const input = h("input", {
    type: "text",
    class: "chat-input",
    placeholder: "Ask me anything…",
    spellcheck: "false",
  }) as HTMLInputElement;
  const send = h("button", { class: "send-btn", title: "Send" }, svg(ICONS.arrowUp, 11));
  const bar = h("div", { class: "chat-bar" }, input, send);

  const el = h(
    "div",
    { class: "view" },
    h("div", { class: "card wash chat-card" }, h("div", { class: "chat-body" }, chipRow, log, picker, bar)),
  );
  (el.querySelector(".card") as HTMLElement).style.setProperty("--wash", "rgba(99,102,241,0.5)");

  let sending = false;
  let renderedKey = "";
  let resolution: Resolution | null = null;
  let showGuide = false;
  let pickerOpen = false;
  let countdown: { note: ChatMessage; left: number; timer: number } | null = null;

  async function refreshModel() {
    resolution = await Bridge.aiResolve(nextFeature());
    modelChip.textContent = chipLabel(resolution);
    State.notify();
  }

  function stopCountdown() {
    if (!countdown) return;
    window.clearInterval(countdown.timer);
    State.chatHistory = State.chatHistory.filter((m) => m !== countdown!.note);
    countdown = null;
  }

  function note(content: string, action: AiAction | null = null): ChatMessage {
    const m: ChatMessage = { id: nextId++, role: "note", content, action };
    State.chatHistory.push(m);
    return m;
  }

  function runAction(action: AiAction) {
    switch (action.kind) {
      case "openSettings":
        actions.openSettingsWindow();
        break;
      case "openBilling":
        actions.openUrl(action.url);
        break;
      case "openGuide":
        showGuide = true;
        break;
      case "chooseModel":
        void openPicker();
        break;
      case "cancel":
        stopCountdown();
        break;
    }
    State.notify();
    onHeightChange();
  }

  interface Ask {
    text: string;
    attachments: string[];
    feature: Feature;
    regenerate: boolean;
    retries: number;
  }

  async function ask(req: Ask) {
    if (sending) return;
    sending = true;
    stopCountdown();
    showGuide = false;
    const reply: ChatMessage = {
      id: nextId++, role: "assistant", content: "", status: "streaming", sources: [], notices: [], feature: req.feature,
    };
    let waking = 0;
    State.stateOverride = "thinking";
    State.notify();
    onHeightChange();

    const settle = () => {
      if (State.stateOverride === "thinking") State.stateOverride = null;
      window.clearTimeout(waking);
    };

    const onEvent = (e: AiEvent) => {
      switch (e.type) {
        case "started":
          reply.caption = e.caption;
          if (!State.chatHistory.includes(reply)) State.chatHistory.push(reply);
          window.clearTimeout(waking);
          if (e.waking) {
            const line = e.waking;
            waking = window.setTimeout(() => {
              if (reply.content) return;
              reply.notices = [...(reply.notices ?? []), line];
              actions.emote("yawn");
              State.notify();
            }, WAKING_AFTER_MS);
          }
          break;
        case "delta":
          reply.content += e.text;
          settle();
          break;
        case "citation":
          if (!reply.sources?.some((s) => s.url === e.url)) reply.sources = [...(reply.sources ?? []), { url: e.url, title: e.title }];
          break;
        case "notice":
          if (!reply.notices?.includes(e.text)) reply.notices = [...(reply.notices ?? []), e.text];
          break;
        case "done":
          settle();
          reply.content = e.text || reply.content;
          reply.status = e.interrupted ? "interrupted" : e.cancelled ? "stopped" : undefined;
          // Drop the "waking up" line once the model has spoken.
          reply.notices = (reply.notices ?? []).filter((n) => !n.startsWith("Waking up"));
          if (!reply.content) State.chatHistory = State.chatHistory.filter((m) => m !== reply);
          // An empty reply never gets here (Rust sends a problem instead), but the sound is the last thing to trust.
          if (!e.cancelled && !e.interrupted && reply.content.trim()) Sound.play("finish");
          break;
        // `error`: a provider or the network failed. `problem`: the island's own notice (a file it
        // can't read, an empty reply). Both are shown the same way: a note and the error sound.
        case "problem":
        case "error": {
          settle();
          State.chatHistory = State.chatHistory.filter((m) => m !== reply);
          Sound.play("error");
          // The cat shows its error face once; it never loops on an error.
          State.stateOverride = "error";
          window.setTimeout(() => {
            if (State.stateOverride === "error") State.stateOverride = null;
            State.notify();
          }, 1500);
          const n = note(e.message, e.action);
          const wait = e.type === "error" ? e.retryAfter : null;
          if (wait != null && req.retries < MAX_AUTO_RETRIES) {
            const left = wait;
            const timer = window.setInterval(() => {
              if (!countdown) return;
              countdown.left -= 1;
              n.content = e.message.replace(/in \d+ s\./, `in ${countdown.left} s.`);
              if (countdown.left <= 0) {
                stopCountdown();
                void ask({ ...req, retries: req.retries + 1 });
              }
              State.notify();
            }, 1000);
            countdown = { note: n, left, timer };
          } else if (wait != null) {
            n.action = null;
          }
          break;
        }
        case "emptyState": {
          settle();
          // Nothing could answer: take the message back so it isn't lost, and show the way out.
          State.chatHistory = State.chatHistory.filter((m) => m !== reply);
          const last = State.chatHistory.at(-1);
          if (last?.role === "user" && last.content === req.text) {
            State.chatHistory.pop();
            input.value = req.text;
          }
          resolution = { ...(resolution ?? ({} as Resolution)), empty: true };
          break;
        }
      }
      State.notify();
      onHeightChange();
    };

    try {
      await Bridge.aiChat(req.feature, req.text, req.attachments, req.regenerate, onEvent);
    } catch (err) {
      settle();
      State.chatHistory = State.chatHistory.filter((m) => m !== reply);
      note(String(err).replace(/^Error:\s*/, ""));
      Sound.play("error");
    } finally {
      settle();
      sending = false;
      State.notify();
      onHeightChange();
      input.focus();
      void refreshModel();
    }
  }

  function submit() {
    if (sending) {
      void Bridge.aiCancel();
      return;
    }
    const text = input.value.trim();
    if (!text) return;
    input.value = "";
    Sound.play("send");
    const attachments = pendingAttachments();
    State.pendingAttachment = null;
    // This message and the conversation before it decide: once a file is in the conversation, every
    // message uses File questions, so the file's text never reaches a model the user didn't pick for files.
    const feature = featureFor(attachments, State.chatHistory);
    State.chatHistory.push({ id: nextId++, role: "user", content: text, attachments });
    void ask({ text, attachments, feature, regenerate: false, retries: 0 });
  }

  function continueOrRetry(m: ChatMessage, how: "continue" | "retry") {
    // Both belong to the reply they extend, so they use the setting that reply used.
    const feature = m.feature ?? "chat";
    if (how === "continue") {
      State.chatHistory.push({ id: nextId++, role: "user", content: "Continue" });
      void ask({ text: "Continue", attachments: [], feature, regenerate: false, retries: 0 });
    } else {
      State.chatHistory = State.chatHistory.filter((x) => x !== m);
      void ask({ text: "", attachments: [], feature, regenerate: true, retries: 0 });
    }
  }

  // ── Model picker ────────────────────────────────────────────────────────────

  async function openPicker() {
    pickerOpen = true;
    clear(picker);
    picker.append(h("div", { class: "picker-head", text: "Looking for models…" }));
    State.notify();
    onHeightChange();
    const [servers, keyed] = await Promise.all([
      Bridge.aiDiscover(),
      Promise.all(CLOUD.map(async (c) => ((await Bridge.secretPresent(c.key)) ? c : null))),
    ]);
    const clouds = keyed.filter((c): c is (typeof CLOUD)[number] => c !== null);
    const lists = await Promise.all(
      clouds.map(async (c) => ({ c, models: await Bridge.aiListModels(c.id).catch(() => []) })),
    );
    renderPicker(lists, servers ?? []);
  }

  function renderPicker(
    clouds: { c: (typeof CLOUD)[number]; models: { id: string; displayName: string }[] }[],
    servers: AiServer[],
  ) {
    clear(picker);
    const f = nextFeature();
    const current = State.settings.ai[f];
    const option = (label: string, choice: ModelChoice) =>
      h("button", {
        class: sameChoice(current, choice) ? "picker-item on" : "picker-item",
        text: label,
        onclick: () => {
          State.settings.ai = { ...State.settings.ai, [f]: choice };
          void Bridge.saveSettings(State.settings);
          pickerOpen = false;
          void refreshModel();
          onHeightChange();
        },
      });
    picker.append(option("Auto", "auto"));
    if (clouds.length) picker.append(h("div", { class: "picker-head", text: "Cloud" }));
    for (const { c, models } of clouds) {
      for (const m of models) picker.append(option(`${c.name} · ${m.displayName}`, { provider: c.id, model: m.id }));
    }
    const running = servers.filter((s) => s.status === "running" && s.models.length);
    if (running.length) picker.append(h("div", { class: "picker-head", text: "Local" }));
    for (const s of running) {
      for (const m of s.models) picker.append(option(`${s.name} · ${m.id}`, { provider: s.provider, model: m.id }));
    }
    State.notify();
    onHeightChange();
  }

  modelChip.addEventListener("click", () => {
    if (pickerOpen) {
      pickerOpen = false;
      State.notify();
      onHeightChange();
    } else {
      void openPicker();
    }
  });

  // ── Rendering ───────────────────────────────────────────────────────────────

  function smallButton(label: string, onclick: () => void): HTMLElement {
    return h("button", { class: "note-btn", text: label, onclick });
  }

  function actionLabel(a: AiAction): string {
    switch (a.kind) {
      case "openSettings": return "Open Settings";
      case "openBilling": return "Open billing page";
      case "openGuide": return "Open guide";
      case "chooseModel": return "Choose model";
      case "cancel": return "Cancel";
    }
  }

  function bubble(m: ChatMessage): HTMLElement {
    if (m.role === "user") {
      return h("div", { class: "chat-row user" }, h("div", { class: "bubble", text: m.content }));
    }
    if (m.role === "note") {
      const action = m.action;
      return h(
        "div",
        { class: "chat-row" },
        h("div", { class: "chat-note" }, h("span", { text: m.content }), action ? smallButton(actionLabel(action), () => runAction(action)) : null),
      );
    }
    const col = h("div", { class: "reply-col" }, h("div", { class: "reply", text: m.content }));
    if (m.status === "interrupted") {
      col.append(
        h("div", { class: "reply-meta" }, h("span", { text: "interrupted" }),
          smallButton("Continue", () => continueOrRetry(m, "continue")),
          smallButton("Retry", () => continueOrRetry(m, "retry"))),
      );
    }
    for (const n of m.notices ?? []) col.append(h("div", { class: "reply-meta", text: n }));
    if (m.sources?.length) {
      const links = h("div", { class: "reply-sources" });
      for (const s of m.sources) {
        links.append(h("a", { href: s.url, text: s.title || s.url, onclick: (e: Event) => {
          e.preventDefault();
          actions.openUrl(s.url);
        } }));
      }
      col.append(links);
    }
    if (m.caption) col.append(h("div", { class: "reply-caption", text: m.caption }));
    return h("div", { class: "chat-row" }, col);
  }

  function emptyState(): HTMLElement {
    return h(
      "div",
      { class: "empty-state" },
      h("button", { class: "btn primary", text: "Add a cloud key", onclick: () => actions.openSettingsWindow() }),
      h("button", { class: "btn secondary", text: "Use a local model", onclick: () => { showGuide = true; State.notify(); } }),
    );
  }

  function guide(): HTMLElement {
    const links = GUIDE_LINKS.map(([name, url]) =>
      h("a", { href: url, text: name, onclick: (e: Event) => { e.preventDefault(); actions.openUrl(url); } }),
    );
    return h(
      "div",
      { class: "chat-note guide" },
      h("span", {}, "Install ", links[0], " or ", links[1], ", start it and download a model, then rescan."),
      smallButton("Rescan", async () => {
        await Bridge.aiDiscover();
        showGuide = false;
        await refreshModel();
      }),
    );
  }

  send.addEventListener("click", () => submit());
  input.addEventListener("keydown", (e) => {
    if ((e as KeyboardEvent).key === "Enter") {
      e.preventDefault();
      submit();
    }
    e.stopPropagation(); // Escape closes the island, not the chat
  });

  return {
    el,
    sync() {
      const file = State.droppedFile;
      const wantChip = file?.name ?? "";
      if (fileChipSlot.dataset.label !== wantChip) {
        fileChipSlot.dataset.label = wantChip;
        clear(fileChipSlot);
        if (wantChip) fileChipSlot.append(contextChip(wantChip));
      }

      const thinking = State.stateOverride === "thinking";
      const empty = !!resolution?.empty;
      const key = [
        thinking, empty, showGuide,
        // A note's text can change at the same length (a countdown), so notes key on their text.
        ...State.chatHistory.map((m) =>
          `${m.id}:${m.role === "note" ? m.content : m.content.length}:${m.status ?? ""}:${m.caption ?? ""}:${m.sources?.length ?? 0}:${m.notices?.length ?? 0}:${m.action?.kind ?? ""}`),
      ].join("|");
      if (key !== renderedKey) {
        renderedKey = key;
        clear(log);
        for (const m of State.chatHistory) {
          if (m.role === "assistant" && !m.content && thinking) continue;
          log.append(bubble(m));
        }
        if (thinking) log.append(typingDots());
        if (empty && !showGuide) log.append(emptyState());
        if (showGuide) log.append(guide());
        log.scrollTop = log.scrollHeight;
      }

      picker.style.display = pickerOpen ? "" : "none";
      const mode = sending ? "stop" : "send";
      if (send.dataset.mode !== mode) {
        send.dataset.mode = mode;
        send.replaceChildren(svg(sending ? ICONS.stop : ICONS.arrowUp, 11));
        send.title = sending ? "Stop" : "Send";
      }
      input.placeholder = State.chatHistory.length === 0 ? "Ask me anything…" : "Continue…";
      input.disabled = sending;
    },
    focus() {
      input.focus();
      input.select();
      void refreshModel();
      void Bridge.aiPrewarm(nextFeature());
    },
  };
}
```

- [ ] **Step 4: The drop card says who will read the file**

In `island.ts` `swallow()`, add `State.dropReader = null;` after `State.pendingAttachment = null;`. Then make the `ingestFile` callback:

```ts
      .then(async (file) => {
        State.droppedFile = { name: file.name, path: file.path };
        State.promptContext = { kind: "file", name: file.name, path: file.path };
        // The inbox copy goes with the next message, whichever turn that is.
        State.pendingAttachment = file.path;
        State.notify();
        const reader = await Bridge.aiResolve("files");
        State.dropReader = reader?.reader ?? null;
        State.notify();
      })
```

In `windows/src/upload/canvas.ts`, `drawChoose`, replace the "What do you want to do with it?" line with:

```ts
    const sub = State.dropReader ? `${State.dropReader} will read this.` : "What do you want to do with it?";
    text(ctx, sub, 114, 100, `400 12.5px ${FONT}`, "#9398A1");
```

In `windows/src/views/upload.ts`, `buildChoose`'s `sync()`, after the title is filled:

```ts
      // Dropping is consent, file by file: say which model will read it.
      sub.textContent = State.dropReader ? `${State.dropReader} will read this.` : "What do you want to do with it?";
```

The position, font and colour are the same as before; only the words change.

- [ ] **Step 5: Styles for the new parts**

Append to `windows/src/style.css`:

```css

/* ── AI: model chip, picker, reply caption, sources, notes ─────────────── */

.chip-row {
  display: flex;
  align-items: center;
  gap: 6px;
}

/* The model chip reuses .chip; it is a button, so it settles at once. */
.model-chip {
  margin-left: auto;
  border-color: rgba(255, 255, 255, 0);
  transform: none;
  cursor: default;
}

.model-chip:hover {
  background: rgba(255, 255, 255, 0.16);
}

.model-picker {
  display: flex;
  flex-direction: column;
  gap: 2px;
  max-height: 120px;
  overflow-y: auto;
  padding: 4px;
  border-radius: 10px;
  background: rgba(255, 255, 255, 0.06);
  scrollbar-width: thin;
  scrollbar-color: rgba(255, 255, 255, 0.18) transparent;
}

.picker-head {
  padding: 4px 6px 2px;
  font: 600 10.5px var(--font);
  letter-spacing: 0.04em;
  text-transform: uppercase;
  color: var(--dim-3);
}

.picker-item {
  border: 0;
  border-radius: 6px;
  padding: 4px 6px;
  background: transparent;
  color: var(--ink-2);
  font: 400 12px var(--font);
  text-align: left;
  cursor: default;
}

.picker-item:hover,
.picker-item.on {
  background: rgba(255, 255, 255, 0.1);
}

.reply-col {
  display: flex;
  flex-direction: column;
  gap: 3px;
  min-width: 0;
}

.reply-caption,
.reply-meta {
  display: flex;
  align-items: center;
  gap: 6px;
  font: 400 10.5px var(--font);
  color: var(--dim-3);
}

.reply-sources {
  display: flex;
  flex-wrap: wrap;
  gap: 2px 10px;
}

.reply-sources a,
.chat-note a {
  font: 400 11px var(--font);
  color: #9db4ff;
  text-decoration: none;
  cursor: pointer;
}

.reply-sources a:hover,
.chat-note a:hover {
  text-decoration: underline;
}

.chat-note {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
  padding: 6px 10px;
  border-radius: 10px;
  background: rgba(255, 255, 255, 0.06);
  font: 400 12px var(--font);
  color: #c8ccd3;
}

.note-btn {
  border: 0;
  border-radius: 999px;
  padding: 3px 10px;
  background: rgba(255, 255, 255, 0.14);
  color: var(--ink);
  font: 500 11px var(--font);
  cursor: default;
}

.note-btn:active {
  transform: scale(0.94);
}

.empty-state {
  display: flex;
  gap: 8px;
  padding: 6px 0;
}
```

- [ ] **Step 6: Type-check**

Run: `cd windows && npx tsc --noEmit && npm run check:ai`
Expected: `tsc` prints nothing, then four `✓` lines and `All AI UI checks passed`.

- [ ] **Step 7: Walk through it (Windows or Linux)**

Start the fake server and the app as in Task 13, Step 9. Expected for each case:
1. **Ask "hi" with a key saved.** The reply streams; `cloud · claude-sonnet-5-5` sits under it; "Cat sleep facts" is a link that opens in the browser.
2. **Restart the server with `--fail 429` and ask again.** The note reads "Claude is busy. Trying again in 2 s." with Cancel. It counts down and sends again by itself; Cancel stops it.
3. **Restart with `--fail 401`.** "Your Anthropic key was rejected." with Open Settings, which opens the settings window.
4. **Restart with `--fail cut` and use a local server.** The partial reply stays, with "interrupted" and Continue / Retry.
5. **Restart with `--fail slow-first-token --delay 5`.** Press the square Stop: the typing dots go and the input comes back.
6. **Remove the key, with no local server running.** "Add a cloud key" and "Use a local model" show. The second shows the guide with the Ollama and LM Studio links and Rescan.
7. **Click the model chip.** The picker lists Auto, then Cloud and Local models. Picking one updates the chip ("Auto · …" or the model name).
8. **Drop a `.txt` file.** The card reads "Claude will read this." (or "Local · <model> will read this.").
9. **Drop a `.zip`.** The note reads "I can't read this kind of file." with the error sound.
10. **Drop a `.txt`, ask about it, then ask a plain follow-up.** Both messages go to the File questions setting: with Chat and File questions set to different models in Settings, both replies' captions show the File questions model, and so does the chip. Dropping another file starts a new conversation, and a chat with no file uses Chat again.
11. **Drop a `.heic` file (any file with that extension) and ask about it.** The note reads "HEIC photos aren't supported yet. Export it as JPEG or PNG." with the error sound; nothing reaches the fake server.
12. **A file's text never reaches the cloud on a follow-up.** Start a second fake server (`python3 tests/fake_local_llm.py /tmp/nm-port2 --persona ollama --log /tmp/nm-local.jsonl`), add `http://127.0.0.1:<its port>` with Settings → AI → Add server…, and set Chat to Claude and File questions to that server's model. Drop a `.txt` that contains the word QUOKKAMARKER, ask about it, then ask "And what else?". Both captions read `local · …`, and the cloud server's log (`--log /tmp/nm-log.jsonl`) holds no QUOKKAMARKER: `grep -c QUOKKAMARKER /tmp/nm-log.jsonl` prints `0`.

- [ ] **Step 8: Commit**

```bash
git add windows/src windows/scripts/check-ai-ui.mjs windows/package.json
git commit -m "feat(ai): chat model chip, reply captions, sources, actionable errors, drop card reader

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 15: Settings window: the AI section, and the README

**Files:**
- Modify: `windows/src/settings/main.ts` (`apiSection` → `aiSection`; imports; `main()`)
- Modify: `windows/src/settings/settings.css` (append)
- Modify: `windows/README.md` (intro, AI, files, log, layout, platform differences, testing)

**Interfaces:**
- **Consumes:** `Bridge.aiDiscover`, `aiListModels`, `aiResolve`, `secretPresent`, `secretSet`, `secretClear` and `saveSettings`; the types `AiServer`, `ModelInfo` and `Feature`; `State` types `AiSettings` and `ModelChoice`.
- **Produces:** the **AI** section, with three boxes.
  - **Which model answers:** Chat and File questions, each with Auto, Cloud or Local options and a line saying what Auto resolves to. A Preferred cloud row appears when both the Claude and OpenAI keys exist.
  - **Cloud providers:** one block each for Claude, Google and OpenAI. Each block is the shipping Claude section's key field, unchanged: the heading with its status dot, the "Key saved in the Windows Credential Manager." line, the `API key` row (`Save key`, `Remove`) and the `Saved. It never touches disk.` / `Key removed.` / `Could not save: …` notices, with the same elements and classes. The only addition is the ✓ / ✗ of the model-list call that checks a pasted key.
  - **Local models:** one row per server with a status dot, plus Rescan and Add server…. The added server is stored in `ai.customServer` (Rust drops any `user:pass@`), with its key in `custom-server-key.default`: the contract's `custom-server-key.<serverId>`, with the one id this window uses.
  - **When it looks:** nothing at launch, because this window is created hidden (spec §2: no network calls then, and never on a timer). The servers, and any cloud model list that is missing or older than 10 minutes, are refreshed when the window is shown or regains focus. The two events arrive together, so one refresh runs at a time and not twice within a second.

  The fixed three-model list is gone.

- [ ] **Step 1: The AI section**

In `windows/src/settings/main.ts`, replace everything from `// ── Claude API section ──` down to (not including) `// ── Integrations section ──` with:

```ts
// ── AI section ────────────────────────────────────────────────────────────────
//
// Three boxes (spec §4): which model answers each feature, the cloud keys, and
// the model servers on this computer. Model lists are live; nothing is fixed.
// Nothing is looked for while this window is hidden at launch (spec §2): the
// servers and the model lists are refreshed when the window opens or regains focus.

const CLOUD_PROVIDERS = [
  { id: "anthropic", name: "Anthropic", brand: "Claude", key: "anthropic-api-key", placeholder: "sk-ant-..." },
  { id: "google", name: "Google", brand: "Google", key: "google-api-key", placeholder: "AIza..." },
  { id: "openai", name: "OpenAI", brand: "OpenAI", key: "openai-api-key", placeholder: "sk-..." },
] as const;

const FEATURES: { id: Feature; label: string }[] = [
  { id: "chat", label: "Chat" },
  { id: "files", label: "File questions" },
];

/** The added server's keychain item: the contract's `custom-server-key.<serverId>` (the id matches
 *  `^[a-z0-9-]{1,32}$`), with the one id this window offers. Rust pins the same string in
 *  `catalog::keychain_name("custom")`, and `secrets.rs` refuses the bare `custom-server-key`. */
const CUSTOM_KEY = "custom-server-key.default";

/** A cloud model list older than this is fetched again when the window regains focus. */
const MODEL_LIST_MAX_AGE_MS = 10 * 60 * 1000;

function serverStatus(s: AiServer): { ok: boolean; text: string } {
  switch (s.status) {
    case "running": {
      const n = s.models.length;
      return { ok: true, text: `Running · ${n} model${n === 1 ? "" : "s"}` };
    }
    case "off": return { ok: false, text: "Server off" };
    case "notInstalled": return { ok: false, text: "Not installed" };
    case "outdated": return { ok: false, text: `Update ${s.name} to use it here.` };
  }
}

function choiceValue(c: ModelChoice): string {
  return c === "auto" ? "auto" : JSON.stringify(c);
}

function aiSection(present: Record<string, boolean>): HTMLElement {
  const which = h("div", { class: "ai-box" });
  const clouds = h("div", { class: "ai-box" });
  const locals = h("div", { class: "ai-box" });
  let servers: AiServer[] = [];
  const models: Record<string, ModelInfo[]> = {};
  const loadedAt: Record<string, number> = {};

  /** The provider's live models. A failure forgets the list, so the next focus tries again. */
  async function loadCloud(id: string) {
    try {
      models[id] = await Bridge.aiListModels(id);
      loadedAt[id] = Date.now();
    } catch {
      delete models[id];
    }
  }

  async function refresh() {
    servers = (await Bridge.aiDiscover()) ?? [];
    const stale = (id: string) => !models[id] || Date.now() - (loadedAt[id] ?? 0) > MODEL_LIST_MAX_AGE_MS;
    await Promise.all(CLOUD_PROVIDERS.filter((p) => present[p.key] && stale(p.id)).map((p) => loadCloud(p.id)));
    await drawWhich();
    drawLocals();
  }

  // 1. Which model answers.
  async function drawWhich() {
    clear(which);
    which.append(h("h3", { text: "Which model answers" }));
    for (const f of FEATURES) {
      const select = h("select", {}) as HTMLSelectElement;
      select.append(h("option", { value: "auto", text: "Auto" }));
      const cloud = h("optgroup", { label: "Cloud" });
      for (const p of CLOUD_PROVIDERS) {
        if (!present[p.key]) continue;
        for (const m of models[p.id] ?? []) {
          cloud.append(h("option", { value: choiceValue({ provider: p.id, model: m.id }), text: `${p.brand} · ${m.displayName}` }));
        }
      }
      if (cloud.children.length) select.append(cloud);
      for (const s of servers.filter((x) => x.status === "running" && x.models.length)) {
        const group = h("optgroup", { label: `Local · ${s.name}` });
        for (const m of s.models) group.append(h("option", { value: choiceValue({ provider: s.provider, model: m.id }), text: m.id }));
        select.append(group);
      }
      const current = choiceValue(settings.ai[f.id]);
      if (![...select.options].some((o) => o.value === current)) {
        const c = settings.ai[f.id];
        if (c !== "auto") select.append(h("option", { value: current, text: `${c.model} (not available now)` }));
      }
      select.value = current;
      select.addEventListener("change", async () => {
        const choice: ModelChoice = select.value === "auto" ? "auto" : JSON.parse(select.value);
        settings.ai = { ...settings.ai, [f.id]: choice };
        await save();
        void drawWhich();
      });
      const line = h("div", { class: "hint" });
      which.append(h("div", { class: "row" }, h("label", { text: f.label }), select), line);
      void Bridge.aiResolve(f.id).then((r) => {
        if (!r) return;
        if (r.empty) line.textContent = "No model yet: add a cloud key or start a local model.";
        else if (r.auto) line.textContent = `${r.modelName ?? r.provider}${r.fallback ? ` · falls back to ${r.fallback}` : ""}`;
        else line.textContent = "";
      });
    }
    // Preferred cloud: only when both Claude and OpenAI have a key.
    if (present["anthropic-api-key"] && present["openai-api-key"]) {
      const pref = h("select", {}) as HTMLSelectElement;
      pref.append(h("option", { value: "anthropic", text: "Claude" }), h("option", { value: "openai", text: "OpenAI" }));
      pref.value = settings.ai.preferredCloud;
      pref.addEventListener("change", async () => {
        settings.ai = { ...settings.ai, preferredCloud: pref.value as AiSettings["preferredCloud"] };
        await save();
        void drawWhich();
      });
      which.append(h("div", { class: "row" }, h("label", { text: "Preferred cloud" }), pref));
    }
  }

  // 2. Cloud providers. Each key is the Claude section as it shipped (a status dot, the
  // "Key saved…" line, the key row and its notices), once per provider; the only addition
  // is the ✓ / ✗ of the model-list call that checks a pasted key.
  function providerKey(p: (typeof CLOUD_PROVIDERS)[number]): HTMLElement {
    const hasKey = present[p.key] ?? false;
    const dot = statusDot(hasKey);
    const state = h("span", { class: "hint", text: hasKey ? "Key saved in the Windows Credential Manager." : "No key yet — the chat needs one." });

    const field = h("input", {
      type: "password",
      placeholder: hasKey ? "••••••••••••  (stored)" : p.placeholder,
      style: "flex:1 1 auto;min-width:0",
      autocomplete: "off",
      spellcheck: "false",
    }) as HTMLInputElement;

    const saveBtn = h("button", { class: "primary", text: "Save key" });
    const clearBtn = h("button", { class: "danger", text: "Remove" });
    const check = h("span", { class: "check" });
    const feedback = h("div", {});

    async function refreshKey() {
      const now = (await Bridge.secretPresent(p.key)) ?? false;
      present[p.key] = now;
      dot.style.background = now ? "#22c55e" : "#f4505e";
      state.textContent = now
        ? "Key saved in the Windows Credential Manager."
        : "No key yet — the chat needs one.";
      field.placeholder = now ? "••••••••••••  (stored)" : p.placeholder;
      clearBtn.style.display = now ? "" : "none";
    }

    saveBtn.addEventListener("click", async () => {
      const value = field.value.trim();
      if (!value) return;
      clear(feedback);
      check.textContent = "";
      try {
        await Bridge.secretSet(p.key, value);
        field.value = "";
        feedback.append(h("div", { class: "notice ok", text: "Saved. It never touches disk." }));
        await refreshKey();
      } catch (err) {
        feedback.append(h("div", { class: "notice err", text: `Could not save: ${String(err)}` }));
        return;
      }
      // A pasted key is checked straight away with a model-list call.
      check.textContent = "Checking…";
      check.className = "check";
      try {
        models[p.id] = await Bridge.aiListModels(p.id);
        loadedAt[p.id] = Date.now();
        check.textContent = "✓";
        check.className = "check ok";
      } catch (err) {
        check.textContent = `✗ ${String(err).replace(/^Error:\s*/, "")}`;
        check.className = "check bad";
      }
      void drawWhich();
    });

    clearBtn.addEventListener("click", async () => {
      clear(feedback);
      check.textContent = "";
      try {
        await Bridge.secretClear(p.key);
        delete models[p.id];
        feedback.append(h("div", { class: "notice ok", text: "Key removed." }));
        await refreshKey();
        void drawWhich();
      } catch (err) {
        feedback.append(h("div", { class: "notice err", text: `Could not remove: ${String(err)}` }));
      }
    });

    clearBtn.style.display = hasKey ? "" : "none";

    return h(
      "div",
      { class: "provider" },
      h("h4", {}, dot, h("span", { text: p.brand })),
      state,
      h("div", { class: "row" }, h("label", { text: "API key" }), field, saveBtn, clearBtn, check),
      feedback,
    );
  }

  function drawClouds() {
    clear(clouds);
    clouds.append(h("h3", { text: "Cloud providers" }));
    for (const p of CLOUD_PROVIDERS) clouds.append(providerKey(p));
  }

  // 3. Local models.
  function drawLocals() {
    clear(locals);
    locals.append(h("h3", { text: "Local models" }));
    for (const s of servers) {
      const st = serverStatus(s);
      const where = s.placement === "network" ? ` · ${s.host}` : "";
      const row = h("div", { class: "row" },
        statusDot(st.ok),
        h("span", { text: `${s.name}${where}` }),
        h("span", { class: "hint", text: st.text }),
      );
      if (s.unencrypted) row.append(h("span", { class: "hint warn", text: "unencrypted on your network" }));
      locals.append(row);
    }
    const urlField = h("input", { type: "text", placeholder: "http://192.168.1.20:11434", style: "flex:1 1 auto;min-width:0", spellcheck: "false" }) as HTMLInputElement;
    const keyField = h("input", { type: "password", placeholder: "API key (optional)", style: "width:160px", autocomplete: "off" }) as HTMLInputElement;
    const addRow = h("div", { class: "row", style: "display:none" },
      urlField, keyField,
      h("button", { class: "primary", text: "Add", onclick: async () => {
        const url = urlField.value.trim();
        if (!url) return;
        // Rust keeps only a clean URL (no user:pass@): the key goes in its own field.
        settings.ai = { ...settings.ai, customServer: url };
        await save();
        if (keyField.value.trim()) await Bridge.secretSet(CUSTOM_KEY, keyField.value.trim()).catch(() => undefined);
        await refresh();
      } }),
    );
    const actions = h("div", { class: "row" },
      h("button", { text: "Rescan", onclick: () => void refresh() }),
      h("button", { text: "Add server…", onclick: () => { addRow.style.display = ""; urlField.focus(); } }),
    );
    if (settings.ai.customServer) {
      actions.append(h("button", { class: "danger", text: "Remove server", onclick: async () => {
        settings.ai = { ...settings.ai, customServer: null };
        await save();
        await Bridge.secretClear(CUSTOM_KEY).catch(() => undefined);
        await refresh();
      } }));
    }
    locals.append(actions, addRow);
  }

  // Nothing is looked for at launch: this window is created hidden, and Settings → AI "opens"
  // when it is shown or comes back into focus. Never on a timer. The two events usually
  // arrive together, so one refresh at a time, and not twice within a second.
  let refreshing = false;
  let lastRefresh = 0;
  async function refreshOnOpen() {
    if (refreshing || Date.now() - lastRefresh < 1000) return;
    refreshing = true;
    try {
      await refresh();
    } finally {
      refreshing = false;
      lastRefresh = Date.now();
    }
  }
  window.addEventListener("focus", () => void refreshOnOpen());
  document.addEventListener("visibilitychange", () => {
    if (document.visibilityState === "visible") void refreshOnOpen();
  });

  // Drawn without asking Rust anything; the first refresh fills in the models and servers.
  drawClouds();
  which.append(h("h3", { text: "Which model answers" }));
  drawLocals();
  // Opened in a window that is already showing (plain `npm run dev` in a browser tab).
  if (document.visibilityState === "visible" && document.hasFocus()) void refreshOnOpen();
  return h("section", {}, h("h2", {}, h("span", { text: "AI" })), which, clouds, locals);
}
```

- [ ] **Step 2: Imports and boot**

Make the imports at the top of `main.ts`:

```ts
import { Bridge, onEvent, type AiServer, type Feature, type HookStatus, type ModelInfo } from "../core/bridge";
import { DEFAULT_SETTINGS, type AiSettings, type ModelChoice, type Settings } from "../core/state";
```

In `main()`:
- delete the line `const hasKey = (await Bridge.secretPresent("anthropic-api-key")) ?? false;`;
- start the `keys` list with the three AI keys:

```ts
  const keys = [
    "anthropic-api-key", "google-api-key", "openai-api-key",
    "stripe-api-key", "github-token", "vercel-token",
    "n8n-url", "n8n-api-key", "resend-api-key", "notion-api-key", "calcom-api-key",
  ];
```

- replace `apiSection(hasKey),` with `aiSection(present),`.

Append to `windows/src/settings/settings.css`:

```css

/* ── AI section: three boxes inside one section ────────────────────────── */

.ai-box {
  display: flex;
  flex-direction: column;
  gap: 10px;
}

.ai-box + .ai-box {
  border-top: 1px solid var(--hairline);
  padding-top: 14px;
}

.ai-box > h3 {
  font: 600 12px var(--font);
  color: var(--dim);
}

/* One cloud key, laid out like the Claude section it grew from: the heading is
   `section > h2`'s look (same font, dot and gap), the rest reuses .hint, .row and .notice. */
.provider {
  display: flex;
  flex-direction: column;
  gap: 12px;
}

.provider + .provider {
  border-top: 1px solid var(--hairline);
  padding-top: 14px;
}

.provider > h4 {
  font: 600 13px var(--font);
  display: flex;
  align-items: center;
  gap: 8px;
}

.check {
  font: 500 12px var(--font);
  color: var(--dim);
}

.check.ok {
  color: var(--green);
}

.check.bad {
  color: var(--red);
}

.hint.warn {
  color: var(--amber);
}
```

Run: `cd windows && npx tsc --noEmit`
Expected: no output, exit 0.

- [ ] **Step 3: Walk through it (Windows or Linux)**

Run `npm run tauri dev`, as in Task 13, Step 9, and open Settings… → AI. Expected:
1. **The section and its boxes.** The section is titled **AI**, with three boxes: Which model answers, Cloud providers, Local models.
2. **Nothing at launch.** With a key already saved, start the fake server with `--log /tmp/nm-log.jsonl` (see Task 13, Step 9) and restart the app without opening Settings: the log has no `GET /v1/models` at all. Open Settings…: the servers and models appear and the log gains `GET /v1/models?limit=100`. Close it and open it again right away: nothing new within a second; after that only the local servers are looked up again, not the cloud model lists, until those are 10 minutes old.
3. **Saving a key.** Each provider keeps the Claude section's look: the dot, "Key saved in the Windows Credential Manager.", the key row, and the "Saved. It never touches disk." notice. Saving a key adds "Checking…", then ✓ with the fake server running. Without `NM_AI_BASE_URL_OVERRIDE`, a made-up Anthropic key reaches the real API and shows "✗ Your Anthropic key was rejected." (the fake server answers `GET /v1/models` for any key, so it can't show a ✗; the Rust test `the_key_check_lists_models_and_says_why_a_key_failed` covers the wording).
4. **The model menus.** Chat and File questions list Auto plus live models; the line under each says, for example, "claude-sonnet-5-5 · falls back to Local · llama3.2".
5. **Preferred cloud.** The row appears only when both the Anthropic and OpenAI keys are saved.
6. **Local models.** Each server row shows a dot and "Running · 1 model", "Server off" or "Not installed".
7. **Adding a server.** Add server… with `http://127.0.0.1:<fake port>` adds a "127.0.0.1" row, Running. A LAN `http://` address adds "unencrypted on your network". Typing `http://me:pw@127.0.0.1:<fake port>` works the same, and `settings.json` holds `http://127.0.0.1:<fake port>` without `me:pw@`.
8. **Rescan.** Rescan refreshes the rows.

- [ ] **Step 4: README**

In `windows/README.md`:

Replace the intro line (line 9, `Approve Claude Code permissions, …`) with:

```markdown
Approve Claude Code permissions, watch your session work, drop a file, chat with Claude, OpenAI or a model on your own computer, keep an eye on your services — without leaving what you're doing.
```

Replace the whole `## Chat and keys` section with:

```markdown
## AI: cloud keys and local models

**Settings… → AI** has three boxes:

- **Which model answers** — *Chat* and *File questions* each use **Auto** or a
  model you pick. Auto uses your preferred cloud when it has a key (Claude, then
  OpenAI, then Google), and a model on this computer otherwise. When the cloud
  is busy or unreachable, Auto asks the local model once instead and says so
  under the reply. A rejected key, a billing limit or a refusal is never handed
  to another model.
- **Cloud providers** — Anthropic, Google and OpenAI keys. A pasted key is
  checked straight away (✓ / ✗).
- **Local models** — NotchMeow looks for Ollama (port 11434), LM Studio (1234),
  llama.cpp (8080) and Jan (1337) on this computer at launch and when the model
  picker or this box opens, never on a timer. **Add server…** takes one server on
  your network; plain `http` to another computer is flagged as unencrypted.

Every reply is labelled `cloud`, `local` or `network`, and web-search sources
from Claude and OpenAI are clickable. OpenAI requests always send `store: false`.

Keys live in the **Windows Credential Manager**, never on disk and never in the
interface — the island can only ask whether a key exists. Every model request
leaves from the Rust side: that is also why local servers accept it, since Ollama
refuses the webview's `http://tauri.localhost` origin and NotchMeow sends none.

No telemetry. NotchMeow only talks to providers you set up, to this computer, and
to servers you typed in.

### Files

A dropped file goes with the message you send next, and the rest of that conversation uses the
**File questions** model, so the file's text never reaches a model you didn't pick for files.
Dropping another file starts a new conversation. Claude and OpenAI read PDFs
and images themselves; other models get the text of PDFs, Word, RTF, HTML and
plain-text files, cut to fit the model with a note such as "I read the first 600
lines." Images and scanned PDFs headed for a model that can't see are read with
Windows' built-in OCR. Archives, apps, disk images, videos and anything over
25 MB are refused at the drop. Text files must be UTF-8. HEIC photos aren't read
yet (Claude and OpenAI reject the format): export them as JPEG or PNG.
```

In `### Layout`, change the `src-tauri/` line to:

```
  src-tauri/           Rust backend: window, named pipe, AI providers (src/ai/), pollers
```

Replace the `### Log` paragraph with:

```markdown
`%LOCALAPPDATA%\NotchMeow\notchmeow.log` — hook events, permission decisions, poller
problems, and AI errors with the provider's request ID. Never a prompt, a file's
contents or a key. It stays on your machine.
```

Add this section after `### Log`:

```markdown
### Testing the AI

`cargo test --workspace` (in `windows/`, after `cargo build --release -p notchmeow-hook`)
runs the shared AI test cases in `tests/fixtures/ai/` and talks to the fake model
server in `tests/fake_local_llm.py`, so it needs Python 3. From a Mac, run the
same thing in Docker: `windows/scripts/cargo-linux.sh test --workspace`.
`npm run check:ai` (Node 22.6 or newer) checks which model setting answers a message.

To click through the chat without keys or models, debug builds read
`NM_AI_BASE_URL_OVERRIDE`, which points Anthropic, OpenAI and Google at the fake
server. Release builds don't contain it.

    python3 tests/fake_local_llm.py port.txt --fail 429      # or --persona ollama, --fail cut…
    $env:NM_AI_BASE_URL_OVERRIDE = "http://127.0.0.1:$(Get-Content port.txt)"
    npm run tauri dev

Save any text as a key, or add `http://127.0.0.1:<port>` with Settings → AI → Add server….
```

In `## What's different from the Mac version`, add:

```markdown
- No Apple on-device model: that one is macOS only.
- Images and scanned PDFs for a model that can't see go through Windows' own OCR
  (`Windows.Media.Ocr`) instead of the Mac's Vision framework.
```

In `## Linux`, at the end of the "What changes on Linux:" list, add:

```markdown
- **AI**: no OCR and no PDF renderer on Linux. An image headed for a model that
  can't see gets "This model can't see images. Pick one that can." A scanned PDF,
  for any model but Claude and OpenAI, gets "I can't read scanned PDFs on Linux
  yet. Try Claude or OpenAI, or paste the text." Claude and OpenAI read both
  natively.
```

- [ ] **Step 5: Final full check**

Run: `cargo test --workspace`
Expected: every `test result:` line says `ok`.

Run: `cd windows && npx tsc --noEmit`
Expected: no output, exit 0.

Run: `cd windows && npm run check:ai`
Expected: four `✓` lines, then `All AI UI checks passed`.

Run: `grep -n "droppedFile" windows/src/views/chat.ts | grep -v "//\|\*"`
Expected: one line, `const file = State.droppedFile;`, in `sync()`, which draws the file chip. No model setting is chosen from it.

Run: `grep -rn "featureFor(" windows/src`
Expected: three lines: the definition in `core/feature.ts`, and `nextFeature()` and `submit()` in `views/chat.ts`, which both pass `State.chatHistory` as the second argument.

Run: `bash scripts/test-ai-contract.sh`
Expected: `All AI contract checks passed` and `Ran 13 tests … OK`.

- [ ] **Step 6: Commit**

```bash
git add windows/src/settings windows/README.md
git commit -m "feat(ai): AI settings section with live model lists; README for AI and files

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Self-review notes

**Spec coverage** (§ = spec section):

| Spec | Where |
|---|---|
| §1 provider types, `prewarm`, `tools`/`responseFormat` reserved for F | Task 2 (`provider.rs`), Task 8 (Ollama prewarm), Task 13 (`ai_prewarm` on chat focus) |
| §1 router: Preferred cloud → other → Google; last-used local → first ready; one local retry | Task 3 (all 30 router cases), Task 12 |
| §1 native Anthropic (streaming, web search), OpenAI Responses (`store:false`, `web_search`, `input_file`/`input_image`), OpenAI-compatible (`max_tokens`, no `tool_choice`, `<think>` hidden) | Tasks 9, 10, 8 |
| §1 all HTTP in Rust, no Origin, keys never in the webview; allowlist gains google/openai/custom | Tasks 2, 8 (Origin asserted from the fake log), 13 |
| §2 discovery: 4 ports, 300 ms parallel, identification, unknown → "Local server (OpenAI-compatible)", outdated Ollama, added server with key, network label, unencrypted flag, embeddings filtered, last-used model remembered; never on a timer | Task 8, Task 12 (`ready_list`, `local_models`), Task 13 (launch / picker / settings / Auto) |
| §3 file table, budget and notices, 25 MB and type rejects, Windows OCR, Linux "can't see", the file joins its own turn, drop card names the reader | Tasks 5, 6, 7, 12, 14 |
| §4 AI section's three boxes, Preferred cloud row, key ✓/✗, local rows, Rescan, Add server…; live lists replace the fixed list; chat chip, caption, sources, empty state | Tasks 14, 15 |
| §5 fallback rules, the error table (with Retry-After), Stop, pre-warm, context overflow, the cat never loops on an error, labels, request-id logging, no content in logs, OpenAI storage | Tasks 3, 12, 14 |
| §6 shared cases run from Rust, fake-server personas and failure modes, debug-only redirect, Windows CI `cargo test`, regression and leak tests | Tasks 1–13, CI in Task 2 |

**Gaps, by design:**
- Apple on-device is macOS only.
- `docs/INTEGRATIONS.md` is updated once by the macOS plan.
- The prototype's hairball reject animation isn't ported here (the cat port owns it). Rejects use the existing error state and sound.

**Choices the spec left open, made here:**
- **Unclassified failures.** Copy for failures the spec's table doesn't list follows its voice:
  - "Couldn't reach Claude. Check your connection.";
  - "Claude took too long to answer.";
  - "Claude had a problem. Try again in a moment.";
  - "Claude: <the provider's own message>" for a bad request;
  - "Your Anthropic key is missing.";
  - "<model> isn't on <server> any more.";
  - "Files over 25 MB are too big for me." and "I can't read this kind of file.";
  - "I couldn't read that file.".
- **Spend limits.** "Your OpenAI spend limit was reached." spells out the spec's "…spend limit reached.".
- **Countdown.** The 20 s default countdown sends again by itself at most 3 times. After that the note stays, without an action.
- **Silence after the first token.** 120 s of silence ends the stream as `interrupted`. "No first token" is measured to the first bytes, so OpenAI's `response.created` counts.
- **Failures in the middle of a stream.** A stream that breaks after some text is `interrupted` and keeps the text. One that breaks before any text is a plain failure, which the router may still route to a local model, but only when its kind is temporary: a mid-stream error with an unknown code (or an `error` that isn't an object) is `bad_request` and never falls back (`errors::stream_error_kind`).
- **History.** It is provider-neutral: files are re-shaped for whichever model answers. Anthropic's web-search blocks aren't replayed, only the text of earlier replies. A long chat on a local or network model is trimmed by the contract's rule (`history-cases.json`, `budget::messages_to_drop`), the same numbers as the Mac; cloud is never trimmed.
- **One added server.** The contract lets every added server keep its key as `custom-server-key.<serverId>` and allows several; this window offers one, stored under the id `default` (`custom-server-key.default`), so "Add server…" replaces the previous server. YAGNI: more would need a list in `AiSettings` and a row each. Nothing has shipped, so there is no settings or keychain migration from a bare `custom-server-key`.
- **Unknown servers on known ports.** They keep the port's provider ID, so they route correctly, and are shown as "Local server (OpenAI-compatible)".
- **"Not installed".** It's shown for Ollama, LM Studio and llama.cpp when their CLI (or `~/.lmstudio`) is absent. Jan and an added server only ever say "Server off".
- **Linux and scanned PDFs.** Linux sends scanned PDFs natively to Claude and OpenAI. For every other model, one that sees images included, it says "I can't read scanned PDFs on Linux yet. Try Claude or OpenAI, or paste the text.", because it has no renderer and no OCR. "This model can't see images." is only for pictures. Windows says "I can't read this scanned PDF. Try Claude or OpenAI, or paste the text." when its OCR or renderer can't help.
- **HEIC photos.** They are never sent to a model that sees images, because Anthropic and OpenAI reject `image/heic` and local servers can't decode it: "HEIC photos aren't supported yet. Export it as JPEG or PNG."
- **Reply length and empty replies.** Every request asks for `providers.json`'s `maxOutputTokens` for its placement, 16,000 for cloud and 4,096 for local and network (`catalog::max_output_tokens`): a thinking model spends its `<think>` or reasoning tokens from the cap, and 4,096 is what the Mac's `LocalChat` already sends. A reply with no text never enters the history and never plays the finish sound; when it stopped at the limit the words are "The model ran out of room before answering. Try again, or pick a model without thinking mode.", with a Choose model button. Text cut off at the limit is kept with "The answer was cut off."
- **Two kinds of failure, two event types.** `AiEvent::Error` carries one of the contract's 12 `ErrorKind`s. The island's own notices (`cant_see`, `scanned_pdf`, `heic`, `rejected`, `unreadable`, `missing_model`, `outdated`, `empty_reply`) are `AiEvent::Problem`, with their own `ProblemKind`, and never reach the router.
- **Which feature answers.** A message that carries a file, and every later message of the same conversation, uses the File questions setting; a conversation with no file uses Chat. The conversation's own messages decide (`featureFor(current, history)`), never `State.droppedFile`, which is never cleared. A file stays in the history for later messages, so a follow-up on the Chat route would hand the file's text to a model the user didn't pick for files. Dropping a file starts a new conversation, which resets the rule. Continue and Retry belong to the reply they extend and use the setting that reply used. Auto may still fall back once, as the spec says; an explicit File questions model never does.
- **Web search tool.** Claude and OpenAI send the tools in providers.json `webSearch`; Claude models starting with one of its `legacyModelPrefixes` get `legacyType`. Nothing is hard-coded in the providers, and a catalog test compares both with the file.
- **Keychain reads.** Which providers have a key is read once, off the async threads, and kept until a key is saved or removed; a turn reads the keys' values once for itself. Focusing the chat or Settings never reads the keychain again.
- **Added server URLs.** A typed `user:pass@`, query or fragment is dropped before the URL is saved or shown; the server's key goes in its own field.

**Placeholder scan:** every code step has its full code. No TBD/TODO.

**Type consistency.** Checked across tasks:
- the names `Choice`, `ModelRef`, `Ready`, `AiSettings`, `AiEvent`, `Resolution`, `Feature`, `FileRef`, `Endpoint`, `Timeouts` and `ModelProvider`;
- the camelCase JSON on both sides: `retryAfter`, `modelName`, `lastUsedLocal`, `preferredCloud`, `customServer`.

The Rust and TypeScript in this plan were compiled and run in a scratch copy, rebuilt from this file's own code blocks:
- 119 Rust tests passed on macOS, in a reduced crate that holds the app's `ai/`, `settings`, `files`, `secrets` (keychain stubbed, but with the real `is_allowed` rule) and `log` modules and type-checks the commands as `lib.rs` registers them (the whole app builds only on Windows and Linux): `ai::*` 110 (105 at the end of Task 12), `settings` 4, `files` 2, `secrets` 3. The fixtures were E1-0's final ones (21 SSE streams, 21 HTTP cases, 13 budget and 12 history cases). No warning points into `src/ai/` in debug, test or release builds;
- `tsc --noEmit` passed at the end of Tasks 13, 14 and 15, and `npm run check:ai` passes with its four cases (and fails on the old one-argument rule, as it should);
- the settings window was driven in a browser with a mocked Tauri bridge, for the previous revision of this plan (the settings code has not changed since): no `ai_*` call at launch, one refresh when the window opens, none within a second, only the local servers again after that, and the key rows' ✓ / ✗ and notices.

The Docker runner (`windows/scripts/cargo-linux.sh test --workspace`) and the real `lib.rs`, with its `platform/` modules, were not run for this revision. `lib.rs`'s edits were compiled in the reduced crate: `secret_set` and `secret_clear` as written, and `save_settings`' new first statement in a function of the same shape. The real `secrets.rs` (the `keyring` crate) was not compiled: its `is_allowed` helpers were, and the tests of `set` and `clear` refusing a bad key ran against a stub that makes the same check.

The `#[cfg(windows)]` OCR module was checked against the windows-rs 0.61.3 sources but not compiled; Task 7 compiles it on Windows.
