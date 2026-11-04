import Foundation

// What the app wires together from the pure parts: the provider the factory makes, the words and buttons the chat shows
// for Claude Code's failures, and (as source pins, because no test program can run the app's windows) where a chat's
// approvals are routed and handed back.

@main
@MainActor
enum ClaudeCodeWiringTests {
    static func main() {
        factory()
        messages()
        pins()
        quickHoldPins()
        T.finish()
    }

    /// The quick-action hold (Task 5): Fix and Rewrite run at no tools, an Explain chat is held there until the picker is used, and only a pick, a cleared
    /// chat or another conversation ends the hold.
    static func quickHoldPins() {
        T.section("Quick actions run with no tools; an Explain chat is held there (source pins)")
        let service = (try? String(contentsOfFile: "NotchBuddy/Sources/App/ClaudeService.swift", encoding: .utf8)) ?? ""
        let picker = (try? String(contentsOfFile: "NotchBuddy/Sources/App/ClaudeChatViews.swift", encoding: .utf8)) ?? ""
        let app = (try? String(contentsOfFile: "NotchBuddy/Sources/App/AppState.swift", encoding: .utf8)) ?? ""
        T.checkTrue("the sources were read", service.contains("func clearConversation(state: AppState)") && picker.contains("private func choose(")
            && app.contains("var claudeLevel: ClaudeCodeLevel"))
        func offset(_ needle: String, in text: String) -> Int { text.range(of: needle)?.lowerBound.utf16Offset(in: text) ?? -1 }

        let appHold = "    @Published var claudeQuickHold: Bool = false"
        T.checkTrue("AppState holds the quick hold beside the chat's level, once, as a published Bool",
                    app.components(separatedBy: appHold).count - 1 == 1 && offset(appHold, in: app) > offset("var claudeLevel: ClaudeCodeLevel", in: app))
        // The hold's own line: the last directive before it opens #if !APPSTORE, and an #endif closes it after.
        let holdAtIndex = app.range(of: "@Published var claudeQuickHold")?.lowerBound
        let before = holdAtIndex.map { String(app[..<$0]) } ?? "", after = holdAtIndex.map { String(app[$0...]) } ?? ""
        let openAt = before.range(of: "#if !APPSTORE", options: .backwards)?.lowerBound.utf16Offset(in: before) ?? -1
        let closedAt = before.range(of: "#endif", options: .backwards)?.lowerBound.utf16Offset(in: before) ?? -1
        T.checkTrue("the hold sits inside the same #if !APPSTORE block as the chat's level", holdAtIndex != nil && openAt > closedAt && after.contains("#endif"))

        let quick = body(of: "quickReply", in: service)
        let startAt = offset("session.level = .noTools", in: quick), planAt = offset("session.plan(", in: quick)
        T.checkTrue("quickReply runs its session at no tools, before it plans", startAt >= 0 && planAt >= 0 && startAt < planAt)

        let reply = body(of: "reply", in: service)
        T.checkTrue("reply sets the level through the hold rule, held by a quick first turn or a held chat",
                    reply.contains("claudeSession.level = ClaudeQuickHold.level(held: firstSystem != nil || state.claudeQuickHold, chosen: state.claudeLevel)"))
        T.checkTrue("reply no longer sets a quick turn to Chat only", !reply.contains("? .chatOnly :"))

        let explain = body(of: "explain", in: service)
        let clearAt = offset("clearConversation(state: state)", in: explain), holdAt = offset("state.claudeQuickHold = true", in: explain)
        T.checkTrue("explain holds its chat after it clears the old one", clearAt >= 0 && holdAt > clearAt)
        // The hold must sit inside the #if !APPSTORE block that opens before it and closes after it: exactly one #if (the opener) and no #endif in between.
        let holdRange = explain.range(of: "state.claudeQuickHold = true")
        let openRange = holdRange.flatMap { explain.range(of: "#if !APPSTORE", options: .backwards, range: explain.startIndex..<$0.lowerBound) }
        let closeRange = holdRange.flatMap { explain.range(of: "#endif", range: $0.upperBound..<explain.endIndex) }
        let inside = (openRange != nil && closeRange != nil) ? String(explain[openRange!.lowerBound..<closeRange!.lowerBound]) : ""
        T.checkTrue("the hold sits inside the #if !APPSTORE block that opens before it and closes after it, with no other #if or #endif between",
                    holdRange != nil && openRange != nil && closeRange != nil && inside.components(separatedBy: "#if").count == 2
                        && !inside.contains("#endif") && inside.contains("state.claudeQuickHold = true"))

        T.checkTrue("clearConversation ends the hold", body(of: "clearConversation", in: service).contains("state.claudeQuickHold = false"))
        T.checkTrue("open(conversationID:) still clears the chat, so it ends the hold too", body(of: "open", in: service).contains("clearConversation(state: state)"))

        let choose = body(of: "choose", in: picker)
        T.checkTrue("a pick in the picker ends the hold", choose.contains("state.claudeQuickHold = false") && choose.contains("state.claudeLevel = level"))
        T.checkTrue("the Folder control says No tools while the chat is held",
                    picker.contains("CompanionChrome.folderLabel(levelKey: state.claudeQuickHold ? \"none\" : state.claudeLevel.key"))
        // The three level rows light only while the hold is off, and none of them is disabled by it (a pick still ends the hold).
        T.checkTrue("the Chat only, Read-only and Agent rows are lit only when the hold is off",
                    picker.contains("isCurrent: state.claudeLevel == .chatOnly && !state.claudeQuickHold")
                        && picker.contains("{ if case .readOnly = state.claudeLevel { !state.claudeQuickHold } else { false } }")
                        && picker.contains("{ if case .agent = state.claudeLevel { !state.claudeQuickHold } else { false } }"))
        T.checkTrue("the hold disables no level row", !picker.contains("enabled: !state.claudeQuickHold") && !picker.contains("enabled: state.claudeQuickHold"))
    }

