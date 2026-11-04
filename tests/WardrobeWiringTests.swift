import Foundation

// Source pins for the wardrobe (sub-project I) in the app files no test program can compile (the views, the island window, the app delegate). Each says where a call must be, so a missed
// call site fails here and not on the owner's screen. Run from the repository root. Each later task of the plan adds its section above the last line of `main`.

@main
enum WardrobeWiringTests {
    static func source(_ file: String) -> String { (try? String(contentsOfFile: "NotchBuddy/Sources/App/\(file)", encoding: .utf8)) ?? "" }
    static func count(_ needle: String, in text: String) -> Int { text.components(separatedBy: needle).count - 1 }
    /// The offset of the first `needle`, or -1.
    static func at(_ needle: String, in text: String) -> Int { text.range(of: needle)?.lowerBound.utf16Offset(in: text) ?? -1 }

    @MainActor static func main() {
        CT.section("who wears it: the five big-cat views dress their cat, and nothing else does")
        let bot = source("BotCanvasView.swift"), pair = source("PairCatViews.swift"), upload = source("UploadCanvasView.swift"), desktop = source("DesktopCatDraw.swift"), greeting = source("CatGreetingRenderer.swift")
        CT.checkTrue("the sources were read", bot.contains("struct BotCanvasView") && pair.contains("struct PairCatCanvasView") && upload.contains("drawCat(ctx") && desktop.contains("enum DesktopCatDraw") && greeting.contains("enum CatGreetingRenderer"))
        CT.check("the island's main cat (compact and open) asks for the outfit once", count("CatOutfitDraw.big(engine.cfg.outfit", in: bot), 1)
        CT.checkTrue("and it is in the big cat's view, before the mini cat's view starts", at("CatOutfitDraw.big(engine.cfg.outfit", in: bot) > 0 && at("CatOutfitDraw.big(engine.cfg.outfit", in: bot) < at("struct MiniBotCanvasView", in: bot))
        CT.check("the second cat of Two cats mode asks once", count("CatOutfitDraw.big(engine.cfg.outfit", in: pair), 1)
        CT.check("the file catch's cat asks once", count("CatOutfitDraw.big(catEngine.cfg.outfit", in: upload), 1)
        CT.check("the desktop cat asks once", count("CatOutfitDraw.big(engine.cfg.outfit", in: desktop), 1)
        CT.check("the greeting dresses its cat and the pair's second cat, and no one else", count("CatOutfitDraw.big(e.cfg.outfit", in: greeting), 2)
        CT.checkTrue("the greeting's cat is dressed with the fade, once it has settled", greeting.contains("fade: Greeting.outfitFade(t)"))
        CT.checkTrue("the mini cat's view and the kittens never ask for the outfit", !source("CatKittenDraw.swift").contains("outfit") && !source("KittenViews.swift").contains("outfit")
            && !String(bot[bot.range(of: "struct MiniBotCanvasView")!.lowerBound...]).contains("outfit"))
        let display = source("CatDisplayPreview.swift"), settingsView = source("CatSettingsView.swift")
        CT.check("the Display preview dresses its big cats once", count("CatOutfitDraw.big(config.outfit", in: display), 1)
        CT.checkTrue("and that line is inside the big branch (after `if big {`)", at("if big {", in: display) > 0 && at("CatOutfitDraw.big(config.outfit", in: display) > at("if big {", in: display))
        CT.check("Settings' preview dresses the Main cat once", count("CatOutfitDraw.big(config.outfit", in: settingsView), 1)
        CT.checkTrue("and the dressed flag guards it", at("if dressed {", in: settingsView) > 0 && at("if dressed {", in: settingsView) < at("CatOutfitDraw.big(config.outfit", in: settingsView))

        CT.section("the draw order: behind after the ears, then the collar, the outfit's neck and top, then the whiskers")
        let r = source("CatRenderer.swift")
        CT.checkTrue("the source was read", r.contains("enum CatRenderer"))
        CT.checkTrue("the behind slot follows the ears of the behind pass", at("front: false, flat: flat?.ears[e.sd < 0 ? 0 : 1]) }\n        // The outfit's `behind` slot", in: r) > 0 && at("CatOutfitDraw.paint(cg, dressed, slot: \"behind\")", in: r) > at("front: false, flat:", in: r))
        let collar = at("CatEffects.drawCollar(cg, g", in: r), neck = at("slot: \"neck\"", in: r), top = at("slot: \"top\"", in: r), whiskers = at("CatFace.drawWhiskers(cg, p, s, L)", in: r)
        CT.checkTrue("the neck slot is after the collar, the top slot after the neck, and the whiskers after both", collar > 0 && neck > collar && top > neck && whiskers > top)
        CT.checkTrue("the outfit is fitted to the ears as drawn (after the ear fit) and to the notch's strip", r.contains("earScale: drawnEk") && r.contains("ceiling: o.earCeiling"))
        CT.checkTrue("a bare cat (a small cat, a kitten) never builds the geometry: the role is checked first", source("CatOutfitDraw.swift").contains("guard let paint, Wardrobe.worn(paint.role), paint.fade > 0.001 else { return nil }"))

        CT.section("the choice, and Auto's one midnight timer: attached before the first cat is drawn")
        let delegate = source("AppDelegate.swift"), clock = source("WardrobeClock+App.swift")
        CT.checkTrue("the sources were read", delegate.contains("private func setupIsland()") && clock.contains("extension WardrobeClock"))
        CT.checkTrue("the clock is attached first thing in setupIsland, before the island window (and its greeting) exists", at("WardrobeClock.shared.attach(", in: delegate) > at("private func setupIsland()", in: delegate) && at("WardrobeClock.shared.attach(", in: delegate) < at("islandController = IslandWindowController()", in: delegate))
        CT.checkTrue("the timer is a wall-clock one-shot, and it is the clock's only timer: no repeating timer, no polling", clock.contains("asyncAfter(wallDeadline:") && count("asyncAfter", in: clock) == 1 && !clock.contains("Timer.scheduledTimer") && !clock.contains("DispatchSource"))
        CT.checkTrue("the clock follows the stored choice, and a change of the system clock or time zone is an event", clock.contains("store.$wardrobe") && clock.contains("NSSystemClockDidChange") && clock.contains("NSSystemTimeZoneDidChange"))
        CT.checkTrue("the date override is Debug-only", clock.contains("#if DEBUG && !APPSTORE\n    /// Debug builds only") && clock.contains("static var debugDay"))

        CT.section("Settings → Cat → Wardrobe: after Desktop, and the app hands it the clock's date")
        let view = source("CatSettingsView.swift"), section = source("CatSettingsSection.swift"), group = source("WardrobeSettingsView.swift")
        CT.checkTrue("the sources were read", view.contains("struct CatSettingsView") && section.contains("CatSettingsSection") && group.contains("struct WardrobeSettingsGroup"))
        CT.checkTrue("the Wardrobe group is the Outfits tab, between Look and Personality", view.contains("if shows(.outfits) { WardrobeSettingsGroup(store: store, active: active, day: wardrobeDay) }") && at("if shows(.outfits)", in: view) > at("if shows(.look) {", in: view) && at("if shows(.outfits)", in: view) < at("if shows(.personality)", in: view))
        CT.checkTrue("the Wardrobe group is a SettingsCard titled Wardrobe, not a GroupBox", group.contains("SettingsCard(\"Wardrobe\")") && !group.contains("GroupBox("))
        CT.checkTrue("the app's section passes the wardrobe clock's date (a Debug build can override it)", section.contains("wardrobeDay: { WardrobeClock.appToday() }"))
        CT.checkTrue("a tile stores through the store, the coat picker stores nothing, and the preview is the only live cat", group.contains("store.setOutfit(id)") && group.contains("@State private var previewCoat") && !group.contains("setCharacter") && count("TimelineView", in: group) == 0 && source("WardrobePreviewViews.swift").contains("TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active))"))
        CT.checkTrue("the group carries the binary check's marker", group.contains(".accessibilityIdentifier(CatOutfitDraw.marker)"))

        CT.section("the settings previews read the resolved outfit: the store's own config, which the app's clock writes and the render script resolves")
        let storeSource = source("CatSettingsStore.swift"), renderScript = (try? String(contentsOfFile: "scripts/render-cat-settings.swift", encoding: .utf8)) ?? ""
        CT.checkTrue("the sources were read", view.contains("struct CatSettingsView") && delegate.contains("private func setupIsland()") && renderScript.contains("store.setOutfit(outfit)"))
        CT.checkTrue("the store holds ONE config for its lifetime (a let), and the shared store's is CatConfig.shared", storeSource.contains("    let config: CatConfig") && storeSource.contains("config: CatConfig = .shared") && !storeSource.contains("var config"))
        CT.check("the Main cat and the Personality previews are the two dressed calls (both id-based, with store.config)", count("CatPreviewView(id: id, head: ", in: view), 2)
        CT.check("both dressed previews pass store.config", count("config: store.config, agentColor: Self.sampleAgent, dressed: true)", in: view), 2)
        CT.check("the Display preview gets store.config", count("DisplayPreviewView(display: store.display, main: id, active: active, config: store.config)", in: view), 1)
        CT.check("the Wardrobe group's preview gets store.config", count("WardrobePreviewView(coat: coat, outfit: resolved(shown), head: 76, active: active, config: store.config)", in: source("WardrobeSettingsView.swift")), 1)
        CT.checkTrue("the app attaches the clock to CatSettingsStore.shared.config (the object the store's config is)", count("WardrobeClock.shared.attach(to: .shared, config: CatSettingsStore.shared.config)", in: delegate) == 1)
        CT.checkTrue("and the clock writes the resolved outfit into that config", source("WardrobeClock+App.swift").contains("config?.outfit = self.resolved"))
        CT.checkTrue("the render script resolves the outfit for the store's config after it sets the choice (no clock there)", at("store.setOutfit(outfit)", in: renderScript) > 0
            && at("store.config.outfit = Wardrobe.resolve(store.wardrobe.outfit, Wardrobe.today())", in: renderScript) > at("store.setOutfit(outfit)", in: renderScript))

        CT.section("the island cat's right-click menu and the desktop cat's Wardrobe submenu")
        let island = source("IslandWindowController.swift"), menus = source("WardrobeMenuApp.swift"), dcc = source("DesktopCatController.swift")
        CT.checkTrue("the sources were read", island.contains("final class IslandWindowController") && menus.contains("WardrobeMenuTarget") && dcc.contains("func showMenu"))
        CT.check("one right-click monitor, and it asks the big cats' hit test (both of Two cats') before it shows anything", [count("matching: .rightMouseDown", in: island), count("isBotHit(event.locationInWindow, includeSecond: true)", in: island)], [1, 1])
        CT.checkTrue("the left-button monitors still use the hit test as before (cat 1 only)", count("guard self.isBotHit(event.locationInWindow) else { return }", in: island) == 1)
        CT.checkTrue("the menu keeps the island open while it is up (the pointer is on the menu, outside the island)", island.contains("if !inIsland && wasInIsland && !wardrobeMenuOpen {") && island.contains("wasInIsland = inIsland || wardrobeMenuOpen"))
        CT.checkTrue("the island cat's menu has Wardrobe in it and nothing else for now: one item", count("menu.addItem(", in: menus) == 1 && menus.contains("NSMenuItem(title: \"Wardrobe\"") && menus.contains("static func islandCatMenu()"))
        CT.checkTrue("the desktop cat's menu is given the stored choice and today's Auto, and a pick goes to the store", dcc.contains("outfit: store.wardrobe.outfit, autoToday: Wardrobe.autoOutfit(WardrobeClock.appToday())") && dcc.contains("store.setOutfit(id)"))

        CT.section("⌃⌥G: the last action, off by default, in every build")
        let logic = source("ShortcutLogic.swift")
        CT.checkTrue("the source was read", logic.contains("enum ShortcutAction"))
        CT.checkTrue("it is appended after the shelf's (Carbon's index), off at first, and not an App Store exclusion", logic.contains("case wardrobe ") && at("case wardrobe ", in: logic) > at("case shelf ", in: logic) && logic.contains("case .toggleIsland, .openChat, .jumpToTerminal, .shelf, .wardrobe: return false") && !logic.contains("case .wardrobe: return true") && logic.contains("var isNonAppStore: Bool { self == .jumpToTerminal || self == .attachFrontWindow }"))
        CT.checkTrue("the press moves the stored choice on", island.contains("case .wardrobe:\n            CatSettingsStore.shared.nextOutfit()"))

        CT.section("the island cat's menu never lets a click open the island, nor opens mid-drag or while hidden")
        CT.checkTrue("a left press that a monitor sees while the menu is up is not a click on the island", island.contains("guard self.wasInIsland && !self.wardrobeMenuOpen else { return }"))
        CT.checkTrue("the menu is refused during a drag of the cat and while the island is hidden", island.contains("!inAttachDrag, attachDragStart == nil, state.mode != .hidden, event.window === window, wasInIsland"))
        CT.checkTrue("the desktop cat's menu looks the Wardrobe tag up once, without a force unwrap", dcc.contains("default: if let id = WardrobeMenuTarget.id(forTag: item.tag) { store.setOutfit(id) }") && !dcc.contains("id(forTag: t)!"))

        CT.section("the Debug panel's Wardrobe section: Debug-only, below Desktop, talking to the clock through notifications")
        let dev = source("WardrobeDevPanel.swift"), devPanel = source("CatDevPanel.swift")
        CT.checkTrue("the sources were read", dev.contains("struct WardrobeDevView") && devPanel.contains("DesktopCatDevView()"))
        CT.checkTrue("the file is compiled in Debug builds only", dev.hasPrefix("import SwiftUI\nimport QuartzCore\n\n#if DEBUG && !APPSTORE") && dev.hasSuffix("#endif\n"))
        CT.checkTrue("it is below the Desktop section", at("WardrobeDevView()", in: devPanel) > at("DesktopCatDevView()", in: devPanel))
        CT.checkTrue("the panel posts the date and the midnight, and the app's clock listens for them (Debug only)", dev.contains("NotificationCenter.default.post(name: WardrobeDev.dateNote") && dev.contains("NotificationCenter.default.post(name: WardrobeDev.midnightNote") && source("WardrobeClock+App.swift").contains("publisher(for: WardrobeDev.dateNote)") && source("WardrobeAuto.swift").contains("#if DEBUG && !APPSTORE\n/// The names the Debug cat panel's Wardrobe section"))

        CT.section("headroom: every canvas tighter than the notch's strip gives its outfit its own ceiling (the canvas top), so a tall hat is shortened, not cut off")
        let uploadSource = source("UploadCanvasView.swift"), root = source("IslandRootView.swift")
        CT.checkTrue("the sources were read", bot.contains("particleOverhang") && root.contains("struct GhostBotView") || island.contains("struct GhostBotView"))
        CT.checkTrue("the Main cat's and the Personality previews (head 84 in 130x118, 62 in 96x84): the canvas top is y 0", settingsView.contains("CatOutfitDraw.big(config.outfit, dpr: Double(context.environment.displayScale), ceiling: 0)"))
        CT.checkTrue("cat 2 of the overview and of the compact notch: the canvas top, or the strip's top where that is lower (never above the canvas)", pair.contains("ceiling: max(0, options.earCeiling ?? 0))")
            && at("options.earCeiling = cy - Double(centre.y)", in: pair) > 0 && at("options.earCeiling = cy - Double(centre.y)", in: pair) < at("CatOutfitDraw.big(engine.cfg.outfit", in: pair))
        CT.checkTrue("the file catch's cat is drawn in the island's own canvas: its top is y 0", upload.contains("CatOutfitDraw.big(catEngine.cfg.outfit, dpr: Double(ctx.environment.displayScale), ceiling: 0)"))
        CT.checkTrue("the island's BotCanvasView (the upload bar's cat and the ghost have no overhang) sets it after the strip's ceiling is known, and only when there is no overhang: the main cat's 40 pt canvas and the compact notch are as they were",
                     bot.contains("if particleOverhang == 0 { options.outfit?.ceiling = max(0, options.earCeiling ?? 0) }") && at("options.earCeiling = cy - Double(restingY(state: state))", in: bot) < at("if particleOverhang == 0 { options.outfit?.ceiling", in: bot) && uploadSource.contains("ceiling: 0"))
        CT.check("the greeting's settled cat and the pair's second cat are given the canvas top (y 0 is the island's top, the strip's top the BotCanvasView hands over to)", count("ceiling: 0)", in: greeting), 2)
        CT.checkTrue("the outfit's own ceiling is the paint's, and never reaches the ears' fit", source("CatOutfitDraw.swift").contains("o.headY = headY; o.ceiling = paint.ceiling ?? ceiling") && r.contains("G.earFit(L, s, ceiling: ceiling)") && r.contains("headY: L.head.y, ceiling: o.earCeiling)"))

        let previews = source("WardrobePreviewViews.swift")
        CT.check("the wardrobe's tile and its live preview (the Debug panel's 200x170 canvas at Ø96) both give the outfit the canvas top", count("CatOutfitDraw.big(outfit, dpr: Double(context.environment.displayScale), ceiling: 0)", in: previews), 2)

        let autoSource = source("WardrobeAuto.swift")
        CT.check("today and the seconds to midnight read the system's calendar as it changes (a time zone change event reads the new zone)", [count("calendar: Calendar = .autoupdatingCurrent", in: autoSource), count("calendar: Calendar = .current", in: autoSource)], [2, 0])

        // @@WIRING-SECTIONS: each later task adds its section immediately above this line.
        CT.finish()
    }
}
