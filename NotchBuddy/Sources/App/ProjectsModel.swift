import Combine
import Foundation

// The Projects model (sub-project P-mac, Task 5): the one place the notch's Projects state lives. It holds the registry and each session's step in memory,
// the pin, the last click, the panel's open state and the layout, and it runs the one tick: a one-shot timer, armed only while the island is expanded, whose
// deadline is the nearest time-based change. Foundation and Combine only: no repeating timer and no delayed dispatch. The wall clock (`now`) and the timer
// (`schedule`) are injected, so the tests drive both. The shared instance and its wiring to the island are Task 8's.
//
// A step is taken from a PreToolUse only, reduced to the tool's path or file name (SessionStepText's words), so a command or a query never becomes one.
// Nothing here logs, stores or sends anything: the full folder lives in `registry` alone.

/// The step a PreToolUse leaves on its session: SessionStepText's words with the tool's input reduced to its `path` and `file_path` keys (so `Bash` without a
/// command is "Runs"), cleaned as the notch shows it. nil for AskUserQuestion, for any event that is not a PreToolUse, or for a tool with no name.
enum ProjectsStep {
    static func line(payload: [String: Any]) -> String? {
        guard (payload["hook_event_name"] as? String) == "PreToolUse",
              let tool = payload["tool_name"] as? String, !tool.isEmpty, tool != "AskUserQuestion" else { return nil }
        var input: [String: Any] = [:]
        if let raw = payload["tool_input"] as? [String: Any] {
            for key in ["path", "file_path"] {
                if let value = raw[key] as? String { input[key] = value }
            }
        }
        return ProjectsRules.cleanStep(SessionStepText.line(tool: tool, input: input))
    }
}

/// The delay of the one tick (ProjectsClock.nextDelay): the nearest of the next "… ago" minute (AGO_TICK_MS from now), a shown finished ending, an open
/// ask's end and a working session's turn to idle. Only a boundary strictly after `now` counts (one at exactly `now` has passed: the contract's later side);
/// the result is never below 50 ms.
enum ProjectsClock {
    static let floorMs = 50.0

    static func nextDelay(_ r: PJRegistry, now: Double) -> Double {
        var best = ProjectsRules.agoTickMs
        func consider(_ at: Double) {
            let d = at - now
            if d > 0, d < best { best = d }
        }
        for s in r.sessions {
            if s.run == "working" {
                consider(ProjectsRegistry.finite0(s.lastAt) + ProjectsRules.quietIdleMs)
            }
            if s.run == "finished", let finished = s.finishedAt {
                consider(ProjectsRegistry.finite0(finished) + ProjectsRules.finishedMs)
            }
            for ask in s.pending where ask.kind == "approval" || ask.kind == "question" {
                let wait = ask.inApp ? ProjectsRules.appWaitMs
                    : (ask.kind == "approval" ? ProjectsRules.cardApprovalMs : ProjectsRules.cardQuestionMs)
                consider(ProjectsRegistry.finite0(ask.at) + wait)
            }
        }
        return max(floorMs, best)
    }
}

@MainActor
final class ProjectsModel: ObservableObject {
    /// The marker of the Projects view in every build (scripts/check-app-binary.sh looks for it).
    static let marker = "NM_PROJECTS_VIEW_ACTIVE"

    typealias Cancel = @MainActor () -> Void
    typealias Schedule = @MainActor (_ afterMs: Double, _ fire: @escaping @MainActor () -> Void) -> Cancel

    private let now: @MainActor () -> Double
    private let schedule: Schedule

    /// The sessions in memory. Not published: `feed` sends `objectWillChange` only when what the island shows changes.
    private(set) var registry: PJRegistry
    /// Each session's step text, in memory only; a key leaves with its session.
    private(set) var steps: [String: String] = [:]
    @Published private(set) var pinned: String?
    @Published private(set) var clicked: String?
    /// The expanded section under the two panels: opened by the chevron, remembered while the app runs.
    @Published var panelOpen = false
    @Published private(set) var layout: ProjectsRules.Layout = .agents
    @Published private(set) var panelShown = false
    /// The project whose peek is open over the left card, in memory only: the big cat and the kittens step aside while it is set. The overview's hover is its only writer.
    @Published private(set) var peekingProject: String?
    /// Whether the one tick is armed (for the tests).
    private(set) var tickArmed = false

