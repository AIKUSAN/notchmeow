import Foundation

@main
@MainActor
enum ClaudeCodeEngineTests {
    static func main() {
        arguments()
        environment()
        stdinLine()
        T.finish()
    }

    static func level(_ key: String, _ folder: String?) -> ClaudeCodeLevel {
        switch key {
        case "read": .readOnly(folder: folder ?? "")
        case "agent": .agent(folder: folder ?? "")
        case "none": .noTools
        default: .chatOnly
        }
    }

    // MARK: - expected-args.json

    static func arguments() {
        T.section("The command line of one turn")
        T.check("the none level has no folder", ClaudeCodeLevel.noTools.folder, nil)
        T.check("and its key is none", ClaudeCodeLevel.noTools.key, "none")
        T.check("none expects no tools in init", ClaudeCodeCommand.initTools(.noTools), [])
        T.check("the other levels do not check init", ClaudeCodeCommand.initTools(.chatOnly), nil)
        let data = T.fixture("claude-code/expected-args.json")
        let chatFolder = data["chatFolder"] as! String
        T.check("model aliases", ClaudeCodeModel.allCases.map(\.rawValue), data["models"] as! [String])
        for c in data["cases"] as! [[String: Any]] {
            let name = c["name"] as! String
            let turn = ClaudeCodeTurn(level: level(c["level"] as! String, c["folder"] as? String),
                                      model: ClaudeCodeModel(rawValue: c["model"] as! String)!,
                                      sessionID: c["sessionId"] as! String, resume: c["resume"] as! Bool,
                                      platform: ClaudeCodePlatform(rawValue: c["platform"] as! String)!)
            let argv = ClaudeCodeCommand.arguments(turn)
            T.check(name, argv, c["argv"] as! [String])
            let cwd = ClaudeCodeCommand.workingDirectory(turn, chatFolder: chatFolder)
            T.check("\(name): runs in", cwd, c["cwd"] as! String == "chatFolder" ? chatFolder : c["folder"] as! String)
            if let folder = c["folder"] as? String {
                T.checkTrue("\(name): the folder is not an argument", !argv.contains { $0.contains(folder) })
            }
            T.checkTrue("\(name): --bare is never used", !argv.contains("--bare"))
        }
    }

    // MARK: - expected-env.json

    static func environment() {
        T.section("The environment of a run")
        let data = T.fixture("claude-code/expected-env.json")
        T.check("stripped names", ClaudeCodeCommand.strippedVariables, Set(data["stripped"] as! [String]))
        T.check("stripped prefixes", ClaudeCodeCommand.strippedPrefixes, data["strippedPrefixes"] as! [String])
        for c in data["cases"] as! [[String: Any]] {
            let platform = ClaudeCodePlatform(rawValue: c["platform"] as! String)!
            T.check(c["name"] as! String,
                    ClaudeCodeCommand.environment(from: c["base"] as! [String: String], platform: platform),
                    c["expect"] as! [String: String])
        }
    }

    // MARK: - stdin

    static func stdinLine() {
        T.section("The message on stdin")
        let png = Data([0x89, 0x50, 0x4E, 0x47])
        let line = ClaudeCodeCommand.userLine(parts: [.fileText(name: "notes.txt", text: "hello"),
                                                      .image(mime: "image/png", data: png),
                                                      .pdf(name: "a.pdf", data: Data([0x25, 0x50])),
                                                      .text("What is in these? Zoé 🐱")])
        T.check("one line that ends with a newline", line.last, 0x0A)
        T.check("and has no other newline", line.dropLast().contains(0x0A), false)
        let json = try! JSONSerialization.jsonObject(with: line) as! [String: Any]
        T.check("a user message", json["type"] as? String, "user")
        T.checkTrue("parent_tool_use_id is null", json["parent_tool_use_id"] is NSNull)
        let message = json["message"] as! [String: Any]
        T.check("role", message["role"] as? String, "user")
        let blocks = message["content"] as! [[String: Any]]
        T.check("block types", blocks.map { $0["type"] as! String }, ["text", "image", "document", "text"])
        T.check("a file's text is introduced by its name", blocks[0]["text"] as? String, "File: notes.txt\n\nhello")
        T.check("the question keeps its Unicode", blocks[3]["text"] as? String, "What is in these? Zoé 🐱")
        let withRecap = ClaudeCodeCommand.userLine(parts: [.text("and now?")], preamble: "Earlier in this chat: …")
        let recapBlocks = ((try! JSONSerialization.jsonObject(with: withRecap) as! [String: Any])["message"] as! [String: Any])["content"] as! [[String: Any]]
        T.check("a recap comes first", recapBlocks.map { $0["text"] as! String }, ["Earlier in this chat: …", "and now?"])
        T.check("the note next to the engine's name says what it does, in plain text", ClaudeCodeEngine.note, "runs your installed Claude Code")
    }
}
