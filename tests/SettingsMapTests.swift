import Foundation

// The Settings control map: every control has its home, every stored key keeps its name and its store, and the Windows starting file (tests/fixtures/settings/controls.json)
// matches the Swift table field by field. The frozen list is today's keys with the literal that must appear in an app source file, and a source scan checks that every key
// literal in a key position is frozen or on the allowlist, so a key the app reads or writes that the map misses fails here. Run through scripts/test-settings-map.sh.

@main
enum SettingsMapTests {
    /// Today's stored keys, each with its store and the literal that must appear in the app's sources.
    static let frozen: [(key: String, store: String, literal: String)] = [
        ("soundEnabled", "defaults", "\"soundEnabled\""), ("soundVolume", "defaults", "\"soundVolume\""), ("openOnHover", "defaults", "\"openOnHover\""),
        ("island.hoverGlow", "defaults", "\"island.hoverGlow\""), ("island.focusAware", "defaults", "\"island.focusAware\""), ("island.tuckAway", "defaults", "\"island.tuckAway\""), ("autoCloseInterval", "defaults", "\"autoCloseInterval\""),
        ("hotkeyEnabled", "defaults", "\"hotkeyEnabled\""), ("hotkeyFlags", "defaults", "\"hotkeyFlags\""), ("hotkeyCode", "defaults", "\"hotkeyCode\""),
        ("mainPill", "defaults", "\"mainPill\""), ("activeIntegrations", "defaults", "\"activeIntegrations\""), ("showPlanInNotch", "defaults", "\"showPlanInNotch\""),
        ("claudePlanUsage", "defaults", "\"claudePlanUsage\""), ("aiClaudeCodeEnabled", "defaults", "\"aiClaudeCodeEnabled\""), ("aiClaudeCodeModel", "defaults", "\"aiClaudeCodeModel\""),
        ("aiChoices", "defaults", "\"aiChoices\""), ("aiPreferredCloud", "defaults", "\"aiPreferredCloud\""), ("claudeModel", "defaults", "\"claudeModel\""),
        ("googleChatModel", "defaults", "\"googleChatModel\""), ("openAIChatModel", "defaults", "\"openAIChatModel\""), ("aiCustomServers", "defaults", "\"aiCustomServers\""),
        ("aiLastUsedLocal", "defaults", "\"aiLastUsedLocal\""), ("aiLocalModels", "defaults", "\"aiLocalModels\""), ("n8nWorkflowFilter", "defaults", "\"n8nWorkflowFilter\""),
        ("vercelProjectFilter", "defaults", "\"vercelProjectFilter\""),
        ("shortcut.<id>.enabled", "defaults", "\"shortcut.\\(rawValue).enabled\""), ("shortcut.<id>.keyCode", "defaults", "\"shortcut.\\(rawValue).keyCode\""), ("shortcut.<id>.flags", "defaults", "\"shortcut.\\(rawValue).flags\""),
        ("cat.character", "defaults", "\"cat.character\""), ("cat.motionStyle", "defaults", "\"cat.motionStyle\""), ("cat.furLines", "defaults", "\"cat.furLines\""), ("cat.collar", "defaults", "\"cat.collar\""),
        ("cat.motion.<id>", "defaults", "\"cat.motion.\\(id)\""), ("cat.collar.<id>", "defaults", "\"cat.collar.\\(id)\""), ("cat.personality.<id>", "defaults", "\"cat.personality.\\(id)\""),
        ("cat.displayMode", "defaults", "\"cat.displayMode\""), ("cat.pair", "defaults", "\"cat.pair\""), ("cat.agentCat.<pillId>", "defaults", "\"cat.agentCat.\""), ("cat.projectCat.<catKey>", "defaults", "\"cat.projectCat.\""),
        ("cat.desktop.on", "defaults", "\"cat.desktop.on\""), ("cat.desktop.size", "defaults", "\"cat.desktop.size\""), ("cat.desktop.spots", "defaults", "\"cat.desktop.spots\""), ("cat.outfit", "defaults", "\"cat.outfit\""),
        ("sidekick.on", "defaults", "\"sidekick.on\""), ("sidekick.local", "defaults", "\"sidekick.local\""), ("sidekick.dismissals", "defaults", "\"sidekick.dismissals\""),
        ("link.visible", "defaults", "\"link.visible\""), ("link.deviceName", "defaults", "\"link.deviceName\""), ("settingsSection", "defaults", "\"settingsSection\""),
        ("notchmeowHooksInstalled", "defaults", "\"notchmeowHooksInstalled\""),
        ("anthropic-api-key", "keychain", "\"anthropic-api-key\""), ("google-api-key", "keychain", "\"google-api-key\""), ("openai-api-key", "keychain", "\"openai-api-key\""),
        ("resend-api-key", "keychain", "\"resend-api-key\""), ("resend-from", "keychain", "\"resend-from\""), ("n8n-url", "keychain", "\"n8n-url\""), ("n8n-api-key", "keychain", "\"n8n-api-key\""),
        ("vercel-token", "keychain", "\"vercel-token\""), ("github-token", "keychain", "\"github-token\""), ("stripe-api-key", "keychain", "\"stripe-api-key\""),
        ("calcom-api-key", "keychain", "\"calcom-api-key\""), ("notion-api-key", "keychain", "\"notion-api-key\""), ("custom-server-key.<id>", "keychain", "\"custom-server-key.\\(id)\""),
        ("link.peer.<id>", "keychain", "\"link.peer."), ("link.static-key", "keychain", "\"link.static-key\""), ("link.device-id", "keychain", "\"link.device-id\""),
        ("companion.humor", "defaults", "\"companion.humor\""), ("companion.seeSessions", "defaults", "\"companion.seeSessions\""),
        ("companion.cloudNoticeShown", "defaults", "\"companion.cloudNoticeShown\""),
    ]
    /// The keys this restyle adds: the one new key, `settingsTab.<page>`.
    static let new: Set<String> = ["settingsTab.<page>"]

