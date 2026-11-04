import CryptoKit
import Foundation

// One pairing conversation (sub-project G2, docs/LINK-CONTRACT.md "The pairing code"), on either side. The rules are the pure machines of LinkPairing, run one event at a time; this file only
// does the I/O around them: the preamble, the three `XX` handshake messages (commitment, hello with the responder's nonce, hello with the initiator's reveal), the code, the user's answer, the
// other side's answer, and the two minutes of the window. Nothing is stored here: a `.paired` outcome says that **both users said yes**, and the caller writes the key (LinkKeychain.add
// re-checks the paired map at that moment).
//
// Nothing here reads a clock or draws a random number of its own: `clock` (whole milliseconds, monotonic) and the nonce come in, so a test can run both sides in one process.

struct LinkIdentity: Sendable {
    let deviceId: String                                  // 32 lower-case hex digits
    let name: String                                      // shown on the other machine's card
    let key: Curve25519.KeyAgreement.PrivateKey           // the static key (LinkKeychain.staticKey)
}

enum LinkPairOutcome: Equatable, Sendable {
    case paired(LinkPeer)
    /// A user said no: this machine's (`byMe`) or the other's.
    case declined(byMe: Bool)
    /// A rule or the wire refused: a `LinkPairing.Refusal` raw value, or "closed", "handshake", "unexpected-frame".
    case refused(String)
}

/// An incoming pairing connection, behind the gate: when the gate is closed nothing is sent and the connection is closed, as for any other refused hello, and nobody sees a card. The service
/// uses this one function for every incoming pairing, so the rule is tested where it is applied.
enum LinkIncomingPairing {
    /// nil when refused. `made` is called with the run before it starts, so the caller can answer it.
    static func run(transport: any LinkTransport, identity: LinkIdentity, nonce: Data, clock: @escaping @Sendable () -> Int, gate: LinkPairing.Gate, state: LinkPairing.ResponderState,
                    hooks: LinkPairRun.Hooks, made: @Sendable (LinkPairRun) -> Void = { _ in }) async -> (LinkPairOutcome, LinkPairing.ResponderState)? {
        guard gate.allows(now: clock()) else { await transport.close(); return nil }
        let run = LinkPairRun(transport: transport, identity: identity, nonce: nonce, clock: clock, hooks: hooks)
        made(run)
        return await run.runResponder(state)
    }
}

