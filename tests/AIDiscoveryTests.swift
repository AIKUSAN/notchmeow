import Foundation

@main
@MainActor
enum AIDiscoveryTests {
    static func main() async {
        AILog.sink.replace { _ in }
        rules()
        await personas()
        await nothingRunning()
        await twoPhase()
        await localRescan()
        T.finish()
    }

    static func target(_ p: AIProviderID, _ base: String = "http://127.0.0.1:1") -> ProbeTarget {
        ProbeTarget(serverID: p.rawValue, provider: p, name: AICatalog.info(p).name, baseURL: base)
    }

    static func rules() {
        T.section("Discovery.identify")
        func id(_ p: AIProviderID, _ native: Bool?, _ models: [String]?, installed: Bool = true) -> String {
            let r = Discovery.identify(target(p), nativeOK: native, models: models, installed: installed)
            let status: String = switch r.status {
            case .running(let m): "running \(m.map(\.id).joined(separator: ","))"
            case .off: "off"
            case .notInstalled: "not installed"
            case .outdated: "outdated"
            }
            return "\(r.provider.rawValue) \(r.name) \(status)"
        }
        T.check("Ollama", id(.ollama, true, ["qwen3.5:2b", "nomic-embed-text"]), "ollama Ollama running qwen3.5:2b")
        T.check("Ollama without /v1 is outdated", id(.ollama, true, nil), "ollama Ollama outdated")
        T.check("something else on 11434", id(.ollama, false, ["m"]), "custom Local server (OpenAI-compatible) running m")
        T.check("llama.cpp", id(.llamacpp, true, ["model.gguf"]), "llamacpp llama.cpp running model.gguf")
        T.check("LocalAI on 8080 (no /health)", id(.llamacpp, false, ["m"]), "custom Local server (OpenAI-compatible) running m")
        T.check("LM Studio", id(.lmstudio, nil, ["gemma-4-e2b"]), "lmstudio LM Studio running gemma-4-e2b")
        T.check("Jan", id(.jan, nil, ["llama3"]), "jan Jan running llama3")
        T.check("off but installed", id(.jan, nil, nil), "jan Jan off")
        T.check("not installed", id(.jan, nil, nil, installed: false), "jan Jan not installed")
        T.check("running with no models is not ready",
                Discovery.identify(target(.lmstudio), nativeOK: nil, models: [], installed: true).status, .running([]))
        let lan = DiscoveredServer(serverID: "custom-1", provider: .custom, name: "studio-pc", baseURL: "http://studio-pc.local:1234",
                                   placement: AICatalog.placement(forHost: "studio-pc.local"), status: .running([ModelInfo(id: "llama3")]))
        T.check("a LAN server is network", lan.placement, .network)
        T.check("its host for captions", lan.host, "studio-pc.local")
        var keyed = lan
        keyed.apiKey = "SECRET-LAN-KEY"
        let probe = ProbeTarget(serverID: "custom-1", provider: .custom, name: "studio-pc", baseURL: lan.baseURL,
                                apiKey: "SECRET-LAN-KEY")
        var dumped = ""
        dump(keyed, to: &dumped)
        dump(probe, to: &dumped)
        T.checkTrue("server keys never print", !"\(keyed) \(probe)".contains("SECRET") && !dumped.contains("SECRET"))
    }

    static func personas() async {
        T.section("Discovery.run against fake personas")
        let ollama = FakeServer(["--persona", "ollama"])
        let lmstudio = FakeServer(["--persona", "lmstudio"])
        let llamacpp = FakeServer(["--persona", "llamacpp"])
        let jan = FakeServer(["--persona", "jan"])
        let localAI = FakeServer()  // generic: /v1/models but no /health
        defer { [ollama, lmstudio, llamacpp, jan, localAI].forEach { $0.stop() } }
        let found = await Discovery.run([
            target(.ollama, ollama.base), target(.lmstudio, lmstudio.base), target(.llamacpp, llamacpp.base),
            target(.jan, jan.base), ProbeTarget(serverID: "llamacpp-2", provider: .llamacpp, name: "llama.cpp", baseURL: localAI.base),
        ], installed: { _ in true })
        T.check("names in order", found.map(\.name),
                ["Ollama", "LM Studio", "llama.cpp", "Jan", Discovery.unknownServerName])
        T.check("all ready", found.map(\.isReady), [true, true, true, true, true])
        T.check("embeddings filtered", found[0].models.map(\.id), ["llama3.2"])
        T.check("localhost is local", found[0].placement, .local)
    }

