import Foundation

// The AI rows of Settings → AI and chat → Your AI and Keys and Local models: which rows show, their words, their chips, what Make main does, and which row is main.
// Plain values, no Keychain, no UserDefaults, no server. Run through scripts/test-settings-ai.sh.

@main
enum SettingsAITests {
    static func S(_ id: String, _ p: AIProviderID, _ name: String, _ network: Bool, _ models: [String]) -> SettingsAI.Server {
        SettingsAI.Server(id: id, provider: p, name: name, network: network, models: models)
    }

    static let base = SettingsAI.Input(
        githubBuild: true, claudeState: .signedIn, claudeVersion: "2.1.289", claudeSignIn: "your Claude plan",
        claudeEnabled: true, claudeModel: "sonnet", keys: [.anthropic],
        cloudModel: [.anthropic: "claude-sonnet-5-5", .openai: "gpt-6.1-sol"],
        servers: [S("ollama", .ollama, "Ollama", false, ["qwen3.5:2b", "llama4"]), S("custom-ab12", .custom, "Studio PC", true, ["big"])],
        memory: ["ollama": "llama4"], appleReady: true)

    @MainActor static func main() {
        let I = base

        CT.section("rows: the plan rows on GitHub builds only, then keys, servers with models, Apple")
        CT.check("rows", SettingsAI.rows(I), [.claudePlan, .openAIPlan, .key(.anthropic), .key(.google), .key(.openai), .server("ollama"), .server("custom-ab12"), .apple])
        var store = I
        store.githubBuild = false
        CT.check("App Store: no plan rows", SettingsAI.rows(store).first, .key(.anthropic))
        CT.checkTrue("no Google plan row (owner's answer 5)", !SettingsAI.rows(I).map { SettingsAI.title($0, I) }.contains { $0.contains("Google plan") })
        var noModels = I
        noModels.servers.append(S("empty", .lmstudio, "Empty", false, []))
        CT.checkTrue("a server with no models has no row", !SettingsAI.rows(noModels).contains(.server("empty")))
        var noApple = I
        noApple.appleReady = false
        CT.checkTrue("no Apple row when it is not ready", !SettingsAI.rows(noApple).contains(.apple))

        CT.section("titles and one-liners")
        CT.check("titles", [SettingsAI.title(.claudePlan, I), SettingsAI.title(.openAIPlan, I), SettingsAI.title(.key(.google), I)], ["Use my Claude plan", "Use my OpenAI plan", "Google AI API key"])
        CT.check("title of a key row", [SettingsAI.title(.key(.anthropic), I), SettingsAI.title(.key(.openai), I)], ["Anthropic API key", "OpenAI API key"])
        CT.check("server title", SettingsAI.title(.server("custom-ab12"), I), "Studio PC")
        CT.check("apple title", SettingsAI.title(.apple, I), "Apple on-device")
        CT.check("plan line", SettingsAI.line(.openAIPlan, I), "Runs your own installed app, signed in by you. NotchMeow never sees your login.")
        CT.check("key line", SettingsAI.line(.key(.anthropic), I), "Your own key, saved on the Keys tab.")
        CT.check("local line", SettingsAI.line(.server("ollama"), I), "A model server on this Mac.")
        CT.check("network line", SettingsAI.line(.server("custom-ab12"), I), "A model server on your network.")
        CT.check("apple line", SettingsAI.line(.apple, I), "Apple's model, on this Mac.")

        CT.section("chips")
        CT.check("chips", [.claudePlan, .openAIPlan, .key(.anthropic), .key(.openai), .server("ollama"), .apple].map { SettingsAI.chip($0, I) },
                 ["Ready", "Not installed", "Ready", "No key yet", "Running, 2 models", "Ready"])
        var off = I
        off.claudeEnabled = false
        CT.check("Claude off", SettingsAI.chip(.claudePlan, off), "Off")
        for (st, word) in [(SettingsAI.ClaudeState.signedOut, "Not signed in"), (.notInstalled, "Not installed"), (.tooOld, "Needs update"), (.unknown, "Not ready")] {
            var x = I
            x.claudeState = st
            CT.check("Claude \(word)", SettingsAI.chip(.claudePlan, x), word)
        }
        CT.check("server chips", [SettingsAI.serverChip(.running([])), SettingsAI.serverChip(.running([ModelInfo(id: "a")])), SettingsAI.serverChip(.running([ModelInfo(id: "a"), ModelInfo(id: "b"), ModelInfo(id: "c")])),
                                  SettingsAI.serverChip(.off), SettingsAI.serverChip(.notInstalled), SettingsAI.serverChip(.outdated)],
                 ["Running, no models yet", "Running, 1 model", "Running, 3 models", "Server off", "Not installed", "Update needed"])

        CT.section("Make main")
        CT.check("Make main Claude", SettingsAI.makeMain(.claudePlan, I), .set(.explicit(ModelRef(provider: .claudeCode, model: "sonnet"))))
        CT.check("Make main Claude off", SettingsAI.makeMain(.claudePlan, off), .unavailable("Connect your Claude plan first."))
        CT.check("Make main OpenAI plan, not installed", SettingsAI.makeMain(.openAIPlan, I), .unavailable("Install OpenAI's Codex CLI first."))
        CT.check("Make main key", SettingsAI.makeMain(.key(.anthropic), I), .set(.explicit(ModelRef(provider: .anthropic, model: "claude-sonnet-5-5"))))
        CT.check("Make main no key", SettingsAI.makeMain(.key(.openai), I), .unavailable("Add a key on the Keys tab first."))
        var g = I
        g.keys = [.google]
        CT.check("Make main key without a model", SettingsAI.makeMain(.key(.google), g), .unavailable("Pick a model for it in the chat first."))
        CT.check("Make main server menu, remembered first", SettingsAI.makeMain(.server("ollama"), I),
                 .menu([ModelRef(provider: .ollama, model: "llama4", serverID: "ollama"), ModelRef(provider: .ollama, model: "qwen3.5:2b", serverID: "ollama")]))
        CT.check("Make main one model", SettingsAI.makeMain(.server("custom-ab12"), I), .set(.explicit(ModelRef(provider: .custom, model: "big", serverID: "custom-ab12"))))
        CT.check("Make main Apple", SettingsAI.makeMain(.apple, I), .set(.explicit(ModelRef(provider: .apple, model: "system"))))
        var noMemory = I
        noMemory.memory = [:]
        CT.check("Make main server menu, stored order without memory", SettingsAI.makeMain(.server("ollama"), noMemory),
                 .menu([ModelRef(provider: .ollama, model: "qwen3.5:2b", serverID: "ollama"), ModelRef(provider: .ollama, model: "llama4", serverID: "ollama")]))

        CT.section("which row is main: only an explicit Chat choice")
        CT.checkTrue("Auto: nothing is main", SettingsAI.rows(I).allSatisfy { !SettingsAI.isMain($0, chat: .auto) })
        let ollama = FeatureSetting.explicit(ModelRef(provider: .ollama, model: "qwen3.5:2b"))
        CT.check("main follows the choice", SettingsAI.rows(I).filter { SettingsAI.isMain($0, chat: ollama) }, [.server("ollama")])
        CT.check("any Anthropic model is the Anthropic row", SettingsAI.rows(I).filter { SettingsAI.isMain($0, chat: .explicit(ModelRef(provider: .anthropic, model: "claude-opus-5-5"))) }, [.key(.anthropic)])
        CT.check("Claude plan main", SettingsAI.rows(I).filter { SettingsAI.isMain($0, chat: .explicit(ModelRef(provider: .claudeCode, model: "sonnet"))) }, [.claudePlan])
        CT.check("Apple main", SettingsAI.rows(I).filter { SettingsAI.isMain($0, chat: .explicit(ModelRef(provider: .apple, model: "system"))) }, [.apple])
        CT.check("a cloud model is the key's row, never a server's", SettingsAI.rows(I).filter { SettingsAI.isMain($0, chat: .explicit(ModelRef(provider: .openai, model: "gpt-6.1-sol", serverID: "ollama"))) }, [.key(.openai)])

        CT.section("getLink: today's links")
        CT.check("get link", [SettingsAI.getLink(.ollama), SettingsAI.getLink(.anthropic)], ["https://ollama.com/download", nil])
        CT.check("get links of the local servers", [SettingsAI.getLink(.lmstudio), SettingsAI.getLink(.jan), SettingsAI.getLink(.llamacpp)],
                 ["https://lmstudio.ai", "https://jan.ai", "https://github.com/ggml-org/llama.cpp"])

        CT.section("fix round 1: a server with no models, the help lines and the reasons")
        var empty = I
        empty.servers.append(S("empty", .lmstudio, "Empty", false, []))
        CT.check("Make main on a server with no models says to start it", SettingsAI.makeMain(.server("empty"), empty), .unavailable("Start the server and load a model first."))
        CT.check("the help line of a saved key is its line", SettingsAI.helpLine(.key(.anthropic), I), "Your own key, saved on the Keys tab.")
        CT.check("a key row with no key has no help line (its chip and button say it)", SettingsAI.helpLine(.key(.openai), I), nil)
        CT.check("the OpenAI plan keeps its one-liner (owner)", SettingsAI.helpLine(.openAIPlan, I), SettingsAI.planLine)
        CT.check("the OpenAI plan says what to do when it is not installed", SettingsAI.reasonLine(.openAIPlan, I), "Install OpenAI's Codex CLI first.")
        CT.check("a key with no key says it on its button, so no reason", SettingsAI.reasonLine(.key(.openai), I), nil)
        CT.check("a key with no model keeps its reason", SettingsAI.reasonLine(.key(.google), g), "Pick a model for it in the chat first.")
        CT.check("a Claude plan that is off keeps its reason", SettingsAI.reasonLine(.claudePlan, off), "Connect your Claude plan first.")
        CT.check("a row that can be made main has no reason", SettingsAI.reasonLine(.apple, I), nil)

        CT.section("the OpenAI plan's states")
        var oa = I
        CT.check("the sign-in words", SettingsAI.codexSignIn, "Open your terminal and run `codex login`. NotchMeow opens nothing.")
        CT.check("the coming words: the chip has none, the reason has a full stop", [SettingsAI.coming, SettingsAI.comingReason], ["Coming with the new chat", "Coming with the new chat."])
        oa.codexState = .signedIn
        CT.check("signed in: the chip says Ready", SettingsAI.chip(.openAIPlan, oa), "Ready")
        CT.check("signed in: Make main sets the OpenAI plan", SettingsAI.makeMain(.openAIPlan, oa), .set(.explicit(ModelRef(provider: .codexPlan, model: ""))))
        CT.check("signed in: no reason", SettingsAI.reasonLine(.openAIPlan, oa), nil)
        oa.codexState = .signedOut
        CT.check("signed out: the chip says Not signed in", SettingsAI.chip(.openAIPlan, oa), "Not signed in")
        CT.check("signed out: Make main says how to sign in", SettingsAI.makeMain(.openAIPlan, oa), .unavailable(SettingsAI.codexSignIn))
        CT.check("signed out: the reason is the sign-in line", SettingsAI.reasonLine(.openAIPlan, oa), SettingsAI.codexSignIn)
        oa.codexState = .notInstalled
        CT.check("not installed: the chip says Not installed", SettingsAI.chip(.openAIPlan, oa), "Not installed")
        CT.check("not installed: Make main says to install", SettingsAI.makeMain(.openAIPlan, oa), .unavailable("Install OpenAI's Codex CLI first."))
        oa.codexState = .tooOld
        CT.check("too old: the chip says Needs update", SettingsAI.chip(.openAIPlan, oa), "Needs update")
        CT.check("too old: Make main says to update", SettingsAI.makeMain(.openAIPlan, oa), .unavailable("This version of Codex is too old for NotchMeow."))
        oa.codexState = .unknown
        CT.check("unknown: the chip says Not ready", SettingsAI.chip(.openAIPlan, oa), "Not ready")
        CT.check("unknown: Make main says to open the tab again", SettingsAI.makeMain(.openAIPlan, oa), .unavailable("Codex didn't answer. Open this tab again to check."))
        CT.check("the OpenAI plan's one-liner is unchanged", SettingsAI.helpLine(.openAIPlan, oa), SettingsAI.planLine)
        oa.codexState = .signedIn
        CT.check("the OpenAI plan row is main for its choice, and only it", SettingsAI.rows(oa).filter { SettingsAI.isMain($0, chat: .explicit(ModelRef(provider: .codexPlan, model: ""))) }, [.openAIPlan])
        CT.checkTrue("the OpenAI plan row is not main on Auto", !SettingsAI.isMain(.openAIPlan, chat: .auto))

        CT.section("Stop using Claude: a choice that named the plan goes back to Auto")
        let claudeChoice = FeatureSetting.explicit(ModelRef(provider: .claudeCode, model: "sonnet"))
        CT.check("the plan's choice goes back to Auto", SettingsAI.afterStoppingClaude(claudeChoice), .auto)
        CT.check("Auto stays Auto", SettingsAI.afterStoppingClaude(.auto), .auto)
        let keyChoice = FeatureSetting.explicit(ModelRef(provider: .anthropic, model: "claude-sonnet-5-5"))
        CT.check("an API key choice is unchanged", SettingsAI.afterStoppingClaude(keyChoice), keyChoice)
        let serverChoice = FeatureSetting.explicit(ModelRef(provider: .custom, model: "big", serverID: "custom-ab12"))
        CT.check("a server choice is unchanged", SettingsAI.afterStoppingClaude(serverChoice), serverChoice)
        let appleChoice = FeatureSetting.explicit(ModelRef(provider: .apple, model: "system"))
        CT.check("the Apple choice is unchanged", SettingsAI.afterStoppingClaude(appleChoice), appleChoice)
        CT.checkTrue("after Stop, the Claude plan row is not main (never Off and Main together)", !SettingsAI.isMain(.claudePlan, chat: SettingsAI.afterStoppingClaude(claudeChoice)))

        CT.finish()
    }
}
