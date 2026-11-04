import Foundation

// The companion's text rules (F3a-mac): the invisible set, code points, civil days, and the secret and word rules that "Right now" reads. A port of
// shared/companion-core.js (the specification; docs/COMPANION-CONTRACT.md, "For ports"), replayed against tests/fixtures/companion/ by
// scripts/test-companion-prompt.sh. Pure Foundation: no clock, no files, no network.
//
// Porting rules: a code point is a Unicode scalar; JS `\d` is ASCII; text order and equality are by code units (ProjectsRegistry.same). No rule is a
// backtracking regex: every search is a scan over the scalars with a bounded look-ahead, so a 100,000-character text is handled in linear time.
enum CompanionText {
    /// The characters a name or a cloud line folds to a space: tab, line feed, vertical tab, form feed, carriage return and the two separators.
    static let lineBreaks: Set<UInt32> = [0x09, 0x0A, 0x0B, 0x0C, 0x0D, 0x2028, 0x2029]

    /// A text as its scalars: the unit every rule below works on.
    typealias Scalars = [Unicode.Scalar]

    static let maxSafeInteger = 9_007_199_254_740_991

    // MARK: - Text and numbers

    /// The contract's invisible set (C0 and C1 controls, the format and bidi marks, the variation selectors, the tag characters). Removed with no space.
    static func isInvisible(_ u: Unicode.Scalar) -> Bool {
        switch u.value {
        case 0x00...0x1F, 0x7F...0x9F, 0xAD, 0x34F, 0x61C, 0x180E, 0x200B...0x200F, 0x2028...0x202E, 0x2060...0x206F, 0x3164,
             0xFE00...0xFE0F, 0xFEFF, 0xFFA0, 0xFFF9...0xFFFB, 0xE0000...0xE007F, 0xE0100...0xE01EF:
            return true
        default:
            return false
        }
    }

    /// The text with the invisible characters removed and nothing put in their place.
    static func clean(_ s: String) -> String {
        text(s.unicodeScalars.filter { !isInvisible($0) })
    }

    /// The text with each line break (see `lineBreaks`) folded to one space.
    static func foldBreaks(_ s: String) -> String {
        text(s.unicodeScalars.map { lineBreaks.contains($0.value) ? (" " as Unicode.Scalar) : $0 })
    }

    /// The number of code points.
    static func codePoints(_ s: String) -> Int {
        s.unicodeScalars.count
    }

    /// `s` kept whole when it has `max` code points or fewer; otherwise its first `max - 1` code points and `…`.
    static func cutTo(_ s: String, _ max: Int) -> String {
        ProjectsRules.cutTo(s, max)
    }

    /// The text after the last `/` or `\` of a word (the word itself when it has none).
    static func lastPart(_ word: String) -> String {
        text(lastPartOf(sc(word)))
    }

    /// A JSON number as a whole number inside JavaScript's safe range; nil for anything else (a boolean, text, a fraction, 1e300).
    static func wholeNumber(_ v: Any?) -> Int? {
        guard let d = ProjectsRegistry.numberOf(v), d == d.rounded(.towardZero), abs(d) <= Double(maxSafeInteger) else { return nil }
        return Int(d)
    }

    /// True for a whole number inside JavaScript's safe range.
    static func isSafe(_ n: Int) -> Bool {
        abs(n) <= maxSafeInteger
    }

