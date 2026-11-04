import Foundation

// MARK: - Where the settings live

/// What `ShortcutLogic` needs from a settings store: `UserDefaults` in the app, a dictionary in the tests, so a test
/// run never writes a preferences file.
protocol ShortcutStore {
    func object(forKey key: String) -> Any?
    func set(_ value: Any?, forKey key: String)
}

extension UserDefaults: ShortcutStore {}

// MARK: - Global shortcut actions

/// The global shortcuts NotchMeow registers with Carbon (`HotKeyCenter`), in the order Settings shows them.
/// Island-local shortcuts (⌘→, ⌘K, ⎋ …) are not actions here: `ShortcutLogic.islandCommand` maps them,
/// and a local key monitor in `IslandWindowController` runs them while the island has the keyboard.
///
/// New actions go at the END: Carbon identifies a registered hot key by its index in `allCases`.
enum ShortcutAction: String, CaseIterable, Sendable {
    case toggleIsland       // ⌘⇧N: open or close the island. Off by default, like the old Hotkey setting.
    case openChat           // ⌃⌥Space: open the chat and focus its field. Off by default: macOS uses the combination
    case goToAlert          // ⌃⌥A: jump to the permission request or question that is waiting
    case jumpToTerminal     // ⌃⌥T: bring the agent's terminal forward (not in the App Store build). Off by default: Rectangle
    case attachFrontWindow  // ⌃⌥W: attach the front window to the chat (not in the App Store build)
    case nextPill           // ⌃⌥]: next pill, opening the island if it is closed
    case prevPill           // ⌃⌥[: previous pill
    case muteToggle         // ⌃⌥M: mute or unmute sounds
    case desktop            // ⌃⌥D: the big cat out on the desktop, or home in the notch. On by default; in the App Store build too. The action ID is frozen.
    case shelf              // ⌃⌥S: open the shelf, or close it (sub-project G1). Off by default; in the App Store build too. The action ID is frozen.
    case wardrobe           // ⌃⌥G: the next outfit in the wardrobe's order (Auto and None included, wrapping). Off by default; in the App Store build too. The action ID is frozen.
    case projects           // ⌃⌥P: open the Projects screen, or fold the island when it already shows it (sub-project P-mac). Off by default; in the App Store build too. The action ID is frozen.

    /// `toggleIsland` keeps the storage keys the old Hotkey setting used (`AppState.hotkey*`), so a shortcut
    /// someone already set keeps working. Every other action has keys of its own.
    var udKeyCode: String { self == .toggleIsland ? "hotkeyCode" : "shortcut.\(rawValue).keyCode" }
    var udFlags: String   { self == .toggleIsland ? "hotkeyFlags" : "shortcut.\(rawValue).flags" }
    var udEnabled: String { self == .toggleIsland ? "hotkeyEnabled" : "shortcut.\(rawValue).enabled" }

    var displayName: String {
        switch self {
        case .toggleIsland:      return "Open or close the island"
        case .openChat:          return "Open chat"
        case .goToAlert:         return "Go to alert"
        case .jumpToTerminal:    return "Jump to terminal"
        case .attachFrontWindow: return "Attach front window"
        case .nextPill:          return "Next pill"
        case .prevPill:          return "Previous pill"
        case .muteToggle:        return "Mute or unmute sounds"
        case .desktop:           return "Cat on the desktop"
        case .shelf:             return "Open the shelf"
        case .wardrobe:          return "Next outfit"
        case .projects:          return "Open Projects"
        }
    }

    /// Left out of the App Store build, like the buttons that do the same things.
    var isNonAppStore: Bool { self == .jumpToTerminal || self == .attachFrontWindow }

    /// On at first: the alert, the front window, the two pill keys and mute. Off at first, each with its combination
    /// kept so that turning it on is one click: the island shortcut (off as it always was), the chat (macOS uses
    /// ⌃⌥Space for "Select next source in Input menu") and the terminal (Rectangle uses ⌃⌥T for "Last Two Thirds").
    var enabledByDefault: Bool {
        switch self {
        case .toggleIsland, .openChat, .jumpToTerminal, .shelf, .wardrobe: return false
        case .projects: return false
        case .goToAlert, .attachFrontWindow, .nextPill, .prevPill, .muteToggle, .desktop: return true
        }
    }

