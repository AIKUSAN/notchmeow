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
        T.check("0, 1 and 2 retries so far: try again", [0, 1, 2].map { ModelRouter.shouldAutoRetry(retries: $0) }, [true, true, true])
        T.check("3 retries so far: stop, show still busy", ModelRouter.shouldAutoRetry(retries: 3), false)
        T.check("fell back", AIMessages.fellBack(from: claude, to: qwen), "Claude's busy right now, so Qwen answered instead.")
        T.check("countdown", AIMessages.countdown(claude, seconds: 20), "Claude is busy. Trying again in 20 s.")
        T.check("still busy after the automatic retry", AIMessages.error(AIError(kind: .rateLimited), target: claude).text,
                "Claude is still busy. Try again in a moment.")
        T.check("still busy when overloaded", AIMessages.error(AIError(kind: .overloaded), target: gpt).text,
                "OpenAI is still busy. Try again in a moment.")
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
        await thinkTagsOnlyForThinkingModels()
        await refusalNeverFallsBack()
        await rescanForALocalFallback()

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
        /// Thrown after the chunks, as a transport would.
        var failure: AIError? = nil
        func listModels() async throws -> [ModelInfo] { [] }
        func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
            let chunks = self.chunks, hang = self.hang, failure = self.failure
            return AsyncThrowingStream { continuation in
                let task = Task {
                    chunks.forEach { continuation.yield($0) }
                    if hang { try? await Task.sleep(nanoseconds: 10_000_000_000) }
                    continuation.finish(throwing: failure)
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

    /// An Auto plan with a cloud primary against scripted providers; counts the local attempts and the rescans.
    static func auto(cloud: ScriptedProvider, planned: Bool = true, rescan: Bool = false,
                     provider: AIProviderID = .anthropic) async -> (result: RunResult, localAttempts: Int, rescans: Int) {
        let attempts = Box<Int>(), rescans = Box<Int>()
        let local = ScriptedProvider(chunks: [.text("Local answer"), .finish(.stop)], hang: false)
        let runner = ChatRunner(makeProvider: { t in
                                    if t.placement == .local { attempts.add(1); return local }
                                    return cloud
                                },
                                makeRequest: { t in ChatRequest(model: t.model, system: "s", messages: []) })
        let primary = ChatTarget(provider: provider, model: "m", placement: .cloud)
        let target = ChatTarget(provider: .ollama, model: "q", placement: .local)
        let plan = RoutePlan(primary: provider, model: nil, serverID: nil, placement: .cloud,
                             fallback: planned ? LocalCandidate(provider: .ollama, model: "q", placement: .local) : nil,
                             isAuto: true)
        let r = await runner.run(plan: plan, primary: primary,
                                 fallback: { rescans.add(1); return planned || rescan ? target : nil },
                                 onEvent: { _ in })
        return (r, attempts.all.count, rescans.all.count)
    }

    /// Only OpenAI-compatible servers emit <think> blocks: a literal tag in a Claude/OpenAI/Apple answer stays.
    static func thinkTagsOnlyForThinkingModels() async {
        T.section("Think blocks are stripped only for OpenAI-compatible servers")
        let literal = "Use <think> tags like <think>x</think> in prompts."
        var (r, attempts, _) = await auto(cloud: ScriptedProvider(chunks: [.text(literal), .finish(.stop)], hang: false))
        T.check("a cloud answer keeps its literal tags", "\(r.outcome.rawValue) \(r.text)", "ok \(literal)")
        (r, attempts, _) = await auto(cloud: ScriptedProvider(chunks: [.text("<think> is a tag."), .finish(.stop)], hang: false))
        T.check("an answer starting with a tag is not empty", "\(r.outcome.rawValue) \(r.text) \(attempts)", "ok <think> is a tag. 0")
        (r, attempts, _) = await auto(cloud: ScriptedProvider(chunks: [.text("  padded <think>  "), .finish(.stop)], hang: false))
        T.check("the answer is still trimmed", r.text, "padded <think>")
        r = await scripted([.text("<think>x</think>Real answer"), .finish(.stop)])
        T.check("a thinking model's blocks are still hidden", r.text, "Real answer")
    }

    /// A refusal is told to the person; it never goes to another model.
    static func refusalNeverFallsBack() async {
        T.section("A refusal never falls back")
        var (r, attempts, _) = await auto(cloud: ScriptedProvider(chunks: [.finish(.refusal)], hang: false), provider: .openai)
        T.check("a content-filter finish with no text is a refusal", "\(r.outcome.rawValue) \(r.error?.kind.rawValue ?? "nil")",
                "error refusal")
        T.check("and no local model was asked", attempts, 0)
        (r, attempts, _) = await auto(cloud: ScriptedProvider(chunks: [.refusal("I can't help with that.", replacesText: false)],
                                                              hang: false, failure: AIError(kind: .interrupted)))
        T.check("a refusal cut before its end is still a refusal", "\(r.outcome.rawValue) \(r.error?.kind.rawValue ?? "nil")",
                "error refusal")
        T.check("with its text", r.text, "I can't help with that.")
        T.check("and no local model was asked either", attempts, 0)
    }

    /// Spec §2: Auto needing a local fallback is a discovery trigger.
    static func rescanForALocalFallback() async {
        T.section("Auto rescans for a local model after a temporary cloud failure")
        let busy = ScriptedProvider(chunks: [], hang: false, failure: AIError(kind: .overloaded, retryAfter: 2))
        var (r, attempts, scans) = await auto(cloud: busy, planned: false, rescan: true)
        T.check("a model found by the rescan answers", "\(r.outcome.rawValue) \(r.text) \(attempts) \(scans)", "fallback Local answer 1 1")
        T.check("and the cloud failure is kept for the notice", r.error?.kind, .overloaded)
        (r, attempts, scans) = await auto(cloud: busy, planned: false, rescan: false)
        T.check("nothing found: the countdown stands", "\(r.outcome.rawValue) \(attempts) \(scans)", "retry_countdown 0 1")
        let down = ScriptedProvider(chunks: [], hang: false, failure: AIError(kind: .server))
        (r, attempts, scans) = await auto(cloud: down, planned: false, rescan: false)
        T.check("nothing found: the error stands", "\(r.outcome.rawValue) \(r.error?.kind.rawValue ?? "nil") \(scans)", "error server 1")
        for kind in [AIErrorKind.auth, .billing, .badRequest] {
            let denied = ScriptedProvider(chunks: [], hang: false, failure: AIError(kind: kind))
            (r, attempts, scans) = await auto(cloud: denied, planned: false, rescan: true)
            T.check("\(kind.rawValue) is not temporary: no rescan", "\(r.outcome.rawValue) \(attempts) \(scans)", "error 0 0")
        }
        (r, attempts, scans) = await auto(cloud: ScriptedProvider(chunks: [.text("<think>endless"), .finish(.length)], hang: false),
                                          planned: false, rescan: true, provider: .google)
        T.check("out of room: no rescan", "\(r.error?.code ?? "nil") \(scans)", "\(AIError.outOfRoomCode) 0")
        (r, attempts, scans) = await auto(cloud: ScriptedProvider(chunks: [.finish(.refusal)], hang: false),
                                          planned: false, rescan: true)
        T.check("refusal: no rescan", "\(r.error?.kind.rawValue ?? "nil") \(scans)", "refusal 0")
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
