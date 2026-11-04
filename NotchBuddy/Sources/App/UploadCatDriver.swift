import Foundation

/// Drives the cat in the drop view from the upload sequence's frames. The sequence knows where the cat is and when the file is hovering, dropped and
/// arrived; the cat's engine turns that into the file catch: the mouth opens wide while the file hovers, snaps wider on the drop, and when the file
/// arrives (380 ms later, the length of the contract's flight) the cat gulps with a squash and chews with happy eyes, or, for a refused file, gags
/// and coughs it up as a hairball.
@MainActor
final class UploadCatDriver: ObservableObject {
    let engine: CatEngine
    private var dropped = false
    private var arrived = false
    private var celebrated = false

    init(engine: CatEngine) { self.engine = engine }

    /// Advances the cat one frame for the sequence frame `f`; `name` is the dropped file's name (a refused file wears its extension in its fur).
    /// Call it before drawing the cat.
    func follow(_ f: USFrame, file name: String) {
        // The sequence's look is -1…1 with positive down; the engine's is positive up.
        engine.lookX = f.lookX
        engine.lookY = -f.lookY
        if f.dropped {
            if !dropped { dropped = true; engine.catchDrop() }                                                  // 2. snap wider, the file flies in
            if !arrived && f.t >= USC.T_SUCK_END {
                arrived = true
                if f.refused { engine.catchReject(CatFileRule.label(for: name)) } else { engine.catchArrive() }   // 3. gulp and 4. chew, or gag and cough
            }
            if !f.refused && !celebrated && f.t >= f.progEnd { celebrated = true; engine.emote("happy") }       // the upload is done
        } else {
            if dropped { dropped = false; arrived = false; celebrated = false; engine.catchOpen(false) }       // a new drag started
            engine.catchOpen(f.zoneOver)                                                                        // 1. open wide while the file hovers
        }
        engine.update(dt: CatEngine.frameDelta(now: engine.now() / 1000, last: engine.lastTime))
    }
}
