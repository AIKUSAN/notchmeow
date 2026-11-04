# E1-0 Shared AI Contract Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Create the language-neutral contract that the macOS (E1-mac) and Windows/Linux (E1-tauri) AI layers both test against. It covers:
- the provider catalog;
- router, HTTP-error, context-budget, history-trimming and attachment test cases;
- recorded SSE streams with expected results;
- a Python reference implementation that proves the cases are consistent;
- an upgraded fake server.

**Architecture:** Everything lives under `tests/fixtures/ai/` as JSON and plain-text SSE files.
- `reference.py` holds the reference implementation. It runs every case in CI before either app consumes it, so a wrong fixture fails here, not in two codebases.
- `tests/fake_local_llm.py` gains server personas, failure modes, the Anthropic `/v1/messages` and OpenAI `/v1/responses` routes, and a request log. Its no-flag behaviour stays byte-for-byte unchanged, because `scripts/test-chat-parsing.sh` depends on it.

**Tech Stack:** Python 3 standard library only (json, zipfile, zlib, struct, http.server, unittest, argparse); Bash; GitHub Actions.

**Spec:** `docs/superpowers/specs/2026-10-03-local-models-design.md` (revision 1).

**Sibling plans:** `2026-10-03-e1-mac-local-models.md` and `2026-10-03-e1-tauri-local-models.md`. Both consume this contract. This plan must land first.

## Global Constraints

- **Python:** 3 standard library only. No pip installs anywhere in tests or CI.
- **Fixtures:** stay tiny. Binary test files are generated at test time by `make_attachments.py`; nothing binary is committed.
- **Timeouts** (ms): probe 300; connect: local 5000, cloud 10000; first token: local 60000, cloud 30000.
- **File limit:** 25 MB = 26,214,400 bytes. Larger files are rejected with reason `size`.
- **Text budget:**
  - 50% of the model's context, at 3.5 characters per token;
  - a local model with unknown context counts as 4,096 tokens;
  - cloud is capped at 204,800 characters.
  
  "Characters" means Unicode scalar values: Swift `unicodeScalars.count`, Rust `chars().count()`.
- **Truncation notices** (exact strings): `I read the first N lines.`, `I read the first line.`, `I read the first part of this file.`
- **History trimming** (a long chat on a small model), counted in Unicode scalars like the text budget:
  - **Estimate:** a text of `n` scalars costs `ceil(n ÷ 3.5)` tokens, computed as `ceil(2n ÷ 7)`.
  - **Budget:** the context (unknown local context = 4,096 tokens) minus a reserved quarter for the reply, `ctx − floor(ctx ÷ 4)`.
  - **Drop:** the oldest turns go two at a time (a user turn and its reply) while the system prompt plus the remaining turns are over budget and more than one turn remains. The system prompt and the latest turn are never dropped. Cloud models are never trimmed.
  - **Notice** (exact string): `This chat got long, so I dropped the oldest messages.`
- **Reply length** (`maxOutputTokens` in `providers.json`): the most tokens a reply may use, by the model's placement: `cloud` 16,000, `network` 4,096, `local` 4,096. OpenAI's reasoning models spend hidden reasoning tokens from the same cap, so 4,096 on cloud could leave an empty reply; 4,096 on local matches the Mac's existing `LocalChat`.
- **Provider IDs** (exact): `anthropic`, `openai`, `google`, `ollama`, `lmstudio`, `llamacpp`, `jan`, `apple`, `custom`.
- **Placements:** `local`, `network`, `cloud`.
- **Error kinds:** `offline`, `unreachable`, `timeout`, `server`, `rate_limited`, `overloaded`, `auth`, `bad_request`, `billing`, `refusal`, `cancelled`, `interrupted`.
- **Router outcomes:** `ok`, `fallback`, `error`, `retry_countdown`, `empty_state`, `interrupted`, `cancelled`.
- **Fake server:** running `python3 tests/fake_local_llm.py <port-file>` with no flags must behave exactly as before.
- **Commits:** local only, never pushed. End every message with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`.

## Review Focus

1. **Non-ASCII text in budget counting.** A file of emoji or CJK text must be measured in Unicode scalars, not bytes. Otherwise the two apps cut at different places. The Task 3 budget case `emoji-scalars` and Task 3b history case `scalars, not characters or bytes` (a family emoji is 5 scalars but 1 Swift `Character`) pin this.
2. **Uppercase or odd file extensions** (`Upper.PDF`, `.HTM`). People rename files, and classification must lowercase the extension. Task 4 cases `Upper.PDF` and `Legacy.HTM` pin this.
3. **A 429 that is really "out of credit".** OpenAI sends billing problems as 429, and Anthropic sends low credit as a 400 mentioning "credit balance". Treating either as "busy" would silently fall back forever. Task 2 has three http-error cases for this.
4. **A stream that stops without its terminal event.** This happens when the laptop sleeps or Ollama crashes. The text received so far must be kept, with error `interrupted`. Task 5's `cut` fixtures for every format pin this.
5. **SSE comment and keep-alive lines** (`: keep-alive`, `event: ping`) and `data:` lines that aren't JSON. Parsers must skip them, not crash. Task 5's `keepalive-cut` and the `ping` in `text-websearch` pin this.

---

## File Structure

| Path | Responsibility |
|---|---|
| `docs/AI-PROVIDERS.md` | Human documentation of the provider catalog and the fixture formats; points to `providers.json` for values |
| `tests/fixtures/ai/providers.json` | Single source of provider IDs, placements, URLs, ports, probe paths, default models, model filters, timeouts, limits and reply lengths |
| `tests/fixtures/ai/router-cases.json` | Auto/explicit routing and failure outcomes |
| `tests/fixtures/ai/http-errors.json` | HTTP status + body → error kind |
| `tests/fixtures/ai/budget-cases.json` | Context budget and truncation notices |
| `tests/fixtures/ai/history-cases.json` | Which oldest turns a long chat drops on a small model, and the notice |
| `tests/fixtures/ai/attachment-cases.json` | File classification and extraction expectations |
| `tests/fixtures/ai/make_attachments.py` | Generates the attachment files into a directory |
| `tests/fixtures/ai/sse/<format>/<name>.txt` + `.expected.json` | Recorded SSE streams and their aggregated results |
| `tests/fixtures/ai/reference.py` | Python reference implementation and runner for every case |
| `tests/fake_local_llm.py` | Fake server: personas, failure modes, three chat routes, request log |
| `tests/test_fake_server.py` | Fake-server tests |
| `scripts/test-ai-contract.sh` | Runs `reference.py` and the fake-server tests |
| `.github/workflows/build.yml` | Adds the contract step |

---

### Task 1: Provider catalog and docs

**Files:**
- Create: `tests/fixtures/ai/providers.json`
- Create: `docs/AI-PROVIDERS.md`
- Create: `tests/fixtures/ai/reference.py` (catalog check only; later tasks extend it)
- Create: `scripts/test-ai-contract.sh`

**Interfaces:**
- Produces: `providers.json`, shaped as `{version, providers[], cloudOrder, webSearch, modelFilters, timeoutsMs, limits, maxOutputTokens}`. Both apps' catalog tests compare their built-in tables to it.
- Produces: `reference.py`, with a `load(name)` helper and a `main()` that runs all `check_*` functions, exits 1 on any failure and prints `✓` / `✗` lines like the Swift tests.

- [ ] **Step 1: Write `providers.json`**

```json
{
  "version": 1,
  "providers": [
    {"id": "anthropic", "name": "Anthropic", "placement": "cloud", "api": "anthropic",
     "baseURL": "https://api.anthropic.com", "chatPath": "/v1/messages", "modelsPath": "/v1/models",
     "keychainKey": "anthropic-api-key", "defaultModel": "claude-sonnet-5-5"},
    {"id": "openai", "name": "OpenAI", "placement": "cloud", "api": "openai-responses",
     "baseURL": "https://api.openai.com", "chatPath": "/v1/responses", "modelsPath": "/v1/models",
     "keychainKey": "openai-api-key", "defaultModel": "gpt-6.1-sol"},
    {"id": "google", "name": "Google", "placement": "cloud", "api": "openai-chat",
     "baseURL": "https://generativelanguage.googleapis.com/v1beta/openai", "chatPath": "/chat/completions", "modelsPath": "/models",
     "keychainKey": "google-api-key", "defaultModel": null, "defaultModelRule": "first id containing 'flash', else first"},
    {"id": "ollama", "name": "Ollama", "placement": "local", "api": "openai-chat",
     "baseURL": "http://127.0.0.1:11434", "port": 11434, "probePath": "/api/version",
     "chatPath": "/v1/chat/completions", "modelsPath": "/v1/models", "keychainKey": null, "defaultModel": null},
    {"id": "lmstudio", "name": "LM Studio", "placement": "local", "api": "openai-chat",
     "baseURL": "http://127.0.0.1:1234", "port": 1234, "probePath": "/v1/models",
     "chatPath": "/v1/chat/completions", "modelsPath": "/v1/models", "keychainKey": null, "defaultModel": null},
    {"id": "llamacpp", "name": "llama.cpp", "placement": "local", "api": "openai-chat",
     "baseURL": "http://127.0.0.1:8080", "port": 8080, "probePath": "/health",
     "chatPath": "/v1/chat/completions", "modelsPath": "/v1/models", "keychainKey": null, "defaultModel": null},
    {"id": "jan", "name": "Jan", "placement": "local", "api": "openai-chat",
     "baseURL": "http://127.0.0.1:1337", "port": 1337, "probePath": "/v1/models",
     "chatPath": "/v1/chat/completions", "modelsPath": "/v1/models", "keychainKey": null, "defaultModel": null},
    {"id": "apple", "name": "Apple on-device", "placement": "local", "api": "apple",
     "keychainKey": null, "defaultModel": "system"},
    {"id": "custom", "name": "Local server", "placement": "computed", "api": "openai-chat",
     "chatPath": "/v1/chat/completions", "modelsPath": "/v1/models", "keychainKey": "custom-server-key", "defaultModel": null}
  ],
  "cloudOrder": ["anthropic", "openai", "google"],
  "webSearch": {
    "anthropic": {"type": "web_search_20260209", "name": "web_search", "max_uses": 5,
                  "legacyType": "web_search_20250305", "legacyModelPrefixes": ["claude-haiku-4", "claude-3"]},
    "openai": {"type": "web_search"}
  },
  "modelFilters": {
    "local": {"exclude": ["embed", "bge-", "all-minilm", "clip", "rerank"]},
    "google": {"exclude": ["embed", "imagen", "veo", "aqa", "tts", "audio", "live"]},
    "openai": {"includePrefixes": ["gpt-", "o1", "o3", "o4", "o5"],
               "exclude": ["embed", "tts", "whisper", "dall-e", "audio", "realtime", "moderat", "codex",
                           "computer-use", "transcribe", "image", "sora", "babbage", "davinci", "instruct",
                           "search", "live"]}
  },
  "timeoutsMs": {"probe": 300, "connectLocal": 5000, "connectCloud": 10000,
                 "firstTokenLocal": 60000, "firstTokenCloud": 30000},
  "limits": {"maxFileBytes": 26214400, "cloudTextCapChars": 204800, "budgetFractionOfContext": 0.5,
             "charsPerToken": 3.5, "defaultLocalContextTokens": 4096},
  "maxOutputTokens": {"cloud": 16000, "network": 4096, "local": 4096}
}
```

- **`placement: "computed"`** means a `custom` server is `local` when its host is `127.0.0.1`, `::1` or `localhost`, and `network` otherwise.
- **`webSearch`** holds the hosted web-search tool each cloud provider sends. Both apps send exactly these values; the Windows app already used `web_search_20260209`, and the Mac moves up from `web_search_20250305`.
  - `web_search_20260209` needs a recent Claude model. A model ID starting with one of `legacyModelPrefixes` (e.g. `claude-haiku-4-5`) gets `legacyType` instead, with the same `name` and `max_uses`. Both apps choose the type with `anthropicWebSearchType(model)`.
- **`cloudOrder`** is the fallback order. The router moves the user's Preferred cloud (`anthropic` or `openai`) to the front.
- **`maxOutputTokens`** is the reply length each app asks for, by the placement of the model that answers: 16,000 for `cloud`, 4,096 for `local` and `network`. It goes out as `max_tokens` (Anthropic, OpenAI-compatible) or `max_output_tokens` (OpenAI Responses).
  - **Why cloud gets more:** OpenAI's reasoning models spend hidden reasoning tokens from the cap, so 4,096 risks an empty reply.
  - **Why local keeps 4,096:** it is what the Mac's `LocalChat` already sends, and a small model's context is small anyway.

- [ ] **Step 2: Write `reference.py` with a catalog check, and run it to see it fail**

```python
#!/usr/bin/env python3
"""Reference implementation of NotchMeow's AI contract.

Runs every fixture in tests/fixtures/ai/ against a small, obviously-correct
Python model of the spec. Exit status 1 if any case fails. Both apps implement
the same behaviour natively; this file is the tie-breaker when they disagree.
"""
import json
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
FAILURES = 0


def load(name):
    with open(os.path.join(HERE, name), encoding="utf-8") as f:
        return json.load(f)


