import Foundation

// The Settings window's sizes and the rules that turn the window's width into a sidebar and a column (the restyle spec, "What is left to the builder"). The numbers are the starting
// values from the plan, tuned at checkpoint 1. The breakpoint is 600 pt: below it the sidebar collapses to icons. Pure Foundation; tests: tests/SettingsRulesTests.swift.

enum SettingsLayout {
    enum SidebarMode: Equatable, Sendable { case expanded, icons }

    static let minWidth = 415.0, minHeight = 420.0, defaultWidth = 720.0, defaultHeight = 560.0
    static let breakpoint = 600.0, sidebarWide = 200.0, sidebarIcons = 56.0, columnMax = 640.0
    static let padding = 20.0, paddingCollapsed = 16.0, fieldMax = 420.0, numberField = 64.0, pickerWidth = 180.0
    static let helpSize = 12.0, tabBarHeight = 28.0

    static func sidebarMode(windowWidth: Double) -> SidebarMode { windowWidth < breakpoint ? .icons : .expanded }

    static func sidebarWidth(_ mode: SidebarMode) -> Double { mode == .icons ? sidebarIcons : sidebarWide }

    static func padding(_ mode: SidebarMode) -> Double { mode == .icons ? paddingCollapsed : padding }

    static func detailWidth(windowWidth: Double) -> Double { windowWidth - sidebarWidth(sidebarMode(windowWidth: windowWidth)) }

    /// The width of the content column: the detail less the side padding on both sides, at most `columnMax`, never negative.
    static func columnWidth(windowWidth: Double) -> Double {
        let mode = sidebarMode(windowWidth: windowWidth)
        return max(0, min(detailWidth(windowWidth: windowWidth) - 2 * padding(mode), columnMax))
    }

    /// A path with the home folder shown as `~`. Only `home` itself or a path under `home/` changes; a longer name that starts the same way does not.
    static func displayPath(_ path: String, home: String) -> String {
        guard !home.isEmpty else { return path }
        if path == home { return "~" }
        if path.hasPrefix(home + "/") { return "~" + String(path.dropFirst(home.count)) }
        return path
    }

    /// A text (a preview of what an install writes) with the home folder shown as `~`, wherever it starts a path (`home/` in the text). Display only: the file keeps the real path.
    /// The JSON the hooks write escapes its slashes (`\/Users\/name\/`), so the escaped form is shown as `~\/` too. A longer name that starts the same way is not changed.
    static func displayText(_ text: String, home: String) -> String {
        guard !home.isEmpty else { return text }
        let plain = text.replacingOccurrences(of: home + "/", with: "~/")
        let escapedHome = home.replacingOccurrences(of: "/", with: "\\/") + "\\/"
        return plain.replacingOccurrences(of: escapedHome, with: "~\\/")
    }
}
