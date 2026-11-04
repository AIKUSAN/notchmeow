import Foundation

// The Projects leak pins (Task 5, the privacy rule of the spec): a session's whole life is fed through the model with a marker planted in every field that
// must never show, store or log: the folder, a prompt, a message, the last assistant message, a transcript path, a tool's command, a search query and a
// tool's response. Checked after every event: no display string holds the marker, a `/` or a `\`; no step does; the stored cat key and value do not; no file
// in the log folder holds the marker. The program writes nothing; scripts/test-projects-leak.sh runs it with HOME set to an empty folder and checks that
// folder is still empty afterwards.
@main
enum ProjectsLeakTests {
    static let marker = "zqLEAKqz"
    static let home = "/Users/sam"
    static let folder = "/Users/sam/zqLEAKqz/proj"

    @MainActor
    final class Clock {
        var t: Double
        init(_ t: Double) { self.t = t }
    }

    /// Every string the view shows: the project's and the sessions' names, labels, notes, steps, hosts, cats and subagent types.
    static func displayStrings(_ v: PJView) -> [String] {
        var out: [String] = []
        for p in v.projects {
            out += [p.id, p.name, p.catKey, p.cat, p.step, p.host]
            for s in p.sessions {
                out += [s.role, s.label, s.note, s.step, s.host, s.state]
                out += s.subagents.map { $0.type }
            }
        }
        return out
    }

    /// A text that holds the marker or a path separator.
    static func leaks(_ text: String) -> Bool {
        text.contains(marker) || text.contains("/") || text.contains("\\")
    }

    @MainActor
    static func main() {
        CT.section("a session's whole life, with the marker in every field that must not show")
        let clock = Clock(1_760_000_000_000)
        let model = ProjectsModel(home: home, now: { clock.t }, schedule: { _, _ in {} })
        let life: [[String: Any]] = [
            ["hook_event_name": "SessionStart", "session_id": "s-leak", "cwd": folder,
             "transcript_path": "/Users/sam/.claude/projects/\(marker)/s.jsonl"],
            ["hook_event_name": "UserPromptSubmit", "session_id": "s-leak", "cwd": folder, "prompt": "fix \(marker) now"],
            ["hook_event_name": "PreToolUse", "session_id": "s-leak", "cwd": folder, "tool_name": "Bash",
             "tool_input": ["command": "echo \(marker) > /Users/sam/\(marker).txt"]],
            ["hook_event_name": "PostToolUse", "session_id": "s-leak", "cwd": folder, "tool_name": "Bash",
             "tool_response": ["stdout": marker]],
            ["hook_event_name": "PreToolUse", "session_id": "s-leak", "cwd": folder, "tool_name": "Grep",
             "tool_input": ["query": marker]],
            ["hook_event_name": "PreToolUse", "session_id": "s-leak", "cwd": folder, "tool_name": "Read",
             "tool_input": ["file_path": "/Users/sam/\(marker)/proj/notes.md"]],
            ["hook_event_name": "Notification", "session_id": "s-leak", "cwd": folder, "message": "\(marker) waits?"],
            ["hook_event_name": "PermissionRequest", "session_id": "s-leak", "cwd": folder, "tool_name": "Bash",
             "tool_input": ["command": "rm \(marker)"], "message": marker],
            ["hook_event_name": "SubagentStart", "session_id": "s-leak", "cwd": folder, "agent_id": "sub-1", "agent_type": "Explore"],
            ["hook_event_name": "Stop", "session_id": "s-leak", "cwd": folder, "last_assistant_message": "done \(marker)"],
        ]
        var shown: [String] = []
        var stepLeaks: [String] = []
        for p in life {
            clock.t += 1000
            model.feed(payload: p)
            shown += displayStrings(model.view()).filter(leaks)
            stepLeaks += model.steps.values.filter(leaks)
        }
        let v = model.view()
        CT.checkTrue("the session is shown (the test is not vacuous)", !v.projects.isEmpty && v.projects[0].sessions.count == 1)
        CT.checkTrue("the full folder is kept in memory", model.registry.sessions.first?.cwd == folder)
        CT.check("no display string holds the marker, a / or a \\", shown, [])
        CT.check("no step holds the marker, a / or a \\", stepLeaks, [])
        CT.check("the step the notch shows is the words, not the command", model.steps["s-leak"], "Reads · notes.md")

        CT.section("the stored cat holds no path, prompt or command")
        let mem = MemoryBacking()
        let store = CatSettingsStore(backing: mem, config: CatConfig())
        store.setProjectCat("leo", for: v.projects.first?.catKey ?? "proj")
        let stored = mem.allKeys() + mem.values.values.map { String(describing: $0) }
        CT.check("the stored keys and values hold no marker, a / or a \\", stored.filter(leaks), [])

        CT.section("the log folder holds no file with the marker, and the walk is real")
        let logDir = ProcessInfo.processInfo.environment["NM_LOG_DIR"] ?? ""
        CT.checkTrue("the log folder exists (the script creates it)", FileManager.default.fileExists(atPath: logDir))
        func logHits() -> [String] {
            var hits: [String] = []
            guard let walk = FileManager.default.enumerator(atPath: logDir) else { return hits }
            for case let rel as String in walk {
                let full = (logDir as NSString).appendingPathComponent(rel)
                var isDir: ObjCBool = false
                if FileManager.default.fileExists(atPath: full, isDirectory: &isDir), !isDir.boolValue,
                   let text = try? String(contentsOfFile: full, encoding: .utf8), text.contains(marker) {
                    hits.append(rel)
                }
            }
            return hits
        }
        // A planted file proves the walk can find the marker (the check is not vacuous); it is removed again at once.
        let canary = (logDir as NSString).appendingPathComponent("canary.txt")
        try? "canary \(marker)".write(toFile: canary, atomically: true, encoding: .utf8)
        CT.check("the walk finds a planted canary", logHits(), ["canary.txt"])
        try? FileManager.default.removeItem(atPath: canary)
        CT.check("no log file holds the marker", logHits(), [])

        CT.finish()
    }
}
