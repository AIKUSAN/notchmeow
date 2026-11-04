import Foundation

@main
@MainActor
enum ClaudeCodeParserTests {
    /// A whole run folded the way the chat sees it.
    struct Folded {
        var engine: EngineReport?
        var text = ""
        var steps: [ChatStep] = []
        var finish: FinishReason?
        var error: AIError?
    }

    static func level(_ key: String, _ folder: String?) -> ClaudeCodeLevel {
        switch key {
        case "read": .readOnly(folder: folder ?? "")
        case "agent": .agent(folder: folder ?? "")
        case "none": .noTools
        default: .chatOnly
        }
    }

    static func fold(lines: [String], stderr: String, level key: String = "chat") -> Folded {
        var parser = ClaudeStreamParser(initTools: ClaudeCodeCommand.initTools(level(key, nil)))
        var out = Folded()
        for line in lines {
            for chunk in parser.consume(line: line) {
                switch chunk {
                case .engine(let r): out.engine = r
                case .text(let t): out.text += t
                case .finish(let f): out.finish = f
                case .step(let s):
                    if let i = out.steps.firstIndex(where: { $0.id == s.id }) { out.steps[i] = s } else { out.steps.append(s) }
                default: break
                }
            }
        }
        out.error = parser.failure(stderr: stderr)
        return out
    }

    static func main() {
        transcripts()
        edges()
        T.finish()
    }

    // MARK: - expected-parse.json

    static func transcripts() {
        T.section("What a transcript means (expected-parse.json)")
        let data = T.fixture("claude-code/expected-parse.json")
        let sid = data["sessionId"] as! String
        for c in data["cases"] as! [[String: Any]] {
            let name = c["name"] as! String
            let path = T.fixtureURL("claude-code/transcripts/\(c["transcript"] as! String)")
            let raw = try! String(contentsOf: path, encoding: .utf8)
                .replacingOccurrences(of: "__SESSION_ID__", with: sid)
                .replacingOccurrences(of: "__CWD__", with: data["cwd"] as! String)
            let got = fold(lines: raw.components(separatedBy: "\n").filter { !$0.isEmpty }, stderr: c["stderr"] as! String,
                           level: c["level"] as? String ?? "chat")
            let expect = c["expect"] as! [String: Any]

            if let e = expect["engine"] as? [String: Any] {
                T.check("\(name): engine", got.engine.map { [$0.sessionID, $0.model, $0.paidBy.rawValue, $0.version ?? ""] },
                        [sid, e["model"] as! String, e["paidBy"] as! String, e["version"] as! String])
            } else {
                T.check("\(name): no engine report", got.engine == nil, true)
            }
            T.check("\(name): text", got.text, expect["text"] as! String)
            let steps = (expect["steps"] as! [[String: Any]]).map { s in
                ChatStep(id: s["id"] as! String, tool: s["tool"] as! String, input: s["input"] as! [String: String],
                         state: ChatStep.State(rawValue: s["state"] as! String)!)
            }
            T.check("\(name): steps", got.steps, steps)
            T.check("\(name): finish", got.finish?.rawValue, expect["finish"] as? String)
            if let e = expect["error"] as? [String: Any] {
                T.check("\(name): error kind", got.error?.kind.rawValue, e["kind"] as? String)
                T.check("\(name): error code", got.error?.code, e["code"] as? String)
                T.check("\(name): resets at", got.error?.resetsAt.map { Int64($0.timeIntervalSince1970) }, (e["resetsAt"] as? NSNumber)?.int64Value)
            } else {
                T.check("\(name): no error", got.error == nil, true)
            }
        }
    }

    // MARK: - Shapes no fixture covers

