import Foundation

// Source pins for the compact island stepping aside for the pointer on either wing, where no test program can compile the app's files (the panel, AppState and the SwiftUI view need the whole app).
// Each says where a call must be, so a missed call site fails here and not on the owner's screen. Run from the repository root through scripts/test-island-wing-wiring.sh.

@main
enum IslandWingWiringTests {
    static func source(_ file: String) -> String { (try? String(contentsOfFile: "NotchBuddy/Sources/App/\(file)", encoding: .utf8)) ?? "" }
    static func count(_ needle: String, in text: String) -> Int { text.components(separatedBy: needle).count - 1 }
    /// The offset of the first `needle`, or -1.
    static func at(_ needle: String, in text: String) -> Int { text.range(of: needle)?.lowerBound.utf16Offset(in: text) ?? -1 }

    @MainActor static func main() {
        let controller = source("IslandWindowController.swift"), island = source("IslandRootView.swift"), app = source("AppState.swift"), rules = source("IslandWing.swift")
        CT.section("the sources were read")
        CT.checkTrue("the four files are there", controller.contains("final class IslandWindowController") && island.contains("struct IslandContainer") && app.contains("final class AppState") && rules.contains("enum IslandWing"))

        CT.section("the rules are pure: no timer, no monitor, no AppKit, no clock of their own")
        CT.checkTrue("IslandWing.swift imports only CoreGraphics and Foundation", rules.contains("import CoreGraphics") && rules.contains("import Foundation") && !rules.contains("import AppKit") && !rules.contains("import SwiftUI"))
        CT.checkTrue("and starts nothing", !rules.contains("Timer") && !rules.contains("DispatchQueue") && !rules.contains("NSEvent") && !rules.contains("CACurrentMediaTime") && !rules.contains("Date()"))

        CT.section("the panel: one step per poll tick, fed by the poll's own pointer and clock, and no new timer or monitor")
        CT.check("the controller holds one wing memory", count("private var wingYield = IslandWing.Yield()", in: controller), 1)
        CT.check("and steps it in exactly one place, from the poll", count("wingYield.step(", in: controller), 1)
        CT.checkTrue("an alert cancels the step-aside: a card or question waiting, a file on its way in, the shelf's hold, the desktop cat away from home, the Wardrobe menu open on the big cat", controller.contains("let wingAlert = decisionWaiting || state.fileDragOver || state.shelfHoldsIsland || state.desktopPhase != .home || wardrobeMenuOpen"))
        CT.checkTrue("the step is given the active rule (with the alert), BOTH wings (the full island's frame, with the hover area's slop), the clock and the button state", controller.contains("IslandWing.isActive(compact: state.mode == .compact, greetingTail: state.greetingTail, dragging: inAttachDrag || attachDragStart != nil, alert: wingAlert)") && controller.contains("IslandWing.wings(island: islandRect, notchWidth: notchW, slop: hoverRect.maxX - islandRect.maxX)") && controller.contains("zone: wingActive ? wings.zone(of: local) : nil") && controller.contains("now: CACurrentMediaTime()") && controller.contains("buttonDown: { NSEvent.pressedMouseButtons != 0 }"))
        CT.checkTrue("the left wing's 0.4 s dwell and the any-button cancel come from the poll alone: the dwell is the rules' own clock reading, and the button state is every mouse button (a right-click on the big cat still opens the Wardrobe menu)", controller.contains("buttonDown: { NSEvent.pressedMouseButtons != 0 }") && controller.contains("matching: .rightMouseDown") && controller.contains("self.showWardrobeMenu(for: event)") && controller.contains("wingYield.step(now: CACurrentMediaTime(), zone:") && rules.contains("static let leftDwell: TimeInterval = 0.4"))
        CT.checkTrue("the zones are the full island's: the island's frame for the hover test is `islandSize`'s, never the shrunk width", controller.contains("let islandRect = panel.currentIslandFrame(nw: notchW, nh: notchH)") && !controller.contains("shownWidth"))
        CT.checkTrue("the poll publishes the fold only when it changes", controller.contains("if state.wingYielded != wing.faded { state.wingYielded = wing.faded }"))
        CT.checkTrue("the pointer over a wing of the folded island is not the island's: hover cannot open it, and the click-through below takes the mouse off the panel", controller.contains("let inIsland = hoverRect.contains(local) && !wing.passThrough"))
        CT.checkTrue("the step comes after the island's rectangle and before the click-through toggle and the FSM's enter and leave", at("let islandRect = panel.currentIslandFrame", in: controller) > 0 && at("let islandRect = panel.currentIslandFrame", in: controller) < at("wingYield.step(", in: controller) && at("wingYield.step(", in: controller) < at("let shouldAcceptMouse = inIsland", in: controller) && at("let shouldAcceptMouse = inIsland", in: controller) < at("fsm.mouseEntered()", in: controller))
        CT.check("the panel registers no mouse-moved monitor (the poll that already runs is the only watcher)", count("matching: .mouseMoved", in: controller), 0)
        CT.checkTrue("and the poll still runs at the hidden rate while the island is hidden (the poller is untouched)", controller.contains("poller.run(hidden: state.mode == .hidden)") && controller.contains("modeSubscription = state.$mode"))

        CT.section("the view: the island's black shrinks into the notch on a spring, and its cats, grid and badges fade with it")
        CT.checkTrue("AppState publishes wingYielded and nothing else sets it", app.contains("@Published var wingYielded = false") && count("wingYielded =", in: controller) == 1 && count("wingYielded =", in: island) == 0)
        CT.checkTrue("the drawn width is the notch's while the compact island has stepped aside, and the full width otherwise", island.contains("private var shownWidth: CGFloat { state.mode == .compact && state.wingYielded ? IslandWing.foldedWidth(notchWidth: state.notchWidth) : islandWidth }"))
        CT.checkTrue("the black is drawn at that width, centred, with the rules' spring", island.contains("IslandShape(width: shownWidth, height: islandHeight, cornerRadius: cornerRadius, topRadius: islandTopRadius)\n                .fill(Color.black)\n                .offset(x: (islandWidth - shownWidth) / 2)\n                .animation(swoosh, value: state.wingYielded)") && island.contains("Animation.spring(response: IslandWing.springResponse, dampingFraction: IslandWing.springDamping)"))
        CT.checkTrue("there is no mask on the black any more (the shape itself shrinks)", !island.contains("// The right wing steps aside: its black fades with the grid"))
        CT.check("the big cat, cat 2, the kittens, the grid, the focus dots (FocusWaitCompactDots), the shelf's badge and the Projects badge all fade with the fold", count(".opacity(state.wingYielded ? 0 : 1)", in: island), 7)
        CT.checkTrue("with the same animation, quick out and gentler in, from the rules' constants, the focus dots included", count(".animation(wingAnimation, value: state.wingYielded)", in: island) == 7 && island.contains(".easeOut(duration: IslandWing.fadeOut) : .easeInOut(duration: IslandWing.fadeIn)"))
        CT.checkTrue("the content after the black is as it was", island.contains("// Content\n            if state.mode == .expanded {"))

        CT.finish()
    }
}
