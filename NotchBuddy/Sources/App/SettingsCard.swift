import SwiftUI

// One card of a page: a GroupBox with its title, an optional status chip on the right of the title (under it when the title and the chip do not fit on one line) and an optional
// footer in help text. `dot` puts a coloured dot before the title (the Keys cards' provider colour). Every card is as wide as the page's column.

struct SettingsCard<Content: View>: View {
    let title: String
    let summary: String?
    let footer: String?
    let dot: Color?
    let content: Content
    init(_ title: String, summary: String? = nil, footer: String? = nil, dot: Color? = nil, @ViewBuilder content: () -> Content) {
        self.title = title; self.summary = summary; self.footer = footer; self.dot = dot; self.content = content()
    }

    private var heading: some View {
        HStack(spacing: 6) {
            if let dot { Circle().fill(dot).frame(width: 8, height: 8) }
            Text(title)
        }
    }

    private var header: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 8) {
                heading.fixedSize()
                Spacer(minLength: 8)
                if let summary { StatusChip(summary) }
            }
            VStack(alignment: .leading, spacing: 4) {
                heading.fixedSize(horizontal: false, vertical: true)
                if let summary { StatusChip(summary) }
            }
        }
    }

    var body: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 10) {
                content.frame(maxWidth: .infinity, alignment: .leading)
                if let footer { HelpText(footer) }
            }
            .padding(6)
        } label: {
            header
        }
        .frame(maxWidth: .infinity)
    }
}
