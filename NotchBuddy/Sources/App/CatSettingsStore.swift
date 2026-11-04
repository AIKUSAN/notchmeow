import Combine
import Foundation

// The app's cat settings: loaded from the store (UserDefaults in the app) when the app starts, handed to the engines through `CatConfig`, and
// saved on every change. Every value goes through `CatSettings.clean` on the way in, so nothing that did not is stored or used. The pure
// part (the clean-up, the keys, load and save) is `CatSettings`; this is the app's single holder of the result.

extension CatConfig {
    /// The settings the engines read: the character, the motion style, each cat's own motion and every personality (engines look them up by
    /// cat ID on every frame, so a change shows on the next one), and the fur-lines switch.
    func apply(_ s: CatSettings) {
        let e = s.engineCfg
        character = s.character
        motion = e.motion
        override = e.override
        pers = e.pers
        furLines = s.furLines
        collar = s.collar
        collarOverride = s.cats.compactMap { $0.value.collar == CatSettings.follow ? nil : ($0.key, $0.value.collar) }.reduce(into: [:]) { $0[$1.0] = $1.1 }
    }
}

@MainActor
final class CatSettingsStore: ObservableObject {
    /// The app's settings, on `UserDefaults.standard` and `CatConfig.shared`. Tests build their own store on a dictionary and a `CatConfig` of their own.
    static let shared = CatSettingsStore()

    @Published private(set) var settings: CatSettings
    /// Settings → Cat → Display: the mode, the pair and the agents' coats. Cleaned by its own `CatDisplaySettings.clean`, beside the Cat settings.
    @Published private(set) var display: CatDisplaySettings
    /// Settings → Cat → Cat on the desktop and the cat's own menu: whether the big cat is out, its size and its spot for each arrangement of screens. Cleaned by its own
    /// `DesktopCatSettings.clean`, beside the Cat settings and the Display settings.
    @Published private(set) var desktop: DesktopCatSettings
    /// Settings → Cat → Wardrobe, the island cat's and the desktop cat's menus and ⌃⌥G: the stored choice (`auto`, `none` or one of the 16 outfits). Cleaned by its own
    /// `WardrobeSettings.clean`, beside the others. The outfit to draw is `config.outfit`, which `WardrobeClock` resolves from this.
    @Published private(set) var wardrobe: WardrobeSettings
    /// Projects' cats: the cat each project folder shows, by folder name (`cat.projectCat.<folder>`). Cleaned by `ProjectsRules.cleanProjectCats`, beside the others.
    @Published private(set) var projectCats: [String: String]
    private let backing: any CatSettingsBacking
    /// Where a new agent's random coat comes from: `Double.random` in the app, a counted seeded source in a test.
    private let rand: () -> Double
    /// The engines' shared settings, which this store feeds; Settings' previews read it too.
    let config: CatConfig

    init(backing: any CatSettingsBacking = UserDefaults.standard, config: CatConfig = .shared, rand: @escaping () -> Double = { Double.random(in: 0..<1) }) {
        self.backing = backing
        self.config = config
        self.rand = rand
        settings = CatSettings.load(from: backing)
        display = CatDisplaySettings.load(from: backing)
        desktop = DesktopCatSettings.load(from: backing)
        wardrobe = WardrobeSettings.load(from: backing)
        projectCats = ProjectCatSettings.load(from: backing)
        config.apply(settings)
    }

    /// Changes the settings. The closure edits a copy; the copy is cleaned (an unknown cat is Shrimpy, a trait is held to 0 to 1, a bad word is
    /// the neutral one), and when it differs from what is held it is published, saved (only the keys that changed) and handed to the engines.
    func update(_ change: (inout CatSettings) -> Void) {
        var next = settings
        change(&next)
        next = CatSettings.clean(next.json)
        guard next != settings else { return }
        next.save(to: backing, replacing: settings)
        settings = next
        config.apply(next)
    }

    // MARK: The Settings rows

