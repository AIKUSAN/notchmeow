import Foundation

@main
@MainActor
enum ClaudeCodeSessionTests {
    static func main() {
        sessions()
        recap()
        readiness()
        hookRouting()
        chips()
        signInWords()
        notes()
        quickHold()
        T.finish()
    }

    /// Mixed values compared as text.
    static func said(_ values: Any...) -> [String] { values.map { "\($0)" } }

    // MARK: - The quick-action hold

    static func quickHold() {
        T.section("A quick Explain's chat is held at no tools until the picker is used")
        let folder = "/Users/zoe/p"
        T.check("held, the next turn is no tools whatever the user chose", ClaudeQuickHold.level(held: true, chosen: .agent(folder: folder)), .noTools)
        T.check("not held, the chosen level is the next turn's", ClaudeQuickHold.level(held: false, chosen: .readOnly(folder: folder)), .readOnly(folder: folder))
        T.check("not held at Chat only, Chat only", ClaudeQuickHold.level(held: false, chosen: .chatOnly), .chatOnly)

        var ids = ["hold-1", "hold-2"].makeIterator()
        func next() -> String { ids.next()! }
        let chatFolder = "/support/NotchMeow/claude-chat"
        var chat = ClaudeChatSession(sessionID: next())
        chat.level = .noTools
        _ = chat.plan(chatFolder: chatFolder, newID: next)
        chat.confirmStarted(in: chatFolder)
        chat.level = .chatOnly
        let toChatOnly = chat.plan(chatFolder: chatFolder, newID: next)
        T.check("a session started at no tools, planned at Chat only, resumes: same id, no recap",
                said(toChatOnly.turn.sessionID, toChatOnly.turn.resume, toChatOnly.needsRecap), said("hold-1", true, false))

        var moved = chat
        moved.level = .readOnly(folder: folder)
        let toReadOnly = moved.plan(chatFolder: chatFolder, newID: next)
        T.check("a session started at no tools, planned at Read-only, starts afresh with a recap",
                said(toReadOnly.turn.sessionID, toReadOnly.needsRecap, toReadOnly.retired ?? "-"), said("hold-2", true, "hold-1"))
    }

    // MARK: - A chat's session

    static func sessions() {
        T.section("A chat's session")
        var ids = ["id-1", "id-2", "id-3"].makeIterator()
        func next() -> String { ids.next()! }
        var chat = ClaudeChatSession(sessionID: next())
        let chatFolder = "/support/NotchMeow/claude-chat"

        let first = chat.plan(chatFolder: chatFolder, newID: next)
        T.check("a new chat starts at Chat only, on a fresh session", said(first.turn.level == .chatOnly, first.turn.resume, first.needsRecap), said(true, false, false))
        T.check("with the id NotchMeow chose", first.turn.sessionID, "id-1")

        var again = chat
        T.check("a turn that never reached init is planned the same way", again.plan(chatFolder: chatFolder, newID: next).turn.resume, false)

        chat.confirmStarted(in: chatFolder)
        T.check("after init the next turn resumes", chat.plan(chatFolder: chatFolder, newID: next).turn.resume, true)

        chat.level = .readOnly(folder: "/Users/zoe/Projects/notchmeow")
        let moved = chat.plan(chatFolder: chatFolder, newID: next)
        T.check("a level change that moves the working folder starts a new session", said(moved.turn.sessionID, moved.turn.resume, moved.needsRecap), said("id-2", false, true))
        T.check("and retires the old one", moved.retired, "id-1")
        chat.confirmStarted(in: "/Users/zoe/Projects/notchmeow")

        chat.level = .agent(folder: "/Users/zoe/Projects/notchmeow")
        let kept = chat.plan(chatFolder: chatFolder, newID: next)
        T.check("Read-only to Agent in the same folder resumes the session, with the new flags",
                said(kept.turn.sessionID, kept.turn.resume, kept.needsRecap, kept.retired == nil), said("id-2", true, false, true))
        T.check("and the level is the new one", kept.turn.level, .agent(folder: "/Users/zoe/Projects/notchmeow"))

        chat.level = .chatOnly
        let back = chat.plan(chatFolder: chatFolder, newID: next)
        T.check("Agent back to Chat only moves it again: a new session and a recap", said(back.turn.sessionID, back.needsRecap, back.retired ?? "-"), said("id-3", true, "id-2"))

        var reset = chat
        let gone = reset.reset(newID: { "id-9" })
        T.check("a new conversation retires the id and starts clean", said(gone, reset.sessionID, reset.started, reset.level == .chatOnly), said("id-3", "id-9", false, true))
        let real = ClaudeChatSession.newID()
        T.check("a real id is a lower-case UUID", real == real.lowercased() && UUID(uuidString: real) != nil, true)
    }

    // MARK: - The recap

