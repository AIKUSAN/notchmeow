import Foundation

// Shared helpers for the AI test programs (scripts/test-ai-*.sh compile this file into each one).
// Run from the repository root: fixture paths are relative to it.

@MainActor
enum T {
    static var failures = 0

    /// Every section starts here, so a test program run by hand (without `NM_LOG_DIR`) stops before it logs.
    static func section(_ name: String) {
        requireTempLog()
        print(name)
    }

    /// Tests never write to the user's real log: `scripts/test-*.sh` set `NM_LOG_DIR` to a temp folder
    /// and `appendAppLog` honours it.
    static func requireTempLog() {
        guard let dir = ProcessInfo.processInfo.environment["NM_LOG_DIR"], !dir.isEmpty, !dir.contains("/Library/Logs") else {
            print("NM_LOG_DIR is not set to a temp folder: run this through its scripts/test-*.sh")
            exit(2)
        }
    }

    static func check<V: Equatable>(_ label: String, _ got: V, _ expected: V) {
        if got == expected {
            print("  ✓ \(label)")
        } else {
            print("  ✗ \(label)")
            print("    got:      \(got)")
            print("    expected: \(expected)")
            failures += 1
        }
    }

    static func checkTrue(_ label: String, _ value: Bool) {
        if value { print("  ✓ \(label)") } else { print("  ✗ \(label)"); failures += 1 }
    }

    static func finish() -> Never {
        if failures == 0 {
            print("\nAll tests passed.")
            exit(0)
        }
        print("\n\(failures) test(s) failed.")
        exit(1)
    }

    static func fixtureURL(_ relative: String) -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("tests/fixtures/ai")
            .appendingPathComponent(relative)
    }

    /// Parsed JSON fixture (dictionary at the top level).
    static func fixture(_ relative: String) -> [String: Any] {
        let data = try! Data(contentsOf: fixtureURL(relative))
        return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    static func text(_ relative: String) -> String {
        try! String(contentsOf: fixtureURL(relative), encoding: .utf8)
    }
}

/// `tests/fake_local_llm.py` on a free port, with its request log in a temp file.
final class FakeServer: @unchecked Sendable {
    let base: String
    let logURL: URL
    private let process: Process
    private let dir: URL

    init(_ flags: [String] = []) {
        dir = FileManager.default.temporaryDirectory.appendingPathComponent("nm-fake-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let portFile = dir.appendingPathComponent("port")
        logURL = dir.appendingPathComponent("log.jsonl")
        process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["python3", "tests/fake_local_llm.py", portFile.path, "--log", logURL.path] + flags
        try! process.run()
        var port = ""
        for _ in 0..<300 {
            if let s = try? String(contentsOf: portFile, encoding: .utf8), !s.isEmpty { port = s; break }
            usleep(10_000)
        }
        precondition(!port.isEmpty, "fake server did not start")
        base = "http://127.0.0.1:\(port.trimmingCharacters(in: .whitespacesAndNewlines))"
    }

    /// One dictionary per request: `method`, `path`, `origin`, `body`.
    func requests() -> [[String: Any]] {
        guard let s = try? String(contentsOf: logURL, encoding: .utf8) else { return [] }
        return s.split(separator: "\n").compactMap {
            try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
        }
    }

    func stop() {
        process.terminate()
        process.waitUntilExit()
        try? FileManager.default.removeItem(at: dir)
    }
}

/// A local TCP port with nothing listening on it (connection refused at once).
func closedPort() -> Int {
    let fd = socket(AF_INET, SOCK_STREAM, 0)
    var addr = sockaddr_in()
    addr.sin_family = sa_family_t(AF_INET)
    addr.sin_addr.s_addr = inet_addr("127.0.0.1")
    addr.sin_port = 0
    var len = socklen_t(MemoryLayout<sockaddr_in>.size)
    withUnsafeMutablePointer(to: &addr) {
        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
            _ = bind(fd, $0, len)
            _ = getsockname(fd, $0, &len)
        }
    }
    let port = Int(UInt16(bigEndian: addr.sin_port))
    close(fd)
    return port
}
