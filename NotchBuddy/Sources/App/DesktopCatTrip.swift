import Foundation

// The desktop cat's trip (sub-project H): the seven phases and the one machine that moves between them, the flight between the notch and the desktop, the frame rate the cat
// aims for, and where its kittens sit. Port of "The desktop cat: the trip" and "size, frame rate and kittens" in design/prototype/cat-core.js (the tie-breaker);
// tests/fixtures/cat/desktop-cases.json pins it. Foundation only, pure, and nothing here throws. The app's side (windows, clocks, events) is `DesktopCatController`.

/// The phases of the trip. The raw values are frozen contract values, like the cat IDs.
enum DesktopPhase: String, CaseIterable, Sendable {
    case home, flyingOut, onDesktop, retracting, atNotchForAlert, returning, flyingHome

    /// Which way a flight goes: `out` towards the desktop spot, `in` towards the notch spot.
    enum Dir: String, Sendable { case out, `in` }

    /// The cat is in the air.
    var flight: Bool { dir != nil }
    var dir: Dir? {
        switch self {
        case .flyingOut, .returning: return .out
        case .retracting, .flyingHome: return .in
        case .home, .onDesktop, .atNotchForAlert: return nil
        }
    }
    /// The desktop window draws the cat.
    var drawn: Bool { self != .home && self != .atNotchForAlert }
    /// The big cat's spot in the notch is empty: never two copies of one cat (drawn implies notchEmpty).
    var notchEmpty: Bool { drawn }
    /// What Settings stores as "the cat is out": `home` and `flyingHome` are off, so quitting mid-flight leaves the cat home.
    var on: Bool {
        switch self {
        case .home, .flyingHome: return false
        case .flyingOut, .onDesktop, .retracting, .atNotchForAlert, .returning: return true
        }
    }
}

/// What the app does on a transition. `turn` reverses the flight in progress, `keep` lets it go on, and so on: see `docs/CAT-CONTRACT.md`, "The desktop cat (H-0)".
enum DesktopAct: String, CaseIterable, Sendable {
    case place, flyOut, flyHome, retract, turn, keep, land, dock, goHome, move, resettle
}

/// The events the machine takes. `dragOut` and `move` carry the spot (the head centre, y down).
enum DesktopEvent: Equatable, Sendable {
    case dragOut(DesktopSpot), move(DesktopSpot)
    case toggle, sendHome, alertOn, alertOff, flightDone, launch, screensChanged
}

enum DesktopCatTrip {
    // MARK: The machine

    /// phase → event → (next phase, act). An event that is not listed makes no sense in that phase and changes nothing.
    private static func next(_ s: DesktopPhase, _ e: DesktopEvent) -> (DesktopPhase, DesktopAct)? {
        switch (s, e) {
        case (.home, .dragOut): return (.onDesktop, .place)
        case (.home, .toggle), (.home, .launch): return (.flyingOut, .flyOut)

        case (.flyingOut, .toggle), (.flyingOut, .sendHome): return (.flyingHome, .turn)
        case (.flyingOut, .alertOn): return (.retracting, .turn)
        case (.flyingOut, .flightDone): return (.onDesktop, .land)
        case (.flyingOut, .screensChanged): return (.flyingOut, .resettle)

        case (.onDesktop, .move): return (.onDesktop, .move)
        case (.onDesktop, .toggle), (.onDesktop, .sendHome): return (.flyingHome, .flyHome)
        case (.onDesktop, .alertOn): return (.retracting, .retract)
        case (.onDesktop, .screensChanged): return (.onDesktop, .resettle)

        case (.retracting, .toggle), (.retracting, .sendHome): return (.flyingHome, .keep)
        case (.retracting, .alertOff): return (.returning, .turn)
        case (.retracting, .flightDone): return (.atNotchForAlert, .dock)

        case (.atNotchForAlert, .toggle), (.atNotchForAlert, .sendHome): return (.home, .goHome)
        case (.atNotchForAlert, .alertOff): return (.returning, .flyOut)

        case (.returning, .toggle), (.returning, .sendHome): return (.flyingHome, .turn)
        case (.returning, .alertOn): return (.retracting, .turn)
        case (.returning, .flightDone): return (.onDesktop, .land)
        case (.returning, .screensChanged): return (.returning, .resettle)

        case (.flyingHome, .toggle): return (.flyingOut, .turn)
        case (.flyingHome, .flightDone): return (.home, .dock)
        default: return nil
        }
    }

