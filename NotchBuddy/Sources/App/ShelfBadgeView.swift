import SwiftUI

/// The badge: a small tray-coloured disc with the count, in the shelf's accent.
struct ShelfBadgeView: View {
    let count: Int
    var height: CGFloat = 32

    var body: some View {
        let k = ShelfBadge.scale(height: height)
        ZStack {
            Circle().fill(Color(hex: "#A5B4FC"))
            Text("\(count)")
                .font(.system(size: 9, weight: .bold).monospacedDigit())
                .foregroundColor(Color(hex: "#0D0E10"))
                .minimumScaleFactor(0.7)
        }
        .frame(width: ShelfBadge.diameter, height: ShelfBadge.diameter)
        .scaleEffect(k)
        .accessibilityLabel("Shelf, \(count) \(count == 1 ? "file" : "files")")
    }
}