def check(label, got, expected):
    global FAILURES
    if got == expected:
        print(f"  ✓ {label}")
    else:
        print(f"  ✗ {label}\n    got:      {got!r}\n    expected: {expected!r}")
        FAILURES += 1


def check_catalog():
    print("providers.json")
    cat = load("providers.json")
    ids = [p["id"] for p in cat["providers"]]
    check("provider ids", ids, ["anthropic", "openai", "google", "ollama", "lmstudio",
                                "llamacpp", "jan", "apple", "custom"])
    ports = {p["id"]: p.get("port") for p in cat["providers"] if p.get("port")}
    check("local ports", ports, {"ollama": 11434, "lmstudio": 1234, "llamacpp": 8080, "jan": 1337})
    check("cloud order", cat["cloudOrder"], ["anthropic", "openai", "google"])
    check("web search tools", (cat["webSearch"]["anthropic"]["type"], cat["webSearch"]["openai"]["type"]),
          ("web_search_20260209", "web_search"))
    ws = cat["webSearch"]["anthropic"]

    def anthropic_web_search_type(model):
        legacy = any(model.startswith(p) for p in ws["legacyModelPrefixes"])
        return ws["legacyType"] if legacy else ws["type"]

    check("sonnet 5.5 gets the new tool", anthropic_web_search_type("claude-sonnet-5-5"), "web_search_20260209")
    check("haiku 4.5 gets the legacy tool", anthropic_web_search_type("claude-haiku-4-5-20251001"), "web_search_20250305")
    check("probe timeout", cat["timeoutsMs"]["probe"], 300)
    check("max file bytes", cat["limits"]["maxFileBytes"], 25 * 1024 * 1024)
    check("reply length by placement", cat["maxOutputTokens"], {"cloud": 16000, "network": 4096, "local": 4096})


CHECKS = [check_catalog]


def main():
    for fn in CHECKS:
        fn()
    if FAILURES:
        print(f"\n{FAILURES} failure(s)")
        sys.exit(1)
    print("\nAll AI contract checks passed")


if __name__ == "__main__":
    main()
```

Temporarily set `"jan"`'s port to `1338` in `providers.json`. Run `python3 tests/fixtures/ai/reference.py`.
Expected: `✗ local ports`, exit 1. Then restore `1337`.

Do the same with `"maxOutputTokens"`'s `"cloud"` set to `4096`. Expected: `✗ reply length by placement`, exit 1. Then restore `16000`.

- [ ] **Step 3: Run it to see it pass**

Run: `python3 tests/fixtures/ai/reference.py`
Expected: nine `✓` lines, then `All AI contract checks passed`.

- [ ] **Step 4: Write `scripts/test-ai-contract.sh`**

```bash
#!/usr/bin/env bash
# Runs the language-neutral AI contract: fixture reference checks + fake server tests.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 tests/fixtures/ai/reference.py
if [ -f tests/test_fake_server.py ]; then
    python3 tests/test_fake_server.py
fi
```

Run: `chmod +x scripts/test-ai-contract.sh && bash scripts/test-ai-contract.sh`
Expected: `All AI contract checks passed`.

- [ ] **Step 5: Write `docs/AI-PROVIDERS.md`**

```markdown
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

A `custom` server is `local` when its host is 127.0.0.1, ::1 or localhost, and `network` otherwise.

## Auto

Auto tries the Preferred cloud (Claude or OpenAI), then the other of the two, then Google,
using the first one with a key. Without a key, it uses the last-used local model, then the
first ready local model, then Apple on-device. A temporary cloud failure retries once on a
local model. See `tests/fixtures/ai/router-cases.json` for every rule as a test case.

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

## Fixture formats

| File | Shape |
|---|---|
| `router-cases.json` | `defaults` plus `cases[]` of `{name, input, expect}`; merge `defaults` under each `input` |
| `http-errors.json` | `cases[]` of `{status, headers, body, kind, retryAfter}` |
| `budget-cases.json` | `cases[]` of `{name, placement, contextTokens, lineLength, lineCount, expect{keptChars, keptLines, notice}}` |
| `history-cases.json` | `rule{reservedOutputDivisor, binaryAttachmentChars, notice}` plus `cases[]` of `{name, placement, contextTokens, system, turns[{role, text, files[]}], expect{dropped, notice}}`; a `text` is `{fill, count}`, `fill` repeated `count` times |
| `attachment-cases.json` | `cases[]` of `{file, kind, reason?, mime?, contains?, notContains?}`; run `make_attachments.py <dir>` first |
| `sse/<format>/<name>.txt` | a raw SSE stream exactly as sent on the wire |
| `sse/<format>/<name>.expected.json` | `{text, toolCalls[{id,name,arguments}], citations[{url,title}], refusal, finish, error}` |

`tests/fixtures/ai/reference.py` is the tie-breaker: if an app and a fixture disagree,
the reference decides.
```

- [ ] **Step 6: Commit**

```bash
git add tests/fixtures/ai/providers.json tests/fixtures/ai/reference.py scripts/test-ai-contract.sh docs/AI-PROVIDERS.md
git commit -m "test(ai): add the shared provider catalog and contract runner

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 2: Router and HTTP-error cases

**Files:**
- Create: `tests/fixtures/ai/router-cases.json`
- Create: `tests/fixtures/ai/http-errors.json`
- Modify: `tests/fixtures/ai/reference.py` (add `route`, `classify_http`, `check_router`, `check_http`)

**Interfaces:**
- Consumes: `providers.json` (`cloudOrder`).
- Produces:
  - **Router semantics.** Both apps implement them as a pure function. `route(input) → {primary, outcome, answeredBy, label, errorKind}`, with these `input` fields:
    - `setting`: `"auto"` or `{provider, model}`;
    - `preferredCloud`;
    - `keys`: list of provider IDs;
    - `online`: bool;
    - `localReady`: a list of `{provider, model, placement}` in discovery order;
    - `lastUsedLocal`: `{provider, model}` or null;
    - `appleReady`: bool;
    - `failure`: an error kind or null.
  - **HTTP errors.** `classify_http(status, body, headers) → (kind, retryAfterSeconds | None)`.

- [ ] **Step 1: Write `router-cases.json`**

```json
{
  "version": 1,
  "defaults": {"setting": "auto", "preferredCloud": "anthropic", "keys": [], "online": true,
               "localReady": [], "lastUsedLocal": null, "appleReady": false, "failure": null},
  "cases": [
    {"name": "cloud key → cloud",
     "input": {"keys": ["anthropic"]},
     "expect": {"primary": "anthropic", "outcome": "ok", "answeredBy": "anthropic", "label": "cloud", "errorKind": null}},
    {"name": "preferred openai wins when both keys exist",
     "input": {"keys": ["anthropic", "openai"], "preferredCloud": "openai"},
     "expect": {"primary": "openai", "outcome": "ok", "answeredBy": "openai", "label": "cloud", "errorKind": null}},
    {"name": "preferred missing → the other of claude/openai",
     "input": {"keys": ["openai", "google"], "preferredCloud": "anthropic"},
     "expect": {"primary": "openai", "outcome": "ok", "answeredBy": "openai", "label": "cloud", "errorKind": null}},
    {"name": "google is last",
     "input": {"keys": ["google"]},
     "expect": {"primary": "google", "outcome": "ok", "answeredBy": "google", "label": "cloud", "errorKind": null}},
    {"name": "no key → first ready local",
     "input": {"localReady": [{"provider": "ollama", "model": "qwen3.5:2b", "placement": "local"}]},
     "expect": {"primary": "ollama", "outcome": "ok", "answeredBy": "ollama", "label": "local", "errorKind": null}},
    {"name": "last used local wins",
     "input": {"localReady": [{"provider": "ollama", "model": "qwen3.5:2b", "placement": "local"},
                              {"provider": "lmstudio", "model": "gemma-4-e2b", "placement": "local"}],
               "lastUsedLocal": {"provider": "lmstudio", "model": "gemma-4-e2b"}},
     "expect": {"primary": "lmstudio", "outcome": "ok", "answeredBy": "lmstudio", "label": "local", "errorKind": null}},
    {"name": "last used not ready → first ready",
     "input": {"localReady": [{"provider": "ollama", "model": "qwen3.5:2b", "placement": "local"}],
               "lastUsedLocal": {"provider": "jan", "model": "llama3"}},
     "expect": {"primary": "ollama", "outcome": "ok", "answeredBy": "ollama", "label": "local", "errorKind": null}},
    {"name": "apple when no server and no key",
     "input": {"appleReady": true},
     "expect": {"primary": "apple", "outcome": "ok", "answeredBy": "apple", "label": "local", "errorKind": null}},
    {"name": "nothing set up → empty state",
     "input": {},
     "expect": {"primary": null, "outcome": "empty_state", "answeredBy": null, "label": null, "errorKind": null}},
    {"name": "offline shortcut goes straight to local",
     "input": {"keys": ["anthropic"], "online": false,
               "localReady": [{"provider": "ollama", "model": "qwen3.5:2b", "placement": "local"}]},
     "expect": {"primary": "ollama", "outcome": "ok", "answeredBy": "ollama", "label": "local", "errorKind": null}},
    {"name": "offline with no local → offline error",
     "input": {"keys": ["anthropic"], "online": false, "failure": "offline"},
     "expect": {"primary": "anthropic", "outcome": "error", "answeredBy": null, "label": null, "errorKind": "offline"}},
    {"name": "timeout → one local retry",
     "input": {"keys": ["anthropic"], "failure": "timeout",
               "localReady": [{"provider": "ollama", "model": "qwen3.5:2b", "placement": "local"}]},
     "expect": {"primary": "anthropic", "outcome": "fallback", "answeredBy": "ollama", "label": "local", "errorKind": "timeout"}},
    {"name": "unreachable cloud → local retry",
     "input": {"keys": ["openai"], "failure": "unreachable",
               "localReady": [{"provider": "ollama", "model": "qwen3.5:2b", "placement": "local"}]},
     "expect": {"primary": "openai", "outcome": "fallback", "answeredBy": "ollama", "label": "local", "errorKind": "unreachable"}},
    {"name": "server error → local retry",
     "input": {"keys": ["anthropic"], "failure": "server",
               "localReady": [{"provider": "ollama", "model": "qwen3.5:2b", "placement": "local"}]},
     "expect": {"primary": "anthropic", "outcome": "fallback", "answeredBy": "ollama", "label": "local", "errorKind": "server"}},
    {"name": "rate limited with local → local retry",
     "input": {"keys": ["anthropic"], "failure": "rate_limited",
               "localReady": [{"provider": "ollama", "model": "qwen3.5:2b", "placement": "local"}]},
     "expect": {"primary": "anthropic", "outcome": "fallback", "answeredBy": "ollama", "label": "local", "errorKind": "rate_limited"}},
    {"name": "rate limited without local → countdown",
     "input": {"keys": ["anthropic"], "failure": "rate_limited"},
     "expect": {"primary": "anthropic", "outcome": "retry_countdown", "answeredBy": null, "label": null, "errorKind": "rate_limited"}},
    {"name": "overloaded without local → countdown",
     "input": {"keys": ["openai"], "failure": "overloaded"},
     "expect": {"primary": "openai", "outcome": "retry_countdown", "answeredBy": null, "label": null, "errorKind": "overloaded"}},
    {"name": "auth never falls back",
     "input": {"keys": ["anthropic"], "failure": "auth",
               "localReady": [{"provider": "ollama", "model": "qwen3.5:2b", "placement": "local"}]},
     "expect": {"primary": "anthropic", "outcome": "error", "answeredBy": null, "label": null, "errorKind": "auth"}},
    {"name": "billing never falls back",
     "input": {"keys": ["openai"], "failure": "billing",
               "localReady": [{"provider": "ollama", "model": "qwen3.5:2b", "placement": "local"}]},
     "expect": {"primary": "openai", "outcome": "error", "answeredBy": null, "label": null, "errorKind": "billing"}},
    {"name": "refusal never falls back",
     "input": {"keys": ["anthropic"], "failure": "refusal",
               "localReady": [{"provider": "ollama", "model": "qwen3.5:2b", "placement": "local"}]},
     "expect": {"primary": "anthropic", "outcome": "error", "answeredBy": null, "label": null, "errorKind": "refusal"}},
    {"name": "bad request never falls back",
     "input": {"keys": ["anthropic"], "failure": "bad_request",
               "localReady": [{"provider": "ollama", "model": "qwen3.5:2b", "placement": "local"}]},
     "expect": {"primary": "anthropic", "outcome": "error", "answeredBy": null, "label": null, "errorKind": "bad_request"}},
    {"name": "explicit cloud choice never falls back",
     "input": {"setting": {"provider": "anthropic", "model": "claude-sonnet-5-5"}, "keys": ["anthropic"], "failure": "timeout",
               "localReady": [{"provider": "ollama", "model": "qwen3.5:2b", "placement": "local"}]},
     "expect": {"primary": "anthropic", "outcome": "error", "answeredBy": null, "label": null, "errorKind": "timeout"}},
    {"name": "explicit local choice beats a cloud key",
     "input": {"setting": {"provider": "lmstudio", "model": "gemma-4-e2b"}, "keys": ["anthropic"],
               "localReady": [{"provider": "ollama", "model": "qwen3.5:2b", "placement": "local"},
                              {"provider": "lmstudio", "model": "gemma-4-e2b", "placement": "local"}]},
     "expect": {"primary": "lmstudio", "outcome": "ok", "answeredBy": "lmstudio", "label": "local", "errorKind": null}},
    {"name": "explicit local that is unreachable → error",
     "input": {"setting": {"provider": "lmstudio", "model": "gemma-4-e2b"}, "failure": "unreachable"},
     "expect": {"primary": "lmstudio", "outcome": "error", "answeredBy": null, "label": null, "errorKind": "unreachable"}},
    {"name": "local primary failure does not go to cloud",
     "input": {"failure": "server",
               "localReady": [{"provider": "ollama", "model": "qwen3.5:2b", "placement": "local"}]},
     "expect": {"primary": "ollama", "outcome": "error", "answeredBy": null, "label": null, "errorKind": "server"}},
    {"name": "stream cut keeps partial text",
     "input": {"keys": ["anthropic"], "failure": "interrupted",
               "localReady": [{"provider": "ollama", "model": "qwen3.5:2b", "placement": "local"}]},
     "expect": {"primary": "anthropic", "outcome": "interrupted", "answeredBy": "anthropic", "label": "cloud", "errorKind": "interrupted"}},
    {"name": "user pressed stop",
     "input": {"keys": ["anthropic"], "failure": "cancelled"},
     "expect": {"primary": "anthropic", "outcome": "cancelled", "answeredBy": null, "label": null, "errorKind": null}},
    {"name": "network server fallback is labelled network",
     "input": {"keys": ["anthropic"], "failure": "overloaded",
               "localReady": [{"provider": "custom", "model": "llama3", "placement": "network"}]},
     "expect": {"primary": "anthropic", "outcome": "fallback", "answeredBy": "custom", "label": "network", "errorKind": "overloaded"}},
    {"name": "fallback prefers last used local",
     "input": {"keys": ["anthropic"], "failure": "timeout",
               "localReady": [{"provider": "ollama", "model": "qwen3.5:2b", "placement": "local"},
                              {"provider": "lmstudio", "model": "gemma-4-e2b", "placement": "local"}],
               "lastUsedLocal": {"provider": "lmstudio", "model": "gemma-4-e2b"}},
     "expect": {"primary": "anthropic", "outcome": "fallback", "answeredBy": "lmstudio", "label": "local", "errorKind": "timeout"}},
    {"name": "apple can be the fallback",
     "input": {"keys": ["anthropic"], "failure": "timeout", "appleReady": true},
     "expect": {"primary": "anthropic", "outcome": "fallback", "answeredBy": "apple", "label": "local", "errorKind": "timeout"}}
  ]
}
```

