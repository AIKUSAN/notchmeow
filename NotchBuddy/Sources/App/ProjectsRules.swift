import Foundation

// The Projects rules (sub-project P-mac): which project and role a Claude Code session has, the names and steps the notch shows, the order inside a
// project, the layout switch and a project's cat. A port of shared/projects-core.js (the specification; docs/PROJECTS-CONTRACT.md), replayed against
// tests/fixtures/projects/ by scripts/test-projects-rules.sh. Pure Foundation: no clock, no files, no network, no randomness (the cat's random number is
// a seeded generator of the same sequence as cat-core.js). It depends on no other app file: the FNV-1a and the generator are copies, pinned by the tests.
//
// Porting rules: a code point is a Unicode scalar (cut and count with unicodeScalars); text order is UTF-16 code-unit order; every sort is stable by its
// input index; a path is compared by its UTF-8 bytes, as JavaScript compares code units, not by Swift's canonical equivalence.
enum ProjectsRules {
    static let version = 1
    static let quietIdleMs = 600_000.0, dimMs = 1_800_000.0, removeMs = 7_200_000.0, finishedMs = 5_200.0
    static let appWaitMs = 600_000.0, cardApprovalMs = 120_000.0, cardQuestionMs = 130_000.0
    static let peekDwellMs = 400.0, agoTickMs = 60_000.0
    static let subagentsMax = 8, sessionsMax = 64, nameMax = 60, stepMax = 80, projectCatsMax = 256
    static let appWaitLabel = "Waiting in Claude App", homeName = "Home"
    static let states = ["approval", "question", "working", "finished", "idle"]
    /// The cats' IDs, in cat-core's order (frozen: stored in settings).
    static let catIds = ["shrimpy", "momo", "ginger", "midnight", "latte", "patches", "blue", "snow", "oreo", "mocha", "silver", "cloud", "leo", "button", "puff", "noodle"]
    /// Folder names that show as a product name (lower-case keys).
    static let aliases = ["notch-buddy": "Notch Buddy", "notchbuddy": "Notch Buddy", "notch_buddy": "Notch Buddy"]

    // MARK: - Character classes and text helpers

    /// The invisible and control characters the core strips (porting rule 5).
    static func isInvisible(_ u: Unicode.Scalar) -> Bool {
        switch u.value {
        case 0x00...0x1F, 0x7F...0x9F, 0xAD, 0x61C, 0x180E, 0x200B...0x200F, 0x202A...0x202E, 0x2028, 0x2029, 0x2060, 0x2066...0x2069,
             0xFEFF, 0xFFF9...0xFFFB, 0xE0000...0xE007F:
            return true
        default:
            return false
        }
    }

    /// JavaScript's whitespace, as `\s` and `trim()` read it (porting rule 6).
    static func isJSSpace(_ u: Unicode.Scalar) -> Bool {
        switch u.value {
        case 0x09...0x0D, 0x20, 0xA0, 0x1680, 0x2000...0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF:
            return true
        default:
            return false
        }
    }

    private static func scalarText<S: Sequence>(_ scalars: S) -> String where S.Element == Unicode.Scalar {
        String(String.UnicodeScalarView(scalars))
    }

    private static func withoutInvisible(_ s: String) -> String {
        scalarText(s.unicodeScalars.filter { !isInvisible($0) })
    }

    /// JavaScript's `trim()`: the whitespace at both ends out.
    static func jsTrim(_ s: String) -> String {
        let u = Array(s.unicodeScalars)
        var a = 0, b = u.count
        while a < b, isJSSpace(u[a]) { a += 1 }
        while b > a, isJSSpace(u[b - 1]) { b -= 1 }
        return scalarText(u[a..<b])
    }

    /// Text order as JavaScript's `<` and the default `sort()` compare it: by UTF-16 code unit.
    static func utf16Less(_ a: String, _ b: String) -> Bool {
        Array(a.utf16).lexicographicallyPrecedes(Array(b.utf16))
    }

    /// Byte-exact equality (porting rule: a path is compared as JavaScript compares it, not by canonical equivalence).
    private static func same(_ a: String, _ b: String) -> Bool {
        a.utf8.elementsEqual(b.utf8)
    }

