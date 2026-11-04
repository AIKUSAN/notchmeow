import Foundation

// Source pins for focus awareness, where no test program can compile the app's files (AppState, HookServer and the views need the whole app). Each says where a call
// must be, so a missed call site or an extra answer fails here and not on the owner's screen. Run from the repository root through scripts/test-focus-aware-wiring.sh.

@main
enum FocusAwareWiringTests {
    static func source(_ file: String) -> String { (try? String(contentsOfFile: "NotchBuddy/Sources/App/\(file)", encoding: .utf8)) ?? "" }
    /// A file by its path from the repository root (the render script and the other tools under scripts/).
    static func file(_ path: String) -> String { (try? String(contentsOfFile: path, encoding: .utf8)) ?? "" }
    static func count(_ needle: String, in text: String) -> Int { text.components(separatedBy: needle).count - 1 }
    /// The offset of the first `needle` at or after `from`, or -1 (UTF-16 offsets, as NSString counts them).
    static func at(_ needle: String, in text: String, from: Int = 0) -> Int {
        let ns = text as NSString
        guard from >= 0, from <= ns.length else { return -1 }
        let r = ns.range(of: needle, options: [], range: NSRange(location: from, length: ns.length - from))
        return r.location == NSNotFound ? -1 : r.location
    }

