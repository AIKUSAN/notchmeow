import Foundation

// MARK: - Provider IDs and placements (tests/fixtures/ai/providers.json)

/// Provider IDs shared with the Windows/Linux app. Never rename: they are stored in
/// UserDefaults and match `tests/fixtures/ai/providers.json`.
enum AIProviderID: String, CaseIterable, Codable, Sendable {
    case anthropic, openai, google, ollama, lmstudio, llamacpp, jan, apple, custom, claudeCode, codexPlan

    /// `claudeCode` runs on Anthropic's servers through the user's own Claude Code, so it counts as cloud.
    /// `codexPlan` is the same kind of thing for OpenAI: the user's own Codex, run as a process.
    var isCloud: Bool {
        self == .anthropic || self == .openai || self == .google || self == .claudeCode || self == .codexPlan
    }
}

/// Claude Code's own model aliases (its `--model` values): plain names, like a catalog row. The engine that uses them
/// is compiled out of the App Store build; the model picker and Settings read the list in both.
enum ClaudeCodeModel: String, CaseIterable, Sendable, Codable {
    case sonnet, opus, haiku

    var label: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }
}

/// Where an answer was computed. Drives the reply caption.
enum AIPlacement: String, Codable, Sendable {
    case local, network, cloud
}

/// The wire format a provider speaks.
enum AIProviderAPI: String, Sendable {
    case anthropic
    case openaiResponses = "openai-responses"
    case openaiChat = "openai-chat"
    case apple
    case claudeCode = "claude-code"
    case codex = "codex"
}

/// One row of the provider catalog.
struct AIProviderInfo: Sendable {
    let id: AIProviderID
    let name: String
    /// "local", "cloud", or "computed" (a custom server: local on localhost, network otherwise).
    let placement: String
    let api: AIProviderAPI
    var baseURL: String? = nil
    var chatPath: String? = nil
    var modelsPath: String? = nil
    var port: Int? = nil
    var probePath: String? = nil
    var keychainKey: String? = nil
    var defaultModel: String? = nil
}

// MARK: - Catalog

/// Built-in copy of `tests/fixtures/ai/providers.json`. `scripts/test-ai-router.sh`
/// fails if the two drift apart.
enum AICatalog {
    static let providers: [AIProviderInfo] = [
        .init(id: .anthropic, name: "Anthropic", placement: "cloud", api: .anthropic,
              baseURL: "https://api.anthropic.com", chatPath: "/v1/messages", modelsPath: "/v1/models",
              keychainKey: "anthropic-api-key", defaultModel: "claude-sonnet-5-5"),
        .init(id: .openai, name: "OpenAI", placement: "cloud", api: .openaiResponses,
              baseURL: "https://api.openai.com", chatPath: "/v1/responses", modelsPath: "/v1/models",
              keychainKey: "openai-api-key", defaultModel: "gpt-6.1-sol"),
        .init(id: .google, name: "Google", placement: "cloud", api: .openaiChat,
              baseURL: "https://generativelanguage.googleapis.com/v1beta/openai", chatPath: "/chat/completions",
              modelsPath: "/models", keychainKey: "google-api-key", defaultModel: nil),
        .init(id: .ollama, name: "Ollama", placement: "local", api: .openaiChat,
              baseURL: "http://127.0.0.1:11434", chatPath: "/v1/chat/completions", modelsPath: "/v1/models",
              port: 11434, probePath: "/api/version"),
        .init(id: .lmstudio, name: "LM Studio", placement: "local", api: .openaiChat,
              baseURL: "http://127.0.0.1:1234", chatPath: "/v1/chat/completions", modelsPath: "/v1/models",
              port: 1234, probePath: "/v1/models"),
        .init(id: .llamacpp, name: "llama.cpp", placement: "local", api: .openaiChat,
              baseURL: "http://127.0.0.1:8080", chatPath: "/v1/chat/completions", modelsPath: "/v1/models",
              port: 8080, probePath: "/health"),
        .init(id: .jan, name: "Jan", placement: "local", api: .openaiChat,
              baseURL: "http://127.0.0.1:1337", chatPath: "/v1/chat/completions", modelsPath: "/v1/models",
              port: 1337, probePath: "/v1/models"),
        .init(id: .apple, name: "Apple on-device", placement: "local", api: .apple, defaultModel: "system"),
        .init(id: .custom, name: "Local server", placement: "computed", api: .openaiChat,
              chatPath: "/v1/chat/completions", modelsPath: "/v1/models", keychainKey: "custom-server-key"),
        .init(id: .claudeCode, name: "Claude plan", placement: "cloud", api: .claudeCode, defaultModel: "sonnet"),
        .init(id: .codexPlan, name: "OpenAI plan", placement: "cloud", api: .codex),
    ]