    /// A text cut to `max` code points: kept whole when it fits, else `max - 1` code points and `…`.
    static func cutTo(_ s: String, _ max: Int) -> String {
        let cps = Array(s.unicodeScalars)
        guard cps.count > max else { return s }
        return scalarText(cps.prefix(Swift.max(0, max - 1))) + "…"
    }

    /// A display name: no invisible characters, at most `nameMax` code points. `""` unless the value is a String.
    static func cleanName(_ s: Any?) -> String {
        cutTo(withoutInvisible((s as? String) ?? ""), nameMax)
    }

    /// A host's name as display text: the invisible characters and the path separators out, the spaces at both ends out, at most `nameMax`.
    static func hostText(_ s: Any?) -> String {
        guard let t = s as? String else { return "" }
        let stripped = scalarText(t.unicodeScalars.filter { !isInvisible($0) && $0 != "/" && $0 != "\\" })
        return cutTo(jsTrim(stripped), nameMax)
    }

    /// FNV-1a 32 over the UTF-8 bytes, as 8 lower-case hex digits (the same function as SK.fnv1a and projects-core.js).
    static func fnv1a(_ s: String) -> String {
        var h: UInt32 = 0x811c9dc5
        for b in s.utf8 {
            h ^= UInt32(b)
            h = h &* 0x01000193
        }
        let hex = String(h, radix: 16)
        return String(repeating: "0", count: 8 - hex.count) + hex
    }

    /// cat-core.js line 31, copied: the seeded generator (`s = s * 1103515245 + 12345`, then `s / 2^32`).
    static func lcg(seed: UInt32) -> () -> Double {
        var s = seed
        return {
            s = s &* 1_103_515_245 &+ 12345
            return Double(s) / 4_294_967_296
        }
    }

    /// A project's name from its folder part, its parent part (` — parent`) and its number (` · k`). The folder part is cut first, so the parent part
    /// and the number survive; when those alone are too long, the parent part is cut and the number kept.
    private static func fitName(_ head: String, _ tail: String, _ num: String) -> String {
        let whole = head + tail + num
        if whole.unicodeScalars.count <= nameMax { return whole }
        let room = nameMax - (tail + num).unicodeScalars.count
        if room >= 1 { return cutTo(head, room) + tail + num }
        return cutTo(tail, nameMax - num.unicodeScalars.count) + num
    }

    /// The byte offsets where `needle` starts in `hay`, compared byte for byte.
    private static func offsets(of needle: String, in hay: String) -> [Int] {
        let h = Array(hay.utf8), n = Array(needle.utf8)
        guard n.count <= h.count else { return [] }
        var out: [Int] = []
        for i in 0...(h.count - n.count) where h[i..<(i + n.count)].elementsEqual(n) {
            out.append(i)
        }
        return out
    }

    // MARK: - Paths

    /// A path as one text: `/` separators, no doubled or trailing `/` (the root `/` stays), an upper-case drive letter. `""` when it is not a non-empty text.
    static func normPath(_ cwd: Any?) -> String {
        guard let raw = cwd as? String, !raw.isEmpty else { return "" }
        var out: [Unicode.Scalar] = []
        for u in raw.unicodeScalars {
            let c: Unicode.Scalar = u == "\\" ? "/" : u
            if c == "/", out.last == "/" { continue }
            out.append(c)
        }
        if out.count > 1, out.last == "/" { out.removeLast() }
        if out.count >= 2, out[0].value >= 0x61, out[0].value <= 0x7A, out[1] == ":", out.count == 2 || out[2] == "/" {
            out[0] = Unicode.Scalar(out[0].value - 0x20) ?? out[0]
        }
        return scalarText(out)
    }

    /// Whether a normalized path is a drive's root (`C:`).
    private static func isDriveRoot(_ r: String) -> Bool {
        let u = Array(r.unicodeScalars)
        return u.count == 2 && u[0].value >= 0x41 && u[0].value <= 0x5A && u[1] == ":"
    }

    struct Place: Equatable, Sendable {
        var root: String
        var worktree: String
    }

    static let worktreesMarker = "/.claude/worktrees/"

