import Foundation

// Subagents shown as kittens beside their parent. Each agent pill keeps a list of kittens and `CatKittens.step` is the one reducer that changes it; the rest says what
// to draw (`view`, `order`) and where (`slots`, `placeOf`). Port of the "Kittens" section of design/prototype/cat-core.js (the tie-breaker);
// tests/fixtures/cat/kitten-cases.json pins it. It is pure: the time is in the event (ms on any one clock), nothing is read from a clock, nothing is changed in place, and
// nothing runs by itself: a leaving kitten is dropped by the next event and `view` hides it from its `until` on, so a hidden island costs nothing. Kittens are never stored.
// Foundation only.

enum CatKittens {
    /// At most this many kittens are tracked per agent; when a ninth starts, the oldest (by `born`) is dropped.
    static let max = 8
    /// A kitten that has stopped plays a happy blink for this long (ms), then goes.
    static let leaveMs = 600.0

    enum State: String, CaseIterable, Sendable {
        case working, searching, approval, leaving

        /// The state a kitten's cat shows: its own, and a happy `finished` while it leaves (the farewell).
        var catState: CatState {
            switch self {
            case .working: return .working
            case .searching: return .searching
            case .approval: return .approval
            case .leaving: return .finished
            }
        }
    }

    /// One subagent: its `agent_id`, its `agent_type`, the session it belongs to (nil when the hook did not say), its state, the times of its start and its last event, and,
    /// once it is leaving, the time it is removed.
    struct Kitten: Equatable, Sendable {
        var id: String
        var type = ""
        var session: String?
        var state = State.working
        var born: Double
        var last: Double
        var until: Double?
    }

    /// The hook events that change a list. `start` is SubagentStart; `tool` a Pre or PostToolUse with an agent_id; `permission` a PermissionRequest from a subagent and
    /// `resolved` its answer; `stop` SubagentStop; `end` the parent's Stop or the session's end (every kitten, or one session's); `sweep` the cat's sleep timer firing;
    /// `tick` only the time.
    enum Kind: String, Sendable { case start, tool, permission, resolved, stop, end, sweep, tick }

    struct Event: Sendable {
        var kind: Kind
        /// ms, on the one clock every event uses. An event whose time is not finite changes nothing.
        var t: Double
        var id: String?
        var agentType: String?
        var session: String?
        var tool: String?

        static func start(id: String?, agentType: String? = nil, session: String? = nil, t: Double) -> Event { Event(kind: .start, t: t, id: id, agentType: agentType, session: session) }
        static func tool(id: String?, tool: String?, t: Double) -> Event { Event(kind: .tool, t: t, id: id, tool: tool) }
        static func permission(id: String?, t: Double) -> Event { Event(kind: .permission, t: t, id: id) }
        static func resolved(id: String?, t: Double) -> Event { Event(kind: .resolved, t: t, id: id) }
        static func stop(id: String?, t: Double) -> Event { Event(kind: .stop, t: t, id: id) }
        static func end(session: String? = nil, t: Double) -> Event { Event(kind: .end, t: t, session: session) }
        static func sweep(t: Double) -> Event { Event(kind: .sweep, t: t) }
        static func tick(t: Double) -> Event { Event(kind: .tick, t: t) }
    }

    // MARK: Cleaning

    /// An agent_id (or a session ID) is text, not empty and at most 128 characters.
    static func isKittenId(_ v: String?) -> Bool { v.map { !$0.isEmpty && $0.count <= 128 } ?? false }
    private static func typeOfAgent(_ v: String?) -> String { v.map { String($0.prefix(64)) } ?? "" }
    private static func sessionOf(_ v: String?) -> String? { isKittenId(v) ? v : nil }

    /// A kitten list as an app may hold it, made safe: entries that repeat an id (the first wins), have no valid id or a time that is not finite are dropped, a type is
    /// cut at 64 characters, a session that is not an ID is none, and only a leaving kitten has a time to go (`until`).
    static func clean(_ list: [Kitten]) -> [Kitten] {
        var out: [Kitten] = [], seen = Set<String>()
        for k in list where isKittenId(k.id) && !seen.contains(k.id) && k.born.isFinite && k.last.isFinite {
            seen.insert(k.id)
            out.append(Kitten(id: k.id, type: typeOfAgent(k.type), session: sessionOf(k.session), state: k.state, born: k.born, last: k.last, until: k.state == .leaving && (k.until?.isFinite ?? false) ? k.until : nil))
        }
        return out
    }

    private static func cap(_ list: inout [Kitten]) {
        while list.count > max {
            var oldest = 0
            for i in 1..<list.count where list[i].born < list[oldest].born { oldest = i }
            list.remove(at: oldest)
        }
    }

