import Foundation

/// A server the user added in Settings → AI → Add server…. Its key (optional) is in the Keychain.
struct CustomServer: Codable, Equatable, Identifiable, Sendable {
    /// "custom-" plus 24 hex digits; always matches `^[a-z0-9-]{1,32}$` (the contract's server ID rule).
    let id: String
    var name: String
    var baseURL: String

    static let idPrefix = "custom-"

    static func newID() -> String {
        idPrefix + UUID().uuidString.lowercased().replacingOccurrences(of: "-", with: "").prefix(24)
    }

    /// `^[a-z0-9-]{1,32}$`, checked by hand: 1 to 32 bytes, each a lowercase letter, a digit or `-`.
    static func isValidID(_ id: String) -> Bool {
        (1...32).contains(id.utf8.count)
            && id.utf8.allSatisfy { ($0 >= 0x61 && $0 <= 0x7A) || ($0 >= 0x30 && $0 <= 0x39) || $0 == 0x2D }
    }

    /// `custom-server-key` (providers.json) is a prefix: it plus `.` and the server ID makes one Keychain item per server.
    var keychainAccount: String { "custom-server-key.\(id)" }
}

/// Builds the provider for a target from a snapshot of keys and servers, so streams can run
/// off the main actor.
struct ProviderFactory: Sendable {
    struct ServerAddress: Sendable, Equatable {
        var baseURL: String
        var key: String?
    }

    var keys: [AIProviderID: String] = [:]
    /// By server ID ("ollama", "custom-…").
    var servers: [String: ServerAddress] = [:]
    /// Debug builds only (`AIURL.cloudOverride()`).
    var cloudOverride: String? = nil
    /// Apple's provider when this Mac has it (macOS 26+).
    var apple: (any ModelProvider)? = nil
    var appleContextTokens: Int = AICatalog.Limits.defaultLocalContextTokens
    #if !APPSTORE
    /// The Claude Code run this turn would make: the chat's session and level (`ClaudeService` sets it).
    var claude: ClaudeCodeSetup? = nil
    /// The Codex run this turn would make, when the chat has set one.
    var codex: CodexSetup? = nil
    #endif

    func make(_ t: ChatTarget) -> any ModelProvider {
        switch t.provider {
        case .anthropic:
            return AnthropicProvider(apiKey: keys[.anthropic] ?? "",
                                     baseURL: cloudOverride ?? AICatalog.info(.anthropic).baseURL!)
        case .openai:
            return OpenAIProvider(apiKey: keys[.openai] ?? "", baseURL: cloudOverride ?? AICatalog.info(.openai).baseURL!)
        case .google:
            return OpenAICompatibleProvider.make(.google, baseURL: cloudOverride ?? AICatalog.info(.google).baseURL!,
                                                 apiKey: keys[.google])
        case .apple:
            return apple ?? UnavailableProvider(id: .apple)
        case .claudeCode:
            #if !APPSTORE
            if let setup = claude {
                return ClaudeCodeProvider(executable: setup.executable, turn: setup.turn, preamble: setup.preamble)
            }
            #endif
            return UnavailableProvider(id: .claudeCode)
        case .codexPlan:
            #if !APPSTORE
            if let setup = codex {
                return CodexProvider(executable: setup.executable, level: setup.level, model: setup.model,
                                     knownState: setup.knownState)
            }
            #endif
            return UnavailableProvider(id: .codexPlan)
        case .ollama, .lmstudio, .llamacpp, .jan, .custom:
            let server = servers[t.serverID ?? t.provider.rawValue]
            return OpenAICompatibleProvider.make(t.provider,
                                                 baseURL: server?.baseURL ?? AICatalog.info(t.provider).baseURL ?? "",
                                                 name: t.provider == .custom ? t.host : nil,
                                                 placement: t.placement, apiKey: server?.key)
        }
    }

