import SwiftUI
import AppKit

// A status word with its dot ("Ready", "Not installed", "Needs update"). The dot comes from SettingsStatus.tone, so every chip of the same word looks the same. Fixed size: the chip is
// never wrapped or cut; a row that has no room for it moves it to its own line first (the rows put it in a ViewThatFits).

struct StatusChip: View {
    let text: String
    init(_ text: String) { self.text = text }

    private var dot: Color {
        switch SettingsStatus.tone(text) {
        case .ok: return Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255)   // #22C55E, written out: the cat picture compiles this file without the app's hex helper
        case .warn: return .orange
        case .error: return .red
        case .neutral: return .secondary
        }
    }

    var body: some View {
        HStack(spacing: 5) {
            Circle().fill(dot).frame(width: 7, height: 7)
            Text(text).font(.system(size: 11)).foregroundColor(Color(nsColor: SettingsColors.help))
        }
        .fixedSize()
        .accessibilityElement(children: .combine)
    }
}
