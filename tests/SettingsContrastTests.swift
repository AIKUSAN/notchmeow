import AppKit
import Foundation

// The help text reads at 4.5:1 or better, in light and dark, on the two system backgrounds a Settings card sits on. A card's own fill is a translucent material that cannot be
// resolved off screen, so the check uses the backgrounds beneath it; the render pictures show the real card. Run through scripts/test-settings-contrast.sh.

@main
enum SettingsContrastTests {
    @MainActor static func main() {
        let appearances: [(name: String, appearance: NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]
        let backgrounds: [(name: String, color: NSColor)] = [("windowBackgroundColor", .windowBackgroundColor), ("controlBackgroundColor", .controlBackgroundColor)]

        CT.section("help text: 4.5:1 or better on both backgrounds, in light and dark")
        for (look, appearance) in appearances {
            for (bgName, bg) in backgrounds {
                let ratio = SettingsColors.contrast(SettingsColors.help, over: bg, appearance: appearance)
                CT.checkTrue("\(look): help over \(bgName) is \(String(format: "%.2f", ratio)):1 (4.5 or more)", ratio >= 4.5)
            }
        }

        // Headless, the system window and control backgrounds resolve to one colour each (white, #1E1E1E in dark), so they do not show a real window. The check
        // below names the window colours a real Settings window sits on: #ECECEC in light and #1E1E1E in dark.
        CT.section("help text over a real light window (#ECECEC) and a real dark window (#1E1E1E)")
        let lightWindow = NSColor(srgbRed: CGFloat(0xEC) / 255, green: CGFloat(0xEC) / 255, blue: CGFloat(0xEC) / 255, alpha: 1)
        let darkWindow = NSColor(srgbRed: CGFloat(0x1E) / 255, green: CGFloat(0x1E) / 255, blue: CGFloat(0x1E) / 255, alpha: 1)
        let lightRatio = SettingsColors.contrast(SettingsColors.help, over: lightWindow, appearance: .aqua)
        let darkRatio = SettingsColors.contrast(SettingsColors.help, over: darkWindow, appearance: .darkAqua)
        CT.checkTrue("light: help over #ECECEC is \(String(format: "%.2f", lightRatio)):1 (4.5 or more)", lightRatio >= 4.5)
        CT.checkTrue("dark: help over #1E1E1E is \(String(format: "%.2f", darkRatio)):1 (4.5 or more)", darkRatio >= 4.5)

        CT.section("information: the secondary label, not asserted")
        let info = SettingsColors.contrast(.secondaryLabelColor, over: .windowBackgroundColor, appearance: .darkAqua)
        print("  info: secondaryLabelColor over windowBackgroundColor, dark: \(String(format: "%.2f", info)):1")

        CT.finish()
    }
}
