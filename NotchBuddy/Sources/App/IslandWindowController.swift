import AppKit
import Combine
import SwiftUI

@MainActor
final class IslandWindowController: NSWindowController {

    private var islandPanel: IslandPanel!
    private var state: AppState { AppState.shared }

    // State machine (replaces all hover/absence/auto-close timers)
    let fsm = IslandStateMachine()

    private var wasInIsland = false
    /// The compact island's right wing stepping aside (`IslandWing`): fed once per poll tick, with no timer or monitor of its own.
    private var wingYield = IslandWing.Yield()
    /// The pointer is over a wing of the compact island (either one, only while the wing rules are active): a hover-only hold, so Open on hover never opens the island from a wing.
    /// Written by the poll before it feeds the state machine; read by `fsm.isHoverHeld`. The click, the love emote and the cat's wake on hover are untouched.
    private var pointerOnWing = false
    private var poller: IslandPoller?
    private var keyMonitor: Any?
    private var localKeyMonitor: Any?
    private var viewSubscription: AnyCancellable?
    private var modeSubscription: AnyCancellable?
    private var outsideClickSubscription: AnyCancellable?
    private var outsideClickMonitor: Any?
    private var outsideClicks = IslandOutsideClick.Tracker()
    private var outsideClickAtDown: IslandOutsideClick.Context?
    private var openOnHoverSubscription: AnyCancellable?
    private var autoCloseSubscription: AnyCancellable?
    private var tuckAwaySubscription: AnyCancellable?
    private var agentActivitySubscription: AnyCancellable?
    private var liveSubscription: AnyCancellable?
    private var holdSubscription: AnyCancellable?
    private var sharePickerSubscription: AnyCancellable?
    /// The one timer for the shelf's hold end (`armShelfHoldEnd`).
    private var shelfHoldEnd: DispatchWorkItem?

    // Confused recovery timer (set by handleDizzy)
    private var confusedRecoveryTimer: DispatchWorkItem?

    // Suppress peek sound on next reveal (e.g. musicReveal)
    var silentNextReveal = false

    // Finished-pin timer
    private var finishedPinTimer: DispatchWorkItem?

    // Bot-head hover (love emote — mirrors prototype botHover())
    private var hoverTimer: DispatchWorkItem?
    private var botHoverTimer: DispatchWorkItem?
    private var botHovering: Bool = false
    private var lastLoveTime: Double = 0
    private var botHoverStartPos: CGPoint = .zero

    /// The desktop cat (sub-project H): a drag of the big cat that ends on empty desktop places it there, and ⌃⌥D takes it out or brings it home. Set by `AppDelegate`.
    weak var desktop: DesktopCatController?

    // Window attach drag (M8)
    private var attachDragStart: NSPoint? = nil
    private var pendingIslandClick = false   // any island click → expand on mouseUp
    private var inAttachDrag = false
    private var dragGhostPanel: NSPanel? = nil
    private var dragGhostSize: CGFloat = 0
    private var ghostCurrentOrigin: NSPoint = .zero
    private var highlightPanel: NSPanel? = nil
    private var highlightWindowPid: pid_t = 0

    // Notch real dimensions (set on init)
    private var notchW: CGFloat = IslandConst.notchWidth
    private var notchH: CGFloat = IslandConst.notchHeight
    private var hasNotch = true

    convenience init() {
        let screen = Self.notchScreen() ?? NSScreen.main!
        let geometry = Self.screenGeometry(for: screen)
        let nW = geometry.width
        let nH = geometry.height

        let panelW: CGFloat = 720
        let panelH: CGFloat = 560   // room for the tallest question card (QuestionLayout, 560 pt); the island is glued to the top and the panel passes the mouse on outside it
        let sf = screen.frame
        let panel = IslandPanel(
            contentRect: NSRect(x: sf.midX - panelW/2, y: sf.maxY - panelH,
                                width: panelW, height: panelH),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered, defer: false
        )
        panel.notchWidth  = nW
        panel.notchHeight = nH

        self.init(window: panel)
        self.islandPanel = panel
        self.notchW = nW
        self.notchH = nH
        self.hasNotch = geometry.hasNotch
        setupPanel(screen: screen)
    }

