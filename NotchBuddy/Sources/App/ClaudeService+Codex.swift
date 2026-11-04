import Foundation

// The OpenAI plan's chat turns (F3a2-mac): the app's side of Codex. The engine is `AI/Core/Codex*.swift`; this file only
// says which turns run Codex and at which level. Wholly excluded from the App Store build, like the rest of the Codex engine.

#if !APPSTORE

extension ClaudeService {
    /// The chat's model choice names the OpenAI plan explicitly. Auto never picks it (`AIService.cloudKeys`), so this is the only way a turn runs Codex.
    func usesCodexByChoice(_ feature: AIFeature) -> Bool {
        if case .explicit(let ref) = AppState.shared.choice(for: feature), ref.provider == .codexPlan { return true }
        return false
    }

    /// What one turn needs to run Codex: the program the last check found, and the level. A quick action (and a quick Explain's first turn) runs at
    /// no tools; a chat turn at Chat only. No model is sent: Codex's own default.
    func codexSetup(quick: Bool) -> CodexSetup {
        CodexSetup(executable: AppState.shared.codexStatus.executable ?? "", level: quick ? .noTools : .chat,
                   model: nil, knownState: AppState.shared.codexStatus.state)
    }
}

#endif
