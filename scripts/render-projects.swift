import AppKit
import SwiftUI

// Draws the Projects views (sub-project P-mac, Task 6) without launching NotchMeow: the app's own views (NotchBuddy/Sources/App/ProjectsViews.swift) go through ImageRenderer
// into PNGs (the peek and the screen go through an AppKit host, for the measured frame and the scroll). The data is the scenarios of tests/fixtures/mac/projects-scenarios.json
// replayed through ProjectsModel, which feeds ProjectsRegistry; nothing is a hand-made row. Every string a picture shows is checked for a path separator, and the
// peek's drawn frame is checked against the left card's, and its "+N more" line against the project's lines; the tool exits 1 when a check fails. Run it through scripts/render-projects.sh:
//   bash scripts/render-projects.sh --all --out DIR            the pictures
//   bash scripts/render-projects.sh --check                    every check, no pictures: the strings, the peek's frame and its lines
//   bash scripts/render-projects.sh --frame-check              the peek's checks alone
//   bash scripts/render-projects.sh --text-check               the string check alone
//   bash scripts/render-projects.sh --reorder-check            the grid and the section hosted with [A, B, C] then [C, A, B]: each project's reported frame follows it

/// The same helpers the app has in IslandRootView.swift and IslandViewContent.swift (those files need the whole app; the sheets do not).
extension Color {
    init(hex: String) {
        let h = hex.trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        let val = UInt64(h, radix: 16) ?? 0
        self.init(red: Double((val >> 16) & 0xFF) / 255, green: Double((val >> 8) & 0xFF) / 255, blue: Double(val & 0xFF) / 255)
    }

    func lighter(by amount: Double) -> Color {
        guard let components = NSColor(self).usingColorSpace(.sRGB) else { return self }
        return Color(
            red: min(1, Double(components.redComponent) + amount),
            green: min(1, Double(components.greenComponent) + amount),
            blue: min(1, Double(components.blueComponent) + amount)
        )
    }
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(1)
}

@MainActor
enum Shot {
    static func save<V: View>(_ view: V, to url: URL) {
        let r = ImageRenderer(content: view)
        r.scale = 2
        r.isOpaque = true
        guard let cg = r.cgImage, let png = NSBitmapImageRep(cgImage: cg).representation(using: .png, properties: [:]) else {
            fail("could not draw \(url.lastPathComponent)")
        }
        try! png.write(to: url)
        print("wrote \(url.path)")
    }

    /// The same picture drawn by AppKit: the view is hosted in a window that is never shown. ImageRenderer leaves a ScrollView empty, and the app's Projects screen
    /// scrolls, so the screen's pictures are drawn this way (render-shelf's panel does the same). The views' `onAppear` runs here, so a frame read there is the drawn one.
    /// `url` nil lays the view out and lets it appear, and writes no file (the checks read what the views report, and need no picture).
    @discardableResult
    static func hosted<V: View>(_ view: V, to url: URL?, scrollToEnd: Bool = false) -> NSView {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = host
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        host.layoutSubtreeIfNeeded()
        if scrollToEnd, let scroll = scrollView(in: host), let doc = scroll.documentView {
            // The end of the list: the document's bottom edge at the visible area's bottom.
            let y = doc.isFlipped ? max(0, doc.frame.height - scroll.contentView.bounds.height) : 0
            scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
            scroll.reflectScrolledClipView(scroll.contentView)
            host.layoutSubtreeIfNeeded()
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
        }
        guard let url else { return host }
        guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { fail("could not draw \(url.lastPathComponent)") }
        host.cacheDisplay(in: host.bounds, to: rep)
        guard let png = rep.representation(using: .png, properties: [:]) else { fail("could not draw \(url.lastPathComponent)") }
        try! png.write(to: url)
        print("wrote \(url.path)")
        return host
    }

    /// The view hosted in a window that is never shown, and the window with it: `hosted` lets its window go when it returns, which takes the views out of the tree
    /// (their `onDisappear` fires). A check that changes what the view draws and reads what it reported must keep both alive; `settle` lets the layout and the `onAppear`s run.
    static func held<V: View>(_ view: V) -> (host: NSHostingView<V>, window: NSWindow) {
        let host = NSHostingView(rootView: view)
        host.frame = NSRect(origin: .zero, size: host.fittingSize)
        let win = NSWindow(contentRect: host.frame, styleMask: [.borderless], backing: .buffered, defer: false)
        win.contentView = host
        settle(host)
        return (host, win)
    }

    static func settle(_ host: NSView) {
        host.layoutSubtreeIfNeeded()
        RunLoop.current.run(until: Date().addingTimeInterval(0.5))
        host.layoutSubtreeIfNeeded()
    }

    /// The first NSScrollView under `view` (a SwiftUI ScrollView is one in a hosting view), or nil.
    static func scrollView(in view: NSView) -> NSScrollView? {
        if let s = view as? NSScrollView { return s }
        for sub in view.subviews { if let s = scrollView(in: sub) { return s } }
        return nil
    }
}

/// What the drawn views report, in the island's coordinates: the frames by name, and what each drawn line is (`onDrawn`: "line" with its id, or "more" with its text).
@MainActor
final class FrameLog {
    var frames: [String: CGRect] = [:]
    var drawn: [(kind: String, text: String)] = []
}

/// The island's rectangles, from ProjectsLayout's numbers: the left card (the overview's), the right card 10 pt after it, and the peek, which is the left card.
enum Island {
    static let leftRect = CGRect(origin: ProjectsLayout.leftCardOrigin, size: CGSize(width: ProjectsLayout.leftCardWidth, height: ProjectsLayout.leftCardHeight))
    static let rightRect = CGRect(x: leftRect.maxX + 10, y: leftRect.minY, width: ProjectsLayout.islandWidth - 10 - leftRect.maxX - 10, height: leftRect.height)
}

extension View {
    /// The view drawn at a rectangle of the island: sized to it, then placed by its centre. `name` reads the frame it lays out in, into `log`.
    func placed(_ r: CGRect, _ name: String? = nil, _ log: FrameLog? = nil) -> some View {
        self.frame(width: r.width, height: r.height)
            .background(GeometryReader { geo in
                Color.clear.onAppear {
                    if let name, let log { log.frames[name] = geo.frame(in: .named("nm.island")) }
                }
            })
            .position(x: r.midX, y: r.midY)
    }
}

/// The clock the model reads: the test's own, set at each step.
@MainActor
final class SketchClock {
    var t: Double
    init(_ t: Double) { self.t = t }
}

/// The fixture's scenarios replayed through the model, as the model's own test replays them: each step's event at its time, then the layout read.
@MainActor
enum Replay {
    static let base = 1_760_000_000_000.0
    static let fixturePath = "tests/fixtures/mac/projects-scenarios.json"
    /// Folders for the seventh-project picture: each one starts a session after the scenario's last step.
    static let extraFolders = ["alpha", "beta", "gamma", "delta"]

    static func root() -> [String: Any] {
        guard let data = try? Data(contentsOf: URL(fileURLWithPath: fixturePath)),
              let json = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else {
            fail("could not read \(fixturePath); run through scripts/render-projects.sh from the repository")
        }
        return json
    }

    static func home() -> String { root()["home"] as? String ?? "/Users/sam" }

    static func steps(_ name: String) -> [[String: Any]] {
        guard let sc = (root()["scenarios"] as? [String: Any])?[name] as? [String: Any], let list = sc["steps"] as? [[String: Any]] else {
            fail("no scenario named \(name)")
        }
        return list
    }

    static func num(_ x: Any?) -> Double { (x as? NSNumber)?.doubleValue ?? 0 }

    static func quietSchedule(_ afterMs: Double, _ fire: @escaping @MainActor () -> Void) -> ProjectsModel.Cancel { { } }

    /// The model after the scenario's first `count` steps. `extra` more folders start a session each after them (seven projects with 3). `busy` adds five more
    /// sessions in notchmeow and three subagents of its main session, all as hook events: a project with more lines than the peek holds.
    static func model(_ name: String, count: Int, extra: Int = 0, busy: Bool = false, pairs: Bool = false) -> ProjectsModel {
        let clock = SketchClock(base)
        let home = home()
        let model = ProjectsModel(home: home, now: { clock.t }, schedule: quietSchedule)
        let all = steps(name)
        for step in all.prefix(count) {
            clock.t = base + num(step["at"])
            if var p = step["event"] as? [String: Any] {
                if let cwd = p["cwd"] as? String, cwd == "~" || cwd.hasPrefix("~/") { p["cwd"] = home + String(cwd.dropFirst()) }
                model.feed(payload: p, waitIn: step["waitIn"] as? String)
            }
            model.refreshLayout(activePills: ["integration_claude"], open: false, focusId: "integration_claude", twoCats: false)
        }
        let last = all.prefix(count).last.map { num($0["at"]) } ?? 0
        for k in 0..<min(extra, extraFolders.count) {
            clock.t = base + last + 1000 * Double(k + 1)
            model.feed(payload: ["hook_event_name": "SessionStart", "session_id": "demo-\(extraFolders[k])", "cwd": "/tmp/nm-projects-demo/\(extraFolders[k])"])
            model.refreshLayout(activePills: ["integration_claude"], open: false, focusId: "integration_claude", twoCats: false)
        }
        if pairs {
            // A second session in every project, so each has two (notchmeow already has two: the main one and the one in its worktree).
            for (k, folder) in (["site"] + extraFolders.prefix(extra)).enumerated() {
                clock.t = base + last + 20_000 + 1000 * Double(k)
                model.feed(payload: ["hook_event_name": "SessionStart", "session_id": "pair-\(folder)", "cwd": "/tmp/nm-projects-demo/\(folder)"])
            }
            model.refreshLayout(activePills: ["integration_claude"], open: false, focusId: "integration_claude", twoCats: false)
        }
        if busy {
            let cwd = "/tmp/nm-projects-demo/notchmeow"
            for k in 1...5 {
                clock.t = base + last + 1000 * Double(k)
                model.feed(payload: ["hook_event_name": "SessionStart", "session_id": "busy-\(k)", "cwd": cwd])
            }
            for (k, type) in ["Explore", "Plan", "Review"].enumerated() {
                clock.t = base + last + 10_000 + 500 * Double(k)
                model.feed(payload: ["hook_event_name": "SubagentStart", "session_id": "s-main", "cwd": cwd, "agent_id": "busy-sub-\(k + 1)", "agent_type": type])
            }
            model.refreshLayout(activePills: ["integration_claude"], open: false, focusId: "integration_claude", twoCats: false)
        }
        return model
    }
}

