import Foundation

/// The words of a session step row ("Reads · README.md", "Runs · npm test"). They lived in `HookServer`; the chat's
/// step rows read the same way, so they live here, unchanged.
enum SessionStepText {
    // MARK: - Step labels

    private static let labels: [String: String] = [
        "Bash":        "Runs",
        "Read":        "Reads",
        "Write":       "Writes",
        "Edit":        "Edits",
        "Glob":        "Finds",
        "Grep":        "Searches",
        "WebSearch":   "Web search",
        "WebFetch":    "Fetches",
        "TodoWrite":   "Tasks",
        "Task":        "Agent",
        "LS":          "Lists",
        "MultiEdit":   "Edits",
        "NotebookEdit": "Notebook",
        // Codex tools
        "apply_patch": "Edits",
        "update_plan": "Tasks",
        "spawn_agent": "Agent",
    ]

    /// The label alone for a tool, never its input (focus awareness's step words): nil for a tool the table does not name.
    static func verb(tool: String) -> String? {
        if tool.hasPrefix("mcp__") { return mcpLabel(tool) }
        return labels[tool]
    }

    /// Codex MCP tools arrive as mcp__server__tool — show "server · tool"
    private static func mcpLabel(_ tool: String) -> String {
        let rest = String(tool.dropFirst(5))
        let parts = rest.components(separatedBy: "__")
        return parts.count >= 2 ? "\(parts[0]) · \(parts.dropFirst().joined(separator: "__"))" : rest
    }

    static func line(tool: String, input: [String: Any]) -> String {
        let label = verb(tool: tool) ?? tool

        // Bash: infer a more precise verb from the command
        if tool == "Bash", let cmd = input["command"] as? String {
            return "\(bashVerb(cmd)) · \(oneLine(cmd))"
        }

        // apply_patch: extract the first file name from the patch
        if tool == "apply_patch", let patch = input["command"] as? String {
            for line in patch.split(separator: "\n") {
                for prefix in ["*** Update File: ", "*** Add File: ", "*** Delete File: "] {
                    if line.hasPrefix(prefix) {
                        let path = String(line.dropFirst(prefix.count))
                        return "\(label) · \(URL(fileURLWithPath: path).lastPathComponent)"
                    }
                }
            }
            return label
        }

        if let cmd = input["command"] as? String {
            return "\(label) · \(oneLine(cmd))"
        } else if let path = input["path"] as? String {
            return "\(label) · \(URL(fileURLWithPath: path).lastPathComponent)"
        } else if let file = input["file_path"] as? String {
            return "\(label) · \(URL(fileURLWithPath: file).lastPathComponent)"
        } else if let query = input["query"] as? String {
            return "\(label) · \(oneLine(query))"
        }
        return label
    }

    /// Infers a verb from a shell command's first word.
    private static func bashVerb(_ command: String) -> String {
        let first = command.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
        switch first {
        case "cat", "bat", "head", "tail", "less", "more", "nl": return "Reads"
        case "rg", "grep", "find", "fd", "ls", "tree", "wc":    return "Finds"
        default: break
        }
        let testRunners = ["pytest", "vitest", "jest", "npm test", "npm run test",
                           "cargo test", "go test", "swift test", "make test",
                           "xcodebuild test", "unittest"]
        if testRunners.contains(where: { command.contains($0) }) { return "Tests" }
        return "Runs"
    }

    /// Collapses whitespace so a multi-line command stays one ticker row.
    private static func oneLine(_ text: String, limit: Int = 60) -> String {
        let collapsed = text.split(whereSeparator: { $0.isNewline || $0 == "\t" })
                            .joined(separator: " ")
        return collapsed.count > limit ? String(collapsed.prefix(limit)) + "…" : collapsed
    }
}