    /// Whether the model reads images, and its context, for sizing files.
    func details(_ t: ChatTarget) async -> (vision: Bool, contextTokens: Int?) {
        switch t.provider {
        case .anthropic, .openai, .google, .claudeCode, .codexPlan: return (true, nil)
        case .apple: return (false, appleContextTokens)
        default:
            guard let provider = make(t) as? OpenAICompatibleProvider,
                  let info = await provider.modelDetails(t.model) else { return (false, nil) }
            return (info.capabilities.contains(.vision), info.contextTokens)
        }
    }
}

/// Stands in for a provider this Mac doesn't have; every call fails as unreachable.
struct UnavailableProvider: ModelProvider {
    let id: AIProviderID
    var displayName: String { AICatalog.info(id).name }
    let placement = AIPlacement.local
    func listModels() async throws -> [ModelInfo] { throw AIError(kind: .unreachable) }
    func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
        AsyncThrowingStream { $0.finish(throwing: AIError(kind: .unreachable)) }
    }
}

/// First launch with E1: the old single chat provider becomes the Chat choice (Anthropic, the
/// old default, becomes Auto), and Ollama / LM Studio URLs on other ports become added servers.
enum AISettingsMigration {
    struct Result: Equatable {
        var choices: [String: FeatureSetting] = [:]
        var customServers: [CustomServer] = []
        var localModels: [String: String] = [:]
    }

    /// `old`: the pre-E1 UserDefaults strings (chatProvider, ollamaServerURL, lmstudioServerURL,
    /// ollamaChatModel, lmstudioChatModel, openAIChatModel, googleChatModel).
    static func migrate(_ old: [String: String],
                        makeID: () -> String = CustomServer.newID) -> Result {
        var r = Result()
        var serverFor: [String: String] = [:]   // provider rawValue → custom server ID
        for (key, provider) in [("ollamaServerURL", AIProviderID.ollama), ("lmstudioServerURL", .lmstudio)] {
            guard let raw = old[key], !raw.isEmpty else { continue }
            let url = AIURL.normalise(raw)
            let defaultURL = AICatalog.info(provider).baseURL!
            guard url != defaultURL, url != defaultURL.replacingOccurrences(of: "127.0.0.1", with: "localhost") else { continue }
            let server = CustomServer(id: makeID(), name: AICatalog.info(provider).name, baseURL: url)
            r.customServers.append(server)
            serverFor[provider.rawValue] = server.id
        }
        for (key, provider) in [("ollamaChatModel", "ollama"), ("lmstudioChatModel", "lmstudio")] {
            if let model = old[key], !model.isEmpty { r.localModels[serverFor[provider] ?? provider] = model }
        }
        guard let raw = old["chatProvider"], raw != AIProviderID.anthropic.rawValue,
              let provider = AIProviderID(rawValue: raw) else { return r }
        let serverID = serverFor[raw]
        let model = switch provider {
        case .openai: old["openAIChatModel"] ?? AICatalog.info(.openai).defaultModel!
        // Pre-E1 stored a local or Google model only when it wasn't the default, so a missing one is a deliberate
        // choice of the old default (ChatProvider.defaultModel): never turn it into Auto, which could use the cloud.
        case .google: old["googleChatModel"] ?? "gemini-2.0-flash"
        case .ollama: r.localModels[serverID ?? raw] ?? "llama3.2"
        case .lmstudio: r.localModels[serverID ?? raw] ?? "local-model"
        default: r.localModels[serverID ?? raw] ?? ""
        }
        if !model.isEmpty {
            r.choices[AIFeature.chat.rawValue] = .explicit(ModelRef(provider: serverID == nil ? provider : .custom,
                                                                    model: model, serverID: serverID))
        }
        return r
    }
}

extension ProviderFactory: RedactsSecrets {
    var redactedSummary: String {
        "ProviderFactory(keys: \(keys.keys.map(\.rawValue).sorted()), servers: \(servers.keys.sorted()), "
            + "override: \(cloudOverride ?? "none"), apple: \(apple != nil))"
    }
}

extension ProviderFactory.ServerAddress: RedactsSecrets {
    var redactedSummary: String { "ServerAddress(\(baseURL), key: \(Self.keyMark(key)))" }
}
