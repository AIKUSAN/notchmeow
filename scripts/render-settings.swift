import AppKit
import SwiftUI

// Draws the restyled Settings window without launching NotchMeow: the real shell, pages and kit (NotchBuddy/Sources/App/Settings*.swift and the kit files beside them) go into an
// NSHostingView in a borderless window that is never shown, in the light or dark appearance, and AppKit draws it into a PNG. Every value on the pictures is a fixed sample:
// this file touches no store, no live service and no real name or path (scripts/check-settings-render-private.sh pins that).
// Run it through scripts/render-settings.sh:
//   bash scripts/render-settings.sh [--out DIR] [--page P] [--tab T] [--width W] [--light] [--appstore] [--stress] [--states empty|ready|error] [--kit]
//   --page / --tab / --width pick one page, one tab, one window width (default: every page and tab at 415, 720 and 1100); --light draws the light appearance (default dark);
//   --appstore only marks the file names (the build define does the rest); --stress asks the pages for their longest strings; --kit draws the kit pieces on a sheet of their own.

enum Shot {
    static let darkBackground = CGColor(srgbRed: 0.16, green: 0.16, blue: 0.17, alpha: 1)

    /// Draws `view` at `width` and its natural height into a PNG at `url`, flattened on the window background of the appearance. Returns the image for the contact sheet.
    @MainActor @discardableResult
    static func save<V: View>(view: V, width: CGFloat, scheme: ColorScheme, url: URL) -> CGImage {
        let appearance = NSAppearance(named: scheme == .dark ? .darkAqua : .aqua)!
        let host = NSHostingView(rootView: view)
        let height = NSHostingController(rootView: view).sizeThatFits(in: CGSize(width: width, height: 100_000)).height.rounded(.up)
        host.frame = NSRect(x: 0, y: 0, width: width, height: height)
        let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.appearance = appearance
        win.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.25))   // SwiftUI settles (the width-driven sidebar mode, the controls)
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { FileHandle.standardError.write(Data("no bitmap\n".utf8)); exit(1) }
        host.cacheDisplay(in: host.bounds, to: rep)
        var fill = darkBackground
        appearance.performAsCurrentDrawingAppearance { fill = NSColor.windowBackgroundColor.cgColor }
        guard let shot = rep.cgImage,
              let cg = CGContext(data: nil, width: shot.width, height: shot.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
        cg.setFillColor(fill)
        cg.fill(CGRect(x: 0, y: 0, width: shot.width, height: shot.height))
        cg.draw(shot, in: CGRect(x: 0, y: 0, width: shot.width, height: shot.height))
        guard let flat = cg.makeImage(), let png = NSBitmapImageRep(cgImage: flat).representation(using: .png, properties: [:]) else { exit(1) }
        try! png.write(to: url)
        print("wrote \(url.path)")
        return flat
    }
}

/// The page cases. Each page's sample is plain values only (no store, no live service, no real name or path). General and Devices have theirs here (Task 5); Tasks 6 to 8
/// replace the others.
enum SettingsSamples {
    @MainActor static func page(_ p: SettingsRoute.Page, tab: SettingsRoute.Tab?, state: String, stress: Bool) -> AnyView {
        switch p {
        case .general:
            if tab == .shortcuts { return AnyView(ShortcutsSettingsView()) }
            return AnyView(GeneralSettingsTab(model: generalModel(state: state, stress: stress)))
        case .devices: return AnyView(devicesView(state: state, stress: stress))
        case .agents: return AnyView(AgentsSettingsPage(model: agentsModel(state: state, stress: stress), actions: noAgentActions))
        case .services: return AnyView(servicesView(state: state, stress: stress))
        case .chat:
            switch tab {
            case .yourAI: return AnyView(YourAITab(model: yourAIModel(state: state, stress: stress), setChat: { _ in }, openKeys: {}))
            case .keys: return AnyView(KeysTab(cards: keyCards(state: state, stress: stress), text: { id in .constant(keyText(id, state: state)) }, dirty: { _ in false },
                                               saved: { keySaved($0, state: state) }, save: { _ in }, remove: { _ in }, toggle: { _ in }))
            case .localModels: return AnyView(LocalModelsTab(model: localModelsModel(state: state, stress: stress), showAddServer: .constant(false), rescan: {},
                                                             remove: { _ in }, toggle: { _ in }, addServer: { _, _, _ in }))
            case .sidekick:
                // The ready picture opens the recap's example, so the checkpoint sees the sample; the other pictures keep it closed, as the app does.
                return AnyView(SidekickSettingsView(store: sidekickStore(state: state), found: state == "empty" ? nil : "Local \u{00B7} qwen3.5:2b",
                                                    example: state == "ready" ? "recap" : nil))
            case .companion: return AnyView(CompanionTab(model: companionModel(stress: stress), setHumor: { _ in }, setSeeSessions: { _ in }, deleteAll: {}))
            default: return placeholder(stress: stress)
            }
        case .cat: return catView(tab: tab, state: state, stress: stress)
        }
    }

    /// The four-slot sample, in catalog order. Sample ids and names only.
    private static let catalog: [(id: String, name: String)] = [
        ("agent_antigravity", "Antigravity"), ("agent_codex", "Codex"), ("ai_anthropic", "Anthropic"), ("sample_stress", "Studio PC in the back office"),
    ]
    private static let places: [String: SettingsRoute.Place] = [
        "agent_antigravity": SettingsRoute.Place(page: .agents), "agent_codex": SettingsRoute.Place(page: .agents),
        "ai_anthropic": SettingsRoute.Place(page: .chat, tab: .keys), "sample_stress": SettingsRoute.Place(page: .devices),
    ]