- [ ] **Step 2: Write `http-errors.json`**

```json
{
  "version": 1,
  "cases": [
    {"status": 401, "headers": {}, "body": {"type": "error", "error": {"type": "authentication_error", "message": "invalid x-api-key"}}, "kind": "auth", "retryAfter": null},
    {"status": 403, "headers": {}, "body": {"error": {"type": "invalid_request_error", "code": "unsupported_country_region_territory", "message": "Country not supported"}}, "kind": "auth", "retryAfter": null},
    {"status": 400, "headers": {}, "body": {"type": "error", "error": {"type": "invalid_request_error", "message": "messages: field required"}}, "kind": "bad_request", "retryAfter": null},
    {"status": 400, "headers": {}, "body": {"type": "error", "error": {"type": "invalid_request_error", "message": "Your credit balance is too low to access the Anthropic API."}}, "kind": "billing", "retryAfter": null},
    {"status": 404, "headers": {}, "body": {"error": {"message": "model 'unknown-model' not found, try pulling it first", "type": "not_found"}}, "kind": "bad_request", "retryAfter": null},
    {"status": 429, "headers": {"Retry-After": "2"}, "body": {"error": {"type": "rate_limit_error", "code": "slow_down", "message": "Slow down"}}, "kind": "rate_limited", "retryAfter": 2},
    {"status": 429, "headers": {}, "body": {"error": {"type": "insufficient_quota", "code": "insufficient_quota", "message": "You exceeded your current quota"}}, "kind": "billing", "retryAfter": null},
    {"status": 429, "headers": {}, "body": {"error": {"type": "rate_limit_error", "code": "credit_balance_exhausted", "message": "Credit exhausted"}}, "kind": "billing", "retryAfter": null},
    {"status": 429, "headers": {}, "body": {"error": {"type": "rate_limit_error", "code": "project_spend_limit_exceeded", "message": "Spend limit"}}, "kind": "billing", "retryAfter": null},
    {"status": 429, "headers": {}, "body": {"error": {"type": "rate_limit_error", "code": "organization_usage_limit_exceeded", "message": "Usage limit"}}, "kind": "billing", "retryAfter": null},
    {"status": 500, "headers": {}, "body": {"type": "error", "error": {"type": "api_error", "message": "Internal server error"}}, "kind": "server", "retryAfter": null},
    {"status": 502, "headers": {}, "body": null, "kind": "server", "retryAfter": null},
    {"status": 503, "headers": {"retry-after": "7"}, "body": {"error": {"type": "service_unavailable_error", "code": "server_is_overloaded", "message": "Busy"}}, "kind": "overloaded", "retryAfter": 7},
    {"status": 529, "headers": {}, "body": {"type": "error", "error": {"type": "overloaded_error", "message": "Overloaded"}}, "kind": "overloaded", "retryAfter": null}
  ]
}
```

These are the rules, in order:
1. A billing marker wins over the status code. The markers are an `error.code` or `error.type` in {`insufficient_quota`, `credit_balance_exhausted`, `organization_spend_limit_exceeded`, `project_spend_limit_exceeded`, `organization_usage_limit_exceeded`}, or a lowercased `error.message` containing `credit balance`.
2. Status 401 or 403 → `auth`.
3. 400, 404, 413 or 422 → `bad_request`.
4. 429 → `rate_limited`.
5. 503 or 529 → `overloaded`.
6. Other 5xx → `server`.
7. Anything else → `bad_request`.

`Retry-After` is read case-insensitively as whole seconds. Missing or non-numeric → `null`.

- [ ] **Step 3: Add the router and HTTP reference to `reference.py`, then run it**

Insert these functions above `CHECKS`, and change `CHECKS` to `[check_catalog, check_router, check_http]`:

```python
TEMPORARY = {"offline", "unreachable", "timeout", "server", "rate_limited", "overloaded"}
COUNTDOWN = {"rate_limited", "overloaded"}
BILLING_CODES = {"insufficient_quota", "credit_balance_exhausted", "organization_spend_limit_exceeded",
                 "project_spend_limit_exceeded", "organization_usage_limit_exceeded"}
CLOUD = {"anthropic", "openai", "google"}


def _cloud_choice(inp):
    order = [inp["preferredCloud"]] + [p for p in ("anthropic", "openai") if p != inp["preferredCloud"]] + ["google"]
    for p in order:
        if p in inp["keys"]:
            return p
    return None


def _local_choice(inp):
    """Returns (provider, placement) or None: last used if ready, else first ready, else Apple."""
    ready = inp["localReady"]
    last = inp["lastUsedLocal"]
    if last:
        for r in ready:
            if r["provider"] == last["provider"] and r["model"] == last["model"]:
                return r["provider"], r["placement"]
    if ready:
        return ready[0]["provider"], ready[0]["placement"]
    if inp["appleReady"]:
        return "apple", "local"
    return None


def _placement(inp, provider):
    if provider in CLOUD:
        return "cloud"
    if provider == "apple":
        return "local"
    for r in inp["localReady"]:
        if r["provider"] == provider:
            return r["placement"]
    return "local"


def route(inp):
    auto = inp["setting"] == "auto"
    if auto:
        cloud = _cloud_choice(inp)
        local = _local_choice(inp)
        if cloud and (inp["online"] or not local):
            primary = cloud
        elif local:
            primary = local[0]
        else:
            return {"primary": None, "outcome": "empty_state", "answeredBy": None, "label": None, "errorKind": None}
    else:
        primary = inp["setting"]["provider"]
        local = None

    failure = inp["failure"]
    if failure is None:
        return {"primary": primary, "outcome": "ok", "answeredBy": primary,
                "label": _placement(inp, primary), "errorKind": None}
    if failure == "cancelled":
        return {"primary": primary, "outcome": "cancelled", "answeredBy": None, "label": None, "errorKind": None}
    if failure == "interrupted":
        return {"primary": primary, "outcome": "interrupted", "answeredBy": primary,
                "label": _placement(inp, primary), "errorKind": "interrupted"}
    if failure in TEMPORARY and auto and primary in CLOUD and local:
        return {"primary": primary, "outcome": "fallback", "answeredBy": local[0],
                "label": local[1], "errorKind": failure}
    if failure in COUNTDOWN:
        return {"primary": primary, "outcome": "retry_countdown", "answeredBy": None, "label": None, "errorKind": failure}
    return {"primary": primary, "outcome": "error", "answeredBy": None, "label": None, "errorKind": failure}


def check_router():
    print("router-cases.json")
    data = load("router-cases.json")
    for case in data["cases"]:
        inp = dict(data["defaults"])
        inp.update(case["input"])
        check(case["name"], route(inp), case["expect"])


def classify_http(status, body, headers):
    err = (body or {}).get("error") or {}
    code, etype = err.get("code"), err.get("type")
    message = (err.get("message") or "").lower()
    retry = None
    for k, v in (headers or {}).items():
        if k.lower() == "retry-after" and str(v).strip().isdigit():
            retry = int(str(v).strip())
    if code in BILLING_CODES or etype in BILLING_CODES or "credit balance" in message:
        return "billing", retry
    if status in (401, 403):
        return "auth", retry
    if status in (400, 404, 413, 422):
        return "bad_request", retry
    if status == 429:
        return "rate_limited", retry
    if status in (503, 529):
        return "overloaded", retry
    if 500 <= status < 600:
        return "server", retry
    return "bad_request", retry


def check_http():
    print("http-errors.json")
    for case in load("http-errors.json")["cases"]:
        got = classify_http(case["status"], case["body"], case["headers"])
        check(f"{case['status']} → {case['kind']}", got, (case["kind"], case["retryAfter"]))
```

Run: `python3 tests/fixtures/ai/reference.py`
Expected: every router case and every http case `✓`, then `All AI contract checks passed`.

- [ ] **Step 4: Prove the runner catches a wrong fixture**

Change the expected `outcome` of "billing never falls back" to `"fallback"`, then run `python3 tests/fixtures/ai/reference.py`. Expected: `✗ billing never falls back`, exit 1. Revert the change and re-run: everything passes.

- [ ] **Step 5: Commit**

```bash
git add tests/fixtures/ai/router-cases.json tests/fixtures/ai/http-errors.json tests/fixtures/ai/reference.py
git commit -m "test(ai): add router and HTTP error cases with a reference implementation

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3: Context-budget cases

**Files:**
- Create: `tests/fixtures/ai/budget-cases.json`
- Modify: `tests/fixtures/ai/reference.py` (add `budget`, `check_budget`)

**Interfaces:**
- Produces: `budget(placement, contextTokens | null, text) → {keptChars, keptLines, notice}`. Both apps implement this to cut text before sending it.
  - Test text is built as `lineCount` lines, each `lineLength - 1` copies of `fill` (default `"a"`) followed by `"\n"`.
  - `keptChars` counts Unicode scalars.

- [ ] **Step 1: Write `budget-cases.json`**

```json
{
  "version": 1,
  "cases": [
    {"name": "local 4K cuts at whole lines", "placement": "local", "contextTokens": 4096, "lineLength": 10, "lineCount": 1000,
     "expect": {"keptChars": 7160, "keptLines": 716, "notice": "I read the first 716 lines."}},
    {"name": "local 8K keeps everything", "placement": "local", "contextTokens": 8192, "lineLength": 10, "lineCount": 1000,
     "expect": {"keptChars": 10000, "keptLines": 1000, "notice": null}},
    {"name": "local unknown context counts as 4K", "placement": "local", "contextTokens": null, "lineLength": 10, "lineCount": 1000,
     "expect": {"keptChars": 7160, "keptLines": 716, "notice": "I read the first 716 lines."}},
    {"name": "cloud unknown context is capped at 204800", "placement": "cloud", "contextTokens": null, "lineLength": 100, "lineCount": 3000,
     "expect": {"keptChars": 204800, "keptLines": 2048, "notice": "I read the first 2048 lines."}},
    {"name": "cloud huge context still capped", "placement": "cloud", "contextTokens": 1050000, "lineLength": 100, "lineCount": 3000,
     "expect": {"keptChars": 204800, "keptLines": 2048, "notice": "I read the first 2048 lines."}},
    {"name": "first line longer than budget", "placement": "local", "contextTokens": 4096, "lineLength": 10000, "lineCount": 1,
     "expect": {"keptChars": 7168, "keptLines": 0, "notice": "I read the first part of this file."}},
    {"name": "only one line fits", "placement": "local", "contextTokens": 4096, "lineLength": 7000, "lineCount": 3,
     "expect": {"keptChars": 7000, "keptLines": 1, "notice": "I read the first line."}},
    {"name": "exact fit is not truncated", "placement": "local", "contextTokens": 4096, "lineLength": 7168, "lineCount": 1,
     "expect": {"keptChars": 7168, "keptLines": 1, "notice": null}},
    {"name": "empty text", "placement": "local", "contextTokens": 4096, "lineLength": 10, "lineCount": 0,
     "expect": {"keptChars": 0, "keptLines": 0, "notice": null}},
    {"name": "network placement uses local rules", "placement": "network", "contextTokens": 4096, "lineLength": 10, "lineCount": 1000,
     "expect": {"keptChars": 7160, "keptLines": 716, "notice": "I read the first 716 lines."}},
    {"name": "emoji-scalars", "placement": "local", "contextTokens": 4096, "lineLength": 10, "lineCount": 1000, "fill": "🐱",
     "expect": {"keptChars": 7160, "keptLines": 716, "notice": "I read the first 716 lines."}}
  ]
}
```

The `emoji-scalars` case uses one Unicode scalar per 🐱, so its scalar counts match the ASCII case. That fails if an app counts bytes (4 per 🐱).

- [ ] **Step 2: Add the budget reference, then run it**

Add the following, and append `check_budget` to `CHECKS`:

```python
def budget(placement, context_tokens, text):
    limits = load("providers.json")["limits"]
    ctx = context_tokens
    if ctx is None and placement != "cloud":
        ctx = limits["defaultLocalContextTokens"]
    chars = int(ctx * limits["budgetFractionOfContext"] * limits["charsPerToken"]) if ctx else None
    if placement == "cloud":
        cap = limits["cloudTextCapChars"]
        chars = cap if chars is None else min(chars, cap)
    if len(text) <= chars:  # Python len() counts Unicode scalars
        return {"keptChars": len(text), "keptLines": text.count("\n") + (0 if text.endswith("\n") or not text else 1),
                "notice": None}
    kept, lines = 0, 0
    for line in text.splitlines(keepends=True):
        if kept + len(line) > chars:
            break
        kept += len(line)
        lines += 1
    if lines == 0:
        return {"keptChars": chars, "keptLines": 0, "notice": "I read the first part of this file."}
    notice = "I read the first line." if lines == 1 else f"I read the first {lines} lines."
    return {"keptChars": kept, "keptLines": lines, "notice": notice}


