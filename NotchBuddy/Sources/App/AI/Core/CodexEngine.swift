import Foundation

// Codex (OpenAI's `codex` command line, run on the user's own plan) as an engine, the pure parts: the levels, the
// command line of one turn, the environment it runs in, the prompt written to its stdin and the folders it uses.
// Nothing here starts a process. `tests/fixtures/ai/codex/` is what both apps must agree on; its `reference.py` is
// the tie-breaker. The App Store build compiles all of this out (`scripts/check-app-binary.sh` looks for strings only
// the engine has).

#if !APPSTORE

/// The two levels NotchMeow offers for Codex. The keys are the fixtures' level names.
enum CodexLevel: String, Sendable, Equatable {
    case chat = "chat", noTools = "none"

    var key: String { rawValue }
}

enum CodexCommand {
    static let base = ["exec", "--json", "--ephemeral", "--skip-git-repo-check", "--sandbox", "read-only",
                       "--ignore-user-config", "--ignore-rules"]
    /// Shell, unified exec, apps, browser, computer use and web search off.
    static let shellOff = ["--disable", "shell_tool", "--disable", "unified_exec", "--disable", "apps",
                           "--disable", "browser_use", "--disable", "computer_use", "--disable", "in_app_browser",
                           "-c", "web_search=\"disabled\""]
    /// The fixture's pattern, written out for the reader; `isValidModel` checks it by hand, without a regex.
    static let modelPattern = #"^[A-Za-z0-9][A-Za-z0-9._:-]{0,63}$"#
    static let offeredLevels: [String] = ["none", "chat"]

    enum Built: Equatable {
        case arguments([String])
        case refused(code: String)
    }

    /// One turn's argv. The chat folder is the working folder (`workingFolderKind`) and never appears here.
    static func arguments(level: String, model: String?, images: [String]) -> Built {
        guard offeredLevels.contains(level) else { return .refused(code: "nm_level_unavailable") }
        if let model, !isValidModel(model) { return .refused(code: "nm_bad_model") }
        var args = base + shellOff
        if let model { args += ["--model", model] }
        // One --image=<path> per picture: the bare form lets the CLI read the final `-` as a second picture.
        for path in images { args += ["--image=\(path)"] }
        return .arguments(args + ["-"])
    }

    /// 1 to 64 ASCII bytes, the first a letter or digit, the rest letters, digits, `.`, `_`, `:` or `-`.
    static func isValidModel(_ model: String) -> Bool {
        func isAlnum(_ b: UInt8) -> Bool {
            (b >= 0x30 && b <= 0x39) || (b >= 0x41 && b <= 0x5A) || (b >= 0x61 && b <= 0x7A)
        }
        let bytes = Array(model.utf8)
        guard (1...64).contains(bytes.count), isAlnum(bytes[0]) else { return false }
        let rest = Set("._:-".utf8)
        return bytes.dropFirst().allSatisfy { isAlnum($0) || rest.contains($0) }
    }

    /// `folder` for Read-only and Agent with a folder the user chose, else NotchMeow's own chat folder.
    static func workingFolderKind(level: String, folder: String?) -> String {
        (level == "read" || level == "agent") && !(folder ?? "").isEmpty ? "folder" : "chatFolder"
    }

    // MARK: Environment

    /// Variables that outrank the user's own Codex login.
    static let strippedVariables: Set<String> = ["OPENAI_API_KEY", "CODEX_API_KEY", "OPENAI_BASE_URL",
                                                 "OPENAI_ORG_ID", "OPENAI_PROJECT_ID"]
    static let strippedPrefixes = ["OPENAI_"]

    /// The caller's environment without those names or prefixes. On Windows names compare without regard to case.
    static func environment(from base: [String: String], platform: ClaudeCodePlatform) -> [String: String] {
        let insensitive = platform == .windows
        return base.filter { name, _ in
            let key = insensitive ? name.uppercased() : name
            return !strippedVariables.contains(key) && !strippedPrefixes.contains { key.hasPrefix($0) }
        }
    }

    /// `environment(from:platform:)` with the PATH that finds the program's own helpers (`ClaudeCodeCommand.searchPath`).
    static func childEnvironment(from base: [String: String], platform: ClaudeCodePlatform, executable: String) -> [String: String] {
        var env = environment(from: base, platform: platform)
        env["PATH"] = ClaudeCodeCommand.searchPath(executable: executable, existing: env["PATH"])
        return env
    }
}

/// The prompt written to Codex's stdin: NotchMeow's instructions, the chat so far and the new message.
enum CodexPrompt {
    static let instructionsHead = "Instructions from NotchMeow, the app this chat runs in (not words of the user):"
    static let earlierHead = "Earlier in this chat (already answered):"
    static let newHead = "The user's new message:"

    struct Image: Equatable, Sendable {
        var mime: String
        var data: Data
    }

    struct Built: Equatable, Sendable {
        var text: String
        var images: [Image]
    }

