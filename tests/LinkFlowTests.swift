import Foundation

// What each side does with each frame (docs/LINK-CONTRACT.md): flow-cases.json replayed against LinkFlow.swift, whole transfers event by event, the chunk plans, and a seeded fuzz of random event scripts.
// Run it through scripts/test-link-flow.sh.

@main
enum LinkFlowTests {
    typealias W = LinkWire

    static func bytes(_ hex: String) -> Data { LinkBytes.data(hex: hex)! }
    static func u64(_ v: Any?) -> UInt64 { (v as! NSNumber).uint64Value }

    /// A fixture frame (a dictionary) as the typed frame; and back.
    static func frame(_ d: [String: Any]) -> W.Frame {
        switch d["type"] as! String {
        case "pair-yes": return .pairYes
        case "pair-no": return .pairNo
        case "offer": return .offer(id: bytes(d["id"] as! String), size: u64(d["size"]), name: d["name"] as! String, kind: d["kind"] as! String)
        case "accept": return .accept(id: bytes(d["id"] as! String))
        case "decline": return .decline(id: bytes(d["id"] as! String), reason: UInt8(d["reason"] as! Int))
        case "chunk": return .chunk(id: bytes(d["id"] as! String), offset: u64(d["offset"]), data: bytes(d["data"] as! String))
        case "done": return .done(id: bytes(d["id"] as! String))
        default: return .cancel(id: bytes(d["id"] as! String))
        }
    }
    static func json(_ f: W.Frame) -> [String: Any] {
        switch f {
        case .pairYes: return ["type": "pair-yes"]
        case .pairNo: return ["type": "pair-no"]
        case .offer(let id, let size, let name, let kind): return ["type": "offer", "id": LinkBytes.hex(id), "size": NSNumber(value: size), "name": name, "kind": kind]
        case .accept(let id): return ["type": "accept", "id": LinkBytes.hex(id)]
        case .decline(let id, let r): return ["type": "decline", "id": LinkBytes.hex(id), "reason": Int(r)]
        case .chunk(let id, let o, let d): return ["type": "chunk", "id": LinkBytes.hex(id), "offset": NSNumber(value: o), "data": LinkBytes.hex(d)]
        case .done(let id): return ["type": "done", "id": LinkBytes.hex(id)]
        case .cancel(let id): return ["type": "cancel", "id": LinkBytes.hex(id)]
        }
    }

    static func receiverState(_ s: [String: Any]) -> LinkFlow.ReceiverState {
        let id = (s["id"] as? String).map(bytes) ?? Data()
        switch s["s"] as! String {
        case "offered": return .offered(id: id, size: (s["size"] as? NSNumber)?.uint64Value ?? 0, name: (s["name"] as? String) ?? "")
        case "receiving": return .receiving(id: id, size: u64(s["size"]), got: u64(s["got"]))
        default: return .idle
        }
    }
    static func json(_ s: LinkFlow.ReceiverState) -> [String: Any] {
        switch s {
        case .idle: return ["s": "idle"]
        case .offered(let id, let size, let name): return ["s": "offered", "id": LinkBytes.hex(id), "size": NSNumber(value: size), "name": name]
        case .receiving(let id, let size, let got): return ["s": "receiving", "id": LinkBytes.hex(id), "size": NSNumber(value: size), "got": NSNumber(value: got)]
        }
    }
    static func senderState(_ s: [String: Any]) -> LinkFlow.SenderState {
        let id = (s["id"] as? String).map(bytes) ?? Data()
        switch s["s"] as! String { case "offered": return .offered(id: id); case "sending": return .sending(id: id); default: return .idle }
    }
    static func json(_ s: LinkFlow.SenderState) -> [String: Any] {
        switch s {
        case .idle: return ["s": "idle"]
        case .offered(let id): return ["s": "offered", "id": LinkBytes.hex(id)]
        case .sending(let id): return ["s": "sending", "id": LinkBytes.hex(id)]
        }
    }
    static func receiverEvent(_ e: [String: Any]) -> LinkFlow.Event {
        if let u = e["user"] as? String { return .user(u == "accept" ? .accept : u == "decline" ? .decline : .cancel) }
        if e["timeout"] as? Bool == true { return .timeout }
        return .frame(frame(e["frame"] as! [String: Any]))
    }
    static func senderEvent(_ e: [String: Any]) -> LinkFlow.SenderEvent {
        if let u = e["user"] as? String { return u == "cancel" ? .userCancel : .userOther }
        return .frame(frame(e["frame"] as! [String: Any]))
    }
    static func outJSON<S: Equatable & Sendable>(_ o: LinkFlow.Out<S>, _ state: [String: Any]) -> [String: Any] {
        ["state": state, "send": o.send.map(json), "notify": o.notify?.rawValue ?? NSNull(), "abort": o.abort?.rawValue ?? NSNull()]
    }
    static func runReceiver(_ s: [String: Any], _ e: [String: Any]) -> ([String: Any], [String: Any]) {
        let o = LinkFlow.receiverStep(receiverState(s), receiverEvent(e)); return (outJSON(o, json(o.state)), json(o.state))
    }
    static func runSender(_ s: [String: Any], _ e: [String: Any]) -> ([String: Any], [String: Any]) {
        let o = LinkFlow.senderStep(senderState(s), senderEvent(e)); return (outJSON(o, json(o.state)), json(o.state))
    }

