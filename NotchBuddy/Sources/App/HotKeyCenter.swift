import AppKit
import Carbon.HIToolbox

// MARK: - C-level event handler
//
// Carbon's InstallEventHandler wants a top-level C-compatible function, so the state it reads lives in
// globals. They are only touched on the main thread: Carbon delivers hot-key events there, and
// `HotKeyCenter` is main-actor isolated.

private nonisolated(unsafe) var gHotKeyHandler: EventHandlerRef? = nil
private nonisolated(unsafe) var gHotKeyTable: [UInt32: ShortcutAction] = [:]
private nonisolated(unsafe) var gOnAction: (@MainActor (ShortcutAction) -> Void)? = nil

private func notchMeowHotKeyEventHandler(
    _: EventHandlerCallRef?,
    _ event: EventRef?,
    _: UnsafeMutableRawPointer?
) -> OSStatus {
    guard let event else { return OSStatus(eventNotHandledErr) }
    var hkid = EventHotKeyID()
    let err = GetEventParameter(
        event,
        EventParamName(kEventParamDirectObject),
        EventParamType(typeEventHotKeyID),
        nil,
        MemoryLayout<EventHotKeyID>.size,
        nil,
        &hkid
    )
    guard err == noErr, let action = gHotKeyTable[hkid.id] else {
        return OSStatus(eventNotHandledErr)
    }
    MainActor.assumeIsolated { gOnAction?(action) }
    return noErr
}

// MARK: - HotKeyCenter

/// Registers NotchMeow's global shortcuts with Carbon `RegisterEventHotKey`.
///
/// - No Accessibility or Input Monitoring permission, and it works in the App Store sandbox.
/// - A registered key press is consumed: it never reaches the app in front. That is why
///   `ShortcutSpec.isUsableGlobal` keeps plain typing keys out.
/// - Which shortcuts are on, and their keys, come from `ShortcutLogic` (UserDefaults).
@MainActor
final class HotKeyCenter {
    static let shared = HotKeyCenter()
    private init() {}

    /// "NMEW": the signature of NotchMeow's hot-key IDs.
    private let kSignature = OSType(0x4E4D4557)

    private var refs: [ShortcutAction: EventHotKeyRef] = [:]
    private var combinations: [ShortcutAction: ShortcutSpec] = [:]

    /// Where the shortcuts are read from: the app's settings. Tests point it at a dictionary.
    var store: any ShortcutStore = UserDefaults.standard

    /// The shortcuts that are registered right now.
    var registered: Set<ShortcutAction> { Set(refs.keys) }

    /// Shortcuts that were not registered: macOS refused them (another app or the system owns the combination), or
    /// another NotchMeow shortcut already has it (Carbon would take both and run only one).
    private(set) var conflicts: Set<ShortcutAction> = []

    // MARK: Lifecycle

    /// Installs the handler (once) and registers every shortcut that is on. `onAction` runs on the main
    /// actor each time one is pressed.
    func start(onAction: @escaping @MainActor (ShortcutAction) -> Void) {
        gOnAction = onAction
        if gHotKeyHandler == nil {
            var spec = EventTypeSpec(
                eventClass: OSType(kEventClassKeyboard),
                eventKind: UInt32(kEventHotKeyPressed)
            )
            let status = InstallEventHandler(
                GetApplicationEventTarget(),
                notchMeowHotKeyEventHandler,
                1, &spec,
                nil, &gHotKeyHandler
            )
            guard status == noErr else { gHotKeyHandler = nil; return }
        }
        registerAll()
    }

    /// Unregisters every hot key (app quit).
    func unregisterAll() {
        for (action, ref) in refs {
            UnregisterEventHotKey(ref)
            gHotKeyTable.removeValue(forKey: Self.carbonID(action))
        }
        refs.removeAll()
        combinations.removeAll()
    }

    /// Registers again from the stored settings: what is on, with its keys.
    func registerAll() {
        unregisterAll()
        conflicts.removeAll()
        let active = ShortcutLogic.activeSpecs(in: store)
        for action in ShortcutAction.allCases {   // in order: of two on one combination, the first wins
            if let spec = active[action] { register(action, spec) }
        }
    }

    /// Registers one action again after its key or its switch changed.
    func reregister(_ action: ShortcutAction) {
        if let ref = refs.removeValue(forKey: action) {
            UnregisterEventHotKey(ref)
            gHotKeyTable.removeValue(forKey: Self.carbonID(action))
        }
        combinations.removeValue(forKey: action)
        conflicts.remove(action)
        if let spec = ShortcutLogic.activeSpecs(in: store)[action] { register(action, spec) }
    }

    // MARK: Private

    private static func carbonID(_ action: ShortcutAction) -> UInt32 {
        UInt32(ShortcutAction.allCases.firstIndex(of: action)!)
    }

    private func register(_ action: ShortcutAction, _ spec: ShortcutSpec) {
        guard !combinations.contains(where: { $0.value == spec }) else {
            conflicts.insert(action)
            return
        }
        let id = Self.carbonID(action)
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(
            UInt32(spec.keyCode),
            ShortcutLogic.carbonModifiers(fromNS: spec.nsFlags),
            EventHotKeyID(signature: kSignature, id: id),
            GetApplicationEventTarget(),
            0,
            &ref
        )
        if status == noErr, let ref {
            refs[action] = ref
            combinations[action] = spec
            gHotKeyTable[id] = action
        } else {
            conflicts.insert(action)
        }
    }
}
