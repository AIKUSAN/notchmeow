import Foundation

// The words on the two chips and what the chat says for each Claude Code failure.
// Fixtures: `tests/fixtures/ai/claude-code/labels.json` and `copy.json`.

#if !APPSTORE

enum ClaudeCodeText {
    /// The note for a failure, with its one button. The button's names are `copy.json`'s; the app maps them to its own actions.
    struct Note: Equatable {
        enum Action: String, Equatable { case installGuide, signIn, updateGuide, retry, gitGuide }
        var text: String
        var action: Action?
    }

    // MARK: Chips

    /// Who pays, as Claude Code says it. What the last run reported wins; before any run, the sign-in method.
    /// A cloud account (Bedrock, Vertex) is neither, and an unknown answer never claims "your plan".
    static func modelChip(authMethod: String?, paidBy: EngineReport.Payer?) -> String {
        if authMethod == "third_party" { return "Claude" }
        switch paidBy {
        case .plan: return "Claude · your plan"
        case .apiKey: return "Claude · API key"
        default: break
        }
        switch authMethod {
        case "claude.ai", "oauth_token": return "Claude · your plan"
        case "api_key", "api_key_helper": return "Claude · API key"
        default: return "Claude"
        }
    }

    /// "Chat only", "Read-only · notchmeow", "Agent · Mis Proyectos".
    static func levelChip(_ level: ClaudeCodeLevel) -> String {
        let words: String
        switch level {
        case .chatOnly: return "Chat only"
        case .noTools: return "No tools"
        case .readOnly: words = "Read-only"
        case .agent: words = "Agent"
        }
        guard let folder = level.folder, !folder.isEmpty else { return words }
        return "\(words) · \(folderName(folder))"
    }

    /// How Claude Code is signed in, in words: "your Claude plan", "an API key".
    static func signInWords(_ authMethod: String?) -> String {
        switch authMethod {
        case "claude.ai": "your Claude plan"
        case "oauth_token": "an OAuth token"
        case "api_key": "an API key"
        case "api_key_helper": "an API key helper"
        case "third_party": "a cloud account"
        default: "its own sign-in"
        }
    }

    /// The last part of a path, whichever separator it uses; "/" and "C:" keep their own names.
    static func folderName(_ path: String) -> String {
        var trimmed = path
        while trimmed.hasSuffix("/") || trimmed.hasSuffix("\\") { trimmed.removeLast() }
        if trimmed.isEmpty { return String(path.prefix(1)) }
        return trimmed.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? trimmed
    }

    // MARK: Failures

    /// The note for one of Claude Code's failures, or nil for any other error (`AIMessages` then decides).
    static func message(for error: AIError, timeZone: TimeZone = .current, locale: Locale = .current) -> Note? {
        switch error.code {
        case ClaudeCodeError.missing: return Note(text: "Claude Code isn't installed.", action: .installGuide)
        case ClaudeCodeError.signedOut: return Note(text: "Claude Code is signed out.", action: .signIn)
        case ClaudeCodeError.planLimit:
            return Note(text: planLimit(resetsAt: error.resetsAt, timeZone: timeZone, locale: locale), action: nil)
        case ClaudeCodeError.tooOld: return Note(text: "Update Claude Code.", action: .updateGuide)
        case ClaudeCodeError.crashed: return Note(text: "Claude stopped unexpectedly.", action: .retry)
        case ClaudeCodeError.offline: return Note(text: "Couldn't reach Claude.", action: nil)
        case ClaudeCodeError.needsGit: return Note(text: "Claude Code needs Git for Windows.", action: .gitGuide)
        case ClaudeCodeError.folderMissing:
            return Note(text: "That folder isn't there any more. Pick another one.", action: nil)
        case ClaudeCodeError.toolsPresent:
            return Note(text: "Claude Code started with tools a quick action must not have, so NotchMeow stopped it.",
                        action: nil)
        default: return nil
        }
    }

    /// "Your Claude plan's limit resets at 3:45 pm." in the viewer's time zone and locale.
    static func planLimit(resetsAt: Date?, timeZone: TimeZone, locale: Locale) -> String {
        guard let resetsAt else { return "Your Claude plan's limit was reached." }
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.locale = locale
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        // Recent macOS puts a narrow no-break space before PM: use a plain one, and lower-case "PM".
        let time = formatter.string(from: resetsAt).replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ").lowercased()
        return "Your Claude plan's limit resets at \(time)."
    }
}

#endif
