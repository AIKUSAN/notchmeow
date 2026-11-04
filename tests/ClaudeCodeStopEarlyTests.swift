import Foundation

// Stop pressed before (or while) the process is being started must leave nothing running. Many streams are
// cancelled after 0 to ~230 ms, so some are stopped before the launch, some in the middle of it and some after it.
// Runs the fake `claude` (tests/fixtures/ai/claude-code/fake_claude.py). No real claude is ever run.

@main
@MainActor
enum ClaudeCodeStopEarlyTests {
    static let runs = 30

    static func alive(_ pidFile: String) -> Bool {
        guard let text = try? String(contentsOfFile: pidFile, encoding: .utf8), let pid = Int32(text) else { return false }
        return kill(pid, 0) == 0
    }

    static func main() async {
        DispatchQueue.global().asyncAfter(deadline: .now() + 120) { print("timed out"); exit(3) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nm-claude-early-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let chat = root.appendingPathComponent("chat").path
        let fake = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("tests/fixtures/ai/claude-code/fake_claude.py").path
        let request = ChatRequest(model: "sonnet", system: "", messages: [.init(role: .user, parts: [.text("Hello")])])

        T.section("Stop before the launch finishes")
        var files: [String] = []
        for i in 0..<runs {
            let pid = root.appendingPathComponent("p\(i).pid").path, child = root.appendingPathComponent("p\(i).child").path
            files += [pid, child]
            let env = ["PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin",
                       // Never says anything and never ends, with a child: only Stop can end it.
                       "NM_FAKE_CLAUDE_HANG_AFTER": "0", "NM_FAKE_CLAUDE_PIDFILE": pid, "NM_FAKE_CLAUDE_CHILD_PIDFILE": child]
            let provider = ClaudeCodeProvider(
                executable: fake, turn: ClaudeCodeTurn(level: .chatOnly, sessionID: "11111111-1111-4111-8111-111111111111", resume: false),
                chatFolder: chat, baseEnvironment: env,
                timings: ClaudeProcessTimings(startup: 60, interruptGrace: 0.2, terminateGrace: 0.2, drain: 0.2))
            let consumer = Task { for try await _ in provider.stream(request) {} }
            // 0 ms (before anything started) up to about 230 ms (after the fake is up).
            try? await Task.sleep(nanoseconds: UInt64(i) * 8_000_000)
            consumer.cancel()
        }
        // A process that escaped Stop writes its pid file within a second: look only after that.
        try? await Task.sleep(nanoseconds: 1_500_000_000)
        let started = files.filter { FileManager.default.fileExists(atPath: $0) }.count
        print("    (\(started) pid files were written)")
        let end = Date().addingTimeInterval(6)
        while Date() < end, files.contains(where: alive) { try? await Task.sleep(nanoseconds: 50_000_000) }
        T.check("no process, and no child of one, is left running", files.filter(alive).map { URL(fileURLWithPath: $0).lastPathComponent }, [])
        T.finish()
    }
}
