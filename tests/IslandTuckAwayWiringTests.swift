import Foundation

// Source pins for Tuck the island away, where no test program can compile the app's files (the panel, AppState and the Settings view need the whole app).
// Each says where a call must be, so a missed call site fails here and not on the owner's screen. Run from the repository root through scripts/test-island-tuck-away-wiring.sh.

@main
enum IslandTuckAwayWiringTests {
    static func source(_ file: String) -> String { (try? String(contentsOfFile: "NotchBuddy/Sources/App/\(file)", encoding: .utf8)) ?? "" }
    static func count(_ needle: String, in text: String) -> Int { text.components(separatedBy: needle).count - 1 }

    @MainActor static func main() {
        let rules = source("IslandTuckAway.swift"), fsm = source("IslandStateMachine.swift"), controller = source("IslandWindowController.swift")
        let app = source("AppState.swift"), sidekick = source("Sidekick.swift"), settings = source("SettingsGeneralPage.swift"), sections = source("SettingsSections.swift")
        CT.section("the sources were read")
        CT.checkTrue("the six files are there", rules.contains("enum IslandTuckAway") && fsm.contains("final class IslandStateMachine") && controller.contains("final class IslandWindowController") && app.contains("final class AppState") && sidekick.contains("final class Sidekick") && settings.contains("struct GeneralSettingsTab"))

        CT.section("the rule is pure: Foundation only, no timer, no clock of its own")
        CT.checkTrue("IslandTuckAway.swift imports only Foundation", rules.contains("import Foundation") && !rules.contains("import AppKit") && !rules.contains("import SwiftUI") && !rules.contains("import Combine") && !rules.contains("import QuartzCore"))
        CT.checkTrue("and starts nothing", !rules.contains("Timer") && !rules.contains("DispatchQueue") && !rules.contains("asyncAfter") && !rules.contains("NSEvent") && !rules.contains("Date()"))

        CT.section("the state machine: the old sixty-second hide is gone, and one one-shot timer is armed in one place")
        CT.check("the fixed sixty-second hide is removed", count("petitToHiddenDelay", in: fsm), 0)
        CT.check("the tuck-away timer is armed in exactly one place", count("armTuck(delay, item)", in: fsm), 1)
        CT.checkTrue("no repeating timer in the state machine", !fsm.contains("repeats: true") && !fsm.contains("scheduledTimer"))
        CT.checkTrue("the state machine reads the rule with its own clock, the setting and the live flag", fsm.contains("IslandTuckAway.hideDelay(tuckAway, lastActivity: lastActivity, now: now(), live: live)"))
        CT.checkTrue("the default is never, and an activity time starts at the launch", fsm.contains("var tuckAway: IslandTuckAway.Choice = .never") && fsm.contains("lastActivity = clock()"))
        CT.checkTrue("a compact island that comes up starts its timer, from the transition itself", fsm.contains("if new == .petit { scheduleTuck() }"))
        CT.checkTrue("the wing fold and the pointer leaving both go through mouseLeft, which only re-arms the one timer", fsm.contains("func mouseLeft() {\n        pointerInside = false"))
        CT.checkTrue("no timer is armed while a hold stands (scheduleTuck's guard), and the one timer is re-armed on a release", fsm.contains("guard state == .petit, !pointerInside, !(isHeldOpen?() ?? false),") && fsm.contains("func scheduleTuck() {") && !fsm.contains("func holdChanged"))
        CT.checkTrue("the state machine has no repeating timer", !fsm.contains("repeats: true") && !fsm.contains("scheduledTimer"))

        CT.section("the hold release: the controller calls scheduleTuck when a hold flips, read after the change, and when the shelf's hold ends by time")
        CT.check("scheduleTuck is called from the two places a hold can release: the flip and the shelf's end", count("fsm.scheduleTuck()", in: controller), 2)
        CT.checkTrue("the hold is watched through the app's change notice, read on the next main-queue turn, and written only when it flips", controller.contains("holdSubscription = state.objectWillChange") && controller.contains(".receive(on: DispatchQueue.main)") && controller.contains("self?.fsm.isHeldOpen?() == true") && controller.contains(".removeDuplicates()"))
        CT.checkTrue("the shelf's hold ends by time with no published change: its start is watched, and one one-shot timer is armed at the picker's end", controller.contains("sharePickerSubscription = state.$sharePickerSince") && controller.contains("armShelfHoldEnd(") && controller.contains("ShelfHold.releaseDelay(pickerSince: since, now: ProcessInfo.processInfo.systemUptime)"))
        CT.checkTrue("that timer is one item, cancelled and replaced on each change, and no repeating timer", controller.contains("private var shelfHoldEnd: DispatchWorkItem?") && controller.contains("shelfHoldEnd?.cancel()") && !controller.contains("repeats: true") && !controller.contains("scheduledTimer"))

        CT.section("the activity: every hook event and alert (touchPill) reaches the state machine, and nothing else does")
        CT.check("touchPill sends the activity once", count("agentActivity.send()", in: app), 1)
        CT.checkTrue("the activity subject is on AppState and is not published", app.contains("let agentActivity = PassthroughSubject<Void, Never>()"))
        CT.checkTrue("the controller feeds each activity to the state machine", controller.contains("agentActivitySubscription = state.agentActivity.sink { [weak self] in self?.fsm.agentActivity() }"))
        CT.check("the controller calls agentActivity exactly once", count("fsm.agentActivity()", in: controller), 1)

        CT.section("live: only a pill working or waiting, changes only through setLive; an idle open session does not count, so the sidekick's ledger is not read here")
        CT.checkTrue("the live state is the rule's, of the pills' raw states alone", controller.contains("IslandTuckAway.isLive(pillStates: tasks.map { $0.state.rawValue })"))
        CT.checkTrue("it is read from the tasks, and written only when it changes", controller.contains("liveSubscription = state.$tasks") && controller.contains(".removeDuplicates()") && controller.contains("self?.fsm.setLive(live)"))
        CT.checkTrue("the sidekick's live publisher is gone (it was used only by the live rule)", !sidekick.contains("liveAgentsPublisher") && !controller.contains("liveAgentsPublisher"))
        CT.check("setLive is called from one place", count("fsm.setLive(", in: controller), 1)

        CT.section("the setting: stored under island.tuckAway, cleaned on load, shown in General → Behavior, and handed to the state machine")
        CT.checkTrue("AppState publishes it and saves it under the key", app.contains("@Published var tuckAway: IslandTuckAway.Choice = .never") && app.contains("UserDefaults.standard.set(tuckAway.rawValue, forKey: IslandTuckAway.defaultsKey)"))
        CT.checkTrue("AppState reads it through the cleaning rule", app.contains("tuckAway = IslandTuckAway.choice(stored: ud.string(forKey: IslandTuckAway.defaultsKey))"))
        CT.checkTrue("the controller hands the setting to the state machine at start and on every change", controller.contains("fsm.tuckAway = state.tuckAway") && controller.contains("tuckAwaySubscription = state.$tuckAway.sink { [weak self] choice in self?.fsm.tuckAway = choice }"))
        CT.checkTrue("the row is in General → Behavior, a picker with the five choices", settings.contains("SettingRow(\"Tuck the island away\"") && settings.contains("Picker(\"\", selection: model.tuckAway)") && sections.contains("tuckAway: $state.tuckAway") && settings.contains(".tag(IslandTuckAway.Choice.never)") && settings.contains(".tag(IslandTuckAway.Choice.m30)"))
        CT.checkTrue("the picker sits in the Behavior group, after Hover glow", settings.range(of: "SettingRow(\"Tuck the island away\"").map { r in settings.range(of: "SwitchRow(\"Hover glow\"").map { $0.lowerBound < r.lowerBound } ?? false } ?? false)

        CT.section("a click on the island counts as activity: the island's press reaches the state machine through userInteracted, which starts with agentActivity")
        CT.checkTrue("userInteracted starts the count before anything else", fsm.contains("func userInteracted() {\n        agentActivity()"))
        CT.checkTrue("the island's press calls userInteracted", controller.contains("self.fsm.userInteracted()"))
        CT.checkTrue("on the Mac that press is the left button only (the monitor is for leftMouseDown), so the click counts for the primary button alone", controller.contains("NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in"))
        CT.checkTrue("the Settings help says the click counts, and no longer says a session is open", settings.contains("this long has passed since the last hook event, alert or click on the island. Never keeps it up.") && !settings.contains("no session is open"))

        CT.section("the dead absence row is gone: the Settings row, its binding and the AppState setting (the stored key on disk is left alone)")
        CT.checkTrue("no 'Hide after … min without movement' row, no binding", !settings.contains("without movement") && !settings.contains("absenceMinutes") && !settings.contains("absenceInterval"))
        CT.checkTrue("AppState has no absence setting and reads no absence key", !app.contains("absenceInterval"))

        CT.section("the wing swoosh is untouched by this")
        CT.checkTrue("the wing's rules and its poll call are as they were", controller.contains("let wing = wingYield.step(now: CACurrentMediaTime(), zone: wingActive ? wings.zone(of: local) : nil, active: wingActive,"))

        CT.finish()
    }
}
