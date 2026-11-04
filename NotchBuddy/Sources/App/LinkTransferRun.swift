import CryptoKit
import Foundation

// One transfer conversation (sub-project G2, docs/LINK-CONTRACT.md "What each side does with each frame"), on either side. The rules are the pure machines of LinkFlow, run one event at a time;
// this file does the I/O around them: the preamble and the two `KK` handshake messages, the offer, the user's answer, the chunks to or from disk, progress, cancel, and the two minutes an offer
// may wait. Only a click on Accept accepts an offer (`respond(accept:)` is called from that button alone): nothing in this file accepts for the user.
//
// A transfer runs only between paired machines: the sender knows the receiver's stored key, and the receiver looks up the sender's device id from the preamble and refuses one it does not know
// (the caller does that before it makes a `LinkTransferReceive`). Nothing here draws a random number except the transfer id the sender makes.
//
// Nothing waits for ever. A connection whose handshake is done must send its first frame within 10 s (a sender sends its offer right after the handshake) and nothing but a file coming in pushes
// that back; while a file comes in, a chunk must come within 60 s (the offer that waits for a click has its own 2 minutes); a sender whose offer nobody answers gives up after 130 s, and one whose
// bytes stop going out after 60 s. A sender's user may cancel at any time: its cancel frame is given 2 s like every frame, and a cancel that comes while the handshake is still going is waited for
// 2 s too, then the connection is cut (the conversation reads nothing before its offer is out). A frame this side sends is given 2 s (`LinkChannel.sendBestEffort`), then the connection is cut, so a peer that stopped reading cannot hold the conversation in a
// send. A conversation that is cut for that reason saves nothing. Each of those is a one-shot `LinkIdleWatch` that exists only while its phase lasts, and each reader hands on at most
// `LinkFrameWindow.frames` frames the conversation has not taken yet. A peer gets one decline per connection (a sender makes a connection for each file): the second ends the connection.

enum LinkTransferOutcome: Equatable, Sendable {
    case completed(URL?)               // the received file's URL; nil on the sending side
    case declined(reason: UInt8)       // the receiver said no (sender), or this side's own decline (receiver: reason 0)
    case expired                       // nobody answered the offer in 2 minutes
    case cancelled                     // either user cancelled during the transfer, or the other side did
    case withdrawn                     // the sender withdrew an offer that was waiting
    case aborted(String)               // a rule or the wire ended it: a `LinkFlow.Abort` raw value, or "closed", "handshake", "disk"
}

/// What the Accept card shows. `name` is the **sanitized** name, the one that will be saved.
struct LinkOffer: Equatable, Sendable {
    let transferId: String
    let name: String
    let size: UInt64
    let peerId: String
    let peerName: String
}

// MARK: - Receiving