    /// The next phase and what the app does, or the same phase and `nil` when the event makes no sense there. A `dragOut` or `move` whose spot is not a spot changes nothing
    /// either. Pure, and it never throws.
    static func step(_ state: DesktopPhase, _ event: DesktopEvent) -> (state: DesktopPhase, act: DesktopAct?) {
        switch event {
        case .dragOut(let s), .move(let s): if !DesktopCatSpots.isValid(s) { return (state, nil) }
        default: break
        }
        guard let n = next(state, event) else { return (state, nil) }
        return (n.0, n.1)
    }

    /// The same machine for raw input (the fixtures, a notification's payload): a state that is not a phase counts as `home`; an event that is not an object with a known
    /// `type` changes nothing; `dragOut` and `move` need a valid `spot`.
    static func step(rawState: Any?, rawEvent: Any?) -> (state: DesktopPhase, act: DesktopAct?) {
        let s = (rawState as? String).flatMap { DesktopPhase(rawValue: $0) } ?? .home
        guard let e = event(rawEvent) else { return (s, nil) }
        return step(s, e)
    }

    static func event(_ raw: Any?) -> DesktopEvent? {
        guard let o = raw as? [String: Any], let type = o["type"] as? String else { return nil }
        switch type {
        case "dragOut": return DesktopCatSpots.spot(o["spot"]).map { .dragOut($0) }
        case "move": return DesktopCatSpots.spot(o["spot"]).map { .move($0) }
        case "toggle": return .toggle
        case "sendHome": return .sendHome
        case "alertOn": return .alertOn
        case "alertOff": return .alertOff
        case "flightDone": return .flightDone
        case "launch": return .launch
        case "screensChanged": return .screensChanged
        default: return nil
        }
    }

    // MARK: The flight

    /// The flight between the notch spot and the desktop spot takes this long (ms).
    static let flightMs = 600.0
    /// The arc bows `lift` of the distance away from the straight line, never more than `max` points, always upwards (a vertical flight bows to the right).
    static let arcLift = 0.25, arcMax = 90.0

    /// Where the cat is `t` (0 to 1, held to that range; NaN is 0) of the way along a flight: a quadratic arc eased in and out, with the cat at full size the whole way.
    /// The path is the same both ways: the position at `(from, to, t)` is the position at `(to, from, 1 - t)`, which is what makes a turn seamless.
    static func flightAt(from: DesktopSpot?, to: DesktopSpot?, t: Double) -> (x: Double, y: Double, scale: Double) {
        func ok(_ s: DesktopSpot?) -> DesktopSpot { s.flatMap { DesktopCatSpots.isValid($0) ? $0 : nil } ?? DesktopSpot(x: 0, y: 0) }
        let f = ok(from), g = ok(to)
        let k = t.isNaN ? 0 : min(max(t, 0), 1), q = CatEase.inOut.at(k)
        let dx = g.x - f.x, dy = g.y - f.y, len = hypot(dx, dy)
        var nx = 0.0, ny = 0.0
        if len > 0 {
            nx = dy / len; ny = -dx / len
            if ny > 0 || (ny == 0 && nx < 0) { nx = -nx; ny = -ny }
        }
        let lift = min(len * arcLift, arcMax), cx = (f.x + g.x) / 2 + nx * lift, cy = (f.y + g.y) / 2 + ny * lift, u = 1 - q
        return (u * u * f.x + 2 * u * q * cx + q * q * g.x, u * u * f.y + 2 * u * q * cy + q * q * g.y, 1)
    }

    /// A flight in progress: its ends, which way it goes and its clock. The app keeps one while the phase is a flight; `turned` and `withNotchEnd` are what `turn` and a change
    /// of the notch spot (compact or expanded) do to it.
    struct Flight: Equatable, Sendable {
        var from: DesktopSpot
        var to: DesktopSpot
        var dir: DesktopPhase.Dir
        /// On the clock the app reads (ms).
        var startMs: Double

