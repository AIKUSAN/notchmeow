import CryptoKit
import Foundation

// The link's conversations (LinkPairRun, LinkTransferReceive, LinkTransferSend, LinkChannel) between two in-memory ends: a pairing with both users agreeing, a no, a tampered message, a replayed
// commitment; a transfer with a real file, a decline, a cancel, an offer nobody answers, a stranger's key, a non-empty KK payload. No socket, no Keychain, no network.
// Run it through scripts/test-link-session.sh.

actor Counter { var n = 0; func add() { n += 1 }; func value() -> Int { n } }
actor Box<T: Sendable> { var v: T?; func set(_ x: T) { v = x }; func get() -> T? { v }; var isSet: Bool { v != nil } }

/// Counts what an end sends, to prove that a refused connection is answered with nothing.
actor LinkCounting: LinkTransport {
    let inner: any LinkTransport
    var sent = 0
    init(_ inner: any LinkTransport) { self.inner = inner }
    func send(_ record: Data) async throws { sent += 1; try await inner.send(record) }
    func receive() async throws -> Data { try await inner.receive() }
    func close() async { await inner.close() }
}

/// Flips one bit of the `index`th record sent through it (0 is the preamble).
actor LinkTamper: LinkTransport {
    let inner: any LinkTransport
    let index: Int
    var count = 0
    init(_ inner: any LinkTransport, flipRecord index: Int) { self.inner = inner; self.index = index }
    func send(_ record: Data) async throws {
        var r = record
        if count == index { r[r.count - 1] ^= 1 }
        count += 1
        try await inner.send(r)
    }
    func receive() async throws -> Data { try await inner.receive() }
    func close() async { await inner.close() }
}

/// Polls a condition every 5 ms for up to 2 s (a test helper: the app itself never polls).
func waitUntil(_ condition: @Sendable () async -> Bool) async {
    for _ in 0..<400 { if await condition() { return }; try? await Task.sleep(for: .milliseconds(5)) }
}

/// Waits a few milliseconds before every send, so that a transfer is still running when the test's click arrives.
actor LinkPaced: LinkTransport {
    let inner: any LinkTransport
    init(_ inner: any LinkTransport) { self.inner = inner }
    func send(_ record: Data) async throws { try? await Task.sleep(for: .milliseconds(3)); try await inner.send(record) }
    func receive() async throws -> Data { try await inner.receive() }
    func close() async { await inner.close() }
}

/// Passes the first `limit` records, then fails every send: a connection that goes away at that point.
actor LinkFailing: LinkTransport {
    let inner: any LinkTransport
    let limit: Int
    var count = 0
    init(_ inner: any LinkTransport, after limit: Int) { self.inner = inner; self.limit = limit }
    func send(_ record: Data) async throws {
        if count >= limit { throw LinkSessionError.io("test: the connection went away") }
        count += 1
        try await inner.send(record)
    }
    func receive() async throws -> Data { try await inner.receive() }
    func close() async { await inner.close() }
}

/// A connection whose sends stop going out after `limit` records: the peer stopped reading. The send that does not go out waits until the transport is aborted, as a real socket's does, and then
/// fails. `cut` says whether `abort()` was called.
actor LinkStalling: LinkTransport {
    let inner: any LinkTransport
    let limit: Int
    private(set) var count = 0
    private(set) var cut = false
    private var held: CheckedContinuation<Void, Never>?
    init(_ inner: any LinkTransport, after limit: Int) { self.inner = inner; self.limit = limit }
    func send(_ record: Data) async throws {
        if count >= limit {
            if !cut { await withCheckedContinuation { held = $0 } }
            throw LinkSessionError.io("test: cut")
        }
        count += 1
        try await inner.send(record)
    }
    func receive() async throws -> Data { try await inner.receive() }
    func close() async { await inner.close() }
    nonisolated func abort() { Task { await self.release() } }
    private func release() async {
        cut = true
        held?.resume(); held = nil
        await inner.close()
    }
}

/// A clock that a test moves. Each side of a pairing reads only its own, so a test can end one side's window at a known point.
final class LinkTestClock: @unchecked Sendable {
    private let lock = NSLock()
    private var ms: Int
    init(_ ms: Int) { self.ms = ms }
    var now: Int { lock.lock(); defer { lock.unlock() }; return ms }
    func set(_ value: Int) { lock.lock(); defer { lock.unlock() }; ms = value }
}

/// The transfer place that the app keeps (LinkBusy: one transfer at a time for the whole Mac, whichever machine it comes from), as a test needs it: one set shared by every connection the test
/// opens. The tests all use one machine, so a set of ids stands in for it.
final class PeerClaims: @unchecked Sendable {
    private let lock = NSLock(); private var peers: Set<String> = []
    func claim(_ id: String) -> Bool { lock.withLock { peers.insert(id).inserted } }
    func release(_ id: String) { lock.withLock { _ = peers.remove(id) } }
    func holds(_ id: String) -> Bool { lock.withLock { peers.contains(id) } }
}

@main
enum LinkSessionTests {
    static func identity(_ n: UInt8, _ name: String) -> LinkIdentity {
        LinkIdentity(deviceId: String(repeating: String(format: "%02x", n), count: 16), name: name, key: try! LinkNoise.privateKey(raw: Data(repeating: n, count: 32)))
    }
    static let nonceA = Data(repeating: 0xA1, count: 32), nonceB = Data(repeating: 0xB1, count: 32)
    static func now(_ ms: Int) -> @Sendable () -> Int { { ms } }

