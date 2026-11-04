import QuartzCore
import SwiftUI

// The Projects views (sub-project P-mac, Task 6): the island's project pills, the big card, the expanded section, the Projects screen, the peek, the compact waiting
// badge and a project's kittens. Plain values in, closures out: nothing here names AppState, ProjectsModel, a store, a host or a user lookup
// (scripts/check-projects-render-private.sh pins it), so scripts/render-projects.sh draws these very views. Every TimelineView is paused unless its `active` (or
// `animate`) flag is set, so a folded island draws none of them (0 % CPU when hidden); scripts/test-projects-wiring.sh pins that (the count of TimelineViews and each one's
// pause), while scripts/check-projects-render-private.sh pins only the naming and privacy rule above.
//
// Looks: a project pill is AgentPill's capsule (28 pt, #0E0F11, the stroke at 0.14, 0.18 and 0.55 on hover, the cat at leading 8, the name at 10 pt semibold);
// the big card is the overview's title row (12 pt semibold #F5F6F8, 11 pt #8E939C) and its step line. A waiting project is amber in both waiting states.

/// The colours and rules the views share.
fileprivate enum ProjectsStyle {
    /// Amber: the approval state's colour, for both waiting states (approval and question).
    static let amber = Theme.State.color["approval"] ?? "#F5A524"

    static func waiting(_ state: String) -> Bool { state == "approval" || state == "question" }

    static func dot(_ state: String) -> String {
        waiting(state) ? amber : (Theme.State.color[state] ?? Theme.State.color["idle"] ?? "#E6E9EE")
    }

    static func catState(_ state: String) -> CatState { CatState(rawValue: state) ?? .idle }
}

/// A project's cat, or a subagent's: a CatEngine like Settings' previews. Its coat is `cat`, its pose `state`; it draws and moves only while `active`.
struct ProjectCatView: View {
    let cat: String
    let state: String
    let head: Double
    let active: Bool
    @StateObject private var engine: CatEngine

    init(cat: String, state: String, head: Double, active: Bool) {
        self.cat = cat
        self.state = state
        self.head = head
        self.active = active
        _engine = StateObject(wrappedValue: CatEngine(CatPresets.byID(cat), mini: head < 30, now: { CACurrentMediaTime() * 1000 }, state: ProjectsStyle.catState(state)))
    }

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active)) { timeline in
            Canvas { context, size in
                _ = timeline.date   // the Canvas redraws on every tick of the timeline
                engine.useCharacter(cat)
                engine.update(dt: CatEngine.frameDelta(now: CACurrentMediaTime(), last: engine.lastTime))
                let options = CatDrawOptions(badge: false)
                context.withCGContext { cg in
                    CatRenderer.draw(cg, engine.look(), cx: Double(size.width) / 2, cy: Double(size.height) / 2 + head * 0.08, D: head, options)
                }
            }
        }
        .frame(width: head / 0.6, height: head / 0.6)
        .onChange(of: state) { _, next in engine.setState(ProjectsStyle.catState(next)) }
        .accessibilityHidden(true)
    }
}

/// A state's dot: amber for both waiting states, else the state's colour. It breathes only while `animate` (a waiting project on an expanded island).
struct ProjectStateDot: View {
    let state: String
    var size: CGFloat = 7
    let animate: Bool

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !animate)) { timeline in
            let phase = animate ? (sin(timeline.date.timeIntervalSinceReferenceDate * 2 * .pi / 1.6) + 1) / 2 : 0
            Circle()
                .fill(Color(hex: ProjectsStyle.dot(state)))
                .frame(width: size, height: size)
                .opacity(animate ? 0.6 + 0.4 * phase : 1)
                .shadow(color: Color(hex: ProjectsStyle.dot(state)).opacity(0.7 * phase), radius: 3)
        }
    }
}

/// A project in the grid: AgentPill's capsule with the project's cat at its leading end, its name, and its state dot where PillBadgeView sits.
struct ProjectPill: View {
    let project: PJProject
    let active: Bool
    let onTap: () -> Void
    let onHover: (Bool) -> Void
    var onFrame: (CGRect) -> Void = { _ in }
    /// Reports what the pill draws, when it appears: ("folder", the folder) and, when there is one, ("detail", the line under it). A test reads it; nil reports nothing.
    var onDrawn: ((String, String) -> Void)? = nil
    @State private var isHovered = false

