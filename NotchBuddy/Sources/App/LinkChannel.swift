import Foundation

// The link's connection layer (sub-project G2): a transport that carries whole records, and the channel that puts Noise transport messages and frames on it. Foundation only, so the session
// tests can run it between two in-memory ends. The real transport (Network.framework, LinkNetwork.swift) cuts a TCP stream into records with `LinkWire.splitRecords`; this file does not know
// sockets.

/// Carries whole records (one record is one Noise message, or the preamble): `send` takes a record's bytes, 1 to 65535 of them, and `receive` gives the bytes of the next whole record, without the
/// length prefix that the wire puts in front (`LinkWire.encodeRecord`, which the real transport applies). Every call may suspend; `receive` throws when the other end has closed.
protocol LinkTransport: Sendable {
    func send(_ record: Data) async throws
    func receive() async throws -> Data
    /// Flushes what was sent and closes. Calling it twice is harmless.
    func close() async
    /// Hard stop, from any task: nothing is flushed, and a send or a read that is pending fails at once. For a peer that stopped reading (a `close` would wait behind its stalled bytes). The default does
    /// nothing, so a stand-in that cannot stall need not have one.
    func abort()
}

extension LinkTransport {
    func abort() {}
}

enum LinkSessionError: Error, Equatable, Sendable {
    case closed
    case violation(String)   // the other side broke the protocol, or a message did not open
    case io(String)
}

/// Frames over an established Noise session. One sender at a time: a frame is encrypted and handed to the transport under a lock that is released in call order, so the nonces go out in the
/// order they were taken (a second sender that arrives while the first is waiting for the transport waits its turn).
actor LinkChannel {
    private let transport: any LinkTransport
    private var sendState: LinkCipherState
    private var receiveState: LinkCipherState
    private var busy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    init(transport: any LinkTransport, send: LinkCipherState, receive: LinkCipherState) {
        self.transport = transport
        self.sendState = send
        self.receiveState = receive
    }

    private func lock() async {
        if busy { await withCheckedContinuation { waiters.append($0) } } else { busy = true }
    }
    private func unlock() {
        if waiters.isEmpty { busy = false } else { waiters.removeFirst().resume() }
    }

    func sendFrame(_ frame: LinkWire.Frame) async throws {
        await lock()
        defer { unlock() }
        do {
            let sealed = try sendState.encrypt(ad: Data(), try LinkWire.encode(frame))
            try await transport.send(sealed)
        } catch let e as LinkSessionError { throw e }
        catch let e as LinkNoiseError { throw LinkSessionError.violation("noise \(e)") }
        catch let e as LinkFrameError { throw LinkSessionError.violation("frame \(e.rawValue)") }
        catch { throw LinkSessionError.io("\(error)") }
    }

    /// The next frame. A message that does not open, a frame that does not decode and a closed transport all end the conversation with an error.
    func receiveFrame() async throws -> LinkWire.Frame {
        let record: Data
        do { record = try await transport.receive() } catch let e as LinkSessionError { throw e } catch { throw LinkSessionError.io("\(error)") }
        do { return try LinkWire.decode(try receiveState.decrypt(ad: Data(), record)) }
        catch let e as LinkNoiseError { throw LinkSessionError.violation("noise \(e)") }
        catch let e as LinkFrameError { throw LinkSessionError.violation("frame \(e.rawValue)") }
    }

    /// Sends one frame and waits for it no longer than `graceMs`: the connection may be stuck behind bytes the peer does not read, and a conversation that waited for ever would hold everything it
    /// holds (a place among the connections, the transfer place). After the grace the transport is cut, which fails the stuck send and every read, and the conversation ends. A failed send is not
    /// reported: the conversation learns of a dead connection from its reader.
    func sendBestEffort(_ frame: LinkWire.Frame, graceMs: Int) async {
        let cut = LinkIdleWatch(ms: graceMs) { [transport] in transport.abort() }
        try? await sendFrame(frame)
        cut.stop()
    }

    func close() async { await transport.close() }
}

/// How many frames a reader may have handed on and not yet seen taken. The reader asks for a place (`take`) before it reads the next frame, and the conversation gives it back (`give`) when it takes
/// the frame from its queue, so a peer that sends faster than the conversation works leaves its bytes in the socket (where TCP slows it down), not in memory.
final class LinkFrameWindow: @unchecked Sendable {
    static let frames = 4
    private let lock = NSLock()
    private var free: Int
    private var waiter: CheckedContinuation<Void, Never>?
    private var closed = false

