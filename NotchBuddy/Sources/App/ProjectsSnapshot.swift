import Foundation

// The Projects view (sub-project P-mac): what the notch shows at a time, built from the registry. A port of shared/projects-core.js's view, order, big
// card and waiting count, replayed against tests/fixtures/projects/ by scripts/test-projects-registry.sh. Pure Foundation. A row carries a step, a host
// and a label, never a path: a project's name and a session's label hold no `/` or `\`.

struct PJSubagentRow: Equatable, Sendable {
    var id: String
    var type: String
    var state: String

    var json: [String: Any] {
        ["id": id, "type": type, "state": state]
    }
}

struct PJSessionRow: Equatable, Sendable {
    var id: String
    var role: String
    var label: String
    var state: String
    var dim: Bool
    var waitingInApp: Bool
    var note: String
    var step: String
    var host: String
    var lastAt: Double
    var agoMin: Int
    var subagents: [PJSubagentRow]

    var json: [String: Any] {
        [
            "id": id, "role": role, "label": label, "state": state, "dim": dim, "waitingInApp": waitingInApp,
            "note": note, "step": step, "host": host, "lastAt": lastAt, "agoMin": agoMin,
            "subagents": subagents.map { $0.json },
        ]
    }
}

struct PJProject: Equatable, Sendable {
    var id: String
    var name: String
    var catKey: String
    var cat: String
    var state: String
    var dim: Bool
    var waiting: Int
    var sessionCount: Int
    var lastAt: Double
    var agoMin: Int
    var step: String
    var host: String
    var sessions: [PJSessionRow]

    var json: [String: Any] {
        [
            "id": id, "name": name, "catKey": catKey, "cat": cat, "state": state, "dim": dim, "waiting": waiting,
            "sessionCount": sessionCount, "lastAt": lastAt, "agoMin": agoMin, "step": step, "host": host,
            "sessions": sessions.map { $0.json },
        ]
    }
}

struct PJView: Equatable, Sendable {
    var projects: [PJProject]
    var waiting: Int
    var sessionCount: Int
    var otherAgentSeen: Bool

    var json: [String: Any] {
        [
            "projects": projects.map { $0.json }, "waiting": waiting,
            "sessionCount": sessionCount, "otherAgentSeen": otherAgentSeen,
        ]
    }
}

/// A project as the order and the big card read it: its id, its most urgent state and its newest activity.
struct PJOrderKey: Equatable, Sendable {
    var id: String
    var state: String
    var lastAt: Double
}

struct PJBigCard: Equatable, Sendable {
    var project: String?
    var pinned: String?
    var clicked: String?

    var json: [String: Any] {
        ["project": ProjectsRegistry.orNull(project), "pinned": ProjectsRegistry.orNull(pinned), "clicked": ProjectsRegistry.orNull(clicked)]
    }
}

enum ProjectsSnapshot {
    /// The notch's view at `now`: the live projects in pill order, the sessions waiting, the live session count and whether another agent was seen.
    /// The registry is not changed. `steps` maps a session id to its step text; a row's note is its newest in-app wait's label.
    static func view(_ r: PJRegistry, now: Double?, steps: [String: String] = [:], projectCats: [String: String] = [:], mainCat: String? = nil) -> PJView {
        let t = ProjectsRegistry.timeOf(now, r.sessions)
        let live = r.sessions.filter { !$0.root.isEmpty && !ProjectsRegistry.sessionStateAt($0, now: t).gone }
        let bySeq = live.indices.sorted { a, b in
            live[a].seq != live[b].seq ? live[a].seq < live[b].seq : a < b
        }.map { live[$0] }
        var roots: [String] = []
        for s in bySeq where !roots.contains(where: { ProjectsRegistry.same($0, s.root) }) {
            roots.append(s.root)
        }
        let named = ProjectsRules.projectNames(roots, home: r.home)
        var projects: [PJProject] = []
        for (j, root) in roots.enumerated() where j < named.count {
            let group = bySeq.filter { ProjectsRegistry.same($0.root, root) }
            let roles = ProjectsRules.rolesOf(group.map { ProjectsRules.RoleIn(id: $0.id, worktree: $0.worktree, seq: Double($0.seq)) })
            let order = ProjectsRules.sessionOrder(group.indices.map {
                ProjectsRules.OrderRow(id: group[$0].id, role: roles[$0].role, seq: Double(group[$0].seq), lastAt: group[$0].lastAt)
            })
            var indexOf: [[UInt8]: Int] = [:]
            for i in group.indices { indexOf[Array(group[i].id.utf8)] = i }
            let picked = order.compactMap { indexOf[Array($0.utf8)] }
            let items = picked.map { i in (row: rowOf(group[i], role: roles[i], t: t, steps: steps), seq: group[i].seq) }
            guard var newest = items.first else { continue }
            for item in items.dropFirst()
            where item.row.lastAt > newest.row.lastAt || (item.row.lastAt == newest.row.lastAt && item.seq > newest.seq) {
                newest = item
            }
            let rows = items.map { $0.row }
            let lastAt = rows.map { $0.lastAt }.max() ?? 0
            let nm = named[j]
            projects.append(PJProject(
                id: ProjectsRules.projectId(root: root), name: nm.name, catKey: nm.catKey,
                cat: ProjectsRules.projectCatOf(nm.catKey, projectCats: projectCats, mainCat: mainCat).cat,
                state: ProjectsRules.projectStateOf(rows.map { $0.state }), dim: rows.allSatisfy { $0.dim },
                waiting: rows.filter { $0.state == "approval" || $0.state == "question" }.count, sessionCount: rows.count,
                lastAt: lastAt, agoMin: ProjectsRules.agoOf(now: t, lastAt: lastAt), step: newest.row.step, host: newest.row.host, sessions: rows))
        }
        let ordered = orderIndices(projects.map { PJOrderKey(id: $0.id, state: $0.state, lastAt: $0.lastAt) }).map { projects[$0] }
        return PJView(projects: ordered, waiting: waitingCount(ordered.map { $0.waiting }), sessionCount: live.count,
                      otherAgentSeen: r.otherAgentSeen)
    }