    static func edges() {
        T.section("Tolerance")
        let junk = fold(lines: ["", "not json", "[1,2]", #"{"type":"mystery"}"#, #"{"type":"stream_event"}"#,
                                #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"hi"}}}"#],
                        stderr: "")
        T.check("junk lines are skipped and the text survives", junk.text, "hi")
        T.check("a run with no result is a crash", junk.error?.code, ClaudeCodeError.crashed)

        let numberTime = fold(lines: [#"{"type":"rate_limit_event","rate_limit_info":{"status":"rejected","resetsAt":"soon"}}"#,
                                      #"{"type":"result","subtype":"success","is_error":true,"result":"limit"}"#], stderr: "")
        T.check("a rejection with a time we cannot read is still the plan's limit", numberTime.error?.code, ClaudeCodeError.planLimit)
        T.check("and carries no time", numberTime.error?.resetsAt == nil, true)

        let allowed = fold(lines: [#"{"type":"rate_limit_event","rate_limit_info":{"status":"allowed_warning","resetsAt":1791301500}}"#,
                                   #"{"type":"result","subtype":"success","is_error":false,"result":"ok"}"#], stderr: "")
        T.check("a warning is not a failure", allowed.error == nil, true)

        let longInput = String(repeating: "é", count: 300)
        let capped = fold(lines: [
            #"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"t1","name":"Bash","input":{}}}}"#,
            #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{"command":"\#(longInput)","timeout":5000,"content":"secret"}}]}}"#,
            #"{"type":"result","subtype":"success","is_error":false,"result":""}"#], stderr: "")
        T.check("a step's input is cut to 200 scalars", capped.steps.first?.input["command"]?.unicodeScalars.count, 200)
        T.check("and keeps only the fields that name the work", capped.steps.first?.input.keys.sorted(), ["command"])
        T.check("a tool use the result never answered stays running", capped.steps.first?.state, .running)
        let mixed = [ChatStep(id: "a", tool: "Read", state: .done), ChatStep(id: "b", tool: "Bash", state: .running), ChatStep(id: "c", tool: "Edit", state: .failed)]
        T.check("Stop ends a step that never finished as stopped, and leaves the others alone", ChatStep.endingUnfinished(mixed).map(\.state), [.done, .stopped, .failed])

        noToolsCheck()

        T.section("Failures")
        func code(_ stderr: String, lines: [String] = []) -> String? {
            fold(lines: lines, stderr: stderr).error?.code
        }
        T.check("git-bash in any case", code("CLAUDE_CODE_GIT_BASH_PATH=C:\\x"), ClaudeCodeError.needsGit)
        T.check("a signed-out result without an assistant error",
                code("", lines: [#"{"type":"result","subtype":"success","is_error":true,"result":"Not logged in · Please run /login"}"#]),
                ClaudeCodeError.signedOut)
        T.check("billing_error is billing", fold(lines: [#"{"type":"assistant","error":"billing_error","message":{"content":[]}}"#,
                                                         #"{"type":"result","subtype":"success","is_error":true,"result":"x"}"#], stderr: "").error?.kind, .billing)
        T.check("server_error is a server failure", fold(lines: [#"{"type":"assistant","error":"server_error","message":{"content":[]}}"#,
                                                                #"{"type":"result","subtype":"success","is_error":true,"result":"x"}"#], stderr: "").error?.kind, .server)
        T.check("an unknown error result is a crash, never a guess",
                code("", lines: [#"{"type":"result","subtype":"error_during_execution","is_error":true,"result":"boom"}"#]),
                ClaudeCodeError.crashed)
    }

    // MARK: - The no-tools level's init check (refusedTools)

    static func noToolsCheck() {
        T.section("The no-tools level's init check")
        let initOK = #"{"type":"system","subtype":"init","session_id":"s","model":"m","tools":[],"apiKeySource":"none","claude_code_version":"2.1.0"}"#
        let leaky = #"{"type":"system","subtype":"init","session_id":"s","model":"m","tools":["Read"],"apiKeySource":"none","claude_code_version":"2.1.0"}"#
        let text = #"{"type":"stream_event","event":{"type":"content_block_delta","delta":{"type":"text_delta","text":"hi"}}}"#
        let toolStart = #"{"type":"stream_event","event":{"type":"content_block_start","index":0,"content_block":{"type":"tool_use","id":"t1","name":"Bash","input":{}}}}"#
        let toolUse = #"{"type":"assistant","message":{"content":[{"type":"tool_use","id":"t1","name":"Bash","input":{}}]}}"#
        let toolResult = #"{"type":"user","message":{"content":[{"type":"tool_result","tool_use_id":"t1","is_error":false}]}}"#
        func checking() -> ClaudeStreamParser { ClaudeStreamParser(initTools: []) }

        var p = checking()
        _ = p.consume(line: leaky)
        T.checkTrue("a tool in init refuses", p.refusedTools)
        T.checkTrue("the init's engine report is still reported", p.engine?.sessionID == "s")
        T.checkTrue("a further clean init after a refusal gives nothing", p.consume(line: initOK).isEmpty)
        T.checkTrue("a text line after a refusal gives nothing", p.consume(line: text).isEmpty)
        T.checkTrue("and the refusal holds", p.refusedTools)
        T.check("the refusal is nm_tools_present, a bad request", p.failure(stderr: "")?.code, ClaudeCodeError.toolsPresent)
        T.check("with its kind", p.failure(stderr: "")?.kind, .badRequest)
        T.check("and no reset time", p.failure(stderr: "")?.resetsAt == nil, true)

        var list = checking()
        _ = list.consume(line: #"{"type":"system","subtype":"init","session_id":"s","model":"m","tools":["Read",1]}"#)
        T.checkTrue("a non-string element in tools refuses", list.refusedTools)
        var missing = checking()
        _ = missing.consume(line: #"{"type":"system","subtype":"init","session_id":"s","model":"m"}"#)
        T.checkTrue("a missing tools key refuses", missing.refusedTools)

        for (name, line) in [("a text delta", text), ("a tool_use start", toolStart), ("a tool_use message", toolUse),
                             ("a tool_result", toolResult)] {
            var early = checking()
            _ = early.consume(line: line)
            T.checkTrue("\(name) before init refuses", early.refusedTools)
        }

        var quiet = checking()
        _ = quiet.consume(line: #"{"type":"system","subtype":"ui_invalidate"}"#)
        _ = quiet.consume(line: #"{"type":"rate_limit_event","rate_limit_info":{"status":"allowed"}}"#)
        _ = quiet.consume(line: #"{"type":"assistant","error":"authentication_failed","message":{"content":[]}}"#)
        T.checkTrue("ui_invalidate, a rate limit and an assistant error before init do not refuse", !quiet.refusedTools)
        _ = quiet.consume(line: initOK)
        T.checkTrue("a passing init lets the run go on", !quiet.refusedTools)
        T.check("and a signed-out assistant error is still signed out", quiet.failure(stderr: "")?.code, ClaudeCodeError.signedOut)

        var afterInit = checking()
        _ = afterInit.consume(line: initOK)
        _ = afterInit.consume(line: toolUse)
        T.checkTrue("a tool_use after a passing init does not refuse (the check is pre-init only)", !afterInit.refusedTools)

        var textBeforeInit = checking()
        _ = textBeforeInit.consume(line: #"{"type":"assistant","message":{"content":[{"type":"text","text":"hi"}]}}"#)
        T.checkTrue("a text-only assistant block before init does not refuse", !textBeforeInit.refusedTools)

        var plain = ClaudeStreamParser()
        _ = plain.consume(line: leaky)
        T.checkTrue("a level that does not check its tools never refuses", !plain.refusedTools)
    }
}