    /// The rules the app keeps around one connection (docs/LINK-CONTRACT.md, "One decline per connection" and "The first frame"), as the contract's `receiver_connection_step` states them. The Mac keeps these
    /// inline in `LinkTransferReceive.run` (its `declines` count, its first-frame watch) and not as a function, so this is a model of that code written from the contract; the run itself is pinned by
    /// scripts/test-link-session.sh. The first-frame number is pinned to the real constant by scripts/test-link-flow.sh.
    static let machineDeclines: Set<UInt8> = [LinkFlow.Decline.busy, LinkFlow.Decline.tooLarge, LinkFlow.Decline.badOffer]

    static func connectionStep(_ state: LinkFlow.ReceiverState, _ declines: Int, _ e: [String: Any]) -> (out: [String: Any], state: LinkFlow.ReceiverState, declines: Int) {
        func pack(_ st: LinkFlow.ReceiverState, _ d: Int, _ send: [W.Frame] = [], _ notify: String? = nil, _ abort: String? = nil) -> ([String: Any], LinkFlow.ReceiverState, Int) {
            (["state": json(st), "declines": d, "send": send.map(json), "notify": notify ?? NSNull(), "abort": abort ?? NSNull()], st, d)
        }
        if e["silent"] as? Bool == true {
            if case .idle = state { return pack(.idle, declines, [], nil, "idle") }
            return pack(state, declines)
        }
        let isOffer: Bool = { if let f = e["frame"] as? [String: Any], f["type"] as? String == "offer" { return true }; return false }()
        let ev = receiverEvent(e)
        let res: LinkFlow.Out<LinkFlow.ReceiverState>
        if isOffer, case .idle = state, e["granted"] as? Bool == false, case .frame(.offer(let id, _, _, _)) = ev {
            res = LinkFlow.Out(state: state, send: [.decline(id: id, reason: LinkFlow.Decline.busy)])
        } else {
            res = LinkFlow.receiverStep(state, ev)
        }
        var d = declines
        if isOffer, res.send.contains(where: { if case .decline(_, let r) = $0 { return machineDeclines.contains(r) }; return false }) {
            if d >= 1 { return pack(.idle, d, [], nil, "declines") }
            d += 1
        }
        return pack(res.state, d, res.send, res.notify?.rawValue, res.abort?.rawValue)
    }

    /// Expired at exactly `firstFrameMs` after the handshake; a clock that went back, or a value that is not whole milliseconds, counts as expired.
    static func firstFrameExpired(_ handshake: Any?, _ now: Any?, limit: Int) -> Bool {
        func whole(_ v: Any?) -> Int? { guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.intValue >= 0 else { return nil }; return n.intValue }
        guard let h = whole(handshake), let n = whole(now) else { return true }
        return !(0 <= n - h && n - h < limit)
    }

    struct Lcg { var s: UInt64; mutating func next(_ n: Int) -> Int { s = s &* 6364136223846793005 &+ 1442695040888963407; return Int((s >> 33) % UInt64(n)) } }

