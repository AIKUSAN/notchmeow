import Foundation

// The shelf contract on the Mac (sub-project G1; docs/SHELF-CONTRACT.md, tests/fixtures/shelf/): the three rules both apps share, `zoneAt` (which half of the open island the pointer is
// in), `shelfClean` (how shelf.json is read) and `shelfAdd` (files dropped on the Shelf half), and the strict JSON reader the file goes through. Foundation only, no AppKit. The fixtures are
// replayed by scripts/test-shelf-rules.sh; `tests/fixtures/shelf/reference.py` decides when this file and a fixture disagree.

// MARK: - A JSON value, read the way the contract reads it

/// A parsed JSON value. Foundation's `JSONSerialization` cannot be used: it repairs a lone surrogate, may strip a byte order mark and has its own idea of big numbers. A string remembers
/// whether it held a lone surrogate (`lone`), which no Swift `String` can hold and which the contract refuses in a name and in a link.
indirect enum ShelfJSON: Equatable, Sendable {
    case null
    case bool(Bool)
    case number(Double)
    case string(String, lone: Bool)
    case array([ShelfJSON])
    case object([String: ShelfJSON])

    static func text(_ s: String) -> ShelfJSON { .string(s, lone: false) }
}

enum ShelfJSONParser {
    /// Nesting deeper than this is "not a shelf" (Python's reference gives up at about 1000 levels; a shelf is two deep).
    static let maxDepth = 512

    /// The bytes of a file to the value they hold, or nil when they are not strict JSON: invalid UTF-8, a byte order mark in front, `NaN`, `Infinity`, text after the value, a control
    /// character inside a string, a number with a leading zero. The last of a repeated key wins.
    static func parse(_ bytes: [UInt8]) -> ShelfJSON? {
        let text = String(decoding: bytes, as: UTF8.self)
        guard Array(text.utf8) == bytes else { return nil }   // decoding repairs invalid UTF-8 with U+FFFD, which changes the bytes
        var p = Reader(s: Array(text.unicodeScalars))
        guard let v = p.value(depth: 0) else { return nil }
        p.skipWhite()
        return p.i == p.s.count ? v : nil
    }

    private struct Reader {
        let s: [Unicode.Scalar]
        var i = 0

        init(s: [Unicode.Scalar]) { self.s = s }

        mutating func skipWhite() {
            while i < s.count, s[i] == " " || s[i] == "\t" || s[i] == "\n" || s[i] == "\r" { i += 1 }
        }

        mutating func lit(_ word: String, _ v: ShelfJSON) -> ShelfJSON? {
            let w = Array(word.unicodeScalars)
            guard i + w.count <= s.count, Array(s[i..<i + w.count]) == w else { return nil }
            i += w.count
            return v
        }

        mutating func value(depth: Int) -> ShelfJSON? {
            skipWhite()
            guard i < s.count else { return nil }
            switch s[i] {
            case "{": return object(depth: depth + 1)
            case "[": return array(depth: depth + 1)
            case "\"": return string().map { .string($0.text, lone: $0.lone) }
            case "t": return lit("true", .bool(true))
            case "f": return lit("false", .bool(false))
            case "n": return lit("null", .null)
            default: return number()
            }
        }

        mutating func array(depth: Int) -> ShelfJSON? {
            guard depth <= ShelfJSONParser.maxDepth else { return nil }
            i += 1
            var out: [ShelfJSON] = []
            skipWhite()
            if i < s.count, s[i] == "]" { i += 1; return .array(out) }
            while true {
                guard let v = value(depth: depth) else { return nil }
                out.append(v)
                skipWhite()
                guard i < s.count else { return nil }
                if s[i] == "," { i += 1; continue }
                if s[i] == "]" { i += 1; return .array(out) }
                return nil
            }
        }

        mutating func object(depth: Int) -> ShelfJSON? {
            guard depth <= ShelfJSONParser.maxDepth else { return nil }
            i += 1
            var out: [String: ShelfJSON] = [:]
            skipWhite()
            if i < s.count, s[i] == "}" { i += 1; return .object(out) }
            while true {
                skipWhite()
                guard i < s.count, s[i] == "\"", let key = string() else { return nil }
                skipWhite()
                guard i < s.count, s[i] == ":" else { return nil }
                i += 1
                guard let v = value(depth: depth) else { return nil }
                if !key.lone { out[key.text] = v }   // reference.py keeps it as a key no lookup matches; dropping it never lets it stand in for the real key
                skipWhite()
                guard i < s.count else { return nil }
                if s[i] == "," { i += 1; continue }
                if s[i] == "}" { i += 1; return .object(out) }
                return nil
            }
        }