    init(_ frames: Int = LinkFrameWindow.frames) { free = frames }

    func take() async {
        await withCheckedContinuation { (c: CheckedContinuation<Void, Never>) in
            let go: Bool = lock.withLock {
                if closed { return true }
                if free > 0 { free -= 1; return true }
                waiter = c
                return false
            }
            if go { c.resume() }
        }
    }

    func give() {
        let w: CheckedContinuation<Void, Never>? = lock.withLock {
            if let w = waiter { waiter = nil; return w }
            free += 1
            return nil
        }
        w?.resume()
    }

    /// The conversation is over: a reader that is waiting for a place is let go (it then meets the closed transport).
    func close() {
        let w: CheckedContinuation<Void, Never>? = lock.withLock { closed = true; let x = waiter; waiter = nil; return x }
        w?.resume()
    }
}

/// A one-shot deadline that activity pushes back: it fires `fire` once, `ms` milliseconds after the last `touch` (or after it was made), and then it is over. It never polls: it sleeps for the time
/// that is left, wakes once, and either fires or sleeps for what is left again. Made when something is pending, stopped when it is not (`stop`), so nothing sleeps for a conversation that ended.
final class LinkIdleWatch: @unchecked Sendable {
    private let lock = NSLock()
    private var last = ContinuousClock.now
    private var over = false
    private var task: Task<Void, Never>?

    init(ms: Int, fire: @escaping @Sendable () -> Void) {
        let limit = Duration.milliseconds(ms)
        let t = Task { [weak self] in
            while true {
                guard let left = self?.left(limit) else { return }
                if left <= .zero { if self?.finish() == true { fire() }; return }
                try? await Task.sleep(for: left)
                if Task.isCancelled { return }
            }
        }
        lock.withLock { if over { t.cancel() } else { task = t } }
    }

    private func left(_ limit: Duration) -> Duration? { lock.withLock { over ? nil : limit - (ContinuousClock.now - last) } }
    private func finish() -> Bool { lock.withLock { if over { return false }; over = true; return true } }

    /// Something happened: the deadline moves.
    func touch() { lock.withLock { last = .now } }

    func stop() {
        let t: Task<Void, Never>? = lock.withLock { over = true; let x = task; task = nil; return x }
        t?.cancel()
    }
}

/// Handshake messages over a transport, one record each. `Data` that comes back from `receive` is re-based at 0.
enum LinkHandshakeIO {
    static func send(_ transport: any LinkTransport, _ message: Data) async throws {
        try await transport.send(message)
    }
    static func receive(_ transport: any LinkTransport) async throws -> Data { Data(try await transport.receive()) }
}

/// Two ends of an in-memory connection, for the tests and for the Debug fake peer's loopback (no sockets, no network). Records come out in the order they went in; after `close` the other end
/// reads what was already sent and then sees the end.
actor LinkMemoryEnd: LinkTransport {
    private var queue: [Data] = []
    private var waiter: CheckedContinuation<Data?, Never>?
    private var peer: LinkMemoryEnd?
    private var closed = false      // this end closed
    private var ended = false       // nothing more will arrive

    static func pair() async -> (LinkMemoryEnd, LinkMemoryEnd) {
        let a = LinkMemoryEnd(), b = LinkMemoryEnd()
        await a.link(to: b)
        await b.link(to: a)
        return (a, b)
    }

    private func link(to other: LinkMemoryEnd) { peer = other }

    private func deliver(_ record: Data) {
        if let w = waiter { waiter = nil; w.resume(returning: record) } else { queue.append(record) }
    }

    private func peerClosed() {
        ended = true
        if let w = waiter { waiter = nil; w.resume(returning: nil) }
    }

    func send(_ record: Data) async throws {
        guard (1...LinkWire.noiseMax).contains(record.count) else { throw LinkSessionError.violation("record length") }   // what the real transport's length prefix would refuse
        guard !closed, !ended, let peer else { throw LinkSessionError.closed }
        await peer.deliver(Data(record))
    }

    func receive() async throws -> Data {
        if !queue.isEmpty { return queue.removeFirst() }
        if ended { throw LinkSessionError.closed }
        guard let record = await withCheckedContinuation({ (c: CheckedContinuation<Data?, Never>) in waiter = c }) else { throw LinkSessionError.closed }
        return record
    }

    func close() async {
        guard !closed else { return }
        closed = true
        ended = true
        if let w = waiter { waiter = nil; w.resume(returning: nil) }
        await peer?.peerClosed()
    }

    nonisolated func abort() { Task { await self.close() } }
}
