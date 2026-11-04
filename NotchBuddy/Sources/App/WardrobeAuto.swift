import Foundation

// What Auto wears and when it looks again (sub-project I). Port of `easterOf`, `autoOutfitFor` and `resolveOutfit` in design/prototype/cat-core.js (the tie-breaker);
// tests/fixtures/cat/wardrobe-cases.json pins them. Everything works on date numbers (year, month, day): no clock, no time zone, so a daylight-saving change can never shift
// Easter's window, and the same date gives the same outfit on every platform. `WardrobeClock` keeps the resolved outfit and the ONE one-shot timer Auto needs (the same shape as
// `CatSleepClock`): it takes its date and its timer from outside, so a test moves both by hand. Foundation only.

extension Wardrobe {
    /// A local calendar date as numbers.
    struct Day: Equatable, Sendable { var y: Int, m: Int, d: Int }

    /// Gregorian Easter Sunday of a year from 1583 to 9999 (the Meeus/Jones/Butcher computation); nil for any other year.
    static func easterOf(_ year: Int) -> (month: Int, day: Int)? {
        guard year >= 1583, year <= 9999 else { return nil }
        let a = year % 19, b = year / 100, c = year % 100, d = b / 4, e = b % 4, f = (b + 8) / 25, g = (b - f + 1) / 3
        let h = (19 * a + b - d - g + 15) % 30, i = c / 4, k = c % 4, l = (32 + 2 * e + 2 * i - h - k) % 7, m = (a + 11 * h + 22 * l) / 451, n = h + l - 7 * m + 114
        return (n / 31, n % 31 + 1)
    }

    /// Days since 1970-01-01 of a calendar date, from the date numbers alone, so a difference of two dates can never be shifted by daylight saving.
    static func days(_ y: Int, _ m: Int, _ d: Int) -> Int {
        let yy = m <= 2 ? y - 1 : y, era = yy / 400, yoe = yy - era * 400
        let doy = (153 * (m + (m > 2 ? -3 : 9)) + 2) / 5 + d - 1, doe = yoe * 365 + yoe / 4 - yoe / 100 + doy
        return era * 146097 + doe - 719468
    }

    /// Whether the numbers are a real date (a year from 1 to 9999).
    static func isDate(_ y: Int, _ m: Int, _ d: Int) -> Bool {
        guard y >= 1, y <= 9999, m >= 1, m <= 12, d >= 1 else { return false }
        let leap = y % 4 == 0 && (y % 100 != 0 || y % 400 == 0)
        return d <= [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][m - 1]
    }

    /// What Auto wears on a local date. The first rule that matches wins, and the order is the contract: 1 Dec 31 to Jan 2 `partyhat`; 2 Dec 1 to Dec 26 `santahat`;
    /// 3 Oct 1 to Nov 1 `witchhat`; 4 Good Friday to Easter Monday (Easter minus 2 days to plus 1) `bunnyears`; 5 Jun 21 to Aug 31 `sunglasses`. Anything else, and a date that is
    /// not a real date, is `none`.
    static func autoOutfit(_ y: Int, _ m: Int, _ d: Int) -> String {
        guard isDate(y, m, d) else { return "none" }
        if (m == 12 && d == 31) || (m == 1 && d <= 2) { return "partyhat" }
        if m == 12 && d <= 26 { return "santahat" }
        if m == 10 || (m == 11 && d == 1) { return "witchhat" }
        if let e = easterOf(y) {
            let k = days(y, m, d) - days(y, e.month, e.day)
            if k >= -2 && k <= 1 { return "bunnyears" }
        }
        if (m == 6 && d >= 21) || m == 7 || m == 8 { return "sunglasses" }
        return "none"
    }

    static func autoOutfit(_ day: Day) -> String { autoOutfit(day.y, day.m, day.d) }

    /// The outfit to draw: the stored choice cleaned, with `auto` replaced by what Auto says for the date (`none` when nothing is worn). Never `auto`.
    static func resolve(_ id: Any?, _ y: Int, _ m: Int, _ d: Int) -> String {
        let o = idOf(id)
        return o == "auto" ? autoOutfit(y, m, d) : o
    }

    static func resolve(_ id: Any?, _ day: Day) -> String { resolve(id, day.y, day.m, day.d) }

    /// Settings' and the menus' label for Auto: "Auto: today, Santa hat" or "Auto: today, none". `today` is `autoOutfit` for today.
    static func autoLabel(today id: String) -> String { "Auto: today, " + (id == "none" ? "none" : name(id)) }

    /// "2026-12-24" as a date: exactly four digits, a hyphen, two, a hyphen, two, and a real date; nil for anything else (the Debug panel's date field).
    static func parseDay(_ text: String) -> Day? {
        let p = text.split(separator: "-", omittingEmptySubsequences: false)
        guard p.count == 3, p[0].count == 4, p[1].count == 2, p[2].count == 2, p.allSatisfy({ $0.utf8.allSatisfy { (48...57).contains($0) } }),
              let y = Int(p[0]), let m = Int(p[1]), let d = Int(p[2]), isDate(y, m, d) else { return nil }
        return Day(y: y, m: m, d: d)
    }