        func hex4(_ at: Int) -> UInt32? {
            guard at + 4 <= s.count else { return nil }
            var v: UInt32 = 0
            for k in 0..<4 {
                guard let d = Character(s[at + k]).hexDigitValue else { return nil }
                v = v * 16 + UInt32(d)
            }
            return v
        }

        mutating func string() -> (text: String, lone: Bool)? {
            i += 1
            var out = String.UnicodeScalarView()
            var lone = false
            while i < s.count {
                let c = s[i]
                if c == "\"" { i += 1; return (String(out), lone) }
                if c.value < 0x20 { return nil }
                if c != "\\" { out.append(c); i += 1; continue }
                i += 1
                guard i < s.count else { return nil }
                let e = s[i]
                i += 1
                switch e {
                case "\"": out.append("\"")
                case "\\": out.append("\\")
                case "/": out.append("/")
                case "b": out.append("\u{8}")
                case "f": out.append("\u{c}")
                case "n": out.append("\n")
                case "r": out.append("\r")
                case "t": out.append("\t")
                case "u":
                    guard let u = hex4(i) else { return nil }
                    i += 4
                    if (0xD800...0xDBFF).contains(u) {
                        // A high surrogate pairs with an escaped low one right after it; on its own it is lone.
                        if i + 6 <= s.count, s[i] == "\\", s[i + 1] == "u", let lo = hex4(i + 2), (0xDC00...0xDFFF).contains(lo) {
                            i += 6
                            out.append(Unicode.Scalar(0x10000 + ((u - 0xD800) << 10) + (lo - 0xDC00))!)
                        } else {
                            lone = true
                        }
                    } else if (0xDC00...0xDFFF).contains(u) {
                        lone = true
                    } else {
                        out.append(Unicode.Scalar(u)!)
                    }
                default: return nil
                }
            }
            return nil
        }

        mutating func number() -> ShelfJSON? {
            let start = i
            if i < s.count, s[i] == "-" { i += 1 }
            func digits() -> Int {
                var n = 0
                while i < s.count, s[i].value >= 0x30, s[i].value <= 0x39 { i += 1; n += 1 }
                return n
            }
            guard i < s.count else { return nil }
            if s[i] == "0" { i += 1 } else if digits() == 0 { return nil }
            if i < s.count, s[i] == "." {
                i += 1
                if digits() == 0 { return nil }
            }
            if i < s.count, s[i] == "e" || s[i] == "E" {
                i += 1
                if i < s.count, s[i] == "+" || s[i] == "-" { i += 1 }
                if digits() == 0 { return nil }
            }
            var text = String.UnicodeScalarView()
            text.append(contentsOf: s[start..<i])
            guard let d = Double(String(text)) else { return nil }   // 1e400 is +infinity, which the rules treat as "not a number we keep"
            return .number(d)
        }
    }
}

// MARK: - The items

/// Which half of the open island the pointer is in.
enum ShelfZone: String, Sendable { case ask, shelf }

/// One word for each incoming item of a drop (`shelfAdd`).
enum ShelfAddResult: String, Sendable { case added, duplicate, full, invalid }

/// A parked file. `link` is the base64 of a security-scoped bookmark (a link) and is nil for a copy, which lives in `shelf/<id>/<name>`.
struct ShelfItem: Equatable, Sendable {
    var id: String
    var name: String
    var size: Int64
    var folder: Bool
    var copy: Bool
    var link: String?
    var addedAt: Int64

    /// The item as the contract's JSON (what `shelfAdd` takes and what shelf.json holds).
    var json: ShelfJSON {
        var o: [String: ShelfJSON] = ["id": .text(id), "name": .text(name), "size": .number(Double(size)), "folder": .bool(folder), "copy": .bool(copy), "addedAt": .number(Double(addedAt))]
        if let link { o["link"] = .text(link) }
        return .object(o)
    }
}

enum ShelfRules {
    static let max = 30
    static let nameMax = 255
    static let linkMax = 8192
    /// The largest size and time every language holds exactly: 2^53 - 1.
    static let numberMax: Double = 9007199254740991

    // MARK: zoneAt

    /// `x` is the pointer's distance from the island's left edge, `width` the island's, both in points. The centre line belongs to Ask, the drop that exists today. Outside the island, or
    /// not a finite number within `numberMax`: nil (no half).
    static func zoneAt(x: Double, width: Double) -> ShelfZone? {
        guard x.isFinite, width.isFinite, Swift.abs(x) <= numberMax, Swift.abs(width) <= numberMax else { return nil }
        guard width > 0, x >= 0, x <= width else { return nil }
        return x * 2 <= width ? .ask : .shelf
    }

