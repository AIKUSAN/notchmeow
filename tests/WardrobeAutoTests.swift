import Foundation

@main
enum WardrobeAutoTests {
    static func rows(_ x: Any?) -> [[String: Any]] { x as! [[String: Any]] }
    static func int(_ x: Any?) -> Int { (x as! NSNumber).intValue }
    /// An integer the way the contract's `Number.isInteger` means it: a whole number, and not text, a boolean, a fraction or null. The fixture holds a few such inputs (2024.5, "2024", null); the app's functions take `Int`, so those rows are checked as "cannot be asked", which the contract answers with null (Easter) and none (Auto).
    static func whole(_ x: Any?) -> Int? {
        guard let n = x as? NSNumber, CFGetTypeID(n) != CFBooleanGetTypeID(), n.doubleValue == n.doubleValue.rounded(), abs(n.doubleValue) < 1e9 else { return nil }
        return n.intValue
    }
    /// Values of different types as one line, to compare.
    static func s(_ x: Any...) -> String { x.map { "\($0)" }.joined(separator: " ") }

    /// A clock for `WardrobeClock` that a test moves by hand: the date, the seconds to midnight, and a list of the timers that were asked for.
    @MainActor final class Fake {
        var day = Wardrobe.Day(y: 2026, m: 12, d: 24)
        var toMidnight = 5400.0
        var timers: [(after: Double, fire: @MainActor @Sendable () -> Void, cancelled: Bool, fired: Bool)] = []
        var waiting: Int { timers.filter { !$0.cancelled && !$0.fired }.count }
        lazy var clock = WardrobeClock(today: { [unowned self] in self.day }, secondsToMidnight: { [unowned self] in self.toMidnight },
                                       schedule: { [unowned self] after, fire in
                                           let i = self.timers.count
                                           self.timers.append((after, fire, false, false))
                                           return { MainActor.assumeIsolated { self.timers[i].cancelled = true } }
                                       })
        /// Fires the newest timer that has not been cancelled, as the system would at its time.
        func fireLast() { let i = timers.lastIndex { !$0.cancelled && !$0.fired }!; timers[i].fired = true; timers[i].fire() }
    }

