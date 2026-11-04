import AppKit

// The island cat's right-click menu (sub-project I): a new menu with only Wardrobe in it for now, as an `NSMenu` built from the pure `WardrobeMenu.items` (the same items the desktop cat's menu
// turns into its own Wardrobe submenu). A pick goes to the store (`CatSettingsStore.setOutfit`); the clock that resolves it follows. The menu is built on every right-click, so the check and
// Auto's label are always today's. Not in the contract, and the test programs do not compile this file.

@MainActor
final class WardrobeMenuTarget: NSObject {
    static let shared = WardrobeMenuTarget()
    /// The tag of a menu item that picks `Wardrobe.ids[tag - tagBase]` (the desktop cat's menu uses the same numbers).
    static let tagBase = 100

    static func tag(for id: String) -> Int { tagBase + (Wardrobe.ids.firstIndex(of: id) ?? 0) }
    static func id(forTag tag: Int) -> String? { Wardrobe.ids.indices.contains(tag - tagBase) ? Wardrobe.ids[tag - tagBase] : nil }

    @objc func picked(_ item: NSMenuItem) {
        guard let id = Self.id(forTag: item.tag) else { return }
        CatSettingsStore.shared.setOutfit(id)
    }

    /// The Wardrobe submenu: 18 choices in their groups, a check on the stored one.
    static func wardrobeSubmenu() -> NSMenu {
        let sub = NSMenu(title: "Wardrobe")
        for item in WardrobeMenu.items(selected: CatSettingsStore.shared.wardrobe.outfit, autoToday: Wardrobe.autoOutfit(WardrobeClock.appToday())) {
            switch item {
            case .separator: sub.addItem(.separator())
            case .heading(let name):
                let h = NSMenuItem(title: name, action: nil, keyEquivalent: "")
                h.isEnabled = false
                sub.addItem(h)
            case .choice(let id, let title, let checked):
                let i = NSMenuItem(title: title, action: #selector(WardrobeMenuTarget.picked(_:)), keyEquivalent: "")
                i.target = shared; i.tag = tag(for: id); i.state = checked ? .on : .off
                sub.addItem(i)
            }
        }
        return sub
    }

    /// The island cat's menu: Wardrobe, and nothing else for now.
    static func islandCatMenu() -> NSMenu {
        let menu = NSMenu()
        let item = NSMenuItem(title: "Wardrobe", action: nil, keyEquivalent: "")
        item.submenu = wardrobeSubmenu()
        menu.addItem(item)
        return menu
    }
}
