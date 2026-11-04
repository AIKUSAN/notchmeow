import Combine
import Foundation

/// Glue between AppState and the AI core: discovery, routing input, providers, pre-warming.
@MainActor
final class AIService {
    static let shared = AIService()
    private var state: AppState { .shared }
    private var firstOpenWatch: AnyCancellable?

    /// At launch: watch the network, and look for local servers the first time the island opens.
    /// Nothing is requested while it stays hidden (0% CPU, no model-list calls in the background).
    func start() {
        KeychainStore.shared.preload(state.customServers.map(\.keychainAccount))
        NetworkMonitor.shared.start { online in
            // Only a real change: a @Published write wakes every AppState observer, even to the same value.
            Task { @MainActor in if AppState.shared.isOnline != online { AppState.shared.isOnline = online } }
        }
        firstOpenWatch = state.$mode.sink { mode in
            guard mode == .expanded else { return }
            Task { @MainActor in AIService.shared.firstLook() }
        }
    }

    private func firstLook() {
        guard firstOpenWatch != nil else { return }
        firstOpenWatch = nil
        Task { await discover() }
    }

    private var addedTargets: [ProbeTarget] {
        state.customServers.map {
            ProbeTarget(serverID: $0.id, provider: .custom, name: $0.name, baseURL: $0.baseURL,
                        apiKey: KeychainStore.shared.get($0.keychainAccount))
        }
    }

    /// Checks localhost (0.3 s) and the user's servers (2 s, in parallel), and Apple's model. The localhost
    /// results show as soon as they are in; the added servers join when their check ends.
    func discover() async {
        let added = Set(state.customServers.map(\.id))
        let kept = state.localServers.filter { added.contains($0.serverID) }
        state.localServers = await Discovery.run(ProbeTarget.defaults + addedTargets, onLocal: { local in
            await MainActor.run { AppState.shared.localServers = local + kept }
        })
        state.appleStatus = AppleOnDevice.status()
    }

    // MARK: Routing input

    func key(_ provider: AIProviderID) -> String? {
        guard let account = AICatalog.info(provider).keychainKey,
              let key = KeychainStore.shared.get(account), !key.isEmpty else { return nil }
        return key
    }

    /// The cloud providers Auto may use: those with a key, and Claude Code once the user connected it and the last
    /// check found it signed in.
    var cloudKeys: Set<AIProviderID> {
        var ready = Set(AICatalog.cloudOrder.filter { key($0) != nil })
        #if !APPSTORE
        if state.claudeCodeEnabled, state.claudeCodeStatus.isReady { ready.insert(.claudeCode) }
        #endif
        return ready
    }

    /// The remembered model for a cloud provider, else its catalog default.
    func cloudModel(_ provider: AIProviderID) -> String {
        let listed = state.fetchedProviderModels[provider]?.map(\.id) ?? []
        let remembered: String = switch provider {
        case .anthropic: state.claudeModel
        case .openai: state.openAIChatModel
        #if !APPSTORE
        case .claudeCode: state.claudeCodeModel.rawValue
        #endif
        case .codexPlan: ""
        default: state.googleChatModel
        }
        if listed.isEmpty || listed.contains(remembered) { return remembered }
        return AICatalog.defaultModel(for: provider, available: listed) ?? remembered
    }

    /// The remembered model on a server if it still has it, else its first model.
    func localModel(_ server: DiscoveredServer) -> String? {
        let ids = server.models.map(\.id)
        if let remembered = state.localModelMemory[server.serverID], ids.contains(remembered) { return remembered }
        return ids.first
    }

    func localReady() -> [LocalCandidate] {
        state.localServers.filter(\.isReady).compactMap { server in
            localModel(server).map {
                LocalCandidate(provider: server.provider, model: $0, placement: server.placement, serverID: server.serverID)
            }
        }
    }

    func routeInput(_ feature: AIFeature) -> RouteInput {
        RouteInput(setting: state.choice(for: feature), preferredCloud: state.preferredCloud, keys: cloudKeys,
                   online: state.isOnline, localReady: localReady(), lastUsedLocal: state.lastUsedLocal,
                   appleReady: state.appleStatus == .ready)
    }

    // MARK: Targets

    func target(_ provider: AIProviderID, model: String, placement: AIPlacement, serverID: String?) -> ChatTarget {
        let server = state.localServers.first { $0.serverID == (serverID ?? provider.rawValue) }
        var label = state.fetchedProviderModels[provider]?.first { $0.id == model }?.label
        #if !APPSTORE
        if provider == .claudeCode { label = "Claude plan · \(ClaudeCodeModel(rawValue: model)?.label ?? model)" }
        if provider == .codexPlan { label = "OpenAI plan" }
        #endif
        return ChatTarget(provider: provider, model: model, placement: placement,
                          serverID: serverID ?? server?.serverID, host: server?.host, modelLabel: label)
    }

