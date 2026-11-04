import SwiftUI

// A group of buttons or chips laid on one line when they fit, else on as many lines as needed. Every child is measured at its ideal size and `.fixedSize()`, so a button label is
// never cut ("Install hooks" is never "Install h…"); a child wider than the line gets a line of its own.

struct WrapRow<Content: View>: View {
    let spacing: CGFloat, lineSpacing: CGFloat
    let content: Content
    init(spacing: CGFloat = 8, lineSpacing: CGFloat = 6, @ViewBuilder content: () -> Content) {
        self.spacing = spacing; self.lineSpacing = lineSpacing; self.content = content()
    }

    var body: some View { WrapLayout(spacing: spacing, lineSpacing: lineSpacing) { content.fixedSize() } }
}

private struct WrapLayout: Layout {
    let spacing: CGFloat, lineSpacing: CGFloat

    private struct Placed { var index: Int; var origin: CGPoint; var size: CGSize }

    /// Flows the children left to right inside `width`; returns where each goes and the size of the whole.
    private func flow(_ subviews: Subviews, width: CGFloat) -> (placed: [Placed], size: CGSize) {
        var placed: [Placed] = []
        var x: CGFloat = 0, y: CGFloat = 0, lineHeight: CGFloat = 0, used: CGFloat = 0
        var line: [Int] = []
        // Centres the finished line's children on its tallest one.
        func closeLine() {
            for i in line { placed[i].origin.y = y + (lineHeight - placed[i].size.height) / 2 }
            line.removeAll()
        }
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                closeLine()
                y += lineHeight + lineSpacing
                x = 0; lineHeight = 0
            }
            placed.append(Placed(index: index, origin: CGPoint(x: x, y: y), size: size))
            line.append(placed.count - 1)
            x += size.width + spacing
            used = max(used, x - spacing)
            lineHeight = max(lineHeight, size.height)
        }
        closeLine()
        return (placed, CGSize(width: used, height: placed.isEmpty ? 0 : y + lineHeight))
    }

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        flow(subviews, width: proposal.width ?? .infinity).size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for p in flow(subviews, width: bounds.width).placed {
            subviews[p.index].place(at: CGPoint(x: bounds.minX + p.origin.x, y: bounds.minY + p.origin.y), anchor: .topLeading, proposal: ProposedViewSize(p.size))
        }
    }
}
