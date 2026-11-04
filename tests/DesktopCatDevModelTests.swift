import Foundation

@main
enum DesktopCatDevModelTests {
    final class Clock { var t = 10_000.0 }

    @MainActor static func main() {
        let clock = Clock()
        let rng = CatRNG(seed: 3)
        let m = DesktopCatDevModel(now: { clock.t }, rand: { rng.next() })
        func run(ms: Double) { var left = ms; while left > 0 { clock.t += 16; left -= 16; m.advance() } }

        CT.section("the Debug-only Desktop section: a mock desktop driven by the real rules")
        CT.checkTrue("its marker is longer than 15 bytes (a shorter string hides in the code, where the binary check cannot see it)", DesktopCatDevModel.marker.utf8.count > 15)
        CT.check("it starts on the desktop, at the desktop spot, at Medium with three kittens", [m.phase.rawValue, "\(m.position == DesktopCatDevModel.desk)", m.size.rawValue, "\(m.kittens)"], ["onDesktop", "true", "medium", "3"])
        CT.check("the rule picks 5 fps for a cat that sits there", m.fps(), 5)
        m.pick(size: .large); m.pick(kittens: 99)
        CT.check("a size and a number of kittens (held to 8)", [m.size.rawValue, "\(m.kittens)"], ["large", "8"])
        m.pick(kittens: -4)
        CT.check("and not below 0", m.kittens, 0)

        CT.section("an alert: the surprised beat, the flight into the notch, then the cat sits in the notch and nothing is drawn")
        m.fireAlert()
        CT.check("retracting, in the air: 60 fps", [m.phase.rawValue, "\(m.fps())"], ["retracting", "60.0"])
        run(ms: 200)
        CT.check("during the surprised beat (450 ms) the cat has not moved yet", m.position == DesktopCatDevModel.desk, true)
        run(ms: 450 + 600)
        CT.check("it has docked in the notch: the cat is not drawn, no frames", [m.phase.rawValue, "\(m.fps())", "\(m.flight == nil)"], ["atNotchForAlert", "0.0", "true"])
        CT.check("and the button state follows", m.alertIsOn, true)

        CT.section("the alert clears: the cat flies back out; cleared mid-flight it turns round without a jump")
        m.clearAlert()
        CT.check("returning", m.phase.rawValue, "returning")
        run(ms: 300)
        let before = m.position
        m.fireAlert()
        let after = m.flight!.position(at: clock.t)
        CT.checkTrue("an alert that lands mid-flight turns it round at the same place (jump \(hypot(before.x - after.x, before.y - after.y)))", hypot(before.x - after.x, before.y - after.y) < 25)
        CT.check("it is retracting again", m.phase.rawValue, "retracting")
        m.clearAlert()
        run(ms: 1500)
        CT.check("and lands back on its spot", [m.phase.rawValue, "\(m.position == DesktopCatDevModel.desk)"], ["onDesktop", "true"])
        CT.check("5 fps again", m.fps(), 5)

        CT.section("home: the toggle sends it into the notch and nothing runs")
        m.toggle()
        run(ms: 1200)
        CT.check("home, not drawn, 0 fps", [m.phase.rawValue, "\(m.fps())"], ["home", "0.0"])
        CT.checkTrue("the readout names the phase and the rate", m.readout.hasPrefix("home") && m.readout.contains("0.0 fps"))
        CT.finish()
    }
}
