import Foundation

/// One concrete model to call.
struct ChatTarget: Sendable, Equatable {
    var provider: AIProviderID
    var model: String
    var placement: AIPlacement
    /// Discovery's server ID (custom servers), nil for cloud and default local servers.
    var serverID: String? = nil
    /// Server host for the `network · model @ host` caption.
    var host: String? = nil
    /// Human model name when the provider gives one ("Claude Sonnet 5.5").
    var modelLabel: String? = nil

    var stripsThinkBlocks: Bool { AICatalog.info(provider).api == .openaiChat }
    var ref: ModelRef { ModelRef(provider: provider, model: model, serverID: serverID) }
}

enum RunEvent: Sendable, Equatable {
    /// A new attempt began (the primary, or the local retry): the reply so far is discarded.
    case started(ChatTarget)
    /// Everything visible so far (think blocks hidden), at most ~15 times a second.
    case text(String)
    case citation(Citation)
    /// A local model has not produced anything after `wakingDelay`: it is probably loading.
    case waking(ChatTarget)
    case fellBack(from: ChatTarget, to: ChatTarget, kind: AIErrorKind)
    /// Claude Code started, or updated, a step.
    case step(ChatStep)
    /// What Claude Code said about the run it started (who pays, which model).
    case engine(EngineReport)
}

struct RunResult: Sendable, Equatable {
    var outcome: RouteOutcome
    var answeredBy: ChatTarget?
    var text: String = ""
    var citations: [Citation] = []
    var finish: FinishReason? = nil
    /// Claude Code took steps before the failure: whatever they did stays done.
    var tookSteps = false
    /// The failure behind `error`, `retryCountdown`, `fallback` (the primary's) or `interrupted`.
    var error: AIError? = nil
}

/// Runs one message: the primary model, then at most one local retry when Auto allows it.
/// Fallback only happens before any text was shown; afterwards a failure keeps the partial reply.
struct ChatRunner: Sendable {
    let makeProvider: @Sendable (ChatTarget) -> any ModelProvider
    let makeRequest: @Sendable (ChatTarget) async -> ChatRequest
    var wakingDelay: TimeInterval = 1.5

    func run(plan: RoutePlan, primary: ChatTarget,
             fallback: @escaping @Sendable () async -> ChatTarget?,
             onEvent: @escaping @Sendable (RunEvent) async -> Void) async -> RunResult {
        let first = await attempt(primary, onEvent: onEvent)
        guard var error = first.error else { return first }
        // Out of room is not a passing problem: another model would not be asked the same question, so
        // the user is told, with a way to pick another model.
        if !first.text.isEmpty || first.tookSteps || error.kind == .cancelled || error.kind == .refusal
            || error.code == AIError.outOfRoomCode {
            return first
        }
        // Cut before any text (a captive portal, a crash right after the headers): nothing to keep,
        // so it is a failed request, not an interrupted reply.
        if error.kind == .interrupted { error.kind = .server }
        var decision = ModelRouter.afterFailure(plan, failure: error.kind)
        // Auto with a cloud primary and a temporary failure wants a local model. When none is known yet
        // (Ollama started after the last scan), ask once more: spec §2's "Auto needs a local fallback".
        let wantsLocal = decision.outcome == .fallback
            || (plan.isAuto && plan.primary.isCloud && plan.fallback == nil && error.kind.isTemporary)
        if wantsLocal {
            if let local = await fallback() {
                await onEvent(.fellBack(from: primary, to: local, kind: error.kind))
                AILog.record(.fallback(from: primary.provider, to: local.provider, kind: error.kind))
                var second = await attempt(local, onEvent: onEvent)
                if second.error == nil {
                    second.outcome = .fallback
                    second.error = error
                    return second
                }
                if !second.text.isEmpty || second.error?.kind == .cancelled { return second }
            }
            var noLocal = plan
            noLocal.fallback = nil
            decision = ModelRouter.afterFailure(noLocal, failure: error.kind)
        }
        return RunResult(outcome: decision.outcome, answeredBy: nil, error: error)
    }

