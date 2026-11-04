import Foundation

// Shared helpers for the cat test programs (scripts/test-cat-*.sh compile this file into each one).
// Run from the repository root: fixture paths are relative to it.
// Numbers compare within 1e-9, because Swift and JavaScript can differ in the last bit of sin, cos and pow.

@MainActor
enum CT {
    static var failures = 0
    static let tolerance = 1e-9

    /// Every section starts here, so a test program run by hand (without `NM_LOG_DIR`) stops before it does anything.
    static func section(_ name: String) {
        requireTempLog()
        print(name)
    }

    /// Tests never write to the user's real log: `scripts/test-*.sh` set `NM_LOG_DIR` to a temp folder.
    static func requireTempLog() {
        guard let dir = ProcessInfo.processInfo.environment["NM_LOG_DIR"], !dir.isEmpty, !dir.contains("/Library/Logs") else {
            print("NM_LOG_DIR is not set to a temp folder: run this through its scripts/test-*.sh")
            exit(2)
        }
    }

    static func check<V: Equatable>(_ label: String, _ got: V, _ expected: V) {
        if got == expected {
            print("  ✓ \(label)")
        } else {
            print("  ✗ \(label)")
            print("    got:      \(got)")
            print("    expected: \(expected)")
            failures += 1
        }
    }

    static func checkTrue(_ label: String, _ value: Bool) {
        if value { print("  ✓ \(label)") } else { print("  ✗ \(label)"); failures += 1 }
    }

    /// `got` within `tol` of `want`.
    static func checkNear(_ label: String, _ got: Double, _ want: Double, tol: Double = tolerance) {
        if abs(got - want) <= tol { print("  ✓ \(label)") } else {
            print("  ✗ \(label)\n    got:      \(got)\n    expected: \(want)")
            failures += 1
        }
    }

    static func finish() -> Never {
        if failures == 0 {
            print("\nAll tests passed.")
            exit(0)
        }
        print("\n\(failures) test(s) failed.")
        exit(1)
    }

    // MARK: - Fixtures

    /// `tests/fixtures/<dir>/<file>`: the cat fixtures by default, the AI fixtures with `dir: "ai"`.
    static func fixtureURL(_ file: String, dir: String = "cat") -> URL {
        URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            .appendingPathComponent("tests/fixtures/\(dir)")
            .appendingPathComponent(file)
    }

    /// A parsed fixture file (a dictionary at the top level).
    static func fixture(_ file: String, dir: String = "cat") -> [String: Any] {
        let data = try! Data(contentsOf: fixtureURL(file, dir: dir))
        return try! JSONSerialization.jsonObject(with: data) as! [String: Any]
    }

    // MARK: - Deep compare with a tolerance

    /// The differences between two JSON-shaped values; empty when equal. Numbers compare within `tol`,
    /// strings, booleans and the shape of the data compare exactly. A key that is null counts as absent.
    static func diffs(_ got: Any, _ want: Any, tol: Double = tolerance) -> [String] {
        var out: [String] = []
        compare(got, want, "$", tol, &out)
        return out
    }

    static func checkJSON(_ label: String, got: Any, want: Any, tol: Double = tolerance) {
        let d = diffs(got, want, tol: tol)
        if d.isEmpty { print("  ✓ \(label)") } else {
            print("  ✗ \(label) (\(d.count) differences)")
            for line in d.prefix(6) { print("    \(line)") }
            failures += 1
        }
    }

    private static func isBool(_ x: Any) -> Bool {
        guard let n = x as? NSNumber else { return false }
        return CFGetTypeID(n) == CFBooleanGetTypeID()
    }

    private static func compare(_ got: Any, _ want: Any, _ at: String, _ tol: Double, _ out: inout [String]) {
        if got is NSNull && want is NSNull { return }
        if let g = got as? [String: Any], let w = want as? [String: Any] {
            let gk = Set(g.filter { !($0.value is NSNull) }.keys), wk = Set(w.filter { !($0.value is NSNull) }.keys)
            if gk != wk { out.append("\(at): keys \(gk.sorted()) vs \(wk.sorted())") }
            for k in gk.intersection(wk).sorted() { compare(g[k]!, w[k]!, "\(at).\(k)", tol, &out) }
        } else if let g = got as? [Any], let w = want as? [Any] {
            if g.count != w.count { out.append("\(at): length \(g.count) vs \(w.count)") }
            for i in 0..<min(g.count, w.count) { compare(g[i], w[i], "\(at)[\(i)]", tol, &out) }
        } else if let g = got as? String, let w = want as? String {
            if g != w { out.append("\(at): \"\(g)\" vs \"\(w)\"") }
        } else if let g = got as? NSNumber, let w = want as? NSNumber {
            if isBool(g) != isBool(w) { out.append("\(at): \(g) vs \(w) (bool against number)") }
            else if isBool(g) { if g.boolValue != w.boolValue { out.append("\(at): \(g) vs \(w)") } }
            else if !(abs(g.doubleValue - w.doubleValue) <= tol) { out.append("\(at): \(g.doubleValue) vs \(w.doubleValue)") }
        } else {
            out.append("\(at): \(type(of: got)) \(got) vs \(type(of: want)) \(want)")
        }
    }

    /// A Swift `Encodable` as the JSON-shaped value the fixtures hold.
    static func json<E: Encodable>(_ value: E) -> Any {
        let data = try! JSONEncoder().encode(value)
        return try! JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }
}

// MARK: - Checks for groups of rows

extension CT {
    /// One line for a whole group of rows: ✓ when none differ, else the first few differences.
    static func checkRows(_ label: String, _ diffs: [String]) {
        if diffs.isEmpty { print("  ✓ \(label)") } else {
            print("  ✗ \(label) (\(diffs.count) differences)")
            for d in diffs.prefix(6) { print("    \(d)") }
            failures += 1
        }
    }
}
