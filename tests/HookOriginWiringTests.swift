import Foundation

// Source pins for the hook routing, where no test program can compile HookServer (it needs the whole app). Each says where HookOrigin must be called and that the old
// editor-only guards are gone, so a missed call site fails here and not on the owner's screen. Run from the repository root through scripts/test-hook-origin-wiring.sh.

@main
enum HookOriginWiringTests {
    static func source(_ file: String) -> String { (try? String(contentsOfFile: "NotchBuddy/Sources/App/\(file)", encoding: .utf8)) ?? "" }
    static func count(_ needle: String, in text: String) -> Int { text.components(separatedBy: needle).count - 1 }
    /// The offset of the first `needle`, or -1.
    static func at(_ needle: String, in text: String) -> Int { text.range(of: needle)?.lowerBound.utf16Offset(in: text) ?? -1 }
    /// The offset of the first `needle` at or after `from`, or -1.
    static func at(_ needle: String, in text: String, from: Int) -> Int { from < 0 ? -1 : text.range(of: needle, range: String.Index(utf16Offset: from, in: text)..<text.endIndex)?.lowerBound.utf16Offset(in: text) ?? -1 }

    @MainActor static func main() {
        let hooks = source("HookServer.swift"), rules = source("HookOrigin.swift"), types = source("IslandTypes.swift"), app = source("AppState.swift"), view = source("IslandViewContent.swift"), target = source("AgentTarget.swift")
        CT.section("the sources were read")
        CT.checkTrue("the five files are there", hooks.contains("final class HookServer") && rules.contains("enum HookOrigin") && types.contains("struct ApprovalInfo") && app.contains("final class AppState") && view.contains("private func openAgentTarget"))

        CT.section("the rules are pure")
        CT.checkTrue("HookOrigin.swift imports only Foundation and starts nothing", rules.contains("import Foundation") && !rules.contains("import AppKit") && !rules.contains("import SwiftUI") && !rules.contains("Timer") && !rules.contains("DispatchQueue") && !rules.contains("NSWorkspace"))

        CT.section("the three entry points route through HookOrigin, and the editor-only guards are gone")
        CT.check("an event, a permission request and a question each ask the rule", count("HookOrigin.route(", in: hooks), 3)
        CT.check("no copy of the editor test is left", count("isVSCodeEditor", in: hooks) + count("isCursorEditor", in: hooks) + count("isCodexEvent", in: hooks), 0)
        CT.check("nothing is ignored for its terminal any more", count("nbLog(\"Ignored", in: hooks), 0)
        CT.check("no request is answered \"ask\" for lack of an editor", count("guard isCodexRequest ||", in: hooks), 0)
        CT.check("a tagged agent's and a Claude app session's permission request and question are answered ask at once; an event still reads its route once for the pill", [count("HookOrigin.answersAskAtOnce(route: route, rawAgent: rawAgent)", in: hooks), count("if case .external = route {", in: hooks)], [2, 1])
        CT.checkTrue("a chat's own run is filtered before the routing, as it was", at("ClaudeHookRouting.route(payload: payload, live: ClaudeService.shared.liveClaudeSessions) { return }", in: hooks) > 0 && at("ClaudeHookRouting.route(payload: payload, live: ClaudeService.shared.liveClaudeSessions) { return }", in: hooks) < at("HookOrigin.route(", in: hooks))
        let permissionChat = at("if case .chat(let chatSession) = ClaudeHookRouting.route(", in: hooks)
        CT.checkTrue("a chat's permission request is filtered before the routing too", permissionChat > 0 && permissionChat < at("HookOrigin.route(", in: hooks, from: permissionChat))
        let questionChat = at("if case .chat = ClaudeHookRouting.route(payload: payload, live: ClaudeService.shared.liveClaudeSessions) {\n            Task.detached", in: hooks)
        CT.checkTrue("a chat's question is filtered before the routing too", questionChat > 0 && questionChat < at("HookOrigin.route(", in: hooks, from: questionChat))
        CT.checkTrue("Codex is the GitHub build's only", count("let codexEnabled = true", in: hooks) == 3 && count("let codexEnabled = false", in: hooks) == 3 && count("#if !APPSTORE\n        let codexEnabled = true", in: hooks) == 3)

        CT.section("two sessions on the one pill: an approval is still closed only by its own session's events")
        CT.check("the verdict compares the session, once", count("sessionId == pending.sessionId", in: hooks), 1)

        CT.section("a pending approval holds only its own session's events: another session's reach the normal switch and leave the card alone")
        let gateStart = at("if let pending = state.pendingApproval, agentId == pending.pillId {", in: hooks)
        let gateEnd = at("switch name {", in: hooks, from: gateStart)
        let gate = gateStart > 0 && gateEnd > gateStart ? String(hooks.utf16[hooks.utf16.index(hooks.utf16.startIndex, offsetBy: gateStart)..<hooks.utf16.index(hooks.utf16.startIndex, offsetBy: gateEnd)])! : ""
        let passesAt = at("case .passes", in: gate), holdsAt = at("case .holds", in: gate)
        CT.checkTrue("processEvent asks the rule, once", count("HookOrigin.pendingVerdict(", in: hooks) == 1 && !gate.isEmpty && count("HookOrigin.pendingVerdict(", in: gate) == 1)
        CT.check("the old swallow-everything line is gone", count("if !resolved { return }", in: hooks), 0)
        CT.check("only the holds case returns", [count("return", in: gate), count("case .holds: return", in: gate)], [1, 1])
        CT.checkTrue("the three cases are there, passes before holds", at("case .resolves", in: gate) > 0 && passesAt > at("case .resolves", in: gate) && holdsAt > passesAt)
        CT.checkTrue("only the resolves case dismisses the card, with the handled note", count("dismissApprovalCard(", in: gate) == 1 && at("dismissApprovalCard(", in: gate) < passesAt && gate.contains("dismissApprovalCard(note: HookOrigin.note(host: pending.host, stillWaiting: false))"))
        CT.checkTrue("the passes case touches nothing but the flag the switch reads", gate.contains("case .passes: approvalHeld = true"))
        CT.checkTrue("another session's SessionEnd does not remove the pill under its approval", hooks.contains("            guard !approvalHeld else { break }   // another session ended: the pill stays, its approval is still waiting"))
        CT.checkTrue("an alert does not replace the card in a compact island either", hooks.contains("} else if isAlert && (view == .approval || view == .question || state.pendingApproval == nil) {"))

        CT.section("the notes name the app the user is in; VS Code, Cursor and Codex read as they did")
        CT.check("the three notes come from the rule", count("HookOrigin.note(", in: hooks), 3)
        CT.check("no note is spelled in the server", count("Handled in ", in: hooks) + count("Still waiting in ", in: hooks), 0)
        CT.checkTrue("the approval keeps where it came from, and the notes use it", hooks.contains("subagentId: askedBy, host: host,") && hooks.contains("HookOrigin.note(host: pending.host, stillWaiting: false)") && types.contains("var host: String = \"VS Code\""))

        CT.section("a terminal session's pill brings its terminal forward")
        CT.checkTrue("the server notes the host and the session of Claude Code's events and permission requests only", count("state.noteHost(", in: hooks) == 2 && hooks.contains("if route == .claude { state.noteHost(agentId, session: sessionId, HookOrigin.hostBundleId(rawAgent: rawAgent, termProgram: termProgram, bundleId: bundleId)) }") && hooks.contains("if pillId == \"integration_claude\" { state.noteHost(pillId, session: sessionId, HookOrigin.terminalBundleId(termProgram: termProgram, bundleId: bundleId)) }"))
        CT.checkTrue("AppState holds it unpublished", app.contains("var hostBundleIds: [String: String] = [:]") && !app.contains("@Published var hostBundleIds"))
        CT.checkTrue("AppState holds the session's host and the pill's current session, unpublished", app.contains("var sessionHosts: [String: HookOrigin.TapHost] = [:]") && app.contains("var pillSessions: [String: String] = [:]") && !app.contains("@Published var sessionHosts") && !app.contains("@Published var pillSessions"))
        CT.checkTrue("noteHost takes the session, and forgetSession exists for SessionEnd", app.contains("func noteHost(_ pillId: String, session sessionId: String, _ bundleId: String?)") && app.contains("func forgetSession(_ sessionId: String)"))
        CT.checkTrue("the pill's tap asks the pure rule, in the GitHub build only, and VS Code's route follows unchanged (the routes live in AgentTarget, which the ↗ button, a drop on an agent's cat and a sidekick note share)", target.contains("case \"integration_claude\":\n            // The app of the session the user is looking at (HookOrigin.tapHost): the open card's session on this pill, else the pill's current one.\n            let appState = AppState.shared\n") && target.contains("if case .app(let id) = host, id == HookOrigin.desktopBundleId") && target.contains("let host = HookOrigin.tapHost(cardSession: cardSession, currentSession: appState.pillSessions[pillId], sessionHosts: appState.sessionHosts, pillHost: appState.hostBundleIds[pillId])") && at("HookOrigin.tapHost(", in: target) < at("let vscodeBundleId = \"com.microsoft.VSCode\"", in: target) && view.contains("AgentTarget.bringForward(pillId: task.id)"))
        CT.checkTrue("the tap takes the card's session only from a card on this pill, and reads the pill-keyed map only as the rule's fallback", target.contains("appState.pendingApproval.flatMap { $0.pillId == pillId ? $0.sessionId : nil }") && count("hostBundleIds[", in: target) == 1 && !target.contains("if let id = AppState.shared.hostBundleIds[pillId]") && count("hostBundleIds[", in: view) == 0)
        let sessionEnd = at("case \"SessionEnd\":", in: hooks)
        CT.checkTrue("SessionEnd forgets that session's host once, before the pill goes", sessionEnd > 0 && count("state.forgetSession(", in: hooks) == 1 && at("state.forgetSession(sessionId)", in: hooks, from: sessionEnd) > sessionEnd && at("state.forgetSession(sessionId)", in: hooks, from: sessionEnd) < at("state.removeTask(id: agentId)", in: hooks, from: sessionEnd))

        CT.section("fix round: a held card keeps its project name, a permission request notes its app, SessionEnd forgets before the guard, no VS Code case in TapHost")
        let upsertAt = at("private func upsertWorkspaceTask(", in: hooks)
        let heldGuard = at("guard !respectsCard || state.pendingApproval?.pillId != id else { return }", in: hooks)
        CT.checkTrue("upsertWorkspaceTask returns while a card on its pill is up, before it writes the name or the folder, when the guard applies", upsertAt > 0 && heldGuard > upsertAt && heldGuard < at("state.tasks[idx].name = projectName", in: hooks, from: upsertAt) && heldGuard < at("state.tasks[idx].sessionCwd = cwd", in: hooks, from: upsertAt))
        CT.checkTrue("the insertion path is unchanged: a missing pill is still created after the main pill", at("state.tasks.insert(task, at: mainIdx + 1)", in: hooks, from: upsertAt) > heldGuard)

        CT.section("round 4: the card's own permission request renames its pill even when it displaces another card; the event paths stay guarded")
        CT.checkTrue("upsertWorkspaceTask takes respectsCard, defaulting to true, so the event paths stay guarded", hooks.contains("private func upsertWorkspaceTask(id: String, projectName: String, cwd: String = \"\", respectsCard: Bool = true) {"))
        CT.checkTrue("the guard is gated by respectsCard, so a caller that passes false skips it and the existing-task branch writes the name and folder", heldGuard > 0 && hooks.contains("guard !respectsCard || state.pendingApproval?.pillId != id else { return }"))
        let permissionAt = at("private func processPermissionRequest(", in: hooks)
        let permissionUpsert = at("upsertWorkspaceTask(id: pillId, projectName: projectName, cwd: cwd, respectsCard: false)", in: hooks, from: permissionAt)
        CT.checkTrue("processPermissionRequest's upsert passes respectsCard: false, and runs before it assigns its own card", permissionAt > 0 && permissionUpsert > permissionAt && permissionUpsert < at("state.pendingApproval = ApprovalInfo(", in: hooks, from: permissionAt))
        CT.check("only the permission request passes respectsCard: false", count("respectsCard: false", in: hooks), 1)
        CT.check("respectsCard is named only in the declaration, the guard and the permission call, so every processEvent call keeps the default", count("respectsCard", in: hooks), 3)
        let permissionNote = at("if pillId == \"integration_claude\" { state.noteHost(pillId, session: sessionId, HookOrigin.terminalBundleId(termProgram: termProgram, bundleId: bundleId)) }", in: hooks)
        CT.checkTrue("processPermissionRequest notes the Claude Code pill's session and app before it touches the pill", permissionAt > 0 && permissionNote > permissionAt && permissionNote < at("state.touchPill(pillId)", in: hooks, from: permissionAt))
        let endForget = at("state.forgetSession(sessionId)", in: hooks, from: sessionEnd)
        CT.checkTrue("SessionEnd forgets its session's host before the approval guard, so another session's end still forgets it", sessionEnd > 0 && endForget > sessionEnd && endForget < at("guard !approvalHeld else { break }", in: hooks, from: sessionEnd))
        CT.checkTrue("TapHost has no VS Code case: its no-app case is .noApp", rules.contains("enum TapHost: Equatable { case app(String), noApp }") && count(".vscode", in: rules) == 0)
        CT.checkTrue("noteHost records .noApp for a session with no bundle ID, VS Code and unmapped alike", app.contains("sessionHosts[sessionId] = .noApp") && count(".vscode", in: app) == 0)

        CT.section("a card holds its pill's shown state: other sessions' events are recorded, the pill keeps the waiting look, the latest state shows when the card closes")
        let updateAt = at("func updateTask(id: String, state: BotState) {", in: app)
        let updateBody = updateAt > 0 ? String(app.utf16[app.utf16.index(app.utf16.startIndex, offsetBy: updateAt)..<app.utf16.index(app.utf16.startIndex, offsetBy: at("\n    }\n", in: app, from: updateAt))])! : ""
        CT.checkTrue("(a) updateTask asks whether a card waits on the pill and shows what the pure rule says", !updateBody.isEmpty && updateBody.contains("let waiting = cardWaiting(on: id)") && updateBody.contains("HookOrigin.shownWhileCard(cardWaiting: waiting, requested: state, current: tasks[idx].state)") && !updateBody.contains("tasks[idx].state = state"))
        CT.checkTrue("(a) a card waits on a pill when its approval is there, or its question with the pill that owns it", app.contains("func cardWaiting(on id: String) -> Bool { pendingApproval?.pillId == id || (pendingQuestion != nil && questionPillId == id) }"))
        CT.checkTrue("(a) the held states are unpublished", app.contains("private var heldPills: [String: (state: BotState, finalLine: String?)] = [:]") && !app.contains("@Published private var heldPills") && !app.contains("@Published var heldPills"))
        CT.checkTrue("(a) the requested state is held while the card waits, and a free pill drops what was held", updateBody.contains("if waiting { heldPills[id] = (state, HookOrigin.heldLine(entryExists: heldPills[id] != nil, held: heldPills[id]?.finalLine, current: tasks[idx].finalLine)) } else { heldPills[id] = nil }"))
        CT.checkTrue("(a) the card's own state shows at once, and nothing is held for it", app.contains("func showCardState(id: String, state: BotState) {") && count("state.showCardState(id: pillId, state: .approval)", in: hooks) == 1 && count("state.showCardState(id: pillId, state: .question)", in: hooks) == 1 && count("state.updateTask(id: pillId, state: .approval)", in: hooks) + count("state.updateTask(id: pillId, state: .question)", in: hooks) == 0)
        CT.checkTrue("(a) the question's pill lives in AppState, where the rule reads it", app.contains("var questionPillId: String = \"\"") && !app.contains("@Published var questionPillId") && count("private var questionPillId", in: hooks) == 0 && count("state.questionPillId = pillId", in: hooks) == 1)
        CT.checkTrue("(a) a pill that goes away forgets what was held for it", app.contains("heldPills[id] = nil", ) && at("heldPills[id] = nil", in: app, from: at("func removeTask(id: String) {", in: app)) > at("func removeTask(id: String) {", in: app))
        CT.check("(b) every place a card closes shows the held state: the approval's two closures, the question's two", count("state.releasePill(id: pillId", in: hooks) + count("AppState.shared.releasePill(id: pillId", in: hooks), 4)
        CT.check("(b) none of them sets .working over the held state any more", count("state.updateTask(id: pillId, state: .working)", in: hooks), 0)
        CT.checkTrue("(b) the approval's two closures keep .working as the fallback, after the card is cleared", count("state.pendingApproval = nil\n        state.isPinned = false\n        let shown = state.releasePill(id: pillId, fallback: .working)", in: hooks) == 2)
        CT.checkTrue("(b) the question's dismissal keeps .working as the fallback, after the card is cleared", count("state.pendingQuestion = nil\n        state.isPinned = false\n        let shown = state.releasePill(id: pillId, fallback: .working)", in: hooks) == 1)
        CT.checkTrue("(b) a question card that only leaves the screen releases the pill and keeps the state it showed", count("AppState.shared.pendingQuestion = nil\n        let pillId = AppState.shared.questionPillId\n        let shown = AppState.shared.releasePill(id: pillId)", in: hooks) == 1)
        CT.checkTrue("(b) the close takes the held state from the pure rule", app.contains("HookOrigin.shownAfterCard(held: held?.state, fallback: fallback ?? tasks[idx].state)"))
        CT.check("(b) a held finish goes idle after the usual delay, once the card is closed: every close schedules the one timer", count("scheduleFinishedIdle(agentId: pillId, external: false)", in: hooks), 4)
        let timerAt = at("private func scheduleFinishedIdle(agentId: String, external: Bool) {", in: hooks)
        let timerEnd = at("\n    }\n", in: hooks, from: timerAt)
        let timer = timerAt > 0 && timerEnd > timerAt ? String(hooks.utf16[hooks.utf16.index(hooks.utf16.startIndex, offsetBy: timerAt)..<hooks.utf16.index(hooks.utf16.startIndex, offsetBy: timerEnd)])! : ""
        CT.checkTrue("(c) the finished-to-idle timer is one helper, with its 5.2 s delay, and Stop calls it", !timer.isEmpty && timer.contains("+ 5.2)") && count("+ 5.2)", in: hooks) == 1 && count("scheduleFinishedIdle(agentId: agentId, external: isExternalAgent)", in: hooks) == 1)
        CT.checkTrue("(c) the timer's closure returns while a card waits on the pill (the card's state goes to the pure rule), before it sets .idle or removes the pill", timer.contains("cardWaiting: AppState.shared.cardWaiting(on: agentId)) else { return }") && at("cardWaiting: AppState.shared.cardWaiting(on: agentId)) else { return }", in: timer) < at("AppState.shared.removeTask(id: agentId)", in: timer) && at("cardWaiting: AppState.shared.cardWaiting(on: agentId)) else { return }", in: timer) < at("AppState.shared.updateTask(id: agentId, state: .idle)", in: timer))
        CT.checkTrue("(e) a cleared held line stays cleared: updateTask asks the pure rule whether an entry exists, and no longer falls back with ?? to the pill's line", updateBody.contains("HookOrigin.heldLine(entryExists: heldPills[id] != nil, held: heldPills[id]?.finalLine, current: tasks[idx].finalLine)") && !updateBody.contains("?? tasks[idx].finalLine") && count("?? tasks[idx].finalLine", in: app) == 0)
        CT.checkTrue("(f) the finished-to-idle timer is superseded: the helper bumps the pill's generation and captures it, the unpublished map lives in HookServer", timer.contains("finishedGeneration[agentId, default: 0] += 1") && timer.contains("let generation = finishedGeneration[agentId, default: 0]") && hooks.contains("private var finishedGeneration: [String: Int] = [:]") && !hooks.contains("@Published") && !app.contains("finishedGeneration"))
        CT.checkTrue("(f) the closure acts only when the pure rule says so (current generation, no card waiting), before it removes the pill or sets .idle", at("HookOrigin.finishedIdleApplies(captured: generation, latest: self.finishedGeneration[agentId, default: 0], cardWaiting: AppState.shared.cardWaiting(on: agentId))", in: timer) > 0 && at("HookOrigin.finishedIdleApplies(", in: timer) < at("AppState.shared.removeTask(id: agentId)", in: timer) && at("HookOrigin.finishedIdleApplies(", in: timer) < at("AppState.shared.updateTask(id: agentId, state: .idle)", in: timer) && count("+ 5.2)", in: hooks) == 1)
        CT.checkTrue("(d) the final line is held with the state: Stop, and every clear in processEvent but SessionEnd's, go through setFinalLine", count("state.setFinalLine(id: agentId, finalText)", in: hooks) == 1 && count("state.setFinalLine(id: agentId, nil)", in: hooks) == 3 && count(".finalLine = ", in: hooks) == 1)
        CT.checkTrue("(d) setFinalLine holds the line while a card waits on a pill with a held state, and writes it otherwise; the release applies it with the state", app.contains("func setFinalLine(id: String, _ line: String?) {") && app.contains("if cardWaiting(on: id), heldPills[id] != nil { heldPills[id]?.finalLine = line } else { tasks[idx].finalLine = line }") && app.contains("if let held { tasks[idx].finalLine = held.finalLine }"))

        CT.finish()
    }
}