/// Two folders of one name with long parents, as the owner's real sessions have them: "notchmeow — GitHub Local Repos" and "notchmeow — nm-projects-demo". Render-only.
extension Replay {
    static func collideLong() -> ProjectsModel {
        let clock = SketchClock(base)
        let model = ProjectsModel(home: home(), now: { clock.t }, schedule: quietSchedule)
        for (k, cwd) in ["/Users/sam/GitHub Local Repos/notchmeow", "/tmp/nm-projects-demo/notchmeow"].enumerated() {
            clock.t = base + 1000 * Double(k)
            model.feed(payload: ["hook_event_name": "SessionStart", "session_id": "long-\(k)", "cwd": cwd])
            model.refreshLayout(activePills: ["integration_claude"], open: false, focusId: "integration_claude", twoCats: false)
        }
        return model
    }
}

/// A long project name with a same-named folder elsewhere, three sessions in the newer one: the big card's title row must keep "· 3 sessions" whole. Render-only.
extension Replay {
    static let longFolder = "an-extremely-long-project-folder-name"

    static func longCard() -> ProjectsModel {
        let clock = SketchClock(base)
        let model = ProjectsModel(home: home(), now: { clock.t }, schedule: quietSchedule)
        clock.t = base
        model.feed(payload: ["hook_event_name": "SessionStart", "session_id": "old", "cwd": "/tmp/nm-projects-demo/\(longFolder)"])
        for k in 1...3 {
            clock.t = base + 1000 * Double(k)
            model.feed(payload: ["hook_event_name": "SessionStart", "session_id": "long-\(k)", "cwd": "/Users/sam/GitHub Local Repos/\(longFolder)"])
        }
        model.refreshLayout(activePills: ["integration_claude"], open: false, focusId: "integration_claude", twoCats: false)
        return model
    }
}

/// What a picture is drawn from: the view (the model's values, or none for the badge) and the model that made it, for its big card and layout.
@MainActor
struct Scene {
    var view: PJView
    let model: ProjectsModel?

    init(model: ProjectsModel) {
        self.model = model
        self.view = model.view()
    }

    init(view: PJView) {
        self.model = nil
        self.view = view
    }
}

/// Every string a picture can show, and the check that none of them carries a path separator (a `/` or a `\`).
enum PictureText {
    /// The strings in a JSON-shaped value: the names, labels, steps and notes the view shows, as the tests pin them.
    static func strings(_ v: Any) -> [String] {
        if let s = v as? String { return [s] }
        if let d = v as? [String: Any] { return d.values.flatMap { strings($0) } }
        if let a = v as? [Any] { return a.flatMap { strings($0) } }
        return []
    }

    /// Every string the views draw for a view: its own text, the words they build from its counts, hosts, ages and types, and the fixed words, for every count
    /// the views can show (0 to 9) and every state. A string the views build is checked whether or not this view has one of it.
    static func drawn(_ v: PJView) -> [String] {
        var out = strings(v.json)
        for p in v.projects {
            out += [ProjectsLayout.sessionsWord(p.sessionCount), ProjectsLayout.agoWord(p.agoMin), ProjectsLayout.hostWord(p.host), ProjectsLayout.waitingWord(p.waiting)]
            for r in p.sessions {
                out += [ProjectsLayout.hostWord(r.host), ProjectsLayout.agoWord(r.agoMin), ProjectsLayout.rowDetail(note: r.note, step: r.step)]
                out += r.subagents.map { ProjectsLayout.subagentWord($0.type) }
            }
        }
        for n in 0...9 {
            out += [ProjectsLayout.projectsWord(n), ProjectsLayout.waitingWord(n), ProjectsLayout.moreWord(n), ProjectsLayout.moreRowsWord(n),
                    ProjectsLayout.sessionsWord(n), ProjectsLayout.badgeLabel(n), ProjectsLayout.menuTitle(n)]
        }
        out += [0, 1, 59, 60, 600].map { ProjectsLayout.agoWord($0) }
        out += ["claude-app", "vscode", "terminal"].map { ProjectsLayout.hostWord($0) }
        out += [ProjectsLayout.emptyScreen, ProjectsLayout.emptySettings, ProjectsLayout.pinTitle(pinned: true), ProjectsLayout.pinTitle(pinned: false),
                ProjectsLayout.subagentWord("")]
        out += CatState.allCases.map { CatIslandLayout.stateWords($0) }
        out += standIns
        return out
    }

    /// The words the stand-ins draw around the views (the Claude Code title row, the other agents, the captions of the badge sheet).
    static let standIns = ["Claude Code", "Codex", "Gemini CLI", "32 pt: three files on the shelf, two waiting projects", "24 pt, the same two counts"]

    /// Prints one line for the picture: whether none of `words` carries a path separator, and which ones do. True when none does.
    static func report(_ name: String, _ words: [String]) -> Bool {
        let bad = words.filter { $0.contains("/") || $0.contains("\\") }
        if bad.isEmpty {
            print("  ✓ \(name): no `/` or `\\` in its \(words.count) strings")
            return true
        }
        print("  ✗ \(name): a path separator in \(bad)")
        return false
    }
}

/// The black island as the app draws it: its body at a width and height, the surround the sheets share, and the coordinate space the pills' frames are read in.
struct IslandBody<Content: View>: View {
    let width: CGFloat
    let height: CGFloat
    @ViewBuilder let content: () -> Content

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 22).fill(Color.black)
            content()
        }
        .frame(width: width, height: height, alignment: .topLeading)
        .coordinateSpace(name: "nm.island")
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .padding(16)
        .background(Color(red: 0.30, green: 0.31, blue: 0.34))
    }
}

/// The top bar's stand-ins: three tabs, the plus, and the folder after it (the folder is the Projects button). It sits 8 pt down, as the shipping header does.
struct HeaderStand: View {
    let width: CGFloat
    var body: some View {
        HStack(spacing: 12) {
            Spacer(minLength: 0)
            ForEach(["chart.bar.xaxis", "list.bullet", "gearshape", "plus", "folder"], id: \.self) { Image(systemName: $0) }
        }
        .font(.system(size: 11, weight: .medium))
        .foregroundColor(Color(hex: "#8E939C"))
        .padding(.horizontal, 12)
        .frame(height: 34)
        .padding(.top, 8)
        .frame(width: width, height: 42, alignment: .topTrailing)
    }
}

/// CardBackground's look as a stand-in (the real card needs the whole app): the corner is the left card's, which the peek shares.
struct CardStand: View {
    var body: some View {
        RoundedRectangle(cornerRadius: ProjectsLayout.leftCardCorner)
            .fill(Color(hex: "#141518"))
            .overlay(RoundedRectangle(cornerRadius: ProjectsLayout.leftCardCorner).stroke(Color.white.opacity(0.035), lineWidth: 1))
    }
}

/// A Text's drawn frame under `key`, reported only when it is drawn (a view that is never put on screen reports nothing).
extension View {
    func frameLogged(_ log: FrameLog?, _ key: String) -> some View {
        background(GeometryReader { geo in Color.clear.onAppear { log?.frames[key] = geo.frame(in: .named("nm.island")) } })
    }
}

/// The Claude Code card's title rows as IntegrationCardView draws them, with the same priorities. `.active` is the session row (the dot, the name at layout priority 1, the subtitle,
/// the Projects row, the slack, the to-do count fixed); `.idle` is the row of an idle card (the dot, the name, the subtitle, the Projects row, the slack: no counter, no layout priority,
/// and no line limit on the shipped path). `row` nil is the row as it shipped, except that the active row's name and subtitle go through `ProjectsTitleFit` as well; the idle row's go through it only with a row (and then with a line limit of 1 too).
/// `fit` false draws the same row without it, the arrangement before the fix, so the check can be seen to fail. It is 178 pt wide: the card's 322 less the 108 pt before the text and the 36 after.
struct TitleRowStand: View {
    enum Kind { case active, idle }
    let kind: Kind
    let name: String
    let subtitle: String
    let row: ProjectsTitleRow?
    var counter: String? = nil
    var fit = true
    var log: FrameLog? = nil
    var prefix = "title"
    static let width = Island.leftRect.width - 108 - 36
    static let longName = "notchmeow-a-long-session-name"

