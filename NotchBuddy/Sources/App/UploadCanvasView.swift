import SwiftUI
import AppKit

// Full 640×176 canvas that drives the upload sequence animation.
// Replaces the header + content area when the upload engine is active.

struct UploadCanvasView: View {
    @ObservedObject var state: AppState
    /// The coat of the cat that catches the file: the cast's, which is the big cat's.
    let cat: String
    @State private var fileIcon: NSImage? = nil
    @StateObject private var driver = UploadCatDriver(engine: .live())

    private var engine: UploadSequenceEngine { .shared }

    var body: some View {
        TimelineView(.animation) { tl in
            let f = engine.frame(at: tl.date)
            let wallTime = tl.date.timeIntervalSinceReferenceDate

            ZStack(alignment: .topLeading) {
                Canvas { ctx, _ in
                    drawScene(ctx: ctx, f: f, wallTime: wallTime)
                }
                .frame(width: 640, height: 176)

                // Interactive choose buttons (invisible hit areas at reference positions)
                if f.chooseAlpha > 0 {
                    chooseOverlay(f: f)
                        .frame(width: 640, height: 176)
                }
            }
        }
        .onChange(of: state.droppedFile?.url) { _, url in
            if let url { loadIcon(url: url) }
        }
        .onAppear {
            if let url = state.droppedFile?.url { loadIcon(url: url) }
        }
        .frame(width: 640, height: 176)
    }

    // MARK: - File icon

    private func loadIcon(url: URL) {
        let img = NSWorkspace.shared.icon(forFile: url.path)
        img.size = NSSize(width: 64, height: 64)
        fileIcon = img
    }

    // MARK: - Choose overlay (transparent SwiftUI buttons over canvas)

    @ViewBuilder
    private func chooseOverlay(f: USFrame) -> some View {
        // Reference positions: button1 x=100 w=176 y=113 h=26, button2 x=284 w=128
        ZStack(alignment: .topLeading) {
            // Primary: "Ask a question about it"
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { state.view = .prompt }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                    UploadSequenceEngine.shared.deactivate()
                }
            } label: {
                Color.clear
                    .frame(width: 168, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: 168, height: 26)
            .position(x: 114 + 84, y: 113 + 13)   // center = (198, 126)

            // Secondary: "Send by email"
            Button {
                withAnimation(.easeInOut(duration: 0.22)) { state.view = .mail }
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.22) {
                    UploadSequenceEngine.shared.deactivate()
                }
            } label: {
                Color.clear
                    .frame(width: 120, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .frame(width: 120, height: 26)
            .position(x: 290 + 60, y: 113 + 13)   // center = (350, 126)
        }
        .opacity(f.chooseAlpha)
        .allowsHitTesting(f.chooseAlpha > 0.5)
    }

    // MARK: - Main draw

