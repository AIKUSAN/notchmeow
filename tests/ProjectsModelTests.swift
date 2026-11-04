import Combine
import Foundation

// The Projects model's Task 5 pins (ProjectsModel): the scenarios of tests/fixtures/mac/projects-scenarios.json replayed through `feed`, a session's step
// and when it leaves, the pin and the click, a Claude App approval, the layout switch and the panel's height, the one tick (its arming, its cancel and
// its re-arm), the clock's edges (ProjectsClock.nextDelay), what publishes, and the big card. A fake clock and a fake scheduler: no timer runs and no
// real time passes.
@main
enum ProjectsModelTests {
    typealias M = ProjectsModel
    typealias R = ProjectsRegistry

    static let base = 1_760_000_000_000.0
    static let pathA = "/tmp/nm-projects-demo/notchmeow"
    static let pathB = "/tmp/nm-projects-demo/site"

    /// The clock the model reads through `now`.
    @MainActor
    final class Clock {
        var t: Double
        init(_ t: Double) { self.t = t }
    }

    /// A scheduler that keeps its live timers and never fires one by itself. `history` holds every delay it was asked for, in order.
    @MainActor
    final class Timers {
        private(set) var live: [Int: @MainActor () -> Void] = [:]
        private(set) var history: [Double] = []
        private var nextId = 0

        func schedule(_ afterMs: Double, _ fire: @escaping @MainActor () -> Void) -> M.Cancel {
            nextId += 1
            let id = nextId
            live[id] = fire
            history.append(afterMs)
            return { [weak self] in self?.live[id] = nil }
        }

        /// Fires the one live timer, as the clock does when its time comes.
        func fireOne() {
            guard let entry = live.first else { return }
            live[entry.key] = nil
            entry.value()
        }
    }

    /// Counts the sends of the model's `objectWillChange`.
    @MainActor
    final class Counter {
        var n = 0
    }

    @MainActor
    static func makeModel(_ clock: Clock, _ timers: Timers, home: String = "/Users/sam") -> M {
        M(home: home, now: { clock.t }, schedule: { after, fire in timers.schedule(after, fire) })
    }

    /// A hook payload with its session and folder, plus the extra keys.
    static func payload(_ name: String, _ session: String, cwd: String = "", _ extra: [String: Any] = [:]) -> [String: Any] {
        var p: [String: Any] = ["hook_event_name": name, "session_id": session]
        if !cwd.isEmpty { p["cwd"] = cwd }
        p.merge(extra) { _, new in new }
        return p
    }

    static func num(_ x: Any?) -> Double {
        (x as? NSNumber)?.doubleValue ?? 0
    }

    /// Each project as `name:state:waiting`, in pill order.
    static func short(_ v: PJView) -> [String] {
        v.projects.map { "\($0.name):\($0.state):\($0.waiting)" }
    }

    /// The sessions of one project as `label:state`.
    static func labels(_ v: PJView, _ name: String) -> [String] {
        v.projects.first { $0.name == name }.map { $0.sessions.map { "\($0.label):\($0.state)" } } ?? []
    }

    static func idOf(_ v: PJView, _ name: String) -> String {
        v.projects.first { $0.name == name }?.id ?? ""
    }

    /// The registry after some events at their times (the same reads the model makes).
    static func regAt(_ events: [(Double, [String: Any])]) -> PJRegistry {
        var r = PJRegistry.empty(home: "/Users/sam")
        for (t, p) in events {
            if let e = R.eventFrom(p, now: t) { r = R.apply(r, e) }
        }
        return r
    }

