import Foundation

// Source pins for the companion's turn (F3a-mac, Task 4), where no test program can compile the app's files. They say where ClaudeService reads the turn's
// parts and gives each target its own system text, that the Claude Code preamble sits inside the App Store exclusion and passes the cloud gate, that
// Companion reads one Projects view, the cat's own mood (never the chat's override) and the Main cat, and that nothing in the turn logs, starts a timer or
// keeps a file's text. Run from the repository root through scripts/test-companion-wiring.sh.

@MainActor
@main
enum CompanionWiringTests {
    static func source(_ file: String) -> String { (try? String(contentsOfFile: "NotchBuddy/Sources/App/\(file)", encoding: .utf8)) ?? "" }
    static func count(_ needle: String, in text: String) -> Int { text.components(separatedBy: needle).count - 1 }
    /// The offset of the first `needle`, or -1.
    static func at(_ needle: String, in text: String) -> Int { text.range(of: needle)?.lowerBound.utf16Offset(in: text) ?? -1 }
    /// The offset of the first `needle` at or after `from`, or -1.
    static func at(_ needle: String, in text: String, from: Int) -> Int {
        from < 0 ? -1 : text.range(of: needle, range: String.Index(utf16Offset: from, in: text)..<text.endIndex)?.lowerBound.utf16Offset(in: text) ?? -1
    }
    /// The offset of the last `needle` that starts before `before`, or -1.
    static func lastAt(_ needle: String, in text: String, before: Int) -> Int {
        guard before > 0 else { return -1 }
        let end = String.Index(utf16Offset: before, in: text)
        return text[..<end].range(of: needle, options: .backwards)?.lowerBound.utf16Offset(in: text) ?? -1
    }

    /// The brace depth at `needle` (opened minus closed braces before it, counted from the start of `text`), or -999 when it is not there.
    static func braceDepth(at needle: String, in text: String) -> Int {
        guard let r = text.range(of: needle) else { return -999 }
        return text[..<r.lowerBound].reduce(0) { $0 + ($1 == "{" ? 1 : ($1 == "}" ? -1 : 0)) }
    }

    /// The text of the method whose header is `header`, through its closing brace at four spaces.
    static func body(_ header: String, in text: String) -> String {
        guard let start = text.range(of: header) else { return "" }
        let rest = text[start.lowerBound...]
        guard let end = rest.range(of: "\n    }\n") else { return String(rest) }
        return String(rest[..<end.upperBound])
    }

