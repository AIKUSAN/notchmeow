import Foundation

// Finding the user's Claude Code and asking it two questions: its version and whether it is signed in. These run
// when Settings opens and before a chat's first turn, never on a timer. NotchMeow never reads Claude Code's
// credential files or Keychain items: it only reads `authMethod` out of `claude auth status` and keeps nothing else.
// The rules are in `tests/fixtures/ai/claude-code/` (`locator-cases.json`, `auth-status.json`, `versions.json`).

#if !APPSTORE

/// What the last check found. `signedIn` is the only state the router treats as ready.
struct ClaudeCodeStatus: Equatable, Sendable {
    enum State: Equatable, Sendable { case notInstalled, tooOld, signedOut, signedIn, unknown }

    var state: State
    var executable: String? = nil
    /// "2.1.211"
    var version: String? = nil
    /// What `claude auth status` reports (`claude.ai`, `api_key`, …): the sign-in method, never an account.
    var authMethod: String? = nil

    var isReady: Bool { state == .signedIn }
    static let notInstalled = ClaudeCodeStatus(state: .notInstalled)
}

enum ClaudeCodeLocator {
    /// The version the flags in `expected-args.json` were verified against (2026-10-06). One number to lower
    /// once older versions have been checked.
    static let minimumVersion = [2, 1, 211]
    /// Where Anthropic's installer is. NotchMeow links to it and installs nothing.
    static let installGuide = "https://docs.claude.com/en/docs/claude-code/setup"

    // MARK: Where it is

    /// The candidates, in order, before the login shell is asked.
    static func candidates(home: String, environment: [String: String]) -> [String] {
        var list = [home + "/.local/bin/claude", "/opt/homebrew/bin/claude", "/usr/local/bin/claude",
                    home + "/.npm-global/bin/claude"]
        if var prefix = environment["NPM_CONFIG_PREFIX"], !prefix.isEmpty {
            while prefix.hasSuffix("/") { prefix.removeLast() }
            list.append(prefix + "/bin/claude")
        }
        return list
    }

