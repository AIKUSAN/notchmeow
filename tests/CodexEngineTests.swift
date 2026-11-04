import Foundation

@main
@MainActor
enum CodexEngineTests {
    static func main() {
        argsCases()
        levelsTable()
        envCases()
        prompt()
        folders()
        T.finish()
    }

    static func contains(_ argv: [String], _ slice: [String]) -> Bool {
        guard !slice.isEmpty, argv.count >= slice.count else { return false }
        return (0...(argv.count - slice.count)).contains { Array(argv[$0..<($0 + slice.count)]) == slice }
    }

    static func mode(_ path: String) -> Int? {
        (try? FileManager.default.attributesOfItem(atPath: path))?[.posixPermissions] as? Int
    }

    // MARK: - expected-args.json

    static func argsCases() {
        T.section("The command line of one turn")
        let data = T.fixture("codex/expected-args.json")
        T.check("base", CodexCommand.base, data["base"] as! [String])
        T.check("the shell-off set", CodexCommand.shellOff, data["shellOff"] as! [String])
        T.check("the model pattern", CodexCommand.modelPattern, data["modelPattern"] as! String)
        for c in data["cases"] as! [[String: Any]] {
            let name = c["name"] as! String
            let level = c["level"] as! String
            let model = c["model"] as? String
            let built = CodexCommand.arguments(level: level, model: model, images: c["images"] as! [String])
            if let argv = c["expect"] as? [String] {
                T.check(name, built, .arguments(argv))
            } else {
                let expect = c["expect"] as! [String: String]
                T.check(name, built, .refused(code: expect["error"]!))
            }
            if let cwd = c["cwd"] as? String {
                T.check("\(name): runs in", CodexCommand.workingFolderKind(level: level, folder: c["folder"] as? String), cwd)
            }
            if let length = c["modelLength"] as? Int, let model {
                T.check("\(name): model length", model.utf8.count, length)
            }
            if let model, ["none", "chat"].contains(level) {
                T.check("\(name): isValidModel", CodexCommand.isValidModel(model), c["expect"] is [String])
            }
        }
        T.check("the chat folder mode", "0" + String(CodexFolders.chatMode, radix: 8), data["chatFolderMode"] as! String)
        T.check("the image folder mode", "0" + String(CodexFolders.imageMode, radix: 8), data["imageFolderMode"] as! String)
    }

    // MARK: - levels.json

    static func levelsTable() {
        T.section("The levels the app offers")
        let levels = T.fixture("codex/levels.json")["levels"] as! [String: [String: Any]]
        let offered = levels.filter { $0.value["offered"] as! Bool }.map { $0.key }.sorted()
        T.check("the offered levels are the ones the command line allows", CodexCommand.offeredLevels.sorted(), offered)
        for key in offered {
            let shellOff = levels[key]!["shellOff"] as! Bool
            guard case .arguments(let argv) = CodexCommand.arguments(level: key, model: nil, images: []) else {
                T.checkTrue("\(key) builds a command line", false)
                continue
            }
            T.check("\(key): the shell-off set is in its arguments exactly when shellOff", contains(argv, CodexCommand.shellOff), shellOff)
        }
        T.check("the chat level's key", CodexLevel.chat.key, "chat")
        T.check("the quick actions' key", CodexLevel.noTools.key, "none")
    }

    // MARK: - expected-env.json

    static func envCases() {
        T.section("The environment of a run")
        let data = T.fixture("codex/expected-env.json")
        T.check("the stripped names", CodexCommand.strippedVariables, Set(data["stripped"] as! [String]))
        T.check("the stripped prefixes", CodexCommand.strippedPrefixes, data["strippedPrefixes"] as! [String])
        for c in data["cases"] as! [[String: Any]] {
            let platform = ClaudeCodePlatform(rawValue: c["platform"] as! String)!
            T.check(c["name"] as! String,
                    CodexCommand.environment(from: c["base"] as! [String: String], platform: platform),
                    c["expect"] as! [String: String])
        }
        T.check("the child's PATH puts the program's own folder first",
                CodexCommand.childEnvironment(from: ["PATH": "/usr/bin"], platform: .mac, executable: "/opt/x/codex")["PATH"],
                "/opt/x:/opt/homebrew/bin:/usr/local/bin:/usr/bin")
    }

    // MARK: - the prompt