    private func drawScene(ctx: GraphicsContext, f: USFrame, wallTime: Double = 0) {
        var c = ctx

        // ── Island background ──────────────────────────────────────
        c.fill(Path(CGRect(x:0, y:0, width:640, height:176)), with: .color(Color.black))

        // ── Card ──────────────────────────────────────────────────
        let cardPath = roundedRect(CGRect(x: USC.CARD_X, y: USC.CARD_Y, width: USC.CARD_W, height: USC.CARD_H), r: USC.CARD_R)

        var cardCtx = c
        cardCtx.clip(to: cardPath)
        cardCtx.fill(Path(CGRect(x: USC.CARD_X, y: USC.CARD_Y, width: USC.CARD_W, height: USC.CARD_H)),
                     with: .color(Color(red:0.051, green:0.055, blue:0.063)))

        // Green glow from card bottom — grows slowly with upload progress
        if f.greenWash > 0 {
            // Center at card bottom edge; gradient fans upward through the card
            let gx = USC.CARD_X + USC.CARD_W/2
            let gy = USC.CARD_Y + USC.CARD_H   // bottom of card
            let gGrad = Gradient(stops: [
                .init(color: Color(red:0.157,green:0.831,blue:0.510).opacity(f.greenWash * 0.90), location:0),
                .init(color: Color(red:0.157,green:0.831,blue:0.510).opacity(f.greenWash * 0.30), location:0.55),
                .init(color: Color(red:0.157,green:0.831,blue:0.510).opacity(0), location:1)
            ])
            cardCtx.fill(Path(CGRect(x:USC.CARD_X,y:USC.CARD_Y,width:USC.CARD_W,height:USC.CARD_H)),
                         with: .radialGradient(gGrad, center:CGPoint(x:gx,y:gy),
                                              startRadius:0, endRadius:USC.CARD_H*1.5))
        }

        // ── Dashed border (animates left→right while on drop zone) ────
        if f.zoneAlpha > 0 {
            var borderCtx = c
            borderCtx.opacity = f.zoneAlpha
            let borderColor = f.zoneOver
                ? Color(red:0.204,green:0.831,blue:0.600).opacity(0.55)
                : Color.white.opacity(0.14)
            let inset = CGRect(x: USC.CARD_X+0.75, y: USC.CARD_Y+0.75,
                               width: USC.CARD_W-1.5, height: USC.CARD_H-1.5)
            // dashPhase increases → pattern marches left-to-right at ~20 pt/s
            let dashPhase = CGFloat(wallTime * 20)
            borderCtx.stroke(roundedRect(inset, r: USC.CARD_R-0.5),
                             with: .color(borderColor),
                             style: StrokeStyle(lineWidth:1.5, dash:[6,5], dashPhase: dashPhase))
        }

        // ── Drop zone text ─────────────────────────────────────────
        if f.zoneAlpha > 0 && f.textAlpha > 0 {
            drawDropText(ctx: &c, f: f)
        }

        // ── Progress bar ──────────────────────────────────────────
        if f.barAlpha > 0 || f.barReveal > 0 {
            drawProgressBar(ctx: &c, f: f)
        }

        // ── Choose view text ─────────────────────────────────────
        if f.chooseAlpha > 0 {
            drawChooseView(ctx: &c, f: f)
        }

        // ── The cat ───────────────────────────────────────────────
        let laid = drawCat(ctx: c, f: f)

        // ── The file: under the pointer while it hovers, then along the flight into the cat's mouth. Drawn after the cat, so in front of it, as in the prototype's catch.
        if f.fileVisible { drawFile(ctx: &c, f: f, cat: laid) }
    }

    // MARK: - Drop zone text + chips

    private func drawDropText(ctx: inout GraphicsContext, f: USFrame) {
        var tCtx = ctx
        tCtx.opacity = f.textAlpha

        let label = Text("Drop your files here")
            .font(.system(size:13, weight:.medium))
            .foregroundColor(Color(hex:"#D5D7DB"))
        tCtx.draw(label, at: CGPoint(x: USC.TEXT_X, y: USC.TEXT_Y - 4), anchor: .leading)

        let chips = ["PDF","Images","Code","Docs"]
        var cx = USC.TEXT_X
        for chip in chips {
            let chipText = Text(chip).font(.system(size:11, weight:.medium)).foregroundColor(Color(hex:"#B9BDC4"))
            // measure approximate width
            let estW = Double(chip.count) * 6.5 + 16
            tCtx.fill(roundedRect(CGRect(x:cx, y:USC.TEXT_Y+9, width:estW, height:18), r:9),
                      with: .color(Color.white.opacity(0.07)))
            tCtx.draw(chipText, at: CGPoint(x: cx + 8, y: USC.TEXT_Y + 18), anchor: .leading)
            cx += estW + 6
        }
    }

    // MARK: - Progress bar