    private var accent: String { ProjectsStyle.dot(project.state) }
    private var nameParts: (folder: String, detail: String?) { ProjectsLayout.pillNameParts(project.name) }

    var body: some View {
        Button(action: onTap) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Capsule()
                        .fill(isHovered ? Color(hex: accent).opacity(0.18) : Color(hex: "#0E0F11"))
                    Capsule()
                        .stroke(Color(hex: accent).opacity(isHovered ? 0.55 : 0.14), lineWidth: 1)
                    HStack(spacing: 0) {
                        ProjectCatView(cat: project.cat, state: project.state, head: 22, active: active)
                            .frame(width: 22, height: 22)
                            .padding(.leading, 8)
                        Spacer()
                    }
                    // Two folders of one name show "<folder>" over "<parent>" (small, under it), so the part that tells them apart is never cut off the end of one line.
                    VStack(spacing: 0) {
                        Text(nameParts.folder)
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundColor(isHovered ? Color(hex: accent).lighter(by: 0.3) : Color(hex: "#6B7079"))
                            .lineLimit(1)
                            .truncationMode(.tail)
                        if let detail = nameParts.detail {
                            Text(detail)
                                .font(.system(size: 9))
                                .foregroundColor(Color(hex: "#8E939C"))
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                    .padding(.leading, ProjectsLayout.pillLeading)     // clear of the cat (which ends at 30 pt) ...
                    .padding(.trailing, nameParts.detail == nil ? ProjectsLayout.pillTrailing : ProjectsLayout.pillTrailingTwoLines)    // ... and of the dot
                    .frame(maxWidth: .infinity, alignment: .center)
                    .onAppear {
                        onDrawn?("folder", nameParts.folder)
                        if let detail = nameParts.detail { onDrawn?("detail", detail) }
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .shadow(color: Color(hex: accent).opacity(isHovered ? 0.35 : 0), radius: 10, x: 0, y: 2)

                ZStack {
                    Circle().fill(Color(hex: "#0B0C0E")).frame(width: 11, height: 11)
                    ProjectStateDot(state: project.state, size: 7, animate: active && ProjectsStyle.waiting(project.state))
                }
                .offset(x: 3, y: -3)
            }
            .opacity(project.dim ? 0.5 : 1)
            .background(GeometryReader { geo in
                Color.clear
                    .onAppear { onFrame(geo.frame(in: .named("nm.island"))) }
                    .onChange(of: geo.frame(in: .named("nm.island"))) { _, frame in onFrame(frame) }
                    .onDisappear { onFrame(.null) }   // a pill that leaves the tree takes its frame with it
            })
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.04 : 1.0)
        .brightness(isHovered ? 0.06 : 0)
        .onHover { hovering in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { isHovered = hovering }
            onHover(hovering)
        }
    }
}

/// The "+N" cell for the projects that do not fit: the same capsule, with the count.
struct ProjectMoreCell: View {
    let count: Int
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            ZStack {
                Capsule().fill(isHovered ? Color.white.opacity(0.07) : Color(hex: "#0E0F11"))
                Capsule().stroke(Color.white.opacity(isHovered ? 0.3 : 0.14), lineWidth: 1)
                Text(ProjectsLayout.moreWord(count))
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isHovered ? Color(hex: "#B0B5BE") : Color(hex: "#6B7079"))
            }
            .frame(maxWidth: .infinity)
            .frame(height: 28)
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

/// The right card's pill grid: two columns of cells, each a project, the "+N", or another agent's pill (`pill`, built by the caller).
struct ProjectPillGrid: View {
    let cells: [ProjectsLayout.Cell]
    let projects: [PJProject]
    let pill: (String) -> AnyView
    let active: Bool
    let onSelect: (String) -> Void
    let onMore: () -> Void
    let onHover: (String, Bool) -> Void
    var onFrame: (String, CGRect) -> Void = { _, _ in }
    /// Reports what each pill draws, as `ProjectPill.onDrawn` does, with the project's id first (nil reports nothing).
    var onDrawn: ((String, String, String) -> Void)? = nil