    static func nothingRunning() async {
        T.section("Discovery.run with nothing running")
        let targets = [AIProviderID.ollama, .lmstudio, .llamacpp, .jan].map { target($0, "http://127.0.0.1:\(closedPort())") }
        let start = Date()
        let found = await Discovery.run(targets, installed: { _ in false })
        let ms = Date().timeIntervalSince(start) * 1000
        T.check("everything reported missing", found.map(\.status), [.notInstalled, .notInstalled, .notInstalled, .notInstalled])
        T.checkTrue("finishes under 400 ms (took \(Int(ms)) ms)", ms < 400)
        T.check("the four defaults are on 127.0.0.1", ProbeTarget.defaults.map(\.baseURL),
                ["http://127.0.0.1:11434", "http://127.0.0.1:1234", "http://127.0.0.1:8080", "http://127.0.0.1:1337"])
    }

    /// A server the user added gets 2 s, so a sleepy LAN host isn't marked off; localhost keeps 0.3 s and its
    /// results don't wait for the added one.
    static func twoPhase() async {
        T.section("Discovery.run: localhost 0.3 s, added servers 2 s, in parallel")
        let local = FakeServer(["--persona", "ollama"])
        let lan = FakeServer(["--fail", "slow-models", "--delay", "1"])  // answers /v1/models after 1 s
        defer { local.stop(); lan.stop() }
        let targets = [target(.ollama, local.base),
                       ProbeTarget(serverID: "custom-1", provider: .custom, name: "lan", baseURL: lan.base)]
        let started = Date()
        let localDoneAt = Box<Double>(-1)
        let localIDs = Box<[String]>([])
        let found = await Discovery.run(targets, installed: { _ in true }, onLocal: { servers in
            localDoneAt.value = Date().timeIntervalSince(started)
            localIDs.value = servers.map { $0.serverID }
        })
        T.check("the local phase holds only localhost targets", localIDs.value, ["ollama"])
        let total = Date().timeIntervalSince(started)
        T.check("both ready, in order", found.map(\.isReady), [true, true])
        T.checkTrue("localhost reported before the slow server answered (\(Int(localDoneAt.value * 1000)) ms)",
                    localDoneAt.value >= 0 && localDoneAt.value < 0.9)
        T.checkTrue("the added server was waited for (\(Int(total * 1000)) ms)", total >= 1.0 && total < 2.0)
        // Without the second phase the same server is off: the 0.3 s probe is for localhost only.
        let quick = await Discovery.probe(targets[1], installed: true)
        T.check("0.3 s would have marked it off", quick.status, .off)
    }

    /// The one-time rescan when Auto needs a local model: localhost only, 0.3 s, and a server the user
    /// added keeps what the last full scan found.
    static func localRescan() async {
        T.section("Discovery.rescanLocal: asks only localhost")
        let local = FakeServer(["--persona", "ollama"])
        defer { local.stop() }
        let far = "http://192.0.2.1:1234"
        let known = DiscoveredServer(serverID: "custom-1", provider: .custom, name: "far", baseURL: far, placement: .network,
                                     status: .running([ModelInfo(id: "gemma")]))
        let started = Date()
        let after = await Discovery.rescanLocal(known: [known], targets: [
            target(.ollama, local.base), ProbeTarget(serverID: "custom-1", provider: .custom, name: "far", baseURL: far),
        ], installed: { _ in true })
        let ms = Date().timeIntervalSince(started) * 1000
        T.checkTrue("did not wait for the far server (\(Int(ms)) ms)", ms < 250)
        T.check("ollama found, the added server kept", Set(after.map { $0.serverID }), ["ollama", "custom-1"])
        T.check("the added server is still ready", after.first { $0.serverID == "custom-1" }?.isReady, true)
    }
}

final class Box<V>: @unchecked Sendable {
    var value: V
    init(_ v: V) { value = v }
}