    private func drawProgressBar(ctx: inout GraphicsContext, f: USFrame) {
        var pCtx = ctx
        pCtx.opacity = max(f.barAlpha, 0.001)

        let x0 = USC.BAR_X0, x1 = USC.BAR_X1, by = USC.BAR_Y
        let barLen = (x1-x0) * f.barReveal

        // Filename label
        let name = state.droppedFile?.name ?? "file"
        let label = Text("Uploading \(name)")
            .font(.system(size:12.5, weight:.medium))
            .foregroundColor(Color(hex:"#A9ADB5"))
        pCtx.draw(label, at: CGPoint(x: x0, y: by-30), anchor: .leading)

        // Checkmark or percentage
        if f.check > 0 {
            var ckCtx = pCtx
            ckCtx.concatenate(CGAffineTransform(translationX: CGFloat(x1-8), y: CGFloat(by-30)))
            ckCtx.concatenate(CGAffineTransform(scaleX: CGFloat(f.check), y: CGFloat(f.check)))
            var circle = Path(); circle.addEllipse(in: CGRect(x:-8,y:-8,width:16,height:16))
            ckCtx.fill(circle, with: .color(Color(hex:"#34D399")))
            var ck = Path()
            ck.move(to: CGPoint(x:-3.6,y:0.2)); ck.addLine(to: CGPoint(x:-1,y:2.8)); ck.addLine(to: CGPoint(x:3.8,y:-2.6))
            ckCtx.stroke(ck, with: .color(Color(red:0.027,green:0.075,blue:0.055)),
                         style: StrokeStyle(lineWidth:2, lineCap:.round, lineJoin:.round))
        } else {
            let pct = Text("\(Int(f.progress*100)) %")
                .font(.system(size:12.5, weight:.medium).monospacedDigit())
                .foregroundColor(Color(hex:"#A9ADB5"))
            pCtx.draw(pct, at: CGPoint(x: x1, y: by-30), anchor: .trailing)
        }

        // Bar track
        if barLen > 0 {
            pCtx.fill(roundedRect(CGRect(x:x0, y:by-3, width:barLen, height:6), r:3),
                      with: .color(Color.white.opacity(0.08)))
        }

        // Bar fill
        let fx = usLerp(USC.BAR_X0, USC.BAR_X1, f.progress)
        if fx > x0 + 1 {
            // Flash color at completion
            let flashGreen = Color(
                red:   usLerp(0.204, 0.431, f.flash),
                green: usLerp(0.827, 0.906, f.flash),
                blue:  usLerp(0.600, 0.718, f.flash))
            let fillGrad = Gradient(stops: [
                .init(color: Color(hex:"#1FA87A"), location:0),
                .init(color: flashGreen, location:1)
            ])
            pCtx.fill(roundedRect(CGRect(x:x0, y:by-3, width:fx-x0, height:6), r:3),
                      with: .linearGradient(fillGrad,
                                           startPoint: CGPoint(x:x0, y:0),
                                           endPoint:   CGPoint(x:fx,  y:0)))
        }

        // Glow trail
        if f.progress > 0.01 && f.progress < 1 {
            let v = (usProgressAt(f.t+0.01, progStart:USC.T_PROG_START, progEnd:f.progEnd)
                   - usProgressAt(f.t,      progStart:USC.T_PROG_START, progEnd:f.progEnd)) / 0.01
            let tl = max(8, min(34, 8 + v*40))
            let tGrad = Gradient(stops:[
                .init(color: Color(red:0.204,green:0.831,blue:0.600,opacity:0), location:0),
                .init(color: Color(red:0.431,green:0.906,blue:0.718,opacity:0.6), location:1)
            ])
            var glowCtx = pCtx
            glowCtx.addFilter(.blur(radius:3))
            glowCtx.fill(roundedRect(CGRect(x:fx-tl, y:by-4, width:tl, height:8), r:4),
                         with: .linearGradient(tGrad,
                                              startPoint:CGPoint(x:fx-tl,y:0),
                                              endPoint:  CGPoint(x:fx,y:0)))
        }
    }

    // MARK: - Choose view text + buttons (canvas layer)

