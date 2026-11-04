import Foundation

// MARK: - Models

enum AICapability: String, Codable, Sendable, Hashable {
    case tools, vision, json
}

struct ModelInfo: Sendable, Equatable, Codable {
    let id: String
    /// Human name when the provider has one (Anthropic's `display_name`), else nil.
    var label: String? = nil
    var contextTokens: Int? = nil
    var capabilities: Set<AICapability> = []
}

// MARK: - Request

struct ChatRequest: Sendable, Equatable {
    enum Role: String, Sendable, Codable { case user, assistant }

    enum Part: Sendable, Equatable {
        case text(String)
        /// Text taken out of a file (already cut to the model's budget).
        case fileText(name: String, text: String)
        case image(mime: String, data: Data)
        /// A PDF sent as-is (Anthropic `document`, OpenAI `input_file`).
        case pdf(name: String, data: Data)
    }

    struct Message: Sendable, Equatable {
        var role: Role
        var parts: [Part]
    }

    /// A function the model may call. Unused in E; the cats (F) will use it.
    struct Tool: Sendable, Equatable {
        let name: String
        let description: String
        /// JSON Schema object, serialised.
        let parametersJSON: Data
    }

    /// Structured output. Unused in E; F will use it.
    struct ResponseFormat: Sendable, Equatable {
        let name: String
        /// JSON Schema object, serialised.
        let schemaJSON: Data
    }

    var model: String
    var system: String
    var messages: [Message]
    var tools: [Tool] = []
    var responseFormat: ResponseFormat? = nil
    /// Reply length cap. The chat sets it from `AICatalog.maxOutputTokens(for:)`; the default is the local cap.
    var maxTokens: Int = AICatalog.OutputTokens.local
    /// Lets Anthropic and OpenAI use their hosted web search.
    var webSearch: Bool = false
}

// MARK: - Stream

struct Citation: Sendable, Equatable, Hashable, Codable {
    let url: String
    let title: String
}

/// A piece of a tool call. `index` orders calls; `replacesArguments` overwrites instead of appending.
struct ToolCallDelta: Sendable, Equatable {
    let index: Int
    var id: String? = nil
    var name: String? = nil
    var arguments: String = ""
    var replacesArguments: Bool = false
}

/// One tool step Claude Code takes on its own (reading a file, running a command), shown as a row in the chat.
struct ChatStep: Sendable, Equatable, Hashable {
    enum State: String, Sendable { case running, done, failed, stopped }

    let id: String
    var tool: String
    /// Only the fields that say what the step does (command, file_path, path, query, pattern, url), each cut to
    /// 200 Unicode scalars: never a file's content.
    var input: [String: String] = [:]
    var state: State = .running

    /// A step that never finished (Stop, a crash) ends as stopped: no row stays "running". The others are left alone.
    static func endingUnfinished(_ steps: [ChatStep]) -> [ChatStep] {
        steps.map { step in
            var ended = step
            if ended.state == .running { ended.state = .stopped }
            return ended
        }
    }
}

/// What a Claude Code run says about itself in its first event (`system/init`).
struct EngineReport: Sendable, Equatable {
    enum Payer: String, Sendable {
        case plan
        case apiKey = "api_key"
        case unknown
    }

    var sessionID: String
    var model: String
    var paidBy: Payer
    var version: String?
}

enum FinishReason: String, Sendable, Equatable {
    case stop, length, refusal
    case toolCalls = "tool_calls"
}

enum ChatChunk: Sendable, Equatable {
    case text(String)
    case toolCall(ToolCallDelta)
    case citation(Citation)
    /// `replacesText`: the text streamed so far *was* the refusal (Anthropic).
    case refusal(String, replacesText: Bool)
    case finish(FinishReason)
    case error(AIErrorKind)
    /// The model is working (search started, reasoning started) but has no output yet.
    /// Counts as the first token for timeouts; carries nothing to show.
    case activity
    /// A step Claude Code is taking, or has finished (the same `id` updates the same row).
    case step(ChatStep)
    /// What the engine reported about the run it started.
    case engine(EngineReport)
}

// MARK: - Errors

/// Error kinds shared with the Windows/Linux app (E1-0 Global Constraints).
enum AIErrorKind: String, Sendable, Codable, CaseIterable, Equatable {
    case offline, unreachable, timeout, server
    case rateLimited = "rate_limited"
    case overloaded, auth
    case badRequest = "bad_request"
    case billing, refusal, cancelled, interrupted

    /// Auto may retry these once on a local model.
    var isTemporary: Bool {
        switch self {
        case .offline, .unreachable, .timeout, .server, .rateLimited, .overloaded: true
        default: false
        }
    }
}

struct AIError: Error, Sendable, Equatable {
    var kind: AIErrorKind
    var status: Int? = nil
    var retryAfter: Int? = nil
    /// Provider error code or type, e.g. `insufficient_quota`. Safe to log (short, no content).
    var code: String? = nil
    /// Provider message. Shown to the user for `bad_request`; never logged.
    var message: String? = nil
    /// `x-request-id` / `request-id`, logged for support.
    var requestID: String? = nil
    /// When a usage limit resets (the Claude plan's limit), so the chat can say when.
    var resetsAt: Date? = nil
}

// MARK: - Provider

protocol ModelProvider: Sendable {
    var id: AIProviderID { get }
    var displayName: String { get }
    var placement: AIPlacement { get }
    func listModels() async throws -> [ModelInfo]
    func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error>
    /// Loads the model ahead of the first message. No-op for providers that don't need it.
    func prewarm(model: String) async
}

extension ModelProvider {
    func prewarm(model: String) async {}
}
