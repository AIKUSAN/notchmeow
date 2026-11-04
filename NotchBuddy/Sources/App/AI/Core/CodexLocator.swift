import Foundation

// Finding the user's Codex (OpenAI's `codex` command line) and asking it two questions: its version and whether it is
// signed in. These run when Settings opens and before a chat's first turn, never on a timer. NotchMeow never opens
// Codex's own folder or its credential files: `codex login status` is reduced to its state and a mode, and nothing
// else of it is kept.
// The rules are in `tests/fixtures/ai/codex/` (`locator-cases.json`, `login-status.json`, `versions.json`).

#if !APPSTORE

/// What the last check found. `signedIn` is the only state the router treats as ready.
struct CodexStatus: Equatable, Sendable {
    enum State: Equatable, Sendable { case notInstalled, tooOld, signedOut, signedIn, unknown }

    var state: State
    var executable: String? = nil
    /// "0.165.0"
    var version: String? = nil
    /// "chatgpt", "api_key" or "unknown"; only when signed in.
    var mode: String? = nil

    var isReady: Bool { state == .signedIn }
    static let notInstalled = CodexStatus(state: .notInstalled)
}

enum CodexLocator {
    /// The version the recording ran (`recorded/v.txt`, codex-cli 0.165.0). Older versions are not checked.
    static let minimumVersion = [0, 165, 0]
    /// Where OpenAI's Codex CLI is published. NotchMeow links to it and installs nothing.
    static let installGuide = "https://github.com/openai/codex"

    // MARK: Where it is

    /// The candidates, in order, before the login shell is asked.
    static func candidates(home: String, environment: [String: String]) -> [String] {
        var list = [home + "/.local/bin/codex", "/opt/homebrew/bin/codex", "/usr/local/bin/codex",
                    home + "/.npm-global/bin/codex"]
        if var prefix = environment["NPM_CONFIG_PREFIX"], !prefix.isEmpty {
            while prefix.hasSuffix("/") { prefix.removeLast() }
            list.append(prefix + "/bin/codex")
        }
        return list
    }

    /// The first candidate that is an executable file; failing that, the login shell's answer when it is an absolute
    /// path to an executable file named exactly `codex`. The answer is the last non-empty line, since the shell may
    /// print a banner first. `loginShell` is only called when no candidate exists: starting a login shell is slow.
    static func find(home: String, environment: [String: String], isExecutable: (String) -> Bool,
                     loginShell: () -> String?) -> (path: String?, askedShell: Bool) {
        if let hit = candidates(home: home, environment: environment).first(where: isExecutable) { return (hit, false) }
        let answer = (loginShell() ?? "").split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .last(where: { !$0.isEmpty }) ?? ""
        if answer.hasPrefix("/"), isExecutable(answer), answer.components(separatedBy: "/").last == "codex" {
            return (answer, true)
        }
        return (nil, true)
    }

    // MARK: Its answers

