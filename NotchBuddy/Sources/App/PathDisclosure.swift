import SwiftUI

// A path is not on the page by default: a "Show path" button opens it in 11 pt monospace, selectable and wrapping (never cut), with Copy and, where the path is a folder or file,
// Show in Finder. `path` is already the display form (the home folder shown as ~, see SettingsLayout.displayPath).

struct PathDisclosure: View {
    let path: String
    let copy: (String) -> Void
    let reveal: (() -> Void)?
    @State private var open: Bool
    /// `opened` is only for the pictures (the page starts closed).
    init(path: String, copy: @escaping (String) -> Void, reveal: (() -> Void)? = nil, opened: Bool = false) {
        self.path = path; self.copy = copy; self.reveal = reveal; _open = State(initialValue: opened)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(open ? "Hide path" : "Show path") { open.toggle() }
                .buttonStyle(.bordered).controlSize(.small).fixedSize()
            if open {
                Text(path)
                    .font(.system(size: 11, design: .monospaced))
                    .textSelection(.enabled)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
                WrapRow {
                    Button("Copy") { copy(path) }.buttonStyle(.bordered).controlSize(.small)
                    if let reveal { Button("Show in Finder", action: reveal).buttonStyle(.bordered).controlSize(.small) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
