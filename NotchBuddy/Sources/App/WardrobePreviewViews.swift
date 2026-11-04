import AppKit
import QuartzCore
import SwiftUI

// The wardrobe's two small cat views (sub-project I): a still tile and the live preview. Both draw a cat in the big-cat role wearing the outfit they are given. They know no store, so Settings'
// Wardrobe group and the Debug cat panel's Wardrobe section both use them.

/// A still cat in an outfit for a tile: drawn once, with no timeline and no engine, so 18 tiles cost nothing while Settings sits there.
struct WardrobeTileView: View {
    let coat: String
    /// The outfit to wear: an ID, or "none".
    let outfit: String

    var body: some View {
        Canvas { context, size in
            context.withCGContext { cg in
                var o = CatDrawOptions(tint: false, badge: false)
                o.outfit = CatOutfitDraw.big(outfit, dpr: Double(context.environment.displayScale), ceiling: 0)   // the canvas top is the line: a tall hat is shortened to it, not cut
                CatRenderer.draw(cg, CatLook(preset: CatPresets.byID(coat)), cx: Double(size.width) / 2, cy: Double(size.height) * 0.66, D: 34, o)
            }
        }
        .accessibilityHidden(true)
    }
}

/// The live preview: one silent engine on the store's `CatConfig`, drawn big, in the big-cat role. It draws only while `active`.
struct WardrobePreviewView: View {
    let coat: String
    let outfit: String
    let head: Double
    let active: Bool
    let config: CatConfig
    @StateObject private var engine: CatEngine

    init(coat: String, outfit: String, head: Double, active: Bool, config: CatConfig) {
        self.coat = coat; self.outfit = outfit; self.head = head; self.active = active; self.config = config
        _engine = StateObject(wrappedValue: CatEngine(CatPresets.byID(coat), now: { CACurrentMediaTime() * 1000 }, cfg: config))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active)) { timeline in
            Canvas { context, size in
                _ = timeline.date   // the Canvas redraws on every tick of the timeline
                engine.useCharacter(coat)
                engine.update(dt: CatEngine.frameDelta(now: CACurrentMediaTime(), last: engine.lastTime))
                var o = CatDrawOptions(badge: false)
                o.fur = config.furLines
                o.outfit = CatOutfitDraw.big(outfit, dpr: Double(context.environment.displayScale), ceiling: 0)   // the canvas top is the line: a tall hat is shortened to it, not cut
                context.withCGContext { cg in
                    CatRenderer.draw(cg, engine.look(), cx: Double(size.width) / 2, cy: Double(size.height) * 0.64, D: head, o)
                }
            }
        }
        .accessibilityHidden(true)
    }
}