def check_budget():
    print("budget-cases.json")
    for case in load("budget-cases.json")["cases"]:
        fill = case.get("fill", "a")
        text = (fill * (case["lineLength"] - 1) + "\n") * case["lineCount"]
        check(case["name"], budget(case["placement"], case["contextTokens"], text), case["expect"])
```

Run: `python3 tests/fixtures/ai/reference.py`
Expected: all budget cases `✓`.

- [ ] **Step 3: Commit**

```bash
git add tests/fixtures/ai/budget-cases.json tests/fixtures/ai/reference.py
git commit -m "test(ai): add context budget cases

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 3b: History trimming cases

**Files:**
- Create: `tests/fixtures/ai/history-cases.json`
- Modify: `tests/fixtures/ai/reference.py` (add `trim_history`, `check_history`)

**Interfaces:**
- Consumes: `providers.json` (`limits.charsPerToken` = 3.5, `limits.defaultLocalContextTokens` = 4,096).
- Produces: `trim_history(placement, contextTokens | null, systemChars, turnChars[]) → {dropped, notice}`. Both apps implement it to decide which of a long chat's oldest turns to leave out before sending. `turnChars` lists each turn's size in Unicode scalars, oldest first. `dropped` counts turns, from the oldest.
- The rule, which is the contract (Windows must match it exactly):
  1. **Cloud** placement: nothing is dropped.
  2. **Context:** `ctx` is `contextTokens`, or 4,096 when it is `null`. `local` and `network` use the same rule.
  3. **Budget:** `budget = ctx − floor(ctx ÷ 4)` tokens. A quarter of the context is kept for the reply.
  4. **Estimate:** `n` scalars cost `ceil(n ÷ 3.5)` tokens, computed as `ceil(2n ÷ 7)` with integers, so no language rounds differently. The estimate is taken over the system prompt plus every remaining turn, in one sum.
  5. **Drop:** while the estimate is over `budget` and more than one turn remains, drop the oldest `min(2, remaining − 1)` turns. A user turn and its reply go together, so the history keeps starting with a user turn.
  6. **Always kept:** the system prompt and the latest turn. If the latest turn alone is over budget it is still sent. An empty history drops nothing.
  7. **Notice:** when `dropped > 0`, the chat shows `This chat got long, so I dropped the oldest messages.`
- **A turn's size** is the sum of its parts in scalars: its text, plus, for each attached file, the file's text (`kind: "text"`) or 1,000 (`binaryAttachmentChars`) for an `image` or `pdf` sent as such.
- **Test text** is built from `{fill, count}`: `fill` repeated `count` times, so its size is `count × scalars(fill)`. The `scalars, not characters or bytes` case fills with a family emoji (5 scalars, 1 grapheme, 18 bytes in UTF-8): an app that counts characters or bytes drops the wrong turns.

- [ ] **Step 1: Write `history-cases.json`**

```json
{
  "version": 1,
  "rule": {
    "reservedOutputDivisor": 4,
    "binaryAttachmentChars": 1000,
    "notice": "This chat got long, so I dropped the oldest messages."
  },
  "cases": [
    {"name": "empty history",
     "placement": "local", "contextTokens": 4096, "system": {"fill": "s", "count": 500}, "turns": [],
     "expect": {"dropped": 0, "notice": null}},
    {"name": "exact fit is not trimmed",
     "placement": "local", "contextTokens": 4096, "system": {"fill": "s", "count": 500},
     "turns": [{"role": "user", "text": {"fill": "u", "count": 5000}},
               {"role": "assistant", "text": {"fill": "a", "count": 5000}},
               {"role": "user", "text": {"fill": "u", "count": 252}}],
     "expect": {"dropped": 0, "notice": null}},
    {"name": "one scalar over drops the oldest pair",
     "placement": "local", "contextTokens": 4096, "system": {"fill": "s", "count": 500},
     "turns": [{"role": "user", "text": {"fill": "u", "count": 5000}},
               {"role": "assistant", "text": {"fill": "a", "count": 5000}},
               {"role": "user", "text": {"fill": "u", "count": 253}}],
     "expect": {"dropped": 2, "notice": "This chat got long, so I dropped the oldest messages."}},
    {"name": "several pairs until it fits (network uses local rules)",
     "placement": "network", "contextTokens": 4096, "system": {"fill": "s", "count": 500},
     "turns": [{"role": "user", "text": {"fill": "u", "count": 3000}},
               {"role": "assistant", "text": {"fill": "a", "count": 3000}},
               {"role": "user", "text": {"fill": "u", "count": 3000}},
               {"role": "assistant", "text": {"fill": "a", "count": 3000}},
               {"role": "user", "text": {"fill": "u", "count": 3000}},
               {"role": "assistant", "text": {"fill": "a", "count": 3000}},
               {"role": "user", "text": {"fill": "u", "count": 3000}}],
     "expect": {"dropped": 4, "notice": "This chat got long, so I dropped the oldest messages."}},
    {"name": "one huge latest message keeps only itself",
     "placement": "local", "contextTokens": 4096, "system": {"fill": "s", "count": 500},
     "turns": [{"role": "user", "text": {"fill": "u", "count": 4000}},
               {"role": "assistant", "text": {"fill": "a", "count": 4000}},
               {"role": "user", "text": {"fill": "u", "count": 20000}}],
     "expect": {"dropped": 2, "notice": "This chat got long, so I dropped the oldest messages."}},
    {"name": "unknown context counts as 4,096 tokens",
     "placement": "local", "contextTokens": null, "system": {"fill": "s", "count": 500},
     "turns": [{"role": "user", "text": {"fill": "u", "count": 4000}},
               {"role": "assistant", "text": {"fill": "a", "count": 4000}},
               {"role": "user", "text": {"fill": "u", "count": 4000}}],
     "expect": {"dropped": 2, "notice": "This chat got long, so I dropped the oldest messages."}},
    {"name": "a larger context keeps everything",
     "placement": "local", "contextTokens": 8192, "system": {"fill": "s", "count": 500},
     "turns": [{"role": "user", "text": {"fill": "u", "count": 4000}},
               {"role": "assistant", "text": {"fill": "a", "count": 4000}},
               {"role": "user", "text": {"fill": "u", "count": 4000}}],
     "expect": {"dropped": 0, "notice": null}},
    {"name": "odd context: the integer line, not a float one",
     "placement": "local", "contextTokens": 5001, "system": {"fill": "s", "count": 500},
     "turns": [{"role": "user", "text": {"fill": "u", "count": 6000}},
               {"role": "assistant", "text": {"fill": "a", "count": 6628}}],
     "expect": {"dropped": 0, "notice": null}},
    {"name": "file text and images count",
     "placement": "local", "contextTokens": 4096, "system": {"fill": "s", "count": 500},
     "turns": [{"role": "user", "text": {"fill": "u", "count": 200},
                "files": [{"kind": "text", "text": {"fill": "f", "count": 8800}}, {"kind": "image"}]},
               {"role": "assistant", "text": {"fill": "a", "count": 300}},
               {"role": "user", "text": {"fill": "u", "count": 200}}],
     "expect": {"dropped": 2, "notice": "This chat got long, so I dropped the oldest messages."}},
    {"name": "scalars, not characters or bytes",
     "placement": "local", "contextTokens": 4096, "system": {"fill": "s", "count": 500},
     "turns": [{"role": "user", "text": {"fill": "👨‍👩‍👧", "count": 1000}},
               {"role": "assistant", "text": {"fill": "👨‍👩‍👧", "count": 1000}},
               {"role": "user", "text": {"fill": "👨‍👩‍👧", "count": 1000}}],
     "expect": {"dropped": 2, "notice": "This chat got long, so I dropped the oldest messages."}},
    {"name": "cloud is never trimmed",
     "placement": "cloud", "contextTokens": null, "system": {"fill": "s", "count": 500},
     "turns": [{"role": "user", "text": {"fill": "u", "count": 90000}},
               {"role": "assistant", "text": {"fill": "a", "count": 90000}},
               {"role": "user", "text": {"fill": "u", "count": 90000}}],
     "expect": {"dropped": 0, "notice": null}}
  ]
}
```

The numbers: 4,096 tokens gives a budget of 3,072 tokens, so a local chat fits while `system + turns` is at most 10,752 scalars (`ceil(2 × 10,752 ÷ 7) = 3,072`). The `exact fit` case sits on that line and `one scalar over` one scalar past it. 8,192 tokens gives 6,144 tokens, or 21,504 scalars. At those two sizes a float formula (`ctx × 0.75 × 3.5`) lands on the same line, so they cannot tell it from the rule. 5,001 tokens can: the budget is 3,751 tokens, which holds 13,128 scalars (`ceil(2 × 13,128 ÷ 7) = 3,751`), while the float formula gives 13,127. The `odd context` case totals exactly 13,128 (500 + 6,000 + 6,628), so the rule keeps both turns and a float formula drops one.

- [ ] **Step 2: Add the rule to the reference, then run it**

Add the following, and append `check_history` to `CHECKS`:

```python
def _est_tokens(scalars):
    """ceil(scalars / 3.5), as integers so no language rounds differently."""
    return -(-scalars * 2 // 7)


def trim_history(placement, context_tokens, system_chars, turn_chars):
    """How many of the oldest turns to drop so a chat fits a small model.

    `turn_chars`: each turn's size in Unicode scalars, oldest first. Returns {dropped, notice}.
    """
    rule = load("history-cases.json")["rule"]
    if placement == "cloud":
        return {"dropped": 0, "notice": None}
    limits = load("providers.json")["limits"]
    ctx = limits["defaultLocalContextTokens"] if context_tokens is None else context_tokens
    budget = ctx - ctx // rule["reservedOutputDivisor"]
    total = system_chars + sum(turn_chars)
    dropped = 0
    while _est_tokens(total) > budget and len(turn_chars) - dropped > 1:
        step = min(2, len(turn_chars) - dropped - 1)
        total -= sum(turn_chars[dropped:dropped + step])
        dropped += step
    return {"dropped": dropped, "notice": rule["notice"] if dropped else None}


def _spec_chars(spec):
    return len(spec["fill"] * spec["count"])  # Python len() counts Unicode scalars


def _turn_chars(turn, rule):
    total = _spec_chars(turn["text"])
    for f in turn.get("files", []):
        total += _spec_chars(f["text"]) if f["kind"] == "text" else rule["binaryAttachmentChars"]
    return total


def check_history():
    print("history-cases.json")
    data = load("history-cases.json")
    rule = data["rule"]
    limits = load("providers.json")["limits"]
    check("rule constants", (rule["reservedOutputDivisor"], rule["binaryAttachmentChars"], limits["charsPerToken"]),
          (4, 1000, 3.5))
    for case in data["cases"]:
        sizes = [_turn_chars(t, rule) for t in case["turns"]]
        got = trim_history(case["placement"], case["contextTokens"], _spec_chars(case["system"]), sizes)
        check(case["name"], got, case["expect"])
```

