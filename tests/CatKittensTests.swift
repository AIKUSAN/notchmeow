import Foundation

@main
enum CatKittensTests {
    typealias K = CatKittens

    static func rows(_ x: Any?) -> [[String: Any]] { x as! [[String: Any]] }

    /// A JSON number (a boolean, text and null are not numbers).
    static func number(_ v: Any?) -> Double? {
        guard let n = v as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID() else { return nil }
        return n.doubleValue
    }

    /// The fixture's kitten list, in the app's types: an entry that is not an object, has no text id, a state that is not one of the four or a time that is not a number is
    /// not a kitten (the app never builds one); `clean` does the rest, as the contract's `cleanKittens` does.
    static func kittens(_ raw: Any?) -> [K.Kitten] {
        (raw as? [Any] ?? []).compactMap { entry in
            guard let k = entry as? [String: Any], let id = k["id"] as? String, let s = k["state"] as? String, let state = K.State(rawValue: s), let born = number(k["born"]), let last = number(k["last"]) else { return nil }
            return K.Kitten(id: id, type: k["type"] as? String ?? "", session: k["session"] as? String, state: state, born: born, last: last, until: number(k["until"]))
        }
    }

    static func json(_ list: [K.Kitten]) -> [[String: Any]] {
        list.map { ["id": $0.id, "type": $0.type, "session": $0.session ?? NSNull(), "state": $0.state.rawValue, "born": $0.born, "last": $0.last, "until": $0.until ?? NSNull()] as [String: Any] }
    }

    /// The fixture's event, or nil when it is not an object, has no time that is a number, or is of a type the app does not have.
    static func event(_ raw: Any?) -> K.Event? {
        guard let e = raw as? [String: Any], let t = number(e["t"]) else { return nil }
        let kind = (e["type"] as? String).flatMap { K.Kind(rawValue: $0) } ?? .tick   // an unknown type only brings the time
        return K.Event(kind: kind, t: t, id: e["id"] as? String, agentType: e["agentType"] as? String, session: e["session"] as? String, tool: e["tool"] as? String)
    }

