# E. Local models everywhere: design

- **Status:** design approved in conversation on 2026-10-03; this written spec awaits review.
- **Revision 1:** OpenAI made a first-class provider (Responses API), alongside Anthropic.
- **Parent spec:** [`2026-10-03-notchmeow-design.md`](2026-10-03-notchmeow-design.md), sub-project E.

## Context

The user wants NotchMeow to run local AI models and, later, to become a "super smart Clippy" with the cats as the mascot (sub-project F). E is the foundation. It gives every NotchMeow feature a model to talk to, local or cloud, on macOS, Windows and Linux.

**Where things stand today:**
- **macOS:**
  - **Providers:** five chat providers live in one enum (`ChatProvider`, `NotchBuddy/Sources/App/IslandTypes.swift:73-144`) and one class (`ClaudeService.swift`).
  - **Local servers:** Ollama and LM Studio are reached through `LocalChat.swift` (OpenAI-compatible, streaming). The user connects them by hand, and only these two stream.
  - **Dropped files:** a file dropped on the notch reaches Anthropic in full; local models get its text, and Google and OpenAI get its name only.
- **Windows/Linux (Tauri):**
  - Anthropic only, non-streaming (`windows/src-tauri/src/claude.rs`).
  - A fixed list of three models in Settings.

## Decisions

| Topic | Decision |
|---|---|
| How a model is obtained | **All three paths, staged.** E1 (this plan): detect the local servers already running, plus Apple's on-device model. E2 (later plan): an optional one-click runtime and model download, not part of the base installer. |
| Default brain | **Cloud first, local by choice, both selectable.** "Auto" uses the cloud when a key exists, and otherwise a local model. If the cloud fails for a temporary reason, Auto retries once locally. |
| Cloud providers | **Anthropic and OpenAI are both first-class, with native providers:**<br>• streaming;<br>• built-in web search with clickable sources;<br>• PDFs and images sent natively;<br>• structured output.<br><br>OpenAI uses its **Responses API**, the API OpenAI recommends for new work and the only one with hosted tools. "Preferred cloud" (Claude or OpenAI) decides which one Auto uses. Google uses its OpenAI-compatible endpoint. |
| Architecture | **Approach A:** one shared core. An OpenAI-compatible adapter covers the other backends, Anthropic and OpenAI stay native, Apple on-device gets its own adapter, and a router chooses per feature. Rejected: Foundry Local as the core (licence terms unclear, catalogue lock-in, no Swift SDK), and macOS 27's pluggable `LanguageModel` as the core (NotchMeow supports macOS 15). |
| Files | Any reasonable file reaches the model you're using: text, PDF, images, scanned PDFs and Word documents. Each file goes with the message it was dropped on. |
| Privacy label | Every answer is labelled **local** (this computer), **network** (a server the user added on their network) or **cloud**. |
| E2 runtime (later) | llama.cpp's `llama-server` as a signed sidecar (MIT licence), with **Qwen3.5-2B** (Apache-2.0) as the suggested default. It's about 1.5–2.7 GB, supports tool calls and reads images. |

**Out of scope for E:**
- the cats' assistant behaviour (F1–F3);
- file shelf and transfer (G);
- Apple's Private Cloud Compute model;
- wrapping backends in macOS 27's `LanguageModel` protocol (possible later, see Risks);
- Windows' Phi Silica / Aion Instruct (wait for Aion Instruct's retail release, January 2027).

## 1. Architecture

**The same shape on both platforms:**
- **`ModelProvider`**:
  - `id`, `displayName` and `placement` (`local` / `network` / `cloud`);
  - `listModels() → [ModelInfo]`, where each model reports its `id`, `contextTokens?` and its `capabilities`: `tools`, `vision`, `json`;
  - `stream(ChatRequest) → stream of ChatChunk`, where a chunk is a text delta, a tool-call delta, a finish reason or an error;
  - `prewarm(model)`, which does nothing for providers that don't need it.
- **`ChatRequest`**:
  - `system` and `messages`, where each message has a role and parts (text, image or file text);
  - optional `tools` and `responseFormat` (a JSON schema), plus `maxTokens`, which is 16,000 for cloud models and 4,096 for local and network ones (from `providers.json` `maxOutputTokens`, so both apps ask for the same length: OpenAI's reasoning models spend hidden reasoning tokens from the cap, and 4,096 locally is what the Mac's `LocalChat` already sends);
  - `tools` and `responseFormat` are unused in E but exist for F, so the interface doesn't change later.
