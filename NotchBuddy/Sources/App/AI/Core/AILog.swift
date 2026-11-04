import Foundation

/// AI events for `~/Library/Logs/NotchMeow/nm.log`. The API only takes IDs, kinds, numbers and
/// codes: there is no way to log a prompt, file contents, a key or a provider's error message.
enum AILog {
    enum Event: Sendable {
        case request(AIProviderID, model: String, placement: AIPlacement)
        case reply(AIProviderID, ms: Int, finish: FinishReason?)
        case failure(AIProviderID, kind: AIErrorKind, status: Int?, code: String?, requestID: String?)
        case fallback(from: AIProviderID, to: AIProviderID, kind: AIErrorKind)
        case discovery(found: [AIProviderID], ms: Int)
        case attachment(kind: AttachmentKind, bytes: Int)
        case rejected(reason: AttachmentRejection, bytes: Int)
        case companionSaveFailed
    }

    static let sink = AILogSink()

    static func record(_ event: Event) { sink.write(line(event)) }

    static func line(_ event: Event) -> String {
        switch event {
        case .request(let p, let model, let placement):
            return "ai request provider=\(p.rawValue) model=\(short(model, 80)) placement=\(placement.rawValue)"
        case .reply(let p, let ms, let finish):
            return "ai reply provider=\(p.rawValue) ms=\(ms) finish=\(finish?.rawValue ?? "none")"
        case .failure(let p, let kind, let status, let code, let requestID):
            return "ai failure provider=\(p.rawValue) kind=\(kind.rawValue) status=\(status.map(String.init) ?? "-")"
                + " code=\(short(code ?? "-", 64)) request_id=\(short(requestID ?? "-", 128))"
        case .fallback(let from, let to, let kind):
            return "ai fallback from=\(from.rawValue) to=\(to.rawValue) kind=\(kind.rawValue)"
        case .discovery(let found, let ms):
            return "ai discovery found=\(found.map(\.rawValue).joined(separator: ",")) ms=\(ms)"
        case .attachment(let kind, let bytes):
            return "ai attachment kind=\(kind.rawValue) bytes=\(bytes)"
        case .rejected(let reason, let bytes):
            return "ai attachment rejected=\(reason.rawValue) bytes=\(bytes)"
        case .companionSaveFailed:
            return "companion save failed"
        }
    }

    /// Codes and IDs come from servers: keep them short and on one line.
    private static func short(_ s: String, _ max: Int) -> String {
        let one = s.filter { !$0.isNewline && $0 != " " }
        return one.count > max ? String(one.prefix(max)) + "…" : one
    }
}

/// Where AI log lines go. Tests swap the writer to capture lines.
final class AILogSink: @unchecked Sendable {
    private let lock = NSLock()
    private var writer: @Sendable (String) -> Void = { appendAppLog("nm.log", $0) }

    func write(_ line: String) {
        let w = lock.withLock { writer }
        w(line)
    }

    func replace(_ newWriter: @escaping @Sendable (String) -> Void) {
        lock.withLock { writer = newWriter }
    }
}

/// Types that hold an API key print a summary without it: `description`, `debugDescription`,
/// `dump()` and the debugger all go through `redactedSummary`.
protocol RedactsSecrets: CustomStringConvertible, CustomDebugStringConvertible, CustomReflectable {
    var redactedSummary: String { get }
}

extension RedactsSecrets {
    var description: String { redactedSummary }
    var debugDescription: String { redactedSummary }
    var customMirror: Mirror { Mirror(self, children: ["summary": redactedSummary], displayStyle: .struct) }

    /// "none" or "<redacted>", never the key.
    static func keyMark(_ key: String?) -> String { (key ?? "").isEmpty ? "none" : "<redacted>" }
}
