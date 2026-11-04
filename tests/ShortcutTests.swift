import Foundation

@main
enum ShortcutTests {
    nonisolated(unsafe) static var cases = 0

    /// One case: counts it, and stops the run with `message` when it fails.
    static func check(_ ok: Bool, _ message: @autoclosure () -> String,
                      file: StaticString = #file, line: UInt = #line) {
        cases += 1
        precondition(ok, message(), file: file, line: line)
    }

    static func main() {
        testDefaults()
        testUsableCombinations()
        testCarbonModifiers()
        testDisplayStrings()
        testDuplicates()
        testStorage()
        testLegacyHotkeyKeys()
        testStoredValuesThatCannotBeTrusted()
        testEnabledAndReset()
        testBuildsAndActiveSpecs()
        testTurnAllOn()
        testTurnOnSummary()
        testListSelection()
        testPills()
        testIslandKeys()
        testIslandKeysInTheChat()
        testIslandKeysWithOtherModifiers()
        testRecorderKeys()
        testTables()
        print("Shortcuts: \(cases) cases passed")
    }

    /// A settings store in memory, so a test run never writes a preferences file.
    final class MemoryStore: ShortcutStore {
        var values: [String: Any] = [:]
        func object(forKey key: String) -> Any? { values[key] }
        func set(_ value: Any?, forKey key: String) { values[key] = value }
    }

    /// A fresh, empty store for `body`.
    static func withDefaults(_ body: (MemoryStore) -> Void) { body(MemoryStore()) }

    static let ctrlOpt = ShortcutSpec.ctrlOpt
    static let cmd = ShortcutSpec.cmdBit
    static let shift = ShortcutSpec.shiftBit
    static let opt = ShortcutSpec.optBit
    static let ctrl = ShortcutSpec.ctrlBit

    // MARK: Defaults

    static func testDefaults() {
        for action in ShortcutAction.allCases {
            check(ShortcutLogic.defaults[action] != nil, "no default for \(action.rawValue)")
        }
        check(ShortcutLogic.defaults.count == ShortcutAction.allCases.count, "the table must cover every action, and only those")
        for (action, spec) in ShortcutLogic.defaults {
            check(spec.isUsableGlobal, "default of \(action.rawValue) would take plain typing from every app")
        }
        check(ShortcutLogic.duplicates(in: ShortcutLogic.defaults).isEmpty, "two defaults share a combination")
        testDefaultsOnAndOff()
        // Carbon identifies a hot key by its index in allCases: new actions are appended, never inserted.
        check(ShortcutAction.allCases.first == .toggleIsland && ShortcutAction.allCases.last == .projects,
              "action order changed")
    }

    // MARK: Which shortcuts are on at first

