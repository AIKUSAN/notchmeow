import Foundation
import Darwin
import AppKit
import SwiftUI
import CryptoKit

// MARK: - HookServer
// Listens on a Unix domain socket for events from nm-hook (Claude Code hooks).
// Thread-safe: socket I/O on background threads, state updates dispatched to main queue.

final class HookServer: @unchecked Sendable {
    static let shared = HookServer()

    // Support directory paths
    static var supportDir: URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("NotchMeow")
    }
    static var socketPath: String {
        #if APPSTORE
        // Container home root keeps path ≤ 103 bytes (sun_path limit on macOS is 104 incl. NUL)
        // /Users/<user>/Library/Containers/io.github.aikusan.notchmeow.store/Data/nm.sock = 73 + len(user) bytes ✓
        return NSHomeDirectory() + "/nm.sock"
        #else
        return supportDir.appendingPathComponent("nm.sock").path
        #endif
    }
    // hookScriptPath is only used by the non-App Store build.
    // App Store build derives the command from the panel-selected claudeURL in buildHooksData(claudeURL:).
    static var hookScriptPath: String { supportDir.appendingPathComponent("nm-hook").path }

    // No approval blocking state — notch is notification-only, user answers in VS Code

    private static let maxPayload = 1_048_576          // 1 MB — reject oversized messages
    private static let receiveTimeoutSeconds: Int = 5   // SO_RCVTIMEO on client sockets
    private static let maxConnections = 32              // concurrent connection ceiling

    private var serverFD: Int32 = -1
    private let connectionLock = NSLock()
    private var connectionCount = 0
    private var pendingApprovalFD: Int32 = -1         // held open while user decides
    private var approvalFDSource: (any DispatchSourceRead)? = nil  // monitors pendingApprovalFD
    private var pendingQuestionFD: Int32 = -1         // held open while user answers AskUserQuestion
    private var questionFDSource: (any DispatchSourceRead)? = nil  // monitors pendingQuestionFD
    private var focusBeforeQuestion: String? = nil    // saved focus to restore after question
    private var activeSessionId: String? = nil        // current Claude Code session
    private var focusBeforeApproval: String? = nil    // saved focus to restore after approval

    private init() {}

    // MARK: - Approval fd helpers

    /// An approval that a subagent asked for is over (answered, dismissed or displaced): its kitten is back to work.
    @MainActor
    private func resolveApprovalKitten(_ info: ApprovalInfo?) {
        guard let info, let subagent = info.subagentId else { return }
        AppState.shared.kittenEvent(info.pillId, CatKittenHooks.resolved(subagentId: subagent, now: CACurrentMediaTime() * 1000))
    }

    @MainActor
    private func cancelApprovalFDSource() {
        approvalFDSource?.cancel()
        approvalFDSource = nil
    }

    /// Cancels the approval fd source (which closes the fd via its cancel handler), shows a
    /// 3-second note, clears approval state, then collapses the island.
    @MainActor
    private func dismissApprovalCard(note: String) {
        // cancelApprovalFDSource() triggers the cancel handler which closes the fd.
        // Never close the fd here directly — Apple requires it to happen in the cancel handler.
        cancelApprovalFDSource()
        pendingApprovalFD = -1
        let state = AppState.shared
        let pillId = state.pendingApproval?.pillId ?? "integration_claude"
        let askedSession = state.pendingApproval?.sessionId
        resolveApprovalKitten(state.pendingApproval)
        state.pendingApproval = nil
        state.isPinned = false
        let shown = state.releasePill(id: pillId, fallback: .working)   // the latest state another session asked while the card was up, else working
        if shown == .finished { scheduleFinishedIdle(agentId: pillId, external: false) }   // an approval is never an external agent's
        clearPillBadge(id: pillId)
        // Restore focus to the pill that was focused before the approval card appeared.
        if let prev = focusBeforeApproval {
            focusBeforeApproval = nil
            if state.focusId == pillId, state.tasks.contains(where: { $0.id == prev }) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) { state.focusId = prev }
            }
        }
        state.noteMessage = FocusAware.cardNote(note, mark: askedSession.flatMap { state.focusMarks.forSession($0, now: FocusAwareApp.now()) })
        state.view = .note
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
            NotificationCenter.default.post(name: .islandCollapse, object: nil)
        }
        #if !APPSTORE
        resurfaceChatApproval()
        #endif
    }

    // MARK: - Question fd helpers

    @MainActor
    private func cancelQuestionFDSource() {
        questionFDSource?.cancel()
        questionFDSource = nil
    }

    @MainActor
    private func dismissQuestionCard(note: String) {
        cancelQuestionFDSource()
        pendingQuestionFD = -1
        let state = AppState.shared
        let pillId = state.questionPillId
        state.pendingQuestion = nil
        state.isPinned = false
        let shown = state.releasePill(id: pillId, fallback: .working)
        if shown == .finished { scheduleFinishedIdle(agentId: pillId, external: false) }
        clearPillBadge(id: pillId)
        if let prev = focusBeforeQuestion {
            focusBeforeQuestion = nil
            if state.focusId == pillId, state.tasks.contains(where: { $0.id == prev }) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) { state.focusId = prev }
            }
        }
        if !note.isEmpty {
            state.noteMessage = note
            state.view = .note
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                NotificationCenter.default.post(name: .islandCollapse, object: nil)
            }
        } else {
            state.view = state.tasks.isEmpty ? .empty : .overview
        }
        #if !APPSTORE
        resurfaceChatApproval()
        #endif
    }

    /// Called by QuestionView. Sends answers JSON and cleans up.
    @MainActor
    func sendQuestionAnswers(_ answers: [String: Any]) {
        let fd = pendingQuestionFD
        pendingQuestionFD = -1
        let source = questionFDSource
        questionFDSource = nil
        if fd >= 0, let data = try? JSONSerialization.data(withJSONObject: ["permissionDecision": "answer", "answers": answers], options: .withoutEscapingSlashes),
           let json = String(data: data, encoding: .utf8) {
            Task.detached { [weak self] in
                self?.sendLine(fd: fd, text: json)
                DispatchQueue.main.async { source?.cancel() }
            }
        } else {
            source?.cancel()
        }
        dismissQuestionCard(note: "")
    }

    /// Called by QuestionView.onDisappear — card left screen without an explicit answer.
    /// Sends "ask" immediately to unblock nm-hook; does NOT navigate (view already changed).
    @MainActor
    func releaseQuestionFD() {
        guard pendingQuestionFD >= 0 else { return }
        let fd = pendingQuestionFD
        pendingQuestionFD = -1
        let source = questionFDSource
        questionFDSource = nil
        AppState.shared.pendingQuestion = nil
        let pillId = AppState.shared.questionPillId
        let shown = AppState.shared.releasePill(id: pillId)   // the question left the screen: the pill shows the state held for it, else the one it shows
        if shown == .finished { scheduleFinishedIdle(agentId: pillId, external: false) }
        Task.detached { [weak self] in
            self?.sendLine(fd: fd, text: #"{"permissionDecision":"ask"}"#)
            DispatchQueue.main.async { source?.cancel() }
        }
    }

    /// Called by QuestionView "Reply in terminal" button.
    @MainActor
    func sendQuestionAsk() {
        let fd = pendingQuestionFD
        pendingQuestionFD = -1
        let source = questionFDSource
        questionFDSource = nil
        if fd >= 0 {
            Task.detached { [weak self] in
                self?.sendLine(fd: fd, text: #"{"permissionDecision":"ask"}"#)
                DispatchQueue.main.async { source?.cancel() }
            }
        } else {
            source?.cancel()
        }
        dismissQuestionCard(note: "")
    }

    /// Returns the tool_input serialized as sorted-keys JSON, "" if absent or empty.
    /// Same computation used in processPermissionRequest and processEvent to match PostToolUse.
    private static func approvalInputKey(_ input: [String: Any]) -> String {
        guard !input.isEmpty,
              let data = try? JSONSerialization.data(withJSONObject: input, options: .sortedKeys),
              let str = String(data: data, encoding: .utf8) else { return "" }
        return str
    }

    // MARK: - Start

    func start() {
        // Ensure support directory exists (mode 0700 — not world-readable)
        let dir = Self.supportDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700 as NSNumber], ofItemAtPath: dir.path)
        #if !APPSTORE
        installHookScript()
        #endif
        Thread.detachNewThread { self.serverThread() }
    }

    // MARK: - Socket server (background thread)

    private func serverThread() {
        let path = Self.socketPath
        // sun_path on macOS is 104 bytes including the NUL terminator → max 103 usable bytes
        let maxSunPathBytes = MemoryLayout<sockaddr_un>.size - MemoryLayout<sa_family_t>.size - 1
        guard path.utf8.count <= maxSunPathBytes else {
            NSLog("HookServer: socket path too long (\(path.utf8.count) bytes, max \(maxSunPathBytes)): \(path)")
            return
        }
        try? FileManager.default.removeItem(atPath: path)

        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return }
        serverFD = fd

        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let cpath = Array(path.utf8CString)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            for (i, c) in cpath.enumerated() where i < raw.count { raw[i] = UInt8(bitPattern: c) }
        }

        let bindRC = withUnsafePointer(to: &addr) { ptr in
            ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard bindRC == 0 else { close(fd); return }
        // Restrict socket to owner only
        chmod(path, 0o600)
        guard Darwin.listen(fd, 32) == 0 else { close(fd); return }

        while true {
            let clientFD = Darwin.accept(fd, nil, nil)
            guard clientFD >= 0 else { break }
            // Reject connections from other users (same-UID check)
            var euid: uid_t = 0
            var egid: gid_t = 0
            guard getpeereid(clientFD, &euid, &egid) == 0, euid == getuid() else {
                close(clientFD)
                continue
            }
            // Enforce concurrent connection ceiling
            connectionLock.lock()
            let count = connectionCount
            if count < Self.maxConnections { connectionCount += 1 }
            connectionLock.unlock()
            guard count < Self.maxConnections else {
                close(clientFD)
                continue
            }
            Thread.detachNewThread { self.handleClient(fd: clientFD) }
        }
    }

    // MARK: - Client handler (background thread)

    private func handleClient(fd: Int32) {
        defer {
            connectionLock.lock(); connectionCount -= 1; connectionLock.unlock()
        }
        // 5-second receive timeout — unresponsive clients don't hold threads forever
        var tv = timeval(tv_sec: Self.receiveTimeoutSeconds, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        // Read newline-delimited JSON
        var raw = Data()
        var buf = [UInt8](repeating: 0, count: 4096)
        outer: while true {
            let n = recv(fd, &buf, buf.count, 0)
            if n <= 0 { break }
            for i in 0..<n {
                if buf[i] == UInt8(ascii: "\n") { break outer }
                raw.append(buf[i])
            }
            if raw.count > Self.maxPayload { break }
        }

        guard !raw.isEmpty,
              let payload = try? JSONSerialization.jsonObject(with: raw) as? [String: Any] else {
            sendLine(fd: fd, text: #"{"ok":true}"#)
            close(fd)
            return
        }

        let nmKind = payload["nm_kind"] as? String ?? ""

        // statusline payloads are handled separately — no session, no reveal, no sound
        if nmKind == "statusline" {
            Task { @MainActor in self.processStatusLine(payload: payload) }
            sendLine(fd: fd, text: #"{"ok":true}"#)
            close(fd)
            return
        }

        // AskUserQuestion via --ask PreToolUse hook — hold fd open like PermissionRequest
        if nmKind == "ask_user_question" {
            let toolInput = payload["tool_input"] as? [String: Any] ?? [:]
            if let parsed = AskQuestion.parse(toolInput: toolInput) {
                Task { @MainActor in self.processQuestionRequest(fd: fd, parsed: parsed, payload: payload) }
            } else {
                // Malformed payload — fall back: send ask so Claude Code re-asks in terminal
                sendLine(fd: fd, text: #"{"permissionDecision":"ask"}"#)
                close(fd)
            }
            return
        }

        let eventName = payload["hook_event_name"] as? String ?? ""

        if eventName == "PermissionRequest" {
            // Hold fd open — Claude Code waits for our decision (up to 120s)
            Task { @MainActor in self.processPermissionRequest(fd: fd, payload: payload) }
        } else {
            Task { @MainActor in self.processEvent(name: eventName, payload: payload) }
            sendLine(fd: fd, text: #"{"ok":true}"#)
            close(fd)
        }
    }


    // MARK: - Event → AppState
    // Claude Code events route to the permanent "integration_claude" task.
    // Events tagged with a valid nm_agent route to a dynamic "integration_<agent>" task.
    // View switches only happen if VS Code (or the agent pill) is currently focused.
    // When not focused: state updates animate the mini bot in the pill; badge shown for alerts.

    @MainActor
    private func processEvent(name: String, payload: [String: Any]) {
        let state = AppState.shared
        #if !APPSTORE
        // The events of a chat's own Claude Code run are not a session: the chat's stream already shows its steps.
        if case .chat = ClaudeHookRouting.route(payload: payload, live: ClaudeService.shared.liveClaudeSessions) { return }
        #endif
        CatSleepClock.shared.agentEvent()   // any agent event wakes a sleeping cat and starts its ten minutes again
        let sessionId = payload["session_id"] as? String
                     ?? payload["conversation_id"] as? String
                     ?? "unknown"
        let cwd = payload["cwd"] as? String ?? ""
        let rawName = URL(fileURLWithPath: cwd).lastPathComponent
        let projectName = aliasProjectName(rawName.isEmpty ? "Session" : rawName)

        // Determine which pill this event belongs to.
        // nm_agent must be lowercase, digits and hyphens, ≤ 24 chars.
        let rawAgent = payload["nm_agent"] as? String ?? ""
        let validAgent = Self.validateAgent(rawAgent)

        let termProgram = payload["term_program"] as? String ?? ""
        let bundleId    = payload["bundle_id"]    as? String ?? ""

        // Routing (HookOrigin):
        // • "codex" → agent_codex (GitHub build only: workspace pill, approvals in the notch)
        // • other valid nm_agent → external pill (fire-and-forget, no approval card)
        // • Cursor bundle ID (its stable Electron one; ToDesktop builds other apps too) → agent_cursor
        // • anything else is Claude Code, from VS Code or from any terminal → integration_claude
        #if !APPSTORE
        let codexEnabled = true
        #else
        let codexEnabled = false
        #endif
        let route = HookOrigin.route(rawAgent: rawAgent, validAgent: validAgent, codexEnabled: codexEnabled, bundleId: bundleId)
        let agentId = HookOrigin.pillId(route)
        let isExternalAgent: Bool
        if case .external = route { isExternalAgent = true } else { isExternalAgent = false }

        // The sidekick reads every event before the pending-approval gate below, so a request that is displaced or declined is still counted (it never answers one).
        Sidekick.shared.feed(payload: payload)
        state.touchPill(agentId)   // the pill's last event: Two cats mode's busiest-other rule reads it
        // A session that stepped back moves on (FocusAware, rule 4). Checked first: the marks' published setter runs on any write, so no write when nothing ends.
        if state.focusMarks.wouldEnd(sessionId: SidekickLedger.sessionKey(payload), event: name, tool: payload["tool_name"] as? String ?? "") {
            state.focusMarks.end(sessionId: SidekickLedger.sessionKey(payload), event: name, tool: payload["tool_name"] as? String ?? "")
        }
        // Which app a terminal session runs in, so the pill's tap brings that app forward (nil for VS Code, whose route is its own).
        if route == .claude { state.noteHost(agentId, session: sessionId, HookOrigin.hostBundleId(rawAgent: rawAgent, termProgram: termProgram, bundleId: bundleId)) }
        // A subagent's start, tools and stop, and the parent's own stop, change this pill's kittens (CatKittenHooks). The parent's cat behaves as it always has.
        if let kitten = CatKittenHooks.event(name: name, payload: payload, now: CACurrentMediaTime() * 1000) { state.kittenEvent(agentId, kitten) }
        let focused = state.focusId == agentId
        // The Projects registry reads every Claude Code event before the gate below (Projects, P-mac): it never answers anything.
        // The --ask hook's ordinary PreToolUse twin keeps a stepped-back question's host, whichever of the two lands first (FocusAware.twinWaitIn).
        let waitIn = FocusAware.twinWaitIn(event: name, tool: payload["tool_name"] as? String ?? "", mark: state.focusMarks.forSession(SidekickLedger.sessionKey(payload), now: FocusAwareApp.now()))
        ProjectsModel.shared.feedFromHook(payload: payload, waitIn: waitIn)

        // While a permission request is pending on this pill (HookOrigin.pendingVerdict): its own session's resolving event dismisses the card, then is processed;
        // its own other events wait; another session's events are processed for that session and leave the card alone (`approvalHeld`).
        var approvalHeld = false
        if let pending = state.pendingApproval, agentId == pending.pillId {
            let verdict = HookOrigin.pendingVerdict(eventName: name, sameSession: sessionId == pending.sessionId,
                                                    sameTool: (payload["tool_name"] as? String ?? "") == pending.tool,
                                                    sameInput: Self.approvalInputKey(payload["tool_input"] as? [String: Any] ?? [:]) == pending.inputKey)
            switch verdict {
            case .resolves: dismissApprovalCard(note: HookOrigin.note(host: pending.host, stillWaiting: false))
            case .passes: approvalHeld = true
            case .holds: return
            }
        }

        switch name {

        case "SessionStart":
            activeSessionId = sessionId
            if isExternalAgent { upsertExternalAgent(id: agentId, name: validAgent!) } else { upsertWorkspaceTask(id: agentId, projectName: projectName, cwd: cwd) }
            state.setFinalLine(id: agentId, nil)
            nbLog("SessionStart \(isExternalAgent ? agentId : projectName) (\(sessionId.prefix(8)))")
            if state.isPresent { expandIfNeeded(to: .overview) }
            SoundEngine.shared.play("work")

        case "UserPromptSubmit":
            activeSessionId = sessionId
            if isExternalAgent { upsertExternalAgent(id: agentId, name: validAgent!) } else { upsertWorkspaceTask(id: agentId, projectName: projectName, cwd: cwd) }
            state.setFinalLine(id: agentId, nil)
            state.updateTask(id: agentId, state: .thinking)
            if let prompt = payload["prompt"] as? String, !prompt.isEmpty {
                appendStep(id: agentId, step: String(prompt.prefix(60)))
            }
            if state.isPresent { expandIfNeeded(to: .overview) }

        case "PreToolUse":
            activeSessionId = sessionId
            let tool = payload["tool_name"] as? String ?? "Tool"
            state.setFinalLine(id: agentId, nil)
            // AskUserQuestion is handled via the dedicated --ask hook.
            // Skip state/step update here to avoid flickering over the question card.
            guard tool != "AskUserQuestion" else { break }
            if isExternalAgent { upsertExternalAgent(id: agentId, name: validAgent!) } else { upsertWorkspaceTask(id: agentId, projectName: projectName, cwd: cwd) }
            // A search tool (web search, web fetch, grep, glob and the Gemini and Codex ones) is "searching"; any other tool is "working".
            state.updateTask(id: agentId, state: BotState(CatRules.toolState(tool)))
            let input = payload["tool_input"] as? [String: Any] ?? [:]
            let step = frenchStep(tool: tool, input: input)
            appendStep(id: agentId, step: step)
            nbLog("PreToolUse \(tool)")

        case "PostToolUse":
            let diffTool = payload["tool_name"] as? String ?? ""
            // The tool that just finished decides: a search tool keeps the cat searching, and the next tool of any other kind puts it back to working.
            state.updateTask(id: agentId, state: BotState(CatRules.toolState(diffTool)))
            // Live diff for Edit / MultiEdit / Write
            let diffInput = payload["tool_input"] as? [String: Any] ?? [:]
            if let diff = buildFileDiff(tool: diffTool, input: diffInput, pillId: agentId) {
                let idx = state.appendSessionDiff(diff, for: agentId)
                let step = String.makeDiffStep(filename: diff.name, added: diff.added, removed: diff.removed, diffId: idx)
                appendStep(id: agentId, step: step)
            }

        case "PostToolUseFailure":
            state.updateTask(id: agentId, state: .working)
            appendStep(id: agentId, step: "⚠ failed")

        case "Notification":
            let message = payload["message"] as? String ?? ""
            let lower = message.lowercased()
            if lower.contains("rate limit") || lower.contains("limite d") {
                state.updateTask(id: agentId, state: .ratelimit)
                SoundEngine.shared.play("rate")
            } else if message.hasSuffix("?") {
                state.updateTask(id: agentId, state: .question)
                appendStep(id: agentId, step: message)
            }

        case "Stop":
            state.updateTask(id: agentId, state: .finished)
            let rawFinal = (payload["last_assistant_message"] as? String)
                ?? (payload["message"] as? String) ?? ""
            let finalText = DiffEngine.toOneLine(rawFinal)
            if !finalText.isEmpty {
                appendStep(id: agentId, step: finalText)
                state.setFinalLine(id: agentId, finalText)
            }
            SoundEngine.shared.play("finish")
            if focused {
                expandIfNeeded(to: .finished)
            } else {
                setPillBadge(id: agentId, badge: .finished)
            }
            scheduleFinishedIdle(agentId: agentId, external: isExternalAgent)

        case "StopFailure":
            state.updateTask(id: agentId, state: .error)
            SoundEngine.shared.play("error")
            if focused {
                expandIfNeeded(to: .error)
            } else {
                setPillBadge(id: agentId, badge: .error)
            }

        case "Interrupt":
            // Codex: user stopped the turn
            activeSessionId = nil
            state.updateTask(id: agentId, state: .idle)
            clearPillBadge(id: agentId)

        case "SessionEnd":
            state.forgetSession(sessionId)       // its host goes with it, even while another session's approval holds the pill
            guard !approvalHeld else { break }   // another session ended: the pill stays, its approval is still waiting
            activeSessionId = nil
            if let idx = state.tasks.firstIndex(where: { $0.id == agentId }) { state.tasks[idx].finalLine = nil }
            state.clearSessionDiffs(for: agentId)
            state.removeTask(id: agentId)

        case "SubagentStart":
            appendStep(id: agentId, step: "+ subagent")

        case "SubagentStop":
            appendStep(id: agentId, step: "• subagent done")

        default:
            break
        }
    }

    /// Per pill, how many finished-to-idle timers were scheduled. Only the latest one acts, so a card's close supersedes the timer a Stop started while the card was up. Not published.
    private var finishedGeneration: [String: Int] = [:]

    /// A finished pill goes idle (an external agent's goes away) 5.2 s later. Not while a card waits on it: the card's close schedules this again for a held finish,
    /// and that newer timer supersedes the earlier one.
    @MainActor
    private func scheduleFinishedIdle(agentId: String, external: Bool) {
        finishedGeneration[agentId, default: 0] += 1
        let generation = finishedGeneration[agentId, default: 0]
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.2) { [weak self] in
            guard let self, HookOrigin.finishedIdleApplies(captured: generation, latest: self.finishedGeneration[agentId, default: 0], cardWaiting: AppState.shared.cardWaiting(on: agentId)) else { return }
            if external {
                AppState.shared.removeTask(id: agentId)
            } else {
                AppState.shared.updateTask(id: agentId, state: .idle)
                self.clearPillBadge(id: agentId)
            }
        }
    }

    // MARK: - Agent validation + dynamic pill

    /// Validates a nm_agent name: lowercase, digits and hyphens, 1–24 chars.
    /// "claude" is reserved and rejected so it cannot impersonate the Claude Code pill.
    /// Returns the name unchanged if valid, nil otherwise.
    private static func validateAgent(_ raw: String) -> String? {
        guard !raw.isEmpty, raw.count <= 24, raw != "claude" else { return nil }
        for scalar in raw.unicodeScalars {
            let v = scalar.value
            let ok = (v >= 0x61 && v <= 0x7A)  // a-z
                  || (v >= 0x30 && v <= 0x39)   // 0-9
                  || v == 0x2D                   // -
            guard ok else { return nil }
        }
        return raw
    }

    /// Creates a dynamic pill for a third-party agent on first event, then no-ops.
    /// ID format: "agent_<name>" — never collides with "integration_*" pills.
    /// Inserted right after integration_claude so it appears in the visible prefix(4).
    @MainActor
    private func upsertExternalAgent(id: String, name: String) {
        let state = AppState.shared
        guard state.tasks.firstIndex(where: { $0.id == id }) == nil else { return }
        // A transient agent's pill is as it always was: its tag, a colour picked by name. A session from the Claude app is Claude Code's (HookOrigin.isDesktop), so it never gets here.
        let task = AgentTask(id: id, name: name, color: IslandConst.colorForProject(name), state: .idle, steps: [], source: .agent)
        if let claudeIdx = state.tasks.firstIndex(where: { $0.id == "integration_claude" }) {
            state.tasks.insert(task, at: claudeIdx + 1)
        } else {
            state.tasks.append(task)
        }
        state.giveCoat(to: id)   // a new agent gets its cat before it is drawn (A cat for each agent mode)
        if state.focusId == nil { state.focusId = id }
        state.syncMode()
    }

    // MARK: - Helpers

    @MainActor
    private func expandIfNeeded(to view: IslandView) {
        let state = AppState.shared
        let isAlert: Bool
        switch view {
        case .approval, .question, .finished, .error, .confused: isAlert = true
        default: isAlert = false
        }
        if state.mode == .expanded {
            // Approval and question always win; other alerts are blocked while a card is showing
            if view == .approval || view == .question {
                state.view = view
            } else if isAlert && state.pendingApproval == nil {
                state.view = view
            }
        } else if isAlert && (view == .approval || view == .question || state.pendingApproval == nil) {
            // Alerts force-expand, but never replace a waiting approval card (as in the expanded branch)
            NotificationCenter.default.post(name: .hookExpand, object: view)
        } else if state.mode == .hidden {
            // Non-alert work events: reveal compact only, never force-expand
            NotificationCenter.default.post(name: .hookReveal, object: nil)
        }
        // Already compact and non-alert: Cat state update is enough, no expand
    }

    // MARK: - Status line (plan gauge)

    @MainActor
    private func processStatusLine(payload: [String: Any]) {
        if let usage = ClaudePlanGauge.parse(payload: payload) {
            AppState.shared.claudePlanUsage = usage
        }
    }

    // MARK: - Permission request (blocking — Claude Code waits for decision)

    @MainActor
    private func processPermissionRequest(fd: Int32, payload: [String: Any]) {
        let state = AppState.shared
        #if !APPSTORE
        // A chat's own Claude Code run asks here too (same hooks). Its card is in that chat, never a pill, and it never
        // touches the one pending approval of the user's own sessions.
        if case .chat(let chatSession) = ClaudeHookRouting.route(payload: payload, live: ClaudeService.shared.liveClaudeSessions) {
            processChatPermission(fd: fd, sessionID: chatSession, payload: payload)
            return
        }
        #endif
        CatSleepClock.shared.agentEvent()
        let sessionId = payload["session_id"] as? String
                     ?? payload["conversation_id"] as? String
                     ?? "unknown"
        let cwd       = payload["cwd"]        as? String ?? ""
        let rawName   = URL(fileURLWithPath: cwd).lastPathComponent
        let projectName = aliasProjectName(rawName.isEmpty ? "Session" : rawName)

        let rawAgent = payload["nm_agent"] as? String ?? ""
        let termProgram = payload["term_program"] as? String ?? ""
        let bundleId    = payload["bundle_id"]    as? String ?? ""

        // Codex gets the same approval card as Claude Code / Cursor (GitHub build only).
        // Other external agents (any other nm_agent) answer immediately with "ask"
        // so the agent re-asks in its own terminal — they do not get a notch card.
        // Claude Code gets its card from VS Code and from any terminal (HookOrigin).
        #if !APPSTORE
        let codexEnabled = true
        #else
        let codexEnabled = false
        #endif
        let route = HookOrigin.route(rawAgent: rawAgent, validAgent: Self.validateAgent(rawAgent), codexEnabled: codexEnabled, bundleId: bundleId)
        // The Projects registry counts the request before it is answered "ask" just below, a Claude App request included (Projects, P-mac).
        // Focus awareness: the session's app is in front, so its own prompt is the place to answer (FocusAwareApp); Projects counts it as "Waiting in <host>".
        let stepped = FocusAwareApp.stepBack(payload: payload, route: route, kind: (payload["tool_name"] as? String) == "AskUserQuestion" ? .question : .permission)
        let waitIn = stepped?.host
        ProjectsModel.shared.feedFromHook(payload: payload, waitIn: waitIn)
        if stepped != nil {   // "ask" at once, no card, no sound
            Task.detached { [weak self] in
                self?.sendLine(fd: fd, text: #"{"permissionDecision":"ask"}"#)
                close(fd)
            }
            return
        }
        // A Claude Code session from the Claude app keeps its approvals in that app: "ask" at once, as a tagged agent's (HookOrigin.answersAskAtOnce).
        if HookOrigin.answersAskAtOnce(route: route, rawAgent: rawAgent) {
            Task.detached { [weak self] in
                self?.sendLine(fd: fd, text: #"{"permissionDecision":"ask"}"#)
                close(fd)
            }
            return
        }

        // Determine which workspace pill owns the request.
        let pillId = HookOrigin.pillId(route)
        let host = HookOrigin.hostName(pillId: pillId, termProgram: termProgram, bundleId: bundleId)
        // The session's app, as processEvent notes it for Claude Code's other events: the pill's tap finds it even when this request is the session's first event.
        if pillId == "integration_claude" { state.noteHost(pillId, session: sessionId, HookOrigin.terminalBundleId(termProgram: termProgram, bundleId: bundleId)) }

        state.touchPill(pillId)
        let tool = payload["tool_name"] as? String ?? "Tool"
        let toolInput = payload["tool_input"] as? [String: Any] ?? [:]
        let inputKey = Self.approvalInputKey(toolInput)
        nbLog("PermissionRequest \(tool) [\(pillId)]")

        // AskUserQuestion is now handled via the dedicated --ask PreToolUse hook.
        // If it still arrives here as a PermissionRequest, reply "ask" so Claude Code
        // re-asks in the terminal — never show the question twice.
        if tool == "AskUserQuestion" {
            Task.detached { [weak self] in
                self?.sendLine(fd: fd, text: #"{"permissionDecision":"ask"}"#)
                close(fd)
            }
            return
        }

        Sidekick.shared.feed(payload: payload)   // before the previous request is displaced
        let command = toolInput["command"] as? String ?? tool

        if pendingApprovalFD >= 0 {
            // Displace the previous request: write "ask" then cancel its source.
            // The cancel handler closes the old fd — never close it directly.
            let old = pendingApprovalFD
            let oldSource = approvalFDSource
            approvalFDSource = nil
            Task.detached { [weak self] in
                // "ask" → nm-hook outputs nothing → Claude Code re-asks
                self?.sendLine(fd: old, text: #"{"permissionDecision":"ask"}"#)
                DispatchQueue.main.async { oldSource?.cancel() }
            }
        }
        pendingApprovalFD = fd
        activeSessionId = sessionId

        upsertWorkspaceTask(id: pillId, projectName: projectName, cwd: cwd, respectsCard: false)
        state.showCardState(id: pillId, state: .approval)
        // The request this one displaces is answered as far as its kitten goes; a request from a subagent makes its kitten wait on this approval.
        resolveApprovalKitten(state.pendingApproval)
        let askedBy = CatKittenHooks.subagentId(payload)
        if let kitten = CatKittenHooks.permission(payload: payload, now: CACurrentMediaTime() * 1000) { state.kittenEvent(pillId, kitten) }
        // The sidekick explains the request in one line and labels how risky it is. It labels only: nothing it says allows or denies anything.
        let why = SidekickExplain.explain(agent: pillId, tool: tool, input: toolInput, cwd: cwd, home: Sidekick.realHome)
        state.pendingApproval = ApprovalInfo(sessionId: sessionId, tool: tool,
                                              command: command, inputKey: inputKey, pillId: pillId, subagentId: askedBy, host: host,
                                              target: why.target, risk: why.risk, line: why.line)
        state.isPinned = true
        SoundEngine.shared.play("approval")

        // Approval always forces the island open — user must be able to respond.
        // Save current focus so we can restore it when the card is dismissed.
        if focusBeforeApproval == nil { focusBeforeApproval = state.focusId }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) { state.focusId = pillId }
        expandIfNeeded(to: .approval)
        // A high-risk request makes the cat jump once, with the emote it already has. Not while the desktop cat is out: its own flight to the notch starts with the same surprise.
        if why.risk == "high", !state.desktopPhase.notchEmpty { NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.surprised) }

        // Monitor fd: if the editor closes the connection (handled externally), dismiss the card.
        // The cancel handler closes the fd — never close it anywhere else.
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in
            guard let self, self.pendingApprovalFD == fd else { return }
            self.dismissApprovalCard(note: HookOrigin.note(host: host, stillWaiting: false))
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        approvalFDSource = source

        // 115s safety timeout — show a note and cancel without sending a decision.
        // nm-hook reads EOF from the cancel handler's close and exits; Claude Code / Codex re-asks.
        let captured = fd
        DispatchQueue.main.asyncAfter(deadline: .now() + 115) { [weak self] in
            guard let self, self.pendingApprovalFD == captured else { return }
            self.dismissApprovalCard(note: HookOrigin.note(host: host, stillWaiting: true))
        }
    }

    /// Called by ApprovalView buttons. Writes the decision to the waiting nm-hook and cleans up.
    @MainActor
    func sendApprovalDecision(_ decision: String) {
        let fd = pendingApprovalFD
        pendingApprovalFD = -1
        // Capture source before nulling — we send the decision first, then cancel the source.
        // The cancel handler closes the fd; never close it directly.
        let source = approvalFDSource
        approvalFDSource = nil

        let json: String
        switch decision {
        case "allow":  json = #"{"permissionDecision":"allow"}"#
        case "always": json = #"{"permissionDecision":"always"}"#
        case "ask":    json = #"{"permissionDecision":"ask"}"#
        default:       json = #"{"permissionDecision":"deny"}"#
        }

        if fd >= 0 {
            Task.detached { [weak self] in
                // Write decision while fd is still valid, then cancel source → cancel handler closes fd
                self?.sendLine(fd: fd, text: json)
                DispatchQueue.main.async { source?.cancel() }
            }
        } else {
            source?.cancel()
        }

        let state = AppState.shared
        let pillId = state.pendingApproval?.pillId ?? "integration_claude"
        if let asked = state.pendingApproval { Sidekick.shared.approvalAnswered(agentId: asked.pillId, sessionId: asked.sessionId) }   // the user's click, for the ledger
        resolveApprovalKitten(state.pendingApproval)
        state.pendingApproval = nil
        state.isPinned = false
        let shown = state.releasePill(id: pillId, fallback: .working)   // the latest state another session asked while the card was up, else working
        if shown == .finished { scheduleFinishedIdle(agentId: pillId, external: false) }   // an approval is never an external agent's
        clearPillBadge(id: pillId)
        // Restore focus to the pill that was focused before the approval card appeared.
        if let prev = focusBeforeApproval {
            focusBeforeApproval = nil
            if state.focusId == pillId, state.tasks.contains(where: { $0.id == prev }) {
                withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) { state.focusId = prev }
            }
        }
        state.view = state.tasks.isEmpty ? .empty : .overview
        #if !APPSTORE
        resurfaceChatApproval()
        #endif
    }

    // MARK: - A chat's own Claude Code run (Agent level)

    #if !APPSTORE
    /// The hook's connection for one waiting request, and what watches it.
    private struct ChatApprovalToken: @unchecked Sendable {
        let fd: Int32
        let source: any DispatchSourceRead
    }
    private var chatApprovals = ChatApprovalQueue<ChatApprovalToken>()
    /// The chat's card pinned the island: only then does the card's going unpin it (a pin the user made stays).
    private var chatApprovalPinned = false

    /// A request from a chat's own run: queued, shown as a card in that chat. Nothing runs without a click. When the
    /// hook is not installed it never gets here, and Claude Code refuses the step.
    @MainActor
    private func processChatPermission(fd: Int32, sessionID: String, payload: [String: Any]) {
        let tool = payload["tool_name"] as? String ?? "Tool"
        // A question cannot be answered in a chat run: hand it back, Claude Code carries on without.
        if tool == "AskUserQuestion" {
            Task.detached { [weak self] in
                self?.sendLine(fd: fd, text: #"{"permissionDecision":"ask"}"#)
                close(fd)
            }
            return
        }
        let input = payload["tool_input"] as? [String: Any] ?? [:]
        let approval = ChatApproval(id: UUID(), sessionID: sessionID, tool: tool,
                                    target: ChatApprovalText.target(tool: tool, input: input))
        // Claude Code gave up (Stop, a crash): the connection closes and the card goes. The cancel handler closes the fd.
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in self?.dropChatApproval(id: approval.id) }
        source.setCancelHandler { close(fd) }
        source.resume()
        chatApprovals.push(approval, token: ChatApprovalToken(fd: fd, source: source))
        showChatApproval()
        // The hook waits 120 s at most: after 115 the card would be lying.
        DispatchQueue.main.asyncAfter(deadline: .now() + 115) { [weak self] in self?.dropChatApproval(id: approval.id) }
    }

    /// Puts the first waiting request on the chat's card (or takes the card away), and brings the chat up for a new one.
    /// The user's own approval or question, if one is waiting, keeps the screen: the chat's card waits behind it.
    @MainActor
    private func showChatApproval() {
        let state = AppState.shared
        let before = state.chatApproval
        if before != chatApprovals.front { state.chatApproval = chatApprovals.front }
        let ownCardWaiting = state.pendingApproval != nil || state.pendingQuestion != nil
        if before == nil, chatApprovals.front != nil {
            SoundEngine.shared.play("approval")
            holdIslandForChatCard(state)
            guard !ownCardWaiting else { return }
            openChatForCard(state)
        } else if chatApprovals.isEmpty, chatApprovalPinned {
            chatApprovalPinned = false
            if !ownCardWaiting { state.isPinned = false }
        }
    }

    /// Pins the island for the chat's card. The card owns the pin only if the island was not pinned before it: a pin
    /// the user made stays theirs, and the card's going does not release it.
    @MainActor
    private func holdIslandForChatCard(_ state: AppState) {
        chatApprovalPinned = !state.isPinned
        state.isPinned = true
    }

    /// Opens the chat on the card (expanded: switch the view; otherwise expand the island to it).
    @MainActor
    private func openChatForCard(_ state: AppState) {
        if state.mode == .expanded {
            state.view = .prompt
        } else {
            NotificationCenter.default.post(name: .hookExpand, object: IslandView.prompt)
        }
    }

    /// The user's own approval or question was just resolved (their paths clear the pin and change the view): a chat
    /// card still queued comes back, pinned and on screen, unless another card of the user's is waiting.
    @MainActor
    private func resurfaceChatApproval() {
        let state = AppState.shared
        guard chatApprovals.front != nil, state.pendingApproval == nil, state.pendingQuestion == nil else { return }
        holdIslandForChatCard(state)
        openChatForCard(state)
    }

    /// Allow or Deny on the chat's card. `id`: the card the click was on; if it is no longer the front card (it was
    /// dropped, and the next one is a step the user has not seen), the click is ignored.
    @MainActor
    func sendChatApprovalDecision(_ decision: String, id: UUID? = nil) {
        if let id, chatApprovals.front?.id != id { return }
        guard let entry = chatApprovals.popFront() else { return }
        let json = decision == "allow" ? #"{"permissionDecision":"allow"}"# : #"{"permissionDecision":"deny"}"#
        let fd = entry.token.fd, source = entry.token.source
        Task.detached { [weak self] in
            self?.sendLine(fd: fd, text: json)
            DispatchQueue.main.async { source.cancel() }
        }
        showChatApproval()
    }

    /// One request gone (its connection closed, or it timed out): no decision is sent, and Claude Code refuses the step.
    @MainActor
    private func dropChatApproval(id: UUID) {
        guard let entry = chatApprovals.remove(id: id) else { return }
        entry.token.source.cancel()
        showChatApproval()
    }

    /// Stop, a new conversation, a level change: every waiting request is handed back (`ask` is a refusal in `-p`).
    @MainActor
    func cancelChatApprovals() {
        for entry in chatApprovals.removeAll() {
            let fd = entry.token.fd, source = entry.token.source
            Task.detached { [weak self] in
                self?.sendLine(fd: fd, text: #"{"permissionDecision":"ask"}"#)
                DispatchQueue.main.async { source.cancel() }
            }
        }
        showChatApproval()
    }

    /// Whether Claude Code's settings carry NotchMeow's `PermissionRequest` hook: Agent mode asks through it.
    static func claudeHooksInstalled() -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: url),
              let settings = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any] else { return false }
        return ClaudeAgentReadiness.hooksInstalled(in: settings)
    }
    #endif

    // MARK: - Question request

    @MainActor
    private func processQuestionRequest(fd: Int32, parsed: AskQuestion, payload: [String: Any]) {
        let state = AppState.shared
        #if !APPSTORE
        // A chat's run cannot be asked a question on the island: Claude Code carries on without.
        if case .chat = ClaudeHookRouting.route(payload: payload, live: ClaudeService.shared.liveClaudeSessions) {
            Task.detached { [weak self] in
                self?.sendLine(fd: fd, text: #"{"permissionDecision":"ask"}"#)
                close(fd)
            }
            return
        }
        #endif
        CatSleepClock.shared.agentEvent()
        let sessionId = payload["session_id"] as? String
                     ?? payload["conversation_id"] as? String
                     ?? "unknown"
        let cwd       = payload["cwd"]        as? String ?? ""
        let rawName   = URL(fileURLWithPath: cwd).lastPathComponent
        let projectName = aliasProjectName(rawName.isEmpty ? "Session" : rawName)

        let rawAgent    = payload["nm_agent"] as? String ?? ""
        let bundleId    = payload["bundle_id"]     as? String ?? ""
        #if !APPSTORE
        let codexEnabled = true
        #else
        let codexEnabled = false
        #endif
        // The question goes to the same pill as the session's other events (HookOrigin): VS Code or any terminal for Claude Code. A tagged agent that is not Codex has
        // no question card (only Claude Code and Codex install the `--ask` hook), so a stray one answers "ask" at once, as a permission request from it does.
        let route = HookOrigin.route(rawAgent: rawAgent, validAgent: Self.validateAgent(rawAgent), codexEnabled: codexEnabled, bundleId: bundleId)
        // The Projects registry counts the question before it is answered "ask" just below, a Claude App question included (Projects, P-mac).
        // Focus awareness: a question from a session whose app is in front is answered in that app (FocusAwareApp), and Projects counts it as "Waiting in <host>".
        let stepped = FocusAwareApp.stepBack(payload: payload, route: route, kind: .question)
        let waitIn = stepped?.host
        ProjectsModel.shared.feedFromHook(payload: payload, waitIn: waitIn)
        if stepped != nil {   // "ask" at once, no card, no sound
            Task.detached { [weak self] in
                self?.sendLine(fd: fd, text: #"{"permissionDecision":"ask"}"#)
                close(fd)
            }
            return
        }
        // A question from the Claude app is answered "ask" at once too (HookOrigin.answersAskAtOnce): the app asks it.
        if HookOrigin.answersAskAtOnce(route: route, rawAgent: rawAgent) {
            Task.detached { [weak self] in
                self?.sendLine(fd: fd, text: #"{"permissionDecision":"ask"}"#)
                close(fd)
            }
            return
        }
        let pillId = HookOrigin.pillId(route)

        Sidekick.shared.feed(payload: payload)
        state.touchPill(pillId)
        // Displace any previous question waiting for an answer.
        if pendingQuestionFD >= 0 {
            let old = pendingQuestionFD
            let oldSrc = questionFDSource
            questionFDSource = nil
            Task.detached { [weak self] in
                self?.sendLine(fd: old, text: #"{"permissionDecision":"ask"}"#)
                DispatchQueue.main.async { oldSrc?.cancel() }
            }
        }
        pendingQuestionFD = fd
        activeSessionId = sessionId
        state.questionPillId = pillId
        state.questionSessionId = sessionId

        upsertWorkspaceTask(id: pillId, projectName: projectName, cwd: cwd)
        state.showCardState(id: pillId, state: .question)
        state.pendingQuestion = parsed
        state.isPinned = true
        SoundEngine.shared.play("approval")

        if focusBeforeQuestion == nil { focusBeforeQuestion = state.focusId }
        withAnimation(.spring(response: 0.5, dampingFraction: 0.72)) { state.focusId = pillId }
        expandIfNeeded(to: .question)

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: .main)
        source.setEventHandler { [weak self] in
            guard let self, self.pendingQuestionFD == fd else { return }
            self.dismissQuestionCard(note: "")
        }
        source.setCancelHandler { close(fd) }
        source.resume()
        questionFDSource = source

        let captured = fd
        DispatchQueue.main.asyncAfter(deadline: .now() + 120) { [weak self] in
            guard let self, self.pendingQuestionFD == captured else { return }
            // Send "ask" so nm-hook exits cleanly; Claude Code re-asks in terminal.
            let askFD = self.pendingQuestionFD
            self.pendingQuestionFD = -1
            let src = self.questionFDSource
            self.questionFDSource = nil
            Task.detached { [weak self] in
                self?.sendLine(fd: askFD, text: #"{"permissionDecision":"ask"}"#)
                DispatchQueue.main.async { src?.cancel() }
            }
            self.dismissQuestionCard(note: "")
        }
    }

    /// Updates or transiently creates a workspace pill (VS Code or Cursor) task.
    /// If the task already exists (persistent), just updates name/cwd.
    /// If missing (transient), creates it and inserts after the main pill.
    @MainActor
    private func upsertWorkspaceTask(id: String, projectName: String, cwd: String = "", respectsCard: Bool = true) {
        let state = AppState.shared
        if let idx = state.tasks.firstIndex(where: { $0.id == id }) {
            // A card on this pill is up: its name is that card's session's project, so another session's event leaves the name and folder alone.
            // A permission request skips this guard: its own card is not up yet, and it renames the pill even over the card it displaces.
            guard !respectsCard || state.pendingApproval?.pillId != id else { return }
            state.tasks[idx].name = projectName
            if !cwd.isEmpty { state.tasks[idx].sessionCwd = cwd }
            return
        }
        // Transient: create and insert after the main pill
        let def = PillCatalog.definition(for: id)
        let color = def?.color ?? "#C0C4CC"
        let source = def?.source ?? .agent
        let task = AgentTask(id: id, name: projectName, color: color,
                             state: .idle, steps: [], source: source, isIntegration: true)
        if let mainIdx = state.tasks.firstIndex(where: { $0.id == state.mainPillId }) {
            state.tasks.insert(task, at: mainIdx + 1)
        } else {
            state.tasks.insert(task, at: 0)
        }
        state.giveCoat(to: id)
        if state.focusId == nil { state.focusId = id }
        state.syncMode()
    }

    // MARK: - Badge helpers

    @MainActor
    private func setPillBadge(id: String, badge: PillBadge) {
        let state = AppState.shared
        guard let idx = state.tasks.firstIndex(where: { $0.id == id }) else { return }
        state.tasks[idx].pillBadge = badge
    }

    @MainActor
    private func clearPillBadge(id: String) {
        let state = AppState.shared
        guard let idx = state.tasks.firstIndex(where: { $0.id == id }) else { return }
        state.tasks[idx].pillBadge = nil
    }

    @MainActor
    private func appendStep(id: String, step: String) {
        let state = AppState.shared
        guard let idx = state.tasks.firstIndex(where: { $0.id == id }) else { return }
        state.tasks[idx].steps.append(step)
        if state.tasks[idx].steps.count > 20 { state.tasks[idx].steps.removeFirst() }
        state.tasks[idx].stepIndex = state.tasks[idx].steps.count - 1
    }

    // MARK: - Project name alias mapping

    private func aliasProjectName(_ name: String) -> String {
        let aliases: [String: String] = [
            "notch-buddy":  "Notch Buddy",
            "notchbuddy":   "Notch Buddy",
            "notch_buddy":  "Notch Buddy",
        ]
        return aliases[name.lowercased()] ?? name
    }

    // MARK: - Step labels

    private func frenchStep(tool: String, input: [String: Any]) -> String {
        SessionStepText.line(tool: tool, input: input)
    }

    // MARK: - Live diff helpers

    @MainActor
    private func buildFileDiff(tool: String, input: [String: Any], pillId: String) -> FileDiff? {
        switch tool {
        case "Edit":
            guard let old = input["old_string"] as? String,
                  let new = input["new_string"] as? String,
                  let path = input["file_path"] as? String,
                  !old.isEmpty || !new.isEmpty else { return nil }
            let d = DiffEngine.fromEdit(old: old, new: new, path: path)
            return (d.added > 0 || d.removed > 0) ? d : nil

        case "MultiEdit":
            guard let path = input["file_path"] as? String,
                  let edits = input["edits"] as? [[String: Any]], !edits.isEmpty else { return nil }
            var totalAdded = 0, totalRemoved = 0, allHunks: [DiffHunk] = [], anyLarge = false
            for edit in edits {
                guard let old = edit["old_string"] as? String,
                      let new = edit["new_string"] as? String else { continue }
                let d = DiffEngine.fromEdit(old: old, new: new, path: path)
                totalAdded += d.added; totalRemoved += d.removed
                allHunks.append(contentsOf: d.hunks); if d.tooLarge { anyLarge = true }
            }
            guard totalAdded > 0 || totalRemoved > 0 else { return nil }
            return FileDiff(path: path, added: totalAdded, removed: totalRemoved,
                            hunks: allHunks, tooLarge: anyLarge, isNewFile: false)

        case "Write":
            guard let path = input["file_path"] as? String,
                  let content = input["content"] as? String, !content.isEmpty else { return nil }
            let d = DiffEngine.fromNew(content: content, path: path)
            return (d.added > 0 || d.removed > 0) ? d : nil

        default:
            return nil
        }
    }

    // MARK: - Logging

    private func nbLog(_ message: String) {
        appendAppLog("nm.log", message)
    }

    private func sendLine(fd: Int32, text: String) {
        let bytes = Array((text + "\n").utf8)
        bytes.withUnsafeBytes { buffer in
            var sent = 0
            while sent < buffer.count {
                let n = Darwin.send(fd, buffer.baseAddress! + sent, buffer.count - sent, 0)
                if n <= 0 { break }
                sent += n
            }
        }
    }

    // MARK: - nm-hook script installation

    func installHookScript() {
        #if APPSTORE
        // In App Store mode the script is written during settings hook installation
        // (requires NSOpenPanel to ~/.claude chosen by the user)
        #else
        let dir = Self.supportDir
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        try? FileManager.default.setAttributes([.posixPermissions: 0o700 as NSNumber], ofItemAtPath: dir.path)
        // nm-hook: shell wrapper (always exits 0, calls nm-hook.py via python3)
        let wrapperURL = URL(fileURLWithPath: Self.hookScriptPath)
        try? nbHookShellWrapper.write(to: wrapperURL, atomically: true, encoding: .utf8)
        _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755 as NSNumber], ofItemAtPath: wrapperURL.path)
        // nm-hook.py: Python relay
        let pyURL = wrapperURL.deletingLastPathComponent().appendingPathComponent("nm-hook.py")
        try? nbHookPythonGitHub.write(to: pyURL, atomically: true, encoding: .utf8)
        _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755 as NSNumber], ofItemAtPath: pyURL.path)
        #endif
    }

    // MARK: - Outdated hook detection

    /// Returns true if settings.json has a NotchMeow hook that needs updating:
    /// either a PermissionRequest hook with timeout < 120s, or the AskUserQuestion
    /// PreToolUse matcher is missing (requires Claude Code 2.1.85+).
    static func hooksNeedUpdate() -> Bool {
        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: settingsURL),
              let settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = settings["hooks"] as? [String: Any] else {
            return false
        }
        // Track whether any NotchMeow hook is installed at all
        var hasNotchMeowHooks = false

        if let permReqHooks = hooks["PermissionRequest"] as? [[String: Any]] {
            for matcher in permReqHooks {
                if let hookList = matcher["hooks"] as? [[String: Any]] {
                    for hook in hookList {
                        if let cmd = hook["command"] as? String,
                           cmd.contains("NotchMeow") || cmd.contains("notchmeow") {
                            hasNotchMeowHooks = true
                            if let timeout = hook["timeout"] as? Int, timeout < 120 { return true }
                        }
                    }
                }
            }
        }

        // Check that the AskUserQuestion PreToolUse entry exists
        if hasNotchMeowHooks {
            let preToolHooks = hooks["PreToolUse"] as? [[String: Any]] ?? []
            let hasAskEntry = preToolHooks.contains { m in
                (m["matcher"] as? String) == "AskUserQuestion"
                && (m["hooks"] as? [[String: Any]])?.contains {
                    let cmd = $0["command"] as? String ?? ""
                    return cmd.contains("NotchMeow") || cmd.contains("notchmeow")
                } ?? false
            }
            if !hasAskEntry { return true }
        }
        return false
    }

    // MARK: - Claude Code settings.json hook installer

    private var _pendingHooksData: Data?

    /// Confirm without a preview behind it (the preview was cleared, or built by another window): the writers say so instead of returning as if they had written.
    private static let noPreview = NSError(domain: "NotchMeow", code: 4, userInfo: [
        NSLocalizedDescriptionKey: "There is nothing to write: click Install hooks (or Install relay) again to build the preview first."
    ])

    /// Returns preview JSON without writing — call writeClaudeHooks() to confirm.
    func previewClaudeHooks() throws -> String {
        let data = try buildHooksData()
        _pendingHooksData = data
        return String(data: data, encoding: .utf8) ?? ""
    }

    /// Writes the hooks to disk (call after user confirms preview). Returns the dated backup's file name (nil when there was no settings.json to back up). Throws when there is no preview, or when the backup
    /// or the write fails: the caller shows it, and nothing is claimed.
    func writeClaudeHooks() throws -> String? {
        guard let data = _pendingHooksData else { throw Self.noPreview }
        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        let backup = try ConfigFileWrite.writeWithBackup(data, to: settingsURL, suffix: "settings.json")
        _pendingHooksData = nil
        return backup
    }

    private func buildHooksData() throws -> Data {
        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        // A settings.json that is there but does not parse is refused, never rebuilt from nothing (that would drop the user's other settings).
        var settings = try ConfigFileWrite.readObject(at: settingsURL, label: "~/.claude/settings.json")
        let hookPath = Self.hookScriptPath
        #if APPSTORE
        // Sandboxed apps create quarantined files; /bin/sh bypasses the quarantine flag
        let quotedCmd = "/bin/sh \"\(hookPath.replacingOccurrences(of: "\"", with: "\\\""))\""
        #else
        let quotedCmd = "\"\(hookPath.replacingOccurrences(of: "\"", with: "\\\""))\""
        #endif
        let events: [(String, Int)] = [
            ("SessionStart", 10), ("SessionEnd", 10),
            ("UserPromptSubmit", 10),
            ("PreToolUse", 10), ("PostToolUse", 10), ("PostToolUseFailure", 10),
            ("PermissionRequest", 120),
            ("Notification", 10),
            ("Stop", 10), ("StopFailure", 10),
            ("SubagentStart", 10), ("SubagentStop", 10),
        ]
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for (event, timeout) in events {
            var existing = hooks[event] as? [[String: Any]] ?? []
            existing.removeAll { ($0["hooks"] as? [[String: Any]])?.contains { ($0["command"] as? String)?.contains("NotchMeow") == true || ($0["command"] as? String)?.contains("notchmeow") == true } ?? false }
            existing.append(["hooks": [["type": "command", "command": quotedCmd, "timeout": timeout]]])
            hooks[event] = existing
        }
        // Dedicated AskUserQuestion PreToolUse hook (Claude Code 2.1.85+, timeout 130s)
        var preToolUse = hooks["PreToolUse"] as? [[String: Any]] ?? []
        preToolUse.append([
            "matcher": "AskUserQuestion",
            "hooks": [["type": "command", "command": "\(quotedCmd) --ask", "timeout": 130]],
        ])
        hooks["PreToolUse"] = preToolUse
        settings["hooks"] = hooks
        return try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
    }

    /// Removes NotchMeow's hooks from settings.json. Returns false when there was nothing of ours to remove (the file is then left alone), true after a write.
    func uninstallClaudeHooks() throws -> Bool {
        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        var settings = try ConfigFileWrite.readObject(at: settingsURL, label: "~/.claude/settings.json")
        guard var hooks = settings["hooks"] as? [String: Any] else { return false }
        let before = hooks.mapValues { ($0 as? [[String: Any]])?.count ?? 0 }

        for key in hooks.keys {
            if var matchers = hooks[key] as? [[String: Any]] {
                matchers.removeAll { matcher in
                    (matcher["hooks"] as? [[String: Any]])?.contains {
                        ($0["command"] as? String)?.contains("NotchMeow") == true ||
                        ($0["command"] as? String)?.contains("notchmeow") == true
                    } ?? false
                }
                if matchers.isEmpty { hooks.removeValue(forKey: key) }
                else { hooks[key] = matchers }
            }
        }
        guard hooks.mapValues({ ($0 as? [[String: Any]])?.count ?? 0 }) != before else { return false }
        settings["hooks"] = hooks
        let newData = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try ConfigFileWrite.write(newData, to: settingsURL)
        return true
    }

    // MARK: - Claude plan status line installer

    private var statusLinePreviousURL: URL {
        Self.supportDir.appendingPathComponent("statusline-previous.json")
    }

    /// Returns true if our statusLine command is installed in ~/.claude/settings.json.
    static func statusLineInstalled() -> Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: url),
              let settings = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let sl = settings["statusLine"] as? [String: Any],
              let cmd = sl["command"] as? String else { return false }
        return cmd.contains("nm-hook")
    }

    private var _pendingStatusLineData: Data?
    private var _pendingPreviousData: Data?
    private var _pendingDeletePrevious: Bool = false

    /// Returns a diff string (only the statusLine key: before → after) without writing anything.
    func previewStatusLine(install: Bool) throws -> String {
        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        let settings = try ConfigFileWrite.readObject(at: settingsURL, label: "~/.claude/settings.json")
        let hookPath = Self.hookScriptPath
        let quotedPath = hookPath.replacingOccurrences(of: "\"", with: "\\\"")
        let quotedCmd = "\"\(quotedPath)\" --statusline"

        // Reset pending side-effects
        _pendingPreviousData = nil
        _pendingDeletePrevious = false

        let oldSL = settings["statusLine"] as? [String: Any]
        let newSL: [String: Any]?

        if install {
            // Check that Python 3 is available (requires Command Line Tools)
            let clCheck = Process()
            clCheck.executableURL = URL(fileURLWithPath: "/usr/bin/xcode-select")
            clCheck.arguments = ["-p"]
            clCheck.standardOutput = FileHandle.nullDevice
            clCheck.standardError = FileHandle.nullDevice
            try? clCheck.run()
            clCheck.waitUntilExit()
            if clCheck.terminationStatus != 0 {
                throw NSError(domain: "NotchMeow", code: 1,
                              userInfo: [NSLocalizedDescriptionKey:
                                  "Command Line Tools are required but not installed. Run: xcode-select --install"])
            }

            if let existing = oldSL,
               let cmd = existing["command"] as? String, !cmd.contains("nm-hook") {
                // Keep existing object but swap command; save old for later restoration
                var updated = existing
                updated["command"] = quotedCmd
                newSL = updated
                _pendingPreviousData = try? JSONSerialization.data(withJSONObject: existing,
                                                                   options: [.prettyPrinted, .sortedKeys])
            } else if let existing = oldSL,
                      let cmd = existing["command"] as? String, cmd.contains("nm-hook") {
                // Already installed — rebuild to update path if needed, keep other fields
                var updated = existing
                updated["command"] = quotedCmd
                newSL = updated
            } else {
                newSL = ["type": "command", "command": quotedCmd]
            }
        } else {
            // Uninstall: only if it's ours
            if let cur = oldSL, let cmd = cur["command"] as? String, cmd.contains("nm-hook") {
                if let prevData = try? Data(contentsOf: statusLinePreviousURL),
                   let prevObj = (try? JSONSerialization.jsonObject(with: prevData)) as? [String: Any] {
                    newSL = prevObj
                    _pendingDeletePrevious = true
                } else {
                    newSL = nil
                }
            } else {
                newSL = oldSL  // not ours — leave unchanged
            }
        }

        // Build the full settings.json with the new statusLine
        var newSettings = settings
        if let sl = newSL {
            newSettings["statusLine"] = sl
        } else {
            newSettings.removeValue(forKey: "statusLine")
        }
        let data = try JSONSerialization.data(withJSONObject: newSettings,
                                              options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        _pendingStatusLineData = data

        // Build a compact diff: show only the statusLine key before → after
        func slJSON(_ val: [String: Any]?) throws -> String {
            guard let v = val else { return "(none)" }
            let d = try JSONSerialization.data(withJSONObject: v, options: [.prettyPrinted, .sortedKeys])
            return String(data: d, encoding: .utf8) ?? "(none)"
        }
        let before = try slJSON(oldSL)
        let after  = try slJSON(newSL)
        return "statusLine\nBefore:\n\(before)\n\nAfter:\n\(after)"
    }

    /// Writes settings.json and commits side effects (call after user confirms). Returns the dated backup's file name (nil when there was no settings.json); throws like `writeClaudeHooks`.
    func writeStatusLine() throws -> String? {
        guard let data = _pendingStatusLineData else { throw Self.noPreview }
        let settingsURL = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        let backup = try ConfigFileWrite.writeWithBackup(data, to: settingsURL, suffix: "settings.json")
        // Commit side effects only after successful write
        if let prevData = _pendingPreviousData {
            try? prevData.write(to: statusLinePreviousURL, options: .atomic)
        }
        if _pendingDeletePrevious {
            try? FileManager.default.removeItem(at: statusLinePreviousURL)
        }
        _pendingStatusLineData = nil
        _pendingPreviousData = nil
        _pendingDeletePrevious = false
        return backup
    }

    // MARK: - App Store: hooks via security-scoped bookmark

    #if APPSTORE
    /// Writes nm-hook script and updates settings.json in one shot.
    /// claudeURL must be a URL from NSOpenPanel (sandbox access is granted immediately — no security scope needed).
    func installAndWriteClaudeHooksAppStore(claudeURL: URL) throws {
        let data = try buildHooksData(claudeURL: claudeURL)

        // Write nm-hook (shell wrapper) + nm-hook.py (Python relay) into ~/.claude/notchmeow/
        let notchmeowDir = claudeURL.appendingPathComponent("notchmeow")
        try FileManager.default.createDirectory(at: notchmeowDir, withIntermediateDirectories: true)
        let wrapperURL = notchmeowDir.appendingPathComponent("nm-hook")
        try nbHookShellWrapper.write(to: wrapperURL, atomically: true, encoding: .utf8)
        _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755 as NSNumber], ofItemAtPath: wrapperURL.path)
        let pyURL = notchmeowDir.appendingPathComponent("nm-hook.py")
        try nbHookPythonAppStore.write(to: pyURL, atomically: true, encoding: .utf8)
        _ = try? FileManager.default.setAttributes([.posixPermissions: 0o755 as NSNumber], ofItemAtPath: pyURL.path)

        // Write settings.json (with backup)
        let settingsURL = claudeURL.appendingPathComponent("settings.json")
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyyMMdd-HHmm"
        let backupURL = claudeURL.appendingPathComponent("settings.json.bak-\(formatter.string(from: Date()))")
        try? FileManager.default.copyItem(at: settingsURL, to: backupURL)
        try data.write(to: settingsURL, options: .atomic)
        UserDefaults.standard.set(true, forKey: "notchmeowHooksInstalled")
    }

    func uninstallClaudeHooksAppStore(claudeURL: URL) throws {
        let settingsURL = claudeURL.appendingPathComponent("settings.json")
        guard let data = try? Data(contentsOf: settingsURL),
              var settings = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              var hooks = settings["hooks"] as? [String: Any] else { return }
        for key in hooks.keys {
            if var matchers = hooks[key] as? [[String: Any]] {
                matchers.removeAll { matcher in
                    (matcher["hooks"] as? [[String: Any]])?.contains {
                        ($0["command"] as? String)?.contains("notchmeow") == true ||
                        ($0["command"] as? String)?.contains("NotchMeow") == true
                    } ?? false
                }
                if matchers.isEmpty { hooks.removeValue(forKey: key) }
                else { hooks[key] = matchers }
            }
        }
        settings["hooks"] = hooks
        let newData = try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
        try newData.write(to: settingsURL, options: .atomic)
        UserDefaults.standard.set(false, forKey: "notchmeowHooksInstalled")
    }

    private func buildHooksData(claudeURL: URL) throws -> Data {
        let settingsURL = claudeURL.appendingPathComponent("settings.json")
        var settings = try ConfigFileWrite.readObject(at: settingsURL, label: "~/.claude/settings.json")   // one that does not parse is refused, not rebuilt from nothing
        // Derive hook path from the panel-selected claudeURL (real ~/.claude, not container)
        let hookPath = claudeURL.appendingPathComponent("notchmeow/nm-hook").path
        let quotedCmd = "/bin/sh \"\(hookPath.replacingOccurrences(of: "\"", with: "\\\""))\""
        let events: [(String, Int)] = [
            ("SessionStart", 10), ("SessionEnd", 10),
            ("UserPromptSubmit", 10),
            ("PreToolUse", 10), ("PostToolUse", 10), ("PostToolUseFailure", 10),
            ("PermissionRequest", 120),
            ("Notification", 10),
            ("Stop", 10), ("StopFailure", 10),
            ("SubagentStart", 10), ("SubagentStop", 10),
        ]
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for (event, timeout) in events {
            var existing = hooks[event] as? [[String: Any]] ?? []
            existing.removeAll { ($0["hooks"] as? [[String: Any]])?.contains {
                ($0["command"] as? String)?.contains("notchmeow") == true ||
                ($0["command"] as? String)?.contains("NotchMeow") == true
            } ?? false }
            existing.append(["hooks": [["type": "command", "command": quotedCmd, "timeout": timeout]]])
            hooks[event] = existing
        }
        // Dedicated AskUserQuestion PreToolUse hook (Claude Code 2.1.85+, timeout 130s)
        var preToolUse = hooks["PreToolUse"] as? [[String: Any]] ?? []
        preToolUse.append([
            "matcher": "AskUserQuestion",
            "hooks": [["type": "command", "command": "\(quotedCmd) --ask", "timeout": 130]],
        ])
        hooks["PreToolUse"] = preToolUse
        settings["hooks"] = hooks
        return try JSONSerialization.data(withJSONObject: settings, options: [.prettyPrinted, .sortedKeys])
    }
    #endif

    // MARK: - Gemini CLI and Antigravity hook installers  (#if !APPSTORE only)

    #if !APPSTORE
    private static var geminiSettingsURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/settings.json")
    }
    private static var agyHooksURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".gemini/config/hooks.json")
    }

    // MARK: Installed-state detection

    static func geminiHooksInstalled() -> Bool {
        guard let data = try? Data(contentsOf: geminiSettingsURL),
              let settings = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let hooks = settings["hooks"] as? [String: Any] else { return false }
        for value in hooks.values {
            guard let groups = value as? [[String: Any]] else { continue }
            for group in groups {
                if let innerHooks = group["hooks"] as? [[String: Any]] {
                    for hook in innerHooks {
                        if let cmd = hook["command"] as? String,
                           cmd.contains("nm-hook"), cmd.contains("--agent gemini") { return true }
                    }
                }
                // Legacy flat entry
                if let cmd = group["command"] as? String,
                   cmd.contains("nm-hook"), cmd.contains("--agent gemini") { return true }
            }
        }
        return false
    }

    static func agyHooksInstalled() -> Bool {
        guard let data = try? Data(contentsOf: agyHooksURL),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let notchmeow = root["notchmeow"] else { return false }
        let json = (try? JSONSerialization.data(withJSONObject: notchmeow))
            .flatMap { String(data: $0, encoding: .utf8) } ?? ""
        return json.contains("nm-hook")
    }

    // MARK: Gemini CLI – preview / write

    private var _pendingGeminiData: Data?
    private var _pendingGeminiFingerprint: String?

    func previewGeminiHooks(install: Bool) throws -> String {
        let url = Self.geminiSettingsURL
        let exists = FileManager.default.fileExists(atPath: url.path)
        if !install && !exists {
            throw NSError(domain: "NotchMeowNoop", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "No Gemini CLI hooks to remove."
            ])
        }
        let current = exists ? try Data(contentsOf: url) : Data()
        _pendingGeminiFingerprint = sha256Hex(current)
        let newData = install ? try buildGeminiHooksData() : try withoutGeminiHooks()
        _pendingGeminiData = newData
        return String(data: newData, encoding: .utf8) ?? ""
    }

    func writeGeminiHooks() throws {
        guard let data = _pendingGeminiData, let fp = _pendingGeminiFingerprint else { return }
        let url = Self.geminiSettingsURL
        let current = (try? Data(contentsOf: url)) ?? Data()
        guard sha256Hex(current) == fp else {
            throw NSError(domain: "NotchMeow", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "~/.gemini/settings.json changed since preview. Refresh and try again."
            ])
        }
        try writeJSONFile(data, to: url, suffix: "settings.json")
        _pendingGeminiData = nil
        _pendingGeminiFingerprint = nil
    }

    private func buildGeminiHooksData() throws -> Data {
        var settings = try Self.strictReadJSONObject(at: Self.geminiSettingsURL,
                                                     label: "~/.gemini/settings.json")
        if let raw = settings["hooks"], !(raw is [String: Any]) {
            throw NSError(domain: "NotchMeow", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "~/.gemini/settings.json: \"hooks\" has an unexpected type — NotchMeow has not touched it."
            ])
        }
        let base = hookBase()
        // (Gemini event key, normalized event name passed via argv, timeout in ms)
        let events: [(String, String, Int)] = [
            ("SessionStart", "SessionStart", 10000),
            ("SessionEnd",   "SessionEnd",   10000),
            ("BeforeTool",   "PreToolUse",   5000),
            ("AfterTool",    "PostToolUse",  5000),
            ("BeforeAgent",  "UserPromptSubmit", 5000),
            ("AfterAgent",   "Stop",         5000),
        ]
        var hooks = settings["hooks"] as? [String: Any] ?? [:]
        for (geminiEvent, normalizedEvent, timeout) in events {
            if let raw = hooks[geminiEvent], !(raw is [[String: Any]]) {
                throw NSError(domain: "NotchMeow", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "~/.gemini/settings.json: \"hooks\"[\"\(geminiEvent)\"] has an unexpected type — NotchMeow has not touched it."
                ])
            }
            var groups = hooks[geminiEvent] as? [[String: Any]] ?? []
            // Remove legacy flat entries and groups whose inner hooks contain nm-hook
            groups = removeNbHookEntries(from: groups)
            let hookEntry: [String: Any] = [
                "type": "command",
                "command": "\(base) --agent gemini \(normalizedEvent)",
                "timeout": timeout,
            ]
            groups.append(["matcher": "*", "hooks": [hookEntry]])
            hooks[geminiEvent] = groups
        }
        settings["hooks"] = hooks
        return try JSONSerialization.data(withJSONObject: settings,
                                         options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    private func withoutGeminiHooks() throws -> Data {
        var settings = try Self.strictReadJSONObject(at: Self.geminiSettingsURL,
                                                     label: "~/.gemini/settings.json")
        if let raw = settings["hooks"], !(raw is [String: Any]) {
            throw NSError(domain: "NotchMeow", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "~/.gemini/settings.json: \"hooks\" has an unexpected type — NotchMeow has not touched it."
            ])
        }
        if var hooks = settings["hooks"] as? [String: Any] {
            for key in hooks.keys {
                if let groups = hooks[key] as? [[String: Any]] {
                    let cleaned = removeNbHookEntries(from: groups)
                    if cleaned.isEmpty { hooks.removeValue(forKey: key) } else { hooks[key] = cleaned }
                }
            }
            if hooks.isEmpty { settings.removeValue(forKey: "hooks") } else { settings["hooks"] = hooks }
        }
        return try JSONSerialization.data(withJSONObject: settings,
                                         options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    // MARK: Antigravity – preview / write

    private var _pendingAgyData: Data?
    private var _pendingAgyFingerprint: String?

    func previewAgyHooks(install: Bool) throws -> String {
        let url = Self.agyHooksURL
        let exists = FileManager.default.fileExists(atPath: url.path)
        if !install && !exists {
            throw NSError(domain: "NotchMeowNoop", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "No Antigravity hooks to remove."
            ])
        }
        let current = exists ? try Data(contentsOf: url) : Data()
        _pendingAgyFingerprint = sha256Hex(current)
        let newData = install ? try buildAgyHooksData() : try withoutAgyHooks()
        _pendingAgyData = newData
        return String(data: newData, encoding: .utf8) ?? ""
    }

    func writeAgyHooks() throws {
        guard let data = _pendingAgyData, let fp = _pendingAgyFingerprint else { return }
        let url = Self.agyHooksURL
        let current = (try? Data(contentsOf: url)) ?? Data()
        guard sha256Hex(current) == fp else {
            throw NSError(domain: "NotchMeow", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "~/.gemini/config/hooks.json changed since preview. Refresh and try again."
            ])
        }
        try writeJSONFile(data, to: url, suffix: "hooks.json")
        _pendingAgyData = nil
        _pendingAgyFingerprint = nil
    }

    private func buildAgyHooksData() throws -> Data {
        var root = try Self.strictReadJSONObject(at: Self.agyHooksURL,
                                                 label: "~/.gemini/config/hooks.json")
        let base = hookBase()
        // PreToolUse / PostToolUse: tool-level hooks — use matcher group
        // PreInvocation / PostInvocation / Stop: lifecycle hooks — direct handler, no matcher
        var notchmeow: [String: Any] = [:]
        for event in ["PreToolUse", "PostToolUse"] {
            let hook: [String: Any] = ["type": "command",
                                       "command": "\(base) --agent antigravity \(event)",
                                       "timeout": 10]
            notchmeow[event] = [["matcher": "*", "hooks": [hook]]]
        }
        for event in ["PreInvocation", "PostInvocation", "Stop"] {
            let hook: [String: Any] = ["type": "command",
                                       "command": "\(base) --agent antigravity \(event)",
                                       "timeout": 10]
            notchmeow[event] = [hook]
        }
        root["notchmeow"] = notchmeow
        return try JSONSerialization.data(withJSONObject: root,
                                         options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    private func withoutAgyHooks() throws -> Data {
        var root = try Self.strictReadJSONObject(at: Self.agyHooksURL,
                                                 label: "~/.gemini/config/hooks.json")
        root.removeValue(forKey: "notchmeow")
        return try JSONSerialization.data(withJSONObject: root,
                                         options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    // MARK: Shared helpers

    /// /bin/sh "<hookScriptPath>" — quoted for paths containing spaces (Application Support).
    private func hookBase() -> String {
        let path = Self.hookScriptPath.replacingOccurrences(of: "\"", with: "\\\"")
        return "/bin/sh \"\(path)\""
    }

    /// Reads a JSON object from url.
    /// Absent file → empty dict. Present but invalid → throws with a user-facing message.
    private static func strictReadJSONObject(at url: URL, label: String) throws -> [String: Any] {
        try ConfigFileWrite.readObject(at: url, label: label)
    }

    /// Backs up the existing file (throws on failure), creates parent dirs, then atomically writes. A symbolic link stays a link: the backup holds the text of the file it points at, and the write goes to
    /// that file and keeps its permissions (`ConfigFileWrite`).
    private func writeJSONFile(_ data: Data, to url: URL, suffix: String) throws {
        try ConfigFileWrite.writeWithBackup(data, to: url, suffix: suffix)
    }

    /// Removes entries containing "nm-hook" from a Gemini-format groups array.
    /// Handles both new group format (matcher + hooks[]) and legacy flat format (command at top level).
    /// Returns the cleaned array; empty groups (after inner-hook removal) are dropped.
    private func removeNbHookEntries(from groups: [[String: Any]]) -> [[String: Any]] {
        groups.compactMap { group -> [String: Any]? in
            // Legacy flat entry — command at group level
            if let cmd = group["command"] as? String, cmd.contains("nm-hook") { return nil }
            // Group format — filter inner hooks
            if var innerHooks = group["hooks"] as? [[String: Any]] {
                innerHooks.removeAll { ($0["command"] as? String)?.contains("nm-hook") == true }
                if innerHooks.isEmpty { return nil }
                var updated = group
                updated["hooks"] = innerHooks
                return updated
            }
            return group
        }
    }

    // MARK: - Codex hook installer  (#if !APPSTORE only)

    static var codexHooksURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".codex/hooks.json")
    }

    /// True when ~/.codex/hooks.json already routes Codex events to NotchMeow's nm-hook.
    static func codexHooksInstalled() -> Bool {
        guard let data = try? Data(contentsOf: codexHooksURL),
              let root = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              let hooks = root["hooks"] as? [String: Any] else { return false }
        for value in hooks.values {
            guard let groups = value as? [[String: Any]] else { continue }
            for group in groups {
                if let innerHooks = group["hooks"] as? [[String: Any]] {
                    for hook in innerHooks {
                        if let cmd = hook["command"] as? String,
                           cmd.contains("nm-hook"), cmd.contains("--agent codex") { return true }
                    }
                }
            }
        }
        return false
    }

    private var _pendingCodexData: Data?
    private var _pendingCodexFingerprint: String?

    func previewCodexHooks(install: Bool) throws -> String {
        let url = Self.codexHooksURL
        let exists = FileManager.default.fileExists(atPath: url.path)
        if !install && !exists {
            throw NSError(domain: "NotchMeowNoop", code: 0, userInfo: [
                NSLocalizedDescriptionKey: "No Codex hooks to remove."
            ])
        }
        let current = exists ? try Data(contentsOf: url) : Data()
        _pendingCodexFingerprint = sha256Hex(current)
        let newData = install ? try buildCodexHooksData() : try withoutCodexHooks()
        _pendingCodexData = newData
        return String(data: newData, encoding: .utf8) ?? ""
    }

    func writeCodexHooks() throws {
        guard let data = _pendingCodexData, let fp = _pendingCodexFingerprint else { return }
        let url = Self.codexHooksURL
        let current = (try? Data(contentsOf: url)) ?? Data()
        guard sha256Hex(current) == fp else {
            throw NSError(domain: "NotchMeow", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "~/.codex/hooks.json changed since preview. Refresh and try again."
            ])
        }
        try writeJSONFile(data, to: url, suffix: "hooks.json")
        _pendingCodexData = nil
        _pendingCodexFingerprint = nil
    }

    private func buildCodexHooksData() throws -> Data {
        var root = try Self.strictReadJSONObject(at: Self.codexHooksURL, label: "~/.codex/hooks.json")
        if let raw = root["hooks"], !(raw is [String: Any]) {
            throw NSError(domain: "NotchMeow", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "~/.codex/hooks.json: \"hooks\" has an unexpected type — NotchMeow has not touched it."
            ])
        }
        let base = hookBase()
        // Events, timeouts in seconds (Codex format).
        // PermissionRequest uses 120s + a statusMessage shown in the Codex UI while waiting.
        let events: [(String, Int, String?)] = [
            ("SessionStart",    10,  nil),
            ("UserPromptSubmit", 10, nil),
            ("PreToolUse",      10,  nil),
            ("PermissionRequest", 120, "Waiting for your answer in the notch (NotchMeow)"),
            ("PostToolUse",     10,  nil),
            ("Stop",            10,  nil),
            ("SubagentStart",   10,  nil),
            ("SubagentStop",    10,  nil),
            ("Interrupt",        3,  nil),
            ("SessionEnd",       3,  nil),
        ]
        var hooks = root["hooks"] as? [String: Any] ?? [:]
        for (event, timeout, statusMsg) in events {
            if let raw = hooks[event], !(raw is [[String: Any]]) {
                throw NSError(domain: "NotchMeow", code: 2, userInfo: [
                    NSLocalizedDescriptionKey: "~/.codex/hooks.json: \"hooks\"[\"\(event)\"] has an unexpected type — NotchMeow has not touched it."
                ])
            }
            var groups = hooks[event] as? [[String: Any]] ?? []
            // Remove existing NotchMeow entries
            groups = removeNbHookEntries(from: groups)
            var hookEntry: [String: Any] = [
                "type": "command",
                "command": "\(base) --agent codex",
                "timeout": timeout,
            ]
            if let msg = statusMsg { hookEntry["statusMessage"] = msg }
            groups.append(["hooks": [hookEntry]])
            hooks[event] = groups
        }
        root["hooks"] = hooks
        return try JSONSerialization.data(withJSONObject: root,
                                         options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    private func withoutCodexHooks() throws -> Data {
        var root = try Self.strictReadJSONObject(at: Self.codexHooksURL, label: "~/.codex/hooks.json")
        if let raw = root["hooks"], !(raw is [String: Any]) {
            throw NSError(domain: "NotchMeow", code: 2, userInfo: [
                NSLocalizedDescriptionKey: "~/.codex/hooks.json: \"hooks\" has an unexpected type — NotchMeow has not touched it."
            ])
        }
        if var hooks = root["hooks"] as? [String: Any] {
            for key in hooks.keys {
                if let groups = hooks[key] as? [[String: Any]] {
                    let cleaned = removeNbHookEntries(from: groups)
                    if cleaned.isEmpty { hooks.removeValue(forKey: key) } else { hooks[key] = cleaned }
                }
            }
            if hooks.isEmpty { root.removeValue(forKey: "hooks") } else { root["hooks"] = hooks }
        }
        return try JSONSerialization.data(withJSONObject: root,
                                         options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
    }

    // MARK: SHA-256 fingerprint

    private func sha256Hex(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }
    #endif
}

// MARK: - Notification names for hook server → controller communication

extension Notification.Name {
    static let hookExpand = Notification.Name("notchBuddy.hookExpand")
}

// MARK: - nm-hook shell wrapper (same for both GitHub and App Store)
// Invoked by Claude Code via /bin/sh or directly via shebang.
// Always exits 0 — never blocks Claude Code.
// Checks xcode-select before running python3 to avoid triggering the
// "install developer tools" dialog on machines without Xcode CLI tools.

private let nbHookShellWrapper = """
#!/bin/sh
# NotchMeow hook relay — always exits 0, never blocks Claude Code
HOOK_DIR="$(dirname "$0")"
if xcode-select -p >/dev/null 2>&1; then
    out=$(/usr/bin/python3 "$HOOK_DIR/nm-hook.py" "$@" 2>/dev/null)
    rc=$?
    if [ "$rc" -eq 0 ] && [ -n "$out" ]; then
        printf '%s\\n' "$out"
    fi
fi
exit 0
"""

// MARK: - nm-hook Python relay (GitHub / non-sandboxed version)

private let nbHookPythonGitHub = """
#!/usr/bin/env python3
# nm-hook.py — NotchMeow hook relay for Claude Code and third-party agents (GitHub version)
# Reads JSON from stdin, forwards to NotchMeow via Unix socket, translates response.
import sys, json, os, socket

def normalize_event(name):
    mapping = {
        'BeforeTool': 'PreToolUse', 'BeforeToolSelection': 'PreToolUse',
        'AfterTool': 'PostToolUse', 'AfterModel': 'PostToolUse',
        'BeforeAgent': 'UserPromptSubmit', 'AfterAgent': 'Stop',
        'startup': 'SessionStart', 'exit': 'SessionEnd',
        'PreInvocation': 'UserPromptSubmit', 'PostInvocation': 'PostToolUse',
    }
    return mapping.get(name, name)

def normalize_tool_fields(payload):
    if 'tool_name' in payload:
        return
    tool = payload.get('toolCall')
    if not isinstance(tool, dict):
        tool = {}
    name = tool.get('name') or payload.get('tool', '')
    if name:
        payload['tool_name'] = name
    if 'tool_input' not in payload and isinstance(tool.get('args'), dict):
        flat = dict(tool['args'])
        for src, dst in [('CommandLine', 'command'), ('FilePath', 'file_path'),
                         ('Path', 'path'), ('Url', 'url'), ('Query', 'query'), ('Pattern', 'pattern')]:
            if src in flat:
                flat[dst] = flat[src]
        payload['tool_input'] = flat
    if 'session_id' not in payload:
        for k in ['conversationId', 'conversation_id', 'sessionId', 'GEMINI_SESSION_ID']:
            if payload.get(k):
                payload['session_id'] = payload[k]
                break
        if 'session_id' not in payload:
            sid = os.environ.get('GEMINI_SESSION_ID', '')
            if sid:
                payload['session_id'] = sid

def main():
    raw = b''
    payload = {}
    try:
        raw = sys.stdin.buffer.read()
        if not raw:
            if '--statusline' not in sys.argv[1:]:
                return
        else:
            payload = json.loads(raw)
    except Exception:
        if '--statusline' not in sys.argv[1:]:
            return

    socket_path = os.path.expanduser(
        '~/Library/Application Support/NotchMeow/nm.sock'
    )

    # --statusline mode: relay rate_limits to NotchMeow, then delegate to saved previous
    if '--statusline' in sys.argv[1:]:
        relay = {
            'nm_kind': 'statusline',
            'session_id': payload.get('session_id', ''),
            'rate_limits': payload.get('rate_limits', {}),
        }
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.settimeout(0.3)
            s.connect(socket_path)
            s.sendall((json.dumps(relay) + '\\n').encode())
            s.close()
        except Exception:
            pass
        prev_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'statusline-previous.json')
        if os.path.exists(prev_file):
            try:
                import subprocess
                with open(prev_file) as f:
                    prev = json.load(f)
                cmd = prev.get('command', '')
                if cmd:
                    result = subprocess.run(['/bin/sh', '-c', cmd], input=raw,
                                             capture_output=True, timeout=10)
                    if result.stdout:
                        sys.stdout.buffer.write(result.stdout)
                        sys.stdout.buffer.flush()
            except Exception:
                pass
        return

    # --ask mode: dedicated hook for AskUserQuestion via PreToolUse (Claude Code 2.1.85+)
    if '--ask' in sys.argv[1:]:
        tool = payload.get('tool_name', '')
        if tool != 'AskUserQuestion':
            return  # Not an AskUserQuestion invocation — exit cleanly (no output)
        payload['nm_kind'] = 'ask_user_question'
        env = os.environ
        payload.setdefault('term_program', env.get('TERM_PROGRAM', ''))
        payload.setdefault('iterm_session_id', env.get('ITERM_SESSION_ID', ''))
        payload.setdefault('term_session_id', env.get('TERM_SESSION_ID', ''))
        payload.setdefault('bundle_id', env.get('__CFBundleIdentifier', ''))
        if 'cwd' not in payload or not payload['cwd']:
            paths = payload.get('workspacePaths') or payload.get('workspace_roots', [])
            if isinstance(paths, list) and paths:
                payload['cwd'] = paths[0]
            else:
                payload['cwd'] = os.getcwd()
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.settimeout(125)
            s.connect(socket_path)
            s.sendall((json.dumps(payload) + '\\n').encode())
            chunks = []
            while True:
                chunk = s.recv(4096)
                if not chunk:
                    break
                chunks.append(chunk)
                if b'\\n' in chunk:
                    break
            s.close()
            response = b''.join(chunks).decode().strip()
            if response:
                try:
                    resp_obj = json.loads(response)
                    decision = resp_obj.get('permissionDecision', '')
                except Exception:
                    decision = ''
                if decision == 'answer':
                    answers = resp_obj.get('answers', {})
                    questions = payload.get('tool_input', {}).get('questions', [])
                    out = {'hookSpecificOutput': {'hookEventName': 'PreToolUse', 'permissionDecision': 'allow', 'updatedInput': {'questions': questions, 'answers': answers}}}
                    sys.stdout.write(json.dumps(out) + '\\n')
                    sys.stdout.flush()
                    sys.exit(0)
                # 'ask' or unknown: fall through → no output → Claude Code asks in terminal
        except Exception:
            pass
        return

    # Parse --agent <name> and optional positional event from argv.
    # --agent tags the payload with nm_agent so the app routes to the right pill.
    # The positional arg is a fallback event name for agents that do not set hook_event_name.
    args = sys.argv[1:]
    agent = ''
    arg_event = ''
    i = 0
    while i < len(args):
        if args[i] == '--agent' and i + 1 < len(args):
            agent = args[i + 1]
            i += 2
        else:
            if not arg_event:
                arg_event = args[i]
            i += 1
    if agent:
        payload.setdefault('nm_agent', agent)
    # A Claude Code session started from the Claude desktop app (its Code tab) says so in CLAUDE_CODE_ENTRYPOINT and has no --agent:
    # it is tagged so the app can tell it apart; it still shows under the Claude Code pill (HookOrigin). An explicit --agent wins.
    if not payload.get('nm_agent') and os.environ.get('CLAUDE_CODE_ENTRYPOINT') == 'claude-desktop':
        payload['nm_agent'] = 'claude-desktop'

    # Enrich with terminal context
    env = os.environ
    payload.setdefault('term_program', env.get('TERM_PROGRAM', ''))
    payload.setdefault('iterm_session_id', env.get('ITERM_SESSION_ID', ''))
    payload.setdefault('term_session_id', env.get('TERM_SESSION_ID', ''))
    payload.setdefault('bundle_id', env.get('__CFBundleIdentifier', ''))
    if 'cwd' not in payload or not payload['cwd']:
        paths = payload.get('workspacePaths') or payload.get('workspace_roots', [])
        if isinstance(paths, list) and paths:
            payload['cwd'] = paths[0]
        else:
            payload['cwd'] = os.getcwd()

    # Normalize event name and tool fields (Gemini CLI / Antigravity → canonical names)
    try:
        raw_event = payload.get('hook_event_name', '') or arg_event
        if raw_event:
            payload['hook_event_name'] = normalize_event(raw_event)
        normalize_tool_fields(payload)
    except Exception:
        pass

    event = payload.get('hook_event_name', '')
    # socket_path is already defined above

    if event == 'PermissionRequest':
        # Block and wait for NotchMeow's decision (Claude Code allows up to 120s)
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.settimeout(118)
            s.connect(socket_path)
            s.sendall((json.dumps(payload) + '\\n').encode())
            chunks = []
            while True:
                chunk = s.recv(4096)
                if not chunk:
                    break
                chunks.append(chunk)
                if b'\\n' in chunk:
                    break
            s.close()
            response = b''.join(chunks).decode().strip()
            if response:
                try:
                    resp_obj = json.loads(response)
                    decision = resp_obj.get('permissionDecision', '')
                except Exception:
                    decision = ''
                if decision == 'allow':
                    out = {'hookSpecificOutput': {'hookEventName': 'PermissionRequest', 'decision': {'behavior': 'allow'}}}
                    sys.stdout.write(json.dumps(out) + '\\n')
                    sys.stdout.flush()
                    sys.exit(0)
                elif decision == 'always' and agent != 'codex':
                    # Let Claude Code persist the rule via updatedPermissions
                    suggestions = payload.get('permission_suggestions', [])
                    out = {'hookSpecificOutput': {'hookEventName': 'PermissionRequest', 'decision': {'behavior': 'allow', 'updatedPermissions': suggestions}}}
                    sys.stdout.write(json.dumps(out) + '\\n')
                    sys.stdout.flush()
                    sys.exit(0)
                elif decision == 'always':
                    # Codex rejects updatedPermissions — answer a plain allow instead
                    out = {'hookSpecificOutput': {'hookEventName': 'PermissionRequest', 'decision': {'behavior': 'allow'}}}
                    sys.stdout.write(json.dumps(out) + '\\n')
                    sys.stdout.flush()
                    sys.exit(0)
                elif decision == 'deny':
                    out = {'hookSpecificOutput': {'hookEventName': 'PermissionRequest', 'decision': {'behavior': 'deny', 'message': 'Denied from NotchMeow'}}}
                    sys.stdout.write(json.dumps(out) + '\\n')
                    sys.stdout.flush()
                    sys.exit(0)
                elif decision == 'answer':
                    # AskUserQuestion answered from the notch
                    answers = resp_obj.get('answers', {})
                    questions = payload.get('tool_input', {}).get('questions', [])
                    out = {'hookSpecificOutput': {'hookEventName': 'PermissionRequest', 'decision': {'behavior': 'allow', 'updatedInput': {'questions': questions, 'answers': answers}}}}
                    sys.stdout.write(json.dumps(out) + '\\n')
                    sys.stdout.flush()
                    sys.exit(0)
                # 'ask' or unknown: fall through → no output → agent re-asks
        except Exception:
            pass
        # App unreachable, timed out, or no explicit decision — print nothing
        # Claude Code / Codex will handle the absence of output (re-ask or default behaviour)
        sys.exit(0)

    # All other events: fire-and-forget (0.3s timeout, never blocks)
    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(0.3)
        s.connect(socket_path)
        s.sendall((json.dumps(payload) + '\\n').encode())
        s.close()
    except Exception:
        pass  # Always exit cleanly — never block the agent

    # Gemini CLI and Antigravity expect a JSON response on stdout (empty = no decision).
    # Antigravity reads "{}" on PreToolUse as a denial, so it gets "ask": its own permission prompt
    # (and the user's Always Allow) stays, and NotchMeow never allows a tool by itself.
    if agent == 'antigravity' and event == 'PreToolUse':
        sys.stdout.write('{"decision":"ask"}\\n')
        sys.stdout.flush()
    elif agent in ('gemini', 'antigravity'):
        sys.stdout.write('{}\\n')
        sys.stdout.flush()

main()
sys.exit(0)
"""

// MARK: - nm-hook Python relay (App Store — socket in sandboxed container)

private let nbHookPythonAppStore = """
#!/usr/bin/env python3
# nm-hook.py — NotchMeow (App Store) hook relay for Claude Code and third-party agents
# Socket lives inside the sandboxed container; script runs outside the sandbox.
import sys, json, os, socket

def normalize_event(name):
    mapping = {
        'BeforeTool': 'PreToolUse', 'BeforeToolSelection': 'PreToolUse',
        'AfterTool': 'PostToolUse', 'AfterModel': 'PostToolUse',
        'BeforeAgent': 'UserPromptSubmit', 'AfterAgent': 'Stop',
        'startup': 'SessionStart', 'exit': 'SessionEnd',
        'PreInvocation': 'UserPromptSubmit', 'PostInvocation': 'PostToolUse',
    }
    return mapping.get(name, name)

def normalize_tool_fields(payload):
    if 'tool_name' in payload:
        return
    tool = payload.get('toolCall')
    if not isinstance(tool, dict):
        tool = {}
    name = tool.get('name') or payload.get('tool', '')
    if name:
        payload['tool_name'] = name
    if 'tool_input' not in payload and isinstance(tool.get('args'), dict):
        flat = dict(tool['args'])
        for src, dst in [('CommandLine', 'command'), ('FilePath', 'file_path'),
                         ('Path', 'path'), ('Url', 'url'), ('Query', 'query'), ('Pattern', 'pattern')]:
            if src in flat:
                flat[dst] = flat[src]
        payload['tool_input'] = flat
    if 'session_id' not in payload:
        for k in ['conversationId', 'conversation_id', 'sessionId', 'GEMINI_SESSION_ID']:
            if payload.get(k):
                payload['session_id'] = payload[k]
                break
        if 'session_id' not in payload:
            sid = os.environ.get('GEMINI_SESSION_ID', '')
            if sid:
                payload['session_id'] = sid

def main():
    raw = b''
    payload = {}
    try:
        raw = sys.stdin.buffer.read()
        if not raw:
            if '--statusline' not in sys.argv[1:]:
                return
        else:
            payload = json.loads(raw)
    except Exception:
        if '--statusline' not in sys.argv[1:]:
            return

    socket_path = os.path.expanduser(
        '~/Library/Containers/io.github.aikusan.notchmeow.store/Data/nm.sock'
    )

    # --statusline mode: relay rate_limits to NotchMeow, then delegate to saved previous
    if '--statusline' in sys.argv[1:]:
        relay = {
            'nm_kind': 'statusline',
            'session_id': payload.get('session_id', ''),
            'rate_limits': payload.get('rate_limits', {}),
        }
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.settimeout(0.3)
            s.connect(socket_path)
            s.sendall((json.dumps(relay) + '\\n').encode())
            s.close()
        except Exception:
            pass
        prev_file = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'statusline-previous.json')
        if os.path.exists(prev_file):
            try:
                import subprocess
                with open(prev_file) as f:
                    prev = json.load(f)
                cmd = prev.get('command', '')
                if cmd:
                    result = subprocess.run(['/bin/sh', '-c', cmd], input=raw,
                                             capture_output=True, timeout=10)
                    if result.stdout:
                        sys.stdout.buffer.write(result.stdout)
                        sys.stdout.buffer.flush()
            except Exception:
                pass
        return

    # --ask mode: dedicated hook for AskUserQuestion via PreToolUse (Claude Code 2.1.85+)
    if '--ask' in sys.argv[1:]:
        tool = payload.get('tool_name', '')
        if tool != 'AskUserQuestion':
            return  # Not an AskUserQuestion invocation — exit cleanly (no output)
        payload['nm_kind'] = 'ask_user_question'
        env = os.environ
        payload.setdefault('term_program', env.get('TERM_PROGRAM', ''))
        payload.setdefault('iterm_session_id', env.get('ITERM_SESSION_ID', ''))
        payload.setdefault('term_session_id', env.get('TERM_SESSION_ID', ''))
        payload.setdefault('bundle_id', env.get('__CFBundleIdentifier', ''))
        if 'cwd' not in payload or not payload['cwd']:
            paths = payload.get('workspacePaths') or payload.get('workspace_roots', [])
            if isinstance(paths, list) and paths:
                payload['cwd'] = paths[0]
            else:
                payload['cwd'] = os.getcwd()
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.settimeout(125)
            s.connect(socket_path)
            s.sendall((json.dumps(payload) + '\\n').encode())
            chunks = []
            while True:
                chunk = s.recv(4096)
                if not chunk:
                    break
                chunks.append(chunk)
                if b'\\n' in chunk:
                    break
            s.close()
            response = b''.join(chunks).decode().strip()
            if response:
                try:
                    resp_obj = json.loads(response)
                    decision = resp_obj.get('permissionDecision', '')
                except Exception:
                    decision = ''
                if decision == 'answer':
                    answers = resp_obj.get('answers', {})
                    questions = payload.get('tool_input', {}).get('questions', [])
                    out = {'hookSpecificOutput': {'hookEventName': 'PreToolUse', 'permissionDecision': 'allow', 'updatedInput': {'questions': questions, 'answers': answers}}}
                    sys.stdout.write(json.dumps(out) + '\\n')
                    sys.stdout.flush()
                    sys.exit(0)
                # 'ask' or unknown: fall through → no output → Claude Code asks in terminal
        except Exception:
            pass
        return

    # Parse --agent <name> and optional positional event from argv.
    # --agent tags the payload with nm_agent so the app routes to the right pill.
    # The positional arg is a fallback event name for agents that do not set hook_event_name.
    args = sys.argv[1:]
    agent = ''
    arg_event = ''
    i = 0
    while i < len(args):
        if args[i] == '--agent' and i + 1 < len(args):
            agent = args[i + 1]
            i += 2
        else:
            if not arg_event:
                arg_event = args[i]
            i += 1
    if agent:
        payload.setdefault('nm_agent', agent)
    # A Claude Code session started from the Claude desktop app (its Code tab) says so in CLAUDE_CODE_ENTRYPOINT and has no --agent:
    # it is tagged so the app can tell it apart; it still shows under the Claude Code pill (HookOrigin). An explicit --agent wins.
    if not payload.get('nm_agent') and os.environ.get('CLAUDE_CODE_ENTRYPOINT') == 'claude-desktop':
        payload['nm_agent'] = 'claude-desktop'

    env = os.environ
    payload.setdefault('term_program', env.get('TERM_PROGRAM', ''))
    payload.setdefault('iterm_session_id', env.get('ITERM_SESSION_ID', ''))
    payload.setdefault('term_session_id', env.get('TERM_SESSION_ID', ''))
    payload.setdefault('bundle_id', env.get('__CFBundleIdentifier', ''))
    if 'cwd' not in payload or not payload['cwd']:
        paths = payload.get('workspacePaths') or payload.get('workspace_roots', [])
        if isinstance(paths, list) and paths:
            payload['cwd'] = paths[0]
        else:
            payload['cwd'] = os.getcwd()

    # Normalize event name and tool fields (Gemini CLI / Antigravity → canonical names)
    try:
        raw_event = payload.get('hook_event_name', '') or arg_event
        if raw_event:
            payload['hook_event_name'] = normalize_event(raw_event)
        normalize_tool_fields(payload)
    except Exception:
        pass

    event = payload.get('hook_event_name', '')
    # socket_path is already defined above

    if event == 'PermissionRequest':
        # Block and wait for NotchMeow's decision (Claude Code allows up to 120s)
        try:
            s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
            s.settimeout(118)
            s.connect(socket_path)
            s.sendall((json.dumps(payload) + '\\n').encode())
            chunks = []
            while True:
                chunk = s.recv(4096)
                if not chunk:
                    break
                chunks.append(chunk)
                if b'\\n' in chunk:
                    break
            s.close()
            response = b''.join(chunks).decode().strip()
            if response:
                try:
                    resp_obj = json.loads(response)
                    decision = resp_obj.get('permissionDecision', '')
                except Exception:
                    decision = ''
                if decision == 'allow':
                    out = {'hookSpecificOutput': {'hookEventName': 'PermissionRequest', 'decision': {'behavior': 'allow'}}}
                    sys.stdout.write(json.dumps(out) + '\\n')
                    sys.stdout.flush()
                    sys.exit(0)
                elif decision == 'always' and agent != 'codex':
                    # Let Claude Code persist the rule via updatedPermissions
                    suggestions = payload.get('permission_suggestions', [])
                    out = {'hookSpecificOutput': {'hookEventName': 'PermissionRequest', 'decision': {'behavior': 'allow', 'updatedPermissions': suggestions}}}
                    sys.stdout.write(json.dumps(out) + '\\n')
                    sys.stdout.flush()
                    sys.exit(0)
                elif decision == 'always':
                    # Codex rejects updatedPermissions — answer a plain allow instead
                    out = {'hookSpecificOutput': {'hookEventName': 'PermissionRequest', 'decision': {'behavior': 'allow'}}}
                    sys.stdout.write(json.dumps(out) + '\\n')
                    sys.stdout.flush()
                    sys.exit(0)
                elif decision == 'deny':
                    out = {'hookSpecificOutput': {'hookEventName': 'PermissionRequest', 'decision': {'behavior': 'deny', 'message': 'Denied from NotchMeow'}}}
                    sys.stdout.write(json.dumps(out) + '\\n')
                    sys.stdout.flush()
                    sys.exit(0)
                elif decision == 'answer':
                    # AskUserQuestion answered from the notch
                    answers = resp_obj.get('answers', {})
                    questions = payload.get('tool_input', {}).get('questions', [])
                    out = {'hookSpecificOutput': {'hookEventName': 'PermissionRequest', 'decision': {'behavior': 'allow', 'updatedInput': {'questions': questions, 'answers': answers}}}}
                    sys.stdout.write(json.dumps(out) + '\\n')
                    sys.stdout.flush()
                    sys.exit(0)
                # 'ask' or unknown: fall through → no output → agent re-asks
        except Exception:
            pass
        # App unreachable, timed out, or no explicit decision — print nothing
        sys.exit(0)

    try:
        s = socket.socket(socket.AF_UNIX, socket.SOCK_STREAM)
        s.settimeout(0.3)
        s.connect(socket_path)
        s.sendall((json.dumps(payload) + '\\n').encode())
        s.close()
    except Exception:
        pass  # Always exit cleanly — never block the agent

    # Gemini CLI and Antigravity expect a JSON response on stdout (empty = no decision).
    # Antigravity reads "{}" on PreToolUse as a denial, so it gets "ask": its own permission prompt
    # (and the user's Always Allow) stays, and NotchMeow never allows a tool by itself.
    if agent == 'antigravity' and event == 'PreToolUse':
        sys.stdout.write('{"decision":"ask"}\\n')
        sys.stdout.flush()
    elif agent in ('gemini', 'antigravity'):
        sys.stdout.write('{}\\n')
        sys.stdout.flush()

main()
sys.exit(0)
"""
