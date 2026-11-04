import Foundation

// Source pins for the restyled Settings window, where no test program can compile the views (they need the whole app). Each says what a file must hold, so a missed rule fails here and not on
// the owner's screen. Later tasks add their sections above the @@WIRING-SECTIONS line. Run from the repository root through scripts/test-settings-wiring.sh.

@main
enum SettingsWiringTests {
    static func source(_ file: String) -> String { (try? String(contentsOfFile: "NotchBuddy/Sources/App/\(file)", encoding: .utf8)) ?? "" }
    static func count(_ needle: String, in text: String) -> Int { text.components(separatedBy: needle).count - 1 }
    static func at(_ needle: String, in text: String) -> String.Index? { text.range(of: needle)?.lowerBound }
    /// True when each needle occurs, each after the one before it.
    static func inOrder(_ needles: [String], in text: String) -> Bool {
        var from = text.startIndex
        for needle in needles {
            guard let found = text.range(of: needle, range: from..<text.endIndex) else { return false }
            from = found.upperBound
        }
        return true
    }
    /// The text from the first `start` up to the first `end` after it; empty when either is missing.
    static func between(_ text: String, _ start: String, _ end: String) -> String {
        guard let a = text.range(of: start), let b = text.range(of: end, range: a.upperBound..<text.endIndex) else { return "" }
        return String(text[a.lowerBound..<b.lowerBound])
    }

    /// The last compiler directive (#if !APPSTORE, #if APPSTORE, #else or #endif) above the first `needle` in `text`; nil when there is none or the needle is missing.
    static func directiveBefore(_ needle: String, in text: String) -> String? {
        guard let hit = text.range(of: needle) else { return nil }
        var best: (directive: String, at: String.Index)? = nil
        for directive in ["#if !APPSTORE", "#if APPSTORE", "#else", "#endif"] {
            guard let r = text.range(of: directive, options: .backwards, range: text.startIndex..<hit.lowerBound) else { continue }
            if best == nil || r.lowerBound > best!.at { best = (directive, r.lowerBound) }
        }
        return best?.directive
    }

    static let kitFiles = ["SettingsShell", "SettingsPage", "SettingsCard", "SettingRow", "SwitchRow", "KeyRow", "StatusChip", "WrapRow", "PathDisclosure", "HelpText", "SettingsTabBar", "SettingsBanner"]

