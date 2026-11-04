import Foundation

// The Projects rules' Task 1 pins: the constants, paths, names, roles, order, ids, cats, steps and the layout switch, against
// tests/fixtures/projects/ (project-cases, cat-cases, claude-only-cases, step-cases), and the rules those fixtures cannot write down.
@main
enum ProjectsRulesTests {
    typealias P = ProjectsRules

    /// A JSON boolean (a CFBoolean), never a number 0 or 1.
    static func isBool(_ x: Any?) -> Bool {
        guard let n = x as? NSNumber else { return false }
        return CFGetTypeID(n) == CFBooleanGetTypeID()
    }

    static func bool(_ x: Any?) -> Bool {
        isBool(x) ? (x as! NSNumber).boolValue : false
    }

    /// One Bool row: the expected value must be a JSON boolean and equal.
    static func boolRow(_ name: String, _ got: Bool, _ want: Any?) -> [String] {
        isBool(want) && bool(want) == got ? [] : ["\(name): got \(got), expected \(String(describing: want))"]
    }

    static func number(_ x: Any?) -> Double {
        (x as? NSNumber)?.doubleValue ?? 0
    }

    @MainActor
    static func main() {
        CT.section("constants")
        CT.check("version", P.version, 1)
        CT.check("quietIdleMs", P.quietIdleMs, 600_000)
        CT.check("dimMs", P.dimMs, 1_800_000)
        CT.check("removeMs", P.removeMs, 7_200_000)
        CT.check("finishedMs", P.finishedMs, 5_200)
        CT.check("appWaitMs", P.appWaitMs, 600_000)
        CT.check("cardApprovalMs", P.cardApprovalMs, 120_000)
        CT.check("cardQuestionMs", P.cardQuestionMs, 130_000)
        CT.check("peekDwellMs", P.peekDwellMs, 400)
        CT.check("agoTickMs", P.agoTickMs, 60_000)
        CT.check("subagentsMax", P.subagentsMax, 8)
        CT.check("sessionsMax", P.sessionsMax, 64)
        CT.check("nameMax", P.nameMax, 60)
        CT.check("stepMax", P.stepMax, 80)
        CT.check("projectCatsMax", P.projectCatsMax, 256)
        CT.check("appWaitLabel", P.appWaitLabel, "Waiting in Claude App")
        CT.check("homeName", P.homeName, "Home")
        CT.check("states", P.states, ["approval", "question", "working", "finished", "idle"])
        CT.check("catIds is CatPresets.ids, in cat-core's order", P.catIds, CatPresets.ids)
        CT.check("aliases", P.aliases, ["notch-buddy": "Notch Buddy", "notchbuddy": "Notch Buddy", "notch_buddy": "Notch Buddy"])
        CT.check("fnv1a of the empty text", P.fnv1a(""), "811c9dc5")
        CT.check("fnv1a of a", P.fnv1a("a"), "e40c292c")
        for s in ["", "a", "notchmeow", "/Users/sam/Code/notchmeow", "é🐱"] {
            CT.check("fnv1a(\(s)) is SK.fnv1a", P.fnv1a(s), SK.fnv1a(s))
        }
        let mine = P.lcg(seed: 42), theirs = CatRNG(seed: 42)
        var a: [Double] = [], b: [Double] = []
        for _ in 0..<5 { a.append(mine()); b.append(theirs.next()) }
        CT.check("lcg(seed: 42) gives CatRNG's first 5 numbers", a, b)

        CT.section("project-cases.json: projectOf, names, roles, order, ids")
        let pc = CT.fixture("project-cases.json", dir: "projects")
        let projectOfRows = PJFixtureRows.group("project-cases.json", pc, "projectOf", expect: 25)
        let namesRows = PJFixtureRows.group("project-cases.json", pc, "names", expect: 19)
        let rolesRows = PJFixtureRows.group("project-cases.json", pc, "roles", expect: 4)
        let orderRows = PJFixtureRows.group("project-cases.json", pc, "order", expect: 2)
        let idsRows = PJFixtureRows.group("project-cases.json", pc, "ids", expect: 2)
        var diffs: [String] = []
        for r in projectOfRows {
            let roots = r["roots"] as? [Any] ?? []
            let got = P.projectOf(r["cwd"], roots: roots, home: r["home"])
            let gotJSON: Any = got.map { ["root": $0.root, "worktree": $0.worktree] as [String: Any] } ?? NSNull()
            diffs += CT.diffs(gotJSON, r["expect"] ?? NSNull()).map { "\(r["name"] ?? ""): \($0)" }
        }
        CT.checkRows("projectOf (\(projectOfRows.count) rows)", diffs)

        diffs = []
        for r in namesRows {
            let roots = r["roots"] as? [Any] ?? []
            let got: [Any] = P.projectNames(roots, home: r["home"]).map { ["root": $0.root, "name": $0.name, "catKey": $0.catKey] as [String: Any] }
            diffs += CT.diffs(got, r["expect"] ?? NSNull()).map { "\(r["name"] ?? ""): \($0)" }
        }
        CT.checkRows("projectNames (\(namesRows.count) rows)", diffs)

        diffs = []
        for r in rolesRows {
            let sessions = (r["sessions"] as? [[String: Any]] ?? []).map {
                P.RoleIn(id: $0["id"] as? String ?? "", worktree: $0["worktree"], seq: number($0["seq"]))
            }
            let got: [Any] = P.rolesOf(sessions).map { ["id": $0.id, "role": $0.role, "label": $0.label] as [String: Any] }
            diffs += CT.diffs(got, r["expect"] ?? NSNull()).map { "\(r["name"] ?? ""): \($0)" }
        }
        CT.checkRows("rolesOf (\(rolesRows.count) rows)", diffs)

        diffs = []
        for r in orderRows {
            let input = (r["rows"] as? [[String: Any]] ?? []).map {
                P.OrderRow(id: $0["id"] as? String ?? "", role: $0["role"] as? String ?? "", seq: number($0["seq"]), lastAt: number($0["lastAt"]))
            }
            let got: [Any] = P.sessionOrder(input)
            diffs += CT.diffs(got, r["expect"] ?? NSNull()).map { "\(r["name"] ?? ""): \($0)" }
        }
        CT.checkRows("sessionOrder (\(orderRows.count) rows)", diffs)

        diffs = []
        for r in idsRows {
            diffs += CT.diffs(P.projectId(root: r["root"] as? String ?? ""), r["expect"] ?? NSNull()).map { "\(r["name"] ?? ""): \($0)" }
        }
        CT.checkRows("projectId (\(idsRows.count) rows)", diffs)

        CT.section("cat-cases.json: projectCatOf, cleanProjectCats")
        let cc = CT.fixture("cat-cases.json", dir: "projects")
        let catRows = PJFixtureRows.group("cat-cases.json", cc, "cat", expect: 11)
        let cleanRows = PJFixtureRows.group("cat-cases.json", cc, "clean", expect: 9)
        diffs = []
        for r in catRows {
            let got = P.projectCatOf(r["catKey"], projectCats: r["projectCats"], mainCat: r["mainCat"])
            let json: [String: Any] = ["cat": got.cat, "stored": got.stored]
            diffs += CT.diffs(json, r["expect"] ?? NSNull()).map { "\(r["name"] ?? ""): \($0)" }
        }
        CT.checkRows("projectCatOf (\(catRows.count) rows)", diffs)

        diffs = []
        for r in cleanRows {
            let got: [String: Any] = P.cleanProjectCats(r["raw"])
            let want = r["expect"] as? [String: Any] ?? [:]
            diffs += CT.diffs(got, want).map { "\(r["name"] ?? ""): \($0)" }
            // The key order the core writes: the expected keys in UTF-16 order.
            if P.sortedCatKeys(P.cleanProjectCats(r["raw"])) != want.keys.sorted(by: P.utf16Less) {
                diffs.append("\(r["name"] ?? ""): key order differs")
            }
        }
        CT.checkRows("cleanProjectCats (\(cleanRows.count) rows)", diffs)

        CT.section("claude-only-cases.json: claudeOnly, islandLayout")
        let co = CT.fixture("claude-only-cases.json", dir: "projects")
        let claudeOnlyRows = PJFixtureRows.group("claude-only-cases.json", co, "claudeOnly", expect: 7)
        let layoutRows = PJFixtureRows.group("claude-only-cases.json", co, "layout", expect: 5)
        diffs = []
        for r in claudeOnlyRows {
            let pills = r["activePills"] as? [Any] ?? []
            let got = P.claudeOnly(activePills: pills, otherAgentSeen: bool(r["otherAgentSeen"]))
            diffs += boolRow("\(r["name"] ?? "")", got, r["expect"])
        }
        CT.checkRows("claudeOnly (\(claudeOnlyRows.count) rows)", diffs)

        diffs = []
        for r in layoutRows {
            let current = (r["current"] as? String).flatMap { P.Layout(rawValue: $0) }
            let got = P.islandLayout(current: current, claudeOnly: bool(r["claudeOnly"]), open: bool(r["open"]))
            diffs += CT.diffs(got.rawValue, r["expect"] ?? NSNull()).map { "\(r["name"] ?? ""): \($0)" }
        }
        CT.checkRows("islandLayout (\(layoutRows.count) rows)", diffs)

        CT.section("step-cases.json: cleanStep")
        let sc = CT.fixture("step-cases.json", dir: "projects")
        let stepsRows = PJFixtureRows.group("step-cases.json", sc, "steps", expect: 13)
        diffs = []
        for r in stepsRows {
            diffs += CT.diffs(P.cleanStep(r["text"]), r["expect"] ?? NSNull()).map { "\(r["name"] ?? ""): \($0)" }
        }
        CT.checkRows("cleanStep (\(stepsRows.count) rows)", diffs)

        CT.section("what the fixtures cannot write")
        // Porting rule 5: the invisible set, and rule 6: JavaScript whitespace.
        let invisibleCodes: [UInt32] = [0x0, 0x1F, 0x7F, 0x9F, 0xAD, 0x61C, 0x180E, 0x200B, 0x200F, 0x202A, 0x202E, 0x2028, 0x2029, 0x2060, 0x2066, 0x2069, 0xFEFF, 0xFFF9, 0xFFFB, 0xE0000, 0xE007F]
        for u in invisibleCodes {
            CT.checkTrue("U+\(String(u, radix: 16, uppercase: true)) is invisible", P.isInvisible(Unicode.Scalar(u)!))
        }
        let visibleCodes: [UInt32] = [0x20, 0x7E, 0xA0, 0x180F, 0x200A, 0x2027, 0x202F, 0x1F431, 0xE0080]
        for u in visibleCodes {
            CT.checkTrue("U+\(String(u, radix: 16, uppercase: true)) is not invisible", !P.isInvisible(Unicode.Scalar(u)!))
        }
        let spaceCodes: [UInt32] = [0x09, 0x0D, 0x20, 0xA0, 0x1680, 0x2000, 0x200A, 0x2028, 0x2029, 0x202F, 0x205F, 0x3000, 0xFEFF]
        for u in spaceCodes {
            CT.checkTrue("U+\(String(u, radix: 16, uppercase: true)) is JavaScript space", P.isJSSpace(Unicode.Scalar(u)!))
        }
        let notSpaceCodes: [UInt32] = [0x0E, 0x200B, 0x180E, 0x61C, 0x41]
        for u in notSpaceCodes {
            CT.checkTrue("U+\(String(u, radix: 16, uppercase: true)) is not JavaScript space", !P.isJSSpace(Unicode.Scalar(u)!))
        }
        CT.check("jsTrim takes NBSP and ideographic space", P.jsTrim("\u{00A0} a \u{3000}"), "a")
        // Porting rule 1: a code point is a Unicode scalar, the cat is one.
        CT.check("cutTo counts the cat as one code point", P.cutTo("ab🐱c", 3), "ab…")
        CT.check("cutTo keeps a text that fits whole", P.cutTo("ab🐱c", 4), "ab🐱c")
        CT.check("cleanName of a number is empty", P.cleanName(42), "")
        CT.check("cleanName removes a bidi override", P.cleanName("a\u{202E}b"), "ab")
        // Porting rule 2: UTF-16 order, where the cat (a surrogate pair) sorts before U+FF5E.
        CT.checkTrue("utf16Less: the cat sorts before U+FF5E", P.utf16Less("🐱", "\u{FF5E}"))
        CT.checkTrue("utf16Less: a prefix sorts first", P.utf16Less("a", "ab"))
        CT.checkTrue("utf16Less: equal texts are not less", !P.utf16Less("ab", "ab"))
        CT.check("sortedCatKeys in UTF-16 order", P.sortedCatKeys(["b": "momo", "a": "momo", "🐱": "momo"]), ["a", "b", "🐱"])
        // hostText and waitLabel: no path separator, blank is no host.
        CT.check("hostText drops separators and spaces at both ends", P.hostText("  /a\\b  "), "ab")
        CT.check("hostText of nothing is empty", P.hostText(nil), "")
        CT.check("waitLabel with no host", P.waitLabel(nil), "Waiting in Claude App")
        CT.check("waitLabel of a blank host", P.waitLabel("   "), "Waiting in Claude App")
        CT.check("waitLabel of a host", P.waitLabel("VS Code"), "Waiting in VS Code")
        // agoOf: whole minutes, never below 0, and an absurd time never traps.
        CT.check("agoOf zero", P.agoOf(now: 0, lastAt: 0), 0)
        CT.check("agoOf 3 minutes and 59.999 s is 3", P.agoOf(now: 239_999, lastAt: 0), 3)
        CT.check("agoOf never below 0", P.agoOf(now: 0, lastAt: 1_000_000), 0)
        CT.check("agoOf of an absurd time does not trap", P.agoOf(now: 1e300, lastAt: 0) > 0, true)
        // projectStateOf: the most urgent state, idle when none.
        CT.check("projectStateOf the most urgent", P.projectStateOf(["idle", "working", "question"]), "question")
        CT.check("projectStateOf unknown words count for nothing", P.projectStateOf(["x"]), "idle")
        CT.check("projectStateOf of nothing is idle", P.projectStateOf([]), "idle")
        // isCatKey: no path separator, no invisible, no prototype name, at most 60 code points.
        CT.checkTrue("isCatKey accepts a name", P.isCatKey("notchmeow"))
        CT.checkTrue("isCatKey refuses constructor", !P.isCatKey("constructor"))
        CT.checkTrue("isCatKey refuses a bidi override", !P.isCatKey("a\u{202E}b"))
        // Every project's cat is picked the way CatAgentCats picks one, with the Main cat taken (the seeded source is the same).
        var pickDiffs: [String] = []
        for i in 0..<300 {
            let name = "p\(i)"
            for main in CatPresets.ids {
                let got = P.projectCatOf(name, projectCats: nil, mainCat: main).cat
                let rng = CatRNG(seed: UInt32(P.fnv1a(name), radix: 16)!)
                let want = CatAgentCats.pickCat(taken: [main], rand: rng.next)
                if got != want { pickDiffs.append("\(name) with Main \(main): \(got) vs \(want)") }
            }
        }
        CT.checkRows("projectCatOf matches CatAgentCats.pickCat for 300 names with each Main cat", pickDiffs)

        CT.finish()
    }
}