    private var nameText: Text { Text(name).font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8")) }
    private var subText: Text { Text(subtitle).font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C")) }

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Color(hex: "#E07950")).frame(width: 7, height: 7)
            texts
            if let row { ProjectsTitleRowView(row: row, onFrame: log.map { l in { key, rect in l.frames["\(prefix)-\(key)"] = rect } }) }
            Spacer(minLength: 2)
            if let counter {
                Text(counter).font(.system(size: 11)).foregroundColor(Color(hex: "#6B7079")).fixedSize().frameLogged(log, "\(prefix)-counter")
            }
        }
        .frame(width: Self.width, alignment: .leading)
    }

    @ViewBuilder private var texts: some View {
        let nameView = nameText.lineLimit(kind == .active || row != nil ? 1 : nil).truncationMode(.tail).frameLogged(log, "\(prefix)-name")
        let subView = subText.lineLimit(kind == .active || row != nil ? 1 : nil).truncationMode(.tail).frameLogged(log, "\(prefix)-sub")
        if fit && (kind == .active || row != nil) {
            ProjectsTitleFit(name: nameView, subtitle: subView).layoutPriority(1)
        } else if kind == .active {
            nameView.layoutPriority(1)
            subView
        } else {
            nameView
            subView
        }
    }
}

/// The session row exactly as it shipped (no Projects row), for the check that the row without one is unchanged: the same frames as `TitleRowStand` with `row` nil.
struct ShippedActiveRow: View {
    let name: String
    let subtitle: String
    let counter: String
    var log: FrameLog? = nil

    var body: some View {
        HStack(spacing: 6) {
            Circle().fill(Color(hex: "#E07950")).frame(width: 7, height: 7)
            Text(name).font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8")).lineLimit(1).truncationMode(.tail).layoutPriority(1).frameLogged(log, "ref-name")
            Text(subtitle).font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C")).lineLimit(1).truncationMode(.tail).frameLogged(log, "ref-sub")
            Spacer(minLength: 2)
            Text(counter).font(.system(size: 11)).foregroundColor(Color(hex: "#6B7079")).fixedSize()
        }
        .frame(width: TitleRowStand.width, alignment: .leading)
    }
}

/// The title rows' picture: a long session name and a short one with the capsule, the idle row with a waiting project, and the row with no projects, on the card's own width.
struct TitleRowsPicture: View {
    let log: FrameLog
    var fit = true
    static let rowY: [CGFloat] = [26, 56, 86, 116]

    var body: some View {
        let some = ProjectsTitleRow(projects: 3, waiting: 1, open: false, onToggle: {})
        IslandBody(width: 360, height: 150) {
            CardStand().frame(width: 340, height: 130).offset(x: 10, y: 10)
            Group {
                TitleRowStand(kind: .active, name: TitleRowStand.longName, subtitle: "Claude Code", row: some, counter: "20/20", fit: fit, log: log, prefix: "a").offset(y: Self.rowY[0])
                TitleRowStand(kind: .active, name: "app", subtitle: "Claude Code", row: ProjectsTitleRow(projects: 3, waiting: 0, open: false, onToggle: {}), fit: fit, log: log, prefix: "b").offset(y: Self.rowY[1])
                TitleRowStand(kind: .idle, name: "Claude Code", subtitle: "Integration", row: some, fit: fit, log: log, prefix: "c").offset(y: Self.rowY[2])
                TitleRowStand(kind: .active, name: TitleRowStand.longName, subtitle: "Claude Code", row: nil, counter: "20/20", fit: fit, log: log, prefix: "d").offset(y: Self.rowY[3])
            }
            .offset(x: 22)
        }
    }
}

/// Another agent's pill, as a stand-in for AgentPill in the agents layout.
struct OtherAgentStand: View {
    let name: String
    let colour: String
    var body: some View {
        ZStack {
            Capsule().fill(Color(hex: "#0E0F11"))
            Capsule().stroke(Color(hex: colour).opacity(0.14), lineWidth: 1)
            Text(name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Color(hex: "#6B7079"))
        }
        .frame(maxWidth: .infinity)
        .frame(height: 28)
    }
}

/// The overview with projects: the big card (its cat at the big cat's place) on the left, the pill grid on the right.
struct IslandClaude: View {
    let view: PJView
    let big: PJProject?
    let cells: [ProjectsLayout.Cell]
    /// Reads the pills' drawn frames ("pill:<id>") and strings ("pill-folder", "pill-detail": "<id>\t<text>"), when given.
    var log: FrameLog? = nil

    var body: some View {
        IslandBody(width: ProjectsLayout.islandWidth, height: 160) {
            HeaderStand(width: ProjectsLayout.islandWidth)
            if let big {
                CardStand().placed(Island.leftRect)
                ProjectBigCard(project: big, animate: true, onOpen: {},
                               onFrame: { key, rect in log?.frames["card-\(key)"] = rect },
                               onDrawn: log.map { l in { key, text in l.drawn.append((kind: "card-\(key)", text: text)) } })
                    .placed(Island.leftRect)
                ProjectCatView(cat: big.cat, state: big.state, head: 58, active: true)
                    .position(x: 68, y: 101)
            }
            CardStand().placed(Island.rightRect)
            ProjectPillGrid(cells: cells, projects: view.projects, pill: { _ in AnyView(EmptyView()) }, active: true,
                            onSelect: { _ in }, onMore: {}, onHover: { _, _ in },
                            onFrame: { id, rect in log?.frames["pill:\(id)"] = rect },
                            onDrawn: log.map { l in { id, kind, text in l.drawn.append((kind: "pill-\(kind)", text: "\(id)\t\(text)")) } })
                .placed(Island.rightRect)
        }
    }
}

/// The agents layout's top part, shared by the folded island and the 252 pt one: the header, Claude Code's card (the title row with the chevron and the count, and
/// the main cat as its stand-in) and the other agents' pills on the right. 640 × 160.
struct AgentsLayer: View {
    let projects: Int
    let waiting: Int
    var log: FrameLog? = nil

    var body: some View {
        ZStack(alignment: .topLeading) {
            HeaderStand(width: ProjectsLayout.islandWidth)
            CardStand().placed(Island.leftRect)
            TitleRowStand(kind: .active, name: TitleRowStand.longName, subtitle: "Claude Code", row: ProjectsTitleRow(projects: projects, waiting: waiting, open: false, onToggle: {}), counter: "20/20", log: log)
                .offset(x: Island.leftRect.minX + 108, y: 53)
            ProjectCatView(cat: "shrimpy", state: "idle", head: 58, active: true)
                .position(x: 68, y: 101)
            CardStand().placed(Island.rightRect)
            HStack(spacing: 6) {
                OtherAgentStand(name: "Codex", colour: "#60A5FA")
                OtherAgentStand(name: "Gemini CLI", colour: "#34D399")
            }
            .frame(width: Island.rightRect.width - 20, height: 28)
            .position(x: Island.rightRect.midX, y: Island.rightRect.midY)
        }
        .frame(width: ProjectsLayout.islandWidth, height: 160, alignment: .topLeading)
    }
}

/// The folded agents layout.
struct IslandAgents: View {
    let projects: Int
    let waiting: Int
    var log: FrameLog? = nil

    var body: some View {
        IslandBody(width: ProjectsLayout.islandWidth, height: 160) {
            AgentsLayer(projects: projects, waiting: waiting, log: log)
        }
    }
}

/// The 252 pt island: the agents layout, and under it the expanded section with one row of three projects.
struct IslandAgentsOpen: View {
    let view: PJView
    let big: PJProject?
    var log: FrameLog? = nil

    /// The section under the cards, inside the island's 10 pt sides.
    static let panelRect = CGRect(x: 10, y: 160, width: ProjectsLayout.islandWidth - 20, height: ProjectsLayout.panelExtra - 8)

    var body: some View {
        IslandBody(width: ProjectsLayout.islandWidth, height: 160 + ProjectsLayout.panelExtra) {
            AgentsLayer(projects: view.projects.count, waiting: view.waiting, log: log)
            CardStand().placed(Self.panelRect)
            ProjectsPanel(cells: ProjectsLayout.panelCells(projects: view.projects.map { $0.id }), projects: view.projects, selected: big, active: true,
                          onSelect: { _ in }, onMore: {}, onHover: { _, _ in },
                          onFrame: { id, rect in log?.frames["pill:\(id)"] = rect },
                          onLayout: { key, rect in log?.frames["panel-\(key)"] = rect },
                          onDrawn: log.map { l in { key, text in l.drawn.append((kind: "panel-\(key)", text: text)) } })
                .placed(Self.panelRect)
        }
    }
}

/// The Projects screen, 240 pt, as the app lays it out: the header's 42 pt, then the content (the island's 10 pt sides and bottom padding) holding the screen, which has
/// no card of its own; the big cat sits at its place beside the list (`IslandConst.viewLayouts[.projects]`: x 54, head 46, centred in the island as `botPosition` does).
/// `log` reads the first section's drawn frame.
struct ProjectsScreenPicture: View {
    let view: PJView
    let log: FrameLog

    /// Where the big cat's head is, and its size: ViewLayout(height: 240, botX: 54, botDiameter: 46) and botPosition's centring (header bottom 42, card 84).
    static let cat = (x: CGFloat(54), y: 42 + (ProjectsLayout.screenHeight - 42 - 84) / 2 + 84 / 2, head: CGFloat(46))
    static let contentRect = CGRect(x: ProjectsLayout.contentSideInset, y: ProjectsLayout.contentTopPadding + ProjectsLayout.headerHeight,
                                    width: ProjectsLayout.islandWidth - 2 * ProjectsLayout.contentSideInset,
                                    height: ProjectsLayout.screenHeight - ProjectsLayout.contentTopPadding - ProjectsLayout.headerHeight - ProjectsLayout.contentBottomPadding)