    static func build(_ request: ChatRequest) -> Built {
        var images: [Image] = []
        let texts: [String] = request.messages.map { message in
            message.parts.compactMap { part -> String? in
                switch part {
                case .text(let text): return text
                case .fileText(let name, let text): return "File: \(name)\n\(text)"
                case .pdf(let name, _): return "File: \(name)"
                case .image(let mime, let data):
                    images.append(Image(mime: mime, data: data))
                    return nil
                }
            }.joined(separator: "\n")
        }
        var sections: [String] = []
        if !request.system.isEmpty { sections.append(instructionsHead + "\n" + request.system) }
        if texts.count > 1 {
            let earlier = (0..<(texts.count - 1)).map { index -> String in
                (request.messages[index].role == .user ? "User: " : "Assistant: ") + texts[index]
            }
            sections.append(earlierHead + "\n" + earlier.joined(separator: "\n"))
        }
        sections.append(newHead + "\n" + (texts.last ?? ""))
        return Built(text: sections.joined(separator: "\n\n"), images: images)
    }

    /// The file extension for a dropped image, so Codex can see what it is.
    static func fileExtension(mime: String) -> String {
        switch mime {
        case "image/png": "png"
        case "image/jpeg": "jpg"
        case "image/gif": "gif"
        case "image/webp": "webp"
        default: "img"
        }
    }
}

/// The folders a Codex run uses: NotchMeow's chat folder (kept empty and read-only) and the image folder (one folder
/// per turn, removed when the turn ends).
enum CodexFolders {
    static let chatMode: Int16 = 0o500
    static let imageMode: Int16 = 0o700

    /// `<Application Support>/NotchMeow/codex-chat`
    static func chatFolder() -> String {
        appSupport("NotchMeow/codex-chat")
    }

    /// `<Application Support>/NotchMeow/codex-images`
    static func imageFolder() -> String {
        appSupport("NotchMeow/codex-images")
    }

    private static func appSupport(_ relative: String) -> String {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent(relative).path
    }

    /// Whether a mode is exactly the chat folder's (0500). The one check of the read-back, pure so that it is tested directly.
    static func folderModeIs0500(_ mode: Int?) -> Bool { mode == Int(chatMode) }

    /// Makes the folder (0700) if it is missing, then sets it to 0500. False when it is not a folder afterwards.
    static func prepareChatFolder(_ path: String) -> Bool {
        let fm = FileManager.default
        // A link is refused before anything changes: setAttributes would follow it and chmod the target.
        if (try? fm.attributesOfItem(atPath: path))?[.type] as? FileAttributeType == .typeSymbolicLink { return false }
        try? fm.createDirectory(atPath: path, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try? fm.setAttributes([.posixPermissions: Int(chatMode)], ofItemAtPath: path)
        var isDirectory: ObjCBool = false
        guard fm.fileExists(atPath: path, isDirectory: &isDirectory), isDirectory.boolValue else { return false }
        // The mode is read back: a folder that stayed writable (the chmod failed silently) is refused, so no run starts in it.
        return folderModeIs0500((try? fm.attributesOfItem(atPath: path))?[.posixPermissions] as? Int)
    }

    /// Writes each image to `<root>/<turn>/image-<n>.<ext>` (folders 0700, files 0600, never overwriting). The paths in
    /// order, or nil with nothing left behind when one cannot be written.
    static func writeImages(_ images: [CodexPrompt.Image], under root: String, turn: String) -> [String]? {
        let fm = FileManager.default
        let folder = root + "/" + turn
        do {
            try fm.createDirectory(atPath: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            try fm.createDirectory(atPath: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
            var paths: [String] = []
            for (index, image) in images.enumerated() {
                let path = folder + "/image-\(index + 1).\(CodexPrompt.fileExtension(mime: image.mime))"
                try writeNew(image.data, to: path)
                paths.append(path)
            }
            return paths
        } catch {
            try? fm.removeItem(atPath: folder)
            return nil
        }
    }

    /// Creates `path` with mode 0600 in one step (no window at a wider mode) and writes `data` into it. Never over an
    /// existing file: the exclusive create fails instead.
    private static func writeNew(_ data: Data, to path: String) throws {
        let descriptor = open(path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard descriptor >= 0 else { throw CocoaError(.fileWriteUnknown) }
        let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
        try handle.write(contentsOf: data)
        try handle.close()
    }

    /// Removes `<root>/<turn>` and what it holds. Silent when it is not there.
    static func removeTurn(under root: String, turn: String) {
        try? FileManager.default.removeItem(atPath: root + "/" + turn)
    }

    /// Removes every turn folder under `root`: what a Quit or a crash left behind. Silent when there is nothing, or a
    /// folder cannot be removed (a turn's folder is NotchMeow's own; nothing else is ever in it).
    static func sweepStale(under root: String) {
        let fm = FileManager.default
        for name in (try? fm.contentsOfDirectory(atPath: root)) ?? [] {
            try? fm.removeItem(atPath: root + "/" + name)
        }
    }
}

#endif