actor LinkPairRun {
    struct Hooks: Sendable {
        /// The code is known: show it, with the other machine's authenticated name.
        var showCode: @Sendable (_ code: String, _ peerName: String) -> Void
        /// The handshake is over (the other side is authenticated); the connection no longer needs the listener's watchdog.
        var handshakeDone: @Sendable () -> Void = {}
    }

    private enum Event: Sendable { case frame(LinkWire.Frame), closed, user(Bool), windowEnded }

    private let transport: any LinkTransport
    private let identity: LinkIdentity
    private let nonce: Data
    private let clock: @Sendable () -> Int
    private let hooks: Hooks
    private let events: AsyncStream<Event>
    private let post: AsyncStream<Event>.Continuation

    /// `nonce` is this side's fresh 32 random bytes (the commitment's, or the responder's answer).
    init(transport: any LinkTransport, identity: LinkIdentity, nonce: Data, clock: @escaping @Sendable () -> Int, hooks: Hooks) {
        self.transport = transport
        self.identity = identity
        self.nonce = nonce
        self.clock = clock
        self.hooks = hooks
        (events, post) = AsyncStream<Event>.makeStream()
    }

    /// The user's click on "They match" (true) or "No" (false).
    nonisolated func answer(_ yes: Bool) { post.yield(.user(yes)) }
    /// The user closed the card: a no, and the conversation ends.
    nonisolated func cancel() { post.yield(.user(false)) }

    private struct Stepped { var notify: LinkPairing.Notify?; var send: [LinkPairing.Send]; var because: LinkPairing.Refusal? }

    // MARK: Initiator

    func runInitiator(_ start: LinkPairing.InitiatorState) async -> (LinkPairOutcome, LinkPairing.InitiatorState) {
        var st = start
        do {
            var hs = try LinkHandshake(pattern: .xx, initiator: true, s: identity.key)
            let myStatic = LinkBytes.hex(LinkNoise.publicKey(of: identity.key))
            let o = LinkPairing.initiatorStep(st, .start(nonce: LinkBytes.hex(nonce), staticKey: myStatic, now: clock()))
            st = o.state
            if let why = o.because { await transport.close(); return (.refused(why.rawValue), st) }
            guard case .commit(let commitHex)? = o.send.first, let commit = LinkBytes.data(hex: commitHex) else { await transport.close(); return (.refused("handshake"), st) }
            try await transport.send(LinkWire.encodePreamble(mode: .pair, deviceId: Data(count: LinkWire.idLen)))
            try await LinkHandshakeIO.send(transport, try hs.write(commit))
            let hello = try LinkWire.decodeHello(try hs.read(try await LinkHandshakeIO.receive(transport)))
            guard let remote = hs.remoteStatic else { throw LinkSessionError.violation("no remote key") }
            let o2 = LinkPairing.initiatorStep(st, .nonce(hello.nonce, peerStatic: LinkBytes.hex(remote), peerId: hello.id, now: clock()))
            st = o2.state
            if let why = o2.because { await transport.close(); return (.refused(why.rawValue), st) }
            let reveal = LinkWire.encodeHello(deviceId: LinkBytes.data(hex: identity.deviceId)!, nonce: nonce, name: identity.name)
            try await LinkHandshakeIO.send(transport, try hs.write(reveal))
            let (_, send, receive) = try hs.finish()
            guard case .coded(let startedAt, let code, _, _) = st.phase else { throw LinkSessionError.violation("no code") }
            let peer = LinkPeer(id: hello.id, name: hello.name, key: LinkBytes.hex(remote), at: Int(Date().timeIntervalSince1970))
            hooks.handshakeDone()
            hooks.showCode(code, hello.name)
            let channel = LinkChannel(transport: transport, send: send, receive: receive)
            let outcome = await answers(channel, windowStart: startedAt, peer: peer) { event in
                switch event {
                case .user(let yes, let now): let r = LinkPairing.initiatorStep(st, .user(yes: yes, now: now)); st = r.state; return Stepped(notify: r.notify, send: r.send, because: r.because)
                case .peer(let yes, let now): let r = LinkPairing.initiatorStep(st, .peer(yes: yes, now: now)); st = r.state; return Stepped(notify: r.notify, send: r.send, because: r.because)
                }
            }
            await transport.close()
            return (outcome, st)
        } catch {
            await transport.close()
            st.phase = .idle
            return (.refused("handshake"), st)
        }
    }

    // MARK: Responder

    /// The preamble was read already (the listener reads it to tell a pairing from a transfer).
    func runResponder(_ start: LinkPairing.ResponderState) async -> (LinkPairOutcome, LinkPairing.ResponderState) {
        var st = start
        do {
            var hs = try LinkHandshake(pattern: .xx, initiator: false, s: identity.key)
            let commit = try hs.read(try await LinkHandshakeIO.receive(transport))
            let o = LinkPairing.responderStep(st, .commit(commit: LinkBytes.hex(commit), nonce: LinkBytes.hex(nonce), now: clock()))
            st = o.state
            if let why = o.because { await transport.close(); return (.refused(why.rawValue), st) }
            let hello = LinkWire.encodeHello(deviceId: LinkBytes.data(hex: identity.deviceId)!, nonce: nonce, name: identity.name)
            try await LinkHandshakeIO.send(transport, try hs.write(hello))
            let reveal = try LinkWire.decodeHello(try hs.read(try await LinkHandshakeIO.receive(transport)))
            guard let remote = hs.remoteStatic else { throw LinkSessionError.violation("no remote key") }
            let myStatic = LinkBytes.hex(LinkNoise.publicKey(of: identity.key))
            let o2 = LinkPairing.responderStep(st, .reveal(LinkPairing.Reveal(nonce: reveal.nonce, staticKey: LinkBytes.hex(remote), own: myStatic, peerId: reveal.id), now: clock()))
            st = o2.state
            if let why = o2.because { await transport.close(); return (.refused(why.rawValue), st) }
            let (_, send, receive) = try hs.finish()
            guard case .coded(let startedAt, let code, _, _) = st.phase else { throw LinkSessionError.violation("no code") }
            let peer = LinkPeer(id: reveal.id, name: reveal.name, key: LinkBytes.hex(remote), at: Int(Date().timeIntervalSince1970))
            hooks.handshakeDone()
            hooks.showCode(code, reveal.name)
            let channel = LinkChannel(transport: transport, send: send, receive: receive)
            let outcome = await answers(channel, windowStart: startedAt, peer: peer) { event in
                switch event {
                case .user(let yes, let now): let r = LinkPairing.responderStep(st, .user(yes: yes, now: now)); st = r.state; return Stepped(notify: r.notify, send: r.send, because: r.because)
                case .peer(let yes, let now): let r = LinkPairing.responderStep(st, .peer(yes: yes, now: now)); st = r.state; return Stepped(notify: r.notify, send: r.send, because: r.because)
                }
            }
            await transport.close()
            return (outcome, st)
        } catch {
            await transport.close()
            st.phase = .idle
            return (.refused("handshake"), st)
        }
    }

    // MARK: The answers (both roles)

    private enum Answer { case user(Bool, now: Int), peer(Bool, now: Int) }

    /// After the code is shown: the user's click and the other side's `pair-yes` or `pair-no`, in either order, inside the window. The only frames a pairing connection may carry.
    private func answers(_ channel: LinkChannel, windowStart: Int, peer: LinkPeer, step: (Answer) -> Stepped) async -> LinkPairOutcome {
        let post = self.post
        let reader = Task {
            do { while true { post.yield(.frame(try await channel.receiveFrame())) } } catch { post.yield(.closed) }
        }
        let remaining = max(0, LinkPairing.windowMs - (clock() - windowStart))
        let timer = Task {
            try? await Task.sleep(for: .milliseconds(remaining))
            if !Task.isCancelled { post.yield(.windowEnded) }
        }
        defer { reader.cancel(); timer.cancel() }

        for await event in events {
            var stepped: Stepped
            var iAnswered = false
            switch event {
            case .user(let yes): stepped = step(.user(yes, now: clock())); iAnswered = true
            case .frame(.pairYes): stepped = step(.peer(true, now: clock()))
            case .frame(.pairNo): stepped = step(.peer(false, now: clock()))
            case .frame: return .refused("unexpected-frame")
            case .closed: return .refused("closed")
            case .windowEnded: return .refused(LinkPairing.Refusal.windowClosed.rawValue)
            }
            // Our own answer must leave before anything is stored: a pair-yes that never left would leave the other side waiting for it alone, with a key stored on this side only.
            for s in stepped.send {
                if case .pair(let yes) = s {
                    do { try await channel.sendFrame(yes ? .pairYes : .pairNo) } catch { return .refused("closed") }
                }
            }
            if stepped.notify == .store { return .paired(peer) }
            if stepped.notify == .discard {
                if stepped.because == .saidNo { return .declined(byMe: iAnswered) }
                return .refused(stepped.because?.rawValue ?? "discard")
            }
            stepped.notify = nil
        }
        return .refused("closed")
    }
}