        /// The flight as `out` or `in`: for `out` the notch is the start, for `in` it is the end.
        static func start(_ dir: DesktopPhase.Dir, notch: DesktopSpot, desktop: DesktopSpot, at ms: Double) -> Flight {
            dir == .out ? Flight(from: notch, to: desktop, dir: dir, startMs: ms) : Flight(from: desktop, to: notch, dir: dir, startMs: ms)
        }
        /// A flight that starts where the cat is on screen (a cat dropped on the notch flies the last bit from the drop point).
        static func home(from point: DesktopSpot, notch: DesktopSpot, at ms: Double) -> Flight { Flight(from: point, to: notch, dir: .in, startMs: ms) }

        var notchEnd: DesktopSpot { dir == .out ? from : to }
        var desktopEnd: DesktopSpot { dir == .out ? to : from }

        /// 0 to 1; a clock that is not a number is the start.
        func progress(at ms: Double) -> Double {
            let t = (ms - startMs) / DesktopCatTrip.flightMs
            return t.isNaN ? 0 : min(max(t, 0), 1)
        }
        func isDone(at ms: Double) -> Bool { progress(at: ms) >= 1 }
        func position(at ms: Double) -> DesktopSpot {
            let p = DesktopCatTrip.flightAt(from: from, to: to, t: progress(at: ms))
            return DesktopSpot(x: p.x, y: p.y)
        }
        /// `turn`: the flight keeps its clock, swaps its ends and carries on from progress `1 - t`, retracing its own path: the cat does not jump.
        func turned(at ms: Double) -> Flight {
            Flight(from: to, to: from, dir: dir == .out ? .in : .out, startMs: ms - (1 - progress(at: ms)) * DesktopCatTrip.flightMs)
        }
        /// The screens changed (`resettle`): the desktop end moves to the new spot and the notch end stays; the flight keeps its clock.
        func withDesktopEnd(_ spot: DesktopSpot) -> Flight {
            var f = self
            if dir == .out { f.to = spot } else { f.from = spot }
            return f
        }
        /// The notch spot moved (the island opened for an alert, or folded): the flight keeps its clock and its desktop end, and aims at the new notch end.
        func withNotchEnd(_ spot: DesktopSpot) -> Flight {
            var f = self
            if dir == .out { f.from = spot } else { f.to = spot }
            return f
        }
    }

    // MARK: Frame rate

    static let fpsMotion = 60.0, fpsActive = 20.0, fpsIdle = 5.0, fpsAsleep = 0.5, fpsOff = 0.0
    /// The cursor is "near" the cat within this many points of the cat's centre (inclusive).
    static let near = 150.0

    /// What the cat is doing. `phase` nil counts as not drawn. `cursorDist` is nil when the app cannot know it.
    struct FpsInput: Equatable, Sendable {
        var phase: DesktopPhase?
        var hidden = false, dragging = false, emote = false, kittenMotion = false, dance = false, asleep = false, working = false
        var cursorDist: Double?
    }

    /// The frame rate the app aims for, in this order: 0 when the phase is not drawn on the desktop or the cat cannot be seen (`hidden`); 60 for any motion (a flight
    /// included); 0.5 asleep (a still frame redrawn every 2 s); 20 working or with the cursor near; else 5. Sleep beats the cursor, and hidden beats everything.
    static func fps(_ i: FpsInput) -> Double {
        guard let phase = i.phase, phase.drawn, !i.hidden else { return fpsOff }
        if phase.flight || i.dragging || i.emote || i.kittenMotion || i.dance { return fpsMotion }
        if i.asleep { return fpsAsleep }
        if i.working || (i.cursorDist.map { $0.isFinite && $0 <= near } ?? false) { return fpsActive }
        return fpsIdle
    }

