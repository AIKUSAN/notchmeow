import Foundation

// The Settings control map (the restyle spec's "Control map"): every control, the page, tab and card it lives on now, and the stored keys it reads and writes. No stored key is lost or
// renamed; the test pins this table against today's keys and against tests/fixtures/settings/controls.json (the Windows plan's starting file). Pure Foundation.
// Tests: tests/SettingsMapTests.swift (scripts/test-settings-map.sh).

enum SettingsMap {
    /// A place on a page: the tab (nil on a page without tabs, or where the shell itself is named) and the card's title.
    struct Home: Equatable, Sendable { var page: SettingsRoute.Page; var tab: SettingsRoute.Tab?; var card: String }
    /// A stored key and where it lives: store is `defaults` (UserDefaults), `keychain` or `file`.
    struct StoredKey: Equatable, Sendable { var key: String; var store: String }
    /// One control: its id, the spec's first-column wording (`was`), its homes (several when the same state shows in several places) and its stored keys.
    struct Control: Equatable, Sendable { var id: String; var was: String; var homes: [Home]; var mac: [StoredKey] }

    private static func h(_ page: SettingsRoute.Page, _ tab: SettingsRoute.Tab?, _ card: String) -> Home {
        Home(page: page, tab: tab, card: card)
    }
    private static func d(_ key: String) -> StoredKey { StoredKey(key: key, store: "defaults") }
    private static func k(_ key: String) -> StoredKey { StoredKey(key: key, store: "keychain") }
    private static func f(_ key: String) -> StoredKey { StoredKey(key: key, store: "file") }

