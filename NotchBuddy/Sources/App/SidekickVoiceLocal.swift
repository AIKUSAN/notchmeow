import Foundation

// The sidekick's local voice, the part that asks a model: ONE short request to a model that runs on this computer, and nothing else. Which model: only one whose placement is `local` (a server on
// 127.0.0.1, ::1 or localhost, and Apple on-device), picked by the router's own local choice (the last used, else the first ready, else Apple), never by a feature's Auto choice, which could pick a
// cloud model. There is no `AIFeature.cats`. It is a one-shot request, not a conversation: nothing is stored, and the chat's history is untouched. It returns nil (and the template stands) when there
// is no local model, on any error, after `SidekickVoice.timeoutMs`, or when the sentence fails the sanity check. It takes its provider from outside, so a test hands it fakes that record every
// request. Compiled with the AI core only (no AppState).

enum SidekickVoiceLocal {
    /// The model the voice may use among those the app found. A candidate that is not local is never considered, whatever the router would do with it.
    static func choice(localReady: [LocalCandidate], lastUsedLocal: ModelRef?, appleReady: Bool) -> LocalCandidate? {
        let local = localReady.filter { $0.placement == .local }
        return ModelRouter.localChoice(RouteInput(setting: .auto, keys: [], online: false, localReady: local, lastUsedLocal: lastUsedLocal, appleReady: appleReady))
    }

    /// The request the model gets: the system line and the one prompt, with the local reply cap.
    static func request(model: String, prompt: String) -> ChatRequest {
        ChatRequest(model: model, system: SidekickVoice.system, messages: [.init(role: .user, parts: [.text(prompt)])], maxTokens: 160)
    }

    /// A nicer sentence for the template `lines` made from `facts`, or nil. `candidate` is `choice(...)`'s answer.
    static func nicerLine(lines: [String], facts: [SKFacts], candidate: LocalCandidate?, provider: @Sendable (ChatTarget) -> any ModelProvider, timeoutMs: Double = SidekickVoice.timeoutMs) async -> String? {
        guard let c = candidate, c.placement == .local, let prompt = SidekickVoice.prompt(lines: lines) else { return nil }
        let target = ChatTarget(provider: c.provider, model: c.model, placement: .local, serverID: c.serverID)
        let model = provider(target)
        guard model.placement == .local else { return nil }
        let stream = model.stream(request(model: c.model, prompt: prompt))
        let text: String? = await withTaskGroup(of: String?.self) { group in
            group.addTask {
                var acc = ReplyAccumulator(stripsThinkBlocks: target.stripsThinkBlocks)
                do { for try await chunk in stream { acc.add(chunk) } } catch { return nil }
                return acc.error == nil ? acc.visibleText : nil
            }
            group.addTask {
                try? await Task.sleep(nanoseconds: UInt64(max(0, timeoutMs) * 1_000_000))
                return nil
            }
            let first = await group.next() ?? nil
            group.cancelAll()
            return first
        }
        guard let text else { return nil }
        let line = text.trimmingCharacters(in: .whitespacesAndNewlines)
        return SidekickVoice.accept(line, facts: facts.map(\.json)) ? line : nil
    }
}
