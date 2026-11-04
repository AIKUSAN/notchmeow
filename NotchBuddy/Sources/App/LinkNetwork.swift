@preconcurrency import Network
import Foundation

// The link on the network (sub-project G2): a transport over a TCP connection (`Network.framework`), the listener that advertises `_notchmeow._tcp`, and the browser that finds the other machines.
// Everything here is event-driven: the listener and the browser are callbacks on a private queue, the connection reads wait on the socket, and **nothing polls**. There is no listener and no
// advert until `LinkService` is told the Mac is visible on the network (Settings → Devices, off by default), and the browser runs only while Send or Devices is open.
//
// Hardening that the contract does not need but a listener on a LAN does: a connection that has not finished its first record and its handshake in 10 seconds is cancelled, and no more than 8
// connections wait at once for that (`LinkListener.maxPending`), 2 of them from one address (`maxPendingPerSource`; the address is a key in memory, never logged); records are cut by `LinkWire.splitRecords` (a length of 0 closes, a record is at most 65535 bytes, so the buffer stays small).

/// A TCP connection as a `LinkTransport`: the bytes of the stream are cut into whole records on the way in and given a length on the way out (`LinkWire`).
actor LinkNWTransport: LinkTransport {
    private let connection: NWConnection
    private var buffer = Data()
    private var queue: [Data] = []
    private var closed = false
    /// Set by `abort()`, which may come from any thread: a connection that was cut has nothing to flush, so `close()` has nothing to wait for.
    private let aborted = Once()

    init(_ connection: NWConnection) { self.connection = connection }

    /// Starts an accepted or new connection and waits until it is ready (or has failed). `timeout` bounds the wait.
    static func ready(_ connection: NWConnection, on queue: DispatchQueue, timeout: Duration = .seconds(10)) async throws -> LinkNWTransport {
        try await withThrowingTaskGroup(of: Void.self) { group in
            group.addTask {
                try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
                    let once = Once()
                    connection.stateUpdateHandler = { state in
                        switch state {
                        case .ready: if once.take() { c.resume() }
                        case .failed(let e): if once.take() { c.resume(throwing: LinkSessionError.io("\(e)")) }
                        case .cancelled: if once.take() { c.resume(throwing: LinkSessionError.closed) }
                        case .waiting(let e): if once.take() { c.resume(throwing: LinkSessionError.io("waiting: \(e)")) }   // no route, no permission: fail at once, do not wait for ever
                        default: break
                        }
                    }
                    connection.start(queue: queue)
                }
            }
            group.addTask { try await Task.sleep(for: timeout); throw LinkSessionError.io("connect timeout") }
            defer { group.cancelAll() }
            do { try await group.next() } catch { connection.cancel(); throw error }
            connection.stateUpdateHandler = nil
            return LinkNWTransport(connection)
        }
    }

    func send(_ record: Data) async throws {
        guard !closed else { throw LinkSessionError.closed }
        let framed: Data
        do { framed = try LinkWire.encodeRecord(record) } catch { throw LinkSessionError.violation("record length") }
        try await withCheckedThrowingContinuation { (c: CheckedContinuation<Void, Error>) in
            connection.send(content: framed, completion: .contentProcessed { error in
                if let error { c.resume(throwing: LinkSessionError.io("\(error)")) } else { c.resume() }
            })
        }
    }

    /// Assumes one reader per transport: `buffer`, `queue` and `closed` are not guarded against two `receive()` calls pending at once (the actor is suspended during the read).
    func receive() async throws -> Data {
        while true {
            if !queue.isEmpty { return queue.removeFirst() }
            if closed { throw LinkSessionError.closed }
            let chunk: Data? = await withCheckedContinuation { (c: CheckedContinuation<Data?, Never>) in
                connection.receive(minimumIncompleteLength: 1, maximumLength: 65_537) { data, _, isComplete, error in
                    if let data, !data.isEmpty { c.resume(returning: data) } else { c.resume(returning: nil); _ = (isComplete, error) }
                }
            }
            guard let chunk else { closed = true; throw LinkSessionError.closed }
            buffer.append(chunk)
            do {
                let (records, rest) = try LinkWire.splitRecords(buffer)
                buffer = rest
                queue.append(contentsOf: records)
            } catch { closed = true; connection.cancel(); throw LinkSessionError.violation("record") }   // a record of length 0
        }
    }

    /// Sends what is queued, tells the other side the stream is finished, and cancels once that went out.
    func close() async {
        guard !closed, !aborted.isSet else { return }   // a cut connection: a final message on it may never be reported as processed, and a close that waited for that would hold its claim for ever
        closed = true
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            connection.send(content: nil, contentContext: .finalMessage, isComplete: true, completion: .contentProcessed { _ in c.resume() })
        }
        connection.cancel()
    }

    /// The other end's address, for the log-free "who is this" of a connection (never logged, never shown).
    nonisolated var endpoint: NWEndpoint { connection.endpoint }

    /// Hard stop: for a connection that is too slow. The pending reads then fail and the conversation ends.
    nonisolated func abort() { _ = aborted.take(); connection.cancel() }

    private final class Once: @unchecked Sendable {
        private let lock = NSLock(); private var taken = false
        func take() -> Bool { lock.withLock { if taken { return false }; taken = true; return true } }
        var isSet: Bool { lock.withLock { taken } }
    }
}