    private let columns = [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)]

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)
            LazyVGrid(columns: columns, spacing: 4) {
                ForEach(cells, id: \.key) { cell in
                    switch cell {
                    case .project(let id):
                        if let project = projects.first(where: { $0.id == id }) {
                            ProjectPill(project: project, active: active, onTap: { onSelect(id) }, onHover: { onHover(id, $0) }, onFrame: { onFrame(id, $0) },
                                        onDrawn: onDrawn.map { report in { report(id, $0, $1) } })
                        }
                    case .more(let count):
                        ProjectMoreCell(count: count, onTap: onMore)
                    case .pill(let id):
                        pill(id)
                    }
                }
            }
            .padding(.horizontal, 8)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension View {
    /// Reports a Text's drawn frame (in the "nm.island" space) and string when it appears, under `key`. Both closures nil: nothing is added.
    @ViewBuilder fileprivate func reporting(_ key: String, _ text: String, _ onFrame: ((String, CGRect) -> Void)?, _ onDrawn: ((String, String) -> Void)?) -> some View {
        if onFrame != nil || onDrawn != nil {
            background(GeometryReader { geo in
                Color.clear.onAppear {
                    onFrame?(key, geo.frame(in: .named("nm.island")))
                    onDrawn?(key, text)
                }
            })
        } else {
            self
        }
    }
}

/// The big card: the project's title row (its dot, name and session count), its step line (the state's words while it has none), the host and the age, and ↗.
/// It draws no card and no cat: the island draws the card's background and the big cat at its place, as it does for the overview.
struct ProjectBigCard: View {
    let project: PJProject
    let animate: Bool
    let onOpen: () -> Void
    /// Report what the title row draws, when it appears: the frames ("name", "count", "detail") in the "nm.island" coordinate space, and the strings ("name", "count",
    /// "detail"). A test reads them (a Text does not say whether it was cut, so the render measures its frame against its string); nil reports nothing.
    var onFrame: ((String, CGRect) -> Void)? = nil
    var onDrawn: ((String, String) -> Void)? = nil

    private var textLeading: CGFloat { CGFloat(CatIslandLayout.oneTextLeading) }
    private var waiting: Bool { ProjectsStyle.waiting(project.state) }
    private var nameParts: (folder: String, detail: String?) { ProjectsLayout.pillNameParts(project.name) }
    /// "· 3 sessions", one string: its dot never travels apart from it.
    private var countText: String { "· \(ProjectsLayout.sessionsWord(project.sessionCount))" }

    /// The step, or the state's words when the session has none.
    private var stepLine: String {
        project.step.isEmpty ? CatIslandLayout.stateWords(ProjectsStyle.catState(project.state)) : project.step
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    ProjectStateDot(state: project.state, size: 7, animate: animate && waiting)
                    Text(nameParts.folder)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#F5F6F8"))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .reporting("name", nameParts.folder, onFrame, onDrawn)
                    // The count is never cut and never leaves a dot behind: it keeps its full width, and the name above gives way (it truncates first).
                    Text(countText)
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .lineLimit(1)
                        .fixedSize(horizontal: true, vertical: false)
                        .layoutPriority(1)
                        .reporting("count", countText, onFrame, onDrawn)
                }
                .padding(.top, 6)
                .padding(.leading, textLeading)
                .padding(.trailing, 36)

                // Two folders of one name: the parent under the folder (as the pill draws it), so what tells them apart is not cut off the title.
                if let detail = nameParts.detail {
                    Text(detail)
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .lineLimit(1)
                        .truncationMode(.middle)
                        .reporting("detail", detail, onFrame, onDrawn)
                        .padding(.top, 1)
                        .padding(.leading, textLeading + 13)   // under the name: the dot and its gap
                        .padding(.trailing, 36)
                }

                Text(stepLine)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: waiting ? ProjectsStyle.amber : "#B0B5BE"))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.top, 6)
                    .padding(.leading, textLeading)
                    .padding(.trailing, 12)

                Text("\(ProjectsLayout.hostWord(project.host)) · \(ProjectsLayout.agoWord(project.agoMin))")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#8E939C"))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .padding(.top, 4)
                    .padding(.leading, textLeading)
                    .padding(.trailing, 12)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.top, 4)

            Button(action: onOpen) {
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundColor(Color(hex: "#5F646D"))
                    .frame(width: 16, height: 16)
                    .background(Color.white.opacity(0.07))
                    .clipShape(Circle())
            }
            .buttonStyle(.plain)
            .padding(.top, 8)
            .padding(.trailing, 10)
            .frame(maxWidth: .infinity, alignment: .topTrailing)
        }
        .opacity(project.dim ? 0.5 : 1)
    }
}

