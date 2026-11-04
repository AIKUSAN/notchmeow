import CryptoKit
import Foundation

// Pairing (sub-project G2, docs/LINK-CONTRACT.md "The pairing code"): the commitment, the six-digit code, the clocks, and the two machines that run commit, nonce, reveal and confirm one event
// at a time. A port of `commit_of`, `pairing_code`, `pairing_attempt_allowed`, `pairing_window_open`, `offer_expired`, `pair_responder_step` and `pair_initiator_step` of
// tests/fixtures/link/reference.py, replayed against pairing-cases.json by scripts/test-link-pairing.sh. Foundation and CryptoKit only; the machines draw nothing: the clock ("now",
// whole milliseconds on a monotonic clock) and the random values (a nonce) come in with the event, so the session (LinkSession) is the only place that reads a clock or a random source.
//
// The code is the same on both screens only when both machines saw the same two nonces and the same two static keys. A key is stored only when both users said yes (`notify: .store`).

enum LinkPairing {
    static let codeDigits = 6
    static let commitLabel = Data("notchmeow-link pairing commit v1".utf8)
    static let codeLabel = Data("notchmeow-link pairing code v1".utf8)
    static let gapMs = 30_000             // at most one pairing attempt every 30 seconds
    static let windowMs = 120_000         // the pairing window closes after 2 minutes
    static let offerTimeoutMs = 120_000   // an offer nobody answers is declined after 2 minutes

    /// `SHA-256(label + static + nonce)`, sent in the clear as the payload of the first Noise message. Nil unless both are 32 bytes.
    static func commitOf(nonce: Data, staticKey: Data) -> Data? {
        guard nonce.count == 32, staticKey.count == 32 else { return nil }
        return Data(SHA256.hash(data: commitLabel + staticKey + nonce))
    }

    /// The six digits both screens show: the first 8 bytes of `SHA-256(label + sI + sR + nI + nR)` as a big-endian number, modulo 10^6, with leading zeros. The handshake hash is deliberately
    /// not an input (the contract says why). Nil unless all four are 32 bytes.
    static func code(nonceI: Data, nonceR: Data, staticI: Data, staticR: Data) -> String? {
        guard [nonceI, nonceR, staticI, staticR].allSatisfy({ $0.count == 32 }) else { return nil }
        let d = Array(SHA256.hash(data: codeLabel + staticI + staticR + nonceI + nonceR))
        let n = LinkBytes.readUInt64(d[0..<8]) % 1_000_000
        let s = String(n)
        return String(repeating: "0", count: codeDigits - s.count) + s
    }

    // MARK: The clocks, in whole milliseconds on a monotonic clock

    private static func ms(_ v: Int?) -> Bool { v != nil && v! >= 0 }

    /// Allowed at exactly 30 s after the last attempt; the first attempt (last nil) always; a clock that went back or a value that is not whole milliseconds, never.
    static func attemptAllowed(last: Int?, now: Int?) -> Bool {
        guard ms(now), last == nil || ms(last) else { return false }
        return last == nil || now! - last! >= gapMs
    }

    /// Open below 2 minutes after `start`.
    static func windowOpen(start: Int?, now: Int?) -> Bool { ms(start) && ms(now) && (0..<windowMs).contains(now! - start!) }

    /// Expired at exactly 2 minutes; a clock that went back or a bad value counts as expired: declining is the safe side.
    static func offerExpired(offered: Int?, now: Int?) -> Bool {
        guard ms(offered), ms(now) else { return true }
        return !(0..<offerTimeoutMs).contains(now! - offered!)
    }

    // MARK: Who may start a pairing with this machine

    /// The owner's rule (2026-10-15): an incoming pairing is allowed **only while Settings → Devices is open on this Mac, or within 2 minutes after the user clicked "Pair a machine" on this Mac**
    /// (the contract's window, so it closes at exactly 120 s like `windowOpen`). At any other time the hello is refused silently: nothing is sent, the connection closes, no card, no alert.
    struct Gate: Equatable, Sendable {
        private(set) var devicesOpen = 0
        private(set) var clickedAt: Int?
        mutating func devicesAppeared() { devicesOpen += 1 }
        mutating func devicesDisappeared() { devicesOpen = max(0, devicesOpen - 1) }
        mutating func pairClicked(now: Int) { clickedAt = now }
        func allows(now: Int?) -> Bool { devicesOpen > 0 || LinkPairing.windowOpen(start: clickedAt, now: now) }
    }

