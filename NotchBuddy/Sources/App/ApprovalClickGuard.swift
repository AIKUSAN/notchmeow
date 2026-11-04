import Foundation

// A fresh permission card ignores clicks for its first 600 ms. The card opens under a pointer that was busy with the window underneath, and a click meant for that window must not land on
// Allow, Always or Deny. Foundation only. The keyboard is not a click and is not guarded. `ApprovalView` waits `window` once per request (one `Task.sleep`: no timer) before its buttons take clicks.

enum ApprovalClickGuard {
    /// How long a new request's buttons ignore clicks (s).
    static let window: TimeInterval = 0.6

    /// The same, as a duration for `Task.sleep`.
    static var duration: Duration { .milliseconds(Int((window * 1000).rounded())) }
}
