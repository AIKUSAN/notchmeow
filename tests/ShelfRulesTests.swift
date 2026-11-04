import Foundation

// The shelf contract on the Mac (docs/SHELF-CONTRACT.md): zone-cases.json and shelf-cases.json replayed against ShelfRules, and what the fixtures cannot write.
// Run it through scripts/test-shelf-rules.sh.

@main
enum ShelfRulesTests {
    @MainActor static func load(_ file: String) -> ShelfJSON {
        let data = try! Data(contentsOf: CT.fixtureURL(file, dir: "shelf"))
        return ShelfJSONParser.parse([UInt8](data))!
    }

    static func obj(_ v: ShelfJSON?) -> [String: ShelfJSON] { if case .object(let o)? = v { return o }; fatalError("not an object: \(String(describing: v))") }
    static func list(_ v: ShelfJSON?) -> [ShelfJSON] { if case .array(let a)? = v { return a }; fatalError("not a list: \(String(describing: v))") }
    static func str(_ v: ShelfJSON?) -> String { if case .string(let s, _)? = v { return s }; fatalError("not text: \(String(describing: v))") }
    static func num(_ v: ShelfJSON?) -> Double { if case .number(let n)? = v { return n }; fatalError("not a number: \(String(describing: v))") }
    static func items(_ v: [ShelfItem]) -> ShelfJSON { .array(v.map(\.json)) }

    /// A good stored item as JSON.
    static func good(_ id: String, link: String? = nil, at t: Double = 1) -> ShelfJSON {
        .object(["id": .text(id), "name": .text("f-\(id).txt"), "size": .number(1), "folder": .bool(false), "copy": .bool(false), "link": .text(link ?? "/p/\(id)"), "addedAt": .number(t)])
    }

