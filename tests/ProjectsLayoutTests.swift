import CoreGraphics
import Foundation

// The Projects island layout's Task 3 pins: the grid's and the panel's cells, the layout switch, the big cat's coat and state, the compact waiting badge's place
// (checked against ShelfBadge's own geometry) and the words, all Foundation and CoreGraphics only.
@main
enum ProjectsLayoutTests {
    typealias L = ProjectsLayout

    @MainActor
    static func main() {
        CT.section("constants: the contract's numbers and the layout's own")
        CT.check("gridCapacity is the 2×2 grid", L.gridCapacity, 4)
        CT.check("panelColumns is one row of three", L.panelColumns, 3)
        CT.checkNear("panelExtra is 92", Double(L.panelExtra), 92)
        CT.checkNear("screenHeight is 240", Double(L.screenHeight), 240)
        CT.checkNear("extraHeight starts at 0", Double(L.extraHeight), 0)
        CT.checkNear("peekDwell is 0.4 s (PEEK_DWELL_MS)", L.peekDwell, 0.4)
        CT.checkNear("badgeDiameter is ShelfBadge's diameter", Double(L.badgeDiameter), Double(ShelfBadge.diameter))
        CT.checkNear("badgeHitSlop is ShelfBadge's slop", Double(L.badgeHitSlop), Double(ShelfBadge.hitSlop))

        CT.section("the peek is the left card's frame, and its lines are capped to that frame")
        CT.checkNear("the island is 640 wide (IslandConst.expandedWidth)", Double(L.islandWidth), 640)
        CT.checkNear("the island is 160 high in the overview (IslandConst.viewLayouts[.overview].height)", Double(L.islandHeight), 160)
        CT.checkNear("the stack's top padding is 8", Double(L.contentTopPadding), 8)
        CT.checkNear("the header is 34 high", Double(L.headerHeight), 34)
        CT.checkNear("the stack's bottom padding is 10", Double(L.contentBottomPadding), 10)
        CT.checkNear("the content view is 98 high", Double(L.contentHeight), 98)
        CT.checkNear("the content's side inset is 10", Double(L.contentSideInset), 10)
        CT.checkNear("the left card's origin x is 10 (the content's side inset)", Double(L.leftCardOrigin.x), 10)
        CT.checkNear("the left card's origin y is 47: 8 + 34 + the 10 pt the 98 pt view leaves in the 108 pt stack middle, centred", Double(L.leftCardOrigin.y), 47)
        CT.checkNear("the left card is 322 wide", Double(L.leftCardWidth), 322)
        CT.checkNear("the left card is 98 tall (the content frame)", Double(L.leftCardHeight), 98)
        CT.checkNear("the left card's corner is CardBackground's 20", Double(L.leftCardCorner), 20)
        CT.check("the peek's line capacity is 3 at the card's height", L.peekLineCapacity, 3)
        let capacityHeight = L.peekHeaderHeight + L.peekHeaderSpacing + CGFloat(L.peekLineCapacity) * L.lineHeight
            + CGFloat(L.peekLineCapacity - 1) * L.lineSpacing + 2 * L.peekPadding
        CT.checkTrue("the capacity's lines fit the peek's height", capacityHeight <= L.peekHeight)
        CT.checkTrue("one line more would not fit, so the capacity is the most that fit", capacityHeight + L.lineSpacing + L.lineHeight > L.peekHeight)

        CT.section("cut: the lines a list draws, the last one '+N more' when lines are cut")
        let cap = L.peekLineCapacity
        let few = L.cut(lines: 2, capacity: cap)
        CT.check("lines within capacity: all shown", few.shown, 2)
        CT.check("lines within capacity: no more line", few.more, 0)
        let full = L.cut(lines: cap, capacity: cap)
        CT.check("exactly capacity lines: all shown", full.shown, cap)
        CT.check("exactly capacity lines: no more line", full.more, 0)
        let one = L.cut(lines: cap + 1, capacity: cap)
        CT.check("capacity + 1 lines: capacity - 1 shown", one.shown, cap - 1)
        CT.check("capacity + 1 lines: two more (the last line is '+2 more')", one.more, 2)
        let many = L.cut(lines: 12, capacity: cap)
        CT.check("12 lines: capacity - 1 shown", many.shown, cap - 1)
        CT.check("12 lines: the rest counted", many.more, 12 - (cap - 1))
        CT.check("12 lines: exactly capacity lines drawn, the last the more line", many.shown + 1, cap)
        CT.check("no lines, no more line", L.cut(lines: 0, capacity: cap).more, 0)

        CT.section("gridCells: the Claude-only right card (capacity 4)")
        let p = ["p1", "p2", "p3", "p4", "p5", "p6", "p7"]
        CT.check("no projects, two pills: the pills", L.gridCells(projects: [], otherPills: ["a", "b"]), [.pill("a"), .pill("b")])
        CT.check("no projects, five pills: truncated to capacity", L.gridCells(projects: [], otherPills: ["a", "b", "c", "d", "e"]).count, 4)
        CT.check("three projects, two pills: the projects then the first pill",
                 L.gridCells(projects: Array(p[0..<3]), otherPills: ["a", "b"]), [.project("p1"), .project("p2"), .project("p3"), .pill("a")])
        CT.check("four projects: no pill", L.gridCells(projects: Array(p[0..<4]), otherPills: ["a", "b"]), [.project("p1"), .project("p2"), .project("p3"), .project("p4")])
        CT.check("five projects: three then +2", L.gridCells(projects: Array(p[0..<5]), otherPills: ["a"]), [.project("p1"), .project("p2"), .project("p3"), .more(2)])
        CT.check("seven projects: three then +4", L.gridCells(projects: p, otherPills: []), [.project("p1"), .project("p2"), .project("p3"), .more(4)])

        CT.section("panelCells: the expanded section (three columns)")
        CT.check("one project", L.panelCells(projects: ["p1"]), [.project("p1")])
        CT.check("three projects: all three", L.panelCells(projects: Array(p[0..<3])), [.project("p1"), .project("p2"), .project("p3")])
        CT.check("four projects: two then +2", L.panelCells(projects: Array(p[0..<4])), [.project("p1"), .project("p2"), .more(2)])
        CT.check("seven projects: two then +5", L.panelCells(projects: p), [.project("p1"), .project("p2"), .more(5)])

        CT.section("a cell's key is its identity in the grid and the section: the project's id, never its slot")
        CT.check("a project's key", L.Cell.project("a").key, "p:a")
        CT.check("another agent's pill's key", L.Cell.pill("a").key, "pill:a")
        CT.check("the +N cell's key does not depend on its count", L.Cell.more(2).key, L.Cell.more(9).key)
        CT.check("the +N cell's key", L.Cell.more(2).key, "more")
        let ordered = L.gridCells(projects: ["p1", "p2", "p3"], otherPills: ["p1"]), reordered = L.gridCells(projects: ["p3", "p1", "p2"], otherPills: ["p1"])
        CT.check("a reorder keeps every project's key (it moves, it is not renamed)", Set(ordered.map { $0.key }), Set(reordered.map { $0.key }))
        CT.check("a reorder changes the keys' order (slot 0 is another cell)", reordered.map { $0.key }, ["p:p3", "p:p1", "p:p2", "pill:p1"])
        CT.check("a project and a pill of the same id never share a key", Set(ordered.map { $0.key }).count, ordered.count)
        CT.check("the +N cell never shares a key with a project named \"more\"", Set([L.Cell.more(1).key, L.Cell.project("more").key]).count, 2)

        CT.section("usesProjects: the Claude-only card, and Two cats mode keeps today's overview")
        CT.checkTrue("projects, no focus, one project, one cat", L.usesProjects(layout: .projects, focusId: nil, projectCount: 1, twoCats: false))
        CT.checkTrue("projects, the Claude pill focused", L.usesProjects(layout: .projects, focusId: "integration_claude", projectCount: 2, twoCats: false))
        CT.checkTrue("another pill focused: today's card", !L.usesProjects(layout: .projects, focusId: "integration_github", projectCount: 2, twoCats: false))
        CT.checkTrue("no project live: today's card", !L.usesProjects(layout: .projects, focusId: nil, projectCount: 0, twoCats: false))
        CT.checkTrue("the agents layout: today's card", !L.usesProjects(layout: .agents, focusId: nil, projectCount: 2, twoCats: false))
        CT.checkTrue("Two cats mode: today's overview", !L.usesProjects(layout: .projects, focusId: nil, projectCount: 2, twoCats: true))

        CT.section("panelShown: the chevron's section, with other agents")
        CT.checkTrue("open, agents, the Claude pill, a project", L.panelShown(panelOpen: true, layout: .agents, focusId: "integration_claude", projectCount: 1, twoCats: false))
        CT.checkTrue("folded: no section", !L.panelShown(panelOpen: false, layout: .agents, focusId: "integration_claude", projectCount: 1, twoCats: false))
        CT.checkTrue("Claude-only layout: no section", !L.panelShown(panelOpen: true, layout: .projects, focusId: "integration_claude", projectCount: 1, twoCats: false))
        CT.checkTrue("another pill focused: no section", !L.panelShown(panelOpen: true, layout: .agents, focusId: "integration_github", projectCount: 1, twoCats: false))
        CT.checkTrue("no project: no section", !L.panelShown(panelOpen: true, layout: .agents, focusId: "integration_claude", projectCount: 0, twoCats: false))
        CT.checkTrue("Two cats mode keeps today's overview: no section", !L.panelShown(panelOpen: true, layout: .agents, focusId: "integration_claude", projectCount: 1, twoCats: true))
        CT.checkTrue("not Two cats: the section", L.panelShown(panelOpen: true, layout: .agents, focusId: "integration_claude", projectCount: 1, twoCats: false))

        CT.section("bigCoat: the big card's project's cat, else the cast's")
        CT.check("the project's cat when it follows the card", L.bigCoat(castCoat: "ginger", usesProjects: true, expandedOverview: true, projectCat: "momo"), "momo")
        CT.check("the cast's when the card is not used", L.bigCoat(castCoat: "ginger", usesProjects: false, expandedOverview: true, projectCat: "momo"), "ginger")
        CT.check("the cast's when the overview is folded", L.bigCoat(castCoat: "ginger", usesProjects: true, expandedOverview: false, projectCat: "momo"), "ginger")
        CT.check("the cast's when the project has no cat", L.bigCoat(castCoat: "ginger", usesProjects: true, expandedOverview: true, projectCat: nil), "ginger")

        CT.section("bigState: the big card's project's state, else the cast's")
        CT.check("a waiting project makes the big cat wait", L.bigState(castState: "working", usesProjects: true, expandedOverview: true, projectState: "approval"), "approval")
        CT.check("an idle project makes the big cat idle, even while the cast works", L.bigState(castState: "working", usesProjects: true, expandedOverview: true, projectState: "idle"), "idle")
        CT.check("no project state: the cast's", L.bigState(castState: "working", usesProjects: true, expandedOverview: true, projectState: nil), "working")
        CT.check("the card not used: the cast's", L.bigState(castState: "working", usesProjects: false, expandedOverview: true, projectState: "approval"), "working")
        CT.check("the overview folded: the cast's", L.bigState(castState: "working", usesProjects: true, expandedOverview: false, projectState: "approval"), "working")

        CT.section("badgeShown: only compact, waiting, and not under the greeting's tail")
        CT.checkTrue("compact with a waiting project", L.badgeShown(compact: true, waiting: 1, greetingTail: false))
        CT.checkTrue("expanded: no badge", !L.badgeShown(compact: false, waiting: 1, greetingTail: false))
        CT.checkTrue("nothing waiting: no badge", !L.badgeShown(compact: true, waiting: 0, greetingTail: false))
        CT.checkTrue("the greeting's tail: no badge", !L.badgeShown(compact: true, waiting: 1, greetingTail: true))

        CT.section("badge geometry: the centre, the scale and the hit rect against ShelfBadge")
        CT.check("centre at 344 × 32", L.badgeCenter(islandWidth: 344, height: 32), CGPoint(x: 278, y: 16))
        CT.check("centre at 344 × 24", L.badgeCenter(islandWidth: 344, height: 24), CGPoint(x: 278, y: 12))
        for h in [CGFloat(0), 4, 24, 32, 40] {
            CT.checkNear("badgeScale(\(h)) is ShelfBadge.scale", Double(L.badgeScale(height: h)), Double(ShelfBadge.scale(height: h)))
        }
        let island32 = CGRect(x: 0, y: 0, width: 344, height: 32)
        let island24 = CGRect(x: 0, y: 0, width: 344, height: 24)
        let hit32 = L.badgeHitRect(island: island32), hit24 = L.badgeHitRect(island: island24)
        CT.check("hit rect at 32 pt", hit32, CGRect(x: 267, y: 5, width: 22, height: 22))
        CT.checkNear("hit rect at 24 pt: left edge", Double(hit24.minX), 269)
        CT.checkNear("hit rect at 24 pt: right edge", Double(hit24.maxX), 287)
        CT.checkNear("hit rect at 24 pt: side", Double(hit24.width), 18)
        CT.checkTrue("32 pt: clear of ShelfBadge's hit rect", !hit32.intersects(ShelfBadge.hitRect(island: island32)))
        CT.checkTrue("24 pt: clear of ShelfBadge's hit rect", !hit24.intersects(ShelfBadge.hitRect(island: island24)))
        CT.checkTrue("32 pt: right of the notch (80 pt from the edge)", hit32.minX >= island32.maxX - 80)
        CT.checkTrue("24 pt: right of the notch (80 pt from the edge)", hit24.minX >= island24.maxX - 80)
        CT.checkTrue("32 pt: left of the grid's span (55 pt in)", hit32.maxX <= island32.maxX - 54 - 1)
        CT.checkTrue("24 pt: left of the grid's span (55 pt in)", hit24.maxX <= island24.maxX - 54 - 1)

        CT.section("words: the exact copy")
        CT.check("host claude-app", L.hostWord("claude-app"), "Claude App")
        CT.section("the Projects screen: top-aligned under the header, scrolled, and the left kept for the big cat")
        CT.checkNear("the screen's first section starts 4 pt under the header's bottom", Double(L.screenTopInset), 4)
        CT.checkNear("the screen leaves 80 pt at the left of the content (x 90 in the island, where the shelf's content starts)", Double(L.screenLeading), 80)
        CT.checkNear("the island's expanded corner is 22 (IslandConst.expandedCorner)", Double(L.islandCorner), 22)
        CT.checkTrue("the screen's list ends at least a corner's radius above the end of the scroll content, so the rounded edge never slices a row there", L.screenBottomInset >= L.islandCorner)
        CT.checkNear("the header's bottom is 8 + 34 = 42 in the island", Double(L.contentTopPadding + L.headerHeight), 42)
        CT.checkTrue("the scroll area (the island less the top 42 and the bottom padding) is shorter than a project with two sessions, six of them", L.screenHeight - L.contentTopPadding - L.headerHeight - L.contentBottomPadding < 6 * 60)

        CT.section("a pill's name in two parts: the folder, and what tells two folders of one name apart")
        func parts(_ name: String) -> [String?] { let p = L.pillNameParts(name); return [p.folder, p.detail] }
        CT.check("a plain name has no detail", parts("notchmeow"), ["notchmeow", nil])
        CT.check("folder and parent split at the first ' — '", parts("notchmeow — GitHub Local Repos"), ["notchmeow", "GitHub Local Repos"])
        CT.check("the rest of the name is the detail, a number included", parts("site — a · 2"), ["site", "a · 2"])
        CT.check("a number without a parent is no split (the name keeps its ' · 2')", parts("site · 2"), ["site · 2", nil])
        CT.check("a later ' — ' stays in the detail", parts("a — b — c"), ["a", "b — c"])
        CT.check("an empty parent leaves no detail", parts("site — "), ["site", nil])
        CT.check("an empty folder is no split: the whole name is the folder", parts(" — a"), [" — a", nil])
        CT.check("the empty name", parts(""), ["", nil])
        CT.check("two colliding long names differ in their details, not their folders",
                 [L.pillNameParts("notchmeow — GitHub Local Repos").folder == L.pillNameParts("notchmeow — nm-projects-demo").folder,
                  L.pillNameParts("notchmeow — GitHub Local Repos").detail != L.pillNameParts("notchmeow — nm-projects-demo").detail], [true, true])

        CT.check("host vscode", L.hostWord("vscode"), "VS Code")
        CT.check("host terminal", L.hostWord("terminal"), "Terminal")
        CT.check("host anything else", L.hostWord("cursor"), "Terminal")
        CT.check("ago 0", L.agoWord(0), "now")
        CT.check("ago 1", L.agoWord(1), "1 min ago")
        CT.check("ago 59", L.agoWord(59), "59 min ago")
        CT.check("ago 60", L.agoWord(60), "1 h ago")
        CT.check("ago 125", L.agoWord(125), "2 h ago")
        CT.check("sessions 1", L.sessionsWord(1), "1 session")
        CT.check("sessions 0", L.sessionsWord(0), "0 sessions")
        CT.check("sessions 3", L.sessionsWord(3), "3 sessions")
        CT.check("projects 1", L.projectsWord(1), "1 project")
        CT.check("projects 2", L.projectsWord(2), "2 projects")
        CT.check("waiting", L.waitingWord(2), "2 waiting")
        CT.check("more", L.moreWord(4), "+4")
        CT.check("subagent with a type", L.subagentWord("Explore"), "Explore")
        CT.check("subagent without a type", L.subagentWord(""), "subagent")
        CT.check("row detail: the note when there is one", L.rowDetail(note: "Fixing tests", step: "Runs"), "Fixing tests")
        CT.check("row detail: the step without a note", L.rowDetail(note: "", step: "Runs"), "Runs")
        CT.check("menu title with no project", L.menuTitle(0), "Projects")
        CT.check("menu title with projects", L.menuTitle(3), "Projects (3)")
        CT.check("pin title when not pinned", L.pinTitle(pinned: false), "Pin")
        CT.check("pin title when pinned", L.pinTitle(pinned: true), "Unpin")
        CT.check("badge label", L.badgeLabel(2), "Projects, 2 waiting")
        CT.check("empty screen", L.emptyScreen, "No Claude Code session is running.")
        CT.check("empty settings", L.emptySettings, "No Claude Code project is running. Each one is listed here while it runs, and keeps the cat you give it.")

        CT.finish()
    }
}
