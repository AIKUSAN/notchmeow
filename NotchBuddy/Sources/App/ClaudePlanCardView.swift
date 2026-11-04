import SwiftUI

// MARK: - Claude Plan Card View

struct ClaudePlanCardView: View {
    let usage: PlanUsage?   // nil = installed, no data yet
    /// Two cats mode's shifted card: the rows have 34 pt less width, so each reset time goes on a second line under its bar. False is the card as it ships.
    var stacked: Bool = false

    @State private var now = Date()

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                let dominant = usage.flatMap { ClaudePlanGauge.dominantPct($0) }
                Circle()
                    .fill(Color(hex: ClaudePlanGauge.color(for: dominant)))
                    .frame(width: 7, height: 7)
                // The title keeps its line and the subtitle gives way, with data or without: the waiting subtitle is the longest text here and used to squeeze the title out.
                Text("Claude plan")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                    .lineLimit(1)
                    .layoutPriority(1)
                Text(subtitleText)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#8E939C"))
                    .lineLimit(1)
            }
            .padding(.top, 6)
            .padding(.leading, 108)
            .padding(.trailing, CatIslandLayout.planRowsTrailing)

            // Gauge rows
            VStack(alignment: .leading, spacing: stacked ? 3 : 5) {
                GaugeRowView(label: "5 hours", window: usage?.fiveHour, now: now, stacked: stacked)
                GaugeRowView(label: "Week",    window: usage?.sevenDay,  now: now, weekly: true, stacked: stacked)
            }
            .padding(.top, 8)
            .padding(.leading, 108)
            .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 4)
        // Update countdown every 30s, only while visible
        .background(
            TimelineView(.periodic(from: .now, by: 30)) { ctx in
                Color.clear.onChange(of: ctx.date) { _, d in now = d }
            }
        )
    }

    private var subtitleText: String {
        guard let usage else { return "Waiting for a Claude Code reply" }
        let diff = now.timeIntervalSince(usage.updatedAt)
        if diff < 60 { return "just now" }
        let mins = Int(diff / 60)
        if mins < 60 { return "\(mins) min ago" }
        return "\(mins / 60) h ago"
    }
}

// MARK: - Gauge Row

// DateFormatter created once, in English, for the weekly reset label
private let weeklyResetFormatter: DateFormatter = {
    let fmt = DateFormatter()
    fmt.locale = Locale(identifier: "en_US_POSIX")
    fmt.dateFormat = "EEE H:mm"
    return fmt
}()

private struct GaugeRowView: View {
    let label: String
    let window: PlanWindow?
    let now: Date
    var weekly: Bool = false
    var stacked: Bool = false

    var body: some View {
        if stacked { stackedRow } else { shippingRow }
    }

    /// The shifted card's row (Two cats mode): the same first line, and the reset time on a second line under the bar so nothing passes the card's edge.
    private var stackedRow: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: CatIslandLayout.planRowSpacing) {
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#6B7079"))
                    .frame(width: CatIslandLayout.planLabelWidth, alignment: .leading)
                if let w = window {
                    let pct = ClaudePlanGauge.effectivePct(w)
                    let accent = Color(hex: ClaudePlanGauge.color(for: pct))
                    ZStack(alignment: .leading) {
                        Capsule()
                            .fill(Color.white.opacity(0.08))
                            .frame(width: CatIslandLayout.planBarWidth, height: 4)
                        Capsule()
                            .fill(accent)
                            .frame(width: max(0, CatIslandLayout.planBarWidth * CGFloat(pct / 100)), height: 4)
                    }
                    .frame(width: CatIslandLayout.planBarWidth, height: 4)
                    Text("\(Int(pct.rounded()))%")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: "#C5C8CD"))
                        .monospacedDigit()
                        .lineLimit(1)
                        .frame(width: CatIslandLayout.planPercentWidth, alignment: .trailing)
                } else {
                    Text("—")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#6B7079"))
                    Spacer()
                }
            }
            if let w = window {
                HStack(spacing: CatIslandLayout.planRowSpacing) {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 8))
                        .foregroundColor(Color(hex: "#6B7079"))
                    Text(resetLabel(w))
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#6B7079"))
                        .fixedSize()
                }
                .padding(.leading, CatIslandLayout.planResetIndent)
            }
        }
    }

    private var shippingRow: some View {
        HStack(spacing: 5) {
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#6B7079"))
                .frame(width: 40, alignment: .leading)
            if let w = window {
                let pct = ClaudePlanGauge.effectivePct(w)
                let accent = Color(hex: ClaudePlanGauge.color(for: pct))
                // Fixed-width bar (~50pt)
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(Color.white.opacity(0.08))
                        .frame(width: 50, height: 4)
                    Capsule()
                        .fill(accent)
                        .frame(width: max(0, 50 * CGFloat(pct / 100)), height: 4)
                }
                .frame(width: 50, height: 4)
                Text("\(Int(pct.rounded()))%")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#C5C8CD"))
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(width: CatIslandLayout.planPercentWidth, alignment: .trailing)
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 8))
                    .foregroundColor(Color(hex: "#6B7079"))
                Text(resetLabel(w))
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#6B7079"))
                    .fixedSize()
            } else {
                Text("—")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#6B7079"))
                Spacer()
            }
        }
    }

    private func resetLabel(_ w: PlanWindow) -> String {
        let secs = w.resetsAt.timeIntervalSince(now)
        guard secs > 0 else { return "Resetting…" }
        if weekly {
            return weeklyResetFormatter.string(from: w.resetsAt)
        } else {
            let h = Int(secs / 3600)
            let m = Int((secs.truncatingRemainder(dividingBy: 3600)) / 60)
            if h > 0 { return "in \(h) h \(m)" }
            return "in \(m) min"
        }
    }
}