    private func setupPanel(screen: NSScreen) {
        guard let panel = window as? IslandPanel else { return }
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 3)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]
        panel.ignoresMouseEvents = true

        // Propagate real notch dimensions to AppState
        AppState.shared.notchWidth  = notchW
        AppState.shared.notchHeight = notchH
        AppState.shared.hasNotch = hasNotch

        let contentSize = panel.contentRect(forFrameRect: panel.frame).size

        // Apple-recommended pattern: put NSHostingView and drag destination as siblings
        // inside a common superview, rather than embedding one inside the other.
        let container = NSView(frame: NSRect(origin: .zero, size: contentSize))
        container.autoresizingMask = [.width, .height]

        let hosting = NSHostingView(rootView: IslandRootView().environmentObject(AppState.shared))
        hosting.frame = NSRect(origin: .zero, size: contentSize)
        hosting.autoresizingMask = [.width, .height]

        // FileDropNSView sits below the hosting view (hitTest returns nil → no mouse interference).
        // AppKit routes NSDraggingDestination events to registered views independently of hitTest.
        let dropView = FileDropNSView(frame: NSRect(origin: .zero, size: contentSize))
        dropView.autoresizingMask = [.width, .height]
        dropView.onDragEntered = { [weak self] loc in
            Task { @MainActor in
                let iLoc = self?.windowToIsland(loc) ?? CGPoint(x: 320, y: 88)
                // A new drag makes any earlier drop stale, so a drop the user left can't write over this hover once the zone is active again.
                _ = FileDropHandler.drops.begin()
                AppState.shared.fileDragOver = true
                AppState.shared.dropHalf = ShelfDrop.half(x: Double(iLoc.x))
                // enterZone sets isActive=true BEFORE hookExpand triggers re-render,
                // so IslandContainer sees isActive=true when state.view becomes .upload.
                UploadSequenceEngine.shared.enterZone(x: iLoc.x, y: iLoc.y)
                NotificationCenter.default.post(name: .hookExpand, object: IslandView.upload)
            }
        }
        dropView.onDragUpdated = { [weak self] loc in
            Task { @MainActor in
                let iLoc = self?.windowToIsland(loc) ?? CGPoint(x: 320, y: 88)
                UploadSequenceEngine.shared.updateCursor(x: iLoc.x, y: iLoc.y)
                let half = ShelfDrop.half(x: Double(iLoc.x))
                if AppState.shared.dropHalf != half { AppState.shared.dropHalf = half }
            }
        }
        dropView.onDragExited = {
            Task { @MainActor in
                AppState.shared.fileDragOver = false
                AppState.shared.dropHalf = nil
                // Do NOT collapse — drag session still active; island stays open.
                UploadSequenceEngine.shared.exitZone()
            }
        }
        dropView.onFilesDropped = { urls in
            Task { @MainActor in
                AppState.shared.dropHalf = nil
                await FileDropHandler.handle(urls: urls, state: AppState.shared)
            }
        }
        // Sub-project G1: which half a point of the drop view is in, and what a drop on the Shelf half does.
        dropView.halfAt = { [weak self] loc in ShelfDrop.half(x: Double(self?.windowToIsland(loc).x ?? 0)) }
        dropView.onShelfDrop = { [weak self] pasteboard, kinds in
            // At the drop itself, before anything is read: a promised file can be slow, or never answer, and must not leave the upload canvas, the file alert and the sequence up meanwhile.
            ShelfFlow.afterShelfDrop(state: AppState.shared)
            ShelfDropReader.read(pasteboard, kinds: kinds) { incoming, temp in
                self?.shelfDropped(incoming, temp: temp)
            }
        }
        // A drop on an agent's own cat (sub-project F1) is consulted first by every drag callback: the grid's cats in A cat for each agent mode and cat 2 in Two cats mode, never the big cat.
        dropView.agentCatAt = { [weak self] loc in self?.sidekickAgentCat(at: loc) }
        dropView.onAgentDragOver = { pill in AppState.shared.sidekickDropPill = pill }
        dropView.onAgentDrop = { urls, pill in SidekickDropApp.handoff(urls: urls, pillId: pill) }

        container.addSubview(hosting)    // z-bottom: SwiftUI + mouse events
        container.addSubview(dropView)   // z-top: drag only (hitTest→nil, transparent to mouse)
        panel.contentView = container

        startPolling()
        startKeyMonitor()
        startLocalKeyMonitor()
        startHotKeys()
        wireFSM()

        // Make panel key whenever the prompt/chat view becomes active
        // (nonactivatingPanel never auto-becomes key, but TextField needs it)
        viewSubscription = state.$view
            .receive(on: DispatchQueue.main)
            .sink { [weak self] newView in
                guard let self else { return }
                if newView == .prompt {
                    self.islandPanel.makeKey()
                }
            }
    }

    // MARK: - FSM wiring

    private func wireFSM() {
        fsm.onTransition = { [weak self] from, to in
            guard let self else { return }
            switch to {
            case .hidden:
                self.setMode(.hidden)

            case .petit:
                if from == .hello {
                    // Fire interrupt first so canvas collapse starts before mode change
                    NotificationCenter.default.post(name: .greetingInterrupt, object: nil)
                    // The canvas stays up in the compact island until the greeting's last beat is over (see AppState.greetingTail).
                    // Only while the canvas is on screen: if a hook alert or a shortcut already replaced the greeting view, a tail would
                    // mount a new canvas at t = 0 in the compact island, and nothing would end it.
                    if state.mode == .expanded && state.view == .greeting { state.greetingTail = true }
                } else if from == .hidden {
                    if self.silentNextReveal {
                        self.silentNextReveal = false
                    } else {
                        SoundEngine.shared.play("peek")
                    }
                }
                // setMode BEFORE changing view: onChange(of: state.view) guards on .expanded,
                // so setting view while already compact won't trigger a spurious open animation.
                self.setMode(.compact)
                if from == .hello { self.state.view = self.defaultView() }
                // Start 60s hide timer if mouse is not currently over the island
                if !self.wasInIsland { self.fsm.mouseLeft() }

            case .home:
                self.expand(to: self.defaultView())
                // Start collapse timer if mouse not currently hovering
                if !self.wasInIsland {
                    self.fsm.mouseLeft()
                }

            case .hello:
                self.expand(to: .greeting)
            }
        }

        // FSM observes greetComplete notification
        NotificationCenter.default.addObserver(
            forName: .greetComplete, object: nil, queue: .main
        ) { [weak self] _ in
            self?.fsm.greetComplete()
        }

        // A chat's waiting approval card holds the island open like the user's own: a delayed collapse cannot hide it.
        #if !APPSTORE
        fsm.isHeldOpen = { AppState.shared.pendingApproval != nil || AppState.shared.chatApproval != nil || AppState.shared.shelfHoldsIsland || AppState.shared.linkHoldsIsland }
        #else
        fsm.isHeldOpen = { AppState.shared.pendingApproval != nil || AppState.shared.shelfHoldsIsland || AppState.shared.linkHoldsIsland }
        #endif
        // Open on hover never opens over, and never folds, a waiting question, a pinned island or the Wardrobe menu that is up on it, and never opens from a wing of the compact island.
        fsm.isHoverHeld = { [weak self] in AppState.shared.pendingQuestion != nil || AppState.shared.isPinned || (self?.pointerOnWing ?? false) || (self?.wardrobeMenuOpen ?? false) }
        // Settings → General → Behavior → Open on hover (off by default).
        fsm.openOnHover = state.openOnHover
        openOnHoverSubscription = state.$openOnHover.sink { [weak self] on in self?.fsm.openOnHover = on }
        // Settings → General → Behavior → Close after: the open island's fold delay.
        autoCloseSubscription = state.$autoCloseInterval.sink { [weak self] delay in self?.fsm.homeToPetitDelay = max(1, delay) }   // never below 1 s: 0 or a negative value would fold the island the moment the pointer leaves
        // Settings → General → Behavior → Tuck the island away (off: never, the default).
        fsm.tuckAway = state.tuckAway
        tuckAwaySubscription = state.$tuckAway.sink { [weak self] choice in self?.fsm.tuckAway = choice }
        // Every hook event and alert starts the tuck-away count again (AppState.touchPill). The pointer's wing folds do not.
        agentActivitySubscription = state.agentActivity.sink { [weak self] in self?.fsm.agentActivity() }
        // Live: a pill working or waiting, or an agent session that has not ended. Written to the state machine only when it changes (IslandTuckAway.isLive).
        liveSubscription = state.$tasks
            .map { tasks in IslandTuckAway.isLive(pillStates: tasks.map { $0.state.rawValue }) }
            .removeDuplicates()
            .sink { [weak self] live in self?.fsm.setLive(live) }
        // The hold (a waiting card, a shelf or link hold) flips: a due compact island hides at once when it is released (IslandStateMachine.scheduleTuck). The app's change notice comes
        // before the change, so the hold is read on the next main-queue turn, and the state machine is told only when the hold flips.
        holdSubscription = state.objectWillChange
            .receive(on: DispatchQueue.main)
            .map { [weak self] _ in self?.fsm.isHeldOpen?() == true }
            .removeDuplicates()
            .sink { [weak self] _ in self?.fsm.scheduleTuck() }
        // The shelf's hold ends by time, with no published change (ShelfHold: the picker's limit, or the 15 s linger, which rewinds the same reading). One one-shot timer at that
        // moment tells the state machine; it is cancelled and replaced on each change of the reading. No poll, no repeating timer.
        sharePickerSubscription = state.$sharePickerSince.sink { [weak self] since in self?.armShelfHoldEnd(since) }
    }

    private func armShelfHoldEnd(_ since: TimeInterval?) {
        shelfHoldEnd?.cancel(); shelfHoldEnd = nil
        guard let delay = ShelfHold.releaseDelay(pickerSince: since, now: ProcessInfo.processInfo.systemUptime) else { return }
        let item = DispatchWorkItem { [weak self] in
            self?.shelfHoldEnd = nil
            self?.fsm.scheduleTuck()
        }
        shelfHoldEnd = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    // MARK: - Polling loop (60 Hz on screen, 10 Hz hidden)

    private func startPolling() {
        let poller = IslandPoller { [weak self] in self?.pollFrame() }
        self.poller = poller
        poller.run(hidden: state.mode == .hidden)
        // Hidden, the poll only has to see the mouse enter the notch (hover-to-show).
        modeSubscription = state.$mode
            .receive(on: DispatchQueue.main)
            .sink { mode in poller.run(hidden: mode == .hidden) }
        // A click outside the open island folds it (IslandOutsideClick): the one global mouse monitor exists only while the island is expanded.
        outsideClickSubscription = state.$mode
            .removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] mode in self?.syncOutsideClickMonitor(expanded: mode == .expanded) }
    }

    // MARK: - A click outside the open island folds it

    private func syncOutsideClickMonitor(expanded: Bool) {
        if expanded, outsideClickMonitor == nil {
            outsideClicks.reset()
            outsideClickMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp, .otherMouseDown, .otherMouseUp]) { [weak self] event in
                MainActor.assumeIsolated { self?.handleOutsideClick(event) }
            }
        } else if !expanded, let monitor = outsideClickMonitor {
            NSEvent.removeMonitor(monitor)
            outsideClickMonitor = nil
            outsideClicks.reset()
            outsideClickAtDown = nil
        }
    }

    /// Global monitors see only other apps' events, so every event here is outside the island. What the app knew at the press decides (the press can take the key away from the panel
    /// before it is released); the release folds when the pair was a click and not a drag.
    private func handleOutsideClick(_ event: NSEvent) {
        switch event.type {
        case .leftMouseDown, .rightMouseDown, .otherMouseDown:
            outsideClicks.down(at: NSEvent.mouseLocation)
            outsideClickAtDown = IslandOutsideClick.Context(
                expanded: state.mode == .expanded,
                pinned: state.isPinned,
                held: decisionWaiting || fsm.isHeldOpen?() == true,
                typing: state.view == .prompt && islandPanel.isKeyWindow && islandPanel.firstResponder is NSTextInputClient,
                pointerInIsland: wasInIsland,
                busy: inAttachDrag || attachDragStart != nil || wardrobeMenuOpen)
        default:
            guard outsideClicks.up(at: NSEvent.mouseLocation), let context = outsideClickAtDown else { return }
            outsideClickAtDown = nil
            if IslandOutsideClick.shouldFold(context) { collapse() }
        }
    }

    private func pollFrame() {
        guard let panel = window as? IslandPanel else { return }

        let mouse = NSEvent.mouseLocation

        // Convert mouse to panel-local coords (macOS: origin bottom-left)
        let pf = panel.frame
        let local = CGPoint(x: mouse.x - pf.minX, y: mouse.y - pf.minY)

        // Island rect in panel coords
        let islandRect = panel.currentIslandFrame(nw: notchW, nh: notchH)
        // On a screen without a notch, the resting bar must not intercept clicks
        // in the app window immediately below the menu bar.
        let hoverRect = !hasNotch && state.mode != .expanded
            ? islandRect : islandRect.insetBy(dx: -6, dy: -6)
        // The compact island steps aside (IslandWing): the pointer over EITHER wing swooshes the whole island into the notch, and the panel passes the mouse on to the menu bar icons under both wings.
        // The notch itself is the island's hover zone. `islandRect` is the full island's frame, so the zones stay where they were and leaving is measured against the original wings. An alert cancels it.
        // Fed by this poll's own pointer and clock: no timer and no monitor of its own.
        let wingAlert = decisionWaiting || state.fileDragOver || state.shelfHoldsIsland || state.desktopPhase != .home || wardrobeMenuOpen
        let wingActive = IslandWing.isActive(compact: state.mode == .compact, greetingTail: state.greetingTail, dragging: inAttachDrag || attachDragStart != nil, alert: wingAlert)
        let wings = IslandWing.wings(island: islandRect, notchWidth: notchW, slop: hoverRect.maxX - islandRect.maxX)
        let wing = wingYield.step(now: CACurrentMediaTime(), zone: wingActive ? wings.zone(of: local) : nil, active: wingActive,
                                  buttonDown: { NSEvent.pressedMouseButtons != 0 })
        if state.wingYielded != wing.faded { state.wingYielded = wing.faded }
        let wasOnWing = pointerOnWing
        pointerOnWing = wingActive && wings.zone(of: local) != nil
        // While files are dragged out of the shelf, or its share picker is open, the pointer may be anywhere and the island still counts it as over it (sub-project G1). The wing's own line above is
        // the same text as before (`&&` binds tighter than `||`), so a drag that ends outside the island ends in the ordinary mouse-left, which starts the fold timer.
        let inIsland = hoverRect.contains(local) && !wing.passThrough || state.shelfHoldsIsland
        // The hover glow's trigger: the pointer itself over the island (not the shelf's hold), written only when it changes.
        let pointerOver = hoverRect.contains(local) && !wing.passThrough
        if state.islandHovered != pointerOver { state.islandHovered = pointerOver }

        // Toggle click-through
        let shouldAcceptMouse = inIsland || inAttachDrag || attachDragStart != nil
        if panel.ignoresMouseEvents == shouldAcceptMouse {
            panel.ignoresMouseEvents = !shouldAcceptMouse
            if shouldAcceptMouse, let cv = panel.contentView {
                panel.invalidateCursorRects(for: cv)
            }
        }

        // Mouse in screen coords (Y flipped, origin top-left) for Bot look-at
        let screenH = panel.screen?.frame.height ?? NSScreen.main!.frame.height
        let newPos = CGPoint(x: mouse.x - (panel.screen?.frame.minX ?? 0), y: screenH - mouse.y)
        let cur = AppState.shared.mousePosition
        if abs(newPos.x - cur.x) > 1 || abs(newPos.y - cur.y) > 1 {
            AppState.shared.mousePosition = newPos
        }

        // The sidekick asks the OS for the idle time on this tick when a sample is due (at most every 5 s, only while an agent has a live session): no timer or monitor of its own.
        Sidekick.shared.tick()

        // AppState can hide the island by itself (last task ended): keep the FSM in step.
        if state.mode == .hidden && fsm.state == .petit { fsm.hiddenExternally() }

        // Feed FSM hover enter/leave
        if inIsland && !wasInIsland {
            guard !inAttachDrag else { wasInIsland = inIsland; return }
            // If in notchmeow: tell greeting to stay open (tc → infinity)
            if fsm.state == .hello {
                NotificationCenter.default.post(name: .greetingHover, object: nil)
            }
            CatSleepClock.shared.wake("hover")   // a hover wakes a sleeping cat
            fsm.mouseEntered()
        }
        if !inIsland && wasInIsland && !wardrobeMenuOpen {   // the Wardrobe menu is up: the pointer is on it, and the island stays open under it
            fsm.mouseLeft()
        }
        // The pointer came off a wing into the notch zone while still over the island: no enter edge, so Open on hover's dwell is armed again here (it cancels and re-arms its one one-shot item).
        if inIsland && wasInIsland && wasOnWing && !pointerOnWing { fsm.hoverResume() }
        wasInIsland = inIsland || wardrobeMenuOpen

        // Bot-head hover (love emote)
        let overBot = state.mode == .expanded && state.stateOverride == nil && isBotHit(local)
        if overBot && !botHovering { botHoverIn(mousePos: NSEvent.mouseLocation) }
        if !overBot && botHovering { botHoverOut() }
        botHovering = overBot
        if botHovering {
            let m = NSEvent.mouseLocation
            let dist = hypot(m.x - botHoverStartPos.x, m.y - botHoverStartPos.y)
            if dist > 40 {
                botHoverStartPos = m
                botHoverTimer?.cancel()
                scheduleLoveTimer()
            }
        }

        // Ghost cat follows cursor + window highlight during drag (60 Hz, no throttle)
        if inAttachDrag {
            updateDragGhost()
            updateWindowHighlight()
        }
    }

    private var lastMouse: CGPoint = .zero

    // MARK: - Bot-head hover (love emote — mirrors prototype botHover())

    private func botHoverIn(mousePos: CGPoint) {
        guard state.mode == .expanded, state.stateOverride == nil else { return }
        guard CACurrentMediaTime() - lastLoveTime > 6 else { return }
        botHoverStartPos = mousePos
        NotificationCenter.default.post(name: .botBlink, object: nil)
        NotificationCenter.default.post(name: .botSetTgEs, object: CGFloat(1.08))
        SoundEngine.shared.play("hover")
        scheduleLoveTimer()
    }

    private func botHoverOut() {
        botHoverTimer?.cancel()
        NotificationCenter.default.post(name: .botSetTgEs, object: CGFloat(1))
    }

    private func scheduleLoveTimer() {
        botHoverTimer?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.botHovering, self.state.stateOverride == nil else { return }
            guard CACurrentMediaTime() - self.lastLoveTime > 6 else { return }
            self.lastLoveTime = CACurrentMediaTime()
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.love)
            SoundEngine.shared.play("love")
        }
        botHoverTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 1.9, execute: item)
    }

    private func scheduleHover(after delay: TimeInterval, action: @escaping () -> Void) {
        hoverTimer?.cancel()
        let item = DispatchWorkItem(block: action)
        hoverTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    // MARK: - Mode transitions

    private func modeLevel(_ m: IslandMode) -> Int {
        switch m { case .hidden: return 0; case .compact: return 1; case .expanded: return 2 }
    }

    func setMode(_ mode: IslandMode) {
        let prev = state.mode
        guard mode != prev else { return }
        let shrinking = modeLevel(mode) < modeLevel(prev)
        let anim: Animation = shrinking
            ? .timingCurve(0.45, 0, 0.2, 1, duration: 0.34)
            : .spring(response: 0.5, dampingFraction: 0.72)
        withAnimation(anim) { state.mode = mode }
        if mode == .expanded { SoundEngine.shared.play("open") }
        if prev == .expanded {
            SoundEngine.shared.play("close")
            state.chatPane = .chat   // the island opens on the chat again
            if fsm.isHeldOpen?() != true { state.isPinned = false }
        }
    }

    func expand(to view: IslandView) {
        state.view = view
        if state.mode == .expanded {
            // Already expanded — just switch view
        } else {
            setMode(.expanded)
        }
        state.lastActivity = .now
    }

    func collapse() {
        guard fsm.isHeldOpen?() != true else { return }
        state.isPinned = false
        finishedPinTimer?.cancel()
        // Keep the FSM in step with what is on screen (home/notchmeow → petit now).
        fsm.collapse()
        setMode(.compact)
        window?.resignKey()
    }

    // MARK: - Global hot keys (Carbon)

    private func startHotKeys() {
        HotKeyCenter.shared.start { [weak self] action in
            self?.handleHotKey(action)
        }
    }

    func handleHotKey(_ action: ShortcutAction) {
        switch action {
        case .toggleIsland:
            if state.mode == .expanded {
                collapse()
            } else {
                openWithKeyboard(defaultView())
            }

        case .openChat:
            openWithKeyboard(.prompt)

        case .goToAlert:
            if state.pendingApproval != nil {
                openWithKeyboard(.approval)
            } else if state.pendingQuestion != nil {
                openWithKeyboard(.question)
            } else {
                NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.annoyed)
                SoundEngine.shared.play("error")
            }

        case .jumpToTerminal:
            #if !APPSTORE
            performJumpToTerminal()
            #endif

        case .attachFrontWindow:
            #if !APPSTORE
            performAttachFrontWindow()
            #endif

        case .nextPill:
            cyclePill(by: +1)

        case .prevPill:
            cyclePill(by: -1)

        case .muteToggle:
            state.soundEnabled.toggle()
            if state.soundEnabled { SoundEngine.shared.play("tick") }
            NotificationCenter.default.post(
                name: .triggerEmote,
                object: state.soundEnabled ? BotEmote.happy : BotEmote.annoyed)

        case .desktop:
            desktop?.toggle()

        case .shelf:
            // The shelf's own key (sub-project G1, off by default): open it, or fold the island when it is already showing it.
            if state.mode == .expanded && state.view == .shelf {
                collapse()
            } else {
                ShelfModel.shared.refresh()
                openWithKeyboard(.shelf)
            }

        case .wardrobe:
            CatSettingsStore.shared.nextOutfit()   // the next outfit in the grid's order, Auto and None included

        case .projects:
            // The Projects key (⌃⌥P, sub-project P-mac, off by default): open the screen, or fold the island when it already shows it.
            if state.mode == .expanded && state.view == .projects {
                collapse()
            } else {
                openWithKeyboard(.projects)
            }
        }
    }

    /// Opens the island on `view` and gives it the keyboard, so the island shortcuts and ⎋ work until it closes.
    /// The state machine is told, like a hook alert does, so its timers don't fold the island under the user.
    private func openWithKeyboard(_ view: IslandView) {
        fsm.openedExternally()
        islandPanel.makeKey()
        expand(to: view)
    }

    /// The agent whose own cat is under a drag (`loc` is in the panel's window), with a live session; nil for everything else, so the drop is what it always was.
    private func sidekickAgentCat(at loc: CGPoint) -> String? {
        guard !isBotHit(loc) else { return nil }   // the big cat's circle, and where it is nearer than cat 2's, is the big cat's: its drop is as it ships
        return SidekickDropApp.agentCat(atWindowPoint: loc, panelWidth: Double(window?.frame.width ?? 720), panelHeight: Double(window?.frame.height ?? 320), live: Sidekick.shared.liveAgents)
    }

    /// The user is typing in the island: it is the key window with a text field being edited. The sidekick's notes wait for them to finish.
    var isTyping: Bool { islandPanel.isKeyWindow && islandPanel.firstResponder is NSTextView }
    /// The pointer is on the island (the poll's own answer). A note stays up while it is.
    var pointerInside: Bool { wasInIsland }

    // MARK: - Pill helpers

    /// ⌃⌥] and ⌃⌥[ (and ⌘→ and ⌘← in the island): the next or previous pill, opening the island if it is closed.
    /// Nothing happens while a permission request or a question is waiting: its card stays on screen, with its agent.
    func cyclePill(by delta: Int) {
        guard let id = ShortcutLogic.pillID(from: state.tasks.map(\.id), current: state.focusId, delta: delta,
                                            decisionWaiting: decisionWaiting) else { return }
        showPill(id)
    }

    private var decisionWaiting: Bool {
        #if !APPSTORE
        if state.chatApproval != nil { return true }
        #endif
        return state.pendingApproval != nil || state.pendingQuestion != nil
    }

    private func showPill(_ id: String) {
        state.setFocus(id)
        state.cardSelection = nil
        fsm.openedExternally()
        expand(to: .overview)
    }

    // MARK: - Island-local shortcuts (while the island has the keyboard)

    private func startLocalKeyMonitor() {
        localKeyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            let handled = MainActor.assumeIsolated { self.handleIslandKey(event) }
            return handled ? nil : event
        }
    }

    /// Runs the island shortcut `event` stands for. Returns false, and the key goes on, when it stands for none
    /// or the island is not the key window (Settings, another app).
    private func handleIslandKey(_ event: NSEvent) -> Bool {
        guard islandPanel.isKeyWindow else { return false }
        let context = IslandKeyContext(inOverview: state.view == .overview, inChat: state.view == .prompt)
        guard let command = ShortcutLogic.islandCommand(
            keyCode: event.keyCode, nsFlags: event.modifierFlags.rawValue,
            characters: event.charactersIgnoringModifiers, in: context) else { return false }
        switch command {
        case .nextPill:        cyclePill(by: +1)
        case .prevPill:        cyclePill(by: -1)
        case .pill(let n):
            if let id = ShortcutLogic.pillID(number: n, in: state.tasks.map(\.id), decisionWaiting: decisionWaiting) { showPill(id) }
        case .listDown:        navigateCard(by: +1)
        case .listUp:          navigateCard(by: -1)
        case .openSelection:   openCardSelection()
        case .toggleDiff:      NotificationCenter.default.post(name: .islandToggleDiff, object: nil)
        case .sendMessage:     NotificationCenter.default.post(name: .islandSendMessage, object: nil)
        case .newConversation: NotificationCenter.default.post(name: .islandNewConversation, object: nil)
        case .openSettings:    NotificationCenter.default.post(name: .openFullSettings, object: nil)
        case .togglePin:       state.isPinned.toggle()
        case .escape:
            if EscapeRouting.isComposing(in: islandPanel) { return false }   // ⎋ cancels the composition
            handleEscape()
        }
        return true
    }

    /// ⎋ with the island as key window. A focused view that handles it (the "Other…" field, a list, a diff) goes
    /// first; otherwise the island closes, unless it is pinned.
    private func handleEscape() {
        if let responder = EscapeRouting.consumer(in: islandPanel) {
            NSApp.sendAction(#selector(NSStandardKeyBindingResponding.cancelOperation(_:)), to: responder, from: nil)
        } else if EscapeRouting.shouldCollapse(expanded: state.mode == .expanded, pinned: state.isPinned, decisionWaiting: decisionWaiting) {
            collapse()
        }
    }

    private func navigateCard(by delta: Int) {
        guard state.view == .overview, state.cardItemCount > 0 else { return }
        state.cardSelection = ShortcutLogic.navigate(
            selection: state.cardSelection, delta: delta, itemCount: state.cardItemCount)
    }

    private func openCardSelection() {
        guard state.view == .overview, state.cardSelection != nil else { return }
        NotificationCenter.default.post(name: .islandActivateCardSelection, object: nil)
    }

    // MARK: - Terminal jump and window attach

    #if !APPSTORE
    /// ⌃⌥T: brings the agent's terminal forward, as the cards' "Open terminal" button does.
    private func performJumpToTerminal() {
        guard state.focusTask != nil else {
            SoundEngine.shared.play("error")
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.annoyed)
            return
        }
        let running = NSWorkspace.shared.runningApplications
        if let terminal = ShortcutLogic.terminalBundleIds.compactMap({ id in
            running.first { $0.bundleIdentifier == id }
        }).first {
            terminal.activate(options: .activateIgnoringOtherApps)
        } else {
            NSWorkspace.shared.open(URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app"))
        }
        collapse()
    }

    /// ⌃⌥W: the window that was in front becomes the chat's context, as when the cat is dragged onto it.
    private func performAttachFrontWindow() {
        guard let app = state.lastExternalApp,
              let ctx = WindowContextCapture.captureActive(from: app) else {
            SoundEngine.shared.play("error")
            return
        }
        state.promptContext = ctx
        // The context only goes with a conversation's first message, so a new window starts a new one.
        ClaudeService.shared.clearConversation(state: state)
        SoundEngine.shared.play("approve")
        NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
        openWithKeyboard(.prompt)
    }
    #endif

    // MARK: - Keyboard (Escape closes)

    private func startKeyMonitor() {
        keyMonitor = NSEvent.addGlobalMonitorForEvents(matching: .keyDown) { [weak self] event in
            Task { @MainActor in
                guard let self = self else { return }
                if event.keyCode == 53 { // Escape
                    if EscapeRouting.shouldCollapse(expanded: self.state.mode == .expanded, pinned: self.state.isPinned, decisionWaiting: self.decisionWaiting) {
                        self.collapse()
                    }
                }
            }
        }

        // Hook server expand requests (alerts only)
        NotificationCenter.default.addObserver(forName: .hookExpand, object: nil, queue: .main) { [weak self] note in
            guard let self, let view = note.object as? IslandView else { return }
            self.fsm.openedExternally()
            self.expand(to: view)
        }

        // Hook server compact reveal (non-alert work events: session start, tool use, etc.)
        NotificationCenter.default.addObserver(forName: .hookReveal, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.fsm.reveal()
        }

        // Music started playing: reveal silently (no peek sound)
        NotificationCenter.default.addObserver(forName: .musicReveal, object: nil, queue: .main) { [weak self] _ in
            guard let self else { return }
            self.silentNextReveal = true
            self.fsm.reveal()
            self.silentNextReveal = false
        }

        // Collapse requests from views (OK button, etc.)
        NotificationCenter.default.addObserver(forName: .islandCollapse, object: nil, queue: .main) { [weak self] _ in
            self?.collapse()
        }

        // .botDizzy — posted by CatEngine.slap() on 3rd hit; show confused view + recover after 3.3s
        NotificationCenter.default.addObserver(forName: .botDizzy, object: nil, queue: .main) { [weak self] _ in
            self?.handleDizzy()
        }

        // Window attach drag.
        // Uses MainActor.assumeIsolated (synchronous) to avoid race with pollFrame().
        // Global mouseUp is the reliable fallback when cursor is outside our panel frame.
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated {
                guard self.wasInIsland && !self.wardrobeMenuOpen else { return }   // a press on the Wardrobe menu is not a click on the island
                self.fsm.userInteracted()            // a click makes a hover-opened island an ordinary open one
                CatSleepClock.shared.wake("click")   // a click wakes a sleeping cat
                self.pendingIslandClick = true
                self.hoverTimer?.cancel()
                self.botHoverTimer?.cancel()
                self.botHovering = false
                // Drag only starts when clicking directly on the bot head
                guard self.isBotHit(event.locationInWindow) else { return }
                self.attachDragStart = NSEvent.mouseLocation
                // Post slap only when expanded
                guard self.state.mode == .expanded else { return }
                NotificationCenter.default.post(name: .triggerSlap, object: nil)
            }
            return event
        }
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseDragged) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated {
                guard let start = self.attachDragStart, !self.inAttachDrag else { return }
                let m = NSEvent.mouseLocation
                guard hypot(m.x - start.x, m.y - start.y) > 3 else { return }
                self.inAttachDrag = true
                NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.love)
                self.showDragGhost()
            }
            return event
        }

        // mouseUp — local (cursor still in panel) + global (cursor moved outside panel frame)
        let finishDrag: @Sendable () -> Void = { [weak self] in
            Task { @MainActor in
                guard let self, self.inAttachDrag else { return }
                let mouse = NSEvent.mouseLocation
                self.inAttachDrag = false
                self.attachDragStart = nil
                self.state.stateOverride = nil
                self.hideDragGhost()
                self.finishBotDrag(at: mouse)
            }
        }
        NSEvent.addLocalMonitorForEvents(matching: .leftMouseUp) { [weak self] event in
            guard let self else { return event }
            MainActor.assumeIsolated {
                let hadPendingClick = self.pendingIslandClick
                let wasDragging     = self.inAttachDrag
                self.pendingIslandClick = false
                if wasDragging {
                    finishDrag()
                } else {
                    self.attachDragStart = nil
                    if hadPendingClick && self.state.mode != .expanded && self.clickedProjectsBadge(event) {
                        self.openProjects()   // a click on the waiting count opens the Projects screen, not the home view
                    } else if hadPendingClick && self.state.mode != .expanded && self.clickedShelfBadge(event) {
                        self.openShelf()   // a click on the shelf's badge opens the shelf, not the home view
                    } else if hadPendingClick && self.state.mode != .expanded {
                        if self.fsm.state == .home {
                            // FSM already thinks it's open (e.g. the view folded it): just reopen.
                            self.expand(to: self.defaultView())
                        } else {
                            self.fsm.click()   // FSM petit/hidden→home; onTransition calls expand(to:)
                        }
                    }
                }
            }
            return event
        }
        NSEvent.addGlobalMonitorForEvents(matching: .leftMouseUp) { _ in
            finishDrag()
        }

        // A right-click on a project's pill opens its Pin / Unpin menu (Projects, P-mac); on a big cat, the Wardrobe menu (sub-project I). It reads no left-button event: a click, a drag,
        // a slap and the drag-out of the cat are as they were.
        NSEvent.addLocalMonitorForEvents(matching: .rightMouseDown) { [weak self] event in
            guard let self else { return event }
            let handled = MainActor.assumeIsolated { self.showProjectPinMenu(for: event) || self.showWardrobeMenu(for: event) }
            return handled ? nil : event
        }

        // Track last external app for window context capture
        let ourBundle = Bundle.main.bundleIdentifier ?? ""
        NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil, queue: .main
        ) { [weak self] note in
            guard let self else { return }
            if let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
               app.bundleIdentifier != ourBundle {
                self.state.lastExternalApp = app
            }
        }
    }

    /// Whether the island's cat menu is open: the pointer is on the menu, outside the island, and the island must not fold under it while the user picks.
    private var wardrobeMenuOpen = false

    /// The island cat's right-click menu, with only Wardrobe in it for now. True when it was shown (the event is used), false for a right-click anywhere else (it goes on as it did).
    private func showWardrobeMenu(for event: NSEvent) -> Bool {
        // Not mid-drag of the cat (a right-click then goes on as before), and not while the island is hidden.
        guard !inAttachDrag, attachDragStart == nil, state.mode != .hidden, event.window === window, wasInIsland,
              isBotHit(event.locationInWindow, includeSecond: true), let view = window?.contentView else { return false }
        // The Pin menu's hold may still be running from the last pick (releasePinMenuHold): it must not end under this menu.
        wardrobeMenuOpen = true
        pinMenuRelease?.cancel()
        defer { wardrobeMenuOpen = false }
        NSMenu.popUpContextMenu(WardrobeMenuTarget.islandCatMenu(), with: event, for: view)
        return true
    }

    /// A right-click on a project's pill in the expanded overview pops one menu with one item, Pin or Unpin (Projects, P-mac). True when it was shown (the event is used), false for a
    /// right-click anywhere else (it goes on as it did). The pill's frame is SwiftUI's, in the island's own coordinates (y down from the island's top); the click is the window's (AppKit:
    /// y up from the window's bottom, the island glued to the window's top), so the point is the click's x from the island's left and its y measured down from the island's top, as
    /// `isBotHit` places the big cat. The menu reuses the Wardrobe menu's flag, and so its holds (Open on hover, the wing, the outside click, the tuck-away).
    private func showProjectPinMenu(for event: NSEvent) -> Bool {
        guard state.mode == .expanded, state.view == .overview, !inAttachDrag, attachDragStart == nil, event.window === window,
              let panel = window as? IslandPanel, let view = panel.contentView else { return false }
        let island = panel.currentIslandFrame(nw: notchW, nh: notchH)
        let point = CGPoint(x: event.locationInWindow.x - island.minX, y: island.maxY - event.locationInWindow.y)
        guard let id = ProjectsHits.pillFrames.first(where: { $0.value.contains(point) })?.key,
              ProjectsModel.shared.appView().projects.contains(where: { $0.id == id }) else { return false }
        wardrobeMenuOpen = true
        pinMenuRelease?.cancel()
        defer { releasePinMenuHold() }
        let menu = NSMenu()
        let item = NSMenuItem(title: ProjectsLayout.pinTitle(pinned: ProjectsModel.shared.isPinned(id)), action: #selector(ProjectPinTarget.toggle(_:)), keyEquivalent: "")
        item.target = ProjectPinTarget.shared
        item.representedObject = id
        menu.addItem(item)
        NSMenu.popUpContextMenu(menu, with: event, for: view)
        return true
    }

    /// The Pin menu's hold ends one moment after `popUpContextMenu` returns, not with it. The call returns when tracking ends, but the click that picked the item is not over: the item's
    /// action, the mouse-up that follows the press and the poll's next look at a pointer that is no longer over the island all come after it, and the outside click (a press it saw while
    /// the hold was on, a release it judges after) folds the island at any of them when the hold is already gone. 0.5 s is far longer than a release takes and short enough that the
    /// next real click is not lost. One cancellable one-shot, no timer; a Wardrobe menu (or another Pin menu) opened meanwhile cancels it first.
    private var pinMenuRelease: DispatchWorkItem?

    private func releasePinMenuHold() {
        pinMenuRelease?.cancel()
        let item = DispatchWorkItem { [weak self] in
            self?.wardrobeMenuOpen = false
            self?.pinMenuRelease = nil
        }
        pinMenuRelease = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5, execute: item)
    }

    /// The big cat was let go at `mouse` (AppKit's coordinates). A drop on another app's window attaches that window to a chat, exactly as before (not in the App Store build);
    /// a drop on no window places the cat on the desktop (`DesktopCatDrop` decides, and tests it); a drop on the island, or on a window that could not be attached, does nothing.
    private func finishBotDrag(at mouse: NSPoint) {
        let kit = DesktopCatScreens.AppKitScreen.all
        let top = DesktopCatScreens.primaryHeight(kit)
        #if !APPSTORE
        let windowUnder = windowBoundsAtScreenPoint(mouse) != nil
        let context = windowUnder ? windowContextAtPoint(mouse) : nil
        #else
        let windowUnder = false
        #endif
        let onIsland = islandRectOnScreen().insetBy(dx: -6, dy: -6).contains(mouse)
        #if !APPSTORE
        let captured = context != nil
        #else
        let captured = false
        #endif
        switch DesktopCatDrop.decide(point: DesktopCatScreens.spot(fromAppKit: Double(mouse.x), Double(mouse.y), primaryHeight: top), screens: DesktopCatScreens.contract(kit),
                                     size: CatSettingsStore.shared.desktop.size, onIsland: onIsland, windowUnder: windowUnder, contextCaptured: captured, appStore: DesktopCatController.isAppStoreBuild) {
        case .attach:
            #if !APPSTORE
            if let ctx = context {
                state.promptContext = ctx
                ClaudeService.shared.clearConversation(state: state)
                SoundEngine.shared.play("approve")
                NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
                expand(to: .prompt)
            }
            #endif
        case .place(let spot):
            desktop?.dragOut(to: spot)
        case .stayHome:
            break
        }
    }

    /// Whether a click landed on the shelf's badge: only in the compact island, only while the badge is drawn.
    private func clickedShelfBadge(_ event: NSEvent) -> Bool {
        guard state.mode == .compact, ShelfBadge.isShown(compact: true, count: ShelfModel.shared.count, greetingTail: state.greetingTail), let panel = window as? IslandPanel else { return false }
        return ShelfBadge.hitRect(island: panel.currentIslandFrame(nw: notchW, nh: notchH)).contains(event.locationInWindow)
    }

    /// Whether a click landed on the Projects waiting badge: only in the compact island, only while the badge is drawn (the shelf badge's rule, beside it).
    private func clickedProjectsBadge(_ event: NSEvent) -> Bool {
        guard state.mode == .compact, ProjectsLayout.badgeShown(compact: true, waiting: ProjectsModel.shared.appView().waiting, greetingTail: state.greetingTail), let panel = window as? IslandPanel else { return false }
        return ProjectsLayout.badgeHitRect(island: panel.currentIslandFrame(nw: notchW, nh: notchH)).contains(event.locationInWindow)
    }

    /// The Shelf (sub-project G1) opens on its view: from the menu bar, a click on the badge, the shortcut, and after a drop on the Shelf half. Whether the files are still there is asked
    /// now, as the shelf opens, and never in the background.
    func openShelf() {
        ShelfModel.shared.refresh()
        fsm.openedExternally()
        expand(to: .shelf)
    }

    /// The Projects screen (sub-project P-mac) opens from the menu bar's Projects item: the island's bookkeeping, then its view, as the shelf's does.
    func openProjects() {
        fsm.openedExternally()
        expand(to: .projects)
    }

    /// Files that arrived from a drop on the Shelf half (sub-project G1; the flow was already cleared at the drop, `ShelfFlow.afterShelfDrop`, and clearing it again here would end a newer drop's turn):
    /// they go on the shelf, the files received for the drop are removed once the store has copied what it keeps, and the island shows the shelf.
    func shelfDropped(_ incoming: [ShelfIncoming], temp: URL?) {
        ShelfModel.shared.add(incoming)
        if let temp { try? FileManager.default.removeItem(at: temp) }
        openShelf()
    }

    /// The island's rectangle on screen, in AppKit's coordinates (the same rectangle the poll uses for the mouse).
    func islandRectOnScreen() -> CGRect {
        guard let panel = window as? IslandPanel else { return .zero }
        return panel.currentIslandFrame(nw: notchW, nh: notchH).offsetBy(dx: panel.frame.minX, dy: panel.frame.minY)
    }

    /// A click on the desktop cat opens the island at the notch, like a click on the notch.
    func openFromDesktop() {
        CatSleepClock.shared.wake("click")
        guard state.mode != .expanded else { return }
        if fsm.state == .home { expand(to: defaultView()) } else { fsm.click() }
    }

    // MARK: - Drag ghost window (cat follows cursor during drag)

    private func showDragGhost() {
        guard dragGhostPanel == nil else { return }
        // Same size as compact bot: diameter=20 → canvasSize≈33, scale 2× for grab comfort
        let canvasSize: CGFloat = 40 / 0.6      // ~67
        dragGhostSize = canvasSize

        let mouse = NSEvent.mouseLocation
        let s = dragGhostSize
        ghostCurrentOrigin = NSPoint(x: mouse.x - s/2, y: mouse.y - s/2)

        let panel = NSPanel(
            contentRect: NSRect(x: ghostCurrentOrigin.x, y: ghostCurrentOrigin.y, width: s, height: s),
            styleMask: [.borderless, .nonactivatingPanel],
            backing: .buffered,
            defer: false
        )
        panel.backgroundColor = .clear
        panel.isOpaque = false
        panel.hasShadow = false
        panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 4)
        panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
        panel.ignoresMouseEvents = true

        let hosting = NSHostingView(
            rootView: GhostBotView(canvasSize: canvasSize)
        )
        hosting.frame = NSRect(x: 0, y: 0, width: s, height: s)
        panel.contentView = hosting
        panel.alphaValue = 0
        panel.orderFront(nil)
        dragGhostPanel = panel
        AppState.shared.isDraggingBot = true

        // Fade + scale-in handled by GhostBotView SwiftUI animation;
        // also fade in the window itself for extra smoothness
        NSAnimationContext.runAnimationGroup { ctx in
            ctx.duration = 0.18
            ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().alphaValue = 1
        }
    }

    private func hideDragGhost() {
        dragGhostPanel?.close()
        dragGhostPanel = nil
        highlightPanel?.close()
        highlightPanel = nil
        highlightWindowPid = 0
        AppState.shared.isDraggingBot = false
    }

    private func updateDragGhost() {
        guard let panel = dragGhostPanel else { return }
        let s = dragGhostSize
        let mouse = NSEvent.mouseLocation
        // Direct follow — bot is "held", no trailing lag
        ghostCurrentOrigin = NSPoint(x: mouse.x - s/2, y: mouse.y - s/2)
        panel.setFrameOrigin(ghostCurrentOrigin)
    }

    // MARK: - Window highlight overlay (white border on target window during drag)

    private func updateWindowHighlight() {
        let mouse = NSEvent.mouseLocation
        guard let (appKitBounds, pid) = windowBoundsAtScreenPoint(mouse) else {
            // Fade out + close if no window under cursor
            if let old = highlightPanel {
                let captured = old
                highlightPanel = nil
                highlightWindowPid = 0
                NSAnimationContext.runAnimationGroup({ ctx in
                    ctx.duration = 0.12
                    ctx.timingFunction = CAMediaTimingFunction(name: .easeIn)
                    captured.animator().alphaValue = 0
                }, completionHandler: { captured.close() })
            }
            return
        }

        if pid == highlightWindowPid, let existing = highlightPanel {
            // Same window — just track position (windows rarely move, instant is fine)
            existing.setFrame(appKitBounds, display: false)
        } else {
            // New window — close old immediately, fade-in new
            highlightPanel?.close()
            highlightPanel = nil
            highlightWindowPid = pid

            let panel = NSPanel(
                contentRect: appKitBounds,
                styleMask: [.borderless, .nonactivatingPanel],
                backing: .buffered, defer: false
            )
            panel.backgroundColor = .clear
            panel.isOpaque = false
            panel.hasShadow = false
            panel.level = NSWindow.Level(rawValue: Int(CGWindowLevelForKey(.mainMenuWindow)) + 2)
            panel.collectionBehavior = [.canJoinAllSpaces, .stationary, .ignoresCycle]
            panel.ignoresMouseEvents = true

            let hosting = NSHostingView(rootView:
                RoundedRectangle(cornerRadius: 12)
                    .stroke(Color.white.opacity(0.75), lineWidth: 3)
                    .shadow(color: Color.white.opacity(0.5), radius: 16)
                    .padding(2)
                    .ignoresSafeArea()
            )
            hosting.frame = CGRect(origin: .zero, size: appKitBounds.size)
            hosting.autoresizingMask = [.width, .height]
            panel.contentView = hosting
            panel.alphaValue = 0
            panel.orderFront(nil)
            highlightPanel = panel

            NSAnimationContext.runAnimationGroup { ctx in
                ctx.duration = 0.14
                ctx.timingFunction = CAMediaTimingFunction(name: .easeOut)
                panel.animator().alphaValue = 1
            }
        }
    }

    private func windowBoundsAtScreenPoint(_ screenPoint: NSPoint) -> (CGRect, pid_t)? {
        guard let screen = window?.screen ?? NSScreen.main else { return nil }
        let screenMaxY = screen.frame.maxY
        let cgPoint = CGPoint(x: screenPoint.x, y: screenMaxY - screenPoint.y)

        guard let list = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        let ourBundle = Bundle.main.bundleIdentifier ?? ""
        for info in list {
            guard let b = info[kCGWindowBounds as String] as? [String: Any],
                  let x = b["X"] as? CGFloat, let y = b["Y"] as? CGFloat,
                  let w = b["Width"] as? CGFloat, let h = b["Height"] as? CGFloat else { continue }
            guard CGRect(x: x, y: y, width: w, height: h).contains(cgPoint) else { continue }
            let pid = info[kCGWindowOwnerPID as String] as? pid_t ?? 0
            guard let app = NSRunningApplication(processIdentifier: pid),
                  app.bundleIdentifier != ourBundle,
                  app.activationPolicy == .regular else { continue }
            // CG → AppKit: flip Y
            return (CGRect(x: x, y: screenMaxY - y - h, width: w, height: h), pid)
        }
        return nil
    }

    // MARK: - Window context at screen point (for drag-attach)

    private func windowContextAtPoint(_ screenPoint: NSPoint) -> PromptContext? {
        let screen = window?.screen ?? NSScreen.main
        // CGWindowList uses top-left origin; NSEvent.mouseLocation uses bottom-left
        let screenMaxY = screen?.frame.maxY ?? NSScreen.main!.frame.maxY
        let cgPoint = CGPoint(x: screenPoint.x, y: screenMaxY - screenPoint.y)

        guard let windowList = CGWindowListCopyWindowInfo(
            [.optionOnScreenOnly, .excludeDesktopElements], kCGNullWindowID
        ) as? [[String: Any]] else { return nil }

        let ourBundle = Bundle.main.bundleIdentifier ?? ""

        for info in windowList {
            guard let b = info[kCGWindowBounds as String] as? [String: Any],
                  let x = b["X"] as? CGFloat, let y = b["Y"] as? CGFloat,
                  let w = b["Width"] as? CGFloat, let h = b["Height"] as? CGFloat else { continue }
            guard CGRect(x: x, y: y, width: w, height: h).contains(cgPoint) else { continue }

            let pid = info[kCGWindowOwnerPID as String] as? pid_t ?? 0
            guard let app = NSRunningApplication(processIdentifier: pid),
                  app.bundleIdentifier != ourBundle,
                  app.activationPolicy == .regular else { continue }

            return WindowContextCapture.captureActive(from: app)
        }
        return nil
    }

    // MARK: - Coordinate conversion: window (AppKit, y-up) → island coords (y-down, 0,0 = island top-left)

    func windowToIsland(_ loc: CGPoint) -> CGPoint {
        let panelH = window?.frame.height ?? 320
        let panelW = window?.frame.width  ?? 720
        let islandLeft = (panelW - IslandConst.expandedWidth) / 2
        // Island is glued to panel top; its bottom in AppKit = panelH - 176
        return CGPoint(
            x: loc.x - islandLeft,
            y: panelH - loc.y                // AppKit y is from bottom; island y from top
        )
    }

    // MARK: - Helpers

    func defaultView() -> IslandView {
        if state.pendingApproval != nil { return .approval }
        return state.tasks.isEmpty ? .empty : .overview
    }

    func baseMode() -> IslandMode {
        guard state.isPresent else { return .hidden }
        return state.tasks.isEmpty ? .hidden : .compact
    }

    // MARK: - Activity reset (call on any user interaction in island)

    func resetActivity() {
        state.lastActivity = .now
    }

    // MARK: - Finished task pin (5.2s)

    func pinForFinished(taskId: String) {
        state.isPinned = true
        finishedPinTimer?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.state.removeTask(id: taskId)
            self.state.isPinned = false
            self.collapse()
        }
        finishedPinTimer = item
        DispatchQueue.main.asyncAfter(deadline: .now() + 5.2, execute: item)
    }

    // MARK: - Dizzy recovery (triggered by CatEngine.slap via .botDizzy)

    private func handleDizzy() {
        let prevView = state.view
        state.stateOverride = .dizzy
        expand(to: .confused)
        confusedRecoveryTimer?.cancel()
        let recovery = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.state.stateOverride = nil
            if self.state.view == .confused {
                let fallback = self.state.tasks.isEmpty ? IslandView.empty : .overview
                self.state.view = (prevView == .confused) ? fallback : prevView
            }
            NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.happy)
        }
        confusedRecoveryTimer = recovery
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.3, execute: recovery)
    }

    // MARK: - Bot hit test (for slap trigger)

    /// `includeSecond`: a press on cat 2 of Two cats mode counts too (the right-click menu belongs to both big cats; the slap and the drag-out stay cat 1's).
    private func isBotHit(_ windowPoint: CGPoint, includeSecond: Bool = false) -> Bool {
        let s = AppState.shared
        guard !s.desktopPhase.notchEmpty else { return false }   // the big cat is on the desktop: its spot in the notch is empty
        let panelH = window?.frame.height ?? 320
        let panelW = window?.frame.width  ?? 720
        let (islandW, fixedH) = islandSize(mode: s.mode, view: s.view,
                                            progress: s.uploadProgress, nw: notchW, nh: notchH)
        // Chat view resizes dynamically — must match IslandContainer.chatPromptHeight
        let islandH: CGFloat
        if s.mode == .expanded && s.view == .prompt {
            islandH = ChatSizing.islandHeight(messages: s.chatHistory.count)
        } else {
            islandH = fixedH
        }
        let islandMinX = (panelW - islandW) / 2
        let (cx, cy, diameter, _) = botPosition(mode: s.mode, view: s.view,
                                                  islandW: islandW, islandH: islandH,
                                                  uploadProgress: s.uploadProgress, hasNotch: s.hasNotch, display: s.displayMode)
        let radius = (diameter / 0.6) / 2
        // botPosition cy is from island TOP; panel AppKit coords have y=0 at bottom
        // island top in AppKit coords = panelH (island glued to top of panel/screen)
        let botX = islandMinX + cx
        let botY = panelH - cy
        // Two cats mode: where cat 2's circle overlaps cat 1's, the nearer centre wins, and a press that is cat 2's is not on the big cat (it drags nothing out of the notch, slaps nothing).
        // Cat 2's circle is its tap shape in the overview (Ø46) and, like cat 1's, the canvas-sized circle in the compact island.
        var second: CatIslandLayout.HitCircle?
        if s.cast.second != nil, let place = secondCatPlace(state: s, islandW: islandW, islandH: islandH) {
            second = .init(x: Double(islandMinX + place.cx), y: Double(panelH - place.cy), r: Double(place.compact ? place.d / 0.6 / 2 : place.d / 2))
        }
        let first = CatIslandLayout.HitCircle(x: Double(botX), y: Double(botY), r: Double(radius))
        let hit = CatIslandLayout.bigCatPressed(x: Double(windowPoint.x), y: Double(windowPoint.y), cat1: first, cat2: second)
        guard !hit, includeSecond, let second else { return hit }
        return CatIslandLayout.bigCatPressed(x: Double(windowPoint.x), y: Double(windowPoint.y), cat1: second, cat2: first)
    }

    // MARK: - Notch detection (static)

    static func notchScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 }
    }

    static func screenGeometry(for screen: NSScreen) -> IslandScreenGeometry {
        let visibleMenuBarHeight = screen.frame.maxY - screen.visibleFrame.maxY
        // visibleFrame includes the menu bar only while it is visible. Keep a
        // small resting bar when menus auto-hide or the app is in full screen.
        let menuBarHeight = visibleMenuBarHeight > 0
            ? visibleMenuBarHeight : NSStatusBar.system.thickness
        return IslandScreenGeometry(
            screenWidth: screen.frame.width, safeAreaTop: screen.safeAreaInsets.top,
            auxiliaryLeftWidth: screen.auxiliaryTopLeftArea?.width,
            auxiliaryRightWidth: screen.auxiliaryTopRightArea?.width,
            menuBarHeight: menuBarHeight
        )
    }

    nonisolated func cleanup() {
        // Called explicitly before release if needed
    }
}

