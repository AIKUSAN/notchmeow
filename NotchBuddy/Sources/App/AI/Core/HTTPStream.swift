import Foundation

// MARK: - URLs

enum AIURL {
    /// Removes spaces, `user:password@`, trailing slashes and a trailing /api or /v1 (users paste docs URLs).
    static func normalise(_ raw: String) -> String {
        var s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        // Credentials never get stored with a server address (a key goes in the Keychain instead).
        if var parts = URLComponents(string: s), parts.user != nil || parts.password != nil {
            parts.user = nil
            parts.password = nil
            s = parts.string ?? s
        }
        while s.hasSuffix("/") { s.removeLast() }
        for suffix in ["/api", "/v1"] where s.hasSuffix(suffix) { s.removeLast(suffix.count) }
        return s
    }

    /// Debug builds only: `NM_AI_BASE_URL_OVERRIDE=http://127.0.0.1:PORT` points the cloud
    /// providers at `tests/fake_local_llm.py`. Compiled out of Release, so a shipped app can't be redirected.
    static func cloudOverride(_ environment: [String: String] = ProcessInfo.processInfo.environment) -> String? {
        #if DEBUG
        guard let raw = environment["NM_AI_BASE_URL_OVERRIDE"], !raw.isEmpty else { return nil }
        return normalise(raw)
        #else
        return nil
        #endif
    }
}

// MARK: - Deadlines

/// `headers`: until the HTTP status arrives. `firstToken`: until the first output (both from the start).
struct StreamDeadlines: Sendable, Equatable {
    var headers: TimeInterval
    var firstToken: TimeInterval

    static let cloud = StreamDeadlines(headers: AICatalog.Timeouts.connectCloud,
                                       firstToken: AICatalog.Timeouts.firstTokenCloud)
    /// A local server sends its headers only once the model is loaded, so both wait the first-token time;
    /// the 5 s connect check is the reachability preflight in `OpenAICompatibleProvider`.
    static let local = StreamDeadlines(headers: AICatalog.Timeouts.firstTokenLocal,
                                       firstToken: AICatalog.Timeouts.firstTokenLocal)
}

private final class StreamClock: @unchecked Sendable {
    private let lock = NSLock()
    private var headers = false
    private var token = false
    private var fired = false

    func sawHeaders() { lock.withLock { headers = true } }
    func sawToken() { lock.withLock { token = true } }
    var headersSeen: Bool { lock.withLock { headers } }
    var tokenSeen: Bool { lock.withLock { token } }
    func fire() { lock.withLock { fired = true } }
    var timedOut: Bool { lock.withLock { fired } }
}

// MARK: - Transport

enum HTTPStream {
    /// Long idle limit once tokens flow; the deadlines above cover the start.
    static let idleTimeout: TimeInterval = 120

