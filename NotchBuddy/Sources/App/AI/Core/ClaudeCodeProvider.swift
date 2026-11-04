import Foundation

// Claude Code as a provider: one `claude -p` process per turn. This file owns the process; the command line and the
// transcript's meaning are in `ClaudeCodeEngine.swift` and `ClaudeStreamParser.swift`.
//
// Nothing runs on a timer. A turn starts one process and ends when it does; Stop interrupts it, then terminates it,
// then kills it (and whatever it started), so no process outlives the chat. Nothing is logged but event types and
// error kinds (`AILog`): never the arguments, the folder, stdin, stdout, stderr or the environment.

#if !APPSTORE

struct ClaudeProcessTimings: Sendable, Equatable {
    /// Seconds to wait for the run's first event. Claude Code says `system/init` within a second or two.
    var startup: TimeInterval = 30
    /// Stop: seconds after the interrupt before the process is terminated, and after that before it is killed.
    var interruptGrace: TimeInterval = 2
    var terminateGrace: TimeInterval = 2
    /// Seconds a pipe may stay open after the process exited (a grandchild that kept it).
    var drain: TimeInterval = 1

    static let standard = ClaudeProcessTimings()
}

/// Where Claude Code's chat-only runs happen: a folder NotchMeow owns and keeps empty.
enum ClaudeCodeFolders {
    /// `<Application Support>/NotchMeow/claude-chat`
    static func chatFolder() -> String {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchMeow/claude-chat").path
    }

    /// Makes `path` (and what is above it) if it is not there, readable by the user only.
    static func ensure(_ path: String) {
        try? FileManager.default.createDirectory(atPath: path, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
    }
}

struct ClaudeCodeProvider: ModelProvider {
    let id = AIProviderID.claudeCode
    let displayName = "Claude plan"
    let placement = AIPlacement.cloud

    /// The program: found by `ClaudeCodeLocator`, never modified.
    var executable: String
    var turn: ClaudeCodeTurn
    var chatFolder: String = ClaudeCodeFolders.chatFolder()
    /// A recap of the chat so far, for a session started afresh in the middle of it.
    var preamble: String? = nil
    /// The caller's environment, from which the run's is made. Tests pass their own.
    var baseEnvironment: [String: String] = ProcessInfo.processInfo.environment
    var timings: ClaudeProcessTimings = .standard

    func listModels() async throws -> [ModelInfo] {
        ClaudeCodeModel.allCases.map { ModelInfo(id: $0.rawValue, label: "Claude \($0.label)", capabilities: [.vision, .tools]) }
    }

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
        AILog.record(.request(id, model: turn.model.rawValue, placement: placement))
        let provider = self
        return AsyncThrowingStream { continuation in
            let run = ClaudeRun(timings: provider.timings)
            let work = Task.detached { await provider.execute(request, run: run, continuation: continuation) }
            continuation.onTermination = { _ in
                run.stop()
                work.cancel()
            }
        }
    }

    private func execute(_ request: ChatRequest, run: ClaudeRun,
                         continuation: AsyncThrowingStream<ChatChunk, Error>.Continuation) async {
        let started = Date()
        func fail(_ error: AIError) {
            AILog.record(.failure(id, kind: error.kind, status: nil, code: error.code, requestID: nil))
            continuation.finish(throwing: error)
        }
        let cwd = ClaudeCodeCommand.workingDirectory(turn, chatFolder: chatFolder)
        if turn.level.folder == nil { ClaudeCodeFolders.ensure(cwd) }
        var isFolder: ObjCBool = false
        guard FileManager.default.fileExists(atPath: cwd, isDirectory: &isFolder), isFolder.boolValue else {
            return fail(AIError(kind: .badRequest, code: ClaudeCodeError.folderMissing))
        }
        guard let message = request.messages.last(where: { $0.role == .user }) else {
            return fail(AIError(kind: .badRequest))
        }
        let line = ClaudeCodeCommand.userLine(parts: message.parts, preamble: preamble)
        let environment = ClaudeCodeCommand.childEnvironment(from: baseEnvironment, platform: turn.platform, executable: executable)
        let output: AsyncStream<Data>
        do {
            output = try run.launch(executable: executable, arguments: ClaudeCodeCommand.arguments(turn),
                                    environment: environment, directory: cwd, stdin: line)
        } catch {
            return fail(AIError(kind: .unreachable, code: ClaudeCodeError.missing))
        }
        // The run must say something soon. After that it may take as long as it needs: a build can run for minutes.
        let watchdog = Task {
            try? await Task.sleep(nanoseconds: UInt64(timings.startup * 1_000_000_000))
            if !Task.isCancelled, !run.sawOutput { run.timedOut() }
        }
        defer { watchdog.cancel() }

        var parser = ClaudeStreamParser(initTools: ClaudeCodeCommand.initTools(turn.level))
        var splitter = SSELineSplitter()
        func feed(_ line: String) {
            let chunks = parser.consume(line: line)
            // A level that refuses tools stops the process at the first line that shows one: nothing more is read, and
            // nothing of that line reaches the chat (its engine report would confirm a session killed right after init).
            if parser.refusedTools { return run.stop() }
            for chunk in chunks { continuation.yield(chunk) }
        }
        for await data in output {
            run.markOutput()
            for byte in data {
                if let complete = splitter.push(byte) { feed(complete) }
            }
        }
        if let last = splitter.flush() { feed(last) }
        await run.waitForExit()
        // Our own stop for a refused tool is a failure, not a Stop: it is checked before the Stop early return.
        if parser.refusedTools, let error = parser.failure(stderr: run.stderrText) { return fail(error) }
        // Stop is not a failure of the run: the consumer has already gone.
        if run.wasStopped, !run.didTimeOut { return continuation.finish() }
        if run.didTimeOut { return fail(AIError(kind: .timeout)) }
        if let error = parser.failure(stderr: run.stderrText) { return fail(error) }
        AILog.record(.reply(id, ms: Int(Date().timeIntervalSince(started) * 1000), finish: .stop))
        continuation.finish()
    }
}