    // MARK: The reducer

    /// The reducer. `list` is one pill's kittens, the result a new list. Every event first drops the leaving kittens whose time is up. An event for an id with no kitten, or
    /// for a kitten that is already leaving, changes nothing: a late tool event must not bring back a kitten that has gone, and without a SubagentStart there is nothing to
    /// show. An event with a time that is not finite returns the list as it is (cleaned). A repeated `start` for an id that is there only refreshes it. `end` with a
    /// session takes only that session's kittens and the ones with no session (two sessions of one agent share a pill); without one it takes every kitten. `sweep` takes a
    /// kitten whose last event is ten minutes or more old (its stop never came). Never throws.
    static func step(_ list: [Kitten], _ ev: Event) -> [Kitten] {
        var l = clean(list)
        guard ev.t.isFinite else { return l }
        let t = ev.t
        func active(_ id: String?) -> Int? { id.flatMap { id in l.firstIndex { $0.id == id && $0.state != .leaving } } }
        l = l.filter { $0.state != .leaving || ($0.until ?? 0) > t }
        switch ev.kind {
        case .start:
            guard isKittenId(ev.id), let id = ev.id else { break }
            if let i = l.firstIndex(where: { $0.id == id }) {
                if l[i].state != .leaving {
                    l[i].last = t
                    let type = typeOfAgent(ev.agentType)
                    if !type.isEmpty { l[i].type = type }
                    if let s = sessionOf(ev.session) { l[i].session = s }
                    break
                }
                l.remove(at: i)
            }
            l.append(Kitten(id: id, type: typeOfAgent(ev.agentType), session: sessionOf(ev.session), state: .working, born: t, last: t, until: nil))
            cap(&l)
        case .tool:
            if let i = active(ev.id) { l[i].state = CatRules.toolState(ev.tool) == .searching ? .searching : .working; l[i].last = t }
        case .permission:
            if let i = active(ev.id) { l[i].state = .approval; l[i].last = t }
        case .resolved:
            if let i = active(ev.id) { if l[i].state == .approval { l[i].state = .working }; l[i].last = t }
        case .stop:
            if let i = active(ev.id) { l[i].state = .leaving; l[i].last = t; l[i].until = t + leaveMs }
        case .end:
            if let q = sessionOf(ev.session) { l = l.filter { $0.session != nil && $0.session != q } } else { l = [] }
        case .sweep:
            l = l.filter { t - $0.last < CatRules.sleepAfterMs }
        case .tick: break
        }
        return l
    }

    // MARK: What to draw

    /// The order kittens are shown in: a kitten waiting on an approval first, then the newest (by `born`; a later place in the list first when they tie).
    static func order(_ list: [Kitten]) -> [Kitten] {
        clean(list).enumerated().sorted { a, b in
            if (a.element.state == .approval) != (b.element.state == .approval) { return a.element.state == .approval }
            if a.element.born != b.element.born { return a.element.born > b.element.born }
            return a.offset > b.offset
        }.map(\.element)
    }

    /// What is drawn at `now` (ms): the kittens in `order`, without a leaving kitten whose time is up. A `now` that is not finite hides nothing.
    static func view(_ list: [Kitten], now: Double) -> [Kitten] {
        order(clean(list).filter { $0.state != .leaving || !now.isFinite || ($0.until ?? 0) > now })
    }

    /// Whether a layer that draws these lists may stop asking for frames: the frame on screen is empty (`lastFrameEmpty`) and nothing is left to show at `now` (ms). A leaving kitten is dropped from its
    /// list only by the next event, so a list can still hold one whose farewell is over, and a layer that waited for its lists to be empty would draw nothing at 30 fps until the cat fell asleep.
    static func mayStop(lastFrameEmpty: Bool, lists: [[Kitten]], now: Double) -> Bool {
        lastFrameEmpty && lists.allSatisfy { view($0, now: now).isEmpty }
    }

    // MARK: Where they sit

