import CoreGraphics
import Foundation

// The Projects island's layout rules and words (P-mac, Task 3). Pure: Foundation and CoreGraphics only, and no other app file. The island and its views read these;
// `ProjectsModel` writes `extraHeight` (the expanded section's height) and nothing else here. The badge's scale is ShelfBadge's rule, copied: the badge sits beside
// ShelfBadge, and the test pins both to the same numbers.

enum ProjectsLayout {
    /// The Claude-only right card is the existing 2×2 pill grid.
    static let gridCapacity = 4
    /// The expanded section under the two panels is one row of three columns.
    static let panelColumns = 3
    /// The expanded section's height under the two panels (Plan call).
    static let panelExtra: CGFloat = 92
    /// The Projects screen's height (the island's content when it shows the screen).
    static let screenHeight: CGFloat = 240
    /// The screen's list is top-aligned: its first section starts this far under the header's bottom (island y 42), and it scrolls past the island's height.
    static let screenTopInset: CGFloat = 4
    /// The big cat keeps the left of the screen (`IslandConst.viewLayouts[.projects]`: x 54, 46 wide, so its head ends at 77): the list starts 80 pt in from the
    /// content's 10 pt side inset, island x 90, where the shelf's content starts. `ProjectsWiringTests` pins that the cat's head ends before it.
    static let screenLeading: CGFloat = 80
    /// The island's expanded corner radius (IslandConst.expandedCorner; ProjectsWiringTests pins that they are one number). The list ends this far above the end of the scroll content,
    /// so a row scrolled to the end is never sliced by the island's rounded edge.
    static let islandCorner: CGFloat = 22
    static let screenBottomInset: CGFloat = islandCorner
    /// The section's extra height, read by `islandSize` for the overview; written only by `ProjectsModel`.
    nonisolated(unsafe) static var extraHeight: CGFloat = 0

    enum Cell: Equatable, Sendable {
        case project(String), more(Int), pill(String)

        /// What a ForEach keys the cell by: a cell is its project (or pill), never its slot, so a reorder moves the view and its state with it. The "+N" cell is one cell whatever its count.
        var key: String {
            switch self {
            case .project(let id): return "p:" + id
            case .more: return "more"
            case .pill(let id): return "pill:" + id
            }
        }
    }

    /// The Claude-only right card: the projects first (the waiting one leads, the caller orders them), then the other pills while they fit; past the capacity the last
    /// cell is "+N" for the rest.
    static func gridCells(projects: [String], otherPills: [String], capacity: Int = gridCapacity) -> [Cell] {
        if projects.count <= capacity {
            return projects.map { Cell.project($0) } + otherPills.prefix(capacity - projects.count).map { Cell.pill($0) }
        }
        return projects.prefix(capacity - 1).map { Cell.project($0) } + [Cell.more(projects.count - (capacity - 1))]
    }

    /// The expanded section: one row of `columns`, the same rule as the grid without pills.
    static func panelCells(projects: [String], columns: Int = panelColumns) -> [Cell] {
        if projects.count <= columns { return projects.map { Cell.project($0) } }
        return projects.prefix(columns - 1).map { Cell.project($0) } + [Cell.more(projects.count - (columns - 1))]
    }

    /// The Claude-only card replaces today's left and right cards only in the projects layout, with the Claude pill (or no focus) and at least one live project.
    /// Two cats mode keeps today's overview (Plan call 26).
    static func usesProjects(layout: ProjectsRules.Layout, focusId: String?, projectCount: Int, twoCats: Bool) -> Bool {
        guard !twoCats, projectCount >= 1, layout == .projects else { return false }
        return focusId == nil || focusId == "integration_claude"
    }

    /// The section under the two panels: opened by the chevron, with other agents, the Claude pill focused and a live project. Two cats mode keeps today's overview
    /// entirely, so it has no section either (owner's ruling at Checkpoint 1).
    static func panelShown(panelOpen: Bool, layout: ProjectsRules.Layout, focusId: String?, projectCount: Int, twoCats: Bool) -> Bool {
        !twoCats && panelOpen && layout == .agents && focusId == "integration_claude" && projectCount >= 1
    }