    var body: some View {
        IslandBody(width: ProjectsLayout.islandWidth, height: ProjectsLayout.screenHeight) {
            HeaderStand(width: ProjectsLayout.islandWidth)
            ProjectsScreenContent(view: view, active: true, onRow: { _ in }, onFirstFrame: { log.frames["first"] = $0 }, onLastFrame: { log.frames["last"] = $0 })
                .placed(Self.contentRect, "content", log)
            ProjectCatView(cat: "shrimpy", state: "idle", head: Self.cat.head, active: true)
                .position(x: Self.cat.x, y: Self.cat.y)
        }
    }
}

/// The peek over the left card: the overview's big card under it, and the peek on top, placed on the card's frame. `log` reads the peek's own frame, the card's
/// frame, and the lines the peek draws (the checks that they are one frame and that the "+N more" line is the right one).
struct PeekPicture: View {
    let big: PJProject?
    let peek: PJProject?
    let log: FrameLog

    var body: some View {
        IslandBody(width: ProjectsLayout.islandWidth, height: 160) {
            HeaderStand(width: ProjectsLayout.islandWidth)
            CardStand().placed(Island.leftRect, "left", log)
            if let big {
                ProjectBigCard(project: big, animate: true, onOpen: {}).placed(Island.leftRect)
            }
            if let peek {
                // The peek reports its own frame (its background reader), placed by its centre on the left card's.
                ProjectsPeek(project: peek, active: true, onFrame: { log.frames["peek"] = $0 },
                             onDrawn: { log.drawn.append((kind: $0, text: $1)) },
                             onTitle: { log.frames["peek-\($0)"] = $1 })
                    .position(x: Island.leftRect.midX, y: Island.leftRect.midY)
            }
            CardStand().placed(Island.rightRect)
        }
    }
}

/// The compact island, 344 wide: the 2×2 grid of agent cats, the shelf's badge and the Projects badge (the waiting count), at the strip's height.
struct CompactStrip: View {
    let height: CGFloat
    let shelf: Int
    let projects: Int

    var body: some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: height / 2).fill(Color.black)
            ForEach(0..<4, id: \.self) { i in
                Circle()
                    .fill([Color(hex: "#E07950"), Color(hex: "#34D399"), Color(hex: "#60A5FA"), Color(hex: "#A78BFA")][i])
                    .frame(width: 12 * height / 32, height: 12 * height / 32)
                    .position(x: 344 - 40 + (i % 2 == 1 ? 8 : -8), y: height / 2 + (i < 2 ? -height / 4 : height / 4))
            }
            ShelfBadgeView(count: shelf, height: height)
                .position(ShelfBadge.center(islandWidth: 344, height: height))
            ProjectsBadgeView(count: projects, height: height)
                .position(ProjectsLayout.badgeCenter(islandWidth: 344, height: height))
        }
        .frame(width: 344, height: height, alignment: .topLeading)
    }
}

struct BadgePicture: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(PictureText.standIns[3])
                .font(.system(size: 12, weight: .semibold)).foregroundColor(.white.opacity(0.9))
            CompactStrip(height: 32, shelf: 3, projects: 2)
            Text(PictureText.standIns[4])
                .font(.system(size: 12, weight: .semibold)).foregroundColor(.white.opacity(0.9))
            CompactStrip(height: 24, shelf: 3, projects: 2)
        }
        .padding(16)
        .background(Color(red: 0.16, green: 0.17, blue: 0.19))
    }
}

/// The cells a reorder check shows, and how many times the view's body ran (a reorder that never reached the view proves nothing).
@MainActor
final class CellsBox: ObservableObject {
    @Published var cells: [ProjectsLayout.Cell]
    var bodies = 0
    init(_ cells: [ProjectsLayout.Cell]) { self.cells = cells }
}

/// The pill grid or the expanded section (`panel`) with the cells of a `CellsBox`, reporting each pill's frame as the island does (a null frame drops it).
struct ReorderHost: View {
    @ObservedObject var box: CellsBox
    let view: PJView
    let panel: Bool
    let log: FrameLog

    var body: some View {
        let _ = { box.bodies += 1 }()
        let report: (String, CGRect) -> Void = { id, rect in log.frames["pill:\(id)"] = rect.isNull ? nil : rect }
        IslandBody(width: ProjectsLayout.islandWidth, height: 160 + ProjectsLayout.panelExtra) {
            if panel {
                ProjectsPanel(cells: box.cells, projects: view.projects, selected: nil, active: false, onSelect: { _ in }, onMore: {}, onHover: { _, _ in }, onFrame: report)
                    .placed(CGRect(x: 10, y: 10, width: ProjectsLayout.islandWidth - 20, height: ProjectsLayout.panelExtra - 8))
            } else {
                ProjectPillGrid(cells: box.cells, projects: view.projects, pill: { _ in AnyView(EmptyView()) }, active: false,
                                onSelect: { _ in }, onMore: {}, onHover: { _, _ in }, onFrame: report)
                    .placed(Island.rightRect)
            }
        }
    }
}

@main
struct RenderProjects {
    static let all = ["island-claude", "island-claude-many", "island-collide", "card-long", "island-agents", "island-agents-open", "island-agents-open-many", "screen", "screen-many", "screen-empty", "peek", "peek-many", "peek-few", "peek-long", "title-rows", "badge"]
    /// The peek's pictures: their frame and their lines are checked whether or not a file is written (`--frame-check`, `--check`).
    static let peekCases = ["peek", "peek-many", "peek-few", "peek-long"]
    /// The screen's pictures: top-aligned, scrolled and clear of the cat, checked whether or not a file is written (`--screen-check`, `--check`).
    static let screenCases = ["screen", "screen-many"]

    /// The scene a picture is drawn from. The agents pictures set the other agent's pill, so their layout is the agents layout; the layout each picture
    /// shows is printed beside its check.
    @MainActor static func scene(_ name: String) -> Scene {
        switch name {
        case "island-claude": return Scene(model: Replay.model("collide-and-home", count: 5))
        case "island-claude-many": return Scene(model: Replay.model("collide-and-home", count: 5, extra: 4))
        case "island-collide": return Scene(model: Replay.collideLong())
        case "card-long": return Scene(model: Replay.longCard())
        case "island-agents":
            let m = Replay.model("collide-and-home", count: 5)
            m.refreshLayout(activePills: ["integration_claude", "agent_codex"], open: false, focusId: "integration_claude", twoCats: false)
            return Scene(model: m)
        case "island-agents-open-many":
            // Seven projects: the section shows two and the "+5" cell.
            let m = Replay.model("collide-and-home", count: 5, extra: 4)
            m.panelOpen = true
            m.refreshLayout(activePills: ["integration_claude", "agent_codex"], open: false, focusId: "integration_claude", twoCats: false)
            return Scene(model: m)
        case "island-agents-open":
            let m = Replay.model("collide-and-home", count: 5)
            m.panelOpen = true
            m.refreshLayout(activePills: ["integration_claude", "agent_codex"], open: false, focusId: "integration_claude", twoCats: false)
            return Scene(model: m)
        case "screen": return Scene(model: Replay.model("two-projects", count: 7))
        case "screen-empty": return Scene(model: Replay.model("two-projects", count: 0))
        // Six projects with two sessions each: more than the island's 188 pt of content holds, so the list must scroll.
        case "screen-many": return Scene(model: Replay.model("two-projects", count: 7, extra: 4, pairs: true))
        case "peek": return Scene(model: Replay.model("two-projects", count: 7))
        case "peek-many": return Scene(model: Replay.model("two-projects", count: 7, busy: true))
        // The main session and its two subagents: three lines, exactly the capacity, so nothing is cut.
        case "peek-few": return Scene(model: Replay.model("two-projects", count: 5))
        // A very long folder name with a same-named twin, three sessions: the peek's header must keep its count whole.
        case "peek-long": return Scene(model: Replay.longCard())
        case "badge", "title-rows": return Scene(view: PJView(projects: [], waiting: 0, sessionCount: 0, otherAgentSeen: false))
        default: fail("no picture named \(name)")
        }
    }

    /// The peek's drawn frame must be the left card's, both as the views lay them out (`log`). True when they are.
    @MainActor static func peekFrameCheck(_ log: FrameLog) -> Bool {
        let want = Island.leftRect
        func same(_ got: CGRect?) -> Bool {
            guard let got else { return false }
            return abs(got.minX - want.minX) < 0.5 && abs(got.minY - want.minY) < 0.5 && abs(got.width - want.width) < 0.5 && abs(got.height - want.height) < 0.5
        }
        let peek = log.frames["peek"], left = log.frames["left"]
        let ok = same(peek) && same(left)
        if ok {
            print("  ✓ peek: its drawn frame is the left card's, \(want)")
        } else {
            print("  ✗ peek: drawn at \(String(describing: peek)), the left card at \(String(describing: left)), expected \(want)")
        }
        return ok
    }

