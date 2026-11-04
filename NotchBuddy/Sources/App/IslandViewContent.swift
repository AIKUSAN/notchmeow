import SwiftUI

// MARK: - Dispatch view content by IslandView

struct IslandViewContent: View {
    let view: IslandView
    @ObservedObject var state: AppState

    var body: some View {
        switch view {
        case .overview:  OverviewView(state: state)
        case .empty:     EmptyStateView(state: state)
        case .approval:  ApprovalView(state: state)
        case .question:  QuestionView(state: state)
        case .error:     ErrorView(state: state)
        case .finished:  FinishedView(state: state)
        case .confused:  ConfusedView()
        case .upload:    UploadView(state: state)
        case .uploading: UploadingView(state: state)
        case .choose:    ChooseView(state: state)
        case .mail:      MailView(state: state)
        case .prompt:    if state.chatPoppedOut { PoppedOutNote(state: state) } else { PromptView(state: state) }
        case .searching: SearchingView(state: state)
        case .result:    ResultView(state: state)
        case .note:      NoteView(state: state)
        case .settings:  SettingsIslandView(state: state)
        case .greeting:  EmptyView()  // GreetingCanvasView overlaid in IslandRootView
        case .sidekick:  SidekickView(engine: Sidekick.shared.engine, state: state)
        case .shelf:
            // Built only while it is the active view: the island stacks every view and fades the inactive ones, but AppKit hit-tests an NSView whatever its alpha, and the shelf's tiles are
            // AppKit views, topmost of the stack. An inactive shelf must have none on screen.
            if state.view == .shelf { ShelfView(model: ShelfModel.shared) }
        case .link:
            if state.view == .link { LinkCardHost() }
        case .projects:
            // Built only while it is the active view, as the shelf's is: an inactive screen has no rows on screen.
            if state.view == .projects { ProjectsScreenHost() }
        }
    }
}

/// The `.link` view in the app: the card for what `LinkService` holds, with the buttons wired to it.
struct LinkCardHost: View {
    @ObservedObject private var link = LinkService.shared

    var body: some View {
        LinkCardView(card: link.card, actions: LinkCardActions(
            answerPair: { link.answerPair(yes: $0, for: $1) }, respondOffer: { link.respondOffer(accept: $0, for: $1) }, cancel: { link.cancelReceiving(for: $0) },
            showInFinder: { NSWorkspace.shared.activateFileViewerSelecting([$0]) }, dismiss: { link.dismissCard(for: $0) }))
    }
}

// MARK: - Overview

struct OverviewView: View {
    @ObservedObject var state: AppState
    /// Projects (P-mac): the Claude-only card and pill grid, and the Claude Code card's expanded section. Read only while Claude is the focus.
    @ObservedObject private var projects = ProjectsModel.shared
    @State private var showingN8nDetail = false
    @State private var activeDiffId: Int? = nil
    /// The project whose peek is open over the left card (the model holds it, so the big cat and the kittens step aside for it), the project whose dwell is running or has run, and
    /// the dwell that opens it (Projects, P-mac).
    private var peekId: String? { projects.peekingProject }
    @State private var peekPending: String?
    @State private var peekTask: Task<Void, Never>?

    var agent: AgentTask? { state.focusTask }

    /// Two cats mode only: cat 2 and the agent it shows. The cats take more of the left card, so the text starts further right (`CatIslandLayout`) and gains a
    /// second line for cat 2's agent. In the other modes `second` is nil and the card is exactly what it has always been.
    private var second: CatCast.Spot? { state.cast.second }
    private var textLeading: CGFloat {
        guard second != nil, let l = IslandConst.viewLayouts[.overview] else { return CGFloat(CatIslandLayout.oneTextLeading) }
        return CGFloat(CatIslandLayout.pairExpanded(botX: Double(l.botX), cy: 0).textLeading)
    }

    /// The same shift for the cards the overview hosts (an integration's, the plan's, a diff): their text starts at 108 on its own, so they move right as a whole.
    /// 0 outside Two cats mode, where they are what they have always been.
    private var cardShift: CGFloat {
        guard let l = IslandConst.viewLayouts[.overview] else { return 0 }
        return CGFloat(CatIslandLayout.overviewCardShift(second: second != nil, botX: Double(l.botX)))
    }

    /// Cat 2's line under the ticker: "Codex · waiting for you", in the colour of the state when it needs you.
    private func secondLine(_ s: CatCast.Spot) -> some View {
        let task = s.pill.flatMap { id in state.tasks.first { $0.id == id } }
        let words = task.map { "\(state.agentName(for: $0.id)) · \(CatIslandLayout.stateWords(CatState(rawValue: $0.state.rawValue) ?? .idle))" } ?? "No other agent"
        let colour: String = {
            switch task?.state {
            case .approval: return "#F5A524"
            case .question: return "#22D3EE"
            case .error: return "#F4505E"
            default: return "#8E939C"
            }
        }()
        return Text(words)
            .font(.system(size: 11))
            .foregroundColor(Color(hex: colour))
            .lineLimit(1)
            .truncationMode(.tail)
            .padding(.leading, textLeading)
            .padding(.trailing, 12)
            .padding(.top, 2)
    }

    /// What the overview reads of Projects, once per body: the model's view, whether the Claude-only layout is on (Plan call 26: never in Two cats mode), its big card, the
    /// row the Claude Code card's title adds with other agents, and the pill grid's input. With no live project, another focus or Two cats mode every part is nil, and the
    /// overview is today's.
    private struct ProjectsOverview {
        var view: PJView
        var card: PJProject?
        var row: ProjectsTitleRow?
        var grid: ProjectsGridInput?
        /// The Projects views draw and move only while the island is expanded on this view (0 % CPU when hidden).
        var active: Bool
        var toggle: () -> Void
    }

    private var projectsOverview: ProjectsOverview {
        let relevant = state.focusId == nil || state.focusId == "integration_claude"
        let view = relevant ? projects.appView() : PJView(projects: [], waiting: 0, sessionCount: 0, otherAgentSeen: false)
        let uses = ProjectsLayout.usesProjects(layout: projects.layout, focusId: state.focusId, projectCount: view.projects.count, twoCats: state.cast.second != nil)
        let projectsActive = state.mode == .expanded && state.view == .overview
        let toggle = { withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { projects.togglePanel() } }
        let projectsRow: ProjectsTitleRow? = if !uses && state.cast.second == nil && state.focusId == "integration_claude" && !view.projects.isEmpty {
            ProjectsTitleRow(projects: view.projects.count, waiting: view.waiting, open: projects.panelShown, onToggle: toggle)
        } else { nil }
        let grid: ProjectsGridInput? = if uses {
            ProjectsGridInput(projects: view.projects, active: projectsActive, onSelect: { projects.select($0) }, onMore: openScreen, onHover: hoverProject, onFrame: recordFrame)
        } else { nil }
        return ProjectsOverview(view: view, card: uses ? projects.bigCard(in: view) : nil, row: projectsRow, grid: grid, active: projectsActive, toggle: toggle)
    }

