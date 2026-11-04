import Foundation

// ConfigFileWrite: how NotchMeow writes another tool's config file (Claude Code's settings.json, Gemini's settings.json, Codex's and Antigravity's hooks.json). Every file here is in a folder
// of this script's own (NM_CONFIG_TEST_DIR, made by scripts/test-config-file-write.sh): the user's real ~/.claude, ~/.gemini and ~/.codex are never read or written.

@main
@MainActor
enum ConfigFileWriteTests {
    static let fm = FileManager.default
    static var base = URL(fileURLWithPath: "/")

    static func folder(_ name: String) throws -> URL {
        let dir = base.appendingPathComponent(name)
        try fm.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }
    static func put(_ text: String, at url: URL, mode: Int = 0o644) throws {
        try fm.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(text.utf8).write(to: url)
        try fm.setAttributes([.posixPermissions: mode], ofItemAtPath: url.path)
    }
    static func text(_ url: URL) -> String { (try? String(contentsOf: url, encoding: .utf8)) ?? "(unreadable)" }
    static func mode(_ url: URL) -> Int { ((try? fm.attributesOfItem(atPath: url.path))?[.posixPermissions] as? NSNumber)?.intValue ?? -1 }
    static func isLink(_ url: URL) -> Bool { (try? fm.attributesOfItem(atPath: url.path))?[.type] as? FileAttributeType == .typeSymbolicLink }
    static func link(_ at: URL, to destination: String) throws {
        try fm.createDirectory(at: at.deletingLastPathComponent(), withIntermediateDirectories: true)
        try fm.createSymbolicLink(atPath: at.path, withDestinationPath: destination)
    }
    /// Both sides of a path comparison go through the same normalising call (the temp folder sits behind /var, a link to /private/var).
    static func same(_ a: URL, _ b: URL) -> Bool { a.resolvingSymlinksInPath().path == b.resolvingSymlinksInPath().path }

