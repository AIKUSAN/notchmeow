import Foundation

// The Codex provider against the fake codex (tests/fixtures/ai/codex/fake_codex.py). No real codex is ever run, and
// nothing reads ~/.codex: the sentinel credentials file is inside this test's own scratch HOME, and only its path and
// mode are checked, never its contents.

@main
@MainActor
enum CodexProviderTests {
    static let marker = "ZZ-LEAK-MARKER-4821"
    static let timings = ClaudeProcessTimings(startup: 20, interruptGrace: 2, terminateGrace: 2, drain: 1)
    static var fixtures: URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath).appendingPathComponent("tests/fixtures/ai/codex")
    }
    static var fake: String { fixtures.appendingPathComponent("fake_codex.py").path }

    /// A scratch folder of this test's own, removed at the end.
    final class Scratch: @unchecked Sendable {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("nm-codex-test-\(UUID().uuidString)")
        init() { try! FileManager.default.createDirectory(at: root, withIntermediateDirectories: true) }
        var chat: String { root.appendingPathComponent("codex-chat").path }
        var images: String { root.appendingPathComponent("codex-images").path }
        var home: String { root.appendingPathComponent("home").path }
        var codexHome: String { root.appendingPathComponent("codex-home").path }
        func file(_ name: String) -> String { root.appendingPathComponent(name).path }
        deinit {
            // The chat folder is 0500: it is made writable again before the scratch folder is removed.
            try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: chat)
            try? FileManager.default.removeItem(at: root)
        }
    }

    struct Outcome: @unchecked Sendable {
        var chunks: [ChatChunk] = []
        var error: AIError?
        /// Every JSON line the fake wrote to its log (one per run, and a write it recorded).
        var calls: [[String: Any]] = []
        var text: String { chunks.compactMap { if case .text(let t) = $0 { t } else { nil } }.joined() }
        var textChunks: Int { chunks.filter { if case .text = $0 { true } else { false } }.count }
        /// The one `codex exec` run in the log.
        var turn: [String: Any]? { calls.first { $0["argv"] != nil } }
    }

    static func request(_ parts: [ChatRequest.Part] = [.text("Hello")]) -> ChatRequest {
        ChatRequest(model: "", system: "", messages: [.init(role: .user, parts: parts)])
    }

    /// A message with two pictures after its words.
    static func pictureRequest() -> ChatRequest {
        request([.text("What is in these?"),
                 .image(mime: "image/png", data: Data([0x89, 0x50, 0x4E, 0x47])),
                 .image(mime: "image/png", data: Data([1, 2, 3]))])
    }

    static func readLog(_ path: String) -> [[String: Any]] {
        ((try? String(contentsOfFile: path, encoding: .utf8)) ?? "").split(separator: "\n").compactMap {
            try? JSONSerialization.jsonObject(with: Data($0.utf8)) as? [String: Any]
        }
    }

    /// The argv the fixture gives for a named case of expected-args.json.
    static func expectedArgs(_ name: String) -> [String] {
        let cases = T.fixture("codex/expected-args.json")["cases"] as! [[String: Any]]
        return cases.first { $0["name"] as? String == name }!["expect"] as! [String]
    }

    static func real(_ path: String) -> String { URL(fileURLWithPath: path).resolvingSymlinksInPath().path }

    static func entries(_ folder: String) -> [String] { (try? FileManager.default.contentsOfDirectory(atPath: folder)) ?? [] }

    /// The picture folder exists (a turn with pictures made it) and holds nothing: an empty listing of a missing folder proves nothing.
    static func emptyPictureFolder(_ s: Scratch) -> Bool {
        FileManager.default.fileExists(atPath: s.images) && entries(s.images).isEmpty
    }

    static func mode(_ path: String) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.posixPermissions] as? Int
    }

    /// Whether a process is still there. A missing or bad pid is not alive: kill(0, _) would signal our own group.
    static func alive(_ pid: Int32?) -> Bool {
        guard let pid, pid > 0 else { return false }
        return kill(pid, 0) == 0
    }

    static func pidFile(_ path: String) -> Int32? {
        Int32(((try? String(contentsOfFile: path, encoding: .utf8)) ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    /// Polls `condition` for at most `seconds`; true as soon as it holds.
    static func waitFor(seconds: Double, _ condition: () -> Bool) async -> Bool {
        let end = Date().addingTimeInterval(seconds)
        while Date() < end {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 20_000_000)
        }
        return condition()
    }

    static func environment(_ s: Scratch, log: String) -> [String: String] {
        [// What the run needs:
         "PATH": ProcessInfo.processInfo.environment["PATH"] ?? "/usr/bin:/bin",
         "NM_FAKE_CODEX_LOG": log, "CANARY": "kept",
         "CODEX_HOME": s.codexHome, "HOME": s.home,
         // What must never reach the run:
         "OPENAI_API_KEY": "sk-FAKE", "CODEX_API_KEY": "ck-FAKE", "OPENAI_BASE_URL": "https://proxy.example",
         "OPENAI_ORG_ID": "org-FAKE", "OPENAI_PROJECT_ID": "proj-FAKE", "OPENAI_ANYTHING_NEW": "x"]
    }

    static func provider(_ s: Scratch, level: CodexLevel = .chat, model: String? = nil, transcript: String,
                         log: String, extra: [String: String] = [:], executable: String? = nil,
                         knownState: CodexStatus.State = .unknown,
                         sweeper: CodexImageSweeper = .shared) -> CodexProvider {
        var env = environment(s, log: log)
        env["NM_FAKE_CODEX_TRANSCRIPT"] = fixtures.appendingPathComponent("transcripts/\(transcript)").path
        env.merge(extra) { $1 }
        return CodexProvider(executable: executable ?? fake, level: level, model: model, knownState: knownState,
                             chatFolder: s.chat, imageFolder: s.images, imageSweeper: sweeper,
                             baseEnvironment: env, timings: timings)
    }

    static func collect(_ provider: CodexProvider, _ req: ChatRequest = request(), log: String) async -> Outcome {
        var out = Outcome()
        do {
            for try await chunk in provider.stream(req) { out.chunks.append(chunk) }
        } catch {
            out.error = error as? AIError ?? AIError(kind: .server)
        }
        out.calls = readLog(log)
        return out
    }

    /// The sentinel: a credentials file that no run may open, read or change. Its mode is 0, so an open would fail.
    /// It guards writes and chmod only. That no source reads ~/.codex is the Task 10 grep over NotchBuddy/Sources, not this test.
    static func makeSentinel(_ s: Scratch) -> String {
        let dir = s.home + "/.codex"
        try! FileManager.default.createDirectory(atPath: dir, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        let staged = s.file("staged-auth")
        try! Data("sentinel".utf8).write(to: URL(fileURLWithPath: staged))
        let path = dir + "/auth.json"
        try! FileManager.default.moveItem(atPath: staged, toPath: path)
        try! FileManager.default.setAttributes([.posixPermissions: 0o000], ofItemAtPath: path)
        return path
    }

    static func main() async {
        // A hung run would hang the build: stop the whole program instead.
        DispatchQueue.global().asyncAfter(deadline: .now() + 180) { print("timed out"); exit(3) }
        await body()
        T.finish()
    }

    /// Everything, in a function of its own so that the scratch folder is removed before the program exits.
    static func body() async {
        let s = Scratch()
        let sentinel = makeSentinel(s)
        factory()
        await turns(s)
        await levels(s)
        await knownStates(s)
        await sweep(s)
        await pictures(s)
        await failures(s)
        await forbidden(s)
        await oversize(s)
        await missing(s)
        await stop(s)
        await watchdog(s)
        await quit(s)
        await noFinalNewline(s)
        T.section("The sentinel")
        T.checkTrue("auth.json is untouched: still there, mode 0", FileManager.default.fileExists(atPath: sentinel) && mode(sentinel) == 0o000)
        await leaks(s)
    }

    // MARK: - The factory

    static func factory() {
        T.section("The factory")
        var factory = ProviderFactory()
        let target = ChatTarget(provider: .codexPlan, model: "", placement: .cloud)
        T.checkTrue("without a setup the plan is unavailable", factory.make(target) is UnavailableProvider)
        factory.codex = CodexSetup(executable: "/x/codex", level: .chat, model: nil)
        guard let made = factory.make(target) as? CodexProvider else {
            T.checkTrue("with a setup the factory makes a Codex provider", false)
            return
        }
        T.check("with a setup it runs that program", made.executable, "/x/codex")
        T.check("at that level", made.level, .chat)
    }

    // MARK: - A turn

    static func turns(_ s: Scratch) async {
        T.section("A chat-only turn")
        let log = s.file("chat.jsonl")
        let req = request()
        let out = await collect(provider(s, transcript: "chat.jsonl", log: log), req, log: log)
        T.check("no error", out.error == nil, true)
        T.check("the text, then the finish, and no engine or step", out.chunks,
                [.text("Hello there, hope you’re doing well!"), .finish(.stop)])
        let turn = out.turn
        T.check("the command line is the chat-only one", turn?["argv"] as? [String], expectedArgs("chat only, one turn, no model"))
        T.check("it runs in the chat folder", real(turn?["cwd"] as? String ?? ""), real(s.chat))
        T.check("the prompt goes on stdin", turn?["stdin"] as? String, CodexPrompt.build(req).text)
        let env = turn?["env"] as? [String: String] ?? [:]
        T.check("the OpenAI names and the Codex key never reach the run",
                env.keys.filter { $0 == "CODEX_API_KEY" || $0.hasPrefix("OPENAI_") }.sorted(), [])
        T.check("CODEX_HOME is kept", env["CODEX_HOME"], s.codexHome)
        T.check("the rest of the environment is kept", env["CANARY"], "kept")

        T.section("The chat folder")
        let writeLog = s.file("write.jsonl")
        _ = await collect(provider(s, transcript: "chat.jsonl", log: writeLog, extra: ["NM_FAKE_CODEX_TRY_WRITE": "made.txt"]), log: writeLog)
        T.checkTrue("the folder refused the write", readLog(writeLog).contains { ($0["write"] as? String) == "refused" })
        T.checkTrue("no file was made in it", !FileManager.default.fileExists(atPath: s.chat + "/made.txt"))
        T.check("the chat folder is mode 0500", mode(s.chat), 0o500)
    }

    // MARK: - Levels and the model

    static func levels(_ s: Scratch) async {
        T.section("Levels and the model")
        let quickLog = s.file("quick.jsonl")
        let quick = await collect(provider(s, level: .noTools, transcript: "chat.jsonl", log: quickLog), log: quickLog)
        T.check("a quick action runs at none, with the same flags", quick.turn?["argv"] as? [String],
                expectedArgs("quick actions (none), no model"))

        let modelLog = s.file("model.jsonl")
        _ = await collect(provider(s, model: "gpt-5.5", transcript: "chat.jsonl", log: modelLog), log: modelLog)
        T.check("a model goes as --model before -", (readLog(modelLog).first?["argv"]) as? [String], expectedArgs("chat only, with a model"))

        let blankLog = s.file("blank.jsonl")
        _ = await collect(provider(s, model: "", transcript: "chat.jsonl", log: blankLog), log: blankLog)
        T.check("an empty model is Codex's own default", (readLog(blankLog).first?["argv"]) as? [String],
                expectedArgs("chat only, one turn, no model"))

        // A fresh picture folder for each refusal: the shared one exists once any turn has run, so only its own absence proves a refusal wrote nothing.
        let flagLog = s.file("flag.jsonl")
        var flagged = provider(s, model: "--sandbox=danger-full-access", transcript: "chat.jsonl", log: flagLog)
        flagged.imageFolder = s.file("flag-images")
        let flag = await collect(flagged, log: flagLog)
        T.check("a model that is a flag is nm_bad_model", flag.error?.code, CodexError.modelRefused)
        T.checkTrue("and it is a bad request", flag.error?.kind == .badRequest)
        T.checkTrue("and no process was started", !FileManager.default.fileExists(atPath: flagLog))
        T.checkTrue("and the picture folder was never made", !FileManager.default.fileExists(atPath: flagged.imageFolder))
        let flagPictures = s.file("flag-pictures.jsonl")
        var flaggedPictures = provider(s, model: "--sandbox=danger-full-access", transcript: "chat.jsonl", log: flagPictures)
        flaggedPictures.imageFolder = s.file("flag-pictures-images")
        _ = await collect(flaggedPictures, pictureRequest(), log: flagPictures)
        T.checkTrue("a bad model with pictures makes no picture folder", !FileManager.default.fileExists(atPath: flaggedPictures.imageFolder))

        let models = try? await provider(s, transcript: "chat.jsonl", log: s.file("models.jsonl")).listModels()
        T.check("the one model row is named for OpenAI", models?.map { $0.label } ?? [], ["OpenAI's default model"])
    }

    // MARK: - A known bad status

    static func knownStates(_ s: Scratch) async {
        T.section("A known bad status fails before anything starts")
        let refused: [(CodexStatus.State, String, AIErrorKind)] = [(.tooOld, CodexError.tooOld, .badRequest),
                                                                   (.signedOut, CodexError.signedOut, .auth)]
        for (state, code, kind) in refused {
            let log = s.file("known-\(state).jsonl")
            var known = provider(s, transcript: "chat.jsonl", log: log, knownState: state)
            known.imageFolder = s.file("known-images-\(state)")
            let out = await collect(known, pictureRequest(), log: log)
            T.check("\(state) fails as \(code)", out.error?.code, code)
            T.checkTrue("and its kind is \(kind.rawValue)", out.error?.kind == kind)
            T.checkTrue("no process was started", !FileManager.default.fileExists(atPath: log))
            T.checkTrue("no picture folder was made", !FileManager.default.fileExists(atPath: known.imageFolder))
            T.check("and no text was shown", out.textChunks, 0)
        }
        // Not blocked (ruling R9): a program that is not found reports itself at launch; an unknown or signed-in status runs.
        for state in [CodexStatus.State.notInstalled, .unknown, .signedIn] {
            let log = s.file("known-ok-\(state).jsonl")
            let out = await collect(provider(s, transcript: "chat.jsonl", log: log, knownState: state), log: log)
            T.checkTrue("\(state) still runs", out.error == nil && out.turn != nil)
        }
    }

    // MARK: - The image folder is swept once per process

    static func sweep(_ s: Scratch) async {
        T.section("The image folder is swept once per process")
        let sweeper = CodexImageSweeper()
        let stale = s.images + "/left-behind"
        try! FileManager.default.createDirectory(atPath: stale, withIntermediateDirectories: true)
        let picture = stale + "/image-1.png"
        try! Data([1, 2]).write(to: URL(fileURLWithPath: picture))
        try! FileManager.default.setAttributes([.posixPermissions: 0o400], ofItemAtPath: picture)
        let first = s.file("sweep-1.jsonl")
        let out = await collect(provider(s, transcript: "chat.jsonl", log: first, sweeper: sweeper), pictureRequest(), log: first)
        T.check("the first turn succeeds", out.error == nil, true)
        T.checkTrue("a folder a crash left behind, with a read-only picture in it, is removed",
                    !FileManager.default.fileExists(atPath: stale))
        T.check("and the turn's own picture folder is gone after it", entries(s.images), [])

        // Once per process: a folder that looks live after the sweep is not swept by a later turn of this process.
        let live = s.images + "/live-turn"
        try! FileManager.default.createDirectory(atPath: live, withIntermediateDirectories: true)
        try! Data([3]).write(to: URL(fileURLWithPath: live + "/image-1.png"))
        let second = s.file("sweep-2.jsonl")
        let again = await collect(provider(s, transcript: "chat.jsonl", log: second, sweeper: sweeper), pictureRequest(), log: second)
        T.check("the second turn succeeds", again.error == nil, true)
        T.checkTrue("a live-looking folder survives a later turn of this process",
                    FileManager.default.fileExists(atPath: live + "/image-1.png"))
        try? FileManager.default.removeItem(atPath: live)
    }

    // MARK: - Pictures

    static func pictures(_ s: Scratch) async {
        T.section("Pictures")
        let log = s.file("images.jsonl")
        let out = await collect(provider(s, transcript: "chat.jsonl", log: log), pictureRequest(), log: log)
        T.check("no error", out.error == nil, true)
        let argv = out.turn?["argv"] as? [String] ?? []
        let tail = Array(argv.suffix(3))
        T.checkTrue("two images go as two --image=<path> arguments before the final -",
                    tail.count == 3 && tail[0].hasPrefix("--image=") && tail[1].hasPrefix("--image=") && tail[2] == "-")
        T.checkTrue("the pictures sit in the image folder, as image-1 and image-2",
                    tail.count == 3 && tail[0].hasPrefix("--image=" + s.images + "/") && tail[0].hasSuffix("/image-1.png")
                        && tail[1].hasPrefix("--image=" + s.images + "/") && tail[1].hasSuffix("/image-2.png"))
        T.checkTrue("the picture folder is empty after a success", emptyPictureFolder(s))

        let crashLog = s.file("images-crash.jsonl")
        let crash = await collect(provider(s, transcript: "crash.jsonl", log: crashLog, extra: ["NM_FAKE_CODEX_EXIT": "1"]),
                                  pictureRequest(), log: crashLog)
        T.check("a crash with pictures is nm_codex_crashed", crash.error?.code, CodexError.crashed)
        T.checkTrue("the picture folder is empty after a crash", emptyPictureFolder(s))
    }

    // MARK: - Failures

    static func failures(_ s: Scratch) async {
        T.section("Failures")
        func run(_ transcript: String, exit: String = "1", stderr: String = "", name: String) async -> Outcome {
            let log = s.file("f-\(name).jsonl")
            return await collect(provider(s, transcript: transcript, log: log,
                                          extra: ["NM_FAKE_CODEX_EXIT": exit, "NM_FAKE_CODEX_STDERR": stderr]), log: log)
        }
        let signedOut = await run("signed-out-exec.jsonl", name: "so")
        T.check("signed out, as Codex really says it", signedOut.error?.code, CodexError.signedOut)
        T.checkTrue("and it is an auth error", signedOut.error?.kind == .auth)
        let onStderr = await run("signed-out.jsonl", stderr: "Not logged in", name: "se")
        T.check("signed out on stderr", onStderr.error?.code, CodexError.signedOut)
        let empty = await run("empty.jsonl", exit: "0", name: "empty")
        T.check("nothing readable with exit 0 is unreadable", empty.error?.code, CodexError.unreadable)
        let crash = await run("crash.jsonl", name: "crash")
        T.check("a crash is nm_codex_crashed", crash.error?.code, CodexError.crashed)
        T.checkTrue("and it is an interruption", crash.error?.kind == .interrupted)
        T.check("and no text was shown", crash.textChunks, 0)
        // The same transcript as a finished chat turn, cut before its turn.completed, so the message comes before the crash.
        let spokenLines = try! String(contentsOf: fixtures.appendingPathComponent("transcripts/chat.jsonl"), encoding: .utf8)
            .split(separator: "\n").filter { !$0.contains("turn.completed") }
        T.checkTrue("the transcript says something before it ends", spokenLines.contains { $0.contains("agent_message") })
        let spoken = s.file("text-then-crash.jsonl")
        try! spokenLines.joined(separator: "\n").write(toFile: spoken, atomically: true, encoding: .utf8)
        let spokenLog = s.file("f-spoken.jsonl")
        let said = await collect(provider(s, transcript: "chat.jsonl", log: spokenLog,
                                          extra: ["NM_FAKE_CODEX_EXIT": "1", "NM_FAKE_CODEX_TRANSCRIPT": spoken]), log: spokenLog)
        T.check("a message, then a crash: nm_codex_crashed", said.error?.code, CodexError.crashed)
        T.check("and the message is not shown", said.textChunks, 0)
    }

    // MARK: - A forbidden item

    static func forbidden(_ s: Scratch) async {
        T.section("A forbidden item")
        let log = s.file("forbidden.jsonl"), childFile = s.file("forbidden-child.pid")
        let started = Date()
        let out = await collect(provider(s, transcript: "chat-wants-command.jsonl", log: log,
                                         extra: ["NM_FAKE_CODEX_HANG_AFTER": "5", "NM_FAKE_CODEX_CHILD_PIDFILE": childFile]), log: log)
        T.check("a forbidden item mid-answer is nm_level_exceeded", out.error?.code, CodexError.levelExceeded)
        T.check("and no text is shown, not even the words before it", out.textChunks, 0)
        T.checkTrue("and the call returns in under 10 s", Date().timeIntervalSince(started) < 10)
        let fakePid = (out.turn?["pid"] as? Int).map { Int32($0) }
        T.checkTrue("the fake's pid was logged", fakePid != nil)
        T.checkTrue("the process and its child are gone",
                    await waitFor(seconds: 5) { !alive(fakePid) && !alive(pidFile(childFile)) })
        let withPictures = s.file("forbidden-pictures.jsonl")
        _ = await collect(provider(s, transcript: "chat-wants-command.jsonl", log: withPictures,
                                   extra: ["NM_FAKE_CODEX_HANG_AFTER": "5"]), pictureRequest(), log: withPictures)
        T.checkTrue("a forbidden item with pictures leaves no picture folder behind", entries(s.images).isEmpty)

        let startedLog = s.file("started.jsonl")
        let only = await collect(provider(s, transcript: "started-only.jsonl", log: startedLog, extra: ["NM_FAKE_CODEX_EXIT": "0"]), log: startedLog)
        T.check("an item that only started is nm_level_exceeded", only.error?.code, CodexError.levelExceeded)
        T.check("and no text is shown", only.textChunks, 0)
    }

    // MARK: - A line past 1 MiB

    static func oversize(_ s: Scratch) async {
        T.section("A line past 1 MiB")
        let wrapper = s.file("long-line.sh")
        try! "#!/bin/sh\nhead -c 1200000 /dev/zero | tr '\\0' 'a'\necho\n".write(toFile: wrapper, atomically: true, encoding: .utf8)
        try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper)
        let log = s.file("long.jsonl")
        let out = await collect(provider(s, transcript: "chat.jsonl", log: log, executable: wrapper), log: log)
        T.check("the run fails as nm_codex_crashed", out.error?.code, CodexError.crashed)
        T.checkTrue("and as an interruption", out.error?.kind == .interrupted)
        T.check("with nothing shown: no text, no step", out.chunks, [])
        let bigPictures = s.file("long-pictures.jsonl")
        _ = await collect(provider(s, transcript: "chat.jsonl", log: bigPictures, executable: wrapper), pictureRequest(), log: bigPictures)
        T.checkTrue("a line past the cap with pictures leaves no picture folder behind", emptyPictureFolder(s))

        // A forbidden item, then a line past the cap: the level's refusal is the reason, not the length.
        let mixedWrapper = s.file("forbidden-then-long.sh")
        let forbiddenTranscript = fixtures.appendingPathComponent("transcripts/chat-wants-command.jsonl").path
        try! "#!/bin/sh\ncat '\(forbiddenTranscript)'\nsleep 0.3\nhead -c 1200000 /dev/zero | tr '\\0' 'a'\necho\n"
            .write(toFile: mixedWrapper, atomically: true, encoding: .utf8)
        try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: mixedWrapper)
        let mixedLog = s.file("mixed.jsonl")
        let mixed = await collect(provider(s, transcript: "chat.jsonl", log: mixedLog, executable: mixedWrapper), log: mixedLog)
        T.check("a forbidden item then a long line is nm_level_exceeded", mixed.error?.code, CodexError.levelExceeded)
        T.check("and no text is shown", mixed.textChunks, 0)
    }

    // MARK: - A missing program

    static func missing(_ s: Scratch) async {
        T.section("A missing program")
        let log = s.file("missing.jsonl")
        let out = await collect(provider(s, transcript: "chat.jsonl", log: log, executable: "/nonexistent/codex"), log: log)
        T.check("is nm_codex_missing", out.error?.code, CodexError.missing)
        T.checkTrue("and unreachable", out.error?.kind == .unreachable)
        let pictures = s.file("missing-pictures.jsonl")
        _ = await collect(provider(s, transcript: "chat.jsonl", log: pictures, executable: "/nonexistent/codex"), pictureRequest(), log: pictures)
        T.checkTrue("and the picture folder is empty after it", emptyPictureFolder(s))

        let empty = await collect(provider(s, transcript: "chat.jsonl", log: s.file("empty-path.jsonl"), executable: ""),
                                  log: s.file("empty-path.jsonl"))
        T.check("an empty program path is nm_codex_missing", empty.error?.code, CodexError.missing)

        // An executable file that cannot be started (its interpreter is not there): a crash, not a missing program.
        let junk = s.file("not-a-program")
        try! "#!/nonexistent/interpreter-for-nm\n".write(toFile: junk, atomically: true, encoding: .utf8)
        try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: junk)
        let junkLog = s.file("junk.jsonl")
        let broken = await collect(provider(s, transcript: "chat.jsonl", log: junkLog, executable: junk), pictureRequest(), log: junkLog)
        T.check("an executable file that will not start is nm_codex_crashed", broken.error?.code, CodexError.crashed)
        T.checkTrue("and it is an interruption", broken.error?.kind == .interrupted)
        T.check("and the picture folder is empty after it", entries(s.images), [])
    }

    // MARK: - Stop

    static func stop(_ s: Scratch) async {
        T.section("Stop")
        let log = s.file("stop.jsonl"), childFile = s.file("stop-child.pid")
        let stream = provider(s, transcript: "chat.jsonl", log: log,
                              extra: ["NM_FAKE_CODEX_HANG_AFTER": "1", "NM_FAKE_CODEX_CHILD_PIDFILE": childFile]).stream(pictureRequest())
        let consumer = Task { () -> Bool in
            do {
                for try await _ in stream {}
                return true
            } catch {
                return false
            }
        }
        T.checkTrue("the child started", await waitFor(seconds: 10) { FileManager.default.fileExists(atPath: childFile) })
        consumer.cancel()
        T.checkTrue("Stop ends the stream without an error", await consumer.value)
        let fakePid = (readLog(log).first?["pid"] as? Int).map { Int32($0) }
        T.checkTrue("the fake's pid was logged", fakePid != nil)
        T.checkTrue("the process and its child are gone within 6 s",
                    await waitFor(seconds: 6) { !alive(fakePid) && !alive(pidFile(childFile)) })
        // The picture folder is removed by the turn's cleanup, which runs as the run ends; poll for it rather than race it.
        T.checkTrue("the picture folder is empty after a Stop", await waitFor(seconds: 6) { emptyPictureFolder(s) })
    }

    // MARK: - A run that says nothing in time

    static func watchdog(_ s: Scratch) async {
        T.section("A run that says nothing within the startup limit is a timeout, and its pictures go")
        let log = s.file("silent.jsonl")
        var silent = provider(s, transcript: "chat.jsonl", log: log,
                              extra: ["NM_FAKE_CODEX_TRANSCRIPT": "", "NM_FAKE_CODEX_HANG_AFTER": "0"])
        silent.timings = ClaudeProcessTimings(startup: 0.5, interruptGrace: 2, terminateGrace: 2, drain: 1)
        let out = await collect(silent, pictureRequest(), log: log)
        T.check("a silent run is a timeout", out.error?.kind, .timeout)
        let pid = (out.turn?["pid"] as? Int).map { Int32($0) }
        T.checkTrue("the fake's pid was logged", pid != nil)
        T.checkTrue("the process is gone", await waitFor(seconds: 6) { !alive(pid) })
        T.checkTrue("its pictures are gone", emptyPictureFolder(s))
    }

    // MARK: - Quit

    static func quit(_ s: Scratch) async {
        T.section("Quit ends a hanging Codex run and what it started")
        let log = s.file("quit.jsonl"), childFile = s.file("quit-child.pid")
        let stream = provider(s, transcript: "chat.jsonl", log: log,
                              extra: ["NM_FAKE_CODEX_HANG_AFTER": "1", "NM_FAKE_CODEX_CHILD_PIDFILE": childFile]).stream(pictureRequest())
        let consumer = Task { () -> Bool in
            do {
                for try await _ in stream {}
                return true
            } catch {
                return false
            }
        }
        T.checkTrue("the child started", await waitFor(seconds: 10) { FileManager.default.fileExists(atPath: childFile) })
        ClaudeRunRegistry.stopAll(wait: 1)
        T.checkTrue("the stream ends without an error", await consumer.value)
        let fakePid = (readLog(log).first?["pid"] as? Int).map { Int32($0) }
        T.checkTrue("the fake's pid was logged", fakePid != nil)
        T.checkTrue("the process and its child are gone",
                    await waitFor(seconds: 6) { !alive(fakePid) && !alive(pidFile(childFile)) })
        T.checkTrue("the pictures are gone", await waitFor(seconds: 6) { emptyPictureFolder(s) })
    }

    // MARK: - A transcript with no final newline

    static func noFinalNewline(_ s: Scratch) async {
        T.section("A run whose last line has no LF still finishes")
        let text = try! String(contentsOf: fixtures.appendingPathComponent("transcripts/chat.jsonl"), encoding: .utf8)
        let bare = s.file("no-final-newline.jsonl")
        try! String(text.dropLast()).write(toFile: bare, atomically: true, encoding: .utf8)
        let wrapper = s.file("no-final-newline.sh")
        try! "#!/bin/sh\ncat '\(bare)'\n".write(toFile: wrapper, atomically: true, encoding: .utf8)
        try! FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: wrapper)
        let log = s.file("no-final.jsonl")
        let out = await collect(provider(s, transcript: "chat.jsonl", log: log, executable: wrapper), log: log)
        T.check("no error", out.error == nil, true)
        T.check("the text, then the finish", out.chunks, [.text("Hello there, hope you’re doing well!"), .finish(.stop)])
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
        let log = s.file("leak.jsonl")
        let req = request([.fileText(name: "\(marker).txt", text: "tell me about \(marker)")])
        _ = await collect(provider(s, transcript: "crash.jsonl", log: log,
                                   extra: ["NM_FAKE_CODEX_STDERR": "stderr says \(marker)", "LEAK_ENV": marker, "NM_FAKE_CODEX_EXIT": "1"]),
                          req, log: log)
        _ = await collect(provider(s, transcript: "chat.jsonl", log: log, extra: ["LEAK_ENV": marker]), req, log: log)
        let captured = lines.lock.withLock { lines.all }
        T.checkTrue("events were logged", captured.count >= 3)
        T.check("no log line holds the prompt, the file name, stderr or the environment", captured.filter { $0.contains(marker) }, [])
    }
}
