import Foundation

// What Claude Code's stream-json output means: text, steps, who pays, and how a run failed. Read one line at a time.
// The rules are `parse()` in `tests/fixtures/ai/claude-code/reference.py`; `expected-parse.json` pins them.
//
// The exact JSON of Claude Code's failures is not documented, so this is tolerant on purpose: a line that is not
// JSON, or an event it does not know, is skipped; a run that ends without a result and without a failure it
// recognises is "Claude stopped unexpectedly", never a guess at what went wrong.

#if !APPSTORE

/// Codes on `AIError.code` for Claude Code's failures, on top of the twelve shared error kinds.
enum ClaudeCodeError {
    static let missing = "nm_claude_missing"
    static let signedOut = "nm_signed_out"
    static let planLimit = "nm_plan_limit"
    static let tooOld = "nm_claude_old"
    static let crashed = "nm_claude_crashed"
    static let offline = "nm_claude_offline"
    static let needsGit = "nm_needs_git"
    static let folderMissing = "nm_folder_missing"
    /// No tools: the run started with tools, or showed one before its init, so NotchMeow stopped it.
    static let toolsPresent = "nm_tools_present"
}

struct ClaudeStreamParser {
    /// Only these fields of a tool's input say what the step does. A Write's `content` never gets here.
    static let stepFields = ["command", "file_path", "path", "query", "pattern", "url"]
    static let stepFieldCap = 200

    private(set) var engine: EngineReport?
    /// Everything shown so far, so the failure rules know whether anything was said.
    private(set) var text = ""
    /// True once the run showed tools a level must not have (No tools). The parser then ignores every later line; stopping the process is the run's job, not the parser's.
    private(set) var refusedTools = false

    /// The tools `init` must report, for a level that checks them; nil: no check. `reference.py`'s `expect_tools`.
    private let initTools: [String]?
    private var initVetted = false
    private var needsBreak = false
    private var steps: [String: ChatStep] = [:]
    private var finished = false
    private var resultSeen = false
    private var resultIsError = false
    private var resultSubtype = ""
    private var resultText = ""
    private var assistantError: String?
    /// nil: no rate-limit event that rejected; 0: rejected, no time given; else Unix seconds.
    private var rejectedResetsAt: Int64?
    private var retried = false

    init(initTools: [String]? = nil) {
        self.initTools = initTools
    }