    private var cancelTick: Cancel?
    /// The absolute time the armed tick fires (nil when nothing is armed).
    private(set) var deadline: Double?
    private var expanded = false
    private var activePills: [String] = []
    private var focusId: String?
    private var twoCats = false

    init(home: String, now: @escaping @MainActor () -> Double, schedule: @escaping Schedule) {
        self.now = now
        self.schedule = schedule
        self.registry = PJRegistry.empty(home: home)
    }

    // MARK: - Events

    /// One hook payload into the model: the event into the registry, the session's step, then the big card's pin and click are kept. The view is sent a
    /// change only when what it shows differs (the times and ages do not count). While the island is expanded the tick is re-armed for the new state.
    func feed(payload: [String: Any], waitIn: String? = nil) {
        guard let ev = ProjectsRegistry.eventFrom(payload, now: now(), waitIn: waitIn) else { return }
        let before = Self.shown(view())
        registry = ProjectsRegistry.apply(registry, ev)
        updateSteps(ev, payload: payload)
        let after = view()
        if Self.shown(after) != before {
            objectWillChange.send()
        }
        reconcile(after)
        if expanded { rearmIfEarlier() }
    }

    private func updateSteps(_ ev: PJEvent, payload: [String: Any]) {
        if ev.agent == ProjectsRegistry.claudeTag, !ev.sessionId.isEmpty {
            if ev.kind == "preTool", let line = ProjectsStep.line(payload: payload) {
                steps[ev.sessionId] = line
            } else if ev.kind == "prompt" {
                steps[ev.sessionId] = nil
            }
        }
        steps = steps.filter { key, _ in registry.sessions.contains { ProjectsRegistry.same($0.id, key) } }
    }

    /// The view as the island shows it: the same, with every project's and session's last activity and "… ago" count set to 0, so a time alone is no change.
    static func shown(_ v: PJView) -> PJView {
        var c = v
        for i in c.projects.indices {
            c.projects[i].lastAt = 0
            c.projects[i].agoMin = 0
            for j in c.projects[i].sessions.indices {
                c.projects[i].sessions[j].lastAt = 0
                c.projects[i].sessions[j].agoMin = 0
            }
        }
        return c
    }

    // MARK: - Reads

    /// The view at now, with the steps; the project's cat when the caller gives one.
    func view(projectCats: [String: String] = [:], mainCat: String? = nil) -> PJView {
        ProjectsSnapshot.view(registry, now: now(), steps: steps, projectCats: projectCats, mainCat: mainCat)
    }

    private static func keys(_ v: PJView) -> [PJOrderKey] {
        v.projects.map { PJOrderKey(id: $0.id, state: $0.state, lastAt: $0.lastAt) }
    }

    /// The big card: the pinned project, else the clicked one, else the most recently active; reads only.
    func bigCard(in view: PJView) -> PJProject? {
        guard let id = ProjectsSnapshot.bigCardOf(Self.keys(view), pinned: pinned, clicked: clicked).project else { return nil }
        return view.projects.first { ProjectsRegistry.same($0.id, id) }
    }

    /// Stores the big card's pin and click back, and the peek: a pin, a click or a peek goes once its project is gone (a peek for a project that ended would keep the big cat
    /// and the kittens faded, as nothing would send its hover-out).
    func reconcile(_ view: PJView) {
        let card = ProjectsSnapshot.bigCardOf(Self.keys(view), pinned: pinned, clicked: clicked)
        if card.pinned != pinned { pinned = card.pinned }
        if card.clicked != clicked { clicked = card.clicked }
        if let id = peekingProject, !Self.has(view, id) { peekingProject = nil }
    }

    private static func has(_ view: PJView, _ id: String) -> Bool {
        view.projects.contains { ProjectsRegistry.same($0.id, id) }
    }