    /// Which catalog pills are on: none when empty, the first two otherwise, all four when the state is error or the picture is a stress one (the amber line).
    private static func active(state: String, stress: Bool) -> Set<String> {
        if stress || state == "error" { return Set(catalog.map(\.id)) }
        if state == "empty" { return [] }
        return ["agent_antigravity", "agent_codex"]
    }

    private static func generalModel(state: String, stress: Bool) -> GeneralSettingsModel {
        let on = active(state: state, stress: stress)
        let links = catalog.filter { on.contains($0.id) }.map { (name: $0.name, place: places[$0.id] ?? SettingsRoute.Place(page: .general)) }
        return GeneralSettingsModel(
            soundEnabled: .constant(true), soundVolume: .constant(0.12), openOnHover: .constant(false), focusAware: .constant(true), hoverGlow: .constant(true),
            tuckAway: .constant(.m15), closeAfter: .constant(15), mainPill: .constant("integration_claude"),
            mainChoices: [("integration_claude", "Claude Code"), ("agent_cursor", "Cursor"), ("agent_antigravity", "Antigravity"), ("agent_codex", "Codex")],
            slots: SettingsStatus.slots(active: on, catalog: catalog), slotLinks: links, launchAtStartup: .constant(false), open: { _ in })
    }

    private static func devicesView(state: String, stress: Bool) -> DevicesSettingsView {
        var rows = [LinkDirectory.Row(id: "sample-desk", name: "Desk PC", state: .pairedOnline),
                    LinkDirectory.Row(id: "sample-travel", name: "Travel laptop", state: .pairedOffline),
                    LinkDirectory.Row(id: "sample-mini", name: "Office Mac mini", state: .available)]
        if stress { rows.append(LinkDirectory.Row(id: "sample-long", name: "A machine with a rather long name for testing the column", state: .pairedOnline)) }
        switch state {
        case "empty":
            return DevicesSettingsView(visible: false, deviceName: "Studio Mac", listening: false, problem: nil, note: nil, rows: [])
        case "error":
            return DevicesSettingsView(visible: true, deviceName: "Studio Mac", listening: false, problem: "The network refused to listen. Turn Visible off and on again.",
                                       note: "Pairing with Desk PC did not finish. Try again.", rows: rows)
        default:
            return DevicesSettingsView(visible: true, deviceName: "Studio Mac", listening: true, problem: nil, note: nil, rows: rows)
        }
    }

    // MARK: Agents and Services (Task 6). Sample values only: fake keys, made-up paths, sample names.

    static var noAgentActions: AgentsSettingsActions {
        AgentsSettingsActions(
            toggle: { _ in }, install: { _ in }, uninstall: { _ in }, confirm: { _ in }, cancel: { _ in }, setShowPlan: { _ in },
            installRelay: {}, uninstallRelay: {}, confirmRelay: {}, cancelRelay: {}, copy: { _ in }, reveal: { _ in })
    }

    /// The failing picture (`--states error`, or `--stress`): the cap is reached and some drafts are not saved.
    private static func failing(_ state: String, _ stress: Bool) -> Bool { state == "error" || stress }

    /// The pills on, across the pages (the cap counts them all): none when empty, four when failing, three otherwise.
    private static func activeSet(state: String, stress: Bool) -> Set<String> {
        if failing(state, stress) { return ["agent_cursor", "agent_antigravity", "agent_codex", "ai_anthropic"] }
        if state == "empty" { return [] }
        return ["agent_antigravity", "agent_codex", "integration_resend"]
    }

    /// A made-up home folder: the preview shows it as ~ (SettingsLayout.displayText), and the render tool reads no real one.
    static let sampleHome = "/Users/sample"

    private static let pendingSample = """
    {
      "hooks": {
        "BeforeTool": [{ "matcher": "*", "hooks": [{ "type": "command", "command": "/Users/sample/.gemini/notchmeow/nm-hook" }] }]
      }
    }
    """

