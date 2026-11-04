import Foundation

@main
@MainActor
enum AISettingsTests {
    static func main() async {
        migration()
        factory()
        await details()
        listFailures()
        await offlineKeyCheck()
        T.finish()
    }

    static func migration() {
        T.section("AISettingsMigration")
        var n = 0
        func id() -> String { n += 1; return "custom-\(n)" }
        T.check("nothing set: Auto everywhere", AISettingsMigration.migrate([:], makeID: id), .init())
        T.check("Anthropic (the old default) becomes Auto",
                AISettingsMigration.migrate(["chatProvider": "anthropic"], makeID: id).choices, [:])
        T.check("OpenAI stays chosen with its model",
                AISettingsMigration.migrate(["chatProvider": "openai", "openAIChatModel": "gpt-6-luna"], makeID: id).choices,
                ["chat": .explicit(ModelRef(provider: .openai, model: "gpt-6-luna"))])
        let ollama = AISettingsMigration.migrate(["chatProvider": "ollama", "ollamaServerURL": "http://127.0.0.1:11434/",
                                                  "ollamaChatModel": "qwen3.5:2b"], makeID: id)
        T.check("default Ollama URL needs no added server", ollama.customServers, [])
        T.check("Ollama stays chosen", ollama.choices, ["chat": .explicit(ModelRef(provider: .ollama, model: "qwen3.5:2b"))])
        T.check("its model is remembered", ollama.localModels, ["ollama": "qwen3.5:2b"])
        n = 0
        let lan = AISettingsMigration.migrate(["chatProvider": "lmstudio", "lmstudioServerURL": "http://studio-pc.local:1234/v1",
                                               "lmstudioChatModel": "gemma-4-e2b"], makeID: id)
        T.check("an LM Studio on another host becomes an added server",
                lan.customServers, [CustomServer(id: "custom-1", name: "LM Studio", baseURL: "http://studio-pc.local:1234")])
        T.check("and the chat points at it",
                lan.choices, ["chat": .explicit(ModelRef(provider: .custom, model: "gemma-4-e2b", serverID: "custom-1"))])
        // Pre-E1 stored a local or Google model only when it wasn't the default: no model means the default.
        T.check("Ollama without a stored model stays an explicit choice, with the old default",
                AISettingsMigration.migrate(["chatProvider": "ollama"], makeID: id).choices,
                ["chat": .explicit(ModelRef(provider: .ollama, model: "llama3.2"))])
        n = 0
        let lanDefault = AISettingsMigration.migrate(["chatProvider": "lmstudio", "lmstudioServerURL": "http://studio-pc.local:1234"],
                                                     makeID: id)
        T.check("LM Studio on another host without a model keeps its old default",
                lanDefault.choices, ["chat": .explicit(ModelRef(provider: .custom, model: "local-model", serverID: "custom-1"))])
        T.check("LM Studio on this Mac without a model keeps its old default",
                AISettingsMigration.migrate(["chatProvider": "lmstudio"], makeID: id).choices,
                ["chat": .explicit(ModelRef(provider: .lmstudio, model: "local-model"))])
        T.check("Google without a stored model keeps its old default",
                AISettingsMigration.migrate(["chatProvider": "google"], makeID: id).choices,
                ["chat": .explicit(ModelRef(provider: .google, model: "gemini-2.0-flash"))])

        T.section("CustomServer IDs and Keychain items")
        let ids = (0..<200).map { _ in CustomServer.newID() }
        T.checkTrue("generated IDs match ^[a-z0-9-]{1,32}$", ids.allSatisfy(CustomServer.isValidID))
        T.check("and are unique", Set(ids).count, 200)
        let migrated = AISettingsMigration.migrate(["chatProvider": "lmstudio", "lmstudioServerURL": "http://studio-pc.local:1234",
                                                    "lmstudioChatModel": "m"])
        T.check("the migration's own IDs are valid", migrated.customServers.map { CustomServer.isValidID($0.id) }, [true])
        T.check("valid IDs", ["a", "custom-1", String(repeating: "a", count: 32)].map(CustomServer.isValidID), [true, true, true])
        T.check("invalid IDs: empty, uppercase, colon, dot, slash, non-ASCII, 33 characters, space",
                ["", "Custom", "custom:1", "a.b", "a/../x", "é", String(repeating: "a", count: 33), "a b"].map(CustomServer.isValidID),
                Array(repeating: false, count: 8))
        T.check("a server's Keychain item", CustomServer(id: "custom-1", name: "n", baseURL: "u").keychainAccount,
                "custom-server-key.custom-1")
        T.check("two servers, two Keychain items",
                Set(["custom-1", "custom-2"].map { CustomServer(id: $0, name: "n", baseURL: "u").keychainAccount }).count, 2)
    }