/// One project's rows: each session (its state dot, label, the note in amber while it waits in the app or else the step, the host and the age), each with its
/// subagents beneath it (a small cat of the project's coat, in its state). A session or a subagent is one line. `limit` caps the lines: past it the last line
/// says how many more there are. `onRow` makes a session a button; nil draws plain rows (the peek).
struct ProjectRows: View {
    let project: PJProject
    let active: Bool
    var onRow: ((String) -> Void)? = nil
    /// The most lines drawn; `ProjectsLayout.cut` decides the last one. nil draws them all.
    var limit: Int? = nil
    /// The space between two lines.
    var spacing: CGFloat = 4
    /// The height of each line; nil keeps the lines' own heights (the screen). The peek fixes it, so its lines are the capacity's.
    var rowHeight: CGFloat? = nil
    /// Reports what each drawn line is, when it appears: ("line", the line's id) for a session or a subagent, ("more", the "+N more" text). A test reads it; nil reports nothing.
    var onDrawn: ((String, String) -> Void)? = nil

    /// One line: a session (`sub` nil) or one of its subagents.
    private struct Line: Identifiable {
        let id: String
        let row: PJSessionRow
        let sub: PJSubagentRow?
    }

    private var lines: [Line] {
        project.sessions.flatMap { row in
            [Line(id: "s:\(row.id)", row: row, sub: nil)] + row.subagents.map { Line(id: "a:\(row.id):\($0.id)", row: row, sub: $0) }
        }
    }

    /// The lines drawn, and how many are cut (the last drawn line is then "+N more", by `ProjectsLayout.cut`).
    private var split: (shown: [Line], more: Int) {
        let all = lines
        guard let limit else { return (all, 0) }
        let cut = ProjectsLayout.cut(lines: all.count, capacity: limit)
        return (Array(all.prefix(cut.shown)), cut.more)
    }

    var body: some View {
        let parts = split
        let more = ProjectsLayout.moreRowsWord(parts.more)
        VStack(alignment: .leading, spacing: spacing) {
            ForEach(parts.shown) { line in
                Group {
                    if let sub = line.sub {
                        subagentLine(line.row, sub)
                    } else {
                        sessionLine(line.row)
                    }
                }
                .onAppear { onDrawn?("line", line.id) }
            }
            if parts.more > 0 {
                Text(more)
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#6B7079"))
                    .lineLimit(1)
                    .frame(height: rowHeight, alignment: .leading)
                    .onAppear { onDrawn?("more", more) }
            }
        }
    }

    @ViewBuilder private func sessionLine(_ row: PJSessionRow) -> some View {
        let text = ProjectsLayout.rowDetail(note: row.note, step: row.step)
        if let onRow {
            Button(action: { onRow(row.id) }) { sessionContent(row, text) }
                .buttonStyle(.plain)
        } else {
            sessionContent(row, text)
        }
    }

    private func sessionContent(_ row: PJSessionRow, _ text: String) -> some View {
        HStack(spacing: 6) {
            ProjectStateDot(state: row.state, size: 6, animate: active && ProjectsStyle.waiting(row.state))
            Text(row.label)
                .font(.system(size: 11, weight: .semibold))
                .foregroundColor(Color(hex: "#F5F6F8"))
                .lineLimit(1)
            if !text.isEmpty {
                Text(text)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: row.note.isEmpty ? "#B0B5BE" : ProjectsStyle.amber))
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer(minLength: 4)
            Text("\(ProjectsLayout.hostWord(row.host)) · \(ProjectsLayout.agoWord(row.agoMin))")
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "#8E939C"))
                .lineLimit(1)
        }
        .contentShape(Rectangle())
        .frame(height: rowHeight)
        .opacity(row.dim ? 0.5 : 1)
    }

    /// A subagent's line: its cat (drawn at head 12, so it reaches beyond the line, centred on it) and its type.
    private func subagentLine(_ row: PJSessionRow, _ sub: PJSubagentRow) -> some View {
        HStack(spacing: 6) {
            ProjectCatView(cat: project.cat, state: sub.state, head: 12, active: active)
            Text(ProjectsLayout.subagentWord(sub.type))
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "#8E939C"))
                .lineLimit(1)
        }
        .padding(.leading, 16)
        .frame(height: rowHeight, alignment: .leading)
        .opacity(row.dim ? 0.5 : 1)
    }
}