- **`ModelRouter`**:
  - **features:** `chat` and `files` in E; F adds `cats`. A conversation that holds a file uses the Files setting for every follow-up, so file text never reaches a model the user didn't pick for files. Dropping a file or starting a new chat resets this;
  - **per-feature setting:** `auto`, or an explicit `(providerID, modelID)`;
  - **resolving Auto:** pick the cloud provider in this order:
    1. the **Preferred cloud** (Claude or OpenAI; Claude by default), if it has a key;
    2. the other one of the two;
    3. Google.

    Use that provider's remembered model, or its default from `docs/AI-PROVIDERS.md`. If there's no cloud key, use the last-used local model. If there's none of those either, use the first ready local model, then Apple on-device;
  - **fallback:** one local retry on a temporary failure (see §5). The result says which provider answered, which drives the label.

**Providers:**

| Provider | Covers | Notes |
|---|---|---|
| `AnthropicProvider` | Claude | Native Messages API with server-side web search (existing behaviour), now **streaming** (SSE) |
| `OpenAIProvider` | OpenAI | Native **Responses API** (`POST /v1/responses`, streaming):<br>• **Web search:** hosted `web_search` tool, with `url_citation` sources shown as clickable links (OpenAI requires that).<br>• **Files:** PDF and images as `input_file` / `input_image` data URLs.<br>• **Structured output:** `text.format` with a JSON schema; flat function tools for F.<br>• **Privacy:** always sends `store:false` and resends the conversation each turn (§5).<br>• **Streams:** close on a terminal event (`response.completed` / `.incomplete` / `.failed`). There is no `[DONE]` line. |
| `OpenAICompatibleProvider` | Google (OpenAI-compatible endpoint), Ollama, LM Studio, llama.cpp, Jan, any server the user adds, and later the E2 runtime | Base URL and optional key. Hides `<think>` blocks (existing). Sends `max_tokens`, not `max_completion_tokens`, and no `tool_choice`, because Ollama ignores both. |
| `AppleOnDeviceProvider` | Apple Foundation Models | macOS 26+ only (`if #available`); see §2 |

