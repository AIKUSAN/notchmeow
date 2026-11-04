import Foundation

/// Google's OpenAI-compatible endpoint, Ollama, LM Studio, llama.cpp, Jan and servers the user adds.
/// Sends `max_tokens` (not `max_completion_tokens`) and never `tool_choice`: Ollama ignores both.
struct OpenAICompatibleProvider: ModelProvider {
    let id: AIProviderID
    let displayName: String
    let placement: AIPlacement
    /// Without a trailing slash, e.g. `http://127.0.0.1:11434`.
    let baseURL: String
    var chatPath = "/v1/chat/completions"
    var modelsPath = "/v1/models"
    var apiKey: String? = nil
    var session: URLSession = .shared
    /// nil: `.cloud` or `.local` by placement. Tests shorten them.
    var deadlines: StreamDeadlines? = nil

    /// The catalog's paths for `provider` at `baseURL` (a cloud override keeps the `/v1/...` paths).
    static func make(_ provider: AIProviderID, baseURL: String, name: String? = nil, placement: AIPlacement? = nil,
                     apiKey: String? = nil, session: URLSession = .shared) -> OpenAICompatibleProvider {
        let info = AICatalog.info(provider)
        let usesCatalogBase = baseURL == info.baseURL
        return OpenAICompatibleProvider(
            id: provider, displayName: name ?? info.name,
            placement: placement ?? (provider.isCloud ? .cloud : AICatalog.placement(forHost: URL(string: baseURL)?.host)),
            baseURL: baseURL,
            chatPath: usesCatalogBase ? (info.chatPath ?? "/v1/chat/completions") : "/v1/chat/completions",
            modelsPath: usesCatalogBase ? (info.modelsPath ?? "/v1/models") : "/v1/models",
            apiKey: apiKey, session: session)
    }

    private var authorization: String { "Bearer \(apiKey ?? "ollama")" }

    func listModels() async throws -> [ModelInfo] {
        guard let url = URL(string: baseURL + modelsPath) else { throw AIError(kind: .badRequest) }
        var req = URLRequest(url: url, timeoutInterval: placement == .cloud ? AICatalog.Timeouts.connectCloud
                                                                             : AICatalog.Timeouts.connectLocal)
        req.setValue(authorization, forHTTPHeaderField: "Authorization")
        let json = try await HTTPStream.json(req, session: session)
        let ids = ((json as? [String: Any])?["data"] as? [[String: Any]] ?? []).compactMap { $0["id"] as? String }
        // Gemini models read images; local models are text-only until `modelDetails` says otherwise.
        let vision: Set<AICapability> = id == .google ? [.vision] : []
        return AICatalog.filterModels(ids, for: id).map { ModelInfo(id: $0, capabilities: vision) }
    }

    /// Capabilities and context from the server's native API, when it has one (Ollama, LM Studio).
    func modelDetails(_ model: String) async -> ModelInfo? {
        switch id {
        case .ollama:
            guard let url = URL(string: baseURL + "/api/show") else { return nil }
            let req = HTTPStream.post(url, body: ["model": model], headers: [:], timeout: AICatalog.Timeouts.connectLocal)
            guard let json = try? await HTTPStream.json(req, session: session) as? [String: Any] else { return nil }
            let caps = Set((json["capabilities"] as? [String] ?? []).compactMap { c -> AICapability? in
                c == "vision" ? .vision : (c == "tools" ? .tools : nil)
            })
            // `num_ctx` is what it runs at (a line of `parameters`); `<arch>.context_length` is only the trained maximum.
            var numCtx: Int?
            for line in (json["parameters"] as? String ?? "").split(separator: "\n") where numCtx == nil {
                let words = line.split(whereSeparator: \.isWhitespace)
                if words.count > 1, words[0] == "num_ctx" { numCtx = Int(words[1]) }
            }
            let info = json["model_info"] as? [String: Any]
            let trained = (info?["general.architecture"] as? String).flatMap { info?["\($0).context_length"] as? Int }
            return ModelInfo(id: model, contextTokens: Self.context(runtime: numCtx, trained: trained), capabilities: caps)
        case .lmstudio:
            guard let url = URL(string: baseURL + "/api/v0/models"),
                  let json = try? await HTTPStream.json(URLRequest(url: url, timeoutInterval: AICatalog.Timeouts.connectLocal),
                                                        session: session) as? [String: Any],
                  let row = (json["data"] as? [[String: Any]])?.first(where: { $0["id"] as? String == model })
            else { return nil }
            return ModelInfo(id: model,
                             contextTokens: Self.context(runtime: row["loaded_context_length"] as? Int,
                                                         trained: row["max_context_length"] as? Int),
                             capabilities: row["type"] as? String == "vlm" ? [.vision] : [])
        default:
            return nil
        }
    }

