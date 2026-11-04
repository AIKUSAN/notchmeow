import SwiftUI

/// The hover glow's drawing (rules: `IslandGlow`): an angular gradient of `Theme.Glow` stroked along `shape`, once sharp-ish and once blurred wide for the halo, turning slowly. The island
/// puts it in the tree only while the glow is shown, so `TimelineView` runs only then (30 frames a second, none under Reduce Motion), and the fade is the view's own insertion and removal.
struct IslandGlowView<S: Shape>: View {
    let shape: S
    /// A fixed angle (degrees) instead of the clock's: for the contact sheet (`scripts/render-glow.sh`), which draws one still frame. The island never sets it.
    var fixedAngle: Double? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var colors: [Color] {
        [Theme.Glow.blue, Theme.Glow.purple, Theme.Glow.pink, Theme.Glow.orange, Theme.Glow.magenta, Theme.Glow.blue].map { Color(hex: $0) }
    }

    /// How far the halo spills past the outline (pt): the blur reaches about twice its radius, plus the edge's own width.
    private var bleed: CGFloat { CGFloat(IslandGlow.haloBlur * 2 + IslandGlow.lineWidth) }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / IslandGlow.framesPerSecond, paused: reduceMotion)) { timeline in
            let gradient = AngularGradient(colors: colors, center: .center,
                                           angle: .degrees(fixedAngle ?? IslandGlow.angle(at: timeline.date.timeIntervalSinceReferenceDate, reduceMotion: reduceMotion)))
            ZStack {
                shape.stroke(gradient, lineWidth: IslandGlow.lineWidth).blur(radius: IslandGlow.haloBlur).opacity(IslandGlow.haloOpacity)
                shape.stroke(gradient, lineWidth: IslandGlow.lineWidth).blur(radius: IslandGlow.edgeBlur)
            }
            // Rasterised through Metal (the wide blur is not reproduced by the offscreen `cacheDisplay` render of the contact sheet without it). The raster is cut at its own bounds, so it gets a margin
            // that holds the halo's spill, and the negative padding gives the island's own size back: the outline stays exactly where the island's is.
            .padding(bleed)
            .drawingGroup()
            .padding(-bleed)
        }
        .allowsHitTesting(false)
    }
}
