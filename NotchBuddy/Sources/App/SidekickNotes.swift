import Foundation

// The sidekick's notes and its one clock. A note (a recap or a nudge) that the show gate refuses is HELD, up to 30 s for a nudge and 2 minutes for a recap, and shown if the gate opens,
// then dropped silently; a note that shows stays up for a short time and then goes away without counting as a dismissal (folding the island unseen is not one). `SidekickNotes` is only the
// bookkeeping of that, as plain values; the rules that decide are `SidekickGate` (the show gate). `SidekickClock` is the ONE one-shot timer of the whole sidekick, in the pattern of
// `CatSleepClock`: it is set to the nearest of the deadlines the sidekick has (a stuck rule falls due, a held note runs out, a shown note's time is up), re-set whenever one of them changes,
// and not set at all when nothing is running, so a hidden island with no agent costs nothing. It takes its clock and its timer from outside, so a test moves both by hand. Foundation only.

struct SKNote: Equatable, Sendable, Identifiable {
    var id: Int
    /// recap, stuck.loop, stuck.errors, stuck.waiting or stuck.silent (the five kinds of dismissal).
    var kind: String
    var text: String
    /// The facts the text was made from (a recap's): the only thing the local voice may be given.
    var facts: [SKFacts] = []
    /// The ledger key of the session a nudge is about.
    var key: String? = nil
    /// The agent a nudge or a one-agent recap is about: "Show me" brings its app forward.
    var agentId: String? = nil
    /// The away period a recap is for.
    var awaySince: Double? = nil
    /// When the note was made (ms): a nudge about a session that has moved on since is stale.
    var createdAt: Double = 0

    var isRecap: Bool { kind == "recap" }

    private static let recapPrefix = "While you were away, "

    /// The rows the island's card shows. One sentence is one row (the card wraps it onto two lines). A recap of several agents is one row for each, the first with "While you were away, " and the others
    /// without it, and at most three rows: a longer recap is cut at the third row, which ends with an ellipsis. The words themselves are the template's, or the local voice's.
    var rows: [String] {
        let lines = text.components(separatedBy: "\n").filter { !$0.isEmpty }
        guard isRecap, lines.count > 1 else { return [text] }
        let agents = lines.filter { !$0.hasPrefix("+") }
        let more = lines.filter { $0.hasPrefix("+") }.compactMap { Int($0.dropFirst().split(separator: " ").first ?? "") }.reduce(0, +)
        func bare(_ l: String) -> String {
            guard l.hasPrefix(Self.recapPrefix), let c = l.dropFirst(Self.recapPrefix.count).first else { return l }
            return c.uppercased() + l.dropFirst(Self.recapPrefix.count + 1)
        }
        let shown = agents.enumerated().map { $0.offset == 0 ? $0.element : bare($0.element) }
        if shown.count <= 3 && more == 0 { return shown }
        // Cut at three rows (owner's answer, 2026-10-14): the third ends with an ellipsis and no count is given.
        var cut = Array(shown.prefix(3))
        var last = cut[cut.count - 1].trimmingCharacters(in: .whitespaces)
        while let end = last.last, end == "." || end == "…" { last.removeLast() }
        cut[cut.count - 1] = last + "…"
        return cut
    }
}

struct SidekickNotes: Equatable, Sendable {
    struct Held: Equatable, Sendable { var note: SKNote; var until: Double }
    struct Showing: Equatable, Sendable { var note: SKNote; var shownAt: Double; var expiresAt: Double; var seen: Bool }

    /// How long a note stays up once it shows, unless the user answers it first.
    static func showMs(for kind: String) -> Double { kind == "recap" ? 45000 : 20000 }

    var held: [Held] = []
    var showing: Showing? = nil
    var lastShownAt: Double? = nil
    /// The away period (its `awaySince`) whose recap was shown.
    var recapGivenFor: Double? = nil

    /// A note the gate may refuse is kept. A recap replaces a recap that is still held; a nudge for a session and kind that is already held or shown is not kept twice.
    mutating func offer(_ note: SKNote, now: Double) {
        if note.isRecap { held.removeAll { $0.note.isRecap } }
        else if held.contains(where: { $0.note.kind == note.kind && $0.note.key == note.key }) || (showing.map { $0.note.kind == note.kind && $0.note.key == note.key } ?? false) { return }
        held.append(Held(note: note, until: now + SidekickGate.hold(for: note.kind)))
    }

    /// The held notes whose time is up, taken out (a nudge that was never shown is not marked as given: the engine may offer it again).
    mutating func dropExpired(now: Double) -> [SKNote] {
        let gone = held.filter { now >= $0.until }.map(\.note)
        held.removeAll { now >= $0.until }
        return gone
    }