    // MARK: The two machines

    enum Refusal: String, Equatable, Sendable {
        case commitLength = "commit-length", commitReplayed = "commit-replayed", attemptTooSoon = "attempt-too-soon", noCommit = "no-commit"
        case revealLate = "reveal-late", revealLength = "reveal-length", revealMismatch = "reveal-mismatch"
        case deviceId = "device-id", ownId = "own-id", idKeyMismatch = "id-key-mismatch", unexpected
        case startLength = "start-length", nonceRepeated = "nonce-repeated", nonceLength = "nonce-length"
        case windowClosed = "window-closed", saidNo = "said-no"
    }

    enum Notify: String, Equatable, Sendable {
        case nonceSent = "nonce-sent", commitSent = "commit-sent", showCode = "show-code", store, discard
    }

    enum Send: Equatable, Sendable {
        case nonce(String), commit(String), reveal(String), pair(yes: Bool)
    }

    /// The two inputs a machine keeps from one step to the next: its own device id and the devices it has paired (device id to the static key stored for it, both lower-case hex).
    /// `paired` is nil when it was not given (an empty map is a different state in the fixtures).
    struct Ids: Equatable, Sendable {
        var ownId: LinkOwnId = .absent
        var paired: [String: String]? = nil
        init(ownId: LinkOwnId = .absent, paired: [String: String]? = nil) { self.ownId = ownId; self.paired = paired }
    }

    struct Out<State: Equatable & Sendable>: Equatable, Sendable {
        var state: State
        var send: [Send] = []
        var notify: Notify? = nil
        var because: Refusal? = nil
    }

    /// False when the machine's own id, if it has one, is not 32 lower-case hex digits (a null one included), or a paired id is not 32 or a paired key is not 64. Fail closed: a capital
    /// letter is never lower-cased, so it cannot make a paired id look new.
    static func idsCanonical(_ ids: Ids) -> Bool {
        switch ids.ownId {
        case .absent: break
        case .null: return false
        case .value(let v): if !LinkBytes.isIdHex(v) { return false }
        }
        return (ids.paired ?? [:]).allSatisfy { LinkBytes.isIdHex($0.key) && LinkBytes.isHex32($0.value) }
    }

    /// Why a peer's hello is refused, given the machine's own id and its paired devices. A hello with no valid device id is refused as `lengthReason` whatever the machine knows; the
    /// all-zero id as `device-id`; a machine whose ids are not canonical refuses every hello as `device-id`; then `own-id`, then `id-key-mismatch` (paired under another key). The key
    /// compared is the one the Noise handshake authenticated, never a value in the hello.
    static func peerRefusal(_ ids: Ids, peerId: String?, peerStatic: String, lengthReason: Refusal) -> Refusal? {
        guard LinkBytes.isIdHex(peerId), let peerId else { return lengthReason }
        if peerId == LinkBytes.zeroId { return .deviceId }
        if !idsCanonical(ids) { return .deviceId }
        if case .value(let own) = ids.ownId, own == peerId { return .ownId }
        if let stored = ids.paired?[peerId], stored != peerStatic { return .idKeyMismatch }
        return nil
    }

    /// A click, or the other side's `pair-yes` or `pair-no`, after the code is shown. Anything but exactly "yes" is a no. Both sides share it.
    private struct Coded { var start: Int; var code: String; var mine: Bool; var theirs: Bool }

    private static func answer<S: Equatable & Sendable>(_ c: Coded, mineAnswer: Bool?, theirAnswer: Bool?, now: Int?, idle: S, coded: (Coded) -> S) -> Out<S> {
        guard windowOpen(start: c.start, now: now) else { return Out(state: idle, notify: .discard, because: .windowClosed) }
        let isMine = mineAnswer != nil
        let yes = isMine ? mineAnswer! : theirAnswer!
        guard yes else { return Out(state: idle, send: isMine ? [.pair(yes: false)] : [], notify: .discard, because: .saidNo) }
        var n = c
        if isMine { n.mine = true } else { n.theirs = true }
        let send: [Send] = isMine ? [.pair(yes: true)] : []
        if n.mine && n.theirs { return Out(state: idle, send: send, notify: .store) }
        return Out(state: coded(n), send: send)
    }

