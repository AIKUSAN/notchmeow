import Foundation

// The focus-awareness rules (FocusAware, Task 1): the setting, the session's host, the match against the frontmost app, the decision, the wording
// (P-mac's ProjectsRules.waitLabel), the card note, the dot, the --ask twin's Projects wait and the marks' endings and ages. Pure: every time is a parameter.
// Run through scripts/test-focus-aware.sh; nothing here launches NotchMeow.

@main
enum FocusAwareTests {
    typealias F = FocusAware

    @MainActor static func main() {
        CT.section("the setting: absent or not a Bool reads as on")
        CT.check("key", F.defaultsKey, "island.focusAware")
        CT.checkTrue("absent reads on", F.enabled(stored: nil))
        CT.checkTrue("true", F.enabled(stored: true))
        CT.checkTrue("false", !F.enabled(stored: false))
        CT.checkTrue("a string reads on", F.enabled(stored: "no"))

        CT.section("the session's host (a GitHub build unless named)")
        let H = { (r: HookOrigin.Route, a: String, t: String, b: String) in
            F.host(route: r, rawAgent: a, termProgram: t, bundleId: b, githubBuild: true)
        }
        CT.check("Claude app", H(.claude, "claude-desktop", "", ""), .app("com.anthropic.claudefordesktop"))
        CT.check("Claude app wins over a terminal it names", H(.claude, "claude-desktop", "iTerm.app", "com.googlecode.iterm2"), .app("com.anthropic.claudefordesktop"))
        CT.check("terminal by bundle", H(.claude, "", "Apple_Terminal", "com.apple.Terminal"), .app("com.apple.Terminal"))
        CT.check("terminal by TERM_PROGRAM only", H(.claude, "", "iTerm.app", ""), .app("com.googlecode.iterm2"))
        CT.check("Ghostty", H(.claude, "", "ghostty", ""), .app("com.mitchellh.ghostty"))
        CT.check("unknown TERM_PROGRAM, no bundle: no host", H(.claude, "", "someterm", ""), nil)
        CT.check("nothing named: no host", H(.claude, "", "", ""), nil)
        CT.check("VS Code", H(.claude, "", "vscode", "com.microsoft.VSCode"), .vscodeFamily)
        CT.check("Cursor route", H(.cursor, "", "vscode", "com.todesktop.230313mzl4w4u92"), .app("com.todesktop.230313mzl4w4u92"))
        CT.check("Codex", H(.codex, "codex", "", ""), .app("com.openai.codex"))
        CT.check("tagged agent in iTerm", H(.external("gemini"), "gemini", "iTerm.app", "com.googlecode.iterm2"), .app("com.googlecode.iterm2"))
        CT.check("tagged agent naming no terminal", H(.external("gemini"), "gemini", "", ""), nil)
        CT.check("NotchMeow's own bundle is no host (a claude it launched inherits the ID)", H(.claude, "", "iTerm.app", "io.github.aikusan.notchmeow"), nil)
        CT.check("NotchMeow's own bundle, a case variant, is no host", H(.claude, "", "", "IO.GitHub.AikUsan.NotchMeow.Debug"), nil)
        CT.check("App Store: tagged agents not matched",
                 F.host(route: .external("gemini"), rawAgent: "gemini", termProgram: "iTerm.app", bundleId: "com.googlecode.iterm2", githubBuild: false), nil)
        CT.check("App Store: the Claude app still matched",
                 F.host(route: .claude, rawAgent: "claude-desktop", termProgram: "", bundleId: "", githubBuild: false), .app("com.anthropic.claudefordesktop"))

        CT.section("the match against the frontmost app")
        CT.checkTrue("same bundle", F.matches(.app("com.apple.Terminal"), frontmost: "com.apple.Terminal"))
        CT.checkTrue("case-insensitive", F.matches(.app("com.apple.Terminal"), frontmost: "com.apple.terminal"))
        CT.checkTrue("another app", !F.matches(.app("com.apple.Terminal"), frontmost: "com.googlecode.iterm2"))
        CT.checkTrue("VS Code Insiders", F.matches(.vscodeFamily, frontmost: "com.microsoft.VSCodeInsiders"))
        CT.checkTrue("Cursor is not VS Code", !F.matches(.vscodeFamily, frontmost: "com.todesktop.230313mzl4w4u92"))
        CT.checkTrue("NotchMeow itself never",
                     !F.matches(.app("com.apple.Terminal"), frontmost: "io.github.aikusan.notchmeow") && !F.matches(.vscodeFamily, frontmost: "io.github.aikusan.notchmeow"))
        CT.checkTrue("no frontmost", !F.matches(.app("x"), frontmost: nil) && !F.matches(.vscodeFamily, frontmost: ""))

        CT.section("the decision reads the frontmost app only when it may step back")
        var reads = 0
        let fm: () -> String? = { reads += 1; return "com.apple.Terminal" }
        CT.checkTrue("off: no step back", !F.decide(enabled: false, host: .app("com.apple.Terminal"), frontmost: fm))
        CT.check("off: not read", reads, 0)
        CT.checkTrue("no host: no step back", !F.decide(enabled: true, host: nil, frontmost: fm))
        CT.check("no host: not read", reads, 0)
        CT.checkTrue("on and matched", F.decide(enabled: true, host: .app("com.apple.Terminal"), frontmost: fm))
        CT.check("read once", reads, 1)

        CT.section("the host's words and the note")
        CT.check("Claude App words", F.hostWords(route: .claude, rawAgent: "claude-desktop", termProgram: "", bundleId: ""), "Claude App")
        CT.check("VS Code words", F.hostWords(route: .claude, rawAgent: "", termProgram: "vscode", bundleId: ""), "VS Code")
        CT.check("iTerm words", F.hostWords(route: .claude, rawAgent: "", termProgram: "iTerm.app", bundleId: ""), "iTerm")
        CT.check("Cursor words", F.hostWords(route: .cursor, rawAgent: "", termProgram: "", bundleId: ""), "Cursor")
        CT.check("Codex words", F.hostWords(route: .codex, rawAgent: "codex", termProgram: "", bundleId: ""), "Codex")
        CT.check("an unknown bundle's words are the terminal", F.hostWords(route: .claude, rawAgent: "", termProgram: "", bundleId: "com.example.unknown"), "the terminal")
        CT.check("tagged agent named by its terminal", F.hostWords(route: .external("gemini"), rawAgent: "gemini", termProgram: "ghostty", bundleId: ""), "Ghostty")
        CT.check("note with words", F.noteText(host: "VS Code", words: "Runs"), "Waiting in VS Code: Runs")
        CT.check("note without words", F.noteText(host: "iTerm", words: nil), "Waiting in iTerm")
        CT.check("empty words are none", F.noteText(host: "iTerm", words: ""), "Waiting in iTerm")
        CT.check("blank host", F.noteText(host: "  ", words: "Runs"), "Waiting in Claude App: Runs")
        for h in ["VS Code", "", "a/b\\c", "\u{202E}evil", String(repeating: "x", count: 70), "the terminal"] {
            CT.check("one label with Projects: \(h.debugDescription)", F.noteText(host: h, words: nil), ProjectsRules.waitLabel(h))
        }

        CT.section("the step words: the label alone, never the input")
        CT.check("verb Bash", SessionStepText.verb(tool: "Bash"), "Runs")
        CT.check("verb Edit", SessionStepText.verb(tool: "Edit"), "Edits")
        CT.check("verb mcp", SessionStepText.verb(tool: "mcp__github__create_issue"), "github · create_issue")
        CT.check("verb unknown", SessionStepText.verb(tool: "AskUserQuestion"), nil)
        CT.check("line unchanged", SessionStepText.line(tool: "Bash", input: ["command": "npm test"]), "Tests · npm test")

        CT.section("the card note and the dot")
        let m = F.Mark(sessionId: "S1", pillId: "integration_claude", host: "iTerm", kind: .permission, words: "Edits", at: 1000)
        CT.check("card note replaced while marked", F.cardNote("Handled in iTerm.", mark: m), "Waiting in iTerm: Edits")
        CT.check("card note kept without a mark", F.cardNote("Handled in iTerm.", mark: nil), "Handled in iTerm.")
        CT.checkTrue("dot", F.showsDot(markLive: true, badgeShown: false, cardWaiting: false))
        CT.checkTrue("badge wins", !F.showsDot(markLive: true, badgeShown: true, cardWaiting: false))
        CT.checkTrue("card wins", !F.showsDot(markLive: true, badgeShown: false, cardWaiting: true))
        CT.checkTrue("no mark", !F.showsDot(markLive: false, badgeShown: false, cardWaiting: false))

        CT.section("the overview's note takes cat 2's line, unless that line is a waiting card (owner's rule, 2026-10-22)")
        CT.checkTrue("cat 2 idle: the note takes its line", F.showsNoteOverSecondLine(markLive: true, secondWaiting: false))
        CT.checkTrue("cat 2 waiting: its line stays, no note", !F.showsNoteOverSecondLine(markLive: true, secondWaiting: true))
        CT.checkTrue("no mark: no note", !F.showsNoteOverSecondLine(markLive: false, secondWaiting: false))
        CT.checkTrue("no mark, cat 2 waiting: no note", !F.showsNoteOverSecondLine(markLive: false, secondWaiting: true))

        CT.section("the --ask twin keeps the host in Projects")
        var q = m
        q.kind = .question
        CT.check("twin of a question mark: its host", F.twinWaitIn(event: "PreToolUse", tool: "AskUserQuestion", mark: q), "iTerm")
        CT.check("twin of a permission mark: nil", F.twinWaitIn(event: "PreToolUse", tool: "AskUserQuestion", mark: m), nil)
        CT.check("another tool: nil", F.twinWaitIn(event: "PreToolUse", tool: "Bash", mark: q), nil)
        CT.check("another event: nil", F.twinWaitIn(event: "PostToolUse", tool: "AskUserQuestion", mark: q), nil)
        CT.check("no mark: nil", F.twinWaitIn(event: "PreToolUse", tool: "AskUserQuestion", mark: nil), nil)

        CT.section("the marks: ages, replacement, endings and the cap")
        var marks = F.Marks()
        marks.record(m)
        CT.check("live at 599 s", marks.forPill("integration_claude", now: 1599)?.sessionId, "S1")
        CT.check("gone at 600 s", marks.forPill("integration_claude", now: 1600), nil)
        CT.check("a clock behind the mark keeps it", marks.forSession("S1", now: 900)?.sessionId, "S1")
        var ahead = F.Marks()
        ahead.record(.init(sessionId: "S1", pillId: "integration_claude", host: "iTerm", kind: .permission, words: nil, at: 1601))
        CT.check("a mark ahead of the clock by more than the lifetime is gone (the clock went back)", ahead.forSession("S1", now: 1000), nil)
        var pruned = F.Marks()
        pruned.record(m)
        var later = m
        later.sessionId = "S2"
        later.at = 1601
        pruned.record(later)
        CT.check("a new request prunes the marks older than the lifetime", pruned.entries.map(\.sessionId), ["S2"])
        var two = F.Marks()
        two.record(m)
        var newer = m
        newer.sessionId = "S2"
        newer.at = 1100
        two.record(newer)
        CT.check("forPill gives the newest of two marks on one pill", two.forPill("integration_claude", now: 1200)?.sessionId, "S2")
        var n = m
        n.words = "Runs"
        n.at = 1100
        marks.record(n)
        CT.check("a newer request of the session replaces it", marks.entries.count, 1)
        CT.check("newest words", marks.forSession("S1", now: 1200)?.words, "Runs")
        marks.end(sessionId: "S1", event: "PreToolUse", tool: "AskUserQuestion")
        CT.check("the --ask twin ends nothing", marks.entries.count, 1)
        marks.end(sessionId: "S1", event: "Notification", tool: "")
        CT.check("a notification ends nothing", marks.entries.count, 1)
        marks.end(sessionId: "S2", event: "Stop", tool: "")
        CT.check("another session's stop ends nothing", marks.entries.count, 1)
        for ev in F.endingEvents {
            var k = F.Marks()
            k.record(n)
            k.end(sessionId: "S1", event: ev, tool: "Bash")
            CT.check("\(ev) ends it", k.entries.count, 0)
        }
        var many = F.Marks()
        for i in 0..<70 {
            many.record(.init(sessionId: "S\(i)", pillId: "p", host: "h", kind: .question, words: nil, at: Double(i)))
        }
        CT.check("at most 64 kept, the newest", [many.entries.count, Int(many.entries.first!.at)], [64, 6])

        CT.section("the end with no mark to end changes nothing (no write, so no publish)")
        var quiet = F.Marks()
        quiet.record(m)
        let before = quiet
        quiet.end(sessionId: "S2", event: "Stop", tool: "")
        CT.checkTrue("an end with no matching mark leaves the marks equal", quiet == before)
        CT.checkTrue("wouldEnd says no for it", !before.wouldEnd(sessionId: "S2", event: "Stop", tool: ""))
        CT.checkTrue("wouldEnd says yes for the session's own Stop", before.wouldEnd(sessionId: "S1", event: "Stop", tool: ""))
        CT.checkTrue("wouldEnd says no for the --ask twin", !before.wouldEnd(sessionId: "S1", event: "PreToolUse", tool: "AskUserQuestion"))

        CT.section("the lapse: the Sidekick's clock (ms) at which a mark ends")
        CT.check("a mark ten seconds old ends in 590 s", F.lapseMs(markAt: 1000 - 10, now: 1000, nowMs: 0), 590_000)
        CT.check("a mark made now ends in 600 s", F.lapseMs(markAt: 1000, now: 1000, nowMs: 0), 600_000)

        CT.finish()
    }
}