actor LinkTransferReceive {
    struct Hooks: Sendable {
        /// An offer is waiting for a click. Show the card.
        var offered: @Sendable (LinkOffer) -> Void
        var progress: @Sendable (_ received: UInt64, _ total: UInt64) -> Void
        /// One active transfer for the whole Mac (`LinkBusy`), whichever machine it comes from: false when another transfer is already claimed, or a card with buttons is on the island (the offer is then
        /// declined as busy). `peerId` says whose offer it is; it does not make the claim per machine.
        var claim: @Sendable (_ peerId: String) -> Bool
        var release: @Sendable (_ peerId: String) -> Void
        /// The handshake is over; the connection no longer needs the listener's watchdog.
        var handshakeDone: @Sendable () -> Void = {}
        /// Asked once, when the handshake is over and before anything is read: false closes the connection (too many connections are open already, `LinkConnectionCaps`). Nothing is shown for it.
        var admit: @Sendable () -> Bool = { true }
        /// false: the run does not give its claim back when it ends, its caller does (`holdsClaim`), once it has cleared what it keeps for the run. The early give-back of an offer this side refused
        /// itself is not affected.
        var releaseAtEnd = true
    }

    /// A connection that has finished its handshake must send its first frame within this long: a sender sends its offer at once, so a machine that says nothing is not worth waiting for.
    static let firstFrameMs = 10_000
    /// While a file comes in, the time the other side may take between two chunks.
    static let stallMs = 60_000
    /// A frame this side sends is waited for no longer than this: after it the connection is cut, however stuck it is (a peer that stopped reading).
    static let graceMs = 2_000

    private enum Event: Sendable { case frame(LinkWire.Frame), closed, flow(LinkFlow.Event), silent, stalled }

    private let transport: any LinkTransport
    private let identity: LinkIdentity
    private let peer: LinkPeer
    private let folder: URL
    private let hooks: Hooks
    private let offerTimeoutMs: Int
    private let firstFrameMs: Int
    private let stallMs: Int
    private let graceMs: Int
    private let events: AsyncStream<Event>
    private let post: AsyncStream<Event>.Continuation
    /// True from the moment this run's offer took the Mac's one transfer place (`Hooks.claim`) until it was given back. A caller that set `releaseAtEnd` to false reads it after `run()`.
    private(set) var holdsClaim = false

    init(transport: any LinkTransport, identity: LinkIdentity, peer: LinkPeer, folder: URL = LinkFileSink.defaultFolder(), offerTimeoutMs: Int = LinkPairing.offerTimeoutMs,
         firstFrameMs: Int = LinkTransferReceive.firstFrameMs, stallMs: Int = LinkTransferReceive.stallMs, graceMs: Int = LinkTransferReceive.graceMs, hooks: Hooks) {
        self.transport = transport
        self.identity = identity
        self.peer = peer
        self.folder = folder
        self.offerTimeoutMs = offerTimeoutMs
        self.firstFrameMs = firstFrameMs
        self.stallMs = stallMs
        self.graceMs = graceMs
        self.hooks = hooks
        (events, post) = AsyncStream<Event>.makeStream()
    }

    /// The user's click on Accept (true) or Decline (false).
    nonisolated func respond(accept: Bool) { post.yield(.flow(.user(accept ? .accept : .decline))) }
    /// The user cancels the transfer that is running (or declines the offer that is waiting).
    nonisolated func cancel() { post.yield(.flow(.user(.cancel))) }

    /// The preamble was read already. Runs the `KK` handshake, then the conversation.
    func run() async -> LinkTransferOutcome {
        var sink: LinkFileSink?
        func finish(_ o: LinkTransferOutcome) async -> LinkTransferOutcome {
            if case .completed = o {} else { sink?.discard() }
            if holdsClaim, hooks.releaseAtEnd { holdsClaim = false; hooks.release(peer.id) }
            let cut = LinkIdleWatch(ms: graceMs) { [transport] in transport.abort() }   // a close waits behind bytes a peer does not read
            await transport.close()
            cut.stop()
            return o
        }
        let channel: LinkChannel
        do {
            guard let remote = LinkBytes.data(hex: peer.key) else { return await finish(.aborted("handshake")) }
            var hs = try LinkHandshake(pattern: .kk, initiator: false, s: identity.key, rs: remote)
            let first = try hs.read(try await LinkHandshakeIO.receive(transport))
            guard first.isEmpty else { return await finish(.aborted("handshake")) }       // the KK payloads are empty (docs/LINK-CONTRACT.md); a port refuses a non-empty one
            try await LinkHandshakeIO.send(transport, try hs.write(Data()))
            let (_, send, receive) = try hs.finish()
            channel = LinkChannel(transport: transport, send: send, receive: receive)
            guard hooks.admit() else { return await finish(.aborted("busy")) }
            hooks.handshakeDone()
        } catch { return await finish(.aborted("handshake")) }

        let post = self.post, window = LinkFrameWindow()
        let reader = Task { do { while true { await window.take(); post.yield(.frame(try await channel.receiveFrame())) } } catch { post.yield(.closed) } }
        var timer: Task<Void, Never>?
        // What the connection is waited for: its first frame (while no offer is in hand), then a chunk at a time (while a file comes in). An offer that waits for the click has `timer`, not this.
        enum Waiting { case nothing, firstFrame, chunk }
        var idleWatch: LinkIdleWatch?
        var waiting = Waiting.nothing
        func wait(for state: LinkFlow.ReceiverState) {
            let want: Waiting
            switch state { case .idle: want = .firstFrame; case .offered: want = .nothing; case .receiving: want = .chunk }
            guard want != waiting else { return }
            idleWatch?.stop()
            waiting = want
            switch want {
            case .nothing: idleWatch = nil
            // The watch cuts the connection itself, before it posts: the conversation may be stuck in a send and not read its queue until the cut fails that send.
            case .firstFrame: idleWatch = LinkIdleWatch(ms: firstFrameMs) { [transport] in transport.abort(); post.yield(.silent) }
            case .chunk: idleWatch = LinkIdleWatch(ms: stallMs) { [transport] in transport.abort(); post.yield(.stalled) }
            }
        }
        defer { reader.cancel(); timer?.cancel(); idleWatch?.stop(); window.close() }
        wait(for: .idle)

        var state = LinkFlow.ReceiverState.idle
        var total: UInt64 = 0
        var offeredName = ""
        var declines = 0      // the declines this machine made itself (not the user's) on this connection: a sender makes one connection per file, and one decline is all it needs
        for await event in events {
            let flowEvent: LinkFlow.Event
            switch event {
            case .closed: return await finish(.aborted("closed"))
            // A report that was on its way when the connection moved on (an offer came in, a chunk did) is not for the phase it finds.
            case .silent: if waiting != .firstFrame { continue }; transport.abort(); return await finish(.aborted("idle"))
            case .stalled: if waiting != .chunk { continue }; transport.abort(); return await finish(.aborted("stalled"))
            case .frame(let f):
                flowEvent = .frame(f); window.give()
                // Only a chunk is activity: while a file comes in the limit is pushed back by chunks and by nothing else a peer sends (a cancel for another transfer, an offer), and while nothing is going on
                // the first-frame limit is not pushed back at all, so no stream of frames keeps a connection alive.
                if case .receiving = state, case .chunk = f { idleWatch?.touch() }
            case .flow(let e): flowEvent = e
            }
            // Busy across connections: the machine models this connection only. This Mac has one transfer place (`Hooks.claim`), whichever machine it is asked for.
            var busyId: Data?
            if case .frame(.offer(let id, _, _, _)) = flowEvent, case .idle = state, !holdsClaim {
                if hooks.claim(peer.id) { holdsClaim = true } else { busyId = id }
            }
            let out = busyId.map { LinkFlow.Out(state: state, send: [.decline(id: $0, reason: LinkFlow.Decline.busy)]) } ?? LinkFlow.receiverStep(state, flowEvent)
            // The second decline the machine makes on one connection is not answered: the connection is cut, so a peer that sends offers without end holds no place and churns no claim.
            if case .frame(.offer) = flowEvent, out.send.contains(where: { if case .decline = $0 { return true }; return false }) {
                declines += 1
                if declines > 1 { transport.abort(); return await finish(.aborted("declines")) }
            }
            state = out.state
            for f in out.send { await channel.sendBestEffort(f, graceMs: graceMs) }
            if let abort = out.abort { return await finish(.aborted(abort.rawValue)) }
            // The machine declined the offer itself (too large, a name it refuses): no card will come, so this Mac's transfer place goes now, not when the connection closes.
            if holdsClaim, case .frame(.offer(_, _, _, _)) = flowEvent, case .idle = state { holdsClaim = false; hooks.release(peer.id) }

            switch out.notify {
            case .offer:
                guard case .offered(let id, let size, let name) = state else { break }
                total = size
                offeredName = name
                timer?.cancel()
                timer = Task { [post, offerTimeoutMs] in
                    try? await Task.sleep(for: .milliseconds(offerTimeoutMs))
                    if !Task.isCancelled { post.yield(.flow(.timeout)) }
                }
                hooks.offered(LinkOffer(transferId: LinkBytes.hex(id), name: name, size: size, peerId: peer.id, peerName: peer.name))
            case .expired: return await finish(.expired)
            case .withdrawn: return await finish(.withdrawn)
            case .cancelled: return await finish(.cancelled)
            case .complete:
                do { let url = try sink?.finish(); return await finish(.completed(url)) } catch { return await finish(.aborted("disk")) }
            default: break
            }

            wait(for: state)

            // Effects of the new state.
            switch (flowEvent, state) {
            case (.user(.accept), .receiving):
                timer?.cancel()
                // Only now is anything created on disk. A file that cannot be created ends the transfer with a cancel the other side sees.
                let s = LinkFileSink(folder: folder, name: offeredName)
                do { _ = try s.open(); sink = s } catch { await channel.sendBestEffort(.cancel(id: currentId(state)), graceMs: graceMs); return await finish(.aborted("disk")) }
            case (.frame(.chunk(_, _, let data)), .receiving(_, _, let got)):
                do { try sink?.write(data) } catch { await channel.sendBestEffort(.cancel(id: currentId(state)), graceMs: graceMs); return await finish(.aborted("disk")) }
                hooks.progress(got, total)
            case (.user(.decline), .idle):
                return await finish(.declined(reason: LinkFlow.Decline.user))
            default: break
            }
        }
        return await finish(.aborted("closed"))
    }

    private func currentId(_ s: LinkFlow.ReceiverState) -> Data {
        switch s { case .offered(let id, _, _), .receiving(let id, _, _): return id; case .idle: return Data(count: LinkWire.idLen) }
    }
}

