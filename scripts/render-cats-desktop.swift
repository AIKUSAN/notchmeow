import CoreGraphics
import Foundation

// The desktop cat's sheets (sub-project H), part of scripts/render-cats.sh: a mock desktop with the cat at each size, the alert flight as a strip of frames, and the bench. They draw
// through `DesktopCatDraw` and the layout, the trip and the pacer of the app, so what the sheets show is what the desktop draws. Run through scripts/render-cats.sh (see the list at the top
// of scripts/render-cats.swift).

extension RenderCats {

    /// A mock desktop in points: a wallpaper, a menu bar, one app window (the click-through shape is easy to see against it) and, for the flight, the notch.
    @MainActor static func mockDesktop(_ cg: CGContext, x: Double, y: Double, w: Double, h: Double, notch: Bool = false) {
        cg.saveGState()
        cg.clip(to: CGRect(x: x, y: y, width: w, height: h))
        let grad = CGGradient(colorsSpace: CGColorSpace(name: CGColorSpace.sRGB)!, colors: [CatDraw.rgb([38, 52, 92]), CatDraw.rgb([120, 74, 120])] as CFArray, locations: [0, 1])!
        cg.drawLinearGradient(grad, start: CGPoint(x: x, y: y), end: CGPoint(x: x + w, y: y + h), options: [])
        cg.fill(CatDraw.roundRect(x + 24, y + h * 0.42, w * 0.46, h * 0.46, 8), CatDraw.white(0.88))
        cg.fill(CatDraw.roundRect(x + 24, y + h * 0.42, w * 0.46, 20, 8), CatDraw.white(0.7))
        cg.fill(CatDraw.roundRect(x, y, w, 24, 0), CatDraw.black(0.45))
        if notch { cg.fill(CatDraw.roundRect(x + w / 2 - 58, y - 12, 116, 36, 12), CatDraw.black(1)) }
        cg.restoreGState()
    }

    /// The window the app would make around a cat at `head`, dashed, and (with `shapes`) the body that takes the mouse in green. `badge` says whether the cat draws its badge
    /// there: the app takes the mouse on the badge only while it does (`DesktopCatController`, `engine.badge != nil`).
    @MainActor static func drawFrame(_ cg: CGContext, head: (x: Double, y: Double), d: Double, slots: CatKittens.Slots, shapes: Bool, badge: Bool) {
        let f = DesktopCatLayout.frame(d: d, slots: slots)
        cg.saveGState()
        cg.setStrokeColor(CatDraw.white(0.55)); cg.setLineWidth(1); cg.setLineDash(phase: 0, lengths: [4, 3])
        cg.stroke(CGRect(x: head.x - f.headX, y: head.y - f.headY, width: f.w, height: f.h))
        cg.restoreGState()
        guard shapes else { return }
        var p = -f.headY
        while p < f.h - f.headY {
            var q = -f.headX
            while q < f.w - f.headX {
                if DesktopCatLayout.hits(DesktopSpot(x: q, y: p), d: d, slots: slots, badge: badge) { cg.fill(CatDraw.roundRect(head.x + q, head.y + p, 2, 2, 0), CatDraw.rgb([60, 220, 120], 0.35)) }
                q += 2
            }
            p += 2
        }
    }

    /// Kittens of every state for the sheets.
    static func sheetKittens(_ n: Int) -> [CatKittens.Kitten] {
        (0..<n).map { CatKittens.Kitten(id: "k\($0)", state: [.approval, .searching, .working][$0 % 3], born: 0, last: 0) }
    }