    /// The first candidate that is an executable file; failing that, what the login shell's `command -v claude`
    /// printed (its last line, when it is an absolute path to an executable). `loginShell` is only called when no
    /// candidate exists: starting a login shell is slow.
    static func find(home: String, environment: [String: String], isExecutable: (String) -> Bool,
                     loginShell: () -> String?) -> (path: String?, askedShell: Bool) {
        if let hit = candidates(home: home, environment: environment).first(where: isExecutable) { return (hit, false) }
        let lines = (loginShell() ?? "").split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty }
        if let last = lines.last, last.hasPrefix("/"), isExecutable(last) { return (last, true) }
        return (nil, true)
    }

    // MARK: Its answers

    /// The first x.y.z in the output of `claude --version`.
    static func parseVersion(_ text: String) -> [Int]? {
        guard let range = text.range(of: #"(\d+)\.(\d+)\.(\d+)"#, options: .regularExpression) else { return nil }
        let parts = text[range].split(separator: ".").compactMap { Int($0) }
        return parts.count == 3 ? parts : nil
    }

    enum VersionCheck: Equatable { case ok, tooOld, unknown }

    static func check(version: [Int]?) -> VersionCheck {
        guard let version else { return .unknown }
        return version.lexicographicallyPrecedes(minimumVersion) ? .tooOld : .ok
    }

    enum AuthResult: Equatable, Sendable {
        case signedIn(authMethod: String?)
        case signedOut
        case unknown
    }

    /// `claude auth status`: exit 0 signed in, 1 signed out. Only `authMethod` is read. `none` is signed out
    /// whatever the exit status says. `exit` is nil when the program could not be run.
    static func parseAuth(exit: Int32?, stdout: String) -> AuthResult {
        guard let exit else { return .unknown }
        var method: String?
        if let data = stdout.data(using: .utf8),
           let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] {
            method = json["authMethod"] as? String
        }
        if exit == 1 || method == "none" { return .signedOut }
        return exit == 0 ? .signedIn(authMethod: method) : .unknown
    }

    // MARK: The checks that start processes

    /// Where the program is on this Mac, asking the login shell last.
    static func locate(environment: [String: String] = ProcessInfo.processInfo.environment) async -> String? {
        #if DEBUG
        // Debug builds only: `NM_CLAUDE_CODE_PATH_OVERRIDE=…/fake_claude.py` runs a chat against the fake claude. Compiled out
        // of Release builds (scripts/check-app-binary.sh proves it), so a shipped app can't be pointed at another program.
        if let path = environment["NM_CLAUDE_CODE_PATH_OVERRIDE"], !path.isEmpty { return path }
        #endif
        let home = NSHomeDirectory()
        let isExecutable: @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) && !isDirectory($0) }
        if let hit = candidates(home: home, environment: environment).first(where: isExecutable) { return hit }
        let shell = environment["SHELL"].flatMap { $0.hasPrefix("/") ? $0 : nil } ?? "/bin/zsh"
        // -l: the user's PATH is set up in their profile; a Finder-launched app has almost none of it.
        let printed = await ClaudeCodeCLI.run(shell, ["-l", "-c", "command -v claude"], environment: environment, timeout: 5)
        return find(home: home, environment: environment, isExecutable: isExecutable, loginShell: { printed.output }).path
    }

    private static func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Where it is, its version and whether it is signed in. Both questions are asked in the run's own environment
    /// (without what would outrank the plan login), so the answer is what a chat would get.
    static func status(environment: [String: String] = ProcessInfo.processInfo.environment) async -> ClaudeCodeStatus {
        guard let exe = await locate(environment: environment) else { return .notInstalled }
        return await statusOf(executable: exe, environment: environment)
    }

    /// The same for a program that is already known.
    static func statusOf(executable exe: String, environment: [String: String]) async -> ClaudeCodeStatus {
        let clean = ClaudeCodeCommand.childEnvironment(from: environment, platform: .current, executable: exe)
        async let versionRun = ClaudeCodeCLI.run(exe, ["--version"], environment: clean, timeout: 5)
        async let authRun = ClaudeCodeCLI.run(exe, ["auth", "status"], environment: clean, timeout: 10)
        let (versionOut, authOut) = await (versionRun, authRun)
        guard let version = parseVersion(versionOut.output) else { return ClaudeCodeStatus(state: .notInstalled) }
        let shown = version.map(String.init).joined(separator: ".")
        var status = ClaudeCodeStatus(state: .unknown, executable: exe, version: shown)
        if check(version: version) == .tooOld { status.state = .tooOld; return status }
        switch parseAuth(exit: authOut.status, stdout: authOut.output) {
        case .signedIn(let method): status.state = .signedIn; status.authMethod = method
        case .signedOut: status.state = .signedOut
        case .unknown: status.state = .unknown
        }
        return status
    }
}

extension ClaudeCodeCommand {
    /// PATH for the child: the program's own folder (a node-based install finds its `node` beside it), then
    /// Homebrew's and `/usr/local`'s, then the rest, without repeats or empty entries. A Finder-launched app has
    /// almost no PATH, and `#!/usr/bin/env node` then fails silently.
    static func searchPath(executable: String, existing: String?) -> String {
        let own = (executable as NSString).deletingLastPathComponent
        var seen = Set<String>()
        return ([own, "/opt/homebrew/bin", "/usr/local/bin"] + (existing ?? "").split(separator: ":").map(String.init))
            .filter { !$0.isEmpty && seen.insert($0).inserted }.joined(separator: ":")
    }

    /// `environment(from:platform:)` (the shared contract, which strips what outranks the plan login) with that PATH.
    static func childEnvironment(from base: [String: String], platform: ClaudeCodePlatform, executable: String) -> [String: String] {
        var env = environment(from: base, platform: platform)
        env["PATH"] = searchPath(executable: executable, existing: env["PATH"])
        return env
    }
}

/// Runs a short program and returns its output, or a `nil` status when it could not be run or took too long.
/// After `timeout` the program gets SIGTERM, then SIGKILL after `killGrace`; the call returns at once when the
/// program is gone, even if a descendant still holds its stdout open (it is never waited on). Only one-shot timers,
/// nothing runs when idle. The output is only ever parsed, never logged.
enum ClaudeCodeCLI {
    static let killGrace: TimeInterval = 1
    /// How long output still in the pipe is waited for once the program has exited.
    private static let drain: TimeInterval = 0.5
    private static let outputCap = 65_536