    private func drawChooseView(ctx: inout GraphicsContext, f: USFrame) {
        var cCtx = ctx
        cCtx.opacity = f.chooseAlpha
        // Slide up: translate down by (1-alpha)*4
        cCtx.concatenate(CGAffineTransform(translationX: 0, y: CGFloat((1-f.chooseAlpha)*4)))

        let name = state.droppedFile?.name ?? "file"
        let titleText = Text("\(name) is ready.")
            .font(.system(size:14, weight:.semibold))
            .foregroundColor(Color(hex:"#F5F6F8"))
        cCtx.draw(titleText, at: CGPoint(x:114, y:80), anchor: .leading)

        let subText = Text("What do you want to do with it?")
            .font(.system(size:12.5))
            .foregroundColor(Color(hex:"#9398A1"))
        cCtx.draw(subText, at: CGPoint(x:114, y:100), anchor: .leading)

        // Primary button (white fill)
        cCtx.fill(roundedRect(CGRect(x:114,y:113,width:168,height:26), r:13),
                  with: .color(Color(hex:"#F5F6F8")))
        let btn1 = Text("Ask a question about it")
            .font(.system(size:12.5, weight:.medium))
            .foregroundColor(Color(red:0.043,green:0.047,blue:0.055))
        cCtx.draw(btn1, at: CGPoint(x:198, y:126), anchor: .center)

        // Secondary button (dim fill)
        cCtx.fill(roundedRect(CGRect(x:290,y:113,width:120,height:26), r:13),
                  with: .color(Color.white.opacity(0.09)))
        let btn2 = Text("Send by email")
            .font(.system(size:12.5, weight:.medium))
            .foregroundColor(Color(hex:"#F1F2F4"))
        cCtx.draw(btn2, at: CGPoint(x:350, y:126), anchor: .center)

        // Who will read the file if asked (or why it can't be read), beside the buttons.
        if let reader = state.dropReaderLine {
            // Up to the card's right edge minus its 18 pt padding (as in the island's own drop card).
            let x: CGFloat = 422
            let room = CGFloat(USC.CARD_X + USC.CARD_W - 18) - x
            cCtx.draw(fitted(reader, maxWidth: room, in: cCtx), at: CGPoint(x: x, y: 126), anchor: .leading)
        }
    }

    /// Canvas text can't truncate itself: the reader line, cut in the middle with "…" until it fits `maxWidth`
    /// (the island's drop card does the same with `.truncationMode(.middle)`).
    private func fitted(_ line: String, maxWidth: CGFloat, in ctx: GraphicsContext) -> GraphicsContext.ResolvedText {
        func resolve(_ s: String) -> GraphicsContext.ResolvedText {
            ctx.resolve(Text(s).font(.system(size:12.5)).foregroundColor(Color(hex:"#9398A1")))
        }
        func width(_ t: GraphicsContext.ResolvedText) -> CGFloat {
            t.measure(in: CGSize(width: CGFloat.infinity, height: CGFloat.infinity)).width
        }
        let full = resolve(line)
        if width(full) <= maxWidth { return full }
        let chars = Array(line)
        func shortened(_ kept: Int) -> String { String(chars.prefix((kept + 1) / 2)) + "…" + String(chars.suffix(kept / 2)) }
        var lo = 0, hi = chars.count   // the most characters that still fit
        while lo < hi {
            let mid = (lo + hi + 1) / 2
            if width(resolve(shortened(mid))) <= maxWidth { lo = mid } else { hi = mid - 1 }
        }
        return resolve(shortened(lo))
    }

    // MARK: - The cat (the mouth catch)