    // MARK: - Pin and click

    /// A click on a pill: that project is the big card (unless a pin holds).
    func select(_ projectId: String) {
        if clicked != projectId { clicked = projectId }
    }

    /// Pins a project, or unpins it when it is the pinned one. One pin at a time. Only a live project can be pinned: the Pin menu is modal, so its project may have ended
    /// while it was open, and a pin on it would come back when the folder does. The pin is reconciled after the toggle.
    func togglePin(_ projectId: String) {
        let live = view()
        if Self.has(live, projectId) { pinned = pinned == projectId ? nil : projectId }
        reconcile(live)
    }

    func isPinned(_ projectId: String) -> Bool {
        pinned == projectId
    }

    /// The overview opens or closes a project's peek. Publishes only on a change.
    func setPeeking(_ id: String?) {
        if peekingProject != id { peekingProject = id }
    }

    // MARK: - Layout

    /// The island's layout and the expanded section: the layout keeps while open and follows Claude-only when folded; the section's height is written to
    /// `ProjectsLayout.extraHeight`. The arguments are kept for `relayout`. `twoCats`: Two cats mode keeps today's overview, so it has no section.
    func refreshLayout(activePills: [String], open: Bool, focusId: String?, twoCats: Bool) {
        self.activePills = activePills
        self.focusId = focusId
        self.twoCats = twoCats
        let claudeOnly = ProjectsRules.claudeOnly(activePills: activePills, otherAgentSeen: registry.otherAgentSeen)
        let next = ProjectsRules.islandLayout(current: layout, claudeOnly: claudeOnly, open: open)
        if next != layout { layout = next }
        let shown = ProjectsLayout.panelShown(panelOpen: panelOpen, layout: layout, focusId: focusId, projectCount: view().projects.count, twoCats: twoCats)
        // The height first: the island reads it when it sees `panelShown` change.
        ProjectsLayout.extraHeight = shown ? ProjectsLayout.panelExtra : 0
        if shown != panelShown { panelShown = shown }
    }

    /// The chevron: opens or closes the section, and reads the layout again at once so `panelShown` and the island's height follow.
    func togglePanel() {
        panelOpen.toggle()
        relayout(open: expanded)
    }

    /// `refreshLayout` with the last pills, focus and Two cats value.
    func relayout(open: Bool) {
        refreshLayout(activePills: activePills, open: open, focusId: focusId, twoCats: twoCats)
    }

    // MARK: - The one tick

    /// The island expanded or folded. Expanded arms the tick (one timer, the nearest boundary); folded cancels it, and nothing is armed while folded.
    func islandExpanded(_ expanded: Bool) {
        self.expanded = expanded
        if !expanded { setPeeking(nil) }
        disarm()
        if expanded { arm() }
    }

    /// Arms the tick for the nearest boundary from now, and keeps its absolute deadline.
    private func arm() {
        disarm()
        let t = now()
        let delay = ProjectsClock.nextDelay(registry, now: t)
        tickArmed = true
        deadline = t + delay
        cancelTick = schedule(delay) { [weak self] in
            self?.fire()
        }
    }

    /// Re-arms only when the nearest boundary is earlier than the armed deadline (or nothing is armed), so a stream of events never pushes the tick back.
    private func rearmIfEarlier() {
        let t = now()
        let due = t + ProjectsClock.nextDelay(registry, now: t)
        if let armed = deadline, due >= armed { return }
        arm()
    }

    private func disarm() {
        cancelTick?()
        cancelTick = nil
        deadline = nil
        tickArmed = false
    }

    /// The tick's time came: the "… ago" words and the time-based states may have changed, so the view is sent, the pin and the click are kept, the layout is
    /// read again, and the tick is armed for the next boundary.
    private func fire() {
        tickArmed = false
        cancelTick = nil
        deadline = nil
        objectWillChange.send()
        reconcile(view())
        // A tick that was already due when the island folded changes nothing: the layout is read only while the island is open.
        guard expanded else { return }
        relayout(open: true)
        arm()
    }
}
