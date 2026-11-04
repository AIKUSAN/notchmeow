import Foundation

// MARK: - Typed error for local model calls

enum LocalChatError: Error {
    /// The server is not reachable (wrong URL, not running, network error).
    case serverUnreachable(String)
    /// The model was requested but is not installed on the server.
    case modelNotFound(String)
    /// The server replied with an error message.
    case serverError(String)

    var localizedDescription: String {
        switch self {
        case .serverUnreachable(let url): return "Cannot reach \(url). Is the server running?"
        case .modelNotFound(let model):   return "Model '\(model)' is not installed."
        case .serverError(let msg):       return msg
        }
    }
}

// MARK: - Local model helpers

/// The pre-E1 local-model API, now a thin layer over the AI core (`AI/Core/`): the chat goes
/// through `ModelRouter` and `OpenAICompatibleProvider`. Kept so `tests/ChatParsingTests.swift`
/// still runs unchanged.
enum LocalChat {

    /// Removes trailing slashes and common documentation sub-paths (/api, /v1).
    static func normaliseURL(_ raw: String) -> String { AIURL.normalise(raw) }

    /// Parses `delta.content` from one OpenAI-SSE event line.
    /// Returns nil for non-data lines, `[DONE]`, missing or null content.
    static func parseSSEDelta(_ line: String) -> String? {
        var parser = OpenAIChatStreamParser()
        for case .text(let t) in parser.consume(line: line) { return t }
        return nil
    }

    /// Removes completed `<think>…</think>` blocks (reasoning models like DeepSeek-R1).
    static func filterThinkingBlocks(_ text: String) -> String {
        ThinkFilter.strip(text).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// For streaming: removes closed think blocks AND hides content inside an
    /// open (unclosed) `<think>` block that hasn't received its closing tag yet.
    static func progressiveFilter(_ text: String) -> String { ThinkFilter.visible(text) }

    /// Fetches models, returning `.success([])` when the server responds but has no chat models,
    /// vs `.failure(.serverUnreachable)` when the server is not reachable.
    static func fetchModelsResult(baseURL: String) async -> Result<[(id: String, label: String)], LocalChatError> {
        do {
            let models = try await OpenAICompatibleProvider.make(.ollama, baseURL: baseURL).listModels()
            return .success(models.map { (id: $0.id, label: $0.id) })
        } catch {
            return .failure(.serverUnreachable(baseURL))
        }
    }

    static func fetchModels(baseURL: String) async -> [(id: String, label: String)] {
        if case .success(let models) = await fetchModelsResult(baseURL: baseURL) { return models }
        return []
    }

    /// Streams a reply from a local OpenAI-compatible server. `onToken` gets the visible text
    /// (think blocks hidden) on the main actor; the result has think blocks removed.
    static func streamChat(
        baseURL: String,
        model: String,
        messages: [[String: Any]],
        onToken: @MainActor @escaping (String) -> Void
    ) async throws -> String {
        let turns: [ChatRequest.Message] = messages.compactMap { m in
            guard let role = (m["role"] as? String).flatMap(ChatRequest.Role.init(rawValue:)),
                  let content = m["content"] as? String else { return nil }
            return ChatRequest.Message(role: role, parts: [.text(content)])
        }
        let request = ChatRequest(model: model, system: "", messages: turns)
        var acc = ReplyAccumulator(stripsThinkBlocks: true)
        var lastUpdate = Date.distantPast
        do {
            for try await chunk in OpenAICompatibleProvider.make(.ollama, baseURL: baseURL).stream(request) {
                acc.add(chunk)
                if case .text = chunk, Date().timeIntervalSince(lastUpdate) >= 1.0 / 15.0 {
                    lastUpdate = Date()
                    let visible = acc.visibleText
                    await MainActor.run { onToken(visible) }
                }
            }
        } catch let e as AIError {
            switch e.kind {
            case .badRequest where e.status == 404: throw LocalChatError.modelNotFound(model)
            case .unreachable, .offline, .timeout, .interrupted: throw LocalChatError.serverUnreachable(baseURL)
            default: throw LocalChatError.serverError(e.message ?? "HTTP \(e.status ?? 0)")
            }
        }
        let visible = acc.visibleText
        await MainActor.run { onToken(visible) }
        return filterThinkingBlocks(acc.text)
    }
}
