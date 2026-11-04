import Foundation

// The local voice in the app: which model it would use and the glue to the AI layer. The rules (the sanity check, the one request, the choice of a LOCAL model) are `SidekickVoice` and
// `SidekickVoiceLocal`, tested against fake providers; this file only reads what the app has found (the servers on this computer, Apple on-device) and builds the provider for the one model
// the voice may ask. It never goes through the chat's Auto choice, which could pick a cloud model, and the AI layer gets no feature of its own for it: a model that is not on this
// computer is not considered, and nothing about a recap or a status answer is ever sent to one.

@MainActor
enum SidekickVoiceApp {
    /// The model on this computer the voice would use now: the last used local one, else the first ready one, else Apple on-device; nil when there is none.
    static func candidate() -> LocalCandidate? {
        let app = AppState.shared
        return SidekickVoiceLocal.choice(localReady: AIService.shared.localReady(), lastUsedLocal: app.lastUsedLocal, appleReady: app.appleStatus == .ready)
    }

    /// The line under the Settings switch: "Local · qwen3.5:2b", or nil when no model on this computer was found.
    static func foundLabel() -> String? {
        candidate().map { AIMessages.targetLabel(AIService.shared.target($0)) }
    }

    /// A nicer sentence for the template `lines` (made from `facts`), or nil, in at most six seconds. The request goes to a model on this computer or to none.
    static func nicer(lines: [String], facts: [SKFacts]) async -> String? {
        guard let c = candidate() else { return nil }
        // The voice only ever asks a server on this computer, whose address and key are in `servers`: it holds no cloud key at all, and the Keychain is never read on this path
        // (AIService.factory() would read every cloud key first). The same servers and Apple's provider, built here without `keys`.
        var servers: [String: ProviderFactory.ServerAddress] = [:]
        for s in AppState.shared.localServers { servers[s.serverID] = .init(baseURL: s.baseURL, key: s.apiKey) }
        let factory = ProviderFactory(servers: servers, cloudOverride: AIURL.cloudOverride(), apple: AppleOnDevice.provider(), appleContextTokens: AppleOnDevice.contextTokens())
        return await SidekickVoiceLocal.nicerLine(lines: lines, facts: facts, candidate: c, provider: { factory.make($0) })
    }
}