    /// The next calendar day (the Debug panel's "midnight in 5 seconds").
    static func nextDay(_ day: Day) -> Day {
        let leap = day.y % 4 == 0 && (day.y % 100 != 0 || day.y % 400 == 0)
        let last = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31][max(1, min(12, day.m)) - 1]
        if day.d < last { return Day(y: day.y, m: day.m, d: day.d + 1) }
        return day.m == 12 ? Day(y: day.y + 1, m: 1, d: 1) : Day(y: day.y, m: day.m + 1, d: 1)
    }

    /// The local calendar date now. `autoupdatingCurrent`, not `current`: a change of time zone while the app runs is read, not a copy taken at launch.
    static func today(now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> Day {
        let c = calendar.dateComponents([.year, .month, .day], from: now)
        return Day(y: c.year ?? 1970, m: c.month ?? 1, d: c.day ?? 1)
    }

    /// Seconds from `now` to the next local midnight (at least a second, so a clock that is a hair early never asks for zero).
    static func secondsToMidnight(now: Date = Date(), calendar: Calendar = .autoupdatingCurrent) -> Double {
        guard let next = calendar.nextDate(after: now, matching: DateComponents(hour: 0, minute: 0, second: 0), matchingPolicy: .nextTime) else { return 3600 }
        return max(1, next.timeIntervalSince(now))
    }
}

/// The menus' items, by the grid's order. The island cat's menu and the desktop cat's menu both turn them into an `NSMenu`.
enum WardrobeMenu {
    enum Item: Equatable, Sendable {
        case choice(id: String, title: String, checked: Bool)
        case heading(String)
        case separator
    }

    /// The 18 entries in their groups, a check on the stored choice. `autoToday` is what Auto wears today (`Wardrobe.autoOutfit`), for the first label.
    static func items(selected: String, autoToday: String) -> [Item] {
        let chosen = Wardrobe.idOf(selected)
        var list: [Item] = []
        for (i, g) in Wardrobe.groups.enumerated() {
            if i > 0 { list.append(.separator) }
            if !g.name.isEmpty { list.append(.heading(g.name)) }
            for id in g.ids { list.append(.choice(id: id, title: id == "auto" ? Wardrobe.autoLabel(today: autoToday) : Wardrobe.name(id), checked: id == chosen)) }
        }
        return list
    }
}

/// Keeps the outfit every big cat wears now. `auto` is resolved from the date: at launch (`start`), when the choice changes, and at the next local midnight, with one one-shot
/// timer that exists only while the choice is `auto` (picking an outfit, or None, cancels it). When the timer fires late, after a long sleep, it recomputes from the date then;
/// when it fires early, it asks again for the rest. Nothing polls.
@MainActor
final class WardrobeClock {
    /// Cancels a scheduled call.
    typealias Cancel = () -> Void

    private let today: () -> Wardrobe.Day
    private let secondsToMidnight: () -> Double
    private let schedule: (_ afterSeconds: Double, _ fire: @escaping @MainActor @Sendable () -> Void) -> Cancel
    private var cancel: Cancel?
    private(set) var choice = Wardrobe.defaultOutfit
    /// The outfit to draw: one of the 16 IDs, or `none`. Never `auto`.
    private(set) var resolved = "none"
    /// Called with the new outfit when it changes.
    var onChange: ((String) -> Void)?
    /// Whether the one-shot is waiting (true only while the choice is `auto`).
    var isArmed: Bool { cancel != nil }

    init(today: @escaping () -> Wardrobe.Day, secondsToMidnight: @escaping () -> Double, schedule: @escaping (Double, @escaping @MainActor @Sendable () -> Void) -> Cancel) {
        self.today = today; self.secondsToMidnight = secondsToMidnight; self.schedule = schedule
        resolved = Wardrobe.resolve(choice, today())
    }

    /// Resolves the stored choice for today and, for `auto`, waits for midnight.
    func start() { refresh(); rearm() }

    /// The stored choice changed (or was just loaded).
    func setChoice(_ raw: Any?) {
        choice = Wardrobe.idOf(raw)
        refresh()
        rearm()
    }

    /// The date changed under us (the Debug panel's date override): look again now.
    func dateChanged() { refresh(); rearm() }

    private func refresh() {
        let next = Wardrobe.resolve(choice, today())
        guard next != resolved else { return }
        resolved = next
        onChange?(next)
    }

    private func rearm() {
        cancel?(); cancel = nil
        guard choice == "auto" else { return }
        cancel = schedule(max(1, secondsToMidnight() + 1)) { [weak self] in self?.fire() }
    }

    private func fire() {
        cancel = nil
        refresh()
        rearm()
    }
}

#if DEBUG && !APPSTORE
/// The names the Debug cat panel's Wardrobe section and the app's `WardrobeClock` share (a Debug build only; compiled out of Release and App Store): the panel posts them, the clock listens, so the
/// panel compiles without the app's files.
enum WardrobeDev {
    /// userInfo `["day": "2026-12-24"]` (text that `Wardrobe.parseDay` reads; anything else is "no date pretended").
    static let dateNote = Notification.Name("nm.wardrobe.debugDate")
    /// "The next midnight is five seconds away" (the clock's one-shot is asked for it and the pretend date moves on a day).
    static let midnightNote = Notification.Name("nm.wardrobe.debugMidnight")
}
#endif
