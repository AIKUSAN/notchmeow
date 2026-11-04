import AppKit
import SwiftUI

// Draws the companion's chat pictures (F3a-mac, Task 10) without launching NotchMeow: the app's own views (PromptView in the island and in its window, PoppedOutNote,
// the conversation list, QuickResultCard, ClaudeLevelChip and ClaudeLevelMenu, ModelPickerView, the one-time cloud line in a reply's note) are drawn from invented data.
// The chat history, the quick result and the chat's pane are set on AppState; the stored conversations go through the app's own store, which lives in the render's
// home folder (--home: scripts/render-home-guard.sh points Foundation there, and this tool stops if the store would be anywhere else). Nothing is read from the pasteboard,
// the owner's defaults or the owner's home folder. The island pictures have the big cat beside the chat as the island draws it (the cat helper is render-sidekick's).
//   bash scripts/render-companion.sh --out DIR [--scale 2]
// Run it through the .sh: it compiles every file of the app but NotchBuddyApp.swift, and runs in a home folder of its own.
// Disclosed, not hidden: the app's views read the Keychain on appear (AIService.prewarm reaches KeychainStore.shared, read-only), and ModelPickerView.onAppear may probe
// 127.0.0.1 local-model ports. Nothing from those reads is printed, drawn, sent or stored. See scripts/render-companion.sh.

@main
struct RenderCompanion {
    final class Clock { var t = 0.0 }

    /// An invented folder: the chip and the menu show only its last part.
    static let sampleFolder = "/Projects/site"

    // MARK: - Invented data

    @MainActor static func message(_ role: ChatRole, _ text: String, caption: String? = nil, notice: String? = nil) -> ChatMessage {
        ChatMessage(role: role, content: text, caption: caption, notice: notice)
    }

    static let local = "local · qwen3.5:2b"

    /// Six messages: the chat as a short talk. Computed, since a chat message is not a constant that Swift 6 lets a static hold.
    @MainActor static var thread6: [ChatMessage] { [
        message(.user, "What should I look at first today?"),
        message(.assistant, "Start with the two notes waiting for you: the copy for the site's contact page, and the list of fixes from Sam's review.", caption: local),
        message(.user, "Which of the two is quicker?"),
        message(.assistant, "The contact page. It is three sentences and one link.", caption: local),
        message(.user, "Good. Draft it in the notes file."),
        message(.assistant, "Done. The draft is in notes, under Contact, with the old wording kept below it.", caption: local),
    ] }

    /// Twelve messages: the six above and six more.
    @MainActor static var thread12: [ChatMessage] { thread6 + [
        message(.user, "Make the contact line shorter."),
        message(.assistant, "Shorter: \u{2018}Write to Sam any time, and expect a reply within a day.\u{2019}", caption: local),
        message(.user, "Thanks. And the list for Friday?"),
        message(.assistant, "Three items: the parser fix, the site review and the notes export.", caption: local),
        message(.user, "Put them in order of effort."),
        message(.assistant, "Notes export first, then the parser fix, then the review, which takes longest.", caption: local),
    ] }

    /// The one-time line a cloud brain's first reply carries (ClaudeService joins it under the reply's own note).
    static let cloudLine = CompanionRightNow.cloudNotice(provider: "Claude")

    /// Four stored conversations, saved through the store: one pinned, the rest newest first after it.
    @MainActor static func seed(_ store: CompanionStore, now: Int) throws {
        let hour = 3_600_000, day = 24 * hour
        let rows: [(title: String, age: Int, pinned: Bool, lines: [(String, String)])] = [
            ("Plan for the week", 2 * hour, true, [("user", "Sketch the week in three lines."), ("assistant", "Monday: the site copy. Tuesday: the review. Friday: the notes export.")]),
            ("Site copy review", day, false, [("user", "Read the contact page."), ("assistant", "Two lines are long. The rest reads well.")]),
            ("Shopping list", 3 * day, false, [("user", "Make a list for the week."), ("assistant", "Milk, oats, lemons, and the good coffee.")]),
            ("Parser notes", 6 * day, false, [("user", "Why does the parser stop at the comma?"), ("assistant", "The rule treats a comma as the end of a field.")]),
        ]
        for row in rows {
            let c = CompanionConversation(id: UUID().uuidString.lowercased(), title: row.title, pinned: row.pinned,
                                          createdAt: now - row.age - hour, updatedAt: now - row.age,
                                          messages: row.lines.map { CompanionMessage(role: $0.0, text: $0.1, caption: "", files: []) })
            try store.save(c)
        }
    }

