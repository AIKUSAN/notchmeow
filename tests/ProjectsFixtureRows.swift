import Foundation

// The rows of a Projects fixture group, with the count the test expects written into the test (P-mac, fix wave 2). A group that is missing, renamed, empty or not an
// array of objects used to read as no rows, so its loop ran zero times and the suite stayed green; now it fails loudly, and so does a group with fewer or more rows than
// the test lists. A deliberate fixture change (tests/fixtures/projects/ is generated from shared/projects-core.js) updates the number in the test beside it.
// Compiled into scripts/test-projects-{rules,registry,model}.sh.
@MainActor
enum PJFixtureRows {
    /// The rows of the top-level `group` of `fixture` (read from `file`), after checking that there are exactly `expect` of them and that every row has each of `keys`
    /// (a key may hold null: a renamed `expect` would otherwise read as the null a row can legitimately expect).
    static func group(_ file: String, _ fixture: [String: Any], _ group: String, expect: Int, keys: [String] = ["name", "expect"]) -> [[String: Any]] {
        guard let rows = fixture[group] as? [[String: Any]] else {
            CT.checkTrue("\(file): the group \(group) is there, an array of objects", false)
            return []
        }
        CT.check("\(file): the group \(group) has its \(expect) rows (a deliberate fixture change updates this number)", rows.count, expect)
        let lacking = rows.compactMap { r in keys.filter { r[$0] == nil }.isEmpty ? nil : "\(r["name"] as? String ?? "?"): \(keys.filter { r[$0] == nil })" }
        CT.check("\(file): every row of \(group) has \(keys.joined(separator: ", "))", lacking, [])
        return rows
    }

    /// The rows of the nested array `key` of one case (`c`, named `name`): not optional, and a row that is not an object fails.
    static func nested(_ file: String, _ c: [String: Any], _ key: String) -> [[String: Any]] {
        guard let rows = c[key] as? [[String: Any]] else {
            CT.checkTrue("\(file): \(c["name"] as? String ?? "?") has its \(key) rows, an array of objects", false)
            return []
        }
        return rows
    }
}
