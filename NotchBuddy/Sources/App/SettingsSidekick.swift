import Foundation

// The words and the example lines of the Sidekick tab in Settings (the restyle spec's Sidekick section). The four stuck kinds are the ones `SidekickStuck` ranks; the switch reads on while at
// least one of them still shows. Only the recap, stuck.waiting and stuck.silent examples read the made-up session (a fixed clock, never the user's ledger, never a path); the loop and
// errors lines come from `SidekickStuck`'s fixed wording. Pure Foundation on the Sidekick rules; tests: tests/SettingsRulesTests.swift (scripts/test-settings-rules.sh).

enum SettingsSidekick {
    static let stuckKinds = SidekickStuck.kinds
    static let stuckNames: [(kind: String, label: String)] = [
        (kind: "stuck.loop", label: "Repeated steps"),
        (kind: "stuck.errors", label: "Repeated errors"),
        (kind: "stuck.waiting", label: "Waiting for your OK"),
        (kind: "stuck.silent", label: "Gone quiet"),
    ]
    static let permissionLine = "Always on: it tells you what a permission would do."
    static let nothingLeaves = "Nothing leaves this Mac unless you pick a cloud AI as your main AI."
    static let comesWithF3a = "Coming soon"

    /// The stuck switch: off when all four are muted, on when none is, and on with "N of 4" still showing when some are muted.
    static func stuckSwitch(isMuted: (String) -> Bool) -> (on: Bool, detail: String?) {
        let muted = stuckKinds.filter(isMuted).count
        if muted == stuckKinds.count { return (false, nil) }
        if muted == 0 { return (true, nil) }
        return (true, "\(stuckKinds.count - muted) of \(stuckKinds.count)")
    }

    /// One example line for a kind (`recap` or a stuck kind), built by the real rules from a made-up Claude Code session on a fixed clock; nil for any other kind.
    static func example(_ kind: String) -> String? {
        let now = 10_000_000.0
        var s = SKSession(key: "integration_claude|example", agentId: "integration_claude", sessionId: "example", startedAt: now - 20 * SK.minute, lastEventAt: now - 5 * SK.minute)
        s.project = "my-app"
        s.state = "approval"
        s.pendingApprovalAt = now - 30_000
        let files = ["app.swift", "lib.swift", "main.swift"]
        s.ring = files.enumerated().map { i, f in
            SKRing(at: now - Double(files.count - i) * SK.minute, kind: "tool", tool: "Edit", target: f, file: f, key: "Edit#\(i)", ok: true)
        }
        if kind == "recap" {
            return SidekickRecap.recap(awaySince: now - 10 * SK.minute, now: now, sessions: [s])?.lines.first
        }
        guard stuckKinds.contains(kind) else { return nil }
        let nudge = SKNudge(kind: kind, reasonId: "example", key: s.key, agentId: "integration_claude")
        return SidekickStuck.text(nudge, SKLedger(sessions: [s]), now: now)
    }
}
