import Foundation

// The file-name rules of the link (docs/LINK-CONTRACT.md "File names"): filename-cases.json replayed against LinkName.swift, and the invariants the reference fuzzes.
// Run it through scripts/test-link-name.sh.

@main
enum LinkNameTests {
    /// A tiny seeded generator, so a failing fuzz can be replayed.
    struct Lcg { var s: UInt64; mutating func next(_ n: Int) -> Int { s = s &* 6364136223846793005 &+ 1442695040888963407; return Int((s >> 33) % UInt64(n)) } }

    /// A raw name as the fixture holds it: text, or anything else (null, a number, a boolean, a list, an object), which is not text.
    enum Raw: Decodable { case text(String), other
        init(from d: Decoder) throws { if let s = try? d.singleValueContainer().decode(String.self) { self = .text(s) } else { self = .other } }
    }
    struct Case: Decodable { let name: String; let raw: Raw; let out: [String: String] }
    struct Numbered: Decodable { let stem: String; let ext: String; let from: Int; let to: Int }
    struct Unique: Decodable { let name: String; let wanted: String; let taken: [String]; let takenNumbered: Numbered?; let out: String? }
    struct Fixture: Decodable { let bytesMax: Int; let extBytesMax: Int; let collisionMax: Int; let cases: [Case]; let uniqueCases: [Unique] }

    static func sanitize(_ raw: Raw) -> LinkName.Result {
        guard case .text(let s) = raw else { return .reject("not-text") }
        return LinkName.sanitize(s)
    }

