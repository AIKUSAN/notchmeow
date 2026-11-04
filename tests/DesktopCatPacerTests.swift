import Foundation

@main
enum DesktopCatPacerTests {
    typealias P = DesktopCatPacer

    /// What a timer is told, as numbers: `arm` compares exactly, and a tenth of 0.05 is not exactly 0.005.
    static func armed(_ a: P.Action) -> [Double]? { if case .arm(let i, let l) = a { return [i, l] }; return nil }
    static func same(_ a: [Double]?, _ b: [Double]) -> Bool { a.map { zip($0, b).allSatisfy { abs($0 - $1) < 1e-12 } && $0.count == b.count } ?? false }

    @MainActor static func main() {
        CT.section("the intervals: one timer at the target's rate, none for a target of nothing")
        CT.check("60, 20, 5 and 0.5 frames a second", [60, 20, 5, 0.5].map { P.interval($0)! }, [1.0 / 60, 0.05, 0.2, 2])
        CT.check("0, a negative rate, NaN and infinity mean no timer", [P.interval(0) == nil, P.interval(-5) == nil, P.interval(.nan) == nil, P.interval(.infinity) == nil], [true, true, true, true])
        CT.checkNear("the slack is a tenth of the interval", P.leeway(0.2), 0.02)
        CT.checkNear("and at most 0.2 s", P.leeway(2), 0.2)

        CT.section("the pacer re-arms the timer only when the target changes")
        var p = P()
        CT.check("a new pacer has no timer", p.fps, 0)
        CT.check("a target of 0 on a pacer with no timer does nothing", p.target(0), .none)
        CT.checkTrue("20 fps arms a 50 ms timer", same(armed(p.target(20)), [0.05, 0.005]))
        CT.check("20 again does nothing", p.target(20), .none)
        CT.checkTrue("5 fps arms 200 ms", same(armed(p.target(5)), [0.2, 0.02]))
        CT.checkTrue("60 fps while it flies", same(armed(p.target(60)), [1.0 / 60, 1.0 / 600]))
        CT.checkTrue("asleep: one frame every two seconds", same(armed(p.target(0.5)), [2, 0.2]))
        CT.check("hidden: the timer is cancelled", p.target(0), .stop)
        CT.check("and stays cancelled", p.target(0), .none)
        CT.check("a target that is NaN is nothing", { var q = P(); _ = q.target(5); return q.target(.nan) }(), P.Action.stop)
        CT.checkTrue("it is back at 5 when the cat can be seen again", same(armed(p.target(5)), [0.2, 0.02]))

        CT.section("what a rate costs: milliseconds a frame times frames a second")
        CT.checkNear("0.4 ms at 5 fps is 0.2 % of a core", P.coreShare(msPerFrame: 0.4, fps: 5), 0.002)
        CT.checkNear("2 ms at 60 fps is 12 %", P.coreShare(msPerFrame: 2, fps: 60), 0.12)

        CT.section("hidden: any one reason hides the cat")
        var v = DesktopCatVisibility()
        CT.check("visible to begin with", v.hidden, false)
        v.screensAsleep = true; CT.check("the displays are asleep", v.hidden, true)
        v = DesktopCatVisibility(); v.locked = true; CT.check("the session is locked", v.hidden, true)
        v = DesktopCatVisibility(); v.covered = true; CT.check("a fullscreen app covers it", v.hidden, true)
        CT.check("and the rule feeds the frame rate: hidden beats a flight", DesktopCatTrip.fps(.init(phase: .flyingOut, hidden: DesktopCatVisibility(covered: true).hidden)), 0)
        CT.finish()
    }
}