    /// The peek's drawn lines against the project's: the "+N more" text the rows drew must be the one the project's lines call for (the count from the lines and
    /// `ProjectsLayout.cut`), and when no lines are cut no "+N more" is drawn; the lines drawn must be what `cut` shows. Each part prints one ✓ or ✗ line.
    @MainActor static func peekLinesCheck(_ name: String, _ log: FrameLog, _ peek: PJProject?) -> Bool {
        guard let peek else {
            print("  ✗ \(name): no project named notchmeow")
            return false
        }
        let lines = peek.sessions.count + peek.sessions.reduce(0) { $0 + $1.subagents.count }
        let cut = ProjectsLayout.cut(lines: lines, capacity: ProjectsLayout.peekLineCapacity)
        let drawnLines = log.drawn.filter { $0.kind == "line" }.count
        let drawnMore = log.drawn.filter { $0.kind == "more" }.map { $0.text }
        let wantMore = cut.more > 0 ? [ProjectsLayout.moreRowsWord(cut.more)] : []
        var ok = true
        if drawnMore == wantMore {
            if wantMore.isEmpty {
                print("  ✓ \(name): \(lines) lines fit the peek, and no \"+N more\" line is drawn")
            } else {
                print("  ✓ \(name): the last line drawn is \(wantMore[0]) for \(lines) lines (\(cut.shown) shown)")
            }
        } else {
            print("  ✗ \(name): the \"+N more\" lines drawn are \(drawnMore), expected \(wantMore) for \(lines) lines")
            ok = false
        }
        if drawnLines == cut.shown {
            print("  ✓ \(name): \(drawnLines) lines are drawn beside the more line")
        } else {
            print("  ✗ \(name): \(drawnLines) lines are drawn, expected \(cut.shown)")
            ok = false
        }
        return ok
    }

    /// The peek's header for a very long name: the count "N sessions" is drawn whole (its frame is as wide as its string), the name is what gives way, and the two end inside the card.
    @MainActor static func peekTitleCheck(_ name: String, _ log: FrameLog, _ peek: PJProject?) -> Bool {
        guard let peek, let count = log.frames["peek-count"], let title = log.frames["peek-name"] else {
            print("  ✗ \(name): the peek's header reported no frames")
            return false
        }
        var ok = true
        func check(_ good: Bool, _ yes: String, _ no: String) {
            print(good ? "  ✓ \(name): \(yes)" : "  ✗ \(name): \(no)")
            if !good { ok = false }
        }
        func width(_ text: String, _ font: NSFont) -> CGFloat { (text as NSString).size(withAttributes: [.font: font]).width }
        let words = ProjectsLayout.sessionsWord(peek.sessionCount)
        let ideal = width(words, NSFont.systemFont(ofSize: 11)), full = width(peek.name, NSFont.systemFont(ofSize: 12, weight: .semibold))
        check(count.width >= ideal - 0.5, "the count is whole: \(Int(count.width)) pt for a \(Int(ideal)) pt string", "the count is cut: \(count.width) pt for a \(ideal) pt string")
        check(title.width < full - 1, "the name is what gives way: \(Int(title.width)) pt for a \(Int(full)) pt string", "the name was not cut (\(title.width) of \(full) pt)")
        check(count.maxX <= Island.leftRect.maxX, "the count ends inside the card", "the count passes the card's edge, at \(count.maxX)")
        return ok
    }

    /// One peek, drawn over the left card: its frame and its lines are checked; the picture is written only when `url` is given. True when the checks passed.
    @MainActor static func peekPicture(_ name: String, to url: URL?) -> Bool {
        let s = scene(name)
        let peek = s.view.projects.first { $0.name == (name == "peek-long" ? s.view.projects.first?.name : "notchmeow") }
        let log = FrameLog()
        Shot.hosted(PeekPicture(big: s.model?.bigCard(in: s.view), peek: peek, log: log), to: url)
        let frame = peekFrameCheck(log)
        let lines = peekLinesCheck(name, log, peek)
        let title = name == "peek-long" ? peekTitleCheck(name, log, peek) : true
        return frame && lines && title
    }

    /// One screen, hosted in a window: its first section must be top-aligned (its top at the header's bottom, `screenTopInset` under it, `screenLeading` in from the content's left,
    /// and the big cat's head clear of it), the list must sit in a ScrollView, and when it is taller than the content the ScrollView must really scroll (its document is taller
    /// than what shows). The picture is written only when `url` is given. True when the checks passed.
    @MainActor static func screenPicture(_ name: String, to url: URL?) -> Bool {
        let s = scene(name)
        let log = FrameLog()
        let host = Shot.hosted(ProjectsScreenPicture(view: s.view, log: log), to: url)
        if name == "screen-many", url != nil {
            // The same list scrolled to its end, for a look at the bottom: the last row clear of the island's rounded edge.
            Shot.hosted(ProjectsScreenPicture(view: s.view, log: FrameLog()), to: url!.deletingLastPathComponent().appendingPathComponent("screen-many-end.png"), scrollToEnd: true)
        }
        var ok = true
        func check(_ good: Bool, _ yes: String, _ no: String) {
            print(good ? "  ✓ \(name): \(yes)" : "  ✗ \(name): \(no)")
            if !good { ok = false }
        }
        let want = CGPoint(x: ProjectsScreenPicture.contentRect.minX + ProjectsLayout.screenLeading, y: ProjectsScreenPicture.contentRect.minY + ProjectsLayout.screenTopInset)
        let first = log.frames["first"]
        check(first.map { abs($0.minY - want.y) < 0.5 } ?? false, "the first project's top is at \(want.y) (the header's bottom, 42, and \(ProjectsLayout.screenTopInset) pt)", "the first project is at \(String(describing: first?.minY)), expected \(want.y)")
        check(first.map { abs($0.minX - want.x) < 0.5 } ?? false, "the list starts at x \(want.x), clear of the cat", "the first project is at x \(String(describing: first?.minX)), expected \(want.x)")
        let cat = ProjectsScreenPicture.cat
        check(first.map { cat.x + cat.head / 2 + 8 <= $0.minX } ?? false, "the big cat's head ends at \(cat.x + cat.head / 2), before the list", "the big cat's head overlaps the list")
        guard let scroll = Shot.scrollView(in: host) else {
            check(false, "", "no ScrollView in the screen")
            return false
        }
        let doc = scroll.documentView?.frame.height ?? 0, shown = scroll.contentView.bounds.height
        let content = log.frames["content"]
        // The last section ends at least the island's corner radius above the end of the scroll content, so the island's rounded edge never slices a row at the end of the list.
        if let last = log.frames["last"] {
            let bottom = doc - (last.maxY - ProjectsScreenPicture.contentRect.minY)
            check(bottom >= ProjectsLayout.screenBottomInset - 0.5 && bottom >= ProjectsLayout.islandCorner - 0.5, "the list ends \(Int(bottom)) pt below its last section (at least the island's \(Int(ProjectsLayout.islandCorner)) pt corner)", "only \(bottom) pt under the last section; the corner is \(ProjectsLayout.islandCorner)")
        } else {
            check(false, "", "the last section reported no frame")
        }
        check(abs(shown - ProjectsScreenPicture.contentRect.height) < 1.5, "the ScrollView shows the island's whole content height, \(Int(shown)) pt", "the ScrollView shows \(shown) pt, expected \(ProjectsScreenPicture.contentRect.height)")
        check(content.map { abs($0.minY - ProjectsScreenPicture.contentRect.minY) < 0.5 } ?? false, "the screen's frame starts under the header", "the screen's frame is at \(String(describing: content))")
        if name == "screen-many" {
            let sessions = s.view.projects.map { $0.sessions.count }
            check(s.view.projects.count == 6 && sessions.allSatisfy { $0 == 2 }, "six projects with two sessions each", "the scene has \(s.view.projects.count) projects with \(sessions) sessions")
            check(doc > shown + 1, "the list (\(Int(doc)) pt) is taller than what shows (\(Int(shown)) pt), and it is in a ScrollView: nothing is cut without a way to scroll", "the list (\(doc) pt) is not taller than what shows (\(shown) pt)")
        }
        return ok
    }

