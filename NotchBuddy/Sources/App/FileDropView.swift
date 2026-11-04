import AppKit
import SwiftUI

// MARK: - NSView drag destination
// Wired at the AppKit level in IslandWindowController (not via SwiftUI NSViewRepresentable)
// so it never interferes with SwiftUI hit-testing.

final class FileDropNSView: NSView {
    var onDragEntered: ((CGPoint) -> Void)?
    var onDragUpdated: ((CGPoint) -> Void)?
    var onDragExited:  (() -> Void)?
    var onFilesDropped: (([URL]) -> Void)?
    /// Which half of the open island a point of this view is in (sub-project G1). Without it every point is Ask, as before.
    var halfAt: (@MainActor (CGPoint) -> DropHalf)?
    /// A drop on the Shelf half: the pasteboard and what it carries. Never called for a drag that started inside the app.
    var onShelfDrop: (@MainActor (NSPasteboard, Set<DragKind>) -> Void)?
    /// A drop on an agent's own cat (sub-project F1). It is consulted FIRST by every drag callback below, after the app's own drags are ruled out and before the island's drop view opens and before
    /// G1's Ask and Shelf halves, which apply only when it answers nil (so the shelf's highlight never lights up over an agent cat). Only file URLs go to an agent's cat. Without it every drop is
    /// what it always was.
    var agentCatAt: (@MainActor (CGPoint) -> String?)?
    var onAgentDragOver: (@MainActor (String?) -> Void)?
    var onAgentDrop: (@MainActor ([URL], String) -> Void)?
    /// The agent cat the drag is over now, and whether the island's drop view was told about this drag (`onDragEntered`): `onDragExited` follows `onDragEntered`, never alone.
    private var overAgentCat: String?
    private var zoneEntered = false

    private func setOverAgentCat(_ pill: String?) {
        guard pill != overAgentCat else { return }
        overAgentCat = pill
        onAgentDragOver?(pill)
    }

    /// The drop view is told the drag left, exactly when it was told it entered (`onDragEntered`): never alone, never twice. An agent's cat takes the drag over from the drop zone through this.
    private func leaveZone() {
        if zoneEntered { zoneEntered = false; onDragExited?() }
    }

    override init(frame: NSRect) {
        super.init(frame: frame)
        registerForDraggedTypes([.fileURL] + ShelfDropReader.extraTypes)
    }
    required init?(coder: NSCoder) { fatalError() }

    // Pass all mouse events through — drag-drop uses NSDraggingDestination, not hitTest
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// A drag that started inside the app (a shelf item dragged out and back in) is nobody's drop: it is never added twice, and it does not open the Ask canvas.
    private func isOwnDrag(_ sender: NSDraggingInfo) -> Bool { sender.draggingSource != nil }

    /// What the drag is allowed to do at its position: file URLs are copied over both halves, as today; promised files and browser images only over Shelf.
    private func operation(_ sender: NSDraggingInfo, kinds: Set<DragKind>) -> NSDragOperation {
        ShelfDrop.accepts(kinds, over: halfAt?(sender.draggingLocation) ?? .ask) ? .copy : []
    }

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !isOwnDrag(sender) else { return [] }
        let kinds = ShelfDropReader.kinds(of: sender.draggingPasteboard)
        guard ShelfDrop.opensIsland(kinds) else { return [] }
        zoneEntered = false   // a new drag: the drop view has not heard of it (a drop that finished never calls exited, so the flag may be stale)
        if kinds.contains(.fileURL), let pill = agentCatAt?(sender.draggingLocation) { setOverAgentCat(pill); return .copy }   // an agent's own cat: the drop view does not open for it
        zoneEntered = true
        onDragEntered?(sender.draggingLocation)
        return operation(sender, kinds: kinds)
    }
    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        guard !isOwnDrag(sender) else { return [] }
        let kinds = ShelfDropReader.kinds(of: sender.draggingPasteboard)
        guard ShelfDrop.opensIsland(kinds) else { return [] }
        if kinds.contains(.fileURL), let pill = agentCatAt?(sender.draggingLocation) { setOverAgentCat(pill); leaveZone(); return .copy }
        setOverAgentCat(nil)
        // The pointer left an agent's cat: the drop view opens now, as it would have at the start.
        if !zoneEntered { zoneEntered = true; onDragEntered?(sender.draggingLocation) }
        onDragUpdated?(sender.draggingLocation)
        return operation(sender, kinds: kinds)
    }
    override func draggingExited(_ sender: NSDraggingInfo?) {
        setOverAgentCat(nil)
        leaveZone()
    }

    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        guard !isOwnDrag(sender) else { return false }
        let kinds = ShelfDropReader.kinds(of: sender.draggingPasteboard)
        // A drop on an agent's own cat hands over a path, not the file: ruled before the Ask and Shelf halves (the big cat's drop is not touched).
        if kinds.contains(.fileURL), let pill = agentCatAt?(sender.draggingLocation),
           let urls = sender.draggingPasteboard.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !urls.isEmpty {
            setOverAgentCat(nil)
            leaveZone()   // the zone the drag had entered is closed before the handler runs
            onAgentDrop?(urls, pill)
            return true
        }
        zoneEntered = false   // a drop is not followed by an exit: the flag is cleared here, silently (an exit would clear the glow the drop handler reads)
        let half = halfAt?(sender.draggingLocation) ?? .ask
        guard ShelfDrop.accepts(kinds, over: half) else { return false }
        if half == .shelf {
            onShelfDrop?(sender.draggingPasteboard, kinds)
            return true
        }
        // The Ask half: exactly as it has always been.
        guard let urls = sender.draggingPasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !urls.isEmpty else { return false }
        onFilesDropped?(urls)
        return true
    }
}

