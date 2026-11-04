import Foundation

// The companion's turn (F3a-mac, Task 4): the parts of one turn as plain values, built on the main actor by Companion and handed to the runner as a
// Sendable value, the lines a request sends (kept in memory for the chat), and today's date. Pure Foundation, so the brain test compiles it. A file's
// text, a hook's text and a reply are data: the record of what was sent names a file and an image, and keeps no file's contents.

/// One turn's prompt, built from its input. "Right now" waits for the cloud notice: a cloud target gets it only once its provider is in `cloudNoticeShown`
/// (the list read when the turn was built).
struct CompanionTurnParts: Sendable, Equatable {
    let input: CompanionPromptInput
    let cloudNoticeShown: [String]

    init(input: CompanionPromptInput, cloudNoticeShown: [String] = []) {
        self.input = input
        self.cloudNoticeShown = cloudNoticeShown
    }

    /// The system text for one target. "Right now" is left out while the cloud notice is still due for this provider (a cloud target, See my sessions on,
    /// the provider not yet shown the line); every other target gets it as the input has it.
    func system(placement: String, provider: String) -> String {
        var i = input
        if CompanionRightNow.needsCloudNotice(placement: placement, seeSessions: i.seeSessions, provider: provider, shown: cloudNoticeShown) {
            i.rightNow = nil
        }
        return CompanionPrompt.promptOf(i)
    }
}

enum CompanionTurn {
    /// The lines of a request as the model gets them: the system text first, then each part of each message. A text part is "<role>: <text>"; a file
    /// is named by its file name and an image as "[image]", never by its contents.
    static func sentLines(_ request: ChatRequest) -> [String] {
        var lines = [request.system]
        for message in request.messages {
            let role = message.role.rawValue
            for part in message.parts {
                switch part {
                case .text(let text):
                    lines.append("\(role): \(text)")
                case .fileText(let name, _), .pdf(let name, _):
                    lines.append("\(role): [file \(name)]")
                case .image:
                    lines.append("\(role): [image]")
                }
            }
        }
        return lines
    }

    /// Today as YYYY-MM-DD in `timeZone`. The calendar is never used: the date is formatted in the POSIX locale, so no user setting changes its digits.
    static func today(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }
}