    /// The owner's decision: five on, three off, and since sub-project H the desktop cat's ⌃⌥D on as well (six on). Since sub-project I ⌃⌥G, the next outfit, is off at first (with the shelf's, five off), so it
    /// cannot take a key from someone who never asked. The off ones keep their combinations so that turning one on is a click.
    static func testDefaultsOnAndOff() {
        let on: Set<ShortcutAction> = [.goToAlert, .attachFrontWindow, .nextPill, .prevPill, .muteToggle, .desktop]
        let off: Set<ShortcutAction> = [.toggleIsland, .openChat, .jumpToTerminal, .shelf, .wardrobe, .projects]   // the shelf's ⌃⌥S (sub-project G1), the wardrobe's ⌃⌥G (sub-project I) and the Projects key's ⌃⌥P (P-mac) are off at first too
        check(on.union(off) == Set(ShortcutAction.allCases) && on.isDisjoint(with: off), "every action is on or off at first")
        for action in on { check(action.enabledByDefault, "\(action.rawValue) is on at first") }
        for action in off { check(!action.enabledByDefault, "\(action.rawValue) is off at first") }
        withDefaults { ud in
            check(Set(ShortcutLogic.activeSpecs(appStore: false, in: ud).keys) == on, "a fresh store registers exactly the six")
            check(Set(ShortcutLogic.activeSpecs(appStore: true, in: ud).keys) == [.goToAlert, .nextPill, .prevPill, .muteToggle, .desktop],
                  "and five in the App Store build, which has no front-window shortcut and does have the desktop cat")
            check(ShortcutLogic.hotKey(for: .desktop, in: ud) == ShortcutSpec(keyCode: 2, nsFlags: ctrlOpt), "⌃⌥D is the desktop cat's")
            check(ShortcutLogic.hotKey(for: .wardrobe, in: ud) == ShortcutSpec(keyCode: 5, nsFlags: ctrlOpt) && !ShortcutLogic.isEnabled(.wardrobe, in: ud), "⌃⌥G is the wardrobe's, and it is off at first")
            // Off at first, and the combination is still there: a click turns it on.
            check(ShortcutLogic.hotKey(for: .openChat, in: ud) == ShortcutSpec(keyCode: 49, nsFlags: ctrlOpt), "⌃⌥Space is kept for the chat")
            check(ShortcutLogic.hotKey(for: .jumpToTerminal, in: ud) == ShortcutSpec(keyCode: 17, nsFlags: ctrlOpt), "⌃⌥T is kept for the terminal")
            check(ShortcutLogic.hotKey(for: .toggleIsland, in: ud) == ShortcutSpec(keyCode: 45, nsFlags: ShortcutSpec.cmdShift), "⌘⇧N is kept for the island")
            ShortcutLogic.setEnabled(true, for: .openChat, in: ud)
            check(ShortcutLogic.activeSpecs(appStore: false, in: ud)[.openChat] == ShortcutSpec(keyCode: 49, nsFlags: ctrlOpt),
                  "turned on, the chat is registered under ⌃⌥Space")
        }
        // The shelf's key (sub-project G1): ⌃⌥S, off at first, in both builds, and registered when it is turned on.
        withDefaults { ud in
            check(ShortcutLogic.hotKey(for: .shelf, in: ud) == ShortcutSpec(keyCode: 1, nsFlags: ctrlOpt), "⌃⌥S is the shelf's, kept while it is off")
            check(!ShortcutLogic.isEnabled(.shelf, in: ud) && ShortcutLogic.activeSpecs(appStore: false, in: ud)[.shelf] == nil && ShortcutLogic.activeSpecs(appStore: true, in: ud)[.shelf] == nil, "the shelf's shortcut is off at first, in both builds")
            check(!ShortcutAction.shelf.isNonAppStore && ShortcutLogic.available(appStore: true).contains(.shelf), "and is offered in the App Store build")
            ShortcutLogic.setEnabled(true, for: .shelf, in: ud)
            check(ShortcutLogic.activeSpecs(appStore: true, in: ud)[.shelf] == ShortcutSpec(keyCode: 1, nsFlags: ctrlOpt), "turned on, it is registered, in the App Store build too")
        }
        check(ShortcutAction.shelf.rawValue == "shelf" && ShortcutAction.shelf.offAtFirstNote?.contains("shelf") == true, "the action ID is frozen as shelf, and Settings says why it is off")
        // The wardrobe's key (sub-project I): ⌃⌥G, off at first, in both builds (the App Store build offers it), registered when it is turned on, and its ID is frozen.
        withDefaults { ud in
            check(ShortcutLogic.activeSpecs(appStore: false, in: ud)[.wardrobe] == nil && ShortcutLogic.activeSpecs(appStore: true, in: ud)[.wardrobe] == nil, "the wardrobe's shortcut is off at first, in both builds")
            check(!ShortcutAction.wardrobe.isNonAppStore && ShortcutLogic.available(appStore: true).contains(.wardrobe), "and is offered in the App Store build")
            ShortcutLogic.setEnabled(true, for: .wardrobe, in: ud)
            check(ShortcutLogic.activeSpecs(appStore: true, in: ud)[.wardrobe] == ShortcutSpec(keyCode: 5, nsFlags: ctrlOpt), "turned on, it is registered under ⌃⌥G, in the App Store build too")
        }
        check(ShortcutAction.wardrobe.rawValue == "wardrobe" && ShortcutAction.wardrobe.displayName == "Next outfit", "the action ID is frozen as wardrobe")
        // The Projects key (sub-project P-mac): ⌃⌥P, off at first, in both builds (the App Store build offers it), registered when it is turned on, its ID and name frozen.
        withDefaults { ud in
            check(ShortcutLogic.hotKey(for: .projects, in: ud) == ShortcutSpec(keyCode: 35, nsFlags: ctrlOpt) && !ShortcutLogic.isEnabled(.projects, in: ud), "⌃⌥P is the Projects key, and it is off at first")
            check(ShortcutLogic.activeSpecs(appStore: false, in: ud)[.projects] == nil && ShortcutLogic.activeSpecs(appStore: true, in: ud)[.projects] == nil, "the Projects key is not registered at first, in both builds")
            check(!ShortcutAction.projects.isNonAppStore && ShortcutLogic.available(appStore: true).contains(.projects), "and is offered in the App Store build")
            ShortcutLogic.setEnabled(true, for: .projects, in: ud)
            check(ShortcutLogic.activeSpecs(appStore: true, in: ud)[.projects] == ShortcutSpec(keyCode: 35, nsFlags: ctrlOpt), "turned on, it is registered under ⌃⌥P, in the App Store build too")
        }
        check(ShortcutAction.projects.rawValue == "projects" && ShortcutAction.projects.displayName == "Open Projects", "the action ID is frozen as projects, and Settings names it Open Projects")
        check(ShortcutAction.projects.offAtFirstNote?.contains("Projects") == true, "Settings says why it is off")
        // The note Settings shows: for the two that are off because another app uses the combination, and for no other.
        check(ShortcutAction.openChat.offAtFirstNote?.contains("⌃⌥Space") == true
              && ShortcutAction.openChat.offAtFirstNote?.contains("Select next source in Input menu") == true, "the chat's note names macOS's shortcut")
        check(ShortcutAction.jumpToTerminal.offAtFirstNote?.contains("⌃⌥T") == true
              && ShortcutAction.jumpToTerminal.offAtFirstNote?.contains("Rectangle") == true
              && ShortcutAction.jumpToTerminal.offAtFirstNote?.contains("Last Two Thirds") == true, "the terminal's note names Rectangle's")
        for action in ShortcutAction.allCases where action != .openChat && action != .jumpToTerminal && action != .shelf && action != .projects {
            check(action.offAtFirstNote == nil, "\(action.rawValue) has no note")
        }
    }

    // MARK: Which combinations may be global

