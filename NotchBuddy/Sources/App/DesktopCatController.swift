import AppKit
import Combine
import QuartzCore

// The desktop cat (sub-project H): the big cat living on the desktop. This is the app's side of the contract: it owns the trip's phase (`DesktopCatTrip.step` decides, this carries
// out the act), the flight's clock, the window (`DesktopCatPanel`), the mouse, the frame timer (`DesktopCatPacer`) and the links to the island, the store and the hook state. Every
// rule it follows is a pure file with a test program; nothing here is run by one, so `tests/DesktopCatWiringTests.swift` pins where it is called from. Nothing polls: one timer runs
// only while the cat is drawn and visible, at the rate `DesktopCatTrip.fps` says, and the mouse monitors exist only while it is.

@MainActor
final class DesktopCatController: NSObject {
    #if APPSTORE
    static let isAppStoreBuild = true
    #else
    static let isAppStoreBuild = false
    #endif

    /// An emote counts as motion (60 fps) for this long: the longest emote of `EMOUTH` in `cat-core.js` (love and proud), shared with the Windows and Linux app.
    static let emoteMs = 1800.0
    /// The surprised emote of an alert plays this long before the cat flies to the notch.
    static let surpriseMs = 450.0

    private let state: AppState
    private let store: CatSettingsStore
    private weak var island: IslandWindowController?
    private let engine: CatEngine
    private let herd = CatKittenHerd()

    private(set) var phase = DesktopPhase.home {
        didSet { if phase != oldValue { state.desktopPhase = phase } }
    }
    private var flight: DesktopCatTrip.Flight?
    /// The desktop spot (the head centre, contract coordinates) and where the head is now (the flight's position, or the drag's).
    private var spot: DesktopSpot?
    private var position = DesktopSpot(x: 0, y: 0)
    private var cursor = DesktopSpot(x: 0, y: 0)
    private var cursorDist: Double?
    private var frame = DesktopCatFrame(w: 100, h: 100, headX: 50, headY: 50)
    private var lastSlots = DesktopCatTrip.kittenSlots([], side: 1)
    private var screens: [DesktopScreen] = []
    private var primaryHeight = 0.0

    private var panel: DesktopCatPanel?
    private var catView: DesktopCatView?
    private var pacer = DesktopCatPacer()
    private var timer: DispatchSourceTimer?
    private var visibility = DesktopCatVisibility()
    private var monitors: [Any] = []
    private var tokens: [(center: NotificationCenter, token: NSObjectProtocol)] = []
    private var cancellables = Set<AnyCancellable>()
    private var retargetQueued = false
    private var flightDoneItem: DispatchWorkItem?
    /// A change of the kitten list (an arrival or a leave) is motion for 600 ms (`DesktopKittenWatch`).
    private var kittenWatch = DesktopKittenWatch()
    private var lastAlert = false

    private var clicks = DesktopCatClicks(interval: NSEvent.doubleClickInterval)
    private var clickItem: DispatchWorkItem?
    private var dragging = false
    private var grab = DesktopSpot(x: 0, y: 0)
    private var emoteUntil = 0.0
    private var overBody = false
    private var lastSize = DesktopSize.medium

    init(state: AppState = .shared, store: CatSettingsStore = .shared, island: IslandWindowController) {
        self.state = state
        self.store = store
        self.island = island
        engine = CatEngine.live(CatPresets.byID(state.cast.big.cat))
        super.init()
        lastSize = store.desktop.size
        refreshScreens()
    }

    private var nowMs: Double { CACurrentMediaTime() * 1000 }

    // MARK: Start