    // MARK: - Drawing

    /// The big cat, as render-sidekick draws it: a few frames of the engine by hand, then the renderer.
    @MainActor static func bigCat(_ cg: CGContext, coat: String, state: CatState, colour: String, cx: Double, cy: Double, d: Double) {
        let clock = Clock(), rng = CatRNG(seed: 3), preset = CatPresets.byID(coat)
        let e = CatEngine(preset, mini: false, now: { clock.t }, rand: { rng.next() }, cfg: CatConfig(motion: "playful"), quiet: true, state: state)
        func place() { let L = CatGeometry.layout(preset, e.s, cx: 0, cy: 0, D: d); e.base = L.base; e.mouthPoint = L.mouth }
        place()
        for _ in 0..<72 { clock.t += 1000.0 / 60; e.update(dt: 1.0 / 60); place() }
        e.collar = CatRules.bigCatCollar(colour: colour, state: state)
        CatRenderer.draw(cg, e.look(time: clock.t / 1000), cx: cx, cy: cy, D: d, CatDrawOptions(badge: true))
    }

    /// The view hosted in a window that is never shown, drawn at `scale`. A ScrollView draws only through AppKit, so ImageRenderer is not used here.
    /// `height` nil takes the view's own fitted height.
    @MainActor static func snapshot<V: View>(_ view: V, width: CGFloat, height: CGFloat?, scale: CGFloat) -> CGImage? {
        let fitted = NSHostingView(rootView: view.frame(width: width)).fittingSize.height
        let h = height ?? fitted.rounded(.up)
        let host = NSHostingView(rootView: view.frame(width: width, height: h))
        host.frame = NSRect(x: 0, y: 0, width: width, height: h)
        let win = NSWindow(contentRect: host.frame, styleMask: [.titled], backing: .buffered, defer: false)
        win.appearance = NSAppearance(named: .darkAqua)
        win.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.6))
        host.layoutSubtreeIfNeeded()
        defer { withExtendedLifetime(win) {} }
        guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: Int((width * scale).rounded()), pixelsHigh: Int((h * scale).rounded()),
                                         bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false, colorSpaceName: .deviceRGB,
                                         bytesPerRow: 0, bitsPerPixel: 0) else { return nil }
        rep.size = host.bounds.size
        host.cacheDisplay(in: host.bounds, to: rep)
        return rep.cgImage
    }

    /// The island as the app draws the chat: black, the view filling the island's size, the island's corners, and the big cat where the island puts it.
    @MainActor static func island<V: View>(_ view: V, height: CGFloat, scale: CGFloat) -> CGImage? {
        let w = IslandConst.expandedWidth
        let shape = ZStack(alignment: .topLeading) {
            Color.black
            view.frame(width: w, height: height, alignment: .topLeading)
        }
        .frame(width: w, height: height, alignment: .topLeading)
        .foregroundColor(Color(hex: "#F5F6F8"))
        .clipShape(UnevenRoundedRectangle(bottomLeadingRadius: IslandConst.expandedCorner, bottomTrailingRadius: IslandConst.expandedCorner))
        guard let shot = snapshot(shape, width: w, height: height, scale: scale) else { return nil }
        let (botX, botY, botD, _) = botPosition(mode: .expanded, view: .prompt, islandW: w, islandH: height, uploadProgress: 0)
        guard let cg = CGContext(data: nil, width: shot.width, height: shot.height, bitsPerComponent: 8, bytesPerRow: 0,
                                 space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        cg.draw(shot, in: CGRect(x: 0, y: 0, width: shot.width, height: shot.height))
        cg.translateBy(x: 0, y: CGFloat(shot.height))
        cg.scaleBy(x: scale, y: -scale)
        bigCat(cg, coat: "shrimpy", state: .idle, colour: "#E07950", cx: Double(botX), cy: Double(botY), d: Double(botD))
        return cg.makeImage()
    }

    /// Stacks pictures one above the other on the page's dark, 16 pt round and 12 pt apart (in pixels: the points times `scale`).
    @MainActor static func stack(_ images: [CGImage], scale: CGFloat) -> CGImage? {
        let margin = 16 * scale, gap = 12 * scale
        let W = CGFloat(images.map(\.width).max() ?? 0) + 2 * margin
        let H = images.reduce(margin) { $0 + CGFloat($1.height) + gap }
        guard let cg = CGContext(data: nil, width: Int(W), height: Int(H), bitsPerComponent: 8, bytesPerRow: 0,
                                 space: CGColorSpace(name: CGColorSpace.sRGB)!, bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        cg.setFillColor(CGColor(srgbRed: 0.059, green: 0.063, blue: 0.071, alpha: 1))
        cg.fill(CGRect(x: 0, y: 0, width: W, height: H))
        var y = H - margin
        for img in images {
            y -= CGFloat(img.height)
            cg.draw(img, in: CGRect(x: margin, y: y, width: CGFloat(img.width), height: CGFloat(img.height)))
            y -= gap
        }
        return cg.makeImage()
    }

    /// Writes one picture as PNG and says where it went and how big it is in points.
    static func save(_ image: CGImage?, _ name: String, in dir: URL, pointWidth: CGFloat, pointHeight: CGFloat) {
        guard let image, let png = NSBitmapImageRep(cgImage: image).representation(using: .png, properties: [:]) else {
            FileHandle.standardError.write(Data("could not draw \(name)\n".utf8))
            exit(1)
        }
        let url = dir.appendingPathComponent(name)
        try! png.write(to: url)
        print("wrote \(url.path) (\(Int(pointWidth)) × \(Int(pointHeight)) pt)")
    }

    // MARK: - The pictures

    @MainActor static func main() {
        var out = "", home = "", scale: CGFloat = 2
        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let k = it.next() {
            switch k {
            case "--out": out = it.next() ?? ""
            case "--scale": scale = CGFloat(Double(it.next() ?? "") ?? Double(scale))
            case "--home": home = it.next() ?? ""
            default:
                FileHandle.standardError.write(Data("unknown argument \(k)\n".utf8))
                exit(2)
            }
        }
        guard !out.isEmpty, !home.isEmpty else {
            FileHandle.standardError.write(Data("usage: render-companion --out DIR [--scale N] --home FAKE_HOME\n".utf8))
            exit(2)
        }
        // The store must be in the render's own home folder. Nothing is drawn or saved if it would be anywhere else (the message names no path).
        let storeRoot = CompanionFiles.standard().root.resolvingSymlinksInPath().path
        let fakeHome = URL(fileURLWithPath: home).resolvingSymlinksInPath().path
        guard storeRoot.hasPrefix(fakeHome + "/") else {
            FileHandle.standardError.write(Data("the companion store would not be in the render's own folder; nothing drawn\n".utf8))
            exit(1)
        }
        let dir = URL(fileURLWithPath: out, isDirectory: true)
        try! FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)

        _ = NSApplication.shared
        let state = AppState.shared
        let store = Companion.shared.store
        do { try seed(store, now: Int(Date().timeIntervalSince1970 * 1000)) } catch {
            FileHandle.standardError.write(Data("could not save the sample conversations\n".utf8))
            exit(1)
        }
        let w = IslandConst.expandedWidth
        let user = message(.user, "Fix this line: the meeting moved to thursday so bring the draft.")

        // The window: the chat in its own 520 × 640 window (no cat gutter; the island's note stands in for it while it is out).
        state.chatPoppedOut = true
        state.chatHistory = thread6
        save(snapshot(PromptView(state: state, inWindow: true), width: 520, height: 640, scale: scale), "window.png", in: dir, pointWidth: 520, pointHeight: 640)

        // The island's note while the chat is in its window.
        state.chatHistory = []
        let poppedH = ChatSizing.islandHeight(messages: 0)
        save(island(PoppedOutNote(state: state), height: poppedH, scale: scale), "popped.png", in: dir, pointWidth: w, pointHeight: poppedH)
        state.chatPoppedOut = false

        // The island's chat at 1, 6 and 12 messages: 280, 480 and 560 pt high, the width unchanged.
        for (name, messages) in [("chat-1.png", Array(thread6.prefix(1))), ("chat-6.png", thread6), ("chat-12.png", thread12)] {
            state.chatHistory = messages
            let h = ChatSizing.islandHeight(messages: messages.count)
            save(island(PromptView(state: state), height: h, scale: scale), name, in: dir, pointWidth: w, pointHeight: h)
        }

        // The saved conversations, in the chat's pane.
        state.chatHistory = [user]
        state.chatPane = .conversations
        let listH = ChatSizing.islandHeight(messages: 1)
        save(island(PromptView(state: state), height: listH, scale: scale), "conversations.png", in: dir, pointWidth: w, pointHeight: listH)
        state.chatPane = .chat

        // A Fix result: Replace (the source app is this one, for the picture), Copy, the close button and the cut note.
        state.quickResult = QuickResult(kind: "fix", text: "The meeting moved to Thursday, so please bring the draft.", running: false, cut: true,
                                        note: nil, sourcePID: getpid())
        state.chatHistory = Array(thread6.prefix(1))   // one message: the 280 pt island, the worst case for the card
        let quickH = ChatSizing.islandHeight(messages: 1)
        save(island(PromptView(state: state), height: quickH, scale: scale), "quick.png", in: dir, pointWidth: w, pointHeight: quickH)
        state.quickResult = nil

        // The Folder control and its menu for each level, one above the other.
        var folders: [CGImage] = []
        for level in [ClaudeCodeLevel.chatOnly, .readOnly(folder: sampleFolder), .agent(folder: sampleFolder)] {
            state.claudeLevel = level
            let block = VStack(alignment: .leading, spacing: 10) {
                ClaudeLevelChip(state: state)
                ClaudeLevelMenu(state: state, isPresented: .constant(true)).frame(width: 290)
            }
            .padding(14)
            .background(Color(hex: "#16171B"))
            if let img = snapshot(block, width: 320, height: nil, scale: scale) { folders.append(img) }
        }
        guard folders.count == 3, let folder = stack(folders, scale: scale) else {
            FileHandle.standardError.write(Data("could not draw folder.png\n".utf8))
            exit(1)
        }
        save(folder, "folder.png", in: dir, pointWidth: 320, pointHeight: CGFloat(folder.height) / scale)
        state.claudeLevel = .chatOnly

        // The model picker, with the Claude plan row (the Claude Code status is ready: the row is there).
        state.claudeCodeEnabled = true
        state.claudeCodeStatus = ClaudeCodeStatus(state: .signedIn)
        // The popover is drawn on the island's dark appearance; ImageRenderer has no window to take it from, so the scheme is set here.
        let picker = ModelPickerView(state: state, isPresented: .constant(true))
            .frame(width: 300)
            .environment(\.colorScheme, .dark)
        let pickerRenderer = ImageRenderer(content: picker)
        pickerRenderer.scale = scale
        pickerRenderer.isOpaque = true
        let pickerH = pickerRenderer.cgImage.map { CGFloat($0.height) / scale } ?? 0
        save(pickerRenderer.cgImage, "picker.png", in: dir, pointWidth: 300, pointHeight: pickerH)
        state.claudeCodeEnabled = false
        state.claudeCodeStatus = .notInstalled

        // A reply with the one-time cloud line under its own note.
        state.chatHistory = [
            message(.user, "Look at this week's plan with me."),
            message(.assistant, "The plan has three days in it. Monday and Tuesday are set, and Friday still needs a title.", caption: "cloud · Claude Sonnet 5.5",
                    notice: cloudLine),
        ]
        let cloudH = ChatSizing.islandHeight(messages: 2)
        save(island(PromptView(state: state), height: cloudH, scale: scale), "cloud-line.png", in: dir, pointWidth: w, pointHeight: cloudH)

        state.chatHistory = []
    }
}