    private static func agentsModel(state: String, stress: Bool) -> AgentsSettingsModel {
        let on = activeSet(state: state, stress: stress)
        let installed: [HookKind: Bool] = state == "ready" ? [.claude: true, .gemini: true, .codex: true, .antigravity: false]
            : state == "error" ? [.claude: true, .gemini: false, .codex: true, .antigravity: false]
            : [.claude: false, .gemini: false, .codex: false, .antigravity: false]
        let pillRows: [(id: String, name: String, color: String, hook: HookKind?)] = [
            ("integration_claude", "Claude Code", "#F5F6F8", nil), ("agent_cursor", "Cursor", "#C0C4CC", nil),
            ("agent_antigravity", "Antigravity", "#E879F9", .antigravity), ("agent_codex", "Codex", "#2DD4BF", .codex),
            ("agent_gemini", "Gemini CLI", "#8AB4F8", .gemini),
        ]
        // What the build offers (PillCatalog.available): the App Store build drops the GitHub-only agents.
        let offered = Set(PillCatalog.available.map(\.id))
        let pills = pillRows.filter { offered.contains($0.id) }.map { row -> PillSwitchModel in
            var missing: String? = nil
            if let hook = row.hook, installed[hook] != true { missing = "Hooks not installed" }
            let isOn = on.contains(row.id)
            return PillSwitchModel(id: row.id, name: row.name, color: row.color, isOn: isOn,
                                   state: SettingsStatus.pillSwitch(isOn: isOn, isMain: row.id == "integration_claude", activeCount: on.count, missing: missing))
        }
        func card(_ kind: HookKind, _ title: String, _ path: String, next: String? = nil) -> HookCardModel {
            let ok = installed[kind] ?? false
            let failed = kind == .claude && state == "error"
            return HookCardModel(
                kind: kind, title: title, chip: SettingsStatus.hookChip(installed: ok, needsUpdate: failed), next: ok ? next : nil, path: path,
                revealable: kind == .claude,
                note: failed ? HookNote(ok: false, text: "❌ ~/.claude/settings.json is not valid JSON — NotchMeow has not touched it.") : nil,
                pendingJSON: kind == .gemini && state == "error" ? pendingSample : nil, needsUpdate: failed)
        }
        let claudePath = stress ? "~/Library/Application Support/NotchMeow/sample-hooks/claude-code-stress-sample/nm-hook-binary" : "~/.claude/notchmeow/nm-hook"
        let hooks = [
            card(.claude, "Claude Code hooks", claudePath),
            card(.gemini, "Gemini CLI hooks", "~/.gemini/settings.json", next: "Restart Gemini CLI to activate"),
            card(.antigravity, "Antigravity hooks", "~/.gemini/config/hooks.json"),
            card(.codex, "Codex hooks", "~/.codex/hooks.json", next: "Open Codex, run /hooks or open Hooks in the app's settings, and trust them"),
        ]
        let plan = PlanUsageModel(showInNotch: state != "empty", relayInstalled: state == "ready", note: nil,
                                  heard: state == "ready" ? "Last heard from Claude Code 2 minutes ago." : nil, pendingJSON: nil)
#if APPSTORE
        return AgentsSettingsModel(pills: pills, hooks: [hooks[0]], plan: nil, home: sampleHome)
#else
        return AgentsSettingsModel(pills: pills, hooks: hooks, plan: plan, home: sampleHome)
#endif
    }

    private static let longURL = String(("https://n8n.example.com/" + String(repeating: "workflow-", count: 12)).prefix(120))
    private static let workflows = [
        "Sync the customer onboarding spreadsheet to the CRM every night", "Send the weekly report", "Build the sample preview",
        "Nightly backup check", "Welcome email for new trials",
    ]
    private static let projects = ["marketing-site-preview-environment-for-the-autumn-launch", "docs-site"]

    private static func servicesView(state: String, stress: Bool) -> ServicesSettingsPage {
        let fails = failing(state, stress)
        let texts: [String: String] = state == "empty" ? [:]
            : fails ? ["resend-api-key": "sample-key-0001", "n8n-url": longURL, "n8n-api-key": "sample-key-0000", "github-token": "sample-key-0000", "vercel-token": "sample-key-0000"]
            : ["resend-api-key": "sample-key-0000", "resend-from": "sample@example.com", "n8n-url": "https://n8n.example.com", "n8n-api-key": "sample-key-0000", "github-token": "sample-key-0000", "vercel-token": "sample-key-0000"]
        let saved: Set<String> = state == "empty" ? []
            : fails ? ["n8n-api-key", "github-token", "vercel-token"]
            : ["resend-api-key", "resend-from", "n8n-url", "n8n-api-key", "github-token", "vercel-token"]
        let dirty: Set<String> = fails ? ["resend-api-key", "n8n-url"] : []
        let on = activeSet(state: state, stress: stress)
        let watched: Set<String> = fails ? [workflows[0]] : Set(workflows.prefix(3))

        func pill(_ id: String, _ name: String, _ color: String) -> PillSwitchModel {
            let isOn = on.contains(id)
            return PillSwitchModel(id: id, name: name, color: color, isOn: isOn,
                                   state: SettingsStatus.pillSwitch(isOn: isOn, isMain: false, activeCount: on.count, missing: nil))
        }
        func chip(_ keys: [String]) -> String? {
            if keys.contains(where: { dirty.contains($0) }) { return "Not saved" }
            return keys.isEmpty ? nil : SettingsStatus.serviceChip(saved: keys.contains(where: { saved.contains($0) }))
        }
        func card(_ id: String, _ name: String, _ color: String, fields: [ServiceFieldModel], help: String? = nil, filter: ServiceFilterModel? = nil) -> ServiceCardModel {
            ServiceCardModel(id: id, name: name, color: color, chip: chip(fields.map(\.id)), pill: pill(id, name, color),
                             fields: fields, help: help, filter: filter)
        }
        func field(_ id: String, _ placeholder: String, secure: Bool = true) -> ServiceFieldModel {
            ServiceFieldModel(id: id, placeholder: placeholder, secure: secure)
        }
        let n8nFilter = ServiceFilterModel(label: "Workflows", items: workflows, filter: .constant(watched), loading: false, onLoad: {})
        let vercelFilter = ServiceFilterModel(label: "Projects", items: projects, filter: .constant([]), loading: false, onLoad: {})
        var cards = [
            card("integration_resend", "Resend", "#22C55E", fields: [field("resend-api-key", "API key  (re_…)"), field("resend-from", "From address  (you@yourdomain.com)", secure: false)]),
            card("integration_n8n", "n8n", "#F29B38", fields: [field("n8n-url", "Instance URL  (https://…)", secure: false), field("n8n-api-key", "API key")], filter: n8nFilter),
            card("integration_vercel", "Vercel", "#7C5CFF", fields: [field("vercel-token", "Token")], filter: vercelFilter),
            card("integration_github", "GitHub", "#F4505E", fields: [field("github-token", "Personal Access Token")],
                 help: "Classic token with repo scope, or fine-grained with read access to Pull requests, Commit statuses and Actions."),
            card("integration_stripe", "Stripe", "#0570DE", fields: [field("stripe-api-key", "Secret key  (sk_live_… or sk_test_…)")]),
            card("integration_calcom", "Cal.com", "#C9956A", fields: [field("calcom-api-key", "API key  (cal_live_…)")]),
            card("integration_notion", "Notion", "#8C8C8C", fields: [field("notion-api-key", "Integration token  (secret_…)")]),
        ]
        cards.append(card("integration_music", "Music", "#FA2D48", fields: [], help: "Shows what Apple Music or Spotify is playing. Nothing to enter."))
        let offered = Set(PillCatalog.available.map(\.id))
        return ServicesSettingsPage(
            cards: cards.filter { offered.contains($0.id) }, text: { id in .constant(texts[id] ?? "") }, dirty: { dirty.contains($0) },
            saved: { saved.contains($0) }, save: { _ in }, toggle: { _ in })
    }