    @MainActor static func main() {
        // JSONSerialization drops a byte order mark at the start of a string value, which the contract's "a byte order mark at the start" case needs: this file is read with JSONDecoder.
        let f = try! JSONDecoder().decode(Fixture.self, from: Data(contentsOf: CT.fixtureURL("filename-cases.json", dir: "link")))
        CT.section("the constants")
        CT.check("200 bytes, an extension of 16, 9999 collisions", [f.bytesMax, f.extBytesMax, f.collisionMax], [LinkName.bytesMax, LinkName.extBytesMax, LinkName.collisionMax])

        CT.section("filename-cases.json: cases")
        var diffs: [String] = []
        for c in f.cases {
            let got = sanitize(c.raw)
            let want: LinkName.Result = c.out["ok"].map { .ok($0) } ?? .reject(c.out["reject"]!)
            // Compared as scalars: Swift's own String == is canonical equivalence, and the contract keeps NFC and NFKC apart.
            func same(_ a: LinkName.Result, _ b: LinkName.Result) -> Bool {
                switch (a, b) {
                case (.ok(let x), .ok(let y)): return Array(x.unicodeScalars) == Array(y.unicodeScalars)
                case (.reject(let x), .reject(let y)): return x == y
                default: return false
                }
            }
            if !same(got, want) { diffs.append("\(c.name): got \(got), want \(want)") }
        }
        CT.check("all \(f.cases.count) cases give the saved name or the reason the fixture says", diffs, [])

        CT.section("filename-cases.json: uniqueCases")
        diffs = []
        for c in f.uniqueCases {
            var taken = c.taken
            if let t = c.takenNumbered { for n in t.from...t.to { taken.append("\(t.stem) (\(n))\(t.ext)") } }
            let got = LinkName.uniqueName(c.wanted, taken: taken)
            if got.map({ Array($0.unicodeScalars) }) != c.out.map({ Array($0.unicodeScalars) }) { diffs.append("\(c.name): got \(String(describing: got)), want \(String(describing: c.out))") }
        }
        CT.check("all \(f.uniqueCases.count) collision cases", diffs, [])

        CT.section("what the fixtures cannot write")
        func ok(_ raw: String) -> String? { if case .ok(let n) = LinkName.sanitize(raw) { return n }; return nil }
        func rej(_ raw: String) -> String? { if case .reject(let r) = LinkName.sanitize(raw) { return r }; return nil }
        CT.check("a run of 250 spaces is one space before the cut: CON, 250 spaces, x.txt is CON x.txt", ok("CON" + String(repeating: " ", count: 250) + "x.txt"), "CON x.txt")
        CT.check("a run of 250 spaces after a dot is one space, and the leading-dot rule gives _. x", ok("." + String(repeating: " ", count: 250) + "x"), "_. x")
        CT.check("the cut leaves dots and spaces only: refused as empty", rej(String(repeating: ". ", count: 120) + String(repeating: "x", count: 20)), "empty")
        CT.check("the cut leaves full-width dots and spaces only, which NFKC makes dots: refused as empty", rej(String(repeating: "\u{FF0E} ", count: 120) + String(repeating: "x", count: 20)), "empty")
        CT.check("a Swift String compares by canonical equivalence, so the key is the NFC scalars case-folded", [LinkName.key("e\u{301}"), LinkName.key("\u{E9}")].map { Array($0.unicodeScalars) }, [Array("\u{E9}".unicodeScalars), Array("\u{E9}".unicodeScalars)])
        CT.check("ß folds to ss (a documented limit: the second of straße.txt and strasse.txt is numbered)", LinkName.uniqueName("strasse.txt", taken: ["stra\u{DF}e.txt"]), "strasse (1).txt")
        CT.check("a leading dot is not an extension", LinkName.uniqueName(".bashrc", taken: [".bashrc"]), ".bashrc (1)")

        CT.section("6000 hostile names: what is accepted is a safe name, and cleaning it again changes nothing")
        var rnd = Lcg(s: 20261014)
        let alphabet: [String] = Array("ab.. /\\:*?\"<>|~%$").map(String.init) + ["\u{0}", "\u{1f}", "\u{7f}", "\u{85}", "\u{200b}", "\u{200d}", "\u{202e}", "\u{2066}", "\u{feff}", "\u{2028}", "\u{a0}", "\u{3000}", "\u{FF0E}", "\u{FF0F}", "\u{FF3C}", "e\u{301}", "\u{E9}", "\u{1F408}", "\u{65E5}", "CON", "nul", "COM1", "\u{B9}", "\u{FB01}"]
        let tails = ["", ".txt", ".", " ", ".tar.gz"]
        var bad: String?
        for _ in 0..<6000 {
            var raw = ""
            for _ in 0..<rnd.next(40) { raw += alphabet[rnd.next(alphabet.count)] }
            raw += tails[rnd.next(tails.count)]
            guard case .ok(let name) = LinkName.sanitize(raw) else {
                if case .reject(let r) = LinkName.sanitize(raw), !["invisible", "separator", "empty"].contains(r) { bad = "reason \(r) for \(raw.unicodeScalars.map(\.value))"; break }
                continue
            }
            let sc = Array(name.unicodeScalars), nk = LinkName.nfkc(sc)
            let stem = LinkName.string(Array(sc.prefix { $0 != "." }))
            let reservedStem = LinkName.isReserved(sc)
            let unique = LinkName.uniqueName(name, taken: [name])
            let checks: [Bool] = [
                !sc.isEmpty, name.utf8.count <= LinkName.bytesMax, Array(name.precomposedStringWithCanonicalMapping.unicodeScalars) == sc,
                !(sc + nk).contains { $0 == "/" || $0 == "\\" }, !sc.contains { "<>:\"|?*".unicodeScalars.contains($0) }, !sc.contains { LinkName.isBadCategory($0) },
                sc.last != "." && sc.last != " ", sc.first != ".", !LinkName.isSpace(sc[0]), !LinkName.trim(nk).isEmpty, !reservedStem || sc.first == "_" || stem.isEmpty,
                { if case .ok(let again) = LinkName.sanitize(name) { return Array(again.unicodeScalars) == sc }; return false }(),
                unique != nil && unique!.utf8.count <= LinkName.bytesMax + 7,
            ]
            if checks.contains(false) { bad = "\(raw.unicodeScalars.map(\.value)) -> \(name) \(checks)"; break }
        }
        CT.check("no hostile name gets through", bad, nil)

        CT.section("3000 raw names of 300 bytes or more: at most 200 bytes, a device name never without its _")
        let heads = ["CON", "nul", "COM1", "LPT9", "aux", "CONOUT$", "\u{FF23}\u{FF2F}\u{FF2E}", "COM\u{B9}"]
        let pieces = [" ", " ", " ", " ", " ", " ", "a", "x", "Z", ".", "\u{E9}", "\u{1F408}", "\u{65E5}", "\u{301}"]
        let ends = ["", ".txt", ".tar.gz", ".bin", " .log"]
        var longBad: String?
        for _ in 0..<3000 {
            var raw = heads[rnd.next(heads.count)] + String(repeating: " ", count: 150 + rnd.next(150))
            let target = 300 + rnd.next(60)
            while raw.utf8.count < target { raw += pieces[rnd.next(pieces.count)] }
            raw += ends[rnd.next(ends.count)]
            guard case .ok(let name) = LinkName.sanitize(raw) else { continue }
            let sc = Array(name.unicodeScalars)
            if name.utf8.count > LinkName.bytesMax || ((LinkName.isReserved(sc) || LinkName.isReserved(LinkName.nfkc(sc))) && sc.first != "_") { longBad = "\(raw.prefix(20)) -> \(name)"; break }
        }
        CT.check("no long name breaks the limit or hides a device name", longBad, nil)
        CT.finish()
    }
}
