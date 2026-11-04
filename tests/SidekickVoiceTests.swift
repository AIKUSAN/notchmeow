import Foundation

// The sanity check against tests/fixtures/sidekick/voice-cases.json, the prompt's size, and the local voice with fake providers that record every request: only a local model is asked, a cloud
// or network one never is, a slow or odd answer leaves the template, and the request holds the template's words and nothing else. Run through scripts/test-sidekick-voice.sh.

final class Recorder: @unchecked Sendable {
    private let lock = NSLock()
    private var items: [ChatRequest] = []
    func add(_ r: ChatRequest) { lock.withLock { items.append(r) } }
    var all: [ChatRequest] { lock.withLock { items } }
}

/// A provider that records the request and answers with `reply` (or never answers, or fails).
struct FakeProvider: ModelProvider {
    enum Mode: Sendable { case reply(String), hang, fail }
    let id: AIProviderID
    let placement: AIPlacement
    let recorder: Recorder
    let mode: Mode
    var displayName: String { "fake \(placement.rawValue)" }
    func listModels() async throws -> [ModelInfo] { [] }
    func stream(_ request: ChatRequest) -> AsyncThrowingStream<ChatChunk, Error> {
        recorder.add(request)
        return AsyncThrowingStream { c in
            switch mode {
            case .reply(let t): c.yield(.text(t)); c.yield(.finish(.stop)); c.finish()
            case .hang: break
            case .fail: c.finish(throwing: AIError(kind: .unreachable))
            }
        }
    }
}

@main
enum SidekickVoiceTests {
    static func rows(_ x: Any?) -> [[String: Any]] { x as! [[String: Any]] }

