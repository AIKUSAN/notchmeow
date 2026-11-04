import Combine
import CryptoKit
import Foundation
@preconcurrency import Network

// The app's one holder of the link (sub-project G2): the settings, the listener and the browser, the pairing and the transfers that are under way, and what the views show. It is the only file
// that joins the pure rules (LinkPairing, LinkFlow), the conversations (LinkPairRun, LinkTransferReceive, LinkTransferSend), the Keychain (LinkKeychain) and the network (LinkNetwork) to the
// app. Views take plain values (`LinkService.Card`, `LinkDirectory.Row`) and closures, so the render script draws them without this file.
//
// What it will not do: it starts no listener and makes no advert until the user turns on "Visible on this network" (off by default), it browses only while Send or Devices is open, it never
// accepts an offer for the user (`respondOffer(accept:)` is only ever called from a click), it keeps no file name, device name or address in a log, and it polls nothing: every change comes from
// a socket, a callback or a click. It starts no timer of its own. The 2-minute windows are one-shot sleeps inside the conversations, started when a pairing or an offer begins.
//
// The Keychain is read at launch, when the user turns Visible on or opens Devices, and when a pairing is stored or a machine forgotten: the key, the device id and the paired map are then held in
// memory, so an incoming connection (which the network chooses the time of) and a change in the browser's results cost no Keychain read, and nothing is read for a connection before its first
// record is known to be one. A machine that is not in the map is looked for in the Keychain once more, at most once in 5 s (`LinkReadLimit`); a read that fails keeps the last good map and says so
// in Devices (`problem`), and the line goes when a read works.
//
// The island has one card. What is on it is something the user is about to click, so no flow replaces another flow's card (`LinkCardRules`, which is tested without the app), a flow that ends
// clears only its own, and a click is ignored for 700 ms after the card changes kind or when it was meant for a card that is no longer the one shown.

@MainActor
final class LinkService: ObservableObject {
    static let shared = LinkService()
    /// In every build (Debug, Release and App Store): `scripts/check-app-binary.sh` looks for it. The Devices section carries it as its accessibility identifier. A marker must be 16 bytes or more:
    /// Swift keeps a shorter string literal inside the instruction that uses it, where `strings` cannot see it, and a Release build would then seem to lack the link.
    static let marker = "NM_LINK_ENGINE_ACTIVE"

    /// What the `.link` island view shows.
    enum Card: Equatable {
        /// A pairing under way: the six digits, the other machine's authenticated name, and whether this user has answered.
        case pair(code: String, peer: String, answered: Bool)
        /// An offer waiting for a click. Nothing accepts it but the user.
        case offer(LinkOffer)
        case receiving(LinkOffer, received: UInt64)
        /// The end of something: a short title and line, and the file when one was saved.
        case result(title: String, detail: String, file: URL?)

        /// The flow a card with buttons belongs to. A result is given the flow that ended by that flow itself.
        var flow: String? {
            switch self {
            case .pair(let code, let peer, _): return "pair:\(code)|\(peer)"
            case .offer(let o), .receiving(let o, _): return "transfer:\(Self.key(o))"
            case .result: return nil
            }
        }

        /// The machine and the transfer id, together: the transfer id is the other machine's own number.
        static func key(_ o: LinkOffer) -> String { LinkCardRules.offerKey(peerId: o.peerId, transferId: o.transferId) }

        /// What the user sees, for `LinkCardRules`: the kind and what it is about, without the answered flag or the progress.
        var shown: LinkCardRules.Shown {
            switch self {
            case .pair(let code, let peer, _): return .init(kind: .pair, key: "\(code)|\(peer)")
            case .offer(let o): return .init(kind: .offer, key: Self.key(o))
            case .receiving(let o, _): return .init(kind: .receiving, key: Self.key(o))
            case .result(let title, let detail, _): return .init(kind: .result, key: "\(title)|\(detail)")
            }
        }
    }

    @Published private(set) var settings: LinkSettings
    @Published private(set) var rows: [LinkDirectory.Row] = []
    @Published private(set) var listening = false
    /// A sentence for Settings → Devices when the listener or the Keychain could not do what was asked; nil otherwise.
    @Published private(set) var problem: String?
    @Published private(set) var card: Card? { didSet { cardChanged(old: oldValue) } }
    /// One line for the shelf's bar while this Mac sends ("Sending a.pdf to Desk PC, 45 %"). No file or machine name goes to a log.
    @Published private(set) var sendStatus: String?
    /// True from the click on a machine's chip until the last file has gone or the user cancelled: the shelf shows Cancel beside the status line while it is.
    @Published private(set) var sending = false
    /// A one-line note for Devices after a pairing that did not happen ("Wait 30 seconds before trying again").
    @Published private(set) var note: String?

    private static let keyProblem = "The link's key could not be read from the Keychain."
    private static let peersProblem = "The paired machines could not be read from the Keychain."