    @MainActor static func main() {
        let fx = CT.fixture("wardrobe-cases.json")

        CT.section("easterOf: \(rows(fx["easter"]).count) years")
        var diffs: [String] = []
        for c in rows(fx["easter"]) {
            let got = whole(c["year"]).flatMap { Wardrobe.easterOf($0) }, want = c["out"] as? [String: Any]
            if got?.month != want.map({ int($0["month"]) }) || got?.day != want.map({ int($0["day"]) }) { diffs.append("\(String(describing: c["year"])): \(String(describing: got))") }
        }
        CT.checkRows("Easter Sunday of every year is as the fixture says (the earliest, the latest, a leap year, a year in March)", diffs)
        CT.check("1582 and 10000 have none", [Wardrobe.easterOf(1582) == nil, Wardrobe.easterOf(10000) == nil], [true, true])

        CT.section("autoOutfit: \(rows(fx["auto"]).count) dates, each side of every boundary, and the dates that are not dates")
        diffs = []
        for c in rows(fx["auto"]) {
            let got = (whole(c["y"]).flatMap { y in whole(c["m"]).flatMap { m in whole(c["d"]).map { Wardrobe.autoOutfit(y, m, $0) } } }) ?? "none"
            if got != c["out"] as! String { diffs.append("\(String(describing: c["y"]))-\(String(describing: c["m"]))-\(String(describing: c["d"])): \(got)") }
        }
        CT.checkRows("every date is as the fixture says", diffs)
        CT.check("a day that is not a day is none", [Wardrobe.autoOutfit(2026, 2, 30), Wardrobe.autoOutfit(2026, 13, 1), Wardrobe.autoOutfit(2026, 12, 0), Wardrobe.autoOutfit(0, 12, 24), Wardrobe.autoOutfit(10000, 12, 24), Wardrobe.autoOutfit(2023, 2, 29), Wardrobe.autoOutfit(2100, 2, 29)], Array(repeating: "none", count: 7))
        CT.check("29 February of a leap year is a day (and nothing to wear)", Wardrobe.autoOutfit(2024, 2, 29), "none")

        CT.section("Easter's window, walked with the calendar: \(rows(fx["easterWindows"]).count) years")
        diffs = []
        for w in rows(fx["easterWindows"]) {
            for d in rows(w["days"]) where Wardrobe.autoOutfit(int(d["y"]), int(d["m"]), int(d["d"])) != d["out"] as! String { diffs.append("k \(int(d["k"])) of \(int(w["year"]))") }
        }
        CT.checkRows("Good Friday to Easter Monday wears the bunny ears and the days round it nothing, in March and in April", diffs)

        CT.section("resolve: \(rows(fx["resolve"]).count) choices")
        diffs = []
        for c in rows(fx["resolve"]) where Wardrobe.resolve(c["id"], int(c["y"]), int(c["m"]), int(c["d"])) != c["out"] as! String { diffs.append("\(String(describing: c["id"]))") }
        CT.checkRows("Auto is resolved for the date, an outfit stays, a made-up name is Auto", diffs)
        CT.check("the label for Auto", [Wardrobe.autoLabel(today: "santahat"), Wardrobe.autoLabel(today: "none")], ["Auto: today, Santa hat", "Auto: today, none"])

        CT.section("the Debug panel's date field and its next day")
        CT.check("a real date is read", Wardrobe.parseDay("2026-12-24"), Wardrobe.Day(y: 2026, m: 12, d: 24))
        CT.check("and nothing else is", ["2026-12-2", "2026-2-24", "26-12-24", "2026-13-01", "2026-02-30", "2026-12-24 ", "2026/12/24", "٢٠٢٦-١٢-٢٤", "", "2026-12", "2026--12-24", "+026-12-24"].compactMap { Wardrobe.parseDay($0) }.count, 0)
        CT.check("the day after", [Wardrobe.nextDay(.init(y: 2026, m: 12, d: 26)), Wardrobe.nextDay(.init(y: 2026, m: 12, d: 31)), Wardrobe.nextDay(.init(y: 2024, m: 2, d: 28)), Wardrobe.nextDay(.init(y: 2023, m: 2, d: 28)), Wardrobe.nextDay(.init(y: 2100, m: 2, d: 28)), Wardrobe.nextDay(.init(y: 2026, m: 4, d: 30))],
                 [.init(y: 2026, m: 12, d: 27), .init(y: 2027, m: 1, d: 1), .init(y: 2024, m: 2, d: 29), .init(y: 2023, m: 3, d: 1), .init(y: 2100, m: 3, d: 1), .init(y: 2026, m: 5, d: 1)])

        CT.section("the date and the seconds to midnight, from the calendar")
        var ny = Calendar(identifier: .gregorian); ny.timeZone = TimeZone(identifier: "America/New_York")!
        func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ mi: Int) -> Date { ny.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: mi))! }
        CT.check("a late evening is still today", Wardrobe.today(now: at(2026, 12, 24, 23, 30), calendar: ny), Wardrobe.Day(y: 2026, m: 12, d: 24))
        CT.checkNear("and midnight is half an hour away", Wardrobe.secondsToMidnight(now: at(2026, 12, 24, 23, 30), calendar: ny), 1800)
        CT.checkNear("the day the clocks go forward is 23 hours long: 00:30 is 22 and a half hours from the next midnight", Wardrobe.secondsToMidnight(now: at(2026, 3, 8, 0, 30), calendar: ny), 22.5 * 3600)
        CT.checkNear("the day they go back is 25 hours long: 00:30 is 24 and a half hours from the next midnight", Wardrobe.secondsToMidnight(now: at(2026, 11, 1, 0, 30), calendar: ny), 24.5 * 3600)
        CT.checkNear("one second before midnight is asked for a full second", Wardrobe.secondsToMidnight(now: ny.date(from: DateComponents(year: 2026, month: 12, day: 24, hour: 23, minute: 59, second: 59, nanosecond: 900_000_000))!, calendar: ny), 1)

        CT.section("the clock: Auto waits for midnight with one one-shot timer")
        let f = Fake()
        var seen: [String] = []
        f.clock.onChange = { seen.append($0) }
        CT.check("before it starts nothing is armed", [f.timers.count, f.clock.isArmed ? 1 : 0], [0, 0])
        f.clock.start()
        CT.check("at launch on 24 December Auto wears the Santa hat", f.clock.resolved, "santahat")
        CT.check("and one timer waits for a second after midnight", [f.timers.count, Int(f.timers[0].after)], [1, 5401])
        CT.check("nothing was announced: the first outfit is read from `resolved`", seen, [])
        f.day = Wardrobe.Day(y: 2026, m: 12, d: 27); f.toMidnight = 86400
        f.fireLast()
        CT.check("at midnight it looks at the date again: nothing to wear on the 27th", f.clock.resolved, "none")
        CT.check("the change was announced", seen, ["none"])
        CT.check("and the next midnight is already waiting (one timer, not two)", [f.timers.count, f.waiting, Int(f.timers[1].after)], [2, 1, 86401])
        f.fireLast()
        CT.check("a timer that fires on the same day changes nothing and waits again", s(f.clock.resolved, seen.count, f.waiting), s("none", 1, 1))
        f.day = Wardrobe.Day(y: 2027, m: 6, d: 25); f.toMidnight = 40000
        f.fireLast()
        CT.check("a timer that fires days late (the Mac slept) recomputes from the date then", f.clock.resolved, "sunglasses")

        CT.section("the clock: an outfit, or None, cancels the timer")
        f.clock.setChoice("bow")
        CT.check("picking the bow shows it, at once, and cancels the timer", s(f.clock.resolved, f.waiting, f.clock.isArmed ? 1 : 0), s("bow", 0, 0))
        f.clock.setChoice("none")
        CT.check("None wears nothing and arms nothing", s(f.clock.resolved, f.waiting), s("none", 0))
        let made = f.timers.count
        f.clock.setChoice("bell")
        CT.check("another outfit arms nothing", f.timers.count, made)
        f.clock.setChoice("auto")
        CT.check("Auto again resolves for the date and arms one timer", s(f.clock.resolved, f.waiting, f.timers.count), s("sunglasses", 1, made + 1))
        f.clock.setChoice("auto")
        CT.check("the same choice again leaves one timer (the old one is cancelled)", f.waiting, 1)
        f.clock.setChoice("Bow")
        CT.check("a made-up name is Auto", s(f.clock.choice, f.clock.resolved, f.waiting), s("auto", "sunglasses", 1))
        f.day = Wardrobe.Day(y: 2026, m: 12, d: 25)
        f.clock.dateChanged()
        CT.check("a date override (Debug panel) is looked at now and the timer is re-armed", s(f.clock.resolved, f.waiting), s("santahat", 1))

        CT.section("the clock: an outfit chosen at launch never starts a timer")
        let g = Fake()
        g.clock.setChoice("crown")
        g.clock.start()
        CT.check("the crown is worn and no timer was asked for", s(g.clock.resolved, g.timers.count), s("crown", 0))
        g.toMidnight = 0.2
        g.clock.setChoice("auto")
        CT.check("a clock that is a hair from midnight still waits a full second", Int(g.timers[0].after), 1)
        CT.finish()
    }
}
