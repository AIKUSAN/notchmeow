import Foundation

// Source pins for the desktop cat's app files, which no test program can compile (the controller, the panel, the island and the delegate need the whole app). Each says where a
// call must be, so a missed call site fails here and not on the owner's desktop. Run from the repository root.

@main
enum DesktopCatWiringTests {
    static func source(_ file: String) -> String { (try? String(contentsOfFile: "NotchBuddy/Sources/App/\(file)", encoding: .utf8)) ?? "" }
    static func count(_ needle: String, in text: String) -> Int { text.components(separatedBy: needle).count - 1 }

    @MainActor static func main() {
        let ctl = source("DesktopCatController.swift"), panel = source("DesktopCatPanel.swift"), island = source("IslandWindowController.swift"), root = source("IslandRootView.swift")
        let kittens = source("KittenViews.swift"), app = source("AppState.swift"), delegate = source("AppDelegate.swift"), view = source("CatSettingsView.swift"), store = source("CatSettingsStore.swift")
        let shortcuts = source("ShortcutLogic.swift")

        CT.section("the window: a floating, non-activating panel that is never key, on every Space, outside fullscreen and the window cycle, click-through until the mouse is over the body")
        CT.checkTrue("the sources were read", ctl.contains("final class DesktopCatController") && panel.contains("final class DesktopCatPanel"))
        CT.checkTrue("borderless and non-activating, floating, never key or main", panel.contains("styleMask: [.borderless, .nonactivatingPanel]") && panel.contains("level = .floating") && panel.contains("override var canBecomeKey: Bool { false }") && panel.contains("override var canBecomeMain: Bool { false }"))
        CT.checkTrue("every Space, not the window cycle, and NOT a fullscreen auxiliary (it steps aside over a fullscreen app)", panel.contains("[.canJoinAllSpaces, .stationary, .ignoresCycle]") && !panel.contains("fullScreenAuxiliary]") && !panel.contains(".fullScreenAuxiliary,"))
        CT.checkTrue("click-through to begin with, and it does not hide when the app deactivates", panel.contains("ignoresMouseEvents = true") && panel.contains("hidesOnDeactivate = false"))
        CT.checkTrue("the panel accepts mouse-moved events, so the local monitor sees moves over it and can give the mouse back outside the body", panel.contains("acceptsMouseMovedEvents = true"))
        CT.checkTrue("the body decides: the panel takes the mouse only over `hits`, or while dragging", ctl.contains("DesktopCatLayout.hits(rel") && ctl.contains("panel?.ignoresMouseEvents = !(over || dragging)"))
        CT.checkTrue("the marker is in the binary of every build: no #if around the panel", panel.contains("static let marker = \"NM_DESKTOP_CAT_PANEL\"") && !panel.contains("#if"))
        CT.checkTrue("the panel may sit above the screen's top edge at the notch spot: constrainFrameRect returns the frame unchanged, as the island's panel does", panel.contains("override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect") && panel.contains("return frameRect"))

        CT.section("nothing polls: one timer at the rule's rate, the mouse monitors only while the cat is drawn and visible, one-shots for the click and for a flight that ends unseen")
        CT.checkTrue("only a change of the target re-arms the one timer (DesktopCatPacer)", ctl.contains("switch pacer.target(fps)") && count("DispatchSource.makeTimerSource", in: ctl) == 1)
        CT.checkTrue("and the target comes from desktopFps", ctl.contains("arm(DesktopCatTrip.fps(input))"))
        CT.checkTrue("no Timer, no CADisplayLink and no sleeping loop", !ctl.contains("Timer.scheduledTimer") && !ctl.contains("CADisplayLink") && !ctl.contains("usleep") && !ctl.contains("Thread.sleep"))
        CT.checkTrue("the mouse monitors are mouse-moved event monitors, added only when the cat is drawn and not hidden, and removed otherwise", ctl.contains("matching: [.mouseMoved, .leftMouseDragged]") && ctl.contains("let want = phase.drawn") && ctl.contains("NSEvent.removeMonitor"))
        CT.checkTrue("from the frame-rate rule on, the monitors also stop while the cat is hidden", ctl.contains("let want = phase.drawn && !visibility.hidden"))
        CT.checkTrue("a frame is skipped, not made, when the cat is not drawn", ctl.contains("guard phase.drawn else { return }") && count("guard phase.drawn", in: ctl) >= 2)
        CT.checkTrue("a slow frame does not slow the cat down: dt is held to 0.25 s, not the island's 0.05 s", count("maxDt: 0.25", in: ctl) == 2)
        CT.checkTrue("the Debug-only cat panel has a Desktop section, compiled out of Release and App Store, with its own marker", source("CatDevPanel.swift").contains("DesktopCatDevView()") && source("DesktopCatDevPanel.swift").contains("#if DEBUG && !APPSTORE") && source("DesktopCatDevModel.swift").contains("#if DEBUG && !APPSTORE") && source("DesktopCatDevModel.swift").contains("static let marker = \"NM_CAT_DEV_DESKTOP\""))
        CT.checkTrue("hidden is the screens asleep, the session locked or the window covered: the first two come from the shared PresenceMonitor, which observes the Mac's notifications once", source("PresenceMonitor.swift").contains("screensDidSleepNotification") && source("PresenceMonitor.swift").contains("com.apple.screenIsLocked") && ctl.contains("PresenceMonitor.shared.subscribe(\"desktopCat\")") && !ctl.contains("screensDidSleepNotification") && !ctl.contains("com.apple.screenIsLocked") && ctl.contains("occlusionState.contains(.visible)"))
        let showBody = ctl.components(separatedBy: "private func show()").dropFirst().first?.components(separatedBy: "private func hide()").first ?? ""
        CT.checkTrue("show() re-reads the panel's real occlusion state a turn later (AppKit updates it asynchronously) and retargets", showBody.contains("DispatchQueue.main.async") && showBody.contains("occlusionState.contains(.visible)") && showBody.contains("visibilityChanged()"))

        CT.section("the trip: every event goes through desktopStep, and what Settings stores is the phase's `on`")
        CT.checkTrue("one entry point into the machine", ctl.contains("DesktopCatTrip.step(phase, event)") && count("DesktopCatTrip.step(", in: ctl) == 1)
        CT.checkTrue("the stored switch follows the phase, so quitting mid-flight home leaves the cat home", ctl.contains("if phase.on != was.on { store.setDesktopOn(phase.on) }"))
        CT.checkTrue("the menu item and ⌃⌥D toggle through the store: the store's switch against the phase", ctl.contains("func toggle() { store.setDesktopOn(!phase.on) }"))
        CT.checkTrue("and the Settings switch is the same toggle: the store's switch against the phase", ctl.contains("if d.on == store.desktop.on, d.on != phase.on { send(.toggle) }"))
        CT.checkTrue("an approval, a question, a chat's approval card or a pill in approval or question state turns into alertOn and alertOff, only on a change", ctl.contains("DesktopCatTrip.alert(pendingApproval: state.pendingApproval != nil, pendingQuestion: state.pendingQuestion != nil, chatApproval: chat") && ctl.contains("let chat = state.chatApproval != nil") && ctl.contains("state.tasks.map { CatState(rawValue: $0.state.rawValue) ?? .idle }") && ctl.contains("guard let self, self.alerting != self.lastAlert else { return }") && ctl.contains("send(self.lastAlert ? .alertOn : .alertOff)"))
        CT.checkTrue("the chat's approval is behind #if !APPSTORE (the App Store build has no chat engine)", ctl.contains("#if !APPSTORE\n        let chat = state.chatApproval != nil\n        #else\n        let chat = false"))
        CT.checkTrue("the surprised emote comes first, then the flight starts after it", ctl.contains("emote(.surprised)") && ctl.contains("startMs: now + Self.surpriseMs"))
        CT.checkTrue("a turn keeps the flight's clock (turned), the notch end follows the island every frame, the screens move the desktop end", ctl.contains(".turned(at: now)") && ctl.contains("f.withNotchEnd(notchSpot())") && ctl.contains("f.withDesktopEnd(s)"))
        CT.checkTrue("a cat that was out flies out again once the greeting is over", ctl.contains("$0.0 != .greeting && !$0.1") && ctl.contains("send(.launch)"))
        CT.checkTrue("a click acts one double-click interval later, a double-click sends it home, a release on the island sends it home", ctl.contains("DesktopCatClicks(interval: NSEvent.doubleClickInterval)") && ctl.contains("case .doubleClick:") && ctl.contains("if onIsland(p) { send(.sendHome) } else { send(.move(drop)) }"))
        let observerBody = ctl.components(separatedBy: "NSApplication.didChangeScreenParametersNotification) { [weak self] in").dropFirst().first?.components(separatedBy: "let ws = ").first ?? ""
        CT.checkTrue("the screens observer re-resolves the cached spot from the store before it sends screensChanged, so no later event reads a spot for screens that are gone", observerBody.components(separatedBy: "send(.screensChanged)").first?.contains("self.spot = self.store.desktop.spot(on: self.screens)") == true && observerBody.contains("send(.screensChanged)"))
        let flyOutBody = ctl.components(separatedBy: "case .flyOut:").dropFirst().first?.components(separatedBy: "case .flyHome:").first ?? ""
        CT.checkTrue("a flight out reads the store's spot for the screens now, never the cache: ensureSpot is gone", flyOutBody.contains("store.desktop.spot(on: screens)") && !ctl.contains("ensureSpot"))
        let sendBody = ctl.components(separatedBy: "func send(_ event: DesktopEvent) {").dropFirst().first?.components(separatedBy: "private func perform(").first ?? ""
        CT.checkTrue("a phase change away from the desktop ends a drag and the pending click, so no mouse-up is waited for", sendBody.contains("if phase != .onDesktop { dragging = false; clickItem?.cancel() }"))
        let hideBody = ctl.components(separatedBy: "private func hide() {").dropFirst().first?.components(separatedBy: "/// The window around the cat").first ?? ""
        CT.checkTrue("hide() clears a drag and the pending click too: an order-out under a held mouse sends no mouse-up", hideBody.contains("dragging = false") && hideBody.contains("clickItem?.cancel()"))
        let notchBody = ctl.components(separatedBy: "private func notchSpot() -> DesktopSpot {").dropFirst().first?.components(separatedBy: "private func refreshScreens()").first ?? ""
        CT.checkTrue("the notch spot is on the island's own screen (the island never moves), not the focused one", notchBody.contains("island?.window?.screen ??") && !notchBody.contains("NSScreen.main"))

        CT.section("the notch's spot is empty while the cat is out: the cat, its kittens and its hit area; nothing else of the island changes")
        CT.checkTrue("AppState publishes the phase", app.contains("@Published var desktopPhase = DesktopPhase.home"))
        CT.checkTrue("the big cat's place draws nothing while the notch is empty (and is the shipping view otherwise)", root.contains("if !state.desktopPhase.notchEmpty { catSpot }") && count("BotCanvasView(state: state, cat: state.bigCatCoat", in: root) == 2)
        CT.checkTrue("its kittens go with it, and the pair's count holds cat 2's only", kittens.contains("!($0.cat == 0 && state.desktopPhase.notchEmpty && !$0.countsBoth)") && kittens.contains("let bigPill = state.desktopPhase.notchEmpty ? nil : cast.big.pill"))
        CT.checkTrue("the slap and the drag start cannot hit an empty spot", island.contains("guard !s.desktopPhase.notchEmpty else { return false }"))

        CT.section("the drag: a window attaches as before, empty desktop places the cat, and the App Store build has no attach")
        CT.checkTrue("the drop goes through DesktopCatDrop", island.contains("DesktopCatDrop.decide(point:") && island.contains("self.finishBotDrag(at: mouse)"))
        CT.checkTrue("the attach is the code that shipped, inside #if !APPSTORE", island.contains("state.promptContext = ctx") && island.contains("ClaudeService.shared.clearConversation(state: state)") && island.contains("expand(to: .prompt)"))
        CT.checkTrue("the window under the cursor is asked first and its context only when there is one", island.contains("let windowUnder = windowBoundsAtScreenPoint(mouse) != nil") && island.contains("let context = windowUnder ? windowContextAtPoint(mouse) : nil"))
        CT.checkTrue("a place sends dragOut to the desktop cat, and a click opens the island", island.contains("desktop?.dragOut(to: spot)") && island.contains("func openFromDesktop()"))
        CT.checkTrue("⌃⌥D toggles it", island.contains("desktop?.toggle()"))
        CT.checkTrue("the App Store flag comes from the build", ctl.contains("static let isAppStoreBuild = true") && ctl.contains("static let isAppStoreBuild = false"))

        CT.section("the app makes the cat once, after the island, and Settings and the store know it")
        CT.checkTrue("AppDelegate makes it after the island is set up and starts it", delegate.contains("DesktopCatController(island: island)") && delegate.contains("island.desktop = cat") && delegate.contains("cat.start()"))
        CT.checkTrue("the store holds the desktop settings and cleans them", store.contains("@Published private(set) var desktop: DesktopCatSettings") && store.contains("DesktopCatSettings.clean(next.json)"))
        CT.checkTrue("Settings has the switch under the Display picker, bound to the store", view.contains("desktopGroup") && view.contains("SwitchRow(\"Cat on the desktop\"") && view.contains("store.setDesktopOn($0)"))
        CT.checkTrue("the Desktop note keeps the dance in the GitHub build and leaves it out of the App Store build (which has no dance)", view.contains("HelpText(desktopNote)") && view.contains("#if !APPSTORE\n        let moves = \"It watches the cursor, dances to music and sleeps\"\n        #else\n        let moves = \"It watches the cursor and sleeps\"\n        #endif"))
        CT.checkTrue("the action is appended, never inserted, and handled", shortcuts.contains("case desktop ") && island.contains("case .desktop:"))
        CT.section("the file catch: a file on its way into the island is an alert to the cat, the catch draws no cat of its own while the desktop cat is out, and a drop waits for the cat")
        let drop = source("FileDropView.swift"), canvas = source("UploadCanvasView.swift")
        CT.checkTrue("the controller feeds the drop flow to the alert rule, with the approvals", ctl.contains("pillStates: state.tasks.map { CatState(rawValue: $0.state.rawValue) ?? .idle }, fileCatch: fileCatching, transferOffer: state.linkOfferPending)") && ctl.contains("state.fileDragOver || (UploadSequenceEngine.shared.isActive && state.mode == .expanded && [IslandView.upload, .uploading, .choose].contains(state.view))"))
        CT.checkTrue("the catch canvas draws no cat while the notch spot is empty", canvas.contains("if state.desktopPhase.notchEmpty { return nil }"))
        CT.checkTrue("a drop waits for the cat before anything is written or played, and checks its token and its flow after the wait", drop.contains("let waited = !DesktopCatTrip.catchReady(state.desktopPhase)\n        await waitForCat(state: state)\n        guard !waited || live() else {"))
        CT.checkTrue("the flow check is `live()`, declared before the wait so the wait can use it", (drop.range(of: "func live() -> Bool { drops.isCurrent(drop) && UploadSequenceEngine.shared.isActive }")?.lowerBound ?? drop.endIndex) < (drop.range(of: "await waitForCat(state: state)")?.lowerBound ?? drop.startIndex))
        CT.checkTrue("a wait that ends with the flow closed clears the drag state, but only for this drop (a newer drag is not disturbed)", drop.contains("guard !waited || live() else {\n            // The flow closed during the wait") && drop.contains("            if drops.isCurrent(drop) { state.fileDragOver = false }\n            return\n        }"))
        CT.checkTrue("the wait is the contract's: the cat is ready, for at most the catch wait", drop.contains("DesktopCatTrip.catchReady(state.desktopPhase)") && drop.contains("DesktopCatTrip.catchWaitMs"))
        CT.checkTrue("the wait comes before `fileDragOver` is cleared, so the alert holds and the cat does not turn round", (drop.range(of: "await waitForCat(state: state)")?.lowerBound ?? drop.endIndex) < (drop.range(of: "state.fileDragOver = false")?.lowerBound ?? drop.startIndex))
        CT.checkTrue("nothing new polls: no Timer in the drop handler", !drop.contains("Timer.") && !drop.contains("DispatchSource"))
        CT.finish()
    }
}
