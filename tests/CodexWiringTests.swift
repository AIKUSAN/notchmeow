import Foundation

// The OpenAI plan's wiring (F3a2-mac), pinned. What the app wires together from the pure parts: the provider the factory
// makes, and the words and button a Codex failure shows. And, as source pins (no test program can run the app's windows,
// the App Store exclusion or the Debug-only override): which Codex files stay wholly out of the App Store build, the one
// Debug-only path override, the provider's own events, what Auto never picks, who runs a Codex turn, where the status is
// asked (a page or the picker opening, or before a turn, never on a timer) and the note's button.

@main
@MainActor
enum CodexWiringTests {
    static func main() {
        selfTests()
        appStoreFree()
        debugOnlyOverride()
        noAuthFile()
        providerPins()
        autoPin()
        turnPins()
        statusPins()
        settingsPins()
        notePin()
        behaviour()
        T.finish()
    }

    static let sources = "NotchBuddy/Sources"
    static let locator = "NotchBuddy/Sources/App/AI/Core/CodexLocator.swift"
    static let providerFile = "NotchBuddy/Sources/App/AI/Core/CodexProvider.swift"
    static let aiService = "NotchBuddy/Sources/App/AI/AIService.swift"
    static let claudeService = "NotchBuddy/Sources/App/ClaudeService.swift"
    static let settingsView = "NotchBuddy/Sources/App/SettingsView.swift"
    static let islandView = "NotchBuddy/Sources/App/IslandViewContent.swift"
    static let settingsSections = "NotchBuddy/Sources/App/SettingsSections.swift"
    static let catalog = "NotchBuddy/Sources/App/AI/Core/AICatalog.swift"
    static let engineFiles = [
        "NotchBuddy/Sources/App/AI/Core/CodexEngine.swift", locator,
        "NotchBuddy/Sources/App/AI/Core/CodexStreamParser.swift",
        "NotchBuddy/Sources/App/AI/Core/CodexText.swift", providerFile,
        "NotchBuddy/Sources/App/ClaudeService+Codex.swift",
    ]
    static let overrideName = "NM_CODEX_PATH_OVERRIDE"

    /// True when the file is wholly App-Store-free: the first code line after the imports (skipping blank lines and `//` comments) is
    /// `#if !APPSTORE`, and the last non-blank line is `#endif`.
    static func isAppStoreFree(_ text: String) -> Bool {
        let lines = text.components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let code = lines.filter { !$0.isEmpty && !$0.hasPrefix("//") && !$0.hasPrefix("import ") }
        return code.first == "#if !APPSTORE" && lines.last(where: { !$0.isEmpty }) == "#endif"
    }

    static func selfTests() {
        T.section("isAppStoreFree tells a wrapped file from an unwrapped one (self-test)")
        T.checkTrue("it is false when the #if opens after the first declaration",
                    !isAppStoreFree("import Foundation\nenum X {}\n#if !APPSTORE\n#endif\n"))
        T.checkTrue("it is false when the last line is not #endif",
                    !isAppStoreFree("#if !APPSTORE\nenum X {}\n"))
        T.checkTrue("it is true for a file wrapped from its first declaration to its end",
                    isAppStoreFree("import Foundation\n#if !APPSTORE\nenum X {}\n#endif\n"))
        T.checkTrue("it is false when code comes before the #if, even if the #if precedes the first declaration",
                    !isAppStoreFree("import Foundation\nlet x = 1\n#if !APPSTORE\nenum X {}\n#endif\n"))
    }

    static func appStoreFree() {
        T.section("Every Codex engine file is wholly out of the App Store build (source pin)")
        for path in engineFiles {
            T.checkTrue("\((path as NSString).lastPathComponent) is App-Store-free", isAppStoreFree(read(path)))
        }
    }

    static func debugOnlyOverride() {
        T.section("The Codex path override is Debug-only (source pin)")
        let users = sourceFiles().filter { $0.text.contains(overrideName) }.map(\.path)
        T.checkTrue("only CodexLocator.swift names \(overrideName)", users == [locator])
        let text = read(locator)
        let found = ranges(of: overrideName, in: text)
        T.checkTrue("and every occurrence lies between a #if DEBUG and its #endif (\(found.count) found)",
                    !found.isEmpty && found.allSatisfy { insideDebug(text, at: $0) })
    }

    static func noAuthFile() {
        T.section("No source names the Codex login file (source pin)")
        let files = sourceFiles()
        T.checkTrue("the Sources folder was read", files.contains { $0.path == locator })
        let named = files.filter { $0.text.contains("auth.json") }.map(\.path)
        for path in named { print("    names auth.json: \(path)") }
        T.checkTrue("no file under NotchBuddy/Sources names auth.json", named.isEmpty)
    }