    /// The fixture's form: either side may be missing, text, `null` or a boolean, which are refused.
    static func zoneAt(x: ShelfJSON?, width: ShelfJSON?) -> ShelfZone? {
        guard case .number(let a)? = x, case .number(let b)? = width else { return nil }
        return zoneAt(x: a, width: b)
    }

    // MARK: Names, ids and links

    private static let reservedNames: Set<String> = {
        var s: Set<String> = ["CON", "PRN", "AUX", "NUL", "COM\u{B9}", "COM\u{B2}", "COM\u{B3}", "LPT\u{B9}", "LPT\u{B2}", "LPT\u{B3}"]
        for n in 1...9 { s.insert("COM\(n)"); s.insert("LPT\(n)") }
        return s
    }()

    /// A Windows device name as the stem of `s` (the part before the first dot, trailing spaces trimmed), ASCII case-insensitively.
    static func reserved(_ s: String) -> Bool {
        var stem = Array(s.unicodeScalars.prefix { $0 != "." })
        while stem.last == " " { stem.removeLast() }
        var up = String.UnicodeScalarView()
        for c in stem { up.append(c.value >= 0x61 && c.value <= 0x7A ? Unicode.Scalar(c.value - 32)! : c) }
        return reservedNames.contains(String(up))
    }

    private static func isIdScalar(_ c: Unicode.Scalar) -> Bool {
        (c.value >= 0x30 && c.value <= 0x39) || (c.value >= 0x41 && c.value <= 0x5A) || (c.value >= 0x61 && c.value <= 0x7A) || c == "_" || c == "-"
    }

    /// 1 to 255 code points; no control, format, separator or lone surrogate; no `/` or `\`; not only dots; not ending in a dot or a space; not a device name.
    static func nameOK(_ name: String, lone: Bool) -> Bool {
        let scalars = Array(name.unicodeScalars)
        guard !lone, (1...nameMax).contains(scalars.count) else { return false }
        for c in scalars {
            switch c.properties.generalCategory {
            case .control, .format, .surrogate, .lineSeparator, .paragraphSeparator: return false
            default: break
            }
            if c == "/" || c == "\\" { return false }
        }
        if scalars.allSatisfy({ $0 == "." }) || scalars.last == "." || scalars.last == " " { return false }
        return !reserved(name)
    }

    /// 1 to 8192 code points, no C0, DEL or C1 control, no lone surrogate. A link is never shown, so the name rules do not apply.
    static func linkOK(_ link: String, lone: Bool) -> Bool {
        let scalars = Array(link.unicodeScalars)
        guard !lone, (1...linkMax).contains(scalars.count) else { return false }
        return !scalars.contains { $0.value < 0x20 || ($0.value >= 0x7F && $0.value <= 0x9F) }
    }

    /// A whole number from 0 to `numberMax` (`5` and `5.0` are the same number), else 0.
    static func whole(_ v: ShelfJSON?) -> Int64 {
        guard case .number(let d)? = v, d.isFinite, d == d.rounded(.towardZero), d >= 0, d <= numberMax else { return 0 }
        return Int64(d)
    }

    // MARK: shelfClean

    /// One stored item to its clean form, or nil when it cannot be kept.
    static func cleanItem(_ raw: ShelfJSON) -> ShelfItem? {
        guard case .object(let o) = raw else { return nil }
        guard case .string(let id, let idLone)? = o["id"], !idLone, (1...64).contains(id.unicodeScalars.count), id.unicodeScalars.allSatisfy(isIdScalar), !reserved(id) else { return nil }
        guard case .string(let name, let nameLone)? = o["name"], nameOK(name, lone: nameLone) else { return nil }
        let copy = o["copy"] == .bool(true), folder = o["folder"] == .bool(true)
        if copy && folder { return nil }   // a folder is only ever a link
        var link: String?
        if !copy {
            guard case .string(let l, let lLone)? = o["link"], linkOK(l, lone: lLone) else { return nil }
            link = l
        }
        return ShelfItem(id: id, name: name, size: whole(o["size"]), folder: folder, copy: copy, link: link, addedAt: whole(o["addedAt"]))
    }

    /// A link as its code points: Swift's `String` equality treats a precomposed and a decomposed é as one string, the contract does not.
    static func linkKey(_ link: String) -> [UInt32] { link.unicodeScalars.map(\.value) }