/// A run the registry can stop at quit.
protocol ClaudeLiveRun: AnyObject, Sendable {
    var isRunning: Bool { get }
    /// Marks the run stopped, sends SIGINT, and returns its pid followed by everything it had started.
    func interruptForQuit() -> [Int32]
}

/// Every `claude` process that is running, so that quitting the app can end them (and what they started) without
/// the stream machinery or a runloop turn. A run is in it from its launch until it exits.
final class ClaudeRunRegistry: @unchecked Sendable {
    private static let shared = ClaudeRunRegistry()
    private let lock = NSLock()
    private var runs: [ObjectIdentifier: ClaudeLiveRun] = [:]

    static var liveCount: Int { shared.lock.withLock { shared.runs.count } }
    static func register(_ run: ClaudeLiveRun) { shared.lock.withLock { shared.runs[ObjectIdentifier(run)] = run } }
    static func unregister(_ run: ClaudeLiveRun) { _ = shared.lock.withLock { shared.runs.removeValue(forKey: ObjectIdentifier(run)) } }

    /// Synchronous, for app quit: interrupt every live run, wait at most `wait` seconds in all for them to exit,
    /// then SIGKILL what is left and everything they had started.
    static func stopAll(wait: TimeInterval = 1) {
        let live = shared.lock.withLock { Array(shared.runs.values) }
        guard !live.isEmpty else { return }
        let families = live.map { ($0, $0.interruptForQuit()) }
        let deadline = Date().addingTimeInterval(wait)
        while Date() < deadline, live.contains(where: \.isRunning) { usleep(20_000) }
        for (run, pids) in families {
            // pids[0] is the process: only while it has not been reaped (its number could be someone else's by now).
            for (index, pid) in pids.enumerated() where (index > 0 || run.isRunning) && kill(pid, 0) == 0 { kill(pid, SIGKILL) }
        }
    }
}

/// Opens once; whoever waits before that is resumed when it does, whoever waits after it does not wait.
private final class Latch: @unchecked Sendable {
    private let lock = NSLock()
    private var isOpen = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    func open() {
        let pending = lock.withLock { () -> [CheckedContinuation<Void, Never>] in
            isOpen = true
            defer { waiters = [] }
            return waiters
        }
        pending.forEach { $0.resume() }
    }

    func wait() async {
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            let ready = lock.withLock { () -> Bool in
                if isOpen { return true }
                waiters.append(done)
                return false
            }
            if ready { done.resume() }
        }
    }
}

/// One process. Everything that touches it is behind the lock.
/// Also runs `codex` (CodexProvider).
final class ClaudeRun: ClaudeLiveRun, @unchecked Sendable {
    private let process = Process()
    private let timings: ClaudeProcessTimings
    private let lock = NSLock()
    private var launched = false
    private var exited = false
    private var exitCode: Int32?
    private var stopRequested = false
    private var timedOutFlag = false
    private var outputSeen = false
    private var errorBytes = Data()
    /// Open when the process has exited / when stderr has ended (or `drain` seconds after the process exited).
    private let exitLatch = Latch(), errorLatch = Latch()

    private static let errorLimit = 65_536
    private static let ignoreSIGPIPE: Void = { signal(SIGPIPE, SIG_IGN) }()

    init(timings: ClaudeProcessTimings) { self.timings = timings }

    var sawOutput: Bool { lock.withLock { outputSeen } }
    var wasStopped: Bool { lock.withLock { stopRequested } }
    var didTimeOut: Bool { lock.withLock { timedOutFlag } }
    func markOutput() { lock.withLock { outputSeen = true } }
    var stderrText: String { lock.withLock { String(decoding: errorBytes, as: UTF8.self) } }
    /// The exit status; nil while it runs, or when a signal ended it.
    var exitStatus: Int32? { lock.withLock { exitCode } }