    @MainActor static func main() async {
        let fx = CT.fixture("voice-cases.json", dir: "sidekick")
        let cases = rows(fx["cases"])
        CT.section("acceptNicerLine: \(cases.count) cases")
        var diffs: [String] = []
        for c in cases where SidekickVoice.accept(c["line"], facts: c["facts"]) != (c["ok"] as! Bool) { diffs.append(c["name"] as! String) }
        CT.checkRows("every sentence is accepted or refused as the fixture says", diffs)

        CT.section("the prompt")
        let facts = [SKFacts(agent: "Claude Code", agentId: "integration_claude", project: "proj", steps: 12, stepsAtLeast: false, files: ["a.js"], more: 0, errors: 0, approvals: 0, end: "finished", quietMinutes: 0)]
        let line = "While you were away, Claude Code in proj ran 12 steps, edited a.js, and finished."
        let p = SidekickVoice.prompt(lines: [line])!
        CT.checkTrue("it holds the template's line", p.contains(line))
        CT.checkTrue("and is under 800 characters", p.count <= 800)
        CT.check("a line too long for the budget gives no prompt", SidekickVoice.prompt(lines: [String(repeating: "x", count: 900)]), nil)
        CT.checkTrue("lines that do not all fit are cut from the end", SidekickVoice.prompt(lines: [line, String(repeating: "y", count: 790)])!.contains(line) && !SidekickVoice.prompt(lines: [line, String(repeating: "y", count: 790)])!.contains("yyy"))

        CT.section("which model: only a local one, by the router's own local choice")
        let ollama = LocalCandidate(provider: .ollama, model: "qwen", placement: .local, serverID: "ollama")
        let lan = LocalCandidate(provider: .custom, model: "big", placement: .network, serverID: "custom-1")
        let cloud = LocalCandidate(provider: .anthropic, model: "c", placement: .cloud)
        CT.check("a local server is chosen", SidekickVoiceLocal.choice(localReady: [ollama], lastUsedLocal: nil, appleReady: false)?.model, "qwen")
        CT.check("a server on the network is never chosen, even alone", SidekickVoiceLocal.choice(localReady: [lan], lastUsedLocal: nil, appleReady: false), nil)
        CT.check("nor a cloud one", SidekickVoiceLocal.choice(localReady: [cloud, lan], lastUsedLocal: nil, appleReady: false), nil)
        CT.check("the local one wins over a network one listed first", SidekickVoiceLocal.choice(localReady: [lan, ollama], lastUsedLocal: ModelRef(provider: .custom, model: "big", serverID: "custom-1"), appleReady: false)?.model, "qwen")
        CT.check("Apple on-device when nothing else is local", SidekickVoiceLocal.choice(localReady: [lan], lastUsedLocal: nil, appleReady: true)?.provider, .apple)
        CT.check("the last used local model comes first", SidekickVoiceLocal.choice(localReady: [ollama, LocalCandidate(provider: .lmstudio, model: "other", placement: .local, serverID: "lmstudio")], lastUsedLocal: ModelRef(provider: .lmstudio, model: "other"), appleReady: false)?.model, "other")

        CT.section("the local voice: one request, to a local model, with the template's words only")
        let local = Recorder(), remote = Recorder()
        func make(_ reply: FakeProvider.Mode) -> @Sendable (ChatTarget) -> any ModelProvider {
            { t in FakeProvider(id: t.provider, placement: t.placement, recorder: t.placement == .local ? local : remote, mode: reply) }
        }
        let nice = "Claude Code finished 12 steps in proj and edited a.js."
        let got = await SidekickVoiceLocal.nicerLine(lines: [line], facts: facts, candidate: ollama, provider: make(.reply(nice)))
        CT.check("a good sentence replaces the template", got, nice)
        CT.check("exactly one request, to the local fake", [local.all.count, remote.all.count], [1, 0])
        let sent = local.all[0]
        CT.check("it is one user message with one text part", sent.messages.count == 1 && sent.messages[0].parts.count == 1, true)
        CT.checkTrue("the text is the prompt: the template's line and nothing of the work", { if case .text(let t) = sent.messages[0].parts[0] { return t == p } else { return false } }())
        CT.check("no tools, no web search, no response format", sent.tools.isEmpty && !sent.webSearch && sent.responseFormat == nil, true)
        CT.check("a network candidate is never asked", await SidekickVoiceLocal.nicerLine(lines: [line], facts: facts, candidate: lan, provider: make(.reply(nice))), nil)
        CT.check("nor a cloud one", await SidekickVoiceLocal.nicerLine(lines: [line], facts: facts, candidate: cloud, provider: make(.reply(nice))), nil)
        CT.check("and neither received a request", remote.all.count, 0)
        CT.check("a provider that says it is not local is not used", await SidekickVoiceLocal.nicerLine(lines: [line], facts: facts, candidate: ollama, provider: { t in FakeProvider(id: t.provider, placement: .cloud, recorder: remote, mode: .reply(nice)) }), nil)
        CT.check("it did not even stream", remote.all.count, 0)
        CT.check("no candidate: the template stands", await SidekickVoiceLocal.nicerLine(lines: [line], facts: facts, candidate: nil, provider: make(.reply(nice))), nil)
        CT.check("a sentence with a made-up number is refused", await SidekickVoiceLocal.nicerLine(lines: [line], facts: facts, candidate: ollama, provider: make(.reply("Claude Code finished 13 steps."))), nil)
        CT.check("a sentence with a path is refused", await SidekickVoiceLocal.nicerLine(lines: [line], facts: facts, candidate: ollama, provider: make(.reply("Claude Code edited src/a.js."))), nil)
        CT.check("an error leaves the template", await SidekickVoiceLocal.nicerLine(lines: [line], facts: facts, candidate: ollama, provider: make(.fail)), nil)
        let t0 = Date()
        CT.check("a model that never answers leaves the template after the timeout", await SidekickVoiceLocal.nicerLine(lines: [line], facts: facts, candidate: ollama, provider: make(.hang), timeoutMs: 150), nil)
        CT.checkTrue("and does not wait longer than that", Date().timeIntervalSince(t0) < 2)
        CT.check("a reasoning block is not part of the sentence", await SidekickVoiceLocal.nicerLine(lines: [line], facts: facts, candidate: LocalCandidate(provider: .ollama, model: "qwen", placement: .local), provider: make(.reply("<think>12 steps? 99</think>" + nice))), nice)
        CT.finish()
    }
}