    /// Draws the cat where the sequence puts it and returns its layout (the file's flight ends at the mouth in it). The driver steps the cat first.
    private func drawCat(ctx: GraphicsContext, f: USFrame) -> CatGeometry.Layout? {
        // The big cat is on the desktop (or in the air): it flies in to catch the file, and until it has landed the island draws no cat of its own (never two cats). The file under the pointer
        // still draws. At home `notchEmpty` is false and this is the shipping canvas.
        if state.desktopPhase.notchEmpty { return nil }
        let catEngine = driver.engine
        catEngine.useCharacter(cat)   // the cast's coat
        driver.follow(f, file: state.droppedFile?.name ?? "file")
        var laid: CatGeometry.Layout?
        // The sequence's squeeze rides along once the cat is a dot on the progress bar; the catch's own squash does the rest.
        let squeezeX = f.t >= USC.T_SHRINK_END ? f.sx : 1, squeezeY = f.t >= USC.T_SHRINK_END ? f.sy : 1
        var look = catEngine.look()
        look.pose.sx *= squeezeX; look.pose.sy *= squeezeY; look.pose.tilt += f.tilt
        look.badge = nil
        var options = CatDrawOptions(fur: catEngine.cfg.furLines)
        // The big cat catches the file in the outfit it wears everywhere else; the scene is the island's own canvas, so its top (y 0) is the island's top.
        options.outfit = CatOutfitDraw.big(catEngine.cfg.outfit, dpr: Double(ctx.environment.displayScale), ceiling: 0)
        ctx.withCGContext { cg in
            laid = CatRenderer.draw(cg, look, cx: f.x, cy: f.y + f.hop, D: f.d, options)
        }
        if let L = laid { catEngine.base = L.base; catEngine.mouthPoint = L.mouth }
        return laid
    }

    // MARK: - The file: under the pointer, then in flight

    /// While the file is still dragged over the island it sits under the pointer. After the drop it arcs into the cat's mouth along the contract's
    /// flight (`CatGreeting.flightAt`, 380 ms, from the drop to the arrival: `T_DROP` to `T_SUCK_END`), in front of the cat, as in the prototype. The
    /// icon leaves the pointer at the size it had there and shrinks as the flight does, so it does not jump.
    private func drawFile(ctx: inout GraphicsContext, f: USFrame, cat L: CatGeometry.Layout?) {
        let cx = f.cursorX, cy = f.cursorY + 14
        guard f.dropped else {
            var fc = ctx; fc.opacity = 0.92
            drawDoc(ctx: &fc, cx: cx, cy: cy, wsc: 1, hsc: 1)
            return
        }
        guard let L, let m = L.mouth, L.R > 0 else { return }
        let w = CatGreeting.flightAt(from: (x: cx, y: cy), to: (x: m.x, y: m.y), R: L.R, k: usSeg(f.t, USC.T_DROP, USC.T_SUCK_END))
        let s = w.size / (0.62 * L.R)   // the flight shrinks the file from 0.62 R to 0.14 R: 1 down to 0.23 of its size under the pointer
        let icon = fileIcon
        ctx.withCGContext { cg in
            cg.saveGState()
            cg.translateBy(x: w.x, y: w.y)
            cg.rotate(by: w.rot)
            cg.translateBy(x: -w.x, y: -w.y)
            drawDocCG(cg: cg, cx: w.x, cy: w.y, wsc: s, hsc: s, fileIcon: icon)
            cg.restoreGState()
        }
    }

    // MARK: - Doc icon (SwiftUI wrapper)

    private func drawDoc(ctx: inout GraphicsContext, cx: Double, cy: Double, wsc: Double, hsc: Double) {
        let w = 34*wsc, h = 42*hsc
        let x = cx-w/2, y = cy-h/2
        let fold = 8*min(wsc,hsc)

        var bodyCtx = ctx
        bodyCtx.addFilter(.shadow(color:.black.opacity(0.45), radius:8, x:0, y:3))
        var body = Path()
        body.move(to: CGPoint(x:x+2,y:y))
        body.addLine(to: CGPoint(x:x+w-fold,y:y))
        body.addLine(to: CGPoint(x:x+w,y:y+fold))
        body.addLine(to: CGPoint(x:x+w,y:y+h-2))
        body.addQuadCurve(to: CGPoint(x:x+w-2,y:y+h), control:CGPoint(x:x+w,y:y+h))
        body.addLine(to: CGPoint(x:x+2,y:y+h))
        body.addQuadCurve(to: CGPoint(x:x,y:y+h-2), control:CGPoint(x:x,y:y+h))
        body.addLine(to: CGPoint(x:x,y:y+2))
        body.addQuadCurve(to: CGPoint(x:x+2,y:y), control:CGPoint(x:x,y:y))
        body.closeSubpath()
        bodyCtx.fill(body, with: .color(Color(red:0.957,green:0.957,blue:0.965)))

        var foldPath = Path()
        foldPath.move(to: CGPoint(x:x+w-fold,y:y))
        foldPath.addLine(to: CGPoint(x:x+w-fold,y:y+fold))
        foldPath.addLine(to: CGPoint(x:x+w,y:y+fold))
        ctx.fill(foldPath, with: .color(Color(red:0.835,green:0.839,blue:0.859)))

        ctx.fill(roundedRect(CGRect(x:x+w*0.18,y:y+h*0.58,width:w*0.64,height:h*0.16),r:2),
                 with: .color(Color(red:0.231,green:0.510,blue:0.961)))
    }
}

