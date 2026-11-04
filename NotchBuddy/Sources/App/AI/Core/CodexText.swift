import Foundation

// The words on the two OpenAI plan chips and what the chat says for each Codex failure.
// Fixtures: `tests/fixtures/ai/codex/labels.json` and `copy.json`; `reference.py` decides when they disagree.

#if !APPSTORE

enum CodexText {
    // MARK: Chips

    /// Who pays, from the sign-in mode `codex login status` gave. Nothing more is claimed.
    static func modelChip(mode: String?) -> String {
        switch mode {
        case "chatgpt": return "OpenAI · your plan"
        case "api_key": return "OpenAI · API key in Codex"
        default: return "OpenAI · Codex"
        }
    }

    /// "Chat only", "No tools", "No tools · notchmeow". Chat has one level and ignores a folder.
    static func levelChip(_ level: CodexLevel, folder: String?) -> String {
        switch level {
        case .chat:
            return "Chat only"
        case .noTools:
            guard let folder, !folder.isEmpty else { return "No tools" }
            return "No tools · \(ClaudeCodeText.folderName(folder))"
        }
    }

    // MARK: Words

    static let signInDetail = "Open your terminal and run `codex login`. NotchMeow opens nothing."

    /// copy.json: the text and the button's name for a Codex code, or nil for any other code. `signIn` is text only.
    static func copy(code: String, resetsAt: Date?, timeZone: TimeZone, locale: Locale) -> (text: String, action: String?)? {
        switch code {
        case "nm_codex_missing": return ("Codex isn't installed.", "installGuide")
        case "nm_codex_signed_out": return ("Codex is signed out.", "signIn")
        case "nm_plan_limit": return (planLimit(resetsAt: resetsAt, timeZone: timeZone, locale: locale), nil)
        case "nm_codex_old": return ("This version of Codex is too old for NotchMeow.", "updateGuide")
        case "nm_codex_unreadable":
            return ("NotchMeow can't read this version of the command line tool. Pick another brain.", nil)
        case "nm_codex_crashed": return ("Codex stopped unexpectedly.", "retry")
        case "nm_codex_bad_model": return ("Codex doesn't know that model.", nil)
        case "nm_bad_model": return ("That model name can't be used.", nil)
        case "nm_level_exceeded":
            return ("Codex tried to do more than this level allows, so NotchMeow stopped it.", nil)
        case "nm_level_unavailable": return ("This level isn't available with your OpenAI plan yet.", nil)
        default: return nil
        }
    }

    /// The chat's note for a Codex failure, with its one button. A signed-out note adds the sign-in line and no button.
    static func message(for error: AIError, timeZone: TimeZone = .current,
                        locale: Locale = .current) -> (text: String, action: AIAction?)? {
        guard let code = error.code,
              let words = copy(code: code, resetsAt: error.resetsAt, timeZone: timeZone, locale: locale) else { return nil }
        if words.action == "signIn" { return (words.text + " " + signInDetail, nil) }
        return (words.text, action(named: words.action))
    }

    private static func action(named name: String?) -> AIAction? {
        switch name {
        case "installGuide": return AIAction.installCodex
        case "updateGuide": return AIAction.updateCodex
        case "retry": return AIAction.tryAgain
        default: return nil
        }
    }

    /// "Your OpenAI plan's limit resets at 3:45 pm." in the viewer's time zone and locale, lower-cased.
    /// A private copy of ClaudeCodeText.planLimit's formatter, kept on purpose; the two fold together in 1.1.
    static func planLimit(resetsAt: Date?, timeZone: TimeZone, locale: Locale) -> String {
        guard let resetsAt else { return "Your OpenAI plan's limit was reached." }
        let formatter = DateFormatter()
        formatter.timeZone = timeZone
        formatter.locale = locale
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        // Recent macOS puts a narrow no-break space before PM: use a plain one, and lower-case "PM".
        let time = formatter.string(from: resetsAt).replacingOccurrences(of: "\u{202F}", with: " ")
            .replacingOccurrences(of: "\u{00A0}", with: " ").lowercased()
        return "Your OpenAI plan's limit resets at \(time)."
    }
}

#endif