    @MainActor static func main() {
        let fx = CT.fixture("kitten-cases.json")

        CT.section("the frozen values: the limits, the four states and the places")
        let limits = fx["limits"] as! [String: Any]
        CT.check("at most 8 kittens per agent", K.max, limits["max"] as! Int)
        CT.checkNear("a farewell lasts 600 ms", K.leaveMs, number(limits["leaveMs"])!)
        CT.checkNear("a kitten whose stop never came goes with the sleep timer: ten minutes", CatRules.sleepAfterMs, number(limits["sleepAfterMs"])!)
        CT.check("the four states", K.State.allCases.map(\.rawValue), fx["states"] as! [String])
        CT.check("the cat state each shows: its own, and a happy finished while it leaves", K.State.allCases.map(\.catState), [.working, .searching, .approval, .finished])
        var diffs: [String] = []
        for (name, want) in fx["places"] as! [String: [String: Any]] {
            guard let p = K.places[name] else { diffs.append("\(name): missing"); continue }
            var got: [String: Any] = ["unit": p.unit, "max": p.max]
            for (key, value) in [("d", p.d), ("x0", p.x0), ("y0", p.y0), ("step", p.step), ("moreSize", p.moreSize)] where want[key] != nil { got[key] = value }
            if want["align"] != nil { got["align"] = p.centred ? "center" : "start" }
            if want["moreAt"] != nil { got["moreAt"] = p.moreAt }
            if let l = p.label { got["label"] = ["x": l.x, "y": l.y, "size": l.size] }
            let d = CT.diffs(got, want)
            if !d.isEmpty { diffs.append("\(name): \(d.first!)") }
        }
        CT.check("the five places", Set(K.places.keys), Set((fx["places"] as! [String: Any]).keys))
        CT.checkRows("every place's numbers are the fixture's", diffs)

        CT.section("kittenStep: \(rows(fx["scripts"]).count) scripts, one event at a time, the whole list compared after each")
        diffs = []
        var steps = 0
        for script in rows(fx["scripts"]) {
            var list = kittens(script["from"])
            for (n, step) in rows(script["steps"]).enumerated() {
                list = event(step["ev"]).map { K.step(list, $0) } ?? K.clean(list)
                steps += 1
                let d = CT.diffs(json(list), step["list"]!)
                if !d.isEmpty { diffs.append("\(script["name"]!), step \(n + 1): \(d.first!)"); break }
            }
        }
        CT.checkRows("every step of all \(rows(fx["scripts"]).count) scripts (\(steps) events) leaves the list the fixture says", diffs)

        CT.section("kittenOrder, kittenView and cleanKittens")
        diffs = []
        for r in rows(fx["order"]) {
            let got = K.order(kittens(r["list"])).map(\.id), want = r["out"] as! [String]
            if got != want { diffs.append("\(r["name"]!): \(got)") }
        }
        CT.checkRows("order: an approval first, then the newest (\(rows(fx["order"]).count) rows)", diffs)
        diffs = []
        for r in rows(fx["views"]) {
            let got = K.view(kittens(r["list"]), now: number(r["now"]) ?? .nan).map(\.id), want = r["out"] as! [String]
            if got != want { diffs.append("\(r["name"]!): \(got)") }
        }
        CT.checkRows("view: a leaving kitten is hidden from its time, and a time that is not a number hides nothing (\(rows(fx["views"]).count) rows)", diffs)
        diffs = []
        for r in rows(fx["cleans"]) {
            let d = CT.diffs(json(K.clean(kittens(r["raw"]))), r["out"]!)
            if !d.isEmpty { diffs.append("\(r["name"]!): \(d.first!)") }
        }
        CT.checkRows("clean (\(rows(fx["cleans"]).count) rows)", diffs)

        CT.section("kittenPlaceOf and kittenSlots: \(rows(fx["placeOf"]).count) places of a mode, \(rows(fx["slots"]).count) slot rows")
        diffs = []
        for r in rows(fx["placeOf"]) {
            let got = K.placeOf(CatDisplaySettings.modeOf(r["mode"]), expanded: r["expanded"] as! Bool)
            if got != r["out"] as! String { diffs.append("\(r["mode"]!) \(r["expanded"]!): \(got)") }
        }
        CT.checkRows("the place for the big cat and cat 2, in every mode (an unknown mode is One cat)", diffs)
        diffs = []
        for r in rows(fx["slots"]) {
            // the loose kittens of the fixture: an entry that is not an object or has no text id is skipped, and a state that is not text is working
            let loose: [K.Kitten] = (r["kittens"] as? [Any] ?? []).compactMap { entry in
                guard let k = entry as? [String: Any], let id = k["id"] as? String else { return nil }
                return K.Kitten(id: id, state: (k["state"] as? String).flatMap { K.State(rawValue: $0) } ?? .working, born: 0, last: 0)
            }
            let place = r["place"].map { ($0 as? String) ?? "\($0)" } ?? "nil"
            let d = CT.diffs(K.slots(place, loose).json, r["out"]!)
            if !d.isEmpty { diffs.append("\(r["name"]!): \(d.first!)") }
        }
        CT.checkRows("every slot row comes out as the fixture says (the label of the pair, the overflow, an unknown place shows nothing)", diffs)

        CT.section("a time that is not finite (JSON cannot write it): the event changes nothing, not even the leaving kittens that are due")
        let list = [K.Kitten(id: "a", state: .working, born: 1, last: 1), K.Kitten(id: "b", state: .leaving, born: 2, last: 2, until: 5)]
        for bad in [Double.nan, .infinity, -.infinity] {
            CT.check("start, stop, end, sweep and tick at \(bad)", [K.step(list, .start(id: "c", t: bad)), K.step(list, .stop(id: "a", t: bad)), K.step(list, .end(t: bad)), K.step(list, .sweep(t: bad)), K.step(list, .tick(t: bad))], Array(repeating: list, count: 5))
        }
        CT.check("a due leaving kitten goes at the next event of any kind", K.step(list, .tick(t: 6)).map(\.id), ["a"])
        CT.check("and stays until its time", K.step(list, .tick(t: 4)).map(\.id), ["a", "b"])
        CT.check("the view hides a kitten from its time without any event", K.view(list, now: 5).map(\.id), ["a"])

        CT.section("what the app sends: a Claude Code that sends no agent_id, a stop twice, a start after the stop, two sessions in one pill")
        var l: [K.Kitten] = []
        l = K.step(l, .start(id: "s1", agentType: "Explore", session: "A", t: 1))
        l = K.step(l, .tool(id: nil, tool: "Grep", t: 2))
        CT.check("a tool event with no agent_id belongs to the parent: the kitten stays as it was", l.map { [$0.id, $0.state.rawValue] }, [["s1", "working"]])
        l = K.step(l, .tool(id: "s1", tool: "WebSearch", t: 3))
        CT.check("a search tool is searching, and the next tool of another kind is working", [l[0].state.rawValue, K.step(l, .tool(id: "s1", tool: "Edit", t: 4))[0].state.rawValue], ["searching", "working"])
        l = K.step(l, .permission(id: "s1", t: 5))
        CT.check("a permission request is an approval, and it is first in the order", [l[0].state.rawValue, K.order(K.step(l, .start(id: "s2", t: 6))).map(\.id).first ?? ""], ["approval", "s1"])
        l = K.step(l, .stop(id: "s1", t: 10))
        let stopped = K.step(l, .stop(id: "s1", t: 20))
        CT.check("a second stop for a kitten that is leaving changes nothing", stopped, l)
        CT.check("a start after the stop is a new kitten", K.step(l, .start(id: "s1", t: 11)).map { [$0.id, $0.state.rawValue, "\($0.born)"] }, [["s1", "working", "11.0"]])
        var two = K.step(K.step([], .start(id: "a1", session: "A", t: 1)), .start(id: "b1", session: "B", t: 2))
        two = K.step(two, .start(id: "n1", t: 3))
        CT.check("one session ending takes its kittens and those with no session, and leaves the other session's", K.step(two, .end(session: "A", t: 4)).map(\.id), ["b1"])

        CT.section("the list keeps its rules whatever arrives: at most 8, no repeats, a leaving kitten has a time, nothing the events did not start")
        var rng = CatRNG(seed: 21), bad: [String] = []
        let ids = ["a", "b", "c", "d", "e", "f", "g", "h", "i", "j", "k", "", String(repeating: "x", count: 129)], sessions: [String?] = [nil, "A", "B", ""]
        var t = 0.0
        var fuzz: [K.Kitten] = []
        for n in 0..<4000 {
            t += rng.next() < 0.1 ? 700 : rng.next() * 40
            let id = ids[Int(rng.next() * Double(ids.count))], session = sessions[Int(rng.next() * Double(sessions.count))]
            let ev: K.Event
            switch Int(rng.next() * 9) {
            case 0: ev = .start(id: id, agentType: String(repeating: "t", count: Int(rng.next() * 100)), session: session, t: t)
            case 1: ev = .tool(id: id, tool: rng.next() < 0.5 ? "Grep" : "Edit", t: t)
            case 2: ev = .permission(id: id, t: t)
            case 3: ev = .resolved(id: id, t: t)
            case 4: ev = .stop(id: id, t: t)
            case 5: ev = .end(session: session, t: t)
            case 6: ev = .sweep(t: t + (rng.next() < 0.05 ? 700_000 : 0))
            case 7: ev = .tick(t: t)
            default: ev = .start(id: id, session: session, t: t)
            }
            fuzz = K.step(fuzz, ev)
            if fuzz.count > K.max { bad.append("event \(n): \(fuzz.count) kittens") }
            if Set(fuzz.map(\.id)).count != fuzz.count { bad.append("event \(n): an id twice") }
            if fuzz.contains(where: { $0.state == .leaving && $0.until == nil || $0.state != .leaving && $0.until != nil }) { bad.append("event \(n): a leaving kitten with no time, or a time without leaving") }
            if fuzz.contains(where: { !K.isKittenId($0.id) || !$0.born.isFinite || !$0.last.isFinite }) { bad.append("event \(n): a kitten that is not one") }
            if K.step(fuzz, .tick(t: t)) != fuzz.filter({ $0.state != .leaving || ($0.until ?? 0) > t }) { bad.append("event \(n): a tick changed more than the due kittens") }
            if bad.count > 5 { break }
        }
        CT.checkRows("4000 events from a seeded source", bad)

        CT.section("a kitten layer may stop asking for frames only when nothing is left to show and the frame on screen is empty")
        let farewell = [K.Kitten(id: "gone", state: .leaving, born: 1, last: 2, until: 5)], working = [K.Kitten(id: "w", state: .working, born: 1, last: 1)]
        CT.check("a kitten that is working: no", K.mayStop(lastFrameEmpty: true, lists: [working], now: 100), false)
        CT.check("a farewell that is not over: no", K.mayStop(lastFrameEmpty: true, lists: [farewell], now: 4), false)
        CT.check("a farewell that is over, though the list keeps it until the next event: yes", K.mayStop(lastFrameEmpty: true, lists: [farewell], now: 5), true)
        CT.check("no list, or lists with nothing in them: yes", [K.mayStop(lastFrameEmpty: true, lists: [], now: 0), K.mayStop(lastFrameEmpty: true, lists: [[], []], now: 0)], [true, true])
        CT.check("the frame on screen still shows a kitten: not yet, whatever the lists hold now", K.mayStop(lastFrameEmpty: false, lists: [farewell], now: 9), false)
        CT.check("two pills, one of them with a working kitten: no", K.mayStop(lastFrameEmpty: true, lists: [farewell, working], now: 9), false)
        CT.check("a time that is not finite hides nothing, so a farewell is still shown: no", K.mayStop(lastFrameEmpty: true, lists: [farewell], now: .nan), false)

        CT.finish()
    }
}
