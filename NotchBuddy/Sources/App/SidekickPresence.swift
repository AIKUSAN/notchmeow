import Foundation

// Is the user at the computer, and may a note show now. Port of `presenceStep` and `shouldShow` in `shared/sidekick-core.js` (the tie-breaker); tests/fixtures/sidekick/presence-cases.json and
// show-cases.json pin them and docs/SIDEKICK-CONTRACT.md explains them. The user is AWAY while any reason holds (the screen is locked, the Mac sleeps, the display is off, or 300 s without
// input), and BACK when the last reason lets go. Both rules are given every time they need and read no clock. Pure Foundation.

struct SKPresence: Equatable, Sendable {
    /// The reasons that hold now, in the frozen order: lock, sleep, display, idle.
    var reasons: [String] = []
    var awaySince: Double? = nil
    var wasAway = false
    var isAway: Bool { !reasons.isEmpty }
}

enum SKSignal: Equatable, Sendable {
    case lock, unlock, sleep, wake, displayOff, displayOn
    /// The OS's seconds since the last input.
    case idle(seconds: Double)
}

struct SKBack: Equatable, Sendable {
    var awaySince: Double
    var awayMs: Double
}

enum SidekickPresence {
    static let order = ["lock", "sleep", "display", "idle"]
    /// 300 s without input is away; a sample under 3 s is back. The samples in between change nothing.
    static let awaySeconds = 300.0, backSeconds = 3.0

    /// Whether the user is away, from the signals the OS gives. `signal` nil is a signal nobody knows: it changes nothing. A time that is not finite changes nothing either.
    /// Returns the new state and, once, when the last reason lets go, `back`.
    static func step(_ state: SKPresence, _ signal: SKSignal?, now: Double) -> (state: SKPresence, back: SKBack?) {
        var reasons = Set(state.reasons.filter(order.contains))
        var since = state.awaySince.flatMap { $0.isFinite ? $0 : nil }
        let was = !reasons.isEmpty
        func keep() -> (SKPresence, SKBack?) { (SKPresence(reasons: order.filter(reasons.contains), awaySince: reasons.isEmpty ? nil : since, wasAway: was), nil) }
        guard now.isFinite, let signal else { return keep() }
        var began = now
        var isIdle = false
        switch signal {
        case .lock: reasons.insert("lock")
        case .unlock: reasons.remove("lock")
        case .sleep: reasons.insert("sleep")
        case .wake: reasons.remove("sleep")
        case .displayOff: reasons.insert("display")
        case .displayOn: reasons.remove("display")
        case .idle(let seconds):
            guard seconds.isFinite else { return keep() }
            isIdle = true
            if seconds >= awaySeconds { reasons.insert("idle"); began = now - seconds * 1000 }
            else if seconds >= 0 && seconds < backSeconds { reasons.remove("idle") }
        }
        let isAway = !reasons.isEmpty
        if isAway { since = !was || since == nil ? began : (isIdle && reasons.contains("idle") ? min(since!, began) : since) }
        if was && !isAway {
            let start = since ?? now
            return (SKPresence(reasons: [], awaySince: nil, wasAway: true), SKBack(awaySince: start, awayMs: now - start))
        }
        return (SKPresence(reasons: order.filter(reasons.contains), awaySince: isAway ? since : nil, wasAway: was), nil)
    }
}

/// What the Mac's own notifications say, kept as flags and turned into events only when something CHANGES, so two notifications for one lock (the screen lock and the session switch) are one
/// lock, and one of them letting go does not unlock while the other still holds. `PresenceMonitor` (the app's side) feeds it; the desktop cat and the sidekick both read the events.
struct SKPresenceFlags: Equatable, Sendable {
    enum Source: Sendable { case screenLock, session, display, system }
    enum Event: Equatable, Sendable {
        case lock, unlock, displayOff, displayOn, sleep, wake

        var signal: SKSignal {
            switch self {
            case .lock: return .lock
            case .unlock: return .unlock
            case .displayOff: return .displayOff
            case .displayOn: return .displayOn
            case .sleep: return .sleep
            case .wake: return .wake
            }
        }
    }

    private(set) var screenLock = false, session = false, display = false, system = false
    /// The screen is locked, or the session was switched away (fast user switching).
    var locked: Bool { screenLock || session }
    /// The screens are asleep.
    var displayOff: Bool { display }
    /// The Mac is asleep.
    var asleep: Bool { system }

