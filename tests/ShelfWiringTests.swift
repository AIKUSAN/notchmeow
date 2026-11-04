import Foundation

// Source pins for the shelf (sub-project G1), where no test program can compile the app's files (the drop view, the panel, AppState and the SwiftUI views need the whole app). Each says where a
// call must be, so a missed call site fails here and not on the owner's screen. Run from the repository root through scripts/test-shelf-wiring.sh.

@main
enum ShelfWiringTests {
    static func source(_ file: String) -> String { (try? String(contentsOfFile: "NotchBuddy/Sources/App/\(file)", encoding: .utf8)) ?? "" }
    static func count(_ needle: String, in text: String) -> Int { text.components(separatedBy: needle).count - 1 }
    /// The offset of the first `needle`, or -1.
    static func at(_ needle: String, in text: String) -> Int { text.range(of: needle)?.lowerBound.utf16Offset(in: text) ?? -1 }

    @MainActor static func main() {
        let drop = source("FileDropView.swift"), controller = source("IslandWindowController.swift"), island = source("IslandRootView.swift"), flow = source("ShelfFlow.swift"), reader = source("ShelfDropReader.swift")
        let rules = source("ShelfRules.swift"), dropRules = source("ShelfDrop.swift"), store = source("ShelfStore.swift"), model = source("ShelfModel.swift")
        CT.section("the sources were read")
        CT.checkTrue("every file is there", drop.contains("final class FileDropNSView") && controller.contains("final class IslandWindowController") && island.contains("struct IslandContainer") && flow.contains("enum ShelfFlow") && reader.contains("enum ShelfDropReader")
                     && rules.contains("enum ShelfRules") && dropRules.contains("enum ShelfDrop") && store.contains("final class ShelfStore") && model.contains("final class ShelfModel"))

        CT.section("the pure files stay pure: no AppKit, no timer, no monitor")
        CT.checkTrue("rules, drop rules and store import Foundation only", [rules, dropRules, store].allSatisfy { $0.contains("import Foundation") && !$0.contains("import AppKit") && !$0.contains("import SwiftUI") })
        CT.checkTrue("and start nothing", [rules, dropRules, store, model, flow, reader].allSatisfy { !$0.contains("Timer") && !$0.contains("DispatchSourceTimer") && !$0.contains("NSEvent") && !$0.contains("asyncAfter") })

        CT.section("the drop path: the Ask half is the code that ships, the Shelf half is added beside it")
        CT.checkTrue("the Ask branch still reads file URLs only and hands them to onFilesDropped, last in performDragOperation", drop.contains("        // The Ask half: exactly as it has always been.\n        guard let urls = sender.draggingPasteboard.readObjects(\n            forClasses: [NSURL.self],\n            options: [.urlReadingFileURLsOnly: true]\n        ) as? [URL], !urls.isEmpty else { return false }\n        onFilesDropped?(urls)\n        return true"))
        CT.checkTrue("a drag that started inside the app is refused at all three steps", count("isOwnDrag(sender)", in: drop) == 3 && drop.contains("sender.draggingSource != nil"))
        CT.checkTrue("what each half accepts is ShelfDrop's, at the drag's position", drop.contains("ShelfDrop.accepts(kinds, over: halfAt?(sender.draggingLocation) ?? .ask)") && drop.contains("guard ShelfDrop.accepts(kinds, over: half) else { return false }"))
        CT.checkTrue("a Shelf drop goes to onShelfDrop and never to the Ask handler", drop.contains("if half == .shelf {\n            onShelfDrop?(sender.draggingPasteboard, kinds)\n            return true\n        }"))
        CT.checkTrue("the controller sets the half on enter, on update and clears it on exit and on an Ask drop", controller.contains("AppState.shared.dropHalf = ShelfDrop.half(x: Double(iLoc.x))") && controller.contains("if AppState.shared.dropHalf != half { AppState.shared.dropHalf = half }") && count("AppState.shared.dropHalf = nil", in: controller) == 2)
        CT.checkTrue("and wires halfAt and onShelfDrop to the reader and to shelfDropped", controller.contains("dropView.halfAt = { [weak self] loc in ShelfDrop.half(x: Double(self?.windowToIsland(loc).x ?? 0)) }") && controller.contains("ShelfDropReader.read(pasteboard, kinds: kinds) { incoming, temp in") && controller.contains("self?.shelfDropped(incoming, temp: temp)"))
        CT.checkTrue("the Ask drop's own handler call is as it was", controller.contains("await FileDropHandler.handle(urls: urls, state: AppState.shared)"))

        CT.section("after a Shelf drop: a fresh token, the alert cleared, the sequence stopped, no wait for the desktop cat")
        CT.checkTrue("ShelfFlow does the four things", flow.contains("_ = FileDropHandler.drops.begin()") && flow.contains("state.fileDragOver = false") && flow.contains("state.dropHalf = nil") && flow.contains("UploadSequenceEngine.shared.deactivate()"))
        CT.checkTrue("and never calls the Ask drop or waits for the cat", !flow.contains("FileDropHandler.handle") && !flow.contains("waitForCat") && !reader.contains("waitForCat"))
        // The flow is cleared at the drop itself, before anything is read: a promise that is slow, or never answers, must not leave the upload canvas, the file alert and the sequence up.
        CT.checkTrue("a Shelf drop clears the flow synchronously, before the reader is asked for anything", at("ShelfFlow.afterShelfDrop(state: AppState.shared)", in: controller) >= 0 && at("ShelfFlow.afterShelfDrop(state: AppState.shared)", in: controller) < at("ShelfDropReader.read(pasteboard, kinds: kinds)", in: controller)
                     && at("dropView.onShelfDrop = ", in: controller) < at("ShelfFlow.afterShelfDrop(state: AppState.shared)", in: controller))
        let dropped = controller.range(of: "func shelfDropped(").map { String(controller[$0.lowerBound...].prefix(600)) } ?? ""
        CT.checkTrue("shelfDropped adds, removes the temp folder, then opens the shelf, in that order, and does not clear the flow again (a newer Ask drop's token and sequence are not its to end)",
                     !dropped.isEmpty && !dropped.contains("ShelfFlow.afterShelfDrop") && at("ShelfModel.shared.add(incoming)", in: dropped) >= 0 && at("ShelfModel.shared.add(incoming)", in: dropped) < at("try? FileManager.default.removeItem(at: temp)", in: dropped) && at("try? FileManager.default.removeItem(at: temp)", in: dropped) < at("        openShelf()\n    }", in: dropped))
        CT.checkTrue("the layer is added over the canvas, inside the upload branch, before the header", island.contains("if state.view == .upload, let half = state.dropHalf {\n                            ShelfDropLayer(half: half)") && at("ShelfDropLayer(half: half)", in: island) < at("IslandHeader(state: state)\n                            .frame(width: islandWidth, height: 34)", in: island))

        CT.section("the reader never fetches a URL")
        CT.checkTrue("no URLSession, no NSImage read from the pasteboard, no web URL class", !reader.contains("URLSession") && !reader.contains("forClasses: [NSImage.self]") && !reader.contains("NSURLRequest") && !reader.contains("Data(contentsOf"))

        CT.section("dragging out: the island stays open, the panel keeps the mouse, the drop view ignores it")
        let dragOut = source("ShelfDragOut.swift"), shelfContent = source("ShelfContent.swift"), shelfView = source("ShelfView.swift"), appState = source("AppState.swift")
        CT.checkTrue("the source lets the files be copied outside the app and refuses a drop inside it", dragOut.contains("context == .outsideApplication ? .copy : []"))
        CT.checkTrue("each dragged file is opened for the length of the session and closed when it ends", dragOut.contains("let accesses = chosen.compactMap { model.open($0) }") && dragOut.contains("for a in accesses { a.end() }"))
        CT.checkTrue("the tile drags the whole selection when it is part of it, and starts after 4 pt", dragOut.contains("let chosen = model.selection.contains(item.id) ? model.selected : [item]") && dragOut.contains("> 4 else { return }"))
        CT.checkTrue("the shelf view tells AppState when a drag begins and ends", shelfView.contains("AppState.shared.shelfDragging = true") && shelfView.contains("AppState.shared.shelfDragging = false") && shelfContent.contains("ShelfTileMouse(model: model, item: item, hooks: hooks)"))
        CT.checkTrue("AppState says the island is held while it drags or the picker is open", appState.contains("var shelfHoldsIsland: Bool { ShelfHold.isHeld(dragging: shelfDragging, pickerSince: sharePickerSince, now: ProcessInfo.processInfo.systemUptime) }"))
        CT.checkTrue("the state machine's hold-open asks it, in both builds", count("|| AppState.shared.shelfHoldsIsland || AppState.shared.linkHoldsIsland }", in: controller) == 2)
        CT.checkTrue("and so does the poll's idea of 'over the island', which also keeps the panel taking the mouse", controller.contains("let inIsland = hoverRect.contains(local) && !wing.passThrough || state.shelfHoldsIsland") && controller.contains("let shouldAcceptMouse = inIsland || inAttachDrag"))

        CT.section("the buttons: Ask is the Ask drop, Show in Finder never touches the files")
        let actions = source("ShelfActions.swift")
        CT.checkTrue("Ask starts the upload sequence, opens the island on its canvas and then runs the drop handler as a drop on Ask does", actions.contains("UploadSequenceEngine.shared.enterZone(x: 320, y: 110)") && actions.contains("NotificationCenter.default.post(name: .hookExpand, object: IslandView.upload)") && actions.contains("await FileDropHandler.handle(urls: [access.url], state: state)")
                     && at("UploadSequenceEngine.shared.enterZone", in: actions) < at("await FileDropHandler.handle", in: actions))
        CT.checkTrue("it checks the rules first (one file, no folder, not missing) and keeps the file open for the chat", actions.contains("guard ShelfActionRules.canAsk([item], missing: model.missing), let access = model.open(item) else { return }") && actions.contains("held = access"))
        CT.checkTrue("Show in Finder opens, reveals and closes", actions.contains("NSWorkspace.shared.activateFileViewerSelecting(accesses.map(\\.url))") && actions.contains("for a in accesses { a.end() }"))
        CT.checkTrue("the shelf view gives the buttons to the content", shelfView.contains("ShelfActions.ask($0, model: model)") && shelfView.contains("ShelfActions.showInFinder($0, model: model)"))
        CT.checkTrue("no button deletes or moves an original: remove goes through the model, which deletes only a copy", !actions.contains("removeItem") && !actions.contains("trashItem") && !actions.contains("moveItem"))

        CT.section("Send: the picker and AirDrop, started by a click, held open by a clock reading, logging only that a send started")
        let send = source("ShelfSend.swift")
        CT.checkTrue("the picker is the system's, anchored below the island after the panel takes the key", send.contains("NSSharingServicePicker(items: urls)") && send.contains("panel.makeKey()") && send.contains("preferredEdge: .minY") && at("panel.makeKey()", in: send) < at("picker.show(", in: send))
        CT.checkTrue("AirDrop is the system's service, and is tried only when it can take the items", send.contains("NSSharingService(named: .sendViaAirDrop)") && send.contains("service.canPerform(withItems: urls)"))
        CT.checkTrue("the island is held by a clock reading that every way out clears", send.contains("state.sharePickerSince = ProcessInfo.processInfo.systemUptime") && send.contains("state.sharePickerSince = nil") && send.contains("if service == nil { finish() }") && send.contains("didShareItems") && send.contains("didFailToShareItems"))
        CT.checkTrue("after a share that ran the island stays open for the linger, from a clock reading taken then, and a failed or cancelled share lets go at once", send.contains("state.sharePickerSince = ShelfHold.lingerSince(now: ProcessInfo.processInfo.systemUptime)") && send.contains("didShareItems items: [Any]) { finish(lingering: true) }") && send.contains("error: Error) { finish() }"))
        CT.checkTrue("the files stay open until the share is over", send.contains("accesses = opened") && send.contains("for a in accesses { a.end() }"))
        CT.checkTrue("the log says only that a send started, with no name and no count", send.contains("appendAppLog(\"shelf.log\", \"a send started\")") && count("appendAppLog", in: send) == 1)
        CT.checkTrue("every callback belongs to one share: each share has its own delegate, a callback from any other is ignored", send.contains("fileprivate final class ShelfShareDelegate") && send.contains("private var isCurrent: Bool { owner.shareDelegate === self }") && send.contains("if isCurrent { owner.finish(lingering: lingering) }") && send.contains("shareDelegate = ShelfShareDelegate(owner: self)") && send.contains("picker.delegate = shareDelegate") && send.contains("service.delegate = shareDelegate") && !send.contains("delegate = self") && !send.contains("final class ShelfSend: NSObject"))
        CT.checkTrue("a share that is over, or replaced by a newer one, is no longer current", count("shareDelegate = nil", in: send) == 1 && at("shareDelegate = nil", in: send) > at("func finish(lingering", in: send) && at("shareDelegate = ShelfShareDelegate(owner: self)", in: send) > at("        finish()\n        let opened", in: send))
        CT.checkTrue("no network: nothing in Send reaches out", !send.contains("URLSession") && !send.contains("NWConnection"))
        CT.checkTrue("no timer of its own: the linger is read from the clock by the poll and the state machine", !send.contains("Timer") && !send.contains("asyncAfter") && !send.contains("DispatchSource") && !send.contains("CADisplayLink") && !send.contains("NSEvent.add"))
        CT.checkTrue("the shelf view gives Send and AirDrop to the content", shelfView.contains("ShelfActions.send($0, model: model)") && shelfView.contains("ShelfActions.airDrop($0, model: model)"))

        CT.section("the badge: compact only, fades with the wing, opens the shelf, wakes nothing")
        let badge = source("ShelfBadge.swift"), badgeView = source("ShelfBadgeView.swift"), wing = source("IslandWing.swift")
        CT.checkTrue("the rules are pure", badge.contains("import CoreGraphics") && badge.contains("import Foundation") && !badge.contains("import AppKit") && !badge.contains("import SwiftUI") && !badge.contains("Timer") && !badge.contains("NSEvent"))
        CT.checkTrue("the island draws it after the grid, only when the rules say so, with the grid's own fade", island.contains("if ShelfBadge.isShown(compact: state.mode == .compact, count: shelf.count, greetingTail: greetingTail) {") && island.contains(".position(ShelfBadge.center(islandWidth: islandWidth, height: islandHeight))\n                    .opacity(state.wingYielded ? 0 : 1)\n                    .animation(wingAnimation, value: state.wingYielded)")
                     && at("CompactMiniGrid(state: state)", in: island) < at("ShelfBadgeView(count: shelf.count", in: island))
        CT.checkTrue("it is on screen only through that one check: nothing else in the island or the controller reveals or expands for the shelf's count", count("ShelfBadge.isShown", in: island) == 1 && !controller.contains("shelf.count") && !island.contains("fsm.reveal") && !source("ShelfModel.swift").contains("reveal") && !source("ShelfModel.swift").contains("hookExpand"))
        CT.checkTrue("a click on it opens the shelf (compact only), before the click that opens the home view", controller.contains("if hadPendingClick && self.state.mode != .expanded && self.clickedShelfBadge(event) {\n                        self.openShelf()") && controller.contains("guard state.mode == .compact, ShelfBadge.isShown(compact: true, count: ShelfModel.shared.count, greetingTail: state.greetingTail)"))
        CT.checkTrue("the wing's rules and its call sites are untouched: the badge adds nothing to IslandWing", !wing.contains("Shelf") && controller.contains("IslandWing.wings(island: islandRect, notchWidth: notchW, slop: hoverRect.maxX - islandRect.maxX)") && controller.contains("buttonDown: { NSEvent.pressedMouseButtons != 0 }"))
        CT.checkTrue("the view reads only the count it is given", badgeView.contains("let count: Int") && !badgeView.contains("ShelfModel"))

        CT.section("App Store parity: the shelf is in every build, its Debug panel only in Debug")
        let devModel = source("ShelfDevModel.swift"), devPanel = source("ShelfDevPanel.swift"), delegate = source("AppDelegate.swift")
        CT.checkTrue("the dev panel's files are wrapped in #if DEBUG && !APPSTORE", devModel.contains("#if DEBUG && !APPSTORE") && devPanel.contains("#if DEBUG && !APPSTORE") && devModel.hasSuffix("#endif\n") && devPanel.hasSuffix("#endif\n"))
        CT.checkTrue("its menu item and window are inside the existing Debug block of the app delegate", at("Shelf (Debug)…", in: delegate) > at("#if DEBUG && !APPSTORE\n        menu.addItem(withTitle: \"Cats (Debug)…\"", in: delegate) && at("@objc private func openShelfPanel()", in: delegate) < at("    #endif\n\n    /// Centres the window", in: delegate) && at("@objc private func openShelfPanel()", in: delegate) > at("@objc private func openCatPanel()", in: delegate))
        CT.checkTrue("nothing of the shelf is under #if !APPSTORE: the whole shelf is in the App Store build, with scoped bookmarks", ["ShelfRules.swift", "ShelfStore.swift", "ShelfModel.swift", "ShelfContent.swift", "ShelfView.swift", "ShelfActions.swift", "ShelfSend.swift", "ShelfDragOut.swift", "ShelfDropReader.swift", "ShelfFlow.swift", "ShelfBadge.swift", "ShelfDrop.swift"].allSatisfy { !source($0).contains("#if !APPSTORE") })
        CT.checkTrue("the only build condition is the bookmark option: scoped in the App Store build", store.contains("#if APPSTORE\n    static let isAppStoreBuild = true") && count("#if", in: store) == 1 && store.contains("[.withSecurityScope]"))
        CT.checkTrue("the shelf view carries the marker the binary check looks for", shelfView.contains(".accessibilityIdentifier(ShelfStore.marker)") && store.contains("static let marker = \"NM_SHELF_STORE_ACTIVE\""))

        CT.section("the final review's fixes: the inactive shelf is not on screen, the layer is clipped, tiles speak, a failed open is told")
        let viewContent = source("IslandViewContent.swift")
        let renderScript = (try? String(contentsOfFile: "scripts/render-shelf.swift", encoding: .utf8)) ?? ""
        CT.checkTrue("the shelf is built only while it is the active view: an inactive one has no mouse overlays above the other views (the island stacks every view, and AppKit ignores alpha)",
                     viewContent.contains("case .shelf:") && viewContent.contains("if state.view == .shelf { ShelfView(model: ShelfModel.shared) }") && !viewContent.contains("case .shelf:     ShelfView("))
        CT.checkTrue("the drop layer is clipped to the island's own shape, in the island's size and not a fixed 640 x 176, so the spring open cannot draw it outside the black",
                     island.contains("ShelfDropLayer(half: half)\n                                .frame(width: islandWidth, height: islandHeight, alignment: .topLeading)\n                                .clipShape(IslandShape(width: islandWidth, height: islandHeight,") && !island.contains(".frame(width: 640, height: 176)"))
        CT.checkTrue("a bookmark is resolved without mounting or UI, in both builds, and a package is not a folder",
                     store.contains("[.withSecurityScope, .withoutUI, .withoutMounting] : [.withoutUI, .withoutMounting]") && store.contains("options: Self.resolveOptions(scoped: scoped)") && store.contains(".isPackageKey") && store.contains("values?.isPackage != true"))
        CT.checkTrue("a promised file's twin is found by name and bytes with Foundation, never by temp path, name alone, size alone or a stored hash",
                     store.contains("fm.contentsEqual(atPath: url.path, andPath:") && !store.contains("SHA") && !store.contains("CryptoKit") && !store.contains("import CommonCrypto"))
        CT.checkTrue("a key with a lone surrogate is not stored under the key without it", rules.contains("if !key.lone { out[key.text] = v }"))
        CT.checkTrue("an item is opened from the store's own copy of it, and the model re-syncs on a refresh", store.contains("let item = items.first { $0.id == caller.id } ?? caller") && model.contains("missing = store.checkMissing()\n        sync()"))
        CT.checkTrue("every failed open (drag, Ask, Show in Finder, Send) goes through one place that refreshes, and a failed drag does not leave `dragging` set",
                     model.contains("if access == nil { refresh() }") && dragOut.contains("if !beginDrag(with: event) { dragging = false; pressed = nil }") && dragOut.contains("private func beginDrag(with event: NSEvent) -> Bool"))
        CT.checkTrue("an empty Shelf drop says so (ShelfDrop.note itself is untouched: note([]) stays nil)", model.contains("incoming.isEmpty ? \"Nothing could be added.\" : ShelfDrop.note(results)") && dropRules.contains("static func note(_ results: [ShelfAddResult]) -> String?"))
        CT.checkTrue("the tile's AppKit overlay is the accessibility element (a button with the name and size, selected state, press toggles) and the SwiftUI tile under it is hidden, so it is not read twice",
                     dragOut.contains("override func isAccessibilityElement() -> Bool { true }") && dragOut.contains("override func accessibilityRole() -> NSAccessibility.Role? { .button }") && dragOut.contains("ShelfTile.detail(item, missing: model?.missing.contains(item.id) == true)")
                     && dragOut.contains("override func isAccessibilitySelected() -> Bool") && dragOut.contains("override func accessibilityPerformPress() -> Bool")
                     && shelfContent.contains(".accessibilityHidden(true)") && at(".accessibilityHidden(true)", in: shelfContent) < at("ShelfTileMouse(model: model, item: item, hooks: hooks)", in: shelfContent)
                     && shelfContent.contains("static func detail(_ item: ShelfItem, missing: Bool) -> String"))
        CT.checkTrue("the render script's shelves are made under the folder the script's trap removes, not in the system temp folder", renderScript.contains("NM_LOG_DIR") && !renderScript.contains("temporaryDirectory.appendingPathComponent(\"notchmeow-render-shelf-"))

        CT.finish()
    }
}