/// A connection that has been accepted but has not finished its handshake. The service calls `finish()` when it has (or when it refuses the connection); until then a watchdog cuts the connection
/// `LinkListener.handshakeSeconds` after it was accepted, and the slot counts against `LinkListener.maxPending`.
final class LinkPendingSlot: @unchecked Sendable {
    private let lock = NSLock()
    private var done = false
    private var release: (@Sendable () -> Void)?
    private var watchdog: Task<Void, Never>?

    fileprivate init(release: @escaping @Sendable () -> Void) { self.release = release }
    fileprivate func arm(_ task: Task<Void, Never>) { lock.withLock { if done { task.cancel() } else { watchdog = task } } }
    var isFinished: Bool { lock.withLock { done } }

    func finish() {
        let (r, w): ((@Sendable () -> Void)?, Task<Void, Never>?) = lock.withLock {
            if done { return (nil, nil) }
            done = true
            defer { release = nil; watchdog = nil }
            return (release, watchdog)
        }
        w?.cancel()
        r?()
    }
}

/// The listener: accepts connections, advertises the machine, and hands each new connection to the service. It exists only while the machine is visible on the network.
final class LinkListener: @unchecked Sendable {
    static let serviceType = "_notchmeow._tcp"
    static let maxPending = 8
    static let maxPendingPerSource = 2
    static let handshakeSeconds = 10

    private let queue = DispatchQueue(label: "notchmeow.link.listener")
    private var listener: NWListener?
    private let lock = NSLock()
    private var pending = 0
    private var pendingBySource: [String: Int] = [:]   // guarded by `lock`
    private let onConnection: @Sendable (LinkNWTransport, LinkPendingSlot) -> Void
    private let onState: @Sendable (_ port: UInt16?, _ failed: Bool) -> Void

    /// `onConnection` gets a connection that is ready, with its pending slot. `onState` says when the listener is ready (with its port) or has failed.
    init(onConnection: @escaping @Sendable (LinkNWTransport, LinkPendingSlot) -> Void, onState: @escaping @Sendable (_ port: UInt16?, _ failed: Bool) -> Void) {
        self.onConnection = onConnection
        self.onState = onState
    }

    /// Starts listening. With `advert` the machine is announced as `_notchmeow._tcp` (a TXT record with `v`, `id` and `name`, nothing else); without it (the tests and the loopback of the Debug fake
    /// peer) only the port exists. `port` 0 lets the system choose.
    func start(advert: (id: String, name: String)?, port: UInt16 = 0, loopbackOnly: Bool = false) throws {
        guard lock.withLock({ listener == nil }) else { return }   // a second start changes nothing: one listener, never an orphan
        let params = NWParameters.tcp
        params.includePeerToPeer = false
        if loopbackOnly { params.requiredInterfaceType = .loopback }
        let l = try NWListener(using: params, on: port == 0 ? .any : NWEndpoint.Port(rawValue: port)!)
        if let advert {
            l.service = NWListener.Service(name: String(advert.id.prefix(12)), type: Self.serviceType, domain: nil, txtRecord: NWTXTRecord(["v": String(LinkWire.protocolVersion), "id": advert.id, "name": advert.name]))
        }
        l.stateUpdateHandler = { [weak self] state in
            guard let self else { return }
            switch state {
            case .ready: self.onState(l.port?.rawValue, false)
            case .waiting: self.onState(nil, true)   // NWListener can recover from waiting to ready by itself: the listener stays, and .ready reports its port again through onState
            case .failed: self.drop(l); self.onState(nil, true)   // a dead listener is not kept, and is already gone when the report is made: the service starts a new one after a wait (LinkRestart.swift)
            default: break
            }
        }
        l.newConnectionHandler = { [weak self] conn in self?.accept(conn) }
        let installed: Bool = lock.withLock { if listener != nil { return false }; listener = l; return true }
        guard installed else { l.cancel(); return }   // a start that raced another one leaves no second listener
        l.start(queue: queue)
    }

