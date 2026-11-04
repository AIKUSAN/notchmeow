import Foundation

// The small rules around the cat that are not drawing and not motion: the work clock that earns zoomies, the sleep timer, what wakes
// a sleeping cat, and which tool names mean "searching". Port of the "Rules" section of design/prototype/cat-core.js;
// tests/fixtures/cat/sequence-cases.json and search-tools.json pin them.

/// The eleven agent states a cat can be in. The raw values are the strings the contract uses.
enum CatState: String, CaseIterable, Sendable {
    case idle, working, thinking, searching, approval, question, error, finished, ratelimit, sleeping, dizzy

    /// Working, thinking and searching are the states that count as work.
    var isBusy: Bool { self == .working || self == .thinking || self == .searching }
}

enum CatRules {
    /// The refused file's two numbers that more than one place waits on: after the file reaches the cat's mouth it takes this long (ms) to start heaving,
    /// and its hairball then lasts this long. The engine plays them and the drop view's refusal note appears when they are over, so both read these.
    static let gagMs = 120.0, hairballMs = 2400.0

    /// An agent that finishes after this much working, thinking or searching earns zoomies (ms). The prototype page shortens it to 12 s.
    static let zoomAfterMs = 5.0 * 60 * 1000

    /// The work clock. `busySince` is nil while no run is open; `workedFor` is how long the last finished run lasted.
    struct WorkClock: Equatable {
        var busySince: Double?
        var workedFor: Double
        init(busySince: Double? = nil, workedFor: Double = 0) { self.busySince = busySince; self.workedFor = workedFor }
    }

    /// Working, thinking and searching keep the clock running; approval and question pauses neither stop nor reset it;
    /// every other state ends the run and stores how long it lasted in `workedFor` (never negative, even if the clock steps back).
    /// Pure: pass the clock in, get the next one back.
    static func workClockStep(_ clock: WorkClock, state: CatState, nowMs: Double) -> WorkClock {
        var c = clock
        if state.isBusy {
            if c.busySince == nil { c.busySince = nowMs }
        } else if state != .approval && state != .question {
            c.workedFor = c.busySince.map { max(0, nowMs - $0) } ?? 0
            c.busySince = nil
        }
        return c
    }

    static func zoomiesOnFinish(workedForMs: Double, thresholdMs: Double = zoomAfterMs) -> Bool { workedForMs >= thresholdMs }

    /// An idle cat falls asleep after this long with no agent event (ms).
    static let sleepAfterMs = 10.0 * 60 * 1000

    /// Milliseconds until the cat should fall asleep, for arming a one-shot timer (no polling): ten minutes after the last agent event.
    /// Only an idle cat sleeps, so any other state (approval and question included) gives nil. A negative or non-finite quiet time counts
    /// as 0. 0 means: asleep now.
    static func sleepDelay(state: CatState, quietMs: Double) -> Double? {
        state == .idle ? max(0, sleepAfterMs - max(0, quietMs.isFinite ? quietMs : 0)) : nil
    }

    /// What an idle cat shows: sleeping once the sleep timer has fired, idle otherwise. Every other state shows itself.
    static func shown(_ state: CatState, asleep: Bool) -> CatState { asleep && state == .idle ? .sleeping : state }

    /// Anything that wakes a sleeping cat. In Playful it wakes with zoomies (see the Playful profile).
    static let wakeEvents = ["hook", "hover", "click"]
    static func wakes(_ kind: String) -> Bool { wakeEvents.contains(kind) }

    /// The collar styles, frozen contract values that Settings stores, in this order: Band and tag, Band, Neckerchief, and Off (the default).
    static let collarStyles = ["tag", "band", "kerchief", "off"]
    /// A stored collar style to a style. An unknown ID, or anything that is not a string, falls back to "off".
    static func collarStyleOf(_ v: Any?) -> String { (v as? String).flatMap { collarStyles.contains($0) ? $0 : nil } ?? "off" }

    /// The colour the big cat wears as its collar: the colour of the agent driving its state, and none when it is idle, asleep or dizzy (those are
    /// the cat's own states, not an agent's) or has no agent. The small cats wear their own agent's colour all the time.
    static func bigCatCollar(colour: String?, state: CatState) -> String? { state == .idle || state == .sleeping || state == .dizzy ? nil : colour }

    /// Tool names that mean "searching" (exact, case-sensitive match on the tool name the hook relay delivers).
    static let searchTools: [String: [String]] = [
        "claude": ["WebSearch", "WebFetch", "Grep", "Glob"],
        "gemini": ["google_web_search", "web_fetch", "grep_search", "search_file_content", "glob"],
        "codex": ["web_search", "grep_files"],
    ]
    private static let searchSet = Set(searchTools.values.flatMap { $0 })
    static func isSearchTool(_ name: String?) -> Bool { name.map { searchSet.contains($0) } ?? false }
    /// The state a tool event puts an agent in: a search tool is searching, any other tool is working.
    static func toolState(_ name: String?) -> CatState { isSearchTool(name) ? .searching : .working }
}
