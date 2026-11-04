import AppKit
import SwiftUI

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSMenuDelegate {
    var statusItem: NSStatusItem?
    private(set) var islandController: IslandWindowController?
    /// The desktop cat (sub-project H), made once the island exists.
    private(set) var desktopCat: DesktopCatController?

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyCenter.shared.unregisterAll()
        #if !APPSTORE
        // Quitting mid-turn: hand the waiting approvals back, then end every running `claude` and what it started
        // (synchronous, at most about a second): nothing may outlive the app.
        HookServer.shared.cancelChatApprovals()
        ClaudeRunRegistry.stopAll()
        #endif
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Ignore SIGPIPE — prevents crash when nm-hook closes socket before we write response
        signal(SIGPIPE, SIG_IGN)
        // Warm up Keychain cache on main thread BEFORE any poller or view touches it
        _ = KeychainStore.shared
        // The cat settings are read before the first cat is made, so the notch opens with the cat the user picked.
        _ = CatSettingsStore.shared
        // Every agent pill that exists at launch has its cat before anything is drawn (a new one gets its coat when it is created).
        CatSettingsStore.shared.ensureAgentCats(for: AppState.shared.tasks.map(\.id))
        NSApp.setActivationPolicy(.accessory)
        setupMenuBarItem()
        setupIsland()
        // The link between machines (sub-project G2): reads the paired machines, and starts listening only if the user has turned "Visible on this network" on (it is off until then).
        LinkService.shared.start()
    }

    // MARK: - Menu bar

    private func setupMenuBarItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        guard let button = statusItem?.button else { return }
        button.image = NSImage(named: "MenuBarIcon") ?? NSImage(systemSymbolName: "circle.fill", accessibilityDescription: "NotchMeow")
        button.image?.size = NSSize(width: 24, height: 18)
        button.image?.accessibilityDescription = "NotchMeow"
        button.image?.isTemplate = true

        let menu = NSMenu()
        menu.addItem(withTitle: "Open NotchMeow", action: #selector(openIsland), keyEquivalent: "")
        // The desktop cat (sub-project H): "Cat on the desktop" while it is home, "Bring the cat home" while it is out (`menuNeedsUpdate`).
        let desktopItem = NSMenuItem(title: "Cat on the desktop", action: #selector(toggleDesktopCat), keyEquivalent: "")
        desktopItem.tag = Self.desktopItemTag
        menu.addItem(desktopItem)
        // The shelf (sub-project G1): opens the island on the files parked in the notch, with their count (`menuNeedsUpdate`).
        let shelfItem = NSMenuItem(title: "Shelf", action: #selector(openShelf), keyEquivalent: "")
        shelfItem.tag = Self.shelfItemTag
        menu.addItem(shelfItem)
        // The Projects screen (sub-project P-mac): opens the island on the projects, with their count (`menuNeedsUpdate`).
        let projectsItem = NSMenuItem(title: "Projects", action: #selector(openProjects), keyEquivalent: "")
        projectsItem.tag = Self.projectsItemTag
        menu.addItem(projectsItem)
        menu.addItem(.separator())
        menu.addItem(withTitle: "Settings…", action: #selector(openSettings), keyEquivalent: ",")
        #if DEBUG && !APPSTORE
        menu.addItem(withTitle: "Cats (Debug)…", action: #selector(openCatPanel), keyEquivalent: "")
        menu.addItem(withTitle: "Shelf (Debug)…", action: #selector(openShelfPanel), keyEquivalent: "")
        menu.addItem(withTitle: "Link (Debug)…", action: #selector(openLinkPanel), keyEquivalent: "")
        #endif
        menu.addItem(.separator())
        menu.addItem(withTitle: "Quit", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

        menu.delegate = self
        statusItem?.menu = menu
    }

    private static let desktopItemTag = 4207

    private static let shelfItemTag = 4208

    private static let projectsItemTag = 4209

    func menuNeedsUpdate(_ menu: NSMenu) {
        menu.item(withTag: Self.desktopItemTag)?.title = desktopCat?.isOut == true ? "Bring the cat home" : "Cat on the desktop"
        let held = ShelfModel.shared.count
        menu.item(withTag: Self.shelfItemTag)?.title = held == 0 ? "Shelf" : "Shelf (\(held))"
        menu.item(withTag: Self.projectsItemTag)?.title = ProjectsLayout.menuTitle(ProjectsModel.shared.appView().projects.count)
    }

    @objc private func openShelf() { islandController?.openShelf() }

    @objc private func openProjects() { islandController?.openProjects() }

    @objc private func toggleDesktopCat() { desktopCat?.toggle() }

    // MARK: - Actions

    @objc private func openIsland() {
        islandController?.expand(to: .overview)
    }

    private var settingsWindow: NSWindow?

    @objc private func openSettingsFromNotification(_ notification: Notification) {
        if let section = notification.object as? String {
            UserDefaults.standard.set(section, forKey: "settingsSection")
        }
        openSettings()
    }

    @objc private func openSettings() {
        // The island floats above every window; fold it away so it can't cover Settings.
        if AppState.shared.mode == .expanded { islandController?.collapse() }

        if let w = settingsWindow, w.isVisible {
            placeBelowIsland(w)
            w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return
        }
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: SettingsLayout.defaultWidth, height: SettingsLayout.defaultHeight),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        win.title = "Settings — NotchMeow"
        let host = NSHostingView(rootView: SettingsView())
        host.sizingOptions = [.minSize]
        win.contentView = host
        win.contentMinSize = NSSize(width: SettingsLayout.minWidth, height: SettingsLayout.minHeight)
        win.isReleasedWhenClosed = false
        placeBelowIsland(win)
        settingsWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    #if DEBUG && !APPSTORE
    private var catPanelWindow: NSWindow?

    /// Debug builds only: the cat panel (coat, size, motion style and state, live). A window like Settings, compiled out of Release and
    /// App Store builds; scripts/check-app-binary.sh proves it.
    @objc private func openCatPanel() {
        if AppState.shared.mode == .expanded { islandController?.collapse() }
        if let w = catPanelWindow, w.isVisible {
            placeBelowIsland(w)
            w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return
        }
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 980, height: 760),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        win.title = "Cats — NotchMeow (Debug)"
        win.identifier = NSUserInterfaceItemIdentifier(CatDevModel.marker)
        let host = NSHostingView(rootView: CatDevView())
        host.sizingOptions = [.minSize]
        win.contentView = host
        win.contentMinSize = NSSize(width: 700, height: 480)
        win.isReleasedWhenClosed = false
        placeBelowIsland(win)
        catPanelWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    private var shelfPanelWindow: NSWindow?
    private var linkPanelWindow: NSWindow?

    /// Debug builds only: the link's fake peer (sub-project G2), a second machine on the loopback address. Compiled out of Release and App Store builds; scripts/check-app-binary.sh proves it.
    @objc private func openLinkPanel() {
        if AppState.shared.mode == .expanded { islandController?.collapse() }
        // The window is kept when closed (isReleasedWhenClosed = false), so the one LinkDevPeer it holds is the only fake peer: reopening shows it, with its Stop.
        if let w = linkPanelWindow { w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return }
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 660, height: 420), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
        win.title = "Link — NotchMeow (Debug)"
        win.identifier = NSUserInterfaceItemIdentifier(LinkDevPeer.marker)
        win.contentView = NSHostingView(rootView: LinkDevView())
        win.isReleasedWhenClosed = false
        placeBelowIsland(win)
        linkPanelWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    /// Debug builds only: the shelf panel (sub-project G1), on a shelf of its own. Compiled out of Release and App Store builds; scripts/check-app-binary.sh proves it.
    @objc private func openShelfPanel() {
        if AppState.shared.mode == .expanded { islandController?.collapse() }
        if let w = shelfPanelWindow, w.isVisible {
            placeBelowIsland(w)
            w.makeKeyAndOrderFront(nil); NSApp.activate(ignoringOtherApps: true); return
        }
        let win = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 720, height: 760),
                           styleMask: [.titled, .closable, .miniaturizable, .resizable],
                           backing: .buffered, defer: false)
        win.title = "Shelf — NotchMeow (Debug)"
        win.identifier = NSUserInterfaceItemIdentifier(ShelfDevModel.marker)
        let host = NSHostingView(rootView: ShelfDevView())
        host.sizingOptions = [.minSize]
        win.contentView = host
        win.contentMinSize = NSSize(width: 700, height: 480)
        win.isReleasedWhenClosed = false
        placeBelowIsland(win)
        shelfPanelWindow = win
        win.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }
    #endif

    /// Centres the window horizontally and keeps its title bar clear of the island panel
    /// (320 pt tall at the top of the notch screen), shrinking it to fit if needed.
    private func placeBelowIsland(_ win: NSWindow) {
        let screen = IslandWindowController.notchScreen() ?? NSScreen.main ?? win.screen
        guard let screen else { win.center(); return }
        let visible = screen.visibleFrame
        let islandBottom = screen.frame.maxY - 320 - 12   // island panel height + margin
        let top = min(visible.maxY, islandBottom)
        var frame = win.frame
        frame.size.height = min(frame.height, max(top - visible.minY - 12, win.minSize.height))
        frame.origin.x = visible.midX - frame.width / 2
        frame.origin.y = max(visible.minY + 12, top - frame.height)
        win.setFrame(frame, display: true)
    }

    // MARK: - Island setup

    private func setupIsland() {
        WardrobeClock.shared.attach(to: .shared, config: CatSettingsStore.shared.config)   // the outfit every big cat wears: Auto's date, resolved, and its one midnight timer
        _ = ProjectsModel.shared   // the Projects model starts with the island: its sinks follow the island from launch, and no view's body first creates it (it publishes its layout)
        islandController = IslandWindowController()
        islandController?.showWindow(nil)
        islandController?.fsm.launch()
        if let island = islandController {
            // The sidekick's notes wait while the user types in the island and stay while the pointer is on it.
            Sidekick.shared.inputs.typing = { [weak island] in island?.isTyping ?? false }
            Sidekick.shared.inputs.pointerOver = { [weak island] in island?.pointerInside ?? false }
            let cat = DesktopCatController(island: island)
            island.desktop = cat
            desktopCat = cat
            cat.start()   // a cat that was out flies back out once the greeting is over
        }
        CatSleepClock.shared.attach(to: AppState.shared)   // an idle cat falls asleep after ten minutes with no agent event
        HookServer.shared.start()
        N8nPoller.shared.start()
        VercelPoller.shared.start()
        ResendPoller.shared.start()
        GithubPoller.shared.start()
        StripePoller.shared.start()
        CalcomPoller.shared.start()
        NotionPoller.shared.start()
        AIService.shared.start()
        NSApp.servicesProvider = CompanionServicesProvider()   // Fix, Rewrite and Explain with NotchMeow in other apps' Services menus
        NSUpdateDynamicServices()
        NotificationCenter.default.addObserver(self, selector: #selector(openSettingsFromNotification(_:)),
                                               name: .openFullSettings, object: nil)
        #if !APPSTORE
        _ = MusicController.shared
        #endif
    }
}
