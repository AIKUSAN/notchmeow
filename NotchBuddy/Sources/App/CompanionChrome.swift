import Foundation

// The companion chat's words (F3a-mac, Task 2): the folder control's labels and help, the line that says where the messages go, and the notes after a
// quick action or a pop-out. Plain strings in every build: the folder words take the level's key and the folder as plain values, so the words exist
// (and the test compiles) without the Claude Code engine.
enum CompanionChrome {
    static let folderRows = ["No folder", "Read a folder…", "Work in a folder…"]
    static let folderHelp = "The folder Claude may use in this chat"
    static let replaceNote = "Copied. Press ⌘V to replace the selection."
    static let poppedOutNote = "The chat is in its own window."
    static let cutNote = "Cut to the first 8,000 characters."

    /// The folder control's label: `chat` has no folder; `read` reads one and `agent` works in one, each shown with the folder's last part. With no
    /// folder (or an empty one) the words stand alone. Any other key reads as `chat`.
    static func folderLabel(levelKey: String, folder: String?) -> String {
        switch levelKey {
        case "read": return withFolder("Reads", folder)
        case "agent": return withFolder("Works in", folder)
        case "none": return "No tools"
        default: return "No folder"
        }
    }

    /// The line on the Companion tab: where the messages are sent.
    static func sentTo(_ brain: String) -> String {
        "This is sent with your messages to \(brain)."
    }

    private static func withFolder(_ words: String, _ folder: String?) -> String {
        guard let folder, !folder.isEmpty else { return words }
        return "\(words) \u{00B7} \(folderName(folder))"
    }

    /// The last part of a folder path, whichever separator it uses: trailing separators go, and a path of separators alone keeps its first character
    /// (the rule of `ClaudeCodeText.folderName`, which this file cannot import: it is part of the Claude Code engine).
    static func folderName(_ path: String) -> String {
        var trimmed = path
        while trimmed.hasSuffix("/") || trimmed.hasSuffix("\\") { trimmed.removeLast() }
        if trimmed.isEmpty { return String(path.prefix(1)) }
        return trimmed.split(whereSeparator: { $0 == "/" || $0 == "\\" }).last.map(String.init) ?? trimmed
    }
}