    static func factory() {
        T.section("The provider factory")
        let target = ChatTarget(provider: .claudeCode, model: "sonnet", placement: .cloud)
        var factory = ProviderFactory()
        T.check("without a setup there is no engine", factory.make(target) is UnavailableProvider, true)
        factory.claude = ClaudeCodeSetup(executable: "/x/claude", turn: ClaudeCodeTurn(level: .chatOnly, sessionID: "s", resume: false), preamble: "recap")
        let provider = factory.make(target) as? ClaudeCodeProvider
        T.check("with one it is Claude Code, on that turn", [provider?.executable, provider?.turn.sessionID, provider?.preamble], ["/x/claude", "s", "recap"])
        T.check("and it is cloud", provider?.placement, .cloud)
        T.check("other providers are untouched", factory.make(ChatTarget(provider: .ollama, model: "m", placement: .local)) is OpenAICompatibleProvider, true)
    }

    static func messages() {
        T.section("Notes and buttons")
        let target = ChatTarget(provider: .claudeCode, model: "sonnet", placement: .cloud)
        let signedOut = AIMessages.error(AIError(kind: .auth, code: ClaudeCodeError.signedOut), target: target)
        T.check("signed out", [signedOut.text, signedOut.action == .signInClaude ? "sign in" : "other"], ["Claude Code is signed out.", "sign in"])
        T.check("the pairs", [
            AIMessages.error(AIError(kind: .unreachable, code: ClaudeCodeError.missing), target: target).action == .installClaude,
            AIMessages.error(AIError(kind: .badRequest, code: ClaudeCodeError.tooOld), target: target).action == .updateClaude,
            AIMessages.error(AIError(kind: .server, code: ClaudeCodeError.crashed), target: target).action == .tryAgain,
            AIMessages.error(AIError(kind: .badRequest, code: ClaudeCodeError.needsGit), target: target).action == .installGit,
        ], [true, true, true, true])
        let limit = AIMessages.error(AIError(kind: .billing, code: ClaudeCodeError.planLimit), target: target)
        T.check("a plan limit says so", limit.text, "Your Claude plan's limit was reached.")
        T.check("with no button, and never a billing page", limit.action == nil, true)
        T.check("another provider's key note is unchanged",
                AIMessages.error(AIError(kind: .auth), target: ChatTarget(provider: .anthropic, model: "m", placement: .cloud)).text,
                "Your Anthropic key was rejected.")
        T.check("an error with no Claude Code code falls through to the general words",
                AIMessages.error(AIError(kind: .overloaded), target: target).text, "Claude is still busy. Try again in a moment.")
    }

    // MARK: - Source pins

    /// The text of the function `name` in `text`: from its signature to the next member.
    static func body(of name: String, in text: String) -> String {
        guard let start = text.range(of: "func \(name)(") else { return "" }
        let rest = text[start.upperBound...]
        let end = rest.range(of: "\n    (@MainActor|private func |func |static func |// MARK)", options: .regularExpression)?.lowerBound ?? rest.endIndex
        return String(rest[..<end])
    }

