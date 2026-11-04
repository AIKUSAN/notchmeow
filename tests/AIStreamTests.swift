import Foundation

@main
@MainActor
enum AIStreamTests {
    static func main() {
        recordedStreams()
        thinkFilter()
        reasoningCountsAsOutput()
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

    /// A local reasoning model that thinks for a minute has started: the first-token watchdog must see it.
    static func reasoningCountsAsOutput() {
        T.section("OpenAI chat reasoning deltas")
        func chunks(_ delta: String) -> [ChatChunk] {
            var p = OpenAIChatStreamParser()
            return p.consume(line: #"data: {"choices":[{"index":0,"delta":\#(delta)}]}"#)
        }
        T.check("reasoning_content is activity", chunks(#"{"content":null,"reasoning_content":"hmm"}"#), [.activity])
        T.check("reasoning is activity", chunks(#"{"reasoning":"hmm"}"#), [.activity])
        T.check("an empty reasoning string is nothing", chunks(#"{"reasoning_content":""}"#), [])
        T.check("a non-string reasoning is nothing", chunks(#"{"reasoning_content":5}"#), [])
        T.check("text still comes through with it", chunks(#"{"content":"hi","reasoning_content":"x"}"#), [.text("hi"), .activity])
        T.check("activity shows nothing in the reply", { var a = ReplyAccumulator(stripsThinkBlocks: true); a.add(.activity); return a.text }(), "")
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