    static func testUsableCombinations() {
        func usable(_ flags: UInt) -> Bool { ShortcutSpec(keyCode: 0, nsFlags: flags).isUsableGlobal }
        check(!usable(0), "a bare key")
        check(!usable(shift), "⇧ alone types capital letters")
        check(!usable(opt), "⌥ alone types accents")
        check(!usable(shift | opt), "⇧⌥ types symbols")
        check(!usable(cmd), "⌘ alone is every Edit-menu key")
        check(!usable(ctrl), "⌃ alone is every Emacs key in a text field")
        check(usable(cmd | shift), "⌘⇧")
        check(usable(cmd | opt), "⌘⌥")
        check(usable(cmd | ctrl), "⌘⌃")
        check(usable(ctrl | opt), "⌃⌥")
        check(usable(ctrl | shift), "⌃⇧")
        check(usable(cmd | shift | opt | ctrl), "all four")
        check(ShortcutSpec(keyCode: 0, nsFlags: cmd | shift).modifierCount == 2, "two modifiers")
        check(ShortcutSpec(keyCode: 0, nsFlags: 0).modifierCount == 0, "no modifiers")
    }

    // MARK: Carbon

    static func testCarbonModifiers() {
        let cmdShift = ShortcutLogic.carbonModifiers(fromNS: ShortcutSpec.cmdShift)
        check(cmdShift == 256 | 512, "⌘⇧ is cmdKey | shiftKey (\(cmdShift))")
        let ctrlOpt = ShortcutLogic.carbonModifiers(fromNS: ShortcutSpec.ctrlOpt)
        check(ctrlOpt == 4096 | 2048, "⌃⌥ is controlKey | optionKey (\(ctrlOpt))")
        check(ShortcutLogic.carbonModifiers(fromNS: 0) == 0, "no modifiers, no Carbon bits")
        let all = ShortcutLogic.carbonModifiers(fromNS: cmd | shift | opt | ctrl)
        check(all == 256 | 512 | 2048 | 4096, "all four")
        check(ShortcutLogic.carbonModifiers(fromNS: 1 << 16) == 0, "caps lock is not a Carbon modifier here")
    }

    // MARK: Display

    static func testDisplayStrings() {
        check(ShortcutLogic.displayString(for: ShortcutLogic.defaults[.toggleIsland]!) == "⇧⌘N", "⌘⇧N shows as ⇧⌘N")
        check(ShortcutLogic.displayString(for: ShortcutLogic.defaults[.goToAlert]!) == "⌃⌥A", "⌃⌥A")
        check(ShortcutLogic.displayString(for: ShortcutLogic.defaults[.openChat]!) == "⌃⌥Space", "⌃⌥Space")
        check(ShortcutLogic.displayString(for: ShortcutLogic.defaults[.nextPill]!) == "⌃⌥]", "⌃⌥]")
        check(ShortcutLogic.displayString(for: ShortcutLogic.defaults[.prevPill]!) == "⌃⌥[", "⌃⌥[")
        check(ShortcutLogic.displayString(for: ShortcutSpec(keyCode: 49, nsFlags: cmd | shift | opt | ctrl)) == "⌃⌥⇧⌘Space",
              "modifier order is ⌃⌥⇧⌘")
        check(ShortcutLogic.keyCodeToString(123) == "←" && ShortcutLogic.keyCodeToString(126) == "↑", "arrows")
        check(ShortcutLogic.keyCodeToString(29) == "0" && ShortcutLogic.keyCodeToString(18) == "1", "digits")
        check(ShortcutLogic.keyCodeToString(50) == "`" && ShortcutLogic.keyCodeToString(27) == "-",
              "keys the General recorder already named")
        check(ShortcutLogic.keyCodeToString(122) == "F1", "F1")
        check(ShortcutLogic.keyCodeToString(127) == "·", "a key without a name shows a dot")
        // The layout in use names the key: on AZERTY the key at position 0 is labelled Q, the one at 12 is A.
        let azerty: (UInt16) -> String? = { code in [0: "Q", 12: "A", 13: "Z", 41: "M"][code] }
        check(ShortcutLogic.displayString(for: ShortcutSpec(keyCode: 0, nsFlags: ctrlOpt), keyName: azerty) == "⌃⌥Q",
              "the default ⌃⌥A is the key labelled Q on AZERTY")
        check(ShortcutLogic.displayString(for: ShortcutSpec(keyCode: 12, nsFlags: ctrlOpt), keyName: azerty) == "⌃⌥A", "and ⌃⌥Q is labelled A")
        check(ShortcutLogic.displayString(for: ShortcutSpec(keyCode: 49, nsFlags: ctrlOpt), keyName: azerty) == "⌃⌥Space",
              "a key the layout has no name for keeps its own")
        check(ShortcutLogic.displayString(for: ShortcutSpec(keyCode: 0, nsFlags: ctrlOpt)) == "⌃⌥A", "no layout, the US names")
        // Every key a default uses has a real name.
        for (action, spec) in ShortcutLogic.defaults {
            check(ShortcutLogic.keyCodeToString(spec.keyCode) != "·", "\(action.rawValue) shows a dot")
        }
    }

    // MARK: Duplicates inside NotchMeow