    private func attempt(_ target: ChatTarget, onEvent: @escaping @Sendable (RunEvent) async -> Void) async -> RunResult {
        await onEvent(.started(target))
        let request = await makeRequest(target)
        let provider = makeProvider(target)
        let shown = ShownFlag()
        let waking = Task {
            guard target.placement != .cloud else { return }
            try? await Task.sleep(nanoseconds: UInt64(wakingDelay * 1_000_000_000))
            if !Task.isCancelled, !shown.value { await onEvent(.waking(target)) }
        }
        defer { waking.cancel() }
        var acc = ReplyAccumulator(stripsThinkBlocks: target.stripsThinkBlocks)
        var lastSent = Date.distantPast
        do {
            for try await chunk in provider.stream(request) {
                acc.add(chunk)
                switch chunk {
                case .text, .refusal:
                    shown.set()
                    if Date().timeIntervalSince(lastSent) >= 1.0 / 15.0 {
                        lastSent = Date()
                        await onEvent(.text(acc.visibleText))
                    }
                case .citation(let c):
                    await onEvent(.citation(c))
                case .step(let step):
                    shown.set()
                    await onEvent(.step(step))
                case .engine(let report):
                    await onEvent(.engine(report))
                default:
                    break
                }
            }
            try Task.checkCancellation()
        } catch {
            let failure = (error as? AIError) ?? AIError(kind: HTTPErrorRules.transportKind(error))
            await onEvent(.text(acc.visibleText))
            let text = acc.visibleText.trimmingCharacters(in: .whitespacesAndNewlines)
            if failure.kind != .cancelled, let refused = Self.refusal(acc, text: text, target: target) { return refused }
            let outcome: RouteOutcome = failure.kind == .cancelled ? .cancelled : (text.isEmpty ? .error : .interrupted)
            return RunResult(outcome: outcome, answeredBy: text.isEmpty ? nil : target, text: text,
                             citations: acc.citations, tookSteps: acc.sawSteps, error: failure)
        }
        await onEvent(.text(acc.visibleText))
        if let refusal = acc.refusal {
            return RunResult(outcome: .error, answeredBy: target, text: refusal, finish: .refusal,
                             error: AIError(kind: .refusal))
        }
        // Only a thinking model's server emits <think> blocks; another provider's text keeps a literal tag.
        let text = acc.visibleText.trimmingCharacters(in: .whitespacesAndNewlines)
        if let refused = Self.refusal(acc, text: text, target: target) { return refused }
        // A finished stream with nothing to show is a failed request, never an empty bubble or an empty
        // turn in the history. With `length`, a thinking model spent the whole cap inside <think>.
        if text.isEmpty {
            return RunResult(outcome: .error, error: AIError(kind: .server,
                                                             code: acc.finish == .length ? AIError.outOfRoomCode : nil))
        }
        return RunResult(outcome: .ok, answeredBy: target, text: text, citations: acc.citations, finish: acc.finish)
    }
}

extension ChatRunner {
    /// A reply with nothing to show that the model declined (a refusal chunk, or a `content_filter` finish):
    /// told to the person, never retried on another model.
    fileprivate static func refusal(_ acc: ReplyAccumulator, text: String, target: ChatTarget) -> RunResult? {
        guard text.isEmpty, acc.refusal != nil || acc.finish == .refusal else { return nil }
        return RunResult(outcome: .error, answeredBy: target, text: acc.refusal ?? "", finish: .refusal,
                         error: AIError(kind: .refusal))
    }
}

extension AIError {
    /// Our own code (never a provider's): the reply hit `max_tokens` before any visible text.
    static let outOfRoomCode = "nm_out_of_room"
}

private final class ShownFlag: @unchecked Sendable {
    private let lock = NSLock()
    private var shown = false
    func set() { lock.withLock { shown = true } }
    var value: Bool { lock.withLock { shown } }
}
