import Foundation

/// OpenAI through the Responses API: streaming, hosted web search, native PDFs and images.
/// Every request sends `store: false` and the whole conversation; never `previous_response_id`.
struct OpenAIProvider: ModelProvider {
    let id = AIProviderID.openai
    let displayName = "OpenAI"
    let placement = AIPlacement.cloud
    let apiKey: String
    var baseURL = AICatalog.info(.openai).baseURL!
    var session: URLSession = .shared
    var deadlines: StreamDeadlines = .cloud

    private var authorization: String { "Bearer \(apiKey)" }

    /// Chat models, newest first (`/v1/models` has no capability fields, so IDs are filtered).
    func listModels() async throws -> [ModelInfo] {
        guard let url = URL(string: baseURL + "/v1/models") else { throw AIError(kind: .badRequest) }
        var req = URLRequest(url: url, timeoutInterval: AICatalog.Timeouts.connectCloud)
        req.setValue(authorization, forHTTPHeaderField: "Authorization")
        let rows = (try await HTTPStream.json(req, session: session) as? [String: Any])?["data"] as? [[String: Any]] ?? []
        let sorted = rows.sorted { ($0["created"] as? Int ?? 0) > ($1["created"] as? Int ?? 0) }
        return AICatalog.filterModels(sorted.compactMap { $0["id"] as? String }, for: .openai)
            .map { ModelInfo(id: $0, capabilities: [.vision, .tools, .json]) }
    }

    func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
        AILog.record(.request(id, model: request.model, placement: placement))
        let req = HTTPStream.post(URL(string: baseURL + "/v1/responses")!, body: Self.body(for: request),
                                  headers: ["Authorization": authorization], timeout: HTTPStream.idleTimeout)
        return HTTPStream.run(req, parser: OpenAIResponsesStreamParser(), provider: id, deadlines: deadlines, session: session)
    }

    static func body(for r: ChatRequest) -> [String: Any] {
        let input: [[String: Any]] = r.messages.map { m in
            if m.role == .assistant {
                return ["role": "assistant", "content": m.parts.map(OpenAICompatibleProvider.plainText).joined(separator: "\n\n")]
            }
            return ["role": "user", "content": m.parts.map(item)]
        }
        var body: [String: Any] = ["model": r.model, "instructions": r.system, "input": input, "stream": true,
                                   "store": false, "max_output_tokens": r.maxTokens]
        var tools: [[String: Any]] = []
        if r.webSearch { tools.append(["type": AICatalog.WebSearch.openAIType]) }
        tools += r.tools.map {
            ["type": "function", "name": $0.name, "description": $0.description,
             "parameters": OpenAICompatibleProvider.jsonObject($0.parametersJSON), "strict": false]
        }
        if !tools.isEmpty { body["tools"] = tools }
        if let format = r.responseFormat {
            body["text"] = ["format": ["type": "json_schema", "name": format.name,
                                       "schema": OpenAICompatibleProvider.jsonObject(format.schemaJSON), "strict": true]]
        }
        return body
    }

    private static func item(_ part: ChatRequest.Part) -> [String: Any] {
        switch part {
        case .text(let t):
            return ["type": "input_text", "text": t]
        case .fileText(let name, let text):
            return ["type": "input_text", "text": "File: \(name)\n\n\(text)"]
        case .image(let mime, let data):
            return ["type": "input_image", "image_url": "data:\(mime);base64,\(data.base64EncodedString())", "detail": "auto"]
        case .pdf(let name, let data):
            return ["type": "input_file", "filename": name,
                    "file_data": "data:application/pdf;base64,\(data.base64EncodedString())"]
        }
    }
}

extension OpenAIProvider: RedactsSecrets {
    var redactedSummary: String { "OpenAIProvider(\(baseURL), key: \(Self.keyMark(apiKey)))" }
}