    /// Why a shortcut is off at first, for Settings; nil for one that is on, and for the island shortcut, which
    /// is off because it always was.
    var offAtFirstNote: String? {
        switch self {
        case .openChat:
            return "Off at first: macOS uses ⌃⌥Space for \u{201C}Select next source in Input menu\u{201D}."
        case .jumpToTerminal:
            return "Off at first: Rectangle uses ⌃⌥T for \u{201C}Last Two Thirds\u{201D}."
        case .shelf:
            return "Off at first: turn it on to open the shelf with one key."
        case .projects:
            return "Off at first: turn it on to open Projects with one key."
        case .toggleIsland, .goToAlert, .attachFrontWindow, .nextPill, .prevPill, .muteToggle, .desktop, .wardrobe:
            return nil
        }
    }
}

// MARK: - Shortcut spec

/// A key and its modifiers, as plain numbers (no AppKit), so this file builds and tests on its own.
struct ShortcutSpec: Equatable, Hashable, Sendable {
    /// Virtual key code: `NSEvent.keyCode`, the `kVK_*` constants.
    var keyCode: UInt16
    /// `NSEvent.ModifierFlags.rawValue`, only the ⌘ ⇧ ⌥ ⌃ bits.
    var nsFlags: UInt

    // Stable since macOS 10.x (AppKit/NSEvent.h).
    static let cmdBit:   UInt = 1 << 20  // NSEvent.ModifierFlags.command = 1048576
    static let shiftBit: UInt = 1 << 17  // .shift   = 131072
    static let optBit:   UInt = 1 << 19  // .option  = 524288
    static let ctrlBit:  UInt = 1 << 18  // .control = 262144
    static let modMask:  UInt = cmdBit | shiftBit | optBit | ctrlBit
    static let cmdShift: UInt = cmdBit | shiftBit   // 1179648
    static let ctrlOpt:  UInt = ctrlBit | optBit    // 786432

    /// The largest virtual key code a keyboard produces.
    static let maxKeyCode = 127

    var modifierCount: Int {
        [Self.cmdBit, Self.shiftBit, Self.optBit, Self.ctrlBit].filter { nsFlags & $0 != 0 }.count
    }

    /// A global shortcut that no ordinary typing produces: ⌘ or ⌃ is held, with at least one more modifier.
    /// A bare key, ⇧ or ⌥ alone (capital letters, accents) or ⌘ or ⌃ alone (every Edit-menu and Emacs key)
    /// would be taken from every other app while the shortcut is registered.
    var isUsableGlobal: Bool {
        nsFlags & (Self.cmdBit | Self.ctrlBit) != 0 && modifierCount >= 2
    }
}

// MARK: - The recorder

/// What the shortcut recorder does with a key press while it listens.
enum RecorderKey: Equatable, Sendable {
    case cancel                     // ⎋ alone: stop recording
    case passThrough                // no modifier: not a shortcut, the key goes on
    case refuse                     // a combination that is not `isUsableGlobal`: a beep
    case record(ShortcutSpec)       // take it
}

// MARK: - Island-local commands

/// What a key press does while the island has the keyboard (`ShortcutLogic.islandCommand`).
enum IslandCommand: Equatable, Sendable {
    case nextPill, prevPill
    case pill(Int)          // ⌘1 to ⌘9
    case listDown, listUp   // ⌘↓ ⌘↑: move through the list on the card
    case openSelection      // ⌘O
    case toggleDiff         // ⌘E
    case sendMessage        // ⌘↩
    case newConversation    // ⌘K
    case openSettings       // ⌘,
    case togglePin          // ⌘P
    case escape             // ⎋
}

