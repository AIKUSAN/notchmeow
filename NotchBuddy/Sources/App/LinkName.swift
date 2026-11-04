import Foundation

// The name a received file is saved under (sub-project G2, docs/LINK-CONTRACT.md "File names"): `sanitize` gives the saved name or a reason, `uniqueName` the name to use when it is taken.
// A port of `sanitize_name` and `unique_name` of tests/fixtures/link/reference.py, replayed against filename-cases.json by scripts/test-link-name.sh. Foundation only.
//
// Everything here works on Unicode scalars, never on Characters: a Swift `Character` is a grapheme cluster and a Swift `String ==` is canonical equivalence, and neither is what the contract
// counts. The two Unicode tables that decide a name (`invisibleRanges` and `spaceRun`) are written out by hand, as in the reference, so they do not move with the system's Unicode version.
// The categories (Cc, Cf, Cs, Zl, Zp, Zs) and NFC/NFKC come from the system, which the contract allows and tells a port to re-check when the Unicode version changes.

enum LinkName {
    static let bytesMax = 200          // UTF-8 bytes of a saved name
    static let extBytesMax = 16        // the part after the last dot is an extension only up to this long
    static let collisionMax = 9999

    enum Result: Equatable, Sendable {
        case ok(String)
        case reject(String)    // "not-text", "invisible", "separator" or "empty"
    }

    /// Every Default_Ignorable code point (DerivedCoreProperties.txt) and U+2800, as in `INVISIBLE_RANGES`.
    static let invisibleRanges: [ClosedRange<UInt32>] = [
        0x00AD...0x00AD, 0x034F...0x034F, 0x061C...0x061C, 0x115F...0x1160, 0x17B4...0x17B5, 0x180B...0x180F, 0x200B...0x200F, 0x202A...0x202E,
        0x2060...0x206F, 0x2800...0x2800, 0x3164...0x3164, 0xFE00...0xFE0F, 0xFEFF...0xFEFF, 0xFFA0...0xFFA0, 0xFFF0...0xFFF8, 0x1BCA0...0x1BCA3,
        0x1D173...0x1D17A, 0xE0000...0xE0FFF,
    ]

    static func isInvisible(_ s: Unicode.Scalar) -> Bool { invisibleRanges.contains { $0.contains(s.value) } }

    /// Cc, Cf, Cs, Zl and Zp: controls, format characters (bidi controls, zero-width, BOM, soft hyphen), surrogates, line and paragraph separators.
    static func isBadCategory(_ s: Unicode.Scalar) -> Bool {
        switch s.properties.generalCategory {
        case .control, .format, .surrogate, .lineSeparator, .paragraphSeparator: return true
        default: return false
        }
    }

    static func isSpace(_ s: Unicode.Scalar) -> Bool { s == " " || s.properties.generalCategory == .spaceSeparator }

    /// `NAME_SPACE_RUN`: U+0009 to U+000D, U+0020, U+0085, U+00A0, U+1680, U+2000 to U+200A, U+2028, U+2029, U+202F, U+205F, U+3000.
    static func inSpaceRun(_ v: UInt32) -> Bool {
        (0x09...0x0D).contains(v) || v == 0x20 || v == 0x85 || v == 0xA0 || v == 0x1680 || (0x2000...0x200A).contains(v) || v == 0x2028 || v == 0x2029 || v == 0x202F || v == 0x205F || v == 0x3000
    }

    static func collapseSpaces(_ scalars: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var out: [Unicode.Scalar] = []
        var inRun = false
        for s in scalars {
            if inSpaceRun(s.value) {
                if !inRun { out.append(" ") }
                inRun = true
            } else {
                out.append(s)
                inRun = false
            }
        }
        return out
    }

    static func scalars(_ s: String) -> [Unicode.Scalar] { Array(s.unicodeScalars) }
    static func string(_ s: [Unicode.Scalar]) -> String { var v = String.UnicodeScalarView(); v.append(contentsOf: s); return String(v) }
    static func byteCount(_ s: [Unicode.Scalar]) -> Int { s.reduce(0) { $0 + UTF8.width($1) } }
    static func nfc(_ s: [Unicode.Scalar]) -> [Unicode.Scalar] { scalars(string(s).precomposedStringWithCanonicalMapping) }
    static func nfkc(_ s: [Unicode.Scalar]) -> [Unicode.Scalar] { scalars(string(s).precomposedStringWithCompatibilityMapping) }

