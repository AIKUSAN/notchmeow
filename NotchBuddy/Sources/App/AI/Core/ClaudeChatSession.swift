import Foundation

// One chat's Claude Code session: its id, whether it has started, the level and model the chat is at, and what a
// level change means. Pure: `ClaudeService` holds one per conversation and asks it for each turn.

#if !APPSTORE

struct ClaudeChatSession: Sendable, Equatable {
    /// What the next turn is: the run to make, whether it needs a recap of the chat so far, and the id that is
    /// retired because the session could not be continued.
    struct Plan: Sendable, Equatable {
        var turn: ClaudeCodeTurn
        var needsRecap: Bool
        var retired: String?
    }

    private(set) var sessionID: String
    /// Claude Code has created the session (it said so in `system/init`): later turns resume it.
    private(set) var started = false
    /// Claude Code keeps a session under the folder it ran in, so it can only be resumed from there.
    private(set) var startedIn: String?
    var level: ClaudeCodeLevel = .chatOnly
    var model: ClaudeCodeModel = .sonnet

    static func newID() -> String { UUID().uuidString.lowercased() }

    init(sessionID: String = Self.newID()) { self.sessionID = sessionID }

    /// The next turn. A level change that keeps the working folder resumes the same session with the new flags.
    /// One that moves it (Agent in a project, then Chat only) starts a new session, to be seeded with a recap, and
    /// retires the old id: Claude Code could not find the old session from the new folder, and a late approval
    /// request from it must be refused.
    mutating func plan(chatFolder: String, platform: ClaudeCodePlatform = .current,
                       newID: () -> String = Self.newID) -> Plan {
        let folder = level.folder ?? chatFolder
        var retired: String?
        var recap = false
        if started, startedIn != folder {
            retired = sessionID
            sessionID = newID()
            started = false
            startedIn = nil
            recap = true
        }
        let turn = ClaudeCodeTurn(level: level, model: model, sessionID: sessionID, resume: started, platform: platform)
        return Plan(turn: turn, needsRecap: recap, retired: retired)
    }

    /// Claude Code reported the session: the next turn resumes it.
    mutating func confirmStarted(in folder: String) {
        started = true
        startedIn = folder
    }

    /// A new conversation: the old id is returned so it can be retired, and nothing of it is kept.
    mutating func reset(newID: () -> String = Self.newID) -> String {
        let old = sessionID
        self = ClaudeChatSession(sessionID: newID())
        return old
    }
}

/// The quick-action hold: a quick Explain's chat runs with no tools until the user picks a level in the picker. Memory only, never stored: a chat that is
/// cleared, opened or picked from ends it. Pure.
enum ClaudeQuickHold {
    /// The level a turn runs at: no tools while the chat is held, otherwise the level the chat has.
    static func level(held: Bool, chosen: ClaudeCodeLevel) -> ClaudeCodeLevel { held ? .noTools : chosen }
}

/// What one chat turn needs to run Claude Code: the program, the turn (session, level, model) and, for a session
/// started afresh, a recap of the chat so far.
struct ClaudeCodeSetup: Sendable, Equatable {
    var executable: String
    var turn: ClaudeCodeTurn
    var preamble: String?
}

/// A recap of the chat so far, for a session started afresh in the middle of it.
enum ClaudeCodeRecap {
    static let maxTurns = 20
    static let maxTurnChars = 1_500
    static let maxChars = 20_000

    /// nil when there is nothing to recall. Oldest turns go first when the recap is too long. Only the words are
    /// kept (no file bodies).
    static func text(turns: [(role: ChatRequest.Role, text: String)]) -> String? {
        var lines: [String] = []
        for turn in turns.suffix(maxTurns) {
            let words = turn.text.trimmingCharacters(in: .whitespacesAndNewlines)
            if words.isEmpty { continue }
            let cut = words.count > maxTurnChars ? String(words.prefix(maxTurnChars)) + "…" : words
            lines.append((turn.role == .user ? "User: " : "Assistant: ") + cut)
        }
        while lines.joined(separator: "\n").count > maxChars, lines.count > 1 { lines.removeFirst() }
        guard !lines.isEmpty else { return nil }
        return "Earlier in this chat, for context only (it is already answered):\n" + lines.joined(separator: "\n")
    }
}

/// Agent mode asks for every step through NotchMeow's hooks. Without them Claude Code refuses every step.
enum ClaudeAgentReadiness: Equatable {
    case ready
    case needsHooks

    static func check(hooksInstalled: Bool) -> ClaudeAgentReadiness { hooksInstalled ? .ready : .needsHooks }

    static let hooksNote = "Agent needs NotchMeow's hooks in Claude Code, or every step is refused. Install them in Settings."
}

#endif