    /// POSTs `request`, maps HTTP errors, then feeds every line to `parser`.
    /// A stream error event or a missing terminal event ends the stream with an `AIError`.
    static func run<P: StreamParser>(_ request: URLRequest, parser: P, provider: AIProviderID,
                                     deadlines: StreamDeadlines,
                                     session: URLSession = .shared) -> AsyncThrowingStream<ChatChunk, Error> {
        AsyncThrowingStream { continuation in
            let clock = StreamClock()
            let started = Date()
            let work = Task {
                var parser = parser
                var requestID: String?
                do {
                    let (bytes, response) = try await session.bytes(for: request)
                    clock.sawHeaders()
                    guard let http = response as? HTTPURLResponse else { throw AIError(kind: .unreachable) }
                    let headers = http.allHeaderFields.reduce(into: [String: String]()) {
                        $0["\($1.key)"] = "\($1.value)"
                    }
                    requestID = HTTPErrorRules.header("x-request-id", in: headers)
                        ?? HTTPErrorRules.header("request-id", in: headers)
                    guard http.statusCode == 200 else {
                        var body = Data()
                        for try await byte in bytes {
                            body.append(byte)
                            if body.count > 65_536 { break }
                        }
                        throw HTTPErrorRules.error(status: http.statusCode, body: body, headers: headers)
                    }
                    var finish: FinishReason?
                    // Lines end at LF only (`SSELineSplitter`): `bytes.lines` would also split on a lone CR,
                    // U+2028, U+2029 and U+0085, which the contract keeps inside the line.
                    var splitter = SSELineSplitter()
                    for try await byte in bytes {
                        guard let line = splitter.push(byte) else { continue }
                        for chunk in parser.consume(line: line) {
                            try emit(chunk, clock: clock, continuation: continuation, finish: &finish, requestID: requestID)
                        }
                        if parser.isTerminal { break }
                    }
                    if !parser.isTerminal, let last = splitter.flush() {
                        for chunk in parser.consume(line: last) {
                            try emit(chunk, clock: clock, continuation: continuation, finish: &finish, requestID: requestID)
                        }
                    }
                    for chunk in parser.finish() {
                        try emit(chunk, clock: clock, continuation: continuation, finish: &finish, requestID: requestID)
                    }
                    AILog.record(.reply(provider, ms: Int(Date().timeIntervalSince(started) * 1000), finish: finish))
                    continuation.finish()
                } catch {
                    var failure: AIError
                    if clock.timedOut {
                        failure = AIError(kind: .timeout)
                    } else if let e = error as? AIError {
                        failure = e
                    } else {
                        failure = AIError(kind: HTTPErrorRules.transportKind(error))
                    }
                    if failure.requestID == nil { failure.requestID = requestID }
                    AILog.record(.failure(provider, kind: failure.kind, status: failure.status, code: failure.code,
                                          requestID: failure.requestID))
                    continuation.finish(throwing: failure)
                }
            }
            let watchdog = Task {
                try? await Task.sleep(nanoseconds: UInt64(deadlines.headers * 1_000_000_000))
                if Task.isCancelled { return }
                if !clock.headersSeen { clock.fire(); work.cancel(); return }
                let rest = deadlines.firstToken - deadlines.headers
                if rest > 0 { try? await Task.sleep(nanoseconds: UInt64(rest * 1_000_000_000)) }
                if Task.isCancelled { return }
                if !clock.tokenSeen { clock.fire(); work.cancel() }
            }
            continuation.onTermination = { _ in
                work.cancel()
                watchdog.cancel()
            }
        }
    }

    private static func emit(_ chunk: ChatChunk, clock: StreamClock,
                             continuation: AsyncThrowingStream<ChatChunk, Error>.Continuation,
                             finish: inout FinishReason?, requestID: String?) throws {
        switch chunk {
        case .error(let kind):
            throw AIError(kind: kind, requestID: requestID)
        case .finish(let f):
            finish = f
        case .text(let t) where t.isEmpty:
            return
        default:
            clock.sawToken()
        }
        continuation.yield(chunk)
    }

    /// GET/POST that returns JSON, with the same error mapping.
    static func json(_ request: URLRequest, session: URLSession = .shared) async throws -> Any {
        let data: Data, response: URLResponse
        do {
            (data, response) = try await session.data(for: request)
        } catch {
            throw AIError(kind: HTTPErrorRules.transportKind(error))
        }
        guard let http = response as? HTTPURLResponse else { throw AIError(kind: .unreachable) }
        guard http.statusCode == 200 else {
            let headers = http.allHeaderFields.reduce(into: [String: String]()) { $0["\($1.key)"] = "\($1.value)" }
            throw HTTPErrorRules.error(status: http.statusCode, body: data, headers: headers)
        }
        guard let json = try? JSONSerialization.jsonObject(with: data) else { throw AIError(kind: .badRequest) }
        return json
    }

    /// JSON body for a POST. `[String: Any]` never crosses an actor: callers build and encode in one place.
    static func post(_ url: URL, body: [String: Any], headers: [String: String], timeout: TimeInterval) -> URLRequest {
        var req = URLRequest(url: url, timeoutInterval: timeout)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")
        for (k, v) in headers { req.setValue(v, forHTTPHeaderField: k) }
        req.httpBody = try? JSONSerialization.data(withJSONObject: body)
        return req
    }
}
