import Foundation

// What the mouse does to the desktop cat (sub-project H), as pure rules: a click waits one double-click interval before it acts (so a double-click never also opens the island),
// a drag begins after 4 points, and the right-click menu is a list the view turns into an NSMenu. Also the little pure rules the controller needs: where the notch spot is, and
// whether a kitten is arriving or leaving. Foundation only; `tests/DesktopCatInputTests.swift` pins them.

/// Press, drag, release and the one-shot timer, as events in; what the cat should do, as events out. The view feeds it the mouse and schedules one timer for `waitUntil`: nothing polls.
struct DesktopCatClicks: Equatable, Sendable {
    /// A press that moves further than this (points) is a drag, not a click (the same on Windows and Linux).
    static let dragThreshold = 4.0

    enum Out: Equatable, Sendable {
        case dragBegan
        case dragMoved(DesktopSpot)
        case dragEnded(DesktopSpot)
        /// A single click, a double-click interval after the release: open the island at the notch with a happy reaction.
        case click
        /// Two clicks inside the interval: send the cat home.
        case doubleClick
    }

    private enum Phase: Equatable, Sendable {
        case idle
        case pressed(second: Bool, from: DesktopSpot)
        case dragging
        case waiting(until: Double)
    }
    private var phase = Phase.idle
    /// `NSEvent.doubleClickInterval`, in seconds.
    var interval: Double

    init(interval: Double) { self.interval = interval.isFinite && interval > 0 ? interval : 0.5 }

    /// The time the one-shot timer must fire at to turn a lone click into a `click`; nil when no click is waiting.
    var waitUntil: Double? { if case .waiting(let t) = phase { return t } else { return nil } }

    /// Times are seconds on one clock (the event's timestamp); a time that is not a number counts as the end of the wait.
    mutating func down(at t: Double, _ p: DesktopSpot) -> [Out] {
        if case .waiting(let until) = phase, t.isFinite, t <= until { phase = .pressed(second: true, from: p); return [] }
        var out: [Out] = []
        if case .waiting = phase { out.append(.click) }   // the wait is over and the timer has not run yet
        phase = .pressed(second: false, from: p)
        return out
    }

    mutating func dragged(_ p: DesktopSpot) -> [Out] {
        switch phase {
        case .pressed(_, let from) where hypot(p.x - from.x, p.y - from.y) > Self.dragThreshold:
            phase = .dragging
            return [.dragBegan, .dragMoved(p)]
        case .dragging: return [.dragMoved(p)]
        default: return []
        }
    }

    mutating func up(at t: Double, _ p: DesktopSpot) -> [Out] {
        switch phase {
        case .pressed(let second, _):
            if second { phase = .idle; return [.doubleClick] }
            phase = .waiting(until: (t.isFinite ? t : 0) + interval)
            return []
        case .dragging: phase = .idle; return [.dragEnded(p)]
        default: return []
        }
    }

    /// The one-shot timer ran.
    mutating func timer(at t: Double) -> [Out] {
        guard case .waiting(let until) = phase, !t.isFinite || t >= until else { return [] }
        phase = .idle
        return [.click]
    }
}

/// The right-click menu: Open the notch, Send home, Size ▸ Small, Medium, Large (the current one ticked), Wardrobe ▸ the 18 choices in their groups (sub-project I, the current one ticked)
/// and, on the Mac, a line showing the shortcut.
enum DesktopCatMenu {
    enum Action: Equatable, Sendable { case openNotch, sendHome, size(DesktopSize), outfit(String) }
    enum Entry: Equatable, Sendable {
        case action(title: String, Action, checked: Bool)
        case submenu(title: String, [Entry])
        case separator
        /// A line that does nothing, shown greyed.
        case note(String)
    }

    /// `shortcut` is the display string of the `desktop` shortcut ("⌃⌥D") when it is on, nil when it is off or the platform has none. `outfit` is the stored wardrobe choice and
    /// `autoToday` what Auto wears today (`Wardrobe.autoOutfit`): the Wardrobe submenu is there only when `outfit` is given.
    static func entries(size: DesktopSize, shortcut: String?, outfit: String? = nil, autoToday: String = "none") -> [Entry] {
        var list: [Entry] = [
            .action(title: "Open the notch", .openNotch, checked: false),
            .action(title: "Send home", .sendHome, checked: false),
            .separator,
            .submenu(title: "Size", [
                .action(title: "Small", .size(.small), checked: size == .small),
                .action(title: "Medium", .size(.medium), checked: size == .medium),
                .action(title: "Large", .size(.large), checked: size == .large),
            ]),
        ]
        if let outfit {
            list.append(.submenu(title: "Wardrobe", WardrobeMenu.items(selected: outfit, autoToday: autoToday).map { item in
                switch item {
                case .choice(let id, let title, let checked): return .action(title: title, .outfit(id), checked: checked)
                case .heading(let name): return .note(name)
                case .separator: return .separator
                }
            }))
        }
        if let shortcut, !shortcut.isEmpty { list += [.separator, .note("Out or home: \(shortcut)")] }
        return list
    }
}

/// Whether the kittens are in motion (`kittenMotion` of `FpsInput`): for 600 ms (`KITTEN_LEAVE_MS`, a kitten's farewell) after **any change to the kitten list**, an arrival or a leave (a kitten
/// that starts to leave changes the list: it is marked `leaving`; one that is gone changes it too). A watch is kept by the controller and asked once per frame; `now` is on the kittens' clock (ms).
struct DesktopKittenWatch: Equatable, Sendable {
    static let motionMs = 600.0
    private var signature: [String] = []
    private var changedAt: Double?

    mutating func observe(_ kittens: [CatKittens.Kitten], now: Double) -> Bool {
        guard now.isFinite else { return false }
        let sig = kittens.map { "\($0.id)|\($0.state == .leaving)" }
        if sig != signature { signature = sig; changedAt = now }
        return changedAt.map { now >= $0 && now - $0 < Self.motionMs } ?? false
    }
}

extension DesktopCatLayout {
    /// The big cat's spot in the notch, in the contract's coordinates: `screenFrame` is the island's screen (contract coordinates), `islandW` the island's width and (`cx`, `cy`)
    /// where `botPosition` puts the cat inside it (from the island's top left). The island is centred on its screen and glued to its top.
    static func notchSpot(screenFrame: DesktopRect, islandW: Double, cx: Double, cy: Double) -> DesktopSpot {
        DesktopSpot(x: screenFrame.x + screenFrame.w / 2 - islandW / 2 + cx, y: screenFrame.y + cy)
    }
}
