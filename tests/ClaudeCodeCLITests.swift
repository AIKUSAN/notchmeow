import Foundation

// ClaudeCodeCLI.run: output, the 64 KiB cap, and a timeout that kills the program and never waits on a pipe a
// descendant holds open. Only /bin/sh and its tools run here, never a real claude.

@main
@MainActor
enum ClaudeCodeCLITests {
    static let env = ["PATH": "/usr/bin:/bin"]

    static func main() async {
        // A hung run must fail the test, not hang it.
        DispatchQueue.global().asyncAfter(deadline: .now() + 15) { print("  ✗ timed out: ClaudeCodeCLI.run never returned"); exit(3) }
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nm-cli-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        await output()
        await ignoresTerm(root.appendingPathComponent("term.pid").path)
        await descendantHoldsPipe(root.appendingPathComponent("bg.pid").path)
        T.finish()
    }

    static func output() async {
        T.section("Output")
        let hello = await ClaudeCodeCLI.run("/bin/sh", ["-c", "echo hello"], environment: env, timeout: 5)
        T.check("normal output and exit status", [hello.status.map(String.init) ?? "nil", hello.output], ["0", "hello\n"])
        let big = await ClaudeCodeCLI.run("/bin/sh", ["-c", "head -c 200000 /dev/zero | tr '\\0' a"], environment: env, timeout: 10)
        T.check("output is capped at 64 KiB", big.output.utf8.count, 65_536)
        let fail = await ClaudeCodeCLI.run("/bin/sh", ["-c", "exit 3"], environment: env, timeout: 5)
        T.check("exit status", fail.status.map(Int.init), 3)
        let missing = await ClaudeCodeCLI.run("/nonexistent/x", [], environment: env, timeout: 5)
        T.check("a program that cannot run", missing.status.map(Int.init), nil)
    }

    static func pid(_ file: String) -> Int32? {
        (try? String(contentsOfFile: file, encoding: .utf8)).flatMap { Int32($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
    }

    static func gone(_ pid: Int32) async -> Bool {
        for _ in 0..<30 {
            if kill(pid, 0) != 0 { return true }
            try? await Task.sleep(nanoseconds: 100_000_000)
        }
        return false
    }

    static func ignoresTerm(_ pidFile: String) async {
        T.section("A program that ignores SIGTERM")
        let start = Date()
        let r = await ClaudeCodeCLI.run("/bin/sh", ["-c", "echo $$ > '\(pidFile)'; trap '' TERM; while :; do sleep 1; done"],
                                        environment: env, timeout: 1)
        T.check("no status", r.status.map(Int.init), nil)
        T.checkTrue("returns within a few seconds", Date().timeIntervalSince(start) < 5)
        if let p = pid(pidFile) {
            let dead = await gone(p)
            if !dead { kill(p, SIGKILL) }
            T.checkTrue("the program is gone afterwards", dead)
        } else { T.checkTrue("the program wrote its pid", false) }
    }

    static func descendantHoldsPipe(_ pidFile: String) async {
        T.section("A descendant holds stdout open")
        let start = Date()
        let r = await ClaudeCodeCLI.run("/bin/sh", ["-c", "sleep 30 & echo $! > '\(pidFile)'; exit 0"], environment: env, timeout: 10)
        let took = Date().timeIntervalSince(start)
        if let p = pid(pidFile) { kill(p, SIGKILL) }
        T.check("the exit status is still reported", r.status.map(Int.init), 0)
        T.checkTrue("returns long before the descendant ends (\(took)s)", took < 5)
    }
}