    func primaryTarget(_ plan: RoutePlan) -> ChatTarget {
        target(plan.primary, model: plan.model ?? cloudModel(plan.primary), placement: plan.placement, serverID: plan.serverID)
    }

    func target(_ c: LocalCandidate) -> ChatTarget {
        target(c.provider, model: c.model, placement: c.placement, serverID: c.serverID)
    }

    /// What a feature uses right now (chip, drop card, Settings line).
    func resolve(_ feature: AIFeature) -> (primary: ChatTarget?, fallback: ChatTarget?) {
        guard let plan = ModelRouter.plan(routeInput(feature)) else { return (nil, nil) }
        return (primaryTarget(plan), plan.fallback.map(target))
    }

    /// The chat's model chip: "Auto · claude-sonnet-5-5", or the chosen model.
    func chip(_ feature: AIFeature) -> (label: String, accentHex: String) {
        let t = resolve(feature).primary
        let accent = t.map { ChatProvider($0.provider).accentHex } ?? "#5C6370"
        #if !APPSTORE
        // The engine says who pays; the label is whatever Claude Code last reported, never a guess.
        if t?.provider == .claudeCode {
            return (ClaudeCodeText.modelChip(authMethod: state.claudeCodeStatus.authMethod, paidBy: state.claudeRunReport?.paidBy), accent)
        }
        if t?.provider == .codexPlan { return (CodexText.modelChip(mode: state.codexStatus.mode), accent) }
        #endif
        let model = t.map { $0.provider == .apple ? "Apple on-device" : $0.model } ?? "No model yet"
        if case .auto = state.choice(for: feature) { return ("Auto · \(model)", accent) }
        return (model, accent)
    }

    /// One line under each Settings row: "Claude Sonnet 5.5 · falls back to Local · qwen3.5:2b".
    func resolutionLine(_ feature: AIFeature) -> String {
        let r = resolve(feature)
        guard let primary = r.primary else { return "Nothing set up yet: add a cloud key or start a local model." }
        let first = AIMessages.targetLabel(primary)
        return r.fallback.map { "\(first) · falls back to \(AIMessages.targetLabel($0))" } ?? first
    }

    /// Auto needs a local model now: look again on this computer only (≤ 0.3 s), then pick last-used,
    /// first ready, or Apple. A server the user added keeps what the last full scan found.
    func freshLocalTarget(for feature: AIFeature) async -> ChatTarget? {
        state.localServers = await Discovery.rescanLocal(known: state.localServers, targets: ProbeTarget.defaults + addedTargets)
        state.appleStatus = AppleOnDevice.status()
        return ModelRouter.localChoice(routeInput(feature)).map(target)
    }

    // MARK: Providers

    func factory() -> ProviderFactory {
        var keys: [AIProviderID: String] = [:]
        for p in AICatalog.cloudOrder { keys[p] = key(p) }
        var servers: [String: ProviderFactory.ServerAddress] = [:]
        for s in state.localServers { servers[s.serverID] = .init(baseURL: s.baseURL, key: s.apiKey) }
        return ProviderFactory(keys: keys, servers: servers, cloudOverride: AIURL.cloudOverride(),
                               apple: AppleOnDevice.provider(), appleContextTokens: AppleOnDevice.contextTokens())
    }

    /// Opening the chat loads the selected local model ahead of the first message.
    func prewarm(_ feature: AIFeature) {
        guard let t = resolve(feature).primary, t.placement != .cloud else { return }
        let provider = factory().make(t)
        Task.detached(priority: .utility) { await provider.prewarm(model: t.model) }
    }

    #if !APPSTORE
    /// Looks for Claude Code and asks it two questions (version, signed in). Called when Settings opens and before a
    /// chat's first turn, never on a timer.
    func refreshClaudeStatus() async {
        let found = await ClaudeCodeLocator.status()
        if state.claudeCodeStatus != found { state.claudeCodeStatus = found }
    }

    /// Looks for Codex and asks it two questions (version, signed in). Called when Settings opens, when the model picker opens and before a turn
    /// that names the OpenAI plan; never on a timer.
    func refreshCodexStatus() async {
        let found = await CodexLocator.status()
        if state.codexStatus != found { state.codexStatus = found }
    }
    #endif

    /// Cloud model list (also checks a pasted key). `failure` says why a call failed, so "offline" is never
    /// read as "refused"; an empty list with no failure still counts as refused.
    func listCloudModels(_ provider: AIProviderID, key: String) async -> (models: [ModelInfo], failure: AIError?) {
        var f = factory()
        f.keys[provider] = key
        do {
            return (try await f.make(ChatTarget(provider: provider, model: "", placement: .cloud)).listModels(), nil)
        } catch {
            return ([], (error as? AIError) ?? AIError(kind: HTTPErrorRules.transportKind(error)))
        }
    }
}