    private static func placeholder(stress: Bool) -> AnyView {
        AnyView(SettingsCard("Sample") {
            HelpText(stress ? "A sample sentence with a very long path-like word /Users/sample/Library/Application-Support/NotchMeow/a-long-folder-name/and-another-one that has to wrap between words." : "A sample sentence.")
        })
    }
}

// MARK: Settings → Sidekick and Cat (Task 8). Sample values only: each store is on a dictionary of its own (no UserDefaults), the agents are the display sample's, and the names
// are made up. The pages are the app's own views, so the pictures show what they do.

/// A dictionary for the samples' stores: nothing is read from or written to UserDefaults.
final class RenderSettingsBacking: CatSettingsBacking {
    var values: [String: Any] = [:]
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
    func removeObject(forKey key: String) { values[key] = nil }
    func allKeys() -> [String] { Array(values.keys) }
}

extension SettingsSamples {
    /// The Sidekick tab's store: ready mutes the errors and the gone-quiet kinds; empty mutes nothing; error mutes all four stuck kinds and turns the master switch off.
    @MainActor static func sidekickStore(state: String) -> SidekickStore {
        let store = SidekickStore(backing: RenderSettingsBacking())
        switch state {
        case "ready":
            for kind in ["stuck.errors", "stuck.silent"] { store.mute(kind) }
        case "error":
            for kind in SettingsSidekick.stuckKinds { store.mute(kind) }
            store.setOn(false)
        default:
            break
        }
        return store
    }

    /// The Cat tab: one store with the agents' display (A cat for each agent, so the list has rows), its coats, and the Auto outfit for today (there is no clock here).
    /// `stress` names the first agent with a long name for the column, and the first project with a long folder name.
    /// Project cats (Task 12): the empty picture has no project at all; the others have two live projects and one stored cat whose project is not running (its row has Reset).
    @MainActor static func catView(tab: SettingsRoute.Tab?, state: String, stress: Bool) -> AnyView {
        let store = CatSettingsStore(backing: RenderSettingsBacking(), config: CatConfig())
        store.setDisplayMode(.perAgent)
        let agents = CatDisplaySample.pills.filter { CatDisplaySettings.isAgentPill($0.id) }.enumerated().map { i, pill in
            CatAgentList.Agent(id: pill.id, name: stress && i == 0 ? "A rather long agent name for the column" : pill.name, color: pill.color, last: Double(100 - i * 10))
        }
        store.ensureAgentCats(for: agents.map(\.id))
        store.config.outfit = Wardrobe.resolve(store.wardrobe.outfit, Wardrobe.today())
        let firstProject = stress ? "a-rather-long-project-folder-name-for-the-column" : "notchmeow"
        var projects: [ProjectCatList.Live] = []
        if state != "empty" {
            store.setProjectCat("leo", for: "old-site")
            projects = [ProjectCatList.Live(catKey: firstProject, name: firstProject), ProjectCatList.Live(catKey: "site", name: "site — a")]
        }
        return AnyView(CatSettingsView(store: store, alwaysActive: true, agents: agents, tab: tab, projects: projects))
    }
}

// MARK: Settings → AI and chat → Companion (Task 9). Sample values only: a fixed brain, 12 saved conversations and three made-up lines of what was sent (no path, no name).
extension SettingsSamples {
    @MainActor static func companionModel(stress: Bool) -> CompanionTab.Model {
        CompanionTab.Model(humor: "little", seeSessions: true,
                           brain: stress ? "Claude · your plan, a much longer brain name that has to wrap between its words" : "Claude · your plan",
                           conversations: 12,
                           lastSent: ["Companion: a short, warm reply in at most two sentences.", "Right now: 2 sessions in Demo Project, one waits for your OK.", "User: Explain this screenshot."])
    }
}

// MARK: Settings → AI and chat (Task 7). Sample values only: fake keys (sample-key-0000), sample servers and model names. The rows come from SettingsAI, the way the app's section
// maps them (Task 11), so the picture shows what the mapping does.

extension SettingsSamples {
    #if APPSTORE
    static let githubBuild = false
    #else
    static let githubBuild = true
    #endif