    // MARK: The responder (the machine that is asked to pair)

    struct Seen: Equatable, Sendable { var commit: String; var at: Int }

    enum ResponderPhase: Equatable, Sendable {
        case idle
        case committed(commit: String, start: Int, nonce: String)
        case coded(start: Int, code: String, mine: Bool, theirs: Bool)
    }

    struct ResponderState: Equatable, Sendable {
        var phase: ResponderPhase = .idle
        var seen: [Seen] = []      // the recent commitments, kept across connections
        var last: Int? = nil       // the time of the last attempt
        var ids = Ids()
    }

    struct Reveal: Equatable, Sendable {
        var nonce: String?, staticKey: String?, own: String?, peerId: String?
        init(nonce: String?, staticKey: String?, own: String?, peerId: String?) { self.nonce = nonce; self.staticKey = staticKey; self.own = own; self.peerId = peerId }
    }

    enum ResponderEvent: Equatable, Sendable {
        case commit(commit: String?, nonce: String?, now: Int?)    // the first message arrived; nonce is the app's fresh one
        case reveal(Reveal, now: Int?)                             // the third message was opened: the initiator's nonce, static key and device id; this machine's own static key
        case user(yes: Bool, now: Int?)
        case peer(yes: Bool, now: Int?)
        case unknown
    }

    static func responderStep(_ state: ResponderState, _ event: ResponderEvent) -> Out<ResponderState> {
        var idle = state; idle.phase = .idle
        func refuse(_ r: Refusal) -> Out<ResponderState> { Out(state: idle, because: r) }
        switch event {
        case .commit(let commit, let nonce, let now):
            guard case .idle = state.phase else { return refuse(.unexpected) }
            guard LinkBytes.isHex32(commit), LinkBytes.isHex32(nonce), let commit, let nonce else { return refuse(.commitLength) }
            if state.seen.contains(where: { $0.commit == commit && windowOpen(start: $0.at, now: now) }) { return refuse(.commitReplayed) }   // before the gap, so a replay is named as one
            guard attemptAllowed(last: state.last, now: now) else { return refuse(.attemptTooSoon) }
            var next = state
            next.seen = state.seen.filter { windowOpen(start: $0.at, now: now) } + [Seen(commit: commit, at: now!)]
            next.last = now
            next.phase = .committed(commit: commit, start: now!, nonce: nonce)
            return Out(state: next, send: [.nonce(nonce)], notify: .nonceSent)
        case .reveal(let r, let now):
            switch state.phase {
            case .idle: return refuse(.noCommit)
            case .coded: return refuse(.unexpected)
            case .committed(let commit, let start, let myNonce):
                guard windowOpen(start: start, now: now) else { return refuse(.revealLate) }
                guard LinkBytes.isHex32(r.nonce), LinkBytes.isHex32(r.staticKey), LinkBytes.isHex32(r.own), let rn = r.nonce, let rs = r.staticKey, let own = r.own else { return refuse(.revealLength) }
                guard let want = commitOf(nonce: LinkBytes.data(hex: rn)!, staticKey: LinkBytes.data(hex: rs)!), LinkBytes.hex(want) == commit else { return refuse(.revealMismatch) }   // a wrong nonce and a wrong key look the same, on purpose
                if let why = peerRefusal(state.ids, peerId: r.peerId, peerStatic: rs, lengthReason: .revealLength) { return refuse(why) }
                guard let code = code(nonceI: LinkBytes.data(hex: rn)!, nonceR: LinkBytes.data(hex: myNonce)!, staticI: LinkBytes.data(hex: rs)!, staticR: LinkBytes.data(hex: own)!) else { return refuse(.revealLength) }
                var next = state
                next.phase = .coded(start: start, code: code, mine: false, theirs: false)
                return Out(state: next, notify: .showCode)
            }
        case .user(let yes, let now), .peer(let yes, let now):
            guard case .coded(let start, let code, let mine, let theirs) = state.phase else { return Out(state: state) }   // an answer before there is a code is ignored
            var isUser = false
            if case .user = event { isUser = true }
            let c = Coded(start: start, code: code, mine: mine, theirs: theirs)
            return answer(c, mineAnswer: isUser ? yes : nil, theirAnswer: isUser ? nil : yes, now: now, idle: idle) { n in
                var s = state; s.phase = .coded(start: n.start, code: n.code, mine: n.mine, theirs: n.theirs); return s
            }
        case .unknown:
            return Out(state: state)
        }
    }