    /// The big cat's coat: the big card's project's cat while the card shows projects in the expanded overview, else the cast's coat.
    static func bigCoat(castCoat: String, usesProjects: Bool, expandedOverview: Bool, projectCat: String?) -> String {
        guard usesProjects, expandedOverview, let cat = projectCat else { return castCoat }
        return cat
    }

    /// The big cat's state: the big card's project's state under the same rule as `bigCoat`, else the cast's state.
    static func bigState(castState: String, usesProjects: Bool, expandedOverview: Bool, projectState: String?) -> String {
        guard usesProjects, expandedOverview, let state = projectState else { return castState }
        return state
    }

    // MARK: - The compact waiting badge

    /// The badge's diameter (pt) and how far beyond it a click still counts; the right wing's inner end, between the notch and the grid.
    static let badgeDiameter: CGFloat = 14
    static let badgeInset: CGFloat = 66
    static let badgeHitSlop: CGFloat = 4

    /// Only in the compact island, with something waiting, and not under the greeting's tail (which still draws the session cats in the grid's place).
    static func badgeShown(compact: Bool, waiting: Int, greetingTail: Bool) -> Bool {
        compact && !greetingTail && waiting > 0
    }

    /// The strip shrinks the grid below 32 pt; the badge shrinks with it (ShelfBadge's rule).
    static func badgeScale(height: CGFloat) -> CGFloat { min(1, max(0, height - 4) / 28) }

    /// The badge's centre in the island's own coordinates (y down, the top left the origin).
    static func badgeCenter(islandWidth: CGFloat, height: CGFloat) -> CGPoint {
        CGPoint(x: islandWidth - badgeInset, y: height / 2)
    }

    /// The square a click counts in, in the same coordinates as `island`.
    static func badgeHitRect(island: CGRect) -> CGRect {
        let r = badgeDiameter / 2 * badgeScale(height: island.height) + badgeHitSlop
        let c = CGPoint(x: island.maxX - badgeInset, y: island.midY)
        return CGRect(x: c.x - r, y: c.y - r, width: 2 * r, height: 2 * r)
    }

    /// The Projects peek's dwell, in seconds (PEEK_DWELL_MS).
    static let peekDwell: Double = ProjectsRules.peekDwellMs / 1000

    // MARK: - The overview's left card, and the peek over it

    /// The shipping island's expanded width (IslandConst.expandedWidth), and the island's height in the overview (IslandConst.viewLayouts[.overview].height).
    static let islandWidth: CGFloat = 640
    static let islandHeight: CGFloat = 160
    /// IslandContentView's stack: 8 pt of top padding, the 34 pt header, 10 pt of bottom padding, and the view's 98 pt frame. The stack's middle is what is left
    /// between the header and the bottom padding (108 pt), and the 98 pt view is centred in it. The content's side inset is 10 pt (the same stack's horizontal padding).
    static let contentTopPadding: CGFloat = 8
    static let headerHeight: CGFloat = 34
    static let contentBottomPadding: CGFloat = 10
    static let contentHeight: CGFloat = 98
    static let contentSideInset: CGFloat = 10

    /// The overview's left card: its origin is the content's inset from the side, and the top of the 98 pt view centred in the stack's middle, which is y 47
    /// (8 + 34 + (160 − 8 − 34 − 10 − 98) / 2). The card is 322 wide (OverviewView's frame) and fills the 98 pt view; CardBackground's corner is 20.
    static let leftCardOrigin = CGPoint(
        x: contentSideInset,
        y: contentTopPadding + headerHeight + (islandHeight - contentTopPadding - headerHeight - contentBottomPadding - contentHeight) / 2)
    static let leftCardWidth: CGFloat = 322
    static let leftCardHeight: CGFloat = 98
    static let leftCardCorner: CGFloat = 20

    /// The peek is the left card's size and corner (its origin is the left card's, set where the island places it). One source, so it cannot drift from the card.
    static let peekWidth = leftCardWidth
    static let peekHeight = leftCardHeight
    static let peekCorner = leftCardCorner

