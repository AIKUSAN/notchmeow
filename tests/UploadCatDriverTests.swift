import Foundation

@main
enum UploadCatDriverTests {
    static func num(_ x: Any?) -> Double { (x as! NSNumber).doubleValue }

    /// A frame of the upload sequence with only the fields the cat reads.
    static func frame(_ t: Double, hover: Bool = false, dropped: Bool = false, refused: Bool = false, lookX: Double = 0, lookY: Double = 0) -> USFrame {
        var f = USFrame()
        f.t = t; f.zoneOver = hover; f.dropped = dropped; f.refused = refused; f.lookX = lookX; f.lookY = lookY
        if refused { f.progEnd = USC.T_COUGH_END }
        return f
    }

    @MainActor static func main() {
        CT.section("which files the cat coughs up: the app's own refusal rule, decided at the drop")
        let ai = CT.fixture("attachment-cases.json", dir: "ai")
        let reject = ai["rejectExtensions"] as! [String], limit = Int(num(ai["maxFileBytes"]))
        CT.check("25 MB is 26,214,400 bytes", limit, 26_214_400)
        for e in reject {
            CT.checkTrue("\(e): an app, an archive, a disk image or a video, in lower and in upper case", CatFileRule.refused(ext: e, size: 1) && CatFileRule.refused(ext: e.uppercased(), size: 1))
        }
        for e in ["pdf", "txt", "swift", "docx", "png", "jpg", "html", "md", "", "bin", "dat"] {
            CT.checkTrue("\"\(e)\" is taken at 0 bytes and at 1 KB (a binary file with no known extension fails later, with no hairball)", !CatFileRule.refused(ext: e, size: 0) && !CatFileRule.refused(ext: e, size: 1000))
        }
        CT.checkTrue("a file of exactly 25 MB is taken", !CatFileRule.refused(ext: "pdf", size: limit))
        CT.checkTrue("one byte more is refused, whatever it is", CatFileRule.refused(ext: "pdf", size: limit + 1) && CatFileRule.refused(ext: "", size: limit + 1))
        CT.checkTrue("a size that is not a size (negative) is not refused", !CatFileRule.refused(ext: "pdf", size: -5))
        CT.check("the label is the extension in capitals", CatFileRule.label(for: "setup.exe"), "EXE")
        CT.check("the last extension of an archive", CatFileRule.label(for: "archive.tar.gz"), "GZ")
        CT.check("four letters at most", CatFileRule.label(for: "site.webarchive"), "WEBA")
        CT.check("a file with no extension is FILE", CatFileRule.label(for: "Makefile"), "FILE")

        // One cat on a fake clock, for a taken file and for a refused one.
        final class NoteLog { var notes: [String] = [] }
        func scene(_ seed: UInt32) -> (e: CatEngine, d: UploadCatDriver, clock: FakeClock, notes: NoteLog) {
            let clock = FakeClock(), rng = CatRNG(seed: seed), log = NoteLog(), p = CatPresets.byID("shrimpy")
            let e = CatEngine(p, now: { clock.t }, rand: { rng.next() }, cfg: CatConfig(), quiet: true)
            e.onNote = { log.notes.append($1) }
            let L = CatGeometry.layout(p, e.s, cx: 0, cy: 0, D: 2 * p.rx)
            e.base = L.base; e.mouthPoint = L.mouth
            return (e, UploadCatDriver(engine: e), clock, log)
        }
        let (e, d, clock, notes) = scene(3)
        func run(_ frames: Int, _ f: @autoclosure () -> USFrame, file: String = "notes.pdf") { for _ in 0..<frames { clock.t += 1000.0 / 60; d.follow(f(), file: file) } }

        CT.section("1. a file hovers: the mouth opens wide and the eyes widen")
        run(40, frame(1.6, hover: true))
        CT.checkTrue("the cat is catching", e.catching)
        CT.check("with wide eyes", e.eyeShape(), CatEye.wide)
        CT.checkTrue("and the mouth is open (spring settled near 0.55)", abs(e.slotH - 0.55) < 0.05)

        CT.section("the drag leaves the island: the cat relaxes")
        run(30, frame(1.6, hover: false))
        CT.checkTrue("not catching", !e.catching)
        CT.checkTrue("the mouth closes", e.slotH < 0.05)

        CT.section("2. the drop: the mouth snaps wider")
        run(20, frame(1.9, hover: true))
        run(30, frame(USC.T_DROP + 0.1, hover: true, dropped: true))
        CT.checkTrue("still catching, and wider than while hovering (near 1.05)", e.catching && abs(e.slotH - 1.05) < 0.08)

        CT.section("3. the file arrives: a gulp with a squash, then a chew with happy eyes")
        run(1, frame(USC.T_SUCK_END + 0.01, dropped: true))
        CT.checkTrue("the catch is over", !e.catching)
        CT.checkTrue("a chew has started", e.chewUntil > e.chewStart && e.chewUntil - e.chewStart == 850)
        CT.check("with happy eyes", e.eyeShape(), CatEye.happy)
        CT.checkTrue("and a squash (the cat is flatter within a few frames)", { run(3, frame(USC.T_SUCK_END + 0.1, dropped: true)); return e.s.sy < 0.95 || e.s.sx > 1.05 }())
        let arrivals = notes.notes.filter { $0 == "emote:happy" }.count
        run(5, frame(USC.T_SUCK_END + 0.2, dropped: true))
        CT.check("the arrival happens once, not on every frame", e.chewUntil - e.chewStart, 850)
        CT.checkTrue("and a taken file is never coughed up", !notes.notes.contains("hairball"))

        CT.section("the upload finishes: one happy emote")
        var f = frame(USC.T_PROG_START + 2.5, dropped: true); f.progEnd = USC.T_PROG_START + 2.4
        run(3, f)
        CT.check("the cat is happy about it, once", notes.notes.filter { $0 == "emote:happy" }.count, arrivals + 1)

        CT.section("a new drag starts over: it opens wide again")
        run(40, frame(1.6, hover: true))
        CT.checkTrue("catching again", e.catching && abs(e.slotH - 0.55) < 0.06)

        CT.section("the cat follows the pointer (the sequence's look is positive down, the engine's positive up)")
        run(1, frame(1.6, hover: true, lookX: 0.4, lookY: 0.5))
        CT.checkNear("looks across", e.lookX, 0.4); CT.checkNear("and down", e.lookY, -0.5)

        CT.section("a refused file: caught like any file, then the cat gags and coughs it up, with no chew and no celebration")
        let (r, rd, rclock, rnotes) = scene(5)
        func runR(_ frames: Int, _ f: @autoclosure () -> USFrame) { for _ in 0..<frames { rclock.t += 1000.0 / 60; rd.follow(f(), file: "setup.exe") } }
        runR(40, frame(1.6, hover: true))
        CT.checkTrue("1. it opens wide while the file hovers, like any file", r.catching && abs(r.slotH - 0.55) < 0.05 && r.eyeShape() == .wide)
        runR(30, frame(USC.T_DROP + 0.1, dropped: true, refused: true))
        CT.checkTrue("2. it snaps wider on the drop, like any file", r.catching && abs(r.slotH - 1.05) < 0.08)
        runR(1, frame(USC.T_SUCK_END + 0.01, dropped: true, refused: true))
        CT.checkTrue("3. at the arrival it does not gulp or chew: nothing is chewed and the eyes are not happy", !r.catching && r.chewUntil == 0 && r.eyeShape() != .happy)
        var ball: String?
        for i in 0..<Int((USC.COUGH_LEAD_S + USC.HAIRBALL_S) * 60 + 30) {
            rclock.t += 1000.0 / 60
            rd.follow(frame(USC.T_SUCK_END + 0.2 + Double(i) / 60, dropped: true, refused: true), file: "setup.exe")
            if let b = r.balls.first { ball = b.file }
        }
        CT.check("4. it coughs up one hairball", rnotes.notes.filter { $0 == "hairball" }.count, 1)
        CT.check("   with the file in its fur, labelled EXE", ball, "EXE")
        CT.checkTrue("   and it is never happy about it, even long after the progress would have ended", !rnotes.notes.contains("emote:happy"))
        runR(40, frame(1.6, hover: true))
        CT.checkTrue("a new drag after a refused drop starts over: open wide again", r.catching && abs(r.slotH - 0.55) < 0.06)

        CT.section("the sequence of a refused file: no bar, no check mark, no green wash, and the choose view after the hairball")
        let seq = UploadSequenceEngine.shared
        seq.enterZone(x: 300, y: 80)
        seq.performDrop(uploadDuration: 2.4, refused: true)
        func at(_ afterDrop: Double) -> USFrame { seq.frame(at: Date().addingTimeInterval(afterDrop)) }
        let arrive = USC.T_SUCK_END - USC.T_DROP, noteAt = USC.T_COUGH_END - USC.T_DROP, doneAt = USC.T_REFUSE_DONE - USC.T_DROP
        CT.checkNear("the note comes 0.12 s of heaving plus the 2.4 s hairball after the file arrives", USC.T_COUGH_END - USC.T_SUCK_END, 2.52)
        CT.check("and those two numbers are the engine's own (one place), not copies", [USC.COUGH_LEAD_S * 1000, USC.HAIRBALL_S * 1000], [CatRules.gagMs, CatRules.hairballMs])
        let flying = at(0.2)
        CT.checkTrue("just after the drop the file is in flight, and the frame says dropped and refused", flying.dropped && flying.refused && flying.fileVisible)
        let gagging = at(arrive + 1.0)
        CT.checkTrue("while the cat gags there is no bar, no progress, no check mark and no green wash", gagging.barAlpha == 0 && gagging.barReveal == 0 && gagging.progress == 0 && gagging.check == 0 && gagging.greenWash == 0)
        CT.checkTrue("the file is gone and the note is not there yet", !gagging.fileVisible && gagging.chooseAlpha == 0 && at(noteAt - 0.05).chooseAlpha == 0)
        CT.checkTrue("the cat stays where it caught the file while it gags", abs(gagging.x - at(noteAt - 0.1).x) < 1e-6 && abs(gagging.y - at(noteAt - 0.1).y) < 1e-6)
        CT.checkTrue("the note starts to appear when the hairball is over", at(noteAt + 0.15).chooseAlpha > 0)
        let done = at(doneAt + 0.1)
        CT.checkTrue("and it is fully there once the cat is at its choose place", done.chooseAlpha == 1)
        CT.checkNear("the cat is at its choose place (x)", done.x, USC.CHOOSE_X); CT.checkNear("(y)", done.y, USC.CHOOSE_Y)
        CT.check("the sequence never reaches an upload's end for the cat to celebrate", done.progEnd, USC.T_COUGH_END)
        seq.deactivate()

        CT.section("a taken file keeps the sequence it had: the bar fills and a check mark follows")
        seq.enterZone(x: 300, y: 80)
        seq.performDrop(uploadDuration: 2.4, refused: false)
        let filling = at(USC.T_PROG_START - USC.T_DROP + 1.0)
        CT.checkTrue("the bar fills, and nothing is refused", filling.dropped && !filling.refused && filling.progress > 0 && filling.barAlpha > 0)
        let checked = at(USC.T_PROG_START + 2.4 - USC.T_DROP + 0.4)
        CT.checkTrue("and the check mark comes at the end", checked.check > 0.9)
        seq.deactivate()

        CT.section("a drop's delayed work only touches its own drop: the token of a newer drop makes the older one stale")
        let gen = DropGeneration()
        let first = gen.begin()
        CT.checkTrue("a fresh token is current", gen.isCurrent(first))
        let second = gen.begin()
        CT.checkTrue("a newer drop makes the older token stale", !gen.isCurrent(first))
        CT.checkTrue("and the newer token is the current one", gen.isCurrent(second))
        CT.checkTrue("tokens only go up and are never reused", second > first && second != first)
        CT.checkTrue("a token that was never handed out is not current", !gen.isCurrent(second + 1) && !gen.isCurrent(0))
        var tokens: [Int] = []
        for _ in 0..<50 { tokens.append(gen.begin()) }
        CT.checkTrue("fifty tokens in a row are strictly increasing", zip(tokens, tokens.dropFirst()).allSatisfy { $0 < $1 } && Set(tokens).count == 50)
        CT.checkTrue("after many drops only the last token is current", tokens.dropLast().allSatisfy { !gen.isCurrent($0) } && gen.isCurrent(tokens.last!))
        CT.finish()
    }
}