    static func testDuplicates() {
        check(ShortcutLogic.duplicates(in: [:]).isEmpty, "nothing, no duplicates")
        let a = ShortcutSpec(keyCode: 0, nsFlags: ctrlOpt)
        let b = ShortcutSpec(keyCode: 17, nsFlags: ctrlOpt)
        check(ShortcutLogic.duplicates(in: [.goToAlert: a]).isEmpty, "one entry")
        check(ShortcutLogic.duplicates(in: [.goToAlert: a, .jumpToTerminal: b]).isEmpty, "two different keys")
        check(ShortcutLogic.duplicates(in: [.goToAlert: a, .jumpToTerminal: a]) == [.goToAlert, .jumpToTerminal],
              "the same combination flags both actions")
        let c = ShortcutSpec(keyCode: 0, nsFlags: ShortcutSpec.cmdShift)
        check(ShortcutLogic.duplicates(in: [.goToAlert: a, .jumpToTerminal: c]).isEmpty, "same key, other modifiers")
        check(ShortcutLogic.duplicates(in: [.goToAlert: a, .jumpToTerminal: a, .muteToggle: a]).count == 3, "three share one")
    }

    // MARK: Storage

    static func testStorage() {
        withDefaults { ud in
            for action in ShortcutAction.allCases {
                check(ShortcutLogic.hotKey(for: action, in: ud) == ShortcutLogic.defaults[action]!, "nothing stored: the default")
            }
            let custom = ShortcutSpec(keyCode: 5, nsFlags: ShortcutSpec.cmdShift)
            ShortcutLogic.save(custom, for: .openChat, in: ud)
            check(ShortcutLogic.hotKey(for: .openChat, in: ud) == custom, "a saved shortcut comes back")
            check(ShortcutLogic.hotKey(for: .goToAlert, in: ud) == ShortcutLogic.defaults[.goToAlert]!, "others are untouched")
            check(ud.object(forKey: "shortcut.openChat.keyCode") as? Int == 5, "stored under its own key")
            check(ud.object(forKey: "shortcut.openChat.flags") as? Int == Int(ShortcutSpec.cmdShift), "flags stored as an Int")
        }
    }

    /// What the old Hotkey setting wrote (`AppState.hotkey*`) must still be read as the island shortcut.
    static func testLegacyHotkeyKeys() {
        check(ShortcutAction.toggleIsland.udKeyCode == "hotkeyCode", "legacy code key")
        check(ShortcutAction.toggleIsland.udFlags == "hotkeyFlags", "legacy flags key")
        check(ShortcutAction.toggleIsland.udEnabled == "hotkeyEnabled", "legacy enabled key")
        for action in ShortcutAction.allCases where action != .toggleIsland {
            check(action.udKeyCode == "shortcut.\(action.rawValue).keyCode", "\(action.rawValue) has its own code key")
            check(action.udFlags == "shortcut.\(action.rawValue).flags", "\(action.rawValue) has its own flags key")
            check(action.udEnabled == "shortcut.\(action.rawValue).enabled", "\(action.rawValue) has its own enabled key")
        }
        withDefaults { ud in
            // A person who set ⌃⌘J and turned the hotkey on, with the old build.
            ud.set(true, forKey: "hotkeyEnabled")
            ud.set(Int(ctrl | cmd), forKey: "hotkeyFlags")
            ud.set(38, forKey: "hotkeyCode")
            check(ShortcutLogic.isEnabled(.toggleIsland, in: ud), "the old toggle is read")
            check(ShortcutLogic.hotKey(for: .toggleIsland, in: ud) == ShortcutSpec(keyCode: 38, nsFlags: ctrl | cmd),
                  "the old combination is read")
            check(ShortcutLogic.activeSpecs(appStore: false, in: ud)[.toggleIsland] == ShortcutSpec(keyCode: 38, nsFlags: ctrl | cmd),
                  "and registered")
        }
    }

    /// A hand-edited file, an old build, a stray write: never a trap, never a shortcut that eats typing.
    static func testStoredValuesThatCannotBeTrusted() {
        let def = ShortcutLogic.defaults[.openChat]!
        func load(code: Any?, flags: Any?) -> ShortcutSpec {
            var result = def
            withDefaults { ud in
                if let code { ud.set(code, forKey: ShortcutAction.openChat.udKeyCode) }
                if let flags { ud.set(flags, forKey: ShortcutAction.openChat.udFlags) }
                result = ShortcutLogic.hotKey(for: .openChat, in: ud)
            }
            return result
        }
        let good = Int(ctrl | opt)
        check(load(code: -1, flags: good) == def, "a negative key code (UInt16(-1) used to trap)")
        check(load(code: 70000, flags: good) == def, "a key code beyond UInt16 (used to trap)")
        check(load(code: 128, flags: good) == def, "a key code no keyboard has")
        check(load(code: 5, flags: -1) == def, "negative flags (UInt(-1) used to trap)")
        check(load(code: "A", flags: good) == def, "a key code of the wrong type")
        check(load(code: 5, flags: "x") == def, "flags of the wrong type")
        check(load(code: 5, flags: nil) == def, "only the code stored")
        check(load(code: nil, flags: good) == def, "only the flags stored")
        check(load(code: 5, flags: 0) == def, "no modifier would take the bare key from every app")
        check(load(code: 5, flags: Int(shift)) == def, "⇧ alone")
        check(load(code: 5, flags: Int(opt)) == def, "⌥ alone")
        check(load(code: 5, flags: Int(cmd)) == def, "⌘ alone")
        check(load(code: 5, flags: Int(ctrl)) == def, "⌃ alone")
        check(load(code: 5, flags: Int(ctrl | opt)) == ShortcutSpec(keyCode: 5, nsFlags: ctrl | opt), "a good value is kept")
        check(load(code: 127, flags: good) == ShortcutSpec(keyCode: 127, nsFlags: ctrl | opt), "the last key code")
        check(load(code: 0, flags: good) == ShortcutSpec(keyCode: 0, nsFlags: ctrl | opt), "the first key code")
        check(load(code: 5, flags: good | Int(1 << 16) | Int(1 << 23)) == ShortcutSpec(keyCode: 5, nsFlags: ctrl | opt),
              "caps lock and the numeric-pad bit are dropped")
        let nsNumber: NSNumber = NSNumber(value: Int(ctrl | opt))
        check(load(code: NSNumber(value: 5), flags: nsNumber) == ShortcutSpec(keyCode: 5, nsFlags: ctrl | opt), "NSNumber values")
    }

