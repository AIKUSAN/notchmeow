import Foundation

// The locator and the two checks, against the shared fixtures and the fake `claude`. No real claude is ever run.

@main
@MainActor
enum ClaudeCodeLocatorTests {
    static var fixtures: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("tests/fixtures/ai/claude-code")
    }

    static func main() async {
        DispatchQueue.global().asyncAfter(deadline: .now() + 120) { print("timed out"); exit(3) }
        searchOrder()
        versions()
        authStatus()
        await realChecks()
        await signIn()
        T.finish()
    }

    // MARK: - locator-cases.json

    static func searchOrder() {
        T.section("Where claude is looked for (locator-cases.json)")
        let data = T.fixture("claude-code/locator-cases.json")
        for c in data["cases"] as! [[String: Any]] where (c["platform"] as! String) != "windows" {
            let existing = Set(c["executables"] as! [String])
            var asked = false
            let found = ClaudeCodeLocator.find(home: c["home"] as! String, environment: c["env"] as! [String: String],
                                               isExecutable: { existing.contains($0) },
                                               loginShell: { asked = true; return c["loginShell"] as? String })
            T.check(c["name"] as! String, found.path, c["expect"] as? String)
            T.check("\(c["name"] as! String): the login shell is asked only when nothing earlier exists", asked, c["loginShellCalled"] as! Bool)
        }
        print("  (the Windows cases are run by the Rust tests)")
    }

    // MARK: - versions.json

    static func versions() {
        T.section("Versions (versions.json)")
        let data = T.fixture("claude-code/versions.json")
        T.check("the pinned minimum", ClaudeCodeLocator.minimumVersion, data["minimum"] as! [Int])
        for c in data["parse"] as! [[String: Any]] {
            T.check("parse \(c["text"] as! String)", ClaudeCodeLocator.parseVersion(c["text"] as! String), c["expect"] as? [Int])
        }
        for c in data["check"] as! [[String: Any]] {
            let expect: ClaudeCodeLocator.VersionCheck = switch c["expect"] as! String { case "ok": .ok; case "tooOld": .tooOld; default: .unknown }
            T.check("check \(String(describing: c["version"]))", ClaudeCodeLocator.check(version: c["version"] as? [Int]), expect)
        }
    }

    // MARK: - auth-status.json

    static func authStatus() {
        T.section("Auth status (auth-status.json)")
        let data = T.fixture("claude-code/auth-status.json")
        for c in data["cases"] as! [[String: Any]] {
            let got = ClaudeCodeLocator.parseAuth(exit: (c["exit"] as? NSNumber).map { Int32(truncating: $0) }, stdout: c["stdout"] as! String)
            let e = c["expect"] as! [String: Any]
            let expect: ClaudeCodeLocator.AuthResult = switch e["state"] as! String {
            case "signedIn": .signedIn(authMethod: e["authMethod"] as? String)
            case "signedOut": .signedOut
            default: .unknown
            }
            T.check(c["name"] as! String, got, expect)
        }
    }

    // MARK: - The fake, end to end

    static func realChecks() async {
        T.section("The checks, against the fake claude")
        let fake = fixtures.appendingPathComponent("fake_claude.py").path
        #if DEBUG
        let overridden = await ClaudeCodeLocator.locate(environment: ["NM_CLAUDE_CODE_PATH_OVERRIDE": fake])
        T.check("a Debug build can be pointed at the fake", overridden, fake)
        #endif
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        func status(_ extra: [String: String]) async -> ClaudeCodeStatus {
            let env = ["PATH": path, "HOME": NSHomeDirectory(), "ANTHROPIC_API_KEY": "sk-ant-FAKE"].merging(extra) { $1 }
            return await ClaudeCodeLocator.statusOf(executable: fake, environment: env)
        }
        let ok = await status([:])
        T.check("signed in with a plan", [ok.state == .signedIn, ok.authMethod == "claude.ai", ok.version == "2.1.211"], [true, true, true])
        let out = await status(["NM_FAKE_CLAUDE_AUTH_EXIT": "1", "NM_FAKE_CLAUDE_AUTH_JSON": "{\"authMethod\":\"none\"}"])
        T.check("signed out", out.state, .signedOut)
        let old = await status(["NM_FAKE_CLAUDE_VERSION": "2.1.100 (Claude Code)"])
        T.check("too old", old.state, .tooOld)
        let odd = await status(["NM_FAKE_CLAUDE_VERSION": "hello"])
        T.check("not Claude Code at all", odd.state, .notInstalled)
        let missing = await ClaudeCodeLocator.statusOf(executable: "/nonexistent/claude", environment: ["PATH": path])
        T.check("a program that cannot run is unknown", missing.state, .notInstalled)
    }

    // MARK: - Sign in

    static func signIn() async {
        T.section("Sign in")
        T.check("quoting", ClaudeCodeSignIn.quoted("/Users/O'Brien/Zoé Ünï/.local/bin/claude"), "'/Users/O'\\''Brien/Zoé Ünï/.local/bin/claude'")
        // The script really runs `auth login` with a path full of awkward characters.
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nm-signin-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("O'Brien Zoé Ünï/bin")
        try! FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let copy = folder.appendingPathComponent("claude").path
        try! FileManager.default.copyItem(atPath: fixtures.appendingPathComponent("fake_claude.py").path, toPath: copy)
        let log = root.appendingPathComponent("log.jsonl").path
        guard let script = ClaudeCodeSignIn.write(executable: copy, into: root.appendingPathComponent("scripts").path) else {
            return T.checkTrue("the script was written", false)
        }
        T.check("the script is executable", FileManager.default.isExecutableFile(atPath: script), true)
        let env = ["PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin", "NM_FAKE_CLAUDE_LOG": log]
        let ran = await ClaudeCodeCLI.run("/bin/zsh", [script], environment: env, timeout: 20)
        T.check("it ran", ran.status, 0)
        let calls = ((try? String(contentsOfFile: log, encoding: .utf8)) ?? "").split(separator: "\n").compactMap {
            try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
        }
        T.check("and it called `auth login`", calls.first?["argv"] as? [String], ["auth", "login"])
    }
}