    static func recap() {
        T.section("The recap of a chat")
        T.check("nothing to recall", ClaudeCodeRecap.text(turns: []) == nil, true)
        let text = ClaudeCodeRecap.text(turns: [(.user, "What is in main.swift?"), (.assistant, "A greeting."), (.user, "  "), (.user, "Thanks")])!
        T.check("the words, in order, with who said them",
                text.components(separatedBy: "\n").dropFirst().map { $0 }, ["User: What is in main.swift?", "Assistant: A greeting.", "User: Thanks"])
        let long = String(repeating: "x", count: 5000)
        let cut = ClaudeCodeRecap.text(turns: [(.user, long)])!
        T.check("a long turn is cut", cut.count < 1700, true)
        let many = (0..<60).map { (ChatRequest.Role.user, "message \($0) " + String(repeating: "y", count: 1200)) }
        let recent = ClaudeCodeRecap.text(turns: many)!
        T.check("only the most recent turns, within the budget", recent.count <= ClaudeCodeRecap.maxChars + 200 && recent.contains("message 59") && !recent.contains("message 0 "), true)
    }

    // MARK: - Agent needs the hooks

    static func readiness() {
        T.section("Agent needs NotchMeow's hooks")
        T.check("with them", ClaudeAgentReadiness.check(hooksInstalled: true), .ready)
        T.check("without them", ClaudeAgentReadiness.check(hooksInstalled: false), .needsHooks)
        T.checkTrue("the note says what to do", ClaudeAgentReadiness.hooksNote.contains("Settings"))
    }

    // MARK: - hook-routing.json

    static func hookRouting() {
        T.section("Which hook payloads belong to a chat (hook-routing.json)")
        let data = T.fixture("claude-code/hook-routing.json")
        let live = Set(data["live"] as! [String])
        for c in data["cases"] as! [[String: Any]] {
            let route = ClaudeHookRouting.route(payload: c["payload"] as! [String: Any], live: (c["live"] as? [String]).map(Set.init) ?? live)
            let expect = c["expect"] as! String
            T.check(c["name"] as! String, route == .other ? "other" : "chat", expect)
        }
        let payload = ["hook_event_name": "PermissionRequest", "session_id": "chat-1", "tool_name": "Bash"] as [String: Any]
        T.check("the route names the chat it goes to", ClaudeHookRouting.route(payload: payload, live: ["chat-1"]), .chat(sessionID: "chat-1"))
    }

    // MARK: - labels.json

    static func chips() {
        T.section("The chips (labels.json)")
        let data = T.fixture("claude-code/labels.json")
        for c in data["modelChip"] as! [[String: Any]] {
            let paid = (c["paidBy"] as? String).flatMap(EngineReport.Payer.init(rawValue:))
            T.check(c["name"] as! String, ClaudeCodeText.modelChip(authMethod: c["authMethod"] as? String, paidBy: paid), c["expect"] as! String)
        }
        for c in data["levelChip"] as! [[String: Any]] {
            let folder = c["folder"] as? String ?? ""
            let level: ClaudeCodeLevel = switch c["level"] as! String { case "read": .readOnly(folder: folder); case "agent": .agent(folder: folder); case "none": .noTools; default: .chatOnly }
            T.check("\(c["level"] as! String) \(folder)", ClaudeCodeText.levelChip(level), c["expect"] as! String)
        }
    }

    static func signInWords() {
        T.section("How Claude Code is signed in")
        T.check("a plan", ClaudeCodeText.signInWords("claude.ai"), "your Claude plan")
        T.check("an API key helper", ClaudeCodeText.signInWords("api_key_helper"), "an API key helper")
        T.check("a method this build does not know", ClaudeCodeText.signInWords("something_new"), "its own sign-in")
        T.check("none given", ClaudeCodeText.signInWords(nil), "its own sign-in")
    }

    // MARK: - copy.json

    static func notes() {
        T.section("What the chat says (copy.json)")
        let data = T.fixture("claude-code/copy.json")
        for c in data["cases"] as! [[String: Any]] {
            let resets = (c["resetsAt"] as? NSNumber).map { Date(timeIntervalSince1970: $0.doubleValue) }
            let error = AIError(kind: AIErrorKind(rawValue: c["kind"] as! String)!, code: c["code"] as? String, resetsAt: resets)
            let note = ClaudeCodeText.message(for: error, timeZone: TimeZone(identifier: c["timeZone"] as? String ?? "UTC")!,
                                              locale: Locale(identifier: c["locale"] as? String ?? "en_US"))
            T.check("\(c["code"] as! String) \(c["locale"] as? String ?? "")", note?.text, c["text"] as? String)
            T.check("\(c["code"] as! String): the one button", note?.action?.rawValue, c["action"] as? String)
        }
        T.check("any other error is left to AIMessages", ClaudeCodeText.message(for: AIError(kind: .server)) == nil, true)
    }
}