    @MainActor static func main() {
        CT.section("the contract's constants")
        let shelf = obj(load("shelf-cases.json"))
        CT.check("30 items, 255 code points in a name, 8192 in a link, 2^53 - 1", [num(shelf["max"]), num(shelf["nameMax"]), num(shelf["linkMax"]), num(shelf["numberMax"])], [Double(ShelfRules.max), Double(ShelfRules.nameMax), Double(ShelfRules.linkMax), ShelfRules.numberMax])
        CT.check("the id pattern is the one the code checks", str(shelf["idPattern"]), "[A-Za-z0-9_-]{1,64}")

        CT.section("zone-cases.json: which half the pointer is in")
        let zones = list(obj(load("zone-cases.json"))["cases"])
        for c in zones {
            let o = obj(c)
            let got = ShelfRules.zoneAt(x: o["x"], width: o["width"])
            var want: ShelfZone?
            if case .string(let w, _)? = o["out"] { want = ShelfZone(rawValue: w) }
            CT.check(str(o["name"]), got?.rawValue ?? "null", want?.rawValue ?? "null")
        }
        CT.check("the typed form agrees at the centre line", [ShelfRules.zoneAt(x: 320, width: 640)?.rawValue, ShelfRules.zoneAt(x: 320.5, width: 640)?.rawValue], ["ask", "shelf"])
        CT.check("and refuses NaN and infinity, which JSON cannot hold", [ShelfRules.zoneAt(x: .nan, width: 640) == nil, ShelfRules.zoneAt(x: 1, width: .infinity) == nil, ShelfRules.zoneAt(x: 1, width: .nan) == nil], [true, true, true])

        CT.section("shelfClean: cleanCases")
        for c in list(shelf["cleanCases"]) {
            let o = obj(c)
            CT.check(str(o["name"]), items(ShelfRules.clean(o["raw"])), o["out"]!)
        }

        CT.section("shelfAdd: addCases")
        for c in list(shelf["addCases"]) {
            let o = obj(c)
            let r = ShelfRules.add(items: o["items"], incoming: o["incoming"])
            let want = obj(o["out"])
            CT.check(str(o["name"]) + " (items)", items(r.items), want["items"]!)
            CT.check(str(o["name"]) + " (results)", ShelfJSON.array(r.results.map { .text($0.rawValue) }), want["results"]!)
        }

        CT.section("parseCases: the bytes of a file")
        for c in list(shelf["parseCases"]) {
            let o = obj(c)
            let bytes: [UInt8]
            if let t = o["text"] { bytes = Array(str(t).utf8) } else {
                let hex = Array(str(o["hex"]).utf8)
                bytes = stride(from: 0, to: hex.count, by: 2).map { UInt8(String(decoding: hex[$0..<$0 + 2], as: UTF8.self), radix: 16)! }
            }
            CT.check(str(o["name"]), items(ShelfRules.read(bytes)), o["out"]!)
        }

        CT.section("what the fixtures cannot write")
        // A name that is the right length in code points but not in UTF-16 units: 255 emoji are 510 units and still fit; 256 do not.
        let emoji255 = String(repeating: "😀", count: 255), emoji256 = String(repeating: "😀", count: 256)
        CT.checkTrue("255 emoji are a name, 256 are not (code points, not UTF-16 units)", ShelfRules.nameOK(emoji255, lone: false) && !ShelfRules.nameOK(emoji256, lone: false))
        CT.checkTrue("a lone surrogate in a name or a link is refused", !ShelfRules.nameOK("a", lone: true) && !ShelfRules.linkOK("/p", lone: true))
        CT.checkTrue("a right-to-left override in a name is refused, in a link it is allowed", !ShelfRules.nameOK("a\u{202E}txt", lone: false) && ShelfRules.linkOK("/p/\u{202E}a", lone: false))
        CT.checkTrue("CON, con.txt, NUL.tar.gz, COM¹ and 'CON .txt' are refused; CONSOLE and COM0 are not", ["CON", "con.txt", "NUL.tar.gz", "COM\u{B9}", "CON .txt"].allSatisfy { !ShelfRules.nameOK($0, lone: false) } && ShelfRules.nameOK("CONSOLE", lone: false) && ShelfRules.nameOK("COM0", lone: false))
        CT.check("a number beyond 2^53 - 1, a fraction and a negative become 0", [ShelfRules.whole(.number(9007199254740992)), ShelfRules.whole(.number(2.5)), ShelfRules.whole(.number(-1)), ShelfRules.whole(.number(.infinity)), ShelfRules.whole(.bool(true)), ShelfRules.whole(nil)], [0, 0, 0, 0, 0, 0] as [Int64])
        CT.check("2^53 - 1 itself stays", ShelfRules.whole(.number(9007199254740991)), 9007199254740991)

        // The parser: what a hostile file can be.
        func parses(_ s: String) -> Bool { ShelfJSONParser.parse(Array(s.utf8)) != nil }
        CT.checkTrue("it reads strict JSON", parses("{\"a\":[1,-2.5e3,true,false,null,\"x\\u00e9\\n\"]}") && parses(" [ ] ") && parses("0") && parses("-0"))
        CT.checkTrue("and refuses what is not: a leading zero, a lone minus, a trailing comma, single quotes, a raw tab in a string, a trailing comma in an object", !parses("01") && !parses("-") && !parses("[1,]") && !parses("{'a':1}") && !parses("[\"a\tb\"]") && !parses("{\"a\":1,}"))
        CT.checkTrue("and NaN, Infinity, text after the value, an unfinished string and a bad escape", !parses("NaN") && !parses("[Infinity]") && !parses("[] x") && !parses("\"abc") && !parses("[\"\\x\"]") && !parses("[\"\\u12\"]"))
        CT.check("a surrogate pair escape is one character; a lone one sets the flag", [ShelfJSONParser.parse(Array("\"\\ud83d\\ude00\"".utf8)), ShelfJSONParser.parse(Array("\"\\ud83d\"".utf8)), ShelfJSONParser.parse(Array("\"\\ude00\"".utf8))], [.string("😀", lone: false), .string("", lone: true), .string("", lone: true)])
        CT.checkTrue("a byte order mark is not white space", ShelfJSONParser.parse([0xEF, 0xBB, 0xBF] + Array("{}".utf8)) == nil)
        CT.checkTrue("invalid UTF-8 is not JSON", ShelfJSONParser.parse([0x22, 0xFF, 0x22]) == nil)
        CT.checkTrue("a thousand nested lists are refused without a stack overflow", ShelfJSONParser.parse(Array((String(repeating: "[", count: 1000) + String(repeating: "]", count: 1000)).utf8)) == nil)
        CT.check("a repeated key keeps the last value", ShelfJSONParser.parse(Array("{\"a\":1,\"a\":2}".utf8)), .object(["a": .number(2)]))
        // reference.py keeps a key with a lone surrogate as a key of its own, which no lookup matches; it must never become the key without the surrogate ("na\ud800me" is not "name").
        CT.check("a key with a lone surrogate is not the key without it", [ShelfJSONParser.parse(Array("{\"na\\ud800me\":1}".utf8)), ShelfJSONParser.parse(Array("{\"name\":\"real\",\"na\\ude00me\":\"fake\"}".utf8))], [.object([:]), .object(["name": .text("real")])])

        // isLossless and encode.
        CT.checkTrue("a clean shelf is lossless; an unreadable file, a dropped item and a duplicate are not",
                     ShelfRules.isLossless(Array("{\"items\":[]}".utf8)) && !ShelfRules.isLossless(Array("{".utf8)) && !ShelfRules.isLossless(Array("[]".utf8)) && !ShelfRules.isLossless(Array("".utf8))
                        && !ShelfRules.isLossless(Array("{\"items\":[{\"id\":\"../x\"}]}".utf8)))
        let one = ShelfItem(id: "a", name: "f.txt", size: 3, folder: false, copy: false, link: "/p/a", addedAt: 7)
        let copy = ShelfItem(id: "b", name: "g.png", size: 0, folder: false, copy: true, link: nil, addedAt: 9)
        let bytes = [UInt8](ShelfRules.encode([copy, one]))
        CT.check("what is written is read back as it was", ShelfRules.read(bytes), [copy, one])
        CT.check("and is stable: the same bytes twice, a slash not escaped", [ShelfRules.encode([copy, one]) == ShelfRules.encode([copy, one]), String(decoding: bytes, as: UTF8.self).contains("\"/p/a\"")], [true, true])
        CT.checkTrue("an empty shelf is written as a file that reads back empty", ShelfRules.read([UInt8](ShelfRules.encode([]))).isEmpty && ShelfRules.isLossless([UInt8](ShelfRules.encode([]))))

        // add, typed: the app's form.
        let r1 = ShelfRules.add([one], [copy, one, ShelfItem(id: "c", name: "a/b", size: 0, folder: false, copy: false, link: "/q", addedAt: 1)])
        CT.check("add (typed): a new copy is added, the same item is a duplicate, a bad name is invalid", r1.results, [.added, .duplicate, .invalid])
        CT.check("and the new item is first", r1.items.map(\.id), ["b", "a"])
        var full: [ShelfItem] = []
        for n in 0..<30 { full.append(ShelfItem(id: "x\(n)", name: "f\(n)", size: 0, folder: false, copy: false, link: "/x/\(n)", addedAt: Int64(n + 1))) }
        let r2 = ShelfRules.add(full, [copy])
        CT.check("a drop on a full shelf is refused and removes nothing", [r2.results, r2.items.count == 30 ? [.full] : []], [[.full], [.full]] as [[ShelfAddResult]])
        // The same bookmark base64 twice is one link; a later one with a different id is a duplicate.
        CT.check("two items with one link are one", ShelfRules.add([one], [ShelfItem(id: "z", name: "z", size: 0, folder: false, copy: false, link: "/p/a", addedAt: 99)]).results, [.duplicate])

        CT.finish()
    }
}
