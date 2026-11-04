import Foundation

// The locator, the version and the sign-in state, against the shared fixtures in tests/fixtures/ai/codex/ and the fake
// codex there. No real codex is ever run, and nothing here opens ~/.codex.

@main
@MainActor
enum CodexLocatorTests {
    static func main() async {
        DispatchQueue.global().asyncAfter(deadline: .now() + 120) { print("timed out"); exit(3) }
        searchOrder()
        versions()
        loginStatus()
        await realChecks()
        await checkEnvironment()
        #if DEBUG
        await debugOverride()
        #endif
        T.finish()
    }

    // MARK: - locator-cases.json

    static func searchOrder() {
        T.section("Where codex is looked for (locator-cases.json)")
        let data = T.fixture("codex/locator-cases.json")
        for c in data["cases"] as! [[String: Any]] where (c["platform"] as! String) != "windows" {
            let name = c["name"] as! String
            let existing = Set(c["executables"] as! [String])
            var asked = false
            let found = CodexLocator.find(home: c["home"] as! String, environment: c["env"] as! [String: String],
                                          isExecutable: { existing.contains($0) },
                                          loginShell: { asked = true; return c["loginShell"] as? String })
            T.check(name, found.path, c["expect"] as? String)
            T.check("\(name): the login shell is asked only when nothing earlier exists", asked, c["loginShellCalled"] as! Bool)
        }
        print("  (the Windows cases are run by F3a2-tauri)")
    }

    // MARK: - versions.json

    static func versions() {
        T.section("Versions (versions.json)")
        let data = T.fixture("codex/versions.json")
        T.check("the pinned minimum", CodexLocator.minimumVersion, data["minimum"] as! [Int])
        for c in data["parse"] as! [[String: Any]] {
            T.check("parse \(c["text"] as! String)", CodexLocator.parseVersion(c["text"] as! String), c["expect"] as? [Int])
        }
        for c in data["check"] as! [[String: Any]] {
            let expect: CodexLocator.VersionCheck = switch c["expect"] as! String {
            case "ok": .ok
            case "old": .old
            default: .unknown
            }
            // A JSON null in the case means nil; a case without the key uses the file's minimum.
            let version = c["version"] as? [Int]
            let minimum = (c["minimum"] ?? data["minimum"]) as? [Int]
            T.check("check \(version.map { $0.map(String.init).joined(separator: ".") } ?? "nil")",
                    CodexLocator.check(version: version, minimum: minimum), expect)
        }
    }

    // MARK: - login-status.json

    static func loginStatus() {
        T.section("Sign-in state (login-status.json)")
        let data = T.fixture("codex/login-status.json")
        for c in data["cases"] as! [[String: Any]] {
            let exit = (c["exit"] as? NSNumber).map { Int32(truncating: $0) }
            let got = CodexLocator.login(exit: exit, stdout: c["stdout"] as! String, stderr: c["stderr"] as? String ?? "")
            let e = c["expect"] as! [String: Any]
            let expect: CodexLocator.Login = switch e["state"] as! String {
            case "signedIn": .signedIn(mode: e["mode"] as! String)
            case "signedOut": .signedOut
            default: .unknown
            }
            T.check(c["name"] as! String, got, expect)
        }
    }

    // MARK: - The fake, end to end