    /// The "+N" cell: the Projects screen, with the spring the header's tabs use.
    private func openScreen() {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) { state.view = .projects }
    }

    /// The big card's open (and its tap): the project's newest session comes forward, by the registry's session id (never a path).
    private func openProject(_ project: PJProject) {
        guard let newest = project.sessions.max(by: { $0.lastAt < $1.lastAt }) else { return }
        AgentTarget.bringForward(session: newest.id)
    }

    /// A project pill's hover, in either layout: after the dwell its peek opens over the left card, and leaving the pill closes it. One sleep per hover-in, cancelled on hover-out
    /// (never a poll); it opens only while the island is expanded on this view. Purely visual: it selects, pins and alerts nothing.
    private func hoverProject(_ id: String, _ hovering: Bool) {
        // A late exit from one pill after the enter of another must not cancel the other's dwell: only the pending id clears it, and only the showing id clears the peek.
        guard hovering else {
            if peekPending == id { clearPeek() } else if peekId == id { projects.setPeeking(nil) }
            return
        }
        peekTask?.cancel()
        peekPending = id
        peekTask = Task {
            try? await Task.sleep(for: .milliseconds(Int(ProjectsLayout.peekDwell * 1000)))
            guard !Task.isCancelled, state.mode == .expanded, state.view == .overview else { return }
            projects.setPeeking(id)
        }
    }

    /// The peek goes, and its dwell with it.
    private func clearPeek() {
        peekTask?.cancel()
        peekTask = nil
        peekPending = nil
        projects.setPeeking(nil)
    }

    /// Where a project's pill is, in the island's own coordinates, for the right-click that pins it (`ProjectsHits`); a pill that left the tree reports a null frame. Such a pill
    /// sends no hover-out, so its own pending or showing peek goes with it.
    private func recordFrame(_ id: String, _ rect: CGRect) {
        if rect.isNull, peekId == id || peekPending == id { clearPeek() }
        ProjectsHits.pillFrames[id] = rect.isNull ? nil : rect
    }

    var body: some View {
        let p = projectsOverview
        VStack(spacing: 0) {
            cards(p)
                .frame(height: ProjectsLayout.contentHeight)
            // The Claude Code card's expanded section (with other agents): one row of projects under the two cards, 8 pt below them.
            if projects.panelShown {
                CardBackground(wash: nil) {
                    ProjectsPanel(cells: ProjectsLayout.panelCells(projects: p.view.projects.map { $0.id }), projects: p.view.projects, selected: projects.bigCard(in: p.view),
                                  active: p.active, onSelect: { projects.select($0) }, onMore: openScreen, onHover: hoverProject, onFrame: recordFrame)
                }
                .frame(height: ProjectsLayout.panelExtra - 8)
                .padding(.top, 8)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// Today's two cards, and with Projects (Claude alone) the project's card and the pill grid in their places.
    private func cards(_ p: ProjectsOverview) -> some View {
        HStack(spacing: 10) {
            // Left card: title row + ticker below + ↗ button overlay
            ZStack(alignment: .topLeading) {
                CardBackground(wash: nil)

                // With other agents and a live project, a tap on the card's empty background opens or closes the section too.
                if p.row != nil { Color.clear.contentShape(Rectangle()).onTapGesture(perform: p.toggle) }

                // Title row + ticker stacked (or integration card)
                if let card = p.card {
                    // The Claude-only card: the project the big card shows. It draws no card and no cat (the island's big cat is its cat); a tap anywhere on it, or its ↗, opens its newest session.
                    ProjectBigCard(project: card, animate: p.active, onOpen: { openProject(card) })
                        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                        .contentShape(Rectangle())
                        .onTapGesture { openProject(card) }
                } else if let agent = agent {
                    if agent.isIntegration {
                        IntegrationCardView(task: agent, showingDetail: $showingN8nDetail, projectsRow: p.row, onDiffTap: { diffIdx in
                            withAnimation(.easeIn(duration: 0.16)) { activeDiffId = diffIdx }
                        })
                        .padding(.leading, cardShift)
                    } else {
                        VStack(alignment: .leading, spacing: 0) {
                            HStack(spacing: 6) {
                                Circle()
                                    .fill(Color(hex: agent.color))
                                    .frame(width: 7, height: 7)
                                Text(agent.name)
                                    .font(.system(size: 12, weight: .semibold))
                                    .foregroundColor(Color(hex: "#F5F6F8"))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                    .layoutPriority(1)
                                Text({ () -> String in
                                    switch agent.source {
                                    case .claudeCode: return "Claude Code"
                                    case .agent:      return "Agent"
                                    case .n8n:        return "n8n"
                                    }
                                }())
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(hex: "#8E939C"))
                                    .lineLimit(1)
                                    .truncationMode(.tail)
                                Spacer(minLength: 2)
                                if agent.steps.count > 1 {
                                    Text("\(min(agent.stepIndex + 1, agent.steps.count))/\(agent.steps.count)")
                                        .font(.system(size: 11))
                                        .foregroundColor(Color(hex: "#6B7079"))
                                        .fixedSize()
                                }
                            }
                            .padding(.top, second == nil ? 6 : 4)
                            .padding(.leading, textLeading)
                            .padding(.trailing, 36)

                            TickerView(task: agent, onDiffTap: { diffIdx in
                                withAnimation(.easeIn(duration: 0.16)) { activeDiffId = diffIdx }
                            })
                                .frame(height: 44)
                                .padding(.top, second == nil ? 6 : 0)
                                .padding(.leading, textLeading)
                                .padding(.trailing, 12)
                            // A live mark takes cat 2's line, unless that line is a waiting card (FocusAware.showsNoteOverSecondLine: the dot's rule).
                            let mark = state.focusMarks.forPill(agent.id, now: FocusAwareApp.now())
                            let secondWaiting = second?.pill.map { state.cardWaiting(on: $0) } ?? false
                            if FocusAware.showsNoteOverSecondLine(markLive: mark != nil, secondWaiting: secondWaiting), let mark {
                                FocusWaitNote(mark: mark, leading: textLeading)
                            } else if let second { secondLine(second) }
                        }
                        .frame(maxWidth: .infinity, alignment: .topLeading)
                        .padding(.top, 4)
                    }
                }

                // Plan detail overlays on top of normal content (GitHub build, home view only)
                #if !APPSTORE
                if state.showingPlanDetail {
                    CardBackground(wash: nil)
                    ClaudePlanCardView(usage: state.claudePlanUsage, stacked: cardShift > 0)
                        .padding(.leading, cardShift)
                        .transition(.opacity)
                }
                #endif

                // Diff overlay — replaces ticker when a diff step is tapped
                if let diffId = activeDiffId,
                   let task = agent,
                   let diff = state.sessionDiffs[task.id]?.first(where: { $0.id == diffId }) {
                    CardBackground(wash: nil)
                    DiffCardView(diff: diff, onDismiss: { activeDiffId = nil })
                        .padding(.leading, cardShift)
                        .transition(.opacity)
                }

                // ↗ jump button — last in ZStack so it renders on top; hidden while any detail is open
                // (the Claude-only card has its own ↗)
                #if !APPSTORE
                let hideJumpButton = showingN8nDetail || state.showingPlanDetail || activeDiffId != nil || p.card != nil
                #else
                let hideJumpButton = showingN8nDetail || activeDiffId != nil || p.card != nil
                #endif
                if !hideJumpButton {
                    Button(action: { openAgentTarget(agent) }) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(Color(hex: "#5F646D"))
                            .frame(width: 16, height: 16)
                            .background(Color.white.opacity(0.07))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    .padding(.trailing, 10)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }
            .frame(width: 322)
            .overlay {   // the peek (Projects, P-mac): the left card's own frame, over it; no hover and no click, so the pills keep both
                if let id = peekId, p.active, let project = p.view.projects.first(where: { $0.id == id }) {
                    ProjectsPeek(project: project, active: p.active)
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
            .animation(.easeOut(duration: 0.12), value: peekId)

            // Right card: agent pills (with Projects, Claude alone: the project pills, then the other pills)
            CardBackground(wash: nil) {
                AgentPillsView(state: state, projects: p.grid)
            }
        }
        .onChange(of: state.focusId) { _, new in
            showingN8nDetail = false
            activeDiffId = nil
            clearPeek()
            #if !APPSTORE
            withAnimation(.easeIn(duration: 0.16)) { state.showingPlanDetail = false }
            #endif
            if new == "integration_github" { GithubPoller.shared.refreshIfStale() }
        }
        #if !APPSTORE
        .onChange(of: state.view) { _, v in
            if v != .overview { state.showingPlanDetail = false; activeDiffId = nil }
        }
        #endif
        // The stacked overview stays in the tree while another view shows, so its pills keep their frames (the right-click checks the view); only the peek goes.
        .onChange(of: state.view) { _, v in
            if v != .overview { clearPeek() }
        }
        .onChange(of: projects.panelShown) { _, _ in clearPeek() }
        .onDisappear { clearPeek() }
        .onChange(of: state.mode) { _, m in
            if m != .expanded { clearPeek(); ProjectsHits.pillFrames.removeAll() }
            #if !APPSTORE
            if m != .expanded { state.showingPlanDetail = false; activeDiffId = nil }
            #endif
            if m == .expanded && state.focusId == "integration_github" {
                GithubPoller.shared.refreshIfStale()
            }
        }
        // ⌘E: open the latest diff of the pill on screen, or close the one that is open
        .onReceive(NotificationCenter.default.publisher(for: .islandToggleDiff)) { _ in
            guard state.view == .overview else { return }
            if activeDiffId != nil {
                withAnimation(.easeIn(duration: 0.16)) { activeDiffId = nil }
            } else if let task = agent, let last = state.sessionDiffs[task.id]?.last {
                withAnimation(.easeIn(duration: 0.16)) { activeDiffId = last.id }
            }
        }
    }

    private func openAgentTarget(_ task: AgentTask?) {
        guard let task else { return }
        switch task.id {
        case "integration_claude", "agent_cursor", "agent_codex", "agent_gemini", "agent_antigravity", HookOrigin.desktopPill:
            AgentTarget.bringForward(pillId: task.id)   // the same routes as a drop on an agent's cat and a note's Show me use (AgentTarget.swift)
        case "integration_resend":
            NSWorkspace.shared.open(URL(string: "https://resend.com/emails")!)
        case "integration_vercel":
            NSWorkspace.shared.open(URL(string: "https://vercel.com/dashboard")!)
        case "integration_github":
            NSWorkspace.shared.open(URL(string: "https://github.com/pulls")!)
        case "integration_n8n":
            if let urlStr = KeychainStore.shared.get("n8n-url"), let url = URL(string: urlStr) {
                NSWorkspace.shared.open(url)
            }
        case "integration_stripe":
            NSWorkspace.shared.open(URL(string: "https://dashboard.stripe.com/payments")!)
        case "integration_notion":
            NSWorkspace.shared.open(URL(string: "https://notion.so")!)
        case "integration_calcom":
            NSWorkspace.shared.open(URL(string: "https://app.cal.com/bookings")!)
        case "ai_anthropic":
            switchChatProvider(.anthropic)
        case "ai_google":
            switchChatProvider(.google)
        case "ai_openai":
            switchChatProvider(.openai)
        case "ai_ollama":
            switchChatProvider(.ollama)
        case "ai_lmstudio":
            switchChatProvider(.lmstudio)
        case "integration_music":
            #if !APPSTORE
            MusicController.shared.openMusic()
            #endif
        default:
            // Non-integration real tasks
            if task.source == .n8n {
                if let urlStr = KeychainStore.shared.get("n8n-url"), let url = URL(string: urlStr) {
                    NSWorkspace.shared.open(url)
                }
            } else {
                #if !APPSTORE
                let terminalBundleIds = ["com.apple.Terminal", "com.googlecode.iterm2",
                                         "net.kovidgoyal.kitty", "com.mitchellh.ghostty"]
                if let hit = terminalBundleIds.compactMap({ id in
                    NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == id }
                }).first {
                    hit.activate(options: .activateIgnoringOtherApps)
                }
                #endif
            }
        }
    }
}

// MARK: - Empty

struct EmptyStateView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ZStack {
            CardBackground(wash: nil)
            HStack(spacing: 16) {
                VStack(alignment: .leading, spacing: 5) {
                    Text("Nothing running right now.")
                        .font(.system(size: 15, weight: .semibold))
                    Text("Drop a file or window, or ask me anything.")
                        .font(.system(size: 13))
                        .foregroundColor(Color(hex: "#9398A1"))
                }
                Spacer()
                PrimaryButton("Ask Claude") {
                    state.view = .prompt
                }
            }
            .padding(.leading, 118)
            .padding(.trailing, 18)
        }
    }
}

// MARK: - Approval

struct ApprovalView: View {
    @ObservedObject var state: AppState
    /// False for the first 600 ms of each request: the buttons ignore clicks (`ApprovalClickGuard`), the keys and the look are as they were.
    @State private var readyToken: UUID?
    /// True only once the guard has run for the request the card shows now: a new request's token is not `readyToken` yet, so its buttons are shut from the first frame.
    private var takesClicks: Bool { approval?.token != nil && approval?.token == readyToken }

    var approval: ApprovalInfo? { state.pendingApproval }

    var body: some View {
        ZStack {
            CardBackground(wash: .amber)
            VStack(alignment: .leading, spacing: 5) {
                HStack(spacing: 6) {
                    AgentWho(task: state.focusTask, label: "needs permission")
                    Spacer(minLength: 6)
                    if approval?.risk == "high" { RiskBadge() }
                }
                CodeBlock(text: approval?.command ?? approval?.tool ?? "…")
                // The sidekick's one line about the request: a fixed sentence with a basename in it, never the command's own words.
                if let line = approval?.line, !line.isEmpty {
                    Text(line).font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C")).lineLimit(1)
                }
                HStack(spacing: 8) {
                    SecondaryButton("Deny") {
                        HookServer.shared.sendApprovalDecision("deny")
                    }
                    PrimaryButton("Allow") {
                        HookServer.shared.sendApprovalDecision("allow")
                    }
                    // Codex rejects updatedPermissions, so "Always" is not offered
                    if approval?.pillId != "agent_codex" {
                        SecondaryButton("Always") {
                            HookServer.shared.sendApprovalDecision("always")
                        }
                    }
                }
                // A click meant for the window underneath must not land on a button: they take clicks only once the guard has run.
                .allowsHitTesting(takesClicks)
            }
            .padding(.leading, 116)
            .padding(.trailing, 16)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        // One sleep per request, cancelled with the view or by the next request (a cancelled sleep leaves the buttons shut): no timer.
        .task(id: approval?.token) {
            readyToken = nil
            guard let token = approval?.token else { return }
            do { try await Task.sleep(for: ApprovalClickGuard.duration) } catch { return }
            readyToken = token
        }
    }
}

// MARK: - Question

struct QuestionView: View {
    @ObservedObject var state: AppState
    @State private var questionIndex = 0
    // Per-question selected labels (empty = none chosen yet)
    @State private var selections: [[String]] = []
    // Per-question custom "Other…" text
    @State private var otherTexts: [String] = []
    // Per-question "Other…" mode active
    @State private var showOther: [Bool] = []
    @FocusState private var otherFieldFocused: Bool

    var question: AskQuestion? { state.pendingQuestion }

    var body: some View {
        ZStack {
            CardBackground(wash: .cyan)
            if let q = question, !q.questions.isEmpty {
                let qi = min(questionIndex, q.questions.count - 1)
                let item = q.questions[qi]
                let isLast = qi == q.questions.count - 1
                let isMulti = item.multiSelect
                let curSel = qi < selections.count ? selections[qi] : []
                let curOther = qi < showOther.count ? showOther[qi] : false
                let curOtherText = qi < otherTexts.count ? otherTexts[qi] : ""
                let canProceed = !curSel.isEmpty || (curOther && !curOtherText.isEmpty)

                VStack(alignment: .leading, spacing: 4) {
                    // Header row: agent name + question counter + "Reply in terminal" link
                    HStack(spacing: 4) {
                        AgentWho(task: nil, label: "Claude Code is asking")
                        Spacer(minLength: 4)
                        if q.questions.count > 1 {
                            Text("\(qi + 1)/\(q.questions.count)")
                                .font(.system(size: 10))
                                .foregroundColor(Color(hex: "#6B7079"))
                        }
                        Button("Reply in terminal") { HookServer.shared.sendQuestionAsk() }
                            .buttonStyle(.plain)
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#6B7079"))
                            .underline()
                    }
                    // Optional short header label above question text
                    if !item.header.isEmpty {
                        Text(item.header)
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#6B7079"))
                    }
                    // With option descriptions the whole question shows (the card is taller then, `QuestionLayout`); without them it is cut at two lines as it always was.
                    Text(item.question)
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundColor(Color(hex: "#F5F6F8"))
                        .lineLimit(item.hasDescriptions ? nil : 2)
                        .fixedSize(horizontal: false, vertical: item.hasDescriptions)
                    // Options (wrapping) or "Other…" compact inline row
                    if curOther {
                        HStack(spacing: 6) {
                            TextField("Your answer…", text: Binding(
                                get: { qi < otherTexts.count ? otherTexts[qi] : "" },
                                set: { v in if qi < otherTexts.count { otherTexts[qi] = v } }
                            ))
                            .textFieldStyle(.plain)
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "#F5F6F8"))
                            .focused($otherFieldFocused)
                            .onAppear { otherFieldFocused = true }
                            .onSubmit { commitOtherAndProceed(q: q, qi: qi, isLast: isLast) }
                            .onExitCommand { if qi < showOther.count { showOther[qi] = false } }
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(Color.white.opacity(0.07))
                            .clipShape(RoundedRectangle(cornerRadius: 8))
                            Button(isLast ? "Send" : "Next") {
                                commitOtherAndProceed(q: q, qi: qi, isLast: isLast)
                            }
                            .buttonStyle(.plain)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(curOtherText.isEmpty ? Color(hex: "#6B7079") : Color(hex: "#F5F6F8"))
                            .padding(.horizontal, 8).padding(.vertical, 5)
                            .background(Color.white.opacity(curOtherText.isEmpty ? 0.05 : 0.15))
                            .clipShape(Capsule())
                            .disabled(curOtherText.isEmpty)
                            Button { if qi < showOther.count { showOther[qi] = false } } label: {
                                Text("✕").font(.system(size: 9))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(Color(hex: "#6B7079"))
                        }
                    } else if item.hasDescriptions {
                        // Each option on its own row, its description under the label.
                        VStack(alignment: .leading, spacing: 6) {
                            ForEach(Array(item.options.enumerated()), id: \.offset) { idx, opt in
                                let isSelected = curSel.contains(opt.label)
                                Button {
                                    if isMulti {
                                        toggleSelection(qi: qi, label: opt.label)
                                    } else {
                                        selectAndProceed(q: q, qi: qi, label: opt.label, isLast: isLast)
                                    }
                                } label: {
                                    VStack(alignment: .leading, spacing: 2) {
                                        Text(opt.label)
                                            .font(.system(size: 12, weight: .medium))
                                            .foregroundColor(isSelected ? Color(hex: "#67E8F9") : Color(hex: "#F5F6F8"))
                                        if !opt.description.isEmpty {
                                            Text(opt.description)
                                                .font(.system(size: 11))
                                                .foregroundColor(Color(hex: "#9AA0A8"))
                                                .multilineTextAlignment(.leading)
                                                .fixedSize(horizontal: false, vertical: true)
                                        }
                                    }
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(.horizontal, 10).padding(.vertical, 6)
                                    .background(isSelected ? Color(hex: "#22D3EE").opacity(0.22) : Color.white.opacity(0.07))
                                    .clipShape(RoundedRectangle(cornerRadius: 8))
                                    .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? Color(hex: "#22D3EE").opacity(0.55) : Color.white.opacity(0.1), lineWidth: 1))
                                }
                                .buttonStyle(.plain)
                                .keyboardShortcut(KeyEquivalent(Character(String(idx + 1))), modifiers: [])
                            }
                            SecondaryButton("Other…") {
                                if qi < showOther.count { showOther[qi] = true }
                            }
                        }
                    } else {
                        ChipFlowLayout(spacing: 6) {
                            ForEach(Array(item.options.enumerated()), id: \.offset) { idx, opt in
                                let isSelected = curSel.contains(opt.label)
                                if isMulti {
                                    Button {
                                        toggleSelection(qi: qi, label: opt.label)
                                    } label: {
                                        Text(opt.label)
                                            .font(.system(size: 12, weight: .medium))
                                            .padding(.horizontal, 8).padding(.vertical, 4)
                                            .background(isSelected ? Color(hex: "#22D3EE").opacity(0.22) : Color.white.opacity(0.07))
                                            .foregroundColor(isSelected ? Color(hex: "#67E8F9") : Color(hex: "#C5C8CD"))
                                            .clipShape(RoundedRectangle(cornerRadius: 7))
                                            .overlay(RoundedRectangle(cornerRadius: 7).stroke(isSelected ? Color(hex: "#22D3EE").opacity(0.55) : Color.white.opacity(0.1), lineWidth: 1))
                                    }
                                    .buttonStyle(.plain)
                                    .keyboardShortcut(KeyEquivalent(Character(String(idx + 1))), modifiers: [])
                                } else {
                                    SecondaryButton(opt.label) {
                                        selectAndProceed(q: q, qi: qi, label: opt.label, isLast: isLast)
                                    }
                                    .keyboardShortcut(KeyEquivalent(Character(String(idx + 1))), modifiers: [])
                                }
                            }
                            // "Other…" implicit free-text option
                            SecondaryButton("Other…") {
                                if qi < showOther.count { showOther[qi] = true }
                            }
                        }
                    }
                    // Send/Next — only for multi-select (and not while "Other…" field is open)
                    if isMulti && !curOther {
                        PrimaryButton(isLast ? "Send" : "Next") {
                            proceedFromQuestion(q: q, qi: qi, isLast: isLast)
                        }
                        .disabled(!canProceed)
                        .opacity(canProceed ? 1 : 0.4)
                    }
                }
                .padding(.leading, 116)
                .padding(.trailing, 16)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear { resetQuestionState() }
        .onChange(of: state.pendingQuestion) { _, _ in resetQuestionState() }
        .onDisappear { HookServer.shared.releaseQuestionFD() }
    }

    private func resetQuestionState() {
        questionIndex = 0
        let count = state.pendingQuestion?.questions.count ?? 0
        selections = Array(repeating: [], count: count)
        otherTexts = Array(repeating: "", count: count)
        showOther  = Array(repeating: false, count: count)
    }

    private func toggleSelection(qi: Int, label: String) {
        guard qi < selections.count else { return }
        if let i = selections[qi].firstIndex(of: label) {
            selections[qi].remove(at: i)
        } else {
            selections[qi].append(label)
        }
    }

    // Single-select: pick a label and immediately advance/send
    private func selectAndProceed(q: AskQuestion, qi: Int, label: String, isLast: Bool) {
        guard qi < selections.count else { return }
        selections[qi] = [label]
        if isLast { sendAnswers(q: q) } else { withAnimation { questionIndex = qi + 1 } }
    }

    // Multi-select Send/Next button
    private func proceedFromQuestion(q: AskQuestion, qi: Int, isLast: Bool) {
        if isLast { sendAnswers(q: q) } else { withAnimation { questionIndex = qi + 1 } }
    }

    // "Other…" confirm
    private func commitOtherAndProceed(q: AskQuestion, qi: Int, isLast: Bool) {
        let text = qi < otherTexts.count ? otherTexts[qi] : ""
        guard !text.isEmpty else { return }
        if qi < selections.count { selections[qi] = [text] }
        if isLast {
            sendAnswers(q: q)
        } else {
            if qi < showOther.count { showOther[qi] = false }
            withAnimation { questionIndex = qi + 1 }
        }
    }

    private func sendAnswers(q: AskQuestion) {
        let answers = AskQuestion.buildAnswers(questions: q.questions, selections: selections)
        HookServer.shared.sendQuestionAnswers(answers)
    }
}

// MARK: - Error

struct ErrorView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ZStack {
            CardBackground(wash: .red)
            VStack(alignment: .leading, spacing: 5) {
                AgentWho(task: state.focusTask, label: "n8n")
                Text("Workflow stopped.")
                    .font(.system(size: 15, weight: .semibold))
                Text("Gmail node timed out after 30s. Retry or open n8n.")
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#FF8D97"))
                HStack(spacing: 8) {
                    PrimaryButton("Retry") { /* retry */ }
                    SecondaryButton("Open in n8n") { /* open */ }
                }
            }
            .padding(.leading, 116)
            .padding(.trailing, 16)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Finished

struct FinishedView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ZStack {
            CardBackground(wash: .green)
            VStack(alignment: .leading, spacing: 5) {
                AgentWho(task: state.focusTask, label: "Claude Code finished")
                Text({
                    if let fl = state.focusTask?.finalLine { return fl }
                    if let s = state.focusTask?.steps.last(where: { !$0.isDiffStep }) { return s }
                    return "Session finished"
                }())
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(1)
                    .truncationMode(.tail)
                HStack(spacing: 8) {
                    if let pillId = state.focusTask?.id, state.pillRunsInClaudeApp(pillId) {
                        // The session runs in the Claude desktop app, not in a terminal.
                        PrimaryButton("Open Claude") {
                            AgentTarget.bringForward(pillId: pillId)
                            NotificationCenter.default.post(name: .islandCollapse, object: nil)
                        }
                    } else {
                        #if !APPSTORE
                        PrimaryButton("Open terminal") {
                            let terminalBundleIds = ["com.apple.Terminal", "com.googlecode.iterm2", "net.kovidgoyal.kitty", "com.mitchellh.ghostty"]
                            let activated = terminalBundleIds.compactMap { id in
                                NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == id }
                            }.first.map { $0.activate(options: .activateIgnoringOtherApps) }
                            if activated == nil {
                                NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
                            }
                            NotificationCenter.default.post(name: .islandCollapse, object: nil)
                        }
                        #endif
                    }
                    SecondaryButton("OK") {
                        NotificationCenter.default.post(name: .islandCollapse, object: nil)
                    }
                }
            }
            .padding(.leading, 116)
            .padding(.trailing, 16)
            .padding(.vertical, 4)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Diff Card

struct DiffCardView: View {
    let diff: FileDiff
    let onDismiss: () -> Void

    private var allLines: [DiffLine] { diff.hunks.flatMap { $0.lines } }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Button(action: onDismiss) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 8, weight: .medium))
                        Text(diff.name)
                            .font(.system(size: 12, weight: .semibold))
                            .lineLimit(1)
                    }
                    .foregroundColor(Color(hex: "#F5F6F8"))
                }
                .buttonStyle(.plain)
                Spacer(minLength: 2)
                if diff.added > 0 {
                    Text("+\(diff.added)")
                        .font(.system(size: 10, weight: .medium).monospaced())
                        .foregroundColor(Color(hex: "#22C55E"))
                }
                if diff.removed > 0 {
                    Text("−\(diff.removed)")
                        .font(.system(size: 10, weight: .medium).monospaced())
                        .foregroundColor(Color(hex: "#F4505E"))
                }
                Button(action: { openInEditor(diff) }) {
                    Image(systemName: "arrow.up.right")
                        .font(.system(size: 8, weight: .medium))
                        .foregroundColor(Color(hex: "#5F646D"))
                        .frame(width: 14, height: 14)
                        .background(Color.white.opacity(0.07))
                        .clipShape(Circle())
                }
                .buttonStyle(.plain)
            }
            .padding(.top, 6)
            .padding(.bottom, 3)

            // Content
            if diff.tooLarge {
                Text("Diff too large")
                    .font(.system(size: 10.5))
                    .foregroundColor(Color(hex: "#6B7079"))
            } else if allLines.isEmpty {
                Text("No changes")
                    .font(.system(size: 10.5))
                    .foregroundColor(Color(hex: "#6B7079"))
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    VStack(alignment: .leading, spacing: 0) {
                        ForEach(Array(allLines.enumerated()), id: \.offset) { _, line in
                            DiffLineRowView(line: line)
                        }
                    }
                }
            }
        }
        .padding(.leading, 108)
        .padding(.trailing, 10)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onExitCommand { onDismiss() }
    }

    private func openInEditor(_ diff: FileDiff) {
        let path = diff.path
        #if !APPSTORE
        let codePaths = ["/opt/homebrew/bin/code", "/usr/local/bin/code", "/usr/bin/code",
                         "\(NSHomeDirectory())/.nvm/current/bin/code"]
        if let codePath = codePaths.first(where: { FileManager.default.fileExists(atPath: $0) }) {
            let p = Process()
            p.executableURL = URL(fileURLWithPath: codePath)
            // Write: open at line 1; Edit/MultiEdit: open file without line number
            p.arguments = diff.isNewFile ? ["-g", "\(path):1"] : [path]
            try? p.run()
            return
        }
        #endif
        NSWorkspace.shared.open(URL(fileURLWithPath: path))
    }
}

struct DiffLineRowView: View {
    let line: DiffLine

    private var bgColor: Color {
        switch line.kind {
        case .added:   return Color(hex: "#22C55E").opacity(0.12)
        case .removed: return Color(hex: "#F4505E").opacity(0.12)
        case .context: return Color.clear
        }
    }
    private var fgColor: Color {
        switch line.kind {
        case .added:   return Color(hex: "#86EFAC")
        case .removed: return Color(hex: "#FCA5A5")
        case .context: return Color(hex: "#6B7079")
        }
    }
    private var symbol: String {
        switch line.kind {
        case .added:   return "+"
        case .removed: return "−"
        case .context: return " "
        }
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(symbol)
                .font(.system(size: 10.5).monospaced())
                .foregroundColor(line.kind == .added ? Color(hex: "#22C55E") :
                                 line.kind == .removed ? Color(hex: "#F4505E") :
                                 Color(hex: "#454850"))
                .frame(width: 12, alignment: .leading)
            Text(line.text)
                .font(.system(size: 10.5).monospaced())
                .foregroundColor(fgColor)
                .lineLimit(1)
                .truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(bgColor)
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Confused

struct ConfusedView: View {
    var body: some View {
        ZStack {
            CardBackground(wash: .pink)
            VStack(alignment: .leading, spacing: 5) {
                Text("Too many hits at once.").font(.system(size: 15, weight: .semibold))
                Text("Give me a sec — back to work in three seconds.")
                    .font(.system(size: 13)).foregroundColor(Color(hex: "#9398A1"))
            }
            .padding(.leading, 128)
            .padding(.trailing, 18)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// MARK: - Upload (drop zone)

struct UploadView: View {
    @ObservedObject var state: AppState
    @State private var dashPhase: CGFloat = 0
    @State private var breathAngle: Double = 0
    // Timer only runs while this is the active tab — killed on deactivation
    @State private var animTimer: Timer? = nil

    private var borderOpacity: Double {
        let breathe = 0.11 + 0.04 * (sin(breathAngle) * 0.5 + 0.5)
        return state.fileDragOver ? 0.65 : breathe
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(hex: "#0E0F11"))
            RoundedRectangle(cornerRadius: 20)
                .stroke(
                    state.fileDragOver
                        ? Color(hex: "#22C55E").opacity(borderOpacity)
                        : Color.white.opacity(borderOpacity),
                    style: StrokeStyle(lineWidth: 1.5, dash: [6, 5], dashPhase: dashPhase)
                )
            RoundedRectangle(cornerRadius: 20)
                .fill(RadialGradient(
                    colors: [Color(hex: "#22C55E").opacity(state.fileDragOver ? 0.13 : 0), Color.clear],
                    center: .bottom, startRadius: 0, endRadius: 200
                ))
            VStack(alignment: .leading, spacing: 8) {
                Text("Drop your files here")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(state.fileDragOver ? Color(hex: "#34D399") : Color(hex: "#D5D7DB"))
                HStack(spacing: 6) {
                    ForEach(["PDF", "Images", "Code", "Docs"], id: \.self) { label in
                        Text(label)
                            .font(.system(size: 11))
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(Color.white.opacity(0.07))
                            .foregroundColor(Color(hex: "#B9BDC4"))
                            .clipShape(Capsule())
                    }
                }
            }
            .padding(.leading, 196)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .onChange(of: state.view) { _, newView in
            newView == .upload ? startTimer() : stopTimer()
        }
        .onAppear {
            if state.view == .upload { startTimer() }
        }
        .onDisappear { stopTimer() }
    }

    private func startTimer() {
        guard animTimer == nil else { return }
        // 20 fps — smooth enough for slow dash, 3× lighter than 60fps
        animTimer = Timer.scheduledTimer(withTimeInterval: 1.0/20.0, repeats: true) { _ in
            dashPhase  += 1.0          // 20 pt/s march
            breathAngle += 0.9 / 20.0  // advance sin phase at 0.9 rad/s
        }
    }

    private func stopTimer() {
        animTimer?.invalidate()
        animTimer = nil
    }
}

// MARK: - Uploading

struct UploadingView: View {
    @ObservedObject var state: AppState

    // Bar geometry in content coords (content has 10pt H padding each side).
    // Island bar: left=36, right=562 (640-78), width=526.
    // Content bar: left=26, width=526.
    // barTop=58 → island y = content_start(42)+58 = 100; bot cy=103 (center = barTop+3).
    private let barLeft: CGFloat  = 26
    private let barWidth: CGFloat = 526
    private let barTop: CGFloat   = 58

    var body: some View {
        // TimelineView fires at display refresh rate — progress derived from elapsed wall time,
        // not from @Published uploadProgress (which only flips to 1.0 at completion).
        // Paused while no upload runs (`uploadStartTime` is nil, so every frame is the same t = 0): the island stacks this view under the others and it ticked at the display's rate all the time.
        // `uploadStartTime` is always set before `state.view` changes to .uploading, and cleared in the same turn as the change away, so the body is evaluated again with the new value.
        TimelineView(.animation(paused: state.uploadStartTime == nil)) { tl in
            let elapsed: Double = {
                guard let start = state.uploadStartTime else { return 0 }
                return tl.date.timeIntervalSince(start)
            }()
            let t        = min(1.0, max(0, elapsed / state.uploadDuration))
            let progress = CGFloat(t * (2 - t))          // ease-out quad
            let fillWidth = max(0, barWidth * progress)
            let isDone   = state.uploadProgress >= 0.999  // only true after handle() sets it

            ZStack(alignment: .topLeading) {
                // Background: dark base
                RoundedRectangle(cornerRadius: 20)
                    .fill(Color(hex: "#141518"))

                // Permanent green radial wash — brighter at completion
                RoundedRectangle(cornerRadius: 20)
                    .fill(RadialGradient(
                        colors: [Color(hex: "#34D399").opacity(isDone ? 0.28 : 0.14), Color.clear],
                        center: UnitPoint(x: 0.5, y: 1.4),
                        startRadius: 0,
                        endRadius: 260
                    ))

                // Bar track
                RoundedRectangle(cornerRadius: 3)
                    .fill(Color.white.opacity(0.09))
                    .frame(width: barWidth, height: 6)
                    .offset(x: barLeft, y: barTop)

                // Bar fill
                RoundedRectangle(cornerRadius: 3)
                    .fill(LinearGradient(
                        colors: [Color(hex: "#1FA87A"), Color(hex: "#34D399")],
                        startPoint: .leading, endPoint: .trailing
                    ))
                    .frame(width: fillWidth, height: 6)
                    .offset(x: barLeft, y: barTop)

                // Glow trail behind dot leading edge
                if progress > 0.01 {
                    Ellipse()
                        .fill(Color(hex: "#6EE7B7").opacity(0.45))
                        .frame(width: 28, height: 12)
                        .blur(radius: 5)
                        .offset(x: barLeft + fillWidth - 14, y: barTop - 3)
                }

                // Text row — filename + % (above bar)
                HStack(spacing: 0) {
                    if isDone {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 12))
                            .foregroundColor(Color(hex: "#34D399"))
                        Text("  \(state.droppedFile?.name ?? "File")")
                            .font(.system(size: 12.5, weight: .semibold))
                            .foregroundColor(Color(hex: "#34D399"))
                            .lineLimit(1).truncationMode(.middle)
                    } else {
                        Text("Uploading \(state.droppedFile?.name ?? "file")")
                            .font(.system(size: 12.5))
                            .foregroundColor(Color(hex: "#A9ADB5"))
                            .lineLimit(1).truncationMode(.middle)
                        Spacer(minLength: 8)
                        Text("\(Int(progress * 100)) %")
                            .font(.system(size: 12.5, weight: .medium))
                            .foregroundColor(Color(hex: "#A9ADB5"))
                            .monospacedDigit()
                    }
                }
                .frame(width: barWidth)
                .offset(x: barLeft, y: barTop - 22)

                // Subtle top border (same as CardBackground)
                RoundedRectangle(cornerRadius: 20)
                    .stroke(Color.white.opacity(0.035), lineWidth: 1)
            }
        }
    }
}

// MARK: - Choose

struct ChooseView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ZStack(alignment: .leading) {
            CardBackground(wash: nil)
            VStack(alignment: .leading, spacing: 8) {
                let fileName = state.droppedFile?.name ?? "file"
                (Text(fileName).font(.system(size: 14, weight: .semibold)) + Text(" is ready.").font(.system(size: 14, weight: .semibold)))
                Text("What do you want to do with it?").font(.system(size: 12.5)).foregroundColor(Color(hex: "#9398A1"))
                HStack(spacing: 8) {
                    PrimaryButton("Ask a question") { state.view = .prompt }
                    SecondaryButton("Send by email") { state.view = .mail }
                    if let reader = state.dropReaderLine {
                        Text(reader)
                            .font(.system(size: 12.5))
                            .foregroundColor(Color(hex: "#9398A1"))
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                }
            }
            .padding(.leading, 98)
            .padding(.trailing, 18)
        }
    }
}

// MARK: - Mail

struct MailView: View {
    @ObservedObject var state: AppState
    @State private var to: String = ""
    @State private var subject: String = ""
    @State private var bodyText: String = ""
    @State private var statusMsg: String = ""
    @State private var isSending = false

