import Foundation

// The Settings rules that are not views: the pages and tabs and the old `settingsSection` tags, the window's widths, the drafts, the status words and the Sidekick tab. Plain values,
// no window, no Keychain, no UserDefaults. Run through scripts/test-settings-rules.sh.

@main
enum SettingsRulesTests {
    @MainActor static func main() {
        CT.section("route: the pages, their titles and icons, the tabs")
        CT.check("sidebar order", SettingsRoute.Page.allCases.map(\.rawValue), ["general", "agents", "chat", "services", "cat", "devices"])
        CT.check("titles", SettingsRoute.Page.allCases.map { SettingsRoute.title($0) }, ["General", "Agents", "AI and chat", "Services", "Cat", "Devices"])
        CT.check("chat tabs", SettingsRoute.tabs(.chat).map(\.rawValue), ["yourai", "keys", "localmodels", "sidekick", "companion"])
        CT.check("chat tabs with Companion", SettingsRoute.tabs(.chat, companion: true).count, 5)
        CT.check("Companion is the last chat tab", SettingsRoute.tabs(.chat, companion: true).last, .companion)
        CT.check("Companion shown", SettingsRoute.companionTabShown, true)
        CT.check("cat tab titles", SettingsRoute.tabs(.cat).map { SettingsRoute.title($0) }, ["Look", "Outfits", "Personality", "Agents' cats"])
        CT.checkTrue("no tabs on three pages", [.agents, .services, .devices].allSatisfy { SettingsRoute.tabs($0).isEmpty })
        CT.checkTrue("at most five tabs, Companion included", SettingsRoute.Page.allCases.allSatisfy { SettingsRoute.tabs($0).count <= 5 })
        CT.check("tab key", SettingsRoute.tabKey(.cat), "settingsTab.cat")
        let icons: [(SettingsRoute.Page, String, String)] = [
            (.general, "gearshape.fill", "#8E939C"), (.agents, "terminal.fill", "#3B9EFF"), (.chat, "bubble.left.and.bubble.right.fill", "#E07950"),
            (.services, "puzzlepiece.extension.fill", "#7C5CFF"), (.cat, "pawprint.fill", "#D9A066"), (.devices, "laptopcomputer.and.iphone", "#5B8DEF"),
        ]
        for (page, symbol, color) in icons {
            let got = SettingsRoute.icon(page)
            CT.check("icon of \(page.rawValue)", [got.symbol, got.color], [symbol, color])
        }

        CT.section("route: the old tags and the new page/tab form (rule 9)")
        let M = { SettingsRoute.migrate(storedSection: $0) }
        CT.check("activepills", M("activepills"), .init(page: .general))
        CT.check("integrations", M("integrations"), .init(page: .services))
        CT.check("shortcuts", M("shortcuts"), .init(page: .general, tab: .shortcuts))
        CT.check("sidekick", M("sidekick"), .init(page: .chat, tab: .sidekick))
        CT.check("chat kept", M("chat"), .init(page: .chat))
        CT.check("devices kept", M("devices"), .init(page: .devices))
        for bad in [nil, "", "Chat", "bogus", "yourai", "/keys", "nope/keys"] { CT.check("unknown \(bad ?? "nil")", M(bad), .init(page: .general)) }
        CT.check("page and tab", M("chat/keys"), .init(page: .chat, tab: .keys))
        CT.check("page and tab, Your AI", M("chat/yourai"), .init(page: .chat, tab: .yourAI))
        CT.check("a tab of another page", M("chat/look"), .init(page: .chat))
        CT.check("Companion", M("chat/companion"), .init(page: .chat, tab: .companion))
        CT.check("stored tab", SettingsRoute.tab(for: .cat, stored: "outfits"), .outfits)
        CT.check("another page's tab", SettingsRoute.tab(for: .cat, stored: "keys"), .look)
        CT.check("garbage tab", SettingsRoute.tab(for: .chat, stored: "x"), .yourAI)
        CT.check("Companion is restored", SettingsRoute.tab(for: .chat, stored: "companion"), .companion)
        CT.check("no tabs", SettingsRoute.tab(for: .agents, stored: "keys"), nil)
        let oldTags: [(String, SettingsRoute.Place)] = [
            ("general", .init(page: .general)), ("activepills", .init(page: .general)), ("agents", .init(page: .agents)),
            ("chat", .init(page: .chat)), ("integrations", .init(page: .services)), ("services", .init(page: .services)),
            ("shortcuts", .init(page: .general, tab: .shortcuts)), ("cat", .init(page: .cat)),
            ("sidekick", .init(page: .chat, tab: .sidekick)), ("devices", .init(page: .devices)),
        ]
        for (tag, want) in oldTags { CT.check("old tag \(tag)", M(tag), want) }
        CT.checkTrue("every page round-trips through its own name", SettingsRoute.Page.allCases.allSatisfy { M($0.rawValue) == .init(page: $0) })
        CT.checkTrue("every tab of every page round-trips through page/tab", SettingsRoute.Page.allCases.allSatisfy { page in
            SettingsRoute.tabs(page).allSatisfy { M("\(page.rawValue)/\($0.rawValue)") == .init(page: page, tab: $0) }
        })
        CT.check("chat/keys/x lands on the page", M("chat/keys/x"), .init(page: .chat))
        CT.check("agents/keys lands on the page (no tabs there)", M("agents/keys"), .init(page: .agents))
        CT.check("chat/ lands on the page", M("chat/"), .init(page: .chat))
        CT.check("Chat/keys is General (names are case-sensitive)", M("Chat/keys"), .init(page: .general))
        CT.check("general/shortcuts keeps its tab", M("general/shortcuts"), .init(page: .general, tab: .shortcuts))

        CT.section("layout: the spec's widths, and the narrowest column the window allows")
        let W: [Double] = [415, 559, 560, 599, 600, 720, 1100, 3000]
        CT.check("modes", W.map { SettingsLayout.sidebarMode(windowWidth: $0) }, [.icons, .icons, .icons, .icons, .expanded, .expanded, .expanded, .expanded])
        CT.check("columns", W.map { SettingsLayout.columnWidth(windowWidth: $0) }, [327, 471, 472, 511, 360, 480, 640, 640])
        CT.checkTrue("no window from 415 up has a column narrower than the 415 one", stride(from: 415.0, through: 3000, by: 1).allSatisfy { SettingsLayout.columnWidth(windowWidth: $0) >= 327 })
        CT.check("tiny window never negative", SettingsLayout.columnWidth(windowWidth: 40), 0)
        CT.check("min", [SettingsLayout.minWidth, SettingsLayout.minHeight], [415, 420])
        CT.check("tilde", SettingsLayout.displayPath("/Users/sam/.claude/settings.json", home: "/Users/sam"), "~/.claude/settings.json")
        CT.check("home itself", SettingsLayout.displayPath("/Users/sam", home: "/Users/sam"), "~")
        CT.check("a longer name is not home", SettingsLayout.displayPath("/Users/samuel/x", home: "/Users/sam"), "/Users/samuel/x")
        CT.check("empty home", SettingsLayout.displayPath("/a/b", home: ""), "/a/b")
        CT.section("layout: the home folder in a preview, plain and as the hooks' JSON writes it")
        CT.check("plain path in a preview", SettingsLayout.displayText("cmd /Users/name/x", home: "/Users/name"), "cmd ~/x")
        let escaped = SettingsLayout.displayText(#"{"command":"\/Users\/name\/.claude\/notchmeow\/nm-hook"}"#, home: "/Users/name")
        CT.check("escaped path in a preview shows ~", escaped, #"{"command":"~\/.claude\/notchmeow\/nm-hook"}"#)
        CT.checkTrue("the user name is not on screen in an escaped preview", !escaped.contains("name") && !escaped.contains("Users"))
        CT.check("a longer name in an escaped preview is not home", SettingsLayout.displayText(#"\/Users\/samuel\/x"#, home: "/Users/sam"), #"\/Users\/samuel\/x"#)

        CT.section("drafts: an edit is kept, a save writes what was really stored")
        var d = SettingsDraftBook(saved: ["anthropic-api-key": "sk-old", "resend-from": ""])
        CT.check("seeded", d.text("anthropic-api-key"), "sk-old")
        CT.checkTrue("clean", !d.isDirty("anthropic-api-key"))
        d.edit("anthropic-api-key", "sk-new")
        CT.checkTrue("dirty after an edit", d.isDirty("anthropic-api-key"))
        CT.checkTrue("another field is untouched", !d.isDirty("resend-from") && !d.isSaved("resend-from"))
        d.edit("anthropic-api-key", "sk-old")
        CT.checkTrue("typed back to the saved value is clean", !d.isDirty("anthropic-api-key"))
        d.edit("anthropic-api-key", " sk-new ")
        d.markSaved("anthropic-api-key", stored: "sk-new")
        CT.check("saved as written", d.text("anthropic-api-key"), "sk-new")
        CT.checkTrue("clean after save", !d.isDirty("anthropic-api-key"))
        d.markSaved("anthropic-api-key", stored: "")
        CT.checkTrue("removed", !d.isSaved("anthropic-api-key") && d.text("anthropic-api-key") == "")
        CT.check("an unknown field", d.text("nope"), "")
        var typed = SettingsDraftBook(saved: ["key-id": "k"])
        typed.edit("key-id", " k ")
        CT.checkTrue("a typed value with spaces is dirty until it is saved", typed.isDirty("key-id"))
        typed.markSaved("key-id", stored: "k")
        CT.checkTrue("saved as written: clean, and the field shows what was stored", !typed.isDirty("key-id") && typed.text("key-id") == "k")

        CT.section("status: the slots, the cap, the chips and their tones")
        let cat = [(id: "agent_antigravity", name: "Antigravity"), (id: "agent_codex", name: "Codex"), (id: "integration_resend", name: "Resend")]
        CT.check("slots", SettingsStatus.slots(active: ["agent_codex", "agent_antigravity"], catalog: cat), .init(text: "2 of 4 slots used", names: ["Antigravity", "Codex"], full: false))
        CT.check("full", SettingsStatus.slots(active: ["agent_codex", "agent_antigravity", "integration_resend", "ai_gone"], catalog: cat).full, true)
        CT.check("main", SettingsStatus.pillSwitch(isOn: false, isMain: true, activeCount: 4, missing: "Hooks not installed"), .init(showsSwitch: false, chip: "Main", disabled: false))
        CT.check("cap", SettingsStatus.pillSwitch(isOn: false, isMain: false, activeCount: 4, missing: nil), .init(showsSwitch: true, chip: "4 of 4 slots used. Turn another off.", disabled: true))
        CT.check("on at the cap can still turn off", SettingsStatus.pillSwitch(isOn: true, isMain: false, activeCount: 4, missing: nil).disabled, false)
        CT.check("missing never disables", SettingsStatus.pillSwitch(isOn: false, isMain: false, activeCount: 1, missing: "Hooks not installed"), .init(showsSwitch: true, chip: "Hooks not installed", disabled: false))
        CT.check("hook chips", [SettingsStatus.hookChip(installed: true, needsUpdate: true), SettingsStatus.hookChip(installed: true, needsUpdate: false), SettingsStatus.hookChip(installed: false, needsUpdate: false), SettingsStatus.hookChip(installed: nil, needsUpdate: false)], ["Needs update", "Installed", "Not installed", nil])
        CT.check("key chips", [SettingsStatus.keyChip(saved: true), SettingsStatus.keyChip(saved: false), SettingsStatus.serviceChip(saved: true)], ["Ready", "No key yet", "Saved"])
        let toneCases: [(String, SettingsStatus.Tone)] = [
            ("Ready", .ok), ("Installed", .ok), ("Saved", .ok), ("Main", .ok), ("Running, 4 models", .ok),
            ("Needs update", .warn), ("Not saved", .warn), ("Hooks not installed", .warn), ("Key not configured", .warn),
            ("Not connected", .warn), ("Update needed", .warn), (SettingsStatus.capSentence, .warn), ("Off for now", .warn),
            ("Not installed", .neutral), ("Not signed in", .neutral), ("No key yet", .neutral), ("Server off", .neutral),
            ("Coming with the new chat", .neutral), ("Coming soon", .neutral),
            ("Not ready", .error),
        ]
        for (chip, want) in toneCases { CT.check("tone of \(chip)", SettingsStatus.tone(chip), want) }

        CT.section("Sidekick tab: the stuck switch, the four labels, the examples")
        let none: (String) -> Bool = { _ in false }, all: (String) -> Bool = { $0.hasPrefix("stuck.") }, three: (String) -> Bool = { $0 != "stuck.loop" && $0.hasPrefix("stuck.") }
        CT.checkTrue("none muted", SettingsSidekick.stuckSwitch(isMuted: none) == (true, nil))
        CT.checkTrue("all muted", SettingsSidekick.stuckSwitch(isMuted: all) == (false, nil))
        CT.checkTrue("three muted", SettingsSidekick.stuckSwitch(isMuted: three) == (true, "1 of 4"))
        CT.check("stuck names", SettingsSidekick.stuckNames.map(\.label), ["Repeated steps", "Repeated errors", "Waiting for your OK", "Gone quiet"])
        CT.check("permission line", SettingsSidekick.permissionLine, "Always on: it tells you what a permission would do.")
        CT.check("nothing leaves", SettingsSidekick.nothingLeaves, "Nothing leaves this Mac unless you pick a cloud AI as your main AI.")
        CT.check("F3a note", SettingsSidekick.comesWithF3a, "Coming soon")
        CT.check("loop example", SettingsSidekick.example("stuck.loop"), "Claude Code has run the same step 4 times.")
        CT.check("errors example", SettingsSidekick.example("stuck.errors"), "Claude Code hit 3 errors in a row.")
        CT.check("waiting example", SettingsSidekick.example("stuck.waiting"), "Claude Code is still waiting for your OK.")
        CT.check("quiet example", SettingsSidekick.example("stuck.silent"), "Claude Code has been quiet for 5 minutes.")
        CT.checkTrue("recap example", SettingsSidekick.example("recap")?.hasPrefix("While you were away, Claude Code in my-app") == true)
        CT.checkTrue("no path in any example", (["recap"] + SettingsSidekick.stuckKinds).allSatisfy { !(SettingsSidekick.example($0) ?? "/").contains("/") })
        CT.check("no example for the permission line", SettingsSidekick.example("risk"), nil)
        CT.finish()
    }
}