    static func prompt() {
        T.section("The prompt")
        let instructions = "Instructions from NotchMeow, the app this chat runs in (not words of the user):"
        T.check("with a system prompt",
                CodexPrompt.build(ChatRequest(model: "", system: "S", messages: [.init(role: .user, parts: [.text("Hi")])])),
                CodexPrompt.Built(text: instructions + "\nS\n\nThe user's new message:\nHi", images: []))
        T.check("with an empty system prompt",
                CodexPrompt.build(ChatRequest(model: "", system: "", messages: [.init(role: .user, parts: [.text("Hi")])])),
                CodexPrompt.Built(text: "The user's new message:\nHi", images: []))
        let history = ChatRequest(model: "", system: "", messages: [
            .init(role: .user, parts: [.text("A")]),
            .init(role: .assistant, parts: [.text("B")]),
            .init(role: .user, parts: [.text("File: p.png"), .image(mime: "image/png", data: Data([1])), .text("C")]),
        ])
        T.check("an earlier chat and an image in the new message",
                CodexPrompt.build(history),
                CodexPrompt.Built(text: "Earlier in this chat (already answered):\nUser: A\nAssistant: B\n\nThe user's new message:\nFile: p.png\nC",
                                  images: [CodexPrompt.Image(mime: "image/png", data: Data([1]))]))
        T.check("a file's text is introduced by its name",
                CodexPrompt.build(ChatRequest(model: "", system: "", messages: [.init(role: .user, parts: [.fileText(name: "n.txt", text: "x")])])).text,
                "The user's new message:\nFile: n.txt\nx")
        T.check("jpeg is jpg", CodexPrompt.fileExtension(mime: "image/jpeg"), "jpg")
        T.check("heic is img", CodexPrompt.fileExtension(mime: "image/heic"), "img")
        T.check("gif is gif", CodexPrompt.fileExtension(mime: "image/gif"), "gif")
        T.check("webp is webp", CodexPrompt.fileExtension(mime: "image/webp"), "webp")
        T.check("a PDF is named, not read",
                CodexPrompt.build(ChatRequest(model: "", system: "", messages: [.init(role: .user, parts: [.pdf(name: "d.pdf", data: Data([0x25]))])])).text,
                "The user's new message:\nFile: d.pdf")
    }

    // MARK: - the folders

    static func folders() {
        T.section("The folders")
        let fm = FileManager.default
        let scratch = fm.temporaryDirectory.appendingPathComponent("codex-folders-\(UUID().uuidString)").path
        let chat = scratch + "/chat"
        defer {
            // The chat folder is 0500, so it is made writable again before the scratch folder is removed.
            try? fm.setAttributes([.posixPermissions: 0o700], ofItemAtPath: chat)
            try? fm.removeItem(atPath: scratch)
        }
        T.checkTrue("prepareChatFolder makes the folder", CodexFolders.prepareChatFolder(chat))
        T.check("the chat folder is mode 0500", mode(chat), 0o500)
        T.checkTrue("a second call is still true", CodexFolders.prepareChatFolder(chat))
        // The read-back: only exactly 0500 is the chat folder's mode, so a folder that stayed writable is refused.
        T.checkTrue("only 0500 is the chat folder's mode",
                    CodexFolders.folderModeIs0500(0o500) && !CodexFolders.folderModeIs0500(0o700)
                        && !CodexFolders.folderModeIs0500(0o501) && !CodexFolders.folderModeIs0500(nil))

        let root = scratch + "/images"
        let paths = CodexFolders.writeImages([CodexPrompt.Image(mime: "image/png", data: Data([1, 2]))], under: root, turn: "t1")
        T.check("writeImages returns the paths in order", paths, [root + "/t1/image-1.png"])
        T.check("the turn folder is mode 0700", mode(root + "/t1"), 0o700)
        T.check("the image file is mode 0600", mode(root + "/t1/image-1.png"), 0o600)
        CodexFolders.removeTurn(under: root, turn: "t1")
        T.check("removeTurn leaves the images folder with no entries", (try? fm.contentsOfDirectory(atPath: root)) ?? ["?"], [])
        CodexFolders.removeTurn(under: root, turn: "t1")

        // A write that fails part way: image-1 is written, then image-2's name is taken by a folder, so its exclusive
        // create fails. The turn folder is NotchMeow's own, so the failure removes it with what was written.
        let failing = scratch + "/failing"
        try! fm.createDirectory(atPath: failing + "/t2/image-2.png", withIntermediateDirectories: true)
        let png = CodexPrompt.Image(mime: "image/png", data: Data([1]))
        T.check("a write that fails part way returns nil", CodexFolders.writeImages([png, png], under: failing, turn: "t2"), nil)
        T.checkTrue("the turn folder is gone with what it held", !fm.fileExists(atPath: failing + "/t2"))

        // A symlink in the chat folder's place is refused before anything is changed, so its target keeps its mode.
        let target = scratch + "/target"
        try! fm.createDirectory(atPath: target, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let link = scratch + "/link"
        try! fm.createSymbolicLink(atPath: link, withDestinationPath: target)
        T.checkTrue("prepareChatFolder refuses a symlink", !CodexFolders.prepareChatFolder(link))
        T.check("and the link's target keeps mode 0700", mode(target), 0o700)
    }
}
