import Foundation

// The drop halves: which half the pointer is in, and what each half accepts. Run it through scripts/test-shelf-drop.sh.

@main
enum ShelfDropTests {
    @MainActor static func main() {
        CT.section("which half")
        CT.check("the left edge, the middle of the left half and the centre line are Ask", [320.0, 0, 100, 319.9].map { ShelfDrop.half(x: $0).rawValue }, ["ask", "ask", "ask", "ask"])
        CT.check("just right of the centre line, and the right edge, are Shelf", [320.5, 321, 480, 640].map { ShelfDrop.half(x: $0).rawValue }, ["shelf", "shelf", "shelf", "shelf"])
        CT.check("outside the island is the Ask drop it has always been", [-10.0, 641, 100000, .nan, .infinity].map { ShelfDrop.half(x: $0).rawValue }, ["ask", "ask", "ask", "ask", "ask"])
        CT.check("the width is the expanded island's", ShelfDrop.islandWidth, 640)
        CT.check("a narrow width splits at its own middle", [ShelfDrop.half(x: 10, width: 20).rawValue, ShelfDrop.half(x: 10.5, width: 20).rawValue], ["ask", "shelf"])

        CT.section("what each half accepts")
        let files: Set<DragKind> = [.fileURL], promised: Set<DragKind> = [.promisedFile], image: Set<DragKind> = [.image]
        CT.check("file URLs are accepted over both halves, as today", [ShelfDrop.accepts(files, over: .ask), ShelfDrop.accepts(files, over: .shelf)], [true, true])
        CT.check("promised files and images only over Shelf", [ShelfDrop.accepts(promised, over: .ask), ShelfDrop.accepts(promised, over: .shelf), ShelfDrop.accepts(image, over: .ask), ShelfDrop.accepts(image, over: .shelf)], [false, true, false, true])
        CT.check("a drag with file URLs and an image is the file drop over Ask", ShelfDrop.accepts([.fileURL, .image], over: .ask), true)
        CT.check("a drag with nothing we read is accepted nowhere and opens nothing", [ShelfDrop.accepts([], over: .ask), ShelfDrop.accepts([], over: .shelf), ShelfDrop.opensIsland([])], [false, false, false])
        CT.check("every drag with something we read opens the island", [files, promised, image].map { ShelfDrop.opensIsland($0) }, [true, true, true])

        CT.section("the note after a drop")
        CT.check("a drop that added everything says nothing", ShelfDrop.note([.added, .added]), nil)
        CT.check("nothing dropped says nothing", ShelfDrop.note([]), nil)
        CT.check("a full shelf says so, with how many", ShelfDrop.note([.added, .full, .full]), "The shelf holds 30 at most: 2 files were not added.")
        CT.check("one file that was refused as full is singular", ShelfDrop.note([.full]), "The shelf holds 30 at most: 1 file was not added.")
        CT.check("a file that cannot be shelved says so", ShelfDrop.note([.invalid, .added]), "1 file can't be shelved.")
        CT.check("both, in that order", ShelfDrop.note([.full, .invalid, .invalid]), "The shelf holds 30 at most: 1 file was not added. 2 files can't be shelved.")
        CT.check("a re-dropped file says it is already there, but only when nothing was added", [ShelfDrop.note([.duplicate]), ShelfDrop.note([.duplicate, .added])], ["Already on the shelf.", nil] as [String?])

        CT.section("when the shelf holds the island open")
        CT.check("a drag out holds it, whatever the picker says", [ShelfHold.isHeld(dragging: true, pickerSince: nil, now: 5), ShelfHold.isHeld(dragging: true, pickerSince: 1000, now: 5)], [true, true])
        CT.check("nothing holds it by default", ShelfHold.isHeld(dragging: false, pickerSince: nil, now: 5), false)
        CT.check("an open picker holds it, up to 120 s", [ShelfHold.isHeld(dragging: false, pickerSince: 100, now: 100), ShelfHold.isHeld(dragging: false, pickerSince: 100, now: 219.9)], [true, true])
        CT.check("and not after the limit: a callback that never came cannot hold the island for ever", [ShelfHold.isHeld(dragging: false, pickerSince: 100, now: 220), ShelfHold.isHeld(dragging: false, pickerSince: 100, now: 100000)], [false, false])
        CT.check("a clock that went backwards, or is not a number, holds nothing", [ShelfHold.isHeld(dragging: false, pickerSince: 100, now: 50), ShelfHold.isHeld(dragging: false, pickerSince: .nan, now: 100), ShelfHold.isHeld(dragging: false, pickerSince: 100, now: .infinity)], [false, false, false])

        CT.section("the island stays open 15 s after a send, read from the clock when someone asks")
        let sent = ShelfHold.lingerSince(now: 500)
        CT.check("the linger is 15 s", ShelfHold.afterSendLinger, 15)
        CT.checkTrue("and inside the picker's own limit", ShelfHold.afterSendLinger < ShelfHold.pickerLimit)
        CT.check("held for 14 s after the send", [ShelfHold.isHeld(dragging: false, pickerSince: sent, now: 500), ShelfHold.isHeld(dragging: false, pickerSince: sent, now: 514), ShelfHold.isHeld(dragging: false, pickerSince: sent, now: 514.9)], [true, true, true])
        CT.check("released at 15 s, and never again after", [ShelfHold.isHeld(dragging: false, pickerSince: sent, now: 515), ShelfHold.isHeld(dragging: false, pickerSince: sent, now: 100000)], [false, false])
        // The delay the one timer waits for (IslandWindowController arms it for the end): 15 s after a send, 120 s after the picker opens, what is left later, and none when nothing holds.
        CT.check("the linger: 15 s from the send", ShelfHold.releaseDelay(pickerSince: sent, now: 500), 15)
        CT.check("the picker: 120 s from its opening", ShelfHold.releaseDelay(pickerSince: 100, now: 100), 120)
        CT.check("and what is left of it later", ShelfHold.releaseDelay(pickerSince: 100, now: 130), 90)
        CT.check("past the end: 0, never negative", ShelfHold.releaseDelay(pickerSince: 100, now: 300), 0)
        CT.check("nothing holds: no delay", ShelfHold.releaseDelay(pickerSince: nil, now: 500), nil)
        CT.check("a clock that is not a number: no delay", ShelfHold.releaseDelay(pickerSince: .nan, now: 100), nil)
        CT.check("a send that finishes late in the picker's life still gets its full 15 s (the reading is taken at the send, not at the picker's start)", [ShelfHold.isHeld(dragging: false, pickerSince: ShelfHold.lingerSince(now: 219), now: 233.9), ShelfHold.isHeld(dragging: false, pickerSince: ShelfHold.lingerSince(now: 219), now: 234)], [true, false])
        CT.check("a picker still up past 15 s stays held until its own 120 s, then is released", [ShelfHold.isHeld(dragging: false, pickerSince: 100, now: 116), ShelfHold.isHeld(dragging: false, pickerSince: 100, now: 219.9), ShelfHold.isHeld(dragging: false, pickerSince: 100, now: 220)], [true, true, false])
        CT.check("a drag out still holds it through the linger's end", ShelfHold.isHeld(dragging: true, pickerSince: sent, now: 600), true)

        CT.section("which buttons work")
        func item(_ id: String, folder: Bool = false) -> ShelfItem { ShelfItem(id: id, name: id, size: 1, folder: folder, copy: false, link: "/p/\(id)", addedAt: 1) }
        let a = item("a"), b = item("b"), dir = item("d", folder: true)
        CT.check("Ask works on one file", ShelfActionRules.canAsk([a], missing: []), true)
        CT.check("and is off for several, for a folder, for nothing and for a missing file", [ShelfActionRules.canAsk([a, b], missing: []), ShelfActionRules.canAsk([dir], missing: []), ShelfActionRules.canAsk([], missing: []), ShelfActionRules.canAsk([a], missing: ["a"])], [false, false, false, false])
        CT.check("Send takes several items and a folder", [ShelfActionRules.canSend([a, b], missing: []), ShelfActionRules.canSend([dir], missing: []), ShelfActionRules.canSend([a, dir], missing: [])], [true, true, true])
        CT.check("and is off for nothing, and when any one of them is missing", [ShelfActionRules.canSend([], missing: []), ShelfActionRules.canSend([a, b], missing: ["b"])], [false, false])
        CT.check("Show in Finder is the same", [ShelfActionRules.canShow([a, dir], missing: []), ShelfActionRules.canShow([], missing: []), ShelfActionRules.canShow([a], missing: ["a"])], [true, false, false])
        CT.check("the Ask hint says it starts a new chat", ShelfActionRules.askHint.contains("new chat"), true)

        CT.section("the compact badge")
        CT.check("it shows in the compact island with something on the shelf", ShelfBadge.isShown(compact: true, count: 3, greetingTail: false), true)
        CT.check("never on an empty shelf, never outside the compact island (so it never wakes a hidden one), never under the greeting's tail", [ShelfBadge.isShown(compact: true, count: 0, greetingTail: false), ShelfBadge.isShown(compact: false, count: 3, greetingTail: false), ShelfBadge.isShown(compact: true, count: 3, greetingTail: true), ShelfBadge.isShown(compact: false, count: 0, greetingTail: true)], [false, false, false, false])
        CT.check("it sits 14 pt in from the right edge, in the middle of the strip", [ShelfBadge.center(islandWidth: 344, height: 32).x, ShelfBadge.center(islandWidth: 344, height: 32).y], [330, 16])
        // The grid's last cell ends 26 pt in from the right edge (centre 40 in, 28 wide); the badge starts 21 pt in.
        CT.checkTrue("it does not touch the grid's cells", 344 - (ShelfBadge.center(islandWidth: 344, height: 32).x + ShelfBadge.diameter / 2) >= 0 && (344 - 26) < (ShelfBadge.center(islandWidth: 344, height: 32).x - ShelfBadge.diameter / 2))
        CT.check("a short strip shrinks it like the grid", [ShelfBadge.scale(height: 32), ShelfBadge.scale(height: 18), ShelfBadge.scale(height: 4), ShelfBadge.scale(height: 100)], [1, 0.5, 0, 1])
        let island = CGRect(x: 188, y: 288, width: 344, height: 32)   // the panel's coordinates, y up
        let hit = ShelfBadge.hitRect(island: island)
        CT.check("a click counts within 11 pt of the badge's centre, as a box", [hit.minX, hit.maxX, hit.midY], [532 - 14 - 11, 532 - 14 + 11, 304])
        CT.checkTrue("the badge's centre is in it; the grid, the notch and the island's far right edge are not", hit.contains(CGPoint(x: 518, y: 304)) && !hit.contains(CGPoint(x: 492, y: 304)) && !hit.contains(CGPoint(x: 360, y: 304)) && !hit.contains(CGPoint(x: 531.9, y: 304)))

        CT.finish()
    }
}
