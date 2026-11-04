import SwiftUI

// A row with a switch. The label is a button that flips it (nothing when `disabled`). The chip, if any, sits before the switch on one line and under the label when the row is too
// narrow; the label then wraps between words beside the switch. A switch that needs something first stays switchable (the chip says what), only `disabled` turns it off.

struct SwitchRow: View {
    let label: String
    let help: String?
    @Binding var isOn: Bool
    let chip: String?
    let disabled: Bool
    init(_ label: String, help: String? = nil, isOn: Binding<Bool>, chip: String? = nil, disabled: Bool = false) {
        self.label = label; self.help = help; _isOn = isOn; self.chip = chip; self.disabled = disabled
    }

    private var labelButton: some View {
        Button { isOn.toggle() } label: { Text(label).contentShape(Rectangle()) }
            .buttonStyle(.plain)
            .accessibilityHidden(true)
    }

    private var toggle: some View {
        Toggle("", isOn: $isOn).labelsHidden().toggleStyle(.switch).accessibilityLabel(label)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    labelButton.fixedSize()
                    Spacer(minLength: 12)
                    if let chip { StatusChip(chip).padding(.trailing, 10) }
                    toggle
                }
                HStack(alignment: .top, spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        labelButton.fixedSize(horizontal: false, vertical: true)
                        if let chip { StatusChip(chip) }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    toggle
                }
            }
            if let help { HelpText(help) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .disabled(disabled)
    }
}
