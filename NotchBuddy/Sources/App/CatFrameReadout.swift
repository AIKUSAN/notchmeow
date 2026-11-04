import Foundation
import QuartzCore

#if DEBUG
/// The Debug-only frame-time readout: every cat draw reports its time, and every two seconds a line goes to
/// `~/Library/Logs/NotchMeow/cat-frames.log` (open it with `tail -f`). Release builds do not contain this.
@MainActor
final class CatFrameReadout {
    static let shared = CatFrameReadout()
    private var meter = CatFrameMeter()
    private var lastReport = CACurrentMediaTime()
    /// The last line written to the log: the cat panel shows it.
    private(set) var latest: String?

    func measure(_ draw: () -> Void) {
        let start = CACurrentMediaTime()
        draw()
        let end = CACurrentMediaTime()
        meter.record(start: start, duration: end - start)
        if end - lastReport >= 2, let r = meter.readout() {
            lastReport = end
            latest = r.line
            appendAppLog("cat-frames.log", r.line)
        }
    }
}
#endif