    /// Literals in a key position that are not Settings' stored keys, each with its reason. Each must still be quoted in the sources, so a stale entry fails too.
    static let allowlist: [(literal: String, reason: String)] = [
        ("greetThreshold", "the greeting's threshold, written and read by AppState; no Settings control shows it"),
        ("notchmeow.musicAutomationGranted", "the Apple Music automation grant flag (MusicFollow), written by MusicController when macOS grants or revokes it; no Settings control"),
        ("notchmeow.spotifyAutomationGranted", "the Spotify automation grant flag (MusicFollow), written by MusicController when macOS grants or revokes it; no Settings control"),
        ("chatProvider", "a pre-E1 chat key, read once by the first-launch migration (AppState.migrateChatSettings), never written"),
        ("ollamaServerURL", "a pre-E1 chat key, read once by the first-launch migration, never written"),
        ("lmstudioServerURL", "a pre-E1 chat key, read once by the first-launch migration, never written"),
        ("ollamaChatModel", "a pre-E1 chat key, read once by the first-launch migration, never written"),
        ("lmstudioChatModel", "a pre-E1 chat key, read once by the first-launch migration, never written"),
        ("hooks", "a key of Claude Code's settings.json that NotchMeow edits: part of the file store (hooks.claude), not a preference"),
        ("statusLine", "a key of Claude Code's settings.json that NotchMeow sets or removes: part of the file store, not a preference"),
        ("notchmeow", "a key of the Antigravity hooks file (~/.gemini/config/hooks.json) that NotchMeow removes on uninstall: part of the file store, not a preference"),
        ("api_key", "the wire name of a provider's API key field (a CodingKey in ModelProvider), not a stored key"),
        (#"^(core\\.(askpass|sshcommand|hookspath|pager|fsmonitor|editor|gitproxy|alternaterefscommand)|uploadpack\\.packobjectshook|submodule\\..+\\.update|tar\\..+\\.command|sequence\\.editor|filter\\..+|diff\\.(.+\\.)?(external|textconv|command)|merge\\..+\\.driver|gpg\\.(.+\\.)?program|credential\\..*helper|includeif?\\..+|alias\\..+|pager\\..+|(difftool|mergetool)\\..+\\.cmd|interactive\\.difffilter)\\z"#,
         "a regex of git config names for the Sidekick's sensitive-file check (SidekickExplain), not a stored key"),
        ("custom-server-key", "the custom provider's bare base name: each server's key is custom-server-key.<id> (frozen); this prefix is only read, by AIService.key(_:)"),
    ]

    /// Where a stored key is named: a `forKey:` argument, an @AppStorage name, a `…Key = "…"` or `…Account = "…"` constant, a Keychain call with a literal account,
    /// a `keychainKey:` argument, a `var keychainAccount: String { "…" }` declaration, and the key argument of the JSON helpers. A key built from a variable or a
    /// concatenation is not seen here (the link's peer prefix, the switch that names the three provider keys): the presence check covers those.
    static let keyPatterns: [String] = [
        #"forKey:\s*"([^"]*)""#,
        #"@AppStorage\("([^"]*)"\)"#,
        #"\w*Key\s*=\s*"([^"]*)""#,
        #"\w*Account\s*=\s*"([^"]*)""#,
        #"KeychainStore\.shared\.\w+\(\s*"([^"]*)""#,
        #"keychainKey:\s*"([^"]*)""#,
        #"var keychainAccount: String \{\s*"([^"]*)""#,
        #"(?:save|load)JSON\([^\n]*?,\s*"([^"]*)"\)"#,
    ]

