import CoreGraphics
import Foundation
import QuartzCore

// Draws the desktop cat (sub-project H): the big cat at full detail (whiskers, stripes, fur lines if they are on, realistic eyes: small eyes are a notch-only look below Ø28),
// its state badge, its collar in the working agent's colour, the music dance and its agent's kittens. The desktop window and the contact sheets draw through this one function, so
// what the sheets show is what the desktop draws. It only draws: the caller has already moved the engines on by a frame. Needs the app's drawing files and nothing of AppKit.

@MainActor
enum DesktopCatDraw {
    struct Scene {
        /// The head width in points.
        var d: Double
        /// The head centre in the context's coordinates (y down).
        var head: (x: Double, y: Double)
        /// The kittens' places (`DesktopCatTrip.kittenSlots`).
        var slots: CatKittens.Slots
        /// The coat the kittens are kittens of: the cat's own.
        var parentCat: String
        /// The working agent's colour: the collar, the kittens' collars. nil when the cat is idle.
        var colour: String?
        /// Pixels per point.
        var dpr: Double
    }

    /// Draws one frame. `advance` moves a kitten's engine on by a frame (the app reads the real clock, a contact sheet its own); `now` is the clock the kittens' engines read (ms).
    static func draw(_ cg: CGContext, _ engine: CatEngine, _ scene: Scene, herd: CatKittenHerd, now: @escaping () -> Double, cfg: CatConfig? = nil, advance: (CatEngine) -> Void) {
        var options = CatDrawOptions()
        options.fur = engine.cfg.furLines                       // Settings → Cat → Fur lines
        options.collar = engine.collarPaint(dpr: scene.dpr)     // Settings → Cat → Collar
        options.outfit = CatOutfitDraw.big(engine.cfg.outfit, dpr: scene.dpr)   // Settings → Cat → Wardrobe: the desktop cat is a big cat; its kittens (below) stay bare
        cg.saveGState()
        if engine.dancingLevel > 0.001 {
            CatEffects.applyDance(cg, level: engine.dancingLevel, seconds: CACurrentMediaTime(), pivotX: scene.head.x, pivotY: scene.head.y + scene.d * 0.45, size: scene.d / 2)
        }
        let layout = CatRenderer.draw(cg, engine.look(), cx: scene.head.x, cy: scene.head.y, D: scene.d, options)
        cg.restoreGState()
        engine.base = layout.base
        engine.mouthPoint = layout.mouth
        CatKittenDraw.draw(cg, scene.slots, parentCat: scene.parentCat, origin: scene.head, unit: scene.d, colour: scene.colour, dpr: scene.dpr, herd: herd, now: now, cfg: cfg, advance: advance)
    }
}
