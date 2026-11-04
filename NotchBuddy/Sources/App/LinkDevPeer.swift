#if DEBUG && !APPSTORE

import AppKit
import CryptoKit
import SwiftUI
@preconcurrency import Network

/// The Debug-only fake peer (sub-project G2): a second machine inside this Mac, on the loopback address, so that a pairing, an Accept card, a transfer each way, a decline, a cancel and a refusal can be
/// tried without a second computer. It has an identity and a Keychain of its own **in memory**, listens on 127.0.0.1 without announcing itself, puts itself on this Mac's list of machines, and
/// speaks the same code as the real thing (LinkPairRun, LinkTransferReceive, LinkTransferSend over LinkNWTransport). Compiled in Debug builds only: `scripts/check-app-binary.sh` proves it is not in Release
/// or App Store builds (`marker`). Opened from the menu bar's "Link (Debug)…". Pairing it writes a real entry (named "Debug Peer") in this Mac's Keychain; Forget removes it.
@MainActor
final class LinkDevPeer: ObservableObject {
    static let marker = "NM_LINK_DEV_PEER"

    @Published private(set) var log: [String] = []
    @Published private(set) var running = false
    /// The code the fake peer shows while a pairing waits for its answer.
    @Published private(set) var code: String?
    /// Accept this peer's own incoming offers by itself (the fake peer is not a person; the real app never does this).
    @Published var autoAccept = true

    private let identity = LinkIdentity(deviceId: String(repeating: "dd", count: 16), name: "Debug Peer", key: Curve25519.KeyAgreement.PrivateKey())
    private let keychain = LinkKeychain(store: MemorySecretStore())
    private var listener: LinkListener?
    private var pairRun: LinkPairRun?
    private var receiveRun: LinkTransferReceive?
    private var pairing = LinkPairing.ResponderState()
    let inbox = FileManager.default.temporaryDirectory.appendingPathComponent("NotchMeow-link-dev-\(UUID().uuidString)", isDirectory: true)

    func say(_ line: String) { log.append(line); if log.count > 10 { log.removeFirst(log.count - 10) } }

    func start() {
        guard listener == nil else { return }
        let l = LinkListener(onConnection: { [weak self] t, slot in Task { @MainActor in await self?.incoming(t, slot) } },
                             onState: { [weak self] port, failed in Task { @MainActor in self?.listenerState(port, failed) } })
        do { try l.start(advert: nil, loopbackOnly: true); listener = l } catch { say("could not listen: \(error)") }
    }

    /// Stops the listener and takes its entry off this Mac's list (`debugInject([])` replaces every injected machine, so nothing of this peer stays there).
    func stop() {
        listener?.stop(); listener = nil; running = false
        LinkService.shared.debugInject([])
        say("stopped")
    }

    private func listenerState(_ p: UInt16?, _ failed: Bool) {
        // A report that arrives after Stop must not put the stopped peer back on the list.
        guard listener != nil else { return }
        guard let p, !failed else { if failed { say("the listener failed") }; return }
        running = true
        let ad = LinkWire.Advert(id: identity.deviceId, name: identity.name)
        LinkService.shared.debugInject([LinkBrowser.Found(advert: ad, endpoint: .hostPort(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: p)!))])
        say("listening on 127.0.0.1:\(p); it is on this Mac's list as Debug Peer")
    }

    func answerPair(_ yes: Bool) { pairRun?.answer(yes); code = nil }

    private func showCode(_ c: String, _ n: String) {
        code = c
        say("pairing with \(n): code \(c). Press They match here and in the island")
    }

    /// Both sides end a pairing the same way: its run and code go, and a machine that paired is kept (in this peer's Keychain, in memory) and logged. False when it did not pair.
    private func endPairing(_ outcome: LinkPairOutcome) -> Bool {
        pairRun = nil; code = nil
        guard case .paired(let peer) = outcome else { return false }
        try? keychain.add(peer, ownId: identity.deviceId)
        say("paired with \(peer.name)")
        return true
    }

    private func incoming(_ t: LinkNWTransport, _ slot: LinkPendingSlot) async {
        guard let pre = try? LinkWire.decodePreamble(try await t.receive()) else { slot.finish(); await t.close(); return }
        switch pre.mode {
        case .pair:
            let run = LinkPairRun(transport: t, identity: identity, nonce: Data((0..<32).map { _ in UInt8.random(in: 0...255) }), clock: LinkService.nowMs,
                                  hooks: .init(showCode: { [weak self] c, n in Task { @MainActor in self?.showCode(c, n) } }, handshakeDone: { slot.finish() }))
            pairRun = run
            pairing.ids = LinkPairing.Ids(ownId: .value(identity.deviceId), paired: keychain.pairedKeys())
            let (outcome, next) = await run.runResponder(pairing)
            pairing = next
            if !endPairing(outcome) { say("pairing ended: \(outcome)") }
        case .transfer:
            guard let peer = keychain.peer(pre.id) else { say("a transfer from a machine this peer does not know: closed"); slot.finish(); await t.close(); return }
            let run = LinkTransferReceive(transport: t, identity: identity, peer: peer, folder: inbox, hooks: .init(
                offered: { [weak self] o in Task { @MainActor in self?.say("offer: \(o.name), \(o.size) bytes"); if self?.autoAccept == true { self?.receiveRun?.respond(accept: true) } } },
                progress: { _, _ in }, claim: { _ in true }, release: { _ in }, handshakeDone: { slot.finish() }))
            receiveRun = run
            let outcome = await run.run()
            receiveRun = nil
            say("receiving ended: \(outcome)")
        }
    }

    /// The fake peer starts a pairing **with this Mac**: it is allowed only while Settings, Devices is open here, or within 2 minutes after you clicked Pair here (the owner's rule); at any other
    /// time this Mac refuses it silently, with no card, and the log says the connection ended without an answer.
    func pairWithMac() {
        guard let port = LinkService.shared.listenerPort else { say("this Mac is not listening: turn on Visible on this network in Settings, Devices"); return }
        Task {
            do {
                let transport = try await LinkNWTransport.ready(NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp), on: DispatchQueue(label: "notchmeow.link.devpeer.out"))
                let run = LinkPairRun(transport: transport, identity: identity, nonce: Data((0..<32).map { _ in UInt8.random(in: 0...255) }), clock: LinkService.nowMs,
                                      hooks: .init(showCode: { [self] c, n in Task { @MainActor in self.showCode(c, n) } }))
                self.pairRun = run
                self.say("asking this Mac to pair")
                var state = LinkPairing.InitiatorState()
                state.ids = LinkPairing.Ids(ownId: .value(identity.deviceId), paired: keychain.pairedKeys())
                let (outcome, _) = await run.runInitiator(state)
                if !endPairing(outcome) {
                    if case .refused("handshake") = outcome { self.say("this Mac ended the connection without an answer (outside the gate: Devices closed, no recent Pair click)") }
                    else { self.say("pairing ended: \(outcome)") }
                }
            } catch { self.say("could not reach this Mac: \(error)") }
        }
    }

    /// The fake peer offers this Mac a file of `bytes` zeros: the real listener must be on (Visible on this network) and the two must be paired.
    /// The file is written off the main actor; a failed write is logged, not swallowed.
    func offer(name: String, bytes: Int) {
        guard let port = LinkService.shared.listenerPort else { say("this Mac is not listening: turn on Visible on this network in Settings, Devices"); return }
        guard let target = keychain.peers().values.first else { say("not paired yet: pair from Settings, Devices first"); return }
        let dir = inbox, file = inbox.appendingPathComponent(name)
        Task {
            do {
                try await Task.detached(priority: .utility) {
                    try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
                    try makeTestFile(file, bytes: bytes)
                }.value
            } catch { self.say("could not write \(name): \(error.localizedDescription)"); return }
            do {
                let source = try LinkFileSource(url: file)
                let transport = try await LinkNWTransport.ready(NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp), on: DispatchQueue(label: "notchmeow.link.devpeer"))
                self.say("offering \(name) to this Mac")
                let outcome = await LinkTransferSend(transport: transport, identity: identity, peer: target, source: source, hooks: .init(progress: { _, _ in })).run()
                self.say("offer ended: \(outcome)")
            } catch { self.say("could not offer: \(error)") }
        }
    }

    deinit { try? FileManager.default.removeItem(at: inbox) }
}