    private let backing: any LinkSettingsBacking
    private let keychain: LinkKeychain
    private let folder: URL
    private let host: String
    private var listener: LinkListener?
    /// Only the report of the listener that is the current one counts (`listenerState`): a stopped one may still say something.
    private var listenerToken: UUID?
    private var browser: LinkBrowser?
    private var browsers = 0
    /// A listener or a browser that failed comes back after a wait (LinkRestart.swift), while the Mac is visible and, for the browser, somebody is looking.
    private var listenerRestarter = LinkRestarter()
    private let listenerWait = LinkRestartWait()
    private var browserRestarter = LinkRestarter()
    private let browserWait = LinkRestartWait()
    private var seen: [String: LinkBrowser.Found] = [:]
    #if DEBUG && !APPSTORE
    /// Debug builds only: machines the Debug fake peer (LinkDevPeer.swift) put on the list, so a pairing and a transfer can be tried on the loopback address without a second computer.
    private var injected: [String: LinkBrowser.Found] = [:]
    private(set) var listenerPort: UInt16?
    private var found: [String: LinkBrowser.Found] { seen.merging(injected) { a, _ in a } }
    func debugInject(_ list: [LinkBrowser.Found]) { injected = Dictionary(list.map { ($0.advert.id, $0) }, uniquingKeysWith: { a, _ in a }); refreshRows() }
    func debugReceivedFolder() -> URL { folder }
    #else
    private var found: [String: LinkBrowser.Found] { seen }
    #endif
    /// The outbound connection of the send that is under way, from the moment it is made until the run on it has ended. Visible off cuts it whatever phase it is in; Cancel cuts it only while it is
    /// connecting, because a run that exists is asked to cancel (`cancelSending`) and sends its cancel frame before anything is cut.
    private var pendingConnection: NWConnection?
    private var pairingState = (initiator: LinkPairing.InitiatorState(), responder: LinkPairing.ResponderState())
    private var pairRun: LinkPairRun?
    /// Who may start a pairing with this Mac: only while Devices is open, or for 2 minutes after the user clicked Pair here (`LinkPairing.Gate`).
    private var pairGate = LinkPairing.Gate()
    private var pairingIncoming = false
    /// An outbound pairing from the click on Pair until it ends. Set before the first await, so two quick clicks start one.
    private var outbound = false
    private var receiveRun: LinkTransferReceive?
    private var sendRun: LinkTransferSend?
    private var sendQueueCancelled = false
    private let busy = LinkBusy()
    /// Established connections, 8 in all and 2 per machine (`LinkConnectionCaps`).
    private let caps = LinkConnectionCaps()
    /// The paired machines, as last read from the Keychain (`reloadPeers`). The Keychain is the truth: it is read again when a pairing is stored (`LinkKeychain.add` re-reads it itself), a machine is
    /// forgotten, Visible is turned on, Devices opens, a machine is not in the map (at most once in 5 s) and at launch.
    private var peers: [String: LinkPeer] = [:]
    private var readLimit = LinkReadLimit()
    /// This machine's device id and static key, read once and kept (they never change while the app runs).
    private var ownDeviceId: String?
    private var ownKey: Curve25519.KeyAgreement.PrivateKey?
    /// Who holds the card and when a click may act on it. The card is only ever changed through `present`.
    private var rules = LinkCardRules()
    /// The flows that have put a card on the island (the card's owner keys), so their ends clear only their own card.
    private var pairFlow: String?
    private var receiveFlow: String?
    /// Counts the times Visible was turned off, and tells which pairing and which transfer run is the current one. Everything that awaits (a connection, a handshake, a run) remembers the generation it
    /// started under, and every hook of a run carries the run's ticket: a late task of a stopped or replaced conversation acts on nothing (`LinkRunGate`, tested without the app).
    private var gate = LinkRunGate()
    private var generation: Int { gate.generation }
    /// Connections that are open now, so Visible off can cut them even before their conversation has a run to cancel.
    private var active: [UUID: LinkNWTransport] = [:]

    init(backing: any LinkSettingsBacking = UserDefaults.standard, keychain: LinkKeychain = LinkKeychain(), folder: URL = LinkFileSink.defaultFolder(), host: String = Host.current().localizedName ?? "Mac") {
        self.backing = backing
        self.keychain = keychain
        self.folder = folder
        self.host = host
        settings = LinkSettings.load(from: backing, host: host)
    }

    // MARK: Start, stop, settings

    /// At launch: reads the paired machines and, only when the user has turned "Visible on this network" on, starts the listener. Costs nothing otherwise.
    func start() {
        reloadPeers()
        if settings.visible { startListening() }
    }

    func setVisible(_ on: Bool) {
        guard on != settings.visible else { return }
        settings.visible = on
        settings.save(to: backing)
        if on {
            reloadPeers()
            startListening()
            if browsers > 0 { startBrowser() }   // Devices was already open: turning Visible on starts the search
        } else {
            stopListening()
            stopBrowser()
        }
        refreshRows()
    }

    /// False when the name is not one a card would accept.
    @discardableResult
    func setDeviceName(_ name: String) -> Bool {
        guard let valid = LinkSettings.validName(name) else { return false }
        guard valid != settings.deviceName else { return true }
        settings.deviceName = valid
        settings.save(to: backing)
        if settings.visible { restartAdvert() }
        return true
    }

    /// The advert carries the name, so a new listener takes over. Connections that were accepted are sockets of their own and the conversations on them do not depend on the listener: a pairing or a
    /// transfer that is running is not touched (this is not `stopListening`).
    private func restartAdvert() {
        listener?.stop(); listener = nil; listenerToken = nil
        listening = false
        startListening()
    }

