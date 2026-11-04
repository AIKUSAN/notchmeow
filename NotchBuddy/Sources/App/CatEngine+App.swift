import Foundation
import QuartzCore

// The app's way into the cat engine: the real clock, the app's own state and emote types, and the sounds. Nothing here is in the
// contract, and the test programs do not compile this file.

extension BotState {
    /// The app's state for a cat state (the two enums have the same cases, with the same raw values).
    init(_ s: CatState) { self = BotState(rawValue: s.rawValue) ?? .working }

    /// What a cat in this state shows: sleeping instead of idle once the sleep timer has fired (`CatRules.shown`).
    func shown(asleep: Bool) -> BotState { BotState(CatRules.shown(CatState(rawValue: rawValue) ?? .idle, asleep: asleep)) }
}

extension CatEngine {
    /// An engine for the app: it reads `CACurrentMediaTime()`, the clock the views use for `dt`, and rolls real dice.
    static func live(_ preset: CatPreset = CatPresets.byID(CatConfig.shared.character), mini: Bool = false) -> CatEngine {
        let e = CatEngine(preset, mini: mini, now: { CACurrentMediaTime() * 1000 })
        e.onSound = { SoundEngine.shared.play($0) }
        return e
    }

    func setState(_ state: BotState, force: Bool = false) {
        if let s = CatState(rawValue: state.rawValue) { setState(s, force: force) }
    }

    /// An emote asked for by the app (a hover, a drop, a finished chat). The triggers are unchanged from before the cats.
    func triggerEmote(_ e: BotEmote) { emote(e.rawValue) }
}