    private static let ollama = SettingsAI.Server(id: "ollama", provider: .ollama, name: "Ollama", network: false, models: ["qwen3.5:2b", "llama4"])
    private static let studio = SettingsAI.Server(id: "custom-studio", provider: .custom, name: "Studio PC", network: true, models: ["gemma-4-27b"])
    private static let backOffice = SettingsAI.Server(id: "custom-back-office", provider: .lmstudio, name: "Studio PC in the back office (LM Studio)", network: true,
                                                      models: ["a-long-local-model-name-for-menus-stress", "llama4"])
    /// A server that answers but has no model loaded: it is not a row of Your AI, and its Local models row says how to make it ready.
    private static let noModels = SettingsAI.Server(id: "custom-jan", provider: .custom, name: "Jan", network: false, models: [])
    private static let customAnthropic = "claude-sonnet-5-5-20261001-extended-thinking-preview"
    private static let customTag = "__custom__"
    private static let presets: [(id: String, label: String)] = [
        ("claude-sonnet-4-6", "Claude Sonnet 4.6"), ("claude-sonnet-5-5", "Claude Sonnet 5.5"),
        ("claude-opus-5-5", "Claude Opus 5.5"), ("claude-haiku-4-5-20251001", "Claude Haiku 4.5"),
    ]
    private static let networkNote = "network · unencrypted on your network"

    static func chatInput(state: String, stress: Bool) -> SettingsAI.Input {
        if state == "empty" {
            return SettingsAI.Input(githubBuild: githubBuild, claudeState: .notInstalled, claudeVersion: nil, claudeSignIn: "", claudeEnabled: false,
                                    claudeModel: "sonnet", keys: [], cloudModel: [:], servers: [], memory: [:], appleReady: false)
        }
        return SettingsAI.Input(githubBuild: githubBuild, claudeState: .signedIn, claudeVersion: "2.1.289", claudeSignIn: "your Claude plan",
                                claudeEnabled: true, claudeModel: "sonnet",
                                keys: state == "error" ? [.anthropic, .openai] : [.anthropic],
                                cloudModel: stress ? [.anthropic: customAnthropic] : [.anthropic: "claude-sonnet-5-5"],
                                servers: [ollama, stress ? backOffice : studio, noModels], memory: ["ollama": "llama4"], appleReady: true)
    }

    /// The pill's switch, as the app will build it: on when the sample's active set has it, the cap rule, and the missing word as its chip.
    private static func chatPill(_ id: String, _ name: String, _ color: String, missing: String?, state: String, stress: Bool) -> PillSwitchModel {
        let on = activeSet(state: state, stress: stress)
        let isOn = on.contains(id)
        return PillSwitchModel(id: id, name: name, color: color, isOn: isOn,
                               state: SettingsStatus.pillSwitch(isOn: isOn, isMain: false, activeCount: on.count, missing: missing))
    }

    private static func claudeLine(_ i: SettingsAI.Input) -> String {
        switch i.claudeState {
        case .notInstalled: return "Claude Code isn't installed on this Mac."
        case .tooOld: return "Claude Code is too old for this."
        case .signedOut: return "Claude Code is signed out. Signing in opens Terminal, and finishes in your browser."
        case .unknown: return "Couldn't ask Claude Code. Is it installed properly?"
        case .signedIn: return "✓ Claude Code \(i.claudeVersion ?? ""), signed in with \(i.claudeSignIn)."
        }
    }

    private static func resolution(state: String, stress: Bool) -> String {
        if state == "empty" { return "Nothing is ready yet. Add a key on the Keys tab or start a local server." }
        if stress { return "Studio PC in the back office (LM Studio) · a-long-local-model-name, falls back to Apple on-device" }
        return githubBuild ? "Claude plan · Sonnet, falls back to Apple on-device" : "Anthropic · claude-sonnet-5-5, falls back to Apple on-device"
    }

    /// Auto, then the cloud models with a key, the Claude plan's models when it is ready, the local models, and Apple on-device, as the app's pop-up lists them.
    private static func choiceSections(_ i: SettingsAI.Input) -> [AIChoiceSection] {
        var out: [AIChoiceSection] = []
        let cloud = SettingsAI.keyProviders.filter { i.keys.contains($0) && i.cloudModel[$0] != nil }
        if !cloud.isEmpty {
            let items: [(label: String, value: FeatureSetting)] = cloud.map { p in
                let model = i.cloudModel[p] ?? ""
                return (label: "\(ChatProvider(p).displayName) · \(model)", value: .explicit(ModelRef(provider: p, model: model)))
            }
            out.append(AIChoiceSection(id: "cloud", title: "Cloud", items: items))
        }
        if i.githubBuild && i.claudeState == .signedIn && i.claudeEnabled {
            let items: [(label: String, value: FeatureSetting)] = ClaudeCodeModel.allCases.map { m in
                (label: "Claude plan · \(m.label)", value: .explicit(ModelRef(provider: .claudeCode, model: m.rawValue)))
            }
            out.append(AIChoiceSection(id: "plan", title: "Claude plan", items: items))
        }
        let servers = i.servers.filter { !$0.models.isEmpty }
        if !servers.isEmpty {
            let items: [(label: String, value: FeatureSetting)] = servers.flatMap { s in
                s.models.map { m in (label: "\(s.name) · \(m)", value: FeatureSetting.explicit(ModelRef(provider: s.provider, model: m, serverID: s.id))) }
            }
            out.append(AIChoiceSection(id: "local", title: "Local", items: items))
        }
        if i.appleReady {
            out.append(AIChoiceSection(id: "apple", title: "Apple on-device",
                                       items: [(label: "Apple on-device", value: .explicit(ModelRef(provider: .apple, model: "system")))]))
        }
        return out
    }