    /// Puts a Keychain line in Devices, or takes it away again once a read worked. Only the Keychain's own lines come and go here; the listener's are `listenerFine()` and its two failures.
    private func report(_ line: String, failed: Bool) {
        if failed { problem = line } else if problem == line { problem = nil }
    }

    /// The listener is fine: its lines go. A Keychain line stays until a read of the Keychain works.
    private func listenerFine() {
        if problem != Self.keyProblem, problem != Self.peersProblem { problem = nil }
    }

    /// This machine's identity, from memory once it has been read. A read that fails is not kept: the next call reads again, and the Devices line says it could not be read until one works.
    private func identity() -> LinkIdentity? {
        do {
            let id = try ownDeviceId ?? keychain.deviceId()
            let key = try ownKey ?? keychain.staticKey()
            ownDeviceId = id; ownKey = key
            report(Self.keyProblem, failed: false)
            return LinkIdentity(deviceId: id, name: settings.deviceName, key: key)
        } catch { report(Self.keyProblem, failed: true); return nil }
    }

    /// The device id alone, for the browser and the list (they do not need the key): from memory, or read once.
    private func deviceId() -> String? {
        if ownDeviceId == nil { ownDeviceId = try? keychain.deviceId() }
        return ownDeviceId
    }

    /// Starts the listener, or asks the one this service holds to start again: `LinkListener.start` is idempotent (nothing changes while it is alive, a new socket when it has failed and dropped
    /// itself), so a failed listener is restarted by calling this again (Devices opening, the name changing, Visible turned on) without anything being orphaned.
    @discardableResult
    private func startListening() -> Bool {
        guard let me = identity() else { return false }
        let fresh = listener == nil
        let token = UUID()
        let gen = generation   // a listener lives inside one generation (Visible off drops it), so a connection it accepts is stamped with the one it was built under
        let l = listener ?? LinkListener(onConnection: { [weak self] transport, slot in Task { @MainActor in await self?.handleIncoming(transport, slot, gen: gen) } },
                                         onState: { [weak self] port, failed in Task { @MainActor in self?.listenerState(token: token, port: port, failed: failed) } })
        do {
            try l.start(advert: (me.deviceId, me.name))
            if fresh { listener = l; listenerToken = token; listenerFine(); appendAppLog("link.log", "listening") }
            return true
        } catch { problem = "This Mac could not start listening."; listening = false; return false }
    }

    /// Visible turned off: nothing keeps running. Conversations are cancelled and their connections cut (also those that have no run yet), and everything that was awaiting is made stale by
    /// the new generation. A card that belonged to one of them goes, since nothing is left to answer.
    private func stopListening() {
        gate.stop()
        listenerRestarter.setWanted(false); listenerWait.cancel()
        listener?.stop(); listener = nil; listenerToken = nil
        listening = false
        sendQueueCancelled = true
        pairRun?.cancel(); receiveRun?.cancel(); sendRun?.cancel()
        pendingConnection?.cancel(); pendingConnection = nil
        pairRun = nil; receiveRun = nil; sendRun = nil
        outbound = false; pairingIncoming = false; sending = false
        pairFlow = nil; receiveFlow = nil
        sendStatus = nil
        let open = active.values
        active = [:]
        open.forEach { $0.abort() }
        rules = LinkCardRules()
        card = nil
        appendAppLog("link.log", "stopped listening")
    }

    private func recordPort(_ port: UInt16?) {
        #if DEBUG && !APPSTORE
        listenerPort = port
        #endif
    }

    private func listenerState(token: UUID, port: UInt16?, failed: Bool) {
        guard token == listenerToken else { return }   // a listener that was stopped or replaced
        // A failed report is not final: the listener may be waiting for the network (no interface, no permission yet) and become ready again, which clears the line; or it may have dropped itself,
        // in which case a new socket is made: the armed wait (`listenerLost`) restarts it, and `devicesOpened()` also tries it when Visible is on and nothing listens.
        if failed {
            listening = false; problem = "This Mac can't listen right now. Check System Settings, Privacy & Security, Local Network."
            if !(listener?.isRunning ?? false) { listenerLost() }   // it dropped itself (a listener that is only waiting for the network is still held, and comes back by itself)
        } else if port != nil { listening = true; listenerFine(); recordPort(port) }
    }

    /// The listener failed and dropped itself. It comes back after a wait that grows (1 s, 5 s, 30 s, then every minute) while the Mac is visible; Visible off ends it.
    private func listenerLost() {
        guard settings.visible else { return }
        listenerRestarter.setWanted(true)
        guard let ms = listenerRestarter.died(nowMs: Self.nowMs()) else { return }
        listenerWait.arm(ms: ms) { [weak self] in self?.relaunchListener() }
    }

    private func relaunchListener() {
        guard settings.visible else { return }
        if startListening() { listenerRestarter.started(nowMs: Self.nowMs()) }
        else if let ms = listenerRestarter.failedRestart() { listenerWait.arm(ms: ms) { [weak self] in self?.relaunchListener() } }
    }

    // MARK: Browsing (only while Send or Devices is open)

    func beginBrowsing() {
        browsers += 1
        startBrowser()
    }

