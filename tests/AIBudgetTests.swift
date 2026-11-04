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

        // A server can report 0 or -1 for a context it doesn't know: that is an unknown context, never a crash.
        let long = "one\ntwo\n" + String(repeating: "x", count: 8000)
        for bad in [0, -1] {
            T.check("a context of \(bad) is unknown for the budget", ContextBudget.charBudget(placement: .local, contextTokens: bad), 7168)
            T.check("a context of \(bad) is unknown for a cloud budget", ContextBudget.charBudget(placement: .cloud, contextTokens: bad), 204_800)
            T.check("cutting with a context of \(bad) uses the unknown-context budget",
                    ContextBudget.cut(long, placement: .local, contextTokens: bad),
                    ContextBudget.cut(long, placement: .local, contextTokens: nil))
            T.check("trimming with a context of \(bad) uses the unknown-context budget",
                    ContextBudget.trimHistory(turnChars: [3000, 3000, 3000, 3000, 3000, 10], systemChars: 100, placement: .local,
                                              contextTokens: bad),
                    ContextBudget.trimHistory(turnChars: [3000, 3000, 3000, 3000, 3000, 10], systemChars: 100, placement: .local,
                                              contextTokens: nil))
        }

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
