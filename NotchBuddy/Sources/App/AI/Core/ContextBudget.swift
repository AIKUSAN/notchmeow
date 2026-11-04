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
        let context = known(contextTokens) ?? (placement == .cloud ? nil : limits.defaultLocalContextTokens)
        let fromContext = context.map { $0 * 7 / 4 }
        guard placement == .cloud else { return fromContext ?? 0 }
        return min(fromContext ?? limits.cloudTextCapChars, limits.cloudTextCapChars)
    }

    /// A server may report 0 or a negative number for a context it doesn't know: that is no context at all.
    private static func known(_ contextTokens: Int?) -> Int? {
        contextTokens.flatMap { $0 > 0 ? $0 : nil }
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
        let context = known(contextTokens) ?? AICatalog.Limits.defaultLocalContextTokens
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