    /// The pill grid with two long colliding names ("notchmeow — GitHub Local Repos", "notchmeow — nm-projects-demo"), hosted so each pill reports what it draws and where. The pills'
    /// strings must differ in the part that tells the folders apart (the detail line is drawn for both, and the two differ), and every string must fit its pill (none is cut). The
    /// picture is written only when `url` is given. True when the checks passed.
    @MainActor static func collidePicture(_ name: String, to url: URL?) -> Bool {
        let s = scene(name)
        let log = FrameLog()
        let cells = ProjectsLayout.gridCells(projects: s.view.projects.map { $0.id }, otherPills: [])
        Shot.hosted(IslandClaude(view: s.view, big: s.model?.bigCard(in: s.view), cells: cells, log: log), to: url)
        var ok = true
        func check(_ good: Bool, _ yes: String, _ no: String) {
            print(good ? "  ✓ \(name): \(yes)" : "  ✗ \(name): \(no)")
            if !good { ok = false }
        }
        func drawn(_ kind: String) -> [String: String] {
            Dictionary(log.drawn.filter { $0.kind == kind }.map { part in
                let bits = part.text.components(separatedBy: "\t")
                return (bits[0], bits.dropFirst().joined(separator: "\t"))
            }, uniquingKeysWith: { a, _ in a })
        }
        let folders = drawn("pill-folder"), details = drawn("pill-detail")
        check(s.view.projects.count == 2 && folders.count == 2, "two pills are drawn", "\(folders.count) pills are drawn for \(s.view.projects.count) projects")
        check(Set(folders.values).count == 1, "both pills draw the same folder line, \(folders.values.first ?? "")", "the folder lines are \(folders.values.sorted())")
        check(details.count == 2 && Set(details.values).count == 2, "both draw a detail line and the two differ: \(details.values.sorted())", "the detail lines are \(details.values.sorted()), expected two different ones")
        // Every string fits what is left of its pill between the cat and the dot (ProjectsLayout's pillLeading and pillTrailing): none ends in an ellipsis.
        for project in s.view.projects {
            guard let frame = log.frames["pill:\(project.id)"], let folder = folders[project.id] else { check(false, "", "pill \(project.name) reported no frame or string"); continue }
            let room = frame.width - ProjectsLayout.pillLeading - (details[project.id] == nil ? ProjectsLayout.pillTrailing : ProjectsLayout.pillTrailingTwoLines)
            let folderW = (folder as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 10, weight: .semibold)]).width
            let detailW = details[project.id].map { ($0 as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 9)]).width } ?? 0
            check(folderW <= room && detailW <= room, "\(project.name) fits its \(Int(frame.width)) pt pill whole (folder \(Int(folderW)), detail \(Int(detailW)) of \(Int(room)) pt)",
                  "\(project.name) is cut in its \(Int(frame.width)) pt pill: folder \(folderW), detail \(detailW), room \(room)")
        }
        return ok
    }

    /// The big card for a very long name, hosted so its title row reports its frames and strings. The count "· N sessions" must be drawn whole (its frame is as wide as its string:
    /// not cut, and no dot left alone), it is one string, the NAME is what gives way (its frame is narrower than its string), nothing of the row passes the card's right edge, and
    /// the parent is drawn under the folder. The picture is written only when `url` is given. True when the checks passed.
    @MainActor static func cardPicture(_ name: String, to url: URL?) -> Bool {
        let s = scene(name)
        let log = FrameLog()
        let cells = ProjectsLayout.gridCells(projects: s.view.projects.map { $0.id }, otherPills: [])
        Shot.hosted(IslandClaude(view: s.view, big: s.model?.bigCard(in: s.view), cells: cells, log: log), to: url)
        var ok = true
        func check(_ good: Bool, _ yes: String, _ no: String) {
            print(good ? "  ✓ \(name): \(yes)" : "  ✗ \(name): \(no)")
            if !good { ok = false }
        }
        func width(_ text: String, _ font: NSFont) -> CGFloat { (text as NSString).size(withAttributes: [.font: font]).width }
        guard let big = s.model?.bigCard(in: s.view) else { check(false, "", "no big card"); return false }
        let words = "· \(ProjectsLayout.sessionsWord(big.sessionCount))"
        let counts = log.drawn.filter { $0.kind == "card-count" }.map { $0.text }
        check(counts == [words], "the count is drawn as one string, \"\(words)\" (its dot with it)", "the count strings drawn are \(counts), expected [\"\(words)\"]")
        let ideal = width(words, NSFont.systemFont(ofSize: 11))
        if let f = log.frames["card-count"] {
            check(f.width >= ideal - 0.5, "the count is whole: \(Int(f.width)) pt for a \(Int(ideal)) pt string", "the count is cut: \(f.width) pt for a \(ideal) pt string")
            check(f.maxX <= Island.leftRect.maxX, "the count ends inside the card (\(Int(f.maxX)) of \(Int(Island.leftRect.maxX)))", "the count passes the card's edge, at \(f.maxX)")
        } else {
            check(false, "", "the count reported no frame")
        }
        let folders = log.drawn.filter { $0.kind == "card-name" }.map { $0.text }
        let folder = ProjectsLayout.pillNameParts(big.name).folder
        check(folders == [folder] && folder.count > 30, "the name drawn is the long folder (\(folder.count) characters)", "the name strings are \(folders), expected the long folder")
        if let f = log.frames["card-name"] {
            let full = width(folder, NSFont.systemFont(ofSize: 12, weight: .semibold))
            check(f.width < full - 1, "the name is what gives way: \(Int(f.width)) pt for a \(Int(full)) pt string", "the name was not cut (\(f.width) of \(full) pt), so the count was not what it gave way to")
        } else {
            check(false, "", "the name reported no frame")
        }
        let detail = ProjectsLayout.pillNameParts(big.name).detail
        check(log.drawn.filter { $0.kind == "card-detail" }.map { $0.text } == (detail.map { [$0] } ?? []) && detail != nil, "the parent, \"\(detail ?? "")\", is drawn under the folder", "the detail line is not drawn as \(String(describing: detail))")
        if let d = log.frames["card-detail"], let n = log.frames["card-name"] {
            check(d.minY >= n.maxY - 1, "and it is under the name (\(Int(d.minY)) below \(Int(n.maxY)))", "the detail line is at \(d.minY), over the name's end \(n.maxY)")
        }
        return ok
    }

    /// The agents layout's pictures, hosted so the title row and the expanded section report where they draw. The title row (a long session name and "20/20") must keep its count capsule
    /// whole (its frame is as wide as the row on its own), the session name giving way; the section's first line is "N projects · M waiting" (the same words as ProjectsLayout's), it and
    /// the pills end inside the section, and the "+N" cell, when there is one, is on the pills' row: the same top and height.
    @MainActor static func agentsPicture(_ name: String, to url: URL?) -> Bool {
        let s = scene(name)
        let log = FrameLog()
        let open = name != "island-agents"
        if open {
            print("  \(name): panel shown \(s.model?.panelShown ?? false), section \(ProjectsLayout.extraHeight) pt")
            Shot.hosted(IslandAgentsOpen(view: s.view, big: s.model?.bigCard(in: s.view), log: log), to: url)
        } else {
            Shot.hosted(IslandAgents(projects: s.view.projects.count, waiting: s.view.waiting, log: log), to: url)
        }
        var ok = true
        func check(_ good: Bool, _ yes: String, _ no: String) {
            print(good ? "  ✓ \(name): \(yes)" : "  ✗ \(name): \(no)")
            if !good { ok = false }
        }
        let row = ProjectsTitleRow(projects: s.view.projects.count, waiting: s.view.waiting, open: false, onToggle: {})
        let alone = NSHostingView(rootView: ProjectsTitleRowView(row: row)).fittingSize.width
        if let f = log.frames["title-count"] {
            check(abs(f.width - alone) < 0.5, "the title row's count and chevron are whole: \(Int(f.width)) pt, as wide as on their own (\(Int(alone)) pt)", "the count is cut: \(f.width) pt for \(alone) pt on its own")
            check(f.width < 80, "and small: \(Int(f.width)) pt, not the words \"N projects · M waiting\"", "the count is \(f.width) pt wide")
        } else {
            check(false, "", "the title row's count reported no frame")
        }
        if let f = log.frames["title-name"] {
            let full = (TitleRowStand.longName as NSString).size(withAttributes: [.font: NSFont.systemFont(ofSize: 12, weight: .semibold)]).width
            check(f.width < full - 1, "the session name is what gives way: \(Int(f.width)) pt for a \(Int(full)) pt string", "the session name was not cut (\(f.width) of \(full) pt)")
        } else {
            check(false, "", "the session name reported no frame")
        }
        guard open else { return ok }
        let panel = IslandAgentsOpen.panelRect
        let words = ProjectsLayout.projectsWord(s.view.projects.count) + (s.view.waiting > 0 ? " · " + ProjectsLayout.waitingWord(s.view.waiting) : "")
        let headers = log.drawn.filter { $0.kind == "panel-header" }.map { $0.text }
        check(headers == [words], "the section's first line is \"\(words)\"", "the section's header strings are \(headers), expected [\"\(words)\"]")
        let pills = log.frames.filter { $0.key.hasPrefix("pill:") }.map { $0.value }
        if let header = log.frames["panel-header"], !pills.isEmpty {
            check(header.minY >= panel.minY && header.maxY <= pills.map { $0.minY }.min()!, "the first line is inside the section, above the pills", "the first line is at \(header)")
            check(pills.allSatisfy { $0.minY >= panel.minY && $0.maxY <= panel.maxY }, "the pills end inside the section (\(Int(pills.map { $0.maxY }.max()!)) of \(Int(panel.maxY)))", "a pill passes the section's edge")
        } else {
            check(false, "", "no header or pill frame was reported")
        }
        if let more = log.frames["panel-more"], let pill = pills.first {
            check(abs(more.minY - pill.minY) < 0.5 && abs(more.height - pill.height) < 0.5, "the \"+N\" cell is on the pills' row: top \(Int(more.minY)) and height \(Int(more.height)) as a pill's", "the \"+N\" cell is at y \(more.minY), \(more.height) high; a pill is at \(pill.minY), \(pill.height) high")
        } else if name == "island-agents-open-many" {
            check(false, "", "no \"+N\" cell was drawn for seven projects")
        }
        return ok
    }

    /// The title rows, hosted so each reports where its name, subtitle and count capsule draw. With the Projects count the subtitle is whole or not drawn at all (a fragment of it never
    /// shows), the name gives way first, the capsule is whole, and an idle row stays on one line; the row without the count has the frames the shipped row has.
    @MainActor static func titleRowsPicture(_ name: String, to url: URL?) -> Bool {
        let log = FrameLog()
        Shot.hosted(TitleRowsPicture(log: log, fit: titleFit), to: url)
        var ok = true
        func check(_ good: Bool, _ yes: String, _ no: String) {
            print(good ? "  ✓ \(name): \(yes)" : "  ✗ \(name): \(no)")
            if !good { ok = false }
        }
        func width(_ text: String, _ font: NSFont) -> CGFloat { (text as NSString).size(withAttributes: [.font: font]).width }
        let alone = NSHostingView(rootView: ProjectsTitleRowView(row: ProjectsTitleRow(projects: 3, waiting: 1, open: false, onToggle: {}))).fittingSize.width
        let aloneCalm = NSHostingView(rootView: ProjectsTitleRowView(row: ProjectsTitleRow(projects: 3, waiting: 0, open: false, onToggle: {}))).fittingSize.width
        let nameFont = NSFont.systemFont(ofSize: 12, weight: .semibold), subFont = NSFont.systemFont(ofSize: 11)
        let rows: [(p: String, label: String, name: String, sub: String)] = [
            ("a", "long name with the count", TitleRowStand.longName, "Claude Code"),
            ("b", "short name, no to-do count, nothing waiting", "app", "Claude Code"),
            ("c", "idle row with a waiting project", "Claude Code", "Integration")]
        for r in rows {
            guard let nameF = log.frames["\(r.p)-name"], let count = log.frames["\(r.p)-count"] else { check(false, "", "\(r.label): no name or count frame"); continue }
            let want = r.p == "b" ? aloneCalm : alone
            check(abs(count.width - want) < 0.5, "\(r.label): the count capsule and chevron are whole (\(Int(count.width)) pt)", "\(r.label): the count is cut: \(count.width) of \(want) pt")
            let sub = log.frames["\(r.p)-sub"], ideal = width(r.sub, subFont)
            // The subtitle: whole, or not drawn at all. A drawn one narrower than its string is the fragment this check is for.
            if let sub {
                check(sub.width >= ideal - 0.5, "\(r.label): the subtitle is drawn whole (\(Int(sub.width)) of \(Int(ideal)) pt)", "\(r.label): a fragment of the subtitle is drawn: \(sub.width) pt for a \(ideal) pt string")
            } else {
                check(true, "\(r.label): the subtitle is not drawn, so no fragment of it shows", "")
            }
            check(nameF.height < 18, "\(r.label): the name is on one line (\(Int(nameF.height)) pt)", "\(r.label): the name wrapped (\(nameF.height) pt high)")
            check(nameF.maxX <= count.minX + 0.5 && (sub.map { $0.maxX <= count.minX + 0.5 } ?? true), "\(r.label): nothing runs into the capsule", "\(r.label): the name or subtitle runs into the capsule")
        }
        let longFull = width(TitleRowStand.longName, nameFont)
        if let n = log.frames["a-name"] { check(n.width < longFull - 1 && log.frames["a-sub"] == nil, "the long name is what gave way (\(Int(n.width)) of \(Int(longFull)) pt) and the subtitle is gone", "the long name is \(n.width) of \(longFull) pt, the subtitle \(String(describing: log.frames["a-sub"]))") }
        if let n = log.frames["b-name"], let sub = log.frames["b-sub"] { check(n.width >= width("app", nameFont) - 0.5 && sub.width >= width("Claude Code", subFont) - 0.5, "a short name keeps its subtitle: both are whole", "the short name's row lost something: name \(n.width), subtitle \(sub.width)") } else { check(false, "", "the short name's row drew no subtitle") }
        // The name fills the room the row leaves it, up to the counter: it is the whole name when that fits, else the longest start (and "…") that fits, within a glyph's rounding. The room is what
        // the row's own fixed parts leave: the dot's 7 + 6 before the name, the capsule and its 6 pt gap, the minimum Spacer (2) between two 6 pt gaps, and the counter. What looks like free
        // space between the chevron and the counter is those 6 + the Spacer + 6, the chevron's own padding and less than one glyph; a name never stops short of a glyph that fits.
        func fills(_ label: String, _ full: String, _ f: FrameLog, _ p: String, rowRight: CGFloat) {
            guard let n = f.frames["\(p)-name"], let count = f.frames["\(p)-count"] else { check(false, "", "\(label): no name or count frame"); return }
            let edge = f.frames["\(p)-counter"].map { $0.minX - 6 } ?? rowRight   // where the Spacer ends: a 6 pt gap before the counter, or the row's own right edge
            let room = edge - 2 - 6 - count.width - 6 - n.minX
            let whole = width(full, nameFont)
            var want = whole
            if whole > room {
                let chars = Array(full)
                want = (1...chars.count).map { width(String(chars.prefix($0)) + "…", nameFont) }.filter { $0 <= room }.max() ?? 0
            }
            // (3 pt: NSString's width of a start and "…" is not SwiftUI's to the point; a name short of its room by a glyph that fits is 4 pt or more.)
            check(abs(n.width - want) < 3 && n.width <= room + 0.5, "\(label): the name fills its room: \(Int(n.width)) pt of \(Int(room)) pt (the longest start that fits is \(Int(want)) pt; the whole name is \(Int(whole)) pt)",
                  "\(label): the name is \(n.width) pt in a room of \(room) pt; it should be \(want) pt (the whole name is \(whole) pt)")
        }
        // A long name with no Projects count (row d) is the active row too: the name gives way, and the subtitle is whole or not drawn at all.
        if let nameF = log.frames["d-name"], let counter = log.frames["d-counter"] {
            let sub = log.frames["d-sub"], ideal = width("Claude Code", subFont)
            if let sub {
                check(sub.width >= ideal - 0.5, "a long name without the count: the subtitle is drawn whole (\(Int(sub.width)) of \(Int(ideal)) pt)", "a long name without the count: a fragment of the subtitle is drawn: \(sub.width) pt for a \(ideal) pt string")
            } else {
                check(true, "a long name without the count: the subtitle is not drawn, so no fragment of it shows", "")
            }
            check(nameF.height < 18, "a long name without the count: the name is on one line (\(Int(nameF.height)) pt)", "a long name without the count: the name wrapped (\(nameF.height) pt high)")
            check(nameF.maxX <= counter.minX + 0.5 && (sub.map { $0.maxX <= counter.minX + 0.5 } ?? true), "a long name without the count: nothing runs into the counter", "a long name without the count: the name or subtitle runs into the counter")
        } else {
            check(false, "", "a long name without the count: no name or counter frame")
        }
        fills("long name with the count", TitleRowStand.longName, log, "a", rowRight: 22 + TitleRowStand.width)
        fills("idle row with a waiting project", "Claude Code", log, "c", rowRight: 22 + TitleRowStand.width)
        for (label, long) in [("a name of wide letters", String(repeating: "W", count: 24)), ("a name of narrow letters", String(repeating: "i", count: 60)), ("a name with spaces", "my long project name here")] {
            let other = FrameLog()
            Shot.hosted(IslandBody(width: 360, height: 40) {
                TitleRowStand(kind: .active, name: long, subtitle: "Claude Code", row: ProjectsTitleRow(projects: 3, waiting: 1, open: false, onToggle: {}), counter: "20/20", fit: titleFit, log: other, prefix: "x").offset(x: 22, y: 10)
            }, to: nil)
            fills(label, long, other, "x", rowRight: 22 + TitleRowStand.width)
        }
        // The row with no Projects count, for a name that leaves the subtitle room whole ("notch" does; the subtitle is 68 pt and the row has 46 pt for a name), is the row as it shipped: the
        // same frames as a copy of it. A longer name gives way, as row d above and the next check show.
        for (label, name, sub) in [("short", "notch", "Claude Code")] {
            let a = FrameLog(), b = FrameLog()
            Shot.hosted(IslandBody(width: 360, height: 40) { TitleRowStand(kind: .active, name: name, subtitle: sub, row: nil, counter: "20/20", log: a, prefix: "x").offset(x: 22, y: 10) }, to: nil)
            Shot.hosted(IslandBody(width: 360, height: 40) { ShippedActiveRow(name: name, subtitle: sub, counter: "20/20", log: b).offset(x: 22, y: 10) }, to: nil)
            let same = ["name", "sub"].allSatisfy { key in
                guard let x = a.frames["x-\(key)"], let y = b.frames["ref-\(key)"] else { return false }
                return abs(x.minX - y.minX) < 0.5 && abs(x.width - y.width) < 0.5 && abs(x.height - y.height) < 0.5
            }
            check(same, "without the count, the \(label)-name row has the shipped row's frames", "without the count, the \(label)-name row differs from the shipped row: row \(a.frames) against shipped \(b.frames)")
        }
        // A name that leaves the subtitle no room whole ("notchmeow" is 69 pt, so only 39 pt of the 68 pt subtitle fit): the shipped row drew that piece ("Claude C…"); now it is not drawn.
        let mid = FrameLog()
        Shot.hosted(IslandBody(width: 360, height: 40) { TitleRowStand(kind: .active, name: "notchmeow", subtitle: "Claude Code", row: nil, counter: "20/20", fit: titleFit, log: mid, prefix: "x").offset(x: 22, y: 10) }, to: nil)
        if let sub = mid.frames["x-sub"] {
            check(sub.width >= width("Claude Code", subFont) - 0.5, "a name with no room for the subtitle whole: the subtitle is drawn whole", "a name with no room for the subtitle whole: a fragment of it is drawn: \(sub.width) pt of \(width("Claude Code", subFont)) pt")
        } else {
            check(mid.frames["x-name"].map { $0.width >= width("notchmeow", nameFont) - 0.5 } ?? false, "a name with no room for the subtitle whole: the subtitle is not drawn and the name is whole", "a name with no room for the subtitle whole: no name frame, or the name is cut")
        }
        return ok
    }

    /// Whether the title rows go through `ProjectsTitleFit` (the fix). Set false by hand to draw the arrangement before it and see the check fail (the render tool reads no environment).
    static let titleFit = true

    /// A pill's identity is its project, not its slot. The grid (`panel` false) and the expanded section (`panel` true) are hosted with the cells [A, B, C], then [C, A, B] in the same
    /// views (so SwiftUI updates them, as the app does when a waiting project moves first); each project's LAST reported frame must be where it is drawn, which a fresh host of
    /// [C, A, B] says (its pills appear new, and report where they are). A slot-keyed ForEach reuses the view in slot 0 for another project whose frame did not change, so nothing is
    /// reported and the right-click Pin finds the old slot. True when every project's frame follows it.
    @MainActor static func reorderCheck(_ name: String, panel: Bool) -> Bool {
        let s = scene("island-claude")
        let ids = s.view.projects.prefix(3).map { $0.id }
        var ok = true
        func check(_ good: Bool, _ yes: String, _ no: String) {
            print(good ? "  ✓ \(name): \(yes)" : "  ✗ \(name): \(no)")
            if !good { ok = false }
        }
        guard ids.count == 3 else { check(false, "", "the scene has \(ids.count) projects, expected 3"); return false }
        let first = ids.map { ProjectsLayout.Cell.project($0) }, second = [ids[2], ids[0], ids[1]].map { ProjectsLayout.Cell.project($0) }
        let truthFirst = FrameLog(), truthSecond = FrameLog(), log = FrameLog()
        let a = Shot.held(ReorderHost(box: CellsBox(first), view: s.view, panel: panel, log: truthFirst))
        let b = Shot.held(ReorderHost(box: CellsBox(second), view: s.view, panel: panel, log: truthSecond))
        let box = CellsBox(first)
        let c = Shot.held(ReorderHost(box: box, view: s.view, panel: panel, log: log))
        let before = box.bodies
        box.cells = second
        Shot.settle(c.host)
        check(box.bodies > before, "the new order reached the view (\(box.bodies - before) more body runs)", "the new order never reached the view")
        for id in ids {
            guard let moved = log.frames["pill:\(id)"], let was = truthFirst.frames["pill:\(id)"], let want = truthSecond.frames["pill:\(id)"] else { check(false, "", "project \(id) reported no frame"); continue }
            check(abs(want.minX - was.minX) + abs(want.minY - was.minY) > 1, "project \(id) moves between the two orders", "project \(id) does not move between the two orders in the fresh hosts (\(was) and \(want)); the check proves nothing")
            check(abs(moved.minX - want.minX) < 0.5 && abs(moved.minY - want.minY) < 0.5 && abs(moved.width - want.width) < 0.5 && abs(moved.height - want.height) < 0.5,
                  "project \(id)'s last reported frame is where it is drawn, \(Int(want.minX)),\(Int(want.minY))",
                  "project \(id) last reported \(moved) but is drawn at \(want): the pill kept its slot's identity")
        }
        withExtendedLifetime((a, b, c)) {}
        return ok
    }

    /// The agents checks alone, with no pictures written.
    @MainActor static func agentsChecks() -> Bool {
        var ok = true
        for name in ["island-agents", "island-agents-open", "island-agents-open-many"] where !agentsPicture(name, to: nil) { ok = false }
        return ok
    }

    /// The pill check alone, with no picture written.
    @MainActor static func collideChecks() -> Bool { collidePicture("island-collide", to: nil) }

    /// The screen checks alone, for every screen case, with no pictures written.
    @MainActor static func screenChecks() -> Bool {
        var ok = true
        for name in screenCases where !screenPicture(name, to: nil) { ok = false }
        return ok
    }

    /// The peek checks alone, for every peek case, with no pictures written.
    @MainActor static func peekChecks() -> Bool {
        var ok = true
        for name in peekCases where !peekPicture(name, to: nil) { ok = false }
        return ok
    }

    /// One picture: its check first (the words it shows), then the picture itself, so a failing picture is still drawn for a look. True when its checks passed.
    @MainActor static func draw(_ name: String, to dir: URL) -> Bool {
        let url = dir.appendingPathComponent("\(name).png")
        let s = scene(name)
        var ok = PictureText.report(name, PictureText.drawn(s.view))
        if let m = s.model { print("  \(name): \(s.view.projects.count) projects, \(s.view.waiting) waiting, layout \(m.layout.rawValue)") }
        switch name {
        case "island-collide":
            ok = collidePicture(name, to: url) && ok
        case "card-long":
            ok = cardPicture(name, to: url) && ok
        case "title-rows":
            ok = titleRowsPicture(name, to: url) && ok
        case "island-claude", "island-claude-many":
            let cells = ProjectsLayout.gridCells(projects: s.view.projects.map { $0.id }, otherPills: [])
            Shot.save(IslandClaude(view: s.view, big: s.model?.bigCard(in: s.view), cells: cells), to: url)
        case "island-agents", "island-agents-open", "island-agents-open-many":
            ok = agentsPicture(name, to: url) && ok
        case "screen", "screen-many":
            ok = screenPicture(name, to: url) && ok
        case "screen-empty":
            Shot.hosted(ProjectsScreenPicture(view: s.view, log: FrameLog()), to: url)
        case "peek", "peek-many", "peek-few", "peek-long":
            ok = peekPicture(name, to: url) && ok
        case "badge":
            Shot.save(BadgePicture(), to: url)
        default:
            fail("no picture named \(name)")
        }
        return ok
    }

    /// Every picture's words, with no pictures written: the check `--text-check` runs. It does not look at the peek's frame or lines (`--frame-check`).
    @MainActor static func textCheck() -> Bool {
        var ok = true
        for name in RenderProjects.all {
            if !PictureText.report(name, PictureText.drawn(scene(name).view)) { ok = false }
        }
        return ok
    }

    @MainActor static func main() {
        var out: String?
        var island: String?
        var names: [String] = []
        var many = false, empty = false, all = false, screen = false, peek = false
        var textOnly = false, frameOnly = false, check = false, screenOnly = false, reorderOnly = false
        var it = CommandLine.arguments.dropFirst().makeIterator()
        while let k = it.next() {
            switch k {
            case "--out": out = it.next()
            case "--island": island = it.next()
            case "--many": many = true
            case "--empty": empty = true
            case "--screen": screen = true
            case "--peek": peek = true
            case "--badge": names.append("badge")
            case "--all": all = true
            case "--text-check": textOnly = true
            case "--frame-check": frameOnly = true
            case "--check": check = true
            case "--screen-check": screenOnly = true
            case "--reorder-check": reorderOnly = true
            default: fail("unknown argument \(k)")
            }
        }
        _ = NSApplication.shared   // the peek's checks are drawn in a window (`Shot.hosted`), as the pictures are
        if check {
            // Every check, no pictures: the words, then the peek's frame and lines. Both run, so each prints.
            let words = textCheck()
            let frames = peekChecks()
            let screens = screenChecks()
            let pills = collideChecks()
            let cards = cardPicture("card-long", to: nil)
            let agents = agentsChecks()
            let titles = titleRowsPicture("title-rows", to: nil)
            let reorders = [reorderCheck("reorder-grid", panel: false), reorderCheck("reorder-panel", panel: true)]
            let ok = words && frames && screens && pills && cards && agents && titles && !reorders.contains(false)
            print(ok ? "All checks passed." : "A check failed.")
            exit(ok ? 0 : 1)
        }
        if reorderOnly {
            let ok = [reorderCheck("reorder-grid", panel: false), reorderCheck("reorder-panel", panel: true)].allSatisfy { $0 }
            print(ok ? "All reorder checks passed." : "A reorder check failed.")
            exit(ok ? 0 : 1)
        }
        if screenOnly {
            let ok = screenChecks()
            print(ok ? "All screen checks passed." : "A screen check failed.")
            exit(ok ? 0 : 1)
        }
        if frameOnly {
            let ok = peekChecks()
            print(ok ? "All peek checks passed." : "A peek check failed.")
            exit(ok ? 0 : 1)
        }
        if textOnly {
            // The check alone: every picture's words and no pictures, nothing written.
            let ok = textCheck()
            print(ok ? "All words are free of path separators." : "A picture shows a path separator.")
            exit(ok ? 0 : 1)
        }
        if screen { names.append(empty ? "screen-empty" : (many ? "screen-many" : "screen")) }
        if peek { names.append(many ? "peek-many" : "peek") }
        if all { names = RenderProjects.all }
        if let island {
            switch island {
            case "claude": names.append(many ? "island-claude-many" : "island-claude")
            case "collide": names.append("island-collide")
            case "card": names.append("card-long")
            case "agents": names.append("island-agents")
            case "agents-open": names.append("island-agents-open")
            default: fail("--island takes claude, collide, card, agents or agents-open")
            }
        }
        if names.isEmpty { fail("say what to draw: --island, --screen, --peek, --badge, --all, --check, --frame-check or --text-check, and --out DIR") }
        guard let out else { fail("say where to write: --out DIR") }
        let dir = URL(fileURLWithPath: out, isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        var ok = true
        for name in names {
            if !draw(name, to: dir) { ok = false }
        }
        if !ok {
            print("A picture failed its check: a path separator in a string, the peek off the left card's frame, a wrong \"+N more\" line, the screen not top-aligned or scrolled, two same-named pills that look alike or cut their names, or a big card whose count is cut. The pictures are written; the tool fails.")
            exit(1)
        }
    }
}
