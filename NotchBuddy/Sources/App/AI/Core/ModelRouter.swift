import Foundation

// MARK: - Settings

/// A model on a provider. `serverID` tells two servers of the same kind apart (custom servers).
struct ModelRef: Sendable, Equatable, Hashable, Codable {
    var provider: AIProviderID
    var model: String
    var serverID: String? = nil
}

/// What a feature (Chat, File questions) uses: Auto, or one model chosen by the user.
enum FeatureSetting: Sendable, Equatable, Hashable, Codable {
    case auto
    case explicit(ModelRef)
}

/// The features that pick a model. F adds `cats`.
enum AIFeature: String, Sendable, Codable, CaseIterable {
    case chat, files
}

/// A local or network model that answered discovery, in discovery order.
struct LocalCandidate: Sendable, Equatable {
    var provider: AIProviderID
    var model: String
    var placement: AIPlacement
    var serverID: String? = nil
}

struct RouteInput: Sendable {
    var setting: FeatureSetting = .auto
    var preferredCloud: AIProviderID = .anthropic
    /// Cloud providers with a key.
    var keys: Set<AIProviderID> = []
    var online = true
    var localReady: [LocalCandidate] = []
    var lastUsedLocal: ModelRef? = nil
    var appleReady = false
    /// Contract tests only: the failure to route.
    var failure: AIErrorKind? = nil
}

enum RouteOutcome: String, Sendable, Equatable {
    case ok, fallback, error, interrupted, cancelled
    case retryCountdown = "retry_countdown"
    case emptyState = "empty_state"
}

/// `reference.py` `route()` result.
struct RouteDecision: Sendable, Equatable {
    var primary: AIProviderID?
    var outcome: RouteOutcome
    var answeredBy: AIProviderID?
    var label: AIPlacement?
    var errorKind: AIErrorKind?
}

/// What to call first, and the one local retry Auto may use.
struct RoutePlan: Sendable, Equatable {
    var primary: AIProviderID
    /// Explicit or local model; nil for an Auto cloud primary (the caller uses the remembered model).
    var model: String?
    var serverID: String?
    var placement: AIPlacement
    var fallback: LocalCandidate?
    var isAuto: Bool
}

// MARK: - Router

/// Pure routing rules, identical to `tests/fixtures/ai/reference.py`.
enum ModelRouter {
    static let apple = LocalCandidate(provider: .apple, model: "system", placement: .local)

    /// Automatic retries of a busy cloud before "still busy". Mirrors MAX_AUTO_RETRIES in windows/src/views/chat.ts.
    static let maxAutoRetries = 3
    static func shouldAutoRetry(retries: Int) -> Bool { retries < maxAutoRetries }

    /// Preferred cloud, then the others of Claude plan / Claude API / OpenAI, then Google; the first that is ready.
    /// `keys` holds the cloud providers with a key, plus `claudeCode` when the user connected it and the last
    /// check found Claude Code signed in.
    static func cloudChoice(_ input: RouteInput) -> AIProviderID? {
        let other: [AIProviderID] = [.claudeCode, .anthropic, .openai].filter { $0 != input.preferredCloud }
        return ([input.preferredCloud] + other + [.google]).first { input.keys.contains($0) }
    }

    /// Last used if ready, else the first ready, else Apple.
    static func localChoice(_ input: RouteInput) -> LocalCandidate? {
        if let last = input.lastUsedLocal,
           let hit = input.localReady.first(where: { $0.provider == last.provider && $0.model == last.model }) {
            return hit
        }
        if let first = input.localReady.first { return first }
        return input.appleReady ? apple : nil
    }

    static func placement(of provider: AIProviderID, in input: RouteInput) -> AIPlacement {
        if provider.isCloud { return .cloud }
        if provider == .apple { return .local }
        return input.localReady.first { $0.provider == provider }?.placement ?? .local
    }

    /// nil means nothing is set up (empty state).
    static func plan(_ input: RouteInput) -> RoutePlan? {
        if case .explicit(let ref) = input.setting {
            let ready = input.localReady.first {
                $0.provider == ref.provider && (ref.serverID == nil || $0.serverID == ref.serverID)
            }
            return RoutePlan(primary: ref.provider, model: ref.model, serverID: ref.serverID ?? ready?.serverID,
                             placement: ready?.placement ?? placement(of: ref.provider, in: input),
                             fallback: nil, isAuto: false)
        }
        let cloud = cloudChoice(input)
        let local = localChoice(input)
        if let cloud, input.online || local == nil {
            return RoutePlan(primary: cloud, model: nil, serverID: nil, placement: .cloud, fallback: local, isAuto: true)
        }
        if let local {
            return RoutePlan(primary: local.provider, model: local.model, serverID: local.serverID,
                             placement: local.placement, fallback: nil, isAuto: true)
        }
        return nil
    }

    /// What a failure of the primary means.
    static func afterFailure(_ plan: RoutePlan, failure: AIErrorKind) -> RouteDecision {
        switch failure {
        case .cancelled:
            return RouteDecision(primary: plan.primary, outcome: .cancelled, answeredBy: nil, label: nil, errorKind: nil)
        case .interrupted:
            return RouteDecision(primary: plan.primary, outcome: .interrupted, answeredBy: plan.primary,
                                 label: plan.placement, errorKind: .interrupted)
        default:
            break
        }
        if failure.isTemporary, plan.isAuto, plan.primary.isCloud, let local = plan.fallback {
            return RouteDecision(primary: plan.primary, outcome: .fallback, answeredBy: local.provider,
                                 label: local.placement, errorKind: failure)
        }
        if failure == .rateLimited || failure == .overloaded {
            return RouteDecision(primary: plan.primary, outcome: .retryCountdown, answeredBy: nil, label: nil, errorKind: failure)
        }
        return RouteDecision(primary: plan.primary, outcome: .error, answeredBy: nil, label: nil, errorKind: failure)
    }

    /// The contract function: plan, then apply `input.failure`.
    static func route(_ input: RouteInput) -> RouteDecision {
        guard let plan = plan(input) else {
            return RouteDecision(primary: nil, outcome: .emptyState, answeredBy: nil, label: nil, errorKind: nil)
        }
        guard let failure = input.failure else {
            return RouteDecision(primary: plan.primary, outcome: .ok, answeredBy: plan.primary,
                                 label: plan.placement, errorKind: nil)
        }
        return afterFailure(plan, failure: failure)
    }
}