/// The Projects screen: one section per project (its cat, name, the waiting count, its rows), scrolled; or the empty state when no project runs. The list is top-aligned
/// under the island's header (`screenTopInset`) and starts `screenLeading` from the left, so the island's big cat keeps the left of the screen and is never over a row; the island
/// gives the view all of its height (IslandContentView's `isTall`), and a list taller than that scrolls.
struct ProjectsScreenContent: View {
    let view: PJView
    let active: Bool
    let onRow: (String) -> Void
    /// Report the first and the last section's drawn frames, in the "nm.island" coordinate space, when they appear (nil reports nothing, and adds nothing). The render checks that
    /// the list is top-aligned and that the last section ends `screenBottomInset` above the end of the scroll content.
    var onFirstFrame: ((CGRect) -> Void)? = nil
    var onLastFrame: ((CGRect) -> Void)? = nil

    var body: some View {
        if view.projects.isEmpty {
            Text(ProjectsLayout.emptyScreen)
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "#8E939C"))
                .multilineTextAlignment(.center)
                .padding(.leading, ProjectsLayout.screenLeading)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 14) {
                    ForEach(Array(view.projects.enumerated()), id: \.element.id) { index, project in
                        section(project)
                            .background {
                                if (index == 0 && onFirstFrame != nil) || (index == view.projects.count - 1 && onLastFrame != nil) {
                                    GeometryReader { geo in
                                        Color.clear.onAppear {
                                            if index == 0 { onFirstFrame?(geo.frame(in: .named("nm.island"))) }
                                            if index == view.projects.count - 1 { onLastFrame?(geo.frame(in: .named("nm.island"))) }
                                        }
                                    }
                                }
                            }
                    }
                }
                .padding(.top, ProjectsLayout.screenTopInset)
                .padding(.leading, ProjectsLayout.screenLeading)
                .padding(.trailing, 12)
                .padding(.bottom, ProjectsLayout.screenBottomInset)   // at least the island's corner radius: the rounded edge never slices the last row
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }

    private func section(_ project: PJProject) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                ProjectCatView(cat: project.cat, state: project.state, head: 20, active: active)
                Text(project.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if project.waiting > 0 {
                    Text(ProjectsLayout.waitingWord(project.waiting))
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Color(hex: ProjectsStyle.amber))
                }
                Spacer(minLength: 0)
            }
            ProjectRows(project: project, active: active, onRow: onRow)
                .padding(.leading, 28)
        }
        .opacity(project.dim ? 0.5 : 1)
    }
}

/// The peek over the left card: the project's name, its session count and its lines, on the card's own dark. It is the left card's size and corner
/// (`peekWidth`, `peekHeight`, `peekCorner`, clipped to it; the island places it on the card), and its lines are capped to the frame (`peekLineCapacity`): the
/// lines past the cap are "+N more", so nothing overhangs the card or clips mid-line.
struct ProjectsPeek: View {
    let project: PJProject
    let active: Bool
    /// Reports the peek's own drawn frame, in the "nm.island" coordinate space, when it appears (nil reports nothing). The render compares it with the left card's.
    var onFrame: ((CGRect) -> Void)? = nil
    /// Reports what its lines draw, as `ProjectRows.onDrawn` does (nil reports nothing). The render counts the drawn lines and reads the "+N more" text with it.
    var onDrawn: ((String, String) -> Void)? = nil
    /// Reports the header's frames ("name", "count"), as `ProjectBigCard.onFrame` does (nil reports nothing).
    var onTitle: ((String, CGRect) -> Void)? = nil

    var body: some View {
        VStack(alignment: .leading, spacing: ProjectsLayout.peekHeaderSpacing) {
            HStack(spacing: 6) {
                Text(project.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                    .lineLimit(1)
                    .truncationMode(.tail)
                    .reporting("name", project.name, onTitle, nil)
                // The name gives way first; the count keeps its whole width (as the big card's does).
                Text(ProjectsLayout.sessionsWord(project.sessionCount))
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#8E939C"))
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                    .layoutPriority(1)
                    .reporting("count", ProjectsLayout.sessionsWord(project.sessionCount), onTitle, nil)
                Spacer(minLength: 0)
            }
            .frame(height: ProjectsLayout.peekHeaderHeight)
            ProjectRows(project: project, active: active, limit: ProjectsLayout.peekLineCapacity, spacing: ProjectsLayout.lineSpacing,
                        rowHeight: ProjectsLayout.lineHeight, onDrawn: onDrawn)
        }
        .padding(ProjectsLayout.peekPadding)
        .frame(width: ProjectsLayout.peekWidth, height: ProjectsLayout.peekHeight, alignment: .topLeading)
        .background {
            if onFrame != nil {
                GeometryReader { geo in
                    Color.clear.onAppear { onFrame?(geo.frame(in: .named("nm.island"))) }
                }
            }
        }
        .background(RoundedRectangle(cornerRadius: ProjectsLayout.peekCorner).fill(Color(hex: "#141518")))
        .overlay(RoundedRectangle(cornerRadius: ProjectsLayout.peekCorner).stroke(Color.white.opacity(0.08), lineWidth: 1))
        .clipShape(RoundedRectangle(cornerRadius: ProjectsLayout.peekCorner))
    }
}

/// The compact island's waiting badge: the shelf badge's shape in amber, with the count in black. It is the waiting count, never an alert.
struct ProjectsBadgeView: View {
    let count: Int
    var height: CGFloat = 32

