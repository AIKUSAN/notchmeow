import Foundation

// The step rows' words, as the session view has always shown them. They were moved out of HookServer unchanged:
// these cases are what they said before.

@main
enum SessionStepTextTests {
    nonisolated(unsafe) static var failures = 0

    static func check(_ label: String, _ got: String, _ expected: String) {
        if got == expected { print("  ✓ \(label)") } else { print("  ✗ \(label)\n    got:      \(got)\n    expected: \(expected)"); failures += 1 }
    }

    static func main() {
        let step = SessionStepText.line
        check("Bash infers a verb: reading", step("Bash", ["command": "cat a.txt"]), "Reads · cat a.txt")
        check("Bash infers a verb: searching", step("Bash", ["command": "ls -la src"]), "Finds · ls -la src")
        check("Bash infers a verb: testing", step("Bash", ["command": "npm test -- --watch"]), "Tests · npm test -- --watch")
        check("Bash otherwise runs", step("Bash", ["command": "echo hi"]), "Runs · echo hi")
        check("a multi-line command is one line", step("Bash", ["command": "a\nb\tc"]), "Runs · a b c")
        check("a long command is cut at 60", step("Bash", ["command": String(repeating: "x", count: 70)]), "Runs · " + String(repeating: "x", count: 60) + "…")
        check("Read shows the file's name", step("Read", ["file_path": "/work/README.md"]), "Reads · README.md")
        check("Edit", step("Edit", ["file_path": "/work/a/b.swift"]), "Edits · b.swift")
        check("a path field works too", step("LS", ["path": "/work/src"]), "Lists · src")
        check("a query", step("WebSearch", ["query": "swift concurrency"]), "Web search · swift concurrency")
        check("a tool with nothing to show is its label", step("Glob", ["pattern": "*.swift"]), "Finds")
        check("an unknown tool keeps its name", step("Frobnicate", [:]), "Frobnicate")
        check("an MCP tool is server · tool", step("mcp__github__create_issue", [:]), "github · create_issue")
        check("a patch shows its first file", step("apply_patch", ["command": "*** Begin Patch\n*** Update File: src/foo.txt\n@@"]), "Edits · foo.txt")
        check("a Codex plan", step("update_plan", [:]), "Tasks")
        if failures == 0 { print("\nAll tests passed."); exit(0) }
        print("\n\(failures) test(s) failed."); exit(1)
    }
}