// MARK: - IslandPanel

final class IslandPanel: NSPanel {
    var notchWidth:  CGFloat = IslandConst.notchWidth
    var notchHeight: CGFloat = IslandConst.notchHeight

    override var canBecomeKey:  Bool { true }
    override var canBecomeMain: Bool { false }

    /// Allow panel to sit in the menu bar / notch area — don't let macOS push it down.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        return frameRect
    }

    func currentIslandFrame(nw: CGFloat, nh: CGFloat) -> CGRect {
        let s = AppState.shared
        let (w, fixedH) = islandSize(mode: s.mode, view: s.view,
                                      progress: s.uploadProgress, nw: nw, nh: nh)
        let h: CGFloat
        if s.mode == .expanded && s.view == .prompt {
            h = ChatSizing.islandHeight(messages: s.chatHistory.count)
        } else {
            h = fixedH
        }
        return CGRect(x: (frame.width - w) / 2, y: frame.height - h, width: w, height: h)
    }
}

// MARK: - Ghost bot view (animated scale-in on appear)

struct GhostBotView: View {
    let canvasSize: CGFloat
    @State private var scale: CGFloat = 0.35

    var body: some View {
        BotCanvasView(state: AppState.shared, cat: AppState.shared.cast.drop)
            .frame(width: canvasSize, height: canvasSize)
            .scaleEffect(scale)
            .onAppear {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.55)) {
                    scale = 1.0
                }
            }
    }
}

