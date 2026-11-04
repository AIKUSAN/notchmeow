import Combine
import CoreGraphics
import Foundation

// Draws a parent's kittens (`CatKittens.slots` says where): each is its parent's cat as a kitten (`CatPresets.kitten(of:)`) with its own engine and state badge, the parent's
// collar in the agent's colour, a happy blink while it leaves, and "+N" or "×N" labels. The app's kitten layers and the contact sheets draw through this one function, so what
// the sheets show is what the island draws. A kitten's coat is its parent's: a kitten's engine is never given `useCharacter` (it would make it an adult), and when the parent's coat
// changes the herd makes a new engine.

/// The engines of the kittens, one for each kitten ID. It belongs to one layer (one parent in one place).
@MainActor
final class CatKittenHerd: ObservableObject {
    private var engines: [String: (coat: String, engine: CatEngine)] = [:]
    /// Where the engines' dice come from: `Double.random` in the app, a seeded source on a contact sheet.
    var rand: () -> Double = { Double.random(in: 0..<1) }
    /// Whether the layer's last frame had nothing to draw. The layer sets it as it draws and reads it to stop asking for frames (`CatKittens.mayStop`).
    var lastFrameEmpty = false

    /// The kitten's engine, made on first sight and again when the parent's coat changes. `now` is the clock the engine reads (ms).
    func engine(_ id: String, parentCat: String, now: @escaping () -> Double, cfg: CatConfig? = nil) -> CatEngine {
        if let e = engines[id], e.coat == parentCat { return e.engine }
        let engine = CatEngine(CatPresets.kitten(of: CatPresets.byID(parentCat)), mini: true, now: now, rand: rand, cfg: cfg)
        engines[id] = (parentCat, engine)
        return engine
    }

    /// Forgets the engines of kittens that are gone.
    func keep(_ ids: Set<String>) {
        if engines.keys.contains(where: { !ids.contains($0) }) { engines = engines.filter { ids.contains($0.key) } }
    }
}

@MainActor
enum CatKittenDraw {
    /// Draws `slots` (from `CatKittens.slots`) for a parent whose head centre (or, for a pill, trailing edge and middle) is `origin`, in units of `unit` px. `advance` moves a
    /// kitten's engine on by a frame (the app reads the real clock, a contact sheet its own); `colour` is the agent's, worn as the collar in Settings' style.
    static func draw(_ cg: CGContext, _ slots: CatKittens.Slots, parentCat: String, origin: (x: Double, y: Double), unit: Double, colour: String?, dpr: Double,
                     herd: CatKittenHerd, now: @escaping () -> Double, cfg: CatConfig? = nil, advance: (CatEngine) -> Void) {
        herd.keep(Set(slots.shown.map(\.id)))
        for k in slots.shown {
            let e = herd.engine(k.id, parentCat: parentCat, now: now, cfg: cfg)
            e.setState((CatKittens.State(rawValue: k.state) ?? .working).catState)
            e.collar = colour
            advance(e)
            var options = CatDrawOptions(badge: true)
            options.collar = e.collarPaint(dpr: dpr)
            CatRenderer.draw(cg, e.look(), cx: origin.x + k.x * unit, cy: origin.y + k.y * unit, D: k.d * unit, options)
        }
        if let m = slots.moreAt {
            let text = "+\(slots.more)"
            // In the overview's rows the "+N" starts right of the last kitten (clear of its badge), on the row's line; elsewhere it sits at `moreAt`.
            if let left = CatIslandLayout.moreLabelLeft(slots), let last = slots.shown.last {
                label(cg, text, x: origin.x + left * unit + labelWidth(text, m.size * unit) / 2, y: origin.y + last.y * unit, size: m.size * unit)
            } else { label(cg, text, x: origin.x + m.x * unit, y: origin.y + m.y * unit, size: m.size * unit) }
        }
        if let l = slots.label { label(cg, l.text, x: origin.x + l.x * unit, y: origin.y + l.y * unit, size: l.size * unit) }
    }

    static func labelWidth(_ text: String, _ size: Double) -> Double { let sz = max(8, size); return Double(text.count) * sz * 0.62 + sz * 0.9 }

    /// A small dark pill with a number in it, centred on (x, y): the "+N" of kittens that do not fit and the "×N" of the pair.
    static func label(_ cg: CGContext, _ text: String, x: Double, y: Double, size: Double) {
        let sz = max(8, size), w = labelWidth(text, size), h = sz * 1.3
        cg.fill(CatDraw.roundRect(x - w / 2, y - h / 2, w, h, h / 2), CatDraw.rgb([42, 44, 49]))
        CatDraw.text(cg, text, x: x, y: y + 0.5, size: sz, bold: true, color: CatDraw.rgb([207, 208, 212]))
    }
}
