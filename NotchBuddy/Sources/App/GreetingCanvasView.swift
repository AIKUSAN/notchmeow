import SwiftUI
import QuartzCore

// The launch greeting: a cat version of Greeting v2. The timeline is CatGreeting's (5.74 s in a 640x150 space) and the drawing is
// CatGreetingRenderer's; this view only runs the clock, holds the cat's engine and talks to the island's state machine.

private enum GT {
    /// The animation is done: the state machine is told here (when the pointer is not on the island).
    static let end: Double = 4.60
    /// Where the timeline starts to collapse by itself.
    static let autoLeave: Double = CatGreeting.GT.leave
    static let pop0: Double = CatGreeting.GT2.pop0
    static let badge: Double = CatGreeting.GT.badge
}

struct GreetingCanvasView: View {
    @ObservedObject var state: AppState

    @State private var startDate = Date()
    @State private var tc: Double = .infinity   // collapses only when the FSM fires .greetingInterrupt
    @State private var greetFired = false
    @StateObject private var engine = CatEngine.live()

    // Scheduled works (cancellable)
    @State private var soundWork1: DispatchWorkItem? = nil
    @State private var soundWork2: DispatchWorkItem? = nil
    @State private var doneWork:   DispatchWorkItem? = nil

    var body: some View {
        // At most 60 frames a second like the big cats (BigCatPacing): at a ProMotion display's 120 Hz the island's whole layer was re-rendered twice as often, and the main thread stalled
        // waiting for a surface whenever the WindowServer was busy (a screen recording), which made the cat's slides uneven. The pose is a function of the timeline's date, so the timeline is unchanged.
        TimelineView(.animation(minimumInterval: BigCatPacing.minimumInterval)) { timeline in
            let t = timeline.date.timeIntervalSince(startDate)
            Canvas { context, size in
                let greeting = state.cast.greeting
                engine.useCharacter(greeting.cat)   // the Main cat falls in, in every display mode
                engine.update(dt: CatEngine.frameDelta(now: CACurrentMediaTime(), last: engine.lastTime))
                let end = CatGreeting.Compact(width: Double(state.notchWidth) + 160, height: Double(state.notchHeight), botInset: CatIslandLayout.compactX(state.cast.mode)[0])
                context.withCGContext { cg in
                    CatGreetingRenderer.draw(cg, t: t, leave: tc, engine: engine, end: end, sessions: greeting.sessions, pair: greeting.pair?[1])
                }
            }
            // Fire greetComplete exactly once at T.end (when no hover)
            .onChange(of: !greetFired && t >= GT.end && tc >= GT.autoLeave) { _, trigger in
                if trigger { fireGreetComplete() }
            }
            // The island has folded and the last beat is over: hand over to the island's own cat and mini grid, which fade in as this fades out
            .onChange(of: state.greetingTail && t >= tc + CatGreeting.GT3.end) { _, over in
                if over { withAnimation(.easeInOut(duration: 0.25)) { state.greetingTail = false } }
            }
        }
        .onAppear {
            startDate = Date()
            tc = .infinity
            greetFired = false
            scheduleWorks()
        }
        .onDisappear {
            cancelWorks()
        }
        .onReceive(NotificationCenter.default.publisher(for: .greetingHover)) { _ in
            // Mouse on notch during greeting → hold open (no auto-collapse)
            if tc >= GT.autoLeave { tc = .infinity }
        }
        .onReceive(NotificationCenter.default.publisher(for: .greetingInterrupt)) { _ in
            // Mouse left during greeting → start collapse from current time
            let t = Date().timeIntervalSince(startDate)
            if tc.isInfinite || tc > t { tc = t }
            cancelWorks()   // cancel auto-done timer (FSM already went to .petit)
        }
    }

    private func fireGreetComplete() {
        guard !greetFired else { return }
        greetFired = true
        cancelWorks()
        NotificationCenter.default.post(name: .greetComplete, object: nil)
    }

    private func scheduleWorks() {
        func schedule(_ delay: Double, _ block: @escaping () -> Void) -> DispatchWorkItem {
            let item = DispatchWorkItem(block: block)
            DispatchQueue.main.asyncAfter(deadline: .now() + delay, execute: item)
            return item
        }
        soundWork1 = schedule(GT.pop0)  { SoundEngine.shared.play("greet") }
        soundWork2 = schedule(GT.badge) { SoundEngine.shared.play("blip")  }
        // doneWork is a safety fallback; normal path fires via .onChange
        doneWork = schedule(GT.end + 0.05) { fireGreetComplete() }
    }

    private func cancelWorks() {
        soundWork1?.cancel(); soundWork1 = nil
        soundWork2?.cancel(); soundWork2 = nil
        doneWork?.cancel();   doneWork = nil
    }
}