    // MARK: The initiator (the machine whose user started the pairing)

    enum InitiatorPhase: Equatable, Sendable {
        case idle
        case started(nonce: String, staticKey: String, start: Int)
        case coded(start: Int, code: String, mine: Bool, theirs: Bool)
    }

    struct InitiatorState: Equatable, Sendable {
        var phase: InitiatorPhase = .idle
        var last: Int? = nil
        var ids = Ids()
    }

    enum InitiatorEvent: Equatable, Sendable {
        case start(nonce: String?, staticKey: String?, now: Int?)                                   // the user chose Pair a machine; the app's fresh nonce and its static public key
        case nonce(String?, peerStatic: String?, peerId: String?, now: Int?)                        // the second message was opened: the responder's nonce, static key and device id
        case user(yes: Bool, now: Int?)
        case peer(yes: Bool, now: Int?)
        case unknown
    }

    static func initiatorStep(_ state: InitiatorState, _ event: InitiatorEvent) -> Out<InitiatorState> {
        var idle = state; idle.phase = .idle
        func refuse(_ r: Refusal) -> Out<InitiatorState> { Out(state: idle, because: r) }
        switch event {
        case .start(let nonce, let staticKey, let now):
            guard case .idle = state.phase else { return refuse(.unexpected) }
            guard LinkBytes.isHex32(nonce), LinkBytes.isHex32(staticKey), let nonce, let staticKey else { return refuse(.startLength) }
            guard attemptAllowed(last: state.last, now: now) else { return refuse(.attemptTooSoon) }
            var next = state
            next.last = now
            next.phase = .started(nonce: nonce, staticKey: staticKey, start: now!)
            let c = commitOf(nonce: LinkBytes.data(hex: nonce)!, staticKey: LinkBytes.data(hex: staticKey)!)!
            return Out(state: next, send: [.commit(LinkBytes.hex(c))], notify: .commitSent)
        case .nonce(let nonce, let peerStatic, let peerId, let now):
            switch state.phase {
            case .idle: return refuse(.noCommit)
            case .coded: return refuse(.nonceRepeated)
            case .started(let myNonce, let myStatic, let start):
                guard windowOpen(start: start, now: now) else { return refuse(.revealLate) }
                guard LinkBytes.isHex32(nonce), LinkBytes.isHex32(peerStatic), let nonce, let peerStatic else { return refuse(.nonceLength) }
                if let why = peerRefusal(state.ids, peerId: peerId, peerStatic: peerStatic, lengthReason: .nonceLength) { return refuse(why) }
                guard let code = code(nonceI: LinkBytes.data(hex: myNonce)!, nonceR: LinkBytes.data(hex: nonce)!, staticI: LinkBytes.data(hex: myStatic)!, staticR: LinkBytes.data(hex: peerStatic)!) else { return refuse(.nonceLength) }
                var next = state
                next.phase = .coded(start: start, code: code, mine: false, theirs: false)
                return Out(state: next, send: [.reveal(myNonce)], notify: .showCode)
            }
        case .user(let yes, let now), .peer(let yes, let now):
            guard case .coded(let start, let code, let mine, let theirs) = state.phase else { return Out(state: state) }
            var isUser = false
            if case .user = event { isUser = true }
            let c = Coded(start: start, code: code, mine: mine, theirs: theirs)
            return answer(c, mineAnswer: isUser ? yes : nil, theirAnswer: isUser ? nil : yes, now: now, idle: idle) { n in
                var s = state; s.phase = .coded(start: n.start, code: n.code, mine: n.mine, theirs: n.theirs); return s
            }
        case .unknown:
            return Out(state: state)
        }
    }
}