    // MARK: On or off

    static func testEnabledAndReset() {
        withDefaults { ud in
            check(!ShortcutLogic.isEnabled(.toggleIsland, in: ud), "the island shortcut is off at first")
            check(ShortcutLogic.isEnabled(.goToAlert, in: ud), "the alert shortcut is on at first")
            ShortcutLogic.setEnabled(true, for: .toggleIsland, in: ud)
            ShortcutLogic.setEnabled(false, for: .goToAlert, in: ud)
            check(ShortcutLogic.isEnabled(.toggleIsland, in: ud) && !ShortcutLogic.isEnabled(.goToAlert, in: ud), "both switches stick")
            ShortcutLogic.save(ShortcutSpec(keyCode: 5, nsFlags: ShortcutSpec.cmdShift), for: .openChat, in: ud)
            for action in ShortcutAction.allCases { ShortcutLogic.resetToDefault(action, in: ud) }
            for action in ShortcutAction.allCases {
                check(ShortcutLogic.isEnabled(action, in: ud) == action.enabledByDefault, "\(action.rawValue) is back on or off as shipped")
                check(ShortcutLogic.hotKey(for: action, in: ud) == ShortcutLogic.defaults[action]!, "\(action.rawValue) is back to its default")
            }
        }
    }

    // MARK: Builds

    static func testBuildsAndActiveSpecs() {
        let all = ShortcutLogic.available(appStore: false)
        check(all == ShortcutAction.allCases, "the GitHub build offers every action, in order")
        let store = ShortcutLogic.available(appStore: true)
        check(!store.contains(.jumpToTerminal) && !store.contains(.attachFrontWindow), "no terminal or window shortcuts in the App Store build")
        check(store.count == all.count - 2, "and nothing else is dropped")
        check(store.contains(.openChat) && store.contains(.muteToggle) && store.contains(.nextPill), "the rest stays")
        withDefaults { ud in
            let normal = ShortcutLogic.activeSpecs(appStore: false, in: ud)
            check(normal.count == 6 && normal[.toggleIsland] == nil && normal[.openChat] == nil && normal[.jumpToTerminal] == nil,
                  "six are on at first: not the island shortcut, the chat or the terminal")
            check(ShortcutLogic.activeSpecs(appStore: true, in: ud).count == 5, "five in the App Store build")
            ShortcutLogic.setEnabled(false, for: .muteToggle, in: ud)
            check(ShortcutLogic.activeSpecs(appStore: false, in: ud)[.muteToggle] == nil, "an off shortcut is not registered")
            ShortcutLogic.setEnabled(true, for: .toggleIsland, in: ud)
            check(ShortcutLogic.activeSpecs(appStore: false, in: ud)[.toggleIsland] == ShortcutLogic.defaults[.toggleIsland]!,
                  "turned on, it is")
            // Two ON actions with one combination are reported; an OFF one is not counted.
            ShortcutLogic.setEnabled(true, for: .openChat, in: ud)
            ShortcutLogic.save(ShortcutLogic.defaults[.goToAlert]!, for: .openChat, in: ud)
            check(ShortcutLogic.duplicates(in: ShortcutLogic.activeSpecs(appStore: false, in: ud)) == [.openChat, .goToAlert],
                  "a duplicate between two on shortcuts")
            ShortcutLogic.setEnabled(false, for: .openChat, in: ud)
            check(ShortcutLogic.duplicates(in: ShortcutLogic.activeSpecs(appStore: false, in: ud)).isEmpty,
                  "turn one off and there is none")
        }
        check(ShortcutLogic.isAppStoreBuild == false, "the test build is not the App Store build")
    }

    // MARK: Turn all on