    var body: some View {
        ZStack(alignment: .leading) {
            CardBackground(wash: nil)
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Text("New email").font(.system(size: 12, weight: .semibold))
                    if let name = state.droppedFile?.name {
                        Text("with").font(.system(size: 12)).foregroundColor(Color(hex: "#8E939C"))
                        Text(name).font(.system(size: 12)).foregroundColor(Color(hex: "#8E939C"))
                            .lineLimit(1).truncationMode(.middle)
                    }
                }

                MailField(label: "To", placeholder: "address@example.com", text: $to)
                MailField(label: "Subject", placeholder: state.droppedFile?.name ?? "Subject", text: $subject)

                // Body — TextEditor scrolls internally when text overflows
                TextEditor(text: $bodyText)
                    .scrollContentBackground(.hidden)
                    .font(.system(size: 12.5))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                    .frame(height: 44)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(Color.white.opacity(0.06))
                    .clipShape(RoundedRectangle(cornerRadius: 10))

                if !statusMsg.isEmpty {
                    Text(statusMsg).font(.system(size: 11)).foregroundColor(Color(hex: "#FF8D97"))
                }

                HStack(spacing: 8) {
                    PrimaryButton(isSending ? "Sending…" : "Send") {
                        guard !isSending else { return }
                        sendMail()
                    }
                    SecondaryButton("Cancel") { state.view = .choose }
                }
            }
            .padding(.leading, 92)
            .padding(.trailing, 18)
            .padding(.vertical, 8)
        }
        .onAppear { subject = state.droppedFile?.name ?? "" }
    }

    private func sendMail() {
        guard !to.isEmpty else { statusMsg = "Missing recipient."; return }
        let subj = subject.isEmpty ? (state.droppedFile?.name ?? "File") : subject

        // Prefer Resend if API key + sender address are configured
        let apiKey  = KeychainStore.shared.get("resend-api-key")
        let fromAddr = KeychainStore.shared.get("resend-from")

        if let apiKey, let fromAddr {
            isSending = true
            statusMsg = ""
            let recipient = to
            let msgBody  = bodyText
            let fileURL  = state.droppedFile?.url
            Task {
                let ok = await sendViaResend(apiKey: apiKey, from: fromAddr,
                                              to: recipient, subject: subj,
                                              body: msgBody, fileURL: fileURL)
                await MainActor.run {
                    isSending = false
                    if ok { onSuccess(recipient: recipient) }
                    else  { statusMsg = "Resend error — check API key & sender." }
                }
            }
        } else if apiKey != nil && fromAddr == nil {
            // API key set but no sender — guide user instead of silent fallback
            statusMsg = "Set sender address in Settings."
        } else {
            // No Resend — fallback to Mail
            sendViaAppleMail(to: to, subject: subj)
        }
    }

    private func sendViaResend(apiKey: String, from: String, to: String,
                                subject: String, body: String, fileURL: URL?) async -> Bool {
        guard let url = URL(string: "https://api.resend.com/emails") else { return false }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        var payload: [String: Any] = [
            "from": from,
            "to": [to],
            "subject": subject,
            "text": body.isEmpty ? " " : body
        ]
        if let fileURL, let data = try? Data(contentsOf: fileURL) {
            payload["attachments"] = [[
                "filename": fileURL.lastPathComponent,
                "content": data.base64EncodedString()
            ]]
        }
        guard let httpBody = try? JSONSerialization.data(withJSONObject: payload) else { return false }
        request.httpBody = httpBody
        guard let (_, response) = try? await URLSession.shared.data(for: request) else { return false }
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        if code == 200 || code == 201 { return true }
        print("[Resend] HTTP \(code)")
        return false
    }

    private func sendViaAppleMail(to: String, subject: String) {
        #if APPSTORE
        // App Store: no AppleScript — use NSSharingService to compose (user sends manually)
        guard let service = NSSharingService(named: .composeEmail) else {
            statusMsg = "Mail not available."
            return
        }
        var items: [Any] = [bodyText.isEmpty ? " " : bodyText]
        if let url = state.droppedFile?.url,
           FileManager.default.fileExists(atPath: url.path) {
            items.append(url)
        }
        service.recipients = [to]
        service.subject = subject
        service.perform(withItems: items)
        onSuccess(recipient: to)
        #else
        func asEscape(_ s: String) -> String {
            s.replacingOccurrences(of: "\\", with: "\\\\")
             .replacingOccurrences(of: "\"", with: "\\\"")
        }

        let bodyLines = bodyText.isEmpty ? [""] : bodyText.components(separatedBy: "\n")
        let bodyExpr = bodyLines.map { "\"\(asEscape($0))\"" }.joined(separator: " & linefeed & ")
            + " & return & return"

        let attachBlock: String
        if let url = state.droppedFile?.url,
           FileManager.default.fileExists(atPath: url.path) {
            let escapedPath = asEscape(url.path)
            attachBlock = "make new attachment with properties {file name:(POSIX file \"\(escapedPath)\")} at after the last paragraph of content"
        } else {
            attachBlock = ""
        }

        let script = """
        tell application "Mail"
            set m to make new outgoing message with properties {subject:"\(asEscape(subject))", visible:false}
            set content of m to \(bodyExpr)
            tell m
                make new to recipient at end of to recipients with properties {address:"\(asEscape(to))"}
                \(attachBlock)
            end tell
            delay 1
            send m
        end tell
        """
        var err: NSDictionary?
        NSAppleScript(source: script)?.executeAndReturnError(&err)
        if err == nil { onSuccess(recipient: to) }
        else { statusMsg = "Mail error: \(err?["NSAppleScriptErrorMessage"] as? String ?? "unknown")" }
        #endif
    }

    private func onSuccess(recipient: String) {
        SoundEngine.shared.play("send")
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.wink)
        state.noteMessage = "Email sent to \(recipient)."
        state.view = .note
        DispatchQueue.main.asyncAfter(deadline: .now() + 2) {
            NotificationCenter.default.post(name: .islandCollapse, object: nil)
        }
    }
}

// MARK: - Prompt (chat)

struct PromptView: View {
    @ObservedObject var state: AppState
    /// True in the pop-out window (CompanionWindowController): no cat gutter and no card wash, the window's own keys instead of the island's.
    var inWindow = false
    /// Exactly one PromptView reacts at a time: the window's while the chat is popped out, the island's otherwise (every island view is alive at once, and the window's stays alive after it closes).
    private var isLive: Bool { inWindow == state.chatPoppedOut }
    @State private var text: String = ""
    @FocusState private var focused: Bool
    @State private var showModelPicker = false

    var body: some View {
        ZStack(alignment: .leading) {
            if inWindow { Color(hex: "#141518") } else { CardBackground(wash: .indigo) }

            VStack(alignment: .leading, spacing: 6) {
                if let ctx = state.promptContext {
                    ContextChip(context: ctx).padding(.top, 4)
                }

                switch state.chatPane {
                case .chat:
                    if !state.chatHistory.isEmpty {
                        ScrollViewReader { proxy in
                            ScrollView(.vertical, showsIndicators: false) {
                                VStack(alignment: .leading, spacing: 6) {
                                    ForEach(state.chatHistory) { msg in
                                        ChatBubble(message: msg).id(msg.id)
                                    }
                                    #if !APPSTORE
                                    if let approval = state.chatApproval { ChatApprovalCard(approval: approval).id("approval") }
                                    #endif
                                    if state.stateOverride != nil || state.chatNotice != nil {
                                        HStack(spacing: 8) {
                                            if state.stateOverride != nil { TypingDotsView() }
                                            if let notice = state.chatNotice {
                                                Text(notice.text)
                                                    .font(.system(size: 10.5))
                                                    .foregroundColor(Color(hex: "#7B8089"))
                                                if notice.cancellable {
                                                    Button("Cancel") { ClaudeService.shared.stop() }
                                                        .font(.system(size: 10.5, weight: .medium))
                                                        .foregroundColor(Color(hex: "#C8CDD4"))
                                                        .buttonStyle(.plain)
                                                }
                                            }
                                            Spacer(minLength: 32)
                                        }
                                        .id("typing")
                                    }
                                }
                                .padding(.vertical, 2)
                            }
                            .onChange(of: state.chatHistory) { _, _ in
                                if let last = state.chatHistory.last(where: { !$0.content.isEmpty }) {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                            #if !APPSTORE
                            .onChange(of: state.chatApproval) { _, v in
                                if v != nil { withAnimation { proxy.scrollTo("approval", anchor: .bottom) } }
                            }
                            #endif
                            .onChange(of: state.stateOverride) { _, v in
                                if v != nil {
                                    withAnimation { proxy.scrollTo("typing", anchor: .bottom) }
                                } else if let last = state.chatHistory.last(where: { !$0.content.isEmpty }) {
                                    withAnimation { proxy.scrollTo(last.id, anchor: .bottom) }
                                }
                            }
                            .onAppear {
                                if let last = state.chatHistory.last {
                                    proxy.scrollTo(last.id, anchor: .bottom)
                                }
                            }
                        }
                        .frame(maxHeight: .infinity)
                    } else if AIService.shared.resolve(ClaudeService.shared.currentFeature).primary == nil {
                        AIEmptyStateView(state: state)
                            .frame(maxHeight: .infinity)
                    } else {
                        Spacer()
                        SidekickStatusChip(state: state)   // the empty chat's one chip: asking it is answered on this Mac (SidekickChat)
                    }
                case .conversations:
                    ConversationListPane(state: state)
                        .frame(maxHeight: .infinity)
                }

                HStack(spacing: 0) {
                    Spacer()
                    ChatMenuButton(state: state, newChat: newConversation, inWindow: inWindow, fieldText: text).padding(.trailing, 6)
                    #if !APPSTORE
                    if AIService.shared.resolve(ClaudeService.shared.currentFeature).primary?.provider == .claudeCode {
                        ClaudeLevelChip(state: state).padding(.trailing, 6)
                    }
                    #endif
                    Button {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.75)) {
                            showModelPicker.toggle()
                        }
                    } label: {
                        let chip = AIService.shared.chip(ClaudeService.shared.currentFeature)
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color(hex: chip.accentHex))
                                .frame(width: 6, height: 6)
                            Text(chip.label)
                                .font(.system(size: 10.5, weight: .medium))
                                .foregroundColor(Color(hex: "#7B8089"))
                            Image(systemName: "chevron.up.chevron.down")
                                .font(.system(size: 8))
                                .foregroundColor(Color(hex: "#5C6370"))
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 4)
                        .background(Color.white.opacity(0.06))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                    .popover(isPresented: $showModelPicker, arrowEdge: .bottom) {
                        ModelPickerView(state: state, isPresented: $showModelPicker)
                            .frame(width: 300)
                    }
                }
                .padding(.horizontal, 10)

                // A Fix or Rewrite result, and the chip for an image waiting to go out; only the live chat view draws them (the island's and the window's share the state).
                if isLive, let result = state.quickResult { QuickResultCard(state: state, result: result) }
                if isLive, ClaudeService.shared.pendingImage != nil, let image = ClaudeService.shared.pendingImage { ExplainScreenshotChip(image: image) }

                HStack(spacing: 8) {
                    TextField(state.chatHistory.isEmpty ? "Ask me anything…" : "Continue…", text: $text)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                        .focused($focused)
                        .onSubmit { sendMessage() }

                    if state.chatStreaming {
                        Button { ClaudeService.shared.stop() } label: {
                            Image(systemName: "stop.fill")
                                .font(.system(size: 9, weight: .semibold))
                                .foregroundColor(Color(hex: "#0B0C0E"))
                        }
                        .buttonStyle(SendButtonStyle())
                        .accessibilityLabel("Stop")
                    } else {
                        Button(action: sendMessage) {
                            Image(systemName: "arrow.up")
                                .font(.system(size: 11, weight: .semibold))
                                .foregroundColor(Color(hex: "#0B0C0E"))
                        }
                        .buttonStyle(SendButtonStyle())
                        .disabled(text.isEmpty)
                    }
                }
                .padding(.horizontal, 10).padding(.vertical, 6)
                .background(Color.white.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 12))
                .simultaneousGesture(TapGesture().onEnded { focused = true })
            }
            .padding(.leading, inWindow ? 16 : 84)
            .padding(.trailing, 16)
            .padding(.top, 12)
            .padding(.bottom, 14)
        }
        .padding(.bottom, inWindow ? 0 : 10)
        .background {
            // The window has no island panel to catch ⌘K (a new chat) and no menu bar to catch ⌘W (back to the island): two key equivalents that exist only there.
            if inWindow {
                Group {
                    Button("") { newConversation() }.keyboardShortcut("k", modifiers: .command)
                    Button("") { CompanionWindowController.shared.bringBack() }.keyboardShortcut("w", modifiers: .command)
                }
                .frame(width: 0, height: 0).opacity(0).accessibilityHidden(true)
            }
        }
        .onAppear {
            focused = true
            AIService.shared.prewarm(ClaudeService.shared.currentFeature)
            #if !APPSTORE
            // Before a chat's first message: is Claude Code there, and signed in? (Never on a timer.)
            if state.claudeCodeEnabled, state.chatHistory.isEmpty { Task { await AIService.shared.refreshClaudeStatus() } }
            #endif
        }
        .onChange(of: state.openModelPicker) { _, open in
            if open, isLive {
                showModelPicker = true
                state.openModelPicker = false
            }
        }
        .onChange(of: state.chatStreaming) { _, streaming in
            if !streaming, isLive { focused = true }
        }
        // ⌘↩ sends, ⌘K starts a new conversation (every island view is alive at once: only the live chat answers)
        .onReceive(NotificationCenter.default.publisher(for: .islandSendMessage)) { _ in
            guard isLive, state.view == .prompt else { return }
            sendMessage()
        }
        .onReceive(NotificationCenter.default.publisher(for: .islandNewConversation)) { _ in
            guard isLive, state.view == .prompt else { return }
            newConversation()
        }
    }

    private func sendMessage() {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty, !state.chatStreaming else { return }
        text = ""
        focused = false
        state.chatPane = .chat   // a message sent from the list streams on the chat, not unseen behind the list
        ClaudeService.shared.send(query: query, context: state.promptContext, state: state)
    }

    /// ⌘K and the menu's New chat: a new chat, shown on the chat pane.
    private func newConversation() {
        text = ""
        ClaudeService.shared.clearConversation(state: state)
        state.chatPane = .chat
        focused = true
    }
}


// MARK: - Model / provider picker

/// Wrapping horizontal flow layout — used by ModelPickerView and QuestionView.
struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) -> CGSize {
        let r = rows(maxW: proposal.replacingUnspecifiedDimensions().width, subviews: subviews)
        return r.size
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout Void) {
        let r = rows(maxW: bounds.width, subviews: subviews)
        for (idx, pt) in r.placements.enumerated() {
            subviews[idx].place(at: CGPoint(x: bounds.minX + pt.x, y: bounds.minY + pt.y), proposal: .unspecified)
        }
    }
    private func rows(maxW: CGFloat, subviews: Subviews) -> (size: CGSize, placements: [(x: CGFloat, y: CGFloat)]) {
        var x: CGFloat = 0, y: CGFloat = 0, lineH: CGFloat = 0, maxX: CGFloat = 0
        var pts: [(x: CGFloat, y: CGFloat)] = []
        for sv in subviews {
            let sz = sv.sizeThatFits(.unspecified)
            if x + sz.width > maxW, x > 0 { x = 0; y += lineH + spacing; lineH = 0 }
            pts.append((x: x, y: y))
            x += sz.width + spacing
            lineH = max(lineH, sz.height)
            maxX = max(maxX, x - spacing)
        }
        return (CGSize(width: max(maxX, 0), height: y + lineH), pts)
    }
}

struct ModelPickerView: View {
    @ObservedObject var state: AppState
    @Binding var isPresented: Bool

    /// A chip in the picker: Auto, a cloud provider, a local server, or Apple's model.
    enum Source: Hashable {
        case auto
        case cloud(AIProviderID)
        case server(String)
        case apple
    }

    private var feature: AIFeature { ClaudeService.shared.currentFeature }

    private var selected: Source {
        guard case .explicit(let ref) = state.choice(for: feature) else { return .auto }
        if ref.provider.isCloud { return .cloud(ref.provider) }
        if ref.provider == .apple { return .apple }
        return .server(ref.serverID ?? ref.provider.rawValue)
    }

    private var sources: [Source] {
        var list: [Source] = [.auto] + AICatalog.cloudOrder.map { .cloud($0) }
        #if !APPSTORE
        if state.claudeCodeEnabled, state.claudeCodeStatus.isReady { list.insert(.cloud(.claudeCode), at: 1) }
        if state.codexStatus.isReady { list.insert(.cloud(.codexPlan), at: list.firstIndex(of: .cloud(.anthropic)) ?? 1) }
        #endif
        list += state.localServers.filter(\.isReady).map { .server($0.serverID) }
        if state.appleStatus == .ready { list.append(.apple) }
        if !list.contains(selected) { list.append(selected) }
        return list
    }