    /// Chunks for one line of stdout.
    mutating func consume(line: String) -> [ChatChunk] {
        if refusedTools { return [] }
        guard let data = line.data(using: .utf8),
              let event = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return [] }
        if initTools != nil, !initVetted, Self.showsSomething(event) {
            refusedTools = true
            return []
        }
        switch event["type"] as? String {
        case "system":
            switch event["subtype"] as? String {
            case "init":
                let report = EngineReport(sessionID: event["session_id"] as? String ?? "",
                                          model: event["model"] as? String ?? "",
                                          paidBy: Self.payer(event["apiKeySource"] as? String),
                                          version: event["claude_code_version"] as? String)
                engine = report
                if let expected = initTools, !initVetted {
                    // `as? [String]` fails on a non-string element, so a malformed list refuses too.
                    guard let tools = event["tools"] as? [String], tools == expected else {
                        refusedTools = true
                        return [.engine(report)]
                    }
                    initVetted = true
                }
                return [.engine(report)]
            case "api_retry":
                retried = true
                return [.activity]
            default:
                return []
            }
        case "stream_event":
            return consumeStream(event["event"] as? [String: Any] ?? [:])
        case "assistant":
            return consumeAssistant(event)
        case "user":
            return consumeToolResults(event)
        case "rate_limit_event":
            let info = event["rate_limit_info"] as? [String: Any] ?? [:]
            if info["status"] as? String == "rejected" {
                rejectedResetsAt = (info["resetsAt"] as? NSNumber).map { $0.int64Value } ?? 0
            }
            return []
        case "result":
            resultSeen = true
            resultIsError = event["is_error"] as? Bool ?? false
            resultSubtype = event["subtype"] as? String ?? ""
            resultText = event["result"] as? String ?? ""
            if !resultIsError && resultSubtype == "success" {
                finished = true
                return [.finish(.stop)]
            }
            if resultSubtype == "error_max_turns" {
                finished = true
                return [.finish(.length)]
            }
            return []
        default:
            return []
        }
    }

    /// An event that would put something on screen, or run a tool, before the tools are checked (`reference.py`'s
    /// `shows_something`): a text or tool start, an assistant's tool use, a user's tool result.
    private static func showsSomething(_ event: [String: Any]) -> Bool {
        switch event["type"] as? String {
        case "stream_event":
            let type = (event["event"] as? [String: Any])?["type"] as? String
            return type == "content_block_start" || type == "content_block_delta"
        case "assistant":
            return hasBlock(event, "tool_use")
        case "user":
            return hasBlock(event, "tool_result")
        default:
            return false
        }
    }

    private static func hasBlock(_ event: [String: Any], _ type: String) -> Bool {
        let content = (event["message"] as? [String: Any])?["content"] as? [Any] ?? []
        return content.contains { ($0 as? [String: Any])?["type"] as? String == type }
    }

    private static func payer(_ source: String?) -> EngineReport.Payer {
        switch source {
        case "none", "oauth": .plan
        case "user", "project", "org", "temporary": .apiKey
        default: .unknown
        }
    }

    private mutating func consumeStream(_ e: [String: Any]) -> [ChatChunk] {
        switch e["type"] as? String {
        case "message_start":
            needsBreak = needsBreak || !text.isEmpty
            return []
        case "content_block_start":
            let block = e["content_block"] as? [String: Any] ?? [:]
            if block["type"] as? String == "tool_use", let id = block["id"] as? String {
                needsBreak = needsBreak || !text.isEmpty
                let step = ChatStep(id: id, tool: block["name"] as? String ?? "")
                steps[id] = step
                return [.step(step)]
            }
            if block["type"] as? String == "text", needsBreak, !text.isEmpty {
                needsBreak = false
                text += "\n\n"
                return [.text("\n\n")]
            }
            return []
        case "content_block_delta":
            let delta = e["delta"] as? [String: Any] ?? [:]
            guard delta["type"] as? String == "text_delta", let piece = delta["text"] as? String else { return [] }
            var out: [ChatChunk] = []
            if needsBreak, !text.isEmpty { text += "\n\n"; out.append(.text("\n\n")) }
            needsBreak = false
            text += piece
            out.append(.text(piece))
            return out
        default:
            return []
        }
    }

    private mutating func consumeAssistant(_ event: [String: Any]) -> [ChatChunk] {
        if let error = event["error"] as? String { assistantError = error }
        var out: [ChatChunk] = []
        let content = (event["message"] as? [String: Any])?["content"] as? [[String: Any]] ?? []
        for block in content where block["type"] as? String == "tool_use" {
            guard let id = block["id"] as? String, var step = steps[id] else { continue }
            step.input = Self.stepInput(block["input"] as? [String: Any] ?? [:])
            steps[id] = step
            out.append(.step(step))
        }
        return out
    }

    private mutating func consumeToolResults(_ event: [String: Any]) -> [ChatChunk] {
        var out: [ChatChunk] = []
        let content = (event["message"] as? [String: Any])?["content"] as? [Any] ?? []
        for case let block as [String: Any] in content where block["type"] as? String == "tool_result" {
            guard let id = block["tool_use_id"] as? String, var step = steps[id] else { continue }
            step.state = (block["is_error"] as? Bool ?? false) ? .failed : .done
            steps[id] = step
            out.append(.step(step))
        }
        return out
    }

    private static func stepInput(_ raw: [String: Any]) -> [String: String] {
        var out: [String: String] = [:]
        for key in stepFields {
            guard let value = raw[key] as? String else { continue }
            out[key] = String(String.UnicodeScalarView(value.unicodeScalars.prefix(stepFieldCap)))
        }
        return out
    }

    // MARK: The end of the run

    /// `nil` when the run ended well. Call once, after the process has exited. `stderr` is only read, never kept.
    /// The exit status is not used: Claude Code does not document one, and a result decides when there is one.
    func failure(stderr: String) -> AIError? {
        if refusedTools { return AIError(kind: .badRequest, code: ClaudeCodeError.toolsPresent) }
        if finished { return nil }
        let words = (resultSeen ? resultText : "")
        let blob = (words + "\n" + stderr).lowercased()
        let paid = engine?.paidBy
        func fail(_ kind: AIErrorKind, _ code: String? = nil, resetsAt: Int64? = nil) -> AIError {
            AIError(kind: kind, code: code,
                    resetsAt: resetsAt.flatMap { $0 > 0 ? Date(timeIntervalSince1970: TimeInterval($0)) : nil })
        }
        if blob.contains("git-bash") || blob.contains("claude_code_git_bash_path") || blob.contains("git for windows") {
            return fail(.badRequest, ClaudeCodeError.needsGit)
        }
        if assistantError == "authentication_failed" || blob.contains("not logged in") || blob.contains("please run /login") {
            return fail(.auth, ClaudeCodeError.signedOut)
        }
        if blob.contains("unknown option") { return fail(.badRequest, ClaudeCodeError.tooOld) }
        if rejectedResetsAt != nil || (assistantError == "rate_limit" && paid == .plan) {
            return fail(.billing, ClaudeCodeError.planLimit, resetsAt: rejectedResetsAt)
        }
        if assistantError == "rate_limit" { return fail(.rateLimited) }
        if assistantError == "billing_error" { return fail(.billing, "billing_error") }
        if assistantError == "overloaded" { return fail(.overloaded) }
        if assistantError == "server_error" { return fail(.server) }
        if resultSeen, retried || blob.contains("unable to connect") { return fail(.unreachable, ClaudeCodeError.offline) }
        return fail(.interrupted, ClaudeCodeError.crashed)
    }
}

#endif