    private static func prefer(_ i: SettingsAI.Input) -> AIPreferModel? {
        let claudeReady = i.githubBuild && i.claudeState == .signedIn && i.claudeEnabled
        let cloudCount = (i.keys.contains(.anthropic) ? 1 : 0) + (i.keys.contains(.openai) ? 1 : 0) + (claudeReady ? 1 : 0)
        guard cloudCount >= 2 else { return nil }
        var choices: [(id: AIProviderID, label: String)] = []
        if claudeReady { choices.append((id: .claudeCode, label: "Claude plan")) }
        if i.keys.contains(.anthropic) { choices.append((id: .anthropic, label: "Claude API")) }
        if i.keys.contains(.openai) { choices.append((id: .openai, label: "OpenAI")) }
        return AIPreferModel(selection: .constant(claudeReady ? .claudeCode : .anthropic), choices: choices)
    }

    /// Your AI: the two features, the preference, and the rows from SettingsAI with Chat on Auto (so no row is Main).
    static func yourAIModel(state: String, stress: Bool) -> YourAIModel {
        let i = chatInput(state: state, stress: stress)
        let rows: [AIRowModel] = SettingsAI.rows(i).map { r in
            var needsKey = false
            if case .key(let p) = r { needsKey = !i.keys.contains(p) }
            return AIRowModel(id: r, title: SettingsAI.title(r, i), line: SettingsAI.helpLine(r, i), chip: SettingsAI.chip(r, i),
                              isMain: SettingsAI.isMain(r, chat: .auto), makeMain: SettingsAI.makeMain(r, i), addKey: needsKey,
                              reason: SettingsAI.reasonLine(r, i))
        }
        let sections = choiceSections(i)
        let features = [
            AIFeatureRow(id: .chat, label: "Chat", selection: .constant(.auto), sections: sections,
                         resolution: resolution(state: state, stress: stress)),
            AIFeatureRow(id: .files, label: "File questions",
                         selection: .constant(state == "empty" ? .auto : .explicit(ModelRef(provider: .ollama, model: "qwen3.5:2b", serverID: "ollama"))),
                         sections: sections, resolution: state == "empty" ? resolution(state: state, stress: stress) : nil),
        ]
        #if APPSTORE
        let claude: ClaudePlanDetails? = nil
        #else
        let claude: ClaudePlanDetails? = githubBuild ? ClaudePlanDetails(
            state: i.claudeState, note: ClaudeCodeEngine.note, line: claudeLine(i), inUse: false, checking: false, model: .constant(.sonnet),
            connect: {}, stop: {}, checkAgain: {}, signIn: {}, guide: URL(string: "https://claude.com/product/claude-code")) : nil
        #endif
        return YourAIModel(features: features, prefer: prefer(i), rows: rows, claude: claude)
    }

    static func keyText(_ id: String, state: String) -> String {
        switch id {
        case "anthropic-api-key": return state == "empty" ? "" : "sample-key-0000"
        case "openai-api-key": return state == "error" ? "sample-key-0000" : ""
        default: return ""
        }
    }

    static func keySaved(_ id: String, state: String) -> Bool { !keyText(id, state: state).isEmpty }

    /// Keys: one card per provider. The OpenAI key is the rejected one in the error picture; a stress picture asks Anthropic for a custom model.
    static func keyCards(state: String, stress: Bool) -> [KeyCardModel] {
        let i = chatInput(state: state, stress: stress)
        let anthropicModel = AnthropicModelPicker(choice: .constant(stress ? customTag : "claude-sonnet-5-5"), options: presets, customTag: customTag,
                                                  custom: .constant(stress ? customAnthropic : ""))
        return [
            KeyCardModel(provider: .anthropic, name: "Anthropic", color: ChatProvider.anthropic.accentHex,
                         help: "From the Claude Console. Saved in the Keychain, checked when you save.", fieldId: "anthropic-api-key",
                         placeholder: "API key (sk-ant-…)", works: i.keys.contains(.anthropic) ? true : nil,
                         pill: chatPill("ai_anthropic", "Anthropic", ChatProvider.anthropic.accentHex,
                                        missing: i.keys.contains(.anthropic) ? nil : "Key not configured", state: state, stress: stress),
                         anthropicModel: anthropicModel),
            KeyCardModel(provider: .google, name: "Google AI", color: ChatProvider.google.accentHex,
                         help: "From Google AI Studio. Saved in the Keychain, checked when you save.", fieldId: "google-api-key",
                         placeholder: "API key (AI Studio)", works: nil,
                         pill: chatPill("ai_google", "Google AI", ChatProvider.google.accentHex, missing: "Key not configured", state: state, stress: stress),
                         anthropicModel: nil),
            KeyCardModel(provider: .openai, name: "OpenAI", color: ChatProvider.openai.accentHex,
                         help: "From the OpenAI dashboard. Saved in the Keychain, checked when you save.", fieldId: "openai-api-key",
                         placeholder: "API key (sk-…)", works: state == "error" ? false : nil,
                         pill: chatPill("ai_openai", "OpenAI", ChatProvider.openai.accentHex,
                                        missing: i.keys.contains(.openai) ? nil : "Key not configured", state: state, stress: stress),
                         anthropicModel: nil),
        ]
    }

    /// The help text under a server the chat cannot use yet: makeMain's reason for it, nil for a server that has a model.
    private static func serverNote(_ id: String, _ i: SettingsAI.Input) -> String? {
        if case .unavailable(let reason) = SettingsAI.makeMain(.server(id), i) { return reason }
        return nil
    }