    private func name(_ s: Source) -> String {
        switch s {
        case .auto: "Auto"
        case .cloud(let p):
            switch p {
            case .claudeCode: "Claude · your plan"
            case .codexPlan: "OpenAI plan"
            default: ChatProvider(p).displayName
            }
        case .server(let id): state.localServers.first { $0.serverID == id }?.name ?? "Local server"
        case .apple: "Apple on-device"
        }
    }

    private func accent(_ s: Source) -> String {
        switch s {
        case .auto: "#A78BFA"
        case .cloud(let p): ChatProvider(p).accentHex
        case .server(let id): ChatProvider(state.localServers.first { $0.serverID == id }?.provider ?? .custom).accentHex
        case .apple: ChatProvider.apple.accentHex
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ChipFlowLayout(spacing: 6) {
                ForEach(sources, id: \.self) { source in
                    Button { pick(source) } label: {
                        HStack(spacing: 5) {
                            Circle()
                                .fill(Color(hex: accent(source)))
                                .frame(width: 7, height: 7)
                            Text(name(source))
                                .font(.system(size: 12, weight: selected == source ? .semibold : .regular))
                        }
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(selected == source
                                    ? Color(hex: accent(source)).opacity(0.18)
                                    : Color.white.opacity(0.06))
                        .overlay(Capsule().stroke(
                            selected == source
                                ? Color(hex: accent(source)).opacity(0.5)
                                : Color.white.opacity(0.1),
                            lineWidth: 1))
                        .clipShape(Capsule())
                    }
                    .buttonStyle(.plain)
                }
            }

            Divider().opacity(0.2)

            modelListView
                .frame(height: 260, alignment: .top)
        }
        .padding(14)
        .background(Color(hex: "#16171B"))
        .onAppear {
            Task { await AIService.shared.discover() }
            if case .cloud(let p) = selected { state.fetchModelsIfNeeded(for: p) }
            #if !APPSTORE
            // When the picker opens: is Codex there, and signed in? (Never on a timer.)
            Task { await AIService.shared.refreshCodexStatus() }
            #endif
        }
    }

    /// Choosing a chip switches at once, keeping that provider's or server's remembered model.
    private func pick(_ source: Source) {
        guard source != selected else { return }
        let setting: FeatureSetting
        switch source {
        case .auto:
            setting = .auto
        case .cloud(let p):
            setting = .explicit(ModelRef(provider: p, model: AIService.shared.cloudModel(p)))
            state.fetchModelsIfNeeded(for: p)
        case .server(let id):
            guard let server = state.localServers.first(where: { $0.serverID == id }),
                  let model = AIService.shared.localModel(server) else { return }
            setting = .explicit(ModelRef(provider: server.provider, model: model, serverID: server.serverID))
        case .apple:
            setting = .explicit(ModelRef(provider: .apple, model: "system"))
        }
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
            state.setChoice(setting, for: feature)
        }
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.surprised)
        SoundEngine.shared.play("pop")
    }

    private var currentModel: String? {
        if case .explicit(let ref) = state.choice(for: feature) { return ref.model }
        return nil
    }

    @ViewBuilder
    private var modelListView: some View {
        switch selected {
        case .auto:
            Text(AIService.shared.resolutionLine(feature))
                .font(.system(size: 12))
                .foregroundColor(Color(hex: "#8A8F98"))
                .padding(.vertical, 4)
        case .cloud(let p):
            if p == .codexPlan {
                // The row names no Codex: that word is for the chip's fallback and the notes (labels.json).
                modelRows([("", "OpenAI's default model")], accent: ChatProvider.codexPlan.accentHex) { ModelRef(provider: .codexPlan, model: $0) }
            } else if p == .claudeCode {
                modelRows(ClaudeCodeModel.allCases.map { ($0.rawValue, "Claude \($0.label)") },
                          accent: ChatProvider.claudeCode.accentHex) { ModelRef(provider: .claudeCode, model: $0) }
            } else if state.loadingProviderModels.contains(p) {
                HStack(spacing: 8) {
                    ProgressView().scaleEffect(0.7)
                    Text("Loading models…")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#8A8F98"))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.vertical, 4)
            } else if let error = state.providerModelFetchError[p] {
                Text(error)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#8A8F98"))
                    .padding(.vertical, 4)
            } else if let models = state.fetchedProviderModels[p] {
                modelRows(models.map { ($0.id, $0.label ?? $0.id) }, accent: ChatProvider(p).accentHex) { id in
                    ModelRef(provider: p, model: id)
                }
            }
        case .server(let id):
            if let server = state.localServers.first(where: { $0.serverID == id }) {
                modelRows(server.models.map { ($0.id, $0.id) }, accent: ChatProvider(server.provider).accentHex) { model in
                    ModelRef(provider: server.provider, model: model, serverID: server.serverID)
                }
            }
        case .apple:
            modelRows([("system", "Apple on-device")], accent: ChatProvider.apple.accentHex) { _ in
                ModelRef(provider: .apple, model: "system")
            }
        }
    }

    private func modelRows(_ models: [(id: String, label: String)], accent: String,
                           ref: @escaping (String) -> ModelRef) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 2) {
                ForEach(models, id: \.id) { model in
                    let isCurrent = currentModel == model.id
                    Button {
                        state.setChoice(.explicit(ref(model.id)), for: feature)
                        isPresented = false
                        SoundEngine.shared.play("blip")
                    } label: {
                        HStack {
                            Text(model.label)
                                .font(.system(size: 12))
                                .foregroundColor(isCurrent ? Color(hex: accent) : Color(hex: "#C8CDD4"))
                            Spacer()
                            if isCurrent {
                                Image(systemName: "checkmark")
                                    .font(.system(size: 10, weight: .semibold))
                                    .foregroundColor(Color(hex: accent))
                            }
                        }
                        .padding(.horizontal, 8)
                        .padding(.vertical, 6)
                        .background(isCurrent ? Color(hex: accent).opacity(0.1) : Color.clear)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                    }
                    .buttonStyle(.plain)
                }
            }
        }
    }
}

struct ChatBubble: View {
    let message: ChatMessage

    var body: some View {
        if !message.content.isEmpty || !message.steps.isEmpty {
            HStack(alignment: .top) {
                if message.role == .user {
                    Spacer(minLength: 32)
                    // A quick Explain's selection is stored inside its <text> wrapper (the model's labelling); the bubble shows only the selection.
                    Text(CompanionChatRules.titleSource(message.content) ?? message.content)
                        .font(.system(size: 12.5))
                        .foregroundColor(Color(hex: "#F1F2F4"))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                        .padding(.horizontal, 10).padding(.vertical, 6)
                        .background(Color.white.opacity(0.13))
                        .clipShape(RoundedRectangle(cornerRadius: 12))
                } else {
                    VStack(alignment: .leading, spacing: 4) {
                        #if !APPSTORE
                        if !message.steps.isEmpty { ClaudeStepsView(steps: message.steps) }
                        #endif
                        if !message.content.isEmpty { ChatMarkdownView(markdown: message.content) }
                        ReplyFooter(message: message)
                    }
                    Spacer(minLength: 8)
                }
            }
        }
    }
}

/// Under a reply: a quiet notice, web-search sources, then `cloud · model` (and Continue · Retry
/// when the stream was cut). Same small grey type as the model chip.
struct ReplyFooter: View {
    let message: ChatMessage

    private static let grey = Color(hex: "#7B8089")

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            if let notice = message.notice {
                Text(notice)
                    .font(.system(size: 10.5))
                    .foregroundColor(Self.grey)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !message.sources.isEmpty {
                ChipFlowLayout(spacing: 8) {
                    ForEach(message.sources, id: \.url) { source in
                        if let url = safeWebURL(source.url) {
                            Link(source.title.isEmpty ? (url.host ?? source.url) : source.title, destination: url)
                                .font(.system(size: 10.5))
                                .foregroundColor(Color(hex: "#A5B4FC"))
                                .lineLimit(1)
                        }
                    }
                }
            }
            if message.caption != nil || message.interrupted {
                HStack(spacing: 6) {
                    if let caption = message.caption {
                        Text(caption).font(.system(size: 10.5)).foregroundColor(Self.grey)
                    }
                    if message.interrupted {
                        Text(AIMessages.interrupted).font(.system(size: 10.5)).foregroundColor(Self.grey)
                        Button("Continue") { ClaudeService.shared.continueReply(state: .shared) }
                        Text("·").foregroundColor(Self.grey)
                        Button("Retry") { ClaudeService.shared.retryLast(state: .shared) }
                    }
                }
                .font(.system(size: 10.5, weight: .medium))
                .foregroundColor(Color(hex: "#C8CDD4"))
                .buttonStyle(.plain)
            }
        }
        .environment(\.openURL, OpenURLAction { url in
            guard let safe = safeWebURL(url.absoluteString) else { return .discarded }
            NSWorkspace.shared.open(safe)
            return .handled
        })
    }
}

/// No key and no model: the two ways to give the cat a brain.
struct AIEmptyStateView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(AIMessages.emptyStateTitle).font(.system(size: 13, weight: .semibold))
            HStack(spacing: 8) {
                PrimaryButton("Add a cloud key") {
                    NotificationCenter.default.post(name: .openFullSettings, object: "chat/keys")
                }
                SecondaryButton("Use a local model") {
                    showNote(AIMessages.localGuide, action: nil, markdown: true, state: state)
                }
                #if !APPSTORE
                SecondaryButton("Connect Claude") {
                    NotificationCenter.default.post(name: .openFullSettings, object: "chat/yourai")
                }
                #endif
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// Shows a note with its optional button (Open Settings, billing page, guide, choose model).
@MainActor
func showNote(_ message: String, action: AIAction?, markdown: Bool = false, state: AppState) {
    state.noteMessage = message
    state.noteAction = (action != nil || markdown)
        ? NoteAction(message: message, action: action ?? .openGuide, markdown: markdown) : nil
    state.view = .note
}

struct TypingDotsView: View {
    @State private var phase = false

    var body: some View {
        HStack(spacing: 4) {
            ForEach(0..<3, id: \.self) { i in
                Circle()
                    .fill(Color(hex: "#6B7079"))
                    .frame(width: 5, height: 5)
                    .scaleEffect(phase ? 1.2 : 0.6)
                    .animation(
                        .easeInOut(duration: 0.45).repeatForever().delay(Double(i) * 0.14),
                        value: phase
                    )
            }
        }
        .padding(.horizontal, 2).padding(.vertical, 4)
        .onAppear { phase = true }
    }
}

// MARK: - Searching

struct SearchingView: View {
    @ObservedObject var state: AppState

    var label: String {
        switch state.promptContext {
        case .window(_, let title, _): return "Claude is reading \(title)…"
        case .file(let name, _): return "Claude is reading \(name)…"
        case nil: return "Claude is searching…"
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            CardBackground(wash: .indigo)

            VStack(alignment: .leading, spacing: 8) {
                if let ctx = state.promptContext {
                    ContextChip(context: ctx)
                }
                ShimmeringText(label)
                    .font(.system(size: 13.5))
            }
            .padding(.leading, 84)
            .padding(.trailing, 16)
        }
    }
}

// MARK: - Result

struct ResultView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ZStack(alignment: .leading) {
            CardBackground(wash: .green)

            if let result = state.searchResult {
                VStack(alignment: .leading, spacing: 7) {
                    Text(result.title)
                        .font(.system(size: 15, weight: .semibold))

                    VStack(spacing: 4) {
                        ForEach(result.items.prefix(3), id: \.label) { item in
                            HStack {
                                Text(item.label).font(.system(size: 12.5, weight: .semibold))
                                Spacer()
                                Text(item.detail).font(.system(size: 12.5)).foregroundColor(Color(hex: "#9398A1"))
                            }
                            .padding(.horizontal, 10).padding(.vertical, 6)
                            .background(Color.white.opacity(0.05))
                            .clipShape(RoundedRectangle(cornerRadius: 10))
                        }
                    }

                    if let note = result.note {
                        Text(note).font(.system(size: 11)).foregroundColor(Color(hex: "#6E737C"))
                    }

                    HStack(spacing: 8) {
                        // The URL comes from the model, which may have read attacker-controlled
                        // files or pages: only plain web links may leave the app.
                        let openURL = safeWebURL(result.items.first?.url)
                        PrimaryButton("Open") {
                            if let openURL { NSWorkspace.shared.open(openURL) }
                        }
                        .disabled(openURL == nil)
                        .help(openURL?.absoluteString ?? "")
                        SecondaryButton("Copy") {
                            let text = result.items.map { "\($0.label): \($0.detail)" }.joined(separator: "\n")
                            NSPasteboard.general.clearContents()
                            NSPasteboard.general.setString(text, forType: .string)
                        }
                        SecondaryButton("Close") { state.view = state.tasks.isEmpty ? .empty : .overview }
                    }
                }
                .padding(.leading, 84)
                .padding(.trailing, 16)
            }
        }
    }
}

// MARK: - Note (short message, auto-closes)

struct NoteView: View {
    @ObservedObject var state: AppState

    /// The action made for this exact message (other notes never show a stale button).
    private var currentAction: NoteAction? {
        guard let a = state.noteAction, a.message == state.noteMessage else { return nil }
        return a
    }

    static func title(_ action: AIAction) -> String {
        switch action {
        case .openSettings: "Open Settings"
        case .openBilling: "Open billing page"
        case .openGuide: "Open guide"
        case .chooseModel: "Choose model"
        case .signInClaude: "Sign in"
        case .installClaude: "How to install"
        case .updateClaude: "How to update"
        case .installGit: "Get Git for Windows"
        case .installCodex: "How to install"
        case .updateCodex: "How to update"
        case .tryAgain: "Try again"
        }
    }

    private func perform(_ action: AIAction) {
        switch action {
        case .openSettings:
            NotificationCenter.default.post(name: .openFullSettings, object: "chat")
        case .openBilling(let url):
            if let safe = safeWebURL(url.absoluteString) { NSWorkspace.shared.open(safe) }
        case .openGuide:
            showNote(AIMessages.localGuide, action: nil, markdown: true, state: state)
        case .chooseModel:
            state.stateOverride = nil
            state.view = .prompt
            state.openModelPicker = true
        case .signInClaude:
            #if !APPSTORE
            ClaudeCodeActions.signIn()
            #endif
        case .installClaude, .updateClaude:
            #if !APPSTORE
            ClaudeCodeActions.openInstallGuide()
            #endif
        case .installGit:
            if let url = URL(string: "https://git-scm.com/downloads/win") { NSWorkspace.shared.open(url) }
        case .installCodex, .updateCodex:
            #if !APPSTORE
            if let url = URL(string: CodexLocator.installGuide) { NSWorkspace.shared.open(url) }
            #endif
        case .tryAgain:
            state.stateOverride = nil
            state.view = .prompt
            ClaudeService.shared.resendLastMessage(state: state)
        }
    }

    var body: some View {
        ZStack(alignment: .leading) {
            CardBackground(wash: nil)
            VStack(alignment: .leading, spacing: 4) {
                if let note = currentAction, note.markdown {
                    Text(.init(note.message))
                        .font(.system(size: 13, weight: .semibold))
                        .tint(Color(hex: "#A5B4FC"))
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text(state.noteMessage ?? "")
                        .font(.system(size: 15, weight: .semibold))
                }
                if let note = currentAction, !note.markdown {
                    SecondaryButton(Self.title(note.action)) { perform(note.action) }
                        .padding(.top, 6)
                }
            }
            .padding(.leading, 98)
            // Only a note with a button or a link gets a right margin: every other note lays out as it shipped.
            .padding(.trailing, currentAction == nil ? 0 : 18)
        }
    }
}

// MARK: - Integration card (overview left card when an integration pill is focused)

struct IntegrationCardView: View {
    let task: AgentTask
    @Binding var showingDetail: Bool
    /// With other agents and a live project (Projects, P-mac): the Claude Code card's title row adds "N projects · M waiting" and the chevron. nil on every other card.
    var projectsRow: ProjectsTitleRow? = nil
    var onDiffTap: ((Int) -> Void)? = nil
    @ObservedObject private var appState = AppState.shared
    @State private var githubDetailSection: GitHubDetailSection = .myPRs

    private var isConfigured: Bool {
        switch task.id {
        case "integration_claude":
            #if APPSTORE
            // Sandboxed: can't read ~/.claude directly — check install flag set by HookServer
            return UserDefaults.standard.bool(forKey: "notchmeowHooksInstalled")
            #else
            let url = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent(".claude/settings.json")
            guard let data = try? Data(contentsOf: url),
                  let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                  let hooks = json["hooks"] as? [String: Any],
                  let ss = hooks["SessionStart"] as? [[String: Any]] else { return false }
            return ss.contains { ($0["hooks"] as? [[String: Any]])?.contains {
                let cmd = $0["command"] as? String
                return cmd?.contains("NotchMeow") == true || cmd?.contains("notchmeow") == true
            } ?? false }
            #endif
        case "agent_gemini":
            #if !APPSTORE
            return HookServer.geminiHooksInstalled()
            #else
            return false
            #endif
        case "agent_antigravity":
            #if !APPSTORE
            return HookServer.agyHooksInstalled()
            #else
            return false
            #endif
        case HookOrigin.desktopPill:
            return true   // nothing to install: the relay tags desktop sessions on its own
        case "agent_cursor", "agent_codex":
            return false  // coming soon
        case "integration_music":
            #if !APPSTORE
            return true  // Apple Music is always installed on macOS
            #else
            return false
            #endif
        case "ai_anthropic":  return KeychainStore.shared.get("anthropic-api-key") != nil
        case "ai_google":     return KeychainStore.shared.get("google-api-key")    != nil
        case "ai_openai":     return KeychainStore.shared.get("openai-api-key")    != nil
        case "ai_ollama":     return AppState.shared.localServers.contains { $0.serverID == "ollama" && $0.isReady }
        case "ai_lmstudio":   return AppState.shared.localServers.contains { $0.serverID == "lmstudio" && $0.isReady }
        case "integration_resend":  return KeychainStore.shared.get("resend-api-key") != nil
        case "integration_n8n":     return KeychainStore.shared.get("n8n-api-key")    != nil
        case "integration_vercel":  return KeychainStore.shared.get("vercel-token")   != nil
        case "integration_github":  return KeychainStore.shared.get("github-token")   != nil
        case "integration_stripe":  return KeychainStore.shared.get("stripe-api-key") != nil
        case "integration_notion":  return KeychainStore.shared.get("notion-api-key") != nil
        case "integration_calcom":  return KeychainStore.shared.get("calcom-api-key") != nil
        default: return false
        }
    }

    private var openURL: URL? {
        switch task.id {
        case "integration_claude":  return nil  // uses terminal button below
        case "integration_resend":  return URL(string: "https://resend.com/emails")
        case "integration_n8n":
            if let s = KeychainStore.shared.get("n8n-url") { return URL(string: s) }
            return nil
        case "integration_vercel":  return URL(string: "https://vercel.com/dashboard")
        case "integration_github":  return URL(string: "https://github.com")
        case "integration_stripe":  return URL(string: "https://dashboard.stripe.com/payments")
        case "integration_notion":  return URL(string: "https://notion.so")
        case "integration_calcom":  return URL(string: "https://app.cal.com/bookings")
        default: return nil
        }
    }

    // Workspace/agent pill with active session: show ticker layout
    private var agentSessionActive: Bool {
        guard let def = PillCatalog.definition(for: task.id) else { return false }
        guard def.category == .workspace || def.category == .agent else { return false }
        return task.state != .idle || !task.steps.isEmpty
    }

    // n8n with a finished execution: show result row instead of "Open n8n" button
    private var n8nHasActivity: Bool {
        task.id == "integration_n8n" && !task.steps.isEmpty &&
        (task.state == .finished || task.state == .error)
    }

    // Vercel with recent deployments
    private var vercelHasActivity: Bool {
        task.id == "integration_vercel" && !appState.vercelDeployments.isEmpty
    }

    // Resend with recent emails
    private var resendHasData: Bool {
        task.id == "integration_resend" && !appState.resendEmails.isEmpty
    }

    // GitHub with stats or pulse loaded
    private var githubHasData: Bool {
        task.id == "integration_github" && (appState.githubPulse != nil || appState.githubStats != nil)
    }

    // GitHub with pulse loaded (richer card)
    private var githubHasPulse: Bool {
        task.id == "integration_github" && appState.githubPulse != nil
    }

    // Stripe: show card as soon as first poll completes (balance OR payments)
    private var stripeHasData: Bool {
        task.id == "integration_stripe" && appState.stripeLoaded
    }

    // Cal.com: show calendar as soon as first poll completes
    private var calcomHasData: Bool {
        task.id == "integration_calcom" && appState.calcomLoaded
    }

    // Notion: show pages as soon as first poll completes
    private var notionHasData: Bool {
        task.id == "integration_notion" && appState.notionLoaded
    }

