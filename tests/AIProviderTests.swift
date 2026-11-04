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
        await anthropic()
        await openAI()
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

        // A server runs a model at its loaded (runtime) context, not the one it was trained for: use the runtime
        // value when there is one, else the trained maximum capped at 4,096; 0 or less counts as unknown.
        T.section("local context sizes (fake Ollama and LM Studio)")
        let ollamaCtx = FakeServer(["--persona", "ollama-ctx"])
        for (model, want) in [("ctx-runtime", 8192), ("ctx-trained-big", 4096), ("ctx-trained-small", 2048),
                              ("ctx-none", nil), ("ctx-zero", nil), ("not-a-model", nil)] as [(String, Int?)] {
            T.check("Ollama \(model)", await local(ollamaCtx).modelDetails(model)?.contextTokens, want)
        }
        ollamaCtx.stop()
        let lmCtx = FakeServer(["--persona", "lmstudio-ctx"])
        for (model, want) in [("lm-loaded", 16384), ("lm-max-big", 4096), ("lm-max-small", 2048),
                              ("lm-none", nil), ("lm-zero", nil)] as [(String, Int?)] {
            T.check("LM Studio \(model)", await local(lmCtx, .lmstudio).modelDetails(model)?.contextTokens, want)
        }
        T.check("LM Studio: a model that is not listed has no details", await local(lmCtx, .lmstudio).modelDetails("not-a-model"), nil)
        lmCtx.stop()
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
