import Foundation

@main
enum CatFrameMeterTests {
    @MainActor static func main() {
        CT.section("draws that come together are one frame")
        var m = CatFrameMeter()
        CT.check("nothing to report before a frame closes", m.summary() == nil, true)
        // Frame 1: thirteen draws, 0.1 ms each, starting within 2 ms of each other. Frame 2 starts 16 ms later.
        for f in 0..<3 {
            let t0 = Double(f) * 0.016
            for i in 0..<13 { m.record(start: t0 + Double(i) * 0.00015, duration: 0.0001) }
        }
        CT.check("two frames have closed (the third is still open)", m.frames.count, 2)
        CT.check("each frame holds thirteen cats", m.frames.map(\.cats), [13, 13])
        CT.checkNear("and adds their times: 13 x 0.1 ms", m.frames[0].ms, 1.3)
        let s = m.summary()!
        CT.checkNear("average", s.avgMs, 1.3); CT.checkNear("worst", s.maxMs, 1.3); CT.check("most cats in a frame", s.cats, 13)

        CT.section("the budget")
        CT.checkTrue("1.3 ms is within the 2 ms budget", m.readout()!.overBudget == false)
        var slow = CatFrameMeter()
        for f in 0..<5 { slow.record(start: Double(f) * 0.016, duration: 0.0031) }
        CT.checkTrue("3.1 ms a frame is over it, and the line says so", slow.readout()!.overBudget && slow.readout()!.line.contains("OVER"))
        CT.check("the budget is 2 ms", catFrameBudgetMs, 2.0)

        CT.section("old frames fall off")
        var long = CatFrameMeter()
        long.keep = 10
        for f in 0..<50 { long.record(start: Double(f) * 0.016, duration: 0.001) }
        CT.check("only the last ten frames are kept", long.frames.count, 10)
        CT.finish()
    }
}