    static func main() {
        let claude = source("ClaudeService.swift"), companion = source("Companion.swift"), turn = source("CompanionTurn.swift")
        CT.section("the sources were read")
        CT.checkTrue("the files are there", claude.contains("final class ClaudeService") && companion.contains("final class Companion") && turn.contains("struct CompanionTurnParts"))

        CT.section("the turn: ClaudeService reads the parts once and gives each target its own system text, and records what it sent")
        CT.check("the parts are read once per reply", count("Companion.shared.turnParts()", in: claude), 1)
        let sendNeedle = "system: firstSystem ?? parts.system(placement: CompanionRightNow.contractPlacement(for: target.placement), provider: target.provider.rawValue),"
        CT.check("the request's system text is the target's, once, with the contract's placement (fix B)", count(sendNeedle, in: claude), 1)
        CT.check("no target's raw placement word reaches the companion's gate in ClaudeService", count("placement: target.placement.rawValue", in: claude), 0)
        CT.check("no target's raw placement word reaches the companion in Companion.swift", count("target.placement.rawValue", in: companion), 0)
        let make = at("makeRequest: { target in", in: claude), built = at("notices.set(built)", in: claude)
        let system = at(sendNeedle, in: claude)
        CT.checkTrue("the system text is inside the request closure", make > 0 && system > make && system < built)
        CT.check("what a turn sent is recorded, once", count("Companion.shared.recordSent(notices.built?.request)", in: claude), 1)
        CT.check("the cloud line is asked for, once", count("Companion.shared.cloudLine(for:", in: claude), 1)
        CT.checkTrue("the prompt is no longer built in ClaudeService", !claude.contains("makeSystemPrompt") && !claude.contains("let system = systemPrompt") && !claude.contains("systemPrompt"))
        let turnAt = at("Companion.shared.turnParts()", in: claude)
        CT.checkTrue("the parts are read before the runner and before the Claude Code preamble", turnAt > 0 && turnAt < at("let runner = ChatRunner(", in: claude) && turnAt < at("Companion.claudePreambleHead", in: claude))

        CT.section("the Claude Code preamble carries the prompt, inside the App Store exclusion, and waits for its cloud notice")
        let head = at("Companion.claudePreambleHead", in: claude)
        CT.check("the preamble head is used once", count("Companion.claudePreambleHead", in: claude), 1)
        let open = lastAt("#if !APPSTORE", in: claude, before: head)
        CT.checkTrue("the preamble sits inside #if !APPSTORE", head > 0 && open >= 0 && at("#endif", in: claude, from: open) > head)
        CT.check("the preamble's prompt is gated as Claude Code (a cloud target), once", count("parts.system(placement: AIPlacement.cloud.rawValue, provider: AIProviderID.claudeCode.rawValue)", in: claude), 1)
        CT.checkTrue("the preamble is the head, the gated prompt and the recap, joined", claude.contains("Companion.claudePreambleHead + \"\\n\""))

        CT.section("Companion: the cloud notice is the one thing that holds Right now back, and the snapshot is taken with the turn")
        CT.checkTrue("the turn carries the cloud notices shown when it was built", companion.contains("cloudNoticeShown: store.settings.cloudNoticeShown"))
        CT.check("the cloud gate reads the contract's placement of the target, once", count("CompanionRightNow.needsCloudNotice(placement: CompanionRightNow.contractPlacement(for: target.placement),", in: companion), 1)
        CT.check("the notice's name is the fixed name for a custom server, once", count("CompanionRightNow.noticeName(provider: target.provider, displayName:", in: companion), 1)
        CT.check("the cloud line is recorded through the store, once", count("store.update", in: companion), 1)
        CT.checkTrue("the cloud line is recorded for the provider it was asked about", companion.contains("$0.cloudNoticeShown.append(provider)"))
        CT.check("lastSent is assigned twice: recordSent keeps it, clearSent empties it", count("lastSent =", in: companion), 2)
        CT.checkTrue("clearSent empties it", body("func clearSent()", in: companion).contains("lastSent = []"))
        CT.checkTrue("the head is the contract's words", companion.contains("static let claudePreambleHead = \"From NotchMeow, the app this chat runs in (instructions and context for you, not words of the user):\""))

        CT.section("Companion: one Projects view per turn, the quiet rule from it, Right now only while See my sessions is on")
        CT.check("the Projects view is read at most twice (turnParts, and quietNow's default)", count("ProjectsModel.shared.view()", in: companion), 2)
        CT.check("turnParts reads the Projects view once", count("let view = ProjectsModel.shared.view()", in: companion), 1)
        CT.check("turnParts passes that view to the quiet rule", count("input.quiet = quietNow(view: view)", in: companion), 1)
        CT.checkTrue("the quiet rule counts the stepped-back waits in that view", companion.contains("(view ?? ProjectsModel.shared.view()).waiting"))
        CT.checkTrue("the quiet rule also counts an approval or a question card", companion.contains("AppState.shared.pendingApproval != nil || AppState.shared.pendingQuestion != nil"))
        let gate = at("if store.settings.seeSessions", in: companion)
        CT.checkTrue("Right now is read from that view, only while See my sessions is on", gate > 0 && at("CompanionRightNow.text(view)", in: companion) > gate)
        CT.check("the sidekick's ledger is never read", count("Sidekick.shared.engine.ledger", in: companion), 0)

        CT.section("Companion: the cat's mood is its own, never the chat's override; the Main cat gives the name and traits")
        CT.checkTrue("the mood is the focused task's state, without the chat's override", companion.contains("input.mood = (AppState.shared.focusTask?.state ?? .idle).rawValue"))
        CT.check("the mood never reads baseState (it holds the chat's override)", count("AppState.shared.baseState", in: companion), 0)
        CT.check("the mood never reads stateOverride", count("stateOverride", in: companion), 0)
        CT.checkTrue("the name is the Main cat's label, and the traits are the Main cat's", companion.contains("CatPresets.all[cats.character]?.label") && companion.contains("cats.cats[cats.character]?.personality.traits"))

        CT.section("today is read in the time zone the app uses, through CompanionTurn")
        CT.check("the turn's date comes from CompanionTurn.today, the current time zone", count("CompanionTurn.today(Date(), timeZone: .current)", in: companion), 1)
        CT.checkTrue("the date's formatter is POSIX and takes the time zone it is given", turn.contains("en_US_POSIX") && turn.contains("formatter.timeZone = timeZone") && !turn.contains("Calendar"))

        CT.section("the turn logs nothing, starts no timer, and keeps no file's text")
        let forbidden = ["AILog", "appendAppLog", "print(", "NSLog", "os_log", "Logger(", "Timer", "DispatchSource", "asyncAfter", "addObserver", "NotificationCenter", "FileManager", "FileHandle"]
        for word in forbidden {
            CT.check("Companion.swift does not hold \(word)", count(word, in: companion), 0)
            CT.check("CompanionTurn.swift does not hold \(word)", count(word, in: turn), 0)
        }
        CT.checkTrue("the turn reads no file from disk", !turn.contains("contentsOf") && !companion.contains("contentsOf"))

        CT.section("conversations: the pane, the menu, the list and opening one")
        let views = source("CompanionViews.swift"), island = source("IslandViewContent.swift"), appState = source("AppState.swift")
        let pure = source("CompanionConversations.swift"), log = source("AI/Core/AILog.swift")
        CT.checkTrue("the new files are there", views.contains("struct ChatMenuButton: View") && views.contains("struct ConversationListPane: View"))
        CT.checkTrue("the pure rules are in their own file, with no SwiftUI or AppKit", pure.contains("enum CompanionChatRules") && !pure.contains("import SwiftUI") && !pure.contains("import AppKit"))
        CT.checkTrue("AppState holds the chat's pane", appState.contains("enum ChatPane: Equatable { case chat, conversations }") && appState.contains("@Published var chatPane: ChatPane = .chat"))
        CT.check("a new chat's first message makes the stored conversation's id, once", count("if conversationID == nil { conversationID = Companion.shared.store.newConversationId() }", in: claude), 1)
        CT.checkTrue("clearing the chat forgets the conversation id", body("func clearConversation(state: AppState)", in: claude).contains("conversationID = nil"))
        let forgetOne = body("func forgetStored(id: String)", in: claude), forgetAll = body("func forgetAllStored()", in: claude)
        CT.checkTrue("deleting the chat's own stored conversation forgets its id, and marks the rows on screen as not to be saved again", forgetOne.contains("guard conversationID == id else { return }") && forgetOne.contains("conversationID = nil") && forgetOne.contains("forgottenRows = Set(AppState.shared.chatHistory.map(\\.id))"))
        CT.checkTrue("deleting every stored conversation forgets the id, marks the rows, and empties What the AI saw last", forgetAll.contains("conversationID = nil") && forgetAll.contains("forgottenRows = Set(AppState.shared.chatHistory.map(\\.id))") && forgetAll.contains("Companion.shared.clearSent()"))
        CT.checkTrue("a cleared chat saves from its first row again", body("func clearConversation(state: AppState)", in: claude).contains("forgottenRows = []"))
        let storeBody = body("func storeCurrent(state: AppState)", in: claude)
        CT.checkTrue("a save keeps only the rows after the deletion, and writes nothing when none is newer", storeBody.contains("CompanionChatRules.messages(rows, excluding: forgottenRows)") && storeBody.contains("if !forgottenRows.isEmpty, messages.isEmpty { return }") && storeBody.contains("CompanionChatRules.Row(id: m.id,"))
        CT.check("forgottenRows is declared once, as ids and not as a position", count("private var forgottenRows: Set<UUID> = []", in: claude), 1)
        CT.check("no row position is kept", count("savedFrom", in: claude), 0)
        CT.check("storeCurrent is declared once", count("func storeCurrent(state: AppState)", in: claude), 1)
        CT.check("finish stores the chat once", count("storeCurrent(state: state)", in: claude), 1)
        let fin = at("private func finish(", in: claude), storeAt = at("storeCurrent(state: state)", in: claude)
        let interruptedAt = at("state.chatHistory[i].interrupted = result.outcome == .interrupted", in: claude)
        let startCount = at("private func startCountdown(", in: claude)
        CT.checkTrue("the store call is in finish, after the reply's content and interruption are set", fin > 0 && storeAt > interruptedAt && storeAt > fin && storeAt < startCount)
        CT.check("the reply's user row keeps its file names, once", count("state.chatHistory[u].files = ", in: claude), 1)
        CT.checkTrue("a failed save is never swallowed by try?", claude.contains("try store.save(record)") && count("try? store.save", in: claude) == 0)
        let svAt = at("func storeCurrent(state: AppState)", in: claude), svEnd = at("func open(conversationID", in: claude)
        let leak = at("localizedDescription", in: claude, from: svAt)
        CT.checkTrue("the save notice is a fixed sentence, with no error text", claude.contains("This conversation could not be saved.") && svAt > 0 && (leak == -1 || leak > svEnd))
        CT.check("a failed save is logged by its kind only, once", count("AILog.record(.companionSaveFailed)", in: claude), 1)
        CT.checkTrue("the log has the kind and no text", log.contains("case companionSaveFailed") && log.contains("\"companion save failed\""))

        let openAt = at("func open(conversationID id: String, state: AppState)", in: claude)
        let openBody = body("func open(conversationID id: String, state: AppState)", in: claude)
        let clearRange = openBody.range(of: "clearConversation(state: state)")
        let beforeClear = clearRange.map { String(openBody[..<$0.lowerBound]) } ?? ""
        CT.checkTrue("open reads the stored conversation, and leaves the chat as it is when it is gone", openAt > 0 && clearRange != nil && beforeClear.contains("guard let stored = Companion.shared.store.conversation(id: id) else { return }"))
        CT.checkTrue("nothing of the chat is touched before the clear", clearRange != nil && !beforeClear.contains("conversation.addUser") && !beforeClear.contains("state.chatHistory") && !beforeClear.contains("conversationID =") && !beforeClear.contains("claudeRecap"))
        CT.check("the clear is called once in open", count("clearConversation(state: state)", in: openBody), 1)
        CT.checkTrue("the restored user rows keep their file names, and their stored words are what is shown", openBody.contains("ChatMessage(role: .user, content: m.text, files: r.files)"))
        let guardAt = at("guard CompanionChatRules.canOpen(streaming: state.chatStreaming, busy: state.stateOverride == .thinking) else { return }", in: openBody)
        let readInOpen = at("Companion.shared.store.conversation(id:", in: openBody)
        CT.checkTrue("open refuses while a reply streams, before it reads the store", guardAt >= 0 && readInOpen > guardAt)
        CT.checkTrue("the row's open is dimmed and does nothing while a reply streams", views.contains("guard CompanionChatRules.canOpen(streaming: state.chatStreaming, busy: state.stateOverride == .thinking) else { return }") && views.contains(".opacity(state.chatStreaming ? 0.5 : 1)"))
        CT.checkTrue("the pane says why, only while a reply streams", views.contains("if state.chatStreaming {\n") && views.contains("Wait for the reply to finish to open a conversation."))
        let recapAt = at("ClaudeCodeRecap.text(turns: conversation.turns", in: claude, from: openAt)
        CT.checkTrue("under #if !APPSTORE, the restored turns are the recap", recapAt > openAt && lastAt("#if !APPSTORE", in: claude, before: recapAt) > openAt && at("#endif", in: claude, from: recapAt) > recapAt)

        let sw = at("switch state.chatPane {", in: island)
        CT.checkTrue("PromptView switches on the pane, both cases", sw > 0 && island.contains("case .chat:") && island.contains("case .conversations:"))
        let inputAt = at("                HStack(spacing: 8) {\n                    TextField(state.chatHistory.isEmpty", in: island)
        let closeAt = at("                    .frame(maxHeight: .infinity)\n                }\n\n                HStack(spacing: 0) {", in: island)
        CT.checkTrue("the input row is after the switch's closing brace, outside every pane", sw > 0 && closeAt > sw && inputAt > closeAt)
        CT.checkTrue("the chat menu sits left of the Folder control", at("ChatMenuButton(state: state", in: island) > 0
            && at("ChatMenuButton(state: state", in: island) < at("ClaudeLevelChip(state: state)", in: island))
        CT.check("the Folder control is still there, once", count("ClaudeLevelChip(state: state)", in: island), 1)
        CT.checkTrue("⌘K (and the menu's New chat) runs the one New chat function, which shows the chat pane", island.contains("            newConversation()\n        }") && island.contains("private func newConversation() {"))
        CT.check("the menu's New chat is the same function as ⌘K", count("newChat: newConversation", in: island), 1)
        let sendBody = body("private func sendMessage()", in: island), newBody = body("private func newConversation()", in: island)
        CT.checkTrue("a message sent from the list shows the chat", sendBody.contains("state.chatPane = .chat") && sendBody.contains("ClaudeService.shared.send("))
        CT.checkTrue("⌘K and the menu's New chat show the chat pane", newBody.contains("state.chatPane = .chat"))
        let iwc = source("IslandWindowController.swift")
        let setModeBody = body("func setMode(_ mode: IslandMode)", in: iwc)
        CT.checkTrue("leaving the expanded island shows the chat again (the collapse path)", setModeBody.contains("if prev == .expanded {\n            SoundEngine.shared.play(\"close\")\n            state.chatPane = .chat"))

        CT.check("the list's delete-all is behind one confirmationDialog", count("confirmationDialog(", in: views), 1)
        CT.check("delete all removes every file through the store, once", count("store.deleteAll()", in: views), 1)
        CT.check("delete all forgets the chat's stored id only when every file went, once", count("if store.deleteAll() == 0 { ClaudeService.shared.forgetAllStored() }", in: views), 1)
        CT.check("a row's delete forgets the chat's stored id only when its file went, once", count("if store.delete(id: conversation.id) == 0 { ClaudeService.shared.forgetStored(id: conversation.id) }", in: views), 1)
        CT.check("Settings' Delete all forgets the chat's stored id only when every file went, once", count("if companionStore.deleteAll() == 0 { ClaudeService.shared.forgetAllStored() }", in: source("SettingsView.swift")), 1)
        CT.check("a delete never forgets before the store has answered", count("forgetAllStored(); ", in: views) + count("forgetStored(id: conversation.id); ", in: views) + count("forgetAllStored(); ", in: source("SettingsView.swift")), 0)
        CT.checkTrue("only a thinking chat is busy: an error state does not block Open", !claude.contains("busy: state.stateOverride != nil") && !views.contains("busy: state.stateOverride != nil"))
        CT.check("a rename is written through the store", count("store.rename(id:", in: views), 1)
        CT.check("opening a conversation goes through ClaudeService, and returns to the chat", count("ClaudeService.shared.open(conversationID:", in: views), 1)
        for word in ["Timer", "asyncAfter", "DispatchSource", "addObserver", "NotificationCenter", "FileManager", "contentsOf", "try?"] {
            CT.check("CompanionViews.swift does not hold \(word)", count(word, in: views), 0)
        }
        CT.section("one chat: the heights, the Folder control, the picker row and the stores")
        let rootView = source("IslandRootView.swift"), botCanvas = source("BotCanvasView.swift"), desktopCat = source("DesktopCatController.swift")
        let sidekickDrop = source("SidekickDropApp.swift"), windowCtl = source("IslandWindowController.swift"), chatViews = source("ClaudeChatViews.swift")
        let settingsCtl = source("SettingsController.swift")
        for (name, text) in [("IslandRootView.swift", rootView), ("BotCanvasView.swift", botCanvas), ("DesktopCatController.swift", desktopCat),
                             ("SidekickDropApp.swift", sidekickDrop), ("IslandWindowController.swift", windowCtl)] {
            CT.check("\(name) has no min(300 (the chat's height is ChatSizing's)", count("min(300", in: text), 0)
        }
        let heightCall = "ChatSizing.islandHeight(messages:"
        CT.check("IslandRootView's chat height is ChatSizing's, once", count(heightCall, in: rootView), 1)
        CT.check("BotCanvasView's chat height is ChatSizing's, once", count(heightCall, in: botCanvas), 1)
        CT.check("DesktopCatController's chat height is ChatSizing's, once", count(heightCall, in: desktopCat), 1)
        CT.check("SidekickDropApp's chat height is ChatSizing's, once", count(heightCall, in: sidekickDrop), 1)
        CT.check("IslandWindowController's chat height is ChatSizing's, twice (the panel and the frame)", count(heightCall, in: windowCtl), 2)
        CT.checkTrue("the unused base and perMsg lets are gone", !rootView.contains("let perMsg") && !windowCtl.contains("let perMsg") && !windowCtl.contains("let base"))
        CT.check("the Folder control reads the folder label, once", count("CompanionChrome.folderLabel(", in: chatViews), 1)
        CT.check("the Folder control no longer reads the Claude Code level chip", count("ClaudeCodeText.levelChip(", in: chatViews), 0)
        CT.check("the Folder control's accessibility label is the folder help, once", count(".accessibilityLabel(CompanionChrome.folderHelp)", in: chatViews), 1)
        for i in 0...2 { CT.check("the level menu's row \(i) reads the folder rows", count("CompanionChrome.folderRows[\(i)]", in: chatViews), 1) }
        CT.check("the picker's Claude row reads Claude · your plan, once", count("\"Claude · your plan\"", in: island), 1)
        CT.check("the picker writes the chat's choice through the store, once", count("state.setChoice(setting, for: feature)", in: island), 1)
        CT.check("Settings writes the chat's choice through the same store, once", count("state.setChoice(setting, for: .chat)", in: settingsCtl), 1)
        CT.check("Make main and Stop using go through afterStoppingClaude, once", count("SettingsAI.afterStoppingClaude(state.choice(for: .chat))", in: settingsCtl), 1)
        CT.section("pop out: one window, one shared state, one chat view at a time")
        let popOut = source("CompanionWindow.swift"), promptView = body("struct PromptView: View {", in: island)
        CT.checkTrue("the controller is a main-actor NSWindowController and window delegate",
                     popOut.contains("@MainActor\nfinal class CompanionWindowController: NSWindowController, NSWindowDelegate") && popOut.contains("static let shared = CompanionWindowController()"))
        CT.check("exactly one NSWindow( is made", count("NSWindow(", in: popOut), 1)
        CT.checkTrue("it is a plain titled window, named Chat",
                     popOut.contains("styleMask: [.titled, .closable, .resizable, .miniaturizable]") && popOut.contains("window.title = \"Chat\""))
        CT.checkTrue("it is 520 x 640 and no smaller than 420 x 360", popOut.contains("width: 520, height: 640") && popOut.contains("window.contentMinSize = NSSize(width: 420, height: 360)"))
        CT.check("its frame is remembered, once", count("setFrameAutosaveName(\"NotchMeowChat\")", in: popOut), 1)
        CT.check("closing does not release it, once", count("isReleasedWhenClosed = false", in: popOut), 1)
        CT.check("it hosts the one PromptView, on the app's shared state, in the window layout, once", count("NSHostingView(rootView: PromptView(state: .shared, inWindow: true))", in: popOut), 1)
        CT.check("there is no second AppState", count("AppState(", in: popOut), 0)
        for word in ["Timer", "asyncAfter", "DispatchSource", "addObserver", "DispatchQueue", "Task.sleep", "AILog", "appendAppLog", "print(", "NSLog", "UserDefaults"] {
            CT.check("CompanionWindow.swift does not hold \(word)", count(word, in: popOut), 0)
        }
        let popOutBody = body("func popOut()", in: popOut), backBody = body("func bringBack()", in: popOut), willClose = body("func windowWillClose(_ notification: Notification)", in: popOut)
        CT.checkTrue("popOut marks the chat popped out, folds the island, activates the app and shows the window",
                     popOutBody.contains("AppState.shared.chatPoppedOut = true") && popOutBody.contains("NotificationCenter.default.post(name: .islandCollapse, object: nil)")
                     && popOutBody.contains("NSApp.activate()") && popOutBody.contains("makeKeyAndOrderFront(nil)"))
        CT.checkTrue("popOut on an open window brings it forward (a minimized one comes back)", popOutBody.contains("window.deminiaturize(nil)"))
        CT.checkTrue("bringBack closes the window", backBody.contains("window?.close()"))
        CT.checkTrue("windowWillClose says the chat is back in the island", willClose.contains("AppState.shared.chatPoppedOut = false"))
        CT.checkTrue("AppState holds the flag, off at launch", appState.contains("@Published var chatPoppedOut = false"))
        CT.check("the island's .prompt case reads the flag, once", count("case .prompt:    if state.chatPoppedOut { PoppedOutNote(state: state) } else { PromptView(state: state) }", in: island), 1)
        CT.check("the island makes its PromptView in that one place only", count("PromptView(state: state", in: island), 1)
        CT.checkTrue("PromptView has the window layout switch, off by default", promptView.contains("var inWindow = false"))
        CT.checkTrue("in the window the cat's 84-point gutter is 16, and the card wash is not drawn",
                     promptView.contains(".padding(.leading, inWindow ? 16 : 84)") && promptView.contains("if inWindow { Color(hex: \"#141518\") } else { CardBackground(wash: .indigo) }"))
        CT.check("isLive is defined once, as inWindow == state.chatPoppedOut", count("private var isLive: Bool { inWindow == state.chatPoppedOut }", in: promptView), 1)
        CT.checkTrue("isLive gates the model-picker and focus onChange blocks", promptView.contains("if open, isLive {") && promptView.contains("if !streaming, isLive { focused = true }"))
        CT.check("isLive guards both island notifications, so one chat view answers", count("guard isLive, state.view == .prompt else { return }", in: promptView), 2)
        CT.checkTrue("no view reacts to the notifications unguarded", !promptView.contains("guard state.view == .prompt else { return }") && !promptView.contains("!inWindow"))
        CT.checkTrue("the window has ⌘K and ⌘W of its own", promptView.contains(".keyboardShortcut(\"k\", modifiers: .command)") && promptView.contains(".keyboardShortcut(\"w\", modifiers: .command)"))
        CT.checkTrue("the chat menu knows the window it is in", promptView.contains("ChatMenuButton(state: state, newChat: newConversation, inWindow: inWindow, fieldText: text)"))
        CT.check("Pop out is the controller's popOut: the menu's item and the note's button, twice", count("CompanionWindowController.shared.popOut()", in: views), 2)   // the menu's item and the note's button
        CT.check("bringBack is called by the window menu's item and the note's button, twice", count("CompanionWindowController.shared.bringBack()", in: views), 2)
        CT.checkTrue("in the window the menu offers Bring back to the island, not Pop out",
                     views.contains("if inWindow {\n                Button(\"Bring back to the island\") { CompanionWindowController.shared.bringBack() }\n            } else {\n                Button(\"Pop out\") { CompanionWindowController.shared.popOut() }")
                     && views.contains("var inWindow = false"))
        let note = body("struct PoppedOutNote: View {", in: views)
        CT.checkTrue("the island's note says where the chat is and offers both ways", note.contains("CompanionChrome.poppedOutNote") && note.contains("PrimaryButton(\"Show the window\")") && note.contains("SecondaryButton(\"Bring it back\")"))

        CT.section("quick actions: the Services, the field and the clipboard, the screenshot")
        let services = source("CompanionServices.swift"), quickRun = source("CompanionQuickRun.swift"), pureQuick = source("CompanionQuickState.swift")
        let delegate = source("AppDelegate.swift")
        func file(_ path: String) -> String { (try? String(contentsOfFile: path, encoding: .utf8)) ?? "" }
        let yml = file("NotchBuddy/project.yml"), plistMac = file("NotchBuddy/Resources/Info.plist"), plistStore = file("NotchBuddy/Resources/InfoAppStore.plist")
        CT.checkTrue("the new files are there", services.contains("final class CompanionServicesProvider: NSObject") && quickRun.contains("extension Companion") && pureQuick.contains("struct QuickResult: Equatable"))
        for message in ["companionFix", "companionRewrite", "companionExplain"] {
            CT.check("project.yml holds \(message) twice (the two targets)", count(message, in: yml), 2)
            CT.check("Info.plist holds \(message) once", count("<string>\(message)</string>", in: plistMac), 1)
            CT.check("InfoAppStore.plist holds \(message) once", count("<string>\(message)</string>", in: plistStore), 1)
            CT.check("the provider declares \(message) with the Services signature, once", count("@objc func \(message)(_ pboard: NSPasteboard, userData: String?, error: AutoreleasingUnsafeMutablePointer<NSString?>)", in: services), 1)
        }
        CT.check("project.yml asks for no return types: the source app is never touched", count("NSReturnTypes", in: yml), 0)
        CT.check("Info.plist asks for no return types", count("NSReturnTypes", in: plistMac), 0)
        CT.check("InfoAppStore.plist asks for no return types", count("NSReturnTypes", in: plistStore), 0)
        CT.check("both targets send plain text, in each of three items", count("public.utf8-plain-text", in: yml), 6)
        CT.check("both targets name the legacy string type, in each of three items", count("NSStringPboardType", in: yml), 6)
        CT.check("both targets name the app's port, in each of three items", count("NSPortName: NotchMeow", in: yml), 6)
        for (kind, label) in [("fix", "Fix with NotchMeow"), ("rewrite", "Rewrite with NotchMeow"), ("explain", "Explain with NotchMeow")] {
            CT.check("the \(kind) menu item reads \"\(label)\" in both targets", count("default: \(label)", in: yml), 2)
        }
        CT.checkTrue("the menu words are CompanionQuick's labels", source("CompanionQuick.swift").contains("\"fix\": \"Fix with NotchMeow\"") && source("CompanionQuick.swift").contains("\"explain\": \"Explain with NotchMeow\""))
        CT.check("the provider reads the selection from the pasteboard's string in one place (the three messages share it)", count("pboard.string(forType: .string)", in: services), 1)
        CT.check("the source app is the frontmost app's process id, once", count("NSWorkspace.shared.frontmostApplication?.processIdentifier", in: services), 1)
        CT.checkTrue("the provider returns at once: no await", !services.contains("await"))
        CT.checkTrue("the provider hands the work to the companion on the main actor, without waiting", services.contains("Task { @MainActor in") && services.contains("Companion.shared.quick("))
        let setAt = at("NSApp.servicesProvider = CompanionServicesProvider()", in: delegate)
        CT.check("the app sets its Services provider once", count("NSApp.servicesProvider = CompanionServicesProvider()", in: delegate), 1)
        CT.check("the app refreshes the Services list once", count("NSUpdateDynamicServices()", in: delegate), 1)
        CT.checkTrue("both come right after the AI service starts", at("AIService.shared.start()", in: delegate) > 0 && setAt > at("AIService.shared.start()", in: delegate) && at("NSUpdateDynamicServices()", in: delegate) > setAt)
        let companionFiles = ((try? FileManager.default.contentsOfDirectory(atPath: "NotchBuddy/Sources/App")) ?? []).filter { $0.hasPrefix("Companion") && $0.hasSuffix(".swift") }
        CT.checkTrue("the companion's files were found", companionFiles.count >= 10)
        for name in companionFiles {
            let text = source(name)
            for word in ["CGEvent", "AXUIElement", "AXIsProcessTrusted", "NSReturnTypes", "CGEventPost", "NSAppleScript", "osascript"] {
                CT.check("\(name) does not hold \(word) (no posting, no Accessibility)", count(word, in: text), 0)
            }
        }
        CT.checkTrue("Services tell the OS when nothing is selected, in the fixed words, and start nothing", count("error.pointee = CompanionQuickRules.noSelectionNote as NSString", in: services) == 1 && services.contains("return") && count("start(\"", in: services) == 3)
        CT.check("the three service methods pass the OS's error out-parameter on", count(", error: error)", in: services), 3)
        for (name, text) in [("CompanionServices.swift", services), ("CompanionQuickRun.swift", quickRun), ("CompanionQuickState.swift", pureQuick)] {
            for word in ["AILog", "appendAppLog", "print(", "NSLog", "os_log", "Logger(", "Timer", "DispatchSource", "asyncAfter", "addObserver", "changeCount", "FileManager", "UserDefaults"] {
                CT.check("\(name) does not hold \(word) (nothing logged, watched or polled)", count(word, in: text), 0)
            }
        }
        CT.checkTrue("the pure state is Foundation only", !pureQuick.contains("import SwiftUI") && !pureQuick.contains("import AppKit"))

        CT.section("quick actions: ClaudeService runs one turn that touches neither the chat nor the conversation")
        let quickBody = body("func quickReply(_ request: CompanionQuickRequest, image: PreparedFile?) async -> (text: String?, error: AIError?, target: ChatTarget?)", in: claude)
        CT.check("quickReply is declared once", count("func quickReply(_ request: CompanionQuickRequest, image: PreparedFile?) async", in: claude), 1)
        CT.checkTrue("quickReply was found", quickBody.contains("ChatRunner(") && quickBody.count > 400)
        CT.checkTrue("quickReply never reads or writes the chat's history", !quickBody.contains("chatHistory"))
        CT.checkTrue("quickReply never touches the model's conversation or the chat's own session", !quickBody.contains("conversation") && !quickBody.contains("claudeSession") && !quickBody.contains("replyTask"))
        CT.checkTrue("quickReply sends the quick request's own system text and user text", quickBody.contains("system: request.system") && quickBody.contains(".text(request.user)"))
        CT.checkTrue("quickReply records what it sent for the chat's What the AI saw", quickBody.contains("Companion.shared.recordSent(box.built?.request)"))
        CT.check("what was sent is recorded by the turn and by the quick run", count("Companion.shared.recordSent(", in: claude), 2)
        CT.check("the Claude plan's quick session is a fresh one, once", count("ClaudeChatSession()", in: claude), 2)
        let freshAt = at("ClaudeChatSession()", in: quickBody)
        let openIf = lastAt("#if !APPSTORE", in: quickBody, before: freshAt)
        CT.checkTrue("the Claude quick path sits inside #if !APPSTORE", freshAt > 0 && openIf >= 0 && at("#endif", in: quickBody, from: openIf) > freshAt)
        CT.checkTrue("it runs with no tools, with the quick system text as the preamble", quickBody.contains("session.level = .noTools") && quickBody.contains("preamble: request.system") && !quickBody.contains(".agent") && !quickBody.contains(".readOnly") && !quickBody.contains("claudeLevel"))
        CT.checkTrue("its session is known to the hook router while it runs", claude.contains("var liveClaudeSessions: Set<String> { quickClaudeSessions.union([claudeSession.sessionID]) }") && quickBody.contains("quickClaudeSessions.insert("))
        CT.checkTrue("a quick session id is never taken out again (a late hook event is still the chat's), and the set is capped", !claude.contains("quickClaudeSessions.remove(") && quickBody.contains("if quickClaudeSessions.count >= Self.quickSessionsMax { quickClaudeSessions.removeAll() }") && claude.contains("static let quickSessionsMax = 64") && !quickBody.contains("defer"))
        CT.checkTrue("a quick reply cut at the model's limit is a failure, not a result to paste", quickBody.contains("result.finish == .length") && quickBody.contains("AIMessages.cutOff"))
        let quickDoc = String(claude[..<claude.range(of: "func quickReply(")!.lowerBound].suffix(1200))
        CT.checkTrue("quickReply's doc says it is a fresh session at no tools, and that Explain's follow-ups stay at no tools until the user picks a level", quickDoc.contains("a fresh session at no tools") && quickDoc.contains("follow-up turns of that chat stay at no tools until the user picks a level"))
        let explainBody = body("func explain(request: CompanionQuickRequest, image: PreparedFile?, state: AppState)", in: claude)
        CT.check("explain is declared once", count("func explain(request: CompanionQuickRequest, image: PreparedFile?, state: AppState)", in: claude), 1)
        let clearAt = at("clearConversation(state: state)", in: explainBody)
        CT.checkTrue("explain starts a new chat first, then keeps the quick system text for that turn only", clearAt >= 0 && at("quickFirst = QuickFirstTurn(system: request.system, user: request.user)", in: explainBody, from: clearAt) > clearAt)
        CT.checkTrue("explain attaches the image to the turn", explainBody.contains("conversation.attach(image)"))
        CT.checkTrue("explain's first message is the request's user text, started like any message", explainBody.contains("state.chatHistory.append(ChatMessage(role: .user, content: request.user))") && explainBody.contains("replyTask = Task { await chat(query: request.user, context: nil, state: state) }"))
        CT.check("the turn takes the quick system text through the pure rule, once", count("quickFirst?.system(forQuery: query, turnCount: conversation.turns.count)", in: claude), 1)
        let sendFn = body("func send(query: String, context: PromptContext?, state: AppState)", in: claude)
        CT.check("a new chat and an ordinary send forget the quick system text (twice: clear, send)", count("quickFirst = nil", in: claude), 2)
        CT.checkTrue("send forgets it after the sidekick's answer and before the message is added", at("quickFirst = nil", in: sendFn) > at("SidekickChat.answer(query, state: state)", in: sendFn) && at("quickFirst = nil", in: sendFn) < at("ChatMessage(role: .user", in: sendFn))
        CT.checkTrue("the clear in clearConversation is the other one", body("func clearConversation(state: AppState)", in: claude).contains("quickFirst = nil"))
        CT.checkTrue("explain never goes through send, and sets the quick turn after its clear", !explainBody.contains("send(") && at("quickFirst = QuickFirstTurn(", in: explainBody) > at("clearConversation(state: state)", in: explainBody))
        let resendFn = body("func resendLastMessage(state: AppState)", in: claude)
        CT.checkTrue("Try again keeps a failed quick first turn: it saves the turn before send and puts it back after", at("let quick = quickFirst", in: resendFn) > 0 && at("send(query: text", in: resendFn) > at("let quick = quickFirst", in: resendFn) && at("quickFirst = quick", in: resendFn) > at("send(query: text", in: resendFn))
        CT.checkTrue("the quick turn's comment says it runs with no tools, and why (its text is untrusted), and does not say no folder and no tools", claude.contains("with no tools, because its text is untrusted") && !claude.contains("no folder and no tools"))
        CT.checkTrue("the quick system text replaces the companion's prompt in the request and in the Claude preamble", claude.contains("system: firstSystem ?? parts.system(placement: CompanionRightNow.contractPlacement(for: target.placement), provider: target.provider.rawValue),") && claude.contains("(firstSystem ?? parts.system(placement: AIPlacement.cloud.rawValue, provider: AIProviderID.claudeCode.rawValue))"))
        CT.check("the pending image is the first pending attachment that is an image, once", count("var pendingImage: PreparedFile?", in: claude), 1)

        CT.section("quick Explain's first turn runs at no tools, web search off for API brains (agent safety: a selection is untrusted data)")
        let replyFull = String(claude[claude.range(of: "private func reply(query: String")!.lowerBound...].prefix(9000))
        CT.checkTrue("reply found", replyFull.contains("quickFirst?.system(forQuery: query") && replyFull.contains("claudeSession.level"))
        CT.check("the Claude session's level is set once per turn", count("claudeSession.level = ", in: claude), 1)
        CT.checkTrue("chat() notes the generation before it waits for an attachment and drops itself when the chat was reset meanwhile", body("func chat(query: String, context: PromptContext?, state: AppState, retries: Int = 0) async", in: claude).contains("let generation = conversationGeneration\n        await preparation?.value\n        guard generation == conversationGeneration else { return }"))

        CT.section("the Claude plan's conduct line: Read-only and Agent are told their tools are theirs")
        let toolsLine = "static let claudeToolsLine = \"In this chat you may use the tools Claude Code gives you in the folder the user chose; the sentence above about not acting on the Mac is about NotchMeow itself, not about your tools.\""
        CT.check("Companion holds the fixed line, once", count(toolsLine, in: companion), 1)
        CT.checkTrue("the line sits inside #if !APPSTORE in Companion.swift", at(toolsLine, in: companion) > 0 && lastAt("#if !APPSTORE", in: companion, before: at(toolsLine, in: companion)) >= 0 && at("#endif", in: companion, from: at(toolsLine, in: companion)) > at(toolsLine, in: companion))
        CT.check("ClaudeService adds it once, to the Claude preamble only", count("Companion.claudeToolsLine", in: claude), 1)
        CT.checkTrue("it follows the prompt and comes before the recap, and only at Read-only and Agent, on every turn (resumed ones too)", claude.contains("(next.turn.level == .chatOnly || next.turn.level == .noTools) ? nil : Companion.claudeToolsLine,\n                                                 next.turn.resume ? nil : claudeRecap]") && at("Companion.claudeToolsLine", in: claude) > at("Companion.claudePreambleHead", in: claude))
        CT.checkTrue("the quick first turn and a held chat run the Claude plan at no tools; every other turn at the user's level", claude.contains("claudeSession.level = ClaudeQuickHold.level(held: firstSystem != nil || state.claudeQuickHold, chosen: state.claudeLevel)"))
        CT.checkTrue("the quick first turn never turns on a brain's web search", claude.contains("webSearch: firstSystem == nil && (target.provider == .anthropic || target.provider == .openai)"))
        CT.check("web search is decided in one place", count("webSearch:", in: replyFull), 1)
        CT.section("quick actions: titles, the card on a screenshot that cannot be read, and the chip's redraw")
        CT.checkTrue("the stored title comes from the bare selection (the wrapper stays in the text)", claude.contains("CompanionRecords.titleOf(CompanionChatRules.titleSource(messages.first { $0.role == \"user\" }?.text))"))
        CT.checkTrue("a user bubble shows the bare selection, not the <text> wrapper the model gets", island.contains("Text(CompanionChatRules.titleSource(message.content) ?? message.content)"))
        let clipBody = body("func quickClipboardImage()", in: quickRun)
        let beginAt = at("quickGate.begin()", in: clipBody)
        CT.checkTrue("a screenshot question clears an older Fix/Rewrite card as soon as it overtakes it", beginAt >= 0 && at("AppState.shared.quickResult = nil", in: clipBody, from: beginAt) > beginAt)
        let prep = body("func prepareAttachment(url: URL, state: AppState)", in: claude)
        let attachAt = at("self.conversation.attach(file)", in: prep), lineAt = at("state.dropReaderLine = AIMessages.dropReader(", in: prep, from: attachAt)
        CT.checkTrue("the chip redraws when a file is attached: the published reader line is set right after the attach", attachAt > 0 && lineAt > attachAt)
        CT.checkTrue("dropReaderLine is published", appState.contains("@Published var dropReaderLine: String? = nil"))

        CT.section("quick actions: the run, the card, the menu and the chip")
        let quickMethod = body("func quick(kind: String, text: String?, image: PreparedFile? = nil, sourcePID: pid_t?, fromClipboard: Bool = false)", in: quickRun)
        CT.check("Companion.quick is declared once", count("func quick(kind: String, text: String?, image: PreparedFile? = nil, sourcePID: pid_t?, fromClipboard: Bool = false)", in: quickRun), 1)
        CT.checkTrue("quick builds the request through CompanionQuick.request, and does nothing when there is none", quickRun.contains("CompanionQuick.request(kind: kind, text: text)") && quickRun.contains("else { return }"))
        CT.checkTrue("an image question to a model that cannot see shows CompanionQuick.noVision and sends nothing", quickRun.contains("CompanionQuick.noVision") && count("CompanionQuick.noVision", in: quickRun) == 1 && quickRun.contains(".details("))
        CT.checkTrue("the island opens on the chat through the existing expand request", quickRun.contains("NotificationCenter.default.post(name: .hookExpand, object: IslandView.prompt)"))
        CT.check("only the existing hookExpand is posted", count("NotificationCenter.default.post(", in: quickRun), 1)
        CT.checkTrue("a popped-out chat is brought forward instead", quickRun.contains("CompanionWindowController.shared.popOut()"))
        CT.checkTrue("fix and rewrite make a running card, ask for one reply, clean it, and ignore a stale one", quickRun.contains("QuickResult.started(kind:") && quickRun.contains("ClaudeService.shared.quickReply(") && quickRun.contains("CompanionQuick.resultClean(kind: kind, reply: reply)") && quickRun.contains("quickGate.isCurrent("))
        CT.checkTrue("a failure sets the note from the shared error words", quickRun.contains("AIMessages.error(") && quickRun.contains(".failed("))
        CT.checkTrue("a new run cancels the earlier one", quickRun.contains("quickTask?.cancel()"))
        CT.check("explain and the screenshot go through ClaudeService.explain, once", count("ClaudeService.shared.explain(request:", in: quickRun), 1)
        CT.check("the clipboard image is read through the system and re-encoded, once", count("static func preparedImage(", in: quickRun), 1)
        CT.checkTrue("the clipboard's image is cut to a safe size", quickRun.contains("kCGImageSourceThumbnailMaxPixelSize") && quickRun.contains("AICatalog.Limits.maxFileBytes"))
        CT.checkTrue("AppState holds the card's state", appState.contains("@Published var quickResult: QuickResult? = nil"))
        let card = body("struct QuickResultCard: View {", in: views)
        CT.checkTrue("the card was found", card.contains("result.heading") && card.contains("textSelection(.enabled)"))
        CT.checkTrue("the card shows the text as plain text, never as Markdown", card.contains("Text(verbatim: result.text)"))
        CT.checkTrue("the result's scroll has a real minimum height, so a short chat never collapses it", card.contains(".frame(minHeight: 48, maxHeight: 84)"))
        CT.checkTrue("the card is laid out before the transcript, which gives way", card.contains(".layoutPriority(1)"))
        CT.checkTrue("the cut note is the shared one, in grey, only when the text was cut", card.contains("if result.cut") && card.contains("CompanionChrome.cutNote"))
        CT.checkTrue("a clipboard-started run says so in one grey line, beside the cut note", card.contains("if result.fromClipboard") && card.contains("CompanionQuickRules.clipboardNote") && card.contains("if result.cut"))
        CT.checkTrue("the run carries the clipboard label into its card, and the menu's quick call takes it", quickRun.contains("QuickResult.started(kind: kind, cut: cut, sourcePID: sourcePID, fromClipboard: fromClipboard)") && quickRun.contains("fromClipboard: Bool = false"))
        CT.checkTrue("Replace is offered only when the card says so", card.contains("if result.canReplace") && card.contains("\"Replace\""))
        CT.checkTrue("Replace puts the text on the pasteboard, brings the source app forward and says to paste: it never pastes", card.contains("NSPasteboard.general.clearContents()") && card.contains("NSRunningApplication(processIdentifier: pid)") && card.contains("app.activate()") && card.contains("CompanionChrome.replaceNote"))
        CT.checkTrue("Copy and the close button are there", card.contains("\"Copy\"") && card.contains("state.quickResult = nil"))
        CT.check("the card reaches the pasteboard in two places (Replace, Copy)", count("NSPasteboard.general.clearContents()", in: card), 2)
        CT.check("PromptView draws the card once, only in the live chat", count("if isLive, let result = state.quickResult", in: promptView), 1)
        CT.check("PromptView draws the screenshot chip once, only in the live chat", count("if isLive, ClaudeService.shared.pendingImage != nil", in: promptView), 1)
        let inputField = at("TextField(state.chatHistory.isEmpty", in: promptView)
        CT.checkTrue("the card and the chip sit above the input row", at("QuickResultCard(", in: promptView) > 0 && at("QuickResultCard(", in: promptView) < inputField && at("ExplainScreenshotChip(", in: promptView) > 0 && at("ExplainScreenshotChip(", in: promptView) < inputField)
        let chip = body("struct ExplainScreenshotChip: View {", in: views)
        CT.checkTrue("the chip runs the image question on the pending image", chip.contains("Companion.shared.quick(kind: \"explainImage\", text: nil, image: image, sourcePID: nil)") && chip.contains("Text(\"Explain this screenshot\")"))
        let menu = body("struct ChatMenuButton: View {", in: views)
        CT.checkTrue("the menu has Fix, Rewrite and Explain, and the copied screenshot", menu.contains("Button(\"Fix\")") && menu.contains("Button(\"Rewrite\")") && menu.contains("Button(\"Explain\")") && menu.contains("Button(\"Explain the copied screenshot\")"))
        let runQuick = body("    private func runQuick(_ kind: String) {", in: views)
        CT.checkTrue("the text items read the field first, then the clipboard when chosen, with the pasteboard's types passed in", runQuick.contains("CompanionQuickSource.pick(field: fieldText, pasteboard: clipboard, pasteboardTypes: types)"))
        let typesAt = at("NSPasteboard.general.types?.map(\\.rawValue) ?? []", in: runQuick), stringAt = at("NSPasteboard.general.string(forType: .string)", in: runQuick)
        CT.checkTrue("the types are read first, and the clipboard's string only after they pass", typesAt >= 0 && stringAt > typesAt && at("CompanionQuickSource.hasSkippedType(types) ? nil", in: runQuick) > typesAt && at("CompanionQuickSource.hasSkippedType(types) ? nil", in: runQuick) < stringAt)
        CT.checkTrue("nothing usable shows the fixed note in the chat, and starts nothing", runQuick.contains("guard let pick = ") && runQuick.contains("CompanionQuickRules.noSelectionNote") && runQuick.contains("AppState.shared.chatNotice = ChatNotice(text: CompanionQuickRules.noSelectionNote)"))
        CT.checkTrue("a usable pick is passed on with its clipboard label", runQuick.contains("Companion.shared.quick(kind: kind, text: pick.text, sourcePID: nil, fromClipboard: pick.fromClipboard)"))
        CT.checkTrue("the screenshot item is enabled by the clipboard's types, looked at when the pointer reaches the menu", menu.contains(".disabled(!hasImage)") && menu.contains(".onHover") && menu.contains("CompanionQuickSource.pasteboardHoldsImage()"))
        CT.section("quick actions: a run clears only the selection note, a clipboard Explain is labelled, a concealed screenshot is never read")
        let noteClearAt = at("if CompanionQuickRules.clearsNotice(state.chatNotice?.text) { state.chatNotice = nil }", in: quickMethod)
        CT.checkTrue("a run clears the selection note through the one helper, once, and only after its request is built", noteClearAt > at("CompanionQuick.request(kind: kind, text: text)", in: quickMethod) && count("chatNotice = nil", in: quickRun) == 1)
        let explainAt = at("ClaudeService.shared.explain(request:", in: quickMethod)
        CT.checkTrue("a clipboard Explain sets its chat note after explain() has cleared the chat", explainAt > 0 && at("if fromClipboard { state.chatNotice = ChatNotice(text: CompanionQuickRules.clipboardNote) }", in: quickMethod, from: explainAt) > explainAt)
        let typesLine = at("let types = pasteboard.types?.map(\\.rawValue) ?? []", in: clipBody)
        CT.checkTrue("the screenshot reads the clipboard's types first, and its data only when they pass the one decision", typesLine >= 0 && at("CompanionQuickSource.holdsReadableImage(types)", in: clipBody) > typesLine && at("pasteboard.data(forType: .png)", in: clipBody) > at("CompanionQuickSource.holdsReadableImage(types)", in: clipBody))
        CT.checkTrue("the screenshot data is read only inside the decision's true branch (no unconditional read)", clipBody.contains("holdsReadableImage(types) ? (pasteboard.data(forType: .png)") && count("pasteboard.data(forType:", in: clipBody) == 2)
        let pasteboardHolds = body("    static func pasteboardHoldsImage() -> Bool {", in: quickRun)
        CT.checkTrue("the menu's screenshot item asks the same decision, not the raw types", pasteboardHolds.contains("holdsReadableImage(NSPasteboard.general.types?.map(\\.rawValue) ?? [])") && !pasteboardHolds.contains("types.contains(.png)"))
        CT.checkTrue("the card's clipboard line is outside the running branch: same brace depth as the cut note, one level out from the running line, and after it", braceDepth(at: "if result.fromClipboard {", in: card) == braceDepth(at: "if result.cut {", in: card) && braceDepth(at: "if result.running {", in: card) == braceDepth(at: "if result.cut {", in: card) + 1 && at("if result.fromClipboard {", in: card) > at("if result.cut {", in: card) && at("if let note = result.note", in: card) > at("if result.fromClipboard {", in: card))
        CT.check("the menu reads the clipboard's string only when an item is chosen", count("NSPasteboard.general.string(forType: .string)", in: views), 1)
        CT.checkTrue("PromptView gives the menu the field's text", promptView.contains("fieldText: text)"))

        CT.section("settings: the Companion tab is plain values, has one marker and one confirmation, logs and copies nothing, and writes only the store's keys")
        let companionPage = source("SettingsCompanionPage.swift"), settingsView = source("SettingsView.swift")
        CT.checkTrue("the page is there and declares CompanionTab", companionPage.contains("struct CompanionTab: View"))
        for word in ["AppState", "CompanionStore", "UserDefaults", "AILog", "appendAppLog", "print(", "NSLog", "os_log", "Logger(", "NSPasteboard", "Timer"] {
            CT.check("SettingsCompanionPage.swift does not hold \(word)", count(word, in: companionPage), 0)
        }
        CT.check("the sheet's root carries CompanionFiles.marker, once", count("CompanionFiles.marker", in: companionPage), 1)
        CT.check("Delete all is behind one confirmationDialog", count("confirmationDialog", in: companionPage), 1)
        CT.check("SettingsView.swift builds CompanionTab once", count("CompanionTab(", in: settingsView), 1)
        CT.check("SettingsView.swift holds no hidden placeholder", count("EmptyView()   // hidden until", in: settingsView), 0)
        let companionNames = ((try? FileManager.default.contentsOfDirectory(atPath: "NotchBuddy/Sources/App")) ?? []).filter { $0.hasPrefix("Companion") && $0.hasSuffix(".swift") }
        for name in (companionNames + ["SettingsCompanionPage.swift"]).sorted() where name != "CompanionStore.swift" {
            CT.check("\(name) writes no companion. key", count("\"companion.", in: source(name)), 0)
        }
        CT.check("only CompanionStore.swift names the companion. keys", companionNames.filter { $0 != "CompanionStore.swift" && count("\"companion.", in: source($0)) > 0 }, [])
        CT.check("the store names its three keys, once each", count("\"companion.", in: source("CompanionStore.swift")), 3)

        CT.section("nothing runs idle, nothing leaks: the companion's source set holds no timer, no watcher, no print and no log of text")
        let set = (companionNames + ["ChatSizing.swift", "SettingsCompanionPage.swift"]).sorted()
        CT.checkTrue("the source set is there (the companion's files, ChatSizing, the Settings page)", set.contains("CompanionStore.swift") && set.allSatisfy { !source($0).isEmpty })
        for word in ["Timer", "asyncAfter", "DispatchSourceTimer", "CADisplayLink", "FSEvents", "makeFileSystemObjectSource", "NSFilePresenter", "NotificationCenter.default.addObserver", "print("] {
            CT.check("no file in the set holds \(word)", set.filter { count(word, in: source($0)) > 0 }, [])
        }
        let logOffenders = set.flatMap { name in
            source(name).components(separatedBy: "\n")
                .filter { $0.contains("AILog.record(") && $0.range(of: #"AILog\.record\(\.[A-Za-z]+\)"#, options: .regularExpression) == nil }
                .map { "\(name): \($0.trimmingCharacters(in: .whitespaces))" }
        }
        CT.check("every AILog.record in the set names an event kind only (no message, title or text)", logOffenders, [])
        CT.check("UserDefaults.standard appears only in CompanionStore.swift", set.filter { $0 != "CompanionStore.swift" && count("UserDefaults.standard", in: source($0)) > 0 }, [])
        let files = source("CompanionFiles.swift")
        let opens = files.components(separatedBy: "\n").filter { $0.contains(" open(") }
        CT.check("CompanionFiles.swift has three open calls (the folder, the read, the write)", opens.count, 3)
        CT.check("every open call in CompanionFiles.swift is O_NOFOLLOW", opens.filter { !$0.contains("O_NOFOLLOW") }.count, 0)
        CT.check("the write's open is O_EXCL as well, once", count("O_CREAT | O_EXCL | O_NOFOLLOW", in: files), 1)
        CT.check("ShortcutLogic.swift has no companion case (openChat is the chat's shortcut)", count("companion", in: source("ShortcutLogic.swift").lowercased()), 0)

        CT.finish()
    }
}
