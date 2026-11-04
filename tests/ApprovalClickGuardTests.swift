import Foundation

@main
enum ApprovalClickGuardTests {
    static func main() {
        var passed = 0
        func ok(_ cond: Bool, _ name: String) { precondition(cond, name); passed += 1; print("✓ \(name)") }
        ok(ApprovalClickGuard.window == 0.6, "the guard is 600 ms")
        ok(ApprovalClickGuard.duration == .milliseconds(600), "the sleep is 600 ms")
        ok(ApprovalClickGuard.window > 0.2 && ApprovalClickGuard.window < 1, "long enough to catch a stray click, short enough not to be felt")
        print("Approval click guard: \(passed) checks passed")
    }
}