/// A test file of `bytes` zeros. It is cut to its size rather than filled, so the 200 MB file costs no memory and no time; a failed write throws.
private func makeTestFile(_ file: URL, bytes: Int) throws {
    guard FileManager.default.createFile(atPath: file.path, contents: nil) else { throw CocoaError(.fileWriteUnknown) }
    let handle = try FileHandle(forWritingTo: file)
    defer { try? handle.close() }
    try handle.truncate(atOffset: UInt64(bytes))
}

/// The panel: start and stop the fake peer, answer its side of a pairing, make it offer a file, and read what it did.
struct LinkDevView: View {
    @StateObject private var dev = LinkDevPeer()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            GroupBox("The fake peer (a second machine on 127.0.0.1)") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button(dev.running ? "Stop" : "Start") { dev.running ? dev.stop() : dev.start() }
                        Toggle("It accepts its own incoming offers", isOn: $dev.autoAccept)
                    }
                    Text("Start it, turn on Visible on this network in Settings, Devices, and click Pair next to Debug Peer. This side shows the same code; press They match here and in the island.").font(.system(size: 11)).foregroundColor(.secondary)
                    HStack {
                        if let c = dev.code { Text(c).font(.system(size: 18, weight: .semibold, design: .monospaced)) }
                        Button("They match") { dev.answerPair(true) }.disabled(dev.code == nil)
                        Button("No") { dev.answerPair(false) }.disabled(dev.code == nil)
                    }
                }.padding(6)
            }
            GroupBox("Pair from this side") {
                HStack {
                    Button("Ask this Mac to pair") { dev.pairWithMac() }
                    Text("Refused silently unless Devices is open on this Mac, or you clicked Pair there in the last 2 minutes.").font(.system(size: 11)).foregroundColor(.secondary)
                }.padding(6)
            }
            GroupBox("Offer this Mac a file") {
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Button("3 MB file") { dev.offer(name: "debug-3mb.bin", bytes: 3_000_000) }
                        Button("200 MB file (to cancel)") { dev.offer(name: "debug-200mb.bin", bytes: 200_000_000) }
                        Button("A name with a path in it") { dev.offer(name: "..\\..\\etc\\passwd", bytes: 10) }
                    }
                    Text("A name with a path in it: expected outcome is declined as not acceptable (reason 4), and no file is saved.").font(.system(size: 11)).foregroundColor(.secondary)
                }.padding(6)
            }
            GroupBox("What it did") {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(Array(dev.log.enumerated()), id: \.offset) { Text($0.element).font(.system(size: 11, design: .monospaced)) }
                    if dev.log.isEmpty { Text("Nothing yet").font(.system(size: 11)).foregroundColor(.secondary) }
                }.frame(maxWidth: .infinity, alignment: .leading).padding(6)
            }
        }.padding(16).frame(minWidth: 620, minHeight: 360)
    }
}

#endif