/// Where the island is, as far as key handling cares.
struct IslandKeyContext: Equatable, Sendable {
    var inOverview: Bool
    var inChat: Bool
}

// MARK: - Pure logic

/// Everything about shortcuts that needs no AppKit: tables, storage, validation, key mapping.
enum ShortcutLogic {

    // MARK: Defaults

    static let defaults: [ShortcutAction: ShortcutSpec] = [
        .toggleIsland:      ShortcutSpec(keyCode: 45, nsFlags: ShortcutSpec.cmdShift),  // ⌘⇧N
        .openChat:          ShortcutSpec(keyCode: 49, nsFlags: ShortcutSpec.ctrlOpt),   // ⌃⌥Space
        .goToAlert:         ShortcutSpec(keyCode: 0,  nsFlags: ShortcutSpec.ctrlOpt),   // ⌃⌥A
        .jumpToTerminal:    ShortcutSpec(keyCode: 17, nsFlags: ShortcutSpec.ctrlOpt),   // ⌃⌥T
        .attachFrontWindow: ShortcutSpec(keyCode: 13, nsFlags: ShortcutSpec.ctrlOpt),   // ⌃⌥W
        .nextPill:          ShortcutSpec(keyCode: 30, nsFlags: ShortcutSpec.ctrlOpt),   // ⌃⌥]
        .prevPill:          ShortcutSpec(keyCode: 33, nsFlags: ShortcutSpec.ctrlOpt),   // ⌃⌥[
        .muteToggle:        ShortcutSpec(keyCode: 46, nsFlags: ShortcutSpec.ctrlOpt),   // ⌃⌥M
        .desktop:           ShortcutSpec(keyCode: 2,  nsFlags: ShortcutSpec.ctrlOpt),   // ⌃⌥D
        .shelf:             ShortcutSpec(keyCode: 1,  nsFlags: ShortcutSpec.ctrlOpt),   // ⌃⌥S
        .wardrobe:          ShortcutSpec(keyCode: 5,  nsFlags: ShortcutSpec.ctrlOpt),   // ⌃⌥G
        .projects:          ShortcutSpec(keyCode: 35, nsFlags: ShortcutSpec.ctrlOpt),   // ⌃⌥P
    ]

    // MARK: Build

    #if APPSTORE
    static let isAppStoreBuild = true
    #else
    static let isAppStoreBuild = false
    #endif

    /// The actions this build offers, in Settings order.
    static func available(appStore: Bool = isAppStoreBuild) -> [ShortcutAction] {
        ShortcutAction.allCases.filter { !(appStore && $0.isNonAppStore) }
    }

    // MARK: Storage

    /// The stored shortcut, or the default when nothing is stored or what is stored cannot be trusted:
    /// a key code outside 0...127 (a hand-edited value used to trap in `UInt16(_:)`), a missing half,
    /// or a combination that is not `isUsableGlobal`.
    static func hotKey(for action: ShortcutAction, in store: any ShortcutStore = UserDefaults.standard) -> ShortcutSpec {
        let def = defaults[action]!
        guard let kc = store.object(forKey: action.udKeyCode) as? Int,
              let fl = store.object(forKey: action.udFlags) as? Int,
              (0...ShortcutSpec.maxKeyCode).contains(kc), fl >= 0 else { return def }
        let spec = ShortcutSpec(keyCode: UInt16(kc), nsFlags: UInt(fl) & ShortcutSpec.modMask)
        return spec.isUsableGlobal ? spec : def
    }

    static func save(_ spec: ShortcutSpec, for action: ShortcutAction, in store: any ShortcutStore = UserDefaults.standard) {
        store.set(Int(spec.keyCode), forKey: action.udKeyCode)
        store.set(Int(spec.nsFlags), forKey: action.udFlags)
    }

    static func isEnabled(_ action: ShortcutAction, in store: any ShortcutStore = UserDefaults.standard) -> Bool {
        store.object(forKey: action.udEnabled) as? Bool ?? action.enabledByDefault
    }

