import Foundation

// The runner against the fake `claude` (tests/fixtures/ai/claude-code/fake_claude.py). No real claude is ever run.

@main
@MainActor
enum ClaudeCodeProviderTests {
    static let sid = "11111111-1111-4111-8111-111111111111"
    static let marker = "ZZ-LEAK-MARKER-7391"
    static var fixtures: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("tests/fixtures/ai/claude-code")
    }
    static var fake: String { fixtures.appendingPathComponent("fake_claude.py").path }

    /// A scratch folder of this test's own, removed at the end.
    final class Scratch: @unchecked Sendable {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nm-claude-test-\(UUID().uuidString)")
        init() { try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
        func folder(_ name: String) -> String {
            let url = root.appendingPathComponent(name, isDirectory: true)
            try! FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
            return url.path
        }
        func file(_ name: String) -> String { root.appendingPathComponent(name).path }
        deinit { try? FileManager.default.removeItem(at: root) }
    }

    struct Outcome: @unchecked Sendable {   // `calls` holds parsed JSON
        var chunks: [ChatChunk] = []
        var error: AIError?
        var calls: [[String: Any]] = []
        var text: String { chunks.compactMap { if case .text(let t) = $0 { t } else { nil } }.joined() }
        var steps: [ChatStep] {
            var out: [ChatStep] = []
            for case .step(let s) in chunks {
                if let i = out.firstIndex(where: { $0.id == s.id }) { out[i] = s } else { out.append(s) }
            }
            return out
        }
        /// The one `claude -p` call (not a --version or auth call).
        var turn: [String: Any]? { calls.first { ($0["argv"] as? [String])?.first == "-p" } }
    }

    static func request(_ text: String = "Hello") -> ChatRequest {
        ChatRequest(model: "sonnet", system: "", messages: [.init(role: .user, parts: [.text(text)])])
    }

    static func readLog(_ path: String) -> [[String: Any]] {
        ((try? String(contentsOfFile: path, encoding: .utf8)) ?? "").split(separator: "\n").compactMap {
            try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
        }
    }

    static func provider(_ scratch: Scratch, transcript: String?, level: ClaudeCodeLevel = .chatOnly, resume: Bool = false,
                         session: String = sid, extra: [String: String] = [:], log: String? = nil,
                         timings: ClaudeProcessTimings = ClaudeProcessTimings(startup: 20, interruptGrace: 2, terminateGrace: 2, drain: 1),
                         executable: String? = nil) -> ClaudeCodeProvider {
        var env = ["PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin",
                   "NM_FAKE_CLAUDE_LOG": log ?? scratch.file("log.jsonl"),
                   "CANARY": "kept",
                   // What must never reach the run:
                   "ANTHROPIC_API_KEY": "sk-ant-FAKE", "ANTHROPIC_AUTH_TOKEN": "tok-FAKE",
                   "CLAUDE_CODE_OAUTH_TOKEN": "oauth-FAKE", "ANTHROPIC_PROFILE": "work", "CLAUDE_CODE_USE_BEDROCK": "1"]
        if let transcript { env["NM_FAKE_CLAUDE_TRANSCRIPT"] = fixtures.appendingPathComponent("transcripts/\(transcript)").path }
        env.merge(extra) { $1 }
        return ClaudeCodeProvider(executable: executable ?? fake,
                                  turn: ClaudeCodeTurn(level: level, sessionID: session, resume: resume),
                                  chatFolder: scratch.folder("chat"), baseEnvironment: env, timings: timings)
    }

    static func collect(_ provider: ClaudeCodeProvider, _ req: ChatRequest = request(), log: String) async -> Outcome {
        var out = Outcome()
        do {
            for try await chunk in provider.stream(req) { out.chunks.append(chunk) }
        } catch {
            out.error = error as? AIError ?? AIError(kind: .server)
        }
        out.calls = readLog(log)
        return out
    }

    static func alive(_ pidFile: String) -> Bool {
        guard let text = try? String(contentsOfFile: pidFile, encoding: .utf8), let pid = Int32(text) else { return false }
        return kill(pid, 0) == 0
    }

    static func waitUntilGone(_ files: [String], seconds: Double) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if files.allSatisfy({ !alive($0) }) { return true }
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
        return false
    }

    static func main() async {
        // A hung run would hang the build: stop the whole program instead.
        DispatchQueue.global().asyncAfter(deadline: .now() + 180) { print("timed out"); exit(3) }
        let scratch = Scratch()
        await turns(scratch)
        await failures(scratch)
        await refusals(scratch)
        await stopping(scratch)
        await concurrency(scratch)
        await folders(scratch)
        await leaks(scratch)
        T.finish()
    }

    // MARK: - One turn

    static func turns(_ s: Scratch) async {
        T.section("A turn")
        let log = s.file("turn.jsonl")
        let p = provider(s, transcript: "success.jsonl", log: log)
        let out = await collect(p, log: log)
        T.check("the reply", out.text, "Bonjour Zoé, hello! 🐱")
        T.check("no error", out.error == nil, true)
        let turn = out.turn!
        T.check("the command line is the engine's", turn["argv"] as? [String], ClaudeCodeCommand.arguments(p.turn))
        T.check("it runs in the chat folder", URL(fileURLWithPath: turn["cwd"] as! String).resolvingSymlinksInPath().path,
                URL(fileURLWithPath: p.chatFolder).resolvingSymlinksInPath().path)
        let env = turn["env"] as! [String: String]
        T.check("what outranks the plan login is gone",
                ["ANTHROPIC_API_KEY", "ANTHROPIC_AUTH_TOKEN", "CLAUDE_CODE_OAUTH_TOKEN", "ANTHROPIC_PROFILE", "CLAUDE_CODE_USE_BEDROCK"].filter { env[$0] != nil }, [])
        T.check("the rest of the environment is kept", env["CANARY"], "kept")
        let stdin = try! JSONSerialization.jsonObject(with: Data((turn["stdin"] as! String).utf8)) as! [String: Any]
        let blocks = (stdin["message"] as! [String: Any])["content"] as! [[String: Any]]
        T.check("the message goes in on stdin, and stdin was closed (the fake reads to its end)", blocks.first?["text"] as? String, "Hello")
        T.check("the engine's report", out.chunks.contains { if case .engine(let r) = $0 { r.model == "claude-sonnet-5-5" && r.paidBy == .plan } else { false } }, true)

        let tools = await collect(provider(s, transcript: "tool-use.jsonl", level: .readOnly(folder: s.folder("project")), resume: true, log: s.file("tools.jsonl")), log: s.file("tools.jsonl"))
        T.check("steps arrive as rows that update", tools.steps.map { "\($0.id):\($0.state.rawValue)" }, ["toolu_01A:done", "toolu_01B:failed"])
        T.check("and the text reads as paragraphs", tools.text, "I'll read the README.\n\nIt says it is a tiny demo.")
        T.check("a later turn resumes the session", (tools.turn?["argv"] as? [String])?.contains("--resume"), true)
    }

    // MARK: - Failures

    static func failures(_ s: Scratch) async {
        T.section("Failures")
        func run(_ transcript: String, exit: String = "1", stderr: String = "", name: String) async -> Outcome {
            let log = s.file("f-\(name).jsonl")
            return await collect(provider(s, transcript: transcript, extra: ["NM_FAKE_CLAUDE_EXIT": exit, "NM_FAKE_CLAUDE_STDERR": stderr], log: log), log: log)
        }
        let signedOut = await run("signed-out.jsonl", name: "so")
        T.check("signed out", signedOut.error?.code, ClaudeCodeError.signedOut)
        let limit = await run("plan-limit.jsonl", name: "pl")
        T.check("the plan's limit", [limit.error?.kind.rawValue, limit.error?.code], ["billing", ClaudeCodeError.planLimit])
        T.check("and when it resets", limit.error?.resetsAt, Date(timeIntervalSince1970: 1791301500))
        let offline = await run("offline.jsonl", name: "off")
        T.check("offline", offline.error?.code, ClaudeCodeError.offline)
        let crash = await run("crash.jsonl", exit: "2", name: "cr")
        T.check("a cut stream keeps what was said", crash.text, "Let me look")
        T.check("and is an interrupted reply", [crash.error?.kind.rawValue, crash.error?.code], ["interrupted", ClaudeCodeError.crashed])
        let git = await run("empty.jsonl", stderr: "Claude Code on Windows requires git-bash", name: "git")
        T.check("Git for Windows missing, from stderr", git.error?.code, ClaudeCodeError.needsGit)

        let none = await collect(provider(s, transcript: nil, executable: "/nonexistent/claude"), log: s.file("none.jsonl"))
        T.check("no such program is 'not installed'", [none.error?.kind.rawValue, none.error?.code], ["unreachable", ClaudeCodeError.missing])
        let gone = await collect(provider(s, transcript: "success.jsonl", level: .readOnly(folder: "/nonexistent-folder-zz")), log: s.file("gone.jsonl"))
        T.check("a folder that is not there", [gone.error?.kind.rawValue, gone.error?.code], ["bad_request", ClaudeCodeError.folderMissing])
        T.check("and nothing was started", gone.turn == nil, true)

        let quiet = provider(s, transcript: nil, extra: ["NM_FAKE_CLAUDE_HANG_AFTER": "0", "NM_FAKE_CLAUDE_PIDFILE": s.file("quiet.pid")],
                             log: s.file("quiet.jsonl"), timings: ClaudeProcessTimings(startup: 0.6, interruptGrace: 0.2, terminateGrace: 0.2, drain: 0.2))
        let silent = await collect(quiet, log: s.file("quiet.jsonl"))
        T.check("a run that never says anything times out", silent.error?.kind, .timeout)
        T.checkTrue("and is stopped", await waitUntilGone([s.file("quiet.pid")], seconds: 5))
    }

    // MARK: - No tools

    /// `collect`, but gives up after `seconds` and returns nil. A run still going then is left alone on purpose: the
    /// check that uses it fails, and the caller kills the process, rather than the suite hanging on a stream that never ends.
    static func collectOrGiveUp(within seconds: Double, _ provider: ClaudeCodeProvider, log: String) async -> Outcome? {
        final class Once: @unchecked Sendable {
            private let lock = NSLock()
            private var done = false
            func claim() -> Bool { lock.withLock { if done { return false }; done = true; return true } }
        }
        return await withCheckedContinuation { (resume: CheckedContinuation<Outcome?, Never>) in
            let once = Once()
            Task { let out = await collect(provider, log: log); if once.claim() { resume.resume(returning: out) } }
            Task {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                if once.claim() { resume.resume(returning: nil) }
            }
        }
    }

    static func refusals(_ s: Scratch) async {
        T.section("No tools: a run that shows a tool is stopped")
        let pid = s.file("leaky.pid"), log = s.file("leaky.jsonl")
        // Two lines out before the hang: ui_invalidate, then the leaky init, which refuses. One line would hang before init.
        let leaky = provider(s, transcript: "no-tools-leaky.jsonl", level: .noTools,
                             extra: ["NM_FAKE_CLAUDE_HANG_AFTER": "2", "NM_FAKE_CLAUDE_PIDFILE": pid], log: log)
        let out = await collectOrGiveUp(within: 10, leaky, log: log)
        T.check("the run is reported as nm_tools_present", [out?.error?.kind.rawValue, out?.error?.code],
                ["bad_request", ClaudeCodeError.toolsPresent])
        T.check("and no text reaches the chat", out?.text, "")
        // Not even the engine report: it would confirm a session that was killed right after init (ClaudeService would resume it).
        T.checkTrue("and no chunk at all reaches the chat, the engine report included", out?.chunks.isEmpty == true)
        let gone = await waitUntilGone([pid], seconds: 5)
        T.checkTrue("the process is stopped at once, not left running", gone)
        if !gone, let text = try? String(contentsOfFile: pid, encoding: .utf8), let number = Int32(text) {
            kill(number, SIGKILL)   // only ever after a failed check: it is still running, so the number is still its own
        }
        T.checkTrue("a bad request never falls back to another provider", AIErrorKind.badRequest.isTemporary == false)

        let clean = await collect(provider(s, transcript: "no-tools.jsonl", level: .noTools, log: s.file("no-tools.jsonl")),
                                  log: s.file("no-tools.jsonl"))
        T.check("a run with no tools answers", clean.text, "Fixed text.")
        T.checkTrue("and it is not an error", clean.error == nil)
    }

    // MARK: - Stop

    static func stopping(_ s: Scratch) async {
        T.section("Stop")
        for stubborn in [false, true] {
            let tag = stubborn ? "stubborn" : "polite"
            let pid = s.file("\(tag).pid"), child = s.file("\(tag).child")
            var extra = ["NM_FAKE_CLAUDE_HANG_AFTER": "8", "NM_FAKE_CLAUDE_PIDFILE": pid, "NM_FAKE_CLAUDE_CHILD_PIDFILE": child]
            if stubborn { extra["NM_FAKE_CLAUDE_STUBBORN"] = "1" }
            let p = provider(s, transcript: "tool-use.jsonl", extra: extra, log: s.file("\(tag).jsonl"),
                             timings: ClaudeProcessTimings(startup: 20, interruptGrace: 0.3, terminateGrace: 0.3, drain: 0.3))
            var sawStep = false
            do {
                for try await chunk in p.stream(request()) {
                    if case .step = chunk {
                        sawStep = true
                        // The fake writes the pid of the child it started a moment after its step line: wait for it, so
                        // that "gone" below means something.
                        var waited = 0
                        while !FileManager.default.fileExists(atPath: child), waited < 250 {
                            try? await Task.sleep(nanoseconds: 20_000_000)
                            waited += 1
                        }
                        T.checkTrue("\(tag): the process and its child were both running when Stop came", alive(pid) && alive(child))
                        break
                    }
                }
            } catch {}
            T.checkTrue("\(tag): a step was running when Stop came", sawStep)
            let started = Date()
            T.checkTrue("\(tag): the process and what it started are gone", await waitUntilGone([pid, child], seconds: 8))
            print("    (\(String(format: "%.1f", Date().timeIntervalSince(started))) s)")
        }
    }

    // MARK: - Two at once

    static func concurrency(_ s: Scratch) async {
        T.section("Two runs at once")
        let aLog = s.file("a.jsonl"), bLog = s.file("b.jsonl")
        let a = provider(s, transcript: "success.jsonl", session: "aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa", log: aLog)
        let b = provider(s, transcript: "tool-use.jsonl", level: .readOnly(folder: s.folder("other")), session: "bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb", log: bLog)
        async let first = collect(a, log: aLog)
        async let second = collect(b, log: bLog)
        let (one, two) = await (first, second)
        T.check("each run has its own reply", [one.text, two.text], ["Bonjour Zoé, hello! 🐱", "I'll read the README.\n\nIt says it is a tiny demo."])
        T.check("and its own session",
                [(one.turn?["argv"] as? [String])?.contains("aaaaaaaa-aaaa-4aaa-8aaa-aaaaaaaaaaaa"),
                 (two.turn?["argv"] as? [String])?.contains("bbbbbbbb-bbbb-4bbb-8bbb-bbbbbbbbbbbb")], [true, true])
        T.check("a chat's steps never reach the other", [one.steps.count, two.steps.count], [0, 2])
    }

    // MARK: - Folders with spaces and non-ASCII characters

    static func folders(_ s: Scratch) async {
        T.section("A folder with spaces and non-ASCII characters")
        let folder = s.folder("Zoé Mes projets/ünï côde")
        let log = s.file("unicode.jsonl")
        let p = provider(s, transcript: "tool-use.jsonl", level: .readOnly(folder: folder), log: log)
        let out = await collect(p, log: log)
        T.check("it works", out.error == nil && out.text.hasSuffix("tiny demo."), true)
        T.check("the process runs in it", URL(fileURLWithPath: out.turn!["cwd"] as! String).resolvingSymlinksInPath().path,
                URL(fileURLWithPath: folder).resolvingSymlinksInPath().path)
        T.checkTrue("and no argument carries it", !(out.turn!["argv"] as! [String]).contains { $0.contains("ünï") })
    }

    // MARK: - Nothing private in the log

    static func leaks(_ s: Scratch) async {
        T.section("Log leak test")
        final class Lines: @unchecked Sendable {
            let lock = NSLock()
            var all: [String] = []
            func add(_ l: String) { lock.withLock { all.append(l) } }
        }
        let lines = Lines()
        AILog.sink.replace { lines.add($0) }
        let folder = s.folder("\(marker)-folder")
        let log = s.file("leak.jsonl")
        for transcript in ["success.jsonl", "plan-limit.jsonl", "crash.jsonl"] {
            let p = provider(s, transcript: transcript, level: .readOnly(folder: folder),
                             extra: ["NM_FAKE_CLAUDE_STDERR": "stderr says \(marker)", "LEAK_ENV": marker, "NM_FAKE_CLAUDE_EXIT": "1"], log: log)
            _ = await collect(p, request("tell me about \(marker)"), log: log)
        }
        let captured = lines.lock.withLock { lines.all }
        T.checkTrue("events were logged", captured.count >= 3)
        T.check("no log line holds the prompt, the folder, stderr or the environment", captured.filter { $0.contains(marker) }, [])
        T.check("and none holds the session id", captured.filter { $0.contains(sid) }, [])
    }
}
