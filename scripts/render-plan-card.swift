import AppKit
import SwiftUI

// Draws the Claude plan card (ClaudePlanCardView.swift) into a PNG without launching NotchMeow: the card's own SwiftUI view goes into a window that is never shown. The card is 322 pt wide and
// 98 pt high as in the overview; a red line marks its right edge (x = 322) and the canvas goes 70 pt past it, so anything that overflows the card is visible. The usage is made of fixed
// labels, the longest the card shows: "in 4 h 59" and "Thu 14:30".
//   bash scripts/render-plan-card.sh --out plan-card.png [--stacked] [--shift 34] [--waiting] [--ago 5]
//   --stacked/--shift are what Two cats mode gives the card (`stacked: true`, 34 pt in); no flags is the card as it ships; --waiting is the card with no data yet (the longest subtitle);
//   --ago is how many minutes old the data is (the subtitle: 59 is the longest ordinary one).

extension Color {
    init(hex: String) {   // the app's own, in IslandRootView.swift
        let val = UInt64(hex.trimmingCharacters(in: CharacterSet(charactersIn: "#")), radix: 16) ?? 0
        self.init(red: Double((val >> 16) & 0xFF) / 255, green: Double((val >> 8) & 0xFF) / 255, blue: Double(val & 0xFF) / 255)
    }
}

@main
struct RenderPlanCard {
    @MainActor static func main() {
        var out = "plan-card.png", stacked = false, shift = 0.0, waiting = false, ago = 5.0
        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let k = it.next() {
            switch k {
            case "--out": out = it.next() ?? out
            case "--stacked": stacked = true
            case "--shift": shift = Double(it.next() ?? "") ?? shift
            case "--waiting": waiting = true
            case "--ago": ago = Double(it.next() ?? "") ?? ago
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
        }
        _ = NSApplication.shared
        let now = Date()
        let thursday = Calendar.current.nextDate(after: now, matching: DateComponents(hour: 14, minute: 30, weekday: 5), matchingPolicy: .nextTime) ?? now.addingTimeInterval(86400)
        let usage = PlanUsage(fiveHour: PlanWindow(usedPct: 63, resetsAt: now.addingTimeInterval(4 * 3600 + 59 * 60 + 30)),
                              sevenDay: PlanWindow(usedPct: 100, resetsAt: thursday), updatedAt: now.addingTimeInterval(-ago * 60))
        let card = ClaudePlanCardView(usage: waiting ? nil : usage, stacked: stacked)
            .padding(.leading, CGFloat(shift))
            .frame(width: 322, height: 98, alignment: .topLeading)
            .background(Color(hex: "#25262A"))
            .overlay(alignment: .trailing) { Rectangle().fill(Color.red).frame(width: 1) }
            .frame(width: 392, height: 98, alignment: .leading)
            .foregroundColor(Color(hex: "#F5F6F8"))
        let host = NSHostingView(rootView: card)
        host.frame = NSRect(x: 0, y: 0, width: 392, height: 98)
        let win = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: .darkAqua)
        win.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        host.layoutSubtreeIfNeeded()
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { FileHandle.standardError.write(Data("no bitmap\n".utf8)); exit(1) }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let shot = rep.cgImage,
              let cg = CGContext(data: nil, width: shot.width, height: shot.height, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                 bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { exit(1) }
        cg.setFillColor(CGColor(srgbRed: 0.05, green: 0.05, blue: 0.06, alpha: 1))
        cg.fill(CGRect(x: 0, y: 0, width: shot.width, height: shot.height))
        cg.draw(shot, in: CGRect(x: 0, y: 0, width: shot.width, height: shot.height))
        guard let flat = cg.makeImage(), let png = NSBitmapImageRep(cgImage: flat).representation(using: .png, properties: [:]) else { exit(1) }
        try! png.write(to: URL(fileURLWithPath: out))
        print("wrote \(out)")
    }
}
