import CoreGraphics
import Foundation

@main
enum CatEffectsTests {
    typealias G = CatGeometry

    @MainActor static func layout(_ D: Double = 100) -> G.Layout {
        G.layout(CatPresets.byID("momo"), CatPose(), cx: 100, cy: 100, D: D, G.Options())
    }
    @MainActor static func cover(_ draw: (CGContext) -> Void) -> Int { Bitmap.coverage(Bitmap.render(200, 200, draw)) }

    @MainActor static func main() {
        let momo = CatPresets.byID("momo")

        CT.section("colours: the strings a preset holds")
        func comps(_ s: String) -> [Double] { CatDraw.color(s).components!.map(Double.init) }
        CT.checkJSON("#RRGGBB", got: comps("#FF8000"), want: [1, 128.0 / 255, 0, 1])
        CT.checkJSON("rgba(r,g,b,a)", got: comps("rgba(150,142,138,.6)"), want: [150.0 / 255, 142.0 / 255, 138.0 / 255, 0.6])
        CT.checkJSON("something unreadable is black", got: comps("nonsense"), want: [0, 0, 0, 1])
        CT.checkNear("an extra alpha multiplies", Double(CatDraw.color("rgba(0,0,0,.5)", alpha: 0.5).alpha), 0.25)
        CT.checkJSON("a mix of two colours", got: CatDraw.mix(CatDraw.color("#000000"), CatDraw.color("#FFFFFF"), 0.5).components!.map(Double.init), want: [0.5, 0.5, 0.5, 1])

        CT.section("text: centred, or starting or ending at x")
        func textBounds(_ anchor: CatDraw.Anchor) -> (left: Int, top: Int, right: Int, bottom: Int) {
            Bitmap.bounds(Bitmap.render(200, 60) { CatDraw.text($0, "Hello", x: 100, y: 30, size: 16, bold: false, color: CatDraw.white(1), anchor: anchor) }, 200)!
        }
        let c = textBounds(.center), l = textBounds(.left), r = textBounds(.right)
        CT.checkTrue("centred text straddles x = 100", c.left < 100 && c.right > 100)
        CT.checkTrue("left-anchored text starts at x", l.left >= 98 && l.left <= 102)
        CT.checkTrue("right-anchored text ends at x", r.right >= 98 && r.right <= 102)
        CT.checkTrue("upright, not mirrored: the glyphs sit around y = 30", c.top > 15 && c.bottom < 45)

        CT.section("the badge")
        let L = layout()
        var s = CatPose(); s.badgeS = 1
        let badgeL = G.layout(momo, s, cx: 100, cy: 100, D: 100, G.Options())
        let small = G.layout(momo, s, cx: 100, cy: 100, D: 20, G.Options())
        for kind in [CatBadge.dots, .bang, .question, .dot] {
            CT.checkTrue("\(kind) draws at full size", cover { CatEffects.drawBadge($0, kind, "#3B9EFF", badgeL, 0.3) } > 100)
            CT.checkTrue("\(kind) draws small", cover { CatEffects.drawBadge($0, kind, "#3B9EFF", small, 0.3) } > 5)
        }
        CT.checkTrue("a bang badge carries its '!' at full size only",
                     cover { CatEffects.drawBadge($0, .bang, "#F5A524", badgeL, 0) } != cover { CatEffects.drawBadge($0, .dot, "#F5A524", badgeL, 0) })
        CT.checkTrue("a hidden badge (scale 0) draws nothing", cover { CatEffects.drawBadge($0, .dots, "#3B9EFF", L, 0) } == 0)

        CT.section("particles: every kind, and nothing before it starts")
        func look(_ kind: CatParticleKind, age: Double) -> CatLook {
            var lk = CatLook(preset: momo)
            lk.particles = [CatParticle(kind: kind, x: 0, y: -0.5, vx: 0, vy: 0, age: age, life: 1.4, size: 0.2, rot: 0.4)]
            return lk
        }
        for kind in [CatParticleKind.heart, .star, .spark, .sweat, .dust, .hair, .z] {
            CT.checkTrue("\(kind) draws mid-life", cover { CatEffects.drawParticles($0, look(kind, age: 0.5), L) } > 5)
            CT.checkTrue("\(kind) waits while its age is negative", cover { CatEffects.drawParticles($0, look(kind, age: -0.1), L) } == 0)
        }

        CT.section("paws: the wave, and a paw drawn by hand")
        let wave = CatWave(now: 1000, start: 450, until: 1550)
        CT.check("no paws out, no paws", CatEffects.wavePaws(pawsOut: 0, wave: wave, rx: 50, ry: 40).count, 0)
        let waving = CatEffects.wavePaws(pawsOut: 1, wave: wave, rx: 50, ry: 40), resting = CatEffects.wavePaws(pawsOut: 1, wave: CatWave(now: 0, start: 0, until: 0), rx: 50, ry: 40)
        CT.checkTrue("the right paw rises when waving and shows its toe beans", waving[1].y < resting[1].y - 20 && waving[1].beans && !resting[1].beans)
        CT.checkTrue("a paw draws, with beans or with toe lines",
                     cover { cg in cg.translateBy(x: 100, y: 100); CatEffects.drawPaw(cg, momo, 50, CatPaw(x: 0, y: 0, k: 1, rot: 0, beans: true)) } > 50
                     && cover { cg in cg.translateBy(x: 100, y: 100); CatEffects.drawPaw(cg, momo, 50, CatPaw(x: 0, y: 0, k: 1, rot: 0, beans: false)) } > 50)
        CT.checkTrue("a paw that is barely out draws nothing", cover { cg in cg.translateBy(x: 100, y: 100); CatEffects.drawPaw(cg, momo, 50, CatPaw(x: 0, y: 0, k: 0.01, rot: 0, beans: false)) } == 0)

        CT.section("hairballs, and a refused file wrapped in fur")
        func ballLook(_ file: String?, age: Double = 0.5) -> CatLook {
            var lk = CatLook(preset: momo)
            lk.balls = [CatBall(x: 0.2, y: 0.8, vx: 0, vy: 0, rot: 0.3, age: age, life: 2.4, file: file, seed: 12345, floor: 1.12)]
            return lk
        }
        CT.checkTrue("a hairball draws", cover { CatEffects.drawBalls($0, ballLook(nil), L) } > 100)
        CT.checkTrue("a file in fur draws, and not the same as a hairball", cover { CatEffects.drawBalls($0, ballLook("EXE"), L) } != cover { CatEffects.drawBalls($0, ballLook(nil), L) })
        func ink(_ age: Double) -> Int { Bitmap.render(200, 200) { CatEffects.drawBalls($0, ballLook(nil, age: age), L) }.reduce(0) { $0 + Int($1) } }
        CT.checkTrue("it fades out over its last half second", ink(2.39) > 0 && ink(2.39) * 5 < ink(0.5))
        let again = Bitmap.render(200, 200) { CatEffects.drawBalls($0, ballLook("EXE"), L) }
        CT.checkTrue("the same ball draws the same strands every frame (seeded)", again == Bitmap.render(200, 200) { CatEffects.drawBalls($0, ballLook("EXE"), L) })

        CT.section("glow, the zoomies' trails, and the dance")
        var glow = CatLook(preset: momo); glow.glowColor = [59, 158, 255]; glow.glowAlpha = 0.4
        CT.checkTrue("a glow draws", cover { CatEffects.drawGlow($0, glow, L) } > 1000)
        glow.glowAlpha = 0.001
        CT.checkTrue("a glow that has faded draws nothing", cover { CatEffects.drawGlow($0, glow, L) } == 0)
        var fast = CatLook(preset: momo); fast.zoomVelocity = 3
        CT.checkTrue("a fast cat leaves afterimages and speed lines", cover { CatEffects.drawZoomTrails($0, fast, L) } > 200)
        fast.zoomVelocity = 1
        CT.checkTrue("a slow one does not", cover { CatEffects.drawZoomTrails($0, fast, L) } == 0)
        fast.zoomVelocity = 3
        CT.checkTrue("and neither does a tiny one (under Ø16)", cover { CatEffects.drawZoomTrails($0, fast, layout(12)) } == 0)
        var moved = false
        _ = Bitmap.render(10, 10) { ctx in
            let before = ctx.ctm
            CatEffects.applyDance(ctx, level: 0, seconds: 0.3, pivotX: 5, pivotY: 5, size: 10)
            CT.checkTrue("at level 0 the dance leaves the context alone", ctx.ctm == before)
            CatEffects.applyDance(ctx, level: 1, seconds: 0.3, pivotX: 5, pivotY: 5, size: 10)
            moved = ctx.ctm != before
        }
        CT.checkTrue("at level 1 it hops and sways around the pivot", moved)

        CT.section("the music bob: the head nods and the ears bounce on the 112 BPM beat of the dance")
        let beatS = 60.0 / CatDance.bpm
        CT.check("the beat is 112 beats a minute", CatDance.bpm, 112)
        CT.checkNear("the curves repeat every beat: a hop", CatDance.curves(0.123).hop, CatDance.curves(0.123 + beatS).hop)
        CT.checkNear("and the landing", CatDance.curves(0.123).land, CatDance.curves(0.123 + 3 * beatS).land)
        CT.checkNear("the cat is on the ground on the beat (no hop, a full landing)", CatDance.curves(5 * beatS).hop, 0)
        CT.checkNear("and at the top half a beat later (the landing has gone)", CatDance.curves(5.5 * beatS).land, 0)
        let rest = CatPose()
        CT.checkTrue("at level 0 the pose comes back as it went in", CatDance.pose(rest, level: 0, seconds: 0.4) == rest && CatDance.pose(rest, level: 0.0005, seconds: 0.4) == rest)
        let landing = CatDance.pose(rest, level: 1, seconds: 5 * beatS), top = CatDance.pose(rest, level: 1, seconds: 5.5 * beatS)
        CT.checkTrue("on the landing the head nods down and the ears flop outward", landing.pitch < -0.1 && landing.earL > 0.15 && landing.earR == landing.earL)
        CT.checkTrue("at the top of the hop the head tips back a little and the ears stand taller", top.pitch > 0.05 && top.earU > 1.1 && top.earL == 0)
        CT.checkTrue("half the level moves the pose half as far", abs(CatDance.pose(rest, level: 0.5, seconds: 5 * beatS).pitch - landing.pitch / 2) < 1e-12)
        var worst = 0.0, finite = true
        for i in 0..<2000 {
            let q = CatDance.pose(rest, level: Double(i % 11) / 10, seconds: Double(i) * 0.0173)
            worst = max(worst, abs(q.pitch), abs(q.earL), abs(q.earU - 1))
            finite = finite && [q.pitch, q.earL, q.earR, q.earU].allSatisfy(\.isFinite)
        }
        CT.checkTrue("it stays small and finite at every moment and level (largest move \(String(format: "%.2f", worst)))", finite && worst < 0.3)
        var tilted = rest; tilted.tilt = 0.3; tilted.earF = 0.5; tilted.yaw = 0.4
        let moved2 = CatDance.pose(tilted, level: 1, seconds: 5 * beatS)
        CT.checkTrue("everything else about the pose is left alone", moved2.tilt == 0.3 && moved2.earF == 0.5 && moved2.yaw == 0.4 && moved2.sx == 1 && moved2.oy == 0)
        CT.finish()
    }
}