// MARK: - Sending

actor LinkTransferSend {
    struct Hooks: Sendable {
        var progress: @Sendable (_ sent: UInt64, _ total: UInt64) -> Void
    }

    /// The other side has this long to answer the handshake (the listener gives a connection 10 s for it too).
    static let handshakeMs = 10_000
    /// An offer nobody answers is given up after this long: a little more than the 2 minutes the receiver gives its user, so the receiver's own "did not answer in time" arrives first.
    static let acceptWaitMs = 130_000
    /// While the file goes out, the longest the other side may take without letting one more chunk through.
    static let stallMs = 60_000
    /// A cancel is sent and not waited for longer than this: after it the connection is cut, however stuck it is.
    static let graceMs = 2_000

    /// How the chunk pump ended: all sent (`done`), the file could not be read or changed size (`disk`, the file's fault), or a send failed (`lost`, the connection's fault).
    private enum Pump: Sendable { case done, disk, lost }
    private enum Event: Sendable { case frame(LinkWire.Frame), closed, cancel, pumped(Pump), unanswered, stalled }

    private let transport: any LinkTransport
    private let identity: LinkIdentity
    private let peer: LinkPeer
    private let source: LinkFileSource
    private let hooks: Hooks
    private let handshakeMs: Int
    private let acceptWaitMs: Int
    private let stallMs: Int
    private let graceMs: Int
    private let events: AsyncStream<Event>
    private let post: AsyncStream<Event>.Continuation
    private let handshakeCut = HandshakeCut()

    init(transport: any LinkTransport, identity: LinkIdentity, peer: LinkPeer, source: LinkFileSource, handshakeMs: Int = LinkTransferSend.handshakeMs, acceptWaitMs: Int = LinkTransferSend.acceptWaitMs,
         stallMs: Int = LinkTransferSend.stallMs, graceMs: Int = LinkTransferSend.graceMs, hooks: Hooks) {
        self.transport = transport
        self.identity = identity
        self.peer = peer
        self.source = source
        self.hooks = hooks
        self.handshakeMs = handshakeMs
        self.acceptWaitMs = acceptWaitMs
        self.stallMs = stallMs
        self.graceMs = graceMs
        (events, post) = AsyncStream<Event>.makeStream()
    }

    /// The user cancels: the run sends its cancel frame and ends, and the connection is cut only if that frame cannot go out within `graceMs` (see `sendBestEffort`), so the other side's user sees a
    /// cancel and not a connection that dropped. While the handshake is still going nothing is read (the cancel is read once the offer is out): the cancel is then given `graceMs` for that to
    /// happen, and the connection is cut when it has not (`HandshakeCut`).
    nonisolated func cancel() {
        post.yield(.cancel)
        handshakeCut.arm(ms: graceMs) { [transport] in transport.abort() }
    }

    /// The deadline of a cancel that comes before the loop reads events (the handshake and the offer): armed by the cancel, ended when the offer is out (or the run is), and then it never fires.
    private final class HandshakeCut: @unchecked Sendable {
        private let lock = NSLock()
        private var over = false
        private var watch: LinkIdleWatch?
        func arm(ms: Int, cut: @escaping @Sendable () -> Void) {
            lock.withLock { if !over, watch == nil { watch = LinkIdleWatch(ms: ms, fire: cut) } }
        }
        func end() {
            let w: LinkIdleWatch? = lock.withLock { over = true; let x = watch; watch = nil; return x }
            w?.stop()
        }
    }

    /// Sends one frame and waits for it no longer than `graceMs` (`LinkChannel.sendBestEffort`): the connection may be stuck behind the chunk the pump is sending (a peer that stopped reading), and
    /// then the cancel would wait for ever. After the grace the transport is cut, which fails the stuck send, frees the channel and lets this one fail too.
    private func sendBestEffort(_ frame: LinkWire.Frame, on channel: LinkChannel) async {
        await channel.sendBestEffort(frame, graceMs: graceMs)
    }

    func run() async -> LinkTransferOutcome {
        func finish(_ o: LinkTransferOutcome) async -> LinkTransferOutcome { self.handshakeCut.end(); self.source.close(); await transport.close(); return o }
        let channel: LinkChannel
        // The handshake has a deadline of its own: a machine that accepts the connection and then says nothing does not hold the send for ever.
        let handshake = LinkIdleWatch(ms: handshakeMs) { [transport] in transport.abort() }
        do {
            guard let remote = LinkBytes.data(hex: peer.key), let me = LinkBytes.data(hex: identity.deviceId) else { handshake.stop(); return await finish(.aborted("handshake")) }
            var hs = try LinkHandshake(pattern: .kk, initiator: true, s: identity.key, rs: remote)
            try await transport.send(LinkWire.encodePreamble(mode: .transfer, deviceId: me))
            try await LinkHandshakeIO.send(transport, try hs.write(Data()))
            let reply = try hs.read(try await LinkHandshakeIO.receive(transport))
            guard reply.isEmpty else { handshake.stop(); return await finish(.aborted("handshake")) }
            let (_, send, receive) = try hs.finish()
            channel = LinkChannel(transport: transport, send: send, receive: receive)
            handshake.stop()
        } catch { handshake.stop(); return await finish(.aborted("handshake")) }

        let id = Data((0..<LinkWire.idLen).map { _ in UInt8.random(in: 0...255) })
        do { try await channel.sendFrame(.offer(id: id, size: source.size, name: source.name, kind: source.kind)) } catch { return await finish(.aborted("closed")) }
        handshakeCut.end()      // from here the loop below reads a cancel and sends it as a frame

        let post = self.post, file = self.source, hooks = self.hooks
        let window = LinkFrameWindow()
        let reader = Task { do { while true { await window.take(); post.yield(.frame(try await channel.receiveFrame())) } } catch { post.yield(.closed) } }
        var pump: Task<Void, Never>?
        // While the offer waits: the answer, within `acceptWaitMs`. While the file goes out: a chunk through within `stallMs` (the pump touches it after each one).
        var wait: LinkIdleWatch? = LinkIdleWatch(ms: acceptWaitMs) { post.yield(.unanswered) }
        defer { reader.cancel(); pump?.cancel(); wait?.stop(); window.close() }

        var state = LinkFlow.SenderState.offered(id: id)
        for await event in events {
            let flowEvent: LinkFlow.SenderEvent
            switch event {
            case .closed: return await finish(.aborted("closed"))
            case .cancel: flowEvent = .userCancel
            case .frame(let f): flowEvent = .frame(f); window.give()
            case .unanswered:
                guard case .offered = state else { continue }   // it was on its way when the answer came
                await sendBestEffort(.cancel(id: id), on: channel)
                return await finish(.expired)
            case .stalled:
                guard case .sending = state else { continue }
                transport.abort()
                return await finish(.aborted("stalled"))
            case .pumped(let end):
                switch end {
                case .done: return await finish(.completed(nil))
                case .disk:
                    await sendBestEffort(.cancel(id: id), on: channel)
                    return await finish(.aborted("disk"))
                case .lost: return await finish(.aborted("closed"))
                }
            }
            var declineReason: UInt8 = 0
            if case .frame(.decline(_, let r)) = flowEvent { declineReason = r }
            let out = LinkFlow.senderStep(state, flowEvent)
            let wasOffered: Bool = { if case .offered = state { return true }; return false }()
            state = out.state
            for f in out.send { await sendBestEffort(f, on: channel) }
            if let abort = out.abort { return await finish(.aborted(abort.rawValue)) }
            switch out.notify {
            case .declined: return await finish(.declined(reason: declineReason))
            case .cancelled: return await finish(wasOffered && flowEvent == .userCancel ? .withdrawn : .cancelled)
            default: break
            }
            if wasOffered, case .sending = state {
                // Accepted: cut the file into chunks and send them, one at a time, each waiting for the transport. A file that is shorter or longer than it was when the offer went out is cancelled.
                // A read that fails or comes back short is the file's fault ("disk"); a send that fails is the connection's ("closed"). A pump that was cancelled posts nothing.
                let moving = LinkIdleWatch(ms: stallMs) { post.yield(.stalled) }
                wait?.stop()
                wait = moving
                pump = Task {
                    func end(_ how: Pump) { if !Task.isCancelled { post.yield(.pumped(how)) } }
                    var sent: UInt64 = 0
                    do {
                        for piece in LinkWire.planChunks(size: file.size) {
                            try Task.checkCancellation()
                            guard let data = try? file.read(piece.length), data.count == piece.length else { end(.disk); return }
                            try await channel.sendFrame(.chunk(id: id, offset: piece.offset, data: data))
                            moving.touch()
                            sent += UInt64(data.count)
                            hooks.progress(sent, file.size)
                        }
                        guard let tail = try? file.read(1), tail.isEmpty else { end(.disk); return }
                        try await channel.sendFrame(.done(id: id))
                        end(.done)
                    } catch { end(.lost) }
                }
            }
        }
        return await finish(.aborted("closed"))
    }
}
