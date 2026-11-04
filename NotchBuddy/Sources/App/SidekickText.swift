import Foundation

// The sidekick's text helpers, shared by every rule: a small regular-expression kit (ICU, with the JavaScript meanings of `$` and `\b` that the contract's rules were
// written with), the basename of a path, the name of an agent, and the command key's hash. Port of the helpers of `shared/sidekick-core.js` (the tie-breaker;
// tests/fixtures/sidekick/ pins it, docs/SIDEKICK-CONTRACT.md explains it). Pure Foundation: no clock, no files, no network, no randomness, and it never throws.

enum Rx {
    private static let lock = NSLock()
    nonisolated(unsafe) private static var cache: [String: NSRegularExpression] = [:]

    /// A compiled pattern, kept. A pattern that does not compile is a programming error caught by the first test run.
    static func make(_ pattern: String, _ options: NSRegularExpression.Options = []) -> NSRegularExpression {
        let key = "\(options.rawValue)|\(pattern)"
        lock.lock(); defer { lock.unlock() }
        if let r = cache[key] { return r }
        let r = try! NSRegularExpression(pattern: pattern, options: options)
        cache[key] = r
        return r
    }

    /// JavaScript's `\b` is an ASCII word boundary; ICU's is a Unicode one. These two lookarounds are JavaScript's. `$` in a pattern means the very end (`\z`), not "before a final newline".
    static let wordStart = "(?<![A-Za-z0-9_])", wordEnd = "(?![A-Za-z0-9_])"

    static func test(_ pattern: String, _ s: String, _ options: NSRegularExpression.Options = []) -> Bool {
        make(pattern, options).firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) != nil
    }

    /// The groups of the first match (group 0 first; a group that did not take part is nil), or nil when there is no match.
    static func groups(_ pattern: String, _ s: String, _ options: NSRegularExpression.Options = []) -> [String?]? {
        guard let m = make(pattern, options).firstMatch(in: s, range: NSRange(s.startIndex..., in: s)) else { return nil }
        return (0..<m.numberOfRanges).map { i in Range(m.range(at: i), in: s).map { String(s[$0]) } }
    }

    /// Every match of the pattern, each as its groups.
    static func all(_ pattern: String, _ s: String, _ options: NSRegularExpression.Options = []) -> [[String?]] {
        make(pattern, options).matches(in: s, range: NSRange(s.startIndex..., in: s)).map { m in
            (0..<m.numberOfRanges).map { i in Range(m.range(at: i), in: s).map { String(s[$0]) } }
        }
    }
}

enum SK {
    static let minute = 60000.0

    /// The last component of a path, `/` or `\` alike, without control and invisible characters (bidi overrides, zero-width marks, line separators), at most 60 code points
    /// (59 and `…` past that). Lines carry nothing else of a path.
    static func baseName(_ p: String) -> String {
        var u = Array(p.unicodeScalars)
        while let l = u.last, l == "/" || l == "\\" { u.removeLast() }
        if let i = u.lastIndex(where: { $0 == "/" || $0 == "\\" }) { u = Array(u[(i + 1)...]) }
        u = u.filter { !invisible($0.value) }
        if u.count > 60 { var v = String.UnicodeScalarView(); v.append(contentsOf: u[..<59]); return String(v) + "…" }
        var v = String.UnicodeScalarView(); v.append(contentsOf: u)
        return String(v)
    }

    private static func invisible(_ c: UInt32) -> Bool {
        (c <= 0x1F) || (0x7F...0x9F).contains(c) || c == 0xAD || c == 0x61C || c == 0x180E || (0x200B...0x200F).contains(c) || (0x202A...0x202E).contains(c)
            || c == 0x2028 || c == 0x2029 || c == 0x2060 || (0x2066...0x2069).contains(c) || c == 0xFEFF || (0xFFF9...0xFFFB).contains(c) || (0xE0000...0xE007F).contains(c)
    }

    /// The name of an agent for a person: Claude Code for `integration_claude`, `agent_<tag>` is the tag with a capital, and any other ID is "An agent".
    static func agentName(_ agentId: String?) -> String {
        guard let id = agentId else { return "An agent" }
        switch id {
        case "integration_claude": return "Claude Code"
        case "agent_cursor": return "Cursor"
        case "agent_codex": return "Codex"
        case "agent_gemini": return "Gemini CLI"
        case "agent_antigravity": return "Antigravity"
        case "agent_claude-desktop": return "Claude App"
        default:
            guard id.hasPrefix("agent_") else { return "An agent" }
            let tag = String(id.dropFirst(6))
            guard let first = tag.first else { return "An agent" }
            return first.uppercased() + tag.dropFirst()
        }
    }

