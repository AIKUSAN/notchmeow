import Foundation

/// A server to check: one of the four known local servers, or one the user added.
struct ProbeTarget: Sendable, Equatable {
    /// "ollama", "lmstudio", "llamacpp", "jan", or "custom-<24 hex digits>" (`CustomServer.newID()`).
    let serverID: String
    let provider: AIProviderID
    /// Display name (for custom servers, what the user typed or the host).
    let name: String
    let baseURL: String
    var apiKey: String? = nil

    /// The four servers checked automatically, on 127.0.0.1 only.
    static let defaults: [ProbeTarget] = [AIProviderID.ollama, .lmstudio, .llamacpp, .jan].map {
        let info = AICatalog.info($0)
        return ProbeTarget(serverID: $0.rawValue, provider: $0, name: info.name, baseURL: info.baseURL!)
    }
}

enum ServerStatus: Sendable, Equatable {
    case running([ModelInfo])
    case off
    case notInstalled
    /// Its own API answers but the OpenAI-compatible one doesn't (too old).
    case outdated
}

struct DiscoveredServer: Sendable, Equatable {
    let serverID: String
    /// `.custom` when an unexpected server answers on a known port.
    var provider: AIProviderID
    var name: String
    let baseURL: String
    var placement: AIPlacement
    var status: ServerStatus
    var apiKey: String? = nil

    var models: [ModelInfo] { if case .running(let m) = status { m } else { [] } }
    var isReady: Bool { !models.isEmpty }
    var host: String? { URL(string: baseURL)?.host }
}

enum Discovery {
    static let unknownServerName = "Local server (OpenAI-compatible)"

    /// Identification from what answered (pure, so every rule has a test).
    /// - nativeOK: the server's own check answered (`/api/version` with a version, `/health`); nil when it has none.
    /// - models: `/v1/models` IDs, nil when that call failed.
    static func identify(_ t: ProbeTarget, nativeOK: Bool?, models: [String]?,
                         installed: Bool) -> (provider: AIProviderID, name: String, status: ServerStatus) {
        let silent: ServerStatus = installed || t.provider == .custom ? .off : .notInstalled
        switch (t.provider, nativeOK, models) {
        case (.ollama, true?, nil):
            return (.ollama, t.name, .outdated)
        case (.ollama, true?, let ids?), (.llamacpp, true?, let ids?):
            return (t.provider, t.name, .running(chatModels(ids, t.provider)))
        case (.ollama, _, let ids?), (.llamacpp, _, let ids?):
            // LocalAI on 8080, or something else on 11434.
            return (.custom, unknownServerName, .running(chatModels(ids, .custom)))
        case (_, _, let ids?):
            return (t.provider, t.name, .running(chatModels(ids, t.provider)))
        default:
            return (t.provider, t.name, silent)
        }
    }

    private static func chatModels(_ ids: [String], _ provider: AIProviderID) -> [ModelInfo] {
        AICatalog.filterModels(ids, for: provider).map { ModelInfo(id: $0) }
    }

    /// All targets in parallel, in two phases that start together: localhost at 0.3 s, and the servers the
    /// user added at 2 s, so a sleepy LAN host isn't marked off. `onLocal` gets the localhost results as soon
    /// as that phase ends, without waiting for the added servers. Results keep the targets' order.
    static func run(_ targets: [ProbeTarget], installed: @escaping @Sendable (AIProviderID) -> Bool = isInstalled,
                    session: URLSession = probeSession,
                    onLocal: (@Sendable ([DiscoveredServer]) async -> Void)? = nil) async -> [DiscoveredServer] {
        let started = Date()
        let indexed = Array(targets.enumerated())
        let added = indexed.filter { $0.element.provider == .custom }
        async let addedFound = scan(added, timeout: AICatalog.Timeouts.probeAdded, installed: installed, session: session)
        let localFound = await scan(indexed.filter { $0.element.provider != .custom },
                                    timeout: AICatalog.Timeouts.probe, installed: installed, session: session)
        await onLocal?(localFound.map(\.1))
        let found = (localFound + (await addedFound)).sorted { $0.0 < $1.0 }.map(\.1)
        AILog.record(.discovery(found: found.filter(\.isReady).map(\.provider), ms: Int(Date().timeIntervalSince(started) * 1000)))
        return found
    }

    private static func scan(_ targets: [(offset: Int, element: ProbeTarget)], timeout: TimeInterval,
                             installed: @escaping @Sendable (AIProviderID) -> Bool,
                             session: URLSession) async -> [(Int, DiscoveredServer)] {
        await withTaskGroup(of: (Int, DiscoveredServer).self) { group in
            for (i, t) in targets {
                group.addTask { (i, await probe(t, installed: installed(t.provider), timeout: timeout, session: session)) }
            }
            var out: [(Int, DiscoveredServer)] = []
            for await r in group { out.append(r) }
            return out
        }
    }

