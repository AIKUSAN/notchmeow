import Foundation

// What a Codex turn means: the fixtures in tests/fixtures/ai/codex/ replayed through CodexStreamParser, plus the edges
// the fixtures do not cover. The fake codex is never run here: the transcripts are read as text.

@main
@MainActor
enum CodexParserTests {
    static func main() {
        tables()
        parseCases()
        stopsAtOnce()
        edges()
        disallowed()
        allowed()
        partialTexts()
        lineReader()
        T.finish()
    }

    // MARK: - levels.json and copy.json

    static func tables() {
        T.section("The tables (levels.json, copy.json)")
        let levels = T.fixture("codex/levels.json")
        let spec = levels["levels"] as! [String: [String: Any]]
        for key in ["chat", "none", "read"] {
            T.check("items of \(key)", CodexLevels.items[key] ?? [], Set(spec[key]!["items"] as! [String]))
        }
        T.check("notes", CodexLevels.notes, Set(levels["notes"] as! [String]))
        T.check("retryNotes", CodexLevels.retryNotes, levels["retryNotes"] as! [String])
        T.check("stepFields", CodexLevels.stepFields, (levels["stepFields"] as! [String: [String]]).mapValues { $0[0] })
        T.check("stepKinds", CodexLevels.stepKinds, levels["stepKinds"] as! [String: String])
        T.check("stepFieldCap", CodexLevels.stepFieldCap, levels["stepFieldCap"] as! Int)

        let copy = T.fixture("codex/copy.json")
        let matches = (copy["match"] as! [[String: Any]]).map { m in
            CodexLevels.Match(code: m["code"] as! String, inStderr: (m["in"] as! String) == "stderr",
                              contains: m["contains"] as! [String])
        }
        T.check("match table, in order", CodexLevels.matches, matches)
        codeKinds(copy["cases"] as! [[String: Any]])
    }

    /// Each of the ten codes has the kind copy.json gives it, and copy.json names no other code. Every code is covered
    /// by copy.json, so none needs an assertion of its own.
    static func codeKinds(_ cases: [[String: Any]]) {
        let all = [CodexError.missing, CodexError.signedOut, CodexError.planLimit, CodexError.tooOld,
                   CodexError.unreadable, CodexError.crashed, CodexError.badModel, CodexError.modelRefused,
                   CodexError.levelExceeded, CodexError.levelUnavailable]
        T.check("copy.json names exactly the ten codes", Set(cases.map { $0["code"] as! String }), Set(all))
        for code in all {
            let row = cases.first { $0["code"] as? String == code }
            T.check("\(code) has its copy.json kind", CodexError.kind(of: code).rawValue,
                    (row?["kind"] as? String) ?? "no copy.json row")
        }
        T.check("a code no table names is interrupted (the fail-safe)",
                CodexError.kind(of: "nm_unknown").rawValue, "interrupted")
    }

    // MARK: - expected-parse.json

    static func parseCases() {
        T.section("What a transcript means (expected-parse.json)")
        let data = T.fixture("codex/expected-parse.json")
        for c in data["cases"] as! [[String: Any]] {
            let name = c["name"] as! String
            let turn = CodexStreamParser.parse(lines: fileLines("codex/transcripts/\(c["transcript"] as! String)"),
                                               exit: Int32(c["exit"] as! Int), stderr: c["stderr"] as! String,
                                               level: c["level"] as! String)
            // The fixture's <cmd200> stands for the first 200 characters of the long command: "cmd " fifty times.
            let expected = canonical(c["expect"] as Any)
                .replacingOccurrences(of: "<cmd200>", with: String(repeating: "cmd ", count: 50))
            T.check(name, canonical(json(turn)), expected)
        }
    }

    // MARK: - Stopping

    static func stopsAtOnce() {
        T.section("A stopped turn: consume returns false at once")
        var parser = CodexStreamParser(level: "chat")
        var answers: [Bool] = []
        for line in fileLines("codex/transcripts/chat-wants-command.jsonl") {
            let goOn = parser.consume(line: line)
            answers.append(goOn)
            if !goOn { break }
        }
        T.check("true before the command, false on it", answers, [true, true, true, true, false])
    }

    // MARK: - Edges the fixtures do not cover