    var body: some View {
        let k = ProjectsLayout.badgeScale(height: height)
        ZStack {
            Circle().fill(Color(hex: ProjectsStyle.amber))
            Text("\(count)")
                .font(.system(size: 9, weight: .bold).monospacedDigit())
                .foregroundColor(Color(hex: "#0D0E10"))
                .minimumScaleFactor(0.7)
        }
        .frame(width: ProjectsLayout.badgeDiameter, height: ProjectsLayout.badgeDiameter)
        .scaleEffect(k)
        .accessibilityLabel(ProjectsLayout.badgeLabel(count))
    }
}

/// A project's subagents as kittens beside its cat, in `place` (CatIslandLayout's kitten box). A kitten is a small cat of the project's coat; it is not given the coat by
/// `useCharacter`, so it stays a kitten. It draws only while `active`, and not while there is none.
struct ProjectKittenLayer: View {
    let subagents: [PJSubagentRow]
    let parentCat: String
    let place: String
    let unit: CGFloat
    let active: Bool
    @StateObject private var herd = CatKittenHerd()

    var body: some View {
        let box = CatIslandLayout.kittenBox(place), u = Double(unit)
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active || subagents.isEmpty)) { timeline in
            Canvas { context, size in
                _ = timeline.date   // the Canvas redraws on every tick of the timeline
                let list = subagents.map { row in
                    CatKittens.Kitten(id: row.id, type: row.type, session: nil, state: row.state == "approval" ? .approval : .working, born: 0, last: 0)
                }
                let slots = CatKittens.slots(place, list)
                context.withCGContext { cg in
                    CatKittenDraw.draw(cg, slots, parentCat: parentCat, origin: (-box.x0 * u, -box.y0 * u), unit: u, colour: nil,
                                       dpr: Double(context.environment.displayScale), herd: herd, now: { CACurrentMediaTime() * 1000 }) { engine in
                        engine.update(dt: CatEngine.frameDelta(now: CACurrentMediaTime(), last: engine.lastTime))
                    }
                }
            }
        }
        .frame(width: (box.x1 - box.x0) * u, height: (box.y1 - box.y0) * u)
        .allowsHitTesting(false)
    }
}

/// The expanded section under the two panels: one row of columns, each a project's pill with its session count and age under it; the selected project is outlined.
struct ProjectsPanel: View {
    let cells: [ProjectsLayout.Cell]
    let projects: [PJProject]
    let selected: PJProject?
    let active: Bool
    let onSelect: (String) -> Void
    let onMore: () -> Void
    let onHover: (String, Bool) -> Void
    var onFrame: (String, CGRect) -> Void = { _, _ in }
    /// Reports the frames of what the section draws besides the pills ("header", "more"), in the "nm.island" space (nil reports nothing). The render checks them.
    var onLayout: ((String, CGRect) -> Void)? = nil
    /// Reports the strings of the same ("header": the line's words).
    var onDrawn: ((String, String) -> Void)? = nil

    /// The section's first line: "N projects" and, when any wait, " · M waiting" in amber (the words the Claude Code card's title row used to carry, which is only the count capsule now).
    private var headerWords: (projects: String, waiting: String) {
        let waiting = projects.reduce(0) { $0 + $1.waiting }
        return (ProjectsLayout.projectsWord(projects.count), waiting > 0 ? " · " + ProjectsLayout.waitingWord(waiting) : "")
    }