    // Each row of Settings is one of the pure edits of `CatSettings` (`withCharacter` and the others), so a row can only change its own field.
    func setCharacter(_ id: String) { update { $0 = $0.withCharacter(id) } }
    func setMotionStyle(_ style: String) { update { $0 = $0.withMotionStyle(style) } }
    /// "follow", "playful" or "classic" for one cat.
    func setMotionOverride(_ word: String, for id: String) { update { $0 = $0.withCatMotion(word, for: id) } }
    /// One of the six presets for one cat (an unknown name is Balanced).
    func setPreset(_ key: String, for id: String) { update { $0 = $0.withPersonality(Personality.named(key), for: id) } }
    /// Moves one slider of one cat: the value is held to 0 to 1 and the preset becomes "custom".
    func setTrait(_ trait: String, _ value: Double, for id: String) {
        update { s in
            guard let p = s.cats[CatSettings.catIdOf(id)]?.personality else { return }
            s = s.withPersonality(Personality.slide(p, trait: trait, value: value), for: id)
        }
    }
    func setFurLines(_ on: Bool) { update { $0 = $0.withFurLines(on) } }
    /// The collar for every cat: "tag", "band", "kerchief" or "off" (anything else is off).
    func setCollar(_ style: String) { update { $0 = $0.withCollar(style) } }
    /// "follow" or a style for one cat ("off" is a style: this cat wears no collar while the global one is on).
    func setCollarOverride(_ word: String, for id: String) { update { $0 = $0.withCatCollar(word, for: id) } }
    /// "Apply to every cat": the motion, collar and personality of cat `id` go to all 16.
    func applyToAll(from id: String) { update { $0 = $0.applyingToAll(from: id) } }

    // MARK: Display

    /// Changes the display settings the same way `update` changes the Cat settings: the closure edits a copy, the copy is cleaned, and when it differs it is
    /// published and saved (only the keys that changed).
    func updateDisplay(_ change: (inout CatDisplaySettings) -> Void) {
        var next = display
        change(&next)
        next = CatDisplaySettings.clean(next.json)
        guard next != display else { return }
        next.save(to: backing, replacing: display)
        display = next
    }
    func setDisplayMode(_ mode: CatDisplayMode) { updateDisplay { $0 = $0.withMode(mode) } }
    /// Cat 1 (`slot` 0) or cat 2 (`slot` 1) of Two cats mode's pair.
    func setPairCat(_ id: String, slot: Int) { updateDisplay { $0 = $0.withPairCat(id, slot: slot) } }
    /// The picker of "Cats for your agents".
    func setAgentCat(_ id: String, for pillId: String) { updateDisplay { $0 = $0.withAgentCat(pillId, id) } }
    /// The dice: a new random coat for one agent, never its current one, always stored.
    func rerollAgentCat(for pillId: String) {
        let rolled = CatAgentCats.rerollAgentCat(pillId, display.agentCats, mainCat: settings.character, rand: rand)
        updateDisplay { $0.agentCats = rolled.agentCats }
    }
    /// "Reset to defaults": the agents in the list start again, Claude Code as Shrimpy, Codex as Momo and every other one with a new random coat.
    func resetAgentCats(for pillIds: [String]) {
        let map = CatAgentCats.assignAgentCats(pillIds, [:], mainCat: settings.character, rand: rand)
        updateDisplay { $0.agentCats = map }
    }
    /// The first sight of an agent pill: it gets its coat now, before anything is drawn, and keeps it. Returns the coat. Safe to call for any pill (an integration
    /// gets the Main cat and nothing is stored) and as often as you like (a stored coat is never changed).
    @discardableResult
    func ensureAgentCat(for pillId: String) -> String {
        let pick = CatAgentCats.agentCatFor(pillId, display.agentCats, mainCat: settings.character, rand: rand)
        if pick.assigned { updateDisplay { $0.agentCats = pick.agentCats } }
        return pick.cat
    }
    /// Once at load: every agent pill that exists gets its coat, and the map is saved once.
    func ensureAgentCats(for pillIds: [String]) {
        let map = CatAgentCats.assignAgentCats(pillIds, display.agentCats, mainCat: settings.character, rand: rand)
        updateDisplay { $0.agentCats = map }
    }

