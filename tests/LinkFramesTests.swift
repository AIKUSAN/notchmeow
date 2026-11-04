import Foundation

// The wire shapes of the link (docs/LINK-CONTRACT.md "On the wire"): frames.json replayed against LinkFrames.swift, and a seeded fuzz of damaged frames.
// Run it through scripts/test-link-frames.sh.

@main
enum LinkFramesTests {
    typealias W = LinkWire

    static func bytes(_ hex: String) -> Data { LinkBytes.data(hex: hex)! }
    static func u64(_ v: Any?) -> UInt64 { (v as! NSNumber).uint64Value }

    /// A fixture frame (a dictionary) as the typed frame.
    static func frame(_ d: [String: Any]) -> W.Frame {
        let type = d["type"] as! String
        if type == "pair-yes" { return .pairYes }
        if type == "pair-no" { return .pairNo }
        let id = bytes(d["id"] as! String)
        switch type {
        case "offer": return .offer(id: id, size: u64(d["size"]), name: d["name"] as! String, kind: d["kind"] as! String)
        case "accept": return .accept(id: id)
        case "decline": return .decline(id: id, reason: UInt8(d["reason"] as! Int))
        case "chunk": return .chunk(id: id, offset: u64(d["offset"]), data: bytes(d["data"] as! String))
        case "done": return .done(id: id)
        default: return .cancel(id: id)
        }
    }

    /// The error code of a failed call, or nil.
    static func code<T>(_ f: () throws -> T) -> String? {
        do { _ = try f(); return nil } catch { return (error as? LinkFrameError)?.rawValue ?? "other:\(error)" }
    }

    struct Lcg { var s: UInt64; mutating func next(_ n: Int) -> Int { s = s &* 6364136223846793005 &+ 1442695040888963407; return Int((s >> 33) % UInt64(n)) } }

