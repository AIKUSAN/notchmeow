import Foundation

// Who holds the island's one link card, and when a click may act on it (sub-project G2). The service has a single card slot for pairing codes, offers, progress and results, and what is on it is
// something the user is about to click: a pairing code or an offer from another machine must never replace it (a click meant for "Accept" would land on another machine's "They match"), and a
// flow that ends must not wipe the card of another one. These are the rules, as plain values: `LinkService` asks them before it changes the card and before it acts on a click, and the test
// program (tests/LinkServiceTests.swift) runs them without the app. No clock is read here: `now` is whole monotonic milliseconds, given by the caller.

struct LinkCardRules: Equatable, Sendable {
    /// A click on a card that has only just changed kind is ignored for this long: a click aimed at the card that was there must not land on the button of the one that replaced it.
    static let settleMs = 700

    enum Kind: Equatable, Sendable {
        case pair, offer, receiving, result
        /// A card with buttons the user is about to press (a result is only read, and may give way).
        var interactive: Bool { self != .result }
    }

    /// What the user was shown: the kind of card and a key for what it is about (the pairing code with the other machine's name, the transfer id, the words of a result). The "answered" flag
    /// and the progress are not part of it, so the user's own answer or a progress tick is not "another card".
    struct Shown: Equatable, Sendable {
        let kind: Kind
        let key: String
    }

    /// What identifies one offer: the machine and the id it chose. A transfer id alone is the other machine's own number, so two machines may use the same one.
    static func offerKey(peerId: String, transferId: String) -> String { "\(peerId)|\(transferId)" }

    /// The flow the card belongs to ("pair:<code>|<peer>", "transfer:<offerKey>"): the one that may change or clear it.
    private(set) var owner: String?
    private(set) var shown: Shown?
    /// When the card last changed kind (or owner).
    private(set) var changedAt = 0

    var interactive: Bool { shown?.kind.interactive ?? false }

    /// A flow asks to put `card` on the island. False when another flow's card with buttons is up: nothing changes then, and the flow must not show anything.
    mutating func show(_ card: Shown, owner flow: String, now: Int) -> Bool {
        if interactive, owner != flow { return false }
        if shown?.kind != card.kind || owner != flow { changedAt = now }
        owner = flow
        shown = card
        return true
    }

    /// A flow is over and has no card to leave: clears the card only if it is this flow's. False (and nothing changes) when the card belongs to another one.
    mutating func end(owner flow: String) -> Bool {
        guard owner == flow else { return false }
        owner = nil
        shown = nil
        return true
    }

    /// May a click act now? `card` is the card the user saw when they clicked (nil: the current one). False for a card that is no longer the one shown, and while the card is still settling.
    func accepts(_ card: Shown?, now: Int) -> Bool {
        guard let current = shown else { return false }
        if let card, card != current { return false }
        return now - changedAt >= Self.settleMs
    }
}

/// Which conversation a late event belongs to. Every hook a conversation gives the network side (the code is known, an offer arrived, bytes came in) reaches the service through a task that
/// may run after the conversation was cancelled, so the hook carries the ticket its conversation was made under and the service acts only if that ticket is still the current one. A stop (Visible
/// turned off) ends all of them at once, and a run that ended or was replaced is stale as soon as another begins.
struct LinkRunGate: Equatable, Sendable {
    struct Ticket: Equatable, Sendable {
        let generation: Int
        let serial: Int
    }

    /// Counts the stops. Whatever awaits remembers the number it started under (`LinkService`).
    private(set) var generation = 0
    private var serial = 0
    private var pair: Ticket?
    private var receive: Ticket?

    mutating func stop() { generation += 1; pair = nil; receive = nil }
    mutating func beginPair() -> Ticket { let t = next(); pair = t; return t }
    mutating func beginReceive() -> Ticket { let t = next(); receive = t; return t }
    private mutating func next() -> Ticket { serial += 1; return Ticket(generation: generation, serial: serial) }
    mutating func endPair() { pair = nil }
    mutating func endReceive() { receive = nil }
    func isPair(_ t: Ticket) -> Bool { t == pair && t.generation == generation }
    func isReceive(_ t: Ticket) -> Bool { t == receive && t.generation == generation }
}

