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
            // A local reasoning model that thinks first (Ollama, LM Studio, llama.cpp) has started: count it as
            // the first output, so the 60 s watchdog and "Waking up…" don't fire while it thinks.
            if ["reasoning_content", "reasoning"].contains(where: { !((delta[$0] as? String) ?? "").isEmpty }) {
                out.append(.activity)
            }
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
