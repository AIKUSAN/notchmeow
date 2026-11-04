import Foundation

// The sidekick's local voice, the pure part: the sanity check that guards the swap of a template for a sentence a local model wrote (`acceptNicerLine`), and the short prompt the model is given.
// Port of `acceptNicerLine` in `shared/sidekick-core.js` (the tie-breaker); tests/fixtures/sidekick/voice-cases.json pins it and docs/SIDEKICK-CONTRACT.md explains it. The template is always
// shown first and is always right; a nicer sentence replaces it only if it is one line of at most 200 characters, with no URL, no `/` or `\`, no backtick and no markdown, uses only numbers
// that are in the facts, and names an agent of the facts. The model is given the template's own words, which hold only the facts (the agent's name, the project's basename, counts, up to three
// file basenames and the state in words): never a command, a path, a prompt or an assistant message. Pure Foundation.

enum SidekickVoice {
    /// The local model has this long; after it the template stands.
    static let timeoutMs = 6000.0
    static let maxCharacters = 200
    /// The prompt stays under this, because Apple's on-device model holds only a few thousand tokens.
    static let maxPromptCharacters = 800
    static let system = "You rewrite one short status line from a coding assistant into one friendly sentence. Keep every name and every number exactly as given. Never add numbers, links, file paths or markdown. Reply with the sentence only."

    /// The prompt: one instruction and the template's lines (which hold only the facts). nil when even one line does not fit.
    static func prompt(lines: [String]) -> String? {
        let head = "Say this in one short, friendly sentence of at most \(maxCharacters) characters. Keep every name and number exactly as it is. Add no numbers, links, paths or markdown.\n\n"
        var kept = lines
        while !kept.isEmpty {
            let p = head + kept.joined(separator: "\n")
            if p.count <= maxPromptCharacters { return p }
            kept.removeLast()
        }
        return nil
    }

    private static func allowedNumbers(_ list: [[String: Any]]) -> Set<String> {
        var allowed = Set<String>()
        func strip(_ d: String) -> String { d.replacingOccurrences(of: "^0+(?=[0-9])", with: "", options: .regularExpression) }
        func walk(_ v: Any?) {
            guard let v, !(v is NSNull) else { return }
            if let n = v as? NSNumber {
                if CFGetTypeID(n) == CFBooleanGetTypeID() { return }
                let d = n.doubleValue
                if d.isFinite { allowed.insert(String(Int64(min(abs(d.rounded(.towardZero)), 1e18)))) }
            } else if let s = v as? String { for m in Rx.all("[0-9]+", s) { if let d = m[0] { allowed.insert(strip(d)) } } }
            else if let a = v as? [Any] { allowed.insert(String(a.count)); a.forEach(walk) }
            else if let o = v as? [String: Any] { o.values.forEach(walk) }
        }
        for f in list {
            walk(f)
            if let files = f["files"] as? [Any], let more = f["more"] as? NSNumber { allowed.insert(String(files.count + more.intValue)) }
            if (f["stepsAtLeast"] as? NSNumber).map({ CFGetTypeID($0) == CFBooleanGetTypeID() && $0.boolValue }) == true { allowed.insert(String(SidekickLedger.ringMax)) }
        }
        return allowed
    }

    /// Whether a sentence from a local model may replace the template. `facts` is the `facts` of a recap or a status: a list of facts, or one fact (anything else is no facts).
    static func accept(_ line: Any?, facts: Any?) -> Bool {
        guard let line = line as? String else { return false }
        let t = line.trimmingCharacters(in: .whitespacesAndNewlines)
        let list = (facts as? [Any])?.compactMap { $0 as? [String: Any] } ?? (facts as? [String: Any]).map { [$0] } ?? []
        if t.isEmpty || t.unicodeScalars.count > maxCharacters || list.isEmpty { return false }
        if Rx.test("[\\r\\n\u{2028}\u{2029}]", t) || Rx.test("://|\(Rx.wordStart)www\\.", t, .caseInsensitive) || Rx.test("[/\\\\`]", t) || Rx.test("[*_#\\[\\]<>|~]", t) || Rx.test("^[-+]\\s", t) { return false }
        let allowed = allowedNumbers(list)
        for m in Rx.all("[0-9]+", t) {
            guard let d = m[0] else { continue }
            if !allowed.contains(d.replacingOccurrences(of: "^0+(?=[0-9])", with: "", options: .regularExpression)) { return false }
        }
        let lower = t.lowercased()
        return list.contains { f in (f["agent"] as? String).map { !$0.isEmpty && lower.contains($0.lowercased()) } ?? false }
    }
}
