import Foundation

/// Which files the cat coughs up, and what it writes on them. The rule is the app's own refusal rule (`AttachmentRules`: apps, archives, disk images
/// and videos by extension, and anything over 25 MB), so there is one list. It is decided at the drop, from what is known then (the extension and the
/// size), instead of waiting for the AI's reader to fail at the end of the upload sequence. A file that fails for any other reason (unreadable, a copy
/// error, a folder) is not refused here: it keeps today's ending, with no hairball.
enum CatFileRule {
    /// `ext` without the dot, in any case; `size` in bytes. No bytes are needed: the rule's size and extension checks run before it reads any.
    static func refused(ext: String, size: Int) -> Bool {
        if case .failure = AttachmentRules.classify(size: size, ext: ext, head: Data()) { return true }
        return false
    }

    /// The label a refused file wears in its fur: the extension in capitals, four letters at most, FILE when it has none.
    static func label(for name: String) -> String {
        let ext = (name as NSString).pathExtension
        return String((ext.isEmpty ? "FILE" : ext).uppercased().prefix(4))
    }
}

/// Numbers the drops. `FileDropHandler.handle` takes a token with `begin()` when a drop starts, so the drop's delayed work never touches a newer
/// drop. The waits of `handle` and its tick-sound loop check `isCurrent` together with "the user has not left the drop flow" (`live()`) before they
/// write state, play a sound or post an emote. The inbox copy checks the token only, so leaving the flow does not lose the copy.
@MainActor
final class DropGeneration {
    private var latest = 0

    /// Starts a new drop: its token is the current one, and every earlier token is stale from now on.
    func begin() -> Int {
        latest += 1
        return latest
    }

    func isCurrent(_ token: Int) -> Bool { token == latest }
}
