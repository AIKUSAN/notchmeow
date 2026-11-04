import Foundation

// MARK: - Plan window

struct PlanWindow: Codable {
    let usedPct: Double   // 0–100, clamped
    let resetsAt: Date
}

// MARK: - Plan usage

struct PlanUsage: Codable {
    var fiveHour: PlanWindow?
    var sevenDay: PlanWindow?
    var updatedAt: Date
}

// MARK: - Parsing + helpers (Foundation-only, no AppKit/SwiftUI)

enum ClaudePlanGauge {

    /// Parses rate_limits from a statusline payload dict. Returns nil if absent/malformed.
    static func parse(payload: [String: Any]) -> PlanUsage? {
        guard let limits = payload["rate_limits"] as? [String: Any] else { return nil }
        let fh = parseWindow(limits["five_hour"])
        let sd = parseWindow(limits["seven_day"])
        guard fh != nil || sd != nil else { return nil }
        return PlanUsage(fiveHour: fh, sevenDay: sd, updatedAt: Date())
    }

    private static func parseWindow(_ raw: Any?) -> PlanWindow? {
        guard let d = raw as? [String: Any] else { return nil }
        let rawPct: Double
        if let v = d["used_percentage"] as? Double { rawPct = v }
        else if let v = d["used_percentage"] as? Int { rawPct = Double(v) }
        else { return nil }
        guard rawPct >= 0, rawPct <= 200 else { return nil }
        let pct = min(100, rawPct)   // clamp 100–200 down to 100
        let rawEpoch: Double
        if let v = d["resets_at"] as? Double { rawEpoch = v }
        else if let v = d["resets_at"] as? Int { rawEpoch = Double(v) }
        else { return nil }
        guard rawEpoch > 0 else { return nil }
        // Reject if more than 400 days in the future (likely milliseconds, not seconds)
        let maxEpoch = Date().timeIntervalSince1970 + 400 * 86400
        guard rawEpoch <= maxEpoch else { return nil }
        return PlanWindow(usedPct: pct, resetsAt: Date(timeIntervalSince1970: rawEpoch))
    }

    /// Effective % for display: 0 if the reset time is in the past.
    static func effectivePct(_ w: PlanWindow) -> Double {
        w.resetsAt <= Date() ? 0 : w.usedPct
    }

    /// The higher of the two effective percentages. nil if both windows absent.
    static func dominantPct(_ usage: PlanUsage) -> Double? {
        let p1 = usage.fiveHour.map { effectivePct($0) }
        let p2 = usage.sevenDay.map { effectivePct($0) }
        switch (p1, p2) {
        case (.none, .none): return nil
        case (let x?, .none): return x
        case (.none, let y?): return y
        case (let x?, let y?): return max(x, y)
        }
    }

    /// Hex color for a given percentage (nil → grey).
    static func color(for pct: Double?) -> String {
        guard let p = pct else { return "#6B7079" }
        if p < 50  { return "#22C55E" }
        if p < 80  { return "#F59E0B" }
        return "#F4505E"
    }

    /// The line under the relay buttons in Settings → Agents → Plan usage: what the relay has heard. nil while the relay is not installed. Claude Code sends the usage only after the first reply of a session and
    /// only for Pro and Max plans, so right after an install the notch pill reads "Claude —" until then: this line says so instead of leaving the user to wonder.
    static func statusNote(relayInstalled: Bool, usage: PlanUsage?, now: Date = Date(), timeZone: TimeZone = .current) -> String? {
        guard relayInstalled else { return nil }
        func pct(_ w: PlanWindow) -> String { "\(Int((w.resetsAt <= now ? 0 : w.usedPct).rounded())) %" }
        var parts: [String] = []
        if let w = usage?.fiveHour { parts.append("5-hour \(pct(w))") }
        if let w = usage?.sevenDay { parts.append("weekly \(pct(w))") }
        guard let usage, !parts.isEmpty else {
            return "Waiting for Claude Code: it sends your usage after the first reply of a session (Pro and Max plans only)."
        }
        let fmt = DateFormatter()
        fmt.locale = Locale(identifier: "en_US_POSIX")
        fmt.timeZone = timeZone
        fmt.dateFormat = "HH:mm"
        return "Last update \(fmt.string(from: usage.updatedAt)): \(parts.joined(separator: ", "))."
    }

    /// Label shown in the island pill chip.
    static func pillLabel(_ usage: PlanUsage?) -> String {
        guard let usage, let pct = dominantPct(usage) else { return "Claude plan" }
        return "Claude \(Int(pct.rounded()))%"
    }
}
