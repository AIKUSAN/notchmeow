import Foundation

/// Claude through the Messages API, streaming, with server-side web search and native PDFs.
struct AnthropicProvider: ModelProvider {
    let id = AIProviderID.anthropic
    let displayName = "Anthropic"
    let placement = AIPlacement.cloud
    let apiKey: String
    var baseURL = AICatalog.info(.anthropic).baseURL!
    var session: URLSession = .shared
    var deadlines: StreamDeadlines = .cloud

    static let version = "2023-06-01"
    /// The catalog's hosted web search (GA, no beta header). Older Claude models take the legacy type.
    static func webSearchTool(model: String) -> [String: Any] {
        ["type": AICatalog.anthropicWebSearchType(model: model), "name": AICatalog.WebSearch.anthropicName,
         "max_uses": AICatalog.WebSearch.anthropicMaxUses]
    }

    private var headers: [String: String] { ["x-api-key": apiKey, "anthropic-version": Self.version] }

    func listModels() async throws -> [ModelInfo] {
        guard let url = URL(string: baseURL + "/v1/models?limit=100") else { throw AIError(kind: .badRequest) }
        var req = URLRequest(url: url, timeoutInterval: AICatalog.Timeouts.connectCloud)
        headers.forEach { req.setValue($1, forHTTPHeaderField: $0) }
        let json = try await HTTPStream.json(req, session: session) as? [String: Any]
        return (json?["data"] as? [[String: Any]] ?? []).compactMap { row in
            guard let id = row["id"] as? String else { return nil }
            return ModelInfo(id: id, label: row["display_name"] as? String, capabilities: [.vision, .tools, .json])
        }
    }

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
        AILog.record(.request(id, model: request.model, placement: placement))
        let req = HTTPStream.post(URL(string: baseURL + "/v1/messages")!, body: Self.body(for: request), headers: headers,
                                  timeout: HTTPStream.idleTimeout)
        return HTTPStream.run(req, parser: AnthropicStreamParser(), provider: id, deadlines: deadlines, session: session)
    }

    static func body(for r: ChatRequest) -> [String: Any] {
        let messages: [[String: Any]] = r.messages.map { m in
            ["role": m.role.rawValue, "content": m.parts.map(block)]
        }
        var body: [String: Any] = ["model": r.model, "max_tokens": r.maxTokens, "system": r.system,
                                   "messages": messages, "stream": true]
        var tools: [[String: Any]] = []
        // Web search citations can't be combined with structured output.
        if r.webSearch && r.responseFormat == nil { tools.append(webSearchTool(model: r.model)) }
        tools += r.tools.map {
            ["name": $0.name, "description": $0.description,
             "input_schema": OpenAICompatibleProvider.jsonObject($0.parametersJSON)]
        }
        if !tools.isEmpty { body["tools"] = tools }
        if let format = r.responseFormat {
            body["output_config"] = ["format": ["type": "json_schema",
                                                "schema": OpenAICompatibleProvider.jsonObject(format.schemaJSON)]]
        }
        return body
    }

    /// One content block of the Messages API shape; Claude Code takes the same blocks on stdin.
    static func block(_ part: ChatRequest.Part) -> [String: Any] {
        switch part {
        case .text(let t):
            return ["type": "text", "text": t]
        case .fileText(let name, let text):
            return ["type": "text", "text": "File: \(name)\n\n\(text)"]
        case .image(let mime, let data):
            return ["type": "image", "source": ["type": "base64", "media_type": mime, "data": data.base64EncodedString()]]
        case .pdf(_, let data):
            return ["type": "document",
                    "source": ["type": "base64", "media_type": "application/pdf", "data": data.base64EncodedString()]]
        }
    }
}

extension AnthropicProvider: RedactsSecrets {
    var redactedSummary: String { "AnthropicProvider(\(baseURL), key: \(Self.keyMark(apiKey)))" }
}
