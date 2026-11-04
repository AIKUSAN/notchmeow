import Foundation

// Pairing (docs/LINK-CONTRACT.md "The pairing code"): pairing-cases.json replayed against LinkPairing.swift: the commitment, the code, the clocks and the two machines row by row.
// The fixtures hold state and events as JSON; the bridge below turns them into the typed values the port takes and the machines' answers back into JSON.
// Run it through scripts/test-link-pairing.sh.

@main
enum LinkPairingTests {
    typealias P = LinkPairing

    // MARK: JSON bridge

    /// A whole number of milliseconds, or nil (text, a boolean, null, a fraction).
    static func msInt(_ v: Any?) -> Int? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), CFNumberIsFloatType(n) == false else { return nil }
        return n.intValue
    }
    /// The time of the last attempt: null is "none yet"; a value that is given but is not whole milliseconds counts as -1, which the rule refuses (the typed port has no way to hold text).
    static func lastInt(_ v: Any?) -> Int? { (v == nil || v is NSNull) ? nil : (msInt(v) ?? -1) }
    static func str(_ v: Any?) -> String? { v as? String }
    static func isYes(_ v: Any?) -> Bool { (v as? String) == "yes" }

    static func ids(_ s: [String: Any]) -> P.Ids {
        var i = P.Ids()
        if s.keys.contains("own_id") { i.ownId = (s["own_id"] as? String).map { .value($0) } ?? .null }
        if let p = s["paired"] as? [String: String] { i.paired = p }
        return i
    }
    static func idsJSON(_ i: P.Ids) -> [String: Any] {
        var o: [String: Any] = [:]
        switch i.ownId { case .absent: break; case .null: o["own_id"] = NSNull(); case .value(let v): o["own_id"] = v }
        if let p = i.paired { o["paired"] = p }
        return o
    }
    static func yes(_ b: Bool) -> Any { b ? "yes" : NSNull() }

    static func responderState(_ s: [String: Any]) -> P.ResponderState {
        var st = P.ResponderState(seen: (s["seen"] as! [[String: Any]]).map { P.Seen(commit: $0["commit"] as! String, at: $0["at"] as! Int) }, last: msInt(s["last"]), ids: ids(s))
        switch s["s"] as! String {
        case "committed": st.phase = .committed(commit: s["commit"] as! String, start: s["start"] as! Int, nonce: s["nonce"] as! String)
        case "coded": st.phase = .coded(start: s["start"] as! Int, code: s["code"] as! String, mine: isYes(s["mine"]), theirs: isYes(s["theirs"]))
        default: break
        }
        return st
    }
    static func json(_ st: P.ResponderState) -> [String: Any] {
        var o = idsJSON(st.ids)
        o["seen"] = st.seen.map { ["commit": $0.commit, "at": $0.at] as [String: Any] }
        o["last"] = st.last.map { $0 as Any } ?? NSNull()
        switch st.phase {
        case .idle: o["s"] = "idle"
        case .committed(let c, let start, let nonce): o["s"] = "committed"; o["commit"] = c; o["start"] = start; o["nonce"] = nonce
        case .coded(let start, let code, let mine, let theirs): o["s"] = "coded"; o["start"] = start; o["code"] = code; o["mine"] = yes(mine); o["theirs"] = yes(theirs)
        }
        return o
    }
    static func responderEvent(_ e: [String: Any]) -> P.ResponderEvent {
        let now = msInt(e["now"])
        if e.keys.contains("commit") { return .commit(commit: str(e["commit"]), nonce: str(e["nonce"]), now: now) }
        if let r = e["reveal"] as? [String: Any] { return .reveal(P.Reveal(nonce: str(r["nonce"]), staticKey: str(r["static"]), own: str(r["own"]), peerId: str(r["peerId"])), now: now) }
        if e.keys.contains("user") { return .user(yes: isYes(e["user"]), now: now) }
        if e.keys.contains("peer") { return .peer(yes: isYes(e["peer"]), now: now) }
        return .unknown
    }

    static func initiatorState(_ s: [String: Any]) -> P.InitiatorState {
        var st = P.InitiatorState(last: msInt(s["last"]), ids: ids(s))
        switch s["s"] as! String {
        case "started": st.phase = .started(nonce: s["nonce"] as! String, staticKey: s["static"] as! String, start: s["start"] as! Int)
        case "coded": st.phase = .coded(start: s["start"] as! Int, code: s["code"] as! String, mine: isYes(s["mine"]), theirs: isYes(s["theirs"]))
        default: break
        }
        return st
    }
    static func json(_ st: P.InitiatorState) -> [String: Any] {
        var o = idsJSON(st.ids)
        o["last"] = st.last.map { $0 as Any } ?? NSNull()
        switch st.phase {
        case .idle: o["s"] = "idle"
        case .started(let n, let s, let start): o["s"] = "started"; o["nonce"] = n; o["static"] = s; o["start"] = start
        case .coded(let start, let code, let mine, let theirs): o["s"] = "coded"; o["start"] = start; o["code"] = code; o["mine"] = yes(mine); o["theirs"] = yes(theirs)
        }
        return o
    }
    static func initiatorEvent(_ e: [String: Any]) -> P.InitiatorEvent {
        let now = msInt(e["now"])
        if let s = e["start"] as? [String: Any] { return .start(nonce: str(s["nonce"]), staticKey: str(s["static"]), now: now) }
        if e.keys.contains("nonce") { return .nonce(str(e["nonce"]), peerStatic: str(e["peerStatic"]), peerId: str(e["peerId"]), now: now) }
        if e.keys.contains("user") { return .user(yes: isYes(e["user"]), now: now) }
        if e.keys.contains("peer") { return .peer(yes: isYes(e["peer"]), now: now) }
        return .unknown
    }

    static func outJSON<S: Equatable & Sendable>(_ o: P.Out<S>, _ state: [String: Any]) -> [String: Any] {
        let send: [[String: Any]] = o.send.map {
            switch $0 {
            case .nonce(let n): return ["nonce": n]
            case .commit(let c): return ["commit": c]
            case .reveal(let r): return ["reveal": r]
            case .pair(let y): return ["pair": y ? "yes" : "no"]
            }
        }
        return ["state": state, "send": send, "notify": o.notify?.rawValue ?? NSNull(), "because": o.because?.rawValue ?? NSNull()]
    }

    static func responderRun(_ state: [String: Any], _ event: [String: Any]) -> ([String: Any], [String: Any]) {
        let o = P.responderStep(responderState(state), responderEvent(event))
        return (outJSON(o, json(o.state)), json(o.state))
    }
    static func initiatorRun(_ state: [String: Any], _ event: [String: Any]) -> ([String: Any], [String: Any]) {
        let o = P.initiatorStep(initiatorState(state), initiatorEvent(event))
        return (outJSON(o, json(o.state)), json(o.state))
    }

    // MARK: Tests

    @MainActor static func main() {
        let f = CT.fixture("pairing-cases.json", dir: "link")
        func data(_ s: String) -> Data { LinkBytes.data(hex: s)! }

        CT.section("the constants")
        CT.check("6 digits, 30 s, 2 minutes, 2 minutes", [f["digits"] as! Int, f["gapMs"] as! Int, f["windowMs"] as! Int, f["offerTimeoutMs"] as! Int], [P.codeDigits, P.gapMs, P.windowMs, P.offerTimeoutMs])
        CT.check("the labels", [String(decoding: P.commitLabel, as: UTF8.self), String(decoding: P.codeLabel, as: UTF8.self)], [f["commitLabel"] as! String, f["codeLabel"] as! String])

        CT.section("commits, codes, invalid")
        var diffs: [String] = []
        for c in f["commits"] as! [[String: Any]] where P.commitOf(nonce: data(c["nonce"] as! String), staticKey: data(c["static"] as! String)).map(LinkBytes.hex) != (c["commit"] as! String) { diffs.append(c["name"] as! String) }
        CT.check("every commitment", diffs, [])
        diffs = []
        for c in f["codes"] as! [[String: Any]] where P.code(nonceI: data(c["nonceI"] as! String), nonceR: data(c["nonceR"] as! String), staticI: data(c["staticI"] as! String), staticR: data(c["staticR"] as! String)) != (c["code"] as! String) { diffs.append(c["name"] as! String) }
        CT.check("every code, leading zeros kept", diffs, [])
        diffs = []
        for c in f["invalid"] as! [[String: Any]] {
            var v: [String: Data] = ["nonceI": data("a1" + String(repeating: "a1", count: 31)), "nonceR": data("b1" + String(repeating: "b1", count: 31)), "staticI": data("c1" + String(repeating: "c1", count: 31)), "staticR": data("c2" + String(repeating: "c2", count: 31))]
            // The field is text that is not 32 bytes, not hex or missing: as bytes it is what hex decoding gives, or nothing (then the field has no 32 bytes either).
            v[c["field"] as! String] = (c["value"] as? String).flatMap { LinkBytes.data(hex: $0) } ?? Data()
            if P.code(nonceI: v["nonceI"]!, nonceR: v["nonceR"]!, staticI: v["staticI"]!, staticR: v["staticR"]!) != nil { diffs.append(c["name"] as! String) }
        }
        CT.check("a nonce or a key that is not 32 bytes gives no code", diffs, [])
        CT.checkTrue("commit_of refuses a short nonce", P.commitOf(nonce: Data(count: 31), staticKey: Data(count: 32)) == nil)

        CT.section("the pairing inside the xx-link Noise vector")
        let s = f["session"] as! [String: Any]
        let vec = ((CT.fixture("noise-vectors.json", dir: "link")["vectors"] as! [[String: Any]]).first { ($0["id"] as! String) == (s["vector"] as! String) })!
        let payloads = (vec["messages"] as! [[String: String]]).prefix(3).map { data($0["payload"]!) }
        let hr = try! LinkWire.decodeHello(payloads[1]), hi = try! LinkWire.decodeHello(payloads[2])
        CT.check("the first payload is the commitment and the hellos carry the nonces the case names", [LinkBytes.hex(payloads[0]), hi.nonce, hr.nonce], [s["commit"] as! String, s["nonceI"] as! String, s["nonceR"] as! String])
        CT.check("the code of that pairing is the one the case names", P.code(nonceI: data(hi.nonce), nonceR: data(hr.nonce), staticI: data(s["staticI"] as! String), staticR: data(s["staticR"] as! String)), (s["code"] as! String))

        CT.section("the clocks")
        diffs = []
        for c in f["gapCases"] as! [[String: Any]] where P.attemptAllowed(last: lastInt(c["last"]), now: msInt(c["now"])) != (c["out"] as! Bool) { diffs.append(c["name"] as! String) }
        for c in f["windowCases"] as! [[String: Any]] where P.windowOpen(start: msInt(c["start"]), now: msInt(c["now"])) != (c["out"] as! Bool) { diffs.append(c["name"] as! String) }
        for c in f["offerCases"] as! [[String: Any]] where P.offerExpired(offered: msInt(c["offered"]), now: msInt(c["now"])) != (c["out"] as! Bool) { diffs.append(c["name"] as! String) }
        CT.check("the attempt gap, the pairing window and the offer timeout, boundaries and bad values", diffs, [])

        CT.section("who may start a pairing with this Mac (the owner's rule, 2026-10-15)")
        var gate = P.Gate()
        CT.check("a fresh Mac refuses an incoming pairing", gate.allows(now: 1000), false)
        gate.devicesAppeared()
        CT.check("while Settings, Devices is open it allows one", gate.allows(now: 1000), true)
        gate.devicesAppeared(); gate.devicesDisappeared()
        CT.check("two openers and one closer: still open; the last closer shuts it", [gate.allows(now: 1000), { var g = gate; g.devicesDisappeared(); g.devicesDisappeared(); return g.allows(now: 1000) }()], [true, false])
        var clicked = P.Gate()
        clicked.pairClicked(now: 5000)
        CT.check("after a click on Pair here the window is the contract's: open at the click, 1 ms before 2 minutes, closed at exactly 120 s, closed long after",
                 [clicked.allows(now: 5000), clicked.allows(now: 124_999), clicked.allows(now: 125_000), clicked.allows(now: 900_000)], [true, true, false, false])
        CT.check("a clock that went back, a missing clock and a gate never clicked all refuse", [clicked.allows(now: 4_999), clicked.allows(now: nil), P.Gate().allows(now: 5000)], [false, false, false])
        var both = clicked; both.devicesAppeared()
        CT.check("Devices open keeps it open past the 2 minutes", both.allows(now: 900_000), true)
        CT.check("a later click opens a new window", { var g = clicked; g.pairClicked(now: 200_000); return [g.allows(now: 125_000), g.allows(now: 319_999), g.allows(now: 320_000)] }(), [false, true, false])

        CT.section("the responder, row by row")
        diffs = []
        let responder = f["responder"] as! [[String: Any]]
        for r in responder {
            let (got, _) = responderRun(r["state"] as! [String: Any], r["event"] as! [String: Any])
            let d = CT.diffs(got, r["out"] as! [String: Any])
            if !d.isEmpty { diffs.append("\(r["name"] as! String): \(d.prefix(2))") }
        }
        CT.check("all \(responder.count) rows", diffs, [])
        CT.section("the initiator, row by row")
        diffs = []
        let initiator = f["initiator"] as! [[String: Any]]
        for r in initiator {
            let (got, _) = initiatorRun(r["state"] as! [String: Any], r["event"] as! [String: Any])
            let d = CT.diffs(got, r["out"] as! [String: Any])
            if !d.isEmpty { diffs.append("\(r["name"] as! String): \(d.prefix(2))") }
        }
        CT.check("all \(initiator.count) rows", diffs, [])

        CT.section("whole pairings")
        diffs = []
        for t in f["machineTrips"] as! [[String: Any]] {
            var state = t["from"] as! [String: Any]
            let events = t["events"] as! [[String: Any]], outs = t["out"] as! [[String: Any]]
            for (i, e) in events.enumerated() {
                let (got, next) = (t["side"] as! String) == "responder" ? responderRun(state, e) : initiatorRun(state, e)
                state = next
                let d = CT.diffs(got, outs[i])
                if !d.isEmpty { diffs.append("\(t["name"] as! String) step \(i): \(d.prefix(2))") }
            }
        }
        CT.check("all trips, step by step", diffs, [])
        CT.finish()
    }
}