    // Apple Music: show card when a track is loaded (playing or paused) or automation is denied
    private var musicIsActive: Bool {
        #if !APPSTORE
        guard task.id == "integration_music" else { return false }
        if appState.musicAutomationDenied { return true }
        return MusicController.shared.trackTitle != nil
        #else
        return false
        #endif
    }

    private var statusDot: Color {
        #if !APPSTORE
        if task.id == "integration_music" {
            if appState.musicAutomationDenied { return Color(hex: "#F4505E") }
            return appState.musicPlaying ? Color(hex: "#FA2D48") : Color(hex: "#22C55E")
        }
        #endif
        if PillCatalog.definition(for: task.id)?.comingSoon == true { return Color(hex: "#6B7079") }
        let svcErr = task.id == "integration_stripe" ? appState.stripeError
                   : task.id == "integration_calcom"  ? appState.calcomError
                   : nil
        if svcErr != nil { return Color(hex: "#F4505E") }
        return isConfigured ? Color(hex: "#22C55E") : Color(hex: "#F4505E")
    }

    private var statusLabel: String {
        #if !APPSTORE
        if task.id == "integration_music" {
            return MusicFollow.statusLine(shown: MusicController.shared.shownApp, playing: appState.musicPlaying, title: MusicController.shared.trackTitle, denied: MusicController.shared.deniedApp)
        }
        #endif
        if PillCatalog.definition(for: task.id)?.comingSoon == true { return "Coming soon" }
        let svcErr = task.id == "integration_stripe" ? appState.stripeError
                   : task.id == "integration_calcom"  ? appState.calcomError
                   : nil
        if let err = svcErr { return err }
        let isHooks = task.id == "agent_gemini" || task.id == "agent_antigravity"
        let isAI    = ChatProvider(pillID: task.id) != nil
        if isConfigured {
            if isHooks { return "Hooks installed" }
            if isAI {
                let provider = ChatProvider(pillID: task.id)!
                if provider.isLocal {
                    let server = appState.localServers.first { $0.serverID == provider.rawValue }
                    return "Connected · \(server.flatMap(AIService.shared.localModel) ?? "")"
                }
                let model: String
                switch task.id {
                case "ai_anthropic": model = appState.claudeModel
                case "ai_google":    model = appState.googleChatModel
                case "ai_openai":    model = appState.openAIChatModel
                default:             model = ""
                }
                return "Key configured · \(model)"
            }
            return "Connected · loading…"
        } else {
            if isHooks { return "Hooks not installed" }
            if isAI {
                let provider = ChatProvider(pillID: task.id)!
                return provider.isLocal ? "Not connected" : "Key not configured"
            }
            return "Key not configured"
        }
    }

    var body: some View {
        if showingDetail && n8nHasActivity {
            N8nDetailView(task: task) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { showingDetail = false }
            }
            .transition(.opacity)
        } else if showingDetail && vercelHasActivity {
            VercelDetailView(deployment: appState.vercelDeployments[0]) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { showingDetail = false }
            }
            .transition(.opacity)
        } else if vercelHasActivity {
            VercelDeploymentListView(deployments: appState.vercelDeployments, onOpenDetail: {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { showingDetail = true }
            })
            .transition(.opacity)
        } else if resendHasData {
            ResendCardView(emails: appState.resendEmails, total: appState.resendTotal)
                .transition(.opacity)
        } else if showingDetail && githubHasPulse {
            GitHubDetailView(
                section: githubDetailSection,
                pulse: appState.githubPulse!,
                activity: appState.githubActivity,
                stats: appState.githubStats,
                onBack: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { showingDetail = false }
                }
            )
            .transition(.opacity)
        } else if githubHasPulse {
            GitHubPulseCardView(
                pulse: appState.githubPulse!,
                stats: appState.githubStats,
                activity: appState.githubActivity,
                onTapSection: { section in
                    githubDetailSection = section
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { showingDetail = true }
                }
            )
            .transition(.opacity)
        } else if githubHasData {
            GitHubStatsCardView(stats: appState.githubStats!)
                .transition(.opacity)
        } else if stripeHasData {
            StripeCardView()
                .transition(.opacity)
        } else if calcomHasData {
            CalcomCardView()
                .transition(.opacity)
        } else if notionHasData {
            NotionCardView()
                .transition(.opacity)
        } else if musicIsActive {
            #if !APPSTORE
            MusicCardView()
                .accessibilityIdentifier(MusicController.marker)
                .transition(.opacity)
            #endif
        } else if agentSessionActive {
            // Active session view — reuse overview layout
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: task.color))
                        .frame(width: 7, height: 7)
                    let sessionName = Text(task.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#F5F6F8"))
                        .lineLimit(1).truncationMode(.tail)
                    let sessionSubtitle = Text(PillCatalog.definition(for: task.id)?.sessionSubtitle ?? "Agent")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .lineLimit(1).truncationMode(.tail)
                    // The subtitle is whole or not drawn at all, never a clipped fragment: ProjectsTitleFit draws the name and subtitle side by side when both fit, else the name alone.
                    ProjectsTitleFit(name: sessionName, subtitle: sessionSubtitle).layoutPriority(1)
                    if let projectsRow { ProjectsTitleRowView(row: projectsRow) }
                    Spacer(minLength: 2)
                    if task.steps.count > 1 {
                        Text("\(min(task.stepIndex + 1, task.steps.count))/\(task.steps.count)")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#6B7079"))
                            .fixedSize()
                    }
                }
                .padding(.top, 6)
                .padding(.leading, 108)
                .padding(.trailing, 36)

                TickerView(task: task, onDiffTap: onDiffTap)
                    .frame(height: 44)
                    .padding(.top, 6)
                    .padding(.leading, 108)
                    .padding(.trailing, 12)
                if let mark = appState.focusMarks.forPill(task.id, now: FocusAwareApp.now()) {
                    FocusWaitNote(mark: mark, leading: 108)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.top, 4)
        } else {
            // Idle / not connected view — slides in from left when returning from detail
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: task.color))
                        .frame(width: 7, height: 7)
                    let idleName = Text(PillCatalog.definition(for: task.id)?.name ?? task.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#F5F6F8"))
                    let idleSubtitle = Text(PillCatalog.definition(for: task.id)?.subtitle ?? "Integration")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#8E939C"))
                    // With the Projects count beside them: one line each, the subtitle whole or not drawn. Without it the row is as it shipped (no line limit).
                    if projectsRow != nil {
                        ProjectsTitleFit(name: idleName.lineLimit(1).truncationMode(.tail), subtitle: idleSubtitle.lineLimit(1).truncationMode(.tail)).layoutPriority(1)
                    } else {
                        idleName
                        idleSubtitle
                    }
                    if let projectsRow { ProjectsTitleRowView(row: projectsRow) }
                    Spacer(minLength: 2)
                }
                .padding(.top, 6)
                .padding(.leading, 108)
                .padding(.trailing, 36)

                HStack(spacing: 5) {
                    Circle().fill(statusDot).frame(width: 5, height: 5)
                    Text(statusLabel)
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#6B7079"))
                }
                .padding(.leading, 108)
                .padding(.top, 2)

                HStack(spacing: 8) {
                    if task.id == "integration_claude" {
                        Button("Open Visual Studio Code") { openVSCode() }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: task.color).opacity(0.7))
                            .buttonStyle(.plain)
                    } else if task.id == "agent_cursor" {
                        #if !APPSTORE
                        if let url = NSWorkspace.shared.urlForApplication(
                            withBundleIdentifier: "com.todesktop.230313mzl4w4u92") {
                            Button("Open Cursor") {
                                NSWorkspace.shared.openApplication(at: url, configuration: .init(),
                                                                   completionHandler: nil)
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: task.color).opacity(0.85))
                            .buttonStyle(.plain)
                        }
                        #endif
                    } else if task.id == "agent_codex" {
                        #if !APPSTORE
                        if let url = NSWorkspace.shared.urlForApplication(
                            withBundleIdentifier: "com.openai.codex") {
                            Button("Open Codex") {
                                NSWorkspace.shared.openApplication(at: url, configuration: .init(),
                                                                   completionHandler: nil)
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: task.color).opacity(0.85))
                            .buttonStyle(.plain)
                        }
                        #endif
                    } else if let provider = ChatProvider(pillID: task.id) {
                        if isConfigured {
                            Button("Chat with \(task.name)") {
                                switchChatProvider(provider)
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: task.color).opacity(0.85))
                            .buttonStyle(.plain)
                        }
                    } else if task.id == "integration_music" {
                        #if !APPSTORE
                        Button("Open \(MusicController.shared.openLabel)") { MusicController.shared.openMusic() }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: task.color).opacity(0.85))
                            .buttonStyle(.plain)
                        if appState.musicAutomationDenied {
                            Button("Open Settings…") { MusicController.shared.openAutomationSettings() }
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: "#8E939C"))
                                .buttonStyle(.plain)
                        }
                        #endif
                    } else if n8nHasActivity {
                        // Clickable pill — tap to open execution detail
                        let success = task.state == .finished
                        let accent  = success ? Color(hex: "#22C55E") : Color(hex: "#F4505E")
                        Button(action: {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { showingDetail = true }
                        }) {
                            HStack(spacing: 5) {
                                Circle().fill(accent).frame(width: 5, height: 5)
                                Text(task.steps.first ?? "Workflow")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(hex: "#C5C8CD"))
                                    .lineLimit(1).truncationMode(.tail)
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundColor(Color(hex: "#6B7079"))
                            }
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(accent.opacity(0.1))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    } else if let url = openURL {
                        Button("Open \(task.name)") { NSWorkspace.shared.open(url) }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: task.color).opacity(0.85))
                            .buttonStyle(.plain)
                    }
                    if task.id == "integration_stripe" && isConfigured {
                        Button("Refresh") { Task { @MainActor in StripePoller.shared.pollNow() } }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: "#0570DE").opacity(0.85))
                            .buttonStyle(.plain)
                    }
                    if task.id == "integration_calcom" && isConfigured {
                        Button("Refresh") { Task { @MainActor in CalcomPoller.shared.pollNow() } }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: "#C9956A").opacity(0.85))
                            .buttonStyle(.plain)
                    }
                    // Settings button: shown when not configured, except cursor/codex and music
                    if !isConfigured
                       && task.id != "agent_cursor"
                       && task.id != "agent_codex"
                       && task.id != "integration_music" {
                        Button("Settings…") {
                            let section: String
                            switch PillCatalog.definition(for: task.id)?.category {
                            case .workspace, .agent: section = "agents"
                            case .ai:                section = "chat/" + (SettingsMap.pillHome(task.id).tab?.rawValue ?? "keys")
                            default:                 section = "services"
                            }
                            NotificationCenter.default.post(name: .openFullSettings, object: section)
                        }
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 108)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.top, 4)
            .transition(.opacity)
        }
    }

    private func openVSCode() {
        let ids = ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.vscodium.codium"]
        let appURL = ids.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first

        // If we have a project folder, open it directly in VS Code
        if let cwd = task.sessionCwd, !cwd.isEmpty, let appURL = appURL {
            NSWorkspace.shared.open(
                [URL(fileURLWithPath: cwd)],
                withApplicationAt: appURL,
                configuration: .init(),
                completionHandler: nil
            )
            return
        }

        // No cwd: activate running instance or launch fresh
        if let running = ids.compactMap({ id in
            NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == id }
        }).first {
            running.activate(options: .activateIgnoringOtherApps)
            return
        }
        if let appURL = appURL {
            NSWorkspace.shared.openApplication(at: appURL, configuration: .init(), completionHandler: nil)
        }
    }

}

// MARK: - Vercel Deployment List View

struct VercelDeploymentListView: View {
    let deployments: [VercelDeployment]
    let onOpenDetail: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: "#7C5CFF"))
                    .frame(width: 7, height: 7)
                Text("Vercel")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                Text("Deployments")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#8E939C"))
            }
            .padding(.top, 6)
            .padding(.leading, 108)
            .padding(.trailing, 36)

            // Deployment rows
            VStack(alignment: .leading, spacing: 3) {
                // First deployment — highlighted, with detail button
                if let first = deployments.first {
                    let accent = Color(hex: first.isSuccess ? "#22C55E" : "#F4505E")
                    HStack(spacing: 5) {
                        Circle().fill(accent).frame(width: 5, height: 5)
                        Text(first.projectName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: "#C5C8CD"))
                            .lineLimit(1).truncationMode(.tail)
                            .layoutPriority(1)
                        Text(first.timeAgo)
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#6B7079"))
                        Button(action: onOpenDetail) {
                            Image(systemName: "ellipsis")
                                .font(.system(size: 8, weight: .medium))
                                .foregroundColor(Color(hex: "#6B7079"))
                                .frame(width: 18, height: 18)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(accent.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }

                // Remaining deployments — plain rows, identical structure → perfect alignment
                ForEach(Array(deployments.dropFirst().prefix(2))) { dep in
                    let accent = Color(hex: dep.isSuccess ? "#22C55E" : "#F4505E")
                    HStack(spacing: 5) {
                        Circle().fill(accent).frame(width: 5, height: 5)
                        Text(dep.projectName)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: "#9398A1"))
                            .lineLimit(1).truncationMode(.tail)
                            .layoutPriority(1)
                        Text(dep.timeAgo)
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#6B7079"))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 5)
            .padding(.leading, 108)
            .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 4)
    }
}

// MARK: - Vercel Deployment Detail View

struct VercelDetailView: View {
    let deployment: VercelDeployment
    let onClose: () -> Void

    private var accent: Color { Color(hex: deployment.isSuccess ? "#22C55E" : "#F4505E") }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            // Header
            HStack(spacing: 7) {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(hex: "#6B7079"))
                        .frame(width: 28, height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Circle().fill(accent).frame(width: 6, height: 6)
                Text(deployment.projectName)
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                    .lineLimit(1).truncationMode(.middle)
                    .layoutPriority(1)
                Spacer(minLength: 2)
                Text(deployment.statusLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(accent)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(accent.opacity(0.14))
                    .clipShape(Capsule())
            }

            // Details
            VStack(alignment: .leading, spacing: 4) {
                if let commit = deployment.commitMessage {
                    Text(commit)
                        .font(.system(size: 10.5))
                        .foregroundColor(Color(hex: "#C5C8CD"))
                        .lineLimit(2)
                }
                HStack(spacing: 8) {
                    if let branch = deployment.branch {
                        Label(branch, systemImage: "arrow.branch")
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#6B7079"))
                    }
                    Text(deployment.timeAgo + " ago")
                        .font(.system(size: 10))
                        .foregroundColor(Color(hex: "#6B7079"))
                }
                Button(action: {
                    if let url = URL(string: "https://\(deployment.url)") {
                        NSWorkspace.shared.open(url)
                    }
                }) {
                    Text(deployment.url)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundColor(Color(hex: "#7C5CFF").opacity(0.85))
                        .lineLimit(1).truncationMode(.middle)
                }
                .buttonStyle(.plain)
            }
        }
        .padding(.top, 8)
        .padding(.leading, 108)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())
    }
}

// MARK: - Resend Card View

struct ResendPulseDot: View {
    @State private var on = false
    var body: some View {
        Circle()
            .fill(Color(hex: "#22C55E"))
            .frame(width: 4, height: 4)
            .opacity(on ? 1 : 0.2)
            .onAppear {
                withAnimation(.easeInOut(duration: 0.9).repeatForever(autoreverses: true)) { on = true }
            }
    }
}

struct ResendCardView: View {
    let emails: [ResendEmail]
    let total: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: "#22C55E"))
                    .frame(width: 7, height: 7)
                Text("Resend")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                Text("Emails")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#8E939C"))
                if let total {
                    ResendPulseDot()
                    Text("\(total)")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundColor(Color(hex: "#C5C8CD"))
                        .monospacedDigit()
                }
            }
            .padding(.top, 6)
            .padding(.leading, 108)
            .padding(.trailing, 36)

            // Email rows — first is highlighted, rest plain (same structure as Vercel list)
            VStack(alignment: .leading, spacing: 3) {
                if let first = emails.first {
                    let accent = Color(hex: first.isDelivered ? "#22C55E" : "#F4505E")
                    HStack(spacing: 5) {
                        Circle().fill(accent).frame(width: 5, height: 5)
                        Text(first.recipientShort)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: "#C5C8CD"))
                            .lineLimit(1).truncationMode(.tail)
                            .layoutPriority(1)
                        Text(first.timeAgo)
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#6B7079"))
                        if !first.subject.isEmpty {
                            Text(first.subject)
                                .font(.system(size: 10))
                                .foregroundColor(Color(hex: "#4D5159"))
                                .lineLimit(1).truncationMode(.tail)
                        }
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(accent.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                }

                ForEach(Array(emails.dropFirst().prefix(2))) { email in
                    let accent = Color(hex: email.isDelivered ? "#22C55E" : "#F4505E")
                    HStack(spacing: 5) {
                        Circle().fill(accent).frame(width: 5, height: 5)
                        Text(email.recipientShort)
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: "#9398A1"))
                            .lineLimit(1).truncationMode(.tail)
                            .layoutPriority(1)
                        Text(email.timeAgo)
                            .font(.system(size: 10))
                            .foregroundColor(Color(hex: "#6B7079"))
                    }
                    .padding(.horizontal, 8).padding(.vertical, 3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(.top, 5)
            .padding(.leading, 108)
            .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 4)
    }
}

// MARK: - GitHub Pulse Card View

private func ciWorstState(_ prs: [GitHubPR]) -> CIState {
    if prs.contains(where: { $0.ci == .failure }) { return .failure }
    if prs.contains(where: { $0.ci == .pending }) { return .pending }
    if prs.contains(where: { $0.ci == .success }) { return .success }
    return .unknown
}

private func ciColor(_ state: CIState) -> String {
    switch state {
    case .failure: return "#F4505E"
    case .pending: return "#F5A524"
    case .success: return "#22C55E"
    case .unknown: return "#6B7079"
    }
}

private func mainCIWorst(_ repos: [GitHubRepoCI]) -> CIState {
    if repos.contains(where: { $0.ci == .failure }) { return .failure }
    if repos.contains(where: { $0.ci == .pending }) { return .pending }
    if repos.contains(where: { $0.ci == .success }) { return .success }
    return .unknown
}

struct GitHubPulseCardView: View {
    let pulse: GitHubPulse
    let stats: GitHubStats?
    let activity: GitHubActivity?
    let onTapSection: (GitHubDetailSection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: "#F4505E"))
                    .frame(width: 7, height: 7)
                Text("GitHub")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                if let s = stats {
                    // Stars + 7-day mini-row → opens Activity detail
                    Button(action: { onTapSection(.activity) }) {
                        HStack(spacing: 4) {
                            Text("★ \(formatCount(s.totalStars))")
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: "#8E939C"))
                                .lineLimit(1)
                            if let act = activity {
                                HStack(spacing: 2) {
                                    ForEach(act.lastDays(7), id: \.date) { day in
                                        RoundedRectangle(cornerRadius: 1.5)
                                            .fill(contributionColor(day.level))
                                            .frame(width: 7, height: 7)
                                    }
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                } else if let act = activity {
                    // No stats yet but activity loaded — show mini-row only
                    Button(action: { onTapSection(.activity) }) {
                        HStack(spacing: 2) {
                            ForEach(act.lastDays(7), id: \.date) { day in
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(contributionColor(day.level))
                                    .frame(width: 7, height: 7)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Overview")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#8E939C"))
                }
            }
            .padding(.top, 6)
            .padding(.leading, 108)
            .padding(.trailing, 36)

            // Stat rows
            VStack(alignment: .leading, spacing: 4) {
                // My PRs
                let prWorst = ciWorstState(pulse.myPRs)
                let prValue: String = {
                    let n = pulse.myPRs.count
                    if n == 0 { return "0" }
                    let failing = pulse.myPRs.filter { $0.ci == .failure }.count
                    let pending = pulse.myPRs.filter { $0.ci == .pending }.count
                    if failing > 0 { return "\(n) · \(failing) failing" }
                    if pending > 0 { return "\(n) · running" }
                    return "\(n)"
                }()
                GitHubStatRow(
                    icon: "arrow.triangle.pull", iconColor: ciColor(prWorst),
                    label: "My PRs", value: prValue
                ) { onTapSection(.myPRs) }

                // To review
                let reviewCount = pulse.toReview.count
                GitHubStatRow(
                    icon: "eye",
                    iconColor: reviewCount > 0 ? "#8AB4F8" : "#6B7079",
                    label: "To review",
                    value: "\(reviewCount)"
                ) { onTapSection(.toReview) }

                // Default branch CI
                let mainWorst = mainCIWorst(pulse.mainCI)
                let (ciIcon, ciIconColor, ciValue): (String, String, String) = {
                    switch mainWorst {
                    case .failure:
                        let n = pulse.mainCI.filter { $0.ci == .failure }.count
                        return ("xmark.octagon.fill", "#F4505E", "\(n) failing")
                    case .pending:
                        return ("checkmark.seal.fill", "#F5A524", "running")
                    case .success:
                        return ("checkmark.seal.fill", "#22C55E", "all green")
                    case .unknown:
                        return ("checkmark.seal.fill", "#6B7079", pulse.mainCI.isEmpty ? "no repos" : "unknown")
                    }
                }()
                GitHubStatRow(
                    icon: ciIcon, iconColor: ciIconColor,
                    label: "Default branch CI", value: ciValue
                ) { onTapSection(.mainCI) }
            }
            .padding(.top, 6)
            .padding(.leading, 108)
            .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 4)
        .clipped()
    }

    private func formatCount(_ n: Int) -> String {
        if n >= 1000 { return String(format: "%.1fk", Double(n) / 1000) }
        return "\(n)"
    }
}