    static func edges() {
        T.section("Edges the fixtures do not cover")
        let thread = #"{"type":"thread.started","thread_id":"t"}"#
        let done = #"{"type":"turn.completed","usage":{"input_tokens":1}}"#
        let retry = #"{"type":"error","message":"Reconnecting... 2/5 (stream closed)"}"#
        func message(_ text: String) -> String {
            #"{"type":"item.completed","item":{"id":"i","type":"agent_message","text":"\#(text)"}}"#
        }
        func run(_ lines: [String], exit: Int32? = 0, stderr: String = "", level: String = "chat") -> CodexTurn {
            CodexStreamParser.parse(lines: lines, exit: exit, stderr: stderr, level: level)
        }

        let unknown = run([thread, done], level: "agent")
        T.check("a level that is not offered fails at once", unknown.error?.code, CodexError.levelUnavailable)
        T.checkTrue("and has no thread", unknown.thread == nil)
        T.checkTrue("the read level is in the table", run([thread, done], level: "read").error == nil)

        T.check("a disallowed item that only starts stops the turn",
                run([message("half"), #"{"type":"item.started","item":{"id":"i","type":"file_change"}}"#]).error?.code,
                CodexError.levelExceeded)
        T.check("an item with no type fails closed",
                run([#"{"type":"item.completed","item":{"id":"i"}}"#]).error?.code, CodexError.levelExceeded)
        T.check("a disallowed item drops the text said before it",
                run([message("half"), #"{"type":"item.completed","item":{"id":"m","type":"mcp_tool_call"}}"#, done]).text, "")

        let after = CodexStreamParser.parse(lines: [message("a"), done, message("b")], exit: 0, stderr: "", level: "chat")
        T.check("turn.completed does not stop the parser; later text is kept", after.text, "a\n\nb")
        T.checkTrue("and the turn is finished", after.finished)

        T.check("a retry note is skipped, not a failure", run([retry, message("ok"), done]).text, "ok")
        T.check("a top-level error with a plan-limit word is the plan's limit",
                run([#"{"type":"error","message":"You have a usage limit"}"#]).error?.kind, .billing)
        T.check("matching is case-sensitive",
                run([#"{"type":"error","message":"Usage Limit"}"#]).error?.code, CodexError.crashed)
        T.check("the first match in table order wins",
                run([#"{"type":"turn.failed","error":{"message":"usage limit: 401 Unauthorized"}}"#]).error?.code,
                CodexError.planLimit)
        T.checkTrue("a failure keeps no message text",
                run([#"{"type":"turn.failed","error":{"message":"usage limit secret-token-xyz"}}"#]).error?.message == nil)

        T.check("lines that are not JSON do not count as output",
                run(["not json", ""], exit: 0).error?.code, CodexError.unreadable)
        T.check("no output with a failing exit is a crash", run([], exit: 1).error?.code, CodexError.crashed)
        T.check("no exit status at all is a crash", run([], exit: nil).error?.code, CodexError.crashed)
        T.check("Not logged in on stderr is signed out", run([], exit: 1, stderr: "Not logged in").error?.kind, .auth)

        T.checkTrue("a thread with no id is an engine with a null id",
                    run([#"{"type":"thread.started"}"#, done]).thread.map { $0 == nil } == true)
        T.check("a failure keeps the thread",
                run([thread, #"{"type":"turn.failed","error":{"message":"boom"}}"#]).thread.flatMap { $0 }, "t")
        T.check("thread_id wins even with another key",
                run([#"{"type":"thread.started","thread_id":"t","other":"x"}"#, done]).thread.flatMap { $0 }, "t")

        // A Swift-only limit, documented: JSONSerialization rejects the bare NaN that json.loads accepts, so such a line is
        // skipped like any other line that is not JSON. serde cannot emit NaN, and the shell-off flags are the barrier.
        let nan = #"{"type":"item.started","item":{"id":"i","type":"command_execution","command":"x"},"x":NaN}"#
        T.checkTrue("a chat command line with a bare NaN is skipped, not a failure", run([thread, nan, done]).error == nil)
        T.checkTrue("and the turn still finishes", run([thread, nan, done]).finished)

        // The step value is cut at 200 Unicode scalars, not characters or bytes.
        // "e\u{301}" is two scalars and one Character: a Character-based cut would keep 200 pairs (400 scalars) and fail.
        for scalar in ["\u{E9}", "\u{1F600}", "e\u{301}"] {
            let full = String(repeating: scalar, count: 250)
            let line = #"{"type":"item.completed","item":{"id":"c","type":"command_execution","command":"\#(full)","status":"completed"}}"#
            let value = run([thread, line, done], level: "read").steps.first?.value ?? ""
            let firstScalars = String(String.UnicodeScalarView(full.unicodeScalars.prefix(200)))
            T.check("a step of \(scalar) keeps 200 Unicode scalars", value.unicodeScalars.count, 200)
            T.check("and they are the first 200", value, firstScalars)
        }
    }

    // MARK: - The parser matrix (review gap)

    static let thread = #"{"type":"thread.started","thread_id":"t"}"#
    static let finished = #"{"type":"turn.completed","usage":{"input_tokens":1}}"#

    /// Every item type a level does not allow ends the turn with nm_level_exceeded and no text, in both phases and at both levels.
    static func disallowed() {
        T.section("Every item a level does not allow ends the turn (both phases, both levels)")
        let types: [String?] = ["command_execution", "file_change", "web_search", "mcp_tool_call", "collab_tool_call",
                                "some_future_type", nil]
        var failed: [String] = []
        for level in ["chat", "none"] {
            for phase in ["item.started", "item.completed"] {
                for type in types {
                    let typeField = type.map { #","type":"\#($0)""# } ?? ""
                    let line = #"{"type":"\#(phase)","item":{"id":"i"\#(typeField)}}"#
                    let turn = CodexStreamParser.parse(lines: [thread, line, finished], exit: 0, stderr: "", level: level)
                    if turn.error?.code != CodexError.levelExceeded || !turn.text.isEmpty {
                        failed.append("\(level) \(phase) \(type ?? "no type")")
                    }
                }
            }
        }
        T.check("all \(types.count * 4) cases end with nm_level_exceeded and no text", failed, [])
    }

    /// The items a level allows give no error in either phase, at either level.
    static func allowed() {
        T.section("The allowed items give no error, in either phase, at either level")
        let items = [#"{"id":"m","type":"agent_message","text":"ok"}"#, #"{"id":"r","type":"reasoning","text":"thinking"}"#,
                     #"{"id":"t","type":"todo_list","items":[]}"#, #"{"id":"e","type":"error","message":"a note"}"#]
        var failed: [String] = []
        for level in ["chat", "none"] {
            for phase in ["item.started", "item.completed"] {
                for item in items {
                    let turn = CodexStreamParser.parse(lines: [thread, #"{"type":"\#(phase)","item":\#(item)}"#, finished],
                                                       exit: 0, stderr: "", level: level)
                    if turn.error != nil { failed.append("\(level) \(phase) \(item)") }
                }
            }
        }
        T.check("no allowed item is an error", failed, [])
    }

    /// A turn that did not finish shows no text, even a complete message; a disallowed item after a finished turn still fails it.
    static func partialTexts() {
        T.section("A turn that did not finish shows no text")
        let message = #"{"type":"item.completed","item":{"id":"m","type":"agent_message","text":"partial"}}"#
        for exit: Int32 in [0, 1] {
            let turn = CodexStreamParser.parse(lines: [thread, message], exit: exit, stderr: "", level: "chat")
            T.check("exit \(exit): no text", turn.text, "")
            T.check("exit \(exit): a crash", turn.error?.code, CodexError.crashed)
            T.checkTrue("exit \(exit): not finished", !turn.finished)
        }
        let mcp = #"{"type":"item.completed","item":{"id":"x","type":"mcp_tool_call"}}"#
        let late = CodexStreamParser.parse(lines: [message, finished, mcp], exit: 0, stderr: "", level: "chat")
        T.check("a message, a finished turn, then an mcp item: nm_level_exceeded", late.error?.code, CodexError.levelExceeded)
        T.check("and no text", late.text, "")
    }

    // MARK: - CodexLineReader (the 1 MiB cap, CRLF and a last line with no LF)

    static func lineReader() {
        T.section("CodexLineReader: the cap, CRLF and the last line")
        let limit = CodexLineReader.limit
        let lf = UInt8(0x0A)
        func run(_ bytes: [UInt8]) -> CodexLineReader.Step {
            var reader = CodexLineReader()
            var step = CodexLineReader.Step.pending
            for byte in bytes {
                step = reader.push(byte)
                if step == .tooLong { break }
            }
            return step
        }
        func lineBytes(_ step: CodexLineReader.Step) -> Int? {
            if case .line(let text) = step { return text.utf8.count }
            return nil
        }
        let a = UInt8(0x61)
        T.check("exactly the limit, then LF, is a line of the limit",
                lineBytes(run([UInt8](repeating: a, count: limit) + [lf])), limit)
        T.checkTrue("one byte more is too long, before the LF",
                    run([UInt8](repeating: a, count: limit + 1) + [lf]) == .tooLong)
        T.check("CRLF drops the CR", run(Array("ab\r\n".utf8)), .line("ab"))
        T.check("a line with no CR is kept as it is", run(Array("ab\n".utf8)), .line("ab"))

        var reader = CodexLineReader()
        for byte in "tail".utf8 { _ = reader.push(byte) }
        T.check("flush returns a last line that has no LF", reader.flush(), "tail")
        T.check("and then there is nothing to flush", reader.flush(), nil)
    }

    // MARK: - Helpers

    static func fileLines(_ relative: String) -> [String] {
        let raw = try! String(contentsOf: T.fixtureURL(relative), encoding: .utf8)
        return raw.components(separatedBy: "\n").filter { !$0.isEmpty }
    }

    static func opt(_ value: Any?) -> Any {
        value ?? NSNull()
    }

    /// The fixture's shape of a turn: engine, text, steps, finish and error, as JSON values.
    static func json(_ turn: CodexTurn) -> [String: Any] {
        var engine: Any = NSNull()
        if let id = turn.thread {
            engine = ["threadId": opt(id), "version": NSNull()] as [String: Any]
        }
        let steps: [[String: Any]] = turn.steps.map { step in
            [step.field: step.value, "kind": step.kind, "state": step.done ? "done" : "failed"]
        }
        var finish: Any = NSNull()
        if turn.finished {
            finish = ["usage": opt(turn.usage.map { $0 as [String: Any] })] as [String: Any]
        }
        var error: Any = NSNull()
        if let err = turn.error {
            error = ["kind": err.kind.rawValue, "code": opt(err.code), "resetsAt": NSNull()] as [String: Any]
        }
        return ["engine": engine, "text": turn.text, "steps": steps, "finish": finish, "error": error]
    }

    static func canonical(_ value: Any) -> String {
        let data = try! JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .fragmentsAllowed])
        return String(decoding: data, as: UTF8.self)
    }
}