    /// The peek's inside: its padding, its name line, and its lines. A session or a subagent is one line of `lineHeight` (a subagent's cat is drawn beyond it, centred),
    /// and the lines are `lineSpacing` apart.
    static let peekPadding: CGFloat = 10
    static let peekHeaderHeight: CGFloat = 16
    static let peekHeaderSpacing: CGFloat = 6
    static let lineHeight: CGFloat = 14
    static let lineSpacing: CGFloat = 2

    /// How many lines the peek draws: the lines that fit under its name line, the last of them "+N more" when lines are cut (`cut`). Derived from the frame.
    static let peekLineCapacity = Int((peekHeight - 2 * peekPadding - peekHeaderHeight - peekHeaderSpacing + lineSpacing) / (lineHeight + lineSpacing))

    /// The lines a list draws: all of them when `lines` fit `capacity`; else the first `capacity` - 1 and "+N more" for the rest, so exactly `capacity` lines show
    /// (the `more` count is the lines not shown, the "+N more" line itself not among them).
    static func cut(lines: Int, capacity: Int) -> (shown: Int, more: Int) {
        guard lines > capacity else { return (lines, 0) }
        let shown = max(0, capacity - 1)
        return (shown, lines - shown)
    }

    // MARK: - The words

    static func hostWord(_ host: String) -> String {
        switch host {
        case "claude-app": return "Claude App"
        case "vscode": return "VS Code"
        default: return "Terminal"
        }
    }

    static func agoWord(_ minutes: Int) -> String {
        if minutes < 1 { return "now" }
        if minutes < 60 { return "\(minutes) min ago" }
        return "\(minutes / 60) h ago"
    }

    /// A project pill's text area: clear of the cat (leading) and of the state dot at the pill's top right (trailing). Under a two-line name the dot sits above the second line,
    /// so that line may come closer to the edge.
    static let pillLeading: CGFloat = 34
    static let pillTrailing: CGFloat = 14
    static let pillTrailingTwoLines: CGFloat = 8

    /// A project's name as a pill draws it: the folder, and under it what tells two folders of one name apart. Names are "<folder>", "<folder> — <parent>" and
    /// "<folder> — <parent> · 2" (`ProjectsRules.projectNames`); the split is at the first " — ", and the detail keeps the rest. No " — " or an empty folder is no split (the whole name is the folder); an empty detail
    /// ("site — ") is no detail: the folder alone, the dash dropped. (A single line cut at its end would show "notchmeow —…" for two different folders.)
    static func pillNameParts(_ name: String) -> (folder: String, detail: String?) {
        guard let r = name.range(of: " — "), r.lowerBound > name.startIndex else { return (name, nil) }
        let detail = String(name[r.upperBound...])
        return (String(name[..<r.lowerBound]), detail.isEmpty ? nil : detail)
    }

    static func sessionsWord(_ n: Int) -> String { n == 1 ? "1 session" : "\(n) sessions" }

    static func projectsWord(_ n: Int) -> String { n == 1 ? "1 project" : "\(n) projects" }

    static func waitingWord(_ n: Int) -> String { "\(n) waiting" }

    static func moreWord(_ n: Int) -> String { "+\(n)" }

    /// The last line of a peek whose rows do not all fit.
    static func moreRowsWord(_ n: Int) -> String { "+\(n) more" }

    static func subagentWord(_ type: String) -> String { type.isEmpty ? "subagent" : type }

    /// A session row's detail line: its note when it has one, else its step.
    static func rowDetail(note: String, step: String) -> String { note.isEmpty ? step : note }

    static func menuTitle(_ projects: Int) -> String { projects == 0 ? "Projects" : "Projects (\(projects))" }

    static func pinTitle(pinned: Bool) -> String { pinned ? "Unpin" : "Pin" }

    static func badgeLabel(_ waiting: Int) -> String { "Projects, \(waiting) waiting" }

    static let emptyScreen = "No Claude Code session is running."
    static let emptySettings = "No Claude Code project is running. Each one is listed here while it runs, and keeps the cat you give it."
}
