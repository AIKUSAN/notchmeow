import Foundation

// A listener or a browser that failed comes back by itself (sub-project G2b), slowly, and only while it is wanted. The rule is pure: it is fed with what happened and a clock in milliseconds and
// answers with a wait, or with nothing. The wait grows (1 s, 5 s, 30 s, then every minute for as long as the thing is wanted), so that a Mac whose network is down is tried a few times quickly and
// then costs one attempt a minute, and a thing that fails at once, over and over, never gets a fast loop. One that stayed up for a minute counts as healthy: its next failure starts the table
// again. Nothing is asked for while it is not wanted (Visible off, or nobody looking at Devices or the shelf: the service says so with `setWanted(false)`).
//
// The Rust twin is `link/restart.rs`: the same table (`scripts/link-tests/rust-wiring.test.mjs` reads this file's numbers). Run the tests through scripts/test-link-restart.sh.

struct LinkRestarter: Equatable {
    /// The first three waits.
    static let delaysMs = [1_000, 5_000, 30_000]
    /// Every wait after those.
    static let steadyMs = 60_000
    /// A thing that ran this long before it failed starts the table again.
    static let stableMs = 60_000

    private var wanted = false
    private var failures = 0
    private var upSince: Int?

    /// Whether anything needs it. Turning it off forgets the table and the age.
    mutating func setWanted(_ on: Bool) {
        wanted = on
        if !on { failures = 0; upSince = nil }
    }

    /// It is up (the first time or a restart).
    mutating func started(nowMs: Int) { upSince = nowMs }

    /// It failed. The wait before trying again, in milliseconds, or nil when nothing needs one.
    mutating func died(nowMs: Int) -> Int? {
        if let since = upSince, nowMs - since >= Self.stableMs { failures = 0 }
        upSince = nil
        return next()
    }

    /// A restart could not even start: the next wait.
    mutating func failedRestart() -> Int? {
        upSince = nil
        return next()
    }

    private mutating func next() -> Int? {
        guard wanted else { return nil }
        let wait = failures < Self.delaysMs.count ? Self.delaysMs[failures] : Self.steadyMs
        failures += 1
        return wait
    }
}

/// One pending restart: arming it cancels the one before, cancelling it ends the wait at once. One sleep for the whole wait, nothing polls.
@MainActor
final class LinkRestartWait {
    private var task: Task<Void, Never>?

    func arm(ms: Int, _ fire: @escaping @MainActor () -> Void) {
        task?.cancel()
        task = Task {
            try? await Task.sleep(for: .milliseconds(ms))
            if !Task.isCancelled { fire() }
        }
    }

    func cancel() {
        task?.cancel()
        task = nil
    }
}