// MARK: - File drop handler

enum FileDropHandler {
    /// One token per drop: the delayed work of an older drop must not touch a newer drop.
    @MainActor static let drops = DropGeneration()

    /// A file dropped while the desktop cat is out waits until the cat is at the notch (`DesktopCatTrip.catchReady`), at most `DesktopCatTrip.catchWaitMs`; with the cat home it does not wait at
    /// all. A short sleep loop that exists only for the length of a drop: no timer.
    @MainActor
    static func waitForCat(state: AppState) async {
        let start = ProcessInfo.processInfo.systemUptime
        while !DesktopCatTrip.catchReady(state.desktopPhase), (ProcessInfo.processInfo.systemUptime - start) * 1000 < DesktopCatTrip.catchWaitMs {
            try? await Task.sleep(nanoseconds: 50_000_000)
        }
    }

    @MainActor
    static func handle(urls: [URL], state: AppState) async {
        guard let url = urls.first else { return }
        let drop = drops.begin()
        // Still this drop's turn: no newer drop has started and the user has not left the drop flow (the engine is deactivated then). Checked after
        // every wait, before anything is written or played.
        func live() -> Bool { drops.isCurrent(drop) && UploadSequenceEngine.shared.isActive }
        // The desktop cat flies to the notch to catch this file (a file on its way in is an alert to it: `DesktopCatController.fileCatching`). A drop that lands before the cat has waits for
        // it; `fileDragOver` stays true meanwhile (it is cleared below), so the alert holds. A newer drop or a left drop flow ends the wait's turn. The flow is checked after the wait only
        // when the wait ran (the cat was not home): with the cat home nothing waits and nothing is checked, as before the wait existed.
        let waited = !DesktopCatTrip.catchReady(state.desktopPhase)
        await waitForCat(state: state)
        guard !waited || live() else {
            // The flow closed during the wait: nothing else clears the drag state, so the cat would sit at the notch until the next drag. Only this drop's own clear: a newer drag is not disturbed.
            if drops.isCurrent(drop) { state.fileDragOver = false }
            return
        }
        let name = url.lastPathComponent

        // Is it a file the cat coughs up? Decided here, at the drop, from what is known now (the extension and the size): the app's own refusal
        // rule, not the AI reader's verdict at the end of the upload sequence.
        let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        let refused = CatFileRule.refused(ext: url.pathExtension, size: bytes)

        // Start animation immediately — do NOT block on file copy.
        // Use original URL first; swap to inbox copy once background copy finishes.
        state.droppedFile = DroppedFile(url: url, name: name)
        state.uploadProgress = 0
        state.fileDragOver = false
        state.promptContext = .file(name: name, fileURL: url)
        ClaudeService.shared.clearConversation(state: state)
        ClaudeService.shared.prepareAttachment(url: url, state: state)

        let dur = 2.4
        UploadSequenceEngine.shared.performDrop(uploadDuration: dur, refused: refused)

        // Copy to inbox in background — update state when done
        let inbox = HookServer.supportDir.appendingPathComponent("inbox")
        Task.detached {
            try? FileManager.default.createDirectory(at: inbox, withIntermediateDirectories: true)
            let dest = inbox.appendingPathComponent(name)
            try? FileManager.default.removeItem(at: dest)
            if (try? FileManager.default.copyItem(at: url, to: dest)) != nil {
                await MainActor.run {
                    guard drops.isCurrent(drop) else { return }   // a newer drop's file stays; leaving the flow does not lose this copy
                    state.droppedFile = DroppedFile(url: dest, name: name)
                    state.promptContext = .file(name: name, fileURL: dest)
                }
            }
        }

        // Drop feedback. The `approve` chime no longer plays here, for any file: it plays when the file turns out to be readable (at the check mark,
        // below), so a refused file never gets it. A refused file gets no gulp and no happy cat either: the cat gags instead.
        if !refused {
            NotificationCenter.default.post(name: .botGulp, object: nil)
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
        }

        state.uploadDuration = dur
        state.uploadStartTime = refused ? nil : Date()   // nothing uploads for a refused file
        state.view = .uploading  // canvas stays active: uploadActive covers .uploading

        if refused {
            // No progress bar, no tick sounds, no check mark and no `approve` chime. The cat caught the file like any file; when it arrives the cat
            // gags and coughs it up as a hairball (USC.COUGH_LEAD_S + USC.HAIRBALL_S), and then the choose view shows the reader line that says why
            // the file cannot be read (`state.dropReaderLine`, set by `prepareAttachment`).
            // The sounds: `annoyed`, once, as the gag starts (the file has reached the mouth) and nothing after it: the hairball and the choose
            // view's note are silent. Sound Stage 3 wires the `pop` at the cough; it is not added here.
            try? await Task.sleep(nanoseconds: UInt64((USC.T_SUCK_END - USC.T_DROP) * 1_000_000_000))
            guard live() else { return }
            SoundEngine.shared.play("annoyed")   // the gag
            try? await Task.sleep(nanoseconds: UInt64((USC.T_REFUSE_DONE - USC.T_SUCK_END + 0.3) * 1_000_000_000))
            guard live() else { return }
            state.uploadProgress = 0
            state.view = .choose   // the note: no sound
            return
        }

        // Canvas timeline from drop:
        //   T_DROP → T_PROG_START : ≈1.30s  gulp + shrink + bar reveal
        //   T_PROG_START → progEnd: dur      progress bar fills
        //   progEnd → growEnd     : 0.70s    the cat grows back to choose position
        let preProgress = USC.T_PROG_START - USC.T_DROP  // ≈1.30s

        // Tick sounds — delayed to sync with canvas progress start
        Task { @MainActor in
            var lastTens = 0
            let progStart = Date().addingTimeInterval(preProgress)
            while lastTens < 9 {
                try? await Task.sleep(nanoseconds: 80_000_000)
                guard live() else { return }
                let approxP = min(1.0, max(0, Date().timeIntervalSince(progStart) / dur))
                let tens = Int(approxP * 10)
                if tens > lastTens {
                    SoundEngine.shared.play("tick")
                    lastTens = tens
                }
            }
        }

        // Wait for canvas progress to complete (gulp/shrink phase + upload duration)
        try? await Task.sleep(nanoseconds: UInt64((preProgress + dur) * 1_000_000_000))
        guard live() else { return }

        // Canvas shows checkmark at this point. The file is taken once the AI's reader has read it: that is when the `approve` chime plays. (A
        // file the reader cannot read has no chime; it ends with the annoyed cat below, as before.)
        if !state.dropRejected { SoundEngine.shared.play("approve") }
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)

        // Wait for grow-back animation + choose overlay settle
        try? await Task.sleep(nanoseconds: UInt64(1_000_000_000))
        guard live() else { return }

        // Clean up upload state
        state.uploadProgress = 0
        state.uploadStartTime = nil

        // Switch to choose — canvas stays active (uploadActive covers .choose).
        // Engine deactivates when user clicks a canvas choose button or navigates away.
        state.view = .choose

        // Any other file the AI can't take (unreadable, a copy error, a folder) keeps this ending: the sound and the annoyed cat, and no hairball.
        // The hairball is only for the refused files above, decided at the drop.
        if state.dropRejected {
            SoundEngine.shared.play("annoyed")
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.annoyed)
        }
    }
}