    func endBrowsing() {
        browsers = max(0, browsers - 1)
        guard browsers == 0 else { return }
        stopBrowser()
        if !sending { sendStatus = nil }   // the last line of a finished send does not wait for the next time the shelf opens
        refreshRows()
    }

    /// Browses when someone is looking (`browsers > 0`) and the Mac is visible: called when the first opener appears and when Visible is turned on while Devices is open.
    private func startBrowser() {
        guard browser == nil, browsers > 0, settings.visible, let id = deviceId() else { return }
        let b = LinkBrowser(ownId: id, onResults: { [weak self] results in Task { @MainActor in self?.browsed(results) } },
                            onFailed: { [weak self] in Task { @MainActor in self?.browserLost() } })
        browser = b
        b.start()
    }

    private func stopBrowser() {
        browserRestarter.setWanted(false); browserWait.cancel()
        browser?.stop(); browser = nil
        seen = [:]
    }

    /// The browser failed: the list on screen is stale, so it is emptied, and the browser starts again after a wait that grows (1 s, 5 s, 30 s, then every minute) while somebody is looking.
    private func browserLost() {
        guard browser != nil, browsers > 0, settings.visible else { return }
        seen = [:]
        refreshRows()
        browserRestarter.setWanted(true)
        guard let ms = browserRestarter.died(nowMs: Self.nowMs()) else { return }
        browserWait.arm(ms: ms) { [weak self] in self?.relaunchBrowser() }
    }

    private func relaunchBrowser() {
        guard let b = browser, browsers > 0, settings.visible else { return }
        b.start()   // idempotent: the failed browser was cleared, so this browses again; if it fails again `browserLost` is called again
        browserRestarter.started(nowMs: Self.nowMs())
    }

    private func browsed(_ results: [LinkBrowser.Found]) {
        guard browser != nil else { return }   // a result that was on its way when the browser was stopped
        seen = Dictionary(results.map { ($0.advert.id, $0) }, uniquingKeysWith: { a, _ in a })
        refreshRows()
    }

    /// Builds the list from what is in memory: no Keychain read (the browser may report many times a second).
    private func refreshRows() {
        rows = LinkDirectory.rows(adverts: found.values.map(\.advert), peers: peers, ownId: deviceId() ?? "")
    }

    /// The read of the paired machines: at launch, when Visible is turned on, when Devices opens, on a miss (`pairedPeer`), and after a pairing was stored or a machine forgotten. A read that cannot
    /// be trusted (an item that will not read, or nothing at all where there were machines: a locked Keychain lists nothing) keeps the last good map and puts a line in Devices.
    private func reloadPeers() {
        readLimit.read(now: Self.nowMs())
        do {
            peers = try keychain.pairedMachines(expectingSome: !peers.isEmpty)
            report(Self.peersProblem, failed: false)
        } catch { report(Self.peersProblem, failed: true) }
        refreshRows()
    }

    /// A paired machine, from memory; when it is not there the Keychain is read again, at most once in 5 s, so a read that failed for a moment does not leave a paired machine unknown until the next
    /// launch, and a peer that sends ids that are not paired cannot make this Mac read the Keychain in a loop.
    private func pairedPeer(_ id: String) -> LinkPeer? {
        if peers[id] == nil, readLimit.due(now: Self.nowMs()) { reloadPeers() }
        return peers[id]
    }

    func forget(_ id: String) {
        keychain.forget(id)
        peers[id] = nil      // so that what is left is the whole map, and a read that finds none is a failed one
        refuseTransfer(from: id)
        reloadPeers()
    }

    /// A machine that was just forgotten is no longer trusted: an offer of it that waits for a click is declined and a file of it that comes in is cancelled, and the card goes now, so no click can
    /// accept or complete what that machine started. The run answers for its own end (`receiveFlow` is cleared, so its end touches nothing of the island).
    private func refuseTransfer(from id: String) {
        guard let run = receiveRun, let flow = receiveFlow, flow == card?.flow else { return }
        switch card {
        case .offer(let o)? where o.peerId == id: run.respond(accept: false)
        case .receiving(let o, _)? where o.peerId == id: run.cancel()
        default: return
        }
        receiveFlow = nil
        present(nil, owner: flow)
    }

    /// Settings → Devices is on screen (or not): while it is, another machine may start a pairing with this one.
    func devicesOpened() {
        pairGate.devicesAppeared()
        reloadPeers()
        if settings.visible && !listening { startListening() }
    }
    func devicesClosed() { pairGate.devicesDisappeared() }

    // MARK: The card

    /// The one way a flow changes the card: `card` is its card, or nil to take its card away. False when another flow's card with buttons is on the island (the card is then left as it is, and
    /// nothing is shown), or when `card` is nil and the card on the island is not this flow's.
    @discardableResult
    private func present(_ new: Card?, owner: String) -> Bool {
        guard let new else {
            guard rules.end(owner: owner) else { return false }
            card = nil
            return true
        }
        guard rules.show(new.shown, owner: owner, now: Self.nowMs()) else { return false }
        card = new
        return true
    }

    // MARK: Pairing

