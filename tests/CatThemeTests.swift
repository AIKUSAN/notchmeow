import Foundation

// The Mac's character, branding and greeting colours come from Theme.generated.swift (shared/theme.json, and the state colours of cat-core.js), not from
// hex literals in the drawing code. These are source pins: they read the files, so they fail the day a colour is typed in again. That stage 7 changed
// no pixel is proved separately, by drawing the contact sheets before and after and comparing the images byte for byte.

@main
enum CatThemeTests {
    static let dir = "NotchBuddy/Sources/App/"
    static func source(_ file: String) -> String { (try? String(contentsOfFile: dir + file, encoding: .utf8)) ?? "" }

    /// Every "#RRGGBB" string in a text, upper-cased.
    static func hexes(_ text: String) -> Set<String> {
        var found = Set<String>()
        var rest = Substring(text)
        while let q = rest.firstIndex(of: "\"") {
            let after = rest.index(after: q)
            guard let end = rest[after...].firstIndex(of: "\"") else { break }
            let s = rest[after..<end]
            if s.count == 7, s.hasPrefix("#"), s.dropFirst().allSatisfy(\.isHexDigit) { found.insert(s.uppercased()) }
            rest = rest[rest.index(after: end)...]
        }
        return found
    }

    @MainActor static func main() {
        let theme = hexes(source("Theme.generated.swift"))
        CT.checkTrue("the generated theme file is there and holds colours (\(theme.count))", theme.count > 30)

        CT.section("no hex literal that is a theme colour is left in the drawing code")
        let files = ["CatFace.swift", "CatEffects.swift", "CatGreeting.swift", "CatGreetingRenderer.swift", "MotionProfiles.swift", "CatDevPanel.swift", "IslandRootView.swift"]
        var leftovers: [String] = []
        for f in files { for h in hexes(source(f)).intersection(theme).sorted() { leftovers.append("\(f) has \(h)") } }
        CT.checkRows("\(files.count) files: the cat's details, the greeting, the state colours and the glows", leftovers)

        CT.section("the colours as numbers: no RGB triple of the greeting, no 0.059 of the panel's page")
        var triples: [String] = []
        for (f, text) in [("CatGreetingRenderer.swift", "141, 144, 152"), ("CatGreetingRenderer.swift", "127, 180, 234"), ("CatGreetingRenderer.swift", "232, 195, 154"),
                          ("CatGreetingRenderer.swift", "lerp(232"), ("CatDevPanel.swift", "red: 0.059")] where source(f).contains(text) { triples.append("\(f) has \(text)") }
        CT.checkRows("the header text, the tint, the halo's two ends and the panel's page colour", triples)

        CT.section("and each file uses the token it should")
        let uses: [(String, [String])] = [
            ("CatFace.swift", ["Theme.Cat.pupil", "Theme.Cat.heart", "Theme.Cat.star", "Theme.Cat.tongue", "Theme.Cat.mouthInside", "Theme.Cat.teeth"]),
            ("CatEffects.swift", ["Theme.Cat.heart", "Theme.Cat.star", "Theme.Cat.sweat", "Theme.Cat.paper", "Theme.Cat.paperFold", "Theme.Cat.paperLabel"]),
            ("CatGreetingRenderer.swift", ["Theme.Greeting.badge", "Theme.Greeting.tintRGB", "Theme.Greeting.haloGoldRGB", "Theme.Greeting.haloBlueRGB", "Theme.Greeting.headerDimRGB"]),
            ("CatGreeting.swift", ["Theme.Greeting.streaks"]),
            ("MotionProfiles.swift", ["Theme.State.color", "Theme.State.glow"]),
            ("CatDevPanel.swift", ["Theme.Brand.pageRGB"]),
            ("IslandRootView.swift", ["Theme.State.glow"]),   // only with the owner's OK: same values, no change of look
        ]
        var missing: [String] = []
        for (f, names) in uses { for n in names where !source(f).contains(n) { missing.append("\(f) does not use \(n)") } }
        CT.checkRows("seven files, twenty-two uses of a token", missing)

        CT.section("the pill colours the Windows app copies: windows/src/core/pills.ts reads PillCatalog.swift, so a change here is deliberate")
        let catalog = source("PillCatalog.swift")
        func pill(_ id: String) -> String? {
            guard let r = catalog.range(of: "id: \"\(id)\"") else { return nil }
            let rest = catalog[r.upperBound...]
            guard let c = rest.range(of: "color: \"") else { return nil }
            return String(rest[c.upperBound...].prefix(7))
        }
        CT.check("Gemini CLI's pill is #8AB4F8 and Antigravity's is #E879F9 (the collars Windows draws for them)", [pill("agent_gemini"), pill("agent_antigravity")], ["#8AB4F8", "#E879F9"])
        CT.finish()
    }
}