    static func info(_ id: AIProviderID) -> AIProviderInfo {
        providers.first { $0.id == id }!
    }

    /// Auto's cloud order before the Preferred cloud moves to the front.
    static let cloudOrder: [AIProviderID] = [.anthropic, .openai, .google]

    /// Hosted web-search tools (providers.json `webSearch`), the same on both apps.
    enum WebSearch {
        static let anthropicType = "web_search_20260209"
        /// Older Claude models (IDs starting with a legacy prefix) can't use `anthropicType`.
        static let anthropicLegacyType = "web_search_20250305"
        static let anthropicLegacyModelPrefixes = ["claude-haiku-4", "claude-3"]
        static let anthropicName = "web_search"
        static let anthropicMaxUses = 5
        static let openAIType = "web_search"
    }

    /// The hosted web-search tool type for a Claude model (providers.json `webSearch.anthropic`).
    static func anthropicWebSearchType(model: String) -> String {
        WebSearch.anthropicLegacyModelPrefixes.contains { model.hasPrefix($0) }
            ? WebSearch.anthropicLegacyType : WebSearch.anthropicType
    }

    enum Filters {
        static let localExclude = ["embed", "bge-", "all-minilm", "clip", "rerank"]
        static let googleExclude = ["embed", "imagen", "veo", "aqa", "tts", "audio", "live"]
        static let openAIIncludePrefixes = ["gpt-", "o1", "o3", "o4", "o5"]
        static let openAIExclude = ["embed", "tts", "whisper", "dall-e", "audio", "realtime", "moderat", "codex",
                                    "computer-use", "transcribe", "image", "sora", "babbage", "davinci",
                                    "instruct", "search", "live"]
    }

    /// Seconds (providers.json stores milliseconds).
    enum Timeouts {
        static let probe: TimeInterval = 0.3
        /// Servers the user added: parallel, and slow LAN hosts still count.
        static let probeAdded: TimeInterval = 2
        static let connectLocal: TimeInterval = 5
        static let connectCloud: TimeInterval = 10
        static let firstTokenLocal: TimeInterval = 60
        static let firstTokenCloud: TimeInterval = 30
    }

    enum Limits {
        static let maxFileBytes = 26_214_400
        static let cloudTextCapChars = 204_800
        static let budgetFractionOfContext = 0.5
        static let charsPerToken = 3.5
        static let defaultLocalContextTokens = 4096
    }

    /// Reply length per placement (providers.json `maxOutputTokens`). Cloud models spend reasoning tokens
    /// from the same cap, so they get more room than local and network servers.
    enum OutputTokens {
        static let cloud = 16_000
        static let network = 4096
        static let local = 4096
    }

    /// The `maxTokens` of a request to a provider at this placement. No caller writes a number.
    static func maxOutputTokens(for placement: AIPlacement) -> Int {
        switch placement {
        case .cloud: OutputTokens.cloud
        case .network: OutputTokens.network
        case .local: OutputTokens.local
        }
    }

    /// A custom server is `local` on 127.0.0.1, ::1 or localhost, and `network` otherwise.
    static func placement(forHost host: String?) -> AIPlacement {
        let h = (host ?? "").lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
        return ["127.0.0.1", "::1", "localhost"].contains(h) ? .local : .network
    }

    /// Chat models only, in the order given. Google IDs lose their `models/` prefix.
    static func filterModels(_ ids: [String], for provider: AIProviderID) -> [String] {
        switch provider {
        case .google:
            return ids.map { $0.hasPrefix("models/") ? String($0.dropFirst(7)) : $0 }
                .filter { id in !Filters.googleExclude.contains { id.lowercased().contains($0) } }
        case .openai:
            return ids.filter { id in
                let l = id.lowercased()
                return Filters.openAIIncludePrefixes.contains { l.hasPrefix($0) }
                    && !Filters.openAIExclude.contains { l.contains($0) }
            }
        case .anthropic, .apple, .claudeCode, .codexPlan:
            return ids
        case .ollama, .lmstudio, .llamacpp, .jan, .custom:
            return ids.filter { id in !Filters.localExclude.contains { id.lowercased().contains($0) } }
        }
    }

    /// The model Auto uses for a provider when none is remembered (`docs/AI-PROVIDERS.md`).
    /// Google has no fixed default: the first listed ID containing "flash", else the first.
    static func defaultModel(for provider: AIProviderID, available: [String]) -> String? {
        if let fixed = info(provider).defaultModel { return fixed }
        if provider == .google { return available.first { $0.contains("flash") } ?? available.first }
        return available.first
    }
}