    static func factory() {
        T.section("ProviderFactory")
        let f = ProviderFactory(keys: [.anthropic: "SECRET-A", .openai: "SECRET-O", .google: "SECRET-G"],
                                servers: ["custom-1": .init(baseURL: "http://studio-pc.local:1234", key: "SECRET-K")])
        T.checkTrue("Anthropic", f.make(ChatTarget(provider: .anthropic, model: "m", placement: .cloud)) is AnthropicProvider)
        T.checkTrue("OpenAI", f.make(ChatTarget(provider: .openai, model: "m", placement: .cloud)) is OpenAIProvider)
        let google = f.make(ChatTarget(provider: .google, model: "m", placement: .cloud)) as? OpenAICompatibleProvider
        T.check("Google path", google.map { $0.baseURL + $0.chatPath },
                "https://generativelanguage.googleapis.com/v1beta/openai/chat/completions")
        let custom = f.make(ChatTarget(provider: .custom, model: "m", placement: .network, serverID: "custom-1",
                                       host: "studio-pc.local")) as? OpenAICompatibleProvider
        T.check("added server URL", custom?.baseURL, "http://studio-pc.local:1234")
        T.check("added server key", custom?.apiKey, "SECRET-K")
        T.check("added server is network", custom?.placement, .network)
        let ollama = f.make(ChatTarget(provider: .ollama, model: "m", placement: .local)) as? OpenAICompatibleProvider
        T.check("default Ollama URL", ollama?.baseURL, "http://127.0.0.1:11434")
        T.check("no Apple model → unavailable", f.make(ChatTarget(provider: .apple, model: "system", placement: .local)).id, .apple)

        var debug = f
        debug.cloudOverride = "http://127.0.0.1:9"
        let redirected = debug.make(ChatTarget(provider: .google, model: "m", placement: .cloud)) as? OpenAICompatibleProvider
        T.check("override keeps /v1 paths for Google", redirected.map { $0.baseURL + $0.chatPath },
                "http://127.0.0.1:9/v1/chat/completions")
        var dumped = ""
        dump(f, to: &dumped)
        T.checkTrue("factory keys never print", !"\(f)".contains("SECRET") && !dumped.contains("SECRET")
                    && !String(reflecting: f.servers["custom-1"]!).contains("SECRET"))
        T.check("override moves Anthropic", (debug.make(ChatTarget(provider: .anthropic, model: "m", placement: .cloud))
                                              as? AnthropicProvider)?.baseURL, "http://127.0.0.1:9")
    }

    static func details() async {
        T.section("ProviderFactory.details")
        let f = ProviderFactory(appleContextTokens: 8192)
        T.check("cloud reads images", await f.details(ChatTarget(provider: .anthropic, model: "m", placement: .cloud)).vision, true)
        T.check("Apple context", await f.details(ChatTarget(provider: .apple, model: "system", placement: .local)).contextTokens, 8192)
        let nobody = ChatTarget(provider: .ollama, model: "m", placement: .local)
        var local = f
        local.servers = ["ollama": .init(baseURL: "http://127.0.0.1:\(closedPort())", key: nil)]
        T.check("unknown local model is text-only", await local.details(nobody).vision, false)
    }

    static func listFailures() {
        T.section("AIMessages.listFailure: offline never says the key was refused")
        let offlineLine = "Couldn't reach Claude. Check your connection."
        func line(_ e: AIError?, online: Bool = true) -> (String, Bool) {
            let f = AIMessages.listFailure(e, provider: .anthropic, online: online)
            return (f.text, f.rejected)
        }
        T.check("a 401 is a rejected key", line(AIError(kind: .auth)).1, true)
        T.check("an empty list is a rejected key, as before", line(nil).1, true)
        T.check("unreachable says so, no rejected mark", line(AIError(kind: .unreachable)) == (offlineLine, false), true)
        T.check("offline says the same line", line(AIError(kind: .offline)) == (offlineLine, false), true)
        T.check("the network monitor offline wins over any failure", line(AIError(kind: .auth), online: false) == (offlineLine, false), true)
        T.check("a busy server is not a rejected key", line(AIError(kind: .overloaded)).1, false)
        // Google answers a bad key with HTTP 400 "API key not valid": in the key check (only) that is a refused key.
        T.check("a 400 on the model list is a rejected key", line(AIError(kind: .badRequest, status: 400)) == ("Anthropic didn't accept this key.", true), true)
        T.check("a 404 on the model list is not", line(AIError(kind: .badRequest, status: 404)).1, false)
        T.check("a 400 while offline still says offline", line(AIError(kind: .badRequest, status: 400), online: false) == (offlineLine, false), true)
    }

    /// The real call with a port nobody listens on: the failure kind comes out of `listModels`.
    static func offlineKeyCheck() async {
        T.section("ProviderFactory: a model list that can't connect throws unreachable")
        var f = ProviderFactory(cloudOverride: "http://127.0.0.1:\(closedPort())")
        f.keys[.anthropic] = "test-key"
        var kind: AIErrorKind?
        do { _ = try await f.make(ChatTarget(provider: .anthropic, model: "", placement: .cloud)).listModels() }
        catch { kind = (error as? AIError)?.kind }
        T.check("refused connection is unreachable, not auth", kind, .unreachable)
    }
}