    static func realChecks() async {
        T.section("The checks, against the fake codex")
        let fake = T.fixtureURL("codex/fake_codex.py").path
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("nm-codex-locator-\(UUID().uuidString)")
        try! FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: home) }
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        func status(_ extra: [String: String]) async -> CodexStatus {
            let env = ["PATH": path, "HOME": home.path].merging(extra) { $1 }
            return await CodexLocator.statusOf(executable: fake, environment: env)
        }
        let ok = await status([:])
        T.check("signed in with a plan", ok.state, .signedIn)
        T.check("its mode is chatgpt", ok.mode, "chatgpt")
        T.check("its version is 0.165.0", ok.version, "0.165.0")
        let out = await status(["NM_FAKE_CODEX_LOGIN_EXIT": "1", "NM_FAKE_CODEX_LOGIN_STDOUT": "Not logged in"])
        T.check("signed out", out.state, .signedOut)
        T.check("signed out has no mode", out.mode, nil)
        // Some builds print the sign-in line on stderr only: both streams are read, the exit code still decides.
        let errLine = await status(["NM_FAKE_CODEX_LOGIN_STREAM": "stderr"])
        T.check("the sign-in line on stderr only: signed in", errLine.state, .signedIn)
        T.check("the sign-in line on stderr only: its mode is chatgpt", errLine.mode, "chatgpt")
        let errOut = await status(["NM_FAKE_CODEX_LOGIN_STREAM": "stderr", "NM_FAKE_CODEX_LOGIN_EXIT": "1",
                                   "NM_FAKE_CODEX_LOGIN_STDOUT": "Not logged in"])
        T.check("the sign-out line on stderr only: signed out", errOut.state, .signedOut)
        T.check("the sign-out line on stderr only: no mode", errOut.mode, nil)
        let old = await status(["NM_FAKE_CODEX_VERSION": "codex-cli 0.98.0"])
        T.check("too old", old.state, .tooOld)
        T.check("too old keeps its version", old.version, "0.98.0")
        let mail = await status(["NM_FAKE_CODEX_LOGIN_STDOUT": "Logged in as zoe@example.com using ChatGPT"])
        T.check("an e-mail on stdout is never kept", String(describing: mail).contains("@"), false)
        T.check("the mail case still reads its mode", mail.mode, "chatgpt")
        T.check("the executable holds no @", mail.executable?.contains("@") ?? false, false)
        T.check("the version holds no @", mail.version?.contains("@") ?? false, false)
        let missing = await CodexLocator.statusOf(executable: "/nonexistent/codex", environment: ["PATH": path])
        T.check("a program that cannot run is not installed", missing.state, .notInstalled)
    }

    // MARK: - The checks' environment

    static func checkEnvironment() async {
        T.section("The checks run without the OpenAI names, and keep CODEX_HOME and PATH (statusOf)")
        let fake = T.fixtureURL("codex/fake_codex.py").path
        let log = FileManager.default.temporaryDirectory.appendingPathComponent("nm-codex-env-\(UUID().uuidString).jsonl").path
        defer { try? FileManager.default.removeItem(atPath: log) }
        let path = ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin"
        let env = ["PATH": path, "HOME": NSTemporaryDirectory(), "NM_FAKE_CODEX_LOG": log, "CODEX_HOME": "/nm/codex-home-test",
                   "OPENAI_API_KEY": "sk-FAKE", "CODEX_API_KEY": "ck-FAKE", "OPENAI_BASE_URL": "https://proxy.example"]
        _ = await CodexLocator.statusOf(executable: fake, environment: env)
        let calls = ((try? String(contentsOfFile: log, encoding: .utf8)) ?? "").split(separator: "\n").compactMap {
            try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
        }
        T.check("both checks ran", calls.count, 2)
        // The two run in parallel, so their order in the log is not fixed.
        T.check("the version check and the sign-in check", calls.map { ($0["argv"] as? [String] ?? []).joined(separator: " ") }.sorted(),
                ["--version", "login status"])
        for call in calls {
            let seen = call["env"] as? [String: String] ?? [:]
            let argv = (call["argv"] as? [String] ?? []).joined(separator: " ")
            T.checkTrue("\(argv): no OpenAI key, Codex key or base URL reaches it",
                        ["OPENAI_API_KEY", "CODEX_API_KEY", "OPENAI_BASE_URL"].allSatisfy { seen[$0] == nil })
            T.checkTrue("\(argv): CODEX_HOME and PATH are kept",
                        seen["CODEX_HOME"] == "/nm/codex-home-test" && seen["PATH"] != nil)
        }
    }

    // MARK: - The Debug override

    #if DEBUG
    static func debugOverride() async {
        T.section("The Debug override")
        let found = await CodexLocator.locate(environment: ["NM_CODEX_PATH_OVERRIDE": "/x/fake"])
        T.check("NM_CODEX_PATH_OVERRIDE wins in a Debug build", found, "/x/fake")
    }
    #endif
}
