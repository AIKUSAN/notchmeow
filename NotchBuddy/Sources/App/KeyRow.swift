import SwiftUI

// A key or URL field with its buttons. The field fills the row up to `fieldMax`, never past the column. Under it, in a WrapRow so no button is cut: Save (when the card can save),
// the check mark after a key was tried (the same marks and colours as before), "Not saved" while the text is typed and not saved, and Remove once a key is saved.

struct KeyRow: View {
    let placeholder: String
    @Binding var text: String
    let saved: Bool, dirty: Bool, works: Bool?, secure: Bool
    let save: (() -> Void)?, remove: (() -> Void)?
    init(_ placeholder: String, text: Binding<String>, saved: Bool, dirty: Bool, works: Bool? = nil, secure: Bool = true,
         save: (() -> Void)? = nil, remove: (() -> Void)? = nil) {
        self.placeholder = placeholder; _text = text; self.saved = saved; self.dirty = dirty; self.works = works; self.secure = secure
        self.save = save; self.remove = remove
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Group {
                if secure { SecureField(placeholder, text: $text) } else { TextField(placeholder, text: $text) }
            }
            .textFieldStyle(.roundedBorder)
            .frame(maxWidth: SettingsLayout.fieldMax)
            WrapRow {
                if let save { saveButton(save) }
                if let works {
                    Image(systemName: works ? "checkmark.circle.fill" : "xmark.circle.fill")
                        .foregroundColor(works ? Color(hex: "#22C55E") : .red)
                        .accessibilityLabel(works ? "Key works" : "Key rejected")
                }
                if dirty { StatusChip("Not saved") }
                if saved, let remove { Button("Remove", action: remove).buttonStyle(.bordered) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    /// Save is prominent and enabled only while the text differs from what is stored; otherwise it is plain and disabled, so an untouched card shows nothing to press.
    @ViewBuilder private func saveButton(_ save: @escaping () -> Void) -> some View {
        if dirty {
            Button("Save", action: save).buttonStyle(.borderedProminent)
        } else {
            Button("Save", action: save).buttonStyle(.bordered).disabled(true)
        }
    }
}
