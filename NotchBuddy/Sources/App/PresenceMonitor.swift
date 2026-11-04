import AppKit
import CoreGraphics

// Whether the user is at the computer: the Mac's own notifications for a lock, a sleep and a display that goes dark, observed ONCE and shared. The desktop cat (it hides while the screen is locked or the
// displays sleep) and the sidekick (away and back) both read the events, so there is one set of observers and neither has its own. Nothing here polls: every event is a notification the system
// sends. The idle time is not a notification: `idleSeconds()` is one cheap read that the sidekick asks for on a tick the island already has (`SidekickIdle`). Pure flags (`SKPresenceFlags`)
// decide what counts as a change, so a lock that arrives as two notifications is one lock.

@MainActor
final class PresenceMonitor {
    static let shared = PresenceMonitor()

    typealias Event = SKPresenceFlags.Event

    private var flags = SKPresenceFlags()
    private var listeners: [(id: String, handler: @MainActor (Event) -> Void)] = []
    private var tokens: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var started = false

    /// The screen is locked, or the session was switched away.
    var locked: Bool { flags.locked }
    /// The displays are asleep.
    var displayOff: Bool { flags.displayOff }
    /// The Mac is asleep.
    var asleep: Bool { flags.asleep }

    /// Tells `handler` about every change from now on. One listener per `id`: subscribing again replaces it.
    func subscribe(_ id: String, _ handler: @escaping @MainActor (Event) -> Void) {
        listeners.removeAll { $0.id == id }
        listeners.append((id, handler))
    }

    /// Starts watching. Called once, at launch; calling it again does nothing.
    func start() {
        guard !started else { return }
        started = true
        let ws = NSWorkspace.shared.notificationCenter, dc = DistributedNotificationCenter.default()
        observe(ws, NSWorkspace.screensDidSleepNotification) { $0.set(.display, true) }
        observe(ws, NSWorkspace.screensDidWakeNotification) { $0.set(.display, false) }
        observe(ws, NSWorkspace.willSleepNotification) { $0.set(.system, true) }
        observe(ws, NSWorkspace.didWakeNotification) { $0.set(.system, false) }
        observe(ws, NSWorkspace.sessionDidResignActiveNotification) { $0.set(.session, true) }
        observe(ws, NSWorkspace.sessionDidBecomeActiveNotification) { $0.set(.session, false) }
        observe(dc, Notification.Name("com.apple.screenIsLocked")) { $0.set(.screenLock, true) }
        observe(dc, Notification.Name("com.apple.screenIsUnlocked")) { $0.set(.screenLock, false) }
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ change: @escaping @MainActor (PresenceMonitor) -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if let self { change(self) } }
        }
        tokens.append((center, token))
    }

    private func set(_ source: SKPresenceFlags.Source, _ on: Bool) {
        guard let event = flags.set(source, on) else { return }
        for l in listeners { l.handler(event) }
    }

    /// How many seconds since the last keyboard or mouse input of this session. It needs no permission and is one cheap system call; it is asked on an existing tick, never on a timer of its own.
    static func idleSeconds() -> Double {
        CGEventSource.secondsSinceLastEventType(.combinedSessionState, eventType: CGEventType(rawValue: ~0)!)
    }
}
