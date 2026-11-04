import Foundation

// The drop halves (sub-project G1): while files are dragged over the open notch it splits at its centre line into Ask (the left half, today's drop) and Shelf (the right half). Foundation
// only. Which half the pointer is in is `ShelfRules.zoneAt` (the shared contract); what each half accepts is here.

/// The half of the open island the pointer is over. Ask is the canvas that ships; Shelf is the layer added on top of it.
enum DropHalf: String, Sendable { case ask, shelf }

/// What a drag carries that NotchMeow can use.
enum DragKind: Hashable, Sendable {
    /// File URLs: what the drop accepts today.
    case fileURL
    /// Promised files (Mail, Photos, a screenshot thumbnail): the sender writes the file when asked.
    case promisedFile
    /// An image with no file behind it (dragged out of a browser).
    case image
}

/// When the shelf holds the island open: while files are dragged out of it, and while its share picker is open. Both mean the pointer may be anywhere and the island must stay. The picker is a
/// clock reading with a limit, evaluated when someone asks (the poll, the state machine): no timer, and a delegate callback that never comes cannot hold the island open for ever.
enum ShelfHold {
    static let pickerLimit: TimeInterval = 120
    /// How long the island stays open after a share ran (owner's ruling): the picker's own limit is a separate safety bound.
    static let afterSendLinger: TimeInterval = 15

    /// The `pickerSince` reading that holds the island for exactly `afterSendLinger` more seconds from `now`: the same clock reading and the same limit, so the linger needs no state, no timer and
    /// no change to `isHeld`. The hold's end is a time, so `IslandWindowController` arms one one-shot timer for it (`releaseDelay`).
    static func lingerSince(now: TimeInterval) -> TimeInterval { now - (pickerLimit - afterSendLinger) }

    /// The seconds until the picker's hold ends, counted from its opening (the linger included: `lingerSince` rewinds the same reading). nil while nothing holds, or the clock is not a number.
    static func releaseDelay(pickerSince: TimeInterval?, now: TimeInterval) -> TimeInterval? {
        guard let since = pickerSince, since.isFinite, now.isFinite else { return nil }
        return max(0, since + pickerLimit - now)
    }

    static func isHeld(dragging: Bool, pickerSince: TimeInterval?, now: TimeInterval) -> Bool {
        if dragging { return true }
        guard let since = pickerSince, since.isFinite, now.isFinite else { return false }
        return now >= since && now - since < pickerLimit
    }
}

enum ShelfDrop {
    /// The open island's width, which the halves are measured against (`IslandConst.expandedWidth`): a drag over the notch always opens the island to this width.
    static let islandWidth: Double = 640

    /// The half for a pointer `x` points from the island's left edge. Outside the island there is no half in the contract; the drop view covers the whole panel and has always taken a drop
    /// anywhere on it as the Ask drop, so outside is Ask.
    static func half(x: Double, width: Double = islandWidth) -> DropHalf {
        ShelfRules.zoneAt(x: x, width: width) == .shelf ? .shelf : .ask
    }

    /// Whether the drop is accepted over `half`. File URLs are accepted over both halves, as they are today. Promised files and browser images only over Shelf; over Ask they are refused,
    /// exactly as they are today (the drop view never saw them).
    static func accepts(_ kinds: Set<DragKind>, over half: DropHalf) -> Bool {
        if kinds.contains(.fileURL) { return true }
        return half == .shelf && (kinds.contains(.promisedFile) || kinds.contains(.image))
    }

    /// Whether a drag opens the island at all: the ones that can be dropped somewhere.
    static func opensIsland(_ kinds: Set<DragKind>) -> Bool {
        !kinds.isEmpty
    }

    /// The short note after a Shelf drop that did not add everything, or nil when there is nothing to say. Nothing old is ever removed to make room, so a full shelf says so.
    /// (The rules for the buttons are in `ShelfActionRules`, below.)
    static func note(_ results: [ShelfAddResult]) -> String? {
        let full = results.filter { $0 == .full }.count, bad = results.filter { $0 == .invalid }.count, dup = results.filter { $0 == .duplicate }.count
        var parts: [String] = []
        if full > 0 { parts.append("The shelf holds \(ShelfRules.max) at most: \(full == 1 ? "1 file was" : "\(full) files were") not added.") }
        if bad > 0 { parts.append(bad == 1 ? "1 file can't be shelved." : "\(bad) files can't be shelved.") }
        if parts.isEmpty && dup > 0 && !results.contains(.added) { parts.append("Already on the shelf.") }
        return parts.isEmpty ? nil : parts.joined(separator: " ")
    }
}

/// Which of the shelf's buttons work on the selected items. A file that has gone missing works with none of them.
enum ShelfActionRules {
    /// What the Ask button's hint says: the file goes to a chat the way a drop on Ask does, which resets the conversation.
    static let askHint = "Ask about this file. Starts a new chat."

    private static func present(_ items: [ShelfItem], _ missing: Set<String>) -> Bool {
        !items.isEmpty && items.allSatisfy { !missing.contains($0.id) }
    }

    /// Ask: one item at a time (it is off while several are selected), never a folder.
    static func canAsk(_ items: [ShelfItem], missing: Set<String>) -> Bool {
        items.count == 1 && !items[0].folder && present(items, missing)
    }

    /// Send (the share sheet, AirDrop) takes several items and folders.
    static func canSend(_ items: [ShelfItem], missing: Set<String>) -> Bool { present(items, missing) }

    /// Show in Finder takes several items and folders.
    static func canShow(_ items: [ShelfItem], missing: Set<String>) -> Bool { present(items, missing) }
}