private struct GitHubStatRow: View {
    let icon: String
    let iconColor: String
    let label: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: iconColor))
                    .frame(width: 14)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#6B7079"))
                Spacer()
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#C5C8CD"))
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - GitHub Detail View

struct GitHubDetailView: View {
    let section: GitHubDetailSection
    let pulse: GitHubPulse
    let activity: GitHubActivity?
    let stats: GitHubStats?
    let onBack: () -> Void
    @ObservedObject private var appState = AppState.shared

    private var title: String {
        switch section {
        case .myPRs:    return "My PRs"
        case .toReview: return "To review"
        case .mainCI:   return "Default branch CI"
        case .activity: return "Activity"
        }
    }

    private var items: [GitHubPR] {
        switch section {
        case .myPRs:    return pulse.myPRs
        case .toReview: return pulse.toReview
        case .mainCI, .activity: return []
        }
    }

    private var repoItems: [GitHubRepoCI] {
        section == .mainCI ? pulse.mainCI : []
    }

    private var totalItems: Int { items.count + repoItems.count }

    /// ⌘O: opens the selected row on github.com, like a click on it.
    private func openSelectedRow() {
        guard appState.view == .overview, appState.mode == .expanded,
              let sel = appState.cardSelection else { return }
        let target: String
        if sel < items.count {
            target = items[sel].url
        } else if sel - items.count < repoItems.count {
            let base = repoItems[sel - items.count].url
            target = base.hasSuffix("/") ? base + "actions" : base + "/actions"
        } else {
            return
        }
        if let url = safeWebURL(target), url.host == "github.com" { NSWorkspace.shared.open(url) }
    }

    var body: some View {
        if section == .activity {
            GitHubActivityDetailContent(
                activity: activity,
                stats: stats,
                login: pulse.login,
                onBack: onBack
            )
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 6) {
                    Button(action: onBack) {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 8, weight: .medium))
                            Text(title)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(Color(hex: "#F5F6F8"))
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 2)
                }
                .padding(.top, 6)
                .padding(.leading, 108)
                .padding(.trailing, 12)

                // List
                if items.isEmpty && repoItems.isEmpty {
                    Text("Nothing here")
                        .font(.system(size: 10.5))
                        .foregroundColor(Color(hex: "#6B7079"))
                        .padding(.top, 8)
                        .padding(.leading, 108)
                } else {
                    ScrollViewReader { proxy in
                        ScrollView(.vertical, showsIndicators: false) {
                            VStack(alignment: .leading, spacing: 0) {
                                ForEach(Array(items.enumerated()), id: \.element.id) { idx, pr in
                                    GitHubPRRowView(pr: pr, showCI: section == .myPRs,
                                                    selected: appState.cardSelection == idx)
                                        .id(idx)
                                }
                                ForEach(Array(repoItems.enumerated()), id: \.element.repo) { idx, repo in
                                    GitHubRepoCIRowView(repo: repo,
                                                        selected: appState.cardSelection == items.count + idx)
                                        .id(items.count + idx)
                                }
                            }
                        }
                        // ⌘↓ and ⌘↑ can select a row below the three that show: keep it in view
                        .onChange(of: appState.cardSelection) { _, sel in
                            if let sel { withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(sel) } }
                        }
                    }
                    .frame(maxHeight: 60)  // 3 rows × 20 pt; rest scrolls
                    .mask(
                        Group {
                            if totalItems > 3 {
                                LinearGradient(
                                    stops: [
                                        .init(color: .black, location: 0),
                                        .init(color: .black, location: 0.8),
                                        .init(color: .clear,  location: 1.0)
                                    ],
                                    startPoint: .top, endPoint: .bottom
                                )
                            } else {
                                Color.black
                            }
                        }
                    )
                    .padding(.top, 4)
                    .padding(.leading, 108)
                    .padding(.trailing, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.top, 4)
            .clipped()
            .onAppear {
                GithubPoller.shared.refreshIfStale()
                appState.cardSelection = nil
                appState.cardItemCount = totalItems
            }
            .onDisappear {
                appState.cardSelection = nil
                appState.cardItemCount = 0
            }
            // a poll can shorten the list under a selection
            .onChange(of: totalItems) { _, count in
                appState.cardItemCount = count
                appState.cardSelection = ShortcutLogic.clampSelection(appState.cardSelection, itemCount: count)
            }
            .onChange(of: appState.mode) { _, mode in
                if mode != .expanded { appState.cardSelection = nil }
            }
            .onReceive(NotificationCenter.default.publisher(for: .islandActivateCardSelection)) { _ in
                openSelectedRow()
            }
            .onExitCommand { onBack() }
        }
    }
}

// MARK: - GitHub Activity Detail

private struct GitHubActivityDetailContent: View {
    let activity: GitHubActivity?
    let stats: GitHubStats?
    let login: String
    let onBack: () -> Void

    @State private var hoveredDay: ContributionDay? = nil

    // Dynamic grid: s=7pt, spacing=1.5pt; numWeeks = floor((202 + 1.5) / (7 + 1.5)) = 23
    private let squareSize: CGFloat = 7
    private let spacing: CGFloat = 1.5
    private var numWeeks: Int { Int((202 + spacing) / (squareSize + spacing)) }

    private var headerRight: String {
        if let day = hoveredDay {
            let label: String
            switch day.count {
            case 0:  label = "No contributions"
            case 1:  label = "1 contribution"
            default: label = "\(day.count) contributions"
            }
            return "\(activityDateLabel(day.date)) · \(label)"
        }
        guard let act = activity else { return "" }
        let total = activityTotalLabel(act.total)
        if let s = stats { return "\(total) past year · \(s.totalRepos) repos" }
        return "\(total) past year"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Button(action: onBack) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 8, weight: .medium))
                        Text("Activity")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(Color(hex: "#F5F6F8"))
                }
                .buttonStyle(.plain)
                Spacer(minLength: 2)
                if activity != nil {
                    Button(action: {
                        let urlStr = "https://github.com/\(login)"
                        if let url = safeWebURL(urlStr), url.host == "github.com" {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        Text(headerRight)
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#8E939C"))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 6)
            .padding(.leading, 108)
            .padding(.trailing, 12)

            // Grid
            if let act = activity {
                let weeks = act.lastWeeks(numWeeks)
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(weeks.indices, id: \.self) { wi in
                        VStack(spacing: spacing) {
                            ForEach(0..<7, id: \.self) { dow in
                                if let day = weeks[wi].first(where: { $0.weekday == dow }) {
                                    RoundedRectangle(cornerRadius: 1.5)
                                        .fill(contributionColor(day.level))
                                        .frame(width: squareSize, height: squareSize)
                                        .onHover { hovering in hoveredDay = hovering ? day : nil }
                                        .onTapGesture {
                                            hoveredDay = (hoveredDay?.date == day.date) ? nil : day
                                        }
                                } else {
                                    Color.clear.frame(width: squareSize, height: squareSize)
                                }
                            }
                        }
                    }
                }
                .padding(.top, 5)
                .padding(.leading, 108)
                .padding(.trailing, 12)
            } else {
                Text("Loading…")
                    .font(.system(size: 10.5))
                    .foregroundColor(Color(hex: "#6B7079"))
                    .padding(.top, 8)
                    .padding(.leading, 108)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 4)
        .clipped()
        .onAppear { GithubPoller.shared.refreshActivityIfStale() }
        .onExitCommand { onBack() }
    }

    private func activityDateLabel(_ dateStr: String) -> String {
        let parts = dateStr.split(separator: "-")
        guard parts.count == 3,
              let month = Int(parts[1]), month >= 1 && month <= 12,
              let day   = Int(parts[2]) else { return dateStr }
        let months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
        return "\(months[month - 1]) \(day)"
    }

    private func activityTotalLabel(_ n: Int) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.locale = Locale(identifier: "en_US")
        return nf.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

private func contributionColor(_ level: Int) -> Color {
    switch level {
    case 1: return Color(hex: "#0E4429")
    case 2: return Color(hex: "#006D32")
    case 3: return Color(hex: "#26A641")
    case 4: return Color(hex: "#39D353")
    default: return Color.white.opacity(0.06)
    }
}

private func ghCIDot(_ ci: CIState) -> Color {
    switch ci {
    case .failure: return Color(hex: "#F4505E")
    case .pending: return Color(hex: "#F5A524")
    case .success: return Color(hex: "#22C55E")
    case .unknown: return Color.clear
    }
}

private struct GitHubPRRowView: View {
    let pr: GitHubPR
    let showCI: Bool
    var selected: Bool = false

    var body: some View {
        Button(action: {
            if let url = safeWebURL(pr.url), url.host == "github.com" {
                NSWorkspace.shared.open(url)
            }
        }) {
            HStack(spacing: 5) {
                if showCI {
                    Circle()
                        .fill(ghCIDot(pr.ci))
                        .frame(width: 5, height: 5)
                        .opacity(pr.ci == .unknown ? 0 : 1)
                } else {
                    Spacer().frame(width: 5)
                }
                Text("\(pr.repo.components(separatedBy: "/").last ?? pr.repo)#\(pr.number)")
                    .font(.system(size: 10.5))
                    .foregroundColor(Color(hex: "#9398A1"))
                    .lineLimit(1)
                Text(pr.title)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#C5C8CD"))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if pr.isDraft {
                    Text("Draft")
                        .font(.system(size: 9.5))
                        .foregroundColor(Color(hex: "#6B7079"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 20)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.12))
                    .opacity(selected ? 1 : 0)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct GitHubRepoCIRowView: View {
    let repo: GitHubRepoCI
    var selected: Bool = false

    private var ciStateWord: String? {
        switch repo.ci {
        case .failure: return "failing"
        case .pending: return "running"
        case .success: return "passing"
        case .unknown: return nil
        }
    }

    var body: some View {
        Button(action: {
            let actionsURL = repo.url.hasSuffix("/") ? repo.url + "actions" : repo.url + "/actions"
            if let url = safeWebURL(actionsURL), url.host == "github.com" {
                NSWorkspace.shared.open(url)
            }
        }) {
            HStack(spacing: 5) {
                Circle()
                    .fill(ghCIDot(repo.ci))
                    .frame(width: 5, height: 5)
                    .opacity(repo.ci == .unknown ? 0 : 1)
                Text(repo.repo.components(separatedBy: "/").last ?? repo.repo)
                    .font(.system(size: 10.5))
                    .foregroundColor(Color(hex: "#9398A1"))
                    .lineLimit(1)
                Text(repo.branch)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#C5C8CD"))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                if let word = ciStateWord {
                    Text(word)
                        .font(.system(size: 10))
                        .foregroundColor(ghCIDot(repo.ci))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 20)
            .background(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.12))
                    .opacity(selected ? 1 : 0)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - GitHub Stats Card View

struct GitHubStatsCardView: View {
    let stats: GitHubStats

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: "#F4505E"))
                    .frame(width: 7, height: 7)
                Text("GitHub")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                Text("Overview")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#8E939C"))
            }
            .padding(.top, 6)
            .padding(.leading, 108)
            .padding(.trailing, 36)

            // Stats rows
            VStack(alignment: .leading, spacing: 5) {
                StatRow(icon: "star.fill", color: "#F5A524",
                        label: "Total stars", value: formatCount(stats.totalStars))
                StatRow(icon: "square.stack.fill", color: "#6B7079",
                        label: "Repositories", value: "\(stats.totalRepos)")
            }
            .padding(.top, 8)
            .padding(.leading, 108)
            .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 4)
    }

    private func formatCount(_ n: Int) -> String {
        if n >= 1000 { return String(format: "%.1fk", Double(n) / 1000) }
        return "\(n)"
    }
}

private struct StatRow: View {
    let icon: String
    let color: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(Color(hex: color))
                .frame(width: 14)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#6B7079"))
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hex: "#C5C8CD"))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Stripe Card View

struct StripeCardView: View {
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: "#0570DE"))
                    .frame(width: 7, height: 7)
                Text("Stripe")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                Text("Payments")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#8E939C"))
            }
            .padding(.top, 6)
            .padding(.leading, 108)
            .padding(.trailing, 36)

            // Balance
            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(balanceFormatted)
                    .font(.system(size: 20, weight: .bold, design: .monospaced))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                    .contentTransition(.numericText(countsDown: false))
                    .animation(.easeOut(duration: 1.2), value: appState.stripeDisplayBalance)
                Text(appState.stripeCurrency.uppercased())
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundColor(Color(hex: "#6B7079"))
                    .padding(.bottom, 1)
            }
            .padding(.leading, 108)
            .padding(.top, 4)

            // Payment rows (animated list)
            VStack(alignment: .leading, spacing: 2) {
                ForEach(appState.stripePayments) { payment in
                    StripePaymentRow(payment: payment)
                        .transition(.asymmetric(
                            insertion: .move(edge: .top).combined(with: .opacity),
                            removal:   .move(edge: .bottom).combined(with: .opacity)
                        ))
                }
            }
            .animation(.spring(response: 0.38, dampingFraction: 0.82),
                        value: appState.stripePayments.map(\.id))
            .padding(.leading, 108)
            .padding(.trailing, 12)
            .padding(.top, 4)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 4)
    }

    private var balanceFormatted: String {
        String(format: "%.2f", Double(appState.stripeDisplayBalance) / 100.0)
    }
}

private struct StripePaymentRow: View {
    let payment: StripePayment

    var body: some View {
        let accent = payment.isSuccess ? Color(hex: "#22C55E") : Color(hex: "#F4505E")
        HStack(spacing: 5) {
            Circle().fill(accent).frame(width: 5, height: 5)
            Text(payment.description ?? "Payment")
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#C5C8CD"))
                .lineLimit(1).truncationMode(.tail)
                .layoutPriority(1)
            Spacer(minLength: 4)
            Text("+\(payment.amountFormatted)")
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundColor(Color(hex: "#22C55E"))
                .fixedSize()
            Text(payment.timeAgo)
                .font(.system(size: 10))
                .foregroundColor(Color(hex: "#6B7079"))
                .fixedSize()
        }
        .frame(maxWidth: .infinity)
    }
}

// MARK: - Cal.com Card View

struct CalcomCardView: View {
    @ObservedObject private var appState = AppState.shared
    @State private var selectedDate: Date? = nil
    @State private var selectedBooking: CalcomBooking? = nil
    @State private var displayMonth: Date = Date()
    @State private var displayHalf: Int = 1  // 1 = first half, 2 = second half

    var body: some View {
        Group {
            if let booking = selectedBooking {
                CalcomBookingDetailView(booking: booking) {
                    withAnimation(.easeOut(duration: 0.2)) { selectedBooking = nil }
                }
            } else if let date = selectedDate {
                CalcomDayView(
                    date: date,
                    bookings: bookingsFor(date),
                    onSelect: { b in withAnimation(.easeOut(duration: 0.2)) { selectedBooking = b } },
                    onBack:   { withAnimation(.easeOut(duration: 0.2)) { selectedDate = nil } }
                )
            } else {
                CalcomCalendarView(
                    displayMonth: $displayMonth,
                    displayHalf: $displayHalf,
                    bookings: appState.calcomBookings,
                    onSelect: { d in withAnimation(.easeOut(duration: 0.2)) { selectedDate = d } }
                )
            }
        }
        .onChange(of: appState.focusId) { _, _ in
            selectedDate = nil; selectedBooking = nil; displayHalf = 1
        }
    }

    private func bookingsFor(_ date: Date) -> [CalcomBooking] {
        let c = Calendar.current.dateComponents([.year, .month, .day], from: date)
        let key = "\(c.year!)-\(String(format: "%02d", c.month!))-\(String(format: "%02d", c.day!))"
        return appState.calcomBookings.filter { $0.dayKey == key }
                                      .sorted { $0.startTime < $1.startTime }
    }
}

struct CalcomCalendarView: View {
    @Binding var displayMonth: Date
    @Binding var displayHalf: Int
    let bookings: [CalcomBooking]
    let onSelect: (Date) -> Void

    private let cal = Calendar.current

    private var navLabel: String {
        let f = DateFormatter(); f.dateFormat = "MMMM yyyy"
        return "\(f.string(from: displayMonth)) Q\(displayHalf)"
    }

    // 7 consecutive days per row, day 1 always at far left — no weekday alignment
    private var allWeeks: [[Date?]] {
        let comps = cal.dateComponents([.year, .month], from: displayMonth)
        let monthStart = cal.date(from: comps)!
        let daysInMonth = cal.range(of: .day, in: .month, for: displayMonth)!.count
        var result: [[Date?]] = []
        var chunk: [Date?] = []
        for i in 0..<daysInMonth {
            chunk.append(cal.date(byAdding: .day, value: i, to: monthStart)!)
            if chunk.count == 7 { result.append(chunk); chunk = [] }
        }
        if !chunk.isEmpty {
            while chunk.count < 7 { chunk.append(nil) }
            result.append(chunk)
        }
        return result
    }

    // Visible weeks for current half
    private var visibleWeeks: [[Date?]] {
        let all = allWeeks
        let splitAt = 2  // always 2 weeks per Q
        return displayHalf == 1 ? Array(all[0..<splitAt]) : Array(all[splitAt...])
    }

    private func hasBookings(_ d: Date) -> Bool {
        let c = cal.dateComponents([.year, .month, .day], from: d)
        let key = "\(c.year!)-\(String(format: "%02d", c.month!))-\(String(format: "%02d", c.day!))"
        return bookings.contains { $0.dayKey == key }
    }

    private func goBack() {
        if displayHalf == 1 {
            displayMonth = cal.date(byAdding: .month, value: -1, to: displayMonth) ?? displayMonth
            displayHalf = 2
        } else {
            displayHalf = 1
        }
    }

    private func goForward() {
        if displayHalf == 1 {
            displayHalf = 2
        } else {
            displayMonth = cal.date(byAdding: .month, value: 1, to: displayMonth) ?? displayMonth
            displayHalf = 1
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(Color(hex: "#C9956A")).frame(width: 7, height: 7)
                Text("Cal.com").font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8"))
                Text("Schedule").font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C"))
            }
            .padding(.top, 6).padding(.leading, 108).padding(.trailing, 36)

            HStack(spacing: 0) {
                Button { goBack() } label: {
                    Image(systemName: "chevron.left").font(.system(size: 8, weight: .semibold))
                        .foregroundColor(Color(hex: "#6B7079")).frame(width: 18, height: 16)
                }.buttonStyle(.plain)
                Text(navLabel).font(.system(size: 10, weight: .semibold))
                    .foregroundColor(Color(hex: "#C5C8CD")).frame(maxWidth: .infinity)
                Button { goForward() } label: {
                    Image(systemName: "chevron.right").font(.system(size: 8, weight: .semibold))
                        .foregroundColor(Color(hex: "#6B7079")).frame(width: 18, height: 16)
                }.buttonStyle(.plain)
            }
            .padding(.leading, 108).padding(.trailing, 12).padding(.top, 2)

            VStack(spacing: 1) {
                ForEach(visibleWeeks.indices, id: \.self) { i in
                    CalcomWeekRow(week: visibleWeeks[i], hasBookings: hasBookings,
                                  isToday: cal.isDateInToday, onSelect: onSelect)
                }
            }
            .padding(.leading, 108).padding(.trailing, 12).padding(.top, 2)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading).padding(.top, 4)
        .transition(.opacity)
    }
}

private struct CalcomWeekRow: View {
    let week: [Date?]
    let hasBookings: (Date) -> Bool
    let isToday: (Date) -> Bool
    let onSelect: (Date) -> Void

    private var weekLabel: String {
        guard let first = week.compactMap({ $0 }).first else { return "" }
        let f = DateFormatter(); f.dateFormat = "dd/MM"
        return f.string(from: first)
    }

