import Foundation

// Source pins for the Projects hook path and the session's jump (P-mac, Task 8), where no test program can compile the app's files. Each says where the registry is
// fed (once per Claude Code hook, before the gate or the answer "ask" that would otherwise return first), that the app's model is wired once and on the real
// home, that the jump is a new route beside the pill's, and that no view or controller reads the registry or a path. Run from the repository root through
// scripts/test-projects-wiring.sh.
//
// Fix wave 2: every pin reads the app's source through `source`, which is the file's code with its comments removed (tests/SourceScan.swift), so a commented-out feed,
// sink or modifier fails its pin; `raw` is the file as written, for the few pins that are about a comment's words. A pin that reads a type takes it with
// `typeText` (its declaration to the closing brace at column 0) and fails when the type is not there, so it cannot overshoot into the next type or fall short of a
// grown one. The last section changes the real sources in memory (a line commented out, a value hard-coded, a pause removed) and asserts the same pins then fail.

@main
enum ProjectsWiringTests {
    static let appDir = "NotchBuddy/Sources/App"
    @MainActor private static var rawCache: [String: String] = [:]
    @MainActor private static var codeCache: [String: String] = [:]

    /// The file as written. An unreadable or empty file fails the run (a pin over "" would otherwise pass or fail by accident) and reads as "".
    @MainActor static func raw(_ file: String) -> String {
        if let hit = rawCache[file] { return hit }
        let text = (try? String(contentsOfFile: "\(appDir)/\(file)", encoding: .utf8)) ?? ""
        if text.isEmpty { CT.checkTrue("\(appDir)/\(file) is readable and not empty", false) }
        rawCache[file] = text
        return text
    }
    /// The file's code: its comments removed. A file the scanner loses its place in (it ends inside a string) fails the run.
    @MainActor static func source(_ file: String) -> String {
        if let hit = codeCache[file] { return hit }
        let scanned = SourceScan.scan(raw(file))
        if !scanned.balanced { CT.checkTrue("\(appDir)/\(file) ends outside any string literal (the comment scanner kept its place)", false) }
        codeCache[file] = scanned.code
        return scanned.code
    }
    /// A type's text in `text` (see `SourceScan.structText`); a type that is not found or never closes fails the run.
    @MainActor static func typeText(_ decl: String, in text: String) -> String {
        guard let found = SourceScan.structText(decl, in: text) else {
            CT.checkTrue("\(decl) is there and closes with a brace at column 0", false)
            return ""
        }
        return found
    }
    /// A modifier chain (see `SourceScan.chain`); one that is not found fails the run.
    @MainActor static func chain(_ needle: String, in text: String) -> String {
        guard let found = SourceScan.chain(needle, in: text) else {
            CT.checkTrue("\(needle) is there", false)
            return ""
        }
        return found
    }
    static func count(_ needle: String, in text: String) -> Int { text.components(separatedBy: needle).count - 1 }
    /// The offset of the first `needle`, or -1.
    static func at(_ needle: String, in text: String) -> Int { text.range(of: needle)?.lowerBound.utf16Offset(in: text) ?? -1 }
    /// The offset of the first `needle` at or after `from`, or -1.
    static func at(_ needle: String, in text: String, from: Int) -> Int { from < 0 ? -1 : text.range(of: needle, range: String.Index(utf16Offset: from, in: text)..<text.endIndex)?.lowerBound.utf16Offset(in: text) ?? -1 }
    /// The text from the UTF-16 offset `start` to the end of `text`, or "" when `start` is not inside it.
    static func tail(_ text: String, from start: Int) -> String {
        let units = Array(text.utf16)
        guard start >= 0, start < units.count else { return "" }
        return String(decoding: units[start...], as: UTF16.self)
    }
    /// The lines of `text` that are exactly `line`, counted.
    static func lines(_ text: String, equal line: String) -> Int { text.components(separatedBy: "\n").filter { $0 == line }.count }
    /// A function's text: from its first line to the first line that is exactly a four-space closing brace (every function pinned here is a member at that depth).
    static func body(_ start: String, in text: String) -> String {
        let at0 = at(start, in: text)
        guard at0 >= 0 else { return "" }
        let rest = tail(text, from: at0), end = at("\n    }\n", in: rest)
        return end > 0 ? String(rest.prefix(end)) : rest
    }

    // MARK: pins that the negative controls also run on changed copies of the real sources

    typealias Pin = (label: String, holds: Bool)

    static let feedLine = "ProjectsModel.shared.feedFromHook(payload: payload, waitIn: waitIn)"

    /// The hook server's feed pins over its code: three feeds, one per handler, each after the chat's own run is filtered out and before what would return first.
    static func feedPins(_ hooks: String) -> [Pin] {
        let procEvent = at("private func processEvent(name: String, payload: [String: Any]) {", in: hooks)
        let procPerm = at("private func processPermissionRequest(fd: Int32, payload: [String: Any]) {", in: hooks)
        let procQ = at("private func processQuestionRequest(fd: Int32, parsed: AskQuestion, payload: [String: Any]) {", in: hooks)
        let gate = at("if let pending = state.pendingApproval, agentId == pending.pillId {", in: hooks, from: procEvent)
        let routeE = at("ClaudeHookRouting.route(payload: payload", in: hooks, from: procEvent)
        let feedE = at(feedLine, in: hooks, from: procEvent)
        let answersP = at("if HookOrigin.answersAskAtOnce(route: route, rawAgent: rawAgent) {", in: hooks, from: procPerm)
        let routeP = at("ClaudeHookRouting.route(payload: payload", in: hooks, from: procPerm)
        let feedP = at(feedLine, in: hooks, from: procPerm)
        let answersQ = at("if HookOrigin.answersAskAtOnce(route: route, rawAgent: rawAgent) {", in: hooks, from: procQ)
        let routeQ = at("ClaudeHookRouting.route(payload: payload", in: hooks, from: procQ)
        let feedQ = at(feedLine, in: hooks, from: procQ)
        return [
            ("three feeds: an event, a permission request and a question", count(feedLine, in: hooks) == 3),
            ("the three handlers are there, in this order", procEvent > 0 && procPerm > procEvent && procQ > procPerm),
            ("in processEvent the feed comes after the chat's own run is filtered out, and before the pending-approval gate",
             routeE > procEvent && feedE > routeE && gate > feedE && gate < procPerm),
            ("in processPermissionRequest the feed comes after the chat's filter and before the 'ask' at once, so a Claude App request is counted",
             routeP > procPerm && feedP > routeP && answersP > feedP && answersP < procQ),
            ("in processQuestionRequest the feed comes after the chat's filter and before the 'ask' at once",
             routeQ > procQ && feedQ > routeQ && answersQ > feedQ),
        ]
    }

    /// The app model's sink and layout pins over its code (ProjectsModel+App.swift): the sinks on the island, and the one place the layout's inputs are read.
    static func modelPins(_ model: String) -> [Pin] {
        let modeSink = SourceScan.block(from: "subscriptions.insert(app.$mode.sink { mode in", to: "\n        })\n", in: model) ?? ""
        let refreshAt = at("model.refreshFromApp {", in: modeSink), expandedAt = at("model.islandExpanded(mode == .expanded)", in: modeSink)
        let refresh = body("fileprivate func refreshFromApp(", in: model)
        let refreshCalls = model.components(separatedBy: "\n").filter { $0.contains("refreshLayout(") }
        return [
            ("the sinks take the new value (the stored one is written after willSet): the mode, then the focus",
             !modeSink.isEmpty && model.contains("subscriptions.insert(app.$focusId.sink { focus in") && model.contains("model.refreshFromApp { $0.focusId = focus }")),
            ("the mode sink reads the layout BEFORE it tells the model the island is expanded (the island reads its height on the mode change, and the tick arms after)",
             modeSink.contains("model.refreshFromApp { $0.expanded = mode == .expanded }") && refreshAt > 0 && expandedAt > refreshAt),
            ("the mode sink does that with the island's own mode, and touches nothing else (no Two cats value, no literal)",
             modeSink.contains("{ mode in\n            model.refreshFromApp { $0.expanded = mode == .expanded }\n            model.islandExpanded(mode == .expanded)\n        })")
                && !modeSink.contains("twoCats") && count("model.islandExpanded(", in: model) == 1),
            ("the active integrations and the main pill have sinks too (toggling an agent pill while folded must not leave a stale layout), each passing its new value",
             model.contains("subscriptions.insert(app.$activeIntegrations.sink { ids in\n            model.refreshFromApp { $0.activeIntegrations = ids }")
                && model.contains("subscriptions.insert(app.$mainPillId.sink { pill in\n            model.refreshFromApp { $0.mainPillId = pill }")),
            ("the app's side has ONE refresh, which reads every input fresh (the pills' expression is written once) and passes Two cats",
             refreshCalls.count == 1 && refreshCalls[0].contains("twoCats: i.twoCats") && count("activeIntegrations.sorted()", in: model) == 1),
            ("Two cats comes from the display mode where the inputs are read, once, and nowhere is it a literal",
             refresh.contains("twoCats: CatSettingsStore.shared.display.mode == .two)") && count("CatSettingsStore.shared.display.mode == .two", in: model) == 1
                && !model.contains("twoCats: false") && !model.contains("twoCats: true") && !model.contains(".twoCats = false") && !model.contains(".twoCats = true")),
            ("the model is told when the display mode changes, with the new value (the stored one is written after the publisher fires)",
             model.contains("subscriptions.insert(CatSettingsStore.shared.$display.sink { display in\n            model.refreshFromApp { $0.twoCats = display.mode == .two }\n        })")),
        ]
    }

    /// The `TimelineView`s of the Projects files (name to code): how many there are, and any whose argument list does not pause on `active` or `animate`.
    static func timelineProblems(_ files: [String: String], expected: Int) -> [String] {
        var out: [String] = []
        var total = 0
        for (name, code) in files.sorted(by: { $0.key < $1.key }) {
            for args in SourceScan.timelineViews(in: code) {
                total += 1
                guard let r = args.range(of: "paused:") else { out.append("\(name): TimelineView(\(args)) has no paused:"); continue }
                let expr = args[r.upperBound...]
                if !(expr.contains("active") || expr.contains("animate")) { out.append("\(name): TimelineView(\(args)) pauses on neither active nor animate") }
            }
        }
        if total != expected { out.append("\(total) TimelineViews, expected \(expected)") }
        return out
    }

