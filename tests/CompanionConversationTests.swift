import Foundation

// The stored conversations' pure rules (F3a-mac, Task 5), run through scripts/test-companion-conversations.sh: which chat rows a stored conversation
// keeps (never a sidekick status row, never an empty one), the text a stored message gives the model (its file names as lines, never a file's text),
// and the day a row shows. Nothing here touches a file, a default or the clock: the times are fixed.
@MainActor
@main
enum CompanionConversationTests {
    static func main() {
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC")!
        /// Milliseconds since 1970 at `hour` UTC on the given day.
        func ms(_ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Int {
            let date = utc.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
            return Int(date.timeIntervalSince1970 * 1000)
        }

        CT.section("the rows a stored conversation keeps")
        let rows = [
            CompanionChatRules.Row(role: "user", text: "read this", caption: nil, files: ["notes.txt"], status: false),
            CompanionChatRules.Row(role: "user", text: "what is Claude doing?", caption: nil, files: [], status: true),
            CompanionChatRules.Row(role: "assistant", text: "Idle.", caption: "From NotchMeow, on this Mac", files: [], status: true),
            CompanionChatRules.Row(role: "assistant", text: "", caption: "cloud · Claude", files: [], status: false),
            CompanionChatRules.Row(role: "assistant", text: "Hello.", caption: "cloud · Claude", files: [], status: false),
        ]
        let kept = CompanionChatRules.messages(rows)
        CT.check("status rows and empty rows are not stored", kept.count, 2)
        CT.check("the first kept row is the user's words", kept.first?.text, "read this")
        CT.check("its file names are kept (names only, here)", kept.first?.files, ["notes.txt"])
        CT.check("a row with no caption is stored with an empty one", kept.first?.caption, "")
        CT.check("the reply keeps its caption, in order", kept.last.map { "\($0.role)|\($0.caption)|\($0.text)" }, "assistant|cloud · Claude|Hello.")

        CT.section("what the model is sent for a stored message")
        let withFiles = CompanionMessage(role: "user", text: "compare these", caption: "", files: ["a.pdf", "b.txt"])
        CT.check("each file is one line, named only", CompanionChatRules.modelText(withFiles),
                 "compare these\n(file: a.pdf, not kept)\n(file: b.txt, not kept)")
        let plain = CompanionMessage(role: "assistant", text: "Done.", caption: "cloud · Claude", files: [])
        CT.check("a message with no files is its words", CompanionChatRules.modelText(plain), "Done.")

        CT.section("a stored conversation restored and saved again keeps its file names")
        let stored = [
            CompanionMessage(role: "user", text: "read these", caption: "", files: ["a.pdf", "b.txt"]),
            CompanionMessage(role: "assistant", text: "Done.", caption: "cloud · Claude", files: []),
        ]
        let back = CompanionChatRules.restored(stored)
        let rebuilt = CompanionChatRules.messages(zip(stored, back).map { message, r in
            CompanionChatRules.Row(role: r.role, text: message.text, caption: r.caption, files: r.files, status: false)
        })
        CT.check("the rebuilt record keeps the file names", rebuilt.first?.files, ["a.pdf", "b.txt"])
        CT.check("the rebuilt record keeps the captions", rebuilt.last?.caption, "cloud · Claude")
        CT.check("the stored words are kept as they are", stored.first?.text, "read these")
        CT.check("the model is sent the file lines, named only", back.first?.modelText,
                 "read these\n(file: a.pdf, not kept)\n(file: b.txt, not kept)")
        CT.check("a message with no caption restores with none", back.first?.caption, nil)

        CT.section("a conversation opens only when no reply is streaming or about to")
        CT.check("an idle chat opens a conversation", CompanionChatRules.canOpen(streaming: false, busy: false), true)
        CT.check("a streaming chat does not open one", CompanionChatRules.canOpen(streaming: true, busy: false), false)
        CT.check("a chat that is thinking (the reply has not started) does not open one", CompanionChatRules.canOpen(streaming: false, busy: true), false)

        CT.check("a chat with an error state allows opening (it is not busy)", CompanionChatRules.canOpen(streaming: false, busy: false), true)

        CT.section("after the open chat's stored copy is deleted, the rows then on screen are not saved again")
        func row(_ role: String, _ text: String, status: Bool = false) -> CompanionChatRules.Row {
            CompanionChatRules.Row(role: role, text: text, caption: role == "assistant" ? "local · x" : nil, files: [], status: status)
        }
        let oldQ = row("user", "old question"), oldA = row("assistant", "old answer")
        let shown = [oldQ, oldA, row("user", "new question"), row("assistant", "new answer")]
        let forgotten: Set<UUID> = [oldQ.id, oldA.id]
        CT.check("nothing forgotten keeps every row", CompanionChatRules.messages(shown, excluding: []).map { $0.text }, ["old question", "old answer", "new question", "new answer"])
        CT.check("the forgotten rows are left out, the newer ones kept", CompanionChatRules.messages(shown, excluding: forgotten).map { $0.text }, ["new question", "new answer"])
        CT.check("the plain call keeps everything", CompanionChatRules.messages(shown).count, 4)
        CT.check("only forgotten rows left: nothing to save", CompanionChatRules.messages([oldQ, oldA], excluding: forgotten).count, 0)
        // Delete while a reply streams, then the reply fails: the placeholder row (forgotten) is removed, and the user's next question is still saved.
        let placeholder = row("assistant", "")
        let askedWhileStreaming = row("user", "question under way")
        let atDelete: Set<UUID> = [oldQ.id, oldA.id, askedWhileStreaming.id, placeholder.id]
        let afterFailure = [oldQ, oldA, askedWhileStreaming]   // the failed reply's placeholder is gone, the rows shift
        let next = [row("user", "next question"), row("assistant", "its answer")]
        CT.check("a row removed after the delete does not make the next question skipped", CompanionChatRules.messages(afterFailure + next, excluding: atDelete).map { $0.text }, ["next question", "its answer"])
        // Delete, then Retry: the reply that was on screen goes, its new reply is saved.
        let retried = row("assistant", "retried answer")
        CT.check("after a Retry the new reply is saved", CompanionChatRules.messages([oldQ, retried], excluding: [oldQ.id, oldA.id]).map { $0.text }, ["retried answer"])
        CT.check("a sidekick status row is still never saved", CompanionChatRules.messages([row("user", "what is Claude doing?", status: true), row("user", "hi")], excluding: []).map { $0.text }, ["hi"])

        CT.section("the day a row shows")
        let now = ms(2026, 10, 26, 12)
        CT.check("the same day is Today", CompanionChatRules.dayLabel(updatedAt: ms(2026, 10, 26, 8), now: now, calendar: utc), "Today")
        CT.check("the day before is Yesterday", CompanionChatRules.dayLabel(updatedAt: ms(2026, 10, 25, 23, 59), now: now, calendar: utc), "Yesterday")
        CT.check("just after midnight is Today, not Yesterday", CompanionChatRules.dayLabel(updatedAt: ms(2026, 10, 26, 0, 1), now: ms(2026, 10, 26, 0, 30), calendar: utc), "Today")
        CT.check("an older day is its month and day", CompanionChatRules.dayLabel(updatedAt: ms(2026, 10, 23, 9), now: now, calendar: utc), "Oct 23")
        CT.check("an older month is its month and day", CompanionChatRules.dayLabel(updatedAt: ms(2026, 2, 3, 9), now: now, calendar: utc), "Feb 3")
        CT.section("a quick Explain's title comes from the bare selection")
        CT.check("one full wrapper goes", CompanionChatRules.titleSource("<text>\nfix this sentence\n</text>"), "fix this sentence")
        CT.check("a multi-line selection keeps its inner line breaks", CompanionChatRules.titleSource("<text>\na\nb\n</text>"), "a\nb")
        CT.check("a text without the wrapper is as it is", CompanionChatRules.titleSource("hello there"), "hello there")
        CT.check("a lone opening tag is as it is", CompanionChatRules.titleSource("<text>"), "<text>")
        CT.check("a wrapper with no line breaks is as it is", CompanionChatRules.titleSource("<text>abc</text>"), "<text>abc</text>")
        CT.check("an opening tag only is as it is", CompanionChatRules.titleSource("<text>\nabc"), "<text>\nabc")
        CT.check("only the outer wrapper goes", CompanionChatRules.titleSource("<text>\n<text>\nx\n</text>\n</text>"), "<text>\nx\n</text>")
        CT.check("text after the closing tag is as it is", CompanionChatRules.titleSource("<text>\nx\n</text> and more"), "<text>\nx\n</text> and more")
        CT.check("nil stays nil", CompanionChatRules.titleSource(nil), nil)

        CT.finish()
    }
}