Run: `python3 tests/fixtures/ai/reference.py`
Expected: under `history-cases.json`, `✓ rule constants` and the eleven cases `✓`, then `All AI contract checks passed`.

- [ ] **Step 3: Prove the cases catch a wrong rule**

In `reference.py`, change `step = min(2, len(turn_chars) - dropped - 1)` to `step = 1`, then run it. Expected: four failures and exit 1: `✗ one scalar over drops the oldest pair`, `✗ unknown context counts as 4,096 tokens`, `✗ file text and images count` and `✗ scalars, not characters or bytes`. Restore the line and re-run: everything passes.

Then change the `while` line to the float formula, `while total > int(ctx * 0.75 * limits["charsPerToken"]) and len(turn_chars) - dropped > 1:`, and run it. Expected: one failure, `✗ odd context: the integer line, not a float one`, exit 1. Restore the line and re-run: everything passes.

- [ ] **Step 4: Commit**

```bash
git add tests/fixtures/ai/history-cases.json tests/fixtures/ai/reference.py
git commit -m "test(ai): add the shared history-trimming rule and cases

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 4: Attachment generator and classification cases

**Files:**
- Create: `tests/fixtures/ai/make_attachments.py`
- Create: `tests/fixtures/ai/attachment-cases.json`
- Modify: `tests/fixtures/ai/reference.py` (add `classify_file`, `check_attachments`)

**Interfaces:**
- Produces:
  - **Generator:** `python3 tests/fixtures/ai/make_attachments.py <dir>` writes every file named in `attachment-cases.json` into `<dir>`.
  - **Classification:** `classify_file(path) → kind | ("rejected", reason)`. Kinds: `text`, `pdf`, `image`, `docx`, `rtf`, `html`, `rejected`.
  - **PDF sub-kinds:** apps also refine `pdf` into `pdf_text` or `pdf_scanned` with their PDF library. The reference accepts either for `pdf`, and the apps' own tests assert the exact sub-kind and the `contains` strings.

- [ ] **Step 1: Write `make_attachments.py`**

```python
#!/usr/bin/env python3
"""Writes NotchMeow's attachment test files into a directory (standard library only)."""
import os
import struct
import sys
import zipfile
import zlib


def pdf(objects):
    out = bytearray(b"%PDF-1.4\n")
    offsets = []
    for i, body in enumerate(objects, start=1):
        offsets.append(len(out))
        out += f"{i} 0 obj\n".encode() + body + b"\nendobj\n"
    xref = len(out)
    out += f"xref\n0 {len(objects) + 1}\n".encode() + b"0000000000 65535 f \n"
    for off in offsets:
        out += f"{off:010d} 00000 n \n".encode()
    out += f"trailer\n<< /Size {len(objects) + 1} /Root 1 0 R >>\nstartxref\n{xref}\n%%EOF\n".encode()
    return bytes(out)


def stream(extra, data):
    return b"<< " + extra + b" /Length " + str(len(data)).encode() + b" >>\nstream\n" + data + b"\nendstream"


CATALOG = b"<< /Type /Catalog /Pages 2 0 R >>"
PAGES = b"<< /Type /Pages /Kids [3 0 R] /Count 1 >>"

TEXT_PDF = pdf([
    CATALOG, PAGES,
    b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 300 144] /Resources << /Font << /F1 4 0 R >> >> /Contents 5 0 R >>",
    b"<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>",
    stream(b"", b"BT /F1 18 Tf 20 70 Td (Hello from NotchMeow) Tj ET"),
])

SCAN_PDF = pdf([
    CATALOG, PAGES,
    b"<< /Type /Page /Parent 2 0 R /MediaBox [0 0 100 100] /Resources << /XObject << /Im1 4 0 R >> >> /Contents 5 0 R >>",
    stream(b"/Type /XObject /Subtype /Image /Width 2 /Height 2 /ColorSpace /DeviceGray /BitsPerComponent 8",
           bytes([0, 255, 255, 0])),
    stream(b"", b"q 100 0 0 100 0 0 cm /Im1 Do Q"),
])


def png_1x1():
    def chunk(tag, data):
        return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    ihdr = struct.pack(">IIBBBBB", 1, 1, 8, 6, 0, 0, 0)
    return b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", ihdr) + chunk(b"IDAT", zlib.compress(b"\x00\xff\x80\x00\xff")) + chunk(b"IEND", b"")


DOCX_PARTS = {
    "[Content_Types].xml": '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types"><Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/><Default Extension="xml" ContentType="application/xml"/><Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/></Types>',
    "_rels/.rels": '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships"><Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/></Relationships>',
    "word/document.xml": '<?xml version="1.0" encoding="UTF-8" standalone="yes"?><w:document xmlns:w="http://schemas.openxmlformats.org/wordprocessingml/2006/main"><w:body><w:p><w:r><w:t>Shrimpy and Momo</w:t></w:r></w:p><w:p><w:r><w:t>live in the notch.</w:t></w:r></w:p></w:body></w:document>',
}

HTML = ("<html><head><style>p{}</style><script>var secret = 'hidden';</script></head>"
        "<body><p>Momo says <b>hi</b></p></body></html>")
RTF = r"{\rtf1\ansi\deff0 {\fonttbl {\f0 Helvetica;}}\f0 Plain RTF text.\par}"


def main(out_dir):
    os.makedirs(out_dir, exist_ok=True)

    def write(name, data):
        with open(os.path.join(out_dir, name), "wb") as f:
            f.write(data if isinstance(data, bytes) else data.encode("utf-8"))

    write("note.txt", "Hello Shrimpy\nSecond line\n")
    write("code.swift", 'print("meow")\n')
    write("empty.txt", b"")
    write("text.pdf", TEXT_PDF)
    write("Upper.PDF", TEXT_PDF)
    write("scan.pdf", SCAN_PDF)
    write("photo.png", png_1x1())
    write("page.html", HTML)
    write("Legacy.HTM", HTML)
    write("doc.rtf", RTF)
    write("setup.exe", b"MZ" + bytes(62))
    write("blob.dat", b"\x00\x01\x02binary\x00")
    with zipfile.ZipFile(os.path.join(out_dir, "letter.docx"), "w", zipfile.ZIP_DEFLATED) as z:
        for name, xml in DOCX_PARTS.items():
            z.writestr(name, xml)
    with zipfile.ZipFile(os.path.join(out_dir, "archive.zip"), "w") as z:
        z.writestr("inside.txt", "packed")
    with open(os.path.join(out_dir, "big.txt"), "wb") as f:
        f.truncate(26214401)  # sparse: 1 byte over the 25 MB limit, takes no real disk space


if __name__ == "__main__":
    main(sys.argv[1])
```

- [ ] **Step 2: Write `attachment-cases.json`**

```json
{
  "version": 1,
  "maxFileBytes": 26214400,
  "rejectExtensions": ["zip", "gz", "tar", "7z", "rar", "dmg", "iso", "pkg", "msi", "exe", "app", "mov", "mp4", "mkv", "avi"],
  "imageExtensions": {"png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg", "gif": "image/gif", "webp": "image/webp", "heic": "image/heic"},
  "cases": [
    {"file": "note.txt", "kind": "text", "contains": ["Hello Shrimpy", "Second line"]},
    {"file": "code.swift", "kind": "text", "contains": ["print(\"meow\")"]},
    {"file": "empty.txt", "kind": "text", "contains": []},
    {"file": "text.pdf", "kind": "pdf_text", "contains": ["Hello from NotchMeow"]},
    {"file": "Upper.PDF", "kind": "pdf_text", "contains": ["Hello from NotchMeow"]},
    {"file": "scan.pdf", "kind": "pdf_scanned"},
    {"file": "photo.png", "kind": "image", "mime": "image/png"},
    {"file": "letter.docx", "kind": "docx", "contains": ["Shrimpy and Momo", "live in the notch."]},
    {"file": "doc.rtf", "kind": "rtf", "contains": ["Plain RTF text."], "notContains": ["Helvetica", "\\par"]},
    {"file": "page.html", "kind": "html", "contains": ["Momo says hi"], "notContains": ["hidden", "p{}"]},
    {"file": "Legacy.HTM", "kind": "html", "contains": ["Momo says hi"], "notContains": ["hidden"]},
    {"file": "archive.zip", "kind": "rejected", "reason": "type"},
    {"file": "setup.exe", "kind": "rejected", "reason": "type"},
    {"file": "blob.dat", "kind": "rejected", "reason": "type"},
    {"file": "big.txt", "kind": "rejected", "reason": "size"}
  ]
}
```

These are the classification rules, in order:
1. Size over `maxFileBytes` → rejected `size`.
2. Lowercased extension: `pdf` → pdf; one of `imageExtensions` → image; `docx`; `rtf`; `html` or `htm` → html; one of `rejectExtensions` → rejected `type`.
3. Otherwise read the first 8,192 bytes. No NUL byte and valid UTF-8 → text. Anything else → rejected `type`. A multi-byte character cut by the 8,192 limit counts as valid.

Extracted HTML text collapses whitespace runs to single spaces and drops `<script>` and `<style>` contents.

- [ ] **Step 3: Add `classify_file` to the reference, then run it**

Add the following, and append `check_attachments` to `CHECKS`:

```python
import subprocess
import tempfile


def classify_file(path, rules):
    if os.path.getsize(path) > rules["maxFileBytes"]:
        return "rejected", "size"
    ext = os.path.splitext(path)[1].lower().lstrip(".")
    if ext == "pdf":
        return "pdf", None
    if ext in rules["imageExtensions"]:
        return "image", None
    if ext in ("docx", "rtf"):
        return ext, None
    if ext in ("html", "htm"):
        return "html", None
    if ext in rules["rejectExtensions"]:
        return "rejected", "type"
    with open(path, "rb") as f:
        head = f.read(8192)
    if b"\x00" in head:
        return "rejected", "type"
    try:
        head.decode("utf-8")
    except UnicodeDecodeError as e:
        if e.start < len(head) - 3:  # only a multi-byte char cut at the very end is allowed
            return "rejected", "type"
    return "text", None


def check_attachments():
    print("attachment-cases.json")
    rules = load("attachment-cases.json")
    with tempfile.TemporaryDirectory() as d:
        subprocess.run([sys.executable, os.path.join(HERE, "make_attachments.py"), d], check=True)
        for case in rules["cases"]:
            kind, reason = classify_file(os.path.join(d, case["file"]), rules)
            expected_kind = "pdf" if case["kind"] in ("pdf_text", "pdf_scanned") else case["kind"]
            check(f"{case['file']} → {case['kind']}", (kind, reason), (expected_kind, case.get("reason")))
```

Run: `python3 tests/fixtures/ai/reference.py`
Expected: all 15 attachment cases `✓`. `big.txt` is sparse, so the run stays fast.

- [ ] **Step 4: Commit**

```bash
git add tests/fixtures/ai/make_attachments.py tests/fixtures/ai/attachment-cases.json tests/fixtures/ai/reference.py
git commit -m "test(ai): add generated attachment files and classification cases

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 5: Recorded SSE streams with expected results

**Files:**
- Create: the 14 stream fixtures below, each with a `.txt` and an `.expected.json`, under `tests/fixtures/ai/sse/openai-chat/`, `tests/fixtures/ai/sse/openai-responses/` and `tests/fixtures/ai/sse/anthropic/`
- Modify: `tests/fixtures/ai/reference.py` (add three aggregators and `check_sse`)

**Interfaces:**
- Produces: `aggregate(format, sse_text) → {text, toolCalls, citations, refusal, finish, error}`. Both apps' stream parsers fold their chunk streams into this shape in tests. The rules:
  - **Text:**
    - `text` concatenates text deltas.
    - For `openai-chat`, `<think>…</think>` blocks are removed. That's existing macOS behaviour.
  - **Tool calls:**
    - `toolCalls` holds client tool calls only; Anthropic `server_tool_use` (web search) is excluded.
    - Each call's `id` is the ID needed to send the result back: Anthropic `tool_use.id`, Responses `call_id`, chat `tool_calls[].id`.
    - `arguments` is the concatenated JSON string.
  - **Citations:** `citations` is deduplicated by URL in first-seen order, each as `{url, title}`.
  - **Refusal:** null unless the provider signals a refusal.
    - Responses: the `response.refusal.done` text.
    - Anthropic: `stop_reason: "refusal"`; the text streamed so far moves to `refusal`, and `text` becomes `""`.
    - Chat: `finish_reason: "content_filter"`, with `refusal` `""`.
  - **Finish reasons:**
    - Anthropic: `end_turn` → `stop`, `max_tokens` → `length`, `tool_use` → `tool_calls`, `refusal` → `refusal`, `stop_sequence` → `stop`.
    - Chat: `stop`, `length` and `tool_calls` stay the same; `content_filter` → `refusal`.
    - Responses: `response.completed` → `tool_calls` if any function call was seen, else `stop`. `response.incomplete` with `max_output_tokens` → `length`. A refusal → `refusal`.
    - `finish` is null when `error` is set.
  - **Errors:**
    - An error event gives an `error` kind: Anthropic `overloaded_error` → `overloaded`, `rate_limit_error` → `rate_limited`, anything else → `server`. Responses `rate_limit_exceeded` → `rate_limited`, billing codes → `billing`, anything else → `server`.
    - `response.failed` maps its `response.error.code` exactly like a Responses error event, so a billing failure never looks temporary.
    - A stream that ends without its terminal event (`data: [DONE]`, `message_stop`, or `response.completed` / `.incomplete` / `.failed`) and with no error → `error: "interrupted"`, keeping the text.
  - **Skipped lines:** lines starting with `:`, `event: ping` blocks, blank lines and `data:` payloads that aren't JSON.