    /// True for a valid civil day written `YYYY-MM-DD` (2026-02-30 is not one). Anything that is not a String is not a day.
    static func isDay(_ v: Any?) -> Bool {
        guard let s = v as? String else { return false }
        let u = sc(s)
        guard u.count == 10, u[4] == "-", u[7] == "-" else { return false }
        func number(_ r: Range<Int>) -> Int? {
            var n = 0
            for i in r {
                guard isDigit(u[i]) else { return nil }
                n = n * 10 + Int(u[i].value - 48)
            }
            return n
        }
        guard let y = number(0..<4), let m = number(5..<7), let d = number(8..<10), (1...12).contains(m) else { return false }
        let leap = (y % 4 == 0 && y % 100 != 0) || y % 400 == 0
        let days = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1]
        return d >= 1 && d <= days
    }

    // MARK: - Secrets and words

    /// True when the text holds a secret's shape: a password word, a key or token, a card number (Luhn), or a long random word. A word is judged
    /// whole, and a web address piece by piece (see `longRandomWord`).
    static func isSecret(_ t: String) -> Bool {
        isSecret(sc(t))
    }

    /// A word as the companion may show it: `""` when the part it shows, or (for a path) any segment of it, has a secret's shape; a word with a separator
    /// keeps its last part, with its `?` or `#` query cut first.
    static func shownWord(_ w: String) -> String {
        text(shown(sc(w)))
    }

    static let passwordWord = lit("password")
    static let bearerWord = lit("bearer ")

    static func isSecret(_ u: Scalars) -> Bool {
        holds(u, passwordWord, run: { _ in true }, min: 0, fold: true)
            || secretShape(u)
            || holds(u, bearerWord, run: { isAlnum($0) || "._~+/=-".unicodeScalars.contains($0) }, min: 20, fold: true)
            || cardNumber(u)
            || wordsOf(u).contains { longRandomWord($0) }
    }

    static func shown(_ w: Scalars) -> Scalars {
        guard w.contains(where: isSeparator) else { return isSecret(w) ? [] : w }
        let startsPath = isPathStart(w)
        if !startsPath && isSecret(w) { return [] }
        let base = Array(w.prefix { $0 != "?" && $0 != "#" })
        let v = lastPartOf(base)
        if isSecret(v) { return [] }
        if startsPath && split(base, isSeparator).contains(where: { isSecret($0) }) { return [] }
        return v
    }

    /// `/`, `~`, `X:\`, `X:/`, `http://` and `https://` start a path or an address.
    static func isPathStart(_ w: Scalars) -> Bool {
        guard let first = w.first else { return false }
        if first == "/" || first == "~" { return true }
        if w.count >= 3, isASCIILetter(first), w[1] == ":", w[2] == "\\" || w[2] == "/" { return true }
        return startsWith(w, "http://") || startsWith(w, "https://")
    }

    // MARK: - Card numbers

    /// True when a digit run, read with its single spaces and hyphens, holds a window of 13 to 19 digits that passes Luhn. An ISO date is a break in the run.
    static func cardNumber(_ u: Scalars) -> Bool {
        let t = dateBreaks(u)
        var i = 0
        while i < t.count {
            guard isDigit(t[i]) else {
                i += 1
                continue
            }
            var digits: [UInt8] = [UInt8(t[i].value - 48)]
            var j = i + 1
            while j < t.count {
                if isDigit(t[j]) {
                    digits.append(UInt8(t[j].value - 48))
                    j += 1
                } else if (t[j] == " " || t[j] == "-"), j + 1 < t.count, isDigit(t[j + 1]) {
                    digits.append(UInt8(t[j + 1].value - 48))
                    j += 2
                } else {
                    break
                }
            }
            if hasLuhnWindow(digits) { return true }
            i = j
        }
        return false
    }

    /// Every `dddd-dd-dd` becomes one dot, left to right, so no digit run crosses a date.
    static func dateBreaks(_ u: Scalars) -> Scalars {
        var out: Scalars = []
        var i = 0
        while i < u.count {
            if i + 10 <= u.count, isISODate(u, i) {
                out.append(".")
                i += 10
            } else {
                out.append(u[i])
                i += 1
            }
        }
        return out
    }

    static func isISODate(_ u: Scalars, _ at: Int) -> Bool {
        let shape = "dddd-dd-dd"
        for (k, c) in shape.unicodeScalars.enumerated() {
            let got = u[at + k]
            if c == "d" ? !isDigit(got) : got != c { return false }
        }
        return true
    }

    /// True when a run of digits holds a window of 13 to 19 digits that passes Luhn. Each window is judged in O(1) from running totals: counting from the
    /// window's right end, every second digit is doubled, so a digit is doubled when its index has the window end's parity.
    static func hasLuhnWindow(_ digits: [UInt8]) -> Bool {
        let n = digits.count
        guard n >= 13 else { return false }
        let m = n + 1
        // plain[p * m + k] and doubled[p * m + k]: the totals of the digits of index parity p that come before k.
        var plain = [Int](repeating: 0, count: 2 * m)
        var doubled = [Int](repeating: 0, count: 2 * m)
        for k in 0..<n {
            let x = Int(digits[k])
            let y = 2 * x > 9 ? 2 * x - 9 : 2 * x
            for p in 0..<2 {
                plain[p * m + k + 1] = plain[p * m + k]
                doubled[p * m + k + 1] = doubled[p * m + k]
            }
            plain[(k % 2) * m + k + 1] += x
            doubled[(k % 2) * m + k + 1] += y
        }
        for end in 13...n {
            for len in 13...min(19, end) {
                let start = end - len
                let same = end % 2
                let sum = (doubled[same * m + end] - doubled[same * m + start]) + (plain[(1 - same) * m + end] - plain[(1 - same) * m + start])
                if sum % 10 == 0 { return true }
            }
        }
        return false
    }

    // MARK: - Long random words, web addresses and kebab names

    /// A word the long-random rule judges: a web address is not judged whole; it is secret with userinfo, and otherwise each piece between
    /// `/ ? & = # : @` is judged by the shape rules and the long-random shape.
    static func longRandomWord(_ w: Scalars) -> Bool {
        guard isUrlWord(w) else { return longRandomShape(w) }
        if hasUserinfo(w) { return true }
        return split(w, { "/?&=#:@".unicodeScalars.contains($0) }).contains { secretShape($0) || longRandomShape($0) }
    }

    /// 24 or more characters from letters, digits and `_ - + / = . :`, with a letter and a digit, and not exempt (an ISO date-time or a kebab name).
    static func longRandomShape(_ w: Scalars) -> Bool {
        guard w.count >= 24, w.allSatisfy({ isAlnum($0) || "_-+/=.:".unicodeScalars.contains($0) }) else { return false }
        return w.contains(where: isASCIILetter) && w.contains(where: isDigit) && !isISODateTime(w) && !isKebabName(w)
    }

    /// A web address: it contains `://` or starts `www.`.
    static func isUrlWord(_ w: Scalars) -> Bool {
        indexOf(w, sc("://")) != nil || startsWith(w, "www.")
    }

    /// Userinfo (`user:pass@`) after the scheme: the authority ends at the first `/ ? #`, and it holds a colon before its last `@`.
    static func hasUserinfo(_ w: Scalars) -> Bool {
        guard let i = indexOf(w, sc("://")) else { return false }
        let authority = Array(w[(i + 3)...].prefix { $0 != "/" && $0 != "?" && $0 != "#" })
        guard let at = authority.lastIndex(of: "@") else { return false }
        return authority[..<at].contains(":")
    }

    /// An ISO date-time: `YYYY-MM-DDTHH:MM`, then optionally `:SS` and `.digits`, then optionally `Z` or a `±HH[:]MM` offset, and nothing after.
    static func isISODateTime(_ u: Scalars) -> Bool {
        var p = 0
        func digits(_ n: Int) -> Bool {
            guard p + n <= u.count, u[p..<(p + n)].allSatisfy(isDigit) else { return false }
            p += n
            return true
        }
        func eat(_ c: Unicode.Scalar) -> Bool {
            guard p < u.count, u[p] == c else { return false }
            p += 1
            return true
        }
        guard digits(4), eat("-"), digits(2), eat("-"), digits(2), eat("T"), digits(2), eat(":"), digits(2) else { return false }
        if eat(":") {
            guard digits(2) else { return false }
            if eat(".") {
                var n = 0
                while p < u.count, isDigit(u[p]) {
                    p += 1
                    n += 1
                }
                guard n > 0 else { return false }
            }
        }
        if p == u.count { return true }
        if u[p] == "Z" { return p + 1 == u.count }
        guard u[p] == "+" || u[p] == "-" else { return false }
        p += 1
        guard digits(2) else { return false }
        _ = eat(":")
        return digits(2) && p == u.count
    }

    /// Three or more parts of 1 to 12 characters, split on `-` or `_`; every part is lower-case letters, except at most one, which is a number or a short
    /// version tag such as `v2`.
    static func isKebabName(_ w: Scalars) -> Bool {
        let parts = split(w, { $0 == "-" || $0 == "_" })
        guard parts.count >= 3, parts.allSatisfy({ utf16Length($0) >= 1 && utf16Length($0) <= 12 }) else { return false }
        let odd = parts.filter { !$0.allSatisfy(isLowerLetter) }
        return odd.isEmpty || (odd.count == 1 && isVersionTag(odd[0]))
    }

    /// `^v?\d{1,4}$`.
    static func isVersionTag(_ p: Scalars) -> Bool {
        let digits = p.first == "v" ? p.dropFirst() : p[...]
        return (1...4).contains(digits.count) && digits.allSatisfy(isDigit)
    }

    // MARK: - Words

    /// The words of a text: split on spaces, the punctuation at both ends taken off, the empty ones dropped.
    static func wordsOf(_ u: Scalars) -> [Scalars] {
        split(u, { $0 == " " }).map(trimPunct).filter { !$0.isEmpty }
    }

    /// The punctuation a word loses at each end.
    static let punctuation = Set(".,;:!?()[]{}\"'".unicodeScalars)

    /// A word with its punctuation at both ends taken off, by two indices.
    static func trimPunct(_ w: Scalars) -> Scalars {
        var a = 0, b = w.count
        while a < b, punctuation.contains(w[a]) { a += 1 }
        while b > a, punctuation.contains(w[b - 1]) { b -= 1 }
        return Array(w[a..<b])
    }

    // MARK: - Shapes of keys and tokens

    /// The shapes of a key, a token or a PEM header (the core's SECRET_SHAPES). Each is a fixed prefix, then a run of characters; the prefixes are built once.
    static func secretShape(_ u: Scalars) -> Bool {
        holds(u, skPrefix, run: { isAlnum($0) || $0 == "_" || $0 == "-" }, min: 16)
            || holds(u, ghPrefix, run: isAlnum, min: 20)
            || holds(u, githubPatPrefix, run: { isAlnum($0) || $0 == "_" }, min: 20)
            || holds(u, akiaPrefix, run: { isAlnum($0) && !isLowerLetter($0) }, min: 16)
            || holds(u, xoxPrefix, run: { isAlnum($0) || $0 == "-" }, min: 10)
            || holds(u, aizaPrefix, run: { isAlnum($0) || $0 == "_" || $0 == "-" }, min: 30)
            || holds(u, hfPrefix, run: isAlnum, min: 20)
            || holds(u, ya29Prefix, run: { isAlnum($0) || $0 == "_" || $0 == "-" }, min: 16)
            || holds(u, eyjPrefix, run: { isAlnum($0) || $0 == "_" || $0 == "-" }, min: 10)
            || holds(u, pemPrefix, run: { _ in true }, min: 0)
    }

    static let skPrefix = lit("sk") + [oneOf("-_")]
    static let ghPrefix = lit("gh") + [oneOf("pousr")] + lit("_")
    static let githubPatPrefix = lit("github_pat_")
    static let akiaPrefix = lit("AKIA")
    static let xoxPrefix = lit("xox") + [oneOf("abprs")] + lit("-")
    static let aizaPrefix = lit("AIza")
    static let hfPrefix = lit("hf_")
    static let ya29Prefix = lit("ya29.")
    static let eyjPrefix = lit("eyJ")
    static let pemPrefix = lit("-----BEGIN ")

    /// True when the text holds, at some place, the prefix (each step one of its scalars, lower-case compared when `fold`) and then at least `min`
    /// scalars of `run`. The look-ahead is `min`, so the scan is linear.
    static func holds(_ u: Scalars, _ prefix: [[UInt8]], run: (Unicode.Scalar) -> Bool, min: Int, fold: Bool = false) -> Bool {
        let k = prefix.count
        guard u.count >= k + min else { return false }
        for i in 0...(u.count - k - min) {
            var matched = true
            for s in 0..<k {
                guard let b = asciiByte(u[i + s], fold: fold), prefix[s].contains(b) else {
                    matched = false
                    break
                }
            }
            if matched, (0..<min).allSatisfy({ run(u[i + k + $0]) }) { return true }
        }
        return false
    }

    /// A scalar as one ASCII byte (lower-cased first when `fold`); nil for anything that is not ASCII, so it matches no prefix step.
    static func asciiByte(_ u: Unicode.Scalar, fold: Bool) -> UInt8? {
        let v = fold ? asciiLower(u) : u
        return v.value < 128 ? UInt8(v.value) : nil
    }

    /// One step per character of a literal (each step is that character's byte).
    static func lit(_ s: String) -> [[UInt8]] {
        s.utf8.map { [$0] }
    }

    /// One step that accepts any of the characters of `s`.
    static func oneOf(_ s: String) -> [UInt8] {
        Array(s.utf8)
    }

    // MARK: - Scalar helpers

    static func sc(_ s: String) -> Scalars {
        Array(s.unicodeScalars)
    }

    static func text<S: Sequence>(_ scalars: S) -> String where S.Element == Unicode.Scalar {
        String(String.UnicodeScalarView(scalars))
    }

    /// The pieces between the scalars `isCut` picks, empty pieces kept (a JavaScript split with a pattern).
    static func split(_ u: Scalars, _ isCut: (Unicode.Scalar) -> Bool) -> [Scalars] {
        var out: [Scalars] = [[]]
        for c in u {
            if isCut(c) { out.append([]) } else { out[out.count - 1].append(c) }
        }
        return out
    }

    static func lastPartOf(_ u: Scalars) -> Scalars {
        guard let i = u.lastIndex(where: isSeparator) else { return u }
        return Array(u[(i + 1)...])
    }

    static func indexOf(_ hay: Scalars, _ needle: Scalars) -> Int? {
        guard needle.count <= hay.count else { return nil }
        for i in 0...(hay.count - needle.count) where hay[i..<(i + needle.count)].elementsEqual(needle) {
            return i
        }
        return nil
    }

    static func startsWith(_ u: Scalars, _ prefix: String) -> Bool {
        let p = sc(prefix)
        return u.count >= p.count && u[0..<p.count].elementsEqual(p)
    }

    static func utf16Length(_ u: Scalars) -> Int {
        u.reduce(0) { $0 + ($1.value > 0xFFFF ? 2 : 1) }
    }

    static func isSeparator(_ u: Unicode.Scalar) -> Bool {
        u == "/" || u == "\\"
    }

    static func isDigit(_ u: Unicode.Scalar) -> Bool {
        (48...57).contains(u.value)
    }

    static func isASCIILetter(_ u: Unicode.Scalar) -> Bool {
        (65...90).contains(u.value) || (97...122).contains(u.value)
    }

    static func isLowerLetter(_ u: Unicode.Scalar) -> Bool {
        (97...122).contains(u.value)
    }

    static func isAlnum(_ u: Unicode.Scalar) -> Bool {
        isDigit(u) || isASCIILetter(u)
    }

    static func asciiLower(_ u: Unicode.Scalar) -> Unicode.Scalar {
        (65...90).contains(u.value) ? Unicode.Scalar(u.value + 32)! : u
    }
}
