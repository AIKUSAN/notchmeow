import Foundation

@main
@MainActor
enum ClaudeCodeApprovalTests {
    static func main() {
        text()
        queue()
        hooks()
        T.finish()
    }

    static func text() {
        T.section("What the card says")
        T.check("a command", ChatApprovalText.target(tool: "Bash", input: ["command": " npm test "]), "Bash · npm test")
        T.check("a file", ChatApprovalText.target(tool: "Write", input: ["file_path": "/work/.env", "content": "SECRET"]), "Write · /work/.env")
        T.check("a path", ChatApprovalText.target(tool: "Read", input: ["path": "/etc/hosts"]), "Read · /etc/hosts")
        T.check("a URL", ChatApprovalText.target(tool: "WebFetch", input: ["url": "https://example.com"]), "WebFetch · https://example.com")
        T.check("an unfamiliar tool with nothing to show is its name", ChatApprovalText.target(tool: "Frob", input: ["x": 1]), "Frob")
        T.check("a blank field is skipped", ChatApprovalText.target(tool: "Grep", input: ["command": "  ", "pattern": "TODO"]), "Grep · TODO")
        T.checkTrue("the content of a Write is never on the card", !ChatApprovalText.target(tool: "Write", input: ["file_path": "a", "content": "SECRET"]).contains("SECRET"))
    }

    static func queue() {
        T.section("Requests waiting for a click")
        func approval(_ session: String, _ tool: String) -> ChatApproval { ChatApproval(id: UUID(), sessionID: session, tool: tool, target: tool) }
        var q = ChatApprovalQueue<Int>()
        T.check("empty", q.front == nil, true)
        let a = approval("s1", "Bash"), b = approval("s1", "Edit"), c = approval("s2", "Write")
        q.push(a, token: 1); q.push(b, token: 2); q.push(c, token: 3)
        T.check("the first to arrive is shown", q.front?.tool, "Bash")
        T.check("answering takes the first", q.popFront()?.token, 1)
        T.check("and shows the next", q.front?.tool, "Edit")
        T.check("a connection that closed leaves only itself", q.remove(id: c.id)?.token, 3)
        T.check("and an unknown id is nothing", q.remove(id: UUID()) == nil, true)
        q.push(c, token: 3)
        T.check("one session's requests go together", q.removeAll(session: "s1").map(\.token), [2])
        T.check("the other session's stay", q.front?.sessionID, "s2")
        T.check("all of them", q.removeAll().map(\.token), [3])
        T.check("then it is empty", q.isEmpty, true)
    }

    static func hooks() {
        T.section("Are NotchMeow's hooks installed")
        func settings(_ command: String) -> [String: Any] {
            ["hooks": ["PermissionRequest": [["hooks": [["type": "command", "command": command, "timeout": 120]]]]]]
        }
        T.check("the hook NotchMeow installs", ClaudeAgentReadiness.hooksInstalled(in: settings("\"/Users/zoe/Library/Application Support/NotchMeow/nm-hook\"")), true)
        T.check("someone else's hook", ClaudeAgentReadiness.hooksInstalled(in: settings("/usr/local/bin/other")), false)
        T.check("no hooks at all", ClaudeAgentReadiness.hooksInstalled(in: [:]), false)
        T.check("hooks for other events only", ClaudeAgentReadiness.hooksInstalled(in: ["hooks": ["Stop": [["hooks": [["command": "nm-hook"]]]]]]), false)
    }
}