    static func setEnabled(_ enabled: Bool, for action: ShortcutAction, in store: any ShortcutStore = UserDefaults.standard) {
        store.set(enabled, forKey: action.udEnabled)
    }

    static func resetToDefault(_ action: ShortcutAction, in store: any ShortcutStore = UserDefaults.standard) {
        save(defaults[action]!, for: action, in: store)
        setEnabled(action.enabledByDefault, for: action, in: store)
    }

    /// A shortcut that "Turn all on" left off, and why.
    struct TurnOnResult: Equatable, Sendable {
        enum Reason: Equatable, Sendable {
            case taken                          // macOS refused the combination: another app has it
            case duplicate(of: ShortcutAction)  // another NotchMeow shortcut already has it
        }
        var action: ShortcutAction
        var reason: Reason
    }

    /// Turns on every shortcut of this build that is off, except those whose combination is not free, and returns
    /// those (in list order). A shortcut already on is left alone. `tryOn` is called once per shortcut that is
    /// switched on; it must register it with the system and say whether that worked (the app passes
    /// `HotKeyCenter`), and a `false` puts the switch back off. A combination another shortcut already has is
    /// refused without asking.
    static func turnAllOn(appStore: Bool = isAppStoreBuild, in store: any ShortcutStore = UserDefaults.standard,
                          tryOn: (ShortcutAction) -> Bool) -> [TurnOnResult] {
        var active = activeSpecs(appStore: appStore, in: store)
        var left: [TurnOnResult] = []
        for action in available(appStore: appStore) where active[action] == nil {
            let spec = hotKey(for: action, in: store)
            if let owner = ShortcutAction.allCases.first(where: { active[$0] == spec }) {
                left.append(TurnOnResult(action: action, reason: .duplicate(of: owner)))
                continue
            }
            setEnabled(true, for: action, in: store)
            if tryOn(action) {
                active[action] = spec
            } else {
                setEnabled(false, for: action, in: store)
                left.append(TurnOnResult(action: action, reason: .taken))
            }
        }
        return left
    }

    /// What Settings says after "Turn all on", nil when everything is on.
    static func turnOnSummary(_ left: [TurnOnResult]) -> String? {
        guard !left.isEmpty else { return nil }
        let parts = left.map { result -> String in
            switch result.reason {
            case .taken:                 return "\(result.action.displayName) (in use elsewhere)"
            case .duplicate(let owner):  return "\(result.action.displayName) (same keys as \(owner.displayName))"
            }
        }
        return "Left off: " + parts.joined(separator: ", ")
    }

    /// The shortcuts that are on, for this build: what `HotKeyCenter` registers.
    static func activeSpecs(appStore: Bool = isAppStoreBuild,
                            in store: any ShortcutStore = UserDefaults.standard) -> [ShortcutAction: ShortcutSpec] {
        var out: [ShortcutAction: ShortcutSpec] = [:]
        for action in available(appStore: appStore) where isEnabled(action, in: store) {
            out[action] = hotKey(for: action, in: store)
        }
        return out
    }

    // MARK: Carbon

    // Carbon modifier bits (Events.h), as plain numbers so no import is needed.
    private static let cCmdKey:   UInt32 = 1 << 8   // cmdKey     = 256
    private static let cShiftKey: UInt32 = 1 << 9   // shiftKey   = 512
    private static let cOptKey:   UInt32 = 1 << 11  // optionKey  = 2048
    private static let cCtrlKey:  UInt32 = 1 << 12  // controlKey = 4096

    static func carbonModifiers(fromNS nsFlags: UInt) -> UInt32 {
        var c: UInt32 = 0
        if nsFlags & ShortcutSpec.cmdBit   != 0 { c |= cCmdKey }
        if nsFlags & ShortcutSpec.shiftBit != 0 { c |= cShiftKey }
        if nsFlags & ShortcutSpec.optBit   != 0 { c |= cOptKey }
        if nsFlags & ShortcutSpec.ctrlBit  != 0 { c |= cCtrlKey }
        return c
    }