    private final class Job: @unchecked Sendable {
        let process = Process()
        let pipe = Pipe()
        var done: CheckedContinuation<(status: Int32?, output: String), Never>?
        private let lock = NSLock()
        private var data = Data()
        private var expired = false, exited = false, eof = false
        private var timers: [DispatchWorkItem] = []

        func append(_ chunk: Data) {
            lock.withLock { if data.count < outputCap { data.append(chunk.prefix(outputCap - data.count)) } }
        }
        func schedule(after delay: TimeInterval, _ body: @escaping @Sendable () -> Void) {
            let item = DispatchWorkItem(block: body)
            lock.withLock { timers.append(item) }
            DispatchQueue.global().asyncAfter(deadline: .now() + delay, execute: item)
        }
        func sawEOF() { if lock.withLock({ eof = true; return exited }) { finish() } }
        func sawExit() {
            if lock.withLock({ exited = true; return eof }) { finish() } else { schedule(after: ClaudeCodeCLI.drain) { self.finish() } }
        }
        func expire() {
            lock.withLock { expired = true }
            if process.isRunning { process.terminate() }
            let pid = process.processIdentifier
            schedule(after: ClaudeCodeCLI.killGrace) { if self.process.isRunning { kill(pid, SIGKILL) } }
        }
        /// Once: stop listening, close the pipe, and answer.
        func finish() {
            let taken = lock.withLock { () -> (CheckedContinuation<(status: Int32?, output: String), Never>, Int32?, String)? in
                guard let waiting = done else { return nil }
                done = nil
                timers.forEach { $0.cancel() }
                let status = expired || process.isRunning ? nil : process.terminationStatus
                return (waiting, status, String(decoding: data, as: UTF8.self))
            }
            guard let (waiting, status, output) = taken else { return }
            pipe.fileHandleForReading.readabilityHandler = nil
            try? pipe.fileHandleForReading.close()
            waiting.resume(returning: (status: status, output: output))
        }
    }

    static func run(_ executable: String, _ arguments: [String], environment: [String: String],
                    timeout: TimeInterval) async -> (status: Int32?, output: String) {
        await withCheckedContinuation { (done: CheckedContinuation<(status: Int32?, output: String), Never>) in
            let job = Job()
            job.done = done
            job.process.executableURL = URL(fileURLWithPath: executable)
            job.process.arguments = arguments
            job.process.environment = environment
            job.process.standardOutput = job.pipe
            job.process.standardError = FileHandle.nullDevice
            job.process.standardInput = FileHandle.nullDevice
            job.pipe.fileHandleForReading.readabilityHandler = { handle in
                let chunk = handle.availableData
                if chunk.isEmpty { handle.readabilityHandler = nil; job.sawEOF() } else { job.append(chunk) }
            }
            job.process.terminationHandler = { _ in job.sawExit() }
            guard (try? job.process.run()) != nil else {
                job.pipe.fileHandleForReading.readabilityHandler = nil
                return done.resume(returning: (nil, ""))
            }
            job.schedule(after: timeout) { job.expire() }
        }
    }
}

/// The script Terminal runs for "Sign in": `claude auth login`, in Anthropic's own flow. NotchMeow never sees what
/// is typed or opened there.
enum ClaudeCodeSignIn {
    /// Single-quoted for any shell, whatever the path holds (spaces, quotes, accents).
    static func quoted(_ path: String) -> String { "'" + path.replacingOccurrences(of: "'", with: "'\\''") + "'" }

    static func script(executable: String) -> String {
        """
        #!/bin/zsh
        clear
        echo "Signing in. Your browser opens to finish."
        \(quoted(executable)) auth login
        echo
        echo "You can close this window and go back to NotchMeow."
        """ + "\n"
    }

    /// Writes the script as an executable `.command` file, which Terminal opens and runs. Returns its path.
    static func write(executable: String, into folder: String) -> String? {
        try? FileManager.default.createDirectory(atPath: folder, withIntermediateDirectories: true,
                                                 attributes: [.posixPermissions: 0o700])
        let path = folder + "/claude-sign-in.command"
        guard (try? script(executable: executable).write(toFile: path, atomically: true, encoding: .utf8)) != nil else { return nil }
        try? FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: path)
        return path
    }
}

#endif
