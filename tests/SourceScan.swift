import Foundation

// Reading app source as text, for the pins no test program can compile the app's files for (P-mac, fix wave 2). A pin that reads a file through `code` cannot be
// satisfied by a commented-out line: whole-line and trailing `//` comments and `/* */` blocks (which nest, as Swift's do) are removed, and a comment marker inside a
// string literal ("://", a script embedded in a multi-line string, a raw `#"..."#` string, an interpolation) is kept as the text it is. Pure Foundation; compiled into
// scripts/test-projects-wiring.sh and scripts/test-projects-registry.sh.
enum SourceScan {
    /// `text` without its comments. A line that held only a comment is gone with its newline; a line that ends in one loses its trailing space too, so a pin that
    /// spans lines reads the code as if the comment had never been written. `balanced` is false when the text ends inside a string or an interpolation (a scanner
    /// that lost its place would otherwise hide code from every pin).
    static func scan(_ text: String) -> (code: String, balanced: Bool) {
        enum Ctx { case code(interp: Bool, depth: Int), str(multi: Bool, hashes: Int) }
        let s = Array(text.unicodeScalars), n = s.count
        var stack: [Ctx] = [.code(interp: false, depth: 0)]
        var lines: [String] = [], touched: [Bool] = []
        var cur = "", curTouched = false
        var i = 0

        func endLine() { lines.append(cur); touched.append(curTouched); cur = ""; curTouched = false }
        func emit(_ from: Int, _ to: Int) { for k in from..<to { cur.unicodeScalars.append(s[k]) } }
        func emitChar() { if s[i] == "\n" { endLine() } else { cur.unicodeScalars.append(s[i]) }; i += 1 }
        func at(_ k: Int) -> Unicode.Scalar? { i + k < n ? s[i + k] : nil }

        while i < n {
            let c = s[i]
            switch stack[stack.count - 1] {
            case .code(let interp, let depth):
                if c == "/", at(1) == "/" {
                    while i < n, s[i] != "\n" { i += 1 }
                    curTouched = true
                    continue
                }
                if c == "/", at(1) == "*" {
                    var level = 1
                    i += 2
                    curTouched = true
                    while i < n, level > 0 {
                        if s[i] == "/", at(1) == "*" { level += 1; i += 2 }
                        else if s[i] == "*", at(1) == "/" { level -= 1; i += 2 }
                        else { if s[i] == "\n" { endLine(); curTouched = true }; i += 1 }
                    }
                    continue
                }
                if c == "#" || c == "\"" {
                    var j = i, hashes = 0
                    while j < n, s[j] == "#" { hashes += 1; j += 1 }
                    if j < n, s[j] == "\"" {
                        let multi = j + 2 < n && s[j + 1] == "\"" && s[j + 2] == "\""
                        let end = j + (multi ? 3 : 1)
                        emit(i, end)
                        i = end
                        stack.append(.str(multi: multi, hashes: hashes))
                        continue
                    }
                }
                if interp {
                    if c == "(" { stack[stack.count - 1] = .code(interp: true, depth: depth + 1) }
                    else if c == ")" {
                        if depth == 0 { stack.removeLast(); emitChar(); continue }
                        stack[stack.count - 1] = .code(interp: true, depth: depth - 1)
                    }
                }
                emitChar()
            case .str(let multi, let hashes):
                if c == "\\" {
                    var j = i + 1, k = 0
                    while k < hashes, j < n, s[j] == "#" { j += 1; k += 1 }
                    if k == hashes {
                        if j < n, s[j] == "(" {
                            emit(i, j + 1)
                            i = j + 1
                            stack.append(.code(interp: true, depth: 0))
                        } else {
                            emit(i, j)
                            i = j
                            if i < n { emitChar() }
                        }
                        continue
                    }
                }
                if c == "\"" {
                    let need = multi ? 3 : 1
                    var q = 0
                    while q < need, i + q < n, s[i + q] == "\"" { q += 1 }
                    if q == need {
                        var h = 0
                        while h < hashes, i + need + h < n, s[i + need + h] == "#" { h += 1 }
                        if h == hashes {
                            emit(i, i + need + h)
                            i += need + h
                            stack.removeLast()
                            continue
                        }
                    }
                }
                emitChar()
            }
        }
        endLine()
        var out: [String] = []
        for (line, wasTouched) in zip(lines, touched) {
            if !wasTouched { out.append(line); continue }
            var kept = line
            while let last = kept.unicodeScalars.last, last == " " || last == "\t" { kept.unicodeScalars.removeLast() }
            if !kept.isEmpty { out.append(kept) }
        }
        return (out.joined(separator: "\n"), stack.count == 1)
    }

    static func code(_ text: String) -> String { scan(text).code }

    /// A shell script without its whole-line `#` comments (a pin over a script's compile line must not be satisfied by a commented-out one).
    static func shellCode(_ text: String) -> String {
        text.components(separatedBy: "\n").filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix("#") }.joined(separator: "\n")
    }

    /// A type's text: from its declaration (`decl`, e.g. "struct ProjectPill: View {") to the first line after it that is exactly "}" at column 0, that line
    /// included. nil when the declaration is not there or the type never closes, so a pin fails instead of reading a window that overshoots into the next type or
    /// falls short of a grown one.
    static func structText(_ decl: String, in text: String) -> String? {
        guard let r = text.range(of: decl) else { return nil }
        var out: [String] = []
        for line in text[r.lowerBound...].components(separatedBy: "\n") {
            out.append(line)
            if line == "}" && out.count > 1 { return out.joined(separator: "\n") }
        }
        return nil
    }

    /// A view expression and the modifier lines that follow it: from the first line holding `needle` through the lines after it that start with ".".
    static func chain(_ needle: String, in text: String) -> String? {
        let lines = text.components(separatedBy: "\n")
        guard let start = lines.firstIndex(where: { $0.contains(needle) }) else { return nil }
        var end = start
        while end + 1 < lines.count, lines[end + 1].trimmingCharacters(in: .whitespaces).hasPrefix(".") { end += 1 }
        return lines[start...end].joined(separator: "\n")
    }

    /// The text from the first `start` to the first `end` after it, `end` included; nil when either is missing.
    static func block(from start: String, to end: String, in text: String) -> String? {
        guard let a = text.range(of: start), let b = text.range(of: end, range: a.upperBound..<text.endIndex) else { return nil }
        return String(text[a.lowerBound..<b.upperBound])
    }

    /// The argument list of every `TimelineView(` in `text` (code, comments already removed): the text up to the matching closing parenthesis.
    static func timelineViews(in text: String) -> [String] {
        var found: [String] = []
        var search = text.startIndex..<text.endIndex
        while let r = text.range(of: "TimelineView(", range: search) {
            var depth = 1, end = r.upperBound
            while end < text.endIndex, depth > 0 {
                if text[end] == "(" { depth += 1 } else if text[end] == ")" { depth -= 1 }
                end = text.index(after: end)
            }
            found.append(String(text[r.upperBound..<end].dropLast()))
            search = end..<text.endIndex
        }
        return found
    }

    /// The `case` names of `enum <name>` (code): the comma-separated names on its `case` lines. nil when the enum is not there.
    static func enumCases(_ name: String, in text: String) -> [String]? {
        guard let body = structText("enum \(name)", in: text) else { return nil }
        return body.components(separatedBy: "\n").flatMap { line -> [String] in
            let t = line.trimmingCharacters(in: .whitespaces)
            guard t.hasPrefix("case ") else { return [] }
            return t.dropFirst(5).components(separatedBy: ",").map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        }
    }
}