    /// "Pair a machine": this Mac starts a pairing with a machine it has seen.
    func pair(with id: String) {
        guard settings.visible else { note = "Turn on Visible on this network first."; return }
        guard pairRun == nil, !outbound, !pairingIncoming, let target = found[id], let me = identity() else { return }
        guard !rules.interactive else { note = "Answer the card on the island first."; return }
        outbound = true
        pairGate.pairClicked(now: Self.nowMs())
        note = nil
        let gen = generation
        let nonce = Data((0..<32).map { _ in UInt8.random(in: 0...255) })
        Task {
            do {
                let transport = try await LinkNWTransport.ready(NWConnection(to: target.endpoint, using: .tcp), on: DispatchQueue(label: "notchmeow.link.out"))
                guard gen == self.generation else { transport.abort(); return }   // Visible was turned off while connecting
                let key = UUID()
                self.active[key] = transport
                defer { self.active[key] = nil }
                // The handshake has 10 seconds, as the listener gives one on the other side: a machine that connects and then says nothing does not hold this Mac's pairing slot.
                let deadline = Task { try? await Task.sleep(for: .seconds(LinkListener.handshakeSeconds)); if !Task.isCancelled { transport.abort() } }
                defer { deadline.cancel() }
                let ticket = self.gate.beginPair()
                let run = LinkPairRun(transport: transport, identity: me, nonce: nonce, clock: Self.nowMs, hooks: self.pairHooks(ticket, done: { deadline.cancel() }))
                self.pairRun = run
                appendAppLog("link.log", "a pairing started")
                var state = self.pairingState.initiator
                state.ids = self.pairIds(me)
                let (outcome, next) = await run.runInitiator(state)
                self.pairingState.initiator = next
                self.pairEnded(outcome, ownId: me.deviceId, gen: gen, outbound: true)
            } catch {
                guard gen == self.generation else { return }
                self.outbound = false; self.pairRun = nil
                self.note = "Could not reach that machine."
            }
        }
    }

    /// The snapshot a pairing starts with: from memory (the store re-reads the Keychain, `LinkKeychain.add`).
    private func pairIds(_ me: LinkIdentity) -> LinkPairing.Ids { LinkPairing.Ids(ownId: .value(me.deviceId), paired: peers.mapValues(\.key)) }

    private nonisolated func pairHooks(_ ticket: LinkRunGate.Ticket, done: @escaping @Sendable () -> Void = {}) -> LinkPairRun.Hooks {
        LinkPairRun.Hooks(showCode: { [weak self] code, name in Task { @MainActor in self?.codeKnown(code, name, ticket) } }, handshakeDone: done)
    }

    /// The code of a pairing is known. It takes the card only if no other flow's card with buttons is up (or an offer is claimed and about to take it); otherwise the pairing is ended (nothing was
    /// ever shown for it). A code that comes from a stopped or replaced pairing (`ticket` is not the current one) does nothing, and does not touch the current run.
    private func codeKnown(_ code: String, _ name: String, _ ticket: LinkRunGate.Ticket) {
        guard gate.isPair(ticket) else { return }
        let card = Card.pair(code: code, peer: name, answered: false)
        if busy.reserveCard(), present(card, owner: card.flow ?? "") { pairFlow = card.flow } else { pairRun?.cancel() }
    }

    /// The user's click on "They match" or "No". `shown` is the card the click was meant for (nil: the one on the island).
    func answerPair(yes: Bool, for shown: LinkCardRules.Shown? = nil) {
        guard case .pair(let code, let peer, false)? = card, rules.accepts(shown, now: Self.nowMs()), let run = pairRun, pairFlow == card?.flow else { return }   // pairFlow is set only by the current run's own code
        let next = Card.pair(code: code, peer: peer, answered: true)
        present(next, owner: next.flow ?? "")
        run.answer(yes)
    }

    /// `gen` is the generation the pairing started under: after Visible was turned off nothing of it is touched (the state it cleared stays cleared), and only a pairing both users said yes to is kept.
    /// `outbound` is true for a pairing this user started: only that one may leave a note in Devices (a machine that connects and is refused must not write on this Mac's screen).
    private func pairEnded(_ outcome: LinkPairOutcome, ownId: String, gen: Int, outbound started: Bool) {
        let flow = pairFlow
        appendAppLog("link.log", "a pairing ended")
        guard gen == generation else {
            if case .paired(let peer) = outcome { try? keychain.add(peer, ownId: ownId); reloadPeers() }
            return
        }
        pairRun = nil; outbound = false; pairFlow = nil
        gate.endPair()
        switch outcome {
        case .paired(let peer):
            // Both users said yes. The paired map is read again here, at the moment of storing (two pairings can overlap for up to two minutes).
            let result: Card
            do { try keychain.add(peer, ownId: ownId); reloadPeers(); result = .result(title: "Paired", detail: "This Mac and \(peer.name) can now send files to each other.", file: nil) }
            catch { result = .result(title: "Not paired", detail: "That machine could not be saved.", file: nil) }
            if let flow { present(result, owner: flow) }
        case .declined(let byMe):
            if let flow { present(byMe ? nil : .result(title: "Not paired", detail: "The other machine said the codes did not match.", file: nil), owner: flow) }
        case .refused(let why):
            if let flow { present(nil, owner: flow) }
            if started { note = why == LinkPairing.Refusal.attemptTooSoon.rawValue ? "Wait 30 seconds before trying again." : "The pairing did not go through." }
        }
        refreshRows()
    }