    /// Spaces off the start; spaces and dots off the end.
    static func trim(_ s: [Unicode.Scalar]) -> [Unicode.Scalar] {
        var a = 0, b = s.count
        while a < b, isSpace(s[a]) { a += 1 }
        while b > a, s[b - 1] == "." || isSpace(s[b - 1]) { b -= 1 }
        return Array(s[a..<b])
    }

    static let reserved: Set<[UInt8]> = {
        var names = ["CON", "PRN", "AUX", "NUL", "CONIN$", "CONOUT$", "COM\u{B9}", "COM\u{B2}", "COM\u{B3}", "LPT\u{B9}", "LPT\u{B2}", "LPT\u{B3}"]
        for n in 0...9 { names.append("COM\(n)"); names.append("LPT\(n)") }
        return Set(names.map { Array($0.utf8) })
    }()

    /// A Windows device name: the part before the first dot, spaces off its end, ASCII letters in capitals.
    static func isReserved(_ s: [Unicode.Scalar]) -> Bool {
        var head = Array(s.prefix { $0 != "." })
        while head.last == " " { head.removeLast() }
        let bytes = head.map { $0.value >= 97 && $0.value <= 122 ? Unicode.Scalar($0.value - 32)! : $0 }
        return reserved.contains(Array(string(bytes).utf8))
    }

    static func splitExt(_ name: [Unicode.Scalar]) -> (stem: [Unicode.Scalar], ext: [Unicode.Scalar]) {
        if let i = name.lastIndex(of: "."), i > 0, byteCount(Array(name[i...])) <= extBytesMax { return (Array(name[..<i]), Array(name[i...])) }
        return (name, [])
    }

    /// `name` cut to `bytesMax` bytes at a code point, keeping an extension of up to `extBytesMax` bytes; the spaces and dots the cut leaves at the end go.
    static func cut(_ name: [Unicode.Scalar]) -> [Unicode.Scalar] {
        if byteCount(name) <= bytesMax { return name }
        let (stem, ext) = splitExt(name)
        let room = bytesMax - byteCount(ext)
        var out: [Unicode.Scalar] = [], used = 0
        for s in stem {
            if used + UTF8.width(s) > room { break }
            out.append(s)
            used += UTF8.width(s)
        }
        return trim(out) + ext
    }

    static func sanitize(_ raw: String) -> Result {
        let nfcForm = collapseSpaces(nfc(scalars(raw))), nfkcForm = collapseSpaces(nfkc(scalars(raw)))
        if (nfcForm + nfkcForm).contains(where: { isBadCategory($0) || isInvisible($0) }) { return .reject("invisible") }
        if (nfcForm + nfkcForm).contains(where: { $0 == "/" || $0 == "\\" }) { return .reject("separator") }
        if trim(nfcForm).isEmpty || trim(nfkcForm).isEmpty { return .reject("empty") }
        let illegal = Set(Array("<>:\"|?*".unicodeScalars))
        func rewrite(_ s: [Unicode.Scalar]) -> [Unicode.Scalar] { trim(s.map { illegal.contains($0) ? "_" : $0 }) }
        var name = rewrite(nfcForm)
        let probe = rewrite(nfkcForm)
        if name.isEmpty { return .reject("empty") }
        if isReserved(name) || isReserved(probe) { name = ["_"] + name }
        name = cut(name)
        // The cut can leave a device name too ("CON" and spaces, the spaces cut away): the same test runs again on the cut name, NFC and NFKC.
        if isReserved(name) || isReserved(trim(nfkc(name))) { name = cut(["_"] + name) }
        if name.first == "." { name = cut(["_"] + name) }
        if trim(name).isEmpty || trim(nfkc(name)).isEmpty { return .reject("empty") }
        return .ok(string(name))
    }

    /// The comparison key of a name: NFC, case-folded (the usual volumes of both systems compare that way).
    static func key(_ name: String) -> String { name.precomposedStringWithCanonicalMapping.folding(options: .caseInsensitive, locale: nil) }

    /// `name` itself when no taken name equals it, else `stem (n)ext` for the smallest n from 1 that is free; nil after 9999 tries. The caller still creates the file exclusively
    /// (`O_EXCL`) and asks again on "already exists": the volume decides which names are the same file.
    static func uniqueName(_ name: String, taken: [String]) -> String? {
        let used = Set(taken.map(key))
        if !used.contains(key(name)) { return name }
        let (stem, ext) = splitExt(scalars(name))
        for n in 1...collisionMax {
            let cand = "\(string(stem)) (\(n))\(string(ext))"
            if !used.contains(key(cand)) { return cand }
        }
        return nil
    }
}
