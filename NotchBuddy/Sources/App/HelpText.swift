import SwiftUI
import AppKit

// The Settings pages' help line: 12 pt in the help colour (4.5:1 or better in light and dark, SettingsColors.help), wrapping between words and never truncated.

struct HelpText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .font(.system(size: SettingsLayout.helpSize))
            .foregroundColor(Color(nsColor: SettingsColors.help))
            .fixedSize(horizontal: false, vertical: true)
    }
}
