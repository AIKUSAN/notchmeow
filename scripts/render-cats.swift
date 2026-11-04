import CoreGraphics
import Foundation
import ImageIO
import UniformTypeIdentifiers

// Renders the cats into a PNG contact sheet with the real CatRenderer, without launching the app.
// Run it through scripts/render-cats.sh:
//   bash scripts/render-cats.sh --out cats.png                     every coat at every size, plus kittens
//   bash scripts/render-cats.sh --cats shrimpy,momo --out two.png  only these coats (IDs)
//   bash scripts/render-cats.sh --stage --cats shrimpy,momo        the big cats on stage panels, like the prototype's Cats section
//   bash scripts/render-cats.sh --states --cats shrimpy            the 11 states, in both motion styles, after 1.2 s in each
//   bash scripts/render-cats.sh --reactions --cats shrimpy --scale 2   the site's "How the cats react" states on one coat, each under the words of its button (after 1.2 s)
//   bash scripts/render-cats.sh --bench-kittens                    the same with eight kittens drawn as well (three under the big cat, two beside it, three at pill ends)
//   bash scripts/render-cats.sh --bench                            frame time of twelve small cats plus the big one
//   bash scripts/render-cats.sh --emotes --cats shrimpy,momo       every emote at its peak, in both motion styles
//   bash scripts/render-cats.sh --mouths --cats momo               the six mouth values: closed, smile, frown, tongue, round, wavy, skew, open
//   bash scripts/render-cats.sh --greeting --cats shrimpy          the launch greeting at its beats, island and cat
//   bash scripts/render-cats.sh --catch --cats shrimpy             the four-step file catch, and a refused file coughed up as a hairball
//   bash scripts/render-cats.sh --fur --cats shrimpy,momo          big cats plain and with fur lines (Settings → Cat → Fur lines), at rest and turned
//   bash scripts/render-cats.sh --collars --cats shrimpy,latte --scale 2   the three collar styles at Ø12 to Ø66, turned, and in six agent colours.
//                                                                  --scale is the device pixel ratio the readability floors are in: try 1 and 2
//   bash scripts/render-cats.sh --dance --cats shrimpy,momo        one beat of the Apple Music dance in eight frames: the hop alone, then with the head-bob and ears
//   bash scripts/render-cats.sh --island --scale 2                 the compact and the expanded island in the three display modes (One cat, A cat for each agent, Two cats), a mock
//                                                                  made of the real cats and the app's own layout numbers (CatIslandLayout) and cast (CatCast)
//   bash scripts/render-cats.sh --kittens --scenario life [--mode one|perAgent|two] [--both] [--steps 2,4,7]
//                                                                  the island after each step of a scripted subagent scenario (tests/fixtures/mac/subagent-scenarios.json), the
//                                                                  compact strip and the overview side by side; --both gives Codex's pill the same kittens
//   bash scripts/render-cats.sh --eyes --scale 1                   the compact cats' eyes: today's flat ink eyes next to the coloured small eyes, every coat and its kitten at Ø12
//                                                                  to Ø24 (--scale is the device pixel ratio: look at 1 and 2)
//   bash scripts/render-cats.sh --desktop-flight --scale 2         sub-project H: the alert flight as a strip of frames: surprised on the desktop, then the arc to the notch
//   bash scripts/render-cats.sh --desktop-catch --scale 2         fixes after H: the file catch as a strip of frames: the cat flies in, the catch plays at the notch, the cat flies back
//   bash scripts/render-cats.sh --desktop [--shapes] --scale 2    the desktop cat at Ø48, Ø64 and Ø96 on a mock desktop, idle and with kittens, and one in the right half of its screen;
//                                                                  --shapes shows the body that takes the mouse (green) inside the window (dashed)
//   bash scripts/render-cats.sh --wing [--mode one|perAgent|two]   the compact island stepping aside for the pointer on either wing: at rest, mid-swoosh, swooshed into the notch (cats and grid gone, the menu bar's icons showing) and with the pointer on the left wing
//   bash scripts/render-cats.sh --bench-desktop                    the desktop cat's frame cost at each size and what it is at each frame rate (idle and awake must be under 1 % of a core)
//   bash scripts/render-cats.sh --wardrobe [--part sheet|preview|compact|compact1|turned|collars] --scale 2   sub-project I: the 16 outfits on the 16 coats (sheet), one coat at five sizes (preview), the compact notch's
//                                                                  Ø20 and Ø18 big cat (compact, compact1), the head turned and the neck outfits over the collars; see scripts/render-cats-wardrobe.swift
//   bash scripts/render-cats.sh --island|--desktop|--desktop-flight --outfit bunnyears   the island (all three display modes), the desktop cat at three sizes, with every big cat dressed (kittens and small cats stay bare)
// The owner looks at this sheet next to design/prototype/notchmeow.html after stages 1 and 4.

@main
enum RenderCats {
    /// A bitmap context whose y axis points down, in points, like a SwiftUI Canvas.
    final class Sheet {
        let cg: CGContext
        let width: Double, height: Double, scale: Double
        init(width: Double, height: Double, scale: Double) {
            self.width = width; self.height = height; self.scale = scale
            let w = Int((width * scale).rounded(.up)), h = Int((height * scale).rounded(.up))
            cg = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!,
                           bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
            cg.translateBy(x: 0, y: CGFloat(h))
            cg.scaleBy(x: CGFloat(scale), y: CGFloat(-scale))
            cg.setAllowsAntialiasing(true)
            cg.setShouldAntialias(true)
            cg.interpolationQuality = .high
            cg.setFillColor(CGColor(srgbRed: 0.059, green: 0.063, blue: 0.071, alpha: 1))
            cg.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }
        func write(to path: String) {
            let image = cg.makeImage()!
            let url = URL(fileURLWithPath: path)
            let dest = CGImageDestinationCreateWithURL(url as CFURL, UTType.png.identifier as CFString, 1, nil)!
            CGImageDestinationAddImage(dest, image, nil)
            precondition(CGImageDestinationFinalize(dest), "could not write \(path)")
        }
    }

    enum Mode {
        case ladder, stage
        case states, reactions, bench
        case emotes, mouths
        case greeting
        case catchSheet
        case fur
        case collars
        case dance
        case eyes
        case island
        case kittens
        case benchKittens
        case desktopFlight
        case desktopCatch
        case desktop
        case benchDesktop
        case wing
        case wardrobe
    }

    struct Args {
        var out = "cats.png"
        var scale = 2.0
        var cats = CatPresets.ids
        var sizes: [Double] = [12, 16, 20, 24, 28, 44, 66]
        var kittens: [Double] = [16, 40]
        var mode = Mode.ladder
        var scenario = "life"
        var display = CatDisplayMode.one
        var both = false
        var steps: [Int]?
        var shapes = false
        var part = "sheet"
        var outfit = "none"
    }

