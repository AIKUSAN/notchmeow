import Foundation

// Claude Code as an engine, the pure parts: the levels, the command line of one turn, the environment it runs
// in and the message written to its stdin. Nothing here starts a process (`ClaudeCodeProvider.swift` does).
// `tests/fixtures/ai/claude-code/` is what both apps must agree on; its `reference.py` is the tie-breaker.
// The App Store build compiles all of this out (`scripts/check-app-binary.sh` looks for strings only the engine has).

#if !APPSTORE

enum ClaudeCodeEngine {
    /// The plain-text note next to the engine's name in the UI. Never "Claude Code" as a label.
    static let note = "runs your installed Claude Code"
}

enum ClaudeCodePlatform: String, Sendable {
    case mac, linux, windows

    /// The Mac app is always `mac`; the other two exist for the shared fixtures.
    static let current = ClaudeCodePlatform.mac
}

/// What Claude may do in a chat. Read-only and Agent carry the folder the user chose. No tools (quick actions only)
/// has no folder and is never offered in the level picker.
enum ClaudeCodeLevel: Sendable, Equatable {
    case chatOnly
    case readOnly(folder: String)
    case agent(folder: String)
    case noTools

    var folder: String? {
        switch self {
        case .chatOnly, .noTools: nil
        case .readOnly(let folder), .agent(let folder): folder
        }
    }

    /// `chat`, `read`, `agent` or `none`, as in the fixtures.
    var key: String {
        switch self {
        case .chatOnly: "chat"
        case .readOnly: "read"
        case .agent: "agent"
        case .noTools: "none"
        }
    }
}

/// One run of Claude Code: everything except the message itself.
struct ClaudeCodeTurn: Sendable, Equatable {
    var level: ClaudeCodeLevel
    var model: ClaudeCodeModel = .sonnet
    /// The id NotchMeow chose for this chat's Claude Code session (lower-case UUID).
    var sessionID: String
    /// False on a chat's first turn (`--session-id`), true on the later ones (`--resume`).
    var resume: Bool
    var platform: ClaudeCodePlatform = .current
}

enum ClaudeCodeCommand {
    static let base = ["-p", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
                       "--include-partial-messages"]
    private static let chatTools = "WebSearch,WebFetch"
    private static let readTools = "Read,Grep,Glob,WebSearch,WebFetch"
    private static let readSettings = #"{"permissions":{"blockReadsOutsideWorkingDirectories":true}}"#
    private static let sandboxSettings = #"{"sandbox":{"enabled":true,"allowUnsandboxedCommands":false,"autoAllowBashIfSandboxed":false}}"#
    private static let noToolsDeny = "WebSearch,WebFetch,mcp__*"

    /// The arguments after the program name. Every quoted value of the spec is one element: there is no shell.
    /// The folder is the process's working folder, never an argument.
    static func arguments(_ turn: ClaudeCodeTurn) -> [String] {
        var args = base + [turn.resume ? "--resume" : "--session-id", turn.sessionID, "--model", turn.model.rawValue]
        switch turn.level {
        case .chatOnly:
            args += ["--safe-mode", "--tools", chatTools, "--allowedTools", chatTools,
                     "--disallowedTools", "mcp__*", "--permission-mode", "dontAsk"]
        case .readOnly:
            args += ["--safe-mode", "--tools", readTools, "--allowedTools", readTools,
                     "--permission-mode", "dontAsk", "--settings", readSettings]
        case .noTools:
            // An empty --tools list: no tool at all, and no MCP server.
            args += ["--safe-mode", "--tools", "", "--disallowedTools", noToolsDeny, "--permission-mode", "dontAsk"]
        case .agent:
            args += ["--permission-mode", "default"]
            // Native Windows has no command sandbox: there every command asks.
            if turn.platform != .windows { args += ["--settings", sandboxSettings] }
        }
        return args
    }

    /// The folder the process runs in: the user's for Read-only and Agent, NotchMeow's own empty one for Chat only
    /// and No tools.
    static func workingDirectory(_ turn: ClaudeCodeTurn, chatFolder: String) -> String {
        turn.level.folder ?? chatFolder
    }

    /// The tools the `init` line must report, in order, for a level that checks them (No tools only). nil: no check.
    static func initTools(_ level: ClaudeCodeLevel) -> [String]? {
        switch level {
        case .noTools: []
        case .chatOnly, .readOnly, .agent: nil
        }
    }

    // MARK: Environment

    /// Variables that outrank the user's plan login in Claude Code's own order of precedence.
    static let strippedVariables: Set<String> = ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN",
                                                 "ANTHROPIC_PROFILE"]
    static let strippedPrefixes = ["CLAUDE_CODE_USE_"]

    /// The environment of a run: the caller's, without what would outrank the plan login. On Windows names
    /// compare without regard to case. An `apiKeyHelper` is a setting, not a variable: it is not touched.
    static func environment(from base: [String: String], platform: ClaudeCodePlatform) -> [String: String] {
        let insensitive = platform == .windows
        return base.filter { name, _ in
            let key = insensitive ? name.uppercased() : name
            return !strippedVariables.contains(key) && !strippedPrefixes.contains { key.hasPrefix($0) }
        }
    }

    // MARK: stdin

    /// The one line written to stdin: the new message as content blocks (a dropped image or PDF as a block, other
    /// files as text), in the documented user-message shape. `preamble` is a recap of the chat so far, only for a
    /// session that is started afresh in the middle of a chat (`ClaudeChatSession` decides when).
    static func userLine(parts: [ChatRequest.Part], preamble: String? = nil) -> Data {
        var content: [[String: Any]] = []
        if let preamble, !preamble.isEmpty { content.append(["type": "text", "text": preamble]) }
        content += parts.map(AnthropicProvider.block)
        let message: [String: Any] = ["type": "user", "message": ["role": "user", "content": content],
                                      "parent_tool_use_id": NSNull()]
        var data = (try? JSONSerialization.data(withJSONObject: message)) ?? Data()
        data.append(0x0A)
        return data
    }
}

#endif