    /// Local models: the servers with their chips, the get link of one that is not installed, Remove on the ones the user added, and Apple's chip.
    static func localModelsModel(state: String, stress: Bool) -> LocalModelsModel {
        let i = chatInput(state: state, stress: stress)
        var servers: [ServerRowModel] = i.servers.map { s in
            let running = !s.models.isEmpty
            return ServerRowModel(
                id: s.id, name: s.name, chip: SettingsAI.serverChip(.running(s.models.map { ModelInfo(id: $0) })), ready: running,
                network: s.network ? networkNote : nil, getLink: nil, removable: s.id.hasPrefix("custom-"),
                pill: s.provider == .ollama
                    ? chatPill("ai_ollama", "Ollama", ChatProvider.ollama.accentHex, missing: nil, state: state, stress: stress) : nil,
                note: serverNote(s.id, i))
        }
        if state != "empty" {
            servers.append(ServerRowModel(
                id: "lmstudio", name: "LM Studio", chip: SettingsAI.serverChip(.notInstalled), ready: false, network: nil,
                getLink: (label: "Get LM Studio", url: URL(string: "https://lmstudio.ai")!), removable: false,
                pill: chatPill("ai_lmstudio", "LM Studio", ChatProvider.lmstudio.accentHex, missing: "Not connected", state: state, stress: stress)))
        }
        return LocalModelsModel(servers: servers, apple: i.appleReady ? SettingsAI.chip(.apple, i) : nil, rescanning: false)
    }
}

/// Every kit piece in one column, as a page would lay them out.
struct KitSheet: View {
    @State private var model = "Sample model"
    let windowWidth: Double
    var body: some View {
        let mode = SettingsLayout.sidebarMode(windowWidth: windowWidth)
        VStack(alignment: .leading, spacing: 18) {
            SettingsCard("Sound", summary: "Ready") {
                SettingRow("Volume") { Text("70 %") }
                SettingRow("Show the island on every screen when more than one display is connected", help: "A long label stacks its control under it and wraps between words.") {
                    Picker("", selection: $model) { Text("Sample model").tag("Sample model"); Text("Another model").tag("Another model") }
                        .labelsHidden().frame(width: SettingsLayout.pickerWidth, alignment: .leading)
                }
            }
            SettingsCard("Hooks", summary: "Needs update", footer: "The footer is help text under the card.") {
                SwitchRow("Show on the island", isOn: .constant(true))
                SwitchRow("Open on hover", help: "Opens the island when the pointer rests on the notch.", isOn: .constant(false), chip: "Hooks not installed")
                SwitchRow("Use my OpenAI plan", isOn: .constant(false), chip: SettingsStatus.capSentence, disabled: true)
                KeyRow("API key (sk-…)", text: .constant("sample-key-0000"), saved: true, dirty: true, works: false, save: {}, remove: {})
                WrapRow {
                    Button("Install hooks") {}.buttonStyle(.borderedProminent)
                    Button("Uninstall") {}.buttonStyle(.bordered)
                    Button("Confirm & write") {}.buttonStyle(.bordered)
                    Button("Cancel") {}.buttonStyle(.bordered)
                    Button("Show in Finder") {}.buttonStyle(.bordered)
                }
                PathDisclosure(path: "~/Library/Application Support/NotchMeow/a-sample-folder/settings-sample.json", copy: { _ in }, reveal: {}, opened: true)
                HelpText("One sentence of help. A second sentence that is a little longer than the first. A third one, long enough to wrap onto a second line in the narrow column.")
                WrapRow {
                    StatusChip("Ready")
                    StatusChip("Needs update")
                    StatusChip("Not ready")
                    StatusChip("No key yet")
                    StatusChip(SettingsStatus.capSentence)
                }
            }
            SettingsTabBar(tabs: SettingsRoute.tabs(.chat), selection: .constant(.keys))
            HelpText("The same bar in 160 pt: it becomes a menu with the current tab's name.")
            SettingsTabBar(tabs: SettingsRoute.tabs(.chat), selection: .constant(.keys)).frame(width: 160)
            SettingsBanner("❌ Sample error that is long enough to wrap onto a second line when the column is narrow.", dismiss: {})
        }
        .frame(width: SettingsLayout.columnWidth(windowWidth: windowWidth), alignment: .leading)
        .padding(.vertical, 16)
        .frame(width: windowWidth)
        .environment(\.settingsMode, mode)
    }
}

/// Every picture drawn this run, at 0.35 scale, four across, each captioned with its file name.
enum ContactSheet {
    @MainActor static func save(_ shots: [(name: String, image: CGImage)], dark: Bool, url: URL) {
        let scale = 0.35, columns = 4, gap = 16.0, captionHeight = 22.0
        let sizes = shots.map { CGSize(width: Double($0.image.width) * scale, height: Double($0.image.height) * scale) }
        let cellWidth = (sizes.map(\.width).max() ?? 100)
        var rowHeights: [Double] = []
        for start in stride(from: 0, to: shots.count, by: columns) {
            rowHeights.append((sizes[start..<min(start + columns, shots.count)].map(\.height).max() ?? 0) + captionHeight)
        }
        let width = Int(Double(columns) * cellWidth + Double(columns + 1) * gap)
        let height = Int(rowHeights.reduce(0, +) + Double(rowHeights.count + 1) * gap)
        guard let cg = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
        cg.setFillColor(dark ? CGColor(srgbRed: 0.1, green: 0.1, blue: 0.11, alpha: 1) : CGColor(srgbRed: 0.88, green: 0.88, blue: 0.89, alpha: 1))
        cg.fill(CGRect(x: 0, y: 0, width: width, height: height))
        let ink: NSColor = dark ? .white : .black
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 13, weight: .semibold), .foregroundColor: ink]
        var top = gap
        for (rowIndex, start) in stride(from: 0, to: shots.count, by: columns).enumerated() {
            for i in start..<min(start + columns, shots.count) {
                let x = gap + Double(i - start) * (cellWidth + gap)
                let size = sizes[i]
                // CoreGraphics counts from the bottom: the caption sits above its picture.
                let pictureBottom = Double(height) - top - captionHeight - size.height
                cg.draw(shots[i].image, in: CGRect(x: x, y: pictureBottom, width: size.width, height: size.height))
                let previous = NSGraphicsContext.current
                NSGraphicsContext.current = NSGraphicsContext(cgContext: cg, flipped: false)
                NSAttributedString(string: shots[i].name, attributes: attrs).draw(at: CGPoint(x: x, y: pictureBottom + size.height + 4))
                NSGraphicsContext.current = previous
            }
            top += rowHeights[rowIndex] + gap
        }
        guard let image = cg.makeImage(), let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else { exit(1) }
        try! png.write(to: url)
        print("wrote \(url.path)")
    }
}