    var body: some View {
        HStack(spacing: 0) {
            Text(weekLabel).font(.system(size: 7)).foregroundColor(Color(hex: "#4B5563"))
                .frame(width: 26, alignment: .leading)
            ForEach(0..<7, id: \.self) { i in
                if let day = week[i] {
                    CalcomDayCell(day: day, hasEvents: hasBookings(day), isToday: isToday(day))
                        .contentShape(Rectangle()).onTapGesture { onSelect(day) }.frame(maxWidth: .infinity)
                } else {
                    Color.clear.frame(maxWidth: .infinity).frame(height: 18)
                }
            }
        }
    }
}

private struct CalcomDayCell: View {
    let day: Date
    let hasEvents: Bool
    let isToday: Bool
    var body: some View {
        VStack(spacing: 1) {
            Text("\(Calendar.current.component(.day, from: day))")
                .font(.system(size: 9, weight: isToday ? .bold : .regular))
                .foregroundColor(isToday ? .white : Color(hex: "#9398A1"))
                .frame(width: 13, height: 13)
                .background(isToday ? Color(hex: "#C9956A").opacity(0.55) : Color.clear)
                .clipShape(Circle())
            Circle().fill(hasEvents ? Color(hex: "#C9956A") : Color.clear).frame(width: 3, height: 3)
        }
        .frame(height: 18)
    }
}

struct CalcomDayView: View {
    let date: Date
    let bookings: [CalcomBooking]
    let onSelect: (CalcomBooking) -> Void
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left").font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color(hex: "#6B7079")).frame(width: 22, height: 22).contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.leading, 108)
                Text(dayLabel).font(.system(size: 11, weight: .semibold)).foregroundColor(Color(hex: "#C5C8CD"))
                Spacer()
            }
            .padding(.top, 6).padding(.trailing, 12)

            if bookings.isEmpty {
                Text("No calls scheduled").font(.system(size: 11)).foregroundColor(Color(hex: "#6B7079"))
                    .padding(.leading, 116).padding(.top, 8)
            } else {
                VStack(alignment: .leading, spacing: 3) {
                    ForEach(bookings) { b in
                        Button { onSelect(b) } label: {
                            HStack(spacing: 6) {
                                Circle().fill(Color(hex: "#C9956A")).frame(width: 4, height: 4)
                                Text(b.timeLabel)
                                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                                    .foregroundColor(Color(hex: "#C9956A")).fixedSize()
                                Text(b.title).font(.system(size: 11)).foregroundColor(Color(hex: "#C5C8CD"))
                                    .lineLimit(1).truncationMode(.tail).layoutPriority(1)
                                Spacer(minLength: 2)
                                Image(systemName: "chevron.right").font(.system(size: 8))
                                    .foregroundColor(Color(hex: "#4B5563"))
                            }
                            .padding(.horizontal, 6).padding(.vertical, 3)
                            .background(Color(hex: "#C9956A").opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 4))
                        }.buttonStyle(.plain)
                    }
                }
                .padding(.leading, 108).padding(.trailing, 12).padding(.top, 5)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading).padding(.top, 4)
        .transition(.opacity)
    }
    private var dayLabel: String {
        let f = DateFormatter(); f.dateFormat = "EEEE d MMMM"; return f.string(from: date)
    }
}

struct CalcomBookingDetailView: View {
    let booking: CalcomBooking
    let onBack: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 4) {
                Button(action: onBack) {
                    Image(systemName: "chevron.left").font(.system(size: 9, weight: .semibold))
                        .foregroundColor(Color(hex: "#6B7079")).frame(width: 22, height: 22).contentShape(Rectangle())
                }.buttonStyle(.plain).padding(.leading, 108)
                Text(booking.timeLabel)
                    .font(.system(size: 10, weight: .medium, design: .monospaced))
                    .foregroundColor(Color(hex: "#C9956A"))
                Spacer()
            }
            .padding(.top, 6).padding(.trailing, 12)

            VStack(alignment: .leading, spacing: 4) {
                Text(booking.title).font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8")).lineLimit(1)
                if let name = booking.attendeeName, !name.isEmpty {
                    CalcomDetailRow(icon: "person.fill", text: name, size: 11)
                }
                if let email = booking.attendeeEmail, !email.isEmpty {
                    CalcomDetailRow(icon: "envelope.fill", text: email, size: 10, truncate: true)
                }
                if let notes = booking.attendeeNotes, !notes.isEmpty {
                    CalcomDetailRow(icon: "note.text", text: notes, size: 10, lines: 2)
                }
            }
            .padding(.leading, 114).padding(.trailing, 12).padding(.top, 5)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading).padding(.top, 4)
        .transition(.opacity)
    }
}

private struct CalcomDetailRow: View {
    let icon: String
    let text: String
    var size: CGFloat = 11
    var truncate: Bool = false
    var lines: Int = 1
    var body: some View {
        HStack(alignment: .top, spacing: 4) {
            Image(systemName: icon).font(.system(size: 9)).foregroundColor(Color(hex: "#6B7079")).frame(width: 10)
            Text(text).font(.system(size: size)).foregroundColor(Color(hex: "#9398A1"))
                .lineLimit(lines).truncationMode(truncate ? .middle : .tail)
        }
    }
}

// MARK: - Notion Card View

struct NotionCardView: View {
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(Color(hex: "#E8E8E8")).frame(width: 7, height: 7)
                Text("Notion").font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8"))
                Text("Recent").font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C"))
            }
            .padding(.top, 6).padding(.leading, 108).padding(.trailing, 36)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(appState.notionPages.prefix(3)) { page in
                    Button {
                        if let url = safeWebURL(page.url) { NSWorkspace.shared.open(url) }
                    } label: {
                        HStack(spacing: 6) {
                            if let emoji = page.emoji {
                                Text(emoji).font(.system(size: 10)).frame(width: 14)
                            } else {
                                Image(systemName: "doc.text").font(.system(size: 9))
                                    .foregroundColor(Color(hex: "#6B7079")).frame(width: 14)
                            }
                            Text(page.title).font(.system(size: 11))
                                .foregroundColor(Color(hex: "#C5C8CD"))
                                .lineLimit(1).truncationMode(.tail).layoutPriority(1)
                            Spacer(minLength: 4)
                            Text(page.timeAgo).font(.system(size: 9))
                                .foregroundColor(Color(hex: "#4B5563"))
                        }
                        .padding(.horizontal, 6).padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 102).padding(.trailing, 12).padding(.top, 5)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading).padding(.top, 4)
        .transition(.opacity)
    }
}

// MARK: - n8n Execution Detail View

struct N8nDetailView: View {
    let task: AgentTask
    let onClose: () -> Void

    private var success: Bool  { task.state == .finished }
    private var accent: Color  { success ? Color(hex: "#22C55E") : Color(hex: "#F4505E") }
    private var statusLabel: String { success ? "Success" : "Failed" }
    private var detail: String? { task.steps.dropFirst().first }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            // Header: back button + workflow name + status badge
            HStack(spacing: 7) {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(hex: "#6B7079"))
                        .frame(width: 28, height: 28)   // large hit area
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Circle().fill(accent).frame(width: 6, height: 6)

                Text(task.steps.first ?? "Workflow")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                    .lineLimit(1).truncationMode(.middle)
                    .layoutPriority(1)

                Spacer(minLength: 2)

                Text(statusLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(accent)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(accent.opacity(0.14))
                    .clipShape(Capsule())
            }

            // Detail body — monospaced, selectable
            if let detail {
                ScrollView(.vertical, showsIndicators: false) {
                    Text(detail)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(Color(hex: "#9398A1"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineSpacing(2)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 88)
            } else {
                Text(success ? "Completed successfully." : "No error details available.")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#6B7079"))
            }
        }
        .padding(.top, 8)
        .padding(.leading, 108)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())   // prevent taps falling through transparent areas
    }
}

// MARK: - Ticker (overview scrolling task steps) V2

struct TickerView: View {
    let task: AgentTask?
    var onDiffTap: ((Int) -> Void)? = nil

    @State private var rowA: String = "…"   // completed (above, left-shifted)
    @State private var rowB: String = "…"   // current (below) → animates diagonally up-left
    @State private var rowC: String = ""    // incoming current — slides in from below

    @State private var rowAOffset: CGFloat = 0
    @State private var rowAOpacity: Double = 1
    @State private var rowBOffset: CGFloat = 22
    @State private var rowBPhase:  Double  = 0   // 0=current, 1=completed (drives X+scale)
    @State private var rowCOffset: CGFloat = 44
    @State private var rowCOpacity: Double = 0

    @State private var displayIndex: Int = -1
    @State private var isTransitioning = false

    private let completedScale: CGFloat = 11.5 / 13   // 0.885 — matches completed font size

    var steps: [String] {
        let raw = task?.steps ?? []
        return raw.isEmpty ? ["…"] : raw
    }

    var body: some View {
        let isActive = task?.state == .thinking || task?.state == .working || task?.state == .searching
        let rowADiffTap: (() -> Void)? = rowA.parseDiffStep().map { dp in { onDiffTap?(dp.diffId) } }
        let rowBDiffTap: (() -> Void)? = rowB.parseDiffStep().map { dp in { onDiffTap?(dp.diffId) } }

        ZStack(alignment: .topLeading) {
            Color.clear

            // Row A: completed row — always rendered at phase=1 + completedScale
            TickerRowView(text: rowA, phase: 1.0, isActive: isActive, onDiffTap: rowADiffTap)
                .scaleEffect(completedScale, anchor: .leading)
                .offset(x: -10, y: rowAOffset)
                .opacity(rowAOpacity)

            // Row B: current step → animates diagonally up-left, phase 0→1, scale 1→completedScale
            TickerRowView(text: rowB, phase: rowBPhase, isActive: isActive, onDiffTap: rowBDiffTap)
                .scaleEffect(1 - rowBPhase * (1 - completedScale), anchor: .leading)
                .offset(x: -rowBPhase * 10, y: rowBOffset)

            // Row C: incoming new step — slides in from below at phase=0
            TickerRowView(text: rowC, phase: 0.0, isActive: isActive)
                .offset(y: rowCOffset)
                .opacity(rowCOpacity)
        }
        .frame(height: 44)
        .clipped()
        .mask(LinearGradient(
            stops: [
                .init(color: .clear, location: 0),
                .init(color: .black, location: 0.12),
                .init(color: .black, location: 0.85),
                .init(color: .clear, location: 1)
            ],
            startPoint: .top, endPoint: .bottom
        ))
        .onAppear {
            let idx = task?.stepIndex ?? -1
            displayIndex = idx
            if idx >= 0, !steps.isEmpty {
                rowA = idx > 0 ? steps[max(0, idx - 1)] : "…"
                rowB = steps[min(idx, steps.count - 1)]
            }
        }
        .onChange(of: task?.steps.count) { _, _ in
            guard let task, !task.steps.isEmpty, !isTransitioning else { return }
            let newIdx = task.stepIndex
            if displayIndex < 0 {
                displayIndex = newIdx
                rowA = newIdx > 0 ? steps[max(0, newIdx - 1)] : "…"
                rowB = steps[min(newIdx, steps.count - 1)]
                return
            }
            guard newIdx != displayIndex else { return }
            tickerAnimate(to: newIdx)
        }
    }

    private func tickerAnimate(to newIdx: Int) {
        isTransitioning = true
        rowC = steps[min(newIdx, steps.count - 1)]
        rowCOffset = 44
        rowCOpacity = 0

        // Old completed (rowA): fades + slides further up
        withAnimation(.easeOut(duration: 0.28)) {
            rowAOffset  = -22
            rowAOpacity = 0
        }

        // Current (rowB): moves diagonally up-left + shrinks to completed size
        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.38)) {
            rowBOffset = 0
            rowBPhase  = 1
        }

        // New current (rowC): slides in from below
        withAnimation(.timingCurve(0.4, 0, 0.2, 1, duration: 0.38)) {
            rowCOffset  = 22
            rowCOpacity = 1
        }

        DispatchQueue.main.asyncAfter(deadline: .now() + 0.50) {
            self.displayIndex    = newIdx
            self.rowA            = self.rowB
            self.rowAOffset      = 0
            self.rowAOpacity     = 1
            self.rowB            = self.rowC
            self.rowBOffset      = 22
            self.rowBPhase       = 0
            self.rowCOffset      = 44
            self.rowCOpacity     = 0
            self.isTransitioning = false
        }
    }
}

struct TickerRowView: View {
    let text: String
    let phase: Double   // 0 = current (shimmer, large), 1 = completed (dim, scaled down by caller)
    var isActive: Bool = true
    var onDiffTap: (() -> Void)? = nil

    var body: some View {
        let chevronOpacity:   Double = isActive ? max(0, 1 - phase * 2)       : 0
        let checkmarkOpacity: Double = isActive ? max(0, phase * 2 - 1)       : 1
        let shimmerOpacity:   Double = isActive ? max(0, 1 - phase * 1.6)     : 0
        let staticOpacity:    Double = isActive ? min(1, max(0, phase * 2 - 0.4)) : 1
        let staticColor = (!isActive && phase < 0.5) ? Color(hex: "#C9CDD4") : Color(hex: "#6B7079")

        if let dp = text.parseDiffStep() {
            HStack(spacing: 6) {
                ZStack {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .opacity(chevronOpacity)
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .regular))
                        .foregroundColor(Color(hex: "#454850"))
                        .opacity(checkmarkOpacity)
                }
                .frame(width: 12, alignment: .center)
                // Filename + counts
                HStack(spacing: 0) {
                    ZStack(alignment: .leading) {
                        TickerShimmerText(text: dp.filename, visible: shimmerOpacity > 0)
                            .opacity(shimmerOpacity)
                        Text(dp.filename)
                            .font(.system(size: 13, weight: .medium))
                            .foregroundColor(staticColor)
                            .lineLimit(1).truncationMode(.tail)
                            .opacity(staticOpacity)
                    }
                    if dp.added > 0 {
                        Text(" +\(dp.added)")
                            .font(.system(size: 10, weight: .medium).monospaced())
                            .foregroundColor(Color(hex: "#22C55E"))
                            .fixedSize()
                    }
                    if dp.removed > 0 {
                        Text(" −\(dp.removed)")
                            .font(.system(size: 10, weight: .medium).monospaced())
                            .foregroundColor(Color(hex: "#F4505E"))
                            .fixedSize()
                    }
                }
            }
            .frame(height: 22, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .contentShape(Rectangle())
            .onTapGesture { onDiffTap?() }
        } else {
            HStack(spacing: 6) {
                // Icon: chevron fades out first half, checkmark fades in second half
                ZStack {
                    Image(systemName: "chevron.right")
                        .font(.system(size: 9, weight: .medium))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .opacity(chevronOpacity)
                    Image(systemName: "checkmark")
                        .font(.system(size: 8, weight: .regular))
                        .foregroundColor(Color(hex: "#454850"))
                        .opacity(checkmarkOpacity)
                }
                .frame(width: 12, alignment: .center)

                // Text: shimmer fades out, dim completed text fades in (overlapping cross-fade)
                ZStack(alignment: .leading) {
                    TickerShimmerText(text: text, visible: shimmerOpacity > 0)
                        .opacity(shimmerOpacity)
                    Text(text)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(staticColor)
                        .lineLimit(1).truncationMode(.tail)
                        .opacity(staticOpacity)
                }
            }
            .frame(height: 22, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

struct TickerShimmerText: View {
    let text: String
    /// False while the row's shimmer is at opacity 0 (a row that is not the working step's): nothing of it is on screen, so the timeline stops asking for frames. Each ticker row
    /// mounts one, in every view the island keeps stacked, and every tick of one is a pass of the whole island's graph.
    let visible: Bool
    /// Keeps the timeline running for a moment after `visible` goes false: the row's opacity is set to 0 at once, but it fades out over 0.38 s, and a shimmer that stopped
    /// moving while still partly visible would show. One `Task.sleep` per hide, no timer.
    @State private var ticking = true

    var body: some View {
        TimelineView(.animation(paused: !ticking && !visible)) { tl in
            let t = tl.date.timeIntervalSinceReferenceDate
            let p = CGFloat(t.truncatingRemainder(dividingBy: 2.2) / 2.2)
            // phase sweeps -0.1 → 1.1 so white peak enters from left and exits right
            let phase = p * 1.2 - 0.1
            Text(text)
                .font(.system(size: 13, weight: .medium))
                .lineLimit(1)
                .truncationMode(.tail)
                .foregroundStyle(LinearGradient(stops: [
                    .init(color: Color(hex: "#7c818a"), location: max(0, phase - 0.3)),
                    .init(color: Color(hex: "#F2F3F5"), location: max(0, min(1, phase))),
                    .init(color: Color(hex: "#7c818a"), location: min(1, phase + 0.3)),
                ], startPoint: .leading, endPoint: .trailing))
        }
        .task(id: visible) {
            if visible { ticking = true; return }
            do { try await Task.sleep(for: .milliseconds(600)) } catch { return }
            ticking = false
        }
    }
}

// MARK: - Agent pills (overview right card)

struct AgentPillsView: View {
    @ObservedObject var state: AppState
    /// The Claude-only card's grid (Projects, P-mac): the live projects first, then the other pills while they fit. nil is the grid that ships.
    var projects: ProjectsGridInput? = nil
    @State private var swapping = false

    /// The pills of the row with the coat the cast gives each: the tasks other than the focused one (and, in Two cats mode, other than cat 2's), the first four.
    private var displayPills: [(task: AgentTask, cat: String)] {
        state.cast.pills.compactMap { p in state.tasks.first { $0.id == p.pill }.map { ($0, p.cat) } }
    }

    private let columns = [
        GridItem(.flexible(), spacing: 4),
        GridItem(.flexible(), spacing: 4)
    ]

    var body: some View {
        if let projects {
            ProjectPillGrid(cells: ProjectsLayout.gridCells(projects: projects.projects.map { $0.id }, otherPills: displayPills.filter { $0.task.id != "integration_claude" }.map { $0.task.id }),
                            projects: projects.projects, pill: { id in AnyView(otherPill(id)) }, active: projects.active,
                            onSelect: projects.onSelect, onMore: projects.onMore, onHover: projects.onHover, onFrame: projects.onFrame)
        } else {
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(displayPills, id: \.task.id) { pill in
                        pillView(pill)
                    }
                }
                .padding(.horizontal, 8)
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// One of the other agents' pills in the Claude-only grid: the same pill, coat and tap as the grid that ships.
    @ViewBuilder private func otherPill(_ id: String) -> some View {
        if let pill = displayPills.first(where: { $0.task.id == id }) { pillView(pill) }
    }

    /// A pill and its tap (a focus change with the blip), the same wherever the grid shows it.
    @ViewBuilder private func pillView(_ pill: (task: AgentTask, cat: String)) -> some View {
        let task = pill.task
        #if !APPSTORE
        if task.id == "integration_music" {
            MusicPill(task: task, cat: pill.cat, state: state, swapping: $swapping) {
                swapping = true
                state.setFocus(task.id)
                SoundEngine.shared.play("blip")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { swapping = false }
            }
        } else {
            AgentPill(task: task, cat: pill.cat, state: state, swapping: $swapping) {
                swapping = true
                state.setFocus(task.id)
                SoundEngine.shared.play("blip")
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { swapping = false }
            }
        }
        #else
        AgentPill(task: task, cat: pill.cat, state: state, swapping: $swapping) {
            swapping = true
            state.setFocus(task.id)
            SoundEngine.shared.play("blip")
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { swapping = false }
        }
        #endif
    }
}

struct AgentPill: View {
    let task: AgentTask
    /// The coat the pill's cat wears: the cast's.
    let cat: String
    @ObservedObject var state: AppState
    @Binding var swapping: Bool
    let onTap: () -> Void
    @State private var isHovered = false

    private var effectiveColor: String { task.color }

    /// How much of the pill's trailing end its kittens take (0 with none).
    private var kittenReserve: CGFloat {
        CGFloat(CatIslandLayout.pillKittenReserve(CatKittens.slots("pill", state.kittenView(task.id)), pillHeight: 28))
    }

    // The Claude Code pill always shows "Claude Code" regardless of the active project name (its ID, integration_claude, is frozen)
    private var displayName: String {
        task.id == "integration_claude" ? "Claude Code" : task.name
    }

    var body: some View {
        Button(action: { onTap() }) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Capsule()
                        .fill(isHovered
                              ? Color(hex: effectiveColor).opacity(0.18)
                              : Color(hex: "#0E0F11"))
                    Capsule()
                        .stroke(Color(hex: effectiveColor).opacity(isHovered ? 0.55 : 0.14), lineWidth: 1)
                    HStack(spacing: 0) {
                        MiniBotCanvasView(task: task, cat: cat)
                            .frame(width: 22 / 0.6, height: 22 / 0.6)
                            .frame(width: 22, height: 22, alignment: .center)
                            .padding(.leading, 8)
                        Spacer()
                    }
                    Text(displayName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(isHovered
                                         ? Color(hex: effectiveColor).lighter(by: 0.3)
                                         : Color(hex: "#6B7079"))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .padding(.leading, kittenReserve > 0 ? 34 : 0)    // with kittens at the trailing end the title keeps clear of them and of the pill's own cat (which ends at 30 pt)
                        .padding(.trailing, kittenReserve)
                        .frame(maxWidth: .infinity, alignment: .center)
                    // The pill's subagents, as up to three small kittens at its trailing end (and "+N").
                    if state.kittens[task.id] != nil {
                        let box = CatIslandLayout.kittenBox("pill")
                        KittenLayerView(state: state, pills: [task.id], parentCat: cat, place: "pill", unit: 28, colour: task.color)
                            .offset(x: CGFloat(box.x1 * 28))
                            .frame(maxWidth: .infinity, alignment: .trailing)
                    }
                }
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .shadow(color: Color(hex: effectiveColor).opacity(isHovered ? 0.35 : 0), radius: 10, x: 0, y: 2)

                // Alert badge (approval / finished / error)
                if let badge = task.pillBadge {
                    PillBadgeView(badge: badge, taskColor: effectiveColor)
                        .offset(x: 3, y: -3)
                } else if state.focusDot(task.id) {   // a session waits in its own app (FocusAware): the badge above wins
                    FocusWaitDot(size: 8, ring: true).offset(x: 3, y: -3)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.04 : 1.0)
        .brightness(isHovered ? 0.06 : 0)
        .onHover { newHover in
            guard !swapping else { return }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { isHovered = newHover }
        }
    }
}

// MARK: - Music Pill (GitHub build only)

#if !APPSTORE
struct MusicPill: View {
    let task: AgentTask
    /// The coat the pill's cat wears: the cast's (the Main cat, for an integration).
    let cat: String
    @ObservedObject var state: AppState
    @Binding var swapping: Bool
    let onTap: () -> Void
    @State private var isHovered = false

    private var isPlaying: Bool { AppState.shared.musicPlaying }
    private var showControls: Bool { isHovered && MusicController.shared.trackTitle != nil }

    var body: some View {
        ZStack {
            // Selection target — full pill area, receives taps where controls don't
            Capsule()
                .fill(Color.clear)
                .contentShape(Capsule())
                .onTapGesture { onTap() }

            // Visual fills
            Capsule()
                .fill(isHovered ? Color(hex: task.color).opacity(0.18) : Color(hex: "#0E0F11"))
                .allowsHitTesting(false)
            Capsule()
                .stroke(Color(hex: task.color).opacity(isHovered ? 0.55 : 0.14), lineWidth: 1)
                .allowsHitTesting(false)

            // Mini cat at leading edge
            HStack(spacing: 0) {
                MiniBotCanvasView(task: task, cat: cat, isDancing: isPlaying)
                    .frame(width: 22 / 0.6, height: 22 / 0.6)
                    .frame(width: 22, height: 22, alignment: .center)
                    .padding(.leading, 8)
                Spacer()
            }
            .allowsHitTesting(false)

            // Title — trailing padding grows on hover to make room for buttons
            Text(task.name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(isHovered ? Color(hex: task.color).lighter(by: 0.3) : Color(hex: "#6B7079"))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, 34)
                .padding(.trailing, showControls ? 52 : 10)
                .frame(maxWidth: .infinity, alignment: .center)
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: showControls)
                .allowsHitTesting(false)

            // Playback controls — appear on hover when a track is loaded
            if showControls {
                HStack(spacing: 0) {
                    Spacer()
                    HStack(spacing: 2) {
                        MusicControlButton(icon: isPlaying ? "pause.fill" : "play.fill", color: task.color) {
                            MusicController.shared.playPause()
                        }
                        MusicControlButton(icon: "forward.fill", color: task.color) {
                            MusicController.shared.nextTrack()
                        }
                    }
                    .padding(.trailing, 4)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .trailing)))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .shadow(color: Color(hex: task.color).opacity(isHovered ? 0.35 : 0), radius: 10, x: 0, y: 2)
        .scaleEffect(isHovered ? 1.04 : 1.0)
        .brightness(isHovered ? 0.06 : 0)
        .onHover { newHover in
            guard !swapping else { return }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { isHovered = newHover }
        }
    }
}

struct MusicControlButton: View {
    let icon: String
    let color: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isHovered ? Color(hex: color).opacity(0.18) : Color(hex: "#0E0F11"))
                Circle()
                    .stroke(Color(hex: color).opacity(isHovered ? 0.55 : 0.14), lineWidth: 1)
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(isHovered ? Color(hex: color).lighter(by: 0.3) : Color(hex: "#6B7079"))
            }
            .frame(width: 20, height: 20)
            .shadow(color: Color(hex: color).opacity(isHovered ? 0.35 : 0), radius: 6)
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.1 : 1.0)
        .onHover { newHover in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { isHovered = newHover }
        }
    }
}
#endif