    static func testTurnAllOn() {
        // Nothing is taken: everything comes on, and only the six that were off are tried.
        withDefaults { ud in
            var tried: [ShortcutAction] = []
            let left = ShortcutLogic.turnAllOn(appStore: false, in: ud) { tried.append($0); return true }
            check(left.isEmpty, "nothing was left off")
            check(tried == [.toggleIsland, .openChat, .jumpToTerminal, .shelf, .wardrobe, .projects], "only the shortcuts that were off are tried, in list order: \(tried)")
            check(Set(ShortcutLogic.activeSpecs(appStore: false, in: ud).keys) == Set(ShortcutAction.allCases), "all twelve are on")
            check(ShortcutLogic.duplicates(in: ShortcutLogic.activeSpecs(appStore: false, in: ud)).isEmpty, "with no two on one combination")
        }
        // One combination is taken (another app has ⌃⌥Space): that shortcut is reported and stays off, the rest come on.
        withDefaults { ud in
            let taken = ShortcutLogic.defaults[.openChat]!
            var asked: [ShortcutAction] = []
            let left = ShortcutLogic.turnAllOn(appStore: false, in: ud) { action in
                asked.append(action)
                return ShortcutLogic.hotKey(for: action, in: ud) != taken
            }
            check(left == [ShortcutLogic.TurnOnResult(action: .openChat, reason: .taken)], "the taken one is reported: \(left)")
            check(!ShortcutLogic.isEnabled(.openChat, in: ud), "and left off in the settings")
            check(ShortcutLogic.isEnabled(.toggleIsland, in: ud) && ShortcutLogic.isEnabled(.jumpToTerminal, in: ud), "the others that were off are on")
            check(ShortcutLogic.activeSpecs(appStore: false, in: ud)[.openChat] == nil, "it is not among the shortcuts to register")
            check(ShortcutLogic.hotKey(for: .openChat, in: ud) == taken, "it keeps its combination")
            // Turning all on again asks only about the one still off, and a free combination now comes on.
            asked.removeAll()
            let again = ShortcutLogic.turnAllOn(appStore: false, in: ud) { asked.append($0); return true }
            check(again.isEmpty && asked == [.openChat], "a second go retries only the one that was left off: \(asked)")
            check(ShortcutLogic.isEnabled(.openChat, in: ud), "and it comes on once the combination is free")
        }
        // Two NotchMeow shortcuts on one combination: the second is refused without asking the system.
        withDefaults { ud in
            ShortcutLogic.save(ShortcutLogic.defaults[.goToAlert]!, for: .jumpToTerminal, in: ud)   // goToAlert is on
            var asked: [ShortcutAction] = []
            let left = ShortcutLogic.turnAllOn(appStore: false, in: ud) { asked.append($0); return true }
            check(left == [ShortcutLogic.TurnOnResult(action: .jumpToTerminal, reason: .duplicate(of: .goToAlert))], "a duplicate is reported: \(left)")
            check(!asked.contains(.jumpToTerminal), "and never registered")
            check(!ShortcutLogic.isEnabled(.jumpToTerminal, in: ud), "and left off")
        }
        // Two that are off at first share a combination: the first in the list wins.
        withDefaults { ud in
            ShortcutLogic.save(ShortcutLogic.defaults[.openChat]!, for: .jumpToTerminal, in: ud)
            let left = ShortcutLogic.turnAllOn(appStore: false, in: ud) { _ in true }
            check(left == [ShortcutLogic.TurnOnResult(action: .jumpToTerminal, reason: .duplicate(of: .openChat))],
                  "the later of two off shortcuts on one combination is the one refused: \(left)")
            check(ShortcutLogic.isEnabled(.openChat, in: ud), "the earlier one comes on")
        }
        // The App Store build has no terminal or front-window shortcut: they are not touched, not even tried.
        withDefaults { ud in
            var asked: [ShortcutAction] = []
            let left = ShortcutLogic.turnAllOn(appStore: true, in: ud) { asked.append($0); return true }
            check(left.isEmpty && asked == [.toggleIsland, .openChat, .shelf, .wardrobe, .projects], "the App Store build tries only what it offers: \(asked)")
            check(ud.object(forKey: ShortcutAction.jumpToTerminal.udEnabled) == nil
                  && ud.object(forKey: ShortcutAction.attachFrontWindow.udEnabled) == nil, "and writes nothing for the two it lacks")
        }
        // A shortcut that was turned off on purpose is turned on too: that is what the button says.
        withDefaults { ud in
            ShortcutLogic.setEnabled(false, for: .muteToggle, in: ud)
            let left = ShortcutLogic.turnAllOn(appStore: false, in: ud) { _ in true }
            check(left.isEmpty && ShortcutLogic.isEnabled(.muteToggle, in: ud), "one switched off by hand comes back on")
        }
    }

    static func testTurnOnSummary() {
        typealias R = ShortcutLogic.TurnOnResult
        check(ShortcutLogic.turnOnSummary([]) == nil, "nothing left off, nothing to say")
        check(ShortcutLogic.turnOnSummary([R(action: .openChat, reason: .taken)]) == "Left off: Open chat (in use elsewhere)", "one taken")
        check(ShortcutLogic.turnOnSummary([R(action: .openChat, reason: .taken), R(action: .jumpToTerminal, reason: .duplicate(of: .goToAlert))])
              == "Left off: Open chat (in use elsewhere), Jump to terminal (same keys as Go to alert)", "a taken one and a duplicate")
    }

    // MARK: Lists

    static func testListSelection() {
        check(ShortcutLogic.navigate(selection: nil, delta: +1, itemCount: 3) == 0, "nothing selected, down: the first row")
        check(ShortcutLogic.navigate(selection: nil, delta: -1, itemCount: 3) == 2, "nothing selected, up: the last row")
        check(ShortcutLogic.navigate(selection: 0, delta: -1, itemCount: 3) == 0, "clamped at the top")
        check(ShortcutLogic.navigate(selection: 2, delta: +1, itemCount: 3) == 2, "clamped at the bottom")
        check(ShortcutLogic.navigate(selection: 1, delta: +1, itemCount: 3) == 2, "a step down")
        check(ShortcutLogic.navigate(selection: 1, delta: -1, itemCount: 3) == 0, "a step up")
        check(ShortcutLogic.navigate(selection: 1, delta: 0, itemCount: 3) == 1, "no move")
        check(ShortcutLogic.navigate(selection: nil, delta: +1, itemCount: 0) == nil, "an empty list")
        check(ShortcutLogic.navigate(selection: 4, delta: +1, itemCount: 0) == nil, "an empty list with a stale selection")
        check(ShortcutLogic.navigate(selection: 9, delta: -1, itemCount: 3) == 2, "a stale selection beyond the list is pulled in")
        check(ShortcutLogic.clampSelection(nil, itemCount: 3) == nil, "nothing stays nothing")
        check(ShortcutLogic.clampSelection(2, itemCount: 3) == 2, "inside the list")
        check(ShortcutLogic.clampSelection(5, itemCount: 3) == 2, "the list shrank")
        check(ShortcutLogic.clampSelection(1, itemCount: 0) == nil, "the list emptied")
        check(ShortcutLogic.clampSelection(-3, itemCount: 3) == 0, "negative")
    }