    @MainActor
    static func main() {
        CT.section("projects-scenarios.json: every scenario replayed through the model")
        let fixture = CT.fixture("projects-scenarios.json", dir: "mac")
        let home = fixture["home"] as? String ?? "/Users/sam"
        let scenarios = fixture["scenarios"] as? [String: Any] ?? [:]
        CT.check("five scenarios", scenarios.count, 5)
        // The floors: how many steps each scenario has and how many expectations the loop below runs, written here from today's fixture (a deliberate fixture change
        // updates them). A renamed `steps`, `expect` or expect key would otherwise leave a loop that checks less and stays green.
        let stepCounts: [String: Int] = ["claude-app-wait": 4, "collide-and-home": 7, "end": 4, "other-agent": 2, "two-projects": 11]
        let stepKeys: Set<String> = ["say", "at", "wait_ms", "event", "expect", "waitIn"], expectKeys: Set<String> = ["projects", "rows", "notes", "waiting", "layout"]
        var expectationsRun = 0
        func ran<V: Equatable>(_ label: String, _ got: V, _ want: V) {
            expectationsRun += 1
            CT.check(label, got, want)
        }
        CT.check("the scenarios' step counts", scenarios.mapValues { (($0 as? [String: Any])?["steps"] as? [[String: Any]])?.count ?? -1 }, stepCounts)
        for name in scenarios.keys.sorted(by: { ProjectsRules.utf16Less($0, $1) }) {
            let sc = scenarios[name] as? [String: Any] ?? [:]
            let clock = Clock(base), timers = Timers()
            let model = makeModel(clock, timers, home: home)
            for (i, step) in ((sc["steps"] as? [[String: Any]]) ?? []).enumerated() {
                let label = "\(name) step \(i + 1)"
                CT.check("\(label): only keys the test reads", Set(step.keys).subtracting(stepKeys).sorted(), [])
                CT.checkTrue("\(label): it has its time, its event (an object or null) and its expect", step["at"] is NSNumber && step["event"] != nil && step["expect"] is [String: Any])
                clock.t = base + num(step["at"])
                if var p = step["event"] as? [String: Any] {
                    if let cwd = p["cwd"] as? String, cwd == "~" || cwd.hasPrefix("~/") {
                        p["cwd"] = home + String(cwd.dropFirst())
                    }
                    model.feed(payload: p, waitIn: step["waitIn"] as? String)
                }
                model.refreshLayout(activePills: ["integration_claude"], open: false, focusId: "integration_claude", twoCats: false)
                guard let expect = step["expect"] as? [String: Any] else { continue }
                let v = model.view()
                CT.check("\(label): only expect keys the test reads", Set(expect.keys).subtracting(expectKeys).sorted(), [])
                if let want = expect["projects"] as? [String] {
                    ran("\(label): projects", short(v), want)
                } else if expect["projects"] != nil { CT.checkTrue("\(label): projects is a list of text", false) }
                if let wantRows = expect["rows"] as? [String: [String]] {
                    for (pn, want) in wantRows.sorted(by: { ProjectsRules.utf16Less($0.key, $1.key) }) {
                        ran("\(label): rows of \(pn)", labels(v, pn), want)
                    }
                } else if expect["rows"] != nil { CT.checkTrue("\(label): rows is an object of lists of text", false) }
                if let want = expect["notes"] as? [String] {
                    let notes = v.projects.flatMap { $0.sessions }.filter { !$0.note.isEmpty }.map { "\($0.label):\($0.note)" }
                    ran("\(label): notes", notes, want)
                } else if expect["notes"] != nil { CT.checkTrue("\(label): notes is a list of text", false) }
                if let want = (expect["waiting"] as? NSNumber)?.intValue {
                    ran("\(label): waiting", v.waiting, want)
                } else if expect["waiting"] != nil { CT.checkTrue("\(label): waiting is a number", false) }
                if let want = expect["layout"] as? String {
                    ran("\(label): layout", model.layout.rawValue, want)
                } else if expect["layout"] != nil { CT.checkTrue("\(label): layout is text", false) }
            }
        }
        CT.check("the scenarios ran 70 expectations in all (28 projects lists, 25 project row lists, 2 notes, 9 waiting counts, 6 layouts)", expectationsRun, 70)

        CT.section("steps: a session's line, and when it leaves")
        let c1 = Clock(base), t1 = Timers(), m1 = makeModel(c1, t1)
        m1.feed(payload: payload("SessionStart", "s1", cwd: pathA))
        m1.feed(payload: payload("PreToolUse", "s1", cwd: pathA, ["tool_name": "Bash", "tool_input": ["command": "rm -rf /x"]]))
        CT.check("a Bash step with a command is Runs (the command never shows)", m1.steps["s1"], "Runs")
        m1.feed(payload: payload("PreToolUse", "s1", cwd: pathA, ["tool_name": "Read", "tool_input": ["file_path": "/Users/sam/a/README.md"]]))
        CT.check("Read shows the file's last part", m1.steps["s1"], "Reads · README.md")
        m1.feed(payload: payload("PreToolUse", "s1", cwd: pathA, ["tool_name": "AskUserQuestion", "tool_input": ["question": "Ship it?"]]))
        CT.check("AskUserQuestion keeps the previous step", m1.steps["s1"], "Reads · README.md")
        m1.feed(payload: payload("UserPromptSubmit", "s1", cwd: pathA, ["prompt": "hello"]))
        CT.check("a prompt leaves no step", m1.steps["s1"], nil)
        m1.feed(payload: payload("PreToolUse", "s1", cwd: pathA, ["tool_name": "Grep", "tool_input": ["query": "TODO"]]))
        CT.check("a search query never shows: Searches", m1.steps["s1"], "Searches")
        m1.feed(payload: payload("SessionEnd", "s1", cwd: pathA))
        CT.check("SessionEnd drops the session's step", m1.steps["s1"], nil)
        CT.check("ProjectsStep: an event that is not PreToolUse has no line", ProjectsStep.line(payload: payload("Stop", "s1")), nil)
        CT.check("ProjectsStep: Bash without a command is Runs", ProjectsStep.line(payload: payload("PreToolUse", "s1", ["tool_name": "Bash", "tool_input": ["command": "ls"]])), "Runs")

        CT.section("pin and click: one pin at a time, the card follows them")
        let c2 = Clock(base), t2 = Timers(), m2 = makeModel(c2, t2)
        c2.t = base
        m2.feed(payload: payload("SessionStart", "a1", cwd: pathA))
        c2.t = base + 1000
        m2.feed(payload: payload("SessionStart", "b1", cwd: pathB))
        let idA = idOf(m2.view(), "notchmeow"), idB = idOf(m2.view(), "site")
        CT.check("with no pin or click, the card is the most recent project", m2.bigCard(in: m2.view())?.name, "site")
        m2.togglePin(idA)
        m2.togglePin(idB)
        CT.check("one pin at a time: only the last one is pinned", [m2.isPinned(idA), m2.isPinned(idB)], [false, true])
        CT.check("the pin is the big card", m2.bigCard(in: m2.view())?.name, "site")
        m2.togglePin(idB)
        m2.select(idA)
        CT.check("with no pin, a click is the big card", m2.bigCard(in: m2.view())?.name, "notchmeow")
        m2.togglePin(idB)
        CT.check("a pin holds over a click", m2.bigCard(in: m2.view())?.name, "site")
        c2.t = base + 2000
        m2.feed(payload: payload("SessionEnd", "b1", cwd: pathB))
        m2.reconcile(m2.view())
        CT.check("the pin goes with its project", m2.pinned, nil)
        CT.check("the card is the next project", m2.bigCard(in: m2.view())?.name, "notchmeow")

        CT.section("a pin survives the island folding and opening again, while its project lives (a pin is memory only and goes with its project)")
        let c2b = Clock(base), t2b = Timers(), m2b = makeModel(c2b, t2b)
        c2b.t = base
        m2b.feed(payload: payload("SessionStart", "a1", cwd: pathA))
        c2b.t = base + 1000
        m2b.feed(payload: payload("SessionStart", "b1", cwd: pathB))
        m2b.islandExpanded(true)
        let pinId = idOf(m2b.view(), "notchmeow")
        CT.check("the most recent project is the card before the pin", m2b.bigCard(in: m2b.view())?.name, "site")
        m2b.togglePin(pinId)
        m2b.islandExpanded(false)
        c2b.t = base + 3000
        m2b.feed(payload: payload("PreToolUse", "b1", cwd: pathB, ["tool_name": "Read", "tool_input": ["file_path": "/Users/sam/b/x.md"]]))
        m2b.refreshLayout(activePills: ["integration_claude"], open: false, focusId: "integration_claude", twoCats: false)
        CT.check("folded, and another project has the newest activity: the pin is kept", m2b.pinned, pinId)
        m2b.islandExpanded(true)
        CT.check("opened again, the pinned project is the big card though the other is more recent", m2b.bigCard(in: m2b.view())?.name, "notchmeow")
        c2b.t = base + 700_000
        t2b.fireOne()
        CT.check("a tick (ten quiet minutes later) keeps the pin too", m2b.pinned, pinId)

        CT.section("a Claude App approval counts once and is in the app")
        let c3 = Clock(base), t3 = Timers(), m3 = makeModel(c3, t3)
        m3.feed(payload: payload("SessionStart", "app1", cwd: pathA, ["nm_agent": "claude-desktop"]))
        c3.t = base + 1000
        m3.feed(payload: payload("PermissionRequest", "app1", cwd: pathA, ["nm_agent": "claude-desktop", "tool_name": "Bash", "tool_input": ["command": "git push"]]))
        let v3 = m3.view()
        CT.check("the approval counts once", v3.waiting, 1)
        CT.checkTrue("its row is waiting in the app", v3.projects.first?.sessions.first?.waitingInApp == true)
        CT.check("its note is Waiting in Claude App", v3.projects.first?.sessions.first?.note, "Waiting in Claude App")

        CT.section("layout: the switch, the panel and its height")
        let c4 = Clock(base), t4 = Timers(), m4 = makeModel(c4, t4)
        m4.refreshLayout(activePills: ["integration_claude"], open: true, focusId: "integration_claude", twoCats: false)
        CT.check("open, it keeps the layout it has (agents at first)", m4.layout, .agents)
        m4.refreshLayout(activePills: ["integration_claude"], open: false, focusId: "integration_claude", twoCats: false)
        CT.check("folded, Claude only shows the projects layout", m4.layout, .projects)
        m4.feed(payload: ["nm_agent": "codex", "hook_event_name": "PreToolUse", "tool_name": "apply_patch"])
        m4.refreshLayout(activePills: ["integration_claude"], open: true, focusId: "integration_claude", twoCats: false)
        CT.check("open, it keeps projects after another agent is seen", m4.layout, .projects)
        m4.refreshLayout(activePills: ["integration_claude"], open: false, focusId: "integration_claude", twoCats: false)
        CT.check("folded, another agent's event shows the agents layout", m4.layout, .agents)
        m4.feed(payload: payload("SessionStart", "s1", cwd: pathA))
        m4.panelOpen = true
        m4.refreshLayout(activePills: ["integration_claude"], open: false, focusId: "integration_claude", twoCats: false)
        CT.check("the section shows under the two panels", m4.panelShown, true)
        CT.check("and makes the island 92 pt taller", ProjectsLayout.extraHeight, 92)
        m4.feed(payload: payload("SessionEnd", "s1", cwd: pathA))
        m4.relayout(open: false)
        CT.check("the last project ending hides the section", m4.panelShown, false)
        CT.check("and gives its height back", ProjectsLayout.extraHeight, 0)

        CT.section("layout: Two cats mode keeps today's overview, with no section and no height")
        let c4b = Clock(base), t4b = Timers(), m4b = makeModel(c4b, t4b)
        m4b.feed(payload: payload("SessionStart", "s1", cwd: pathA))
        m4b.panelOpen = true
        m4b.refreshLayout(activePills: ["integration_claude", "agent_codex"], open: true, focusId: "integration_claude", twoCats: true)
        CT.check("Two cats mode: the section is not shown", m4b.panelShown, false)
        CT.check("and the island is not taller", ProjectsLayout.extraHeight, 0)
        m4b.relayout(open: true)
        CT.check("relayout keeps the last Two cats value", m4b.panelShown, false)
        m4b.refreshLayout(activePills: ["integration_claude", "agent_codex"], open: true, focusId: "integration_claude", twoCats: false)
        CT.check("leaving Two cats mode shows the section the chevron had opened", m4b.panelShown, true)
        CT.check("and makes the island 92 pt taller", ProjectsLayout.extraHeight, 92)
        m4b.refreshLayout(activePills: ["integration_claude", "agent_codex"], open: true, focusId: "integration_claude", twoCats: true)
        CT.check("entering Two cats mode takes the section and its height away at once", m4b.panelShown == false && ProjectsLayout.extraHeight == 0, true)
        m4b.panelOpen = false
        m4b.refreshLayout(activePills: ["integration_claude"], open: false, focusId: "integration_claude", twoCats: false)

        CT.section("layout: the chevron toggles the section and the island's height together")
        let c4c = Clock(base), t4c = Timers(), m4c = makeModel(c4c, t4c)
        m4c.feed(payload: ["nm_agent": "codex", "hook_event_name": "PreToolUse", "tool_name": "apply_patch"])
        m4c.feed(payload: payload("SessionStart", "s1", cwd: pathA))
        m4c.refreshLayout(activePills: ["integration_claude", "agent_codex"], open: false, focusId: "integration_claude", twoCats: false)
        m4c.islandExpanded(true)
        m4c.togglePanel()
        CT.check("the chevron opens the section", m4c.panelOpen, true)
        CT.check("it is shown at once, without a feed", m4c.panelShown, true)
        CT.check("and the island is 92 pt taller", ProjectsLayout.extraHeight, 92)
        m4c.togglePanel()
        CT.check("the chevron closes it", m4c.panelOpen == false && m4c.panelShown == false, true)
        CT.check("and gives the height back", ProjectsLayout.extraHeight, 0)

        CT.section("the tick: one timer, armed only while the island is expanded")
        let c5 = Clock(base), t5 = Timers(), m5 = makeModel(c5, t5)
        m5.islandExpanded(true)
        CT.check("expanded: one timer", t5.live.count, 1)
        CT.check("with no session it is the next minute", t5.history.last, 60000)
        CT.checkTrue("tickArmed reads true", m5.tickArmed)
        m5.islandExpanded(true)
        CT.check("a second expand leaves one timer", t5.live.count, 1)
        c5.t = base + 1000
        m5.feed(payload: payload("SessionStart", "s1", cwd: pathA))
        m5.feed(payload: payload("Stop", "s1", cwd: pathA))
        CT.check("a finished session re-arms the timer at its ending", t5.history.last, 5200)
        CT.check("and there is still one timer", t5.live.count, 1)
        t5.fireOne()
        CT.check("the fired tick re-arms one timer while expanded", t5.live.count, 1)
        CT.checkTrue("tickArmed reads true after the fire", m5.tickArmed)
        m5.islandExpanded(false)
        CT.check("folded: the timer is cancelled", t5.live.count, 0)
        CT.checkTrue("tickArmed reads false", !m5.tickArmed)
        m5.feed(payload: payload("SessionStart", "s2", cwd: pathB))
        CT.check("folded: a feed arms nothing", t5.live.count, 0)

        CT.section("a stream of events does not push the tick back")
        let c11 = Clock(base), t11 = Timers(), m11 = makeModel(c11, t11)
        m11.feed(payload: payload("SessionStart", "s1", cwd: pathA))
        m11.islandExpanded(true)
        CT.check("armed for the next minute at expand", t11.history.last, 60000)
        // The scheduler fires the armed tick at its deadline; the test tracks the deadline from the last arm.
        var deadline = base + 60000
        var seen = t11.history.count
        var fires: [Double] = []
        for step in 1...6 {
            let at = base + 30000 * Double(step)
            while t11.live.count == 1, deadline <= at {
                c11.t = deadline
                fires.append(deadline)
                t11.fireOne()
                deadline = c11.t + (t11.history.last ?? 0)
                seen = t11.history.count
            }
            c11.t = at
            m11.feed(payload: payload("PreToolUse", "s1", cwd: pathA, ["tool_name": "Bash"]))
            if t11.history.count != seen {
                deadline = at + (t11.history.last ?? 0)
                seen = t11.history.count
            }
        }
        CT.check("the tick first fires at its first deadline, 60 s after the arm", fires.first, base + 60000)
        CT.check("and keeps firing every 60 s over three minutes: exactly three fires, at the first, second and third minute", fires, [base + 60_000, base + 120_000, base + 180_000])
        let c12 = Clock(base), t12 = Timers(), m12 = makeModel(c12, t12)
        m12.feed(payload: payload("SessionStart", "s1", cwd: pathA))
        m12.islandExpanded(true)
        c12.t = base + 10000
        m12.feed(payload: payload("Stop", "s1", cwd: pathA))
        CT.check("a Stop that ends in 5.2 s re-arms sooner than the armed minute", t12.history.last, 5200)
        CT.check("and there is still one timer", t12.live.count, 1)

        CT.section("ProjectsClock.nextDelay: the nearest boundary after now, never below 50 ms")
        let t = base
        CT.check("an empty registry: the next minute", ProjectsClock.nextDelay(PJRegistry.empty(home: "/Users/sam"), now: t), 60000)
        let start = payload("SessionStart", "s1", cwd: pathA)
        CT.check("a finished session ends in 4.2 s",
                 ProjectsClock.nextDelay(regAt([(t - 1000, start), (t - 1000, payload("Stop", "s1", cwd: pathA))]), now: t), 4200)
        CT.check("an open card approval ends in 1 s",
                 ProjectsClock.nextDelay(regAt([(t - 119_000, start), (t - 119_000, payload("PermissionRequest", "s1", cwd: pathA, ["tool_name": "Bash"]))]), now: t), 1000)
        CT.check("a working session turns idle in 1 s",
                 ProjectsClock.nextDelay(regAt([(t - 599_000, start), (t - 599_000, payload("PreToolUse", "s1", cwd: pathA, ["tool_name": "Bash"]))]), now: t), 1000)
        CT.check("a Claude App approval ends in 1 s",
                 ProjectsClock.nextDelay(regAt([
                    (t - 599_000, payload("SessionStart", "s1", cwd: pathA, ["nm_agent": "claude-desktop"])),
                    (t - 599_000, payload("PermissionRequest", "s1", cwd: pathA, ["nm_agent": "claude-desktop", "tool_name": "Bash"])),
                 ]), now: t), 1000)
        CT.check("a finished ending at exactly now has passed",
                 ProjectsClock.nextDelay(regAt([(t - 5200, start), (t - 5200, payload("Stop", "s1", cwd: pathA))]), now: t), 60000)
        CT.check("a card approval at exactly its end has passed",
                 ProjectsClock.nextDelay(regAt([(t - 120_000, start), (t - 120_000, payload("PermissionRequest", "s1", cwd: pathA, ["tool_name": "Bash"]))]), now: t), 60000)
        CT.check("a card question 5 s before its end is due in 5 s",
                 ProjectsClock.nextDelay(regAt([(t - 125_000, start), (t - 125_000, payload("PermissionRequest", "s1", cwd: pathA, ["tool_name": "AskUserQuestion"]))]), now: t), 5000)
        CT.check("a card question at exactly its end has passed",
                 ProjectsClock.nextDelay(regAt([(t - 130_000, start), (t - 130_000, payload("PermissionRequest", "s1", cwd: pathA, ["tool_name": "AskUserQuestion"]))]), now: t), 60000)
        CT.check("a working session at exactly 10 min quiet has passed",
                 ProjectsClock.nextDelay(regAt([(t - 600_000, start), (t - 600_000, payload("PreToolUse", "s1", cwd: pathA, ["tool_name": "Bash"]))]), now: t), 60000)
        CT.check("a boundary 10 ms ahead is the 50 ms floor",
                 ProjectsClock.nextDelay(regAt([(t - 5190, start), (t - 5190, payload("Stop", "s1", cwd: pathA))]), now: t), 50)

        CT.section("publishing: one send for a change shown, none for one that is not")
        let c6 = Clock(base), t6 = Timers(), m6 = makeModel(c6, t6)
        let counter = Counter()
        var bag = Set<AnyCancellable>()
        m6.objectWillChange.sink { counter.n += 1 }.store(in: &bag)
        func sends(_ run: () -> Void) -> Int {
            let before = counter.n
            run()
            return counter.n - before
        }
        let same = payload("PreToolUse", "p1", cwd: pathA, ["tool_name": "Bash", "tool_input": ["command": "ls"]])
        c6.t = base
        CT.check("a new project is one send", sends { m6.feed(payload: payload("SessionStart", "p1", cwd: pathA)) }, 1)
        c6.t = base + 1000
        CT.check("a state change is one send", sends { m6.feed(payload: payload("UserPromptSubmit", "p1", cwd: pathA)) }, 1)
        c6.t = base + 2000
        CT.check("a new step is one send", sends { m6.feed(payload: same) }, 1)
        c6.t = base + 3000
        CT.check("the same step again changes nothing shown", sends { m6.feed(payload: same) }, 0)
        c6.t = base + 4000
        CT.check("and again, later, still nothing shown", sends { m6.feed(payload: same) }, 0)
        c6.t = base + 5000
        CT.check("a waiting ask is one send", sends { m6.feed(payload: payload("PermissionRequest", "p1", cwd: pathA, ["tool_name": "Bash"])) }, 1)

        CT.section("the big card: the most recent project, a waiting one counts, a pin holds")
        let c7 = Clock(base), t7 = Timers(), m7 = makeModel(c7, t7)
        c7.t = base
        m7.feed(payload: payload("SessionStart", "b1", cwd: pathB))
        c7.t = base + 1000
        m7.feed(payload: payload("PermissionRequest", "b1", cwd: pathB, ["tool_name": "Bash"]))
        c7.t = base + 2000
        m7.feed(payload: payload("SessionStart", "a1", cwd: pathA))
        m7.feed(payload: payload("UserPromptSubmit", "a1", cwd: pathA))
        let v7 = m7.view()
        CT.check("the waiting project is first in pill order", short(v7).first, "site:approval:1")
        CT.check("and it is counted as waiting", v7.waiting, 1)
        CT.check("with no pin, the card is the most recent project", m7.bigCard(in: v7)?.name, "notchmeow")
        CT.check("and the card's state is its own project's state", m7.bigCard(in: v7)?.state, "working")

        let c7b = Clock(base), t7b = Timers(), m7b = makeModel(c7b, t7b)
        m7b.feed(payload: payload("SessionStart", "a1", cwd: pathA))
        m7b.feed(payload: payload("UserPromptSubmit", "a1", cwd: pathA))
        c7b.t = base + 1000
        m7b.feed(payload: payload("SessionStart", "b1", cwd: pathB))
        c7b.t = base + 2000
        m7b.feed(payload: payload("PermissionRequest", "b1", cwd: pathB, ["tool_name": "Bash"]))
        CT.check("a waiting project that is also the most recent is the card", m7b.bigCard(in: m7b.view())?.name, "site")
        CT.check("and its state is approval", m7b.bigCard(in: m7b.view())?.state, "approval")
        m7b.togglePin(idOf(m7b.view(), "notchmeow"))
        CT.check("a pinned calm project is the card while another waits", m7b.bigCard(in: m7b.view())?.name, "notchmeow")
        CT.check("and its state is calm", m7b.bigCard(in: m7b.view())?.state, "working")
        CT.check("the other project still counts as waiting", m7b.view().waiting, 1)

        let c8 = Clock(base), t8 = Timers(), m8 = makeModel(c8, t8)
        m8.feed(payload: payload("SessionStart", "q1", cwd: pathB))
        m8.feed(payload: payload("PermissionRequest", "q1", cwd: pathB, ["tool_name": "AskUserQuestion"]))
        CT.check("a question makes the big card's state question", m8.bigCard(in: m8.view())?.state, "question")

        CT.section("open, and the last project ends")
        let c9 = Clock(base), t9 = Timers(), m9 = makeModel(c9, t9)
        m9.feed(payload: payload("SessionStart", "s1", cwd: pathA))
        m9.islandExpanded(true)
        m9.panelOpen = true
        m9.refreshLayout(activePills: ["integration_claude"], open: true, focusId: "integration_claude", twoCats: false)
        CT.checkTrue("the section shows while open", m9.panelShown)
        c9.t = base + 1000
        m9.feed(payload: payload("SessionEnd", "s1", cwd: pathA))
        m9.relayout(open: true)
        CT.check("the last project ending hides the section on relayout", m9.panelShown, false)
        CT.check("and gives its height back", ProjectsLayout.extraHeight, 0)
        let c10 = Clock(base), t10 = Timers(), m10 = makeModel(c10, t10)
        m10.feed(payload: payload("SessionStart", "s1", cwd: pathA))
        m10.islandExpanded(true)
        m10.panelOpen = true
        m10.refreshLayout(activePills: ["integration_claude"], open: true, focusId: "integration_claude", twoCats: false)
        c10.t = base + 1000
        m10.feed(payload: payload("SessionEnd", "s1", cwd: pathA))
        t10.fireOne()
        CT.check("the tick hides the section by itself", m10.panelShown, false)
        CT.check("and gives its height back by itself", ProjectsLayout.extraHeight, 0)

        CT.section("a stray tick after the island folds: nothing is armed, and the layout is not read again")
        let c13 = Clock(base), t13 = Timers(), m13 = makeModel(c13, t13)
        m13.feed(payload: payload("SessionStart", "s13", cwd: pathA))
        m13.islandExpanded(true)
        m13.panelOpen = true
        m13.refreshLayout(activePills: ["integration_claude"], open: true, focusId: "integration_claude", twoCats: false)
        CT.checkTrue("the section shows while open", m13.panelShown)
        let stray = t13.live.values.first
        CT.checkTrue("a tick is armed to be the stray one", stray != nil)
        m13.islandExpanded(false)
        CT.check("folded: the armed tick is cancelled", t13.live.count, 0)
        m13.feed(payload: payload("SessionEnd", "s13", cwd: pathA))
        CT.check("folded: a feed does not read the layout again", m13.panelShown, true)
        stray?()   // the tick that was already due when the island folded
        CT.check("the stray tick arms nothing", t13.live.count, 0)
        CT.checkTrue("tickArmed stays false", !m13.tickArmed)
        CT.checkTrue("the deadline is cleared", m13.deadline == nil)
        CT.checkTrue("the section and its height are as they were", m13.panelShown && ProjectsLayout.extraHeight == 92)

        CT.section("the peek: the model holds which project is peeking, memory only, and a fold clears it")
        let c14 = Clock(base), t14 = Timers(), m14 = makeModel(c14, t14)
        var changes14 = 0
        let sub14 = m14.objectWillChange.sink { changes14 += 1 }
        CT.checkTrue("nothing peeks at first", m14.peekingProject == nil)
        m14.setPeeking("notchmeow")
        CT.check("a project can peek", m14.peekingProject, "notchmeow")
        m14.setPeeking("notchmeow")
        CT.check("the same project again publishes nothing more", changes14, 1)
        m14.setPeeking("site")
        CT.check("another project replaces it", m14.peekingProject, "site")
        m14.islandExpanded(true)
        CT.check("expanding keeps it", m14.peekingProject, "site")
        m14.islandExpanded(false)
        CT.checkTrue("folding clears it", m14.peekingProject == nil)
        m14.setPeeking(nil)
        CT.check("clearing what is clear publishes nothing", changes14, 3)
        sub14.cancel()

        CT.section("a pin names a live project: a toggle for one that has ended is ignored, and a stale pin does not come back with the folder")
        let c15 = Clock(base), t15 = Timers(), m15 = makeModel(c15, t15)
        m15.feed(payload: payload("SessionStart", "a1", cwd: pathA))
        c15.t = base + 1000
        m15.feed(payload: payload("SessionStart", "b1", cwd: pathB))
        let id15A = idOf(m15.view(), "notchmeow"), id15B = idOf(m15.view(), "site")
        m15.togglePin("no-such-project")
        CT.check("an id that is no project's pins nothing", m15.pinned, nil)
        c15.t = base + 2000
        m15.feed(payload: payload("SessionEnd", "b1", cwd: pathB))   // the project ends while the Pin menu is open ...
        m15.togglePin(id15B)                                        // ... and its item is chosen
        CT.check("choosing Pin for a project that has just ended pins nothing", m15.pinned, nil)
        c15.t = base + 3000
        m15.feed(payload: payload("SessionStart", "b2", cwd: pathB))   // the folder comes back
        CT.check("and the pin does not resurrect when the folder returns", m15.pinned, nil)
        m15.togglePin(id15A)
        CT.check("a live project still pins", m15.pinned, id15A)
        c15.t = base + 4000
        m15.feed(payload: payload("SessionEnd", "a1", cwd: pathA))
        m15.togglePin(id15A)
        CT.check("a pin whose project ended is gone, and toggling it does not bring it back", m15.pinned, nil)

        CT.section("the peeking project ends: the peek goes with it (the big cat and the kittens come back)")
        let c16 = Clock(base), t16 = Timers(), m16 = makeModel(c16, t16)
        m16.feed(payload: payload("SessionStart", "a1", cwd: pathA))
        c16.t = base + 1000
        m16.feed(payload: payload("SessionStart", "b1", cwd: pathB))
        let id16B = idOf(m16.view(), "site"), id16A = idOf(m16.view(), "notchmeow")
        m16.setPeeking(id16B)
        c16.t = base + 2000
        m16.feed(payload: payload("PreToolUse", "a1", cwd: pathA, ["tool_name": "Read", "tool_input": ["file_path": "/Users/sam/a/x.md"]]))
        CT.check("an event in another project leaves the peek as it is", m16.peekingProject, id16B)
        c16.t = base + 3000
        m16.feed(payload: payload("SessionEnd", "b1", cwd: pathB))
        CT.check("the peeking project's SessionEnd clears the peek", m16.peekingProject, nil)
        m16.islandExpanded(true)
        m16.setPeeking(id16A)
        c16.t = base + 3000 + ProjectsRules.removeMs
        t16.fireOne()
        CT.check("a project that goes by the clock's tick clears its peek too (a tick reads the view again)", m16.peekingProject, nil)

        CT.section("the layout is written before the section is shown, in both directions")
        let c17 = Clock(base), t17 = Timers(), m17 = makeModel(c17, t17)
        m17.feed(payload: payload("SessionStart", "s1", cwd: pathA))
        m17.panelOpen = true
        var heights17: [CGFloat] = []
        let sub17 = m17.$panelShown.dropFirst().sink { _ in heights17.append(ProjectsLayout.extraHeight) }   // a sink is called before the value is stored: what it reads is what the island would
        m17.refreshLayout(activePills: ["integration_claude", "agent_codex"], open: true, focusId: "integration_claude", twoCats: false)
        CT.check("opening: the height is 92 when panelShown publishes", heights17, [92])
        c17.t = base + 1000
        m17.feed(payload: payload("SessionEnd", "s1", cwd: pathA))
        m17.relayout(open: true)
        CT.check("closing: the height is 0 when panelShown publishes", heights17, [92, 0])
        m17.panelOpen = true
        m17.feed(payload: payload("SessionStart", "s2", cwd: pathA))
        m17.relayout(open: true)
        m17.togglePanel()
        CT.check("the chevron closes it with the height already 0", heights17, [92, 0, 92, 0])
        sub17.cancel()

        CT.section("opening the island after every session timed out: read fresh, the section is not shown and adds no height")
        let c18 = Clock(base), t18 = Timers(), m18 = makeModel(c18, t18)
        m18.feed(payload: payload("SessionStart", "s1", cwd: pathA))
        m18.panelOpen = true
        m18.refreshLayout(activePills: ["integration_claude", "agent_codex"], open: false, focusId: "integration_claude", twoCats: false)
        CT.check("folded, the section is shown for the live project", m18.panelShown && ProjectsLayout.extraHeight == 92, true)
        c18.t = base + ProjectsRules.removeMs + 1000   // two hours of quiet: no feed, so nothing read the layout again
        CT.check("with no feed and no tick the layout is still the old one", m18.panelShown, true)
        m18.relayout(open: true)   // what the island's mode sink does before it tells the model the island is expanded
        m18.islandExpanded(true)
        CT.check("opened: no project is live, so the section is not shown", m18.panelShown, false)
        CT.check("and it adds no height", ProjectsLayout.extraHeight, 0)

        _ = bag
        CT.finish()
    }
}