    /// One session's row at `t`.
    private static func rowOf(_ s: PJSession, role: ProjectsRules.Role, t: Double, steps: [String: String]) -> PJSessionRow {
        let st = ProjectsRegistry.sessionStateAt(s, now: t)
        let lastAt = ProjectsRegistry.finite0(s.lastAt)
        let appWaits = s.pending.filter { ProjectsRegistry.liveAsk($0, now: t) && $0.inApp }
        return PJSessionRow(
            id: s.id, role: role.role, label: role.label, state: st.state, dim: st.dim, waitingInApp: st.waitingInApp,
            note: st.waitingInApp ? ProjectsRules.waitLabel(appWaits.last?.waitIn) : "",
            step: ProjectsRules.cleanStep(steps[s.id] ?? ""), host: hostOf(s), lastAt: lastAt,
            agoMin: ProjectsRules.agoOf(now: t, lastAt: lastAt), subagents: subagentRows(s, t: t))
    }

    /// The subagents a session shows at `t`: those active in the last 10 min, the ones asking first, then the newest born, then the later listed.
    private static func subagentRows(_ s: PJSession, t: Double) -> [PJSubagentRow] {
        let shown: [(index: Int, state: String)] = s.subagents.indices
            .filter { t - ProjectsRegistry.finite0(s.subagents[$0].last) < ProjectsRules.quietIdleMs }
            .map { i in
                let k = s.subagents[i]
                let asking = s.pending.contains { ProjectsRegistry.same($0.by, k.id) && ProjectsRegistry.liveAsk($0, now: t) }
                return (index: i, state: asking ? "approval" : "working")
            }
        return shown.sorted { a, b in
            let x = a.state == "approval" ? 0 : 1, y = b.state == "approval" ? 0 : 1
            if x != y { return x < y }
            let born = ProjectsRegistry.finite0(s.subagents[a.index].born), other = ProjectsRegistry.finite0(s.subagents[b.index].born)
            if born != other { return born > other }
            return a.index > b.index
        }.map { item in
            let k = s.subagents[item.index]
            return PJSubagentRow(id: k.id, type: ProjectsRegistry.subTypeText(k.type), state: item.state)
        }
    }

    /// Where a session's host is: the Claude App, VS Code (Cursor's bundle is not VS Code), or a terminal.
    static func hostOf(_ s: PJSession) -> String {
        if s.fromApp { return "claude-app" }
        let bundle = s.bundleId.lowercased()
        let text = s.termProgram.lowercased() + " " + bundle
        let vscode = !ProjectsRegistry.same(bundle, ProjectsRegistry.cursorBundle) && ProjectsRegistry.hasText(text, "vscode")
        return vscode ? "vscode" : "terminal"
    }

    /// The order of the projects' indices: a waiting project (approval or question) first, then the most recently active, then by id; a tie keeps the input order.
    static func orderIndices(_ keys: [PJOrderKey]) -> [Int] {
        func waits(_ state: String) -> Int { state == "approval" || state == "question" ? 0 : 1 }
        return keys.indices.sorted { a, b in
            let wa = waits(keys[a].state), wb = waits(keys[b].state)
            if wa != wb { return wa < wb }
            let la = ProjectsRegistry.finite0(keys[a].lastAt), lb = ProjectsRegistry.finite0(keys[b].lastAt)
            if la != lb { return la > lb }
            if !ProjectsRegistry.same(keys[a].id, keys[b].id) { return ProjectsRules.utf16Less(keys[a].id, keys[b].id) }
            return a < b
        }
    }

    /// The projects' ids in pill order (see `orderIndices`).
    static func projectOrder(_ keys: [PJOrderKey]) -> [String] {
        orderIndices(keys).map { keys[$0].id }
    }

    /// The project the big card shows: the pinned one, else the last clicked, each only while that project is still there; else the most recently
    /// active (the first, on a tie). An empty id is no project when a pin or a click is judged.
    static func bigCardOf(_ keys: [PJOrderKey], pinned: String?, clicked: String?) -> PJBigCard {
        func here(_ id: String?) -> String? {
            guard let id, keys.contains(where: { ProjectsRegistry.same($0.id, id) }) else { return nil }
            return id
        }
        func truthy(_ id: String?) -> String? {
            guard let id, !id.isEmpty else { return nil }
            return id
        }
        let pin = here(pinned), click = here(clicked)
        var best: PJOrderKey?
        for k in keys {
            if let b = best {
                if ProjectsRegistry.finite0(k.lastAt) > ProjectsRegistry.finite0(b.lastAt) { best = k }
            } else {
                best = k
            }
        }
        return PJBigCard(project: truthy(pin) ?? truthy(click) ?? best?.id, pinned: pin, clicked: click)
    }

    /// The sessions waiting over the projects: the sum of the counts that are 0 or more.
    static func waitingCount(_ counts: [Int]) -> Int {
        counts.filter { $0 >= 0 }.reduce(0, +)
    }

    /// A JSON value as a whole, non-negative count; 0 for anything else (text, a fraction, a negative, a boolean).
    static func wholeCount(_ v: Any?) -> Int {
        guard let d = ProjectsRegistry.numberOf(v), d >= 0, d == d.rounded(.towardZero) else { return 0 }
        return Int(min(d, 9_007_199_254_740_992))
    }
}
