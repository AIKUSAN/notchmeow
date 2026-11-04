import Foundation

// Codex (OpenAI's `codex` command line, run on the user's own plan) as a provider: one `codex exec` process per turn,
// at Chat only, and at no tools for the quick actions. The process itself is `ClaudeRun`, the same owner Claude Code
// uses, so Stop, quit and the startup watchdog behave alike. The command line, the environment, the prompt and the
// folders are `CodexEngine.swift`; what the output means is `CodexStreamParser.swift`.
//
// Nothing is shown while the process runs: the text is yielded once, after the run has ended and its turn completed.
// Nothing is logged but event kinds (`AILog`); the prompt goes only to the child's stdin.

#if !APPSTORE

/// What one chat turn needs to run Codex: the program, the level, and the model (nil or "" is Codex's own default).
struct CodexSetup: Sendable, Equatable {
    var executable: String
    var level: CodexLevel
    var model: String?
    /// What the last status check found, read when the turn starts: a known too-old or signed-out Codex fails before it is started.
    var knownState: CodexStatus.State = .unknown
}

/// Splits a Codex run's stdout into lines, and says at once when a line is longer than `limit` bytes. Checking while
/// the bytes arrive means a process that never ends a line cannot make NotchMeow buffer without bound.
struct CodexLineReader: Sendable {
    static let limit = 1_048_576

    enum Step: Equatable {
        case pending
        case line(String)
        case tooLong
    }

    private var buffer: [UInt8] = []

    /// A line ends at LF; one CR before it is dropped (CRLF), as `SSELineSplitter` does.
    mutating func push(_ byte: UInt8) -> Step {
        guard byte == 0x0A else {
            guard buffer.count < Self.limit else { return .tooLong }
            buffer.append(byte)
            return .pending
        }
        return .line(take())
    }

    /// The last line, when the stream ends without a final LF.
    mutating func flush() -> String? { buffer.isEmpty ? nil : take() }

    private mutating func take() -> String {
        if buffer.last == 0x0D { buffer.removeLast() }
        defer { buffer.removeAll(keepingCapacity: true) }
        return String(decoding: buffer, as: UTF8.self)
    }
}

/// The image folder's sweep, once per process: the first Codex turn of the process removes the turn folders a Quit or a
/// crash left behind. A turn that comes while the sweep runs waits for it, so the sweep never runs beside a live run's
/// own writes. No timer and no watcher: it runs only when a turn is about to write.
final class CodexImageSweeper: @unchecked Sendable {
    static let shared = CodexImageSweeper()
    private let lock = NSLock()
    private var swept = false

    func sweepOnce(root: String) {
        lock.withLock {
            guard !swept else { return }
            CodexFolders.sweepStale(under: root)
            swept = true
        }
    }
}

struct CodexProvider: ModelProvider {
    let id = AIProviderID.codexPlan
    let displayName = "OpenAI plan"
    let placement = AIPlacement.cloud

    /// The program: found by `CodexLocator`, never modified.
    var executable: String
    var level: CodexLevel
    /// nil or "": no `--model`, Codex's own default.
    var model: String? = nil
    /// The last status check's state (`CodexSetup.knownState`).
    var knownState: CodexStatus.State = .unknown
    var chatFolder: String = CodexFolders.chatFolder()
    var imageFolder: String = CodexFolders.imageFolder()
    /// The once-per-process sweep of `imageFolder` (`CodexImageSweeper.shared` in production; a test passes its own).
    var imageSweeper: CodexImageSweeper = .shared
    /// The caller's environment, from which the run's is made. Tests pass their own.
    var baseEnvironment: [String: String] = ProcessInfo.processInfo.environment
    var timings: ClaudeProcessTimings = .standard

    /// How one run ended. The stream is finished only after this is known, and after the pictures are gone.
    private enum Ending {
        case finished(String)
        case stopped
        case failed(AIError)
    }

    func listModels() async throws -> [ModelInfo] {
        [ModelInfo(id: "", label: "OpenAI's default model")]
    }

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
        AILog.record(.request(id, model: model ?? "", placement: placement))
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

    private var nonEmptyModel: String? { (model ?? "").isEmpty ? nil : model }

    private func arguments(images: [String]) -> CodexCommand.Built {
        CodexCommand.arguments(level: level.key, model: nonEmptyModel, images: images)
    }

    /// The error for a code, with the kind copy.json gives it.
    private static func failure(_ code: String) -> AIError {
        AIError(kind: CodexError.kind(of: code), code: code)
    }