    /// The first x.y.z in the output of `codex --version`.
    static func parseVersion(_ text: String) -> [Int]? {
        guard let range = text.range(of: #"([0-9]+)\.([0-9]+)\.([0-9]+)"#, options: .regularExpression) else { return nil }
        let parts = text[range].split(separator: ".").compactMap { Int($0) }
        return parts.count == 3 ? parts : nil
    }

    enum VersionCheck: Equatable { case ok, old, unknown }

    /// A missing version or minimum is unknown: unknown is allowed to run.
    static func check(version: [Int]?, minimum: [Int]?) -> VersionCheck {
        guard let version, let minimum else { return .unknown }
        return version.lexicographicallyPrecedes(minimum) ? .old : .ok
    }

    enum Login: Equatable, Sendable { case signedIn(mode: String), signedOut, unknown }

    /// `codex login status`: only the exit code decides the state (nil: the program could not run, so unknown;
    /// non-zero: signed out). When signed in, the mode is read from the text, stdout then stderr joined, by fixed
    /// case-insensitive substrings. (Some builds print the sign-in line on stderr; `statusOf` reads both streams.)
    static func login(exit: Int32?, stdout: String, stderr: String = "") -> Login {
        guard let exit else { return .unknown }
        guard exit == 0 else { return .signedOut }
        let text = (stdout + "\n" + stderr).lowercased()
        let mode = text.contains("chatgpt") ? "chatgpt" : text.contains("api key") ? "api_key" : "unknown"
        return .signedIn(mode: mode)
    }

    // MARK: The checks that start processes

    /// Where the program is on this Mac, asking the login shell last.
    static func locate(environment: [String: String] = ProcessInfo.processInfo.environment) async -> String? {
        #if DEBUG
        // Debug builds only: `NM_CODEX_PATH_OVERRIDE=…/fake_codex.py` runs a chat against the fake codex. Compiled out
        // of Release builds (scripts/check-app-binary.sh proves it), so a shipped app can't be pointed at another program.
        if let path = environment["NM_CODEX_PATH_OVERRIDE"], !path.isEmpty { return path }
        #endif
        let home = NSHomeDirectory()
        let isExecutable: @Sendable (String) -> Bool = { FileManager.default.isExecutableFile(atPath: $0) && !isDirectory($0) }
        if let hit = candidates(home: home, environment: environment).first(where: isExecutable) { return hit }
        let shell = environment["SHELL"].flatMap { $0.hasPrefix("/") ? $0 : nil } ?? "/bin/zsh"
        // -l: the user's PATH is set up in their profile; a Finder-launched app has almost none of it.
        let printed = await ClaudeCodeCLI.run(shell, ["-l", "-c", "command -v codex"], environment: environment, timeout: 5)
        return find(home: home, environment: environment, isExecutable: isExecutable, loginShell: { printed.output }).path
    }

    private static func isDirectory(_ path: String) -> Bool {
        var isDir: ObjCBool = false
        return FileManager.default.fileExists(atPath: path, isDirectory: &isDir) && isDir.boolValue
    }

    /// Where it is, its version and whether it is signed in.
    static func status(environment: [String: String] = ProcessInfo.processInfo.environment) async -> CodexStatus {
        guard let exe = await locate(environment: environment) else { return .notInstalled }
        return await statusOf(executable: exe, environment: environment)
    }

    /// The same for a program that is already known. Both questions run in the child's own environment (without the
    /// OpenAI variables that would outrank the user's login), in parallel.
    static func statusOf(executable exe: String, environment: [String: String]) async -> CodexStatus {
        let clean = CodexCommand.childEnvironment(from: environment, platform: .current, executable: exe)
        async let versionRun = ClaudeCodeCLI.run(exe, ["--version"], environment: clean, timeout: 5)
        // The shared runner keeps stdout only, so the shell sends stderr into it (`2>&1`) and execs the program. The
        // path comes in as "$0", never spliced into the script; the timeout and the kill are the runner's own.
        async let loginRun = ClaudeCodeCLI.run("/bin/sh", ["-c", #"exec "$0" login status 2>&1"#, exe],
                                               environment: clean, timeout: 10)
        let (versionOut, loginOut) = await (versionRun, loginRun)
        if versionOut.status == nil && versionOut.output.isEmpty { return .notInstalled }
        let parsed = parseVersion(versionOut.output)
        var status = CodexStatus(state: .unknown, executable: exe,
                                 version: parsed.map { $0.map(String.init).joined(separator: ".") })
        if check(version: parsed, minimum: minimumVersion) == .old {
            status.state = .tooOld
            return status
        }
        switch login(exit: loginOut.status, stdout: loginOut.output) {
        case .signedIn(let mode): status.state = .signedIn; status.mode = mode
        case .signedOut: status.state = .signedOut
        case .unknown: status.state = .unknown
        }
        return status
    }
}

#endif
