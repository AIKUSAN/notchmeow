import Foundation
#if canImport(FoundationModels)
import FoundationModels
#endif

/// Apple's on-device model (macOS 26+, Apple Intelligence on). FoundationModels is weak-linked
/// (`project.yml`), so on macOS 15 none of this runs and the app still launches.
enum AppleOnDevice {
    enum Status: Sendable, Equatable {
        case ready, downloading, turnOn, hidden

        /// The one line in Settings; nil when the Mac isn't eligible.
        var line: String? {
            switch self {
            case .ready: "Ready"
            case .downloading: "Downloading"
            case .turnOn: "Turn on Apple Intelligence in System Settings"
            case .hidden: nil
            }
        }
    }

    static func status() -> Status {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) {
            switch SystemLanguageModel.default.availability {
            case .available: return .ready
            case .unavailable(.modelNotReady): return .downloading
            case .unavailable(.appleIntelligenceNotEnabled): return .turnOn
            default: return .hidden
            }
        }
        #endif
        return .hidden
    }

    /// The provider, or nil before macOS 26.
    static func provider() -> (any ModelProvider)? {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) { return AppleOnDeviceProvider() }
        #endif
        return nil
    }

    /// Apple's context (4,096 tokens before macOS 27, maybe 8,192 after); 4,096 when unavailable.
    static func contextTokens() -> Int {
        #if canImport(FoundationModels)
        if #available(macOS 26, *) { return SystemLanguageModel.default.contextSize }
        #endif
        return AICatalog.Limits.defaultLocalContextTokens
    }
}

#if canImport(FoundationModels)
@available(macOS 26, *)
struct AppleOnDeviceProvider: ModelProvider {
    let id = AIProviderID.apple
    let displayName = "Apple on-device"
    let placement = AIPlacement.local
    /// Wait before the single retry after `rateLimited`.
    var rateLimitRetryDelay: TimeInterval = 1

    func listModels() async throws -> [ModelInfo] {
        [ModelInfo(id: "system", label: "Apple on-device", contextTokens: SystemLanguageModel.default.contextSize)]
    }

    func prewarm(model: String) async {
        LanguageModelSession(model: .default).prewarm()
    }

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
        AILog.record(.request(id, model: "system", placement: placement))
        let delay = rateLimitRetryDelay
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    do {
                        try await Self.generate(request, into: continuation)
                    } catch let e as AIError where e.kind == .rateLimited {
                        // Apple's limits for accessory apps are unclear: one quiet retry, then a temporary failure.
                        try await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
                        try await Self.generate(request, into: continuation)
                    }
                    continuation.finish()
                } catch {
                    let failure = (error as? AIError) ?? AIError(kind: HTTPErrorRules.transportKind(error))
                    AILog.record(.failure(.apple, kind: failure.kind, status: nil, code: nil, requestID: nil))
                    continuation.finish(throwing: failure)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Rebuilds the conversation as a transcript (every turn is resent, like the other providers).
    private static func generate(_ request: ChatRequest,
                                 into continuation: AsyncThrowingStream<ChatChunk, Error>.Continuation) async throws {
        func text(_ m: ChatRequest.Message) -> String {
            m.parts.map(OpenAICompatibleProvider.plainText).filter { !$0.isEmpty }.joined(separator: "\n\n")
        }
        func segment(_ s: String) -> [Transcript.Segment] { [.text(Transcript.TextSegment(content: s))] }
        var entries: [Transcript.Entry] = [.instructions(Transcript.Instructions(segments: segment(request.system),
                                                                                  toolDefinitions: []))]
        for m in request.messages.dropLast() {
            entries.append(m.role == .user ? .prompt(Transcript.Prompt(segments: segment(text(m))))
                                           : .response(Transcript.Response(assetIDs: [], segments: segment(text(m)))))
        }
        let session = LanguageModelSession(model: .default, transcript: Transcript(entries: entries))
        var sent = ""
        do {
            for try await snapshot in session.streamResponse(to: request.messages.last.map(text) ?? "") {
                let full = snapshot.content
                guard full.count > sent.count, full.hasPrefix(sent) else { continue }
                continuation.yield(.text(String(full.dropFirst(sent.count))))
                sent = full
            }
            continuation.yield(.finish(.stop))
        } catch let error as LanguageModelSession.GenerationError {
            throw map(error, sentText: !sent.isEmpty)
        }
    }

    private static func map(_ error: LanguageModelSession.GenerationError, sentText: Bool) -> AIError {
        switch error {
        case .rateLimited: return AIError(kind: sentText ? .interrupted : .rateLimited)
        case .guardrailViolation, .refusal: return AIError(kind: .refusal)
        case .exceededContextWindowSize: return AIError(kind: .badRequest, message: "This chat is too long for Apple's model.")
        case .assetsUnavailable: return AIError(kind: .unreachable)
        default: return AIError(kind: .server)
        }
    }
}
#endif