    /// The held notes in the order the gate is asked: a recap first, then the others as they came.
    var queue: [SKNote] { held.filter { $0.note.isRecap }.map(\.note) + held.filter { !$0.note.isRecap }.map(\.note) }

    /// What the gate needs to know about the note on screen.
    var visible: SKShowInput.Visible? { showing.map { SKShowInput.Visible(kind: $0.note.kind, seen: $0.seen) } }

    func recapGiven(for awaySince: Double?) -> Bool { awaySince != nil && recapGivenFor == awaySince }

    /// A held note shows now (it replaces the one on screen when the gate said so).
    mutating func show(_ id: Int, now: Double) -> SKNote? {
        guard let i = held.firstIndex(where: { $0.note.id == id }) else { return nil }
        let note = held.remove(at: i).note
        showing = Showing(note: note, shownAt: now, expiresAt: now + Self.showMs(for: note.kind), seen: false)
        lastShownAt = now
        if note.isRecap { recapGivenFor = note.awaySince }
        return note
    }

    /// The island is open on the note: the user has seen it.
    mutating func markSeen() { if showing != nil { showing!.seen = true } }

    /// The note on screen goes (answered, or its time is up). It returns the note; whether that counts as a dismissal is the caller's.
    mutating func retire() -> SKNote? {
        defer { showing = nil }
        return showing?.note
    }

    /// The note on screen has run out its time. Held back (false) while `holdOn` says the pointer is on it.
    func showingExpired(now: Double) -> Bool { showing.map { now >= $0.expiresAt } ?? false }

    /// The note on screen is kept a little longer (the pointer is on it).
    mutating func extendShowing(to at: Double) { if showing != nil { showing!.expiresAt = at } }

    /// A held note is dropped without ever showing (its kind is muted, or the switch is off).
    mutating func drop(_ id: Int) { held.removeAll { $0.note.id == id } }

    /// A nudge's words changed in place (the waiting nudge at the app's give-up time): it is not a second nudge.
    mutating func retext(kind: String, key: String?, text: String) {
        for i in held.indices where held[i].note.kind == kind && held[i].note.key == key { held[i].note.text = text }
        if showing?.note.kind == kind && showing?.note.key == key { showing!.note.text = text }
    }

    /// The nearer of two deadlines (nil is no deadline): the one-shot clock is set to the nearest deadline the sidekick has, from the stuck rules and from the notes.
    static func nearest(_ a: Double?, _ b: Double?) -> Double? { [a, b].compactMap { $0 }.min() }

    /// The nearest time something here must be looked at again: a held note runs out, or the note on screen has had its time. nil when there is nothing.
    var nextDeadline: Double? { (held.map(\.until) + (showing.map { [$0.expiresAt] } ?? [])).min() }
}

/// The one-shot timer. `set(at)` makes `at` (ms on the sidekick's clock) the only deadline: a different one cancels and replaces the timer, the same one leaves it alone, and nil cancels it.
@MainActor
final class SidekickClock {
    typealias Cancel = () -> Void

    private let now: () -> Double
    private let schedule: (_ afterMs: Double, _ fire: @escaping @MainActor @Sendable () -> Void) -> Cancel
    private var cancel: Cancel?
    /// The time the timer is set for, nil when it is not set.
    private(set) var deadline: Double?
    /// How many timers were scheduled in all: a test proves a hidden island with nothing running schedules none.
    private(set) var scheduled = 0
    /// Called when the deadline has come. The timer is spent by then; the caller sets the next one.
    var onFire: (() -> Void)?

    init(now: @escaping () -> Double, schedule: @escaping (Double, @escaping @MainActor @Sendable () -> Void) -> Cancel) {
        self.now = now; self.schedule = schedule
    }

    func set(_ at: Double?) {
        guard at != deadline else { return }
        cancel?(); cancel = nil; deadline = nil
        guard let at, at.isFinite else { return }
        deadline = at
        scheduled += 1
        cancel = schedule(max(0, at - now())) { [weak self] in self?.fire() }
    }

    private func fire() {
        cancel = nil
        guard let at = deadline else { return }
        let rest = at - now()
        if rest > 1 { scheduled += 1; cancel = schedule(rest) { [weak self] in self?.fire() }; return }   // the timer was early: wait for the rest
        deadline = nil
        onFire?()
    }
}

/// Which views of the open island may host a note: the ones the user is only looking at. A note never covers a card, a question, the chat, a mail draft, the drop flow or Settings; it waits
/// for the gate (and is dropped silently when its time is up). A hidden or compact island hosts it: the note opens it the way a finished task does.
enum SidekickHost {
    static let views: Set<String> = ["overview", "empty", "finished", "note", "sidekick"]

    static func canHost(expanded: Bool, view: String) -> Bool { !expanded || views.contains(view) }
}