// MARK: - Doc icon in CGContext (for the file in flight)

private func drawDocCG(cg: CGContext, cx: Double, cy: Double, wsc: Double, hsc: Double, fileIcon: NSImage?) {
    let w = 34*wsc, h = 42*hsc
    let x = cx-w/2, y = cy-h/2
    let fold = 8.0*min(wsc,hsc)

    // Use real file icon if available
    if let icon = fileIcon,
       let cgImg = icon.cgImage(forProposedRect: nil, context: nil, hints: nil) {
        cg.saveGState()
        cg.setShadow(offset: CGSize(width:0,height:3), blur:8, color: CGColor(gray:0, alpha:0.45))
        let rect = CGRect(x:x, y:y, width:w, height:h)
        cg.draw(cgImg, in: rect)
        cg.restoreGState()
        return
    }

    // Generic document shape
    cg.saveGState()
    cg.setShadow(offset: CGSize(width:0,height:3), blur:8, color: CGColor(gray:0, alpha:0.45))
    cg.setFillColor(CGColor(red:0.957,green:0.957,blue:0.965,alpha:1))
    let bp = CGMutablePath()
    bp.move(to: CGPoint(x:x+2,y:y))
    bp.addLine(to: CGPoint(x:x+w-fold,y:y))
    bp.addLine(to: CGPoint(x:x+w,y:y+fold))
    bp.addLine(to: CGPoint(x:x+w,y:y+h-2))
    bp.addQuadCurve(to: CGPoint(x:x+w-2,y:y+h), control:CGPoint(x:x+w,y:y+h))
    bp.addLine(to: CGPoint(x:x+2,y:y+h))
    bp.addQuadCurve(to: CGPoint(x:x,y:y+h-2), control:CGPoint(x:x,y:y+h))
    bp.addLine(to: CGPoint(x:x,y:y+2))
    bp.addQuadCurve(to: CGPoint(x:x+2,y:y), control:CGPoint(x:x,y:y))
    bp.closeSubpath()
    cg.addPath(bp); cg.fillPath()
    cg.restoreGState()

    // Fold
    cg.setFillColor(CGColor(red:0.835,green:0.839,blue:0.859,alpha:1))
    let fp = CGMutablePath()
    fp.move(to: CGPoint(x:x+w-fold,y:y)); fp.addLine(to: CGPoint(x:x+w-fold,y:y+fold)); fp.addLine(to: CGPoint(x:x+w,y:y+fold))
    cg.addPath(fp); cg.fillPath()

    // Blue accent line
    cg.setFillColor(CGColor(red:0.231,green:0.510,blue:0.961,alpha:1))
    cg.addRect(CGRect(x:x+w*0.18, y:y+h*0.58, width:w*0.64, height:h*0.16))
    cg.fillPath()
}

// MARK: - Rounded rect helper (mirrors reference rr())

func roundedRect(_ rect: CGRect, r rr: Double) -> Path {
    let r = max(0, min(rr, Double(rect.width)/2, Double(rect.height)/2))
    var p = Path()
    p.addRoundedRect(in: rect, cornerSize: CGSize(width:r, height:r))
    return p
}
