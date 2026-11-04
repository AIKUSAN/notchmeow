import Foundation

// The restart table of a listener or a browser that failed (LinkRestarter, sub-project G2b) and its one-shot wait. The same cases as link/restart.rs. Run it through scripts/test-link-restart.sh.

@main
enum LinkRestartTests {
    static func wanted() -> LinkRestarter {
        var r = LinkRestarter()
        r.setWanted(true)
        return r
    }

    @MainActor static func main() async {
        CT.section("nothing is scheduled for a thing nobody wants")
        var r = LinkRestarter()
        CT.check("never wanted", [r.died(nowMs: 0), r.failedRestart()], [nil, nil])
        r = wanted()
        r.setWanted(false)
        CT.check("no longer wanted", [r.died(nowMs: 10), r.failedRestart()], [nil, nil])

        CT.section("the waits are 1 s, 5 s, 30 s, then every minute")
        r = wanted()
        r.started(nowMs: 0)
        var waits = [r.died(nowMs: 100)]
        for _ in 0..<6 { waits.append(r.failedRestart()) }
        CT.check("the table", waits, [1_000, 5_000, 30_000, 60_000, 60_000, 60_000, 60_000])

        CT.section("a thing that fails at once again and again never gets a fast loop")
        r = wanted()
        var t = 0
        var seen: [Int?] = []
        for _ in 0..<6 {
            r.started(nowMs: t)
            let w = r.died(nowMs: t + 10)
            seen.append(w)
            t += 10 + (w ?? 0)
        }
        CT.check("the table again", seen, [1_000, 5_000, 30_000, 60_000, 60_000, 60_000])

        CT.section("a minute of life starts the table again")
        r = wanted()
        r.started(nowMs: 0)
        CT.check("first failure, then a failed restart", [r.died(nowMs: 10), r.failedRestart()], [1_000, 5_000])
        r.started(nowMs: 200_000)
        CT.check("59.999 s is not a minute", r.died(nowMs: 259_999), 30_000)
        r.started(nowMs: 300_000)
        CT.check("a minute is", r.died(nowMs: 360_000), 1_000)
        r.started(nowMs: 400_000)
        CT.check("and so is a long life", r.died(nowMs: 1_400_000), 1_000)

        CT.section("turning the wish off forgets the table")
        r = wanted()
        r.started(nowMs: 0); _ = r.died(nowMs: 10); _ = r.failedRestart()
        r.setWanted(false); r.setWanted(true)
        CT.check("back to one second", r.died(nowMs: 20), 1_000)

        CT.section("no wait is shorter than a second or longer than a minute")
        r = wanted()
        var ok = true
        for _ in 0..<200 { if let w = r.failedRestart(), !(1_000...60_000).contains(w) { ok = false } }
        CT.checkTrue("200 waits in a row", ok)

        CT.section("the one-shot wait")
        let wait = LinkRestartWait()
        var fired = 0
        wait.arm(ms: 30) { fired += 1 }
        try? await Task.sleep(for: .milliseconds(300))
        CT.check("it fires once", fired, 1)
        wait.arm(ms: 60_000) { fired += 1 }
        wait.cancel()
        wait.arm(ms: 30) { fired += 10 }
        wait.arm(ms: 30) { fired += 100 }
        try? await Task.sleep(for: .milliseconds(300))
        CT.check("a cancelled wait does not fire, and arming again replaces the one before", fired, 101)
        CT.finish()
    }
}
