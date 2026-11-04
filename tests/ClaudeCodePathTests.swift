import Foundation

// A node-based install (`#!/usr/bin/env node`, npm or nvm) only runs if `node` is on the child's PATH, and a
// Finder-launched app has almost none. The child (a turn, the status checks) gets a PATH that finds it.
// Never runs a real node or a real claude: the `node` here is a shell script of this test's own.

@main
@MainActor
enum ClaudeCodePathTests {
    static func main() async {
        DispatchQueue.global().asyncAfter(deadline: .now() + 120) { print("timed out"); exit(3) }
        pureHelper()
        await nodeInstall()
        T.finish()
    }

    static func pureHelper() {
        T.section("The PATH of the child")
        func path(executable: String, existing: String?) -> String { ClaudeCodeCommand.searchPath(executable: executable, existing: existing) }
        T.check("its own folder first, then Homebrew and /usr/local, then the rest in order",
                path(executable: "/Users/me/.npm-global/bin/claude", existing: "/usr/bin:/bin"),
                "/Users/me/.npm-global/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin")
        T.check("no repeats, the first place wins",
                path(executable: "/usr/local/bin/claude", existing: "/bin:/usr/local/bin:/bin:/opt/homebrew/bin:/usr/bin"),
                "/usr/local/bin:/opt/homebrew/bin:/bin:/usr/bin")
        T.check("no empty entries", path(executable: "/a/claude", existing: ":/bin::/usr/bin:"), "/a:/opt/homebrew/bin:/usr/local/bin:/bin:/usr/bin")
        T.check("no PATH at all", path(executable: "/a/claude", existing: nil), "/a:/opt/homebrew/bin:/usr/local/bin")
        T.check("an empty PATH", path(executable: "/a/claude", existing: ""), "/a:/opt/homebrew/bin:/usr/local/bin")
        T.check("a folder with spaces stays one entry",
                path(executable: "/Users/Zoé Ünï/My Tools/bin/claude", existing: "/usr/bin"),
                "/Users/Zoé Ünï/My Tools/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin")
        T.check("a bare name adds no folder", path(executable: "claude", existing: "/bin"), "/opt/homebrew/bin:/usr/local/bin:/bin")

        let env = ClaudeCodeCommand.childEnvironment(
            from: ["PATH": "/usr/bin", "ANTHROPIC_API_KEY": "sk-ant-FAKE", "ANTHROPIC_AUTH_TOKEN": "x", "CLAUDE_CODE_USE_BEDROCK": "1",
                   "CANARY": "kept"], platform: .current, executable: "/a/claude")
        T.check("what is stripped stays stripped, the rest is kept and PATH is added to",
                env, ["PATH": "/a:/opt/homebrew/bin:/usr/local/bin:/usr/bin", "CANARY": "kept"])
        T.check("a run with no PATH gets one", ClaudeCodeCommand.childEnvironment(from: [:], platform: .current, executable: "/a/claude")["PATH"],
                "/a:/opt/homebrew/bin:/usr/local/bin")
    }

    /// `claude` is a node script and the only `node` is a shell script beside it that prints a version.
    static func nodeInstall() async {
        T.section("A node-based install, with the PATH of a Finder-launched app")
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nm-claude-node-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let bin = root.appendingPathComponent("My Tools/.npm-global/bin")
        try! FileManager.default.createDirectory(at: bin, withIntermediateDirectories: true)
        let log = root.appendingPathComponent("env.txt").path
        func install(_ name: String, _ body: String) {
            let file = bin.appendingPathComponent(name)
            try! body.write(to: file, atomically: true, encoding: .utf8)
            try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: file.path)
        }
        install("claude", "#!/usr/bin/env node\nthis is not run by anything but a node\n")
        // Records which names the child had (not their values), prints a version and exits 0.
        install("node", "#!/bin/sh\nenv | cut -d= -f1 | sort > '\(log)'\necho '2.9.9 (Claude Code)'\n")
        let claude = bin.appendingPathComponent("claude").path
        let guiEnvironment = ["PATH": "/usr/bin:/bin", "HOME": NSHomeDirectory(), "ANTHROPIC_API_KEY": "sk-ant-FAKE"]

        let status = await ClaudeCodeLocator.statusOf(executable: claude, environment: guiEnvironment)
        T.check("Settings sees the version", status.version, "2.9.9")
        T.check("and it is not reported as missing", status.state != .notInstalled, true)
        let names = ((try? String(contentsOfFile: log, encoding: .utf8)) ?? "").split(separator: "\n").map(String.init)
        T.check("the key that outranks the plan login did not reach the child", names.contains("ANTHROPIC_API_KEY"), false)

        // A turn: the same PATH reaches the process (the fake logs its environment).
        let fake = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("tests/fixtures/ai/claude-code/fake_claude.py").path
        let turnLog = root.appendingPathComponent("turn.jsonl").path
        let provider = ClaudeCodeProvider(
            executable: fake, turn: ClaudeCodeTurn(level: .chatOnly, sessionID: "11111111-1111-4111-8111-111111111111", resume: false),
            chatFolder: root.appendingPathComponent("chat").path,
            baseEnvironment: ["PATH": "/usr/bin:/bin:/opt/homebrew/bin", "NM_FAKE_CLAUDE_LOG": turnLog,
                              "NM_FAKE_CLAUDE_TRANSCRIPT": URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
                                  .appendingPathComponent("tests/fixtures/ai/claude-code/transcripts/success.jsonl").path])
        do {
            for try await _ in provider.stream(ChatRequest(model: "sonnet", system: "", messages: [.init(role: .user, parts: [.text("Hi")])])) {}
        } catch {}
        let calls = ((try? String(contentsOfFile: turnLog, encoding: .utf8)) ?? "").split(separator: "\n").compactMap {
            try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
        }
        let seen = (calls.first?["env"] as? [String: String])?["PATH"] ?? ""
        T.check("a turn's PATH starts with the program's folder, then Homebrew", seen.hasPrefix(URL(fileURLWithPath: fake).deletingLastPathComponent().path + ":/opt/homebrew/bin:/usr/local/bin:"), true)
    }
}
