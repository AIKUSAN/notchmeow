import Foundation
import Network

/// Tells the router when the Mac is offline, so Auto goes straight to a local model instead
/// of waiting for the cloud to time out. Event-driven: no polling, no CPU while idle.
final class NetworkMonitor: @unchecked Sendable {
    static let shared = NetworkMonitor()

    private let monitor = NWPathMonitor()
    private let lock = NSLock()
    private var online = true
    private var started = false

    var isOnline: Bool { lock.withLock { online } }

    /// `onChange` runs on a background queue with the new state.
    func start(onChange: @escaping @Sendable (Bool) -> Void = { _ in }) {
        let first = lock.withLock { () -> Bool in
            defer { started = true }
            return !started
        }
        guard first else { return }
        monitor.pathUpdateHandler = { [weak self] path in
            let up = path.status == .satisfied
            self?.lock.withLock { self?.online = up }
            onChange(up)
        }
        monitor.start(queue: DispatchQueue(label: "io.github.aikusan.notchmeow.network"))
    }
}