    @MainActor static func main() async {
        setvbuf(stdout, nil, _IONBF, 0)   // a hang then shows how far it got
        DispatchQueue.global().asyncAfter(deadline: .now() + 90) { print("timed out: a conversation never ended"); exit(1) }   // a test, not the app: a hang must fail the run
        let mac = identity(0x11, "Studio Mac"), pc = identity(0x22, "Desk PC")
        let macPub = LinkBytes.hex(LinkNoise.publicKey(of: mac.key)), pcPub = LinkBytes.hex(LinkNoise.publicKey(of: pc.key))

        // MARK: pairing
        func pair(initiatorSays: Bool?, responderSays: Bool?, tamperRecord: Int? = nil, responderState: LinkPairing.ResponderState = .init(),
                  initiatorSendLimit: Int? = nil, responderSendLimit: Int? = nil, windowEndsAtCode: Bool = false) async -> (LinkPairOutcome, LinkPairOutcome, String?, String?) {
            let (a, b) = await LinkMemoryEnd.pair()
            var ta: any LinkTransport = tamperRecord.map { LinkTamper(a, flipRecord: $0) } ?? a
            if let limit = initiatorSendLimit { ta = LinkFailing(ta, after: limit) }
            let tb: any LinkTransport = responderSendLimit.map { LinkFailing(b, after: $0) } ?? b
            let codeA = Box<String>(), codeB = Box<String>()
            let clockA = LinkTestClock(1000), clockB = LinkTestClock(1000)
            let initiator = LinkPairRun(transport: ta, identity: mac, nonce: nonceA, clock: { clockA.now }, hooks: .init(showCode: { c, _ in
                Task { await codeA.set(c) }
                if windowEndsAtCode { clockA.set(1000 + LinkPairing.windowMs) }     // the window (started at 1000 ms) ends the moment the code is on screen: every answer and the timer see it closed
            }))
            let responder = LinkPairRun(transport: tb, identity: pc, nonce: nonceB, clock: { clockB.now }, hooks: .init(showCode: { c, _ in Task { await codeB.set(c) } }))
            // The preamble is read by the listener in the app: here the test reads and checks it.
            async let ri = initiator.runInitiator(.init())
            async let rr: (LinkPairOutcome, LinkPairing.ResponderState) = {
                let pre = try? LinkWire.decodePreamble(try await b.receive())
                guard pre?.mode == .pair else { return (.refused("no preamble"), responderState) }
                return await responder.runResponder(responderState)
            }()
            // The users answer once the codes are on screen.
            Task {
                await waitUntil { await codeA.isSet }
                await waitUntil { await codeB.isSet }
                if let y = initiatorSays { initiator.answer(y) }
                if let y = responderSays { responder.answer(y) }
            }
            let (oi, _) = await ri, (or, _) = await rr
            return (oi, or, await codeA.get(), await codeB.get())
        }

        CT.section("pairing: both users say they match")
        let ok = await pair(initiatorSays: true, responderSays: true)
        CT.check("both sides are paired with each other", [ok.0, ok.1].map { o -> String in if case .paired(let p) = o { return "\(p.name) \(p.key.prefix(8))" }; return "no" }, ["Desk PC \(pcPub.prefix(8))", "Studio Mac \(macPub.prefix(8))"])
        CT.check("the two screens show the same six digits", [ok.2 == ok.3, ok.2?.count == 6], [true, true])

        CT.section("pairing: a no on either side stores nothing")
        let no = await pair(initiatorSays: true, responderSays: false)
        CT.check("the responder said no: both see it", [no.0, no.1], [.declined(byMe: false), .declined(byMe: true)])
        let no2 = await pair(initiatorSays: false, responderSays: nil)
        CT.check("the initiator said no first", [no2.0, no2.1], [.declined(byMe: true), .declined(byMe: false)])

        CT.section("pairing: damaged and replayed")
        func isPaired(_ o: LinkPairOutcome) -> Bool { if case .paired = o { return true }; return false }
        let bad = await pair(initiatorSays: true, responderSays: true, tamperRecord: 2)
        CT.check("a bit flipped in the initiator's reveal (the last handshake message): neither side is paired", [isPaired(bad.0), isPaired(bad.1)], [false, false])
        let bad2 = await pair(initiatorSays: true, responderSays: true, tamperRecord: 3)
        CT.check("a bit flipped in the initiator's answer: the responder, which could not open it, stores nothing", isPaired(bad2.1), false)
        CT.check("a commitment seen again inside the window is refused as a replay", await {
            var seen = LinkPairing.ResponderState()
            seen.seen = [.init(commit: LinkBytes.hex(LinkPairing.commitOf(nonce: nonceA, staticKey: LinkNoise.publicKey(of: mac.key))!), at: 0)]
            seen.last = nil
            return await pair(initiatorSays: nil, responderSays: nil, responderState: seen).1
        }(), LinkPairOutcome.refused("commit-replayed"))

        CT.section("pairing: a pair-yes that cannot be sent stores nothing")
        let noResponderSend = await pair(initiatorSays: true, responderSays: true, responderSendLimit: 1)      // the responder's hello goes out, its pair-yes does not
        CT.check("the responder's pair-yes never left: the responder refuses (closed) and so does the initiator, which never got it", [noResponderSend.0, noResponderSend.1], [.refused("closed"), .refused("closed")])
        let noInitiatorSend = await pair(initiatorSays: true, responderSays: true, initiatorSendLimit: 3)     // preamble, commit and reveal go out, the pair-yes does not
        CT.check("the initiator's pair-yes never left: the initiator refuses (closed) before any store, and so does the responder", [noInitiatorSend.0, noInitiatorSend.1], [.refused("closed"), .refused("closed")])

        CT.section("pairing: the window ends while the code is on screen")
        let late = await pair(initiatorSays: true, responderSays: true, windowEndsAtCode: true)
        CT.check("the window closes before anyone answers: the initiator is refused as window-closed, the responder, which never gets a pair-yes, as closed", [late.0, late.1], [.refused("window-closed"), .refused("closed")])
        CT.check("nothing is paired on either side", [isPaired(late.0), isPaired(late.1)], [false, false])

        // MARK: the gate on an incoming pairing
        func incoming(gate: LinkPairing.Gate, at ms: Int) async -> (initiator: LinkPairOutcome, responder: LinkPairOutcome?, cardShown: Bool, sentByResponder: Bool) {
            let (a, b) = await LinkMemoryEnd.pair()
            let counted = LinkCounting(b)
            let card = Box<String>(), made = Box<LinkPairRun>()
            let initiator = LinkPairRun(transport: a, identity: mac, nonce: nonceA, clock: now(ms), hooks: .init(showCode: { _, _ in }))
            async let ri = initiator.runInitiator(.init())
            async let rr: LinkPairOutcome? = {
                guard (try? LinkWire.decodePreamble(try await counted.receive()))?.mode == .pair else { return nil }
                return await LinkIncomingPairing.run(transport: counted, identity: pc, nonce: nonceB, clock: now(ms), gate: gate, state: .init(), hooks: .init(showCode: { c, _ in Task { await card.set(c) } }), made: { r in Task { await made.set(r) } })?.0
            }()
            // When the card is up nobody answers in a test: both users cancel, which ends the pairing as a no. A refused connection never shows a card, so this waits out its 2 s and does nothing.
            Task { await waitUntil { await card.isSet }; if await card.isSet { initiator.cancel(); await made.get()?.cancel() } }
            let (oi, _) = await ri
            let r = await rr
            return (oi, r, await card.isSet, await counted.sent > 0)
        }
        var closedGate = LinkPairing.Gate()
        CT.section("an incoming pairing outside the gate is refused silently")
        let outside = await incoming(gate: closedGate, at: 1000)
        CT.check("Devices closed and no click: no run, no card, nothing sent, and the initiator is refused", [outside.responder == nil, outside.cardShown, outside.sentByResponder, outside.initiator == .refused("handshake")], [true, false, false, true])
        closedGate.pairClicked(now: 0)
        let atEdge = await incoming(gate: closedGate, at: 120_000)
        CT.check("a click 120 s ago is not enough: refused at exactly 120 s, no card", [atEdge.responder == nil, atEdge.cardShown], [true, false])
        let insideClick = await incoming(gate: closedGate, at: 119_999)
        CT.check("1 ms earlier it is inside the window: the pairing runs and the card is shown", [insideClick.responder != nil, insideClick.cardShown], [true, true])
        var open = LinkPairing.Gate()
        open.devicesAppeared()
        let withDevices = await incoming(gate: open, at: 500_000)
        CT.check("with Devices open it runs at any time", [withDevices.responder != nil, withDevices.cardShown], [true, true])

        // MARK: transfer
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("notchmeow-link-session-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let macPeer = LinkPeer(id: mac.deviceId, name: mac.name, key: macPub, at: 1), pcPeer = LinkPeer(id: pc.deviceId, name: pc.name, key: pcPub, at: 1)

        func transfer(file: URL, folder: URL, respond: Bool?, cancelClickBeforeAnswer: Bool = false, offerTimeoutMs: Int = 120_000, senderPeer: LinkPeer? = nil, claim: Bool = true, receiverCancelsAtBytes: UInt64? = nil, paced: Bool = false,
                      senderSendLimit: Int? = nil, senderCancelsAtBytes: UInt64? = nil, shrinkAfterOffer: Bool = false, cutProbe: Box<LinkStalling>? = nil)
            async -> (sender: LinkTransferOutcome, receiver: LinkTransferOutcome, offer: LinkOffer?, progress: [UInt64]) {
            let (a, b) = await LinkMemoryEnd.pair()
            let offered = Box<LinkOffer>(), prog = Box<[UInt64]>(), who = Box<LinkTransferReceive>()
            await prog.set([])
            let receiver = LinkTransferReceive(transport: b, identity: pc, peer: macPeer, folder: folder, offerTimeoutMs: offerTimeoutMs, hooks: .init(
                offered: { o in Task { await offered.set(o) } },
                progress: { got, _ in Task { var p = await prog.get() ?? []; p.append(got); await prog.set(p); if let limit = receiverCancelsAtBytes, got >= limit { await who.get()?.cancel() } } },
                claim: { _ in claim }, release: { _ in }))
            await who.set(receiver)
            let senderBox = Box<LinkTransferSend>()
            var senderTransport: any LinkTransport = paced ? LinkPaced(a) : a
            if let limit = senderSendLimit { senderTransport = LinkFailing(senderTransport, after: limit) }
            // A transport that never stalls and only notes whether `abort()` was called: the sender's cancel must reach the other side before anything cuts the connection.
            if let cutProbe { let w = LinkStalling(senderTransport, after: Int.max); await cutProbe.set(w); senderTransport = w }
            let sender = LinkTransferSend(transport: senderTransport, identity: mac, peer: senderPeer ?? pcPeer, source: try! LinkFileSource(url: file), hooks: .init(progress: { sent, _ in
                if let limit = senderCancelsAtBytes, sent >= limit { Task { await senderBox.get()?.cancel() } }      // the sender's own user cancels while the file goes out
            }))
            await senderBox.set(sender)
            Task {
                await waitUntil { await offered.isSet }
                if shrinkAfterOffer { _ = truncate(file.path, 0) }      // the source gets shorter after the offer; the sender's open handle reads the new, shorter file
                if cancelClickBeforeAnswer { receiver.cancel() }      // a cancel click while an offer waits is ignored: the answer is Decline
                if let r = respond { receiver.respond(accept: r) }
            }
            async let rs = sender.run()
            async let rr: LinkTransferOutcome = {
                let pre = try? LinkWire.decodePreamble(try await b.receive())
                guard pre?.mode == .transfer, pre?.id == mac.deviceId else { return .aborted("no preamble") }
                return await receiver.run()
            }()
            let (s, r) = (await rs, await rr)
            return (s, r, await offered.get(), await prog.get() ?? [])
        }

        let folder = root.appendingPathComponent("Downloads/NotchMeow", isDirectory: true)
        let big = root.appendingPathComponent("photo.bin")
        var payload = Data(count: 200_000); for i in 0..<payload.count { payload[i] = UInt8(truncatingIfNeeded: i &* 31 &+ 7) }
        try! payload.write(to: big)

        CT.section("transfer: a file of 200 000 bytes, accepted")
        let t1 = await transfer(file: big, folder: folder, respond: true)
        var received: URL?; if case .completed(let u) = t1.receiver { received = u }
        CT.check("the receiver completed and the sender finished", [t1.receiver == .completed(received), t1.sender == .completed(nil)], [true, true])
        CT.check("the card named the file and its size, and the peer", [t1.offer?.name, t1.offer.map { "\($0.size)" }, t1.offer?.peerName] as [String?], ["photo.bin", "200000", "Studio Mac"])
        CT.check("the bytes are the same (SHA-256)", received.map { SHA256.hash(data: try! Data(contentsOf: $0)).description } , SHA256.hash(data: payload).description)
        CT.check("it lives in the folder, quarantined, and progress went up to the size", [received?.deletingLastPathComponent().path == folder.path, received.map(LinkFileSink.isQuarantined) == true, t1.progress.last == 200_000], [true, true, true])

        CT.section("transfer: a second file with the same name is numbered")
        let t2 = await transfer(file: big, folder: folder, respond: true)
        if case .completed(let u2?) = t2.receiver { CT.check("photo (1).bin", u2.lastPathComponent, "photo (1).bin") } else { CT.checkTrue("the second transfer completed", false) }

        CT.section("transfer: declined, not answered, cancelled, busy")
        let before = (try? FileManager.default.contentsOfDirectory(atPath: folder.path).count) ?? 0
        let t3 = await transfer(file: big, folder: folder, respond: false)
        CT.check("a decline reaches the sender with reason 0 and creates no file", [t3.sender, t3.receiver, .completed(nil)] as [LinkTransferOutcome], [.declined(reason: 0), .declined(reason: 0), .completed(nil)])
        CT.check("the folder has no new file", (try? FileManager.default.contentsOfDirectory(atPath: folder.path).count) ?? 0, before)
        let t4 = await transfer(file: big, folder: folder, respond: nil, offerTimeoutMs: 60)
        CT.check("nobody answers: the offer expires, the sender sees reason 1 (timeout), and nothing was written", [t4.receiver, t4.sender, .completed(nil)] as [LinkTransferOutcome], [.expired, .declined(reason: 1), .completed(nil)])
        CT.check("still no new file: nothing accepted by itself", (try? FileManager.default.contentsOfDirectory(atPath: folder.path).count) ?? 0, before)
        let t5 = await transfer(file: big, folder: folder, respond: true, claim: false)
        CT.check("another transfer of the same peer is running: declined as busy (reason 2)", t5.sender, .declined(reason: 2))
        let t6 = await transfer(file: big, folder: folder, respond: false, cancelClickBeforeAnswer: true)
        CT.check("a cancel click while an offer waits is ignored; the Decline that follows is the answer", t6.sender, .declined(reason: 0))
        let t8 = await transfer(file: big, folder: folder, respond: true, receiverCancelsAtBytes: 65_536, paced: true)
        CT.check("the receiver's user cancels in the middle: both sides end cancelled", [t8.sender, t8.receiver], [.cancelled, .cancelled])
        CT.check("and the partial file is gone", (try? FileManager.default.contentsOfDirectory(atPath: folder.path).count) ?? 0, before)

        CT.section("transfer: the sender's user cancels while the file goes out")
        let beforeSenderCancel = (try? FileManager.default.contentsOfDirectory(atPath: folder.path).count) ?? 0
        let t9 = await transfer(file: big, folder: folder, respond: true, paced: true, senderCancelsAtBytes: 1)
        CT.check("the sender's user cancels after the first chunk: both sides end cancelled", [t9.sender, t9.receiver], [.cancelled, .cancelled])
        CT.check("and the receiver leaves no file", (try? FileManager.default.contentsOfDirectory(atPath: folder.path).count) ?? 0, beforeSenderCancel)
        // The service's Cancel asks the run to cancel and cuts nothing itself (a connection cut first would take the cancel frame with it: the other side would see a dropped connection, not a cancel).
        let probe = Box<LinkStalling>()
        let t9b = await transfer(file: big, folder: folder, respond: true, paced: true, senderCancelsAtBytes: 1, cutProbe: probe)
        CT.check("the cancel frame is what the receiver acts on: it ends cancelled, not aborted as closed, and the sender is cancelled", [t9b.sender, t9b.receiver], [.cancelled, .cancelled])
        CT.check("and the connection was not cut on the way (the run closed it after the frame went out)", await probe.get()?.cut, false)

        CT.section("transfer: what fails while the file goes out")
        let shrink = root.appendingPathComponent("shrinks.bin")
        try! payload.write(to: shrink)
        let t10 = await transfer(file: shrink, folder: folder, respond: true, shrinkAfterOffer: true)
        CT.check("the source file got shorter after the offer: a disk fault, so the sender ends aborted as disk and the receiver is cancelled", [t10.sender, t10.receiver], [.aborted("disk"), .cancelled])
        let t11 = await transfer(file: big, folder: folder, respond: true, senderSendLimit: 4)
        CT.check("the connection goes away after the first chunk: aborted as closed, not disk, and the receiver is closed too", [t11.sender, t11.receiver], [.aborted("closed"), .aborted("closed")])

        CT.section("transfer: a stranger's key, and a non-empty KK payload")
        let stranger = LinkPeer(id: pc.deviceId, name: "x", key: LinkBytes.hex(LinkNoise.publicKey(of: identity(0x33, "x").key)), at: 1)
        let t7 = await transfer(file: big, folder: folder, respond: true, senderPeer: stranger)
        CT.check("a sender that holds another key for the receiver cannot complete the handshake", [t7.sender, t7.receiver], [.aborted("handshake"), .aborted("handshake")])
        // A peer whose first KK payload is not empty: the receiver refuses it.
        let (x, y) = await LinkMemoryEnd.pair()
        let strict = LinkTransferReceive(transport: y, identity: pc, peer: macPeer, folder: folder, hooks: .init(offered: { _ in }, progress: { _, _ in }, claim: { _ in true }, release: { _ in }))
        async let strictRun = strict.run()
        var hs = try! LinkHandshake(pattern: .kk, initiator: true, s: mac.key, rs: LinkBytes.data(hex: pcPub)!)
        try! await LinkHandshakeIO.send(x, try! hs.write(Data("hi".utf8)))
        CT.check("a non-empty payload in the first KK message is refused", await strictRun, .aborted("handshake"))
        await x.close()

        CT.section("transfer: an offer the machine declines itself frees the peer's claim at once")
        // The receiver of each connection is the app's, with a claim that is one set per peer. The Mac side is a raw sender: its KK handshake, then one offer frame.
        let claims = PeerClaims()
        let macId = mac.deviceId
        /// `stallAfter`: the receiver's own sends stop going out after that many records (1 is its handshake reply): the peer stopped reading.
        func connect(_ offer: LinkWire.Frame?, firstFrameMs: Int = LinkTransferReceive.firstFrameMs, stallMs: Int = LinkTransferReceive.stallMs, admit: Bool = true, graceMs: Int = LinkTransferReceive.graceMs,
                     stallAfter: Int? = nil, releaseAtEnd: Bool = true)
            async -> (sender: LinkChannel, end: LinkMemoryEnd, receiver: LinkTransferReceive, run: Task<LinkTransferOutcome, Never>, offered: Box<LinkOffer>, stalled: LinkStalling?) {
            let (a, b) = await LinkMemoryEnd.pair()
            let offered = Box<LinkOffer>()
            let stalled = stallAfter.map { LinkStalling(b, after: $0) }
            let receiverEnd: any LinkTransport
            if let stalled { receiverEnd = stalled } else { receiverEnd = b }
            let receiver = LinkTransferReceive(transport: receiverEnd, identity: pc, peer: macPeer, folder: folder, firstFrameMs: firstFrameMs, stallMs: stallMs, graceMs: graceMs, hooks: .init(
                offered: { o in Task { await offered.set(o) } }, progress: { _, _ in },
                claim: { claims.claim($0) }, release: { claims.release($0) }, admit: { admit }, releaseAtEnd: releaseAtEnd))
            let run = Task { await receiver.run() }
            var hs = try! LinkHandshake(pattern: .kk, initiator: true, s: mac.key, rs: LinkBytes.data(hex: pcPub)!)
            let first = try! hs.write(Data())
            try! await LinkHandshakeIO.send(a, first)
            let answer = try! await LinkHandshakeIO.receive(a)
            let reply = try! hs.read(answer)
            precondition(reply.isEmpty)
            let (_, send, receive) = try! hs.finish()
            let sender = LinkChannel(transport: a, send: send, receive: receive)
            if let offer { try! await sender.sendFrame(offer) }
            return (sender, a, receiver, run, offered, stalled)
        }

        // An offer over 4 GiB: the machine declines it (reason 3). No card, and the connection stays open.
        let id1 = Data(repeating: 0x51, count: LinkWire.idLen)
        let big1 = await connect(.offer(id: id1, size: LinkWire.sizeMax + 1, name: "huge.bin", kind: "bin"))
        CT.check("an offer over 4 GiB from a paired peer is declined by the machine as too large (reason 3)", try! await big1.sender.receiveFrame(), .decline(id: id1, reason: LinkFlow.Decline.tooLarge))
        await waitUntil { !claims.holds(macId) }
        CT.check("the claim is released at once, while that connection is still open", claims.holds(macId), false)

        // While that first connection is still open, a second offer from the same peer on a new connection is shown, not declined as busy.
        let id3 = Data(repeating: 0x53, count: LinkWire.idLen)
        let second = await connect(.offer(id: id3, size: 10, name: "ok.bin", kind: "bin"))
        await waitUntil { await second.offered.isSet }
        CT.checkTrue("a second offer from the same peer on a new connection gets its card (not busy)", await second.offered.isSet)
        second.receiver.respond(accept: false)
        await second.end.close()
        CT.check("the user declines it: the sender sees reason 0", await second.run.value, .declined(reason: 0))
        await big1.end.close()
        _ = await big1.run.value

        // A name the sanitizer refuses (a separator): declined by the machine as a bad offer (reason 4), claim released at once.
        let id2 = Data(repeating: 0x52, count: LinkWire.idLen)
        let badName = await connect(.offer(id: id2, size: 10, name: "a/b.bin", kind: "bin"))
        CT.check("an offer with a name the sanitizer refuses is declined as a bad offer (reason 4)", try! await badName.sender.receiveFrame(), .decline(id: id2, reason: LinkFlow.Decline.badOffer))
        await waitUntil { !claims.holds(macId) }
        CT.check("and its claim is released at once too, while that connection is open", claims.holds(macId), false)
        await badName.end.close()
        _ = await badName.run.value

        // MARK: nothing waits for ever
        let count = { (try? FileManager.default.contentsOfDirectory(atPath: folder.path).count) ?? 0 }

        CT.section("receiving: a connection that says nothing, or stops sending, is cut")
        let quiet = await connect(nil, firstFrameMs: 150)
        CT.check("a connection whose handshake is done and sends no first frame within the limit is closed", await quiet.run.value, .aborted("idle"))
        await quiet.end.close()
        let refused = await connect(nil, admit: false)
        CT.check("a connection the caps refuse is closed at once, as busy, before it is read", await refused.run.value, .aborted("busy"))
        await refused.end.close()
        let idQ = Data(repeating: 0x61, count: LinkWire.idLen)
        let waits = await connect(.offer(id: idQ, size: 10, name: "wait.bin", kind: "bin"), firstFrameMs: 100, stallMs: 100)
        await waitUntil { await waits.offered.isSet }
        try? await Task.sleep(for: .milliseconds(450))
        waits.receiver.respond(accept: false)
        CT.check("an offer that waits for the click is not cut by those limits (the click, 450 ms later, is still answered)", await waits.run.value, .declined(reason: 0))
        await waits.end.close()
        let beforeStall = count()
        let idS = Data(repeating: 0x62, count: LinkWire.idLen)
        let stall = await connect(.offer(id: idS, size: 200_000, name: "stall.bin", kind: "bin"), stallMs: 200)
        await waitUntil { await stall.offered.isSet }
        stall.receiver.respond(accept: true)
        CT.check("the accept goes out", try! await stall.sender.receiveFrame(), .accept(id: idS))
        try! await stall.sender.sendFrame(.chunk(id: idS, offset: 0, data: Data(count: 1000)))
        CT.check("a file that stops coming is cut after the limit and aborted as stalled", await stall.run.value, .aborted("stalled"))
        CT.check("and nothing of it is kept", count(), beforeStall)
        await stall.end.close()

        /// The run's outcome if it ends within the helper's 2 s of waiting, nil if it is still running.
        func endsSoon(_ run: Task<LinkTransferOutcome, Never>) async -> LinkTransferOutcome? {
            let box = Box<LinkTransferOutcome>()
            Task { await box.set(await run.value) }
            await waitUntil { await box.isSet }
            return await box.get()
        }

        CT.section("receiving: a peer that stopped reading cannot wedge the conversation")
        let idW = Data(repeating: 0x71, count: LinkWire.idLen)
        let wedgedDecline = await connect(.offer(id: idW, size: LinkWire.sizeMax + 1, name: "w.bin", kind: "bin"), graceMs: 200, stallAfter: 1)
        let wd = await endsSoon(wedgedDecline.run)
        CT.check("a decline that cannot go out is cut after the grace, and the run ends", wd != nil, true)
        CT.check("the stuck connection was cut, and the claim is back", [await wedgedDecline.stalled?.cut, claims.holds(macId)], [true, false])
        let idA = Data(repeating: 0x72, count: LinkWire.idLen)
        let wedgedAccept = await connect(.offer(id: idA, size: 10, name: "wa.bin", kind: "bin"), graceMs: 200, stallAfter: 1)
        await waitUntil { await wedgedAccept.offered.isSet }
        let beforeWedge = count()
        wedgedAccept.receiver.respond(accept: true)
        let wa = await endsSoon(wedgedAccept.run)
        CT.check("an accept that cannot go out is cut after the grace, and the run ends", wa != nil, true)
        CT.check("the stuck connection was cut, the claim is back and nothing of the file is kept", [await wedgedAccept.stalled?.cut, claims.holds(macId), count() == beforeWedge], [true, false, true])
        await wedgedDecline.end.close(); await wedgedAccept.end.close()

        CT.section("receiving: stray frames and declined offers do not keep a connection alive")
        let idF = Data(repeating: 0x73, count: LinkWire.idLen)
        let strays = await connect(nil, firstFrameMs: 300)
        let strayFlood = Task { for _ in 0..<30 { try? await strays.sender.sendFrame(.cancel(id: idF)); try? await Task.sleep(for: .milliseconds(100)) } }
        let sa = await endsSoon(strays.run)
        strayFlood.cancel()
        CT.check("a cancel for nothing every 100 ms is not a first frame: the 300 ms limit still ends the connection as idle", sa, .aborted("idle"))
        await strays.end.close()
        let offerFlood = await connect(nil, firstFrameMs: 5_000)
        let flooder = Task { for i in 0..<30 { try? await offerFlood.sender.sendFrame(.offer(id: Data(repeating: UInt8(0x80 + i), count: LinkWire.idLen), size: LinkWire.sizeMax + 1, name: "f.bin", kind: "bin")); try? await Task.sleep(for: .milliseconds(100)) } }
        let first = try? await offerFlood.sender.receiveFrame()
        let of = await endsSoon(offerFlood.run)
        flooder.cancel()
        CT.check("the first declined offer is answered, the second one ends the connection (one decline per connection)", [first == .decline(id: Data(repeating: 0x80, count: LinkWire.idLen), reason: LinkFlow.Decline.tooLarge), of == .aborted("declines")], [true, true])
        CT.check("and its claim is back", claims.holds(macId), false)
        await offerFlood.end.close()

        let idG = Data(repeating: 0x76, count: LinkWire.idLen)
        let beforeFlood = count()
        let trickle = await connect(.offer(id: idG, size: 200_000, name: "trickle.bin", kind: "bin"), stallMs: 200)
        await waitUntil { await trickle.offered.isSet }
        trickle.receiver.respond(accept: true)
        CT.check("the accept goes out", try! await trickle.sender.receiveFrame(), .accept(id: idG))
        let strayId = Data(repeating: 0x77, count: LinkWire.idLen)
        let cancelFlood = Task { for _ in 0..<60 { try? await trickle.sender.sendFrame(.cancel(id: strayId)); try? await Task.sleep(for: .milliseconds(50)) } }
        let tf = await endsSoon(trickle.run)      // the flood lasts about 3 s: the run must end while it is still going
        cancelFlood.cancel()
        CT.check("while a file is coming in, a cancel for another transfer every 50 ms is not a chunk: the 200 ms limit still ends it as stalled", tf, .aborted("stalled"))
        CT.check("and nothing of it is kept", count(), beforeFlood)
        await trickle.end.close()

        CT.section("receiving: a caller that releases the claim itself gets it from the run")
        let idK = Data(repeating: 0x74, count: LinkWire.idLen)
        let kept = await connect(.offer(id: idK, size: 10, name: "k.bin", kind: "bin"), releaseAtEnd: false)
        await waitUntil { await kept.offered.isSet }
        kept.receiver.respond(accept: false)
        CT.check("the user declines", await kept.run.value, .declined(reason: 0))
        CT.check("the run did not give the claim back, and says it holds it", [claims.holds(macId), await kept.receiver.holdsClaim], [true, true])
        claims.release(macId)
        await kept.end.close()
        let idR = Data(repeating: 0x75, count: LinkWire.idLen)
        let early = await connect(.offer(id: idR, size: LinkWire.sizeMax + 1, name: "r.bin", kind: "bin"), releaseAtEnd: false)
        _ = try! await early.sender.receiveFrame()      // the decline: the claim was taken before it and goes right after it
        await waitUntil { !claims.holds(macId) }
        CT.check("an offer the machine refuses itself still gives its claim back at once", [claims.holds(macId), await early.receiver.holdsClaim], [false, false])
        await early.end.close()
        _ = await early.run.value

        CT.section("receiving: a peer cannot make the conversation queue frames without bound")
        let window = LinkFrameWindow(2)
        await window.take(); await window.take()
        let third = Box<Bool>()
        Task { await window.take(); await third.set(true) }
        try? await Task.sleep(for: .milliseconds(100))
        CT.check("with two places taken the third read waits", await third.isSet, false)
        window.give()
        await waitUntil { await third.isSet }
        CT.check("and goes when one is given back", await third.isSet, true)
        let closing = Box<Bool>()
        Task { await window.take(); await window.take(); await closing.set(true) }
        try? await Task.sleep(for: .milliseconds(50))
        window.close()
        await waitUntil { await closing.isSet }
        CT.check("closing the window lets a waiting reader go", await closing.isSet, true)

        CT.section("a deadline that activity pushes back")
        let fired = Counter()
        let moved = LinkIdleWatch(ms: 300) { Task { await fired.add() } }
        for _ in 0..<5 { try? await Task.sleep(for: .milliseconds(100)); moved.touch() }
        CT.check("it does not fire while something keeps happening (500 ms, limit 300 ms)", await fired.value(), 0)
        await waitUntil { await fired.value() == 1 }
        CT.check("it fires once, after the last touch", await fired.value(), 1)
        let stopped = LinkIdleWatch(ms: 100) { Task { await fired.add() } }
        stopped.stop()
        try? await Task.sleep(for: .milliseconds(300))
        CT.check("a stopped one never fires", await fired.value(), 1)

        // MARK: sending
        func rawPeer(_ end: LinkMemoryEnd, reply: Bool = true) async -> LinkChannel? {
            guard let pre = try? LinkWire.decodePreamble(try await end.receive()), pre.mode == .transfer else { return nil }
            var hs = try! LinkHandshake(pattern: .kk, initiator: false, s: pc.key, rs: LinkBytes.data(hex: macPub)!)
            guard let first = try? hs.read(try await LinkHandshakeIO.receive(end)), first.isEmpty, reply else { return nil }
            try! await LinkHandshakeIO.send(end, try! hs.write(Data()))
            let (_, send, receive) = try! hs.finish()
            return LinkChannel(transport: end, send: send, receive: receive)
        }
        func sender(_ t: any LinkTransport, handshakeMs: Int = 10_000, acceptWaitMs: Int = 130_000, stallMs: Int = 60_000, graceMs: Int = 2_000) -> LinkTransferSend {
            LinkTransferSend(transport: t, identity: mac, peer: pcPeer, source: try! LinkFileSource(url: big), handshakeMs: handshakeMs, acceptWaitMs: acceptWaitMs, stallMs: stallMs, graceMs: graceMs, hooks: .init(progress: { _, _ in }))
        }

        CT.section("sending: a handshake nobody answers, an offer nobody answers")
        do {
            let (a, b) = await LinkMemoryEnd.pair()
            async let out = sender(a, handshakeMs: 150).run()
            _ = await rawPeer(b, reply: false)
            CT.check("the machine takes the connection and never answers the handshake: the send gives up as a failed handshake", await out, .aborted("handshake"))
        }
        do {
            let (a, b) = await LinkMemoryEnd.pair()
            async let out = sender(a, acceptWaitMs: 150).run()
            let ch = await rawPeer(b)!
            guard case .offer(let oid, _, _, _) = try! await ch.receiveFrame() else { fatalError("no offer") }
            CT.check("the offer is never answered: the send ends as expired (and says no more)", await out, .expired)
            CT.check("the machine is told, best effort, that the offer is withdrawn", try! await ch.receiveFrame(), .cancel(id: oid))
        }

        CT.section("sending: Cancel ends the send at once, even when the connection is stuck")
        func stuck(cancel: Bool, stallMs: Int = 60_000) async -> (LinkTransferOutcome, Bool, TimeInterval) {
            let (a, b) = await LinkMemoryEnd.pair()
            let wrapped = LinkStalling(a, after: 4)            // preamble, handshake, offer, one chunk: the second chunk does not go out
            let run = sender(wrapped, stallMs: stallMs, graceMs: 200)
            async let out = run.run()
            let ch = await rawPeer(b)!
            guard case .offer(let oid, _, _, _) = try! await ch.receiveFrame() else { fatalError("no offer") }
            try! await ch.sendFrame(.accept(id: oid))
            await waitUntil { await wrapped.count >= 4 }
            try? await Task.sleep(for: .milliseconds(100))      // the second chunk is now waiting behind a peer that does not read
            let began = Date()
            if cancel { run.cancel() }
            let outcome = await out
            return (outcome, await wrapped.cut, Date().timeIntervalSince(began))
        }
        let cancelled = await stuck(cancel: true)
        CT.check("the user cancels: the send is cancelled, and the stuck connection was cut", [cancelled.0 == .cancelled, cancelled.1], [true, true])
        CT.checkTrue("and it took about the grace (0.2 s here), not for ever (took \(String(format: "%.2f", cancelled.2)) s)", cancelled.2 < 3)
        let stalled = await stuck(cancel: false, stallMs: 300)
        CT.check("nobody cancels and nothing goes out for the limit: the send is aborted as stalled and the connection cut", [stalled.0 == .aborted("stalled"), stalled.1], [true, true])

        CT.section("sending: a Cancel during the handshake")
        do {
            let (a, b) = await LinkMemoryEnd.pair()
            let run = sender(a, handshakeMs: 5_000, graceMs: 150)
            async let out = run.run()
            _ = await rawPeer(b, reply: false)
            let began = Date()
            run.cancel()
            let outcome = await out
            let took = Date().timeIntervalSince(began)
            CT.check("the machine says nothing and the user cancels: the run is cut after the grace and ends as a failed handshake", outcome, .aborted("handshake"))
            CT.checkTrue("and that took about the grace (0.15 s here), not the handshake's 5 s (took \(String(format: "%.2f", took)) s)", took < 2)
        }
        do {
            let (a, b) = await LinkMemoryEnd.pair()
            let probe = LinkStalling(a, after: Int.max)
            let run = sender(probe, handshakeMs: 5_000, graceMs: 300)
            async let out = run.run()
            run.cancel()
            let ch = await rawPeer(b)!      // answers at once: well inside the grace
            guard case .offer(let oid, _, _, _) = try! await ch.receiveFrame() else { fatalError("no offer") }
            CT.check("the handshake finished inside the grace: the cancel is sent as a frame (the offer is withdrawn)", try! await ch.receiveFrame(), .cancel(id: oid))
            CT.check("and the run ends withdrawn", await out, .withdrawn)
            try? await Task.sleep(for: .milliseconds(500))
            CT.check("the cut that was waiting was stopped with the handshake: nothing was cut, even after the grace", await probe.cut, false)
        }
        CT.finish()
    }
}