    /// What no Projects file's code may hold: a timer object, a repeating animation, a sleep, a log, print, UserDefaults or the GitHub build's flag.
    static let projectBans = ["Timer", "onReceive(Timer", "repeatForever", "Task.sleep", "appendAppLog", "nbLog", "print(", "UserDefaults", "#if !APPSTORE"]
    static func bannedHits(_ code: String) -> [String] { projectBans.filter { code.contains($0) } }

    /// `text` with the `nth` (0-based) line that contains `needle` commented out.
    static func commentedOut(_ text: String, _ needle: String, nth: Int = 0) -> String {
        var seen = 0
        return text.components(separatedBy: "\n").map { line -> String in
            guard line.contains(needle) else { return line }
            defer { seen += 1 }
            return seen == nth ? "// " + line : line
        }.joined(separator: "\n")
    }
    /// `text` with the first `old` replaced by `new` (a control that does not change anything is a broken control, so callers assert `changed`).
    static func replaced(_ text: String, _ old: String, _ new: String) -> String {
        guard let r = text.range(of: old) else { return text }
        return text.replacingCharacters(in: r, with: new)
    }

    @MainActor static func main() {
        let hooks = source("HookServer.swift"), state = source("AppState.swift"), target = source("AgentTarget.swift"), model = source("ProjectsModel+App.swift")
        CT.section("the sources were read")
        CT.checkTrue("the files are there", hooks.contains("final class HookServer") && state.contains("final class AppState") && target.contains("enum AgentTarget") && model.contains("extension ProjectsModel"))

        CT.section("the registry is fed from every Claude Code hook, once each, through the app's model")
        for pin in feedPins(hooks) { CT.checkTrue(pin.label, pin.holds) }

        CT.section("the question remembers its session, beside its pill")
        CT.checkTrue("processQuestionRequest sets the session next to the pill", hooks.contains("        state.questionPillId = pillId\n        state.questionSessionId = sessionId\n") && count("state.questionSessionId = sessionId", in: hooks) == 1)
        CT.checkTrue("AppState declares questionSessionId beside questionPillId", state.contains("    var questionPillId: String = \"\"\n    var questionSessionId: String = \"\"\n"))

        CT.section("the jump: a new route beside the pill's, and the pill's own route is untouched")
        let jump = at("static func bringForward(session sessionId: String)", in: target)
        let vscodeLine = at("let vscodeBundleId = \"com.microsoft.VSCode\"", in: target)
        CT.checkTrue("bringForward(session:) comes after the pill route's VS Code line", jump > 0 && vscodeLine > 0 && jump > vscodeLine)
        let jumpBody = tail(target, from: jump)
        CT.checkTrue("it reads the session's own host", jumpBody.contains("AppState.shared.sessionHosts[sessionId]"))
        CT.checkTrue("it opens the Claude app by its bundle ID, as the pill's route does", jumpBody.contains("id == HookOrigin.desktopBundleId") && jumpBody.contains("NSWorkspace.shared.openApplication"))
        CT.checkTrue("it falls back to VS Code's route, as the pill's", jumpBody.contains("\"com.microsoft.VSCode\"") && jumpBody.contains("/Applications/Visual Studio Code.app"))
        CT.check("the pill route keeps its four GitHub-build blocks at 12 spaces", lines(target, equal: "            #if !APPSTORE"), 4)
        CT.check("the new route's GitHub-build block is at 8 spaces, once", lines(target, equal: "        #if !APPSTORE"), 1)
        CT.checkTrue("that block is inside the new function", at("\n        #if !APPSTORE\n", in: target) > jump)
        CT.checkTrue("case \"integration_claude\": is still the pill route's", count("case \"integration_claude\":", in: target) == 1)

        CT.section("ProjectsModel+App: one shared model, on the real home, its launch layout read from the real pills")
        CT.checkTrue("the shared model is a static, on the real home, the wall clock in ms and one one-shot timer on the main queue",
                     model.contains("static let shared: ProjectsModel") && model.contains("home: Sidekick.realHome") && model.contains("Date().timeIntervalSince1970 * 1000")
                        && model.contains("DispatchWorkItem { MainActor.assumeIsolated { fire() } }") && model.contains("DispatchQueue.main.asyncAfter(deadline: .now() + afterMs / 1000, execute: item)") && model.contains("return { item.cancel() }"))
        CT.checkTrue("the launch layout is read from the real pills (the main pill and the active integrations), with the focus and the island's mode, by the one refresh that reads them fresh",
                     model.contains("let model = ProjectsModel(") && model.contains("        model.refreshFromApp()\n")
                        && model.contains("refreshLayout(activePills: [i.mainPillId] + i.activeIntegrations.sorted(), open: i.expanded, focusId: i.focusId, twoCats: i.twoCats)"))
        let fStart = at("func feedFromHook(payload: [String: Any], waitIn: String?) {", in: model)
        let fBody = fStart > 0 ? tail(model, from: fStart) : ""
        let fEnd = at("\n    }", in: fBody)
        let fText = fEnd > 0 ? String(fBody.prefix(fEnd)) : fBody
        CT.checkTrue("feedFromHook is the feed, then the layout read while the island is open, and nothing else",
                     fText.contains("{\n        feed(payload: payload, waitIn: waitIn)\n        refreshFromApp()") && count("\n", in: fText) == 2)

        CT.section("the Projects files: one delayed dispatch (the one tick), no log, no sleep, no defaults, nothing under the GitHub build's flag")
        let projectFiles = ((try? FileManager.default.contentsOfDirectory(atPath: "NotchBuddy/Sources/App")) ?? []).filter { $0.hasPrefix("Projects") && $0.hasSuffix(".swift") }.sorted()
        CT.check("the Projects files are found: exactly these eight (a new Projects file is added here, with its pins)", projectFiles,
                 ["ProjectsLayout.swift", "ProjectsModel+App.swift", "ProjectsModel.swift", "ProjectsRegistry.swift", "ProjectsRules.swift", "ProjectsScreen.swift", "ProjectsSnapshot.swift", "ProjectsViews.swift"])
        let asyncHits = projectFiles.filter { count("asyncAfter", in: source($0)) > 0 }
        CT.check("asyncAfter is only in ProjectsModel+App.swift", asyncHits, ["ProjectsModel+App.swift"])
        CT.check("and it is there once", projectFiles.reduce(0) { $0 + count("asyncAfter", in: source($1)) }, 1)
        CT.checkTrue("no Projects file has a timer object, a repeating animation, a sleep, a log, print, UserDefaults or the GitHub build's flag",
                     projectFiles.allSatisfy { bannedHits(source($0)).isEmpty })
        // Every animation clock in the Projects views is paused unless the island is expanded and the view is on screen (0 % CPU when hidden): the three TimelineViews of
        // ProjectsViews.swift (the cat, the waiting dot, the kittens), each pausing on `active` or `animate`. A deliberate new one updates the number.
        let projectCode = Dictionary(uniqueKeysWithValues: projectFiles.map { ($0, source($0)) })
        CT.check("every TimelineView of the Projects files is paused unless active or animate (three, all in ProjectsViews.swift)", timelineProblems(projectCode, expected: 3), [])
        CT.check("and they are all in ProjectsViews.swift", projectFiles.filter { count("TimelineView(", in: source($0)) > 0 }, ["ProjectsViews.swift"])
        // The island files the branch edited: their Timer, repeatForever and TimelineView uses are exactly those of the branch's base (a899f23f), so nothing Projects
        // added to them runs a clock. A deliberate change to one of these updates the row.
        let islandClocks: [String: [Int]] = [   // repeatForever, Timer, onReceive(Timer, TimelineView(
            "IslandViewContent.swift": [3, 14, 0, 2], "IslandRootView.swift": [0, 5, 0, 1], "IslandWindowController.swift": [0, 20, 0, 0], "KittenViews.swift": [0, 0, 0, 1],
            "BotCanvasView.swift": [0, 0, 0, 2], "AppState.swift": [0, 7, 0, 0], "CatSettingsView.swift": [0, 0, 0, 1], "AppDelegate.swift": [0, 0, 0, 0],
            "HookServer.swift": [0, 0, 0, 0], "AgentTarget.swift": [0, 0, 0, 0], "IslandTypes.swift": [0, 0, 0, 0], "ShortcutLogic.swift": [0, 0, 0, 0],
            "CatSettingsSection.swift": [0, 0, 0, 0], "CatSettingsStore.swift": [0, 0, 0, 0], "SettingsMap.swift": [0, 0, 0, 0],
        ]
        var clockDrift: [String] = []
        for (f, want) in islandClocks.sorted(by: { $0.key < $1.key }) {
            let text = source(f), got = ["repeatForever", "Timer", "onReceive(Timer", "TimelineView("].map { count($0, in: text) }
            if got != want { clockDrift.append("\(f): \(got), expected \(want)") }
        }
        CT.check("the edited island files hold no clock the branch added (\(islandClocks.count) files)", clockDrift, [])

        CT.section("Task 9: the Projects screen's two files exist and are read, so no pin passes on a missing one")
        let screen = source("ProjectsScreen.swift"), views = source("ProjectsViews.swift"), fm = FileManager.default
        CT.checkTrue("ProjectsScreen.swift exists and is not empty", fm.fileExists(atPath: "NotchBuddy/Sources/App/ProjectsScreen.swift") && !screen.isEmpty)
        CT.checkTrue("ProjectsViews.swift exists and is not empty", fm.fileExists(atPath: "NotchBuddy/Sources/App/ProjectsViews.swift") && !views.isEmpty)

        CT.section("Task 9: the screen is built from the shared model, active only on the expanded island's Projects view, and it carries the marker")
        CT.checkTrue("ProjectsScreenHost builds ProjectsScreenContent from the model's view, active on the expanded Projects view, and opens a row",
                     screen.contains("struct ProjectsScreenHost: View") && screen.contains("ProjectsScreenContent(view: model.appView(), active: state.mode == .expanded && state.view == .projects, onRow: { ProjectsScreenHost.open($0) })"))
        CT.check("the screen references the marker once, so it is linked in every build", count("ProjectsModel.marker", in: screen), 1)
        let openBody = tail(screen, from: at("static func open(_ session: String)", in: screen))
        let approvalAt = at("state.view = .approval", in: openBody), questionAt = at("state.view = .question", in: openBody)
        let bringAt = at("AgentTarget.bringForward(session: session)", in: openBody)
        CT.checkTrue("a row's click: that session's waiting approval first, then its waiting question, else its own app (AgentTarget.bringForward)",
                     approvalAt > 0 && questionAt > approvalAt && bringAt > questionAt
                        && openBody.contains("ProjectsRegistry.same(approval.sessionId, session)") && openBody.contains("ProjectsRegistry.same(state.questionSessionId, session)"))

        CT.section("Task 9: the island shows the screen only on its view; the folder tab, the menu item and the shortcut reach it")
        let content = source("IslandViewContent.swift"), root = source("IslandRootView.swift"), types = source("IslandTypes.swift")
        let wc = source("IslandWindowController.swift"), delegate = source("AppDelegate.swift"), logic = source("ShortcutLogic.swift")
        CT.check("IslandViewContent builds the screen once", count("ProjectsScreenHost()", in: content), 1)
        CT.checkTrue("and only inside if state.view == .projects, in the .projects case", content.contains("        case .projects:\n") && content.contains("            if state.view == .projects { ProjectsScreenHost() }"))
        CT.check("IslandRootView builds no screen (it stacks every view)", count("ProjectsScreenHost", in: root), 0)
        CT.checkTrue("the header's folder tab comes right after the plus tab",
                     root.contains("                TabButton(icon: \"plus\", view: .upload, state: state)\n                TabButton(icon: \"folder.fill\", view: .projects, state: state)\n"))
        CT.checkTrue("IslandView gains projects after sidekick, and its layout is 240 high with the cat on the left",
                     types.contains("    case sidekick\n") && types.contains("    case projects\n") && at("    case projects\n", in: types) > at("    case sidekick\n", in: types)
                        && types.contains(".projects:  ViewLayout(height: 240, botX: 54,  botY: nil, botDiameter: 46, agentMode: .none),"))
        CT.checkTrue("the menu's Projects item has a tag of its own beside the shelf's, and its title follows the count in menuNeedsUpdate",
                     delegate.contains("        let projectsItem = NSMenuItem(title: \"Projects\", action: #selector(openProjects), keyEquivalent: \"\")")
                        && delegate.contains("        projectsItem.tag = Self.projectsItemTag\n        menu.addItem(projectsItem)")
                        && delegate.contains("private static let projectsItemTag = 4209")
                        && delegate.contains("menu.item(withTag: Self.projectsItemTag)?.title = ProjectsLayout.menuTitle(ProjectsModel.shared.appView().projects.count)")
                        && at("menu.item(withTag: Self.projectsItemTag)", in: delegate) > at("func menuNeedsUpdate", in: delegate))
        CT.checkTrue("the item opens the island on Projects", delegate.contains("@objc private func openProjects() { islandController?.openProjects() }") && count("#selector(openProjects)", in: delegate) == 1)
        CT.checkTrue("the model starts with the island, before any view's body could first create it", delegate.contains("        _ = ProjectsModel.shared") && at("_ = ProjectsModel.shared", in: delegate) > at("private func setupIsland()", in: delegate))
        CT.checkTrue("openProjects() opens the island on Projects, as the shelf's does (the bookkeeping, then the view)",
                     wc.contains("    func openProjects() {\n        fsm.openedExternally()\n        expand(to: .projects)\n    }"))
        let hot = tail(wc, from: at("func handleHotKey(_ action: ShortcutAction) {", in: wc))
        CT.checkTrue("the Projects key folds the island when it already shows Projects, else opens it with the keyboard, after the wardrobe's case",
                     hot.contains("        case .projects:\n            if state.mode == .expanded && state.view == .projects {\n                collapse()\n            } else {\n                openWithKeyboard(.projects)\n            }")
                        && at("case .projects:", in: hot) > at("case .wardrobe:", in: hot))
        CT.checkTrue("and the case says why in a comment of its own (the file as written)", raw("IslandWindowController.swift").contains("        case .projects:\n            // "))
        CT.checkTrue("ShortcutAction gains projects last, after wardrobe (Carbon's index)", logic.contains("    case projects\n") && at("    case projects\n", in: logic) > at("    case wardrobe\n", in: logic) && at("    case wardrobe\n", in: logic) > 0)
        CT.checkTrue("its default is ⌃⌥P (the key code 35 is P; the file says so in its comment); it is off at first on a line of its own, and the shelf's and wardrobe's line keeps its literal",
                     logic.contains(".projects:          ShortcutSpec(keyCode: 35, nsFlags: ShortcutSpec.ctrlOpt),")
                        && raw("ShortcutLogic.swift").contains(".projects:          ShortcutSpec(keyCode: 35, nsFlags: ShortcutSpec.ctrlOpt),   // ⌃⌥P")
                        && logic.contains("        case .projects: return false\n")
                        && logic.contains("case .toggleIsland, .openChat, .jumpToTerminal, .shelf, .wardrobe: return false"))
        CT.checkTrue("it is named Open Projects, has its off note, and is offered in the App Store build (isNonAppStore unchanged)",
                     logic.contains("        case .projects:          return \"Open Projects\"")
                        && logic.contains("        case .projects:\n            return \"Off at first: turn it on to open Projects with one key.\"")
                        && logic.contains("var isNonAppStore: Bool { self == .jumpToTerminal || self == .attachFrontWindow }"))

        CT.section("Task 9: the sinks follow the island's mode and focus from the published values; the layout reads are the model's")
        for pin in modelPins(model) { CT.checkTrue(pin.label, pin.holds) }
        CT.checkTrue("appView reads the project cats and the main cat when it is asked",
                     model.contains("func appView() -> PJView {\n        view(projectCats: CatSettingsStore.shared.projectCats, mainCat: CatSettingsStore.shared.settings.character)\n    }"))
        CT.check("the one delayed dispatch is still the model file's only one", count("asyncAfter", in: model), 1)

        CT.section("Task 10: the island is taller for the overview's section only, and the cat does not move when it opens")
        let sizeAt = at("func islandSize(mode: IslandMode, view: IslandView,", in: wc)
        let sizeBody = sizeAt > 0 ? tail(wc, from: sizeAt) : ""
        let sizeQuestionAt = at("if view == .question, let h = QuestionLayout.height { return (IslandConst.expandedWidth, h) }", in: sizeBody)
        let extraAt = at("return (IslandConst.expandedWidth, layout.height + (view == .overview ? ProjectsLayout.extraHeight : 0))", in: sizeBody)
        CT.checkTrue("islandSize adds the section's height for the overview only, after the question's own branch (unchanged)", sizeAt > 0 && sizeQuestionAt > 0 && extraAt > sizeQuestionAt)
        CT.check("and nowhere else in the controller", count("ProjectsLayout.extraHeight", in: wc), 1)
        let posAt = at("func botPosition(mode: IslandMode, view: IslandView,", in: root)
        let posBody = posAt > 0 ? tail(root, from: posAt) : ""
        CT.checkTrue("botPosition centres the overview's cat on min(islandH, layout.height), so it stays put while the section opens (the other views use islandH, as they did)",
                     posBody.contains("let h = view == .overview ? min(islandH, layout.height) : islandH\n            cy = headerBottom + (h - headerBottom - cardH) / 2 + cardH / 2"))

        CT.section("Task 10: the island animates its height with the section, names its coordinate space, and the content frame grows with it")
        let projectsObserved = "@ObservedObject private var projects = ProjectsModel.shared"
        CT.check("IslandContainer, BotPlacement and IslandContentView observe the model", count(projectsObserved, in: root), 3)
        let containerAt = at("struct IslandContainer: View {", in: root), shapeAt = at("struct IslandShape: Shape {", in: root)
        let containerSrc = String(decoding: Array(root.utf16)[max(0, containerAt)..<max(max(0, containerAt), shapeAt)], as: UTF16.self)
        CT.checkTrue("the container holds it", containerSrc.contains(projectsObserved))
        CT.checkTrue("the height follows panelShown on openSpring, only for the expanded overview, from islandSize",
                     containerSrc.contains(".onChange(of: projects.panelShown) { _, _ in\n            guard state.mode == .expanded, state.view == .overview else { return }")
                        && containerSrc.contains("let (w, h) = islandSize(mode: .expanded, view: .overview,")
                        && at("withAnimation(openSpring) {", in: containerSrc, from: at(".onChange(of: projects.panelShown)", in: containerSrc)) > at(".onChange(of: projects.panelShown)", in: containerSrc))
        CT.check("the island's own space is named once, on the framed island", count(".coordinateSpace(name: \"nm.island\")", in: root), 1)
        CT.checkTrue("and it is right after the island's frame (no layout change)", containerSrc.contains("        .frame(width: islandWidth, height: islandHeight, alignment: .topLeading)\n        .coordinateSpace(name: \"nm.island\")\n"))
        CT.checkTrue("the content frame is tall for the overview while the section shows, and a moment after, so the cards do not slide while the island shrinks",
                     root.contains("let tallOverview = v == .overview && (projects.panelShown || panelHeld)")
                        && root.contains("let isTall = v == .prompt || (v == .mail && active) || (v == .shelf && active) || (v == .projects && active) || tallOverview")
                        && root.contains(".padding(.top, tallOverview ? 5 : 0)"))
        CT.section("the Projects screen: the island's whole height, top-aligned, scrolled, and the big cat beside the list, never over it")
        let screenViews = source("ProjectsViews.swift"), layoutSrc = source("ProjectsLayout.swift")
        let tallAt = at("let isTall = ", in: root)
        let tallLine = tallAt > 0 ? tail(root, from: tallAt).components(separatedBy: "\n")[0] : ""
        CT.checkTrue("the .projects view is tall only while it is the active view (as the shelf's and the mail's are), so an inactive one never stretches the stack", tallLine.contains("(v == .projects && active)"))
        let screenSrc = typeText("struct ProjectsScreenContent: View {", in: screenViews)
        CT.checkTrue("the screen scrolls vertically, and its list starts screenTopInset under the header and screenLeading from the left (beside the cat)",
                     screenSrc.contains("ScrollView(.vertical, showsIndicators: false)") && screenSrc.contains(".padding(.top, ProjectsLayout.screenTopInset)") && screenSrc.contains(".padding(.leading, ProjectsLayout.screenLeading)"))
        // The cat's head (botX +- botDiameter / 2) must end before the list's left edge (the content's 10 pt side inset + screenLeading), with room for the whiskers.
        func number(_ key: String, in line: String) -> Double? {
            guard let r = line.range(of: "\(key): ") else { return nil }
            return Double(line[r.upperBound...].prefix { "0123456789.".contains($0) })
        }
        let layoutLine = types.components(separatedBy: "\n").first { $0.contains(".projects:  ViewLayout(") } ?? ""
        let leadingLine = layoutSrc.components(separatedBy: "\n").first { $0.contains("static let screenLeading") } ?? ""
        let catX = number("botX", in: layoutLine) ?? 0, catD = number("botDiameter", in: layoutLine) ?? 0
        let listLeft = 10 + (Double(leadingLine.components(separatedBy: "= ").last?.components(separatedBy: " ").first ?? "") ?? 0)
        CT.checkTrue("the layout lines were read (botX \(catX), diameter \(catD), the list's left edge \(listLeft))", catX > 0 && catD > 0 && listLeft > 10)
        CT.checkTrue("the big cat's head ends at \(catX + catD / 2), at least 8 pt before the list's left edge: the cat is never drawn over a row", catX + catD / 2 + 8 <= listLeft)
        CT.check("BotPlacement and botPosition name no Projects view, so the cat is placed by the view's layout line alone", count("view == .projects", in: root), 0)

        CT.section("a project pill draws its name in two parts, so two folders of one name look different")
        let pillSrc = typeText("struct ProjectPill: View {", in: screenViews)
        CT.checkTrue("the pill splits the name with ProjectsLayout.pillNameParts and draws the detail under the folder, cut in the middle (the tail stays visible)",
                     pillSrc.contains("ProjectsLayout.pillNameParts(project.name)") && pillSrc.contains("Text(nameParts.folder)") && pillSrc.contains("Text(detail)") && pillSrc.contains(".truncationMode(.middle)")
                        && pillSrc.contains(".font(.system(size: 9))") && pillSrc.contains("Color(hex: \"#8E939C\")"))
        CT.checkTrue("the pill never draws project.name as one cut line any more", !pillSrc.contains("Text(project.name)"))

        CT.section("the big card's title: the name gives way, \"· N sessions\" stays whole")
        let cardSrc = typeText("struct ProjectBigCard: View {", in: screenViews)
        let countSrc = chain("Text(countText)", in: cardSrc)
        CT.checkTrue("the count is one Text (its dot with it), kept whole by fixedSize and a layout priority above the name's", countSrc.contains(".fixedSize(horizontal: true, vertical: false)") && countSrc.contains(".layoutPriority(1)")
                        && cardSrc.contains("\"· \\(ProjectsLayout.sessionsWord(project.sessionCount))\""))
        let nameSrc = chain("Text(nameParts.folder)", in: cardSrc)
        CT.checkTrue("the name (the folder, tail-truncated) has the default priority, so it is what gives way, and the parent goes under it", !nameSrc.isEmpty && !nameSrc.contains("layoutPriority") && nameSrc.contains(".truncationMode(.tail)") && cardSrc.contains("Text(detail)"))

        CT.section("the Claude Code title row keeps a count capsule and the chevron only; the words are the section's first line")
        let titleBody = typeText("struct ProjectsTitleRowView: View {", in: screenViews)
        CT.checkTrue("the row is fixed in size and above the session name's layout priority (1), as its last modifier", titleBody.contains(".fixedSize(horizontal: true, vertical: false)") && titleBody.contains(".layoutPriority(2)")
                        && at(".layoutPriority(2)", in: titleBody) > at(".reporting(\"count\"", in: titleBody) && !titleBody.contains("lineLimit") && !titleBody.contains("truncationMode"))
        CT.checkTrue("it draws the project count (and the waiting number in amber when any wait) and the chevron, and none of the words", titleBody.contains("capsule(row.projects") && titleBody.contains("if row.waiting > 0 { capsule(row.waiting") && titleBody.contains("chevron.up")
                        && !titleBody.contains("Text(ProjectsLayout.projectsWord") && !titleBody.contains("Text(ProjectsLayout.waitingWord"))
        let panelSrc = typeText("struct ProjectsPanel: View {", in: screenViews)
        CT.checkTrue("the section's first line is \"N projects\" and \" · M waiting\" (ProjectsLayout's words), over the pills' row", panelSrc.contains("ProjectsLayout.projectsWord(projects.count)") && panelSrc.contains("\" · \" + ProjectsLayout.waitingWord(waiting)")
                        && at("Text(words.projects)", in: panelSrc) > 0 && at("Text(words.projects)", in: panelSrc) < at("ForEach(cells, id: \\.key)", in: panelSrc))
        CT.checkTrue("the pills' row is top-aligned, so the \"+N\" cell is on the pills' row (the same top)", panelSrc.contains("HStack(alignment: .top, spacing: 6) {\n                ForEach(cells, id: \\.key)"))
        CT.checkTrue("a cell's identity is its key, never its slot: no ForEach in the Projects views is keyed by \\.offset, and both cell lists are keyed by \\.key", !screenViews.contains("\\.offset") && count("ForEach(cells, id: \\.key)", in: screenViews) == 2)

        CT.section("the title rows never show a fragment of the subtitle: ProjectsTitleFit on the active row always, on the idle row only beside the Projects count")
        let fitSrc = typeText("struct ProjectsTitleFit<Name: View, Subtitle: View>: View {", in: screenViews)
        CT.checkTrue("ProjectsTitleFit offers the name and subtitle side by side, then the name alone, by ViewThatFits(in: .horizontal)",
                     fitSrc.contains("ViewThatFits(in: .horizontal) {\n            HStack(spacing: 6) {\n                name\n                subtitle\n            }\n            name\n        }"))
        let cardView = typeText("struct IntegrationCardView: View {", in: content)
        let rowsSrc = tail(cardView, from: at("} else if agentSessionActive {", in: cardView))
        CT.check("both title rows go through it, once each", count("ProjectsTitleFit(", in: rowsSrc), 2)
        CT.checkTrue("the active row: always through ProjectsTitleFit, ungated, ahead of the capsule row, so a subtitle that cannot fit whole is never drawn as a fragment, with or without the count",
                     rowsSrc.contains("                    ProjectsTitleFit(name: sessionName, subtitle: sessionSubtitle).layoutPriority(1)\n                    if let projectsRow { ProjectsTitleRowView(row: projectsRow) }")
                        && !rowsSrc.contains("if projectsRow != nil {\n                        ProjectsTitleFit(name: sessionName")
                        && rowsSrc.contains("let sessionName = Text(task.name)") && rowsSrc.contains(".lineLimit(1).truncationMode(.tail)"))
        CT.checkTrue("the idle row: gated the same way; its one-line limit is on the projects path only (the shipped path has none)",
                     rowsSrc.contains("if projectsRow != nil {\n                        ProjectsTitleFit(name: idleName.lineLimit(1).truncationMode(.tail), subtitle: idleSubtitle.lineLimit(1).truncationMode(.tail)).layoutPriority(1)\n                    } else {\n                        idleName\n                        idleSubtitle\n                    }")
                        && !rowsSrc.contains("let idleName = Text(PillCatalog.definition(for: task.id)?.name ?? task.name)\n                        .font(.system(size: 12, weight: .semibold))\n                        .foregroundColor(Color(hex: \"#F5F6F8\"))\n                        .lineLimit"))
        CT.checkTrue("the capsule row follows, still behind its own gate", rowsSrc.contains("if let projectsRow { ProjectsTitleRowView(row: projectsRow) }") && count("if let projectsRow { ProjectsTitleRowView(row: projectsRow) }", in: rowsSrc) == 2)

        CT.section("the screen ends a corner's radius above the end of its content, and the island's corner is the one number")
        let cornerLine = types.components(separatedBy: "\n").first { $0.contains("static let expandedCorner") } ?? ""
        let layoutCorner = (layoutSrc.components(separatedBy: "\n").first { $0.contains("static let islandCorner") } ?? "")
        func after(_ eq: String, in line: String) -> Double? { line.range(of: eq).flatMap { Double(line[$0.upperBound...].prefix { "0123456789.".contains($0) }) } }
        CT.checkTrue("ProjectsLayout.islandCorner is IslandConst.expandedCorner (the same number, read from both)", after("expandedCorner: CGFloat = ", in: cornerLine) != nil && after("expandedCorner: CGFloat = ", in: cornerLine) == after("islandCorner: CGFloat = ", in: layoutCorner))
        CT.checkTrue("the screen's scroll content ends screenBottomInset below the last section", screenSrc.contains(".padding(.bottom, ProjectsLayout.screenBottomInset)") && layoutSrc.contains("static let screenBottomInset: CGFloat = islandCorner"))

        CT.section("the peek's header: the name gives way, the count keeps its width")
        let peekSrc = typeText("struct ProjectsPeek: View {", in: screenViews)
        let peekCountAt = at("Text(ProjectsLayout.sessionsWord(project.sessionCount))", in: peekSrc)
        let peekCount = chain("Text(ProjectsLayout.sessionsWord(project.sessionCount))", in: peekSrc)
        CT.checkTrue("the count is fixed-size with a priority above the name's", peekCount.contains(".fixedSize(horizontal: true, vertical: false)") && peekCount.contains(".layoutPriority(1)"))
        let peekNameAt = at("Text(project.name)", in: peekSrc)
        CT.checkTrue("the name keeps the default priority and cuts at its tail", peekNameAt > 0 && peekNameAt < peekCountAt && !String(tail(peekSrc, from: peekNameAt).prefix(peekCountAt - peekNameAt)).contains("layoutPriority")
                        && chain("Text(project.name)", in: peekSrc).contains(".truncationMode(.tail)"))

        CT.checkTrue("panelHeld is set when the section closes and cleared by one delayed dispatch (0.9 s, no timer), held as a work item that the next close cancels before it re-arms",
                     root.contains("@State private var panelHeld = false") && root.contains("@State private var panelRelease: DispatchWorkItem?")
                        && root.contains(".onChange(of: projects.panelShown) { was, shown in\n            guard was, !shown else { return }\n            panelHeld = true\n            panelRelease?.cancel()\n            let release = DispatchWorkItem { panelHeld = false }\n            panelRelease = release\n            DispatchQueue.main.asyncAfter(deadline: .now() + 0.9, execute: release)"))

        CT.section("Task 10: the big cat's coat, state, glow and kittens follow the big card (Claude alone, expanded overview), and are today's otherwise")
        let canvasSrc = source("BotCanvasView.swift"), kittenSrc = source("KittenViews.swift")
        CT.check("both BotPlacement branches draw the coat the Projects rule gives", count("BotCanvasView(state: state, cat: state.bigCatCoat", in: root), 2)
        CT.check("and none still reads the cast's big cat directly", count("cat: state.cast.big.cat", in: root), 0)
        let placeSrc = typeText("struct BotPlacement: View {", in: root)
        CT.checkTrue("BotPlacement observes the model, so a pill click changes the coat at once", placeSrc.contains(projectsObserved))
        CT.checkTrue("its glow follows the big cat's state (the same state as the cat)", placeSrc.contains("let bigState = state.bigCatState") && !placeSrc.contains("state.effectiveState"))
        CT.checkTrue("AppState gains bigCatCoat, bigCatState and projectKittens in the model's app file", model.contains("extension AppState {") && model.contains("var bigCatCoat: String {") && model.contains("var bigCatState: BotState {") && model.contains("var projectKittens: [PJSubagentRow]? {"))
        CT.checkTrue("the coat starts from the cast's big cat and the state from the effective state, and both only differ on the expanded overview",
                     model.contains("ProjectsLayout.bigCoat(castCoat: cast.big.cat, usesProjects: card != nil, expandedOverview: mode == .expanded && view == .overview, projectCat: card?.cat)")
                        && model.contains("ProjectsLayout.bigState(castState: effectiveState.rawValue, usesProjects: card != nil, expandedOverview: mode == .expanded && view == .overview, projectState: card?.state)")
                        && model.contains("?? effectiveState"))
        CT.checkTrue("the one big-card lookup is the expanded overview's, with the Two cats ruling, and reads the model's view only then",
                     model.contains("guard mode == .expanded, view == .overview else { return nil }")
                        && model.contains("ProjectsLayout.usesProjects(layout: model.layout, focusId: focusId, projectCount: v.projects.count, twoCats: cast.second != nil)"))
        CT.checkTrue("the kittens are all of the big card project's subagents", model.contains("card.sessions.flatMap { $0.subagents }"))
        CT.checkTrue("BotCanvasView reads no effectiveState any more, takes the state from bigCatState once per body, and observes the model",
                     !canvasSrc.contains("state.effectiveState") && count("state.bigCatState", in: canvasSrc) == 1 && canvasSrc.contains("let shownState = state.bigCatState") && count("shownState", in: canvasSrc) == 5
                        && canvasSrc.contains(projectsObserved))
        CT.checkTrue("its four reads: the collar, the dance gate, the change and the forced state",
                     canvasSrc.contains("state: CatState(rawValue: shownState.rawValue) ?? .idle)") && canvasSrc.contains("allowed.contains(shownState)")
                        && canvasSrc.contains(".onChange(of: shownState) { _, newState in") && canvasSrc.contains("engine.setState(shownState, force: true)"))
        CT.checkTrue("KittenPlacement observes the model", kittenSrc.contains(projectsObserved))
        CT.check("KittenPlacement is still one placement in the island and one kittenParents call", [count("KittenPlacement(state: state", in: root), count("CatIslandLayout.kittenParents(", in: kittenSrc)], [1, 1])
        CT.checkTrue("its project branch draws ProjectKittenLayer for the big cat INSTEAD of the big cat's own layer (an else-if, never both), and nothing while the cat is on the desktop",
                     kittenSrc.contains("if overview, let rows = state.projectKittens {") && kittenSrc.contains("} else if compact || overview, !state.kittens.isEmpty {")
                        && kittenSrc.contains("if !state.desktopPhase.notchEmpty {") && at("ProjectKittenLayer(", in: kittenSrc) > at("if overview, let rows = state.projectKittens {", in: kittenSrc)
                        && at("ProjectKittenLayer(", in: kittenSrc) < at("} else if compact || overview, !state.kittens.isEmpty {", in: kittenSrc))
        CT.checkTrue("it is active only on the expanded overview and in the big cat's coat", kittenSrc.contains("parentCat: state.bigCatCoat") && kittenSrc.contains("active: state.mode == .expanded && state.view == .overview"))

        CT.section("Task 10: the overview's two layouts")
        CT.check("OverviewView observes the model", count(projectsObserved, in: content), 1)
        let usesCalls = ((try? FileManager.default.contentsOfDirectory(atPath: "NotchBuddy/Sources/App")) ?? []).filter { $0.hasSuffix(".swift") && $0 != "ProjectsLayout.swift" }
            .flatMap { f in source(f).components(separatedBy: "\n").filter { $0.contains("usesProjects(") && !$0.contains("///") && !$0.contains("usesProjects: ") } }
        CT.checkTrue("usesProjects( is called in two places, and each passes twoCats: the cast's second cat is there",
                     usesCalls.count == 2 && usesCalls.allSatisfy { $0.contains("twoCats: state.cast.second != nil") || $0.contains("twoCats: cast.second != nil") })
        CT.checkTrue("every Projects view in the overview is active only on the expanded overview (one definition, three uses)",
                     count("let projectsActive = state.mode == .expanded && state.view == .overview", in: content) == 1
                        && content.contains("ProjectBigCard(project: card, animate: p.active,") && content.contains("ProjectsGridInput(projects: view.projects, active: projectsActive,")
                        && content.contains("active: p.active, onSelect: { projects.select($0) }, onMore: openScreen, onHover: hoverProject, onFrame: recordFrame)")
                        && content.contains("grid: grid, active: projectsActive, toggle: toggle)"))
        CT.checkTrue("the big card and the pill grid are built only under the projects layout; the shipping cards are the else",
                     content.contains("if let card = p.card {") && content.contains("} else if let agent = agent {") && at("ProjectBigCard(project: card", in: content) > at("if let card = p.card {", in: content)
                        && at("ProjectBigCard(project: card", in: content) < at("} else if let agent = agent {", in: content)
                        && content.contains("let grid: ProjectsGridInput? = if uses {") && content.contains("AgentPillsView(state: state, projects: p.grid)")
                        && content.contains("        if let projects {\n            ProjectPillGrid(") && content.contains("        } else {\n            VStack(spacing: 0) {\n                Spacer(minLength: 0)\n                LazyVGrid(columns: columns, spacing: 4) {"))
        CT.checkTrue("a project pill selects it, the +N opens the screen, and the hover is the peek's (Task 11: no placeholder is left)",
                     count("onSelect: { projects.select($0) }", in: content) == 2 && content.contains("onMore: openScreen") && content.contains("withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { state.view = .projects }")
                        && count("onHover: { _, _ in }", in: content) == 0 && count("onHover: hoverProject", in: content) == 2)
        CT.checkTrue("the big card's open brings forward the project's newest session by the registry's session id",
                     content.contains("AgentTarget.bringForward(session: newest.id)") && content.contains("project.sessions.max(by: { $0.lastAt < $1.lastAt })"))
        CT.checkTrue("a project's cell is the grid's: the other pills are the cast's pills that are not Claude, with their coat and the shipping tap",
                     content.contains("otherPills: displayPills.filter { $0.task.id != \"integration_claude\" }.map { $0.task.id }") && content.contains("private func pillView(_ pill: (task: AgentTask, cat: String))")
                        && count("pillView(pill)", in: content) == 2 && content.contains("if let pill = displayPills.first(where: { $0.task.id == id }) { pillView(pill) }")
                        && count("state.setFocus(task.id)", in: content) == 3)
        CT.checkTrue("the chevron and the count are on the Claude Code card only with other agents (not the projects layout), a live project, and not in Two cats mode",
                     content.contains("!uses && state.cast.second == nil && state.focusId == \"integration_claude\"") && !content.contains("agent?.id == \"integration_claude\"")
                        && content.contains("let projectsRow: ProjectsTitleRow? = if "))
        CT.checkTrue("the chevron toggles the section with the island's own spring, and so does a tap on the card's empty background",
                     content.contains("let toggle = { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { projects.togglePanel() } }")
                        && content.contains("Color.clear.contentShape(Rectangle()).onTapGesture(perform: p.toggle)"))
        CT.checkTrue("the section is the model's panelShown, under the cards, with the island's transition",
                     content.contains("if projects.panelShown {") && content.contains("ProjectsPanel(cells: ProjectsLayout.panelCells(projects: p.view.projects.map { $0.id }),")
                        && content.contains(".transition(.opacity.combined(with: .move(edge: .top)))"))
        CT.checkTrue("the title rows of the Claude Code card (session and idle) carry the row, and nothing else of IntegrationCardView changes",
                     count("ProjectsTitleRowView(row: projectsRow)", in: content) == 2 && content.contains("var projectsRow: ProjectsTitleRow? = nil"))

        CT.section("Task 10: waiting is a count, never an alert; the model's side")
        let projectViews = ["ProjectsViews.swift", "ProjectsScreen.swift", "ProjectsModel+App.swift", "ProjectsModel.swift"]
        let alertWords = ["wingAlert", "isHeldOpen", "isHoverHeld", "agentActivity", "userInteracted"]
        CT.checkTrue("no Projects file touches the island's alert, hold or activity rules", projectViews.allSatisfy { f in alertWords.allSatisfy { !source(f).contains($0) } })
        CT.checkTrue("the model has a togglePanel that relayouts while it is expanded", source("ProjectsModel.swift").contains("func togglePanel() {\n        panelOpen.toggle()\n        relayout(open: expanded)\n    }"))
        CT.check("the app's side has ONE refreshLayout call (its inputs and the display sink are pinned above, in modelPins)", model.components(separatedBy: "\n").filter { $0.contains("refreshLayout(") }.count, 1)

        CT.section("no view or controller reads the registry or a path")
        let viewFiles = ["IslandViewContent.swift", "IslandRootView.swift", "KittenViews.swift", "BotCanvasView.swift", "AppDelegate.swift",
                         "IslandWindowController.swift", "CatSettingsSection.swift", "ProjectsViews.swift", "ProjectsScreen.swift"]
        CT.checkTrue("none of them contains .registry or .cwd, and the two Projects view files are read (a missing one fails, it is not empty)",
                     !views.isEmpty && !screen.isEmpty && viewFiles.allSatisfy { !source($0).contains(".registry") && !source($0).contains(".cwd") })

        // MARK: Task 11 (the peek, Pin / Unpin, the compact waiting badge)
        let noAlert = ["wingAlert", "isHeldOpen", "isHoverHeld", "fsm.reveal", "hookExpand", "agentActivity", "userInteracted", "IslandTuckAway"]
        func touchesNoAlert(_ text: String) -> Bool { !text.isEmpty && noAlert.allSatisfy { !text.contains($0) } }

        CT.section("Task 11: the right-click monitor asks the Pin menu first and the Wardrobe menu second")
        let rightAt = at("NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in", in: wc)
        let rightText = rightAt > 0 ? String(tail(wc, from: rightAt).prefix(400)) : ""
        CT.checkTrue("one handled flag: the pin menu, then (only if it did not show) the wardrobe's",
                     rightText.contains("let handled = MainActor.assumeIsolated { self.showProjectPinMenu(for: event) || self.showWardrobeMenu(for: event) }")
                        && count("showProjectPinMenu(for: event)", in: wc) == 1 && count("showWardrobeMenu(for: event)", in: wc) == 1)
        let pinFn = body("private func showProjectPinMenu(for event: NSEvent) -> Bool {", in: wc)
        CT.checkTrue("showProjectPinMenu is there, and it is a member of the controller after the wardrobe's", !pinFn.isEmpty && at("private func showProjectPinMenu", in: wc) > at("private func showWardrobeMenu", in: wc))
        let guardAt = at("guard state.mode == .expanded", in: pinFn), flagAt = at("wardrobeMenuOpen = true", in: pinFn), deferAt = at("defer { wardrobeMenuOpen = false }", in: pinFn)
        let popAt = at("NSMenu.popUpContextMenu(", in: pinFn)
        CT.checkTrue("it returns false unless the island is expanded on the overview and the point is in a pill's frame, before it takes the flag",
                     guardAt >= 0 && pinFn.contains("state.view == .overview") && pinFn.contains("ProjectsHits.pillFrames.first(where: { $0.value.contains(point) })")
                        && pinFn.contains("else { return false }") && at("else { return false }", in: pinFn) < flagAt && flagAt > 0)
        CT.checkTrue("it takes wardrobeMenuOpen (the Wardrobe menu's own flag, so the menu has its holds) before it pops, and ends the hold through releasePinMenuHold, not at once", flagAt > 0 && pinFn.contains("wardrobeMenuOpen = true\n        pinMenuRelease?.cancel()\n        defer { releasePinMenuHold() }") && !pinFn.contains("wardrobeMenuOpen = false") && popAt > at("defer { releasePinMenuHold() }", in: pinFn))
        let releaseFn = body("private func releasePinMenuHold() {", in: wc)
        CT.checkTrue("the hold outlives popUpContextMenu by 0.5 s (a menu item's action and the click's mouse-up come after the call, and the outside click would fold the island at either), by one cancellable one-shot, never a poll",
                     !releaseFn.isEmpty && releaseFn.contains("DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)") && releaseFn.contains("self?.wardrobeMenuOpen = false") && releaseFn.contains("pinMenuRelease = item")
                        && wc.contains("private var pinMenuRelease: DispatchWorkItem?") && !releaseFn.contains("Timer"))
        let wardrobeFn = body("private func showWardrobeMenu(for event: NSEvent) -> Bool {", in: wc)
        CT.checkTrue("a Wardrobe menu opened while the pin's hold is still running ends that release first, so the hold cannot drop under the Wardrobe menu", !wardrobeFn.isEmpty && wardrobeFn.contains("wardrobeMenuOpen = true\n        pinMenuRelease?.cancel()\n        defer { wardrobeMenuOpen = false }"))
        CT.checkTrue("the outside click reads the hold at the press (busy) and the poll's pointer memory reads it too, so the whole click is covered", wc.contains("busy: inAttachDrag || attachDragStart != nil || wardrobeMenuOpen)") && wc.contains("wasInIsland = inIsland || wardrobeMenuOpen"))
        CT.checkTrue("the point is the window's, in the island's own coordinates: x from the island's left, y measured down from its top",
                     pinFn.contains("let island = panel.currentIslandFrame(nw: notchW, nh: notchH)") && pinFn.contains("CGPoint(x: event.locationInWindow.x - island.minX, y: island.maxY - event.locationInWindow.y)"))
        CT.checkTrue("one NSMenu, one item, titled by ProjectsLayout.pinTitle(, whose action toggles the pin; popped in the content view",
                     count("NSMenu()", in: pinFn) == 1 && count("menu.addItem(", in: pinFn) == 1 && count("NSMenuItem(", in: pinFn) == 1
                        && pinFn.contains("title: ProjectsLayout.pinTitle(pinned: ProjectsModel.shared.isPinned(id))") && pinFn.contains("#selector(ProjectPinTarget.toggle(_:))")
                        && pinFn.contains("NSMenu.popUpContextMenu(menu, with: event, for: view)") && pinFn.contains("return true"))
        CT.checkTrue("its pill must still be a live project (a frame that outlived its pill pins nothing)", pinFn.contains("ProjectsModel.shared.appView().projects.contains(where: { $0.id == id })"))
        CT.checkTrue("it touches no alert, hold, activity or tuck-away rule", touchesNoAlert(pinFn))
        CT.check("the Wardrobe flag keeps its name (pinned elsewhere) and is set only by the two menus", count("wardrobeMenuOpen = true", in: wc), 2)

        CT.section("Task 11: the pin menu's target and the pill frames are the app's side of the model")
        CT.checkTrue("ProjectsHits is a main-actor enum with the frames (project id to a rectangle in the island's coordinates)",
                     model.contains("@MainActor enum ProjectsHits {") && model.contains("static var pillFrames: [String: CGRect] = [:]"))
        CT.checkTrue("ProjectPinTarget is a main-actor NSObject whose toggle reads the project's id from the item and toggles its pin in the shared model",
                     model.contains("final class ProjectPinTarget: NSObject {") && model.contains("static let shared = ProjectPinTarget()") && model.contains("@objc func toggle(_ item: NSMenuItem) {")
                        && model.contains("guard let id = item.representedObject as? String else { return }") && model.contains("ProjectsModel.shared.togglePin(id)"))
        CT.checkTrue("ProjectsViews.swift never names ProjectsHits, a window, a panel, a popover or a menu (the render tool does not compile the app's side)",
                     ["ProjectsHits", "NSWindow", "NSPanel", "NSPopover", ".popover(", "NSMenu"].allSatisfy { !views.contains($0) })
        CT.checkTrue("a pill that leaves the tree reports a null frame, so a stale frame cannot be right-clicked", views.contains(".onDisappear { onFrame(.null) }"))

        CT.section("Task 11: the compact badge's click opens the Projects screen, before the shelf badge's")
        let upAt = at("NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in", in: wc)
        let upText = upAt > 0 ? String(tail(wc, from: upAt).prefix(1800)) : ""
        let projBadgeAt = at("hadPendingClick && self.state.mode != .expanded && self.clickedProjectsBadge(event) {\n                        self.openProjects()", in: upText)
        let shelfBadgeAt = at("hadPendingClick && self.state.mode != .expanded && self.clickedShelfBadge(event) {", in: upText)
        CT.checkTrue("the mouse-up monitor asks clickedProjectsBadge (then openProjects) and then clickedShelfBadge", projBadgeAt > 0 && shelfBadgeAt > projBadgeAt)
        CT.check("both badge clicks are asked once each, in that one monitor", [count("clickedProjectsBadge(event)", in: wc), count("clickedShelfBadge(event)", in: wc)], [1, 1])
        let clickFn = body("private func clickedProjectsBadge(_ event: NSEvent) -> Bool {", in: wc)
        CT.checkTrue("clickedProjectsBadge mirrors the shelf's: compact only, only while the badge is drawn, ProjectsLayout.badgeHitRect over the island's frame",
                     clickFn.contains("guard state.mode == .compact, ProjectsLayout.badgeShown(compact: true, waiting: ProjectsModel.shared.appView().waiting, greetingTail: state.greetingTail), let panel = window as? IslandPanel else { return false }")
                        && clickFn.contains("return ProjectsLayout.badgeHitRect(island: panel.currentIslandFrame(nw: notchW, nh: notchH)).contains(event.locationInWindow)"))
        CT.checkTrue("it touches no alert, hold, activity or tuck-away rule", touchesNoAlert(clickFn))

        CT.section("Task 11: the island draws the badge only compact, beside the shelf's, as the waiting count (never an alert)")
        let badgeAt = at("if ProjectsLayout.badgeShown(compact: state.mode == .compact,", in: root)
        let badgeText = badgeAt > 0 ? String(tail(root, from: badgeAt).prefix(700)) : ""
        let badgeEnd = at("\n            }\n", in: badgeText)
        let badgeBlock = badgeEnd > 0 ? String(badgeText.prefix(badgeEnd)) : badgeText
        CT.checkTrue("the badge is built once, inside that if, with the count the model reports and its own place", count("ProjectsBadgeView(", in: root) == 1 && badgeBlock.contains("ProjectsBadgeView(count: projectsWaiting, height: islandHeight)")
                        && badgeBlock.contains(".position(ProjectsLayout.badgeCenter(islandWidth: islandWidth, height: islandHeight))"))
        CT.checkTrue("it fades with the wing, like the grid and the shelf's badge", badgeBlock.contains(".opacity(state.wingYielded ? 0 : 1)") && badgeBlock.contains(".animation(wingAnimation, value: state.wingYielded)"))
        CT.checkTrue("it comes after the mini grid, and after the shelf's badge block", badgeAt > at("CompactMiniGrid(state: state)", in: root) && badgeAt > at("ShelfBadgeView(count: shelf.count", in: root))
        CT.check("ShelfBadge.isShown is still asked once in the island, and the shelf's block is as it was", [count("ShelfBadge.isShown", in: root), count("ShelfBadgeView(count: shelf.count, height: islandHeight)", in: root)], [1, 1])
        CT.checkTrue("the count is read when the island draws (the model's view, only while compact: no timer, no subscription of its own)",
                     root.contains("let projectsWaiting = state.mode == .compact ? projects.appView().waiting : 0") && count("projects.appView()", in: root) == 1
                        && badgeBlock.contains("waiting: projectsWaiting"))
        CT.checkTrue("the badge's own lines touch no alert, hold, activity or tuck-away rule", touchesNoAlert(badgeBlock))

        CT.section("Task 11: the peek is a view inside the island over the left card, after a dwell, and purely visual")
        let ovAt = at("struct OverviewView: View {", in: content), ovEnd = at("    private func openAgentTarget(", in: content)
        let overview = ovAt >= 0 && ovEnd > ovAt ? String(decoding: Array(content.utf16)[ovAt..<ovEnd], as: UTF16.self) : ""
        CT.checkTrue("OverviewView is found", !overview.isEmpty)
        CT.checkTrue("it keeps the peek's project and its dwell task as state", overview.contains("private var peekId: String? { projects.peekingProject }") && !overview.contains("@State private var peekId")
                        && overview.contains("@State private var peekPending: String?") && overview.contains("@State private var peekTask: Task<Void, Never>?"))
        let hoverFn = body("private func hoverProject(_ id: String, _ hovering: Bool) {", in: overview)
        CT.checkTrue("a hover-in starts ONE sleep for the dwell (a Task, no timer, no poll); a hover-out cancels it and clears the peek",
                     !hoverFn.isEmpty && count("Task.sleep", in: hoverFn) == 1 && count("Task {", in: hoverFn) == 1 && count("Timer", in: hoverFn) == 0
                        && hoverFn.contains("Task.sleep(for: .milliseconds(Int(ProjectsLayout.peekDwell * 1000)))") && hoverFn.contains("peekTask?.cancel()")
                        && hoverFn.contains("projects.setPeeking(nil)") && hoverFn.contains("guard !Task.isCancelled, state.mode == .expanded, state.view == .overview else { return }")
                        && hoverFn.contains("projects.setPeeking(id)") && hoverFn.contains("peekPending = id"))
        CT.checkTrue("a late exit from one pill after the enter of another cancels nothing of the other's: only the pending id clears the dwell, only the showing id clears the peek",
                     hoverFn.contains("guard hovering else {\n            if peekPending == id { clearPeek() } else if peekId == id { projects.setPeeking(nil) }\n            return\n        }")
                        && at("guard hovering else {", in: hoverFn) < at("peekTask?.cancel()", in: hoverFn))
        CT.check("the dwell and the sleep are in no other place of the overview", [count("Task.sleep", in: overview), count("ProjectsLayout.peekDwell", in: overview)], [1, 1])
        let clearFn = body("private func clearPeek() {", in: overview)
        CT.checkTrue("clearPeek cancels the dwell and clears the pending id and the peek", clearFn.contains("peekTask?.cancel()") && clearFn.contains("peekTask = nil") && clearFn.contains("peekPending = nil") && clearFn.contains("projects.setPeeking(nil)"))
        let modeAt = at(".onChange(of: state.mode) { _, m in", in: overview)
        let modeText = modeAt > 0 ? String(tail(overview, from: modeAt).prefix(300)) : ""
        CT.checkTrue("it clears when the mode leaves .expanded: the peek, the dwell task and the frames, before the GitHub build's block",
                     modeText.contains("if m != .expanded { clearPeek(); ProjectsHits.pillFrames.removeAll() }") && at("if m != .expanded { clearPeek()", in: modeText) < at("#if !APPSTORE", in: modeText))
        CT.checkTrue("it clears when the view leaves the overview, the focus changes or the section opens or closes (a pill that goes takes no hover-out with it)",
                     overview.contains(".onChange(of: state.view) { _, v in\n            if v != .overview { clearPeek() }\n        }") && !overview.contains("if v != .overview { clearPeek(); ProjectsHits")
                        && overview.contains(".onDisappear { clearPeek() }")
                        && overview.contains(".onChange(of: projects.panelShown) { _, _ in clearPeek() }")
                        && overview.contains("            showingN8nDetail = false\n            activeDiffId = nil\n            clearPeek()\n"))
        CT.checkTrue("the peek is drawn inside the island as an overlay of the left card, with the project's own value, and ignores the pointer (the pills stay hoverable and clickable)",
                     count("ProjectsPeek(", in: overview) == 1 && overview.contains("\n                if let id = peekId, p.active, let project = p.view.projects.first(where: { $0.id == id }) {\n                    ProjectsPeek(project: project, active: p.active)\n                        .allowsHitTesting(false)")
                        && overview.contains("            .frame(width: 322)\n            .overlay {"))
        CT.checkTrue("no popover, no window, no panel is made for it", ["NSPopover", ".popover(", "NSWindow", "NSPanel"].allSatisfy { !overview.contains($0) && !model.contains($0) && !views.contains($0) })
        CT.checkTrue("the overview's own Projects lines touch no alert, hold, activity or tuck-away rule (the overview's other lines are not Projects')",
                     touchesNoAlert(hoverFn) && touchesNoAlert(clearFn) && touchesNoAlert(body("private func recordFrame(_ id: String, _ rect: CGRect) {", in: overview)))
        let recordFn = body("private func recordFrame(_ id: String, _ rect: CGRect) {", in: overview)
        CT.checkTrue("a pill's frame goes to ProjectsHits through one function; a null frame removes it", recordFn.contains("ProjectsHits.pillFrames[id] = rect.isNull ? nil : rect"))
        CT.checkTrue("a pill that leaves the tree under the pointer (no hover-out comes) drops its own pending or showing peek, before its frame goes",
                     recordFn.contains("if rect.isNull, peekId == id || peekPending == id { clearPeek() }") && at("clearPeek()", in: recordFn) < at("ProjectsHits.pillFrames[id] =", in: recordFn))

        CT.section("Task 11 fix: while a peek is open the big cat and the kittens step aside (opacity only), from one memory-only value the overview alone writes")
        let modelSrc = source("ProjectsModel.swift")
        CT.checkTrue("the model holds the peeking project, published, set only through setPeeking (which publishes on a change only), and a fold clears it",
                     modelSrc.contains("@Published private(set) var peekingProject: String?") && modelSrc.contains("func setPeeking(_ id: String?) {\n        if peekingProject != id { peekingProject = id }\n    }")
                        && body("func islandExpanded(_ expanded: Bool) {", in: modelSrc).contains("if !expanded { setPeeking(nil) }"))
        let allApp = ((try? FileManager.default.contentsOfDirectory(atPath: "NotchBuddy/Sources/App")) ?? []).filter { $0.hasSuffix(".swift") }
        CT.check("setPeeking( is called from the overview's hover and clear only (three calls), and the model's own fold", allApp.filter { $0 != "ProjectsModel.swift" && $0 != "IslandViewContent.swift" }.reduce(0) { $0 + count("setPeeking(", in: source($1)) }, 0)
        CT.check("the overview's three calls are all inside hoverProject and clearPeek", [count("projects.setPeeking(", in: content), count("projects.setPeeking(", in: hoverFn) + count("projects.setPeeking(", in: clearFn)], [3, 3])
        CT.checkTrue("AppState.projectPeeking is the peek's one reader: the expanded overview with a project peeking, nowhere else",
                     model.contains("var projectPeeking: Bool {\n        mode == .expanded && view == .overview && ProjectsModel.shared.peekingProject != nil\n    }"))
        CT.checkTrue("BotPlacement fades the cat spot (glow and cat) with it, and changes nothing else (hit testing, position, engine)",
                     placeSrc.contains("        .allowsHitTesting(false)\n        .opacity(state.projectPeeking ? 0 : 1)\n        .animation(.easeOut(duration: 0.12), value: state.projectPeeking)")
                        && placeSrc.contains("if !state.desktopPhase.notchEmpty { catSpot }")
                        && count("state.projectPeeking", in: placeSrc) == 2 && count(".allowsHitTesting(false)", in: placeSrc) == 1)
        let kittenBodyAt = at("struct KittenPlacement: View {", in: kittenSrc)
        let kittenPlace = kittenBodyAt >= 0 ? tail(kittenSrc, from: kittenBodyAt) : ""
        CT.checkTrue("KittenPlacement fades both of its branches (the project's kittens and the big cat's own) with it, over the whole of its old body",
                     kittenPlace.contains("        layers\n            .opacity(state.projectPeeking ? 0 : 1)\n            .animation(.easeOut(duration: 0.12), value: state.projectPeeking)")
                        && kittenPlace.contains("    @ViewBuilder private var layers: some View {") && kittenPlace.contains("        if overview, let rows = state.projectKittens {")
                        && count("state.projectPeeking", in: kittenPlace) == 2)
        CT.checkTrue("neither placement nor the model's reader touches an alert, hold, activity or tuck-away rule",
                     touchesNoAlert(placeSrc.replacingOccurrences(of: "state.desktopPhase", with: "")) && touchesNoAlert(kittenPlace) && touchesNoAlert(body("var projectPeeking: Bool {", in: model)))
        CT.checkTrue("both call sites hand the pills' hover and frame to it: the grid through its input, the section directly",
                     overview.contains("onSelect: { projects.select($0) }, onMore: openScreen, onHover: hoverProject, onFrame: recordFrame)")
                        && count("onFrame: recordFrame", in: overview) == 2)
        CT.checkTrue("the grid passes its input's hover and frame on to the pills", content.contains("onSelect: projects.onSelect, onMore: projects.onMore, onHover: projects.onHover, onFrame: projects.onFrame)")
                        && views.contains("    let onHover: (String, Bool) -> Void\n    let onFrame: (String, CGRect) -> Void\n}"))

        CT.section("Task 11: the Task 10 minors")
        CT.checkTrue("ProjectsOverview no longer carries an unread `uses`", !content.contains("var uses: Bool") && !content.contains("ProjectsOverview(view: view, uses:"))
        CT.checkTrue("Two cats is a required argument of panelShown and of refreshLayout (no default to forget)",
                     !source("ProjectsLayout.swift").contains("twoCats: Bool = false") && !source("ProjectsModel.swift").contains("twoCats: Bool = false")
                        && source("ProjectsLayout.swift").contains("projectCount: Int, twoCats: Bool) -> Bool {") && source("ProjectsModel.swift").contains("focusId: String?, twoCats: Bool) {"))
        CT.checkTrue("the relayout that reads the stored values is unchanged", source("ProjectsModel.swift").contains("func relayout(open: Bool) {\n        refreshLayout(activePills: activePills, open: open, focusId: focusId, twoCats: twoCats)\n    }"))

        CT.section("Task 12: Settings → Cat → Agents' cats gains Project cats")
        let catPanel = source("CatSettingsView.swift"), catSection = source("CatSettingsSection.swift")
        let catScriptText = (try? String(contentsOfFile: "scripts/render-cat-settings.sh", encoding: .utf8)) ?? ""
        CT.checkTrue("scripts/render-cat-settings.sh is readable and not empty", !catScriptText.isEmpty)
        let catScript = SourceScan.shellCode(catScriptText)
        let groupText = body("    private var projectsGroup: some View {", in: catPanel)
        let rowText = body("    private func projectRow(_ row: ProjectCatList.Row) -> some View {", in: catPanel)
        CT.checkTrue("the section observes the model and passes the live projects as catKey and name only, never a path",
                     catSection.contains("@ObservedObject private var projects = ProjectsModel.shared")
                        && catSection.contains("let live = projects.appView().projects.map { ProjectCatList.Live(catKey: $0.catKey, name: $0.name) }")
                        && catSection.contains("tab: tab, projects: live)") && !catSection.contains("cwd"))
        CT.checkTrue("the card sits in the agents' block after the perAgent group, on its own line, so it shows in every display mode",
                     catPanel.contains("                if store.display.mode == .perAgent { agentsGroup }\n                projectsGroup\n            }\n"))
        CT.checkTrue("projectsGroup: the card's name, the empty sentence under if rows.isEmpty, and one row per project",
                     groupText.contains("let rows = ProjectCatList.rows(live: projects, stored: store.projectCats, main: id)") && groupText.contains("SettingsCard(\"Project cats\")")
                        && groupText.contains("if rows.isEmpty {\n                HelpText(ProjectsLayout.emptySettings)\n            }") && groupText.contains("ForEach(rows, id: \\.catKey) { projectRow($0) }"))
        CT.checkTrue("the card's help text states the limit with the cap's own constant, and no longer promises a cat for every project",
                     groupText.contains("HelpText(\"Each project wears the cat you give it, by its folder's name; up to \\(ProjectsRules.projectCatsMax) projects keep one. A project without one gets a cat that is not the Main cat.\")")
                        && !groupText.contains("by its folder's name. A project without one"))
        let nameLines = (groupText + rowText).components(separatedBy: "\n").filter { $0.contains("Text(row.name)") }
        CT.checkTrue("the name is never cut: no line limit in the card, and the name's line has no width frame and is fixed-size vertically",
                     !(groupText + rowText).contains("lineLimit") && nameLines.count == 1 && !(nameLines.first ?? "").contains(".frame(width:")
                        && (nameLines.first ?? "").contains(".fixedSize(horizontal: false, vertical: true)"))
        let wrapAt = at("WrapRow {", in: rowText), wrapped = wrapAt >= 0 ? tail(rowText, from: wrapAt) : ""
        CT.checkTrue("projectRow: the preview, the picker and Reset sit in one WrapRow, and Reset is only for a stored cat",
                     count("WrapRow {", in: rowText) == 1 && wrapped.contains("CatPreviewView(id: row.cat, head: 28, active: active, config: store.config)")
                        && wrapped.contains("catPicker(Binding(get: { row.cat }, set: { store.setProjectCat($0, for: row.catKey) }))")
                        && wrapped.contains("if row.stored {\n                    Button(\"Reset\") { store.resetProjectCat(for: row.catKey) }\n                }"))
        CT.checkTrue("CatSettingsView keeps one lineLimit (the Main cat's tile), no GroupBox, and reads neither the app's model nor AppState",
                     count(".lineLimit(1)", in: catPanel) == 1 && count("GroupBox(", in: catPanel) == 0 && !catPanel.contains("ProjectsModel.shared") && !catPanel.contains("AppState.shared"))
        CT.checkTrue("CatSettingsView takes projects after tab, with an empty default, and keeps it",
                     catPanel.contains("wardrobeDay: @escaping () -> Wardrobe.Day = { Wardrobe.today() }, tab: SettingsRoute.Tab? = nil, projects: [ProjectCatList.Live] = []) {")
                        && catPanel.contains("self.projects = projects"))
        CT.checkTrue("the cat render script compiles ProjectsLayout beside Task 4's two files, right before CatSettingsStore",
                     count("$APP/ProjectsRules.swift $APP/ProjectCatSettings.swift $APP/ProjectsLayout.swift $APP/CatSettingsStore.swift", in: catScript) == 1)

        CT.section("the scanner: comments go, strings stay (tests/SourceScan.swift)")
        let scanCases: [(String, String)] = [
            ("a // c\nb\n", "a\nb\n"),
            ("// c\nb\n", "b\n"),
            ("let u = \"http://x\" // c\n", "let u = \"http://x\"\n"),
            ("x /* a /* nested */ b */ y\n", "x  y\n"),
            ("/* a\n b */\nz\n", "z\n"),
            ("let r = #\"a // b \"c\" \"#\nq // z\n", "let r = #\"a // b \"c\" \"#\nq\n"),
            ("let m = \"\"\"\n// not a comment\n\"\"\"\nk\n", "let m = \"\"\"\n// not a comment\n\"\"\"\nk\n"),
            ("let i = \"a \\(f(\"//\")) b\" // c\n", "let i = \"a \\(f(\"//\")) b\"\n"),
            ("let e = \"q\\\"// x\" // c\n", "let e = \"q\\\"// x\"\n"),
            ("a\n\n// c\n\nb\n", "a\n\n\nb\n"),
        ]
        for (input, want) in scanCases { CT.check("code(\(input.debugDescription))", SourceScan.code(input), want) }
        CT.check("a text that ends inside a string is not balanced", SourceScan.scan("let s = \"abc\n").balanced, false)
        CT.check("structText: from the declaration to the brace at column 0, and no further", SourceScan.structText("struct A {", in: "struct A {\n    var x = 1\n}\nstruct B {\n}\n"), "struct A {\n    var x = 1\n}")
        CT.check("structText: a declaration that is not there is nil", SourceScan.structText("struct C {", in: "struct A {\n}\n"), nil)
        CT.check("structText: a type that never closes is nil", SourceScan.structText("struct A {", in: "struct A {\n    var x = 1\n"), nil)
        CT.check("chain: the expression and its modifier lines, not the next sibling", SourceScan.chain("Text(a)", in: "  Text(a)\n    .font(x)\n    .bold()\n  Text(b)\n    .italic()\n"), "  Text(a)\n    .font(x)\n    .bold()")
        CT.check("timelineViews: each argument list, nested parentheses kept", SourceScan.timelineViews(in: "TimelineView(.animation(minimumInterval: 1, paused: !a)) { t in\n}\nTimelineView(.periodic(from: d, by: 1)) { _ in }"),
                 [".animation(minimumInterval: 1, paused: !a)", ".periodic(from: d, by: 1)"])
        CT.check("enumCases: the case names, in order", SourceScan.enumCases("E", in: "enum E: String {\n    case a, b\n    case c\n}\n"), ["a", "b", "c"])

        CT.section("negative controls: the real sources, changed in memory, must fail the same pins (a comment keeps a substring; the code does not)")
        let hooksRaw = raw("HookServer.swift"), modelRaw = raw("ProjectsModel+App.swift"), viewsRaw = raw("ProjectsViews.swift")
        func failing(_ pins: [Pin]) -> [String] { pins.filter { !$0.holds }.map { $0.label } }
        func modelFails(_ changed: String) -> Bool { changed != modelRaw && !failing(modelPins(SourceScan.code(changed))).isEmpty }
        CT.check("unchanged, the feed pins and the model pins all hold", failing(feedPins(SourceScan.code(hooksRaw))) + failing(modelPins(SourceScan.code(modelRaw))), [])
        for nth in 0..<3 {
            let changed = commentedOut(hooksRaw, feedLine, nth: nth)
            CT.checkTrue("feed \(nth + 1) of 3 commented out: the feed pins fail", changed != hooksRaw && !failing(feedPins(SourceScan.code(changed))).isEmpty)
        }
        let noApprovalFeed = commentedOut(hooksRaw, feedLine, nth: 1)
        CT.checkTrue("the Claude App approval's feed commented out: the permission request's pin names it",
                     failing(feedPins(SourceScan.code(noApprovalFeed))).contains { $0.contains("processPermissionRequest") })
        CT.check("(the file as written still holds three of the line, so a substring pin over it passed)", count(feedLine, in: noApprovalFeed), 3)
        let noExpanded = commentedOut(modelRaw, "model.islandExpanded(mode == .expanded)")
        CT.checkTrue("islandExpanded(...) commented out in the mode sink: the model pins fail, the sink's order pin among them",
                     modelFails(noExpanded) && failing(modelPins(SourceScan.code(noExpanded))).contains { $0.contains("BEFORE") })
        CT.check("(the file as written still holds the call, so a substring pin over it passed)", noExpanded.contains("model.islandExpanded(mode == .expanded)"), true)
        CT.checkTrue("islandExpanded(false) hard-coded in the mode sink fails", modelFails(replaced(modelRaw, "model.islandExpanded(mode == .expanded)", "model.islandExpanded(false)")))
        CT.checkTrue("twoCats: false where the layout's inputs are read fails",
                     modelFails(replaced(modelRaw, "twoCats: CatSettingsStore.shared.display.mode == .two)", "twoCats: false)")))
        CT.checkTrue("twoCats: false passed to the one refreshLayout call fails", modelFails(replaced(modelRaw, "twoCats: i.twoCats", "twoCats: false")))
        CT.checkTrue("a literal twoCats in the mode sink fails",
                     modelFails(replaced(modelRaw, "model.refreshFromApp { $0.expanded = mode == .expanded }", "model.refreshFromApp { $0.expanded = mode == .expanded; $0.twoCats = false }")))
        CT.checkTrue("the display sink assigning a literal fails", modelFails(replaced(modelRaw, "$0.twoCats = display.mode == .two", "$0.twoCats = false")))
        CT.checkTrue("the display sink commented out fails", modelFails(commentedOut(modelRaw, "model.refreshFromApp { $0.twoCats = display.mode == .two }")))
        let pausedProblems = { (changed: String) in timelineProblems(["ProjectsViews.swift": SourceScan.code(changed)], expected: 3) }
        CT.check("unchanged, the three TimelineViews all pause on active or animate", pausedProblems(viewsRaw), [])
        CT.checkTrue("a TimelineView whose pause is `false` fails", !pausedProblems(replaced(viewsRaw, "paused: !active)", "paused: false)")).isEmpty)
        CT.checkTrue("a TimelineView with no pause at all fails", !pausedProblems(replaced(viewsRaw, ", paused: !animate)", ")")).isEmpty)
        CT.checkTrue("a pause on something else fails", !pausedProblems(replaced(viewsRaw, "paused: !active || subagents.isEmpty", "paused: subagents.isEmpty")).isEmpty)
        CT.checkTrue("a fourth TimelineView fails the count", !pausedProblems(viewsRaw + "\nTimelineView(.animation) { _ in }\n").isEmpty)
        CT.checkTrue("a commented-out TimelineView is not counted", pausedProblems(viewsRaw + "\n// TimelineView(.animation) { _ in }\n").isEmpty)
        CT.checkTrue("repeatForever, a Timer and onReceive(Timer in code are hits; the same words in a comment are not",
                     !bannedHits(SourceScan.code(viewsRaw + "\nlet a = Animation.linear.repeatForever()\n")).isEmpty && !bannedHits(SourceScan.code(viewsRaw + "\nlet t = Timer.publish(every: 1, on: .main, in: .common)\n")).isEmpty
                        && bannedHits(SourceScan.code(viewsRaw + "\n// repeatForever Timer onReceive(Timer\n")).isEmpty)
        CT.checkTrue("the type extractor follows a grown type and stops at its brace: a line added inside ProjectPill is in its text, ProjectMoreCell's is not",
                     SourceScan.structText("struct ProjectPill: View {", in: SourceScan.code(replaced(viewsRaw, "struct ProjectPill: View {", "struct ProjectPill: View {\n    var added = \"MARKER\""))).map { $0.contains("MARKER") && !$0.contains("struct ProjectMoreCell") } ?? false)

        CT.finish()
    }
}
