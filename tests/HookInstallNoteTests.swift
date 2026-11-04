import Foundation

// Settings → Agents: what the user is told after "Confirm & write". The words are HookInstallNote's (pure); the wiring pins read the app's own source (SettingsAgentsPage.swift, SettingsController.swift, SettingsSections.swift, HookServer.swift) to prove that the
// result of an install lands right under the buttons of its box, and that a confirm never reports a success the writer did not return. No test here reads or writes the real ~/.claude.

@main
@MainActor
enum HookInstallNoteTests {
    static func read(_ path: String) -> String { (try? String(contentsOfFile: path, encoding: .utf8)) ?? "" }

    /// The text between two markers (the first `from`, then the first `to` after it).
    static func between(_ source: String, _ from: String, _ to: String) -> String {
        guard let a = source.range(of: from) else { return "" }
        let rest = source[a.upperBound...]
        return String(rest.prefix(upTo: rest.range(of: to)?.lowerBound ?? rest.endIndex))
    }

    /// A function's body: from its signature to the first line that is just its closing brace (4 spaces in).
    static func body(_ source: String, _ signature: String) -> String { between(source, signature, "\n    }\n") }

    static func main() {
        CT.section("the words")
        let file = "~/.claude/settings.json"
        CT.check("installed, with the backup's name", HookInstallNote.installed("Hooks installed", file: file, backup: "settings.json.bak-20261017-123456"),
                 HookNote(ok: true, text: "✓ Hooks installed in ~/.claude/settings.json. Backup: settings.json.bak-20261017-123456"))
        CT.check("installed, a file that did not exist before", HookInstallNote.installed("Hooks installed", file: file, backup: nil),
                 HookNote(ok: true, text: "✓ Hooks installed in ~/.claude/settings.json. No backup: the file did not exist."))
        CT.check("removed", HookInstallNote.removed("Hooks", file: file), HookNote(ok: true, text: "✓ Hooks removed from ~/.claude/settings.json."))
        CT.check("nothing of ours to remove is said, not reported as a removal", HookInstallNote.absent("NotchMeow hooks", file: file),
                 HookNote(ok: true, text: "No NotchMeow hooks found in ~/.claude/settings.json: nothing changed."))
        let boom = NSError(domain: "NotchMeow", code: 2, userInfo: [NSLocalizedDescriptionKey: "~/.claude/settings.json is not valid JSON — NotchMeow has not touched it."])
        CT.check("a failure carries the error's own words, in red (not ok)", HookInstallNote.failure(boom),
                 HookNote(ok: false, text: "❌ ~/.claude/settings.json is not valid JSON — NotchMeow has not touched it."))

        let view = read("NotchBuddy/Sources/App/SettingsAgentsPage.swift"), controller = read("NotchBuddy/Sources/App/SettingsController.swift")
        let sections = read("NotchBuddy/Sources/App/SettingsSections.swift"), server = read("NotchBuddy/Sources/App/HookServer.swift")
        CT.section("the app's source: where the result goes")
        CT.checkTrue("the sources were read", !view.isEmpty && !controller.isEmpty && !sections.isEmpty && !server.isEmpty)
        let claudeBox = between(view, "private func hookCard(", "@ViewBuilder private func installButton(")
        let planBox = between(view, "private func planCard(", "struct PillSwitchRow")
        CT.checkTrue("the Claude Code hooks box shows the note, under its buttons and before the preview", {
            guard let buttons = claudeBox.range(of: "Button(\"Uninstall\")"), let note = claudeBox.range(of: "if let note = card.note { HookNoteLine(note: note) }"), let preview = claudeBox.range(of: "if let json = card.pendingJSON {") else { return false }
            return buttons.upperBound < note.lowerBound && note.upperBound < preview.lowerBound
        }())
        CT.checkTrue("the Plan usage box shows its note and what the relay has heard, under its buttons", {
            guard let buttons = planBox.range(of: "Button(\"Install relay\")"), let note = planBox.range(of: "if let note = model.note { HookNoteLine(note: note) }"), let heard = planBox.range(of: "if let heard = model.heard"), let preview = planBox.range(of: "if let json = model.pendingJSON {") else { return false }
            return buttons.upperBound < note.lowerBound && note.upperBound < heard.lowerBound && heard.upperBound < preview.lowerBound
                && sections.contains("ClaudePlanGauge.statusNote(relayInstalled: state.planRelayInstalled, usage: state.claudePlanUsage)")
        }())

        let confirm = body(controller, "func confirmInstall() {"), install = body(controller, "func installHooks() {"), uninstall = body(controller, "func uninstallHooks() {")
        CT.checkTrue("confirmInstall reports the backup the writer returned, and a failure in the box too", confirm.contains("let backup = try HookServer.shared.writeClaudeHooks()") && confirm.contains("claudeNote = HookInstallNote.installed(\"Hooks installed\", file: \"~/.claude/settings.json\", backup: backup)") && confirm.contains("claudeNote = HookInstallNote.failure(error)"))
        CT.checkTrue("nothing is claimed before the write: the success note comes after the writer returns", {
            guard let wrote = confirm.range(of: "writeClaudeHooks()"), let said = confirm.range(of: "HookInstallNote.installed(") else { return false }
            return wrote.upperBound < said.lowerBound
        }())
        CT.checkTrue("a preview that cannot be built (a settings.json that does not parse) shows in the box too", install.contains("claudeNote = HookInstallNote.failure(error)"))
        CT.checkTrue("uninstall says whether it removed anything, and fails in the box", uninstall.contains("let removed = try HookServer.shared.uninstallClaudeHooks()") && uninstall.contains("HookInstallNote.removed(") && uninstall.contains("HookInstallNote.absent(") && uninstall.contains("claudeNote = HookInstallNote.failure(error)"))

        let confirmSL = body(controller, "func confirmStatusLine() {"), installSL = body(controller, "func installStatusLine() {")
        CT.checkTrue("the status line's confirm reports the backup too, and a failure", confirmSL.contains("let backup = try HookServer.shared.writeStatusLine()") && confirmSL.contains("planNote = ") && confirmSL.contains("HookInstallNote.installed(\"Status line relay installed\"") && confirmSL.contains("planNote = HookInstallNote.failure(error)"))
        CT.checkTrue("a status line preview that cannot be built shows in the Plan usage box", installSL.contains("planNote = HookInstallNote.failure(error)"))

        CT.section("Plan usage: the switch says what is true")
        let toggle = between(planBox, "SwitchRow(\"Show in the notch\", isOn: Binding(", "))\n")
        CT.checkTrue("the switch is on only when the notch shows the gauge (not while an install waits for its confirm)", toggle.contains("get: { model.showInNotch }") && !toggle.contains("planTogglePending"))
        CT.checkTrue("the page's switch reads the model, and SettingsSections passes the notch's own setting", toggle.contains("get: { model.showInNotch }") && sections.contains("showInNotch: state.showPlanInNotch"))
        CT.checkTrue("Install relay also turns the gauge on once confirmed: a relay with the pill off looks like a gauge that does not work", {
            let relay = body(controller, "func installRelay() {")
            return relay.contains("planTogglePending = true") && relay.contains("installStatusLine()")
        }())

        CT.section("HookServer: the writers do not claim what they did not do")
        CT.checkTrue("both writers return their backup's name to the caller", server.contains("func writeClaudeHooks() throws -> String?") && server.contains("func writeStatusLine() throws -> String?"))

        CT.finish()
    }
}