    /// A desktop cat on a mock desktop: a big cat on a fake clock, settled for 1.5 s, then drawn by the one function the app draws with.
    @MainActor static func drawDesktopCat(_ cg: CGContext, coat: String, state: CatState, d: Double, head: (x: Double, y: Double), kittens: Int, side: Int, colour: String?, badge: Bool, frames: Int = 90, emote: String? = nil, shapes: Bool = false) {
        let (e, clock, _) = scene(CatPresets.byID(coat), profile: "playful", D: d, state: state)
        e.collar = colour
        e.cfg.outfit = sheetOutfit   // `--outfit`: the desktop cat is a big cat; its kittens stay bare
        let rng = CatRNG(seed: 5), herd = CatKittenHerd()
        herd.rand = { rng.next() }
        let slots = DesktopCatTrip.kittenSlots(sheetKittens(kittens), side: side)
        let scratch = Sheet(width: 4, height: 4, scale: 1).cg
        let sceneValue = DesktopCatDraw.Scene(d: d, head: head, slots: slots, parentCat: coat, colour: colour, dpr: 2)
        if let emote { e.emote(emote) }
        for _ in 0..<frames {
            clock.t += 1000.0 / 60
            e.update(dt: 1.0 / 60)
            DesktopCatDraw.draw(scratch, e, sceneValue, herd: herd, now: { clock.t }) { $0.update(dt: 1.0 / 60) }
        }
        drawFrame(cg, head: head, d: d, slots: slots, shapes: shapes, badge: badge)
        DesktopCatDraw.draw(cg, e, sceneValue, herd: herd, now: { clock.t }) { $0.update(dt: 1.0 / 60) }
    }

    /// The three sizes on a mock desktop, with and without kittens, and one in the right half of its screen (its kittens on its left).
    @MainActor static func desktopSheet(_ a: Args) -> Sheet {
        let pw = 400.0, ph = 330.0, cols = 4.0, rows = 2.0, coat = a.cats.first ?? "shrimpy"
        let sheet = Sheet(width: pw * cols, height: ph * rows + 28, scale: a.scale)
        let labels = ["Small Ø48", "Medium Ø64", "Large Ø96", "Medium, right half"]
        for (ci, size) in [DesktopSize.small, .medium, .large, .medium].enumerated() {
            for row in 0..<2 {
                let ox = Double(ci) * pw, oy = 28 + Double(row) * ph
                mockDesktop(sheet.cg, x: ox + 6, y: oy + 6, w: pw - 12, h: ph - 12)
                let right = ci == 3
                let head = (x: ox + (right ? pw - 150 : 190), y: oy + 150)
                drawDesktopCat(sheet.cg, coat: coat, state: row == 0 ? .idle : .working, d: size.d, head: head, kittens: row == 0 ? 0 : (ci == 1 ? 5 : 3), side: right ? -1 : 1, colour: row == 0 ? nil : "#E07950", badge: row == 1, shapes: a.shapes)
                if row == 0 { CatDraw.text(sheet.cg, labels[ci], x: ox + pw / 2, y: 14, size: 12, bold: true, color: CatDraw.white(0.8)) }
            }
        }
        return sheet
    }

    /// The alert flight as a strip of frames: the surprised cat on the desktop, then the arc to the notch at 0, 20, 40, 60, 80 and 100 %.
    @MainActor static func flightSheet(_ a: Args) -> Sheet {
        let pw = 300.0, ph = 330.0, n = 7.0, coat = a.cats.first ?? "shrimpy", d = DesktopSize.medium.d
        let sheet = Sheet(width: pw * n, height: ph + 28, scale: a.scale)
        let notch = DesktopSpot(x: pw / 2 + 56, y: 56), desk = DesktopSpot(x: pw - 70, y: 230)
        let flight = DesktopCatTrip.Flight(from: desk, to: notch, dir: .in, startMs: 0)
        for i in 0..<Int(n) {
            let ox = Double(i) * pw, oy = 28.0
            mockDesktop(sheet.cg, x: ox + 4, y: oy + 4, w: pw - 8, h: ph - 8, notch: true)
            // the arc, dotted, from the desktop spot to the notch
            for k in 0...30 {
                let p = flight.position(at: Double(k) / 30 * DesktopCatTrip.flightMs)
                sheet.cg.fill(CatDraw.circle(ox + p.x, oy + p.y, 1.5), CatDraw.white(0.5))
            }
            let t = i == 0 ? 0 : Double(i - 1) / 5
            let p = flight.position(at: t * DesktopCatTrip.flightMs)
            drawDesktopCat(sheet.cg, coat: coat, state: .approval, d: d, head: (ox + p.x, oy + p.y), kittens: 0, side: 1, colour: "#E07950", badge: true, frames: i == 0 ? 20 : 20 + i * 4, emote: "surprised")
            CatDraw.text(sheet.cg, i == 0 ? "alert: surprised" : "\(Int(t * 100)) %", x: ox + pw / 2, y: 14, size: 12, bold: true, color: CatDraw.white(0.8))
        }
        return sheet
    }

