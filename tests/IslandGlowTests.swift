import Foundation

// The hover glow's rules (IslandGlow.swift): when it is drawn, how the colours turn, and what it is made of.

@main
enum IslandGlowTests {
    static func main() {
        var passed = 0
        func ok(_ cond: Bool, _ name: String) { precondition(cond, name); passed += 1; print("✓ \(name)") }

        ok(IslandGlow.defaultsKey == "island.hoverGlow", "the setting's key is island.hoverGlow")
        ok(IslandGlow.lineWidth == 3, "the bright edge is 3 pt")
        ok(IslandGlow.fade == 0.2, "it fades in and out over 0.2 s")

        // When it is drawn: the switch on, the pointer over the island, an island on screen, no cat drag.
        ok(IslandGlow.isShown(enabled: true, pointerOver: true, islandOnScreen: true, dragging: false), "on, hovered, on screen: drawn")
        ok(!IslandGlow.isShown(enabled: false, pointerOver: true, islandOnScreen: true, dragging: false), "switched off: never drawn")
        ok(!IslandGlow.isShown(enabled: true, pointerOver: false, islandOnScreen: true, dragging: false), "pointer away: not drawn (so no animation, no timeline)")
        ok(!IslandGlow.isShown(enabled: true, pointerOver: true, islandOnScreen: false, dragging: false), "hidden island: not drawn")
        ok(!IslandGlow.isShown(enabled: true, pointerOver: true, islandOnScreen: true, dragging: true), "while the cat's head is dragged: not drawn")

        // The turn: one revolution in secondsPerTurn, always inside 0..<360, still under Reduce Motion.
        ok(IslandGlow.angle(at: 0, reduceMotion: false) == 0, "angle 0 at time 0")
        ok(IslandGlow.angle(at: IslandGlow.secondsPerTurn / 2, reduceMotion: false) == 180, "half a turn is 180 degrees")
        ok(IslandGlow.angle(at: IslandGlow.secondsPerTurn * 3, reduceMotion: false) == 0, "whole turns come back to 0")
        ok(abs(IslandGlow.angle(at: 3.3, reduceMotion: false) - 3.3 / IslandGlow.secondsPerTurn * 360) < 1e-9, "the angle is linear in time")
        for t in stride(from: -50.0, through: 800, by: 7.31) {
            let a = IslandGlow.angle(at: t, reduceMotion: false)
            precondition(a >= 0 && a < 360, "angle \(a) at \(t)")
        }
        ok(true, "the angle stays in 0..<360 for negative and large times")
        ok(IslandGlow.angle(at: 123.4, reduceMotion: true) == 0, "Reduce Motion: a still glow (angle 0 at any time)")
        ok(IslandGlow.angle(at: .nan, reduceMotion: false) == 0 && IslandGlow.angle(at: .infinity, reduceMotion: false) == 0, "a time that is not a number gives 0")
        ok(IslandGlow.framesPerSecond <= 30, "the redraw is at most 30 frames a second")

        print("Island hover glow: \(passed) checks passed")
    }
}
