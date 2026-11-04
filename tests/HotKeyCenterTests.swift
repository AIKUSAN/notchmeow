import AppKit
import Carbon.HIToolbox

/// A settings store in memory: the test never writes a preferences file.
final class MemoryStore: ShortcutStore {
    var values: [String: Any] = [:]
    func object(forKey key: String) -> Any? { values[key] }
    func set(_ value: Any?, forKey key: String) { values[key] = value }
}

/// The Carbon plumbing of `HotKeyCenter`, without launching the app and without a real key press: the shortcuts
/// are registered with the system under combinations nobody uses (⌃⌥⇧⌘ with F13 to F20), and a press is
/// simulated by sending Carbon the same event the system would send.
@main
enum HotKeyCenterTests {
    nonisolated(unsafe) static var cases = 0

    static func check(_ ok: Bool, _ message: @autoclosure () -> String,
                      file: StaticString = #file, line: UInt = #line) {
        cases += 1
        precondition(ok, message(), file: file, line: line)
    }

    static let allFour = ShortcutSpec.cmdBit | ShortcutSpec.shiftBit | ShortcutSpec.optBit | ShortcutSpec.ctrlBit
    /// F13 to F19, the ISO section key, F11, F12 and F2: keys nobody binds with all four modifiers held.
    static let fKeys: [UInt16] = [105, 107, 113, 106, 64, 79, 80, 10, 103, 111, 120]

    /// Sends Carbon a "hot key pressed" event for `action`, as the system does when its combination is typed.
    @MainActor static func press(_ action: ShortcutAction) {
        var event: EventRef?
        let created = CreateEvent(nil, OSType(kEventClassKeyboard), UInt32(kEventHotKeyPressed), 0,
                                  EventAttributes(kEventAttributeNone), &event)
        precondition(created == noErr && event != nil, "CreateEvent failed (\(created))")
        var id = EventHotKeyID(signature: OSType(0x4E4D4557),
                               id: UInt32(ShortcutAction.allCases.firstIndex(of: action)!))
        let set = SetEventParameter(event, EventParamName(kEventParamDirectObject),
                                    EventParamType(typeEventHotKeyID), MemoryLayout<EventHotKeyID>.size, &id)
        precondition(set == noErr, "SetEventParameter failed (\(set))")
        SendEventToEventTarget(event, GetApplicationEventTarget())
        ReleaseEvent(event)
    }

    @MainActor static func main() {
        let ud = MemoryStore()
        let center = HotKeyCenter.shared
        center.store = ud
        let actions = ShortcutLogic.available(appStore: false).filter { $0 != .toggleIsland }
        check(actions.count == 11, "eleven actions besides the island shortcut")
        for (action, key) in zip(actions, fKeys) {
            ShortcutLogic.save(ShortcutSpec(keyCode: key, nsFlags: allFour), for: action, in: ud)
        }
        ShortcutLogic.save(ShortcutSpec(keyCode: 90, nsFlags: allFour), for: .toggleIsland, in: ud)  // F20

        // Start: what is on at first is registered (six of the eleven besides the island's), and a press runs the right action, once.
        let onAtFirst = actions.filter { $0.enabledByDefault }
        check(onAtFirst.count == 6, "six are on at first")
        var pressed: [ShortcutAction] = []
        center.start { pressed.append($0) }
        check(center.registered == Set(onAtFirst), "only the six that are on at first are registered")
        check(center.conflicts.isEmpty, "no conflicts: \(center.conflicts)")
        for action in onAtFirst { press(action) }
        check(pressed == onAtFirst, "each press runs its own action, in order: \(pressed)")
        press(.openChat)
        check(pressed.count == onAtFirst.count, "a shortcut that is off is not delivered")

        // "Turn all on" with the real thing behind it: the other four are registered (the desktop cat's is on already), and delivered.
        let left = ShortcutLogic.turnAllOn(appStore: false, in: ud) { action in
            center.reregister(action)
            return !center.conflicts.contains(action)
        }
        check(left.isEmpty, "nothing is left off when every combination is free: \(left)")
        check(center.registered == Set(ShortcutAction.allCases), "all twelve are registered")
        pressed.removeAll()
        for action in ShortcutAction.allCases { press(action) }
        check(pressed == ShortcutAction.allCases, "and each is delivered: \(pressed)")

        // Turning one off and back.
        ShortcutLogic.setEnabled(false, for: .muteToggle, in: ud)
        center.reregister(.muteToggle)
        check(!center.registered.contains(.muteToggle), "turned off, it is not registered")
        check(center.registered.count == 11, "the others stay")

        // A new key for one action: the old combination is released, the new one taken.
        ShortcutLogic.save(ShortcutSpec(keyCode: 96, nsFlags: allFour), for: .openChat, in: ud)  // F5 with ⌃⌥⇧⌘
        center.reregister(.openChat)
        check(center.registered.contains(.openChat) && center.conflicts.isEmpty, "re-registered under its new key")

        // Two shortcuts of ours on one combination: the second one is refused and reported.
        ShortcutLogic.setEnabled(true, for: .muteToggle, in: ud)
        let first = ShortcutAction.goToAlert   // before .muteToggle in the list: it keeps the combination
        ShortcutLogic.save(ShortcutLogic.hotKey(for: first, in: ud), for: .muteToggle, in: ud)
        center.registerAll()
        check(center.conflicts == [.muteToggle], "the later one is reported: \(center.conflicts)")
        check(center.registered.count == 11 && !center.registered.contains(.muteToggle),
              "all but the refused one are registered: \(center.registered.count)")
        pressed.removeAll()
        press(first)
        check(pressed == [first], "the first one still works")
        // A conflict clears when the shortcut is turned off.
        ShortcutLogic.setEnabled(false, for: .muteToggle, in: ud)
        center.reregister(.muteToggle)
        check(center.conflicts.isEmpty, "turned off, its conflict is gone")

        // Quit: everything is released, and a second start does not install a second handler.
        center.unregisterAll()
        check(center.registered.isEmpty, "nothing registered after unregisterAll")
        pressed.removeAll()
        press(actions[1])
        check(pressed.isEmpty, "a press after unregisterAll is ignored")
        center.start { pressed.append($0) }
        press(actions[1])
        check(pressed == [actions[1]], "one start, one delivery (\(pressed))")
        center.unregisterAll()

        print("HotKeyCenter: \(cases) cases passed")
    }
}
