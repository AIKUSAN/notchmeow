import Foundation

// The Settings window's pages and tabs, and how an old stored section maps to one of them (the restyle spec's rule 9: `settingsSection` keeps working, `settingsTab.<page>` is the only new
// key). Pure values: no view, no UserDefaults. The window's shell reads the stored tags through `migrate` and `tab(for:stored:)`, so a stored value from an older build, or a tab that is
// hidden, never leaves a blank detail. Tests: tests/SettingsRulesTests.swift (scripts/test-settings-rules.sh).

enum SettingsRoute {
    enum Page: String, CaseIterable, Sendable { case general, agents, chat, services, cat, devices }

    enum Tab: String, CaseIterable, Sendable {
        case general, shortcuts, yourAI = "yourai", keys, localModels = "localmodels", sidekick, companion,
             look, outfits, personality, agentCats = "agentcats"
    }

    struct Place: Equatable, Sendable {
        var page: Page
        var tab: Tab? = nil
    }

    /// The Companion tab (F3a).
    static let companionTabShown = true
    static let sectionKey = "settingsSection"

    static func tabKey(_ page: Page) -> String { "settingsTab.\(page.rawValue)" }

    static func title(_ page: Page) -> String {
        switch page {
        case .general: return "General"
        case .agents: return "Agents"
        case .chat: return "AI and chat"
        case .services: return "Services"
        case .cat: return "Cat"
        case .devices: return "Devices"
        }
    }

    static func title(_ tab: Tab) -> String {
        switch tab {
        case .general: return "General"
        case .shortcuts: return "Shortcuts"
        case .yourAI: return "Your AI"
        case .keys: return "Keys"
        case .localModels: return "Local models"
        case .sidekick: return "Sidekick"
        case .companion: return "Companion"
        case .look: return "Look"
        case .outfits: return "Outfits"
        case .personality: return "Personality"
        case .agentCats: return "Agents' cats"
        }
    }

    /// The sidebar's coloured tile: the symbol and its colour (the existing `SettingsSidebarRow` colours).
    static func icon(_ page: Page) -> (symbol: String, color: String) {
        switch page {
        case .general: return ("gearshape.fill", "#8E939C")
        case .agents: return ("terminal.fill", "#3B9EFF")
        case .chat: return ("bubble.left.and.bubble.right.fill", "#E07950")
        case .services: return ("puzzlepiece.extension.fill", "#7C5CFF")
        case .cat: return ("pawprint.fill", "#D9A066")
        case .devices: return ("laptopcomputer.and.iphone", "#5B8DEF")
        }
    }

    /// The tabs a page shows, in order. Agents, Services and Devices have none.
    static func tabs(_ page: Page, companion: Bool = companionTabShown) -> [Tab] {
        switch page {
        case .general: return [.general, .shortcuts]
        case .chat: return [.yourAI, .keys, .localModels, .sidekick] + (companion ? [.companion] : [])
        case .cat: return [.look, .outfits, .personality, .agentCats]
        case .agents, .services, .devices: return []
        }
    }

    /// The place an old or new stored section names. A bare page or an old tag gives its page; `<page>/<tab>` gives that tab when the page shows it; anything else is General.
    static func migrate(storedSection: String?) -> Place {
        guard let raw = storedSection else { return Place(page: .general) }
        switch raw {
        case "activepills": return Place(page: .general)
        case "integrations": return Place(page: .services)
        case "shortcuts": return Place(page: .general, tab: .shortcuts)
        case "sidekick": return Place(page: .chat, tab: .sidekick)
        default: break
        }
        let parts = raw.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard let page = Page(rawValue: parts[0]) else { return Place(page: .general) }
        if parts.count == 2, let tab = Tab(rawValue: parts[1]), tabs(page).contains(tab) { return Place(page: page, tab: tab) }
        return Place(page: page)
    }

    /// The tab to show on a page: the stored one when the page shows it, else its first tab; nil for a page without tabs.
    static func tab(for page: Page, stored: String?) -> Tab? {
        let visible = tabs(page)
        guard let first = visible.first else { return nil }
        if let stored, let tab = Tab(rawValue: stored), visible.contains(tab) { return tab }
        return first
    }
}
