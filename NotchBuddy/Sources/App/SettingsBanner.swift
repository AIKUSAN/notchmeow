import SwiftUI

// The line that says what just happened ("Checking the key…", "Hooks installed", an error). It sits at the top of the page, under the tabs, wraps to as many lines as it needs, is red
// when the message starts with ❌ and has an x that dismisses it. The message texts are the old ones, unchanged.

struct SettingsBanner: View {
    let text: String
    let dismiss: () -> Void
    init(_ text: String, dismiss: @escaping () -> Void) { self.text = text; self.dismiss = dismiss }

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Text(text)
                .font(.system(size: 12))
                .foregroundColor(text.hasPrefix("❌") ? .red : .secondary)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
            Button(action: dismiss) {
                Image(systemName: "xmark").font(.system(size: 10, weight: .semibold)).foregroundColor(.secondary)
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.leading, 12).padding(.trailing, 4).padding(.vertical, 4)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color(nsColor: .controlBackgroundColor)))
        .accessibilityElement(children: .contain)
    }
}