    // MARK: Incoming connections

    /// The run of an incoming transfer, as the main actor knows it: set when it becomes the one that may show a card (its first offer is waiting for a click), never before.
    private final class ReceiveHandle: @unchecked Sendable {
        var run: LinkTransferReceive?
        var ticket: LinkRunGate.Ticket?
    }

    /// `gen` is the generation the listener that accepted the socket was built under: a connection that was accepted before Visible was turned off is closed, however late its task runs.
    private func handleIncoming(_ t: LinkNWTransport, _ slot: LinkPendingSlot, gen: Int) async {
        // Nothing is accepted while the Mac is not visible: a connection that a stopped listener had already taken is closed.
        guard gen == generation, settings.visible else { slot.finish(); await t.close(); return }
        let key = UUID()
        active[key] = t
        defer { active[key] = nil; caps.release(key) }
        // The first record comes first: nothing is looked up, read from the Keychain or decided for a connection that has not sent a valid one.
        guard let pre = try? LinkWire.decodePreamble(try await t.receive()), gen == generation else { slot.finish(); await t.close(); return }
        switch pre.mode {
        case .pair:
            // Outside the gate (Devices closed and no Pair click in the last 2 minutes), while another pairing runs, or while a card with buttons is on the island: refused silently, nothing sent,
            // no card, no alert. A code from another machine never appears in front of a card the user is about to click.
            guard pairRun == nil, !outbound, !pairingIncoming, !rules.interactive, pairGate.allows(now: Self.nowMs()) else { slot.finish(); await t.close(); return }
            guard let me = identity() else { slot.finish(); await t.close(); return }
            pairingIncoming = true
            var state = pairingState.responder
            state.ids = pairIds(me)
            let ticket = gate.beginPair()
            let result = await LinkIncomingPairing.run(transport: t, identity: me, nonce: Data((0..<32).map { _ in UInt8.random(in: 0...255) }), clock: Self.nowMs, gate: pairGate, state: state,
                                                       hooks: pairHooks(ticket, done: { slot.finish() }),
                                                       made: { [weak self] run in Task { @MainActor in if let self, self.gate.isPair(ticket) { self.pairRun = run } } })
            slot.finish()
            guard let (outcome, next) = result else { if gen == generation { pairingIncoming = false; gate.endPair() }; return }
            appendAppLog("link.log", "a pairing started")
            pairingState.responder = next
            if gen == generation { pairingIncoming = false }
            pairEnded(outcome, ownId: me.deviceId, gen: gen, outbound: false)
        case .transfer:
            // A transfer runs only between paired machines: an id this Mac does not know is closed without an answer.
            guard let peer = pairedPeer(pre.id), let me = identity() else { slot.finish(); await t.close(); return }
            // The run is not "the" receive run until its offer is waiting for a click (`offerArrived`): a connection that has only said hello holds nothing and blocks nobody. One transfer holds the
            // card: a second one still gets its answer, "busy" (reason 2), and no card, because its claim fails (`LinkBusy`).
            let busy = self.busy, caps = self.caps
            let handle = ReceiveHandle()
            // The run keeps its transfer place until this function gives it back (`releaseAtEnd: false`), after `receiveRun` is cleared: an offer that comes in between would otherwise find the place
            // free and `receiveRun` still set, and be declined for it.
            let run = LinkTransferReceive(transport: t, identity: me, peer: peer, folder: folder, hooks: LinkTransferReceive.Hooks(
                offered: { [weak self] offer in Task { @MainActor in self?.offerArrived(offer, handle, gen: gen) } },
                progress: { [weak self] got, _ in Task { @MainActor in if let ticket = handle.ticket { self?.progressed(got, ticket) } } },
                claim: { busy.claim($0) }, release: { busy.release($0) }, handshakeDone: { slot.finish() }, admit: { caps.admit(key, peer: peer.id) }, releaseAtEnd: false))
            handle.run = run
            appendAppLog("link.log", "a transfer started")
            let outcome = await run.run()
            // The run and its handle hold each other (the run holds its hooks, the hooks hold the handle): the run is over, so the handle lets go, and an offer that was still on its way can promote nothing.
            handle.run = nil
            slot.finish()
            appendAppLog("link.log", "a transfer ended")
            // The island first, so that no click reaches a run that is over; the transfer place is given back after that, and it is read only now (a suspension is a place for a click).
            if gen == generation, handle.ticket != nil {   // never promoted: nothing of the island was touched
                if receiveRun === run { receiveRun = nil; gate.endReceive() }
                receiveEnded(outcome)
            }
            let held = await run.holdsClaim
            if held { busy.release(peer.id) }
        }
    }