// MARK: - Notification names

extension Notification.Name {
    static let triggerEmote     = Notification.Name("notchBuddy.triggerEmote")
    static let triggerSlap      = Notification.Name("notchBuddy.triggerSlap")
    static let botDizzy         = Notification.Name("notchBuddy.botDizzy")
    static let botBlink         = Notification.Name("notchBuddy.botBlink")
    static let botSetTgEs       = Notification.Name("notchBuddy.botSetTgEs")
    static let botGulp          = Notification.Name("notchBuddy.botGulp")
    static let islandAction     = Notification.Name("notchBuddy.islandAction")
    static let islandCollapse   = Notification.Name("notchBuddy.islandCollapse")
    // Island shortcuts → the views that act on them
    static let islandSendMessage           = Notification.Name("notchBuddy.islandSendMessage")
    static let islandNewConversation       = Notification.Name("notchBuddy.islandNewConversation")
    static let islandToggleDiff            = Notification.Name("notchBuddy.islandToggleDiff")
    static let islandActivateCardSelection = Notification.Name("notchBuddy.islandActivateCardSelection")
    static let openFullSettings = Notification.Name("notchBuddy.openFullSettings")
    static let hookReveal       = Notification.Name("notchBuddy.hookReveal")
    static let musicReveal      = Notification.Name("notchBuddy.musicReveal")
    // Greeting ↔ IslandWindowController
    static let greetComplete    = Notification.Name("notchBuddy.greetComplete")
    static let greetingHover    = Notification.Name("notchBuddy.greetingHover")
    static let greetingInterrupt = Notification.Name("notchBuddy.greetingInterrupt")
}

// MARK: - islandSize (takes real notch dimensions)

func islandSize(mode: IslandMode, view: IslandView,
                progress: Double = 0,
                nw: CGFloat = IslandConst.notchWidth,
                nh: CGFloat = IslandConst.notchHeight) -> (CGFloat, CGFloat) {
    switch mode {
    case .hidden:   return (nw, nh)
    case .compact:  return (nw + 160, nh)
    case .expanded:
        let layout = IslandConst.viewLayouts[view]!
        if view == .question, let h = QuestionLayout.height { return (IslandConst.expandedWidth, h) }   // a question with option descriptions needs more room
        // The Claude Code card's expanded section makes the overview taller (Projects, P-mac); every other view is as it was.
        return (IslandConst.expandedWidth, layout.height + (view == .overview ? ProjectsLayout.extraHeight : 0))
    }
}