    static func pins() {
        T.section("Where a chat's approvals are routed (source pins)")
        let hook = (try? String(contentsOfFile: "NotchBuddy/Sources/App/HookServer.swift", encoding: .utf8)) ?? ""
        T.checkTrue("HookServer.swift was read", hook.contains("final class HookServer"))
        for name in ["processEvent", "processPermissionRequest", "processQuestionRequest"] {
            let text = body(of: name, in: hook)
            let route = text.range(of: "ClaudeHookRouting.route(")?.lowerBound
            let session = text.range(of: "let sessionId")?.lowerBound
            T.checkTrue("\(name) asks the router before it looks at a session, so a chat never makes or touches a pill",
                        route != nil && session != nil && route! < session!)
            let guarded = text.range(of: "#if !APPSTORE")?.lowerBound
            T.checkTrue("and only in a build that has the engine", guarded != nil && route != nil && guarded! < route!)
        }
        let service = (try? String(contentsOfFile: "NotchBuddy/Sources/App/ClaudeService.swift", encoding: .utf8)) ?? ""
        T.checkTrue("ClaudeService.swift was read", service.contains("final class ClaudeService"))
        T.checkTrue("a new conversation hands every waiting approval back", body(of: "clearConversation", in: service).contains("cancelChatApprovals()"))
        T.checkTrue("so does Stop", body(of: "stop", in: service).contains("cancelChatApprovals()"))
        T.checkTrue("and a session retired by a level change", service.contains("if next.retired != nil { HookServer.shared.cancelChatApprovals() }"))
        let failed = body(of: "finish", in: service)
        let refusal = failed.range(of: "result.error?.code == ClaudeCodeError.toolsPresent")
        T.checkTrue("a run refused for its tools retires the chat's session (its id stays routed to the chat) and keeps a recap for the fresh one",
                    refusal != nil && failed[refusal!.upperBound...].prefix(600).contains("quickClaudeSessions.insert(claudeSession.reset())")
                        && failed[refusal!.upperBound...].prefix(600).contains("claudeRecap = ClaudeCodeRecap.text(")
                        && failed[refusal!.upperBound...].prefix(600).contains("cancelChatApprovals()"))
        T.checkTrue("only the chat's current session, and the quick actions in flight (F3a-mac Task 8), are live", service.contains("var liveClaudeSessions: Set<String> { quickClaudeSessions.union([claudeSession.sessionID]) }"))
        cardPins(hook)
    }

    /// The chat's card against the user's own pin and cards (fix round 1 of Task 10).
    static func cardPins(_ hook: String) {
        T.section("The chat's card and the user's own pin and cards (source pins)")
        // 1. A pin the user already made is never released by the chat's card.
        let hold = body(of: "holdIslandForChatCard", in: hook)
        let owner = hold.range(of: "chatApprovalPinned = !state.isPinned")?.lowerBound
        let pin = hold.range(of: "state.isPinned = true")?.lowerBound
        T.checkTrue("the card owns the pin only if the island was not pinned before it", owner != nil && pin != nil && owner! < pin!)
        T.checkTrue("a new card and a re-surfaced card both pin through it",
                    body(of: "showChatApproval", in: hook).contains("holdIslandForChatCard(") && body(of: "resurfaceChatApproval", in: hook).contains("holdIslandForChatCard("))
        // 2. A click answers the card the user saw, or nothing.
        let decision = body(of: "sendChatApprovalDecision", in: hook)
        let guardAt = decision.range(of: "if let id, chatApprovals.front?.id != id { return }")?.lowerBound
        let popAt = decision.range(of: "chatApprovals.popFront()")?.lowerBound
        T.checkTrue("a decision takes the id of the card the click was on", decision.contains("id: UUID? = nil"))
        T.checkTrue("a click on a card that is no longer the front is ignored before anything is popped",
                    guardAt != nil && popAt != nil && guardAt! < popAt!)
        // 3. After the user's own approval or question is resolved, a queued chat card comes back.
        for name in ["dismissApprovalCard", "sendApprovalDecision", "dismissQuestionCard"] {
            let text = body(of: name, in: hook)
            let call = text.range(of: "resurfaceChatApproval()")
            let tail = call.map { String(text[$0.upperBound...]) } ?? ""
            let head = call.map { String(text[..<$0.lowerBound].suffix(40)) } ?? ""
            T.checkTrue("\(name) ends by bringing a queued chat card back, only in a build that has the engine",
                        call != nil && tail.hasPrefix("\n        #endif\n    }") && head.contains("#if !APPSTORE"))
        }
        let back = body(of: "resurfaceChatApproval", in: hook)
        T.checkTrue("and never while the user's own approval or question is still waiting",
                    back.contains("state.pendingApproval == nil, state.pendingQuestion == nil"))
        windowPins()
    }

    /// A waiting chat card holds the island open, so the delayed collapse of a handled approval cannot hide it.
    static func windowPins() {
        T.section("A waiting chat card holds the island open (source pins)")
        let window = (try? String(contentsOfFile: "NotchBuddy/Sources/App/IslandWindowController.swift", encoding: .utf8)) ?? ""
        T.checkTrue("IslandWindowController.swift was read", window.contains("final class IslandWindowController"))
        let held = "        #if !APPSTORE\n"
            + "        fsm.isHeldOpen = { AppState.shared.pendingApproval != nil || AppState.shared.chatApproval != nil || AppState.shared.shelfHoldsIsland || AppState.shared.linkHoldsIsland }\n"
            + "        #else\n"
            + "        fsm.isHeldOpen = { AppState.shared.pendingApproval != nil || AppState.shared.shelfHoldsIsland || AppState.shared.linkHoldsIsland }\n"
            + "        #endif\n"
        T.checkTrue("held open by a waiting chat card, in a build that has the engine; the App Store line holds only approvals, the shelf (G1) and the link (G2)",
                    window.contains(held))
        let waiting = "        #if !APPSTORE\n"
            + "        if state.chatApproval != nil { return true }\n"
            + "        #endif\n"
            + "        return state.pendingApproval != nil || state.pendingQuestion != nil\n"
        T.checkTrue("the pill shortcuts and Escape treat a waiting chat card as a decision waiting", window.contains(waiting))
    }
}