    /// An offer is waiting for a click: its run becomes the receive run now (not when its connection was accepted), and it takes the card only if no other flow's card with buttons is up; otherwise
    /// it is declined, and the user never sees it. An offer of a run that was made before Visible was turned off shows nothing and answers nothing.
    /// A pairing code cannot take the card between the claim and this call (`LinkBusy.reserveCard`), so the decline below is not reached by that race: the second offer is refused as busy (reason 2)
    /// at its claim. `LinkTransferReceive` has no way to send "busy" afterwards, only the user's decline.
    private func offerArrived(_ offer: LinkOffer, _ handle: ReceiveHandle, gen: Int) {
        guard gen == generation, let run = handle.run else { return }   // `handle.run` is nil once its run has ended: no promotion of a run that is over
        // Another run still holds the place (its claim is given back after it is cleared, `handleIncoming`), so this is not reached by a run that is over; if it ever is, this one is declined rather
        // than put beside it.
        guard receiveRun == nil else { run.respond(accept: false); return }
        receiveRun = run
        handle.ticket = gate.beginReceive()
        let card = Card.offer(offer)
        if present(card, owner: card.flow ?? "") { receiveFlow = card.flow } else { run.respond(accept: false) }
    }

    /// Bytes came in. `LinkTransferReceive` does not give the transfer id with them, but a run has one offer, so the ticket stands for it: the tick counts only when it is from the run whose offer is
    /// the card on the island (`receiveFlow` is set by that run's own offer, and by nothing else).
    private func progressed(_ got: UInt64, _ ticket: LinkRunGate.Ticket) {
        guard gate.isReceive(ticket) else { return }
        switch card {
        case .offer(let o)?, .receiving(let o, _)?:
            guard let flow = receiveFlow, flow == card?.flow else { return }
            present(.receiving(o, received: got), owner: flow)
        default: break
        }
    }

    /// The user's click on Accept or Decline. The only way an offer is accepted. `shown` is the card the click was meant for (nil: the one on the island).
    func respondOffer(accept: Bool, for shown: LinkCardRules.Shown? = nil) {
        // The run answered is the one whose offer this is: `receiveFlow` is the key of the offer the current run showed.
        guard case .offer(let o)? = card, rules.accepts(shown, now: Self.nowMs()), let run = receiveRun, receiveFlow == card?.flow else { return }
        // An offer whose run has already ended (expired, withdrawn) is not accepted: the end is on its way and shows what happened.
        if accept { guard busy.holds(o.peerId) else { return }; present(.receiving(o, received: 0), owner: "transfer:\(Card.key(o))") }
        run.respond(accept: accept)
    }

    func cancelReceiving(for shown: LinkCardRules.Shown? = nil) {
        guard case .receiving? = card, rules.accepts(shown, now: Self.nowMs()), let run = receiveRun, receiveFlow == card?.flow else { return }
        run.cancel()
    }

    private func receiveEnded(_ outcome: LinkTransferOutcome) {
        guard let flow = receiveFlow else { return }   // no card was ever shown for it (declined as busy, a failed handshake): nothing of the island is touched
        receiveFlow = nil
        switch outcome {
        case .completed(let url): present(.result(title: "Received", detail: url.map { "Saved as \($0.lastPathComponent) in Downloads/NotchMeow." } ?? "Saved.", file: url), owner: flow)
        case .declined, .withdrawn: present(nil, owner: flow)
        case .expired: present(.result(title: "Offer expired", detail: "Nobody answered in 2 minutes, so it was declined.", file: nil), owner: flow)
        case .cancelled: present(.result(title: "Transfer cancelled", detail: "Nothing was saved.", file: nil), owner: flow)
        case .aborted: present(.result(title: "Transfer stopped", detail: "The connection ended before the file was complete. Nothing was saved.", file: nil), owner: flow)
        }
    }

    /// The OK on a result, or the close of any card: what the user dismissed is answered "no" / "cancel" for its flow, and a result goes.
    func dismissCard(for shown: LinkCardRules.Shown? = nil) {
        switch card {
        case .offer?: respondOffer(accept: false, for: shown)
        case .pair(_, _, false)?: answerPair(yes: false, for: shown)
        case .receiving?: cancelReceiving(for: shown)
        case .result?: if rules.accepts(shown, now: Self.nowMs()) { present(nil, owner: rules.owner ?? "") }
        default: break
        }
    }

    // MARK: Sending

