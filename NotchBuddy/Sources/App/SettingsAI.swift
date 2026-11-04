import Foundation

// The AI rows of Settings → AI and chat (the restyle spec's Your AI, Keys and Local models): which rows show and in what order, their words and chips, what Make main does, and which
// row is the chat's main choice. Pure Foundation on the AI core (AI/Core). The Claude Code state is this file's own `ClaudeState`, so the App Store build, which has no Claude Code
// engine, compiles this file too: the window maps ClaudeCodeStatus.State to it inside its own `#if !APPSTORE`. Tests: tests/SettingsAITests.swift (scripts/test-settings-ai.sh).

enum SettingsAI {
    enum Row: Hashable, Sendable { case claudePlan, openAIPlan, key(AIProviderID), server(String), apple }

    /// ClaudeCodeStatus.State's cases, in every build.
    enum ClaudeState: Equatable, Sendable { case notInstalled, tooOld, signedOut, signedIn, unknown }

    struct Server: Equatable, Sendable {
        var id: String
        var provider: AIProviderID
        var name: String
        var network: Bool
        var models: [String]
    }

    struct Input: Equatable, Sendable {
        var githubBuild: Bool
        var claudeState: ClaudeState
        var claudeVersion: String?
        var claudeSignIn: String
        var claudeEnabled: Bool
        var claudeModel: String
        var keys: Set<AIProviderID>
        var cloudModel: [AIProviderID: String]
        var servers: [Server]
        var memory: [String: String]
        var appleReady: Bool
        var codexState: ClaudeState = .notInstalled
    }

    enum MakeMain: Equatable, Sendable {
        case set(FeatureSetting)
        case menu([ModelRef])
        case unavailable(String)
    }

    static let planLine = "Runs your own installed app, signed in by you. NotchMeow never sees your login."
    static let coming = "Coming with the new chat"
    /// The reason Make main gives for a coming row, with its full stop. Windows and Linux still show these two; windows/scripts/settings-tests/drift.test.mjs pins only `coming`, not this reason.
    static let comingReason = "Coming with the new chat."
    static let codexSignIn = "Open your terminal and run `codex login`. NotchMeow opens nothing."
    static let keyProviders: [AIProviderID] = [.anthropic, .google, .openai]

    /// The plan rows on GitHub builds only; then the keys; then each server that has models; then Apple when it is ready.
    static func rows(_ i: Input) -> [Row] {
        var out: [Row] = []
        if i.githubBuild { out += [.claudePlan, .openAIPlan] }
        out += keyProviders.map { Row.key($0) }
        out += i.servers.filter { !$0.models.isEmpty }.map { Row.server($0.id) }
        if i.appleReady { out.append(.apple) }
        return out
    }

    static func title(_ r: Row, _ i: Input) -> String {
        switch r {
        case .claudePlan: return "Use my Claude plan"
        case .openAIPlan: return "Use my OpenAI plan"
        case .key(let p): return keyTitle(p)
        case .server(let id): return i.servers.first(where: { $0.id == id })?.name ?? ""
        case .apple: return "Apple on-device"
        }
    }

    private static func keyTitle(_ p: AIProviderID) -> String {
        switch p {
        case .anthropic: return "Anthropic API key"
        case .google: return "Google AI API key"
        case .openai: return "OpenAI API key"
        default: return "API key"
        }
    }

    static func line(_ r: Row, _ i: Input) -> String {
        switch r {
        case .claudePlan, .openAIPlan: return planLine
        case .key: return "Your own key, saved on the Keys tab."
        case .server(let id):
            let network = i.servers.first(where: { $0.id == id })?.network ?? false
            return network ? "A model server on your network." : "A model server on this Mac."
        case .apple: return "Apple's model, on this Mac."
        }
    }

    static func chip(_ r: Row, _ i: Input) -> String {
        switch r {
        case .claudePlan: return claudeChip(i)
        case .openAIPlan: return codexChip(i)
        case .key(let p): return SettingsStatus.keyChip(saved: i.keys.contains(p))
        case .server(let id):
            let models = i.servers.first(where: { $0.id == id })?.models ?? []
            return serverChip(.running(models.map { ModelInfo(id: $0) }))
        case .apple: return "Ready"
        }
    }

    private static func claudeChip(_ i: Input) -> String {
        switch i.claudeState {
        case .signedIn: return i.claudeEnabled ? "Ready" : "Off"
        case .signedOut: return "Not signed in"
        case .notInstalled: return "Not installed"
        case .tooOld: return "Needs update"
        case .unknown: return "Not ready"
        }
    }