    // MARK: Conflicts inside NotchMeow

    /// The actions whose combination is shared with another action in `specs`.
    static func duplicates(in specs: [ShortcutAction: ShortcutSpec]) -> Set<ShortcutAction> {
        var seen: [ShortcutSpec: ShortcutAction] = [:]
        var dups: Set<ShortcutAction> = []
        for action in ShortcutAction.allCases {
            guard let spec = specs[action] else { continue }
            if let other = seen[spec] {
                dups.insert(action)
                dups.insert(other)
            } else {
                seen[spec] = action
            }
        }
        return dups
    }

    // MARK: Display

    /// "⌃⌥A", "⌘⇧N": modifiers in the order macOS shows them, then the key. A shortcut is a key position, so
    /// `keyName` can give the character printed on that key in the layout in use (`KeyLayoutNames`): the key
    /// labelled A on an AZERTY keyboard is the one the US layout calls Q. A key it has no name for (Space, the
    /// arrows, F1) keeps the name of `keyCodeToString`.
    static func displayString(for spec: ShortcutSpec, keyName: (UInt16) -> String? = { _ in nil }) -> String {
        var s = ""
        if spec.nsFlags & ShortcutSpec.ctrlBit  != 0 { s += "⌃" }
        if spec.nsFlags & ShortcutSpec.optBit   != 0 { s += "⌥" }
        if spec.nsFlags & ShortcutSpec.shiftBit != 0 { s += "⇧" }
        if spec.nsFlags & ShortcutSpec.cmdBit   != 0 { s += "⌘" }
        return s + (keyName(spec.keyCode) ?? keyCodeToString(spec.keyCode))
    }

    /// The name of a virtual key code, "·" for a key without one here.
    static func keyCodeToString(_ code: UInt16) -> String {
        keyNames[code] ?? "·"
    }

    private static let keyNames: [UInt16: String] = [
        0: "A", 1: "S", 2: "D", 3: "F", 4: "H", 5: "G", 6: "Z", 7: "X", 8: "C", 9: "V",
        11: "B", 12: "Q", 13: "W", 14: "E", 15: "R", 16: "Y", 17: "T",
        18: "1", 19: "2", 20: "3", 21: "4", 22: "6", 23: "5", 24: "=", 25: "9", 26: "7", 27: "-",
        28: "8", 29: "0", 30: "]", 31: "O", 32: "U", 33: "[", 34: "I", 35: "P", 37: "L", 38: "J",
        39: "'", 40: "K", 41: ";", 42: "\\", 43: ",", 44: "/", 45: "N", 46: "M", 47: ".",
        36: "↩", 48: "⇥", 49: "Space", 50: "`", 51: "⌫", 53: "⎋",
        123: "←", 124: "→", 125: "↓", 126: "↑",
        122: "F1", 120: "F2", 99: "F3", 118: "F4", 96: "F5", 97: "F6",
        98: "F7", 100: "F8", 101: "F9", 109: "F10", 103: "F11", 111: "F12",
    ]

    // MARK: Lists and pills

    /// The next list selection: nil on an empty list, clamped to the list, and from nothing selected ↓ takes
    /// the first row and ↑ the last.
    static func navigate(selection: Int?, delta: Int, itemCount: Int) -> Int? {
        guard itemCount > 0 else { return nil }
        if let cur = selection { return max(0, min(itemCount - 1, cur + delta)) }
        return delta > 0 ? 0 : itemCount - 1
    }

    /// A selection kept inside a list that shrank: nil when nothing is selected or the list is empty.
    static func clampSelection(_ selection: Int?, itemCount: Int) -> Int? {
        guard let s = selection, itemCount > 0 else { return nil }
        return min(max(s, 0), itemCount - 1)
    }

