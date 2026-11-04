import SwiftUI

// A label, optional help under it, and a control. Label left and control right when both fit on one line; otherwise the row stacks and the control goes under the label at full width.
// The label is never squeezed: in the side-by-side layout it is `.fixedSize()`, in the stacked one it wraps between words.

struct SettingRow<Control: View>: View {
    let label: String
    let help: String?
    let control: Control
    init(_ label: String, help: String? = nil, @ViewBuilder control: () -> Control) {
        self.label = label; self.help = help; self.control = control()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 0) {
                    Text(label).fixedSize()
                    Spacer(minLength: 12)
                    control
                }
                VStack(alignment: .leading, spacing: 6) {
                    Text(label).fixedSize(horizontal: false, vertical: true)
                    control.frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if let help { HelpText(help) }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