    @MainActor static func main() {
        let rules = source("FocusAware.swift"), app = source("FocusAwareApp.swift"), hs = source("HookServer.swift")
        let appState = source("AppState.swift"), sidekick = source("Sidekick.swift"), engine = source("SidekickEngine.swift")
        CT.section("the sources were read")
        CT.checkTrue("the files are there", rules.contains("enum FocusAware") && app.contains("enum FocusAwareApp") && hs.contains("final class HookServer") && appState.contains("final class AppState") && sidekick.contains("final class Sidekick") && engine.contains("final class SidekickEngine"))

        CT.section("the pure rules: Foundation only, no timer, no observer, no clock of their own")
        CT.checkTrue("FocusAware.swift imports only Foundation", rules.contains("import Foundation") && !rules.contains("import AppKit") && !rules.contains("import SwiftUI") && !rules.contains("import Combine"))
        CT.checkTrue("and starts nothing and reads nothing of the system", !rules.contains("Timer") && !rules.contains("DispatchQueue") && !rules.contains("asyncAfter") && !rules.contains("Date()") && !rules.contains("NSWorkspace"))

        CT.section("the app side reads the frontmost app once, starts nothing, and never answers allow")
        CT.check("NSWorkspace.shared.frontmostApplication is read exactly once", count("NSWorkspace.shared.frontmostApplication", in: app), 1)
        CT.checkTrue("no observer, timer, dispatch source or Projects feed in FocusAwareApp", !["notificationCenter", "addObserver", "didActivateApplication", "Timer", "asyncAfter", "DispatchSource", "ProjectsModel"].contains { app.contains($0) })
        CT.checkTrue("it never names an allow answer", !app.contains("\"allow\""))
        CT.checkTrue("the mark is recorded before the Sidekick is fed, so its evaluation already sees the mark", at("focusMarks.record(", in: app) >= 0 && at("focusMarks.record(", in: app) < at("Sidekick.shared.feed(payload: payload)", in: app))
        let logLines = app.components(separatedBy: "\n").filter { $0.contains("appendAppLog(") || $0.contains("nbLog(") }
        CT.checkTrue("the log line is there and names neither the app nor its host", !logLines.isEmpty && logLines.allSatisfy { !$0.contains("bundleIdentifier") && !$0.contains("frontmost") && !$0.contains("host") })

        CT.section("HookServer: the two request handlers step back before their Projects feed and their answer, and answer ask at once")
        let pr = at("private func processPermissionRequest(fd: Int32", in: hs), pq = at("private func processQuestionRequest(fd: Int32", in: hs)
        CT.check("stepBack is called in each request handler", count("FocusAwareApp.stepBack(payload: payload, route: route, kind:", in: hs), 2)
        let s1 = at("FocusAwareApp.stepBack(payload: payload, route: route, kind:", in: hs, from: pr)
        let f1 = at("ProjectsModel.shared.feedFromHook(payload: payload, waitIn: waitIn)", in: hs, from: s1)
        let i1 = at("if stepped != nil {", in: hs, from: f1)
        let a1 = at("{\"permissionDecision\":\"ask\"}", in: hs, from: i1)
        let k1 = at("HookOrigin.answersAskAtOnce(route: route, rawAgent: rawAgent)", in: hs, from: a1)
        CT.checkTrue("in the permission handler: step back, then the Projects feed with the host, then the answer, then the ordinary ask at once", pr >= 0 && s1 > pr && f1 > s1 && i1 > f1 && a1 > i1 && k1 > a1 && k1 < pq)
        let s2 = at("FocusAwareApp.stepBack(payload: payload, route: route, kind:", in: hs, from: pq)
        let f2 = at("ProjectsModel.shared.feedFromHook(payload: payload, waitIn: waitIn)", in: hs, from: s2)
        let i2 = at("if stepped != nil {", in: hs, from: f2)
        let a2 = at("{\"permissionDecision\":\"ask\"}", in: hs, from: i2)
        let k2 = at("HookOrigin.answersAskAtOnce(route: route, rawAgent: rawAgent)", in: hs, from: a2)
        CT.checkTrue("in the question handler, the same order", pq >= 0 && s2 > pq && f2 > s2 && i2 > f2 && a2 > i2 && k2 > a2)
        CT.check("the Projects feed never passes a nil host any more", count("waitIn: nil", in: hs), 0)
        let kindPermission = "let stepped = FocusAwareApp.stepBack(payload: payload, route: route, kind: (payload[\"tool_name\"] as? String) == \"AskUserQuestion\" ? .question : .permission)"
        let kindQuestion = "let stepped = FocusAwareApp.stepBack(payload: payload, route: route, kind: .question)"
        CT.checkTrue("the permission handler's kind is the tool test, in full, between its start and the question handler (a swap of the two kinds fails here)", count(kindPermission, in: hs) == 1 && at(kindPermission, in: hs) > pr && at(kindPermission, in: hs) < pq)
        CT.checkTrue("the question handler's kind is .question, in full, after its start", count(kindQuestion, in: hs) == 1 && at(kindQuestion, in: hs) > pq)

        CT.section("HookServer: processEvent ends a mark before the gate, and passes the --ask twin's host to Projects")
        let pe = at("private func processEvent(name: String", in: hs)
        let touch = at("state.touchPill(agentId)   // the pill's last event", in: hs, from: pe)
        let end = at("state.focusMarks.end(sessionId: SidekickLedger.sessionKey(payload), event: name, tool:", in: hs, from: pe)
        let twin = at("FocusAware.twinWaitIn(event: name,", in: hs, from: pe)
        let gate = at("HookOrigin.pendingVerdict(", in: hs, from: pe)
        CT.check("the end is called once", count("state.focusMarks.end(sessionId: SidekickLedger.sessionKey(payload), event: name, tool:", in: hs), 1)
        CT.check("the twin's host is passed once", count("FocusAware.twinWaitIn(event: name,", in: hs), 1)
        CT.checkTrue("the end comes after the pill's last event and before the twin, and the twin before the pending-approval gate", pe >= 0 && touch > pe && end > touch && twin > end && gate > twin)
        let wouldEnd = at("if state.focusMarks.wouldEnd(sessionId: SidekickLedger.sessionKey(payload), event: name, tool: payload[\"tool_name\"] as? String ?? \"\") {", in: hs, from: pe)
        CT.check("wouldEnd is checked once", count("state.focusMarks.wouldEnd(", in: hs), 1)
        CT.checkTrue("the end runs only inside that check (no write, so no publish, when no mark ends)", wouldEnd > touch && end > wouldEnd && end < twin)

        CT.section("HookServer: the card's note is the mark's while the asking session has one")
        let dismiss = at("private func dismissApprovalCard(note: String) {", in: hs)
        CT.check("cardNote is called once", count("FocusAware.cardNote(note, mark:", in: hs), 1)
        CT.checkTrue("and it is inside dismissApprovalCard", dismiss >= 0 && at("FocusAware.cardNote(note, mark:", in: hs, from: dismiss) > dismiss)

        CT.section("HookServer: the answer is still only \"ask\" and \"allow\" is unchanged")
        CT.check("permissionDecision allow appears exactly twice (pinned)", count("\"permissionDecision\":\"allow\"", in: hs), 2)
        CT.check("answersAskAtOnce is still called in the two handlers", count("HookOrigin.answersAskAtOnce(route: route, rawAgent: rawAgent)", in: hs), 2)

        CT.section("AppState: the setting (persisted, read through the rule) and the marks (memory only)")
        CT.checkTrue("the setting is published on by default and saved under the key", appState.contains("@Published var focusAware: Bool = true") && appState.contains("UserDefaults.standard.set(focusAware, forKey: FocusAware.defaultsKey)"))
        CT.checkTrue("the setting is read through the rule at load", appState.contains("focusAware = FocusAware.enabled(stored: ud.object(forKey: FocusAware.defaultsKey))"))
        CT.checkTrue("the marks are published in memory only, no defaults write", appState.contains("@Published var focusMarks = FocusAware.Marks()") && !appState.contains("focusMarks, forKey"))

        CT.section("the Sidekick: a request that stepped back to its app is not a waiting nudge")
        CT.checkTrue("Sidekick.swift gives the engine the held state from stepBackEnd alone (a live mark has an end): no second closure", sidekick.contains("env.stepBackEnd = { sessionId in") && !sidekick.contains("env.stepBackWaiting") && !engine.contains("stepBackWaiting"))
        CT.checkTrue("the engine holds the waiting nudge back per session (the rule's ledger), and the card check is the card alone", engine.contains("env.stepBackEnd(s.sessionId) != nil") && engine.contains("SidekickStuck.step(ruleLedger(), now: now, ctx: stuckContext())") && engine.contains("cardShown: env.ownCardShown(),") && engine.contains("ownCard: env.ownCardShown(),"))
        CT.checkTrue("Sidekick.swift gives the engine the mark's end in the sidekick's clock, so a held nudge is due when the mark lapses", sidekick.contains("env.stepBackEnd = { sessionId in") && sidekick.contains("FocusAware.lapseMs(markAt: mark.at, now: FocusAwareApp.now(), nowMs: Sidekick.nowMs())") && sidekick.contains("FocusAware.lapseMs(markAt: $0.at, now: now, nowMs: Sidekick.nowMs())"))
        CT.checkTrue("the engine wakes at the lapse of any live mark (Env.focusLapseAt reads the app's marks, not the ledger; deadline reads focusLapseAt)", engine.contains("env.focusLapseAt()") && !engine.contains("focusLapse(now:") && !engine.contains("ledger.sessions.compactMap") && sidekick.contains("env.focusLapseAt = {") && sidekick.contains("AppState.shared.focusMarks.live(now: now)") && engine.contains("return [stuck, notes.nextDeadline, giveUp, focusLapseAt].compactMap { $0 }.min()"))
        CT.section("the lapse redraw: the app is told when a stepped-back mark runs out, whether or not the Sidekick is on")
        CT.checkTrue("Sidekick.swift: the app's state publishes at the lapse, so the pill views (which observe AppState) redraw", sidekick.contains("env.focusLapsed = { AppState.shared.objectWillChange.send() }"))
        CT.checkTrue("the engine tells the app once a lapse has passed, at the top of evaluate, and sets the next lapse from the marks (only one still to come)", engine.contains("if let lapse = focusLapseAt, env.now() >= lapse { focusLapseAt = nil; env.focusLapsed() }") && engine.contains("focusLapseAt = env.focusLapseAt().flatMap { $0 > now ? $0 : nil }"))
        CT.checkTrue("the lapse is not gated by the Sidekick's switch", !engine.contains("store.settings.on ? ledger.sessions") && !engine.contains("let lapses = store.settings.on"))
        CT.section("key scope: the mark is keyed the ledger's way, and only the focus calls use that key")
        CT.checkTrue("the mark's own session key is SidekickLedger.sessionKey (FocusAwareApp)", app.contains("let sessionId = SidekickLedger.sessionKey(payload)"))
        CT.checkTrue("the mark's end and its lookup in processEvent use sessionKey", count("state.focusMarks.end(sessionId: SidekickLedger.sessionKey(payload), event: name, tool:", in: hs) == 1 && count("mark: state.focusMarks.forSession(SidekickLedger.sessionKey(payload), now: FocusAwareApp.now()))", in: hs) == 1)
        CT.check("the three handlers keep the session's own key for everything else (the pre-focus expression, unchanged)", count("let sessionId = payload[\"session_id\"] as? String\n", in: hs), 3)
        CT.check("no handler keys its session with sessionKey any more", count("let sessionId = SidekickLedger.sessionKey(payload)", in: hs), 0)
        CT.checkTrue("FocusAwareApp's own non-focus note of the host keeps the old expression", app.contains("state.noteHost(pillId, session: payload[\"session_id\"] as? String ?? payload[\"conversation_id\"] as? String ?? \"unknown\","))
        CT.checkTrue("FocusAware has no anyLive (no caller)", !rules.contains("anyLive"))

        CT.section("Task 3: the dot on the pill, the note on the card, the compact dots and the Settings row")
        let ivc = source("IslandViewContent.swift"), root = source("IslandRootView.swift"), views = source("FocusAwareViews.swift")
        let general = source("SettingsGeneralPage.swift"), sections = source("SettingsSections.swift"), renderSettings = file("scripts/render-settings.swift")
        let pillStart = at("struct AgentPill: View {", in: ivc), musicMark = at("// MARK: - Music Pill", in: ivc)
        let badgeAt = at("PillBadgeView(badge: badge, taskColor: effectiveColor)", in: ivc, from: pillStart)
        let dotAt = at("} else if state.focusDot(task.id) {", in: ivc, from: pillStart)
        CT.checkTrue("AgentPill: the dot is the else of the approval badge (the badge wins by construction)", pillStart >= 0 && badgeAt > pillStart && dotAt > badgeAt && dotAt < musicMark)
        CT.checkTrue("AgentPill: the open island's dot is 8 pt on a ring, at the badge's place", ivc.contains("FocusWaitDot(size: 8, ring: true).offset(x: 3, y: -3)"))
        let overviewMark = at("state.focusMarks.forPill(agent.id, now: FocusAwareApp.now())", in: ivc)
        CT.checkTrue("OverviewView: the note replaces cat 2's line while the mark lives", overviewMark >= 0 && overviewMark < at("} else if let second { secondLine(second) }", in: ivc))
        let cardTicker = at("TickerView(task: task, onDiffTap: onDiffTap)", in: ivc)
        CT.checkTrue("IntegrationCardView: the note follows the ticker in the active-session branch", cardTicker >= 0 && at("appState.focusMarks.forPill(task.id, now: FocusAwareApp.now())", in: ivc, from: cardTicker) > cardTicker)
        CT.check("the note is drawn in exactly the two cards", count("FocusWaitNote(mark:", in: ivc), 2)
        CT.checkTrue("PillBadgeView is unchanged: its three colours and icons", ["#F5A524", "#22C55E", "#F4505E", "exclamationmark", "checkmark", "xmark"].allSatisfy { ivc.contains($0) })
        CT.checkTrue("CompactMiniGrid: each cell's dot", root.contains("state.focusDot(other.task.id)") && root.contains("FocusWaitDot(size: 5).offset(x: 2, y: -2)"))
        let compactDots = at("FocusWaitCompactDots(state: state, islandW: islandWidth, islandH: islandHeight)", in: root)
        // The 120 characters before the dots' call: the group's `if state.mode == .compact {` (the grid's own `if` is further up, before the greeting fade).
        let lead = compactDots >= 120 ? (root as NSString).substring(with: NSRange(location: compactDots - 120, length: 120)) : ""
        CT.checkTrue("IslandContainer: the compact dots only in the compact island, then the greeting and wing fades", compactDots > 0 && lead.contains("if state.mode == .compact {")
            && at(".opacity(greetingTail ? 0 : 1)", in: root, from: compactDots) > compactDots && at(".opacity(state.wingYielded ? 0 : 1)", in: root, from: compactDots) > compactDots)
        CT.checkTrue("FocusAwareViews: the amber is the theme's approval colour and the note is FocusAware's wording", views.contains("Theme.State.color[\"approval\"]") && views.contains("FocusAware.noteText(host: mark.host, words: mark.words)"))
        CT.section("nits: one amber, one lapse expression, one held state")
        CT.check("FocusAwareViews reads the theme's approval colour once, in one file-level amber", count("Theme.State.color[\"approval\"]", in: views), 1)
        CT.checkTrue("and the amber is a file-level private let that the dot and the note use", views.contains("private let amber = Color(hex: Theme.State.color[\"approval\"] ?? \"#F5A524\")") && count("fill(amber)", in: views) == 1 && count("foregroundColor(amber)", in: views) == 1)
        CT.checkTrue("FocusAwareViews: no animation, timer, tap or button", !["TimelineView", "withAnimation", "repeatForever", "Timer", "onTapGesture", "Button"].contains { views.contains($0) })
        CT.checkTrue("Settings: the binding is required, not optional", general.contains("var focusAware: Binding<Bool> ") && !general.contains("var focusAware: Binding<Bool>?") && !general.contains("if let focusAware"))
        let openHover = at("SwitchRow(\"Open on hover\"", in: general), stepRow = at("SwitchRow(\"Step back when I'm already in the app\", help:", in: general), glowRow = at("SwitchRow(\"Hover glow\"", in: general)
        CT.checkTrue("Settings: the row is once, after Open on hover and before Hover glow, bound to the model", openHover >= 0 && stepRow > openHover && glowRow > stepRow && general.contains("isOn: model.focusAware)"))
        CT.check("Settings: the row is drawn once", count("SwitchRow(\"Step back when I'm already in the app\"", in: general), 1)
        CT.checkTrue("SettingsSections passes the state's binding", sections.contains("focusAware: $state.focusAware,") && !sections.contains("focusAware: nil,"))
        CT.checkTrue("render-settings draws the row with a constant", renderSettings.contains("focusAware: .constant(true)"))

        CT.section("one dot rule: the compact grid and the big cat's dots ask focusDot and read nothing else")
        let gridOverlay = "if state.focusDot(other.task.id) { FocusWaitDot(size: 5).offset(x: 2, y: -2) }"
        CT.checkTrue("CompactMiniGrid's cell dot is the focusDot condition", root.contains(gridOverlay))
        let dotsStart = at("struct FocusWaitCompactDots: View {", in: views), dotsEnd = at("extension AppState {", in: views)
        let dotsBody = dotsStart >= 0 && dotsEnd > dotsStart ? (views as NSString).substring(with: NSRange(location: dotsStart, length: dotsEnd - dotsStart)) : ""
        CT.check("FocusWaitCompactDots asks focusDot for the big cat and for cat 2", count("state.focusDot(pill)", in: dotsBody), 2)
        CT.checkTrue("and reads no mark, badge or card of its own", !dotsBody.isEmpty && !dotsBody.contains("focusMarks") && !dotsBody.contains("pillBadge") && !dotsBody.contains("cardWaiting"))

        CT.section("one dot rule: the stand feeds both rows the same state (Gemini badged, Cursor carded, no dot on either)")
        let stand = file("scripts/render-focus-aware.swift")
        let row2 = at("// Row 2:", in: stand), row3 = at("// Row 3:", in: stand)
        let row2Body = row2 >= 0 && row3 > row2 ? (stand as NSString).substring(with: NSRange(location: row2, length: row3 - row2)) : ""
        CT.checkTrue("row 1 sets the one state: Gemini with the approval badge, and the Cursor card", stand.contains("task(\"agent_gemini\", .approval, badge: .approval)") && stand.contains("state.pendingApproval = ApprovalInfo(sessionId: \"S-cursor\""))
        CT.checkTrue("row 2 is drawn from that state: it sets neither the tasks nor the card again", !row2Body.isEmpty && !row2Body.contains("state.tasks =") && !row2Body.contains("pendingApproval = nil"))
        CT.checkTrue("the row 2 caption says Gemini and Cursor get no dot", stand.contains("Compact notch: the big cat's dot (Claude Code); Gemini (badged) and Cursor (waiting) get none"))

        CT.section("the owner's rule on the stand: rows 5 and 6 are captioned with the rule, drawn by OverviewView from one state each")
        CT.checkTrue("row 5 is captioned: cat 2 waiting, its line stays, no note", stand.contains("5. Cat 2 waiting (Codex's card): its line stays, no note is drawn (owner's rule)"))
        CT.checkTrue("row 6 is captioned: cat 2 idle, the note replaces its line", stand.contains("6. Cat 2 idle (Codex working): the note replaces its line (owner's rule)"))
        CT.checkTrue("both rows are the overview in Two cats mode (Gemini focused with its mark)", stand.contains("setDisplayMode(.two)") && stand.contains("state.focusId = \"agent_gemini\""))
        CT.checkTrue("row 5 has cat 2 on a waiting card, row 6 has it working with no card", stand.contains("task(\"agent_codex\", .approval)") && stand.contains("pendingApproval = ApprovalInfo(sessionId: \"S-codex\"") && stand.contains("task(\"agent_codex\", .working)") && stand.contains("state.pendingApproval = nil"))
        CT.checkTrue("the rows are OverviewView itself, not a copy of the app's line or the note", stand.contains("OverviewView(state: state)") && !stand.contains("secondLine"))

        CT.section("the owner's rule (2026-10-22): the note takes cat 2's line, unless that line is a waiting card")
        let secondWaiting = at("let secondWaiting = second?.pill.map { state.cardWaiting(on: $0) } ?? false", in: ivc)
        let ruleCall = at("if FocusAware.showsNoteOverSecondLine(markLive: mark != nil, secondWaiting: secondWaiting), let mark {", in: ivc)
        let ruleLine = at("} else if let second { secondLine(second) }", in: ivc)
        CT.check("OverviewView asks the rule once", count("FocusAware.showsNoteOverSecondLine(", in: ivc), 1)
        CT.checkTrue("the card's wait is read before the rule, and the rule decides the note before cat 2's line", secondWaiting >= 0 && ruleCall > secondWaiting && ruleLine > ruleCall)
        CT.checkTrue("the mark is read once, for the rule (the same place as before)", overviewMark >= 0 && overviewMark < ruleCall)
        CT.check("the note line is drawn once in OverviewView (the rule's branch)", count("FocusWaitNote(mark: mark, leading: textLeading)", in: ivc), 1)

        CT.finish()
    }
}