    @MainActor static func main() {
        CT.section("the kit: twelve files, one view each")
        let kit = Dictionary(uniqueKeysWithValues: kitFiles.map { ($0, source("\($0).swift")) })
        for name in kitFiles { CT.checkTrue("\(name).swift is there and declares \(name)", (kit[name] ?? "").contains("struct \(name)")) }

        CT.section("the kit: nothing truncates, nothing is shortened")
        let wrap = kit["WrapRow"] ?? "", chip = kit["StatusChip"] ?? "", help = kit["HelpText"] ?? "", row = kit["SettingRow"] ?? "", tabs = kit["SettingsTabBar"] ?? ""
        CT.checkTrue("WrapRow is a custom Layout and fixes each child's size", wrap.contains(": Layout") && wrap.contains(".fixedSize()"))
        CT.checkTrue("StatusChip is fixedSize and has no line limit", chip.contains(".fixedSize()") && !chip.contains("lineLimit"))
        CT.checkTrue("HelpText uses the help colour and size and has no line limit", help.contains("SettingsColors.help") && help.contains("SettingsLayout.helpSize") && !help.contains("lineLimit"))
        CT.checkTrue("SettingRow chooses its layout with ViewThatFits", row.contains("ViewThatFits"))
        CT.checkTrue("SettingsTabBar is a ViewThatFits of text tabs and a Menu, never a segmented control", tabs.contains("ViewThatFits") && tabs.contains("Menu") && !tabs.contains(".segmented"))
        CT.checkTrue("no kit file has a line limit of one", kitFiles.allSatisfy { !(kit[$0] ?? "").contains("lineLimit") })

        CT.section("the kit: no segmented picker, no split view, and nothing that polls or listens")
        for banned in [".pickerStyle(.segmented)", "NavigationSplitView", "Timer", "asyncAfter", "DispatchSource", "onReceive"] {
            let hits = kitFiles.filter { (kit[$0] ?? "").contains(banned) }
            CT.checkTrue("no kit file contains \(banned)", hits.isEmpty)
        }

        CT.section("the shell: the width decides the sidebar, the minimum is the layout's")
        let shell = kit["SettingsShell"] ?? ""
        CT.checkTrue("SettingsShell asks the layout rule for the mode", shell.contains("SettingsLayout.sidebarMode(windowWidth:"))
        CT.checkTrue("and sets the window minimum from it", shell.contains("SettingsLayout.minWidth") && shell.contains("SettingsLayout.minHeight"))
        CT.checkTrue("and hands the mode down through the environment", shell.contains(".environment(\\.settingsMode, mode)") && shell.contains("var settingsMode: SettingsLayout.SidebarMode"))

        CT.section("General, Shortcuts and Devices (Task 5)")
        let general = source("SettingsGeneralPage.swift")
        CT.checkTrue("SettingsGeneralPage.swift is there and declares struct GeneralSettingsTab", general.contains("struct GeneralSettingsTab"))
        CT.checkTrue("the General tab has four cards, in the order Sound, Island, On the island, Startup", count("SettingsCard(", in: general) == 4
            && inOrder(["SettingsCard(\"Sound\")", "SettingsCard(\"Island\")", "SettingsCard(\"On the island\")", "SettingsCard(\"Startup\")"], in: general))
        CT.checkTrue("Hover glow is a switch with its help, bound to the model", general.contains("SwitchRow(\"Hover glow\", help:") && general.contains("isOn: model.hoverGlow"))
        CT.checkTrue("Open on hover is a switch with its help, bound to the model", general.contains("SwitchRow(\"Open on hover\", help:") && general.contains("isOn: model.openOnHover"))
        CT.checkTrue("the tuck-away row offers Never and 30 minutes as tags", general.contains("SettingRow(\"Tuck the island away\"") && general.contains(".tag(IslandTuckAway.Choice.never)") && general.contains(".tag(IslandTuckAway.Choice.m30)"))
        CT.checkTrue("Close after is a row with a number field and the word seconds", general.contains("SettingRow(\"Close after\")") && general.contains("\"seconds\""))
        CT.checkTrue("the General tab has no Hotkey card and no shortcut recorder (the shortcut is the Shortcuts tab's first row)", !general.contains("Hotkey") && !general.contains("ShortcutRecorderButton"))
        CT.checkTrue("the General tab has no GroupBox", !general.contains("GroupBox"))
        CT.checkTrue("the launch switch is bound to the model", general.contains("SwitchRow(\"Launch at Mac startup\"") && general.contains("isOn: model.launchAtStartup"))

        let shortcuts = source("ShortcutsSettingsView.swift")
        CT.checkTrue("Shortcuts: the global shortcuts and the island's list are cards", shortcuts.contains("SettingsCard(\"Global shortcuts\")") && shortcuts.contains("SettingsCard(\"In the island\")"))
        CT.checkTrue("Shortcuts: no GroupBox is left", !shortcuts.contains("GroupBox"))
        CT.checkTrue("Shortcuts: each action is a SettingRow named by the action, its controls in a WrapRow", shortcuts.contains("SettingRow(action.displayName") && shortcuts.contains("WrapRow {"))
        CT.checkTrue("Shortcuts: the island's list is two columns when expanded and stacked in icons mode", shortcuts.contains("@Environment(\\.settingsMode)") && shortcuts.contains("settingsMode == .expanded"))

        let devices = between(source("LinkViews.swift"), "struct DevicesSettingsView", "struct DevicesSettingsSection")
        CT.checkTrue("Devices: the three cards, in order: This Mac, Machines, Received files", inOrder(["SettingsCard(\"This Mac\")", "SettingsCard(\"Machines\")", "SettingsCard(\"Received files\")"], in: devices))
        CT.checkTrue("Devices: Forget and Keep are buttons inside a WrapRow", inOrder(["WrapRow {", "Button(\"Forget \\(row.name)?\")", "Button(\"Keep\")"], in: devices))
        CT.checkTrue("Devices: the machines show a StatusChip beside the name", devices.contains("StatusChip("))
        CT.checkTrue("Devices: no GroupBox is left", !devices.contains("GroupBox"))
        CT.checkTrue("Devices: the visible switch is a SwitchRow, the name field a capped SettingRow", devices.contains("SwitchRow(\"Visible on this network\"") && devices.contains("SettingRow(\"Name\")") && devices.contains("SettingsLayout.fieldMax"))
        CT.checkTrue("Devices: the machine name wraps between words (fixedSize, no fixed column)", devices.contains("Text(row.name).fixedSize(horizontal: false, vertical: true)"))
        let permission = devices.range(of: "Button(\"Local Network permission…\"").map { String(devices[..<$0.lowerBound]) } ?? ""
        CT.checkTrue("Devices: the Local Network permission button sits in a WrapRow, so it never truncates", permission.suffix(60).contains("WrapRow {"))

        CT.section("the page: the column is the layout's width rule, and one knob decides scrolling")
        let page = kit["SettingsPage"] ?? ""
        CT.checkTrue("SettingsPage takes the column maximum and the side padding from SettingsLayout", page.contains("SettingsLayout.columnMax") && page.contains("SettingsLayout.padding("))
        CT.checkTrue("scrolling is the scrolls parameter alone (no environment key)", !page.contains("settingsScrolls") && !shell.contains("settingsScrolls"))
        CT.checkTrue("the tab bar's menu names the selected tab only when it is one of the tabs", tabs.contains("tabs.contains($0)"))

        CT.section("Agents and Services (Task 6)")
        let agents = source("SettingsAgentsPage.swift")
        let services = source("SettingsServicesPage.swift")
        CT.checkTrue("SettingsAgentsPage.swift declares the page, the switch row and the models", ["struct AgentsSettingsPage", "struct PillSwitchRow", "enum HookKind", "struct HookCardModel", "struct PlanUsageModel", "struct AgentsSettingsModel", "struct AgentsSettingsActions", "struct PillSwitchModel"].allSatisfy { agents.contains($0) })
        CT.checkTrue("SettingsServicesPage.swift declares the page and the models", ["struct ServicesSettingsPage", "struct ServiceCardModel", "struct ServiceFieldModel", "struct ServiceFilterModel"].allSatisfy { services.contains($0) })
        CT.checkTrue("neither page uses a segmented picker", !agents.contains(".pickerStyle(.segmented)") && !services.contains(".pickerStyle(.segmented)"))
        let hookCard = between(agents, "func hookCard", "func planCard")
        let installButton = between(agents, "func installButton", "func planCard")
        let planCard = between(agents, "func planCard", "struct PillSwitchRow")
        CT.checkTrue("one install button per card: its title is Update hooks when an update is pending, else Install hooks; prominent only when no preview waits", inOrder(["let title = card.needsUpdate ? \"Update hooks\" : \"Install hooks\"", "if prominent && (card.needsUpdate || card.installed != true) {", ".borderedProminent", "} else {", ".bordered)"], in: installButton) && hookCard.contains("installButton(card, prominent: card.pendingJSON == nil)"))
        CT.checkTrue("the hook card has one Confirm & write and no install button of its own (the title comes from installButton)",!hookCard.contains("Button(\"Install hooks\")") && count("Button(\"Confirm & write\")", in: hookCard) == 1)
        CT.checkTrue("the plan card's Install relay is prominent only when no preview waits", planCard.contains("else if model.pendingJSON == nil") && planCard.contains("Button(\"Install relay\")"))
        let preview = (try? String(contentsOfFile: "NotchBuddy/Sources/App/SettingsLayout.swift", encoding: .utf8)) ?? ""
        CT.checkTrue("the pending preview goes through SettingsLayout.displayText (the home folder shows as ~), in the hook card and the plan card", hookCard.contains("PendingPreview(json: SettingsLayout.displayText(json, home: home)") && planCard.contains("PendingPreview(json: SettingsLayout.displayText(json, home: home)") && preview.contains("static func displayText(") && preview.contains("replacingOccurrences(of: home + \"/\", with: \"~/\")"))
        CT.checkTrue("hook card: Uninstall, then the note, then the JSON preview, then the path", inOrder(["Button(\"Uninstall\")", "if let note = card.note { HookNoteLine(note: note) }", "if let json = card.pendingJSON {", "PathDisclosure("], in: hookCard))
        CT.checkTrue("Confirm & write and Cancel sit inside a WrapRow (the hook card and the plan card each have one)", count("Button(\"Confirm & write\")", in: agents) == 2 && inOrder(["WrapRow {", "Button(\"Confirm & write\")", "Button(\"Cancel\")"], in: agents))
        CT.checkTrue("plan card: Install relay, then the note, then the heard line, then the JSON preview", inOrder(["Button(\"Install relay\")", "if let note = model.note { HookNoteLine(note: note) }", "if let heard = model.heard", "if let json = model.pendingJSON {"], in: planCard))
        CT.checkTrue("the plan switch reads model.showInNotch and its getter names nothing pending", planCard.contains("get: { model.showInNotch }") && !planCard.contains("get: { model.pending"))
        CT.checkTrue("the page's switch rows are PillSwitchRow, in a card titled Where you code (the spec's name), and Plan usage is its own card", agents.contains("PillSwitchRow(") && agents.contains("SettingsCard(\"Where you code\")") && !agents.contains("SettingsCard(\"On the island\")") && agents.contains("SettingsCard(\"Plan usage\""))
        let renderTool = (try? String(contentsOfFile: "scripts/render-settings.swift", encoding: .utf8)) ?? ""
        CT.checkTrue("the App Store sample offers only PillCatalog.available's pills (the agents' rows and the services' cards)", renderTool.contains("let offered = Set(PillCatalog.available.map(\\.id))") && renderTool.contains("pillRows.filter { offered.contains($0.id) }") && renderTool.contains("cards.filter { offered.contains($0.id) }"))
        CT.checkTrue("Services: the colour dot sits in each card's header (SettingsCard dot:), and its switch row has no dot of its own", services.contains("SettingsCard(card.name, summary: card.chip, dot: Color(hex: card.color))") && services.contains("dot: false"))
        CT.checkTrue("Services: the filter is a plain DisclosureGroup (closed by default): no startsOpen, no WatchFilter", !services.contains("startsOpen") && !services.contains("WatchFilter"))
        CT.checkTrue("the plan card's More disclosure holds the relay sentence", agents.contains("DisclosureGroup(\"More\")") && agents.contains("NotchMeow adds a status line relay to ~/.claude/settings.json."))
        CT.checkTrue("the Services card: the switch 'Show on the island' is first, then the fields, the help and the filter", inOrder(["Show on the island", "KeyRow(", "DisclosureGroup(\"Choose which to watch\""], in: services))
        CT.checkTrue("Services: save(card.id) occurs in the two branches of saveButton (prominent when dirty, disabled otherwise), and KeyRow takes no save argument", count("save(card.id)", in: services) == 2 && !between(services, "KeyRow(", "secure: field.secure)").contains("save:") && !between(services, "KeyRow(", "secure: field.secure)").isEmpty)
        CT.checkTrue("Services: the filter sits behind the disclosure and holds IntegrationFilterRow", services.contains("IntegrationFilterRow(") && services.contains("DisclosureGroup(\"Choose which to watch\""))
        let filterRow = between(source("SettingsView.swift"), "struct IntegrationFilterRow", "// MARK: - Shortcut recorder button")
        CT.checkTrue("IntegrationFilterRow lays its buttons in a WrapRow and has no mini control", filterRow.contains("WrapRow {") && !filterRow.contains(".controlSize(.mini)"))
        CT.checkTrue("IntegrationFilterRow: the count is help text, and the names wrap between words", filterRow.contains("HelpText(\"Watching") && filterRow.contains(".fixedSize(horizontal: false, vertical: true)"))

        CT.section("AI and chat: Your AI, Keys, Local models (Task 7)")
        let aiPage = source("SettingsAIPage.swift")
        let aiViews = source("AISettingsViews.swift")
        CT.checkTrue("SettingsAIPage.swift declares the three tabs and their models", ["struct YourAITab", "struct KeysTab", "struct LocalModelsTab", "struct YourAIModel", "struct AIRowModel", "struct ClaudePlanDetails", "struct KeyCardModel", "struct AnthropicModelPicker", "struct LocalModelsModel", "struct ServerRowModel", "struct AIFeatureRow", "struct AIChoiceSection", "struct AIPreferModel"].allSatisfy { aiPage.contains($0) })
        CT.checkTrue("Your AI has two cards, Which one answers first, then Choose your AI", inOrder(["SettingsCard(\"Which one answers\")", "SettingsCard(\"Choose your AI\")"], in: aiPage))
        CT.checkTrue("Make main is a plain button or a menu of the server's models", aiPage.contains("Button(\"Make main\")") && aiPage.contains("Menu(\"Make main\")"))
        CT.checkTrue("the Claude plan's controls sit in DisclosureGroup(\"Details\")", aiPage.contains("DisclosureGroup(\"Details\""))
        CT.checkTrue("an unavailable Make main says why in help text under the row", aiPage.contains("HelpText(reason)"))
        CT.checkTrue("Keys: one card per provider, the colour dot in the title row, one KeyRow passing works", aiPage.contains("SettingsCard(card.name, dot:") && aiPage.contains("works: card.works"))
        CT.checkTrue("Keys: KeyRow, then the Show on the island switch, then the help text", inOrder(["KeyRow(", "PillSwitchRow(pill: pill, label: \"Show on the island\"", "HelpText(card.help)"], in: aiPage))
        CT.checkTrue("Local models: one card, and Rescan and Add server… share a WrapRow", aiPage.contains("SettingsCard(\"Local models\")") && inOrder(["WrapRow {", "\"Rescan\"", "Button(\"Add server…\")"], in: aiPage))
        let beforeRescan = aiPage.range(of: "Button(model.rescanning").map { String(aiPage[..<$0.lowerBound]) } ?? ""
        CT.checkTrue("Rescan sits in a WrapRow: WrapRow { comes directly before its button", beforeRescan.trimmingCharacters(in: .whitespacesAndNewlines).hasSuffix("WrapRow {"))
        CT.checkTrue("Local models: a server with no models shows its note as help text under its row", aiPage.contains("if let note = server.note { HelpText(note) }"))
        CT.checkTrue("every picker row is a PickerRow: the fixed width is set once, inside PickerRow", count("frame(width: SettingsLayout.pickerWidth", in: aiPage) == 1 && count("PickerRow(", in: aiPage) >= 4)
        CT.checkTrue("a row shows its line (SettingRow's help, nil when there is none) and its reason (when there is one) as help text", aiPage.contains("SettingRow(row.title, help: row.line)") && aiPage.contains("if let reason = row.reason { HelpText(reason) }"))
        let render = (try? String(contentsOfFile: "scripts/render-settings.swift", encoding: .utf8)) ?? ""
        CT.checkTrue("the render's preference names Anthropic 'Claude API' with no plan too (spec)", render.contains("label: \"Claude API\"))"))
        CT.checkTrue("Local models: the add sheet is AddServerSheet with the page's closure", aiPage.contains("AddServerSheet(isPresented: $showAddServer, onAdd: addServer)"))
        CT.checkTrue("the page has no segmented picker, no Google plan, no ChatGPT, no Keychain, no Claude Code status or engine", !aiPage.contains(".pickerStyle(.segmented)") && !aiPage.contains("Use my Google plan") && !aiPage.contains("ChatGPT") && !aiPage.contains("KeychainStore") && !aiPage.contains("ClaudeCodeStatus") && !aiPage.contains("ClaudeCodeEngine") && !aiPage.contains("ConnectClaudePlanView"))
        CT.checkTrue("the page has no line limit: model ids and labels are never cut", !aiPage.contains("lineLimit"))
        CT.checkTrue("AISettingsViews.swift no longer holds LocalServerRow, and AddServerSheet stays", !aiViews.contains("struct LocalServerRow") && aiViews.contains("struct AddServerSheet"))
        CT.checkTrue("SettingsView's chat placeholder no longer names LocalServerRow", !source("SettingsView.swift").contains("LocalServerRow"))

        CT.section("Sidekick and Cat tabs in the kit (Task 8)")
        let sidekickPage = source("SidekickSettingsView.swift")
        let sidekickStruct = between(sidekickPage, "struct SidekickSettingsView: View", "struct SidekickSettingsSection")
        CT.checkTrue("the Sidekick tab's cards come in order: Notes, Quiet times, Where its words come from, Today so far, Muted notes", inOrder(["SettingsCard(\"Notes\")", "SettingsCard(\"Quiet times\"", "SettingsCard(\"Where its words come from\")", "SettingsCard(\"Today so far\"", "SettingsCard(\"Muted notes\")"], in: sidekickPage))
        CT.checkTrue("Show me an example draws the made-up sentence in the island note's card look, with no buttons", sidekickPage.contains("SettingsSidekick.example(") && sidekickPage.contains("CardBackground(wash: nil)") && sidekickPage.contains("SidekickView.title("))
        CT.checkTrue("the permission line is locked on and says why; jokes and moods come with F3a", sidekickPage.contains("SwitchRow(\"Permission line\", help: SettingsSidekick.permissionLine, isOn: .constant(true), disabled: true)") && sidekickPage.contains("SwitchRow(\"Jokes and moods\", isOn: .constant(false), chip: SettingsSidekick.comesWithF3a, disabled: true)"))
        CT.checkTrue("the view takes plain values: no shared store, no engine, no app state (the wrapper below it reads AppState as it did)", !sidekickStruct.contains("Sidekick.shared") && !sidekickStruct.contains("engine") && !sidekickStruct.contains("AppState"))
        CT.checkTrue("each F3a row carries its own chip: the three quiet times, jokes and moods, and Today so far", ["SwitchRow(\"Full-screen apps\", isOn: .constant(false), chip: SettingsSidekick.comesWithF3a, disabled: true)", "SwitchRow(\"Calls and screen sharing\", isOn: .constant(false), chip: SettingsSidekick.comesWithF3a, disabled: true)", "SwitchRow(\"Chosen hours\", isOn: .constant(false), chip: SettingsSidekick.comesWithF3a, disabled: true)", "StatusChip(SettingsSidekick.comesWithF3a)"].allSatisfy { sidekickPage.contains($0) })
        CT.checkTrue("the stuck switch is worked out once per body, and its chip reads that value", sidekickPage.contains("let stuck = SettingsSidekick.stuckSwitch(isMuted: store.settings.isMuted)") && sidekickPage.contains("chip: stuck.detail)"))
        CT.checkTrue("the view can open one example at first (the render tool's picture); the app opens none", sidekickPage.contains("example: String? = nil") && sidekickPage.contains("_shownExample = State(initialValue: example)"))
        CT.checkTrue("every switch of the Sidekick tab is a SwitchRow: no Toggle is left in the page", !sidekickPage.contains("Toggle("))
        CT.checkTrue("the Cat views and the Wardrobe card are SettingsCards with HelpText: no GroupBox is left", !source("CatSettingsView.swift").contains("GroupBox(") && !source("WardrobeSettingsView.swift").contains("GroupBox("))
        CT.checkTrue("Reset to defaults sits in a WrapRow", source("CatSettingsView.swift").contains("WrapRow {"))
        CT.checkTrue("CatSettingsSection takes a tab (nil draws every group, as today's call in SettingsView does) and passes it on", source("CatSettingsSection.swift").contains("var tab: SettingsRoute.Tab? = nil") && source("CatSettingsSection.swift").contains("tab: tab"))
        let catScript = (try? String(contentsOfFile: "scripts/render-cat-settings.sh", encoding: .utf8)) ?? ""
        CT.checkTrue("the cat picture compiles the kit files its page uses, before CatDisplayPreview", catScript.contains("$APP/SettingsRoute.swift $APP/SettingsLayout.swift $APP/SettingsStatus.swift $APP/SettingsColors.swift $APP/SettingsCard.swift $APP/SettingRow.swift $APP/SwitchRow.swift $APP/StatusChip.swift $APP/WrapRow.swift $APP/HelpText.swift $APP/CatDisplayPreview.swift"))
        let renderSidekick = (try? String(contentsOfFile: "scripts/render-sidekick.swift", encoding: .utf8)) ?? ""
        CT.checkTrue("the sidekick picture takes the Settings page's own height, not a fixed 470", renderSidekick.contains("sizeThatFits(in:") && !renderSidekick.contains("height = 470.0"))

        CT.section("App side A: the controller, the drafts and the builders (Task 10)")
        let controller = source("SettingsController.swift")
        let sections = source("SettingsSections.swift")
        let drafts = source("SettingsDrafts.swift")
        let moved = ["installHooks", "confirmInstall", "uninstallHooks", "installHooksAppStore", "uninstallHooksAppStore", "pickClaudeFolder", "triggerGeminiPreview", "confirmGeminiOp", "triggerAgyPreview", "confirmAgyOp", "triggerCodexPreview", "confirmCodexOp", "installStatusLine", "uninstallStatusLine", "confirmStatusLine", "loadVercelProjects", "loadN8nWorkflows", "fetchN8nWorkflows", "toggleStartup"]
        for name in moved {
            CT.checkTrue("SettingsController.swift declares func \(name)() once", count("func \(name)(", in: controller) == 1)
        }
        CT.checkTrue("saveService reads SettingsMap.serviceFields[pillId] and triggers the GitHub pulse", between(controller, "func saveService(", "func loadVercelProjects").contains("SettingsMap.serviceFields[pillId]") && between(controller, "func saveService(", "func loadVercelProjects").contains("GithubPoller.shared.triggerPulseNow()"))
        CT.checkTrue("the controller holds each pending JSON preview per kind", controller.contains("@Published var pending: [HookKind: String] = [:]"))
        CT.checkTrue("reveal opens the script or the settings file, copy writes the pasteboard", controller.contains("NSWorkspace.shared.activateFileViewerSelecting") && controller.contains("NSPasteboard.general.setString("))
        CT.checkTrue("SettingsSections is an enum of static builders with one pill-row builder", sections.contains("enum SettingsSections") && count("SettingsStatus.pillSwitch(", in: sections) == 1 && count("state.toggleIntegration(", in: sections) == 1)
        CT.checkTrue("the missing-prerequisite words each appear once, in the one builder", count("\"Key not configured\"", in: sections) == 1 && count("\"Not connected\"", in: sections) == 1)
        CT.checkTrue("General's bindings are AppState's own, through the observed wrapper: hoverGlow and tuckAway", sections.contains("hoverGlow: $state.hoverGlow") && sections.contains("tuckAway: $state.tuckAway"))
        CT.checkTrue("the main pill's setter keeps today's side effects (drop from the slots, load the tasks, focus)", sections.contains("state.activeIntegrations.remove(") && sections.contains("state.loadIntegrationTasks()") && sections.contains("state.setFocus("))
        CT.checkTrue("the Plan usage card reads the plan gauge's note from AppState", sections.contains("ClaudePlanGauge.statusNote(relayInstalled: state.planRelayInstalled, usage: state.claudePlanUsage)"))
        CT.checkTrue("the App Store build's Claude path is written out, and the GitHub build's path is the home-relative one", sections.contains("homeDirectoryForCurrentUser") && sections.contains("~/.claude/notchmeow/nm-hook"))
        CT.checkTrue("SettingsDrafts holds a SettingsDraftBook and seeds every field id in init", drafts.contains("SettingsDraftBook") && between(drafts, "init(read:", "func text(").contains("SettingsDraftBook(saved:"))
        let fieldIdsBody = between(drafts, "static let fieldIds", "@Published")
        CT.checkTrue("the field ids are the three AI keys (AICatalog's Keychain names) and every service field", fieldIdsBody.contains("[AIProviderID.anthropic, .google, .openai].map { AICatalog.info($0).keychainKey! }") && fieldIdsBody.contains("SettingsMap.serviceFields"))
        let installBody = between(controller, "func installHooks(", "func confirmInstall(")
        CT.checkTrue("installHooks only previews: its body never writes, the write is confirmInstall's after Confirm & write", !installBody.isEmpty && !installBody.contains("writeClaudeHooks("))
        CT.checkTrue("pills() filters every row through PillCatalog.available", between(sections, "static func pills(state:", "private static func missing(").contains("PillCatalog.available.first(where:"))

        CT.section("App side B: AI and chat, Make main, Sidekick and Cat (Task 11)")
        let aiBlock = between(controller, "// MARK: - AI and chat", "// MARK: - General, Devices")
        let saveKeyBody = between(controller, "func saveKey(_ provider", "func removeKey(")
        let removeKeyBody = between(controller, "func removeKey(", "func fetchModelsIfNeeded(")
        let setChatBody = between(controller, "func setChat(", "// MARK: - General, Devices")
        let yourAIBody = between(sections, "static func yourAI(", "static func keys(")
        let keysBody = between(sections, "static func keys(", "static func localModels(")
        let localBody = between(sections, "static func localModels(", "static func aiInput(")
        let inputBody = between(sections, "static func aiInput(", "static func claudeState(")
        let choiceBody = between(sections, "private static func choiceSections(", "private static func isListed(")
        CT.checkTrue("saveKey(_:drafts:) checks a pasted key with the model list and says why a call failed", saveKeyBody.contains("AIService.shared.listCloudModels(") && saveKeyBody.contains("AIMessages.listFailure("))
        CT.checkTrue("saveKey writes the trimmed draft, marks it saved, and no longer sets preferredCloud", saveKeyBody.contains("drafts.markSaved(") && saveKeyBody.contains("trimmingCharacters(in: .whitespacesAndNewlines)") && !saveKeyBody.contains("preferredCloud"))
        CT.checkTrue("removeKey is the same path with an empty value", removeKeyBody.contains("saveKey(provider, drafts: drafts)") && removeKeyBody.contains("= \"\""))
        CT.checkTrue("setChat is the one Make main setter: Chat only, never Files", setChatBody.contains("state.setChoice(setting, for: .chat)") && !setChatBody.contains(".files"))
        CT.checkTrue("the Claude plan's connect, stop and check are GitHub-only, behind #if !APPSTORE", inOrder(["#if !APPSTORE", "func connectClaude(", "func stopClaude(", "func checkClaude(", "AIService.shared.refreshClaudeStatus()", "#endif"], in: aiBlock))
        let stopBody = between(controller, "func stopClaude()", "/// \"Check again\"")
        CT.checkTrue("stopClaude resets Chat and File questions that named the plan, through SettingsAI.afterStoppingClaude", stopBody.contains("state.setChoice(SettingsAI.afterStoppingClaude(state.choice(for: .chat)), for: .chat)") && stopBody.contains("state.setChoice(SettingsAI.afterStoppingClaude(state.choice(for: .files)), for: .files)"))
        CT.checkTrue("the controller holds the AI page's published state and the fallback model list", ["@Published var keyWorks: [AIProviderID: Bool] = [:]", "@Published var fetchedModels: [(id: String, label: String)] = []", "@Published var modelChoice: String", "@Published var customModel: String", "@Published var showAddServer = false", "@Published var rescanning = false", "@Published var checkingClaude = false", "static let fallbackModels", "static let customModelTag = \"__custom__\""].allSatisfy { controller.contains($0) })
        CT.checkTrue("ClaudeChatViews.swift no longer holds ConnectClaudePlanView, and SettingsView's AI page no longer builds it", !source("ClaudeChatViews.swift").contains("ConnectClaudePlanView") && !source("SettingsView.swift").contains("ConnectClaudePlanView("))
        CT.checkTrue("Make main, the resolution line and the chooser rows come from the builders", sections.contains("SettingsAI.makeMain(") && sections.contains("SettingsAI.isMain(") && sections.contains("AIService.shared.resolutionLine("))
        CT.checkTrue("the Claude plan's details are GitHub-only: #if !APPSTORE before ClaudePlanDetails(", inOrder(["#if !APPSTORE", "ClaudePlanDetails(", "#endif"], in: yourAIBody))
        CT.checkTrue("the Claude plan's choice section is GitHub-only: #if !APPSTORE before id: \"plan\" and #endif after it, inside choiceSections", inOrder(["#if !APPSTORE", "id: \"plan\"", "#endif"], in: choiceBody) && count("id: \"plan\"", in: choiceBody) == 1)
        CT.checkTrue("aiInput maps ClaudeCodeStatus.State to SettingsAI.ClaudeState case for case, inside #if !APPSTORE", inOrder(["#if !APPSTORE", "claudeState(status.state)", "#endif"], in: inputBody) && inOrder(["#if !APPSTORE", "func claudeState(", "case .notInstalled: return .notInstalled", "case .signedIn: return .signedIn", "#endif"], in: sections))
        CT.checkTrue("the local servers' pills come from a provider table (Ollama, LM Studio), never from a display name", sections.contains("static let localPillIds") && sections.contains(".ollama: \"ai_ollama\"") && sections.contains(".lmstudio: \"ai_lmstudio\"") && localBody.contains("localPillIds[server.provider]"))
        CT.checkTrue("a server with no model keeps its makeMain words as its note", localBody.contains("SettingsAI.makeMain(.server("))
        CT.checkTrue("Keys: each card's switch comes from pills(state:ids:), its colour from ChatProvider's accent", keysBody.contains("pills(state: state, ids:") && keysBody.contains("ChatProvider(") && keysBody.contains(".accentHex"))
        CT.checkTrue("SidekickSettings' header says a kind's switch turned off in Settings mutes it at once", source("SidekickSettings.swift").contains("turning a kind's switch off in Settings mutes it at once (`mute`)"))

        CT.section("The swap: the shell, the window, the migration, the island's tags (Task 12)")
        let swapView = source("SettingsView.swift"), swapRoute = source("SettingsRoute.swift"), swapApp = source("AppDelegate.swift")
        let swapIsland = source("IslandViewContent.swift"), swapSections = source("SettingsSections.swift")
        CT.checkTrue("the shell migrates the stored section and writes the migrated tag back, and keeps the tab in its own state", swapView.contains("SettingsRoute.migrate(storedSection:") && swapView.contains("SettingsRoute.tabKey(") && swapView.contains("@State private var tab: SettingsRoute.Tab?"))
        CT.checkTrue("the page is the kit's: SettingsShell hosts SettingsPage, and a change of page or tab clears the banner", swapView.contains("SettingsShell(") && swapView.contains("SettingsPage(") && swapView.contains("controller.banner = \"\""))
        CT.checkTrue("the old shell is gone: no GroupBox, no status line, no old sections, no split view, no timer", ["GroupBox", "statusMessage", "activePillsSection", "integrationsSection", "NavigationSplitView", "Timer"].allSatisfy { !swapView.contains($0) })
        CT.checkTrue("the window opens at the layout's default size and its minimum is the layout's (not the old 640 by 420)", swapApp.contains("NSRect(x: 0, y: 0, width: SettingsLayout.defaultWidth, height: SettingsLayout.defaultHeight)") && swapApp.contains("win.contentMinSize = NSSize(width: SettingsLayout.minWidth, height: SettingsLayout.minHeight)") && !swapApp.contains("width: 640, height: 420"))
        CT.checkTrue("the sidebar's tags in the route: the six pages, and the old stored tags only in SettingsRoute.migrate", swapRoute.contains("case general, agents, chat, services, cat, devices") && swapRoute.contains("case \"activepills\": return Place(page: .general)"))
        CT.checkTrue("the island's default Settings link goes to Services, and the old Integrations tag is gone", swapIsland.contains("section = \"services\"") && !swapIsland.contains("section = \"integrations\""))
        CT.checkTrue("an AI pill's Settings link goes to its own tab: the switch reads SettingsMap.pillHome", swapIsland.contains("section = \"chat/\" + (SettingsMap.pillHome(task.id).tab?.rawValue ?? \"keys\")"))
        CT.checkTrue("the empty state's Add a cloud key opens chat/keys, Connect Claude opens chat/yourai (one each)", count("object: \"chat/keys\")", in: swapIsland) == 1 && count("object: \"chat/yourai\")", in: swapIsland) == 1)
        CT.checkTrue("the Settings… link of the island keeps the chat tag for the menu (perform .openSettings is unchanged)", swapIsland.contains("NotificationCenter.default.post(name: .openFullSettings, object: \"chat\")"))

        let arriveBody = between(swapView, "private func arrive() {", "@ViewBuilder private func content(")
        CT.checkTrue("arrive() asks for the models, runs discovery and asks Claude Code (that one only in the GitHub build)", arriveBody.contains("controller.fetchModelsIfNeeded()") && arriveBody.contains("AIService.shared.discover()") && inOrder(["#if !APPSTORE", "controller.checkClaude()", "#endif"], in: arriveBody))
        CT.checkTrue("settle() is the migration through select: one place writes the stored section and a page's tab", between(swapView, "private func settle() {", "private func loadTab(").contains("select(SettingsRoute.migrate(storedSection: storedSection))"))
        CT.checkTrue("SettingsSections.yourAI takes no openKeys: the YourAITab's own closure is the only one", !between(swapSections, "static func yourAI(", "static func keys(").contains("openKeys"))

        CT.section("The swap: every card of the controls map is on a page")
        let controlsURL = URL(fileURLWithPath: "tests/fixtures/settings/controls.json")
        let controlsJSON = (try? Data(contentsOf: controlsURL)).flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] } ?? [:]
        let controlRows = controlsJSON["controls"] as? [[String: Any]] ?? []
        var mapCards: [String] = []
        for row in controlRows {
            for home in row["homes"] as? [[String: Any]] ?? [] {
                if let card = home["card"] as? String, card != "(the shell)", !mapCards.contains(card) { mapCards.append(card) }
            }
        }
        let settingsFiles = ((try? FileManager.default.contentsOfDirectory(atPath: "NotchBuddy/Sources/App")) ?? []).filter { name in
            (name.hasPrefix("Settings") && name.hasSuffix(".swift"))
                || ["CatSettingsView.swift", "WardrobeSettingsView.swift", "SidekickSettingsView.swift", "ShortcutsSettingsView.swift", "LinkViews.swift"].contains(name)
        }.sorted()
        let settingsText = settingsFiles.map { source($0) }.joined(separator: "\n")
        // A group's name (Resend, n8n, … or Anthropic, Google AI, OpenAI) is checked name by name: each is a card's literal.
        let missingCards = mapCards.flatMap { $0.components(separatedBy: ", ") }.filter { !settingsText.contains("\"\($0)\"") }
        CT.checkTrue(missingCards.isEmpty ? "every card of controls.json is a string literal in a Settings file (\(mapCards.count) cards)" : "every card of controls.json is a string literal in a Settings file; missing: \(missingCards)",
                     !mapCards.isEmpty && missingCards.isEmpty)
        CT.checkTrue("the segmented picker is only in the Cat motion style (CatSettingsView.swift, once) and the Companion's Humor (SettingsCompanionPage.swift, once)", settingsFiles.filter { source($0).contains(".pickerStyle(.segmented)") } == ["CatSettingsView.swift", "SettingsCompanionPage.swift"] && count(".pickerStyle(.segmented)", in: source("CatSettingsView.swift")) == 1 && count(".pickerStyle(.segmented)", in: source("SettingsCompanionPage.swift")) == 1)

        CT.section("The swap: the App Store build's absences")
        CT.checkTrue("Gemini, Antigravity and Codex hook cards are inside #if !APPSTORE in SettingsSections.swift", ["\"Gemini CLI hooks\"", "\"Antigravity hooks\"", "\"Codex hooks\""].allSatisfy { directiveBefore($0, in: swapSections) == "#if !APPSTORE" })
        CT.checkTrue("Claude Code's hook card is in both builds: no guard above it", directiveBefore("\"Claude Code hooks\"", in: swapSections) != "#if !APPSTORE")
        let planModel = between(swapSections, "private static func planCard(", "// MARK: - Services")
        CT.checkTrue("the Plan usage card is built only in the GitHub build: planCard returns nil under APPSTORE", inOrder(["#if APPSTORE", "return nil", "#else", "PlanUsageModel("], in: planModel))
        CT.checkTrue("the Plan usage card's title is on the Agents page, which draws it only when the model has one", source("SettingsAgentsPage.swift").contains("SettingsCard(\"Plan usage\"") && swapView.contains("AgentsSettingsPage(model:"))

        CT.section("Final fix round: the Keychain's answer is shown, and a refused write is never 'saved'")
        let keychainSource = source("ClaudeService.swift")
        let keychainSave = between(keychainSource, "static func save(key: String, value: String)", "static func load(key:")
        let keychainSet = between(keychainSource, "/// Updates cache + persists to Keychain.", "/// Loads keys only known")
        CT.checkTrue("Keychain.save returns whether the Keychain took the value, written in place by KeychainWrite", inOrder(["static func save(key: String, value: String) -> Bool", "else { return false }", "return KeychainWrite.save(service: service, account: key, data: data)"], in: keychainSave))
        CT.checkTrue("KeychainStore.set is @discardableResult, returns a Bool, and caches only what the Keychain took", inOrder(["@discardableResult", "func set(_ key: String, value: String) -> Bool", "guard Keychain.save(key: key, value: value) else { return false }", "lock.withLock { cache[key] = value }", "return true"], in: keychainSet))
        CT.checkTrue("the controller's three Keychain writers each say so when refused, and each call site reads the result", count("\"❌ Couldn't save to the Keychain.\"", in: controller) == 3 && count("KeychainStore.shared.set(", in: controller) == 3)
        let saveKeyHelper = between(controller, "private func saveKey(_ key: String, value: String) -> Bool", "// MARK: - Vercel project list")
        CT.checkTrue("the Keychain helper returns the write's or the removal's result (an empty value removes the item)", inOrder(["if value.isEmpty { return KeychainStore.shared.remove(key) }", "return KeychainStore.shared.set(key, value: value)"], in: saveKeyHelper))
        let saveServiceBody = between(controller, "func saveService(", "private static func keychainBanner")
        CT.checkTrue("saveService marks a field saved only after the Keychain took it, and names a refused write or removal", inOrder(["guard saveKey(\"github-token\", value: value) else { failure = Self.keychainBanner(value); continue }", "drafts.markSaved(id, stored: value)"], in: saveServiceBody) && inOrder(["guard saveKey(id, value: value) else { failure = Self.keychainBanner(value); continue }", "drafts.markSaved(id, stored: value)"], in: saveServiceBody) && saveServiceBody.contains("banner = failure ?? "))
        let keychainBannerBody = between(controller, "private static func keychainBanner(_ value: String) -> String {", "/// Writes one Keychain field")
        CT.checkTrue("keychainBanner says 'remove' for an empty value and 'save' otherwise", inOrder(["value.isEmpty ? \"❌ Couldn't remove from the Keychain.\" : \"❌ Couldn't save to the Keychain.\""], in: keychainBannerBody))
        CT.checkTrue("saveService marks exactly the value it wrote (untrimmed, as the old saveIntegrations did)", saveServiceBody.contains("let value = drafts.book.text(id)") && !saveServiceBody.contains("trimmingCharacters"))
        let aiSaveBody = between(controller, "func saveKey(_ provider: AIProviderID, drafts: SettingsDrafts) {", "func removeKey(")
        let aiRemoveBody = between(controller, "func removeKey(", "func fetchModelsIfNeeded()")
        CT.checkTrue("saveKey: a refused write says so, marks nothing saved and runs no model check", inOrder(["else if !KeychainStore.shared.set(fieldId, value: key) {", "banner = \"❌ Couldn't save to the Keychain.\"", "return", "drafts.markSaved(fieldId, stored: key)", "AIService.shared.listCloudModels("], in: aiSaveBody))
        let addBody = between(controller, "func addServer(", "/// Rescan:")
        CT.checkTrue("addServer: a refused key write says so, adds no server and runs no discovery", inOrder(["!KeychainStore.shared.set(server.keychainAccount, value: key)", "banner = \"❌ Couldn't save to the Keychain.\"", "return", "state.customServers.append(server)", "AIService.shared.discover()"], in: addBody))

        CT.section("Final fix round: removing a key deletes it; the model list follows the key")
        CT.checkTrue("saveKey: an empty key removes the Keychain item, as saveService does (removeKey goes through it)", inOrder(["if key.isEmpty {", "KeychainStore.shared.remove(fieldId)"], in: aiSaveBody) && aiRemoveBody.contains("saveKey(provider, drafts: drafts)"))
        CT.checkTrue("saveKey: a refused removal says so ('Couldn't remove'), leaves the mark and the model check alone", inOrder(["guard KeychainStore.shared.remove(fieldId) else {", "banner = \"❌ Couldn't remove from the Keychain.\"", "return", "} else if !KeychainStore.shared.set(fieldId, value: key) {", "drafts.markSaved(fieldId, stored: key)"], in: aiSaveBody))
        let removeServerBody = between(controller, "func removeServer(_ id: String) {", "/// The Add server sheet's")
        CT.checkTrue("removeServer keeps a server listed until the Keychain has let go of its key, and says so when it refuses", inOrder(["guard KeychainStore.shared.remove(server.keychainAccount) else {", "banner = \"❌ Couldn't remove from the Keychain.\"", "return", "state.customServers.removeAll"], in: removeServerBody))
        CT.checkTrue("removeKey clears the draft and goes through saveKey, with a guard instead of a force unwrap", inOrder(["guard let fieldId = AICatalog.info(provider).keychainKey else { return }", "drafts.text(fieldId).wrappedValue = \"\"", "saveKey(provider, drafts: drafts)"], in: aiRemoveBody))
        CT.checkTrue("saveKey and removeKey have no force unwrap of keychainKey, and the controller has none at all", !aiSaveBody.contains("keychainKey!") && !aiRemoveBody.contains("keychainKey!") && count("keychainKey!", in: controller) == 0 && aiSaveBody.contains("guard let fieldId = AICatalog.info(provider).keychainKey else { return }"))
        CT.checkTrue("saveKey clears the Anthropic model list and fetches it again, so a removed key's models never stay", inOrder(["if provider == .anthropic {", "fetchedModels = []", "fetchModelsIfNeeded()"], in: aiSaveBody))

        CT.section("Final fix round: a failed status-line preview leaves nothing to confirm")
        let statusLineInstall = between(controller, "func installStatusLine()", "func uninstallStatusLine()")
        CT.checkTrue("installStatusLine's catch clears the pending JSON and hides the diff, so Confirm can never write an older preview", inOrder(["} catch {", "pendingStatusLineJSON = \"\"", "showStatusLineDiff = false"], in: statusLineInstall))

        CT.section("Final fix round: one model-list request on open, the drafts only on Save")
        let onAppear = between(swapView, ".onAppear {", ".onChange(of: storedSection)")
        CT.checkTrue("the page's onAppear asks for no models: arrive() does it, once per arrival", !onAppear.contains("fetchModelsIfNeeded") && count("controller.fetchModelsIfNeeded()", in: swapView) == 1 && arriveBody.contains("controller.fetchModelsIfNeeded()"))
        CT.checkTrue("SettingsView holds exactly one SettingsDrafts, as @StateObject private var drafts", count("SettingsDrafts(", in: swapView) == 1 && swapView.contains("@StateObject private var drafts = SettingsDrafts("))
        let settleBody = between(swapView, "private func settle() {", "private func loadTab(")
        let loadTabBody = between(swapView, "private func loadTab(", "/// A link to a place")
        let selectBody = between(swapView, "private func select(", "/// The tab a page shows")
        for (name, body) in [("settle", settleBody), ("loadTab", loadTabBody), ("select", selectBody), ("arrive", arriveBody)] {
            CT.checkTrue("\(name) never saves a draft (no save, markSaved or KeychainStore in its body)", !body.isEmpty && !body.contains("save") && !body.contains("markSaved") && !body.contains("KeychainStore"))
        }

        CT.section("Final fix round: Make main sets Chat only; the hook previews write only on Confirm")
        CT.checkTrue("setChoice is called in SettingsSections.swift only by the feature chooser's binding", count("setChoice(", in: sections) == 1 && sections.contains("set: { state.setChoice($0, for: feature) }"))
        CT.checkTrue("SettingsAIPage calls no setChoice: its Make main buttons call setChat", !aiPage.contains("setChoice(") && aiPage.contains("Button(\"Make main\") { setChat(setting) }") && aiPage.contains("Button(refs[i].model) { setChat(.explicit(refs[i])) }"))
        let geminiPreview = between(controller, "func triggerGeminiPreview(", "func confirmGeminiOp(")
        let agyPreview = between(controller, "func triggerAgyPreview(", "func confirmAgyOp(")
        let codexPreview = between(controller, "func triggerCodexPreview(", "func confirmCodexOp(")
        for (name, body) in [("triggerGeminiPreview", geminiPreview), ("triggerAgyPreview", agyPreview), ("triggerCodexPreview", codexPreview)] {
            CT.checkTrue("\(name) only previews: no HookServer.shared.write in its body", !body.isEmpty && !body.contains("HookServer.shared.write"))
        }
        CT.checkTrue("confirmGeminiOp writes, then clears the pending JSON, then says it is done", inOrder(["HookServer.shared.writeGeminiHooks()", "pending[.gemini] = nil", "banner = geminiPendingInstall"], in: between(controller, "func confirmGeminiOp(", "func triggerAgyPreview(")))
        CT.checkTrue("confirmAgyOp writes, then clears the pending JSON, then says it is done", inOrder(["HookServer.shared.writeAgyHooks()", "pending[.antigravity] = nil", "banner = agyPendingInstall"], in: between(controller, "func confirmAgyOp(", "func triggerCodexPreview(")))
        CT.checkTrue("confirmCodexOp writes, then clears the pending JSON, then says it is done", inOrder(["HookServer.shared.writeCodexHooks()", "pending[.codex] = nil", "banner = codexPendingInstall"], in: between(controller, "func confirmCodexOp(", "// MARK: - Plan usage")))
        CT.checkTrue("confirmInstall (Claude Code) writes, then clears the pending JSON, then says it is done", inOrder(["HookServer.shared.writeClaudeHooks()", "pending[.claude] = nil", "claudeNote = HookInstallNote.installed"], in: between(controller, "func confirmInstall(", "func uninstallHooks(")))
        let hookPreviewBranch = between(agents, "if let json = card.pendingJSON {", "PathDisclosure(path: card.path")
        CT.checkTrue("the hook card's Confirm & write sits inside its pending-JSON branch", hookPreviewBranch.contains("Button(\"Confirm & write\") { actions.confirm(card.kind) }"))

        CT.section("Final fix round: the #if branches balance")
        for (name, text) in [("SettingsController.swift", controller), ("SettingsSections.swift", sections)] {
            CT.checkTrue("\(name): every #if has its #endif", count("#if ", in: text) > 0 && count("#if ", in: text) == count("#endif", in: text))
        }

        CT.section("Final fix round: the stale names")
        CT.checkTrue("SidekickSettingsView names the Sidekick tab by its page and tab, and the old name is gone", count("Settings → AI and chat → Sidekick", in: sidekickPage) == 2 && !sidekickPage.contains("Settings → Sidekick"))
        let docsAgents = (try? String(contentsOfFile: "docs/AGENTS.md", encoding: .utf8)) ?? ""
        CT.checkTrue("docs/AGENTS.md names the pill switches on the three pages, not the old Active pills list", count("the pill switches on the Agents, AI and chat and Services pages", in: docsAgents) == 2 && !docsAgents.contains("Settings → Active pills"))

        CT.section("Polish round from the real window (checkpoint 2): Save, the install button, Cancel, the cat rows, the key caps, the notes, the intro")
        let keyRowSource = source("KeyRow.swift")
        let servicesPage = source("SettingsServicesPage.swift")
        let sectionsSource = source("SettingsSections.swift")
        let catSource = source("CatSettingsView.swift")
        let settingsViewSource = source("SettingsView.swift")
        let sidekickView = source("SidekickSettingsView.swift")
        let controllerSource = source("SettingsController.swift")
        // 1. Save is lit only when the card has something to save.
        CT.checkTrue("polish 1: KeyRow's Save is prominent only while the text differs from what is stored, and disabled otherwise", inOrder(["@ViewBuilder private func saveButton", "if dirty {", "Button(\"Save\", action: save).buttonStyle(.borderedProminent)", "} else {", "Button(\"Save\", action: save).buttonStyle(.bordered).disabled(true)"], in: keyRowSource) && keyRowSource.contains("if let save { saveButton(save) }"))
        CT.checkTrue("polish 1: a Services card's Save is prominent only while one of its fields differs from what is stored", servicesPage.contains("saveButton(card, dirty: card.fields.contains { dirty($0.id) })") && inOrder(["@ViewBuilder private func saveButton", "if dirty {", "Button(\"Save\") { save(card.id) }.buttonStyle(.borderedProminent)", "} else {", "Button(\"Save\") { save(card.id) }.buttonStyle(.bordered).disabled(true)"], in: servicesPage))
        // 2. Install hooks is plain once the hooks are installed.
        CT.checkTrue("polish 2: HookCardModel carries whether the hooks are installed (nil when the state is not known)", source("SettingsAgentsPage.swift").contains("var installed: Bool?"))
        CT.checkTrue("polish 2: the Claude and the other cards pass their installed state into the model", sectionsSource.contains("installed: claudeInstalled") && sectionsSource.contains("installed: installed"))
        CT.checkTrue("polish 2: a card's install button is prominent only when its hooks are missing or outdated", source("SettingsAgentsPage.swift").contains("card.installed != true"))
        // 3. Cancel clears the preview's own prompt, and nothing else.
        let cancelBody = between(controllerSource, "func cancel(_ k: HookKind)", "private func dropPreviewPrompt()")
        let dropBody = between(controllerSource, "private func dropPreviewPrompt()", "// MARK: - Claude Code hooks")
        CT.checkTrue("polish 3: cancel(_:) drops the preview's prompt once the kind's preview is gone", cancelBody.contains("pending[k] = nil") && cancelBody.contains("dropPreviewPrompt()"))
        CT.checkTrue("polish 3: the plan relay's cancel drops the prompt too", between(controllerSource, "func cancelRelay()", "func installStatusLine()").contains("dropPreviewPrompt()"))
        CT.checkTrue("polish 3: dropPreviewPrompt clears only the preview prompt, and only when no other preview waits", inOrder(["#if !APPSTORE", "relayWaits = showStatusLineDiff", "#endif", "banner == \"Review the JSON below before confirming.\"", "pending.isEmpty", "&& !relayWaits { banner = \"\" }"], in: dropBody))
        // 4. The per-cat pickers sit on the card's leading edge, like every other control.
        let motionGroup = between(catSource, "private var motionGroup", "// MARK: Personality")
        let lookGroup = between(catSource, "private var lookGroup", "// MARK: Apply to every cat")
        CT.checkTrue("polish 4: This cat's motion is a SettingRow with the cat's name as its help, and no HStack beside the pop-up", motionGroup.contains("SettingRow(\"This cat's motion\", help: label)") && !motionGroup.contains("HStack") && motionGroup.contains(".frame(width: 180)"))
        CT.checkTrue("polish 4: This cat's collar is a SettingRow with the cat's name as its help, and no HStack beside the pop-up", lookGroup.contains("SettingRow(\"This cat's collar\", help: label)") && !lookGroup.contains("HStack") && lookGroup.contains(".frame(width: 180)"))
        // 5. Every switch of the shortcut list lines up: the key cap has one minimum width.
        let recorder = between(settingsViewSource, "struct ShortcutRecorderButton", "private func record(")
        CT.checkTrue("polish 5: the key cap's label has a minimum width of 64 pt (fits ^⌥Space at 47.6 pt plus 16 pt of padding), after its padding and before its background", inOrder([".padding(.horizontal, 8).padding(.vertical, 3)", ".frame(minWidth: 64)", ".background("], in: recorder))
        // 6. A server that is not installed shows only its Get link.
        let localModelsBody = between(sectionsSource, "static func localModels(", "static func aiInput(")
        CT.checkTrue("polish 6: the start-the-server words are set only for an installed server (SettingsAI.makeMain's words, unchanged)", localModelsBody.contains("if case .unavailable(let reason) = SettingsAI.makeMain(.server(server.serverID), input), server.status != .notInstalled { note = reason }"))
        // 7. The Sidekick example is as tall as its content, with a small minimum.
        CT.checkTrue("polish 7: the example box has no fixed height (its minimum is 56 pt, its height is its content's)", sidekickView.contains(".frame(maxWidth: .infinity, minHeight: 56, alignment: .topLeading)") && !sidekickView.contains("maxHeight: 98") && !sidekickView.contains("minHeight: 98"))
        // @@WIRING-SECTIONS
        CT.finish()
    }
}