    func stop() {
        let l: NWListener? = lock.withLock { let x = listener; listener = nil; return x }
        l?.cancel()
    }

    /// True while a socket is held: false before the first start, after `stop()` and after a failure dropped it.
    var isRunning: Bool { lock.withLock { listener != nil } }

    /// Cancels `l` and clears it, if it is still the listener (a stop or a new start may have replaced it already).
    private func drop(_ l: NWListener) {
        lock.withLock { if listener === l { listener = nil } }
        l.cancel()
    }

    /// Where a connection comes from, as a key for the per-address cap: the host without its interface scope. Never logged, never shown.
    static func sourceKey(_ endpoint: NWEndpoint) -> String {
        guard case .hostPort(let host, _) = endpoint else { return "\(endpoint)" }
        return String("\(host)".split(separator: "%", maxSplits: 1).first ?? "")
    }

    private func accept(_ conn: NWConnection) {
        let source = Self.sourceKey(conn.endpoint)
        let admitted: Bool = lock.withLock {
            if pending >= Self.maxPending || pendingBySource[source, default: 0] >= Self.maxPendingPerSource { return false }
            pending += 1
            pendingBySource[source, default: 0] += 1
            return true
        }
        guard admitted else { conn.cancel(); return }
        let slot = LinkPendingSlot { [weak self] in
            guard let self else { return }
            self.lock.withLock {
                self.pending -= 1
                let left = self.pendingBySource[source, default: 0] - 1
                self.pendingBySource[source] = left > 0 ? left : nil
            }
        }
        // The handshake clock starts at accept: the watchdog is armed before the connection is ready, and cuts it if the service has not finished the handshake in time.
        slot.arm(Task { try? await Task.sleep(for: .seconds(Self.handshakeSeconds)); if !Task.isCancelled && !slot.isFinished { conn.cancel(); slot.finish() } })
        let q = queue, handler = onConnection
        Task {
            do {
                let transport = try await LinkNWTransport.ready(conn, on: q, timeout: .seconds(Self.handshakeSeconds))
                handler(transport, slot)
            } catch { conn.cancel(); slot.finish() }
        }
    }
}

/// The browser: finds the other machines' adverts. It runs only while Send or Devices is open (`LinkService` counts the openers).
final class LinkBrowser: @unchecked Sendable {
    struct Found: Sendable { let advert: LinkWire.Advert; let endpoint: NWEndpoint }

    private let queue = DispatchQueue(label: "notchmeow.link.browser")
    private let lock = NSLock()
    private var browser: NWBrowser?   // guarded by `lock`
    private let ownId: String
    private let onResults: @Sendable ([Found]) -> Void
    private let onFailed: @Sendable () -> Void

    /// `onFailed` is called when the browser failed on its own (not when `stop()` ended it): the list is stale and `start()` browses again.
    init(ownId: String, onResults: @escaping @Sendable ([Found]) -> Void, onFailed: @escaping @Sendable () -> Void) {
        self.ownId = ownId
        self.onResults = onResults
        self.onFailed = onFailed
    }

    func start() {
        lock.withLock {
            guard browser == nil else { return }
            let b = NWBrowser(for: .bonjourWithTXTRecord(type: LinkListener.serviceType, domain: nil), using: .tcp)
            b.browseResultsChangedHandler = { [ownId, onResults] results, _ in
                var found: [Found] = []
                for r in results {
                    guard case .bonjour(let txt) = r.metadata else { continue }
                    let dict = txt.dictionary
                    // An advert that does not pass the contract's checks (version, id, name, this machine's own id) is not listed.
                    if let ad = try? LinkWire.parseTxt(dict, ownId: .value(ownId)) { found.append(Found(advert: ad, endpoint: r.endpoint)) }
                }
                onResults(found)
            }
            // A failed browser is cancelled and cleared, so the next start() browses again, and the service is told (unless `stop()` ended it first) so that it starts it again after a wait.
            b.stateUpdateHandler = { [weak self, weak b] state in
                guard case .failed = state, let b else { return }
                b.cancel()
                if self?.clearIfCurrent(b) == true { self?.onFailed() }
            }
            browser = b
            b.start(queue: queue)
        }
    }

    func stop() {
        let b: NWBrowser? = lock.withLock { let x = browser; browser = nil; return x }
        b?.cancel()
    }

    /// Clears `b` if it is still the browser; true when it was (a `stop()` may have taken it already).
    private func clearIfCurrent(_ b: NWBrowser) -> Bool {
        lock.withLock { if browser === b { browser = nil; return true }; return false }
    }
}
