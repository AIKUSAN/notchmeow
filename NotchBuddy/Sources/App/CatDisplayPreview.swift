import SwiftUI
import QuartzCore

// Settings → Cat → Display: a small live picture of the compact notch in the chosen mode. It draws a sample island (`CatDisplaySample`: five pills, Claude Code
// working, Codex waiting for you) with the real cats of the real renderer, in the places the cast (`CatCast`) and the layout (`CatIslandLayout`) give them, so what it
// shows is what the notch will show. It draws only while it is `active` (the Settings window is on screen and the key window), like the other previews.

struct DisplayPreviewView: View {
    let display: CatDisplaySettings
    /// The Main cat: the character picked in Settings.
    let main: String
    let active: Bool
    let config: CatConfig
    @StateObject private var herd = DisplayPreviewHerd()

    /// The real compact island on a notch of 185 pt: 345 by 32 pt, drawn 1.3 times as big.
    static let island = (w: 345.0, h: 32.0), scale = 1.3

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active)) { timeline in
            Canvas { context, size in
                _ = timeline.date   // the Canvas redraws on every tick of the timeline
                let cast = CatDisplaySample.cast(display, main: main)
                context.withCGContext { cg in herd.draw(cg, cast: cast, config: config, dpr: Double(context.environment.displayScale)) }
            }
        }
        .frame(width: Self.island.w * Self.scale, height: Self.island.h * Self.scale)
        .accessibilityHidden(true)
    }
}

/// The preview's engines, one for each place a cat can be (the big cat, cat 2 and the four cells of the grid). A place keeps its engine when its coat changes.
@MainActor
final class DisplayPreviewHerd: ObservableObject {
    private var engines: [String: CatEngine] = [:]

    private func engine(_ slot: String, _ coat: String, _ config: CatConfig) -> CatEngine {
        let e = engines[slot] ?? CatEngine(CatPresets.byID(coat), now: { CACurrentMediaTime() * 1000 }, cfg: config, quiet: true)
        engines[slot] = e
        e.useCharacter(coat)
        return e
    }

    func draw(_ cg: CGContext, cast: CatCast.Result, config: CatConfig, dpr: Double) {
        let W = DisplayPreviewView.island.w, H = DisplayPreviewView.island.h, k = DisplayPreviewView.scale
        cg.saveGState()
        cg.scaleBy(x: k, y: k)
        cg.fill(CatDraw.roundRect(0, 0, W, H, 14), CatDraw.black(1))
        cg.fill(CatDraw.roundRect(80, 0, W - 160, H, 10), CatDraw.rgb([24, 25, 28]))   // the notch, a shade lighter than the island so the two ears can be seen
        func pill(_ id: String?) -> CatDisplaySample.Pill? { CatDisplaySample.pills.first { $0.id == id } }
        func cat(_ slot: String, _ coat: String, _ id: String?, cx: Double, cy: Double, d: Double, big: Bool) {
            let e = engine(slot, coat, config), state = pill(id)?.state ?? .idle
            e.setState(state)
            e.collar = big ? CatRules.bigCatCollar(colour: pill(id)?.color, state: state) : pill(id)?.color
            e.update(dt: CatEngine.frameDelta(now: CACurrentMediaTime(), last: e.lastTime))
            var options = CatDrawOptions(badge: big)
            if big { options.badgeSide = -1; options.earCeiling = 0 }   // never under the camera housing; the top of the island is the top of the screen
            if big { options.outfit = CatOutfitDraw.big(config.outfit, dpr: dpr * k) }   // the big cats wear the outfit (the owner's answer, 2026-10-14); the grid's pill cats stay bare
            options.collar = e.collarPaint(dpr: dpr * k)
            let laid = CatRenderer.draw(cg, e.look(), cx: cx, cy: cy, D: d, options)
            e.base = laid.base
            e.mouthPoint = laid.mouth
        }
        let xs = CatIslandLayout.compactX(cast.mode)
        cat("big", cast.big.cat, cast.big.pill, cx: xs[0], cy: H / 2, d: 20, big: true)
        if let second = cast.second { cat("second", second.cat, second.pill, cx: xs[1], cy: H / 2, d: 20, big: true) }
        for (i, p) in cast.pills.enumerated() {
            cat("grid\(i)", p.cat, p.pill, cx: W - 40 + (i % 2 == 1 ? 8 : -8), cy: H / 2 + (i < 2 ? -8 : 8), d: 12, big: false)
        }
        cg.restoreGState()
    }
}
