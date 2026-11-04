import Foundation

// Which pill a hook event belongs to (HookOrigin): the cases HookServer used to decide with three copies of an editor test. Run from the repository root through
// scripts/test-hook-origin.sh.

@main
enum HookOriginTests {
    typealias O = HookOrigin

    static func route(_ agent: String = "", valid: String? = nil, codex: Bool = true, bundle: String = "") -> O.Route {
        O.route(rawAgent: agent, validAgent: valid, codexEnabled: codex, bundleId: bundle)
    }

    @MainActor static func main() {
        CT.section("the pill: a Claude Code event belongs to the Claude Code pill from VS Code and from any terminal")
        CT.check("VS Code", O.pillId(route(bundle: "com.microsoft.VSCode")), "integration_claude")
        CT.check("Terminal", O.pillId(route(bundle: "com.apple.Terminal")), "integration_claude")
        CT.check("iTerm", O.pillId(route(bundle: "com.googlecode.iterm2")), "integration_claude")
        CT.check("Ghostty", O.pillId(route(bundle: "com.mitchellh.ghostty")), "integration_claude")
        CT.check("Warp", O.pillId(route(bundle: "dev.warp.Warp-Stable")), "integration_claude")
        CT.check("a tmux session with no bundle ID at all", O.pillId(route()), "integration_claude")
        CT.check("an event with an empty payload", O.pillId(route("", valid: nil, bundle: "")), "integration_claude")

        CT.section("Cursor, Codex and tagged agents keep their pills")
        CT.check("Cursor, told apart by its bundle ID in any letter case", [O.pillId(route(bundle: "com.todesktop.230313mzl4w4u92")), O.pillId(route(bundle: "COM.TODESKTOP.230313MZL4W4U92"))], ["agent_cursor", "agent_cursor"])
        CT.check("another ToDesktop app is not Cursor", O.pillId(route(bundle: "com.todesktop.123456abc")), "integration_claude")
        CT.check("Codex in the GitHub build", O.pillId(route("codex", valid: "codex", bundle: "com.apple.Terminal")), "agent_codex")
        CT.check("a Codex tag in the App Store build is an ordinary external agent", route("codex", valid: "codex", codex: false), .external("codex"))
        CT.check("a tagged agent", O.pillId(route("gemini", valid: "gemini", bundle: "com.apple.Terminal")), "agent_gemini")
        CT.check("a tag that did not validate is no agent: the event is Claude Code's", route("Bad Agent!", valid: nil), .claude)
        CT.check("a tagged agent from Cursor's window is still that agent", O.pillId(route("gemini", valid: "gemini", bundle: "com.todesktop.230313mzl4w4u92")), "agent_gemini")

        CT.section("the editor test the three call sites repeated")
        CT.checkTrue("TERM_PROGRAM vscode", O.isVSCode(termProgram: "vscode", bundleId: ""))
        CT.checkTrue("a VS Code bundle ID", O.isVSCode(termProgram: "", bundleId: "com.microsoft.VSCode"))
        CT.checkTrue("VS Code Insiders", O.isVSCode(termProgram: "", bundleId: "com.microsoft.VSCodeInsiders"))
        CT.checkTrue("Cursor is not VS Code, even with TERM_PROGRAM vscode", !O.isVSCode(termProgram: "vscode", bundleId: "com.todesktop.230313mzl4w4u92"))
        CT.checkTrue("Terminal is not", !O.isVSCode(termProgram: "Apple_Terminal", bundleId: "com.apple.Terminal"))

        CT.section("where the user is: the words of the notes")
        CT.check("VS Code reads as it always did", O.hostName(pillId: "integration_claude", termProgram: "vscode", bundleId: "com.microsoft.VSCode"), "VS Code")
        CT.check("Cursor", O.hostName(pillId: "agent_cursor", termProgram: "vscode", bundleId: "com.todesktop.230313mzl4w4u92"), "Cursor")
        CT.check("Codex", O.hostName(pillId: "agent_codex", termProgram: "Apple_Terminal", bundleId: "com.apple.Terminal"), "Codex")
        CT.check("Terminal by its bundle ID", O.hostName(pillId: "integration_claude", termProgram: "", bundleId: "com.apple.Terminal"), "Terminal")
        CT.check("Terminal by TERM_PROGRAM alone", O.hostName(pillId: "integration_claude", termProgram: "Apple_Terminal", bundleId: ""), "Terminal")
        CT.check("iTerm", O.hostName(pillId: "integration_claude", termProgram: "iTerm.app", bundleId: "com.googlecode.iterm2"), "iTerm")
        CT.check("Ghostty", O.hostName(pillId: "integration_claude", termProgram: "ghostty", bundleId: "com.mitchellh.ghostty"), "Ghostty")
        CT.check("Warp, whatever its channel", O.hostName(pillId: "integration_claude", termProgram: "WarpTerminal", bundleId: "dev.warp.Warp-Preview"), "Warp")
        CT.check("a terminal we have no name for", O.hostName(pillId: "integration_claude", termProgram: "tmux", bundleId: "org.example.Term"), "the terminal")
        CT.check("nothing known", O.hostName(pillId: "integration_claude", termProgram: "", bundleId: ""), "the terminal")
        CT.check("the two notes", [O.note(host: "VS Code", stillWaiting: false), O.note(host: "Terminal", stillWaiting: true)], ["Handled in VS Code.", "Still waiting in Terminal."])

        CT.section("the app to bring forward")
        CT.check("the app that started the session wins", O.terminalBundleId(termProgram: "Apple_Terminal", bundleId: "com.jetbrains.intellij"), "com.jetbrains.intellij")
        CT.check("TERM_PROGRAM when the relay saw no bundle ID", [O.terminalBundleId(termProgram: "Apple_Terminal", bundleId: ""), O.terminalBundleId(termProgram: "iTerm.app", bundleId: "")], ["com.apple.Terminal", "com.googlecode.iterm2"])
        CT.check("Ghostty and WezTerm", [O.terminalBundleId(termProgram: "ghostty", bundleId: ""), O.terminalBundleId(termProgram: "WezTerm", bundleId: "")], ["com.mitchellh.ghostty", "com.github.wez.wezterm"])
        CT.check("VS Code keeps its own route", O.terminalBundleId(termProgram: "vscode", bundleId: "com.microsoft.VSCode"), nil)
        CT.check("so does Cursor", O.terminalBundleId(termProgram: "vscode", bundleId: "com.todesktop.230313mzl4w4u92"), nil)
        CT.check("tmux with nothing else: no app to name", O.terminalBundleId(termProgram: "tmux", bundleId: ""), nil)
        CT.check("kitty with no bundle ID", O.terminalBundleId(termProgram: "kitty", bundleId: ""), "net.kovidgoyal.kitty")
        CT.check("Alacritty with no bundle ID", O.terminalBundleId(termProgram: "alacritty", bundleId: ""), "org.alacritty")
        CT.check("Warp Preview: the relay's bundle ID comes back unchanged", O.terminalBundleId(termProgram: "WarpTerminal", bundleId: "dev.warp.Warp-Preview"), "dev.warp.Warp-Preview")
        CT.check("Warp with no bundle ID still falls back to Warp Stable", O.terminalBundleId(termProgram: "WarpTerminal", bundleId: ""), "dev.warp.Warp-Stable")

        CT.section("a pending approval holds only its own session's events")
        func verdict(_ name: String, session: Bool, tool: Bool = true, input: Bool = true) -> O.PendingVerdict { O.pendingVerdict(eventName: name, sameSession: session, sameTool: tool, sameInput: input) }
        CT.check("another session's SessionStart passes", verdict("SessionStart", session: false), .passes)
        CT.check("another session's Stop passes", verdict("Stop", session: false), .passes)
        CT.check("another session's PostToolUse with the same tool and input passes", verdict("PostToolUse", session: false), .passes)
        CT.check("same session: Stop resolves", verdict("Stop", session: true), .resolves)
        CT.check("same session: PostToolUse with the same tool and input resolves", verdict("PostToolUse", session: true), .resolves)
        CT.check("same session: PostToolUse of a different tool holds", verdict("PostToolUse", session: true, tool: false), .holds)
        CT.check("same session: PostToolUse of a different input holds", verdict("PostToolUseFailure", session: true, input: false), .holds)
        CT.check("same session: PreToolUse holds", verdict("PreToolUse", session: true), .holds)
        CT.check("same session: SessionStart holds", verdict("SessionStart", session: true), .holds)

        CT.section("the tap brings forward the app of the session the user is looking at")
        let iterm = "com.googlecode.iterm2", ghostty = "com.mitchellh.ghostty"
        // Session A (iTerm) sent its event first; session B (Ghostty) sent the pill its last one, so B is the pill's current session and the pill's last host is Ghostty.
        // "T" is a session with no terminal app known (tmux, an unmapped TERM_PROGRAM): its own answer, not the pill's last host.
        let hosts: [String: O.TapHost] = ["A": .app(iterm), "B": .app(ghostty), "V": .noApp, "T": .noApp]
        func tap(card: String?, current: String?, pill: String?) -> O.TapHost { O.tapHost(cardSession: card, currentSession: current, sessionHosts: hosts, pillHost: pill) }
        CT.check("a card open on session A (iTerm) while the pill's current session is B (Ghostty): A's app", tap(card: "A", current: "B", pill: ghostty), .app(iterm))
        CT.check("no card: the pill's current session B's app", tap(card: nil, current: "B", pill: ghostty), .app(ghostty))
        CT.check("a card on a VS Code session while the pill's last host is iTerm: VS Code, not iTerm", tap(card: "V", current: "A", pill: iterm), .noApp)
        CT.check("a known VS Code session with no card: VS Code, not the pill's last host", tap(card: nil, current: "V", pill: iterm), .noApp)
        CT.check("a session recorded with no app (tmux) while the pill's last host is iTerm: no app, not iTerm", tap(card: "T", current: "A", pill: iterm), .noApp)
        CT.check("a card on a session the map does not know: the pill's last host", tap(card: "X", current: "B", pill: iterm), .app(iterm))
        CT.check("no card and an unknown current session: the pill's last host", tap(card: nil, current: "X", pill: iterm), .app(iterm))
        CT.check("an unknown session with no last host: VS Code's existing route", tap(card: nil, current: "X", pill: nil), .noApp)

        CT.section("a card holds the pill's shown state; the latest state shows when it closes")
        CT.check("a card waits: the pill keeps the state it shows, whatever another session asks", O.shownWhileCard(cardWaiting: true, requested: "working", current: "approval"), "approval")
        CT.check("a card waits: even a finish does not show", O.shownWhileCard(cardWaiting: true, requested: "finished", current: "question"), "question")
        CT.check("no card waits: the requested state shows, as before", O.shownWhileCard(cardWaiting: false, requested: "working", current: "idle"), "working")
        CT.check("the rule is generic: it holds a number as well", O.shownWhileCard(cardWaiting: true, requested: 2, current: 1), 1)
        CT.check("the card closes with nothing held: the fallback shows", O.shownAfterCard(held: nil, fallback: "working"), "working")
        CT.check("the card closes with a state held: the latest state shows", O.shownAfterCard(held: "finished", fallback: "working"), "finished")
        CT.check("the held state wins over the fallback (numbers too)", O.shownAfterCard(held: 3, fallback: 0), 3)
        CT.check("a held entry with a cleared (nil) line shows nil, even when the pill's own line is still set", O.heldLine(entryExists: true, held: nil, current: "old line"), String?.none)
        CT.check("no held entry: the pill's own line stays", O.heldLine(entryExists: false, held: nil, current: "old line"), "old line")
        CT.check("a held entry with a line shows that line, not the pill's own", O.heldLine(entryExists: true, held: "held line", current: "old line"), "held line")
        CT.check("no held entry and no line of its own: nil", O.heldLine(entryExists: false, held: nil, current: nil), String?.none)

        CT.section("the finished to idle timer: a later timer supersedes an earlier one, and a card waiting stops it")
        CT.check("a superseded timer (the card's close scheduled a newer one) does not apply", O.finishedIdleApplies(captured: 1, latest: 2, cardWaiting: false), false)
        CT.check("a card waiting on the pill: the timer does not apply", O.finishedIdleApplies(captured: 2, latest: 2, cardWaiting: true), false)
        CT.check("the current timer, no card waiting: it applies", O.finishedIdleApplies(captured: 2, latest: 2, cardWaiting: false), true)
        CT.check("superseded and a card waiting: it does not apply", O.finishedIdleApplies(captured: 1, latest: 2, cardWaiting: true), false)

        CT.section("a session from the Claude desktop app has its own pill (upstream 344dc12: the tag comes from CLAUDE_CODE_ENTRYPOINT)")
        CT.check("the entrypoint tags the event when no --agent was given", O.agentTag(explicit: "", entrypoint: "claude-desktop"), "claude-desktop")
        CT.check("an explicit --agent wins over the entrypoint", O.agentTag(explicit: "gemini", entrypoint: "claude-desktop"), "gemini")
        CT.check("any other entrypoint (the CLI, VS Code, the SDK) is untagged", [O.agentTag(explicit: "", entrypoint: "cli"), O.agentTag(explicit: "", entrypoint: "vscode"), O.agentTag(explicit: "", entrypoint: "")], ["", "", ""])
        CT.check("no entrypoint at all is untagged", O.agentTag(explicit: "", entrypoint: nil), "")
        CT.check("the tag is exact: a look-alike entrypoint is not Claude Desktop", O.agentTag(explicit: "", entrypoint: "Claude-Desktop"), "")
        CT.section("the tag says where a Claude Code session runs; it does not make a pill of its own")
        CT.check("the tag routes to Claude Code, though it is a valid agent name", route("claude-desktop", valid: "claude-desktop", bundle: "com.anthropic.claudefordesktop"), .claude)
        CT.check("its pill is the Claude Code pill", O.pillId(route("claude-desktop", valid: "claude-desktop")), "integration_claude")
        CT.check("the tag is recognised exactly", [O.isDesktop(rawAgent: "claude-desktop"), O.isDesktop(rawAgent: "Claude-Desktop"), O.isDesktop(rawAgent: "claude-desktop-x"), O.isDesktop(rawAgent: "")], [true, false, false, false])
        CT.check("a look-alike tag is still an ordinary agent", route("claude-desktop-x", valid: "claude-desktop-x"), .external("claude-desktop-x"))
        CT.check("the constants agree (the frozen pill ID is kept, though no event reaches it)", [O.desktopTag, O.desktopPill, O.desktopBundleId], ["claude-desktop", "agent_claude-desktop", "com.anthropic.claudefordesktop"])
        CT.check("the notes name the app the user is in", O.hostName(pillId: "agent_claude-desktop", termProgram: "", bundleId: ""), "Claude App")
        CT.check("the host of such a session is the Claude app, whatever the relay saw", [O.hostBundleId(rawAgent: "claude-desktop", termProgram: "", bundleId: ""), O.hostBundleId(rawAgent: "claude-desktop", termProgram: "Apple_Terminal", bundleId: "com.apple.Terminal")], ["com.anthropic.claudefordesktop", "com.anthropic.claudefordesktop"])
        CT.check("a terminal session keeps its terminal as the host", O.hostBundleId(rawAgent: "", termProgram: "iTerm.app", bundleId: "com.googlecode.iterm2"), "com.googlecode.iterm2")
        CT.check("a session whose host is the Claude app is recognised; any other host is not", [O.isClaudeAppHost(.app("com.anthropic.claudefordesktop")), O.isClaudeAppHost(.app("com.googlecode.iterm2")), O.isClaudeAppHost(.noApp), O.isClaudeAppHost(nil)], [true, false, false, false])
        CT.check("a permission request or a question from the app is answered ask at once, with no card", [O.answersAskAtOnce(route: .claude, rawAgent: "claude-desktop"), O.answersAskAtOnce(route: .external("gemini"), rawAgent: "gemini"), O.answersAskAtOnce(route: .claude, rawAgent: ""), O.answersAskAtOnce(route: .codex, rawAgent: "codex")], [true, true, false, false])

        CT.finish()
    }
}
