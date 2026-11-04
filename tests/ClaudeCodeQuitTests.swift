import Foundation

// Quitting the app must leave no `claude` and nothing it started running: `ClaudeRunRegistry.stopAll()` is what the
// app calls when it terminates. Runs the fake `claude` (tests/fixtures/ai/claude-code/fake_claude.py). No real claude.

@main
@MainActor
enum ClaudeCodeQuitTests {
    static func pid(_ file: String) -> Int32? {
        (try? String(contentsOfFile: file, encoding: .utf8)).flatMap { Int32($0) }
    }

    /// Alive and not a zombie: `kill(pid, 0)` succeeds on a zombie, `ps` tells the two apart.
    static func alive(_ file: String) -> Bool {
        guard let pid = pid(file), kill(pid, 0) == 0 else { return false }
        let ps = Process()
        ps.executableURL = URL(fileURLWithPath: "/bin/ps")
        ps.arguments = ["-o", "stat=", "-p", String(pid)]
        let out = Pipe()
        ps.standardOutput = out
        guard (try? ps.run()) != nil else { return true }
        let text = String(decoding: out.fileHandleForReading.readDataToEndOfFile(), as: UTF8.self)
        ps.waitUntilExit()
        return !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && !text.contains("Z")
    }

    static func waitFor(_ seconds: Double, _ condition: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end { if condition() { return true }; try? await Task.sleep(nanoseconds: 50_000_000) }
        return condition()
    }

    /// A run that never says anything more, with a child, started the way a chat starts it.
    static func start(_ root: URL, _ name: String, stubborn: Bool, hang: Bool = true) async -> (pid: String, child: String, consumer: Task<Void, Never>) {
        let pidFile = root.appendingPathComponent("\(name).pid").path, childFile = root.appendingPathComponent("\(name).child").path
        var env = ["PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin", "NM_FAKE_CLAUDE_PIDFILE": pidFile]
        if hang { env["NM_FAKE_CLAUDE_HANG_AFTER"] = "0"; env["NM_FAKE_CLAUDE_CHILD_PIDFILE"] = childFile }
        if stubborn { env["NM_FAKE_CLAUDE_STUBBORN"] = "1" }
        let fake = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("tests/fixtures/ai/claude-code/fake_claude.py").path
        let provider = ClaudeCodeProvider(
            executable: fake, turn: ClaudeCodeTurn(level: .chatOnly, sessionID: "11111111-1111-4111-8111-111111111111", resume: false),
            chatFolder: root.appendingPathComponent("chat").path, baseEnvironment: env,
            // Long graces: only the quit path may end these runs in time.
            timings: ClaudeProcessTimings(startup: 60, interruptGrace: 30, terminateGrace: 30, drain: 0.2))
        let request = ChatRequest(model: "sonnet", system: "", messages: [.init(role: .user, parts: [.text("Hello")])])
        let consumer = Task { do { for try await _ in provider.stream(request) {} } catch {} }
        return (pidFile, childFile, consumer)
    }

    static func main() async {
        DispatchQueue.global().asyncAfter(deadline: .now() + 120) { print("timed out"); exit(3) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nm-claude-quit-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        T.section("stopAll with no run is a no-op")
        T.check("nothing is live", ClaudeRunRegistry.liveCount, 0)
        ClaudeRunRegistry.stopAll()
        T.check("and still nothing", ClaudeRunRegistry.liveCount, 0)

        T.section("Quit ends a running claude and what it started")
        let plain = await start(root, "plain", stubborn: false)
        let up = await waitFor(10) { pid(plain.pid) != nil && pid(plain.child) != nil }
        T.checkTrue("the fake and its child are up", up)
        T.check("the run is registered", ClaudeRunRegistry.liveCount, 1)
        let t0 = Date()
        ClaudeRunRegistry.stopAll()
        T.checkTrue("stopAll returned within 2 s of a polite run (\(String(format: "%.2f", Date().timeIntervalSince(t0))) s)", Date().timeIntervalSince(t0) < 2)
        let gone = await waitFor(4) { !alive(plain.pid) && !alive(plain.child) }
        T.check("the fake and its child are gone", [alive(plain.pid), alive(plain.child)], [false, false])
        _ = gone
        plain.consumer.cancel()
        let unregistered = await waitFor(3) { ClaudeRunRegistry.liveCount == 0 }
        T.checkTrue("and the run unregistered itself", unregistered)

        T.section("A stubborn claude (ignores SIGINT and SIGTERM) is killed")
        let stubborn = await start(root, "stubborn", stubborn: true)
        _ = await waitFor(10) { pid(stubborn.pid) != nil && pid(stubborn.child) != nil }
        let t1 = Date()
        ClaudeRunRegistry.stopAll()
        let elapsed = Date().timeIntervalSince(t1)
        T.checkTrue("stopAll is bounded (\(String(format: "%.2f", elapsed)) s)", elapsed < 3)
        _ = await waitFor(4) { !alive(stubborn.pid) && !alive(stubborn.child) }
        T.check("the fake and its child are gone", [alive(stubborn.pid), alive(stubborn.child)], [false, false])
        stubborn.consumer.cancel()

        T.section("A run that ends by itself leaves the registry")
        let quick = await start(root, "quick", stubborn: false, hang: false)
        _ = await quick.consumer.value
        let empty = await waitFor(3) { ClaudeRunRegistry.liveCount == 0 }
        T.checkTrue("nothing is live after a normal exit", empty)
        // Whatever a failure left behind.
        for file in ["plain", "stubborn"].flatMap({ ["\($0).pid", "\($0).child"] }) {
            if let p = pid(root.appendingPathComponent(file).path) { kill(p, SIGKILL) }
        }
        T.finish()
    }
}
