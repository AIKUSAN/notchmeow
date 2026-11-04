import Foundation

// What a Codex run means, read one stdout line at a time: its text, its steps, its usage and how it failed. It fails
// closed: the first item the level does not allow ends the turn, and then the turn shows nothing. The rules are
// `parse()` in `tests/fixtures/ai/codex/reference.py`; `expected-parse.json` pins them.

#if !APPSTORE

/// Codes on `AIError.code` for Codex's failures (copy.json's codes, typed out).
enum CodexError {
    static let missing = "nm_codex_missing"
    static let signedOut = "nm_codex_signed_out"
    static let planLimit = "nm_plan_limit"
    static let tooOld = "nm_codex_old"
    static let unreadable = "nm_codex_unreadable"
    static let crashed = "nm_codex_crashed"
    static let badModel = "nm_codex_bad_model"
    static let modelRefused = "nm_bad_model"
    static let levelExceeded = "nm_level_exceeded"
    static let levelUnavailable = "nm_level_unavailable"

    /// copy.json's kind for a code.
    static func kind(of code: String) -> AIErrorKind {
        switch code {
        case missing: .unreachable
        case signedOut: .auth
        case planLimit: .billing
        case tooOld, unreadable, badModel, modelRefused, levelExceeded, levelUnavailable: .badRequest
        case crashed: .interrupted
        default: .interrupted // fail-safe: a code no table names is shown as an interruption, never as a success
        }
    }
}

/// levels.json and copy.json, typed out. The tests replay both files against these values.
enum CodexLevels {
    /// The item types each level may carry. Any other item ends the turn.
    static let items: [String: Set<String>] = {
        let words: Set<String> = ["agent_message", "reasoning", "todo_list"]
        return ["chat": words, "none": words, "read": words.union(["command_execution"])]
    }()
    static let notes: Set<String> = ["error"]
    static let retryNotes = ["Reconnecting..."]
    /// A step's item type to the one field that names the work.
    static let stepFields = ["command_execution": "command", "web_search": "query"]
    static let stepKinds = ["command_execution": "command", "web_search": "search"]
    static let stepFieldCap = 200

    struct Match: Equatable, Sendable {
        var code: String
        var inStderr: Bool
        var contains: [String]
    }

    /// In order: the first match wins.
    static let matches: [Match] = [
        Match(code: CodexError.signedOut, inStderr: true, contains: ["Not logged in"]),
        Match(code: CodexError.planLimit, inStderr: false, contains: ["usage limit"]),
        Match(code: CodexError.badModel, inStderr: false, contains: ["model is not supported when using Codex"]),
        Match(code: CodexError.signedOut, inStderr: false, contains: ["401 Unauthorized"]),
    ]
}

/// One command or search the run made. `value` is the field that names the work, cut to 200 Unicode scalars.
struct CodexStep: Equatable, Sendable {
    var kind: String
    var field: String
    var value: String
    var done: Bool
}

/// What a run means once it has ended. `error` carries a kind and a code only, never the provider's message text.
struct CodexTurn: Equatable, Sendable {
    /// nil: no thread.started, so no engine. .some(nil): a thread.started with no id.
    var thread: String?? = nil
    var text = ""
    var steps: [CodexStep] = []
    var finished = false
    var usage: [String: Int]? = nil
    var error: AIError? = nil
}

struct CodexStreamParser: Sendable {
    private let allowed: Set<String>
    private var thread: String?? = nil
    private var texts: [String] = []
    private var steps: [CodexStep] = []
    private var finished = false
    private var usage: [String: Int]? = nil
    /// Lines that were JSON objects. Other lines are skipped and not counted.
    private var seen = 0
    /// Set once the turn must end (a failure, or a level that is not offered). It then is the turn's whole meaning.
    private var stopped: CodexTurn? = nil

    init(level: String) {
        guard let items = CodexLevels.items[level] else {
            allowed = []
            stopped = Self.failure(CodexError.levelUnavailable, thread: nil)
            return
        }
        allowed = items
    }

    /// One stdout line. False: the turn must stop now (a failure, or a level that is not offered); read no more.
    mutating func consume(line: String) -> Bool {
        if stopped != nil { return false }
        guard let ev = Self.object(line) else { return true }
        seen += 1
        switch ev["type"] as? String {
        case "thread.started":
            thread = .some(Self.threadID(ev))
        case "item.started":
            return consumeItem(ev, completed: false)
        case "item.completed":
            return consumeItem(ev, completed: true)
        case "turn.completed":
            finished = true
            usage = Self.usage(ev["usage"])
        case "turn.failed":
            let err = (ev["error"] as? [String: Any]) ?? [:]
            return stop(Self.classify(err["message"] as? String, inStderr: false) ?? CodexError.crashed)
        case "error":
            let message = ev["message"] as? String
            if let message, Self.isRetryNote(message) { break }
            return stop(Self.classify(message, inStderr: false) ?? CodexError.crashed)
        default:
            break
        }
        return true
    }