    /// Which project a session's folder belongs to: its root and worktree (`""` for a repository's own folder), or nil. A worktree belongs to the
    /// repository before its path; its name is the segment after the last marker. The home folder is never a root that another session joins.
    static func projectOf(_ cwd: Any?, roots: [Any], home: Any?) -> Place? {
        let n = normPath(cwd)
        if n.isEmpty { return nil }
        let h = normPath(home)
        let marks = offsets(of: worktreesMarker, in: n)
        if let first = marks.first, let last = marks.last {
            let bytes = Array(n.utf8)
            let root = String(decoding: bytes[0..<first], as: UTF8.self)
            let segment = bytes[(last + worktreesMarker.utf8.count)...].prefix { $0 != UInt8(ascii: "/") }
            return Place(root: root.isEmpty ? "/" : root, worktree: cleanName(String(decoding: segment, as: UTF8.self)))
        }
        if !h.isEmpty, same(n, h) { return Place(root: h, worktree: "") }
        var best = ""
        for item in roots {
            guard let r0 = item as? String else { continue }
            let r = normPath(r0)
            if r.isEmpty || (!h.isEmpty && same(r, h)) { continue }
            let bare = r == "/" || isDriveRoot(r)
            let inside = same(n, r) || (!bare && n.utf8.starts(with: (r + "/").utf8))
            if inside && r.utf8.count > best.utf8.count { best = r }
        }
        return Place(root: best.isEmpty ? n : best, worktree: "")
    }

    struct Named: Equatable, Sendable {
        var root: String
        var name: String
        var catKey: String
    }

    /// The name of each project root, in input order. The root folder is `Session`; the home folder is `homeName` and never shares a name. Two roots
    /// with one folder name show their parent folder; two with the same label get a number, and every name given so far is taken.
    static func projectNames(_ roots: [Any], home: Any?) -> [Named] {
        let h = normPath(home)
        let list = roots.compactMap { $0 as? String }.map(normPath).filter { !$0.isEmpty }
        struct Info {
            var root: String
            var isHome: Bool
            var catKey: String
            var parent: String
        }
        let info: [Info] = list.map { r in
            let segs = r.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
            let base = cleanName(segs.last ?? "")
            let isHome = same(r, h)
            let catKey = isHome ? homeName : base.isEmpty ? "Session" : (aliases[base.lowercased()] ?? base)
            let parent = segs.count >= 2 ? cleanName(segs[segs.count - 2]) : ""
            return Info(root: r, isHome: isHome, catKey: catKey, parent: parent)
        }
        var count: [String: Int] = [:]
        for i in info { count[i.catKey, default: 0] += 1 }
        let tails: [String] = info.map { i in
            (!i.isHome && count[i.catKey, default: 0] >= 2 && !i.parent.isEmpty) ? " — \(i.parent)" : ""
        }
        let plain: [String] = info.indices.map { fitName(info[$0].catKey, tails[$0], "") }
        var taken: Set<String> = info.contains { $0.isHome } ? [homeName] : []
        var used: [String: Int] = [:]
        var out: [Named] = []
        for (j, i) in info.enumerated() {
            if i.isHome {
                out.append(Named(root: i.root, name: homeName, catKey: i.catKey))
                continue
            }
            var k = (used[plain[j]] ?? 0) + 1
            var name = k == 1 ? plain[j] : fitName(i.catKey, tails[j], " · \(k)")
            while taken.contains(name) {
                k += 1
                name = fitName(i.catKey, tails[j], " · \(k)")
            }
            taken.insert(name)
            used[plain[j]] = k
            out.append(Named(root: i.root, name: name, catKey: i.catKey))
        }
        return out
    }

    // MARK: - Roles and order inside a project

    /// `worktree` is `Any?` (a JSON value, as the hook gives it), so the conformance is unchecked: it is only read as a value, never shared.
    struct RoleIn: @unchecked Sendable {
        var id: String
        var worktree: Any?
        var seq: Double
    }

    struct Role: Equatable, Sendable {
        var id: String
        var role: String
        var label: String
    }