    // MARK: Pills

    static func testPills() {
        let ids = ["a", "b", "c"]
        func step(_ current: String?, _ delta: Int, waiting: Bool = false) -> String? {
            ShortcutLogic.pillID(from: ids, current: current, delta: delta, decisionWaiting: waiting)
        }
        func number(_ n: Int, waiting: Bool = false) -> String? {
            ShortcutLogic.pillID(number: n, in: ids, decisionWaiting: waiting)
        }
        check(step("a", +1) == "b", "next")
        check(step("c", +1) == "a", "next wraps to the first")
        check(step("a", -1) == "c", "previous wraps to the last")
        check(step("b", -1) == "a", "previous")
        check(step(nil, +1) == "b", "no focus counts as the first pill")
        check(step("gone", -1) == "c", "a focus that left counts as the first pill")
        check(ShortcutLogic.pillID(from: [], current: "a", delta: +1, decisionWaiting: false) == nil, "no pills")
        check(ShortcutLogic.pillID(from: ["a"], current: "a", delta: +1, decisionWaiting: false) == "a", "one pill stays")
        check(step("a", -7) == "c", "a big step still wraps")
        check(number(1) == "a" && number(3) == "c", "by number")
        check(number(4) == nil, "a number past the last pill")
        check(number(0) == nil, "zero")
        check(ShortcutLogic.pillID(number: 1, in: [], decisionWaiting: false) == nil, "no pills by number")
        // A permission request or a question is waiting: its card stays, with its agent.
        check(step("a", +1, waiting: true) == nil && step("a", -1, waiting: true) == nil, "next and previous do nothing while a decision waits")
        check(number(1, waiting: true) == nil && number(2, waiting: true) == nil, "⌘1 to ⌘9 do nothing while a decision waits")
        check(step("a", +1, waiting: false) == "b" && number(2, waiting: false) == "b", "and work again once it is answered")
    }

    // MARK: Island keys

    static let overview = IslandKeyContext(inOverview: true, inChat: false)
    static let chat = IslandKeyContext(inOverview: false, inChat: true)
    static let other = IslandKeyContext(inOverview: false, inChat: false)

    static func cmdKey(_ code: UInt16, _ ctx: IslandKeyContext) -> IslandCommand? {
        ShortcutLogic.islandCommand(keyCode: code, nsFlags: cmd, in: ctx)
    }

    static func testIslandKeys() {
        check(cmdKey(124, overview) == .nextPill, "⌘→")
        check(cmdKey(123, overview) == .prevPill, "⌘←")
        check(cmdKey(125, overview) == .listDown, "⌘↓")
        check(cmdKey(126, overview) == .listUp, "⌘↑")
        check(cmdKey(31, overview) == .openSelection, "⌘O")
        check(cmdKey(14, overview) == .toggleDiff, "⌘E on the overview")
        check(cmdKey(14, other) == nil, "⌘E elsewhere is left alone")
        check(cmdKey(43, other) == .openSettings, "⌘, without characters")
        check(ShortcutLogic.islandCommand(keyCode: 46, nsFlags: cmd, characters: ",", in: other) == .openSettings,
              "⌘, on a layout that puts the comma elsewhere (AZERTY: key code 46)")
        check(ShortcutLogic.islandCommand(keyCode: 43, nsFlags: cmd, characters: ";", in: other) == nil,
              "the US comma position is a semicolon on AZERTY: not Settings")
        check(ShortcutLogic.islandCommand(keyCode: 43, nsFlags: cmd, characters: ",", in: other) == .openSettings, "⌘, on the US layout")
        check(ShortcutLogic.islandCommand(keyCode: 43, nsFlags: cmd | shift, characters: ",", in: other) == nil, "⌘⇧, is not ⌘,")
        check(cmdKey(35, other) == .togglePin, "⌘P")
        check(cmdKey(36, overview) == nil, "⌘↩ outside the chat is left alone")
        check(cmdKey(40, overview) == nil, "⌘K outside the chat is left alone")
        let digits: [UInt16: Int] = [18: 1, 19: 2, 20: 3, 21: 4, 23: 5, 22: 6, 26: 7, 28: 8, 25: 9]
        for (code, n) in digits { check(cmdKey(code, other) == .pill(n), "⌘\(n)") }
        check(cmdKey(29, other) == nil, "⌘0 is left alone")
        check(ShortcutLogic.islandCommand(keyCode: 53, nsFlags: 0, in: other) == .escape, "⎋ with nothing held")
        check(ShortcutLogic.islandCommand(keyCode: 53, nsFlags: 1 << 16, in: other) == .escape, "⎋ with only caps lock on")
        check(ShortcutLogic.islandCommand(keyCode: 0, nsFlags: 0, in: other) == nil, "a plain letter is left alone")
        check(ShortcutLogic.islandCommand(keyCode: 49, nsFlags: 0, in: chat) == nil, "typing a space in the chat is left alone")
        check(cmdKey(8, overview) == nil && cmdKey(9, overview) == nil && cmdKey(0, overview) == nil, "⌘C ⌘V ⌘A are left alone")
    }