    /// The one rescan when Auto needs a local model: this computer only, 0.3 s. A server the user added on
    /// another network keeps what the last full scan found, so a slow link can't flip it to "off" here.
    static func rescanLocal(known: [DiscoveredServer], targets: [ProbeTarget],
                            installed: @escaping @Sendable (AIProviderID) -> Bool = isInstalled,
                            session: URLSession = probeSession) async -> [DiscoveredServer] {
        let here = targets.filter { AICatalog.placement(forHost: URL(string: $0.baseURL)?.host) == .local }
        var out = known
        for found in await scan(Array(here.enumerated()), timeout: AICatalog.Timeouts.probe, installed: installed,
                                session: session).sorted(by: { $0.0 < $1.0 }).map(\.1) {
            if let i = out.firstIndex(where: { $0.serverID == found.serverID }) { out[i] = found } else { out.append(found) }
        }
        return out
    }

    /// One server. `timeout` is 0.3 s for discovery; Add server… allows a sleepy LAN host 5 s.
    static func probe(_ t: ProbeTarget, installed: Bool, timeout: TimeInterval = AICatalog.Timeouts.probe,
                      session: URLSession = probeSession) async -> DiscoveredServer {
        let nativePath: String? = t.provider == .ollama ? "/api/version" : (t.provider == .llamacpp ? "/health" : nil)
        async let native: Bool? = nativePath == nil ? nil : nativeAnswers(t, path: nativePath!, timeout: timeout, session: session)
        async let models = modelIDs(t, timeout: timeout, session: session)
        let (provider, name, status) = identify(t, nativeOK: await native, models: await models, installed: installed)
        return DiscoveredServer(serverID: t.serverID, provider: provider, name: name, baseURL: t.baseURL,
                                placement: AICatalog.placement(forHost: URL(string: t.baseURL)?.host),
                                status: status, apiKey: t.apiKey)
    }

    static let probeSession: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = AICatalog.Timeouts.probe
        config.timeoutIntervalForResource = AICatalog.Timeouts.connectLocal  // each request carries its own limit
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    private static func request(_ t: ProbeTarget, _ path: String, timeout: TimeInterval) -> URLRequest? {
        guard let url = URL(string: t.baseURL + path) else { return nil }
        var req = URLRequest(url: url, timeoutInterval: timeout)
        if let key = t.apiKey { req.setValue("Bearer \(key)", forHTTPHeaderField: "Authorization") }
        return req
    }

    private static func nativeAnswers(_ t: ProbeTarget, path: String, timeout: TimeInterval,
                                      session: URLSession) async -> Bool {
        guard let req = request(t, path, timeout: timeout),
              let json = try? await HTTPStream.json(req, session: session) as? [String: Any] else { return false }
        return path == "/api/version" ? json["version"] != nil : true
    }

    private static func modelIDs(_ t: ProbeTarget, timeout: TimeInterval, session: URLSession) async -> [String]? {
        guard let req = request(t, "/v1/models", timeout: timeout),
              let json = try? await HTTPStream.json(req, session: session) as? [String: Any],
              let rows = json["data"] as? [[String: Any]] else { return nil }
        return rows.compactMap { $0["id"] as? String }
    }

    /// Where each server's app or binary usually lives ("○ Not installed" vs "○ Server off").
    static let installPaths: [AIProviderID: [String]] = [
        .ollama: ["/Applications/Ollama.app", "~/Applications/Ollama.app", "/opt/homebrew/bin/ollama", "/usr/local/bin/ollama"],
        .lmstudio: ["/Applications/LM Studio.app", "~/Applications/LM Studio.app", "~/.lmstudio/bin/lms"],
        .llamacpp: ["/opt/homebrew/bin/llama-server", "/usr/local/bin/llama-server"],
        .jan: ["/Applications/Jan.app", "~/Applications/Jan.app"],
    ]

    @Sendable static func isInstalled(_ provider: AIProviderID) -> Bool {
        (installPaths[provider] ?? []).contains {
            FileManager.default.fileExists(atPath: NSString(string: $0).expandingTildeInPath)
        }
    }
}

extension ProbeTarget: RedactsSecrets {
    var redactedSummary: String { "ProbeTarget(\(serverID), \(baseURL), key: \(Self.keyMark(apiKey)))" }
}

extension DiscoveredServer: RedactsSecrets {
    var redactedSummary: String {
        "DiscoveredServer(\(serverID), \(name), \(baseURL), \(placement.rawValue), ready: \(isReady), key: \(Self.keyMark(apiKey)))"
    }
}