    /// Each session's role and label, in input order: a session in no worktree is `main`, one in a worktree is `side` (labelled by the worktree's
    /// name). The mains are numbered in start order (`main`, `main · 2`, …), and so are the sides of one worktree.
    static func rolesOf(_ sessions: [RoleIn]) -> [Role] {
        let byStart = sessions.indices.sorted { a, b in
            let x = numOr0(sessions[a].seq), y = numOr0(sessions[b].seq)
            return x != y ? x < y : a < b
        }
        var roles = [String](repeating: "", count: sessions.count)
        var labels = roles
        var mains = 0
        var sideCount: [String: Int] = [:]
        for i in byStart {
            // A worktree that is not text (undefined, null) is no worktree, as the empty text is.
            let name = cleanName(sessions[i].worktree)
            if name.isEmpty {
                mains += 1
                roles[i] = "main"
                labels[i] = mains == 1 ? "main" : "main · \(mains)"
            } else {
                let k = (sideCount[name] ?? 0) + 1
                sideCount[name] = k
                roles[i] = "side"
                labels[i] = k == 1 ? name : "\(name) · \(k)"
            }
        }
        return sessions.indices.map { Role(id: sessions[$0].id, role: roles[$0], label: labels[$0]) }
    }

    struct OrderRow: Sendable {
        var id: String
        var role: String
        var seq: Double
        var lastAt: Double
    }

    /// The order sessions show in: the mains first, by start; then the sides, most recent activity first; a tie is broken by id, then by input order.
    static func sessionOrder(_ rows: [OrderRow]) -> [String] {
        let mains = rows.indices.filter { rows[$0].role == "main" }.sorted { a, b in
            let x = numOr0(rows[a].seq), y = numOr0(rows[b].seq)
            if x != y { return x < y }
            if !same(rows[a].id, rows[b].id) { return utf16Less(rows[a].id, rows[b].id) }
            return a < b
        }
        let sides = rows.indices.filter { rows[$0].role != "main" }.sorted { a, b in
            let x = numOr0(rows[a].lastAt), y = numOr0(rows[b].lastAt)
            if x != y { return x > y }
            if !same(rows[a].id, rows[b].id) { return utf16Less(rows[a].id, rows[b].id) }
            return a < b
        }
        return (mains + sides).map { rows[$0].id }
    }

    /// The view's id of a project: `p-` plus the FNV-1a of its root. Never shown, never stored.
    static func projectId(root: String) -> String {
        "p-" + fnv1a(root)
    }

    // MARK: - Steps, labels and states

    /// A step as the notch shows it: invisible characters become spaces, a word that holds a path keeps its last part (`…` when it has none), words are
    /// joined by one space, at most `stepMax` code points. `""` when not text.
    static func cleanStep(_ text: Any?) -> String {
        guard let t = text as? String else { return "" }
        var words: [String] = []
        var word: [Unicode.Scalar] = []
        for u in t.unicodeScalars {
            if isInvisible(u) || isJSSpace(u) {
                if !word.isEmpty { words.append(pathPart(word)); word = [] }
            } else {
                word.append(u)
            }
        }
        if !word.isEmpty { words.append(pathPart(word)) }
        return cutTo(words.joined(separator: " "), stepMax)
    }

    /// A word as a step shows it: a word with a `/` or `\` keeps its last non-empty part, `…` when it has none.
    private static func pathPart(_ word: [Unicode.Scalar]) -> String {
        func isSep(_ u: Unicode.Scalar) -> Bool { u == "/" || u == "\\" }
        guard word.contains(where: isSep) else { return scalarText(word) }
        guard let last = word.split(whereSeparator: isSep).last else { return "…" }
        return scalarText(last)
    }

    /// The label of a session that waits in an app: `Waiting in <host>`, or `appWaitLabel` when no host is given.
    static func waitLabel(_ host: Any?) -> String {
        let h = hostText(host)
        return h.isEmpty ? appWaitLabel : "Waiting in \(h)"
    }

    /// Whole minutes since `lastAt`, never below 0. A time too far off to count still returns a number (it never traps).
    static func agoOf(now: Double, lastAt: Double) -> Int {
        let m = max(0, ((numOr0(now) - numOr0(lastAt)) / agoTickMs).rounded(.down))
        return Int(min(m, 9_007_199_254_740_992))
    }