    /// A server runs a model at the context it is loaded with, not the one it was trained for: the runtime value
    /// when there is one, else the trained maximum capped at the default; 0 or less is no value at all. The same
    /// rule as `context_tokens` in windows/src-tauri/src/ai/discovery.rs.
    static func context(runtime: Int?, trained: Int?) -> Int? {
        func positive(_ v: Int?) -> Int? { v.flatMap { $0 > 0 ? $0 : nil } }
        return positive(runtime) ?? positive(trained).map { min($0, AICatalog.Limits.defaultLocalContextTokens) }
    }

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
        guard let url = URL(string: baseURL + chatPath) else {
            return AsyncThrowingStream { $0.finish(throwing: AIError(kind: .badRequest)) }
        }
        AILog.record(.request(id, model: request.model, placement: placement))
        let req = HTTPStream.post(url, body: Self.body(for: request), headers: ["Authorization": authorization],
                                  timeout: HTTPStream.idleTimeout)
        guard placement != .cloud else {
            return HTTPStream.run(req, parser: OpenAIChatStreamParser(), provider: id,
                                  deadlines: deadlines ?? .cloud, session: session)
        }
        // Local and network servers: a 5 s reachability check first (a sleeping LAN host would
        // otherwise hold the chat for the whole first-token wait).
        let preflight = URLRequest(url: URL(string: baseURL + modelsPath)!, timeoutInterval: AICatalog.Timeouts.connectLocal)
        let session = self.session, provider = id, deadlines = self.deadlines ?? .local
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    _ = try await HTTPStream.json(preflight, session: session)
                } catch let e as AIError where e.status != nil {
                    // It answered (even with an error page): reachable.
                } catch {
                    let kind = (error as? AIError)?.kind ?? .unreachable
                    AILog.record(.failure(provider, kind: kind, status: nil, code: nil, requestID: nil))
                    continuation.finish(throwing: AIError(kind: kind))
                    return
                }
                do {
                    for try await chunk in HTTPStream.run(req, parser: OpenAIChatStreamParser(), provider: provider,
                                                          deadlines: deadlines, session: session) {
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Ollama loads a model when it gets an empty generate request.
    func prewarm(model: String) async {
        guard id == .ollama, let url = URL(string: baseURL + "/api/generate") else { return }
        let req = HTTPStream.post(url, body: ["model": model], headers: [:], timeout: AICatalog.Timeouts.connectLocal)
        _ = try? await session.data(for: req)
    }

    /// Chat-completions body. Images go as `image_url` data URLs; everything else is text.
    static func body(for r: ChatRequest) -> [String: Any] {
        var messages: [[String: Any]] = [["role": "system", "content": r.system]]
        for m in r.messages {
            let hasImage = m.parts.contains { if case .image = $0 { return true } else { return false } }
            if hasImage {
                messages.append(["role": m.role.rawValue, "content": m.parts.map { part -> [String: Any] in
                    switch part {
                    case .image(let mime, let data):
                        return ["type": "image_url",
                                "image_url": ["url": "data:\(mime);base64,\(data.base64EncodedString())"]]
                    default:
                        return ["type": "text", "text": plainText(part)]
                    }
                }])
            } else {
                messages.append(["role": m.role.rawValue, "content": m.parts.map(plainText).joined(separator: "\n\n")])
            }
        }
        var body: [String: Any] = ["model": r.model, "messages": messages, "stream": true, "max_tokens": r.maxTokens]
        if !r.tools.isEmpty {
            body["tools"] = r.tools.map { tool -> [String: Any] in
                ["type": "function", "function": ["name": tool.name, "description": tool.description,
                                                  "parameters": jsonObject(tool.parametersJSON)]]
            }
        }
        if let format = r.responseFormat {
            body["response_format"] = ["type": "json_schema",
                                       "json_schema": ["name": format.name, "schema": jsonObject(format.schemaJSON), "strict": true]]
        }
        return body
    }

    static func plainText(_ part: ChatRequest.Part) -> String {
        switch part {
        case .text(let t): t
        case .fileText(let name, let text): "File: \(name)\n\n\(text)"
        case .pdf(let name, _): "File: \(name)"
        case .image: ""
        }
    }

    static func jsonObject(_ data: Data) -> Any {
        (try? JSONSerialization.jsonObject(with: data)) ?? [String: Any]()
    }
}

extension OpenAICompatibleProvider: RedactsSecrets {
    var redactedSummary: String { "OpenAICompatibleProvider(\(id.rawValue), \(baseURL), key: \(Self.keyMark(apiKey)))" }
}