    static let controls: [Control] = [
        Control(id: "sound.enabled", was: "General: Enable sounds", homes: [h(.general, .general, "Sound")], mac: [d("soundEnabled")]),
        Control(id: "sound.volume", was: "General: Volume", homes: [h(.general, .general, "Sound")], mac: [d("soundVolume")]),
        Control(id: "island.openOnHover", was: "General: Open on hover", homes: [h(.general, .general, "Island")], mac: [d("openOnHover")]),
        Control(id: "island.focusAware", was: "(new) Focus awareness: Step back when I'm already in the app", homes: [h(.general, .general, "Island")], mac: [d("island.focusAware")]),
        Control(id: "island.hoverGlow", was: "General: Hover glow", homes: [h(.general, .general, "Island")], mac: [d("island.hoverGlow")]),
        Control(id: "island.tuckAway", was: "General: Tuck the island away", homes: [h(.general, .general, "Island")], mac: [d("island.tuckAway")]),
        Control(id: "island.closeAfter", was: "General: Close after N s inactive", homes: [h(.general, .general, "Island")], mac: [d("autoCloseInterval")]),
        Control(id: "startup.launch", was: "General: Launch at Mac startup", homes: [h(.general, .general, "Startup")], mac: []),
        Control(id: "pills.main", was: "Active pills: Main", homes: [h(.general, .general, "On the island")], mac: [d("mainPill")]),
        Control(id: "pills.slots", was: "Active pills: N/4 slots used", homes: [h(.general, .general, "On the island")], mac: []),
        Control(id: "pills.switches",
                was: "Active pills: Claude Code, Cursor, Antigravity, Codex; Active pills: Gemini CLI; Active pills: Anthropic, Google AI, OpenAI; Active pills: Ollama, LM Studio; Active pills: Resend, n8n, Vercel, GitHub, Notion, Cal.com, Stripe, Apple Music",
                homes: [h(.agents, nil, "On the island"), h(.chat, .keys, "Anthropic, Google AI, OpenAI"), h(.chat, .localModels, "Local models"),
                        h(.services, nil, "Resend, n8n, Vercel, GitHub, Stripe, Cal.com, Notion, Music")],
                mac: [d("activeIntegrations")]),
        Control(id: "hooks.claude",
                was: "Agents: Claude Code hooks (Install, Uninstall, Update, Confirm); Agents: Claude Code hooks, App Store install state",
                homes: [h(.agents, nil, "Claude Code hooks")],
                mac: [f("~/.claude/notchmeow/nm-hook"), f("~/.claude/settings.json"), d("notchmeowHooksInstalled")]),
        Control(id: "hooks.gemini", was: "Agents: Gemini CLI, Antigravity, Codex hooks", homes: [h(.agents, nil, "Gemini CLI hooks")], mac: [f("~/.gemini/settings.json")]),
        Control(id: "hooks.antigravity", was: "Agents: Gemini CLI, Antigravity, Codex hooks", homes: [h(.agents, nil, "Antigravity hooks")], mac: [f("~/.gemini/config/hooks.json")]),
        Control(id: "hooks.codex", was: "Agents: Gemini CLI, Antigravity, Codex hooks", homes: [h(.agents, nil, "Codex hooks")], mac: [f("~/.codex/hooks.json")]),
        Control(id: "plan.usage", was: "Agents: Plan usage, Show in the notch, relay", homes: [h(.agents, nil, "Plan usage")],
                mac: [d("showPlanInNotch"), d("claudePlanUsage"), f("~/.claude/settings.json")]),
        Control(id: "ai.claudePlan", was: "AI: Connect Claude (Use my Claude plan, Stop using it, Check again)", homes: [h(.chat, .yourAI, "Choose your AI")],
                mac: [d("aiClaudeCodeEnabled"), d("aiClaudeCodeModel")]),
        Control(id: "ai.openAIPlan", was: "(new) ChatGPT plan, Gemini rows, Make main", homes: [h(.chat, .yourAI, "Choose your AI")], mac: []),
        Control(id: "ai.routing", was: "AI: Which model answers: Chat, File questions; AI: Preferred cloud",
                homes: [h(.chat, .yourAI, "Which one answers"), h(.chat, .yourAI, "Choose your AI")], mac: [d("aiChoices"), d("aiPreferredCloud")]),
        Control(id: "ai.key.anthropic", was: "AI: Paste an API key (Anthropic); AI: Anthropic API key, Save; AI: Anthropic Model, Custom",
                homes: [h(.chat, .keys, "Anthropic")], mac: [k("anthropic-api-key"), d("claudeModel")]),
        Control(id: "ai.key.google", was: "AI: Google AI key", homes: [h(.chat, .keys, "Google AI")], mac: [k("google-api-key"), d("googleChatModel")]),
        Control(id: "ai.key.openai", was: "AI: OpenAI key", homes: [h(.chat, .keys, "OpenAI")], mac: [k("openai-api-key"), d("openAIChatModel")]),
        Control(id: "ai.local", was: "AI: Local models list, Rescan, Add server", homes: [h(.chat, .localModels, "Local models")],
                mac: [d("aiCustomServers"), k("custom-server-key.<id>"), d("aiLastUsedLocal"), d("aiLocalModels")]),
        Control(id: "ai.apple", was: "AI: Apple on-device status", homes: [h(.chat, .localModels, "Local models"), h(.chat, .yourAI, "Choose your AI")], mac: []),
        Control(id: "service.resend", was: "Integrations: Resend key, From", homes: [h(.services, nil, "Resend")], mac: [k("resend-api-key"), k("resend-from")]),
        Control(id: "service.n8n", was: "Integrations: n8n URL, key, Workflows filter", homes: [h(.services, nil, "n8n")],
                mac: [k("n8n-url"), k("n8n-api-key"), d("n8nWorkflowFilter")]),
        Control(id: "service.vercel", was: "Integrations: Vercel token, Projects filter", homes: [h(.services, nil, "Vercel")],
                mac: [k("vercel-token"), d("vercelProjectFilter")]),
        Control(id: "service.github", was: "Integrations: GitHub token", homes: [h(.services, nil, "GitHub")], mac: [k("github-token")]),
        Control(id: "service.stripe", was: "Integrations: Stripe, Cal.com, Notion", homes: [h(.services, nil, "Stripe")], mac: [k("stripe-api-key")]),
        Control(id: "service.calcom", was: "Integrations: Stripe, Cal.com, Notion", homes: [h(.services, nil, "Cal.com")], mac: [k("calcom-api-key")]),
        Control(id: "service.notion", was: "Integrations: Stripe, Cal.com, Notion", homes: [h(.services, nil, "Notion")], mac: [k("notion-api-key")]),
        Control(id: "service.music", was: "Active pills: Resend, n8n, Vercel, GitHub, Notion, Cal.com, Stripe, Apple Music", homes: [h(.services, nil, "Music")], mac: []),
        Control(id: "shortcuts.global", was: "General: Show island with shortcut, Shortcut recorder; Shortcuts: Global shortcuts (11 actions), Turn all on, Reset to defaults",
                homes: [h(.general, .shortcuts, "Global shortcuts")],
                mac: [d("hotkeyEnabled"), d("hotkeyFlags"), d("hotkeyCode"), d("shortcut.<id>.enabled"), d("shortcut.<id>.keyCode"), d("shortcut.<id>.flags")]),
        Control(id: "shortcuts.island", was: "Shortcuts: In the island", homes: [h(.general, .shortcuts, "In the island")], mac: []),
        Control(id: "cat.main", was: "Cat: Main cat", homes: [h(.cat, .look, "Main cat")], mac: [d("cat.character")]),
        Control(id: "cat.look", was: "Cat: Look (collar, this cat's collar, fur lines)", homes: [h(.cat, .look, "Look")],
                mac: [d("cat.collar"), d("cat.collar.<id>"), d("cat.furLines")]),
        Control(id: "cat.desktop", was: "Cat: Desktop", homes: [h(.cat, .look, "Desktop")],
                mac: [d("cat.desktop.on"), d("cat.desktop.size"), d("cat.desktop.spots")]),
        Control(id: "cat.wardrobe", was: "Cat: Wardrobe", homes: [h(.cat, .outfits, "Wardrobe")], mac: [d("cat.outfit")]),
        Control(id: "cat.personality", was: "Cat: Personality", homes: [h(.cat, .personality, "Personality")], mac: [d("cat.personality.<id>")]),
        Control(id: "cat.motion", was: "Cat: Motion", homes: [h(.cat, .personality, "Motion")], mac: [d("cat.motionStyle"), d("cat.motion.<id>")]),
        Control(id: "cat.everyCat", was: "Cat: Every cat (Apply to every cat)", homes: [h(.cat, .personality, "Every cat")], mac: []),
        Control(id: "cat.display", was: "Cat: Display, Your two cats, Cats for your agents",
                homes: [h(.cat, .agentCats, "Display"), h(.cat, .agentCats, "Your two cats"), h(.cat, .agentCats, "Cats for your agents"), h(.cat, .agentCats, "Project cats")],
                mac: [d("cat.displayMode"), d("cat.pair"), d("cat.agentCat.<pillId>"), d("cat.projectCat.<catKey>")]),
        Control(id: "sidekick.master", was: "Sidekick: Recaps and nudges", homes: [h(.chat, .sidekick, "Notes")], mac: [d("sidekick.on")]),
        Control(id: "sidekick.kinds", was: "Sidekick: Muted notes, Unmute; (new) per-kind switches, Show me an example",
                homes: [h(.chat, .sidekick, "Notes"), h(.chat, .sidekick, "Muted notes")], mac: [d("sidekick.dismissals")]),
        Control(id: "sidekick.example", was: "(new) per-kind switches, Show me an example", homes: [h(.chat, .sidekick, "Notes")], mac: []),
        Control(id: "sidekick.words", was: "Sidekick: Nicer wording from a local model", homes: [h(.chat, .sidekick, "Where its words come from")],
                mac: [d("sidekick.local")]),
        Control(id: "sidekick.quiet", was: "(new)", homes: [h(.chat, .sidekick, "Quiet times")], mac: []),
        Control(id: "sidekick.today", was: "(new)", homes: [h(.chat, .sidekick, "Today so far")], mac: []),
        Control(id: "companion.humor", was: "(new) Companion: Humor", homes: [h(.chat, .companion, "Personality")], mac: [d("companion.humor")]),
        Control(id: "companion.sessions", was: "(new) Companion: See my sessions, the one-time cloud line", homes: [h(.chat, .companion, "What the chat knows")],
                mac: [d("companion.seeSessions"), d("companion.cloudNoticeShown")]),
        Control(id: "companion.conversations", was: "(new) Companion: Conversations, Delete all", homes: [h(.chat, .companion, "Conversations")],
                mac: [f("~/Library/Application Support/NotchMeow/companion/conversations/<id>.json")]),
        Control(id: "companion.sawLast", was: "(new) Companion: What the AI saw last", homes: [h(.chat, .companion, "What the AI saw last")], mac: []),
        Control(id: "devices.thisMac", was: "Devices: Visible on this network, Name", homes: [h(.devices, nil, "This Mac")],
                mac: [d("link.visible"), d("link.deviceName")]),
        Control(id: "devices.machines", was: "Devices: Machines, Pair, Forget, Local Network permission", homes: [h(.devices, nil, "Machines")],
                mac: [k("link.peer.<id>"), k("link.static-key"), k("link.device-id")]),
        Control(id: "devices.received", was: "Devices: Show in Finder", homes: [h(.devices, nil, "Received files")], mac: []),
        Control(id: "settings.selection", was: "Sidebar selection", homes: [h(.general, nil, "(the shell)")],
                mac: [d("settingsSection"), d("settingsTab.<page>")]),
    ]