    /// The same rule for raw input: only `true` counts for a flag, and `cursorDist` only as a finite number; anything that is not an object, or has no phase, draws nothing.
    static func fps(raw: Any?) -> Double {
        guard let o = raw as? [String: Any] else { return fpsOff }
        func flag(_ k: String) -> Bool { DesktopCatSettings.isTrue(o[k]) }
        return fps(FpsInput(phase: (o["phase"] as? String).flatMap { DesktopPhase(rawValue: $0) }, hidden: flag("hidden"), dragging: flag("dragging"), emote: flag("emote"),
                            kittenMotion: flag("kittenMotion"), dance: flag("dance"), asleep: flag("asleep"), working: flag("working"), cursorDist: DesktopCatSpots.number(o["cursorDist"])))
    }

    // MARK: Alerts

    /// Whether something needs the user: a pending approval or question, a chat's approval card, any pill in the approval or question state, or a file on its way into the island
    /// (`fileCatch`: dragged over it, waiting for the cat, or its drop flow on screen). The cat flies into the notch while this is true and back out when it is not
    /// (`desktopAlert` in cat-core.js).
    static func alert(pendingApproval: Bool, pendingQuestion: Bool, chatApproval: Bool, pillStates: [CatState], fileCatch: Bool = false, transferOffer: Bool = false) -> Bool {
        pendingApproval || pendingQuestion || chatApproval || fileCatch || transferOffer || pillStates.contains { $0 == .approval || $0 == .question }
    }

    /// The same rule for raw input: a flag counts only when it is exactly `true`, `pillStates` only as a list of the state names `approval` and `question`, and anything that is not an
    /// object is no alert.
    static func alert(raw: Any?) -> Bool {
        guard let o = raw as? [String: Any] else { return false }
        func flag(_ k: String) -> Bool { DesktopCatSettings.isTrue(o[k]) }
        let pill = (o["pillStates"] as? [Any])?.contains { ($0 as? String) == "approval" || ($0 as? String) == "question" } ?? false
        return flag("approval") || flag("question") || flag("chatApproval") || flag("fileCatch") || flag("transferOffer") || pill
    }

    // MARK: The file catch

    /// How long a dropped file waits for the cat to be at the notch before the catch plays anyway (ms): `DESKTOP_CATCH_WAIT_MS`.
    static let catchWaitMs = 1500.0

    /// Whether the big cat is at the notch, so the island may draw it and a catch may play with it: the phases whose notch spot is not empty (`desktopCatchReady`).
    static func catchReady(_ phase: DesktopPhase) -> Bool { !phase.notchEmpty }
    /// The same for raw input: a value that is not a phase counts as home.
    static func catchReady(raw: Any?) -> Bool { catchReady((raw as? String).flatMap { DesktopPhase(rawValue: $0) } ?? .home) }

    // MARK: Kittens

    /// Where the desktop cat's kittens sit, in units of D (the head width, from the head centre, x right and y down): up to 3 of 0.3 D in a row at the lower right, then a "+N"
    /// at the next slot. A table of its own: `CatKittens.places` (which both apps copy and pin) is untouched.
    static let kittenMax = 3
    static let kittenD = 0.3, kittenX0 = 0.82, kittenY0 = 0.22, kittenStep = 0.33, kittenMoreSize = 0.2

    /// The slots for the cat's kittens (already in order). `side` -1 puts them on the left (a cat in the right half of its screen keeps them on screen); anything else is the right.
    static func kittenSlots(_ kittens: [CatKittens.Kitten], side: Int) -> CatKittens.Slots {
        let m = side == -1 ? -1.0 : 1.0
        let list = kittens.filter { CatKittens.isKittenId($0.id) }, count = list.count, n = min(count, kittenMax), more = count - n
        return CatKittens.Slots(
            place: "desktop", unit: "D", count: count,
            shown: list.prefix(n).enumerated().map { CatKittens.Slot(id: $1.id, state: $1.state.rawValue, x: m * (kittenX0 + Double($0) * kittenStep), y: kittenY0, d: kittenD) },
            more: more,
            moreAt: more > 0 ? CatKittens.More(x: m * (kittenX0 + Double(kittenMax) * kittenStep), y: kittenY0, size: kittenMoreSize) : nil,
            label: nil)
    }
}
