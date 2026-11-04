import Foundation

/// Pure 4-state FSM for island open/close logic.
/// No AppKit / AppState dependencies — communicates via `onTransition`.
@MainActor
final class IslandStateMachine {

    enum State: Equatable {
        case hidden   // island invisible (notch size)
        case petit    // compact island (notch + ears)
        case home     // expanded, overview
        case hello   // expanded, greeting animation
    }

    private(set) var state: State = .hidden

    /// Fired on every transition: (from, to)
    var onTransition: ((State, State) -> Void)?

    /// When non-nil and returns true, timers and mouse-leave never auto-collapse or hide the island.
    var isHeldOpen: (() -> Bool)?

    /// home → petit delay (seconds). Override for debug.
    var homeToPetitDelay: TimeInterval = 15
    /// notchmeow → petit delay after greeting animation ends (no hover). ~0.6s syncs with canvas collapse.
    var greetAutoCollapseDelay: TimeInterval = 0.6
    /// notchmeow → petit delay when mouse is hovering over the greeting.
    var greetHoverCollapseDelay: TimeInterval = 10

    /// Opt-in (Settings → General → Behavior): hovering the island opens it, and an island opened that way folds shortly after the pointer leaves. Off: hover only peeks (petit).
    var openOnHover = false
    /// The pointer must stay over the island this long (s) before Open on hover opens it; leaving earlier cancels it. The usual hover peek is not delayed.
    var hoverDwell: TimeInterval = 0.15
    /// How the dwell timer is armed: one one-shot `DispatchWorkItem` per hover. A test replaces it with a clock it turns by hand.
    var armHoverOpen: (TimeInterval, DispatchWorkItem) -> Void = { delay, item in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item) }
    private var hoverOpenWork: DispatchWorkItem?
    /// Holds that apply to Open on hover only (a waiting question, a pinned island): while one is true hover neither opens the island nor folds a hover-opened one.
    /// `isHeldOpen` is left as it was, so with the switch off nothing differs.
    var isHoverHeld: (() -> Bool)?
    /// Grace period after the pointer leaves a hover-opened island (no flicker at the edge).
    var hoverCloseDelay: TimeInterval = 0.6
    /// True while the island is open because of a hover, until the user clicks inside it.
    private(set) var openedByHover = false

    // Tuck away (Settings → General → Behavior → Tuck the island away): when the compact island hides by itself. "Never" (the default) keeps it up. A time hides it once nothing is
    // live and that time has passed since the last activity (a hook event or an alert). The pointer leaving the island (a wing fold included) only re-arms the one timer; it neither starts nor shortens the count.
    var tuckAway: IslandTuckAway.Choice = .never {
        didSet { if state == .petit { scheduleTuck() } }
    }
    /// Whether an agent is live right now (`IslandTuckAway.isLive`), set by the app when it changes (`setLive`). A live agent keeps the compact island up.
    private(set) var live = false
    /// The last hook event or alert (`agentActivity`), on the clock `now`. Starts at launch, so a fresh island is not due at once.
    private(set) var lastActivity: TimeInterval
    /// The clock the tuck-away rule reads (seconds, monotonic). A test replaces it.
    var now: () -> TimeInterval
    /// How the tuck-away timer is armed: one one-shot `DispatchWorkItem`. A test replaces it with a clock it turns by hand.
    var armTuck: (TimeInterval, DispatchWorkItem) -> Void = { delay, item in DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item) }
    /// The pointer is over the island (`mouseEntered` and `mouseLeft`): the compact island is not hidden under it.
    private var pointerInside = false

    private var petitHideWork: DispatchWorkItem?
    private var homeCollapseWork: DispatchWorkItem?
    private var greetCollapseWork: DispatchWorkItem?

    init() {
        let clock: () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }
        now = clock
        lastActivity = clock()
    }

    // MARK: – Inputs

    /// App launched or debug "launch greeting"
    func launch() {
        cancelTimers()
        transition(to: .hello)
    }

    /// Mouse entered the island notch area
    func mouseEntered() {
        pointerInside = true
        switch state {
        case .hidden:
            if isHeldOpen?() == true {
                // Island already expanded by an external call — sync FSM state without transition
                state = .home
            } else {
                cancelTimers()
                transition(to: .petit)
            }
        case .petit:
            petitHideWork?.cancel()
            petitHideWork = nil
        case .home:
            homeCollapseWork?.cancel()
            homeCollapseWork = nil
        case .hello:
            // Mouse hovering during greeting — cancel short auto-collapse, extend to hover delay
            scheduleGreetCollapse(delay: greetHoverCollapseDelay)
        }
        hoverResume()
    }

    /// Open on hover: the island opens once the pointer has stayed `hoverDwell`. Not while a card holds it (the switch above already opened it as an ordinary open island).
    /// Also called on its own when a hover-only hold (the pointer on a wing of the compact island) ends while the pointer is still over the island, so there is no new enter edge: it
    /// arms the dwell again and does nothing else (no peek, no greeting logic). `scheduleHoverOpen` cancels the pending item before it arms a new one: never two at a time.
    func hoverResume() {
        if openOnHover, state == .hidden || state == .petit, isHeldOpen?() != true, isHoverHeld?() != true { scheduleHoverOpen() }
    }

    private func scheduleHoverOpen() {
        hoverOpenWork?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.state == .hidden || self.state == .petit, self.isHeldOpen?() != true, self.isHoverHeld?() != true else { return }
            self.cancelTimers()
            self.openedByHover = true
            self.transition(to: .home)
        }
        hoverOpenWork = item
        armHoverOpen(hoverDwell, item)
    }

    /// Mouse left the island notch area
    func mouseLeft() {
        pointerInside = false
        hoverOpenWork?.cancel(); hoverOpenWork = nil   // leaving before the dwell is over cancels the open
        switch state {
        case .hidden:
            break
        case .petit:
            scheduleTuck()
        case .home:
            if isHeldOpen?() != true { scheduleHomeCollapse() }
        case .hello:
            if isHeldOpen?() != true {
                // Interrupt greeting immediately → compact (overrides 10s auto-collapse)
                greetCollapseWork?.cancel(); greetCollapseWork = nil
                transition(to: .petit)
            }
        }
    }

    /// Compact island clicked.
    /// Also accepts `.hidden`: after an alert the island can be on screen while the
    /// FSM never saw the mouse enter (it was already there), and the click must still open it.
    func click() {
        openedByHover = false
        guard state == .petit || state == .hidden else { return }
        cancelTimers()
        transition(to: .home)
    }

    /// The app hid the island on its own (e.g. `AppState.syncMode()` when the last
    /// task ends). Mirror it without side effects, so the next hover peeks again
    /// instead of being swallowed by a FSM that still thinks the island is `.petit`.
    func hiddenExternally() {
        guard state == .petit else { return }
        cancelTimers()
        state = .hidden
    }

    /// The app expanded the island externally (hookExpand for an alert).
    /// Cancel timers and sync state to `.home` without firing `onTransition`, so the
    /// next hover/mouseLeft behave correctly instead of collapsing the island.
    func openedExternally() {
        cancelTimers()
        openedByHover = false
        guard state != .home && state != .hello else { return }
        state = .home
    }

    /// The app folded the island itself (Escape, Settings, OK button, auto-close).
    /// Move to `.petit` right away so hover and click keep working; waiting for the
    /// 15 s home timer left the island compact on screen while the FSM still said `.home`.
    func collapse() {
        openedByHover = false
        guard state == .home || state == .hello else { return }
        cancelTimers()
        transition(to: .petit)
    }

    /// Greeting animation finished (called at T.end ≈ 4.60 s).
    /// Schedules auto-collapse. Does not override a longer hover timer already running.
    func greetComplete() {
        guard state == .hello else { return }
        // If mouse entered before this fires (hover timer already running), don't override it
        if greetCollapseWork == nil {
            scheduleGreetCollapse(delay: greetAutoCollapseDelay)
        }
    }

    private func scheduleGreetCollapse(delay: TimeInterval) {
        greetCollapseWork?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.state == .hello else { return }
            self.transition(to: .petit)
        }
        greetCollapseWork = item
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// Non-alert work event: show compact from hidden (HookServer reveal). The transition arms the tuck-away timer.
    func reveal() {
        guard state == .hidden else { return }
        cancelTimers()
        transition(to: .petit)
    }

    /// A hook event or an alert reached the app (`AppState.touchPill`), or a click on the island (`userInteracted`): the tuck-away count starts again from now, and a compact island that is up re-arms its one timer.
    func agentActivity() {
        lastActivity = now()
        if state == .petit { scheduleTuck() }
    }

    /// The app's live state changed (`IslandTuckAway.isLive`). Only a change counts; a compact island that is up re-arms its timer for what is left.
    func setLive(_ value: Bool) {
        guard value != live else { return }
        live = value
        if state == .petit { scheduleTuck() }
    }

    // MARK: – Timers

    /// The compact island's one timer (`petitHideWork`), armed for the rule's time. Only while it is up, the pointer is off it and no hold stands; nothing is armed for "Never" or while something is live.
    /// Each call replaces the last, so the timer always reflects the newest activity, live state, setting, pointer and hold.
    /// Called by `IslandWindowController` when a hold flips or a shelf hold's end time passes: a due island then hides at once when nothing holds it. Not a poll.
    func scheduleTuck() {
        petitHideWork?.cancel(); petitHideWork = nil
        guard state == .petit, !pointerInside, !(isHeldOpen?() ?? false),
              let delay = IslandTuckAway.hideDelay(tuckAway, lastActivity: lastActivity, now: now(), live: live) else { return }
        let item = DispatchWorkItem { [weak self] in
            guard let self else { return }
            self.petitHideWork = nil
            guard self.state == .petit, !(self.isHeldOpen?() ?? false) else { return }
            // Decided again now. A timer can fire a moment before its time, and then it is armed again for what is left.
            if IslandTuckAway.hideDelay(self.tuckAway, lastActivity: self.lastActivity, now: self.now(), live: self.live) == 0 {
                self.transition(to: .hidden)
            } else {
                self.scheduleTuck()
            }
        }
        petitHideWork = item
        armTuck(delay, item)
    }

    private func scheduleHomeCollapse() {
        homeCollapseWork?.cancel()
        let item = DispatchWorkItem { [weak self] in
            guard let self, self.state == .home, !(self.isHeldOpen?() ?? false) else { return }
            // A question or a pin holds a hover-opened island: it stays, as an ordinary open island.
            if self.openedByHover, self.isHoverHeld?() == true { self.openedByHover = false; return }
            self.openedByHover = false
            self.transition(to: .petit)
        }
        homeCollapseWork = item
        let delay = openedByHover ? hoverCloseDelay : homeToPetitDelay
        DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
    }

    /// The user clicked inside the island: a hover-opened island now stays like any open island (the normal auto-close) instead of folding as soon as the pointer leaves.
    func userInteracted() {
        agentActivity()   // a click on the island is activity: the tuck-away count starts again
        openedByHover = false
    }

    func cancelTimers() {
        petitHideWork?.cancel();    petitHideWork = nil
        homeCollapseWork?.cancel(); homeCollapseWork = nil
        greetCollapseWork?.cancel(); greetCollapseWork = nil
        hoverOpenWork?.cancel(); hoverOpenWork = nil
    }

    private func transition(to new: State) {
        guard new != state else { return }
        let old = state
        state = new
        onTransition?(old, new)
        if new == .petit { scheduleTuck() }   // the compact island is up: its tuck-away timer starts (nothing while the pointer is on it)
    }

}
