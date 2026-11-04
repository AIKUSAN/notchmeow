import Foundation

/// The frame-time budget of the cats: twelve small cats plus the big one stay under this many milliseconds of drawing per frame.
let catFrameBudgetMs = 2.0

/// Adds up the time every cat draw takes, frame by frame. The views time each draw and report it here (in Debug builds only); the
/// draws of one display frame come one after the other within a few milliseconds, so a draw that starts within `window` seconds of
/// the first draw of a group belongs to that frame.
struct CatFrameMeter {
    /// One finished frame: how long all its cats took to draw, and how many cats there were.
    struct Frame: Equatable { var ms: Double; var cats: Int }

    var window = 0.006
    /// The last `keep` frames, oldest first.
    private(set) var frames: [Frame] = []
    var keep = 240
    private var groupStart: Double?
    private var groupMs = 0.0
    private var groupCats = 0

    /// A draw that started at `start` (seconds, any steady clock) and took `duration` seconds.
    mutating func record(start: Double, duration: Double) {
        if let g = groupStart, start - g > window { closeGroup() }
        if groupStart == nil { groupStart = start }
        groupMs += duration * 1000
        groupCats += 1
    }

    private mutating func closeGroup() {
        guard groupStart != nil else { return }
        frames.append(Frame(ms: groupMs, cats: groupCats))
        if frames.count > keep { frames.removeFirst(frames.count - keep) }
        groupStart = nil; groupMs = 0; groupCats = 0
    }

    /// Average, worst and 95th-percentile frame, and the most cats seen in one frame. nil until a frame has closed.
    func summary() -> (avgMs: Double, p95Ms: Double, maxMs: Double, cats: Int)? {
        guard !frames.isEmpty else { return nil }
        let sorted = frames.map(\.ms).sorted()
        return (sorted.reduce(0, +) / Double(sorted.count), sorted[min(sorted.count - 1, Int(Double(sorted.count) * 0.95))], sorted.last!, frames.map(\.cats).max()!)
    }

    /// One line for the log, and whether the average is over the budget.
    func readout() -> (line: String, overBudget: Bool)? {
        guard let s = summary() else { return nil }
        let over = s.avgMs > catFrameBudgetMs
        return (String(format: "cat frame: avg %.2f ms, p95 %.2f ms, max %.2f ms, up to %d cats%@", s.avgMs, s.p95Ms, s.maxMs, s.cats,
                       over ? " (OVER the \(catFrameBudgetMs) ms budget)" : ""), over)
    }
}