    /// The turn's meaning once the run has ended: its failure when there was one; else its text, steps and usage when it
    /// finished; else what stderr says; else unreadable (no output at exit 0) or a crash.
    func finish(exit: Int32?, stderr: String) -> CodexTurn {
        if let stopped { return stopped }
        if finished {
            return CodexTurn(thread: thread, text: texts.joined(separator: "\n\n"), steps: steps,
                             finished: true, usage: usage, error: nil)
        }
        if let code = Self.classify(stderr, inStderr: true) { return Self.failure(code, thread: thread) }
        if seen == 0 && exit == 0 { return Self.failure(CodexError.unreadable, thread: thread) }
        return Self.failure(CodexError.crashed, thread: thread)
    }

    static func parse(lines: [String], exit: Int32?, stderr: String, level: String) -> CodexTurn {
        var parser = CodexStreamParser(level: level)
        for line in lines {
            if !parser.consume(line: line) { break }
        }
        return parser.finish(exit: exit, stderr: stderr)
    }

    // MARK: - Items

    private mutating func consumeItem(_ ev: [String: Any], completed: Bool) -> Bool {
        let item = (ev["item"] as? [String: Any]) ?? [:]
        let kind = (item["type"] as? String) ?? ""
        if CodexLevels.notes.contains(kind) { return true }
        guard allowed.contains(kind) else { return stop(CodexError.levelExceeded) }
        if completed {
            if kind == "agent_message", let text = item["text"] as? String {
                texts.append(text)
            }
            if let field = CodexLevels.stepFields[kind], let stepKind = CodexLevels.stepKinds[kind] {
                let value = (item[field] as? String) ?? ""
                let done = (item["status"] as? String) == "completed"
                steps.append(CodexStep(kind: stepKind, field: field, value: Self.cut(value), done: done))
            }
        }
        return true
    }

    private mutating func stop(_ code: String) -> Bool {
        stopped = Self.failure(code, thread: thread)
        return false
    }

    // MARK: - Helpers

    private static func failure(_ code: String, thread: String??) -> CodexTurn {
        CodexTurn(thread: thread, error: AIError(kind: CodexError.kind(of: code), code: code))
    }

    /// The JSON object on a line, or nil when the line is not one. A Swift-only limit, documented: JSONSerialization rejects
    /// the bare NaN and Infinity that json.loads accepts, so such a line is skipped like any other line that is not JSON.
    /// serde cannot emit them, and the shell-off flags are the primary barrier. Unparsable lines do not fail closed.
    private static func object(_ line: String) -> [String: Any]? {
        guard let data = line.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data) else { return nil }
        return value as? [String: Any]
    }

    /// `thread_id` when it is a string; else the one key other than `type`, when it is a string.
    private static func threadID(_ ev: [String: Any]) -> String? {
        if let id = ev["thread_id"] as? String { return id }
        let others = ev.filter { $0.key != "type" }
        guard others.count == 1 else { return nil }
        return others.first?.value as? String
    }

    /// The integers of a usage object; nil when it is not an object.
    private static func usage(_ value: Any?) -> [String: Int]? {
        (value as? [String: Any])?.compactMapValues(integer)
    }

    /// An integer JSON number. A bool is an NSNumber too (`as? Int` reads it as 1), and a float is not an integer.
    private static func integer(_ value: Any) -> Int? {
        guard let number = value as? NSNumber, CFGetTypeID(number) != CFBooleanGetTypeID(),
              !CFNumberIsFloatType(number as CFNumber) else { return nil }
        return number.intValue
    }

    /// The code for a failure text by the match table, or nil when nothing matches.
    private static func classify(_ text: String?, inStderr: Bool) -> String? {
        guard let text else { return nil }
        return CodexLevels.matches.first { match in
            // A literal, case-sensitive contains: no case folding and no canonical equivalence.
            match.inStderr == inStderr && match.contains.contains { text.range(of: $0, options: .literal) != nil }
        }?.code
    }

    /// A retry note is skipped: a message that starts with one of `retryNotes`, compared scalar by scalar.
    private static func isRetryNote(_ message: String) -> Bool {
        CodexLevels.retryNotes.contains { note in
            message.unicodeScalars.starts(with: note.unicodeScalars)
        }
    }

    /// The first `stepFieldCap` Unicode scalars, as a Python slice of the same string gives.
    private static func cut(_ value: String) -> String {
        String(String.UnicodeScalarView(value.unicodeScalars.prefix(CodexLevels.stepFieldCap)))
    }
}

#endif