    static func parse() -> Args {
        var a = Args()
        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let k = it.next() {
            switch k {
            case "--out": a.out = it.next() ?? a.out
            case "--scale": a.scale = Double(it.next() ?? "") ?? a.scale
            case "--cats": a.cats = (it.next() ?? "").split(separator: ",").map(String.init).filter { CatPresets.all[$0] != nil }
            case "--sizes": a.sizes = (it.next() ?? "").split(separator: ",").compactMap { Double($0) }
            case "--stage": a.mode = .stage
            case "--states": a.mode = .states
            case "--reactions": a.mode = .reactions
            case "--bench": a.mode = .bench
            case "--emotes": a.mode = .emotes
            case "--mouths": a.mode = .mouths
            case "--greeting": a.mode = .greeting
            case "--catch": a.mode = .catchSheet
            case "--fur": a.mode = .fur
            case "--collars": a.mode = .collars
            case "--dance": a.mode = .dance
            case "--eyes": a.mode = .eyes
            case "--island": a.mode = .island
            case "--kittens": a.mode = .kittens
            case "--bench-kittens": a.mode = .benchKittens
            case "--desktop-flight": a.mode = .desktopFlight
            case "--desktop-catch": a.mode = .desktopCatch
            case "--desktop": a.mode = .desktop
            case "--shapes": a.shapes = true
            case "--bench-desktop": a.mode = .benchDesktop
            case "--wing": a.mode = .wing
            case "--wardrobe": a.mode = .wardrobe
            case "--part": a.part = it.next() ?? a.part
            case "--outfit": let id = it.next() ?? ""; a.outfit = Wardrobe.ids.contains(id) && id != "auto" ? id : "none"
            case "--scenario": a.scenario = it.next() ?? a.scenario
            case "--steps": a.steps = (it.next() ?? "").split(separator: ",").compactMap { Int($0) }
            case "--both": a.both = true
            case "--mode": a.display = CatDisplayMode(rawValue: it.next() ?? "") ?? .one
            default: FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8)); exit(2)
            }
        }
        return a
    }

    @MainActor static func main() {
        let a = parse()
        sheetOutfit = a.outfit
        let sheet: Sheet
        switch a.mode {
        case .ladder: sheet = ladder(a)
        case .stage: sheet = stage(a)
        case .states: sheet = states(a)
        case .reactions: sheet = reactions(a)
        case .bench: bench(); return
        case .benchKittens: bench(kittens: 8); return
        case .desktopFlight: sheet = flightSheet(a)
        case .desktopCatch: sheet = desktopCatchSheet(a)
        case .desktop: sheet = desktopSheet(a)
        case .benchDesktop: benchDesktop(); return
        case .wing: sheet = wingSheet(a)
        case .wardrobe: sheet = wardrobeSheet(a)
        case .emotes: sheet = emotes(a)
        case .mouths: sheet = mouths(a)
        case .greeting: sheet = greeting(a)
        case .catchSheet: sheet = catchSheet(a)
        case .fur: sheet = furSheet(a)
        case .collars: sheet = collarSheet(a)
        case .dance: sheet = danceSheet(a)
        case .eyes: sheet = eyeSheet(a)
        case .island: sheet = islandSheet(a)
        case .kittens: sheet = kittenSheet(a)
        }
        sheet.write(to: a.out)
        print("wrote \(a.out)")
    }

    // MARK: A cat on a fake clock

    final class Clock { var t = 0.0 }

    /// An engine on a fake clock and a seeded random source, so a sheet looks the same every time.
    @MainActor static func scene(_ preset: CatPreset, profile: String, D: Double, seed: UInt32 = 7, state: CatState = .idle, mini: Bool = false, quiet: Bool = false) -> (e: CatEngine, clock: Clock, step: () -> Void) {
        let clock = Clock(), rng = CatRNG(seed: seed)
        let e = CatEngine(preset, mini: mini, now: { clock.t }, rand: { rng.next() }, cfg: CatConfig(motion: profile), quiet: quiet, state: state)
        func place() { let L = CatGeometry.layout(preset, e.s, cx: 0, cy: 0, D: D); e.base = L.base; e.mouthPoint = L.mouth }
        place()
        return (e, clock, { clock.t += 1000.0 / 60; e.update(dt: 1.0 / 60); place() })
    }

    // MARK: States: every state in both motion styles

    @MainActor static func states(_ a: Args) -> Sheet {
        let cell = 190.0, labelW = 130.0, rows = a.cats.count * 2
        let sheet = Sheet(width: labelW + cell * Double(CatState.allCases.count) + 8, height: cell * Double(rows) + 28, scale: a.scale)
        let cg = sheet.cg
        for (ci, st) in CatState.allCases.enumerated() {
            CatDraw.text(cg, st.rawValue, x: labelW + (Double(ci) + 0.5) * cell, y: 14, size: 12, bold: true, color: CatDraw.white(0.8))
        }
        var row = 0
        for id in a.cats {
            for profile in ["playful", "classic"] {
                let top = 28 + Double(row) * cell
                CatDraw.text(cg, "\(CatPresets.byID(id).label) · \(profile)", x: 62, y: top + cell / 2, size: 12, bold: true, color: CatDraw.white(0.85))
                for (ci, st) in CatState.allCases.enumerated() {
                    let x = labelW + Double(ci) * cell
                    let (e, clock, step) = scene(CatPresets.byID(id), profile: profile, D: 110, state: st)
                    for _ in 0..<72 { step() }                       // 1.2 s into the state
                    cg.saveGState()
                    cg.clip(CatDraw.roundRect(x + 3, top + 3, cell - 6, cell - 6, 12))
                    cg.fill(CatDraw.roundRect(x, top, cell, cell, 0), CatDraw.black(1))
                    CatRenderer.draw(cg, e.look(time: clock.t / 1000), cx: x + cell / 2, cy: top + cell * 0.58, D: 110, CatDrawOptions(glow: true))
                    cg.restoreGState()
                }
                row += 1
            }
        }
        return sheet
    }

    // MARK: Reactions: the site's eight states on one coat, each under its button's words

    /// The site's "How the cats react" buttons, in order (docs/index.html and windows/src/site/rules.ts): the state each one sets, and the words on it.
    static let reactionWords: [(state: CatState, words: String)] = [
        (.working, "Working"), (.thinking, "Thinking"), (.approval, "Needs your OK"), (.question, "Has a question"),
        (.finished, "Done"), (.error, "Something failed"), (.ratelimit, "Hit a limit"), (.sleeping, "Asleep"),
    ]

    @MainActor static func reactions(_ a: Args) -> Sheet {
        let cell = 190.0, top = 28.0
        let preset = CatPresets.byID(a.cats.first ?? "shrimpy")
        let sheet = Sheet(width: cell * Double(reactionWords.count) + 8, height: top + cell + 8, scale: a.scale)
        let cg = sheet.cg
        for (ci, r) in reactionWords.enumerated() {
            let x = Double(ci) * cell
            CatDraw.text(cg, r.words, x: x + cell / 2, y: 14, size: 12, bold: true, color: CatDraw.white(0.8))
            let (e, clock, step) = scene(preset, profile: "playful", D: 110, state: r.state)
            for _ in 0..<72 { step() }                       // 1.2 s into the state
            cg.saveGState()
            cg.clip(CatDraw.roundRect(x + 3, top + 3, cell - 6, cell - 6, 12))
            cg.fill(CatDraw.roundRect(x, top, cell, cell, 0), CatDraw.black(1))
            CatRenderer.draw(cg, e.look(time: clock.t / 1000), cx: x + cell / 2, cy: top + cell * 0.58, D: 110, CatDrawOptions(glow: true))
            cg.restoreGState()
        }
        return sheet
    }

    // MARK: Emotes: every emote at its peak

    /// The emotes and how long after they start the sheet shows them (ms): about when they are most themselves.
    static let emotePeaks: [(name: String, ms: Int)] = [
        ("love", 700), ("happy", 300), ("surprised", 250), ("proud", 700), ("wink", 450), ("yawn", 650), ("annoyed", 300),
        ("hello", 1000), ("zoomies", 900), ("hairball", 1250),
    ]

    @MainActor static func emotes(_ a: Args) -> Sheet {
        let cell = 190.0, labelW = 130.0, rows = a.cats.count * 2
        let sheet = Sheet(width: labelW + cell * Double(emotePeaks.count) + 8, height: cell * Double(rows) + 28, scale: a.scale)
        let cg = sheet.cg
        for (ci, em) in emotePeaks.enumerated() { CatDraw.text(cg, em.name, x: labelW + (Double(ci) + 0.5) * cell, y: 14, size: 12, bold: true, color: CatDraw.white(0.8)) }
        var row = 0
        for id in a.cats {
            for profile in ["playful", "classic"] {
                let top = 28 + Double(row) * cell
                CatDraw.text(cg, "\(CatPresets.byID(id).label) · \(profile)", x: 62, y: top + cell / 2, size: 12, bold: true, color: CatDraw.white(0.85))
                for (ci, em) in emotePeaks.enumerated() {
                    let x = labelW + Double(ci) * cell
                    let (e, clock, step) = scene(CatPresets.byID(id), profile: profile, D: 110, quiet: true)
                    e.emote(em.name)
                    for _ in 0..<Int((Double(em.ms) / (1000.0 / 60)).rounded()) { step() }
                    cg.saveGState()
                    cg.clip(CatDraw.roundRect(x + 3, top + 3, cell - 6, cell - 6, 12))
                    cg.fill(CatDraw.roundRect(x, top, cell, cell, 0), CatDraw.black(1))
                    CatRenderer.draw(cg, e.look(time: clock.t / 1000), cx: x + cell / 2, cy: top + cell * 0.58, D: 110, CatDrawOptions(glow: true))
                    cg.restoreGState()
                }
                row += 1
            }
        }
        return sheet
    }

    // MARK: Mouths: the six values, set by hand

    @MainActor static func mouths(_ a: Args) -> Sheet {
        let cell = 210.0, labelW = 130.0
        let variants: [(String, (inout CatPose) -> Void, Double)] = [
            ("closed", { _ in }, 0), ("smile", { $0.smile = 1 }, 0), ("frown", { $0.smile = -0.8 }, 0), ("skew", { $0.mskew = 0.7; $0.smile = -0.15 }, 0),
            ("blep", { $0.tongue = 0.8; $0.smile = 0.4 }, 0), ("wavy", { $0.wavy = 1; $0.tongue = 0.45 }, 0), ("meow", { $0.smile = 0.1 }, 0.5),
            ("yawn", { $0.tongue = 0.35; $0.mround = 0.15 }, 1), ("'o'", { $0.mround = 1 }, 0.6), ("hiss", { $0.smile = -1 }, 0.75),
        ]
        let sheet = Sheet(width: labelW + cell * Double(variants.count) + 8, height: cell * Double(a.cats.count) + 28, scale: a.scale)
        let cg = sheet.cg
        for (ci, v) in variants.enumerated() { CatDraw.text(cg, v.0, x: labelW + (Double(ci) + 0.5) * cell, y: 14, size: 12, bold: true, color: CatDraw.white(0.8)) }
        for (ri, id) in a.cats.enumerated() {
            let top = 28 + Double(ri) * cell
            CatDraw.text(cg, CatPresets.byID(id).label, x: 62, y: top + cell / 2, size: 12, bold: true, color: CatDraw.white(0.85))
            for (ci, v) in variants.enumerated() {
                let x = labelW + Double(ci) * cell
                var pose = CatPose(); v.1(&pose)
                cg.saveGState()
                cg.clip(CatDraw.roundRect(x + 3, top + 3, cell - 6, cell - 6, 12))
                cg.fill(CatDraw.roundRect(x, top, cell, cell, 0), CatDraw.black(1))
                CatRenderer.draw(cg, CatLook(preset: CatPresets.byID(id), pose: pose, mouthOpen: v.2), cx: x + cell / 2, cy: top + cell * 0.55, D: 150)
                cg.restoreGState()
            }
        }
        return sheet
    }



    // MARK: Fur lines: plain next to fur, big, at rest and with the head turned

    @MainActor static func furSheet(_ a: Args) -> Sheet {
        let cell = 250.0, labelW = 110.0
        var turned = CatPose(); turned.yaw = 0.5; turned.pitch = 0.2
        let variants: [(String, Bool, CatPose)] = [("plain (the default)", false, CatPose()), ("fur lines", true, CatPose()), ("fur lines, head turned", true, turned)]
        let sheet = Sheet(width: labelW + cell * Double(variants.count) + 8, height: cell * Double(a.cats.count) + 28, scale: a.scale)
        let cg = sheet.cg
        for (ci, v) in variants.enumerated() { CatDraw.text(cg, v.0, x: labelW + (Double(ci) + 0.5) * cell, y: 14, size: 12, bold: true, color: CatDraw.white(0.8)) }
        for (ri, id) in a.cats.enumerated() {
            let top = 28 + Double(ri) * cell, preset = CatPresets.byID(id)
            CatDraw.text(cg, preset.label, x: 52, y: top + cell / 2, size: 12, bold: true, color: CatDraw.white(0.85))
            for (ci, v) in variants.enumerated() {
                let x = labelW + Double(ci) * cell
                cg.saveGState()
                cg.clip(CatDraw.roundRect(x + 3, top + 3, cell - 6, cell - 6, 12))
                cg.fill(CatDraw.roundRect(x, top, cell, cell, 0), CatDraw.black(1))
                CatRenderer.draw(cg, CatLook(preset: preset, pose: v.2), cx: x + cell / 2, cy: top + cell * 0.55, D: 150, CatDrawOptions(fur: v.1))
                cg.restoreGState()
            }
        }
        return sheet
    }

    // MARK: The music dance: one beat in eight frames, with and without the head-bob

    @MainActor static func danceSheet(_ a: Args) -> Sheet {
        let frames = 8, cell = 170.0, labelW = 190.0, D = 90.0, beat = 60 / CatDance.bpm
        let sheet = Sheet(width: labelW + cell * Double(frames) + 8, height: 28 + cell * Double(a.cats.count * 2), scale: a.scale)
        let cg = sheet.cg
        for f in 0..<frames { CatDraw.text(cg, String(format: "%.0f%% of the beat", Double(f) / Double(frames) * 100), x: labelW + (Double(f) + 0.5) * cell, y: 14, size: 11, bold: true, color: CatDraw.white(0.8)) }
        var row = 0
        for id in a.cats {
            for bob in [false, true] {
                let top = 28 + Double(row) * cell, preset = CatPresets.byID(id)
                CatDraw.text(cg, "\(preset.label) · \(bob ? "head-bob and ears" : "the hop alone")", x: labelW / 2, y: top + cell / 2, size: 12, bold: true, color: CatDraw.white(0.85))
                for f in 0..<frames {
                    let (e, _, step) = scene(preset, profile: "playful", D: D, quiet: true)
                    e.setDancing(true)
                    for _ in 0..<90 { step() }                                      // 1.5 s: the dance is at its full level
                    let seconds = 10 * beat + Double(f) / Double(frames) * beat      // frame f of one beat, ten beats in
                    let level = e.dancingLevel
                    if !bob { e.dancingLevel = 0 }                                   // the hop alone: the engine hands the renderer its own pose
                    let look = e.look(time: seconds)
                    e.dancingLevel = level
                    let x = labelW + Double(f) * cell, cx = x + cell / 2, cy = top + cell * 0.5
                    cg.saveGState()
                    cg.clip(CatDraw.roundRect(x + 2, top + 2, cell - 4, cell - 4, 10))
                    cg.fill(CatDraw.roundRect(x, top, cell, cell, 0), CatDraw.black(1))
                    CatEffects.applyDance(cg, level: level, seconds: seconds, pivotX: cx, pivotY: cy + D * 0.45, size: D / 2)
                    CatRenderer.draw(cg, look, cx: cx, cy: cy, D: D)
                    cg.restoreGState()
                }
                row += 1
            }
        }
        return sheet
    }

    // MARK: Collars: every style at every size, turned, and in the agents' colours

    /// The colours of the agents (the pill catalogue's, as the prototype's collar panel uses them).
    static let agentColors: [(name: String, hex: String)] = [("Claude Code", "#E07950"), ("Gemini CLI", "#8AB4F8"), ("Codex", "#2DD4BF"), ("Antigravity", "#E879F9"), ("Cursor", "#C0C4CC"), ("Claude Code pill", "#F5F6F8")]

    /// Each cat: a row per style (Off first) across the head widths and two turned heads, then a row per style in the six agent colours at Ø28. The sheet's
    /// scale is the device pixel ratio the collar's floors are measured in (a band 3 px thick, a tag 6 across, a neckerchief 7 wide and 5 deep).
    @MainActor static func collarSheet(_ a: Args) -> Sheet {
        let sizes: [Double] = [12, 16, 20, 24, 28, 44, 66], cell = 84.0, labelW = 200.0, dpr = a.scale
        let styles = [("Off", "off"), ("Band and tag", "tag"), ("Band", "band"), ("Neckerchief", "kerchief")]
        var turned = CatPose(); turned.yaw = 0.6; turned.pitch = 0.2
        let columns = sizes.count + 2, rowsPerCat = styles.count + 3
        let sheet = Sheet(width: labelW + cell * Double(columns) + 8, height: 28 + (cell + 8) * Double(rowsPerCat * a.cats.count), scale: a.scale)
        let cg = sheet.cg
        for (ci, d) in sizes.enumerated() { CatDraw.text(cg, "Ø\(Int(d))", x: labelW + (Double(ci) + 0.5) * cell, y: 14, size: 12, bold: true, color: CatDraw.white(0.8)) }
        CatDraw.text(cg, "Ø20 turned", x: labelW + (Double(sizes.count) + 0.5) * cell, y: 14, size: 12, bold: true, color: CatDraw.white(0.8))
        CatDraw.text(cg, "Ø66 turned", x: labelW + (Double(sizes.count) + 1.5) * cell, y: 14, size: 12, bold: true, color: CatDraw.white(0.8))
        func cellAt(_ col: Int, _ row: Int, _ preset: CatPreset, pose: CatPose, D: Double, collar: CatCollarPaint?) {
            let x = labelW + Double(col) * cell, top = 28 + Double(row) * (cell + 8)
            cg.saveGState()
            cg.clip(CatDraw.roundRect(x + 2, top, cell - 4, cell, 10))
            cg.fill(CatDraw.roundRect(x, top, cell, cell, 0), CatDraw.black(1))
            var o = CatDrawOptions(); o.collar = collar
            CatRenderer.draw(cg, CatLook(preset: preset, pose: pose), cx: x + cell / 2, cy: top + cell * 0.5, D: D, o)
            cg.restoreGState()
        }
        for (ri, id) in a.cats.enumerated() {
            let preset = CatPresets.byID(id), first = ri * rowsPerCat
            for (si, style) in styles.enumerated() {
                let row = first + si, top = 28 + Double(row) * (cell + 8)
                CatDraw.text(cg, "\(preset.label) · \(style.0)", x: labelW / 2, y: top + cell / 2, size: 12, bold: true, color: CatDraw.white(0.85))
                let paint = CatCollarPaint(style: style.1, color: agentColors[0].hex, dpr: dpr)
                for (ci, d) in sizes.enumerated() { cellAt(ci, row, preset, pose: CatPose(), D: d, collar: paint) }
                cellAt(sizes.count, row, preset, pose: turned, D: 20, collar: paint)
                cellAt(sizes.count + 1, row, preset, pose: turned, D: 66, collar: paint)
            }
            for (si, style) in styles.dropFirst().enumerated() {
                let row = first + styles.count + si, top = 28 + Double(row) * (cell + 8)
                CatDraw.text(cg, "\(style.0), Ø28, six agents", x: labelW / 2, y: top + cell / 2, size: 11, bold: false, color: CatDraw.white(0.7))
                for (ci, c) in agentColors.enumerated() {
                    cellAt(ci, row, preset, pose: CatPose(), D: 28, collar: CatCollarPaint(style: style.1, color: c.hex, dpr: dpr))
                    CatDraw.text(cg, c.name, x: labelW + (Double(ci) + 0.5) * cell, y: top + cell - 5, size: 8, bold: false, color: CatDraw.white(0.5))
                }
            }
        }
        return sheet
    }

    // MARK: The file catch: taken, and refused

    @MainActor static func catchSheet(_ a: Args) -> Sheet {
        let cell = 200.0, labelW = 170.0   // wide enough for "Shrimpy · refused file"
        let taken = ["hovering: mouth wide", "dropped: snaps wider", "the file flies in", "gulp", "chew", "lick"]
        let refused = ["hovering: mouth wide", "dropped: snaps wider", "the file flies in", "gags", "coughs it up", "rolls away"]
        let sheet = Sheet(width: labelW + cell * 6 + 8, height: (cell + 20) * Double(a.cats.count * 2) + 8, scale: a.scale)
        let cg = sheet.cg
        var row = 0
        for id in a.cats {
            let preset = CatPresets.byID(id)
            for isRefused in [false, true] {
                let top = 4 + Double(row) * (cell + 20)
                CatDraw.text(cg, "\(preset.label) · \(isRefused ? "refused file" : "taken file")", x: labelW / 2, y: top + cell / 2, size: 12, bold: true, color: CatDraw.white(0.85))
                for (ci, label) in (isRefused ? refused : taken).enumerated() {
                    let (e, clock, step) = scene(preset, profile: "playful", D: 110, quiet: true)
                    func run(_ ms: Double) { for _ in 0..<Int((ms / (1000.0 / 60)).rounded()) { step() } }
                    let x = labelW + Double(ci) * cell, cx = x + cell / 2, cy = top + cell * 0.6
                    e.catchOpen(true); run(500)
                    var fileK: Double?                                    // where the file is along its flight, if it is in the air
                    if ci == 0 { fileK = nil }
                    if ci >= 1 { e.catchDrop(); run(ci == 1 ? 100 : 380); fileK = ci == 1 ? 0.25 : 1 }
                    if ci == 2 { e.catchDrop(); fileK = 0.75 }
                    if ci >= 3 {
                        if isRefused { e.catchReject("EXE") } else { e.catchArrive() }
                        run([100.0, 500, 1000][min(ci - 3, 2)] + (isRefused ? [500.0, 800, 1100][min(ci - 3, 2)] : 0))
                        fileK = nil
                    }
                    cg.saveGState()
                    cg.clip(CatDraw.roundRect(x + 3, top + 3, cell - 6, cell - 6, 12))
                    cg.fill(CatDraw.roundRect(x, top, cell, cell, 0), CatDraw.black(1))
                    let L = CatRenderer.draw(cg, e.look(time: clock.t / 1000), cx: cx, cy: cy, D: 110, CatDrawOptions(glow: true))
                    if let k = fileK, let m = L.mouth {
                        let w = CatGreeting.flightAt(from: (x: cx + 70, y: top + 24), to: (x: m.x, y: m.y), R: L.R, k: k)
                        CatEffects.drawFile(cg, x: w.x, y: w.y, size: w.size, rot: w.rot, ext: isRefused ? "EXE" : "PDF")
                    }
                    cg.restoreGState()
                    CatDraw.text(cg, label, x: cx, y: top + cell + 9, size: 10, bold: false, color: CatDraw.white(0.55))
                }
                row += 1
            }
        }
        return sheet
    }

    // MARK: The launch greeting at its beats

    @MainActor static func greeting(_ a: Args) -> Sheet {
        let beats: [(Double, String)] = [(0.3, "grows"), (0.62, "lands"), (0.72, "squash"), (1.2, "bounce"), (1.5, "slides aside"), (1.9, "pops up"), (2.3, "waves"),
                                         (2.7, "waves"), (3.0, "slides back"), (3.8, "settles"), (4.5, "badge, tint"), (5.0, "collapses"), (5.2, "collapses"),
                                         (5.4, "the row pops in"), (5.75, "the row holds"), (5.9, "glides"), (6.0, "glides"), (6.1, "the fourth pops in"), (6.5, "the grid")]
        let cols = 2, rows = (beats.count + 1) / 2, w = 640.0, h = 150.0
        let sheet = Sheet(width: w * Double(cols) + 24, height: (h + 22) * Double(rows * a.cats.count), scale: a.scale)
        let cg = sheet.cg
        var slot = 0
        for id in a.cats {
            for (i, beat) in beats.enumerated() {
                let ox = 8 + Double(i % cols) * (w + 8), oy = 4 + Double(slot + i / cols) * (h + 22)
                let (e, clock, step) = scene(CatPresets.byID(id), profile: "playful", D: 80, quiet: true); e.cfg.outfit = sheetOutfit
                let scratch = CGContext(data: nil, width: 4, height: 4, bitsPerComponent: 8, bytesPerRow: 0, space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
                let frames = Int((beat.0 * 60).rounded())
                for _ in 0..<frames { step(); CatGreetingRenderer.draw(scratch, t: clock.t / 1000, leave: CatGreeting.GT.leave, engine: e, end: CatGreeting.Compact()) }
                cg.saveGState()
                cg.translateBy(x: ox, y: oy)
                let P = CatGreeting.pose(beat.0)
                cg.fill(CatDraw.roundRect(320 - P.iw / 2, 0, P.iw, P.ih, 24), CatDraw.black(1))
                cg.clip(CatDraw.roundRect(320 - P.iw / 2, 0, P.iw, P.ih, 24))
                CatGreetingRenderer.draw(cg, t: beat.0, leave: CatGreeting.GT.leave, engine: e, end: CatGreeting.Compact())
                cg.restoreGState()
                CatDraw.text(cg, String(format: "%.2f s · %@", beat.0, beat.1), x: ox + 4, y: oy + h + 9, size: 10, bold: false, color: CatDraw.white(0.5), anchor: .left)
            }
            slot += rows
        }
        return sheet
    }

    // MARK: Frame time: twelve small cats plus the big one

    /// This thread's CPU time in seconds: a busy machine does not inflate it the way it inflates the wall clock.
    static func cpuNow() -> Double { Double(clock_gettime_nsec_np(CLOCK_THREAD_CPUTIME_ID)) / 1e9 }

    @MainActor static func bench(kittens: Int = 0) {
        let sheet = Sheet(width: 640, height: 220, scale: 2)
        let states = CatState.allCases
        let cats = (0..<12).map { i -> (CatEngine, Clock, () -> Void, Double, Double) in
            let id = CatPresets.ids[i % 4 == 0 ? 0 : (i % 4 == 1 ? 1 : (i % 4 == 2 ? 3 : 4))]
            let d = [12.0, 16, 20, 24][i % 4], (e, c, s) = scene(CatPresets.byID(id), profile: i % 2 == 0 ? "playful" : "classic", D: d, seed: UInt32(i + 1), state: states[i % states.count], mini: true)
            return (e, c, s, d, 60 + Double(i) * 34)
        }
        let big = scene(CatPresets.byID("shrimpy"), profile: "playful", D: 66, state: .working)
        var bigOptions = CatDrawOptions()
        bigOptions.outfit = CatOutfitDraw.big(sheetOutfit, dpr: 2)   // `--outfit`: the big cat's cost with an outfit on
        // kittens (Ø15, with their state badges), drawn at 30 fps like the small cats: they are small cats too
        let kits = (0..<kittens).map { i -> (CatEngine, Clock, () -> Void, Double) in
            let (e, c, s) = scene(CatPresets.kitten(of: CatPresets.byID(["shrimpy", "momo", "ginger"][i % 3])), profile: "playful", D: 15, seed: UInt32(40 + i), state: [CatState.working, .searching, .approval][i % 3], mini: true)
            return (e, c, s, 30 + Double(i) * 30)
        }
        var times: [Double] = []
        for f in 0..<600 {
            let start = cpuNow()
            sheet.cg.clear(CGRect(x: 0, y: 0, width: 640, height: 220))
            for i in cats.indices where f % 2 == 0 {                  // the small cats redraw at 30 fps, like MiniBotCanvasView
                cats[i].2()
                CatRenderer.draw(sheet.cg, cats[i].0.look(time: cats[i].1.t / 1000), cx: cats[i].4, cy: 30, D: cats[i].3, CatDrawOptions(badge: true))
            }
            for i in kits.indices where f % 2 == 0 {
                kits[i].2()
                CatRenderer.draw(sheet.cg, kits[i].0.look(time: kits[i].1.t / 1000), cx: kits[i].3, cy: 75, D: 15, CatDrawOptions(badge: true))
            }
            big.step()
            CatRenderer.draw(sheet.cg, big.e.look(time: big.clock.t / 1000), cx: 320, cy: 130, D: 66, bigOptions)
            if f >= 60 { times.append((cpuNow() - start) * 1000) }
        }
        times.sort()
        let avg = times.reduce(0, +) / Double(times.count)
        print(String(format: "12 small cats (30 fps)%@ + the big one (60 fps), update and draw, CPU time: avg %.2f ms, p95 %.2f ms, max %.2f ms per frame (%d frames)", kittens > 0 ? " + \(kittens) kittens (30 fps)" : "", avg, times[Int(Double(times.count) * 0.95)], times.last!, times.count))
    }

    // MARK: Stage panels: the big cats, the way the prototype shows them

    private static let panelW = 560.0, panelH = 450.0

    @MainActor static func stage(_ a: Args) -> Sheet {
        let sheet = Sheet(width: panelW * Double(a.cats.count), height: panelH, scale: a.scale)
        for (i, id) in a.cats.enumerated() {
            let cg = sheet.cg, ox = Double(i) * panelW, p = CatPresets.byID(id)
            cg.saveGState()
            cg.clip(CatDraw.roundRect(ox + 4, 4, panelW - 8, panelH - 8, 14))
            cg.fill(CatDraw.roundRect(ox, 0, panelW, panelH, 0), CatDraw.black(1))
            CatDraw.text(cg, p.label, x: ox + 40, y: 22, size: 13, bold: true, color: CatDraw.white(0.9))
            CatRenderer.draw(cg, CatLook(preset: p), cx: ox + panelW / 2, cy: panelH * 0.57, D: min(panelW * 0.4, panelH * 0.5))
            cg.restoreGState()
        }
        return sheet
    }

    // MARK: Size ladder: every coat at every size, then its kittens

    private static let rowH = 150.0
    private static func slotW(_ d: Double) -> Double { max(62, d * 2.2) }

    // MARK: The island in the three display modes

    /// The island as the app lays it out, in a mock: the compact strip (345 by 32 pt, a notch of 185 in the middle) and the expanded overview (640 by 160) for each
    /// display mode, with the sample island of Settings' Display preview (`CatDisplaySample`). The cats are the real ones in the places `CatIslandLayout`, `CatCast` and the
    /// app's `botPosition` give them; the texts and the cards are drawn the way the prototype draws its mock, to judge the room they leave, not their look.
    @MainActor static func islandSheet(_ a: Args) -> Sheet {
        let rowH = 196.0, left = 150.0, cw = 345.0, ew = 640.0, gap = 28.0
        let sheet = Sheet(width: left + cw + gap + ew + 16, height: rowH * 3 + 8, scale: a.scale)
        let cg = sheet.cg
        for (i, mode) in CatDisplayMode.allCases.enumerated() {
            let top = Double(i) * rowH + 8
            let display = CatDisplaySettings(mode: mode, pair: CatDisplaySettings.defaultPair, agentCats: [:])
            let cast = CatDisplaySample.cast(display, main: "shrimpy")
            let name = ["one": "One cat", "perAgent": "A cat for each agent", "two": "Two cats"][mode.rawValue]!
            CatDraw.text(cg, name, x: 14, y: top + 20, size: 12, bold: true, color: CatDraw.white(0.9), anchor: .left)
            drawCompact(cg, cast, ox: left, oy: top + 10)
            drawExpanded(cg, cast, ox: left + cw + gap, oy: top)
        }
        return sheet
    }

    /// A cat on its own fake clock for 1.2 s, then drawn: `coat` in `state`, `d` across, centred at (cx, cy).
    @MainActor private static func drawIslandCat(_ cg: CGContext, _ coat: String, _ state: CatState, colour: String?, big: Bool, cx: Double, cy: Double, d: Double, top: Double? = nil, headroom: Double? = nil, badgeSide: Double = 1, badgeLeft: Double? = nil, seed: UInt32) {
        let s = scene(CatPresets.byID(coat), profile: "playful", D: d, seed: seed, state: state, mini: !big, quiet: true)
        for _ in 0..<72 { s.step() }
        s.e.collar = big ? CatRules.bigCatCollar(colour: colour, state: state) : colour
        var options = CatDrawOptions(badge: big)
        if big { options.outfit = CatOutfitDraw.big(sheetOutfit, dpr: 2) }   // `--outfit`: every big cat of the island sheets is dressed, the small ones are not
        options.badgeSide = badgeSide
        options.badgeLeftLimit = badgeLeft
        if let top { options.earCeiling = top }
        // `headroom`: the cat's own canvas has no overhang (cat 2 of the overview: the canvas is D/0.6, so its top is D/1.2 above the head's centre). The app gives the outfit that line as its ceiling
        // and the canvas cuts anything past it; the sheet clips to the same line, so what it shows is what the canvas would.
        if let headroom {
            options.outfit?.ceiling = cy - headroom
            cg.saveGState(); cg.clip(to: CGRect(x: cx - 2000, y: cy - headroom, width: 4000, height: 4000))
        }
        CatRenderer.draw(cg, s.e.look(time: s.clock.t / 1000), cx: cx, cy: cy, D: d, options)
        if headroom != nil { cg.restoreGState() }
    }

    private static func samplePill(_ id: String?) -> CatDisplaySample.Pill? { CatDisplaySample.pills.first { $0.id == id } }

    /// The kittens of a scene, by pill, and the time they are drawn at (ms).
    struct KittenScene {
        var lists: [String: [CatKittens.Kitten]] = [:]
        var now = 0.0
    }

    /// One parent's kittens in one place, settled for 0.75 s on a fake clock and then drawn.
    @MainActor static func drawKittens(_ cg: CGContext, _ list: [CatKittens.Kitten], place: String, parentCat: String, origin: (x: Double, y: Double), unit: Double, colour: String?) {
        let clock = Clock(), herd = CatKittenHerd(), rng = CatRNG(seed: 5), slots = CatKittens.slots(place, list), scratch = Sheet(width: 4, height: 4, scale: 1).cg
        herd.rand = { rng.next() }
        func go(_ into: CGContext) {
            CatKittenDraw.draw(into, slots, parentCat: parentCat, origin: origin, unit: unit, colour: colour, dpr: 2, herd: herd, now: { clock.t }) { e in e.update(dt: 1.0 / 60) }
        }
        for _ in 0..<45 { clock.t += 1000.0 / 60; go(scratch) }
        go(cg)
    }

    @MainActor static func drawKittenLayers(_ cg: CGContext, _ cast: CatCast.Result, expanded: Bool, big: (x: Double, y: Double, d: Double), second: (x: Double, y: Double, d: Double)?, ox: Double, oy: Double, kit: KittenScene) {
        for parent in CatIslandLayout.kittenParents(cast.mode, expanded: expanded, big: big, second: second) {
            let spot = parent.cat == 0 ? cast.big : cast.second
            let pills = parent.countsBoth ? [cast.big.pill, cast.second?.pill].compactMap { $0 } : [spot?.pill].compactMap { $0 }
            let list = pills.flatMap { CatKittens.view(kit.lists[$0] ?? [], now: kit.now) }
            guard !list.isEmpty, let spot else { continue }
            drawKittens(cg, list, place: parent.place, parentCat: spot.cat, origin: (ox + parent.x, oy + parent.y), unit: parent.unit, colour: parent.countsBoth ? nil : samplePill(spot.pill)?.color)
        }
    }

    @MainActor static func drawCompact(_ cg: CGContext, _ cast: CatCast.Result, ox: Double, oy: Double, kit: KittenScene = KittenScene(), swoosh: Double = 0) {
        let W = 345.0, H = 32.0
        // `swoosh`: how far the island has stepped aside into the notch (IslandWing): its black narrows to the notch's width, centred, and its cats, grid and kittens fade with it.
        let w = Double(IslandWing.width(full: W, notchWidth: W - 160, swoosh: swoosh))
        cg.fill(CatDraw.roundRect(ox + (W - w) / 2, oy, w, H, 14), CatDraw.black(1))
        cg.fill(CatDraw.roundRect(ox + 80, oy, W - 160, H, 10), CatDraw.rgb([24, 25, 28]))
        cg.saveGState(); cg.setAlpha(CGFloat(1 - swoosh)); cg.beginTransparencyLayer(auxiliaryInfo: nil)   // the cats, grid and kittens fade as one picture
        defer { cg.endTransparencyLayer(); cg.restoreGState() }
        let xs = CatIslandLayout.compactX(cast.mode)
        func big(_ spot: CatCast.Spot, _ x: Double, _ seed: UInt32) {
            let p = samplePill(spot.pill)
            drawIslandCat(cg, spot.cat, p?.state ?? .idle, colour: p?.color, big: true, cx: ox + x, cy: oy + H / 2, d: 20, top: -H / 2 + 0, badgeSide: -1, seed: seed)
        }
        big(cast.big, xs[0], 1)
        if let second = cast.second { big(second, xs[1], 2) }
        for (i, p) in cast.pills.enumerated() {
            let sp = samplePill(p.pill)
            drawIslandCat(cg, p.cat, sp?.state ?? .idle, colour: sp?.color, big: false, cx: ox + W - 40 + (i % 2 == 1 ? 8 : -8), cy: oy + H / 2 + (i < 2 ? -8 : 8), d: 12, seed: UInt32(10 + i))
        }
        let ys = oy - oy + H / 2
        drawKittenLayers(cg, cast, expanded: false, big: (xs[0], ys, 20), second: xs.count > 1 ? (xs[1], ys, 20) : nil, ox: ox, oy: oy, kit: kit)
    }

    @MainActor static func drawExpanded(_ cg: CGContext, _ cast: CatCast.Result, ox: Double, oy: Double, kit: KittenScene = KittenScene()) {
        let W = 640.0, H = 160.0, two = cast.second != nil
        cg.fill(CatDraw.roundRect(ox, oy, W, H, 22), CatDraw.black(1))
        let card = CatDraw.rgb([19, 20, 23])
        cg.fill(CatDraw.roundRect(ox + CatIslandLayout.cardX, oy + 42, 322, 84, 12), card)
        cg.fill(CatDraw.roundRect(ox + 342, oy + 42, 288, 84, 12), card)
        // the cats: where botPosition puts the one big cat (68, 101, 58 across), and the pair's
        let cy = 101.0, one = CatIslandLayout.pairExpanded(botX: 68, cy: cy)
        let bigPill = samplePill(cast.big.pill)
        drawIslandCat(cg, cast.big.cat, bigPill?.state ?? .idle, colour: bigPill?.color, big: true, cx: ox + (two ? one.cat1X : 68), cy: oy + cy, d: 58, badgeSide: two ? -1 : 1, badgeLeft: two ? ox + one.cat1X - CatIslandLayout.pairBadgeReach(cat1X: one.cat1X) : nil, seed: 3)
        if let second = cast.second {
            let p = samplePill(second.pill)
            drawIslandCat(cg, second.cat, p?.state ?? .idle, colour: p?.color, big: true, cx: ox + one.cat2X, cy: oy + one.cat2Y, d: one.cat2D, headroom: one.cat2D / 1.2, badgeSide: 1, seed: 4)
        }
        // the left card's text, from where the layout says it starts
        let lead = ox + CatIslandLayout.cardX + (two ? one.textLeading : CatIslandLayout.oneTextLeading), titleY = oy + 42 + 4 + (two ? 4 : 6) + 8, tickerY = titleY + 8 + (two ? 0 : 6)
        CatDraw.text(cg, bigPill?.name ?? "Nothing in focus", x: lead, y: titleY, size: 12, bold: true, color: CatDraw.white(0.95), anchor: .left)
        CatDraw.text(cg, "Edit CatFace.swift", x: lead - 10 * 0.0, y: tickerY + 8, size: 10.5, bold: false, color: CatDraw.white(0.4), anchor: .left)
        CatDraw.text(cg, "Run the cat tests", x: lead, y: tickerY + 30, size: 12, bold: false, color: CatDraw.white(0.85), anchor: .left)
        if let second = cast.second {
            let p = samplePill(second.pill)
            let words = p.map { "\($0.name) · \(CatIslandLayout.stateWords($0.state))" } ?? "No other agent"
            let tone: [Double] = p?.state == .approval ? [245, 165, 36] : [142, 147, 156]
            CatDraw.text(cg, words, x: lead, y: tickerY + 44 + 2 + 7, size: 11, bold: false, color: CatDraw.rgb(tone), anchor: .left)
        }
        // the right card: the row of pills, two by two, each with its cat
        for (i, p) in cast.pills.enumerated() {
            let x = ox + 342 + 8 + Double(i % 2) * (134 + 4), y = oy + 42 + 12 + Double(i / 2) * 32, sp = samplePill(p.pill)
            cg.fill(CatDraw.roundRect(x, y, 134, 28, 14), CatDraw.rgb([14, 15, 17]))
            drawIslandCat(cg, p.cat, sp?.state ?? .idle, colour: sp?.color, big: false, cx: x + 8 + 11, cy: y + 14, d: 22, seed: UInt32(20 + i))
            let list = CatKittens.view(kit.lists[p.pill] ?? [], now: kit.now), slots = CatKittens.slots("pill", list)
            let reserve = CatIslandLayout.pillKittenReserve(slots, pillHeight: 28)
            // with kittens the title keeps clear of them and of the pill's own cat (its right edge is at 30 pt: the title starts 34 pt in), and is cut at the end when it does not fit (6 pt a letter)
            let full = sp?.name ?? p.pill, room = reserve > 0 ? 134 - 34 - reserve : 134, fit = max(1, Int(room / 6.2)), shown = reserve > 0 && full.count > fit ? String(full.prefix(max(1, fit - 1))) + "…" : full
            CatDraw.text(cg, shown, x: reserve > 0 ? x + 34 + room / 2 : x + 67, y: y + 14, size: 10, bold: true, color: CatDraw.rgb([107, 112, 121]))
            if !list.isEmpty { drawKittens(cg, list, place: "pill", parentCat: p.cat, origin: (x + 134, y + 14), unit: 28, colour: sp?.color) }
        }
        let pairAt = CatIslandLayout.pairExpanded(botX: 68, cy: cy)
        drawKittenLayers(cg, cast, expanded: true, big: (cast.second != nil ? pairAt.cat1X : 68, cy, 58), second: cast.second != nil ? (pairAt.cat2X, pairAt.cat2Y, pairAt.cat2D) : nil, ox: ox, oy: oy, kit: kit)
    }

    /// The island after each step of a scripted subagent scenario: the compact strip and the overview, in the chosen mode (default One cat), with the step's words.
    @MainActor static func kittenSheet(_ a: Args) -> Sheet {
        let data = try! JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: "tests/fixtures/mac/subagent-scenarios.json"))) as! [String: Any]
        let common = data["common"] as! [String: Any], scenario = (data["scenarios"] as! [String: Any])[a.scenario] as! [String: Any]
        let steps = scenario["steps"] as! [[String: Any]]
        let pick = a.steps ?? Array(1...steps.count)
        let rowH = 176.0, left = 400.0, cw = 345.0, ew = 640.0, gap = 24.0
        func short(_ s: String) -> String { s.count > 62 ? String(s.prefix(60)) + "…" : s }
        let sheet = Sheet(width: left + cw + gap + ew + 16, height: rowH * Double(pick.count) + 28, scale: a.scale)
        let cg = sheet.cg
        // the caption is the scenario's title (the words before its first colon), so that it fits the site's box on a phone too
        let about = scenario["about"] as! String, title = about.components(separatedBy: ":").first ?? about
        CatDraw.text(cg, "\(a.scenario): \(short(title))", x: 14, y: 14, size: 11, bold: true, color: CatDraw.white(0.9), anchor: .left)
        let display = CatDisplaySettings(mode: a.display, pair: CatDisplaySettings.defaultPair, agentCats: [:])
        let cast = CatDisplaySample.cast(display, main: "shrimpy")
        var list: [CatKittens.Kitten] = []
        for (n, step) in steps.enumerated() {
            let at = (step["at"] as! NSNumber).doubleValue
            if let sent = step["event"] as? [String: Any] {
                let payload = common.merging(sent) { _, s in s }, name = payload["hook_event_name"] as? String ?? ""
                let ev = name == "PermissionRequest" ? CatKittenHooks.permission(payload: payload, now: at) : CatKittenHooks.event(name: name, payload: payload, now: at)
                if let ev { list = CatKittens.step(list, ev) }
            } else if let inner = step["internal"] as? [String: Any] {
                switch inner["type"] as? String {
                case "resolved": list = CatKittens.step(list, CatKittenHooks.resolved(subagentId: inner["id"] as! String, now: at))
                case "sweep": list = CatKittens.step(list, .sweep(t: at))
                default: list = CatKittens.step(list, .tick(t: at))
                }
            }
            guard let row = pick.firstIndex(of: n + 1) else { continue }
            let top = 28 + Double(row) * rowH
            var kit = KittenScene(lists: ["integration_claude": list], now: at + 300)
            if a.both { kit.lists["agent_codex"] = list }
            CatDraw.text(cg, short("\(n + 1). \(step["say"] as! String)"), x: 14, y: top + 14, size: 10.5, bold: false, color: CatDraw.white(0.8), anchor: .left)
            CatDraw.text(cg, list.map { "\($0.id): \($0.state.rawValue)" }.joined(separator: ", "), x: 14, y: top + 32, size: 9.5, bold: false, color: CatDraw.white(0.5), anchor: .left)
            drawCompact(cg, cast, ox: left, oy: top + 10, kit: kit)
            drawExpanded(cg, cast, ox: left + cw + gap, oy: top, kit: kit)
        }
        return sheet
    }

    // MARK: Small eyes: today's ink eyes next to the coloured ones

    /// Every coat (as a cat, and as a kitten) at the compact sizes, each drawn twice: with the flat ink eyes the compact cats had, and with the coloured small
    /// eyes. Both rest, looking straight ahead, so the sheet shows nothing but the eye.
    @MainActor static func eyeSheet(_ a: Args) -> Sheet {
        let cols: [(d: Double, kitten: Bool)] = [12, 16, 20, 24].map { ($0, false) } + [12, 16, 20].map { ($0, true) }
        func cellW(_ d: Double) -> Double { max(36, d * 1.5 + 12) }
        let left = 120.0, head = 34.0, rowH = 36.0
        let width = left + cols.map { 2 * cellW($0.d) + 6 }.reduce(0, +) + 8
        let sheet = Sheet(width: width, height: head + rowH * Double(a.cats.count) + 6, scale: a.scale)
        let cg = sheet.cg
        var x = left
        for c in cols {
            let w = cellW(c.d)
            CatDraw.text(cg, c.kitten ? "kitten Ø\(Int(c.d))" : "Ø\(Int(c.d))", x: x + w, y: 11, size: 10, bold: true, color: CatDraw.white(0.85))
            CatDraw.text(cg, "ink", x: x + w / 2, y: 25, size: 9, bold: false, color: CatDraw.white(0.5))
            CatDraw.text(cg, "coloured", x: x + w * 1.5, y: 25, size: 9, bold: false, color: CatDraw.white(0.5))
            x += 2 * w + 6
        }
        for (ri, id) in a.cats.enumerated() {
            let top = head + Double(ri) * rowH, p = CatPresets.byID(id)
            CatDraw.text(cg, p.label, x: 12, y: top + rowH / 2, size: 11, bold: true, color: CatDraw.white(0.9), anchor: .left)
            x = left
            for c in cols {
                let w = cellW(c.d), preset = c.kitten ? CatPresets.kitten(of: p) : p
                for (i, ink) in [true, false].enumerated() {
                    var look = CatLook(preset: preset)
                    look.inkEyes = ink
                    cg.fill(CatDraw.roundRect(x + Double(i) * w + 1, top + 2, w - 2, rowH - 4, 6), CatDraw.black(1))
                    CatRenderer.draw(cg, look, cx: x + Double(i) * w + w / 2, cy: top + rowH / 2 + 1, D: c.d, CatDrawOptions(tint: false, badge: false))
                }
                x += 2 * w + 6
            }
        }
        return sheet
    }

    @MainActor static func ladder(_ a: Args) -> Sheet {
        let widths = a.sizes.map(slotW) + a.kittens.map(slotW)
        let sheet = Sheet(width: 150 + widths.reduce(0, +) + 24, height: rowH * Double(a.cats.count) + 8, scale: a.scale)
        let cg = sheet.cg
        for (ri, id) in a.cats.enumerated() {
            let top = Double(ri) * rowH + 4, p = CatPresets.byID(id)
            CatDraw.text(cg, p.label, x: 60, y: top + rowH / 2 - 6, size: 13, bold: true, color: CatDraw.white(0.92))
            CatDraw.text(cg, p.desc ?? id, x: 60, y: top + rowH / 2 + 12, size: 10, bold: false, color: CatDraw.white(0.5))
            var x = 130.0
            let cells: [(Double, CatPreset, String)] = a.sizes.map { ($0, p, "Ø\(Int($0))") } + a.kittens.map { ($0, CatPresets.kitten(of: p), "kitten Ø\(Int($0))") }
            for (d, preset, label) in cells {
                let w = slotW(d), cx = x + w / 2, cy = top + 20 + rowH * 0.42
                cg.fill(CatDraw.roundRect(x + 4, top + 22, w - 8, rowH - 46, 10), CatDraw.black(1))
                CatRenderer.draw(cg, CatLook(preset: preset), cx: cx, cy: cy, D: d)
                CatDraw.text(cg, label, x: cx, y: top + rowH - 10, size: 10, bold: false, color: CatDraw.white(0.55))
                x += w
            }
        }
        return sheet
    }
}