    /// Characters the chat's Markdown reads as markup (emphasis, links, code, headings and list markers at a line's start, entities, HTML). Each gets a backslash, which the parser drops, so
    /// the text is shown as it is: a file name like `__init__.py` stays as it is. Newlines are kept; nothing else changes. `@` is NOT here: escaping it does not stop the renderer's e-mail autolink (`icon@2x.png` can show as a link), and a link only opens through the chat's `safeWebURL`, which allows http and https, so that link is inert.
    private static let markup = "\\`*_[]()#+-.!|<>~&".unicodeScalars

    static func markdownPlain(_ s: String) -> String {
        var out = String.UnicodeScalarView()
        for c in s.unicodeScalars {
            if markup.contains(c) { out.append("\\") }
            out.append(c)
        }
        return String(out)
    }

    // MARK: The command key

    /// FNV-1a, 32 bits, over the UTF-8 bytes of a string, as 8 lower-case hex digits.
    static func fnv1a(_ s: String) -> String {
        var h: UInt32 = 0x811c9dc5
        for b in s.utf8 { h ^= UInt32(b); h = h &* 0x01000193 }
        let hex = String(h, radix: 16)
        return String(repeating: "0", count: max(0, 8 - hex.count)) + hex
    }

    /// How deep an input may nest before its key is a fixed marker instead of a hash (the contract's `too-deep`): a hook payload from the socket is never deeper than JSONSerialization allows, and a
    /// recursion on hostile input must not run out of stack.
    static let maxDepth = 200

    /// Canonical JSON, as JavaScript's `JSON.stringify` writes it with the keys sorted (by UTF-16 code unit): no spaces. A whole number is written without a point. nil when `v` nests deeper than `maxDepth`.
    static func canon(_ v: Any?, depth: Int = 0) -> String? {
        guard depth <= maxDepth else { return nil }
        guard let v, !(v is NSNull) else { return "null" }
        if let n = v as? NSNumber {
            if CFGetTypeID(n) == CFBooleanGetTypeID() { return n.boolValue ? "true" : "false" }
            let d = n.doubleValue
            if !d.isFinite { return "null" }
            if d == d.rounded(), abs(d) < 1e15 { return String(Int64(d)) }
            return "\(d)"
        }
        if let s = v as? String { return quote(s) }
        if let a = v as? [Any] {
            var parts: [String] = []
            for x in a { guard let c = canon(x, depth: depth + 1) else { return nil }; parts.append(c) }
            return "[" + parts.joined(separator: ",") + "]"
        }
        if let o = v as? [String: Any] {
            let keys = o.keys.sorted { Array($0.utf16).lexicographicallyPrecedes(Array($1.utf16)) }
            var parts: [String] = []
            for k in keys { guard let c = canon(o[k], depth: depth + 1) else { return nil }; parts.append(quote(k) + ":" + c) }
            return "{" + parts.joined(separator: ",") + "}"
        }
        return "null"
    }

    /// A JSON string the way `JSON.stringify` writes it: quotes, backslash and the control characters escaped, everything else as it is.
    static func quote(_ s: String) -> String {
        var out = "\""
        for c in s.unicodeScalars {
            switch c {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\u{08}": out += "\\b"
            case "\u{0C}": out += "\\f"
            case "\n": out += "\\n"
            case "\r": out += "\\r"
            case "\t": out += "\\t"
            default:
                if c.value < 0x20 { out += String(format: "\\u%04x", c.value) } else { out.unicodeScalars.append(c) }
            }
        }
        return out + "\""
    }

    /// What "the same step" means: the tool name and a hash of its input, whitespace in a command folded. Only the hash is ever stored.
    static func commandKey(tool: String, input: Any?) -> String {
        var v = input
        if var o = input as? [String: Any], let c = o["command"] as? String {
            o["command"] = c.trimmingCharacters(in: .whitespacesAndNewlines).replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
            v = o
        }
        guard let c = canon(v) else { return "\(tool)#too-deep" }
        return "\(tool)#\(fnv1a(c))"
    }
}