    static func main() {
        CT.section("the folder of this test")
        guard let path = ProcessInfo.processInfo.environment["NM_CONFIG_TEST_DIR"], path.contains("notchmeow-config-write"), !path.contains("/.claude"), !path.contains("/.gemini"), !path.contains("/.codex") else {
            print("NM_CONFIG_TEST_DIR is not a temp folder of this script: run this through scripts/test-config-file-write.sh")
            exit(2)
        }
        base = URL(fileURLWithPath: path)
        CT.checkTrue("it is a folder made for this run", (try? fm.createDirectory(at: base, withIntermediateDirectories: true)) != nil)

        func scenario(_ name: String, _ body: (URL) throws -> Void) {
            CT.section(name)
            do { try body(try folder(String(name.prefix(24)).filter { $0.isLetter || $0.isNumber })) } catch { CT.checkTrue("the scenario ran: \(error)", false) }
        }

        scenario("a plain file: replaced, and its permissions kept") { dir in
            for want in [0o600, 0o640, 0o644, 0o755] {
                let file = dir.appendingPathComponent("plain-\(want).json")
                try put("{\"old\":1}", at: file, mode: want)
                try ConfigFileWrite.write(Data("{\"new\":1}".utf8), to: file)
                CT.check("text \(String(want, radix: 8)): the new text", text(file), "{\"new\":1}")
                CT.check("mode \(String(want, radix: 8)): the same", mode(file), want)
            }
            CT.check("resolving a plain file is that file", same(ConfigFileWrite.resolved(dir.appendingPathComponent("plain-600.json")), dir.appendingPathComponent("plain-600.json")), true)
        }

        scenario("a file that is not there yet: made, with its folder") { dir in
            let file = dir.appendingPathComponent("new/deeper/settings.json")
            try ConfigFileWrite.write(Data("{}".utf8), to: file)
            CT.check("written", text(file), "{}")
            CT.checkTrue("a new file is readable by its owner", mode(file) & 0o600 == 0o600)
        }

        scenario("a symbolic link: it stays a link, the file it points at changes, with its permissions") { dir in
            let target = dir.appendingPathComponent("dotfiles/settings.json"), settings = dir.appendingPathComponent("home/.cfg/settings.json")
            try put("{\"old\":1}", at: target, mode: 0o600)
            try link(settings, to: target.path)
            try ConfigFileWrite.write(Data("{\"new\":1}".utf8), to: settings)
            CT.check("the link is still a link", isLink(settings), true)
            CT.check("the file it points at has the new text", text(target), "{\"new\":1}")
            CT.check("the file it points at keeps 0600 (a link's own mode is 0755)", mode(target), 0o600)
            CT.check("reading through the link gives the new text", text(settings), "{\"new\":1}")
        }

        scenario("the dated backup of a link holds the file's text, not a second link") { dir in
            let target = dir.appendingPathComponent("dotfiles/hooks.json"), settings = dir.appendingPathComponent("home/hooks.json"), backup = dir.appendingPathComponent("home/hooks.json.bak-20261008-1200")
            try put("{\"before\":1}", at: target, mode: 0o600)
            try link(settings, to: target.path)
            try ConfigFileWrite.backUp(settings, to: backup)
            try ConfigFileWrite.write(Data("{\"after\":1}".utf8), to: settings)
            CT.check("the backup is a file, not a link", isLink(backup), false)
            CT.check("it still holds the text from before the write", text(backup), "{\"before\":1}")
            CT.check("and the write changed the file the link points at", text(target), "{\"after\":1}")
            CT.check("the backup of a plain file is a copy too", try { let f = dir.appendingPathComponent("plain.json"), b = dir.appendingPathComponent("plain.json.bak"); try put("{\"p\":1}", at: f); try ConfigFileWrite.backUp(f, to: b); return text(b) }(), "{\"p\":1}")
        }

        scenario("a relative link, a chain of links and a link through a linked folder") { dir in
            let shared = dir.appendingPathComponent("shared/settings.json")
            try put("{\"old\":1}", at: shared, mode: 0o640)
            let relative = dir.appendingPathComponent("home/.cfg/settings.json")
            try link(relative, to: "../../shared/settings.json")
            CT.check("a relative link resolves to its file", same(ConfigFileWrite.resolved(relative), shared), true)
            let chain = dir.appendingPathComponent("home/chain.json"), middle = dir.appendingPathComponent("home/middle.json")
            try link(middle, to: relative.path)
            try link(chain, to: "middle.json")
            CT.check("a chain of two links resolves to the last file", same(ConfigFileWrite.resolved(chain), shared), true)
            try ConfigFileWrite.write(Data("{\"new\":1}".utf8), to: chain)
            CT.check("both links stay links and the shared file changes, with 0640", [isLink(chain), isLink(middle), isLink(relative), text(shared) == "{\"new\":1}", mode(shared) == 0o640], [true, true, true, true, true])
            // ~/.claude is itself a link to another folder, and settings.json in it is a relative link: the link is read from the real folder, not from the path it was reached through.
            let store = dir.appendingPathComponent("store/claude/settings.json"), other = dir.appendingPathComponent("store/shared/settings.json"), home = dir.appendingPathComponent("home2/.claude")
            try put("{\"viaDir\":1}", at: other, mode: 0o600)
            try link(store, to: "../shared/settings.json")
            try link(home, to: dir.appendingPathComponent("store/claude").path)
            CT.check("through a linked folder", same(ConfigFileWrite.resolved(home.appendingPathComponent("settings.json")), other), true)
            try ConfigFileWrite.write(Data("{\"viaDir\":2}".utf8), to: home.appendingPathComponent("settings.json"))
            CT.check("the file at the end changes", text(other), "{\"viaDir\":2}")
        }

        scenario("a link to a file that is not there: the file is made where the link points") { dir in
            let target = dir.appendingPathComponent("elsewhere/not-yet/settings.json"), settings = dir.appendingPathComponent("home/settings.json")
            try link(settings, to: target.path)
            try ConfigFileWrite.write(Data("{\"first\":1}".utf8), to: settings)
            CT.check("the link is still a link, and the file is where it points", [isLink(settings), text(target) == "{\"first\":1}"], [true, true])
        }

        scenario("a loop of links ends") { dir in
            let a = dir.appendingPathComponent("home/a.json"), b = dir.appendingPathComponent("home/b.json")
            try link(a, to: "b.json")
            try link(b, to: "a.json")
            _ = ConfigFileWrite.resolved(a)
            CT.checkTrue("resolving a loop returns", true)
        }

        // Reading a config file before changing it: a file that is there but cannot be read as a JSON object is never taken for an empty one, because a write built from [:] drops everything the user had in it.
        scenario("reading a config file: missing is empty, an unreadable one is refused") { dir in
            let label = "~/.claude/settings.json"
            @MainActor func refused(_ name: String, _ body: String) throws {
                let file = dir.appendingPathComponent(name)
                try put(body, at: file)
                do { _ = try ConfigFileWrite.readObject(at: file, label: label); CT.checkTrue("\(name): refused", false) }
                catch {
                    let said = (error as NSError).localizedDescription
                    CT.checkTrue("\(name): refused, and the message names the file and says it was left alone (\(said))", said.contains(label) && said.contains("not valid JSON") && said.contains("has not touched it"))
                }
                CT.check("\(name): the file is as it was", text(file), body)
            }
            CT.check("a file that is not there is an empty object", (try? ConfigFileWrite.readObject(at: dir.appendingPathComponent("nope.json"), label: label))?.count, 0)
            let good = dir.appendingPathComponent("good.json")
            try put("{\"model\":\"opus\",\"env\":{\"A\":\"1\"}}", at: good)
            let obj = try ConfigFileWrite.readObject(at: good, label: label)
            CT.check("a JSON object is read", [obj["model"] as? String, (obj["env"] as? [String: Any])?["A"] as? String], ["opus", "1"])
            let blank = dir.appendingPathComponent("blank.json")
            try put("  \n", at: blank)
            CT.check("a file with only whitespace holds nothing to lose: an empty object", (try? ConfigFileWrite.readObject(at: blank, label: label))?.count, 0)
            try refused("comments.json", "{\n  // mine\n  \"model\": \"opus\",\n}\n")
            try refused("array.json", "[1,2]")
            try refused("truncated.json", "{\"model\":\"op")
            try refused("scalar.json", "\"opus\"")
        }

        scenario("writing a config file with its dated backup: the backup's name comes back") { dir in
            let when = Calendar.current.date(from: DateComponents(year: 2026, month: 10, day: 17, hour: 12, minute: 34, second: 56))!
            let file = dir.appendingPathComponent("home/settings.json")
            CT.check("no file yet: nothing to back up, nothing named", try ConfigFileWrite.writeWithBackup(Data("{\"a\":1}".utf8), to: file, suffix: "settings.json", now: when), nil as String?)
            CT.check("and the file is written", text(file), "{\"a\":1}")
            let name = try ConfigFileWrite.writeWithBackup(Data("{\"a\":2}".utf8), to: file, suffix: "settings.json", now: when)
            CT.check("the backup is named with the suffix and the second", name, "settings.json.bak-20261017-123456")
            CT.check("it sits beside the file and holds the text from before", text(file.deletingLastPathComponent().appendingPathComponent(name ?? "-")), "{\"a\":1}")
            CT.check("the file holds the new text", text(file), "{\"a\":2}")
            let again = try ConfigFileWrite.writeWithBackup(Data("{\"a\":3}".utf8), to: file, suffix: "settings.json", now: when)
            CT.check("a second write in the same second never replaces or fails on the first backup", [again, text(file.deletingLastPathComponent().appendingPathComponent("settings.json.bak-20261017-123456")), text(file.deletingLastPathComponent().appendingPathComponent(again ?? "-"))], ["settings.json.bak-20261017-123456-1", "{\"a\":1}", "{\"a\":2}"] as [String?])
        }

        scenario("a backup that cannot be made stops the write: the file is not touched") { dir in
            let sealed = dir.appendingPathComponent("sealed")
            let file = sealed.appendingPathComponent("settings.json")
            try put("{\"keep\":1}", at: file)
            try fm.setAttributes([.posixPermissions: 0o555], ofItemAtPath: sealed.path)   // the folder cannot take the backup beside the file
            defer { try? fm.setAttributes([.posixPermissions: 0o755], ofItemAtPath: sealed.path) }
            if getuid() == 0 { CT.checkTrue("root ignores folder permissions: skipped", true); return }
            do { _ = try ConfigFileWrite.writeWithBackup(Data("{\"new\":1}".utf8), to: file, suffix: "settings.json"); CT.checkTrue("it threw", false) }
            catch { CT.checkTrue("it threw: \((error as NSError).localizedDescription)", (error as NSError).localizedDescription.contains("Could not back up settings.json")) }
            CT.check("the file is as it was", text(file), "{\"keep\":1}")
        }

        scenario("the app's writers use it: the source says so, and the rule of a backup, a merge, a diff and a confirm still holds") { _ in
            let hook = (try? String(contentsOfFile: "NotchBuddy/Sources/App/HookServer.swift", encoding: .utf8)) ?? ""
            func count(_ needle: String) -> Int { hook.components(separatedBy: needle).count - 1 }
            func body(of signature: String) -> String {
                guard let start = hook.range(of: signature) else { return "" }
                let rest = hook[start.upperBound...]
                return String(rest.prefix(upTo: rest.range(of: "\n    }\n")?.lowerBound ?? rest.endIndex))
            }
            CT.checkTrue("the source was read", hook.contains("func writeJSONFile"))
            let json = body(of: "private func writeJSONFile(_ data: Data, to url: URL, suffix: String) throws {"), strict = body(of: "private static func strictReadJSONObject(at url: URL, label: String) throws -> [String: Any] {")
            CT.checkTrue("writeJSONFile (Gemini's settings, Codex's and Antigravity's hooks) backs up and writes through ConfigFileWrite (one function for every writer), and no longer writes atomically to the link", !json.isEmpty && json.contains("try ConfigFileWrite.writeWithBackup(data, to: url, suffix: suffix)") && !json.contains(".atomic") && !json.contains("copyItem"))
            CT.checkTrue("and the strict read of those files is ConfigFileWrite's too", !strict.isEmpty && strict.contains("try ConfigFileWrite.readObject(at: url, label: label)"))
            let hooksWrite = body(of: "func writeClaudeHooks() throws -> String? {"), statusWrite = body(of: "func writeStatusLine() throws -> String? {"), uninstall = body(of: "func uninstallClaudeHooks() throws -> Bool {")
            let build = body(of: "private func buildHooksData() throws -> Data {"), previewSL = body(of: "func previewStatusLine(install: Bool) throws -> String {")
            CT.checkTrue("Claude Code's installer writes only what the user confirmed (the preview's pending data), after a dated backup that must succeed, through ConfigFileWrite, and says so when there is no preview", hooksWrite.contains("guard let data = _pendingHooksData else { throw Self.noPreview }") && hooksWrite.contains("try ConfigFileWrite.writeWithBackup(data, to: settingsURL, suffix: \"settings.json\")") && !hooksWrite.contains("try?") && !hooksWrite.contains(".atomic") && hooksWrite.contains("return backup"))
            CT.checkTrue("so does the plan gauge's status line writer", statusWrite.contains("guard let data = _pendingStatusLineData else { throw Self.noPreview }") && statusWrite.contains("try ConfigFileWrite.writeWithBackup(data, to: settingsURL, suffix: \"settings.json\")") && !statusWrite.contains("try? ConfigFileWrite") && statusWrite.contains("return backup"))
            CT.checkTrue("and the uninstall: it reads the file strictly, writes through ConfigFileWrite, and says whether it removed anything", uninstall.contains("try ConfigFileWrite.readObject(at: settingsURL, label: \"~/.claude/settings.json\")") && uninstall.contains("try ConfigFileWrite.write(newData, to: settingsURL)") && !uninstall.contains(".atomic") && !uninstall.contains("try? JSONSerialization") && uninstall.contains("return true") && uninstall.contains("return false"))
            CT.checkTrue("a settings.json that does not parse is never taken for an empty one: both previews read it strictly, and neither starts from an empty dictionary", build.contains("try ConfigFileWrite.readObject(at: settingsURL, label: \"~/.claude/settings.json\")") && previewSL.contains("try ConfigFileWrite.readObject(at: settingsURL, label: \"~/.claude/settings.json\")") && !build.contains("var settings: [String: Any] = [:]") && !previewSL.contains("var settings: [String: Any] = [:]"))
            CT.check("the preview still builds the data before anything is written (the install's and the status line's)", [hook.contains("func previewClaudeHooks() throws -> String {") && hook.contains("_pendingHooksData = data"), hook.contains("func previewStatusLine(install: Bool) throws -> String {") && hook.contains("_pendingStatusLineData = data")], [true, true])
            CT.check("the App Store build's own two writes (its sandbox folder grant) are as they were", count("newData.write(to: settingsURL, options: .atomic)") + count("try data.write(to: settingsURL, options: .atomic)"), 2)
        }

        CT.finish()
    }
}