**macOS (`NotchBuddy/Sources/App/AI/`, new folder):**
- **New files:**
  - `ModelProvider.swift`: the protocol and the request/response types;
  - `ModelRouter.swift`;
  - `AnthropicProvider.swift`: moved out of `ClaudeService`, plus streaming;
  - `OpenAIProvider.swift`: the Responses API (replaces today's chat-completions path for OpenAI);
  - `OpenAICompatibleProvider.swift`: grows out of `LocalChat.swift`;
  - `AppleOnDeviceProvider.swift`;
  - `Discovery.swift`;
  - `Attachments.swift`.
- `ClaudeService` keeps the conversation and UI state and calls the router.
- `ChatProvider` gains `llamacpp`, `jan`, `apple` and `custom`. Existing raw values and pill IDs don't change.
- No third-party dependencies. FoundationModels, PDFKit, Vision and Network are system frameworks. FoundationModels must be weak-linked so the app still launches on macOS 15; verify this in the build.

**Windows/Linux (`windows/src-tauri/src/ai/`, new module):**
- **Files:**
  - `mod.rs`
  - `provider.rs`: the trait and types
  - `router.rs`
  - `anthropic.rs`: today's `claude.rs` moved here, plus streaming
  - `openai.rs`: the Responses API
  - `openai_compat.rs`
  - `discovery.rs`
  - `attachments.rs`
- **Tauri commands:** `ai_discover`, `ai_list_models`, `ai_chat` (streams over a `tauri::ipc::Channel`), `ai_cancel`.
- **All model HTTP goes through Rust (`reqwest`):**
  - It sends no `Origin` header. Ollama's default allowed origins don't include Windows' `http://tauri.localhost`.
  - Keys never reach the webview.
  - Don't use `tauri-plugin-http`, which adds the webview Origin.
- `secrets.rs`'s allowlist gains `google-api-key` and `openai-api-key`.

**Keeping both apps in sync:** `docs/AI-PROVIDERS.md` (new) is the single list of provider IDs, display names, default URLs and ports, default models and model-list filters. Both apps follow it, like `PillCatalog` for pills.

## 2. Discovery and connection

**Local servers.** Only the user's own computer (127.0.0.1) is checked automatically. All checks run in parallel with a 0.3 s timeout each.

| Server | Port | Check | Identified as |
|---|---|---|---|
| Ollama | 11434 | `GET /api/version` | Ollama |
| LM Studio | 1234 | `GET /v1/models` | LM Studio; mistral.rs also defaults to 1234, so an unexpected reply makes it "Local server" |
| llama.cpp | 8080 | `GET /health`, then `/v1/models` | llama.cpp; LocalAI also uses 8080 and becomes "Local server" |
| Jan | 1337 | `GET /v1/models` | Jan; its server is off until the user starts it |

- **Unknown servers:** anything else that answers in the OpenAI format becomes "Local server (OpenAI-compatible)".
- **When checks run:** at launch, when the model picker or the AI settings open, and when Auto needs a local fallback. Never on a timer. NotchMeow keeps 0% CPU while hidden.
- **Servers the user adds:** "Add server…" takes a URL plus an optional API key (Keychain / Credential Manager / Secret Service).
  - A non-localhost address is labelled **network**.
  - Plain `http` to a non-localhost address shows "unencrypted on your network".
  - Network addresses only ever come from the user. Auto-checking only localhost also means the macOS 15 Local Network permission prompt never appears unless the user adds a network server.
- **Models:** each server's `/v1/models` list, with embedding models filtered out (existing Mac behaviour).
  - Capabilities come from Ollama's native model info and LM Studio's model types when available. Otherwise NotchMeow assumes text only.
  - The last-used model on each server is remembered.

**Apple on-device (macOS 26+):**
- **Status:** `SystemLanguageModel.default.availability` drives one status line:
  - "Ready";
  - "Downloading";
  - "Turn on Apple Intelligence in System Settings";
  - hidden when the Mac isn't eligible.
- **Context size:** read `contextSize` at runtime. It's back-deployed to 26.0 and may be 4,096 or 8,192 tokens. Measure inputs with `tokenCount(for:)`.
- **Rate limits:** if `GenerationError.rateLimited` comes back, retry once after a short delay, then treat it as a temporary failure (§5). Apple's documents and the WWDC26 statements disagree about rate limits for accessory apps on macOS.

## 3. Files to the AI

One attachment pipeline per platform, used by Chat and file questions:

| File | Model can see images (`vision`) | Model can't see images |
|---|---|---|
| Text and code (detected as UTF-8) | Text | Text |
| PDF with a text layer | Anthropic: native PDF block. OpenAI: native `input_file`, so the model also sees page images. Others: extracted text | Extracted text |
| Image, or PDF without a text layer | The image; a PDF's first pages are rendered as images | Recognised text: macOS Vision and Windows' built-in OCR. On Linux: "This model can't see images." |
| .docx, .rtf, .html | Converted to text (OpenAI could read .docx natively, but local conversion keeps every provider consistent) | Converted to text |
| Archives, apps, disk images, video, or anything over 25 MB | Rejected | Rejected |

**Text extraction:**
- **macOS:** PDFKit for PDFs, `NSAttributedString` document import for docx/rtf/html, and the Vision framework for OCR. No dependencies.
- **Windows/Linux:**
  - a Rust PDF text crate (MIT/Apache);
  - `zip` + XML text for docx;
  - an HTML tag strip;
  - Windows OCR through the `windows` crate (`Windows.Media.Ocr`).

**Text budget.** Text is sized to the model, not a fixed 24,000 characters. The budget is about 50% of the model's context, measured in tokens: Apple's own count, or about 3.5 characters per token elsewhere. It's capped at 200 KB for cloud models. When a file is cut short, the model and the user are told: "I read the first 600 lines."

**Behaviour:**
- **Rejects:** a rejected file plays the cat's hairball reject (prototype `catchReject`). It's the same reject list as the prototype's `REJECT` set and 25 MB limit.
- **Which turn a file joins:** a file joins the message it was dropped on, not only the first message of a conversation. This fixes today's macOS bug, tracked separately; E keeps the fix and adds a regression test.
- **Who reads it:** the drop card says which model will read the file, for example "Claude will read this" or "Local · qwen3.5:2b will read this". Dropping is consent, file by file.
- **Docs:** `docs/INTEGRATIONS.md` (French) is updated. Today it promises file contents only go to Anthropic. It will now list what each provider receives.

## 4. Settings and the model picker

Shipping screens keep their style; new parts follow it.

**AI settings.** The Settings section **Chat** is renamed **AI** on both platforms, since F will use it too. It has three boxes:

1. **Which model answers** (new):
   - one row per feature: `Chat [Auto ▾]` and `File questions [Auto ▾]`. F adds `Cats`;
   - under each Auto, one line saying what it currently resolves to, for example "Claude Sonnet · falls back to Local · qwen3.5:2b";
   - menu groups: **Cloud** (only providers with a key), **Local** (grouped by server), **Apple on-device**;
   - a **Preferred cloud** row, `[Claude ▾ | OpenAI]`, tells Auto which cloud to try first. It's shown only when both keys exist.
2. **Cloud providers:**
   - today's Anthropic, Google and OpenAI key fields, unchanged in look;
   - a pasted key is checked straight away with a model-list call, which shows ✓ or ✗.
3. **Local models** (extends today's Ollama / LM Studio box):
   - one row per server with a status dot: `● Running · 4 models`, `○ Server off`, `○ Not installed`;
   - **Rescan** and **Add server…** buttons;
   - Apple's status line;
   - E2's "Download a model" goes here later.

**Chat:**
- **Model chip:** the Mac's existing model chip and popover stay. The Windows/Linux chat gains the same chip.
- **Reply caption:** every reply gets a small caption: `cloud · Claude Sonnet`, `cloud · gpt-6.1-sol`, `local · qwen3.5:2b` or `network · llama3 @ studio-pc`.
- **Web-search sources:** sources from Claude and OpenAI web search appear as clickable links under the reply. OpenAI requires citations to be visible and clickable.
- **Empty state** (no key and no model): "Add a cloud key" and "Use a local model". The second opens a short guide linking Ollama and LM Studio.

**Windows/Linux settings** (`windows/src/settings/main.ts`): the same three boxes. The fixed three-model list is replaced by each provider's live model list. The chosen models are stored in `settings.rs`.

## 5. Errors, fallbacks and privacy

**When Auto retries locally.** Auto retries **once**, per message, when all of these hold:
- the setting is Auto;
- a local model is ready;
- the failure is temporary:
  - offline;
  - DNS or connection failure;
  - a connection timeout (local 5 s, cloud 10 s);
  - no first token (local 60 s, cloud 30 s);
  - HTTP 5xx;
  - HTTP 429 or "overloaded" (OpenAI: `rate_limit_error`; 503 `server_is_overloaded`).

The next message tries the cloud again, so Auto recovers without the user doing anything.

**It never retries on:**
- 401/403 (key problems);
- 400 (a bad request);
- **billing limits, which retrying can't fix.** OpenAI returns these as a 429 with `insufficient_quota`, `credit_balance_exhausted`, `*_spend_limit_exceeded` or `organization_usage_limit_exceeded`. Anthropic's equivalent is a billing or credit error. Falling back would hide that the account needs attention;
- a model refusal, because sending it to another model would get around the provider's rules;
- the user pressing Stop.

**Offline shortcut (Mac).** `NWPathMonitor` (Network framework) tells the router when the Mac is offline. Auto then goes straight to local instead of waiting for the cloud timeout.

**Messages.** Plain, lightly cat-flavoured, and each has at most one action:

| Situation | Message | Action |
|---|---|---|
| Fell back to local | "Claude's busy right now, so Qwen answered instead." (caption: local) | none |
| 429 and no local model | "Claude is busy. Trying again in 20 s." (honours `Retry-After`) | Cancel |
| Key rejected | "Your Anthropic key was rejected." (or OpenAI, Google) | Open Settings |
| Billing limit | "Your OpenAI credit ran out." or "…spend limit reached." | Open billing page |
| Local server unreachable | "Couldn't reach LM Studio. Is its server on?" | Open guide |
| Local model loading | "Waking up qwen3.5…" (the cat yawns and stretches) | none |
| Stream cut off | partial reply kept, marked "interrupted" | Continue · Retry |
| Outdated server | "Update Ollama to use it here." | Open guide |
| Too long for the model | "This chat got long, so I dropped the oldest messages." | none |
| Model can't see images (Linux, no OCR) | "This model can't see images. Pick one that can." | Choose model |
| Refusal | the provider's refusal, shown as is | none |

**Responsiveness:**
- **Pre-warming:** opening the chat pre-warms the selected local model. Ollama loads the model on an empty request; Apple's model has `prewarm()`.
- **Stop:** cancels any stream on both platforms.
- **Context overflow:** drops the oldest turns, never the system prompt or the latest message.
- **The cat:** failures use the existing error state and sound. The cat never loops on an error.

**Privacy rules:**
- **Labels:** every answer is labelled local, network or cloud.
- **Allowed connections:** NotchMeow only contacts providers that are set up, localhost, and servers the user typed in. No telemetry.
- **Keys:**
  - stored only in the OS keychain;
  - stay on the Rust side on Windows and Linux;
  - never logged.
- **Logs (`AppLog`, `nm.log`):** record event types and errors, never prompts, file contents or keys.
- **Apple:** only the on-device model; Private Cloud Compute is not used in E.
- **OpenAI storage:** every request sends `store:false`. Otherwise the Responses API stores conversations by default, for at least 30 days. NotchMeow resends the conversation each turn instead of using `previous_response_id`. OpenAI still keeps abuse-monitoring logs for up to 30 days and doesn't train on API data by default. `INTEGRATIONS.md` says so.
- **Support logs:** for API errors NotchMeow logs the provider's request ID (`x-request-id`), which is useful for support. It never logs content.
- **No effect on agents:** a model failure can never block an agent. Hooks, approvals and cat states run on separate paths from AI calls.
- **Deferred to F:**
  - a "what was sent" log;
  - defence against instructions hidden in files (prompt injection).

  E's chat has no client-side tools, so injected instructions can't act. F's cats will have tools.

## 6. Testing

**Shared test cases.** `tests/fixtures/ai/` (new) is run by both the Swift and the Rust tests, so the two apps can't drift apart:

| File | What it covers |
|---|---|
| `router-cases.json` | Inputs: keys present, local servers up, online or offline, and the error kind. Expected: chosen provider, fallback yes or no, and the label. Must include: no key + local up → local; rejected key → error, no fallback; 429 + local → local; 429 and no local → retry countdown; refusal → no fallback; OpenAI `insufficient_quota` 429 → billing message, no fallback; Preferred cloud = OpenAI with both keys → OpenAI. |
| `sse/*.txt` | Recorded streams in three formats: OpenAI chat-completions (local servers and Google), OpenAI **Responses**, and Anthropic. They cover text, `<think>` blocks, tool-call deltas split across chunks, a stream cut mid-way and keep-alive comments. The Responses streams add `function_call_arguments.delta`, `web_search_call.*`, `output_text.annotation.added`, `refusal.delta`, `response.incomplete`, `response.failed` and a mid-stream `error` event. |
| `budget-cases.json` | Context sizes against text lengths, giving the expected cut point and notice |
| `attachments/` | Tiny files (a few KB each): text PDF, image-only PDF, docx, rtf, html, png, zip. The over-25 MB file is generated during the test and never committed. |

**Fake server.** `tests/fake_local_llm.py` gains:
- `--persona ollama|lmstudio|llamacpp|jan`, which provides each server's check endpoints;
- an Anthropic `/v1/messages` SSE route and an OpenAI `/v1/responses` SSE route;
- `--fail timeout|500|429|401|cut|slow-first-token|refuse`.

**Debug-only redirect.** In Debug builds only, an environment variable points the cloud providers' base URLs at the fake server. Release builds compile it out, so a shipped app can't be redirected.

**Swift tests:**
- New `scripts/test-ai-*.sh` follow the existing pattern (`swiftc` with the sources, the fake server on a free port) and are added to `.github/workflows/build.yml`:
  - router;
  - streaming parser;
  - budget;
  - attachments;
  - discovery against fake personas.
- Existing `ChatParsingTests` keep passing.

**Rust tests:**
- Unit tests in `ai/*` over the same fixtures.
- Linux CI already runs `cargo test --workspace`.
- **New:** add the same step to `.github/workflows/windows.yml`. Windows is where the Origin difference lives.

**Regression and leak tests:**
- The dropped-file-after-first-turn bug gets a regression test.
- **Leak test:** a unique marker word is put in a prompt and in a dropped file. The test then asserts that it never appears in the log output.

**Done means:**
- **Mac:**
  - with Ollama running and no keys, chat works locally with zero setup;
  - with Apple Intelligence on, on macOS 26+, chat works with no keys and no servers;
  - offline mid-session, the next message is answered locally within about 1 s, with no cloud wait.
- **Windows/Linux:** chat works with Anthropic, Google, OpenAI, Ollama, LM Studio, llama.cpp and Jan, all streaming.
- **OpenAI parity:** on both platforms, OpenAI matches Claude: web search with clickable sources, native PDF and image reading, and streaming. Every OpenAI request carries `store:false`; the fake server's request log asserts it.
- **Files:** each file type in §3 reaches each provider as the table says.
- **Discovery:** with nothing running, discovery finishes in under 400 ms.
- **Footprint:** 0% CPU while hidden, and no new Mac dependencies.
- **CI:** all shared test cases pass on macOS, Windows and Linux CI.

**Manual matrix before release:**
- real Ollama and LM Studio on all three operating systems;
- Jan and llama.cpp on one OS each;
- Apple on-device on macOS 26 and 27;
- Windows 11 (Origin behaviour) and Linux Wayland;
- the empty state;
- a network trace (Little Snitch or `nettop`) showing traffic only to configured hosts;
- a VoiceOver / Narrator pass on the new settings and messages.

## Files touched

- **macOS:**
  - **New:** the `NotchBuddy/Sources/App/AI/*` files.
  - **Changed:**
    - `ClaudeService.swift` and `LocalChat.swift` (absorbed);
    - `IslandTypes.swift` (`ChatProvider`);
    - `AppState.swift` (per-feature choices);
    - `SettingsView.swift` (AI section);
    - `IslandViewContent.swift` (reply caption, empty state, drop card);
    - `FileDropView.swift`;
    - `project.yml` (framework linking).
- **Windows/Linux:**
  - **New:** `windows/src-tauri/src/ai/*`.
  - **Changed:**
    - `claude.rs` (moved);
    - `lib.rs` (commands);
    - `secrets.rs`;
    - `settings.rs`;
    - `files.rs`;
    - `windows/src/views/chat.ts`;
    - `windows/src/island/island.ts`;
    - `windows/src/settings/main.ts`;
    - `Cargo.toml` (PDF, zip and `windows` OCR crates).
- **Docs:**
  - **New:** `docs/AI-PROVIDERS.md`.
  - **Changed:** `docs/INTEGRATIONS.md` (what each provider receives) and `windows/README.md` (platform differences).
- **Tests and CI:**
  - **New:** `tests/fixtures/ai/*` and `scripts/test-ai-*.sh`.
  - **Changed:** `tests/fake_local_llm.py`, `.github/workflows/build.yml` and `windows.yml`.

## E2 outline (separate plan, after E1 ships)

- **Runtime:** a "Download a model" button in Local models installs llama.cpp's `llama-server`. It ships signed inside the app bundle: notarized with the hardened runtime on Mac, Authenticode on Windows. It runs on a private port as one more OpenAI-compatible server.
- **What gets downloaded:** only model weights (data), after the user confirms the name, size and licence. Default Qwen3.5-2B; a smaller Qwen3.5-0.8B for low-RAM machines.
- **Still to decide:** whether the runtime ships in the base installer or as an optional component. Decided in E2's own brainstorm.

## Risks and open questions

- **Apple rate limits for accessory apps** are documented inconsistently. The retry-then-fallback path covers it; test on real hardware.
- **Weak-linking FoundationModels** on a macOS 15 deployment target must be verified in the first build.
- **Tool calling on small local models** is uneven: Ollama ignores `tool_choice`, and template quality varies. It doesn't affect E, which uses no tools; F must test it model by model.
- **macOS 27's `LanguageModel` protocol.** Apple's open-source `ChatCompletionsLanguageModel` (Apache-2.0, no dependencies) could later let the Mac run every backend through Apple's session API. Revisit when macOS 27 becomes the floor.
- **Gemma 4 E2B** is 4.6–7.5 GB on disk despite its name. Don't suggest it as a small default.

## Research

Done 2026-10-03 by research subagents. The notes are summarised in the conversation; their key sources are:
- Apple: WWDC26 sessions 241/339/8016, TN3193, the `contextSize` docs, `apple/foundation-models-utilities`;
- Microsoft: Phi Silica and Foundry Local docs and licences;
- OpenAI (developers.openai.com/api/docs): migrate-to-responses, deprecations, tools-web-search, file-inputs, images-vision, structured-outputs, function-calling, models, your-data, error-codes, rate-limits, and the Responses streaming-events reference;
- Ollama: OpenAI-compatibility and tool-calling docs, `envconfig` (allowed origins);
- LM Studio: headless docs;
- llama.cpp: server README, function-calling docs, PRs #17524 and #12379;
- Jan: API server docs;
- model cards: Qwen3.5-2B, Gemma 4 E2B;
- Tauri: sidecar and Microsoft Store docs.