@main
struct RenderSettings {
    static let usage = "usage: render-settings.sh [--out DIR] [--page P] [--tab T] [--width W] [--light] [--appstore] [--stress] [--states empty|ready|error] [--kit]"

    @MainActor static func main() {
        var out = (NSTemporaryDirectory() as NSString).appendingPathComponent("settings-render")
        var pageName: String?, tabName: String?, widths: [Double] = [415, 720, 1100]
        var light = false, appstore = false, stress = false, kit = false, state = "ready"
        func fail(_ message: String) -> Never { FileHandle.standardError.write(Data("\(message)\n\(usage)\n".utf8)); exit(2) }
        var it = CommandLine.arguments.dropFirst().makeIterator()
        func value(_ what: String) -> String { guard let v = it.next() else { fail("\(what) needs a value") }; return v }
        while let k = it.next() {
            switch k {
            case "--out": out = value(k)
            case "--page": pageName = value(k)
            case "--tab": tabName = value(k)
            case "--width": guard let w = Double(value(k)), w > 0 else { fail("--width needs a number") }; widths = [w]
            case "--light": light = true
            case "--appstore": appstore = true
            case "--stress": stress = true
            case "--states": state = value(k)
            case "--kit": kit = true
            default: fail("unknown argument \(k)")
            }
        }
        guard ["empty", "ready", "error"].contains(state) else { fail("unknown state \(state)") }
        let pages: [SettingsRoute.Page]
        if let pageName { guard let p = SettingsRoute.Page(rawValue: pageName) else { fail("unknown page \(pageName)") }; pages = [p] } else { pages = SettingsRoute.Page.allCases }
        if let tabName, SettingsRoute.Tab(rawValue: tabName) == nil { fail("unknown tab \(tabName)") }

        _ = NSApplication.shared
        let dir = URL(fileURLWithPath: out, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        let scheme: ColorScheme = light ? .light : .dark
        let suffix = "\(light ? "light" : "dark")\(appstore ? "-appstore" : "")\(stress ? "-stress" : "")\(state == "ready" ? "" : "-\(state)")"
        var shots: [(name: String, image: CGImage)] = []
        func draw<V: View>(_ name: String, _ view: V, width: Double) {
            let file = "\(name).png"
            shots.append((file, Shot.save(view: view, width: width, scheme: scheme, url: dir.appendingPathComponent(file))))
        }

        if kit {
            for w in [415.0, 720.0] { draw("kit-\(Int(w))-\(suffix)", KitSheet(windowWidth: w), width: w) }
        } else {
            for page in pages {
                let all = SettingsRoute.tabs(page)
                let tabs: [SettingsRoute.Tab?] = all.isEmpty ? [nil] : (tabName.flatMap { SettingsRoute.Tab(rawValue: $0) }.map { all.contains($0) ? [$0] : [] } ?? all)
                for tab in tabs {
                    for w in widths {
                        let sampleError = page == .chat ? "❌ That key was refused by OpenAI. Check it and save again."
                            : "❌ Sample error that is long enough to wrap onto a second line when the column is narrow."
                        let banner: String? = state == "error" ? sampleError : nil
                        let mode = SettingsLayout.sidebarMode(windowWidth: w)
                        let detailWidth = w - SettingsLayout.sidebarWidth(mode)
                        func pageView(_ p: SettingsRoute.Page) -> some View {
                            SettingsPage(page: p, tab: .constant(tab), banner: banner, scrolls: false) { SettingsSamples.page(p, tab: tab, state: state, stress: stress) }
                        }
                        // The shell fills its window, so the window's height is the page's natural height (at least the minimum): measure the page alone at the detail's width.
                        let natural = NSHostingController(rootView: pageView(page).environment(\.settingsMode, mode).frame(width: detailWidth))
                            .sizeThatFits(in: CGSize(width: detailWidth, height: 100_000)).height
                        let height = max(SettingsLayout.minHeight, natural.rounded(.up))
                        let name = "\(page.rawValue)\(tab.map { "-\($0.rawValue)" } ?? "")-\(Int(w))-\(suffix)"
                        let shell = SettingsShell(version: "1.0.0", icon: nil, page: .constant(page), scrolls: false) { pageView($0) }.frame(width: w, height: height)
                        draw(name, shell, width: w)
                    }
                }
            }
        }
        if !shots.isEmpty { ContactSheet.save(shots, dark: !light, url: dir.appendingPathComponent("sheet-\(suffix).png")) }
        print("drew \(shots.count) pictures")
    }
}