    /// A key with its interpolations written as `<>`, so `shortcut.\(rawValue).enabled` and `shortcut.<id>.enabled` compare equal.
    static func normalise(_ key: String) -> String {
        key.replacingOccurrences(of: #"\\\([^)]*\)"#, with: "<>", options: .regularExpression)
           .replacingOccurrences(of: #"<[^>]*>"#, with: "<>", options: .regularExpression)
    }

    /// The shape of tests/fixtures/settings/controls.json (decoded here only; the Swift table has no Codable).
    struct FileHome: Decodable { var page: String; var tab: String?; var card: String }
    struct FileKey: Decodable { var key: String; var store: String }
    struct FileControl: Decodable { var id: String; var was: String; var homes: [FileHome]; var mac: [FileKey] }
    struct FilePage: Decodable { var page: String; var title: String; var tabs: [String] }
    struct FileMap: Decodable { var version: Int; var note: String; var pages: [FilePage]; var controls: [FileControl] }

    /// One line per control, every field: id | was | homes page/tab/card | mac key (store). The Swift table and the JSON file both go through it.
    static func format(_ id: String, _ was: String, _ homes: [(page: String, tab: String?, card: String)], _ mac: [(key: String, store: String)]) -> String {
        let h = homes.map { "\($0.page)/\($0.tab ?? "–")/\($0.card)" }.joined(separator: "; ")
        let m = mac.map { "\($0.key) (\($0.store))" }.joined(separator: ", ")
        return "\(id) | \(was) | \(h) | \(m)"
    }

    static func row(_ c: SettingsMap.Control) -> String {
        format(c.id, c.was, c.homes.map { (page: $0.page.rawValue, tab: $0.tab?.rawValue, card: $0.card) }, c.mac.map { (key: $0.key, store: $0.store) })
    }

    static func fileRow(_ c: FileControl) -> String {
        format(c.id, c.was, c.homes.map { (page: $0.page, tab: $0.tab, card: $0.card) }, c.mac.map { (key: $0.key, store: $0.store) })
    }

    /// The app's sources, concatenated (the literals must appear in one of them).
    static func appSource() -> String {
        let root = "NotchBuddy/Sources/App"
        var out = ""
        if let walker = FileManager.default.enumerator(atPath: root) {
            for case let rel as String in walker where rel.hasSuffix(".swift") {
                out += (try? String(contentsOfFile: root + "/" + rel, encoding: .utf8)) ?? ""
                out += "\n"
            }
        }
        return out
    }

    /// Every literal found in a key position under the app's sources, as written in the source (interpolations left in).
    static func scanKeyLiterals(_ root: String) -> [String] {
        var out: [String] = []
        guard let walker = FileManager.default.enumerator(atPath: root) else { return out }
        let regexes = keyPatterns.map { try! NSRegularExpression(pattern: $0) }
        for case let rel as String in walker where rel.hasSuffix(".swift") {
            guard let text = try? String(contentsOfFile: root + "/" + rel, encoding: .utf8) else { continue }
            let ns = text as NSString
            for re in regexes {
                for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                    out.append(ns.substring(with: m.range(at: 1)))
                }
            }
        }
        return out
    }

    @MainActor static func main() {
        let controls = SettingsMap.controls
        let fileURL = CT.fixtureURL("controls.json", dir: "settings")
        let file = try! JSONDecoder().decode(FileMap.self, from: Data(contentsOf: fileURL))

        CT.section("controls.json matches SettingsMap.controls, field by field")
        CT.check("version 1", file.version, 1)
        CT.checkTrue("has a note", !file.note.isEmpty)
        CT.check("controls.json ids, in order", file.controls.map(\.id), controls.map(\.id))
        CT.check("controls.json equals SettingsMap.controls", file.controls.map(fileRow), controls.map(row))
        let pages = SettingsRoute.Page.allCases.map { "\($0.rawValue)|\(SettingsRoute.title($0))|\(SettingsRoute.tabs($0).map(\.rawValue).joined(separator: ","))" }
        CT.check("pages in controls.json match SettingsRoute", file.pages.map { "\($0.page)|\($0.title)|\($0.tabs.joined(separator: ","))" }, pages)
        CT.check("control ids are unique", Set(controls.map(\.id)).count, controls.count)

        CT.section("every frozen key sits under exactly one control, with its store")
        for f in frozen {
            let owners = controls.filter { c in c.mac.contains { $0.key == f.key && $0.store == f.store } }.map(\.id)
            CT.check("\(f.key) (\(f.store)): one control", owners.count, 1)
        }

        CT.section("every stored key in the map is frozen, new or a file")
        let known = Set(frozen.map { "\($0.key)|\($0.store)" })
        for c in controls {
            for m in c.mac {
                let ok = m.store == "file" || known.contains("\(m.key)|\(m.store)") || (new.contains(m.key) && m.store == "defaults")
                CT.checkTrue("\(c.id): \(m.key) (\(m.store)) is a known key", ok)
            }
        }

        CT.section("every frozen literal is read somewhere in the app's sources")
        let source = appSource()
        for f in frozen {
            CT.checkTrue("\(f.key): \(f.literal) found in the app", source.contains(f.literal))
        }

        CT.section("every key position in the app names a frozen key or an allowlisted one")
        let frozenNormal = Set(frozen.map { normalise($0.key) })
        let allowed = Set(allowlist.map(\.literal))
        var unlisted: [String] = []
        for lit in Set(scanKeyLiterals("NotchBuddy/Sources/App")).sorted() where !allowed.contains(lit) {
            let n = normalise(lit)
            let frozenPrefix = n.hasSuffix(".") && frozenNormal.contains { $0.hasPrefix(n) }
            if !frozenNormal.contains(n) && !frozenPrefix { unlisted.append(lit) }
        }
        CT.check("no key literal outside the frozen list and the allowlist", unlisted, [])
        for a in allowlist {
            CT.checkTrue("allowlisted \(a.literal): still in the sources, with a reason", source.contains("\"\(a.literal)\"") && !a.reason.isEmpty)
        }

        CT.section("every home: its page, its tab, a nil tab only where the page has none")
        for c in controls {
            var ok = true
            for h in c.homes {
                let tabs = SettingsRoute.tabs(h.page, companion: true)
                if tabs.isEmpty {
                    if h.tab != nil { ok = false }
                } else if c.id == "settings.selection" {
                    if let t = h.tab, !tabs.contains(t) { ok = false }
                } else {
                    guard let t = h.tab, tabs.contains(t) else { ok = false; continue }
                }
            }
            CT.checkTrue("\(c.id): every home is on its page", ok)
        }

        CT.section("every page: at most 5 tabs (Companion included)")
        for page in SettingsRoute.Page.allCases {
            CT.checkTrue("\(page.rawValue): tabs within the cap", SettingsRoute.tabs(page).count <= 5)
        }

        CT.section("pillHome: the page each pill's card lives on")
        let agents = SettingsRoute.Place(page: .agents)
        let keys = SettingsRoute.Place(page: .chat, tab: .keys)
        let local = SettingsRoute.Place(page: .chat, tab: .localModels)
        let services = SettingsRoute.Place(page: .services)
        let general = SettingsRoute.Place(page: .general)
        let expected: [(String, SettingsRoute.Place)] = [
            ("integration_claude", agents), ("agent_cursor", agents), ("agent_antigravity", agents), ("agent_codex", agents), ("agent_gemini", agents),
            ("ai_anthropic", keys), ("ai_google", keys), ("ai_openai", keys), ("ai_ollama", local), ("ai_lmstudio", local),
            ("integration_resend", services), ("integration_n8n", services), ("integration_vercel", services), ("integration_github", services),
            ("integration_stripe", services), ("integration_calcom", services), ("integration_notion", services), ("integration_music", services),
            ("unknown_pill", general),
        ]
        for (id, place) in expected {
            CT.check("pillHome(\(id))", SettingsMap.pillHome(id), place)
        }

        CT.section("serviceFields: the eight service pills, each field a keychain key of its own card")
        let services8 = ["integration_resend", "integration_n8n", "integration_vercel", "integration_github", "integration_stripe", "integration_calcom", "integration_notion", "integration_music"]
        CT.check("the eight service pills", Set(SettingsMap.serviceFields.keys), Set(services8))
        CT.check("music has no fields", SettingsMap.serviceFields["integration_music"], [])
        for (pill, fields) in SettingsMap.serviceFields {
            let card = "service." + pill.dropFirst("integration_".count)
            let owner = controls.first { $0.id == card }
            for field in fields {
                let onCard = owner?.mac.contains { $0.key == field && $0.store == "keychain" } ?? false
                CT.checkTrue("\(pill): \(field) is a keychain key of \(card)", onCard)
            }
        }

        CT.finish()
    }
}
