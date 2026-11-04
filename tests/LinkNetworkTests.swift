import Foundation
@preconcurrency import Network

// The Network.framework transport (LinkNetwork.swift) over real TCP on the loopback address: records cut out of a stream, a pairing and a transfer end to end through a LinkListener with no
// advert (so no Bonjour and no local-network prompt), a connection that stalls is cut, a record of length 0 closes. 127.0.0.1 only: nothing leaves the machine.
// Run it through scripts/test-link-network.sh.

actor Slot<T: Sendable> { var v: T?; func set(_ x: T) { v = x }; func get() -> T? { v }; var isSet: Bool { v != nil } }

/// The connections a listener handed over and did not finish, so the pending slots stay taken.
actor Held {
    private(set) var count = 0
    private var slots: [LinkPendingSlot] = []
    private var transports: [LinkNWTransport] = []
    func add(_ t: LinkNWTransport, _ s: LinkPendingSlot) { count += 1; slots.append(s); transports.append(t) }
    func finishFirst() { if !slots.isEmpty { slots.removeFirst().finish() } }
}

@main
enum LinkNetworkTests {
    static func identity(_ n: UInt8, _ name: String) -> LinkIdentity {
        LinkIdentity(deviceId: String(repeating: String(format: "%02x", n), count: 16), name: name, key: try! LinkNoise.privateKey(raw: Data(repeating: n, count: 32)))
    }

    /// Starts a loopback-only listener (no interface but lo0, so no local-network prompt) on a free port and waits for its port.
    static func listen(_ onConnection: @escaping @Sendable (LinkNWTransport, LinkPendingSlot) -> Void) async -> (LinkListener, UInt16) {
        let port = Slot<UInt16>()
        let l = LinkListener(onConnection: onConnection, onState: { p, _ in if let p { Task { await port.set(p) } } })
        try! l.start(advert: nil, loopbackOnly: true)
        for _ in 0..<400 { if await port.isSet { break }; try? await Task.sleep(for: .milliseconds(5)) }
        return (l, await port.get() ?? 0)
    }

    static func connect(_ port: UInt16) async throws -> LinkNWTransport {
        let c = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        return try await LinkNWTransport.ready(c, on: DispatchQueue(label: "test.client"))
    }

    /// True when nothing accepts on the loopback port: a connection is refused. A stop is not instant, so this tries for a moment (an orphan listener accepts every try and never passes).
    static func refused(_ port: UInt16) async -> Bool {
        for _ in 0..<40 {
            do {
                let t = try await connect(port)
                await t.close()
            } catch { return true }
            try? await Task.sleep(for: .milliseconds(50))
        }
        return false
    }