    // MARK: The desktop cat

    /// Changes the desktop settings the same way `update` changes the Cat settings: the closure edits a copy, the copy is cleaned, and when it differs it is published and
    /// saved (only the keys that changed).
    func updateDesktop(_ change: (inout DesktopCatSettings) -> Void) {
        var next = desktop
        change(&next)
        next = DesktopCatSettings.clean(next.json)
        guard next != desktop else { return }
        next.save(to: backing, replacing: desktop)
        desktop = next
    }
    /// Whether the cat is out. The trip stores `DESKTOP_PHASE_INFO[phase].on` (`DesktopPhase.on`), so a cat that quit mid-flight home is home at the next launch.
    func setDesktopOn(_ on: Bool) { updateDesktop { $0 = $0.withOn(on) } }
    func setDesktopSize(_ size: DesktopSize) { updateDesktop { $0 = $0.withSize(size) } }
    /// The cat was released at `spot` (AppKit's coordinates already turned into the contract's: `DesktopCatScreens`): this arrangement keeps the clamped spot.
    func rememberDesktopSpot(_ spot: DesktopSpot, on screens: [DesktopScreen]) { updateDesktop { $0 = $0.remembering(spot, on: screens) } }

    // MARK: The wardrobe

    /// Changes the wardrobe settings the same way `update` changes the Cat settings: the closure edits a copy, the copy is cleaned, and when it differs it is published and
    /// saved (only the key that changed).
    func updateWardrobe(_ change: (inout WardrobeSettings) -> Void) {
        var next = wardrobe
        change(&next)
        next = WardrobeSettings.clean(next.json)
        guard next != wardrobe else { return }
        next.save(to: backing, replacing: wardrobe)
        wardrobe = next
    }
    /// One of the 18 IDs (Settings' tiles, the menus' items): a made-up name is `auto`. The new choice is stored, and the clock that resolves it follows `$wardrobe`.
    func setOutfit(_ id: String) { updateWardrobe { $0 = $0.withOutfit(id) } }
    /// ⌃⌥G: the next ID in the grid's order, `auto` and `none` included, wrapping to `auto`.
    func nextOutfit() { setOutfit(Wardrobe.next(after: wardrobe.outfit)) }

    // MARK: Project cats

    /// Changes the project cats the same way `updateWardrobe` changes the wardrobe: the closure edits a copy, the copy is cleaned, and when it differs it is
    /// published and saved (only the keys that changed, and the ones no longer held are removed). A change whose clean-up would drop a project's stored cat that the change kept
    /// is refused whole (nothing written, nothing published): at the cap of `projectCatsMax` the clean-up keeps the first keys in UTF-16 order, so a new project would silently
    /// evict another project's cat.
    func updateProjectCats(_ change: (inout [String: String]) -> Void) {
        var next = projectCats
        change(&next)
        let wanted = next
        next = ProjectsRules.cleanProjectCats(next)
        guard projectCats.keys.allSatisfy({ wanted[$0] == nil || next[$0] != nil }) else { return }
        guard next != projectCats else { return }
        ProjectCatSettings.save(next, to: backing, replacing: projectCats)
        projectCats = next
    }
    /// A project's cat: a cat ID for a folder name. A made-up cat ID or a name that cannot be a folder key changes nothing and stores nothing.
    func setProjectCat(_ catId: String, for catKey: String) {
        guard ProjectsRules.isCatKey(catKey), ProjectsRules.catIds.contains(catId) else { return }
        updateProjectCats { $0[catKey] = catId }
    }
    /// Drops a project's stored cat: the project shows the cat it gets from its name again.
    func resetProjectCat(for catKey: String) { updateProjectCats { $0[catKey] = nil } }
}