    /// The file catch as a strip of frames: the cat on its desktop spot, a file dragged to the notch (the cat is surprised), the arc in at 50 %, the catch at the notch, the arc back at 50 %, and the
    /// cat on its spot again. Each frame is one phase of the trip. The desktop cat is drawn while the phase is `drawn`, the catch's cat at the notch while the cat is `catchReady` (the island draws
    /// none of its own before that), and the sheet counts the cats in every frame and fails if a frame shows other than one.
    @MainActor static func desktopCatchSheet(_ a: Args) -> Sheet {
        let pw = 300.0, ph = 330.0, coat = a.cats.first ?? "shrimpy", d = DesktopSize.medium.d
        let notch = DesktopSpot(x: pw / 2 + 56, y: 56), desk = DesktopSpot(x: pw - 70, y: 230)
        let inbound = DesktopCatTrip.Flight(from: desk, to: notch, dir: .in, startMs: 0), outbound = DesktopCatTrip.Flight(from: notch, to: desk, dir: .out, startMs: 0)
        let half = 0.5 * DesktopCatTrip.flightMs
        let frames: [(phase: DesktopPhase, label: String, head: DesktopSpot?, file: Bool)] = [
            (.onDesktop, "on its spot", desk, false),
            (.retracting, "a file is dragged in: surprised", desk, true),
            (.retracting, "flying to the notch, 50 %", inbound.position(at: half), true),
            (.atNotchForAlert, "the catch, at the notch", nil, true),
            (.returning, "flying back, 50 %", outbound.position(at: half), false),
            (.onDesktop, "back on its spot", desk, false),
        ]
        let sheet = Sheet(width: pw * Double(frames.count), height: ph + 28, scale: a.scale)
        for (i, f) in frames.enumerated() {
            let ox = Double(i) * pw, oy = 28.0
            mockDesktop(sheet.cg, x: ox + 4, y: oy + 4, w: pw - 8, h: ph - 8, notch: true)
            if f.file { sheet.cg.fill(CatDraw.roundRect(ox + notch.x + 26, oy + notch.y + 30, 16, 20, 3), CatDraw.white(0.92)) }
            var cats = 0
            if f.phase.drawn, let p = f.head {
                drawDesktopCat(sheet.cg, coat: coat, state: .working, d: d, head: (ox + p.x, oy + p.y), kittens: 0, side: 1, colour: "#E07950", badge: true, emote: i == 1 ? "surprised" : nil)
                cats += 1
            }
            if DesktopCatTrip.catchReady(f.phase) {
                drawDesktopCat(sheet.cg, coat: coat, state: .idle, d: d * 0.8, head: (ox + notch.x, oy + notch.y), kittens: 0, side: 1, colour: nil, badge: false, emote: "happy")
                cats += 1
            }
            if (f.head != nil) != f.phase.drawn || cats != 1 {
                FileHandle.standardError.write(Data("frame \(i + 1) (\(f.phase.rawValue)) shows \(cats) cat(s)\n".utf8))
                exit(1)
            }
            CatDraw.text(sheet.cg, f.label, x: ox + pw / 2, y: 14, size: 12, bold: true, color: CatDraw.white(0.8))
            CatDraw.text(sheet.cg, "cats on screen: \(cats)", x: ox + pw / 2, y: oy + ph - 14, size: 11, bold: false, color: CatDraw.white(0.9))
        }
        return sheet
    }