    /// One notification. Returns the event only when the answer changed.
    mutating func set(_ source: Source, _ on: Bool) -> Event? {
        let wasLocked = locked
        switch source {
        case .screenLock: screenLock = on
        case .session: session = on
        case .display:
            guard display != on else { return nil }
            display = on
            return on ? .displayOff : .displayOn
        case .system:
            guard system != on else { return nil }
            system = on
            return on ? .sleep : .wake
        }
        return locked == wasLocked ? nil : (locked ? .lock : .unlock)
    }
}

/// When the OS is asked how long the user has been idle. It is not a poll of its own: the answer is read on a tick the island already has, on a hook event and on an unlock, and only
/// while an agent has a live session (nothing to recap or nudge otherwise). Every 5 s at most, and every 1 s while the user is away by idle, so a return is noticed at once.
enum SidekickIdle {
    static let normalMs = 5000.0, awayMs = 1000.0

    static func sampleDue(now: Double, last: Double?, liveSessions: Bool, idleAway: Bool) -> Bool {
        guard liveSessions, now.isFinite else { return false }
        guard let last, last.isFinite, last <= now else { return true }
        return now - last >= (idleAway ? awayMs : normalMs)
    }
}

struct SKShowInput: Equatable, Sendable {
    /// The Sidekick switch ("Recaps and nudges"): off means nothing shows.
    var on = true
    var kind = ""
    var dismissals: [String: Int] = SidekickSettings.zeros
    var away = false
    var ratelimit = false
    /// "approval" or "question": a card is in front of the island.
    var card: String? = nil
    /// The waiting nudge's own card is on screen.
    var ownCard = false
    var inputFocused = false
    /// The note on screen now: its kind, and whether the user has seen it.
    var visible: Visible? = nil
    var lastShownAt: Double? = nil
    var now: Double? = nil
    var nudged = false
    var recapGiven = false

    struct Visible: Equatable, Sendable { var kind: String?; var seen: Bool }
}

struct SKShowDecision: Equatable, Sendable {
    var show: Bool
    /// "ok", or the first thing that says no: off, kind, muted, away, ratelimit, card, typing, busy, recent, nudged, recapGiven.
    var reason: String
    /// The note shown replaces a nudge nobody has seen.
    var replace: Bool
    var json: [String: Any] { ["show": show, "reason": reason, "replace": replace] }
}

enum SidekickGate {
    static let holdMs: [String: Double] = ["nudge": 30000, "recap": 2 * SK.minute]
    static let noteGapMs = 60000.0

    /// How long a refused note is kept, waiting for the gate to open: 30 s for a nudge, 2 minutes for a recap.
    static func hold(for kind: String) -> Double { kind == "recap" ? holdMs["recap"]! : holdMs["nudge"]! }

    /// Whether a note (a recap or a nudge) may show now. The reasons are tried in this order: off, kind, muted, away (a recap waits for the return, and so does a nudge), ratelimit (a stuck nudge
    /// only), card (an approval or a question is in front; for the waiting nudge its own card must not be on screen), typing, busy (another note is visible, unless it is a nudge nobody has seen and
    /// this is the recap, which replaces it), recent (a note showed in the last 60 s; the recap goes first), nudged, recapGiven.
    static func shouldShow(_ i: SKShowInput) -> SKShowDecision {
        func no(_ reason: String) -> SKShowDecision { SKShowDecision(show: false, reason: reason, replace: false) }
        if !i.on { return no("off") }
        if !SidekickSettings.kinds.contains(i.kind) { return no("kind") }
        if SidekickSettings.cleanDismissals(i.dismissals)[i.kind, default: 0] >= SidekickSettings.muteAt { return no("muted") }
        let recap = i.kind == "recap"
        if i.away { return no("away") }
        if !recap && i.ratelimit { return no("ratelimit") }
        if i.kind == "stuck.waiting" ? i.ownCard : (i.card == "approval" || i.card == "question") { return no("card") }
        if i.inputFocused { return no("typing") }
        var replace = false
        if let v = i.visible {
            if recap, let k = v.kind, k != "recap", !v.seen { replace = true } else { return no("busy") }
        }
        if !recap, let last = i.lastShownAt, let now = i.now, last.isFinite, now.isFinite, now - last < noteGapMs { return no("recent") }
        if !recap && i.nudged { return no("nudged") }
        if recap && i.recapGiven { return no("recapGiven") }
        return SKShowDecision(show: true, reason: "ok", replace: replace)
    }
}