    /// The OpenAI plan's chip: Codex's state, word for word from the rules' table (no enabled switch, unlike the Claude plan).
    private static func codexChip(_ i: Input) -> String {
        switch i.codexState {
        case .signedIn: return "Ready"
        case .signedOut: return "Not signed in"
        case .notInstalled: return "Not installed"
        case .tooOld: return "Needs update"
        case .unknown: return "Not ready"
        }
    }

    /// What the row's "Make main" does: set the chat's choice, offer a menu (a server with several models), or say why it cannot.
    static func makeMain(_ r: Row, _ i: Input) -> MakeMain {
        switch r {
        case .claudePlan:
            guard i.claudeState == .signedIn, i.claudeEnabled else { return .unavailable("Connect your Claude plan first.") }
            return .set(.explicit(ModelRef(provider: .claudeCode, model: i.claudeModel)))
        case .openAIPlan:
            switch i.codexState {
            case .signedIn: return .set(.explicit(ModelRef(provider: .codexPlan, model: "")))
            case .signedOut: return .unavailable(codexSignIn)
            case .notInstalled: return .unavailable("Install OpenAI's Codex CLI first.")
            case .tooOld: return .unavailable("This version of Codex is too old for NotchMeow.")
            case .unknown: return .unavailable("Codex didn't answer. Open this tab again to check.")
            }
        case .key(let p):
            guard i.keys.contains(p) else { return .unavailable("Add a key on the Keys tab first.") }
            guard let model = i.cloudModel[p], !model.isEmpty else { return .unavailable("Pick a model for it in the chat first.") }
            return .set(.explicit(ModelRef(provider: p, model: model)))
        case .server(let id):
            // A server with no model yet cannot answer: its row says so, and the Local models tab shows the same words under it.
            guard let server = i.servers.first(where: { $0.id == id }), !server.models.isEmpty else {
                return .unavailable("Start the server and load a model first.")
            }
            if server.models.count == 1 {
                return .set(.explicit(ModelRef(provider: server.provider, model: server.models[0], serverID: server.id)))
            }
            // The model used last comes first; the rest keep the server's order.
            var ordered = server.models
            if let remembered = i.memory[id], let at = ordered.firstIndex(of: remembered) {
                ordered.remove(at: at)
                ordered.insert(remembered, at: 0)
            }
            return .menu(ordered.map { ModelRef(provider: server.provider, model: $0, serverID: server.id) })
        case .apple:
            return .set(.explicit(ModelRef(provider: .apple, model: "system")))
        }
    }

    /// The line under a row. A key row with no key has none: its chip and its Add a key button say it.
    static func helpLine(_ r: Row, _ i: Input) -> String? {
        if case .key(let p) = r, !i.keys.contains(p) { return nil }
        return line(r, i)
    }

    /// Stop using the Claude plan: a choice that named it goes back to Auto, so no row is Off and main at once. Any other choice stays.
    static func afterStoppingClaude(_ setting: FeatureSetting) -> FeatureSetting {
        guard case .explicit(let ref) = setting, ref.provider == .claudeCode else { return setting }
        return .auto
    }

    /// Why a row cannot be made main, as help text under it. None when the chip already says the same (a reason that only repeats the chip
    /// and its full stop) or the row's button already says it (a key with no key).
    static func reasonLine(_ r: Row, _ i: Input) -> String? {
        if case .key(let p) = r, !i.keys.contains(p) { return nil }
        guard case .unavailable(let reason) = makeMain(r, i) else { return nil }
        if reason == chip(r, i) + "." { return nil }
        return reason
    }

    /// Only an explicit Chat choice is main: Auto has no main row (Which one answers already shows what it resolves to).
    static func isMain(_ r: Row, chat: FeatureSetting) -> Bool {
        guard case .explicit(let ref) = chat else { return false }
        switch r {
        case .claudePlan: return ref.provider == .claudeCode
        case .openAIPlan: return ref.provider == .codexPlan
        case .key(let p): return ref.provider == p
        case .server(let id): return (ref.serverID ?? ref.provider.rawValue) == id && !ref.provider.isCloud && ref.provider != .apple
        case .apple: return ref.provider == .apple
        }
    }

    static func serverChip(_ s: ServerStatus) -> String {
        switch s {
        case .running(let models):
            if models.isEmpty { return "Running, no models yet" }
            return models.count == 1 ? "Running, 1 model" : "Running, \(models.count) models"
        case .off: return "Server off"
        case .notInstalled: return "Not installed"
        case .outdated: return "Update needed"
        }
    }

    /// Where to get a local server (today's `LocalServerRow.getURLs`); nil for the cloud providers.
    static func getLink(_ p: AIProviderID) -> String? {
        switch p {
        case .ollama: return "https://ollama.com/download"
        case .lmstudio: return "https://lmstudio.ai"
        case .jan: return "https://jan.ai"
        case .llamacpp: return "https://github.com/ggml-org/llama.cpp"
        default: return nil
        }
    }
}