    /// Starts the process, writes `stdin` to it and closes it, and returns what it prints, in pieces. The stream
    /// ends when stdout does (or `drain` seconds after the process exited). If Stop came first nothing is started
    /// and the stream is empty.
    func launch(executable: String, arguments: [String], environment: [String: String], directory: String,
                stdin line: Data) throws -> AsyncStream<Data> {
        _ = Self.ignoreSIGPIPE
        let input = Pipe(), output = Pipe(), errors = Pipe()
        process.executableURL = URL(fileURLWithPath: executable)
        process.arguments = arguments
        process.environment = environment
        process.currentDirectoryURL = URL(fileURLWithPath: directory, isDirectory: true)
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors

        let (stream, continuation) = AsyncStream<Data>.makeStream()
        let drain = timings.drain
        let errorLatch = errorLatch
        output.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                continuation.finish()
            } else {
                continuation.yield(data)
            }
        }
        errors.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                errorLatch.open()
                return
            }
            guard let self else { return }
            self.lock.withLock { if self.errorBytes.count < Self.errorLimit { self.errorBytes.append(data) } }
        }
        process.terminationHandler = { [weak self] finished in
            // A grandchild may still hold the pipes: give the last bytes a moment, then let go.
            DispatchQueue.global().asyncAfter(deadline: .now() + drain) {
                output.fileHandleForReading.readabilityHandler = nil
                errors.fileHandleForReading.readabilityHandler = nil
                continuation.finish()
                errorLatch.open()
            }
            guard let self else { return }
            self.lock.withLock {
                self.exited = true
                self.exitCode = finished.terminationReason == .exit ? finished.terminationStatus : nil
            }
            ClaudeRunRegistry.unregister(self)
            self.exitLatch.open()
        }
        // Under the lock, so that a Stop never falls between "started" and "can be stopped".
        let startedNow = try lock.withLock { () -> Bool in
            if stopRequested { return false }
            try process.run()
            launched = true
            ClaudeRunRegistry.register(self)
            return true
        }
        guard startedNow else {
            continuation.finish()
            exitLatch.open()
            errorLatch.open()
            return stream
        }
        // Written on its own thread: a large PDF must not wait for the pipe while the reply is being read.
        DispatchQueue.global().async {
            try? input.fileHandleForWriting.write(contentsOf: line)
            try? input.fileHandleForWriting.close()
        }
        return stream
    }

    func waitForExit() async {
        await exitLatch.wait()
        await errorLatch.wait()
    }

    private var running: Bool { lock.withLock { launched && !exited } }
    var isRunning: Bool { running }

    /// Quit: the same as Stop's first step, but also for a run Stop has already begun to end, and it returns the
    /// pid and everything the process had started so that the caller can kill them.
    func interruptForQuit() -> [Int32] {
        let pid: Int32? = lock.withLock {
            guard launched, !exited else { return nil }
            stopRequested = true
            return process.processIdentifier
        }
        guard let pid else { return [] }
        let family = Self.descendants(of: pid)
        kill(pid, SIGINT)
        return [pid] + family
    }

    /// No first event in time: the same as Stop, but the failure is a timeout.
    func timedOut() {
        lock.withLock { timedOutFlag = true }
        stop()
    }

    /// Stop. Interrupt first (Claude Code ends the tool it is running), then terminate, then kill the process and
    /// everything it had started when Stop was pressed. Safe to call twice, or after the process ended.
    func stop() {
        let pid: Int32? = lock.withLock {
            guard !exited, !stopRequested else { return nil }
            stopRequested = true
            return launched ? process.processIdentifier : nil
        }
        guard let pid else { return }
        let family = Self.descendants(of: pid)
        kill(pid, SIGINT)
        let timings = timings
        Task.detached { [self] in
            try? await Task.sleep(nanoseconds: UInt64(timings.interruptGrace * 1_000_000_000))
            if running { kill(pid, SIGTERM) }
            try? await Task.sleep(nanoseconds: UInt64(timings.terminateGrace * 1_000_000_000))
            if running { kill(pid, SIGKILL) }
            for child in family where kill(child, 0) == 0 { kill(child, SIGKILL) }
        }
    }

    /// Children, grandchildren and so on. `pgrep -P` lists the children of one process.
    static func descendants(of pid: Int32) -> [Int32] {
        var found: [Int32] = []
        var queue = [pid]
        while let next = queue.popLast() {
            let ask = Process()
            ask.executableURL = URL(fileURLWithPath: "/usr/bin/pgrep")
            ask.arguments = ["-P", String(next)]
            let out = Pipe()
            ask.standardOutput = out
            ask.standardError = FileHandle.nullDevice
            guard (try? ask.run()) != nil else { continue }
            let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
            ask.waitUntilExit()
            let children = text.split(whereSeparator: \.isNewline).compactMap { Int32($0) }
            found += children
            queue += children
        }
        return found
    }
}

#endif