    /// The places kittens go, and the numbers: every number is a multiple of a unit, `D` (the parent's head width, from its head centre, x right and y down) or `H` (the pill's
    /// height, from the pill's trailing edge, so x is negative inside it, and the middle of its height). The numbers are the brainstorm mockup's, divided by its parent's size.
    struct PlaceSpec: Equatable, Sendable {
        var unit: String
        var max: Int
        var d = 0.0, x0 = 0.0, y0 = 0.0, step = 0.0
        var centred = false
        /// Where the "+N" label is centred (default: the next slot after the last one drawn) and its text height.
        var moreAt: [Double]?
        var moreSize = 0.0
        /// The pair in the compact island has no room beside it: only a count "×N", drawn by cat 2 of the pair, at this spot.
        var label: (x: Double, y: Double, size: Double)?
        static func == (a: PlaceSpec, b: PlaceSpec) -> Bool {
            a.unit == b.unit && a.max == b.max && a.d == b.d && a.x0 == b.x0 && a.y0 == b.y0 && a.step == b.step && a.centred == b.centred && a.moreAt == b.moreAt && a.moreSize == b.moreSize
                && a.label?.x == b.label?.x && a.label?.y == b.label?.y && a.label?.size == b.label?.size
        }
    }
    static let places: [String: PlaceSpec] = [
        "bigExpanded": PlaceSpec(unit: "D", max: 3, d: 15.0 / 58, x0: 24.0 / 58, y0: 34.0 / 58, step: 18.0 / 58, moreSize: 0.2),
        "bigCompact": PlaceSpec(unit: "D", max: 2, d: 12.0 / 20, x0: 22.0 / 20, y0: 5.0 / 20, step: 13.0 / 20, moreAt: [42.0 / 20, -10.0 / 20], moreSize: 0.25),
        "pairCompact": PlaceSpec(unit: "D", max: 0, label: (1.1, 0.3, 0.5)),
        "pairExpanded": PlaceSpec(unit: "D", max: 3, d: 15.0 / 58, x0: 0, y0: 34.0 / 58, step: 18.0 / 58, centred: true, moreAt: [0, 50.0 / 58], moreSize: 0.2),
        "pill": PlaceSpec(unit: "H", max: 3, d: 15.0 / 28, x0: -17.5 / 28, y0: 0, step: -16.0 / 28, moreSize: 0.36),
    ]

    /// The place kittens go for the big cat (and, in Two cats mode, for cat 2): `bigExpanded` or `bigCompact`; in Two cats mode `pairExpanded` or `pairCompact`. An agent pill
    /// uses `pill`.
    static func placeOf(_ mode: CatDisplayMode, expanded: Bool) -> String { mode == .two ? (expanded ? "pairExpanded" : "pairCompact") : (expanded ? "bigExpanded" : "bigCompact") }

    struct Slot: Equatable, Sendable { var id: String; var state: String; var x: Double; var y: Double; var d: Double }
    struct More: Equatable, Sendable { var x: Double; var y: Double; var size: Double }
    struct Label: Equatable, Sendable { var text: String; var x: Double; var y: Double; var size: Double }
    /// `shown` the first `max` kittens, `more` how many are left over (the "+N"), `moreAt` where that label goes (nil when none is left over), `label` the pair's "×N" (nil
    /// unless the place has one and there is a kitten). An unknown place shows nothing.
    struct Slots: Equatable, Sendable {
        var place: String
        var unit: String?
        var count: Int
        var shown: [Slot]
        var more: Int
        var moreAt: More?
        var label: Label?

        /// As the fixtures hold it, a JSON-shaped dictionary.
        var json: [String: Any] {
            ["place": place, "unit": unit ?? NSNull(), "count": count, "shown": shown.map { ["id": $0.id, "state": $0.state, "x": $0.x, "y": $0.y, "d": $0.d] as [String: Any] }, "more": more,
             "moreAt": moreAt.map { ["x": $0.x, "y": $0.y, "size": $0.size] as [String: Any] } ?? NSNull(),
             "label": label.map { ["text": $0.text, "x": $0.x, "y": $0.y, "size": $0.size] as [String: Any] } ?? NSNull()]
        }
    }

    /// The slots for one parent's kittens in one place. `kittens` is what `view` returned (already in order).
    static func slots(_ place: String, _ kittens: [Kitten]) -> Slots {
        let list = kittens.filter { isKittenId($0.id) }, count = list.count
        guard let p = places[place] else { return Slots(place: place, unit: nil, count: count, shown: [], more: 0, moreAt: nil, label: nil) }
        let n = Swift.min(count, p.max), more = p.label != nil ? 0 : count - n
        func x(_ i: Int) -> Double { p.centred ? p.x0 + (Double(i) - Double(n - 1) / 2) * p.step : p.x0 + Double(i) * p.step }
        return Slots(place: place, unit: p.unit, count: count,
                     shown: list.prefix(n).enumerated().map { Slot(id: $1.id, state: $1.state.rawValue, x: x($0), y: p.y0, d: p.d) }, more: more,
                     moreAt: more > 0 ? More(x: p.moreAt?[0] ?? p.x0 + Double(p.max) * p.step, y: p.moreAt?[1] ?? p.y0, size: p.moreSize) : nil,
                     label: p.label.flatMap { count > 0 ? Label(text: "×\(count)", x: $0.x, y: $0.y, size: $0.size) : nil })
    }
}