    /// The Settings place a pill's card lives on, by its id alone (no catalog import): agents, Keys, Local models, Services, and General for everything else.
    static func pillHome(_ pillId: String) -> SettingsRoute.Place {
        if pillId == "integration_claude" || pillId.hasPrefix("agent_") { return SettingsRoute.Place(page: .agents) }
        switch pillId {
        case "ai_anthropic", "ai_google", "ai_openai": return SettingsRoute.Place(page: .chat, tab: .keys)
        default: break
        }
        if pillId.hasPrefix("ai_") { return SettingsRoute.Place(page: .chat, tab: .localModels) }
        if pillId.hasPrefix("integration_") { return SettingsRoute.Place(page: .services) }
        return SettingsRoute.Place(page: .general)
    }

    /// Each service pill's Keychain fields, in card order (an empty list for the Music card, which keeps none).
    static let serviceFields: [String: [String]] = [
        "integration_resend": ["resend-api-key", "resend-from"],
        "integration_n8n": ["n8n-url", "n8n-api-key"],
        "integration_vercel": ["vercel-token"],
        "integration_github": ["github-token"],
        "integration_stripe": ["stripe-api-key"],
        "integration_calcom": ["calcom-api-key"],
        "integration_notion": ["notion-api-key"],
        "integration_music": [],
    ]
}