- [ ] **Step 1: Write the OpenAI chat-completions fixtures**

`tests/fixtures/ai/sse/openai-chat/text-think.txt` (each `data:` line is followed by one blank line, as on the wire):

```text
data: {"choices":[{"index":0,"delta":{"role":"assistant","content":"<think>\nplan "}}]}

data: {"choices":[{"index":0,"delta":{"content":"it\n</think>"}}]}

data: {"choices":[{"index":0,"delta":{"content":null,"reasoning_content":"internal"}}]}

data: {"choices":[{"index":0,"delta":{"content":"Hello from "}}]}

data: {"choices":[{"index":0,"delta":{"content":"NotchMeow."}}]}

data: {"choices":[{"index":0,"delta":{},"finish_reason":"stop"}]}

data: [DONE]

```

`tests/fixtures/ai/sse/openai-chat/text-think.expected.json`:

```json
{"text": "Hello from NotchMeow.", "toolCalls": [], "citations": [], "refusal": null, "finish": "stop", "error": null}
```

`tests/fixtures/ai/sse/openai-chat/tool-call.txt`:

```text
data: {"choices":[{"index":0,"delta":{"role":"assistant","content":null,"tool_calls":[{"index":0,"id":"call_1","type":"function","function":{"name":"get_status","arguments":""}}]}}]}

data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"{\"agent\":"}}]}}]}

data: {"choices":[{"index":0,"delta":{"tool_calls":[{"index":0,"function":{"arguments":"\"claude\"}"}}]}}]}

data: {"choices":[{"index":0,"delta":{},"finish_reason":"tool_calls"}]}

data: [DONE]

```

`tests/fixtures/ai/sse/openai-chat/tool-call.expected.json`:

```json
{"text": "", "toolCalls": [{"id": "call_1", "name": "get_status", "arguments": "{\"agent\":\"claude\"}"}], "citations": [], "refusal": null, "finish": "tool_calls", "error": null}
```

`tests/fixtures/ai/sse/openai-chat/keepalive-cut.txt`:

```text
: keep-alive

data: {"choices":[{"index":0,"delta":{"content":"Partial "}}]}

: keep-alive

data: not json at all

data: {"choices":[{"index":0,"delta":{"content":"answer"}}]}

```

`tests/fixtures/ai/sse/openai-chat/keepalive-cut.expected.json`:

```json
{"text": "Partial answer", "toolCalls": [], "citations": [], "refusal": null, "finish": null, "error": "interrupted"}
```

- [ ] **Step 2: Write the OpenAI Responses fixtures**

`tests/fixtures/ai/sse/openai-responses/text-citations.txt`:

```text
event: response.created
data: {"type":"response.created","sequence_number":0,"response":{"id":"resp_1","object":"response","status":"in_progress"}}

event: response.output_item.added
data: {"type":"response.output_item.added","sequence_number":1,"output_index":0,"item":{"type":"web_search_call","id":"ws_1","status":"in_progress"}}

event: response.web_search_call.in_progress
data: {"type":"response.web_search_call.in_progress","sequence_number":2,"output_index":0,"item_id":"ws_1"}

event: response.web_search_call.searching
data: {"type":"response.web_search_call.searching","sequence_number":3,"output_index":0,"item_id":"ws_1"}

event: response.web_search_call.completed
data: {"type":"response.web_search_call.completed","sequence_number":4,"output_index":0,"item_id":"ws_1"}

event: response.output_item.added
data: {"type":"response.output_item.added","sequence_number":5,"output_index":1,"item":{"type":"message","id":"msg_1","status":"in_progress","role":"assistant","content":[]}}

event: response.output_text.delta
data: {"type":"response.output_text.delta","sequence_number":6,"item_id":"msg_1","output_index":1,"content_index":0,"delta":"Cats sleep "}

event: response.output_text.delta
data: {"type":"response.output_text.delta","sequence_number":7,"item_id":"msg_1","output_index":1,"content_index":0,"delta":"a lot."}

event: response.output_text.annotation.added
data: {"type":"response.output_text.annotation.added","sequence_number":8,"item_id":"msg_1","output_index":1,"content_index":0,"annotation_index":0,"annotation":{"type":"url_citation","url":"https://example.com/cats","title":"Cat sleep facts","start_index":0,"end_index":17}}

event: response.output_text.annotation.added
data: {"type":"response.output_text.annotation.added","sequence_number":9,"item_id":"msg_1","output_index":1,"content_index":0,"annotation_index":1,"annotation":{"type":"url_citation","url":"https://example.com/cats","title":"Cat sleep facts","start_index":5,"end_index":17}}

event: response.output_text.done
data: {"type":"response.output_text.done","sequence_number":10,"item_id":"msg_1","output_index":1,"content_index":0,"text":"Cats sleep a lot."}

event: response.completed
data: {"type":"response.completed","sequence_number":11,"response":{"id":"resp_1","object":"response","status":"completed"}}

```

`tests/fixtures/ai/sse/openai-responses/text-citations.expected.json`:

```json
{"text": "Cats sleep a lot.", "toolCalls": [], "citations": [{"url": "https://example.com/cats", "title": "Cat sleep facts"}], "refusal": null, "finish": "stop", "error": null}
```

`tests/fixtures/ai/sse/openai-responses/tool-call.txt`:

```text
event: response.created
data: {"type":"response.created","sequence_number":0,"response":{"id":"resp_2","object":"response","status":"in_progress"}}

event: response.output_item.added
data: {"type":"response.output_item.added","sequence_number":1,"output_index":0,"item":{"type":"function_call","id":"fc_1","call_id":"call_9","name":"get_status","arguments":"","status":"in_progress"}}

event: response.function_call_arguments.delta
data: {"type":"response.function_call_arguments.delta","sequence_number":2,"item_id":"fc_1","output_index":0,"delta":"{\"agent\":"}

event: response.function_call_arguments.delta
data: {"type":"response.function_call_arguments.delta","sequence_number":3,"item_id":"fc_1","output_index":0,"delta":"\"codex\"}"}

event: response.function_call_arguments.done
data: {"type":"response.function_call_arguments.done","sequence_number":4,"item_id":"fc_1","output_index":0,"arguments":"{\"agent\":\"codex\"}"}

event: response.completed
data: {"type":"response.completed","sequence_number":5,"response":{"id":"resp_2","object":"response","status":"completed"}}

```

`tests/fixtures/ai/sse/openai-responses/tool-call.expected.json`:

```json
{"text": "", "toolCalls": [{"id": "call_9", "name": "get_status", "arguments": "{\"agent\":\"codex\"}"}], "citations": [], "refusal": null, "finish": "tool_calls", "error": null}
```

`tests/fixtures/ai/sse/openai-responses/refusal.txt`:

```text
event: response.created
data: {"type":"response.created","sequence_number":0,"response":{"id":"resp_3","object":"response","status":"in_progress"}}

event: response.output_item.added
data: {"type":"response.output_item.added","sequence_number":1,"output_index":0,"item":{"type":"message","id":"msg_3","status":"in_progress","role":"assistant","content":[]}}

event: response.refusal.delta
data: {"type":"response.refusal.delta","sequence_number":2,"item_id":"msg_3","output_index":0,"content_index":0,"delta":"I can't help "}

event: response.refusal.delta
data: {"type":"response.refusal.delta","sequence_number":3,"item_id":"msg_3","output_index":0,"content_index":0,"delta":"with that."}

event: response.refusal.done
data: {"type":"response.refusal.done","sequence_number":4,"item_id":"msg_3","output_index":0,"content_index":0,"refusal":"I can't help with that."}

event: response.completed
data: {"type":"response.completed","sequence_number":5,"response":{"id":"resp_3","object":"response","status":"completed"}}

```

`tests/fixtures/ai/sse/openai-responses/refusal.expected.json`:

```json
{"text": "", "toolCalls": [], "citations": [], "refusal": "I can't help with that.", "finish": "refusal", "error": null}
```

`tests/fixtures/ai/sse/openai-responses/incomplete.txt`:

```text
event: response.created
data: {"type":"response.created","sequence_number":0,"response":{"id":"resp_4","object":"response","status":"in_progress"}}

event: response.output_text.delta
data: {"type":"response.output_text.delta","sequence_number":1,"item_id":"msg_4","output_index":0,"content_index":0,"delta":"Long answer"}

event: response.incomplete
data: {"type":"response.incomplete","sequence_number":2,"response":{"id":"resp_4","object":"response","status":"incomplete","incomplete_details":{"reason":"max_output_tokens"}}}

```

`tests/fixtures/ai/sse/openai-responses/incomplete.expected.json`:

```json
{"text": "Long answer", "toolCalls": [], "citations": [], "refusal": null, "finish": "length", "error": null}
```

`tests/fixtures/ai/sse/openai-responses/failed.txt`:

```text
event: response.created
data: {"type":"response.created","sequence_number":0,"response":{"id":"resp_5","object":"response","status":"in_progress"}}

event: response.failed
data: {"type":"response.failed","sequence_number":1,"response":{"id":"resp_5","object":"response","status":"failed","error":{"code":"server_error","message":"The server had an error."}}}

```

`tests/fixtures/ai/sse/openai-responses/failed.expected.json`:

```json
{"text": "", "toolCalls": [], "citations": [], "refusal": null, "finish": null, "error": "server"}
```

`tests/fixtures/ai/sse/openai-responses/error-event.txt`:

```text
event: response.created
data: {"type":"response.created","sequence_number":0,"response":{"id":"resp_6","object":"response","status":"in_progress"}}

event: response.output_text.delta
data: {"type":"response.output_text.delta","sequence_number":1,"item_id":"msg_6","output_index":0,"content_index":0,"delta":"Hel"}

event: error
data: {"type":"error","sequence_number":2,"code":"rate_limit_exceeded","message":"Rate limit reached.","param":null}

```

`tests/fixtures/ai/sse/openai-responses/error-event.expected.json`:

```json
{"text": "Hel", "toolCalls": [], "citations": [], "refusal": null, "finish": null, "error": "rate_limited"}
```

- [ ] **Step 3: Write the Anthropic fixtures**

`tests/fixtures/ai/sse/anthropic/text-websearch.txt`:

```text
event: message_start
data: {"type":"message_start","message":{"id":"msg_01","type":"message","role":"assistant","model":"claude-sonnet-5-5","content":[],"stop_reason":null,"usage":{"input_tokens":12,"output_tokens":1}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"server_tool_use","id":"srvtoolu_1","name":"web_search","input":{}}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"query\":\"cat sleep\"}"}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: content_block_start
data: {"type":"content_block_start","index":1,"content_block":{"type":"web_search_tool_result","tool_use_id":"srvtoolu_1","content":[{"type":"web_search_result","url":"https://example.com/cats","title":"Cat sleep facts","encrypted_content":"abc","page_age":null}]}}

event: content_block_stop
data: {"type":"content_block_stop","index":1}

event: content_block_start
data: {"type":"content_block_start","index":2,"content_block":{"type":"text","text":""}}

event: ping
data: {"type":"ping"}

event: content_block_delta
data: {"type":"content_block_delta","index":2,"delta":{"type":"citations_delta","citation":{"type":"web_search_result_location","url":"https://example.com/cats","title":"Cat sleep facts","encrypted_index":"xyz","cited_text":"Cats sleep 12 to 16 hours"}}}

event: content_block_delta
data: {"type":"content_block_delta","index":2,"delta":{"type":"text_delta","text":"Cats sleep "}}

event: content_block_delta
data: {"type":"content_block_delta","index":2,"delta":{"type":"text_delta","text":"a lot."}}

event: content_block_stop
data: {"type":"content_block_stop","index":2}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"end_turn","stop_sequence":null},"usage":{"output_tokens":20}}

event: message_stop
data: {"type":"message_stop"}

```

`tests/fixtures/ai/sse/anthropic/text-websearch.expected.json`:

```json
{"text": "Cats sleep a lot.", "toolCalls": [], "citations": [{"url": "https://example.com/cats", "title": "Cat sleep facts"}], "refusal": null, "finish": "stop", "error": null}
```

`tests/fixtures/ai/sse/anthropic/tool-use.txt`:

```text
event: message_start
data: {"type":"message_start","message":{"id":"msg_02","type":"message","role":"assistant","model":"claude-sonnet-5-5","content":[],"stop_reason":null,"usage":{"input_tokens":20,"output_tokens":1}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"toolu_1","name":"get_status","input":{}}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"{\"agent\":"}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"input_json_delta","partial_json":"\"gemini\"}"}}

event: content_block_stop
data: {"type":"content_block_stop","index":0}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"tool_use","stop_sequence":null},"usage":{"output_tokens":9}}

event: message_stop
data: {"type":"message_stop"}

```

`tests/fixtures/ai/sse/anthropic/tool-use.expected.json`:

```json
{"text": "", "toolCalls": [{"id": "toolu_1", "name": "get_status", "arguments": "{\"agent\":\"gemini\"}"}], "citations": [], "refusal": null, "finish": "tool_calls", "error": null}
```

`tests/fixtures/ai/sse/anthropic/refusal.txt`:

```text
event: message_start
data: {"type":"message_start","message":{"id":"msg_03","type":"message","role":"assistant","model":"claude-sonnet-5-5","content":[],"stop_reason":null,"usage":{"input_tokens":5,"output_tokens":1}}}

event: message_delta
data: {"type":"message_delta","delta":{"stop_reason":"refusal","stop_sequence":null},"usage":{"output_tokens":1}}

event: message_stop
data: {"type":"message_stop"}

```

`tests/fixtures/ai/sse/anthropic/refusal.expected.json`:

```json
{"text": "", "toolCalls": [], "citations": [], "refusal": "", "finish": "refusal", "error": null}
```

`tests/fixtures/ai/sse/anthropic/error-overloaded.txt`:

```text
event: message_start
data: {"type":"message_start","message":{"id":"msg_04","type":"message","role":"assistant","model":"claude-sonnet-5-5","content":[],"stop_reason":null,"usage":{"input_tokens":5,"output_tokens":1}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Hi"}}

event: error
data: {"type":"error","error":{"type":"overloaded_error","message":"Overloaded"}}

```

`tests/fixtures/ai/sse/anthropic/error-overloaded.expected.json`:

```json
{"text": "Hi", "toolCalls": [], "citations": [], "refusal": null, "finish": null, "error": "overloaded"}
```

`tests/fixtures/ai/sse/anthropic/cut.txt`:

```text
event: message_start
data: {"type":"message_start","message":{"id":"msg_05","type":"message","role":"assistant","model":"claude-sonnet-5-5","content":[],"stop_reason":null,"usage":{"input_tokens":5,"output_tokens":1}}}

event: content_block_start
data: {"type":"content_block_start","index":0,"content_block":{"type":"text","text":""}}

event: content_block_delta
data: {"type":"content_block_delta","index":0,"delta":{"type":"text_delta","text":"Partial"}}

```

`tests/fixtures/ai/sse/anthropic/cut.expected.json`:

```json
{"text": "Partial", "toolCalls": [], "citations": [], "refusal": null, "finish": null, "error": "interrupted"}
```

- [ ] **Step 4: Add the aggregators to the reference, then run them**

Add the following, and append `check_sse` to `CHECKS`:

```python
import glob
import re

THINK = re.compile(r"<think>.*?</think>", re.DOTALL)


def _events(sse_text):
    """Yields parsed JSON payloads; skips comments, pings, blanks and non-JSON data."""
    for line in sse_text.splitlines():
        if not line.startswith("data:"):
            continue
        payload = line[5:].strip()
        if payload == "[DONE]":
            yield "[DONE]"
            continue
        try:
            yield json.loads(payload)
        except ValueError:
            continue


def _result(text="", tools=None, cites=None, refusal=None, finish=None, error=None):
    seen, uniq = set(), []
    for c in cites or []:
        if c["url"] not in seen:
            seen.add(c["url"])
            uniq.append(c)
    return {"text": text, "toolCalls": tools or [], "citations": uniq, "refusal": refusal,
            "finish": None if error else finish, "error": error}


def agg_openai_chat(sse_text):
    text, tools, finish, done = "", {}, None, False
    for ev in _events(sse_text):
        if ev == "[DONE]":
            done = True
            continue
        for ch in ev.get("choices", []):
            d = ch.get("delta") or {}
            if isinstance(d.get("content"), str):
                text += d["content"]
            for tc in d.get("tool_calls") or []:
                slot = tools.setdefault(tc["index"], {"id": "", "name": "", "arguments": ""})
                slot["id"] = tc.get("id") or slot["id"]
                fn = tc.get("function") or {}
                slot["name"] = fn.get("name") or slot["name"]
                slot["arguments"] += fn.get("arguments") or ""
            if ch.get("finish_reason"):
                finish = {"content_filter": "refusal"}.get(ch["finish_reason"], ch["finish_reason"])
    text = THINK.sub("", text)
    refusal = "" if finish == "refusal" else None
    return _result(text, [tools[k] for k in sorted(tools)], [], refusal, finish,
                   None if done else "interrupted")


def _responses_error_kind(code):
    """One mapping for `error` events and `response.failed`: billing must never look temporary."""
    if code == "rate_limit_exceeded":
        return "rate_limited"
    if code in BILLING_CODES:
        return "billing"
    return "server"


def agg_openai_responses(sse_text):
    text, calls, cites, refusal, finish, error, terminal = "", {}, [], None, None, None, False
    for ev in _events(sse_text):
        if ev == "[DONE]":
            continue
        t = ev.get("type")
        if t == "response.output_text.delta":
            text += ev["delta"]
        elif t == "response.output_item.added" and ev["item"].get("type") == "function_call":
            it = ev["item"]
            calls[it["id"]] = {"id": it["call_id"], "name": it["name"], "arguments": it.get("arguments", "")}
        elif t == "response.function_call_arguments.delta":
            calls[ev["item_id"]]["arguments"] += ev["delta"]
        elif t == "response.function_call_arguments.done":
            calls[ev["item_id"]]["arguments"] = ev["arguments"]
        elif t == "response.output_text.annotation.added" and ev["annotation"].get("type") == "url_citation":
            cites.append({"url": ev["annotation"]["url"], "title": ev["annotation"].get("title", "")})
        elif t == "response.refusal.done":
            refusal = ev["refusal"]
        elif t == "response.completed":
            terminal = True
            finish = "refusal" if refusal is not None else ("tool_calls" if calls else "stop")
        elif t == "response.incomplete":
            terminal = True
            reason = (ev["response"].get("incomplete_details") or {}).get("reason")
            finish = "refusal" if reason == "content_filter" else "length"
        elif t == "response.failed":
            terminal = True
            error = _responses_error_kind((ev["response"].get("error") or {}).get("code"))
        elif t == "error":
            error = _responses_error_kind(ev.get("code"))
    if not terminal and not error:
        error = "interrupted"
    return _result(text, list(calls.values()), cites, refusal, finish, error)


def agg_anthropic(sse_text):
    text, blocks, cites, finish, error, stopped = "", {}, [], None, None, False
    for ev in _events(sse_text):
        if ev == "[DONE]":
            continue
        t = ev.get("type")
        if t == "content_block_start":
            blocks[ev["index"]] = dict(ev["content_block"], _args="")
        elif t == "content_block_delta":
            d = ev["delta"]
            if d["type"] == "text_delta":
                text += d["text"]
            elif d["type"] == "input_json_delta":
                blocks[ev["index"]]["_args"] += d["partial_json"]
            elif d["type"] == "citations_delta":
                cites.append({"url": d["citation"]["url"], "title": d["citation"].get("title", "")})
        elif t == "message_delta":
            sr = ev["delta"].get("stop_reason")
            finish = {"end_turn": "stop", "max_tokens": "length", "tool_use": "tool_calls",
                      "refusal": "refusal", "stop_sequence": "stop"}.get(sr, finish)
        elif t == "message_stop":
            stopped = True
        elif t == "error":
            et = ev["error"]["type"]
            error = {"overloaded_error": "overloaded", "rate_limit_error": "rate_limited"}.get(et, "server")
    tools = [{"id": b["id"], "name": b["name"], "arguments": b["_args"]}
             for _, b in sorted(blocks.items()) if b["type"] == "tool_use"]
    refusal = None
    if finish == "refusal":
        refusal, text = text, ""
    if not stopped and not error:
        error = "interrupted"
    return _result(text, tools, cites, refusal, finish, error)


AGGREGATORS = {"openai-chat": agg_openai_chat, "openai-responses": agg_openai_responses, "anthropic": agg_anthropic}


def check_sse():
    print("sse/")
    for fmt, fn in AGGREGATORS.items():
        for path in sorted(glob.glob(os.path.join(HERE, "sse", fmt, "*.txt"))):
            with open(path, encoding="utf-8") as f:
                got = fn(f.read())
            with open(path[:-4] + ".expected.json", encoding="utf-8") as f:
                expected = json.load(f)
            check(f"{fmt}/{os.path.basename(path)}", got, expected)
```

Run: `python3 tests/fixtures/ai/reference.py`
Expected: 14 `sse/` cases `✓`, plus all earlier sections.

- [ ] **Step 5: Commit**

```bash
git add tests/fixtures/ai/sse tests/fixtures/ai/reference.py
git commit -m "test(ai): add recorded SSE streams for chat, Responses and Anthropic

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 6: Fake server personas, failure modes and new routes

**Files:**
- Modify: `tests/fake_local_llm.py`
- Create: `tests/test_fake_server.py`

**Interfaces:**
- Consumes: the `sse/` fixtures from Task 5. The new routes stream those files, so the fake server and the parsers share one source.
- Produces: the command line `python3 tests/fake_local_llm.py <port-file> [--persona P] [--fail F] [--delay S] [--log PATH]`.
  - `--persona`: `generic` (default, the current behaviour), `ollama`, `lmstudio`, `llamacpp`, `jan`.
  - `--fail`: `none` (default), `timeout`, `500`, `429`, `401`, `billing`, `overloaded`, `cut`, `slow-first-token`, `refuse`.
  - `--delay`: seconds for `timeout` and `slow-first-token` (default 3).
  - `--log`: appends one JSON line per request: `{"method", "path", "origin", "body"}`.
  - **Routes:**
    - `POST /v1/chat/completions`: the existing stream when `--fail none` and no client function tool. With one, it streams `sse/openai-chat/tool-call.txt`.
    - `POST /v1/responses`: streams `text-citations.txt`, or `tool-call.txt` when `tools` holds a client function tool (hosted `web_search` doesn't count), or `refusal.txt` under `--fail refuse`.
    - `POST /v1/messages`: streams `anthropic/text-websearch.txt`, or `tool-use.txt` / `refusal.txt` the same way.
    - `GET /api/version` (ollama only), `GET /health` (llamacpp only) and `GET /api/tags` (ollama only).
    - Other personas 404 on the persona-only routes.
  - **Failure responses:**
    - `500`: status 500 with the http-errors 500 body.
    - `429`: status 429 with `Retry-After: 2` and the `slow_down` body.
    - `401`: status 401.
    - `billing`: status 429 with the `insufficient_quota` body.
    - `overloaded`: status 529 on `/v1/messages`, 503 with `Retry-After: 7` elsewhere.
    - `cut`: sends the first half of the stream's lines, then closes.
    - `timeout`: sleeps `--delay` seconds before sending headers.
    - `slow-first-token`: sends headers, sleeps `--delay` seconds, then streams.

- [ ] **Step 1: Write the failing tests**

`tests/test_fake_server.py`:

```python
#!/usr/bin/env python3
"""Tests for tests/fake_local_llm.py (standard library only)."""
import json
import os
import subprocess
import sys
import tempfile
import time
import unittest
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.abspath(__file__))
SERVER = os.path.join(ROOT, "fake_local_llm.py")
FIX = os.path.join(ROOT, "fixtures", "ai")


class Server:
    def __init__(self, *flags):
        self.tmp = tempfile.TemporaryDirectory()
        self.port_file = os.path.join(self.tmp.name, "port")
        self.log = os.path.join(self.tmp.name, "log.jsonl")
        self.proc = subprocess.Popen([sys.executable, SERVER, self.port_file, "--log", self.log, *flags])
        for _ in range(300):
            if os.path.exists(self.port_file) and os.path.getsize(self.port_file):
                break
            time.sleep(0.01)
        with open(self.port_file) as f:
            self.base = f"http://127.0.0.1:{f.read().strip()}"

    def get(self, path):
        with urllib.request.urlopen(self.base + path, timeout=5) as r:
            return r.status, r.read().decode()

    def post(self, path, body, timeout=10, headers=None):
        req = urllib.request.Request(self.base + path, data=json.dumps(body).encode(),
                                     headers={"Content-Type": "application/json", **(headers or {})})
        try:
            with urllib.request.urlopen(req, timeout=timeout) as r:
                return r.status, dict(r.headers), r.read().decode()
        except urllib.error.HTTPError as e:
            return e.code, dict(e.headers), e.read().decode()

    def requests(self):
        with open(self.log) as f:
            return [json.loads(line) for line in f]

    def close(self):
        self.proc.kill()
        self.proc.wait()
        self.tmp.cleanup()


def fixture(*parts):
    with open(os.path.join(FIX, "sse", *parts), encoding="utf-8") as f:
        return f.read()