/// Who may take the island's card, decided where the transfer's own task can ask without leaving it (so the answer is exact when the offer arrives, not when the main thread gets to it).
final class LinkBusy: @unchecked Sendable {
    private let lock = NSLock(); private var peers: Set<String> = []; private var cardLocked = false
    /// False when a transfer is already claimed (by any machine: the island has one card), or a card with buttons is on the island (the offer is then declined as busy, and no card is shown).
    /// The claim is what makes a run "the one that may show a card"; a connection that has only said hello does not hold it.
    func claim(_ id: String) -> Bool { lock.withLock { !cardLocked && peers.isEmpty && peers.insert(id).inserted } }
    func release(_ id: String) { lock.withLock { _ = peers.remove(id) } }
    /// This peer's offer holds the Mac's one transfer place (its run holds the claim until it ends): an Accept click for an offer whose run has ended is not for it.
    func holds(_ id: String) -> Bool { lock.withLock { peers.contains(id) } }
    func setCardLocked(_ on: Bool) { lock.withLock { cardLocked = on } }
    /// A pairing code is about to take the card. False when an offer has been claimed and has not got its card yet (the pairing is ended instead; nothing is shown for it). Otherwise the card
    /// is locked at once, so an offer that arrives next is declined as busy at its claim, not after it passed.
    func reserveCard() -> Bool { lock.withLock { if !peers.isEmpty { return false }; cardLocked = true; return true } }
}

/// How many connections may be established at once (their handshake done): 8 in all and 2 for one machine, so a machine that holds connections open and says nothing cannot take every
/// descriptor or crowd the other machines out. Asked from the conversation's own task, so it is a lock and not the main actor. Connections that have not finished their handshake are not counted
/// here: they are bounded by the listener's own pending cap and its 10 seconds (`LinkListener`), and they are not yet known to be the machine they say they are.
final class LinkConnectionCaps: @unchecked Sendable {
    static let total = 8
    static let perPeer = 2
    private let lock = NSLock()
    private var owners: [UUID: String] = [:]

    /// True when the connection `id` of `peer` may go on (and is counted from now until `release`).
    func admit(_ id: UUID, peer: String) -> Bool {
        lock.withLock {
            if owners[id] != nil { return true }
            guard owners.count < Self.total, owners.values.filter({ $0 == peer }).count < Self.perPeer else { return false }
            owners[id] = peer
            return true
        }
    }

    func release(_ id: UUID) { lock.withLock { _ = owners.removeValue(forKey: id) } }
    var count: Int { lock.withLock { owners.count } }
}

/// How often the paired machines are read from the Keychain on a miss (an id this Mac does not know) or by choice: once in 5 s, so a peer that sends ids that are not paired cannot make the Mac
/// read the Keychain in a loop, and a read that failed for a moment is tried again soon. Plain values: the caller gives `now` (`LinkClock.nowMs()`).
struct LinkReadLimit: Equatable, Sendable {
    static let gapMs = 5_000
    private var last: Int?

    func due(now: Int) -> Bool { last.map { now - $0 >= Self.gapMs } ?? true }
    /// A read happened (whoever asked for it).
    mutating func read(now: Int) { last = now }
}

/// The link's whole-millisecond clock: monotonic, and it keeps counting while the Mac sleeps (`CLOCK_MONOTONIC_RAW` on macOS), as a sleeping task does, so a window that was measured by the clock and
/// one that was slept for end together. (`ProcessInfo.systemUptime` stops during sleep.) Only differences mean anything.
enum LinkClock {
    static func nowMs() -> Int { Int(clock_gettime_nsec_np(CLOCK_MONOTONIC_RAW) / 1_000_000) }
}
