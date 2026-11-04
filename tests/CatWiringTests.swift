import Foundation

// Source pins for the app files no test program can compile (HookServer, AppState and the SwiftUI views need the whole app). Each says where a call must be, so a
// missed call site fails here and not on the owner's screen. Run from the repository root.

@main
enum CatWiringTests {
    static func source(_ file: String) -> String { (try? String(contentsOfFile: "NotchBuddy/Sources/App/\(file)", encoding: .utf8)) ?? "" }
    static func count(_ needle: String, in text: String) -> Int { text.components(separatedBy: needle).count - 1 }
    /// The offset of the first `needle`, or -1.
    static func at(_ needle: String, in text: String) -> Int { text.range(of: needle)?.lowerBound.utf16Offset(in: text) ?? -1 }

    @MainActor static func main() {
        CT.section("each pill's last event: every hook event the pill gets touches it (Two cats mode's busiest-other rule reads it)")
        let hook = source("HookServer.swift"), app = source("AppState.swift")
        CT.checkTrue("the sources were read", hook.contains("final class HookServer") && app.contains("final class AppState"))
        CT.check("the event, the permission request and the question request each touch their pill", count("state.touchPill(", in: hook), 3)
        CT.checkTrue("an event touches its pill before a pending approval can end the handling early", at("state.touchPill(agentId)", in: hook) > 0 && at("state.touchPill(agentId)", in: hook) < at("case .holds: return", in: hook))
        CT.checkTrue("AppState keeps the times in a dictionary that is not published by itself: it announces a change only when an event reorders the agents' list in Settings, before it records the time", app.contains("var pillLastEvent: [String: Double] = [:]") && !app.contains("@Published var pillLastEvent") && app.contains("if CatAgentList.touchReorders(pillLastEvent, id: id) { objectWillChange.send() }") && app.contains("objectWillChange.send() }\n        pillLastEvent[id] = ms"))
        CT.checkTrue("on the clock the sleep timer and the engines use", app.contains("func touchPill(_ id: String, at ms: Double = CACurrentMediaTime() * 1000)"))

        CT.section("Settings → Cat: four tabs (Look, Outfits, Personality, Agents' cats), the character is the Main cat, and the app hosts the section with the agents the island has")
        let view = source("CatSettingsView.swift"), settings = source("SettingsSections.swift") + source("SettingsView.swift"), section = source("CatSettingsSection.swift"), preview = source("CatDisplayPreview.swift")
        CT.checkTrue("the sources were read", view.contains("struct CatSettingsView") && settings.contains("struct SettingsView") && section.contains("CatSettingsSection") && preview.contains("DisplayPreviewView"))
        CT.checkTrue("the group is titled Main cat, and nothing is titled Character any more", view.contains("SettingsCard(\"Main cat\")") && !view.contains("GroupBox(\"Main cat\")") && !view.contains("GroupBox(\"Character\")"))
        CT.checkTrue("the tabs come in order: Look holds the Main cat, then Outfits, Personality and Agents' cats (Display, the pair or the agents' list)", at("if shows(.look) {", in: view) > 0 && at("characterGroup\n", in: view) > at("if shows(.look) {", in: view) && at("if shows(.outfits)", in: view) > at("characterGroup\n", in: view) && at("if shows(.personality)", in: view) > at("if shows(.outfits)", in: view) && at("if shows(.agentCats) {", in: view) > at("if shows(.personality)", in: view) && at("displayGroup\n", in: view) > at("if shows(.agentCats) {", in: view) && at("pairGroup }", in: view) > at("displayGroup\n", in: view) && at("agentsGroup }", in: view) > at("pairGroup }", in: view))
        CT.checkTrue("CatSettingsView takes the tab (nil draws every group) and shows a group only on its tab", view.contains("tab: SettingsRoute.Tab? = nil") && view.contains("private func shows(_ t: SettingsRoute.Tab) -> Bool { tab == nil || tab == t }"))
        CT.checkTrue("the pair is shown only in Two cats mode and the agents' list only in A cat for each agent", view.contains("if store.display.mode == .two { pairGroup }") && view.contains("if store.display.mode == .perAgent { agentsGroup }"))
        CT.checkTrue("Settings hosts the section through CatSettingsSection, which reads the agents from AppState", settings.contains("CatSettingsSection(tab: tab ?? .look)") && section.contains("@ObservedObject private var app = AppState.shared") && section.contains("isAgentPill"))
        CT.checkTrue("the Display preview animates only while Settings is visible (paused unless active), at 30 fps", preview.contains("TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active))"))
        CT.checkTrue("and every Settings preview gets `active` from the window's visibility", count("active: active", in: view) >= 5)

        CT.section("A cat for each agent: a new agent pill gets its coat when it is created, and once at launch; the island reads the cast again when Settings changes it")
        let delegate = source("AppDelegate.swift"), cast = source("CatCast+App.swift")
        CT.checkTrue("the sources were read", delegate.contains("applicationDidFinishLaunching") && cast.contains("var cast: CatCast.Result"))
        CT.check("the pill creation sites in the hook server (a third-party agent, and a workspace pill) give a coat", count("giveCoat(to: id)", in: hook), 2)
        CT.check("the pill creation sites in AppState (addTask, loading the declared pills, switching one on) give a coat", count("giveCoat(to:", in: app), 3)
        CT.checkTrue("at launch every pill that exists gets its coat, after the store is made and before the island is set up", at("ensureAgentCats(for: AppState.shared.tasks.map(\\.id))", in: delegate) > at("_ = CatSettingsStore.shared", in: delegate) && at("ensureAgentCats(for: AppState.shared.tasks.map(\\.id))", in: delegate) < at("setupIsland()", in: delegate))
        CT.checkTrue("the cast reads the focused pill (focusTask), each pill's last event and the stored settings", cast.contains("focusId: focusTask?.id") && cast.contains("pillLastEvent[$0.id]") && cast.contains("store.display.agentCats") && cast.contains("store.settings.character"))
        CT.checkTrue("AppState watches the display settings and the Main cat, and not the sliders", app.contains("store.$display") && app.contains("$settings.map(\\.character).removeDuplicates()"))

        CT.section("every cat view takes its coat from the cast, one test per call site: nothing follows the Main cat on its own, so a per-agent coat is never overwritten")
        let sources = ((try? FileManager.default.contentsOfDirectory(atPath: "NotchBuddy/Sources/App")) ?? []).filter { $0.hasSuffix(".swift") }.sorted()
        let followers = sources.filter { source($0).contains("useCharacter(CatConfig.shared.character)") }
        CT.check("no file in the app still re-reads the Main cat each frame (\(sources.count) files)", followers, [])
        let canvas = source("BotCanvasView.swift"), island = source("IslandRootView.swift"), content = source("IslandViewContent.swift"), controller = source("IslandWindowController.swift")
        let greetingView = source("GreetingCanvasView.swift"), upload = source("UploadCanvasView.swift"), greeting = source("CatGreetingRenderer.swift")
        func lines(_ text: String, containing needle: String) -> [String] { text.components(separatedBy: "\n").filter { $0.contains(needle) } }
        CT.checkTrue("the big cat: the view has a `cat` and draws it (BotCanvasView)", canvas.contains("let cat: String") && canvas.contains("engine.useCharacter(cat)"))
        CT.check("the big cat: both BotPlacement branches pass the big cat's coat, which comes from the cast through the Projects rule (AppState.bigCatCoat starts from cast.big.cat)", count("BotCanvasView(state: state, cat: state.bigCatCoat", in: island), 2)
        CT.checkTrue("the pill cats: the view has a `cat`, draws it, and every MiniBotCanvasView( in the app is given one", canvas.contains("MiniBotCanvasView") && canvas.contains("engine.useCharacter(cat)   // the cast's coat for this pill") && (lines(content, containing: "MiniBotCanvasView(") + lines(island, containing: "MiniBotCanvasView(")).allSatisfy { $0.contains("cat:") })
        CT.checkTrue("the pills: the row and the music pill are given the cast's coat for their pill", content.contains("AgentPill(task: task, cat: pill.cat, state: state") && content.contains("MusicPill(task: task, cat: pill.cat, state: state") && content.contains("let cat: String"))
        CT.checkTrue("the row and the 2x2 grid are the cast's pills, and nothing filters the focused pill out by hand any more", content.contains("state.cast.pills") && island.contains("state.cast.pills") && !content.contains("filter { $0.id != state.focusId }") && !island.contains("filter { $0.id != state.focusId }"))
        CT.checkTrue("the greeting: the Main cat falls in and the session cats are the cast's", greetingView.contains("engine.useCharacter(greeting.cat)") && greetingView.contains("sessions: greeting.sessions") && greeting.contains("sessions: [String]? = nil"))
        CT.checkTrue("the drop view: given the cast's drop coat, and draws it", island.contains("UploadCanvasView(state: state, cat: state.cast.drop)") && upload.contains("let cat: String") && upload.contains("catEngine.useCharacter(cat)"))
        CT.checkTrue("the drag ghost: the cast's drop coat", controller.contains("BotCanvasView(state: AppState.shared, cat: AppState.shared.cast.drop)"))

        CT.section("Two cats: cat 1 moves and cat 2 appears in that mode only; One cat and A cat for each agent keep the layout that ships")
        let pair = source("PairCatViews.swift"), cast2 = source("CatCast+App.swift")
        CT.checkTrue("the sources were read", pair.contains("struct SecondCatPlacement") && island.contains("func botPosition"))
        CT.checkTrue("botPosition takes the display mode (One cat by default) and moves cat 1 only in Two cats mode: 30 pt in the compact island, 18 pt left in the overview", island.contains("display: CatDisplayMode = .one") && island.contains("CatIslandLayout.compactX(display)[0]") && island.contains("if display == .two && view == .overview"))
        CT.check("the three users of botPosition (the placement, the look-at and the slap's hit test) pass the display mode", count("display: state.displayMode", in: island) + count("display: state.displayMode", in: canvas) + count("display: s.displayMode", in: controller), 3)
        CT.check("cat 2 is placed once, beside the big cat, with the same mask and the same fade for the greeting and the upload view", count("SecondCatPlacement(state: state", in: island), 1)
        CT.checkTrue("cat 2 is drawn only when the cast has one (Two cats mode), and shows the agent's state, asleep with the big cat", pair.contains("if let second = cast.second") && pair.contains("(task?.state ?? .idle).shown(asleep: state.catAsleep)"))
        CT.checkTrue("tapping cat 2 focuses its agent, in the overview only", pair.contains("state.setFocus(id)") && pair.contains(".allowsHitTesting(!place.compact && task != nil)"))
        CT.checkTrue("the overview's text starts where CatIslandLayout says only when there is a cat 2, with the old paddings otherwise", content.contains("guard second != nil, let l = IslandConst.viewLayouts[.overview] else { return CGFloat(CatIslandLayout.oneTextLeading) }") && content.contains(".padding(.top, second == nil ? 6 : 4)") && content.contains(".padding(.top, second == nil ? 6 : 0)") && content.contains("if let second { secondLine(second) }"))
        let plan = source("ClaudePlanCardView.swift")
        CT.checkTrue("the overview moves its hosted cards (the integration card, the plan card, the diff card) right by CatIslandLayout's one shift, which is 0 without a cat 2", content.contains("CatIslandLayout.overviewCardShift(second: second != nil, botX: Double(l.botX))") && count(".padding(.leading, cardShift)", in: content) == 3 && content.contains("DiffCardView(diff: diff, onDismiss: { activeDiffId = nil })\n                        .padding(.leading, cardShift)") && content.contains("ClaudePlanCardView(usage: state.claudePlanUsage, stacked: cardShift > 0)\n                        .padding(.leading, cardShift)") && content.contains("})\n                        .padding(.leading, cardShift)"))
        CT.checkTrue("the plan card is stacked by the same fact as the shift (one rule: cardShift > 0), in its one call, and its default is the shipping layout", content.contains("ClaudePlanCardView(usage: state.claudePlanUsage, stacked: cardShift > 0)") && count("ClaudePlanCardView(", in: content) == 1 && plan.contains("var stacked: Bool = false") && count("var stacked: Bool = false", in: plan) == 2 && !content.contains("stacked: second"))
        CT.checkTrue("the shipping row keeps its 40 pt label, 50 pt bar, fixed-size reset label and the rows' paddings; its percent is on one line in CatIslandLayout's column (it was a literal 30 and wrapped '100%')", plan.contains(".frame(width: 40, alignment: .leading)") && plan.contains("Capsule()\n                        .fill(Color.white.opacity(0.08))\n                        .frame(width: 50, height: 4)") && plan.contains(".monospacedDigit()\n                    .lineLimit(1)\n                    .frame(width: CatIslandLayout.planPercentWidth, alignment: .trailing)\n                Image(systemName: \"arrow.clockwise\")") && !plan.contains(".frame(width: 30, alignment: .trailing)") && plan.contains("Image(systemName: \"arrow.clockwise\")\n                    .font(.system(size: 8))\n                    .foregroundColor(Color(hex: \"#6B7079\"))\n                Text(resetLabel(w))\n                    .font(.system(size: 10))\n                    .foregroundColor(Color(hex: \"#6B7079\"))\n                    .fixedSize()") && plan.contains(".padding(.leading, 108)\n            .padding(.trailing, 12)") && count(".padding(.leading, 108)", in: plan) == 2)
        CT.checkTrue("the header keeps its title on its line and its priority, lets the subtitle truncate in both layouts (no fixedSize), and has the rows' own right margin; the row picks its layout in one place", plan.contains(".lineLimit(1)\n                    .layoutPriority(1)\n                Text(subtitleText)") && plan.contains("Text(subtitleText)\n                    .font(.system(size: 11))\n                    .foregroundColor(Color(hex: \"#8E939C\"))\n                    .lineLimit(1)\n            }") && !plan.contains("fixedSize(horizontal: !stacked") && plan.contains(".padding(.leading, 108)\n            .padding(.trailing, CatIslandLayout.planRowsTrailing)") && plan.contains("if stacked { stackedRow } else { shippingRow }"))
        CT.check("the shipping 108 is untouched: the same number of paddings in IslandViewContent.swift (38) and ClaudePlanCardView.swift (2) as before the shift", [count(".padding(.leading, 108)", in: content), count(".padding(.leading, 108)", in: plan)], [38, 2])
        CT.checkTrue("both cats' badges stay clear of each other: cat 1's on its left, cat 2's on its right when expanded and on its left in the compact island", canvas.contains("} else if CatIslandLayout.secondBesideBig(state.displayMode, overview: state.view == .overview) {") && !canvas.contains("} else if state.displayMode == .two {") && count("options.badgeSide = -1", in: canvas) == 2 && pair.contains("options.badgeSide = compact ? -1 : 1"))
        CT.checkTrue("cat 1's badge is held inside the card where cat 2 is drawn beside it, by CatIslandLayout's one number, in the same branch as its flip and in no other", canvas.contains("options.badgeSide = -1                       // cat 1's badge sits on its left only where cat 2 is drawn beside it\n                    options.badgeLeftLimit = cx - CatIslandLayout.pairBadgeReach(cat1X: Double(restingPlace(state: state).botCx))") && count("badgeLeftLimit", in: canvas) == 1)
        let sheet = (try? String(contentsOfFile: "scripts/render-cats.swift", encoding: .utf8)) ?? ""
        CT.checkTrue("the contact sheet holds cat 1's badge by the same number, in the pair only (a nil limit otherwise)", sheet.contains("options.badgeLeftLimit = badgeLeft") && sheet.contains("badgeLeft: two ? ox + one.cat1X - CatIslandLayout.pairBadgeReach(cat1X: one.cat1X) : nil"))
        CT.checkTrue("cat 1's badge and cat 2's place use the same rule (CatIslandLayout.secondBesideBig), so the badge flips left only where cat 2 is drawn", pair.contains("guard CatIslandLayout.secondBesideBig(state.displayMode, overview: state.view == .overview) else { return nil }"))
        CT.checkTrue("the greeting hands the pair to the renderer, and the settled cat is where the pair's first cat lives", greetingView.contains("pair: greeting.pair?[1]") && greetingView.contains("botInset: CatIslandLayout.compactX(state.cast.mode)[0]"))
        CT.checkTrue("the display mode comes from Settings", cast2.contains("var displayMode: CatDisplayMode { CatSettingsStore.shared.display.mode }"))

        CT.section("Kittens: the hook server turns the subagent events into kitten events in both builds, the sleep timer sweeps, nothing runs by itself")
        let kittenApp = source("CatKittens+App.swift"), kittenHooks = source("CatKittenHooks.swift"), kittenCore = source("CatKittens.swift"), sleepApp = source("CatSleep+App.swift"), types = source("IslandTypes.swift")
        /// How many `#if` blocks are open at an offset of a file: 0 means the code is in every build (the App Store's included).
        func depth(_ text: String, at offset: Int) -> Int {
            guard offset >= 0 else { return -1 }   // the anchor is not there: not "in every build"
            var d = 0
            for line in String(text.utf16.prefix(offset))!.components(separatedBy: "\n") {
                let t = line.trimmingCharacters(in: .whitespaces)
                if t.hasPrefix("#if ") { d += 1 } else if t.hasPrefix("#endif") { d -= 1 }
            }
            return d
        }
        CT.checkTrue("the sources were read", kittenApp.contains("func kittenEvent") && kittenHooks.contains("enum CatKittenHooks") && kittenCore.contains("enum CatKittens") && sleepApp.contains("CatSleepClock"))
        CT.check("processEvent turns a hook event into a kitten event once, after the pill's last event and before a pending approval can end the handling", [count("CatKittenHooks.event(name: name, payload: payload", in: hook), at("CatKittenHooks.event(name: name, payload: payload", in: hook) > at("state.touchPill(agentId)", in: hook) ? 1 : 0, at("CatKittenHooks.event(name: name, payload: payload", in: hook) < at("case .holds: return", in: hook) ? 1 : 0], [1, 1, 1])
        CT.check("the events reach the pill the event belongs to (agentId), a permission request the pill that owns it (pillId)", [count("state.kittenEvent(agentId, kitten)", in: hook), count("state.kittenEvent(pillId, kitten)", in: hook)], [1, 1])
        CT.checkTrue("a request from a subagent is remembered in the approval (subagentId), and its kitten is resolved when the card is answered, dismissed or displaced", types.contains("var subagentId: String? = nil") && hook.contains("subagentId: askedBy") && count("resolveApprovalKitten(", in: hook) == 4)
        CT.checkTrue("the hook server's kitten calls are in every build: none sits inside an #if block (the App Store build installs SubagentStart and SubagentStop too)", ["CatKittenHooks.event(name: name, payload: payload", "CatKittenHooks.permission(payload: payload", "resolveApprovalKitten(state.pendingApproval)"].allSatisfy { depth(hook, at: at($0, in: hook)) == 0 })
        let removedPills = [("loadIntegrationTasks", "kittens[def.id] = nil"), ("toggleIntegration", "kittens[id] = nil"), ("removeTask", "kittens[id] = nil")].map { fn, line -> Int in
            let from = at("func \(fn)(", in: app)
            let rest = from >= 0 ? String(app.utf16.dropFirst(from))! : ""
            let body = rest.components(separatedBy: "\n    func ")[0]
            return count(line, in: body)
        }
        CT.check("every function that drops a catalog pill drops its kittens too (loadIntegrationTasks, toggleIntegration, removeTask)", removedPills, [1, 1, 1])
        CT.check("both installers (the GitHub build's and the App Store build's) list SubagentStart and SubagentStop", count("(\"SubagentStart\", 10), (\"SubagentStop\", 10)", in: hook), 2)
        CT.checkTrue("both relays forward the hook's payload whole (they add fields and remove none), so a subagent's agent_id and agent_type reach the island", count("s.sendall((json.dumps(payload)", in: hook) >= 4 && !hook.contains("payload.pop(") && !hook.contains("del payload[") && !hook.contains("payload.clear("))
        CT.checkTrue("the kitten files have no build condition at all", [kittenApp, kittenHooks, kittenCore].allSatisfy { !$0.contains("#if") })
        CT.checkTrue("the sleep timer's sweep: when the cat falls asleep the kittens whose stop never came go", sleepApp.contains("if asleep { app?.sweepKittens() }") && kittenApp.contains(".sweep(t: ms)"))
        CT.checkTrue("a pill that goes takes its kittens, and they are never stored", app.contains("kittens[id] = nil") && app.contains("@Published var kittens: [String: [CatKittens.Kitten]] = [:]") && !kittenApp.contains("UserDefaults") && !kittenCore.contains("UserDefaults"))
        CT.checkTrue("no timer and no polling anywhere in the kitten code: a farewell ends because the view stops drawing it", [kittenApp, kittenHooks, kittenCore].allSatisfy { !$0.contains("Timer") && !$0.contains("asyncAfter") && !$0.contains("DispatchWorkItem") && !$0.contains("Task {") })
        let sender = (try? String(contentsOfFile: "scripts/test-cat-kitten-hooks.sh", encoding: .utf8)) ?? ""
        CT.checkTrue("the tests send the scripted events to a socket of their own, never the app's", count("fake-subagent-events.py --scenario", in: sender) == 1 && sender.contains("--sock \"$SOCK_DIR/s\"") && !sender.contains("Application Support"))

        CT.section("Kittens are drawn at every place by one function, in their parent's coat, and a kitten is never given useCharacter")
        let layers = source("KittenViews.swift"), draw = source("CatKittenDraw.swift"), pillSource = content
        CT.checkTrue("the sources were read", layers.contains("struct KittenLayerView") && draw.contains("enum CatKittenDraw"))
        CT.checkTrue("no kitten file gives an engine useCharacter: a kitten's coat is its parent's as a kitten, made with CatPresets.kitten(of:), and a new engine when the parent's coat changes", !layers.contains("useCharacter(") && !draw.contains("useCharacter(") && draw.contains("CatPresets.kitten(of: CatPresets.byID(parentCat))") && draw.contains("e.coat == parentCat"))
        CT.checkTrue("every kitten has its own state badge, wears the parent's collar colour and blinks happily while it leaves", draw.contains("CatDrawOptions(badge: true)") && draw.contains("e.collar = colour") && draw.contains("(CatKittens.State(rawValue: k.state) ?? .working).catState"))
        CT.check("the big cat's and the pair's kittens are drawn by one placement in the island, with the same mask and the same fade as the cats", [count("KittenPlacement(state: state", in: island), count("CatIslandLayout.kittenParents(", in: layers)], [1, 1])
        CT.checkTrue("an agent pill draws its own kittens at its trailing end, and its title keeps clear of them", pillSource.contains("KittenLayerView(state: state, pills: [task.id], parentCat: cat, place: \"pill\", unit: 28, colour: task.color)") && pillSource.contains(".padding(.trailing, kittenReserve)"))
        CT.checkTrue("the \"+N\" is drawn at the overview's anchor (right of the last kitten) through CatIslandLayout.moreLabelLeft, and at moreAt otherwise", draw.contains("CatIslandLayout.moreLabelLeft(slots)") && count("x: origin.x + m.x * unit", in: draw) == 1)
        CT.checkTrue("the layers redraw with their canvas, pause when the island is hidden and run no timer of their own", layers.contains("paused: state.mode == .hidden") && ![layers, draw].contains { $0.contains("Timer") || $0.contains("asyncAfter") || $0.contains("DispatchWorkItem") })
        CT.checkTrue("the parent's coat reaches the layer from the cast (the big cat's, cat 2's and the pill's)", layers.contains("cat: spot.cat") && pillSource.contains("parentCat: cat"))
        CT.checkTrue("a layer with nothing to draw stops asking for frames (CatKittens.mayStop, on the frame it just drew and the lists it draws) and starts again when the kittens or its pills change", layers.contains("@State private var quiet = false") && layers.contains("paused: state.mode == .hidden || quiet") && layers.contains("herd.lastFrameEmpty = list.isEmpty") && layers.contains("CatKittens.mayStop(lastFrameEmpty: herd.lastFrameEmpty, lists: pills.map { state.kittens[$0] ?? [] }, now: CACurrentMediaTime() * 1000)") && layers.contains(".onChange(of: state.kittens) { _, _ in quiet = false }") && layers.contains(".onChange(of: pills) { _, _ in quiet = false }") && draw.contains("var lastFrameEmpty = false"))

        CT.finish()
    }
}