class FakeServerTests(unittest.TestCase):
    def test_generic_keeps_old_models_route(self):
        s = Server()
        try:
            status, body = self.get_ok(s, "/v1/models")
            self.assertEqual([m["id"] for m in json.loads(body)["data"]], ["llama3.2", "nomic-embed-text"])
        finally:
            s.close()

    def test_query_strings_are_ignored(self):
        s = Server()
        try:
            status, body = self.get_ok(s, "/v1/models?limit=100")
            self.assertEqual(json.loads(body)["data"][0]["id"], "llama3.2")
        finally:
            s.close()

    def test_ollama_persona_has_version(self):
        s = Server("--persona", "ollama")
        try:
            status, body = self.get_ok(s, "/api/version")
            self.assertIn("version", json.loads(body))
        finally:
            s.close()

    def test_llamacpp_persona_has_health_and_generic_does_not(self):
        s = Server("--persona", "llamacpp")
        g = Server()
        try:
            self.assertEqual(self.get_ok(s, "/health")[0], 200)
            with self.assertRaises(urllib.error.HTTPError):
                g.get("/health")
        finally:
            s.close()
            g.close()

    def test_responses_route_streams_fixture(self):
        s = Server()
        try:
            status, _, body = s.post("/v1/responses", {"model": "gpt-6.1-sol", "input": "hi", "store": False})
            self.assertEqual(status, 200)
            self.assertEqual(body, fixture("openai-responses", "text-citations.txt"))
            self.assertIs(s.requests()[0]["body"]["store"], False)
        finally:
            s.close()

    def test_messages_route_with_tools_streams_tool_use(self):
        s = Server()
        try:
            _, _, body = s.post("/v1/messages", {"model": "claude-sonnet-5-5", "tools": [{"name": "get_status"}]})
            self.assertEqual(body, fixture("anthropic", "tool-use.txt"))
        finally:
            s.close()

    def test_hosted_web_search_alone_still_streams_text(self):
        s = Server()
        try:
            _, _, body = s.post("/v1/responses", {"model": "gpt-6.1-sol", "tools": [{"type": "web_search"}]})
            self.assertEqual(body, fixture("openai-responses", "text-citations.txt"))
            _, _, body = s.post("/v1/messages", {"model": "claude-sonnet-5-5",
                                                 "tools": [{"type": "web_search_20250305", "name": "web_search"}]})
            self.assertEqual(body, fixture("anthropic", "text-websearch.txt"))
        finally:
            s.close()

    def test_429_has_retry_after(self):
        s = Server("--fail", "429")
        try:
            status, headers, body = s.post("/v1/responses", {"model": "x"})
            self.assertEqual(status, 429)
            self.assertEqual(headers.get("Retry-After"), "2")
            self.assertEqual(json.loads(body)["error"]["code"], "slow_down")
        finally:
            s.close()

    def test_billing_is_429_insufficient_quota(self):
        s = Server("--fail", "billing")
        try:
            status, _, body = s.post("/v1/responses", {"model": "x"})
            self.assertEqual((status, json.loads(body)["error"]["code"]), (429, "insufficient_quota"))
        finally:
            s.close()

    def test_overloaded_is_529_on_messages(self):
        s = Server("--fail", "overloaded")
        try:
            self.assertEqual(s.post("/v1/messages", {"model": "x"})[0], 529)
            self.assertEqual(s.post("/v1/responses", {"model": "x"})[0], 503)
        finally:
            s.close()

    def test_cut_sends_partial_stream(self):
        s = Server("--fail", "cut")
        try:
            _, _, body = s.post("/v1/messages", {"model": "x"})
            full = fixture("anthropic", "text-websearch.txt")
            self.assertTrue(full.startswith(body) and len(body) < len(full))
            self.assertNotIn("message_stop", body)
        finally:
            s.close()

    def test_timeout_delays_headers(self):
        s = Server("--fail", "timeout", "--delay", "2")
        try:
            with self.assertRaises(Exception):
                s.post("/v1/chat/completions", {"model": "llama3.2"}, timeout=0.5)
        finally:
            s.close()

    def test_log_records_origin_header(self):
        s = Server()
        try:
            s.post("/v1/chat/completions", {"model": "llama3.2"}, headers={"Origin": "http://tauri.localhost"})
            self.assertEqual(s.requests()[0]["origin"], "http://tauri.localhost")
        finally:
            s.close()

    def get_ok(self, s, path):
        status, body = s.get(path)
        self.assertEqual(status, 200)
        return status, body


if __name__ == "__main__":
    unittest.main(verbosity=2)
```

- [ ] **Step 2: Run the tests to see them fail**

Run: `python3 tests/test_fake_server.py`
Expected: FAIL. `--log` is an unrecognised argument, so the server exits and the port file never appears; most tests error.

- [ ] **Step 3: Extend `tests/fake_local_llm.py`**

Keep `MODELS_RESPONSE`, `SSE_EVENTS`, `EXPECTED_RESPONSE`, `FastBindHTTPServer` and `find_free_port` exactly as they are. Update the docstring's usage line to the new command line. Replace the `FakeLLMHandler` class and the `__main__` block with:

```python
import argparse
import os

FIXTURES = os.path.join(os.path.dirname(os.path.abspath(__file__)), "fixtures", "ai", "sse")
OPTS = argparse.Namespace(persona="generic", fail="none", delay=3.0, log=None)

ERROR_BODIES = {
    "500": (500, {}, {"type": "error", "error": {"type": "api_error", "message": "Internal server error"}}),
    "429": (429, {"Retry-After": "2"}, {"error": {"type": "rate_limit_error", "code": "slow_down", "message": "Slow down"}}),
    "401": (401, {}, {"type": "error", "error": {"type": "authentication_error", "message": "invalid x-api-key"}}),
    "billing": (429, {}, {"error": {"type": "insufficient_quota", "code": "insufficient_quota", "message": "You exceeded your current quota"}}),
}


def has_client_tools(fmt, tools):
    """True when the request carries a client-side function tool.

    Hosted tools don't count: Anthropic `{"type": "web_search_20250305", ...}` and
    Responses `{"type": "web_search"}`. Claude and OpenAI requests always carry web
    search, and must still get a text stream.
    """
    for t in tools or []:
        ttype = t.get("type", "")
        if fmt == "anthropic":
            if not ttype.startswith("web_search"):  # custom tools: name + input_schema, no server type
                return True
        elif ttype == "function":
            return True
    return False


def read_fixture(fmt, name):
    with open(os.path.join(FIXTURES, fmt, name), encoding="utf-8") as f:
        return f.read()


class FakeLLMHandler(BaseHTTPRequestHandler):
    def log_message(self, fmt, *args):
        pass  # suppress request logging

    def _send_json(self, status, payload, headers=None):
        body = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        for k, v in (headers or {}).items():
            self.send_header(k, v)
        self.end_headers()
        self.wfile.write(body)

    def _log(self, body):
        if OPTS.log:
            with open(OPTS.log, "a") as f:
                f.write(json.dumps({"method": self.command, "path": self.path,
                                    "origin": self.headers.get("Origin"), "body": body}) + "\n")

    def do_GET(self):
        self._log(None)
        persona_routes = {
            ("ollama", "/api/version"): {"version": "0.35.1"},
            ("ollama", "/api/tags"): {"models": [{"name": "qwen3.5:2b"}, {"name": "nomic-embed-text"}]},
            ("llamacpp", "/health"): {"status": "ok"},
        }
        path = self.path.split("?", 1)[0]  # real APIs take queries such as ?limit=100
        if path == "/v1/models":
            self._send_json(200, MODELS_RESPONSE)
        elif (OPTS.persona, path) in persona_routes:
            self._send_json(200, persona_routes[(OPTS.persona, path)])
        else:
            self.send_response(404)
            self.end_headers()

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        raw = self.rfile.read(length)
        try:
            req_body = json.loads(raw)
        except Exception:
            req_body = {}
        self._log(req_body)

        routes = {"/v1/chat/completions": "openai-chat", "/v1/responses": "openai-responses",
                  "/v1/messages": "anthropic"}
        fmt = routes.get(self.path.split("?", 1)[0])
        if fmt is None:
            self.send_response(404)
            self.end_headers()
            return

        model = req_body.get("model", "")
        if fmt == "openai-chat" and model == "unknown-model":
            self._send_json(404, {"error": {"message": f"model '{model}' not found, try pulling it first",
                                            "type": "not_found"}})
            return

        if OPTS.fail == "timeout":
            time.sleep(OPTS.delay)
        if OPTS.fail in ERROR_BODIES:
            status, headers, payload = ERROR_BODIES[OPTS.fail]
            self._send_json(status, payload, headers)
            return
        if OPTS.fail == "overloaded":
            if fmt == "anthropic":
                self._send_json(529, {"type": "error", "error": {"type": "overloaded_error", "message": "Overloaded"}})
            else:
                self._send_json(503, {"error": {"type": "service_unavailable_error", "code": "server_is_overloaded",
                                                "message": "Busy"}}, {"Retry-After": "7"})
            return

        client_tools = has_client_tools(fmt, req_body.get("tools"))
        if fmt == "openai-chat" and not client_tools and OPTS.fail != "cut":
            text = "".join("data: " + json.dumps(e) + "\n\n" for e in SSE_EVENTS) + "data: [DONE]\n\n"
        else:
            name = {"openai-chat": "text-think.txt", "openai-responses": "text-citations.txt",
                    "anthropic": "text-websearch.txt"}[fmt]
            if client_tools:
                name = {"openai-chat": "tool-call.txt", "openai-responses": "tool-call.txt",
                        "anthropic": "tool-use.txt"}[fmt]
            if OPTS.fail == "refuse" and fmt != "openai-chat":
                name = "refusal.txt"
            text = read_fixture(fmt, name)

        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.end_headers()
        if OPTS.fail == "slow-first-token":
            self.wfile.flush()
            time.sleep(OPTS.delay)
        if OPTS.fail == "cut":
            # Exactly the first half of the lines, in one write, so the client sees a prefix
            # of the full stream with no terminal event.
            lines = text.splitlines(keepends=True)
            self.wfile.write("".join(lines[: len(lines) // 2]).encode())
            self.wfile.flush()
        else:
            for chunk in text.split("\n\n"):
                if chunk:
                    self.wfile.write((chunk + "\n\n").encode())
                    self.wfile.flush()
                    time.sleep(0.005)
        self.close_connection = True
```

Replace the `__main__` block with:

```python
if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("port_file", nargs="?")
    parser.add_argument("--persona", default="generic", choices=["generic", "ollama", "lmstudio", "llamacpp", "jan"])
    parser.add_argument("--fail", default="none", choices=["none", "timeout", "500", "429", "401", "billing",
                                                           "overloaded", "cut", "slow-first-token", "refuse"])
    parser.add_argument("--delay", type=float, default=3.0)
    parser.add_argument("--log")
    args = parser.parse_args()
    OPTS.persona, OPTS.fail, OPTS.delay, OPTS.log = args.persona, args.fail, args.delay, args.log

    port = find_free_port()
    server = FastBindHTTPServer(("127.0.0.1", port), FakeLLMHandler)

    # Write port to the file passed as argv[1] so the caller can read it
    if args.port_file:
        with open(args.port_file, "w") as f:
            f.write(str(port))
            f.flush()

    server.serve_forever()
```

- [ ] **Step 4: Run the new tests and the old chat-parsing test**

Run: `python3 tests/test_fake_server.py`
Expected: `Ran 13 tests … OK`.

Run: `bash scripts/test-chat-parsing.sh`
Expected: the same `✓` output as before this task. This proves the no-flag behaviour is unchanged.

- [ ] **Step 5: Commit**

```bash
git add tests/fake_local_llm.py tests/test_fake_server.py
git commit -m "test(ai): fake server gains personas, failure modes, Responses and Messages routes

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

### Task 7: Run the contract in CI

**Files:**
- Modify: `.github/workflows/build.yml` (add one step before `Test chat parsing`)

**Interfaces:**
- Consumes: `scripts/test-ai-contract.sh` (Task 1).

- [ ] **Step 1: Add the CI step**

In `.github/workflows/build.yml`, insert this step before the `- name: Test chat parsing` step, at the same indentation:

```yaml
      - name: AI contract (fixtures + fake server)
        run: bash scripts/test-ai-contract.sh
```

- [ ] **Step 2: Run the whole contract locally the way CI will**

Run: `bash scripts/test-ai-contract.sh && bash scripts/test-chat-parsing.sh`
Expected: `All AI contract checks passed`, `Ran 13 tests … OK`, then the chat-parsing `✓` lines. Exit 0.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/build.yml
git commit -m "ci: run the shared AI contract

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---

## Self-review notes

- **Spec coverage:** this plan covers the contract parts of spec §6: the shared cases, the fake-server personas and failure modes, the Anthropic and Responses routes, and the debug-only redirect target. It also provides the router (§1/§5), error (§5), budget (§3), history-trimming (§5, "Context overflow") and classification (§3) rules that both apps implement. App behaviour itself is covered in E1-mac and E1-tauri.
- **Four rules made explicit here:**
  - **`unreachable`** (connection refused, DNS failure) is separate from `offline` (the OS reports no network). The spec's "Local server unreachable" message needs its own kind.
  - **Billing detection:** Anthropic's low-credit response is a 400 whose message contains "credit balance", not a 429.
  - **History trimming:** the spec says only "drops the oldest turns, never the system prompt or the latest message". Task 3b fixes the numbers (a quarter of the context kept for the reply, tokens estimated as scalars ÷ 3.5, pairs dropped oldest first) so the Mac and Windows apps cut at the same turn.
  - **Reply length:** `maxOutputTokens` in `providers.json` gives cloud 16,000 and local and network 4,096, so both apps ask for the same length and a reasoning model has room to answer.
