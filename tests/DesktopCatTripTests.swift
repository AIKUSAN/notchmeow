import Foundation

@main
enum DesktopCatTripTests {
    typealias T = DesktopCatTrip

    static func rows(_ x: Any?) -> [[String: Any]] { x as! [[String: Any]] }
    static func num(_ v: Any?) -> Double { (v as! NSNumber).doubleValue }
    static func step(_ r: (state: DesktopPhase, act: DesktopAct?)) -> [String: Any] { ["state": r.state.rawValue, "act": r.act?.rawValue ?? NSNull()] }
    static func spot(_ x: Double, _ y: Double) -> DesktopSpot { DesktopSpot(x: x, y: y) }

    /// The fixture's kittens, in the app's types: an entry that is not an object with a text id is not a kitten (the app never builds one); a state that is not text is working.
    static func kittens(_ raw: Any?) -> [CatKittens.Kitten] {
        (raw as? [Any] ?? []).compactMap { entry in
            guard let k = entry as? [String: Any], let id = k["id"] as? String else { return nil }
            return CatKittens.Kitten(id: id, state: (k["state"] as? String).flatMap { CatKittens.State(rawValue: $0) } ?? .working, born: 0, last: 0)
        }
    }

    @MainActor static func main() {
        let fx = CT.fixture("desktop-cases.json")

        CT.section("the frozen values: the seven phases, their table, the nine events, the eleven acts, the flight and the frame rates")
        CT.check("the phases, in order", DesktopPhase.allCases.map(\.rawValue), fx["phaseIds"] as! [String])
        var diffs: [String] = []
        let table = fx["phases"] as! [String: [String: Any]]
        for p in DesktopPhase.allCases {
            let row = table[p.rawValue]!
            let got: [String: Any] = ["flight": p.flight, "dir": p.dir?.rawValue ?? NSNull(), "drawn": p.drawn, "notchEmpty": p.notchEmpty, "on": p.on]
            let d = CT.diffs(got, row)
            if !d.isEmpty { diffs.append("\(p.rawValue): \(d.first!)") }
            if p.drawn && !p.notchEmpty { diffs.append("\(p.rawValue): two copies of one cat") }
        }
        CT.checkRows("what each phase means is the fixture's, and a drawn phase has an empty notch spot", diffs)
        CT.check("the acts, in order", DesktopAct.allCases.map(\.rawValue), fx["acts"] as! [String])
        CT.checkNear("the flight takes 600 ms", T.flightMs, num(fx["flightMs"]))
        let arc = fx["arc"] as! [String: Any]
        CT.check("the arc bows a quarter of the distance, at most 90 points", [T.arcLift, T.arcMax], [num(arc["lift"]), num(arc["max"])])
        let fps = fx["fps"] as! [String: Any]
        CT.check("the frame rates", [T.fpsMotion, T.fpsActive, T.fpsIdle, T.fpsAsleep, T.fpsOff], [num(fps["motion"]), num(fps["active"]), num(fps["idle"]), num(fps["asleep"]), num(fps["off"])])
        CT.checkNear("near is 150 points", T.near, num(fx["near"]))

        CT.section("desktopStep: \(rows(fx["steps"]).count) rows, every phase and event, and input that is neither")
        diffs = []
        for c in rows(fx["steps"]) {
            let d = CT.diffs(step(T.step(rawState: c["state"], rawEvent: c["event"])), c["out"]!)
            if !d.isEmpty { diffs.append("\(c["state"] ?? "nil") + \(c["event"] ?? "nil"): \(d.first!)") }
        }
        CT.checkRows("every step is as the fixture says", diffs)

        CT.section("trips: \(rows(fx["trips"]).count) scripts of events, the state and the act after each")
        for c in rows(fx["trips"]) {
            var s = DesktopPhase(rawValue: c["from"] as! String) ?? .home
            var got: [[String: Any]] = []
            for e in c["events"] as! [Any] { let r = T.step(rawState: s.rawValue, rawEvent: e); s = r.state; got.append(step(r)) }
            CT.checkJSON(c["name"] as! String, got: got, want: c["out"]!)
        }

        CT.section("the typed machine is the raw one: a spot that is NaN is not a spot")
        CT.checkJSON("a drag out with a NaN spot changes nothing", got: step(T.step(.home, .dragOut(spot(.nan, 1)))), want: step((.home, nil)))
        CT.checkJSON("so does a move to infinity", got: step(T.step(.onDesktop, .move(spot(.infinity, 1)))), want: step((.onDesktop, nil)))
        CT.checkJSON("a move to a real spot is the move act", got: step(T.step(.onDesktop, .move(spot(10, 20)))), want: step((.onDesktop, .move)))
        CT.checkTrue("an alert while the cat is home does not take it out", T.step(.home, .alertOn).act == nil && T.step(.home, .alertOn).state == .home)
        CT.checkTrue("an alert while it flies home does not turn it round", T.step(.flyingHome, .alertOn).state == .flyingHome)

        CT.section("desktopFlightAt: \(rows(fx["flights"]).count) points on the arc")
        diffs = []
        for c in rows(fx["flights"]) {
            let t: Double = (c["t"] as? NSNumber).map { CFGetTypeID($0) == CFBooleanGetTypeID() ? .nan : $0.doubleValue } ?? .nan   // text and null are not numbers: t is 0
            let p = T.flightAt(from: DesktopCatSpots.spot(c["from"]), to: DesktopCatSpots.spot(c["to"]), t: t)
            let d = CT.diffs(["x": p.x, "y": p.y, "scale": p.scale], c["out"]!)
            if !d.isEmpty { diffs.append("\(c["name"] as! String) at \(c["t"] ?? "nil"): \(d.first!)") }
        }
        CT.checkRows("every point is as the fixture says (eased, bowed upwards, full size)", diffs)
        CT.checkTrue("a t that is NaN is the start", T.flightAt(from: spot(10, 20), to: spot(100, 200), t: .nan).x == 10)
        CT.checkTrue("and infinity is the end", abs(T.flightAt(from: spot(10, 20), to: spot(100, 200), t: .infinity).x - 100) < 1e-9)
        var nonFinite: [String] = []
        for t in [0.0, 0.25, 1.0] {
            let to = spot(100, 200), zero = spot(0, 0)
            for bad in [spot(.nan, 5), spot(5, .infinity)] {
                let a = T.flightAt(from: bad, to: to, t: t), b = T.flightAt(from: zero, to: to, t: t)
                if [a.x, a.y, a.scale] != [b.x, b.y, b.scale] { nonFinite.append("from \(bad) at \(t)") }
                let c = T.flightAt(from: to, to: bad, t: t), d = T.flightAt(from: to, to: zero, t: t)
                if [c.x, c.y, c.scale] != [d.x, d.y, d.scale] { nonFinite.append("to \(bad) at \(t)") }
            }
        }
        CT.checkRows("a from or a to that is not finite counts as 0, 0 (the same point at t = 0, 0.25 and 1)", nonFinite)

        CT.section("the flight's clock: it runs 600 ms, a turn does not make the cat jump, and the notch end can move")
        let fl = T.Flight.start(.out, notch: spot(756, 16), desktop: spot(907, 328), at: 1000)
        CT.check("it starts at the notch", [fl.position(at: 1000).x, fl.position(at: 1000).y], [756, 16])
        CT.checkNear("and ends at the desktop spot", fl.position(at: 1600).x, 907)
        CT.check("progress is held to 0...1 and a clock that is NaN is the start", [fl.progress(at: 900), fl.progress(at: 1300), fl.progress(at: 9999), fl.progress(at: .nan)], [0, 0.5, 1, 0])
        CT.check("done at 600 ms and not before", [fl.isDone(at: 1599), fl.isDone(at: 1600)], [false, true])
        let inbound = T.Flight.start(.in, notch: spot(756, 16), desktop: spot(907, 328), at: 0)
        CT.check("the notch end of an out flight is its start, of an in flight its end", [fl.notchEnd, fl.desktopEnd, inbound.notchEnd], [spot(756, 16), spot(907, 328), spot(756, 16)])
        var worst = 0.0
        for ms in stride(from: 1000.0, through: 1600.0, by: 25) {
            let before = fl.position(at: ms), after = fl.turned(at: ms).position(at: ms)
            worst = max(worst, hypot(before.x - after.x, before.y - after.y))
        }
        CT.checkTrue("turned at any moment, the cat is exactly where it was (worst jump \(worst))", worst < 1e-9)
        let back = fl.turned(at: 1200)
        CT.check("a turned flight flies the other way", back.dir.rawValue, "in")
        CT.checkNear("and has the same time left to go as it had come (200 ms of 600 become 400 to go)", back.progress(at: 1200), 1 - fl.progress(at: 1200))
        CT.checkNear("it reaches the notch after the remaining time", back.position(at: 1200 + 0.2 * 600 * 2).x, 756, tol: 1e-6)
        CT.checkTrue("turned twice, it is the flight it was", fl.turned(at: 1200).turned(at: 1200).position(at: 1400).x - fl.position(at: 1400).x < 1e-9)
        let moved = fl.withNotchEnd(spot(700, 300))
        CT.check("the notch end moves and the desktop end stays", [moved.from, moved.to], [spot(700, 300), spot(907, 328)])
        CT.check("an in flight changes its end instead", inbound.withNotchEnd(spot(700, 300)).to, spot(700, 300))
        CT.check("the desktop end moves too (the screens changed) and the notch end stays", [fl.withDesktopEnd(spot(500, 500)).from, fl.withDesktopEnd(spot(500, 500)).to, inbound.withDesktopEnd(spot(500, 500)).from, inbound.withDesktopEnd(spot(500, 500)).to], [spot(756, 16), spot(500, 500), spot(500, 500), spot(756, 16)])
        let drop = T.Flight.home(from: spot(400, 400), notch: spot(756, 16), at: 50)
        CT.check("a cat dropped on the notch flies from the drop point, inwards", [drop.position(at: 50) == spot(400, 400), drop.dir == .in], [true, true])

        CT.section("what needs the user: an approval, a question, a chat's approval card, or a pill in approval or question state")
        CT.check("nothing", T.alert(pendingApproval: false, pendingQuestion: false, chatApproval: false, pillStates: [.idle, .working, .finished]), false)
        CT.check("an approval", T.alert(pendingApproval: true, pendingQuestion: false, chatApproval: false, pillStates: []), true)
        CT.check("a question", T.alert(pendingApproval: false, pendingQuestion: true, chatApproval: false, pillStates: []), true)
        CT.check("the Claude chat's Agent approval card", T.alert(pendingApproval: false, pendingQuestion: false, chatApproval: true, pillStates: []), true)
        CT.check("a pill in the approval state, with no card pending", T.alert(pendingApproval: false, pendingQuestion: false, chatApproval: false, pillStates: [.working, .approval]), true)
        CT.check("a pill that asks a question", T.alert(pendingApproval: false, pendingQuestion: false, chatApproval: false, pillStates: [.question]), true)
        CT.check("an error or a rate limit is not an alert", T.alert(pendingApproval: false, pendingQuestion: false, chatApproval: false, pillStates: [.error, .ratelimit, .dizzy]), false)

        CT.section("the file catch: a file on its way into the island is an alert, and the cat must be at the notch before the catch plays")
        CT.checkNear("a dropped file waits at most 1.5 s for the cat", T.catchWaitMs, num(fx["catchWaitMs"]))
        diffs = []
        for c in rows(fx["alertCases"]) where T.alert(raw: c["input"]) != (c["out"] as! Bool) { diffs.append(c["name"] as! String) }
        CT.checkRows("every alert case (\(rows(fx["alertCases"]).count) rows) is as the fixture says: a flag counts only when it is exactly true", diffs)
        diffs = []
        for c in rows(fx["offerCases"]) where T.alert(raw: c["input"]) != (c["out"] as! Bool) { diffs.append(c["name"] as! String) }
        CT.checkRows("every transfer-offer case (\(rows(fx["offerCases"]).count) rows, sub-project G2) is as the fixture says: a waiting Accept card is an alert", diffs)
        CT.check("the typed rule agrees: a waiting transfer offer alone is an alert, and without it nothing is", [T.alert(pendingApproval: false, pendingQuestion: false, chatApproval: false, pillStates: [], transferOffer: true), T.alert(pendingApproval: false, pendingQuestion: false, chatApproval: false, pillStates: [])], [true, false])
        diffs = []
        for c in rows(fx["catchReady"]) where T.catchReady(raw: c["phase"]) != (c["out"] as! Bool) { diffs.append("\(c["phase"] ?? "nil")") }
        CT.checkRows("every phase's readiness (\(rows(fx["catchReady"]).count) rows) is as the fixture says", diffs)
        CT.check("the cat is at the notch at home and while it waits there for an answer, nowhere else", DesktopPhase.allCases.filter { T.catchReady($0) }.map(\.rawValue), ["home", "atNotchForAlert"])
        CT.check("the island and the desktop never both draw: ready is exactly not drawn", DesktopPhase.allCases.allSatisfy { T.catchReady($0) == !$0.drawn }, true)
        CT.check("a file on its way in is an alert", T.alert(pendingApproval: false, pendingQuestion: false, chatApproval: false, pillStates: [], fileCatch: true), true)
        CT.check("a caller that does not know of files is as before", T.alert(pendingApproval: false, pendingQuestion: false, chatApproval: false, pillStates: [.idle]), false)
        CT.check("a file and an approval are one alert until both clear", [T.alert(pendingApproval: true, pendingQuestion: false, chatApproval: false, pillStates: [], fileCatch: false), T.alert(pendingApproval: false, pendingQuestion: false, chatApproval: false, pillStates: [], fileCatch: false)], [true, false])

        CT.section("desktopFps: \(rows(fx["fpsCases"]).count) rows")
        diffs = []
        for c in rows(fx["fpsCases"]) where T.fps(raw: c["input"]) != num(c["out"]) { diffs.append("\(c["name"] as! String): \(T.fps(raw: c["input"]))") }
        CT.checkRows("every rate is as the fixture says (only `true` counts for a flag, sleep beats the cursor, hidden beats everything)", diffs)
        CT.check("the typed rule: a cursor that is NaN is not near", T.fps(.init(phase: .onDesktop, cursorDist: .nan)), 5)
        CT.check("infinity is not near", T.fps(.init(phase: .onDesktop, cursorDist: .infinity)), 5)
        CT.check("150 points is near", T.fps(.init(phase: .onDesktop, cursorDist: 150)), 20)
        CT.check("a phase of nothing draws nothing", T.fps(.init(phase: nil, dragging: true)), 0)

        CT.section("the kittens' slots: \(rows(fx["kittenSlots"]).count) rows, and the same in points at each size")
        diffs = []
        for c in rows(fx["kittenSlots"]) {
            let side = (c["side"] as? NSNumber).flatMap { CFGetTypeID($0) == CFBooleanGetTypeID() ? nil : $0.intValue } ?? 1
            let d = CT.diffs(T.kittenSlots(kittens(c["kittens"]), side: side).json, c["out"]!)
            if !d.isEmpty { diffs.append("\(c["name"] as! String): \(d.first!)") }
        }
        CT.checkRows("every slot is as the fixture says (up to three, then +N, mirrored on the left; things that are not kittens are skipped)", diffs)
        diffs = []
        for c in rows(fx["kittenSizes"]) {
            let size = DesktopSize(rawValue: c["size"] as! String)!
            let slots = T.kittenSlots((0..<(c["count"] as! Int)).map { CatKittens.Kitten(id: "k\($0)", state: [.approval, .searching, .working][$0 % 3], born: 0, last: 0) }, side: 1)
            let got: [String: Any] = ["size": size.rawValue, "d": size.d, "count": slots.count,
                                      "shown": slots.shown.map { ["id": $0.id, "state": $0.state, "x": $0.x * size.d, "y": $0.y * size.d, "d": $0.d * size.d] as [String: Any] }, "more": slots.more,
                                      "moreAt": slots.moreAt.map { ["x": $0.x * size.d, "y": $0.y * size.d, "size": $0.size * size.d] as [String: Any] } ?? NSNull()]
            let d = CT.diffs(got, c)
            if !d.isEmpty { diffs.append("\(size.rawValue) \(c["count"] ?? ""): \(d.first!)") }
        }
        CT.checkRows("one table serves Ø48, Ø64 and Ø96", diffs)
        CT.check("B's table is untouched: the big cat's kittens are still where they were", CatKittens.places["bigExpanded"]?.max, 3)
        CT.check("and the desktop is not one of its places", CatKittens.places["desktop"] == nil, true)
        let ids = (0..<5).map { CatKittens.Kitten(id: "k\($0)", state: .working, born: 0, last: 0) }
        CT.checkTrue("on the left the whole row mirrors, the +N too", T.kittenSlots(ids, side: -1).moreAt!.x == -T.kittenSlots(ids, side: 1).moreAt!.x && T.kittenSlots(ids, side: -1).shown.allSatisfy { $0.x < 0 })
        CT.checkTrue("a kitten with an empty id is skipped", T.kittenSlots([CatKittens.Kitten(id: "", state: .working, born: 0, last: 0)], side: 1).count == 0)
        CT.finish()
    }
}