    @MainActor static func main() async {
        setvbuf(stdout, nil, _IONBF, 0)
        DispatchQueue.global().asyncAfter(deadline: .now() + 90) { print("timed out"); exit(1) }

        CT.section("records over TCP")
        let server = Slot<LinkNWTransport>()
        let (listener, port) = await listen { t, slot in slot.finish(); Task { await server.set(t) } }
        CT.checkTrue("the listener has a port", port != 0)
        let client = try! await connect(port)
        for _ in 0..<400 { if await server.isSet { break }; try? await Task.sleep(for: .milliseconds(5)) }
        let s = await server.get()!
        try! await client.send(Data("one".utf8))
        try! await client.send(Data(count: 65535))
        try! await client.send(Data("three".utf8))
        let r1 = try! await s.receive(), r2 = try! await s.receive(), r3 = try! await s.receive()
        CT.check("three records arrive whole and in order, the big one too", [String(decoding: r1, as: UTF8.self), "\(r2.count)", String(decoding: r3, as: UTF8.self)], ["one", "65535", "three"])
        var tooLong = false
        do { try await client.send(Data(count: 65536)) } catch { tooLong = (error as? LinkSessionError) == .violation("record length") }
        CT.checkTrue("a record of 65536 bytes is refused before it is sent", tooLong)
        try! await s.send(Data("back".utf8))
        CT.check("and the other way", String(decoding: try! await client.receive(), as: UTF8.self), "back")
        await client.close()
        var closed = false
        do { _ = try await s.receive() } catch { closed = (error as? LinkSessionError) == .closed }
        CT.checkTrue("a closed connection ends the other side's read", closed)

        CT.section("a record of length 0 closes")
        let c2 = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port)!, using: .tcp)
        let raw = try! await LinkNWTransport.ready(c2, on: DispatchQueue(label: "test.raw"))
        for _ in 0..<400 { if let t = await server.get(), t !== s { break }; try? await Task.sleep(for: .milliseconds(5)) }
        let s2 = await server.get()!
        c2.send(content: Data([0, 0]), completion: .contentProcessed { _ in })
        var violation = false
        do { _ = try await s2.receive() } catch { violation = (error as? LinkSessionError) == .violation("record") }
        CT.checkTrue("the reader throws a violation", violation)
        await raw.close()

        CT.section("a close after an abort returns at once, and the other side sees the end")
        let victim = try! await connect(port)
        for _ in 0..<400 { if let t = await server.get(), t !== s, t !== s2 { break }; try? await Task.sleep(for: .milliseconds(5)) }
        let victimPeer = await server.get()!
        victim.abort()
        let closeDone = Slot<Bool>()
        Task { await victim.close(); await closeDone.set(true) }
        for _ in 0..<200 { if await closeDone.isSet { break }; try? await Task.sleep(for: .milliseconds(5)) }
        CT.checkTrue("close() on a connection that was cut returns within a second (it waits for nothing)", await closeDone.isSet)
        var ended = false
        do { _ = try await victimPeer.receive() } catch { ended = true }
        CT.checkTrue("and the other end's read ends", ended)

        CT.section("a pairing through the listener")
        listener.stop()
        let mac = identity(0x11, "Studio Mac"), pc = identity(0x22, "Desk PC")
        let pcPeer = LinkPeer(id: pc.deviceId, name: pc.name, key: LinkBytes.hex(LinkNoise.publicKey(of: pc.key)), at: 1), macPeer = LinkPeer(id: mac.deviceId, name: mac.name, key: LinkBytes.hex(LinkNoise.publicKey(of: mac.key)), at: 1)
        let outcomes = Slot<LinkPairOutcome>(), codes = Slot<String>(), codesA = Slot<String>()
        let responderRun = Slot<LinkPairRun>()
        let (l2, port2) = await listen { t, slot in
            Task {
                guard let pre = try? LinkWire.decodePreamble(try await t.receive()), pre.mode == .pair else { slot.finish(); await t.close(); return }
                let run = LinkPairRun(transport: t, identity: pc, nonce: Data(repeating: 0xB1, count: 32), clock: { Int(DispatchTime.now().uptimeNanoseconds / 1_000_000) }, hooks: .init(showCode: { c, _ in Task { await codes.set(c) } }, handshakeDone: { slot.finish() }))
                await responderRun.set(run)
                let (o, _) = await run.runResponder(.init())
                await outcomes.set(o)
            }
        }
        let t = try! await connect(port2)
        let initiator = LinkPairRun(transport: t, identity: mac, nonce: Data(repeating: 0xA1, count: 32), clock: { Int(DispatchTime.now().uptimeNanoseconds / 1_000_000) }, hooks: .init(showCode: { c, _ in Task { await codesA.set(c) } }))
        Task {
            for _ in 0..<400 { if await codes.isSet, await codesA.isSet { break }; try? await Task.sleep(for: .milliseconds(5)) }
            initiator.answer(true); await responderRun.get()?.answer(true)
        }
        let (oi, _) = await initiator.runInitiator(.init())
        for _ in 0..<400 { if await outcomes.isSet { break }; try? await Task.sleep(for: .milliseconds(5)) }
        CT.check("both sides are paired over a real socket, and saw the same code", [oi == .paired(pcPeer.withAt(oi)), await outcomes.get() == .paired(macPeer.withAt(await outcomes.get())), await codes.get() == codesA.get()], [true, true, true])
        l2.stop()

        CT.section("a second start leaves no orphan, and stop closes the port")
        let firstPort = Slot<UInt16>()
        let twice = LinkListener(onConnection: { _, slot in slot.finish() }, onState: { p, _ in if let p { Task { await firstPort.set(p) } } })
        try! twice.start(advert: nil, loopbackOnly: true)
        for _ in 0..<400 { if await firstPort.isSet { break }; try? await Task.sleep(for: .milliseconds(5)) }
        let p1 = await firstPort.get() ?? 0
        CT.checkTrue("the first start has a port", p1 != 0)
        try! twice.start(advert: nil, loopbackOnly: true)   // a second start changes nothing
        twice.stop()
        let gone = await refused(p1)
        CT.checkTrue("after stop, the first port refuses connections (no orphan kept listening)", gone)

        CT.section("a listener that cannot bind reports it, and listens again later")
        let (busyListener, busyPort) = await listen { _, slot in slot.finish() }
        let failed = Slot<Bool>(), up = Slot<UInt16>()
        let retry = LinkListener(onConnection: { _, slot in slot.finish() }, onState: { p, f in if f { Task { await failed.set(true) } }; if let p { Task { await up.set(p) } } })
        try! retry.start(advert: nil, port: busyPort, loopbackOnly: true)
        for _ in 0..<400 { if await failed.isSet { break }; try? await Task.sleep(for: .milliseconds(5)) }
        CT.checkTrue("a port already in use is reported as a failure", await failed.isSet)
        busyListener.stop()
        var listening = false
        for _ in 0..<200 {
            try! retry.start(advert: nil, port: busyPort, loopbackOnly: true)
            for _ in 0..<10 { if await up.isSet { break }; try? await Task.sleep(for: .milliseconds(5)) }
            if await up.isSet { listening = true; break }
        }
        CT.checkTrue("once the port is free, a start listens again (the dead listener was cleared)", listening)
        retry.stop()

        CT.section("no more than 2 connections waiting for their handshake from one address")
        let held = Held()
        let (l4, port4) = await listen { t, slot in Task { await held.add(t, slot) } }
        let c1 = try! await connect(port4), c2b = try! await connect(port4)
        for _ in 0..<400 { if await held.count == 2 { break }; try? await Task.sleep(for: .milliseconds(5)) }
        CT.check("two connections are given to the service", await held.count, 2)
        let c3 = try? await connect(port4)
        var third = false
        if let c3 { do { _ = try await c3.receive() } catch { third = true } } else { third = true }
        CT.check("a third from the same address is cancelled and never given to the service", [third, await held.count == 2], [true, true])
        await held.finishFirst()
        let c4 = try! await connect(port4)
        for _ in 0..<400 { if await held.count == 3 { break }; try? await Task.sleep(for: .milliseconds(5)) }
        CT.check("when one has finished its handshake the place is free again", await held.count, 3)
        await c1.close(); await c2b.close(); await c4.close(); l4.stop()

        // Guards the 10 s bound only. The test cannot tell the accept clock from the ready clock: on loopback the two are a few milliseconds apart, so it does not prove the clock starts at accept.
        CT.section("a connection that says nothing is cut within the handshake bound")
        let cut = Slot<Date>()
        let (l3, port3) = await listen { t, slot in
            Task {
                do { _ = try await t.receive() } catch { await cut.set(Date()) }
                slot.finish()
            }
        }
        let quiet = NWConnection(host: "127.0.0.1", port: NWEndpoint.Port(rawValue: port3)!, using: .tcp)
        let began = Date()
        _ = try! await LinkNWTransport.ready(quiet, on: DispatchQueue(label: "test.quiet"))
        for _ in 0..<(LinkListener.handshakeSeconds * 200 + 400) { if await cut.isSet { break }; try? await Task.sleep(for: .milliseconds(5)) }
        let at = await cut.get()
        CT.checkTrue("after \(LinkListener.handshakeSeconds) seconds of silence the listener cancels the connection", at != nil)
        let after = at.map { $0.timeIntervalSince(began) } ?? -1
        CT.checkTrue("and it is cut within about \(LinkListener.handshakeSeconds) seconds of silence (not earlier, not later; the bound only, not the accept-vs-ready clock)", after >= 9.5 && after <= Double(LinkListener.handshakeSeconds) + 1.5)
        quiet.cancel(); l3.stop()
        CT.finish()
    }
}

extension LinkPeer {
    /// The same peer with the time of whatever outcome is compared (the pairing stamps the time it ended).
    func withAt(_ o: LinkPairOutcome?) -> LinkPeer { if case .paired(let p)? = o { return LinkPeer(id: id, name: name, key: key, at: p.at) }; return self }
}
