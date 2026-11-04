import SwiftUI

// The Shelf half of the drop view (sub-project G1), drawn over the upload canvas while files are dragged over the notch. It is a layer on top of the canvas and nothing else: every pixel it
// draws is in the right half (x from 320 on) of the 640 x 176 island, so the Ask half is the canvas as it ships. scripts/render-shelf.sh --ask-check proves it.

struct ShelfDropLayer: View {
    /// The half the pointer is over; the half lights up over Shelf.
    let half: DropHalf

    static let size = CGSize(width: 640, height: 176)
    /// What the layer covers: the right half of the canvas's card (x 10 to 630, y 42 to 166), 2 pt inside it so that the canvas's own dashed border stays. It starts 1 pt right of the centre line (the rasteriser
    /// bleeds a few percent of alpha into the pixel beside an edge), so no pixel left of x = 320 is drawn.
    static let cover = CGRect(x: 321, y: 44, width: 307, height: 120)
    static let accent = Color(hex: "#A5B4FC")

    private var lit: Bool { half == .shelf }
    private var shape: UnevenRoundedRectangle {
        UnevenRoundedRectangle(topLeadingRadius: 0, bottomLeadingRadius: 0, bottomTrailingRadius: 18, topTrailingRadius: 18)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            // The card's colour over the canvas's drop text and chips, whose right part reaches past the centre line.
            shape.fill(Color(red: 0.051, green: 0.055, blue: 0.063))
                .frame(width: Self.cover.width, height: Self.cover.height)
                .offset(x: Self.cover.minX, y: Self.cover.minY)
            shape.fill(lit ? Self.accent.opacity(0.12) : Color.white.opacity(0.03))
                .frame(width: Self.cover.width, height: Self.cover.height)
                .offset(x: Self.cover.minX, y: Self.cover.minY)
            // The centre line, at the cover's edge.
            Rectangle().fill(Color.white.opacity(lit ? 0.0 : 0.10))
                .frame(width: 1, height: Self.cover.height - 12)
                .offset(x: Self.cover.minX, y: Self.cover.minY + 6)
            if lit {
                shape.strokeBorder(Self.accent.opacity(0.7), style: StrokeStyle(lineWidth: 1.5, dash: [6, 5]))
                    .frame(width: Self.cover.width, height: Self.cover.height)
                    .offset(x: Self.cover.minX, y: Self.cover.minY)
            }
            VStack(spacing: 5) {
                Image(systemName: "tray.and.arrow.down.fill")
                    .font(.system(size: 24, weight: .regular))
                    .foregroundColor(lit ? Self.accent : Color(hex: "#8E939C"))
                Text("Shelf")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(Color(hex: "#D5D7DB"))
                Text("Keep it here for later")
                    .font(.system(size: 11, weight: .regular))
                    .foregroundColor(Color(hex: "#8E939C"))
            }
            .frame(width: Self.cover.width, height: Self.cover.height)
            .offset(x: Self.cover.minX, y: Self.cover.minY)
        }
        .frame(width: Self.size.width, height: Self.size.height, alignment: .topLeading)
        .animation(.easeOut(duration: 0.15), value: half)
        .allowsHitTesting(false)
    }
}