    static func providerPins() {
        T.section("The Codex provider reports only its own events (source pin)")
        let provider = read(providerFile)
        T.checkTrue("CodexProvider.swift was read", provider.contains("struct CodexProvider"))
        T.checkTrue("it never reports a Claude engine event", !provider.contains(".engine("))
        T.checkTrue("it never reports a step", !provider.contains(".step("))
        T.checkTrue("it writes no app log line", !provider.contains("appendAppLog"))
        let records = ranges(of: "AILog.record(", in: provider).map { provider[$0.upperBound...] }
        let kinds = [".request(", ".reply(", ".failure("]
        T.checkTrue("each AILog.record( is followed by .request(, .reply( or .failure( (\(records.count) found)",
                    !records.isEmpty && records.allSatisfy { tail in kinds.contains { tail.hasPrefix($0) } })
    }

    static func autoPin() {
        T.section("Auto never picks the OpenAI plan (source pin)")
        let keys = member("var cloudKeys", in: read(aiService))
        T.checkTrue("cloudKeys was read", keys.contains("AICatalog.cloudOrder"))
        T.checkTrue("cloudKeys does not name codexPlan", !keys.contains("codexPlan"))
        let order = read(catalog).components(separatedBy: "\n").first { $0.contains("static let cloudOrder") } ?? ""
        T.checkTrue("the cloud order (AICatalog.cloudOrder) was read", order.contains("["))
        T.checkTrue("and it does not name codexPlan, the only way Auto could pick it", !order.contains("codexPlan"))
    }

    static func turnPins() {
        T.section("A chat turn and a quick action set the Codex run (source pin)")
        let service = read(claudeService)
        T.checkTrue("ClaudeService.swift was read", service.contains("final class ClaudeService"))
        T.checkTrue("reply sets a chat turn's run at Chat only",
                    body(of: "reply", in: service).contains("factory.codex = codexSetup(quick: firstSystem != nil)"))
        T.checkTrue("quickReply sets a quick action's run at no tools",
                    body(of: "quickReply", in: service).contains("factory.codex = codexSetup(quick: true)"))
        let setup = read("NotchBuddy/Sources/App/ClaudeService+Codex.swift")
        T.checkTrue("codexSetup carries the last known status into the run (knownState)",
                    setup.contains("knownState: AppState.shared.codexStatus.state"))
        let factory = read("NotchBuddy/Sources/App/AI/Core/ProviderFactory.swift")
        T.checkTrue("the factory hands that status to the provider (knownState: setup.knownState)",
                    factory.contains("knownState: setup.knownState"))
    }

    static func statusPins() {
        T.section("The Codex status is asked only when a page or the picker opens, or before a turn (source pins)")
        let call = "refreshCodexStatus()"
        let callers = sourceFiles().filter { $0.text.contains(call) }.map(\.path).sorted()
        let expected = [aiService, claudeService, settingsView, islandView].sorted()
        T.checkTrue("only the service's definition, the chat's turns, Settings and the picker ask (\(callers.count) files)", callers == expected)
        let service = read(claudeService), settings = read(settingsView), island = read(islandView), ai = read(aiService)
        // The run is set by `factory.codex = codexSetup(...)`; the status must be asked before that line in each of the two turns.
        func asksBeforeRun(_ text: String) -> Bool {
            guard let ask = text.range(of: call), let run = text.range(of: "factory.codex = codexSetup(") else { return false }
            return ask.lowerBound < run.lowerBound
        }
        T.checkTrue("reply and quickReply each ask for the status before they set the Codex run (\(count(call, in: service)) calls)",
                    count(call, in: service) == 2 && asksBeforeRun(body(of: "reply", in: service)) && asksBeforeRun(body(of: "quickReply", in: service)))
        T.checkTrue("Settings asks when its page opens: arrive",
                    count(call, in: settings) == 1 && body(of: "arrive", in: settings).contains(call))
        T.checkTrue("the picker asks when it opens: ModelPickerView",
                    count(call, in: island) == 1 && structBody("ModelPickerView", in: island).contains(call))
        T.checkTrue("the service defines it once", count(call, in: ai) == 1 && ai.contains("func refreshCodexStatus() async"))
        T.checkTrue("no Codex file keeps a Timer", engineFiles.allSatisfy { !read($0).contains("Timer") })
    }