    @MainActor static func main() {
        let f = CT.fixture("frames.json", dir: "link")
        CT.section("the constants")
        CT.check("the numbers the rules name", [f["noiseMax"] as! Int, f["tag"] as! Int, f["idLen"] as! Int, f["protocolVersion"] as! Int, f["chunkMax"] as! Int, f["chunkSize"] as! Int, f["rawNameMax"] as! Int, f["kindMax"] as! Int, f["deviceNameMax"] as! Int],
                 [W.noiseMax, W.tag, W.idLen, Int(W.protocolVersion), W.chunkMax, W.chunkSize, W.rawNameMax, W.kindMax, W.deviceNameMax])
        CT.check("4 GiB inclusive", u64(f["sizeMax"]), W.sizeMax)
        CT.check("the type numbers", (f["types"] as! [String: Int]).sorted { $0.key < $1.key }.map(\.value), ["accept": 2, "cancel": 6, "chunk": 4, "decline": 3, "done": 5, "offer": 1, "pairNo": 34, "pairYes": 33].sorted { $0.key < $1.key }.map(\.value))
        CT.check("a chunk frame at its largest plus the tag fills one Noise message exactly", 1 + W.idLen + 8 + W.chunkMax + W.tag, W.noiseMax)

        CT.section("frames: encode and decode")
        var diffs: [String] = []
        for c in f["frames"] as! [[String: Any]] {
            let want = frame(c["frame"] as! [String: Any]), hex = c["hex"] as! String
            if (try? W.encode(want)).map(LinkBytes.hex) != hex { diffs.append("encode: \(c["name"] as! String)") }
            if (try? W.decode(bytes(hex))) != want { diffs.append("decode: \(c["name"] as! String)") }
        }
        CT.check("every frame encodes to its hex and decodes back", diffs, [])

        CT.section("rejects and limits")
        diffs = []
        for c in f["rejects"] as! [[String: Any]] where code({ try W.decode(bytes(c["hex"] as! String)) }) != (c["error"] as! String) { diffs.append(c["name"] as! String) }
        CT.check("every damaged frame is refused with the fixture's cause", diffs, [])
        diffs = []
        for c in f["limits"] as! [[String: Any]] {
            let fill = bytes(c["fill"] as! String), count = c["count"] as! Int
            var data = Data(); for _ in 0..<count { data.append(fill) }
            let raw = Data([4]) + bytes(c["id"] as! String) + Data(W_be(u64(c["offset"]))) + data
            if (code({ try W.decode(raw) }) ?? "ok") != (c["out"] as! String) { diffs.append(c["name"] as! String) }
        }
        CT.check("a chunk of 65494 bytes is good, 65495 is chunk-long", diffs, [])

        CT.section("hello, advert, first record, records")
        diffs = []
        for c in f["hello"] as! [[String: Any]] {
            let out = c["out"] as! [String: String], hex = c["hex"] as! String
            if let e = out["error"] {
                if code({ try W.decodeHello(bytes(hex)) }) != e { diffs.append("hello: \(c["name"] as! String)") }
            } else if let h = try? W.decodeHello(bytes(hex)) {
                if h != W.Hello(id: out["id"]!, nonce: out["nonce"]!, name: out["name"]!) { diffs.append("hello: \(c["name"] as! String)") }
                if LinkBytes.hex(W.encodeHello(deviceId: bytes(out["id"]!), nonce: bytes(out["nonce"]!), name: out["name"]!)) != hex { diffs.append("hello re-encoded: \(c["name"] as! String)") }
            } else { diffs.append("hello: \(c["name"] as! String)") }
        }
        for c in f["txt"] as! [[String: Any]] {
            let out = c["out"] as! [String: String]
            guard let rec = c["txt"] as? [String: Any] else {
                if out["error"] != "not-a-record" { diffs.append("advert: \(c["name"] as! String)") }
                continue   // a list and null are not records: the typed call cannot be given one
            }
            var own = LinkOwnId.absent
            if c["ownId"] != nil { own = (c["ownId"] as? String).map { .value($0) } ?? .null }
            let txt = rec.compactMapValues { $0 as? String }      // a number is no text: the version check then sees nothing
            let got: [String: String]
            do { let a = try W.parseTxt(txt, ownId: own); got = ["id": a.id, "name": a.name] } catch { got = ["error": (error as? LinkFrameError)?.rawValue ?? "other"] }
            if got != out { diffs.append("advert: \(c["name"] as! String): \(got)") }
        }
        for c in f["preamble"] as! [[String: Any]] {
            let out = c["out"] as! [String: String], hex = c["hex"] as! String
            if let e = out["error"] { if code({ try W.decodePreamble(bytes(hex)) }) != e { diffs.append("preamble: \(c["name"] as! String)") }; continue }
            let p = try? W.decodePreamble(bytes(hex))
            if p?.id != out["id"] || (p?.mode == .pair) != (out["mode"] == "pair") || p.map({ LinkBytes.hex(W.encodePreamble(mode: $0.mode, deviceId: bytes($0.id))) }) != hex { diffs.append("preamble: \(c["name"] as! String)") }
        }
        for c in f["records"] as! [[String: Any]] {
            let out = c["out"] as! [String: Any], hex = c["hex"] as! String
            do {
                let r = try W.splitRecords(bytes(hex))
                if r.records.map(LinkBytes.hex) != (out["records"] as! [String]) || LinkBytes.hex(r.rest) != (out["rest"] as! String) { diffs.append("records: \(c["name"] as! String)") }
            } catch { if (error as? LinkFrameError)?.rawValue != (out["error"] as? String) { diffs.append("records: \(c["name"] as! String)") } }
        }
        for c in f["recordEncode"] as! [[String: Any]] {
            let out = c["out"] as! [String: String]
            do { if LinkBytes.hex(try W.encodeRecord(bytes(c["payload"] as! String))) != out["hex"] { diffs.append("record: \(c["name"] as! String)") } }
            catch { if (error as? LinkFrameError)?.rawValue != out["error"] { diffs.append("record: \(c["name"] as! String)") } }
        }
        CT.check("every hello, advert, first record and record case is as the fixture says", diffs, [])
        CT.check("a record of 65535 bytes is made, one of 65536 is not", [(try? W.encodeRecord(Data(count: 65535)))?.count ?? -1, code { try W.encodeRecord(Data(count: 65536)) } == "record-length" ? 1 : 0], [65537, 1])
        CT.check("the nonce of an advert's own id given as null refuses every advert", code { try W.parseTxt(["v": "1", "id": "ab" + String(repeating: "cd", count: 15), "name": "Mac"], ownId: .null) }, "device-id")

        CT.section("planChunks")
        CT.check("an empty file has none; 10 bytes by 4 are 4, 4, 2; a multiple fits exactly", [W.planChunks(size: 0).count, W.planChunks(size: 10, chunkSize: 4).map(\.length).reduce(0, +), W.planChunks(size: 65536).count], [0, 10, 2])
        CT.check("the offsets are contiguous", W.planChunks(size: 10, chunkSize: 4).map { Int($0.offset) }, [0, 4, 8])

        CT.section("8000 damaged frames: nothing but a LinkFrameError, and what is accepted encodes back to the same bytes")
        var rnd = Lcg(s: 20261014)
        let seeds = (f["frames"] as! [[String: Any]]).map { bytes($0["hex"] as! String) }.filter { $0.count < 200 }
        var bad: String?
        for _ in 0..<8000 {
            var b = [UInt8](seeds[rnd.next(seeds.count)])
            for _ in 0..<rnd.next(4) {
                switch rnd.next(4) {
                case 0 where !b.isEmpty: b[rnd.next(b.count)] = UInt8(rnd.next(256))
                case 1 where !b.isEmpty: b.removeSubrange(rnd.next(b.count)...)
                case 2: for _ in 0..<(1 + rnd.next(3)) { b.append(UInt8(rnd.next(256))) }
                default: if !b.isEmpty { b.insert(UInt8(rnd.next(256)), at: rnd.next(b.count)) }
                }
            }
            do { let fr = try W.decode(Data(b)); if try W.encode(fr) != Data(b) { bad = LinkBytes.hex(b); break } }
            catch is LinkFrameError {} catch { bad = "other error \(error)"; break }
        }
        CT.check("no damaged frame traps or re-encodes differently", bad, nil)
        CT.finish()
    }

    static func W_be(_ v: UInt64) -> [UInt8] { LinkBytes.beUInt64(v) }
}