    /// The pill `delta` steps from `current`, wrapping around. An unknown or missing `current` counts as the first.
    /// Nil when there are no pills, and nil while a permission request or a question is waiting
    /// (`decisionWaiting`): its card must stay on screen, with the agent it belongs to.
    static func pillID(from ids: [String], current: String?, delta: Int, decisionWaiting: Bool) -> String? {
        guard !decisionWaiting, !ids.isEmpty else { return nil }
        let cur = current.flatMap { ids.firstIndex(of: $0) } ?? 0
        let n = ids.count
        return ids[((cur + delta) % n + n) % n]
    }

    /// The pill for ⌘1 to ⌘9: nil when there is none, and nil while a decision is waiting.
    static func pillID(number: Int, in ids: [String], decisionWaiting: Bool) -> String? {
        guard !decisionWaiting, ids.indices.contains(number - 1) else { return nil }
        return ids[number - 1]
    }

    // MARK: Recorder

    /// What the recorder does with this key press.
    static func recorderKey(keyCode: UInt16, nsFlags: UInt) -> RecorderKey {
        let mods = nsFlags & ShortcutSpec.modMask
        if keyCode == 53 && mods == 0 { return .cancel }
        if mods == 0 { return .passThrough }
        let spec = ShortcutSpec(keyCode: keyCode, nsFlags: mods)
        return spec.isUsableGlobal && Int(keyCode) <= ShortcutSpec.maxKeyCode ? .record(spec) : .refuse
    }

    // MARK: Island-local keys

    private static let digitKeyCodes: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]

    /// What a key press means while the island has the keyboard, nil when the island leaves it alone.
    /// Only ⌘ with nothing else counts (⌘⇧N and friends are not island keys). In the chat, ⌘ with an arrow keeps
    /// moving the cursor in the text field instead of moving between pills. ⌘, is the comma wherever the layout puts
    /// it: `characters` is the key's character without modifiers (`NSEvent.charactersIgnoringModifiers`); without
    /// it, the US position (key code 43) stands in. The other keys are positions, which are the same on the layouts
    /// that matter here (the letters O, E, K and P and the number row).
    static func islandCommand(keyCode: UInt16, nsFlags: UInt, characters: String? = nil,
                              in ctx: IslandKeyContext) -> IslandCommand? {
        let mods = nsFlags & ShortcutSpec.modMask
        if keyCode == 53 && mods == 0 { return .escape }
        guard mods == ShortcutSpec.cmdBit else { return nil }
        if let characters { if characters == "," { return .openSettings } } else if keyCode == 43 { return .openSettings }
        switch keyCode {
        case 124: return ctx.inChat ? nil : .nextPill
        case 123: return ctx.inChat ? nil : .prevPill
        case 125: return ctx.inChat ? nil : .listDown
        case 126: return ctx.inChat ? nil : .listUp
        case 31:  return .openSelection
        case 14:  return ctx.inOverview ? .toggleDiff : nil
        case 36:  return ctx.inChat ? .sendMessage : nil
        case 40:  return ctx.inChat ? .newConversation : nil
        case 35:  return .togglePin
        default:  return digitKeyCodes[keyCode].map { .pill($0) }
        }
    }

    /// The island-local shortcuts, as Settings lists them (read-only).
    static let islandShortcuts: [(key: String, description: String)] = [
        ("⌘→ / ⌘←", "Next or previous pill"),
        ("⌘1 to ⌘9", "Go to a pill by its number"),
        ("⌘↓ / ⌘↑", "Move through a list"),
        ("⌘O", "Open the selected item"),
        ("⌘E", "Open or close the latest diff"),
        ("⌘↩", "Send the chat message"),
        ("⌘K", "Start a new conversation"),
        ("⌘,", "Open Settings"),
        ("⌘P", "Pin or unpin the island"),
        ("⎋", "Close the island, or go back"),
    ]

    // MARK: Terminals

    /// The terminals ⌃⌥T and the cards' "Open terminal" button bring forward, in order of preference.
    static let terminalBundleIds = ["com.apple.Terminal", "com.googlecode.iterm2",
                                    "net.kovidgoyal.kitty", "com.mitchellh.ghostty"]
}