    /// Sends the shelf's items to a paired machine, one after the other (each is its own offer, and the other user answers each). Every wait in it ends: the connect in 10 s, the handshake in
    /// 10 s, an offer nobody answers in 130 s, a stalled file in 60 s, and Cancel within 2 s (`cancelSending`); in each case `sending` goes back to false.
    func send(_ items: [ShelfItem], to id: String, model: ShelfModel) {
        guard !sending, sendRun == nil else { return }
        guard let peer = pairedPeer(id), let target = found[id], let me = identity() else { sendStatus = "That machine is not on the network."; return }
        sendQueueCancelled = false
        let accesses = items.compactMap { model.open($0) }
        guard accesses.count == items.count else { sendStatus = "A file is missing."; accesses.forEach { $0.end() }; return }
        sending = true
        let gen = generation
        Task {
            defer { accesses.forEach { $0.end() }; if gen == self.generation { self.sending = false; self.sendRun = nil } }
            var sent = 0
            for access in accesses {
                if self.sendQueueCancelled || gen != self.generation { break }
                let source: LinkFileSource
                do { source = try LinkFileSource(url: access.url) } catch { self.sendStatus = "\(access.url.lastPathComponent) cannot be sent (a folder, a file over 4 GB, or a name that is too long)."; continue }
                self.sendStatus = "Waiting for \(peer.name) to accept \(source.name)"
                // Cancel cuts this connection while it is connecting; once there is a run, the run is asked to cancel and cuts it itself if it has to (`cancelSending`).
                let connection = NWConnection(to: target.endpoint, using: .tcp)
                self.pendingConnection = connection
                defer { if self.pendingConnection === connection { self.pendingConnection = nil } }
                do {
                    let transport = try await LinkNWTransport.ready(connection, on: DispatchQueue(label: "notchmeow.link.out"))
                    guard gen == self.generation else { transport.abort(); return }   // Visible was turned off while connecting
                    // Cancel was clicked while connecting: there is no run to cancel yet, and none is made.
                    if self.sendQueueCancelled { transport.abort(); self.sendStatus = "Cancelled"; break }
                    let key = UUID()
                    self.active[key] = transport
                    defer { self.active[key] = nil }
                    let run = LinkTransferSend(transport: transport, identity: me, peer: peer, source: source, hooks: .init(progress: { done, total in
                        Task { @MainActor in if gen == self.generation, !self.sendQueueCancelled { self.sendStatus = "Sending \(source.name) to \(peer.name), \(LinkText.percent(done, total)) %" } }
                    }))
                    self.sendRun = run
                    appendAppLog("link.log", "a send started")
                    let outcome = await run.run()
                    guard gen == self.generation else { return }
                    self.sendRun = nil
                    switch outcome {
                    // The protocol has no receipt: all the bytes and the end marker went out, which is all this side can say.
                    case .completed: sent += 1; self.sendStatus = "Finished sending \(source.name) to \(peer.name)"
                    case .declined(let r): self.sendStatus = r == 1 ? "\(peer.name) did not answer in time" : r == 2 ? "\(peer.name) is receiving something else right now" : r == 3 ? "\(source.name) is too large" : "\(peer.name) declined \(source.name)"
                    case .expired: self.sendStatus = "\(peer.name) did not answer in time"; self.sendQueueCancelled = true
                    case .withdrawn, .cancelled: self.sendStatus = "Cancelled"; self.sendQueueCancelled = true
                    case .aborted: self.sendStatus = self.sendQueueCancelled ? "Cancelled" : "The connection to \(peer.name) ended"
                    }
                } catch {
                    guard gen == self.generation else { return }
                    // A connection that Cancel cut did not "fail to be reached": the status stays "Cancelled".
                    self.sendStatus = self.sendQueueCancelled ? "Cancelled" : "Could not reach \(peer.name)."
                }
            }
            if sent > 1, gen == self.generation, !self.sendQueueCancelled { self.sendStatus = "Finished sending \(sent) files to \(peer.name)" }
        }
    }

    /// The Cancel on the shelf's status line. The files that were still to go are not sent, and the send ends within 2 s, whatever phase it is in. A run that exists sends its cancel frame first (the
    /// other side's user then sees "cancelled", not a connection that dropped), and cuts the connection itself only if that frame cannot go out in time, or if the handshake is not over in
    /// time (`LinkTransferSend.cancel`): the connection is not cut from here. Before there is a run (connecting) there is nobody to tell, and the connection is cut now.
    func cancelSending() {
        guard sending else { return }
        sendQueueCancelled = true
        if let run = sendRun { run.cancel() } else { pendingConnection?.cancel(); sendStatus = "Cancelled" }
    }

    // MARK: Island

    private func cardChanged(old: Card?) {
        let state = AppState.shared
        let offer: Bool = { if case .offer? = card { return true }; return false }()
        let hold: Bool = { switch card { case .pair?, .offer?, .receiving?: return true; default: return false } }()
        if state.linkOfferPending != offer { state.linkOfferPending = offer }
        if state.linkHoldsIsland != hold { state.linkHoldsIsland = hold }
        busy.setCardLocked(hold)   // an offer that arrives now is declined as busy, whatever thread its run is on
        if card != nil && old == nil || (card != nil && !sameKind(card, old)) { NotificationCenter.default.post(name: .hookExpand, object: IslandView.link) }
        if card == nil, state.view == .link { NotificationCenter.default.post(name: .islandCollapse, object: nil) }
    }

    private func sameKind(_ a: Card?, _ b: Card?) -> Bool {
        switch (a, b) {
        case (.pair?, .pair?), (.offer?, .offer?), (.receiving?, .receiving?), (.result?, .result?): return true
        default: return false
        }
    }

    /// Whole milliseconds, monotonic, and counting while the Mac sleeps (`LinkClock`).
    nonisolated static func nowMs() -> Int { LinkClock.nowMs() }
}

extension LinkKeychain {
    /// The paired machines, as `peers()` reads them, but a read that cannot be trusted throws instead of coming back short: an item that is there and will not read (the Keychain is locked, a prompt
    /// was refused), or no machine at all when `expectingSome` (a locked Keychain lists nothing; a machine is never removed behind the app's back that this Mac still should trust).
    func pairedMachines(expectingSome: Bool) throws -> [String: LinkPeer] {
        for account in store.accounts(prefix: Self.peerPrefix) where store.lookup(account) == .failed { throw LinkKeychainError.readFailed }
        let read = peers()
        if expectingSome, read.isEmpty { throw LinkKeychainError.readFailed }
        return read
    }
}