    var body: some View {
        let words = headerWords
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 0) {
                Text(words.projects).foregroundColor(Color(hex: "#8E939C"))
                Text(words.waiting).foregroundColor(Color(hex: ProjectsStyle.amber))
                Spacer(minLength: 0)
            }
            .font(.system(size: 11))
            .lineLimit(1)
            .padding(.leading, 4)
            .reporting("header", words.projects + words.waiting, onLayout, onDrawn)
            // Top-aligned, so a "+N" cell sits on the pills' row (a pill's tile also has its caption under it, which would centre it lower).
            HStack(alignment: .top, spacing: 6) {
                ForEach(cells, id: \.key) { cell in
                    tile(cell).frame(maxWidth: .infinity)
                }
            }
        }
        .padding(.horizontal, 8)
        .padding(.top, 8)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private func tile(_ cell: ProjectsLayout.Cell) -> some View {
        switch cell {
        case .project(let id):
            if let project = projects.first(where: { $0.id == id }) {
                VStack(spacing: 6) {
                    ProjectPill(project: project, active: active, onTap: { onSelect(id) }, onHover: { onHover(id, $0) }, onFrame: { onFrame(id, $0) })
                        .overlay(Capsule().stroke(Color.white.opacity(selected?.id == id ? 0.35 : 0), lineWidth: 1))
                    Text("\(ProjectsLayout.sessionsWord(project.sessionCount)) · \(ProjectsLayout.agoWord(project.agoMin))")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .lineLimit(1)
                }
            }
        case .more(let count):
            ProjectMoreCell(count: count, onTap: onMore)
                .reporting("more", "", onLayout, nil)
        case .pill:
            EmptyView()
        }
    }
}

/// The title rows' name and subtitle (the active session row always; the idle row only while the Projects count sits beside it): the name and the subtitle side by side when both fit whole,
/// else the name alone, which truncates at its tail. The subtitle is never squeezed: at a width it cannot have whole it is not drawn at all, so no fragment of it ("C", "(") shows
/// between the name and the count capsule. Both views come in with their own line limit.
struct ProjectsTitleFit<Name: View, Subtitle: View>: View {
    let name: Name
    let subtitle: Subtitle

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 6) {
                name
                subtitle
            }
            name
        }
    }
}

/// What the Claude Code card's title row adds with other agents and a live project: a small count capsule (the number of projects, and beside it an amber one with the waiting number
/// when any wait) and the chevron that opens the expanded section. The row already carries the session's name and its to-do count, so this is fixed in size and above the name in
/// layout priority; "N projects · M waiting" is the section's first line (`ProjectsPanel`).
struct ProjectsTitleRow {
    let projects: Int
    let waiting: Int
    let open: Bool
    let onToggle: () -> Void
}

struct ProjectsTitleRowView: View {
    let row: ProjectsTitleRow
    /// Reports the row's drawn frame under "count" (nil reports nothing). The render checks that it is whole.
    var onFrame: ((String, CGRect) -> Void)? = nil

    private func capsule(_ n: Int, text: String, fill: String) -> some View {
        Text("\(n)")
            .font(.system(size: 10, weight: .semibold).monospacedDigit())
            .foregroundColor(Color(hex: text))
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color(hex: fill).opacity(0.16)))
    }

    var body: some View {
        HStack(spacing: 4) {
            capsule(row.projects, text: "#8E939C", fill: "#FFFFFF")
            if row.waiting > 0 { capsule(row.waiting, text: ProjectsStyle.amber, fill: ProjectsStyle.amber) }
            Button(action: row.onToggle) {
                Image(systemName: row.open ? "chevron.up" : "chevron.down")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Color(hex: "#8E939C"))
                    .frame(width: 16, height: 16)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        .fixedSize(horizontal: true, vertical: false)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(ProjectsLayout.projectsWord(row.projects) + (row.waiting > 0 ? ", " + ProjectsLayout.waitingWord(row.waiting) : ""))
        .reporting("count", "", onFrame, nil)
        .layoutPriority(2)
    }
}

/// The Claude-only card's pill grid, as the overview hands it to `AgentPillsView`: the live projects (the waiting one leads), whether the views may move, what a click does,
/// and where the pills report their hover and their frames.
struct ProjectsGridInput {
    let projects: [PJProject]
    let active: Bool
    let onSelect: (String) -> Void
    let onMore: () -> Void
    let onHover: (String, Bool) -> Void
    let onFrame: (String, CGRect) -> Void
}