    @MainActor static func main() {
        let f = CT.fixture("flow-cases.json", dir: "link")
        CT.section("the constants")
        CT.check("chunk size and 4 GiB", [Int(truncating: f["chunkSize"] as! NSNumber), Int(u64(f["sizeMax"]))], [W.chunkSize, Int(W.sizeMax)])
        CT.check("the abort reasons", f["aborts"] as! [String], ["unexpected", "id", "order", "overflow", "short"])

        CT.section("the receiver and the sender, row by row")
        var diffs: [String] = []
        let receiver = f["receiver"] as! [[String: Any]], sender = f["sender"] as! [[String: Any]]
        for c in receiver { let d = CT.diffs(runReceiver(c["state"] as! [String: Any], c["event"] as! [String: Any]).0, c["out"] as! [String: Any]); if !d.isEmpty { diffs.append("receiver: \(c["name"] as! String): \(d.prefix(2))") } }
        for c in sender { let d = CT.diffs(runSender(c["state"] as! [String: Any], c["event"] as! [String: Any]).0, c["out"] as! [String: Any]); if !d.isEmpty { diffs.append("sender: \(c["name"] as! String): \(d.prefix(2))") } }
        CT.check("all \(receiver.count) receiver rows and \(sender.count) sender rows", diffs, [])

        CT.section("whole transfers")
        diffs = []
        for t in f["trips"] as! [[String: Any]] {
            var state = t["from"] as! [String: Any]
            let outs = t["out"] as! [[String: Any]]
            for (i, e) in (t["events"] as! [[String: Any]]).enumerated() {
                let (got, next) = (t["side"] as! String) == "receiver" ? runReceiver(state, e) : runSender(state, e)
                state = next
                let d = CT.diffs(got, outs[i]); if !d.isEmpty { diffs.append("\(t["name"] as! String) step \(i): \(d.prefix(2))") }
            }
        }
        CT.check("all trips, step by step", diffs, [])

        CT.section("chunk plans")
        diffs = []
        for c in f["chunkPlans"] as! [[String: Any]] {
            let got = W.planChunks(size: u64(c["size"]), chunkSize: c["chunkSize"] as! Int).map { [Int($0.offset), $0.length] }
            if got != (c["out"] as! [[Int]]) { diffs.append(c["name"] as! String) }
        }
        CT.check("every plan", diffs, [])

        CT.section("the machine's one transfer place, through the real LinkBusy (docs/LINK-CONTRACT.md, \"One transfer for the whole machine\")")
        diffs = []
        let placeIds = ["01010101010101010101010101010101", "02020202020202020202020202020202"]
        let places = f["places"] as! [[String: Any]]
        for t in places {
            let busy = LinkBusy()
            let from = t["from"] as! [String: Any]
            if let h = from["holder"] as? String { _ = busy.claim(h) }
            busy.setCardLocked(from["card"] as! Bool)
            let outs = t["out"] as! [[String: Any]]
            for (i, e) in (t["events"] as! [[String: Any]]).enumerated() {
                var granted: Bool?
                if let c = e["claim"] as? String { granted = busy.claim(c) }
                else if let r = e["release"] as? String { busy.release(r) }
                else if let on = e["card"] as? Bool { busy.setCardLocked(on) }
                let want = outs[i], wantHolder = (want["place"] as! [String: Any])["holder"] as? String
                let holders = placeIds.filter { busy.holds($0) }
                if granted != want["granted"] as? Bool || holders != (wantHolder.map { [$0] } ?? []) { diffs.append("\(t["name"] as! String) step \(i)") }
            }
        }
        CT.check("all \(places.count) place trips, step by step", diffs, [])

        CT.section("one decline per connection, and the first-frame clock")
        diffs = []
        let connections = f["connections"] as! [[String: Any]]
        for t in connections {
            let from = t["from"] as! [String: Any]
            var state = receiverState(from["state"] as! [String: Any]), declines = from["declines"] as! Int
            let outs = t["out"] as! [[String: Any]]
            for (i, e) in (t["events"] as! [[String: Any]]).enumerated() {
                let r = connectionStep(state, declines, e)
                state = r.state; declines = r.declines
                let d = CT.diffs(r.out, outs[i]); if !d.isEmpty { diffs.append("\(t["name"] as! String) step \(i): \(d.prefix(2))") }
            }
        }
        CT.check("all \(connections.count) connection trips, step by step", diffs, [])
        let limit = (f["firstFrameMs"] as! NSNumber).intValue
        CT.check("the first-frame limit is 10 s", limit, 10_000)
        diffs = []
        let firstFrame = f["firstFrame"] as! [[String: Any]]
        for c in firstFrame where firstFrameExpired(c["handshake"], c["now"], limit: limit) != (c["out"] as! Bool) { diffs.append(c["name"] as! String) }
        CT.check("all \(firstFrame.count) first-frame rows, 9 999 ms open and 10 000 ms closed", diffs, [])

        CT.section("3000 random event scripts: nothing traps, the count never passes the size, an abort lands in idle, only a click starts a transfer")
        var rnd = Lcg(s: 20261014)
        let ids = [bytes(String(repeating: "01", count: 16)), bytes(String(repeating: "02", count: 16))]
        let names = ["a.txt", "../x", "CON", "a\u{0}"], sizes: [UInt64] = [0, 5, 10, 1 << 32, (1 << 32) + 1], offsets: [UInt64] = [0, 2, 4, 6, 8, 10]
        var bad: String?
        outer: for _ in 0..<3000 {
            var state = LinkFlow.ReceiverState.idle
            for _ in 0..<(1 + rnd.next(29)) {
                let id = ids[rnd.next(2)]
                let ev: LinkFlow.Event
                switch rnd.next(6) {
                case 0: ev = .frame(.offer(id: id, size: sizes[rnd.next(5)], name: names[rnd.next(4)], kind: ""))
                case 1: ev = .frame(.chunk(id: id, offset: offsets[rnd.next(6)], data: Data(repeating: 0xAB, count: 1 + rnd.next(4))))
                case 2: ev = .frame([.done(id: id), .cancel(id: id), .accept(id: id)][rnd.next(3)])
                case 3: ev = .frame(.decline(id: id, reason: 0))
                case 4: ev = .user([.accept, .decline, .cancel][rnd.next(3)])
                default: ev = .timeout
                }
                let before = state
                let res = LinkFlow.receiverStep(state, ev)
                state = res.state
                var startedByClick = true
                if case .receiving = state, !{ if case .receiving = before { return true }; return false }() { startedByClick = (ev == .user(.accept)) }
                var overshoot = false
                if case .receiving(_, let size, let got) = state { overshoot = got > size }
                if (res.abort != nil && state != .idle) || overshoot || !startedByClick { bad = "\(before) \(ev) -> \(res)"; break outer }
            }
        }
        CT.check("no script breaks an invariant", bad, nil)
        CT.finish()
    }
}