    /// In the chat, ⌘ with an arrow moves the cursor in the text field: line start, line end, top, bottom.
    static func testIslandKeysInTheChat() {
        for code: UInt16 in [123, 124, 125, 126] {
            check(cmdKey(code, chat) == nil, "⌘ and arrow \(code) must stay with the text field in the chat")
        }
        check(cmdKey(36, chat) == .sendMessage, "⌘↩ sends in the chat")
        check(cmdKey(40, chat) == .newConversation, "⌘K starts over in the chat")
        check(cmdKey(14, chat) == nil, "⌘E is not for the chat")
        check(cmdKey(43, chat) == .openSettings && cmdKey(35, chat) == .togglePin, "⌘, and ⌘P work in the chat")
        check(cmdKey(18, chat) == .pill(1), "⌘1 works in the chat")
        check(ShortcutLogic.islandCommand(keyCode: 53, nsFlags: 0, in: chat) == .escape, "⎋ in the chat")
    }

    /// ⌘⇧N, ⌘⌥1, ⌃⌘E … belong to other shortcuts or other apps: the island never takes them.
    static func testIslandKeysWithOtherModifiers() {
        let others: [UInt] = [cmd | shift, cmd | opt, cmd | ctrl, ctrl, opt, shift, ctrl | opt]
        for flags in others {
            for code: UInt16 in [124, 123, 125, 126, 31, 14, 36, 40, 43, 35, 18, 25] {
                check(ShortcutLogic.islandCommand(keyCode: code, nsFlags: flags, in: overview) == nil,
                      "key \(code) with flags \(flags) must be left alone")
                check(ShortcutLogic.islandCommand(keyCode: code, nsFlags: flags, in: chat) == nil,
                      "key \(code) with flags \(flags) must be left alone in the chat")
            }
            check(ShortcutLogic.islandCommand(keyCode: 53, nsFlags: flags, in: overview) == nil, "⎋ with a modifier is left alone")
        }
        check(ShortcutLogic.islandCommand(keyCode: 124, nsFlags: cmd | (1 << 16) | (1 << 23), in: overview) == .nextPill,
              "caps lock and the arrow-key bit do not hide ⌘→")
    }

    // MARK: Recorder

    static func testRecorderKeys() {
        func key(_ code: UInt16, _ flags: UInt) -> RecorderKey { ShortcutLogic.recorderKey(keyCode: code, nsFlags: flags) }
        check(key(53, 0) == .cancel, "⎋ alone cancels")
        check(key(53, 1 << 16) == .cancel, "⎋ with only caps lock on still cancels")
        check(key(53, cmd) == .refuse, "⌘⎋ is not a usable shortcut and does not cancel")
        check(key(0, 0) == .passThrough && key(36, 0) == .passThrough && key(48, 0) == .passThrough, "keys without a modifier go on")
        check(key(0, shift) == .refuse, "⇧A is refused: it would take capital A from every app")
        check(key(0, opt) == .refuse && key(0, shift | opt) == .refuse, "⌥A and ⇧⌥A are refused")
        check(key(0, cmd) == .refuse && key(0, ctrl) == .refuse, "⌘A and ⌃A are refused")
        check(key(0, ctrl | opt) == .record(ShortcutSpec(keyCode: 0, nsFlags: ctrl | opt)), "⌃⌥A is taken")
        check(key(45, cmd | shift) == .record(ShortcutSpec(keyCode: 45, nsFlags: cmd | shift)), "⌘⇧N is taken")
        check(key(49, ctrl | opt | (1 << 16) | (1 << 23)) == .record(ShortcutSpec(keyCode: 49, nsFlags: ctrl | opt)),
              "caps lock and the arrow-key bit are left out of what is stored")
        check(key(127, ctrl | opt) == .record(ShortcutSpec(keyCode: 127, nsFlags: ctrl | opt)), "the last key code")
        check(key(200, ctrl | opt) == .refuse, "a key code no keyboard has is refused, so a stored value is always one hotKey(for:) accepts")
        // Whatever the recorder takes, hotKey(for:) reads back unchanged.
        withDefaults { ud in
            for code: UInt16 in [0, 5, 45, 49, 123, 127] {
                for flags in [cmd | shift, ctrl | opt, cmd | ctrl, cmd | opt | shift] {
                    guard case .record(let spec) = key(code, flags) else { check(false, "key \(code) flags \(flags) should record"); return }
                    ShortcutLogic.save(spec, for: .openChat, in: ud)
                    check(ShortcutLogic.hotKey(for: .openChat, in: ud) == spec, "a recorded combination is read back as it was")
                }
            }
        }
    }

    // MARK: Tables

    static func testTables() {
        check(!ShortcutLogic.islandShortcuts.isEmpty, "the Settings table has rows")
        for row in ShortcutLogic.islandShortcuts {
            check(!row.key.isEmpty && !row.description.isEmpty, "a row with an empty cell")
        }
        check(ShortcutLogic.terminalBundleIds.first == "com.apple.Terminal", "Terminal first")
        check(ShortcutLogic.terminalBundleIds.count == 4, "four terminals, as the cards' button")
        check(Set(ShortcutLogic.terminalBundleIds).count == 4, "no repeats")
    }
}