    /// The desktop cat's cost: update and draw at each size, and what that costs at the frame rate the rule picks for what the cat is doing. Idle and awake (5 fps, no kittens: kittens
    /// exist only while their agent works, which is 20 fps) must stay under 1 % of a core; asleep is about nothing; the busy rates are reported.
    @MainActor static func benchDesktop() {
        func measure(_ size: DesktopSize, state: CatState, kittens: Int) -> (avg: Double, p95: Double) {
            let sheet = Sheet(width: 400, height: 300, scale: 2)
            let (e, clock, _) = scene(CatPresets.byID("shrimpy"), profile: "playful", D: size.d, state: state)
            e.collar = state == .idle || state == .sleeping ? nil : "#E07950"
            e.cfg.outfit = sheetOutfit   // `--outfit`: the cost with an outfit on
            let rng = CatRNG(seed: 5), herd = CatKittenHerd()
            herd.rand = { rng.next() }
            let value = DesktopCatDraw.Scene(d: size.d, head: (150, 150), slots: DesktopCatTrip.kittenSlots(sheetKittens(kittens), side: 1), parentCat: "shrimpy", colour: "#E07950", dpr: 2)
            var times: [Double] = []
            for f in 0..<600 {
                let start = cpuNow()
                sheet.cg.clear(CGRect(x: 0, y: 0, width: 400, height: 300))
                clock.t += 1000.0 / 60
                e.update(dt: 1.0 / 60)
                DesktopCatDraw.draw(sheet.cg, e, value, herd: herd, now: { clock.t }) { $0.update(dt: 1.0 / 60) }
                if f >= 60 { times.append((cpuNow() - start) * 1000) }
            }
            times.sort()
            return (times.reduce(0, +) / Double(times.count), times[Int(Double(times.count) * 0.95)])
        }
        func pct(_ ms: Double, _ fps: Double) -> Double { DesktopCatPacer.coreShare(msPerFrame: ms, fps: fps) * 100 }
        var failed = false
        for size in DesktopSize.allCases {
            let idle = measure(size, state: .idle, kittens: 0), withKittens = measure(size, state: .idle, kittens: 3)
            let asleep = measure(size, state: .sleeping, kittens: 0), busy = measure(size, state: .working, kittens: 3)
            let ok = pct(idle.avg, DesktopCatTrip.fpsIdle) < 1
            if !ok { failed = true }
            print(String(format: "Ø%.0f idle, no kittens: %.2f ms a frame, %.0f fps: %.2f %% of a core (held, under 1 %%: %@)", size.d, idle.avg, DesktopCatTrip.fpsIdle, pct(idle.avg, DesktopCatTrip.fpsIdle), ok ? "yes" : "NO"))
            print(String(format: "Ø%.0f %.0f fps with three kittens: %.2f ms a frame (p95 %.2f): %.2f %% of a core (reported, not held)", size.d, DesktopCatTrip.fpsIdle, withKittens.avg, withKittens.p95, pct(withKittens.avg, DesktopCatTrip.fpsIdle)))
            print(String(format: "Ø%.0f also: asleep %.1f fps %.2f %%; working with three kittens %.0f fps %.2f %%; in motion %.0f fps %.2f %%", size.d, DesktopCatTrip.fpsAsleep, pct(asleep.avg, DesktopCatTrip.fpsAsleep),
                         DesktopCatTrip.fpsActive, pct(busy.avg, DesktopCatTrip.fpsActive), DesktopCatTrip.fpsMotion, pct(busy.avg, DesktopCatTrip.fpsMotion)))
        }
        print(failed ? "FAIL: a size costs 1 % of a core or more while idle and awake" : "ok: idle and awake is under 1 % of a core at every size; hidden, home and the notch's folded island draw nothing (0 fps)")
        if failed { exit(1) }
    }
}