    /// Subscribes to everything the cat reacts to. Called once, after the island is set up. A cat that was out flies out again once the greeting is over.
    func start() {
        // Something needs the user (an approval, a question, a chat's approval card, a pill in approval or question state) or nothing does any more: only a change is an event.
        lastAlert = alerting
        state.objectWillChange.receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated {
                guard let self, self.alerting != self.lastAlert else { return }
                self.lastAlert = self.alerting
                self.send(self.lastAlert ? .alertOn : .alertOff)
            } }
            .store(in: &cancellables)
        // The Settings switch, the menu-bar item and ⌃⌥D all end up in the store: the cat follows it.
        store.$desktop.dropFirst().removeDuplicates()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] d in MainActor.assumeIsolated { self?.settingsChanged(d) } }
            .store(in: &cancellables)
        // Anything that can change the frame rate (a state, a kitten, sleep) asks again once per run-loop turn; a cat at home ignores it.
        state.objectWillChange.sink { [weak self] _ in MainActor.assumeIsolated { self?.scheduleRetarget() } }.store(in: &cancellables)
        // After the greeting: a cat that was out flies back out.
        state.$view.combineLatest(state.$greetingTail).filter { $0.0 != .greeting && !$0.1 }.first()
            .receive(on: DispatchQueue.main)
            .sink { [weak self] _ in MainActor.assumeIsolated { if self?.store.desktop.on == true { self?.send(.launch) } } }
            .store(in: &cancellables)
        observe(NotificationCenter.default, NSApplication.didChangeScreenParametersNotification) { [weak self] in
            guard let self else { return }
            self.refreshScreens()
            // The cached spot follows the screens now, whatever the phase: the machine ignores a screen change at home, at the alert and on the way back, and a flight out reads the spot.
            self.spot = self.store.desktop.spot(on: self.screens)
            if let s = self.spot, let f = self.flight { self.flight = f.withDesktopEnd(s) }
            self.send(.screensChanged)
        }
        observe(NSWorkspace.shared.notificationCenter, NSWorkspace.activeSpaceDidChangeNotification) { [weak self] in self?.occlusionChanged() }
        // The screen locked or the displays asleep hide the cat. The Mac's notifications are observed once, by the PresenceMonitor the sidekick shares (a lock that comes as two notifications is one event).
        PresenceMonitor.shared.subscribe("desktopCat") { [weak self] event in
            guard let self else { return }
            switch event {
            case .lock: self.visibility.locked = true
            case .unlock: self.visibility.locked = false
            case .displayOff: self.visibility.screensAsleep = true
            case .displayOn: self.visibility.screensAsleep = false
            case .sleep, .wake: return
            }
            self.visibilityChanged()
        }
        PresenceMonitor.shared.start()
    }

    private func observe(_ center: NotificationCenter, _ name: Notification.Name, _ handler: @escaping @MainActor () -> Void) {
        let token = center.addObserver(forName: name, object: nil, queue: .main) { _ in MainActor.assumeIsolated { handler() } }
        tokens.append((center, token))
    }

    /// What the notch calls an alert: `pendingApproval` or `pendingQuestion`, a chat's approval card (the GitHub build's Claude Code chat) and any pill in the approval or question state.
    private var alerting: Bool {
        #if !APPSTORE
        let chat = state.chatApproval != nil
        #else
        let chat = false
        #endif
        return DesktopCatTrip.alert(pendingApproval: state.pendingApproval != nil, pendingQuestion: state.pendingQuestion != nil, chatApproval: chat,
                                    pillStates: state.tasks.map { CatState(rawValue: $0.state.rawValue) ?? .idle }, fileCatch: fileCatching, transferOffer: state.linkOfferPending)
    }

    /// A file is on its way into the island: dragged over it, or its drop flow (the upload, uploading and choose views) is on screen. To the desktop cat that is an alert: it flies to the notch to
    /// catch the file, the island's catch plays with that cat (the canvas draws none of its own while the notch spot is empty), and it flies back when the flow is over. A drop that is waiting
    /// for the cat keeps `fileDragOver` true (`FileDropHandler.handle` clears it once the catch begins), so the alert holds and the cat does not turn round. The island keeps the drop view open
    /// after a drag that leaves without a drop, so the cat stays until the island folds it.
    private var fileCatching: Bool {
        state.fileDragOver || (UploadSequenceEngine.shared.isActive && state.mode == .expanded && [IslandView.upload, .uploading, .choose].contains(state.view))
    }

    // MARK: Controls (the menu-bar item, ⌃⌥D, the Settings switch and the cat's own menu all end here)

    /// Out if it is home, home if it is out: the menu-bar item and ⌃⌥D.
    func toggle() { store.setDesktopOn(!phase.on) }
    func sendHome() { send(.sendHome) }
    /// The big cat was dropped on empty desktop at `spot` (`DesktopCatDrop`).
    func dragOut(to spot: DesktopSpot) { send(.dragOut(spot)) }
    /// "Bring the cat home" while it is out, "Cat on the desktop" while it is home: the menu-bar item's title.
    var isOut: Bool { phase.on }

    private func settingsChanged(_ d: DesktopCatSettings) {
        if d.on == store.desktop.on, d.on != phase.on { send(.toggle) }   // a stale emission (a newer flip is already queued) is ignored, so queued flips cannot ping-pong
        if d.size != lastSize {
            lastSize = d.size
            if let s = spot, phase.drawn { spot = DesktopCatSpots.clampSpot(s, screens, size: d.size); if let c = spot { store.rememberDesktopSpot(c, on: screens) } }
            if flight == nil, let s = spot { position = s }
            tick()
        }
    }

    // MARK: The trip

    /// One event into the machine, and its act carried out.
    func send(_ event: DesktopEvent) {
        let was = phase
        let r = DesktopCatTrip.step(phase, event)
        phase = r.state
        // A drag lives only on the desktop: a phase change away from it (an approval, ⌃⌥D, a dock) ends it, since no mouse-up will reach the view once the cat is gone.
        if phase != .onDesktop { dragging = false; clickItem?.cancel() }
        if let act = r.act { perform(act, event) }
        if phase.on != was.on { store.setDesktopOn(phase.on) }   // what Settings stores; quitting mid-flight home leaves the cat home
        updateMonitors()
        retarget()
    }

    private func perform(_ act: DesktopAct, _ event: DesktopEvent) {
        let now = nowMs
        switch act {
        case .place:
            if case .dragOut(let p) = event, let c = DesktopCatSpots.clampSpot(p, screens, size: store.desktop.size) {
                spot = c; position = c; flight = nil
                store.rememberDesktopSpot(c, on: screens)
                show()
                emote(.happy)
            }
        case .flyOut:
            let target = store.desktop.spot(on: screens) ?? DesktopSpot(x: 600, y: 300)   // the remembered spot for the screens now, else the first spot ever
            spot = target
            flight = .start(.out, notch: notchSpot(), desktop: target, at: now)
            position = notchSpot()
            show()
        case .flyHome:
            let from = position
            flight = DesktopCatTrip.Flight(from: from, to: notchSpot(), dir: .in, startMs: now)
            show()
        case .retract:
            emote(.surprised)
            flight = DesktopCatTrip.Flight(from: position, to: notchSpot(), dir: .in, startMs: now + Self.surpriseMs)
        case .turn:
            flight = (flight ?? DesktopCatTrip.Flight(from: position, to: notchSpot(), dir: .in, startMs: now)).turned(at: now)
        case .keep:
            break
        case .land:
            flight = nil
            if let s = spot { position = s }
        case .dock, .goHome:
            flight = nil
            hide()
        case .move:
            if case .move(let p) = event {
                spot = DesktopCatSpots.clampSpot(p, screens, size: store.desktop.size)
                if let c = spot { position = c; store.rememberDesktopSpot(c, on: screens) }
            }
        case .resettle:
            spot = store.desktop.spot(on: screens)
            if let s = spot {
                if let f = flight { flight = f.withDesktopEnd(s) } else { position = s }
            }
        }
        tick()
    }

    /// The big cat's place in the notch, in the contract's coordinates, for the island as it is now (compact, or open for an alert).
    private func notchSpot() -> DesktopSpot {
        // The island's own screen: its panel is placed once, at launch, and never moved, so the focused screen may be another one.
        let screen = island?.window?.screen ?? IslandWindowController.notchScreen() ?? NSScreen.screens[0]
        let (islandW, islandH) = islandSize(mode: state.mode, view: state.view, progress: state.uploadProgress, nw: state.notchWidth, nh: state.notchHeight)
        let h: CGFloat = (state.mode == .expanded && state.view == .prompt) ? ChatSizing.islandHeight(messages: state.chatHistory.count) : islandH
        let (cx, cy, _, _) = botPosition(mode: state.mode, view: state.view, islandW: islandW, islandH: h, uploadProgress: state.uploadProgress, hasNotch: state.hasNotch, display: state.displayMode)
        let f = screen.frame
        let frame = DesktopRect(x: Double(f.minX), y: primaryHeight - Double(f.maxY), w: Double(f.width), h: Double(f.height))
        return DesktopCatLayout.notchSpot(screenFrame: frame, islandW: Double(islandW), cx: Double(cx), cy: Double(cy))
    }

    private func refreshScreens() {
        let list = DesktopCatScreens.AppKitScreen.all
        primaryHeight = DesktopCatScreens.primaryHeight(list)
        screens = DesktopCatScreens.contract(list)
    }

    // MARK: The window

    private func ensurePanel() -> DesktopCatPanel {
        if let p = panel { return p }
        let p = DesktopCatPanel(), v = DesktopCatView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
        v.controller = self
        p.contentView = v
        panel = p; catView = v
        let token = NotificationCenter.default.addObserver(forName: NSWindow.didChangeOcclusionStateNotification, object: p, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.occlusionChanged() }
        }
        tokens.append((NotificationCenter.default, token))
        return p
    }

    private func show() {
        let p = ensurePanel()
        layoutWindow()
        p.orderFrontRegardless()
        // AppKit updates occlusionState a turn after ordering front: read it then, so a cat shown behind a fullscreen Space is not left thinking it is visible.
        DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated {
            guard let self, self.phase.drawn, let w = self.panel else { return }
            self.visibility.covered = !w.occlusionState.contains(.visible)
            self.visibilityChanged()
        } }
    }

    private func hide() {
        dragging = false
        clickItem?.cancel()
        panel?.ignoresMouseEvents = true
        panel?.orderOut(nil)
        overBody = false
    }

    /// The window around the cat, at the head's position: sized for the cat, its badge and its kittens, and no larger.
    private func layoutWindow() {
        guard let p = panel, let v = catView else { return }
        let side = DesktopCatLayout.side(of: position, screens: screens)
        lastSlots = DesktopCatTrip.kittenSlots(kittensNow(), side: side)
        let f = DesktopCatLayout.frame(d: store.desktop.size.d, slots: lastSlots)
        let o = DesktopCatLayout.origin(spot: position, frame: f, primaryHeight: primaryHeight)
        let rect = NSRect(x: o.x, y: o.y, width: f.w, height: f.h)
        frame = f
        if p.frame != rect { p.setFrame(rect, display: false); v.frame = NSRect(origin: .zero, size: rect.size) }
    }

    private func kittensNow() -> [CatKittens.Kitten] { state.cast.big.pill.map { state.kittenView($0, at: nowMs) } ?? [] }

    // MARK: Frames

    /// One frame: the flight moves on, the engines move on, the window follows the head, and the view is asked to draw.
    private func tick() {
        guard phase.drawn else { return }
        let now = nowMs
        if let f = flight {
            let f2 = f.withNotchEnd(notchSpot())
            flight = f2
            position = f2.position(at: now)
            if f2.isDone(at: now) { send(.flightDone); return }
        }
        prepareEngine()
        engine.update(dt: CatEngine.frameDelta(now: CACurrentMediaTime(), last: engine.lastTime, maxDt: 0.25))   // a slow frame (5 fps) must not slow the cat down
        layoutWindow()
        catView?.needsDisplay = true
        retarget()
    }

    /// The cat shows what the big cat shows: the cast's coat, the role's state, the working agent's colour as a collar, the music dance, and where the cursor is.
    private func prepareEngine() {
        engine.useCharacter(state.cast.big.cat)
        engine.setState(state.effectiveState)
        engine.collar = CatRules.bigCatCollar(colour: state.focusTask?.color, state: CatState(rawValue: state.effectiveState.rawValue) ?? .idle)
        engine.setDancing(dancing)
        let look = CatGeometry.cursorLook(dx: cursor.x - position.x, dy: cursor.y - position.y)
        engine.lookX = look.x
        engine.lookY = look.y
    }

    /// The Apple Music dance, as the notch's big cat does it (not in the App Store build).
    private var dancing: Bool {
        #if !APPSTORE
        guard state.musicPlaying, state.activeIntegrations.contains("integration_music") else { return false }
        return [BotState.idle, .working, .thinking, .searching, .finished].contains(state.effectiveState)
        #else
        return false
        #endif
    }

    func draw(_ cg: CGContext, dpr: Double) {
        guard phase.drawn else { return }
        let pillColour = state.cast.big.pill.flatMap { id in state.tasks.first { $0.id == id }?.color }
        let scene = DesktopCatDraw.Scene(d: store.desktop.size.d, head: (frame.headX, frame.headY), slots: lastSlots, parentCat: state.cast.big.cat, colour: pillColour, dpr: dpr)
        DesktopCatDraw.draw(cg, engine, scene, herd: herd, now: { CACurrentMediaTime() * 1000 }) { e in
            e.update(dt: CatEngine.frameDelta(now: CACurrentMediaTime(), last: e.lastTime, maxDt: 0.25))
        }
    }

    private func emote(_ e: BotEmote) {
        engine.triggerEmote(e)
        emoteUntil = nowMs + Self.emoteMs
        scheduleRetarget()
    }

    // MARK: The frame rate (nothing polls)

    private func scheduleRetarget() {
        guard phase.drawn || timer != nil, !retargetQueued else { return }
        retargetQueued = true
        DispatchQueue.main.async { [weak self] in MainActor.assumeIsolated { self?.retargetQueued = false; self?.retarget() } }
    }

    /// Asks `DesktopCatTrip.fps` what the cat is doing, and re-arms the one timer only when the answer changed.
    private func retarget() {
        let now = nowMs
        let busy = CatState(rawValue: state.effectiveState.rawValue)?.isBusy ?? false
        let input = DesktopCatTrip.FpsInput(phase: phase, hidden: visibility.hidden, dragging: dragging, emote: now < emoteUntil,
                                            kittenMotion: kittenWatch.observe(kittensNow(), now: now), dance: dancing, asleep: state.catAsleep,
                                            working: busy, cursorDist: cursorDist)
        arm(DesktopCatTrip.fps(input))
        // A flight that ends while the cat cannot be seen still ends: one one-shot for its end, not a poll.
        flightDoneItem?.cancel(); flightDoneItem = nil
        if timer == nil, let f = flight, phase.flight {
            let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self?.send(.flightDone) } }
            flightDoneItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0.01, (f.startMs + DesktopCatTrip.flightMs - nowMs) / 1000), execute: item)
        }
    }

    /// The one timer: replaced only when the target changes (`DesktopCatPacer`), cancelled at 0.
    private func arm(_ fps: Double) {
        switch pacer.target(fps) {
        case .none: break
        case .stop:
            timer?.cancel(); timer = nil
        case .arm(let interval, let leeway):
            timer?.cancel()
            let t = DispatchSource.makeTimerSource(queue: .main)
            t.schedule(deadline: .now() + interval, repeating: interval, leeway: .milliseconds(Int(leeway * 1000)))
            t.setEventHandler { [weak self] in MainActor.assumeIsolated { self?.tick() } }
            t.resume()
            timer = t
        }
    }

    // MARK: Visibility

    private func occlusionChanged() {
        visibility.covered = panel.map { !$0.occlusionState.contains(.visible) } ?? false
        visibilityChanged()
    }

    private func visibilityChanged() {
        updateMonitors()
        retarget()
        if !visibility.hidden { tick() }
    }

    // MARK: The mouse

    /// The mouse monitors exist only while the cat is drawn and can be seen: a mouse-moved event monitor, not a 60 Hz timer.
    private func updateMonitors() {
        let want = phase.drawn && !visibility.hidden
        if want && monitors.isEmpty {
            let moved: @Sendable (NSEvent) -> Void = { [weak self] _ in MainActor.assumeIsolated { self?.mouseMoved() } }
            if let g = NSEvent.addGlobalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: moved) { monitors.append(g) }
            if let l = NSEvent.addLocalMonitorForEvents(matching: [.mouseMoved, .leftMouseDragged], handler: { e in moved(e); return e }) { monitors.append(l) }
            mouseMoved()
        } else if !want && !monitors.isEmpty {
            monitors.forEach { NSEvent.removeMonitor($0) }
            monitors = []
            panel?.ignoresMouseEvents = true
            overBody = false
            cursorDist = nil
        }
    }

    private func mouseSpot() -> DesktopSpot {
        let m = NSEvent.mouseLocation
        return DesktopCatScreens.spot(fromAppKit: Double(m.x), Double(m.y), primaryHeight: primaryHeight)
    }

    /// Takes the mouse only over the body; a hover wakes a sleeping cat; the distance feeds the frame rate.
    private func mouseMoved() {
        cursor = mouseSpot()
        let rel = DesktopSpot(x: cursor.x - position.x, y: cursor.y - position.y)
        cursorDist = hypot(rel.x, rel.y)
        let over = phase.drawn && DesktopCatLayout.hits(rel, d: store.desktop.size.d, slots: lastSlots, badge: engine.badge != nil)
        if over != overBody || dragging {
            overBody = over
            panel?.ignoresMouseEvents = !(over || dragging)
            if over { CatSleepClock.shared.wake("hover") }
        }
        scheduleRetarget()
    }

    func mouseDown(_ event: NSEvent) {
        CatSleepClock.shared.wake("click")
        cursor = mouseSpot()
        grab = DesktopSpot(x: cursor.x - position.x, y: cursor.y - position.y)
        handle(clicks.down(at: event.timestamp, cursor))
    }

    func mouseDragged(_ event: NSEvent) { cursor = mouseSpot(); handle(clicks.dragged(cursor)) }

    func mouseUp(_ event: NSEvent) {
        cursor = mouseSpot()
        handle(clicks.up(at: event.timestamp, cursor))
        if let until = clicks.waitUntil {   // a lone click acts after one double-click interval: one one-shot, not a poll
            clickItem?.cancel()
            let item = DispatchWorkItem { [weak self] in MainActor.assumeIsolated { self.map { $0.handle($0.clicks.timer(at: ProcessInfo.processInfo.systemUptime)) } } }
            clickItem = item
            DispatchQueue.main.asyncAfter(deadline: .now() + max(0, until - event.timestamp), execute: item)
        }
    }

    private func handle(_ outs: [DesktopCatClicks.Out]) {
        for out in outs {
            switch out {
            case .dragBegan:
                clickItem?.cancel()
                guard phase == .onDesktop else { break }   // a cat in flight cannot be picked up
                dragging = true
                retarget()
            case .dragMoved(let p):
                guard dragging else { break }
                position = DesktopSpot(x: p.x - grab.x, y: p.y - grab.y)
                tick()
            case .dragEnded(let p):
                guard dragging else { break }
                dragging = false
                let drop = DesktopSpot(x: p.x - grab.x, y: p.y - grab.y)
                if onIsland(p) { send(.sendHome) } else { send(.move(drop)) }   // let go on the notch: home; else the spot is clamped and saved
                panel?.ignoresMouseEvents = true; overBody = false
                mouseMoved()
            case .click:
                emote(.happy)
                island?.openFromDesktop()
            case .doubleClick:
                clickItem?.cancel()
                send(.sendHome)
            }
        }
    }

    private func onIsland(_ p: DesktopSpot) -> Bool {
        guard let r = island?.islandRectOnScreen() else { return false }
        let m = DesktopCatScreens.appKit(p, primaryHeight: primaryHeight)
        return r.insetBy(dx: -6, dy: -6).contains(CGPoint(x: m.x, y: m.y))
    }

    // MARK: The right-click menu

    func showMenu(with event: NSEvent, in view: NSView) {
        let shortcut = ShortcutLogic.isEnabled(.desktop) ? ShortcutLogic.displayString(for: ShortcutLogic.hotKey(for: .desktop)) : nil
        let menu = NSMenu()
        func add(_ entries: [DesktopCatMenu.Entry], to menu: NSMenu) {
            for e in entries {
                switch e {
                case .separator: menu.addItem(.separator())
                case .note(let text): let i = NSMenuItem(title: text, action: nil, keyEquivalent: ""); i.isEnabled = false; menu.addItem(i)
                case .action(let title, let a, let checked):
                    let i = NSMenuItem(title: title, action: #selector(menuPicked(_:)), keyEquivalent: "")
                    i.target = self; i.tag = Self.tag(a); i.state = checked ? .on : .off
                    menu.addItem(i)
                case .submenu(let title, let sub):
                    let i = NSMenuItem(title: title, action: nil, keyEquivalent: ""), m = NSMenu(title: title)
                    add(sub, to: m); i.submenu = m; menu.addItem(i)
                }
            }
        }
        add(DesktopCatMenu.entries(size: store.desktop.size, shortcut: shortcut, outfit: store.wardrobe.outfit, autoToday: Wardrobe.autoOutfit(WardrobeClock.appToday())), to: menu)
        NSMenu.popUpContextMenu(menu, with: event, for: view)
    }

    private static func tag(_ a: DesktopCatMenu.Action) -> Int {
        switch a {
        case .openNotch: return 1
        case .sendHome: return 2
        case .size(let s): return 10 + DesktopSize.allCases.firstIndex(of: s)!
        case .outfit(let id): return WardrobeMenuTarget.tag(for: id)   // 100 to 117
        }
    }

    @objc private func menuPicked(_ item: NSMenuItem) {
        switch item.tag {
        case 1: island?.openFromDesktop()
        case 2: send(.sendHome)
        case 10...12: store.setDesktopSize(DesktopSize.allCases[item.tag - 10])
        default: if let id = WardrobeMenuTarget.id(forTag: item.tag) { store.setOutfit(id) }   // Wardrobe ▸ (sub-project I): tags 100 to 117
        }
    }
}