    /// The most urgent of some states: approval, question, working, finished, idle. Unknown words count for nothing; no state is idle.
    static func projectStateOf(_ states: [String]) -> String {
        self.states.first { states.contains($0) } ?? "idle"
    }

    /// A number as the rules read it: a finite number, else 0.
    private static func numOr0(_ x: Double) -> Double {
        x.isFinite ? x : 0
    }

    // MARK: - Claude only and the layout switch

    /// The shape of a pill ID: a lower-case letter, then 1 to 63 of lower-case letters, digits, `_` and `-`.
    private static func isPillId(_ s: String) -> Bool {
        func isLower(_ u: Unicode.Scalar) -> Bool { u.value >= 0x61 && u.value <= 0x7A }
        func isDigit(_ u: Unicode.Scalar) -> Bool { u.value >= 0x30 && u.value <= 0x39 }
        let u = Array(s.unicodeScalars)
        guard (2...64).contains(u.count), isLower(u[0]) else { return false }
        return u.dropFirst().allSatisfy { isLower($0) || isDigit($0) || $0 == "_" || $0 == "-" }
    }

    /// An agent pill other than Claude Code's own two (`integration_claude` and `agent_claude-desktop`).
    private static func isOtherAgentPill(_ v: Any) -> Bool {
        guard let s = v as? String, isPillId(s) else { return false }
        return s.hasPrefix("agent_") && s.utf8.count > 6 && s != "agent_claude-desktop"
    }

    /// Claude only: no other agent's pill is declared and no other agent has sent an event.
    static func claudeOnly(activePills: [Any], otherAgentSeen: Bool) -> Bool {
        if otherAgentSeen { return false }
        return !activePills.contains { isOtherAgentPill($0) }
    }

    enum Layout: String, Sendable {
        case projects, agents
    }

    /// The island's layout: while it is open it keeps the layout it has; folded, it shows the projects when Claude only, else the agents.
    static func islandLayout(current: Layout?, claudeOnly: Bool, open: Bool) -> Layout {
        if open, let c = current { return c }
        return claudeOnly ? .projects : .agents
    }

    // MARK: - Project cats

    private static let protoKeys: Set<String> = ["__proto__", "constructor", "prototype"]

    /// A key that can name a project's cat: 1 to `nameMax` code points, no path separator, no invisible character, no prototype name.
    static func isCatKey(_ k: String) -> Bool {
        let u = k.unicodeScalars
        return !k.isEmpty && u.count <= nameMax
            && !u.contains { $0 == "/" || $0 == "\\" || isInvisible($0) }
            && !protoKeys.contains(k)
    }

    /// The stored project cats, cleaned: `[catKey: catId]`, at most `projectCatsMax`, the first in UTF-16 order; `[:]` unless a plain object.
    static func cleanProjectCats(_ raw: Any?) -> [String: String] {
        guard let dict = raw as? [String: Any] else { return [:] }
        let valid = dict.keys.filter { isCatKey($0) && catIds.contains(dict[$0] as? String ?? "") }
        var out: [String: String] = [:]
        for k in valid.sorted(by: utf16Less).prefix(projectCatsMax) {
            if let v = dict[k] as? String { out[k] = v }
        }
        return out
    }

    /// The keys of a cat map in UTF-16 order (the order the core writes them).
    static func sortedCatKeys(_ cats: [String: String]) -> [String] {
        cats.keys.sorted(by: utf16Less)
    }

    /// The cat a project shows: its stored coat, else the one picked from its name as cat-core.js picks one with the Main cat taken. Stores nothing.
    static func projectCatOf(_ catKey: Any?, projectCats: Any?, mainCat: Any?) -> (cat: String, stored: Bool) {
        let main = (mainCat as? String).flatMap { catIds.contains($0) ? $0 : nil } ?? "shrimpy"
        guard let key = catKey as? String, isCatKey(key) else { return (main, false) }
        if let c = cleanProjectCats(projectCats)[key] { return (c, true) }
        let free = catIds.filter { $0 != main }
        let r = lcg(seed: UInt32(fnv1a(key), radix: 16) ?? 0)()
        let i = min(free.count - 1, max(0, Int(floor(r * Double(free.count)))))
        return (free[i], false)
    }
}