// MARK: - Music Card View (GitHub build only)

#if !APPSTORE
struct MusicCardView: View {
    @ObservedObject private var controller = MusicController.shared
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if appState.musicAutomationDenied {
                // Automation denied — prompt user to fix
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: "#F4505E"))
                        .frame(width: 7, height: 7)
                    Text(controller.deniedLabel)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#F5F6F8"))
                    Spacer(minLength: 2)
                }
                .padding(.top, 6)
                .padding(.leading, 108)
                .padding(.trailing, 36)

                Text("Allow NotchMeow to control \(controller.deniedLabel)")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#8E939C"))
                    .padding(.leading, 108)
                    .padding(.trailing, 12)

                Button("Open Settings…") { MusicController.shared.openAutomationSettings() }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(hex: "#FA2D48").opacity(0.85))
                    .buttonStyle(.plain)
                    .padding(.leading, 108)
                    .padding(.top, 2)
            } else {
                // Line 1: dot + title
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: "#FA2D48"))
                        .frame(width: 7, height: 7)
                    if let title = controller.trackTitle {
                        Text(title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(hex: "#F5F6F8"))
                            .lineLimit(1).truncationMode(.tail)
                            .frame(maxWidth: 150, alignment: .leading)
                    }
                }
                .padding(.top, 6)
                .padding(.leading, 108)

                // Line 2: artist
                if let line = MusicFollow.secondLine(artist: controller.artist, app: controller.shownApp) {
                    Text(line)
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: 150, alignment: .leading)
                        .padding(.leading, 108)
                }

                // Line 3: controls
                HStack(spacing: 8) {
                    Button(action: { MusicController.shared.previousTrack() }) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#8E939C"))
                    }
                    .buttonStyle(.plain)
                    Button(action: { MusicController.shared.playPause() }) {
                        Image(systemName: appState.musicPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#FA2D48"))
                    }
                    .buttonStyle(.plain)
                    Button(action: { MusicController.shared.nextTrack() }) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#8E939C"))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 108)
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 4)
    }
}
#endif

struct PillBadgeView: View {
    let badge: PillBadge
    let taskColor: String

    private var badgeColor: Color {
        switch badge {
        case .approval: return Color(hex: "#F5A524")
        case .finished: return Color(hex: "#22C55E")
        case .error:    return Color(hex: "#F4505E")
        }
    }

    private var icon: String {
        switch badge {
        case .approval: return "exclamationmark"
        case .finished: return "checkmark"
        case .error:    return "xmark"
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "#0B0C0E"))
                .frame(width: 14, height: 14)
            Circle()
                .fill(badgeColor)
                .frame(width: 12, height: 12)
            Image(systemName: icon)
                .font(.system(size: 6, weight: .bold))
                .foregroundColor(.black)
        }
        .shadow(color: badgeColor.opacity(0.6), radius: 4, x: 0, y: 0)
    }
}

// MARK: - Column agents (right side of non-overview views)

struct ColumnAgentsView: View {
    @ObservedObject var state: AppState

    var others: [(task: AgentTask, cat: String)] {
        state.cast.pills.compactMap { p in state.tasks.first { $0.id == p.pill }.map { ($0, p.cat) } }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(others.enumerated()), id: \.1.task.id) { idx, other in
                MiniBotCanvasView(task: other.task, cat: other.cat)
                    .frame(width: 16 / 0.6, height: 16 / 0.6)
                    .frame(width: 16, height: 16)
                    .position(x: 0, y: CGFloat(50 + idx * 24))
                    .animation(.spring(response: 0.5, dampingFraction: 0.72).delay(Double(idx) * 0.035), value: idx)
            }
        }
    }
}

// MARK: - Card background

struct CardBackground<Content: View>: View {
    enum Wash { case red, green, pink, amber, cyan, indigo, soft }

    let wash: Wash?
    let content: (() -> Content)?

    init(wash: Wash?, @ViewBuilder content: @escaping () -> Content) {
        self.wash = wash
        self.content = content
    }

    var washColor: Color {
        switch wash {
        case .red:    return Color(hex: "#F4505E").opacity(0.55)
        case .green:  return Color(hex: "#34D399").opacity(0.5)
        case .pink:   return Color(hex: "#F472B6").opacity(0.55)
        case .amber:  return Color(hex: "#F5A524").opacity(0.42)
        case .cyan:   return Color(hex: "#22D3EE").opacity(0.38)
        case .indigo: return Color(hex: "#6366F1").opacity(0.5)
        case .soft:   return Color.white.opacity(0.08)
        case nil:     return Color.clear
        }
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(hex: "#141518"))
                .overlay(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: washColor, location: 0),
                            .init(color: .clear, location: 0.7)
                        ]),
                        center: UnitPoint(x: 0.5, y: 1.3),
                        startRadius: 0,
                        endRadius: 280
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.035), lineWidth: 1)
                )

            if let content = content {
                content()
            }
        }
    }
}

extension CardBackground where Content == EmptyView {
    init(wash: Wash?) {
        self.wash = wash
        self.content = nil
    }

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 20)
                .fill(Color(hex: "#141518"))
                .overlay(
                    RadialGradient(
                        gradient: Gradient(stops: [
                            .init(color: washColor, location: 0),
                            .init(color: .clear, location: 0.7)
                        ]),
                        center: UnitPoint(x: 0.5, y: 1.3),
                        startRadius: 0,
                        endRadius: 280
                    )
                    .clipShape(RoundedRectangle(cornerRadius: 20))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 20)
                        .stroke(Color.white.opacity(0.035), lineWidth: 1)
                )
        }
    }
}

// MARK: - Shared sub-components

struct AgentWho: View {
    let task: AgentTask?
    let label: String

    var body: some View {
        HStack(spacing: 7) {
            if let task = task {
                Circle().fill(Color(hex: task.color)).frame(width: 8, height: 8)
                Text(task.name).font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8"))
            }
            Text(label).font(.system(size: 12)).foregroundColor(Color(hex: "#8E939C"))
        }
    }
}

/// The small orange capsule at the end of the approval card's first row, on high-risk requests only.
struct RiskBadge: View {
    var body: some View {
        Text("High risk")
            .font(.system(size: 10, weight: .semibold))
            .foregroundColor(Color(hex: "#F5A524"))
            .padding(.horizontal, 7).padding(.vertical, 2)
            .background(Color(hex: "#F5A524").opacity(0.16))
            .overlay(Capsule().stroke(Color(hex: "#F5A524").opacity(0.45), lineWidth: 0.5))
            .clipShape(Capsule())
    }
}

struct CodeBlock: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 12, design: .monospaced))
            .padding(.horizontal, 10).padding(.vertical, 5)
            .background(Color.white.opacity(0.07))
            .overlay(RoundedRectangle(cornerRadius: 10).stroke(Color.white.opacity(0.06)))
            .clipShape(RoundedRectangle(cornerRadius: 10))
            .foregroundColor(Color(hex: "#E8E9EC"))
    }
}

struct ContextChip: View {
    let context: PromptContext
    @State private var glowing = false

    var label: String {
        switch context {
        case .window(let app, _, let url):
            if let url = url, let host = URL(string: url)?.host { return "\(app) · \(host)" }
            return app
        case .file(let name, _): return name
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(LinearGradient(colors: [Color(hex: "#FF6B5B"), Color(hex: "#F7B32B"), Color(hex: "#2DD4A7"), Color(hex: "#38BDF8"), Color(hex: "#A78BFA")], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: 7, height: 7)
            Text(label)
                .font(.system(size: 11.5))
                .foregroundColor(Color(hex: "#F1F2F4"))
        }
        .padding(.horizontal, 10).padding(.vertical, 4)
        .background(Color.white.opacity(0.1))
        .clipShape(Capsule())
        .overlay(Capsule().stroke(Color.white.opacity(glowing ? 0.75 : 0), lineWidth: 1.5))
        .scaleEffect(glowing ? 1.06 : 1.0)
        .onAppear {
            withAnimation(.spring(response: 0.25, dampingFraction: 0.55)) { glowing = true }
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.45) {
                withAnimation(.easeOut(duration: 0.3)) { glowing = false }
            }
        }
    }
}

struct MailField: View {
    let label: String
    let placeholder: String
    @Binding var text: String

    var body: some View {
        HStack(spacing: 8) {
            Text(label)
                .font(.system(size: 12.5))
                .foregroundColor(Color(hex: "#80858E"))
                .frame(width: 44, alignment: .leading)
            TextField(placeholder, text: $text)
                .textFieldStyle(.plain)
                .font(.system(size: 12.5))
                .foregroundColor(Color(hex: "#F5F6F8"))
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 10))
    }
}

struct ShimmeringText: View {
    let text: String
    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text)
            .foregroundStyle(
                LinearGradient(
                    stops: [
                        .init(color: Color(hex: "#7c818a"), location: 0),
                        .init(color: .white, location: 0.4),
                        .init(color: Color(hex: "#7c818a"), location: 0.7)
                    ],
                    startPoint: .leading,
                    endPoint: .trailing
                )
            )
    }
}

struct ShimmerOverlay: View {
    @State private var phase: CGFloat = 0.0

    var body: some View {
        LinearGradient(
            stops: [
                // Clamp all locations to [0,1] and keep them ordered
                .init(color: .clear,                   location: max(0, phase - 0.3)),
                .init(color: Color.white.opacity(0.6), location: max(0, min(1, phase))),
                .init(color: .clear,                   location: min(1, phase + 0.3))
            ],
            startPoint: .leading, endPoint: .trailing
        )
        .blendMode(.overlay)
        .onAppear {
            withAnimation(.linear(duration: 2.2).repeatForever(autoreverses: false)) {
                phase = 1.3  // travels left→right, exits right edge cleanly
            }
        }
    }
}

// MARK: - Button styles

struct PrimaryButton: View {
    let title: String
    let kbd: String?
    let action: () -> Void

    init(_ title: String, kbd: String? = nil, action: @escaping () -> Void) {
        self.title = title; self.kbd = kbd; self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(title).font(.system(size: 12.5, weight: .medium))
                if let k = kbd {
                    Text(k).font(.system(size: 10.5))
                        .padding(.horizontal, 4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.black.opacity(0.4)))
                        .opacity(0.55)
                }
            }
            .padding(.horizontal, 13).padding(.vertical, 7)
            .background(Color(hex: "#F5F6F8"))
            .foregroundColor(Color(hex: "#0B0C0E"))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct SecondaryButton: View {
    let title: String
    let kbd: String?
    let action: () -> Void

    init(_ title: String, kbd: String? = nil, action: @escaping () -> Void) {
        self.title = title; self.kbd = kbd; self.action = action
    }

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Text(title).font(.system(size: 12.5, weight: .medium))
                if let k = kbd {
                    Text(k).font(.system(size: 10.5))
                        .padding(.horizontal, 4)
                        .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.4)))
                        .opacity(0.55)
                }
            }
            .padding(.horizontal, 13).padding(.vertical, 7)
            .background(Color.white.opacity(0.09))
            .foregroundColor(Color(hex: "#F1F2F4"))
            .clipShape(Capsule())
        }
        .buttonStyle(.plain)
    }
}

struct IconButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 28, height: 28)
            .background(Color.white.opacity(0.08))
            .clipShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}

struct SendButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .frame(width: 28, height: 28)
            .background(Color(hex: "#F5F6F8"))
            .clipShape(Circle())
            .scaleEffect(configuration.isPressed ? 0.94 : 1)
    }
}

// MARK: - Settings island view (Point 7)

struct SettingsIslandView: View {
    @ObservedObject var state: AppState

    private var claudeConnected: Bool {
        let url = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".claude/settings.json")
        guard let data = try? Data(contentsOf: url),
              let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let hooks = json["hooks"] as? [String: Any],
              let ss = hooks["SessionStart"] as? [[String: Any]] else { return false }
        return ss.contains { matcher in
            (matcher["hooks"] as? [[String: Any]])?.contains {
                ($0["command"] as? String)?.contains("NotchMeow") == true
            } ?? false
        }
    }

    private var apiConnected: Bool {
        KeychainStore.shared.get("anthropic-api-key") != nil
    }

    var body: some View {
        ZStack(alignment: .leading) {
            CardBackground(wash: nil)
            VStack(alignment: .leading, spacing: 10) {
                // Sound row
                HStack(spacing: 10) {
                    Toggle("", isOn: $state.soundEnabled)
                        .toggleStyle(.switch)
                        .labelsHidden()
                        .scaleEffect(0.75)
                        .frame(width: 44)
                    Text("Sound")
                        .font(.system(size: 12.5))
                        .foregroundColor(Color(hex: "#C5C8CD"))
                    Slider(value: $state.soundVolume, in: 0...0.2)
                        .frame(width: 72)
                        .opacity(state.soundEnabled ? 1 : 0.4)
                }

                // Auto-close row
                HStack(spacing: 10) {
                    Image(systemName: "timer")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .frame(width: 16)
                    Text("Auto-close · \(Int(state.autoCloseInterval))s")
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#C5C8CD"))
                    Spacer()
                    HStack(spacing: 6) {
                        ForEach([10, 15, 30], id: \.self) { s in
                            Button("\(s)s") {
                                state.autoCloseInterval = Double(s)
                            }
                            .font(.system(size: 11))
                            .padding(.horizontal, 7).padding(.vertical, 3)
                            .background(state.autoCloseInterval == Double(s) ? Color(hex: "#252830") : Color.clear)
                            .foregroundColor(state.autoCloseInterval == Double(s) ? Color(hex: "#F5F6F8") : Color(hex: "#6B7079"))
                            .clipShape(Capsule())
                            .buttonStyle(.plain)
                        }
                    }
                }

                // Connection status
                HStack(spacing: 14) {
                    StatusBadge(label: "Claude Code", ok: claudeConnected)
                    StatusBadge(label: "API", ok: apiConnected)
                    Spacer()
                    Button("Settings…") {
                        NotificationCenter.default.post(name: .openFullSettings, object: nil)
                    }
                    .font(.system(size: 11.5))
                    .foregroundColor(Color(hex: "#8E939C"))
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 84)
            .padding(.trailing, 16)
            .padding(.vertical, 14)
        }
    }
}

struct StatusBadge: View {
    let label: String
    let ok: Bool

    var body: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(ok ? Color(hex: "#22C55E") : Color(hex: "#F4505E"))
                .frame(width: 6, height: 6)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#8E939C"))
        }
    }
}

// MARK: - Color extension (lighten)

// MARK: - Chat-provider switch (used by AI pill buttons and ↗ action)

/// Mirrors ModelPickerView provider-chip tap: animates, fires surprised emote + "pop" sound,
/// then opens the chat view. No-op if provider is already selected (just opens chat).
@MainActor
func switchChatProvider(_ provider: ChatProvider) {
    let state = AppState.shared
    let id = provider.providerID
    var ref: ModelRef?
    if id.isCloud {
        ref = ModelRef(provider: id, model: AIService.shared.cloudModel(id))
    } else if let server = state.localServers.first(where: { $0.serverID == id.rawValue }),
              let model = AIService.shared.localModel(server) {
        ref = ModelRef(provider: id, model: model, serverID: server.serverID)
    }
    if let ref, state.choice(for: .chat) != .explicit(ref) {
        withAnimation(.spring(response: 0.25, dampingFraction: 0.7)) {
            state.setChoice(.explicit(ref), for: .chat)
        }
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.surprised)
        SoundEngine.shared.play("pop")
    }
    state.view = .prompt
}

extension Color {
    func lighter(by amount: Double) -> Color {
        guard let components = NSColor(self).usingColorSpace(.sRGB) else { return self }
        return Color(
            red: min(1, Double(components.redComponent) + amount),
            green: min(1, Double(components.greenComponent) + amount),
            blue: min(1, Double(components.blueComponent) + amount)
        )
    }
}