    static func settingsPins() {
        T.section("The Settings pop-up's OpenAI plan rows (source pin)")
        let sections = read(settingsSections)
        T.checkTrue("SettingsSections.swift was read", sections.contains("func isListed("))
        T.checkTrue("a choice that is not listed is labelled \"OpenAI plan (not running)\"",
                    sections.contains("ref.provider == .codexPlan ? \"OpenAI plan (not running)\""))
        // isListed's codexPlan branch: ready under #if !APPSTORE, false otherwise. Compared line by line, with indentation trimmed.
        let lines = body(of: "isListed", in: sections).components(separatedBy: "\n").map { $0.trimmingCharacters(in: .whitespaces) }
        let shape = ["#if !APPSTORE", "return state.codexStatus.isReady", "#else", "return false", "#endif"]
        let start = lines.firstIndex(of: "if ref.provider == .codexPlan {")
        let shaped = start.map { $0 + shape.count < lines.count && Array(lines[($0 + 1)...($0 + shape.count)]) == shape } ?? false
        T.checkTrue("isListed's codexPlan branch is ready under #if !APPSTORE and false in the App Store build", shaped)
    }

    static func notePin() {
        T.section("The note's button opens Codex's page (source pin)")
        let lines = read(islandView).components(separatedBy: "\n")
        let opens = lines.indices.contains { i in
            lines[i].contains("case .installCodex, .updateCodex:")
                && (i + 1 ..< min(i + 4, lines.count)).contains { lines[$0].contains("CodexLocator.installGuide") }
        }
        T.checkTrue("case .installCodex, .updateCodex: opens CodexLocator.installGuide within three lines", opens)
    }

    static func behaviour() {
        T.section("The factory and the words, as the app wires them (behaviour)")
        let target = ChatTarget(provider: .codexPlan, model: "", placement: .cloud)
        T.checkTrue("an OpenAI plan turn with no Codex run set is the unavailable provider",
                    ProviderFactory().make(target) is UnavailableProvider)
        let missing = AIError(kind: .unreachable, code: "nm_codex_missing")
        T.checkTrue("a missing Codex shows the install guide's button",
                    AIMessages.error(missing, target: target).action == .installCodex)
        let old = AIError(kind: .badRequest, code: "nm_codex_old")
        T.checkTrue("an old Codex shows the update guide's button",
                    AIMessages.error(old, target: target).action == .updateCodex)
    }

    // MARK: Helpers (copied in shape from tests/ClaudeCodeWiringTests.swift)

    /// The text of the function `name` (its body, up to the next member at four spaces).
    static func body(of name: String, in text: String) -> String {
        guard let start = text.range(of: "func \(name)(") else { return "" }
        let rest = text[start.upperBound...]
        let end = rest.range(of: "\n    (@MainActor|private func |func |static func |// MARK)", options: .regularExpression)?.lowerBound ?? rest.endIndex
        return String(rest[..<end])
    }

    /// The text from `marker` (a property or function header) to the closing brace at four spaces.
    static func member(_ marker: String, in text: String) -> String {
        guard let start = text.range(of: marker) else { return "" }
        let rest = text[start.lowerBound...]
        let end = rest.range(of: "\n    }\n")?.upperBound ?? rest.endIndex
        return String(rest[..<end])
    }

    /// The text of the top-level struct `name`, up to its closing brace at column 0.
    static func structBody(_ name: String, in text: String) -> String {
        guard let start = text.range(of: "struct \(name):") else { return "" }
        let rest = text[start.lowerBound...]
        let end = rest.range(of: "\n}\n")?.upperBound ?? rest.endIndex
        return String(rest[..<end])
    }

    static func read(_ path: String) -> String {
        (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
    }

    /// Every entry under NotchBuddy/Sources with its text. A folder or a file that is not text reads as "", which no check matches.
    static func sourceFiles() -> [(path: String, text: String)] {
        guard let walker = FileManager.default.enumerator(atPath: sources) else { return [] }
        return walker.compactMap { $0 as? String }.map { (path: sources + "/" + $0, text: read(sources + "/" + $0)) }
    }

    static func ranges(of needle: String, in text: String) -> [Range<String.Index>] {
        var found: [Range<String.Index>] = []
        var index = text.startIndex
        while let range = text.range(of: needle, range: index..<text.endIndex) {
            found.append(range)
            index = range.upperBound
        }
        return found
    }

    static func count(_ needle: String, in text: String) -> Int {
        ranges(of: needle, in: text).count
    }

    /// The occurrence lies in a `#if DEBUG` block: the last directive before it is that `#if DEBUG`, and an `#endif` closes it after.
    static func insideDebug(_ text: String, at range: Range<String.Index>) -> Bool {
        let before = text[..<range.lowerBound]
        guard let open = before.range(of: "#if DEBUG", options: .backwards) else { return false }
        if before[open.upperBound...].contains("#endif") { return false }
        let after = text[range.upperBound...]
        guard let close = after.range(of: "#endif") else { return false }
        return !after[..<close.lowerBound].contains("#if")
    }
}
