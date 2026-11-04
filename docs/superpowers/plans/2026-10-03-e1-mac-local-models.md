# E1 (macOS) Local Models Everywhere Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Every NotchMeow chat and file question on the Mac can be answered by a cloud model (Anthropic, OpenAI, Google) or a local one (Ollama, LM Studio, llama.cpp, Jan, a server the user adds, Apple's on-device model), chosen per feature by Auto or by the user, streamed, labelled `local` / `network` / `cloud`, with one local retry when the cloud has a passing problem.

**Architecture:**
- A Foundation-only AI core in `NotchBuddy/Sources/App/AI/Core/` holds the types, the provider catalog, the router (a pure function), the three SSE parsers, HTTP error classification, the context budget, the attachment plan, the providers, discovery and the chat runner. Because it imports only Foundation, `scripts/test-ai-*.sh` compile it with `swiftc` next to small `@main` test programs, like the existing tests, and run every case in E1-0's `tests/fixtures/ai/` files.
- Frameworks stay out of the core: `AI/Platform/` holds PDFKit + Vision + AppKit extraction, `NWPathMonitor`, and FoundationModels (behind `#if canImport(FoundationModels)` + `@available(macOS 26, *)`, weak-linked).
- `AI/AIService.swift` is the only glue between `AppState` and the core. `ClaudeService` keeps the conversation and the UI state and calls the router.

**Tech Stack:** Swift 6 (strict concurrency), SwiftUI + AppKit, Foundation `URLSession` streaming, PDFKit, Vision, Network, FoundationModels (macOS 26+, weak), XcodeGen, Python 3 fake server from E1-0, Bash, GitHub Actions. No third-party dependencies.

**Spec:** `docs/superpowers/specs/2026-10-03-local-models-design.md` (revision 1, OpenAI first-class).

**Depends on:** `docs/superpowers/plans/2026-10-03-e1-0-shared-ai-contract.md`. It must be merged first. This plan consumes:
- `tests/fixtures/ai/providers.json` (including its `webSearch` object with `legacyType` and `legacyModelPrefixes`, and its `maxOutputTokens` object: the reply length per placement), `router-cases.json`, `http-errors.json`, `budget-cases.json`, `history-cases.json` (Task 3b), `attachment-cases.json` + `make_attachments.py`, and `sse/<format>/*.txt` + `.expected.json`;
- `tests/fake_local_llm.py` with `--persona`, `--fail`, `--delay` and `--log`, serving `/v1/chat/completions`, `/v1/responses` and `/v1/messages`:
  - only a client function tool selects a tool-call stream (`has_client_tools`); hosted web search still gets the text stream;
  - query strings are ignored, so `GET /v1/models?limit=100` works;
- `tests/fixtures/ai/reference.py`, the tie-breaker when Swift and a fixture disagree.

**Sibling plan:** `2026-10-03-e1-tauri-local-models.md` (Windows/Linux). Nothing here touches `windows/`.

## Global Constraints

- **Platform:** macOS 15 floor (`MACOSX_DEPLOYMENT_TARGET 15.0`), Swift 6 with `-strict-concurrency=complete`, SwiftUI + AppKit. No third-party dependencies. Never edit `NotchBuddy.xcodeproj` by hand: change `project.yml`, run `xcodegen`, and commit the regenerated `project.pbxproj` (and `Resources/Info*.plist` when `info:` changes).
- **Core purity:** every file in `NotchBuddy/Sources/App/AI/Core/` has exactly one import, `import Foundation`. `scripts/test-ai-router.sh` fails the run otherwise.
- **Provider IDs** (exact): `anthropic`, `openai`, `google`, `ollama`, `lmstudio`, `llamacpp`, `jan`, `apple`, `custom`. `ChatProvider` raw values equal them. Existing raw values and the pill IDs `ai_anthropic`, `ai_google`, `ai_openai`, `ai_ollama`, `ai_lmstudio` never change; new providers get no pill.
- **Placements:** `local`, `network`, `cloud`. A `custom` server is `local` on `127.0.0.1`, `::1` or `localhost`, else `network`.
- **Error kinds:** `offline`, `unreachable`, `timeout`, `server`, `rate_limited`, `overloaded`, `auth`, `bad_request`, `billing`, `refusal`, `cancelled`, `interrupted`.
- **Router outcomes:** `ok`, `fallback`, `error`, `retry_countdown`, `empty_state`, `interrupted`, `cancelled`.
- **Timeouts:** probe 0.3 s; connect: local 5 s, cloud 10 s; first token: local 60 s, cloud 30 s.
- **Limits:** files over 25 MB (26,214,400 bytes) are rejected with reason `size`. The text budget is `floor(context × 7 / 4)` characters (50% of the context at 3.5 characters per token), computed in integers, never in floating point; an unknown local context counts as 4,096 tokens; cloud text is capped at 204,800 characters. "Characters" means Unicode scalars (`unicodeScalars.count`).
- **Lines end at `\n` only**, in the budget's line counting and in SSE line splitting. One trailing `\r` is dropped from an SSE line, so `\r\n` still works. A lone `\r`, U+2028, U+2029 and U+0085 never split a line. Swift's `String.split(separator: "\n")` (a `\r\n` is one `Character`) and `URLSession.AsyncBytes.lines` are not used for this: the stream is split by `SSELineSplitter` on the byte `0x0A`.
- **HTTP errors:** a billing marker (`insufficient_quota`, `credit_balance_exhausted`, `organization_usage_limit_exceeded`, `billing_error`, any code ending in `_spend_limit_exceeded`, "credit balance" in the message) or status 402 is `billing` before the status table applies. The `error` field of a body may be a dictionary, a string or a list (first element); an odd shape counts as no marker and never crashes. `Retry-After` counts only if it is ASCII digits and greater than 0, else nil.
- **Truncation notices** (exact): `I read the first N lines.`, `I read the first line.`, `I read the first part of this file.`
- **Cloud defaults:** Anthropic `claude-sonnet-5-5`; OpenAI `gpt-6.1-sol`; Google: the first listed model containing "flash", else the first.
- **OpenAI:** Responses API (`POST /v1/responses`), `store: false` on every request, the whole conversation resent each turn, never `previous_response_id`. Streams end on `response.completed` / `.incomplete` / `.failed`; there is no `[DONE]`. `response.failed` and `error` events, like Anthropic's `error` event, map their code or type with the one shared `HTTPErrorRules.streamErrorKind` (`stream_error_kind` in `reference.py`):
  - `rate_limit_exceeded`, `rate_limit_error` → `rate_limited`; `server_is_overloaded`, `slow_down`, `overloaded_error` → `overloaded`; `server_error`, `api_error`, `timeout_error`, `vector_store_timeout` → `server`;
  - the billing codes → `billing`; `invalid_prompt`, `image_content_policy_violation`, `content_policy_violation`, `content_filter` → `refusal`; `authentication_error`, `invalid_api_key`, `permission_error` → `auth`;
  - anything else, including `invalid_request_error`, `context_length_exceeded`, an unknown code, a missing code and an `error` that is not an object → `bad_request`, which never falls back to a local model. Only the known temporary kinds may.
- **OpenAI-compatible servers:** send `max_tokens` (the catalog's value for the server's placement: 4096 for local and network servers, as `LocalChat` does today), never `max_completion_tokens`, never `tool_choice`.
- **Empty and cut replies:**
  - A reply with no visible text is a failure, and an empty assistant turn never enters the history. When the cap was hit (`length`), the user sees: "The model ran out of room before answering. Try again, or pick a model without thinking mode."
  - A reply with text that hit the cap is kept, with the notice "The answer was cut off."
- **Web search:** both apps send the values in `providers.json` `webSearch`:
  - Anthropic `{"type": "web_search_20260209", "name": "web_search", "max_uses": 5}`, GA, so no beta header. The Mac moves up from `web_search_20250305`, and `search()` uses the same type with `max_uses` 3.
  - OpenAI `{"type": "web_search"}`.
- **Anthropic:** Messages API, streaming, PDFs as `document` blocks, `anthropic-version: 2023-06-01`.
- **Discovery:** 127.0.0.1 only (Ollama 11434 `/api/version`, LM Studio 1234 `/v1/models`, llama.cpp 8080 `/health`, Jan 1337 `/v1/models`), all in parallel. It runs the first time the island opens after launch, when the model picker or Settings → AI opens, when Auto needs a local model, and when nothing is known yet. Nothing is requested while the island stays hidden, and nothing runs on a timer: 0% CPU while hidden. Cloud model lists are only fetched from the picker and Settings.
- **Logs:** `AILog` writes to `~/Library/Logs/NotchMeow/nm.log` (via `appendAppLog`). It records event types, provider and model IDs, status codes, error codes and the provider's request ID. It never records prompts, file contents, keys or provider error messages.
  - **Tests never write the real log.** `appendAppLog` honours `NM_LOG_DIR`, every `scripts/test-*.sh` that builds log code sets it to a temp folder, test programs refuse to run without it (`T.requireTempLog()`), and `scripts/check-test-logs.sh` fails CI for a script that forgets. The app never sets it, so production behaviour is unchanged.
- **Debug-only override:** in `#if DEBUG` builds, `NM_AI_BASE_URL_OVERRIDE=http://127.0.0.1:PORT` points Anthropic, OpenAI and Google at the fake server. Release builds compile it out; `scripts/check-app-binary.sh` checks this.
- **FoundationModels:** only under `#if canImport(FoundationModels)` and `@available(macOS 26, *)`. It must stay weak-linked (`scripts/check-app-binary.sh`). It never uses Private Cloud Compute.
  - **CI needs the macOS 26 SDK** (Xcode 26 or later). On an older Xcode the provider would be compiled out without a word, so `scripts/check-sdk.sh` and `check-app-binary.sh … release` fail loudly instead. `build.yml` runs on `macos-latest`; if that image is older, pin `runs-on: macos-26`.
- **Shipping views:** never restyle them. New lines and buttons reuse the existing fonts, colours and components (`PrimaryButton`, `SecondaryButton`, `GroupBox`, the chip capsules, `#7B8089` 10.5 pt caption grey).
- **Secrets:**
  - Keys live only in the Keychain (`KeychainStore`). `custom-server-key` is a prefix: each added server's key is stored under `custom-server-key.<server id>`, one Keychain item per server, and any number of servers may be added. A server ID matches `^[a-z0-9-]{1,32}$`; the app generates `custom-` plus 24 hex digits (`CustomServer.newID()`).
  - Every type holding a key (the providers, `ProbeTarget`, `DiscoveredServer`, `ProviderFactory`) prints `<redacted>` in `description`, `debugDescription` and `dump()`.
  - `user:password@` is stripped from a server URL before it is stored.
- **Commits:** every task ends with a local `git commit` whose message ends with `Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>`. Never push.
- **Resolved here** (the spec left these open; details in each task):
  - **Feature routing.** File questions (`files`) when the message being sent carries a file or any earlier message in the current conversation did; otherwise Chat. It is derived from the conversation's messages (their files), never from a flag, so a follow-up stays on the route the person chose for files: with File questions on a local model and Chat on the cloud, the file's text never reaches the cloud on message 2. A file drop or an attached window starts a new conversation (`clearConversation`, the shipped fix), which resets the rule. Continue and Retry add no file, so they keep the route of the reply they follow. Prepared files are kept on their turn: read, OCR'd and rendered once at drop, never again.
  - **Retry.** Retry regenerates the last answer and never removes a user message it didn't add.
  - **First token.** "First token" means the first output event: text, a tool call, a refusal, or a search or reasoning step starting.
  - **Interruptions.** A stream cut before any text counts as a `server` failure (Auto retries locally); a cut after text keeps the partial reply as `interrupted`.
  - **Failed local retry.** When the local retry fails too, the cloud's own failure decides the result (countdown or error).
  - **Hairball.** A rejected drop plays the existing annoyed emote and sound and posts `.botReject`; the hairball animation hooks onto it in the cat sub-project.
  - **HTML.** HTML is converted with a tag strip, not `NSAttributedString`: its WebKit importer can load remote resources.
  - **HEIC.** HEIC photos are re-encoded as JPEG with ImageIO; no `image/heic` ever reaches Anthropic or OpenAI.
  - **First check.** Spec §2's "at launch" check runs when the island first opens, so nothing is requested while it stays hidden.
  - **Reply length.** One value per placement, from `providers.json` `maxOutputTokens` (`{"cloud": 16000, "network": 4096, "local": 4096}`), read with `AICatalog.maxOutputTokens(for:)`; no caller writes a number. Current Claude and GPT models spend reasoning tokens from the cloud cap, and 4,096 truncated replies, so cloud requests get 16,000; local and network servers keep 4,096. A catalog test compares the built-in copy with `providers.json` and pins cloud 16,000 and local 4,096, so editing the fixture or the catalog alone, or both together, fails a test until the pin is changed on purpose.

## Review Focus

1. **A stream cut before any text** (a hotel captive portal, the Mac sleeping just after the request, a server crashing after its headers). A person expects "had a problem" or a local answer, never an empty bubble marked "interrupted". Task 8 pins it with the fake server's `cut` mode, which stops before any text in both cloud formats.
2. **Stop pressed after part of the reply appeared.** The partial reply stays, without the "interrupted" mark and without an error note. Task 8 pins it with a scripted provider that streams text and then waits.
3. **A local model deleted or renamed since discovery** (the user ran `ollama rm`). The server answers 404, and the person expects "qwen3.5:2b isn't installed. Pick another model above the chat box." with Choose model, not a raw error. Task 5 (404 → `bad_request` with status 404) and Task 8 (the copy) pin it.
4. **A thinking model that spends the whole token cap inside `<think>`** (Qwen and DeepSeek-style models on Ollama, with the 4,096-token local cap). A person expects "The model ran out of room before answering. Try again, or pick a model without thinking mode." with Choose model, never an empty bubble or an empty turn in the history. A cut with text keeps it and adds "The answer was cut off." Task 8 pins both with a scripted provider.
5. **A password-protected PDF** (bank statements often are). The person expects a clear "I can't read this kind of file" and no half-read or rejected API call. Task 4 pins it by encrypting the generated text PDF with PDFKit.
6. **A follow-up question about a dropped file, with File questions on a local model and Chat on a cloud model.** The file's text is in the history after message 1, so a follow-up that took the Chat route would send it to the cloud, which the person ruled out for files. A person expects every message of that conversation to stay on the local model, and Retry and Continue too, until a new file or window starts a new conversation. Task 8 pins it: `Conversation.feature` is File questions when the current message or any earlier one carries a file, and a routing check shows the follow-up never reaches the cloud.
7. **A mid-stream error the app has never seen** (a policy refusal on `response.failed`, a new error code, an `error` that is a string or `null`). A person expects the app to say so and stop, never to retry silently on a local model with a prompt the cloud refused, and never to crash. Tasks 2 and 3 pin it: unknown codes and odd shapes are `bad_request`, and only the known temporary kinds may fall back.
8. **A reply or file containing U+2028, U+0085, a lone carriage return or CRLF line ends.** A person expects every character of the reply, and the same line count for a file, on every platform. Tasks 3, 4 and 5 pin it: lines end at `\n` only, through the byte splitter used by the real transport.

---

## File Structure

| Path | Responsibility | Task |
|---|---|---|
| `NotchBuddy/Sources/App/AI/Core/AICatalog.swift` | Provider IDs, placements, built-in copy of `providers.json`, model filters, timeouts, limits, reply caps per placement | 1 |
| `NotchBuddy/Sources/App/AI/Core/ModelProvider.swift` | `ModelProvider` protocol, `ChatRequest`, `ChatChunk`, `ModelInfo`, `AIError`, `AIErrorKind` | 1 |
| `NotchBuddy/Sources/App/AI/Core/HTTPErrors.swift` | HTTP status + body → error kind, Retry-After, the shared mid-stream error mapping, transport errors | 2 |
| `NotchBuddy/Sources/App/AI/Core/ModelRouter.swift` | Settings types and the pure router (`plan`, `afterFailure`, `route`) | 2 |
| `NotchBuddy/Sources/App/AI/Core/SSEParsers.swift` | SSE line splitting (LF only) and the three format parsers | 3 |
| `NotchBuddy/Sources/App/AI/Core/ReplyAccumulator.swift` | `<think>` filter and folding chunks into a reply | 3 |
| `NotchBuddy/Sources/App/AI/Core/ContextBudget.swift` | File text budget and chat-history trimming (the shared `history-cases.json` rule) | 4 |
| `NotchBuddy/Sources/App/AI/Core/Attachments.swift` | File classification, HTML tag strip, what each provider receives | 4 |
| `NotchBuddy/Sources/App/AI/Platform/AttachmentExtractor.swift` | PDFKit, docx/rtf import, page rendering, Vision OCR | 4 |
| `NotchBuddy/Sources/App/AI/Core/AILog.swift` | The content-free AI log; `RedactsSecrets` | 5 |
| `NotchBuddy/Sources/App/AI/Core/HTTPStream.swift` | URL normalising, Debug override, streaming transport with deadlines | 5 |
| `NotchBuddy/Sources/App/AI/Core/OpenAICompatibleProvider.swift` | Google, Ollama, LM Studio, llama.cpp, Jan, custom servers | 5 |
| `NotchBuddy/Sources/App/AI/Core/AnthropicProvider.swift` | Claude, streaming, web search, native PDF | 6 |
| `NotchBuddy/Sources/App/AI/Core/OpenAIProvider.swift` | OpenAI Responses, `store:false`, web search, files and images | 7 |
| `NotchBuddy/Sources/App/AI/Core/Conversation.swift` | The provider-independent chat, files per message, and the Chat / File questions route | 8 |
| `NotchBuddy/Sources/App/AI/Core/ChatRunner.swift` | One message: primary, at most one local retry, waking, interruptions | 8 |
| `NotchBuddy/Sources/App/AI/Core/AIMessages.swift` | Every user-facing AI string (spec §5 table), captions, drop-card line | 8 |
| `NotchBuddy/Sources/App/AI/Core/Discovery.swift` | Parallel localhost probes, identification rules, install hints | 9 |
| `NotchBuddy/Sources/App/AI/Platform/NetworkMonitor.swift` | `NWPathMonitor` online state | 9 |
| `NotchBuddy/Sources/App/AI/Platform/AppleOnDeviceProvider.swift` | Apple Foundation Models status and provider | 10 |
| `NotchBuddy/Sources/App/AI/Core/ProviderFactory.swift` | `CustomServer`, provider construction, pre-E1 settings migration | 11 |
| `NotchBuddy/Sources/App/AI/AIService.swift` | AppState ↔ core glue: discovery, routing input, targets, pre-warm | 11 |
| `NotchBuddy/Sources/App/AISettingsViews.swift` | Settings → AI rows: local server row, Add server sheet | 13 |
| `NotchBuddy/Sources/App/IslandTypes.swift` | `ChatProvider` gains `llamacpp`, `jan`, `apple`, `custom` | 11 |
| `NotchBuddy/Sources/App/AppState.swift` | Per-feature choices, Preferred cloud, servers, live AI state, `ChatMessage` fields | 11, 12, 13 |
| `NotchBuddy/Sources/App/ClaudeService.swift` | Chat through router + runner; Stop, Continue, Retry (regenerate), countdown; `search()` keeps its flow with the catalog web search | 11 |
| `NotchBuddy/Sources/App/FileDropView.swift` | Reads the dropped file for the AI; reject feedback | 11 |
| `NotchBuddy/Sources/App/IslandViewContent.swift` | Model chip and picker (11); caption, sources, notices, Stop, empty state, note action, drop card (12) | 11, 12 |
| `NotchBuddy/Sources/App/UploadCanvasView.swift` | Drop card line on the canvas | 12 |
| `NotchBuddy/Sources/App/SettingsView.swift` | "Chat" becomes "AI" with three boxes | 13 |
| `NotchBuddy/Sources/App/LocalChat.swift` | Thin facade over the core, kept for `ChatParsingTests` | 14 |
| `NotchBuddy/project.yml` | Weak-link note (10); `NSLocalNetworkUsageDescription` (13) | 10, 13 |
| `tests/AITestSupport.swift` | Shared `T.check` harness, fixture loading, `FakeServer`, `closedPort()` | 1 |
| `tests/AIRouterTests.swift`, `AIStreamTests.swift`, `AIBudgetTests.swift`, `AIAttachmentTests.swift`, `AIProviderTests.swift`, `AIRunnerTests.swift`, `AIDiscoveryTests.swift`, `AIPlatformTests.swift`, `AISettingsTests.swift` | One `@main` program per script | 1–11 |
| `scripts/test-ai-{router,stream,budget,attachments,providers,runner,discovery,platform,settings}.sh` | Build and run each test program | 1–11 |
| `scripts/check-app-binary.sh`, `scripts/check-sdk.sh` | Weak FoundationModels; no Debug override in Release; the SDK has FoundationModels (else the Apple provider is silently compiled out) | 10 |
| `scripts/check-test-logs.sh`, `NotchBuddy/Sources/App/AppLog.swift` | Test scripts keep out of the real `nm.log` (`NM_LOG_DIR`) | 1 |
| `.github/workflows/build.yml` | One step per script, binary check after the Release build | 1–11 |
| `docs/INTEGRATIONS.md` (French), `docs/SPEC.md`, `README.md`, `CHANGELOG.md` | What each provider receives, Settings → AI | 14 |

---

### Task 1: AI core types and provider catalog

**Files:**
- Create: `NotchBuddy/Sources/App/AI/Core/ModelProvider.swift`
- Create: `NotchBuddy/Sources/App/AI/Core/AICatalog.swift`
- Create: `tests/AITestSupport.swift`
- Create: `tests/AIRouterTests.swift` (catalog section; Task 2 adds router and HTTP sections)
- Create: `scripts/test-ai-router.sh`
- Create: `scripts/check-test-logs.sh`
- Modify: `NotchBuddy/Sources/App/AppLog.swift` (`NM_LOG_DIR`)
- Modify: `scripts/test-chat-parsing.sh` (`NM_LOG_DIR`)
- Modify: `.github/workflows/build.yml`

**Interfaces:**
- Consumes: `tests/fixtures/ai/providers.json` (E1-0 Task 1, including `maxOutputTokens`).
- Produces:
  - `enum AIProviderID: String, CaseIterable, Codable, Sendable` (9 cases, `isCloud`);
  - `enum AIPlacement { local, network, cloud }`;
  - `enum AIProviderAPI { anthropic, openaiResponses, openaiChat, apple }`;
  - `struct AIProviderInfo`;
  - `AICatalog.providers`, `.info(_:)`, `.cloudOrder`;
  - `AICatalog.WebSearch` (`anthropicType`, `anthropicLegacyType`, `anthropicLegacyModelPrefixes`, `anthropicName`, `anthropicMaxUses`, `openAIType`);
  - `AICatalog.anthropicWebSearchType(model:)`: the hosted search tool a Claude model gets (`web_search_20260209`, or `web_search_20250305` for `claude-haiku-4*` and `claude-3*`);
  - `AICatalog.Filters`, `.Timeouts` (seconds), `.Limits`, `.OutputTokens` (`cloud`, `network`, `local`: the reply caps of `providers.json` `maxOutputTokens`);
  - `AICatalog.maxOutputTokens(for placement: AIPlacement) -> Int`: the `maxTokens` of a request at that placement (cloud 16,000; network and local 4,096). Callers never write a number;
  - `AICatalog.placement(forHost:)`, `.filterModels(_:for:)`, `.defaultModel(for:available:)`.
- Produces: `ModelInfo {id, label?, contextTokens?, capabilities}`; `ChatRequest {model, system, messages, tools, responseFormat, maxTokens (defaults to the local cap), webSearch}` with nested `Role`, `Part` (`.text`, `.fileText(name:text:)`, `.image(mime:data:)`, `.pdf(name:data:)`), `Message`, `Tool`, `ResponseFormat`.
- Produces: `Citation {url, title}`, `ToolCallDelta`, `FinishReason {stop, length, toolCalls, refusal}`, `ChatChunk {text, toolCall, citation, refusal(_:replacesText:), finish, error, activity}`, `AIErrorKind` (12 cases, `isTemporary`), `AIError {kind, status, retryAfter, code, message, requestID}`.
- Produces: `protocol ModelProvider: Sendable { id; displayName; placement; listModels() async throws -> [ModelInfo]; stream(_:) -> AsyncThrowingStream<ChatChunk, Error>; prewarm(model:) async }`.
- Produces (tests): `T.section`, `T.check(_:_:_:)`, `T.checkTrue`, `T.finish()`, `T.fixture(_:)`, `T.text(_:)`, `T.fixtureURL(_:)`, `T.requireTempLog()`, `FakeServer(flags)` with `.base`, `.requests()` and `.stop()`, and `closedPort()`.
- Produces (logs): `appLogDirectory()`: `~/Library/Logs/NotchMeow`, or the folder in `NM_LOG_DIR`. Every test script sets `NM_LOG_DIR` to a temp folder, so no test run touches the real `nm.log`; `scripts/check-test-logs.sh` fails CI when a script forgets.

- [ ] **Step 1: Check that the shared contract is in place**

Run: `bash scripts/test-ai-contract.sh`
Expected: `All AI contract checks passed` and `Ran 13 tests … OK`. If the script is missing, stop: E1-0 has not landed.

- [ ] **Step 2: Write the shared test harness `tests/AITestSupport.swift`**

```swift
import Foundation

// Shared helpers for the AI test programs (scripts/test-ai-*.sh compile this file into each one).
// Run from the repository root: fixture paths are relative to it.

@MainActor
enum T {
    static var failures = 0

    /// Every section starts here, so a test program run by hand (without `NM_LOG_DIR`) stops before it logs.
    static func section(_ name: String) {
        requireTempLog()
        print(name)
    }

    /// Tests never write to the user's real log: `scripts/test-*.sh` set `NM_LOG_DIR` to a temp folder
    /// and `appendAppLog` honours it.
    static func requireTempLog() {
        guard let dir = ProcessInfo.processInfo.environment["NM_LOG_DIR"], !dir.isEmpty, !dir.contains("/Library/Logs") else {
            print("NM_LOG_DIR is not set to a temp folder: run this through its scripts/test-*.sh")
            exit(2)
        }
    }

    static func check<V: Equatable>(_ label: String, _ got: V, _ expected: V) {
        if got == expected {
            print("  ✓ \(label)")
        } else {
            print("  ✗ \(label)")
            print("    got:      \(got)")
            print("    expected: \(expected)")
            failures += 1
        }
    }

    static func checkTrue(_ label: String, _ value: Bool) {
        if value { print("  ✓ \(label)") } else { print("  ✗ \(label)"); failures += 1 }
    }

    static func finish() -> Never {
        if failures == 0 {
            print("\nAll tests passed.")
            exit(0)
        }
        print("\n\(failures) test(s) failed.")
        exit(1)
    }

    static func fixtureURL(_ relative: String) -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("tests/fixtures/ai")
            .appendingPathComponent(relative)
    }

    /// Parsed JSON fixture (dictionary at the top level).
    static func fixture(_ relative: String) -> [String: Any] {
        let data = try! Data(contentsOf: fixtureURL(relative))
        return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    static func text(_ relative: String) -> String {
        try! String(contentsOf: fixtureURL(relative), encoding: .utf8)
    }
}

/// `tests/fake_local_llm.py` on a free port, with its request log in a temp file.
final class FakeServer: @unchecked Sendable {
    let base: String
    let logURL: URL
    private let process: Process
    private let dir: URL

    init(_ flags: [String] = []) {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("nm-fake-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let portFile = dir.appendingPathComponent("port")
        logURL = dir.appendingPathComponent("log.jsonl")
        process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "tests/fake_local_llm.py", portFile.path, "--log", logURL.path] + flags
        try! process.run()
        var port = ""
        for _ in 0..<300 {
            if let s = try? String(contentsOf: portFile, encoding: .utf8), !s.isEmpty { port = s; break }
            usleep(10_000)
        }
        precondition(!port.isEmpty, "fake server did not start")
        base = "http://127.0.0.1:\(port.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    /// One dictionary per request: `method`, `path`, `origin`, `body`.
    func requests() -> [[String: Any]] {
        guard let s = try? String(contentsOf: logURL, encoding: .utf8) else { return [] }
        return s.split(separator: "\n").compactMap {
            try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
        }
    }

    func stop() {
        process.terminate()
        process.waitUntilExit()
        try? FileManager.default.removeItem(at: dir)
    }
}

/// A local TCP port with nothing listening on it (connection refused at once).
func closedPort() -> Int {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_addr.s_addr = inet_addr("127.0.0.1")
    addr.sin_port = 0
    var len = socklen_t(MemoryLayout<sockaddr_in>.size)
    withUnsafeMutablePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            _ = bind(fd, $0, len)
            _ = getsockname(fd, $0, &len)
        }
    }
    let port = Int(UInt16(bigEndian: addr.sin_port))
    close(fd)
    return port
}
```

- [ ] **Step 3: Write the failing catalog test `tests/AIRouterTests.swift`**

```swift
import Foundation

@main
@MainActor
enum AIRouterTests {
    static func main() {
        catalogMatchesProvidersJSON()
        logsStayInTheTestFolder()
        T.finish()
    }

    // MARK: - providers.json

    static func catalogMatchesProvidersJSON() {
        T.section("providers.json ↔ AICatalog")
        let json = T.fixture("providers.json")
        let rows = json["providers"] as! [[String: Any]]
        T.check("provider ids", rows.map { $0["id"] as! String }, AICatalog.providers.map(\.id.rawValue))
        T.check("enum covers every id", AIProviderID.allCases.map(\.rawValue), rows.map { $0["id"] as! String })
        for row in rows {
            let id = AIProviderID(rawValue: row["id"] as! String)!
            let p = AICatalog.info(id)
            T.check("\(id.rawValue) name", p.name, row["name"] as! String)
            T.check("\(id.rawValue) placement", p.placement, row["placement"] as! String)
            T.check("\(id.rawValue) api", p.api.rawValue, row["api"] as! String)
            T.check("\(id.rawValue) baseURL", p.baseURL, row["baseURL"] as? String)
            T.check("\(id.rawValue) chatPath", p.chatPath, row["chatPath"] as? String)
            T.check("\(id.rawValue) modelsPath", p.modelsPath, row["modelsPath"] as? String)
            T.check("\(id.rawValue) port", p.port, row["port"] as? Int)
            T.check("\(id.rawValue) probePath", p.probePath, row["probePath"] as? String)
            T.check("\(id.rawValue) keychainKey", p.keychainKey, row["keychainKey"] as? String)
            T.check("\(id.rawValue) defaultModel", p.defaultModel, row["defaultModel"] as? String)
        }
        T.check("cloud order", AICatalog.cloudOrder.map(\.rawValue), json["cloudOrder"] as! [String])
        let web = json["webSearch"] as? [String: [String: Any]] ?? [:]
        let claude = web["anthropic"] ?? [:]
        T.check("anthropic web search type", AICatalog.WebSearch.anthropicType, claude["type"] as? String)
        T.check("anthropic web search name", AICatalog.WebSearch.anthropicName, claude["name"] as? String)
        T.check("anthropic web search max_uses", AICatalog.WebSearch.anthropicMaxUses, claude["max_uses"] as? Int)
        T.check("anthropic legacy web search type", AICatalog.WebSearch.anthropicLegacyType, claude["legacyType"] as? String)
        T.check("anthropic legacy model prefixes", AICatalog.WebSearch.anthropicLegacyModelPrefixes,
                claude["legacyModelPrefixes"] as? [String] ?? [])
        T.check("openai web search type", AICatalog.WebSearch.openAIType, web["openai"]?["type"] as? String)

        let filters = json["modelFilters"] as! [String: [String: [String]]]
        T.check("local exclude", AICatalog.Filters.localExclude, filters["local"]!["exclude"]!)
        T.check("google exclude", AICatalog.Filters.googleExclude, filters["google"]!["exclude"]!)
        T.check("openai include", AICatalog.Filters.openAIIncludePrefixes, filters["openai"]!["includePrefixes"]!)
        T.check("openai exclude", AICatalog.Filters.openAIExclude, filters["openai"]!["exclude"]!)

        let ms = json["timeoutsMs"] as! [String: Int]
        T.check("probe timeout", Int(AICatalog.Timeouts.probe * 1000), ms["probe"]!)
        T.check("connect local", Int(AICatalog.Timeouts.connectLocal * 1000), ms["connectLocal"]!)
        T.check("connect cloud", Int(AICatalog.Timeouts.connectCloud * 1000), ms["connectCloud"]!)
        T.check("first token local", Int(AICatalog.Timeouts.firstTokenLocal * 1000), ms["firstTokenLocal"]!)
        T.check("first token cloud", Int(AICatalog.Timeouts.firstTokenCloud * 1000), ms["firstTokenCloud"]!)

        let limits = json["limits"] as! [String: Any]
        T.check("max file bytes", AICatalog.Limits.maxFileBytes, limits["maxFileBytes"] as! Int)
        T.check("cloud text cap", AICatalog.Limits.cloudTextCapChars, limits["cloudTextCapChars"] as! Int)
        T.check("budget fraction", AICatalog.Limits.budgetFractionOfContext, limits["budgetFractionOfContext"] as! Double)
        T.check("chars per token", AICatalog.Limits.charsPerToken, limits["charsPerToken"] as! Double)
        T.check("default local context", AICatalog.Limits.defaultLocalContextTokens, limits["defaultLocalContextTokens"] as! Int)

        T.section("Reply length")
        let caps = json["maxOutputTokens"] as! [String: Int]
        T.check("reply cap placements", Set(caps.keys), Set(["cloud", "network", "local"]))
        T.check("cloud reply cap", AICatalog.maxOutputTokens(for: .cloud), caps["cloud"]!)
        T.check("network reply cap", AICatalog.maxOutputTokens(for: .network), caps["network"]!)
        T.check("local reply cap", AICatalog.maxOutputTokens(for: .local), caps["local"]!)
        // Pinned on purpose: a cap changed in the fixture and the catalog together still stops here, so it is a decision.
        T.check("pinned reply caps (cloud 16,000, local 4,096)",
                [AICatalog.maxOutputTokens(for: .cloud), AICatalog.maxOutputTokens(for: .local)], [16_000, 4096])

        T.section("AICatalog helpers")
        T.check("localhost is local", AICatalog.placement(forHost: "localhost"), .local)
        T.check("::1 is local", AICatalog.placement(forHost: "[::1]"), .local)
        T.check("LAN host is network", AICatalog.placement(forHost: "studio-pc.local"), .network)
        T.check("local filter drops embeddings",
                AICatalog.filterModels(["llama3.2", "nomic-embed-text", "bge-m3"], for: .ollama), ["llama3.2"])
        T.check("google strips models/ and filters",
                AICatalog.filterModels(["models/gemini-3-flash", "models/text-embedding-005"], for: .google),
                ["gemini-3-flash"])
        T.check("openai keeps chat families only",
                AICatalog.filterModels(["gpt-6.1-sol", "whisper-1", "o5-mini", "gpt-6-search-preview", "dall-e-3"], for: .openai),
                ["gpt-6.1-sol", "o5-mini"])
        T.check("google default prefers flash",
                AICatalog.defaultModel(for: .google, available: ["gemini-3-pro", "gemini-3-flash"]), "gemini-3-flash")
        T.check("anthropic default is fixed",
                AICatalog.defaultModel(for: .anthropic, available: []), "claude-sonnet-5-5")

        T.section("Anthropic web search tool per model")
        T.check("Sonnet 5.5 gets the current tool", AICatalog.anthropicWebSearchType(model: "claude-sonnet-5-5"),
                "web_search_20260209")
        T.check("Haiku 4.5 gets the legacy tool", AICatalog.anthropicWebSearchType(model: "claude-haiku-4-5-20251001"),
                "web_search_20250305")
        T.check("Claude 3 models get the legacy tool", AICatalog.anthropicWebSearchType(model: "claude-3-5-sonnet-latest"),
                "web_search_20250305")
        T.check("any other model gets the current tool", AICatalog.anthropicWebSearchType(model: "claude-opus-5-5"),
                "web_search_20260209")
    }

    // MARK: - Logs

    /// The AI log goes through `appendAppLog`; with `NM_LOG_DIR` set it must land in the temp folder.
    static func logsStayInTheTestFolder() {
        T.section("Test logs")
        let dir = URL(fileURLWithPath: ProcessInfo.processInfo.environment["NM_LOG_DIR"]!, isDirectory: true)
        T.check("appLogDirectory follows NM_LOG_DIR", appLogDirectory().path, dir.path)
        appendAppLog("nm.log", "probe line from AIRouterTests")
        let written = (try? String(contentsOf: dir.appendingPathComponent("nm.log"), encoding: .utf8)) ?? ""
        T.checkTrue("a log line lands in the temp folder", written.contains("probe line from AIRouterTests"))
    }
}
```

- [ ] **Step 4: Write `scripts/test-ai-router.sh`**

```bash
#!/usr/bin/env bash
# AI core: provider catalog vs providers.json, router-cases.json, http-errors.json.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-ai-router.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs

# The core must stay Foundation-only so these swiftc tests can build it.
bad=$(grep -h '^import ' NotchBuddy/Sources/App/AI/Core/*.swift | sort -u | grep -v '^import Foundation$' || true)
if [ -n "$bad" ]; then echo "AI/Core imports more than Foundation: $bad" >&2; exit 1; fi

swiftc -swift-version 6 \
    NotchBuddy/Sources/App/AI/Core/*.swift \
    NotchBuddy/Sources/App/AppLog.swift \
    tests/AITestSupport.swift tests/AIRouterTests.swift \
    -o "$TEST_DIR/ai-router-tests"
"$TEST_DIR/ai-router-tests"
```

Run: `chmod +x scripts/test-ai-router.sh && bash scripts/test-ai-router.sh`
Expected: FAIL. `AI/Core/` doesn't exist yet, so `swiftc` reports `error: error opening input file 'NotchBuddy/Sources/App/AI/Core/*.swift' (No such file or directory)`.

- [ ] **Step 5: Keep test runs out of the real log**

`AILog` writes through `appendAppLog`, so any test that logs would append to `~/Library/Logs/NotchMeow/nm.log`. From now on every test script sets `NM_LOG_DIR` to a temp folder and `appendAppLog` honours it. The app never sets it, so production behaviour is unchanged.

In `NotchBuddy/Sources/App/AppLog.swift`, replace:

```swift
/// Appends one timestamped line to `~/Library/Logs/NotchMeow/<fileName>`.
```

with:

```swift
/// Where the logs go: `~/Library/Logs/NotchMeow`, or the folder in `NM_LOG_DIR`. Only the test
/// scripts set it, so that no test run ever appends to the user's real log.
func appLogDirectory() -> URL {
    if let dir = ProcessInfo.processInfo.environment["NM_LOG_DIR"], !dir.isEmpty {
        return URL(fileURLWithPath: dir, isDirectory: true)
    }
    return FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/NotchMeow")
}

/// Appends one timestamped line to `<appLogDirectory()>/<fileName>`.
```

and replace:

```swift
    let logsDir = fm.urls(for: .libraryDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Logs/NotchMeow")
```

with:

```swift
    let logsDir = appLogDirectory()
```

The existing `scripts/test-chat-parsing.sh` will start logging in Task 14, so give it the same line now. After its `TEST_DIR=` line, add:

```bash
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs
```

Write `scripts/check-test-logs.sh`, which fails when a test script builds code that can write the log but doesn't set `NM_LOG_DIR`:

```bash
#!/usr/bin/env bash
# Every test script that builds code which can write the app log (AppLog.swift, LocalChat.swift or
# AI/Core) must set NM_LOG_DIR, so no test run appends to ~/Library/Logs/NotchMeow/nm.log.
set -euo pipefail
cd "$(dirname "$0")/.."
status=0
for script in scripts/test-*.sh; do
    if grep -qE 'AppLog\.swift|LocalChat\.swift|AI/Core/' "$script" && ! grep -q 'NM_LOG_DIR' "$script"; then
        echo "✗ $script builds the app log code but doesn't set NM_LOG_DIR" >&2
        status=1
    fi
done
[ "$status" = 0 ] && echo "✓ every log-writing test script sets NM_LOG_DIR"
exit "$status"
```

Run: `chmod +x scripts/check-test-logs.sh && bash scripts/check-test-logs.sh`
Expected: `✓ every log-writing test script sets NM_LOG_DIR`.

Then delete the `export NM_LOG_DIR` line from `scripts/test-ai-router.sh` and run it again.
Expected: `✗ scripts/test-ai-router.sh builds the app log code but doesn't set NM_LOG_DIR`, exit 1. Put the line back.

- [ ] **Step 6: Write `NotchBuddy/Sources/App/AI/Core/ModelProvider.swift`**

```swift
import Foundation

// MARK: - Models

enum AICapability: String, Codable, Sendable, Hashable {
    case tools, vision, json
}

struct ModelInfo: Sendable, Equatable, Codable {
    let id: String
    /// Human name when the provider has one (Anthropic's `display_name`), else nil.
    var label: String? = nil
    var contextTokens: Int? = nil
    var capabilities: Set<AICapability> = []
}

// MARK: - Request

struct ChatRequest: Sendable, Equatable {
    enum Role: String, Sendable, Codable { case user, assistant }

    enum Part: Sendable, Equatable {
        case text(String)
        /// Text taken out of a file (already cut to the model's budget).
        case fileText(name: String, text: String)
        case image(mime: String, data: Data)
        /// A PDF sent as-is (Anthropic `document`, OpenAI `input_file`).
        case pdf(name: String, data: Data)
    }

    struct Message: Sendable, Equatable {
        var role: Role
        var parts: [Part]
    }

    /// A function the model may call. Unused in E; the cats (F) will use it.
    struct Tool: Sendable, Equatable {
        let name: String
        let description: String
        /// JSON Schema object, serialised.
        let parametersJSON: Data
    }

    /// Structured output. Unused in E; F will use it.
    struct ResponseFormat: Sendable, Equatable {
        let name: String
        /// JSON Schema object, serialised.
        let schemaJSON: Data
    }

    var model: String
    var system: String
    var messages: [Message]
    var tools: [Tool] = []
    var responseFormat: ResponseFormat? = nil
    /// Reply length cap. The chat sets it from `AICatalog.maxOutputTokens(for:)`; the default is the local cap.
    var maxTokens: Int = AICatalog.OutputTokens.local
    /// Lets Anthropic and OpenAI use their hosted web search.
    var webSearch: Bool = false
}

// MARK: - Stream

struct Citation: Sendable, Equatable, Hashable, Codable {
    let url: String
    let title: String
}

/// A piece of a tool call. `index` orders calls; `replacesArguments` overwrites instead of appending.
struct ToolCallDelta: Sendable, Equatable {
    let index: Int
    var id: String? = nil
    var name: String? = nil
    var arguments: String = ""
    var replacesArguments: Bool = false
}

enum FinishReason: String, Sendable, Equatable {
    case stop, length, refusal
    case toolCalls = "tool_calls"
}

enum ChatChunk: Sendable, Equatable {
    case text(String)
    case toolCall(ToolCallDelta)
    case citation(Citation)
    /// `replacesText`: the text streamed so far *was* the refusal (Anthropic).
    case refusal(String, replacesText: Bool)
    case finish(FinishReason)
    case error(AIErrorKind)
    /// The model is working (search started, reasoning started) but has no output yet.
    /// Counts as the first token for timeouts; carries nothing to show.
    case activity
}

// MARK: - Errors

/// Error kinds shared with the Windows/Linux app (E1-0 Global Constraints).
enum AIErrorKind: String, Sendable, Codable, CaseIterable, Equatable {
    case offline, unreachable, timeout, server
    case rateLimited = "rate_limited"
    case overloaded, auth
    case badRequest = "bad_request"
    case billing, refusal, cancelled, interrupted

    /// Auto may retry these once on a local model.
    var isTemporary: Bool {
        switch self {
        case .offline, .unreachable, .timeout, .server, .rateLimited, .overloaded: true
        default: false
        }
    }
}

struct AIError: Error, Sendable, Equatable {
    var kind: AIErrorKind
    var status: Int? = nil
    var retryAfter: Int? = nil
    /// Provider error code or type, e.g. `insufficient_quota`. Safe to log (short, no content).
    var code: String? = nil
    /// Provider message. Shown to the user for `bad_request`; never logged.
    var message: String? = nil
    /// `x-request-id` / `request-id`, logged for support.
    var requestID: String? = nil
}

// MARK: - Provider

protocol ModelProvider: Sendable {
    var id: AIProviderID { get }
    var displayName: String { get }
    var placement: AIPlacement { get }
    func listModels() async throws -> [ModelInfo]
    func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error>
    /// Loads the model ahead of the first message. No-op for providers that don't need it.
    func prewarm(model: String) async
}

extension ModelProvider {
    func prewarm(model: String) async {}
}
```

- [ ] **Step 7: Write `NotchBuddy/Sources/App/AI/Core/AICatalog.swift`**

```swift
import Foundation

// MARK: - Provider IDs and placements (tests/fixtures/ai/providers.json)

/// Provider IDs shared with the Windows/Linux app. Never rename: they are stored in
/// UserDefaults and match `tests/fixtures/ai/providers.json`.
enum AIProviderID: String, CaseIterable, Codable, Sendable {
    case anthropic, openai, google, ollama, lmstudio, llamacpp, jan, apple, custom

    var isCloud: Bool { self == .anthropic || self == .openai || self == .google }
}

/// Where an answer was computed. Drives the reply caption.
enum AIPlacement: String, Codable, Sendable {
    case local, network, cloud
}

/// The wire format a provider speaks.
enum AIProviderAPI: String, Sendable {
    case anthropic
    case openaiResponses = "openai-responses"
    case openaiChat = "openai-chat"
    case apple
}

/// One row of the provider catalog.
struct AIProviderInfo: Sendable {
    let id: AIProviderID
    let name: String
    /// "local", "cloud", or "computed" (a custom server: local on localhost, network otherwise).
    let placement: String
    let api: AIProviderAPI
    var baseURL: String? = nil
    var chatPath: String? = nil
    var modelsPath: String? = nil
    var port: Int? = nil
    var probePath: String? = nil
    var keychainKey: String? = nil
    var defaultModel: String? = nil
}

// MARK: - Catalog

/// Built-in copy of `tests/fixtures/ai/providers.json`. `scripts/test-ai-router.sh`
/// fails if the two drift apart.
enum AICatalog {
    static let providers: [AIProviderInfo] = [
        .init(id: .anthropic, name: "Anthropic", placement: "cloud", api: .anthropic,
              baseURL: "https://api.anthropic.com", chatPath: "/v1/messages", modelsPath: "/v1/models",
              keychainKey: "anthropic-api-key", defaultModel: "claude-sonnet-5-5"),
        .init(id: .openai, name: "OpenAI", placement: "cloud", api: .openaiResponses,
              baseURL: "https://api.openai.com", chatPath: "/v1/responses", modelsPath: "/v1/models",
              keychainKey: "openai-api-key", defaultModel: "gpt-6.1-sol"),
        .init(id: .google, name: "Google", placement: "cloud", api: .openaiChat,
              baseURL: "https://generativelanguage.googleapis.com/v1beta/openai", chatPath: "/chat/completions",
              modelsPath: "/models", keychainKey: "google-api-key", defaultModel: nil),
        .init(id: .ollama, name: "Ollama", placement: "local", api: .openaiChat,
              baseURL: "http://127.0.0.1:11434", chatPath: "/v1/chat/completions", modelsPath: "/v1/models",
              port: 11434, probePath: "/api/version"),
        .init(id: .lmstudio, name: "LM Studio", placement: "local", api: .openaiChat,
              baseURL: "http://127.0.0.1:1234", chatPath: "/v1/chat/completions", modelsPath: "/v1/models",
              port: 1234, probePath: "/v1/models"),
        .init(id: .llamacpp, name: "llama.cpp", placement: "local", api: .openaiChat,
              baseURL: "http://127.0.0.1:8080", chatPath: "/v1/chat/completions", modelsPath: "/v1/models",
              port: 8080, probePath: "/health"),
        .init(id: .jan, name: "Jan", placement: "local", api: .openaiChat,
              baseURL: "http://127.0.0.1:1337", chatPath: "/v1/chat/completions", modelsPath: "/v1/models",
              port: 1337, probePath: "/v1/models"),
        .init(id: .apple, name: "Apple on-device", placement: "local", api: .apple, defaultModel: "system"),
        .init(id: .custom, name: "Local server", placement: "computed", api: .openaiChat,
              chatPath: "/v1/chat/completions", modelsPath: "/v1/models", keychainKey: "custom-server-key"),
    ]

    static func info(_ id: AIProviderID) -> AIProviderInfo {
        providers.first { $0.id == id }!
    }

    /// Auto's cloud order before the Preferred cloud moves to the front.
    static let cloudOrder: [AIProviderID] = [.anthropic, .openai, .google]

    /// Hosted web-search tools (providers.json `webSearch`), the same on both apps.
    enum WebSearch {
        static let anthropicType = "web_search_20260209"
        /// Older Claude models (IDs starting with a legacy prefix) can't use `anthropicType`.
        static let anthropicLegacyType = "web_search_20250305"
        static let anthropicLegacyModelPrefixes = ["claude-haiku-4", "claude-3"]
        static let anthropicName = "web_search"
        static let anthropicMaxUses = 5
        static let openAIType = "web_search"
    }

    /// The hosted web-search tool type for a Claude model (providers.json `webSearch.anthropic`).
    static func anthropicWebSearchType(model: String) -> String {
        WebSearch.anthropicLegacyModelPrefixes.contains { model.hasPrefix($0) }
            ? WebSearch.anthropicLegacyType : WebSearch.anthropicType
    }

    enum Filters {
        static let localExclude = ["embed", "bge-", "all-minilm", "clip", "rerank"]
        static let googleExclude = ["embed", "imagen", "veo", "aqa", "tts", "audio", "live"]
        static let openAIIncludePrefixes = ["gpt-", "o1", "o3", "o4", "o5"]
        static let openAIExclude = ["embed", "tts", "whisper", "dall-e", "audio", "realtime", "moderat", "codex",
                                    "computer-use", "transcribe", "image", "sora", "babbage", "davinci",
                                    "instruct", "search", "live"]
    }

    /// Seconds (providers.json stores milliseconds).
    enum Timeouts {
        static let probe: TimeInterval = 0.3
        static let connectLocal: TimeInterval = 5
        static let connectCloud: TimeInterval = 10
        static let firstTokenLocal: TimeInterval = 60
        static let firstTokenCloud: TimeInterval = 30
    }

    enum Limits {
        static let maxFileBytes = 26_214_400
        static let cloudTextCapChars = 204_800
        static let budgetFractionOfContext = 0.5
        static let charsPerToken = 3.5
        static let defaultLocalContextTokens = 4096
    }

    /// Reply length per placement (providers.json `maxOutputTokens`). Cloud models spend reasoning tokens
    /// from the same cap, so they get more room than local and network servers.
    enum OutputTokens {
        static let cloud = 16_000
        static let network = 4096
        static let local = 4096
    }

    /// The `maxTokens` of a request to a provider at this placement. No caller writes a number.
    static func maxOutputTokens(for placement: AIPlacement) -> Int {
        switch placement {
        case .cloud: OutputTokens.cloud
        case .network: OutputTokens.network
        case .local: OutputTokens.local
        }
    }

    /// A custom server is `local` on 127.0.0.1, ::1 or localhost, and `network` otherwise.
    static func placement(forHost host: String?) -> AIPlacement {
        let h = (host ?? "").lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return ["127.0.0.1", "::1", "localhost"].contains(h) ? .local : .network
    }

    /// Chat models only, in the order given. Google IDs lose their `models/` prefix.
    static func filterModels(_ ids: [String], for provider: AIProviderID) -> [String] {
        switch provider {
        case .google:
            return ids.map { $0.hasPrefix("models/") ? String($0.dropFirst(7)) : $0 }
                .filter { id in !Filters.googleExclude.contains { id.lowercased().contains($0) } }
        case .openai:
            return ids.filter { id in
                let l = id.lowercased()
                return Filters.openAIIncludePrefixes.contains { l.hasPrefix($0) }
                    && !Filters.openAIExclude.contains { l.contains($0) }
            }
        case .anthropic, .apple:
            return ids
        case .ollama, .lmstudio, .llamacpp, .jan, .custom:
            return ids.filter { id in !Filters.localExclude.contains { id.lowercased().contains($0) } }
        }
    }

    /// The model Auto uses for a provider when none is remembered (`docs/AI-PROVIDERS.md`).
    /// Google has no fixed default: the first listed ID containing "flash", else the first.
    static func defaultModel(for provider: AIProviderID, available: [String]) -> String? {
        if let fixed = info(provider).defaultModel { return fixed }
        if provider == .google { return available.first { $0.contains("flash") } ?? available.first }
        return available.first
    }
}
```

- [ ] **Step 8: Run the catalog test**

Run: `bash scripts/test-ai-router.sh`
Expected: every line under `providers.json ↔ AICatalog`, `Reply length`, `AICatalog helpers`, `Anthropic web search tool per model` and `Test logs` is `✓`, then `All tests passed.`

- [ ] **Step 9: Prove the test catches drift**

Temporarily change `port: 1337` to `port: 1338` in `AICatalog.swift`, then run `bash scripts/test-ai-router.sh`.
Expected: `✗ jan port`, exit 1. Restore `1337` and re-run: `All tests passed.`

Then change `static let cloud = 16_000` to `8_000` in `AICatalog.OutputTokens` and run it again.
Expected: `✗ cloud reply cap` and `✗ pinned reply caps (cloud 16,000, local 4,096)`, exit 1. Restore `16_000`: `All tests passed.`

- [ ] **Step 10: Add the CI step**

In `.github/workflows/build.yml`, insert this step immediately before `- name: Test plan gauge` (after any `AI …` steps added by earlier tasks), at the same indentation:

```yaml
      - name: AI router, catalog and HTTP errors
        run: bash scripts/test-ai-router.sh
```

Then insert this step before `- name: Test screen geometry`, the first test step:

```yaml
      - name: Test scripts keep out of the real log
        run: bash scripts/check-test-logs.sh
```

- [ ] **Step 11: Build the app**

Run: `cd NotchBuddy && xcodegen && xcodebuild -project NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug build 2>&1 | grep -E "error:|BUILD" ; cd ..`
Expected: `** BUILD SUCCEEDED **` and no `error:` line. New files under `Sources/` are picked up by `xcodegen`.

- [ ] **Step 12: Commit**

```bash
git add NotchBuddy/Sources/App/AI/Core/ModelProvider.swift \
    NotchBuddy/Sources/App/AI/Core/AICatalog.swift \
    NotchBuddy/Sources/App/AppLog.swift \
    tests/AITestSupport.swift \
    tests/AIRouterTests.swift \
    scripts/test-ai-router.sh \
    scripts/check-test-logs.sh \
    scripts/test-chat-parsing.sh \
    .github/workflows/build.yml \
    NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -m "feat(ai): add the AI core types and the provider catalog

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---
### Task 2: Routing and HTTP error rules

**Files:**
- Create: `NotchBuddy/Sources/App/AI/Core/HTTPErrors.swift`
- Create: `NotchBuddy/Sources/App/AI/Core/ModelRouter.swift`
- Modify: `tests/AIRouterTests.swift`

**Interfaces:**
- Consumes: `AIProviderID`, `AIPlacement`, `AIErrorKind`, `AIError`, `AICatalog` (Task 1); `router-cases.json`, `http-errors.json` (E1-0 Task 2).
- Produces:
  - `HTTPErrorRules.billingCodes: Set<String>` and `HTTPErrorRules.isBilling(_ code: String?) -> Bool` (the set, or any code ending in `_spend_limit_exceeded`): the one billing rule, shared by HTTP and stream errors;
  - `HTTPErrorRules.classify(status:body:headers:) -> (kind: AIErrorKind, retryAfter: Int?)`, which never crashes on an odd body (a string, a list, `null`, bad JSON);
  - `HTTPErrorRules.streamErrorKind(_ codeOrType: String?) -> AIErrorKind`: the one mid-stream mapping (OpenAI `error.code`, Anthropic `error.type`); unknown or missing is `.badRequest`;
  - `HTTPErrorRules.error(status:body:headers:) -> AIError` (with `code`, `message`, `requestID`);
  - `HTTPErrorRules.isSpendLimit(_:) -> Bool`, `HTTPErrorRules.transportKind(_ error: Error) -> AIErrorKind`, `HTTPErrorRules.header(_:in:) -> String?`.
- Produces: `ModelRef {provider, model, serverID?}`, `FeatureSetting {auto, explicit(ModelRef)}`, `AIFeature {chat, files}`, `LocalCandidate {provider, model, placement, serverID?}`, `RouteInput`, `RouteOutcome`, `RouteDecision`, `RoutePlan {primary, model?, serverID?, placement, fallback?, isAuto}`.
- Produces: `ModelRouter.apple`, `.cloudChoice(_:)`, `.localChoice(_:) -> LocalCandidate?`, `.placement(of:in:)`, `.plan(_:) -> RoutePlan?`, `.afterFailure(_:failure:) -> RouteDecision`, `.route(_:) -> RouteDecision` (the contract function).

- [ ] **Step 1: Add the failing router and HTTP tests**

In `tests/AIRouterTests.swift`, make `main()` call the new sections:

```swift
    static func main() {
        catalogMatchesProvidersJSON()
        logsStayInTheTestFolder()
        contractNames()
        routerCases()
        httpErrorCases()
        T.finish()
    }
```

Then add these members just before the enum's final closing brace:

```swift
    // MARK: - Names shared with the Windows/Linux app

    /// The exact error kinds and router outcomes of E1-0's Global Constraints.
    static func contractNames() {
        T.section("Contract names")
        T.check("error kinds", AIErrorKind.allCases.map(\.rawValue),
                ["offline", "unreachable", "timeout", "server", "rate_limited", "overloaded", "auth", "bad_request",
                 "billing", "refusal", "cancelled", "interrupted"])
        T.check("router outcomes",
                [RouteOutcome.ok, .fallback, .error, .retryCountdown, .emptyState, .interrupted, .cancelled].map(\.rawValue),
                ["ok", "fallback", "error", "retry_countdown", "empty_state", "interrupted", "cancelled"])
    }

    // MARK: - router-cases.json

    static func candidate(_ d: [String: Any]) -> LocalCandidate {
        LocalCandidate(provider: AIProviderID(rawValue: d["provider"] as! String)!,
                       model: d["model"] as! String,
                       placement: AIPlacement(rawValue: d["placement"] as! String)!)
    }

    static func routeInput(_ d: [String: Any]) -> RouteInput {
        var input = RouteInput()
        if let s = d["setting"] as? [String: Any] {
            input.setting = .explicit(ModelRef(provider: AIProviderID(rawValue: s["provider"] as! String)!,
                                               model: s["model"] as! String))
        }
        input.preferredCloud = AIProviderID(rawValue: d["preferredCloud"] as! String)!
        input.keys = Set((d["keys"] as! [String]).map { AIProviderID(rawValue: $0)! })
        input.online = d["online"] as! Bool
        input.localReady = (d["localReady"] as! [[String: Any]]).map(candidate)
        if let last = d["lastUsedLocal"] as? [String: Any] {
            input.lastUsedLocal = ModelRef(provider: AIProviderID(rawValue: last["provider"] as! String)!,
                                           model: last["model"] as! String)
        }
        input.appleReady = d["appleReady"] as! Bool
        input.failure = (d["failure"] as? String).map { AIErrorKind(rawValue: $0)! }
        return input
    }

    static func expected(_ d: [String: Any]) -> RouteDecision {
        RouteDecision(primary: (d["primary"] as? String).flatMap(AIProviderID.init(rawValue:)),
                      outcome: RouteOutcome(rawValue: d["outcome"] as! String)!,
                      answeredBy: (d["answeredBy"] as? String).flatMap(AIProviderID.init(rawValue:)),
                      label: (d["label"] as? String).flatMap(AIPlacement.init(rawValue:)),
                      errorKind: (d["errorKind"] as? String).flatMap(AIErrorKind.init(rawValue:)))
    }

    static func routerCases() {
        T.section("router-cases.json")
        let data = T.fixture("router-cases.json")
        let defaults = data["defaults"] as! [String: Any]
        for c in data["cases"] as! [[String: Any]] {
            let merged = defaults.merging(c["input"] as! [String: Any]) { _, new in new }
            T.check(c["name"] as! String, ModelRouter.route(routeInput(merged)), expected(c["expect"] as! [String: Any]))
        }

        T.section("ModelRouter.plan (app-side shape)")
        var input = RouteInput()
        input.keys = [.anthropic]
        input.localReady = [LocalCandidate(provider: .ollama, model: "qwen3.5:2b", placement: .local)]
        let plan = ModelRouter.plan(input)
        T.check("cloud primary keeps a local fallback", plan?.fallback?.model, "qwen3.5:2b")
        input.setting = .explicit(ModelRef(provider: .anthropic, model: "claude-opus-5-5"))
        T.check("explicit choice has no fallback", ModelRouter.plan(input)?.fallback, nil)
        T.check("explicit choice keeps its model", ModelRouter.plan(input)?.model, "claude-opus-5-5")
    }

    // MARK: - http-errors.json

    static func httpErrorCases() {
        T.section("http-errors.json")
        for c in T.fixture("http-errors.json")["cases"] as! [[String: Any]] {
            let status = c["status"] as! Int
            // A body is an object, a list, a string or null; `.fragmentsAllowed` keeps all of them.
            let body = (c["body"] as Any?).flatMap { $0 is NSNull ? nil : try! JSONSerialization.data(withJSONObject: $0, options: [.fragmentsAllowed]) }
            let headers = c["headers"] as! [String: String]
            let got = HTTPErrorRules.classify(status: status, body: body, headers: headers)
            let kind = AIErrorKind(rawValue: c["kind"] as! String)!
            T.check("\(status) → \(kind.rawValue)", "\(got.kind.rawValue) \(got.retryAfter.map(String.init) ?? "nil")",
                    "\(kind.rawValue) \((c["retryAfter"] as? Int).map(String.init) ?? "nil")")
        }

        T.section("HTTPErrorRules.classify never crashes")
        for raw in ["", "not json", "[]", "[1, 2]", "\"boom\"", "null", "{\"error\": []}", "{\"error\": 5}", "{\"error\": null}",
                    "{\"error\": [\"x\"]}", "{\"error\": {\"code\": 402, \"type\": [1], \"message\": {}}}"] {
            T.check("odd body \(raw.isEmpty ? "(empty)" : raw)", HTTPErrorRules.classify(status: 500, body: Data(raw.utf8), headers: [:]).kind, .server)
        }
        T.check("Retry-After: 0 is no value", HTTPErrorRules.classify(status: 429, body: nil, headers: ["Retry-After": "0"]).retryAfter, nil)
        T.check("Retry-After: ² is no value", HTTPErrorRules.classify(status: 429, body: nil, headers: ["retry-after": "²"]).retryAfter, nil)
        T.check("Retry-After: ١٢ (Arabic-Indic) is no value", HTTPErrorRules.classify(status: 429, body: nil, headers: ["Retry-After": "١٢"]).retryAfter, nil)
        T.check("Retry-After: +5 is no value (Int(\"+5\") alone would accept it)",
                HTTPErrorRules.classify(status: 429, body: nil, headers: ["Retry-After": "+5"]).retryAfter, nil)
        T.check("Retry-After: 12 counts", HTTPErrorRules.classify(status: 429, body: nil, headers: ["Retry-After": " 12 "]).retryAfter, 12)

        T.section("HTTPErrorRules.error")
        let body = try! JSONSerialization.data(withJSONObject:
            ["error": ["type": "insufficient_quota", "code": "insufficient_quota", "message": "quota"]])
        let e = HTTPErrorRules.error(status: 429, body: body, headers: ["x-request-id": "req_123"])
        T.check("billing keeps its code", e.code, "insufficient_quota")
        T.check("request id captured", e.requestID, "req_123")
        T.check("spend limit is spotted", HTTPErrorRules.isSpendLimit("project_spend_limit_exceeded"), true)
        T.check("quota is not a spend limit", HTTPErrorRules.isSpendLimit("insufficient_quota"), false)
        T.check("a user spend limit is spotted too", HTTPErrorRules.isSpendLimit("user_spend_limit_exceeded"), true)

        T.section("HTTPErrorRules.streamErrorKind (reference.py stream_error_kind)")
        let table: [(AIErrorKind, [String])] = [
            (.rateLimited, ["rate_limit_exceeded", "rate_limit_error"]),
            (.overloaded, ["server_is_overloaded", "slow_down", "overloaded_error"]),
            (.server, ["server_error", "api_error", "timeout_error", "vector_store_timeout"]),
            (.billing, ["insufficient_quota", "credit_balance_exhausted", "organization_usage_limit_exceeded", "billing_error",
                        "project_spend_limit_exceeded", "user_spend_limit_exceeded"]),
            (.refusal, ["invalid_prompt", "image_content_policy_violation", "content_policy_violation", "content_filter"]),
            (.auth, ["authentication_error", "invalid_api_key", "permission_error"]),
            (.badRequest, ["invalid_request_error", "context_length_exceeded", "something_new", "", "SERVER_ERROR"]),
        ]
        for (kind, codes) in table {
            for code in codes { T.check("\(code.isEmpty ? "(empty)" : code) → \(kind.rawValue)", HTTPErrorRules.streamErrorKind(code), kind) }
        }
        T.check("a missing code is bad_request, never server", HTTPErrorRules.streamErrorKind(nil), .badRequest)
        T.checkTrue("only known temporary codes may fall back",
                    ["something_new", "invalid_prompt", "context_length_exceeded", "insufficient_quota"]
                        .allSatisfy { !HTTPErrorRules.streamErrorKind($0).isTemporary })

        T.section("HTTPErrorRules.transportKind")
        T.check("offline", HTTPErrorRules.transportKind(URLError(.notConnectedToInternet)), .offline)
        T.check("refused", HTTPErrorRules.transportKind(URLError(.cannotConnectToHost)), .unreachable)
        T.check("dns", HTTPErrorRules.transportKind(URLError(.cannotFindHost)), .unreachable)
        T.check("timed out", HTTPErrorRules.transportKind(URLError(.timedOut)), .timeout)
        T.check("cancelled", HTTPErrorRules.transportKind(CancellationError()), .cancelled)
    }
```

Run: `bash scripts/test-ai-router.sh`
Expected: FAIL with `error: cannot find type 'LocalCandidate' in scope` (and `RouteInput`, `ModelRouter`, `HTTPErrorRules`).

- [ ] **Step 2: Write `NotchBuddy/Sources/App/AI/Core/HTTPErrors.swift`**

These are the rules of `reference.py` `classify_http`, in order: a billing marker or status 402 wins over the status table; then 401/403 → `auth`; 400/404/413/422 → `bad_request`; 429 → `rate_limited`; 503/529 → `overloaded`; other 5xx → `server`; anything else → `bad_request`. A billing marker is a code or type in `billingCodes`, any code ending in `_spend_limit_exceeded`, or "credit balance" in the message. The body's `error` may be an object, a string (LM Studio, Ollama) or a list whose first element is used (Google); anything else counts as no marker and nothing crashes. `Retry-After` counts only ASCII digits, and `0` is no value, so the app uses its default.

`streamErrorKind` is `reference.py` `stream_error_kind`: the one mapping for a code that arrives inside a stream (an OpenAI `response.failed` or `error` event, an Anthropic `error` event). It shares `isBilling` with `classify`, and everything it does not know is `bad_request`, which never falls back to a local model.

```swift
import Foundation

/// HTTP status + body → error kind, exactly as `tests/fixtures/ai/reference.py` `classify_http`.
enum HTTPErrorRules {
    static let billingCodes: Set<String> = [
        "insufficient_quota", "credit_balance_exhausted", "organization_usage_limit_exceeded", "billing_error",
    ]

    /// A billing code: the set above, or any `*_spend_limit_exceeded` (organization, project, user…).
    static func isBilling(_ code: String?) -> Bool {
        guard let code else { return false }
        return billingCodes.contains(code) || code.hasSuffix("_spend_limit_exceeded")
    }

    /// Rules in order: billing marker or 402, 401/403, 400/404/413/422, 429, 503/529, other 5xx, anything else.
    static func classify(status: Int, body: Data?, headers: [String: String]) -> (kind: AIErrorKind, retryAfter: Int?) {
        let err = errorObject(body)
        let message = (err["message"] as? String ?? "").lowercased()
        let retry = retryAfter(headers)
        if isBilling(err["code"] as? String) || isBilling(err["type"] as? String) || status == 402
            || message.contains("credit balance") {
            return (.billing, retry)
        }
        switch status {
        case 401, 403: return (.auth, retry)
        case 400, 404, 413, 422: return (.badRequest, retry)
        case 429: return (.rateLimited, retry)
        case 503, 529: return (.overloaded, retry)
        case 500..<600: return (.server, retry)
        default: return (.badRequest, retry)
        }
    }

    /// The full error: kind, Retry-After, code, message and request ID.
    static func error(status: Int, body: Data?, headers: [String: String]) -> AIError {
        let (kind, retry) = classify(status: status, body: body, headers: headers)
        let err = errorObject(body)
        let code = (err["code"] as? String) ?? (err["type"] as? String)
        return AIError(kind: kind, status: status, retryAfter: retry, code: code,
                       message: err["message"] as? String,
                       requestID: header("x-request-id", in: headers) ?? header("request-id", in: headers))
    }

    /// OpenAI's spend and usage caps (as opposed to running out of credit).
    static func isSpendLimit(_ code: String?) -> Bool {
        guard let code else { return false }
        return code.hasSuffix("_spend_limit_exceeded") || code == "organization_usage_limit_exceeded"
    }

    private static let streamKinds: [String: AIErrorKind] = [
        "rate_limit_exceeded": .rateLimited, "rate_limit_error": .rateLimited,
        "server_is_overloaded": .overloaded, "slow_down": .overloaded, "overloaded_error": .overloaded,
        "server_error": .server, "api_error": .server, "timeout_error": .server, "vector_store_timeout": .server,
        "invalid_prompt": .refusal, "image_content_policy_violation": .refusal,
        "content_policy_violation": .refusal, "content_filter": .refusal,
        "authentication_error": .auth, "invalid_api_key": .auth, "permission_error": .auth,
    ]

    /// Kind of a mid-stream error: an OpenAI `error.code` or an Anthropic `error.type`.
    /// Only the codes above may be temporary; everything else, a missing code included, is `bad_request`.
    static func streamErrorKind(_ codeOrType: String?) -> AIErrorKind {
        guard let code = codeOrType else { return .badRequest }
        if isBilling(code) { return .billing }
        return streamKinds[code] ?? .badRequest
    }

    /// Network failures before any HTTP status.
    static func transportKind(_ error: Error) -> AIErrorKind {
        if error is CancellationError { return .cancelled }
        guard let url = error as? URLError else { return .unreachable }
        switch url.code {
        case .notConnectedToInternet, .dataNotAllowed, .internationalRoamingOff: return .offline
        case .timedOut: return .timeout
        case .cancelled: return .cancelled
        default: return .unreachable
        }
    }

    static func header(_ name: String, in headers: [String: String]) -> String? {
        headers.first { $0.key.lowercased() == name }?.value
    }

    /// ASCII digits only (`²` and Arabic-Indic digits are not), and more than 0; otherwise nil.
    private static func retryAfter(_ headers: [String: String]) -> Int? {
        guard let raw = header("retry-after", in: headers)?.trimmingCharacters(in: .whitespaces),
              !raw.isEmpty, raw.utf8.allSatisfy({ $0 >= 0x30 && $0 <= 0x39 }),
              let seconds = Int(raw), seconds > 0 else { return nil }
        return seconds
    }

    /// `v` itself if an object, its first element if a list (Google wraps errors in a list), else empty.
    private static func firstObject(_ v: Any?) -> [String: Any] {
        if let list = v as? [Any] { return list.first as? [String: Any] ?? [:] }
        return v as? [String: Any] ?? [:]
    }

    /// The body's `error` object; a string, a number, `null` or bad JSON gives an empty one.
    private static func errorObject(_ body: Data?) -> [String: Any] {
        guard let body, let json = try? JSONSerialization.jsonObject(with: body, options: [.fragmentsAllowed]) else { return [:] }
        return firstObject(firstObject(json)["error"])
    }
}
```

- [ ] **Step 3: Write `NotchBuddy/Sources/App/AI/Core/ModelRouter.swift`**

`route()` reproduces `reference.py` exactly. `plan()` and `afterFailure()` are the two halves the app uses: what to call first, then what a failure means.

```swift
import Foundation

// MARK: - Settings

/// A model on a provider. `serverID` tells two servers of the same kind apart (custom servers).
struct ModelRef: Sendable, Equatable, Hashable, Codable {
    var provider: AIProviderID
    var model: String
    var serverID: String? = nil
}

/// What a feature (Chat, File questions) uses: Auto, or one model chosen by the user.
enum FeatureSetting: Sendable, Equatable, Hashable, Codable {
    case auto
    case explicit(ModelRef)
}

/// The features that pick a model. F adds `cats`.
enum AIFeature: String, Sendable, Codable, CaseIterable {
    case chat, files
}

/// A local or network model that answered discovery, in discovery order.
struct LocalCandidate: Sendable, Equatable {
    var provider: AIProviderID
    var model: String
    var placement: AIPlacement
    var serverID: String? = nil
}

struct RouteInput: Sendable {
    var setting: FeatureSetting = .auto
    var preferredCloud: AIProviderID = .anthropic
    /// Cloud providers with a key.
    var keys: Set<AIProviderID> = []
    var online = true
    var localReady: [LocalCandidate] = []
    var lastUsedLocal: ModelRef? = nil
    var appleReady = false
    /// Contract tests only: the failure to route.
    var failure: AIErrorKind? = nil
}

enum RouteOutcome: String, Sendable, Equatable {
    case ok, fallback, error, interrupted, cancelled
    case retryCountdown = "retry_countdown"
    case emptyState = "empty_state"
}

/// `reference.py` `route()` result.
struct RouteDecision: Sendable, Equatable {
    var primary: AIProviderID?
    var outcome: RouteOutcome
    var answeredBy: AIProviderID?
    var label: AIPlacement?
    var errorKind: AIErrorKind?
}

/// What to call first, and the one local retry Auto may use.
struct RoutePlan: Sendable, Equatable {
    var primary: AIProviderID
    /// Explicit or local model; nil for an Auto cloud primary (the caller uses the remembered model).
    var model: String?
    var serverID: String?
    var placement: AIPlacement
    var fallback: LocalCandidate?
    var isAuto: Bool
}

// MARK: - Router

/// Pure routing rules, identical to `tests/fixtures/ai/reference.py`.
enum ModelRouter {
    static let apple = LocalCandidate(provider: .apple, model: "system", placement: .local)

    /// Preferred cloud, then the other of Claude/OpenAI, then Google; the first with a key.
    static func cloudChoice(_ input: RouteInput) -> AIProviderID? {
        let other: [AIProviderID] = [.anthropic, .openai].filter { $0 != input.preferredCloud }
        return ([input.preferredCloud] + other + [.google]).first { input.keys.contains($0) }
    }

    /// Last used if ready, else the first ready, else Apple.
    static func localChoice(_ input: RouteInput) -> LocalCandidate? {
        if let last = input.lastUsedLocal,
           let hit = input.localReady.first(where: { $0.provider == last.provider && $0.model == last.model }) {
            return hit
        }
        if let first = input.localReady.first { return first }
        return input.appleReady ? apple : nil
    }

    static func placement(of provider: AIProviderID, in input: RouteInput) -> AIPlacement {
        if provider.isCloud { return .cloud }
        if provider == .apple { return .local }
        return input.localReady.first { $0.provider == provider }?.placement ?? .local
    }

    /// nil means nothing is set up (empty state).
    static func plan(_ input: RouteInput) -> RoutePlan? {
        if case .explicit(let ref) = input.setting {
            let ready = input.localReady.first {
                $0.provider == ref.provider && (ref.serverID == nil || $0.serverID == ref.serverID)
            }
            return RoutePlan(primary: ref.provider, model: ref.model, serverID: ref.serverID ?? ready?.serverID,
                             placement: ready?.placement ?? placement(of: ref.provider, in: input),
                             fallback: nil, isAuto: false)
        }
        let cloud = cloudChoice(input)
        let local = localChoice(input)
        if let cloud, input.online || local == nil {
            return RoutePlan(primary: cloud, model: nil, serverID: nil, placement: .cloud, fallback: local, isAuto: true)
        }
        if let local {
            return RoutePlan(primary: local.provider, model: local.model, serverID: local.serverID,
                             placement: local.placement, fallback: nil, isAuto: true)
        }
        return nil
    }

    /// What a failure of the primary means.
    static func afterFailure(_ plan: RoutePlan, failure: AIErrorKind) -> RouteDecision {
        switch failure {
        case .cancelled:
            return RouteDecision(primary: plan.primary, outcome: .cancelled, answeredBy: nil, label: nil, errorKind: nil)
        case .interrupted:
            return RouteDecision(primary: plan.primary, outcome: .interrupted, answeredBy: plan.primary,
                                 label: plan.placement, errorKind: .interrupted)
        default:
            break
        }
        if failure.isTemporary, plan.isAuto, plan.primary.isCloud, let local = plan.fallback {
            return RouteDecision(primary: plan.primary, outcome: .fallback, answeredBy: local.provider,
                                 label: local.placement, errorKind: failure)
        }
        if failure == .rateLimited || failure == .overloaded {
            return RouteDecision(primary: plan.primary, outcome: .retryCountdown, answeredBy: nil, label: nil, errorKind: failure)
        }
        return RouteDecision(primary: plan.primary, outcome: .error, answeredBy: nil, label: nil, errorKind: failure)
    }

    /// The contract function: plan, then apply `input.failure`.
    static func route(_ input: RouteInput) -> RouteDecision {
        guard let plan = plan(input) else {
            return RouteDecision(primary: nil, outcome: .emptyState, answeredBy: nil, label: nil, errorKind: nil)
        }
        guard let failure = input.failure else {
            return RouteDecision(primary: plan.primary, outcome: .ok, answeredBy: plan.primary,
                                 label: plan.placement, errorKind: nil)
        }
        return afterFailure(plan, failure: failure)
    }
}
```

- [ ] **Step 4: Run the tests**

Run: `bash scripts/test-ai-router.sh`
Expected: every `router-cases.json` case (30) and every `http-errors.json` case (21) is `✓`; so are the `never crashes` lines, the `streamErrorKind` table and the other `HTTPErrorRules` lines; then `All tests passed.`

- [ ] **Step 5: Prove a wrong rule fails**

Run each of these edits on its own, run the script, then restore the line:
- delete `.overloaded` from `isTemporary` in `ModelProvider.swift`. Expected: `✗ network server fallback is labelled network` (and the other `overloaded` fallback cases);
- in `streamErrorKind`, return `.server` for an unknown code (`?? .server`) instead of `.badRequest`. Expected: `✗ something_new → bad_request` and `✗ only known temporary codes may fall back`;
- in `classify`, replace `|| status == 402` with `|| false`. Expected: `✗ 402 → billing`;
- in `isBilling`, drop `|| code.hasSuffix("_spend_limit_exceeded")`. Expected: `✗ 429 → billing` (twice) and `✗ user_spend_limit_exceeded → billing`;
- in `firstObject`, replace the last line with `return v as! [String: Any]`. Expected: the run aborts with `Could not cast value of type 'NSTaggedPointerString'` (a string `error` field);
- in `retryAfter`, delete the `raw.utf8.allSatisfy(…)` condition. Expected: `✗ Retry-After: +5 is no value (Int("+5") alone would accept it)`;
- in `retryAfter`, delete `seconds > 0`. Expected: `✗ 429 → rate_limited` (the `0` case) and `✗ Retry-After: 0 is no value`.

Restored: `All tests passed.`

- [ ] **Step 6: Build the app**

Run: `cd NotchBuddy && xcodegen && xcodebuild -project NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug build 2>&1 | grep -E "error:|BUILD" ; cd ..`
Expected: `** BUILD SUCCEEDED **` and no `error:` line. New files under `Sources/` are picked up by `xcodegen`.

- [ ] **Step 7: Commit**

```bash
git add NotchBuddy/Sources/App/AI/Core/HTTPErrors.swift \
    NotchBuddy/Sources/App/AI/Core/ModelRouter.swift \
    tests/AIRouterTests.swift \
    NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -m "feat(ai): add the router and HTTP error rules from the shared cases

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---
### Task 3: SSE stream parsers and reply accumulator

**Files:**
- Create: `NotchBuddy/Sources/App/AI/Core/SSEParsers.swift`
- Create: `NotchBuddy/Sources/App/AI/Core/ReplyAccumulator.swift`
- Create: `tests/AIStreamTests.swift`
- Create: `scripts/test-ai-stream.sh`
- Modify: `.github/workflows/build.yml`

**Interfaces:**
- Consumes: `ChatChunk`, `ToolCallDelta`, `Citation`, `FinishReason` (Task 1); `HTTPErrorRules.streamErrorKind(_:)` (Task 2); `tests/fixtures/ai/sse/` (E1-0 Task 5 and the final-fix wave): 21 streams, 6 `openai-chat`, 10 `openai-responses` and 5 `anthropic`. The test checks those counts.
- Produces:
  - `SSELineSplitter` (`mutating push(_ byte: UInt8) -> String?`, `mutating flush() -> String?`): a line ends at the byte `0x0A` only, and one `\r` before it is dropped;
  - `SSEPayload(line:)` (`.done` / `.json`);
  - `protocol StreamParser: Sendable { mutating consume(line:) -> [ChatChunk]; mutating finish() -> [ChatChunk]; var isTerminal }`;
  - `OpenAIChatStreamParser`, `OpenAIResponsesStreamParser`, `AnthropicStreamParser`. The error events of the last two use `HTTPErrorRules.streamErrorKind` and never crash on an `error` that is not an object.
- Produces:
  - `ThinkFilter.strip(_:)` (no trim) and `ThinkFilter.visible(_:)` (hides an open block, trims);
  - `ReplyAccumulator(stripsThinkBlocks:)` with `add(_:)`, `text`, `visibleText`, `toolCalls`, `citations`, `refusal`, `finish`, `error`.

- [ ] **Step 1: Write the failing test `tests/AIStreamTests.swift`**

```swift
import Foundation

@main
@MainActor
enum AIStreamTests {
    static func main() {
        recordedStreams()
        thinkFilter()
        lineSplitter()
        streamedInPieces()
        failedCodes()
        oddErrorShapes()
        T.finish()
    }

    /// The lines of a stream, split like the transport does: at `\n` only (`SSELineSplitter`).
    static func lines(_ sse: String) -> [String] {
        var splitter = SSELineSplitter()
        var out = Array(sse.utf8).compactMap { splitter.push($0) }
        if let last = splitter.flush() { out.append(last) }
        return out
    }

    /// Runs one recorded stream through a parser and folds it like the reference aggregator.
    static func aggregate(format: String, sse: String) -> ReplyAccumulator {
        var acc = ReplyAccumulator(stripsThinkBlocks: format == "openai-chat")
        var chunks: [ChatChunk] = []
        switch format {
        case "openai-chat":
            var p = OpenAIChatStreamParser()
            for line in lines(sse) { chunks += p.consume(line: line) }
            chunks += p.finish()
        case "openai-responses":
            var p = OpenAIResponsesStreamParser()
            for line in lines(sse) { chunks += p.consume(line: line) }
            chunks += p.finish()
        default:
            var p = AnthropicStreamParser()
            for line in lines(sse) { chunks += p.consume(line: line) }
            chunks += p.finish()
        }
        chunks.forEach { acc.add($0) }
        return acc
    }

    /// The accumulator in the `.expected.json` shape, as comparable JSON text.
    static func asJSON(_ acc: ReplyAccumulator) -> String {
        let obj: [String: Any] = [
            "text": acc.text,
            "toolCalls": acc.toolCalls.map { ["id": $0.id, "name": $0.name, "arguments": $0.arguments] },
            "citations": acc.citations.map { ["url": $0.url, "title": $0.title] },
            "refusal": acc.refusal as Any? ?? NSNull(),
            "finish": acc.finish?.rawValue as Any? ?? NSNull(),
            "error": acc.error?.rawValue as Any? ?? NSNull(),
        ]
        return canonical(obj)
    }

    static func canonical(_ obj: Any) -> String {
        let data = try! JSONSerialization.data(withJSONObject: obj, options: [.sortedKeys])
        return String(decoding: data, as: UTF8.self)
    }

    static func recordedStreams() {
        T.section("sse/ recorded streams")
        var counts: [String: Int] = [:]
        for format in ["openai-chat", "openai-responses", "anthropic"] {
            let dir = T.fixtureURL("sse/\(format)")
            let names = try! FileManager.default.contentsOfDirectory(atPath: dir.path)
                .filter { $0.hasSuffix(".txt") }.sorted()
            for name in names {
                let sse = T.text("sse/\(format)/\(name)")
                let expected = T.fixture("sse/\(format)/\(name.dropLast(4)).expected.json")
                T.check("\(format)/\(name)", asJSON(aggregate(format: format, sse: sse)), canonical(expected))
                counts[format, default: 0] += 1
            }
        }
        T.check("streams per format", counts, ["openai-chat": 6, "openai-responses": 10, "anthropic": 5])
    }

    /// A line ends at LF only: CRLF still works, and a lone CR or a Unicode separator stays inside its line.
    static func lineSplitter() {
        T.section("SSELineSplitter")
        T.check("LF", lines("a\nb\n"), ["a", "b"])
        T.check("CRLF drops one CR", lines("a\r\nb\r\n"), ["a", "b"])
        T.check("a last line without LF", lines("a\nb"), ["a", "b"])
        T.check("a lone CR is no line end", lines("x\ry\n"), ["x\ry"])
        T.check("U+2028, U+2029, U+0085, VT and FF are no line ends", lines("a\u{2028}b\u{2029}c\u{85}d\u{0B}e\u{0C}f\n"),
                ["a\u{2028}b\u{2029}c\u{85}d\u{0B}e\u{0C}f"])
        T.check("only one CR is dropped", lines("a\r\r\n"), ["a\r"])
        T.check("a blank line stays a line", lines("a\n\nb\n"), ["a", "", "b"])
        T.check("multi-byte characters are never cut", lines("é🐱\n"), ["é🐱"])
        var comment = OpenAIChatStreamParser()
        let chunks = lines(": ping\rdata: {\"choices\":[{\"delta\":{\"content\":\"X\"}}]}\n").flatMap { comment.consume(line: $0) }
        T.check("a data: after a lone CR is part of the comment line", chunks.isEmpty, true)
    }

    static func thinkFilter() {
        T.section("ThinkFilter")
        T.check("strip keeps surrounding text", ThinkFilter.strip("a<think>x</think>b"), "ab")
        T.check("strip does not trim", ThinkFilter.strip("<think>x</think> hi "), " hi ")
        T.check("strip leaves an open block", ThinkFilter.strip("hi<think>open"), "hi<think>open")
        T.check("visible hides an open block", ThinkFilter.visible("answer<think>hidden"), "answer")
        T.check("visible of open block alone", ThinkFilter.visible("<think>\nhalf"), "")
        T.check("visible removes closed block", ThinkFilter.visible("<think>done</think>result"), "result")
    }

    /// `response.failed`, the `error` event and Anthropic's `error` event all map their code through
    /// `HTTPErrorRules.streamErrorKind`: billing and refusals never look temporary, unknown is `bad_request`.
    static func failedCodes() {
        T.section("Stream failure codes")
        func failed(_ code: String) -> AIErrorKind? {
            let line = #"data: {"type":"response.failed","response":{"status":"failed","error":{"code":"\#(code)"}}}"#
            return aggregate(format: "openai-responses", sse: line).error
        }
        func errorEvent(_ code: String) -> AIErrorKind? {
            aggregate(format: "openai-responses", sse: #"data: {"type":"error","code":"\#(code)","message":"m"}"#).error
        }
        func anthropic(_ type: String) -> AIErrorKind? {
            aggregate(format: "anthropic", sse: #"data: {"type":"error","error":{"type":"\#(type)","message":"m"}}"#).error
        }
        T.check("failed + insufficient_quota → billing", failed("insufficient_quota"), .billing)
        T.check("failed + rate_limit_exceeded → rate_limited", failed("rate_limit_exceeded"), .rateLimited)
        T.check("failed + project_spend_limit_exceeded → billing", failed("project_spend_limit_exceeded"), .billing)
        T.check("failed + server_error → server", failed("server_error"), .server)
        T.check("failed + invalid_prompt → refusal", failed("invalid_prompt"), .refusal)
        T.check("failed + an unknown code → bad_request", failed("something_new"), .badRequest)
        T.check("error event + server_is_overloaded → overloaded", errorEvent("server_is_overloaded"), .overloaded)
        T.check("error event + an unknown code → bad_request", errorEvent("something_new"), .badRequest)
        T.check("anthropic overloaded_error → overloaded", anthropic("overloaded_error"), .overloaded)
        T.check("anthropic rate_limit_error → rate_limited", anthropic("rate_limit_error"), .rateLimited)
        T.check("anthropic api_error → server", anthropic("api_error"), .server)
        T.check("anthropic authentication_error → auth", anthropic("authentication_error"), .auth)
        T.check("anthropic billing_error → billing", anthropic("billing_error"), .billing)
        T.check("anthropic invalid_request_error → bad_request", anthropic("invalid_request_error"), .badRequest)
        T.check("anthropic an unknown type → bad_request", anthropic("something_new"), .badRequest)
    }

    /// An `error` that is a string, `null`, a list or missing is an unknown code: `bad_request`, never a crash.
    static func oddErrorShapes() {
        T.section("Odd error shapes")
        let failed = ["\"boom\"", "null", "[]", "[1]", "5", "{}", "{\"code\": 5}", "{\"code\": null}", "{\"code\": [\"x\"]}"]
        for shape in failed {
            let responses = aggregate(format: "openai-responses", sse: #"data: {"type":"response.failed","response":{"error":\#(shape)}}"#)
            T.check("response.failed with error \(shape)", responses.error, .badRequest)
            let anthropic = aggregate(format: "anthropic", sse: #"data: {"type":"error","error":\#(shape)}"#)
            T.check("anthropic error with error \(shape)", anthropic.error, .badRequest)
        }
        T.check("response.failed with no response", aggregate(format: "openai-responses", sse: #"data: {"type":"response.failed"}"#).error, .badRequest)
        T.check("response.failed with a string response",
                aggregate(format: "openai-responses", sse: #"data: {"type":"response.failed","response":"x"}"#).error, .badRequest)
        T.check("error event with a number code",
                aggregate(format: "openai-responses", sse: #"data: {"type":"error","code":7}"#).error, .badRequest)
        T.check("anthropic error with no error", aggregate(format: "anthropic", sse: #"data: {"type":"error"}"#).error, .badRequest)
    }

    /// A `<think>` tag split across two deltas still disappears.
    static func streamedInPieces() {
        T.section("ReplyAccumulator")
        var acc = ReplyAccumulator(stripsThinkBlocks: true)
        for piece in ["<thi", "nk>plan</th", "ink>Hello"] { acc.add(.text(piece)) }
        T.check("split think tags", acc.text, "Hello")
        acc.add(.citation(Citation(url: "https://a.example", title: "A")))
        acc.add(.citation(Citation(url: "https://a.example", title: "A again")))
        T.check("citations dedupe by URL", acc.citations.count, 1)
        acc.add(.finish(.stop))
        acc.add(.error(.interrupted))
        T.check("an error hides the finish reason", acc.finish, nil)
    }
}
```

- [ ] **Step 2: Write `scripts/test-ai-stream.sh`**

```bash
#!/usr/bin/env bash
# AI core: the three SSE parsers against every recorded stream in tests/fixtures/ai/sse/.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-ai-stream.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs
swiftc -swift-version 6 \
    NotchBuddy/Sources/App/AI/Core/*.swift \
    NotchBuddy/Sources/App/AppLog.swift \
    tests/AITestSupport.swift tests/AIStreamTests.swift \
    -o "$TEST_DIR/ai-stream-tests"
"$TEST_DIR/ai-stream-tests"
```

Run: `chmod +x scripts/test-ai-stream.sh && bash scripts/test-ai-stream.sh`
Expected: FAIL with `error: cannot find 'ReplyAccumulator' in scope`.

- [ ] **Step 3: Write `NotchBuddy/Sources/App/AI/Core/SSEParsers.swift`**

Each parser turns `data:` lines into chunks and ignores comments, `event:` lines, blanks and non-JSON payloads. `finish()` adds `.error(.interrupted)` when the terminal event never came: `[DONE]` for chat, `message_stop` for Anthropic, and `response.completed`, `.incomplete` or `.failed` for Responses. Search and reasoning steps emit `.activity`: it counts as the first token for timeouts and is otherwise ignored. Error events never choose a kind themselves: they call `HTTPErrorRules.streamErrorKind`, so a code nobody mapped is `bad_request` and Auto never retries it on a local model. `SSELineSplitter` is what cuts the stream into lines (`0x0A` only; see Global Constraints).

```swift
import Foundation

// MARK: - SSE lines

/// Splits a byte stream into lines. A line ends at the byte `0x0A` only, and one `\r` before it is dropped
/// (CRLF). A lone `\r`, U+2028, U+2029, U+0085, VT and FF stay inside their line, as the contract says.
/// Not `URLSession.AsyncBytes.lines` or `String.split`/`lines`: they also split on those, and Swift
/// reads `\r\n` as a single `Character`, so `split(separator: "\n")` would not split it at all.
/// Working on bytes also means a multi-byte character can never be cut: UTF-8 continuation bytes are never `0x0A`.
struct SSELineSplitter: Sendable {
    private var buffer: [UInt8] = []

    /// The finished line when `byte` ends one.
    mutating func push(_ byte: UInt8) -> String? {
        guard byte == 0x0A else { buffer.append(byte); return nil }
        return take()
    }

    /// The last line, when the stream ends without a final LF.
    mutating func flush() -> String? { buffer.isEmpty ? nil : take() }

    private mutating func take() -> String {
        if buffer.last == 0x0D { buffer.removeLast() }
        defer { buffer.removeAll(keepingCapacity: true) }
        return String(decoding: buffer, as: UTF8.self)
    }
}

/// One `data:` payload. Comments (`:`), `event:` lines, blanks and non-JSON data are skipped.
enum SSEPayload {
    case done
    case json([String: Any])

    init?(line: String) {
        guard line.hasPrefix("data:") else { return nil }
        let payload = line.dropFirst(5).trimmingCharacters(in: .whitespaces)
        if payload == "[DONE]" { self = .done; return }
        guard let obj = try? JSONSerialization.jsonObject(with: Data(payload.utf8)) as? [String: Any] else { return nil }
        self = .json(obj)
    }
}

/// Turns SSE lines into chunks. `finish()` adds `.error(.interrupted)` when the terminal event never came.
protocol StreamParser: Sendable {
    mutating func consume(line: String) -> [ChatChunk]
    mutating func finish() -> [ChatChunk]
    /// True once the terminal event arrived: stop reading.
    var isTerminal: Bool { get }
}

// MARK: - OpenAI chat completions (local servers, Google)

struct OpenAIChatStreamParser: StreamParser {
    private var done = false

    var isTerminal: Bool { done }

    mutating func consume(line: String) -> [ChatChunk] {
        guard let payload = SSEPayload(line: line) else { return [] }
        guard case .json(let event) = payload else { done = true; return [] }
        var out: [ChatChunk] = []
        for choice in event["choices"] as? [[String: Any]] ?? [] {
            let delta = choice["delta"] as? [String: Any] ?? [:]
            if let text = delta["content"] as? String, !text.isEmpty { out.append(.text(text)) }
            for call in delta["tool_calls"] as? [[String: Any]] ?? [] {
                let fn = call["function"] as? [String: Any] ?? [:]
                out.append(.toolCall(ToolCallDelta(index: call["index"] as? Int ?? 0, id: call["id"] as? String,
                                                   name: fn["name"] as? String,
                                                   arguments: fn["arguments"] as? String ?? "")))
            }
            if let reason = choice["finish_reason"] as? String {
                if reason == "content_filter" {
                    out.append(.refusal("", replacesText: false))
                    out.append(.finish(.refusal))
                } else {
                    out.append(.finish(FinishReason(rawValue: reason) ?? .stop))
                }
            }
        }
        return out
    }

    mutating func finish() -> [ChatChunk] { done ? [] : [.error(.interrupted)] }
}

// MARK: - OpenAI Responses (no [DONE]; terminal events instead)

struct OpenAIResponsesStreamParser: StreamParser {
    private var terminal = false
    private var errored = false
    private var callIndex: [String: Int] = [:]
    private var refused = false

    var isTerminal: Bool { terminal || errored }

    mutating func consume(line: String) -> [ChatChunk] {
        guard case .json(let event)? = SSEPayload(line: line), let type = event["type"] as? String else { return [] }
        switch type {
        case "response.output_text.delta":
            return [.text(event["delta"] as? String ?? "")]
        case "response.output_item.added":
            guard let item = event["item"] as? [String: Any] else { return [] }
            guard item["type"] as? String == "function_call", let itemID = item["id"] as? String else { return [.activity] }
            let index = callIndex.count
            callIndex[itemID] = index
            return [.toolCall(ToolCallDelta(index: index, id: item["call_id"] as? String, name: item["name"] as? String,
                                            arguments: item["arguments"] as? String ?? "", replacesArguments: true))]
        case "response.function_call_arguments.delta", "response.function_call_arguments.done":
            guard let itemID = event["item_id"] as? String, let index = callIndex[itemID] else { return [] }
            let isDone = type.hasSuffix(".done")
            let args = (isDone ? event["arguments"] : event["delta"]) as? String ?? ""
            return [.toolCall(ToolCallDelta(index: index, arguments: args, replacesArguments: isDone))]
        case "response.web_search_call.in_progress", "response.web_search_call.searching":
            return [.activity]
        case "response.output_text.annotation.added":
            guard let a = event["annotation"] as? [String: Any], a["type"] as? String == "url_citation",
                  let url = a["url"] as? String else { return [] }
            return [.citation(Citation(url: url, title: a["title"] as? String ?? ""))]
        case "response.refusal.done":
            refused = true
            return [.refusal(event["refusal"] as? String ?? "", replacesText: false)]
        case "response.completed":
            terminal = true
            return [.finish(refused ? .refusal : (callIndex.isEmpty ? .stop : .toolCalls))]
        case "response.incomplete":
            terminal = true
            let details = (event["response"] as? [String: Any])?["incomplete_details"] as? [String: Any]
            return [.finish(details?["reason"] as? String == "content_filter" ? .refusal : .length)]
        case "response.failed":
            terminal = true
            errored = true
            // An `error` that is a string, null or a list has no code: unknown, so bad_request.
            let error = (event["response"] as? [String: Any])?["error"] as? [String: Any]
            return [.error(HTTPErrorRules.streamErrorKind(error?["code"] as? String))]
        case "error":
            errored = true
            return [.error(HTTPErrorRules.streamErrorKind(event["code"] as? String))]
        default:
            return []
        }
    }

    mutating func finish() -> [ChatChunk] { isTerminal ? [] : [.error(.interrupted)] }
}

// MARK: - Anthropic Messages

struct AnthropicStreamParser: StreamParser {
    private var toolIndexByBlock: [Int: Int] = [:]
    private var text = ""
    private var stopped = false
    private var errored = false

    var isTerminal: Bool { stopped || errored }

    mutating func consume(line: String) -> [ChatChunk] {
        guard case .json(let event)? = SSEPayload(line: line), let type = event["type"] as? String else { return [] }
        switch type {
        case "content_block_start":
            guard let index = event["index"] as? Int, let block = event["content_block"] as? [String: Any] else { return [] }
            guard block["type"] as? String == "tool_use" else { return [.activity] }
            let toolIndex = toolIndexByBlock.count
            toolIndexByBlock[index] = toolIndex
            return [.toolCall(ToolCallDelta(index: toolIndex, id: block["id"] as? String, name: block["name"] as? String,
                                            replacesArguments: true))]
        case "content_block_delta":
            guard let index = event["index"] as? Int, let delta = event["delta"] as? [String: Any] else { return [] }
            switch delta["type"] as? String {
            case "text_delta":
                let t = delta["text"] as? String ?? ""
                text += t
                return [.text(t)]
            case "input_json_delta":
                // server_tool_use (web search) arguments are not client tool calls.
                guard let toolIndex = toolIndexByBlock[index] else { return [] }
                return [.toolCall(ToolCallDelta(index: toolIndex, arguments: delta["partial_json"] as? String ?? ""))]
            case "citations_delta":
                guard let c = delta["citation"] as? [String: Any], let url = c["url"] as? String else { return [] }
                return [.citation(Citation(url: url, title: c["title"] as? String ?? ""))]
            default:
                return []
            }
        case "message_delta":
            let reasons: [String: FinishReason] = ["end_turn": .stop, "stop_sequence": .stop, "max_tokens": .length,
                                                   "tool_use": .toolCalls, "refusal": .refusal]
            guard let raw = (event["delta"] as? [String: Any])?["stop_reason"] as? String,
                  let reason = reasons[raw] else { return [] }
            return reason == .refusal ? [.refusal(text, replacesText: true), .finish(.refusal)] : [.finish(reason)]
        case "message_stop":
            stopped = true
            return []
        case "error":
            errored = true
            let type = (event["error"] as? [String: Any])?["type"] as? String
            return [.error(HTTPErrorRules.streamErrorKind(type))]
        default:
            return []
        }
    }

    mutating func finish() -> [ChatChunk] { isTerminal ? [] : [.error(.interrupted)] }
}
```

- [ ] **Step 4: Write `NotchBuddy/Sources/App/AI/Core/ReplyAccumulator.swift`**

```swift
import Foundation

// MARK: - <think> blocks (reasoning models on local servers)

enum ThinkFilter {
    private static let closed = try! NSRegularExpression(pattern: "<think>[\\s\\S]*?</think>")

    /// Removes closed `<think>…</think>` blocks. No trimming: this is the contract's `text`.
    static func strip(_ text: String) -> String {
        closed.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: "")
    }

    /// What the chat bubble shows while streaming: closed blocks removed, an open block hidden, trimmed.
    static func visible(_ text: String) -> String {
        let cleaned = strip(text)
        let shown = cleaned.range(of: "<think>").map { String(cleaned[..<$0.lowerBound]) } ?? cleaned
        return shown.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Folding chunks into a reply

/// Folds a chunk stream into the shape of the contract's `.expected.json`.
struct ReplyAccumulator: Sendable {
    struct ToolCall: Sendable, Equatable {
        var id = ""
        var name = ""
        var arguments = ""
    }

    /// True for the OpenAI chat-completions format, whose reasoning models emit `<think>` blocks.
    let stripsThinkBlocks: Bool
    private(set) var rawText = ""
    private var calls: [Int: ToolCall] = [:]
    private(set) var citations: [Citation] = []
    private(set) var refusal: String?
    private var finishReason: FinishReason?
    private(set) var error: AIErrorKind?

    init(stripsThinkBlocks: Bool) { self.stripsThinkBlocks = stripsThinkBlocks }

    mutating func add(_ chunk: ChatChunk) {
        switch chunk {
        case .text(let t):
            rawText += t
        case .toolCall(let d):
            var call = calls[d.index] ?? ToolCall()
            if let id = d.id, !id.isEmpty { call.id = id }
            if let name = d.name, !name.isEmpty { call.name = name }
            call.arguments = d.replacesArguments ? d.arguments : call.arguments + d.arguments
            calls[d.index] = call
        case .citation(let c):
            if !citations.contains(where: { $0.url == c.url }) { citations.append(c) }
        case .refusal(let r, let replacesText):
            refusal = r
            if replacesText { rawText = "" }
        case .finish(let f):
            finishReason = f
        case .error(let kind):
            error = kind
        case .activity:
            break
        }
    }

    /// The reply text (think blocks removed when the format has them).
    var text: String { stripsThinkBlocks ? ThinkFilter.strip(rawText) : rawText }
    /// What to show while streaming.
    var visibleText: String { stripsThinkBlocks ? ThinkFilter.visible(rawText) : rawText }
    var toolCalls: [ToolCall] { calls.keys.sorted().map { calls[$0]! } }
    /// nil when the stream failed.
    var finish: FinishReason? { error == nil ? finishReason : nil }
}
```

- [ ] **Step 5: Run the tests**

Run: `bash scripts/test-ai-stream.sh`
Expected:
- all 21 streams `✓` (including `openai-responses/failed-policy.txt`, `failed-billing.txt`, `failed-unknown.txt`, `cut.txt`, and `openai-chat/content-filter.txt`, `crlf.txt`, `unicode-separators.txt`) and `✓ streams per format`;
- the `SSELineSplitter`, `Stream failure codes` and `Odd error shapes` lines `✓`;
- the `ThinkFilter` and `ReplyAccumulator` lines `✓`, then `All tests passed.`

Then break each rule once, run the script and restore it:
- unknown code → `.server` in `streamErrorKind`: `✗ openai-responses/failed-unknown.txt`;
- delete `if buffer.last == 0x0D { buffer.removeLast() }` in `SSELineSplitter`: `✗ openai-chat/crlf.txt`, `✗ CRLF drops one CR`;
- also end a line at `0x0D` (`byte == 0x0A || byte == 0x0D`): `✗ a lone CR is no line end` and `✗ only one CR is dropped`;
- make `OpenAIResponsesStreamParser.finish()` return `[]`: `✗ openai-responses/cut.txt`.

- [ ] **Step 6: Add the CI step**

In `.github/workflows/build.yml`, insert this step immediately before `- name: Test plan gauge` (after any `AI …` steps added by earlier tasks), at the same indentation:

```yaml
      - name: AI stream parsers
        run: bash scripts/test-ai-stream.sh
```

- [ ] **Step 7: Build the app**

Run: `cd NotchBuddy && xcodegen && xcodebuild -project NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug build 2>&1 | grep -E "error:|BUILD" ; cd ..`
Expected: `** BUILD SUCCEEDED **` and no `error:` line. New files under `Sources/` are picked up by `xcodegen`.

- [ ] **Step 8: Commit**

```bash
git add NotchBuddy/Sources/App/AI/Core/SSEParsers.swift \
    NotchBuddy/Sources/App/AI/Core/ReplyAccumulator.swift \
    tests/AIStreamTests.swift \
    scripts/test-ai-stream.sh \
    .github/workflows/build.yml \
    NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -m "feat(ai): parse chat, Responses and Anthropic streams

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---
### Task 4: Context budget and attachments

**Files:**
- Create: `NotchBuddy/Sources/App/AI/Core/ContextBudget.swift`
- Create: `NotchBuddy/Sources/App/AI/Core/Attachments.swift`
- Create: `NotchBuddy/Sources/App/AI/Platform/AttachmentExtractor.swift`
- Create: `tests/AIBudgetTests.swift`, `tests/AIAttachmentTests.swift`
- Create: `scripts/test-ai-budget.sh`, `scripts/test-ai-attachments.sh`
- Modify: `.github/workflows/build.yml`

**Interfaces:**
- Consumes: `AICatalog.Limits` (Task 1), `ChatRequest.Part`, `ChatRequest.Message`, `AIProviderAPI`, `AIPlacement` (Task 1); `budget-cases.json`, `history-cases.json`, `attachment-cases.json`, `make_attachments.py` (E1-0 Tasks 3, 3b and 4).
- Produces:
  - `BudgetResult {keptChars, keptLines, notice?, text}`;
  - `ContextBudget.charBudget(placement:contextTokens:)`, `.cut(_:placement:contextTokens:) -> BudgetResult`;
  - `HistoryTrim {dropped, notice?}` and the shared history rule (E1-0 Task 3b):
    - `ContextBudget.trimHistory(turnChars:systemChars:placement:contextTokens:) -> HistoryTrim`, over sizes in Unicode scalars;
    - `ContextBudget.trimHistory(messages:system:placement:contextTokens:) -> HistoryTrim`, over real messages, which sizes each one with `ContextBudget.chars(of:)`;
    - `ContextBudget.estimatedTokens(chars:)`, `.reservedOutputDivisor` (4), `.binaryPartChars` (1,000) and `.historyNotice`.
- Produces:
  - `AttachmentKind {text, image, docx, rtf, html, pdfText, pdfScanned}`, `AttachmentRejection {size, type}`;
  - `PreparedFile {name, kind, mime, data?, text?, pageImages}`;
  - `AttachmentRules.classify(url:)` and `.classify(size:ext:head:)` → `Result<Coarse, AttachmentRejection>`, plus `AttachmentRules.htmlToText(_:)`;
  - `AttachmentPlan.parts(for:api:vision:placement:contextTokens:) -> (parts: [ChatRequest.Part], notice: String?)`.
- Produces: `AttachmentPlan.sendableImageTypes` (png, jpeg, gif, webp).
- Produces (Platform):
  - `AttachmentExtractor.prepare(url:) -> Result<PreparedFile, AttachmentRejection>` (synchronous: call it off the main thread);
  - `AttachmentExtractor.cgImage(_:)` and `.jpeg(_:)`, both through ImageIO: HEIC is re-encoded as JPEG.

- [ ] **Step 1: Write the failing budget test `tests/AIBudgetTests.swift`**

```swift
import Foundation

@main
@MainActor
enum AIBudgetTests {
    static func main() {
        budgetCases()
        cutText()
        historyCases()
        T.finish()
    }

    static func budgetCases() {
        T.section("budget-cases.json")
        for c in T.fixture("budget-cases.json")["cases"] as! [[String: Any]] {
            let fill = c["fill"] as? String ?? "a"
            let line = String(repeating: fill, count: (c["lineLength"] as! Int) - 1) + "\n"
            let text = String(repeating: line, count: c["lineCount"] as! Int)
            let r = ContextBudget.cut(text, placement: AIPlacement(rawValue: c["placement"] as! String)!,
                                      contextTokens: c["contextTokens"] as? Int)
            let e = c["expect"] as! [String: Any]
            T.check(c["name"] as! String, "\(r.keptChars) \(r.keptLines) \(r.notice ?? "nil")",
                    "\(e["keptChars"] as! Int) \(e["keptLines"] as! Int) \(e["notice"] as? String ?? "nil")")
            T.check("\(c["name"] as! String): text length matches", r.text.unicodeScalars.count, r.keptChars)
        }
    }

    static func cutText() {
        T.section("ContextBudget.cut text")
        let r = ContextBudget.cut("one\ntwo\n" + String(repeating: "x", count: 8000), placement: .local, contextTokens: nil)
        T.check("keeps whole lines", r.text, "one\ntwo\n")
        T.check("notice", r.notice, "I read the first 2 lines.")
        T.check("the integer line is the catalog's 50% at 3.5 chars a token",
                AICatalog.Limits.budgetFractionOfContext * AICatalog.Limits.charsPerToken, 1.75)
        T.check("floor(ctx × 7 / 4)", [4096, 4097, 4099, 1].map { ContextBudget.charBudget(placement: .local, contextTokens: $0) },
                [7168, 7169, 7173, 1])
        T.check("unknown local context is 4,096 tokens", ContextBudget.charBudget(placement: .network, contextTokens: nil), 7168)
        T.check("cloud is capped at 204,800", ContextBudget.charBudget(placement: .cloud, contextTokens: 1_000_000), 204_800)
        T.check("cloud with no context is the cap", ContextBudget.charBudget(placement: .cloud, contextTokens: nil), 204_800)

        // Lines end at \n only: CRLF counts as one line end, a lone CR, U+2028 and U+0085 as none.
        let crlf = ContextBudget.cut(String(repeating: "ab\r\n", count: 3000), placement: .local, contextTokens: nil)
        T.check("CRLF lines are counted at the LF", "\(crlf.keptLines) \(crlf.keptChars)", "1792 7168")
        let odd = ContextBudget.cut("a\u{2028}b\u{85}c\rd\n" + String(repeating: "x", count: 8000), placement: .local, contextTokens: nil)
        T.check("Unicode separators and a lone CR are no line ends", "\(odd.keptLines) \(odd.text)", "1 a\u{2028}b\u{85}c\rd\n")
    }

    /// Every case of history-cases.json, built into real messages (text, file text, image and PDF parts),
    /// so the count of Unicode scalars is tested through the same code the chat uses.
    static func historyCases() {
        T.section("history-cases.json")
        let json = T.fixture("history-cases.json")
        let rule = json["rule"] as! [String: Any]
        T.check("rule constants", [ContextBudget.reservedOutputDivisor, ContextBudget.binaryPartChars],
                [rule["reservedOutputDivisor"] as! Int, rule["binaryAttachmentChars"] as! Int])
        T.check("notice", ContextBudget.historyNotice, rule["notice"] as! String)
        T.check("3.5 characters a token, rounded up",
                [0, 1, 7, 8].map { ContextBudget.estimatedTokens(chars: $0) }, [0, 1, 2, 3])

        func text(_ spec: Any?) -> String {
            let s = spec as! [String: Any]
            return String(repeating: s["fill"] as! String, count: s["count"] as! Int)
        }
        for c in json["cases"] as! [[String: Any]] {
            let messages = (c["turns"] as! [[String: Any]]).map { turn -> ChatRequest.Message in
                var parts: [ChatRequest.Part] = []
                for file in turn["files"] as? [[String: Any]] ?? [] {
                    switch file["kind"] as! String {
                    case "text": parts.append(.fileText(name: "f.txt", text: text(file["text"])))
                    case "image": parts.append(.image(mime: "image/png", data: Data([1])))
                    default: parts.append(.pdf(name: "f.pdf", data: Data([1])))
                    }
                }
                parts.append(.text(text(turn["text"])))
                return ChatRequest.Message(role: ChatRequest.Role(rawValue: turn["role"] as! String)!, parts: parts)
            }
            let got = ContextBudget.trimHistory(messages: messages, system: text(c["system"]),
                                                placement: AIPlacement(rawValue: c["placement"] as! String)!,
                                                contextTokens: c["contextTokens"] as? Int)
            let e = c["expect"] as! [String: Any]
            T.check(c["name"] as! String, "\(got.dropped) \(got.notice ?? "nil")",
                    "\(e["dropped"] as! Int) \(e["notice"] as? String ?? "nil")")
        }
    }
}
```

- [ ] **Step 2: Write `scripts/test-ai-budget.sh`**

```bash
#!/usr/bin/env bash
# AI core: context budget (budget-cases.json) and chat-history trimming.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-ai-budget.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs
swiftc -swift-version 6 \
    NotchBuddy/Sources/App/AI/Core/*.swift \
    NotchBuddy/Sources/App/AppLog.swift \
    tests/AITestSupport.swift tests/AIBudgetTests.swift \
    -o "$TEST_DIR/ai-budget-tests"
"$TEST_DIR/ai-budget-tests"
```

Run: `chmod +x scripts/test-ai-budget.sh && bash scripts/test-ai-budget.sh`
Expected: FAIL with `error: cannot find 'ContextBudget' in scope`.

- [ ] **Step 3: Write `NotchBuddy/Sources/App/AI/Core/ContextBudget.swift`**

`cut` reproduces `reference.py` `budget()`, counting Unicode scalars: `emoji-scalars` fails if bytes are counted.
`trimHistory` is `reference.py` `trim_history()`: the Windows app implements the same rule, and the `scalars, not characters or bytes` case fails if `Character`s are counted.

```swift
import Foundation

/// What a long chat leaves out (`reference.py` `trim_history()`).
struct HistoryTrim: Sendable, Equatable {
    /// Messages dropped from the oldest end.
    var dropped: Int
    /// "This chat got long, so I dropped the oldest messages." when something was dropped.
    var notice: String?
}

/// Result of sizing a file's text to the model (`reference.py` `budget()`).
struct BudgetResult: Sendable, Equatable {
    /// Unicode scalars kept.
    var keptChars: Int
    var keptLines: Int
    /// "I read the first N lines." etc., nil when nothing was cut.
    var notice: String?
    var text: String
}

enum ContextBudget {
    /// Characters (Unicode scalars) a file may use: `floor(context × 7 / 4)`, i.e. 50% of the context at
    /// 3.5 chars/token, in integers (a context of 4,097 gives 7,169, never 7,170). Unknown local
    /// context = 4,096 tokens, cloud capped at 204,800.
    static func charBudget(placement: AIPlacement, contextTokens: Int?) -> Int {
        let limits = AICatalog.Limits.self
        let context = contextTokens ?? (placement == .cloud ? nil : limits.defaultLocalContextTokens)
        let fromContext = context.map { $0 * 7 / 4 }
        guard placement == .cloud else { return fromContext ?? 0 }
        return min(fromContext ?? limits.cloudTextCapChars, limits.cloudTextCapChars)
    }

    /// Cuts `text` at whole lines to fit; a first line longer than the budget is cut mid-line.
    static func cut(_ text: String, placement: AIPlacement, contextTokens: Int?) -> BudgetResult {
        let budget = charBudget(placement: placement, contextTokens: contextTokens)
        let scalars = Array(text.unicodeScalars)
        if scalars.count <= budget {
            let newlines = scalars.reduce(0) { $0 + ($1 == "\n" ? 1 : 0) }
            let lines = newlines + ((text.isEmpty || scalars.last == "\n") ? 0 : 1)
            return BudgetResult(keptChars: scalars.count, keptLines: lines, notice: nil, text: text)
        }
        var kept = 0, lines = 0, lineStart = 0
        for (i, s) in scalars.enumerated() where s == "\n" {
            let length = i + 1 - lineStart
            if kept + length > budget { break }
            kept += length
            lines += 1
            lineStart = i + 1
        }
        if lines == 0 {
            return BudgetResult(keptChars: budget, keptLines: 0, notice: "I read the first part of this file.",
                                text: string(scalars[0..<budget]))
        }
        let notice = lines == 1 ? "I read the first line." : "I read the first \(lines) lines."
        return BudgetResult(keptChars: kept, keptLines: lines, notice: notice, text: string(scalars[0..<kept]))
    }

    // MARK: - Long chats (history-cases.json)

    /// A quarter of the context is kept for the reply.
    static let reservedOutputDivisor = 4
    /// An image or PDF sent as such counts this many scalars.
    static let binaryPartChars = 1000
    static let historyNotice = "This chat got long, so I dropped the oldest messages."

    /// Tokens for `chars` Unicode scalars at 3.5 per token, rounded up, in integers: `ceil(2n ÷ 7)`.
    static func estimatedTokens(chars: Int) -> Int { (chars * 2 + 6) / 7 }

    /// A part's size in Unicode scalars (never `Character`s or bytes).
    static func chars(of part: ChatRequest.Part) -> Int {
        switch part {
        case .text(let t): t.unicodeScalars.count
        case .fileText(_, let t): t.unicodeScalars.count
        case .image, .pdf: binaryPartChars
        }
    }

    /// The oldest messages a long chat leaves out for a small model (`reference.py` `trim_history`).
    /// Cloud models are never trimmed. Otherwise, while the system prompt and the messages are over the
    /// input budget (the context minus a quarter for the reply) and more than one message remains, the two
    /// oldest go: a user message and its answer. With exactly two left, only the older goes (`min(2, remaining - 1)`).
    /// The system prompt and the latest message always stay.
    static func trimHistory(turnChars: [Int], systemChars: Int, placement: AIPlacement,
                            contextTokens: Int?) -> HistoryTrim {
        guard placement != .cloud else { return HistoryTrim(dropped: 0, notice: nil) }
        let context = contextTokens ?? AICatalog.Limits.defaultLocalContextTokens
        let budget = context - context / reservedOutputDivisor
        var total = systemChars + turnChars.reduce(0, +)
        var dropped = 0
        while estimatedTokens(chars: total) > budget, turnChars.count - dropped > 1 {
            let step = min(2, turnChars.count - dropped - 1)
            total -= turnChars[dropped..<(dropped + step)].reduce(0, +)
            dropped += step
        }
        return HistoryTrim(dropped: dropped, notice: dropped > 0 ? historyNotice : nil)
    }

    static func trimHistory(messages: [ChatRequest.Message], system: String, placement: AIPlacement,
                            contextTokens: Int?) -> HistoryTrim {
        trimHistory(turnChars: messages.map { $0.parts.reduce(0) { $0 + chars(of: $1) } },
                    systemChars: system.unicodeScalars.count, placement: placement, contextTokens: contextTokens)
    }

    private static func string(_ scalars: ArraySlice<Unicode.Scalar>) -> String {
        var view = String.UnicodeScalarView()
        view.append(contentsOf: scalars)
        return String(view)
    }
}
```

Run: `bash scripts/test-ai-budget.sh`
Expected: all 13 `budget-cases.json` cases (including `odd context floors, never rounds up` and `a lone CR is not a line end`) and their text-length checks `✓`, the `cut` lines `✓`, `✓ rule constants` and the twelve `history-cases.json` cases (including the two-turn one: `dropped: 1`) `✓`, then `All tests passed.`

Then break each rule once, run the script and restore it:
- `charBudget` with `Int((Double($0) * 1.75).rounded())`: `✗ odd context floors, never rounds up` and `✗ floor(ctx × 7 / 4)`;
- end a line at `"\r"` too in `cut` (`where s == "\n" || s == "\r"`): `✗ a lone CR is not a line end` and `✗ CRLF lines are counted at the LF`;
- in `trimHistory`, `let step = 2`: `✗ two turns over budget: only the oldest goes`; and `turnChars.count - dropped > 2` in the loop condition: the same line again.

- [ ] **Step 4: Write the failing attachment test `tests/AIAttachmentTests.swift`**

The test also:
- pins Review Focus 5: it encrypts the generated text PDF with PDFKit and expects a rejection;
- makes a HEIC copy of `photo.png` with ImageIO and expects JPEG out. It skips with a note on a machine without a HEIC encoder.

```swift
import Foundation
import ImageIO
import PDFKit

@main
@MainActor
enum AIAttachmentTests {
    static func main() {
        let dir = URL(fileURLWithPath: CommandLine.arguments[1])
        attachmentCases(dir)
        lockedPDF(dir)
        heic(dir)
        readOnce(dir)
        plan(dir)
        html()
        T.finish()
    }

    static func attachmentCases(_ dir: URL) {
        T.section("attachment-cases.json")
        for c in T.fixture("attachment-cases.json")["cases"] as! [[String: Any]] {
            let file = c["file"] as! String
            let kind = c["kind"] as! String
            switch AttachmentExtractor.prepare(url: dir.appendingPathComponent(file)) {
            case .failure(let reason):
                T.check("\(file) → \(kind)", "rejected \(reason.rawValue)", "rejected \(c["reason"] as? String ?? "?")")
            case .success(let prepared):
                T.check("\(file) → \(kind)", prepared.kind.rawValue, kind)
                for needle in c["contains"] as? [String] ?? [] {
                    T.checkTrue("\(file) contains \"\(needle)\"", prepared.text?.contains(needle) == true)
                }
                for needle in c["notContains"] as? [String] ?? [] {
                    T.checkTrue("\(file) leaves out \"\(needle)\"", prepared.text?.contains(needle) == false)
                }
                if let mime = c["mime"] as? String { T.check("\(file) mime", prepared.mime, mime) }
            }
        }
    }

    /// Bank statements are often password-protected: rejected, not sent half-read.
    static func lockedPDF(_ dir: URL) {
        T.section("Locked PDF")
        let doc = PDFDocument(url: dir.appendingPathComponent("text.pdf"))!
        let locked = dir.appendingPathComponent("locked.pdf")
        doc.write(to: locked, withOptions: [.userPasswordOption: "secret", .ownerPasswordOption: "secret"])
        let result = AttachmentExtractor.prepare(url: locked)
        T.checkTrue("a password-protected PDF is rejected", result == .failure(.type))
    }

    /// iPhone photos are HEIC: they reach the APIs as JPEG.
    static func heic(_ dir: URL) {
        T.section("HEIC")
        let png = try! Data(contentsOf: dir.appendingPathComponent("photo.png"))
        let heicURL = dir.appendingPathComponent("photo.heic")
        guard let image = AttachmentExtractor.cgImage(png),
              let destination = CGImageDestinationCreateWithURL(heicURL as CFURL, "public.heic" as CFString, 1, nil) else {
            print("  · no HEIC encoder on this machine, skipped")
            return
        }
        CGImageDestinationAddImage(destination, image, nil)
        guard CGImageDestinationFinalize(destination) else { print("  · no HEIC encoder on this machine, skipped"); return }
        let prepared = try? AttachmentExtractor.prepare(url: heicURL).get()
        T.check("HEIC is sent as JPEG", prepared?.mime, "image/jpeg")
        T.check("with JPEG bytes", prepared?.data?.prefix(2).map { $0 }, [0xFF, 0xD8])
    }

    /// A dropped file is read once, at the drop. If its inbox copy is cleaned up afterwards, the messages
    /// that follow still carry the file: nothing opens it again.
    static func readOnce(_ dir: URL) {
        T.section("A prepared file is read once")
        let copy = dir.appendingPathComponent("inbox-copy.txt")
        try! "Shrimpy's notes".write(to: copy, atomically: true, encoding: .utf8)
        let prepared = try! AttachmentExtractor.prepare(url: copy).get()
        try! FileManager.default.removeItem(at: copy)
        for message in 1...3 {
            let parts = AttachmentPlan.parts(for: prepared, api: .openaiChat, vision: false, placement: .local,
                                             contextTokens: nil).parts
            T.check("message \(message) still gets the file after the original is gone", parts,
                    [.fileText(name: "inbox-copy.txt", text: "Shrimpy's notes")])
        }
        T.checkTrue("opening the missing file again fails cleanly", AttachmentExtractor.prepare(url: copy) == .failure(.type))
    }

    static func describe(_ parts: [ChatRequest.Part]) -> [String] {
        parts.map {
            switch $0 {
            case .text: "text"
            case .fileText: "fileText"
            case .image(let mime, _): "image \(mime)"
            case .pdf: "pdf"
            }
        }
    }

    static func plan(_ dir: URL) {
        T.section("AttachmentPlan (spec §3 table)")
        let pdf = try! AttachmentExtractor.prepare(url: dir.appendingPathComponent("text.pdf")).get()
        let scan = try! AttachmentExtractor.prepare(url: dir.appendingPathComponent("scan.pdf")).get()
        let png = try! AttachmentExtractor.prepare(url: dir.appendingPathComponent("photo.png")).get()
        func p(_ f: PreparedFile, _ api: AIProviderAPI, vision: Bool, _ placement: AIPlacement = .local) -> [String] {
            describe(AttachmentPlan.parts(for: f, api: api, vision: vision, placement: placement, contextTokens: nil).parts)
        }
        T.check("text PDF → Anthropic native", p(pdf, .anthropic, vision: true, .cloud), ["pdf"])
        T.check("text PDF → OpenAI native", p(pdf, .openaiResponses, vision: true, .cloud), ["pdf"])
        T.check("text PDF → Google text", p(pdf, .openaiChat, vision: true, .cloud), ["fileText"])
        T.check("text PDF → local text", p(pdf, .openaiChat, vision: false), ["fileText"])
        T.check("scanned PDF → vision local gets pages", p(scan, .openaiChat, vision: true), ["text", "image image/png"])
        T.check("scanned PDF → text-only local gets OCR", p(scan, .openaiChat, vision: false), ["fileText"])
        T.check("scanned PDF → Anthropic native", p(scan, .anthropic, vision: true, .cloud), ["pdf"])
        T.check("image → vision model", p(png, .openaiChat, vision: true), ["text", "image image/png"])
        T.check("image → Apple gets OCR text", p(png, .apple, vision: false), ["fileText"])
        let heic = PreparedFile(name: "x.heic", kind: .image, mime: "image/heic", data: Data([1]), text: "words")
        T.check("an unconverted HEIC never reaches Anthropic", p(heic, .anthropic, vision: true, .cloud), ["fileText"])

        let long = PreparedFile(name: "long.txt", kind: .text,
                                text: String(repeating: String(repeating: "a", count: 9) + "\n", count: 1000))
        let cut = AttachmentPlan.parts(for: long, api: .openaiChat, vision: false, placement: .local, contextTokens: nil)
        T.check("long text is cut with a notice", cut.notice, "I read the first 716 lines.")
        if case .fileText(_, let body) = cut.parts.first {
            T.checkTrue("the model is told too", body.hasSuffix("(I read the first 716 lines.)"))
        } else {
            T.checkTrue("long text gives a fileText part", false)
        }
    }

    static func html() {
        T.section("AttachmentRules.htmlToText")
        T.check("entities and blocks", AttachmentRules.htmlToText("<p>Tom&nbsp;&amp;&#32;Jerry</p><p>&#x1F431;</p>"),
                "Tom & Jerry 🐱")
        T.check("inline tags join words", AttachmentRules.htmlToText("N<b>otch</b>Meow"), "NotchMeow")
        T.check("comments dropped", AttachmentRules.htmlToText("a<!-- secret -->b"), "a b")
    }
}
```

- [ ] **Step 5: Write `scripts/test-ai-attachments.sh`**

```bash
#!/usr/bin/env bash
# AI attachments: every case in attachment-cases.json (files generated, never committed),
# the per-provider plan of spec §3, and the HTML tag strip. Uses PDFKit, Vision and AppKit.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-ai-attachments.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs
python3 tests/fixtures/ai/make_attachments.py "$TEST_DIR/files"
swiftc -swift-version 6 \
    NotchBuddy/Sources/App/AI/Core/*.swift \
    NotchBuddy/Sources/App/AI/Platform/AttachmentExtractor.swift \
    NotchBuddy/Sources/App/AppLog.swift \
    tests/AITestSupport.swift tests/AIAttachmentTests.swift \
    -o "$TEST_DIR/ai-attachment-tests"
"$TEST_DIR/ai-attachment-tests" "$TEST_DIR/files"
```

Run: `chmod +x scripts/test-ai-attachments.sh && bash scripts/test-ai-attachments.sh`
Expected: FAIL with `error: error opening input file 'NotchBuddy/Sources/App/AI/Platform/AttachmentExtractor.swift' (No such file or directory)`.

- [ ] **Step 6: Write `NotchBuddy/Sources/App/AI/Core/Attachments.swift`**

The classification rules follow `reference.py` `classify_file`, in order: size; the lowercased extension; then the first 8 KB must be UTF-8 without a NUL byte. HTML uses a tag strip rather than `NSAttributedString`, whose WebKit importer can fetch remote resources; the strip also matches the Windows build and the contract's whitespace rule. The plan is the spec §3 table. Anthropic and OpenAI get any PDF natively, since both read page images.

```swift
import Foundation

// MARK: - Kinds

/// Exact kinds from `attachment-cases.json` (`pdf` is refined into text or scanned by PDFKit).
enum AttachmentKind: String, Sendable, Equatable {
    case text, image, docx, rtf, html
    case pdfText = "pdf_text"
    case pdfScanned = "pdf_scanned"
}

enum AttachmentRejection: String, Error, Sendable, Equatable {
    case size, type
}

/// A dropped file, read once and ready to be turned into parts for any provider.
struct PreparedFile: Sendable, Equatable {
    let name: String
    let kind: AttachmentKind
    var mime: String = "text/plain"
    /// Original bytes, for PDFs and images.
    var data: Data? = nil
    /// The text: file text, extracted PDF/docx/rtf/html text, or OCR of an image or scanned PDF.
    var text: String? = nil
    /// First pages of a scanned PDF, as PNG.
    var pageImages: [Data] = []
}

// MARK: - Classification (reference.py classify_file)

enum AttachmentRules {
    static let rejectExtensions: Set<String> = ["zip", "gz", "tar", "7z", "rar", "dmg", "iso", "pkg", "msi",
                                                "exe", "app", "mov", "mp4", "mkv", "avi"]
    static let imageMIME: [String: String] = ["png": "image/png", "jpg": "image/jpeg", "jpeg": "image/jpeg",
                                              "gif": "image/gif", "webp": "image/webp", "heic": "image/heic"]

    /// Before PDFKit: `pdf` is not yet split into text and scanned.
    enum Coarse: Sendable, Equatable {
        case text, pdf, docx, rtf, html
        case image(mime: String)
    }

    static func classify(url: URL) -> Result<Coarse, AttachmentRejection> {
        let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        var head = Data()
        if size <= AICatalog.Limits.maxFileBytes, let handle = try? FileHandle(forReadingFrom: url) {
            head = (try? handle.read(upToCount: 8192)) ?? Data()
            try? handle.close()
        }
        return classify(size: size, ext: url.pathExtension, head: head)
    }

    /// Rules in order: size; extension (lowercased); otherwise the first 8 KB must be UTF-8 without NUL.
    static func classify(size: Int, ext: String, head: Data) -> Result<Coarse, AttachmentRejection> {
        if size > AICatalog.Limits.maxFileBytes { return .failure(.size) }
        let e = ext.lowercased()
        switch e {
        case "pdf": return .success(.pdf)
        case "docx": return .success(.docx)
        case "rtf": return .success(.rtf)
        case "html", "htm": return .success(.html)
        default: break
        }
        if let mime = imageMIME[e] { return .success(.image(mime: mime)) }
        if rejectExtensions.contains(e) || head.contains(0) { return .failure(.type) }
        // A multi-byte character cut by the 8 KB read is fine: an error in the last 3 bytes is allowed.
        let valid = (0...min(3, head.count)).contains { String(data: head.dropLast($0), encoding: .utf8) != nil }
        return valid ? .success(.text) : .failure(.type)
    }

    /// Tag strip: drops script/style/comments, keeps block breaks as spaces, decodes entities,
    /// collapses whitespace runs to single spaces. No WebKit, so no network.
    static func htmlToText(_ html: String) -> String {
        var s = html
        let rules: [(String, String)] = [
            ("(?is)<(script|style)\\b[^>]*>.*?</\\1\\s*>", " "),
            ("(?s)<!--.*?-->", " "),
            ("(?i)</?(p|div|br|li|ul|ol|tr|td|th|table|h[1-6]|section|article|header|footer|blockquote|pre)\\b[^>]*>", " "),
            ("<[^>]+>", ""),
        ]
        for (pattern, template) in rules {
            let re = try! NSRegularExpression(pattern: pattern)
            s = re.stringByReplacingMatches(in: s, range: NSRange(s.startIndex..., in: s), withTemplate: template)
        }
        s = decodeEntities(s)
        return s.split(whereSeparator: { $0.isWhitespace }).joined(separator: " ")
    }

    private static func decodeEntities(_ text: String) -> String {
        var s = text
        for (entity, char) in [("&nbsp;", " "), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'"), ("&apos;", "'")] {
            s = s.replacingOccurrences(of: entity, with: char)
        }
        let numeric = try! NSRegularExpression(pattern: "&#(x?)([0-9a-fA-F]+);")
        for m in numeric.matches(in: s, range: NSRange(s.startIndex..., in: s)).reversed() {
            let hex = (s as NSString).substring(with: m.range(at: 1)) == "x"
            let digits = (s as NSString).substring(with: m.range(at: 2))
            if let v = UInt32(digits, radix: hex ? 16 : 10), let scalar = Unicode.Scalar(v),
               let r = Range(m.range, in: s) {
                s.replaceSubrange(r, with: String(Character(scalar)))
            }
        }
        return s.replacingOccurrences(of: "&amp;", with: "&")
    }
}

// MARK: - What each provider receives (spec §3)

enum AttachmentPlan {
    /// Image types every vision API accepts (HEIC is converted to JPEG when the file is read).
    static let sendableImageTypes: Set<String> = ["image/png", "image/jpeg", "image/gif", "image/webp"]

    /// The parts for one file and one model, plus the truncation notice shown to the user.
    /// Anthropic and OpenAI read PDFs natively (both see page images); other vision models get
    /// images; everything else gets text cut to the model's budget.
    static func parts(for file: PreparedFile, api: AIProviderAPI, vision: Bool,
                      placement: AIPlacement, contextTokens: Int?) -> (parts: [ChatRequest.Part], notice: String?) {
        let nativePDF = vision && (api == .anthropic || api == .openaiResponses)
        func text(_ t: String?) -> ([ChatRequest.Part], String?) {
            let cut = ContextBudget.cut(t ?? "", placement: placement, contextTokens: contextTokens)
            let body = cut.notice.map { "\(cut.text)\n\n(\($0))" } ?? cut.text
            return ([.fileText(name: file.name, text: body)], cut.notice)
        }
        switch file.kind {
        case .text, .docx, .rtf, .html:
            return text(file.text)
        case .pdfText:
            if nativePDF, let data = file.data { return ([.pdf(name: file.name, data: data)], nil) }
            return text(file.text)
        case .pdfScanned:
            if nativePDF, let data = file.data { return ([.pdf(name: file.name, data: data)], nil) }
            if vision, !file.pageImages.isEmpty {
                return ([.text("File: \(file.name)")] + file.pageImages.map { .image(mime: "image/png", data: $0) }, nil)
            }
            return text(file.text)
        case .image:
            if vision, let data = file.data, sendableImageTypes.contains(file.mime) {
                return ([.text("File: \(file.name)"), .image(mime: file.mime, data: data)], nil)
            }
            return text(file.text)
        }
    }
}
```

- [ ] **Step 7: Write `NotchBuddy/Sources/App/AI/Platform/AttachmentExtractor.swift`**

```swift
import AppKit
import Foundation
import ImageIO
import PDFKit
import Vision

/// Reads a dropped file once: text, PDF text layer or page images, docx/rtf text, image OCR.
/// Synchronous and slow on big files: call it off the main thread.
enum AttachmentExtractor {
    static let maxPDFPagesAsImages = 3
    /// Long edge for rendered pages, as recommended for Claude vision input.
    static let pageImageLongEdge: CGFloat = 1568

    static func prepare(url: URL) -> Result<PreparedFile, AttachmentRejection> {
        let name = url.lastPathComponent
        switch AttachmentRules.classify(url: url) {
        case .failure(let reason):
            return .failure(reason)
        case .success(.text):
            guard let data = try? Data(contentsOf: url) else { return .failure(.type) }
            return .success(PreparedFile(name: name, kind: .text, text: String(decoding: data, as: UTF8.self)))
        case .success(.html):
            guard let data = try? Data(contentsOf: url) else { return .failure(.type) }
            return .success(PreparedFile(name: name, kind: .html,
                                         text: AttachmentRules.htmlToText(String(decoding: data, as: UTF8.self))))
        case .success(.docx):
            return documentText(url: url, type: .officeOpenXML).map {
                .success(PreparedFile(name: name, kind: .docx, text: $0))
            } ?? .failure(.type)
        case .success(.rtf):
            return documentText(url: url, type: .rtf).map {
                .success(PreparedFile(name: name, kind: .rtf, text: $0))
            } ?? .failure(.type)
        case .success(.pdf):
            // A password-protected PDF can't be read here, and the APIs refuse it too.
            guard let data = try? Data(contentsOf: url), let doc = PDFDocument(data: data), !doc.isLocked else {
                return .failure(.type)
            }
            let layer = (doc.string ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            if !layer.isEmpty {
                return .success(PreparedFile(name: name, kind: .pdfText, mime: "application/pdf", data: data, text: layer))
            }
            let pages = renderPages(doc)
            let ocr = pages.compactMap { NSImage(data: $0)?.cgImage(forProposedRect: nil, context: nil, hints: nil) }
                .map(recognizeText).joined(separator: "\n")
            return .success(PreparedFile(name: name, kind: .pdfScanned, mime: "application/pdf", data: data,
                                         text: ocr, pageImages: pages))
        case .success(.image(let mime)):
            guard let data = try? Data(contentsOf: url), let cg = cgImage(data) else { return .failure(.type) }
            // Anthropic and OpenAI don't take HEIC: re-encode it as JPEG. If that fails, no image goes
            // out and models get the recognised text instead.
            if mime == "image/heic" {
                return .success(PreparedFile(name: name, kind: .image, mime: "image/jpeg", data: jpeg(cg),
                                             text: recognizeText(cg)))
            }
            return .success(PreparedFile(name: name, kind: .image, mime: mime, data: data, text: recognizeText(cg)))
        }
    }

    /// docx / rtf through the system importer (no network for these formats).
    static func documentText(url: URL, type: NSAttributedString.DocumentType) -> String? {
        guard let attributed = try? NSAttributedString(url: url, options: [.documentType: type],
                                                       documentAttributes: nil) else { return nil }
        return attributed.string
    }

    /// The first pages as PNG, long edge at most 1,568 px.
    static func renderPages(_ doc: PDFDocument) -> [Data] {
        (0..<min(doc.pageCount, maxPDFPagesAsImages)).compactMap { index in
            guard let page = doc.page(at: index) else { return nil }
            let bounds = page.bounds(for: .mediaBox)
            let scale = min(pageImageLongEdge / max(bounds.width, bounds.height, 1), 4)
            let image = page.thumbnail(of: NSSize(width: bounds.width * scale, height: bounds.height * scale), for: .mediaBox)
            guard let cg = image.cgImage(forProposedRect: nil, context: nil, hints: nil) else { return nil }
            return NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:])
        }
    }

    /// On-device text recognition (Vision). Empty when nothing readable.
    static func recognizeText(_ image: CGImage) -> String {
        let request = VNRecognizeTextRequest()
        request.recognitionLevel = .accurate
        request.usesLanguageCorrection = true
        try? VNImageRequestHandler(cgImage: image).perform([request])
        return (request.results ?? []).compactMap { $0.topCandidates(1).first?.string }.joined(separator: "\n")
    }

    /// First frame of any image ImageIO reads (PNG, JPEG, GIF, WebP, HEIC).
    static func cgImage(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }

    /// JPEG through ImageIO (quality 0.85).
    static func jpeg(_ image: CGImage) -> Data? {
        let out = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(out as CFMutableData, "public.jpeg" as CFString, 1, nil)
        else { return nil }
        CGImageDestinationAddImage(destination, image, [kCGImageDestinationLossyCompressionQuality: 0.85] as CFDictionary)
        return CGImageDestinationFinalize(destination) ? out as Data : nil
    }
}
```

- [ ] **Step 8: Run the attachment tests**

Run: `bash scripts/test-ai-attachments.sh`
Expected:
- all 15 `attachment-cases.json` cases `✓` (`text.pdf → pdf_text`, `scan.pdf → pdf_scanned`, `big.txt → rejected`);
- `✓ a password-protected PDF is rejected`;
- `✓ HEIC is sent as JPEG` and `✓ with JPEG bytes`, and `✓ an unconverted HEIC never reaches Anthropic`;
- `✓ message 3 still gets the file after the original is gone`;
- every `AttachmentPlan` and `htmlToText` line `✓`, then `All tests passed.`

- [ ] **Step 9: Add the CI steps**

In `.github/workflows/build.yml`, insert this step immediately before `- name: Test plan gauge` (after any `AI …` steps added by earlier tasks), at the same indentation:

```yaml
      - name: AI context budget
        run: bash scripts/test-ai-budget.sh
```

Then, right after it:

```yaml
      - name: AI attachments
        run: bash scripts/test-ai-attachments.sh
```

- [ ] **Step 10: Build the app**

Run: `cd NotchBuddy && xcodegen && xcodebuild -project NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug build 2>&1 | grep -E "error:|BUILD" ; cd ..`
Expected: `** BUILD SUCCEEDED **` and no `error:` line. New files under `Sources/` are picked up by `xcodegen`.

- [ ] **Step 11: Commit**

```bash
git add NotchBuddy/Sources/App/AI/Core/ContextBudget.swift \
    NotchBuddy/Sources/App/AI/Core/Attachments.swift \
    NotchBuddy/Sources/App/AI/Platform/AttachmentExtractor.swift \
    tests/AIBudgetTests.swift \
    tests/AIAttachmentTests.swift \
    scripts/test-ai-budget.sh \
    scripts/test-ai-attachments.sh \
    .github/workflows/build.yml \
    NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -m "feat(ai): size file text to the model and read every file type

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---
### Task 5: HTTP transport, log policy, Debug override and the OpenAI-compatible provider

**Files:**
- Create: `NotchBuddy/Sources/App/AI/Core/AILog.swift`
- Create: `NotchBuddy/Sources/App/AI/Core/HTTPStream.swift`
- Create: `NotchBuddy/Sources/App/AI/Core/OpenAICompatibleProvider.swift`
- Create: `tests/AIProviderTests.swift` (OpenAI-compatible and endpoint sections; Tasks 6–7 add Anthropic and OpenAI)
- Create: `scripts/test-ai-providers.sh`
- Modify: `.github/workflows/build.yml`

**Interfaces:**
- Consumes: Tasks 1–4; `FakeServer` and `closedPort()` (Task 1); `tests/fake_local_llm.py` (E1-0 Task 6).
- Produces:
  - `AILog.Event` (`request`, `reply`, `failure`, `fallback`, `discovery`, `attachment`, `rejected`), `AILog.record(_:)`, `AILog.line(_:)`;
  - `AILog.sink: AILogSink` with `replace(_:)`, which tests use to capture or silence lines;
  - `protocol RedactsSecrets` (`redactedSummary`; supplies `description`, `debugDescription` and `customMirror`; `keyMark(_:)`).
- Produces:
  - `AIURL.normalise(_:)`, which also drops `user:password@`, and `AIURL.cloudOverride(_ environment:) -> String?` (Debug only);
  - `StreamDeadlines {headers, firstToken}` with `.cloud` (10 s / 30 s) and `.local` (60 s / 60 s; the 5 s connect check is the preflight);
  - `HTTPStream.idleTimeout` (120 s), `HTTPStream.run(_:parser:provider:deadlines:session:)`, `HTTPStream.json(_:session:)`, `HTTPStream.post(_:body:headers:timeout:)`.
- Produces:
  - `OpenAICompatibleProvider {id, displayName, placement, baseURL, chatPath, modelsPath, apiKey?, session, deadlines?}`;
  - its `make(_:baseURL:name:placement:apiKey:session:)`, `modelDetails(_:) async -> ModelInfo?`, `prewarm(model:)`;
  - static `body(for:)`, `plainText(_:)` and `jsonObject(_:)`.

- [ ] **Step 1: Write the failing test `tests/AIProviderTests.swift`**

It runs the fake server with each failure mode. It also checks:
- Review Focus 3: a deleted model → `bad_request` 404;
- that a hostile model ID stays on one log line;
- that a key never shows in `description`, `debugDescription` or `dump()`;
- that credentials are stripped from server URLs.

```swift
import Foundation

/// Serves the bytes in `body` for any request, so a test chooses the exact bytes of an SSE stream.
final class StubProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var body = Data()
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        let response = HTTPURLResponse(url: request.url!, statusCode: 200, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "text/event-stream"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.body)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

@main
@MainActor
enum AIProviderTests {
    static func main() async {
        AILog.sink.replace { _ in }  // these tests don't read the AI log lines
        await openAICompatible()
        await lineEnds()
        endpoints()
        T.finish()
    }

    struct Result {
        var reply: ReplyAccumulator
        var error: AIError?
    }

    static func collect(_ stream: AsyncThrowingStream<ChatChunk, Error>, stripsThink: Bool = false) async -> Result {
        var acc = ReplyAccumulator(stripsThinkBlocks: stripsThink)
        do {
            for try await chunk in stream { acc.add(chunk) }
            return Result(reply: acc, error: nil)
        } catch {
            return Result(reply: acc, error: error as? AIError)
        }
    }

    static func request(_ model: String, _ text: String = "hello", tools: Bool = false) -> ChatRequest {
        var r = ChatRequest(model: model, system: "You are Shrimpy.",
                            messages: [.init(role: .user, parts: [.text(text)])])
        if tools {
            r.tools = [.init(name: "get_status", description: "Agent status",
                             parametersJSON: Data(#"{"type":"object","properties":{}}"#.utf8))]
        }
        return r
    }

    static func lastBody(_ server: FakeServer) -> [String: Any] {
        server.requests().last { $0["method"] as? String == "POST" }?["body"] as? [String: Any] ?? [:]
    }

    // MARK: - OpenAI-compatible

    static func local(_ server: FakeServer, _ provider: AIProviderID = .ollama) -> OpenAICompatibleProvider {
        OpenAICompatibleProvider.make(provider, baseURL: server.base)
    }

    static func openAICompatible() async {
        T.section("OpenAICompatibleProvider (fake server)")
        let s = FakeServer()
        let ok = await collect(local(s).stream(request("llama3.2")), stripsThink: true)
        T.check("streams and hides <think>", ok.reply.text.hasPrefix("## Answer"), true)
        T.check("no error", ok.error, nil)
        let body = lastBody(s)
        T.check("sends max_tokens (the local cap)", body["max_tokens"] as? Int, AICatalog.maxOutputTokens(for: .local))
        T.check("never max_completion_tokens", body["max_completion_tokens"] == nil, true)
        T.check("never tool_choice", body["tool_choice"] == nil, true)
        T.check("streams", body["stream"] as? Bool, true)
        T.check("system first", (body["messages"] as? [[String: Any]])?.first?["role"] as? String, "system")
        T.check("checks the server first", s.requests().first?["path"] as? String, "/v1/models")

        let tools = await collect(local(s).stream(request("llama3.2", tools: true)))
        T.check("tool call assembled", tools.reply.toolCalls.first?.arguments, #"{"agent":"claude"}"#)
        T.check("tool body uses function wrapper",
                ((lastBody(s)["tools"] as? [[String: Any]])?.first?["function"] as? [String: Any])?["name"] as? String,
                "get_status")

        var withImage = request("llava")
        withImage.messages[0].parts = [.text("What is this?"), .image(mime: "image/png", data: Data([1, 2, 3]))]
        _ = await collect(local(s).stream(withImage))
        let content = (lastBody(s)["messages"] as? [[String: Any]])?.last?["content"] as? [[String: Any]]
        T.check("image goes as a data URL",
                (content?.last?["image_url"] as? [String: Any])?["url"] as? String, "data:image/png;base64,AQID")

        let missing = await collect(local(s).stream(request("unknown-model")))
        T.check("a deleted model → bad_request 404", "\(missing.error?.kind.rawValue ?? "nil") \(missing.error?.status ?? 0)",
                "bad_request 404")

        let models = (try? await local(s).listModels()) ?? []
        T.check("model list drops embeddings", models.map(\.id), ["llama3.2"])
        s.stop()

        for (flag, kind) in [("500", AIErrorKind.server), ("429", .rateLimited), ("401", .auth), ("billing", .billing)] {
            let f = FakeServer(["--fail", flag])
            let r = await collect(local(f).stream(request("llama3.2")))
            T.check("--fail \(flag) → \(kind.rawValue)", r.error?.kind, kind)
            if flag == "429" { T.check("Retry-After read", r.error?.retryAfter, 2) }
            f.stop()
        }

        let cut = FakeServer(["--fail", "cut"])
        let partial = await collect(local(cut).stream(request("llama3.2")), stripsThink: true)
        T.check("cut stream → interrupted", partial.error?.kind, .interrupted)
        cut.stop()

        let slow = FakeServer(["--fail", "slow-first-token", "--delay", "3"])
        var slowProvider = local(slow)
        slowProvider.deadlines = StreamDeadlines(headers: 1, firstToken: 1)
        T.check("no first token in time → timeout", await collect(slowProvider.stream(request("llama3.2"))).error?.kind, .timeout)
        slow.stop()

        let hang = FakeServer(["--fail", "timeout", "--delay", "3"])
        var hangProvider = local(hang)
        hangProvider.deadlines = StreamDeadlines(headers: 1, firstToken: 2)
        T.check("no headers in time → timeout", await collect(hangProvider.stream(request("llama3.2"))).error?.kind, .timeout)
        hang.stop()

        let nobody = OpenAICompatibleProvider.make(.lmstudio, baseURL: "http://127.0.0.1:\(closedPort())")
        T.check("nothing listening → unreachable", await collect(nobody.stream(request("x"))).error?.kind, .unreachable)

        let ollama = FakeServer(["--persona", "ollama"])
        await local(ollama).prewarm(model: "qwen3.5:2b")
        let warm = ollama.requests().last
        T.check("prewarm asks Ollama to load the model", warm?["path"] as? String, "/api/generate")
        T.check("prewarm names the model", (warm?["body"] as? [String: Any])?["model"] as? String, "qwen3.5:2b")
        T.check("no native details → nil", await local(ollama).modelDetails("qwen3.5:2b"), nil)
        ollama.stop()
    }

    // MARK: - Lines end at LF only

    /// The real transport (`HTTPStream.run`) fed exact bytes through a stub `URLProtocol`: the fake server can't
    /// send a lone CR or a Unicode separator, and `bytes.lines` would split on all of them.
    static func lineEnds() async {
        T.section("HTTPStream splits lines at LF only")
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [StubProtocol.self]
        let session = URLSession(configuration: config)
        func run(_ sse: String) async -> Result {
            StubProtocol.body = Data(sse.utf8)
            let request = URLRequest(url: URL(string: "http://stub.test/v1/chat/completions")!)
            return await collect(HTTPStream.run(request, parser: OpenAIChatStreamParser(), provider: .ollama,
                                                deadlines: .local, session: session), stripsThink: true)
        }
        func delta(_ text: String) -> String { #"data: {"choices":[{"delta":{"content":"\#(text)"}}]}"# }
        let stop = #"data: {"choices":[{"delta":{},"finish_reason":"stop"}]}"#

        let separators = await run([delta("one\u{2028}two\u{85}three"), stop, "data: [DONE]", ""].joined(separator: "\n"))
        T.check("U+2028 and U+0085 stay inside the line", separators.reply.text, "one\u{2028}two\u{85}three")
        T.check("and the stream ends cleanly", separators.error, nil)

        let crlf = await run([delta("A"), "", stop, "", "data: [DONE]", "", ""].joined(separator: "\r\n"))
        T.check("CRLF line ends work", crlf.reply.text, "A")
        T.check("and the stream ends cleanly (CRLF)", crlf.error, nil)

        let loneCR = await run([": keep\r" + delta("B"), delta("A"), stop, "data: [DONE]", ""].joined(separator: "\n"))
        T.check("a data: line after a lone CR is part of the comment", loneCR.reply.text, "A")

        let noFinalLF = await run([delta("A"), stop, "data: [DONE]"].joined(separator: "\n"))
        T.check("a last line without LF still counts", noFinalLF.error, nil)
    }

    // MARK: - Endpoints

    static func endpoints() {
        T.section("Keys never print")
        let compat = OpenAICompatibleProvider.make(.custom, baseURL: "http://127.0.0.1:1", apiKey: "SECRET-KEY-1")
        T.checkTrue("description", !"\(compat)".contains("SECRET"))
        T.checkTrue("debugDescription", !String(reflecting: compat).contains("SECRET"))
        var dumped = ""
        dump(compat, to: &dumped)
        T.checkTrue("dump", !dumped.contains("SECRET") && dumped.contains("<redacted>"))

        T.section("AILog")
        let line = AILog.line(.request(.custom, model: "evil\nai failure kind=auth", placement: .network))
        T.checkTrue("a hostile model ID stays on one line", !line.contains("\n"))
        T.check("and loses its spaces", line, "ai request provider=custom model=evilaifailurekind=auth placement=network")

        T.section("AIURL")
        T.check("normalise", AIURL.normalise(" http://127.0.0.1:1234/v1/ "), "http://127.0.0.1:1234")
        T.check("credentials are never kept", AIURL.normalise("http://bob:hunter2@studio-pc.local:1234/v1/"),
                "http://studio-pc.local:1234")
        T.check("override read in Debug", AIURL.cloudOverride(["NM_AI_BASE_URL_OVERRIDE": "http://127.0.0.1:9/"]),
                "http://127.0.0.1:9")
        T.check("no override by default", AIURL.cloudOverride([:]), nil)
    }
}
```

- [ ] **Step 2: Write `scripts/test-ai-providers.sh`**

```bash
#!/usr/bin/env bash
# AI providers against tests/fake_local_llm.py: request bodies, streaming, failure modes.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-ai-providers.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs
# -D DEBUG: the Debug-only base-URL override is under test too.
swiftc -swift-version 6 -D DEBUG \
    NotchBuddy/Sources/App/AI/Core/*.swift \
    NotchBuddy/Sources/App/AppLog.swift \
    tests/AITestSupport.swift tests/AIProviderTests.swift \
    -o "$TEST_DIR/ai-provider-tests"
"$TEST_DIR/ai-provider-tests"
```

Run: `chmod +x scripts/test-ai-providers.sh && bash scripts/test-ai-providers.sh`
Expected: FAIL with `error: cannot find 'OpenAICompatibleProvider' in scope`.

- [ ] **Step 3: Write `NotchBuddy/Sources/App/AI/Core/AILog.swift`**

The API only takes IDs, kinds, numbers and codes, so a prompt, file contents, a key or a provider's message can't reach the log. Server-supplied strings are shortened and lose spaces and newlines.

```swift
import Foundation

/// AI events for `~/Library/Logs/NotchMeow/nm.log`. The API only takes IDs, kinds, numbers and
/// codes: there is no way to log a prompt, file contents, a key or a provider's error message.
enum AILog {
    enum Event: Sendable {
        case request(AIProviderID, model: String, placement: AIPlacement)
        case reply(AIProviderID, ms: Int, finish: FinishReason?)
        case failure(AIProviderID, kind: AIErrorKind, status: Int?, code: String?, requestID: String?)
        case fallback(from: AIProviderID, to: AIProviderID, kind: AIErrorKind)
        case discovery(found: [AIProviderID], ms: Int)
        case attachment(kind: AttachmentKind, bytes: Int)
        case rejected(reason: AttachmentRejection, bytes: Int)
    }

    static let sink = AILogSink()

    static func record(_ event: Event) { sink.write(line(event)) }

    static func line(_ event: Event) -> String {
        switch event {
        case .request(let p, let model, let placement):
            return "ai request provider=\(p.rawValue) model=\(short(model, 80)) placement=\(placement.rawValue)"
        case .reply(let p, let ms, let finish):
            return "ai reply provider=\(p.rawValue) ms=\(ms) finish=\(finish?.rawValue ?? "none")"
        case .failure(let p, let kind, let status, let code, let requestID):
            return "ai failure provider=\(p.rawValue) kind=\(kind.rawValue) status=\(status.map(String.init) ?? "-")"
                + " code=\(short(code ?? "-", 64)) request_id=\(short(requestID ?? "-", 128))"
        case .fallback(let from, let to, let kind):
            return "ai fallback from=\(from.rawValue) to=\(to.rawValue) kind=\(kind.rawValue)"
        case .discovery(let found, let ms):
            return "ai discovery found=\(found.map(\.rawValue).joined(separator: ",")) ms=\(ms)"
        case .attachment(let kind, let bytes):
            return "ai attachment kind=\(kind.rawValue) bytes=\(bytes)"
        case .rejected(let reason, let bytes):
            return "ai attachment rejected=\(reason.rawValue) bytes=\(bytes)"
        }
    }

    /// Codes and IDs come from servers: keep them short and on one line.
    private static func short(_ s: String, _ max: Int) -> String {
        let one = s.filter { !$0.isNewline && $0 != " " }
        return one.count > max ? String(one.prefix(max)) + "…" : one
    }
}

/// Where AI log lines go. Tests swap the writer to capture lines.
final class AILogSink: @unchecked Sendable {
    private let lock = NSLock()
    private var writer: @Sendable (String) -> Void = { appendAppLog("nm.log", $0) }

    func write(_ line: String) {
        let w = lock.withLock { writer }
        w(line)
    }

    func replace(_ newWriter: @escaping @Sendable (String) -> Void) {
        lock.withLock { writer = newWriter }
    }
}

/// Types that hold an API key print a summary without it: `description`, `debugDescription`,
/// `dump()` and the debugger all go through `redactedSummary`.
protocol RedactsSecrets: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    var redactedSummary: String { get }
}

extension RedactsSecrets {
    var description: String { redactedSummary }
    var debugDescription: String { redactedSummary }
    var customMirror: Mirror { Mirror(self, children: ["summary": redactedSummary], displayStyle: .struct) }

    /// "none" or "<redacted>", never the key.
    static func keyMark(_ key: String?) -> String { (key ?? "").isEmpty ? "none" : "<redacted>" }
}
```

- [ ] **Step 4: Write `NotchBuddy/Sources/App/AI/Core/HTTPStream.swift`**

A watchdog task cancels the request when the headers or the first token are late, and the error becomes `timeout`. Any content chunk counts as the first token, including `.activity`.

```swift
import Foundation

// MARK: - URLs

enum AIURL {
    /// Removes spaces, `user:password@`, trailing slashes and a trailing /api or /v1 (users paste docs URLs).
    static func normalise(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Credentials never get stored with a server address (a key goes in the Keychain instead).
        if var parts = URLComponents(string: s), parts.user != nil || parts.password != nil {
            parts.user = nil
            parts.password = nil
            s = parts.string ?? s
        }
        while s.hasSuffix("/") { s.removeLast() }
        for suffix in ["/api", "/v1"] where s.hasSuffix(suffix) { s.removeLast(suffix.count) }
        return s
    }

    /// Debug builds only: `NM_AI_BASE_URL_OVERRIDE=http://127.0.0.1:PORT` points the cloud
    /// providers at `tests/fake_local_llm.py`. Compiled out of Release, so a shipped app can't be redirected.
    static func cloudOverride(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        #if DEBUG
        guard let raw = environment["NM_AI_BASE_URL_OVERRIDE"], !raw.isEmpty else { return nil }
        return normalise(raw)
        #else
        return nil
        #endif
    }
}

// MARK: - Deadlines

/// `headers`: until the HTTP status arrives. `firstToken`: until the first output (both from the start).
struct StreamDeadlines: Sendable, Equatable {
    var headers: TimeInterval
    var firstToken: TimeInterval

    static let cloud = StreamDeadlines(headers: AICatalog.Timeouts.connectCloud,
                                       firstToken: AICatalog.Timeouts.firstTokenCloud)
    /// A local server sends its headers only once the model is loaded, so both wait the first-token time;
    /// the 5 s connect check is the reachability preflight in `OpenAICompatibleProvider`.
    static let local = StreamDeadlines(headers: AICatalog.Timeouts.firstTokenLocal,
                                       firstToken: AICatalog.Timeouts.firstTokenLocal)
}

private final class StreamClock: @unchecked Sendable {
    private let lock = NSLock()
    private var headers = false
    private var token = false
    private var fired = false

    func sawHeaders() { lock.withLock { headers = true } }
    func sawToken() { lock.withLock { token = true } }
    var headersSeen: Bool { lock.withLock { headers } }
    var tokenSeen: Bool { lock.withLock { token } }
    func fire() { lock.withLock { fired = true } }
    var timedOut: Bool { lock.withLock { fired } }
}

// MARK: - Transport

enum HTTPStream {
    /// Long idle limit once tokens flow; the deadlines above cover the start.
    static let idleTimeout: TimeInterval = 120

    /// POSTs `request`, maps HTTP errors, then feeds every line to `parser`.
    /// A stream error event or a missing terminal event ends the stream with an `AIError`.
    static func run<P: StreamParser>(_ request: URLRequest, parser: P, provider: AIProviderID,
                                     deadlines: StreamDeadlines,
                                     session: URLSession = .shared) -> AsyncThrowingStream<ChatChunk, Error> {
        AsyncThrowingStream { continuation in
            let clock = StreamClock()
            let started = Date()
            let work = Task {
                var parser = parser
                var requestID: String?
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    clock.sawHeaders()
                    guard let http = response as? HTTPURLResponse else { throw AIError(kind: .unreachable) }
                    let headers = http.allHeaderFields.reduce(into: [String: String]()) {
                        $0["\($1.key)"] = "\($1.value)"
                    }
                    requestID = HTTPErrorRules.header("x-request-id", in: headers)
                        ?? HTTPErrorRules.header("request-id", in: headers)
                    guard http.statusCode == 200 else {
                        var body = Data()
                        for try await byte in bytes {
                            body.append(byte)
                            if body.count > 65_536 { break }
                        }
                        throw HTTPErrorRules.error(status: http.statusCode, body: body, headers: headers)
                    }
                    var finish: FinishReason?
                    // Lines end at LF only (`SSELineSplitter`): `bytes.lines` would also split on a lone CR,
                    // U+2028, U+2029 and U+0085, which the contract keeps inside the line.
                    var splitter = SSELineSplitter()
                    for try await byte in bytes {
                        guard let line = splitter.push(byte) else { continue }
                        for chunk in parser.consume(line: line) {
                            try emit(chunk, clock: clock, continuation: continuation, finish: &finish, requestID: requestID)
                        }
                        if parser.isTerminal { break }
                    }
                    if !parser.isTerminal, let last = splitter.flush() {
                        for chunk in parser.consume(line: last) {
                            try emit(chunk, clock: clock, continuation: continuation, finish: &finish, requestID: requestID)
                        }
                    }
                    for chunk in parser.finish() {
                        try emit(chunk, clock: clock, continuation: continuation, finish: &finish, requestID: requestID)
                    }
                    AILog.record(.reply(provider, ms: Int(Date().timeIntervalSince(started) * 1000), finish: finish))
                    continuation.finish()
                } catch {
                    var failure: AIError
                    if clock.timedOut {
                        failure = AIError(kind: .timeout)
                    } else if let e = error as? AIError {
                        failure = e
                    } else {
                        failure = AIError(kind: HTTPErrorRules.transportKind(error))
                    }
                    if failure.requestID == nil { failure.requestID = requestID }
                    AILog.record(.failure(provider, kind: failure.kind, status: failure.status, code: failure.code,
                                          requestID: failure.requestID))
                    continuation.finish(throwing: failure)
                }
            }
            let watchdog = Task {
                try? await Task.sleep(nanoseconds: UInt64(deadlines.headers * 1_000_000_000))
                if Task.isCancelled { return }
                if !clock.headersSeen { clock.fire(); work.cancel(); return }
                let rest = deadlines.firstToken - deadlines.headers
                if rest > 0 { try? await Task.sleep(nanoseconds: UInt64(rest * 1_000_000_000)) }
                if Task.isCancelled { return }
                if !clock.tokenSeen { clock.fire(); work.cancel() }
            }
            continuation.onTermination = { _ in
                work.cancel()
                watchdog.cancel()
            }
        }
    }

    private static func emit(_ chunk: ChatChunk, clock: StreamClock,
                             continuation: AsyncThrowingStream<ChatChunk, Error>.Continuation,
                             finish: inout FinishReason?, requestID: String?) throws {
        switch chunk {
        case .error(let kind):
            throw AIError(kind: kind, requestID: requestID)
        case .finish(let f):
            finish = f
        case .text(let t) where t.isEmpty:
            return
        default:
            clock.sawToken()
        }
        continuation.yield(chunk)
    }

    /// GET/POST that returns JSON, with the same error mapping.
    static func json(_ request: URLRequest, session: URLSession = .shared) async throws -> Any {
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AIError(kind: HTTPErrorRules.transportKind(error))
        }
        guard let http = response as? HTTPURLResponse else { throw AIError(kind: .unreachable) }
        guard http.statusCode == 200 else {
            let headers = http.allHeaderFields.reduce(into: [String: String]()) { $0["\($1.key)"] = "\($1.value)" }
            throw HTTPErrorRules.error(status: http.statusCode, body: data, headers: headers)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) else { throw AIError(kind: .badRequest) }
        return json
    }

    /// JSON body for a POST. `[String: Any]` never crosses an actor: callers build and encode in one place.
    static func post(_ url: URL, body: [String: Any], headers: [String: String], timeout: TimeInterval) -> URLRequest {
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return req
    }
}
```

- [ ] **Step 5: Write `NotchBuddy/Sources/App/AI/Core/OpenAICompatibleProvider.swift`**

For a local or network server, the provider first sends `GET …/v1/models` with a 5 s timeout. That is the spec's connect timeout. A sleeping LAN host fails fast, and Ollama loading a model, which only sends its headers once loaded, still gets the 60 s first-token wait.

```swift
import Foundation

/// Google's OpenAI-compatible endpoint, Ollama, LM Studio, llama.cpp, Jan and servers the user adds.
/// Sends `max_tokens` (not `max_completion_tokens`) and never `tool_choice`: Ollama ignores both.
struct OpenAICompatibleProvider: ModelProvider {
    let id: AIProviderID
    let displayName: String
    let placement: AIPlacement
    /// Without a trailing slash, e.g. `http://127.0.0.1:11434`.
    let baseURL: String
    var chatPath = "/v1/chat/completions"
    var modelsPath = "/v1/models"
    var apiKey: String? = nil
    var session: URLSession = .shared
    /// nil: `.cloud` or `.local` by placement. Tests shorten them.
    var deadlines: StreamDeadlines? = nil

    /// The catalog's paths for `provider` at `baseURL` (a cloud override keeps the `/v1/...` paths).
    static func make(_ provider: AIProviderID, baseURL: String, name: String? = nil, placement: AIPlacement? = nil,
                     apiKey: String? = nil, session: URLSession = .shared) -> OpenAICompatibleProvider {
        let info = AICatalog.info(provider)
        let usesCatalogBase = baseURL == info.baseURL
        return OpenAICompatibleProvider(
            id: provider, displayName: name ?? info.name,
            placement: placement ?? (provider.isCloud ? .cloud : AICatalog.placement(forHost: URL(string: baseURL)?.host)),
            baseURL: baseURL,
            chatPath: usesCatalogBase ? (info.chatPath ?? "/v1/chat/completions") : "/v1/chat/completions",
            modelsPath: usesCatalogBase ? (info.modelsPath ?? "/v1/models") : "/v1/models",
            apiKey: apiKey, session: session)
    }

    private var authorization: String { "Bearer \(apiKey ?? "ollama")" }

    func listModels() async throws -> [ModelInfo] {
        guard let url = URL(string: baseURL + modelsPath) else { throw AIError(kind: .badRequest) }
        var req = URLRequest(url: url, timeoutInterval: placement == .cloud ? AICatalog.Timeouts.connectCloud
                                                                             : AICatalog.Timeouts.connectLocal)
        req.setValue(authorization, forHTTPHeaderField: "Authorization")
        let json = try await HTTPStream.json(req, session: session)
        let ids = ((json as? [String: Any])?["data"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
        // Gemini models read images; local models are text-only until `modelDetails` says otherwise.
        let vision: Set<AICapability> = id == .google ? [.vision] : []
        return AICatalog.filterModels(ids, for: id).map { ModelInfo(id: $0, capabilities: vision) }
    }

    /// Capabilities and context from the server's native API, when it has one (Ollama, LM Studio).
    func modelDetails(_ model: String) async -> ModelInfo? {
        switch id {
        case .ollama:
            guard let url = URL(string: baseURL + "/api/show") else { return nil }
            let req = HTTPStream.post(url, body: ["model": model], headers: [:], timeout: AICatalog.Timeouts.connectLocal)
            guard let json = try? await HTTPStream.json(req, session: session) as? [String: Any] else { return nil }
            let caps = Set((json["capabilities"] as? [String] ?? []).compactMap { c -> AICapability? in
                c == "vision" ? .vision : (c == "tools" ? .tools : nil)
            })
            return ModelInfo(id: model, capabilities: caps)
        case .lmstudio:
            guard let url = URL(string: baseURL + "/api/v0/models"),
                  let json = try? await HTTPStream.json(URLRequest(url: url, timeoutInterval: AICatalog.Timeouts.connectLocal),
                                                        session: session) as? [String: Any],
                  let row = (json["data"] as? [[String: Any]])?.first(where: { $0["id"] as? String == model })
            else { return nil }
            return ModelInfo(id: model, contextTokens: row["loaded_context_length"] as? Int,
                             capabilities: row["type"] as? String == "vlm" ? [.vision] : [])
        default:
            return nil
        }
    }

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
        guard let url = URL(string: baseURL + chatPath) else {
            return AsyncThrowingStream { $0.finish(throwing: AIError(kind: .badRequest)) }
        }
        AILog.record(.request(id, model: request.model, placement: placement))
        let req = HTTPStream.post(url, body: Self.body(for: request), headers: ["Authorization": authorization],
                                  timeout: HTTPStream.idleTimeout)
        guard placement != .cloud else {
            return HTTPStream.run(req, parser: OpenAIChatStreamParser(), provider: id,
                                  deadlines: deadlines ?? .cloud, session: session)
        }
        // Local and network servers: a 5 s reachability check first (a sleeping LAN host would
        // otherwise hold the chat for the whole first-token wait).
        let preflight = URLRequest(url: URL(string: baseURL + modelsPath)!, timeoutInterval: AICatalog.Timeouts.connectLocal)
        let session = self.session, provider = id, deadlines = self.deadlines ?? .local
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    _ = try await HTTPStream.json(preflight, session: session)
                } catch let e as AIError where e.status != nil {
                    // It answered (even with an error page): reachable.
                } catch {
                    let kind = (error as? AIError)?.kind ?? .unreachable
                    AILog.record(.failure(provider, kind: kind, status: nil, code: nil, requestID: nil))
                    continuation.finish(throwing: AIError(kind: kind))
                    return
                }
                do {
                    for try await chunk in HTTPStream.run(req, parser: OpenAIChatStreamParser(), provider: provider,
                                                          deadlines: deadlines, session: session) {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Ollama loads a model when it gets an empty generate request.
    func prewarm(model: String) async {
        guard id == .ollama, let url = URL(string: baseURL + "/api/generate") else { return }
        let req = HTTPStream.post(url, body: ["model": model], headers: [:], timeout: AICatalog.Timeouts.connectLocal)
        _ = try? await session.data(for: req)
    }

    /// Chat-completions body. Images go as `image_url` data URLs; everything else is text.
    static func body(for r: ChatRequest) -> [String: Any] {
        var messages: [[String: Any]] = [["role": "system", "content": r.system]]
        for m in r.messages {
            let hasImage = m.parts.contains { if case .image = $0 { return true } else { return false } }
            if hasImage {
                messages.append(["role": m.role.rawValue, "content": m.parts.map { part -> [String: Any] in
                    switch part {
                    case .image(let mime, let data):
                        return ["type": "image_url",
                                "image_url": ["url": "data:\(mime);base64,\(data.base64EncodedString())"]]
                    default:
                        return ["type": "text", "text": plainText(part)]
                    }
                }])
            } else {
                messages.append(["role": m.role.rawValue, "content": m.parts.map(plainText).joined(separator: "\n\n")])
            }
        }
        var body: [String: Any] = ["model": r.model, "messages": messages, "stream": true, "max_tokens": r.maxTokens]
        if !r.tools.isEmpty {
            body["tools"] = r.tools.map { tool -> [String: Any] in
                ["type": "function", "function": ["name": tool.name, "description": tool.description,
                                                  "parameters": jsonObject(tool.parametersJSON)]]
            }
        }
        if let format = r.responseFormat {
            body["response_format"] = ["type": "json_schema",
                                       "json_schema": ["name": format.name, "schema": jsonObject(format.schemaJSON), "strict": true]]
        }
        return body
    }

    static func plainText(_ part: ChatRequest.Part) -> String {
        switch part {
        case .text(let t): t
        case .fileText(let name, let text): "File: \(name)\n\n\(text)"
        case .pdf(let name, _): "File: \(name)"
        case .image: ""
        }
    }

    static func jsonObject(_ data: Data) -> Any {
        (try? JSONSerialization.jsonObject(with: data)) ?? [String: Any]()
    }
}

extension OpenAICompatibleProvider: RedactsSecrets {
    var redactedSummary: String { "OpenAICompatibleProvider(\(id.rawValue), \(baseURL), key: \(Self.keyMark(apiKey)))" }
}
```

- [ ] **Step 6: Run the tests**

Run: `bash scripts/test-ai-providers.sh`
Expected:
- every line under `OpenAICompatibleProvider (fake server)`, `HTTPStream splits lines at LF only`, `AILog` and `AIURL` is `✓`, then `All tests passed.`;
- in particular `✓ never tool_choice`, `✓ --fail 429 → rate_limited`, `✓ no first token in time → timeout`, `✓ a deleted model → bad_request 404`, `✓ U+2028 and U+0085 stay inside the line`, `✓ CRLF line ends work`, `✓ a data: line after a lone CR is part of the comment`, the three `Keys never print` lines and `✓ credentials are never kept`.

The run takes about 10 s because of the delay modes.

Then, to see the transport test bite: in `HTTPStream.run`, put back `for try await line in bytes.lines { … }` in place of the `SSELineSplitter` loop and run the script. Expected: `✗ U+2028 and U+0085 stay inside the line` and `✗ a data: line after a lone CR is part of the comment`. Restore the splitter.

- [ ] **Step 7: Add the CI step**

In `.github/workflows/build.yml`, insert this step immediately before `- name: Test plan gauge` (after any `AI …` steps added by earlier tasks), at the same indentation:

```yaml
      - name: AI providers (fake server)
        run: bash scripts/test-ai-providers.sh
```

- [ ] **Step 8: Build the app**

Run: `cd NotchBuddy && xcodegen && xcodebuild -project NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug build 2>&1 | grep -E "error:|BUILD" ; cd ..`
Expected: `** BUILD SUCCEEDED **` and no `error:` line. New files under `Sources/` are picked up by `xcodegen`.

- [ ] **Step 9: Commit**

```bash
git add NotchBuddy/Sources/App/AI/Core/AILog.swift \
    NotchBuddy/Sources/App/AI/Core/HTTPStream.swift \
    NotchBuddy/Sources/App/AI/Core/OpenAICompatibleProvider.swift \
    tests/AIProviderTests.swift \
    scripts/test-ai-providers.sh \
    .github/workflows/build.yml \
    NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -m "feat(ai): stream from OpenAI-compatible servers with deadlines and a content-free log

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---
### Task 6: Anthropic provider (streaming)

**Files:**
- Create: `NotchBuddy/Sources/App/AI/Core/AnthropicProvider.swift`
- Modify: `tests/AIProviderTests.swift`

**Interfaces:**
- Consumes: `AnthropicStreamParser` (Task 3); `HTTPStream`, `AILog`, `OpenAICompatibleProvider.jsonObject` (Task 5).
- Produces: `AnthropicProvider {apiKey, baseURL (default https://api.anthropic.com), session, deadlines}`, plus:
  - `listModels()` (labels from `display_name`);
  - `stream(_:)` with `x-api-key` and `anthropic-version` (no beta header);
  - static `body(for:)`, `version`, and `webSearchTool(model:)`: `{type, name, max_uses}` from `AICatalog.WebSearch`, with the type chosen by `AICatalog.anthropicWebSearchType(model:)` (`web_search_20260209`, or `web_search_20250305` for `claude-haiku-4*` and `claude-3*`), `max_uses` 5;
  - `RedactsSecrets` conformance.
- Mapping: `.pdf` → `document`, `.image` → `image`, `.fileText` → text block "File: name…", tools → `{name, description, input_schema}`, `responseFormat` → `output_config.format` (`json_schema`). With a response format, web search is left out, because citations can't be combined with structured output.

- [ ] **Step 1: Add the failing Anthropic tests**

In `tests/AIProviderTests.swift`, call the new section from `main()` after `await openAICompatible()`:

```swift
        await anthropic()
```

Then add this section before `    // MARK: - Endpoints`:

```swift
    // MARK: - Anthropic

    static func anthropic() async {
        T.section("AnthropicProvider (fake server)")
        let s = FakeServer()
        let claude = AnthropicProvider(apiKey: "test-key", baseURL: s.base)
        var r = request("claude-sonnet-5-5")
        r.webSearch = true
        r.messages[0].parts.insert(.pdf(name: "a.pdf", data: Data("%PDF".utf8)), at: 0)
        let ok = await collect(claude.stream(r))
        T.check("text", ok.reply.text, "Cats sleep a lot.")
        T.check("web search sources", ok.reply.citations, [Citation(url: "https://example.com/cats", title: "Cat sleep facts")])
        let body = lastBody(s)
        T.check("streams", body["stream"] as? Bool, true)
        T.check("system prompt", body["system"] as? String, "You are Shrimpy.")
        let tool = (body["tools"] as? [[String: Any]])?.first
        T.check("catalog web search tool", tool?["type"] as? String, "web_search_20260209")
        T.check("web search max_uses", tool?["max_uses"] as? Int, 5)
        let first = ((body["messages"] as? [[String: Any]])?.first?["content"] as? [[String: Any]])?.first
        T.check("PDF as a document block", first?["type"] as? String, "document")

        var older = request("claude-haiku-4-5-20251001")
        older.webSearch = true
        _ = await collect(claude.stream(older))
        let olderTool = (lastBody(s)["tools"] as? [[String: Any]])?.first
        T.check("an older model gets the legacy search tool", olderTool?["type"] as? String, "web_search_20250305")
        T.check("with the same max_uses", olderTool?["max_uses"] as? Int, 5)

        let tools = await collect(claude.stream(request("claude-sonnet-5-5", tools: true)))
        T.check("client tool call", tools.reply.toolCalls.first?.name, "get_status")
        T.check("tool schema as input_schema",
                (lastBody(s)["tools"] as? [[String: Any]])?.first?["input_schema"] != nil, true)

        let refuse = FakeServer(["--fail", "refuse"])
        let refused = await collect(AnthropicProvider(apiKey: "k", baseURL: refuse.base).stream(request("claude-sonnet-5-5")))
        T.check("refusal finish", refused.reply.finish, .refusal)
        refuse.stop()

        let listed = (try? await claude.listModels())?.map(\.id)
        T.check("model list (?limit=100 reaches the fake)", listed, ["llama3.2", "nomic-embed-text"])
        var dumpedClaude = ""
        dump(claude, to: &dumpedClaude)
        T.checkTrue("the key never prints", !"\(claude)".contains("test-key") && !dumpedClaude.contains("test-key"))
        s.stop()

        for (flag, kind) in [("overloaded", AIErrorKind.overloaded), ("401", .auth), ("cut", .interrupted)] {
            let f = FakeServer(["--fail", flag])
            let result = await collect(AnthropicProvider(apiKey: "k", baseURL: f.base).stream(request("claude-sonnet-5-5")))
            T.check("--fail \(flag) → \(kind.rawValue)", result.error?.kind, kind)
            f.stop()
        }
    }
```

Run: `bash scripts/test-ai-providers.sh`
Expected: FAIL with `error: cannot find 'AnthropicProvider' in scope`.

- [ ] **Step 2: Write `NotchBuddy/Sources/App/AI/Core/AnthropicProvider.swift`**

```swift
import Foundation

/// Claude through the Messages API, streaming, with server-side web search and native PDFs.
struct AnthropicProvider: ModelProvider {
    let id = AIProviderID.anthropic
    let displayName = "Anthropic"
    let placement = AIPlacement.cloud
    let apiKey: String
    var baseURL = AICatalog.info(.anthropic).baseURL!
    var session: URLSession = .shared
    var deadlines: StreamDeadlines = .cloud

    static let version = "2023-06-01"
    /// The catalog's hosted web search (GA, no beta header). Older Claude models take the legacy type.
    static func webSearchTool(model: String) -> [String: Any] {
        ["type": AICatalog.anthropicWebSearchType(model: model), "name": AICatalog.WebSearch.anthropicName,
         "max_uses": AICatalog.WebSearch.anthropicMaxUses]
    }

    private var headers: [String: String] { ["x-api-key": apiKey, "anthropic-version": Self.version] }

    func listModels() async throws -> [ModelInfo] {
        guard let url = URL(string: baseURL + "/v1/models?limit=100") else { throw AIError(kind: .badRequest) }
        var req = URLRequest(url: url, timeoutInterval: AICatalog.Timeouts.connectCloud)
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        let json = try await HTTPStream.json(req, session: session) as? [String: Any]
        return (json?["data"] as? [[String: Any]] ?? []).compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            return ModelInfo(id: id, label: row["display_name"] as? String, capabilities: [.vision, .tools, .json])
        }
    }

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
        AILog.record(.request(id, model: request.model, placement: placement))
        let req = HTTPStream.post(URL(string: baseURL + "/v1/messages")!, body: Self.body(for: request), headers: headers,
                                  timeout: HTTPStream.idleTimeout)
        return HTTPStream.run(req, parser: AnthropicStreamParser(), provider: id, deadlines: deadlines, session: session)
    }

    static func body(for r: ChatRequest) -> [String: Any] {
        let messages: [[String: Any]] = r.messages.map { m in
            ["role": m.role.rawValue, "content": m.parts.map(block)]
        }
        var body: [String: Any] = ["model": r.model, "max_tokens": r.maxTokens, "system": r.system,
                                   "messages": messages, "stream": true]
        var tools: [[String: Any]] = []
        // Web search citations can't be combined with structured output.
        if r.webSearch && r.responseFormat == nil { tools.append(webSearchTool(model: r.model)) }
        tools += r.tools.map {
            ["name": $0.name, "description": $0.description,
             "input_schema": OpenAICompatibleProvider.jsonObject($0.parametersJSON)]
        }
        if !tools.isEmpty { body["tools"] = tools }
        if let format = r.responseFormat {
            body["output_config"] = ["format": ["type": "json_schema",
                                                "schema": OpenAICompatibleProvider.jsonObject(format.schemaJSON)]]
        }
        return body
    }

    private static func block(_ part: ChatRequest.Part) -> [String: Any] {
        switch part {
        case .text(let t):
            return ["type": "text", "text": t]
        case .fileText(let name, let text):
            return ["type": "text", "text": "File: \(name)\n\n\(text)"]
        case .image(let mime, let data):
            return ["type": "image", "source": ["type": "base64", "media_type": mime, "data": data.base64EncodedString()]]
        case .pdf(_, let data):
            return ["type": "document",
                    "source": ["type": "base64", "media_type": "application/pdf", "data": data.base64EncodedString()]]
        }
    }
}

extension AnthropicProvider: RedactsSecrets {
    var redactedSummary: String { "AnthropicProvider(\(baseURL), key: \(Self.keyMark(apiKey)))" }
}
```

- [ ] **Step 3: Run the tests**

Run: `bash scripts/test-ai-providers.sh`
Expected: every `AnthropicProvider (fake server)` line `✓`, including:
- `✓ web search sources` and `✓ catalog web search tool` (`web_search_20260209`), `✓ an older model gets the legacy search tool` (`web_search_20250305`);
- `✓ PDF as a document block`, `✓ model list (?limit=100 reaches the fake)`, `✓ the key never prints`;
- `✓ --fail overloaded → overloaded` and `✓ --fail cut → interrupted`;
- then `All tests passed.`

- [ ] **Step 4: Build the app**

Run: `cd NotchBuddy && xcodegen && xcodebuild -project NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug build 2>&1 | grep -E "error:|BUILD" ; cd ..`
Expected: `** BUILD SUCCEEDED **` and no `error:` line. New files under `Sources/` are picked up by `xcodegen`.

- [ ] **Step 5: Commit**

```bash
git add NotchBuddy/Sources/App/AI/Core/AnthropicProvider.swift \
    tests/AIProviderTests.swift \
    NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -m "feat(ai): stream Claude replies with web search and native PDFs

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---
### Task 7: OpenAI Responses provider

**Files:**
- Create: `NotchBuddy/Sources/App/AI/Core/OpenAIProvider.swift`
- Modify: `tests/AIProviderTests.swift`

**Interfaces:**
- Consumes: `OpenAIResponsesStreamParser` (Task 3); `HTTPStream`, `AILog`, `OpenAICompatibleProvider.plainText` / `jsonObject` (Task 5).
- Produces: `OpenAIProvider {apiKey, baseURL (default https://api.openai.com), session, deadlines}`, plus:
  - `listModels()`: newest first, filtered with `AICatalog.filterModels(_:for: .openai)`;
  - `stream(_:)` to `POST /v1/responses`;
  - static `body(for:)`: `instructions`, `input` (user content as `input_text` / `input_file` / `input_image`; assistant content as a string), `stream: true`, `store: false`, `max_output_tokens`, `tools` (`{"type":"web_search"}` and flat function tools), and `text.format` (JSON schema) for `responseFormat`;
  - `RedactsSecrets` conformance.

- [ ] **Step 1: Add the failing OpenAI tests**

In `tests/AIProviderTests.swift`, call the new section from `main()` after `await anthropic()`:

```swift
        await openAI()
```

Then add this section before `    // MARK: - Endpoints`:

```swift
    // MARK: - OpenAI

    static func openAI() async {
        T.section("OpenAIProvider (fake server)")
        let s = FakeServer()
        let gpt = OpenAIProvider(apiKey: "test-key", baseURL: s.base)
        var r = request("gpt-6.1-sol")
        r.webSearch = true
        r.messages[0].parts.insert(.pdf(name: "a.pdf", data: Data("%PDF".utf8)), at: 0)
        r.messages.append(.init(role: .assistant, parts: [.text("Earlier answer")]))
        r.messages.append(.init(role: .user, parts: [.text("And now?")]))
        let ok = await collect(gpt.stream(r))
        T.check("text", ok.reply.text, "Cats sleep a lot.")
        T.check("url_citation sources", ok.reply.citations.map(\.url), ["https://example.com/cats"])
        T.check("no error without [DONE]", ok.error, nil)
        let body = lastBody(s)
        T.check("store:false on every request", body["store"] as? Bool, false)
        T.check("no previous_response_id", body["previous_response_id"] == nil, true)
        T.check("instructions carry the system prompt", body["instructions"] as? String, "You are Shrimpy.")
        let input = body["input"] as? [[String: Any]] ?? []
        T.check("whole conversation resent", input.count, 3)
        let file = (input.first?["content"] as? [[String: Any]])?.first
        T.check("PDF as input_file", file?["type"] as? String, "input_file")
        T.check("PDF data URL", (file?["file_data"] as? String)?.hasPrefix("data:application/pdf;base64,"), true)
        T.check("assistant turn as text", input[1]["content"] as? String, "Earlier answer")
        T.check("hosted web search", (body["tools"] as? [[String: Any]])?.first?["type"] as? String, "web_search")

        let tools = await collect(gpt.stream(request("gpt-6.1-sol", tools: true)))
        T.check("function call id is call_id", tools.reply.toolCalls.first?.id, "call_9")
        T.check("flat function tool", (lastBody(s)["tools"] as? [[String: Any]])?.first?["name"] as? String, "get_status")
        T.check("every request store:false", s.requests().filter { $0["path"] as? String == "/v1/responses" }
            .allSatisfy { ($0["body"] as? [String: Any])?["store"] as? Bool == false }, true)
        T.checkTrue("the key never prints", !"\(gpt)".contains("test-key") && !String(reflecting: gpt).contains("test-key"))
        s.stop()

        for (flag, kind) in [("billing", AIErrorKind.billing), ("overloaded", .overloaded), ("cut", .interrupted)] {
            let f = FakeServer(["--fail", flag])
            let result = await collect(OpenAIProvider(apiKey: "k", baseURL: f.base).stream(request("gpt-6.1-sol")))
            T.check("--fail \(flag) → \(kind.rawValue)", result.error?.kind, kind)
            if flag == "billing" { T.check("billing code kept", result.error?.code, "insufficient_quota") }
            if flag == "overloaded" { T.check("503 Retry-After", result.error?.retryAfter, 7) }
            f.stop()
        }
    }
```

Run: `bash scripts/test-ai-providers.sh`
Expected: FAIL with `error: cannot find 'OpenAIProvider' in scope`.

- [ ] **Step 2: Write `NotchBuddy/Sources/App/AI/Core/OpenAIProvider.swift`**

```swift
import Foundation

/// OpenAI through the Responses API: streaming, hosted web search, native PDFs and images.
/// Every request sends `store: false` and the whole conversation; never `previous_response_id`.
struct OpenAIProvider: ModelProvider {
    let id = AIProviderID.openai
    let displayName = "OpenAI"
    let placement = AIPlacement.cloud
    let apiKey: String
    var baseURL = AICatalog.info(.openai).baseURL!
    var session: URLSession = .shared
    var deadlines: StreamDeadlines = .cloud

    private var authorization: String { "Bearer \(apiKey)" }

    /// Chat models, newest first (`/v1/models` has no capability fields, so IDs are filtered).
    func listModels() async throws -> [ModelInfo] {
        guard let url = URL(string: baseURL + "/v1/models") else { throw AIError(kind: .badRequest) }
        var req = URLRequest(url: url, timeoutInterval: AICatalog.Timeouts.connectCloud)
        req.setValue(authorization, forHTTPHeaderField: "Authorization")
        let rows = (try await HTTPStream.json(req, session: session) as? [String: Any])?["data"] as? [[String: Any]] ?? []
        let sorted = rows.sorted { ($0["created"] as? Int ?? 0) > ($1["created"] as? Int ?? 0) }
        return AICatalog.filterModels(sorted.compactMap { $0["id"] as? String }, for: .openai)
            .map { ModelInfo(id: $0, capabilities: [.vision, .tools, .json]) }
    }

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
        AILog.record(.request(id, model: request.model, placement: placement))
        let req = HTTPStream.post(URL(string: baseURL + "/v1/responses")!, body: Self.body(for: request),
                                  headers: ["Authorization": authorization], timeout: HTTPStream.idleTimeout)
        return HTTPStream.run(req, parser: OpenAIResponsesStreamParser(), provider: id, deadlines: deadlines, session: session)
    }

    static func body(for r: ChatRequest) -> [String: Any] {
        let input: [[String: Any]] = r.messages.map { m in
            if m.role == .assistant {
                return ["role": "assistant", "content": m.parts.map(OpenAICompatibleProvider.plainText).joined(separator: "\n\n")]
            }
            return ["role": "user", "content": m.parts.map(item)]
        }
        var body: [String: Any] = ["model": r.model, "instructions": r.system, "input": input, "stream": true,
                                   "store": false, "max_output_tokens": r.maxTokens]
        var tools: [[String: Any]] = []
        if r.webSearch { tools.append(["type": AICatalog.WebSearch.openAIType]) }
        tools += r.tools.map {
            ["type": "function", "name": $0.name, "description": $0.description,
             "parameters": OpenAICompatibleProvider.jsonObject($0.parametersJSON), "strict": false]
        }
        if !tools.isEmpty { body["tools"] = tools }
        if let format = r.responseFormat {
            body["text"] = ["format": ["type": "json_schema", "name": format.name,
                                       "schema": OpenAICompatibleProvider.jsonObject(format.schemaJSON), "strict": true]]
        }
        return body
    }

    private static func item(_ part: ChatRequest.Part) -> [String: Any] {
        switch part {
        case .text(let t):
            return ["type": "input_text", "text": t]
        case .fileText(let name, let text):
            return ["type": "input_text", "text": "File: \(name)\n\n\(text)"]
        case .image(let mime, let data):
            return ["type": "input_image", "image_url": "data:\(mime);base64,\(data.base64EncodedString())", "detail": "auto"]
        case .pdf(let name, let data):
            return ["type": "input_file", "filename": name,
                    "file_data": "data:application/pdf;base64,\(data.base64EncodedString())"]
        }
    }
}

extension OpenAIProvider: RedactsSecrets {
    var redactedSummary: String { "OpenAIProvider(\(baseURL), key: \(Self.keyMark(apiKey)))" }
}
```

- [ ] **Step 3: Run the tests**

Run: `bash scripts/test-ai-providers.sh`
Expected: every `OpenAIProvider (fake server)` line `✓`, including `✓ store:false on every request`, `✓ every request store:false`, `✓ no error without [DONE]`, `✓ --fail billing → billing` and `✓ 503 Retry-After`; then `All tests passed.`

- [ ] **Step 4: Build the app**

Run: `cd NotchBuddy && xcodegen && xcodebuild -project NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug build 2>&1 | grep -E "error:|BUILD" ; cd ..`
Expected: `** BUILD SUCCEEDED **` and no `error:` line. New files under `Sources/` are picked up by `xcodegen`.

- [ ] **Step 5: Commit**

```bash
git add NotchBuddy/Sources/App/AI/Core/OpenAIProvider.swift \
    tests/AIProviderTests.swift \
    NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -m "feat(ai): add OpenAI through the Responses API with store:false

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---
### Task 8: Conversation, chat runner and error copy

**Files:**
- Create: `NotchBuddy/Sources/App/AI/Core/Conversation.swift`
- Create: `NotchBuddy/Sources/App/AI/Core/ChatRunner.swift`
- Create: `NotchBuddy/Sources/App/AI/Core/AIMessages.swift`
- Create: `tests/AIRunnerTests.swift`
- Create: `scripts/test-ai-runner.sh`
- Modify: `.github/workflows/build.yml`

**Interfaces:**
- Consumes: `ModelRouter.afterFailure`, `RoutePlan` (Task 2); `ReplyAccumulator`, `ThinkFilter` (Task 3); `PreparedFile`, `AttachmentPlan`, `ContextBudget.trimHistory` (Task 4); all three providers (Tasks 5–7).
- Produces:
  - `Conversation` with `turns`, `feature` (`files` when the message being sent or any earlier message carries a file, else `chat`; derived from the turns), `attach(_:)`, `attachContext(_:)`, `addUser(_:)`, `addAssistant(_:)`, `removeLastUser()` (takes back a message that got no answer) and `regenerate() -> Turn?` (Retry: drops the last answer only, and hands back the user message to answer again);
  - `Conversation.request(model:api:vision:placement:contextTokens:system:maxTokens:webSearch:) -> Conversation.Built {request, fileNotices, droppedMessages}`.
- Produces:
  - `ChatTarget {provider, model, placement, serverID?, host?, modelLabel?}` (`stripsThinkBlocks`, `ref`);
  - `RunEvent {started, text(visible), citation, waking, fellBack(from:to:kind:)}`, `RunResult {outcome, answeredBy?, text, citations, finish?, error?}`;
  - `ChatRunner(makeProvider:makeRequest:wakingDelay:)` with `.run(plan:primary:fallback:onEvent:) async -> RunResult`.
- Produces: `AIError.outOfRoomCode` (our own code for "hit the cap before any text").
- Produces: `AIAction {openSettings, openBilling(URL), openGuide, chooseModel}`, and `AIMessages` with:
  - constants: `historyTrimmed`, `outOfRoom`, `cutOff`, `interrupted`, `localGuide`, `emptyStateTitle`;
  - names: `shortName`, `bareModel`, `serverName`, `short(_:max:)`;
  - lines: `caption`, `targetLabel`, `dropReader`, `rejected`, `fellBack`, `countdown`, `waking`, and `replyNotes(fellBack:built:finish:)`, the quiet line under a reply;
  - `error(_:target:) -> (text, action?)`, `billingURL(_:)`.

- [ ] **Step 1: Write the failing test `tests/AIRunnerTests.swift`**

The test covers:
- the dropped-file-after-first-turn regression (`file dropped after the first turn joins the next message`);
- the route follows the file: `files` for a file on the current message or on any earlier one, `chat` without a file or after a new conversation, kept by Continue and Retry, and a routing check that a follow-up goes to the local File questions model and never to the cloud Chat model (Review Focus 6);
- Retry never removing a user message;
- the reply cap each request carries (cloud and local retry), read from the catalog;
- every row of the spec §5 copy table that applies to the Mac;
- fallback, countdown, never-fallback cases, waking and Stop, against the fake server;
- Review Focus 1–4 and 6: a cut before text, Stop after text, a deleted local model, tokens spent thinking, and a follow-up about a file;
- the leak test: a marker word goes into the prompt and the dropped file, the test proves the provider received it, then checks that no log line contains it.

```swift
import Foundation

/// Collects log lines and events from @Sendable callbacks.
final class Box<V: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [V] = []
    func add(_ v: V) { lock.withLock { items.append(v) } }
    var all: [V] { lock.withLock { items } }
}

@main
@MainActor
enum AIRunnerTests {
    nonisolated static let logLines = Box<String>()
    static let marker = "ZEBRAQUOKKA7"

    static func main() async {
        AILog.sink.replace { logLines.add($0) }
        conversation()
        featureRouting()
        copy()
        await runner()
        await replyCaps()
        await leak()
        T.finish()
    }

    // MARK: - Conversation (dropped-file regression)

    static func conversation() {
        T.section("Conversation")
        let file = PreparedFile(name: "notes.txt", kind: .text, text: "Shrimpy's notes")
        let cap = AICatalog.maxOutputTokens(for: .local)
        var c = Conversation()
        c.addUser("hi")
        c.addAssistant("hello")
        T.check("plain chat uses the chat route", c.feature, .chat)
        c.attach(file)
        T.check("a dropped file switches to file questions", c.feature, .files)
        c.addUser("what's in it?")
        T.check("the message carrying it is a file question", c.feature, .files)
        var built = c.request(model: "m", api: .openaiChat, vision: false, placement: .local, contextTokens: nil,
                              system: "s", maxTokens: cap, webSearch: false)
        T.check("file dropped after the first turn joins the next message",
                built.request.messages[2].parts.first, .fileText(name: "notes.txt", text: "Shrimpy's notes"))
        T.check("earlier messages stay without it", built.request.messages[0].parts, [.text("hi")])
        c.addAssistant("They are notes.")
        T.check("the next message stays on File questions", c.feature, .files)
        c.addUser("and then?")
        T.check("a follow-up without a file is still a file question", c.feature, .files)
        built = c.request(model: "m", api: .openaiChat, vision: false, placement: .local, contextTokens: nil,
                          system: "s", maxTokens: cap, webSearch: false)
        T.check("the file stays in the history", built.request.messages[2].parts.count, 2)
        T.check("the new message has no copy of it", built.request.messages[4].parts, [.text("and then?")])

        var undo = Conversation()
        undo.attach(file)
        undo.addUser("q")
        undo.removeLastUser()
        undo.addUser("q again")
        T.check("a failed message gives its file back", undo.turns.last?.files.count, 1)

        var regenerate = Conversation()
        regenerate.addUser("q")
        regenerate.addAssistant("partial")
        T.check("Retry hands back the question", regenerate.regenerate()?.text, "q")
        T.check("and drops only the answer", regenerate.turns.map(\.text), ["q"])
        T.check("a second Retry finds no answer to drop", regenerate.regenerate() == nil, true)
        T.check("so the user message stays", regenerate.turns.map(\.text), ["q"])
        regenerate.addAssistant("   ")
        T.check("an empty reply never joins the history", regenerate.turns.count, 1)

        var exchanges = Conversation()
        for (q, a) in [("one", "answer one"), ("two", "answer two")] { exchanges.addUser(q); exchanges.addAssistant(a) }
        _ = exchanges.regenerate()
        T.check("Retry only touches the last exchange", exchanges.turns.map(\.text), ["one", "answer one", "two"])
        var inFlight = Conversation()
        inFlight.addUser("one")
        inFlight.addAssistant("answer one")
        inFlight.addUser("two")
        T.check("a message still being answered is never regenerated",
                inFlight.regenerate() == nil && inFlight.turns.count == 3, true)

        var unanswered = Conversation()
        unanswered.addUser("first question")
        unanswered.addUser("second question")   // a failed Retry left the first one without an answer
        let joined = unanswered.request(model: "m", api: .openaiChat, vision: false, placement: .local, contextTokens: nil,
                                        system: "s", maxTokens: cap, webSearch: false)
        T.check("two user messages in a row go out as one", joined.request.messages.map(\.role), [.user])
        T.check("with both questions", joined.request.messages.first?.parts,
                [.text("first question"), .text("second question")])

        T.section("Conversation history trimming")
        var long = Conversation()
        for i in 0..<6 {
            long.addUser(String(repeating: "u", count: 3000) + "\(i)")
            long.addAssistant(String(repeating: "a", count: 3000))
        }
        long.addUser("latest")
        let trimmed = long.request(model: "m", api: .openaiChat, vision: false, placement: .local, contextTokens: 4096,
                                   system: "s", maxTokens: cap, webSearch: false)
        T.checkTrue("oldest messages dropped", trimmed.droppedMessages > 0)
        T.check("starts with a user message", trimmed.request.messages.first?.role, .user)
        T.check("keeps the latest message", trimmed.request.messages.last?.parts, [.text("latest")])

        // A family emoji is 5 Unicode scalars but 1 Swift Character: history-cases.json counts scalars.
        let family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}"
        var emoji = Conversation()
        for _ in 0..<2 {
            emoji.addUser(String(repeating: family, count: 1000))
            emoji.addAssistant(String(repeating: family, count: 1000))
        }
        emoji.addUser("hi")
        let counted = emoji.request(model: "m", api: .openaiChat, vision: false, placement: .local, contextTokens: 4096,
                                    system: "s", maxTokens: cap, webSearch: false)
        T.check("the chat counts scalars, not characters", counted.droppedMessages, 2)
        T.check("and says so", AIMessages.historyTrimmed, "This chat got long, so I dropped the oldest messages.")
    }

    // MARK: - Which route a message takes

    /// The provider a message goes to when File questions is a local model and Chat is Auto with a cloud key:
    /// the settings that make a leak possible.
    static func providerFor(_ c: Conversation) -> AIProviderID? {
        let qwen = LocalCandidate(provider: .ollama, model: "qwen3.5:2b", placement: .local)
        let setting: FeatureSetting = c.feature == .files
            ? .explicit(ModelRef(provider: qwen.provider, model: qwen.model)) : .auto
        return ModelRouter.plan(RouteInput(setting: setting, keys: [.anthropic], localReady: [qwen]))?.primary
    }

    static func featureRouting() {
        T.section("Conversation.feature (a follow-up stays on File questions)")
        let file = PreparedFile(name: "notes.txt", kind: .text, text: "Shrimpy's notes")

        T.check("an empty conversation is Chat", Conversation().feature, .chat)
        var plain = Conversation()
        plain.addUser("hi")
        plain.addAssistant("hello")
        plain.addUser("how are you?")
        T.check("no files anywhere is Chat", plain.feature, .chat)
        T.check("and Chat goes to the cloud", providerFor(plain), .anthropic)

        var c = Conversation()
        c.attach(file)
        T.check("a file waiting for the next message is File questions", c.feature, .files)
        c.addUser("what's in it?")
        T.check("the current message carries a file: File questions", c.feature, .files)
        T.check("and goes to the local model", providerFor(c), .ollama)
        c.addAssistant("They are notes.")
        c.addUser("who wrote them?")
        T.check("a file only on an earlier message: still File questions", c.feature, .files)
        T.check("so the follow-up never reaches the cloud", providerFor(c), .ollama)
        c.addAssistant("Shrimpy did.")
        c.addUser("and what's the weather like?")
        T.check("any number of messages later", c.feature, .files)

        var cut = c
        cut.addAssistant("Half an ans")
        cut.addUser("Continue from where you stopped.")
        T.check("Continue keeps the route", cut.feature, .files)
        var plainCut = plain
        plainCut.addAssistant("Half an ans")
        plainCut.addUser("Continue from where you stopped.")
        T.check("and Continue in a chat without files stays Chat", plainCut.feature, .chat)
        var retry = c
        retry.addAssistant("A bad answer")
        _ = retry.regenerate()
        T.check("Retry keeps the route", retry.feature, .files)

        var failed = Conversation()
        failed.attach(file)
        failed.addUser("q")
        failed.removeLastUser()
        T.check("a message that got no answer gives its file back, and its route", failed.feature, .files)

        // A file drop or an attached window makes ClaudeService start a new Conversation.
        c = Conversation()
        c.addUser("a new question")
        T.check("after a reset: Chat again", c.feature, .chat)
        T.check("and it goes to the cloud again", providerFor(c), .anthropic)
    }

    // MARK: - Copy (spec §5 table)

    static func copy() {
        T.section("AIMessages")
        let claude = ChatTarget(provider: .anthropic, model: "claude-sonnet-5-5", placement: .cloud, modelLabel: "Claude Sonnet 5.5")
        let gpt = ChatTarget(provider: .openai, model: "gpt-6.1-sol", placement: .cloud)
        let qwen = ChatTarget(provider: .ollama, model: "qwen3.5:2b", placement: .local)
        let lms = ChatTarget(provider: .lmstudio, model: "gemma-4-e2b", placement: .local)
        let studio = ChatTarget(provider: .custom, model: "llama3", placement: .network, serverID: "custom-1", host: "studio-pc")
        T.check("fell back", AIMessages.fellBack(from: claude, to: qwen), "Claude's busy right now, so Qwen answered instead.")
        T.check("countdown", AIMessages.countdown(claude, seconds: 20), "Claude is busy. Trying again in 20 s.")
        T.check("key rejected", AIMessages.error(AIError(kind: .auth), target: claude).text, "Your Anthropic key was rejected.")
        T.check("key rejected action", AIMessages.error(AIError(kind: .auth), target: claude).action, .openSettings)
        T.check("credit ran out", AIMessages.error(AIError(kind: .billing, code: "insufficient_quota"), target: gpt).text,
                "Your OpenAI credit ran out.")
        T.check("spend limit", AIMessages.error(AIError(kind: .billing, code: "project_spend_limit_exceeded"), target: gpt).text,
                "Your OpenAI spend limit was reached.")
        T.checkTrue("billing opens the billing page",
                    AIMessages.error(AIError(kind: .billing), target: gpt).action == .openBilling(AIMessages.billingURL(.openai)!))
        T.check("local unreachable", AIMessages.error(AIError(kind: .unreachable), target: lms).text,
                "Couldn't reach LM Studio. Is its server on?")
        T.check("local unreachable action", AIMessages.error(AIError(kind: .unreachable), target: lms).action, .openGuide)
        T.check("waking", AIMessages.waking(qwen), "Waking up qwen3.5…")
        T.check("caption cloud", AIMessages.caption(claude), "cloud · Claude Sonnet 5.5")
        T.check("caption cloud id", AIMessages.caption(gpt), "cloud · gpt-6.1-sol")
        T.check("caption local", AIMessages.caption(qwen), "local · qwen3.5:2b")
        T.check("caption network", AIMessages.caption(studio), "network · llama3 @ studio-pc")
        T.check("drop card cloud", AIMessages.dropReader(claude), "Claude will read this")
        T.check("drop card local", AIMessages.dropReader(qwen), "Local · qwen3.5:2b will read this")
        T.check("label cloud with name", AIMessages.targetLabel(claude), "Claude Sonnet 5.5")
        T.check("label cloud without name", AIMessages.targetLabel(gpt), "OpenAI · gpt-6.1-sol")
        T.check("label local", AIMessages.targetLabel(qwen), "Local · qwen3.5:2b")
        T.check("label network", AIMessages.targetLabel(studio), "Network · llama3 @ studio-pc")
        T.check("rejected type", AIMessages.rejected(.type), "I can't read this kind of file, but I can email it.")
        T.check("long model IDs are shortened",
                AIMessages.dropReader(ChatTarget(provider: .ollama, model: "hf.co/unsloth/Qwen3.5-2B-GGUF:Q4_K_M", placement: .local)),
                "Local · hf.co/unsloth…2B-GGUF:Q4_K_M will read this")
        T.check("deleted local model", AIMessages.error(AIError(kind: .badRequest, status: 404), target: qwen).text,
                "qwen3.5:2b isn't installed. Pick another model above the chat box.")
        T.check("deleted local model action", AIMessages.error(AIError(kind: .badRequest, status: 404), target: qwen).action,
                .chooseModel)
        T.check("out of room", AIMessages.error(AIError(kind: .server, code: AIError.outOfRoomCode), target: qwen).text,
                "The model ran out of room before answering. Try again, or pick a model without thinking mode.")
        T.check("cut off", AIMessages.cutOff, "The answer was cut off.")
        let built = Conversation.Built(request: ChatRequest(model: "m", system: "s", messages: []),
                                       fileNotices: ["I read the first 716 lines."], droppedMessages: 2)
        T.check("every note, in order",
                AIMessages.replyNotes(fellBack: "Claude's busy right now, so Qwen answered instead.", built: built, finish: .length),
                "Claude's busy right now, so Qwen answered instead. I read the first 716 lines. "
                    + "This chat got long, so I dropped the oldest messages. The answer was cut off.")
        T.check("a cut answer says so", AIMessages.replyNotes(fellBack: nil, built: nil, finish: .length), "The answer was cut off.")
        T.check("a normal answer has no notes", AIMessages.replyNotes(fellBack: nil, built: nil, finish: .stop), nil)
        T.check("refusal fallback copy", AIMessages.error(AIError(kind: .refusal), target: claude).text,
                "Claude declined to answer this.")
    }

    // MARK: - Runner against fake servers

    struct Setup: Sendable {
        let cloud: String
        let local: String
    }

    static func runner(_ cloudFlags: [String], localFlags: [String] = [], primary: AIProviderID = .anthropic,
                       withFallback: Bool = true, prompt: String = "hello",
                       fileText: String? = nil) async -> (RunResult, [RunEvent]) {
        let (result, events, _, _) = await run(cloudFlags, localFlags: localFlags, primary: primary,
                                            withFallback: withFallback, prompt: prompt, fileText: fileText)
        return (result, events)
    }

    /// Also returns what the cloud and the local fake servers received, as JSON text.
    static func run(_ cloudFlags: [String], localFlags: [String] = [], primary: AIProviderID = .anthropic,
                    withFallback: Bool = true, prompt: String = "hello",
                    fileText: String? = nil) async -> (RunResult, [RunEvent], String, String) {
        let cloud = FakeServer(cloudFlags)
        let local = FakeServer(localFlags)
        defer { cloud.stop(); local.stop() }
        let setup = Setup(cloud: cloud.base, local: local.base)
        var conversation = Conversation()
        if let fileText { conversation.attach(PreparedFile(name: "secret.txt", kind: .text, text: fileText)) }
        conversation.addUser(prompt)
        let convo = conversation
        let primaryTarget = ChatTarget(provider: primary, model: primary == .openai ? "gpt-6.1-sol" : "claude-sonnet-5-5",
                                       placement: .cloud)
        let localTarget = ChatTarget(provider: .ollama, model: "llama3.2", placement: .local)
        let runner = ChatRunner(
            makeProvider: { t -> any ModelProvider in
                switch t.provider {
                case .anthropic: AnthropicProvider(apiKey: "k", baseURL: setup.cloud)
                case .openai: OpenAIProvider(apiKey: "k", baseURL: setup.cloud)
                default: OpenAICompatibleProvider.make(t.provider, baseURL: setup.local)
                }
            },
            makeRequest: { t in
                convo.request(model: t.model, api: AICatalog.info(t.provider).api, vision: t.placement == .cloud,
                              placement: t.placement, contextTokens: nil, system: "s",
                              maxTokens: AICatalog.maxOutputTokens(for: t.placement),
                              webSearch: t.provider == .anthropic || t.provider == .openai).request
            },
            wakingDelay: 0.2)
        let plan = RoutePlan(primary: primary, model: nil, serverID: nil, placement: .cloud,
                             fallback: withFallback ? LocalCandidate(provider: .ollama, model: "llama3.2", placement: .local) : nil,
                             isAuto: true)
        let events = Box<RunEvent>()
        let result = await runner.run(plan: plan, primary: primaryTarget,
                                      fallback: { withFallback ? localTarget : nil },
                                      onEvent: { events.add($0) })
        // A GET (the model list) is logged with a null body, which JSONSerialization cannot write.
        func sent(_ server: FakeServer) -> String {
            server.requests().compactMap { $0["body"] }
                .filter { JSONSerialization.isValidJSONObject($0) }
                .compactMap { try? JSONSerialization.data(withJSONObject: $0) }
                .map { String(decoding: $0, as: UTF8.self) }.joined(separator: "\n")
        }
        return (result, events.all, sent(cloud), sent(local))
    }

    static func runner() async {
        T.section("ChatRunner")
        var (r, events) = await runner([])
        T.check("cloud answers", r.outcome, .ok)
        T.check("answer text", r.text, "Cats sleep a lot.")
        T.check("sources kept", r.citations.count, 1)

        (r, events) = await runner(["--fail", "500"])
        T.check("500 → one local retry", r.outcome, .fallback)
        T.check("local answered", r.answeredBy?.provider, .ollama)
        T.checkTrue("local reply text", r.text.hasPrefix("## Answer"))
        T.check("primary error kept for the notice", r.error?.kind, .server)
        T.checkTrue("fell-back event", events.contains { if case .fellBack = $0 { true } else { false } })

        (r, _) = await runner(["--fail", "429"], withFallback: false)
        T.check("429 and no local → countdown", r.outcome, .retryCountdown)
        T.check("Retry-After honoured", r.error?.retryAfter, 2)

        (r, _) = await runner(["--fail", "billing"], primary: .openai)
        T.check("billing never falls back", r.outcome, .error)
        T.check("billing kind", r.error?.kind, .billing)

        (r, _) = await runner(["--fail", "401"])
        T.check("rejected key never falls back", r.outcome, .error)

        (r, _) = await runner(["--fail", "refuse"])
        T.check("refusal never falls back", r.error?.kind, .refusal)
        T.check("refusal is not retried", r.answeredBy?.provider, .anthropic)

        (r, _) = await runner(["--fail", "500"], localFlags: ["--fail", "500"])
        T.check("local retry fails too → the cloud error", r.outcome, .error)
        T.check("and its kind", r.error?.kind, .server)

        (r, _) = await runner(["--fail", "overloaded"], localFlags: ["--fail", "500"])
        T.check("busy + local fails → countdown", r.outcome, .retryCountdown)

        (r, events) = await runner(["--fail", "500"], localFlags: ["--fail", "slow-first-token", "--delay", "1"])
        T.checkTrue("waking event for a slow local model", events.contains { if case .waking = $0 { true } else { false } })

        (r, _) = await runner(["--fail", "cut"])
        T.check("cut before any text → a failed request, retried locally", r.outcome, .fallback)
        (r, _) = await runner(["--fail", "cut"], withFallback: false)
        T.check("cut before any text, no local → error", r.outcome, .error)
        T.check("reported as a server problem", r.error?.kind, .server)

        await stopAfterText()
        await emptyReply()
        await outOfRoomNeverFallsBack()

        let task = Task { await runner(["--fail", "slow-first-token", "--delay", "3"]) }
        try? await Task.sleep(nanoseconds: 500_000_000)
        task.cancel()
        T.check("Stop cancels", await task.value.0.outcome, .cancelled)
    }

    /// Each request carries the reply cap its placement gets from the catalog.
    static func replyCaps() async {
        T.section("Reply caps")
        let cloudCap = AICatalog.maxOutputTokens(for: .cloud)
        let localCap = AICatalog.maxOutputTokens(for: .local)
        T.checkTrue("the cloud cap is larger, so the checks below can tell the two apart", cloudCap > localCap)
        let (_, _, claude, _) = await run([])
        T.checkTrue("Claude's request carries the cloud cap", claude.contains("\"max_tokens\":\(cloudCap)"))
        let (_, _, gpt, _) = await run([], primary: .openai)
        T.checkTrue("OpenAI's request carries the cloud cap", gpt.contains("\"max_output_tokens\":\(cloudCap)"))
        let (_, _, _, retry) = await run(["--fail", "500"])
        T.checkTrue("the local retry carries the local cap", retry.contains("\"max_tokens\":\(localCap)"))
    }

    /// Yields its chunks, then waits until cancelled (`hang`) or ends.
    struct ScriptedProvider: ModelProvider {
        let id = AIProviderID.ollama
        let displayName = "Scripted"
        let placement = AIPlacement.local
        var chunks: [ChatChunk] = [.text("Half an ans")]
        var hang = true
        func listModels() async throws -> [ModelInfo] { [] }
        func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
            let chunks = self.chunks, hang = self.hang
            return AsyncThrowingStream { continuation in
                let task = Task {
                    chunks.forEach { continuation.yield($0) }
                    if hang { try? await Task.sleep(nanoseconds: 10_000_000_000) }
                    continuation.finish()
                }
                continuation.onTermination = { _ in task.cancel() }
            }
        }
    }

    static func scripted(_ chunks: [ChatChunk]) async -> RunResult {
        let runner = ChatRunner(makeProvider: { _ in ScriptedProvider(chunks: chunks, hang: false) },
                                makeRequest: { t in ChatRequest(model: t.model, system: "s", messages: []) })
        let target = ChatTarget(provider: .ollama, model: "m", placement: .local)
        let plan = RoutePlan(primary: .ollama, model: "m", serverID: nil, placement: .local, fallback: nil, isAuto: true)
        return await runner.run(plan: plan, primary: target, fallback: { nil }, onEvent: { _ in })
    }

    static func emptyReply() async {
        var r = await scripted([.activity, .finish(.stop)])
        T.check("a reply with no text is a failed request", "\(r.outcome.rawValue) \(r.error?.kind.rawValue ?? "nil")",
                "error server")
        r = await scripted([.text("<think>Let me think about this for a very long"), .finish(.length)])
        T.check("all tokens spent thinking → out of room", r.error?.code, AIError.outOfRoomCode)
        r = await scripted([.text("Half of the answer"), .finish(.length)])
        T.check("cut at the cap: the text is kept", "\(r.outcome.rawValue) \(r.text)", "ok Half of the answer")
        T.check("and marked length", r.finish, .length)
    }

    /// A cloud model that spends its whole cap thinking: Auto must say so, not quietly ask a local model.
    static func outOfRoomNeverFallsBack() async {
        let asked = Box<Int>()
        let runner = ChatRunner(makeProvider: { _ in ScriptedProvider(chunks: [.text("<think>endless"), .finish(.length)], hang: false) },
                                makeRequest: { t in ChatRequest(model: t.model, system: "s", messages: []) })
        let primary = ChatTarget(provider: .google, model: "m", placement: .cloud)
        let local = ChatTarget(provider: .ollama, model: "q", placement: .local)
        let plan = RoutePlan(primary: .google, model: nil, serverID: nil, placement: .cloud,
                             fallback: LocalCandidate(provider: .ollama, model: "q", placement: .local), isAuto: true)
        let r = await runner.run(plan: plan, primary: primary, fallback: { asked.add(1); return local }, onEvent: { _ in })
        T.check("out of room is an error, not a fallback", "\(r.outcome.rawValue) \(asked.all.count)", "error 0")
        T.check("and it says why", r.error?.code, AIError.outOfRoomCode)
    }

    static func stopAfterText() async {
        let runner = ChatRunner(makeProvider: { _ in ScriptedProvider() },
                                makeRequest: { t in ChatRequest(model: t.model, system: "s", messages: []) })
        let target = ChatTarget(provider: .ollama, model: "m", placement: .local)
        let plan = RoutePlan(primary: .ollama, model: "m", serverID: nil, placement: .local, fallback: nil, isAuto: true)
        let task = Task { await runner.run(plan: plan, primary: target, fallback: { nil }, onEvent: { _ in }) }
        try? await Task.sleep(nanoseconds: 300_000_000)
        task.cancel()
        let r = await task.value
        T.check("Stop after text keeps the partial reply", r.text, "Half an ans")
        T.check("as cancelled, not interrupted", r.outcome, .cancelled)
    }

    // MARK: - Leak test

    static func leak() async {
        T.section("Logs never carry prompts or file contents")
        let before = logLines.all.count
        let prompt = "Tell me about \(marker) please"
        let file = "line one\n\(marker) is in this file\n"
        var sent = ""
        for (flags, primary) in [([String](), AIProviderID.anthropic), (["--fail", "500"], .anthropic),
                                 (["--fail", "401"], .anthropic), (["--fail", "cut"], .openai),
                                 (["--fail", "billing"], .openai)] {
            sent += await run(flags, primary: primary, prompt: prompt, fileText: file).2
        }
        let lines = Array(logLines.all.dropFirst(before))
        T.checkTrue("the marker really went to the provider", sent.contains(marker))
        T.checkTrue("these runs were logged", lines.count >= 10)
        T.checkTrue("request lines name the provider", lines.contains { $0.hasPrefix("ai request provider=anthropic") })
        T.checkTrue("failures carry the kind", lines.contains { $0.contains("kind=billing") })
        T.check("no log line contains the marker", lines.filter { $0.contains(marker) }, [])
    }
}
```

- [ ] **Step 2: Write `scripts/test-ai-runner.sh`**

```bash
#!/usr/bin/env bash
# AI chat runner: conversation/per-turn files, error copy, fallback and countdown against
# the fake server, and the log leak test (a marker word must never reach a log line).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-ai-runner.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs
swiftc -swift-version 6 \
    NotchBuddy/Sources/App/AI/Core/*.swift \
    NotchBuddy/Sources/App/AppLog.swift \
    tests/AITestSupport.swift tests/AIRunnerTests.swift \
    -o "$TEST_DIR/ai-runner-tests"
"$TEST_DIR/ai-runner-tests"
```

Run: `chmod +x scripts/test-ai-runner.sh && bash scripts/test-ai-runner.sh`
Expected: FAIL with `error: cannot find 'Conversation' in scope`.

- [ ] **Step 3: Write `NotchBuddy/Sources/App/AI/Core/Conversation.swift`**

A file joins the user message it was attached before, on whichever turn, and stays in the history as an already-prepared `PreparedFile`, so it is never read again. Each model gets it in its own form. `feature` follows the file: File questions once the message being sent, or any earlier message, carries one. It is derived from the turns, never from a flag, so a follow-up stays on the route the person chose for files and the file's text cannot reach a cloud Chat model. `ClaudeService` still starts a new conversation on every drop and window attach, keeping the shipped fix, and that resets the rule.

```swift
import Foundation

/// What the model sees of one chat, independent of any provider. Files join the user message
/// they were attached before, and stay in the history after it; each provider gets them in its own
/// form (native PDF, image, or text cut to its budget).
struct Conversation: Sendable, Equatable {
    struct Turn: Sendable, Equatable {
        var role: ChatRequest.Role
        var text: String
        var files: [PreparedFile] = []
        /// "Context — App: …" line for an attached window.
        var context: String? = nil
    }

    private(set) var turns: [Turn] = []
    private(set) var pendingFiles: [PreparedFile] = []
    private(set) var pendingContext: String? = nil

    /// File questions (`files`) when the message being sent carries a file or any earlier message in this
    /// conversation did; otherwise `chat`. A file's text stays in the history, so a follow-up on the Chat
    /// route could send it to a cloud model that the person kept File questions away from. Derived from the
    /// messages, never from a flag. A file drop or an attached window starts a new `Conversation`, which
    /// resets it. Continue and Retry add no file, so they keep the route of the reply they follow.
    var feature: AIFeature {
        let carriesFile = !pendingFiles.isEmpty || turns.contains { !$0.files.isEmpty }
        return carriesFile ? .files : .chat
    }

    /// The file goes out with the next user message, whichever turn that is.
    mutating func attach(_ file: PreparedFile) { pendingFiles.append(file) }

    mutating func attachContext(_ line: String) { pendingContext = line }

    mutating func addUser(_ text: String) {
        turns.append(Turn(role: .user, text: text, files: pendingFiles, context: pendingContext))
        pendingFiles = []
        pendingContext = nil
    }

    /// Empty replies are not kept (APIs reject empty assistant messages).
    mutating func addAssistant(_ text: String) {
        let t = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !t.isEmpty else { return }
        turns.append(Turn(role: .assistant, text: t))
    }

    /// Undo a user message that got no answer, putting its files back for the next try.
    mutating func removeLastUser() {
        guard let last = turns.last, last.role == .user else { return }
        turns.removeLast()
        pendingFiles = last.files + pendingFiles
        pendingContext = last.context ?? pendingContext
    }

    /// Retry: drops the last answer and hands back the user message it answered, so it can be answered
    /// again. Only an answer is ever removed, and only when the chat ends with a user message and its
    /// answer: a message still being answered, or an earlier exchange, is left alone. Retry never takes
    /// back a user message, because it didn't add one.
    mutating func regenerate() -> Turn? {
        guard turns.count >= 2, turns[turns.count - 1].role == .assistant,
              turns[turns.count - 2].role == .user else { return nil }
        turns.removeLast()
        return turns.last
    }

    struct Built: Sendable, Equatable {
        var request: ChatRequest
        /// Truncation notices for the newest message's files ("I read the first 716 lines.").
        var fileNotices: [String]
        var droppedMessages: Int
    }

    /// The request for one model.
    func request(model: String, api: AIProviderAPI, vision: Bool, placement: AIPlacement, contextTokens: Int?,
                 system: String, maxTokens: Int, webSearch: Bool) -> Built {
        var notices: [String] = []
        var messages: [ChatRequest.Message] = turns.enumerated().map { index, turn in
            var parts: [ChatRequest.Part] = []
            if let context = turn.context { parts.append(.text(context)) }
            for file in turn.files {
                let planned = AttachmentPlan.parts(for: file, api: api, vision: vision,
                                                   placement: placement, contextTokens: contextTokens)
                parts += planned.parts
                // Only the newest message's notices are new to the user.
                if index == turns.count - 1, let n = planned.notice { notices.append(n) }
            }
            parts.append(.text(turn.text))
            return ChatRequest.Message(role: turn.role, parts: parts)
        }
        // A failed Retry leaves its question unanswered; if the user then asks something else, two user
        // messages follow each other. Some chat templates refuse that, so same-role neighbours are joined.
        messages = Self.joiningSameRole(messages)
        // Long chats on small models: the shared rule (history-cases.json), in Unicode scalars.
        let trim = ContextBudget.trimHistory(messages: messages, system: system, placement: placement,
                                             contextTokens: contextTokens)
        messages.removeFirst(trim.dropped)
        let request = ChatRequest(model: model, system: system, messages: messages, maxTokens: maxTokens,
                                  webSearch: webSearch)
        return Built(request: request, fileNotices: notices, droppedMessages: trim.dropped)
    }

    private static func joiningSameRole(_ messages: [ChatRequest.Message]) -> [ChatRequest.Message] {
        var joined: [ChatRequest.Message] = []
        for message in messages {
            if let last = joined.last, last.role == message.role {
                joined[joined.count - 1].parts += message.parts
            } else {
                joined.append(message)
            }
        }
        return joined
    }
}
```

- [ ] **Step 4: Write `NotchBuddy/Sources/App/AI/Core/ChatRunner.swift`**

The rules:
- **Fallback.** Auto retries locally only before any text was shown, and only when the router says `fallback`. The `fallback` closure runs discovery again first, as the spec asks.
- **Cut before text.** A stream cut before any text is a `server` failure (Review Focus 1).
- **Empty replies.** A finished stream with no visible text is a `server` failure. With `length`, it also carries `AIError.outOfRoomCode` (Review Focus 4), and Auto does not retry it on another model. Text that hit the cap comes back `ok` with `finish == .length`.
- **Failed retry.** If the local retry fails, the cloud failure decides the result, as if there were no local model: a countdown or an error.

```swift
import Foundation

/// One concrete model to call.
struct ChatTarget: Sendable, Equatable {
    var provider: AIProviderID
    var model: String
    var placement: AIPlacement
    /// Discovery's server ID (custom servers), nil for cloud and default local servers.
    var serverID: String? = nil
    /// Server host for the `network · model @ host` caption.
    var host: String? = nil
    /// Human model name when the provider gives one ("Claude Sonnet 5.5").
    var modelLabel: String? = nil

    var stripsThinkBlocks: Bool { AICatalog.info(provider).api == .openaiChat }
    var ref: ModelRef { ModelRef(provider: provider, model: model, serverID: serverID) }
}

enum RunEvent: Sendable, Equatable {
    /// A new attempt began (the primary, or the local retry): the reply so far is discarded.
    case started(ChatTarget)
    /// Everything visible so far (think blocks hidden), at most ~15 times a second.
    case text(String)
    case citation(Citation)
    /// A local model has not produced anything after `wakingDelay`: it is probably loading.
    case waking(ChatTarget)
    case fellBack(from: ChatTarget, to: ChatTarget, kind: AIErrorKind)
}

struct RunResult: Sendable, Equatable {
    var outcome: RouteOutcome
    var answeredBy: ChatTarget?
    var text: String = ""
    var citations: [Citation] = []
    var finish: FinishReason? = nil
    /// The failure behind `error`, `retryCountdown`, `fallback` (the primary's) or `interrupted`.
    var error: AIError? = nil
}

/// Runs one message: the primary model, then at most one local retry when Auto allows it.
/// Fallback only happens before any text was shown; afterwards a failure keeps the partial reply.
struct ChatRunner: Sendable {
    let makeProvider: @Sendable (ChatTarget) -> any ModelProvider
    let makeRequest: @Sendable (ChatTarget) async -> ChatRequest
    var wakingDelay: TimeInterval = 1.5

    func run(plan: RoutePlan, primary: ChatTarget,
             fallback: @escaping @Sendable () async -> ChatTarget?,
             onEvent: @escaping @Sendable (RunEvent) async -> Void) async -> RunResult {
        let first = await attempt(primary, onEvent: onEvent)
        guard var error = first.error else { return first }
        // Out of room is not a passing problem: another model would not be asked the same question, so
        // the user is told, with a way to pick another model.
        if !first.text.isEmpty || error.kind == .cancelled || error.kind == .refusal
            || error.code == AIError.outOfRoomCode {
            return first
        }
        // Cut before any text (a captive portal, a crash right after the headers): nothing to keep,
        // so it is a failed request, not an interrupted reply.
        if error.kind == .interrupted { error.kind = .server }
        var decision = ModelRouter.afterFailure(plan, failure: error.kind)
        if decision.outcome == .fallback {
            if let local = await fallback() {
                await onEvent(.fellBack(from: primary, to: local, kind: error.kind))
                AILog.record(.fallback(from: primary.provider, to: local.provider, kind: error.kind))
                var second = await attempt(local, onEvent: onEvent)
                if second.error == nil {
                    second.outcome = .fallback
                    second.error = error
                    return second
                }
                if !second.text.isEmpty || second.error?.kind == .cancelled { return second }
            }
            var noLocal = plan
            noLocal.fallback = nil
            decision = ModelRouter.afterFailure(noLocal, failure: error.kind)
        }
        return RunResult(outcome: decision.outcome, answeredBy: nil, error: error)
    }

    private func attempt(_ target: ChatTarget, onEvent: @escaping @Sendable (RunEvent) async -> Void) async -> RunResult {
        await onEvent(.started(target))
        let request = await makeRequest(target)
        let provider = makeProvider(target)
        let shown = ShownFlag()
        let waking = Task {
            guard target.placement != .cloud else { return }
            try? await Task.sleep(nanoseconds: UInt64(wakingDelay * 1_000_000_000))
            if !Task.isCancelled, !shown.value { await onEvent(.waking(target)) }
        }
        defer { waking.cancel() }
        var acc = ReplyAccumulator(stripsThinkBlocks: target.stripsThinkBlocks)
        var lastSent = Date.distantPast
        do {
            for try await chunk in provider.stream(request) {
                acc.add(chunk)
                switch chunk {
                case .text, .refusal:
                    shown.set()
                    if Date().timeIntervalSince(lastSent) >= 1.0 / 15.0 {
                        lastSent = Date()
                        await onEvent(.text(acc.visibleText))
                    }
                case .citation(let c):
                    await onEvent(.citation(c))
                default:
                    break
                }
            }
            try Task.checkCancellation()
        } catch {
            let failure = (error as? AIError) ?? AIError(kind: HTTPErrorRules.transportKind(error))
            await onEvent(.text(acc.visibleText))
            let text = ThinkFilter.visible(acc.text)
            let outcome: RouteOutcome = failure.kind == .cancelled ? .cancelled : (text.isEmpty ? .error : .interrupted)
            return RunResult(outcome: outcome, answeredBy: text.isEmpty ? nil : target, text: text,
                             citations: acc.citations, error: failure)
        }
        await onEvent(.text(acc.visibleText))
        if let refusal = acc.refusal {
            return RunResult(outcome: .error, answeredBy: target, text: refusal, finish: .refusal,
                             error: AIError(kind: .refusal))
        }
        let text = ThinkFilter.visible(acc.text)
        // A finished stream with nothing to show is a failed request, never an empty bubble or an empty
        // turn in the history. With `length`, a thinking model spent the whole cap inside <think>.
        if text.isEmpty {
            return RunResult(outcome: .error, error: AIError(kind: .server,
                                                             code: acc.finish == .length ? AIError.outOfRoomCode : nil))
        }
        return RunResult(outcome: .ok, answeredBy: target, text: text, citations: acc.citations, finish: acc.finish)
    }
}

extension AIError {
    /// Our own code (never a provider's): the reply hit `max_tokens` before any visible text.
    static let outOfRoomCode = "nm_out_of_room"
}

private final class ShownFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var shown = false
    func set() { lock.withLock { shown = true } }
    var value: Bool { lock.withLock { shown } }
}
```

- [ ] **Step 5: Write `NotchBuddy/Sources/App/AI/Core/AIMessages.swift`**

The copy follows the spec §5 table verbatim. Rows the table doesn't cover (offline with no local model, a cloud timeout, a server error, still busy after the automatic retry, an empty refusal) get short lines in the same voice.

```swift
import Foundation

/// The one button a message may carry.
enum AIAction: Sendable, Equatable {
    case openSettings
    case openBilling(URL)
    case openGuide
    case chooseModel
}

/// Every user-facing AI string (spec §5 copy table). Plain, lightly cat-flavoured, one action at most.
enum AIMessages {
    static let historyTrimmed = ContextBudget.historyNotice
    static let outOfRoom = "The model ran out of room before answering. Try again, or pick a model without thinking mode."
    static let cutOff = "The answer was cut off."
    static let interrupted = "interrupted"
    static let localGuide = "Run a model on this Mac with [Ollama](https://ollama.com/download) or "
        + "[LM Studio](https://lmstudio.ai), then come back. I'll find it on my own."
    static let emptyStateTitle = "Pick a brain for me first."

    /// "Claude", "OpenAI", "Gemini", "Apple's model", or a local model's family ("Qwen").
    static func shortName(_ t: ChatTarget) -> String {
        switch t.provider {
        case .anthropic: return "Claude"
        case .openai: return "OpenAI"
        case .google: return "Gemini"
        case .apple: return "Apple's model"
        default:
            let base = t.model.split(separator: "/").last.map(String.init) ?? t.model
            let letters = base.prefix { $0.isLetter }
            return letters.isEmpty ? base : letters.prefix(1).uppercased() + letters.dropFirst()
        }
    }

    /// Model ID without its tag: "qwen3.5:2b" → "qwen3.5".
    static func bareModel(_ model: String) -> String {
        String(model.split(separator: ":").first ?? Substring(model))
    }

    static func serverName(_ t: ChatTarget) -> String {
        t.provider == .custom ? (t.host ?? "the local server") : AICatalog.info(t.provider).name
    }

    /// Caption under each reply: `cloud · Claude Sonnet 5.5`, `local · qwen3.5:2b`, `network · llama3 @ studio-pc`.
    static func caption(_ t: ChatTarget) -> String {
        let name = t.provider == .apple ? "Apple on-device" : (t.modelLabel ?? t.model)
        if t.placement == .network, let host = t.host { return "network · \(name) @ \(host)" }
        return "\(t.placement.rawValue) · \(name)"
    }

    /// The drop card's line: "Claude will read this", "Local · qwen3.5:2b will read this".
    static func dropReader(_ t: ChatTarget?) -> String? {
        guard let t else { return nil }
        switch t.placement {
        case .cloud: return "\(shortName(t)) will read this"
        case .local: return t.provider == .apple ? "Apple on-device will read this" : "Local · \(short(t.model)) will read this"
        case .network: return "Network · \(short(t.model)) @ \(t.host ?? "server") will read this"
        }
    }

    /// Settings and picker label: "Claude Sonnet 5.5", "OpenAI · gpt-6.1-sol", "Local · qwen3.5:2b".
    static func targetLabel(_ t: ChatTarget) -> String {
        switch t.placement {
        case .cloud: return t.modelLabel ?? "\(shortName(t)) · \(t.model)"
        case .local: return t.provider == .apple ? "Apple on-device" : "Local · \(t.model)"
        case .network: return "Network · \(t.model) @ \(t.host ?? "server")"
        }
    }

    /// Drop card line for a file the AI can't take.
    static func rejected(_ reason: AttachmentRejection) -> String {
        switch reason {
        case .size: "Over 25 MB: too big for me to read, but I can email it."
        case .type: "I can't read this kind of file, but I can email it."
        }
    }

    /// Long model IDs (`hf.co/…/Qwen3.5-2B-GGUF:Q4_K_M`) keep their start and end.
    static func short(_ model: String, max: Int = 28) -> String {
        guard model.count > max else { return model }
        return model.prefix(max / 2 - 1) + "…" + model.suffix(max / 2)
    }

    static func fellBack(from: ChatTarget, to: ChatTarget) -> String {
        "\(shortName(from))'s busy right now, so \(shortName(to)) answered instead."
    }

    static func countdown(_ t: ChatTarget, seconds: Int) -> String {
        "\(shortName(t)) is busy. Trying again in \(seconds) s."
    }

    static func waking(_ t: ChatTarget) -> String { "Waking up \(bareModel(t.model))…" }

    /// The message (and its one action) for a failed reply.
    static func error(_ e: AIError, target t: ChatTarget) -> (text: String, action: AIAction?) {
        let name = shortName(t)
        let local = t.placement != .cloud
        if e.code == AIError.outOfRoomCode { return (outOfRoom, .chooseModel) }
        switch e.kind {
        case .auth:
            let owner = t.provider.isCloud ? AICatalog.info(t.provider).name : serverName(t)
            return ("Your \(owner) key was rejected.", .openSettings)
        case .billing:
            let owner = AICatalog.info(t.provider).name
            let text = HTTPErrorRules.isSpendLimit(e.code) ? "Your \(owner) spend limit was reached."
                                                            : "Your \(owner) credit ran out."
            return (text, billingURL(t.provider).map(AIAction.openBilling))
        case .unreachable where local:
            return ("Couldn't reach \(serverName(t)). Is its server on?", .openGuide)
        case .unreachable:
            return ("Couldn't reach \(name). Check your connection.", nil)
        case .offline:
            return ("You're offline, and no local model is ready.", .openGuide)
        case .timeout:
            return ("\(local ? bareModel(t.model) : name) took too long to answer.", nil)
        case .server:
            return ("\(local ? serverName(t) : name) had a problem. Try again in a moment.", nil)
        case .rateLimited, .overloaded:
            return ("\(name) is still busy. Try again in a minute.", nil)
        case .badRequest where e.status == 404:
            return local ? ("\(t.model) isn't installed. Pick another model above the chat box.", .chooseModel)
                         : ("Model not found: \(t.model). Pick another one in Settings.", .openSettings)
        case .badRequest:
            return (e.message ?? "\(name) couldn't handle that message.", nil)
        case .refusal:
            return ("\(name) declined to answer this.", nil)
        case .cancelled, .interrupted:
            return ("", nil)
        }
    }

    /// The quiet line under a reply: fell back to a local model, a file read in part, old messages dropped,
    /// an answer cut at the token cap. Nil when there is nothing to say.
    static func replyNotes(fellBack: String?, built: Conversation.Built?, finish: FinishReason?) -> String? {
        var notes = fellBack.map { [$0] } ?? []
        if let built {
            notes += built.fileNotices
            if built.droppedMessages > 0 { notes.append(historyTrimmed) }
        }
        if finish == .length { notes.append(cutOff) }
        return notes.isEmpty ? nil : notes.joined(separator: " ")
    }

    static func billingURL(_ provider: AIProviderID) -> URL? {
        switch provider {
        case .openai: URL(string: "https://platform.openai.com/settings/organization/billing/overview")
        case .anthropic: URL(string: "https://console.anthropic.com/settings/billing")
        case .google: URL(string: "https://aistudio.google.com/")
        default: nil
        }
    }
}
```

- [ ] **Step 6: Run the tests**

Run: `bash scripts/test-ai-runner.sh`
Expected: every line `✓`, including:
- `✓ file dropped after the first turn joins the next message`;
- `✓ a file only on an earlier message: still File questions`, `✓ so the follow-up never reaches the cloud`, `✓ Retry keeps the route`, `✓ after a reset: Chat again`;
- `✓ Claude's request carries the cloud cap`, `✓ the local retry carries the local cap`;
- `✓ 500 → one local retry`, `✓ 429 and no local → countdown`, `✓ billing never falls back`, `✓ refusal never falls back`;
- `✓ cut before any text → a failed request, retried locally`, `✓ Stop after text keeps the partial reply`;
- `✓ all tokens spent thinking → out of room`, `✓ cut at the cap: the text is kept`, `✓ regenerating never removes the user message`;
- `✓ the marker really went to the provider` and `✓ no log line contains the marker`;
- then `All tests passed.` (about 15 s).

Then prove the route is pinned. In `Conversation.feature`, temporarily make it ignore the history: replace its body with `pendingFiles.isEmpty ? .chat : .files`, and run the script again.
Expected: `✗ the next message stays on File questions`, `✗ a file only on an earlier message: still File questions` and `✗ so the follow-up never reaches the cloud`, exit 1. Restore the body: `All tests passed.`

- [ ] **Step 7: Add the CI step**

In `.github/workflows/build.yml`, insert this step immediately before `- name: Test plan gauge` (after any `AI …` steps added by earlier tasks), at the same indentation:

```yaml
      - name: AI chat runner and log leak test
        run: bash scripts/test-ai-runner.sh
```

- [ ] **Step 8: Build the app**

Run: `cd NotchBuddy && xcodegen && xcodebuild -project NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug build 2>&1 | grep -E "error:|BUILD" ; cd ..`
Expected: `** BUILD SUCCEEDED **` and no `error:` line. New files under `Sources/` are picked up by `xcodegen`.

- [ ] **Step 9: Commit**

```bash
git add NotchBuddy/Sources/App/AI/Core/Conversation.swift \
    NotchBuddy/Sources/App/AI/Core/ChatRunner.swift \
    NotchBuddy/Sources/App/AI/Core/AIMessages.swift \
    tests/AIRunnerTests.swift \
    scripts/test-ai-runner.sh \
    .github/workflows/build.yml \
    NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -m "feat(ai): run a message with one local retry, keep files per turn, never log content

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---
### Task 9: Discovery and network monitor

**Files:**
- Create: `NotchBuddy/Sources/App/AI/Core/Discovery.swift`
- Create: `NotchBuddy/Sources/App/AI/Platform/NetworkMonitor.swift`
- Create: `tests/AIDiscoveryTests.swift`, `tests/AIPlatformTests.swift`
- Create: `scripts/test-ai-discovery.sh`, `scripts/test-ai-platform.sh`
- Modify: `.github/workflows/build.yml`

**Interfaces:**
- Consumes: `AICatalog` (Task 1); `HTTPStream.json`, `AILog` (Task 5); fake server personas (E1-0 Task 6).
- Produces:
  - `ProbeTarget {serverID, provider, name, baseURL, apiKey?}` and `ProbeTarget.defaults` (the four 127.0.0.1 servers);
  - `ServerStatus {running([ModelInfo]), off, notInstalled, outdated}`;
  - `DiscoveredServer {serverID, provider, name, baseURL, placement, status, apiKey?}` (`models`, `isReady`, `host`).
- Produces:
  - `Discovery.unknownServerName`, `Discovery.identify(_:nativeOK:models:installed:)` (pure);
  - `Discovery.run(_:installed:session:) async -> [DiscoveredServer]` (parallel, keeps order);
  - `Discovery.probe(_:installed:timeout:session:)`, `Discovery.probeSession`, `Discovery.installPaths`, `Discovery.isInstalled(_:)`;
  - `RedactsSecrets` conformance for `ProbeTarget` and `DiscoveredServer`.
- Produces: `NetworkMonitor.shared` with `start(onChange:)` and `isOnline`.
- Identification, resolved here, using only what the contract's personas serve:
  - **Ollama:** `/api/version` answers and `/v1/models` answers. If only `/api/version` answers, it is `outdated` ("Update Ollama to use it here.").
  - **llama.cpp:** `/health` answers and `/v1/models` answers. If only `/v1/models` answers on 11434 or 8080, it is "Local server (OpenAI-compatible)" (LocalAI on 8080).
  - **LM Studio and Jan:** `/v1/models` answers.
  - **Silent server:** "Not installed" when its app or binary isn't in the usual places, else "Server off".

- [ ] **Step 1: Write the failing test `tests/AIDiscoveryTests.swift`**

```swift
import Foundation

@main
@MainActor
enum AIDiscoveryTests {
    static func main() async {
        AILog.sink.replace { _ in }
        rules()
        await personas()
        await nothingRunning()
        T.finish()
    }

    static func target(_ p: AIProviderID, _ base: String = "http://127.0.0.1:1") -> ProbeTarget {
        ProbeTarget(serverID: p.rawValue, provider: p, name: AICatalog.info(p).name, baseURL: base)
    }

    static func rules() {
        T.section("Discovery.identify")
        func id(_ p: AIProviderID, _ native: Bool?, _ models: [String]?, installed: Bool = true) -> String {
            let r = Discovery.identify(target(p), nativeOK: native, models: models, installed: installed)
            let status: String = switch r.status {
            case .running(let m): "running \(m.map(\.id).joined(separator: ","))"
            case .off: "off"
            case .notInstalled: "not installed"
            case .outdated: "outdated"
            }
            return "\(r.provider.rawValue) \(r.name) \(status)"
        }
        T.check("Ollama", id(.ollama, true, ["qwen3.5:2b", "nomic-embed-text"]), "ollama Ollama running qwen3.5:2b")
        T.check("Ollama without /v1 is outdated", id(.ollama, true, nil), "ollama Ollama outdated")
        T.check("something else on 11434", id(.ollama, false, ["m"]), "custom Local server (OpenAI-compatible) running m")
        T.check("llama.cpp", id(.llamacpp, true, ["model.gguf"]), "llamacpp llama.cpp running model.gguf")
        T.check("LocalAI on 8080 (no /health)", id(.llamacpp, false, ["m"]), "custom Local server (OpenAI-compatible) running m")
        T.check("LM Studio", id(.lmstudio, nil, ["gemma-4-e2b"]), "lmstudio LM Studio running gemma-4-e2b")
        T.check("Jan", id(.jan, nil, ["llama3"]), "jan Jan running llama3")
        T.check("off but installed", id(.jan, nil, nil), "jan Jan off")
        T.check("not installed", id(.jan, nil, nil, installed: false), "jan Jan not installed")
        T.check("running with no models is not ready",
                Discovery.identify(target(.lmstudio), nativeOK: nil, models: [], installed: true).status, .running([]))
        let lan = DiscoveredServer(serverID: "custom-1", provider: .custom, name: "studio-pc", baseURL: "http://studio-pc.local:1234",
                                   placement: AICatalog.placement(forHost: "studio-pc.local"), status: .running([ModelInfo(id: "llama3")]))
        T.check("a LAN server is network", lan.placement, .network)
        T.check("its host for captions", lan.host, "studio-pc.local")
        var keyed = lan
        keyed.apiKey = "SECRET-LAN-KEY"
        let probe = ProbeTarget(serverID: "custom-1", provider: .custom, name: "studio-pc", baseURL: lan.baseURL,
                                apiKey: "SECRET-LAN-KEY")
        var dumped = ""
        dump(keyed, to: &dumped)
        dump(probe, to: &dumped)
        T.checkTrue("server keys never print", !"\(keyed) \(probe)".contains("SECRET") && !dumped.contains("SECRET"))
    }

    static func personas() async {
        T.section("Discovery.run against fake personas")
        let ollama = FakeServer(["--persona", "ollama"])
        let lmstudio = FakeServer(["--persona", "lmstudio"])
        let llamacpp = FakeServer(["--persona", "llamacpp"])
        let jan = FakeServer(["--persona", "jan"])
        let localAI = FakeServer()  // generic: /v1/models but no /health
        defer { [ollama, lmstudio, llamacpp, jan, localAI].forEach { $0.stop() } }
        let found = await Discovery.run([
            target(.ollama, ollama.base), target(.lmstudio, lmstudio.base), target(.llamacpp, llamacpp.base),
            target(.jan, jan.base), ProbeTarget(serverID: "llamacpp-2", provider: .llamacpp, name: "llama.cpp", baseURL: localAI.base),
        ], installed: { _ in true })
        T.check("names in order", found.map(\.name),
                ["Ollama", "LM Studio", "llama.cpp", "Jan", Discovery.unknownServerName])
        T.check("all ready", found.map(\.isReady), [true, true, true, true, true])
        T.check("embeddings filtered", found[0].models.map(\.id), ["llama3.2"])
        T.check("localhost is local", found[0].placement, .local)
    }

    static func nothingRunning() async {
        T.section("Discovery.run with nothing running")
        let targets = [AIProviderID.ollama, .lmstudio, .llamacpp, .jan].map { target($0, "http://127.0.0.1:\(closedPort())") }
        let start = Date()
        let found = await Discovery.run(targets, installed: { _ in false })
        let ms = Date().timeIntervalSince(start) * 1000
        T.check("everything reported missing", found.map(\.status), [.notInstalled, .notInstalled, .notInstalled, .notInstalled])
        T.checkTrue("finishes under 400 ms (took \(Int(ms)) ms)", ms < 400)
        T.check("the four defaults are on 127.0.0.1", ProbeTarget.defaults.map(\.baseURL),
                ["http://127.0.0.1:11434", "http://127.0.0.1:1234", "http://127.0.0.1:8080", "http://127.0.0.1:1337"])
    }
}
```

- [ ] **Step 2: Write `scripts/test-ai-discovery.sh`**

```bash
#!/usr/bin/env bash
# AI discovery: identification rules, fake server personas, and the 400 ms budget
# when nothing is running (all probes in parallel, 0.3 s each).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-ai-discovery.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs
swiftc -swift-version 6 \
    NotchBuddy/Sources/App/AI/Core/*.swift \
    NotchBuddy/Sources/App/AppLog.swift \
    tests/AITestSupport.swift tests/AIDiscoveryTests.swift \
    -o "$TEST_DIR/ai-discovery-tests"
"$TEST_DIR/ai-discovery-tests"
```

Run: `chmod +x scripts/test-ai-discovery.sh && bash scripts/test-ai-discovery.sh`
Expected: FAIL with `error: cannot find 'Discovery' in scope`.

- [ ] **Step 3: Write `NotchBuddy/Sources/App/AI/Core/Discovery.swift`**

```swift
import Foundation

/// A server to check: one of the four known local servers, or one the user added.
struct ProbeTarget: Sendable, Equatable {
    /// "ollama", "lmstudio", "llamacpp", "jan", or "custom-<24 hex digits>" (`CustomServer.newID()`).
    let serverID: String
    let provider: AIProviderID
    /// Display name (for custom servers, what the user typed or the host).
    let name: String
    let baseURL: String
    var apiKey: String? = nil

    /// The four servers checked automatically, on 127.0.0.1 only.
    static let defaults: [ProbeTarget] = [AIProviderID.ollama, .lmstudio, .llamacpp, .jan].map {
        let info = AICatalog.info($0)
        return ProbeTarget(serverID: $0.rawValue, provider: $0, name: info.name, baseURL: info.baseURL!)
    }
}

enum ServerStatus: Sendable, Equatable {
    case running([ModelInfo])
    case off
    case notInstalled
    /// Its own API answers but the OpenAI-compatible one doesn't (too old).
    case outdated
}

struct DiscoveredServer: Sendable, Equatable {
    let serverID: String
    /// `.custom` when an unexpected server answers on a known port.
    var provider: AIProviderID
    var name: String
    let baseURL: String
    var placement: AIPlacement
    var status: ServerStatus
    var apiKey: String? = nil

    var models: [ModelInfo] { if case .running(let m) = status { m } else { [] } }
    var isReady: Bool { !models.isEmpty }
    var host: String? { URL(string: baseURL)?.host }
}

enum Discovery {
    static let unknownServerName = "Local server (OpenAI-compatible)"

    /// Identification from what answered (pure, so every rule has a test).
    /// - nativeOK: the server's own check answered (`/api/version` with a version, `/health`); nil when it has none.
    /// - models: `/v1/models` IDs, nil when that call failed.
    static func identify(_ t: ProbeTarget, nativeOK: Bool?, models: [String]?,
                         installed: Bool) -> (provider: AIProviderID, name: String, status: ServerStatus) {
        let silent: ServerStatus = installed || t.provider == .custom ? .off : .notInstalled
        switch (t.provider, nativeOK, models) {
        case (.ollama, true?, nil):
            return (.ollama, t.name, .outdated)
        case (.ollama, true?, let ids?), (.llamacpp, true?, let ids?):
            return (t.provider, t.name, .running(chatModels(ids, t.provider)))
        case (.ollama, _, let ids?), (.llamacpp, _, let ids?):
            // LocalAI on 8080, or something else on 11434.
            return (.custom, unknownServerName, .running(chatModels(ids, .custom)))
        case (_, _, let ids?):
            return (t.provider, t.name, .running(chatModels(ids, t.provider)))
        default:
            return (t.provider, t.name, silent)
        }
    }

    private static func chatModels(_ ids: [String], _ provider: AIProviderID) -> [ModelInfo] {
        AICatalog.filterModels(ids, for: provider).map { ModelInfo(id: $0) }
    }

    /// All targets in parallel, 0.3 s per request; results keep the targets' order.
    static func run(_ targets: [ProbeTarget], installed: @escaping @Sendable (AIProviderID) -> Bool = isInstalled,
                    session: URLSession = probeSession) async -> [DiscoveredServer] {
        let started = Date()
        let found = await withTaskGroup(of: (Int, DiscoveredServer).self) { group in
            for (i, t) in targets.enumerated() {
                group.addTask { (i, await probe(t, installed: installed(t.provider), session: session)) }
            }
            var out: [(Int, DiscoveredServer)] = []
            for await r in group { out.append(r) }
            return out.sorted { $0.0 < $1.0 }.map(\.1)
        }
        AILog.record(.discovery(found: found.filter(\.isReady).map(\.provider), ms: Int(Date().timeIntervalSince(started) * 1000)))
        return found
    }

    /// One server. `timeout` is 0.3 s for discovery; Add server… allows a sleepy LAN host 5 s.
    static func probe(_ t: ProbeTarget, installed: Bool, timeout: TimeInterval = AICatalog.Timeouts.probe,
                      session: URLSession = probeSession) async -> DiscoveredServer {
        let nativePath: String? = t.provider == .ollama ? "/api/version" : (t.provider == .llamacpp ? "/health" : nil)
        async let native: Bool? = nativePath == nil ? nil : nativeAnswers(t, path: nativePath!, timeout: timeout, session: session)
        async let models = modelIDs(t, timeout: timeout, session: session)
        let (provider, name, status) = identify(t, nativeOK: await native, models: await models, installed: installed)
        return DiscoveredServer(serverID: t.serverID, provider: provider, name: name, baseURL: t.baseURL,
                                placement: AICatalog.placement(forHost: URL(string: t.baseURL)?.host),
                                status: status, apiKey: t.apiKey)
    }

    static let probeSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = AICatalog.Timeouts.probe
        config.timeoutIntervalForResource = AICatalog.Timeouts.probe
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private static func request(_ t: ProbeTarget, _ path: String, timeout: TimeInterval) -> URLRequest? {
        guard let url = URL(string: t.baseURL + path) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        if let key = t.apiKey { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        return req
    }

    private static func nativeAnswers(_ t: ProbeTarget, path: String, timeout: TimeInterval,
                                      session: URLSession) async -> Bool {
        guard let req = request(t, path, timeout: timeout),
              let json = try? await HTTPStream.json(req, session: session) as? [String: Any] else { return false }
        return path == "/api/version" ? json["version"] != nil : true
    }

    private static func modelIDs(_ t: ProbeTarget, timeout: TimeInterval, session: URLSession) async -> [String]? {
        guard let req = request(t, "/v1/models", timeout: timeout),
              let json = try? await HTTPStream.json(req, session: session) as? [String: Any],
              let rows = json["data"] as? [[String: Any]] else { return nil }
        return rows.compactMap { $0["id"] as? String }
    }

    /// Where each server's app or binary usually lives ("○ Not installed" vs "○ Server off").
    static let installPaths: [AIProviderID: [String]] = [
        .ollama: ["/Applications/Ollama.app", "~/Applications/Ollama.app", "/opt/homebrew/bin/ollama", "/usr/local/bin/ollama"],
        .lmstudio: ["/Applications/LM Studio.app", "~/Applications/LM Studio.app", "~/.lmstudio/bin/lms"],
        .llamacpp: ["/opt/homebrew/bin/llama-server", "/usr/local/bin/llama-server"],
        .jan: ["/Applications/Jan.app", "~/Applications/Jan.app"],
    ]

    @Sendable static func isInstalled(_ provider: AIProviderID) -> Bool {
        (installPaths[provider] ?? []).contains {
            FileManager.default.fileExists(atPath: NSString(string: $0).expandingTildeInPath)
        }
    }
}

extension ProbeTarget: RedactsSecrets {
    var redactedSummary: String { "ProbeTarget(\(serverID), \(baseURL), key: \(Self.keyMark(apiKey)))" }
}

extension DiscoveredServer: RedactsSecrets {
    var redactedSummary: String {
        "DiscoveredServer(\(serverID), \(name), \(baseURL), \(placement.rawValue), ready: \(isReady), key: \(Self.keyMark(apiKey)))"
    }
}
```

Run: `bash scripts/test-ai-discovery.sh`
Expected:
- every identification rule `✓`;
- `✓ names in order` and `✓ all ready` against the five fake servers;
- `✓ finishes under 400 ms (took N ms)`, then `All tests passed.`

- [ ] **Step 4: Write the failing test `tests/AIPlatformTests.swift`**

```swift
import Foundation

@main
@MainActor
enum AIPlatformTests {
    static func main() async {
        AILog.sink.replace { _ in }
        await network()
        T.finish()
    }

    static func network() async {
        T.section("NetworkMonitor")
        let changed = Flag()
        NetworkMonitor.shared.start { _ in changed.set() }
        for _ in 0..<40 where !changed.value { try? await Task.sleep(nanoseconds: 50_000_000) }
        T.checkTrue("reports the path once started", changed.value)
        T.checkTrue("this machine is online", NetworkMonitor.shared.isOnline)
    }

}

final class Flag: @unchecked Sendable {
    private let lock = NSLock()
    private var on = false
    func set() { lock.withLock { on = true } }
    var value: Bool { lock.withLock { on } }
}
```

- [ ] **Step 5: Write `scripts/test-ai-platform.sh`**

```bash
#!/usr/bin/env bash
# AI platform files (Network, and FoundationModels from Task 10) built for the macOS 15 floor:
# a missing availability guard fails the build.
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-ai-platform.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs
swiftc -swift-version 6 -target "$(uname -m)-apple-macos15.0" -warnings-as-errors \
    NotchBuddy/Sources/App/AI/Core/*.swift \
    NotchBuddy/Sources/App/AI/Platform/NetworkMonitor.swift \
    NotchBuddy/Sources/App/AppLog.swift \
    tests/AITestSupport.swift tests/AIPlatformTests.swift \
    -o "$TEST_DIR/ai-platform-tests"
"$TEST_DIR/ai-platform-tests"
```

Run: `chmod +x scripts/test-ai-platform.sh && bash scripts/test-ai-platform.sh`
Expected: FAIL with `error: error opening input file 'NotchBuddy/Sources/App/AI/Platform/NetworkMonitor.swift' (No such file or directory)`.

- [ ] **Step 6: Write `NotchBuddy/Sources/App/AI/Platform/NetworkMonitor.swift`**

```swift
import Foundation
import Network

/// Tells the router when the Mac is offline, so Auto goes straight to a local model instead
/// of waiting for the cloud to time out. Event-driven: no polling, no CPU while idle.
final class NetworkMonitor: @unchecked Sendable {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var online = true
    private var started = false

    var isOnline: Bool { lock.withLock { online } }

    /// `onChange` runs on a background queue with the new state.
    func start(onChange: @escaping @Sendable (Bool) -> Void = { _ in }) {
        let first = lock.withLock { () -> Bool in
            defer { started = true }
            return !started
        }
        guard first else { return }
        monitor.pathUpdateHandler = { [weak self] path in
            let up = path.status == .satisfied
            self?.lock.withLock { self?.online = up }
            onChange(up)
        }
        monitor.start(queue: DispatchQueue(label: "io.github.aikusan.notchmeow.network"))
    }
}
```

Run: `bash scripts/test-ai-platform.sh`
Expected: `✓ reports the path once started`, `✓ this machine is online`, `All tests passed.`

- [ ] **Step 7: Add the CI steps**

In `.github/workflows/build.yml`, insert this step immediately before `- name: Test plan gauge` (after any `AI …` steps added by earlier tasks), at the same indentation:

```yaml
      - name: AI discovery
        run: bash scripts/test-ai-discovery.sh
```

Then, right after it:

```yaml
      - name: AI platform (macOS 15 floor, weak linking)
        run: bash scripts/test-ai-platform.sh
```

- [ ] **Step 8: Build the app**

Run: `cd NotchBuddy && xcodegen && xcodebuild -project NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug build 2>&1 | grep -E "error:|BUILD" ; cd ..`
Expected: `** BUILD SUCCEEDED **` and no `error:` line. New files under `Sources/` are picked up by `xcodegen`.

- [ ] **Step 9: Commit**

```bash
git add NotchBuddy/Sources/App/AI/Core/Discovery.swift \
    NotchBuddy/Sources/App/AI/Platform/NetworkMonitor.swift \
    tests/AIDiscoveryTests.swift \
    tests/AIPlatformTests.swift \
    scripts/test-ai-discovery.sh \
    scripts/test-ai-platform.sh \
    .github/workflows/build.yml \
    NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -m "feat(ai): find local model servers in parallel and watch the network

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---
### Task 10: Apple on-device provider and the weak-link check

**Files:**
- Create: `NotchBuddy/Sources/App/AI/Platform/AppleOnDeviceProvider.swift`
- Create: `scripts/check-app-binary.sh`, `scripts/check-sdk.sh`
- Modify: `tests/AIPlatformTests.swift`, `scripts/test-ai-platform.sh`, `NotchBuddy/project.yml`, `.github/workflows/build.yml`

**Interfaces:**
- Consumes: `ModelProvider`, `ChatRequest`, `AIError` (Task 1); `OpenAICompatibleProvider.plainText`, `AILog`, `HTTPErrorRules.transportKind` (Tasks 2, 5).
- Produces:
  - `AppleOnDevice.Status {ready, downloading, turnOn, hidden}` with `line` ("Ready", "Downloading", "Turn on Apple Intelligence in System Settings", or nil);
  - `AppleOnDevice.status()`, `AppleOnDevice.provider() -> (any ModelProvider)?` (nil before macOS 26), `AppleOnDevice.contextTokens()`;
  - `@available(macOS 26, *) AppleOnDeviceProvider`.
- SDK facts checked against the macOS 27 SDK:
  - `SystemLanguageModel.contextSize` is `@backDeployed` to 26.0 and returns 4,096 before 27;
  - `tokenCount(for:)` needs 26.4, so this plan sizes with the 3.5 chars/token estimate;
  - `GenerationError` is deprecated in 27 but still the 26.0 API;
  - `streamResponse` yields cumulative snapshots: the provider sends the differences.
- **Weak linking:** every FoundationModels use sits behind `#available(macOS 26, *)`, so the linker weak-links the framework on its own (checked: `LC_LOAD_WEAK_DYLIB` in Debug and Release). No explicit `-weak_framework` flag is added, because it would fail to link on an SDK without FoundationModels. `scripts/check-app-binary.sh` fails CI if the link ever becomes strong.
- **The SDK must have FoundationModels.** Without the macOS 26 SDK, `#if canImport(FoundationModels)` compiles the Apple provider out, and nothing would say so. `.github/workflows/build.yml` runs on `macos-latest` and pins no Xcode, so `scripts/check-sdk.sh` (run first by `test-ai-platform.sh`) and `check-app-binary.sh … release` (run after the CI build) fail loudly when the framework is missing. If `macos-latest` ever ships an older Xcode, pin the runner (`runs-on: macos-26`) or select Xcode 26+ with `xcode-select -s`. Local builds already need Xcode 26 or later (`xcodeVersion: "27.0"` in `project.yml`).

- [ ] **Step 1: Add the failing Apple test**

In `tests/AIPlatformTests.swift`, call it from `main()` after `await network()`:

```swift
        await apple()
```

Then add this function after `network()`:

```swift
    static func apple() async {
        T.section("Apple on-device")
        let status = AppleOnDevice.status()
        print("  · status on this Mac: \(status) (\(status.line ?? "hidden"))")
        T.checkTrue("context is at least 4,096 tokens", AppleOnDevice.contextTokens() >= 4096)
        if #unavailable(macOS 26) {
            T.checkTrue("no provider before macOS 26", AppleOnDevice.provider() == nil)
        }
        // Real generation is opt-in (CI runners have no Apple Intelligence): NM_TEST_APPLE=1.
        guard ProcessInfo.processInfo.environment["NM_TEST_APPLE"] == "1", status == .ready,
              let provider = AppleOnDevice.provider() else { return }
        var acc = ReplyAccumulator(stripsThinkBlocks: false)
        let request = ChatRequest(model: "system", system: "Answer in one word.",
                                  messages: [.init(role: .user, parts: [.text("Say hello.")])])
        do {
            for try await chunk in provider.stream(request) { acc.add(chunk) }
        } catch {
            T.checkTrue("Apple generation failed: \(error)", false)
        }
        T.checkTrue("Apple's model answered (\(acc.text))", !acc.text.isEmpty)
    }
```

Write `scripts/check-sdk.sh`. The Apple provider is compiled only when the SDK has FoundationModels; on an older Xcode it would silently disappear:

```bash
#!/usr/bin/env bash
# Apple's on-device provider only compiles with the macOS 26 SDK. On an older Xcode,
# `#if canImport(FoundationModels)` quietly compiles it out and the app would ship without it.
set -euo pipefail
SDK="$(xcrun --sdk macosx --show-sdk-path)"
VERSION="$(xcrun --sdk macosx --show-sdk-version)"
if [ ! -d "$SDK/System/Library/Frameworks/FoundationModels.framework" ]; then
    echo "✗ The active macOS SDK ($VERSION) has no FoundationModels: the Apple on-device provider would be compiled out." >&2
    echo "  Use Xcode 26 or later: pin the runner (runs-on: macos-26) or select it with xcode-select -s." >&2
    exit 1
fi
echo "✓ macOS SDK $VERSION has FoundationModels"
```

Replace `scripts/test-ai-platform.sh` with this version. It checks the SDK first, adds the provider, and checks the weak link on the test binary:

```bash
#!/usr/bin/env bash
# AI platform files (Network, FoundationModels) built for the macOS 15 floor: a missing
# availability guard fails the build, and FoundationModels must be weak-linked.
# Real Apple generation is opt-in: NM_TEST_APPLE=1 bash scripts/test-ai-platform.sh
set -euo pipefail
cd "$(dirname "$0")/.."
bash scripts/check-sdk.sh
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-ai-platform.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs
swiftc -swift-version 6 -target "$(uname -m)-apple-macos15.0" -warnings-as-errors \
    NotchBuddy/Sources/App/AI/Core/*.swift \
    NotchBuddy/Sources/App/AI/Platform/NetworkMonitor.swift \
    NotchBuddy/Sources/App/AI/Platform/AppleOnDeviceProvider.swift \
    NotchBuddy/Sources/App/AppLog.swift \
    tests/AITestSupport.swift tests/AIPlatformTests.swift \
    -o "$TEST_DIR/ai-platform-tests"
if otool -l "$TEST_DIR/ai-platform-tests" | grep -A2 'LC_LOAD_DYLIB$' | grep -q FoundationModels; then
    echo "FoundationModels is strongly linked: the app would not launch on macOS 15" >&2
    exit 1
fi
"$TEST_DIR/ai-platform-tests"
```

Run: `chmod +x scripts/check-sdk.sh && bash scripts/test-ai-platform.sh`
Expected: `✓ macOS SDK … has FoundationModels`, then FAIL with `error: error opening input file 'NotchBuddy/Sources/App/AI/Platform/AppleOnDeviceProvider.swift' (No such file or directory)`.

- [ ] **Step 2: Write `NotchBuddy/Sources/App/AI/Platform/AppleOnDeviceProvider.swift`**

```swift
import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple's on-device model (macOS 26+, Apple Intelligence on). FoundationModels is weak-linked
/// (`project.yml`), so on macOS 15 none of this runs and the app still launches.
enum AppleOnDevice {
    enum Status: Sendable, Equatable {
        case ready, downloading, turnOn, hidden

        /// The one line in Settings; nil when the Mac isn't eligible.
        var line: String? {
            switch self {
            case .ready: "Ready"
            case .downloading: "Downloading"
            case .turnOn: "Turn on Apple Intelligence in System Settings"
            case .hidden: nil
            }
        }
    }

    static func status() -> Status {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return .ready
            case .unavailable(.modelNotReady): return .downloading
            case .unavailable(.appleIntelligenceNotEnabled): return .turnOn
            default: return .hidden
            }
        }
        #endif
        return .hidden
    }

    /// The provider, or nil before macOS 26.
    static func provider() -> (any ModelProvider)? {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) { return AppleOnDeviceProvider() }
        #endif
        return nil
    }

    /// Apple's context (4,096 tokens before macOS 27, maybe 8,192 after); 4,096 when unavailable.
    static func contextTokens() -> Int {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) { return SystemLanguageModel.default.contextSize }
        #endif
        return AICatalog.Limits.defaultLocalContextTokens
    }
}

#if canImport(FoundationModels)
@available(macOS 26, *)
struct AppleOnDeviceProvider: ModelProvider {
    let id = AIProviderID.apple
    let displayName = "Apple on-device"
    let placement = AIPlacement.local
    /// Wait before the single retry after `rateLimited`.
    var rateLimitRetryDelay: TimeInterval = 1

    func listModels() async throws -> [ModelInfo] {
        [ModelInfo(id: "system", label: "Apple on-device", contextTokens: SystemLanguageModel.default.contextSize)]
    }

    func prewarm(model: String) async {
        LanguageModelSession(model: .default).prewarm()
    }

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
        AILog.record(.request(id, model: "system", placement: placement))
        let delay = rateLimitRetryDelay
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    do {
                        try await Self.generate(request, into: continuation)
                    } catch let e as AIError where e.kind == .rateLimited {
                        // Apple's limits for accessory apps are unclear: one quiet retry, then a temporary failure.
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        try await Self.generate(request, into: continuation)
                    }
                    continuation.finish()
                } catch {
                    let failure = (error as? AIError) ?? AIError(kind: HTTPErrorRules.transportKind(error))
                    AILog.record(.failure(.apple, kind: failure.kind, status: nil, code: nil, requestID: nil))
                    continuation.finish(throwing: failure)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Rebuilds the conversation as a transcript (every turn is resent, like the other providers).
    private static func generate(_ request: ChatRequest,
                                 into continuation: AsyncThrowingStream<ChatChunk, Error>.Continuation) async throws {
        func text(_ m: ChatRequest.Message) -> String {
            m.parts.map(OpenAICompatibleProvider.plainText).filter { !$0.isEmpty }.joined(separator: "\n\n")
        }
        func segment(_ s: String) -> [Transcript.Segment] { [.text(Transcript.TextSegment(content: s))] }
        var entries: [Transcript.Entry] = [.instructions(Transcript.Instructions(segments: segment(request.system),
                                                                                  toolDefinitions: []))]
        for m in request.messages.dropLast() {
            entries.append(m.role == .user ? .prompt(Transcript.Prompt(segments: segment(text(m))))
                                           : .response(Transcript.Response(assetIDs: [], segments: segment(text(m)))))
        }
        let session = LanguageModelSession(model: .default, transcript: Transcript(entries: entries))
        var sent = ""
        do {
            for try await snapshot in session.streamResponse(to: request.messages.last.map(text) ?? "") {
                let full = snapshot.content
                guard full.count > sent.count, full.hasPrefix(sent) else { continue }
                continuation.yield(.text(String(full.dropFirst(sent.count))))
                sent = full
            }
            continuation.yield(.finish(.stop))
        } catch let error as LanguageModelSession.GenerationError {
            throw map(error, sentText: !sent.isEmpty)
        }
    }

    private static func map(_ error: LanguageModelSession.GenerationError, sentText: Bool) -> AIError {
        switch error {
        case .rateLimited: return AIError(kind: sentText ? .interrupted : .rateLimited)
        case .guardrailViolation, .refusal: return AIError(kind: .refusal)
        case .exceededContextWindowSize: return AIError(kind: .badRequest, message: "This chat is too long for Apple's model.")
        case .assetsUnavailable: return AIError(kind: .unreachable)
        default: return AIError(kind: .server)
        }
    }
}
#endif
```

- [ ] **Step 3: Run the platform tests**

Run: `bash scripts/test-ai-platform.sh`
Expected:
- the build has no warnings: `-warnings-as-errors` is on and the target is macOS 15;
- `· status on this Mac: …`, `✓ context is at least 4,096 tokens`, `All tests passed.`

On a Mac with Apple Intelligence on, also run `NM_TEST_APPLE=1 bash scripts/test-ai-platform.sh`.
Expected: `✓ Apple's model answered (…)`.

- [ ] **Step 4: Write `scripts/check-app-binary.sh`**

```bash
#!/usr/bin/env bash
# Checks a built NotchMeow.app: FoundationModels weak-linked (the app must launch on macOS 15),
# and, for Release builds, the Debug-only AI base-URL override compiled out.
# `release` is the CI check: it also fails when FoundationModels isn't linked at all, which means the
# SDK had none and the Apple on-device provider was silently compiled out.
# Usage: bash scripts/check-app-binary.sh path/to/NotchMeow.app [release]
set -euo pipefail
APP="$1"
BINS=("$APP"/Contents/MacOS/NotchMeow*)   # Debug builds put the code in NotchMeow.debug.dylib
[ -e "${BINS[0]}" ] || { echo "No binary in $APP/Contents/MacOS" >&2; exit 1; }
weak=0
for BIN in "${BINS[@]}"; do
    if otool -l "$BIN" | grep -A2 'LC_LOAD_DYLIB$' | grep -q FoundationModels; then
        echo "✗ $(basename "$BIN") links FoundationModels strongly: NotchMeow would not launch on macOS 15" >&2
        exit 1
    fi
    if otool -l "$BIN" | grep -A2 'LC_LOAD_WEAK_DYLIB' | grep -q FoundationModels; then weak=1; fi
    if [ "${2:-}" = "release" ] && strings "$BIN" | grep -q NM_AI_BASE_URL_OVERRIDE; then
        echo "✗ $(basename "$BIN") still reads NM_AI_BASE_URL_OVERRIDE" >&2
        exit 1
    fi
done
if [ "$weak" = 1 ]; then
    echo "✓ FoundationModels is weak-linked"
elif [ "${2:-}" = "release" ]; then
    echo "✗ FoundationModels is not linked at all: the Apple on-device provider was compiled out. Build with Xcode 26 or later (scripts/check-sdk.sh)." >&2
    exit 1
else
    echo "· FoundationModels not linked (this SDK has none: Apple on-device is compiled out)"
fi
[ "${2:-}" = "release" ] && echo "✓ No AI base-URL override in this Release build"
exit 0
```

- [ ] **Step 5: Note the weak link in `NotchBuddy/project.yml`**

Under `settings: base:`, after `OTHER_SWIFT_FLAGS: "-strict-concurrency=complete"`, add:

```yaml
    # FoundationModels (macOS 26+) is weak-linked automatically because every use is behind
    # `#available(macOS 26, *)`; scripts/check-app-binary.sh fails the build if that ever changes.
```

- [ ] **Step 6: Check it in CI**

In `.github/workflows/build.yml`, give the `Build` step a derived-data path by adding this line after `-configuration Release \`:

```yaml
            -derivedDataPath NotchBuddy/build \
```

Then append this step at the end of the job (after `Build`):

```yaml

      - name: Check app binary (weak FoundationModels, no Debug override)
        run: bash scripts/check-app-binary.sh NotchBuddy/build/Build/Products/Release/NotchMeow.app release
```

(`NotchBuddy/build/` is already in `.gitignore`.) The `AI platform` step added in Task 9 now also runs `scripts/check-sdk.sh` first, so a runner without the macOS 26 SDK fails there, before the build.

- [ ] **Step 7: Verify both configurations locally**

Run:
```bash
chmod +x scripts/check-app-binary.sh
cd NotchBuddy && xcodegen && xcodebuild -project NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Release -derivedDataPath build build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | grep -E "error:|BUILD"; cd ..
bash scripts/check-app-binary.sh NotchBuddy/build/Build/Products/Release/NotchMeow.app release
cd NotchBuddy && xcodebuild -project NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath build build 2>&1 | grep -E "error:|BUILD"; cd ..
bash scripts/check-app-binary.sh NotchBuddy/build/Build/Products/Debug/NotchMeow.app
```
Expected: `** BUILD SUCCEEDED **` twice, then:
- Release: `✓ FoundationModels is weak-linked` and `✓ No AI base-URL override in this Release build`;
- Debug: `✓ FoundationModels is weak-linked`, where the code lives in `NotchMeow.debug.dylib`.

- [ ] **Step 8: Commit**

```bash
git add NotchBuddy/Sources/App/AI/Platform/AppleOnDeviceProvider.swift \
    scripts/check-app-binary.sh \
    scripts/check-sdk.sh \
    tests/AIPlatformTests.swift \
    scripts/test-ai-platform.sh \
    NotchBuddy/project.yml \
    .github/workflows/build.yml \
    NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -m "feat(ai): add Apple on-device and check FoundationModels stays weak-linked

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---
### Task 11: Chat on the router

**Files:**
- Create: `NotchBuddy/Sources/App/AI/Core/ProviderFactory.swift`
- Create: `NotchBuddy/Sources/App/AI/AIService.swift`
- Create: `tests/AISettingsTests.swift`, `scripts/test-ai-settings.sh`
- Modify: `NotchBuddy/Sources/App/IslandTypes.swift` (`ChatProvider`)
- Modify: `NotchBuddy/Sources/App/AppState.swift` (AI routing state, migration, `ChatMessage`)
- Modify: `NotchBuddy/Sources/App/ClaudeService.swift` (chat through the router; `search()` uses the catalog web search)
- Modify: `NotchBuddy/Sources/App/FileDropView.swift`, `NotchBuddy/Sources/App/AppDelegate.swift`
- Modify: `NotchBuddy/Sources/App/IslandViewContent.swift` (model chip, picker, AI pills)
- Modify: `.github/workflows/build.yml`

**Interfaces:**
- Consumes: everything from Tasks 1–10.
- Produces (Core):
  - `CustomServer {id, name, baseURL}` with `newID()` (`custom-` plus 24 lowercase hex digits), `isValidID(_:)` (`^[a-z0-9-]{1,32}$`, the contract's server ID rule), `idPrefix` (`"custom-"`) and `keychainAccount` (`custom-server-key.<id>`: the catalog's `custom-server-key` is a prefix, one Keychain item per server, any number of servers);
  - `ProviderFactory {keys, servers: [String: ServerAddress], cloudOverride, apple, appleContextTokens}` with `make(_:)` and `details(_:) async -> (vision, contextTokens)`. It and `ServerAddress` are `RedactsSecrets`;
  - `UnavailableProvider`;
  - `AISettingsMigration.migrate(_ old: [String: String], makeID:) -> Result {choices, customServers, localModels}`.
- Produces (`AppState`):
  - persisted: `aiChoices: [String: FeatureSetting]`, `preferredCloud: AIProviderID`, `lastUsedLocal: ModelRef?`, `customServers`, `localModelMemory: [serverID: model]`;
  - live: `localServers: [DiscoveredServer]`, `appleStatus`, `isOnline`, `chatNotice: ChatNotice?`, `chatStreaming`, `dropReaderLine`, `dropRejected`, `noteAction: NoteAction?`;
  - `choice(for:)`, `setChoice(_:for:)`, `remember(_:)`;
  - `fetchedProviderModels: [AIProviderID: [ModelInfo]]` and `fetchModelsIfNeeded(for: AIProviderID)` (cloud only).
- Kept until Task 13: `chatProvider`, `ollamaServerURL` and `lmstudioServerURL`, which the old Settings still reads. Nothing routes on them any more.
- Removed: `activeChatModel`, `ollamaChatModel`, `lmstudioChatModel`, `ClaudeService.fetchGoogleModels`, `fetchOpenAIModels` and `chatOpenAICompatible`.
- Produces: `ChatMessage {…, caption?, sources: [Citation], notice?, interrupted}`, `ChatNotice {text, cancellable}`, `NoteAction {message, action: AIAction, markdown}`.
- Produces (`AIService.shared`, MainActor):
  - setup: `start()` (network monitor, Keychain preload, then the first discovery when `AppState.mode` first becomes `.expanded`), `discover() async`;
  - keys and models: `key(_:)`, `cloudKeys`, `cloudModel(_:)`, `localModel(_:)`, `localReady()`, `routeInput(_:)`;
  - targets: `target(_:model:placement:serverID:)`, `primaryTarget(_:)`, `target(_: LocalCandidate)`, `resolve(_:) -> (primary?, fallback?)`;
  - UI text: `chip(_:) -> (label, accentHex)`, `resolutionLine(_:)`;
  - providers: `freshLocalTarget(for:) async`, `factory()`, `prewarm(_:)`, `listCloudModels(_:key:) async`;
  - `Notification.Name.botReject`.
- Produces (`ClaudeService.shared`):
  - `currentFeature` (`Conversation.feature`: File questions once a file is in the conversation), `clearConversation(state:)` (still called on every drop and window attach, and it resets the route), `prepareAttachment(url:state:)`;
  - `send(query:context:state:)`, `stop()`, `chat(query:context:state:isRetry:) async` (adds the user message, then the private `reply(query:context:addedUserTurn:isRetry:state:)`), `continueReply(state:)`;
  - `retryLast(state:)`, which regenerates: it does nothing while a reply streams, asks `Conversation.regenerate()` for the user message (which drops only the answer), and calls `reply` with `addedUserTurn: false`, so a failure never removes the user's message.
- Produces: `ChatProvider` gains `llamacpp`, `jan`, `apple` and `custom`; `init(_ id: AIProviderID)`, `providerID`, and `pillID: String?` (nil for the new four).

- [ ] **Step 1: Write the failing settings test `tests/AISettingsTests.swift`**

```swift
import Foundation

@main
@MainActor
enum AISettingsTests {
    static func main() async {
        migration()
        factory()
        await details()
        T.finish()
    }

    static func migration() {
        T.section("AISettingsMigration")
        var n = 0
        func id() -> String { n += 1; return "custom-\(n)" }
        T.check("nothing set: Auto everywhere", AISettingsMigration.migrate([:], makeID: id), .init())
        T.check("Anthropic (the old default) becomes Auto",
                AISettingsMigration.migrate(["chatProvider": "anthropic"], makeID: id).choices, [:])
        T.check("OpenAI stays chosen with its model",
                AISettingsMigration.migrate(["chatProvider": "openai", "openAIChatModel": "gpt-6-luna"], makeID: id).choices,
                ["chat": .explicit(ModelRef(provider: .openai, model: "gpt-6-luna"))])
        let ollama = AISettingsMigration.migrate(["chatProvider": "ollama", "ollamaServerURL": "http://127.0.0.1:11434/",
                                                  "ollamaChatModel": "qwen3.5:2b"], makeID: id)
        T.check("default Ollama URL needs no added server", ollama.customServers, [])
        T.check("Ollama stays chosen", ollama.choices, ["chat": .explicit(ModelRef(provider: .ollama, model: "qwen3.5:2b"))])
        T.check("its model is remembered", ollama.localModels, ["ollama": "qwen3.5:2b"])
        n = 0
        let lan = AISettingsMigration.migrate(["chatProvider": "lmstudio", "lmstudioServerURL": "http://studio-pc.local:1234/v1",
                                               "lmstudioChatModel": "gemma-4-e2b"], makeID: id)
        T.check("an LM Studio on another host becomes an added server",
                lan.customServers, [CustomServer(id: "custom-1", name: "LM Studio", baseURL: "http://studio-pc.local:1234")])
        T.check("and the chat points at it",
                lan.choices, ["chat": .explicit(ModelRef(provider: .custom, model: "gemma-4-e2b", serverID: "custom-1"))])
        T.check("a local choice without a model falls back to Auto",
                AISettingsMigration.migrate(["chatProvider": "ollama"], makeID: id).choices, [:])

        T.section("CustomServer IDs and Keychain items")
        let ids = (0..<200).map { _ in CustomServer.newID() }
        T.checkTrue("generated IDs match ^[a-z0-9-]{1,32}$", ids.allSatisfy(CustomServer.isValidID))
        T.check("and are unique", Set(ids).count, 200)
        let migrated = AISettingsMigration.migrate(["chatProvider": "lmstudio", "lmstudioServerURL": "http://studio-pc.local:1234",
                                                    "lmstudioChatModel": "m"])
        T.check("the migration's own IDs are valid", migrated.customServers.map { CustomServer.isValidID($0.id) }, [true])
        T.check("valid IDs", ["a", "custom-1", String(repeating: "a", count: 32)].map(CustomServer.isValidID), [true, true, true])
        T.check("invalid IDs: empty, uppercase, colon, dot, slash, non-ASCII, 33 characters, space",
                ["", "Custom", "custom:1", "a.b", "a/../x", "é", String(repeating: "a", count: 33), "a b"].map(CustomServer.isValidID),
                Array(repeating: false, count: 8))
        T.check("a server's Keychain item", CustomServer(id: "custom-1", name: "n", baseURL: "u").keychainAccount,
                "custom-server-key.custom-1")
        T.check("two servers, two Keychain items",
                Set(["custom-1", "custom-2"].map { CustomServer(id: $0, name: "n", baseURL: "u").keychainAccount }).count, 2)
    }

    static func factory() {
        T.section("ProviderFactory")
        let f = ProviderFactory(keys: [.anthropic: "SECRET-A", .openai: "SECRET-O", .google: "SECRET-G"],
                                servers: ["custom-1": .init(baseURL: "http://studio-pc.local:1234", key: "SECRET-K")])
        T.checkTrue("Anthropic", f.make(ChatTarget(provider: .anthropic, model: "m", placement: .cloud)) is AnthropicProvider)
        T.checkTrue("OpenAI", f.make(ChatTarget(provider: .openai, model: "m", placement: .cloud)) is OpenAIProvider)
        let google = f.make(ChatTarget(provider: .google, model: "m", placement: .cloud)) as? OpenAICompatibleProvider
        T.check("Google path", google.map { $0.baseURL + $0.chatPath },
                "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")
        let custom = f.make(ChatTarget(provider: .custom, model: "m", placement: .network, serverID: "custom-1",
                                       host: "studio-pc.local")) as? OpenAICompatibleProvider
        T.check("added server URL", custom?.baseURL, "http://studio-pc.local:1234")
        T.check("added server key", custom?.apiKey, "SECRET-K")
        T.check("added server is network", custom?.placement, .network)
        let ollama = f.make(ChatTarget(provider: .ollama, model: "m", placement: .local)) as? OpenAICompatibleProvider
        T.check("default Ollama URL", ollama?.baseURL, "http://127.0.0.1:11434")
        T.check("no Apple model → unavailable", f.make(ChatTarget(provider: .apple, model: "system", placement: .local)).id, .apple)

        var debug = f
        debug.cloudOverride = "http://127.0.0.1:9"
        let redirected = debug.make(ChatTarget(provider: .google, model: "m", placement: .cloud)) as? OpenAICompatibleProvider
        T.check("override keeps /v1 paths for Google", redirected.map { $0.baseURL + $0.chatPath },
                "http://127.0.0.1:9/v1/chat/completions")
        var dumped = ""
        dump(f, to: &dumped)
        T.checkTrue("factory keys never print", !"\(f)".contains("SECRET") && !dumped.contains("SECRET")
                    && !String(reflecting: f.servers["custom-1"]!).contains("SECRET"))
        T.check("override moves Anthropic", (debug.make(ChatTarget(provider: .anthropic, model: "m", placement: .cloud))
                                              as? AnthropicProvider)?.baseURL, "http://127.0.0.1:9")
    }

    static func details() async {
        T.section("ProviderFactory.details")
        let f = ProviderFactory(appleContextTokens: 8192)
        T.check("cloud reads images", await f.details(ChatTarget(provider: .anthropic, model: "m", placement: .cloud)).vision, true)
        T.check("Apple context", await f.details(ChatTarget(provider: .apple, model: "system", placement: .local)).contextTokens, 8192)
        let nobody = ChatTarget(provider: .ollama, model: "m", placement: .local)
        var local = f
        local.servers = ["ollama": .init(baseURL: "http://127.0.0.1:\(closedPort())", key: nil)]
        T.check("unknown local model is text-only", await local.details(nobody).vision, false)
    }
}
```

- [ ] **Step 2: Write `scripts/test-ai-settings.sh`**

```bash
#!/usr/bin/env bash
# AI settings: migration of the pre-E1 chat settings and the provider factory
# (which provider, URL and key each choice gets, Debug override included).
set -euo pipefail
cd "$(dirname "$0")/.."
TEST_DIR="$(mktemp -d "${TMPDIR:-/tmp}/notchmeow-ai-settings.XXXXXX")"
trap 'rm -rf "$TEST_DIR"' EXIT
export NM_LOG_DIR="$TEST_DIR/logs"   # tests never write to ~/Library/Logs
swiftc -swift-version 6 \
    NotchBuddy/Sources/App/AI/Core/*.swift \
    NotchBuddy/Sources/App/AppLog.swift \
    tests/AITestSupport.swift tests/AISettingsTests.swift \
    -o "$TEST_DIR/ai-settings-tests"
"$TEST_DIR/ai-settings-tests"
```

Run: `chmod +x scripts/test-ai-settings.sh && bash scripts/test-ai-settings.sh`
Expected: FAIL with `error: cannot find 'AISettingsMigration' in scope`.

- [ ] **Step 3: Write `NotchBuddy/Sources/App/AI/Core/ProviderFactory.swift`**

Migration rules:
- **Old default.** The old single `chatProvider` default (`anthropic`) becomes Auto. Anthropic is Auto's first choice anyway, until a second key or a local model exists.
- **Other choices.** Any other saved provider stays chosen for Chat, with its remembered model.
- **Custom URLs.** An Ollama or LM Studio URL that isn't the default address becomes an added server.

```swift
import Foundation

/// A server the user added in Settings → AI → Add server…. Its key (optional) is in the Keychain.
struct CustomServer: Codable, Equatable, Identifiable, Sendable {
    /// "custom-" plus 24 hex digits; always matches `^[a-z0-9-]{1,32}$` (the contract's server ID rule).
    let id: String
    var name: String
    var baseURL: String

    static let idPrefix = "custom-"

    static func newID() -> String {
        idPrefix + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(24)
    }

    /// `^[a-z0-9-]{1,32}$`, checked by hand: 1 to 32 bytes, each a lowercase letter, a digit or `-`.
    static func isValidID(_ id: String) -> Bool {
        (1...32).contains(id.utf8.count)
            && id.utf8.allSatisfy { ($0 >= 0x61 && $0 <= 0x7A) || ($0 >= 0x30 && $0 <= 0x39) || $0 == 0x2D }
    }

    /// `custom-server-key` (providers.json) is a prefix: it plus `.` and the server ID makes one Keychain item per server.
    var keychainAccount: String { "custom-server-key.\(id)" }
}

/// Builds the provider for a target from a snapshot of keys and servers, so streams can run
/// off the main actor.
struct ProviderFactory: Sendable {
    struct ServerAddress: Sendable, Equatable {
        var baseURL: String
        var key: String?
    }

    var keys: [AIProviderID: String] = [:]
    /// By server ID ("ollama", "custom-…").
    var servers: [String: ServerAddress] = [:]
    /// Debug builds only (`AIURL.cloudOverride()`).
    var cloudOverride: String? = nil
    /// Apple's provider when this Mac has it (macOS 26+).
    var apple: (any ModelProvider)? = nil
    var appleContextTokens: Int = AICatalog.Limits.defaultLocalContextTokens

    func make(_ t: ChatTarget) -> any ModelProvider {
        switch t.provider {
        case .anthropic:
            return AnthropicProvider(apiKey: keys[.anthropic] ?? "",
                                     baseURL: cloudOverride ?? AICatalog.info(.anthropic).baseURL!)
        case .openai:
            return OpenAIProvider(apiKey: keys[.openai] ?? "", baseURL: cloudOverride ?? AICatalog.info(.openai).baseURL!)
        case .google:
            return OpenAICompatibleProvider.make(.google, baseURL: cloudOverride ?? AICatalog.info(.google).baseURL!,
                                                 apiKey: keys[.google])
        case .apple:
            return apple ?? UnavailableProvider(id: .apple)
        case .ollama, .lmstudio, .llamacpp, .jan, .custom:
            let server = servers[t.serverID ?? t.provider.rawValue]
            return OpenAICompatibleProvider.make(t.provider,
                                                 baseURL: server?.baseURL ?? AICatalog.info(t.provider).baseURL ?? "",
                                                 name: t.provider == .custom ? t.host : nil,
                                                 placement: t.placement, apiKey: server?.key)
        }
    }

    /// Whether the model reads images, and its context, for sizing files.
    func details(_ t: ChatTarget) async -> (vision: Bool, contextTokens: Int?) {
        switch t.provider {
        case .anthropic, .openai, .google: return (true, nil)
        case .apple: return (false, appleContextTokens)
        default:
            guard let provider = make(t) as? OpenAICompatibleProvider,
                  let info = await provider.modelDetails(t.model) else { return (false, nil) }
            return (info.capabilities.contains(.vision), info.contextTokens)
        }
    }
}

/// Stands in for a provider this Mac doesn't have; every call fails as unreachable.
struct UnavailableProvider: ModelProvider {
    let id: AIProviderID
    var displayName: String { AICatalog.info(id).name }
    let placement = AIPlacement.local
    func listModels() async throws -> [ModelInfo] { throw AIError(kind: .unreachable) }
    func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
        AsyncThrowingStream { $0.finish(throwing: AIError(kind: .unreachable)) }
    }
}

/// First launch with E1: the old single chat provider becomes the Chat choice (Anthropic, the
/// old default, becomes Auto), and Ollama / LM Studio URLs on other ports become added servers.
enum AISettingsMigration {
    struct Result: Equatable {
        var choices: [String: FeatureSetting] = [:]
        var customServers: [CustomServer] = []
        var localModels: [String: String] = [:]
    }

    /// `old`: the pre-E1 UserDefaults strings (chatProvider, ollamaServerURL, lmstudioServerURL,
    /// ollamaChatModel, lmstudioChatModel, openAIChatModel, googleChatModel).
    static func migrate(_ old: [String: String],
                        makeID: () -> String = CustomServer.newID) -> Result {
        var r = Result()
        var serverFor: [String: String] = [:]   // provider rawValue → custom server ID
        for (key, provider) in [("ollamaServerURL", AIProviderID.ollama), ("lmstudioServerURL", .lmstudio)] {
            guard let raw = old[key], !raw.isEmpty else { continue }
            let url = AIURL.normalise(raw)
            let defaultURL = AICatalog.info(provider).baseURL!
            guard url != defaultURL, url != defaultURL.replacingOccurrences(of: "127.0.0.1", with: "localhost") else { continue }
            let server = CustomServer(id: makeID(), name: AICatalog.info(provider).name, baseURL: url)
            r.customServers.append(server)
            serverFor[provider.rawValue] = server.id
        }
        for (key, provider) in [("ollamaChatModel", "ollama"), ("lmstudioChatModel", "lmstudio")] {
            if let model = old[key], !model.isEmpty { r.localModels[serverFor[provider] ?? provider] = model }
        }
        guard let raw = old["chatProvider"], raw != AIProviderID.anthropic.rawValue,
              let provider = AIProviderID(rawValue: raw) else { return r }
        let serverID = serverFor[raw]
        let model = switch provider {
        case .openai: old["openAIChatModel"] ?? AICatalog.info(.openai).defaultModel!
        case .google: old["googleChatModel"] ?? ""
        default: r.localModels[serverID ?? raw] ?? ""
        }
        if !model.isEmpty {
            r.choices[AIFeature.chat.rawValue] = .explicit(ModelRef(provider: serverID == nil ? provider : .custom,
                                                                    model: model, serverID: serverID))
        }
        return r
    }
}

extension ProviderFactory: RedactsSecrets {
    var redactedSummary: String {
        "ProviderFactory(keys: \(keys.keys.map(\.rawValue).sorted()), servers: \(servers.keys.sorted()), "
            + "override: \(cloudOverride ?? "none"), apple: \(apple != nil))"
    }
}

extension ProviderFactory.ServerAddress: RedactsSecrets {
    var redactedSummary: String { "ServerAddress(\(baseURL), key: \(Self.keyMark(key)))" }
}
```

Run: `bash scripts/test-ai-settings.sh`
Expected: every `AISettingsMigration`, `CustomServer IDs and Keychain items`, `ProviderFactory` and `ProviderFactory.details` line `✓`, then `All tests passed.`

Then break each rule once, run the script and restore it:
- `newID()` without `.lowercased()`: `✗ generated IDs match ^[a-z0-9-]{1,32}$`;
- `isValidID` returning `true`: `✗ invalid IDs: empty, uppercase, colon, dot, slash, non-ASCII, 33 characters, space`;
- `keychainAccount` returning `"custom-server-key"` for every server: `✗ a server's Keychain item` and `✗ two servers, two Keychain items`.

- [ ] **Step 4: Add the CI step**

In `.github/workflows/build.yml`, insert this step immediately before `- name: Test plan gauge` (after any `AI …` steps added by earlier tasks), at the same indentation:

```yaml
      - name: AI settings migration and provider factory
        run: bash scripts/test-ai-settings.sh
```

- [ ] **Step 5: Extend `ChatProvider`**

In `NotchBuddy/Sources/App/IslandTypes.swift`, replace everything from `// MARK: - Chat provider` up to (not including) `// MARK: - View dimensions` with the code below. Raw values and pill IDs of the five existing cases don't change.

```swift
// MARK: - Chat provider

/// Raw values are the shared provider IDs (`AIProviderID`). Existing raw values and pill IDs never change.
enum ChatProvider: String, CaseIterable, Codable {
    case anthropic = "anthropic"
    case google    = "google"
    case openai    = "openai"
    case ollama    = "ollama"
    case lmstudio  = "lmstudio"
    case llamacpp  = "llamacpp"
    case jan       = "jan"
    case apple     = "apple"
    case custom    = "custom"

    init(_ id: AIProviderID) { self.init(rawValue: id.rawValue)! }

    var providerID: AIProviderID { AIProviderID(rawValue: rawValue)! }

    var displayName: String {
        switch self {
        case .anthropic: "Anthropic"
        case .google:    "Google"
        case .openai:    "OpenAI"
        case .ollama:    "Ollama"
        case .lmstudio:  "LM Studio"
        case .llamacpp:  "llama.cpp"
        case .jan:       "Jan"
        case .apple:     "Apple on-device"
        case .custom:    "Local server"
        }
    }

    var accentHex: String {
        switch self {
        case .anthropic: "#E07950"
        case .google:    "#4285F4"
        case .openai:    "#10A37F"
        case .ollama:    "#FACC15"
        case .lmstudio:  "#A3E635"
        case .llamacpp:  "#F59E0B"
        case .jan:       "#38BDF8"
        case .apple:     "#C8CDD4"
        case .custom:    "#94A3B8"
        }
    }

    var defaultModel: String {
        switch self {
        case .anthropic: AICatalog.info(.anthropic).defaultModel!
        case .google:    "gemini-2.0-flash"
        case .openai:    AICatalog.info(.openai).defaultModel!
        case .ollama:    "llama3.2"
        case .lmstudio:  "local-model"
        case .apple:     "system"
        case .llamacpp, .jan, .custom: ""
        }
    }

    var keychainKey: String {
        switch self {
        case .anthropic: "anthropic-api-key"
        case .google:    "google-api-key"
        case .openai:    "openai-api-key"
        default:         ""
        }
    }

    var isLocal: Bool { !providerID.isCloud }

    /// Pills exist for the five original providers only.
    var pillID: String? {
        switch self {
        case .anthropic: "ai_anthropic"
        case .google:    "ai_google"
        case .openai:    "ai_openai"
        case .ollama:    "ai_ollama"
        case .lmstudio:  "ai_lmstudio"
        default:         nil
        }
    }

    init?(pillID: String) {
        switch pillID {
        case "ai_anthropic": self = .anthropic
        case "ai_google":    self = .google
        case "ai_openai":    self = .openai
        case "ai_ollama":    self = .ollama
        case "ai_lmstudio":  self = .lmstudio
        default:             return nil
        }
    }
}
```

- [ ] **Step 6: Add the AI routing state to `AppState`**

In `NotchBuddy/Sources/App/AppState.swift`, replace everything from the line `// Claude model used by the chat and the search — persisted` up to (not including) the line `// Sound volume (0–0.2) — persisted, synced to SoundEngine` with:

```swift
    // Claude model used by the chat and the search — persisted (Anthropic's remembered model)
    static let defaultClaudeModel = AICatalog.info(.anthropic).defaultModel!
    @Published var claudeModel: String = AppState.defaultClaudeModel {
        didSet { UserDefaults.standard.set(claudeModel, forKey: "claudeModel") }
    }

    // Remembered cloud models (Google, OpenAI) — persisted
    @Published var googleChatModel: String = ChatProvider.google.defaultModel {
        didSet { UserDefaults.standard.set(googleChatModel, forKey: "googleChatModel") }
    }
    @Published var openAIChatModel: String = ChatProvider.openai.defaultModel {
        didSet { UserDefaults.standard.set(openAIChatModel, forKey: "openAIChatModel") }
    }

    // Pre-E1 chat settings, still read by Settings until it moves to the AI section (Task 13).
    @Published var chatProvider: ChatProvider = .anthropic {
        didSet { UserDefaults.standard.set(chatProvider.rawValue, forKey: "chatProvider") }
    }
    @Published var ollamaServerURL: String = "" {
        didSet { UserDefaults.standard.set(ollamaServerURL, forKey: "ollamaServerURL") }
    }
    @Published var lmstudioServerURL: String = "" {
        didSet { UserDefaults.standard.set(lmstudioServerURL, forKey: "lmstudioServerURL") }
    }

    // MARK: AI routing (E1) — persisted

    /// Per feature ("chat", "files"): Auto or one chosen model.
    @Published var aiChoices: [String: FeatureSetting] = [:] {
        didSet { Self.saveJSON(aiChoices, "aiChoices") }
    }
    /// Which cloud Auto tries first when both Claude and OpenAI keys exist.
    @Published var preferredCloud: AIProviderID = .anthropic {
        didSet { UserDefaults.standard.set(preferredCloud.rawValue, forKey: "aiPreferredCloud") }
    }
    @Published var lastUsedLocal: ModelRef? = nil {
        didSet { Self.saveJSON(lastUsedLocal, "aiLastUsedLocal") }
    }
    /// Servers added in Settings → AI (keys in the Keychain).
    @Published var customServers: [CustomServer] = [] {
        didSet { Self.saveJSON(customServers, "aiCustomServers") }
    }
    /// Last model used on each local server, by server ID.
    @Published var localModelMemory: [String: String] = [:] {
        didSet { Self.saveJSON(localModelMemory, "aiLocalModels") }
    }

    // MARK: AI routing (E1) — live

    @Published var localServers: [DiscoveredServer] = []
    @Published var appleStatus: AppleOnDevice.Status = .hidden
    @Published var isOnline: Bool = true
    /// "Waking up qwen3.5…" or the busy countdown, shown where the typing dots are.
    @Published var chatNotice: ChatNotice? = nil
    /// A reply is streaming: the send button becomes Stop.
    @Published var chatStreaming: Bool = false
    /// Drop card line: who will read the file, or why it can't be read.
    @Published var dropReaderLine: String? = nil
    @Published var dropRejected: Bool = false
    /// Optional button for the current note (only shown while `noteMessage` is the one it was made for).
    @Published var noteAction: NoteAction? = nil

    func choice(for feature: AIFeature) -> FeatureSetting { aiChoices[feature.rawValue] ?? .auto }

    func setChoice(_ setting: FeatureSetting, for feature: AIFeature) {
        aiChoices[feature.rawValue] = setting
        if case .explicit(let ref) = setting { remember(ref) }
    }

    /// Remembers the model per provider (cloud) or per server (local).
    func remember(_ ref: ModelRef) {
        switch ref.provider {
        case .anthropic: claudeModel = ref.model
        case .openai: openAIChatModel = ref.model
        case .google: googleChatModel = ref.model
        case .apple: break
        default: localModelMemory[ref.serverID ?? ref.provider.rawValue] = ref.model
        }
    }

    private static func saveJSON<T: Encodable>(_ value: T, _ key: String) {
        if let data = try? JSONEncoder().encode(value) { UserDefaults.standard.set(data, forKey: key) }
    }

    private static func loadJSON<T: Decodable>(_ type: T.Type, _ key: String) -> T? {
        UserDefaults.standard.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    /// First launch with E1 only (see `AISettingsMigration`).
    private func migrateChatSettings(_ ud: UserDefaults) {
        guard ud.object(forKey: "aiChoices") == nil else { return }
        let keys = ["chatProvider", "ollamaServerURL", "lmstudioServerURL", "ollamaChatModel",
                    "lmstudioChatModel", "openAIChatModel", "googleChatModel"]
        var old: [String: String] = [:]
        for key in keys { old[key] = ud.string(forKey: key) }
        let r = AISettingsMigration.migrate(old)
        customServers = r.customServers
        localModelMemory = r.localModels
        aiChoices = r.choices   // always written, so this runs once
    }

    // The always-on workspace pill (default: VS Code). Persisted.
    @Published var mainPillId: String = PillCatalog.defaultMainPillId {
        didSet { UserDefaults.standard.set(mainPillId, forKey: "mainPill") }
    }

    // Dynamically fetched cloud model lists for the in-chat picker
    @Published var fetchedProviderModels: [AIProviderID: [ModelInfo]] = [:]
    @Published var providerModelFetchError: [AIProviderID: String] = [:]
    @Published var loadingProviderModels: Set<AIProviderID> = []

    /// Fetches a cloud provider's models if not already loaded or loading.
    func fetchModelsIfNeeded(for provider: AIProviderID) {
        guard provider.isCloud, !loadingProviderModels.contains(provider),
              fetchedProviderModels[provider] == nil else { return }
        guard let key = AIService.shared.key(provider) else {
            providerModelFetchError[provider] = "No API key — add it in Settings."
            return
        }
        loadingProviderModels.insert(provider)
        providerModelFetchError.removeValue(forKey: provider)
        Task {
            let models = await AIService.shared.listCloudModels(provider, key: key)
            loadingProviderModels.remove(provider)
            if models.isEmpty {
                providerModelFetchError[provider] = "Failed to load models. Check your API key."
            } else {
                fetchedProviderModels[provider] = models
            }
        }
    }
```

Then, in `init()`, replace:

```swift
        if let v = ud.string(forKey: "chatProvider"), let p = ChatProvider(rawValue: v) { chatProvider = p }
        if let v = ud.string(forKey: "googleChatModel"), !v.isEmpty { googleChatModel = v }
        if let v = ud.string(forKey: "openAIChatModel"), !v.isEmpty { openAIChatModel = v }
        if let v = ud.string(forKey: "ollamaChatModel"), !v.isEmpty { ollamaChatModel = v }
        if let v = ud.string(forKey: "lmstudioChatModel"), !v.isEmpty { lmstudioChatModel = v }
        if let v = ud.string(forKey: "ollamaServerURL"), !v.isEmpty { ollamaServerURL = v }
        if let v = ud.string(forKey: "lmstudioServerURL"), !v.isEmpty { lmstudioServerURL = v }
```

with:

```swift
        if let v = ud.string(forKey: "chatProvider"), let p = ChatProvider(rawValue: v) { chatProvider = p }
        if let v = ud.string(forKey: "ollamaServerURL"), !v.isEmpty { ollamaServerURL = v }
        if let v = ud.string(forKey: "lmstudioServerURL"), !v.isEmpty { lmstudioServerURL = v }
        if let v = ud.string(forKey: "googleChatModel"), !v.isEmpty { googleChatModel = v }
        if let v = ud.string(forKey: "openAIChatModel"), !v.isEmpty { openAIChatModel = v }
        if let v = Self.loadJSON([String: FeatureSetting].self, "aiChoices") { aiChoices = v }
        if let v = ud.string(forKey: "aiPreferredCloud"), let p = AIProviderID(rawValue: v) { preferredCloud = p }
        if let v = Self.loadJSON(ModelRef.self, "aiLastUsedLocal") { lastUsedLocal = v }
        if let v = Self.loadJSON([CustomServer].self, "aiCustomServers") { customServers = v }
        if let v = Self.loadJSON([String: String].self, "aiLocalModels") { localModelMemory = v }
        migrateChatSettings(ud)
```

Then replace the `ChatMessage` struct at the end of the file:

```swift
struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: ChatRole
    var content: String   // var for streaming updates
}
```

with:

```swift
struct ChatMessage: Identifiable, Equatable {
    let id = UUID()
    let role: ChatRole
    var content: String   // var for streaming updates
    /// Under a reply: "cloud · Claude Sonnet 5.5", "local · qwen3.5:2b".
    var caption: String? = nil
    /// Web search sources (Claude and OpenAI), shown as links.
    var sources: [Citation] = []
    /// One quiet line: fell back to local, file cut short, old messages dropped.
    var notice: String? = nil
    /// The stream was cut: the partial reply is kept with Continue · Retry.
    var interrupted: Bool = false
}

/// Shown where the typing dots are: "Waking up qwen3.5…", or the busy countdown with Cancel.
struct ChatNotice: Equatable {
    var text: String
    var cancellable: Bool = false
}

/// The single button under a note, tied to the message it was made for.
struct NoteAction: Equatable {
    let message: String
    let action: AIAction
    /// The message is Markdown with links (the local-model guide).
    var markdown: Bool = false
}
```

- [ ] **Step 7: Write `NotchBuddy/Sources/App/AI/AIService.swift`**

```swift
import Combine
import Foundation

/// Glue between AppState and the AI core: discovery, routing input, providers, pre-warming.
@MainActor
final class AIService {
    static let shared = AIService()
    private var state: AppState { .shared }
    private var firstOpenWatch: AnyCancellable?

    /// At launch: watch the network, and look for local servers the first time the island opens.
    /// Nothing is requested while it stays hidden (0% CPU, no model-list calls in the background).
    func start() {
        KeychainStore.shared.preload(state.customServers.map(\.keychainAccount))
        NetworkMonitor.shared.start { online in
            Task { @MainActor in AppState.shared.isOnline = online }
        }
        firstOpenWatch = state.$mode.sink { mode in
            guard mode == .expanded else { return }
            Task { @MainActor in AIService.shared.firstLook() }
        }
    }

    private func firstLook() {
        guard firstOpenWatch != nil else { return }
        firstOpenWatch = nil
        Task { await discover() }
    }

    /// Checks localhost and the user's servers (≤ 0.3 s), and Apple's model.
    func discover() async {
        let custom = state.customServers.map {
            ProbeTarget(serverID: $0.id, provider: .custom, name: $0.name, baseURL: $0.baseURL,
                        apiKey: KeychainStore.shared.get($0.keychainAccount))
        }
        state.localServers = await Discovery.run(ProbeTarget.defaults + custom)
        state.appleStatus = AppleOnDevice.status()
    }

    // MARK: Routing input

    func key(_ provider: AIProviderID) -> String? {
        guard let account = AICatalog.info(provider).keychainKey,
              let key = KeychainStore.shared.get(account), !key.isEmpty else { return nil }
        return key
    }

    var cloudKeys: Set<AIProviderID> { Set(AICatalog.cloudOrder.filter { key($0) != nil }) }

    /// The remembered model for a cloud provider, else its catalog default.
    func cloudModel(_ provider: AIProviderID) -> String {
        let listed = state.fetchedProviderModels[provider]?.map(\.id) ?? []
        let remembered: String = switch provider {
        case .anthropic: state.claudeModel
        case .openai: state.openAIChatModel
        default: state.googleChatModel
        }
        if listed.isEmpty || listed.contains(remembered) { return remembered }
        return AICatalog.defaultModel(for: provider, available: listed) ?? remembered
    }

    /// The remembered model on a server if it still has it, else its first model.
    func localModel(_ server: DiscoveredServer) -> String? {
        let ids = server.models.map(\.id)
        if let remembered = state.localModelMemory[server.serverID], ids.contains(remembered) { return remembered }
        return ids.first
    }

    func localReady() -> [LocalCandidate] {
        state.localServers.filter(\.isReady).compactMap { server in
            localModel(server).map {
                LocalCandidate(provider: server.provider, model: $0, placement: server.placement, serverID: server.serverID)
            }
        }
    }

    func routeInput(_ feature: AIFeature) -> RouteInput {
        RouteInput(setting: state.choice(for: feature), preferredCloud: state.preferredCloud, keys: cloudKeys,
                   online: state.isOnline, localReady: localReady(), lastUsedLocal: state.lastUsedLocal,
                   appleReady: state.appleStatus == .ready)
    }

    // MARK: Targets

    func target(_ provider: AIProviderID, model: String, placement: AIPlacement, serverID: String?) -> ChatTarget {
        let server = state.localServers.first { $0.serverID == (serverID ?? provider.rawValue) }
        let label = state.fetchedProviderModels[provider]?.first { $0.id == model }?.label
        return ChatTarget(provider: provider, model: model, placement: placement,
                          serverID: serverID ?? server?.serverID, host: server?.host, modelLabel: label)
    }

    func primaryTarget(_ plan: RoutePlan) -> ChatTarget {
        target(plan.primary, model: plan.model ?? cloudModel(plan.primary), placement: plan.placement, serverID: plan.serverID)
    }

    func target(_ c: LocalCandidate) -> ChatTarget {
        target(c.provider, model: c.model, placement: c.placement, serverID: c.serverID)
    }

    /// What a feature uses right now (chip, drop card, Settings line).
    func resolve(_ feature: AIFeature) -> (primary: ChatTarget?, fallback: ChatTarget?) {
        guard let plan = ModelRouter.plan(routeInput(feature)) else { return (nil, nil) }
        return (primaryTarget(plan), plan.fallback.map(target))
    }

    /// The chat's model chip: "Auto · claude-sonnet-5-5", or the chosen model.
    func chip(_ feature: AIFeature) -> (label: String, accentHex: String) {
        let t = resolve(feature).primary
        let accent = t.map { ChatProvider($0.provider).accentHex } ?? "#5C6370"
        let model = t.map { $0.provider == .apple ? "Apple on-device" : $0.model } ?? "No model yet"
        if case .auto = state.choice(for: feature) { return ("Auto · \(model)", accent) }
        return (model, accent)
    }

    /// One line under each Settings row: "Claude Sonnet 5.5 · falls back to Local · qwen3.5:2b".
    func resolutionLine(_ feature: AIFeature) -> String {
        let r = resolve(feature)
        guard let primary = r.primary else { return "Nothing set up yet: add a cloud key or start a local model." }
        let first = AIMessages.targetLabel(primary)
        return r.fallback.map { "\(first) · falls back to \(AIMessages.targetLabel($0))" } ?? first
    }

    /// Auto needs a local model now: look again (≤ 0.3 s), then pick last-used, first ready, or Apple.
    func freshLocalTarget(for feature: AIFeature) async -> ChatTarget? {
        await discover()
        return ModelRouter.localChoice(routeInput(feature)).map(target)
    }

    // MARK: Providers

    func factory() -> ProviderFactory {
        var keys: [AIProviderID: String] = [:]
        for p in AICatalog.cloudOrder { keys[p] = key(p) }
        var servers: [String: ProviderFactory.ServerAddress] = [:]
        for s in state.localServers { servers[s.serverID] = .init(baseURL: s.baseURL, key: s.apiKey) }
        return ProviderFactory(keys: keys, servers: servers, cloudOverride: AIURL.cloudOverride(),
                               apple: AppleOnDevice.provider(), appleContextTokens: AppleOnDevice.contextTokens())
    }

    /// Opening the chat loads the selected local model ahead of the first message.
    func prewarm(_ feature: AIFeature) {
        guard let t = resolve(feature).primary, t.placement != .cloud else { return }
        let provider = factory().make(t)
        Task.detached(priority: .utility) { await provider.prewarm(model: t.model) }
    }

    /// Cloud model list (also checks a pasted key: an empty list means it was refused).
    func listCloudModels(_ provider: AIProviderID, key: String) async -> [ModelInfo] {
        var f = factory()
        f.keys[provider] = key
        return (try? await f.make(ChatTarget(provider: provider, model: "", placement: .cloud)).listModels()) ?? []
    }
}

extension Notification.Name {
    /// A dropped file the AI can't read (object: its extension). The cat's hairball hooks here.
    static let botReject = Notification.Name("notchMeow.botReject")
}
```

- [ ] **Step 8: Route the chat in `ClaudeService`**

a) In `NotchBuddy/Sources/App/ClaudeService.swift`, replace everything from the line `// MARK: - Model list` up to (not including) the line `/// Chosen in Settings; falls back to the default when the field is left empty.` with:

```swift
    // MARK: - Model list

    /// Anthropic models, newest first, for the Settings picker. Empty on any error
    /// (callers fall back to a static list).
    static func fetchModels(apiKey: String) async -> [(id: String, label: String)] {
        let models = (try? await AnthropicProvider(apiKey: apiKey).listModels()) ?? []
        return models.map { (id: $0.id, label: $0.label ?? $0.id) }
    }
```

b) Replace everything from the line `// Multi-turn conversation messages (for API)` up to (not including) the line `// MARK: - Structured search (M8 — window attach + web search)` with the code below.
- The window context still goes out with a conversation's first message. A dropped file joins the next message, and the conversation stays on File questions from then on (`Conversation.feature`). `clearConversation` still runs on every drop and window attach, keeping the shipped fix.
- Every request's `maxTokens` comes from `AICatalog.maxOutputTokens(for:)` for the target's placement.
- `reply` only takes back a user message it added, and an empty result never enters the history.
- A reply cut at the cap gets "The answer was cut off."

```swift
    /// What the model sees of the current chat (provider-independent).
    private var conversation = Conversation()
    /// Bumped on every reset: a reply still on its way is dropped when it lands instead of
    /// being added to the new conversation.
    private var conversationGeneration = 0
    /// The message being answered (Stop cancels it).
    private var replyTask: Task<Void, Never>?
    /// Reading a dropped file; the next message waits for it.
    private var preparation: Task<Void, Never>?
    private var countdownTask: Task<Void, Never>?

    /// File questions use the `files` route from the message that carries a file onward, everything else `chat`.
    var currentFeature: AIFeature { conversation.feature }

    /// Starts over when a new file or window is attached, so the next turn carries it. Clears what
    /// the model gets and the transcript on screen together, like the Windows build does on drop.
    func clearConversation(state: AppState) {
        conversation = Conversation()
        conversationGeneration += 1
        replyTask?.cancel()
        countdownTask?.cancel()
        preparation = nil
        state.chatHistory = []
        state.chatNotice = nil
        state.chatStreaming = false
        if state.stateOverride == .thinking { state.stateOverride = nil }
    }

    /// Reads a dropped file off the main thread; it joins the next message sent.
    func prepareAttachment(url: URL, state: AppState) {
        let generation = conversationGeneration
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        state.dropReaderLine = nil
        state.dropRejected = false
        preparation = Task {
            let result = await Task.detached(priority: .userInitiated) { AttachmentExtractor.prepare(url: url) }.value
            guard generation == self.conversationGeneration else { return }
            switch result {
            case .success(let file):
                self.conversation.attach(file)
                AILog.record(.attachment(kind: file.kind, bytes: bytes))
                state.dropReaderLine = AIMessages.dropReader(AIService.shared.resolve(.files).primary)
            case .failure(let reason):
                AILog.record(.rejected(reason: reason, bytes: bytes))
                state.dropReaderLine = AIMessages.rejected(reason)
                state.dropRejected = true
            }
        }
    }

    /// Resolved once: NSFullUserName() is a system call, and the name cannot change under us
    /// while the app runs.
    private let systemPrompt = ClaudeService.makeSystemPrompt()

    /// Greets the user by their macOS first name when there is one worth using, and stays
    /// neutral otherwise — same wording as the Windows build.
    private nonisolated static func makeSystemPrompt() -> String {
        let opening = if let firstName = resolveUserFirstName() {
            "You are Shrimpy, \(firstName)'s personal AI assistant embedded in the notch of their Mac."
        } else {
            "You are Shrimpy, a personal AI assistant embedded in the notch of the user's Mac."
        }
        return """
        \(opening) \
        You have web search access and can help with absolutely anything — research, coding, finding places, recommendations, tasks, questions. \
        Respond in the user's language. Be thorough and complete — use as much detail as the task requires. \
        Use light Markdown when it helps: short paragraphs, bullet lists, **bold**, `inline code` and fenced code blocks. Avoid tables and big headings: the chat window is small.
        """
    }

    // MARK: - Chat (router → provider, streaming)

    /// Sends a message; Stop cancels it.
    func send(query: String, context: PromptContext?, state: AppState) {
        countdownTask?.cancel()
        // Only the newest partial reply keeps Continue · Retry: they act on the last exchange.
        for i in state.chatHistory.indices { state.chatHistory[i].interrupted = false }
        state.chatHistory.append(ChatMessage(role: .user, content: query))
        state.stateOverride = .thinking
        replyTask = Task { await chat(query: query, context: context, state: state) }
    }

    func stop() {
        replyTask?.cancel()
        countdownTask?.cancel()
    }

    func chat(query: String, context: PromptContext?, state: AppState, isRetry: Bool = false) async {
        await preparation?.value
        if conversation.turns.isEmpty, case .window(let app, let title, let url) = context {
            conversation.attachContext("Context — App: \(app), Window: \(title)" + (url.map { ", URL: \($0)" } ?? ""))
        }
        conversation.addUser(query)
        await reply(query: query, context: context, addedUserTurn: true, isRetry: isRetry, state: state)
    }

    /// Answers the conversation's last user message. `addedUserTurn`: this call added that message,
    /// so it may take it back on failure; a regenerate (Retry) never removes a user message.
    private func reply(query: String, context: PromptContext?, addedUserTurn: Bool, isRetry: Bool,
                       state: AppState) async {
        let generation = conversationGeneration
        let service = AIService.shared
        var input = service.routeInput(conversation.feature)
        if ModelRouter.plan(input) == nil {
            // Nothing known yet: a server may have started since launch.
            await service.discover()
            input = service.routeInput(conversation.feature)
        }
        guard generation == conversationGeneration else { return }
        guard let plan = ModelRouter.plan(input) else {
            if addedUserTurn { conversation.removeLastUser() }
            state.stateOverride = nil
            state.chatNotice = nil
            return  // PromptView shows the empty state
        }
        let primary = service.primaryTarget(plan)
        let factory = service.factory()
        let convo = conversation
        let system = systemPrompt
        let notices = NoticeBox()
        let runner = ChatRunner(
            makeProvider: { factory.make($0) },
            makeRequest: { target in
                let details = await factory.details(target)
                let built = convo.request(model: target.model, api: AICatalog.info(target.provider).api,
                                          vision: details.vision, placement: target.placement,
                                          contextTokens: details.contextTokens, system: system,
                                          maxTokens: AICatalog.maxOutputTokens(for: target.placement),
                                          webSearch: target.provider == .anthropic || target.provider == .openai)
                notices.set(built)
                return built.request
            })
        let placeholder = ChatMessage(role: .assistant, content: "")
        let msgID = placeholder.id
        state.chatHistory.append(placeholder)
        state.chatStreaming = true

        let result = await runner.run(
            plan: plan, primary: primary,
            fallback: { await AIService.shared.freshLocalTarget(for: convo.feature) },
            onEvent: { event in
                await MainActor.run {
                    guard generation == ClaudeService.shared.conversationGeneration,
                          let i = state.chatHistory.firstIndex(where: { $0.id == msgID }) else { return }
                    switch event {
                    case .started:
                        state.chatHistory[i].content = ""
                        state.chatNotice = nil
                    case .text(let visible):
                        state.chatHistory[i].content = visible
                        if !visible.isEmpty {
                            state.stateOverride = nil
                            state.chatNotice = nil
                        }
                    case .citation(let c):
                        if !state.chatHistory[i].sources.contains(c) { state.chatHistory[i].sources.append(c) }
                    case .waking(let t):
                        state.chatNotice = ChatNotice(text: AIMessages.waking(t))
                        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.yawn)
                    case .fellBack(let from, let to, _):
                        state.chatHistory[i].notice = AIMessages.fellBack(from: from, to: to)
                    }
                }
            })
        guard generation == conversationGeneration else { return }
        finish(result, primary: primary, notices: notices, msgID: msgID, query: query, context: context,
               addedUserTurn: addedUserTurn, isRetry: isRetry, state: state)
    }

    private func finish(_ result: RunResult, primary: ChatTarget, notices: NoticeBox, msgID: UUID, query: String,
                        context: PromptContext?, addedUserTurn: Bool, isRetry: Bool, state: AppState) {
        state.chatStreaming = false
        state.chatNotice = nil
        state.stateOverride = nil
        let i = state.chatHistory.firstIndex { $0.id == msgID }
        func removePlaceholder() { if let i { state.chatHistory.remove(at: i) } }
        func takeBackUserTurn() { if addedUserTurn { conversation.removeLastUser() } }

        switch result.outcome {
        case .ok, .fallback, .interrupted:
            guard let i, let answeredBy = result.answeredBy, !result.text.isEmpty else {
                removePlaceholder()
                takeBackUserTurn()
                showError(AIMessages.error(AIError(kind: .server), target: primary).text, action: nil, state: state)
                return
            }
            conversation.addAssistant(result.text)
            state.chatHistory[i].notice = AIMessages.replyNotes(fellBack: state.chatHistory[i].notice,
                                                                built: notices.built, finish: result.finish)
            state.chatHistory[i].content = result.text
            state.chatHistory[i].sources = result.citations
            state.chatHistory[i].caption = AIMessages.caption(answeredBy)
            state.chatHistory[i].interrupted = result.outcome == .interrupted
            if answeredBy.placement != .cloud { state.lastUsedLocal = answeredBy.ref }
            state.view = .prompt
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
        case .cancelled:
            if result.text.isEmpty {
                removePlaceholder()
                takeBackUserTurn()
            } else {
                conversation.addAssistant(result.text)
                if let i { state.chatHistory[i].content = result.text }
            }
        case .retryCountdown where !isRetry:
            removePlaceholder()
            takeBackUserTurn()
            startCountdown(seconds: result.error?.retryAfter ?? 20, target: primary, state: state) {
                if addedUserTurn {
                    await self.chat(query: query, context: context, state: state, isRetry: true)
                } else {
                    await self.reply(query: query, context: context, addedUserTurn: false, isRetry: true, state: state)
                }
            }
        case .error where result.error?.kind == .refusal:
            guard let i else { return }
            let text = result.text.isEmpty ? AIMessages.error(AIError(kind: .refusal), target: primary).text : result.text
            conversation.addAssistant(text)
            state.chatHistory[i].content = text
            state.chatHistory[i].caption = result.answeredBy.map(AIMessages.caption)
        default:
            removePlaceholder()
            takeBackUserTurn()
            let (text, action) = AIMessages.error(result.error ?? AIError(kind: .server), target: primary)
            showError(text, action: action, state: state)
        }
    }

    /// "Claude is busy. Trying again in 20 s." then one automatic retry.
    private func startCountdown(seconds: Int, target: ChatTarget, state: AppState,
                                retry: @escaping @MainActor () async -> Void) {
        countdownTask = Task {
            for left in stride(from: seconds, to: 0, by: -1) {
                state.chatNotice = ChatNotice(text: AIMessages.countdown(target, seconds: left), cancellable: true)
                try? await Task.sleep(nanoseconds: 1_000_000_000)
                if Task.isCancelled { state.chatNotice = nil; return }
            }
            state.chatNotice = nil
            state.stateOverride = .thinking
            replyTask = Task { await retry() }
        }
    }

    /// The partial reply's "Continue".
    func continueReply(state: AppState) {
        send(query: "Continue from where you stopped.", context: nil, state: state)
    }

    /// The partial reply's "Retry": drops that reply and answers the same user message again.
    /// It never removes a user message: it didn't add one.
    func retryLast(state: AppState) {
        guard !state.chatStreaming, let lastUser = conversation.regenerate() else { return }
        if let i = state.chatHistory.lastIndex(where: { $0.role == .assistant }) { state.chatHistory.remove(at: i) }
        state.stateOverride = .thinking
        replyTask = Task {
            await reply(query: lastUser.text, context: nil, addedUserTurn: false, isRetry: false, state: state)
        }
    }
```

c) In `search(…)`, use the catalog's web search (GA, no beta header). `model` is the chosen Claude model, so a Haiku or Claude 3 model gets the legacy tool type:

```swift
        let tools: [[String: Any]] = [
            ["type": "web_search_20250305", "name": "web_search", "max_uses": 3]
        ]
```

becomes

```swift
        let tools: [[String: Any]] = [
            ["type": AICatalog.anthropicWebSearchType(model: model), "name": AICatalog.WebSearch.anthropicName, "max_uses": 3]
        ]
```

and

```swift
            let result = try await callAPI(body: body, key: key, beta: "web-search-2025-03-05")
            await handleResult(result, state: state)
```

becomes

```swift
            let result = try await callAPI(body: body, key: key)
            await handleResult(result, state: state)
```

d) Delete everything from `    // MARK: - Chat result handler` up to (not including) `    // MARK: - Structured result handler`. `handleChatResult` has no caller left.

e) In `NotchBuddy/Sources/App/ClaudeService.swift`, replace:

```swift
    private func showError(_ message: String, state: AppState) async {
        state.stateOverride = .error
        state.noteMessage = message
        state.view = .note
    }
```

with:

```swift
    private func showError(_ message: String, state: AppState) async {
        showError(message, action: nil, state: state)
    }

    private func showError(_ message: String, action: AIAction?, state: AppState) {
        state.stateOverride = .error
        state.noteMessage = message
        state.noteAction = action.map { NoteAction(message: message, action: $0) }
        state.view = .note
    }
```

f) In `KeychainStore`, add `preload` before `remove`. Replace:

```swift
    /// Removes from cache + Keychain only if the key was previously set.
```

with:

```swift
    /// Loads keys only known at runtime (one per added AI server), once, at launch.
    func preload(_ keys: [String]) {
        for key in keys where lock.withLock({ cache[key] == nil }) {
            if let v = Keychain.load(key: key) { lock.withLock { cache[key] = v } }
        }
    }

    /// Removes from cache + Keychain only if the key was previously set.
```

g) Append at the end of the file:

```swift
/// The request built for whichever model answered (notices to show under the reply).
private final class NoticeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var last: Conversation.Built?
    func set(_ b: Conversation.Built) { lock.withLock { last = b } }
    var built: Conversation.Built? { lock.withLock { last } }
}
```

- [ ] **Step 9: Read dropped files for the AI**

In `NotchBuddy/Sources/App/FileDropView.swift`, replace:

```swift
        ClaudeService.shared.clearConversation(state: state)
```

with:

```swift
        ClaudeService.shared.clearConversation(state: state)
        ClaudeService.shared.prepareAttachment(url: url, state: state)
```

and replace:

```swift
        state.view = .choose
    }
```

with:

```swift
        state.view = .choose

        // A file the AI can't take: the cat's reject (the hairball hooks onto .botReject).
        if state.dropRejected {
            SoundEngine.shared.play("annoyed")
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.annoyed)
            NotificationCenter.default.post(name: .botReject, object: url.pathExtension.lowercased())
        }
    }
```

In `NotchBuddy/Sources/App/AppDelegate.swift`, `setupIsland()`, add `AIService.shared.start()` after `NotionPoller.shared.start()`:

```swift
        NotionPoller.shared.start()
        AIService.shared.start()
```

- [ ] **Step 10: Point the model chip and picker at the router**

a) In `NotchBuddy/Sources/App/IslandViewContent.swift`, replace:

```swift
                    } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color(hex: state.chatProvider.accentHex))
                                .frame(width: 6, height: 6)
                            Text(state.activeChatModel)
```

with:

```swift
                    } label: {
                        let chip = AIService.shared.chip(ClaudeService.shared.currentFeature)
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color(hex: chip.accentHex))
                                .frame(width: 6, height: 6)
                            Text(chip.label)
```

b) Replace:

```swift
        .onAppear { focused = true }
        .onChange(of: state.view) { _, view in
            if view == .prompt {
                state.fetchModelsIfNeeded(for: state.chatProvider)
            }
        }
        .onChange(of: state.chatProvider) { _, provider in
            if state.view == .prompt {
                state.fetchModelsIfNeeded(for: provider)
            }
        }
    }

    private func sendMessage() {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return }
        text = ""
        focused = false
        state.chatHistory.append(ChatMessage(role: .user, content: query))
        state.stateOverride = .thinking
        Task {
            await ClaudeService.shared.chat(query: query, context: state.promptContext, state: state)
            await MainActor.run { focused = true }
        }
    }
```

with:

```swift
        .onAppear { focused = true }
        .onChange(of: state.chatStreaming) { _, streaming in
            if !streaming { focused = true }
        }
    }

    private func sendMessage() {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !state.chatStreaming else { return }
        text = ""
        focused = false
        ClaudeService.shared.send(query: query, context: state.promptContext, state: state)
    }
```

c) Replace the whole `ModelPickerView`, from the line `struct ModelPickerView: View {` up to (not including) `struct ChatBubble: View {`, with the code below. It keeps the chip capsules and model rows. The chips are Auto, the three clouds, each ready local server, and Apple. Picking a chip or a model sets the current feature's choice.

```swift
struct ModelPickerView: View {
    @ObservedObject var state: AppState
    @Binding var isPresented: Bool

    /// A chip in the picker: Auto, a cloud provider, a local server, or Apple's model.
    enum Source: Hashable {
        case auto
        case cloud(AIProviderID)
        case server(String)
        case apple
    }

    private var feature: AIFeature { ClaudeService.shared.currentFeature }

    private var selected: Source {
        guard case .explicit(let ref) = state.choice(for: feature) else { return .auto }
        if ref.provider.isCloud { return .cloud(ref.provider) }
        if ref.provider == .apple { return .apple }
        return .server(ref.serverID ?? ref.provider.rawValue)
    }

    private var sources: [Source] {
        var list: [Source] = [.auto] + AICatalog.cloudOrder.map { .cloud($0) }
        list += state.localServers.filter(\.isReady).map { .server($0.serverID) }
        if state.appleStatus == .ready { list.append(.apple) }
        if !list.contains(selected) { list.append(selected) }
        return list
    }

    private func name(_ s: Source) -> String {
        switch s {
        case .auto: "Auto"
        case .cloud(let p): ChatProvider(p).displayName
        case .server(let id): state.localServers.first { $0.serverID == id }?.name ?? "Local server"
        case .apple: "Apple on-device"
        }
    }

    private func accent(_ s: Source) -> String {
        switch s {
        case .auto: "#A78BFA"
        case .cloud(let p): ChatProvider(p).accentHex
        case .server(let id): ChatProvider(state.localServers.first { $0.serverID == id }?.provider ?? .custom).accentHex
        case .apple: ChatProvider.apple.accentHex
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ChipFlowLayout(spacing: 6) {
                ForEach(sources, id: \.self) { source in
                    Button { pick(source) } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color(hex: accent(source)))
                                .frame(width: 7, height: 7)
                            Text(name(source))
                                .font(.system(size: 12, weight: selected == source ? .semibold : .regular))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(selected == source
                                    ? Color(hex: accent(source)).opacity(0.18)
                                    : Color.white.opacity(0.06))
                        .overlay(Capsule().stroke(
                            selected == source
                                ? Color(hex: accent(source)).opacity(0.5)
                                : Color.white.opacity(0.1),
                            lineWidth: 1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().opacity(0.2)

            modelListView
                .frame(height: 260, alignment: .top)
        }
        .padding(14)
        .background(Color(hex: "#16171B"))
        .onAppear {
            Task { await AIService.shared.discover() }
            if case .cloud(let p) = selected { state.fetchModelsIfNeeded(for: p) }
        }
    }

    /// Choosing a chip switches at once, keeping that provider's or server's remembered model.
    private func pick(_ source: Source) {
        guard source != selected else { return }
        let setting: FeatureSetting
        switch source {
        case .auto:
            setting = .auto
        case .cloud(let p):
            setting = .explicit(ModelRef(provider: p, model: AIService.shared.cloudModel(p)))
            state.fetchModelsIfNeeded(for: p)
        case .server(let id):
            guard let server = state.localServers.first(where: { $0.serverID == id }),
                  let model = AIService.shared.localModel(server) else { return }
            setting = .explicit(ModelRef(provider: server.provider, model: model, serverID: server.serverID))
        case .apple:
            setting = .explicit(ModelRef(provider: .apple, model: "system"))
        }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
            state.setChoice(setting, for: feature)
        }
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.surprised)
        SoundEngine.shared.play("pop")
    }

    private var currentModel: String? {
        if case .explicit(let ref) = state.choice(for: feature) { return ref.model }
        return nil
    }

    @ViewBuilder
    private var modelListView: some View {
        switch selected {
        case .auto:
            Text(AIService.shared.resolutionLine(feature))
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "#8A8F98"))
                .padding(.vertical, 4)
        case .cloud(let p):
            if state.loadingProviderModels.contains(p) {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Loading models…")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#8A8F98"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            } else if let error = state.providerModelFetchError[p] {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#8A8F98"))
                    .padding(.vertical, 4)
            } else if let models = state.fetchedProviderModels[p] {
                modelRows(models.map { ($0.id, $0.label ?? $0.id) }, accent: ChatProvider(p).accentHex) { id in
                    ModelRef(provider: p, model: id)
                }
            }
        case .server(let id):
            if let server = state.localServers.first(where: { $0.serverID == id }) {
                modelRows(server.models.map { ($0.id, $0.id) }, accent: ChatProvider(server.provider).accentHex) { model in
                    ModelRef(provider: server.provider, model: model, serverID: server.serverID)
                }
            }
        case .apple:
            modelRows([("system", "Apple on-device")], accent: ChatProvider.apple.accentHex) { _ in
                ModelRef(provider: .apple, model: "system")
            }
        }
    }

    private func modelRows(_ models: [(id: String, label: String)], accent: String,
                           ref: @escaping (String) -> ModelRef) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(models, id: \.id) { model in
                    let isCurrent = currentModel == model.id
                    Button {
                        state.setChoice(.explicit(ref(model.id)), for: feature)
                        isPresented = false
                        SoundEngine.shared.play("blip")
                    } label: {
                        HStack {
                            Text(model.label)
                                .font(.system(size: 12))
                                .foregroundColor(isCurrent ? Color(hex: accent) : Color(hex: "#C8CDD4"))
                            Spacer()
                            if isCurrent {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(Color(hex: accent))
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(isCurrent ? Color(hex: accent).opacity(0.1) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}
```

d) AI pills:

```swift
        case "ai_ollama":     return !AppState.shared.ollamaServerURL.isEmpty
        case "ai_lmstudio":   return !AppState.shared.lmstudioServerURL.isEmpty
```

becomes

```swift
        case "ai_ollama":     return AppState.shared.localServers.contains { $0.serverID == "ollama" && $0.isReady }
        case "ai_lmstudio":   return AppState.shared.localServers.contains { $0.serverID == "lmstudio" && $0.isReady }
```

and

```swift
                if provider.isLocal {
                    let model = provider == .ollama ? appState.ollamaChatModel : appState.lmstudioChatModel
                    return "Connected · \(model)"
                }
```

becomes

```swift
                if provider.isLocal {
                    let server = appState.localServers.first { $0.serverID == provider.rawValue }
                    return "Connected · \(server.flatMap(AIService.shared.localModel) ?? "")"
                }
```

e) Replace the body of `switchChatProvider`: everything from `func switchChatProvider(_ provider: ChatProvider) {` up to (not including) `extension Color {`. Keep its doc comment and `@MainActor`.

```swift
func switchChatProvider(_ provider: ChatProvider) {
    let state = AppState.shared
    let id = provider.providerID
    var ref: ModelRef?
    if id.isCloud {
        ref = ModelRef(provider: id, model: AIService.shared.cloudModel(id))
    } else if let server = state.localServers.first(where: { $0.serverID == id.rawValue }),
              let model = AIService.shared.localModel(server) {
        ref = ModelRef(provider: id, model: model, serverID: server.serverID)
    }
    if let ref, state.choice(for: .chat) != .explicit(ref) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
            state.setChoice(.explicit(ref), for: .chat)
        }
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.surprised)
        SoundEngine.shared.play("pop")
    }
    state.view = .prompt
}
```

- [ ] **Step 11: Build and run every AI suite**

Run: `cd NotchBuddy && xcodegen && xcodebuild -project NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug build 2>&1 | grep -E "error:|BUILD" ; cd ..`
Expected: `** BUILD SUCCEEDED **`.

Run: `for t in router stream budget attachments providers runner discovery platform settings; do bash scripts/test-ai-$t.sh | tail -1; done; bash scripts/test-chat-parsing.sh | tail -1`
Expected: `All tests passed.` ten times.

- [ ] **Step 12: Manual check**

Quit any running NotchMeow first: two copies would fight over the hook socket. Then build and launch the Debug build:
```bash
cd NotchBuddy && xcodebuild -project NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath build build | tail -1; cd ..
NotchBuddy/build/Build/Products/Debug/NotchMeow.app/Contents/MacOS/NotchMeow
```
Expected:
- With a real Anthropic key, open the chat: the chip reads `Auto · claude-sonnet-5-5` (or your remembered model), and a question streams in.
- The picker shows `Auto`, `Anthropic`, `Google`, `OpenAI`, plus every running local server.
- With Ollama or LM Studio running and no key, the chip names the local model, and the reply streams.
- Nothing runs while the island is hidden: after launch, leave it alone until it hides. `nettop -p NotchMeow` shows no connection to ports 11434, 1234, 8080 or 1337. The first time the island opens, the four localhost probes appear once, and they come back only when the picker or Settings opens, or when Auto needs a local model.
- (Captions, sources, Stop and the empty state arrive in Task 12. Settings → Local models still shows the old Connect box until Task 13.)

- [ ] **Step 13: Commit**

```bash
git add NotchBuddy/Sources/App/AI/Core/ProviderFactory.swift \
    NotchBuddy/Sources/App/AI/AIService.swift \
    tests/AISettingsTests.swift \
    scripts/test-ai-settings.sh \
    NotchBuddy/Sources/App/IslandTypes.swift \
    NotchBuddy/Sources/App/AppState.swift \
    NotchBuddy/Sources/App/ClaudeService.swift \
    NotchBuddy/Sources/App/FileDropView.swift \
    NotchBuddy/Sources/App/AppDelegate.swift \
    NotchBuddy/Sources/App/IslandViewContent.swift \
    .github/workflows/build.yml \
    NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -m "feat(ai): route the chat through Auto, any provider and one local retry

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---
### Task 12: Chat UI — caption, sources, notices, Stop, empty state, note actions, drop card

**Files:**
- Modify: `NotchBuddy/Sources/App/IslandViewContent.swift` (PromptView, ChatBubble, NoteView, ChooseView; new `ReplyFooter`, `AIEmptyStateView`, `showNote`)
- Modify: `NotchBuddy/Sources/App/UploadCanvasView.swift`
- Modify: `NotchBuddy/Sources/App/AppState.swift` (`openModelPicker`)

**Interfaces:**
- Consumes:
  - from Task 11: `ChatMessage.caption/sources/notice/interrupted`, `AppState.chatNotice/chatStreaming/dropReaderLine/noteAction`;
  - from Task 11: `ClaudeService.stop()/continueReply(state:)/retryLast(state:)`, `AIService.resolve/prewarm`;
  - from Task 8: `AIMessages.interrupted/emptyStateTitle/localGuide`, `AIAction`;
  - `safeWebURL(_:)` (existing).
- Produces:
  - `ReplyFooter(message:)`, `AIEmptyStateView(state:)`;
  - `@MainActor func showNote(_:action:markdown:state:)`, `NoteView.title(_:)`;
  - `AppState.openModelPicker`.
- Style: shipping views keep their look. New lines reuse existing type and colours:
  - captions and notices: 10.5 pt, `#7B8089`;
  - links: `#A5B4FC`;
  - drop-card line: 12.5 pt, `#9398A1`, the card's own subtitle style;
  - buttons: `PrimaryButton`, `SecondaryButton` and the existing `SendButtonStyle`.
  NoteView looks exactly as before unless its current message carries an action.

- [ ] **Step 1: The typing row shows "Waking up…" and the busy countdown**

In `NotchBuddy/Sources/App/IslandViewContent.swift`, replace:

```swift
                                if state.stateOverride != nil {
                                    HStack { TypingDotsView(); Spacer(minLength: 32) }
                                        .id("typing")
                                }
```

with:

```swift
                                if state.stateOverride != nil || state.chatNotice != nil {
                                    HStack(spacing: 8) {
                                        if state.stateOverride != nil { TypingDotsView() }
                                        if let notice = state.chatNotice {
                                            Text(notice.text)
                                                .font(.system(size: 10.5))
                                                .foregroundColor(Color(hex: "#7B8089"))
                                            if notice.cancellable {
                                                Button("Cancel") { ClaudeService.shared.stop() }
                                                    .font(.system(size: 10.5, weight: .medium))
                                                    .foregroundColor(Color(hex: "#C8CDD4"))
                                                    .buttonStyle(.plain)
                                            }
                                        }
                                        Spacer(minLength: 32)
                                    }
                                    .id("typing")
                                }
```

- [ ] **Step 2: Empty state when nothing is set up**

Replace:

```swift
                    .frame(maxHeight: .infinity)
                } else {
                    Spacer()
                }
```

with:

```swift
                    .frame(maxHeight: .infinity)
                } else if AIService.shared.resolve(ClaudeService.shared.currentFeature).primary == nil {
                    AIEmptyStateView(state: state)
                        .frame(maxHeight: .infinity)
                } else {
                    Spacer()
                }
```

- [ ] **Step 3: Send becomes Stop while a reply streams**

Replace:

```swift
                    Button(action: sendMessage) {
                        Image(systemName: "arrow.up")
                            .font(.system(size: 11, weight: .semibold))
                            .foregroundColor(Color(hex: "#0B0C0E"))
                    }
                    .buttonStyle(SendButtonStyle())
                    .disabled(text.isEmpty)
```

with:

```swift
                    if state.chatStreaming {
                        Button { ClaudeService.shared.stop() } label: {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(Color(hex: "#0B0C0E"))
                        }
                        .buttonStyle(SendButtonStyle())
                        .accessibilityLabel("Stop")
                    } else {
                        Button(action: sendMessage) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Color(hex: "#0B0C0E"))
                        }
                        .buttonStyle(SendButtonStyle())
                        .disabled(text.isEmpty)
                    }
```

- [ ] **Step 4: Pre-warm on open, and open the picker from "Choose model"**

Replace:

```swift
        .onAppear { focused = true }
        .onChange(of: state.chatStreaming) { _, streaming in
```

with:

```swift
        .onAppear {
            focused = true
            AIService.shared.prewarm(ClaudeService.shared.currentFeature)
        }
        .onChange(of: state.openModelPicker) { _, open in
            if open {
                showModelPicker = true
                state.openModelPicker = false
            }
        }
        .onChange(of: state.chatStreaming) { _, streaming in
```

In `NotchBuddy/Sources/App/AppState.swift`, replace:

```swift
    /// Optional button for the current note (only shown while `noteMessage` is the one it was made for).
    @Published var noteAction: NoteAction? = nil
```

with:

```swift
    /// Optional button for the current note (only shown while `noteMessage` is the one it was made for).
    @Published var noteAction: NoteAction? = nil
    /// Set to open the model picker from an error's "Choose model".
    @Published var openModelPicker: Bool = false
```

- [ ] **Step 5: Caption, sources, notice and Continue · Retry under each reply; the empty-state view; `showNote`**

In `ChatBubble`, replace the assistant branch through the end of the struct:

```swift
                } else {
                    ChatMarkdownView(markdown: message.content)
                    Spacer(minLength: 8)
                }
            }
        }
    }
}
```

with:

```swift
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        ChatMarkdownView(markdown: message.content)
                        ReplyFooter(message: message)
                    }
                    Spacer(minLength: 8)
                }
            }
        }
    }
}

/// Under a reply: a quiet notice, web-search sources, then `cloud · model` (and Continue · Retry
/// when the stream was cut). Same small grey type as the model chip.
struct ReplyFooter: View {
    let message: ChatMessage

    private static let grey = Color(hex: "#7B8089")

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let notice = message.notice {
                Text(notice)
                    .font(.system(size: 10.5))
                    .foregroundColor(Self.grey)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !message.sources.isEmpty {
                ChipFlowLayout(spacing: 8) {
                    ForEach(message.sources, id: \.url) { source in
                        if let url = safeWebURL(source.url) {
                            Link(source.title.isEmpty ? (url.host ?? source.url) : source.title, destination: url)
                                .font(.system(size: 10.5))
                                .foregroundColor(Color(hex: "#A5B4FC"))
                                .lineLimit(1)
                        }
                    }
                }
            }
            if message.caption != nil || message.interrupted {
                HStack(spacing: 6) {
                    if let caption = message.caption {
                        Text(caption).font(.system(size: 10.5)).foregroundColor(Self.grey)
                    }
                    if message.interrupted {
                        Text(AIMessages.interrupted).font(.system(size: 10.5)).foregroundColor(Self.grey)
                        Button("Continue") { ClaudeService.shared.continueReply(state: .shared) }
                        Text("·").foregroundColor(Self.grey)
                        Button("Retry") { ClaudeService.shared.retryLast(state: .shared) }
                    }
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(Color(hex: "#C8CDD4"))
                .buttonStyle(.plain)
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            guard let safe = safeWebURL(url.absoluteString) else { return .discarded }
            NSWorkspace.shared.open(safe)
            return .handled
        })
    }
}

/// No key and no model: the two ways to give the cat a brain.
struct AIEmptyStateView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AIMessages.emptyStateTitle).font(.system(size: 13, weight: .semibold))
            HStack(spacing: 8) {
                PrimaryButton("Add a cloud key") {
                    NotificationCenter.default.post(name: .openFullSettings, object: "chat")
                }
                SecondaryButton("Use a local model") {
                    showNote(AIMessages.localGuide, action: nil, markdown: true, state: state)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Shows a note with its optional button (Open Settings, billing page, guide, choose model).
@MainActor
func showNote(_ message: String, action: AIAction?, markdown: Bool = false, state: AppState) {
    state.noteMessage = message
    state.noteAction = (action != nil || markdown)
        ? NoteAction(message: message, action: action ?? .openGuide, markdown: markdown) : nil
    state.view = .note
}
```

- [ ] **Step 6: NoteView shows the error's one action**

Replace the whole `NoteView`:

```swift
struct NoteView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ZStack(alignment: .leading) {
            CardBackground(wash: nil)
            VStack(alignment: .leading, spacing: 4) {
                Text(state.noteMessage ?? "")
                    .font(.system(size: 15, weight: .semibold))
            }
            .padding(.leading, 98)
        }
    }
}
```

with:

```swift
struct NoteView: View {
    @ObservedObject var state: AppState

    /// The action made for this exact message (other notes never show a stale button).
    private var currentAction: NoteAction? {
        guard let a = state.noteAction, a.message == state.noteMessage else { return nil }
        return a
    }

    static func title(_ action: AIAction) -> String {
        switch action {
        case .openSettings: "Open Settings"
        case .openBilling: "Open billing page"
        case .openGuide: "Open guide"
        case .chooseModel: "Choose model"
        }
    }

    private func perform(_ action: AIAction) {
        switch action {
        case .openSettings:
            NotificationCenter.default.post(name: .openFullSettings, object: "chat")
        case .openBilling(let url):
            if let safe = safeWebURL(url.absoluteString) { NSWorkspace.shared.open(safe) }
        case .openGuide:
            showNote(AIMessages.localGuide, action: nil, markdown: true, state: state)
        case .chooseModel:
            state.stateOverride = nil
            state.view = .prompt
            state.openModelPicker = true
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            CardBackground(wash: nil)
            VStack(alignment: .leading, spacing: 4) {
                if let note = currentAction, note.markdown {
                    Text(.init(note.message))
                        .font(.system(size: 13, weight: .semibold))
                        .tint(Color(hex: "#A5B4FC"))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(state.noteMessage ?? "")
                        .font(.system(size: 15, weight: .semibold))
                }
                if let note = currentAction, !note.markdown {
                    SecondaryButton(Self.title(note.action)) { perform(note.action) }
                        .padding(.top, 6)
                }
            }
            .padding(.leading, 98)
            // Only a note with a button or a link gets a right margin: every other note lays out as it shipped.
            .padding(.trailing, currentAction == nil ? 0 : 18)
        }
    }
}
```

- [ ] **Step 7: The drop card says who will read the file**

In `ChooseView`, replace:

```swift
                HStack(spacing: 8) {
                    PrimaryButton("Ask a question") { state.view = .prompt }
                    SecondaryButton("Send by email") { state.view = .mail }
                }
```

with:

```swift
                HStack(spacing: 8) {
                    PrimaryButton("Ask a question") { state.view = .prompt }
                    SecondaryButton("Send by email") { state.view = .mail }
                    if let reader = state.dropReaderLine {
                        Text(reader)
                            .font(.system(size: 12.5))
                            .foregroundColor(Color(hex: "#9398A1"))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
```

In `NotchBuddy/Sources/App/UploadCanvasView.swift`, replace:

```swift
        cCtx.draw(btn2, at: CGPoint(x:350, y:126), anchor: .center)
    }
```

with:

```swift
        cCtx.draw(btn2, at: CGPoint(x:350, y:126), anchor: .center)

        // Who will read the file if asked (or why it can't be read), beside the buttons.
        if let reader = state.dropReaderLine {
            let readerText = Text(reader)
                .font(.system(size:12.5))
                .foregroundColor(Color(hex:"#9398A1"))
            cCtx.draw(readerText, at: CGPoint(x:422, y:126), anchor: .leading)
        }
    }
```

The canvas line sits right of "Send by email" (x 422), in the card's subtitle style. `AIMessages.dropReader` shortens long model IDs so the line stays inside the 640 pt card.

- [ ] **Step 8: Build**

Run: `cd NotchBuddy && xcodegen && xcodebuild -project NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug build 2>&1 | grep -E "error:|BUILD" ; cd ..`
Expected: `** BUILD SUCCEEDED **`.

- [ ] **Step 9: Manual check with the fake server**

Quit NotchMeow, then:
```bash
python3 tests/fake_local_llm.py /tmp/nm-port --log /tmp/nm-log.jsonl &
cd NotchBuddy && xcodebuild -project NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug -derivedDataPath build build | tail -1; cd ..
NM_AI_BASE_URL_OVERRIDE=http://127.0.0.1:$(cat /tmp/nm-port) NotchBuddy/build/Build/Products/Debug/NotchMeow.app/Contents/MacOS/NotchMeow
```
The override needs a cloud key to route to the cloud. If no real Anthropic key is saved (pasting overwrites it), paste `test` in Settings → Anthropic API → Save, then remove it after the check.

Expected:
- **Reply:** a question gets "Cats sleep a lot.", a `Cat sleep facts` link under it (opens in the browser), and `cloud · claude-sonnet-5-5` under that.
- **Stop:** the send arrow turns into a stop square while the reply streams.
- **Busy:** restart the fake server with `--fail 429` (keep the same port file). With no local server running: "Claude is busy. Trying again in 2 s." with Cancel, then one retry. With Ollama or LM Studio running, Auto answers locally instead, with "Claude's busy right now, so … answered instead." above `local · …`.
- **Key rejected:** with `--fail 401`: "Your Anthropic key was rejected." and an **Open Settings** button that opens Settings → Chat.
- **Drop card:** drop a `.txt`; the card says "Claude will read this". Drop a `.zip`: "I can't read this kind of file, but I can email it.", plus the annoyed emote and sound.
- **Empty state:** with no key and no local server, the chat shows "Pick a brain for me first." with **Add a cloud key** and **Use a local model** (a note with Ollama and LM Studio links).

Stop the fake server: `kill %1`.

- [ ] **Step 10: Commit**

```bash
git add NotchBuddy/Sources/App/IslandViewContent.swift \
    NotchBuddy/Sources/App/UploadCanvasView.swift \
    NotchBuddy/Sources/App/AppState.swift
git commit -m "feat(chat): label each reply, show sources, Stop, the empty state and who reads a dropped file

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---
### Task 13: Settings — "Chat" becomes "AI"

**Files:**
- Create: `NotchBuddy/Sources/App/AISettingsViews.swift` (`LocalServerRow`, `AddServerSheet`)
- Modify: `NotchBuddy/Sources/App/SettingsView.swift`
- Modify: `NotchBuddy/Sources/App/AppState.swift` (drop the three pre-E1 properties)
- Modify: `NotchBuddy/project.yml` (`NSLocalNetworkUsageDescription` on both targets)

**Interfaces:**
- Consumes:
  - from Task 11: `AIService.shared.discover()/key(_:)/cloudKeys/cloudModel(_:)/resolutionLine(_:)/listCloudModels(_:key:)`, `AppState.choice(for:)/setChoice(_:for:)/preferredCloud/customServers/localServers/appleStatus`, `CustomServer`, `KeychainStore.remove(_:)`;
  - from Task 9: `Discovery.probe(_:installed:timeout:session:)`, `DiscoveredServer`, `ServerStatus`.
- Produces: `LocalServerRow(server:onRemove:)` and `AddServerSheet(isPresented:onAdd:)`.
- The section's tag stays `"chat"`: it is persisted in `settingsSection` and used by `.openFullSettings`. Only the title changes to "AI".
- **Box 1 "Which model answers":**
  - one row each for Chat and File questions: Auto, Cloud (providers with a key), Local (by server), Apple on-device;
  - under Auto, the resolution line ("Claude Sonnet 5.5 · falls back to Local · qwen3.5:2b");
  - a Preferred cloud segmented control, shown only when both the Claude and OpenAI keys exist.
- **Box 2:** today's Anthropic and other-provider key fields, unchanged in look. Save now checks the key with a model-list call and shows ✓ or ✗. The second box's title changes from "Chat — other providers" to "Other cloud providers".
- **Box 3 "Local models":**
  - one row per server, with the status dot and "Running · N models", "Server off", "Not installed" (with a Get link) or "Update Ollama to use it here.";
  - added servers show "network · unencrypted on your network" on plain http;
  - the Apple status line, then **Rescan** and **Add server…**.
- **Local Network permission:** network addresses only ever come from the user. macOS 15's Local Network prompt, which carries `NSLocalNetworkUsageDescription`, can only appear after **Add server…**.

- [ ] **Step 1: Write `NotchBuddy/Sources/App/AISettingsViews.swift`**

```swift
import SwiftUI

/// One local server in Settings → AI → Local models: `● Running · 4 models`, `○ Server off`, `○ Not installed`.
struct LocalServerRow: View {
    let server: DiscoveredServer
    let onRemove: () -> Void

    private static let getURLs: [AIProviderID: String] = [
        .ollama: "https://ollama.com/download", .lmstudio: "https://lmstudio.ai",
        .jan: "https://jan.ai", .llamacpp: "https://github.com/ggml-org/llama.cpp",
    ]

    private var statusText: String {
        switch server.status {
        case .running(let models):
            models.isEmpty ? "Running · no models yet" : "Running · \(models.count) model\(models.count == 1 ? "" : "s")"
        case .off: "Server off"
        case .notInstalled: "Not installed"
        case .outdated: "Update \(server.name) to use it here."
        }
    }

    private var isUserServer: Bool { server.serverID.hasPrefix(CustomServer.idPrefix) }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                if server.isReady {
                    Circle().fill(Color(hex: "#22C55E")).frame(width: 8, height: 8)
                } else {
                    Circle().stroke(Color.secondary, lineWidth: 1).frame(width: 8, height: 8)
                }
                Text(server.name).font(.system(size: 12, weight: .semibold))
                Text(statusText).font(.system(size: 11)).foregroundColor(.secondary)
                Spacer()
                if server.status == .notInstalled || server.status == .outdated,
                   let link = Self.getURLs[server.provider].flatMap(URL.init(string:)) {
                    Link(server.status == .outdated ? "Update" : "Get \(server.name)", destination: link)
                        .font(.system(size: 11))
                }
                if isUserServer {
                    Button("Remove", action: onRemove).buttonStyle(.bordered).controlSize(.small)
                }
            }
            if server.placement == .network {
                Text(server.baseURL.hasPrefix("http://") ? "network · unencrypted on your network" : "network")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
                    .padding(.leading, 16)
            }
        }
    }
}

/// Settings → AI → Add server…: a URL and an optional key, checked before it is saved.
struct AddServerSheet: View {
    @Binding var isPresented: Bool
    let onAdd: (_ name: String, _ baseURL: String, _ key: String?) -> Void

    @State private var url = ""
    @State private var key = ""
    @State private var checking = false
    @State private var error: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add a server").font(.headline)
            Text("An OpenAI-compatible server on this Mac or your network (Ollama, LM Studio, llama.cpp…).")
                .font(.system(size: 11))
                .foregroundColor(.secondary)
            TextField("http://studio-pc.local:1234", text: $url)
                .textFieldStyle(.roundedBorder)
            SecureField("API key (optional)", text: $key)
                .textFieldStyle(.roundedBorder)
            if let error {
                Text(error).font(.system(size: 11)).foregroundColor(.red)
            }
            HStack {
                Spacer()
                Button("Cancel") { isPresented = false }
                Button(checking ? "Checking…" : "Add") { add() }
                    .buttonStyle(.borderedProminent)
                    .disabled(checking || url.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(16)
        .frame(width: 380)
    }

    private func add() {
        let base = AIURL.normalise(url)
        guard let parsed = URL(string: base), let scheme = parsed.scheme?.lowercased(),
              scheme == "http" || scheme == "https", let host = parsed.host else {
            error = "Use an http:// or https:// address."
            return
        }
        checking = true
        error = nil
        let apiKey = key.isEmpty ? nil : key
        let target = ProbeTarget(serverID: "new", provider: .custom, name: host, baseURL: base, apiKey: apiKey)
        Task {
            let found = await Discovery.probe(target, installed: true, timeout: AICatalog.Timeouts.connectLocal,
                                              session: .shared)
            checking = false
            if case .running = found.status {
                onAdd(host, base, apiKey)
                isPresented = false
            } else {
                error = "Couldn't reach a model server at \(base)."
            }
        }
    }
}
```

- [ ] **Step 2: Replace the Connect state in `SettingsView`**

In `NotchBuddy/Sources/App/SettingsView.swift`, replace:

```swift
    @State private var ollamaURL:    String = AppState.shared.ollamaServerURL
    @State private var lmstudioURL:  String = AppState.shared.lmstudioServerURL
    @State private var connectingOllama:    Bool = false
    @State private var connectingLMStudio:  Bool = false
```

with:

```swift
    /// ✓ / ✗ after a pasted key was checked with a model-list call.
    @State private var keyWorks: [AIProviderID: Bool] = [:]
    @State private var showAddServer = false
    @State private var rescanning = false
```

Rename the sidebar row and the title (the tag stays `"chat"`):

```swift
SettingsSidebarRow(title: "Chat",         icon: "bubble.left.and.bubble.right.fill", color: "#E07950").tag("chat")
```

becomes

```swift
SettingsSidebarRow(title: "AI",           icon: "bubble.left.and.bubble.right.fill", color: "#E07950").tag("chat")
```

and

```swift
        case "chat":         return "Chat"
```

becomes

```swift
        case "chat":         return "AI"
```

- [ ] **Step 3: The AI section**

Replace everything from `    // MARK: - Chat section` up to (not including) `    // MARK: - Integrations section` with:

```swift
    // MARK: - AI section (tag stays "chat": it is persisted in "settingsSection")

    @ViewBuilder private var chatSection: some View {
        GroupBox("Which model answers") {
            VStack(alignment: .leading, spacing: 10) {
                ForEach(AIFeature.allCases, id: \.self) { feature in
                    VStack(alignment: .leading, spacing: 3) {
                        HStack(spacing: 8) {
                            Text(feature == .chat ? "Chat" : "File questions")
                                .frame(width: 110, alignment: .leading)
                            Picker("", selection: choiceBinding(feature)) { choiceItems(feature) }
                                .labelsHidden()
                        }
                        if state.choice(for: feature) == .auto {
                            Text(AIService.shared.resolutionLine(feature))
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                                .padding(.leading, 118)
                        }
                    }
                }
                if AIService.shared.cloudKeys.isSuperset(of: [.anthropic, .openai]) {
                    HStack(spacing: 8) {
                        Text("Preferred cloud").frame(width: 110, alignment: .leading)
                        Picker("", selection: $state.preferredCloud) {
                            Text("Claude").tag(AIProviderID.anthropic)
                            Text("OpenAI").tag(AIProviderID.openai)
                        }
                        .labelsHidden()
                        .pickerStyle(.segmented)
                        .frame(width: 180)
                    }
                }
            }
            .padding(6)
        }

        GroupBox("Anthropic API") {
            VStack(alignment: .leading, spacing: 8) {
                HStack(spacing: 6) {
                    SecureField("API key (sk-ant-…)", text: $apiKey)
                        .textFieldStyle(.roundedBorder)
                    keyMark(.anthropic)
                }
                Button("Save") { saveKey(.anthropic, apiKey) }
                    .buttonStyle(.borderedProminent)

                Divider().padding(.vertical, 2)

                Picker("Model", selection: $modelChoice) {
                    ForEach(displayModels, id: \.id) { preset in
                        Text(preset.label).tag(preset.id)
                    }
                    Text("Custom…").tag(Self.customModelTag)
                }
                .onChange(of: modelChoice) { _, choice in
                    if choice != Self.customModelTag {
                        state.claudeModel = choice
                    } else {
                        applyCustomModel(customModel)
                    }
                }

                if modelChoice == Self.customModelTag {
                    TextField("Model ID (e.g. claude-sonnet-5-5)", text: $customModel)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: customModel) { _, value in applyCustomModel(value) }
                }

                Text("Used by the chat. The list comes from your Anthropic account.")
                    .font(.system(size: 11))
                    .foregroundColor(.secondary)
            }
            .padding(6)
        }

        GroupBox("Other cloud providers") {
            VStack(alignment: .leading, spacing: 12) {
                Text("To use Google Gemini or OpenAI from the chat. Keys are stored in the Keychain.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                HStack(spacing: 8) {
                    Circle().fill(Color(hex: "#4285F4")).frame(width: 8, height: 8)
                    Text("Google AI").font(.system(size: 12, weight: .semibold))
                    keyMark(.google)
                }
                SecureField("API key (AI Studio)", text: $googleKey)
                    .textFieldStyle(.roundedBorder)
                Button("Save") { saveKey(.google, googleKey) }
                    .buttonStyle(.borderedProminent)

                Divider()

                HStack(spacing: 8) {
                    Circle().fill(Color(hex: "#10A37F")).frame(width: 8, height: 8)
                    Text("OpenAI").font(.system(size: 12, weight: .semibold))
                    keyMark(.openai)
                }
                SecureField("API key (sk-…)", text: $openAIKey)
                    .textFieldStyle(.roundedBorder)
                Button("Save") { saveKey(.openai, openAIKey) }
                    .buttonStyle(.borderedProminent)
            }
            .padding(.vertical, 4)
        }

        GroupBox("Local models") {
            VStack(alignment: .leading, spacing: 10) {
                Text("Models running on this Mac, or on a server you add. Found automatically on this Mac only.")
                    .font(.system(size: 12))
                    .foregroundColor(.secondary)

                ForEach(state.localServers, id: \.serverID) { server in
                    LocalServerRow(server: server) { removeServer(server.serverID) }
                }

                if let line = state.appleStatus.line {
                    HStack(spacing: 8) {
                        Circle()
                            .fill(state.appleStatus == .ready ? Color(hex: "#22C55E") : Color.secondary.opacity(0.5))
                            .frame(width: 8, height: 8)
                        Text("Apple on-device").font(.system(size: 12, weight: .semibold))
                        Text(line).font(.system(size: 11)).foregroundColor(.secondary)
                    }
                }

                HStack(spacing: 8) {
                    Button(rescanning ? "Scanning…" : "Rescan") {
                        rescanning = true
                        Task {
                            await AIService.shared.discover()
                            rescanning = false
                        }
                    }
                    .disabled(rescanning)
                    Button("Add server…") { showAddServer = true }
                }
                .buttonStyle(.bordered)
            }
            .padding(.vertical, 4)
        }
        .onAppear { Task { await AIService.shared.discover() } }
        .sheet(isPresented: $showAddServer) {
            AddServerSheet(isPresented: $showAddServer) { name, url, key in
                let server = CustomServer(id: CustomServer.newID(), name: name, baseURL: url)
                if let key, !key.isEmpty { KeychainStore.shared.set(server.keychainAccount, value: key) }
                state.customServers.append(server)
                Task { await AIService.shared.discover() }
            }
        }
    }

    private func choiceBinding(_ feature: AIFeature) -> Binding<FeatureSetting> {
        Binding(get: { state.choice(for: feature) }, set: { state.setChoice($0, for: feature) })
    }

    /// Auto, then Cloud (providers with a key), Local (by server), Apple on-device.
    @ViewBuilder private func choiceItems(_ feature: AIFeature) -> some View {
        Text("Auto").tag(FeatureSetting.auto)
        let cloud = AICatalog.cloudOrder.filter { AIService.shared.key($0) != nil }
        if !cloud.isEmpty {
            Section("Cloud") {
                ForEach(cloud, id: \.self) { p in
                    let model = AIService.shared.cloudModel(p)
                    Text("\(ChatProvider(p).displayName) · \(model)")
                        .tag(FeatureSetting.explicit(ModelRef(provider: p, model: model)))
                }
            }
        }
        let servers = state.localServers.filter(\.isReady)
        if !servers.isEmpty {
            Section("Local") {
                ForEach(servers, id: \.serverID) { server in
                    ForEach(server.models, id: \.id) { m in
                        Text("\(server.name) · \(m.id)")
                            .tag(FeatureSetting.explicit(ModelRef(provider: server.provider, model: m.id, serverID: server.serverID)))
                    }
                }
            }
        }
        if state.appleStatus == .ready {
            Section("Apple on-device") {
                Text("Apple on-device").tag(FeatureSetting.explicit(ModelRef(provider: .apple, model: "system")))
            }
        }
        // A choice that isn't available right now (server off) still shows, so the menu keeps it.
        if case .explicit(let ref) = state.choice(for: feature), !isListed(ref) {
            Text("\(ChatProvider(ref.provider).displayName) · \(ref.model) (not running)")
                .tag(FeatureSetting.explicit(ref))
        }
    }

    private func isListed(_ ref: ModelRef) -> Bool {
        if ref.provider.isCloud { return AIService.shared.key(ref.provider) != nil && AIService.shared.cloudModel(ref.provider) == ref.model }
        if ref.provider == .apple { return state.appleStatus == .ready }
        return state.localServers.contains { $0.isReady && $0.serverID == (ref.serverID ?? ref.provider.rawValue)
            && $0.models.contains { $0.id == ref.model } }
    }

    @ViewBuilder private func keyMark(_ provider: AIProviderID) -> some View {
        if let works = keyWorks[provider] {
            Image(systemName: works ? "checkmark.circle.fill" : "xmark.circle.fill")
                .foregroundColor(works ? Color(hex: "#22C55E") : .red)
                .accessibilityLabel(works ? "Key works" : "Key rejected")
        }
    }

    /// Saves the key, then checks it straight away with a model-list call.
    private func saveKey(_ provider: AIProviderID, _ value: String) {
        let key = value.trimmingCharacters(in: .whitespacesAndNewlines)
        KeychainStore.shared.set(AICatalog.info(provider).keychainKey!, value: key)
        state.fetchedProviderModels[provider] = nil
        keyWorks[provider] = nil
        guard !key.isEmpty else { statusMessage = "Key removed."; return }
        statusMessage = "Checking the key…"
        Task {
            let works = !(await AIService.shared.listCloudModels(provider, key: key)).isEmpty
            keyWorks[provider] = works
            statusMessage = works ? "✓ Key saved and working." : "❌ \(AICatalog.info(provider).name) didn't accept this key."
        }
    }

    private func removeServer(_ id: String) {
        guard let server = state.customServers.first(where: { $0.id == id }) else { return }
        KeychainStore.shared.remove(server.keychainAccount)
        state.customServers.removeAll { $0.id == id }
        state.localServers.removeAll { $0.serverID == id }
        if case .explicit(let ref) = state.choice(for: .chat), ref.serverID == id { state.setChoice(.auto, for: .chat) }
        if case .explicit(let ref) = state.choice(for: .files), ref.serverID == id { state.setChoice(.auto, for: .files) }
    }
```

- [ ] **Step 4: Remove the old Connect action and update the pill hint**

Delete `connectLocal(provider:)`: everything from `    private func connectLocal(provider: ChatProvider) async {` up to (not including) `    private func installHooks() {`.

In `pillRow(_:)`, replace:

```swift
            if def.category == .ai {
                if let provider = ChatProvider(pillID: def.id), provider.isLocal {
                    let url = provider == .ollama ? state.ollamaServerURL : state.lmstudioServerURL
                    if url.isEmpty { return "Not connected" }
                } else {
```

with:

```swift
            if def.category == .ai {
                if let provider = ChatProvider(pillID: def.id), provider.isLocal {
                    if !state.localServers.contains(where: { $0.serverID == provider.rawValue && $0.isReady }) {
                        return "Not connected"
                    }
                } else {
```

- [ ] **Step 5: Drop the pre-E1 properties from `AppState`**

Delete this block (added in Task 11 for the old Settings):

```swift
    // Pre-E1 chat settings, still read by Settings until it moves to the AI section (Task 13).
    @Published var chatProvider: ChatProvider = .anthropic {
        didSet { UserDefaults.standard.set(chatProvider.rawValue, forKey: "chatProvider") }
    }
    @Published var ollamaServerURL: String = "" {
        didSet { UserDefaults.standard.set(ollamaServerURL, forKey: "ollamaServerURL") }
    }
    @Published var lmstudioServerURL: String = "" {
        didSet { UserDefaults.standard.set(lmstudioServerURL, forKey: "lmstudioServerURL") }
    }
```

and these three lines in `init()`:

```swift
        if let v = ud.string(forKey: "chatProvider"), let p = ChatProvider(rawValue: v) { chatProvider = p }
        if let v = ud.string(forKey: "ollamaServerURL"), !v.isEmpty { ollamaServerURL = v }
        if let v = ud.string(forKey: "lmstudioServerURL"), !v.isEmpty { lmstudioServerURL = v }
```

- [ ] **Step 6: Declare the Local Network use**

In `NotchBuddy/project.yml`, under the `NotchBuddy` target's `info: properties:`, replace:

```yaml
        NSAccessibilityUsageDescription: "Pour lire le titre de la fenêtre active et l'attacher comme contexte."
```

with:

```yaml
        NSAccessibilityUsageDescription: "Pour lire le titre de la fenêtre active et l'attacher comme contexte."
        NSLocalNetworkUsageDescription: "Pour joindre un serveur de modèles d'IA que vous avez ajouté sur votre réseau."
```

Under the `NotchMeowAppStore` target's `info: properties:`, replace:

```yaml
        ITSAppUsesNonExemptEncryption: NO
```

with:

```yaml
        ITSAppUsesNonExemptEncryption: NO
        NSLocalNetworkUsageDescription: "Pour joindre un serveur de modèles d'IA que vous avez ajouté sur votre réseau."
```

- [ ] **Step 7: Build all schemes**

Run:
```bash
cd NotchBuddy && xcodegen
xcodebuild -project NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug build 2>&1 | grep -E "error:|BUILD"
xcodebuild -project NotchBuddy.xcodeproj -scheme NotchMeowAppStore -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD"
cd ..
grep -c NSLocalNetworkUsageDescription NotchBuddy/Resources/Info.plist NotchBuddy/Resources/InfoAppStore.plist
```
Expected: `** BUILD SUCCEEDED **` twice; each plist count is `1`.

- [ ] **Step 8: Manual check**

Quit NotchMeow, then start an LM Studio persona and the Debug build:
```bash
python3 tests/fake_local_llm.py /tmp/nm-port --persona lmstudio &
NotchBuddy/build/Build/Products/Debug/NotchMeow.app/Contents/MacOS/NotchMeow
```
(Build it first with `-derivedDataPath build`, as in Task 11.)

Expected:
- **Section:** the sidebar says **AI**, with three boxes in the order above.
- **Default rows:** Ollama, LM Studio, llama.cpp and Jan each show their real state on this Mac.
- **Add server…:** add `http://127.0.0.1:<port from /tmp/nm-port>`. A "127.0.0.1" row appears, `● Running · 1 model`, with Remove. In "Which model answers", Local now lists `127.0.0.1 · llama3.2`.
- **Choosing it:** pick it for Chat. The resolution line disappears, and a chat question streams the fake answer, captioned `local · llama3.2`.
- **Network address:** add `http://<your Mac's .local name>:<port>`. The row shows "network · unencrypted on your network", and macOS may ask for Local Network access.
- **Key check:** with a real key, Save shows ✓ and "✓ Key saved and working."; a wrong key shows ✗.
- **Apple:** on macOS 26+ with Apple Intelligence on, the Apple on-device line says "Ready".

Stop the fake server: `kill %1`.

- [ ] **Step 9: Commit**

```bash
git add NotchBuddy/Sources/App/AISettingsViews.swift \
    NotchBuddy/Sources/App/SettingsView.swift \
    NotchBuddy/Sources/App/AppState.swift \
    NotchBuddy/project.yml \
    NotchBuddy/Resources/Info.plist \
    NotchBuddy/Resources/InfoAppStore.plist \
    NotchBuddy/NotchBuddy.xcodeproj/project.pbxproj
git commit -m "feat(settings): AI section with model choices, key checks and local servers

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---
### Task 14: LocalChat absorbed, docs and final verification

**Files:**
- Modify: `NotchBuddy/Sources/App/LocalChat.swift` (thin facade over the core)
- Modify: `scripts/test-chat-parsing.sh`
- Modify: `docs/INTEGRATIONS.md` (French), `docs/SPEC.md` (French), `README.md`, `CHANGELOG.md`

**Interfaces:**
- Consumes: `AIURL.normalise`, `OpenAIChatStreamParser`, `ThinkFilter`, `ReplyAccumulator`, `OpenAICompatibleProvider` (Tasks 3, 5).
- Produces: `LocalChat` keeps its public API (`normaliseURL`, `parseSSEDelta`, `filterThinkingBlocks`, `progressiveFilter`, `fetchModelsResult`, `fetchModels`, `streamChat`, `LocalChatError`). Only `tests/ChatParsingTests.swift` uses it, and that file stays unchanged.

- [ ] **Step 1: Make `LocalChat` a facade over the core**

Replace `NotchBuddy/Sources/App/LocalChat.swift` with:

```swift
import Foundation

// MARK: - Typed error for local model calls

enum LocalChatError: Error {
    /// The server is not reachable (wrong URL, not running, network error).
    case serverUnreachable(String)
    /// The model was requested but is not installed on the server.
    case modelNotFound(String)
    /// The server replied with an error message.
    case serverError(String)

    var localizedDescription: String {
        switch self {
        case .serverUnreachable(let url): return "Cannot reach \(url). Is the server running?"
        case .modelNotFound(let model):   return "Model '\(model)' is not installed."
        case .serverError(let msg):       return msg
        }
    }
}

// MARK: - Local model helpers

/// The pre-E1 local-model API, now a thin layer over the AI core (`AI/Core/`): the chat goes
/// through `ModelRouter` and `OpenAICompatibleProvider`. Kept so `tests/ChatParsingTests.swift`
/// still runs unchanged.
enum LocalChat {

    /// Removes trailing slashes and common documentation sub-paths (/api, /v1).
    static func normaliseURL(_ raw: String) -> String { AIURL.normalise(raw) }

    /// Parses `delta.content` from one OpenAI-SSE event line.
    /// Returns nil for non-data lines, `[DONE]`, missing or null content.
    static func parseSSEDelta(_ line: String) -> String? {
        var parser = OpenAIChatStreamParser()
        for case .text(let t) in parser.consume(line: line) { return t }
        return nil
    }

    /// Removes completed `<think>…</think>` blocks (reasoning models like DeepSeek-R1).
    static func filterThinkingBlocks(_ text: String) -> String {
        ThinkFilter.strip(text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// For streaming: removes closed think blocks AND hides content inside an
    /// open (unclosed) `<think>` block that hasn't received its closing tag yet.
    static func progressiveFilter(_ text: String) -> String { ThinkFilter.visible(text) }

    /// Fetches models, returning `.success([])` when the server responds but has no chat models,
    /// vs `.failure(.serverUnreachable)` when the server is not reachable.
    static func fetchModelsResult(baseURL: String) async -> Result<[(id: String, label: String)], LocalChatError> {
        do {
            let models = try await OpenAICompatibleProvider.make(.ollama, baseURL: baseURL).listModels()
            return .success(models.map { (id: $0.id, label: $0.id) })
        } catch {
            return .failure(.serverUnreachable(baseURL))
        }
    }

    static func fetchModels(baseURL: String) async -> [(id: String, label: String)] {
        if case .success(let models) = await fetchModelsResult(baseURL: baseURL) { return models }
        return []
    }

    /// Streams a reply from a local OpenAI-compatible server. `onToken` gets the visible text
    /// (think blocks hidden) on the main actor; the result has think blocks removed.
    static func streamChat(
        baseURL: String,
        model: String,
        messages: [[String: Any]],
        onToken: @MainActor @escaping (String) -> Void
    ) async throws -> String {
        let turns: [ChatRequest.Message] = messages.compactMap { m in
            guard let role = (m["role"] as? String).flatMap(ChatRequest.Role.init(rawValue:)),
                  let content = m["content"] as? String else { return nil }
            return ChatRequest.Message(role: role, parts: [.text(content)])
        }
        let request = ChatRequest(model: model, system: "", messages: turns)
        var acc = ReplyAccumulator(stripsThinkBlocks: true)
        var lastUpdate = Date.distantPast
        do {
            for try await chunk in OpenAICompatibleProvider.make(.ollama, baseURL: baseURL).stream(request) {
                acc.add(chunk)
                if case .text = chunk, Date().timeIntervalSince(lastUpdate) >= 1.0 / 15.0 {
                    lastUpdate = Date()
                    let visible = acc.visibleText
                    await MainActor.run { onToken(visible) }
                }
            }
        } catch let e as AIError {
            switch e.kind {
            case .badRequest where e.status == 404: throw LocalChatError.modelNotFound(model)
            case .unreachable, .offline, .timeout, .interrupted: throw LocalChatError.serverUnreachable(baseURL)
            default: throw LocalChatError.serverError(e.message ?? "HTTP \(e.status ?? 0)")
            }
        }
        let visible = acc.visibleText
        await MainActor.run { onToken(visible) }
        return filterThinkingBlocks(acc.text)
    }
}
```

In `scripts/test-chat-parsing.sh`, replace:

```bash
swiftc \
    NotchBuddy/Sources/App/LocalChat.swift \
    NotchBuddy/Sources/App/ChatMarkdown.swift \
    tests/ChatParsingTests.swift \
```

with:

```bash
swiftc \
    NotchBuddy/Sources/App/LocalChat.swift \
    NotchBuddy/Sources/App/AI/Core/*.swift \
    NotchBuddy/Sources/App/AppLog.swift \
    NotchBuddy/Sources/App/ChatMarkdown.swift \
    tests/ChatParsingTests.swift \
```

Run: `bash scripts/test-chat-parsing.sh`
Expected: the unchanged `ChatParsingTests` print the same `✓` lines as before, then `All tests passed.`

- [ ] **Step 2: `docs/INTEGRATIONS.md` (keep it in French)**

a) In §3, replace:

```markdown
  - **Poser une question dessus** → vue `prompt` avec une pastille du fichier. Envoi à l'API Claude (§5) : PDF en bloc `document`, images en bloc `image`, texte et code (≤ 200 Ko) en texte. Autres types : message « Je ne sais pas lire ce format, mais je peux l'envoyer par mail. »
```

with:

```markdown
  - **Poser une question dessus** → vue `prompt` avec une pastille du fichier. Le fichier part avec le message suivant, quel que soit le tour, vers le modèle choisi pour « File questions » (§5quater), et les messages suivants de la même conversation restent sur ce modèle. La carte dit qui le lira : « Claude will read this », « Local · qwen3.5:2b will read this ».
  - Fichiers refusés (archives, apps, images disque, vidéos, plus de 25 Mo) : la carte le dit (« I can't read this kind of file, but I can email it. ») et le chat ne les reçoit pas ; l'envoi par mail reste possible.
```

b) In §5, replace:

```markdown
- Modèle par défaut : `claude-sonnet-4-6`, choisi
```

with:

```markdown
- Le chat passe par la même API, en streaming (`stream: true`), avec la recherche web et les PDF en bloc `document` : voir §5quater.
- Modèle par défaut : `claude-sonnet-5-5`, choisi
```

and replace:

```markdown
- Outil de recherche web côté serveur de l'API : l'identifiant de type à jour est dans la doc (au moment d'écrire, `web_search_20250305`) ; `max_uses` 5.
```

with:

```markdown
- Outil de recherche web côté serveur de l'API : `web_search_20260209` (valeur partagée avec Windows dans `tests/fixtures/ai/providers.json`, clé `webSearch`), sans en-tête bêta ; les modèles dont l'identifiant commence par `claude-haiku-4` ou `claude-3` reçoivent `web_search_20250305` (`legacyType`) ; `max_uses` 5 pour le chat, 3 pour la recherche.
```

c) Replace everything from `## 5bis. Autres fournisseurs du chat (Google AI, OpenAI)` up to (not including) `## 6. Mail (app Mail du Mac)` with the text below. It replaces the old promise that file contents only go to Anthropic with what each provider receives. The Windows/Linux plan leaves this file to this one ("updated once for both apps"), so the text covers both platforms, as the spec describes them.

```markdown
## 5bis. Autres fournisseurs cloud (OpenAI, Google AI)

Clés dans Réglages → AI (`google-api-key`, `openai-api-key` : Trousseau sur macOS, Gestionnaire d'identification sur Windows, Secret Service sous Linux ; sur Windows et Linux, les clés restent côté Rust). Une clé collée est vérifiée tout de suite par un appel à la liste des modèles (✓ ou ✗). Les modèles se choisissent dans le chat ou dans Réglages → AI.

- **OpenAI** : API **Responses**, `POST https://api.openai.com/v1/responses`, en streaming. Chaque requête envoie `store: false` et toute la conversation (jamais `previous_response_id`). Recherche web hébergée (`web_search`), sources affichées en liens cliquables sous la réponse. PDF en `input_file`, images en `input_image` (URL `data:`). Le flux se termine sur `response.completed`, `.incomplete` ou `.failed` : il n'y a pas de ligne `[DONE]`. Liste des modèles : `GET /v1/models`, triée par date, filtrée par préfixe (`gpt-`, `o1`, `o3`, `o4`, `o5`) et sans `embed`, `tts`, `whisper`, `dall-e`, `audio`, `realtime`, `moderat`, `codex`, `computer-use`, `transcribe`, `image`, `sora`, `babbage`, `davinci`, `instruct`, `search`, `live`. Modèle par défaut : `gpt-6.1-sol`.
- **Google AI (Gemini)** : point d'accès compatible OpenAI, `POST https://generativelanguage.googleapis.com/v1beta/openai/chat/completions`, en streaming. Liste : `GET …/openai/models`, préfixe `models/` retiré, sans `embed`, `imagen`, `veo`, `aqa`, `tts`, `audio`, `live` ; par défaut, le premier modèle contenant « flash ».

Les identifiants, ports et filtres sont aussi dans `docs/AI-PROVIDERS.md` et `tests/fixtures/ai/providers.json`.

---

## 5ter. Modèles locaux

**IDs de pastilles** (macOS) : `ai_ollama` (jaune `#FACC15`), `ai_lmstudio` (vert citron `#A3E635`). llama.cpp, Jan, Apple et les serveurs ajoutés n'ont pas de pastille.
**Catégorie** : AI for the chat
**Plateforme** : macOS, Windows et Linux (Apple on-device : macOS 26+ seulement ; détails Windows et Linux dans `windows/README.md`)

### Détection

Seul ce Mac (127.0.0.1) est vérifié automatiquement, toutes les vérifications en parallèle, 0,3 s chacune : au lancement, à l'ouverture du sélecteur de modèle ou de Réglages → AI, et quand Auto a besoin d'un modèle local. Jamais en tâche de fond.

| Serveur | Port | Vérification |
|---|---|---|
| Ollama | 11434 | `GET /api/version`, puis `/v1/models` |
| LM Studio | 1234 | `GET /v1/models` |
| llama.cpp | 8080 | `GET /health` et `/v1/models` |
| Jan | 1337 | `GET /v1/models` |

Un autre serveur qui répond au format OpenAI sur ces ports devient « Local server (OpenAI-compatible) ». Ollama qui répond sans `/v1` est signalé « Update Ollama to use it here. ». Les modèles d'embedding sont retirés de la liste.

### Serveurs ajoutés

Réglages → AI → Local models → **Add server…** : une URL et une clé facultative (`custom-server-key.<id>` dans le Trousseau sur macOS, avec `<id>` de la forme `custom-` suivi de 24 chiffres hexadécimaux ; Gestionnaire d'identification ou Secret Service ailleurs). Une adresse hors de ce Mac est étiquetée « network », et « unencrypted on your network » si elle est en `http`. Les adresses réseau ne viennent que de l'utilisateur : NotchMeow ne parcourt jamais le réseau local, donc l'autorisation Réseau local de macOS 15 n'apparaît que si vous ajoutez un tel serveur. Sur Windows et Linux, tous les appels aux modèles partent de Rust, sans en-tête `Origin` (Ollama refuse celui de la webview Windows).

### Apple on-device

macOS 26 et plus, Apple Intelligence activée. Une ligne d'état dans Réglages → AI : « Ready », « Downloading », « Turn on Apple Intelligence in System Settings », ou rien si le Mac n'est pas compatible. La taille du contexte est lue sur le Mac (`contextSize`). Seul le modèle sur l'appareil est utilisé, jamais Private Cloud Compute.

### Streaming et pré-chargement

Les réponses arrivent mot à mot (`stream: true`, `max_tokens`, jamais `tool_choice`). Les blocs `<think>…</think>` sont masqués. Ouvrir le chat pré-charge le modèle local choisi (Ollama : requête vide sur `/api/generate` ; Apple : `prewarm()`). Si rien n'arrive après 1,5 s : « Waking up qwen3.5… ».

---

## 5quater. Quel modèle répond, et ce qu'il reçoit

Réglages → **AI** (anciennement Chat) : une ligne par usage, « Chat » et « File questions », chacune sur **Auto** ou un modèle précis.

- **Auto** prend le cloud préféré (Claude par défaut, ou OpenAI : réglage « Preferred cloud », visible quand les deux clés existent), puis l'autre des deux, puis Google, le premier qui a une clé. Sans clé : le dernier modèle local utilisé, sinon le premier prêt, sinon Apple on-device.
- **Repli local** : en Auto, une seule nouvelle tentative locale par message si le cloud a un souci passager (hors ligne, serveur injoignable, délai dépassé : connexion 10 s, premier mot 30 s ; erreur 5xx, 429, surcharge). Jamais pour une clé refusée, une requête invalide, un crédit épuisé, un refus du modèle ou un Stop. Sur macOS, quand `NWPathMonitor` signale le Mac hors ligne, Auto va directement au local.
- Chaque réponse porte une légende : `cloud · Claude Sonnet 5.5`, `local · qwen3.5:2b`, `network · llama3 @ studio-pc`.
- **Fichiers** : dès qu'un message de la conversation porte un fichier, tous les messages suivants (Continue et Retry compris) vont au modèle choisi pour « File questions », pas à celui de « Chat » : le texte du fichier reste dans l'historique et ne doit pas partir vers le cloud si vous avez choisi un modèle local. Déposer un fichier ou attacher une fenêtre démarre une nouvelle conversation.

**Ce que reçoit le fournisseur** : le message, toute la conversation en cours, et ce qui a été attaché :

| Fichier | Anthropic | OpenAI | Google, serveurs locaux et réseau | Apple on-device (macOS) |
|---|---|---|---|---|
| Texte, code, docx, rtf, html | texte | texte | texte | texte |
| PDF avec texte | PDF tel quel (`document`) | PDF tel quel (`input_file`) | texte extrait | texte extrait |
| Image, PDF scanné | image ou PDF tel quel | image ou PDF tel quel | image (premières pages pour un PDF) si le modèle lit les images ; sinon texte reconnu sur l'appareil (Vision sur macOS, OCR de Windows ; sous Linux : « This model can't see images. Pick one that can. ») | texte reconnu (Vision) |
| Fenêtre attachée (macOS) | nom de l'app, titre, URL | idem | idem | idem |

Extraction : PDFKit, import `NSAttributedString` (docx, rtf) et Vision sur macOS ; une crate PDF, `zip` + XML (docx) et l'OCR de Windows sur Windows et Linux. Le HTML est réduit à son texte sur les deux plateformes.

Le texte est taillé au modèle : la moitié de son contexte (environ 3,5 caractères par token, 4 096 tokens si inconnu en local), 204 800 caractères au plus vers le cloud. Quand un fichier est coupé, le modèle et vous le savez : « I read the first 600 lines. ». Quand la conversation devient trop longue pour un petit modèle, les plus anciens messages sont retirés deux par deux, une question et sa réponse (« This chat got long, so I dropped the oldest messages. »), jamais le prompt système ni le dernier message, et jamais pour le cloud. Le quart du contexte est gardé pour la réponse, la taille se compte en caractères Unicode (3,5 par token) et la règle est la même sur Windows : `tests/fixtures/ai/history-cases.json`.

**Confidentialité** :
- NotchMeow ne contacte que les fournisseurs configurés, ce Mac et les serveurs que vous avez saisis. Pas de télémétrie.
- OpenAI : `store: false` sur chaque requête, sans quoi l'API Responses garde les conversations au moins 30 jours. OpenAI conserve encore des journaux anti-abus jusqu'à 30 jours et n'entraîne pas ses modèles sur les données de l'API par défaut.
- Les clés restent dans le trousseau du système (côté Rust sur Windows et Linux). Les journaux (`nm.log` ; sur macOS `~/Library/Logs/NotchMeow/nm.log`) notent des types d'événements, des erreurs et l'identifiant de requête du fournisseur (`x-request-id`, utile au support) ; jamais un prompt, le contenu d'un fichier ou une clé.
- Un échec de modèle ne bloque jamais un agent : hooks, validations et états des chats passent par d'autres chemins.

### Erreurs

| Situation | Message | Action |
|---|---|---|
| Repli local | « Claude's busy right now, so Qwen answered instead. » | — |
| 429 sans modèle local | « Claude is busy. Trying again in 20 s. » (respecte `Retry-After`) | Cancel |
| Clé refusée | « Your Anthropic key was rejected. » | Open Settings |
| Crédit ou plafond | « Your OpenAI credit ran out. » / « Your OpenAI spend limit was reached. » | Open billing page |
| Serveur local injoignable | « Couldn't reach LM Studio. Is its server on? » | Open guide |
| Flux coupé | réponse partielle gardée, marquée « interrupted » | Continue · Retry |
| Modèle qui ne lit pas les images (Linux, sans OCR) | « This model can't see images. Pick one that can. » | Choose model |
| Refus du modèle | le refus du fournisseur, tel quel | — |

---
```

d) In §7, add the Local Network row:

```markdown
| Micro + Reconnaissance vocale (optionnel) | dictée | premier clic sur le micro |
```

becomes

```markdown
| Micro + Reconnaissance vocale (optionnel) | dictée | premier clic sur le micro |
| Réseau local | joindre un serveur de modèles ajouté sur le réseau | premier serveur réseau ajouté (jamais pour ce Mac seul) |
```

- [ ] **Step 3: `docs/SPEC.md` (French)**

Replace:

```markdown
- Pastilles IA (cloud) : `isConfigured` = clé API dans le Keychain. Pastilles IA locales (Ollama, LM Studio) : `isConfigured` = URL serveur non vide (définie via le bouton **Connect** dans Réglages → Chat). Bouton « Chat with… » → change le fournisseur et ouvre la vue `.prompt`.
```

with:

```markdown
- Pastilles IA (cloud) : `isConfigured` = clé API dans le Keychain. Pastilles IA locales (Ollama, LM Studio) : `isConfigured` = serveur trouvé sur ce Mac avec au moins un modèle (détection automatique, Réglages → AI). Bouton « Chat with… » → le Chat utilise ce fournisseur avec son dernier modèle, et la vue `.prompt` s'ouvre. llama.cpp, Jan, Apple on-device et les serveurs ajoutés n'ont pas de pastille.
```

and replace:

```markdown
- **Anthropic API** : clé (Trousseau), modèle (défaut `claude-sonnet-4-6` ; liste depuis l'API, voir INTEGRATIONS §5).
- **Chat — other providers** : clé Google AI (Trousseau) ; clé OpenAI (Trousseau). Les modèles se choisissent dans le chat (voir INTEGRATIONS §5bis).
- **Local models** : URL du serveur Ollama (défaut `http://127.0.0.1:11434`) et/ou LM Studio (défaut `http://127.0.0.1:1234`). Bouton **Connect** : vérifie la joignabilité et sauvegarde l'URL. Bouton **Disconnect** : efface l'URL et le cache. Aucune clé requise (voir INTEGRATIONS §5ter).
```

with:

```markdown
- **AI** (anciennement Chat), trois blocs :
  - **Which model answers** : Chat et File questions, chacun sur Auto ou un modèle (Cloud, Local par serveur, Apple on-device), avec sous Auto la ligne de résolution ; **Preferred cloud** (Claude ou OpenAI) quand les deux clés existent (voir INTEGRATIONS §5quater).
  - **Anthropic API** : clé (Trousseau), modèle (défaut `claude-sonnet-5-5` ; liste depuis l'API, voir INTEGRATIONS §5) ; **Other cloud providers** : clés Google AI et OpenAI (Trousseau). Chaque clé enregistrée est vérifiée par un appel à la liste des modèles (✓ / ✗).
  - **Local models** : une ligne par serveur trouvé sur ce Mac (Ollama, LM Studio, llama.cpp, Jan) avec son état, les serveurs ajoutés (**Add server…**, URL + clé facultative), la ligne Apple on-device, **Rescan** (voir INTEGRATIONS §5ter).
```

- [ ] **Step 4: `README.md` and `CHANGELOG.md`**

In `README.md`, replace:

```markdown
| **Google AI API key** *(macOS)* | chat with Google AI (Gemini) | Settings → Chat — other providers · Keychain |
| **OpenAI API key** *(macOS)* | chat with OpenAI | Settings → Chat — other providers · Keychain |
| **Ollama server** *(macOS)* | chat with local models via Ollama | Settings → Chat → Local models → **Connect** |
| **LM Studio server** *(macOS)* | chat with local models via LM Studio | Settings → Chat → Local models → **Connect** |
```

with:

```markdown
| **Google AI API key** *(macOS)* | chat with Google AI (Gemini) | Settings → AI → Other cloud providers · Keychain |
| **OpenAI API key** *(macOS)* | chat with OpenAI | Settings → AI → Other cloud providers · Keychain |
| **Local model servers** *(macOS)* | chat with Ollama, LM Studio, llama.cpp or Jan | found automatically on this Mac; a server on your network: Settings → AI → Local models → **Add server…** |
| **Apple Intelligence** *(macOS 26+)* | chat with Apple's on-device model | turn on Apple Intelligence in System Settings |
```

(The feature line near the top lists platforms, and the Windows/Linux plan also edits it, so it is left for whichever plan lands last.)

In `CHANGELOG.md`, under `## Unreleased (NotchMeow)`, replace:

```markdown
- Removed Coucou's reserved assets (sounds, media, captures and prototypes); NotchMeow's own cats, icons and sounds are in progress
```

with:

```markdown
- Removed Coucou's reserved assets (sounds, media, captures and prototypes); NotchMeow's own cats, icons and sounds are in progress
- Local models everywhere (macOS): Ollama, LM Studio, llama.cpp and Jan are found on their own, Apple's on-device model answers on macOS 26+, and you can add a model server on your network. Settings → Chat is now Settings → AI: choose Auto or a model for Chat and for File questions, and which cloud Auto tries first
- Claude, OpenAI (now through the Responses API, never stored) and Gemini stream their answers; Claude and OpenAI show their web sources as links. Each answer says where it came from (local, network or cloud), and when the cloud is busy or unreachable Auto answers once with a local model
- Dropped files reach every model: text, PDFs, scans and images (read on the Mac for models that can't see images), Word, RTF and HTML, cut to fit small models; the drop card says who will read the file, and follow-up questions stay with the model chosen for File questions
```

- [ ] **Step 5: Run everything CI runs**

Quit NotchMeow first (it writes the log too). Run:
```bash
LOG=~/Library/Logs/NotchMeow/nm.log; before=$(stat -f %z "$LOG" 2>/dev/null || echo 0)
bash scripts/check-test-logs.sh
bash scripts/check-sdk.sh
bash scripts/test-ai-contract.sh
for t in router stream budget attachments providers runner discovery platform settings; do bash scripts/test-ai-$t.sh | tail -1; done
for t in screen-geometry safe-links chat-parsing plan-gauge ask-question diff-engine github-pulse github-activity; do bash scripts/test-$t.sh | tail -1; done
cd NotchBuddy && xcodegen
xcodebuild -project NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Release -derivedDataPath build build CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO 2>&1 | grep -E "error:|BUILD"
xcodebuild -project NotchBuddy.xcodeproj -scheme NotchMeowAppStore -configuration Debug build CODE_SIGNING_ALLOWED=NO 2>&1 | grep -E "error:|BUILD"
cd .. && bash scripts/check-app-binary.sh NotchBuddy/build/Build/Products/Release/NotchMeow.app release
after=$(stat -f %z "$LOG" 2>/dev/null || echo 0); [ "$before" = "$after" ] && echo "✓ the real nm.log did not change" || echo "✗ a test wrote to $LOG"
```
Expected:
- `✓ every log-writing test script sets NM_LOG_DIR` and `✓ macOS SDK … has FoundationModels`;
- the contract: `All AI contract checks passed` and `Ran 13 tests … OK`;
- the nine AI suites and the eight existing suites each end in `All tests passed.` (screen geometry and safe links print their own `… cases passed` line);
- `** BUILD SUCCEEDED **` twice;
- `✓ FoundationModels is weak-linked` and `✓ No AI base-URL override in this Release build`;
- `✓ the real nm.log did not change`: no suite, including `chat-parsing`, which now goes through `AILog`, wrote to `~/Library/Logs`.

- [ ] **Step 6: Check for new warnings**

Run a clean Debug build and count warnings in the files this plan touched:
```bash
cd NotchBuddy && xcodebuild -project NotchBuddy.xcodeproj -scheme NotchBuddy -configuration Debug clean build 2>&1 | grep "warning:" | grep -E "/AI/|AISettingsViews|LocalChat|ClaudeService|AppState|IslandTypes|SettingsView|FileDropView|UploadCanvasView|AppDelegate|IslandViewContent" | grep -vE "activateIgnoringOtherApps|dashPhase|breathAngle|fetchN8nWorkflows"; cd ..
```
Expected: no output. CONTRIBUTING asks for no new warnings. The excluded patterns are the existing warnings in `IslandViewContent` and `SettingsView`.

- [ ] **Step 7: Manual matrix before release (spec §6)**

- **Ollama, no keys:** chat works with zero setup, captioned `local · <model>`.
- **Apple Intelligence on, macOS 26+, no keys and no servers:** chat works, captioned `local · Apple on-device`.
- **Offline mid-session** (turn Wi-Fi off) with a local server running: the next message is answered locally within about 1 s, with no cloud wait.
- **LM Studio, llama.cpp (`llama-server -m … --jinja`) and Jan:** each found by Rescan and usable.
- **A file, then a follow-up** with File questions on a local model and Chat on Claude: drop a file and ask two questions. Both answers are captioned `local · <model>`, and `nettop -p NotchMeow` shows no connection to the cloud. Attaching a window starts a new conversation, so the next question, with no file in it, is captioned `cloud · …`.
- **The empty state** with nothing set up.
- **Network trace:** run `nettop -p NotchMeow` while chatting with each provider. Traffic goes only to the configured hosts and 127.0.0.1.
- **VoiceOver:** check the Settings → AI boxes, the reply caption and sources, Stop, and the note buttons.
- **macOS 15 Mac (or VM):** the app launches, and the Apple on-device line is hidden.

- [ ] **Step 8: Refresh the code graph**

`ARCHITECT.md` asks for an incremental graphify update after big changes. Run `/graphify --update` from the repo root. Only code changed, so it is AST-only, with no LLM. `graphify-out/` is excluded from git, so nothing to commit.

- [ ] **Step 9: Commit**

```bash
git add NotchBuddy/Sources/App/LocalChat.swift \
    scripts/test-chat-parsing.sh \
    docs/INTEGRATIONS.md \
    docs/SPEC.md \
    README.md \
    CHANGELOG.md
git commit -m "docs(ai): say what each provider receives; LocalChat becomes a facade over the AI core

Co-Authored-By: Claude Sonnet 5.5 <noreply@anthropic.com>"
```

---
## Self-review

**1. Spec coverage**

| Spec | Where |
|---|---|
| §1 `ModelProvider`, `ChatRequest` (tools + `responseFormat` kept for F), `ChatChunk` | Task 1 |
| §1 Router per feature, Auto order, Preferred cloud, one local retry, label | Tasks 2, 8, 11 (`files` when the message being sent or any earlier message in the conversation carries a file), 13 (Preferred cloud row) |
| §1 Providers: Anthropic streaming + web search + native PDF; OpenAI Responses (`store:false`, `web_search`, `input_file`/`input_image`, no `[DONE]`); OpenAI-compatible (`max_tokens`, no `tool_choice`, `<think>` hidden); Apple | Tasks 6, 7, 5, 10 |
| §1 `ClaudeService` keeps conversation and UI state; `ChatProvider` gains four cases; pill IDs frozen; no dependencies; FoundationModels weak-linked and verified | Tasks 11, 10 |
| §2 Probes (ports, paths, 0.3 s, parallel, identification, unknown server) | Task 9 |
| §2 When checks run | First island open after launch (Task 11; nothing while hidden), picker (Task 11), Settings (Task 13), when Auto needs local (Tasks 8, 11), nothing known yet (Task 11). Never on a timer |
| §2 Added servers, network label, unencrypted, Keychain key, Local Network prompt only for them | Task 13 |
| §2 Model lists without embeddings; capabilities from Ollama `/api/show` and LM Studio `/api/v0/models`, else text only; last model per server | Tasks 1, 5, 11 |
| §2 Apple status line, `contextSize` at runtime, `rateLimited` retry once | Task 10 |
| §3 File table, extraction, budget, notice to the model and the user | Tasks 4, 8, 11, 12 |
| §3 Rejects, file joins its message, drop card names the model, INTEGRATIONS update | Tasks 4, 11, 8 (regression test), 12, 14 |
| §4 AI section, three boxes, key check, model chip and popover, reply caption, sources, empty state | Tasks 13, 11, 12 |
| §5 Retry rules, never-retry rules, offline shortcut, copy table, pre-warming, Stop, cat error state | Tasks 2, 8, 9, 11, 12 |
| §5 Context overflow: drops the oldest turns, never the system prompt or the latest message | Task 4 (`ContextBudget.trimHistory`, every case of E1-0's `history-cases.json`), Task 8 (`Conversation.request`, notice under the reply) |
| §5 Privacy: labels, connections, keys, logs, Apple on-device only, `store:false`, request ID, no effect on agents | Tasks 12, 9, 13, 5, 10, 7. Nothing touches `HookServer` |
| §6 Shared cases, fake personas, Debug redirect, Swift scripts in CI, `ChatParsingTests`, regression and leak tests | Tasks 1–5, 8, 9, 10, 14 |
| §6 Discovery < 400 ms, store:false asserted from the fake server's log, manual matrix | Tasks 9, 7, 14 |

Deliberately not built here:
- **Hairball animation.** The cats are still being drawn in their own sub-project. Rejects post `.botReject` and use the existing annoyed emote and sound.
- **Launch check.** Spec §2's launch check is deferred to the island's first open, per the review lesson "no model lists while hidden".
- **Linux "can't see images" row.** It doesn't apply on the Mac, which has Vision OCR.
- **LM Studio vs mistral.rs.** The contract's personas give no LM Studio-only signal, so whatever answers `/v1/models` on port 1234 is named LM Studio.

**2. Placeholder scan.** No "TBD", no "similar to Task N", and no step without its code. Every code block was extracted and applied, task by task, to a scratch clone of the repository that carried the E1-0 contract with Task 3b as finished by the E1-0 final-fix wave (`Ran 13 tests`, 123 contract checks, 21 HTTP error cases, 13 budget cases, 12 history cases, 21 SSE fixtures, `maxOutputTokens` in `providers.json`). There:
- every AI script that exists after a task (`test-ai-*`, `check-test-logs`, `check-sdk`, and `test-chat-parsing` after Tasks 1 and 14) passed after it (116 script runs over the 14 tasks), and a Debug build succeeded after each task;
- the new rules were broken on purpose and each break failed a test: the catalog's cloud cap, the fixture's alone, both together (only the pin notices), a provider that hard-codes a cap, a `feature` that ignores the history, the old per-message rule, and a float history budget (the odd-context case);
- the final-fix rules were broken the same way, one edit each, and each break failed a test: an unknown, missing or Anthropic/Responses stream code going back to `server`, the shared billing set, 402, `billing_error`, the `*_spend_limit_exceeded` suffix, a force-cast `error` field (the run aborts), `Retry-After` without the ASCII check and with `0`, the CR dropped before LF, a lone CR ending a line, the transport put back on `bytes.lines`, a Responses or Anthropic stream with no `interrupted`, `content_filter` not a refusal, a rounded budget, a lone CR ending a budget line, the two history mutations, and the three server-ID and Keychain-item rules;
- after Task 14 the Release and App Store builds succeeded, a clean Debug build had no new warnings, and `check-app-binary.sh` passed on the Debug and Release builds;
- `check-sdk.sh` and `check-app-binary.sh … release` fail as intended on an SDK or binary without FoundationModels;
- the real `~/Library/Logs/NotchMeow/nm.log` did not change across all of it.

**3. Type consistency.**
- `AICatalog.maxOutputTokens(for:)` (Task 1) is the only source of a request's `maxTokens`: the Task 8 test harness and `ClaudeService.reply` (Task 11) call it with the target's placement, and `ChatRequest.maxTokens` defaults to `AICatalog.OutputTokens.local`.
- `Conversation.feature` (Task 8) is what `ClaudeService.currentFeature`, `routeInput` and the fallback closure (Task 11) and the chip, picker and drop card (Task 12) read.
- `AIProviderID`, `ModelRef`, `FeatureSetting`, `AIFeature`, `LocalCandidate`, `RoutePlan` and `ChatTarget` keep the same fields from Task 2 to Task 13.
- `ChatTarget` is defined in Task 8 and used by Tasks 11–12.
- `AIAction` is defined in Task 8 and used by `NoteAction` (Task 11) and `NoteView` (Task 12).
- `AppState.fetchedProviderModels` is keyed by `AIProviderID` from Task 11 onward, and the old Settings compiles against it (`[.ollama] = nil`).
- `AttachmentRejection` is used by `AILog` (Task 5) and `AIMessages.rejected` (Task 8).

**4. Review Focus.** Eight lines, each pinned by a test in its owning task: Task 8 (cut before text, Stop after text, deleted-model copy, tokens spent thinking, a follow-up about a file), Task 5 (404 mapping; lines at LF only through the real transport), Task 4 (locked PDF; lines at LF only in the budget), and Tasks 2 and 3 (unknown or odd stream errors; the line splitter). Writing them found real bugs, all fixed in the code above:
- a cut before any text left an empty "interrupted" bubble;
- a stream that finished with no text (a paused search, a tool call nobody asked for, a thinking model out of room) left an empty bubble.

The Windows review's lessons are applied too:
- reply caps from the catalog (`maxOutputTokens`: 16,000 cloud, 4,096 local and network), with out-of-room and cut-off copy;
- routing that follows the file: a follow-up stays on File questions;
- Retry that never removes a user message;
- `webSearch` checked against `providers.json`, including `legacyType` and `legacyModelPrefixes`, with the tool chosen per model by `AICatalog.anthropicWebSearchType(model:)` in the chat and in `search()`;
- no model lists while hidden, and a rescan when Settings opens;
- redacted keys and stripped URL credentials;
- prepared files kept on their turn;
- HEIC to JPEG through ImageIO;
- tests that never write to the real `nm.log` (`NM_LOG_DIR`);
- history trimming from the shared `history-cases.json`.

Found in the independent review and fixed here:
- a follow-up to a file message took the Chat route with the file's text still in the history, so a cloud Chat model received what the person had kept on a local File questions model; `Conversation.feature` is now derived from the conversation's files, and Continue and Retry keep it;
- the cloud reply length was a literal in `ClaudeService`; it is now `providers.json` `maxOutputTokens`, pinned in the catalog test;
- a reply that spends its whole cap thinking fell back to a local model as if the cloud were busy; it now says why and never switches models;
- the shipped `NoteView` got a new right margin for every note; only notes with a button or a link have it now;
- a failed Retry left its question unanswered, so the next message made two user messages in a row, which some chat templates refuse; same-role neighbours are joined when the request is built;
- Retry could act on a stream still running, or on an older exchange from a stale button; it now waits for the reply to end, and only the newest partial reply keeps Continue · Retry;
- history was measured in `Character`s, not Unicode scalars;
- CI on a runner without the macOS 26 SDK would have compiled the Apple provider out without a word; it now fails loudly.

**Contract notes.**
- **Consumed revision.** This plan uses E1-0 as revised:
  - `webSearch` in `providers.json`, checked by the catalog test and sent by both cloud providers and `search()`;
  - `maxOutputTokens` in `providers.json` (`cloud` 16000, `network` 4096, `local` 4096), checked and pinned by the catalog test and read for every chat request's `maxTokens`;
  - `has_client_tools`, and query strings ignored (`Ran 13 tests`), in the fake server;
  - `stream_error_kind`: one mapping for `response.failed`, `error` and Anthropic `error` events (unknown or odd → `bad_request`, never `server`);
  - 21 SSE fixtures (6 `openai-chat`, 10 `openai-responses`, 5 `anthropic`);
  - 21 HTTP error cases (402 and `billing_error` and `*_spend_limit_exceeded` are billing; string and list `error` bodies; `Retry-After` ASCII digits above 0 only), 13 budget cases (`floor(ctx × 7 / 4)`; lines end at `\n` only) and 12 history cases, including `odd context: the integer line, not a float one` (`ContextBudget.trimHistory` uses integer math, `ceil(2n ÷ 7)` against `ctx − floor(ctx ÷ 4)`) and the two-turn case (`dropped: 1`);
  - `custom-server-key` is a prefix: `custom-server-key.<serverId>`, `^[a-z0-9-]{1,32}$`.
- **History-trim rule.** Shared with Windows through E1-0 Task 3b (`history-cases.json`): `budget = ctx − floor(ctx ÷ 4)` tokens, tokens estimated as `ceil(scalars ÷ 3.5)`, the oldest turns dropped two at a time while over budget and more than one turn remains, the system prompt and the latest turn always kept, cloud untouched, and the notice "This chat got long, so I dropped the oldest messages.". `ContextBudget.trimHistory` runs every case, built into real messages.