    private func execute(_ request: ChatRequest, run: ClaudeRun,
                         continuation: AsyncThrowingStream<ChatChunk, Error>.Continuation) async {
        let started = Date()
        func fail(_ error: AIError) {
            AILog.record(.failure(id, kind: error.kind, status: nil, code: error.code, requestID: nil))
            continuation.finish(throwing: error)
        }
        // 0. What the last status check found: a Codex known to be too old or signed out is not started, and nothing is
        // written. A program not found, or an unknown state, is still tried: the launch itself reports a missing program (R9).
        switch knownState {
        case .tooOld: return fail(Self.failure(CodexError.tooOld))
        case .signedOut: return fail(Self.failure(CodexError.signedOut))
        case .notInstalled, .unknown, .signedIn: break
        }
        // 1. The model and the level, refused before anything is written.
        if case .refused(let code) = arguments(images: []) { return fail(Self.failure(code)) }
        // 2. The chat folder, made if missing and kept read-only.
        guard CodexFolders.prepareChatFolder(chatFolder) else { return fail(Self.failure(CodexError.crashed)) }
        // 3. The prompt, and the pictures in this turn's own folder: runTurn writes them and removes them, whatever happens.
        let prompt = CodexPrompt.build(request)
        let turnID = UUID().uuidString.lowercased()
        switch await runTurn(prompt, turnID: turnID, run: run) {
        case .failed(let error):
            fail(error)
        case .stopped:
            continuation.finish()
        case .finished(let text):
            if !text.isEmpty { continuation.yield(.text(text)) }
            continuation.yield(.finish(.stop))
            AILog.record(.reply(id, ms: Int(Date().timeIntervalSince(started) * 1000), finish: .stop))
            continuation.finish()
        }
    }

    /// One run from writing the pictures to the process's exit. The turn's pictures are removed when this returns,
    /// however the run ended, so nothing is left on disk by the time the caller finishes the stream.
    private func runTurn(_ prompt: CodexPrompt.Built, turnID: String, run: ClaudeRun) async -> Ending {
        // The sweep comes first, so no picture is written before it. The cleanup is registered before the first write
        // below (nothing is awaited in between), so this turn's folder goes however the run ends.
        imageSweeper.sweepOnce(root: imageFolder)
        defer { CodexFolders.removeTurn(under: imageFolder, turn: turnID) }
        guard let pictures = CodexFolders.writeImages(prompt.images, under: imageFolder, turn: turnID) else {
            return .failed(Self.failure(CodexError.crashed))
        }
        let argv: [String]
        switch arguments(images: pictures) {
        case .arguments(let built): argv = built
        case .refused(let code): return .failed(Self.failure(code))
        }
        let environment = CodexCommand.childEnvironment(from: baseEnvironment, platform: .current, executable: executable)
        let output: AsyncStream<Data>
        do {
            output = try run.launch(executable: executable, arguments: argv, environment: environment,
                                    directory: chatFolder, stdin: Data(prompt.text.utf8))
        } catch {
            // Missing only when there is no program to run (an empty path, or no executable file there); one that is there
            // but will not start is a crash.
            let runnable = !executable.isEmpty && FileManager.default.isExecutableFile(atPath: executable)
            return .failed(Self.failure(runnable ? CodexError.crashed : CodexError.missing))
        }
        // The run must say something soon. After that it may take as long as it needs.
        let startup = timings.startup
        let watchdog = Task {
            try? await Task.sleep(nanoseconds: UInt64(startup * 1_000_000_000))
            if !Task.isCancelled, !run.sawOutput { run.timedOut() }
        }
        defer { watchdog.cancel() }

        var parser = CodexStreamParser(level: level.key)
        var reader = CodexLineReader()
        var stoppedByLevel = false
        var tooLong = false
        // After a refusal no more lines are parsed: the rest of the output is read and dropped.
        func feed(_ line: String) {
            guard !stoppedByLevel else { return }
            if !parser.consume(line: line) {
                stoppedByLevel = true
                run.stop()
            }
        }
        for await data in output {
            run.markOutput()
            for byte in data {
                guard !tooLong else { break }
                switch reader.push(byte) {
                case .pending:
                    continue
                case .line(let line):
                    feed(line)
                case .tooLong:
                    // The parser never sees the long line, nor anything after it.
                    tooLong = true
                    run.stop()
                }
            }
        }
        if !tooLong, let last = reader.flush() { feed(last) }
        await run.waitForExit()

        // Our own stops (a refused item, a line past the cap) are failures, so they are checked before the user's Stop.
        // A refused item comes first: once it has stopped the run, a later long line is not the reason for the failure.
        let outcome = parser.finish(exit: run.exitStatus, stderr: run.stderrText)
        if stoppedByLevel { return .failed(outcome.error ?? Self.failure(CodexError.levelExceeded)) }
        if tooLong { return .failed(Self.failure(CodexError.crashed)) }
        // Stop is not a failure of the run: the consumer has already gone.
        if run.wasStopped, !run.didTimeOut { return .stopped }
        if run.didTimeOut { return .failed(AIError(kind: .timeout)) }
        if let error = outcome.error { return .failed(error) }
        return .finished(outcome.text)
    }
}

#endif
