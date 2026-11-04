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
    /// Claude Code took at least one step: the work is done, so Auto must not hand the question to another model.
    private(set) var sawSteps = false

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
        case .activity, .engine:
            break
        case .step:
            sawSteps = true
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