    /// Newest first (stable: equal times keep the file's order), then the first of each id (ASCII case-insensitively) and of each link (exactly), then the first 30. One pass in sorted
    /// order: an item skipped for a repeated link reserves nothing, so its id stays free.
    static func tidy(_ items: [ShelfItem]) -> [ShelfItem] {
        let sorted = items.enumerated().sorted { $0.element.addedAt != $1.element.addedAt ? $0.element.addedAt > $1.element.addedAt : $0.offset < $1.offset }.map(\.element)
        var ids = Set<String>(), links = Set<[UInt32]>(), out: [ShelfItem] = []
        for it in sorted {
            if ids.contains(it.id.lowercased()) || (it.link.map { links.contains(linkKey($0)) } ?? false) { continue }
            ids.insert(it.id.lowercased())
            if let l = it.link { links.insert(linkKey(l)) }
            out.append(it)
        }
        return Array(out.prefix(max))
    }

    /// The parsed content of shelf.json to the items the shelf holds. Anything that is not `{"items": [ ... ]}` is an empty shelf. Never traps.
    static func clean(_ raw: ShelfJSON?) -> [ShelfItem] {
        guard case .object(let o)? = raw, case .array(let list)? = o["items"] else { return [] }
        return tidy(list.compactMap(cleanItem))
    }

    // MARK: shelfAdd

    /// Files dropped on the Shelf half. `items` is the shelf as stored (cleaned first), `incoming` the drop's items in the order the app wants them shown. One word per incoming item;
    /// nothing already on the shelf is ever removed.
    static func add(items: ShelfJSON?, incoming: ShelfJSON?) -> (items: [ShelfItem], results: [ShelfAddResult]) {
        var listed: [ShelfJSON] = []
        if case .array(let l)? = items { listed = l }
        let current = clean(.object(["items": .array(listed)]))
        var ids = Set(current.map { $0.id.lowercased() }), links = Set(current.compactMap { $0.link.map(linkKey) })
        var accepted: [ShelfItem] = [], results: [ShelfAddResult] = []
        var list: [ShelfJSON] = []
        if case .array(let l)? = incoming { list = l }
        for raw in list {
            guard let it = cleanItem(raw) else { results.append(.invalid); continue }
            if ids.contains(it.id.lowercased()) || (it.link.map { links.contains(linkKey($0)) } ?? false) {
                results.append(.duplicate)
            } else if current.count + accepted.count >= max {
                results.append(.full)
            } else {
                accepted.append(it)
                ids.insert(it.id.lowercased())
                if let l = it.link { links.insert(linkKey(l)) }
                results.append(.added)
            }
        }
        return (tidy(accepted + current), results)
    }

    /// The typed form the app uses: the stored shelf and the drop's items.
    static func add(_ items: [ShelfItem], _ incoming: [ShelfItem]) -> (items: [ShelfItem], results: [ShelfAddResult]) {
        add(items: .array(items.map(\.json)), incoming: .array(incoming.map(\.json)))
    }

    // MARK: Reading and writing the file

    /// The bytes of shelf.json to the items it holds. Unreadable bytes are an empty shelf.
    static func read(_ bytes: [UInt8]) -> [ShelfItem] { clean(ShelfJSONParser.parse(bytes)) }

    /// Whether reading `bytes` keeps everything in them: strict JSON, an object with a list of items, and no item dropped or removed as a duplicate. When it does not, an app that is
    /// about to write a new shelf.json keeps a copy of the old one first (docs/SHELF-CONTRACT.md).
    static func isLossless(_ bytes: [UInt8]) -> Bool {
        guard case .object(let o)? = ShelfJSONParser.parse(bytes), case .array(let list)? = o["items"] else { return false }
        return clean(.object(o)).count == list.count
    }

    /// shelf.json's bytes: `{"version": 1, "items": [ ... ]}`, keys sorted so the file is stable.
    static func encode(_ items: [ShelfItem]) -> Data {
        let objs: [[String: Any]] = items.map { it in
            var d: [String: Any] = ["id": it.id, "name": it.name, "size": it.size, "folder": it.folder, "copy": it.copy, "addedAt": it.addedAt]
            if let l = it.link { d["link"] = l }
            return d
        }
        return (try? JSONSerialization.data(withJSONObject: ["version": 1, "items": objs] as [String: Any], options: [.sortedKeys, .withoutEscapingSlashes])) ?? Data("{\"items\":[],\"version\":1}".utf8)
    }
}
